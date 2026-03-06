#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Ubuntu OpenClaw EasyMode Bootstrap"
APP_VERSION="1.2.0"

AI_ROOT="${AI_ROOT:-$HOME/ai}"
OPENCLAW_DIR="${OPENCLAW_DIR:-$AI_ROOT/openclaw}"
OPENCLAW_REPO="${OPENCLAW_REPO:-https://github.com/openclaw/openclaw.git}"
NODE_MAJOR="${NODE_MAJOR:-22}"

LOG_FILE="${LOG_FILE:-$AI_ROOT/bootstrap.log}"
OPENCLAW_DASHBOARD_URL="${OPENCLAW_DASHBOARD_URL:-http://127.0.0.1:3000}"
AUTO_LAUNCH_OPENCLAW="${AUTO_LAUNCH_OPENCLAW:-1}"
CREATE_OPENCLAW_SHORTCUT="${CREATE_OPENCLAW_SHORTCUT:-1}"
OPENCLAW_AUTOSTART="${OPENCLAW_AUTOSTART:-1}"

INSTALL_BASE=1
INSTALL_SECURITY=0
INSTALL_DEV_TOOLS=1
INSTALL_DOCKER=1
INSTALL_NODE=1
INSTALL_GH=1
INSTALL_SHORTCUTS=1
INSTALL_OPENCLAW=0
CONFIGURE_OPENCLAW=0

NONINTERACTIVE_MODE=0
DRY_RUN=0
YES_MODE=0
SKIP_UPDATE=0
RUN_CLEANUP=0

show_reboot_notice=0
docker_group_added=0
SUDO_KEEPALIVE_PID=""
OPENCLAW_ACTION=""

declare -a SUMMARY_ADDED=()
declare -a SUMMARY_CHANGED=()
declare -a SUMMARY_FAILED=()

# Color theme (auto-disables when not a TTY or NO_COLOR is set)
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_TITLE=$'\033[1;36m'
  C_APP=$'\033[1;35m'
  C_SECTION=$'\033[1;34m'
  C_INFO=$'\033[0;36m'
  C_WARN=$'\033[1;33m'
  C_ERR=$'\033[1;31m'
  C_OK=$'\033[1;32m'
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_TITLE=""
  C_APP=""
  C_SECTION=""
  C_INFO=""
  C_WARN=""
  C_ERR=""
  C_OK=""
fi

print_header() {
  clear || true
  echo "${C_TITLE}============================================================${C_RESET}"
  echo "  ${C_APP}$APP_NAME${C_RESET} ${C_DIM}v$APP_VERSION${C_RESET}"
  echo "${C_TITLE}============================================================${C_RESET}"
  echo
}

log() {
  echo
  echo "${C_SECTION}---- $1${C_RESET}"
}

warn() {
  echo
  echo "${C_WARN}WARNING:${C_RESET} $1"
}

record_added() {
  SUMMARY_ADDED+=("$1")
}

record_changed() {
  SUMMARY_CHANGED+=("$1")
}

record_failed() {
  SUMMARY_FAILED+=("$1")
}

print_execution_summary() {
  local item
  echo
  echo "${C_TITLE}============================================================${C_RESET}"
  echo "${C_BOLD}Execution summary${C_RESET}"
  echo "${C_TITLE}============================================================${C_RESET}"

  echo
  echo "${C_OK}${C_BOLD}Added:${C_RESET}"
  if [ "${#SUMMARY_ADDED[@]}" -eq 0 ]; then
    echo "  ${C_DIM}- None${C_RESET}"
  else
    for item in "${SUMMARY_ADDED[@]}"; do
      echo "  - $item"
    done
  fi

  echo
  echo "${C_INFO}${C_BOLD}Changed:${C_RESET}"
  if [ "${#SUMMARY_CHANGED[@]}" -eq 0 ]; then
    echo "  ${C_DIM}- None${C_RESET}"
  else
    for item in "${SUMMARY_CHANGED[@]}"; do
      echo "  - $item"
    done
  fi

  echo
  echo "${C_WARN}${C_BOLD}Failed (non-fatal):${C_RESET}"
  if [ "${#SUMMARY_FAILED[@]}" -eq 0 ]; then
    echo "  ${C_DIM}- None${C_RESET}"
  else
    for item in "${SUMMARY_FAILED[@]}"; do
      echo "  - $item"
    done
  fi
  echo
}

print_potential_issues() {
  echo
  echo "${C_TITLE}============================================================${C_RESET}"
  echo "${C_BOLD}Potential issues to keep in mind${C_RESET}"
  echo "${C_TITLE}============================================================${C_RESET}"
  echo
  if [ "$INSTALL_SECURITY" = "1" ]; then
    echo "  - UFW sets incoming traffic to deny by default."
    echo "    This can affect remote SSH and local network access to apps/services."
  else
    echo "  - Security hardening is disabled in desktop-safe mode."
    echo "    Re-run with --hardened if you want UFW/fail2ban enabled."
  fi
  echo "  - Docker non-sudo usage requires a logout/login after docker group changes."
  echo "  - Desktop shortcut and dashboard open are best-effort by desktop environment support."
  echo "  - OpenClaw desktop launcher uses user Docker permissions after install."
  echo "  - Apt may report deferred phased updates; this is normal on Ubuntu."
  echo "  - This script does not install AI models."
  echo
}

die() {
  echo
  echo "${C_ERR}${C_BOLD}ERROR:${C_RESET} $1"
  exit 1
}

pause() {
  echo
  read -r -p "Press Enter to continue..."
}

on_error() {
  local exit_code="$1"
  local line_no="$2"
  record_failed "Script aborted at line $line_no (exit code $exit_code)"
  echo
  echo "${C_ERR}${C_BOLD}ERROR:${C_RESET} Script failed at line $line_no with exit code $exit_code"
  echo "${C_INFO}Check log file:${C_RESET} $LOG_FILE"
  print_execution_summary
  exit "$exit_code"
}

cleanup() {
  if [ -n "${SUDO_KEEPALIVE_PID:-}" ] && kill -0 "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1; then
    kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
  fi
}

trap 'on_error $? $LINENO' ERR
trap cleanup EXIT

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_cmd() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

run_apt() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] sudo apt-get $*"
    return 0
  fi
  if [ "$NONINTERACTIVE_MODE" = "1" ] || [ "$YES_MODE" = "1" ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get "$@"
  else
    sudo apt-get "$@"
  fi
}

setup_logging() {
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
}

require_sudo() {
  if [ "$DRY_RUN" = "1" ]; then
    log "Sudo access required (dry-run skipped)"
    return 0
  fi

  if ! sudo -n true 2>/dev/null; then
    log "Sudo access required"
    sudo true
  fi
}

start_sudo_keepalive() {
  if [ "$DRY_RUN" = "1" ]; then
    return 0
  fi

  (
    while true; do
      sudo -n true >/dev/null 2>&1 || exit 0
      sleep 50
    done
  ) &
  SUDO_KEEPALIVE_PID="$!"
}

is_ubuntu() {
  if [ ! -f /etc/os-release ]; then
    return 1
  fi
  . /etc/os-release
  [ "${ID:-}" = "ubuntu" ]
}

get_codename() {
  . /etc/os-release
  echo "${VERSION_CODENAME:-}"
}

system_update() {
  log "Updating system packages"
  run_apt update
  run_apt upgrade -y
  run_apt autoremove -y
}

install_base_packages() {
  log "Installing base packages"
  run_apt install -y \
    ca-certificates \
    curl \
    wget \
    git \
    unzip \
    zip \
    jq \
    build-essential \
    software-properties-common \
    apt-transport-https \
    gnupg \
    lsb-release \
    bash-completion \
    tmux \
    htop \
    btop \
    tree \
    nano \
    vim \
    less \
    rsync \
    net-tools \
    dnsutils \
    ufw \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    pipx
}

install_security_tools() {
  log "Installing security tools"
  run_apt install -y fail2ban unattended-upgrades

  log "Configuring unattended upgrades"
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] sudo dpkg-reconfigure -f noninteractive unattended-upgrades"
  else
    sudo dpkg-reconfigure -f noninteractive unattended-upgrades || true
  fi

  log "Configuring UFW firewall"
  run_cmd sudo ufw default deny incoming
  run_cmd sudo ufw default allow outgoing

  if command_exists ssh && systemctl list-unit-files | grep -q '^ssh\.service'; then
    run_cmd sudo ufw allow OpenSSH
  fi

  run_cmd sudo ufw --force enable

  local ssh_active=0
  if command_exists systemctl; then
    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
      ssh_active=1
    fi
  fi

  if [ "$ssh_active" = "1" ]; then
    log "Enabling fail2ban (SSH is active)"
    run_cmd sudo systemctl enable fail2ban
    run_cmd sudo systemctl restart fail2ban
  else
    warn "SSH service is not active; fail2ban will remain installed but disabled"
    if [ "$DRY_RUN" = "1" ]; then
      echo "[dry-run] sudo systemctl disable --now fail2ban"
    else
      sudo systemctl disable --now fail2ban >/dev/null 2>&1 || true
    fi
  fi
}

install_dev_tools() {
  log "Installing common dev tools"
  export PATH="$HOME/.local/bin:$PATH"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] ensure pipx is installed"
    echo "[dry-run] pipx ensurepath"
    echo "[dry-run] pipx install poetry"
    echo "[dry-run] pipx install ruff"
    echo "[dry-run] pipx install black"
    return 0
  fi

  # Ubuntu 24.04+ enforces PEP 668 for system Python. Avoid pip --user upgrades here.
  if ! command_exists pipx; then
    warn "pipx not found; attempting apt install"
    run_apt install -y pipx python3-venv
  fi

  if ! command_exists pipx; then
    warn "pipx is unavailable; skipping poetry/ruff/black installs"
    record_failed "pipx unavailable; skipped poetry/ruff/black"
    return 0
  fi

  pipx ensurepath || true

  if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
  fi

  pipx install poetry || pipx upgrade poetry || { warn "poetry install failed; continuing"; record_failed "poetry install/upgrade failed"; }
  pipx install ruff || pipx upgrade ruff || { warn "ruff install failed; continuing"; record_failed "ruff install/upgrade failed"; }
  pipx install black || pipx upgrade black || { warn "black install failed; continuing"; record_failed "black install/upgrade failed"; }
}

install_docker() {
  log "Installing Docker"

  run_apt remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true
  run_cmd sudo install -m 0755 -d /etc/apt/keyrings

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] add Docker apt key and repo"
  else
    if [ ! -f /etc/apt/keyrings/docker.asc ]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
      sudo chmod a+r /etc/apt/keyrings/docker.asc
    fi
  fi

  local arch codename
  arch="$(dpkg --print-architecture)"
  codename="$(get_codename)"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] write docker apt source for ${arch}/${codename}"
  else
    echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  fi

  run_apt update
  run_apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] ensure docker group + user membership"
  else
    if ! getent group docker >/dev/null 2>&1; then
      sudo groupadd docker
    fi

    if ! id -nG "$USER" | grep -qw docker; then
      sudo usermod -aG docker "$USER"
      docker_group_added=1
      show_reboot_notice=1
    fi
  fi

  run_cmd sudo systemctl enable docker
  run_cmd sudo systemctl start docker
}

install_node() {
  log "Installing Node.js ${NODE_MAJOR}.x"

  run_cmd sudo install -m 0755 -d /etc/apt/keyrings

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] add NodeSource apt key and repo"
  else
    if [ ! -f /etc/apt/keyrings/nodesource.gpg ]; then
      curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
      sudo chmod a+r /etc/apt/keyrings/nodesource.gpg
    fi

    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
      | sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null
  fi

  run_apt update
  run_apt install -y nodejs
}

install_gh() {
  log "Installing GitHub CLI"
  run_apt install -y gh
}

create_workspace() {
  log "Creating workspace structure"
  run_cmd mkdir -p "$AI_ROOT"
  run_cmd mkdir -p "$AI_ROOT/projects"
  run_cmd mkdir -p "$AI_ROOT/tools"
  run_cmd mkdir -p "$AI_ROOT/tmp"
}

install_openclaw_repo() {
  log "Installing OpenClaw repository"
  run_cmd mkdir -p "$(dirname "$OPENCLAW_DIR")"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] clone or update $OPENCLAW_REPO into $OPENCLAW_DIR"
    OPENCLAW_ACTION="changed"
    return 0
  fi

  if [ ! -d "$OPENCLAW_DIR/.git" ]; then
    git clone "$OPENCLAW_REPO" "$OPENCLAW_DIR"
    OPENCLAW_ACTION="added"
  else
    git -C "$OPENCLAW_DIR" pull --ff-only
    OPENCLAW_ACTION="changed"
  fi
}

configure_openclaw_files() {
  log "Creating OpenClaw helper files"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime/data"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime/logs"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime/config"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime/workspace"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] write OpenClaw helper files"
    return 0
  fi

  # Docker Compose requires these vars; empty values cause "invalid spec" volume errors
  local config_dir="$OPENCLAW_DIR/runtime/config"
  local workspace_dir="$OPENCLAW_DIR/runtime/workspace"
  local gateway_token
  gateway_token="$(openssl rand -hex 16 2>/dev/null || echo "local-$(date +%s)")"
  if [ ! -f "$OPENCLAW_DIR/.env" ]; then
    cat > "$OPENCLAW_DIR/.env" <<ENVEOF
# OpenClaw Docker Compose env (created by EasyMode installer)
OPENCLAW_CONFIG_DIR=$config_dir
OPENCLAW_WORKSPACE_DIR=$workspace_dir
OPENCLAW_GATEWAY_TOKEN=$gateway_token
ENVEOF
  fi

  # OpenClaw's npm scripts use pnpm for TypeScript build
  if command -v corepack >/dev/null 2>&1; then
    corepack enable 2>/dev/null || true
    corepack prepare pnpm@latest --activate 2>/dev/null || true
  elif command -v npm >/dev/null 2>&1; then
    npm install -g pnpm 2>/dev/null || true
  fi

  cat > "$OPENCLAW_DIR/runtime/README_LOCAL_SETUP.txt" <<'EOF'
OpenClaw local prep completed.

This script does NOT install models.
It will attempt to start OpenClaw and open the dashboard URL after setup.

Recommended next steps:
1. Read the official docs in the OpenClaw repo.
2. Prefer Docker-based or sandboxed runs.
3. Review any marketplace skills or third-party tools before enabling them.
4. Do not connect personal accounts until you fully trust the environment.
5. Keep OpenClaw updated due to recent security fixes.

Useful checks:
- node -v
- npm -v
- docker --version
- docker compose version
EOF

  cat > "$OPENCLAW_DIR/runtime/config/openclaw.env.example" <<'EOF'
# Example local environment file for OpenClaw
# Copy this to .env only after reviewing the project docs.

NODE_ENV=production
OPENCLAW_DATA_DIR=./runtime/data
OPENCLAW_LOG_DIR=./runtime/logs

# Add provider/API settings manually after review.
# Do not paste secrets into random files without understanding how the app uses them.
EOF

  cat > "$OPENCLAW_DIR/runtime/openclaw-safe-start.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

echo "Review docs first, then run the startup method you choose."
echo
echo "Examples:"
echo "  - Docker flow from docs"
echo "  - Installer/wizard flow from docs"
echo "  - Auto launcher: ./runtime/openclaw-launch.sh"
echo
echo "Repo location:"
pwd
EOF

  chmod +x "$OPENCLAW_DIR/runtime/openclaw-safe-start.sh"
}

create_openclaw_launcher() {
  log "Creating OpenClaw launcher"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime/logs"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] write $OPENCLAW_DIR/runtime/openclaw-launch.sh"
    return 0
  fi

  cat > "$OPENCLAW_DIR/runtime/openclaw-launch.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

OPENCLAW_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
DASHBOARD_URL="\${OPENCLAW_DASHBOARD_URL:-$OPENCLAW_DASHBOARD_URL}"
LOG_FILE="\$OPENCLAW_DIR/runtime/logs/openclaw-launch.log"
mkdir -p "\$(dirname "\$LOG_FILE")"

echo "OpenClaw launcher"
echo "Repo: \$OPENCLAW_DIR"
echo "Dashboard URL: \$DASHBOARD_URL"
echo

compose_file=""
for candidate in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
  if [ -f "\$OPENCLAW_DIR/\$candidate" ]; then
    compose_file="\$candidate"
    break
  fi
done

# Ensure .env exists for Docker Compose (avoids "invalid spec" volume errors)
if [ -n "\$compose_file" ] && [ ! -f "\$OPENCLAW_DIR/.env" ]; then
  cfg="\$OPENCLAW_DIR/runtime/config"
  ws="\$OPENCLAW_DIR/runtime/workspace"
  mkdir -p "\$cfg" "\$ws"
  tok="\$(openssl rand -hex 16 2>/dev/null || echo "local-\$(date +%s)")"
  echo "OPENCLAW_CONFIG_DIR=\$cfg" > "\$OPENCLAW_DIR/.env"
  echo "OPENCLAW_WORKSPACE_DIR=\$ws" >> "\$OPENCLAW_DIR/.env"
  echo "OPENCLAW_GATEWAY_TOKEN=\$tok" >> "\$OPENCLAW_DIR/.env"
fi

started=0

if command -v docker >/dev/null 2>&1 && [ -n "\$compose_file" ]; then
  echo "Trying Docker startup with \$compose_file..."
  if (cd "\$OPENCLAW_DIR" && docker compose up -d) >>"\$LOG_FILE" 2>&1; then
    started=1
  elif [ "\${OPENCLAW_FORCE_SUDO_DOCKER:-0}" = "1" ] && command -v sudo >/dev/null 2>&1; then
    (cd "\$OPENCLAW_DIR" && sudo docker compose up -d) >>"\$LOG_FILE" 2>&1 && started=1
  fi
fi

if [ "\$started" -eq 0 ] && [ -f "\$OPENCLAW_DIR/package.json" ] && command -v npm >/dev/null 2>&1; then
  echo "Trying npm startup..."
  if ! command -v pnpm >/dev/null 2>&1; then
    if command -v corepack >/dev/null 2>&1; then
      corepack enable 2>/dev/null || true
      corepack prepare pnpm@latest --activate 2>/dev/null || true
    else
      npm install -g pnpm >>"\$LOG_FILE" 2>&1 || true
    fi
  fi
  if [ ! -d "\$OPENCLAW_DIR/node_modules" ]; then
    if command -v pnpm >/dev/null 2>&1; then
      (cd "\$OPENCLAW_DIR" && pnpm install) >>"\$LOG_FILE" 2>&1 || true
    else
      (cd "\$OPENCLAW_DIR" && npm install) >>"\$LOG_FILE" 2>&1 || true
    fi
  fi

  if command -v jq >/dev/null 2>&1 && jq -e '.scripts.start' "\$OPENCLAW_DIR/package.json" >/dev/null 2>&1; then
    nohup bash -lc "cd \"\$OPENCLAW_DIR\" && npm run start" >>"\$LOG_FILE" 2>&1 &
    started=1
  elif command -v jq >/dev/null 2>&1 && jq -e '.scripts.dev' "\$OPENCLAW_DIR/package.json" >/dev/null 2>&1; then
    nohup bash -lc "cd \"\$OPENCLAW_DIR\" && npm run dev" >>"\$LOG_FILE" 2>&1 &
    started=1
  fi
fi

port_ready() {
  if command -v ss >/dev/null 2>&1; then
    ss -tlnp 2>/dev/null | grep -qE ":\$PORT([^0-9]|\$)" && return 0
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -tlnp 2>/dev/null | grep -qE ":\$PORT([^0-9]|\$)" && return 0
  fi
  return 1
}

PORT=3000
[[ "\$DASHBOARD_URL" =~ :([0-9]+) ]] && PORT="\${BASH_REMATCH[1]}"

if [ "\$started" -eq 1 ] && command -v xdg-open >/dev/null 2>&1; then
  echo "Waiting for OpenClaw to be ready (up to 90s)..."
  for i in \$(seq 1 90); do
    if port_ready; then
      echo "Ready."
      xdg-open "\$DASHBOARD_URL" >/dev/null 2>&1 || true
      break
    fi
    sleep 1
    if [ \$((i % 10)) -eq 0 ]; then
      echo "  ... still waiting (\$i s)"
    fi
  done
  if ! port_ready; then
    echo "Timed out. OpenClaw may still be starting. Opening browser anyway."
    xdg-open "\$DASHBOARD_URL" >/dev/null 2>&1 || true
  fi
fi

if [ "\$started" -eq 1 ]; then
  echo "OpenClaw start command submitted."
  echo "Logs: \$LOG_FILE"
  exit 0
fi

echo "Could not determine a startup command automatically."
echo "Check repo docs and run preferred startup manually."
exit 1
EOF

  chmod +x "$OPENCLAW_DIR/runtime/openclaw-launch.sh"
}

create_openclaw_status_script() {
  log "Creating OpenClaw status script"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] write $OPENCLAW_DIR/runtime/openclaw-status.sh"
    return 0
  fi

  cat > "$OPENCLAW_DIR/runtime/openclaw-status.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

OPENCLAW_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
DASHBOARD_URL="\${OPENCLAW_DASHBOARD_URL:-$OPENCLAW_DASHBOARD_URL}"
PORT=3000
if [[ "\$DASHBOARD_URL" =~ :([0-9]+) ]]; then PORT="\${BASH_REMATCH[1]}"; fi

echo "OpenClaw Status"
echo "Dashboard URL: \$DASHBOARD_URL"
echo

running=0
if command -v ss >/dev/null 2>&1; then
  if ss -tlnp 2>/dev/null | grep -qE ":\$PORT([^0-9]|\$)"; then
    running=1
  fi
fi
if [ "\$running" -eq 0 ] && command -v netstat >/dev/null 2>&1; then
  if netstat -tlnp 2>/dev/null | grep -qE ":\$PORT([^0-9]|\$)"; then
    running=1
  fi
fi

if [ "\$running" -eq 1 ]; then
  echo "Status: Running"
  echo "Open dashboard: \$DASHBOARD_URL"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "\$DASHBOARD_URL" 2>/dev/null &
  fi
else
  echo "Status: Not running"
  echo "Run the OpenClaw launcher to start: \$OPENCLAW_DIR/runtime/openclaw-launch.sh"
fi
echo
EOF

  chmod +x "$OPENCLAW_DIR/runtime/openclaw-status.sh"
}

create_openclaw_autostart_service() {
  if [ "$OPENCLAW_AUTOSTART" != "1" ]; then
    return 0
  fi

  log "Creating OpenClaw autostart service"
  run_cmd mkdir -p "$HOME/.config/systemd/user"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] write systemd user service for OpenClaw autostart"
    return 0
  fi

  cat > "$HOME/.config/systemd/user/openclaw.service" <<EOF
[Unit]
Description=OpenClaw
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$OPENCLAW_DIR/runtime/openclaw-launch.sh
RemainAfterExit=yes
Environment="OPENCLAW_DASHBOARD_URL=$OPENCLAW_DASHBOARD_URL"

[Install]
WantedBy=default.target
EOF

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload
    systemctl --user enable openclaw.service
    record_changed "OpenClaw autostart enabled (starts when you log in)"
  else
    warn "systemctl not found; skipping autostart enable"
  fi
}

create_openclaw_icon() {
  log "Creating OpenClaw icon asset"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime/assets"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] write $OPENCLAW_DIR/runtime/assets/openclaw-icon.svg"
    return 0
  fi

  cat > "$OPENCLAW_DIR/runtime/assets/openclaw-icon.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0f172a"/>
      <stop offset="100%" stop-color="#1e293b"/>
    </linearGradient>
    <linearGradient id="accent" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#22d3ee"/>
      <stop offset="100%" stop-color="#6366f1"/>
    </linearGradient>
  </defs>
  <rect x="8" y="8" width="240" height="240" rx="44" fill="url(#bg)"/>
  <g fill="url(#accent)">
    <ellipse cx="128" cy="155" rx="42" ry="38"/>
    <ellipse cx="80" cy="95" rx="18" ry="22" transform="rotate(-35 80 95)"/>
    <ellipse cx="176" cy="95" rx="18" ry="22" transform="rotate(35 176 95)"/>
    <ellipse cx="58" cy="125" rx="14" ry="18" transform="rotate(-50 58 125)"/>
    <ellipse cx="198" cy="125" rx="14" ry="18" transform="rotate(50 198 125)"/>
  </g>
</svg>
EOF
}

install_openclaw_shortcuts() {
  log "Creating OpenClaw desktop shortcuts"

  if [ "$CREATE_OPENCLAW_SHORTCUT" != "1" ]; then
    return 0
  fi

  if [ -z "${XDG_CURRENT_DESKTOP:-}" ] && [ -z "${DESKTOP_SESSION:-}" ]; then
    warn "No desktop session detected; skipping OpenClaw desktop shortcuts"
    record_failed "Skipped OpenClaw shortcut creation (no desktop session)"
    return 0
  fi

  local desktop_file="$HOME/Desktop/OpenClaw.desktop"
  local app_file="$HOME/.local/share/applications/openclaw.desktop"
  local icon_path="$OPENCLAW_DIR/runtime/assets/openclaw-icon.svg"
  local icon_value="utilities-terminal"

  if [ -f "$icon_path" ]; then
    icon_value="$icon_path"
  fi

  run_cmd mkdir -p "$HOME/Desktop"
  run_cmd mkdir -p "$HOME/.local/share/applications"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] write OpenClaw desktop files"
    return 0
  fi

  cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=OpenClaw
Comment=Start OpenClaw and open dashboard
Exec=bash -c '$OPENCLAW_DIR/runtime/openclaw-launch.sh; echo; read -p \"Press Enter to close...\"'
Icon=$icon_value
Terminal=true
Categories=Development;
EOF

  cp "$desktop_file" "$app_file"
  chmod +x "$desktop_file" "$app_file"

  if command_exists gio; then
    gio set "$desktop_file" metadata::trusted true >/dev/null 2>&1 || true
  fi

  local dashboard_file="$HOME/Desktop/OpenClaw Dashboard.desktop"
  local dashboard_app="$HOME/.local/share/applications/openclaw-dashboard.desktop"
  cat > "$dashboard_file" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=OpenClaw Dashboard
Comment=Check OpenClaw status and open dashboard
Exec=bash -c '$OPENCLAW_DIR/runtime/openclaw-status.sh; read -p \"Press Enter to close...\"'
Icon=$icon_value
Terminal=true
Categories=Development;
EOF
  cp "$dashboard_file" "$dashboard_app"
  chmod +x "$dashboard_file" "$dashboard_app"
  if command_exists gio; then
    gio set "$dashboard_file" metadata::trusted true >/dev/null 2>&1 || true
  fi
}

launch_openclaw_after_install() {
  if [ "$AUTO_LAUNCH_OPENCLAW" != "1" ]; then
    return 0
  fi

  log "Launching OpenClaw and opening dashboard"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] $OPENCLAW_DIR/runtime/openclaw-launch.sh"
    return 0
  fi

  if [ ! -x "$OPENCLAW_DIR/runtime/openclaw-launch.sh" ]; then
    warn "OpenClaw launcher is missing; skipping auto-launch"
    record_failed "OpenClaw auto-launch skipped (launcher missing)"
    return 0
  fi

  if OPENCLAW_FORCE_SUDO_DOCKER=1 "$OPENCLAW_DIR/runtime/openclaw-launch.sh"; then
    record_changed "OpenClaw launch command started and dashboard open attempted"
  else
    warn "OpenClaw auto-launch could not determine startup command"
    record_failed "OpenClaw auto-launch did not find a supported startup method"
  fi
}

detect_terminal_desktop_id() {
  local id
  for id in org.gnome.Terminal.desktop org.gnome.Console.desktop kgx.desktop xfce4-terminal.desktop konsole.desktop; do
    if [ -f "/usr/share/applications/$id" ] || [ -f "$HOME/.local/share/applications/$id" ]; then
      echo "$id"
      return 0
    fi
  done
  return 1
}

add_terminal_desktop_shortcut() {
  local app_id="$1"
  local src=""
  local dst="$HOME/Desktop/Terminal.desktop"

  if [ -f "/usr/share/applications/$app_id" ]; then
    src="/usr/share/applications/$app_id"
  elif [ -f "$HOME/.local/share/applications/$app_id" ]; then
    src="$HOME/.local/share/applications/$app_id"
  else
    return 1
  fi

  run_cmd mkdir -p "$HOME/Desktop"
  run_cmd cp "$src" "$dst"
  run_cmd chmod +x "$dst"

  if command_exists gio; then
    run_cmd gio set "$dst" metadata::trusted true || true
  fi
}

pin_terminal_to_gnome_dock() {
  local app_id="$1"

  if ! command_exists gsettings; then
    return 0
  fi
  if [ "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ] && [ "${DESKTOP_SESSION:-}" != "ubuntu" ]; then
    return 0
  fi
  if ! gsettings writable org.gnome.shell favorite-apps >/dev/null 2>&1; then
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] add ${app_id} to GNOME favorites"
    return 0
  fi

  local updated
  updated="$(python3 - "$app_id" <<'PY'
import ast
import subprocess
import sys

app = sys.argv[1]
cur = subprocess.check_output(
    ["gsettings", "get", "org.gnome.shell", "favorite-apps"], text=True
).strip()
apps = ast.literal_eval(cur)
if app not in apps:
    apps.append(app)
print(str(apps))
PY
)"
  gsettings set org.gnome.shell favorite-apps "$updated" || true
}

install_terminal_shortcuts() {
  log "Configuring terminal shortcut and dock pin"

  if [ -z "${XDG_CURRENT_DESKTOP:-}" ] && [ -z "${DESKTOP_SESSION:-}" ]; then
    warn "No desktop session detected; skipping shortcut setup"
    return 0
  fi

  local terminal_id
  if terminal_id="$(detect_terminal_desktop_id)"; then
    add_terminal_desktop_shortcut "$terminal_id" || warn "Could not create desktop terminal shortcut"
    pin_terminal_to_gnome_dock "$terminal_id" || warn "Could not pin terminal to dock"
  else
    warn "No known terminal launcher found"
  fi
}

write_summary() {
  log "Writing summary"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] write summary to $AI_ROOT/BOOTSTRAP_SUMMARY.txt"
    return 0
  fi

  cat > "$AI_ROOT/BOOTSTRAP_SUMMARY.txt" <<EOF
$APP_NAME completed.

Installed components:
  Base packages:        $INSTALL_BASE
  Security tools:       $INSTALL_SECURITY
  Dev tools:            $INSTALL_DEV_TOOLS
  Docker:               $INSTALL_DOCKER
  Node.js:              $INSTALL_NODE
  GitHub CLI:           $INSTALL_GH
  Terminal shortcuts:   $INSTALL_SHORTCUTS
  OpenClaw repo:        $INSTALL_OPENCLAW
  OpenClaw prep files:  $CONFIGURE_OPENCLAW
  OpenClaw shortcut:    $CREATE_OPENCLAW_SHORTCUT
  OpenClaw auto-launch: $AUTO_LAUNCH_OPENCLAW

Modes:
  Noninteractive:       $NONINTERACTIVE_MODE
  Yes mode:             $YES_MODE
  Dry-run:              $DRY_RUN
  Skip update:          $SKIP_UPDATE

Workspace:
  $AI_ROOT

OpenClaw repo:
  $OPENCLAW_DIR

Checks:
  python3 --version
  docker --version
  docker compose version
  node -v
  npm -v
  gh --version

Docker test:
  docker run hello-world

Notes:
  - No AI models were installed.
  - No NVIDIA tooling was installed.
  - OpenClaw auto-launch is best-effort and depends on detected startup methods.
  - Review official OpenClaw docs before enabling skills, secrets, or external integrations.
EOF
}

run_verification_checks() {
  log "Verification checks"

  local ok=0
  local fail=0

  check_cmd() {
    local label="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
      echo "${C_OK}[OK]${C_RESET}   $label"
      ok=$((ok + 1))
    else
      echo "${C_ERR}[FAIL]${C_RESET} $label"
      fail=$((fail + 1))
    fi
  }

  check_cmd "python3 available" "command -v python3"
  check_cmd "node available" "command -v node"
  check_cmd "npm available" "command -v npm"
  check_cmd "docker available" "command -v docker"
  check_cmd "gh available" "command -v gh"

  echo
  echo "${C_BOLD}Verification result:${C_RESET} ${C_OK}${ok} passed${C_RESET}, ${C_ERR}${fail} failed${C_RESET}"
}

show_status() {
  print_header
  echo "${C_BOLD}Current selection:${C_RESET}"
  echo
  echo "  1. Base Ubuntu housekeeping      : $INSTALL_BASE"
  echo "  2. Security tools                : $INSTALL_SECURITY"
  echo "  3. Common dev tools              : $INSTALL_DEV_TOOLS"
  echo "  4. Docker                        : $INSTALL_DOCKER"
  echo "  5. Node.js                       : $INSTALL_NODE"
  echo "  6. GitHub CLI                    : $INSTALL_GH"
  echo "  7. Terminal desktop shortcuts    : $INSTALL_SHORTCUTS"
  echo "  8. Clone OpenClaw repo           : $INSTALL_OPENCLAW"
  echo "  9. Configure OpenClaw helper env : $CONFIGURE_OPENCLAW"
  echo
}

toggle_option() {
  local var_name="$1"
  local current_value="${!var_name}"
  if [ "$current_value" = "1" ]; then
    printf -v "$var_name" '%s' "0"
  else
    printf -v "$var_name" '%s' "1"
  fi
}

set_defaults() {
  INSTALL_BASE=1
  INSTALL_SECURITY=0
  INSTALL_DEV_TOOLS=1
  INSTALL_DOCKER=1
  INSTALL_NODE=1
  INSTALL_GH=1
  INSTALL_SHORTCUTS=1
  INSTALL_OPENCLAW=0
  CONFIGURE_OPENCLAW=0
}

set_power_user_defaults() {
  set_hardened_openclaw_defaults
}

set_hardened_defaults() {
  INSTALL_BASE=1
  INSTALL_SECURITY=1
  INSTALL_DEV_TOOLS=1
  INSTALL_DOCKER=1
  INSTALL_NODE=1
  INSTALL_GH=1
  INSTALL_SHORTCUTS=1
  INSTALL_OPENCLAW=0
  CONFIGURE_OPENCLAW=0
}

set_hardened_openclaw_defaults() {
  INSTALL_BASE=1
  INSTALL_SECURITY=1
  INSTALL_DEV_TOOLS=1
  INSTALL_DOCKER=1
  INSTALL_NODE=1
  INSTALL_GH=1
  INSTALL_SHORTCUTS=1
  INSTALL_OPENCLAW=1
  CONFIGURE_OPENCLAW=1
}

confirm_cleanup() {
  if [ "$YES_MODE" = "1" ] || [ "$DRY_RUN" = "1" ]; then
    return 0
  fi

  if [ "$NONINTERACTIVE_MODE" = "1" ]; then
    die "--cleanup in noninteractive mode requires --yes"
  fi

  echo
  echo "${C_WARN}${C_BOLD}Cleanup confirmation${C_RESET}"
  echo "This will remove EasyMode-managed components and OpenClaw local files."
  echo "Type ${C_BOLD}REMOVE${C_RESET} to continue:"
  local confirm
  read -r confirm
  if [ "$confirm" != "REMOVE" ]; then
    die "Cleanup cancelled by user"
  fi
}

run_cleanup() {
  confirm_cleanup
  require_sudo
  start_sudo_keepalive

  log "Running cleanup/remove flow"
  record_changed "Cleanup flow started"

  log "Stopping related services"
  run_cmd sudo systemctl disable --now docker >/dev/null 2>&1 || true
  run_cmd sudo systemctl disable --now fail2ban >/dev/null 2>&1 || true
  record_changed "Docker/fail2ban services stopped or disabled"

  log "Removing apt-managed components"
  run_apt remove -y \
    gh \
    nodejs \
    fail2ban \
    unattended-upgrades \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    docker-ce-rootless-extras \
    libslirp0 \
    slirp4netns \
    pigz || true
  run_apt autoremove -y || true
  record_changed "Apt cleanup attempted for EasyMode-installed packages"

  log "Removing apt source files and keys"
  run_cmd sudo rm -f /etc/apt/sources.list.d/docker.list
  run_cmd sudo rm -f /etc/apt/sources.list.d/nodesource.list
  run_cmd sudo rm -f /etc/apt/keyrings/docker.asc
  run_cmd sudo rm -f /etc/apt/keyrings/nodesource.gpg
  record_changed "Docker/NodeSource apt source files removed"

  log "Removing Python CLI tools installed via pipx"
  if command_exists pipx; then
    run_cmd pipx uninstall poetry || true
    run_cmd pipx uninstall ruff || true
    run_cmd pipx uninstall black || true
    record_changed "pipx tools removal attempted (poetry/ruff/black)"
  fi

  log "Removing OpenClaw repo and generated files"
  if [ -d "$OPENCLAW_DIR" ]; then
    run_cmd rm -rf "$OPENCLAW_DIR"
    record_changed "Removed OpenClaw directory at $OPENCLAW_DIR"
  fi

  log "Removing desktop shortcuts"
  run_cmd rm -f "$HOME/Desktop/OpenClaw.desktop"
  run_cmd rm -f "$HOME/Desktop/OpenClaw Dashboard.desktop"
  run_cmd rm -f "$HOME/.local/share/applications/openclaw.desktop"
  run_cmd rm -f "$HOME/.local/share/applications/openclaw-dashboard.desktop"
  record_changed "Removed OpenClaw desktop shortcuts"

  log "Removing OpenClaw autostart service"
  if [ -f "$HOME/.config/systemd/user/openclaw.service" ]; then
    run_cmd systemctl --user disable openclaw.service 2>/dev/null || true
    run_cmd rm -f "$HOME/.config/systemd/user/openclaw.service"
    run_cmd systemctl --user daemon-reload 2>/dev/null || true
    record_changed "Removed OpenClaw autostart service"
  fi

  log "Removing EasyMode output files"
  run_cmd rm -f "$AI_ROOT/BOOTSTRAP_SUMMARY.txt"
  run_cmd rm -f "$LOG_FILE"
  record_changed "Removed EasyMode summary/log files"

  if [ "$DRY_RUN" = "0" ]; then
    run_cmd sudo apt-get update || true
  fi

  echo
  echo "${C_TITLE}============================================================${C_RESET}"
  echo "${C_OK}${C_BOLD}Cleanup complete${C_RESET}"
  echo "${C_TITLE}============================================================${C_RESET}"
  print_execution_summary
}

run_install() {
  local had_node=0
  local had_docker=0
  local had_gh=0
  local had_openclaw=0

  if command_exists node; then
    had_node=1
  fi
  if command_exists docker; then
    had_docker=1
  fi
  if command_exists gh; then
    had_gh=1
  fi
  if [ -d "$OPENCLAW_DIR/.git" ]; then
    had_openclaw=1
  fi

  require_sudo
  start_sudo_keepalive
  create_workspace
  record_changed "Workspace directories ensured at $AI_ROOT"

  if [ "$SKIP_UPDATE" = "0" ]; then
    system_update
    record_changed "System package index/upgrade processed"
  else
    log "Skipping apt update/upgrade as requested"
  fi

  if [ "$INSTALL_BASE" = "1" ]; then
    install_base_packages
    record_changed "Base package set installed/verified"
  fi
  if [ "$INSTALL_SECURITY" = "1" ]; then
    install_security_tools
    record_changed "Security tools configured (ufw, fail2ban, unattended-upgrades)"
  fi
  if [ "$INSTALL_DEV_TOOLS" = "1" ]; then
    install_dev_tools
    record_changed "Dev tools processed via pipx"
  fi
  if [ "$INSTALL_DOCKER" = "1" ]; then
    install_docker
    if [ "$had_docker" = "1" ]; then
      record_changed "Docker engine and compose verified/updated"
    else
      record_added "Docker engine and compose installed"
    fi
  fi
  if [ "$INSTALL_NODE" = "1" ]; then
    install_node
    if [ "$had_node" = "1" ]; then
      record_changed "Node.js runtime updated/verified"
    else
      record_added "Node.js runtime installed"
    fi
  fi
  if [ "$INSTALL_GH" = "1" ]; then
    install_gh
    if [ "$had_gh" = "1" ]; then
      record_changed "GitHub CLI updated/verified"
    else
      record_added "GitHub CLI installed"
    fi
  fi
  if [ "$INSTALL_SHORTCUTS" = "1" ]; then
    install_terminal_shortcuts
    record_changed "Terminal desktop shortcut and dock pin attempted"
  fi
  if [ "$INSTALL_OPENCLAW" = "1" ]; then
    install_openclaw_repo
    if [ "$OPENCLAW_ACTION" = "added" ] || [ "$had_openclaw" = "0" ]; then
      record_added "OpenClaw repository cloned to $OPENCLAW_DIR"
    else
      record_changed "OpenClaw repository refreshed at $OPENCLAW_DIR"
    fi
  fi
  if [ "$CONFIGURE_OPENCLAW" = "1" ]; then
    if [ "$INSTALL_OPENCLAW" != "1" ]; then
      install_openclaw_repo
      if [ "$OPENCLAW_ACTION" = "added" ] || [ "$had_openclaw" = "0" ]; then
        record_added "OpenClaw repository cloned to $OPENCLAW_DIR"
      else
        record_changed "OpenClaw repository refreshed at $OPENCLAW_DIR"
      fi
    fi
    configure_openclaw_files
    record_changed "OpenClaw helper runtime/config files generated"
  fi
  if [ "$INSTALL_OPENCLAW" = "1" ] || [ "$CONFIGURE_OPENCLAW" = "1" ]; then
    create_openclaw_launcher
    record_changed "OpenClaw launcher script generated"
    create_openclaw_status_script
    record_changed "OpenClaw status script generated"
    create_openclaw_icon
    record_changed "OpenClaw icon asset generated"
    if [ "$CREATE_OPENCLAW_SHORTCUT" = "1" ]; then
      install_openclaw_shortcuts
      record_changed "OpenClaw desktop shortcut files generated"
    fi
    create_openclaw_autostart_service
    launch_openclaw_after_install
  fi

  write_summary
  if [ "$DRY_RUN" = "0" ]; then
    run_verification_checks
  fi

  echo
  echo "${C_TITLE}============================================================${C_RESET}"
  echo "${C_OK}${C_BOLD}Install complete${C_RESET}"
  echo "${C_TITLE}============================================================${C_RESET}"
  echo
  echo "${C_INFO}Summary file:${C_RESET}"
  echo "  $AI_ROOT/BOOTSTRAP_SUMMARY.txt"
  echo "${C_INFO}Log file:${C_RESET}"
  echo "  $LOG_FILE"
  print_execution_summary

  if [ "$docker_group_added" = "1" ]; then
    echo
    echo "Docker group was added to your user."
    echo "Log out and back in, or reboot, before using docker without sudo."
  elif [ "$show_reboot_notice" = "1" ]; then
    echo
    echo "A reboot or re-login is recommended."
  fi

  print_potential_issues

  echo
  echo "Recommended checks:"
  echo "  python3 --version"
  echo "  docker --version"
  echo "  docker compose version"
  echo "  node -v"
  echo "  npm -v"
  echo "  gh --version"
  echo

  if [ "$INSTALL_OPENCLAW" = "1" ] || [ "$CONFIGURE_OPENCLAW" = "1" ]; then
    echo "${C_TITLE}============================================================${C_RESET}"
    echo "${C_BOLD}OpenClaw dashboard${C_RESET}"
    echo "${C_TITLE}============================================================${C_RESET}"
    echo
    echo "  ${C_INFO}Dashboard URL:${C_RESET} $OPENCLAW_DASHBOARD_URL"
    echo "  ${C_INFO}Status script:${C_RESET} $OPENCLAW_DIR/runtime/openclaw-status.sh"
    echo "  ${C_INFO}Launcher:${C_RESET}      $OPENCLAW_DIR/runtime/openclaw-launch.sh"
    if [ "$OPENCLAW_AUTOSTART" = "1" ]; then
      echo "  ${C_INFO}Autostart:${C_RESET}     Enabled at login (~/.config/systemd/user/openclaw.service)"
    fi
    echo
  fi
}

advanced_menu() {
  while true; do
    show_status
    echo "${C_BOLD}Advanced menu:${C_RESET}"
    echo
    echo "  1) Toggle base Ubuntu housekeeping"
    echo "  2) Toggle security tools"
    echo "  3) Toggle common dev tools"
    echo "  4) Toggle Docker"
    echo "  5) Toggle Node.js"
    echo "  6) Toggle GitHub CLI"
    echo "  7) Toggle terminal desktop shortcuts"
    echo "  8) Toggle clone OpenClaw repo"
    echo "  9) Toggle configure OpenClaw helper env"
    echo " 10) Reset to desktop-safe defaults"
    echo " 11) Reset to hardened defaults"
    echo " 12) Reset to hardened + OpenClaw defaults"
    echo " 13) Start install"
    echo " 14) Cleanup / remove EasyMode changes"
    echo " 15) Exit"
    echo
    read -r -p "Choose an option: " choice

    case "$choice" in
      1) toggle_option INSTALL_BASE ;;
      2) toggle_option INSTALL_SECURITY ;;
      3) toggle_option INSTALL_DEV_TOOLS ;;
      4) toggle_option INSTALL_DOCKER ;;
      5) toggle_option INSTALL_NODE ;;
      6) toggle_option INSTALL_GH ;;
      7) toggle_option INSTALL_SHORTCUTS ;;
      8) toggle_option INSTALL_OPENCLAW ;;
      9) toggle_option CONFIGURE_OPENCLAW ;;
      10) set_defaults ;;
      11) set_hardened_defaults ;;
      12) set_hardened_openclaw_defaults ;;
      13) run_install; break ;;
      14) run_cleanup; break ;;
      15) exit 0 ;;
      *) warn "Invalid option"; pause ;;
    esac
  done
}

main_menu() {
  while true; do
    print_header
    echo "${C_BOLD}Choose install mode:${C_RESET}"
    echo
    echo "  1) Default desktop-safe install"
    echo "     - Ubuntu housekeeping"
    echo "     - No firewall/fail2ban hardening by default"
    echo "     - Common dev tools"
    echo "     - Docker"
    echo "     - Node.js"
    echo "     - GitHub CLI"
    echo "     - Terminal shortcut setup"
    echo "     - No OpenClaw install"
    echo
    echo "  2) Desktop-safe + OpenClaw prep"
    echo "     - Everything above"
    echo "     - Clone OpenClaw repo"
    echo "     - Create helper config files"
    echo
    echo "  3) Hardened install (security tools on)"
    echo "  4) Advanced selection menu"
    echo "  5) Cleanup / remove EasyMode changes"
    echo "  6) Exit"
    echo
    read -r -p "Choose an option: " choice

    case "$choice" in
      1) set_defaults; run_install; break ;;
      2) set_defaults; INSTALL_OPENCLAW=1; CONFIGURE_OPENCLAW=1; run_install; break ;;
      3) set_hardened_defaults; run_install; break ;;
      4) advanced_menu; break ;;
      5) run_cleanup; break ;;
      6) exit 0 ;;
      *) warn "Invalid option"; pause ;;
    esac
  done
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --noninteractive)
        NONINTERACTIVE_MODE=1
        ;;
      --yes)
        YES_MODE=1
        NONINTERACTIVE_MODE=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --skip-update)
        SKIP_UPDATE=1
        ;;
      --default)
        NONINTERACTIVE_MODE=1
        set_defaults
        ;;
      --default-openclaw)
        NONINTERACTIVE_MODE=1
        set_defaults
        INSTALL_OPENCLAW=1
        CONFIGURE_OPENCLAW=1
        ;;
      --hardened)
        NONINTERACTIVE_MODE=1
        set_hardened_defaults
        ;;
      --hardened-openclaw)
        NONINTERACTIVE_MODE=1
        set_hardened_openclaw_defaults
        ;;
      --cleanup)
        RUN_CLEANUP=1
        NONINTERACTIVE_MODE=1
        ;;
      --no-launch-openclaw)
        AUTO_LAUNCH_OPENCLAW=0
        ;;
      --no-openclaw-shortcut)
        CREATE_OPENCLAW_SHORTCUT=0
        ;;
      --no-openclaw-autostart)
        OPENCLAW_AUTOSTART=0
        ;;
      --version)
        echo "$APP_VERSION"
        exit 0
        ;;
      --help|-h)
        cat <<EOF
Usage:
  $0
  $0 --default
  $0 --default-openclaw
  $0 --hardened
  $0 --hardened-openclaw
  $0 --cleanup --yes
  $0 --default-openclaw --no-launch-openclaw --no-openclaw-shortcut
  $0 --default --noninteractive --yes
  $0 --default --dry-run

Flags:
  --default            Run desktop-safe defaults without menu
  --default-openclaw   Run desktop-safe defaults + OpenClaw prep
  --hardened           Run hardened defaults (security tools enabled)
  --hardened-openclaw  Run hardened defaults + OpenClaw prep
  --cleanup            Remove EasyMode-installed components (requires --yes in noninteractive mode)
  --no-launch-openclaw Disable OpenClaw auto-launch at end of install
  --no-openclaw-shortcut Disable OpenClaw desktop shortcut creation
  --no-openclaw-autostart Disable OpenClaw autostart at login
  --noninteractive     Skip menu and prompts
  --yes                Alias for fully noninteractive flow
  --dry-run            Print actions without making changes
  --skip-update        Skip apt update/upgrade
  --version            Print script version
  --help, -h           Show help

Environment variables:
  AI_ROOT=/path/to/workspace
  OPENCLAW_DIR=/path/to/openclaw
  OPENCLAW_REPO=https://github.com/openclaw/openclaw.git
  OPENCLAW_DASHBOARD_URL=http://127.0.0.1:3000
  AUTO_LAUNCH_OPENCLAW=1
  CREATE_OPENCLAW_SHORTCUT=1
  OPENCLAW_AUTOSTART=1
  NODE_MAJOR=22
  LOG_FILE=/path/to/bootstrap.log
EOF
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  setup_logging

  if ! is_ubuntu; then
    die "This script is intended for Ubuntu."
  fi

  if [ "$NONINTERACTIVE_MODE" = "1" ]; then
    if [ "$RUN_CLEANUP" = "1" ]; then
      run_cleanup
    else
      run_install
    fi
  else
    main_menu
  fi
}

main "$@"
