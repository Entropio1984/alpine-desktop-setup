#!/bin/sh -e
# Genera el apkovl (la configuración) de la sesión live de Lázaro Linux.
# Lo ejecuta mkimage.sh bajo fakeroot, con el nombre de host como $1.
# Variables que deja build.sh / el perfil:
#   LAZARO_LIVE_DIR  carpeta lazaro-linux/live (archivos a copiar tal cual)
#   LAZARO_SCRIPT    ruta a desktop-postinstall.sh
#   LAZARO_VERSION_ENV  archivo con la versión de Alpine y de la ISO
#   LAZARO_WORLD     paquetes de la sesión live
#   LAZARO_PUBKEY    llave pública que firma el repositorio de la ISO

HOSTNAME="$1"
[ -n "$HOSTNAME" ] || { echo "uso: $0 nombre-de-host" >&2; exit 1; }
: "${LAZARO_LIVE_DIR:?falta LAZARO_LIVE_DIR}"
: "${LAZARO_SCRIPT:?falta LAZARO_SCRIPT}"
: "${LAZARO_VERSION_ENV:?falta LAZARO_VERSION_ENV}"
: "${LAZARO_WORLD:?falta LAZARO_WORLD}"
: "${LAZARO_PUBKEY:?falta LAZARO_PUBKEY}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

rc_add() {
	mkdir -p "$tmp"/etc/runlevels/"$2"
	ln -sf /etc/init.d/"$1" "$tmp"/etc/runlevels/"$2"/"$1"
}

# Archivos fijos de la sesión live (Calamares, servicios, accesos).
cp -a "$LAZARO_LIVE_DIR"/. "$tmp"/
chown -R root:root "$tmp"
chmod 0755 "$tmp"/usr/sbin/* "$tmp"/etc/init.d/*

# El script del usuario se copia a la ISO desde la raíz del repositorio:
# así hay una sola copia que mantener.
install -Dm755 "$LAZARO_SCRIPT" "$tmp"/usr/share/lazaro/desktop-postinstall.sh
install -Dm644 "$LAZARO_VERSION_ENV" "$tmp"/usr/share/lazaro/version.env

# El índice del repositorio de la ISO lo firma nuestra llave, no la de
# Alpine: sin ella, setup-disk no podría instalar desde la ISO.
install -Dm644 "$LAZARO_PUBKEY" "$tmp/etc/apk/keys/$(basename "$LAZARO_PUBKEY")"

echo "$HOSTNAME" > "$tmp"/etc/hostname
mkdir -p "$tmp"/etc/apk
printf '%s\n' $LAZARO_WORLD > "$tmp"/etc/apk/world

# Igual que "setup-devd udev" (alpine-conf): eudev en lugar de mdev,
# necesario para Xorg y para que Calamares vea los discos.
rc_add devfs sysinit
rc_add dmesg sysinit
rc_add udev sysinit
rc_add udev-trigger sysinit
rc_add udev-settle sysinit
rc_add modloop sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot

rc_add udev-postmount default
rc_add dbus default
rc_add elogind default
rc_add networkmanager default
rc_add lazaro-live default
rc_add lightdm default

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

tar -c -C "$tmp" etc usr | gzip -9n > "$HOSTNAME".apkovl.tar.gz
