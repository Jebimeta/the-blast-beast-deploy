#!/usr/bin/env bash
# Genera `.env.prod` con secretos aleatorios y los datos del dominio.
#
# Uso:
#   ./ops/generate-env.sh [--force]
#
# El archivo resultante se crea con permisos 600 y no se versiona.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.prod"
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *)
      echo "Argumento desconocido: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ -f "$ENV_FILE" && "$FORCE" != true ]]; then
  echo "Ya existe $ENV_FILE. Usa --force para sobrescribirlo." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "Falta openssl. Instálalo antes de continuar." >&2
  exit 1
fi

read -r -p "Dominio apex (sin https ni www) [theblastbeast.com]: " SITE_DOMAIN
SITE_DOMAIN="${SITE_DOMAIN:-theblastbeast.com}"

read -r -p "Correo para Let's Encrypt [admin@${SITE_DOMAIN}]: " ACME_EMAIL
ACME_EMAIL="${ACME_EMAIL:-admin@${SITE_DOMAIN}}"

read -r -p "Email del primer administrador [redaccion@${SITE_DOMAIN}]: " ADMIN_EMAIL
ADMIN_EMAIL="${ADMIN_EMAIL:-redaccion@${SITE_DOMAIN}}"

if [[ ! "$SITE_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo "Dominio no válido: $SITE_DOMAIN" >&2
  exit 1
fi

DB_PASSWORD="$(openssl rand -hex 24)"
JWT_SECRET="$(openssl rand -base64 48 | tr -d '\n')"
ADMIN_PASSWORD="$(openssl rand -base64 18 | tr -d '\n')"

umask 077
cat > "$ENV_FILE" <<EOF
# Generado por ops/generate-env.sh el $(date -u +%FT%TZ).
# No versionar. Permisos 600.

SITE_DOMAIN=$SITE_DOMAIN
ACME_EMAIL=$ACME_EMAIL
SITE_BASE_URL=https://$SITE_DOMAIN
# Orígenes CORS permitidos, separados por comas. Vacío = SITE_BASE_URL.
CORS_ALLOWED_ORIGINS=
ALLOWED_HOSTS=$SITE_DOMAIN,www.$SITE_DOMAIN
HTTP_PORT=80
HTTPS_PORT=443

DB_NAME=blastbeast
DB_USER=blastbeast
DB_PASSWORD=$DB_PASSWORD

JWT_SECRET=$JWT_SECRET
AUTH_COOKIE_SECURE=true
AUTH_COOKIE_DOMAIN=
# Límite de intentos fallidos de login (por IP + email y por IP).
AUTH_LOGIN_WINDOW=PT15M
AUTH_LOGIN_MAX_ATTEMPTS=5
AUTH_LOGIN_MAX_ATTEMPTS_PER_IP=20

STORAGE_PUBLIC_BASE_URL=https://$SITE_DOMAIN/media

ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_PASSWORD=$ADMIN_PASSWORD
ADMIN_DISPLAY_NAME=Redacción Blast Beast

# Agenda de conciertos. Rellena TICKETMASTER_API_KEY y pon ENABLED=true para
# importar automáticamente los conciertos de España.
TICKETMASTER_ENABLED=false
TICKETMASTER_API_KEY=

# Difusión en redes (IA opcional). Sin AI_API_KEY se usa una plantilla local y
# el texto del artículo no sale del servidor.
AI_BASE_URL=https://api.openai.com/v1
AI_API_KEY=
AI_MODEL=gpt-4o-mini
AI_TIMEOUT=20s

# Imágenes a desplegar. 'latest' o el SHA del commit publicado en cada repo.
# En producción usa SHA inmutables: API y web son repos distintos.
API_IMAGE_TAG=latest
WEB_IMAGE_TAG=latest

BACKUP_DIR=/var/backups/the-blast-beast
BACKUP_RETENTION_DAYS=14
BACKUP_AGE_RECIPIENT=

ALERT_WEBHOOK_URL=
EOF

chmod 600 "$ENV_FILE"

cat <<EOF

[+] Creado $ENV_FILE

Guarda estas credenciales en tu gestor de contraseñas; no se vuelven a mostrar:

  Admin:  $ADMIN_EMAIL
  Clave:  $ADMIN_PASSWORD

Siguientes pasos:
  1. Revisa BACKUP_AGE_RECIPIENT y ALERT_WEBHOOK_URL en $ENV_FILE.
  2. Las imágenes de GHCR son públicas; no hace falta login salvo que las privatices.
  3. ./ops/deploy.sh latest latest

Para desplegar una versión concreta:
  ./ops/deploy.sh <sha-api> <sha-web>
EOF
