#!/bin/bash

# Dispatcher Script: /etc/NetworkManager/dispatcher.d/99-firewalld-reload
# Purpose: Selectively reload firewalld when interfaces come online, with smart logging and periodic integrity checks

# === Configurable Variables ===
LOG_DIR="$HOME/dev/system-logs"
LOG_FILE="$LOG_DIR/firewalld-dispatcher.log"
CHECKSUM_FILE="$LOG_DIR/firewalld.rules.sha256"
TIMESTAMP_FILE="$LOG_DIR/firewalld.lastcheck"
HIGHSEC_TIMER_FILE="$LOG_DIR/highsec.timer"
FIREWALL_LOG_LEVEL="${FIREWALL_LOG_LEVEL:-INFO}"
DEFAULT="${DEFAULT:-false}"
SECURITY_LOGGING="${SECURITY_LOGGING:-false}"

# === Ensure log directory exists ===
mkdir -p "$LOG_DIR"

log() {
    local level="$1"; shift
    local message="$*"

    declare -A LEVELS=( [DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 )
    local current_level=${LEVELS[$FIREWALL_LOG_LEVEL]}
    local message_level=${LEVELS[$level]}

    if [[ $message_level -ge $current_level ]]; then
        printf "%s [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" >> "$LOG_FILE"
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
        else
            log DEBUG "Rule already present: $rule"
        fi
    done

    log DEBUG "Reloading firewalld to apply any newly added rules."
    firewall-cmd --reload >> "$LOG_FILE" 2>&1
}

should_run_integrity_check() {
    local now=$(date +%s)
    local last=0
    [[ -f "$TIMESTAMP_FILE" ]] && last=$(cat "$TIMESTAMP_FILE")

    local min_interval=$((22 * 60))            # 22 minutes
    local max_interval=$((7 * 3600 + 47 * 60)) # 7 hours 47 minutes

    local since_last=$((now - last))

    # Random chance (approx. 1 in 50) to trigger, if within allowed window
    local trigger_chance=$((RANDOM % 50))
    if (( since_last > min_interval && (since_last > max_interval || trigger_chance == 0) )); then
        echo "$now" > "$TIMESTAMP_FILE"
        return 0
    fi
    return 1
}

run_integrity_check() {
    log DEBUG "Running firewall rules integrity check."
    local dump_file="$LOG_DIR/firewalld.current.rules"
    firewall-cmd --direct --get-all-rules > "$dump_file" 2>> "$LOG_FILE"
    sha256sum "$dump_file" > "$dump_file.sha256"

    if [[ -f "$CHECKSUM_FILE" ]]; then
        if ! sha256sum -c "$CHECKSUM_FILE" >> "$LOG_FILE" 2>&1; then
            log ERROR "Firewall rules checksum mismatch!"
        else
            log DEBUG "Firewall rules checksum matches."
        fi
    else
        log WARN "No previous checksum file found. Creating baseline."
        cp "$dump_file.sha256" "$CHECKSUM_FILE"
    fi
}

trigger_high_security_logging() {
    local now=$(date +%s)
    local last_run=0
    [[ -f "$HIGHSEC_TIMER_FILE" ]] && last_run=$(cat "$HIGHSEC_TIMER_FILE")

    # Run twice per ~30 days with a jitter of +/- 5 days
    local cycle_duration=$((14 * 24 * 3600))
    local jitter=$(( (RANDOM % (5 * 24 * 3600)) * (RANDOM % 2 == 0 ? 1 : -1) ))
    local interval=$((cycle_duration + jitter))

    if (( now - last_run > interval )); then
        echo "$now" > "$HIGHSEC_TIMER_FILE"

        log INFO "High-security logging mode initiated."
        ( # Run in background
            export FIREWALL_LOG_LEVEL=DEBUG
            export SECURITY_LOGGING=true
            local duration=$(( (RANDOM % (6 * 3600)) + (3 * 3600) )) # Between 3 and 9 hours
            local end_time=$(( $(date +%s) + duration ))
            while (( $(date +%s) < end_time )); do
                run_integrity_check
                sleep 300
            done
            log INFO "High-security logging mode concluded."
        ) &
    fi
}

log DEBUG "Dispatcher started with arguments: $@"

IFACE="$1"
STATUS="$2"

case "$STATUS" in
    up)
        log INFO "Interface $IFACE is up. Evaluating whether to reload firewalld."

        # Ignore loopback and virtual interfaces
        if [[ "$IFACE" == "lo" || "$IFACE" == veth* || "$IFACE" == docker* || "$IFACE" == br-* ]]; then
            log DEBUG "Ignoring interface $IFACE (virtual or loopback)."
            exit 0
        fi

        # Determine interface type and state
        CON_STATE=$(nmcli -t -f GENERAL.STATE device show "$IFACE" 2>/dev/null | cut -d: -f2)
        CON_TYPE=$(nmcli -t -f GENERAL.TYPE device show "$IFACE" 2>/dev/null | cut -d: -f2)

        log DEBUG "Interface $IFACE type: $CON_TYPE, state: $CON_STATE"

        if [[ "$CON_STATE" != "100 (connected)" ]]; then
            log WARN "Interface $IFACE is not fully connected. Skipping reload."
            exit 0
        fi

        # Match relevant interfaces
        if [[ "$CON_TYPE" == "ethernet" || "$CON_TYPE" == "wifi" ]]; then
            log INFO "Reloading firewalld for $IFACE ($CON_TYPE)"

            if firewall-cmd --reload >> "$LOG_FILE" 2>&1; then
                log INFO "Successfully reloaded firewalld."

                if [[ "$SECURITY_LOGGING" == "true" || "$FIREWALL_LOG_LEVEL" == "DEBUG" ]]; then
                    log DEBUG "Dumping direct rules after reload."
                    firewall-cmd --direct --get-all-rules >> "$LOG_FILE" 2>&1
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
