# OpenClaw EasyMode Installer (Ubuntu)

One-command bootstrap installer for fresh Ubuntu systems that prepares a safe developer baseline and optional OpenClaw setup.

## Quick Start

Run the interactive menu:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/master/install.sh)
```

If `curl` is missing on a fresh image:

```bash
sudo apt update && sudo apt install -y curl
```

Or use `wget` directly (no process substitution needed):

```bash
wget -qO- https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/master/install.sh | bash
```

Run safe defaults without menu:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/master/install.sh) --default --noninteractive --yes
```

Run defaults plus OpenClaw clone + helper files:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/master/install.sh) --default-openclaw --noninteractive --yes
```

## Safer Alternative (Review First)

```bash
curl -fsSL https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/master/install.sh -o install.sh
less install.sh
bash install.sh
```

## What It Installs

- Base Ubuntu packages for development and troubleshooting
- Security tools (`ufw`, `fail2ban`, `unattended-upgrades`) in hardened mode
- Common dev tooling (`pipx`, `poetry`, `ruff`, `black`)
- Docker Engine + Docker Compose plugin
- Node.js via NodeSource (default major: 22)
- GitHub CLI (`gh`)
- Optional OpenClaw clone and helper runtime files
- OpenClaw launcher helper (`runtime/openclaw-launch.sh`) for start + dashboard open
- Optional OpenClaw desktop shortcut (`OpenClaw.desktop`)
- Optional terminal desktop shortcut and GNOME dock pin

When OpenClaw is installed, the installer also attempts to launch it and open the dashboard URL automatically.

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

## CLI Flags

- `--default` Run safe defaults without menu
- `--default-openclaw` Run desktop-safe defaults + OpenClaw prep
- `--hardened` Run hardened defaults (security tools enabled)
- `--hardened-openclaw` Run hardened defaults + OpenClaw prep
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
- `NODE_MAJOR` Node.js major version (default: `22`)
- `LOG_FILE` Installer log file path (default: `$AI_ROOT/bootstrap.log`)

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

## End-of-install issue summary

At the end of every run, the installer prints:

- **Execution summary**
  - Added / Changed / Failed (non-fatal) steps
- **Potential issues to keep in mind**
  - Common post-install gotchas users should be aware of
- **Summary and log file paths**
  - `BOOTSTRAP_SUMMARY.txt` and `bootstrap.log` locations

## Troubleshooting

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

## Publishing the One-Liner

Prefer pinned release tags in docs:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/v1.1.0/install.sh)
```

## License

MIT. See `LICENSE`.
