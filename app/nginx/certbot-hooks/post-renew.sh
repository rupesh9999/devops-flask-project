#!/bin/bash
# Certbot deploy hook to reload Nginx after certificate renewal
set -euo pipefail
systemctl reload nginx
