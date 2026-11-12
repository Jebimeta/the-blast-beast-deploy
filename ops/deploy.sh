#!/usr/bin/env bash
# Despliegue con pull de GHCR, espera de healthchecks, smoke test y rollback.
#
# Uso:
#   ./ops/deploy.sh <tag>        # tag = latest o SHA del commit
#
# Requisitos en el servidor:
#   - docker login ghcr.io (o paquetes públicos)
#   - .env.prod generado con ops/generate-env.sh
#
# El tag del último despliegue correcto queda en `.deployed-tag` para poder
# volver atrás si el nuevo no pasa el smoke test. Las migraciones Flyway son
# forward-only: un rollback de imagen no revierte el esquema. Por eso el deploy
# hace un backup antes de tocar nada.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env.prod}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/docker-compose.prod.yml}"
TAG="${1:-${IMAGE_TAG:-latest}}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

SITE_BASE_URL="${SITE_BASE_URL:-http://localhost}"
SITE_BASE_URL="${SITE_BASE_URL%/}"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker no está disponible"
[[ -f "$COMPOSE_FILE" ]] || die "no existe $COMPOSE_FILE"
[[ -f "$ENV_FILE" ]] || die "no existe $ENV_FILE; ejecuta ops/generate-env.sh"

COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
PREVIOUS="$(cat "$ROOT_DIR/.deployed-tag" 2>/dev/null || true)"

wait_healthy() {
  local service="$1" id status
  id="$("${COMPOSE[@]}" ps -q "$service")"
  [[ -n "$id" ]] || return 1
  for _ in $(seq 1 60); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || true)"
    [[ "$status" == "healthy" ]] && return 0
    sleep 2
  done
  log "$service no quedó healthy (último estado: ${status:-desconocido})"
  return 1
}

smoke() {
  curl -fsS --max-time 15 "$SITE_BASE_URL/api/v1/ping" >/dev/null 2>&1 || return 1
  curl -fsS --max-time 15 -o /dev/null "$SITE_BASE_URL/" || return 1
  curl -fsS --max-time 15 "$SITE_BASE_URL/sitemap.xml" 2>/dev/null | grep -q '<urlset' || return 1
  return 0
}

if [[ "${BACKUP_BEFORE_DEPLOY:-true}" != "false" ]]; then
  if "${COMPOSE[@]}" ps --status running --services 2>/dev/null | grep -qx db; then
    log "Backup previo al despliegue…"
    "$ROOT_DIR/ops/backup.sh"
  else
    log "No hay base de datos en marcha; se omite el backup del primer despliegue."
  fi
fi

log "Desplegando tag '$TAG' (anterior: '${PREVIOUS:-ninguno}')"
IMAGE_TAG="$TAG" "${COMPOSE[@]}" pull
IMAGE_TAG="$TAG" "${COMPOSE[@]}" up -d --remove-orphans

if wait_healthy api && wait_healthy web && wait_healthy caddy && smoke; then
  printf '%s\n' "$TAG" > "$ROOT_DIR/.deployed-tag"
  docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true
  log "Despliegue correcto: $SITE_BASE_URL (tag $TAG)"
  exit 0
fi

log "El despliegue no pasó las comprobaciones."
if [[ -n "$PREVIOUS" ]]; then
  log "Rollback a '$PREVIOUS'…"
  IMAGE_TAG="$PREVIOUS" "${COMPOSE[@]}" up -d --remove-orphans
  if wait_healthy api && wait_healthy web && smoke; then
    log "Rollback completado. Revisa los logs del tag $TAG."
  else
    log "El rollback tampoco quedó sano. Intervención manual necesaria."
  fi
fi

exit 1
