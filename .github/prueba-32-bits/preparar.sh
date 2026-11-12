#!/bin/sh
# Prepara el disco de la máquina virtual de 32 bits (Alpine x86). Lo
# ejecuta alpine-make-vm-image dentro del sistema recién creado (chroot),
# con esta carpeta montada en /mnt. $1 = escritorio (lxqt, xfce...).
#
# Deja un Alpine "recién instalado" como el que obtendría una persona con
# setup-alpine: usuario normal, red por DHCP y nada de escritorio. El
# script se ejecuta en el primer arranque (ver fase.sh), en un sistema
# encendido de verdad y no dentro de un chroot.
set -eu

escritorio="$1"

echo prueba-x86 > /etc/hostname
printf '127.0.0.1\tprueba-x86 localhost\n' > /etc/hosts

# Usuario normal, como el que crea setup-alpine. Contraseña "prueba"
# (solo existe dentro de la máquina virtual de la prueba).
adduser -D -s /bin/ash prueba
echo 'prueba:prueba' | chpasswd
echo 'root:prueba' | chpasswd

rc-update add networking default
rc-update add local default

install -Dm755 /mnt/desktop-postinstall.sh /root/desktop-postinstall.sh
install -Dm755 /mnt/fase.sh /usr/local/sbin/prueba-fase
install -Dm755 /mnt/lazaro-autologin /usr/local/sbin/lazaro-autologin
echo "$escritorio" > /etc/prueba-escritorio

# El servicio "local" corre esto en cada arranque. Se lanza aparte para
# que el arranque termine y el script trabaje en un sistema ya en marcha.
cat > /etc/local.d/prueba.start <<'FIN'
#!/bin/sh
setsid /usr/local/sbin/prueba-fase </dev/null >/dev/null 2>&1 &
FIN
chmod 755 /etc/local.d/prueba.start

# Mensajes del kernel también por el puerto serie (el registro que lee
# GitHub); la pantalla sigue siendo la consola principal.
sed -i 's|^default_kernel_opts=.*|default_kernel_opts="console=ttyS0,115200 console=tty0"|' \
    /etc/update-extlinux.conf
update-extlinux --warn-only 2>&1 | grep -v 'cannot open device' || true

echo "Disco preparado: $(cat /etc/alpine-release), $(apk --print-arch), escritorio $escritorio."
