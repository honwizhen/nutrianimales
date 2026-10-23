-- Evidencia de la parte 2: triggers de auditoria y RBAC.
-- Tome una captura por bloque.
--
-- Uso (desde la raiz del proyecto). La sesion arranca como app_produccion:
--   set -a; . ./.env; set +a
--   docker exec -i -e PGPASSWORD="$APP_PRODUCCION_PASSWORD" -e PGSSLMODE=require nutri_postgres \
--     psql -h postgres -U app_produccion -d "$POSTGRES_DB" \
--     -v auditor_pw="$AUDITOR_DB_PASSWORD" -v gerente_pw="$GERENTE_DB_PASSWORD" \
--     < scripts/demo_parte2.sql
--
-- Bloques 1 y 2: app_produccion modifica lotes y no puede leer la auditoria.
-- Bloque 3: auditor_db (el rol que si puede leer auditoria_datos) muestra los registros.
-- Bloque 4: gerente_db solo ve las vistas de reportes.

\pset pager off
\echo '================ 1. UPDATE y DELETE en lotes_produccion como app_produccion ================'
SELECT session_user, current_user;

UPDATE lotes_produccion
SET estado = 'retenido', cantidad_producida = cantidad_producida + 1
WHERE codigo = 'LOT-2026-0001';

-- Se borra un lote sin control de calidad asociado (la FK impediria borrar los otros)
DELETE FROM lotes_produccion
WHERE id = (SELECT max(l.id) FROM lotes_produccion l
            WHERE NOT EXISTS (SELECT 1 FROM control_calidad c WHERE c.lote_id = l.id));

\echo '================ 2. app_produccion intenta leer auditoria_datos ================'
-- Debe fallar con: permission denied for table auditoria_datos
SELECT * FROM auditoria_datos LIMIT 1;

\echo '================ 3. Registro en auditoria_datos (leido por auditor_db) ================'
\setenv PGPASSWORD :auditor_pw
\connect - auditor_db
SELECT session_user, current_user;
\x on
SELECT id, tabla, operacion, usuario, fecha, fila_id, valor_antes, valor_nuevo
FROM auditoria_datos
WHERE tabla = 'lotes_produccion' AND usuario = 'app_produccion'
ORDER BY id DESC
LIMIT 2;
\x off

\echo '================ 4. gerente_db intenta leer auditoria_datos ================'
\setenv PGPASSWORD :gerente_pw
\connect - gerente_db
SELECT session_user, current_user;
-- Debe fallar con: permission denied for table auditoria_datos
SELECT * FROM auditoria_datos LIMIT 1;
-- Tampoco puede leer las tablas de negocio directamente
SELECT count(*) FROM ventas;
-- Solo las vistas de reportes
SELECT * FROM v_produccion_por_planta ORDER BY planta, estado;
