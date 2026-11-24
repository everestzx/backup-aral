#!/bin/bash
# Purpose: Back up ARALert, apply an update folder, and verify the app still works
# Authors: ARALert Group (Leinardt Omadto, Nyan Jean Alcovindas, Jorge Benidict Licup)
# Usage:   sudo ./aralert-update.sh <update-dir> | --help
# Note:    Drafted with AI assistance; reviewed and tested by the group.

if [ "$1" = "--help" ]; then
    echo "Usage: sudo $0 <update-dir>"
    echo "Automatically backs up /opt/aralert, copies files from <update-dir>,"
    echo "restarts ARALert, and verifies /api/health/. Prints manual restore steps on failure."
    echo "Example: sudo ./scripts/aralert-update.sh /tmp/aralert-patch"
    exit 0
fi

if [ `id -u` -ne 0 ]; then
    echo "Error: Please run as root (use sudo)."
    exit 1
fi

if [ $# -lt 1 ]; then
    echo "Error: Provide an update directory (try --help)."
    exit 1
fi

if [ ! -d "$1" ]; then
    echo "Error: Directory $1 does not exist."
    exit 1
fi

if [ ! -f /etc/aralert.conf ]; then
    echo "Error: /etc/aralert.conf not found. Run aralert-install.sh first."
    exit 1
fi
. /etc/aralert.conf

BACKUP_DIR="/var/backups/aralert"
mkdir -p "$BACKUP_DIR"
STAMP=`date +%Y%m%d-%H%M%S`
BACKUP_FILE="$BACKUP_DIR/aralert-backup-$STAMP.tar.gz"
SCRIPT_DIR=`dirname "$0"`

echo "1. Backing up $APP_DIR to $BACKUP_FILE..."
tar -czf "$BACKUP_FILE" -C /opt aralert && tar -tzf "$BACKUP_FILE" > /dev/null
if [ $? -ne 0 ]; then
    echo "Error: Backup creation or verification failed. Update cancelled."
    exit 1
fi
chmod 600 "$BACKUP_FILE"
echo "Backup verified OK."

echo "2. Applying update from $1..."
cp -r "$1"/. "$APP_DIR/"
chown -R www-data:www-data "$APP_DIR"
chmod 600 "$APP_DIR/backend/.env"

echo "3. Restarting ARALert and checking health..."
bash "$SCRIPT_DIR/aralert-start-stop.sh" stop > /dev/null 2>&1
bash "$SCRIPT_DIR/aralert-start-stop.sh" start > /dev/null 2>&1

if curl -sf "http://127.0.0.1:$APP_PORT/api/health/" > /dev/null; then
    echo "SUCCESS: Update applied and ARALert passed health check."
    exit 0
else
    bash "$SCRIPT_DIR/aralert-start-stop.sh" stop > /dev/null 2>&1
    echo "FAILURE: ARALert failed the health check after update! Application stopped."
    echo "Restore the backup manually with this exact command:"
    echo "  sudo rm -rf /opt/aralert && sudo tar -xzf $BACKUP_FILE -C /opt && sudo $SCRIPT_DIR/aralert-start-stop.sh start"
    exit 1
fi
