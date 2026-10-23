-- Esquema de NutriAnimales S.A. (seccion 11 del enunciado)

CREATE TABLE plantas (
  id                   SERIAL PRIMARY KEY,
  nombre               VARCHAR(100) NOT NULL,
  ubicacion            VARCHAR(150) NOT NULL,
  capacidad_produccion INTEGER NOT NULL,          -- toneladas por mes
  estado               VARCHAR(20) NOT NULL DEFAULT 'activa'
);

CREATE TABLE productos (
  id              SERIAL PRIMARY KEY,
  codigo          VARCHAR(20) UNIQUE NOT NULL,
  nombre          VARCHAR(150) NOT NULL,
  tipo            VARCHAR(20) NOT NULL CHECK (tipo IN ('aves','cerdos','ganado','peces')),
  precio_unitario NUMERIC(12,2) NOT NULL,
  activo          BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE materias_primas (
  id           SERIAL PRIMARY KEY,
  nombre       VARCHAR(150) NOT NULL,
  categoria    VARCHAR(50) NOT NULL,
  stock_actual NUMERIC(12,2) NOT NULL,
  stock_minimo NUMERIC(12,2) NOT NULL,
  proveedor    VARCHAR(150)
);

CREATE TABLE lotes_produccion (
  id                 SERIAL PRIMARY KEY,
  codigo             VARCHAR(30) UNIQUE NOT NULL,
  planta_id          INTEGER NOT NULL REFERENCES plantas(id),
  producto_id        INTEGER NOT NULL REFERENCES productos(id),
  cantidad_producida NUMERIC(12,2) NOT NULL,
  fecha_inicio       TIMESTAMP NOT NULL,
  estado             VARCHAR(20) NOT NULL DEFAULT 'en_proceso'
);

CREATE TABLE clientes (
  id       SERIAL PRIMARY KEY,
  nombre   VARCHAR(150) NOT NULL,
  tipo     VARCHAR(20) NOT NULL CHECK (tipo IN ('distribuidor','empresa','persona')),
  correo   VARCHAR(150),
  segmento VARCHAR(50)
);

CREATE TABLE ventas (
  id           SERIAL PRIMARY KEY,
  cliente_id   INTEGER NOT NULL REFERENCES clientes(id),
  producto_id  INTEGER NOT NULL REFERENCES productos(id),
  cantidad     NUMERIC(12,2) NOT NULL,
  precio_total NUMERIC(14,2) NOT NULL,
  fecha        TIMESTAMP NOT NULL,
  estado       VARCHAR(20) NOT NULL DEFAULT 'completada'
);

CREATE TABLE control_calidad (
  id             SERIAL PRIMARY KEY,
  lote_id        INTEGER NOT NULL REFERENCES lotes_produccion(id),
  parametro      VARCHAR(50) NOT NULL,
  valor_obtenido NUMERIC(10,3) NOT NULL,
  valor_esperado NUMERIC(10,3) NOT NULL,
  aprobado       BOOLEAN NOT NULL
);

CREATE TABLE gastos (
  id           SERIAL PRIMARY KEY,
  categoria    VARCHAR(50) NOT NULL,
  descripcion  VARCHAR(255),
  monto        NUMERIC(14,2) NOT NULL,
  fecha        DATE NOT NULL,
  aprobado_por VARCHAR(100)
);

-- Tablas de soporte de seguridad
CREATE TABLE auditoria_datos (
  id          SERIAL PRIMARY KEY,
  tabla       VARCHAR(100) NOT NULL,
  operacion   VARCHAR(10) NOT NULL,          -- INSERT, UPDATE, DELETE
  usuario     VARCHAR(100) DEFAULT current_user,
  fecha       TIMESTAMP   DEFAULT NOW(),
  ip_cliente  INET        DEFAULT inet_client_addr(),
  fila_id     INTEGER,
  valor_antes JSONB,
  valor_nuevo JSONB
);
CREATE INDEX idx_audit_tabla   ON auditoria_datos(tabla);
CREATE INDEX idx_audit_usuario ON auditoria_datos(usuario);
CREATE INDEX idx_audit_fecha   ON auditoria_datos(fecha);

CREATE TABLE backups (
  id     SERIAL PRIMARY KEY,
  fecha  TIMESTAMP NOT NULL DEFAULT NOW(),
  estado VARCHAR(20) NOT NULL,                -- exitoso, fallido
  ruta   VARCHAR(255)
);

CREATE TABLE alertas_auditoria (
  id        SERIAL PRIMARY KEY,
  tipo      VARCHAR(20) NOT NULL,             -- rendimiento, hardening, datos
  alerta    VARCHAR(10) NOT NULL,             -- R1..R5, H1..H5, D1..D7
  mensaje   TEXT NOT NULL,
  fecha     TIMESTAMP NOT NULL DEFAULT NOW(),
  severidad VARCHAR(20) NOT NULL              -- critica, advertencia
);
CREATE INDEX idx_alertas_fecha ON alertas_auditoria(fecha);
