use anyhow::{Context, Result};
use directories::ProjectDirs;
use serde::Deserialize;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Deserialize)]
pub struct Policy {
    pub schema: u32,
    pub backend: Option<String>,
    pub checks: Option<Checks>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Checks {
    pub require_firewall_active: Option<bool>,
    pub required_services: Option<Vec<String>>,
    pub required_ports: Option<Vec<String>>,
    pub required_fragments: Option<Vec<String>>,
}

impl Default for Policy {
    fn default() -> Self {
        Self {
            schema: 1,
            backend: Some("auto".into()),
            checks: Some(Checks::default()),
        }
    }
}

impl Default for Checks {
    fn default() -> Self {
        Self {
            require_firewall_active: Some(true),
            required_services: None,
            required_ports: None,
            required_fragments: None,
        }
    }
}

pub fn default_policy_path() -> Result<PathBuf> {
    let proj = ProjectDirs::from("org", "sentinel", "sentinel")
        .context("unable to determine XDG project dirs")?;
    Ok(proj.config_dir().join("policy.toml"))
}

pub fn load_policy(path: &Path) -> Result<Policy> {
    let default_path = default_policy_path()?;
    if !path.exists() {
        if path == default_path {
            tracing::warn!(path = %path.display(), "policy file not found; using default inline policy");
            return Ok(Policy::default());
        }
        anyhow::bail!("policy file not found: {}", path.display());
    }

    let s = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read policy file: {}", path.display()))?;
    let p: Policy = toml::from_str(&s).context("failed to parse policy TOML")?;
    anyhow::ensure!(p.schema == 1, "unsupported policy schema: {}", p.schema);
    Ok(p)
}
