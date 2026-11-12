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
- [M3 — SEO técnico: sitemap, robots, RSS, JSON-LD y prerender selectivo](./the-blast-beast-api/docs/04-seo.md)
- [M4 — Calidad: Testcontainers, e2e, accesibilidad y rendimiento](./the-blast-beast-api/docs/05-calidad.md)
- [M5 — Producción: VPS, TLS, backups, monitorización y RGPD](./the-blast-beast-api/docs/06-produccion.md)

## Estado

**M5 — Producción: infraestructura implementada y validada en local; despliegue real pendiente de VPS, dominio y datos legales.**

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
| SEO técnico: sitemap con imágenes, `robots.txt` dinámico y RSS global + por categoría | ✅ |
| JSON-LD `WebSite`/`SearchAction`, `NewsArticle` y `BreadcrumbList` | ✅ |
| Páginas `/sobre`, `/contacto` y `/privacidad` prerenderizadas; resto SSR | ✅ |
| SSR por petición con estados HTTP reales (404/410) | ✅ |
| Tests: 29 unitarios + 41 integración (Testcontainers) backend, 7 frontend, 12 e2e | ✅ |
| Cobertura de servicios: 93,6 % de líneas (JaCoCo, mínimo 70 %) | ✅ |
| Accesibilidad WCAG 2.1 AA con axe: 0 violaciones en público y panel | ✅ |
| Lighthouse móvil (mediana de 3 pasadas): rendimiento ≥ 0,90, SEO ≥ 0,95 | ✅ |
| Docker multi-stage (glibc para WebP) + volumen de medios + `/media/*` en Caddy | ✅ |
| CI en GitHub Actions (build, tests, e2e + Lighthouse, imagen GHCR) | ✅ en verde |
| Stack de producción: solo Caddy expuesto, redes internas, límites y logs rotados | ✅ validado en local |
| TLS automático, redirección `www` → apex y cabeceras/CSP estrictas | ✅ `caddy validate` |
| Backups de PostgreSQL + medios con checksum, retención y cifrado age opcional | ✅ restauración aplicada |
| Monitorización cada 2 min con alertas por webhook y comprobación de TLS/disco | ✅ validado en local |
| Hardening del VPS (UFW, fail2ban, unattended-upgrades, SSH por clave) | ✅ documentado |
| CD por SSH con healthchecks, smoke test y rollback de imagen | ✅ validación en CI |

Rutas públicas del sitio:

| Ruta | Contenido |
|---|---|
| `/` | Portada con destacados, secciones y últimas noticias |
| `/articulos` | Archivo completo con orden y paginación |
| `/categorias/:slug` | Sección |
| `/articulos/:slug` | Detalle de la noticia |
| `/bandas/:slug` | Banda y sus noticias |
| `/buscar?q=` | Búsqueda full-text |
| `/sobre` | Sobre el medio |
| `/contacto` | Contacto de la redacción |
| `/privacidad` | Política de privacidad |
| `/admin/login` | Acceso a la redacción |

Credenciales del seed de desarrollo: `redaccion@theblastbeast.com` / `Redaccion2026!`.

M5 deja preparado el despliegue real: imágenes en GHCR, Caddy con TLS automático,
secretos fuera del repositorio, backups con restauración probada, monitorización y
hardening. El paso a producción está bloqueado solo por el VPS, el dominio/DNS, el acceso
SSH y los datos legales del titular. El runbook completo está en
[`docs/06-produccion.md`](./the-blast-beast-api/docs/06-produccion.md).

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
- Sitemap: http://localhost:8088/sitemap.xml
- RSS global: http://localhost:8088/feed.xml
- Robots: http://localhost:8088/robots.txt
- API directa: http://localhost:8080/api/v1/ping
- Swagger: http://localhost:8080/swagger-ui.html
- Health: http://localhost:8080/actuator/health

Credenciales del seed de desarrollo: `redaccion@theblastbeast.com` / `Redaccion2026!`.

`SITE_BASE_URL` (por defecto `http://localhost:8088`) alimenta canonical y Open Graph del
SSR y, en tiempo de build, el HTML prerenderizado de `/sobre`, `/contacto` y `/privacidad`.
En producción se apunta al dominio real antes de construir la imagen y `ALLOWED_HOSTS` al
host público.

### Producción

El stack de producción no compila en el servidor: descarga las imágenes de GHCR y solo
expone Caddy en 80/443. Los secretos viven en `.env.prod` (permisos 600, ignorado por git),
generado con `ops/generate-env.sh` a partir de `.env.prod.example`.

```bash
cp .env.prod.example .env.prod   # o ./ops/generate-env.sh
docker compose --env-file .env.prod -f docker-compose.prod.yml config
./ops/deploy.sh latest
```

El despliegue real, TLS, backups, restauración, monitorización, hardening y checklist
RGPD están en
[`docs/06-produccion.md`](./the-blast-beast-api/docs/06-produccion.md).

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

M1–M4 se validaron de extremo a extremo sobre PostgreSQL real, no sobre un sustituto:

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
- `/sitemap.xml` responde con URLs absolutas, `lastmod` e `image:loc` de la variante `hero`;
  `/robots.txt` bloquea `/admin` y `/api/`; `/feed.xml` y `/categorias/{slug}/feed.xml`
  devuelven RSS 2.0 con `content:encoded` y `media:content` en UTF-8.
- Sitemap y feeds responden `304 Not Modified` con el ETag correcto.
- `/sobre`, `/contacto` y `/privacidad` se sirven prerenderizadas con canonical absoluto al
  origen público; la portada y el detalle publican JSON-LD `WebSite`, `NewsArticle` y
  `BreadcrumbList`.
- Hidratación sin errores de consola más allá de los 4xx esperados al pedir contenido
  retirado o inexistente.
- El transfer cache de Angular reutiliza en el navegador las respuestas del SSR: la portada
  se hidrata sin repetir peticiones a `/api`. `CacheControlFilter` marca el contenido público
  como cacheable y el área privada como `no-store`.
- `mvn clean verify`: 29 unitarios + 41 de integración con Testcontainers, JaCoCo en 93,6 %
  de líneas de servicio.
- `npm run e2e`: 12 tests de Playwright en verde; axe sin violaciones WCAG 2.1 AA.
- `npm run lighthouse`: medianas de 0,92–0,96 en rendimiento, 0,98–1,00 en accesibilidad,
  buenas prácticas y SEO sobre las cuatro URLs medidas.

Docker Desktop y WSL 2 se instalaron en esta máquina solo como entorno local; el proyecto
no depende de esa configuración: cualquier Docker con contenedores Linux sirve.
