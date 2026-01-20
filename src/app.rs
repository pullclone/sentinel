use anyhow::{anyhow, Result};
use chrono::Utc;

use crate::{
    backends::{all_backends, firewalld::FirewalldBackend, nftables::NftablesBackend, Backend},
    cli::{BackendChoice, BackendCmd, Cli, Command},
    config::{default_policy_path, load_policy, Policy},
    status::{ExitStatus, Overall, StatusReport, Summary},
};

pub async fn run(cli: Cli) -> Result<ExitStatus> {
    match cli.cmd {
        Command::Backend { cmd } => {
            match cmd {
                BackendCmd::List => {
                    for b in all_backends() {
                        println!("{}", b.name());
                    }
                }
                BackendCmd::Detect => {
                    for b in all_backends() {
                        let ok = b.detect().await.unwrap_or(false);
                        println!("{}: {}", b.name(), if ok { "yes" } else { "no" });
                    }
                }
            }
            Ok(ExitStatus::Ok)
        }
        _ => handle_status_like(cli).await,
    }
}

async fn handle_status_like(cli: Cli) -> Result<ExitStatus> {
    let policy_path = cli.policy.clone().unwrap_or(default_policy_path()?);
    let policy_res = load_policy(&policy_path);

    let backend_hint = backend_label(
        cli.backend,
        policy_res.as_ref().ok().and_then(|p| p.backend.as_deref()),
    );

    let policy = match policy_res {
        Ok(p) => p,
        Err(_) => {
            let report = error_report(
                &backend_hint,
                "policy-load-failed",
                "policy file missing or invalid (schema=1 required)",
            );
            return emit_report(cli.cmd, report);
        }
    };

    let backend = match select_backend(cli.backend, policy.backend.as_deref()).await {
        Ok(b) => b,
        Err(_) => {
            let report = error_report(
                &backend_label(cli.backend, policy.backend.as_deref()),
                "backend-detect-failed",
                "no supported firewall backend detected (firewalld or nftables)",
            );
            return emit_report(cli.cmd, report);
        }
    };

    match cli.cmd {
        Command::Status { json, one_line } => {
            let report = build_report(backend.as_ref(), &policy).await?;
            output_report(&report, json, one_line);
            Ok(report.overall.into())
        }
        Command::Check { json } => {
            let report = build_report(backend.as_ref(), &policy).await?;
            if json {
                println!("{}", serde_json::to_string_pretty(&report)?);
            } else {
                println!("{}", report.overall.as_str());
            }
            Ok(report.overall.into())
        }
        Command::Diff => {
            let snap = backend.snapshot().await?;
            println!("{}", snap.raw.trim());
            Ok(ExitStatus::Ok)
        }
        Command::Backend { .. } => unreachable!("handled earlier"),
    }
}

async fn select_backend(
    choice: BackendChoice,
    policy_backend: Option<&str>,
) -> Result<Box<dyn Backend>> {
    match choice {
        BackendChoice::Firewalld => return Ok(Box::new(FirewalldBackend)),
        BackendChoice::Nftables => return Ok(Box::new(NftablesBackend)),
        BackendChoice::Auto => {}
    }

    if let Some(name) = policy_backend {
        if name == "auto" {
            // fall through to detection
        } else if let Some(b) = backend_from_name(name) {
            return Ok(b);
        } else {
            return Err(anyhow!("unsupported backend from policy: {name}"));
        }
    }

    for b in all_backends() {
        if b.detect().await.unwrap_or(false) {
            return backend_from_name(b.name())
                .ok_or_else(|| anyhow!("unsupported backend detected: {}", b.name()));
        }
    }

    Err(anyhow!(
        "no supported firewall backend detected (firewalld or nftables)"
    ))
}

fn backend_from_name(name: &str) -> Option<Box<dyn Backend>> {
    match name {
        "firewalld" => Some(Box::new(FirewalldBackend)),
        "nftables" => Some(Box::new(NftablesBackend)),
        _ => None,
    }
}

async fn build_report(backend: &dyn Backend, policy: &Policy) -> Result<StatusReport> {
    let snap = backend.snapshot().await?;
    let findings = backend.validate(policy, &snap).await?;

    let mut warn = 0u32;
    let mut failed = 0u32;
    for f in &findings {
        match f.severity {
            Overall::Warn => warn += 1,
            Overall::Error => failed += 1,
            Overall::Ok => {}
        }
    }

    let overall = if failed > 0 {
        Overall::Error
    } else if warn > 0 {
        Overall::Warn
    } else {
        Overall::Ok
    };

    Ok(StatusReport {
        schema: 1,
        overall,
        backend: snap.backend_name.to_string(),
        active_profile: "default".into(),
        last_check: Utc::now(),
        summary: Summary {
            checks_total: findings.len() as u32,
            checks_warn: warn,
            checks_failed: failed,
        },
        findings,
    })
}

fn emit_report(cmd: Command, report: StatusReport) -> Result<ExitStatus> {
    match cmd {
        Command::Status { json, one_line } => {
            output_report(&report, json, one_line);
            Ok(report.overall.into())
        }
        Command::Check { json } => {
            if json {
                println!("{}", serde_json::to_string_pretty(&report)?);
            } else {
                println!("{}", report.overall.as_str());
            }
            Ok(report.overall.into())
        }
        Command::Diff => {
            eprintln!(
                "{}",
                report
                    .findings
                    .first()
                    .map(|f| f.msg.as_str())
                    .unwrap_or("diff unavailable")
            );
            Ok(report.overall.into())
        }
        Command::Backend { .. } => unreachable!("handled earlier"),
    }
}

fn output_report(report: &StatusReport, json: bool, one_line: bool) {
    if one_line {
        println!("sentinel:{}:{}", report.backend, report.overall.as_str());
    } else if json {
        println!("{}", serde_json::to_string_pretty(report).unwrap());
    } else {
        print_human_readable(report);
    }
}

fn backend_label(choice: BackendChoice, policy_backend: Option<&str>) -> String {
    match choice {
        BackendChoice::Firewalld => "firewalld".into(),
        BackendChoice::Nftables => "nftables".into(),
        BackendChoice::Auto => policy_backend.unwrap_or("auto").to_string(),
    }
}

fn print_human_readable(report: &StatusReport) {
    println!("backend: {}", report.backend);
    println!("overall: {}", report.overall.as_str());
    println!("last_check: {}", report.last_check.to_rfc3339());
    println!(
        "checks: total={} warn={} failed={}",
        report.summary.checks_total, report.summary.checks_warn, report.summary.checks_failed
    );
    for f in &report.findings {
        println!("- [{}] {}: {}", f.severity.as_str(), f.id, f.msg);
    }
}

fn error_report(backend: &str, id: &str, msg: &str) -> StatusReport {
    StatusReport {
        schema: 1,
        overall: Overall::Error,
        backend: backend.to_string(),
        active_profile: "default".into(),
        last_check: Utc::now(),
        summary: Summary {
            checks_total: 1,
            checks_warn: 0,
            checks_failed: 1,
        },
        findings: vec![crate::status::Finding {
            id: id.into(),
            severity: Overall::Error,
            msg: msg.into(),
        }],
    }
}
