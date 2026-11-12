#!/usr/bin/env bash
# Backup consistente de PostgreSQL + volumen de medios.
#
# Uso:
#   ./ops/backup.sh
#
# Variables (se leen de .env.prod y se pueden sobrescribir en el entorno):
#   ENV_FILE, COMPOSE_FILE, BACKUP_DIR, BACKUP_RETENTION_DAYS,
#   BACKUP_AGE_RECIPIENT
#
# El backup se escribe como `blast-beast-<UTC>.tar.gz` (o `.age` si hay
# destinatario age) junto a un `.sha256`. La restauración se prueba con
# `./ops/restore-backup.sh <archivo>`.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env.prod}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/docker-compose.prod.yml}"
PROJECT="${COMPOSE_PROJECT_NAME:-the-blast-beast}"

CLI_BACKUP_DIR="${BACKUP_DIR:-}"
CLI_RETENTION="${BACKUP_RETENTION_DAYS:-}"
CLI_AGE="${BACKUP_AGE_RECIPIENT:-}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

BACKUP_DIR="${CLI_BACKUP_DIR:-${BACKUP_DIR:-/var/backups/the-blast-beast}}"
RETENTION="${CLI_RETENTION:-${BACKUP_RETENTION_DAYS:-14}}"
AGE_RECIPIENT="${CLI_AGE:-${BACKUP_AGE_RECIPIENT:-}}"
DB_NAME="${DB_NAME:-blastbeast}"
DB_USER="${DB_USER:-blastbeast}"
MEDIA_VOLUME="${PROJECT}_media"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker no está disponible"
[[ -f "$COMPOSE_FILE" ]] || die "no existe $COMPOSE_FILE"

if [[ -n "$AGE_RECIPIENT" ]] && ! command -v age >/dev/null 2>&1; then
  die "BACKUP_AGE_RECIPIENT está definido pero falta el binario 'age'"
fi

mkdir -p "$BACKUP_DIR"
umask 077

# Evita dos backups solapados si el timer se retrasa.
exec 9>"$BACKUP_DIR/.backup.lock"
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || die "ya hay un backup en curso"
fi

COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

if ! "${COMPOSE[@]}" ps --status running --services 2>/dev/null | grep -qx db; then
  die "el contenedor de PostgreSQL no está en marcha"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bb-backup.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
log "Volcando PostgreSQL ($DB_NAME)…"
"${COMPOSE[@]}" exec -T db \
  pg_dump -U "$DB_USER" -d "$DB_NAME" \
  --format=custom --no-owner --no-privileges > "$WORK_DIR/db.dump"

[[ -s "$WORK_DIR/db.dump" ]] || die "pg_dump generó un archivo vacío"

log "Empaquetando el volumen de medios ($MEDIA_VOLUME)…"
docker volume inspect "$MEDIA_VOLUME" >/dev/null 2>&1 \
  || die "no existe el volumen $MEDIA_VOLUME"

MEDIA_FILES="$(docker run --rm \
  -v "$MEDIA_VOLUME:/media:ro" \
  alpine:3.20 sh -c 'find /media -type f | wc -l' | tr -d '[:space:]')"

docker run --rm \
  -v "$MEDIA_VOLUME:/media:ro" \
  -v "$WORK_DIR:/backup:rw" \
  alpine:3.20 tar czf /backup/media.tar.gz -C /media .

COUNTS="$("${COMPOSE[@]}" exec -T db psql -U "$DB_USER" -d "$DB_NAME" -Atc "
  select 'articles=' || count(*) from articles
  union all select 'users=' || count(*) from users
  union all select 'categories=' || count(*) from categories
  union all select 'bands=' || count(*) from bands
  union all select 'tags=' || count(*) from tags
  union all select 'media_assets=' || count(*) from media_assets
  union all select 'article_revisions=' || count(*) from article_revisions
  union all select 'refresh_tokens=' || count(*) from refresh_tokens
  union all select 'newsletter_subscribers=' || count(*) from newsletter_subscribers
")"

{
  echo "timestamp=$TIMESTAMP"
  echo "db_name=$DB_NAME"
  echo "image_tag=${IMAGE_TAG:-unknown}"
  echo "media_files=$MEDIA_FILES"
  echo "counts:"
  echo "$COUNTS" | awk '{print "count." $0}'
} > "$WORK_DIR/manifest.txt"

ARCHIVE="$BACKUP_DIR/blast-beast-$TIMESTAMP.tar.gz"
tar czf "$ARCHIVE" -C "$WORK_DIR" db.dump media.tar.gz manifest.txt

FINAL="$ARCHIVE"
if [[ -n "$AGE_RECIPIENT" ]]; then
  log "Cifrando con age…"
  age --recipient "$AGE_RECIPIENT" --output "$ARCHIVE.age" "$ARCHIVE"
  rm -f "$ARCHIVE"
  FINAL="$ARCHIVE.age"
fi

sha256sum "$FINAL" | awk '{print $1}' > "$FINAL.sha256"

log "Backup completado: $FINAL ($(du -h "$FINAL" | cut -f1))"
log "Recuentos: $(printf '%s' "$COUNTS" | tr '\n' ' ')"

find "$BACKUP_DIR" -maxdepth 1 -type f -name 'blast-beast-*' \
  -mtime +"$RETENTION" -print -delete

log "Retención aplicada: $RETENTION días"
