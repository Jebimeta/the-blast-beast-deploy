#!/usr/bin/env bash
# Preparación de un VPS Ubuntu/Debian recién creado.
#
# Uso (como root, desde el repo ya clonado):
#   sudo SSH_PORT=22 ./ops/bootstrap-vps.sh
#
# Hace lo siguiente:
#   - Instala Docker, UFW, fail2ban, unattended-upgrades, age, jq y utilidades.
#   - Activa el firewall permitiendo solo SSH, 80 y 443.
#   - Rota los logs de Docker y activa live-restore.
#   - Añade swap si hay menos de 4 GB de RAM.
#   - Instala los timers de backup y healthcheck.
#
# NO modifica sshd: el cambio a solo-clave se hace a mano siguiendo
# docs/06-produccion.md, comprobando `sshd -t` antes de reiniciar.

set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta este script como root (sudo)." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_PORT="${SSH_PORT:-22}"
DEPLOY_USER="${DEPLOY_USER:-${SUDO_USER:-}}"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

if ! grep -qiE '^(ID|ID_LIKE)=.*(ubuntu|debian)' /etc/os-release; then
  log "Aviso: este script está pensado para Ubuntu/Debian. Continúa bajo tu responsabilidad."
fi

if [[ -z "$DEPLOY_USER" || "$DEPLOY_USER" == "root" ]]; then
  if id ubuntu >/dev/null 2>&1; then
    DEPLOY_USER=ubuntu
  else
    DEPLOY_USER=deploy
    if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
      log "Creando usuario $DEPLOY_USER…"
      useradd --create-home --shell /bin/bash "$DEPLOY_USER"
    fi
  fi
fi

log "Usuario de despliegue: $DEPLOY_USER"
log "Puerto SSH permitido: $SSH_PORT"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg git ufw fail2ban unattended-upgrades \
  age jq openssl logrotate

if ! command -v docker >/dev/null 2>&1; then
  log "Instalando Docker…"
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker
usermod -aG docker "$DEPLOY_USER" 2>/dev/null || true

if [[ ! -f /etc/docker/daemon.json ]]; then
  log "Configurando el daemon de Docker…"
  cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true
}
EOF
  systemctl restart docker
else
  log "Aviso: /etc/docker/daemon.json ya existe; revísalo a mano."
fi

cat > /etc/sysctl.d/99-the-blast-beast.conf <<'EOF'
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
kernel.dmesg_restrict = 1
EOF
sysctl --system >/dev/null

log "Configurando UFW…"
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp"
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port = $SSH_PORT
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades

mem_mb="$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)"
swap_count="$(swapon --show --noheadings 2>/dev/null | wc -l | tr -d '[:space:]')"
if [[ "$mem_mb" -lt 4096 && "$swap_count" -eq 0 ]]; then
  log "Añadiendo 2 GB de swap (RAM detectada: ${mem_mb} MB)…"
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  cat > /etc/sysctl.d/99-swappiness.conf <<'EOF'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF
  sysctl --system >/dev/null
fi

install -d -m 750 -o "$DEPLOY_USER" -g "$DEPLOY_USER" /opt/the-blast-beast
install -d -m 700 /var/backups/the-blast-beast
install -d -m 755 /var/lib/the-blast-beast

if [[ -d "$ROOT_DIR/ops/systemd" ]]; then
  log "Instalando timers de backup y healthcheck…"
  install -m 644 "$ROOT_DIR"/ops/systemd/*.service /etc/systemd/system/
  install -m 644 "$ROOT_DIR"/ops/systemd/*.timer /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now the-blast-beast-backup.timer
  systemctl enable --now the-blast-beast-healthcheck.timer
fi

cat <<EOF

[+] VPS preparado.

Siguientes pasos:
  1. Copia la clave pública SSH del usuario $DEPLOY_USER y desactiva el login
     por contraseña siguiendo docs/06-produccion.md (no reinicies sshd sin
     comprobar antes 'sshd -t').
  2. Clona el repo en /opt/the-blast-beast y ejecuta ./ops/generate-env.sh.
  3. Haz docker login ghcr.io (o publica los paquetes de GHCR).
  4. ./ops/deploy.sh latest

Comprueba el firewall con: ufw status verbose
EOF
