# shellcheck shell=sh
# Perfil de mkimage.sh (aports/scripts) para la ISO de Lázaro Linux.
# build.sh lo copia a ~/.mkimage/ junto con genapkovl-lazaro.sh.
#
# Dos listas de paquetes:
#  - LAZARO_LIVE: lo que se instala en RAM al arrancar la sesión live
#    (escritorio XFCE, red, Calamares). Va en /etc/apk/world del apkovl.
#  - apks: todo lo que se copia al repositorio de la ISO. Incluye lo
#    anterior y además lo que necesita el sistema instalado sin internet
#    (sistema base, XFCE completo, firmware común en portátiles viejos).

# Escritorio de la sesión live = lo que instala "setup-desktop xfce" en
# alpine-conf (verificado en la etiqueta 3.22.0, la de Alpine 3.24).
LAZARO_XFCE="xorg-server xf86-input-libinput xinit eudev mesa-dri-gallium
	xfce4 elogind gvfs lightdm lightdm-gtk-greeter polkit-elogind
	xfce4-screensaver xfce4-terminal font-dejavu dbus dbus-x11 firefox"

LAZARO_LIVE="alpine-base $LAZARO_XFCE
	networkmanager networkmanager-wifi networkmanager-cli network-manager-applet
	wpa_supplicant calamares doas musl-locales tzdata kbd-bkeymaps
	adwaita-icon-theme setxkbmap udev-init-scripts udev-init-scripts-openrc"

# Lo que necesitan setup-disk y el sistema instalado, para instalar sin
# internet: el world del destino (live/usr/share/lazaro/paquetes-base,
# el mismo archivo que usa lazaro-instalar) más kernel, GRUB y firmware
# de portátiles comunes (setup-disk elige el firmware según el hardware;
# lo que no esté aquí se descarga si hay internet).
LAZARO_DESTINO="$(grep -v '^#' "${LAZARO_DIR:?}/live/usr/share/lazaro/paquetes-base")
	linux-lts mkinitfs grub grub-bios grub-efi efibootmgr sfdisk parted
	udev-init-scripts udev-init-scripts-openrc
	linux-firmware-none linux-firmware-other linux-firmware-intel
	linux-firmware-i915 linux-firmware-radeon linux-firmware-amdgpu
	linux-firmware-nvidia linux-firmware-ath9k_htc linux-firmware-ath10k
	linux-firmware-brcm linux-firmware-rtlwifi linux-firmware-rtw88
	linux-firmware-rtl_nic linux-firmware-rtl_bt linux-firmware-mediatek
	intel-ucode amd-ucode"

profile_lazaro() {
	profile_standard
	title="Lázaro Linux"
	desc="Tu hardware aún tiene pulso.
		Sesión live con XFCE e instalador Calamares."
	profile_abbrev="lazaro"
	image_name="lazaro-linux"
	arch="x86_64"
	kernel_addons=
	# console=ttyS0 primero y tty0 al final: la consola principal sigue
	# siendo la pantalla; el puerto serie solo sirve a las pruebas (QEMU).
	kernel_cmdline="console=ttyS0,115200 console=tty0"
	syslinux_serial="0 115200"
	boot_addons="amd-ucode intel-ucode"
	initrd_ucode="/boot/amd-ucode.img /boot/intel-ucode.img"
	apks="$apks $LAZARO_LIVE $LAZARO_DESTINO"
	grub_mod="$grub_mod serial terminal"
	apkovl="genapkovl-lazaro.sh"
	# genapkovl-lazaro.sh corre como proceso aparte: recibe la lista así.
	export LAZARO_WORLD="$LAZARO_LIVE"
	hostname="lazaro"
}

# Nombre del volumen y textos del menú de arranque. Van sin tildes
# porque GRUB y syslinux de la ISO no cargan una fuente con acentos.
gen_volid() {
	printf "%s" "LAZARO ${RELEASE%_rc*}" | cut -c1-32
}

syslinux_gen_config() {
	[ -z "$syslinux_serial" ] || echo "SERIAL $syslinux_serial"
	echo "SAY Lazaro Linux - Tu hardware aun tiene pulso"
	echo "TIMEOUT ${syslinux_timeout:-30}"
	echo "PROMPT 1"
	echo "DEFAULT lazaro"
	cat <<- EOF

	LABEL lazaro
		MENU LABEL Lazaro Linux (sesion live)
		KERNEL /boot/vmlinuz-lts
		INITRD /boot/amd-ucode.img,/boot/intel-ucode.img,/boot/initramfs-lts
		APPEND $initfs_cmdline $kernel_cmdline

	LABEL seguro
		MENU LABEL Lazaro Linux (modo grafico seguro)
		KERNEL /boot/vmlinuz-lts
		INITRD /boot/amd-ucode.img,/boot/intel-ucode.img,/boot/initramfs-lts
		APPEND $initfs_cmdline $kernel_cmdline nomodeset
	EOF
}

grub_gen_config() {
	cat <<- EOF
	set timeout=5
	serial --unit=0 --speed=115200
	terminal_input console serial
	terminal_output console serial

	menuentry "Lazaro Linux - Tu hardware aun tiene pulso" {
		linux	/boot/vmlinuz-lts $initfs_cmdline $kernel_cmdline
		initrd	/boot/amd-ucode.img /boot/intel-ucode.img /boot/initramfs-lts
	}

	menuentry "Lazaro Linux (modo grafico seguro)" {
		linux	/boot/vmlinuz-lts $initfs_cmdline $kernel_cmdline nomodeset
		initrd	/boot/amd-ucode.img /boot/intel-ucode.img /boot/initramfs-lts
	}
	EOF
}
