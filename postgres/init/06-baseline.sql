-- Hardening punto 12 y base de las alertas H2 y H5.

-- ===== pg_settings_baseline (H5) =====
CREATE TABLE pg_settings_baseline (
  name           TEXT PRIMARY KEY,
  valor_esperado TEXT NOT NULL,
  descripcion    TEXT
);

INSERT INTO pg_settings_baseline (name, valor_esperado, descripcion) VALUES
  ('ssl',                        'on',                 'TLS obligatorio (hardening 6)'),
  ('ssl_min_protocol_version',   'TLSv1.2',            'Sin TLS 1.0/1.1'),
  ('password_encryption',        'scram-sha-256',      'Sin md5 (hardening 5)'),
  ('log_min_duration_statement', '1000',               'Consultas lentas > 1 s (hardening 11, R1)'),
  ('shared_preload_libraries',   'pg_stat_statements', 'Monitoreo de consultas (R1, D1, D6, D7)'),
  ('log_connections',            'on',                 'Auditoria de conexiones (R4, H4)'),
  ('log_disconnections',         'on',                 'Auditoria de desconexiones'),
  ('log_statement',              'ddl',                'Registro de cambios de esquema');

-- Vista que usa H5: una fila por cada parametro que se desvio del baseline.
-- Incluye reglas de pg_hba con metodo md5/password/trust (degradacion de autenticacion).
CREATE OR REPLACE FUNCTION fn_h5_desviaciones()
RETURNS TABLE (parametro TEXT, valor_esperado TEXT, valor_actual TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT b.name, b.valor_esperado, s.setting
  FROM public.pg_settings_baseline b
  JOIN pg_settings s ON s.name = b.name
  WHERE s.setting IS DISTINCT FROM b.valor_esperado
  UNION ALL
  SELECT 'pg_hba linea ' || r.line_number, 'scram-sha-256 o reject', r.auth_method
  FROM pg_hba_file_rules r
  WHERE r.auth_method IN ('md5', 'password', 'trust');
$$;

-- ===== Hash de archivos de configuracion (H2) =====
CREATE TABLE config_hash_baseline (
  archivo       TEXT PRIMARY KEY,
  hash_esperado TEXT NOT NULL,
  registrado    TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Calcula el MD5 actual de los archivos montados en /etc/postgresql/conf.
-- SECURITY DEFINER para que rol_ti lo ejecute sin ser superusuario.
CREATE OR REPLACE FUNCTION fn_h2_hashes()
RETURNS TABLE (archivo TEXT, hash_esperado TEXT, hash_actual TEXT, modificado BOOLEAN)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT b.archivo, b.hash_esperado, md5(pg_read_file(b.archivo)),
         md5(pg_read_file(b.archivo)) <> b.hash_esperado
  FROM public.config_hash_baseline b;
$$;

-- Re-registra el baseline despues de un cambio aprobado.
CREATE OR REPLACE FUNCTION fn_h2_aprobar_cambio()
RETURNS VOID
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  UPDATE public.config_hash_baseline
  SET hash_esperado = md5(pg_read_file(archivo)), registrado = NOW();
$$;

INSERT INTO config_hash_baseline (archivo, hash_esperado)
SELECT f, md5(pg_read_file(f))
FROM unnest(ARRAY[current_setting('config_file'), current_setting('hba_file')]) AS f;

REVOKE ALL ON FUNCTION fn_h5_desviaciones(), fn_h2_hashes(), fn_h2_aprobar_cambio() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_h5_desviaciones(), fn_h2_hashes() TO rol_ti, rol_auditor;
GRANT SELECT ON pg_settings_baseline, config_hash_baseline TO rol_ti, rol_auditor;
