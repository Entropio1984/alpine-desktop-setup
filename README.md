# desktop-postinstall.sh — Script de post-instalación de escritorio para Alpine Linux

Script de shell POSIX (`ash`, compatible con BusyBox) que automatiza la configuración de un entorno de escritorio recién instalado en Alpine Linux: red, audio, idioma, controladores de video, energía, impresión, ofimática y estabilidad general del sistema. Está pensado especialmente para revivir equipos antiguos o con recursos limitados (2-8 GB de RAM), pero funciona igual de bien en hardware moderno.

Detecta automáticamente qué tiene tu sistema (entorno de escritorio, GPU, CPU) y adapta lo que instala en consecuencia, en vez de asumir una configuración fija.

> ⚠️ **Problema conocido sin resolver — GPU NVIDIA.** En las pruebas realizadas hasta ahora, el modo seguro del Bloque 12 (bloqueo de `nouveau` vía Xorg + `/etc/modprobe.d`) **no ha sido suficiente en todos los casos**: tras reiniciar, el equipo puede seguir mostrando pantalla negra en hardware con tarjeta NVIDIA. Esto sigue bajo investigación y **no debe darse por resuelto** solo por haber respondido "sí" a la pregunta del Bloque 12. Ver la sección [Limitaciones conocidas](#limitaciones-conocidas) para más detalle.

---

## Tabla de contenidos

1. [Requisitos previos](#requisitos-previos)
2. [Cómo ejecutarlo](#cómo-ejecutarlo)
3. [Filosofía del script](#filosofía-del-script)
4. [Recorrido bloque por bloque](#recorrido-bloque-por-bloque)
5. [Menú de opciones al inicio](#menú-de-opciones-al-inicio)
6. [Archivos que el script crea o modifica](#archivos-que-el-script-crea-o-modifica)
7. [Servicios OpenRC habilitados](#servicios-openrc-habilitados)
8. [Registro de ejecución (log)](#registro-de-ejecución-log)
9. [Reejecución / idempotencia](#reejecución--idempotencia)
10. [Limitaciones conocidas](#limitaciones-conocidas)
11. [Solución de problemas](#solución-de-problemas)
12. [Cómo revertir cambios específicos](#cómo-revertir-cambios-específicos)

---

## Requisitos previos

- Alpine Linux ya instalado (`setup-alpine` ejecutado).
- Un entorno de escritorio ya instalado mediante `setup-desktop` (XFCE, KDE Plasma, GNOME, MATE o LXQt) — el script **no instala el entorno de escritorio en sí**, solo lo complementa y corrige detalles que Alpine deja sin configurar por defecto.
- Repositorios `main` **y** `community` habilitados en `/etc/apk/repositories` (varios paquetes que el script instala, como `flatpak`, `libreoffice` o `earlyoom`, viven en `community`).
- Conexión a internet activa.
- Acceso como `root` (directamente o vía `doas`).

Puedes verificar los repositorios con:

```sh
grep -v '^#' /etc/apk/repositories
```

## Cómo ejecutarlo

```sh
doas sh desktop-postinstall.sh
```

o, si ya estás en una sesión root:

```sh
sh desktop-postinstall.sh
```

Al empezar, el script muestra **un menú de casillas** con todas las decisiones opcionales (ver [sección 5](#menú-de-opciones-al-inicio)). Después de confirmar, corre solo de principio a fin, sin más preguntas. Al finalizar, **reinicia el sistema** — varios cambios (bloqueo de módulos de kernel, servicios recién habilitados, variables de idioma) no toman efecto por completo hasta el próximo arranque.

## Filosofía del script

Tres principios guían todas las decisiones de diseño:

- **Detectar antes de asumir.** El script nunca asume qué entorno de escritorio, GPU o CPU tienes — los detecta con `apk info -e`, `lspci` y `/proc/cpuinfo`, y adapta cada bloque al resultado real.
- **Nunca abortar por un paquete faltante.** Cada instalación pasa por la función `install_pkg()`, que registra un `WARN` y continúa si un paquete no existe en tu rama/arquitectura, en vez de detener todo el script (`set -e` sigue activo para errores verdaderamente graves, como quedarte sin permisos de root).
- **Honestidad sobre las limitaciones de Alpine.** Cuando algo no tiene una solución limpia en Alpine (por ejemplo, `unrar` no está empaquetado por ser de licencia no-libre, o el microcódigo de AMD no tiene paquete dedicado), el script lo dice explícitamente en el log en vez de fingir que lo resolvió.

## Recorrido bloque por bloque

El script se organiza en 30 bloques. `main()` los ejecuta casi en el orden del archivo, con una excepción deliberada: `detect_hardware` (Bloque 11) y el menú de opciones (Bloque 29) corren **al principio**, justo después de actualizar los repositorios, para que todas las decisiones se tomen antes de empezar a instalar.

### Bloque 1 — `check_root`
Verifica que el script corre como `root` (`id -u` = 0). Si no, aborta con un mensaje claro.

### Bloque 2 — `update_system` / `install_pkg` / `install_pkgs`
`update_system` corre `apk update` una sola vez al principio. `install_pkg` instala **un** paquete con tolerancia a fallos (usado cuando el nombre del paquete depende de hardware detectado y no se quiere arriesgar una transacción en lote). `install_pkgs` instala **varios** paquetes en una sola transacción de `apk` (mucho más rápido: una sola resolución de dependencias en vez de una por paquete) — si la transacción en lote falla porque algún nombre no existe en tu rama/arquitectura, cae automáticamente a instalar cada paquete por separado con `install_pkg`, así se gana velocidad en el caso normal sin perder la tolerancia a fallos individuales en el caso excepcional.

### Bloque 3 — `setup_keyboard_layout`
**Depende de una casilla del menú inicial** (ver sección 5) si se desea configurar el teclado a distribución latam — no es una preferencia universal, así que no se aplica sin confirmar. Si se acepta, lo hace en dos capas independientes:
- **Consola (TTY):** `setup-keymap latam latam`, ejecutado de forma no interactiva. El único prompt que sobrevive es la confirmación de OpenRC al reiniciar el servicio `loadkmap` ("you are stopping a boot service"), que se responde automáticamente vía `yes |`.
- **Sesión gráfica (Xorg):** crea `/etc/X11/xorg.conf.d/00-keyboard.conf` con `Option "XkbLayout" "latam"`, para que XFCE, Plasma, GNOME, MATE o LXQt también arranquen en ese layout (la consola y Xorg son capas separadas; una no implica la otra).

### Bloque 4 — `detect_desktop_environment`
Pregunta a `apk` (no a variables de entorno, que no existen en una shell root fuera de sesión gráfica) qué entornos están instalados: `xfce4-session`, `plasma-desktop-meta`/`plasma-desktop`, `gnome-shell`, `mate-session-manager`, `lxqt-session`. Guarda el resultado en las variables `DE_XFCE`, `DE_PLASMA`, `DE_GNOME`, `DE_MATE`, `DE_LXQT` (cada una `"yes"`/`"no"`), que usan todos los bloques posteriores para decidir qué instalar. Si tienes más de un entorno instalado simultáneamente, el script configura ambos sin conflicto.

### Bloque 5 — `detect_target_user`
Identifica al usuario real del sistema (no root) para poder aplicarle configuración de idioma y grupos más adelante. Usa `$DOAS_USER` (Alpine usa `doas`, no `sudo`) con `logname` como respaldo, y resuelve su directorio home vía `getent passwd`. Si no logra determinar un usuario, los bloques que lo necesitan simplemente avisan y continúan sin fallar.

### Bloque 6 — `setup_applets`
Instala la base de red/audio (`networkmanager`, `wpa_supplicant`, `pulseaudio`) siempre, sin importar el entorno gráfico. Luego, según las banderas `DE_*` detectadas en el Bloque 4, instala el "applet" nativo correspondiente:

| Entorno | WiFi | Volumen |
|---|---|---|
| XFCE | `network-manager-applet` | `xfce4-pulseaudio-plugin` |
| Plasma | `plasma-nm` | `plasma-pa` |
| GNOME | (incrustado en el shell) | `pavucontrol` (mezclador avanzado) |
| MATE | `network-manager-applet` | `mate-media` |
| LXQt | `network-manager-applet` | `pavucontrol-qt` (mezclador; el widget de bandeja ya viene en `lxqt-panel`) |

`wpa_supplicant` y `pulseaudio` **no** se registran como servicios OpenRC de arranque: `wpa_supplicant` lo invoca NetworkManager internamente vía D-Bus, y PulseAudio se gestiona por sesión de usuario en cada entorno, no como demonio de sistema.

### Bloque 7 — `detect_wifi_hardware`
Detecta adaptadores de red inalámbrica tanto por **PCI** (`lspci`, clase "Network controller"/"Wireless") como por **USB** (`lsusb`, instalando `usbutils` si falta). Es importante cubrir ambos: un adaptador WiFi conectado como dongle externo **no aparece en `lspci`**, solo en `lsusb`. El resultado combinado se guarda en `$WIFI_INFO` para que el bloque siguiente lo use.

### Bloque 8 — `install_wifi_firmware`
Busca palabras clave de fabricante (Intel, Realtek, Atheros/Qualcomm, MediaTek/Ralink, Marvell, Broadcom) en `$WIFI_INFO` e instala el/los subpaquete(s) de firmware correspondientes (Alpine divide el firmware en decenas de subpaquetes por fabricante: `linux-firmware-intel`, `linux-firmware-realtek`, `linux-firmware-ath9k_htc`, etc.). En una instalación normal de Alpine ya están todos presentes (ver la nota del Bloque 12), así que este paso solo marca la diferencia en sistemas adelgazados. Si no se identifica el fabricante por nombre, instala un conjunto amplio como red de seguridad en vez de no instalar nada.

> **Sobre el filtro de `lsusb`:** la primera versión de este bloque capturaba la salida completa de `lsusb` sin filtrar, lo que causaba falsos positivos — una cámara web Realtek, un teclado con chip MediaTek, o el hub USB interno de la placa (a menudo Intel) hacían que el script instalara firmware WiFi innecesario. Se corrigió filtrando por frases específicas de adaptador de red (`802.11`, `WLAN`, `Wi-Fi`, `wireless network`, `network adapter`) en vez de palabras sueltas como "wireless" o "adapter", que son demasiado amplias.

### Bloque 9 — `detect_bluetooth_hardware`
Detecta adaptadores Bluetooth por **PCI** y **USB** (`lsusb`, ya que la inmensa mayoría de adaptadores Bluetooth en laptops están cableados internamente por USB, a menudo combinados con el chip WiFi en el mismo controlador físico). El resultado se guarda en `$BT_INFO`.

### Bloque 10 — `install_bluetooth`
Instala `bluez` + `bluez-openrc` + `pulseaudio-bluez` y habilita el servicio `bluetooth`. **`pulseaudio-bluez` es el eslabón que suele faltar:** sin él, `bluez` permite emparejar audífonos o altavoces Bluetooth, pero PulseAudio no tiene el módulo necesario para enrutar el perfil A2DP — el dispositivo se empareja pero no emite sonido. Si `$BT_INFO` identificó un fabricante, instala también el firmware Bluetooth correspondiente — **importante:** no existe un paquete genérico `linux-firmware-bluetooth` en Alpine; el firmware de Bluetooth está fragmentado por fabricante igual que el de WiFi (`linux-firmware-rtl_bt` para Realtek, `linux-firmware-ar3k` para Atheros/Qualcomm; Broadcom e Intel reutilizan `linux-firmware-brcm`/`linux-firmware-intel`, que ya cubren el combo WiFi+Bluetooth). Si no se detectó ningún adaptador Bluetooth, el bloque no instala nada (evita dejar `bluez` corriendo sin hardware que gestionar).

### Bloque 11 — `detect_hardware`
Ejecuta `lspci` y clasifica **todos** los adaptadores de video presentes en banderas independientes: `GPU_HAS_INTEL`, `GPU_HAS_AMD`, `GPU_HAS_NVIDIA`, `GPU_HAS_VIRTUAL` (más `GPU_COUNT` con el total). Esto es deliberado: en un laptop con gráficos híbridos (Optimus, Intel+NVIDIA) `lspci` devuelve más de una línea, y el script necesita saber de **todas** las GPU presentes, no solo la primera que coincida.

También revisa `lsusb` en busca de adaptadores de video **DisplayLink** (docks USB para múltiples monitores, invisibles para `lspci`). Solo se registra una advertencia informativa — **no se intenta instalar nada automáticamente**, porque el driver que necesitan (`evdi`) no está empaquetado en Alpine (solo existe vía DKMS en otras distros) y, aun así, `evdi` por sí solo no es un driver completo: DisplayLink exige además su propio userspace binario cerrado, no distribuible por un gestor de paquetes.

### Bloque 12 — `install_drivers`
Instala controladores según las banderas del Bloque 11 (puede instalar más de un fabricante a la vez, si el hardware es híbrido):
- **Intel:** `linux-firmware-i915`, `mesa-vulkan-intel`.
- **AMD:** `linux-firmware-amdgpu`/`radeon`, `mesa-vulkan-ati`/`radeon`, `vulkan-loader`.
- **Virtual (QEMU/VMware/VirtualBox):** drivers `xf86-video-*` + `spice-vdagent`.
- **NVIDIA:** `linux-firmware-nvidia` (driver abierto `nouveau`). El modo seguro se elige con una casilla del menú inicial, que solo aparece si se detectó una NVIDIA (ver [sección 5](#menú-de-opciones-al-inicio)) — importante en tarjetas antiguas (Tesla/Fermi/Kepler), donde `nouveau` puede colgar el arranque incluso si hay una GPU integrada de respaldo.

Si no se detecta ninguna GPU reconocida, `mesa-dri-gallium` ya deja software rendering (`llvmpipe`) como respaldo funcional.

> **Sobre el firmware (corrección):** una versión anterior de esta nota daba a entender que el script mantenía el sistema liviano al no instalar el metapaquete `linux-firmware` (que depende de todos los subpaquetes de fabricante). Pero la [documentación oficial de Alpine](https://wiki.alpinelinux.org/wiki/Kernels) indica que ese metapaquete **ya viene incluido en la instalación por defecto**. Por lo tanto, en un sistema recién instalado, los subpaquetes de firmware que piden los Bloques 8, 10 y 12 ya están presentes y `apk add` no hace nada con ellos: no cuesta nada, pero tampoco aporta. Solo marcan la diferencia en un sistema adelgazado con `linux-firmware-none`, donde falta todo el firmware y el script agrega únicamente el del hardware detectado. El script no intenta adelgazar el sistema por su cuenta: quitar firmware a ciegas podría dejar sin WiFi o sin video un equipo que hoy funciona.

### Bloque 13 — `check_unclaimed_devices`
Cierra el ciclo de los bloques de firmware anteriores preguntando algo distinto: **¿quedó algún dispositivo sin ningún controlador del kernel enlazado?** Usa `lspci -k`, que añade una línea `Kernel driver in use:` a cada dispositivo que sí tiene driver; los que no la tienen se reportan (filtrando a clases de red, video y audio — muchos dispositivos como los *host bridges* legítimamente no llevan driver, y eso es normal). Un dispositivo de red o video sin driver es exactamente el síntoma de hardware que solo funciona con controladores propietarios o fuera del árbol del kernel.

En Alpine hay **dos caminos distintos y no intercambiables** para esos casos, y el bloque los explica en el log:

| Tipo | Ejemplos | Mecanismo |
|---|---|---|
| Módulo de **kernel** | NVIDIA `.ko`, Broadcom `wl`, varios Realtek USB | **AKMS** (Alpine Kernel Module Support) — el equivalente oficial de DKMS: compila el módulo desde fuente y lo **reconstruye solo** en cada actualización de kernel. Alpine empaqueta varios como `*-src` (`rtl8812au-src`, `rtl88x2bu-src`, `rtw89-src`…), casi todos en el repositorio `testing` |
| Binario de **espacio de usuario** (glibc) | Plugins de impresora, DRM Widevine | **`gcompat`** — capa de compatibilidad glibc sobre musl. **No** sirve para módulos de kernel |

Instalar `gcompat` depende de una casilla del menú inicial (ver sección 5), pero **no instala módulos propietarios ni habilita `testing` por su cuenta**: habilitar un repositorio inestable a nivel de sistema puede arrastrar paquetes rotos al resto de la instalación, y compilar un módulo equivocado puede dejar el equipo sin red o sin video. Reporta el diagnóstico con los comandos exactos y deja la decisión al usuario.

> **Sobre NVIDIA:** los drivers propietarios de NVIDIA no están disponibles en Alpine por la incompatibilidad con musl libc — AKMS no cambia eso. Para GPU NVIDIA la única vía sigue siendo `nouveau` (ver Bloque 12).

### Bloque 14 — `detect_cpu` / `install_microcode`
Lee `/proc/cpuinfo` para clasificar el fabricante (`GenuineIntel`/`AuthenticAMD`). Instala `intel-ucode` o `amd-ucode` según el caso. Con syslinux (extlinux) o GRUB, el paquete **agrega solo** su imagen de microcódigo a la línea `INITRD` del cargador de arranque, así que basta con reiniciar; se puede verificar con `dmesg | grep -i microcode`. Alpine no instala el microcódigo por defecto: es la única pieza específica del fabricante de la CPU que falta tras la instalación, porque el resto (control de frecuencia, sensores de temperatura, virtualización) ya viene dentro del kernel genérico y se activa solo.

> **Corrección:** una versión anterior de este bloque afirmaba que `amd-ucode` no existía en Alpine e instalaba `linux-firmware-amd` en su lugar, y advertía que el microcódigo podía requerir integración manual en el arranque. Ambas afirmaciones venían de información desactualizada; la [wiki oficial de Alpine](https://wiki.alpinelinux.org/wiki/CPU_Microcode) documenta `amd-ucode` y la integración automática.

También detecta el **nivel de microarquitectura x86-64** (v1 a v4) a partir de los *flags* de `/proc/cpuinfo` — el método habitual (`/lib/ld-linux-x86-64.so.2 --help`) es propio de glibc y no existe en musl. **Es un dato solo informativo:** la optimización por nivel que hacen distribuciones como CachyOS ocurre al *compilar* los paquetes, no después de instalarlos, y Alpine distribuye un único juego de paquetes x86_64 para el nivel base. Saber el nivel sirve para entender qué rendimiento esperar, no cambia nada de lo que se instala.

| Nivel | Requisitos clave | CPUs típicas |
|---|---|---|
| v1 | SSE2 (base de x86-64) | Athlon 64, Core 2 tempranos |
| v2 | SSE4.2, POPCNT, SSSE3 | Nehalem, Sandy/Ivy Bridge, Bulldozer (~2008–2012) |
| v3 | AVX2, FMA, BMI1/2 | Haswell (2013) en adelante, Zen |
| v4 | AVX-512 | Skylake-X, Zen 4/5 |

> Dato relevante para hardware antiguo: los repositorios optimizados de CachyOS existen solo para v3, v4 y Zen 4; en CPUs v2 (como un Core i3 M 370 o un i7-2630QM), CachyOS instala sus paquetes genéricos. Es decir, en esa clase de equipos la ventaja de CachyOS por nivel de CPU no aplica, y Alpine no pierde nada en ese aspecto.

### Bloque 15 — `setup_zram`
Calcula la RAM física total (`/proc/meminfo`) y configura `zram-init` con un dispositivo swap comprimido (algoritmo `zstd`) de tamaño igual al 100% de esa RAM. Ajusta también `vm.swappiness=100` y `vm.page-cluster=0` en `/etc/sysctl.conf` (valores recomendados para swap sobre zram). Pensado para exprimir el máximo de memoria efectiva en equipos con poca RAM física.

### Bloque 16 — `setup_earlyoom`
Instala `earlyoom` (+ su subpaquete `earlyoom-openrc`, necesario para que exista el script de arranque) y lo habilita. `earlyoom` monitorea la memoria en segundo plano y cierra el proceso responsable (ej. una pestaña de Chrome) segundos antes de que el sistema se quede sin memoria y se congele por completo.

### Bloque 17 — `setup_power`
Instala y habilita `acpid` (+ `acpid-openrc`), para que Alpine reaccione a eventos físicos: cerrar la tapa de un laptop, presionar el botón de encendido, etc.

### Bloque 18 — `optimize_hdd_storage`
Recorre `/sys/block/*/queue/rotational` para identificar discos **mecánicos** (excluyendo `loop`/`ram`/`zram`). Si encuentra alguno, configura el planificador de E/S vía una regla `udev` persistente (`/etc/udev/rules.d/60-ioscheduler.rules`): prioriza **BFQ** (diseñado para que un proceso con mucha carga de E/S no congele el resto del escritorio — la misma filosofía que `earlyoom` aplica a la memoria), verificando en tiempo de ejecución si el kernel actual lo tiene disponible y cayendo a `mq-deadline` si no.

La regla de `udev` filtra **por atributo físico** (`rotational==1`), no por nombre de disco — esto es clave en configuraciones mixtas (ej. sistema instalado en SSD con un HDD auxiliar solo para datos): el SSD nunca recibe esta regla sin importar qué letra de disco (`sda`/`sdb`) le toque en un arranque dado, ya que el orden de asignación no está garantizado entre reinicios. El bloque también identifica cuál disco es la raíz del sistema (usando `mount`, sin depender de `findmnt`/`lsblk` para no sumar una dependencia nueva) y ajusta la sugerencia de `noatime` en consecuencia: si el disco mecánico detectado **no** es la raíz (es un disco de datos auxiliar), la sugerencia es más directa, ya que modificar `/etc/fstab` para una partición no-raíz tiene mucho menor riesgo que tocar la partición de arranque.

**No modifica `/etc/fstab`** automáticamente en ningún caso — es un archivo crítico para el arranque y se deja como sugerencia manual en el log, no como cambio automático.

### Bloque 19 — `setup_usb_automount`
Configura el montaje automático de memorias USB al conectarlas. Es el bloque con más piezas coordinadas:
1. **`dbus`** (+ servicio `dbus`) — instalado primero porque todo lo demás en este bloque depende del bus de mensajes del sistema.
2. **`udisks2`** — hace el montaje real. No tiene servicio OpenRC propio: se activa bajo demanda vía D-Bus.
3. **`elogind` + `polkit-elogind`** (servicios `elogind` y `polkit`, nombres distintos a los paquetes) — autorización para que un usuario normal (no root) pueda montar sin contraseña, basada en detección de **sesión activa** (no en pertenencia a grupos Unix — ver [Limitaciones conocidas](#limitaciones-conocidas)).
4. **Disparador según entorno:** `gvfs` + `thunar-volman` para XFCE; `gvfs` para GNOME/MATE; `gvfs` + `lxqt-policykit` para LXQt. Plasma no necesita nada adicional aquí porque Dolphin usa KIO/Solid + `udisks2` directamente.

### Bloque 20 — `setup_printing`
**Depende de una casilla del menú inicial** (ver sección 5) si se desea soporte de impresión — no todo equipo "revivido" tiene o necesita una impresora. Si se acepta, instala `cups` + `cups-openrc` + `cups-filters` + `system-config-printer`, habilita el servicio `cupsd`, y deja la interfaz web de CUPS disponible en `http://localhost:631`.

### Bloque 21 — `install_archive_tools`
Instala `zip`, `unzip`, `p7zip`. **`unrar` no se instala porque no existe como paquete en Alpine** (licencia no-libre, verificado en v3.24) — el script lo indica explícitamente en el log en vez de intentarlo y fallar en silencio, y apunta al binario oficial de `rarlab.com/download.htm` como única vía si de verdad se necesita soporte RAR (no automatizado por el script: cada versión de RARLAB cambia el nombre del archivo, y una URL fija quedaría rota con el tiempo).

### Bloque 22 — `setup_locale_es`
Configura español en tres capas independientes, porque ningún mecanismo por sí solo cubre todos los casos:
1. **`/etc/profile.d/lang-es.sh`** — variables `LANG`/`LC_ALL`/`LC_MESSAGES=es_ES.UTF-8` para shells de login tradicionales.
2. **`/etc/environment`** — las mismas variables, leídas por PAM (`pam_env`) en la mayoría de gestores de sesión gráficos (SDDM incluido), que no siempre pasan por `/etc/profile.d`.
3. **`plasma-localerc`** (solo si se detecta Plasma) — Plasma tiene su **propio** mecanismo de idioma, separado del `LANG` del sistema, con dos secciones distintas: `[Formats]` (números/fecha) y `[Translations]` (idioma real de la interfaz). Se escribe tanto en `/etc/xdg/plasma-localerc` (default para usuarios nuevos) como en `$HOME/.config/plasma-localerc` del usuario detectado en el Bloque 5.

También instala `musl-locales`/`musl-locales-lang` y el metapaquete `lang`, que dispara automáticamente (vía `install_if` de `apk`) los subpaquetes `-lang` de todo el software ya instalado en el sistema (XFCE, GTK, Plasma, NetworkManager applet, etc.), sin necesidad de listar cada paquete a mano.

> **Nota:** musl (la libc de Alpine) no tiene un locale `es_MX.UTF-8` — solo un conjunto reducido, entre ellos `es_ES.UTF-8`, que es el que usa el script. Para la traducción de interfaz esto no supone ninguna diferencia práctica (los paquetes de idioma no distinguen variantes regionales de español).

### Bloque 23 — `install_fonts`
Instala `ttf-dejavu`, `font-liberation` + `font-liberation-sans-narrow` (métricamente compatibles con Arial/Times/Courier — importante para abrir `.docx` sin que el texto se desborde) y `font-noto`. Se ejecuta antes de LibreOffice a propósito.

### Bloque 24 — `install_libreoffice`
**Depende de una casilla del menú inicial** (ver sección 5) — es de los paquetes más pesados del script, y quien prefiera OnlyOffice vía Flatpak puede omitirlo aquí. Si se acepta, instala `libreoffice` + `libreoffice-lang-es`.

### Bloque 25 — `setup_flatpak`
**Depende de una casilla del menú inicial** (ver sección 5) si se desea habilitar Flatpak/Flathub en absoluto — si no se marca, no se instala nada de infraestructura (`flatpak`, portales XDG). Marcar OnlyOffice o Chrome en el menú activa Flatpak automáticamente. Si se acepta: instala Flatpak y agrega el repositorio Flathub, instala `xdg-desktop-portal` + `xdg-desktop-portal-gtk` como base universal, y además el portal nativo correspondiente si se detecta Plasma (`xdg-desktop-portal-kde`) o LXQt (`xdg-desktop-portal-lxqt`) — así los diálogos de "Abrir/Guardar" de apps en sandbox (Chrome, OnlyOffice) se ven coherentes con el entorno en vez de forzar siempre estética GTK. Luego instala OnlyOffice y/o Google Chrome desde Flathub, según las casillas marcadas.

### Bloque 26 — `setup_display_manager`
Habilita el gestor de inicio de sesión gráfico (`lightdm`/`sddm`/`gdm`) en el runlevel `default`. No basta con que `setup-desktop` lo haya instalado — hay casos reales donde el DM queda instalado pero no correctamente enganchado al arranque. En vez de una prioridad fija (que podría elegir el DM equivocado en equipos con más de un entorno instalado, como XFCE + Plasma a la vez), reutiliza las banderas `DE_*` del Bloque 4 para preferir el emparejamiento convencional — el mismo que usa el propio `setup-desktop` de Alpine internamente: Plasma → `sddm`, GNOME → `gdm`, cualquier otro (XFCE/MATE/LXQt) → `lightdm` si está instalado. Si hay más de un DM instalado, se advierte explícitamente cuál se eligió y por qué.

### Bloque 27 — `setup_update_shortcut`
**Depende de una casilla del menú inicial** (ver sección 5) si se desea un botón en el menú de aplicaciones para actualizar el sistema (Alpine vía `apk` y Flatpak, si está instalado) con un clic. Usa dos piezas del ecosistema freedesktop.org que hacen esto trivialmente multi-entorno:

- **Un único archivo `.desktop`** en `/usr/share/applications/` — el estándar XDG que XFCE, Plasma, GNOME, MATE y LXQt leen por igual, así que el botón aparece en el menú de **todos** los entornos detectados sin lógica separada por DE.
- **`pkexec`** (parte de `polkit-elogind`, ya instalado en el Bloque 19) para pedir autenticación. Por defecto, sin ninguna regla de polkit adicional, si el usuario pertenece al grupo `wheel` (se agrega automáticamente si hace falta), `pkexec` pide **su propia contraseña** — igual que `doas` — nunca la de root.

El trabajo se divide en dos scripts. `alpine-update-root.sh` corre como root vía `pkexec` y solo imprime a stdout/stderr (`apk update`, `apk upgrade`, y `flatpak update -y` si Flatpak está instalado) — sin nada gráfico en el lado privilegiado, para no depender de que X11/Wayland se reenvíe correctamente a través del salto de privilegios. `alpine-update-launcher.sh` corre como el usuario normal e invoca el anterior.

**Por qué la ventana puede quedarse pegada en el primer mensaje sin este ajuste.** `apk` y `flatpak` deciden cuánto detalle imprimir — y con qué buffer — según si su salida está conectada a una terminal real. Aquí no lo está (escribe a un archivo), así que sin protección, ninguno de los dos tiene motivo para soltar su salida línea por línea: la ventana de progreso puede quedarse mostrando solo "Actualizando Alpine (apk)" hasta que el proceso completo termina, sin forma de saber si sigue trabajando o si ya no hay actualizaciones pendientes. `alpine-update-root.sh` envuelve cada llamada con `script -qec "..." /dev/null` (`script` es parte de `util-linux-misc`, instalado junto a `zenity` en este mismo bloque) — engaña al programa haciéndole creer que sí hay una terminal, sin que aparezca nada distinto en la pantalla real, ya que el *typescript* que `script` normalmente guardaría se descarta a `/dev/null`. También se agrega `--no-progress` a `apk` explícitamente, para evitar que, al creerse en una terminal, intente dibujar una barra de progreso que se redibuja a sí misma (con retornos de carro en vez de saltos de línea), algo que no se lleva bien con `tail -n1`. Si `script` no está disponible por algún motivo, el script sigue funcionando igual sin él — solo vuelve al comportamiento anterior.

**No se muestra ninguna ventana hasta que la contraseña ya se aceptó.** Encadenar `pkexec` directamente con Zenity en una sola tubería hace que ambas ventanas arranquen a la vez, y la de Zenity a veces tapa al diálogo de contraseña — obligando a buscarlo. En vez de eso, `alpine-update-root.sh` escribe en un archivo marcador (`/tmp/.alpine-update-authenticated`) apenas `pkexec` lo autoriza como root, y el lanzador espera a ver ese marcador (o a que el proceso termine antes, por ejemplo si se cancela la contraseña o no hay agente de autenticación) antes de mostrar nada. El marcador lo crea el lanzador como el usuario normal; `alpine-update-root.sh` solo escribe contenido dentro de él (nunca lo borra ni lo recrea), así la propiedad nunca cambia de manos y el lanzador puede borrarlo después sin toparse con el bit *sticky* de `/tmp`, que impide borrar archivos ajenos.

**Una sola línea que se reemplaza sola, sin scroll — y por qué costó cuatro intentos llegar aquí.** En vez de `--text-info` (que exige desplazarse para ver lo más nuevo), se usa `zenity --progress --pulsate`, donde cualquier línea que empiece con `#` reemplaza el texto visible (confirmado directamente en el código fuente de Zenity). Llegar a un mecanismo confiable para alimentar esas líneas — y para que la ventana supiera cuándo terminar — tomó cuatro diseños:

1. **Un bucle de sondeo** (`while kill -0 "$BGPID"; do tail -n1 ...; sleep 0.3; done`) — frágil: si la detección del proceso fallaba en cualquier vuelta, el bucle no volvía a ejecutarse y la ventana quedaba congelada en el primer mensaje, con la barra animándose (dando una falsa sensación de actividad) pero sin texto nuevo — exactamente el síntoma reportado en la práctica.
2. **Una tubería con nombre (FIFO)** para separar el prefijado `#` del resto, pensada para no depender del sondeo anterior — pero demostró en pruebas quedarse esperando para siempre si el lector y el escritor no llegaban a sincronizarse en el momento exacto de abrir la tubería.
3. **`alpine-update-root.sh` escribiendo el prefijo `#` directamente**, simplificando el lanzador a un `tail -f` directo hacia Zenity — esto sí arregló el avance en vivo (verificado con tiempos reales: las líneas llegan escalonadas según se producen), pero dejaba `tail -f` corriendo *para siempre* a propósito. Ese "costo aceptado" resultó ser un error real: sin que la tubería hacia Zenity reciba EOF, la barra `--pulsate` nunca deja de animarse y el botón para cerrar la ventana nunca se habilita, aunque el último mensaje ya diga que todo terminó — el síntoma reportado en la siguiente ronda.
4. **El diseño actual:** `tail -n1 -f --pid="$BGPID" "$LOG"` — `--pid` es una opción real de GNU coreutils (`tail --help` la documenta explícitamente: *"with -f, terminate after process ID, PID dies"*) que hace que `tail` se detenga **solo**, automáticamente, en cuanto el trabajo de fondo ya no existe, sin rastrear ni matar ningún proceso a mano. Eso le da a Zenity el EOF que le faltaba. El `tail` de BusyBox (el de Alpine por defecto) no soporta `--pid`, así que este bloque instala `coreutils` junto con `zenity`.

Verificado con el `tail` real de GNU coreutils (no una simulación): al terminar el trabajo de fondo, la alimentación se corta sola y el proceso que lee la salida recibe EOF sin intervención externa — el lanzador completo termina limpio, sin necesitar ningún mecanismo de por sí ajeno al diseño para forzar su cierre.

La barra animada de `--pulsate` transmite que el proceso sigue corriendo aunque el texto no cambie por un momento, y como no se usa `--auto-close`, la ventana **se queda abierta mostrando el mensaje final** hasta que el usuario la cierra, en vez de desaparecer antes de que le dé tiempo a leerlo. `alpine-update-root.sh` incluye la hora en su propia línea de resultado (éxito o error), así el mensaje final queda completo por sí solo sin depender de que el lanzador agregue algo después.

> **Nota honesta:** al sondear cada 0.3 segundos, alguna línea de progreso intermedia entre dos sondeos puede no llegar a mostrarse si `apk` avanza más rápido que eso — no se pierde información importante (el mensaje final siempre se captura), solo algún paso intermedio del recorrido.

> **Nota técnica:** algunos programas cambian su propio buffering cuando su salida va a una tubería en vez de a una terminal, así que el texto puede llegar en bloques en vez de línea por línea perfectamente fluida.

**Detección de actualización del kernel.** En Alpine, actualizar el kernel *reemplaza* el paquete y borra los módulos del kernel anterior, así que hasta reiniciar, cargar módulos nuevos (por ejemplo, al conectar un USB) puede fallar. El botón lo maneja en dos capas:
- Durante la actualización, `alpine-update-root.sh` compara `/lib/modules` antes y después de `apk upgrade` (en vez de la salida de `apk info`, cuyo formato cambió entre apk-tools v2 y v3). Si cambió, lo anuncia en la misma ventana, indicando la versión anterior y la nueva.
- Al cerrar la ventana, `alpine-update-launcher.sh` comprueba si el kernel *que está corriendo* sigue instalado, y si no, muestra un aviso emergente pidiendo reiniciar. Para eso busca `/lib/modules/$(uname -r)/modules.order`, un archivo que pertenece al **paquete** del kernel y desaparece al desinstalarse, en vez de comprobar solo si existe el directorio: si al desinstalar el kernel viejo quedan residuos sin dueño (por ejemplo, archivos generados por `depmod`), el directorio seguiría existiendo y el aviso nunca aparecería. Si el sistema no usa `modules.order`, recurre a comprobar el directorio. Como se basa en el **estado** del sistema y no solo en la última ejecución, el aviso sigue apareciendo aunque se pulse el botón varias veces sin reiniciar.

**Agente de autenticación polkit.** `pkexec` lanzado desde un menú gráfico, sin terminal, necesita un agente de autenticación **en ejecución** para dibujar la ventana de contraseña; sin él, falla con *"No authentication agent found"* y la actualización nunca empieza. Plasma, GNOME y LXQt (vía `lxqt-policykit`, Bloque 19) traen el suyo. Para XFCE el script instala `polkit-gnome`, y para MATE su agente nativo `mate-polkit`. Pero instalar el paquete **no garantiza que arranque**: el autoarranque de `polkit-gnome` suele estar restringido a ciertos escritorios según la distribución. Por eso el lanzador, en cada ejecución, comprueba si hay un agente del propio usuario corriendo (leyendo `/proc/*/comm` directamente, sin depender de las opciones de `pgrep`, que varían entre versiones) y, si no lo hay, lo inicia desde las rutas conocidas del binario, que también cambian entre distribuciones. Si no encuentra ninguno, continúa igual: puede tratarse de un escritorio con agente integrado, como GNOME Shell.

**Cierre de la ventana a mitad del proceso — resuelto por diseño, no por blindaje.** En una versión anterior de este bloque, `apk` quedaba conectado *directamente* a Zenity por una tubería (`pkexec | tee | zenity`): si el usuario cerraba la ventana a mitad del proceso, la tubería se rompía y `apk` podía morir por `SIGPIPE` a mitad de una transacción. La solución de entonces era ignorar esa señal (`trap '' PIPE`). Con el rediseño de esta sección (ver más arriba), `alpine-update-root.sh` ya no escribe a una tubería sino a un **archivo** (`>> "$LOG"`) — Zenity ni siquiera está conectado a él, solo lee ese archivo por separado. El riesgo desapareció estructuralmente, así que el `trap` ya no aparece en ninguno de los dos scripts: mantenerlo activo en el lanzador, además de innecesario, era contraproducente, porque una subshell hereda los `trap` de su shell padre — de haber quedado, la subshell que sondea el log y alimenta a Zenity habría ignorado también el cierre de la ventana, quedando en un bucle infinito huérfano en segundo plano en vez de terminar limpiamente cuando el usuario cierra la ventana (el comportamiento que sí se quiere ahí).

**Permisos del log.** El lanzador corre como el usuario normal, que no puede escribir en `/var/log`. El script crea `/var/log/alpine-update.log` perteneciente al grupo `wheel` con permiso `664`, para que cada ejecución quede registrada. *(Una versión anterior de este bloque omitía este paso: la ventana funcionaba, pero el log nunca se guardaba.)*

### Bloque 28 — `setup_user_groups`
Agrega al usuario detectado en el Bloque 5 a los grupos `audio`, `video` y `lpadmin` (necesarios para acceso a hardware de sonido/video y administración de impresoras).

### Bloque 29 — `select_options_menu`
Reúne **todas las decisiones opcionales en una sola pantalla** al inicio, usando `dialog` (se instala en ese momento; funciona tanto en una consola TTY como en una terminal gráfica). Se marca con la barra espaciadora, se continúa con Enter, y una segunda pantalla muestra un resumen con **Comenzar** o **Volver**; al volver, el menú conserva lo ya marcado. A partir de ahí el script corre solo. Aunque este bloque está al final del archivo, `main()` lo ejecuta al principio, justo después de `detect_hardware`, porque la casilla de NVIDIA solo se muestra si se detectó una NVIDIA.

Cada decisión queda en una variable `OPT_*`, y los bloques que antes preguntaban ahora consultan esa variable mediante la función auxiliar `want`. El **respaldo** vive en esa misma función: si el menú no se pudo mostrar (sin terminal interactiva, o sin poder instalar `dialog`), las variables quedan vacías y `want` vuelve a preguntar cada opción por separado, como en versiones anteriores. Pulsar **Salir** en el menú termina el script sin haber hecho cambios de configuración.

Los textos del menú van **sin acentos** a propósito: el menú aparece antes de que el script configure el idioma, y en una consola TTY recién instalada los acentos pueden verse como símbolos extraños.

### Bloque 30 — `main`
Orquesta la ejecución de todos los bloques anteriores en el orden correcto (el orden importa: por ejemplo, `detect_desktop_environment` debe correr antes que `setup_applets`, y `detect_hardware` antes que `install_drivers`).

## Menú de opciones al inicio

Al empezar, el script muestra una pantalla de casillas con todas las decisiones opcionales. Se navega con las flechas, se marca o desmarca con la **barra espaciadora** y se continúa con **Enter**. Después aparece un resumen con lo que se va a instalar, con dos botones: **Comenzar** (el script corre solo desde ahí hasta el final) o **Volver** (regresa al menú conservando lo ya marcado).

| Casilla | Marcada por defecto | Bloque | Qué hace |
|---|---|---|---|
| Teclado latinoamericano | Sí | 3 | Configura `latam` en consola (TTY) y en Xorg |
| NVIDIA en modo seguro | Sí | 12 | **Solo aparece si se detectó una NVIDIA.** Bloquea `nouveau` (Xorg + kernel) y usa la otra GPU |
| gcompat | No | 13 | Compatibilidad con programas propietarios compilados contra glibc |
| Impresoras (CUPS) | Sí | 20 | Instala CUPS y habilita su servicio |
| LibreOffice | Sí | 24 | LibreOffice con paquete de idioma español |
| Flatpak/Flathub | No | 25 | Infraestructura de Flatpak y portales XDG |
| OnlyOffice | No | 25 | Vía Flatpak; **marcarla activa Flatpak automáticamente** |
| Google Chrome | No | 25 | Vía Flatpak (empaquetado comunitario, no oficial de Google); también activa Flatpak |
| Botón "Actualizar el sistema" | Sí | 27 | Acceso directo en el menú de aplicaciones |

**Por qué estos valores por defecto:** el modo seguro de NVIDIA viene marcado porque, en el hardware antiguo al que apunta este proyecto, dejarlo desmarcado puede terminar en pantalla negra, mientras que marcarlo solo cuesta la aceleración de la NVIDIA. Flatpak viene desmarcado porque instalarlo sin ninguna aplicación sería infraestructura sin uso; por eso marcar una de sus aplicaciones lo activa sola.

**Respaldo:** si el menú no se puede mostrar (por ejemplo, si el script se ejecuta sin una terminal interactiva, o si `dialog` no se pudo instalar), el script vuelve al comportamiento anterior y hace cada pregunta por separado en el momento en que la necesita, respondiendo `s` o `n`. Cualquier respuesta que no empiece con `s`/`S`/`y`/`Y` (incluyendo Enter vacío) se interpreta como "no".

**Salir:** pulsar **Salir** en el menú termina el script sin haber hecho cambios de configuración (hasta ese punto solo se actualizó el índice de paquetes y se instalaron las herramientas de detección y el propio `dialog`).

## Archivos que el script crea o modifica

| Archivo | Bloque | Propósito |
|---|---|---|
| `/etc/X11/xorg.conf.d/00-keyboard.conf` | 3 | Layout de teclado latam en Xorg |
| `/etc/X11/xorg.conf.d/20-nouveau-safe.conf` | 12 | `NoAccel` para nouveau (solo si se acepta el modo seguro) |
| `/etc/modprobe.d/blacklist-nouveau.conf` | 12 | Bloqueo del módulo `nouveau` a nivel de kernel (solo si se acepta) |
| `/etc/conf.d/zram-init` | 15 | Tamaño y algoritmo del dispositivo zram |
| `/etc/sysctl.conf` | 15 | `vm.swappiness`, `vm.page-cluster` (se agregan líneas, no se sobreescribe) |
| `/etc/udev/rules.d/60-ioscheduler.rules` | 18 | Planificador de E/S (BFQ o mq-deadline) para discos mecánicos detectados |
| `/etc/profile.d/lang-es.sh` | 22 | Variables de idioma para shells de login |
| `/etc/environment` | 22 | Variables de idioma para PAM (se limpian líneas `LANG`/`LC_*` previas antes de reescribir) |
| `/etc/xdg/plasma-localerc` | 22 | Idioma de Plasma, default de sistema (solo si se detecta Plasma) |
| `$HOME/.config/plasma-localerc` | 22 | Idioma de Plasma para el usuario detectado (solo si se detecta Plasma) |
| `/etc/rc.conf` | 22 | Se agrega `unicode="YES"` si no estaba presente |
| `/var/log/desktop-postinstall.log` | (todos) | Registro completo de la ejecución |
| `/usr/local/bin/alpine-update-root.sh` | 27 | Script de trabajo (root, vía `pkexec`): `apk update`/`apk upgrade` + `flatpak update`, imprime a stdout/stderr |
| `/usr/local/bin/alpine-update-launcher.sh` | 27 | Script lanzador (usuario normal): invoca `pkexec` y canaliza su salida en vivo hacia `zenity --text-info` |
| `/usr/share/applications/alpine-update.desktop` | 27 | Entrada de menú "Actualizar el sistema", visible en todos los DE detectados |
| `/var/log/alpine-update.log` | 27 | Registro de cada ejecución del botón de actualización (grupo `wheel`, permiso `664`, para que el usuario normal pueda escribir) |

## Servicios OpenRC habilitados

Todos en el runlevel `default`, salvo aclaración:

`networkmanager`, `bluetooth` (solo si se detectó adaptador Bluetooth), `spice-vdagentd` (solo entornos virtualizados), `zram-init`, `earlyoom`, `acpid`, `dbus`, `elogind`, `polkit`, `cupsd`, `lightdm`/`sddm`/`gdm` (el que corresponda, ver Bloque 25).

`udisks2`, `wpa_supplicant` y `pulseaudio` **no** se registran como servicios de arranque a propósito (ver Bloques 6 y 19 para el porqué de cada uno).

## Registro de ejecución (log)

Todo lo que el script hace queda en `/var/log/desktop-postinstall.log`, con cuatro niveles:

- `[INFO]` — paso en curso.
- `[OK]` — paso completado con éxito.
- `[WARN]` — algo no salió como se esperaba, pero el script continúa (paquete no encontrado, servicio no agregado, etc.).
- `[ERROR]` — fallo grave que sí detiene el script (falta de permisos root, `apk update` fallido).

El log es acumulativo entre ejecuciones (usa `tee -a`), así que si corres el script varias veces, verás el historial completo de todas las corridas en el mismo archivo.

## Reejecución / idempotencia

El script está diseñado para poder correrse más de una vez sin causar daño:

- `apk add` sobre un paquete ya instalado no hace nada.
- `rc-update add` sobre un servicio ya agregado a un runlevel no duplica la entrada.
- Los archivos de configuración se sobreescriben con `cat >` (contenido determinista, no se acumulan versiones).
- `/etc/environment` limpia explícitamente las líneas `LANG`/`LC_ALL`/`LC_MESSAGES` previas antes de volver a escribirlas, para evitar duplicados.

Esto es útil si quieres volver a correrlo tras cambiar de opinión en alguna de las preguntas interactivas, o después de instalar un segundo entorno de escritorio.

## Limitaciones conocidas

- **⚠️ Pantalla negra persistente en hardware NVIDIA, incluso con el modo seguro activado.** Pruebas realizadas hasta ahora muestran que, en al menos algunos equipos con tarjeta NVIDIA, el problema de pantalla negra **reaparece tras reiniciar** aunque se haya respondido "sí" a la pregunta del Bloque 12 (bloqueo de `nouveau` vía `NoAccel` en Xorg + `blacklist` en `/etc/modprobe.d`). Esto indica que la causa raíz **no está completamente resuelta** con el enfoque actual — es un pendiente abierto, no una solución garantizada. Si te encuentras en este caso:
  - No asumas que el equipo quedó "arreglado" solo por haber aceptado el modo seguro; verifica el arranque real tras reiniciar.
  - Si necesitas recuperar acceso, entra por una TTY (consola de texto, sin arrancar Xorg) para revisar `dmesg | grep -i nouveau` y `cat /var/log/desktop-postinstall.log`, y confirmar si `/etc/modprobe.d/blacklist-nouveau.conf` realmente se aplicó y si el módulo sigue cargado (`lsmod | grep nouveau`).
  - Si el bloqueo del módulo no fue suficiente, puede que el cuelgue ocurra en una etapa aún más temprana que la cubierta por este script (por ejemplo, en el propio firmware/KMS antes de que OpenRC llegue a iniciar servicios) — este escenario requiere más diagnóstico específico por equipo y todavía no tiene una solución generalizada incorporada al script.
- **`unrar` no está disponible.** No hay alternativa vía `apk`; ver Bloque 20.
- **El microcódigo de AMD no se garantiza cargado en el arranque** solo con instalar el paquete; Alpine no lo integra automáticamente al initramfs.
- **El montaje de USB depende de `elogind` reconociendo la sesión como activa.** Si en algún momento el montaje pide contraseña de root inesperadamente, el problema casi seguro está en que la sesión gráfica no está siendo reconocida como activa por `elogind` — **no** es un problema de pertenencia a grupos Unix (`plugdev`/`storage`), que es el mecanismo de un backend distinto (`seatd`) que este script no usa.
- **El script asume que el entorno de escritorio ya fue instalado por separado** (vía `setup-desktop`). No instala XFCE, Plasma, GNOME, MATE ni LXQt desde cero.
- **Hardware NVIDIA legacy:** el modo seguro del Bloque 12 deshabilita la NVIDIA por completo (a nivel de kernel). Si más adelante necesitas usarla (por ejemplo, para decodificación de video), tendrás que revertir manualmente (ver siguiente sección).

## Solución de problemas

**El teclado sigue en inglés dentro de la sesión gráfica.** Algunos entornos (especialmente XFCE) cachean su propia configuración de teclado la primera vez que arrancan. Abre el panel de configuración de teclado del entorno una sola vez y confirma que "latam" ya aparece preseleccionado.

**Pantalla negra o cuelgue al iniciar Xorg con NVIDIA.** Si respondiste "no" a la pregunta del Bloque 12 y ahora tienes problemas, vuelve a correr el script y responde "sí" esta vez — o edita manualmente `/etc/modprobe.d/blacklist-nouveau.conf` (ver contenido en la [tabla de archivos](#archivos-que-el-script-crea-o-modifica)).

**Flatpak no se instaló / falló el `remote-add`.** Verifica que el repositorio `community` esté habilitado (`grep -v '^#' /etc/apk/repositories`) y que haya conexión a internet.

**El montaje automático de USB no funciona.** Confirma que `elogind` y `polkit` estén corriendo (`rc-service elogind status`, `rc-service polkit status`) y que hayas reiniciado después de correr el script (estos servicios necesitan estar activos desde el arranque, no basta con iniciarlos manualmente después).

## Cómo revertir cambios específicos

| Para revertir... | Hacer esto |
|---|---|
| Bloqueo de NVIDIA | Borrar `/etc/X11/xorg.conf.d/20-nouveau-safe.conf` y `/etc/modprobe.d/blacklist-nouveau.conf`, luego reiniciar |
| Idioma del sistema | Borrar `/etc/profile.d/lang-es.sh`, quitar las líneas `LANG`/`LC_*` de `/etc/environment`, y (si aplica) `/etc/xdg/plasma-localerc` y `$HOME/.config/plasma-localerc` |
| zram | `rc-service zram-init stop`, `rc-update del zram-init`, borrar `/etc/conf.d/zram-init` |
| EarlyOOM | `rc-update del earlyoom`, `apk del earlyoom earlyoom-openrc` |
| CUPS | `rc-update del cupsd`, `apk del cups cups-filters system-config-printer` |
| Planificador de E/S para HDD | Borrar `/etc/udev/rules.d/60-ioscheduler.rules`, luego `udevadm control --reload-rules && udevadm trigger` (o reiniciar) |

---

*Este README documenta el script `desktop-postinstall.sh` tal como quedó tras las correcciones y adiciones acumuladas: distribución latam (opcional), detección multi-entorno (XFCE/Plasma/GNOME/MATE/LXQt), detección y firmware de adaptadores WiFi y Bluetooth (PCI y USB, con puente de audio A2DP vía `pulseaudio-bluez`), soporte de gráficos híbridos, protección NVIDIA legacy, menú de casillas al inicio con respaldo a preguntas individuales, instalación en lote con fallback automático (`install_pkgs`), optimización de E/S para discos mecánicos, habilitación automática del Display Manager, acceso directo de actualización en el menú de aplicaciones (vía `pkexec`, multi-entorno), zram, EarlyOOM, gestión de energía, montaje automático de USB, impresión (opcional), idioma español en tres capas, tipografías, LibreOffice (opcional), Flatpak (opcional), y diagnóstico de dispositivos sin controlador con orientación sobre AKMS y `gcompat` para hardware que solo funciona con drivers propietarios.*
