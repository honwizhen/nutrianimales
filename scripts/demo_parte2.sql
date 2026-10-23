-- Evidencia de la parte 2: triggers de auditoria y RBAC del gerente.
-- Tome una captura por bloque.
--
-- Uso (desde la raiz del proyecto):
--   set -a; . ./.env; set +a
--   docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" -e PGSSLMODE=require nutri_postgres \
--     psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
--     -v gerente_pw="$GERENTE_DB_PASSWORD" < scripts/demo_parte2.sql
--
-- Los bloques 1 y 2 corren como postgres: ti_db solo tiene SELECT sobre lotes_produccion.

\pset pager off
\echo '================ 1. UPDATE y DELETE en lotes_produccion ================'
SELECT session_user, current_user;

UPDATE lotes_produccion
SET estado = 'retenido', cantidad_producida = cantidad_producida + 1
WHERE codigo = 'LOT-2026-0001';

-- Se borra un lote sin control de calidad asociado (la FK impediria borrar los otros)
DELETE FROM lotes_produccion
WHERE id = (SELECT max(l.id) FROM lotes_produccion l
            WHERE NOT EXISTS (SELECT 1 FROM control_calidad c WHERE c.lote_id = l.id));

\echo '================ 2. Registro en auditoria_datos ================'
\x on
SELECT id, tabla, operacion, usuario, fecha, fila_id, valor_antes, valor_nuevo
FROM auditoria_datos
WHERE tabla = 'lotes_produccion'
ORDER BY id DESC
LIMIT 2;
\x off

\echo '================ 3. gerente_db intenta leer auditoria_datos ================'
\setenv PGPASSWORD :gerente_pw
\connect - gerente_db
SELECT session_user, current_user;
-- Debe fallar con: permission denied for table auditoria_datos
SELECT * FROM auditoria_datos LIMIT 1;
-- Tampoco puede leer las tablas de negocio directamente
SELECT count(*) FROM ventas;
-- Solo las vistas de reportes
SELECT * FROM v_produccion_por_planta ORDER BY planta, estado;
