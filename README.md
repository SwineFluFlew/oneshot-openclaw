# OpenClaw EasyMode Installer (Ubuntu)

One-command bootstrap installer for fresh Ubuntu systems that prepares a safe developer baseline and optional OpenClaw setup.

## Quick Start

Run the interactive menu:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/main/install.sh)
```

If `curl` is missing on a fresh image:

```bash
sudo apt update && sudo apt install -y curl
```

Or use `wget` directly (no process substitution needed):

```bash
wget -qO- https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/main/install.sh | bash
```

Run safe defaults without menu:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/main/install.sh) --default --noninteractive --yes
```

Run defaults plus OpenClaw clone + helper files:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/main/install.sh) --default-openclaw --noninteractive --yes
```

Run cleanup/remove mode (noninteractive):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/main/install.sh) --cleanup --yes
```

## Safer Alternative (Review First)

```bash
curl -fsSL https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/main/install.sh -o install.sh
less install.sh
bash install.sh
```

## What It Installs

- Base Ubuntu packages for development and troubleshooting (`htop`, `btop` — the Ubuntu `btop` package is btop++)
- Security tools (`ufw`, `fail2ban`, `unattended-upgrades`) in hardened mode
- Common dev tooling (`pipx`, `poetry`, `ruff`, `black`)
- Docker Engine + Docker Compose plugin
- Node.js via NodeSource (default major: 22)
- GitHub CLI (`gh`)
- Optional OpenClaw clone and helper runtime files
- OpenClaw launcher helper (`runtime/openclaw-launch.sh`) for start + dashboard open
- Local OpenClaw icon asset (`runtime/assets/openclaw-icon.svg`) for shortcut branding
- Optional OpenClaw desktop shortcut (`OpenClaw.desktop`)
- Optional OpenClaw Dashboard shortcut (checks status and opens dashboard)
- Optional OpenClaw autostart at login (systemd user service)
- OpenClaw onboarding wizard at end of install (configures .env, gateway, workspace)
- Optional terminal desktop shortcut and GNOME dock pin

When OpenClaw is installed, the installer also attempts to launch it and open the dashboard URL automatically. With autostart enabled, OpenClaw will start when you log in.

## Menu Modes

- **Default desktop-safe install**
  - Installs baseline tools
  - Leaves security hardening off by default
  - Does not clone OpenClaw
- **Desktop-safe + OpenClaw prep**
  - Baseline tools plus OpenClaw clone and local helper files
- **Hardened install**
  - Enables security tools (`ufw`, `fail2ban`, `unattended-upgrades`)
- **Advanced menu**
  - Toggle each install component individually
  - Includes cleanup/remove option

## CLI Flags

- `--default` Run safe defaults without menu
- `--default-openclaw` Run desktop-safe defaults + OpenClaw prep
- `--hardened` Run hardened defaults (security tools enabled)
- `--hardened-openclaw` Run hardened defaults + OpenClaw prep
- `--cleanup` Remove EasyMode-installed components (requires `--yes` in noninteractive mode)
- `--no-launch-openclaw` Disable OpenClaw auto-launch at end of install
- `--no-openclaw-shortcut` Disable OpenClaw desktop shortcut creation
- `--no-openclaw-autostart` Disable OpenClaw autostart at login
- `--no-openclaw-onboard` Skip OpenClaw onboarding wizard
- `--noninteractive` Skip menu and prompts
- `--yes` Fully noninteractive alias
- `--dry-run` Print actions only (no changes)
- `--skip-update` Skip `apt update/upgrade`
- `--version` Print script version
- `--help` Show help

## Environment Variables

- `AI_ROOT` Base workspace path (default: `$HOME/ai`)
- `OPENCLAW_DIR` OpenClaw target directory (default: `$AI_ROOT/openclaw`)
- `OPENCLAW_REPO` OpenClaw git URL
- `OPENCLAW_DASHBOARD_URL` Dashboard URL to open after launch (default: `http://127.0.0.1:3000`)
- `AUTO_LAUNCH_OPENCLAW` Auto-launch OpenClaw after install when repo is present (`1`/`0`)
- `CREATE_OPENCLAW_SHORTCUT` Create OpenClaw desktop shortcut (`1`/`0`)
- `OPENCLAW_AUTOSTART` Enable OpenClaw autostart at login via systemd user service (`1`/`0`)
- `OPENCLAW_ONBOARD` Run OpenClaw onboarding wizard at end of install (`1`/`0`)
- `NODE_MAJOR` Node.js major version (default: `22`)
- `LOG_FILE` Installer log file path (default: `$AI_ROOT/bootstrap.log`)

## Cleanup / Remove

The installer includes a cleanup flow (menu option and `--cleanup`) that attempts to remove components this script manages:

- Docker, Node.js, GitHub CLI, fail2ban/unattended-upgrades
- Docker/NodeSource apt source files and keys
- pipx tools installed by script (`poetry`, `ruff`, `black`)
- OpenClaw repo directory, generated desktop shortcuts, and autostart service
- EasyMode summary/log files

Cleanup is best-effort and does not remove unrelated user files.

## Notes and Caveats

- Intended for Ubuntu only.
- Script requires `sudo`.
- Firewall changes may affect remote access if your SSH setup is nonstandard.
- Desktop shortcut behavior depends on desktop environment (GNOME pinning is supported).
- Script does not install models.
- OpenClaw auto-launch and browser opening are best-effort based on detected startup files.

## Gotchas (Read This)

- **Firewall (`ufw`)**
  - In hardened mode, incoming traffic is set to `deny` and outgoing to `allow`.
  - This can block inbound SSH or local-network access to services you run.
- **Fail2ban**
  - Only enabled when SSH is active.
  - Usually harmless for normal browsing; mainly impacts repeated failed login attempts.
- **Docker permissions**
  - If your user is newly added to the `docker` group, you must log out and back in before `docker` works without `sudo`.
  - OpenClaw desktop launcher also depends on this permission.
- **Desktop shortcuts/pinning**
  - Shortcut creation and dock pinning are best-effort and desktop-environment specific.
- **Apt phased updates**
  - Seeing "upgrades have been deferred due to phasing" is normal on Ubuntu.
- **OpenClaw expectations**
  - Installer does not install models.
  - Auto-launch uses best-effort detection (`docker compose` or `npm` scripts) and may need manual startup.
  - The launcher waits up to 90 seconds for the dashboard port before opening the browser; the Dashboard shortcut only opens when the port is listening.
  - OpenClaw requires `pnpm`; the installer installs it after Node (via corepack or `npm install -g pnpm`).
  - Docker Compose needs `OPENCLAW_CONFIG_DIR`, `OPENCLAW_WORKSPACE_DIR`, `OPENCLAW_GATEWAY_TOKEN`; the installer creates a `.env` with these if missing.

## Known Limitations

- Auto-launch is best-effort and depends on detected startup files/scripts.
- Dashboard open (`xdg-open`) may be ignored in headless or restricted desktop sessions.
- Dock pinning behavior is desktop-environment specific and may be unavailable outside GNOME-compatible setups.

## End-of-install issue summary

At the end of every run, the installer prints:

- **Execution summary**
  - Added / Changed / Failed (non-fatal) steps
- **Potential issues to keep in mind**
  - Common post-install gotchas users should be aware of
- **Summary and log file paths**
  - `BOOTSTRAP_SUMMARY.txt` and `bootstrap.log` locations

## Troubleshooting

- **`spawn pnpm ENOENT` or OpenClaw build fails**
  - OpenClaw's scripts require pnpm. With system Node (NodeSource), run: `sudo corepack enable && sudo corepack prepare pnpm@latest --activate` or `sudo npm install -g pnpm`. Re-run the installer to get the updated launcher.

- **Docker Compose "invalid spec: :/home/node/.openclaw: empty section between colons"**
  - Create a `.env` file in the OpenClaw repo root with `OPENCLAW_CONFIG_DIR`, `OPENCLAW_WORKSPACE_DIR`, `OPENCLAW_GATEWAY_TOKEN` set (see `runtime/config/openclaw.env.example` or re-run the installer).

- **`externally-managed-environment` during dev tools step**
  - This is a Python packaging policy on newer Ubuntu releases (PEP 668).
  - Current installer versions avoid `python3 -m pip install --user --upgrade pip` and use `pipx`.
  - If you hit this, rerun using the latest script from this repository.

## Recommended Verification

```bash
python3 --version
docker --version
docker compose version
node -v
npm -v
gh --version
docker run hello-world
```

## OpenClaw Dashboard (when OpenClaw is installed)

- Dashboard URL: `http://127.0.0.1:3000` (or value of `OPENCLAW_DASHBOARD_URL`)
- **CLI:** `openclaw` — symlinked to `~/.local/bin/openclaw`; run `openclaw --help` or `openclaw onboard` from any terminal (ensure `~/.local/bin` is in `PATH`; open a new terminal if needed)
- Status script: `$OPENCLAW_DIR/runtime/openclaw-status.sh` — checks if OpenClaw is running and optionally opens the dashboard
- Launcher: `$OPENCLAW_DIR/runtime/openclaw-launch.sh` — starts OpenClaw and opens the dashboard (skips start if already running)
- Onboard wizard: run at end of install (`openclaw onboard`) — configures .env, gateway, workspace, and skills
- Autostart: When enabled, OpenClaw starts automatically at login via a systemd user service (`~/.config/systemd/user/openclaw.service`)

## Publishing the One-Liner

Prefer pinned release tags in docs:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/v1.2.0/install.sh)
```

## License

MIT. See `LICENSE`.
