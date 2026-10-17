# Lázaro Linux

**Tu hardware aún tiene pulso.**

ISO de Alpine Linux con sesión live (escritorio XFCE) e instalador gráfico
Calamares, pensada para revivir portátiles antiguos. Arranca en equipos
con BIOS y con UEFI. Al instalar se elige uno de los escritorios que Alpine
soporta oficialmente y, al final, se ejecuta `desktop-postinstall.sh`
(el de la raíz de este repositorio) sin hacer preguntas.

## Cómo está armada

| Pieza | Dónde | Qué hace |
|---|---|---|
| Versión de Alpine y de Calamares | `config.env` | Un solo lugar para cambiar de versión |
| Calamares | `paquetes/calamares/APKBUILD` | Alpine no lo empaqueta, así que se compila |
| Perfil de la ISO | `perfil/mkimg.lazaro.sh` | Lo usa `mkimage.sh` de aports |
| Sesión live | `perfil/genapkovl-lazaro.sh` + `live/` | Usuario `lazaro`, inicio automático, Calamares |
| Pasos de instalación | `live/usr/sbin/lazaro-instalar` | Usa `setup-disk` y `setup-desktop` de Alpine |
| Pruebas | `pruebas/qemu.sh` | Arranque live e instalación en QEMU, BIOS y UEFI |
| Compilación automática | `.github/workflows/lazaro-iso.yml` | Estable + edge, en cada cambio y cada lunes |

### Qué pasa al instalar

1. Calamares pregunta idioma, zona horaria, teclado, **escritorio**
   (XFCE preseleccionado), disco y usuario.
2. Calamares particiona y monta el disco (ext4; partición EFI en UEFI).
3. `lazaro-instalar base`: `setup-disk` instala el sistema base, el kernel,
   el firmware del hardware detectado y GRUB (BIOS o UEFI, con la ruta de
   respaldo `EFI/boot/bootx64.efi` para firmwares viejos).
4. Calamares crea el usuario (grupo `wheel`, con `doas`).
5. `lazaro-instalar escritorio`: `setup-desktop <escritorio>`.
6. `lazaro-instalar ajustes`: idioma, teclado, zona horaria y
   `desktop-postinstall.sh` con las opciones premarcadas de su menú.
   Si no hay internet, el script queda programado para el primer
   arranque con red (servicio `lazaro-primer-arranque`).

XFCE se instala sin internet desde la propia ISO. Los demás escritorios
(MATE, LXQt, xfce-wayland, GNOME, Plasma, Sway) se descargan.

## Compilar

En cualquier Linux con Docker:

```sh
./lazaro-linux/build.sh
```

La ISO queda en `lazaro-linux/salida/`. La primera vez tarda bastante
porque compila Calamares; después lo toma de `lazaro-linux/cache/`.

Para probar la siguiente versión de Alpine sin tocar archivos:

```sh
ALPINE_BRANCH=edge ./lazaro-linux/build.sh
```

Para cambiarla de forma permanente, edita `ALPINE_BRANCH` en
`config.env`.

## Probar

Solo en máquinas virtuales o en un equipo de sobra: el instalador borra
el disco que se elija.

```sh
./lazaro-linux/pruebas/qemu.sh live salida/lazaro-linux-*.iso bios
./lazaro-linux/pruebas/qemu.sh instalar salida/lazaro-linux-*.iso uefi xfce con-red
```

Las capturas de pantalla y los registros quedan en
`lazaro-linux/pruebas/resultados/`.

## Versiones probadas

| Alpine | Calamares | Estado |
|---|---|---|
| v3.24 | 3.4.3 | En pruebas (CI) |
| edge | 3.4.3 | Aviso temprano (CI, no bloquea) |

## Pendiente

- Probar en el ASUS K53SV (BIOS antiguo, Intel HD 3000 + NVIDIA GT 540M).
- Capturas reales de cada escritorio en el selector (hoy son tarjetas).
- Cifrado de disco (desactivado por ahora).
