# desktop-postinstall.sh — configuración de escritorio para Alpine Linux

Script de shell POSIX (`ash` de BusyBox, el shell de Alpine) que termina de configurar un escritorio recién instalado en Alpine Linux: red, audio, teclado, idioma, controladores de video, energía, impresión, aplicaciones de uso diario y estabilidad del sistema.

Está pensado para revivir equipos antiguos o con poca memoria (2 a 8 GB de RAM), pero sirve igual en equipos modernos. No asume nada: detecta el escritorio, la tarjeta gráfica y el procesador, e instala solo lo que corresponde.

> ⚠️ **Tarjetas NVIDIA.** Versiones anteriores del modo seguro podían dejar la pantalla en negro en algunos equipos. La causa probable ya se corrigió (ver [Bloque 16](#bloque-16--install_drivers)), pero falta confirmarlo en un equipo que arranque con Xorg. En portátiles Optimus hay un modo nuevo, probado en un equipo real, que apaga la NVIDIA y deja todo en la gráfica integrada.

> 💿 **Lázaro Linux.** Este script también va dentro de la ISO instalable de [Lázaro Linux](https://github.com/Entropio1984/lazaro-linux) (*Tu hardware aún tiene pulso*), que lo ejecuta al final de la instalación sin hacer preguntas.

---

## Contenido

1. [Requisitos](#requisitos)
2. [Cómo ejecutarlo](#cómo-ejecutarlo)
3. [Opciones de la línea de órdenes](#opciones-de-la-línea-de-órdenes)
4. [Menú de opciones](#menú-de-opciones)
5. [El botón "Actualizar el sistema"](#el-botón-actualizar-el-sistema)
6. [Qué hace cada bloque](#qué-hace-cada-bloque)
7. [Archivos que crea o modifica](#archivos-que-crea-o-modifica)
8. [Servicios que habilita](#servicios-que-habilita)
9. [Registro (log) y reejecución](#registro-log-y-reejecución)
10. [Compatibilidad con futuras versiones de Alpine](#compatibilidad-con-futuras-versiones-de-alpine)
11. [Limitaciones conocidas](#limitaciones-conocidas)
12. [Solución de problemas](#solución-de-problemas)
13. [Cómo revertir cambios](#cómo-revertir-cambios)
14. [Historial de correcciones](#historial-de-correcciones)

---

## Requisitos

- Alpine Linux instalado con `setup-alpine`.
- Un escritorio instalado con `setup-desktop`: XFCE, KDE Plasma, GNOME, MATE, LXQt o Sway. El script lo complementa; también puede instalarlo él mismo con `--escritorio` (ver [Opciones](#opciones-de-la-línea-de-órdenes)). Sin escritorio, hace solo la configuración de consola.
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

Para no ver el menú e instalar todo de una vez:

```sh
doas sh desktop-postinstall.sh --full
```

**Recién instalado, antes del primer reinicio.** Si acabas de instalar Alpine en un disco y el sistema nuevo sigue montado (por ejemplo en `/mnt`), el script lo puede configurar desde el sistema en el que estás, sin reiniciar:

```sh
sh desktop-postinstall.sh --full --destino /mnt
```

Con `--escritorio xfce` (u otro) instala además el escritorio. Al encender el equipo nuevo, todo queda listo. Si el sistema ya arrancó alguna vez, ejecuta el script dentro de él, sin `--destino`.

## Opciones de la línea de órdenes

Sin opciones aparece el menú. Con cualquiera de estas opciones (salvo `--usuario`, `--escritorio` y `--destino`) el script no pregunta nada. Así lo puede llamar un instalador gráfico, como Calamares en [Lázaro Linux](https://github.com/Entropio1984/lazaro-linux), con lo que eligió el usuario.

| Opción | Qué hace |
|---|---|
| `--full` | Instala todos los programas de la lista de abajo |
| `--minimo` | Solo la configuración base (red, audio, controladores, idioma, energía...), sin programas opcionales |
| `--con LISTA` | Marca esos programas (separados por comas) |
| `--sin LISTA` | Desmarca esos programas; gana sobre `--con` y `--full` |
| `--menu` | Muestra el menú igual, con lo anterior ya marcado |
| `--idioma IDIOMA` | Idioma del sistema, por ejemplo `es_CO.UTF-8` (por defecto `es_ES.UTF-8`) |
| `--teclado latam` o `--teclado no` | Teclado latinoamericano, o no tocar el teclado |
| `--nvidia seguro`, `optimus` o `activa` | Qué hacer con una NVIDIA (ver [Bloque 16](#bloque-16--install_drivers)). `optimus` es el modo automático: en portátiles con dos gráficas apaga la NVIDIA; en los demás equipos la deja activa si es Kepler (2012) o más nueva y usa el modo seguro si es más antigua o no se identificó |
| `--usuario NOMBRE` | El usuario del escritorio, si no se puede adivinar |
| `--escritorio NOMBRE` | Instala antes ese escritorio con `setup-desktop`: `xfce`, `xfce-wayland`, `mate`, `lxqt`, `gnome`, `plasma` o `sway` |
| `--destino CARPETA` | Configura el sistema instalado en esa carpeta, sin reiniciar |
| `--ayuda` | Muestra la ayuda |

Programas para `--con` y `--sin`: `impresoras`, `libreoffice`, `firefox`, `vlc`, `youtube` (YouTube ligero: pipe-viewer + mpv), `fastfetch`, `btop`, `flatpak` (tienda Flathub), `onlyoffice`, `chrome`, `brave` (estos tres por Flatpak; marcarlos activa Flatpak), `gcompat` y `actualizaciones` (botón "Actualizar el sistema", aviso de actualizaciones en la barra y, en Sway, su icono en waybar).

Sin `--full` ni `--minimo`, se parte de las casillas premarcadas del menú. Sin escritorio, los programas gráficos se omiten aunque se pidan. Ejemplos:

```sh
desktop-postinstall.sh --minimo --con libreoffice,vlc,brave
desktop-postinstall.sh --full --sin chrome --idioma es_MX.UTF-8
desktop-postinstall.sh --escritorio xfce --full --destino /mnt
```

Las decisiones también se pueden fijar con variables de entorno, como hacían los instaladores anteriores: `OPT_LIBREOFFICE=yes`, `OPT_CHROME=no`, `OPT_LANG=es_CO.UTF-8`... (una por casilla del menú). Si se dan las dos cosas, mandan las opciones.

## Menú de opciones

Se navega con las flechas, se marca o desmarca con la **barra espaciadora** y se continúa con **Enter**. Después aparece un resumen con dos botones: **Comenzar** o **Volver** (vuelve al menú sin perder lo marcado). **Salir** termina el script sin cambiar la configuración del sistema.

| Opción | Marcada por defecto | Qué hace |
|---|---|---|
| Teclado latinoamericano | Sí | Distribución `latam` en la consola, en Xorg y en sesiones Wayland |
| NVIDIA en modo seguro | Según la tarjeta | Solo aparece si hay una NVIDIA y el equipo **no** es un portátil Optimus. Bloquea el driver `nouveau`. Viene marcada en tarjetas Tesla o Fermi (o no identificadas) y desmarcada en Kepler o más nuevas |
| gcompat | No | Permite ejecutar programas propietarios compilados para otras distribuciones (glibc) |
| Impresoras (CUPS) | Sí | Instala el sistema de impresión |
| Fastfetch | No | Resumen del equipo en la terminal |
| Btop | No | Monitor de procesador, memoria y discos |
| LibreOffice | Sí | Suite de oficina en el idioma del sistema (paquete pesado) |
| Firefox | Sí | Navegador, registrado como predeterminado |
| VLC | No | Reproductor de video completo (además de `mpv`) |
| YouTube ligero | No | Buscar y ver videos de YouTube sin navegador (pipe-viewer + mpv, hasta 480p). Ver [YouTube ligero](#youtube-ligero) |
| Flatpak/Flathub | No | Tienda de aplicaciones Flatpak |
| OnlyOffice | No | Por Flatpak; marcarla activa Flatpak |
| Google Chrome | No | Por Flatpak (paquete comunitario, no oficial de Google); marcarla activa Flatpak |
| Brave | No | Navegador por Flatpak; marcarla activa Flatpak |
| Botón "Actualizar el sistema" | Sí | Acceso directo en el menú de aplicaciones y aviso cuando hay actualizaciones |

Sin escritorio, el menú no muestra los programas gráficos.

**Portátiles Optimus** (gráfica integrada más una NVIDIA): en lugar de la casilla de NVIDIA aparece una segunda pantalla con tres modos: *ahorro* (recomendado y marcado por defecto), *seguro* o *activa*. Ver [Bloque 16](#bloque-16--install_drivers).

**Por qué esos valores por defecto:** en las NVIDIA más antiguas (Tesla y Fermi), dejar `nouveau` activo puede terminar en pantalla negra, así que ahí el modo seguro viene marcado; desde Kepler `nouveau` maneja bien el escritorio y bloquearlo dejaría el equipo sin aceleración. Flatpak viene desmarcado porque instalarlo sin ninguna aplicación no sirve de nada; por eso se activa solo al marcar OnlyOffice, Chrome o Brave.

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

Si una descarga se queda detenida (3 minutos sin avanzar), el botón corta ese paso y lo repite, hasta 3 veces. Si se pulsa el botón mientras otra actualización sigue en curso, avisa y no empieza otra. Cerrar la ventana no detiene la actualización (cortarla a la mitad podría dejar el sistema a medio actualizar): sigue en segundo plano y avisa al terminar.

Cada ejecución queda registrada en `/var/log/alpine-update.log`.

**Aviso de actualizaciones.** Cada 6 horas (con `crond`, desde `/etc/periodic/hourly/alpine-update-revisar`) se leen los repositorios y se anota cuántos paquetes se pueden actualizar en `/var/lib/alpine-update/pendientes`. Si hay alguno:

- En XFCE, MATE y LXQt aparece un icono en la bandeja del panel y una notificación con el botón "Actualizar ahora". En GNOME, que no tiene bandeja, solo la notificación. Los dos abren "Actualizar el sistema" (`/usr/local/bin/alpine-update-aviso`, que arranca con la sesión desde `/etc/xdg/autostart`).
- En Sway aparece un icono con el número en waybar; un clic abre el botón.
- Plasma no lleva este aviso: trae el suyo (Discover).

Al terminar una actualización, el número se cuenta otra vez y el icono desaparece.

## Qué hace cada bloque

El script tiene 38 bloques, escritos en el mismo orden en que los ejecuta `main()`. Primero las opciones y las detecciones (escritorio y gráficas), luego todas las decisiones (Bloque 8), y después la instalación, sin más preguntas.

Principios que siguen todos los bloques:

- **Detectar antes de asumir:** el escritorio se averigua con `apk info -e`, las gráficas leyendo `/sys`, el procesador con `/proc/cpuinfo`.
- **No abortar por un paquete que falta:** si un paquete no existe en la versión instalada, se anota un aviso y el script sigue.
- **Decir la verdad sobre los límites:** si algo no tiene solución en Alpine (por ejemplo, los controladores propietarios de NVIDIA), el log lo dice en vez de fingir que lo resolvió.

### Bloque 1 — `leer_argumentos`
Lee las opciones de la línea de órdenes (ver [Opciones](#opciones-de-la-línea-de-órdenes)) y comprueba que sean válidas antes de tocar nada. Un nombre de programa, de escritorio o de idioma desconocido detiene el script con un mensaje claro. `--ayuda` funciona sin ser administrador.

### Bloque 2 — `check_root`
Comprueba que el script corre como administrador; si no, se detiene con un mensaje claro.

### Bloque 3 — `ejecutar_en_destino`
Solo con `--destino CARPETA`. Comprueba que en esa carpeta haya un Alpine instalado, monta `proc`, `sys`, `dev` y `dev/pts` dentro de ella, copia la configuración de internet (`resolv.conf`) y se ejecuta a sí mismo "dentro" de ese sistema con `chroot`, con las mismas opciones. Al terminar cierra los procesos que hayan quedado vivos ahí dentro, desmonta lo que montó y borra su copia. Es lo mismo que hace el instalador de Lázaro Linux.

### Bloque 4 — `update_system`, `install_pkg`, `install_pkgs`
`update_system` ejecuta `apk update` una vez al principio. `install_pkgs` instala varios paquetes en una sola operación de `apk`, que es mucho más rápido. Si esa operación falla (por ejemplo, porque un nombre no existe en esta versión), reintenta paquete por paquete con `install_pkg`, que tolera fallos individuales.

**Vigilante de descargas (`apk_vigilado`).** Cada llamada a `apk` se vigila por dos problemas:

- **Descarga detenida.** A veces el servidor deja de mandar datos a mitad de una descarga y `apk` se queda esperando para siempre. Si pasa **2 minutos sin avanzar** (sin leer ni escribir nada y sin ningún programa de instalación trabajando), se corta y se reintenta.
- **Corte de internet.** Si `apk` falla y su mensaje es de red (DNS, conexión, descarga cortada, error del servidor), el script espera a que el repositorio vuelva a responder (`esperar_red`, hasta 3 minutos) y reintenta. Un microcorte de unos segundos ya no deja paquetes sin instalar.

Son **hasta 4 intentos** en total, y cada reintento sigue donde quedó, porque `apk` guarda cada paquete al terminar de instalarlo. Si la red no vuelve, el script da la conexión por caída: las siguientes descargas ya no esperan (fallarían igual), sigue con lo que no necesita internet y al final avisa cuántas descargas faltaron y pide volver a ejecutarlo (ver [Registro](#registro-log-y-reejecución)). Antes del `apk update` del principio el script espera hasta 2 minutos a que haya internet; sin el índice de paquetes no se puede seguir, así que si no lo consigue se detiene.

**Avance en pantalla.** Mientras `apk`, `setup-desktop` o Flatpak trabajan, la pantalla muestra una línea por paquete, por ejemplo `(12/80) Instalando libreoffice-writer` o `(1/2) Descargando de Flathub`. Si pasan 20 segundos sin novedades (una descarga grande, un paquete que tarda en configurarse), aparece `... sigue trabajando (1 min 20 s)`, para que se vea que el script no está congelado. La salida completa sigue yendo solo al registro.

`ensure_hw_tools` instala `pciutils` y `usbutils`. El BusyBox de Alpine trae un `lsusb` reducido que solo muestra códigos numéricos, sin los nombres que necesitan los bloques de detección.

### Bloque 5 — `install_desktop`
Solo con `--escritorio NOMBRE`. Instala ese escritorio con `setup-desktop`, la herramienta de Alpine, antes de todo lo demás. Si falla (por ejemplo, por un corte de internet), espera a la red y lo repite hasta 3 veces. Si el escritorio ya estaba, `setup-desktop` solo comprueba que no falte nada.

### Bloque 6 — `detect_desktop_environment`
Pregunta a `apk` qué escritorios están instalados y guarda el resultado en `DE_XFCE`, `DE_PLASMA`, `DE_GNOME`, `DE_MATE`, `DE_LXQT` y `DE_SWAY`. Si hay más de uno, configura todos.

### Bloque 7 — `detect_hardware`
Clasifica todas las tarjetas gráficas leyendo `/sys` (fabricante y tipo en números, sin depender del texto de `lspci`). Además averigua:

- cuál es la **gráfica principal**, la que usó el equipo al encender;
- si el equipo es **portátil**, por el tipo de chasis o por la presencia de batería;
- si es un **portátil Optimus**: portátil, una sola NVIDIA, y la principal es Intel o AMD;
- la **generación de cada NVIDIA**, por el nombre de su chip (base de datos de `lspci`, o el registro de `nouveau` si no aparece): Tesla, Fermi, Kepler, Maxwell, Pascal, Volta o moderna (Turing, 2018, en adelante). Con varias NVIDIA manda la más antigua.

También avisa si hay un adaptador de video USB DisplayLink, que Alpine no soporta.

### Bloque 8 — `decidir_opciones`, `select_options_menu`
Todas las decisiones se toman aquí, antes de instalar nada, y cada una queda en una variable `OPT_*`:

- **Con opciones** (`--full`, `--minimo`, `--con`...): se usan esas, sin preguntar. Lo que no digan las opciones sale de las variables `OPT_*` del entorno, si las hay, y si no de las casillas premarcadas del menú.
- **Sin opciones y con terminal:** el menú de casillas (ver [Menú de opciones](#menú-de-opciones)).
- **Sin opciones y sin terminal:** las variables `OPT_*` del entorno; lo que falte lo pregunta la función `want` en su momento.

En los tres casos se aplican dos reglas: OnlyOffice, Chrome y Brave activan Flatpak, y sin escritorio no se instalan programas gráficos.

### Bloque 9 — `setup_keyboard_layout`
Solo si se marcó en el menú. Configura la distribución latinoamericana (`latam`) en cuatro lugares, porque cada uno la lee por su cuenta:

- **Consola de texto:** `setup-keymap latam latam`.
- **Xorg** (XFCE, MATE, LXQt y la pantalla de inicio de SDDM, que en Alpine usa Xorg): `/etc/X11/xorg.conf.d/00-keyboard.conf`.
- **Wayland** (Plasma desde Alpine 3.22, GNOME desde 3.24, sway, labwc): Wayland no lee `/etc/X11/`. Se agregan:
  - la variable `XKB_DEFAULT_LAYOUT=latam`, que KWin usa cuando el usuario no ha elegido distribución (comprobado en el código de KWin), igual que los compositores basados en wlroots;
  - `/etc/xdg/kxkbrc`, el valor por defecto de Plasma, que se ve en Preferencias del sistema;
  - un esquema de `gsettings` para GNOME, que también aplica a su pantalla de inicio.

Lo que el usuario elija después en la configuración del escritorio tiene prioridad sobre estos valores.

### Bloque 10 — `detect_target_user`
Identifica al usuario real (no root) para aplicarle el idioma y los grupos más adelante. Lo busca en este orden: `--usuario`, `$DOAS_USER` (quien ejecutó `doas`), `logname` y, si nada de eso sirve (por ejemplo, con `--destino` o al arrancar), el único usuario normal del sistema, si hay solo uno. Si no lo encuentra, los bloques que lo necesitan avisan y siguen.

### Bloque 11 — `setup_applets`
Instala NetworkManager y un servidor de audio:

- Si el sistema ya tiene **PipeWire** (`pipewire-pulse`) o **PulseAudio**, lo respeta.
- Si no tiene ninguno: PipeWire en Plasma y GNOME; PulseAudio en XFCE, MATE, LXQt y Sway.

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
| Sway | `network-manager-applet` (en la bandeja de `waybar`) | control de volumen de `waybar`; al hacer clic abre `pavucontrol` |

En XFCE, instalar el plugin no basta: el panel que XFCE crea la primera vez para cada usuario sale de `/etc/xdg/xfce4/panel/default.xml`, que no lo incluye. El script lo agrega ahí, junto al área de notificación y con las teclas de volumen activadas. Solo afecta a los usuarios que todavía no entraron a XFCE; quien ya tiene su panel lo agrega con clic derecho en el panel > Panel > Agregar elementos > Plugin de audio PulseAudio.

**Sway** trae de fábrica una barra que solo muestra la fecha: sin WiFi, sin volumen y sin menú de aplicaciones. El script la cambia por **`waybar`** (con iconos de `font-awesome`), que tiene:

- un botón de **menú de aplicaciones** (`fuzzel`), que también se abre con **Super+D**;
- un botón con la **lista de atajos de teclado** (`sway-atajos`), que también se abre con **Super+F1**. La lista se lee de la configuración real de Sway, sale en español si el sistema está en español, y se puede escribir para buscar;
- el icono de WiFi de NetworkManager, el volumen (la rueda del ratón lo sube y lo baja), la red (al hacer clic abre `nmtui`), la batería, el brillo y el reloj.

Como Sway no arranca los programas de `/etc/xdg/autostart`, el script los agrega en `/etc/sway/config.d/50-lazaro-barra.conf`: el servidor de audio, el icono de WiFi y la ventana de contraseña de administrador (`polkit-gnome`). La configuración de `waybar` se copia al usuario y a `/etc/skel` (usuarios nuevos); si el usuario ya tenía una propia, no se toca. Si `waybar` no se puede instalar, queda la barra original.

### Bloques 12 y 13 — WiFi
Detecta adaptadores WiFi internos (`lspci`) y USB (`lsusb`), y según el fabricante instala su firmware (`linux-firmware-intel`, `-realtek`, `-ath10k`, etc.). Si **no hay adaptador WiFi, no instala nada**. El conjunto amplio de firmware (de varios fabricantes) se instala solo en dos casos: hay un adaptador pero no se reconoce el fabricante, o no se pudo revisar del todo el hardware (no están `pciutils` y `usbutils`, que traen los nombres de los dispositivos, o `lspci`/`lsusb` fallaron). En una instalación normal de Alpine ese firmware ya está, así que este paso solo cambia algo en sistemas reducidos.

### Bloques 14 y 15 — Bluetooth
Detecta adaptadores Bluetooth y, si hay alguno, instala `bluez`, su firmware y el **puente de audio** del servidor elegido en el Bloque 11 (`pulseaudio-bluez` o `pipewire-spa-bluez`). Sin ese puente, los audífonos se emparejan pero no suenan. Si no hay adaptador, **no instala nada** (ni `bluez` ni firmware). Solo si no se pudo revisar del todo el hardware (igual que en el Bloque 12) instala Bluetooth por si acaso.

### Bloque 16 — `install_drivers`
Instala los controladores de cada gráfica detectada:

- **Intel:** firmware, Vulkan y decodificación de video por hardware (`libva-intel-driver` para gráficas antiguas, `intel-media-driver` para las de 2014 en adelante).
- **AMD:** firmware, Vulkan (`mesa-vulkan-ati`) y decodificación de video (`mesa-va-gallium`).
- **Máquinas virtuales:** controladores de video y `spice-vdagent`.
- **NVIDIA:** firmware y uno de tres modos. En tarjetas Turing o más nuevas también Vulkan libre (`mesa-vulkan-nouveau`, NVK), con el que Mesa da OpenGL por encima de Vulkan (Zink).

| Modo | Cuándo se ofrece | Qué hace |
|---|---|---|
| **Ahorro** | Solo en portátiles Optimus (predeterminado) | Carga `nouveau` para que pueda **apagar** la NVIDIA, y deja el escritorio y el video en la gráfica integrada |
| **Seguro** | Siempre | Bloquea `nouveau`. La NVIDIA queda sin driver, pero **sigue encendida** |
| **Activa** | Siempre (predeterminado si no es Optimus y la NVIDIA es Kepler o más nueva) | `nouveau` con aceleración 3D. Riesgo de pantalla negra en tarjetas Tesla o Fermi |

Cada modo borra los archivos de los otros, así que volver a ejecutar el script y elegir otro modo cambia la configuración por completo.

**El modo de ahorro** se probó en un ASUS K53SV (Intel HD 3000 y GeForce GT 540M) con Plasma en Wayland: la NVIDIA queda apagada (`D3cold`), el escritorio fluido y el video de YouTube decodificado por la Intel. Resuelve tres cosas que mantenían encendida la NVIDIA:

1. **Programas que abren todas las gráficas.** Las variables `KWIN_DRM_DEVICES` y `MOZ_DRM_DEVICE` dejan a KWin y a Firefox en la integrada. Para Xorg (pantalla de inicio de SDDM, XFCE, MATE, LXQt) se desactiva `AutoAddGPU`.
2. **El audio HDMI de la NVIDIA.** Al arrancar se desconecta de su driver. No se pierde nada: las salidas de video del portátil están en la integrada.
3. **Una pantalla "fantasma".** `nouveau` creía tener algo conectado en su salida VGA, que en un portátil Optimus no está cableada. Al arrancar se desconectan las salidas analógicas de la NVIDIA; las digitales no se tocan.

Para comprobarlo después de reiniciar, el script muestra el comando exacto; debe responder `D3cold`.

Al final del bloque, `check_vaapi` comprueba con `vainfo` si la gráfica principal decodifica video H.264 y lo anota en el log.

> **Gráficas antiguas y YouTube:** las Intel de la época Sandy Bridge solo decodifican H.264, pero YouTube envía VP9 o AV1, que acaban en el procesador. Por eso el script recomienda la extensión *enhanced-h264ify* para Firefox.

### Bloque 17 — `check_unclaimed_devices`
Lista los dispositivos de red, video o audio que quedaron sin controlador, que es el síntoma de hardware que necesita controladores propietarios. Explica en el log los dos caminos de Alpine para esos casos y no aplica ninguno por su cuenta:

| Tipo | Ejemplos | Camino |
|---|---|---|
| Módulo del kernel | Broadcom `wl`, algunos Realtek USB | AKMS (equivalente a DKMS); varios paquetes están en el repositorio `testing` |
| Programa compilado para glibc | Controladores de impresora, Widevine | `gcompat` (opcional en el menú) |

Los controladores propietarios de NVIDIA no existen en Alpine; la única opción es `nouveau`.

### Bloque 18 — `detect_cpu`, `install_microcode`
Instala el microcódigo del procesador (`intel-ucode` o `amd-ucode`). No hace falta actualizar el cargador de arranque a mano: los paquetes `syslinux` y `grub` de Alpine se actualizan solos cada vez que cambia algo en `/boot`, y `update-extlinux` agrega la imagen del microcódigo a la línea `INITRD`. El script **comprueba** que la configuración del cargador la mencione y avisa si no (por ejemplo, si se desactivó la actualización automática con `disable_trigger=1`). No ejecuta `update-extlinux` por su cuenta, porque eso reescribiría un `extlinux.conf` editado a mano. También anota en el log el nivel x86-64 del procesador (v1 a v4), solo como dato: Alpine usa los mismos paquetes para todos los niveles.

### Bloque 19 — `setup_zram`
Crea memoria de intercambio comprimida en RAM (`zram`, con `zstd`) del mismo tamaño que la RAM física, y ajusta `vm.swappiness` y `vm.page-cluster` para ese uso. Ayuda mucho en equipos con poca memoria.

### Bloque 20 — `setup_earlyoom`
Instala `earlyoom`, que cierra el programa que está agotando la memoria antes de que el equipo se congele.

### Bloque 21 — `setup_power`
Con escritorio, **no** habilita `acpid` (y lo quita del arranque si estaba): `elogind` ya atiende el botón de encendido y la tapa, y tener los dos podía apagar el equipo por accidente. Alpine hace lo mismo en `setup-desktop` desde 2025. Solo en sistemas sin escritorio habilita `acpid`.

### Bloque 22 — `optimize_hdd_storage`
Si hay discos mecánicos, les asigna el planificador BFQ (o `mq-deadline` si el kernel no tiene BFQ) con una regla `udev`, para que una copia grande o una actualización no congelen el escritorio. La regla se aplica solo a discos mecánicos, aunque cambie su nombre (`sda`, `sdb`) entre arranques. **No modifica `/etc/fstab`**; sugiere en el log agregar `noatime` a mano.

### Bloque 23 — `setup_ssd_trim`
Si hay un disco de estado sólido que acepta TRIM, programa `fstrim -a` una vez por semana. Sin TRIM, los SSD baratos se vuelven más lentos al escribir con el tiempo, y Alpine no lo programa por defecto. Alpine no tiene un servicio `fstrim` de OpenRC, así que se usa su mecanismo propio: un script en `/etc/periodic/weekly/`, que ejecuta `crond`.

### Bloque 24 — `setup_usb_automount`
Hace que las memorias USB se monten solas: instala y habilita `dbus`, `udisks2`, `elogind` y `polkit`, más `gvfs` en XFCE, GNOME, MATE y LXQt (en LXQt también `lxqt-policykit`, y en XFCE `thunar-volman`). Plasma no necesita nada más.

### Bloque 25 — `setup_printing`
Solo si se marcó en el menú. Instala CUPS y su configurador; la administración web queda en `http://localhost:631`.

### Bloque 26 — `install_archive_tools`
Instala `zip`, `unzip` y `7zip`.

### Bloque 27 — `install_console_tools`
Opcional: **Fastfetch** (resumen del equipo en la terminal) y **Btop** (monitor de procesador, memoria y discos). Los dos funcionan también sin escritorio.

### Bloque 28 — `setup_locale`
Configura español (`es_ES.UTF-8`), u otro idioma si se indica con la variable `OPT_LANG` (por ejemplo `OPT_LANG=pt_BR.UTF-8`, como hace el instalador de Lázaro Linux), en tres capas: `/etc/profile.d` para las consolas, `/etc/environment` para las sesiones gráficas, y el archivo propio de idioma de Plasma. También instala el metapaquete `lang`, que agrega solo las traducciones de todo lo instalado. musl, la biblioteca de C de Alpine, no tiene variantes regionales como `es_CO`, pero las traducciones de los programas son las mismas.

### Bloque 29 — `install_fonts`
Instala DejaVu, Liberation (compatible en medidas con Arial, Times y Courier, para abrir documentos de Office sin descuadres), Noto y Noto Emoji (sin ella, WhatsApp Web muestra cuadritos en vez de emojis).

### Bloque 30 — `install_libreoffice`
Solo si se marcó en el menú. LibreOffice con su paquete de idioma español.

### Bloque 31 — `install_daily_apps`
Instala y deja como predeterminadas las aplicaciones de uso diario:

| Uso | Aplicación |
|---|---|
| PDF | Evince (Okular en Plasma) |
| Audio y video | `mpv`, que usa la decodificación por hardware del Bloque 16 |
| Reproductor completo | VLC (opcional; `vlc` y `vlc-qt`, que trae la ventana y la entrada del menú). `mpv` sigue siendo el predeterminado |
| YouTube | YouTube ligero (opcional): `gtk-pipe-viewer` para buscar y `mpv` para ver. Ver [YouTube ligero](#youtube-ligero) |
| Navegador | Firefox (opcional en el menú) |
| Tienda de aplicaciones | Discover en LXQt; GNOME Software (con `gnome-software-plugin-apk2` y `apk-polkit-rs`) en XFCE, MATE y Sway. Plasma y GNOME ya traen la suya |

La tienda instala y actualiza paquetes de Alpine y, si se activó Flatpak, también aplicaciones de Flathub.

Las preferencias se escriben en `/etc/xdg/mimeapps.list`. Si el usuario ya eligió otra aplicación, su elección personal manda.

#### YouTube ligero

Para equipos de un núcleo y 2 GB, donde YouTube en el navegador se traba. En el menú aparece **YouTube** (icono genérico de video): se busca en esa ventana (`gtk-pipe-viewer`) y el video se abre en `mpv`.

| Archivo | Qué deja |
|---|---|
| Paquetes | `pipe-viewer`, `pipe-viewer-gtk`, `mpv`, `yt-dlp` y `yt-dlp-ejs-rt-quickjs` |
| `/etc/yt-dlp.conf` | `--js-runtimes quickjs`: el motor de JavaScript que yt-dlp usa para los desafíos de YouTube. Lo leen mpv y pipe-viewer |
| `/etc/mpv/mpv.conf` | Hasta 480p, H.264 (`avc1`), 30 cuadros y audio AAC cuando mpv abre un enlace; `hwdec=auto-safe`; caché de 50 MB; salida de video `gpu-next` con respaldo por procesador (`wlshm`, `x11`) para equipos sin 3D |
| `~/.config/pipe-viewer/gtk-pipe-viewer.conf` y `pipe-viewer.conf` (también en `/etc/skel`) | Solo las opciones que cambian; pipe-viewer agrega las demás con su valor por defecto |
| `/usr/share/applications/lazaro-youtube.desktop` | La entrada "YouTube" del menú. La original, "GTK Pipe Viewer", se oculta con una copia en `/usr/local/share/applications` |

Opciones de pipe-viewer que se cambian (todas existen en la versión 0.5.3):

| Opción | Valor original | Valor en Lázaro |
|---|---|---|
| `video_player_selected` | `undef` (el primero que encuentra) | `"mpv"` |
| `resolution` | `"best"` | `"480"` |
| `prefer_mp4` | `0` | `1` |
| `prefer_m4a` | `0` | `1` |
| `ignore_av1` | `0` | `1` |
| `hfr` (60 cuadros) | `1` | `0` |
| `srt_languages` | `["en", "es"]` | `["es", "en"]` |
| `thousand_separator` | `","` | `"."` |

**Por qué QuickJS:** el paquete `yt-dlp` de Alpine ya trae el componente `yt-dlp-ejs` (no hace falta `--remote-components`), pero sin indicar nada `apk` instala Deno (unos 40 MB). Con `yt-dlp-ejs-rt-quickjs` queda QuickJS (menos de 1 MB). Alpine solo activa deno y node por defecto, por eso hace falta `/etc/yt-dlp.conf`. Todo YouTube ligero suma unos 18 MB.

**Cuando YouTube cambia y los videos dejan de abrir:** casi siempre basta con actualizar yt-dlp:

```sh
doas apk upgrade yt-dlp yt-dlp-ejs pipe-viewer
```

Si la versión de Alpine estable todavía no trae el arreglo, se puede tomar solo yt-dlp de la rama edge (es Python puro, no arrastra el resto del sistema):

```sh
doas apk upgrade --repository https://dl-cdn.alpinelinux.org/alpine/edge/community yt-dlp yt-dlp-ejs yt-dlp-ejs-rt-quickjs
```

Para ver qué falla: `yt-dlp -v "https://www.youtube.com/watch?v=..."`. Si el problema es el motor de JavaScript, se puede probar Deno: `doas apk add deno` y cambiar `quickjs` por `deno` en `/etc/yt-dlp.conf`.

**Calidad según el equipo:** con un solo núcleo, el script deja 360p desde el principio (en una prueba, 480p a pantalla completa usó 56 % de un núcleo moderno); con dos o más, 480p. Si aun así el video se traba, bajar a 360p:

- En la ventana de YouTube: en los ajustes, elegir la resolución 360 (pipe-viewer la guarda al cerrar la ventana).
- O a mano: en `~/.config/pipe-viewer/gtk-pipe-viewer.conf` cambiar `resolution => "480"` por `resolution => "360"`, y en `/etc/mpv/mpv.conf` (o en una copia en `~/.config/mpv/mpv.conf`) cambiar cada `480` por `360`.

Firefox ofrece cambiar su interfaz al idioma del sistema en el primer arranque. Al final, el script recomienda dos extensiones, sin instalarlas: **uBlock Origin** (bloquea publicidad y reduce la carga del procesador) y **enhanced-h264ify** (ver Bloque 16).

### Bloque 32 — `setup_flatpak`
Solo si se marcó Flatpak, OnlyOffice, Chrome o Brave. Instala Flatpak, agrega Flathub y los portales del escritorio (para que los diálogos de abrir y guardar se vean como el resto del sistema), y luego las aplicaciones marcadas. Si agregar Flathub o descargar una aplicación falla por un corte de internet, espera a que la red vuelva y lo reintenta (hasta 3 veces).

**Si una aplicación de Flathub no se puede instalar en ese momento** (sin internet, o por ejemplo Google Chrome al instalar desde el instalador de Lázaro Linux: Chrome se descarga de la página de Google y ese paso no funciona dentro del sistema que se está instalando), queda anotada en `/etc/flatpak-pendientes`. En cada arranque, el servicio `local` la reintenta en segundo plano: una vez por minuto, hasta 20 veces. Cuando ya no queda ninguna pendiente, el reintento se borra solo. El resultado queda en `/var/log/flatpak-pendientes.log`.

### Bloque 33 — `setup_display_manager`
Habilita la pantalla de inicio de sesión que corresponde al escritorio: SDDM para Plasma, GDM para GNOME y LightDM para los demás. Si hay más de una instalada, avisa cuál eligió. Si no hay ninguna de esas tres pero está **greetd** (la que usan Sway y XFCE Wayland), habilita greetd.

- **Sway:** `setup-desktop` no le instala pantalla de inicio (hay que entrar por la consola y escribir `sway`). Si no hay otra pantalla de inicio instalada, el script le pone la misma que Alpine usa para XFCE Wayland: **greetd con gtkgreet**, liviana y sin Xorg. Para eso hace los mismos pasos que `setup-desktop`: `rc_need="seatd dbus"` en `/etc/conf.d/greetd`, agrega `dbus-run-session sway` a `/etc/greetd/environments` y suma el usuario `greetd` al grupo `seat`. Si ya hay otra pantalla de inicio (por ejemplo, Sway junto a XFCE), no agrega greetd.
- **Idioma de greetd** (`setup_greetd_idioma`): gtkgreet no lee la configuración de idioma del sistema, así que saldría en inglés. El script agrega el idioma (`env LANG=...`) a la línea de gtkgreet en `/etc/greetd/config.toml`.
- **Nombre del equipo primero** (`dm_tras_hostname`): agrega `rc_need="${rc_need:-} hostname"` al final de `/etc/conf.d/<pantalla de inicio>`. Si la pantalla de inicio arranca antes de que se ponga el nombre del equipo (pasa en el primer arranque), los programas que abre la sesión después (en MATE, el panel) no pueden conectarse a la pantalla ("Authorization required").

### Bloque 34 — `setup_greeter_resolution`
La pantalla de inicio usa la **resolución que el usuario eligió** en su escritorio. Sin esto, LightDM, SDDM y GDM arrancan siempre con la que sugiere el monitor, que no siempre es la correcta (máquinas virtuales, monitores externos).

- **Guardar:** en cada sesión corre `/usr/local/libexec/pantalla-inicio/guardar` (lo arranca `/etc/xdg/autostart/pantalla-inicio.desktop`). Anota la resolución en `~/.config/pantalla-inicio` cada vez que cambia. La lee con `xrandr` en XFCE, MATE y LXQt, y con `kscreen-doctor` en Plasma.
- **Aplicar con LightDM:** `/etc/lightdm/lightdm.conf.d/50-pantalla-inicio.conf` hace que LightDM ejecute `aplicar`, que pone con `xrandr` la resolución anotada más reciente.
- **Aplicar con SDDM:** `/etc/sddm.conf.d/50-pantalla-inicio.conf` hace lo mismo. Además deja la pantalla de inicio de SDDM **sobre Xorg**: en Plasma corre sobre Wayland, donde no hay un paso para aplicar la resolución. Como Plasma no trae Xorg, el script instala `xorg-server` y `xf86-input-libinput`; si no se pudieron instalar, SDDM se deja con su servidor de siempre (sin Xorg la pantalla de inicio no aparecería).
- **GDM:** GNOME guarda la resolución en `~/.config/monitors.xml`, el mismo formato que lee GDM. El servicio `pantalla-inicio-gdm` copia el más reciente para GDM al apagar y al arrancar, antes de GDM.

Si hay varios usuarios, gana la última sesión. La resolución nueva se aplica a partir del primer inicio de sesión hecho con ella. Sway y XFCE Wayland (greetd) quedan fuera: su pantalla de inicio no tiene un paso donde aplicarla.

### Bloque 35 — `setup_update_shortcut`
Crea el botón "Actualizar el sistema" (ver [la sección del botón](#el-botón-actualizar-el-sistema)). Funciona con dos scripts:

- `alpine-update-launcher.sh` corre como el usuario: pregunta por el cambio de versión, pide la contraseña con `pkexec` y muestra el avance con `zenity`.
- `alpine-update-root.sh` corre como administrador y solo hace el trabajo (`apk`, `flatpak`), sin ventanas.

Detalles de funcionamiento:

- **La ventana aparece después de la contraseña**, para no tapar el diálogo de `pkexec`.
- **Muestra una sola línea que se va reemplazando.** Para que la ventana se cierre bien al terminar se usa `tail --pid` de GNU coreutils (el `tail` de BusyBox no tiene esa opción), y `script` (de `util-linux-misc`) hace que `apk` muestre su avance línea por línea.
- **Agente de contraseña:** XFCE, MATE y Sway necesitan uno aparte (`polkit-gnome` en XFCE y Sway, `mate-polkit` en MATE). El lanzador comprueba que esté corriendo y, si no, lo inicia.
- **Aviso de reinicio:** el lanzador avisa si el kernel en uso ya no está instalado o si cambió la versión de Alpine.

### Bloque 36 — `setup_user_groups`
Agrega al usuario a los grupos `audio`, `video` y `lpadmin` (sonido, video y administración de impresoras).

### Bloque 37 — `fix_home_owner`
El script corre como administrador y crea algunos archivos en la carpeta del usuario (por ejemplo `~/.config`). En un sistema recién instalado, donde el usuario aún no entró nunca, esos archivos quedarían de `root` y el escritorio no podría guardar su configuración. Al final, los archivos de `root` dentro de la carpeta del usuario vuelven a su dueño.

### Bloque 38 — `main`
Ejecuta los bloques en orden. Termina con código 0 si todo salió bien y con código 3 si terminó pero faltaron descargas por la conexión (un instalador puede usarlo para programar otro intento).

## Archivos que crea o modifica

| Archivo | Bloque | Para qué |
|---|---|---|
| `/etc/X11/xorg.conf.d/00-keyboard.conf` | 9 | Teclado `latam` en Xorg |
| `/etc/xdg/plasma-workspace/env/teclado-latam.sh`, `/etc/profile.d/teclado-latam.sh` | 9 | `XKB_DEFAULT_LAYOUT=latam` para Wayland |
| `/etc/xdg/kxkbrc` | 9 | Teclado `latam` por defecto en Plasma |
| `/etc/xdg/xfce4/panel/default.xml` | 11 | Icono de volumen en el panel de XFCE (usuarios nuevos) |
| `/usr/share/glib-2.0/schemas/90-desktop-postinstall-teclado.gschema.override` | 9 | Teclado `latam` por defecto en GNOME |
| `/etc/sway/config.d/50-lazaro-barra.conf` | 11 | Sway: barra `waybar`, audio, WiFi, agente de contraseña y atajos Super+D y Super+F1 |
| `/usr/local/bin/sway-atajos` | 11 | Sway: lista de atajos de teclado |
| `~/.config/waybar/config.jsonc`, `/etc/skel/.config/waybar/config.jsonc` | 11 | Sway: botones y módulos de la barra (solo si no existía) |
| `/etc/modprobe.d/blacklist-nouveau.conf` | 16 | Bloqueo de `nouveau` (modo seguro) |
| `/etc/lightdm/lightdm.conf.d/40-nvidia-modo-seguro.conf` | 16 | LightDM abre aunque no haya pantalla del kernel (modo seguro) |
| `/etc/default/grub` (línea `GRUB_GFXPAYLOAD_LINUX=auto`, con un comentario que la marca) | 16 | GRUB arranca Linux en modo gráfico para que haya pantalla simple del kernel y SDDM abra (modo seguro) |
| `/etc/local.d/nvidia-optimus.start` | 16 | Modo ahorro: audio HDMI y salidas fantasma de la NVIDIA |
| `/etc/xdg/plasma-workspace/env/gpu-integrada.sh`, `/etc/profile.d/gpu-integrada.sh` | 16 | Modo ahorro: escritorio y video en la gráfica integrada |
| `/etc/X11/xorg.conf.d/20-gpu-integrada.conf` | 16 | Modo ahorro: Xorg no abre la NVIDIA |
| `/etc/conf.d/zram-init` | 19 | Configuración de zram |
| `/etc/sysctl.conf` | 19 | `vm.swappiness` y `vm.page-cluster` (se agregan líneas) |
| `/etc/udev/rules.d/60-ioscheduler.rules` | 22 | Planificador para discos mecánicos |
| `/etc/periodic/weekly/fstrim` | 23 | TRIM semanal de los SSD |
| `/etc/profile.d/idioma-sistema.sh`, `/etc/environment` | 28 | Idioma del sistema |
| `/etc/xdg/plasma-localerc`, `~/.config/plasma-localerc` | 28 | Idioma de Plasma (solo con Plasma) |
| `/etc/rc.conf` | 28 | Agrega `unicode="YES"` si falta |
| `/etc/flatpak-pendientes`, `/etc/local.d/flatpak-pendientes.start` | 32 | Aplicaciones de Flathub por reintentar en cada arranque (se borran solos al terminar) |
| `/var/log/flatpak-pendientes.log` | 32 | Registro de esos reintentos |
| `/etc/conf.d/<pantalla de inicio>` (`lightdm`, `sddm`, `gdm` o `greetd`) | 33 | Línea `rc_need` para arrancar después del nombre del equipo |
| `/etc/conf.d/greetd`, `/etc/greetd/environments` | 33 | Sway: pantalla de inicio greetd (`seatd`, `dbus` y la sesión `dbus-run-session sway`) |
| `/etc/greetd/config.toml` | 33 | Idioma de la pantalla de inicio greetd (se modifica la línea de gtkgreet) |
| `/usr/local/libexec/pantalla-inicio/` (`guardar`, `aplicar`, `sddm-xsetup`) | 34 | Resolución de la pantalla de inicio |
| `/etc/xdg/autostart/pantalla-inicio.desktop` | 34 | Arranca `guardar` en cada sesión (salvo GNOME) |
| `~/.config/pantalla-inicio` | 34 | Resolución anotada por `guardar` (lo escribe la sesión del usuario) |
| `/etc/lightdm/lightdm.conf.d/50-pantalla-inicio.conf` | 34 | LightDM aplica esa resolución |
| `/etc/sddm.conf.d/50-pantalla-inicio.conf` | 34 | SDDM aplica esa resolución y usa Xorg |
| `/etc/init.d/pantalla-inicio-gdm` | 34 | Servicio que copia `monitors.xml` a `/var/lib/gdm/.config/` |
| `/etc/xdg/mimeapps.list` | 31 | Aplicaciones predeterminadas |
| `/usr/local/bin/alpine-update-root.sh`, `/usr/local/bin/alpine-update-launcher.sh` | 35 | Botón de actualización |
| `/etc/periodic/hourly/alpine-update-revisar`, `/var/lib/alpine-update/` | 35 | Revisión periódica de actualizaciones |
| `/usr/local/bin/alpine-update-aviso`, `/etc/xdg/autostart/alpine-update-aviso.desktop` | 35 | Icono y notificación de actualizaciones (no en Plasma ni Sway) |
| `/usr/share/applications/alpine-update.desktop` | 35 | Entrada "Actualizar el sistema" en el menú |
| `/var/log/alpine-update.log` | 35 | Registro del botón |
| `/var/backups/alpine-update/` | 35 | Copias de `/etc/apk/repositories` antes de cada cambio de versión |
| `/var/log/desktop-postinstall.log` | todos | Registro del script |

## Servicios que habilita

En el arranque normal (`default`): `networkmanager`, `dbus`, `elogind`, `polkit`, `zram-init`, `earlyoom`, la pantalla de inicio que corresponda (`lightdm`, `sddm`, `gdm` o `greetd`), y según el caso:

- `bluetooth`, si hay adaptador Bluetooth;
- `cupsd`, si se marcaron las impresoras;
- `local`, en el modo de ahorro de NVIDIA o si quedó alguna aplicación de Flathub por reintentar;
- `pantalla-inicio-gdm`, con GDM (resolución de la pantalla de inicio);
- `spice-vdagentd`, en máquinas virtuales;
- `crond`, si hay un SSD (para el TRIM semanal);
- `acpid`, solo en sistemas sin escritorio.

`seatd` no se agrega al arranque: con greetd (Sway), OpenRC lo arranca antes de greetd porque el script lo pone como requisito en `/etc/conf.d/greetd`.

`udisks2`, `wpa_supplicant` y el servidor de audio no se habilitan como servicios: se activan solos cuando se necesitan o con cada sesión de usuario.

## Registro (log) y reejecución

Todo queda en `/var/log/desktop-postinstall.log` con cuatro niveles: `[INFO]` (paso en curso), `[OK]` (paso completado), `[WARN]` (algo falló, pero el script sigue) y `[ERROR]` (fallo grave que detiene el script). El registro se acumula entre ejecuciones.

La salida completa de `apk` (y de otros programas como `mkinitfs` y `flatpak`) va **solo al registro**. La pantalla muestra un resumen de cada paso y, mientras se instala, una línea por paquete y un aviso de "sigue trabajando" si algo tarda (ver Bloque 4). Si un paquete falla, el motivo exacto está en el registro.

El script se puede ejecutar varias veces sin hacer daño: instalar un paquete que ya está no hace nada, habilitar un servicio dos veces no lo duplica, y los archivos de configuración se reescriben completos. Sirve para cambiar una opción del menú o después de instalar otro escritorio.

**Si se cortó internet y no volvió**, el script no se detiene: termina lo que no necesita descargar, avisa cuántas descargas faltaron y sale con el código 3. Basta con volver a ejecutarlo con las mismas opciones cuando la conexión esté estable; lo ya instalado no se repite.

## Compatibilidad con futuras versiones de Alpine

Alpine publica una versión estable cada mayo y cada noviembre (3.21 en diciembre de 2024, 3.22 en mayo de 2025, 3.23 en diciembre de 2025, 3.24 en junio de 2026). El repositorio `main` recibe soporte unos dos años; **`community` solo hasta la siguiente versión**, unos seis meses. Casi todo lo que instala este script está en `community`, así que conviene cambiar de versión cada seis meses, o al menos una vez al año. El botón "Actualizar el sistema" lo ofrece cuando hay una versión nueva.

Revisión hecha en octubre de 2026 contra los repositorios reales de Alpine (versiones 3.22, 3.23, 3.24 y edge):

- **Todos los paquetes del script existen en las cuatro versiones.**
- **apk-tools 3** (desde 3.23) acepta todas las órdenes que usa el script y el botón.
- **/usr-merge** (convertir `/bin`, `/sbin` y `/lib` en enlaces a `/usr`): estaba previsto para 3.23, se pospuso, y será obligatorio en una versión futura (Alpine mencionó 3.26 o 3.27). El script no escribe en esas carpetas. Cuando llegue, conviene leer las notas de esa versión antes de usar el cambio de versión del botón.
- **Wayland:** en Alpine, Plasma solo tiene sesión Wayland desde 3.22 y GNOME desde 3.24; edge ya trae Plasma 6.8. Sway es solo Wayland. MATE y LXQt siguen en Xorg, y XFCE también, salvo su variante Wayland (con greetd). Por eso el teclado se configura en ambos.
- **PipeWire:** Alpine marcó como obsoleto su lanzador automático en favor de los servicios de usuario de OpenRC. El script detecta si falta y avisa.

## Limitaciones conocidas

- **NVIDIA con Xorg:** la corrección de la pantalla negra (ver [Historial](#historial-de-correcciones)) falta confirmarla en un equipo que arranque con Xorg. Si vuelve a ocurrir, entra a una consola de texto y revisa `dmesg | grep -i nouveau`, `lsmod | grep nouveau` y `/var/log/desktop-postinstall.log`.
- **Modo de ahorro de NVIDIA:** probado solo en un modelo (ASUS K53SV) con Plasma en Wayland. No se probó con XFCE, MATE o LXQt, ni la suspensión. Si algún puerto de video del portátil estuviera cableado a la NVIDIA, no daría imagen en este modo.
- **Modo seguro de NVIDIA:** deja la tarjeta sin driver, pero encendida. En un portátil Optimus conviene el modo de ahorro.
- **Cambio de versión de Alpine:** probado en una simulación, no todavía en un equipo real.
- **Montaje de USB:** depende de que `elogind` reconozca la sesión gráfica como activa. Si al montar pide la contraseña de root, el problema está ahí, no en los grupos del usuario.
- **Resolución de la pantalla de inicio:** no funciona con greetd (Sway, XFCE Wayland), que usa la resolución que sugiere el monitor. Con varios usuarios, la pantalla de inicio usa la resolución de la última sesión, sea de quien sea.
- **Escritorio:** el script no elige ni configura un escritorio por su cuenta: o ya está instalado, o se pide con `--escritorio`.
- **`--destino`:** la carpeta no puede tener espacios. Las aplicaciones de Flathub que no se pueden instalar dentro de un `chroot` (como Chrome) quedan para después del primer arranque.

## Solución de problemas

**El teclado sigue en inglés en la sesión gráfica.** Abre una vez la configuración de teclado del escritorio y confirma que aparece "latam" (XFCE, por ejemplo, guarda su propia configuración la primera vez). En Plasma, si alguna vez se eligió otra distribución, esa elección (`~/.config/kxkbrc`) manda sobre la del script.

**Pantalla negra al iniciar con NVIDIA.** Entra a una consola de texto (Ctrl+Alt+F2). Si existe `/etc/X11/xorg.conf.d/20-nouveau-safe.conf`, de una versión anterior del script, bórralo y reinicia. Si la NVIDIA quedó activa, vuelve a ejecutar el script y elige el modo seguro (o el de ahorro, en un portátil Optimus).

**En el modo de ahorro, la NVIDIA sigue encendida (`D0`).** Revisa que el servicio `local` haya arrancado (`rc-status default | grep local`), que `nouveau` esté cargado (`lspci -k`) y qué programas tienen abierta la NVIDIA.

**El cambio de versión quedó incompleto.** No reinicies. Conéctate a internet y vuelve a pulsar el botón, o ejecuta `doas apk upgrade --available` en una terminal. La versión anterior de los repositorios está en `/var/backups/alpine-update/`.

**Flatpak no se instaló.** Revisa que el repositorio `community` esté habilitado y que haya internet.

**Una aplicación de Flathub (OnlyOffice o Chrome) no aparece.** Si no se pudo instalar durante el script, se reintenta sola en cada arranque con internet. Revisa `/etc/flatpak-pendientes` (lo que falta) y `/var/log/flatpak-pendientes.log` (los intentos).

**La pantalla de inicio no usa la resolución que elegí.** Inicia sesión una vez con la resolución nueva y espera unos segundos antes de cerrarla o reiniciar: la pantalla de inicio la usa desde la próxima vez que aparezca.

**La instalación parece detenida.** Si `apk` pasa 2 minutos sin avanzar, el script lo corta y lo reintenta solo; en pantalla aparece el aviso. Si internet se cortó, el script espera hasta 3 minutos a que vuelva ("esperando a que vuelva internet..."). Si al final dice que faltaron descargas, revisa la conexión y vuelve a ejecutar el script con las mismas opciones.

**Las memorias USB no se montan solas.** Comprueba que `elogind` y `polkit` estén corriendo (`rc-service elogind status`, `rc-service polkit status`) y que hayas reiniciado después de ejecutar el script.

## Cómo revertir cambios

| Para quitar... | Hacer esto |
|---|---|
| Modo seguro de NVIDIA | Volver a ejecutar el script eligiendo otro modo. A mano: borrar `/etc/modprobe.d/blacklist-nouveau.conf`, `/etc/lightdm/lightdm.conf.d/40-nvidia-modo-seguro.conf` y, en `/etc/default/grub`, el comentario del modo seguro y la línea `GRUB_GFXPAYLOAD_LINUX=auto`; ejecutar `mkinitfs $(uname -r)` y `grub-mkconfig -o /boot/grub/grub.cfg`, y reiniciar |
| Modo de ahorro de NVIDIA | Borrar `/etc/local.d/nvidia-optimus.start`, los dos `gpu-integrada.sh` y `/etc/X11/xorg.conf.d/20-gpu-integrada.conf`; reiniciar |
| Teclado latam en Wayland | Borrar los dos `teclado-latam.sh`, `/etc/xdg/kxkbrc` y el esquema de GNOME; ejecutar `glib-compile-schemas /usr/share/glib-2.0/schemas` |
| Idioma | Borrar `/etc/profile.d/idioma-sistema.sh` (o `lang-es.sh` en versiones anteriores), las líneas `LANG`/`LC_*` de `/etc/environment` y, con Plasma, los dos `plasma-localerc` |
| Un cambio de versión de Alpine | Solo es seguro si `apk upgrade --available` todavía no se ejecutó: copiar el respaldo de `/var/backups/alpine-update/` sobre `/etc/apk/repositories` y ejecutar `doas apk update` |
| zram | `rc-service zram-init stop`, `rc-update del zram-init` y borrar `/etc/conf.d/zram-init` |
| EarlyOOM | `rc-update del earlyoom` y `apk del earlyoom earlyoom-openrc` |
| Impresoras | `rc-update del cupsd` y `apk del cups cups-filters system-config-printer` |
| Planificador de discos | Borrar `/etc/udev/rules.d/60-ioscheduler.rules` y reiniciar |
| TRIM semanal | Borrar `/etc/periodic/weekly/fstrim` |
| Barra de Sway | Borrar `/etc/sway/config.d/50-lazaro-barra.conf` (vuelve la barra original) y, si se quiere, `~/.config/waybar/config.jsonc` y `/usr/local/bin/sway-atajos` |
| Pantalla de inicio greetd (Sway) | `rc-update del greetd` y `apk del greetd-gtkgreet`; se vuelve a entrar por la consola escribiendo `sway` |
| Resolución de la pantalla de inicio | Borrar `/usr/local/libexec/pantalla-inicio/`, `/etc/xdg/autostart/pantalla-inicio.desktop` y los dos `50-pantalla-inicio.conf` (con eso SDDM vuelve también a su servidor de siempre); con GDM, además, `rc-update del pantalla-inicio-gdm` y borrar `/etc/init.d/pantalla-inicio-gdm` |
| YouTube ligero | `apk del pipe-viewer pipe-viewer-gtk yt-dlp yt-dlp-ejs-rt-quickjs`, y borrar `/usr/share/applications/lazaro-youtube.desktop` y `/usr/local/share/applications/gtk-pipe-viewer.desktop`. Si no tenías configuración propia antes, borrar también `/etc/yt-dlp.conf`, `~/.config/pipe-viewer/` y `/etc/skel/.config/pipe-viewer/` (el script no toca archivos que ya existían). `/etc/mpv/mpv.conf` puede quedarse (sirve para mpv en general) |
| Reintentos de Flathub | Borrar `/etc/flatpak-pendientes` y `/etc/local.d/flatpak-pendientes.start` |

## Historial de correcciones

Cambios importantes respecto a versiones anteriores del script, para quien venga de una de ellas:

- **Volumen en XFCE:** el plugin de volumen se instalaba pero no aparecía en el panel; ahora se agrega al panel de los usuarios nuevos.
- **Avance visible:** durante las instalaciones la pantalla muestra cada paquete y avisa "sigue trabajando" cuando algo tarda, en vez de quedarse quieta hasta el OK final.
- **Opciones y cortes de internet:** el script acepta opciones (`--full`, `--minimo`, `--con`, `--destino`...) para usarse sin menú; Fastfetch, Btop y VLC pasaron a ser opciones del script (antes los instalaba aparte el instalador de Lázaro Linux, y VLC quedaba sin ventana porque faltaba `vlc-qt`); `apk` y Flatpak reintentan cuando una descarga falla por la red; y los bloques del archivo quedaron en el orden en que se ejecutan (la numeración cambió).
- **Revisión general:** el firmware de Bluetooth y de WiFi ya no se instala si no hay adaptador; greetd se reconoce como pantalla de inicio; la salida de `apk` va al registro en vez de a la pantalla; y `apk_vigilado` corta y reintenta (hasta 3 veces) las descargas que pasan 2 minutos sin avanzar, que antes podían dejar el script detenido indefinidamente (ver Bloque 4).
- **Modo seguro de NVIDIA:** escribía `20-nouveau-safe.conf`, que pedía a Xorg usar el driver `nouveau` sin decir en qué tarjeta. Con el módulo bloqueado ese driver no funciona, y en un portátil híbrido Xorg lo aplicaba a la Intel: causa probable de la pantalla negra. Ya no se crea, y se borra si existe.
- **`acpid`:** se habilitaba siempre; ahora solo sin escritorio (ver Bloque 21).
- **Audio:** se forzaba PulseAudio; ahora se respeta el servidor que ya tenga el sistema (ver Bloque 11).
- **Teclado:** solo se configuraba para Xorg; ahora también para Wayland (ver Bloque 9).
- **`lsusb`:** el script daba por bueno el `lsusb` reducido de BusyBox y la detección por USB podía fallar en silencio; ahora instala `usbutils`.
- **Paquetes:** se quitó `mesa-vulkan-radeon`, que no existe y hacía fallar la instalación en equipos AMD; `p7zip` y `ttf-dejavu` se cambiaron por sus nombres actuales, `7zip` y `font-dejavu`.
- **Microcódigo AMD:** una versión decía que `amd-ucode` no existía; sí existe y se instala.
- **SSD:** no había TRIM periódico; ahora se programa uno semanal si hay un SSD.
- **Botón de actualización:** varios diseños anteriores de la ventana se quedaban congelados o no se cerraban; el actual usa `tail --pid`. El registro no se guardaba porque el usuario no podía escribir en `/var/log`; ahora el archivo pertenece al grupo `wheel`.
