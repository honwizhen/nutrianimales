#!/usr/bin/env bash
# Imprime la evidencia de los 12 puntos de hardening. Tome una captura por cada bloque.
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
PSQL="docker exec -e PGPASSWORD=$POSTGRES_PASSWORD nutri_postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -tAc"

echo "== 1. Usuario no-root =="
for c in nutri_n8n nutri_pgadmin; do printf '%s: ' "$c"; docker exec "$c" whoami; done
echo; echo "== 2. .env con chmod 600 =="; ls -la .env
echo; echo "== 3. Red aislada =="; docker network inspect nutrianimales-net | head -n 30
echo; echo "== 4. PostgreSQL sin puerto expuesto =="; docker compose ps
echo; echo "== 5. scram-sha-256 =="; $PSQL "SHOW password_encryption;"
echo; echo "== 6. SSL en PostgreSQL =="; $PSQL "SHOW ssl;"
echo; echo "== 7. agente_ia solo lectura (requiere que el rol exista) =="
echo "   Ejecute: INSERT con agente_ia -> debe fallar con 'permission denied'"
echo; echo "== 8. Headers de Nginx =="; curl -skI https://localhost:8443
echo; echo "== 9. Certificado de Nginx =="; echo | openssl s_client -connect localhost:8443 2>/dev/null | openssl x509 -noout -subject -dates
echo; echo "== 10. Volumenes 700 =="; ls -la data/
echo; echo "== 11. Logs de auditoria / pg_stat_statements =="
$PSQL "SHOW log_min_duration_statement;"
$PSQL "SHOW shared_preload_libraries;"
echo; echo "== 12. pg_settings_baseline (se crea en la fase de alertas) =="
$PSQL "SELECT * FROM pg_settings_baseline;" || true
