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
- [M1 — Lectura pública: endpoints, seed y SEO](./the-blast-beast-api/docs/02-lectura-publica.md)

## Estado

**M1 — Lectura pública, completado y verificado en ejecución.**

| Pieza | Estado |
|---|---|
| Contrato OpenAPI 3.0 con endpoints de lectura y `delegatePattern` | ✅ |
| Esquema Flyway `V1__baseline.sql` (11 tablas, full-text, `pg_trgm`) | ✅ PostgreSQL 17.11 |
| API: artículos, destacados, detalle, categorías, bandas y búsqueda | ✅ |
| Full-text en español con filtros combinables y orden | ✅ |
| Seed de desarrollo: 8 noticias, 4 categorías, bandas y etiquetas | ✅ perfil `dev` |
| Web: portada, archivo, secciones, detalle, bandas, búsqueda y 404/410 | ✅ |
| SEO: title, meta, canonical, Open Graph, JSON-LD y `noindex` en errores | ✅ |
| SSR por petición con estados HTTP reales (404/410) | ✅ |
| Tests: 10 backend, 3 frontend | ✅ |
| Docker multi-stage + docker compose | ✅ stack completo sano (db, api, web, caddy) |
| CI en GitHub Actions (build, tests, imagen GHCR) | ✅ escrito |

Rutas públicas del sitio:

| Ruta | Contenido |
|---|---|
| `/` | Portada con destacados, secciones y últimas noticias |
| `/articulos` | Archivo completo con orden y paginación |
| `/categorias/:slug` | Sección |
| `/articulos/:slug` | Detalle de la noticia |
| `/bandas/:slug` | Banda y sus noticias |
| `/buscar?q=` | Búsqueda full-text |

M2 (redacción: autenticación, CRUD y editor) es el siguiente hito.

## Arranque rápido

Stack completo en contenedores (PostgreSQL + API + web SSR + Caddy):

```bash
docker compose up -d --build
```

Los valores por defecto funcionan tal cual. El perfil `dev` está activo, así que la base de
datos se carga con el contenido de ejemplo. Para cambiar puertos, credenciales o dominio:
`cp .env.example .env` y edita el archivo.

- Sitio completo: http://localhost:8088
- API a través de Caddy: http://localhost:8088/api/v1/articles
- API directa: http://localhost:8080/api/v1/ping
- Swagger: http://localhost:8080/swagger-ui.html
- Health: http://localhost:8080/actuator/health

`SITE_BASE_URL` (por defecto `http://localhost:8088`) alimenta canonical y Open Graph del
SSR. En producción se apunta al dominio real y `ALLOWED_HOSTS` al host público.

Desarrollo con recarga en caliente (solo la base de datos en Docker):

```bash
docker compose up -d db

cd the-blast-beast-api
./mvnw spring-boot:run -Dspring-boot.run.profiles=dev

cd ../the-blast-beast-web
npm install
npm start
```

- Web: http://localhost:4200
- API: http://localhost:8080/api/v1/articles

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

M1 se validó de extremo a extremo sobre PostgreSQL real, no sobre un sustituto:

- Docker Desktop 4.98 en modo usuario, backend WSL 2, Engine 29.9.2 y Compose v5.6.1.
- `docker compose up -d --build` levanta PostgreSQL 17.11, la API, el SSR y Caddy; los cuatro
  contenedores quedan `healthy`.
- La API arranca con Flyway activado y aplica `V1__baseline.sql`: 12 tablas (11 de dominio
  más `flyway_schema_history`), extensión `pg_trgm` y `articles.search_vector` como columna
  generada `tsvector`.
- El seed carga 8 noticias publicadas (más un borrador y una archivada para probar 404 y
  410), 4 categorías, bandas y etiquetas.
- Búsqueda full-text en español comprobada con `plainto_tsquery('spanish', ...)`.
- El sitio servido por Caddy en http://localhost:8088 responde 200 y renderiza en servidor
  portada, archivo, secciones, detalle, bandas y búsqueda; los 404/410 devuelven el status
  HTTP correcto.
- Hidratación sin errores de consola más allá de los 4xx esperados al pedir contenido
  retirado o inexistente.

Docker Desktop y WSL 2 se instalaron en esta máquina solo como entorno local; el proyecto
no depende de esa configuración: cualquier Docker con contenedores Linux sirve.
