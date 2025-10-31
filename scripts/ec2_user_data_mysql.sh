#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y mysql-server

cat <<'EOF' > /etc/mysql/mysql.conf.d/99-custom.cnf
[mysqld]
bind-address = 0.0.0.0
skip-name-resolve
EOF

systemctl enable mysql
systemctl restart mysql

mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS ${db_name};
CREATE USER IF NOT EXISTS '${db_username}'@'${db_allowed_host_pattern}' IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_username}'@'${db_allowed_host_pattern}';
FLUSH PRIVILEGES;
SQL

cat <<'EOT' > /root/mysql-hardening.txt
Recommended manual hardening steps:
 1. Run mysql_secure_installation to set the root password and remove anonymous users.
 2. Restrict root remote access if not required.
 3. Configure automated backups or snapshots.
EOT
