# Sentinel Security Notes

## Update (vNext skeleton)
- Rust CLI scaffold added with argv-based command execution and timeouts; policy parsing uses TOML (no `source`).
- Legacy Bash artifacts moved to `legacy/`; they still contain the risks listed below.

## Summary
Current Sentinel scripts run with elevated privileges (NetworkManager dispatcher, optional boot unit) but lack input validation, permission hardening, and structured output. The CLI is a Bash wrapper that sources config directly. No tests or redaction exist yet.

## Findings
1) Config sourcing risk: `cli-wrapper/sentinelctl` uses `source` on `~/.config/sentinel/env.conf` without validation, allowing arbitrary code execution if the file is modified.  
2) Unvalidated inputs: dispatcher consumes `$IFACE`/`$STATUS` from NetworkManager without sanitizing; rules and command args are expanded unquoted (e.g., `firewall-cmd ... $rule`), enabling word-splitting/injection if inputs are manipulated.  
3) Path and permission gaps: logs/state default to `~/dev/sentinel-logs` with no mode enforcement; config dir permissions are not set; logrotate example hardcodes `/home/valera` and uses `chattr` without ownership checks.  
4) Privilege boundary: NetworkManager dispatcher runs as root and triggers desktop notifications (`notify-send`) and background jobs; no isolation or capability bounds are defined. Optional boot unit calls a missing `/usr/local/bin/sentinel-selfcheck` with full privileges.  
5) Logging and redaction: firewall rules, diffs, and integrity outputs are written verbatim to files; no redaction of sensitive tokens/paths, and no schema versioning for future JSON output.  
6) Reliability/timeouts: calls to `firewall-cmd`, `nmcli`, `sha256sum`, and background loops lack timeouts or process supervision; failures could hang dispatcher execution.

## Recommended Actions
- Rebuild `sentinelctl` with strict argument parsing, no `source`, and explicit allowlists for env names; parse config files safely (key=value) and validate env identifiers.  
- Quote all shell variables, switch to array-based exec where possible, and validate interface names/status against expected patterns.  
- Move to XDG config/state/cache paths with enforced `0700/0600` permissions; remove user-specific hardcoding; ensure logrotate rules respect ownership.  
- Move runtime work into a supervised systemd.user service (or a small agent) with bounded privileges; keep GUI notifications out of root context.  
- Define JSON schema v1 with redaction defaults; avoid logging secrets or personal data in diffs/logs.  
- Add timeouts and error handling around external commands; add unit tests for config parsing, diffing, and status aggregation; integrate CI.
