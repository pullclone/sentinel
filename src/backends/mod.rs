use crate::{config::Policy, status::Finding};
use anyhow::Result;

pub mod firewalld;
pub mod nftables;

#[derive(Clone, Debug)]
pub struct BackendStatus {
    pub backend_name: &'static str,
    pub active: bool,
    pub facts: Vec<(String, String)>,
    pub raw: String,
}

#[async_trait::async_trait]
pub trait Backend: Send + Sync {
    fn name(&self) -> &'static str;

    /// Lightweight detection: is this backend usable on this machine right now?
    async fn detect(&self) -> Result<bool>;

    /// Gather current state for status output / diff.
    async fn snapshot(&self) -> Result<BackendStatus>;

    /// Validate policy against current snapshot (MVP checks ok; evolve later).
    async fn validate(&self, policy: &Policy, snap: &BackendStatus) -> Result<Vec<Finding>>;
}

pub fn all_backends() -> Vec<Box<dyn Backend>> {
    vec![
        Box::new(firewalld::FirewalldBackend),
        Box::new(nftables::NftablesBackend),
    ]
}
