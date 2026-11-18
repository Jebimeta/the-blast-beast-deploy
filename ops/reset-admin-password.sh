#!/usr/bin/env bash
# Restablece la contraseña de un usuario de redacción sin usar el correo.
#
# Uso:
#   ./ops/reset-admin-password.sh [email]
#
# La contraseña se pide por consola y no queda en el historial. Se ejecuta una
# tarea de mantenimiento dentro de la imagen de la API (perfil reset-password)
# que no abre el puerto HTTP y termina al acabar.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env.prod}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/docker-compose.prod.yml}"
EMAIL="${1:-${RESET_PASSWORD_EMAIL:-}}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || die "docker no está disponible"
[[ -f "$ENV_FILE" ]] || die "no existe $ENV_FILE; ejecuta ops/generate-env.sh"
[[ -f "$COMPOSE_FILE" ]] || die "no existe $COMPOSE_FILE"

if [[ -z "$EMAIL" ]]; then
  read -r -p "Email del administrador: " EMAIL
fi
[[ -n "$EMAIL" ]] || die "el email no puede estar vacío"

read -r -s -p "Nueva contraseña (mínimo 12 caracteres): " PASSWORD
echo
read -r -s -p "Repite la contraseña: " PASSWORD_CONFIRM
echo

[[ ${#PASSWORD} -ge 12 ]] || die "la contraseña debe tener al menos 12 caracteres"
[[ "$PASSWORD" == "$PASSWORD_CONFIRM" ]] || die "las contraseñas no coinciden"

# Se exporta para no pasar la contraseña en la línea de comandos (visible en `ps`).
export RESET_PASSWORD="$PASSWORD"
export RESET_PASSWORD_EMAIL="$EMAIL"

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" run --rm \
  -e SPRING_PROFILES_ACTIVE=prod,reset-password \
  -e RESET_PASSWORD_EMAIL \
  -e RESET_PASSWORD \
  api
