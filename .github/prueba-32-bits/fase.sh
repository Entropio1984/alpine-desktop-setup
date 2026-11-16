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
    pgrep -f icewm-lxde/volumen >/dev/null 2>&1 || falta="$falta volumen"
    if [ -z "$falta" ]; then
        decir "PRUEBA-ICEWM-OK lxsession, pcmanfm, nm-applet, lxpolkit y volumen corriendo"
    else
        decir "PRUEBA-FALLO IceWM: no están corriendo:$falta"
        ps -o pid,user,args > "$S" 2>&1 || ps > "$S" 2>&1
        case "$falta" in *volumen*)
            decir "=== Volumen: arranque a mano (errores) ==="
            su -s /bin/sh prueba -c 'DISPLAY=:0 timeout 8 /usr/local/libexec/icewm-lxde/volumen' > "$S" 2>&1
            decir "=== Autostart y run.log de lxsession ==="
            cat /etc/xdg/lxsession/icewm-lxde/autostart > "$S" 2>&1
            tail -n 20 /home/prueba/.cache/lxsession/icewm-lxde/run.log > "$S" 2>&1
        esac
    fi
    # IceWM no abre SVG: sin los iconos en PNG, la barra y el menú
    # quedan sin iconos.
    iconos=$(find /usr/share/icewm-lxde/iconos -name '*_16x16.png' 2>/dev/null | wc -l)
    if [ "$iconos" -ge 10 ]; then
        decir "PRUEBA-ICEWM-ICONOS-OK $iconos iconos en PNG"
    else
        decir "PRUEBA-FALLO IceWM: solo $iconos iconos en PNG (barra y menú sin iconos)"
    fi
    # Opciones que usa el script y que IceWM debe conocer (si una cambia
    # de nombre, IceWM la ignora en silencio).
    for op in $(sed -n 's/^\([A-Za-z][A-Za-z0-9]*\)=.*/\1/p' /etc/icewm/preferences); do
        # Theme vale aunque no figure en la lista de ejemplo de IceWM.
        [ "$op" = Theme ] && continue
        grep -q "^# *$op=" /usr/share/icewm/preferences \
            || decir "PRUEBA-FALLO IceWM no conoce la opción $op"
    done
    decir "=== Barra de IceWM (/etc/icewm/toolbar) ==="
    cat /etc/icewm/toolbar > "$S" 2>&1
    decir "=== Avisos de la sesión (.xsession-errors) ==="
    tail -n 20 /home/prueba/.xsession-errors > "$S" 2>&1 || true
    decir "=== Menú de aplicaciones de IceWM ==="
    su -s /bin/sh prueba -c 'LANG=es_ES.UTF-8 /usr/local/libexec/icewm-lxde/menu-aplicaciones' > "$S" 2>&1
fi

# IceWM: el escritorio de PCManFM. Debe tener de fondo la imagen de la
# distribución (preparar.sh deja la de Lázaro), la papelera (necesita el
# bus de D-Bus de la sesión) y "Usar como fondo del escritorio" en el
# clic derecho de una foto. Después se pone otra foto de fondo con esa
# misma orden, como lo haría la persona.
if [ "$escritorio" = icewm ]; then
    decir "=== Escritorio de IceWM (PCManFM) ==="
    conf=/home/prueba/.config/pcmanfm/icewm-lxde/desktop-items-0.conf
    pid=$(pgrep -x pcmanfm | head -n 1)
    U="XAUTHORITY=/home/prueba/.Xauthority $(tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -E '^(DBUS_SESSION_BUS_ADDRESS|DISPLAY|LANG|XDG_[A-Z_]*)=' | sed "s/=\(.*\)/='\1'/" | tr '\n' ' ')"
    falla=""
    grep -q '^wallpaper=/usr/share/backgrounds/lazaro/' "$conf" 2>/dev/null || falla="$falla sin-fondo-de-la-distribucion"
    su -s /bin/sh prueba -c "$U gio info trash:/// >/dev/null 2>&1" || falla="$falla sin-papelera"
    grep -q 'icewm-lxde/fondo' /usr/share/file-manager/actions/icewm-lxde-fondo.desktop 2>/dev/null || falla="$falla sin-usar-como-fondo"
    foto=/home/prueba/foto-de-prueba.png
    rsvg-convert -w 256 -h 256 "$(find /usr/share/icons/Papirus -name 'firefox.svg' | head -n 1)" -o "$foto" 2>/dev/null
    chown prueba:prueba "$foto"
    su -s /bin/sh prueba -c "$U /usr/local/libexec/icewm-lxde/fondo $foto" > "$S" 2>&1
    sleep 5
    grep -q "^wallpaper=$foto" "$conf" 2>/dev/null || falla="$falla usar-como-fondo-no-cambio-el-fondo"
    cat "$conf" > "$S" 2>&1
    if [ -z "$falla" ]; then
        decir "PRUEBA-ICEWM-ESCRITORIO-OK fondo con imagen, papelera y 'Usar como fondo del escritorio'"
    else
        decir "PRUEBA-FALLO IceWM, escritorio:$falla"
    fi
    # La captura final muestra el fondo de la distribución.
    su -s /bin/sh prueba -c "$U /usr/local/libexec/icewm-lxde/fondo /usr/share/backgrounds/lazaro/lazaro-fondo.jpg" > "$S" 2>&1
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

# IceWM: una ventana abierta en la captura, para ver la barra de título
# con sus botones (después de medir la memoria, para no sumarla).
if [ "$escritorio" = icewm ] && command -v lxterminal >/dev/null 2>&1; then
    DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 lxterminal >/dev/null 2>&1 &
    sleep 10
    # Con la ventana abierta, abrir el menú con un clic en el botón de la
    # barra (abajo a la izquierda) y pasar el mouse por la primera
    # categoría: la captura debe mostrar el menú encima de la ventana y
    # el submenú abierto sin otro clic.
    if apk add -q xdotool > "$S" 2>&1; then
        export DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0
        alto=$(xdotool getdisplaygeometry | cut -d' ' -f2)
        decir "=== Ventanas antes de abrir el menú ==="
        xdotool search --onlyvisible --name . getwindowname %@ > "$S" 2>&1 || true
        xdotool mousemove 12 $((alto - 10)) click 1
        sleep 3
        decir "=== Ventanas con el menú abierto ==="
        xdotool search --onlyvisible --name . getwindowname %@ > "$S" 2>&1 || true
        xdotool mousemove_relative -- 60 -80
        sleep 1
        xdotool mousemove_relative -- 10 -10
        sleep 3
        unset DISPLAY XAUTHORITY
    else
        decir "PRUEBA-AVISO no se pudo instalar xdotool para abrir el menú"
    fi
fi

decir "PRUEBA-CAPTURA"
sleep 15

# IceWM: programa de capturas. Primero una captura sin ventana (que
# funcione sin GNOME Shell); después la tecla Imprimir debe abrir su
# ventana, que sale en la segunda captura.
if [ "$escritorio" = icewm ] && command -v xdotool >/dev/null 2>&1; then
    export DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0
    xdotool key Escape; sleep 1
    decir "=== Tamaño en disco del programa de capturas ==="
    apk info -s gnome-screenshot libhandy1 > "$S" 2>&1
    rm -f /tmp/prueba-captura.png
    timeout 30 gnome-screenshot -f /tmp/prueba-captura.png > "$S" 2>&1
    if [ -s /tmp/prueba-captura.png ]; then
        decir "PRUEBA-CAPTURAS-OK gnome-screenshot guardó $(wc -c < /tmp/prueba-captura.png) bytes"
    else
        decir "PRUEBA-FALLO gnome-screenshot no guardó la captura"
    fi
    xdotool key Print
    ventana=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 2
        ventana=$(xdotool search --onlyvisible --class gnome-screenshot 2>/dev/null | head -n 1)
        [ -n "$ventana" ] && break
    done
    if [ -n "$ventana" ]; then
        decir "PRUEBA-CAPTURAS-TECLA-OK Imprimir abrió la ventana de capturas"
        decir "=== Memoria de la ventana de capturas (MB) ==="
        for d in /proc/[0-9]*; do
            awk -v n="$(cat "$d/comm" 2>/dev/null)" '/^VmRSS/ && n ~ /screenshot/ {printf "%6.1f %s\n", $2/1024, n}' "$d/status" 2>/dev/null
        done > "$S"
        decir "PRUEBA-OTRA-CAPTURA"
        sleep 15
    else
        decir "PRUEBA-FALLO la tecla Imprimir no abrió la ventana de capturas"
        ps -o pid,args > "$S" 2>&1 || true
    fi
    unset DISPLAY XAUTHORITY
fi
decir "PRUEBA-FIN"
poweroff
