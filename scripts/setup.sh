#!/usr/bin/env bash
# Prepara .env, directorios de volumenes, permisos y certificados.
# Ejecutar una vez antes de "docker compose up -d".
set -euo pipefail
cd "$(dirname "$0")/.."

SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# 1. .env con contrasenas aleatorias (hardening 2)
if [ ! -f .env ]; then
  cp .env.example .env
  while grep -q '=change_me$' .env; do
    var=$(grep -m1 '=change_me$' .env | cut -d= -f1)
    sed -i "s|^${var}=change_me$|${var}=$(openssl rand -hex 24)|" .env
  done
  echo "[ok] .env creado con contrasenas aleatorias. Agregue GROQ_API_KEY y los datos de Telegram."
fi
chmod 600 .env

# 2. Volumenes con permisos restringidos (hardening 10)
mkdir -p data/postgres data/n8n data/pgadmin data/loki data/alloy
$SUDO chown -R 1000:1000   data/n8n data/pgadmin data/alloy   # usuarios no-root (hardening 1)
$SUDO chown -R 10001:10001 data/loki                           # usuario de la imagen de Loki
$SUDO chmod 700 data/postgres data/n8n data/pgadmin data/loki data/alloy

# 3. Certificados (hardening 6 y 9)
bash ./scripts/gen-certs.sh

# 4. Rotacion de logs: auth.log y ufw.log deben existir para Alloy (H1)
[ -f /var/log/ufw.log ]  || echo "[!] /var/log/ufw.log no existe. Ejecute: sudo ufw enable && sudo ufw logging on"
[ -f /var/log/auth.log ] || echo "[!] /var/log/auth.log no existe. Instale rsyslog: sudo apt install rsyslog"

echo "[ok] Listo. Siguiente paso: docker compose up -d"
