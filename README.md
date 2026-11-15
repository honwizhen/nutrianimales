# NutriAnimales S.A. - Monitoreo, seguridad y hardening

BCD 9220 Seguridad de sistemas digitales, Lead University, III cuatrimestre 2026.

Stack: PostgreSQL 16, N8N, pgAdmin, Nginx (HTTPS), Loki y Grafana Alloy, todo en Docker Compose sobre la red aislada `nutrianimales-net`.

## Requisitos

- Ubuntu 22.04 o 24.04 con Docker Engine, Docker Compose v2, OpenSSL, Python 3, UFW y rsyslog.
- Docker Desktop no sirve: la alerta H1 necesita el UFW y los logs del host Linux.
- Puertos 8080 y 8443 libres.

## Levantar el sistema (menos de 5 minutos)

```bash
git clone https://github.com/honwizhen/nutrianimales.git && cd nutrianimales
chmod +x scripts/*.sh
./scripts/setup.sh          # .env con contrasenas aleatorias, volumenes chmod 700, certificados
nano .env                   # agregar GROQ_API_KEY, TELEGRAM_BOT_TOKEN y TELEGRAM_CHAT_ID
docker compose up -d
docker compose ps           # 6 servicios en "running"; solo nginx publica puertos
./scripts/n8n-import.sh     # credenciales desde .env + flujos H1 y H2 activados
```

Preparar el host para H1 (una sola vez):

```bash
sudo ufw allow OpenSSH && sudo ufw enable
sudo ufw logging medium     # registra conexiones permitidas en /var/log/ufw.log
```

Accesos:

| Servicio | URL |
|---|---|
| N8N | https://localhost:8443/ |
| pgAdmin | https://localhost:8443/pgadmin/ |
| PostgreSQL | sin puerto. Desde pgAdmin: host `postgres`, puerto 5432, SSL mode `require` |

Los certificados son autofirmados; el navegador muestra una advertencia la primera vez.

## Estructura

```
docker-compose.yml        6 servicios en nutrianimales-net
.env.example              variables sin valores reales (.env esta en .gitignore)
nginx/nginx.conf          TLS 1.2/1.3, redireccion 8080 -> 8443, headers de seguridad
postgres/conf/            postgresql.conf y pg_hba.conf (montados como directorio, vigilados por H2)
postgres/init/            se ejecuta una vez al crear el volumen:
  01-extensions.sql         pg_stat_statements
  02-schema.sql             12 tablas de la seccion 11
  03-seed.sql               registros minimos (3 plantas, 50 productos, 1200 ventas, ...)
  04-auditoria.sql          fn_auditoria() y triggers en lotes_produccion, ventas, clientes, productos
  05-roles.sh               agente_ia (solo SELECT) y RBAC: rol_gerente, rol_ti, rol_auditor
  06-baseline.sql           pg_settings_baseline, fn_h5_desviaciones(), hashes MD5 para H2
loki/loki-config.yaml     almacenamiento local, retencion 30 dias
alloy/config.alloy        envia /var/log/ufw.log y /var/log/auth.log a Loki
n8n/workflows/            H1_ufw.json, H2_hash_config.json, H3-H5 y D1-D7 (parte 4)
scripts/                  setup.sh, gen-certs.sh, n8n-import.sh, verify.sh, carga_pgbench.sh, reporte_pgbadger.sh
```

## Hardening: 12 puntos (seccion 10)

`./scripts/verify.sh` imprime la evidencia de todos los puntos; `./scripts/verify.sh 7` solo la del punto 7. Una captura por bloque.

| # | Medida | Implementacion | Evidencia esperada |
|---|---|---|---|
| 1 | Usuario no-root | `user: "1000:1000"` en n8n y pgadmin | `whoami` no es root |
| 2 | `.env` protegido | chmod 600 en setup.sh, `.env` en .gitignore | `-rw-------` |
| 3 | Red aislada | `nutrianimales-net` (bridge) | `docker network inspect` |
| 4 | Postgres sin puerto | servicio sin `ports:` | `docker compose ps`: solo nginx con 8080/8443 |
| 5 | scram-sha-256 | `POSTGRES_INITDB_ARGS`, `password_encryption`, pg_hba | `scram-sha-256` |
| 6 | SSL en Postgres | `ssl = on`, TLS 1.2 minimo, pg_hba solo `hostssl` | `on` |
| 7 | agente_ia solo lectura | solo `GRANT SELECT` en tablas de negocio | `permission denied for table clientes` |
| 8 | Headers en Nginx | X-Frame-Options, HSTS, nosniff, CSP | headers en `curl -kI` |
| 9 | Certificado en Nginx | OpenSSL autofirmado (gen-certs.sh) | candado HTTPS |
| 10 | Volumenes 700 | setup.sh | `drwx------` en `data/*` |
| 11 | Logs de auditoria | `log_min_duration_statement=1000`, pg_stat_statements | consulta de 1.5 s visible |
| 12 | pg_settings_baseline | 06-baseline.sql | 8 parametros esperados vs actuales |

## Alertas de hardening de esta seccion

**H1 - Regla UFW modificada.** Alloy envia `auth.log` y `ufw.log` a Loki. Cada minuto N8N consulta Loki y alerta si aparece un `sudo ufw allow/deny/delete/...` o trafico permitido al puerto 5432.

```bash
sudo ufw allow 5432/tcp     # ataque A3: alerta en menos de 1 minuto
sudo ufw delete allow 5432/tcp
```

**H2 - pg_hba.conf o postgresql.conf modificado.** Postgres calcula el MD5 de sus propios archivos de configuracion (`fn_h2_hashes()`) y lo compara con el hash registrado al iniciar. N8N alerta una vez por cada cambio nuevo.

```bash
echo "# cambio no autorizado" >> postgres/conf/pg_hba.conf    # dispara H2
git checkout postgres/conf/pg_hba.conf                        # restaurar
# Si el cambio fue aprobado, registrar el nuevo hash:
docker exec -it nutri_postgres psql -U postgres -d nutrianimales_db -c "SELECT fn_h2_aprobar_cambio();"
```

Cada alerta queda registrada en `alertas_auditoria` y se envia a Telegram con el formato del enunciado. Los flujos corren cada minuto y ademas tienen un disparador "Probar manualmente" para la demo en vivo. `scripts/n8n-import.sh` se puede repetir: despublica, reimporta y vuelve a publicar.

`fn_h5_desviaciones()` ya compara la configuracion contra `pg_settings_baseline` y detecta reglas md5 en pg_hba; el flujo H5 puede usarla directamente.

## Alertas H3-H5 y D1-D7 (parte 4)

Diez flujos en `n8n/workflows/` con la misma forma: `Cada minuto` (o `Probar manualmente`) → `Consultar` (Postgres, credencial `Postgres ti_db`) → `Construir alerta` (Code) → `Enviar alerta` (Execute Workflow al subflujo `enviar_alerta`, que deduplica, envía a Telegram y registra en `alertas_auditoria`).

Requisito: el subflujo `enviar_alerta` debe estar **publicado** (activo). N8N 2.x rechaza llamar un subflujo sin versión publicada (`Workflow is not active and cannot be executed`). `scripts/n8n-import.sh` solo publica los flujos cuyo id empieza con `nutri`.

| Alerta | Archivo | Fuente | Umbral | dedup_key (minutos) |
|---|---|---|---|---|
| H3 | `H3_grant_agente_ia.json` | `has_table_privilege`, `pg_roles`, `pg_auth_members` | cualquier INSERT/UPDATE/DELETE/TRUNCATE | `H3:<n>` (60) |
| H4 | `H4_ip_fuera_docker.json` | `pg_stat_activity` | IP fuera de 172.28.0.0/16 | `H4:<pid>:<inicio>` (60) |
| H5 | `H5_ssl_md5_baseline.json` | `fn_h5_desviaciones()` | cualquier desvío del baseline | `H5:<parametro>=<valor>` (60) |
| D1 | `D1_delete_masivo.json` | `pg_stat_statements` (deltas) | > 100 filas por ejecución | `D1:<queryid>:<calls>` (60) |
| D2 | `D2_crecimiento_tabla.json` | `pg_stat_user_tables` | > 20 % en 30 min (tablas ≥ 50 filas) | `D2:<tabla>` (30) |
| D3 | `D3_backup_obsoleto.json` | tabla `backups` (`estado = 'exitoso'`) | > 24 h | `D3` (360) |
| D4 | `D4_duplicados.json` | `HAVING count(*) > 1` en clientes.correo, productos.codigo, lotes_produccion.codigo | > 5 duplicados | `D4:<total>` (60) |
| D5 | `D5_bloqueos_deadlocks.json` | `pg_blocking_pids`, `pg_stat_database.deadlocks` | bloqueo > 30 s o deadlock nuevo | `D5:<pid>` (30) |
| D6 | `D6_update_masivo.json` | `pg_stat_statements` (deltas) | > 50 filas por ejecución | `D6:<queryid>:<calls>` (60) |
| D7 | `D7_exfiltracion.json` | `pg_stat_statements` (deltas), sin `ti_db` | > 1,000 filas en clientes/ventas | `D7:<queryid>:<calls>` (60) |

**Método de deltas (D1, D6, D7).** `pg_stat_statements` acumula `calls` y `rows`. El nodo Code guarda la foto anterior en los datos estáticos del flujo y alerta cuando `(rows - rows_antes) / (calls - calls_antes)` supera el umbral. La primera ejecución solo guarda la foto. Los datos estáticos (D1, D2, D5 deadlocks, D6, D7) **solo se guardan con el flujo activo**: con "Probar manualmente" esas alertas nunca disparan.

Correcciones respecto al enunciado:
- A4: `GRANT INSERT ON ALL TABLES TO agente_ia;` es error de sintaxis; se usa `GRANT INSERT ON ALL TABLES IN SCHEMA public TO agente_ia;`.
- D7: el SQL del enunciado no tiene paréntesis en el `OR` (cualquier SELECT a clientes dispara) y usa `usename`, que no existe en `pg_roles` (es `rolname`).
- H5 se prueba con `password_encryption = md5`; `ssl = off` cortaría la conexión TLS de N8N.
- D3 busca `estado = 'exitoso'` (valor que usa `03-seed.sql`).
- H4: con el `pg_hba.conf` del repositorio cualquier IP fuera de 172.28.0.0/16 se rechaza antes de llegar a `pg_stat_activity`. Para la demo se relaja `pg_hba.conf` (lo que además dispara H2) y se conecta por 127.0.0.1.

Emulación (como `postgres`, dentro de `psql`) y respuesta:

```sql
-- H3 (ataque A4)
GRANT INSERT ON ALL TABLES IN SCHEMA public TO agente_ia;
REVOKE INSERT ON ALL TABLES IN SCHEMA public FROM agente_ia;
-- H5
ALTER SYSTEM SET password_encryption = 'md5'; SELECT pg_reload_conf();
ALTER SYSTEM RESET password_encryption;       SELECT pg_reload_conf();
-- D1
CREATE TABLE prueba_delete AS SELECT * FROM ventas LIMIT 200;
DELETE FROM prueba_delete;
DROP TABLE prueba_delete;
-- D6
CREATE TABLE prueba_update AS SELECT * FROM lotes_produccion LIMIT 200;
UPDATE prueba_update SET estado = 'cancelado';
DROP TABLE prueba_update;
-- D2 (+30 % en gastos) y limpieza (60 filas: no dispara D1)
INSERT INTO gastos (categoria, descripcion, monto, fecha, aprobado_por)
SELECT 'prueba', 'prueba D2', 1000, CURRENT_DATE, 'parte4' FROM generate_series(1, 60);
DELETE FROM gastos WHERE descripcion = 'prueba D2';
-- D3 (envejece el ultimo respaldo) y respuesta
UPDATE backups SET fecha = fecha - interval '25 hours';
INSERT INTO backups (estado, ruta) VALUES ('exitoso', '/backups/manual.sql.gz');
-- D4 (6 copias de un correo existente = 6 duplicados) y limpieza
INSERT INTO clientes (nombre, tipo, correo, segmento)
SELECT 'Prueba D4 ' || g, 'persona', 'cliente1@example.com', 'minorista' FROM generate_series(1, 6) g;
DELETE FROM clientes WHERE nombre LIKE 'Prueba D4 %';
```

D5 (dos terminales de `psql`): en la 1 `BEGIN; UPDATE plantas SET estado = estado WHERE id = 1;`, en la 2 `UPDATE plantas SET estado = estado WHERE id = 1;` (queda esperando); después de la alerta, `ROLLBACK;` en la 1.

D7 (ataque A5), como `agente_ia` por la red Docker:

```bash
set -a; . ./.env; set +a
docker exec -e PGPASSWORD="$AGENTE_IA_PASSWORD" -e PGSSLMODE=require nutri_postgres \
  psql -h postgres -U agente_ia -d nutrianimales_db -c "SELECT * FROM ventas" > /dev/null
```

`clientes` tiene 200 filas: `SELECT * FROM clientes` nunca supera 1,000. A5 se demuestra con `ventas` (1,200 filas) salvo que el grupo suba `clientes` a más de 1,000.

## Bot de Telegram (agente_ia + Groq)

`n8n/workflows/bot_telegram.json` lee los mensajes con `getUpdates` cada 10 s (sin webhook ni puerto publico), filtra el ataque A2, traduce la pregunta a un SELECT con Groq, lo valida otra vez y lo ejecuta como `agente_ia`. Los intentos bloqueados quedan en `alertas_auditoria` (`datos`, `A2`, `critica`). No usa `$env`, asi que funciona con `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`.

Antes de importarlo, en la interfaz de N8N (una sola vez):
1. Credenciales con estos nombres exactos: `Telegram NutriAnimales` (Telegram API), `Groq API` (Header Auth: `Authorization` = `Bearer <GROQ_API_KEY>`), `Postgres agente_ia` y `Postgres ti_db` (host `postgres`, SSL Require, Ignore SSL Issues).
2. Data Table `bot_config` con columnas `clave` y `valor` (string) y una fila `telegram_bot_token` = token del bot. `getUpdates` necesita el token en la URL y ninguna credencial de N8N puede ponerlo ahi.
3. Despues de importar, cambiar el chat autorizado en el nodo "Configuración" si no es el mismo.

Si el token se rota en BotFather, actualizar la credencial y la fila de `bot_config`.

### Por que el token esta en una Data Table

Lo ideal seria que todo el bot usara la credencial cifrada `Telegram NutriAnimales`, pero en N8N 2.44 no se puede para leer mensajes:
- **HTTP Request con "Predefined Credential Type" → Telegram API:** N8N solo agrega a la peticion lo que la credencial declara en `authenticate` (headers, query o body). `telegramApi` no define `authenticate` y Telegram exige el token en la ruta (`/bot<token>/getUpdates`). Probado: la peticion sale sin token y Telegram responde `404 Not Found`.
- **Nodo Telegram:** usa la credencial, pero solo para sus operaciones fijas (`sendMessage`, `getChat`, ...). `getUpdates` esta comentado en el codigo del nodo y `deleteWebhook` solo lo usa el Telegram Trigger. Por eso las **respuestas** si usan la credencial cifrada.

Alternativas evaluadas y descartadas:
- **Proxy interno** (`nginx` sin puertos que agrega el token desde `.env` y solo reenvia `/getUpdates` y `/deleteWebhook`): saca el token de N8N, pero agrega un servicio y una red mas al compose solo para esto, y el token sigue visible con `docker inspect`.
- **Webhook con Telegram Trigger** (solo credencial cifrada): Telegram necesita llegar a N8N por HTTPS publico. En la VM exige dominio con certificado valido y abrir el 8443 a internet; en local, un tunel cloudflared. Contradice el hardening 4 (nada expuesto).

Mitigaciones aplicadas:
- El flujo no guarda datos de ninguna ejecucion: `saveDataSuccessExecution`, `saveDataErrorExecution` = `none`, `saveManualExecutions` y `saveExecutionProgress` = `false`. La salida del nodo "Leer token" nunca queda en `execution_data`. Para depurar, activarlas temporalmente y borrar esas ejecuciones despues.
- El token no esta en el JSON del repositorio ni en `$env` (`N8N_BLOCK_ENV_ACCESS_IN_NODE=true`); el JSON solo tiene el chat ID, que no es secreto.
- `data/n8n` con chmod 700 (hardening 10): solo el dueno lee la base de N8N.
- N8N no publica puertos: solo se llega por Nginx, con usuario owner.

## Carga con pgbench y reporte con pgBadger

Solo necesitan el servicio `postgres` corriendo y `.env`. Ninguno instala nada en el host.

```bash
./scripts/carga_pgbench.sh           # esquema bench, 10 clientes, 60 s; termina con el top de pg_stat_statements
./scripts/carga_pgbench.sh --lenta   # ademas, una consulta de 1.5 s que queda en los logs para R1
./scripts/reporte_pgbadger.sh        # genera reportes/pgbadger.html a partir de docker logs
open reportes/pgbadger.html          # macOS; en Ubuntu: xdg-open
```

- Cada corrida de pgbench recrea las tablas de `bench`. No toca las tablas de negocio ni reinicia `pg_stat_statements`, asi que sus estadisticas son acumuladas.
- Con `log_min_duration_statement = 1000`, el reporte solo muestra como consultas lentas las de 1 s o mas: la carga normal de pgbench no aparece ahi.
- En las bases inicializadas a partir de este cambio, las contrasenas de `05-roles.sh` no quedan en `docker logs` ni en `pg_stat_statements`. El enmascarado de `reporte_pgbadger.sh` es una segunda capa para bases creadas antes: esas conservan las contrasenas hasta recrearlas, asi que no capture su `docker logs` sin filtrar.

## Usuarios de base de datos

| Usuario | Rol | Uso |
|---|---|---|
| postgres | superusuario | administracion |
| agente_ia | solo SELECT en tablas de negocio | bot de Telegram con Groq |
| ti_db | rol_ti + pg_monitor | credencial de los flujos de N8N |
| gerente_db | rol_gerente | reportes, sin auditoria |
| auditor_db | rol_auditor | auditoria y estadisticas |

Todas las contrasenas estan en `.env`. Ninguna esta escrita en el repositorio.

## Nota sobre Filebeat

El enunciado menciona Filebeat + Loki. Filebeat no tiene salida nativa a Loki (requeriria Logstash con un plugin) y Promtail, el agente original de Loki, llego a fin de vida el 2 de marzo de 2026. Se usa Grafana Alloy, su reemplazo oficial, con la misma funcion: leer `ufw.log` y `auth.log` y enviarlos a Loki.

## Estado de pruebas

Probado fuera de Docker (PostgreSQL 16 y n8n 2.44.6 nativos):

- Los 6 scripts de `postgres/init` sobre una base nueva.
- Puntos 5, 6, 7, 11 y 12, RBAC (gerente sin acceso a auditoria) y triggers con valor antes/despues.
- H2 y H5 detectan cambios; H2 alerta una sola vez por cambio.
- Flujos H1 y H2 importados, publicados y ejecutados de punta a punta (H1 contra un Loki simulado). Telegram no se pudo probar.

Pendiente de probar en la VM: `docker compose up` completo, Nginx (`docker exec nutri_nginx nginx -t`), pgAdmin detras de `/pgadmin/`, Loki + Alloy reales y el envio a Telegram.

## Reiniciar desde cero

Los scripts de `postgres/init` solo corren con el volumen vacio:

```bash
docker compose down
sudo rm -rf data/postgres && mkdir -m 700 data/postgres
docker compose up -d
```

## Secretos

`.env` nunca se sube al repositorio. Si un secreto se filtra, se revoca y rota aunque el commit se revierta (seccion 9).
