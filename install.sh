#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Ubuntu OpenClaw EasyMode Bootstrap"
VERSION="1.1.0"

AI_ROOT="${AI_ROOT:-$HOME/ai}"
OPENCLAW_DIR="${OPENCLAW_DIR:-$AI_ROOT/openclaw}"
OPENCLAW_REPO="${OPENCLAW_REPO:-https://github.com/openclaw/openclaw.git}"
NODE_MAJOR="${NODE_MAJOR:-22}"

LOG_FILE="${LOG_FILE:-$AI_ROOT/bootstrap.log}"

INSTALL_BASE=1
INSTALL_SECURITY=1
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

show_reboot_notice=0
docker_group_added=0
SUDO_KEEPALIVE_PID=""

print_header() {
  clear || true
  echo "============================================================"
  echo "  $APP_NAME v$VERSION"
  echo "============================================================"
  echo
}

log() {
  echo
  echo "---- $1"
}

warn() {
  echo
  echo "WARNING: $1"
}

die() {
  echo
  echo "ERROR: $1"
  exit 1
}

pause() {
  echo
  read -r -p "Press Enter to continue..."
}

on_error() {
  local exit_code="$1"
  local line_no="$2"
  echo
  echo "ERROR: Script failed at line $line_no with exit code $exit_code"
  echo "Check log file: $LOG_FILE"
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
    echo "[dry-run] sudo apt $*"
    return 0
  fi
  if [ "$NONINTERACTIVE_MODE" = "1" ] || [ "$YES_MODE" = "1" ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt "$@"
  else
    sudo apt "$@"
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

  log "Enabling fail2ban"
  run_cmd sudo systemctl enable fail2ban
  run_cmd sudo systemctl restart fail2ban
}

install_dev_tools() {
  log "Installing common dev tools"
  export PATH="$HOME/.local/bin:$PATH"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] python3 -m pip install --user --upgrade pip"
    echo "[dry-run] pipx ensurepath"
    echo "[dry-run] pipx install poetry"
    echo "[dry-run] pipx install ruff"
    echo "[dry-run] pipx install black"
    return 0
  fi

  python3 -m pip install --user --upgrade pip
  pipx ensurepath || true

  pipx install poetry || warn "poetry install failed; continuing"
  pipx install ruff || warn "ruff install failed; continuing"
  pipx install black || warn "black install failed; continuing"
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
    return 0
  fi

  if [ ! -d "$OPENCLAW_DIR/.git" ]; then
    git clone "$OPENCLAW_REPO" "$OPENCLAW_DIR"
  else
    git -C "$OPENCLAW_DIR" pull --ff-only
  fi
}

configure_openclaw_files() {
  log "Creating OpenClaw helper files"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime/data"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime/logs"
  run_cmd mkdir -p "$OPENCLAW_DIR/runtime/config"

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] write OpenClaw helper files"
    return 0
  fi

  cat > "$OPENCLAW_DIR/runtime/README_LOCAL_SETUP.txt" <<'EOF'
OpenClaw local prep completed.

This script does NOT install models and does NOT auto-start OpenClaw.

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

echo "This helper intentionally does not start OpenClaw automatically."
echo "Review docs first, then run the exact official startup method you choose."
echo
echo "Examples:"
echo "  - Docker flow from docs"
echo "  - Installer/wizard flow from docs"
echo
echo "Repo location:"
pwd
EOF

  chmod +x "$OPENCLAW_DIR/runtime/openclaw-safe-start.sh"
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
  - OpenClaw was not auto-started.
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
      echo "[OK]   $label"
      ok=$((ok + 1))
    else
      echo "[FAIL] $label"
      fail=$((fail + 1))
    fi
  }

  check_cmd "python3 available" "command -v python3"
  check_cmd "node available" "command -v node"
  check_cmd "npm available" "command -v npm"
  check_cmd "docker available" "command -v docker"
  check_cmd "gh available" "command -v gh"

  echo
  echo "Verification result: ${ok} passed, ${fail} failed"
}

show_status() {
  print_header
  echo "Current selection:"
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
  INSTALL_SECURITY=1
  INSTALL_DEV_TOOLS=1
  INSTALL_DOCKER=1
  INSTALL_NODE=1
  INSTALL_GH=1
  INSTALL_SHORTCUTS=1
  INSTALL_OPENCLAW=0
  CONFIGURE_OPENCLAW=0
}

set_power_user_defaults() {
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

run_install() {
  require_sudo
  start_sudo_keepalive
  create_workspace

  if [ "$SKIP_UPDATE" = "0" ]; then
    system_update
  else
    log "Skipping apt update/upgrade as requested"
  fi

  if [ "$INSTALL_BASE" = "1" ]; then
    install_base_packages
  fi
  if [ "$INSTALL_SECURITY" = "1" ]; then
    install_security_tools
  fi
  if [ "$INSTALL_DEV_TOOLS" = "1" ]; then
    install_dev_tools
  fi
  if [ "$INSTALL_DOCKER" = "1" ]; then
    install_docker
  fi
  if [ "$INSTALL_NODE" = "1" ]; then
    install_node
  fi
  if [ "$INSTALL_GH" = "1" ]; then
    install_gh
  fi
  if [ "$INSTALL_SHORTCUTS" = "1" ]; then
    install_terminal_shortcuts
  fi
  if [ "$INSTALL_OPENCLAW" = "1" ]; then
    install_openclaw_repo
  fi
  if [ "$CONFIGURE_OPENCLAW" = "1" ]; then
    if [ "$INSTALL_OPENCLAW" != "1" ]; then
      install_openclaw_repo
    fi
    configure_openclaw_files
  fi

  write_summary
  if [ "$DRY_RUN" = "0" ]; then
    run_verification_checks
  fi

  echo
  echo "============================================================"
  echo "Install complete"
  echo "============================================================"
  echo
  echo "Summary file:"
  echo "  $AI_ROOT/BOOTSTRAP_SUMMARY.txt"
  echo "Log file:"
  echo "  $LOG_FILE"

  if [ "$docker_group_added" = "1" ]; then
    echo
    echo "Docker group was added to your user."
    echo "Log out and back in, or reboot, before using docker without sudo."
  elif [ "$show_reboot_notice" = "1" ]; then
    echo
    echo "A reboot or re-login is recommended."
  fi

  echo
  echo "Recommended checks:"
  echo "  python3 --version"
  echo "  docker --version"
  echo "  docker compose version"
  echo "  node -v"
  echo "  npm -v"
  echo "  gh --version"
  echo
}

advanced_menu() {
  while true; do
    show_status
    echo "Advanced menu:"
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
    echo " 10) Reset to safe defaults"
    echo " 11) Reset to power-user defaults"
    echo " 12) Start install"
    echo " 13) Exit"
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
      11) set_power_user_defaults ;;
      12) run_install; break ;;
      13) exit 0 ;;
      *) warn "Invalid option"; pause ;;
    esac
  done
}

main_menu() {
  while true; do
    print_header
    echo "Choose install mode:"
    echo
    echo "  1) Default safe install"
    echo "     - Ubuntu housekeeping"
    echo "     - Security tools"
    echo "     - Common dev tools"
    echo "     - Docker"
    echo "     - Node.js"
    echo "     - GitHub CLI"
    echo "     - Terminal shortcut setup"
    echo "     - No OpenClaw install"
    echo
    echo "  2) Default + OpenClaw prep"
    echo "     - Everything above"
    echo "     - Clone OpenClaw repo"
    echo "     - Create helper config files"
    echo
    echo "  3) Advanced selection menu"
    echo "  4) Exit"
    echo
    read -r -p "Choose an option: " choice

    case "$choice" in
      1) set_defaults; run_install; break ;;
      2) set_power_user_defaults; run_install; break ;;
      3) advanced_menu; break ;;
      4) exit 0 ;;
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
        set_power_user_defaults
        ;;
      --version)
        echo "$VERSION"
        exit 0
        ;;
      --help|-h)
        cat <<EOF
Usage:
  $0
  $0 --default
  $0 --default-openclaw
  $0 --default --noninteractive --yes
  $0 --default --dry-run

Flags:
  --default            Run safe defaults without menu
  --default-openclaw   Run defaults + OpenClaw prep
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
    run_install
  else
    main_menu
  fi
}

main "$@"
