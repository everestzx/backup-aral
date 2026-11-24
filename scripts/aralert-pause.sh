#!/bin/bash
# Purpose: Pause (kill -STOP) and resume (kill -CONT) ARALert processes
# Authors: ARALert Group (Leinardt Omadto, Nyan Jean Alcovindas, Jorge Benidict Licup)
# Usage:   sudo ./aralert-pause.sh pause|resume|--help
# Note:    Drafted with AI assistance; reviewed and tested by the group.

if [ "$1" = "--help" ]; then
    echo "Usage: sudo $0 pause|resume"
    echo "Options:"
    echo "  pause   Freeze ARALert processes with kill -STOP (nothing responds)"
    echo "  resume  Unfreeze ARALert processes with kill -CONT"
    echo "  --help  Show this help message"
    echo "Example: sudo ./scripts/aralert-pause.sh pause"
    exit 0
fi

if [ `id -u` -ne 0 ]; then
    echo "Error: Please run as root (use sudo)."
    exit 1
fi

PID_FILE="/run/aralert.pids"
if [ ! -f "$PID_FILE" ]; then
    echo "Error: ARALert is not running."
    exit 1
fi
PIDS=`cat "$PID_FILE"`

case "$1" in
    pause)
        for P in $PIDS; do
            kill -STOP "$P"
            if [ $? -ne 0 ]; then
                echo "Error: Failed to pause PID $P."
                exit 1
            fi
        done
        echo "ARALert paused (PIDs: $PIDS). Process is frozen until resumed."
        exit 0
        ;;
    resume)
        for P in $PIDS; do
            kill -CONT "$P"
            if [ $? -ne 0 ]; then
                echo "Error: Failed to resume PID $P."
                exit 1
            fi
        done
        echo "ARALert resumed (PIDs: $PIDS). Application is responding again."
        exit 0
        ;;
    *)
        echo "Usage: sudo $0 pause|resume (try --help)"
        exit 1
        ;;
esac
