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
ALLOWED_HOSTS=$SITE_DOMAIN,www.$SITE_DOMAIN
HTTP_PORT=80
HTTPS_PORT=443

DB_NAME=blastbeast
DB_USER=blastbeast
DB_PASSWORD=$DB_PASSWORD

JWT_SECRET=$JWT_SECRET
AUTH_COOKIE_SECURE=true
AUTH_COOKIE_DOMAIN=

STORAGE_PUBLIC_BASE_URL=https://$SITE_DOMAIN/media

ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_PASSWORD=$ADMIN_PASSWORD
ADMIN_DISPLAY_NAME=Redacción Blast Beast

IMAGE_TAG=latest

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
  2. Haz login en GHCR en el servidor (o publica las imágenes).
  3. ./ops/deploy.sh latest

Cambia la contraseña del administrador después del primer acceso.
EOF
