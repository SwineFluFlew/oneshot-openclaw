# OpenClaw EasyMode Installer (Ubuntu)

One-command bootstrap installer for fresh Ubuntu systems that prepares a safe developer baseline and optional OpenClaw setup.

## Quick Start

Run the interactive menu:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SwineFluFlew/oneshot-openclaw/master/install.sh)
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
