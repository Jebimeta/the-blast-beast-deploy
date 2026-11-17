#!/usr/bin/env bash
# Despliegue con pull de GHCR, espera de healthchecks, smoke test y rollback.
#
# Uso:
#   ./ops/deploy.sh <api-tag> <web-tag>
#   ./ops/deploy.sh --rollback       # vuelve al par guardado en .deployed-images
#   ./ops/deploy.sh                  # usa API_IMAGE_TAG/WEB_IMAGE_TAG de .env.prod
#
# Ejemplos:
#   ./ops/deploy.sh latest latest
#   ./ops/deploy.sh 0aad223c c2dce7ee
#   ./ops/deploy.sh --rollback
#
# Requisitos en el servidor:
#   - Paquetes de GHCR públicos, o docker login ghcr.io si son privados.
#   - .env.prod generado con ops/generate-env.sh
#
# El par de tags del último despliegue correcto queda en `.deployed-images` para
# poder volver atrás si el nuevo no pasa el smoke test. API y web son repos
# distintos: usa SHA inmutables, no `latest`, para que el rollback sea real.
# Las migraciones Flyway son forward-only: un rollback de imagen no revierte el
# esquema. Por eso el deploy hace un backup antes de tocar nada.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env.prod}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/docker-compose.prod.yml}"
STATE_FILE="${STATE_FILE:-$ROOT_DIR/.deployed-images}"

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

previous_tag() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || return 0
  sed -n "s/^${key}=//p" "$STATE_FILE" | head -n 1
}

PREVIOUS_API="$(previous_tag API_IMAGE_TAG)"
PREVIOUS_WEB="$(previous_tag WEB_IMAGE_TAG)"

ROLLBACK=false
if [[ "${1:-}" == "--rollback" ]]; then
  ROLLBACK=true
  shift
fi

if [[ "$ROLLBACK" == true ]]; then
  [[ $# -eq 0 ]] || {
    echo "Uso: $0 --rollback" >&2
    exit 1
  }
  [[ -n "$PREVIOUS_API" && -n "$PREVIOUS_WEB" ]] \
    || die "no hay un par anterior en $STATE_FILE"
  API_TAG="$PREVIOUS_API"
  WEB_TAG="$PREVIOUS_WEB"
else
  if [[ $# -eq 1 || $# -gt 2 ]]; then
    echo "Uso: $0 <api-tag> <web-tag>" >&2
    echo "     $0   # usa API_IMAGE_TAG/WEB_IMAGE_TAG de .env.prod" >&2
    exit 1
  fi
  API_TAG="${1:-${API_IMAGE_TAG:-latest}}"
  WEB_TAG="${2:-${WEB_IMAGE_TAG:-latest}}"
fi

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

log "Desplegando API='$API_TAG' web='$WEB_TAG' (anterior: API='${PREVIOUS_API:-ninguno}', web='${PREVIOUS_WEB:-ninguno}')"
API_IMAGE_TAG="$API_TAG" WEB_IMAGE_TAG="$WEB_TAG" "${COMPOSE[@]}" pull api web
API_IMAGE_TAG="$API_TAG" WEB_IMAGE_TAG="$WEB_TAG" "${COMPOSE[@]}" up -d --remove-orphans

if wait_healthy api && wait_healthy web && wait_healthy caddy && smoke; then
  umask 077
  {
    printf 'API_IMAGE_TAG=%s\n' "$API_TAG"
    printf 'WEB_IMAGE_TAG=%s\n' "$WEB_TAG"
  } > "$STATE_FILE"
  docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true
  log "Despliegue correcto: $SITE_BASE_URL (API $API_TAG, web $WEB_TAG)"
  exit 0
fi

log "El despliegue no pasó las comprobaciones."
if [[ "$ROLLBACK" == true ]]; then
  log "El rollback manual no pasó las comprobaciones. Intervención manual necesaria."
  exit 1
fi
if [[ -n "$PREVIOUS_API" && -n "$PREVIOUS_WEB" ]]; then
  log "Rollback a API='$PREVIOUS_API', web='$PREVIOUS_WEB'…"
  API_IMAGE_TAG="$PREVIOUS_API" WEB_IMAGE_TAG="$PREVIOUS_WEB" \
    "${COMPOSE[@]}" pull api web || true
  API_IMAGE_TAG="$PREVIOUS_API" WEB_IMAGE_TAG="$PREVIOUS_WEB" \
    "${COMPOSE[@]}" up -d --remove-orphans
  if wait_healthy api && wait_healthy web && wait_healthy caddy && smoke; then
    log "Rollback completado. Revisa los logs de API=$API_TAG, web=$WEB_TAG."
  else
    log "El rollback tampoco quedó sano. Intervención manual necesaria."
  fi
else
  log "No hay un par anterior en $STATE_FILE; no se puede hacer rollback."
fi

exit 1
