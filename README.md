# The Blast Beast

Portal de noticias de heavy metal. Proyecto de publicación real y portfolio.

| Repo | Contenido |
|---|---|
| `the-blast-beast-deploy` (este repo) | Orquestación: Docker Compose, Caddy y documentación del workspace |
| [`the-blast-beast-api`](./the-blast-beast-api) | API REST — Java 21, Spring Boot 3.5, PostgreSQL, OpenAPI |
| [`the-blast-beast-web`](./the-blast-beast-web) | Frontend — Angular 22 con SSR |

## Clonar el proyecto

El repo de deploy espera los otros dos como carpetas hermanas (están en `.gitignore`):

```bash
git clone git@github.com:Jebimeta/the-blast-beast-deploy.git the-blast-beast
cd the-blast-beast

git clone git@github.com:Jebimeta/the-blast-beast-api.git
git clone git@github.com:Jebimeta/the-blast-beast-web.git
```

Con esa estructura, `docker compose up -d --build` funciona sin configuración adicional.

## Documentación

Vive en el repo de la API porque el contrato `openapi.yaml` y el modelo de datos son la
fuente de verdad del sistema:

- [Auditoría de los repos de referencia](./the-blast-beast-api/docs/00-auditoria-repos.md)
- [Arquitectura, modelo de datos, API y roadmap](./the-blast-beast-api/docs/01-arquitectura.md)

## Estado

**M0 — Fundaciones, completado y verificado en ejecución.**

| Pieza | Estado |
|---|---|
| Contrato OpenAPI 3.0 + generación de delegates | ✅ |
| Esquema Flyway `V1__baseline.sql` (11 tablas, full-text, `pg_trgm`) | ✅ aplicado en PostgreSQL 17.11 |
| Seguridad base (stateless, CORS, cabeceras) | ✅ |
| Errores RFC 9457 (`ProblemDetail` + `ErrorCode`) | ✅ |
| API: `/api/v1/ping`, Swagger UI, `/actuator/health` | ✅ 200 |
| Web Angular 22 + SSR + Tailwind 4, integrada con la API | ✅ 200 |
| Tests: 1 backend, 3 frontend | ✅ |
| Docker multi-stage + docker compose | ✅ stack completo sano (db, api, web, caddy) |
| CI en GitHub Actions (build, tests, imagen GHCR) | ✅ escrito |
| Repos git inicializados y commit inicial | ✅ |

Sin funcionalidad de negocio todavía: los artículos llegan en M1.

## Arranque rápido

Stack completo en contenedores (PostgreSQL + API + web SSR + Caddy):

```bash
docker compose up -d --build
```

Los valores por defecto funcionan tal cual. Para cambiar puertos, credenciales o dominio:
`cp .env.example .env` y edita el archivo.

- Sitio completo: http://localhost:8088
- API a través de Caddy: http://localhost:8088/api/v1/ping
- API directa: http://localhost:8080/api/v1/ping
- Swagger: http://localhost:8080/swagger-ui.html
- Health: http://localhost:8080/actuator/health

Desarrollo con recarga en caliente (solo la base de datos en Docker):

```bash
docker compose up -d db

cd the-blast-beast-api
./mvnw spring-boot:run -Dspring-boot.run.profiles=local

cd ../the-blast-beast-web
npm install
npm start
```

- Web: http://localhost:4200
- API: http://localhost:8080/api/v1/ping

Las variables de entorno y sus valores por defecto están documentadas en
[`the-blast-beast-api/.env.example`](./the-blast-beast-api/.env.example). El archivo no se
carga solo: exporta las variables en tu shell o pásalas por Docker Compose. En local, los
valores por defecto de `application.yml` funcionan sin configurar nada.

## Toolchain local (solo esta máquina)

Las herramientas están en `.toolchain/` sin instalar en el sistema. Para usarlas en una
terminal nueva:

```powershell
$root = (Get-Location).Path
$env:JAVA_HOME = "$root\.toolchain\jdk"
$env:Path = "$env:JAVA_HOME\bin;$root\.toolchain\node;$root\.toolchain\maven\bin;$root\.toolchain\git\cmd;$env:Path"
```

`.toolchain/` está ignorado por git.

El CLI de Docker vive fuera del PATH del sistema. Para `docker` y `docker compose` en una
terminal nueva:

```powershell
$env:Path = "$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin;$env:Path"
```


### Entorno verificado en esta máquina

M0 se validó de extremo a extremo sobre PostgreSQL real, no sobre un sustituto:

- Docker Desktop 4.98 en modo usuario, backend WSL 2, Engine 29.9.2 y Compose v5.6.1.
- `docker compose up -d --build` levanta PostgreSQL 17.11, la API, el SSR y Caddy; los cuatro
  contenedores quedan `healthy`.
- La API arranca con Flyway activado y aplica `V1__baseline.sql`: 12 tablas (11 de dominio
  más `flyway_schema_history`), extensión `pg_trgm` y `articles.search_vector` como columna
  generada `tsvector`.
- Búsqueda full-text en español comprobada con `plainto_tsquery('spanish', ...)`.
- El sitio servido por Caddy en http://localhost:8088 responde 200, hidrata sin errores de
  consola y muestra «API operativa» tras llamar a `/api/v1/ping` a través del proxy.

Docker Desktop y WSL 2 se instalaron en esta máquina solo como entorno local; el proyecto
no depende de esa configuración: cualquier Docker con contenedores Linux sirve.

