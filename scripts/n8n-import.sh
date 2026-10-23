#!/usr/bin/env bash
# Crea las credenciales de N8N desde .env e importa los flujos de n8n/workflows.
# Las credenciales se pasan por stdin al contenedor: no quedan en disco ni en el repositorio.
# Ejecutar despues de "docker compose up -d". Se puede repetir: sobrescribe por id.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

C=nutri_n8n
docker exec "$C" true 2>/dev/null || { echo "El contenedor $C no esta corriendo"; exit 1; }

echo "[1/3] Credenciales (Postgres ti_db y Telegram)"
docker exec -i "$C" sh -c 'umask 077; cat > /tmp/cred.json' <<JSON
[
  {
    "id": "nutriPgTi01",
    "name": "Postgres ti_db",
    "type": "postgres",
    "data": {
      "host": "postgres",
      "port": 5432,
      "database": "${POSTGRES_DB}",
      "user": "ti_db",
      "password": "${TI_DB_PASSWORD}",
      "ssl": "require",
      "allowUnauthorizedCerts": true
    }
  },
  {
    "id": "nutriTelegram01",
    "name": "Telegram NutriAnimales",
    "type": "telegramApi",
    "data": { "accessToken": "${TELEGRAM_BOT_TOKEN}" }
  }
]
JSON
docker exec "$C" sh -c 'n8n import:credentials --input=/tmp/cred.json; rm -f /tmp/cred.json'

echo "[2/3] Flujos"
IDS=$(grep -ho '"id": "nutri[A-Za-z0-9]*"' n8n/workflows/*.json | cut -d'"' -f4 | grep -vE 'Pg|Telegram')
for id in $IDS; do   # un flujo publicado no se puede sobrescribir: despublicar primero (repetible)
  docker exec "$C" n8n unpublish:workflow --id="$id" >/dev/null 2>&1 || true
done
for f in n8n/workflows/*.json; do
  docker cp "$f" "$C:/tmp/wf.json"
  docker exec "$C" sh -c 'n8n import:workflow --input=/tmp/wf.json && rm -f /tmp/wf.json'
done

echo "[3/3] Publicacion"
for id in $IDS; do
  docker exec "$C" n8n publish:workflow --id="$id" >/dev/null 2>&1 \
    || echo "  [!] No se pudo publicar $id. Activelo desde la interfaz de N8N."
done
docker restart "$C" >/dev/null
echo "[ok] Flujos importados y activados. N8N se reinicio para cargarlos."
