#!/bin/bash

# Sentinel Script: /etc/NetworkManager/dispatcher.d/99-firewalld-sentinel
# Purpose: Selectively reload firewalld when interfaces come online, with smart logging, integrity checks, KDE notifications, Alpenglow-themed logging, and automatic ruleset/log backups

# === Configurable Variables ===
SENTINEL_LOG_DIR="$HOME/dev/sentinel-logs"
SENTINEL_LOG_FILE="$SENTINEL_LOG_DIR/sentinel.log"
SENTINEL_CHECKSUM_FILE="$SENTINEL_LOG_DIR/sentinel.rules.sha256"
SENTINEL_TIMESTAMP_FILE="$SENTINEL_LOG_DIR/sentinel.lastcheck"
SENTINEL_HIGHSEC_FILE="$SENTINEL_LOG_DIR/highsec.timer"
FIREWALL_LOG_LEVEL="${FIREWALL_LOG_LEVEL:-INFO}"
DEFAULT="${DEFAULT:-false}"
SECURITY_LOGGING="${SECURITY_LOGGING:-false}"
FIREWALL_POPUPS="${FIREWALL_POPUPS:-false}"

# === Alpenglow Color Theme for Console Logging ===
COLORS=(
    [DEBUG]='\e[38;5;99m'
    [INFO]='\e[38;5;215m'
    [WARN]='\e[38;5;208m'
    [ERROR]='\e[38;5;197m'
    [RESET]='\e[0m'
)

mkdir -p "$SENTINEL_LOG_DIR"

log() {
    local level="$1"; shift
    local message="$*"

    declare -A LEVELS=( [DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 )
    local current_level=${LEVELS[$FIREWALL_LOG_LEVEL]}
    local message_level=${LEVELS[$level]}

    if [[ $message_level -ge $current_level ]]; then
        printf "%s [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" >> "$SENTINEL_LOG_FILE"
        printf "%b%s [%s] %s%b\n" "${COLORS[$level]}" "$(date '+%H:%M:%S')" "$level" "$message" "${COLORS[RESET]}"
    fi

    if command -v logger &>/dev/null; then
        logger -t Sentinel -p user.${level,,} "$message"
    fi
}

firewall_notify() {
    local title="$1"
    local body="$2"
    if [[ "$FIREWALL_POPUPS" == "true" ]]; then
        notify-send "Sentinel Alert: $title" "$body"
    fi
}

backup_ruleset() {
    local backup_file="$SENTINEL_LOG_DIR/sentinel.rules.$(date +%Y%m%d-%H%M%S).bak"
    firewall-cmd --direct --get-all-rules > "$backup_file"
    sha256sum "$backup_file" >> "$SENTINEL_LOG_DIR/sentinel.rules.backups.sha256"
    log INFO "Backed up ruleset to $backup_file"
}

verify_rotated_logs() {
    log DEBUG "Verifying SHA256 of rotated Sentinel logs..."
    local integrity_file="$SENTINEL_LOG_DIR/sentinel.log.integrity"
    if [[ -f "$integrity_file" ]]; then
        if ! sha256sum -c "$integrity_file" >> "$SENTINEL_LOG_FILE" 2>&1; then
            log ERROR "One or more rotated logs failed SHA256 integrity check!"
            firewall_notify "Sentinel Log Integrity Alert" "Log tampering may have occurred."
        else
            log DEBUG "All rotated logs passed SHA256 integrity check."
        fi
    else
        log WARN "No integrity file for rotated logs found."
    fi
}

verify_or_initialize_rules() {
    log DEBUG "Verifying presence of critical firewalld rules."
    local required_rules=(
        "-p icmp --icmp-type echo-request -m limit --limit 5/second --limit-burst 10 -j ACCEPT"
        "-p icmp --icmp-type echo-request -j DROP"
    )

    for rule in "${required_rules[@]}"; do
        if ! firewall-cmd --direct --get-all-rules | grep -q -- "$rule"; then
            log WARN "Missing required rule: $rule — Adding it now."
            if [[ "$rule" == *limit* ]]; then
                firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 $rule
            else
                firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 1 $rule
            fi
            firewall_notify "New Rule Added" "$rule"
        else
            log DEBUG "Rule already present: $rule"
        fi
    done

    log DEBUG "Reloading firewalld to apply any newly added rules."
    firewall-cmd --reload >> "$SENTINEL_LOG_FILE" 2>&1
}

should_run_integrity_check() {
    local now=$(date +%s)
    local last=0
    [[ -f "$SENTINEL_TIMESTAMP_FILE" ]] && last=$(cat "$SENTINEL_TIMESTAMP_FILE")
    local min_interval=$((22 * 60))
    local max_interval=$((7 * 3600 + 47 * 60))
    local since_last=$((now - last))
    local trigger_chance=$((RANDOM % 50))
    if (( since_last > min_interval && (since_last > max_interval || trigger_chance == 0) )); then
        echo "$now" > "$SENTINEL_TIMESTAMP_FILE"
        return 0
    fi
    return 1
}

run_integrity_check() {
    log DEBUG "Running firewall rules integrity check."
    local dump_file="$SENTINEL_LOG_DIR/sentinel.current.rules"
    firewall-cmd --direct --get-all-rules > "$dump_file" 2>> "$SENTINEL_LOG_FILE"
    sha256sum "$dump_file" > "$dump_file.sha256"
    if [[ -f "$SENTINEL_CHECKSUM_FILE" ]]; then
        if ! sha256sum -c "$SENTINEL_CHECKSUM_FILE" >> "$SENTINEL_LOG_FILE" 2>&1; then
            log ERROR "Firewall rules checksum mismatch!"
            firewall_notify "Integrity Check Failed" "Firewall checksum mismatch detected."
        else
            log DEBUG "Firewall rules checksum matches."
        fi
    else
        log WARN "No previous checksum file found. Creating baseline."
        cp "$dump_file.sha256" "$SENTINEL_CHECKSUM_FILE"
    fi
    verify_rotated_logs
}

trigger_high_security_logging() {
    local now=$(date +%s)
    local last_run=0
    [[ -f "$SENTINEL_HIGHSEC_FILE" ]] && last_run=$(cat "$SENTINEL_HIGHSEC_FILE")
    local cycle_duration=$((14 * 24 * 3600))
    local jitter=$(( (RANDOM % (5 * 24 * 3600)) * (RANDOM % 2 == 0 ? 1 : -1) ))
    local interval=$((cycle_duration + jitter))
    if (( now - last_run > interval )); then
        echo "$now" > "$SENTINEL_HIGHSEC_FILE"
        log INFO "High-security logging mode initiated."
        firewall_notify "High-Security Logging" "High-security logging mode has started."
        (
            export FIREWALL_LOG_LEVEL=DEBUG
            export SECURITY_LOGGING=true
            local duration=$(( (RANDOM % (6 * 3600)) + (3 * 3600) ))
            local end_time=$(( $(date +%s) + duration ))
            while (( $(date +%s) < end_time )); do
                run_integrity_check
                sleep 300
            done
            log INFO "High-security logging mode concluded."
            firewall_notify "High-Security Logging Ended" "Mode has ended."
        ) &
    fi
}

log DEBUG "Sentinel started with arguments: $@"

IFACE="$1"
STATUS="$2"

case "$STATUS" in
    up)
        log INFO "Interface $IFACE is up. Evaluating whether to reload firewalld."
        if [[ "$IFACE" == "lo" || "$IFACE" == veth* || "$IFACE" == docker* || "$IFACE" == br-* ]]; then
            log DEBUG "Ignoring interface $IFACE (virtual or loopback)."
            exit 0
        fi
        CON_STATE=$(nmcli -t -f GENERAL.STATE device show "$IFACE" 2>/dev/null | cut -d: -f2)
        CON_TYPE=$(nmcli -t -f GENERAL.TYPE device show "$IFACE" 2>/dev/null | cut -d: -f2)
        log DEBUG "Interface $IFACE type: $CON_TYPE, state: $CON_STATE"
        if [[ "$CON_STATE" != "100 (connected)" ]]; then
            log WARN "Interface $IFACE is not fully connected. Skipping reload."
            exit 0
        fi
        if [[ "$CON_TYPE" == "ethernet" || "$CON_TYPE" == "wifi" ]]; then
            log INFO "Backing up current ruleset before reload."
            backup_ruleset
            log INFO "Reloading firewalld for $IFACE ($CON_TYPE)"
            if firewall-cmd --reload >> "$SENTINEL_LOG_FILE" 2>&1; then
                log INFO "Successfully reloaded firewalld."
                if [[ "$SECURITY_LOGGING" == "true" || "$FIREWALL_LOG_LEVEL" == "DEBUG" ]]; then
                    log DEBUG "Dumping direct rules after reload."
                    firewall-cmd --direct --get-all-rules >> "$SENTINEL_LOG_FILE" 2>&1
                fi
                verify_or_initialize_rules
                if should_run_integrity_check; then
                    run_integrity_check
                else
                    log DEBUG "Skipping integrity check (not due yet)."
                fi
                trigger_high_security_logging
            else
                log ERROR "Failed to reload firewalld."
                firewall_notify "Reload Failed" "Failed to reload firewalld."
            fi
        else
            log DEBUG "Interface $IFACE type $CON_TYPE not eligible for reload."
        fi
        ;;
    down)
        log DEBUG "Interface $IFACE went down. No action taken."
        ;;
    *)
        log DEBUG "Unhandled event: $STATUS on $IFACE"
        ;;
esac
