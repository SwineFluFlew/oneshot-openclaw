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
- Security tools (`ufw`, `fail2ban`, `unattended-upgrades`)
- Common dev tooling (`pipx`, `poetry`, `ruff`, `black`)
- Docker Engine + Docker Compose plugin
- Node.js via NodeSource (default major: 22)
- GitHub CLI (`gh`)
- Optional OpenClaw clone and helper runtime files
- Optional terminal desktop shortcut and GNOME dock pin

## Menu Modes

- **Default safe install**
  - Installs baseline tools
  - Does not clone OpenClaw
- **Default + OpenClaw prep**
  - Baseline tools plus OpenClaw clone and local helper files
- **Advanced menu**
  - Toggle each install component individually

## CLI Flags

- `--default` Run safe defaults without menu
- `--default-openclaw` Run defaults + OpenClaw prep
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
- `NODE_MAJOR` Node.js major version (default: `22`)
- `LOG_FILE` Installer log file path (default: `$AI_ROOT/bootstrap.log`)

## Notes and Caveats

- Intended for Ubuntu only.
- Script requires `sudo`.
- Firewall changes may affect remote access if your SSH setup is nonstandard.
- Desktop shortcut behavior depends on desktop environment (GNOME pinning is supported).
- Script does not install models and does not auto-start OpenClaw.

## Gotchas (Read This)

- **Firewall (`ufw`)**
  - The script sets incoming traffic to `deny` and outgoing to `allow`.
  - This can block inbound SSH or local-network access to services you run.
- **Fail2ban**
  - Usually harmless for normal browsing.
  - Mainly impacts repeated failed login attempts (for example SSH lockouts).
- **Docker permissions**
  - If your user is newly added to the `docker` group, you must log out and back in before `docker` works without `sudo`.
- **Desktop shortcuts/pinning**
  - Shortcut creation and dock pinning are best-effort and desktop-environment specific.
- **Apt phased updates**
  - Seeing "upgrades have been deferred due to phasing" is normal on Ubuntu.
- **OpenClaw expectations**
  - Installer does not install models and does not auto-start OpenClaw.

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
