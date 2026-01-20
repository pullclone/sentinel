### 🛠️ Setup Instructions (Step-by-Step)

#### 🔒 1. Log Directory & File Permissions

```bash
mkdir -p ~/dev/sentinel-logs
touch ~/dev/sentinel-logs/sentinel.log
sudo chattr +a ~/dev/sentinel-logs/sentinel.log
```

#### 📜 2. Logrotate Configuration

Save the following as:
`/etc/logrotate.d/sentinel`

```conf
/home/valera/dev/sentinel-logs/sentinel.log {
    daily
    size 500k
    rotate 14
    compress
    dateext
    missingok
    notifempty
    copytruncate

    prerotate
        /usr/bin/chattr -a /home/valera/dev/sentinel-logs/sentinel.log || true
    endscript

    postrotate
        /usr/bin/chattr +a /home/valera/dev/sentinel-logs/sentinel.log || true
        find /home/valera/dev/sentinel-logs/ -name "sentinel.log-*.gz" -exec sha256sum {} \; >> /home/valera/dev/sentinel-logs/sentinel.log.integrity
    endscript
}
```

Then test:

```bash
sudo logrotate -f /etc/logrotate.d/sentinel
```

---

### 📂 File Locations Involved

| Path                                                     | Purpose                                     |
| -------------------------------------------------------- | ------------------------------------------- |
| `/etc/NetworkManager/dispatcher.d/99-firewalld-sentinel` | The dispatcher script                       |
| `~/dev/sentinel-logs/sentinel.log`                       | Main log file (append-only)                 |
| `~/dev/sentinel-logs/sentinel.rules.YYYYMMDD-HHMMSS.bak` | Timestamped ruleset backups                 |
| `~/dev/sentinel-logs/sentinel.rules.backups.sha256`      | Hash list of ruleset backups                |
| `~/dev/sentinel-logs/sentinel.log.integrity`             | Integrity hashes of rotated logs            |
| `~/dev/sentinel-logs/sentinel.rules.sha256`              | Current expected SHA of firewall rules      |
| `~/dev/sentinel-logs/sentinel.lastcheck`                 | Timestamp for next routine integrity check  |
| `~/dev/sentinel-logs/highsec.timer`                      | Timestamp tracker for high-security periods |
