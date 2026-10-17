# shellcheck shell=sh
# Valores derivados de config.env. Lo cargan build.sh y las pruebas.
# Requiere que LAZARO_DIR apunte a la carpeta lazaro-linux.

. "$LAZARO_DIR/config.env"

case "$ALPINE_BRANCH" in
	edge)
		ALPINE_DOCKER_TAG="edge"
		APORTS_BRANCH="master"
		;;
	v[0-9]*.[0-9]*)
		ALPINE_DOCKER_TAG="${ALPINE_BRANCH#v}"
		APORTS_BRANCH="${ALPINE_BRANCH#v}-stable"
		;;
	*)
		echo "ALPINE_BRANCH no válido: '$ALPINE_BRANCH' (usa vX.Y o edge)" >&2
		exit 1
		;;
esac

ALPINE_REPO_MAIN="$ALPINE_MIRROR/$ALPINE_BRANCH/main"
ALPINE_REPO_COMMUNITY="$ALPINE_MIRROR/$ALPINE_BRANCH/community"
ISO_FILE="$ISO_NAME-$ISO_VERSION-$ALPINE_DOCKER_TAG-$ALPINE_ARCH.iso"

export ALPINE_BRANCH ALPINE_ARCH ALPINE_MIRROR CALAMARES_VERSION ISO_NAME \
	ISO_VERSION ALPINE_DOCKER_TAG APORTS_BRANCH ALPINE_REPO_MAIN \
	ALPINE_REPO_COMMUNITY ISO_FILE
