#!/usr/bin/env bash
# Usuarios y roles (hardening punto 7 y RBAC de la seccion 7).
# Las contrasenas vienen de .env, nunca quedan escritas en el repositorio.
set -euo pipefail
export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"

for v in AGENTE_IA_PASSWORD GERENTE_DB_PASSWORD TI_DB_PASSWORD AUDITOR_DB_PASSWORD; do
  if [ -z "${!v:-}" ]; then echo "Falta la variable $v en .env" >&2; exit 1; fi
done

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v db="$POSTGRES_DB" \
  -v agente_pw="$AGENTE_IA_PASSWORD" \
  -v gerente_pw="$GERENTE_DB_PASSWORD" \
  -v ti_pw="$TI_DB_PASSWORD" \
  -v auditor_pw="$AUDITOR_DB_PASSWORD" <<'SQL'

-- Nadie hereda permisos por defecto sobre el esquema public
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;

-- ===== Punto 7: agente_ia solo lectura =====
-- Usuario del agente de IA (bot de Telegram). Solo SELECT en tablas de negocio,
-- sin acceso a auditoria ni a las tablas de seguridad.
CREATE ROLE agente_ia LOGIN PASSWORD :'agente_pw' CONNECTION LIMIT 5;
GRANT CONNECT ON DATABASE :"db" TO agente_ia;
GRANT USAGE ON SCHEMA public TO agente_ia;
GRANT SELECT ON plantas, productos, materias_primas, lotes_produccion,
                clientes, ventas, control_calidad, gastos TO agente_ia;
ALTER ROLE agente_ia SET statement_timeout = '30s';

-- ===== RBAC: tres roles (seccion 7) =====
CREATE ROLE rol_gerente NOLOGIN;
CREATE ROLE rol_ti      NOLOGIN;
CREATE ROLE rol_auditor NOLOGIN;

-- Gerente: solo tablas de reportes, sin auditoria
GRANT CONNECT ON DATABASE :"db" TO rol_gerente;
GRANT USAGE ON SCHEMA public TO rol_gerente;
GRANT SELECT ON ventas, clientes, productos, lotes_produccion TO rol_gerente;

-- TI: lectura total + escritura en backups y alertas. Tambien es el usuario de los flujos de N8N.
GRANT CONNECT ON DATABASE :"db" TO rol_ti;
GRANT USAGE ON SCHEMA public TO rol_ti;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO rol_ti;
GRANT INSERT ON backups, alertas_auditoria TO rol_ti;
GRANT USAGE ON SEQUENCE backups_id_seq, alertas_auditoria_id_seq TO rol_ti;
GRANT pg_monitor TO rol_ti;   -- pg_stat_statements, pg_stat_activity, pg_settings de todos

-- Auditor: solo tablas de monitoreo y vistas de estadisticas
GRANT CONNECT ON DATABASE :"db" TO rol_auditor;
GRANT USAGE ON SCHEMA public TO rol_auditor;
GRANT SELECT ON auditoria_datos, backups, alertas_auditoria TO rol_auditor;
GRANT pg_read_all_stats TO rol_auditor;

CREATE ROLE gerente_db LOGIN PASSWORD :'gerente_pw' IN ROLE rol_gerente;
CREATE ROLE ti_db      LOGIN PASSWORD :'ti_pw'      IN ROLE rol_ti;
CREATE ROLE auditor_db LOGIN PASSWORD :'auditor_pw' IN ROLE rol_auditor;
SQL

echo "[05-roles] agente_ia, rol_gerente, rol_ti, rol_auditor creados"
