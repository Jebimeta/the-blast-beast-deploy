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
- [M2 — Redacción: auth, CRUD, medios, revisiones y panel](./the-blast-beast-api/docs/03-redaccion.md)

## Estado

**M2 — Redacción, completado y verificado en ejecución.**

| Pieza | Estado |
|---|---|
| Contrato OpenAPI 3.0 con endpoints públicos, de auth y de redacción | ✅ |
| Esquema Flyway `V1__baseline.sql` (11 tablas, full-text, `pg_trgm`) | ✅ PostgreSQL 17.11 |
| API pública: artículos, destacados, detalle, categorías, bandas y búsqueda | ✅ |
| Auth: JWT en memoria + refresco opaco en cookie HttpOnly con rotación y detección de reuso | ✅ |
| CRUD de artículos con estados, revisiones restaurables y vista previa Markdown saneada | ✅ |
| Medios: subida, variantes WebP `thumb`/`hero`, protección de imágenes en uso | ✅ |
| Taxonomía editable: categorías, bandas y etiquetas | ✅ |
| Web pública: portada, archivo, secciones, detalle, bandas, búsqueda y 404/410 | ✅ |
| Panel `/admin`: login, listado, editor con autoguardado, taxonomía y biblioteca | ✅ |
| SEO: title, meta, canonical, OG, Twitter, JSON-LD con imagen y `noindex` en errores | ✅ |
| SSR por petición con estados HTTP reales (404/410) | ✅ |
| Tests: 21 backend, 3 frontend | ✅ |
| Docker multi-stage (glibc para WebP) + volumen de medios + `/media/*` en Caddy | ✅ |
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
| `/admin/login` | Acceso a la redacción |

Credenciales del seed de desarrollo: `redaccion@theblastbeast.com` / `Redaccion2026!`.

M3 (sitemap, RSS y prerender selectivo) es el siguiente hito.

## Arranque rápido

Stack completo en contenedores (PostgreSQL + API + web SSR + Caddy):

```bash
docker compose up -d --build
```

Los valores por defecto funcionan tal cual. El perfil `dev` está activo, así que la base de
datos se carga con el contenido de ejemplo. Para cambiar puertos, credenciales o dominio:
`cp .env.example .env` y edita el archivo.

- Sitio completo: http://localhost:8088
- Panel de redacción: http://localhost:8088/admin/login
- API a través de Caddy: http://localhost:8088/api/v1/articles
- Medios a través de Caddy: http://localhost:8088/media/…
- API directa: http://localhost:8080/api/v1/ping
- Swagger: http://localhost:8080/swagger-ui.html
- Health: http://localhost:8080/actuator/health

Credenciales del seed de desarrollo: `redaccion@theblastbeast.com` / `Redaccion2026!`.

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
[`.env.example`](./.env.example) (Compose) y en
[`the-blast-beast-api/.env.example`](./the-blast-beast-api/.env.example) (API). Los archivos
no se cargan solos: exporta las variables en tu shell o pásalas por Docker Compose. En
local, los valores por defecto de `application.yml` funcionan sin configurar nada.

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

M1 y M2 se validaron de extremo a extremo sobre PostgreSQL real, no sobre un sustituto:

- Docker Desktop 4.98 en modo usuario, backend WSL 2, Engine 29.9.2 y Compose v5.6.1.
- `docker compose up -d --build` levanta PostgreSQL 17.11, la API, el SSR y Caddy; los cuatro
  contenedores quedan `healthy`.
- La API arranca con Flyway activado y aplica `V1__baseline.sql`: 12 tablas (11 de dominio
  más `flyway_schema_history`), extensión `pg_trgm` y `articles.search_vector` como columna
  generada `tsvector`.
- El seed carga 8 noticias publicadas (más un borrador y una archivada para probar 404 y
  410), 4 categorías, bandas, etiquetas y el usuario de redacción.
- Búsqueda full-text en español comprobada con `plainto_tsquery('spanish', ...)`.
- El sitio servido por Caddy en http://localhost:8088 responde 200 y renderiza en servidor
  portada, archivo, secciones, detalle, bandas y búsqueda; los 404/410 devuelven el status
  HTTP correcto.
- El panel en `/admin` permite login, CRUD de artículos con autoguardado y revisiones,
  taxonomía y subida de medios; las variantes WebP se generan dentro del contenedor glibc y
  se sirven por `/media/*` a través de Caddy.
- Hidratación sin errores de consola más allá de los 4xx esperados al pedir contenido
  retirado o inexistente.

Docker Desktop y WSL 2 se instalaron en esta máquina solo como entorno local; el proyecto
no depende de esa configuración: cualquier Docker con contenedores Linux sirve.
