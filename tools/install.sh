#!/bin/sh
# install.sh: instala LANE, su dependencia LaneTK y los proyectos
# satélite del ecosistema en /opt/.
#
# Uso:
#   cd ~/proyectos/lane
#   sudo tools/install.sh [-y] [--install-deps] [--no-satellites]
#
# -y, --yes            no pedir confirmación
#     --install-deps   instalar dependencias faltantes (solo Void Linux)
#     --no-satellites  no instalar los proyectos satélite

set -e

AUTO_YES=0
INSTALL_DEPS=0
INSTALL_SATS=1
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)          AUTO_YES=1 ;;
        --install-deps)    INSTALL_DEPS=1 ;;
        --no-satellites)   INSTALL_SATS=0 ;;
        -h|--help)         sed -n '2,12p' "$0"; exit 0 ;;
        *)                 echo "Argumento desconocido: $1" >&2; exit 1 ;;
    esac
    shift
done

if [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi

SRC="${REAL_HOME}/proyectos/lane"
DST="/opt/lane"
TK_DST="/opt/lanetk"

if [ "$(id -u)" -ne 0 ]; then
    echo "install.sh: necesita root. Correlo con sudo." >&2
    exit 1
fi
if [ ! -d "$SRC/src" ]; then
    echo "install.sh: no existe $SRC/src" >&2
    exit 1
fi

# --- Helpers ---
is_void() { [ -f /etc/os-release ] && grep -q '^ID="\?void"\?$' /etc/os-release; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

MISSING=""
need_cmd() {
    if has_cmd "$1"; then echo "    OK      $1"
    else echo "    FALTA   $1"; MISSING="$MISSING $1"; fi
}
need_one_of() {
    local present=""
    for c in "$@"; do
        if has_cmd "$c"; then present="$c"; break; fi
    done
    if [ -n "$present" ]; then echo "    OK      $present (alternativas: $*)"
    else echo "    FALTA   una de: $*"; MISSING="$MISSING $1"; fi
}

echo "==> LANE — instalación en $DST"
echo "    Origen:  $SRC"
echo

echo "==> Verificando LaneTK"
if [ -d "$TK_DST/src/lib" ]; then
    echo "    OK      $TK_DST (ya instalado)"
else
    echo "    FALTA   $TK_DST"
    echo "            instalalo primero con:"
    echo "              cd ~/proyectos/lanetk && sudo tools/install.sh"
    exit 1
fi
echo

echo "==> Verificando dependencias del entorno"
echo
echo "  Captura de pantalla:"
need_cmd scrot
need_cmd xdotool
need_cmd xwininfo
need_cmd slop
echo
echo "  Grabación de video:"
need_cmd ffmpeg
echo
echo "  Multi-monitor y cursor:"
need_cmd xrandr
need_cmd xmodmap
echo
echo "  Portapapeles y apertura de archivos:"
need_cmd xclip
need_cmd xdg-open
echo
echo "  Búsqueda de archivos:"
need_cmd fd
echo
echo "  Control de sesión:"
need_cmd loginctl
echo

if [ -n "$MISSING" ]; then
    echo "==> Faltan dependencias:$MISSING"
    echo
    if is_void; then
        echo "    Paquetes sugeridos para Void:"
        echo "      xbps-install -S scrot xdotool xwininfo slop ffmpeg \\"
        echo "                     xrandr xmodmap xclip xdg-utils fd elogind"
        echo
        if [ "$INSTALL_DEPS" -eq 1 ]; then
            echo "==> Instalando dependencias (--install-deps activo)"
            xbps-install -Sy scrot xdotool xwininfo slop ffmpeg \
                xrandr xmodmap xclip xdg-utils fd elogind \
                || { echo "Instalación falló" >&2; exit 1; }
        else
            echo "    Volvé a correr con --install-deps para instalarlas."
            exit 1
        fi
    else
        echo "    Instalalas a mano según tu gestor de paquetes."
        exit 1
    fi
else
    echo "==> Todas las dependencias presentes."
fi
echo

if [ -d "$DST" ] && [ "$AUTO_YES" -eq 0 ]; then
    printf "==> Se va a reemplazar $DST. Continuar? [y/N] "
    read -r ans
    case "$ans" in y|Y|yes|YES) ;; *) echo "Cancelado."; exit 0 ;; esac
fi

echo "==> Copiando LANE"
rm -rf "$DST"
mkdir -p "$DST"
tar -C "$SRC" \
    --exclude='./.git' \
    --exclude='*.bak' --exclude='*.bak-*' --exclude='*.bak.*' \
    --exclude='*.orig' --exclude='*.swp' --exclude='.DS_Store' \
    -cf - . | tar -C "$DST" -xf -

echo "==> Ajustando permisos"
chmod -R a+rX,go-w "$DST"
chmod +x "$DST/run" "$DST/bin/lane-session"
[ -f "$DST/tools/install.sh" ] && chmod +x "$DST/tools/install.sh"

echo "==> Verificando require cruzado con LaneTK"
cd "$DST"
if ./run -e '
    require("lib.server")
    require("lib.app")
    print("requires OK")
' 2>&1; then
    echo "    OK"
else
    echo "    FALLO: revisar LUA_PATH de $DST/run" >&2
    exit 1
fi

# --- .desktop para login managers ---
echo "==> Instalando .desktop para login managers"
XSESSION_DIR="/usr/share/xsessions"
DESKTOP_SRC="$DST/tools/LANE.desktop"
DESKTOP_DST="$XSESSION_DIR/LANE.desktop"
if [ -f "$DESKTOP_SRC" ]; then
    mkdir -p "$XSESSION_DIR"
    sed "s|@LANE_SESSION@|$DST/bin/lane-session|g" \
        "$DESKTOP_SRC" > "$DESKTOP_DST"
    chmod 0644 "$DESKTOP_DST"
    echo "    OK      $DESKTOP_DST"
fi

USER_DESKTOP="${REAL_HOME}/.local/share/xsessions/LANE.desktop"
if [ -f "$USER_DESKTOP" ]; then
    echo "    AVISO   existe $USER_DESKTOP (user-local)"
fi
echo

# --- Satélites ---
if [ "$INSTALL_SATS" -eq 1 ]; then
    echo "==> Instalando proyectos satélite"
    SATS="lane-bar lane-launcher lane-files lane-sysmon lane-network \
          lane-disks lane-procs lane-search lane-battery"
    for s in $SATS; do
        sat_src="${REAL_HOME}/proyectos/$s"
        sat_installer="$sat_src/tools/install.sh"
        if [ -d "$sat_src" ] && [ -x "$sat_installer" ]; then
            echo "--- $s ---"
            "$sat_installer" -y 2>&1 | tail -3
        elif [ -d "$sat_src" ]; then
            echo "--- $s --- (sin install.sh, omitido)"
        else
            echo "--- $s --- (no clonado, omitido)"
        fi
        echo
    done
else
    echo "==> Satélites omitidos (--no-satellites)"
fi

echo
echo "==> Instalación completa."
echo "    LANE en $DST"
echo "    .desktop en $DESKTOP_DST"
echo "    Satélites en /opt/lane-*"
