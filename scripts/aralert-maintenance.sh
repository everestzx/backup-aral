#!/bin/bash
# Purpose: Toggle ARALert maintenance mode on or off via Nginx 503 response
# Authors: ARALert Group (Leinardt Omadto, Nyan Jean Alcovindas, Jorge Benidict Licup)
# Usage:   sudo ./aralert-maintenance.sh on|off|status|--help
# Note:    Drafted with AI assistance; reviewed and tested by the group.

if [ "$1" = "--help" ]; then
    echo "Usage: sudo $0 on|off|status"
    echo "Options:"
    echo "  on      Show users the 'temporarily unavailable' message (HTTP 503)"
    echo "  off     Return ARALert to normal operation"
    echo "  status  Check whether maintenance mode is on or off"
    echo "  --help  Show this help message"
    echo "Example: sudo ./scripts/aralert-maintenance.sh on"
    exit 0
fi

if [ `id -u` -ne 0 ]; then
    echo "Error: Please run as root (use sudo)."
    exit 1
fi

if [ ! -f /etc/aralert.conf ]; then
    echo "Error: /etc/aralert.conf not found. Run aralert-install.sh first."
    exit 1
fi
. /etc/aralert.conf
FLAG="$APP_DIR/maintenance.flag"

case "$1" in
    on)
        service nginx start
        touch "$FLAG" && chmod 644 "$FLAG"
        echo "Maintenance mode ON: server now shows the temporarily unavailable message."
        exit 0
        ;;
    off)
        rm -f "$FLAG"
        echo "Maintenance mode OFF: ARALert is back online."
        exit 0
        ;;
    status)
        if [ -f "$FLAG" ]; then
            echo "Maintenance mode is ON."
        else
            echo "Maintenance mode is OFF."
        fi
        exit 0
        ;;
    *)
        echo "Usage: sudo $0 on|off|status (try --help)"
        exit 1
        ;;
esac
