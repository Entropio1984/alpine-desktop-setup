#!/bin/sh
# ==============================================================================
# Script de configuración post-instalación para entorno de escritorio en Alpine
# Compatible con: ash (BusyBox) - shell por defecto de Alpine Linux
# ==============================================================================

set -eu

LOG_FILE="/var/log/desktop-postinstall.log"

log_info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$1" | tee -a "$LOG_FILE"; }
log_ok()    { printf '\033[1;32m[OK]\033[0m    %s\n' "$1" | tee -a "$LOG_FILE"; }
log_warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$1" | tee -a "$LOG_FILE"; }
log_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" | tee -a "$LOG_FILE"; }

trap 'log_error "Ocurrió un error inesperado. Abortando script."; exit 1' EXIT INT TERM

ask_yes_no() {
    prompt="$1"
    printf '%s [s/N]: ' "$prompt"
    if ! read -r resp; then
        resp=""
    fi
    case "$resp" in
        [sSyY]*) return 0 ;;
        *) return 1 ;;
    esac
}

# Consulta una decision tomada en el menu de casillas del inicio
# (Bloque 29, select_options_menu). $1 es el nombre de la variable
# (p. ej. OPT_CUPS) y $2 la pregunta de respaldo. Si el menu no se pudo
# mostrar (sin terminal interactiva, o sin poder instalar 'dialog'), la
# variable queda vacia y se pregunta como siempre, una por una: el
# respaldo vive aqui, en un solo lugar, en vez de repetirse en cada
# bloque. El nombre de la variable siempre viene del propio script,
# nunca de la entrada del usuario, asi que el 'eval' es seguro.
want() {
    eval "want_val=\${$1:-}"
    case "$want_val" in
        yes) return 0 ;;
        no)  return 1 ;;
        *)   ask_yes_no "$2" ;;
    esac
}

# ------------------------------------------------------------------------------
# BLOQUE 1: Validación de permisos de superusuario
# ------------------------------------------------------------------------------
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Este script debe ejecutarse como root."
        exit 1
    fi
    log_ok "Permisos de superusuario verificados."
}

# ------------------------------------------------------------------------------
# BLOQUE 2: Actualización de repositorios
# ------------------------------------------------------------------------------
update_system() {
    log_info "Actualizando índice de paquetes..."
    apk update || { log_error "Fallo al actualizar apk."; exit 1; }
}

install_pkg() {
    pkg="$1"
    log_info "Instalando: $pkg"
    if apk add --no-cache "$pkg" >/dev/null 2>&1; then
        log_ok "'$pkg' instalado."
    else
        log_warn "Fallo al instalar '$pkg' (puede no existir en tu rama/arquitectura)."
    fi
}

# install_pkgs: instala varios paquetes en UNA sola transaccion de apk
# (rapido: una sola resolucion de dependencias/descarga/bloqueo de base
# de datos, en vez de una por paquete). Si la transaccion en lote falla
# -- por ejemplo, uno de los nombres no existe en esta rama/arquitectura,
# algo que ha pasado varias veces con este script (mesa-vulkan-radeon,
# mesa-dri...) -- cae automaticamente a instalar cada paquete por
# separado con install_pkg, que SI tolera fallos individuales. Asi se
# gana velocidad en el caso normal sin sacrificar la resiliencia.
install_pkgs() {
    log_info "Instalando en lote: $*"
    if apk add --no-cache "$@" >/dev/null 2>&1; then
        for p in "$@"; do
            log_ok "'$p' instalado (lote)."
        done
    else
        log_warn "La instalacion en lote fallo (probablemente algun paquete no existe en tu rama). Reintentando uno por uno..."
        for p in "$@"; do
            install_pkg "$p"
        done
    fi
}

# ensure_hw_tools: garantiza las versiones COMPLETAS de lspci y lsusb.
# CORRECCION: antes se usaba "command -v lsusb || install_pkg usbutils".
# El BusyBox de Alpine trae su propio 'lsusb' (verificado en la
# configuracion de BusyBox de 3.24 y edge; 'lspci' en cambio NO viene en
# BusyBox), y ese lsusb solo muestra codigos numericos ("ID 8087:0024"),
# sin los nombres ("Bluetooth", "802.11"...) que buscan los bloques de
# deteccion de WiFi y Bluetooth por USB. Como 'command -v' lo encontraba,
# usbutils nunca se instalaba y esa deteccion podia fallar en silencio.
# Ahora se pregunta por el PAQUETE, no por el comando.
HW_TOOLS_READY="no"
ensure_hw_tools() {
    [ "$HW_TOOLS_READY" = "yes" ] && return 0
    apk info -e pciutils >/dev/null 2>&1 || install_pkg "pciutils"
    apk info -e usbutils >/dev/null 2>&1 || install_pkg "usbutils"
    # El shell recuerda la ruta de los comandos ya usados; se olvida para
    # que 'lsusb' apunte al recien instalado y no al de BusyBox.
    hash -r 2>/dev/null || true
    HW_TOOLS_READY="yes"
}

# ------------------------------------------------------------------------------
# BLOQUE 3: Distribución de teclado a "latam" (consola + sesión gráfica)
# ------------------------------------------------------------------------------
setup_keyboard_layout() {
    log_info "== Distribución de teclado =="

    if ! want OPT_KEYBOARD "¿Deseas configurar el teclado a distribución latinoamericana (latam)?"; then
        log_info "Se omite la configuración de teclado. Se deja el layout por defecto del sistema/instalación."
        return 0
    fi

    log_info "== Configurando distribución de teclado a 'latam' =="

    if command -v setup-keymap >/dev/null 2>&1; then
        if yes | setup-keymap latam latam >>"$LOG_FILE" 2>&1; then
            log_ok "Teclado de consola (TTY) configurado a 'latam'."
        else
            log_warn "No se pudo configurar el teclado de consola automáticamente. Ejecuta manualmente: setup-keymap latam latam"
        fi
    else
        log_warn "'setup-keymap' no disponible (paquete alpine-conf). Se omite la configuración de consola."
    fi

    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<'EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "latam"
EndSection
EOF
    log_ok "Teclado de sesión gráfica (Xorg) configurado a 'latam' en /etc/X11/xorg.conf.d/00-keyboard.conf"

    # Wayland NO lee /etc/X11/: cada compositor toma la distribucion de
    # teclado de su propia configuracion. Desde Alpine 3.22, Plasma solo
    # tiene sesion Wayland, y GNOME 50 (Alpine 3.24) tambien. Sin estas
    # tres capas, esos escritorios arrancarian con teclado en ingles.
    #
    # 1) Variable XKB_DEFAULT_LAYOUT: la leen KWin (cuando el usuario no
    #    ha elegido distribucion; verificado en el codigo de KWin,
    #    src/xkb.cpp) y los compositores basados en wlroots (sway, labwc,
    #    el de "xfce-wayland"). Va en las variables de sesion de Plasma y
    #    en /etc/profile.d para los demas.
    for kbf in /etc/xdg/plasma-workspace/env/teclado-latam.sh /etc/profile.d/teclado-latam.sh; do
        mkdir -p "${kbf%/*}"
        cat > "$kbf" <<'EOF'
# Generado por desktop-postinstall.sh: teclado latinoamericano en Wayland
# (KWin, sway, labwc). Una distribucion elegida por el usuario en la
# configuracion del escritorio tiene prioridad sobre esta variable.
export XKB_DEFAULT_LAYOUT=latam
EOF
    done

    # 2) Plasma: valor por defecto de sistema en kxkbrc (/etc/xdg). Asi la
    #    distribucion aparece tambien en Preferencias del sistema > Teclado.
    #    La configuracion propia del usuario (~/.config/kxkbrc) manda.
    cat > /etc/xdg/kxkbrc <<'EOF'
[Layout]
LayoutList=latam
Use=true
EOF

    # 3) GNOME: valor por defecto de gsettings (aplica tambien a la pantalla
    #    de inicio de GDM). Sin systemd-localed, GNOME no tiene otra fuente.
    if [ -d /usr/share/glib-2.0/schemas ]; then
        cat > /usr/share/glib-2.0/schemas/90-desktop-postinstall-teclado.gschema.override <<'EOF'
[org.gnome.desktop.input-sources]
sources=[('xkb', 'latam')]
EOF
        if command -v glib-compile-schemas >/dev/null 2>&1; then
            glib-compile-schemas /usr/share/glib-2.0/schemas >>"$LOG_FILE" 2>&1 \
                || log_warn "No se pudieron recompilar los esquemas de GNOME (glib-compile-schemas)."
        fi
    fi
    log_ok "Teclado 'latam' para sesiones Wayland: XKB_DEFAULT_LAYOUT, /etc/xdg/kxkbrc (Plasma) y esquema de GNOME."
}

# ------------------------------------------------------------------------------
# BLOQUE 4: Detección multiparadigma del entorno de escritorio
# ------------------------------------------------------------------------------
DE_XFCE="no"
DE_PLASMA="no"
DE_GNOME="no"
DE_MATE="no"
DE_LXQT="no"

detect_desktop_environment() {
    log_info "== Detectando entorno de escritorio instalado =="

    apk info -e xfce4-session >/dev/null 2>&1 && { DE_XFCE="yes"; log_ok "XFCE detectado."; }

    # Se comprueban ambos nombres: plasma-desktop-meta (metapaquete usado
    # por setup-desktop) y plasma-desktop (paquete real que trae como
    # dependencia). Cubre también instalaciones manuales/no estándar que
    # no pasaron por el metapaquete.
    apk info -e plasma-desktop-meta >/dev/null 2>&1 && { DE_PLASMA="yes"; log_ok "KDE Plasma detectado."; }
    apk info -e plasma-desktop >/dev/null 2>&1 && { DE_PLASMA="yes"; log_ok "KDE Plasma detectado."; }

    apk info -e gnome-shell >/dev/null 2>&1 && { DE_GNOME="yes"; log_ok "GNOME detectado."; }
    apk info -e mate-session-manager >/dev/null 2>&1 && { DE_MATE="yes"; log_ok "MATE detectado."; }
    apk info -e lxqt-session >/dev/null 2>&1 && { DE_LXQT="yes"; log_ok "LXQt detectado."; }

    if [ "$DE_XFCE" = "no" ] && [ "$DE_PLASMA" = "no" ] && [ "$DE_GNOME" = "no" ] && [ "$DE_MATE" = "no" ] && [ "$DE_LXQT" = "no" ]; then
        log_warn "No se detectó un entorno soportado. Se instalarán herramientas genéricas de consola."
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 5: Detección del usuario real del sistema (vía doas/logname)
# ------------------------------------------------------------------------------
TARGET_USER=""
TARGET_HOME=""

detect_target_user() {
    log_info "== Detectando usuario real del sistema =="

    TARGET_USER="${DOAS_USER:-}"
    [ -z "$TARGET_USER" ] && TARGET_USER="$(logname 2>/dev/null || true)"

    if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
        log_warn "No se pudo determinar un usuario estándar vía doas ni logname."
        TARGET_USER=""
        return 0
    fi

    TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)"
    if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
        log_warn "No se pudo determinar el directorio home de '$TARGET_USER'."
        TARGET_HOME=""
        return 0
    fi

    log_ok "Usuario detectado: $TARGET_USER (home: $TARGET_HOME)"
}

# ------------------------------------------------------------------------------
# BLOQUE 6: Applets de red y audio (enrutamiento dinámico según DE)
# ------------------------------------------------------------------------------
# Servidor de audio: PulseAudio o PipeWire.
# En Alpine, "pulseaudio" es tambien un nombre VIRTUAL: lo provee el
# paquete real pulseaudio (prioridad mas alta) y pipewire-pulse. Los dos
# se excluyen entre si (apk instala solo uno). Por eso el script ya no
# fuerza PulseAudio: si el sistema ya tiene un servidor, lo respeta; asi,
# si algun dia Alpine cambia el predeterminado a PipeWire, el script no
# lo revierte.
#   - pipewire-pulse instalado      -> PipeWire.
#   - pulseaudio (real) instalado    -> PulseAudio (hoy, lo que instala
#     setup-desktop con Plasma; PipeWire corre igual al lado, para
#     compartir pantalla, y coordinan el uso de la tarjeta).
#   - ninguno: Plasma o GNOME -> PipeWire (su ecosistema ya lo usa);
#     Xfce, MATE, LXQt o sin escritorio -> PulseAudio.
AUDIO_SERVER=""
choose_audio_server() {
    if apk info -e pipewire-pulse >/dev/null 2>&1; then
        AUDIO_SERVER="pipewire"
    elif apk info -e pulseaudio >/dev/null 2>&1; then
        AUDIO_SERVER="pulseaudio"
    elif [ "$DE_PLASMA" = "yes" ] || [ "$DE_GNOME" = "yes" ]; then
        AUDIO_SERVER="pipewire"
    else
        AUDIO_SERVER="pulseaudio"
    fi
    log_info "Servidor de audio: $AUDIO_SERVER"
}

setup_applets() {
    log_info "== Configurando servicios base de red y audio =="

    install_pkgs networkmanager networkmanager-wifi wpa_supplicant

    choose_audio_server
    if [ "$AUDIO_SERVER" = "pipewire" ]; then
        install_pkgs pipewire wireplumber pipewire-pulse pipewire-alsa
        # Arranque por sesion: el paquete de Alpine trae un lanzador por
        # autoarranque XDG, marcado como obsoleto en favor de los
        # "servicios de usuario" de OpenRC (rc-update -U). Si el lanzador
        # desaparece en una version futura, se avisa como activarlo.
        if [ ! -f /etc/xdg/autostart/pipewire.desktop ]; then
            log_warn "PipeWire ya no trae lanzador automatico en esta version de Alpine."
            log_info "Activalo para tu usuario (una sola vez, sin doas): rc-update -U add pipewire && rc-update -U add wireplumber && rc-update -U add pipewire-pulse"
        fi
    else
        install_pkgs pulseaudio pulseaudio-alsa
    fi

    log_info "Inyectando applets de interfaz específicos..."

    if [ "$DE_XFCE" = "yes" ]; then
        install_pkg "network-manager-applet"
        install_pkg "xfce4-pulseaudio-plugin"
    fi

    if [ "$DE_PLASMA" = "yes" ]; then
        install_pkg "plasma-nm"
        install_pkg "plasma-pa"
    fi

    if [ "$DE_GNOME" = "yes" ]; then
        # GNOME tiene estos controles incrustados en su shell de forma monolítica.
        # Instalamos pavucontrol como mezclador avanzado de respaldo.
        install_pkg "pavucontrol"
    fi

    if [ "$DE_MATE" = "yes" ]; then
        # MATE es altamente compatible con el ecosistema GTK de NM.
        install_pkg "network-manager-applet"
        install_pkg "mate-media"
    fi

    if [ "$DE_LXQT" = "yes" ]; then
        # lxqt-panel YA trae su propio plugin de volumen en la bandeja (no
        # requiere paquete aparte, solo activarlo desde la configuración
        # del panel). nm-applet sigue siendo el estándar de facto para
        # WiFi en LXQt, ya que no hay un applet nativo Qt tan extendido.
        install_pkg "network-manager-applet"
        # pavucontrol-qt es un mezclador detallado complementario (igual
        # que pavucontrol en GNOME), no el widget de bandeja en sí.
        install_pkg "pavucontrol-qt"
    fi

    rc-update add networkmanager default || log_warn "No se pudo agregar 'networkmanager' al runlevel default."

    log_ok "Arquitectura de red y audio acoplada al entorno visual."
}

# ------------------------------------------------------------------------------
# BLOQUE 7: Deteccion de hardware de red inalambrica (PCI + USB)
# ------------------------------------------------------------------------------
# Un adaptador WiFi puede estar conectado por PCI/PCIe (tarjeta interna) o
# por USB (dongle externo). lspci NO ve dispositivos USB, asi que hace
# falta lsusb tambien (paquete usbutils) para no perder adaptadores
# conectados como dongle, que es el caso mas comun cuando alguien
# "conecta" un adaptador WiFi a un equipo ya instalado.
WIFI_INFO=""

detect_wifi_hardware() {
    log_info "== Detectando adaptadores de red inalambrica (PCI + USB) =="

    ensure_hw_tools

    net_pci=""
    net_usb=""

    if command -v lspci >/dev/null 2>&1; then
        net_pci="$(lspci | grep -Ei 'network controller|wireless' || true)"
    fi

    # Filtro afinado: "wireless"/"adapter" solos son demasiado amplios
    # (matchean camaras web, teclados, o el propio hub USB interno de la
    # placa) -- por eso se usan frases mas especificas de un adaptador de
    # red real (802.11, WLAN, Wi-Fi, "wireless network", "network
    # adapter"), evitando el falso positivo masivo del filtro original.
    if command -v lsusb >/dev/null 2>&1; then
        net_usb="$(lsusb | grep -Ei '802\.11|wlan|wi-?fi|wireless network|network adapter' || true)"
    fi

    WIFI_INFO="$net_pci
$net_usb"

    if [ -z "$net_pci" ] && [ -z "$net_usb" ]; then
        log_warn "No se detecto informacion de adaptadores de red (PCI ni USB)."
        return 0
    fi

    log_info "Adaptadores de red detectados:"
    log_info "$WIFI_INFO"
}

# ------------------------------------------------------------------------------
# BLOQUE 8: Firmware de adaptadores WiFi segun fabricante detectado
# ------------------------------------------------------------------------------
# Alpine divide el firmware en decenas de subpaquetes por fabricante
# (linux-firmware-intel, linux-firmware-realtek, linux-firmware-ath9k_htc,
# etc.). Sin el subpaquete correcto, el driver del kernel puede cargar
# pero la tarjeta jamas asocia a una red (o ni siquiera aparece).
# NOTA SOBRE EL FIRMWARE: la instalacion normal de Alpine YA incluye el
# metapaquete "linux-firmware", que depende de todos los subpaquetes de
# fabricante. En ese caso, los subpaquetes que este script instala segun
# el hardware detectado ya estan presentes y 'apk add' simplemente no hace
# nada (sin costo). Solo marcan la diferencia en un sistema adelgazado
# con 'linux-firmware-none', donde falta todo el firmware y este script
# agrega unicamente el del hardware realmente detectado.
install_wifi_firmware() {
    log_info "== Instalando firmware de adaptadores WiFi =="

    if [ -z "$WIFI_INFO" ]; then
        log_warn "Sin informacion de hardware de red; se omite instalacion de firmware especifico."
        return 0
    fi

    matched="no"

    if echo "$WIFI_INFO" | grep -qi "intel"; then
        install_pkgs linux-firmware-intel
        matched="yes"
    fi

    if echo "$WIFI_INFO" | grep -Eqi "realtek|rtl[0-9]"; then
        install_pkgs linux-firmware-realtek linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-rtlwifi linux-firmware-rtl_nic
        matched="yes"
    fi

    if echo "$WIFI_INFO" | grep -Eqi "atheros|qualcomm|qca"; then
        install_pkgs linux-firmware-ath9k_htc linux-firmware-ath10k linux-firmware-ath12k linux-firmware-qca
        matched="yes"
    fi

    if echo "$WIFI_INFO" | grep -Eqi "mediatek|ralink|mt7[0-9]"; then
        install_pkgs linux-firmware-mediatek
        matched="yes"
    fi

    if echo "$WIFI_INFO" | grep -qi "marvell"; then
        install_pkgs linux-firmware-mrvl
        matched="yes"
    fi

    if echo "$WIFI_INFO" | grep -qi "broadcom"; then
        install_pkgs linux-firmware-brcm
        matched="yes"
    fi

    if [ "$matched" = "no" ]; then
        log_warn "No se identifico el fabricante del adaptador WiFi por nombre."
        log_info "Instalando un conjunto amplio de firmware como red de seguridad..."
        install_pkgs linux-firmware-intel linux-firmware-realtek linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-ath9k_htc linux-firmware-ath10k linux-firmware-mediatek linux-firmware-mrvl linux-firmware-brcm
    fi

    log_ok "Firmware de WiFi instalado."
    log_info "Si el adaptador se conecto despues de arrancar, puede requerir 'modprobe -r <driver> && modprobe <driver>' o reiniciar para que tome el firmware nuevo."
}

# ------------------------------------------------------------------------------
# BLOQUE 9: Deteccion de hardware Bluetooth (PCI + USB)
# ------------------------------------------------------------------------------
# La inmensa mayoria de adaptadores Bluetooth en laptops estan cableados
# internamente por USB (a menudo combinados con el chip WiFi en el mismo
# controlador fisico), por lo que lsusb es la fuente principal aqui.
# Tambien se revisa lspci por si el adaptador aparece como dispositivo
# PCI independiente (menos comun, pero ocurre en algunos equipos).
BT_INFO=""

detect_bluetooth_hardware() {
    log_info "== Detectando hardware Bluetooth (PCI + USB) =="

    ensure_hw_tools

    bt_pci=""
    bt_usb=""

    if command -v lspci >/dev/null 2>&1; then
        bt_pci="$(lspci | grep -Ei 'bluetooth' || true)"
    fi

    if command -v lsusb >/dev/null 2>&1; then
        bt_usb="$(lsusb | grep -Ei 'bluetooth' || true)"
    fi

    BT_INFO="$bt_pci
$bt_usb"

    if [ -z "$bt_pci" ] && [ -z "$bt_usb" ]; then
        log_info "No se detecto ningun adaptador Bluetooth (PCI ni USB)."
        return 0
    fi

    log_info "Adaptador(es) Bluetooth detectado(s):"
    log_info "$BT_INFO"
}

# ------------------------------------------------------------------------------
# BLOQUE 10: Pila Bluetooth (bluez) y firmware por fabricante
# ------------------------------------------------------------------------------
# NOTA: a diferencia de lo que sugiere el nombre, NO existe un paquete
# generico "linux-firmware-bluetooth" en Alpine -- el firmware de
# Bluetooth esta fragmentado por fabricante igual que el de WiFi
# (linux-firmware-rtl_bt para Realtek, linux-firmware-ar3k para
# Atheros/Qualcomm, linux-firmware-brcm cubre WiFi+Bluetooth combinado
# de Broadcom, linux-firmware-intel cubre combos Intel). Muchos chips
# combo WiFi+Bluetooth ya quedan cubiertos por el firmware que instalo
# el Bloque 8; aqui solo se completa lo especifico de Bluetooth que
# pueda faltar.
install_bluetooth() {
    if [ -z "$BT_INFO" ]; then
        return 0
    fi

    log_info "== Instalando pila Bluetooth (bluez) =="

    # El "puente" que enruta el perfil A2DP hacia el servidor de audio:
    # sin el, bluez permite emparejar el dispositivo pero los
    # audifonos/altavoces Bluetooth no emiten sonido. Depende del servidor
    # elegido en el Bloque 6.
    if [ "$AUDIO_SERVER" = "pipewire" ]; then
        install_pkgs bluez bluez-openrc pipewire-spa-bluez
    else
        install_pkgs bluez bluez-openrc pulseaudio-bluez
    fi

    if echo "$BT_INFO" | grep -Eqi "realtek|rtl[0-9]"; then
        install_pkgs linux-firmware-rtl_bt
    fi

    if echo "$BT_INFO" | grep -Eqi "atheros|qualcomm|qca"; then
        install_pkgs linux-firmware-ar3k
    fi

    if echo "$BT_INFO" | grep -qi "broadcom"; then
        install_pkgs linux-firmware-brcm
    fi

    if echo "$BT_INFO" | grep -qi "intel"; then
        install_pkgs linux-firmware-intel
    fi

    rc-update add bluetooth default || log_warn "No se pudo agregar 'bluetooth' al runlevel default."

    log_ok "Soporte Bluetooth instalado y activado (servicio OpenRC: bluetooth)."
}

# ------------------------------------------------------------------------------
# BLOQUE 11: Detección de hardware gráfico (soporta configuraciones híbridas)
# ------------------------------------------------------------------------------
GPU_HAS_INTEL="no"
GPU_HAS_AMD="no"
GPU_HAS_NVIDIA="no"
GPU_HAS_VIRTUAL="no"
GPU_COUNT=0
NVIDIA_COUNT=0
NVIDIA_SLOT=""      # ranura PCI de la NVIDIA, p. ej. 0000:01:00.0
PRIMARY_SLOT=""     # GPU que el firmware uso al arrancar (boot_vga)
PRIMARY_VENDOR=""
IS_LAPTOP="no"
OPTIMUS_LAPTOP="no" # portatil con grafica integrada + una NVIDIA

detect_hardware() {
    log_info "== Detectando hardware gráfico =="
    ensure_hw_tools

    if command -v lspci >/dev/null 2>&1; then
        log_info "Componentes PCI detectados:"
        lspci 2>/dev/null | tee -a "$LOG_FILE" || true
    fi

    # La clasificacion se hace leyendo /sys (clase y fabricante en
    # numeros), no el texto de lspci: funciona aunque lspci falte o sea
    # la version reducida de BusyBox, y no depende de como cada version
    # de la base de datos de nombres describa el dispositivo.
    #   Clases: 0x0300 VGA, 0x0302 3D (tipico de la NVIDIA en Optimus),
    #           0x0380 otro controlador de pantalla.
    #   Fabricantes: 0x8086 Intel, 0x1002 AMD, 0x10de NVIDIA; virtuales:
    #           0x1af4 virtio, 0x15ad VMware, 0x80ee VirtualBox,
    #           0x1b36 QXL, 0x1234 QEMU.
    for dev in /sys/bus/pci/devices/*; do
        [ -r "$dev/class" ] || continue
        case "$(cat "$dev/class")" in
            0x0300*|0x0302*|0x0380*) ;;
            *) continue ;;
        esac
        slot="${dev##*/}"
        vendor="$(cat "$dev/vendor" 2>/dev/null || echo desconocido)"
        boot_vga="$(cat "$dev/boot_vga" 2>/dev/null || echo 0)"
        GPU_COUNT=$((GPU_COUNT + 1))
        case "$vendor" in
            0x8086) GPU_HAS_INTEL="yes" ;;
            0x1002) GPU_HAS_AMD="yes" ;;
            0x10de) GPU_HAS_NVIDIA="yes"; NVIDIA_COUNT=$((NVIDIA_COUNT + 1)); NVIDIA_SLOT="$slot" ;;
            0x1af4|0x15ad|0x80ee|0x1b36|0x1234) GPU_HAS_VIRTUAL="yes" ;;
        esac
        if [ "$boot_vga" = "1" ]; then
            PRIMARY_SLOT="$slot"
            PRIMARY_VENDOR="$vendor"
        fi
        log_info "GPU en $slot: fabricante $vendor, dispositivo $(cat "$dev/device" 2>/dev/null)$( [ "$boot_vga" = "1" ] && echo ' (principal al arrancar)')"
    done

    if [ "$GPU_COUNT" -eq 0 ]; then
        log_warn "No se detectó ningún controlador de video."
        return 0
    fi

    # Portatil: tipo de chasis del firmware (8 portatil, 9 laptop,
    # 10 notebook, 14 sub-notebook, 30-32 tableta/convertible) o, como
    # respaldo, la presencia de una bateria.
    case "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" in
        8|9|10|11|14|30|31|32) IS_LAPTOP="yes" ;;
    esac
    if [ "$IS_LAPTOP" = "no" ] && ls -d /sys/class/power_supply/BAT* >/dev/null 2>&1; then
        IS_LAPTOP="yes"
    fi

    # Optimus: portatil donde la pantalla la maneja la grafica integrada
    # (Intel o AMD, la principal al arrancar) y hay UNA NVIDIA adicional.
    # Si la principal fuera la NVIDIA (escritorios, o portatiles con
    # conmutador en modo "solo dedicada"), el modo de ahorro no aplica:
    # apagarla dejaria sin imagen las salidas conectadas a ella.
    if [ "$IS_LAPTOP" = "yes" ] && [ "$NVIDIA_COUNT" -eq 1 ]; then
        case "$PRIMARY_VENDOR" in
            0x8086|0x1002) OPTIMUS_LAPTOP="yes" ;;
        esac
    fi

    log_ok "Resumen GPU -> Intel:$GPU_HAS_INTEL AMD:$GPU_HAS_AMD NVIDIA:$GPU_HAS_NVIDIA Virtual:$GPU_HAS_VIRTUAL (adaptadores: $GPU_COUNT; portatil: $IS_LAPTOP; Optimus: $OPTIMUS_LAPTOP)"

    # Adaptadores de video por USB (docks para multiples monitores) no
    # aparecen en lspci. DisplayLink es el fabricante mas comun. NO se
    # intenta instalar nada automaticamente: "evdi" (el driver de kernel
    # que necesitan) no esta empaquetado en Alpine -- en las distros que
    # lo ofrecen requiere compilarse vía DKMS contra el kernel en uso, un
    # flujo que Alpine no tiene estandarizado. Solo se advierte.
    if command -v lsusb >/dev/null 2>&1 && lsusb | grep -qi "displaylink"; then
        log_warn "Adaptador de video USB DisplayLink detectado."
        log_info "DisplayLink requiere el modulo de kernel 'evdi', que NO esta empaquetado en Alpine (solo existe vía DKMS en otras distros). No se instala nada automaticamente; sera necesario compilarlo manualmente si se necesita soporte multi-monitor por USB."
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 12: Firmware y controladores de video (NVIDIA: modos ahorro Optimus, seguro y activo)
# ------------------------------------------------------------------------------
install_drivers() {
    log_info "== Instalando firmware y controladores =="

    # El script no pide el metapaquete "linux-firmware" (depende de todos
    # los subpaquetes de fabricante); solo pide los del hardware detectado.
    # Ver la NOTA SOBRE EL FIRMWARE del Bloque 8: en una instalacion
    # normal de Alpine ese metapaquete ya viene incluido.
    install_pkgs mesa-dri-gallium mesa-gl mesa-egl

    if [ "$GPU_HAS_INTEL" = "yes" ]; then
        log_info "Instalando firmware Intel..."
        # libva-intel-driver: GPU Intel antiguas (hasta ~2016).
        # intel-media-driver: GPU Intel de Broadwell (2014) en adelante.
        # Se instalan ambos: libva prueba el moderno y, si la GPU no lo
        # soporta, recurre al antiguo.
        install_pkgs linux-firmware-i915 mesa-vulkan-intel libva-intel-driver intel-media-driver libva-utils
    fi

    if [ "$GPU_HAS_AMD" = "yes" ]; then
        log_info "Instalando firmware y Vulkan para AMD/Radeon..."
        install_pkgs linux-firmware-amdgpu linux-firmware-radeon mesa-vulkan-ati vulkan-loader mesa-va-gallium libva-utils
    fi

    if [ "$GPU_HAS_VIRTUAL" = "yes" ]; then
        log_info "Entorno virtualizado detectado. Instalando utilidades QEMU/KVM/VirtualBox..."
        install_pkgs xf86-video-vmware xf86-video-qxl spice-vdagent
        rc-update add spice-vdagentd default || log_warn "Fallo al habilitar spice-vdagentd."
    fi

    if [ "$GPU_HAS_NVIDIA" = "yes" ]; then
        log_info "Instalando soporte NVIDIA (driver abierto Nouveau, vía Gallium)..."
        install_pkgs linux-firmware-nvidia

        nvidia_mode=""
        if [ "$OPTIMUS_LAPTOP" = "yes" ]; then
            log_info "Portatil con graficos hibridos (Optimus): pantalla en la grafica integrada ($PRIMARY_SLOT), NVIDIA en $NVIDIA_SLOT."
            nvidia_mode="${OPT_NVIDIA_MODE:-}"
            if [ -z "$nvidia_mode" ]; then
                log_info "Opciones: apagar la NVIDIA y usar la integrada (ahorro, recomendado) / bloquearla por completo / dejarla activa."
                if ask_yes_no "¿Apagar la NVIDIA cuando no se usa y dejar escritorio y video en la grafica integrada (recomendado)?"; then
                    nvidia_mode="optimus"
                elif ask_yes_no "¿Bloquear la NVIDIA por completo (modo seguro)?"; then
                    nvidia_mode="safe"
                else
                    nvidia_mode="active"
                fi
            fi
        else
            if [ "$GPU_COUNT" -gt 1 ]; then
                log_warn "Varias GPU ($GPU_COUNT adaptadores), pero no es un portatil Optimus (o la NVIDIA es la principal)."
            else
                log_warn "Se detectó NVIDIA como única tarjeta gráfica (sin gráfica integrada de respaldo)."
            fi
            log_warn "En tarjetas NVIDIA antiguas (Tesla/Fermi/Kepler), Nouveau puede causar pantalla negra o cuelgues."
            log_info "Opción 's': bloquea el módulo nouveau y usa la GPU restante (o la imagen básica del firmware). Modo seguro."
            log_info "Opción 'n': deja Nouveau activo con aceleración 3D normal en la NVIDIA."
            if want OPT_NVIDIA_SAFE "¿Bloquear la NVIDIA y usar solo la GPU restante (modo seguro)?"; then
                nvidia_mode="safe"
            else
                nvidia_mode="active"
            fi
        fi

        case "$nvidia_mode" in
            optimus) nvidia_apply_optimus ;;
            safe)    nvidia_apply_safe ;;
            *)
                nvidia_clean_modes
                log_info "Se mantiene Nouveau activo sin restricciones (NVIDIA con aceleración 3D normal)."
                ;;
        esac
        if [ "$INITRAMFS_DIRTY" = "yes" ]; then
            regen_initramfs
        fi
    fi

    if [ "$GPU_HAS_INTEL" = "no" ] && [ "$GPU_HAS_AMD" = "no" ] && [ "$GPU_HAS_NVIDIA" = "no" ] && [ "$GPU_HAS_VIRTUAL" = "no" ]; then
        log_warn "GPU no identificada. mesa-dri-gallium ya cubre software rendering (llvmpipe) de respaldo."
    fi

    check_vaapi
    log_ok "Instalación de firmware y controladores finalizada."
}

# --- Modos de la NVIDIA --------------------------------------------------------
# Cada modo empieza borrando los archivos de los otros (nvidia_clean_modes),
# asi que volver a correr el script y elegir otro modo cambia de verdad la
# configuracion en vez de mezclar restos de la anterior.
NV_BLACKLIST="/etc/modprobe.d/blacklist-nouveau.conf"
NV_XORG_SAFE="/etc/X11/xorg.conf.d/20-nouveau-safe.conf"   # de la version anterior del modo seguro
NV_XORG_IGPU="/etc/X11/xorg.conf.d/20-gpu-integrada.conf"
NV_LOCAL="/etc/local.d/nvidia-optimus.start"
NV_ENV_PLASMA="/etc/xdg/plasma-workspace/env/gpu-integrada.sh"
NV_ENV_PROFILE="/etc/profile.d/gpu-integrada.sh"
INITRAMFS_DIRTY="no"

nvidia_clean_modes() {
    for f in "$NV_BLACKLIST" "$NV_XORG_SAFE" "$NV_XORG_IGPU" "$NV_LOCAL" "$NV_ENV_PLASMA" "$NV_ENV_PROFILE"; do
        if [ -e "$f" ]; then
            if [ "$f" = "$NV_BLACKLIST" ]; then
                INITRAMFS_DIRTY="yes"
            fi
            rm -f "$f"
            log_info "Eliminado (configuracion NVIDIA anterior): $f"
        fi
    done
}

# Modo seguro: bloquea el modulo nouveau en el kernel.
# CORRECCION: la version anterior escribia ademas 20-nouveau-safe.conf, una
# seccion "Device" de Xorg con Driver "nouveau" y NoAccel, SIN indicar a que
# tarjeta aplicaba. Esa combinacion se contradice: con el modulo bloqueado,
# el driver nouveau de Xorg no puede funcionar, y como la seccion no tenia
# BusID, Xorg la aplicaba a la tarjeta principal -- en un portatil Optimus,
# la Intel -- intentando manejarla con el driver de NVIDIA. Es una causa
# probable de la "pantalla negra persistente" registrada en el README (en
# Wayland no se nota, porque Wayland no lee esos archivos). Ahora solo se
# bloquea el modulo, y Xorg detecta por si mismo la grafica que queda.
nvidia_apply_safe() {
    nvidia_clean_modes
    mkdir -p /etc/modprobe.d
    cat > "$NV_BLACKLIST" <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
    INITRAMFS_DIRTY="yes"
    log_ok "Modo seguro aplicado: $NV_BLACKLIST"
    log_info "La NVIDIA quedara sin driver. Ojo: sin driver tampoco se apaga y sigue consumiendo energia."
    log_info "Para revertir: borra ese archivo, ejecuta 'mkinitfs <version-del-kernel>' y reinicia."
}

# Modo ahorro (portatiles Optimus): nouveau se carga para poder APAGAR la
# NVIDIA (solo nouveau sabe hacer la llamada al firmware que la apaga), y
# el escritorio y el video se mantienen en la grafica integrada para que
# nada la despierte. Probado en un ASUS K53SV (Intel HD 3000 + GT 540M,
# Fermi) con Plasma en Wayland: la NVIDIA queda en D3cold (sin corriente).
# Tres obstaculos encontrados en esas pruebas, y como se resuelven:
#   1. KWin, Firefox y otros programas abren todas las GPU que encuentran.
#      -> Variables de sesion KWIN_DRM_DEVICES y MOZ_DRM_DEVICE apuntando a
#         la integrada; en Xorg, AutoAddGPU desactivado.
#   2. La funcion de audio HDMI de la NVIDIA quedaba activa y mantenia
#      despierta a la grafica. Las salidas de video del portatil estan en
#      la integrada, asi que ese audio no sirve para nada.
#      -> Se desvincula de su driver al arrancar.
#   3. nouveau detectaba una pantalla "fantasma" en su salida VGA analogica
#      (que en un portatil Optimus no esta cableada) y la mantenia
#      encendida con una consola de texto.
#      -> Se desconectan al arrancar las salidas ANALOGICAS de la NVIDIA
#         (VGA/TV) que figuren como conectadas. Las digitales no se tocan.
nvidia_apply_optimus() {
    nvidia_clean_modes
    aud_slot="${NVIDIA_SLOT%.*}.1"

    # 1) Script de arranque (servicio 'local' de OpenRC).
    mkdir -p /etc/local.d
    {
        printf '#!/bin/sh\n'
        printf '# Generado por desktop-postinstall.sh (modo ahorro para portatiles Optimus).\n'
        printf '# Permite que nouveau apague la NVIDIA cuando no se usa.\n'
        printf 'GPU=%s\n' "$NVIDIA_SLOT"
        printf 'AUD=%s\n' "$aud_slot"
        cat <<'EOF'

# Soltar el audio HDMI de la NVIDIA: mientras siga activo, la grafica no
# puede apagarse. Las salidas de video estan en la grafica integrada.
if [ -e "/sys/bus/pci/drivers/snd_hda_intel/$AUD" ]; then
    echo "$AUD" > /sys/bus/pci/drivers/snd_hda_intel/unbind 2>/dev/null
fi

# Esperar a que nouveau registre la tarjeta (hasta 15 s).
i=0
while ! ls -d /sys/bus/pci/devices/"$GPU"/drm/card* >/dev/null 2>&1 && [ "$i" -lt 15 ]; do
    sleep 1
    i=$((i + 1))
done

# Desconectar salidas analogicas "fantasma" (VGA/TV) que nouveau cree
# conectadas: mientras haya una, mantiene la tarjeta encendida.
for c in /sys/bus/pci/devices/"$GPU"/drm/card*/card*-*; do
    [ -f "$c/status" ] || continue
    case "${c##*/}" in
        *-VGA-*|*-TV-*|*-SVIDEO-*|*-Composite-*|*-Component-*) ;;
        *) continue ;;
    esac
    if [ "$(cat "$c/status")" = "connected" ]; then
        echo off > "$c/status"
    fi
done
exit 0
EOF
    } > "$NV_LOCAL"
    chmod +x "$NV_LOCAL"
    rc-update add local default >/dev/null 2>&1 || log_warn "No se pudo habilitar el servicio 'local' de OpenRC."
    log_ok "Script de arranque creado: $NV_LOCAL (servicio 'local' habilitado)."

    # 2) Variables de sesion: escritorio y video en la integrada. El numero
    #    de dispositivo (card0, card1...) se busca en cada inicio de sesion a
    #    partir de la ranura PCI fija, porque puede cambiar entre arranques.
    mkdir -p "${NV_ENV_PLASMA%/*}" /etc/profile.d
    for envf in "$NV_ENV_PLASMA" "$NV_ENV_PROFILE"; do
        {
            printf '# Generado por desktop-postinstall.sh (modo ahorro para portatiles Optimus).\n'
            printf '# Deja el escritorio (KWin) y el video de Firefox en la grafica integrada\n'
            printf '# para que ningun programa despierte a la NVIDIA.\n'
            printf '_igpu=/sys/bus/pci/devices/%s/drm\n' "$PRIMARY_SLOT"
            cat <<'EOF'
for _p in "$_igpu"/card*; do [ -e "$_p" ] && export KWIN_DRM_DEVICES="/dev/dri/${_p##*/}"; done
for _p in "$_igpu"/renderD*; do [ -e "$_p" ] && export MOZ_DRM_DEVICE="/dev/dri/${_p##*/}"; done
unset _igpu _p
EOF
        } > "$envf"
    done
    log_ok "Variables de sesion: $NV_ENV_PLASMA (Plasma) y $NV_ENV_PROFILE (demas sesiones)."

    # 3) Xorg: que no agregue la NVIDIA como GPU secundaria. No afecta a
    #    sesiones Wayland ni a Xwayland (Plasma solo tiene sesion Wayland en
    #    Alpine desde 3.22), pero sigue sirviendo para la pantalla de inicio
    #    de SDDM, que en Alpine corre sobre Xorg por defecto, y para Xfce,
    #    MATE y LXQt.
    mkdir -p /etc/X11/xorg.conf.d
    cat > "$NV_XORG_IGPU" <<'EOF'
# Generado por desktop-postinstall.sh (modo ahorro para portatiles Optimus).
# Xorg usa solo la grafica principal (la integrada) y no abre la NVIDIA.
Section "ServerFlags"
    Option "AutoAddGPU" "off"
EndSection
EOF
    log_ok "Xorg limitado a la grafica principal: $NV_XORG_IGPU"
    log_warn "La parte de Xorg (pantalla de inicio de SDDM, Xfce, MATE, LXQt) aun no se ha probado en un equipo real."

    log_info "Despues de reiniciar, verifica que la NVIDIA quedo apagada (debe decir D3cold):"
    log_info "  cat /sys/bus/pci/devices/$NVIDIA_SLOT/power_state"
    log_info "Limite: si algun puerto de video del portatil estuviera cableado a la NVIDIA, no daria imagen en este modo (en la mayoria de portatiles Optimus todos van a la integrada)."
}

# Regenera el initramfs de cada kernel instalado, para que el cambio en el
# bloqueo de nouveau aplique desde las primeras etapas del arranque.
regen_initramfs() {
    if ! command -v mkinitfs >/dev/null 2>&1; then
        log_warn "mkinitfs no disponible; no se regenero el initramfs."
        return 0
    fi
    for kdir in /lib/modules/*; do
        [ -d "$kdir/kernel" ] || continue
        kver="${kdir##*/}"
        if mkinitfs "$kver" >>"$LOG_FILE" 2>&1; then
            log_ok "initramfs regenerado para el kernel $kver."
        else
            log_warn "No se pudo regenerar el initramfs de $kver. Ejecuta manualmente: mkinitfs $kver"
        fi
    done
    INITRAMFS_DIRTY="no"
}

# Comprueba que la decodificacion de video por hardware (VA-API) responde
# en la grafica principal y lo deja en el log. Solo informa, no cambia
# nada. Se consulta el dispositivo de esa grafica por su ranura PCI (y no
# "el primero" de /dev/dri), porque en equipos hibridos el primero puede
# ser la NVIDIA: justo eso le paso a Firefox en las pruebas del K53SV.
check_vaapi() {
    command -v vainfo >/dev/null 2>&1 || return 0
    [ -n "$PRIMARY_SLOT" ] || return 0
    [ "$GPU_HAS_VIRTUAL" = "yes" ] && return 0
    render=""
    for r in /sys/bus/pci/devices/"$PRIMARY_SLOT"/drm/renderD*; do
        [ -e "$r" ] && render="/dev/dri/${r##*/}"
    done
    if [ -z "$render" ]; then
        log_info "VA-API: la grafica principal aun no tiene dispositivo de video; verificalo tras reiniciar con: vainfo"
        return 0
    fi
    va_out="$(vainfo --display drm --device "$render" 2>&1 || true)"
    va_drv="$(printf '%s\n' "$va_out" | grep -m1 'Driver version' | sed 's/.*Driver version: *//' || true)"
    if printf '%s\n' "$va_out" | grep -q 'VAProfileH264'; then
        log_ok "VA-API funciona en la grafica principal (${va_drv:-driver desconocido}): H.264 se decodifica por hardware."
    elif printf '%s\n' "$va_out" | grep -q 'VAProfile'; then
        log_ok "VA-API funciona en la grafica principal (${va_drv:-driver desconocido}), pero sin H.264."
    else
        log_warn "VA-API no respondio en $render: el video se decodificara con el procesador. Revisa con: vainfo --display drm --device $render"
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 13: Dispositivos sin controlador y capas de compatibilidad
# ------------------------------------------------------------------------------
# Hasta aqui el script instalo firmware para el hardware que reconocio.
# Este bloque cierra el ciclo preguntando algo distinto: ¿quedo algun
# dispositivo SIN ningun driver del kernel enlazado? Ese es justamente
# el sintoma de hardware que solo funciona con controladores propietarios
# o fuera del arbol del kernel.
#
# En Alpine hay DOS caminos, y no son intercambiables:
#
#   1. Modulos de KERNEL (NVIDIA .ko, broadcom "wl", varios Realtek USB):
#      se manejan con AKMS (Alpine Kernel Module Support), el equivalente
#      oficial de DKMS: compila el modulo desde fuente y lo RECONSTRUYE
#      automaticamente en cada actualizacion de kernel. Alpine empaqueta
#      varios de estos como paquetes "*-src" (rtl8812au-src,
#      rtl88x2bu-src, rtw89-src...), casi todos en el repositorio
#      "testing", que NO viene habilitado por defecto.
#
#   2. Binarios de ESPACIO DE USUARIO compilados contra glibc (plugins de
#      impresora, DRM Widevine): se manejan con "gcompat", una capa de
#      compatibilidad glibc sobre musl. gcompat NO sirve para modulos de
#      kernel: son mundos distintos.
#
# El script NO instala automaticamente modulos propietarios ni habilita
# "testing" por su cuenta: habilitar un repositorio inestable a nivel de
# sistema puede arrastrar paquetes rotos al resto de la instalacion, y
# compilar un modulo equivocado puede dejar el equipo sin red o sin
# video. Se reporta el diagnostico y se deja la decision al usuario.
check_unclaimed_devices() {
    log_info "== Verificando dispositivos sin controlador cargado =="

    if ! command -v lspci >/dev/null 2>&1; then
        log_warn "'lspci' no disponible; se omite esta verificacion."
        return 0
    fi

    # "lspci -k" agrega la linea "Kernel driver in use:" a cada
    # dispositivo que SI tiene driver enlazado. Se listan los que no la
    # tienen, filtrando a las clases que nos importan (red, video,
    # audio): muchos dispositivos como los host bridges no llevan driver
    # y eso es completamente normal, no un problema.
    unclaimed="$(lspci -k 2>/dev/null | awk '
        /^[0-9a-f][0-9a-f]:/ {
            if (dev != "" && claimed == 0 && dev ~ /Network|Ethernet|VGA|3D controller|Audio device|Wireless/) print dev
            dev = $0; claimed = 0; next
        }
        /Kernel driver in use:/ { claimed = 1 }
        END {
            if (dev != "" && claimed == 0 && dev ~ /Network|Ethernet|VGA|3D controller|Audio device|Wireless/) print dev
        }
    ' || true)"

    if [ -z "$unclaimed" ]; then
        log_ok "Todos los dispositivos de red, video y audio tienen un controlador del kernel enlazado."
    else
        log_warn "Los siguientes dispositivos NO tienen ningun controlador del kernel enlazado:"
        log_warn "$unclaimed"
        log_info "Esto suele indicar hardware que requiere un controlador propietario o fuera del arbol del kernel."
        log_info "Camino recomendado en Alpine: AKMS (equivalente oficial de DKMS), que compila el modulo y lo reconstruye solo en cada actualizacion de kernel."
        log_info "  1) apk add akms linux-lts-dev linux-headers"
        log_info "  2) Busca si existe un paquete de fuentes para tu chip: apk search -- -src | grep -i <tu_chip>"
        log_info "  3) Varios viven en el repositorio 'testing' (no habilitado por defecto). Se instalan con la sintaxis pkg@testing tras agregar el repo con etiqueta, en vez de habilitar 'testing' para todo el sistema."
        log_info "Nota: los drivers NVIDIA propietarios no estan disponibles en Alpine por la incompatibilidad con musl libc; para GPU NVIDIA la unica via es nouveau."
    fi

    # gcompat: util para binarios de espacio de usuario compilados contra
    # glibc (plugins de impresoras HP, DRM Widevine de Netflix, etc.).
    # No tiene relacion con los modulos de kernel de arriba.
    if want OPT_GCOMPAT "¿Deseas instalar 'gcompat' (capa de compatibilidad glibc para programas propietarios de espacio de usuario, p.ej. plugins de impresora o DRM de video)?"; then
        install_pkgs gcompat
        log_ok "gcompat instalado. Los binarios compilados contra glibc pueden ejecutarse normalmente."
    else
        log_info "Se omite gcompat."
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 14: Detección de CPU y microcódigo
# ------------------------------------------------------------------------------
CPU_VENDOR=""

detect_cpu() {
    log_info "== Detectando fabricante de CPU =="
    if grep -qi "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
        CPU_VENDOR="intel"
    elif grep -qi "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
        CPU_VENDOR="amd"
    else
        CPU_VENDOR="desconocido"
    fi
    log_ok "CPU clasificada como: $CPU_VENDOR"

    # Nivel de microarquitectura x86-64 (v1..v4). SOLO INFORMATIVO: la
    # optimizacion por nivel (lo que hace CachyOS) ocurre al COMPILAR los
    # paquetes, no despues de instalarlos. Alpine distribuye un unico
    # juego de paquetes x86_64 para el nivel base, asi que este dato no
    # cambia nada de lo que se instala; sirve para saber que esperar.
    # Se lee /proc/cpuinfo porque el metodo habitual
    # (/lib/ld-linux-x86-64.so.2 --help) es propio de glibc y no existe
    # en musl.
    if [ "$(uname -m)" = "x86_64" ]; then
        CPU_FLAGS=" $(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null | cut -d: -f2) "
        CPU_LEVEL="x86-64-v1"
        cpu_has_flags cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3 && CPU_LEVEL="x86-64-v2"
        [ "$CPU_LEVEL" = "x86-64-v2" ] && cpu_has_flags avx avx2 bmi1 bmi2 f16c fma abm movbe xsave && CPU_LEVEL="x86-64-v3"
        [ "$CPU_LEVEL" = "x86-64-v3" ] && cpu_has_flags avx512f avx512bw avx512cd avx512dq avx512vl && CPU_LEVEL="x86-64-v4"
        log_info "Nivel de microarquitectura detectado: $CPU_LEVEL (informativo; Alpine usa paquetes compilados para el nivel base)."
    fi
}

# Devuelve 0 si TODOS los flags pedidos estan en $CPU_FLAGS. Usa 'case'
# (coincidencia de patrones del propio shell) en vez de invocar grep por
# cada flag.
cpu_has_flags() {
    for f in "$@"; do
        case "$CPU_FLAGS" in
            *" $f "*) ;;
            *) return 1 ;;
        esac
    done
    return 0
}

install_microcode() {
    log_info "== Instalando microcódigo de CPU =="
    case "$CPU_VENDOR" in
        intel)
            install_pkg "intel-ucode"
            ;;
        amd)
            # CORRECCION: una version anterior afirmaba que 'amd-ucode' no
            # existia en Alpine e instalaba linux-firmware-amd en su lugar.
            # Eso venia de un hilo antiguo de la lista de desarrollo, de
            # cuando el paquete efectivamente faltaba. Hoy la wiki oficial
            # (wiki.alpinelinux.org/wiki/CPU_Microcode) lo documenta, y
            # las imagenes oficiales de Alpine ya lo incluyen.
            install_pkg "amd-ucode"
            ;;
        *)
            log_warn "Fabricante de CPU no identificado. Se omite instalación de microcódigo."
            return 0
            ;;
    esac
    # No hace falta ejecutar update-extlinux ni update-grub a mano: los
    # paquetes syslinux y grub de Alpine traen un "trigger" que apk ejecuta
    # cada vez que cambia algo en /boot (y el microcodigo se instala en
    # /boot/*-ucode.img), y update-extlinux agrega esa imagen a la linea
    # INITRD por su cuenta. Ejecutarlo a mano seria peor: ignoraria
    # disable_trigger=1 de /etc/update-extlinux.conf y reescribiria un
    # extlinux.conf editado a mano.
    # Lo que si se hace es COMPROBAR el resultado, para avisar en el caso
    # en que el trigger esta desactivado.
    ucode_img="intel-ucode.img"
    [ "$CPU_VENDOR" = "amd" ] && ucode_img="amd-ucode.img"
    boot_cfg=""
    for f in /boot/extlinux.conf /boot/grub/grub.cfg; do
        if [ -f "$f" ]; then
            boot_cfg="$f"
            break
        fi
    done
    if [ ! -f "/boot/$ucode_img" ]; then
        log_warn "No se encontro /boot/$ucode_img: el paquete del microcodigo no quedo instalado."
    elif [ -n "$boot_cfg" ] && grep -q "$ucode_img" "$boot_cfg"; then
        log_ok "Microcodigo incluido en el arranque ($boot_cfg). Se cargara en el proximo inicio; verificalo despues con: dmesg | grep -i microcode"
    elif [ -n "$boot_cfg" ]; then
        log_warn "$boot_cfg no menciona $ucode_img. Si desactivaste la actualizacion automatica del cargador (disable_trigger=1), agrega '/boot/$ucode_img' a mano antes del initramfs en la linea INITRD."
    else
        log_info "No se reconocio el cargador de arranque; verifica tras reiniciar con: dmesg | grep -i microcode"
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 15: zram (memoria comprimida al 100% de la RAM física)
# ------------------------------------------------------------------------------
setup_zram() {
    log_info "== Configurando zram =="
    install_pkgs zram-init zram-init-openrc

    ram_total_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
    ram_total_mb=$((ram_total_kb / 1024))

    log_info "RAM física detectada: ${ram_total_mb}MB. Configurando zram al 100% de ese valor."

    cat > /etc/conf.d/zram-init <<EOF
load_on_start=yes
unload_on_stop=yes
num_devices=1
type0=swap
size0=${ram_total_mb}
algo0=zstd
EOF

    if ! grep -q "^vm.swappiness=100" /etc/sysctl.conf 2>/dev/null; then
        {
            echo "vm.swappiness=100"
            echo "vm.page-cluster=0"
        } >> /etc/sysctl.conf
    fi

    rc-update add zram-init default || log_warn "No se pudo agregar 'zram-init' al runlevel default."

    log_ok "zram configurado (swap comprimido = 100% de la RAM, algoritmo zstd)."
}

# ------------------------------------------------------------------------------
# BLOQUE 16: EarlyOOM
# ------------------------------------------------------------------------------
setup_earlyoom() {
    log_info "== Configurando EarlyOOM =="
    install_pkgs earlyoom earlyoom-openrc
    rc-update add earlyoom default || log_warn "No se pudo agregar 'earlyoom' al runlevel default."
    log_ok "EarlyOOM configurado."
}

# ------------------------------------------------------------------------------
# BLOQUE 17: Gestión de energía básica (ACPI)
# ------------------------------------------------------------------------------
# CORRECCION: antes se habilitaba acpid siempre. Desde mayo de 2025,
# setup-desktop (alpine-conf) lo DESHABILITA a proposito en los equipos
# de escritorio, porque podia apagar el sistema por accidente: con un
# escritorio, elogind ya atiende el boton de encendido y la tapa, y acpid
# respondia al mismo evento por su cuenta. Este script instala elogind
# siempre (Bloque 19), asi que acpid solo se habilita si no hay escritorio.
setup_power() {
    log_info "== Configurando gestión de energía (ACPI) =="
    if [ "$DE_XFCE" = "yes" ] || [ "$DE_PLASMA" = "yes" ] || [ "$DE_GNOME" = "yes" ] || [ "$DE_MATE" = "yes" ] || [ "$DE_LXQT" = "yes" ]; then
        if rc-update show default 2>/dev/null | grep -q '^ *acpid '; then
            rc-update del acpid default >/dev/null 2>&1 || true
            log_info "acpid quitado del arranque: con escritorio, elogind maneja el boton de encendido y la tapa (igual que hace setup-desktop)."
        fi
        log_ok "Gestion de energia a cargo de elogind."
        return 0
    fi
    install_pkgs acpid acpid-openrc
    rc-update add acpid default || log_warn "No se pudo agregar 'acpid' al runlevel default."
    log_ok "acpid configurado (sistema sin escritorio)."
}

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# BLOQUE 18: Optimizacion de discos duros mecanicos (HDD)
# ------------------------------------------------------------------------------
# Equipos "revividos" suelen tener disco mecanico, no SSD. BFQ prioriza
# que un proceso con mucha carga de E/S (una actualizacion de apk, copiar
# un archivo grande) no congele el resto del escritorio -- el mismo
# objetivo que earlyoom persigue para la memoria. Contrapartida real: BFQ
# tiene mas overhead de CPU que mq-deadline; en CPUs muy debiles esto
# puede notarse. Se verifica en tiempo de ejecucion si el kernel actual
# tiene BFQ disponible (no se asume) y se cae a mq-deadline si no.
#
# NO se modifica /etc/fstab automaticamente (por ejemplo, para agregar
# "noatime"): es un archivo critico para el arranque y un error ahi deja
# el sistema sin bootear. Se sugiere como paso manual en el log.
optimize_hdd_storage() {
    log_info "== Optimizando planificador de E/S para discos mecanicos =="

    modprobe bfq 2>/dev/null || true

    # Identifica el disco raiz solo para dar contexto mas preciso en el
    # log (no cambia la logica: la regla udev sigue aplicando por
    # atributo 'rotational', no por nombre de disco, asi que funciona
    # igual sea cual sea el orden sda/sdb entre reinicios). Se usa
    # 'mount' en vez de findmnt/lsblk para no agregar una dependencia
    # nueva solo por este dato informativo.
    root_partition="$(mount | awk '$3=="/" {print $1; exit}')"
    root_dev=""
    if [ -n "$root_partition" ]; then
        root_dev="$(basename "$root_partition" | sed -E 's#^/dev/##; s/p?[0-9]+$//')"
    fi

    found_rotational="no"
    found_nonrotational="no"
    sample_dev=""

    for dev in /sys/block/*/queue/rotational; do
        [ -e "$dev" ] || continue
        devname="$(echo "$dev" | cut -d/ -f4)"
        case "$devname" in
            loop*|ram*|zram*) continue ;;
        esac
        rotational="$(cat "$dev" 2>/dev/null || echo 0)"
        if [ "$rotational" = "1" ]; then
            found_rotational="yes"
            [ -z "$sample_dev" ] && sample_dev="$devname"
            if [ "$devname" = "$root_dev" ]; then
                log_info "Disco mecanico detectado: /dev/$devname (es el disco RAIZ del sistema)"
            else
                log_info "Disco mecanico detectado: /dev/$devname (auxiliar, no es la raiz)"
            fi
        else
            found_nonrotational="yes"
            if [ "$devname" = "$root_dev" ]; then
                log_info "Disco de estado solido detectado: /dev/$devname (es el disco RAIZ del sistema)"
            fi
        fi
    done

    if [ "$found_rotational" = "no" ]; then
        log_info "No se detectaron discos mecanicos (SSD/NVMe unicamente, o ninguno). Se omite esta optimizacion."
        return 0
    fi

    chosen_scheduler="mq-deadline"
    if [ -r "/sys/block/$sample_dev/queue/scheduler" ] && grep -q "bfq" "/sys/block/$sample_dev/queue/scheduler"; then
        chosen_scheduler="bfq"
    else
        log_warn "El kernel actual no reporta 'bfq' disponible; se usa 'mq-deadline' como alternativa segura."
    fi

    mkdir -p /etc/udev/rules.d
    cat > /etc/udev/rules.d/60-ioscheduler.rules <<EOF
# Generado por desktop-postinstall.sh
# Se aplica solo a dispositivos con rotational==1 (por atributo, no por
# nombre) -- en un sistema mixto SSD+HDD, el/los SSD nunca se ven
# afectados por esta regla, sin importar que letra de disco les toque.
ACTION=="add|change", KERNEL=="sd[a-z]|hd[a-z]|vd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="$chosen_scheduler"
EOF

    log_ok "Planificador '$chosen_scheduler' configurado para discos mecanicos en /etc/udev/rules.d/60-ioscheduler.rules"

    if [ "$found_nonrotational" = "yes" ]; then
        log_info "Configuracion mixta detectada (SSD + HDD): el SSD conserva el planificador que el kernel ya le asigna por defecto, no requiere intervencion."
        log_info "Sugerencia manual: si el disco mecanico se usa solo para datos (no es la raiz), agregar 'noatime' a su linea en /etc/fstab es especialmente seguro de aplicar (a diferencia de tocar la particion raiz) y reduce escrituras innecesarias."
    else
        log_info "Sugerencia manual (no aplicada automaticamente): agregar 'noatime' a las opciones de montaje en /etc/fstab reduce escrituras innecesarias en discos mecanicos."
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 18b: TRIM semanal para discos de estado solido
# ------------------------------------------------------------------------------
# Un SSD necesita que el sistema le avise que bloques quedaron libres
# (TRIM); sin eso, en SSD baratos el rendimiento de escritura cae con el
# tiempo. Alpine no monta con 'discard' ni programa un TRIM periodico, y
# no tiene un servicio "fstrim" de OpenRC (eso es un timer de systemd en
# otras distribuciones). Se usa el mecanismo propio de Alpine: un script
# en /etc/periodic/weekly, que ejecuta crond (setup-alpine lo habilita).
# 'fstrim -a' solo recorta los sistemas de archivos que lo soportan.
setup_ssd_trim() {
    log_info "== TRIM periodico para SSD =="
    has_ssd="no"
    for dev in /sys/block/*/queue/rotational; do
        [ -e "$dev" ] || continue
        devname="${dev%/queue/rotational}"
        devname="${devname##*/}"
        case "$devname" in
            loop*|ram*|zram*|sr*) continue ;;
        esac
        # Solo discos que no giran Y aceptan TRIM (discard_max_bytes > 0).
        [ "$(cat "$dev" 2>/dev/null)" = "0" ] || continue
        [ "$(cat "/sys/block/$devname/queue/discard_max_bytes" 2>/dev/null || echo 0)" != "0" ] || continue
        has_ssd="yes"
        log_info "Disco de estado solido con TRIM: /dev/$devname"
    done
    if [ "$has_ssd" = "no" ]; then
        log_info "No hay discos de estado solido con TRIM. Se omite."
        return 0
    fi
    install_pkgs fstrim
    mkdir -p /etc/periodic/weekly
    cat > /etc/periodic/weekly/fstrim <<'EOF'
#!/bin/sh
# Generado por desktop-postinstall.sh: TRIM semanal de los SSD.
fstrim -a >/dev/null 2>&1 || true
EOF
    chmod 755 /etc/periodic/weekly/fstrim
    rc-update add crond default >/dev/null 2>&1 || log_warn "No se pudo habilitar 'crond' (necesario para el TRIM semanal)."
    log_ok "TRIM semanal configurado: /etc/periodic/weekly/fstrim (lo ejecuta crond)."
}

# ------------------------------------------------------------------------------
# BLOQUE 19: Montaje automático de USB (udisks2 + polkit + gvfs por DE)
# ------------------------------------------------------------------------------
# El montaje real lo hace udisks2 (dbus-activated, no requiere su propio
# servicio OpenRC). Para que un usuario normal (no root) pueda montar sin
# contraseña hace falta autorización vía polkit + gestión de sesión vía
# elogind (Alpine no usa systemd, por eso la variante "elogind" en vez del
# polkit "puro"). Comandos y nombres de servicio verificados contra la
# wiki oficial de Alpine (los nombres de servicio OpenRC difieren de los
# nombres de paquete: "elogind" y "polkit", no "polkit-elogind").
# Además, cada gestor de archivos necesita su propio "disparador" que
# reaccione al evento de conexión: gvfs para los basados en GTK
# (XFCE/GNOME/MATE), gvfs + lxqt-policykit para LXQt. Plasma no necesita
# nada de esto porque Dolphin usa KIO/Solid + udisks2 directamente.
setup_usb_automount() {
    log_info "== Configurando montaje automático de USB =="

    # CRÍTICO: dbus debe estar instalado y habilitado ANTES que udisks2,
    # elogind y polkit, ya que los tres dependen estrictamente del bus de
    # mensajes del sistema para funcionar. Se instala aquí explícitamente
    # en vez de asumir que ya llegó como dependencia transitiva de la DE.
    install_pkg "dbus"
    rc-update add dbus default || log_warn "No se pudo agregar 'dbus' al runlevel default."

    install_pkg "udisks2"

    install_pkg "elogind"
    rc-update add elogind default || log_warn "No se pudo agregar 'elogind' al runlevel default."

    install_pkg "polkit-elogind"
    rc-update add polkit default || log_warn "No se pudo agregar 'polkit' al runlevel default."

    if [ "$DE_XFCE" = "yes" ]; then
        install_pkg "gvfs"
        install_pkg "thunar-volman"
    fi

    if [ "$DE_GNOME" = "yes" ]; then
        install_pkg "gvfs"
    fi

    if [ "$DE_MATE" = "yes" ]; then
        install_pkg "gvfs"
    fi

    if [ "$DE_LXQT" = "yes" ]; then
        install_pkg "gvfs"
        install_pkg "lxqt-policykit"
    fi

    if [ "$DE_PLASMA" = "yes" ]; then
        log_info "Plasma detectado: Dolphin usa KIO/Solid + udisks2 directamente, sin necesidad de gvfs."
    fi

    log_ok "Montaje automático de USB configurado. Verifica al conectar un USB tras reiniciar."
}

# ------------------------------------------------------------------------------
# BLOQUE 20: Soporte de impresión (CUPS)
# ------------------------------------------------------------------------------
setup_printing() {
    log_info "== Soporte de impresión (CUPS) =="

    if ! want OPT_CUPS "¿Deseas instalar soporte de impresión (CUPS)?"; then
        log_info "Se omite CUPS."
        return 0
    fi

    log_info "== Configurando soporte de impresión (CUPS) =="
    install_pkgs cups cups-openrc cups-filters system-config-printer
    rc-update add cupsd default || log_warn "No se pudo agregar 'cupsd' al runlevel default."
    log_ok "CUPS configurado. Interfaz web disponible en http://localhost:631"
}

# ------------------------------------------------------------------------------
# BLOQUE 21: Backends de compresión
# ------------------------------------------------------------------------------
install_archive_tools() {
    log_info "== Instalando utilidades de compresión =="
    install_pkgs zip unzip 7zip
    log_ok "Backends de compresión instalados (zip/unzip/7z)."
}

# ------------------------------------------------------------------------------
# BLOQUE 22: Idioma español — sistema, XFCE y propagación global a Plasma
# ------------------------------------------------------------------------------
setup_locale_es() {
    log_info "== Configurando idioma español para el sistema =="

    install_pkg "musl-locales"
    install_pkg "musl-locales-lang"

    if [ -f /etc/rc.conf ] && ! grep -q '^unicode="YES"' /etc/rc.conf; then
        sed -i 's/#unicode="NO"/#unicode="NO"\nunicode="YES"/' /etc/rc.conf 2>/dev/null || true
    fi

    cat > /etc/profile.d/lang-es.sh <<'EOF'
export LANG="es_ES.UTF-8"
export LC_ALL="es_ES.UTF-8"
export LC_MESSAGES="es_ES.UTF-8"
EOF
    chmod +x /etc/profile.d/lang-es.sh
    log_ok "Capa 1/3: variables de idioma escritas en /etc/profile.d/lang-es.sh"

    if [ -f /etc/environment ]; then
        sed -i '/^LANG=/d;/^LC_ALL=/d;/^LC_MESSAGES=/d' /etc/environment
    fi
    {
        echo "LANG=es_ES.UTF-8"
        echo "LC_ALL=es_ES.UTF-8"
        echo "LC_MESSAGES=es_ES.UTF-8"
    } >> /etc/environment
    log_ok "Capa 2/3: variables de idioma agregadas a /etc/environment (leído por PAM en la mayoría de gestores de sesión gráficos)."

    install_pkg "lang"

    if [ "$DE_PLASMA" = "yes" ]; then
        log_info "Reforzando traducciones específicas de Plasma..."
        install_pkg "plasma-desktop-lang"
        install_pkg "kdeplasma-addons-lang"

        mkdir -p /etc/xdg
        cat > /etc/xdg/plasma-localerc <<'EOF'
[Formats]
LANG=es_ES.UTF-8

[Translations]
LANGUAGE=es_ES:es
EOF
        log_ok "Capa 3/3: default de sistema escrito en /etc/xdg/plasma-localerc (aplica a usuarios nuevos)."

        if [ -n "$TARGET_USER" ] && [ -n "$TARGET_HOME" ]; then
            # Si ~/.config no existe aún (usuario que nunca inició sesión),
            # se crea a nombre del usuario: creada por root, Plasma no
            # podría guardar nada ahí ("kioworkerrc not writable").
            if [ ! -d "$TARGET_HOME/.config" ]; then
                mkdir -p "$TARGET_HOME/.config"
                chown "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$TARGET_HOME/.config" 2>/dev/null || true
            fi
            cat > "$TARGET_HOME/.config/plasma-localerc" <<'EOF'
[Formats]
LANG=es_ES.UTF-8

[Translations]
LANGUAGE=es_ES:es
EOF
            chown "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$TARGET_HOME/.config/plasma-localerc" 2>/dev/null || true
            log_ok "Capa 3/3: idioma de Plasma pre-configurado también para el usuario existente '$TARGET_USER'."
        else
            log_warn "No se detectó un usuario existente; solo quedó el default de sistema en /etc/xdg/plasma-localerc."
        fi
    fi

    log_ok "Idioma español configurado para el/los entorno(s) detectado(s)."
}

# ------------------------------------------------------------------------------
# BLOQUE 23: Tipografías base (antes de LibreOffice)
# ------------------------------------------------------------------------------
install_fonts() {
    log_info "== Instalando tipografías base =="
    # font-noto-emoji va aparte de font-noto: sin el, paginas como
    # WhatsApp Web muestran cuadritos en lugar de emojis. (Plasma ya lo
    # trae como dependencia; los demas escritorios no.)
    install_pkgs font-dejavu font-liberation font-liberation-sans-narrow font-noto font-noto-emoji
    log_ok "Tipografías base instaladas."
}

# ------------------------------------------------------------------------------
# BLOQUE 24: LibreOffice + paquete de idioma español
# ------------------------------------------------------------------------------
install_libreoffice() {
    log_info "== LibreOffice =="

    if ! want OPT_LIBREOFFICE "¿Deseas instalar LibreOffice? (paquete pesado; si prefieres OnlyOffice vía Flatpak, puedes responder 'n' aquí y aceptarlo más adelante)"; then
        log_info "Se omite LibreOffice."
        return 0
    fi

    log_info "== Instalando LibreOffice (español) =="
    install_pkgs libreoffice libreoffice-lang-es
    log_ok "LibreOffice instalado con soporte de idioma español."
}

# ------------------------------------------------------------------------------
# BLOQUE 25: Flatpak + Flathub (OnlyOffice y Google Chrome, opcionales)
# ------------------------------------------------------------------------------
setup_flatpak() {
    log_info "== Flatpak / Flathub =="

    if ! want OPT_FLATPAK "¿Deseas habilitar Flatpak/Flathub en este sistema? (necesario solo si planeas instalar apps como OnlyOffice o Chrome desde Flathub)"; then
        log_info "Se omite Flatpak por completo (no se instala infraestructura ni se preguntará por apps individuales)."
        return 0
    fi

    log_info "== Configurando Flatpak y repositorio Flathub =="

    # dbus ya se instaló y habilitó en el Bloque 18 (setup_usb_automount).
    # Portal GTK como base universal (XFCE/GNOME/MATE, y red de seguridad
    # para cualquier entorno). El propio xdg-desktop-portal elige el
    # backend correcto en tiempo real según XDG_CURRENT_DESKTOP, así que
    # tener varios instalados es seguro: no hace falta excluir GTK.
    # (install_pkgs ya tolera que 'flatpak' falle por repo 'community' no
    # habilitado: si la transacción en lote falla, reintenta cada paquete
    # por separado, así que xdg-desktop-portal/-gtk no se pierden con él.)
    install_pkgs flatpak xdg-desktop-portal xdg-desktop-portal-gtk

    if [ "$DE_PLASMA" = "yes" ]; then
        log_info "Plasma detectado: instalando portal nativo Qt/KDE para diálogos coherentes con el entorno..."
        install_pkg "xdg-desktop-portal-kde"
    fi

    if [ "$DE_LXQT" = "yes" ]; then
        log_info "LXQt detectado: instalando portal nativo Qt/LXQt para diálogos coherentes con el entorno..."
        install_pkg "xdg-desktop-portal-lxqt"
    fi

    if ! command -v flatpak >/dev/null 2>&1; then
        log_error "flatpak no quedó instalado. Verifica el repositorio 'community'. Se omite esta sección."
        return 0
    fi

    if command -v dbus-run-session >/dev/null 2>&1; then
        remote_add_cmd="dbus-run-session -- flatpak"
    else
        log_warn "'dbus-run-session' no disponible; se ejecuta flatpak sin bus de sesión."
        remote_add_cmd="flatpak"
    fi

    if $remote_add_cmd remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
        log_ok "Repositorio Flathub agregado (o ya existía)."
    else
        log_warn "No se pudo agregar el repositorio Flathub."
        return 0
    fi

    if want OPT_ONLYOFFICE "¿Deseas instalar OnlyOffice Desktop Editors vía Flatpak?"; then
        $remote_add_cmd install -y flathub org.onlyoffice.desktopeditors && log_ok "OnlyOffice instalado." || log_warn "Fallo al instalar OnlyOffice."
    else
        log_info "Se omite OnlyOffice."
    fi

    if want OPT_CHROME "¿Deseas instalar Google Chrome vía Flatpak (paquete comunitario, no oficial de Google)?"; then
        $remote_add_cmd install -y flathub com.google.Chrome && log_ok "Google Chrome instalado." || log_warn "Fallo al instalar Google Chrome."
    else
        log_info "Se omite Google Chrome."
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 26: Habilitar el Gestor de Inicio de Sesión (Display Manager)
# ------------------------------------------------------------------------------
# No basta con que setup-desktop lo haya dejado instalado: hay reportes
# reales de lightdm/sddm fallando al no quedar correctamente enganchados
# al runlevel default. A diferencia de una prioridad fija, aquí se usan
# las banderas DE_* ya detectadas (Bloque 4) para elegir el DM que
# corresponde por convención -- la misma que usa el propio setup-desktop
# de Alpine (plasma->sddm, gnome->gdm) -- en vez de encender el primero
# que aparezca instalado. Esto importa en equipos con más de un entorno
# instalado (p. ej. XFCE + Plasma a la vez), donde una prioridad fija
# podría habilitar el DM equivocado para el entorno que realmente se usa.
setup_display_manager() {
    log_info "== Detectando y habilitando Gestor de Inicio de Sesión =="

    dm_installed=""
    apk info -e lightdm >/dev/null 2>&1 && dm_installed="$dm_installed lightdm"
    apk info -e sddm >/dev/null 2>&1 && dm_installed="$dm_installed sddm"
    apk info -e gdm >/dev/null 2>&1 && dm_installed="$dm_installed gdm"

    if [ -z "$dm_installed" ]; then
        log_warn "No se detectó un Display Manager instalado (lightdm/sddm/gdm). El sistema arrancará en modo texto."
        return 0
    fi

    chosen=""
    if [ "$DE_PLASMA" = "yes" ] && echo "$dm_installed" | grep -qw "sddm"; then
        chosen="sddm"
    elif [ "$DE_GNOME" = "yes" ] && echo "$dm_installed" | grep -qw "gdm"; then
        chosen="gdm"
    elif echo "$dm_installed" | grep -qw "lightdm"; then
        chosen="lightdm"
    else
        chosen="$(echo "$dm_installed" | awk '{print $1}')"
    fi

    dm_count="$(echo "$dm_installed" | wc -w)"
    if [ "$dm_count" -gt 1 ]; then
        log_warn "Se detectaron varios Display Managers instalados ($dm_installed). Se habilita '$chosen' según el entorno de escritorio detectado."
    fi

    rc-update add "$chosen" default || log_warn "Fallo al habilitar '$chosen'."
    log_ok "Display Manager '$chosen' habilitado en el runlevel default."
}

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# BLOQUE 27: Acceso directo de actualizacion en el menu de aplicaciones
# ------------------------------------------------------------------------------
# Los archivos .desktop siguen el estandar XDG Desktop Entry: un unico
# archivo en /usr/share/applications/ aparece automaticamente en el menu
# de TODOS los entornos detectados (XFCE, Plasma, GNOME, MATE, LXQt), sin
# logica especifica por DE -- es justamente para eso que existe el
# estandar.
#
# Autenticacion via pkexec (parte de polkit-elogind, Bloque 19). Por
# defecto, SIN necesidad de ninguna regla de polkit personalizada: si el
# usuario objetivo esta en el grupo "wheel", pkexec pide UNICAMENTE su
# propia contrasena (igual que doas), nunca la de root. Es el
# comportamiento estandar documentado de polkit, no un ajuste especial.
#
# Diseno en dos scripts separados por robustez:
#   - alpine-update-root.sh      -> corre como root via pkexec; SOLO
#     hace el trabajo (apk + flatpak), sin nada grafico, para no
#     depender de que X11/Wayland se reenvien correctamente a traves
#     del salto de privilegios.
#   - alpine-update-launcher.sh  -> corre como el usuario normal; llama
#     a pkexec y muestra el resultado con zenity ya en su propia sesion
#     grafica, sin cruzar el limite de privilegios para la parte visual.
setup_update_shortcut() {
    log_info "== Acceso directo de actualizacion en el menu =="

    if ! want OPT_UPDATE_SHORTCUT "¿Deseas crear un boton en el menu de aplicaciones para actualizar Alpine (y Flatpak, si esta instalado) con un clic?"; then
        log_info "Se omite el acceso directo de actualizacion."
        return 0
    fi

    # util-linux-misc trae 'script', necesario mas abajo en
    # alpine-update-root.sh para forzar a apk/flatpak a comportarse como
    # si escribieran a una terminal real.
    # coreutils trae la version de 'tail' con soporte para --pid, usada
    # mas abajo para que la ventana de progreso sepa cuando terminar sola
    # (el 'tail' de BusyBox, el de por defecto en Alpine, no tiene esa
    # opcion).
    install_pkgs zenity util-linux-misc coreutils

    # pkexec lanzado desde un menu grafico (sin terminal) NECESITA un
    # agente de autenticacion polkit en ejecucion para dibujar la ventana
    # de contrasena. Sin el, pkexec falla con "No authentication agent
    # found" y la actualizacion nunca empieza. Plasma (polkit-kde-agent),
    # GNOME (integrado en GNOME Shell) y LXQt (lxqt-policykit, Bloque 19)
    # ya traen el suyo; XFCE y MATE se cubren aqui. Ademas, el lanzador
    # comprueba en cada ejecucion que el agente este CORRIENDO y lo
    # inicia si hace falta: instalar el paquete no garantiza que arranque,
    # porque el autoarranque de polkit-gnome suele estar restringido a
    # ciertos escritorios segun la distribucion.
    if [ "$DE_XFCE" = "yes" ]; then
        install_pkgs polkit-gnome
    fi
    if [ "$DE_MATE" = "yes" ]; then
        install_pkgs mate-polkit
    fi

    if [ -z "$TARGET_USER" ]; then
        log_warn "No se determino un usuario estandar; el acceso directo se creara igual, pero verifica manualmente que el usuario este en el grupo 'wheel' para que pkexec pida solo su propia contrasena."
    else
        if ! id -nG "$TARGET_USER" 2>/dev/null | grep -qw wheel; then
            adduser "$TARGET_USER" wheel && log_ok "Usuario '$TARGET_USER' agregado al grupo 'wheel' (requerido por pkexec)." || log_warn "No se pudo agregar '$TARGET_USER' al grupo 'wheel'."
        fi
    fi

    cat > /usr/local/bin/alpine-update-root.sh <<'INNEREOF'
#!/bin/sh
# Ejecutado como root via pkexec. Imprime a stdout/stderr a proposito
# (sin redirigir a un archivo aqui): el script lanzador es quien captura
# esta salida en vivo y la muestra en pantalla.
#
# NOTA DE DISENO: cada linea que este script imprime lleva el prefijo
# "# " -- es la sintaxis que 'zenity --progress' usa para saber que debe
# actualizar el texto visible (una linea SIN ese prefijo se ignora por
# completo). Esto hace que /var/log/alpine-update.log se vea distinto a
# un log convencional si se abre despues, pero a cambio el lanzador
# puede alimentar a Zenity con un 'tail -f' directo, sin procesos
# intermedios que sincronizar. Un diseno anterior usaba una tuberia con
# nombre (FIFO) para separar el prefijado del resto, y esa version
# demostro en pruebas ser propensa a quedarse esperando para siempre si
# el lector y el escritor no llegaban a sincronizarse a tiempo.

printf 'ok\n' > /tmp/.alpine-update-authenticated 2>/dev/null || true

# apk (y flatpak) deciden cuanto detalle imprimir -- y con que buffer --
# segun si SU salida esta conectada a una terminal real. Aqui no lo esta,
# asi que 'script' (util-linux-misc) hace creer al programa que si la
# hay, sin que aparezca nada distinto en la pantalla real (su copia
# normal se descarta a /dev/null). Si 'script' no esta disponible, se
# sigue igual sin el.
if command -v script >/dev/null 2>&1; then
    run_raw() { script -qec "$1" /dev/null; }
else
    run_raw() { sh -c "$1"; }
fi

# Antepone "# " a cada linea que llega por su entrada, usando solo
# comandos internos del shell (read/echo) -- no un programa aparte
# (como 'sed') que pudiera acumular su propia salida en un buffer antes
# de escribirla, sobre todo al procesar muchas lineas seguidas.
prefixed() {
    while IFS= read -r linea; do
        echo "# $linea"
    done
}

EXIT_TMP="/tmp/.alpine-update-exit"

# Ejecuta un paso, muestra su salida y deja su codigo en $step_status.
run_step() {
    run_raw "$1; echo \$? > $EXIT_TMP" | prefixed
    step_status="$(cat "$EXIT_TMP" 2>/dev/null || echo 1)"
    rm -f "$EXIT_TMP"
    return "$step_status"
}

# --- Siguiente version estable de Alpine ----------------------------------
# Imprime "ACTUAL SIGUIENTE ESPEJO" (p. ej. "3.23 3.24 https://dl-cdn...")
# si hay una version estable mas nueva que la instalada, o nada (y
# devuelve 1) si no la hay, si no hay internet o si los repositorios no
# usan una version fija (edge, latest-stable).
#   - La version actual se lee de /etc/apk/repositories (la que de verdad
#     usa apk), no de /etc/alpine-release.
#   - La ultima estable se lee del archivo latest-releases.yaml que publica
#     cada espejo (campo "branch: v3.NN").
#   - Se propone solo la INMEDIATAMENTE siguiente (3.23 -> 3.24), aunque
#     haya otra mas nueva: un salto a la vez es el camino mas probado. Si
#     falta otra, el boton la ofrece en la siguiente ejecucion.
#   - Antes de proponerla se confirma que el espejo ya tiene su repositorio.
next_release() {
    repo_line="$(grep -m1 -E '^[[:space:]]*https?://[^[:space:]]+/v3\.[0-9]+/main' /etc/apk/repositories 2>/dev/null)" || return 1
    nr_cur="$(printf '%s\n' "$repo_line" | sed -E 's#.*/v(3\.[0-9]+)/main.*#\1#')"
    nr_base="$(printf '%s\n' "$repo_line" | sed -E 's#^[[:space:]]*(https?://[^[:space:]]+)/v3\.[0-9]+/main.*#\1#')"
    nr_arch="$(apk --print-arch 2>/dev/null)"
    [ -n "$nr_cur" ] && [ -n "$nr_base" ] && [ -n "$nr_arch" ] || return 1
    nr_latest="$(wget -q -T 15 -O - "$nr_base/latest-stable/releases/$nr_arch/latest-releases.yaml" 2>/dev/null \
        | sed -n -E 's/^[[:space:]]*branch:[[:space:]]*v(3\.[0-9]+).*/\1/p' | head -n1)"
    [ -n "$nr_latest" ] || return 1
    nr_cur_minor="${nr_cur#3.}"
    nr_latest_minor="${nr_latest#3.}"
    case "$nr_cur_minor$nr_latest_minor" in *[!0-9]*) return 1 ;; esac
    [ "$nr_latest_minor" -gt "$nr_cur_minor" ] || return 1
    nr_next="3.$((nr_cur_minor + 1))"
    wget -q -T 15 --spider "$nr_base/v$nr_next/main/$nr_arch/APKINDEX.tar.gz" 2>/dev/null || return 1
    echo "$nr_cur $nr_next $nr_base"
}

echo "# ===== Actualizando Alpine (apk) ====="

# Kernels instalados ANTES de actualizar. Se compara /lib/modules (un
# directorio por kernel instalado) en vez de la salida de 'apk info',
# cuyo formato cambio entre apk-tools v2 y v3.
modules_before="$(ls /lib/modules 2>/dev/null | tr '\n' ' ')"

apk_status=0
run_step "apk update --no-progress" || apk_status=$step_status
run_step "apk upgrade --no-progress" || apk_status=$step_status

# --- Cambio a la siguiente version estable (solo si se pidio) ---------
# El lanzador solo pasa la opcion; la version de destino se vuelve a
# calcular aqui, como root, en vez de aceptar un valor que llegue desde
# fuera. Procedimiento oficial de Alpine: cambiar la version en
# /etc/apk/repositories, actualizar apk-tools y luego
# 'apk upgrade --available'.
if [ "${1:-}" = "--nueva-version" ]; then
    if [ "$apk_status" -ne 0 ]; then
        echo "# "
        echo "# No se cambia de version porque la actualizacion normal fallo. Revisa la conexion e intentalo de nuevo."
    elif ! nr_info="$(next_release)"; then
        echo "# "
        echo "# No se encontro una version nueva disponible; se hizo solo la actualizacion normal."
    else
        # shellcheck disable=SC2086
        set -- $nr_info
        v_cur="$1"
        v_next="$2"
        echo "# "
        echo "# ===== Cambiando de Alpine $v_cur a Alpine $v_next ====="
        mkdir -p /var/backups/alpine-update
        backup="/var/backups/alpine-update/repositories.v$v_cur.$(date +%Y%m%d-%H%M%S)"
        cp /etc/apk/repositories "$backup"
        echo "# Copia de los repositorios anteriores: $backup"
        cur_re="$(printf '%s' "$v_cur" | sed 's/\./\\./g')"
        sed -i "s#/v$cur_re/#/v$v_next/#g" /etc/apk/repositories
        if ! run_step "apk update --no-progress"; then
            cp "$backup" /etc/apk/repositories
            run_step "apk update --no-progress" || true
            apk_status=1
            echo "# No se pudo leer el repositorio de Alpine $v_next. Se restauraron los repositorios de $v_cur: el sistema no cambio."
        else
            run_step "apk add --upgrade --no-progress apk-tools" || true
            if run_step "apk upgrade --available --no-progress"; then
                echo "# "
                echo "# Alpine quedo actualizado a la version $v_next."
            else
                apk_status=$step_status
                echo "# "
                echo "# *** El cambio a Alpine $v_next quedo INCOMPLETO (codigo $apk_status). ***"
                echo "# No reinicies todavia: conectate a internet y vuelve a usar este boton,"
                echo "# o ejecuta en una terminal: doas apk upgrade --available"
            fi
            if [ -d /boot/grub ] && command -v grub-install >/dev/null 2>&1; then
                echo "# AVISO: este equipo arranca con GRUB. Antes de reiniciar, revisa en las"
                echo "# notas de la version si hay que ejecutar grub-install (en 3.24 si hacia falta)."
            fi
        fi
    fi
fi

modules_after="$(ls /lib/modules 2>/dev/null | tr '\n' ' ')"
if [ -n "$modules_after" ] && [ "$modules_before" != "$modules_after" ]; then
    echo "# "
    echo "# *** SE ACTUALIZO EL KERNEL ***"
    echo "# Antes:   $modules_before"
    echo "# Despues: $modules_after"
    echo "# Es necesario REINICIAR el equipo para empezar a usarlo."
fi

if command -v flatpak >/dev/null 2>&1; then
    echo "# "
    echo "# ===== Actualizando aplicaciones Flatpak ====="
    run_raw "flatpak update -y" | prefixed
fi

echo "# "
if [ "$apk_status" -eq 0 ]; then
    echo "# Actualizacion completada sin errores. ($(date '+%H:%M:%S'))"
else
    echo "# Actualizacion terminada con errores, codigo $apk_status. ($(date '+%H:%M:%S'))"
fi

exit "$apk_status"
INNEREOF
    chmod 755 /usr/local/bin/alpine-update-root.sh
    chown root:root /usr/local/bin/alpine-update-root.sh

    cat > /usr/local/bin/alpine-update-launcher.sh <<'INNEREOF'
#!/bin/sh
# Corre como el usuario normal; pide autenticacion via pkexec y muestra
# el avance en vivo, ya en la sesion grafica del usuario -- ningun
# proceso grafico cruza el limite de privilegios, solo texto plano a
# traves de una tuberia.
LOG="/var/log/alpine-update.log"
MARKER="/tmp/.alpine-update-authenticated"

# El marcador lo crea el lanzador (dueno: el usuario), y alpine-update-root.sh
# solo ESCRIBE contenido dentro de el una vez autenticado -- nunca lo borra
# ni lo recrea, asi que la propiedad se mantiene y este script si puede
# borrarlo despues, pese al bit sticky de /tmp.
rm -f "$MARKER"
: > "$MARKER"

# --- Agente de autenticacion polkit ------------------------------------
# pkexec sin terminal depende de un agente grafico para pedir la
# contrasena. Se busca uno del propio usuario leyendo /proc directamente
# (sin depender de las opciones de pgrep, que varian entre versiones).
polkit_agent_running() {
    for c in /proc/[0-9]*/comm; do
        [ -O "$c" ] || continue
        read -r name < "$c" 2>/dev/null || continue
        case "$name" in
            polkit-gnome-*|polkit-kde-*|polkit-mate-*|lxqt-policykit*) return 0 ;;
        esac
    done
    return 1
}

if ! polkit_agent_running; then
    for agent in \
        /usr/libexec/polkit-gnome-authentication-agent-1 \
        /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
        /usr/libexec/polkit-mate-authentication-agent-1 \
        /usr/lib/mate-polkit/polkit-mate-authentication-agent-1
    do
        if [ -x "$agent" ]; then
            "$agent" >/dev/null 2>&1 &
            sleep 1
            break
        fi
    done
fi

# NOTA: en versiones anteriores de este bloque, apk quedaba conectado
# DIRECTAMENTE a Zenity por una tuberia (pkexec | tee | zenity), y cerrar
# la ventana a mitad del proceso podia matarlo por SIGPIPE -- de ahi un
# 'trap PIPE' que ya no aparece aqui. Con el diseno actual, apk escribe a
# un ARCHIVO (linea de abajo), no a una tuberia: Zenity ni siquiera esta
# conectado a el, asi que ese riesgo desaparecio por diseno, no hace
# falta blindarse contra el.

# --- Siguiente version estable de Alpine ----------------------------------
# Imprime "ACTUAL SIGUIENTE ESPEJO" (p. ej. "3.23 3.24 https://dl-cdn...")
# si hay una version estable mas nueva que la instalada, o nada (y
# devuelve 1) si no la hay, si no hay internet o si los repositorios no
# usan una version fija (edge, latest-stable).
#   - La version actual se lee de /etc/apk/repositories (la que de verdad
#     usa apk), no de /etc/alpine-release.
#   - La ultima estable se lee del archivo latest-releases.yaml que publica
#     cada espejo (campo "branch: v3.NN").
#   - Se propone solo la INMEDIATAMENTE siguiente (3.23 -> 3.24), aunque
#     haya otra mas nueva: un salto a la vez es el camino mas probado. Si
#     falta otra, el boton la ofrece en la siguiente ejecucion.
#   - Antes de proponerla se confirma que el espejo ya tiene su repositorio.
next_release() {
    repo_line="$(grep -m1 -E '^[[:space:]]*https?://[^[:space:]]+/v3\.[0-9]+/main' /etc/apk/repositories 2>/dev/null)" || return 1
    nr_cur="$(printf '%s\n' "$repo_line" | sed -E 's#.*/v(3\.[0-9]+)/main.*#\1#')"
    nr_base="$(printf '%s\n' "$repo_line" | sed -E 's#^[[:space:]]*(https?://[^[:space:]]+)/v3\.[0-9]+/main.*#\1#')"
    nr_arch="$(apk --print-arch 2>/dev/null)"
    [ -n "$nr_cur" ] && [ -n "$nr_base" ] && [ -n "$nr_arch" ] || return 1
    nr_latest="$(wget -q -T 15 -O - "$nr_base/latest-stable/releases/$nr_arch/latest-releases.yaml" 2>/dev/null \
        | sed -n -E 's/^[[:space:]]*branch:[[:space:]]*v(3\.[0-9]+).*/\1/p' | head -n1)"
    [ -n "$nr_latest" ] || return 1
    nr_cur_minor="${nr_cur#3.}"
    nr_latest_minor="${nr_latest#3.}"
    case "$nr_cur_minor$nr_latest_minor" in *[!0-9]*) return 1 ;; esac
    [ "$nr_latest_minor" -gt "$nr_cur_minor" ] || return 1
    nr_next="3.$((nr_cur_minor + 1))"
    wget -q -T 15 --spider "$nr_base/v$nr_next/main/$nr_arch/APKINDEX.tar.gz" 2>/dev/null || return 1
    echo "$nr_cur $nr_next $nr_base"
}

# --- Ofrecer el cambio de version ----------------------------------------
# Alpine publica una version estable cada seis meses, y el repositorio
# 'community' (escritorio, Firefox, LibreOffice...) solo recibe
# actualizaciones hasta la siguiente. Si hay una version nueva, se
# pregunta antes de pedir la contrasena. Sin internet, o si el usuario
# elige "Solo actualizar" o cierra la ventana, se hace la actualizacion
# normal de siempre.
MODE=""
release_before="$(cat /etc/alpine-release 2>/dev/null)"
if nr_info="$(next_release)"; then
    # shellcheck disable=SC2086
    set -- $nr_info
    if zenity --question --title="Nueva version de Alpine" --width=440 \
        --ok-label="Cambiar a Alpine $2" --cancel-label="Solo actualizar" \
        --text="Hay una version nueva de Alpine: $2 (tienes $1).\n\nLa version actual pronto dejara de recibir actualizaciones de seguridad para el navegador y el escritorio.\n\nEl cambio descarga bastante y puede tardar. Mantén el equipo conectado a la corriente y a internet, y reinicia al terminar.\n\nNotas de cada version: https://alpinelinux.org/releases/" \
        2>/dev/null; then
        MODE="--nueva-version"
    fi
fi

{
    echo "===== Actualizacion iniciada: $(date) ====="
    # shellcheck disable=SC2086
    pkexec /usr/local/bin/alpine-update-root.sh $MODE
} >> "$LOG" 2>&1 &
BGPID=$!

# --- No mostrar NADA hasta que la contrasena ya se haya aceptado -------
# pkexec y el dialogo de Zenity arrancarian al mismo tiempo si se
# encadenaran en una sola tuberia, y la ventana de Zenity a veces tapa al
# dialogo de contrasena, obligando a buscarlo. Aqui se espera a que
# alpine-update-root.sh escriba en MARKER (ya autenticado como root) o a
# que el proceso completo termine antes de eso (p. ej. el usuario
# cancelo el dialogo de contrasena, o pkexec fallo por falta de agente):
# en ese caso no se muestra ninguna ventana.
while [ ! -s "$MARKER" ] && kill -0 "$BGPID" 2>/dev/null; do
    sleep 0.2
done

# Se captura el resultado ANTES de borrar el marcador, para no depender
# de inferirlo despues por otros medios.
authenticated="no"
[ -s "$MARKER" ] && authenticated="yes"
rm -f "$MARKER"

if [ "$authenticated" = "no" ]; then
    # El proceso ya termino y nunca llego a ejecutar nada como root
    # (contrasena cancelada o pkexec sin agente): no hay nada que
    # mostrar.
    wait "$BGPID" 2>/dev/null
    exit 0
fi

# --- Ventana de progreso: solo la linea mas reciente, sin scroll -------
# En vez de --text-info (que exige desplazarse para ver el avance mas
# nuevo), se usa --progress --pulsate con una sola linea que se
# reemplaza sola cada vez. La barra animada transmite "esto sigue
# corriendo" aunque el texto no cambie por un momento.
#
# CORRECCION: tres disenos anteriores de este bloque resultaron
# fragiles o incompletos. El primero sondeaba el log dependiendo de
# 'kill -0 "$BGPID"' en cada vuelta; si esa deteccion fallaba, la
# ventana quedaba congelada en el primer mensaje. El segundo uso una
# tuberia con nombre (FIFO) para separar el prefijado "# " del resto, y
# demostro en pruebas quedarse esperando para siempre si el lector y el
# escritor no llegaban a sincronizarse a tiempo. El tercero (con
# alpine-update-root.sh ya escribiendo el prefijo "# " directamente)
# arreglo el avance en vivo, pero dejaba 'tail -f' corriendo para
# siempre a proposito -- lo cual resulto ser un error, no un costo
# aceptable: sin que la tuberia hacia Zenity reciba EOF, la barra
# --pulsate nunca deja de animarse y el boton para cerrar la ventana
# nunca se habilita, aunque el ultimo mensaje ya diga que todo termino.
#
# Ahora se usa 'tail --pid="$BGPID"' (coreutils, instalado junto con
# zenity mas arriba -- el 'tail' de BusyBox no soporta esta opcion):
# tail se detiene SOLO, automaticamente, en cuanto el trabajo de fondo
# ya no existe, sin necesidad de rastrear ni matar ningun proceso a
# mano. Eso le da a Zenity el EOF que estaba esperando para dejar de
# animarse y habilitar el cierre de la ventana.
tail -n1 -f --pid="$BGPID" "$LOG" | zenity --progress --pulsate \
    --title="Actualizando el sistema" \
    --text="Iniciando..." \
    --width=420 &
ZPID=$!

wait "$BGPID"
wait "$ZPID" 2>/dev/null

# --- Aviso de reinicio ---------------------------------------------
# modules.order pertenece al PAQUETE del kernel: desaparece al
# desinstalarse ese kernel, aunque en su directorio queden residuos sin
# dueno (p. ej. archivos generados por depmod), que harian que un simple
# "existe el directorio?" nunca detectara la actualizacion. Si el
# sistema no usa modules.order, se recurre a comprobar el directorio.
running="$(uname -r)"
reboot_needed="no"
if ls /lib/modules/*/modules.order >/dev/null 2>&1; then
    [ -f "/lib/modules/$running/modules.order" ] || reboot_needed="yes"
else
    [ -d "/lib/modules/$running" ] || reboot_needed="yes"
fi

release_after="$(cat /etc/alpine-release 2>/dev/null)"
if [ -n "$release_after" ] && [ "$release_after" != "$release_before" ] && [ "${release_after%.*}" != "${release_before%.*}" ]; then
    zenity --info --title="Alpine actualizado" \
        --text="El sistema ahora es Alpine $release_after.\n\nReinicia el equipo para terminar el cambio de version." \
        --width=380 2>/dev/null
elif [ "$reboot_needed" = "yes" ]; then
    zenity --warning --title="Reinicio necesario" \
        --text="Se instalo una version nueva del kernel (el nucleo del sistema).\n\nReinicia el equipo cuando puedas para empezar a usarla." \
        --width=380 2>/dev/null
fi
INNEREOF
    chmod 755 /usr/local/bin/alpine-update-launcher.sh
    chown root:root /usr/local/bin/alpine-update-launcher.sh

    # CORRECCION: el lanzador corre como el usuario normal, que NO puede
    # escribir en /var/log. Sin esto, 'tee -a' fallaba en silencio: la
    # ventana funcionaba, pero el log nunca se guardaba. Se crea el
    # archivo perteneciente al grupo 'wheel' (al que el usuario ya se
    # agrego arriba) con permiso de escritura para el grupo.
    touch /var/log/alpine-update.log
    chown root:wheel /var/log/alpine-update.log
    chmod 664 /var/log/alpine-update.log

    mkdir -p /usr/share/applications
    cat > /usr/share/applications/alpine-update.desktop <<'INNEREOF'
[Desktop Entry]
Type=Application
Name=Actualizar el sistema
Comment=Actualiza Alpine Linux y las aplicaciones Flatpak; ofrece pasar a la siguiente version estable
Exec=/usr/local/bin/alpine-update-launcher.sh
Icon=system-software-update
Terminal=false
Categories=System;
StartupNotify=true
INNEREOF

    log_ok "Acceso directo creado: aparecera como 'Actualizar el sistema' en el menu de aplicaciones."
    log_info "Al hacer clic, pedira la contrasena del usuario (no la de root, siempre que pertenezca al grupo 'wheel') y actualizara apk + flatpak."
    log_info "Si hay una version estable nueva de Alpine, el boton preguntara antes si se quiere cambiar a ella."
}

# BLOQUE 28: Permisos de grupo para Audio/Video/Impresión
# ------------------------------------------------------------------------------
setup_user_groups() {
    log_info "== Configurando permisos de grupo =="

    if [ -z "$TARGET_USER" ]; then
        log_warn "No se determinó un usuario estándar. Ejecuta manualmente: adduser <usuario> audio video lpadmin"
        return 0
    fi

    for grp in audio video lpadmin; do
        adduser "$TARGET_USER" "$grp" && log_ok "Agregado a '$grp'." || log_warn "No se pudo agregar a '$grp'."
    done
}

# ------------------------------------------------------------------------------
# BLOQUE 29: Menu de casillas con todas las decisiones al inicio
# ------------------------------------------------------------------------------
# Antes, las 9 preguntas aparecian repartidas a lo largo de una ejecucion
# larga, obligando a vigilar la terminal de principio a fin. Aqui se
# reunen en UNA pantalla al inicio (casillas con 'dialog', que funciona
# tanto en una consola TTY como en una terminal grafica), se confirma un
# resumen, y el resto del script corre solo, sin volver a preguntar.
#
# Aunque este bloque esta al final del archivo, main() lo ejecuta al
# principio, justo despues de detect_hardware(): la opcion de NVIDIA
# solo tiene sentido mostrarla si hay una NVIDIA.
#
# Los textos del menu van SIN acentos a proposito: el menu aparece antes
# de que el script configure el idioma, y en una consola TTY recien
# instalada los acentos pueden verse como simbolos extranos.
#
# Si el menu no se puede mostrar (sin terminal interactiva, o sin poder
# instalar 'dialog'), las variables OPT_* quedan vacias y want() vuelve
# a preguntar cada opcion por separado, como antes.
MENU_USED="no"

# Convierte yes/no al formato de estado de una casilla de dialog.
menu_state() {
    if [ "$1" = "yes" ]; then echo on; else echo off; fi
}

select_options_menu() {
    log_info "== Seleccion de acciones =="

    if [ ! -t 0 ] || [ ! -t 1 ]; then
        log_warn "No hay una terminal interactiva: se preguntara cada opcion por separado durante la ejecucion."
        return 0
    fi

    command -v dialog >/dev/null 2>&1 || install_pkgs dialog
    if ! command -v dialog >/dev/null 2>&1; then
        log_warn "No se pudo instalar 'dialog': se preguntara cada opcion por separado durante la ejecucion."
        return 0
    fi

    # Valores por defecto (casillas premarcadas). Criterios:
    #  - NVIDIA en modo seguro: marcado. En el hardware antiguo al que
    #    apunta este proyecto, el fallo de dejarlo desmarcado (pantalla
    #    negra) es mucho peor que el de marcarlo (perder la aceleracion
    #    de la NVIDIA, usando la otra GPU).
    #  - Flatpak y sus aplicaciones: desmarcados. Instalar Flatpak sin
    #    ninguna aplicacion seria infraestructura para nada; marcar
    #    OnlyOffice o Chrome activa Flatpak automaticamente.
    OPT_KEYBOARD=yes
    OPT_NVIDIA_SAFE=yes
    # Portatiles Optimus: en vez de la casilla de modo seguro se muestra
    # una segunda pantalla con tres modos; por defecto, el de ahorro
    # (probado en el K53SV, ver nvidia_apply_optimus).
    OPT_NVIDIA_MODE=""
    [ "$OPTIMUS_LAPTOP" = "yes" ] && OPT_NVIDIA_MODE="optimus"
    OPT_GCOMPAT=no
    OPT_CUPS=yes
    OPT_LIBREOFFICE=yes
    OPT_FIREFOX=yes
    OPT_FLATPAK=no
    OPT_ONLYOFFICE=no
    OPT_CHROME=no
    OPT_UPDATE_SHORTCUT=yes

    while :; do
        # Se arma la lista de casillas con los valores ACTUALES: si el
        # usuario vuelve desde el resumen, encuentra lo que ya habia
        # marcado, no los valores por defecto.
        set -- KEYBOARD "Teclado en distribucion latinoamericana (latam)" "$(menu_state "$OPT_KEYBOARD")"
        if [ "$GPU_HAS_NVIDIA" = "yes" ] && [ "$OPTIMUS_LAPTOP" = "no" ]; then
            set -- "$@" NVIDIA_SAFE "NVIDIA en modo seguro (evita pantalla negra)" "$(menu_state "$OPT_NVIDIA_SAFE")"
        fi
        set -- "$@" \
            GCOMPAT "gcompat: programas propietarios compilados con glibc" "$(menu_state "$OPT_GCOMPAT")" \
            CUPS "Impresoras (CUPS)" "$(menu_state "$OPT_CUPS")" \
            LIBREOFFICE "LibreOffice en espanol (paquete pesado)" "$(menu_state "$OPT_LIBREOFFICE")" \
            FIREFOX "Navegador Firefox" "$(menu_state "$OPT_FIREFOX")" \
            FLATPAK "Flatpak/Flathub (tienda de aplicaciones)" "$(menu_state "$OPT_FLATPAK")" \
            ONLYOFFICE "OnlyOffice via Flatpak (activa Flatpak)" "$(menu_state "$OPT_ONLYOFFICE")" \
            CHROME "Google Chrome via Flatpak, paquete comunitario" "$(menu_state "$OPT_CHROME")" \
            UPDATE_SHORTCUT "Boton 'Actualizar el sistema' en el menu" "$(menu_state "$OPT_UPDATE_SHORTCUT")"

        # Tamano "0 0 0": dialog calcula alto, ancho y alto de la lista
        # segun el contenido y la pantalla disponible. Con un tamano fijo
        # (antes 20x72), en pantallas amplias las descripciones quedaban
        # cortadas; en pantallas chicas dialog igual recorta la ventana y
        # la lista se vuelve desplazable, asi que no se pierde ninguna
        # opcion.
        # --no-tags: oculta los nombres internos (KEYBOARD, CUPS...), que
        # no le dicen nada al usuario y ocupaban ~17 columnas -- sin ellos,
        # todas las descripciones caben completas en una consola de 80
        # columnas. dialog SIGUE devolviendo esos nombres al confirmar, que
        # es lo que el script lee mas abajo (verificado).
        if ! sel="$(dialog --stdout --separate-output --no-tags \
                --backtitle "Configuracion post-instalacion de Alpine Linux" \
                --title "Acciones a realizar" \
                --ok-label "Continuar" --cancel-label "Salir" \
                --checklist "ESPACIO marca o desmarca, ENTER continua.\nDespues de confirmar, el script corre solo, sin mas preguntas." \
                0 0 0 "$@")"; then
            clear 2>/dev/null || true
            log_info "Configuracion cancelada por el usuario en el menu inicial. No se hicieron cambios."
            trap - EXIT INT TERM
            exit 0
        fi

        # Todo se reinicia a "no" y se marca "yes" solo lo seleccionado.
        # Las etiquetas se validan contra una lista fija antes del eval.
        for k in KEYBOARD NVIDIA_SAFE GCOMPAT CUPS LIBREOFFICE FIREFOX FLATPAK ONLYOFFICE CHROME UPDATE_SHORTCUT; do
            eval "OPT_$k=no"
        done
        for tag in $sel; do
            case "$tag" in
                KEYBOARD|NVIDIA_SAFE|GCOMPAT|CUPS|LIBREOFFICE|FIREFOX|FLATPAK|ONLYOFFICE|CHROME|UPDATE_SHORTCUT)
                    eval "OPT_$tag=yes" ;;
            esac
        done

        # Las aplicaciones Flatpak no pueden instalarse sin Flatpak.
        if [ "$OPT_ONLYOFFICE" = "yes" ] || [ "$OPT_CHROME" = "yes" ]; then
            OPT_FLATPAK=yes
        fi

        # Portatil Optimus: elegir que hacer con la NVIDIA. "Volver"
        # regresa a la pantalla de casillas.
        if [ "$OPTIMUS_LAPTOP" = "yes" ]; then
            if ! nv_sel="$(dialog --stdout --no-tags \
                    --backtitle "Configuracion post-instalacion de Alpine Linux" \
                    --title "Grafica NVIDIA (portatil con graficos hibridos)" \
                    --ok-label "Continuar" --cancel-label "Volver" \
                    --radiolist "Este portatil tiene una grafica integrada y una NVIDIA.\nFLECHAS para moverse, ESPACIO elige, ENTER continua." \
                    0 0 0 \
                    optimus "Apagarla y usar la integrada (ahorro, recomendado)" "$( [ "$OPT_NVIDIA_MODE" = optimus ] && echo on || echo off)" \
                    safe "Bloquearla por completo (sin driver)" "$( [ "$OPT_NVIDIA_MODE" = safe ] && echo on || echo off)" \
                    active "Dejarla activa con nouveau (riesgo en tarjetas viejas)" "$( [ "$OPT_NVIDIA_MODE" = active ] && echo on || echo off)")"; then
                continue
            fi
            case "$nv_sel" in
                optimus|safe|active) OPT_NVIDIA_MODE="$nv_sel" ;;
            esac
        fi

        summary=""
        [ "$OPT_KEYBOARD" = "yes" ]        && summary="$summary\n  - Teclado latinoamericano"
        [ "$GPU_HAS_NVIDIA" = "yes" ] && [ "$OPTIMUS_LAPTOP" = "no" ] && [ "$OPT_NVIDIA_SAFE" = "yes" ] && summary="$summary\n  - NVIDIA en modo seguro"
        case "$OPT_NVIDIA_MODE" in
            optimus) summary="$summary\n  - NVIDIA apagada, todo en la grafica integrada (ahorro)" ;;
            safe)    summary="$summary\n  - NVIDIA bloqueada (modo seguro)" ;;
            active)  summary="$summary\n  - NVIDIA activa con nouveau" ;;
        esac
        [ "$OPT_GCOMPAT" = "yes" ]         && summary="$summary\n  - gcompat"
        [ "$OPT_CUPS" = "yes" ]            && summary="$summary\n  - Impresoras (CUPS)"
        [ "$OPT_LIBREOFFICE" = "yes" ]     && summary="$summary\n  - LibreOffice"
        [ "$OPT_FIREFOX" = "yes" ]         && summary="$summary\n  - Firefox"
        [ "$OPT_FLATPAK" = "yes" ]         && summary="$summary\n  - Flatpak/Flathub"
        [ "$OPT_ONLYOFFICE" = "yes" ]      && summary="$summary\n  - OnlyOffice"
        [ "$OPT_CHROME" = "yes" ]          && summary="$summary\n  - Google Chrome"
        [ "$OPT_UPDATE_SHORTCUT" = "yes" ] && summary="$summary\n  - Boton de actualizacion"
        [ -z "$summary" ] && summary="\n  (ninguna opcional)"

        if dialog --title "Confirmar" \
                --yes-label "Comenzar" --no-label "Volver" \
                --yesno "Ademas de la configuracion base (red, audio, drivers, idioma, etc.), se instalara:\n$summary\n\nA partir de aqui el script no hara mas preguntas." \
                0 0; then
            break
        fi
        # "Volver" (o ESC): se repite el menu con las marcas actuales.
    done

    clear 2>/dev/null || true
    MENU_USED="yes"
    # '%b' interpreta los \n del resumen sin usarlo como cadena de
    # formato: si una descripcion llegara a contener un '%', printf no
    # lo confundiria con una directiva (antes: error y linea cortada).
    log_ok "Opciones elegidas en el menu:$(printf '%b' "$summary" | tr '\n' ' ')"
}

# ------------------------------------------------------------------------------
# BLOQUE 30: Aplicaciones de uso diario y aplicaciones predeterminadas
# ------------------------------------------------------------------------------
# Pensado para el usuario comun al que apunta el script: leer PDFs,
# reproducir audios y videos locales, y navegar. Cada aplicacion se
# registra ademas como PREDETERMINADA: instalarla no basta, porque varias
# aplicaciones se declaran capaces de abrir el mismo tipo de archivo (por
# ejemplo, LibreOffice Draw tambien abre PDF) y cual gana depende del
# escritorio. Los valores se escriben en /etc/xdg/mimeapps.list, el
# archivo de preferencias a nivel de sistema del estandar freedesktop.
# Limite conocido: si el usuario ya eligio otra aplicacion por su cuenta,
# su eleccion personal (~/.config/mimeapps.list) tiene prioridad.
MIMEAPPS="/etc/xdg/mimeapps.list"

# Imprime el primer archivo .desktop existente de la lista. Los nombres
# cambian entre versiones (evince, por ejemplo, usa org.gnome.Evince.desktop),
# asi que nunca se apunta a una aplicacion que no esta instalada.
find_desktop_file() {
    for d in "$@"; do
        if [ -f "/usr/share/applications/$d" ]; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

# Registra $1 (archivo .desktop) como predeterminado para los tipos MIME
# restantes, en la seccion [Default Applications]. Reemplaza una entrada
# previa del mismo tipo y conserva el resto del archivo intacto.
set_default_app() {
    app="$1"; shift
    mkdir -p /etc/xdg
    [ -f "$MIMEAPPS" ] || printf '[Default Applications]\n' > "$MIMEAPPS"
    grep -qx '\[Default Applications\]' "$MIMEAPPS" || printf '\n[Default Applications]\n' >> "$MIMEAPPS"
    for mime in "$@"; do
        awk -v m="$mime" -v a="$app" '
            /^\[/ { insec = ($0 == "[Default Applications]") }
            insec && index($0, m "=") == 1 { next }
            { print }
            $0 == "[Default Applications]" { print m "=" a }
        ' "$MIMEAPPS" > "$MIMEAPPS.tmp" && mv "$MIMEAPPS.tmp" "$MIMEAPPS"
    done
}

install_daily_apps() {
    log_info "== Aplicaciones de uso diario =="

    if [ "$DE_XFCE" = "no" ] && [ "$DE_PLASMA" = "no" ] && [ "$DE_GNOME" = "no" ] && [ "$DE_MATE" = "no" ] && [ "$DE_LXQT" = "no" ]; then
        log_warn "No se detecto un entorno de escritorio: se omiten las aplicaciones graficas."
        return 0
    fi

    # --- Visor de PDF ---
    # Okular en Plasma (se integra con el resto del escritorio); evince en
    # los demas (GTK, liviano). Si conviven Plasma y otro escritorio, se
    # instalan ambos y el predeterminado de sistema es evince.
    if [ "$DE_PLASMA" = "yes" ]; then
        install_pkgs okular
    fi
    if [ "$DE_XFCE" = "yes" ] || [ "$DE_GNOME" = "yes" ] || [ "$DE_MATE" = "yes" ] || [ "$DE_LXQT" = "yes" ]; then
        install_pkgs evince
    fi
    if pdf_app="$(find_desktop_file org.gnome.Evince.desktop evince.desktop okularApplication_pdf.desktop org.kde.okular.desktop)"; then
        set_default_app "$pdf_app" application/pdf
        log_ok "Visor de PDF predeterminado: $pdf_app"
    else
        log_warn "No se encontro el visor de PDF instalado; no se cambio la aplicacion predeterminada para PDF."
    fi

    # --- Reproductor multimedia ---
    # mpv: bajo consumo, trae controles en pantalla y usa la decodificacion
    # de video por hardware (VA-API) instalada en el Bloque 12. Cubre los
    # audios de WhatsApp (.ogg/.opus) y los videos descargados habituales.
    install_pkgs mpv
    if media_app="$(find_desktop_file mpv.desktop io.mpv.Mpv.desktop)"; then
        set_default_app "$media_app" \
            audio/ogg audio/x-opus+ogg audio/opus audio/mpeg audio/mp4 audio/aac \
            audio/x-wav audio/wav audio/flac audio/webm \
            video/mp4 video/webm video/x-matroska video/quicktime \
            video/x-msvideo video/3gpp video/mpeg video/ogg
        log_ok "Reproductor multimedia predeterminado: $media_app"
    else
        log_warn "No se encontro el reproductor instalado; no se cambiaron las aplicaciones predeterminadas de audio y video."
    fi

    # --- Navegador ---
    if want OPT_FIREFOX "¿Deseas instalar el navegador Firefox?"; then
        install_pkgs firefox
        if web_app="$(find_desktop_file firefox.desktop org.mozilla.firefox.desktop)"; then
            set_default_app "$web_app" x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml
            log_ok "Navegador predeterminado: $web_app"
        else
            log_warn "No se encontro Firefox instalado; no se cambio el navegador predeterminado."
        fi
        # No se fuerza el idioma: en su primer arranque, Firefox ofrece
        # descargar el paquete de idioma que coincide con el del sistema
        # (es_ES). Forzar otra variante requeriria descargas atadas a la
        # version exacta del navegador, que se romperian al actualizarlo.
        log_info "En su primer arranque, Firefox ofrecera cambiar su interfaz al idioma del sistema (espanol)."
    else
        log_info "Se omite Firefox."
    fi
}

# Recomendaciones que el script NO aplica por su cuenta (instalar
# extensiones sin que el usuario lo vea no es buena practica). Se
# muestran al final para que las vea quien ejecuto el script.
print_browser_recommendations() {
    command -v firefox >/dev/null 2>&1 || return 0
    log_info "== Recomendaciones para Firefox (instalar desde addons.mozilla.org) =="
    log_info "  - uBlock Origin: bloquea publicidad y rastreadores, lo que reduce la carga del procesador al navegar."
    log_info "  - enhanced-h264ify: en equipos antiguos, pide a YouTube video H.264, que la GPU puede decodificar"
    log_info "    por hardware; los formatos por defecto (VP9/AV1) terminan decodificandose en el procesador."
}

# ------------------------------------------------------------------------------
# BLOQUE 31: Función principal
# ------------------------------------------------------------------------------
main() {
    log_info "===== Iniciando configuración post-instalación de escritorio en Alpine Linux ====="

    check_root
    update_system
    # detect_hardware se ejecuta ANTES del menu (Bloque 29) para que la
    # opcion de NVIDIA solo aparezca si hay una NVIDIA.
    detect_hardware
    select_options_menu
    setup_keyboard_layout
    detect_desktop_environment
    detect_target_user
    setup_applets
    detect_wifi_hardware
    install_wifi_firmware
    detect_bluetooth_hardware
    install_bluetooth
    install_drivers
    check_unclaimed_devices
    detect_cpu
    install_microcode
    setup_zram
    setup_earlyoom
    setup_power
    optimize_hdd_storage
    setup_ssd_trim
    setup_usb_automount
    setup_printing
    install_archive_tools
    setup_locale_es
    install_fonts
    install_libreoffice
    install_daily_apps
    setup_flatpak
    setup_display_manager
    setup_update_shortcut
    setup_user_groups

    print_browser_recommendations
    log_ok "===== Proceso completado exitosamente ====="
    log_info "Reinicia el sistema para que todos los cambios surtan efecto."

    trap - EXIT INT TERM
}

main "$@"
