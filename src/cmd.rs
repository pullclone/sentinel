use anyhow::{Context, Result};
use std::time::{Duration, Instant};
use tokio::{process::Command, time};

pub async fn run_timeout(
    program: &str,
    args: &[&str],
    timeout_ms: u64,
) -> Result<(i32, String, String)> {
    let mut cmd = Command::new(program);
    cmd.args(args);

    let mut child = cmd
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .with_context(|| format!("failed to spawn: {program}"))?;

    let deadline = Instant::now() + Duration::from_millis(timeout_ms);

    loop {
        if let Some(_status) = child.try_wait()? {
            let out = child
                .wait_with_output()
                .await
                .context("failed to collect command output")?;
            let code = out.status.code().unwrap_or(2);
            let stdout = String::from_utf8_lossy(&out.stdout).to_string();
            let stderr = String::from_utf8_lossy(&out.stderr).to_string();
            return Ok((code, stdout, stderr));
        }

        if Instant::now() >= deadline {
            let _ = child.start_kill();
            let _ = child.wait().await;
            anyhow::bail!("command timed out: {program} {args:?}");
        }

        time::sleep(Duration::from_millis(25)).await;
    }
}
