# lg-webos4-tweaks

Inicio sin anuncios, más RAM libre y botones del mando reprogramables para **televisores LG de 2018 rooteados (webOS 4.x)**.

🇬🇧 [Read this in English](README.md)

---

Los LG de 2018 traen unos 840 MB de RAM y dedican buena parte a mantener Netflix, el navegador
y otras apps precargadas en segundo plano, las uses o no. El resultado es un televisor que tira
de swap, va a tirones y tarda una eternidad en abrir cualquier cosa.

Medido en un **43UK6300PSB** (webOS 4.4.3, firmware 05.50.70):

| | Antes | Después |
|---|---|---|
| RAM disponible | 183 MB | **373 MB** |
| Swap en uso | 197 MB | 0 MB |
| Apps precargadas | 9 | 0 |
| Botones del mando | Netflix / Prime Video, fijos | la app que quieras |

![Hearth en un LG de 2018](docs/hearth-home.png)

<sub>Un 43UK6300PSB con [Hearth](https://github.com/rudra-avatar/webos-custom-launcher) en
lugar de la barra de LG. Captura nativa a través del propio inspector del televisor, no una
foto. Hearth es un proyecto aparte — este repositorio es lo que hace que un televisor de
2018 vaya lo bastante fluido para disfrutarlo.</sub>

Casi todos los proyectos de este tipo apuntan a 2019 en adelante. [LGlow](https://github.com/IrvingGuerra/lglow),
que sería la opción obvia, excluye explícitamente 2018 porque reemplaza el inicio a pantalla
completa (`com.webos.app.fullhome`) que llegó con webOS 4.5 — los de 2018 no lo tienen. Este
repositorio es lo que queda al asumir eso, y resultó ser la parte que de verdad importa.

## Qué hace

**Desactiva la precarga de apps.** LG mantiene hasta 2 apps residentes de una lista de 9.
Quitar eso es de donde sale casi toda la memoria.

**Detiene AirPlay y HomeKit** (opcional, `STOP_AIRPLAY=0` para conservarlos). Entre los dos
ocupan unos 35 MB de forma permanente.

**Reasigna los botones Netflix y Amazon** del mando a cualquier app instalada.

**No** reemplaza tu pantalla de inicio. Para eso instala
[Hearth](https://github.com/rudra-avatar/webos-custom-launcher) desde Homebrew Channel —
mira [Pantalla de inicio](#pantalla-de-inicio) para la pega concreta de webOS 4.

## Requisitos

- Un LG de 2018 (webOS 4.x), **rooteado**, con Homebrew Channel instalado.
- Acceso SSH al televisor.

¿Aún sin rootear? Consulta antes [cani.rootmy.tv](https://cani.rootmy.tv/) con tu modelo y
firmware. Si todavía es rooteable, [dejavuln-autoroot](https://github.com/throwaway96/dejavuln-autoroot)
funciona desde una memoria USB, sin modo desarrollador ni cuenta de LG.

> **Desactiva las actualizaciones automáticas antes que nada.** Cuando LG le mande a tu
> televisor un firmware parcheado, rootearlo se acabó para siempre. En Homebrew Channel,
> activa además **Block system updates**.

## Instalación

```sh
git clone https://github.com/josearevalo19977722-dev/lg-webos4-tweaks
cd lg-webos4-tweaks

# Solo la RAM
ssh root@<IP-DEL-TV> 'sh -s' < install.sh

# RAM + reasignar los dos botones
ssh root@<IP-DEL-TV> 'NETFLIX_BUTTON=youtube.leanback.v4 \
                      AMAZON_BUTTON=com.disney.disneyplus-prod sh -s' < install.sh
```

Luego reinicia el televisor. Para ver los IDs de tus apps:

```sh
ssh root@<IP-DEL-TV> 'luna-send -n 1 -f luna://com.webos.applicationManager/listApps "{}" </dev/null'
```

### Opciones

| Variable | Efecto |
|---|---|
| `NETFLIX_BUTTON=<appId>` | reasigna el botón Netflix |
| `AMAZON_BUTTON=<appId>` | reasigna el botón Amazon |
| `STOP_AIRPLAY=0` | mantiene AirPlay y HomeKit |
| `SKIP_PRELOAD=1` | no toca la precarga |
| `SKIP_BUTTONS=1` | no toca el mando |

## Desinstalación

```sh
ssh root@<IP-DEL-TV> 'sh -s' < uninstall.sh
```

Reinicias y vuelve a estar de fábrica. **No se modifica ningún archivo de las particiones de
LG**: las copias parcheadas viven en `/var/lib/webosbrew` y se montan encima en cada arranque,
así que borrar los scripts y reiniciar revierte todo.

## Cómo funciona

Todo lo de abajo salió de trastear en un televisor real. Está escrito porque no hay nada de
esto documentado para webOS 4 en ninguna parte.

### La precarga vive en una configuración de solo lectura

`/etc/configd/layers/base/com.webos.service.preloadmanager.json` y sus variantes por
resolución en `distro/` definen qué apps se precargan. `/etc` es de solo lectura (y el overlay
está al 100%), así que el instalador genera una copia con todos los `isEnabled` en `false` y
`maxPreloadApp: 0`, y el script de arranque la monta encima de las cinco rutas.

La copia se genera **a partir del archivo de tu propio televisor**, así que funciona en modelos
cuya lista de apps sea distinta a la original.

### HomeKit revive si solo lo detienes

`airplay-adaptor` es un job normal de upstart. `homekit` no: lo lanza bajo demanda `ls-hubd`,
el bus de servicios de Luna, y su padre vuelve a levantarlo. Con `kill -9` sí se queda abajo.

### Los botones del mando están en un archivo JavaScript

No en `com.webos.keyaction.json`, que solo cubre teclas de sistema (volumen, guía, subtítulos).
Los hotkeys de apps están en `handleCPHotkeys()`, dentro de
`/usr/lib/qt5/qml/KeyFilters/appLaunch.js`, que carga el compositor:

```js
case WebOS.Key_webOS_Netflix:  appId = "netflix";  break;
case WebOS.Key_webOS_Amazon:   appId = "amazon";   break;
case WebOS.Key_webOS_IVI:      appId = "ivi";      break;
```

Dos cadenas de texto. Eso es toda la atadura.

### …y montar el parche no basta

Esta costó un reinicio extra descubrirla:

```
 2s  arranca surface-manager y lee appLaunch.js
42s  webOS ejecuta start-devmode.sh, que encadena el arranque de Homebrew Channel
44s  nuestro script monta el archivo parcheado  ← demasiado tarde
```

El compositor no vuelve a leer el archivo, y no hay ningún enganche anterior disponible, así
que `20-remote-buttons` reinicia `surface-manager` después de montar. Verás un parpadeo de la
interfaz durante el arranque. Un efecto secundario muy bienvenido: reiniciar el compositor una
vez asentado el arranque libera otros ~80 MB.

Para confirmar que funcionó, comprueba que `surface-manager` arrancó **después** del segundo 44:

```sh
sm=$(pgrep -x surface-manager)
echo $(( $(awk '{print $22}' /proc/$sm/stat) / $(getconf CLK_TCK) ))s
```

### Capturas de pantalla limpias

`/dev/fb0` está a ceros: la interfaz se compone por hardware y no pasa por ahí, y en webOS 4
no existe `com.webos.service.capture`. Pero las apps web exponen un endpoint de Chrome
DevTools en el puerto **9998**, así que se puede sacar un PNG perfecto de cualquiera de ellas:

```sh
ssh -f -N -L 19998:127.0.0.1:9998 root@<IP-DEL-TV>
curl -s http://127.0.0.1:19998/json/list        # localiza el id de la página
# luego envía Page.captureScreenshot por el WebSocket de esa página
```

La captura del principio de este README se hizo así.

### `luna-send` falla en silencio sin stdin

Si no rediriges la entrada estándar, `luna-send` termina con código 0 y no hace nada: ni salida
ni error. Toda llamada necesita `</dev/null`. Cuenta con perder una hora con esto.

## Pantalla de inicio

[Hearth](https://github.com/rudra-avatar/webos-custom-launcher) funciona en webOS 4 aunque solo
esté probado de webOS 7 en adelante, porque se compila para Chrome 53.

Su opción **"make this launcher the default instead of LG Home"** **no** funciona en webOS 4:
el botón HOME sigue abriendo la barra de LG. Lo que sí funciona es activar
**"Add the launcher as a TV input"**. Entonces aparece junto a HDMI 1/2/3, y el televisor
retoma esa entrada al encender, así que arranca directamente en Hearth. No existe ningún ajuste
de "arrancar en la app X": `powerOnScreen` solo admite `todays` o `liveTv`.

## YouTube sin anuncios

La app de YouTube de fábrica es `"type": "native"` con `"main": "cobalt"`, el motor ligero de
Google para televisores. El [youtube-webos](https://github.com/webosbrew/youtube-webos) oficial
es una app `web`, así que en un televisor de 2018 corre sobre Chrome 53 y no declara soporte
para webOS 4.

El [fork de NicholasBly](https://github.com/NicholasBly/youtube-webos) sí declara soporte para
webOS 3 y 4, y conserva las capas de traducción que necesitan los televisores antiguos. Usa su
build **estándar**, no la `webOS22+`. Confirmado funcionando en un 43UK6300PSB.

En cualquier caso hay que desinstalar antes el YouTube de fábrica: comparten el ID
`youtube.leanback.v4`. Se puede reinstalar desde la LG Content Store, que sigue accesible,
porque el bloqueo de actualizaciones solo redirige `su.lge.com` y `snu.lge.com`.

## Créditos

Construido sobre [webOS Homebrew Project](https://www.webosbrew.org/),
[dejavuln-autoroot](https://github.com/throwaway96/dejavuln-autoroot) y
[LGlow](https://github.com/IrvingGuerra/lglow), de quien este proyecto toma el principio de no
escribir nunca en las particiones de LG.

Sin relación con LG. Rootear y modificar tu televisor es responsabilidad tuya.

## Licencia

MIT — ver [LICENSE](LICENSE). No se incluye código de LG: cada archivo parcheado se genera en
tu propio dispositivo a partir de los que ya están en él.
