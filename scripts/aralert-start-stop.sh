#!/bin/bash
# Purpose: Start and stop ARALert and its dependent services in the correct order
# Authors: ARALert Group (Leinardt Omadto, Nyan Jean Alcovindas, Jorge Benidict Licup)
# Usage:   sudo ./aralert-start-stop.sh start|stop|--help
# Note:    Drafted with AI assistance; reviewed and tested by the group.

if [ "$1" = "--help" ]; then
    echo "Usage: sudo $0 start|stop"
    echo "Options:"
    echo "  start   Start PostgreSQL, ARALert processes, and Nginx in order"
    echo "  stop    Stop Nginx, ARALert processes, and PostgreSQL in reverse order"
    echo "  --help  Show this help message"
    echo "Example: sudo ./scripts/aralert-start-stop.sh start"
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
PID_FILE="/run/aralert.pids"

case "$1" in
    start)
        if [ -f "$PID_FILE" ]; then
            for P in `cat "$PID_FILE"`; do
                if kill -0 "$P" 2>/dev/null; then
                    echo "Error: ARALert is already running (PID $P). Refusing to start a second copy."
                    exit 1
                fi
            done
            rm -f "$PID_FILE"
        fi

        echo "1. Starting PostgreSQL..."
        service postgresql start

        echo "2. Starting ARALert backend and frontend..."
        nohup "$APP_DIR/backend/venv/bin/python" "$APP_DIR/backend/manage.py" runserver "127.0.0.1:$APP_PORT" --noreload --insecure > /var/log/aralert-backend.log 2>&1 &
        BE_PID=$!
        nohup python3 -m http.server "$FE_PORT" --bind 127.0.0.1 --directory "$APP_DIR/frontend/dist" > /var/log/aralert-frontend.log 2>&1 &
        FE_PID=$!
        echo "$BE_PID $FE_PID" > "$PID_FILE"

        TRIES=0
        OK=0
        while [ $TRIES -lt 6 -a $OK -eq 0 ]; do
            sleep 1
            if curl -sf "http://127.0.0.1:$APP_PORT/api/health/" > /dev/null; then
                OK=1
            fi
            TRIES=$(( $TRIES + 1 ))
        done

        if [ $OK -eq 0 ]; then
            echo "Error: ARALert backend failed to start. Check /var/log/aralert-backend.log"
            exit 1
        fi

        echo "3. Starting Nginx..."
        service nginx restart
        echo "ARALert started (PIDs: $BE_PID $FE_PID)."
        exit 0
        ;;
    stop)
        echo "1. Stopping Nginx..."
        service nginx stop

        echo "2. Stopping ARALert processes..."
        if [ -f "$PID_FILE" ]; then
            for P in `cat "$PID_FILE"`; do
                kill -CONT "$P" 2>/dev/null
                kill "$P" 2>/dev/null
            done
            rm -f "$PID_FILE"
            sleep 1
        fi

        echo "3. Stopping PostgreSQL..."
        service postgresql stop
        echo "ARALert and dependent services stopped."
        exit 0
        ;;
    *)
        echo "Usage: sudo $0 start|stop (try --help)"
        exit 1
        ;;
esac
