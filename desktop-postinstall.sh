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
# algo que ha pasado varias veces con este script (amd-ucode, unrar,
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

# ------------------------------------------------------------------------------
# BLOQUE 3: Distribución de teclado a "latam" (consola + sesión gráfica)
# ------------------------------------------------------------------------------
setup_keyboard_layout() {
    log_info "== Distribución de teclado =="

    if ! ask_yes_no "¿Deseas configurar el teclado a distribución latinoamericana (latam)?"; then
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
setup_applets() {
    log_info "== Configurando servicios base de red y audio =="

    install_pkgs networkmanager networkmanager-wifi wpa_supplicant pulseaudio pulseaudio-alsa

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

    command -v lspci >/dev/null 2>&1 || install_pkg "pciutils"
    command -v lsusb >/dev/null 2>&1 || install_pkg "usbutils"

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
# El paquete generico "linux-firmware" (instalado en el bloque de drivers
# de GPU) NO incluye el firmware especifico de cada chipset WiFi -- Alpine
# lo divide en decenas de subpaquetes por fabricante (linux-firmware-intel,
# linux-firmware-realtek, linux-firmware-ath9k_htc, etc.), igual que ya
# pasaba con las GPU. Sin el subpaquete correcto, el driver del kernel
# puede cargar pero la tarjeta jamas asocia a una red (o ni siquiera
# aparece), y NetworkManager/wpa_supplicant (instalados en el bloque de
# applets) no tienen nada que hacer sin el firmware presente.
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

    command -v lspci >/dev/null 2>&1 || install_pkg "pciutils"
    command -v lsusb >/dev/null 2>&1 || install_pkg "usbutils"

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

    # pulseaudio-bluez es el "puente" que enruta el perfil A2DP hacia
    # PulseAudio -- sin este paquete, bluez permite emparejar el
    # dispositivo pero los audifonos/altavoces Bluetooth no emiten sonido.
    install_pkgs bluez bluez-openrc pulseaudio-bluez

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

detect_hardware() {
    log_info "== Detectando hardware gráfico =="
    command -v lspci >/dev/null 2>&1 || install_pkg "pciutils"

    if ! command -v lspci >/dev/null 2>&1; then
        log_error "No fue posible obtener 'lspci'. Se omitirá la detección automática de GPU."
        return 0
    fi

    log_info "Componentes PCI detectados:"
    lspci | tee -a "$LOG_FILE"

    vga_line="$(lspci | grep -Ei 'VGA compatible controller|3D controller' || true)"
    GPU_COUNT="$(lspci | grep -cEi 'VGA compatible controller|3D controller' || true)"

    if [ -z "$vga_line" ]; then
        log_warn "No se detectó ningún controlador de video vía lspci."
        return 0
    fi

    log_info "Controlador(es) de video encontrado(s):"
    log_info "$vga_line"

    echo "$vga_line" | grep -qi "intel" && GPU_HAS_INTEL="yes"
    echo "$vga_line" | grep -Eq "AMD|ATI|Radeon" && GPU_HAS_AMD="yes"
    echo "$vga_line" | grep -qi "nvidia" && GPU_HAS_NVIDIA="yes"
    echo "$vga_line" | grep -Eqi "virtio|vmware|virtualbox|qxl" && GPU_HAS_VIRTUAL="yes"

    log_ok "Resumen GPU -> Intel:$GPU_HAS_INTEL AMD:$GPU_HAS_AMD NVIDIA:$GPU_HAS_NVIDIA Virtual:$GPU_HAS_VIRTUAL (adaptadores detectados: $GPU_COUNT)"

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
# BLOQUE 12: Firmware y controladores de video (protección NVIDIA Legacy)
# ------------------------------------------------------------------------------
install_drivers() {
    log_info "== Instalando firmware y controladores =="

    # NOTA IMPORTANTE: NO se instala el paquete generico "linux-firmware".
    # Se confirmo que ese paquete DEPENDE de (arrastra) practicamente
    # todos sus ~113 subpaquetes de fabricante -- instalarlo anularia
    # todo el trabajo de deteccion especifica de este bloque y traeria
    # cientos de MB de firmware irrelevante. Solo se instalan los
    # subpaquetes que corresponden al hardware realmente detectado.
    install_pkgs mesa-dri-gallium mesa-gl mesa-egl

    if [ "$GPU_HAS_INTEL" = "yes" ]; then
        log_info "Instalando firmware Intel..."
        install_pkgs linux-firmware-i915 mesa-vulkan-intel
    fi

    if [ "$GPU_HAS_AMD" = "yes" ]; then
        log_info "Instalando firmware y Vulkan para AMD/Radeon..."
        install_pkgs linux-firmware-amdgpu linux-firmware-radeon mesa-vulkan-ati mesa-vulkan-radeon vulkan-loader
    fi

    if [ "$GPU_HAS_VIRTUAL" = "yes" ]; then
        log_info "Entorno virtualizado detectado. Instalando utilidades QEMU/KVM/VirtualBox..."
        install_pkgs xf86-video-vmware xf86-video-qxl spice-vdagent
        rc-update add spice-vdagentd default || log_warn "Fallo al habilitar spice-vdagentd."
    fi

    if [ "$GPU_HAS_NVIDIA" = "yes" ]; then
        log_info "Instalando soporte NVIDIA (driver abierto Nouveau, vía Gallium)..."
        install_pkgs linux-firmware-nvidia

        if [ "$GPU_COUNT" -gt 1 ]; then
            log_warn "Configuración híbrida detectada ($GPU_COUNT adaptadores, ej. Optimus)."
            log_warn "Aunque exista una GPU integrada de respaldo, Xorg puede seguir intentando inicializar aceleración 3D sobre nouveau y colgar el arranque en tarjetas Fermi/Kepler antiguas."
        else
            log_warn "Se detectó NVIDIA como única tarjeta gráfica (sin gráfica integrada de respaldo)."
        fi
        log_warn "En tarjetas NVIDIA antiguas (Tesla/Fermi/Kepler), Nouveau puede causar pantalla negra o cuelgues al iniciar Xorg."

        log_info "Opción 's': bloquea la NVIDIA por completo (kernel + Xorg) y usa solo la GPU restante. Modo seguro, recomendado en hardware Legacy."
        log_info "Opción 'n': deja Nouveau activo con aceleración 3D normal en la NVIDIA. Riesgo de pantalla negra/cuelgue en tarjetas antiguas."

        if ask_yes_no "¿Bloquear la NVIDIA y usar solo la GPU restante (modo seguro)?"; then
            log_info "Aplicando protección: NoAccel en Xorg + bloqueo del módulo nouveau en el kernel..."

            install_pkg "xf86-video-nouveau"
            mkdir -p /etc/X11/xorg.conf.d
            cat > /etc/X11/xorg.conf.d/20-nouveau-safe.conf <<EOF
Section "Device"
    Identifier "Nvidia Legacy Failsafe"
    Driver "nouveau"
    Option "NoAccel" "True"
EndSection
EOF

            mkdir -p /etc/modprobe.d
            cat > /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

            log_ok "Protección aplicada: /etc/X11/xorg.conf.d/20-nouveau-safe.conf + /etc/modprobe.d/blacklist-nouveau.conf"
            log_info "La NVIDIA quedará inactiva; el sistema usará solo la(s) GPU(s) restante(s). Para revertir: borra ambos archivos y reinicia."
        else
            log_info "Se mantiene Nouveau activo sin restricciones (NVIDIA con aceleración 3D normal)."
        fi
    fi

    if [ "$GPU_HAS_INTEL" = "no" ] && [ "$GPU_HAS_AMD" = "no" ] && [ "$GPU_HAS_NVIDIA" = "no" ] && [ "$GPU_HAS_VIRTUAL" = "no" ]; then
        log_warn "GPU no identificada. mesa-dri-gallium ya cubre software rendering (llvmpipe) de respaldo."
    fi

    log_ok "Instalación de firmware y controladores finalizada."
}

# ------------------------------------------------------------------------------
# BLOQUE 13: Detección de CPU y microcódigo
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
}

install_microcode() {
    log_info "== Instalando microcódigo de CPU =="
    case "$CPU_VENDOR" in
        intel)
            install_pkg "intel-ucode"
            ;;
        amd)
            install_pkg "linux-firmware-amd"
            log_info "AMD no tiene paquete 'amd-ucode' en Alpine; el microcódigo viene en linux-firmware-amd*."
            ;;
        *)
            log_warn "Fabricante de CPU no identificado. Se omite instalación de microcódigo."
            ;;
    esac
    log_warn "Verifica que se cargó en el arranque con: dmesg | grep -i microcode"
}

# ------------------------------------------------------------------------------
# BLOQUE 14: zram (memoria comprimida al 100% de la RAM física)
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
# BLOQUE 15: EarlyOOM
# ------------------------------------------------------------------------------
setup_earlyoom() {
    log_info "== Configurando EarlyOOM =="
    install_pkgs earlyoom earlyoom-openrc
    rc-update add earlyoom default || log_warn "No se pudo agregar 'earlyoom' al runlevel default."
    log_ok "EarlyOOM configurado."
}

# ------------------------------------------------------------------------------
# BLOQUE 16: Gestión de energía básica (ACPI)
# ------------------------------------------------------------------------------
setup_power() {
    log_info "== Configurando gestión de energía (ACPI) =="
    install_pkgs acpid acpid-openrc
    rc-update add acpid default || log_warn "No se pudo agregar 'acpid' al runlevel default."
    log_ok "acpid configurado."
}

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# BLOQUE 17: Optimizacion de discos duros mecanicos (HDD)
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

    found_rotational="no"
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
            log_info "Disco mecanico detectado: /dev/$devname"
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
ACTION=="add|change", KERNEL=="sd[a-z]|hd[a-z]|vd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="$chosen_scheduler"
EOF

    log_ok "Planificador '$chosen_scheduler' configurado para discos mecanicos en /etc/udev/rules.d/60-ioscheduler.rules"
    log_info "Sugerencia manual (no aplicada automaticamente): agregar 'noatime' a las opciones de montaje en /etc/fstab reduce escrituras innecesarias en discos mecanicos."
}

# BLOQUE 18: Montaje automático de USB (udisks2 + polkit + gvfs por DE)
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
# BLOQUE 19: Soporte de impresión (CUPS)
# ------------------------------------------------------------------------------
setup_printing() {
    log_info "== Soporte de impresión (CUPS) =="

    if ! ask_yes_no "¿Deseas instalar soporte de impresión (CUPS)?"; then
        log_info "Se omite CUPS."
        return 0
    fi

    log_info "== Configurando soporte de impresión (CUPS) =="
    install_pkgs cups cups-openrc cups-filters system-config-printer
    rc-update add cupsd default || log_warn "No se pudo agregar 'cupsd' al runlevel default."
    log_ok "CUPS configurado. Interfaz web disponible en http://localhost:631"
}

# ------------------------------------------------------------------------------
# BLOQUE 20: Backends de compresión
# ------------------------------------------------------------------------------
# NOTA: "unrar" NO existe como paquete en Alpine (ni en main ni en
# community, verificado en v3.24) - es de licencia no-libre y Alpine no
# lo empaqueta. No se automatiza su instalación manual porque cada
# versión de rarlab.com cambia de nombre de archivo y una URL fija en
# el script quedaría rota sin previo aviso.
install_archive_tools() {
    log_info "== Instalando utilidades de compresión =="
    install_pkgs zip unzip p7zip
    log_warn "'unrar' no está disponible en los repos de Alpine (licencia no-libre)."
    log_info "Para soporte de RAR, instala manualmente el binario oficial desde https://www.rarlab.com/download.htm"
    log_ok "Backends de compresión instalados (zip/unzip/7z)."
}

# ------------------------------------------------------------------------------
# BLOQUE 21: Idioma español — sistema, XFCE y propagación global a Plasma
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
            mkdir -p "$TARGET_HOME/.config"
            cat > "$TARGET_HOME/.config/plasma-localerc" <<'EOF'
[Formats]
LANG=es_ES.UTF-8

[Translations]
LANGUAGE=es_ES:es
EOF
            chown "$TARGET_USER":"$TARGET_USER" "$TARGET_HOME/.config/plasma-localerc" 2>/dev/null || true
            log_ok "Capa 3/3: idioma de Plasma pre-configurado también para el usuario existente '$TARGET_USER'."
        else
            log_warn "No se detectó un usuario existente; solo quedó el default de sistema en /etc/xdg/plasma-localerc."
        fi
    fi

    log_ok "Idioma español configurado para el/los entorno(s) detectado(s)."
}

# ------------------------------------------------------------------------------
# BLOQUE 22: Tipografías base (antes de LibreOffice)
# ------------------------------------------------------------------------------
install_fonts() {
    log_info "== Instalando tipografías base =="
    install_pkgs ttf-dejavu font-liberation font-liberation-sans-narrow font-noto
    log_ok "Tipografías base instaladas."
}

# ------------------------------------------------------------------------------
# BLOQUE 23: LibreOffice + paquete de idioma español
# ------------------------------------------------------------------------------
install_libreoffice() {
    log_info "== LibreOffice =="

    if ! ask_yes_no "¿Deseas instalar LibreOffice? (paquete pesado; si prefieres OnlyOffice vía Flatpak, puedes responder 'n' aquí y aceptarlo más adelante)"; then
        log_info "Se omite LibreOffice."
        return 0
    fi

    log_info "== Instalando LibreOffice (español) =="
    install_pkgs libreoffice libreoffice-lang-es
    log_ok "LibreOffice instalado con soporte de idioma español."
}

# ------------------------------------------------------------------------------
# BLOQUE 24: Flatpak + Flathub (OnlyOffice y Google Chrome, opcionales)
# ------------------------------------------------------------------------------
setup_flatpak() {
    log_info "== Flatpak / Flathub =="

    if ! ask_yes_no "¿Deseas habilitar Flatpak/Flathub en este sistema? (necesario solo si planeas instalar apps como OnlyOffice o Chrome desde Flathub)"; then
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

    if ask_yes_no "¿Deseas instalar OnlyOffice Desktop Editors vía Flatpak?"; then
        $remote_add_cmd install -y flathub org.onlyoffice.desktopeditors && log_ok "OnlyOffice instalado." || log_warn "Fallo al instalar OnlyOffice."
    else
        log_info "Se omite OnlyOffice."
    fi

    if ask_yes_no "¿Deseas instalar Google Chrome vía Flatpak (paquete comunitario, no oficial de Google)?"; then
        $remote_add_cmd install -y flathub com.google.Chrome && log_ok "Google Chrome instalado." || log_warn "Fallo al instalar Google Chrome."
    else
        log_info "Se omite Google Chrome."
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 25: Habilitar el Gestor de Inicio de Sesión (Display Manager)
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
# BLOQUE 26: Permisos de grupo para Audio/Video/Impresión
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
# BLOQUE 27: Función principal
# ------------------------------------------------------------------------------
main() {
    log_info "===== Iniciando configuración post-instalación de escritorio en Alpine Linux ====="

    check_root
    update_system
    setup_keyboard_layout
    detect_desktop_environment
    detect_target_user
    setup_applets
    detect_wifi_hardware
    install_wifi_firmware
    detect_bluetooth_hardware
    install_bluetooth
    detect_hardware
    install_drivers
    detect_cpu
    install_microcode
    setup_zram
    setup_earlyoom
    setup_power
    optimize_hdd_storage
    setup_usb_automount
    setup_printing
    install_archive_tools
    setup_locale_es
    install_fonts
    install_libreoffice
    setup_flatpak
    setup_display_manager
    setup_user_groups

    log_ok "===== Proceso completado exitosamente ====="
    log_info "Reinicia el sistema para que todos los cambios surtan efecto."

    trap - EXIT INT TERM
}

main "$@"
