-- Datos de prueba con los registros minimos de la seccion 11.
-- setseed hace que los datos sean iguales en cada instalacion.
SELECT setseed(0.2026);

INSERT INTO plantas (nombre, ubicacion, capacidad_produccion, estado) VALUES
  ('Planta Alajuela', 'Alajuela, Valle Central', 4500, 'activa'),
  ('Planta Cartago',  'Cartago, Valle Central',  3200, 'activa'),
  ('Planta Heredia',  'Heredia, Valle Central',  2800, 'activa');

INSERT INTO productos (codigo, nombre, tipo, precio_unitario, activo)
SELECT
  'PRD-' || lpad(g::text, 3, '0'),
  (ARRAY['Concentrado','Iniciador','Engorde','Mantenimiento','Premezcla'])[1 + g % 5]
    || ' ' || t.tipo || ' ' || g,
  t.tipo,
  round((8000 + random() * 22000)::numeric, 2),
  g % 10 <> 0
FROM generate_series(1, 50) g
CROSS JOIN LATERAL (SELECT (ARRAY['aves','cerdos','ganado','peces'])[1 + g % 4] AS tipo) t;

INSERT INTO materias_primas (nombre, categoria, stock_actual, stock_minimo, proveedor)
SELECT
  (ARRAY['Maiz amarillo','Harina de soya','Harina de pescado','Melaza','Carbonato de calcio',
         'Sal mineral','Afrecho de trigo','Aceite vegetal','Lisina','Metionina'])[1 + g % 10] || ' L' || g,
  (ARRAY['cereal','proteina','mineral','aditivo','energia'])[1 + g % 5],
  round((random() * 50000)::numeric, 2),
  round((2000 + random() * 8000)::numeric, 2),
  (ARRAY['Agroinsumos CR','Granos del Pacifico','Nutrimix S.A.','Importadora Central'])[1 + g % 4]
FROM generate_series(1, 100) g;

INSERT INTO lotes_produccion (codigo, planta_id, producto_id, cantidad_producida, fecha_inicio, estado)
SELECT
  'LOT-2026-' || lpad(g::text, 4, '0'),
  1 + g % 3,
  1 + g % 50,
  round((5 + random() * 45)::numeric, 2),
  NOW() - (random() * INTERVAL '180 days'),
  (ARRAY['en_proceso','completado','completado','completado','retenido'])[1 + g % 5]
FROM generate_series(1, 500) g;

INSERT INTO clientes (nombre, tipo, correo, segmento)
SELECT
  (ARRAY['Avicola','Porcina','Ganadera','Acuicola','Agropecuaria'])[1 + g % 5] || ' Cliente ' || g,
  (ARRAY['distribuidor','empresa','persona'])[1 + g % 3],
  'cliente' || g || '@example.com',
  (ARRAY['mayorista','minorista','corporativo'])[1 + g % 3]
FROM generate_series(1, 200) g;

INSERT INTO ventas (cliente_id, producto_id, cantidad, precio_total, fecha, estado)
SELECT
  1 + (random() * 199)::int,
  p.id,
  q.cantidad,
  round(q.cantidad * p.precio_unitario, 2),
  NOW() - (random() * INTERVAL '365 days'),
  (ARRAY['completada','completada','completada','pendiente','anulada'])[1 + g % 5]
FROM generate_series(1, 1200) g
CROSS JOIN LATERAL (SELECT round((1 + random() * 99)::numeric, 2) AS cantidad) q
JOIN productos p ON p.id = 1 + g % 50;

INSERT INTO control_calidad (lote_id, parametro, valor_obtenido, valor_esperado, aprobado)
SELECT
  1 + g % 500,
  par.parametro,
  round((par.esperado * (0.9 + random() * 0.2))::numeric, 3),
  par.esperado,
  TRUE
FROM generate_series(1, 300) g
CROSS JOIN LATERAL (
  SELECT (ARRAY['humedad','proteina','grasa','fibra','cenizas'])[1 + g % 5] AS parametro,
         (ARRAY[12.0, 18.0, 4.5, 6.0, 7.0])[1 + g % 5]                   AS esperado
) par;
UPDATE control_calidad SET aprobado = abs(valor_obtenido - valor_esperado) / valor_esperado <= 0.07;

INSERT INTO gastos (categoria, descripcion, monto, fecha, aprobado_por)
SELECT
  (ARRAY['mantenimiento','transporte','energia','materia_prima','planilla'])[1 + g % 5],
  'Gasto operativo #' || g,
  round((50000 + random() * 2000000)::numeric, 2),
  CURRENT_DATE - (random() * 365)::int,
  (ARRAY['Gerencia General','Jefatura de Planta','Finanzas'])[1 + g % 3]
FROM generate_series(1, 200) g;

-- Un respaldo inicial para que D3 tenga linea base
INSERT INTO backups (fecha, estado, ruta) VALUES (NOW(), 'exitoso', '/backups/inicial.sql.gz');
