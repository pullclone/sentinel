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

  waybarDir = cfg.waybar.assetsDir;

  waybarScript = pkgs.writeShellScript "sentinel-waybar.sh" ''
    set -euo pipefail

    STATUS_FILE="''${1:-${cfg.statusPath}}"
    JQ="${pkgs.jq}/bin/jq"

    if [[ ! -r "$STATUS_FILE" ]]; then
      "$JQ" -n --arg text "🛡 sentinel:unknown" --arg class "error" --arg tooltip "No status file: $STATUS_FILE" \
        '{text:$text,class:$class,tooltip:$tooltip}'
      exit 0
    fi

    overall="$("$JQ" -r '.overall // "error"' "$STATUS_FILE")"
    backend="$("$JQ" -r '.backend // "unknown"' "$STATUS_FILE")"

    text="🛡 ''${backend}:''${overall}"

    tooltip="$("$JQ" -r '
      "Sentinel (" + (.backend // "unknown") + "): " + (.overall // "unknown") + "\n" +
      "warn=" + ((.summary.checks_warn // 0)|tostring) + " failed=" + ((.summary.checks_failed // 0)|tostring) + "\n\n" +
      ((.findings // []) | map(.severity + ": " + .id + " — " + .msg) | .[0:10] | join("\n"))
    ' "$STATUS_FILE")"

    "$JQ" -n --arg text "$text" --arg class "$overall" --arg tooltip "$tooltip" \
      '{text:$text,class:$class,tooltip:$tooltip}'
  '';

  menuScript = pkgs.writeShellScript "sentinel-menu.sh" ''
    set -euo pipefail

    SENTINEL="${lib.getExe cfg.package}"
    LAUNCHER='${cfg.waybar.launcherCmd}'
    PAGER="${pkgs.less}/bin/less"

    choice="$(printf "Status\nCheck\nDiff\nBackends\n" | eval "$LAUNCHER" || true)"

    case "$choice" in
      Status) "$SENTINEL" status ;;
      Check)  "$SENTINEL" check ;;
      Diff)   "$SENTINEL" diff | ''${PAGER} ;;
      Backends) "$SENTINEL" backend detect | ''${PAGER} ;;
      *) exit 0 ;;
    esac
  '';

  waybarSnippet = pkgs.writeText "waybar.jsonc" ''
    // Sentinel (installed by NixOS module)
    // Scripts:
    //   ${waybarDir}/sentinel-waybar.sh
    //   ${waybarDir}/sentinel-menu.sh
    //
    // Add this block into your Waybar config:
    {
      "custom/sentinel": {
        "exec": "${waybarDir}/sentinel-waybar.sh ${cfg.statusPath}",
        "return-type": "json",
        "interval": 5,
        "on-click": "${waybarDir}/sentinel-menu.sh"
      }
    }
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

    # Install Waybar assets when enabled
    environment.etc = lib.mkIf cfg.waybar.enable {
      "sentinel/waybar/sentinel-waybar.sh" = {
        source = waybarScript;
        mode = "0755";
      };
      "sentinel/waybar/sentinel-menu.sh" = {
        source = menuScript;
        mode = "0755";
      };
      "sentinel/waybar/waybar.jsonc" = {
        source = waybarSnippet;
        mode = "0644";
      };
    };

    environment.systemPackages = lib.mkIf cfg.waybar.enable (
      [ pkgs.jq pkgs.fuzzel pkgs.less ] ++ [ cfg.package ]
    );

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
