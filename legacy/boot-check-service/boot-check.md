## ✅ **Step 1: Create a systemd boot-time unit for Sentinel self-check**

### 🔧 `/etc/systemd/system/sentinel-boot-check.service`

```ini
[Unit]
Description=Sentinel: Firewall Integrity Check at Boot
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sentinel-selfcheck
StandardOutput=journal
StandardError=journal
SyslogIdentifier=SentinelBoot
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

---

### 🔧 `/usr/local/bin/sentinel-selfcheck`

(make executable: `chmod +x /usr/local/bin/sentinel-selfcheck`)

```bash
#!/bin/bash

# Minimal boot-time self-check for Sentinel
export FIREWALL_LOG_LEVEL=INFO
export FIREWALL_POPUPS=false

SENTINEL_DIR="$HOME/dev/sentinel-logs"
LOG_FILE="$SENTINEL_DIR/sentinel.boot.log"
mkdir -p "$SENTINEL_DIR"

{
  echo "=== Sentinel Boot-Time Self-Check ==="
  date

  echo "--- Verifying firewall rules..."
  firewall-cmd --direct --get-all-rules

  echo "--- Running integrity check..."
  "$HOME/dev/sentinel-check.sh"

  echo "--- Verifying rotated logs..."
  "$HOME/dev/sentinel-verify-logs.sh"

  echo "=== Completed ==="
  date
} >> "$LOG_FILE" 2>&1
```

> If you prefer, you can simply *source* your main Sentinel script and call `run_integrity_check` directly.

---

## ✅ **Step 2: Enable and test**

```bash
sudo systemctl daemon-reexec
sudo systemctl enable sentinel-boot-check.service
sudo systemctl start sentinel-boot-check.service
journalctl -t SentinelBoot -b
```

---

## ✅ **Step 3: Journal-Based Alerting with `systemd` Units**

You can use **`systemd-path` + `journalctl` + `mail`/`notify-send`/`logger`** to trigger alerts for critical failures:

### Example: Monitor for `firewall-cmd --reload` failures

```bash
journalctl -u NetworkManager | grep "Failed to reload firewalld"
```

Or make it **automatic** with a `systemd` timer + script that checks `journalctl -p err -u NetworkManager` (or `-t Sentinel`).

---

## 🧠 Why It’s Not Redundant

| Feature                           | Dispatcher-based            | Boot Unit                       |
| --------------------------------- | --------------------------- | ------------------------------- |
| Interface reaction                | ✅ Real-time                 | ❌                               |
| Boot-time readiness               | ❌                           | ✅                               |
| Journal visibility                | ✅ (via `logger`)            | ✅ (via `SyslogIdentifier`)      |
| SHA256 integrity + ruleset verify | ✅                           | ✅                               |
| Failover independence             | No — requires NM dispatcher | Yes — standalone, systemd-based |

---

Would you like me to patch these components into a clean file structure with install steps and summary?
