#!/bin/sh
# Compila la ISO de Lázaro Linux.
#
#   ./build.sh            En cualquier Linux con Docker: abre un contenedor
#                         Alpine de la versión de config.env y compila dentro.
#   ./build.sh --dentro   Lo que corre dentro del contenedor (o en un Alpine
#                         de verdad, como root).
#
# Resultado: salida/lazaro-linux-<versión>-<alpine>-x86_64.iso
# Caché (Calamares ya compilado y su llave de firma): cache/
#
# Para otra versión de Alpine: ALPINE_BRANCH=edge ./build.sh

set -eu

LAZARO_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$LAZARO_DIR")"
. "$LAZARO_DIR/lib.sh"

SALIDA="${SALIDA:-$LAZARO_DIR/salida}"
CACHE="${CACHE:-$LAZARO_DIR/cache}"

msg() { printf '\n==> %s\n' "$*"; }

if [ "${1:-}" != "--dentro" ]; then
	mkdir -p "$SALIDA" "$CACHE"
	msg "Compilando en alpine:$ALPINE_DOCKER_TAG (Alpine $ALPINE_BRANCH)"
	exec docker run --rm \
		-e ALPINE_BRANCH -e ALPINE_ARCH -e ALPINE_MIRROR \
		-e CALAMARES_VERSION -e ISO_VERSION \
		-e SALIDA=/salida -e CACHE=/cache \
		-v "$REPO_DIR:/src:ro" \
		-v "$SALIDA:/salida" \
		-v "$CACHE:/cache" \
		"alpine:$ALPINE_DOCKER_TAG" \
		/bin/sh /src/lazaro-linux/build.sh --dentro
fi

[ "$(id -u)" -eq 0 ] || { echo "build.sh --dentro debe ejecutarse como root" >&2; exit 1; }

msg "Preparando el entorno de compilación"
printf '%s\n%s\n' "$ALPINE_REPO_MAIN" "$ALPINE_REPO_COMMUNITY" > /etc/apk/repositories
apk update
apk add alpine-sdk alpine-conf apk-tools busybox fakeroot syslinux xorriso \
	squashfs-tools mtools grub grub-efi dosfstools git

# abuild no compila como root: se usa un usuario del grupo abuild.
id constructor >/dev/null 2>&1 || adduser -D -G abuild constructor
CONSTRUCTOR_HOME=/home/constructor
mkdir -p "$CACHE/llaves" "$CACHE/paquetes/$ALPINE_BRANCH"
chown -R constructor:abuild "$CACHE"

# Llave de firma del repositorio propio (Calamares). Se guarda en la caché
# para que los paquetes ya compilados sigan siendo válidos.
if ! ls "$CACHE"/llaves/*.rsa >/dev/null 2>&1; then
	msg "Creando la llave de firma"
	su constructor -c "abuild-keygen -n"
	cp "$CONSTRUCTOR_HOME"/.abuild/*.rsa "$CONSTRUCTOR_HOME"/.abuild/*.rsa.pub "$CACHE/llaves/"
fi
LLAVE="$(ls "$CACHE"/llaves/*.rsa | head -n1)"
mkdir -p "$CONSTRUCTOR_HOME/.abuild"
cp "$CACHE"/llaves/* "$CONSTRUCTOR_HOME/.abuild/"
echo "PACKAGER_PRIVKEY=\"$CONSTRUCTOR_HOME/.abuild/$(basename "$LLAVE")\"" > "$CONSTRUCTOR_HOME/.abuild/abuild.conf"
cp "$CACHE"/llaves/*.rsa.pub /etc/apk/keys/
chown -R constructor:abuild "$CONSTRUCTOR_HOME"

# --- Calamares ----------------------------------------------------------
REPO_PROPIO="$CACHE/paquetes/$ALPINE_BRANCH"
TRABAJO="$CONSTRUCTOR_HOME/trabajo"
rm -rf "$TRABAJO"
mkdir -p "$TRABAJO"
cp -r "$LAZARO_DIR/paquetes" "$TRABAJO/"
chown -R constructor:abuild "$TRABAJO"

if ls "$REPO_PROPIO/paquetes/$ALPINE_ARCH/calamares-$CALAMARES_VERSION-"*.apk >/dev/null 2>&1; then
	msg "Calamares $CALAMARES_VERSION ya está compilado (caché)"
else
	msg "Compilando Calamares $CALAMARES_VERSION (tarda varios minutos)"
	cd "$TRABAJO/paquetes/calamares"
	if ! grep -q '^sha512sums=".\+' APKBUILD; then
		# Primera compilación de una versión nueva: se calcula la suma y se
		# muestra para fijarla en el APKBUILD del repositorio.
		su constructor -c "CALAMARES_VERSION=$CALAMARES_VERSION abuild checksum"
		echo "AVISO: fija esta suma en paquetes/calamares/APKBUILD:"
		grep -A2 '^sha512sums' APKBUILD
	fi
	su constructor -c "CALAMARES_VERSION=$CALAMARES_VERSION REPODEST=$REPO_PROPIO abuild -r"
fi

# --- aports/scripts (mkimage.sh) ---------------------------------------
msg "Descargando aports/scripts de la rama $APORTS_BRANCH"
APORTS="$CONSTRUCTOR_HOME/aports"
rm -rf "$APORTS"
su constructor -c "git clone --quiet --depth 1 --filter=blob:none --sparse \
	-b $APORTS_BRANCH https://github.com/alpinelinux/aports.git $APORTS \
	&& git -C $APORTS sparse-checkout set scripts"

mkdir -p "$CONSTRUCTOR_HOME/.mkimage"
cp "$LAZARO_DIR"/perfil/mkimg.lazaro.sh "$LAZARO_DIR"/perfil/genapkovl-lazaro.sh \
	"$CONSTRUCTOR_HOME/.mkimage/"
cat > "$CONSTRUCTOR_HOME/version.env" <<EOF
ALPINE_BRANCH="$ALPINE_BRANCH"
ALPINE_MIRROR="$ALPINE_MIRROR"
ISO_VERSION="$ISO_VERSION"
CALAMARES_VERSION="$CALAMARES_VERSION"
LAZARO_LLAVE="$(basename "$LLAVE").pub"
EOF
chown -R constructor:abuild "$CONSTRUCTOR_HOME"

# --- ISO ----------------------------------------------------------------
msg "Generando la ISO"
mkdir -p "$SALIDA"
chown constructor:abuild "$SALIDA"
su constructor -c "cd $CONSTRUCTOR_HOME && \
	LAZARO_DIR='$LAZARO_DIR' \
	LAZARO_LIVE_DIR='$LAZARO_DIR/live' \
	LAZARO_SCRIPT='$REPO_DIR/desktop-postinstall.sh' \
	LAZARO_VERSION_ENV='$CONSTRUCTOR_HOME/version.env' \
	LAZARO_PUBKEY='$LLAVE.pub' \
	sh $APORTS/scripts/mkimage.sh \
		--tag '$ISO_VERSION' \
		--outdir '$SALIDA' \
		--workdir '$CONSTRUCTOR_HOME/mkimage-trabajo' \
		--arch '$ALPINE_ARCH' \
		--repository '$ALPINE_REPO_MAIN' \
		--repository '$ALPINE_REPO_COMMUNITY' \
		--repository '$REPO_PROPIO/paquetes' \
		--profile lazaro"

ISO_GENERADA="$SALIDA/lazaro-linux-$ISO_VERSION-$ALPINE_ARCH.iso"
[ -f "$ISO_GENERADA" ] || { echo "No se generó la ISO" >&2; exit 1; }
mv "$ISO_GENERADA" "$SALIDA/$ISO_FILE"
(cd "$SALIDA" && sha256sum "$ISO_FILE" > "$ISO_FILE.sha256")
msg "Listo: $SALIDA/$ISO_FILE ($(du -h "$SALIDA/$ISO_FILE" | cut -f1))"
