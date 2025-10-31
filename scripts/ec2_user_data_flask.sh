#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv python3-pip nginx git ufw \
  software-properties-common certbot python3-certbot-nginx mysql-client

APP_DIR="/opt/flask-app"
REPO_URL="${repo_url}"
DB_NAME="${db_name}"
DB_USERNAME="${db_username}"
DB_PASSWORD="${db_password}"
DB_HOST="${db_host}"
DOMAIN_NAME="${domain_name}"
ACME_EMAIL="${acme_email}"
PROJECT_NAME="${project_name}"
ENVIRONMENT="${environment}"
SERVICE_NAME="flask-app"
IP_ALLOWLIST="${ip_allowlist}"
ALLOWLIST_FILE="/etc/nginx/ip-allowlist.conf"

mkdir -p "${APP_DIR}"
if [ ! -d "${APP_DIR}/.git" ]; then
  git clone "${REPO_URL}" "${APP_DIR}"
else
  cd "${APP_DIR}" && git pull --rebase
fi

cd "${APP_DIR}/app/flask_app"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

deactivate

cat <<ENVVARS > /etc/flask-app.env
DATABASE_URL="mysql+pymysql://${DB_USERNAME}:${DB_PASSWORD}@${DB_HOST}:3306/${DB_NAME}"
FLASK_ENV="${ENVIRONMENT}"
ENVVARS

cat <<'UNIT' > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=Gunicorn instance to serve Flask app
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/opt/flask-app/app/flask_app
EnvironmentFile=/etc/flask-app.env
ExecStart=/opt/flask-app/app/flask_app/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:8000 app:app
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

mkdir -p /var/log/flask-app
chown www-data:www-data /var/log/flask-app

cat <<'NGINX' > /etc/nginx/sites-available/flask-app
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name SERVER_NAME_PLACEHOLDER;

    access_log /var/log/nginx/flask_access.log;
    error_log /var/log/nginx/flask_error.log;

    location /healthz {
        return 200 'ok';
        add_header Content-Type text/plain;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $$host;
        proxy_set_header X-Real-IP $$remote_addr;
        proxy_set_header X-Forwarded-For $$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $$scheme;

        include /etc/nginx/ip-allowlist.conf;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/flask-app /etc/nginx/sites-enabled/flask-app
rm -f /etc/nginx/sites-enabled/default

SERVER_NAME_VALUE="${DOMAIN_NAME:-_}"
sed -i "s/SERVER_NAME_PLACEHOLDER/${SERVER_NAME_VALUE}/" /etc/nginx/sites-available/flask-app

echo "allow all;" > "${ALLOWLIST_FILE}"
if [ -n "${IP_ALLOWLIST}" ]; then
  IFS=',' read -ra ADDR <<< "${IP_ALLOWLIST}"
  : > "${ALLOWLIST_FILE}"
  for ip in "${ADDR[@]}"; do
    CLEANED_IP=$(echo "$ip" | xargs)
    if [ -n "${CLEANED_IP}" ]; then
      echo "allow ${CLEANED_IP};" >> "${ALLOWLIST_FILE}"
    fi
  done
  echo "deny all;" >> "${ALLOWLIST_FILE}"
fi

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}

nginx -t
systemctl restart nginx

if [ -n "${DOMAIN_NAME}" ] && [ -n "${ACME_EMAIL}" ]; then
  certbot --nginx --non-interactive --agree-tos --redirect -m "${ACME_EMAIL}" -d "${DOMAIN_NAME}"
fi

ufw allow "Nginx Full"
ufw allow OpenSSH || true
echo "y" | ufw enable
