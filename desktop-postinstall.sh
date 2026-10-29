#!/bin/sh
# ==============================================================================
# Script de configuración post-instalación para entorno de escritorio en Alpine
# Compatible con: ash (BusyBox) - shell por defecto de Alpine Linux
#
# Uso rápido (como root; "--ayuda" muestra todas las opciones):
#   sh desktop-postinstall.sh                 menú de casillas
#   sh desktop-postinstall.sh --full          todo, sin preguntar
#   sh desktop-postinstall.sh --minimo --con libreoffice,brave
#   sh desktop-postinstall.sh --full --destino /mnt
#       (sistema recién instalado en /mnt, antes del primer reinicio)
#
# Orden del archivo: primero las herramientas comunes (registro, opciones,
# apk), luego un bloque por tarea en el mismo orden en que las ejecuta
# main(), al final del archivo.
# ==============================================================================

set -eu

LOG_FILE="/var/log/desktop-postinstall.log"

# Descriptor 3 = la salida normal del script. Los avisos de apk_vigilado van
# ahi, aunque quien lo llame mande la salida de apk a otra parte.
exec 3>&1

log_info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$1" | tee -a "$LOG_FILE"; }
log_ok()    { printf '\033[1;32m[OK]\033[0m    %s\n' "$1" | tee -a "$LOG_FILE"; }
log_warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$1" | tee -a "$LOG_FILE"; }
log_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" | tee -a "$LOG_FILE"; }

# Un error no previsto (set -e) termina el script por la trampa EXIT. Ctrl+C
# o una orden de terminar pasan por la segunda trampa, que quita la primera
# para no mostrar dos mensajes. Los errores ya explicados usan "morir".
# En todos los casos, "limpiar" corta un apk a medias y, con --destino,
# desmonta lo que el script montó.
trap 'limpiar; log_error "Ocurrió un error inesperado. Abortando script."' EXIT
trap 'trap - EXIT; limpiar; log_error "Script interrumpido."; exit 130' INT TERM

limpiar() {
    apk_detener
    # Lo lanzado con con_avance: un programa en segundo plano no recibe
    # Ctrl+C, asi que se corta aqui (con sus hijos) y lo que alcanzo a
    # escribir pasa al registro.
    [ -z "${_av_pid:-}" ] || terminar_arbol "$_av_pid"
    if [ -n "${_av_salida:-}" ] && [ -f "$_av_salida" ]; then
        cat "$_av_salida" >>"$LOG_FILE" 2>/dev/null || true
        rm -f "$_av_salida"
    fi
    rm -f "${_apk_salida:-}"
    destino_desmontar
}

morir() {
    trap - EXIT
    limpiar
    log_error "$1"
    exit 1
}

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

# Consulta una decision ya tomada: por las opciones de la linea de ordenes,
# por variables OPT_* del entorno o en el menu de casillas del inicio
# (decidir_opciones). $1 es el nombre de la variable (p. ej. OPT_CUPS) y
# $2 la pregunta de respaldo. Si nada la fijo (sin opciones y sin
# terminal para el menu), la variable queda vacia y se pregunta como
# siempre, una por una: el respaldo vive aqui, en un solo lugar, en vez
# de repetirse en cada bloque. El nombre de la variable siempre viene del
# propio script, nunca de la entrada del usuario, asi que el 'eval' es
# seguro.
want() {
    want_val=""
    eval "want_val=\${$1:-}"
    case "$want_val" in
        yes) return 0 ;;
        no)  return 1 ;;
        *)   ask_yes_no "$2" ;;
    esac
}

# ------------------------------------------------------------------------------
# BLOQUE 1: Opciones de la línea de órdenes
# ------------------------------------------------------------------------------
# Sin opciones, el script muestra su menu de casillas (o, sin terminal,
# pregunta cada cosa por separado), como siempre. Con opciones corre sin
# preguntar: asi lo puede llamar un instalador grafico (Calamares) con lo
# que eligio el usuario, o una persona que quiere dejarlo todo listo de una
# vez con --full.
#
# Las decisiones tambien se pueden fijar con variables OPT_* en el entorno
# (OPT_LIBREOFFICE=yes ...), la forma que usaban los instaladores
# anteriores. Si se dan las dos, mandan las opciones.

# Programas opcionales que se pueden marcar con --con y --sin.
PROGRAMAS="impresoras libreoffice firefox vlc youtube fastfetch btop flatpak onlyoffice chrome brave gcompat actualizaciones"
# Los que solo sirven con escritorio: sin escritorio no se instalan.
PROGRAMAS_GRAFICOS="libreoffice firefox vlc youtube flatpak onlyoffice chrome brave"

# Nombre de la variable OPT_* de cada programa.
programa_var() {
    case "$1" in
        impresoras|cups)  echo OPT_CUPS ;;
        libreoffice)      echo OPT_LIBREOFFICE ;;
        firefox)          echo OPT_FIREFOX ;;
        vlc)              echo OPT_VLC ;;
        youtube)          echo OPT_YOUTUBE ;;
        fastfetch)        echo OPT_FASTFETCH ;;
        btop)             echo OPT_BTOP ;;
        flatpak|flathub)  echo OPT_FLATPAK ;;
        onlyoffice)       echo OPT_ONLYOFFICE ;;
        chrome)           echo OPT_CHROME ;;
        brave)            echo OPT_BRAVE ;;
        gcompat)          echo OPT_GCOMPAT ;;
        actualizaciones)  echo OPT_UPDATE_SHORTCUT ;;
        *) return 1 ;;
    esac
}

# Escritorios que acepta --escritorio (los de setup-desktop de Alpine).
ESCRITORIOS="xfce xfce-wayland mate lxqt gnome plasma sway"

ARG_MODO=""          # vacio, "full" o "minimo"
ARG_MENU="no"        # --menu: mostrar el menu aunque haya opciones
ARG_CON=""           # programas de --con
ARG_SIN=""           # programas de --sin
ARG_NVIDIA=""        # seguro, optimus o activa
ARG_USUARIO=""
ARG_ESCRITORIO=""
ARG_DESTINO=""
HAY_OPCIONES="no"    # alguna opcion fijo decisiones: no se pregunta nada
ARGS_INTERNOS=""     # los argumentos sin --destino, para el chroot

mostrar_ayuda() {
    cat <<'AYUDA'
Uso: desktop-postinstall.sh [opciones]

Configura un escritorio de Alpine Linux recien instalado: red, audio,
controladores, idioma, energia, discos, impresoras, programas y el aviso
de actualizaciones. Se ejecuta como root.

Sin opciones muestra un menu de casillas. Con cualquiera de las opciones
de abajo (salvo --usuario, --escritorio y --destino) no pregunta nada.

  --full               Todo: todos los programas de la lista de abajo.
  --minimo             Solo la configuracion base, sin programas opcionales.
  --con LISTA          Marca estos programas (separados por comas).
  --sin LISTA          Desmarca estos programas. Gana sobre --con.
  --menu               Muestra el menu igual, con lo anterior ya marcado.
  --idioma IDIOMA      Idioma del sistema, p. ej. es_CO.UTF-8 (por defecto
                       es_ES.UTF-8).
  --teclado latam|no   Teclado latinoamericano, o no tocar el teclado.
  --nvidia MODO        Graficas NVIDIA: seguro (bloquearla), activa, u
                       optimus (automatico: en portatiles con dos graficas
                       la apaga; en los demas la deja activa si es de 2012
                       en adelante, Kepler, y si no la bloquea).
  --usuario NOMBRE     Usuario del escritorio (si no se puede adivinar).
  --escritorio NOMBRE  Instala antes ese escritorio con setup-desktop:
                       xfce, xfce-wayland, mate, lxqt, gnome, plasma o sway.
  --destino CARPETA    Configura el sistema instalado en CARPETA (p. ej.
                       /mnt) sin reiniciar, desde el sistema en uso.
  --ayuda              Muestra esta ayuda.

Programas para --con y --sin:
  impresoras, libreoffice, firefox, vlc, youtube (buscar y ver videos
  de YouTube sin navegador: pipe-viewer + mpv), fastfetch, btop,
  flatpak (tienda Flathub), onlyoffice, chrome, brave (estos tres por
  Flatpak; marcarlos activa Flatpak), gcompat, actualizaciones (boton
  "Actualizar el sistema" y aviso de actualizaciones).
  Sin --full ni --minimo, se parte de las casillas premarcadas del menu.
  Sin escritorio, los programas graficos se omiten.

Ejemplos:
  desktop-postinstall.sh --full
  desktop-postinstall.sh --minimo --con libreoffice,vlc,brave
  desktop-postinstall.sh --full --sin chrome --idioma es_MX.UTF-8
  desktop-postinstall.sh --escritorio xfce --full --destino /mnt

Registro: /var/log/desktop-postinstall.log
AYUDA
}

error_de_uso() {
    trap - EXIT INT TERM
    printf 'desktop-postinstall.sh: %s\nUsa --ayuda para ver las opciones.\n' "$1" >&2
    exit 2
}

# Agrega $1 a ARGS_INTERNOS entre comillas simples, para recuperarlo
# despues con 'eval set --' sin que se separen las palabras.
guardar_arg() {
    ARGS_INTERNOS="$ARGS_INTERNOS '$(printf '%s' "$1" | sed "s/'/'\\\\''/g")'"
}

# Comprueba los nombres de una lista separada por comas y la deja en
# $lista, separada por espacios.
leer_lista() {
    lista="$(printf '%s' "$1" | tr ',' ' ')"
    for _p in $lista; do
        programa_var "$_p" >/dev/null || error_de_uso "Programa desconocido: '$_p'. Validos: $PROGRAMAS"
    done
}

leer_argumentos() {
    while [ $# -gt 0 ]; do
        opcion="$1"
        valor=""
        case "$opcion" in
            --*=*) valor="${opcion#*=}"; opcion="${opcion%%=*}" ;;
        esac
        case "$opcion" in
            --con|--sin|--idioma|--teclado|--nvidia|--usuario|--escritorio|--destino)
                # Forma "--con lista" (dos palabras) o "--con=lista".
                if [ "$1" = "$opcion" ]; then
                    [ $# -ge 2 ] || error_de_uso "Falta el valor de $opcion."
                    valor="$2"
                    shift
                fi
                [ -n "$valor" ] || error_de_uso "Falta el valor de $opcion."
                ;;
        esac

        case "$opcion" in
            --full|--todo)    ARG_MODO="full";   HAY_OPCIONES="yes" ;;
            --minimo|--mínimo) ARG_MODO="minimo"; HAY_OPCIONES="yes" ;;
            --menu)           ARG_MENU="yes" ;;
            --con)            leer_lista "$valor"; ARG_CON="$ARG_CON $lista"; HAY_OPCIONES="yes" ;;
            --sin)            leer_lista "$valor"; ARG_SIN="$ARG_SIN $lista"; HAY_OPCIONES="yes" ;;
            --idioma)
                case "$valor" in
                    *[!A-Za-z0-9_.@-]*) error_de_uso "Idioma no valido: '$valor' (ejemplo: es_CO.UTF-8)." ;;
                esac
                OPT_LANG="$valor"
                HAY_OPCIONES="yes"
                ;;
            --teclado)
                case "$valor" in
                    latam)              OPT_KEYBOARD="yes" ;;
                    no|ninguno|ninguna) OPT_KEYBOARD="no" ;;
                    *) error_de_uso "Teclado no valido: '$valor' (usa latam o no)." ;;
                esac
                HAY_OPCIONES="yes"
                ;;
            --nvidia)
                case "$valor" in
                    seguro|optimus|activa) ARG_NVIDIA="$valor" ;;
                    *) error_de_uso "Modo de NVIDIA no valido: '$valor' (usa seguro, optimus o activa)." ;;
                esac
                HAY_OPCIONES="yes"
                ;;
            --usuario)        ARG_USUARIO="$valor" ;;
            --escritorio)
                case " $ESCRITORIOS " in
                    *" $valor "*) ARG_ESCRITORIO="$valor" ;;
                    *) error_de_uso "Escritorio no valido: '$valor'. Validos: $ESCRITORIOS" ;;
                esac
                ;;
            --destino)        ARG_DESTINO="$valor" ;;
            -h|--ayuda|--help)
                mostrar_ayuda
                trap - EXIT INT TERM
                exit 0
                ;;
            *) error_de_uso "Opcion desconocida: $1" ;;
        esac

        # Todo menos --destino se repite dentro del sistema de destino.
        if [ "$opcion" != "--destino" ]; then
            if [ -n "$valor" ]; then guardar_arg "$opcion=$valor"; else guardar_arg "$opcion"; fi
        fi
        shift
    done
}

# ------------------------------------------------------------------------------
# BLOQUE 2: Validación de permisos de superusuario
# ------------------------------------------------------------------------------
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        morir "Este script debe ejecutarse como root."
    fi
    log_ok "Permisos de superusuario verificados."
}

# ------------------------------------------------------------------------------
# BLOQUE 3: Sistema recién instalado, sin reiniciar (--destino)
# ------------------------------------------------------------------------------
# Despues de instalar Alpine en un disco (setup-alpine, setup-disk), el
# sistema nuevo puede quedar montado, por ejemplo en /mnt. Con --destino
# /mnt el script se copia ahi y se ejecuta "dentro" de ese sistema
# (chroot), igual que lo hace el instalador de Lazaro Linux: todo lo que
# instala y configura queda en el disco nuevo, no en el sistema desde el
# que se ejecuta. Los servicios quedan habilitados y arrancan al encender
# el equipo nuevo. Lo que no se puede hacer dentro de un chroot (algunas
# aplicaciones de Flathub, como Chrome) queda pendiente y se instala solo
# despues del primer arranque con internet.
#
# Sin --destino, el script configura el sistema en el que corre: tanto
# uno ya arrancado como uno al que se entro a mano con chroot.
DESTINO_MONTADOS=""

# Monta algo en $1 (dentro del destino) si no estaba montado ya; el resto
# de argumentos son los de mount. Solo se desmonta al final lo que se
# monto aqui.
destino_montar() {
    _punto="$1"
    shift
    mkdir -p "$_punto"
    mountpoint -q "$_punto" && return 0
    mount "$@" "$_punto" || morir "No se pudo montar $_punto."
    DESTINO_MONTADOS="$_punto $DESTINO_MONTADOS"
}

# Cierra los procesos que quedaron vivos dentro del destino (por ejemplo,
# servicios de D-Bus que arranca flatpak): si no, no se podria desmontar.
destino_cerrar_procesos() {
    for _senal in TERM KILL; do
        _quedan=""
        for _proc in /proc/[0-9]*; do
            [ "$(readlink "$_proc/root" 2>/dev/null)" = "$1" ] || continue
            kill -s "$_senal" "${_proc#/proc/}" 2>/dev/null && _quedan="si"
        done
        [ -n "$_quedan" ] || return 0
        sleep 1
    done
}

destino_desmontar() {
    [ -n "$DESTINO_MONTADOS" ] || return 0
    destino_cerrar_procesos "$DESTINO_RAIZ"
    for _punto in $DESTINO_MONTADOS; do
        umount "$_punto" 2>/dev/null || umount -l "$_punto" 2>/dev/null \
            || log_warn "No se pudo desmontar $_punto."
    done
    DESTINO_MONTADOS=""
}

# Ejecuta el script dentro del sistema montado en --destino y termina.
# shellcheck disable=SC2120  # los argumentos salen de ARGS_INTERNOS
ejecutar_en_destino() {
    DESTINO_RAIZ="$(cd "$ARG_DESTINO" 2>/dev/null && pwd -P)" \
        || morir "La carpeta de --destino no existe: $ARG_DESTINO"
    case "$DESTINO_RAIZ" in
        /) morir "--destino no puede ser el sistema en uso: para configurarlo, ejecuta el script sin --destino." ;;
        *[[:space:]]*) morir "La carpeta de --destino no puede tener espacios: $DESTINO_RAIZ" ;;
    esac
    [ -f "$DESTINO_RAIZ/etc/alpine-release" ] \
        || morir "$DESTINO_RAIZ no parece un Alpine instalado (falta etc/alpine-release). ¿Montaste el disco nuevo ahi?"
    [ -f "$0" ] || morir "Para usar --destino, guarda el script en un archivo y ejecutalo desde ahi."

    log_info "===== Configurando el sistema instalado en $DESTINO_RAIZ (sin reiniciar) ====="
    destino_montar "$DESTINO_RAIZ/proc" -t proc proc
    destino_montar "$DESTINO_RAIZ/sys" -t sysfs sys
    destino_montar "$DESTINO_RAIZ/dev" -o bind /dev
    destino_montar "$DESTINO_RAIZ/dev/pts" -o bind /dev/pts

    # El sistema nuevo usa la conexion a internet de este.
    cp /etc/resolv.conf "$DESTINO_RAIZ/etc/resolv.conf" 2>/dev/null \
        || log_warn "No se pudo copiar /etc/resolv.conf: dentro del destino puede no haber internet."
    mkdir -p "$DESTINO_RAIZ/root"
    cp "$0" "$DESTINO_RAIZ/root/.desktop-postinstall.sh"

    # DOAS_USER vacio: el usuario de este sistema no tiene por que existir
    # en el nuevo (alli se busca con --usuario o se adivina).
    eval "set -- $ARGS_INTERNOS"
    _rc=0
    env PATH=/usr/sbin:/usr/bin:/sbin:/bin DOAS_USER= \
        chroot "$DESTINO_RAIZ" /bin/sh /root/.desktop-postinstall.sh "$@" || _rc=$?

    rm -f "$DESTINO_RAIZ/root/.desktop-postinstall.sh"
    destino_desmontar
    trap - EXIT INT TERM
    if [ "$_rc" -eq 0 ]; then
        log_ok "Sistema en $DESTINO_RAIZ configurado. Ya puedes reiniciar en el sistema nuevo."
    else
        log_error "La configuracion dentro de $DESTINO_RAIZ termino con error ($_rc). Detalles en $DESTINO_RAIZ$LOG_FILE"
    fi
    exit "$_rc"
}

# ------------------------------------------------------------------------------
# BLOQUE 4: Actualización de repositorios, apk y cortes de internet
# ------------------------------------------------------------------------------
update_system() {
    log_info "Actualizando índice de paquetes..."
    if ! esperar_red 120; then
        morir "No hay conexion con los repositorios de Alpine. Conectate a internet y vuelve a ejecutar el script."
    fi
    apk_vigilado update >>"$LOG_FILE" 2>&1 || morir "Fallo al actualizar apk (detalles en $LOG_FILE)."
}

# --- Cortes de internet -------------------------------------------------------
# En una conexion inestable (wifi debil, un modem que se reinicia) una
# descarga puede fallar a la mitad aunque segundos despues la red vuelva.
# Antes, ese paquete quedaba sin instalar con solo un aviso en el
# registro. Ahora, cuando apk falla por la red, se espera a que vuelva y
# se reintenta (apk_vigilado). Si la red no vuelve en unos minutos, se
# da por caida y las siguientes descargas ya no esperan (cada una
# fallaria igual): el script sigue con lo que no necesita internet, y al
# final avisa que hay que volver a ejecutarlo.
RED_CAIDA="no"
FALLOS_DE_RED=0

# Devuelve 0 si responde el primer repositorio de internet de apk. Sin
# repositorios de internet (solo locales) no hay nada que comprobar.
red_disponible() {
    _repo="$(grep -m1 '^http' /etc/apk/repositories 2>/dev/null || true)"
    [ -n "$_repo" ] || return 0
    wget -q --spider -T 8 "$_repo/$(apk --print-arch)/APKINDEX.tar.gz" 2>/dev/null
}

# Espera hasta $1 segundos (180 por defecto) a que haya red. Si ya se dio
# por caida, solo comprueba una vez.
esperar_red() {
    _limite="${1:-180}"
    [ "$RED_CAIDA" = "yes" ] && _limite=0
    _t=0
    while ! red_disponible; do
        if [ "$_t" -ge "$_limite" ]; then
            RED_CAIDA="yes"
            return 1
        fi
        [ "$_t" -gt 0 ] || log_warn "Sin conexion con el repositorio de Alpine; esperando a que vuelva internet..." >&3
        sleep 10
        _t=$((_t + 10))
    done
    if [ "$_t" -gt 0 ] || [ "$RED_CAIDA" = "yes" ]; then
        log_ok "La conexion volvio." >&3
    fi
    RED_CAIDA="no"
    return 0
}

# Devuelve 0 si la salida de apk (archivo $1) muestra un fallo de red: los
# mensajes de apk-tools para DNS, TLS, HTTP 5xx, descargas cortadas y los
# errores de conexion del sistema.
# "fetching URL: ... database format error" y "masked in: --no-network": la descarga del
# indice de paquetes se corto (llego incompleto) y apk sigue con el indice
# viejo o sin indice, asi que los paquetes que faltan parecen no existir.
# Visto en un ASUS K53SV con wifi inestable: pciutils y xrandr fallaron
# sin reintentar.
fallo_de_red() {
    grep -qiE 'fetching [^ ]*: v[0-9] database format error|masked in: --no-network|unexpected end of file|DNS:|TLS: unspecified|HTTP 408|HTTP 50[0-9]|remote server returned|connection|network (is )?unreachable|host is unreachable|timed out|I/O error|integrity error|try again later|broken pipe' "$1"
}

# --- Avance en pantalla -------------------------------------------------------
# La salida completa de apk, setup-desktop y flatpak va al registro. En
# pantalla se muestra un resumen mientras trabajan, para que se vea que el
# script no esta congelado:
#   - una linea por paquete: "(12/80) Instalando libreoffice-writer";
#   - si pasan 20 s sin novedades, "... sigue trabajando (1 min 20 s)".
# Quien lanza el programa en segundo plano llama a avance_iniciar, luego a
# avance_revisar cada 5 s con el archivo donde va su salida, y al terminar
# a avance_terminar. Todo se escribe en el descriptor 3 (la pantalla).
avance_iniciar() {
    _av_leidas=0
    _av_silencio=0
    _av_total=0
    _av_ultima=""
}

# Traduce la salida de apk y flatpak (en la entrada) a lineas cortas en
# espanol; lo demas se descarta.
avance_traducir() {
    awk '
        # apk alinea el numero con espacios: "( 1/12) Installing ...".
        { sub(/^\( +/, "(") }
        /^\([0-9]+\/[0-9]+\) (Installing|Upgrading|Downgrading|Reinstalling) / {
            print "        " $1 " Instalando " $3; next
        }
        /^\([0-9]+\/[0-9]+\) Purging / {
            print "        " $1 " Quitando " $3; next
        }
        /^(Installing|Instalando) [0-9]+\/[0-9]+/ {
            sub(/[^0-9\/].*$/, "", $2)
            print "        (" $2 ") Descargando de Flathub"
        }
    '
}

# Deja en $_av_nuevas las lineas traducidas que el programa escribio en el
# archivo $1 desde la ultima lectura. Flatpak redibuja su barra con
# retornos de carro: se cuentan como saltos de linea, y una linea igual a
# la anterior no se repite (la barra de un mismo paquete se redibuja
# muchas veces).
avance_leer() {
    _av_nuevas=""
    _av_lineas="$(tr '\r' '\n' <"$1" 2>/dev/null | wc -l)"
    [ "$_av_lineas" -gt "$_av_leidas" ] || return 0
    _av_nuevas="$(tr '\r' '\n' <"$1" | sed -n "$((_av_leidas + 1)),${_av_lineas}p" \
        | avance_traducir | awk -v u="$_av_ultima" '$0 != u { print; u = $0 }')"
    _av_leidas="$_av_lineas"
    [ -z "$_av_nuevas" ] || _av_ultima="$(printf '%s\n' "$_av_nuevas" | tail -n 1)"
    return 0
}

# $1 = archivo con la salida del programa que esta corriendo.
avance_revisar() {
    _av_total=$((_av_total + 5))
    avance_leer "$1"
    if [ -n "$_av_nuevas" ]; then
        printf '%s\n' "$_av_nuevas" >&3
        _av_silencio=0
        return 0
    fi
    _av_silencio=$((_av_silencio + 5))
    if [ $((_av_silencio % 20)) -eq 0 ]; then
        if [ "$_av_total" -ge 60 ]; then
            printf '        ... sigue trabajando (%s min %s s)\n' $((_av_total / 60)) $((_av_total % 60)) >&3
        else
            printf '        ... sigue trabajando (%s s)\n' "$_av_total" >&3
        fi
    fi
    return 0
}

# Muestra las ultimas lineas que el programa escribio antes de terminar.
avance_terminar() {
    avance_leer "$1"
    [ -z "$_av_nuevas" ] || printf '%s\n' "$_av_nuevas" >&3
    return 0
}

# Termina un proceso y todos sus descendientes (primero los hijos, para
# que no queden huerfanos trabajando: setup-desktop lanza apk, por
# ejemplo). Los numeros de los hijos se leen de /proc.
# shellcheck disable=SC2013 # son numeros de proceso, uno por palabra
terminar_arbol() {
    for _ta_hijo in $(grep -ls "^PPid:[[:space:]]*$1\$" /proc/[0-9]*/status 2>/dev/null | cut -d/ -f3); do
        terminar_arbol "$_ta_hijo"
    done
    kill "$1" 2>/dev/null || true
}

# con_avance: ejecuta una orden mostrando su avance en pantalla y deja su
# salida completa en la salida normal (quien llama la manda al registro).
# Devuelve el codigo de salida de la orden. Si el script se interrumpe
# antes, limpiar (arriba) corta la orden y guarda en el registro lo que
# alcanzo a escribir.
_av_pid=""
_av_salida=""
con_avance() {
    _av_salida="$(mktemp)"
    "$@" >"$_av_salida" 2>&1 </dev/null &
    _av_pid=$!
    avance_iniciar
    while kill -0 "$_av_pid" 2>/dev/null; do
        sleep 5
        kill -0 "$_av_pid" 2>/dev/null || break
        avance_revisar "$_av_salida"
    done
    _av_rc=0
    wait "$_av_pid" || _av_rc=$?
    _av_pid=""
    avance_terminar "$_av_salida"
    cat "$_av_salida"
    rm -f "$_av_salida"
    _av_salida=""
    return "$_av_rc"
}

# apk_vigilado: ejecuta apk (con los argumentos dados) sin que se quede
# colgado para siempre y reintentando si falla por la red.
# 1) Descarga detenida. apk (3.0) baja los paquetes por HTTPS con el
#    socket en modo bloqueante, y su --timeout solo se aplica si la
#    conexion TLS pidio esperar; si el servidor deja de mandar datos a
#    mitad de un paquete, apk espera indefinidamente (visto en una VM: 20+
#    minutos quieto, sin usar CPU, en "apk add pulseaudio" y luego en "apk
#    add lang"). Aqui se vigila: si apk pasa 120 s sin leer ni escribir
#    nada (eso incluye descomprimir y escribir en el disco) y sin ningun
#    proceso hijo (los scripts de instalacion, como mkinitfs, pueden
#    tardar), se corta y se reintenta.
# 2) Corte de internet. Si apk termina con error y su salida muestra un
#    fallo de red, se espera a que la red vuelva (esperar_red) y se
#    reintenta.
# Hasta 4 intentos en total. apk confirma cada paquete al terminar de
# instalarlo, asi que el reintento sigue donde quedo. La salida de apk se
# guarda aparte para revisarla y despues se copia a la salida normal (los
# que llaman la mandan al registro). Los avisos van al descriptor 3 (ver
# arriba), para que se vean en pantalla, igual que el avance (ver
# avance_revisar). Si la descarga no se pudo completar por la red,
# devuelve 124.
_apk_pid=""
apk_vigilado() {
    _apk_intento=1
    _apk_salida="$(mktemp)"
    while :; do
        apk "$@" >"$_apk_salida" 2>&1 &
        _apk_pid=$!
        _apk_antes=""
        _apk_quieto=0
        avance_iniciar
        while kill -0 "$_apk_pid" 2>/dev/null; do
            sleep 5
            avance_revisar "$_apk_salida"
            _apk_ahora="$(awk '/^(rchar|wchar):/ { s += $2 } END { print s }' "/proc/$_apk_pid/io" 2>/dev/null)"
            # Sin /proc no se puede medir: entonces nunca se corta.
            if [ -z "$_apk_ahora" ] || [ "$_apk_ahora" != "$_apk_antes" ] \
                    || grep -qs "^PPid:[[:space:]]*$_apk_pid\$" /proc/[0-9]*/status; then
                _apk_antes="$_apk_ahora"
                _apk_quieto=0
            else
                _apk_quieto=$((_apk_quieto + 5))
            fi
            if [ "$_apk_quieto" -ge 120 ]; then
                log_warn "apk lleva 2 minutos sin avanzar (descarga detenida). Se corta y se reintenta ($_apk_intento/4)..." >&3
                apk_detener
                break
            fi
        done
        _apk_rc=0
        wait "$_apk_pid" || _apk_rc=$?
        _apk_pid=""
        avance_terminar "$_apk_salida"
        cat "$_apk_salida"

        if [ "$_apk_quieto" -ge 120 ]; then
            _apk_motivo="detenida"
        elif [ "$_apk_rc" -ne 0 ] && fallo_de_red "$_apk_salida"; then
            _apk_motivo="red"
        else
            rm -f "$_apk_salida"
            return "$_apk_rc"
        fi

        if [ "$_apk_intento" -ge 4 ]; then
            rm -f "$_apk_salida"
            FALLOS_DE_RED=$((FALLOS_DE_RED + 1))
            return 124
        fi
        if [ "$_apk_motivo" = "red" ]; then
            if ! esperar_red; then
                log_warn "Internet sigue sin responder: se omite esta descarga (apk $*)." >&3
                rm -f "$_apk_salida"
                FALLOS_DE_RED=$((FALLOS_DE_RED + 1))
                return 124
            fi
            log_warn "Una descarga fallo por la conexion; se reintenta ($_apk_intento/4)..." >&3
            sleep $((_apk_intento * 5))
        fi
        _apk_intento=$((_apk_intento + 1))
    done
}

# Corta el apk que este corriendo (si hay uno). Antes de forzarlo se
# comprueba que ese numero de proceso siga siendo apk: si ya termino, el
# numero pudo pasar a otro programa.
apk_detener() {
    [ -n "$_apk_pid" ] || return 0
    kill "$_apk_pid" 2>/dev/null || true
    sleep 2
    if [ "$(cat "/proc/$_apk_pid/comm" 2>/dev/null)" = apk ]; then
        kill -9 "$_apk_pid" 2>/dev/null || true
    fi
    return 0
}

apk_add() {
    apk_vigilado add --no-cache "$@"
}

install_pkg() {
    pkg="$1"
    log_info "Instalando: $pkg"
    _pkg_rc=0
    apk_add "$pkg" >>"$LOG_FILE" 2>&1 || _pkg_rc=$?
    # Instalado aunque apk diga error: fallo solo un paso final.
    if [ "$_pkg_rc" -ne 0 ] && [ "$_pkg_rc" -ne 124 ] && pkg_installed "$pkg"; then
        log_ok "'$pkg' instalado."
        reparar_pasos_finales
        return 0
    fi
    case "$_pkg_rc" in
        0)   log_ok "'$pkg' instalado." ;;
        124) log_warn "No se pudo descargar '$pkg' por problemas de conexion." ;;
        *)   log_warn "Fallo al instalar '$pkg' (puede no existir en tu rama/arquitectura)." ;;
    esac
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
    # Con "set -e", el codigo de salida se toma con "||" para que un lote
    # fallido no termine el script.
    _lote_rc=0
    apk_add "$@" >>"$LOG_FILE" 2>&1 || _lote_rc=$?
    if [ "$_lote_rc" -eq 0 ]; then
        for p in "$@"; do
            log_ok "'$p' instalado (lote)."
        done
    elif [ "$_lote_rc" -eq 124 ]; then
        # La descarga no se pudo completar por la red (ver apk_vigilado):
        # probar paquete por paquete solo sumaria esperas. Se sigue con el
        # resto del script.
        log_warn "No se pudo descargar el lote por problemas de conexion: $*"
    else
        # apk tambien termina con error cuando los paquetes SI quedaron
        # instalados pero fallo su paso final (un "trigger", por ejemplo
        # fc-cache de fontconfig). Entonces no hay nada que reintentar:
        # solo reparar ese paso.
        _lote_faltan=""
        for p in "$@"; do
            pkg_installed "$p" || _lote_faltan="$_lote_faltan $p"
        done
        if [ -z "$_lote_faltan" ]; then
            for p in "$@"; do
                log_ok "'$p' instalado (lote)."
            done
            reparar_pasos_finales
        else
            log_warn "La instalacion en lote fallo (probablemente algun paquete no existe en tu rama). Reintentando uno por uno:$_lote_faltan"
            for p in $_lote_faltan; do
                install_pkg "$p"
            done
        fi
    fi
}

# Si a algun paquete instalado le fallo su paso final (apk muestra
# "N errors" en cada orden desde entonces), "apk fix" lo vuelve a correr.
# La revision solo lee la base de datos local, pero se le pone un limite
# de tiempo para que nunca deje esperando al script. Si la revision misma
# falla, se intenta la reparacion igual (sin paquetes rotos no hace nada).
reparar_pasos_finales() {
    _sim_rc=0
    _sim="$(timeout 120 apk fix --simulate 2>&1)" || _sim_rc=$?
    _rotos="$(printf '%s\n' "$_sim" | sed -n 's/^([ 0-9]*\/[0-9]*) Reinstalling \([^ ]*\).*/\1/p' | tr '\n' ' ')"
    if [ "$_sim_rc" -ne 0 ] && [ -z "$_rotos" ]; then
        printf '%s\n' "$_sim" >>"$LOG_FILE"
        log_warn "No se pudo revisar si quedaron paquetes a medio instalar (codigo $_sim_rc). Se intenta 'apk fix' por si acaso..."
    elif [ -z "$_rotos" ]; then
        return 0
    else
        log_warn "A estos paquetes les fallo su paso final de instalacion: ${_rotos% }. Se repara con 'apk fix'..."
    fi
    _fix_rc=0
    apk_vigilado fix >>"$LOG_FILE" 2>&1 || _fix_rc=$?
    if [ "$_fix_rc" -eq 0 ]; then
        log_ok "Paquetes reparados."
    else
        log_warn "No se pudieron reparar ahora. Despues de reiniciar ejecuta: doas apk fix"
    fi
}

# Devuelve 0 si el paquete $1 esta instalado.
pkg_installed() { apk info -e "$1" >/dev/null 2>&1; }

# enable_service SERVICIO [RUNLEVEL] [AVISO]: agrega el servicio de OpenRC
# al runlevel (por defecto "default"). Si falla, avisa y sigue; AVISO
# reemplaza el mensaje de siempre.
enable_service() {
    _svc_nivel="${2:-default}"
    _svc_aviso="No se pudo agregar '$1' al runlevel $_svc_nivel."
    rc-update add "$1" "$_svc_nivel" || log_warn "${3:-$_svc_aviso}"
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
    pkg_installed pciutils || install_pkg "pciutils"
    pkg_installed usbutils || install_pkg "usbutils"
    # El shell recuerda la ruta de los comandos ya usados; se olvida para
    # que 'lsusb' apunte al recien instalado y no al de BusyBox.
    hash -r 2>/dev/null || true
    HW_TOOLS_READY="yes"
}

# El hardware se pudo revisar del todo: estan las versiones completas de
# lspci y lsusb (las de BusyBox no muestran nombres, asi que un adaptador
# USB pasaria desapercibido) y las dos funcionaron.
hw_revisado() {
    pkg_installed pciutils && pkg_installed usbutils &&
        lspci >/dev/null 2>&1 && lsusb >/dev/null 2>&1
}

# ------------------------------------------------------------------------------
# BLOQUE 5: Instalar el escritorio (--escritorio)
# ------------------------------------------------------------------------------
# Lo normal es instalar el escritorio antes con la herramienta de Alpine
# (setup-desktop) y despues ejecutar este script. Con --escritorio NOMBRE
# el script lo hace por su cuenta, primero, con la misma herramienta. Si
# el escritorio ya estaba instalado, setup-desktop solo comprueba que no
# falte nada.
install_desktop() {
    [ -n "$ARG_ESCRITORIO" ] || return 0
    log_info "== Escritorio: $ARG_ESCRITORIO (setup-desktop) =="
    command -v setup-desktop >/dev/null 2>&1 || install_pkg alpine-conf
    command -v setup-desktop >/dev/null 2>&1 \
        || morir "No esta 'setup-desktop' (paquete alpine-conf): no se puede instalar el escritorio."
    # setup-desktop instala con apk directamente: si falla (por ejemplo,
    # por un corte de internet), se espera a la red y se repite.
    for _intento in 1 2 3; do
        if con_avance setup-desktop "$ARG_ESCRITORIO" >>"$LOG_FILE" 2>&1; then
            log_ok "Escritorio '$ARG_ESCRITORIO' instalado."
            return 0
        fi
        [ "$_intento" -lt 3 ] || break
        log_warn "setup-desktop fallo; se reintenta ($_intento/3)..."
        esperar_red || break
    done
    morir "No se pudo instalar el escritorio '$ARG_ESCRITORIO' (detalles en $LOG_FILE)."
}

# ------------------------------------------------------------------------------
# BLOQUE 6: Detección multiparadigma del entorno de escritorio
# ------------------------------------------------------------------------------
DE_XFCE="no"
DE_PLASMA="no"
DE_GNOME="no"
DE_MATE="no"
DE_LXQT="no"
DE_SWAY="no"

# Devuelve 0 si se detecto al menos un entorno de escritorio.
has_desktop() {
    [ "$DE_XFCE" = "yes" ] || [ "$DE_PLASMA" = "yes" ] || [ "$DE_GNOME" = "yes" ] || [ "$DE_MATE" = "yes" ] || [ "$DE_LXQT" = "yes" ] || [ "$DE_SWAY" = "yes" ]
}

detect_desktop_environment() {
    log_info "== Detectando entorno de escritorio instalado =="

    pkg_installed xfce4-session && { DE_XFCE="yes"; log_ok "XFCE detectado."; }

    # Se comprueban ambos nombres: plasma-desktop-meta (metapaquete usado
    # por setup-desktop) y plasma-desktop (paquete real que trae como
    # dependencia). Cubre también instalaciones manuales/no estándar que
    # no pasaron por el metapaquete.
    if pkg_installed plasma-desktop-meta || pkg_installed plasma-desktop; then
        DE_PLASMA="yes"; log_ok "KDE Plasma detectado."
    fi

    pkg_installed gnome-shell && { DE_GNOME="yes"; log_ok "GNOME detectado."; }
    pkg_installed mate-session-manager && { DE_MATE="yes"; log_ok "MATE detectado."; }
    pkg_installed lxqt-session && { DE_LXQT="yes"; log_ok "LXQt detectado."; }
    pkg_installed sway && { DE_SWAY="yes"; log_ok "Sway detectado."; }

    if ! has_desktop; then
        log_warn "No se detectó un entorno soportado. Se instalarán herramientas genéricas de consola."
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 7: Detección de hardware gráfico (soporta configuraciones híbridas)
# ------------------------------------------------------------------------------
GPU_HAS_INTEL="no"
GPU_HAS_AMD="no"
GPU_HAS_NVIDIA="no"
GPU_HAS_VIRTUAL="no"
GPU_COUNT=0
NVIDIA_COUNT=0
NVIDIA_SLOT=""      # ranura PCI de la NVIDIA, p. ej. 0000:01:00.0
NVIDIA_SLOTS=""     # todas las NVIDIA, si hay mas de una
PRIMARY_SLOT=""     # GPU que el firmware uso al arrancar (boot_vga)
PRIMARY_VENDOR=""
IS_LAPTOP="no"
OPTIMUS_LAPTOP="no" # portatil con grafica integrada + una NVIDIA
NVIDIA_CHIP=""      # nombre del chip, p. ej. GF108 (vacio si no se supo)
NVIDIA_GEN="desconocida" # tesla, fermi, kepler, maxwell, pascal, volta, moderna (Turing en adelante)
NVIDIA_HAY_MODERNA="no"  # alguna NVIDIA es Turing o posterior (instalar NVK)

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
            0x10de) GPU_HAS_NVIDIA="yes"; NVIDIA_COUNT=$((NVIDIA_COUNT + 1)); NVIDIA_SLOT="$slot"; NVIDIA_SLOTS="$NVIDIA_SLOTS $slot" ;;
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

    [ "$GPU_HAS_NVIDIA" = "no" ] || nvidia_detectar_generacion

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

# Generacion de la NVIDIA, a partir del nombre de su chip. Decide cuanto
# se puede confiar en nouveau:
#   - tesla, fermi: lo mas antiguo; en algunos equipos nouveau da pantalla
#     negra o cuelgues, y NVIDIA ya no tiene driver que funcione con los
#     kernels actuales.
#   - kepler, maxwell, pascal, volta: nouveau maneja bien el escritorio,
#     aunque el 3D va lento (no puede subir la velocidad de la tarjeta).
#   - moderna (Turing, 2018, en adelante): nouveau usa el firmware GSP de
#     NVIDIA y rinde bien; Vulkan con NVK y OpenGL por encima (Zink).
# El nombre sale de la base de datos de lspci ("GF108M [GeForce GT
# 540M]": el chip es la primera palabra) y, si no esta, del registro del
# kernel, donde nouveau escribe "NVIDIA GF108 (0c1f00a1)" al cargarse.
nvidia_generacion_de_chip() {
    case "$1" in
        TU*|GA*|GH*|AD*|GB*) echo moderna ;;
        GV*) echo volta ;;
        GP*) echo pascal ;;
        GM*) echo maxwell ;;
        GK*) echo kepler ;;
        GF*) echo fermi ;;
        NV*|G[0-9]*|GT2*|MCP*|C[0-9]*) echo tesla ;;
        *) echo desconocida ;;
    esac
}

# Chip de la NVIDIA en la ranura $1, o vacio si no se supo.
nvidia_chip_de() {
    _c=""
    if command -v lspci >/dev/null 2>&1; then
        # -mm: campos entre comillas; el 3.o es el nombre del dispositivo.
        _c="$(lspci -mm -s "$1" 2>/dev/null \
            | awk -F'"' 'NR == 1 { split($6, p, " "); print p[1] }')" || _c=""
    fi
    if [ "$(nvidia_generacion_de_chip "$_c")" = desconocida ]; then
        # Solo la linea de nouveau de ESA ranura (puede haber varias NVIDIA).
        _c="$(dmesg 2>/dev/null \
            | sed -n "s/.*nouveau $1: NVIDIA \\([A-Z][A-Z0-9]*\\) (.*/\\1/p" | head -n 1)" || _c=""
    fi
    echo "$_c"
}

# Con varias NVIDIA manda la mas antigua (NVIDIA_GEN decide el modo
# seguro) y NVK se instala si alguna es moderna.
nvidia_detectar_generacion() {
    NVIDIA_GEN=""
    NVIDIA_CHIP=""
    for _slot in $NVIDIA_SLOTS; do
        _chip="$(nvidia_chip_de "$_slot")"
        _gen="$(nvidia_generacion_de_chip "$_chip")"
        log_info "NVIDIA en $_slot: chip ${_chip:-no identificado}, generacion $_gen."
        [ "$_gen" != moderna ] || NVIDIA_HAY_MODERNA="yes"
        if [ -z "$NVIDIA_GEN" ] || [ "$(nvidia_orden "$_gen")" -lt "$(nvidia_orden "$NVIDIA_GEN")" ]; then
            NVIDIA_GEN="$_gen"
            NVIDIA_CHIP="$_chip"
        fi
    done
    : "${NVIDIA_GEN:=desconocida}"
}

# Orden de antiguedad; la desconocida cuenta como la mas antigua.
nvidia_orden() {
    case "$1" in
        tesla) echo 1 ;; fermi) echo 2 ;; kepler) echo 3 ;; maxwell) echo 4 ;;
        pascal) echo 5 ;; volta) echo 6 ;; moderna) echo 7 ;; *) echo 0 ;;
    esac
}

# Generacion en la que nouveau maneja bien el escritorio (Kepler o mas
# nueva). Con tesla, fermi o desconocida se prefiere el modo seguro
# cuando la NVIDIA es la unica grafica.
nvidia_confiable() {
    case "$NVIDIA_GEN" in
        kepler|maxwell|pascal|volta|moderna) return 0 ;;
    esac
    return 1
}

# ------------------------------------------------------------------------------
# BLOQUE 8: Decisiones al inicio: opciones o menú de casillas
# ------------------------------------------------------------------------------
# Todas las decisiones se toman aqui, al principio, y el resto del script
# corre solo, sin volver a preguntar. Hay tres caminos:
#   - Con opciones (--full, --minimo, --con...): se usan esas, sin
#     preguntar nada (--menu muestra igual el menu, ya marcado).
#   - Sin opciones y con terminal: menu de casillas con 'dialog' (funciona
#     tanto en una consola TTY como en una terminal grafica) y un resumen
#     para confirmar.
#   - Sin opciones y sin terminal (o sin poder instalar 'dialog'): las
#     variables OPT_* del entorno que haya; las que falten se preguntan
#     una por una (want).
#
# main() lo ejecuta despues de detect_hardware y detect_desktop_environment:
# la opcion de NVIDIA solo se muestra si hay una NVIDIA, y los programas
# graficos solo si hay escritorio.
#
# Los textos del menu van SIN acentos a proposito: el menu aparece antes
# de que el script configure el idioma, y en una consola TTY recien
# instalada los acentos pueden verse como simbolos extranos.
decidir_opciones() {
    log_info "== Seleccion de acciones =="

    if [ "$HAY_OPCIONES" = "no" ] && [ "$ARG_MENU" = "no" ]; then
        select_options_menu
        # Un instalador que fija las OPT_* pero es anterior a las opciones
        # mas nuevas: esas no se preguntan, quedan desmarcadas.
        if [ -n "${OPT_CHROME:-}${OPT_LIBREOFFICE:-}${OPT_CUPS:-}" ]; then
            for _var in OPT_BRAVE OPT_VLC OPT_YOUTUBE OPT_FASTFETCH OPT_BTOP; do
                eval ": \"\${$_var:=no}\""
            done
        fi
        ajustar_dependencias
        return 0
    fi

    case "$ARG_MODO" in
        full)   opciones_base yes ;;
        minimo) opciones_base no ;;
        *)      menu_defaults ;;
    esac
    for _p in $ARG_CON; do eval "$(programa_var "$_p")=yes"; done
    for _p in $ARG_SIN; do eval "$(programa_var "$_p")=no"; done
    aplicar_nvidia
    ajustar_dependencias
    if [ "$ARG_MENU" = "yes" ] && [ -t 0 ] && [ -t 1 ]; then
        select_options_menu
    else
        menu_summary
        log_ok "Opciones elegidas:$(printf '%b' "$summary" | tr '\n' ' ')"
    fi
}

# Convierte yes/no al formato de estado de una casilla de dialog.
menu_state() {
    if [ "$1" = "yes" ]; then echo on; else echo off; fi
}

select_options_menu() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        log_warn "No hay una terminal interactiva: se preguntara cada opcion por separado durante la ejecucion."
        return 0
    fi

    command -v dialog >/dev/null 2>&1 || install_pkgs dialog
    if ! command -v dialog >/dev/null 2>&1; then
        log_warn "No se pudo instalar 'dialog': se preguntara cada opcion por separado durante la ejecucion."
        return 0
    fi

    menu_defaults

    while :; do
        menu_checklist
        menu_read_selection

        # Portatil Optimus: elegir que hacer con la NVIDIA. "Volver"
        # regresa a la pantalla de casillas.
        if [ "$OPTIMUS_LAPTOP" = "yes" ]; then
            menu_nvidia_mode || continue
        fi

        menu_summary

        if dialog --title "Confirmar" \
                --yes-label "Comenzar" --no-label "Volver" \
                --yesno "Ademas de la configuracion base (red, audio, drivers, idioma, etc.), se instalara:\n$summary\n\nA partir de aqui el script no hara mas preguntas." \
                0 0; then
            break
        fi
        # "Volver" (o ESC): se repite el menu con las marcas actuales.
    done

    clear 2>/dev/null || true
    # '%b' interpreta los \n del resumen sin usarlo como cadena de
    # formato: si una descripcion llegara a contener un '%', printf no
    # lo confundiria con una directiva (antes: error y linea cortada).
    log_ok "Opciones elegidas en el menu:$(printf '%b' "$summary" | tr '\n' ' ')"
}

# Valores por defecto (casillas premarcadas). Solo se llenan las
# variables vacias: lo que ya fijaron las opciones o el entorno se
# respeta. Criterios:
#  - NVIDIA en modo seguro: marcado. En el hardware antiguo al que
#    apunta este proyecto, el fallo de dejarlo desmarcado (pantalla
#    negra) es mucho peor que el de marcarlo (perder la aceleracion
#    de la NVIDIA, usando la otra GPU).
#  - Flatpak y sus aplicaciones: desmarcados. Instalar Flatpak sin
#    ninguna aplicacion seria infraestructura para nada; marcar
#    OnlyOffice, Chrome o Brave activa Flatpak automaticamente.
#  - Fastfetch, Btop y VLC: desmarcados (extras, no hacen falta para el
#    uso diario: el reproductor de siempre es mpv, ver install_daily_apps).
menu_defaults() {
    : "${OPT_KEYBOARD:=yes}"
    # Modo seguro por defecto solo si la NVIDIA es antigua o no se supo
    # cual es: en Kepler o mas nueva, bloquearla dejaria el equipo sin
    # aceleracion cuando es la unica grafica.
    if nvidia_confiable; then
        : "${OPT_NVIDIA_SAFE:=no}"
    else
        : "${OPT_NVIDIA_SAFE:=yes}"
    fi
    # Portatiles Optimus: en vez de la casilla de modo seguro se muestra
    # una segunda pantalla con tres modos; por defecto, el de ahorro
    # (probado en el K53SV, ver nvidia_apply_optimus).
    if [ "$OPTIMUS_LAPTOP" = "yes" ]; then
        : "${OPT_NVIDIA_MODE:=optimus}"
    else
        OPT_NVIDIA_MODE=""
    fi
    : "${OPT_GCOMPAT:=no}"
    : "${OPT_CUPS:=yes}"
    : "${OPT_LIBREOFFICE:=yes}"
    : "${OPT_FIREFOX:=yes}"
    : "${OPT_VLC:=no}"
    : "${OPT_YOUTUBE:=no}"
    : "${OPT_FASTFETCH:=no}"
    : "${OPT_BTOP:=no}"
    : "${OPT_FLATPAK:=no}"
    : "${OPT_ONLYOFFICE:=no}"
    : "${OPT_CHROME:=no}"
    : "${OPT_BRAVE:=no}"
    : "${OPT_UPDATE_SHORTCUT:=yes}"
}

# --full (yes) y --minimo (no): todos los programas opcionales con el
# mismo valor. Teclado y NVIDIA quedan como en el menu.
opciones_base() {
    for _p in $PROGRAMAS; do
        _var="$(programa_var "$_p")"
        eval "[ -n \"\${$_var:-}\" ] || $_var=$1"
    done
    menu_defaults
}

# --nvidia: seguro, optimus o activa. "optimus" (lo que pasa el instalador
# de Lazaro) es el modo automatico: apaga la NVIDIA en los portatiles con
# dos graficas y, en los demas equipos, la deja activa si es Kepler o mas
# nueva y la bloquea (modo seguro) si es mas antigua o desconocida.
aplicar_nvidia() {
    case "$ARG_NVIDIA" in
        seguro)
            OPT_NVIDIA_SAFE="yes"
            [ "$OPTIMUS_LAPTOP" = "no" ] || OPT_NVIDIA_MODE="safe"
            ;;
        optimus)
            OPT_NVIDIA_SAFE="yes"
            if [ "$OPTIMUS_LAPTOP" = "yes" ]; then
                OPT_NVIDIA_MODE="optimus"
            elif [ "$GPU_HAS_NVIDIA" = "yes" ]; then
                if nvidia_confiable; then
                    OPT_NVIDIA_SAFE="no"
                    log_info "--nvidia optimus: no es un portatil con dos graficas y la NVIDIA ($NVIDIA_GEN) funciona bien con nouveau: queda activa."
                else
                    log_warn "--nvidia optimus: no es un portatil con dos graficas y la NVIDIA es antigua o desconocida ($NVIDIA_GEN): se usa el modo seguro."
                fi
            fi
            ;;
        activa)
            OPT_NVIDIA_SAFE="no"
            [ "$OPTIMUS_LAPTOP" = "no" ] || OPT_NVIDIA_MODE="active"
            ;;
    esac
}

# Reglas que valen sin importar de donde salieron las decisiones:
#  - Las aplicaciones de Flathub necesitan Flatpak.
#  - Sin escritorio, los programas graficos no sirven: no se instalan.
ajustar_dependencias() {
    if [ "${OPT_ONLYOFFICE:-}" = "yes" ] || [ "${OPT_CHROME:-}" = "yes" ] || [ "${OPT_BRAVE:-}" = "yes" ]; then
        if [ "${OPT_FLATPAK:-}" = "no" ]; then
            log_warn "OnlyOffice, Chrome y Brave se instalan con Flatpak: se activa Flatpak."
        fi
        OPT_FLATPAK="yes"
    fi
    if ! has_desktop; then
        _omitidos=""
        for _p in $PROGRAMAS_GRAFICOS; do
            _var="$(programa_var "$_p")"
            _val=""
            eval "_val=\${$_var:-}"
            [ "$_val" = "no" ] || _omitidos="$_omitidos $_p"
            eval "$_var=no"
        done
        if [ -n "$_omitidos" ] && [ "$HAY_OPCIONES" = "yes" ]; then
            log_info "Sin escritorio: se omiten los programas graficos:$_omitidos."
        fi
    fi
}

# Muestra la pantalla de casillas y deja las etiquetas elegidas en $sel.
# "Salir" termina el script sin hacer cambios.
menu_checklist() {
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
        FASTFETCH "Fastfetch: resumen del equipo en la terminal" "$(menu_state "$OPT_FASTFETCH")" \
        BTOP "Btop: monitor de procesador, memoria y discos" "$(menu_state "$OPT_BTOP")"
    # Sin escritorio, los programas graficos no se ofrecen.
    if has_desktop; then
        set -- "$@" \
            LIBREOFFICE "LibreOffice en el idioma del sistema (paquete pesado)" "$(menu_state "$OPT_LIBREOFFICE")" \
            FIREFOX "Navegador Firefox" "$(menu_state "$OPT_FIREFOX")" \
            VLC "Reproductor de video VLC" "$(menu_state "$OPT_VLC")" \
            YOUTUBE "YouTube ligero: buscar y ver videos sin navegador" "$(menu_state "$OPT_YOUTUBE")" \
            FLATPAK "Flatpak/Flathub (tienda de aplicaciones)" "$(menu_state "$OPT_FLATPAK")" \
            ONLYOFFICE "OnlyOffice via Flatpak (activa Flatpak)" "$(menu_state "$OPT_ONLYOFFICE")" \
            CHROME "Google Chrome via Flatpak, paquete comunitario" "$(menu_state "$OPT_CHROME")" \
            BRAVE "Navegador Brave via Flatpak" "$(menu_state "$OPT_BRAVE")"
    fi
    set -- "$@" \
        UPDATE_SHORTCUT "Boton 'Actualizar el sistema' y aviso de actualizaciones" "$(menu_state "$OPT_UPDATE_SHORTCUT")"

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
}

# Etiquetas de las casillas (las que devuelve dialog, sin "OPT_").
CASILLAS="KEYBOARD NVIDIA_SAFE GCOMPAT CUPS FASTFETCH BTOP LIBREOFFICE FIREFOX VLC YOUTUBE FLATPAK ONLYOFFICE CHROME BRAVE UPDATE_SHORTCUT"

# Pasa las etiquetas de $sel a las variables OPT_*.
menu_read_selection() {
    # Todo se reinicia a "no" y se marca "yes" solo lo seleccionado.
    # Las etiquetas se validan contra la lista fija antes del eval.
    for k in $CASILLAS; do
        eval "OPT_$k=no"
    done
    for tag in $sel; do
        case " $CASILLAS " in
            *" $tag "*) eval "OPT_$tag=yes" ;;
        esac
    done
    ajustar_dependencias
}

# Portatil Optimus: segunda pantalla con los tres modos de la NVIDIA.
# Devuelve 1 si se eligio "Volver".
menu_nvidia_mode() {
    if ! nv_sel="$(dialog --stdout --no-tags \
            --backtitle "Configuracion post-instalacion de Alpine Linux" \
            --title "Grafica NVIDIA (portatil con graficos hibridos)" \
            --ok-label "Continuar" --cancel-label "Volver" \
            --radiolist "Este portatil tiene una grafica integrada y una NVIDIA.\nFLECHAS para moverse, ESPACIO elige, ENTER continua." \
            0 0 0 \
            optimus "Apagarla y usar la integrada (ahorro, recomendado)" "$( [ "$OPT_NVIDIA_MODE" = optimus ] && echo on || echo off)" \
            safe "Bloquearla por completo (sin driver)" "$( [ "$OPT_NVIDIA_MODE" = safe ] && echo on || echo off)" \
            active "Dejarla activa con nouveau (riesgo en tarjetas viejas)" "$( [ "$OPT_NVIDIA_MODE" = active ] && echo on || echo off)")"; then
        return 1
    fi
    case "$nv_sel" in
        optimus|safe|active) OPT_NVIDIA_MODE="$nv_sel" ;;
    esac
}

# Arma en $summary la lista de lo que se va a instalar.
menu_summary() {
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
    [ "$OPT_FASTFETCH" = "yes" ]       && summary="$summary\n  - Fastfetch"
    [ "$OPT_BTOP" = "yes" ]            && summary="$summary\n  - Btop"
    [ "$OPT_LIBREOFFICE" = "yes" ]     && summary="$summary\n  - LibreOffice"
    [ "$OPT_FIREFOX" = "yes" ]         && summary="$summary\n  - Firefox"
    [ "$OPT_VLC" = "yes" ]             && summary="$summary\n  - VLC"
    [ "$OPT_YOUTUBE" = "yes" ]         && summary="$summary\n  - YouTube ligero"
    [ "$OPT_FLATPAK" = "yes" ]         && summary="$summary\n  - Flatpak/Flathub"
    [ "$OPT_ONLYOFFICE" = "yes" ]      && summary="$summary\n  - OnlyOffice"
    [ "$OPT_CHROME" = "yes" ]          && summary="$summary\n  - Google Chrome"
    [ "$OPT_BRAVE" = "yes" ]           && summary="$summary\n  - Brave"
    [ "$OPT_UPDATE_SHORTCUT" = "yes" ] && summary="$summary\n  - Boton y aviso de actualizaciones"
    if [ -z "$summary" ]; then
        summary="\n  (ninguna opcional)"
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 9: Distribución de teclado a "latam" (consola + sesión gráfica)
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
# BLOQUE 10: Detección del usuario real del sistema
# ------------------------------------------------------------------------------
# En orden: --usuario, quien llamo a doas, quien inicio sesion (logname) y,
# si nada de eso sirve (por ejemplo, dentro de un chroot o al arrancar),
# el unico usuario normal del sistema, si hay solo uno.
TARGET_USER=""
TARGET_HOME=""

# Imprime el usuario normal (UID 1000 a 59999, carpeta en /home) si hay
# exactamente uno.
unico_usuario() {
    awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ /^\/home\// { print $1 }' /etc/passwd 2>/dev/null \
        | { read -r _u1 || exit 0; read -r _u2 && exit 0; printf '%s' "$_u1"; }
}

detect_target_user() {
    log_info "== Detectando usuario real del sistema =="

    TARGET_USER="${ARG_USUARIO:-${DOAS_USER:-}}"
    [ -n "$TARGET_USER" ] || TARGET_USER="$(logname 2>/dev/null || true)"
    if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
        TARGET_USER="$(unico_usuario)"
    fi

    if [ -z "$TARGET_USER" ]; then
        log_warn "No se pudo determinar el usuario del escritorio (usa --usuario NOMBRE)."
        return 0
    fi
    if ! id "$TARGET_USER" >/dev/null 2>&1; then
        log_warn "El usuario '$TARGET_USER' no existe en este sistema."
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
# BLOQUE 11: Applets de red y audio (enrutamiento dinámico según DE)
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
    if pkg_installed pipewire-pulse; then
        AUDIO_SERVER="pipewire"
    elif pkg_installed pulseaudio; then
        AUDIO_SERVER="pulseaudio"
    elif [ "$DE_PLASMA" = "yes" ] || [ "$DE_GNOME" = "yes" ]; then
        AUDIO_SERVER="pipewire"
    else
        AUDIO_SERVER="pulseaudio"
    fi
    log_info "Servidor de audio: $AUDIO_SERVER"
}

# El plugin de volumen de XFCE no aparece solo: el panel que XFCE crea
# la primera vez para cada usuario sale de /etc/xdg/xfce4/panel/default.xml,
# y ese archivo no lo incluye. Aqui se agrega al panel de arriba, a la
# derecha del area de notificacion (o antes del reloj), con las teclas de
# volumen del teclado activadas. Solo afecta a los paneles nuevos: un
# usuario que ya entro a XFCE conserva el suyo (se agrega a mano con clic
# derecho en el panel > Panel > Agregar elementos > Plugin de audio).
XFCE_PANEL_XML="/etc/xdg/xfce4/panel/default.xml"
xfce_panel_volumen() {
    if [ ! -f "$XFCE_PANEL_XML" ]; then
        log_warn "No esta $XFCE_PANEL_XML: el icono de volumen se agrega a mano en el panel."
        return 0
    fi
    if grep -q 'value="pulseaudio"' "$XFCE_PANEL_XML"; then
        log_info "El panel de XFCE ya trae el icono de volumen."
        return 0
    fi
    _xp_tmp="$(mktemp)"
    # Numero nuevo = el mayor de los plugins + 1. Se coloca despues del
    # area de notificacion (systray) o, si no la hay, antes del reloj.
    if awk '
        FNR == NR {
            if (match($0, /name="plugin-[0-9]+"/)) {
                n = substr($0, RSTART + 13, RLENGTH - 14) + 0
                if (n > max) max = n
                if ($0 ~ /value="systray"/) bandeja = n
                if ($0 ~ /value="clock"/) reloj = n
            }
            next
        }
        FNR == 1 {
            nuevo = max + 1
            if (!bandeja && !reloj) exit 1
        }
        /<value type="int" value="[0-9]+"\/>/ && !puesto {
            match($0, /value="[0-9]+"/)
            id = substr($0, RSTART + 7, RLENGTH - 8) + 0
            sangria = $0; sub(/<.*/, "", sangria)
            linea = sangria "<value type=\"int\" value=\"" nuevo "\"/>"
            if (!bandeja && id == reloj) { print linea; print; puesto = 1; next }
            if (bandeja && id == bandeja) { print; print linea; puesto = 1; next }
        }
        /<property name="plugins" type="empty">/ {
            print
            sangria = $0; sub(/<.*/, "", sangria)
            print sangria "  <property name=\"plugin-" nuevo "\" type=\"string\" value=\"pulseaudio\">"
            print sangria "    <property name=\"enable-keyboard-shortcuts\" type=\"bool\" value=\"true\"/>"
            print sangria "  </property>"
            next
        }
        { print }
        END { if (FNR != NR && !puesto) exit 1 }
    ' "$XFCE_PANEL_XML" "$XFCE_PANEL_XML" >"$_xp_tmp" && grep -q 'value="pulseaudio"' "$_xp_tmp"; then
        # Se escribe al lado y se cambia de golpe (mv): si algo falla a
        # mitad, el archivo original queda intacto.
        cp "$_xp_tmp" "$XFCE_PANEL_XML.nuevo" && chmod 644 "$XFCE_PANEL_XML.nuevo" \
            && mv -f "$XFCE_PANEL_XML.nuevo" "$XFCE_PANEL_XML"
        log_ok "Icono de volumen agregado al panel de XFCE (para los usuarios que entren por primera vez)."
    else
        log_warn "No se pudo agregar el icono de volumen al panel de XFCE; se agrega a mano en el panel."
    fi
    rm -f "$_xp_tmp"
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
        install_pkgs network-manager-applet xfce4-pulseaudio-plugin
        # Sin el plugin instalado, el panel mostraria un elemento roto.
        if apk info -e xfce4-pulseaudio-plugin >/dev/null 2>&1; then
            xfce_panel_volumen
        fi
    fi

    if [ "$DE_PLASMA" = "yes" ]; then
        install_pkgs plasma-nm plasma-pa
    fi

    if [ "$DE_GNOME" = "yes" ]; then
        # GNOME tiene estos controles incrustados en su shell de forma monolítica.
        # Instalamos pavucontrol como mezclador avanzado de respaldo.
        install_pkg "pavucontrol"
    fi

    if [ "$DE_MATE" = "yes" ]; then
        # MATE es altamente compatible con el ecosistema GTK de NM.
        install_pkgs network-manager-applet mate-media
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

    if [ "$DE_SWAY" = "yes" ]; then
        setup_sway_barra
    fi

    enable_service networkmanager

    log_ok "Arquitectura de red y audio acoplada al entorno visual."
}

# Sway trae de fabrica una barra que solo muestra la fecha: sin wifi, sin
# volumen y sin menu de aplicaciones. Se cambia por waybar, con:
#   - boton de menu (fuzzel, muestra los programas instalados),
#   - boton con la lista de atajos de teclado (sway-atajos),
#   - icono de wifi de NetworkManager (nm-applet) en la bandeja,
#   - volumen (clic: pavucontrol; rueda del raton: subir/bajar),
#   - red, bateria, brillo y reloj.
# Sway tampoco lee /etc/xdg/autostart, asi que el audio y nm-applet se
# arrancan desde /etc/sway/config.d (que el config de Sway incluye al final).
setup_sway_barra() {
    log_info "Sway: barra con menu de aplicaciones, wifi y volumen (waybar)..."
    install_pkgs waybar font-awesome fuzzel network-manager-applet pavucontrol polkit-gnome

    if ! pkg_installed waybar; then
        log_warn "Sway: no se pudo instalar waybar; queda la barra original."
        return 0
    fi

    sway_conf_sesion
    sway_instalar_atajos
    sway_instalar_apagado
    sway_config_waybar
    log_ok "Sway: barra waybar con menu, wifi y volumen lista."
}

# Programas de la sesion, atajos y barra en /etc/sway/config.d.
sway_conf_sesion() {
    mkdir -p /etc/sway/config.d
    {
        echo "# Lazaro Linux / desktop-postinstall.sh: barra y programas de la sesion."
        if [ -x /usr/libexec/pipewire-launcher ]; then
            echo "exec /usr/libexec/pipewire-launcher"
        elif command -v pulseaudio >/dev/null 2>&1; then
            echo "exec pulseaudio --start"
        fi
        echo "exec nm-applet --indicator"
        # Ventana de contrasena para acciones de administrador (wifi
        # protegido, actualizaciones); Sway no trae una propia.
        echo "exec /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
        echo "# Super+D abre el mismo menu que el boton de la barra."
        echo "bindsym --no-warn \$mod+d exec fuzzel"
        echo "# Super+F1 muestra la lista de atajos de teclado."
        echo "bindsym --no-warn \$mod+F1 exec sway-atajos"
        echo "# La barra que define /etc/sway/config (bar-0) pasa a ser waybar."
        echo "bar bar-0 swaybar_command waybar"
    } > /etc/sway/config.d/50-lazaro-barra.conf
}

# Lista de atajos de teclado (boton de teclado en la barra y Super+F1),
# leida de la configuracion real de Sway y con el ratón: rueda para
# recorrerla y se puede escribir para buscar.
sway_instalar_atajos() {
    mkdir -p /usr/local/bin
    cat > /usr/local/bin/sway-atajos <<'ATAJOS'
#!/bin/sh
# Muestra los atajos de teclado de Sway (boton de la barra y Super+F1).
# Lee la misma configuracion que Sway: la del usuario si existe; si no,
# la del sistema, mas /etc/sway/config.d.
conf="${XDG_CONFIG_HOME:-$HOME/.config}/sway/config"
[ -f "$conf" ] || conf="${SWAY_ATAJOS_CONFIG:-/etc/sway/config}"
idioma="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
case "$idioma" in es*) es=1 ;; *) es=0 ;; esac
extra=""
for f in /etc/sway/config.d/*; do
    [ -f "$f" ] && extra="$extra $f"
done

lista() {
    # shellcheck disable=SC2086
    awk -v es="$es" '
    function nombre_tecla(k,   n, i, p, out, t) {
        n = split(k, p, "[+]"); out = ""
        for (i = 1; i <= n; i++) {
            t = p[i]
            if (t == "Mod4") t = "Super"
            else if (t == "Mod1") t = "Alt"
            else if (t == "Shift") t = es ? "Mayús" : "Shift"
            else if (t == "Control" || t == "Ctrl") t = "Ctrl"
            else if (t == "Return") t = es ? "Intro" : "Enter"
            else if (t == "space") t = es ? "Espacio" : "Space"
            else if (t == "minus") t = "-"
            else if (t == "Left") t = "←"
            else if (t == "Right") t = "→"
            else if (t == "Up") t = "↑"
            else if (t == "Down") t = "↓"
            else if (t == "Escape") t = "Esc"
            else if (t == "Print") t = es ? "ImprPant" : "Print"
            else if (t ~ /^XF86AudioRaiseVolume$/) t = es ? "Tecla subir volumen" : "Volume up key"
            else if (t ~ /^XF86AudioLowerVolume$/) t = es ? "Tecla bajar volumen" : "Volume down key"
            else if (t ~ /^XF86AudioMute$/) t = es ? "Tecla silenciar" : "Mute key"
            else if (t ~ /^XF86AudioMicMute$/) t = es ? "Tecla silenciar micrófono" : "Mic mute key"
            else if (t ~ /^XF86MonBrightnessUp$/) t = es ? "Tecla subir brillo" : "Brightness up key"
            else if (t ~ /^XF86MonBrightnessDown$/) t = es ? "Tecla bajar brillo" : "Brightness down key"
            else if (length(t) == 1) t = toupper(t)
            out = out (out == "" ? "" : "+") t
        }
        return out
    }
    function lado(d) {
        if (d == "left") return "la izquierda"
        if (d == "right") return "la derecha"
        if (d == "up") return "arriba"
        return "abajo"
    }
    function describir(c,   w, n) {
        if (!es) return c
        n = split(c, w, " ")
        if (c ~ /^exec (foot|\$term)/) return "Abrir la terminal"
        if (c ~ /^exec (fuzzel|wmenu|\$menu|dmenu|wofi)/) return "Menú de aplicaciones"
        if (c ~ /^exec sway-atajos/) return "Ver esta lista de atajos"
        if (c ~ /^exec swaynag.*exit/) return "Salir de Sway (cerrar sesión)"
        if (c ~ /set-sink-mute/) return "Silenciar el sonido"
        if (c ~ /set-sink-volume.*-/) return "Bajar el volumen"
        if (c ~ /set-sink-volume/) return "Subir el volumen"
        if (c ~ /set-source-mute/) return "Silenciar el micrófono"
        if (c ~ /brightnessctl.*-$/) return "Bajar el brillo"
        if (c ~ /brightnessctl/) return "Subir el brillo"
        if (c ~ /^exec grim/) return "Captura de pantalla (se guarda en la carpeta personal)"
        if (c == "kill") return "Cerrar la ventana"
        if (c == "reload") return "Recargar la configuración de Sway"
        if (w[1] == "focus" && w[2] ~ /^(left|right|up|down)$/) return "Pasar a la ventana de " lado(w[2])
        if (w[1] == "move" && w[2] ~ /^(left|right|up|down)$/) return "Mover la ventana hacia " lado(w[2])
        if (c ~ /^workspace number/) return "Ir al escritorio " w[3]
        if (c ~ /^move container to workspace number/) return "Mover la ventana al escritorio " w[6]
        if (c == "splith") return "Abrir la próxima ventana al lado"
        if (c == "splitv") return "Abrir la próxima ventana debajo"
        if (c == "layout stacking") return "Ventanas apiladas"
        if (c == "layout tabbed") return "Ventanas en pestañas"
        if (c == "layout toggle split") return "Cambiar entre lado a lado y una debajo de otra"
        if (c == "fullscreen") return "Pantalla completa (sí/no)"
        if (c == "floating toggle") return "Ventana flotante (sí/no)"
        if (c == "focus mode_toggle") return "Cambiar entre ventanas flotantes y fijas"
        if (c == "focus parent") return "Seleccionar el grupo de ventanas"
        if (c == "move scratchpad") return "Esconder la ventana (cajón)"
        if (c == "scratchpad show") return "Mostrar la ventana escondida (cajón)"
        if (c ~ /^mode "?resize"?$/) return "Modo cambiar tamaño (salir con Esc)"
        if (c ~ /^mode "?default"?$/) return "Salir del modo cambiar tamaño"
        if (c ~ /^resize shrink width/) return "Más angosta"
        if (c ~ /^resize grow width/) return "Más ancha"
        if (c ~ /^resize shrink height/) return "Más baja"
        if (c ~ /^resize grow height/) return "Más alta"
        return c
    }
    function expandir(s,   k) {
        for (k in var) {
            while (index(s, "$" k " ") || substr(s, length(s) - length(k)) == "$" k || index(s, "$" k "+")) {
                s = substr(s, 1, index(s, "$" k) - 1) var[k] substr(s, index(s, "$" k) + length(k) + 1)
            }
        }
        return s
    }
    {
        sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "")
        if ($0 ~ /^#/ || $0 == "") next
        if ($1 == "set" && substr($2, 1, 1) == "$") {
            v = $0; sub(/^set[ \t]+\$[^ \t]+[ \t]+/, "", v)
            var[substr($2, 2)] = v; next
        }
        if ($1 == "mode" && $NF == "{") { modo = $2; gsub(/"/, "", modo); next }
        if ($0 == "}") { modo = ""; next }
        if ($1 != "bindsym") next
        i = 2
        while (substr($i, 1, 2) == "--") i++
        tecla = expandir($i)
        cmd = $0
        sub(/^bindsym[ \t]+/, "", cmd)
        while (cmd ~ /^--/) sub(/^--[^ \t]+[ \t]+/, "", cmd)
        sub(/^[^ \t]+[ \t]+/, "", cmd)
        cmd = expandir(cmd)
        k = (modo == "" ? "" : modo ":") tecla
        if (!(k in desc)) orden[++total] = k
        desc[k] = describir(cmd)
        etiqueta[k] = (modo == "" ? "" : (es ? "[cambiar tamaño] " : "[" modo "] ")) nombre_tecla(tecla)
    }
    END {
        for (j = 1; j <= total; j++) {
            k = orden[j]
            printf "%s  →  %s\n", etiqueta[k], desc[k]
        }
    }' "$conf" $extra
}

if [ "${1:-}" = "--lista" ] || [ -z "${WAYLAND_DISPLAY:-}" ]; then
    lista
else
    if [ "$es" = 1 ]; then prompt="Atajos (escribe para buscar): "; else prompt="Shortcuts: "; fi
    lista | fuzzel --dmenu --width 70 --lines 25 --prompt "$prompt" >/dev/null
fi
ATAJOS
    chmod 755 /usr/local/bin/sway-atajos
}

# Boton de apagado de la barra: menu para cerrar sesion, suspender,
# reiniciar o apagar. elogind deja hacerlo sin contrasena a quien tiene
# la sesion activa (como el boton de apagado de los otros escritorios).
sway_instalar_apagado() {
    mkdir -p /usr/local/bin
    # Se escribe aparte y se cambia de una vez: waybar nunca ve el archivo
    # a medio escribir si el script se repite con la sesion abierta.
    cat > /usr/local/bin/sway-apagar.nuevo <<'APAGAR'
#!/bin/sh
# Menu de la barra de Sway: cerrar sesion, suspender, reiniciar o apagar.
idioma="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
case "$idioma" in
    es*) salir="Cerrar sesión"; susp="Suspender"; rein="Reiniciar"; apag="Apagar"; prompt="¿Qué hacer? " ;;
    *) salir="Log out"; susp="Suspend"; rein="Restart"; apag="Shut down"; prompt="Action: " ;;
esac
# Sin fuzzel (por ejemplo, si no se pudo descargar) se usa swaynag, que
# viene con Sway.
if ! command -v fuzzel >/dev/null 2>&1; then
    exec swaynag -t warning -m "$prompt" \
        -B "$apag" "loginctl poweroff" -B "$rein" "loginctl reboot" \
        -B "$susp" "loginctl suspend" -B "$salir" "swaymsg exit"
fi
eleccion="$(printf '%s\n' "$apag" "$rein" "$susp" "$salir" \
    | fuzzel --dmenu --lines 4 --width 24 --prompt "$prompt")" || exit 0
case "$eleccion" in
    "$apag") exec loginctl poweroff ;;
    "$rein") exec loginctl reboot ;;
    "$susp") exec loginctl suspend ;;
    "$salir") exec swaymsg exit ;;
esac
APAGAR
    chmod 755 /usr/local/bin/sway-apagar.nuevo
    mv -f /usr/local/bin/sway-apagar.nuevo /usr/local/bin/sway-apagar
}

# Configuracion de waybar para el usuario y para los usuarios nuevos.
# Solo iconos y reloj con el idioma del sistema: sirve en cualquier idioma.
sway_config_waybar() {
    for base in /etc/skel "$TARGET_HOME"; do
        [ -n "$base" ] || continue
        config_nuevo=no
        [ -d "$base/.config" ] || config_nuevo=yes
        waybar_conf="$base/.config/waybar/config.jsonc"
        # Si ya hay una configuracion (propia del usuario), se respeta.
        if [ -e "$waybar_conf" ] || [ -L "$waybar_conf" ] || [ -L "$base/.config/waybar" ]; then
            log_info "Sway: ya existe $waybar_conf; no se cambia."
            continue
        fi
        mkdir -p "$base/.config/waybar"
        cat > "$waybar_conf" <<'WAYBAR'
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "modules-left": ["custom/menu", "custom/atajos", "sway/workspaces", "sway/mode"],
    "modules-center": ["clock"],
    "modules-right": ["custom/actualizaciones", "tray", "pulseaudio", "network", "backlight", "battery", "custom/apagado"],
    "custom/menu": {
        "format": "    ",
        "tooltip": false,
        "on-click": "fuzzel"
    },
    "custom/atajos": {
        "format": " \uf11c ",
        "tooltip": false,
        "on-click": "sway-atajos"
    },
    "custom/apagado": {
        "format": " \uf011 ",
        "tooltip": false,
        "on-click": "sway-apagar"
    },
    "custom/actualizaciones": {
        "exec": "n=$(cat /var/lib/alpine-update/pendientes 2>/dev/null); [ \"${n:-0}\" -gt 0 ] 2>/dev/null && echo \"$n\" || true",
        "interval": 60,
        "format": "\uf019 {}",
        "tooltip-format": "Hay actualizaciones: clic para instalarlas",
        "on-click": "/usr/local/bin/alpine-update-launcher.sh"
    },
    "clock": {
        "format": "{:%a %d %b  %H:%M}",
        "tooltip-format": "<tt>{calendar}</tt>"
    },
    "tray": { "spacing": 8 },
    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": "",
        "format-icons": { "default": ["", "", ""] },
        "on-click": "pavucontrol"
    },
    "network": {
        "format-wifi": " {signalStrength}%",
        "format-ethernet": "",
        "format-disconnected": "",
        "tooltip-format": "{ifname} {ipaddr}",
        "tooltip-format-wifi": "{essid} {ipaddr}",
        "on-click": "foot nmtui"
    },
    "backlight": {
        "format": " {percent}%"
    },
    "battery": {
        "states": { "warning": 25, "critical": 10 },
        "format": "{icon} {capacity}%",
        "format-charging": " {capacity}%",
        "format-icons": ["", "", "", "", ""]
    }
}
WAYBAR
        if [ "$base" = "$TARGET_HOME" ] && [ -n "$TARGET_USER" ]; then
            grupo="$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")"
            chown -h "$TARGET_USER:$grupo" "$base/.config/waybar" "$waybar_conf" \
                || log_warn "No se pudo dar la configuracion de waybar a '$TARGET_USER'."
            if [ "$config_nuevo" = yes ]; then
                chown "$TARGET_USER:$grupo" "$base/.config" || true
            fi
        fi
    done
}

# ------------------------------------------------------------------------------
# BLOQUE 12: Deteccion de hardware de red inalambrica (PCI + USB)
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

    if [ -z "$net_pci" ] && [ -z "$net_usb" ]; then
        if hw_revisado; then
            log_info "No se detecto ningun adaptador de red inalambrica (PCI ni USB)."
            WIFI_INFO=""
        else
            # Sin las herramientas no se sabe: se instala el firmware general
            # (Bloque 13), como si hubiera un adaptador desconocido.
            log_warn "No se pudo revisar del todo el hardware (lspci/lsusb)."
            WIFI_INFO="desconocido"
        fi
        return 0
    fi
    WIFI_INFO="$net_pci
$net_usb"

    log_info "Adaptadores de red detectados:"
    log_info "$WIFI_INFO"
}

# ------------------------------------------------------------------------------
# BLOQUE 13: Firmware de adaptadores WiFi segun fabricante detectado
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
# BLOQUE 14: Deteccion de hardware Bluetooth (PCI + USB)
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

    if [ -z "$bt_pci" ] && [ -z "$bt_usb" ]; then
        if hw_revisado; then
            log_info "No se detecto ningun adaptador Bluetooth (PCI ni USB)."
            BT_INFO=""
        else
            log_warn "No se pudo revisar del todo el hardware (lspci/lsusb); se instala Bluetooth por si acaso."
            BT_INFO="desconocido"
        fi
        return 0
    fi
    BT_INFO="$bt_pci
$bt_usb"

    log_info "Adaptador(es) Bluetooth detectado(s):"
    log_info "$BT_INFO"
}

# ------------------------------------------------------------------------------
# BLOQUE 15: Pila Bluetooth (bluez) y firmware por fabricante
# ------------------------------------------------------------------------------
# NOTA: a diferencia de lo que sugiere el nombre, NO existe un paquete
# generico "linux-firmware-bluetooth" en Alpine -- el firmware de
# Bluetooth esta fragmentado por fabricante igual que el de WiFi
# (linux-firmware-rtl_bt para Realtek, linux-firmware-ar3k para
# Atheros/Qualcomm, linux-firmware-brcm cubre WiFi+Bluetooth combinado
# de Broadcom, linux-firmware-intel cubre combos Intel). Muchos chips
# combo WiFi+Bluetooth ya quedan cubiertos por el firmware que instalo
# el Bloque 13; aqui solo se completa lo especifico de Bluetooth que
# pueda faltar.
install_bluetooth() {
    if [ -z "$BT_INFO" ]; then
        return 0
    fi

    log_info "== Instalando pila Bluetooth (bluez) =="

    # El "puente" que enruta el perfil A2DP hacia el servidor de audio:
    # sin el, bluez permite emparejar el dispositivo pero los
    # audifonos/altavoces Bluetooth no emiten sonido. Depende del servidor
    # elegido en el Bloque 11.
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

    enable_service bluetooth

    log_ok "Soporte Bluetooth instalado y activado (servicio OpenRC: bluetooth)."
}

# ------------------------------------------------------------------------------
# BLOQUE 16: Firmware y controladores de video (NVIDIA: modos ahorro Optimus, seguro y activo)
# ------------------------------------------------------------------------------
install_drivers() {
    log_info "== Instalando firmware y controladores =="

    # El script no pide el metapaquete "linux-firmware" (depende de todos
    # los subpaquetes de fabricante); solo pide los del hardware detectado.
    # Ver la NOTA SOBRE EL FIRMWARE del Bloque 13: en una instalacion
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
        # Sin xf86-video-qxl: con ese driver Xorg no tiene DPMS (apagar la
        # pantalla) y la gestion de energia de LXQt se cierra con "Unsupported
        # extension". El driver "modesetting" de Xorg maneja QXL sin ese fallo.
        install_pkgs xf86-video-vmware spice-vdagent
        if pkg_installed xf86-video-qxl; then
            apk del -q xf86-video-qxl >/dev/null 2>&1 \
                || log_warn "No se pudo quitar xf86-video-qxl."
        fi
        enable_service spice-vdagentd default "Fallo al habilitar spice-vdagentd."
    fi

    if [ "$GPU_HAS_NVIDIA" = "yes" ]; then
        log_info "Instalando soporte NVIDIA (driver abierto Nouveau, vía Gallium)..."
        install_pkgs linux-firmware-nvidia
        # Turing en adelante: Vulkan libre (NVK). Con el, Mesa da tambien
        # OpenGL por encima de Vulkan (Zink), el camino recomendado para
        # estas tarjetas desde Mesa 25.1.
        if [ "$NVIDIA_HAY_MODERNA" = "yes" ]; then
            log_info "NVIDIA moderna (Turing o posterior): instalando Vulkan libre (NVK)."
            install_pkgs mesa-vulkan-nouveau vulkan-loader
        fi

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
            if nvidia_confiable; then
                log_info "NVIDIA $NVIDIA_GEN ($NVIDIA_CHIP): Nouveau la maneja bien; se recomienda dejarla activa."
            else
                log_warn "NVIDIA $NVIDIA_GEN${NVIDIA_CHIP:+ ($NVIDIA_CHIP)}: en tarjetas antiguas (Tesla/Fermi) Nouveau puede causar pantalla negra o cuelgues."
            fi
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
NV_LIGHTDM_SAFE="/etc/lightdm/lightdm.conf.d/40-nvidia-modo-seguro.conf"
INITRAMFS_DIRTY="no"

nvidia_clean_modes() {
    for f in "$NV_BLACKLIST" "$NV_XORG_SAFE" "$NV_XORG_IGPU" "$NV_LOCAL" "$NV_ENV_PLASMA" "$NV_ENV_PROFILE" "$NV_LIGHTDM_SAFE"; do
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
    # Si la NVIDIA es la UNICA grafica y el equipo arranca en modo BIOS,
    # sin nouveau el kernel no tiene ningun dispositivo de pantalla (ni DRM
    # ni framebuffer). Dos consecuencias, vistas en un Compaq Presario CQ50
    # (GeForce 8200M G):
    #   - Xorg no tiene con que dibujar salvo el controlador VESA.
    #   - elogind marca el puesto seat0 como "no grafico" y LightDM espera
    #     para siempre sin abrir la pantalla de inicio.
    # VESA solo se usa si no hay otro controlador, y la opcion de LightDM
    # no cambia nada cuando si hay pantalla del kernel. Los escritorios
    # Wayland (GNOME, Sway, XFCE Wayland) necesitan DRM y no funcionan asi.
    install_pkgs xf86-video-vesa
    if ! pkg_installed xf86-video-vesa; then
        log_warn "No se pudo instalar xf86-video-vesa: si la NVIDIA es la unica grafica y el equipo arranca en modo BIOS, la pantalla de inicio puede no abrir. Instalalo luego con: doas apk add xf86-video-vesa"
    fi
    mkdir -p "$(dirname "$NV_LIGHTDM_SAFE")"
    cat > "$NV_LIGHTDM_SAFE" <<'EOF'
# Generado por desktop-postinstall.sh (NVIDIA en modo seguro): no esperar a
# que elogind vea un dispositivo de pantalla del kernel para abrir LightDM.
[LightDM]
logind-check-graphical=false
EOF
    log_ok "Modo seguro aplicado: $NV_BLACKLIST"
    log_info "La NVIDIA quedara sin driver. Ojo: sin driver tampoco se apaga y sigue consumiendo energia."
    log_info "Para revertir: borra ese archivo y $NV_LIGHTDM_SAFE, ejecuta 'mkinitfs <version-del-kernel>' y reinicia."
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
# BLOQUE 17: Dispositivos sin controlador y capas de compatibilidad
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
# BLOQUE 18: Detección de CPU y microcódigo
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
# BLOQUE 19: zram (memoria comprimida al 100% de la RAM física)
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

    enable_service zram-init

    log_ok "zram configurado (swap comprimido = 100% de la RAM, algoritmo zstd)."
}

# ------------------------------------------------------------------------------
# BLOQUE 20: EarlyOOM
# ------------------------------------------------------------------------------
setup_earlyoom() {
    log_info "== Configurando EarlyOOM =="
    install_pkgs earlyoom earlyoom-openrc
    enable_service earlyoom
    log_ok "EarlyOOM configurado."
}

# ------------------------------------------------------------------------------
# BLOQUE 21: Gestión de energía básica (ACPI)
# ------------------------------------------------------------------------------
# CORRECCION: antes se habilitaba acpid siempre. Desde mayo de 2025,
# setup-desktop (alpine-conf) lo DESHABILITA a proposito en los equipos
# de escritorio, porque podia apagar el sistema por accidente: con un
# escritorio, elogind ya atiende el boton de encendido y la tapa, y acpid
# respondia al mismo evento por su cuenta. Este script instala elogind
# siempre (Bloque 24), asi que acpid solo se habilita si no hay escritorio.
setup_power() {
    log_info "== Configurando gestión de energía (ACPI) =="
    if has_desktop; then
        if rc-update show default 2>/dev/null | grep -q '^ *acpid '; then
            rc-update del acpid default >/dev/null 2>&1 || true
            log_info "acpid quitado del arranque: con escritorio, elogind maneja el boton de encendido y la tapa (igual que hace setup-desktop)."
        fi
        log_ok "Gestion de energia a cargo de elogind."
        return 0
    fi
    install_pkgs acpid acpid-openrc
    enable_service acpid
    log_ok "acpid configurado (sistema sin escritorio)."
}

# ------------------------------------------------------------------------------
# BLOQUE 22: Optimizacion de discos duros mecanicos (HDD)
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
# BLOQUE 23: TRIM semanal para discos de estado solido
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
# BLOQUE 24: Montaje automático de USB (udisks2 + polkit + gvfs por DE)
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
    enable_service dbus

    install_pkg "udisks2"

    install_pkg "elogind"
    enable_service elogind

    install_pkg "polkit-elogind"
    enable_service polkit

    if [ "$DE_XFCE" = "yes" ]; then
        install_pkgs gvfs thunar-volman
    fi

    if [ "$DE_GNOME" = "yes" ]; then
        install_pkg "gvfs"
    fi

    if [ "$DE_MATE" = "yes" ]; then
        install_pkg "gvfs"
    fi

    if [ "$DE_LXQT" = "yes" ]; then
        install_pkgs gvfs lxqt-policykit
    fi

    if [ "$DE_PLASMA" = "yes" ]; then
        log_info "Plasma detectado: Dolphin usa KIO/Solid + udisks2 directamente, sin necesidad de gvfs."
    fi

    log_ok "Montaje automático de USB configurado. Verifica al conectar un USB tras reiniciar."
}

# ------------------------------------------------------------------------------
# BLOQUE 25: Soporte de impresión (CUPS)
# ------------------------------------------------------------------------------
setup_printing() {
    log_info "== Soporte de impresión (CUPS) =="

    if ! want OPT_CUPS "¿Deseas instalar soporte de impresión (CUPS)?"; then
        log_info "Se omite CUPS."
        return 0
    fi

    log_info "== Configurando soporte de impresión (CUPS) =="
    install_pkgs cups cups-openrc cups-filters system-config-printer
    enable_service cupsd
    log_ok "CUPS configurado. Interfaz web disponible en http://localhost:631"
}

# ------------------------------------------------------------------------------
# BLOQUE 26: Backends de compresión
# ------------------------------------------------------------------------------
install_archive_tools() {
    log_info "== Instalando utilidades de compresión =="
    install_pkgs zip unzip 7zip
    log_ok "Backends de compresión instalados (zip/unzip/7z)."
}

# ------------------------------------------------------------------------------
# BLOQUE 27: Herramientas de terminal opcionales (Fastfetch, Btop)
# ------------------------------------------------------------------------------
# Fastfetch muestra un resumen del equipo (sistema, procesador, memoria);
# Btop es un monitor de recursos a pantalla completa. Los dos funcionan
# tambien sin escritorio.
install_console_tools() {
    log_info "== Herramientas de terminal =="
    _herramientas=""
    if want OPT_FASTFETCH "¿Deseas instalar Fastfetch (resumen del equipo en la terminal)?"; then
        _herramientas="fastfetch"
    fi
    if want OPT_BTOP "¿Deseas instalar Btop (monitor de procesador, memoria y discos)?"; then
        _herramientas="$_herramientas btop"
    fi
    if [ -z "$_herramientas" ]; then
        log_info "Se omiten Fastfetch y Btop."
        return 0
    fi
    # shellcheck disable=SC2086
    install_pkgs $_herramientas
}

# ------------------------------------------------------------------------------
# BLOQUE 28: Idioma (español por defecto, u OPT_LANG) — sistema, XFCE y propagación global a Plasma
# ------------------------------------------------------------------------------
setup_locale() {
    # Idioma: espanol de Espana salvo que se indique otro con OPT_LANG
    # (por ejemplo el que se eligio en el instalador de Lazaro Linux).
    idioma="${OPT_LANG:-es_ES.UTF-8}"
    # Forma aceptada: xx_XX.UTF-8 o xxx_XX.UTF-8, con un modificador
    # opcional de letras (por ejemplo sr_RS.UTF-8@latin).
    valido=no
    case "${idioma%@*}" in
        [a-z][a-z]_[A-Z][A-Z].UTF-8|[a-z][a-z][a-z]_[A-Z][A-Z].UTF-8) valido=yes ;;
    esac
    case "$idioma" in
        *@) valido=no ;;
        *@*) case "${idioma#*@}" in *[!a-z]*) valido=no ;; esac ;;
    esac
    if [ "$valido" != yes ]; then
        log_warn "Idioma no valido '$idioma'; se usa es_ES.UTF-8."
        idioma="es_ES.UTF-8"
    fi
    region="${idioma%%.*}"
    traducciones="$region:${region%%_*}"
    case "$idioma" in
        *@*) traducciones="$region@${idioma#*@}:${region%%_*}@${idioma#*@}:$traducciones" ;;
    esac
    log_info "== Configurando el idioma del sistema ($idioma) =="

    install_pkgs musl-locales musl-locales-lang

    if [ -f /etc/rc.conf ] && ! grep -q '^unicode="YES"' /etc/rc.conf; then
        sed -i 's/#unicode="NO"/#unicode="NO"\nunicode="YES"/' /etc/rc.conf 2>/dev/null || true
    fi

    cat > /etc/profile.d/idioma-sistema.sh <<EOF
export LANG="$idioma"
export LC_ALL="$idioma"
export LC_MESSAGES="$idioma"
EOF
    chmod +x /etc/profile.d/idioma-sistema.sh
    # Nombre de versiones anteriores, que siempre ponian espanol (se
    # borra despues de escribir el nuevo).
    rm -f /etc/profile.d/lang-es.sh
    log_ok "Capa 1/3: variables de idioma escritas en /etc/profile.d/idioma-sistema.sh"

    if [ -f /etc/environment ]; then
        sed -i '/^LANG=/d;/^LC_ALL=/d;/^LC_MESSAGES=/d' /etc/environment
    fi
    {
        echo "LANG=$idioma"
        echo "LC_ALL=$idioma"
        echo "LC_MESSAGES=$idioma"
    } >> /etc/environment
    log_ok "Capa 2/3: variables de idioma agregadas a /etc/environment (leído por PAM en la mayoría de gestores de sesión gráficos)."

    install_pkg "lang"

    if [ "$DE_PLASMA" = "yes" ]; then
        log_info "Reforzando traducciones específicas de Plasma..."
        install_pkgs plasma-desktop-lang kdeplasma-addons-lang

        mkdir -p /etc/xdg
        cat > /etc/xdg/plasma-localerc <<EOF
[Formats]
LANG=$idioma

[Translations]
LANGUAGE=$traducciones
EOF
        log_ok "Capa 3/3: default de sistema escrito en /etc/xdg/plasma-localerc (aplica a usuarios nuevos)."

        if [ -n "$TARGET_USER" ] && [ -n "$TARGET_HOME" ]; then
            config_dir="$TARGET_HOME/.config"
            grupo="$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")"
            mkdir -p "$config_dir"
            cat > "$config_dir/plasma-localerc" <<EOF
[Formats]
LANG=$idioma

[Translations]
LANGUAGE=$traducciones
EOF
            chown -h "$TARGET_USER:$grupo" "$config_dir/plasma-localerc" \
                || log_warn "No se pudo dar plasma-localerc a '$TARGET_USER'."
            # ~/.config tiene que ser del usuario. Si el script corre antes
            # del primer inicio de sesión, la carpeta la acaba de crear root
            # (o una versión anterior de este script) y Plasma no podría
            # guardar nada ahí ("kioworkerrc not writable"). Se cambia de
            # dueño después de escribir el archivo, para que el usuario no
            # pueda meter un enlace en medio.
            chown -h "$TARGET_USER:$grupo" "$config_dir" \
                || log_warn "No se pudo dar $config_dir a '$TARGET_USER': Plasma no podrá guardar su configuración."
            log_ok "Capa 3/3: idioma de Plasma pre-configurado también para el usuario existente '$TARGET_USER'."
        else
            log_warn "No se detectó un usuario existente; solo quedó el default de sistema en /etc/xdg/plasma-localerc."
        fi
    fi

    log_ok "Idioma $idioma configurado para el/los entorno(s) detectado(s)."
}

# ------------------------------------------------------------------------------
# BLOQUE 29: Tipografías base (antes de LibreOffice)
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
# BLOQUE 30: LibreOffice + paquete de idioma del sistema
# ------------------------------------------------------------------------------
install_libreoffice() {
    log_info "== LibreOffice =="

    if ! want OPT_LIBREOFFICE "¿Deseas instalar LibreOffice? (paquete pesado; si prefieres OnlyOffice vía Flatpak, puedes responder 'n' aquí y aceptarlo más adelante)"; then
        log_info "Se omite LibreOffice."
        return 0
    fi

    # Paquete de idioma: el del sistema ya validado por setup_locale,
    # que corre antes (por defecto espanol).
    # Alpine los nombra por region (libreoffice-lang-pt_br) o por idioma
    # (libreoffice-lang-es); el ingles viene incluido.
    lo_region="$(printf '%s' "${idioma:-es_ES.UTF-8}" | sed 's/[.@].*//' | tr '[:upper:]' '[:lower:]')"
    lo_idioma=""
    for p in "libreoffice-lang-$lo_region" "libreoffice-lang-${lo_region%%_*}"; do
        case "$p" in *[!a-z_-]*) continue ;; esac
        if apk search -qx "$p" 2>/dev/null | grep -qx "$p"; then
            lo_idioma="$p"
            break
        fi
    done
    log_info "== Instalando LibreOffice =="
    # shellcheck disable=SC2086  # vacio si no hay paquete de idioma
    install_pkgs libreoffice $lo_idioma
    log_ok "LibreOffice instalado${lo_idioma:+ ($lo_idioma)}."
}

# Instala una aplicacion de Flathub ($1 = id, $2 = nombre para mostrar).
# Si la descarga falla por la red, espera a que vuelva y reintenta (hasta
# 3 intentos). Si aun asi no se puede, o falla por otra causa, queda
# pendiente (flatpak_pendiente). Otra causa conocida: Google Chrome se
# descarga de la pagina de Google durante la instalacion y ese paso no
# funciona dentro del sistema que se esta instalando (chroot).
FLATPAK_PENDIENTES="/etc/flatpak-pendientes"
FLATHUB_LISTO="no"
flatpak_app() {
    if [ "$FLATHUB_LISTO" = "no" ]; then
        flatpak_pendiente "$1" "$2"
        return 0
    fi
    _fp_salida="$(mktemp)"
    _fp_intento=1
    while :; do
        # shellcheck disable=SC2086
        if con_avance $remote_add_cmd install -y --noninteractive flathub "$1" >"$_fp_salida" 2>&1; then
            cat "$_fp_salida" >>"$LOG_FILE"; rm -f "$_fp_salida"
            log_ok "$2 instalado."
            return 0
        fi
        cat "$_fp_salida" >>"$LOG_FILE"
        [ "$_fp_intento" -lt 3 ] || break
        grep -qiE 'resolve|curl|could not connect|couldn.t connect|timeout|timed out|connection|network|error receiving data' "$_fp_salida" || break
        esperar_red || break
        log_warn "$2: la descarga fallo por la conexion; se reintenta ($_fp_intento/3)..."
        _fp_intento=$((_fp_intento + 1))
    done
    rm -f "$_fp_salida"
    flatpak_pendiente "$1" "$2"
}

# Deja una aplicacion de Flathub pendiente: se instala sola, en segundo
# plano, en cada arranque con internet (hasta 20 minutos por arranque)
# hasta lograrlo. Tambien agrega Flathub si no se pudo agregar antes.
flatpak_pendiente() {
    log_warn "$2 no se pudo instalar ahora; se instalara solo despues de arrancar el equipo con internet."
    grep -qx "$1" "$FLATPAK_PENDIENTES" 2>/dev/null || echo "$1" >>"$FLATPAK_PENDIENTES"
    mkdir -p /etc/local.d
    cat > /etc/local.d/flatpak-pendientes.start <<'PEND'
#!/bin/sh
# Generado por desktop-postinstall.sh: instala en segundo plano las
# aplicaciones de Flathub que no se pudieron instalar antes. Se borra
# sola cuando no queda ninguna pendiente.
lista=/etc/flatpak-pendientes
[ -s "$lista" ] || { rm -f "$0"; exit 0; }
(
    i=0
    while [ -s "$lista" ] && [ $i -lt 20 ]; do
        sleep 60
        i=$((i + 1))
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
            >>/var/log/flatpak-pendientes.log 2>&1 || continue
        for app in $(cat "$lista"); do
            if flatpak install -y --noninteractive flathub "$app" >>/var/log/flatpak-pendientes.log 2>&1; then
                grep -vx "$app" "$lista" > "$lista.tmp"; mv -f "$lista.tmp" "$lista"
            fi
        done
    done
    [ -s "$lista" ] || rm -f "$lista" /etc/local.d/flatpak-pendientes.start
) >/dev/null 2>&1 &
PEND
    chmod 755 /etc/local.d/flatpak-pendientes.start
    rc-update add local default >/dev/null 2>&1 || log_warn "No se pudo habilitar el servicio 'local' de OpenRC."
    return 0
}

# ------------------------------------------------------------------------------
# BLOQUE 31: Aplicaciones de uso diario y aplicaciones predeterminadas
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

# YouTube ligero: se busca con gtk-pipe-viewer y se ve en mpv, sin
# navegador. En equipos de un nucleo y 2 GB es mucho mas liviano que
# YouTube en Firefox. Limita a 480p, H.264 (avc1) y 30 cuadros: lo que un
# procesador viejo decodifica sin trabarse (VP9, AV1 y 60 fps no).
# yt-dlp necesita un motor de JavaScript para los desafios de YouTube. Se
# pide QuickJS a proposito (menos de 1 MB): sin pedirlo, apk elige Deno
# (unos 40 MB). El paquete yt-dlp de Alpine ya trae el componente
# yt-dlp-ejs, pero solo activa deno y node: /etc/yt-dlp.conf activa
# QuickJS para todos (mpv y pipe-viewer llaman al mismo yt-dlp).
# Las configuraciones se escriben solo si no existen: un cambio del
# usuario (por ejemplo bajar a 360p) se respeta.
configurar_youtube() {
    install_pkgs pipe-viewer pipe-viewer-gtk mpv yt-dlp yt-dlp-ejs-rt-quickjs
    for _yt in gtk-pipe-viewer mpv yt-dlp qjs; do
        if ! command -v "$_yt" >/dev/null 2>&1; then
            log_warn "No se pudo instalar $_yt; se omite YouTube ligero."
            return 0
        fi
    done

    if [ -e /etc/yt-dlp.conf ]; then
        # Si ya existia sin motor de JavaScript elegido, se agrega QuickJS
        # sin tocar lo demas.
        grep -q -e '--js-runtimes' /etc/yt-dlp.conf \
            || printf '%s\n' '--js-runtimes quickjs' >> /etc/yt-dlp.conf
    else
        cat > /etc/yt-dlp.conf <<'YTDLP'
# yt-dlp para todo el sistema (lo usan mpv y pipe-viewer).
# Motor de JavaScript para los desafios de YouTube: QuickJS, el mas
# liviano. Si deja de funcionar, se puede probar con "deno" instalando
# el paquete deno (unos 40 MB).
--js-runtimes quickjs
YTDLP
    fi

    mkdir -p /etc/mpv
    if [ ! -e /etc/mpv/mpv.conf ]; then
        cat > /etc/mpv/mpv.conf <<'MPV'
# mpv para todo el sistema, pensado para equipos de un nucleo y 2 GB.
# Cada usuario puede cambiarlo en ~/.config/mpv/mpv.conf.

# Videos de internet (YouTube y otros) cuando mpv los abre directamente:
# hasta 480p, H.264 (avc1) y 30 cuadros, con audio AAC. Si no hay esa
# combinacion, lo mas parecido hasta 480p; si no hay nada hasta 480p, la
# calidad mas baja que haya (nunca la mas alta).
# Para 360p: cambiar cada 480 por 360.
ytdl-format=bestvideo[height<=?480][vcodec^=avc1][fps<=30]+bestaudio[acodec^=mp4a]/best[height<=?480][vcodec^=avc1][fps<=?30]/best[height<=?480][vcodec^=avc1]/best[height<=?480]/worst

# Decodificar con la grafica si puede; si no, con el procesador, sin errores.
hwdec=auto-safe

# Memoria para el video ya descargado: suficiente para unos minutos de
# 480p sin pedir demasiada RAM.
cache=yes
demuxer-max-bytes=50MiB
demuxer-max-back-bytes=10MiB
MPV
    fi

    for base in /etc/skel "$TARGET_HOME"; do
        [ -n "$base" ] || continue
        mkdir -p "$base/.config/pipe-viewer"
        # pipe-viewer completa las demas opciones con sus valores por
        # defecto (todas las de aqui existen en pipe-viewer 0.5.3).
        for pv in gtk-pipe-viewer pipe-viewer; do
            [ -e "$base/.config/pipe-viewer/$pv.conf" ] && continue
            cat > "$base/.config/pipe-viewer/$pv.conf" <<'PIPEVIEWER'
#!/usr/bin/perl
# Lazaro Linux: solo las opciones que cambian; las demas las agrega
# pipe-viewer con su valor por defecto.
use utf8;
our $CONFIG = {
  # mpv (por defecto: el primero que encuentra)
  video_player_selected => "mpv",
  # 480p (por defecto: "best"). Para 360p: "360".
  resolution            => "480",
  # MP4/H.264 y audio M4A (por defecto: 0, 0)
  prefer_mp4            => 1,
  prefer_m4a            => 1,
  # Sin AV1 ni 60 cuadros (por defecto: 0, 1)
  ignore_av1            => 1,
  hfr                   => 0,
  # Subtitulos en espanol primero (por defecto: ["en", "es"])
  srt_languages         => ["es", "en"],
  # Miles con punto (por defecto: ",")
  thousand_separator    => ".",
};
PIPEVIEWER
        done
    done

    # El menu muestra "YouTube" con un icono generico de video, en lugar
    # de "GTK Pipe Viewer".
    cat > /usr/share/applications/lazaro-youtube.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=YouTube
GenericName=Videos de YouTube
Comment=Search and watch YouTube videos without a web browser
Comment[es]=Buscar y ver videos de YouTube sin navegador
Exec=gtk-pipe-viewer
Icon=applications-multimedia
Terminal=false
StartupNotify=true
Categories=AudioVideo;Video;Player;Network;
Keywords=youtube;video;videos;musica;pipe-viewer;
DESKTOP
    mkdir -p /usr/local/share/applications
    if [ -f /usr/share/applications/gtk-pipe-viewer.desktop ]; then
        sed '/^\[Desktop Entry\]/a NoDisplay=true' /usr/share/applications/gtk-pipe-viewer.desktop \
            > /usr/local/share/applications/gtk-pipe-viewer.desktop
    fi
    log_ok "YouTube ligero listo: menu > YouTube (480p, H.264, QuickJS)."
}

install_daily_apps() {
    log_info "== Aplicaciones de uso diario =="

    if ! has_desktop; then
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
    if [ "$DE_XFCE" = "yes" ] || [ "$DE_GNOME" = "yes" ] || [ "$DE_MATE" = "yes" ] || [ "$DE_LXQT" = "yes" ] || [ "$DE_SWAY" = "yes" ]; then
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
    # de video por hardware (VA-API) instalada en el Bloque 16. Cubre los
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

    # --- VLC (opcional) ---
    # Reproductor mas completo que mpv (menus, listas, subtitulos). Si se
    # elige, se instala ademas de mpv, que sigue como predeterminado.
    # El paquete "vlc" de Alpine no trae ventana ni entrada en el menu:
    # esas estan en vlc-qt.
    if want OPT_VLC "¿Deseas instalar el reproductor VLC?"; then
        install_pkgs vlc vlc-qt
    else
        log_info "Se omite VLC."
    fi

    # --- YouTube ligero (opcional) ---
    if want OPT_YOUTUBE "¿Deseas instalar YouTube ligero (buscar y ver videos sin navegador)?"; then
        configurar_youtube
    else
        log_info "Se omite YouTube ligero."
    fi

    # --- Tienda de aplicaciones ---
    # Plasma trae Discover y GNOME trae GNOME Software (los instala
    # setup-desktop). En los demas: Discover en LXQt (Qt, como el
    # escritorio) y GNOME Software en XFCE, MATE y Sway (GTK). Ambas instalan y
    # actualizan paquetes de Alpine y, con Flatpak (Bloque 32), tambien
    # aplicaciones de Flathub: su soporte de Flatpak se agrega solo
    # (install_if) cuando flatpak esta instalado.
    if [ "$DE_LXQT" = "yes" ] && [ "$DE_PLASMA" = "no" ]; then
        install_pkgs discover
    fi
    if { [ "$DE_XFCE" = "yes" ] || [ "$DE_MATE" = "yes" ] || [ "$DE_SWAY" = "yes" ]; } && [ "$DE_GNOME" = "no" ]; then
        install_pkgs gnome-software gnome-software-plugin-apk2 apk-polkit-rs
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
        # (es_ES u OPT_LANG). Forzar otra variante requeriria descargas atadas a la
        # version exacta del navegador, que se romperian al actualizarlo.
        log_info "En su primer arranque, Firefox ofrecera cambiar su interfaz al idioma del sistema."
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
# BLOQUE 32: Flatpak + Flathub (OnlyOffice, Google Chrome y Brave, opcionales)
# ------------------------------------------------------------------------------
setup_flatpak() {
    log_info "== Flatpak / Flathub =="

    if ! want OPT_FLATPAK "¿Deseas habilitar Flatpak/Flathub en este sistema? (necesario solo si planeas instalar apps como OnlyOffice o Chrome desde Flathub)"; then
        log_info "Se omite Flatpak por completo (no se instala infraestructura ni se preguntará por apps individuales)."
        return 0
    fi

    log_info "== Configurando Flatpak y repositorio Flathub =="

    # dbus ya se instaló y habilitó en el Bloque 24 (setup_usb_automount).
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
        log_warn "flatpak no quedó instalado. Verifica el repositorio 'community'. Se omite esta sección."
        return 0
    fi

    if command -v dbus-run-session >/dev/null 2>&1; then
        remote_add_cmd="dbus-run-session -- flatpak"
    else
        log_warn "'dbus-run-session' no disponible; se ejecuta flatpak sin bus de sesión."
        remote_add_cmd="flatpak"
    fi

    # Agregar Flathub descarga su descripcion: con la red inestable se
    # reintenta. Si no se logra, las aplicaciones quedan pendientes y
    # Flathub se agrega junto con ellas despues del primer arranque.
    FLATHUB_LISTO="no"
    for _intento in 1 2 3; do
        if $remote_add_cmd remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >>"$LOG_FILE" 2>&1; then
            FLATHUB_LISTO="yes"
            break
        fi
        if [ "$_intento" -lt 3 ] && esperar_red; then
            sleep 5
        fi
    done
    if [ "$FLATHUB_LISTO" = "yes" ]; then
        log_ok "Repositorio Flathub agregado (o ya existía)."
    else
        log_warn "No se pudo agregar el repositorio Flathub ahora (¿sin internet?)."
    fi

    if want OPT_ONLYOFFICE "¿Deseas instalar OnlyOffice Desktop Editors vía Flatpak?"; then
        flatpak_app org.onlyoffice.desktopeditors "OnlyOffice"
    else
        log_info "Se omite OnlyOffice."
    fi

    if want OPT_CHROME "¿Deseas instalar Google Chrome vía Flatpak (paquete comunitario, no oficial de Google)?"; then
        flatpak_app com.google.Chrome "Google Chrome"
    else
        log_info "Se omite Google Chrome."
    fi

    if want OPT_BRAVE "¿Deseas instalar el navegador Brave vía Flatpak?"; then
        flatpak_app com.brave.Browser "Brave"
    else
        log_info "Se omite Brave."
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 33: Habilitar el Gestor de Inicio de Sesión (Display Manager)
# ------------------------------------------------------------------------------
# La llave de X que crea la pantalla de inicio queda atada al nombre del
# equipo. Si arranca antes que el servicio "hostname" (pasa en el primer
# arranque), el nombre cambia con la sesion ya abierta y los programas que
# la sesion abre despues (en MATE, el panel) no pueden conectarse a la
# pantalla ("Authorization required"). Se le pide a OpenRC que ponga el
# nombre antes de arrancarla. OpenRC lee /etc/conf.d como un script de
# shell, asi que se agrega una linea al final que suma "hostname" a lo que
# el archivo ya pida, sin tener que entender como esta escrito.
dm_tras_hostname() {
    _conf="/etc/conf.d/$1"
    # shellcheck disable=SC2016  # la linea se escribe tal cual
    _linea='rc_need="${rc_need:-} hostname"'
    grep -qsxF "$_linea" "$_conf" && return 0
    mkdir -p /etc/conf.d
    printf '%s\n' "$_linea" >> "$_conf"
}

# No basta con que setup-desktop lo haya dejado instalado: hay reportes
# reales de lightdm/sddm fallando al no quedar correctamente enganchados
# al runlevel default. A diferencia de una prioridad fija, aquí se usan
# las banderas DE_* ya detectadas (Bloque 6) para elegir el DM que
# corresponde por convención -- la misma que usa el propio setup-desktop
# de Alpine (plasma->sddm, gnome->gdm) -- en vez de encender el primero
# que aparezca instalado. Esto importa en equipos con más de un entorno
# instalado (p. ej. XFCE + Plasma a la vez), donde una prioridad fija
# podría habilitar el DM equivocado para el entorno que realmente se usa.
setup_display_manager() {
    log_info "== Detectando y habilitando Gestor de Inicio de Sesión =="

    setup_greetd_sway
    setup_greetd_idioma

    dm_installed=""
    pkg_installed lightdm && dm_installed="$dm_installed lightdm"
    pkg_installed sddm && dm_installed="$dm_installed sddm"
    pkg_installed gdm && dm_installed="$dm_installed gdm"

    if [ -z "$dm_installed" ]; then
        # Sway y XFCE Wayland usan greetd, que se habilita aparte.
        if pkg_installed greetd; then
            dm_tras_hostname greetd
            if rc-update add greetd default >/dev/null 2>&1; then
                log_ok "Pantalla de inicio 'greetd' habilitada."
            else
                log_warn "Fallo al habilitar 'greetd'."
            fi
        else
            log_warn "No se detectó un Display Manager instalado (lightdm/sddm/gdm/greetd). El sistema arrancará en modo texto."
        fi
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

    dm_tras_hostname "$chosen"
    enable_service "$chosen" default "Fallo al habilitar '$chosen'."
    log_ok "Display Manager '$chosen' habilitado en el runlevel default."
}

# Sway: setup-desktop de Alpine no instala pantalla de inicio para Sway
# (hay que entrar por consola y escribir "sway"). Se le pone la misma que
# Alpine usa para XFCE Wayland: greetd con gtkgreet (dentro de cage), que
# es liviana y no necesita Xorg. Si ya hay otra pantalla de inicio (por
# ejemplo, Sway junto a XFCE), Sway se agrega como sesion en greetd solo
# si greetd es la que esta instalada.
setup_greetd_sway() {
    [ "$DE_SWAY" = "yes" ] || return 0
    if pkg_installed lightdm || pkg_installed sddm || pkg_installed gdm; then
        log_info "Sway: ya hay otra pantalla de inicio instalada; no se agrega greetd."
        return 0
    fi

    log_info "Sway: instalando pantalla de inicio grafica (greetd + gtkgreet)..."
    install_pkg "greetd-gtkgreet"
    if ! pkg_installed greetd-gtkgreet; then
        log_warn "Sway: no se pudo instalar greetd-gtkgreet; se entrara por consola escribiendo 'sway'."
        return 0
    fi
    # Mismos pasos que setup-desktop hace para XFCE Wayland.
    if ! grep -q '^rc_need' /etc/conf.d/greetd 2>/dev/null; then
        echo 'rc_need="seatd dbus"' >> /etc/conf.d/greetd
    fi
    # Igual que el lanzador de Sway de Alpine (sway.desktop): con su propio
    # bus de sesion, que necesitan la bandeja de la barra y el audio.
    if ! grep -qx 'dbus-run-session sway' /etc/greetd/environments 2>/dev/null; then
        echo "dbus-run-session sway" >> /etc/greetd/environments
    fi
    addgroup greetd seat 2>/dev/null || true
    rc-update add dbus default >/dev/null 2>&1 || true
    dm_tras_hostname greetd
    enable_service greetd default "Fallo al habilitar 'greetd'."
    log_ok "Sway: pantalla de inicio greetd habilitada."
}

# gtkgreet corre como el usuario greetd, que no pasa por /etc/profile:
# sin esto, la pantalla de inicio de Sway y XFCE Wayland sale en ingles.
setup_greetd_idioma() {
    [ -f /etc/greetd/config.toml ] || return 0
    gtkgreet_re='^command = "\(env LANG=[^ ]* \)\{0,1\}cage -s -- gtkgreet"'
    grep -q "$gtkgreet_re" /etc/greetd/config.toml || return 0
    idioma_greetd="$(sed -n 's/^LANG=//p' /etc/environment 2>/dev/null | tail -n 1)"
    [ -n "$idioma_greetd" ] || return 0
    sed -i "s|$gtkgreet_re|command = \"env LANG=$idioma_greetd cage -s -- gtkgreet\"|" \
        /etc/greetd/config.toml
    log_ok "Pantalla de inicio greetd en idioma $idioma_greetd."
}

# ------------------------------------------------------------------------------
# BLOQUE 34: La pantalla de inicio usa la resolucion elegida por el usuario
# ------------------------------------------------------------------------------
# Cada escritorio guarda la resolucion en la configuracion del usuario, que
# la pantalla de inicio (LightDM, SDDM, GDM) no lee: esta arranca siempre
# con la resolucion que el monitor sugiere. En un portatil suele ser la
# correcta, pero no en maquinas virtuales ni con monitores externos.
#   - guardar (corre en la sesion del usuario): anota la resolucion actual
#     en ~/.config/pantalla-inicio cada vez que cambia. Lee xrandr en
#     sesiones Xorg (XFCE, MATE, LXQt) y kscreen-doctor en Plasma (Wayland).
#   - aplicar (corre como root al abrir la pantalla de inicio de LightDM o
#     SDDM, ambas sobre Xorg): aplica con xrandr el archivo mas reciente.
#   - GNOME guarda la resolucion en ~/.config/monitors.xml, el mismo
#     formato que lee GDM: un servicio la copia al arrancar.
# Sway y XFCE Wayland (greetd) quedan fuera: su pantalla de inicio no tiene
# un paso donde aplicar la resolucion (usa la que sugiere el monitor).
PANTALLA_DIR="/usr/local/libexec/pantalla-inicio"

setup_greeter_resolution() {
    log_info "== Resolucion de la pantalla de inicio =="

    if ! pkg_installed lightdm && ! pkg_installed sddm && ! pkg_installed gdm; then
        log_info "No hay pantalla de inicio grafica: nada que ajustar."
        return 0
    fi

    mkdir -p "$PANTALLA_DIR"
    pantalla_guardar_script
    pantalla_aplicar_script
    chmod 755 "$PANTALLA_DIR/guardar" "$PANTALLA_DIR/aplicar" "$PANTALLA_DIR/sddm-xsetup"
    pantalla_autoarranque

    if pkg_installed lightdm || pkg_installed sddm; then
        install_pkgs xrandr xauth
    fi
    pantalla_lightdm
    pantalla_sddm
    pantalla_gdm
    log_info "La pantalla de inicio toma la resolucion despues del primer inicio de sesion con la resolucion nueva."
}

# "guardar": anota la resolucion de la sesion del usuario.
pantalla_guardar_script() {
    cat > "$PANTALLA_DIR/guardar" <<'EOF'
#!/bin/sh
# Generado por desktop-postinstall.sh. Anota la resolucion de la sesion
# en ~/.config/pantalla-inicio para que la pantalla de inicio use la
# misma. Revisa cada 3 segundos (al reiniciar no siempre alcanza a correr
# la anotacion final) y una ultima vez al cerrar la sesion.
# Siempre en ~/.config (no en XDG_CONFIG_HOME): ahi la busca "aplicar".
dest="$HOME/.config/pantalla-inicio"

# Una pantalla colgada no debe dejar este proceso esperando para siempre.
con_limite() {
    if command -v timeout >/dev/null 2>&1; then timeout 5 "$@"; else "$@"; fi
}

leer() {
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        # Plasma: "Output: N NOMBRE" y, en sus lineas, "Modes:" con la
        # resolucion actual marcada con "*" (p. ej. 2:1366x768@60*!).
        command -v kscreen-doctor >/dev/null 2>&1 || return 0
        con_limite kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '
            /Output:/ { for (i = 1; i < NF; i++) if ($i == "Output:") nombre = $(i + 2)
                        activa = ($0 ~ /[[:space:]]enabled/) }
            /^[[:space:]]*enabled[[:space:]]*$/ { activa = 1 }
            /^[[:space:]]*disabled[[:space:]]*$/ { activa = 0 }
            /Modes:/ && activa { for (i = 1; i <= NF; i++) if ($i ~ /\*/) {
                    m = $i; sub(/^[0-9]+:/, "", m); sub(/@.*/, "", m); sub(/[*!]+$/, "", m)
                    print nombre, m } }'
    elif [ -n "${DISPLAY:-}" ] && command -v xrandr >/dev/null 2>&1; then
        con_limite xrandr --current 2>/dev/null | awk '$2 == "connected" {
            for (i = 3; i <= NF; i++) if ($i ~ /^[0-9]+x[0-9]+[+]/) {
                m = $i; sub(/[+].*/, "", m); print $1, m; break } }'
    fi
}

# La llave de X de la sesion queda atada al nombre del equipo. Si el
# nombre cambia despues de abrir X (LightDM puede arrancar antes que el
# servicio "hostname"), xrandr ya no puede conectarse aunque el escritorio
# siga funcionando: se usa una copia de la llave valida para cualquier
# nombre (familia "ffff"), igual que en "aplicar". Se llama fuera de
# "$(leer)" para que el cambio de XAUTHORITY dure.
comodin=""
llave_comodin() {
    [ -z "$comodin" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ -n "${DISPLAY:-}" ] \
        && command -v xrandr >/dev/null 2>&1 || return 0
    con_limite xrandr --current >/dev/null 2>&1 && return 0
    command -v xauth >/dev/null 2>&1 || return 0
    original="${XAUTHORITY:-$HOME/.Xauthority}"
    [ -f "$original" ] || return 0
    nueva="$(mktemp)" || return 0
    xauth -f "$original" nlist 2>/dev/null | sed 's/^..../ffff/' \
        | xauth -f "$nueva" nmerge - 2>/dev/null
    # Solo se usa si de verdad abre la pantalla; si no, se reintenta en
    # la siguiente vuelta.
    if XAUTHORITY="$nueva" con_limite xrandr --current >/dev/null 2>&1; then
        comodin="$nueva"
        XAUTHORITY="$comodin"
        export XAUTHORITY
    else
        rm -f "$nueva"
    fi
}

vueltas=10
anotar() {
    actual="$(leer)"
    [ -n "$actual" ] || return 0
    if [ "$actual" != "$(cat "$dest" 2>/dev/null)" ]; then
        mkdir -p "${dest%/*}"
        printf '%s\n' "$actual" > "$dest.tmp.$$" && mv -f "$dest.tmp.$$" "$dest"
    else
        # Con varios usuarios gana el archivo mas reciente: se marca
        # como reciente aunque la resolucion no haya cambiado, cada 10
        # vueltas (30 segundos, como antes), para no escribir en el disco
        # a cada vuelta. Al cerrar la sesion se marca siempre.
        vueltas=$((vueltas + 1))
        if [ "$vueltas" -ge 10 ] || [ "${1:-}" = final ]; then
            touch "$dest"
            vueltas=0
        fi
    fi
}

# Al cerrar la sesion, el escritorio termina este proceso: antes de
# salir se anota por ultima vez (la pantalla aun existe).
trap 'anotar final; [ -z "$comodin" ] || rm -f "$comodin"; exit 0' TERM HUP INT

# La sesion sigue abierta? No se mira el proceso padre: LXQt y otros
# lanzan el autoarranque "separado" y el padre pasa a ser init, que un
# usuario normal no puede consultar. Se pregunta a elogind por la sesion
# y, si no responde, se mira si la pantalla sigue viva.
sesion_viva() {
    if [ -n "${XDG_SESSION_ID:-}" ] && command -v loginctl >/dev/null 2>&1; then
        case "$(con_limite loginctl show-session "$XDG_SESSION_ID" -p State --value 2>/dev/null)" in
            active|online) return 0 ;;
            closing) return 1 ;;
        esac
    fi
    [ -n "$(leer)" ]
}

# Primero se espera a que el escritorio aplique su propia configuracion.
sleep 10
# La llave se revisa antes de cada pregunta por la sesion: si no hay
# loginctl, sesion_viva mira la pantalla con xrandr.
while llave_comodin; sesion_viva; do
    anotar
    sleep 3 &
    wait $!
done
[ -z "$comodin" ] || rm -f "$comodin"
exit 0
EOF
}

# "aplicar": la aplica al abrir la pantalla de inicio (LightDM y SDDM).
pantalla_aplicar_script() {
    cat > "$PANTALLA_DIR/aplicar" <<'EOF'
#!/bin/sh
# Generado por desktop-postinstall.sh. Corre como root al abrir la
# pantalla de inicio (LightDM o SDDM): aplica la resolucion que anoto
# "guardar" en la ultima sesion. Siempre termina bien: si fallara,
# LightDM no mostraria la pantalla de inicio.
archivo=""
for f in /home/*/.config/pantalla-inicio; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    if [ -z "$archivo" ] || [ "$f" -nt "$archivo" ]; then
        archivo="$f"
    fi
done
[ -n "$archivo" ] || exit 0
command -v xrandr >/dev/null 2>&1 || exit 0

# La llave de X que crea LightDM queda atada al nombre del equipo. Si el
# nombre cambia despues de abrir X (LightDM puede arrancar antes que el
# servicio "hostname"), xrandr ya no puede conectarse: se usa una copia
# de la llave valida para cualquier nombre (familia "ffff").
comodin=""
if ! xrandr --query >/dev/null 2>&1 && [ -n "${XAUTHORITY:-}" ] \
        && command -v xauth >/dev/null 2>&1 && comodin="$(mktemp)"; then
    xauth -f "$XAUTHORITY" nlist 2>/dev/null | sed 's/^..../ffff/' \
        | xauth -f "$comodin" nmerge - 2>/dev/null
    XAUTHORITY="$comodin"
    export XAUTHORITY
fi

conectadas="$(xrandr --query 2>/dev/null | awk '$2 == "connected" { print $1 }')"
n_conectadas="$(printf '%s\n' "$conectadas" | grep -c .)"
n_guardadas="$(grep -c . "$archivo")"

while read -r salida modo _; do
    # El archivo lo escribe el usuario: solo se aceptan nombres y
    # resoluciones con forma valida.
    case "$salida" in ''|*[!A-Za-z0-9_-]*) continue ;; esac
    case "$modo" in ''|*[!0-9x]*|x*|*x) continue ;; esac
    if ! printf '%s\n' "$conectadas" | grep -qx "$salida"; then
        # Xorg y Wayland pueden nombrar distinto la misma pantalla: con
        # una sola pantalla de cada lado, se entiende que es la misma.
        [ "$n_guardadas" = 1 ] && [ "$n_conectadas" = 1 ] || continue
        salida="$conectadas"
    fi
    xrandr --output "$salida" --mode "$modo" >/dev/null 2>&1 \
        || logger -t pantalla-inicio "No se pudo poner $salida en $modo (de $archivo)." 2>/dev/null \
        || true
done < "$archivo"
[ -z "$comodin" ] || rm -f "$comodin"
exit 0
EOF

    # SDDM reemplaza su propio Xsetup por el comando configurado: se
    # aplica la resolucion y luego se corre el original.
    cat > "$PANTALLA_DIR/sddm-xsetup" <<'EOF'
#!/bin/sh
# Generado por desktop-postinstall.sh.
/usr/local/libexec/pantalla-inicio/aplicar
[ -x /usr/share/sddm/scripts/Xsetup ] && exec /usr/share/sddm/scripts/Xsetup
exit 0
EOF
}

# Autoarranque de "guardar" en las sesiones (GNOME usa monitors.xml).
pantalla_autoarranque() {
    mkdir -p /etc/xdg/autostart
    cat > /etc/xdg/autostart/pantalla-inicio.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Guardar resolucion para la pantalla de inicio
Exec=$PANTALLA_DIR/guardar
NoDisplay=true
NotShowIn=GNOME;
X-GNOME-Autostart-enabled=true
EOF
}

pantalla_lightdm() {
    if pkg_installed lightdm; then
        mkdir -p /etc/lightdm/lightdm.conf.d
        cat > /etc/lightdm/lightdm.conf.d/50-pantalla-inicio.conf <<EOF
# Generado por desktop-postinstall.sh: resolucion elegida por el usuario.
[Seat:*]
display-setup-script=$PANTALLA_DIR/aplicar
EOF
        log_ok "LightDM usara la resolucion de la ultima sesion."
    fi
}

pantalla_sddm() {
    if pkg_installed sddm; then
        mkdir -p /etc/sddm.conf.d
        # Plasma pone la pantalla de inicio de SDDM sobre Wayland (kwin),
        # donde no hay un paso para aplicar la resolucion: se usa la
        # pantalla de inicio sobre Xorg, como en LXQt. Plasma no trae
        # Xorg; si no se pudo instalar, SDDM se deja como estaba (sin
        # Xorg la pantalla de inicio no apareceria).
        if { [ ! -x /usr/libexec/Xorg ] && [ ! -x /usr/bin/Xorg ]; } \
                || ! pkg_installed xf86-input-libinput; then
            install_pkgs xorg-server xf86-input-libinput
        fi
        servidor=""
        # Hace falta Xorg y su controlador de teclado y raton (libinput);
        # la pantalla usa modesetting, que viene con Xorg.
        if { [ -x /usr/libexec/Xorg ] || [ -x /usr/bin/Xorg ]; } \
                && pkg_installed xf86-input-libinput; then
            servidor="[General]
DisplayServer=x11
"
        fi
        cat > /etc/sddm.conf.d/50-pantalla-inicio.conf <<EOF
# Generado por desktop-postinstall.sh: resolucion elegida por el usuario.
${servidor}[X11]
DisplayCommand=$PANTALLA_DIR/sddm-xsetup
EOF
        log_ok "SDDM usara la resolucion de la ultima sesion."
    fi
}

pantalla_gdm() {
    if pkg_installed gdm; then
        cat > /etc/init.d/pantalla-inicio-gdm <<'EOF'
#!/sbin/openrc-run
# Generado por desktop-postinstall.sh. Copia la configuracion de pantallas
# de GNOME de la ultima sesion (~/.config/monitors.xml) a GDM.
description="Resolucion de GNOME para la pantalla de inicio (GDM)"

depend() {
    before gdm
}

# Se copia al apagar (con la ultima sesion ya cerrada) y otra vez al
# arrancar, antes de GDM: asi el archivo ya esta en su sitio cuando
# arranca la pantalla de inicio.
copiar() {
    archivo=""
    for f in /home/*/.config/monitors.xml; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        if [ -z "$archivo" ] || [ "$f" -nt "$archivo" ]; then
            archivo="$f"
        fi
    done
    [ -n "$archivo" ] || return 0
    # Un monitors.xml normal pesa unos pocos KB.
    [ "$(wc -c < "$archivo")" -le 65536 ] || return 0
    if ! install -d -o gdm -g gdm /var/lib/gdm/.config \
            || ! install -m 644 -o gdm -g gdm "$archivo" /var/lib/gdm/.config/monitors.xml; then
        ewarn "No se pudo copiar $archivo para GDM."
    fi
    return 0
}

start() {
    copiar
}

stop() {
    copiar
}
EOF
        chmod 755 /etc/init.d/pantalla-inicio-gdm
        rc-update add pantalla-inicio-gdm default >/dev/null 2>&1 \
            || log_warn "No se pudo habilitar 'pantalla-inicio-gdm'."
        log_ok "GDM usara la resolucion de la ultima sesion de GNOME."
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 35: Acceso directo de actualizacion en el menu de aplicaciones
# ------------------------------------------------------------------------------
# Los archivos .desktop siguen el estandar XDG Desktop Entry: un unico
# archivo en /usr/share/applications/ aparece automaticamente en el menu
# de TODOS los entornos detectados (XFCE, Plasma, GNOME, MATE, LXQt), sin
# logica especifica por DE -- es justamente para eso que existe el
# estandar.
#
# Autenticacion via pkexec (parte de polkit-elogind, Bloque 24). Por
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

    shortcut_install_deps
    shortcut_add_wheel
    shortcut_write_root_script
    shortcut_write_launcher
    shortcut_prepare_log
    shortcut_write_desktop_file
    shortcut_write_checker
    shortcut_write_notifier

    log_ok "Acceso directo creado: aparecera como 'Actualizar el sistema' en el menu de aplicaciones."
    log_info "Al hacer clic, pedira la contrasena del usuario (no la de root, siempre que pertenezca al grupo 'wheel') y actualizara apk + flatpak."
    log_info "Si hay una version estable nueva de Alpine, el boton preguntara antes si se quiere cambiar a ella."
    log_info "Cuando haya actualizaciones, un icono en la barra (o un aviso) lleva al boton. Plasma usa su propio aviso."
}

# Programas que usan el lanzador y el agente de autenticacion polkit.
shortcut_install_deps() {
    # util-linux-misc trae 'script', necesario en alpine-update-root.sh
    # (shortcut_write_root_script) para forzar a apk/flatpak a comportarse como
    # si escribieran a una terminal real.
    # coreutils trae la version de 'tail' con soporte para --pid, usada
    # en el lanzador (shortcut_write_launcher) para que la ventana de progreso sepa cuando terminar sola
    # (el 'tail' de BusyBox, el de por defecto en Alpine, no tiene esa
    # opcion).
    install_pkgs zenity util-linux-misc coreutils

    # pkexec lanzado desde un menu grafico (sin terminal) NECESITA un
    # agente de autenticacion polkit en ejecucion para dibujar la ventana
    # de contrasena. Sin el, pkexec falla con "No authentication agent
    # found" y la actualizacion nunca empieza. Plasma (polkit-kde-agent),
    # GNOME (integrado en GNOME Shell) y LXQt (lxqt-policykit, Bloque 24)
    # ya traen el suyo; XFCE, MATE y Sway se cubren aqui. Ademas, el lanzador
    # comprueba en cada ejecucion que el agente este CORRIENDO y lo
    # inicia si hace falta: instalar el paquete no garantiza que arranque,
    # porque el autoarranque de polkit-gnome suele estar restringido a
    # ciertos escritorios segun la distribucion.
    if [ "$DE_XFCE" = "yes" ] || [ "$DE_SWAY" = "yes" ]; then
        install_pkgs polkit-gnome
    fi
    if [ "$DE_MATE" = "yes" ]; then
        install_pkgs mate-polkit
    fi
}

# pkexec pide la contrasena del propio usuario solo si esta en "wheel".
shortcut_add_wheel() {
    if [ -z "$TARGET_USER" ]; then
        log_warn "No se determino un usuario estandar; el acceso directo se creara igual, pero verifica manualmente que el usuario este en el grupo 'wheel' para que pkexec pida solo su propia contrasena."
    else
        if ! id -nG "$TARGET_USER" 2>/dev/null | grep -qw wheel; then
            if adduser "$TARGET_USER" wheel; then
                log_ok "Usuario '$TARGET_USER' agregado al grupo 'wheel' (requerido por pkexec)."
            else
                log_warn "No se pudo agregar '$TARGET_USER' al grupo 'wheel'."
            fi
        fi
    fi
}

# alpine-update-root.sh: el trabajo como root (apk + flatpak).
shortcut_write_root_script() {
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
        case "$linea" in
            # Aviso propio de 'script' cuando run_step corta un paso.
            "Session terminated"*) continue ;;
        esac
        echo "# $linea"
    done
}

# Archivo temporal propio (nombre unico): un nombre fijo en /tmp, escrito
# por root, podria haberlo dejado preparado otro usuario.
EXIT_TMP="$(mktemp)"
trap 'rm -f "$EXIT_TMP"' EXIT
# Al cancelar, salir por 'exit' para que tambien se borre.
trap 'exit 130' INT TERM HUP

# Un solo boton a la vez: si se pulsa otra vez mientras el primero sigue
# trabajando (por ejemplo, porque parecia detenido), el segundo avisa y
# sale en vez de quedarse esperando a que apk suelte su base de datos.
LOCK_DIR=/run/alpine-update.lock
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    otro="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
    if [ -n "$otro" ] && kill -0 "$otro" 2>/dev/null; then
        echo "# Ya hay una actualizacion en curso. Espera a que termine (su ventana puede estar detras de otras)."
        exit 75
    fi
    # Quedo de una ejecucion que se corto (apagado, corte de luz).
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || { echo "# No se pudo empezar la actualizacion."; exit 75; }
fi
echo $$ > "$LOCK_DIR/pid"
trap 'rm -f "$EXIT_TMP"; rm -rf "$LOCK_DIR"' EXIT

# Todos los procesos que cuelgan de $1 (hijos, nietos...).
descendants() {
    d_todos="$1"
    d_nuevos="$1"
    while [ -n "$d_nuevos" ]; do
        d_padres="$(echo "$d_nuevos" | tr ' ' '|')"
        d_nuevos="$(grep -H '^PPid:' /proc/[0-9]*/status 2>/dev/null \
            | awk -v p="^($d_padres)\$" '$2 ~ p { split($1, f, "/"); print f[3] }' | tr '\n' ' ')"
        d_nuevos="${d_nuevos% }"
        [ -z "$d_nuevos" ] || d_todos="$d_todos $d_nuevos"
    done
    echo "$d_todos"
}

# Bytes leidos y escritos por esos procesos: si no cambia, no avanzan.
io_total() {
    for io_pid in $1; do
        cat "/proc/$io_pid/io" 2>/dev/null
    done | awk '/^(rchar|wchar):/ { s += $2 } END { print s + 0 }'
}

# Ejecuta un paso, muestra su salida y deja su codigo en $step_status.
#
# Vigilado: apk 3 (y a veces flatpak) puede quedarse para siempre
# esperando una descarga que el servidor dejo de enviar, sin error y sin
# avanzar, y la ventana solo mostraba la barra moviendose. Si en 3
# minutos ni el programa ni lo que el lance (scripts, mkinitfs...) lee
# o escribe nada, se corta y se repite el paso (hasta 3 intentos): la
# repeticion retoma lo que ya se habia descargado.
STALL_LIMIT=180
run_step() {
    rs_intento=1
    while :; do
        : > "$EXIT_TMP"
        ( run_raw "$1; echo \$? > $EXIT_TMP" | prefixed ) &
        rs_pid=$!
        rs_antes=""
        rs_quieto=0
        while kill -0 "$rs_pid" 2>/dev/null; do
            sleep 5
            rs_procs="$(descendants "$rs_pid")"
            rs_ahora="$(io_total "$rs_procs")"
            if [ "$rs_ahora" != "$rs_antes" ]; then
                rs_antes="$rs_ahora"
                rs_quieto=0
            else
                rs_quieto=$((rs_quieto + 5))
            fi
            if [ "$rs_quieto" -ge "$STALL_LIMIT" ]; then
                echo "# La descarga lleva 3 minutos detenida. Se corta y se intenta de nuevo ($rs_intento de 3)..."
                # shellcheck disable=SC2086
                kill $rs_procs 2>/dev/null
                sleep 2
                # shellcheck disable=SC2086
                kill -9 $(descendants "$rs_pid") 2>/dev/null
                break
            fi
        done
        wait "$rs_pid" 2>/dev/null
        step_status="$(cat "$EXIT_TMP" 2>/dev/null)"
        [ -n "$step_status" ] || step_status=1
        if [ "$rs_quieto" -lt "$STALL_LIMIT" ]; then
            return "$step_status"
        fi
        if [ "$rs_intento" -ge 3 ]; then
            echo "# La descarga se detuvo 3 veces. Revisa la conexion a internet e intentalo mas tarde."
            step_status=124
            return 124
        fi
        rs_intento=$((rs_intento + 1))
    done
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
    run_step "flatpak update -y --noninteractive" || true
fi

# El aviso de actualizaciones (alpine-update-revisar) se apaga solo:
# se cuenta otra vez lo que queda por actualizar.
if [ -d /var/lib/alpine-update ]; then
    { apk list -u 2>/dev/null | grep -c . || true; } > /var/lib/alpine-update/pendientes.tmp
    mv -f /var/lib/alpine-update/pendientes.tmp /var/lib/alpine-update/pendientes
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
}

# alpine-update-launcher.sh: la parte grafica, como el usuario.
shortcut_write_launcher() {
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

# Si se cierra la ventana (Cancelar) antes de terminar, el trabajo de
# fondo NO se detiene: cortar apk a mitad de una instalacion podria
# dejar el sistema a medio actualizar. Se avisa y, al terminar, se
# muestra el resultado.
wait "$ZPID" 2>/dev/null
if kill -0 "$BGPID" 2>/dev/null; then
    zenity --info --title="La actualizacion sigue" --width=400 \
        --text="La actualizacion sigue trabajando en segundo plano: cortarla a la mitad podria dejar el sistema a medio actualizar.\n\nNo apagues el equipo. Te avisaremos cuando termine." \
        2>/dev/null &
    wait "$BGPID"
    if tail -n 3 "$LOG" | grep -q "completada sin errores"; then
        zenity --info --title="Actualizacion terminada" --width=380 \
            --text="La actualizacion termino sin errores." 2>/dev/null
    else
        zenity --warning --title="Actualizacion terminada" --width=420 \
            --text="La actualizacion termino con errores. Los detalles estan en $LOG." 2>/dev/null
    fi
fi
wait "$BGPID" 2>/dev/null

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
}

shortcut_prepare_log() {
    # CORRECCION: el lanzador corre como el usuario normal, que NO puede
    # escribir en /var/log. Sin esto, 'tee -a' fallaba en silencio: la
    # ventana funcionaba, pero el log nunca se guardaba. Se crea el
    # archivo perteneciente al grupo 'wheel' (al que el usuario ya se
    # agrego en shortcut_add_wheel) con permiso de escritura para el grupo.
    touch /var/log/alpine-update.log
    chown root:wheel /var/log/alpine-update.log
    chmod 664 /var/log/alpine-update.log
}

# Revision periodica (como root, con crond): cada 6 horas lee los
# repositorios y anota en /var/lib/alpine-update/pendientes cuantos
# paquetes se pueden actualizar. El aviso de la sesion solo lee ese
# numero, sin permisos de administrador.
shortcut_write_checker() {
    mkdir -p /var/lib/alpine-update /etc/periodic/hourly
    cat > /etc/periodic/hourly/alpine-update-revisar <<'INNEREOF'
#!/bin/sh
# Generado por desktop-postinstall.sh: cuenta las actualizaciones
# disponibles para el aviso de la barra. Corre cada hora, pero solo
# revisa si pasaron 6 horas desde la ultima vez (o si nunca reviso).
estado=/var/lib/alpine-update
marca="$estado/ultima-revision"
mkdir -p "$estado"
[ -n "$(find "$marca" -mmin -355 2>/dev/null)" ] && exit 0
# Si el boton "Actualizar el sistema" esta trabajando, no estorbar.
[ -d /run/alpine-update.lock ] && exit 0
# Sin internet (o con la descarga detenida) se intenta la hora siguiente.
timeout 300 apk update -q >/dev/null 2>&1 || exit 0
touch "$marca"
{ apk list -u 2>/dev/null | grep -c . || true; } > "$estado/pendientes.tmp"
mv -f "$estado/pendientes.tmp" "$estado/pendientes"
INNEREOF
    chmod 755 /etc/periodic/hourly/alpine-update-revisar
    enable_service crond
}

# Aviso en la sesion grafica: un icono en la bandeja del panel (XFCE,
# MATE, LXQt) y una notificacion con el boton "Actualizar ahora" (en
# GNOME, que no tiene bandeja, queda solo la notificacion). Los dos
# abren el boton "Actualizar el sistema". Plasma trae su propio aviso
# (Discover) y Sway lo muestra en waybar (sway_config_waybar).
shortcut_write_notifier() {
    if [ "$DE_XFCE" = "no" ] && [ "$DE_MATE" = "no" ] && [ "$DE_LXQT" = "no" ] && [ "$DE_GNOME" = "no" ]; then
        return 0
    fi
    install_pkgs py3-gobject3 gtk+3.0 libnotify

    cat > /usr/local/bin/alpine-update-aviso <<'INNEREOF'
#!/usr/bin/env python3
# Generado por desktop-postinstall.sh: avisa en la sesion cuando hay
# actualizaciones (las cuenta /etc/periodic/hourly/alpine-update-revisar)
# y al hacer clic abre "Actualizar el sistema".
import subprocess
import threading

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

PENDIENTES = "/var/lib/alpine-update/pendientes"
LANZADOR = "/usr/local/bin/alpine-update-launcher.sh"
ICONO = "system-software-update"


def pendientes():
    try:
        with open(PENDIENTES) as f:
            return int(f.read().strip() or 0)
    except (OSError, ValueError):
        return 0


def texto(n):
    if n == 1:
        return "Hay 1 actualizacion disponible"
    return "Hay %d actualizaciones disponibles" % n


def abrir(*_):
    subprocess.Popen([LANZADOR], start_new_session=True)
    return False


def notificar(n):
    # notify-send --wait devuelve el nombre de la accion pulsada.
    def esperar():
        try:
            r = subprocess.run(
                ["notify-send", "--app-name=Actualizar el sistema", "--icon=" + ICONO,
                 "--action=abrir=Actualizar ahora", "--wait",
                 texto(n), "Haz clic en \"Actualizar ahora\" o en el icono de la barra."],
                capture_output=True, text=True, timeout=3600)
        except (OSError, subprocess.SubprocessError):
            return
        if r.stdout.strip() == "abrir":
            GLib.idle_add(abrir)
    threading.Thread(target=esperar, daemon=True).start()


class Aviso:
    def __init__(self):
        self.avisado = 0
        self.icono = Gtk.StatusIcon.new_from_icon_name(ICONO)
        self.icono.set_title("Actualizar el sistema")
        self.icono.set_visible(False)
        self.icono.connect("activate", abrir)
        self.revisar()
        GLib.timeout_add_seconds(60, self.revisar)

    def revisar(self):
        n = pendientes()
        if n > 0:
            self.icono.set_tooltip_text(texto(n) + ". Haz clic para instalarlas.")
            self.icono.set_visible(True)
            if n > self.avisado:
                notificar(n)
            self.avisado = n
        else:
            self.icono.set_visible(False)
            self.avisado = 0
        return True


if __name__ == "__main__":
    Aviso()
    Gtk.main()
INNEREOF
    chmod 755 /usr/local/bin/alpine-update-aviso

    mkdir -p /etc/xdg/autostart
    cat > /etc/xdg/autostart/alpine-update-aviso.desktop <<'INNEREOF'
[Desktop Entry]
Type=Application
Name=Aviso de actualizaciones
Comment=Avisa cuando hay actualizaciones y abre "Actualizar el sistema"
Exec=/usr/local/bin/alpine-update-aviso
Icon=system-software-update
NoDisplay=true
NotShowIn=KDE;
X-GNOME-Autostart-enabled=true
INNEREOF
}

# Entrada del menu de aplicaciones.
shortcut_write_desktop_file() {
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
}

# ------------------------------------------------------------------------------
# BLOQUE 36: Permisos de grupo para Audio/Video/Impresión
# ------------------------------------------------------------------------------
setup_user_groups() {
    log_info "== Configurando permisos de grupo =="

    if [ -z "$TARGET_USER" ]; then
        log_warn "No se determinó un usuario estándar. Ejecuta manualmente: adduser <usuario> audio video lpadmin"
        return 0
    fi

    for grp in audio video lpadmin; do
        # lpadmin lo crea CUPS: si no se instalo la impresora, no existe.
        getent group "$grp" >/dev/null 2>&1 || continue
        if adduser "$TARGET_USER" "$grp"; then
            log_ok "Agregado a '$grp'."
        else
            log_warn "No se pudo agregar a '$grp'."
        fi
    done
}

# ------------------------------------------------------------------------------
# BLOQUE 37: Dueño de los archivos de la carpeta personal
# ------------------------------------------------------------------------------
# El script corre como root y crea algunos archivos en la carpeta del
# usuario (por ejemplo ~/.config). Si el usuario aun no ha entrado nunca
# (sistema recien instalado), esos archivos quedarian de root y el
# escritorio no podria guardar su configuracion (Plasma: "kioworkerrc not
# writable"). Se devuelven al usuario solo los archivos que son de root.
fix_home_owner() {
    [ -n "$TARGET_USER" ] && [ -n "$TARGET_HOME" ] || return 0
    case "$TARGET_HOME" in
        /|/root|/home) return 0 ;;
    esac
    _grupo="$(id -gn "$TARGET_USER" 2>/dev/null)" || return 0
    if find "$TARGET_HOME" -xdev -user root -exec chown -h "$TARGET_USER:$_grupo" {} \; 2>>"$LOG_FILE"; then
        log_ok "Archivos de $TARGET_HOME devueltos a '$TARGET_USER'."
    else
        log_warn "No se pudieron revisar los dueños de los archivos de $TARGET_HOME."
    fi
}

# ------------------------------------------------------------------------------
# BLOQUE 38: Función principal
# ------------------------------------------------------------------------------
main() {
    # Primero las opciones: --ayuda o un error de uso no necesitan root
    # ni tocan nada.
    leer_argumentos "$@"
    log_info "===== Iniciando configuración post-instalación de escritorio en Alpine Linux ====="

    check_root
    [ -z "$ARG_DESTINO" ] || ejecutar_en_destino   # no vuelve
    update_system
    install_desktop
    # Hardware y escritorio se detectan ANTES de las decisiones (Bloque 8):
    # la opcion de NVIDIA solo aparece si hay una NVIDIA, y los programas
    # graficos solo si hay escritorio.
    detect_desktop_environment
    detect_hardware
    decidir_opciones
    setup_keyboard_layout
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
    install_console_tools
    setup_locale
    install_fonts
    install_libreoffice
    install_daily_apps
    setup_flatpak
    setup_display_manager
    setup_greeter_resolution
    setup_update_shortcut
    setup_user_groups
    fix_home_owner
    reparar_pasos_finales

    print_browser_recommendations
    if [ "$FALLOS_DE_RED" -gt 0 ]; then
        log_warn "===== Terminado, pero $FALLOS_DE_RED descarga(s) fallaron por la conexion a internet ====="
        log_warn "Cuando la conexion este estable, vuelve a ejecutar el script con las mismas opciones: lo ya instalado no se repite."
    else
        log_ok "===== Proceso completado exitosamente ====="
    fi
    log_info "Reinicia el sistema para que todos los cambios surtan efecto."

    trap - EXIT INT TERM
    # Codigo 3: termino, pero faltan descargas (un instalador puede
    # programar otro intento).
    [ "$FALLOS_DE_RED" -eq 0 ] || exit 3
}

main "$@"
