# NutriAnimales S.A. - Infraestructura y hardening

BCD 9220 Seguridad de sistemas digitales, Lead University. Stack: PostgreSQL 16, N8N, pgAdmin y Nginx en Docker Compose.

## Requisitos

- Linux (Ubuntu recomendado) con Docker, Docker Compose v2, OpenSSL y UFW. H1 necesita un UFW real en el host, por eso no sirve Docker Desktop.
- Puertos 8080 y 8443 libres.

## Levantar el sistema (menos de 5 minutos)

```bash
git clone <repo> && cd nutrianimales
chmod +x scripts/*.sh     # git via API no conserva el bit de ejecucion
./scripts/setup.sh        # crea .env, volumenes con permisos y certificados
nano .env                 # reemplace contrasenas y tokens
docker compose up -d
docker compose ps         # todos en "running"
```

Accesos:

- N8N: https://localhost:8443/
- pgAdmin: https://localhost:8443/pgadmin/
- PostgreSQL: sin puerto expuesto. Desde pgAdmin use host `postgres`, puerto 5432, SSL mode `require`.

El navegador mostrara una advertencia porque los certificados son autofirmados.

## Evidencia de hardening

```bash
./scripts/verify.sh
```

Imprime los comandos de los 12 puntos. Tome una captura numerada por cada bloque.

| # | Medida | Donde |
|---|--------|-------|
| 1 | Usuario no-root | `user: "1000:1000"` en n8n y pgadmin |
| 2 | Variables en `.env` | `.env` con chmod 600, en `.gitignore` |
| 3 | Red aislada | `nutrianimales-net` |
| 4 | Postgres sin puerto | servicio `postgres` sin `ports:` |
| 5 | scram-sha-256 | `POSTGRES_INITDB_ARGS`, `postgresql.conf`, `pg_hba.conf` |
| 6 | SSL en Postgres | `postgresql.conf` |
| 7 | agente_ia solo lectura | pendiente: se crea con el esquema de la BD |
| 8 | Headers en Nginx | `nginx/nginx.conf` |
| 9 | Certificado en Nginx | `scripts/gen-certs.sh` |
| 10 | Volumenes chmod 700 | `scripts/setup.sh` |
| 11 | Logs de auditoria | `log_min_duration_statement=1000`, `pg_stat_statements` |
| 12 | pg_settings_baseline | pendiente: se crea en la fase de alertas |

## Pendiente

- Tabla `pg_settings_baseline`, rol `agente_ia` y esquema de la BD (seccion 11 del enunciado).
- Envio de `ufw.log` y del log de autenticacion del host a Loki, y las alertas H1 y H2 en N8N.
- Fijar versiones de imagenes (`n8nio/n8n`, `dpage/pgadmin4`) antes de la entrega.

## Secretos

`.env` no se sube a ningun repositorio. Si un secreto se filtra, se revoca y rota aunque el commit se revierta.
