#!/usr/bin/env bash
# Evidencia de los 12 puntos de hardening (seccion 10). Tome una captura por bloque.
# Uso: ./scripts/verify.sh            (todos)
#      ./scripts/verify.sh 7          (solo el punto 7)
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

# psql dentro del contenedor, por TLS como lo haria un cliente de la red Docker
sql() { # usuario contrasena consulta
  docker exec -e PGPASSWORD="$2" -e PGSSLMODE=require nutri_postgres \
    psql -h postgres -U "$1" -d "$POSTGRES_DB" -c "$3" 2>&1
}
PG() { sql "$POSTGRES_USER" "$POSTGRES_PASSWORD" "$1"; }
hdr() { echo; echo "================ $1 ================"; echo "\$ $2"; }
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
ONLY="${1:-}"

if want 1; then hdr "1. Usuario no-root" "docker exec <c> whoami / id"
  for c in nutri_n8n nutri_pgadmin; do printf '%-14s ' "$c:"; docker exec "$c" sh -c 'echo "$(whoami 2>/dev/null || echo uid) -> $(id)"'; done
fi
if want 2; then hdr "2. .env con chmod 600 y en .gitignore" "ls -la .env; grep -n '^.env$' .gitignore"
  ls -la .env; grep -n '^\.env$' .gitignore
fi
if want 3; then hdr "3. Red Docker aislada" "docker network inspect nutrianimales-net"
  docker network inspect nutrianimales-net --format '{{.Name}} driver={{.Driver}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}}'
  docker network inspect nutrianimales-net --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{println}}{{end}}'
fi
if want 4; then hdr "4. PostgreSQL sin puerto expuesto" "docker compose ps"
  docker compose ps --format 'table {{.Name}}\t{{.State}}\t{{.Ports}}'
fi
if want 5; then hdr "5. scram-sha-256" "SHOW password_encryption;"
  PG "SHOW password_encryption;"
  PG "SELECT rolname, left(rolpassword, 14) AS hash FROM pg_authid WHERE rolpassword IS NOT NULL;"
fi
if want 6; then hdr "6. SSL/TLS en PostgreSQL" "SHOW ssl;"
  PG "SHOW ssl;"
  PG "SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();"
fi
if want 7; then hdr "7. agente_ia solo lectura" "INSERT con agente_ia -> permission denied"
  sql agente_ia "$AGENTE_IA_PASSWORD" "SELECT count(*) AS clientes_visibles FROM clientes;"
  sql agente_ia "$AGENTE_IA_PASSWORD" "INSERT INTO clientes (nombre, tipo) VALUES ('prueba', 'persona');"
fi
if want 8; then hdr "8. Headers de seguridad en Nginx" "curl -kI https://localhost:8443"
  curl -skI https://localhost:8443 | grep -iE '^(HTTP|x-frame|x-content|strict-transport|content-security)'
fi
if want 9; then hdr "9. Certificado SSL en Nginx" "openssl s_client -connect localhost:8443"
  echo | openssl s_client -connect localhost:8443 2>/dev/null | openssl x509 -noout -subject -issuer -dates
  echo "(Captura adicional: el candado HTTPS en el navegador en https://localhost:8443)"
fi
if want 10; then hdr "10. Volumenes con permisos restringidos" "ls -la data/"
  ls -la data/
fi
if want 11; then hdr "11. Logs de auditoria activados" "pg_stat_statements con consultas lentas"
  PG "SHOW log_min_duration_statement;"
  PG "SELECT pg_sleep(1.5);" >/dev/null
  PG "SELECT round(mean_exec_time) AS ms, calls, query FROM pg_stat_statements WHERE mean_exec_time > 1000 ORDER BY mean_exec_time DESC LIMIT 5;"
fi
if want 12; then hdr "12. pg_settings_baseline" "SELECT * FROM pg_settings_baseline; + comparacion H5"
  PG "SELECT * FROM pg_settings_baseline;"
  PG "SELECT b.name, b.valor_esperado, s.setting AS valor_actual, b.valor_esperado = s.setting AS ok FROM pg_settings_baseline b JOIN pg_settings s USING (name);"
fi
