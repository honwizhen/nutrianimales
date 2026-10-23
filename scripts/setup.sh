#!/usr/bin/env bash
# Prepara .env, directorios de volumenes y permisos. Ejecutar una vez antes de "docker compose up -d".
set -euo pipefail
cd "$(dirname "$0")/.."

SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# 1. .env
if [ ! -f .env ]; then
  cp .env.example .env
  # Llave de cifrado de N8N generada al azar
  KEY=$(openssl rand -hex 32)
  sed -i "s|^N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=${KEY}|" .env
  echo "[!] .env creado desde .env.example. Edite las contrasenas antes de continuar."
fi
chmod 600 .env

# 2. Volumenes con permisos restringidos
mkdir -p data/postgres data/n8n data/pgadmin
$SUDO chown -R 1000:1000 data/n8n data/pgadmin   # usuarios no-root (user: 1000:1000)
chmod 700 data/postgres data/n8n data/pgadmin

# 3. Certificados
bash ./scripts/gen-certs.sh

echo "[ok] Listo. Siguiente paso: docker compose up -d"
