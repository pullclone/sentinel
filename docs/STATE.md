# Sentinel: Current State

## Update (vNext skeleton)
- Rust CLI `sentinelctl` scaffold added (policy parsing, backend detection hooks).
- Legacy Bash prototypes moved to `legacy/` and no longer treated as runtime code.
- Nix flake/module and Waybar assets are not wired yet (pending next batches).

## Overview
Sentinel is presently a set of Bash utilities focused on Firewalld integrity checks and logging. There is no long-running daemon. Everything is event-driven (NetworkManager dispatcher) or manual (systemd oneshot helper, CLI wrapper, logrotate).

## Components
- `99-firewalld-reload`: NetworkManager dispatcher script that reloads firewalld on interface up events, enforces two ICMP rules, performs periodic integrity checks and optional “high-security” logging bursts, and writes to `~/dev/sentinel-logs/sentinel.log`. Uses `nmcli`, `firewall-cmd`, `notify-send`, and `logger`.
- `cli-wrapper/sentinelctl`: Bash helper that reads `~/.config/sentinel/env.conf`, toggles a few environment flags (log level, popups, security logging), tails logs, diffs rules, and pauses logging. Stores state in `~/.config/sentinel/env.conf` and `~/dev/sentinel-logs`.
- `boot-check service/sentinel-boot-check.service`: Example systemd oneshot unit calling a missing `/usr/local/bin/sentinel-selfcheck` script to run integrity checks at boot; outputs to journal with `SyslogIdentifier=SentinelBoot`.
- `logrotate.d/sentinel`: Example logrotate config for `~/dev/sentinel-logs/sentinel.log`, with `chattr` toggles and integrity hashing of rotated logs.
- Drafts: Variants of the dispatcher script with cosmetic logging and backup helpers; no additional functionality beyond the main dispatcher intent.

## Runtime Model
- Continuously running: none.
- Event-driven: `99-firewalld-reload` via NetworkManager dispatcher (root context). Spawns background integrity/high-security loops.
- On-demand: `cli-wrapper/sentinelctl` (user context), `logrotate` runs if configured, optional systemd boot oneshot.
- IPC: none; everything shells out to `firewall-cmd`, `nmcli`, `notify-send`, `logger`.

## Config, State, and Logs
- Config: `~/.config/sentinel/env.conf` (sourced by `sentinelctl`, holds `FIREWALL_LOG_LEVEL`, `FIREWALL_POPUPS`, `SECURITY_LOGGING`). Not XDG-compliant for logs/state.
- State/logs (all in `~/dev/sentinel-logs`): `sentinel.log` (append-only intent), `sentinel.rules.sha256`, `sentinel.current.rules`, `sentinel.lastcheck`, `highsec.timer`, optional `sentinel.log.integrity` and rules backups in drafts.
- Logging backend: file-based; optional `logger` in one draft; no journald consumption.
- Permissions: no enforced `0700/0600` on config/state/log dirs; logrotate example hardcodes `/home/valera`.

## Environment Model
- Current “environment” is just a trio of flags (`FIREWALL_LOG_LEVEL`, `FIREWALL_POPUPS`, `SECURITY_LOGGING`). There is no concept of named environments or profiles.
- No JSON output or exit-code semantics defined; `sentinelctl` only prints key/value pairs or tails files.

## Data Flow
- Network event → dispatcher reloads firewalld → ensures ICMP rules → optional integrity check/high-security mode → logs to `sentinel.log` and optional notifications.
- User CLI (`sentinelctl`) → reads env config → prints/toggles flags, tails logs, diffs rules vs. stored checksum.
- Boot oneshot (if installed) → calls external self-check script → writes to journal/log file (script missing).

## Current Gaps vs. Wayland/Niri Goals
- No Wayland/Waybar integration; no structured status output for a module.
- `sentinelctl` is far from the requested contract (no `--json`, `env list/current`, `switch-env`, `diff` variants, exit codes, or redaction).
- Hardcoded paths under `~/dev/sentinel-logs` and `/home/valera`; not XDG-compliant and not NixOS-friendly.
- No systemd.user service, journald logging, or packaging/flake/devShell.
- No tests, timeouts, or reliability hardening; background sleeps run unsupervised.

## Prioritized Bug/Tech-Debt List
1) Replace ad-hoc `sentinelctl` with a real CLI that implements the contract (JSON schema v1, exit codes, env management, log view, diff).  
2) Normalize storage: XDG config/state/cache with enforced permissions; remove hardcoded user paths; expose journald output.  
3) Refactor dispatcher logic into a maintainable service/agent (or at least a supervised systemd unit) with deterministic intervals and timeouts; drop desktop-notification coupling from root context.  
4) Add tests around status aggregation, env parsing/switching, diffing, and log filtering; introduce CI.  
5) Packaging: Nix flake outputs for CLI/agent/tray plus devShell; optional NixOS module and systemd.user unit.  
6) UX foundations: Waybar module script/config and (optional) SNI tray using `sentinelctl` as the source of truth.

## Concrete PR Plan
- Sentinelctl MVP
  - Build a single-source-of-truth CLI (prefer Rust/Go/Python with arg parsing) that covers `status`, `view-logs`, `env list/current`, `switch-env`, `diff`, `--json` schema v1, clear exit codes, and redaction.  
  - Use XDG paths, stable log ingestion (journald reader or file fallback), and deterministic timeouts.  
  - Add unit tests for env handling, diff, status, and log filtering; ship a devShell with test/lint tools.
- Waybar Integration
  - Provide a Waybar custom module script calling `sentinelctl status --json` for icon/text and exit-code mapping.  
  - Click handlers: left opens `fuzzel/wofi/rofi-wayland` action menu invoking `sentinelctl`; right opens logs/diff in `$PAGER`/terminal.  
  - Document sample Waybar config and menu script.
- Nix Packaging
  - Add flake outputs for `sentinelctl` (and agent/tray if added) plus `devShell`.  
  - Optional NixOS module: `services.sentinel.enable/environment/settings/extraEnv`, systemd.user service, XDG paths, journald logging, and log access via `sentinelctl view-logs`.
