-- Triggers de auditoria (seccion 6 del enunciado).
-- Se crean despues del seed para que auditoria_datos arranque limpia.

CREATE OR REPLACE FUNCTION fn_auditoria()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    INSERT INTO auditoria_datos (tabla, operacion, fila_id, valor_antes, valor_nuevo)
    VALUES (TG_TABLE_NAME, 'DELETE', OLD.id, row_to_json(OLD)::jsonb, NULL);
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO auditoria_datos (tabla, operacion, fila_id, valor_antes, valor_nuevo)
    VALUES (TG_TABLE_NAME, 'UPDATE', NEW.id, row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb);
    RETURN NEW;
  ELSIF TG_OP = 'INSERT' THEN
    INSERT INTO auditoria_datos (tabla, operacion, fila_id, valor_antes, valor_nuevo)
    VALUES (TG_TABLE_NAME, 'INSERT', NEW.id, NULL, row_to_json(NEW)::jsonb);
    RETURN NEW;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
-- SECURITY DEFINER: un usuario con permiso de escritura en ventas puede generar
-- su registro de auditoria sin tener INSERT directo sobre auditoria_datos.

CREATE TRIGGER trg_auditoria_lotes
  AFTER INSERT OR UPDATE OR DELETE ON lotes_produccion
  FOR EACH ROW EXECUTE FUNCTION fn_auditoria();

CREATE TRIGGER trg_auditoria_ventas
  AFTER INSERT OR UPDATE OR DELETE ON ventas
  FOR EACH ROW EXECUTE FUNCTION fn_auditoria();

CREATE TRIGGER trg_auditoria_clientes
  AFTER INSERT OR UPDATE OR DELETE ON clientes
  FOR EACH ROW EXECUTE FUNCTION fn_auditoria();

CREATE TRIGGER trg_auditoria_formulas
  AFTER INSERT OR UPDATE OR DELETE ON productos
  FOR EACH ROW EXECUTE FUNCTION fn_auditoria();
