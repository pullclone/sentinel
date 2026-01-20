# Sentinel vNext (NixOS + Wayland)

Sentinel is a Rust CLI (`sentinelctl`) for **policy validation + status reporting** across pluggable firewall backends. The CLI is the single source of truth for UI consumers (Waybar, menus, future tray).

## What it does
- Reads a TOML policy (`schema = 1`) and validates live firewall state.
- Backends: `firewalld` (`firewall-cmd`) and `nftables` (`nft`), with auto-detect.
- Emits status JSON schema v1 with exit codes: 0=ok, 1=warn, 2=error.
- NixOS module runs periodic checks to `/run/sentinel/status.json`, world-readable for Waybar.

## Policy
- User runs: `~/.config/sentinel/policy.toml` (XDG).
- NixOS module: typically `/etc/sentinel/policy.toml` or a Nix store path.
- Example: `sentinel.policy.toml.example`

```toml
schema = 1
backend = "auto" # auto|firewalld|nftables

[checks]
require_firewall_active = true
required_services = ["ssh"]
required_ports = ["22/tcp"]
required_fragments = ["tcp dport 22 accept"]
```

## CLI examples
```bash
# format, build, test
cargo fmt && cargo build && cargo test

# status (human / one-line / JSON)
cargo run -- status
cargo run -- status --one-line
cargo run -- status --json

# check (exit codes 0/1/2) and backend detection
cargo run -- check --json
cargo run -- backend detect
```

## Flake usage
- `nix develop` — shell with cargo/rustc/rustfmt/clippy.
- `nix build` — builds `sentinelctl`.
- `nixosModules.sentinel` — NixOS module exporting the service/timer.

On first `nix build`, replace the printed `cargoHash` in `flake.nix` and re-run.

## NixOS module example
```nix
{
  services.sentinel = {
    enable = true;
    package = inputs.sentinel.packages.${pkgs.system}.default;
    policyFile = /etc/sentinel/policy.toml; # or a store path
    backend = "auto";
    interval = "30s";
    statusPath = "/run/sentinel/status.json";

    waybar.enable = true;
    # waybar.launcherCmd = "${pkgs.wofi}/bin/wofi --dmenu -p 'Sentinel> '";
  };

  # Optional: provide policy via /etc
  environment.etc."sentinel/policy.toml".text = ''
    schema = 1
    backend = "auto"
    [checks]
    require_firewall_active = true
    required_ports = ["22/tcp"]
    required_fragments = ["tcp dport 22 accept"]
  '';
}
```

## Waybar wiring (installed when `services.sentinel.waybar.enable = true`)
- Helper scripts/snippet land at: `/etc/sentinel/waybar/`
  - `sentinel-waybar.sh` — returns Waybar JSON (text/class/tooltip) reading `statusPath`.
  - `sentinel-menu.sh` — menu (default launcher: fuzzel); change via `waybar.launcherCmd` (e.g., wofi/rofi-wayland).
  - `waybar.jsonc` — ready-to-copy snippet.
- Waybar config snippet (already written to `/etc/sentinel/waybar/waybar.jsonc`):
```jsonc
{
  "custom/sentinel": {
    "exec": "/etc/sentinel/waybar/sentinel-waybar.sh /run/sentinel/status.json",
    "return-type": "json",
    "interval": 5,
    "on-click": "/etc/sentinel/waybar/sentinel-menu.sh"
  }
}
```

Status file is world-readable by design (redacted schema v1) so Waybar can read it. The menu uses absolute store paths for jq/launcher/less.
