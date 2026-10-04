#!/bin/sh
# install.sh: instala LANE (y opcionalmente LaneTK) en /opt/.
#
# Uso:
#   cd ~/proyectos/lane
#   sudo tools/install.sh [-y]
#
# -y, --yes  no pedir confirmación

set -e

AUTO_YES=0
for a in "$@"; do
    case "$a" in
        -y|--yes) AUTO_YES=1 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    esac
done

# Usuario real (por si se corre con sudo)
if [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi

SRC_LANE="${REAL_HOME}/proyectos/lane"
DST_LANE="/opt/lane"
DST_TK="/opt/lanetk"

# Buscar LaneTK en orden: $LANETK_DIR, working copy, /opt
TK_CANDIDATE=""
for cand in "$LANETK_DIR" "${REAL_HOME}/proyectos/lanetk" "$DST_TK"; do
    if [ -n "$cand" ] && [ -d "$cand/src/lib" ]; then
        TK_CANDIDATE="$cand"
        break
    fi
done

if [ "$(id -u)" -ne 0 ]; then
    echo "install.sh: necesita root. Correlo con sudo." >&2
    exit 1
fi

if [ ! -d "$SRC_LANE/src" ]; then
    echo "install.sh: no existe $SRC_LANE/src" >&2
    exit 1
fi

echo "==> Instalación de LANE en /opt/"
echo "    LANE:   $SRC_LANE"
echo "    Dest:   $DST_LANE"
echo "    LaneTK: ${TK_CANDIDATE:-<se clonará desde GitHub>}"
echo

if [ -d "$DST_LANE" ] && [ "$AUTO_YES" -eq 0 ]; then
    printf "Se va a reemplazar $DST_LANE. Continuar? [y/N] "
    read -r ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *) echo "Cancelado."; exit 0 ;;
    esac
fi

# Instalar LaneTK si no está en /opt
if [ -d "$DST_TK/src/lib" ]; then
    echo "==> LaneTK ya existe en $DST_TK (no se toca)"
elif [ -n "$TK_CANDIDATE" ] && [ "$TK_CANDIDATE" != "$DST_TK" ]; then
    echo "==> Copiando LaneTK desde $TK_CANDIDATE"
    mkdir -p "$DST_TK"
    tar -C "$TK_CANDIDATE" \
        --exclude='./.git' \
        --exclude='./.backups' \
        --exclude='./docs' \
        --exclude='./examples' \
        --exclude='./tests' \
        --exclude='./tools' \
        --exclude='*.bak' --exclude='*.bak-*' --exclude='*.bak.*' \
        --exclude='*.orig' --exclude='*.swp' --exclude='.DS_Store' \
        -cf - . | tar -C "$DST_TK" -xf -
else
    echo "==> Clonando LaneTK desde GitHub"
    git clone --depth=1 https://github.com/Ansmoun/LaneTK.git "$DST_TK"
fi

# Copiar LANE
echo "==> Copiando LANE"
rm -rf "$DST_LANE"
mkdir -p "$DST_LANE"
tar -C "$SRC_LANE" \
    --exclude='./.git' \
    --exclude='*.bak' --exclude='*.bak-*' --exclude='*.bak.*' \
    --exclude='*.orig' --exclude='*.swp' --exclude='.DS_Store' \
    -cf - . | tar -C "$DST_LANE" -xf -

# Permisos
echo "==> Ajustando permisos"
chmod -R a+rX,go-w "$DST_LANE" "$DST_TK"
chmod +x "$DST_LANE/run" "$DST_LANE/bin/lane-session"
[ -f "$DST_LANE/tools/install.sh" ] && chmod +x "$DST_LANE/tools/install.sh"
[ -f "$DST_TK/run" ] && chmod +x "$DST_TK/run"
[ -f "$DST_TK/bin/lanetk-session" ] && chmod +x "$DST_TK/bin/lanetk-session"

# Verificación: un require cruzado desde el run instalado
echo "==> Verificando require de LANE con LaneTK desde /opt"
if "$DST_LANE/run" -e '
    require("lib.server")
    require("app")
    require("bar.engine")
    print("requires OK")
' 2>&1; then
    echo "    OK"
else
    echo "    FALLO: revisar LUA_PATH de $DST_LANE/run" >&2
    exit 1
fi

echo
echo "==> Instalación completa."
echo
echo "Pasos que quedan por hacer (una sola vez):"
echo
echo "  1. Apuntar la sesión a LANE."
echo "     En ~/.xinitrc (o wrapper de sesión):"
echo "       exec $DST_LANE/bin/lane-session"
echo
echo "  2. Si usas Lefty como greeter, verificar que arranca esta sesión"
echo "     (por defecto el wrapper de greetd ya apunta a LaneTK; LANE"
echo "     se lanza dentro de la sesión, no desde el greeter)."
echo
echo "  3. Para probar sin reiniciar sesión:"
echo "       cd $DST_LANE && ./run apps/bar.lua"
