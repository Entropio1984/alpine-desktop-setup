#!/bin/sh
# Pruebas automáticas de la ISO en QEMU (las usa GitHub Actions, pero
# también sirven en cualquier Linux con qemu-system-x86_64, xorriso y
# socat; con OVMF para UEFI).
#
#   pruebas/qemu.sh live ISO bios|uefi
#       Arranca la ISO como lo haría un usuario y espera a que Calamares
#       se abra en el escritorio. Guarda capturas de pantalla.
#
#   pruebas/qemu.sh instalar ISO bios|uefi ESCRITORIO con-red|sin-red
#       Instala sin interfaz (lazaro-instalar auto) en un disco virtual,
#       y luego arranca el disco y comprueba que el sistema instalado
#       inicia con su gestor de sesión.
#
# Resultados (registro del puerto serie y capturas) en pruebas/resultados/.
# Nunca toca discos reales: todo ocurre en archivos dentro de esa carpeta.

set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
RES="${RESULTADOS:-$DIR/resultados}"
mkdir -p "$RES"
# Los sockets UNIX no admiten rutas de más de 108 bytes, así que el del
# monitor de QEMU va en una carpeta temporal corta.
SOCK_DIR="$(mktemp -d /tmp/lzq.XXXXXX)"
trap 'rm -rf "$SOCK_DIR"' EXIT

uso() { sed -n '2,/^$/s/^# \{0,1\}//p' "$0" >&2; exit 2; }

[ $# -ge 3 ] || uso
orden="$1"
ISO="$(realpath "$2")"
MODO="$3"

KVM=""
[ -w /dev/kvm ] && KVM="-enable-kvm -cpu host"
MEM="${MEM:-4096}"

ovmf() {
	for d in /usr/share/OVMF /usr/share/edk2/ovmf /usr/share/qemu; do
		for c in OVMF_CODE_4M.fd OVMF_CODE.fd; do
			if [ -f "$d/$c" ]; then
				OVMF_CODE="$d/$c"
				OVMF_VARS_ORIG="$d/$(echo "$c" | sed 's/CODE/VARS/')"
				return 0
			fi
		done
	done
	echo "No se encontró OVMF (firmware UEFI para QEMU)" >&2
	exit 1
}

firmware_args() { # nombre-de-la-prueba
	if [ "$MODO" = uefi ]; then
		ovmf
		[ -f "$RES/$1-vars.fd" ] || cp "$OVMF_VARS_ORIG" "$RES/$1-vars.fd"
		echo "-drive if=pflash,format=raw,readonly=on,file=$OVMF_CODE -drive if=pflash,format=raw,file=$RES/$1-vars.fd"
	fi
}

captura() { # socket archivo
	printf 'screendump %s\n' "$2.ppm" | socat - "UNIX-CONNECT:$1" >/dev/null 2>&1 || true
	sleep 2
	if [ -f "$2.ppm" ] && command -v convert >/dev/null 2>&1; then
		convert "$2.ppm" "$2.png" && rm -f "$2.ppm"
	fi
}

# esperar ARCHIVO_SERIE PID SEGUNDOS TEXTO_OK [TEXTO_FALLO]
esperar() {
	t=0
	while [ "$t" -lt "$3" ]; do
		if grep -q "$4" "$1" 2>/dev/null; then return 0; fi
		if [ -n "${5:-}" ] && grep -q "$5" "$1" 2>/dev/null; then return 1; fi
	if grep -q 'initramfs emergency recovery shell' "$1" 2>/dev/null; then
		echo "El initramfs no encontró el sistema y abrió la consola de emergencia" >&2
		return 1
	fi
		kill -0 "$2" 2>/dev/null || { grep -q "$4" "$1" 2>/dev/null; return $?; }
		sleep 5
		t=$((t + 5))
	done
	echo "Tiempo agotado ($3 s) esperando '$4'" >&2
	return 1
}

terminar() { kill "$1" 2>/dev/null || true; sleep 2; kill -9 "$1" 2>/dev/null || true; }

prueba_live() {
	nombre="live-$MODO"
	serie="$RES/$nombre-serie.log"
	mon="$SOCK_DIR/$nombre.mon"
	rm -f "$serie" "$mon"
	# shellcheck disable=SC2046
	qemu-system-x86_64 $KVM -m "$MEM" -smp 2 $(firmware_args "$nombre") \
		-cdrom "$ISO" -boot d -vga std -display none \
		-nic user,model=virtio-net-pci \
		-serial "file:$serie" -monitor "unix:$mon,server,nowait" &
	pid=$!
	ok=0
	if esperar "$serie" "$pid" 900 LAZARO-CALAMARES-ABIERTO LAZARO-CALAMARES-NO-ABRIO; then
		sleep 20
		captura "$mon" "$RES/$nombre-calamares"
		echo "OK: la sesión live arrancó ($MODO) y Calamares se abrió."
	else
		captura "$mon" "$RES/$nombre-fallo"
		echo "FALLO: Calamares no se abrió en la sesión live ($MODO)." >&2
		ok=1
	fi
	terminar "$pid"
	tail -n 40 "$serie" || true
	return $ok
}

prueba_instalar() {
	de="$1"
	red="$2"
	nombre="instalar-$MODO-$de-$red"
	disco="$RES/$nombre.qcow2"
	serie="$RES/$nombre-instalacion.log"
	mon="$SOCK_DIR/$nombre.mon"
	rm -f "$disco" "$serie" "$mon" "$RES/$nombre-vars.fd"
	qemu-img create -q -f qcow2 "$disco" 20G

	nic="-nic user,model=virtio-net-pci"
	[ "$red" = sin-red ] && nic="-nic none"

	# Kernel e initramfs de la propia ISO, para poder pasar parámetros de
	# instalación desatendida sin tocar el menú de arranque.
	k="$RES/vmlinuz-lts"
	i="$RES/initramfs-lts"
	xorriso -osirrox on -indev "$ISO" \
		-extract /boot/vmlinuz-lts "$k" \
		-extract /boot/initramfs-lts "$i" >/dev/null 2>&1
	chmod u+w "$k" "$i"

	# Con OVMF y arranque directo del kernel, el CD por IDE no se detecta a
	# tiempo y el initramfs no encuentra la ISO; por virtio-scsi sí.
	cd_args="-cdrom $ISO"
	mods="loop,squashfs,sd-mod,usb-storage"
	if [ "$MODO" = uefi ]; then
		cd_args="-device virtio-scsi-pci,id=scsi0 -drive id=cd0,if=none,media=cdrom,readonly=on,file=$ISO -device scsi-cd,drive=cd0,bus=scsi0.0"
		mods="$mods,virtio_scsi,sr-mod"
	fi

	echo "Instalando ($MODO, $de, $red)..."
	# shellcheck disable=SC2046
	qemu-system-x86_64 $KVM -m "$MEM" -smp 2 $(firmware_args "$nombre") \
		-kernel "$k" -initrd "$i" \
		-append "modules=$mods console=tty0 console=ttyS0,115200 lazaro.autoinstall=$de lazaro.disco=/dev/vda" \
		$cd_args -drive "file=$disco,if=virtio,format=qcow2" \
		-vga std -display none $nic \
		-serial "file:$serie" -monitor "unix:$mon,server,nowait" &
	pid=$!
	if ! esperar "$serie" "$pid" 3600 LAZARO-AUTOINSTALL-OK LAZARO-AUTOINSTALL-FALLO; then
		captura "$mon" "$RES/$nombre-instalacion-fallo"
		terminar "$pid"
		echo "FALLO: la instalación desatendida no terminó bien." >&2
		tail -n 120 "$serie" >&2 || true
		return 1
	fi
	# La instalación apaga la máquina sola.
	t=0
	while kill -0 "$pid" 2>/dev/null && [ $t -lt 120 ]; do sleep 2; t=$((t + 2)); done
	terminar "$pid"

	echo "Arrancando el sistema instalado..."
	serie2="$RES/$nombre-arranque.log"
	rm -f "$serie2" "$mon"
	# shellcheck disable=SC2046
	qemu-system-x86_64 $KVM -m 2048 -smp 2 $(firmware_args "$nombre") \
		-drive "file=$disco,if=virtio,format=qcow2" -boot c \
		-vga std -display none $nic \
		-serial "file:$serie2" -monitor "unix:$mon,server,nowait" &
	pid=$!
	ok=0
	if esperar "$serie2" "$pid" 600 LAZARO-PRUEBA-FIN; then
		captura "$mon" "$RES/$nombre-instalado"
		if grep -Eq '(lightdm|sddm|gdm|greetd).*started|status: started' "$serie2"; then
			echo "OK: el sistema instalado arrancó y su gestor de sesión está activo."
		else
			echo "FALLO: el sistema arrancó, pero el gestor de sesión no está activo." >&2
			ok=1
		fi
	else
		captura "$mon" "$RES/$nombre-arranque-fallo"
		echo "FALLO: el sistema instalado no terminó de arrancar." >&2
		ok=1
	fi
	terminar "$pid"
	tail -n 60 "$serie2" || true
	rm -f "$disco" "$k" "$i"
	return $ok
}

case "$orden" in
	live) prueba_live ;;
	instalar) [ $# -eq 5 ] || uso; prueba_instalar "$4" "$5" ;;
	*) uso ;;
esac
