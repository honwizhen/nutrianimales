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
n8n/workflows/            H1_ufw.json, H2_hash_config.json
scripts/                  setup.sh, gen-certs.sh, n8n-import.sh, verify.sh
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

Cada alerta queda registrada en `alertas_auditoria` y se envia a Telegram con el formato del enunciado.

`fn_h5_desviaciones()` ya compara la configuracion contra `pg_settings_baseline` y detecta reglas md5 en pg_hba; el flujo H5 puede usarla directamente.

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

## Reiniciar desde cero

Los scripts de `postgres/init` solo corren con el volumen vacio:

```bash
docker compose down
sudo rm -rf data/postgres && mkdir -m 700 data/postgres
docker compose up -d
```

## Secretos

`.env` nunca se sube al repositorio. Si un secreto se filtra, se revoca y rota aunque el commit se revierta (seccion 9).
