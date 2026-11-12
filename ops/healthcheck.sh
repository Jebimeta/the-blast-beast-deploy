#!/usr/bin/env bash
# Healthcheck externo + alertas. Pensado para un timer de systemd cada 2 minutos.
#
# Comprueba API, portada, sitemap, PostgreSQL y espacio en disco. Si algo falla,
# envía un aviso a ALERT_WEBHOOK_URL (formato Slack; Discord acepta /slack) y
# recuerda el estado para no repetir la alerta en cada ejecución.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env.prod}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/docker-compose.prod.yml}"
STATE_FILE="${STATE_FILE:-/var/lib/the-blast-beast/health.state}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

SITE_BASE_URL="${SITE_BASE_URL:-http://localhost:8088}"
SITE_BASE_URL="${SITE_BASE_URL%/}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
DB_NAME="${DB_NAME:-blastbeast}"
DB_USER="${DB_USER:-blastbeast}"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

send_alert() {
  local message="$1"
  [[ -n "$ALERT_WEBHOOK_URL" ]] || return 0

  local payload
  if command -v jq >/dev/null 2>&1; then
    payload="$(printf '%s' "$message" | jq -Rs '{text: .}')"
  else
    payload="{\"text\":\"$message\"}"
  fi

  curl -fsS --max-time 10 -X POST \
    -H 'Content-Type: application/json' \
    -d "$payload" "$ALERT_WEBHOOK_URL" >/dev/null 2>&1 \
    || log "No se pudo entregar la alerta al webhook"
}

failures=()

api_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$SITE_BASE_URL/api/v1/ping" 2>/dev/null || true)"
[[ "$api_code" == "200" ]] || failures+=("API /ping HTTP $api_code")

home_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$SITE_BASE_URL/" 2>/dev/null || true)"
[[ "$home_code" == "200" ]] || failures+=("portada HTTP $home_code")

if ! curl -fsS --max-time 10 "$SITE_BASE_URL/sitemap.xml" 2>/dev/null | grep -q '<urlset'; then
  failures+=("sitemap.xml inválido")
fi

if ! curl -fsS --max-time 10 "$SITE_BASE_URL/robots.txt" 2>/dev/null | grep -q 'Sitemap:'; then
  failures+=("robots.txt sin sitemap")
fi

if command -v docker >/dev/null 2>&1 && [[ -f "$COMPOSE_FILE" ]]; then
  if ! docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" \
    exec -T db pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
    failures+=("PostgreSQL no responde")
  fi
fi

disk_usage="$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
[[ "${disk_usage:-0}" -lt 90 ]] || failures+=("disco al ${disk_usage}%")

if [[ "$SITE_BASE_URL" == https://* ]] && command -v openssl >/dev/null 2>&1; then
  host="$(printf '%s' "$SITE_BASE_URL" | sed -E 's#^https://##; s#/.*$##; s#:.*$##')"
  end_date="$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
  if [[ -n "$end_date" ]]; then
    end_epoch="$(date -d "$end_date" +%s 2>/dev/null || echo 0)"
    days_left=$(( (end_epoch - $(date +%s)) / 86400 ))
    [[ "$days_left" -ge 14 ]] || failures+=("certificado TLS caduca en $days_left días")
  else
    failures+=("no se pudo leer el certificado TLS")
  fi
fi

mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
previous="$(cat "$STATE_FILE" 2>/dev/null || echo up)"

if [[ "${#failures[@]}" -gt 0 ]]; then
  message="The Blast Beast ($SITE_BASE_URL) con problemas: ${failures[*]}"
  log "$message"
  send_alert "$message"
  printf 'down\n' > "$STATE_FILE" 2>/dev/null || true
  exit 1
fi

log "OK: API, portada, sitemap, robots, PostgreSQL y disco"
if [[ "$previous" == "down" ]]; then
  send_alert "The Blast Beast ($SITE_BASE_URL) vuelve a estar sano."
fi
printf 'up\n' > "$STATE_FILE" 2>/dev/null || true
