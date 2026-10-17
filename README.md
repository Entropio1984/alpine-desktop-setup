# desktop-postinstall.sh — configuración de escritorio para Alpine Linux

Script de shell POSIX (`ash` de BusyBox, el shell de Alpine) que termina de configurar un escritorio recién instalado en Alpine Linux: red, audio, teclado, idioma, controladores de video, energía, impresión, aplicaciones de uso diario y estabilidad del sistema.

Está pensado para revivir equipos antiguos o con poca memoria (2 a 8 GB de RAM), pero sirve igual en equipos modernos. No asume nada: detecta el escritorio, la tarjeta gráfica y el procesador, e instala solo lo que corresponde.

> ⚠️ **Tarjetas NVIDIA.** Versiones anteriores del modo seguro podían dejar la pantalla en negro en algunos equipos. La causa probable ya se corrigió (ver [Bloque 12](#bloque-12--install_drivers)), pero falta confirmarlo en un equipo que arranque con Xorg. En portátiles Optimus hay un modo nuevo, probado en un equipo real, que apaga la NVIDIA y deja todo en la gráfica integrada.

> 💿 **Lázaro Linux.** Este script también va dentro de la ISO instalable de [Lázaro Linux](lazaro-linux/README.md) (*Tu hardware aún tiene pulso*), que lo ejecuta al final de la instalación sin hacer preguntas.

---

## Contenido

1. [Requisitos](#requisitos)
2. [Cómo ejecutarlo](#cómo-ejecutarlo)
3. [Menú de opciones](#menú-de-opciones)
4. [El botón "Actualizar el sistema"](#el-botón-actualizar-el-sistema)
5. [Qué hace cada bloque](#qué-hace-cada-bloque)
6. [Archivos que crea o modifica](#archivos-que-crea-o-modifica)
7. [Servicios que habilita](#servicios-que-habilita)
8. [Registro (log) y reejecución](#registro-log-y-reejecución)
9. [Compatibilidad con futuras versiones de Alpine](#compatibilidad-con-futuras-versiones-de-alpine)
10. [Limitaciones conocidas](#limitaciones-conocidas)
11. [Solución de problemas](#solución-de-problemas)
12. [Cómo revertir cambios](#cómo-revertir-cambios)
13. [Historial de correcciones](#historial-de-correcciones)

---

## Requisitos

- Alpine Linux instalado con `setup-alpine`.
- Un escritorio instalado con `setup-desktop`: XFCE, KDE Plasma, GNOME, MATE o LXQt. El script **no instala el escritorio**; lo complementa.
- Repositorios `main` y `community` habilitados en `/etc/apk/repositories`. Casi todo lo que instala el script está en `community`.
- Conexión a internet.
- Acceso de administrador (`doas` o una sesión de `root`).

Para revisar los repositorios:

```sh
grep -v '^#' /etc/apk/repositories
```

## Cómo ejecutarlo

```sh
doas sh desktop-postinstall.sh
```

Si ya estás como `root`, basta con `sh desktop-postinstall.sh`.

Al empezar aparece un menú con todas las opciones. Después de confirmarlo, el script trabaja solo hasta el final. Al terminar, **reinicia el equipo**: varios cambios (servicios nuevos, módulos del kernel, idioma) solo se aplican en el siguiente arranque.

## Menú de opciones

Se navega con las flechas, se marca o desmarca con la **barra espaciadora** y se continúa con **Enter**. Después aparece un resumen con dos botones: **Comenzar** o **Volver** (vuelve al menú sin perder lo marcado). **Salir** termina el script sin cambiar la configuración del sistema.

| Opción | Marcada por defecto | Qué hace |
|---|---|---|
| Teclado latinoamericano | Sí | Distribución `latam` en la consola, en Xorg y en sesiones Wayland |
| NVIDIA en modo seguro | Sí | Solo aparece si hay una NVIDIA y el equipo **no** es un portátil Optimus. Bloquea el driver `nouveau` |
| gcompat | No | Permite ejecutar programas propietarios compilados para otras distribuciones (glibc) |
| Impresoras (CUPS) | Sí | Instala el sistema de impresión |
| LibreOffice | Sí | Suite de oficina en español (paquete pesado) |
| Firefox | Sí | Navegador, registrado como predeterminado |
| Flatpak/Flathub | No | Tienda de aplicaciones Flatpak |
| OnlyOffice | No | Por Flatpak; marcarla activa Flatpak |
| Google Chrome | No | Por Flatpak (paquete comunitario, no oficial de Google); marcarla activa Flatpak |
| Botón "Actualizar el sistema" | Sí | Acceso directo en el menú de aplicaciones |

**Portátiles Optimus** (gráfica integrada más una NVIDIA): en lugar de la casilla de NVIDIA aparece una segunda pantalla con tres modos: *ahorro* (recomendado y marcado por defecto), *seguro* o *activa*. Ver [Bloque 12](#bloque-12--install_drivers).

**Por qué esos valores por defecto:** en el hardware viejo al que apunta el proyecto, dejar `nouveau` activo puede terminar en pantalla negra, así que el modo seguro viene marcado. Flatpak viene desmarcado porque instalarlo sin ninguna aplicación no sirve de nada; por eso se activa solo al marcar OnlyOffice o Chrome.

**Si el menú no se puede mostrar** (por ejemplo, sin una terminal interactiva), el script hace cada pregunta por separado cuando la necesita. Solo las respuestas que empiezan por `s` o `y` cuentan como "sí"; Enter vacío es "no".

Los textos del menú van sin tildes a propósito: aparece antes de configurar el idioma, y en una consola recién instalada las tildes pueden verse como símbolos extraños.

## El botón "Actualizar el sistema"

Si se marca en el menú, aparece **"Actualizar el sistema"** en el menú de aplicaciones de cualquier escritorio. Al pulsarlo:

1. **Si hay una versión estable nueva de Alpine**, pregunta primero: *"Cambiar a Alpine 3.NN"* o *"Solo actualizar"*. Sin internet, o si se cierra la ventana, hace solo la actualización normal.
2. Pide **la contraseña del propio usuario** (no la de root). El usuario debe estar en el grupo `wheel`; el script lo agrega si hace falta.
3. Muestra una ventana con el paso en curso. Al terminar, la ventana queda abierta con el resultado hasta que se cierra.
4. Si se instaló un kernel nuevo, o si se cambió de versión de Alpine, avisa que hay que reiniciar.

**Actualización normal:** `apk update`, `apk upgrade` y, si está instalado, `flatpak update`. No cambia de versión de Alpine.

**Cambio de versión** (procedimiento oficial de Alpine):

1. Primero hace la actualización normal. Si falla, no sigue.
2. Guarda una copia de `/etc/apk/repositories` en `/var/backups/alpine-update/`.
3. Cambia la versión en ese archivo, por ejemplo de `v3.24` a `v3.25`.
4. Lee el repositorio nuevo. Si no lo consigue, **restaura la copia**: el sistema queda como estaba.
5. Actualiza `apk-tools` y ejecuta `apk upgrade --available`.

Detalles importantes:

- **Avanza una versión a la vez** (3.24 → 3.25), aunque haya otra más nueva. Si falta otra, el botón la ofrece la próxima vez que se use.
- La versión de destino la calcula el propio proceso con permisos de administrador; no acepta un número que llegue de fuera.
- Si `apk upgrade --available` falla a mitad de camino, **no se revierte nada**: el sistema queda a medio actualizar y el mensaje pide no reiniciar, conectarse a internet y volver a pulsar el botón (o ejecutar `doas apk upgrade --available`).
- Si el equipo arranca con **GRUB**, avisa que puede hacer falta ejecutar `grub-install` (Alpine lo pidió en 3.24). Con `extlinux`, el cargador habitual de Alpine en equipos con BIOS, no hace falta nada.
- Solo funciona si `/etc/apk/repositories` usa una versión fija (`v3.NN`). Con `edge` o `latest-stable` no ofrece el cambio.
- Antes de aceptar conviene leer las [notas de la versión](https://alpinelinux.org/releases/): a veces piden un paso manual.

**Por qué importa:** el repositorio `community` (escritorio, Firefox, LibreOffice...) solo recibe actualizaciones durante unos seis meses, hasta que sale la siguiente versión. Ver [Compatibilidad](#compatibilidad-con-futuras-versiones-de-alpine).

Cada ejecución queda registrada en `/var/log/alpine-update.log`.

## Qué hace cada bloque

El script tiene 31 bloques. `main()` los ejecuta casi en orden, con una excepción: la detección de gráficas (Bloque 11) y el menú (Bloque 29) van al principio, para tomar todas las decisiones antes de instalar nada.

Principios que siguen todos los bloques:

- **Detectar antes de asumir:** el escritorio se averigua con `apk info -e`, las gráficas leyendo `/sys`, el procesador con `/proc/cpuinfo`.
- **No abortar por un paquete que falta:** si un paquete no existe en la versión instalada, se anota un aviso y el script sigue.
- **Decir la verdad sobre los límites:** si algo no tiene solución en Alpine (por ejemplo, los controladores propietarios de NVIDIA), el log lo dice en vez de fingir que lo resolvió.

### Bloque 1 — `check_root`
Comprueba que el script corre como administrador; si no, se detiene con un mensaje claro.

### Bloque 2 — `update_system`, `install_pkg`, `install_pkgs`
`update_system` ejecuta `apk update` una vez al principio. `install_pkgs` instala varios paquetes en una sola operación de `apk`, que es mucho más rápido. Si esa operación falla (por ejemplo, porque un nombre no existe en esta versión), reintenta paquete por paquete con `install_pkg`, que tolera fallos individuales.

`ensure_hw_tools` instala `pciutils` y `usbutils`. El BusyBox de Alpine trae un `lsusb` reducido que solo muestra códigos numéricos, sin los nombres que necesitan los bloques de detección.

### Bloque 3 — `setup_keyboard_layout`
Solo si se marcó en el menú. Configura la distribución latinoamericana (`latam`) en cuatro lugares, porque cada uno la lee por su cuenta:

- **Consola de texto:** `setup-keymap latam latam`.
- **Xorg** (XFCE, MATE, LXQt y la pantalla de inicio de SDDM, que en Alpine usa Xorg): `/etc/X11/xorg.conf.d/00-keyboard.conf`.
- **Wayland** (Plasma desde Alpine 3.22, GNOME desde 3.24, sway, labwc): Wayland no lee `/etc/X11/`. Se agregan:
  - la variable `XKB_DEFAULT_LAYOUT=latam`, que KWin usa cuando el usuario no ha elegido distribución (comprobado en el código de KWin), igual que los compositores basados en wlroots;
  - `/etc/xdg/kxkbrc`, el valor por defecto de Plasma, que se ve en Preferencias del sistema;
  - un esquema de `gsettings` para GNOME, que también aplica a su pantalla de inicio.

Lo que el usuario elija después en la configuración del escritorio tiene prioridad sobre estos valores.

### Bloque 4 — `detect_desktop_environment`
Pregunta a `apk` qué escritorios están instalados y guarda el resultado en `DE_XFCE`, `DE_PLASMA`, `DE_GNOME`, `DE_MATE` y `DE_LXQT`. Si hay más de uno, configura todos.

### Bloque 5 — `detect_target_user`
Identifica al usuario real (no root) a partir de `$DOAS_USER` o `logname`, para aplicarle el idioma y los grupos más adelante. Si no lo encuentra, los bloques que lo necesitan avisan y siguen.

### Bloque 6 — `setup_applets`
Instala NetworkManager y un servidor de audio:

- Si el sistema ya tiene **PipeWire** (`pipewire-pulse`) o **PulseAudio**, lo respeta.
- Si no tiene ninguno: PipeWire en Plasma y GNOME; PulseAudio en XFCE, MATE y LXQt.

En Alpine, el paquete real `pulseaudio` y `pipewire-pulse` se excluyen entre sí. Hoy, al instalar Plasma, Alpine elige PulseAudio, y PipeWire corre al lado para compartir pantalla. Respetar lo instalado evita que el script contradiga a Alpine si algún día cambia su elección.

Alpine arranca PipeWire con un lanzador automático que marcó como obsoleto. Si en una versión futura desaparece, el log indica cómo activarlo con los servicios de usuario de OpenRC (`rc-update -U add pipewire`).

Luego instala los indicadores de red y volumen de cada escritorio:

| Escritorio | Red | Volumen |
|---|---|---|
| XFCE | `network-manager-applet` | `xfce4-pulseaudio-plugin` |
| Plasma | `plasma-nm` | `plasma-pa` |
| GNOME | integrado | `pavucontrol` (mezclador avanzado) |
| MATE | `network-manager-applet` | `mate-media` |
| LXQt | `network-manager-applet` | `pavucontrol-qt` (el control de la bandeja ya viene en `lxqt-panel`) |

### Bloques 7 y 8 — WiFi
Detecta adaptadores WiFi internos (`lspci`) y USB (`lsusb`), y según el fabricante instala su firmware (`linux-firmware-intel`, `-realtek`, `-ath10k`, etc.). Si no reconoce el fabricante, instala un conjunto amplio. En una instalación normal de Alpine ese firmware ya está, así que este paso solo cambia algo en sistemas reducidos.

### Bloques 9 y 10 — Bluetooth
Detecta adaptadores Bluetooth y, si hay alguno, instala `bluez`, su firmware y el **puente de audio** del servidor elegido en el Bloque 6 (`pulseaudio-bluez` o `pipewire-spa-bluez`). Sin ese puente, los audífonos se emparejan pero no suenan. Si no hay adaptador, no instala nada.

### Bloque 11 — `detect_hardware`
Clasifica todas las tarjetas gráficas leyendo `/sys` (fabricante y tipo en números, sin depender del texto de `lspci`). Además averigua:

- cuál es la **gráfica principal**, la que usó el equipo al encender;
- si el equipo es **portátil**, por el tipo de chasis o por la presencia de batería;
- si es un **portátil Optimus**: portátil, una sola NVIDIA, y la principal es Intel o AMD.

También avisa si hay un adaptador de video USB DisplayLink, que Alpine no soporta.

### Bloque 12 — `install_drivers`
Instala los controladores de cada gráfica detectada:

- **Intel:** firmware, Vulkan y decodificación de video por hardware (`libva-intel-driver` para gráficas antiguas, `intel-media-driver` para las de 2014 en adelante).
- **AMD:** firmware, Vulkan (`mesa-vulkan-ati`) y decodificación de video (`mesa-va-gallium`).
- **Máquinas virtuales:** controladores de video y `spice-vdagent`.
- **NVIDIA:** firmware y uno de tres modos.

| Modo | Cuándo se ofrece | Qué hace |
|---|---|---|
| **Ahorro** | Solo en portátiles Optimus (predeterminado) | Carga `nouveau` para que pueda **apagar** la NVIDIA, y deja el escritorio y el video en la gráfica integrada |
| **Seguro** | Siempre | Bloquea `nouveau`. La NVIDIA queda sin driver, pero **sigue encendida** |
| **Activa** | Siempre | `nouveau` con aceleración 3D. Riesgo de pantalla negra en tarjetas antiguas |

Cada modo borra los archivos de los otros, así que volver a ejecutar el script y elegir otro modo cambia la configuración por completo.

**El modo de ahorro** se probó en un ASUS K53SV (Intel HD 3000 y GeForce GT 540M) con Plasma en Wayland: la NVIDIA queda apagada (`D3cold`), el escritorio fluido y el video de YouTube decodificado por la Intel. Resuelve tres cosas que mantenían encendida la NVIDIA:

1. **Programas que abren todas las gráficas.** Las variables `KWIN_DRM_DEVICES` y `MOZ_DRM_DEVICE` dejan a KWin y a Firefox en la integrada. Para Xorg (pantalla de inicio de SDDM, XFCE, MATE, LXQt) se desactiva `AutoAddGPU`.
2. **El audio HDMI de la NVIDIA.** Al arrancar se desconecta de su driver. No se pierde nada: las salidas de video del portátil están en la integrada.
3. **Una pantalla "fantasma".** `nouveau` creía tener algo conectado en su salida VGA, que en un portátil Optimus no está cableada. Al arrancar se desconectan las salidas analógicas de la NVIDIA; las digitales no se tocan.

Para comprobarlo después de reiniciar, el script muestra el comando exacto; debe responder `D3cold`.

Al final del bloque, `check_vaapi` comprueba con `vainfo` si la gráfica principal decodifica video H.264 y lo anota en el log.

> **Gráficas antiguas y YouTube:** las Intel de la época Sandy Bridge solo decodifican H.264, pero YouTube envía VP9 o AV1, que acaban en el procesador. Por eso el script recomienda la extensión *enhanced-h264ify* para Firefox.

### Bloque 13 — `check_unclaimed_devices`
Lista los dispositivos de red, video o audio que quedaron sin controlador, que es el síntoma de hardware que necesita controladores propietarios. Explica en el log los dos caminos de Alpine para esos casos y no aplica ninguno por su cuenta:

| Tipo | Ejemplos | Camino |
|---|---|---|
| Módulo del kernel | Broadcom `wl`, algunos Realtek USB | AKMS (equivalente a DKMS); varios paquetes están en el repositorio `testing` |
| Programa compilado para glibc | Controladores de impresora, Widevine | `gcompat` (opcional en el menú) |

Los controladores propietarios de NVIDIA no existen en Alpine; la única opción es `nouveau`.

### Bloque 14 — `detect_cpu`, `install_microcode`
Instala el microcódigo del procesador (`intel-ucode` o `amd-ucode`). No hace falta actualizar el cargador de arranque a mano: los paquetes `syslinux` y `grub` de Alpine se actualizan solos cada vez que cambia algo en `/boot`, y `update-extlinux` agrega la imagen del microcódigo a la línea `INITRD`. El script **comprueba** que la configuración del cargador la mencione y avisa si no (por ejemplo, si se desactivó la actualización automática con `disable_trigger=1`). No ejecuta `update-extlinux` por su cuenta, porque eso reescribiría un `extlinux.conf` editado a mano. También anota en el log el nivel x86-64 del procesador (v1 a v4), solo como dato: Alpine usa los mismos paquetes para todos los niveles.

### Bloque 15 — `setup_zram`
Crea memoria de intercambio comprimida en RAM (`zram`, con `zstd`) del mismo tamaño que la RAM física, y ajusta `vm.swappiness` y `vm.page-cluster` para ese uso. Ayuda mucho en equipos con poca memoria.

### Bloque 16 — `setup_earlyoom`
Instala `earlyoom`, que cierra el programa que está agotando la memoria antes de que el equipo se congele.

### Bloque 17 — `setup_power`
Con escritorio, **no** habilita `acpid` (y lo quita del arranque si estaba): `elogind` ya atiende el botón de encendido y la tapa, y tener los dos podía apagar el equipo por accidente. Alpine hace lo mismo en `setup-desktop` desde 2025. Solo en sistemas sin escritorio habilita `acpid`.

### Bloque 18 — `optimize_hdd_storage`
Si hay discos mecánicos, les asigna el planificador BFQ (o `mq-deadline` si el kernel no tiene BFQ) con una regla `udev`, para que una copia grande o una actualización no congelen el escritorio. La regla se aplica solo a discos mecánicos, aunque cambie su nombre (`sda`, `sdb`) entre arranques. **No modifica `/etc/fstab`**; sugiere en el log agregar `noatime` a mano.

### Bloque 18b — `setup_ssd_trim`
Si hay un disco de estado sólido que acepta TRIM, programa `fstrim -a` una vez por semana. Sin TRIM, los SSD baratos se vuelven más lentos al escribir con el tiempo, y Alpine no lo programa por defecto. Alpine no tiene un servicio `fstrim` de OpenRC, así que se usa su mecanismo propio: un script en `/etc/periodic/weekly/`, que ejecuta `crond`.

### Bloque 19 — `setup_usb_automount`
Hace que las memorias USB se monten solas: instala y habilita `dbus`, `udisks2`, `elogind` y `polkit`, más `gvfs` en XFCE, GNOME, MATE y LXQt (en LXQt también `lxqt-policykit`, y en XFCE `thunar-volman`). Plasma no necesita nada más.

### Bloque 20 — `setup_printing`
Solo si se marcó en el menú. Instala CUPS y su configurador; la administración web queda en `http://localhost:631`.

### Bloque 21 — `install_archive_tools`
Instala `zip`, `unzip` y `7zip`.

### Bloque 22 — `setup_locale_es`
Configura español (`es_ES.UTF-8`) en tres capas: `/etc/profile.d` para las consolas, `/etc/environment` para las sesiones gráficas, y el archivo propio de idioma de Plasma. También instala el metapaquete `lang`, que agrega solo las traducciones de todo lo instalado. musl, la biblioteca de C de Alpine, no tiene variantes regionales como `es_CO`, pero las traducciones de los programas son las mismas.

### Bloque 23 — `install_fonts`
Instala DejaVu, Liberation (compatible en medidas con Arial, Times y Courier, para abrir documentos de Office sin descuadres), Noto y Noto Emoji (sin ella, WhatsApp Web muestra cuadritos en vez de emojis).

### Bloque 24 — `install_libreoffice`
Solo si se marcó en el menú. LibreOffice con su paquete de idioma español.

### Bloque 25 — `setup_flatpak`
Solo si se marcó Flatpak, OnlyOffice o Chrome. Instala Flatpak, agrega Flathub y los portales del escritorio (para que los diálogos de abrir y guardar se vean como el resto del sistema), y luego las aplicaciones marcadas.

### Bloque 26 — `setup_display_manager`
Habilita la pantalla de inicio de sesión que corresponde al escritorio: SDDM para Plasma, GDM para GNOME y LightDM para los demás. Si hay más de una instalada, avisa cuál eligió.

### Bloque 27 — `setup_update_shortcut`
Crea el botón "Actualizar el sistema" (ver [la sección del botón](#el-botón-actualizar-el-sistema)). Funciona con dos scripts:

- `alpine-update-launcher.sh` corre como el usuario: pregunta por el cambio de versión, pide la contraseña con `pkexec` y muestra el avance con `zenity`.
- `alpine-update-root.sh` corre como administrador y solo hace el trabajo (`apk`, `flatpak`), sin ventanas.

Detalles de funcionamiento:

- **La ventana aparece después de la contraseña**, para no tapar el diálogo de `pkexec`.
- **Muestra una sola línea que se va reemplazando.** Para que la ventana se cierre bien al terminar se usa `tail --pid` de GNU coreutils (el `tail` de BusyBox no tiene esa opción), y `script` (de `util-linux-misc`) hace que `apk` muestre su avance línea por línea.
- **Agente de contraseña:** XFCE y MATE necesitan uno aparte (`polkit-gnome`, `mate-polkit`). El lanzador comprueba que esté corriendo y, si no, lo inicia.
- **Aviso de reinicio:** el lanzador avisa si el kernel en uso ya no está instalado o si cambió la versión de Alpine.

### Bloque 28 — `setup_user_groups`
Agrega al usuario a los grupos `audio`, `video` y `lpadmin` (sonido, video y administración de impresoras).

### Bloque 29 — `select_options_menu`
El menú inicial (ver [Menú de opciones](#menú-de-opciones)). Cada decisión queda en una variable `OPT_*`; la función `want` la consulta y, si el menú no se pudo mostrar, hace la pregunta por separado.

### Bloque 30 — `install_daily_apps`
Instala y deja como predeterminadas las aplicaciones de uso diario:

| Uso | Aplicación |
|---|---|
| PDF | Evince (Okular en Plasma) |
| Audio y video | `mpv`, que usa la decodificación por hardware del Bloque 12 |
| Navegador | Firefox (opcional en el menú) |

Las preferencias se escriben en `/etc/xdg/mimeapps.list`. Si el usuario ya eligió otra aplicación, su elección personal manda.

Firefox ofrece cambiar su interfaz al idioma del sistema en el primer arranque. Al final, el script recomienda dos extensiones, sin instalarlas: **uBlock Origin** (bloquea publicidad y reduce la carga del procesador) y **enhanced-h264ify** (ver Bloque 12).

### Bloque 31 — `main`
Ejecuta los bloques en el orden necesario.

## Archivos que crea o modifica

| Archivo | Bloque | Para qué |
|---|---|---|
| `/etc/X11/xorg.conf.d/00-keyboard.conf` | 3 | Teclado `latam` en Xorg |
| `/etc/xdg/plasma-workspace/env/teclado-latam.sh`, `/etc/profile.d/teclado-latam.sh` | 3 | `XKB_DEFAULT_LAYOUT=latam` para Wayland |
| `/etc/xdg/kxkbrc` | 3 | Teclado `latam` por defecto en Plasma |
| `/usr/share/glib-2.0/schemas/90-desktop-postinstall-teclado.gschema.override` | 3 | Teclado `latam` por defecto en GNOME |
| `/etc/modprobe.d/blacklist-nouveau.conf` | 12 | Bloqueo de `nouveau` (modo seguro) |
| `/etc/local.d/nvidia-optimus.start` | 12 | Modo ahorro: audio HDMI y salidas fantasma de la NVIDIA |
| `/etc/xdg/plasma-workspace/env/gpu-integrada.sh`, `/etc/profile.d/gpu-integrada.sh` | 12 | Modo ahorro: escritorio y video en la gráfica integrada |
| `/etc/X11/xorg.conf.d/20-gpu-integrada.conf` | 12 | Modo ahorro: Xorg no abre la NVIDIA |
| `/etc/conf.d/zram-init` | 15 | Configuración de zram |
| `/etc/sysctl.conf` | 15 | `vm.swappiness` y `vm.page-cluster` (se agregan líneas) |
| `/etc/udev/rules.d/60-ioscheduler.rules` | 18 | Planificador para discos mecánicos |
| `/etc/periodic/weekly/fstrim` | 18b | TRIM semanal de los SSD |
| `/etc/profile.d/lang-es.sh`, `/etc/environment` | 22 | Idioma español |
| `/etc/xdg/plasma-localerc`, `~/.config/plasma-localerc` | 22 | Idioma de Plasma (solo con Plasma) |
| `/etc/rc.conf` | 22 | Agrega `unicode="YES"` si falta |
| `/etc/xdg/mimeapps.list` | 30 | Aplicaciones predeterminadas |
| `/usr/local/bin/alpine-update-root.sh`, `/usr/local/bin/alpine-update-launcher.sh` | 27 | Botón de actualización |
| `/usr/share/applications/alpine-update.desktop` | 27 | Entrada "Actualizar el sistema" en el menú |
| `/var/log/alpine-update.log` | 27 | Registro del botón |
| `/var/backups/alpine-update/` | 27 | Copias de `/etc/apk/repositories` antes de cada cambio de versión |
| `/var/log/desktop-postinstall.log` | todos | Registro del script |

## Servicios que habilita

En el arranque normal (`default`): `networkmanager`, `dbus`, `elogind`, `polkit`, `zram-init`, `earlyoom`, la pantalla de inicio que corresponda (`lightdm`, `sddm` o `gdm`), y según el caso:

- `bluetooth`, si hay adaptador Bluetooth;
- `cupsd`, si se marcaron las impresoras;
- `local`, en el modo de ahorro de NVIDIA;
- `spice-vdagentd`, en máquinas virtuales;
- `crond`, si hay un SSD (para el TRIM semanal);
- `acpid`, solo en sistemas sin escritorio.

`udisks2`, `wpa_supplicant` y el servidor de audio no se habilitan como servicios: se activan solos cuando se necesitan o con cada sesión de usuario.

## Registro (log) y reejecución

Todo queda en `/var/log/desktop-postinstall.log` con cuatro niveles: `[INFO]` (paso en curso), `[OK]` (paso completado), `[WARN]` (algo falló, pero el script sigue) y `[ERROR]` (fallo grave que detiene el script). El registro se acumula entre ejecuciones.

El script se puede ejecutar varias veces sin hacer daño: instalar un paquete que ya está no hace nada, habilitar un servicio dos veces no lo duplica, y los archivos de configuración se reescriben completos. Sirve para cambiar una opción del menú o después de instalar otro escritorio.

## Compatibilidad con futuras versiones de Alpine

Alpine publica una versión estable cada mayo y cada noviembre (3.21 en diciembre de 2024, 3.22 en mayo de 2025, 3.23 en diciembre de 2025, 3.24 en junio de 2026). El repositorio `main` recibe soporte unos dos años; **`community` solo hasta la siguiente versión**, unos seis meses. Casi todo lo que instala este script está en `community`, así que conviene cambiar de versión cada seis meses, o al menos una vez al año. El botón "Actualizar el sistema" lo ofrece cuando hay una versión nueva.

Revisión hecha en octubre de 2026 contra los repositorios reales de Alpine (versiones 3.22, 3.23, 3.24 y edge):

- **Todos los paquetes del script existen en las cuatro versiones.**
- **apk-tools 3** (desde 3.23) acepta todas las órdenes que usa el script y el botón.
- **/usr-merge** (convertir `/bin`, `/sbin` y `/lib` en enlaces a `/usr`): estaba previsto para 3.23, se pospuso, y será obligatorio en una versión futura (Alpine mencionó 3.26 o 3.27). El script no escribe en esas carpetas. Cuando llegue, conviene leer las notas de esa versión antes de usar el cambio de versión del botón.
- **Wayland:** en Alpine, Plasma solo tiene sesión Wayland desde 3.22 y GNOME desde 3.24; edge ya trae Plasma 6.8. XFCE, MATE y LXQt siguen en Xorg. Por eso el teclado se configura en ambos.
- **PipeWire:** Alpine marcó como obsoleto su lanzador automático en favor de los servicios de usuario de OpenRC. El script detecta si falta y avisa.

## Limitaciones conocidas

- **NVIDIA con Xorg:** la corrección de la pantalla negra (ver [Historial](#historial-de-correcciones)) falta confirmarla en un equipo que arranque con Xorg. Si vuelve a ocurrir, entra a una consola de texto y revisa `dmesg | grep -i nouveau`, `lsmod | grep nouveau` y `/var/log/desktop-postinstall.log`.
- **Modo de ahorro de NVIDIA:** probado solo en un modelo (ASUS K53SV) con Plasma en Wayland. No se probó con XFCE, MATE o LXQt, ni la suspensión. Si algún puerto de video del portátil estuviera cableado a la NVIDIA, no daría imagen en este modo.
- **Modo seguro de NVIDIA:** deja la tarjeta sin driver, pero encendida. En un portátil Optimus conviene el modo de ahorro.
- **Cambio de versión de Alpine:** probado en una simulación, no todavía en un equipo real.
- **Montaje de USB:** depende de que `elogind` reconozca la sesión gráfica como activa. Si al montar pide la contraseña de root, el problema está ahí, no en los grupos del usuario.
- **El script no instala el escritorio:** hay que instalarlo antes con `setup-desktop`.

## Solución de problemas

**El teclado sigue en inglés en la sesión gráfica.** Abre una vez la configuración de teclado del escritorio y confirma que aparece "latam" (XFCE, por ejemplo, guarda su propia configuración la primera vez). En Plasma, si alguna vez se eligió otra distribución, esa elección (`~/.config/kxkbrc`) manda sobre la del script.

**Pantalla negra al iniciar con NVIDIA.** Entra a una consola de texto (Ctrl+Alt+F2). Si existe `/etc/X11/xorg.conf.d/20-nouveau-safe.conf`, de una versión anterior del script, bórralo y reinicia. Si la NVIDIA quedó activa, vuelve a ejecutar el script y elige el modo seguro (o el de ahorro, en un portátil Optimus).

**En el modo de ahorro, la NVIDIA sigue encendida (`D0`).** Revisa que el servicio `local` haya arrancado (`rc-status default | grep local`), que `nouveau` esté cargado (`lspci -k`) y qué programas tienen abierta la NVIDIA.

**El cambio de versión quedó incompleto.** No reinicies. Conéctate a internet y vuelve a pulsar el botón, o ejecuta `doas apk upgrade --available` en una terminal. La versión anterior de los repositorios está en `/var/backups/alpine-update/`.

**Flatpak no se instaló.** Revisa que el repositorio `community` esté habilitado y que haya internet.

**Las memorias USB no se montan solas.** Comprueba que `elogind` y `polkit` estén corriendo (`rc-service elogind status`, `rc-service polkit status`) y que hayas reiniciado después de ejecutar el script.

## Cómo revertir cambios

| Para quitar... | Hacer esto |
|---|---|
| Modo seguro de NVIDIA | Borrar `/etc/modprobe.d/blacklist-nouveau.conf`, ejecutar `mkinitfs $(uname -r)` y reiniciar |
| Modo de ahorro de NVIDIA | Borrar `/etc/local.d/nvidia-optimus.start`, los dos `gpu-integrada.sh` y `/etc/X11/xorg.conf.d/20-gpu-integrada.conf`; reiniciar |
| Teclado latam en Wayland | Borrar los dos `teclado-latam.sh`, `/etc/xdg/kxkbrc` y el esquema de GNOME; ejecutar `glib-compile-schemas /usr/share/glib-2.0/schemas` |
| Idioma | Borrar `/etc/profile.d/lang-es.sh`, las líneas `LANG`/`LC_*` de `/etc/environment` y, con Plasma, los dos `plasma-localerc` |
| Un cambio de versión de Alpine | Solo es seguro si `apk upgrade --available` todavía no se ejecutó: copiar el respaldo de `/var/backups/alpine-update/` sobre `/etc/apk/repositories` y ejecutar `doas apk update` |
| zram | `rc-service zram-init stop`, `rc-update del zram-init` y borrar `/etc/conf.d/zram-init` |
| EarlyOOM | `rc-update del earlyoom` y `apk del earlyoom earlyoom-openrc` |
| Impresoras | `rc-update del cupsd` y `apk del cups cups-filters system-config-printer` |
| Planificador de discos | Borrar `/etc/udev/rules.d/60-ioscheduler.rules` y reiniciar |
| TRIM semanal | Borrar `/etc/periodic/weekly/fstrim` |

## Historial de correcciones

Cambios importantes respecto a versiones anteriores del script, para quien venga de una de ellas:

- **Modo seguro de NVIDIA:** escribía `20-nouveau-safe.conf`, que pedía a Xorg usar el driver `nouveau` sin decir en qué tarjeta. Con el módulo bloqueado ese driver no funciona, y en un portátil híbrido Xorg lo aplicaba a la Intel: causa probable de la pantalla negra. Ya no se crea, y se borra si existe.
- **`acpid`:** se habilitaba siempre; ahora solo sin escritorio (ver Bloque 17).
- **Audio:** se forzaba PulseAudio; ahora se respeta el servidor que ya tenga el sistema (ver Bloque 6).
- **Teclado:** solo se configuraba para Xorg; ahora también para Wayland (ver Bloque 3).
- **`lsusb`:** el script daba por bueno el `lsusb` reducido de BusyBox y la detección por USB podía fallar en silencio; ahora instala `usbutils`.
- **Paquetes:** se quitó `mesa-vulkan-radeon`, que no existe y hacía fallar la instalación en equipos AMD; `p7zip` y `ttf-dejavu` se cambiaron por sus nombres actuales, `7zip` y `font-dejavu`.
- **Microcódigo AMD:** una versión decía que `amd-ucode` no existía; sí existe y se instala.
- **SSD:** no había TRIM periódico; ahora se programa uno semanal si hay un SSD.
- **Botón de actualización:** varios diseños anteriores de la ventana se quedaban congelados o no se cerraban; el actual usa `tail --pid`. El registro no se guardaba porque el usuario no podía escribir en `/var/log`; ahora el archivo pertenece al grupo `wheel`.
