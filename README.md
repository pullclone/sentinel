# Sentinel vNext (NixOS + Wayland)

Sentinel is being rebuilt as a Rust CLI (`sentinelctl`) that validates firewall policy and reports status for pluggable backends (firewalld, nftables, and future backends). The CLI is the single source of truth for UI consumers such as Waybar.

## Current state
- Rust skeleton with `sentinelctl` subcommands: `status`, `check`, `diff`, `backend list`, `backend detect`.
- Policy parsing uses TOML (`schema = 1`). Missing default policy falls back to a minimal inline policy.
- Backends: firewalld (`firewall-cmd`) and nftables (`nft`) with simple snapshot/validation hooks.

## Usage (dev)
```bash
# format, build, test
cargo fmt
cargo build
cargo test

# sample run (uses default XDG policy path if none provided)
cargo run -- status --one-line
```

## Nix flake
- `nix develop` — enters a shell with cargo/rustc/rustfmt/clippy.
- `nix build` — builds the `sentinelctl` binary.
- `nixosModules.sentinel` — NixOS module for periodic checks writing `/run/sentinel/status.json`.

On first `nix build`, Nix will print the expected `cargoHash`; replace the placeholder in `flake.nix` with that value and re-run.

## Policy example
See `sentinel.policy.toml.example` for a minimal schema-1 policy.
