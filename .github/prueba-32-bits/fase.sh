#!/bin/sh
# Corre dentro de la máquina virtual de 32 bits en cada arranque (lo lanza
# /etc/local.d/prueba.start). Todo lo que importa se escribe en el puerto
# serie (/dev/ttyS0), que el flujo de GitHub guarda y revisa.
#
#   Arranque 1: espera la red, corre desktop-postinstall.sh completo con
#               el escritorio de /etc/prueba-escritorio, deja el inicio
#               automático de sesión y reinicia.
#   Arranque 2: espera a que la sesión del escritorio abra, mide la
#               memoria, pide la captura de pantalla y apaga.

S=/dev/ttyS0
decir() { printf '%s\n' "$*" > "$S"; }
ESC="$(printf '\033')"
sin_colores() { sed "s/${ESC}\[[0-9;]*m//g"; }

escritorio="$(cat /etc/prueba-escritorio)"

if [ ! -e /var/lib/prueba-fase1 ]; then
    decir "PRUEBA-ARRANQUE-1 $(cat /etc/alpine-release) arquitectura=$(apk --print-arch) kernel=$(uname -r) escritorio=$escritorio"
    decir "Procesador: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2-)"
    decir "Memoria total: $(awk '/MemTotal/ {print int($2/1024) " MB"}' /proc/meminfo)"

    i=0
    until wget -q --spider -T 5 https://dl-cdn.alpinelinux.org/alpine/ 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -lt 60 ] || { decir "PRUEBA-FALLO sin red"; poweroff; exit 1; }
        sleep 2
    done
    decir "Red lista. Corriendo desktop-postinstall.sh --escritorio $escritorio --full"

    inicio=$(date +%s)
    # La salida va a un archivo y no a una tubería: los servicios que el
    # script arranca heredan la salida, y con una tubería la dejarían
    # abierta para siempre (pasó con XFCE). Una copia se va mostrando por
    # el puerto serie.
    : > /root/salida.txt
    tail -f /root/salida.txt | sin_colores > "$S" &
    rc=0
    sh /root/desktop-postinstall.sh --escritorio "$escritorio" --full --usuario prueba \
        > /root/salida.txt 2>&1 < /dev/null || rc=$?
    sleep 2
    pkill -f 'tail -f /root/salida.txt' 2>/dev/null || true
    decir "PRUEBA-SCRIPT rc=$rc minutos=$(( ($(date +%s) - inicio) / 60 ))"

    decir "=== Avisos y errores del script ==="
    sin_colores < /var/log/desktop-postinstall.log | grep -E '^\[(WARN|ERROR)\]' > "$S" || decir "(ninguno)"

    decir "=== Programas instalados ==="
    for p in firefox libreoffice vlc mpv pipe-viewer pipe-viewer-gtk yt-dlp fastfetch btop flatpak cups \
             gnome-software lightdm sddm xorg-server lxqt-session xfce4-session icewm lxsession pcmanfm networkmanager pipewire; do
        if apk info -e "$p" >/dev/null 2>&1; then
            decir "PRUEBA-PAQUETE $p si $(apk info -e -v "$p" 2>/dev/null)"
        else
            decir "PRUEBA-PAQUETE $p no"
        fi
    done
    # En 32 bits Flathub no tiene programas: el script no debe instalar
    # Flatpak ni dejar aplicaciones "pendientes" que nunca llegarian.
    if [ -e /etc/flatpak-pendientes ] || apk info -e flatpak >/dev/null 2>&1; then
        decir "PRUEBA-FALLO en 32 bits quedo Flatpak instalado o con aplicaciones pendientes:"
        cat /etc/flatpak-pendientes > "$S" 2>/dev/null
    else
        decir "PRUEBA-SIN-FLATPAK-OK"
    fi
    decir "Disco usado: $(df -h / | awk 'NR==2 {print $3}')"

    if [ "$rc" != 0 ]; then
        decir "PRUEBA-FALLO el script terminó con error $rc"
        decir "=== Últimas 80 líneas del registro ==="
        sin_colores < /var/log/desktop-postinstall.log | tail -n 80 > "$S"
        poweroff
        exit 1
    fi

    # Inicio automático de sesión, con la misma herramienta que usa la ISO
    # de Lázaro (sirve para LightDM, SDDM y GDM).
    mkdir -p /etc/lazaro
    echo prueba > /etc/lazaro/autologin
    /usr/local/sbin/lazaro-autologin > "$S" 2>&1 || decir "Aviso: lazaro-autologin terminó con error"

    touch /var/lib/prueba-fase1
    sync
    decir "PRUEBA-REINICIO"
    reboot
    exit 0
fi

# ---- Arranque 2: la sesión del escritorio ----
decir "PRUEBA-ARRANQUE-2"
case "$escritorio" in
    lxqt) proceso=lxqt-session ;;
    xfce) proceso=xfce4-session ;;
    mate) proceso=mate-session ;;
    icewm) proceso=icewm ;;
    *)    proceso="$escritorio" ;;
esac

i=0
until pgrep -x "$proceso" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 150 ]; then
        decir "PRUEBA-FALLO la sesión ($proceso) no abrió en 5 minutos"
        decir "=== Servicios ==="; rc-status > "$S" 2>&1
        decir "=== Xorg ==="; grep -E '\((EE|WW)\)' /var/log/Xorg.0.log > "$S" 2>&1
        decir "PRUEBA-CAPTURA"; sleep 15
        decir "PRUEBA-FIN"
        poweroff
        exit 1
    fi
    sleep 2
done
decir "PRUEBA-SESION-OK $proceso abrió en $((i * 2)) s"

# Se deja asentar la sesión (programas que arrancan solos, avisos...).
sleep 90

# IceWM: lo que debe arrancar con la sesión de LXDE, y el menú de
# aplicaciones tal como lo ve el usuario.
if [ "$escritorio" = icewm ]; then
    falta=""
    for p in lxsession pcmanfm nm-applet lxpolkit; do
        pgrep -x "$p" >/dev/null 2>&1 || falta="$falta $p"
    done
    if [ -z "$falta" ]; then
        decir "PRUEBA-ICEWM-OK lxsession, pcmanfm, nm-applet y lxpolkit corriendo"
    else
        decir "PRUEBA-FALLO IceWM: no están corriendo:$falta"
        ps -o pid,user,args > "$S" 2>&1 || ps > "$S" 2>&1
    fi
    decir "=== Barra de IceWM (/etc/icewm/toolbar) ==="
    cat /etc/icewm/toolbar > "$S" 2>&1
    decir "=== Avisos de la sesión (.xsession-errors) ==="
    tail -n 40 /home/prueba/.xsession-errors > "$S" 2>&1
    decir "=== Cargadores de imágenes (SVG para los íconos Papirus) ==="
    ls /usr/lib/gdk-pixbuf-2.0/*/loaders/ > "$S" 2>&1
    decir "=== IceWM: opciones de la barra de herramientas ==="
    grep -i -n 'toolbar' /usr/share/icewm/preferences > "$S" 2>&1 || true
    strings /usr/bin/icewm 2>/dev/null | grep -i 'toolbar' | head -n 20 > "$S" 2>&1 || true
    decir "=== IceWM: bibliotecas de imagen ==="
    ldd /usr/bin/icewm 2>&1 | grep -i -E 'pixbuf|imlib|rsvg|png|xpm' > "$S" 2>&1 || true
    decir "=== Paquetes con cargador SVG ==="
    apk info -L librsvg 2>/dev/null | grep -i -E 'loader|pixbuf' > "$S" 2>&1 || true
    apk search -q 'librsvg*' 'gdk-pixbuf*' 2>/dev/null > "$S" || true
    decir "=== Registro de lxsession ==="
    tail -n 30 /home/prueba/.cache/lxsession/icewm-lxde/run.log > "$S" 2>&1 || true
    decir "=== Menú de aplicaciones de IceWM ==="
    su -s /bin/sh prueba -c 'LANG=es_ES.UTF-8 /usr/local/libexec/icewm-lxde/menu-aplicaciones' > "$S" 2>&1
fi

decir "=== Memoria con la sesión abierta y sin programas (MB) ==="
free -m > "$S"
decir "PRUEBA-MEMORIA usada=$(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {print int((t-a)/1024)}' /proc/meminfo) disponible=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)"
decir "=== Los 15 procesos que más memoria usan (MB) ==="
for d in /proc/[0-9]*; do
    awk -v n="$(cat "$d/comm" 2>/dev/null)" '/^VmRSS/ {printf "%6.1f %s\n", $2/1024, n}' "$d/status" 2>/dev/null
done | sort -rn | head -n 15 > "$S"
decir "=== Zram ==="
cat /proc/swaps > "$S" 2>&1

decir "PRUEBA-CAPTURA"
sleep 15
decir "PRUEBA-FIN"
poweroff
