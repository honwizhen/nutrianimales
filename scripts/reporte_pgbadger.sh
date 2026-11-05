#!/usr/bin/env bash
# Genera reportes/pgbadger.html con pgBadger a partir de los logs de nutri_postgres.
# Con logging_collector=off y log_destination=stderr, los logs son los del contenedor (docker logs).
# Uso: ./scripts/reporte_pgbadger.sh
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

CONTENEDOR=nutri_postgres
# dalibo/pgbadger no se actualiza desde 2018 (10.1, solo amd64). Esta es 13.1, con arm64, fijada por digest.
IMAGEN=matsuu/pgbadger:13.1@sha256:5c97109788ecb353391fab18aa03c10ffeeeb2fcf491fa8fb81c29dd1ae8660c
SALIDA=reportes/pgbadger.html

umask 077
mkdir -p reportes
LOG_TEMP=reportes/.postgres-sanitizado.log
trap 'rm -f "$LOG_TEMP"' EXIT

export PGPASSWORD="$POSTGRES_PASSWORD"
ajuste() {
  docker exec -e PGPASSWORD -e PGSSLMODE=require "$CONTENEDOR" \
    psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SHOW $1"
}

if [ "$(ajuste logging_collector)" != "off" ] || [ "$(ajuste log_destination)" != "stderr" ]; then
  echo "Este script espera logging_collector=off y log_destination=stderr." >&2
  exit 1
fi
PREFIJO=$(ajuste log_line_prefix)   # el prefijo real, para no duplicar el de postgresql.conf

# log_statement=ddl deja en el log el CREATE ROLE ... PASSWORD de 05-roles.sh en texto plano.
# Se enmascara antes de que el log llegue a pgBadger.
docker logs "$CONTENEDOR" 2>&1 \
  | sed -E "s/([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][[:space:]]+)'[^']*'/\1'***'/g" > "$LOG_TEMP"

# Imagen de terceros: sin red, raiz de solo lectura y sin root.
docker run --rm --network none --read-only --tmpfs /tmp --user "$(id -u):$(id -g)" \
  -v "$PWD/reportes:/reportes" "$IMAGEN" \
  -f stderr -p "$PREFIJO" -o "/reportes/$(basename "$SALIDA")" "/reportes/$(basename "$LOG_TEMP")"
chmod 600 "$SALIDA"

# Si una contrasena de .env llego al reporte, no se conserva.
for v in POSTGRES_PASSWORD AGENTE_IA_PASSWORD GERENTE_DB_PASSWORD TI_DB_PASSWORD AUDITOR_DB_PASSWORD APP_PRODUCCION_PASSWORD; do
  if grep -qF "${!v}" "$SALIDA"; then
    rm -f "$SALIDA"
    echo "ERROR: el reporte contenia el valor de $v; se elimino." >&2
    exit 1
  fi
done

LENTAS=$(grep -c 'duration: ' "$LOG_TEMP" || true)
echo "[ok] $SALIDA ($LENTAS consultas de 1 s o mas en el log)"
[ "$LENTAS" -gt 0 ] || echo "[!] Sin consultas lentas: corra ./scripts/carga_pgbench.sh --lenta"
