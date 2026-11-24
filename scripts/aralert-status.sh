#!/bin/bash
# Purpose: Report ARALert running state, listening ports, and CPU/memory/disk usage
# Authors: ARALert Group (Leinardt Omadto, Nyan Jean Alcovindas, Jorge Benidict Licup)
# Usage:   sudo ./aralert-status.sh [--help]
# Note:    Drafted with AI assistance; reviewed and tested by the group.

if [ "$1" = "--help" ]; then
    echo "Usage: sudo $0 [--help]"
    echo "Reports whether ARALert and dependent services are running, listening ports,"
    echo "and CPU, memory, and disk usage."
    echo "Example: sudo ./scripts/aralert-status.sh"
    exit 0
fi

if [ `id -u` -ne 0 ]; then
    echo "Error: Please run as root (use sudo) to inspect all listening ports."
    exit 1
fi

if [ ! -f /etc/aralert.conf ]; then
    echo "Error: /etc/aralert.conf not found. Run aralert-install.sh first."
    exit 1
fi
. /etc/aralert.conf
PID_FILE="/run/aralert.pids"

echo "=== Dependent Services ==="
for SVC in postgresql nginx; do
    if service "$SVC" status > /dev/null 2>&1; then
        echo "$SVC: running"
    else
        echo "$SVC: stopped"
    fi
done

echo "=== Maintenance Mode ==="
if [ -f "$APP_DIR/maintenance.flag" ]; then
    echo "Maintenance: ON (503 message active)"
else
    echo "Maintenance: OFF"
fi

echo "=== ARALert Application Status ==="
if [ ! -f "$PID_FILE" ]; then
    echo "ARALert: STOPPED"
    exit 1
fi

PIDS=`cat "$PID_FILE"`
ALIVE=0
for P in $PIDS; do
    if kill -0 "$P" 2>/dev/null; then
        STATE=`ps -p "$P" -o stat= | grep -o "^."`
        if [ "$STATE" = "T" ]; then
            echo "Process $P: PAUSED (STOP signal)"
        else
            echo "Process $P: RUNNING"
        fi
        ps -p "$P" -o pid,stat,%cpu,%mem,comm
        ALIVE=$(( $ALIVE + 1 ))
    fi
done

if [ $ALIVE -eq 0 ]; then
    echo "ARALert: STOPPED"
    exit 1
fi

echo "=== Listening Ports ==="
ss -tlnp | grep -E ":($WEB_PORT|$APP_PORT|$FE_PORT)\b" > /tmp/aralert-ports.txt
cat /tmp/aralert-ports.txt

echo "=== System Memory and Disk ==="
free -h
df -h /
exit 0
