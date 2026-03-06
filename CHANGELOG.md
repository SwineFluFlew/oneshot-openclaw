# Changelog

## 1.1.0 - 2026-03-06

- Skip OpenClaw onboarding when repo is already installed and up to date (git pull reported "Already up to date").
- Fixed OpenClaw desktop shortcuts not launching when clicked (use wrapper scripts instead of bash -c to avoid .desktop Exec quoting issues).
- Added one-command Ubuntu EasyMode installer scaffold.
- Added interactive default and advanced menu flows.
- Added dry-run, noninteractive, yes-mode, and skip-update flags.
- Added optional terminal desktop shortcut and GNOME dock pin.
- Added logging, error trap, sudo keepalive, and verification checks.
- Added README, license, and ShellCheck CI workflow.
