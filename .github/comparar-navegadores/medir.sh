#!/bin/sh
# Compara navegadores de Alpine de 32 bits en varias páginas.
#
# Corre dentro de un contenedor Alpine x86 con 1 procesador y 1 GB de
# memoria (como un equipo viejo), con una pantalla virtual (Xvfb) de
# 1024x768. Por cada navegador y página: lo abre, mira durante $VENTANA
# segundos y anota
#   - carga: segundos hasta que el navegador deja de usar el procesador
#     (aproximación del tiempo de carga de la página);
#   - cpu: segundos de procesador gastados en total;
#   - mem: memoria máxima (PSS, en MB) de todos sus procesos;
# y saca una captura para ver si la página se ve bien o sale rota.
#
# Uso: medir.sh SALIDA NAVEGADOR...   (sitios en $SITIOS)
set -u
SALIDA="$1"; shift
VENTANA="${VENTANA:-40}"
mkdir -p "$SALIDA"

apk add -q xvfb imagemagick font-dejavu font-noto dbus dbus-x11 \
    ca-certificates mesa-dri-gallium >/dev/null
adduser -D nav 2>/dev/null || true

Xvfb :9 -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &
export DISPLAY=:9
# WebKitGTK (Epiphany, Badwolf, Surf) aísla las páginas con bubblewrap,
# que no funciona dentro de un contenedor sin privilegios. Solo para la
# medición.
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
sleep 2

uid=$(id -u nav)

# PSS y tiempo de procesador de todos los procesos del usuario nav.
muestra() {
    pss=0; cpu=0
    for d in /proc/[0-9]*; do
        [ "$(awk '/^Uid:/ {print $2}' "$d/status" 2>/dev/null)" = "$uid" ] || continue
        p=$(awk '/^Pss:/ {print $2}' "$d/smaps_rollup" 2>/dev/null)
        pss=$((pss + ${p:-0}))
        # Campos 14 y 15 de /proc/PID/stat: tiempo de usuario y de sistema.
        c=$(sed 's/.*) //' "$d/stat" 2>/dev/null | awk '{print $12 + $13}')
        cpu=$((cpu + ${c:-0}))
    done
    echo "$pss $cpu"
}

limpiar() {
    pkill -KILL -u nav 2>/dev/null
    sleep 1
    rm -rf /home/nav/.mozilla /home/nav/.cache /home/nav/.config /home/nav/.local /home/nav/.netsurf /home/nav/.dillo /home/nav/perfil-ff
}

orden() { # NAVEGADOR URL -> comando (como nav)
    case "$1" in
        firefox)
            mkdir -p /home/nav/perfil-ff
            cat > /home/nav/perfil-ff/user.js <<'FF'
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("app.update.enabled", false);
user_pref("dom.ipc.processCount", 2);
user_pref("dom.ipc.processCount.webIsolated", 1);
FF
            chown -R nav /home/nav/perfil-ff
            echo "firefox --no-remote --profile /home/nav/perfil-ff '$2'" ;;
        epiphany) echo "epiphany --private-instance '$2'" ;;
        badwolf) echo "badwolf '$2'" ;;
        surf) echo "surf '$2'" ;;
        netsurf) echo "$(command -v netsurf-gtk3 || command -v netsurf-gtk || echo netsurf) '$2'" ;;
        dillo) echo "dillo '$2'" ;;
        *) echo "$1 '$2'" ;;
    esac
}

for nav in "$@"; do
    pkg="$nav"
    [ "$nav" = netsurf ] && pkg=netsurf
    if ! apk add -q "$pkg" >/dev/null 2>&1; then
        echo "RESULTADO $nav - no-existe - - -"
        continue
    fi
    echo "== $nav $(apk info -e -v "$pkg" 2>/dev/null)"
    # Primera apertura en blanco: que no cuente la preparación inicial.
    limpiar
    su nav -s /bin/sh -c "dbus-run-session -- sh -c \"$(orden "$nav" about:blank)\"" >/dev/null 2>&1 &
    sleep 15
    limpiar
    n=0
    for sitio in $SITIOS; do
        n=$((n + 1))
        su nav -s /bin/sh -c "dbus-run-session -- sh -c \"$(orden "$nav" "$sitio")\"" >"$SALIDA/$nav-$n.log" 2>&1 &
        inicio=$(awk '{print $1}' /proc/uptime)
        maxpss=0; ultimo=0; quieto=0; carga=""
        cpu_total=0
        for _ in $(seq 1 $((VENTANA * 2))); do
            sleep 0.5
            read -r pss cpu <<EOF2
$(muestra)
EOF2
            [ "${pss:-0}" -gt "$maxpss" ] && maxpss=$pss
            [ "${cpu:-0}" -gt "$cpu_total" ] && cpu_total=$cpu
            # Menos de 0,05 s de procesador en 1 s (2 muestras) = quieto.
            delta=$(( ${cpu:-0} - ultimo )); ultimo=${cpu:-0}
            if [ "${cpu:-0}" -gt 50 ] && [ "$delta" -lt 3 ]; then
                quieto=$((quieto + 1))
            else
                quieto=0
            fi
            if [ -z "$carga" ] && [ "$quieto" -ge 4 ]; then
                carga=$(awk -v a="$inicio" '{printf "%.1f", $1 - a - 2}' /proc/uptime)
            fi
        done
        import -window root -resize 400x300 "$SALIDA/$nav-$n.png" 2>/dev/null
        echo "RESULTADO $nav $n ${carga:-+$VENTANA} $(awk -v c="$cpu_total" 'BEGIN {printf "%.1f", c / 100}') $((maxpss / 1024))"
        limpiar
    done
done
