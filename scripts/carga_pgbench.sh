#!/usr/bin/env bash
# Carga de prueba con pgbench dentro de nutri_postgres (esquema bench, 10 clientes, 60 s).
# Uso: ./scripts/carga_pgbench.sh           carga normal
#      ./scripts/carga_pgbench.sh --lenta   ademas, una consulta de 1.5 s a mitad de la carga (R1)
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

CONTENEDOR=nutri_postgres
CLIENTES=10
DURACION=60
ESCALA=10   # 1 millon de filas; con escala < clientes todos compiten por las mismas filas

LENTA=0
case "${1:-}" in
  "") ;;
  --lenta) LENTA=1 ;;
  *) echo "Uso: $0 [--lenta]" >&2; exit 2 ;;
esac

# La contrasena viaja por el entorno, no por la linea de comandos (visible en ps).
# Conexion TLS por la red Docker, igual que verify.sh: pg_hba solo acepta hostssl.
export PGPASSWORD="$POSTGRES_PASSWORD"
PG=(docker exec -i -e PGPASSWORD -e PGSSLMODE=require -e "PGOPTIONS=-c search_path=bench" "$CONTENEDOR")
CONEXION=(-h postgres -U "$POSTGRES_USER")   # la base va al final: en pgbench, -d es modo debug

echo "[1/3] Inicializando tablas de pgbench en el esquema bench (escala $ESCALA)"
"${PG[@]}" psql "${CONEXION[@]}" -v ON_ERROR_STOP=1 -q -c "CREATE SCHEMA IF NOT EXISTS bench;" "$POSTGRES_DB"
"${PG[@]}" pgbench "${CONEXION[@]}" -i -q -s "$ESCALA" "$POSTGRES_DB"

PID_LENTA=""
if [ "$LENTA" -eq 1 ]; then
  # Supera log_min_duration_statement (1 s): queda en los logs y en pg_stat_statements.
  (
    sleep $((DURACION / 2))
    "${PG[@]}" psql "${CONEXION[@]}" -v ON_ERROR_STOP=1 -c \
      "/* carga_pgbench: consulta lenta R1 */ SELECT pg_sleep(1.5), count(*) FROM public.ventas;" "$POSTGRES_DB" >/dev/null
    echo "[--lenta] Consulta lenta ejecutada"
  ) &
  PID_LENTA=$!
fi

echo "[2/3] pgbench: $CLIENTES clientes durante $DURACION s"
"${PG[@]}" pgbench "${CONEXION[@]}" -c "$CLIENTES" -j 2 -T "$DURACION" -P 10 "$POSTGRES_DB"

if [ -n "$PID_LENTA" ]; then
  wait "$PID_LENTA"
  echo "--- Consulta lenta en los logs de Postgres:"
  docker logs "$CONTENEDOR" 2>&1 | grep 'duration:.*pg_sleep' | tail -1
fi

# Sin pg_stat_statements_reset(): otras alertas leen estas estadisticas, asi que son acumuladas.
echo "[3/3] Consultas mas lentas de pg_stat_statements (promedio, acumulado)"
"${PG[@]}" psql "${CONEXION[@]}" -v ON_ERROR_STOP=1 -P pager=off "$POSTGRES_DB" <<'SQL'
SELECT calls,
       round(mean_exec_time::numeric, 2) AS promedio_ms,
       round(max_exec_time::numeric, 2)  AS maximo_ms,
       left(regexp_replace(query, '\s+', ' ', 'g'), 80) AS consulta
FROM public.pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY mean_exec_time DESC
LIMIT 10;
SQL
