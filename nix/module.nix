{ lib, config, pkgs, ... }:
let
  cfg = config.services.sentinel;

  writer = pkgs.writeShellScriptBin "sentinel-write-status" ''
    set -euo pipefail
    umask 022

    mkdir -p "$(dirname "${cfg.statusPath}")"

    tmp="$(mktemp --tmpdir="$(dirname "${cfg.statusPath}")" sentinel.status.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT

    ${lib.getExe cfg.package} check --json \
      --backend ${cfg.backend} \
      --policy ${cfg.policyFile} \
      ${lib.escapeShellArgs cfg.extraArgs} \
      > "$tmp"

    chmod 0644 "$tmp"
    mv -f "$tmp" "${cfg.statusPath}"
    trap - EXIT
  '';
in
{
  options.services.sentinel = {
    enable = lib.mkEnableOption "Sentinel periodic policy validation + status reporting";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The sentinelctl package to run.";
    };

    policyFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to sentinel policy TOML (schema = 1).";
    };

    backend = lib.mkOption {
      type = lib.types.enum [ "auto" "firewalld" "nftables" ];
      default = "auto";
      description = "Backend selection for sentinelctl.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "30s";
      description = "systemd timer interval (e.g. 10s, 30s, 2min).";
    };

    statusPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/sentinel/status.json";
      description = "Path to the JSON status file (world-readable for Waybar).";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra args passed to sentinelctl check.";
    };

    waybar = {
      enable = lib.mkEnableOption "Install Waybar helper assets (placeholder for future assets)";

      assetsDir = lib.mkOption {
        type = lib.types.str;
        default = "/etc/sentinel/waybar";
        description = "Directory where Waybar helper scripts/snippets would be installed.";
      };

      launcherCmd = lib.mkOption {
        type = lib.types.str;
        default = "${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt 'Sentinel> '";
        description = "Launcher command for any Waybar menu helpers.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.services.sentinel-check = {
      description = "Sentinel policy check (writes status JSON)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${writer}/bin/sentinel-write-status";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_NETLINK" ];
        PrivateNetwork = true;
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];

        RuntimeDirectory = "sentinel";
        RuntimeDirectoryMode = "0755";

        SyslogIdentifier = "sentinel";
      };
    };

    systemd.timers.sentinel-check = {
      description = "Run Sentinel policy checks periodically";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = cfg.interval;
        AccuracySec = "1s";
        RandomizedDelaySec = "2s";
        Unit = "sentinel-check.service";
      };
    };
  };
}
