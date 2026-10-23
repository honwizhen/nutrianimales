#!/usr/bin/env bash
# Genera certificados autofirmados para Nginx y PostgreSQL (hardening puntos 6 y 9).
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p nginx/certs postgres/certs

for svc in nginx postgres; do
  if [ -f "$svc/certs/server.crt" ]; then
    echo "[skip] $svc/certs ya existe"
    continue
  fi
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "$svc/certs/server.key" -out "$svc/certs/server.crt" \
    -subj "/C=CR/O=NutriAnimales S.A./CN=${svc}.nutrianimales-net" \
    -addext "subjectAltName=DNS:localhost,DNS:${svc},IP:127.0.0.1" 2>/dev/null
  chmod 600 "$svc/certs/server.key"
  chmod 644 "$svc/certs/server.crt"
  echo "[ok] $svc/certs"
done

# PostgreSQL exige que la llave sea del usuario postgres (uid 999 en la imagen oficial) con modo 600
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
$SUDO chown 999:999 postgres/certs/server.key postgres/certs/server.crt
