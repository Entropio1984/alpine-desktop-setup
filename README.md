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
5. [Preguntas interactivas que hará el script](#preguntas-interactivas-que-hará-el-script)
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

El script pedirá confirmación en un puñado de puntos (ver [sección 5](#preguntas-interactivas-que-hará-el-script)); el resto corre sin intervención. Al finalizar, **reinicia el sistema** — varios cambios (bloqueo de módulos de kernel, servicios recién habilitados, variables de idioma) no toman efecto por completo hasta el próximo arranque.

## Filosofía del script

Tres principios guían todas las decisiones de diseño:

- **Detectar antes de asumir.** El script nunca asume qué entorno de escritorio, GPU o CPU tienes — los detecta con `apk info -e`, `lspci` y `/proc/cpuinfo`, y adapta cada bloque al resultado real.
- **Nunca abortar por un paquete faltante.** Cada instalación pasa por la función `install_pkg()`, que registra un `WARN` y continúa si un paquete no existe en tu rama/arquitectura, en vez de detener todo el script (`set -e` sigue activo para errores verdaderamente graves, como quedarte sin permisos de root).
- **Honestidad sobre las limitaciones de Alpine.** Cuando algo no tiene una solución limpia en Alpine (por ejemplo, `unrar` no está empaquetado por ser de licencia no-libre, o el microcódigo de AMD no tiene paquete dedicado), el script lo dice explícitamente en el log en vez de fingir que lo resolvió.

## Recorrido bloque por bloque

El script se organiza en 27 bloques, ejecutados en este orden por la función `main()`:

### Bloque 1 — `check_root`
Verifica que el script corre como `root` (`id -u` = 0). Si no, aborta con un mensaje claro.

### Bloque 2 — `update_system` / `install_pkg` / `install_pkgs`
`update_system` corre `apk update` una sola vez al principio. `install_pkg` instala **un** paquete con tolerancia a fallos (usado cuando el nombre del paquete depende de hardware detectado y no se quiere arriesgar una transacción en lote). `install_pkgs` instala **varios** paquetes en una sola transacción de `apk` (mucho más rápido: una sola resolución de dependencias en vez de una por paquete) — si la transacción en lote falla porque algún nombre no existe en tu rama/arquitectura, cae automáticamente a instalar cada paquete por separado con `install_pkg`, así se gana velocidad en el caso normal sin perder la tolerancia a fallos individuales en el caso excepcional.

### Bloque 3 — `setup_keyboard_layout`
**Pregunta primero** (ver sección 5) si se desea configurar el teclado a distribución latam — no es una preferencia universal, así que no se aplica sin confirmar. Si se acepta, lo hace en dos capas independientes:
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
Busca palabras clave de fabricante (Intel, Realtek, Atheros/Qualcomm, MediaTek/Ralink, Marvell, Broadcom) en `$WIFI_INFO` e instala el/los subpaquete(s) de firmware correspondientes — el paquete genérico `linux-firmware` **no** incluye el firmware específico de cada chipset WiFi, Alpine lo divide en decenas de subpaquetes por fabricante (`linux-firmware-intel`, `linux-firmware-realtek`, `linux-firmware-ath9k_htc`, etc.), igual que ocurre con las GPU. Si no se identifica el fabricante por nombre, instala un conjunto amplio como red de seguridad en vez de no instalar nada.

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
- **NVIDIA:** `linux-firmware-nvidia` (driver abierto `nouveau`). Aquí el script **pregunta** si quieres activar un modo seguro (ver [sección 5](#preguntas-interactivas-que-hará-el-script)) — importante en tarjetas antiguas (Tesla/Fermi/Kepler), donde `nouveau` puede colgar el arranque incluso si hay una GPU integrada de respaldo.

Si no se detecta ninguna GPU reconocida, `mesa-dri-gallium` ya deja software rendering (`llvmpipe`) como respaldo funcional.

> **Por qué no se instala el paquete genérico `linux-firmware`:** se verificó directamente en el repositorio de Alpine que ese paquete tiene **102 dependencias** — arrastra casi todos sus subpaquetes de fabricante por defecto. Instalarlo anularía todo el trabajo de selección específica de este bloque y de los Bloques 8/10 (WiFi/Bluetooth), sumando cientos de MB de firmware irrelevante. Por eso el script instala únicamente los subpaquetes que corresponden al hardware realmente detectado.

### Bloque 13 — `detect_cpu` / `install_microcode`
Lee `/proc/cpuinfo` para clasificar el fabricante (`GenuineIntel`/`AuthenticAMD`). Para Intel instala `intel-ucode`. **Para AMD no existe un paquete `amd-ucode` en Alpine** — el microcódigo viaja dentro de `linux-firmware-amd`, que es lo que se instala en su lugar. En ambos casos se advierte que el paquete instalado no garantiza por sí solo que el microcódigo se cargue en el arranque (Alpine no lo integra automáticamente al initramfs); verificar con `dmesg | grep -i microcode` tras reiniciar.

### Bloque 14 — `setup_zram`
Calcula la RAM física total (`/proc/meminfo`) y configura `zram-init` con un dispositivo swap comprimido (algoritmo `zstd`) de tamaño igual al 100% de esa RAM. Ajusta también `vm.swappiness=100` y `vm.page-cluster=0` en `/etc/sysctl.conf` (valores recomendados para swap sobre zram). Pensado para exprimir el máximo de memoria efectiva en equipos con poca RAM física.

### Bloque 15 — `setup_earlyoom`
Instala `earlyoom` (+ su subpaquete `earlyoom-openrc`, necesario para que exista el script de arranque) y lo habilita. `earlyoom` monitorea la memoria en segundo plano y cierra el proceso responsable (ej. una pestaña de Chrome) segundos antes de que el sistema se quede sin memoria y se congele por completo.

### Bloque 16 — `setup_power`
Instala y habilita `acpid` (+ `acpid-openrc`), para que Alpine reaccione a eventos físicos: cerrar la tapa de un laptop, presionar el botón de encendido, etc.

### Bloque 17 — `optimize_hdd_storage`
Recorre `/sys/block/*/queue/rotational` para identificar discos **mecánicos** (excluyendo `loop`/`ram`/`zram`). Si encuentra alguno, configura el planificador de E/S vía una regla `udev` persistente (`/etc/udev/rules.d/60-ioscheduler.rules`): prioriza **BFQ** (diseñado para que un proceso con mucha carga de E/S no congele el resto del escritorio — la misma filosofía que `earlyoom` aplica a la memoria), verificando en tiempo de ejecución si el kernel actual lo tiene disponible y cayendo a `mq-deadline` si no. **No modifica `/etc/fstab`** automáticamente (por ejemplo, para agregar `noatime`) — es un archivo crítico para el arranque y se deja como sugerencia manual en el log, no como cambio automático.

### Bloque 18 — `setup_usb_automount`
Configura el montaje automático de memorias USB al conectarlas. Es el bloque con más piezas coordinadas:
1. **`dbus`** (+ servicio `dbus`) — instalado primero porque todo lo demás en este bloque depende del bus de mensajes del sistema.
2. **`udisks2`** — hace el montaje real. No tiene servicio OpenRC propio: se activa bajo demanda vía D-Bus.
3. **`elogind` + `polkit-elogind`** (servicios `elogind` y `polkit`, nombres distintos a los paquetes) — autorización para que un usuario normal (no root) pueda montar sin contraseña, basada en detección de **sesión activa** (no en pertenencia a grupos Unix — ver [Limitaciones conocidas](#limitaciones-conocidas)).
4. **Disparador según entorno:** `gvfs` + `thunar-volman` para XFCE; `gvfs` para GNOME/MATE; `gvfs` + `lxqt-policykit` para LXQt. Plasma no necesita nada adicional aquí porque Dolphin usa KIO/Solid + `udisks2` directamente.

### Bloque 19 — `setup_printing`
**Pregunta primero** (ver sección 5) si se desea soporte de impresión — no todo equipo "revivido" tiene o necesita una impresora. Si se acepta, instala `cups` + `cups-openrc` + `cups-filters` + `system-config-printer`, habilita el servicio `cupsd`, y deja la interfaz web de CUPS disponible en `http://localhost:631`.

### Bloque 20 — `install_archive_tools`
Instala `zip`, `unzip`, `p7zip`. **`unrar` no se instala porque no existe como paquete en Alpine** (licencia no-libre, verificado en v3.24) — el script lo indica explícitamente en el log en vez de intentarlo y fallar en silencio, y apunta al binario oficial de `rarlab.com/download.htm` como única vía si de verdad se necesita soporte RAR (no automatizado por el script: cada versión de RARLAB cambia el nombre del archivo, y una URL fija quedaría rota con el tiempo).

### Bloque 21 — `setup_locale_es`
Configura español en tres capas independientes, porque ningún mecanismo por sí solo cubre todos los casos:
1. **`/etc/profile.d/lang-es.sh`** — variables `LANG`/`LC_ALL`/`LC_MESSAGES=es_ES.UTF-8` para shells de login tradicionales.
2. **`/etc/environment`** — las mismas variables, leídas por PAM (`pam_env`) en la mayoría de gestores de sesión gráficos (SDDM incluido), que no siempre pasan por `/etc/profile.d`.
3. **`plasma-localerc`** (solo si se detecta Plasma) — Plasma tiene su **propio** mecanismo de idioma, separado del `LANG` del sistema, con dos secciones distintas: `[Formats]` (números/fecha) y `[Translations]` (idioma real de la interfaz). Se escribe tanto en `/etc/xdg/plasma-localerc` (default para usuarios nuevos) como en `$HOME/.config/plasma-localerc` del usuario detectado en el Bloque 5.

También instala `musl-locales`/`musl-locales-lang` y el metapaquete `lang`, que dispara automáticamente (vía `install_if` de `apk`) los subpaquetes `-lang` de todo el software ya instalado en el sistema (XFCE, GTK, Plasma, NetworkManager applet, etc.), sin necesidad de listar cada paquete a mano.

> **Nota:** musl (la libc de Alpine) no tiene un locale `es_MX.UTF-8` — solo un conjunto reducido, entre ellos `es_ES.UTF-8`, que es el que usa el script. Para la traducción de interfaz esto no supone ninguna diferencia práctica (los paquetes de idioma no distinguen variantes regionales de español).

### Bloque 22 — `install_fonts`
Instala `ttf-dejavu`, `font-liberation` + `font-liberation-sans-narrow` (métricamente compatibles con Arial/Times/Courier — importante para abrir `.docx` sin que el texto se desborde) y `font-noto`. Se ejecuta antes de LibreOffice a propósito.

### Bloque 23 — `install_libreoffice`
**Pregunta primero** (ver sección 5) — es de los paquetes más pesados del script, y quien prefiera OnlyOffice vía Flatpak puede omitirlo aquí. Si se acepta, instala `libreoffice` + `libreoffice-lang-es`.

### Bloque 24 — `setup_flatpak`
**Pregunta primero** (ver sección 5) si se desea habilitar Flatpak/Flathub en absoluto — si se responde "no", no se instala nada de infraestructura (`flatpak`, portales XDG) ni se pregunta por apps individuales. Si se acepta: instala Flatpak y agrega el repositorio Flathub, instala `xdg-desktop-portal` + `xdg-desktop-portal-gtk` como base universal, y además el portal nativo correspondiente si se detecta Plasma (`xdg-desktop-portal-kde`) o LXQt (`xdg-desktop-portal-lxqt`) — así los diálogos de "Abrir/Guardar" de apps en sandbox (Chrome, OnlyOffice) se ven coherentes con el entorno en vez de forzar siempre estética GTK. Luego **pregunta** dos veces más si instalar OnlyOffice y Google Chrome desde Flathub.

### Bloque 25 — `setup_display_manager`
Habilita el gestor de inicio de sesión gráfico (`lightdm`/`sddm`/`gdm`) en el runlevel `default`. No basta con que `setup-desktop` lo haya instalado — hay casos reales donde el DM queda instalado pero no correctamente enganchado al arranque. En vez de una prioridad fija (que podría elegir el DM equivocado en equipos con más de un entorno instalado, como XFCE + Plasma a la vez), reutiliza las banderas `DE_*` del Bloque 4 para preferir el emparejamiento convencional — el mismo que usa el propio `setup-desktop` de Alpine internamente: Plasma → `sddm`, GNOME → `gdm`, cualquier otro (XFCE/MATE/LXQt) → `lightdm` si está instalado. Si hay más de un DM instalado, se advierte explícitamente cuál se eligió y por qué.

### Bloque 26 — `setup_user_groups`
Agrega al usuario detectado en el Bloque 5 a los grupos `audio`, `video` y `lpadmin` (necesarios para acceso a hardware de sonido/video y administración de impresoras).

### Bloque 27 — `main`
Orquesta la ejecución de todos los bloques anteriores en el orden correcto (el orden importa: por ejemplo, `detect_desktop_environment` debe correr antes que `setup_applets`, y `detect_hardware` antes que `install_drivers`).

## Preguntas interactivas que hará el script

El script se detiene a preguntar en siete puntos, en este orden:

1. **Distribución de teclado (Bloque 3):**
   > `¿Deseas configurar el teclado a distribución latinoamericana (latam)?`
   - **`s`** → Configura "latam" en consola (TTY) y en Xorg.
   - **`n`** → No toca la configuración de teclado; se deja el layout por defecto del sistema/instalación.

2. **NVIDIA detectada (Bloque 12):**
   > `¿Bloquear la NVIDIA y usar solo la GPU restante (modo seguro)?`
   - **`s`** → Bloquea `nouveau` por completo: `Option "NoAccel" "True"` en Xorg **+** `blacklist nouveau` a nivel de kernel (`/etc/modprobe.d`). La NVIDIA queda inactiva; el sistema usa solo la(s) GPU(s) restante(s). Recomendado en tarjetas Tesla/Fermi/Kepler o si notas pantalla negra/cuelgues.
   - **`n`** → Deja `nouveau` activo con aceleración 3D normal. Riesgo de cuelgue en hardware legacy.

3. **Soporte de impresión / CUPS (Bloque 19):**
   > `¿Deseas instalar soporte de impresión (CUPS)?`
   - **`n`** → Omite CUPS por completo (ni paquetes ni servicio).

4. **LibreOffice (Bloque 23):**
   > `¿Deseas instalar LibreOffice? (paquete pesado; si prefieres OnlyOffice vía Flatpak, puedes responder 'n' aquí y aceptarlo más adelante)`
   - Pensado para equipos con poco espacio en disco, o para quien prefiera usar únicamente OnlyOffice desde Flatpak.

5. **Flatpak/Flathub como infraestructura base (Bloque 24):**
   > `¿Deseas habilitar Flatpak/Flathub en este sistema? (necesario solo si planeas instalar apps como OnlyOffice o Chrome desde Flathub)`
   - **`n`** → No instala `flatpak` ni los portales XDG, y **no se preguntará** por OnlyOffice ni Chrome (bloque completo omitido).
   - **`s`** → Instala la infraestructura y continúa a las dos preguntas siguientes.

6. **OnlyOffice vía Flatpak (Bloque 24, solo si se aceptó la pregunta 5):**
   > `¿Deseas instalar OnlyOffice Desktop Editors vía Flatpak?`

7. **Google Chrome vía Flatpak (Bloque 24, solo si se aceptó la pregunta 5):**
   > `¿Deseas instalar Google Chrome vía Flatpak (paquete comunitario, no oficial de Google)?`
   - Se aclara explícitamente que es un empaquetado mantenido por la comunidad de Flathub, no publicado por Google.

Cualquier respuesta que no empiece con `s`/`S`/`y`/`Y` (incluyendo Enter vacío) se interpreta como "no". La pregunta de NVIDIA solo aparece si el hardware detectado incluye una tarjeta NVIDIA; las preguntas 6 y 7 solo aparecen si se respondió "sí" a la pregunta 5.

## Archivos que el script crea o modifica

| Archivo | Bloque | Propósito |
|---|---|---|
| `/etc/X11/xorg.conf.d/00-keyboard.conf` | 3 | Layout de teclado latam en Xorg |
| `/etc/X11/xorg.conf.d/20-nouveau-safe.conf` | 12 | `NoAccel` para nouveau (solo si se acepta el modo seguro) |
| `/etc/modprobe.d/blacklist-nouveau.conf` | 12 | Bloqueo del módulo `nouveau` a nivel de kernel (solo si se acepta) |
| `/etc/conf.d/zram-init` | 14 | Tamaño y algoritmo del dispositivo zram |
| `/etc/sysctl.conf` | 14 | `vm.swappiness`, `vm.page-cluster` (se agregan líneas, no se sobreescribe) |
| `/etc/udev/rules.d/60-ioscheduler.rules` | 17 | Planificador de E/S (BFQ o mq-deadline) para discos mecánicos detectados |
| `/etc/profile.d/lang-es.sh` | 21 | Variables de idioma para shells de login |
| `/etc/environment` | 21 | Variables de idioma para PAM (se limpian líneas `LANG`/`LC_*` previas antes de reescribir) |
| `/etc/xdg/plasma-localerc` | 21 | Idioma de Plasma, default de sistema (solo si se detecta Plasma) |
| `$HOME/.config/plasma-localerc` | 21 | Idioma de Plasma para el usuario detectado (solo si se detecta Plasma) |
| `/etc/rc.conf` | 21 | Se agrega `unicode="YES"` si no estaba presente |
| `/var/log/desktop-postinstall.log` | (todos) | Registro completo de la ejecución |

## Servicios OpenRC habilitados

Todos en el runlevel `default`, salvo aclaración:

`networkmanager`, `bluetooth` (solo si se detectó adaptador Bluetooth), `spice-vdagentd` (solo entornos virtualizados), `zram-init`, `earlyoom`, `acpid`, `dbus`, `elogind`, `polkit`, `cupsd`, `lightdm`/`sddm`/`gdm` (el que corresponda, ver Bloque 25).

`udisks2`, `wpa_supplicant` y `pulseaudio` **no** se registran como servicios de arranque a propósito (ver Bloques 6 y 18 para el porqué de cada uno).

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

*Este README documenta el script `desktop-postinstall.sh` tal como quedó tras las correcciones y adiciones acumuladas: distribución latam (opcional), detección multi-entorno (XFCE/Plasma/GNOME/MATE/LXQt), detección y firmware de adaptadores WiFi y Bluetooth (PCI y USB, con puente de audio A2DP vía `pulseaudio-bluez`), soporte de gráficos híbridos, protección NVIDIA legacy, instalación en lote con fallback automático (`install_pkgs`), optimización de E/S para discos mecánicos, habilitación automática del Display Manager, zram, EarlyOOM, gestión de energía, montaje automático de USB, impresión (opcional), idioma español en tres capas, tipografías, LibreOffice (opcional) y Flatpak (opcional).*
