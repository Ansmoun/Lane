# LANE

**Layered Agnostic Native Environment.**

Entorno de escritorio para Linux. Consume la API pública de
[LaneTK](https://github.com/Ansmoun/LaneTK) (el toolkit gráfico en
LuaJIT + FFI) y provee lo que hace que un escritorio sea un
escritorio: barra, wallpaper, launcher, panel de sistema, menú de
logout, cliente de screenshot.

LANE no tiene dependencias de GTK, Qt, WebKit ni Electron. Corre
sobre X11 vía los bindings XCB de LaneTK.

---

## Índice

1. Arquitectura
2. Estructura del repositorio
3. Requisitos
4. Instalación
5. Uso
6. Configuración
7. Componentes
8. Documentación extendida

---

## 1. Arquitectura

LANE se apoya en LaneTK para todo lo que es infraestructura (XCB,
Cairo, Pango, event loop, widgets base, animaciones) y aporta:

- El motor de la barra superior y sus estilos intercambiables.
- La gestión de wallpaper (multi-monitor, formatos arbitrarios).
- El launcher de aplicaciones.
- El menú de logout.
- El cliente de screenshot y grabación.
- El panel de sistema (tabs de inicio, recursos, red).
- El wrapper de sesión y el autostart de daemons.

LANE no conoce ni depende del gestor de ventanas. Arranca idéntico
con bspwm, i3, openbox, fluxbox o dwm.

---

## 2. Estructura del repositorio

    lane/
    |-- README.md              -- este archivo
    |-- LICENSE                -- GPL-3.0
    |-- run                    -- entry point. Resuelve LUA_PATH.
    |-- autostart.lua          -- daemons que arrancan con la sesión
    |-- layout.lua             -- spec de la barra superior
    |-- apps/                  -- entry points de los daemons
    |-- bin/
    |   +-- lane-session       -- wrapper de sesión (lo llama startx)
    |-- src/
    |   |-- app.lua            -- esqueleto común de apps one-shot
    |   |-- autostart.lua      -- lógica de spawn
    |   |-- panel.lua          -- panel de sistema
    |   |-- panelapp.lua       -- app del panel
    |   |-- password_prompt.lua
    |   |-- timer.lua
    |   |-- wallpaper.lua      -- lógica del wallpaper
    |   |-- bar/               -- motor de la barra
    |   |   |-- engine.lua
    |   |   |-- geometry.lua
    |   |   |-- separators.lua
    |   |   |-- widgets.lua
    |   |   +-- styles/        -- estilos intercambiables
    |   +-- tabs/              -- tabs del panel de sistema
    |       |-- inicio.lua, config.lua, cpu.lua, ram.lua, ...
    |       |-- net/
    |       +-- resources/
    |-- palettes/              -- paletas de colores
    |-- icons-png/             -- iconos en PNG (por tamaño)
    +-- icons-src/             -- iconos fuente en SVG

`run` resuelve LUA_PATH con dos raíces: `LANE/src` y `LaneTK`. Busca
LaneTK en este orden: `$LANETK_DIR`, `~/proyectos/lanetk`, o
`/opt/lanetk`.

---

## 3. Requisitos

- **LaneTK** instalado y accesible desde LUA_PATH.
- **LuaJIT**.
- **X11** con XCB, Cairo, Pango, xkbcommon.
- **ffmpeg** para el wallpaper y la grabación de video.
- **scrot** para las capturas de pantalla.
- **pactl** o **wpctl** para el sampler de volumen.
- **xrandr**.
- **bspwm** o cualquier otro WM (no obligatorio).

---

## 4. Instalación

LANE es un repositorio de desarrollo. En producción se instala junto
con LaneTK en `/opt/`:

    sudo tools/install.sh

(Script en desarrollo. Instala LaneTK en `/opt/lanetk/` — clonando el
repo si no existe — y LANE en `/opt/lane/`.)

---

## 5. Uso

Desde la raíz del repositorio:

    ./run apps/bar.lua           -- barra superior
    ./run apps/wallpaper.lua     -- wallpaper
    ./run apps/launcher.lua      -- daemon del launcher
    ./run apps/screenshot.lua    -- daemon del screenshot
    ./run apps/logout.lua        -- daemon del menú de logout
    ./run apps/sysmon.lua        -- panel de sistema (one-shot)

En una sesión completa, todos los daemons los lanza `bin/lane-session`
al arrancar la sesión, según lo declarado en `autostart.lua`.

Atajos típicos (declarados en `sxhkdrc`):

    super + d           → echo toggle > /tmp/lane-launcher.cmd
    super + Print       → echo toggle > /tmp/lane-screenshot.cmd
    super + shift + e   → echo toggle > /tmp/lane-logout.cmd
    super + b           → echo reload > /tmp/lane-bar.cmd

Los daemons se controlan por trigger file (`echo <cmd> > /tmp/lane-<name>.cmd`).

---

## 6. Configuración

- **`layout.lua`** (raíz): spec de la barra superior. Define el
  estilo, qué widgets van en cada zona (`left`, `center`, `right`),
  gaps y padding.
- **`autostart.lua`** (raíz): daemons a lanzar con la sesión.
- **`~/.config/lane/wm`**: WM a usar (`bspwm`, `i3`, ...). Lo lee
  `bin/lane-session`.
- **`~/.config/lane/palette`**: paleta activa. Lo lee LaneTK.
- **`~/.config/lane/screenshot.conf`**: preferencias de grabación
  (calidad, preset de ffmpeg, CRF).

---

## 7. Componentes

**Barra** (`src/bar/`):
- `engine.lua`: monta el árbol a partir de `layout.lua` y un
  registry de constructores.
- `geometry.lua`: traduce la spec a coordenadas absolutas sobre un
  monitor.
- `separators.lua`: primitivas de separadores (flechas, glyphs, gaps).
- `widgets.lua`: constructores reales (iconos + texto) con samplers
  del sistema.
- `styles/`: estilos intercambiables (`arrow`, `dock`, `island`,
  `minimal`, etc.). Cada uno es un módulo independiente.

**Wallpaper** (`src/wallpaper.lua`):
Decodifica cualquier formato a BGRA del tamaño exacto de cada
monitor con `ffmpeg + lanczos`, y lo sube a un pixmap server-side.
Cero CPU por frame, cero Cairo en el camino de dibujo.

**Autostart** (`src/autostart.lua`):
Spawnea los daemons declarados en `autostart.lua`. Log por daemon a
`/tmp/lane-<name>.log`.

**Wrapper de sesión** (`bin/lane-session`):
Aplica `xrandr`, ejecuta el autostart, lee `~/.config/lane/wm` (o
`/tmp/lane-wm-choice` si viene de un greeter) y hace `exec` al WM.

---

## 8. Documentación extendida

- **LaneTK**: <https://github.com/Ansmoun/LaneTK>
  Documentación de la API del toolkit. Necesaria para escribir
  widgets o apps nuevas.
- **Lefty**: <https://github.com/Ansmoun/Lefty>
  El greeter (pantalla de login). Es el punto de entrada típico a
  LANE en una sesión completa.
