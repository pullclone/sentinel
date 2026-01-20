use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StatusReport {
    pub schema: u32,
    pub overall: Overall,
    pub backend: String,
    pub active_profile: String,
    pub last_check: DateTime<Utc>,
    pub summary: Summary,
    pub findings: Vec<Finding>,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Overall {
    Ok,
    Warn,
    Error,
}

impl Overall {
    pub fn as_str(&self) -> &'static str {
        match self {
            Overall::Ok => "ok",
            Overall::Warn => "warn",
            Overall::Error => "error",
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Summary {
    pub checks_total: u32,
    pub checks_warn: u32,
    pub checks_failed: u32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Finding {
    pub id: String,
    pub severity: Overall,
    pub msg: String,
}

#[derive(Copy, Clone, Debug)]
pub enum ExitStatus {
    Ok,
    Warn,
    Error,
}

impl ExitStatus {
    pub fn code(self) -> i32 {
        match self {
            ExitStatus::Ok => 0,
            ExitStatus::Warn => 1,
            ExitStatus::Error => 2,
        }
    }
}

impl From<Overall> for ExitStatus {
    fn from(o: Overall) -> Self {
        match o {
            Overall::Ok => ExitStatus::Ok,
            Overall::Warn => ExitStatus::Warn,
            Overall::Error => ExitStatus::Error,
        }
    }
}
