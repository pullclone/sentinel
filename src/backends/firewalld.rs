use anyhow::Result;
use std::collections::HashSet;
use tracing::debug;

use crate::{
    backends::{Backend, BackendStatus},
    cmd::run_timeout,
    config::Policy,
    status::{Finding, Overall},
};

pub struct FirewalldBackend;

#[async_trait::async_trait]
impl Backend for FirewalldBackend {
    fn name(&self) -> &'static str {
        "firewalld"
    }

    async fn detect(&self) -> Result<bool> {
        match run_timeout("firewall-cmd", &["--state"], 1500).await {
            Ok((_code, out, _err)) => Ok(out.trim() == "running"),
            Err(err) => {
                debug!(error = ?err, "firewalld detection failed");
                Ok(false)
            }
        }
    }

    async fn snapshot(&self) -> Result<BackendStatus> {
        let active = match run_timeout("firewall-cmd", &["--state"], 1500).await {
            Ok((_code, out, _err)) => out.trim() == "running",
            Err(err) => {
                debug!(error = ?err, "firewalld state check failed");
                false
            }
        };

        let default_zone = match run_timeout("firewall-cmd", &["--get-default-zone"], 1500).await {
            Ok((_code, out, _err)) => out.trim().to_string(),
            Err(err) => {
                debug!(error = ?err, "failed to read firewalld default zone");
                "unknown".to_string()
            }
        };

        let list_args = if default_zone.is_empty() || default_zone == "unknown" {
            vec!["--list-all"]
        } else {
            vec!["--zone", default_zone.as_str(), "--list-all"]
        };

        let raw = match run_timeout("firewall-cmd", &list_args, 2000).await {
            Ok((_code, out, _err)) => out,
            Err(err) => {
                debug!(error = ?err, "failed to get firewalld listing");
                String::new()
            }
        };

        Ok(BackendStatus {
            backend_name: self.name(),
            active,
            facts: vec![("default_zone".into(), default_zone)],
            raw,
        })
    }

    async fn validate(&self, policy: &Policy, snap: &BackendStatus) -> Result<Vec<Finding>> {
        let mut findings = Vec::new();
        let checks = policy.checks.as_ref();
        let parsed = parse_zone_listing(&snap.raw);

        if checks
            .and_then(|c| c.require_firewall_active)
            .unwrap_or(true)
            && !snap.active
        {
            findings.push(Finding {
                id: "firewalld-not-running".into(),
                severity: Overall::Error,
                msg: "firewalld is not running (firewall-cmd --state != running)".into(),
            });
            return Ok(findings);
        }

        if let Some(req_services) = checks.and_then(|c| c.required_services.as_ref()) {
            for s in req_services {
                if !parsed.services.contains(s) {
                    findings.push(Finding {
                        id: format!("missing-service:{s}"),
                        severity: Overall::Warn,
                        msg: format!("required service not found in zone listing: {s}"),
                    });
                }
            }
        }

        if let Some(req_ports) = checks.and_then(|c| c.required_ports.as_ref()) {
            for p in req_ports {
                if !parsed.ports.contains(p) {
                    findings.push(Finding {
                        id: format!("missing-port:{p}"),
                        severity: Overall::Warn,
                        msg: format!("required port not found in zone listing: {p}"),
                    });
                }
            }
        }

        Ok(findings)
    }
}

#[derive(Default)]
struct ZoneListing {
    services: HashSet<String>,
    ports: HashSet<String>,
}

fn parse_zone_listing(raw: &str) -> ZoneListing {
    let mut result = ZoneListing::default();

    for line in raw.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("services:") {
            for svc in rest.split_whitespace() {
                if !svc.is_empty() {
                    result.services.insert(svc.to_string());
                }
            }
        } else if let Some(rest) = line.strip_prefix("ports:") {
            for port in rest.split_whitespace() {
                if !port.is_empty() {
                    result.ports.insert(port.to_string());
                }
            }
        }
    }

    result
}
