#!/bin/bash
# Purpose: Install ARALert and its platform (PostgreSQL, Python, Nginx) on Ubuntu/WSL
# Authors: ARALert Group (Leinardt Omadto, Nyan Jean Alcovindas, Jorge Benidict Licup)
# Usage:   sudo ./aralert-install.sh [--help]
# Note:    Drafted with AI assistance; reviewed and tested by the group.

if [ "$1" = "--help" ]; then
    echo "Usage: sudo $0 [--help]"
    echo "Installs PostgreSQL, Python venv, and Nginx, deploys ARALert to /opt/aralert,"
    echo "creates the database, sets permissions, and verifies the app responds."
    echo "Example: sudo ./scripts/aralert-install.sh"
    exit 0
fi

if [ `id -u` -ne 0 ]; then
    echo "Error: Please run as root (use sudo)."
    exit 1
fi

SRC_DIR="."
if [ ! -f "$SRC_DIR/backend/manage.py" ]; then
    SRC_DIR=".."
fi
if [ ! -f "$SRC_DIR/backend/manage.py" ]; then
    echo "Error: Cannot find backend/manage.py. Run from the aralert project folder."
    exit 1
fi

CONF="/etc/aralert.conf"
if [ ! -f "$CONF" ]; then
    echo -n "Enter a new PostgreSQL password for aralert_user: "
    read DB_PASS
    if [ "$DB_PASS" = "" ]; then
        echo "Error: Password cannot be empty."
        exit 1
    fi
    SECRET=`head -c 24 /dev/urandom | base64`
    echo 'APP_DIR="/opt/aralert"' > "$CONF"
    echo 'APP_PORT="8000"' >> "$CONF"
    echo 'FE_PORT="5173"' >> "$CONF"
    echo 'WEB_PORT="80"' >> "$CONF"
    echo 'DB_NAME="aralert"' >> "$CONF"
    echo 'DB_USER="aralert_user"' >> "$CONF"
    echo "DB_PASS=\"$DB_PASS\"" >> "$CONF"
    echo "SECRET_KEY=\"$SECRET\"" >> "$CONF"
    chown root:root "$CONF" && chmod 600 "$CONF"
fi

. "$CONF"

echo "1. Installing required packages..."
apt-get update && apt-get install -y python3 python3-venv python3-pip postgresql nginx curl
if [ $? -ne 0 ]; then
    echo "Error: Package installation failed."
    exit 1
fi

echo "2. Copying application files to $APP_DIR..."
START_DIR=`pwd`
mkdir -p "$APP_DIR/backend" "$APP_DIR/frontend" "$APP_DIR/scripts" /var/backups/aralert
tar --exclude='.venv' --exclude='venv' --exclude='__pycache__' --exclude='.env' -cf - -C "$SRC_DIR/backend" . | tar -xf - -C "$APP_DIR/backend"
cp -r "$SRC_DIR/frontend/dist" "$APP_DIR/frontend/"
cp "$SRC_DIR/scripts/"*.sh "$APP_DIR/scripts/" && chmod +x "$APP_DIR/scripts/"*.sh
echo "<h1>503 Service Unavailable</h1><p>ARALert is temporarily unavailable for maintenance.</p>" > "$APP_DIR/maintenance.html"

echo "3. Configuring PostgreSQL database..."
service postgresql start
su - postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'\" | grep -q 1"
if [ $? -ne 0 ]; then
    su - postgres -c "psql -c \"CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';\""
else
    su - postgres -c "psql -c \"ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';\""
fi
su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'\" | grep -q 1"
if [ $? -ne 0 ]; then
    su - postgres -c "psql -c \"CREATE DATABASE $DB_NAME OWNER $DB_USER;\""
else
    su - postgres -c "psql -c \"ALTER DATABASE $DB_NAME OWNER TO $DB_USER;\""
fi

echo "4. Writing backend environment and running migrations..."
ENV_FILE="$APP_DIR/backend/.env"
echo "SECRET_KEY=$SECRET_KEY" > "$ENV_FILE"
echo "DEBUG=False" >> "$ENV_FILE"
echo "ALLOWED_HOSTS=localhost,127.0.0.1" >> "$ENV_FILE"
echo "USE_SQLITE=False" >> "$ENV_FILE"
echo "DB_NAME=$DB_NAME" >> "$ENV_FILE"
echo "DB_USER=$DB_USER" >> "$ENV_FILE"
echo "DB_PASSWORD=$DB_PASS" >> "$ENV_FILE"
echo "DB_HOST=127.0.0.1" >> "$ENV_FILE"
echo "DB_PORT=5432" >> "$ENV_FILE"

python3 -m venv "$APP_DIR/backend/venv"
"$APP_DIR/backend/venv/bin/pip" install -q -r "$APP_DIR/backend/requirements.txt"
cd "$APP_DIR/backend"
./venv/bin/python manage.py migrate accounts 0007 \
    && PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -f "$APP_DIR/backend/sql/supabase_api_tables.sql" > /dev/null \
    && ./venv/bin/python manage.py migrate \
    && PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -c "ALTER TABLE api_attendance ADD COLUMN IF NOT EXISTS school_year_id BIGINT REFERENCES school_year(id) ON DELETE SET NULL;" > /dev/null \
    && ./venv/bin/python manage.py collectstatic --noinput
if [ $? -ne 0 ]; then
    echo "Error: Database migration or static setup failed."
    exit 1
fi
./venv/bin/python seed_superadmin.py
cd "$START_DIR"

echo "5. Setting ownership and permissions..."
chown -R www-data:www-data "$APP_DIR"
chmod 755 "$APP_DIR"
chmod 600 "$ENV_FILE"

echo "6. Configuring Nginx..."
NGINX_CONF="/etc/nginx/sites-available/aralert"
echo "server {" > "$NGINX_CONF"
echo "    listen $WEB_PORT;" >> "$NGINX_CONF"
echo "    server_name localhost;" >> "$NGINX_CONF"
echo "    error_page 503 /maintenance.html;" >> "$NGINX_CONF"
echo "    location = /maintenance.html { root $APP_DIR; internal; }" >> "$NGINX_CONF"
echo "    location /api/ {" >> "$NGINX_CONF"
echo "        if (-f $APP_DIR/maintenance.flag) { return 503; }" >> "$NGINX_CONF"
echo "        proxy_pass http://127.0.0.1:$APP_PORT;" >> "$NGINX_CONF"
echo '        proxy_set_header Host $host;' >> "$NGINX_CONF"
echo "    }" >> "$NGINX_CONF"
echo "    location / {" >> "$NGINX_CONF"
echo "        if (-f $APP_DIR/maintenance.flag) { return 503; }" >> "$NGINX_CONF"
echo "        proxy_intercept_errors on;" >> "$NGINX_CONF"
echo "        error_page 404 = /index.html;" >> "$NGINX_CONF"
echo "        proxy_pass http://127.0.0.1:$FE_PORT;" >> "$NGINX_CONF"
echo "    }" >> "$NGINX_CONF"
echo "}" >> "$NGINX_CONF"
rm -f /etc/nginx/sites-enabled/default
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/aralert

echo "7. Starting services and verifying health..."
SCRIPT_DIR=`dirname "$0"`
service nginx stop > /dev/null 2>&1
bash "$SCRIPT_DIR/aralert-start-stop.sh" stop > /dev/null 2>&1
bash "$SCRIPT_DIR/aralert-start-stop.sh" start

if curl -sf "http://127.0.0.1:$WEB_PORT/api/health/" > /dev/null; then
    echo "SUCCESS: ARALert is installed and responding at http://localhost:$WEB_PORT"
    exit 0
else
    echo "FAILURE: ARALert did not respond to health check."
    exit 1
fi
