use clap::{Parser, Subcommand, ValueEnum};

#[derive(Parser, Debug)]
#[command(
    name = "sentinelctl",
    version,
    about = "Sentinel: policy validation + status reporting"
)]
pub struct Cli {
    /// Override backend selection (default: auto)
    #[arg(long, value_enum, default_value_t = BackendChoice::Auto)]
    pub backend: BackendChoice,

    /// Path to policy file (default: XDG config sentinel/policy.toml)
    #[arg(long)]
    pub policy: Option<std::path::PathBuf>,

    #[command(subcommand)]
    pub cmd: Command,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Show current status (human or JSON)
    Status {
        #[arg(long)]
        json: bool,
        /// Print a short single-line status for bars
        #[arg(long)]
        one_line: bool,
    },

    /// Run validations and return exit code (0/1/2)
    Check {
        #[arg(long)]
        json: bool,
    },

    /// Show diff between current state and policy/baseline (MVP: policy-based snapshot)
    Diff,

    /// Backend utilities
    Backend {
        #[command(subcommand)]
        cmd: BackendCmd,
    },
}

#[derive(Subcommand, Debug)]
pub enum BackendCmd {
    List,
    Detect,
}

#[derive(Copy, Clone, Debug, ValueEnum, PartialEq, Eq)]
pub enum BackendChoice {
    Auto,
    Firewalld,
    Nftables,
}
