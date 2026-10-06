#!/bin/sh
# lane-trigger.sh: arranca un daemon de LANE si no esta corriendo
# y escribe el trigger correspondiente.
#
# Uso: lane-trigger.sh <app-name> <trigger-file>
# Ejemplo: lane-trigger.sh logout /tmp/lane-logout.cmd
#
# Detecta si LANE esta instalado en /opt/lane o si corre desde
# ~/proyectos/lane. Prioriza /opt para produccion.

APP="$1"
TRIGGER="$2"

if [ -z "$APP" ] || [ -z "$TRIGGER" ]; then
    echo "uso: $0 <app-name> <trigger-file>" >&2
    exit 1
fi

if [ -d "/opt/lane" ] && [ -x "/opt/lane/run" ]; then
    LANE_DIR="/opt/lane"
else
    LANE_DIR="$HOME/proyectos/lane"
fi

if [ ! -x "$LANE_DIR/run" ]; then
    echo "lane-trigger: no se encontro $LANE_DIR/run" >&2
    exit 1
fi

if ! pgrep -f "apps/$APP.lua" > /dev/null 2>&1; then
    nohup "$LANE_DIR/run" "apps/$APP.lua" \
        > "/tmp/lane-$APP.log" 2>&1 &
    sleep 0.6
fi

echo toggle > "$TRIGGER"
