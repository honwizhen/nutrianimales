-- Vistas de reportes para el gerente (RBAC, seccion 7).
-- rol_gerente solo tiene SELECT sobre estas vistas, nunca sobre las tablas.
-- Las vistas se ejecutan con los permisos de su dueno (postgres), por eso el
-- gerente puede leerlas sin tener acceso directo a ventas, clientes, etc.
-- Se crean antes de 05-roles.sh, que les da los permisos.

-- Ventas por mes, producto y estado
CREATE VIEW v_ventas_resumen AS
SELECT
  date_trunc('month', v.fecha)::date AS mes,
  p.codigo                           AS producto_codigo,
  p.nombre                           AS producto,
  p.tipo                             AS tipo_animal,
  v.estado,
  count(*)                           AS num_ventas,
  sum(v.cantidad)                    AS cantidad_total,
  sum(v.precio_total)                AS monto_total
FROM ventas v
JOIN productos p ON p.id = v.producto_id
GROUP BY 1, 2, 3, 4, 5;

-- Produccion por planta y estado de lote
CREATE VIEW v_produccion_por_planta AS
SELECT
  pl.nombre                   AS planta,
  pl.capacidad_produccion,
  l.estado,
  count(*)                    AS num_lotes,
  sum(l.cantidad_producida)   AS cantidad_total,
  min(l.fecha_inicio)         AS primer_lote,
  max(l.fecha_inicio)         AS ultimo_lote
FROM lotes_produccion l
JOIN plantas pl ON pl.id = l.planta_id
GROUP BY pl.id, pl.nombre, pl.capacidad_produccion, l.estado;

-- Clientes con su volumen de compras. Sin correo: el gerente no necesita datos de contacto.
CREATE VIEW v_clientes AS
SELECT
  c.id,
  c.nombre,
  c.tipo,
  c.segmento,
  count(v.id) FILTER (WHERE v.estado = 'completada')             AS compras_completadas,
  coalesce(sum(v.precio_total) FILTER (WHERE v.estado = 'completada'), 0) AS monto_comprado,
  max(v.fecha)                                                    AS ultima_compra
FROM clientes c
LEFT JOIN ventas v ON v.cliente_id = c.id
GROUP BY c.id, c.nombre, c.tipo, c.segmento;
