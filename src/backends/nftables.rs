use anyhow::Result;
use tracing::debug;

use crate::{
    backends::{Backend, BackendStatus},
    cmd::run_timeout,
    config::Policy,
    status::{Finding, Overall},
};

pub struct NftablesBackend;

#[async_trait::async_trait]
impl Backend for NftablesBackend {
    fn name(&self) -> &'static str {
        "nftables"
    }

    async fn detect(&self) -> Result<bool> {
        match run_timeout("nft", &["list", "ruleset"], 2000).await {
            Ok((code, _out, _err)) => Ok(code == 0),
            Err(err) => {
                debug!(error = ?err, "nftables detection failed");
                Ok(false)
            }
        }
    }

    async fn snapshot(&self) -> Result<BackendStatus> {
        let (code, out, err) = match run_timeout("nft", &["list", "ruleset"], 2500).await {
            Ok(res) => res,
            Err(err) => {
                debug!(error = ?err, "nft list ruleset failed");
                (1, String::new(), String::new())
            }
        };
        let active = code == 0;
        let raw = if active { out } else { err };

        Ok(BackendStatus {
            backend_name: self.name(),
            active,
            facts: vec![],
            raw,
        })
    }

    async fn validate(&self, policy: &Policy, snap: &BackendStatus) -> Result<Vec<Finding>> {
        let mut findings = Vec::new();
        let checks = policy.checks.as_ref();

        if checks
            .and_then(|c| c.require_firewall_active)
            .unwrap_or(true)
            && !snap.active
        {
            findings.push(Finding {
                id: "nftables-unavailable".into(),
                severity: Overall::Error,
                msg: "unable to read nftables ruleset (nft list ruleset failed)".into(),
            });
            return Ok(findings);
        }

        if let Some(frags) = checks.and_then(|c| c.required_fragments.as_ref()) {
            for f in frags {
                if !snap.raw.contains(f) {
                    findings.push(Finding {
                        id: format!("missing-fragment:{f}"),
                        severity: Overall::Warn,
                        msg: format!("required fragment not found in ruleset: {f}"),
                    });
                }
            }
        }

        Ok(findings)
    }
}
