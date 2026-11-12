#!/usr/bin/env bash
# Verifica un backup y, opcionalmente, lo restaura en producción.
#
# Uso:
#   ./ops/restore-backup.sh <backup.tar.gz|backup.tar.gz.age>            # solo verifica
#   ./ops/restore-backup.sh <backup> --apply [--yes]                     # restaura
#
# La verificación arranca un PostgreSQL temporal, restaura el dump y compara
# los recuentos de tablas y el número de ficheros de medios con el manifiesto.
# Solo si todo coincide permite aplicar el backup.
#
# Variables:
#   ENV_FILE, COMPOSE_FILE, AGE_IDENTITY_FILE (clave privada age)

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env.prod}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/docker-compose.prod.yml}"
PROJECT="${COMPOSE_PROJECT_NAME:-the-blast-beast}"

APPLY=false
YES=false
BACKUP_FILE=""

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=true ;;
    --yes) YES=true ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    -*)
      echo "Argumento desconocido: $arg" >&2
      exit 1
      ;;
    *)
      [[ -z "$BACKUP_FILE" ]] || { echo "Solo se admite un backup." >&2; exit 1; }
      BACKUP_FILE="$arg"
      ;;
  esac
done

[[ -n "$BACKUP_FILE" ]] || { echo "Falta el archivo de backup." >&2; exit 1; }
[[ -f "$BACKUP_FILE" ]] || { echo "No existe $BACKUP_FILE" >&2; exit 1; }

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

DB_NAME="${DB_NAME:-blastbeast}"
DB_USER="${DB_USER:-blastbeast}"
MEDIA_VOLUME="${PROJECT}_media"
[[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || { echo "DB_NAME no válido." >&2; exit 1; }

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker no está disponible"
[[ -f "$COMPOSE_FILE" ]] || die "no existe $COMPOSE_FILE"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bb-restore.XXXXXX")"
CONTAINER="bb-restore-$$"
cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# 1. Integridad del archivo.
if [[ -f "$BACKUP_FILE.sha256" ]]; then
  expected="$(tr -d '[:space:]' < "$BACKUP_FILE.sha256")"
  actual="$(sha256sum "$BACKUP_FILE" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || die "el checksum no coincide"
  log "Checksum OK"
else
  log "Aviso: no hay .sha256 junto al backup; se omite la comprobación"
fi

# 2. Descifrado y extracción.
if [[ "$BACKUP_FILE" == *.age ]]; then
  [[ -n "${AGE_IDENTITY_FILE:-}" ]] || die "define AGE_IDENTITY_FILE con la clave privada age"
  command -v age >/dev/null 2>&1 || die "falta el binario 'age'"
  log "Descifrando…"
  age --decrypt --identity "$AGE_IDENTITY_FILE" --output "$WORK_DIR/backup.tar.gz" "$BACKUP_FILE"
else
  cp "$BACKUP_FILE" "$WORK_DIR/backup.tar.gz"
fi

tar xzf "$WORK_DIR/backup.tar.gz" -C "$WORK_DIR"
for required in db.dump media.tar.gz manifest.txt; do
  [[ -f "$WORK_DIR/$required" ]] || die "el backup no contiene $required"
done

EXPECTED_MEDIA="$(sed -n 's/^media_files=//p' "$WORK_DIR/manifest.txt")"
ACTUAL_MEDIA="$(tar tzf "$WORK_DIR/media.tar.gz" | awk '!/\/$/ && $0 != "." {n++} END {print n+0}')"
[[ -z "$EXPECTED_MEDIA" || "$EXPECTED_MEDIA" == "$ACTUAL_MEDIA" ]] \
  || die "medios: esperados $EXPECTED_MEDIA, encontrados $ACTUAL_MEDIA"

# 3. Restauración en un PostgreSQL temporal.
log "Arrancando PostgreSQL temporal…"
docker run -d --rm --name "$CONTAINER" \
  -e POSTGRES_PASSWORD=restore \
  -e POSTGRES_DB=restore \
  -p 127.0.0.1::5432 \
  postgres:17-alpine >/dev/null

for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" pg_isready -U postgres -d restore >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
docker exec "$CONTAINER" pg_isready -U postgres -d restore >/dev/null 2>&1 \
  || die "el PostgreSQL temporal no arrancó"

log "Restaurando el dump…"
docker cp "$WORK_DIR/db.dump" "$CONTAINER:/tmp/db.dump" >/dev/null
docker exec "$CONTAINER" pg_restore \
  -U postgres -d restore --no-owner --no-privileges --exit-on-error /tmp/db.dump

# 4. Comparación con el manifiesto.
failures=0
while IFS='=' read -r table expected; do
  [[ "$table" =~ ^[a-z_]+$ ]] || continue
  actual="$(docker exec "$CONTAINER" psql -U postgres -d restore -Atc "select count(*) from $table")"
  if [[ "$actual" == "$expected" ]]; then
    log "  $table: $actual"
  else
    log "  $table: esperado $expected, restaurado $actual"
    failures=$((failures + 1))
  fi
done < <(grep -E '^count\.[a-z_]+=[0-9]+$' "$WORK_DIR/manifest.txt" | sed 's/^count\.//')

[[ "$failures" -eq 0 ]] || die "la verificación encontró $failures diferencias"
log "Backup verificado: $ACTUAL_MEDIA ficheros de medios y todos los recuentos coinciden"

if [[ "$APPLY" != true ]]; then
  log "Modo verificación. No se ha tocado producción."
  exit 0
fi

# 5. Aplicación en producción.
if [[ "$YES" != true ]]; then
  echo
  echo "Esto reemplazará la base de datos '$DB_NAME' y el volumen '$MEDIA_VOLUME'."
  read -r -p "Escribe RESTAURAR para continuar: " answer
  [[ "$answer" == "RESTAURAR" ]] || { echo "Cancelado."; exit 1; }
fi

COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

log "Parando API y web…"
"${COMPOSE[@]}" stop api web >/dev/null

log "Recreando la base de datos…"
"${COMPOSE[@]}" exec -T db psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -c \
  "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$DB_NAME' and pid <> pg_backend_pid();" >/dev/null
"${COMPOSE[@]}" exec -T db psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -c \
  "drop database if exists \"$DB_NAME\";" >/dev/null
"${COMPOSE[@]}" exec -T db psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -c \
  "create database \"$DB_NAME\";" >/dev/null

"${COMPOSE[@]}" exec -T db pg_restore \
  -U "$DB_USER" -d "$DB_NAME" --no-owner --no-privileges --exit-on-error \
  < "$WORK_DIR/db.dump"

log "Restaurando medios…"
docker run --rm -v "$MEDIA_VOLUME:/media" alpine:3.20 \
  sh -c 'find /media -mindepth 1 -delete'
docker run --rm \
  -v "$MEDIA_VOLUME:/media" \
  -v "$WORK_DIR:/backup:ro" \
  alpine:3.20 tar xzf /backup/media.tar.gz -C /media

log "Arrancando API y web…"
"${COMPOSE[@]}" up -d api web >/dev/null

for service in api web; do
  id="$("${COMPOSE[@]}" ps -q "$service")"
  healthy=false
  for _ in $(seq 1 60); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || true)"
    if [[ "$status" == "healthy" ]]; then
      healthy=true
      break
    fi
    sleep 2
  done
  [[ "$healthy" == true ]] || die "$service no quedó healthy tras la restauración"
done

SITE_BASE_URL="${SITE_BASE_URL:-http://localhost}"
curl -fsS --max-time 15 "$SITE_BASE_URL/api/v1/ping" >/dev/null \
  || die "la API no responde tras la restauración"
curl -fsS --max-time 15 -o /dev/null "$SITE_BASE_URL/" \
  || die "el sitio no responde tras la restauración"

log "Restauración completada y verificada en caliente."
