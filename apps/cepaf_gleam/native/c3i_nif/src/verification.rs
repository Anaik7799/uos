//! Verification NIFs — run gleam check and report results.
//!
//! STAMP: SC-VER-001, SC-NIF-001

use rustler::NifResult;
use serde::Serialize;
use std::process::Command;

#[derive(Debug, Serialize)]
struct VerificationResult {
    ok: bool,
    output: String,
    warnings: usize,
    errors: usize,
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn verification_run() -> NifResult<String> {
    // NOTE(20261027-full-integration): resolve the UOS Gleam project first;
    // the old `/home/an/dev/ver/c3i` fallback targeted the stale external C3I
    // tree and mis-scoped `gleam check` when the harness runs from UOS.
    // The fork/wait ECHILD defect is separate — see docs/reviews/
    // 20261027-1830-verification-run-nif-diagnosis.md; a governed rebuild must
    // also switch the spawn to posix_spawn/open_port for BEAM-safety.
    let gleam_dir = if std::path::Path::new("lib/cepaf_gleam/gleam.toml").exists() {
        "lib/cepaf_gleam"
    } else if std::path::Path::new("apps/cepaf_gleam/gleam.toml").exists() {
        "apps/cepaf_gleam"
    } else if std::path::Path::new("gleam.toml").exists() {
        "."
    } else if std::path::Path::new("/home/an/NAS-setup/uos/apps/cepaf_gleam/gleam.toml").exists() {
        "/home/an/NAS-setup/uos/apps/cepaf_gleam"
    } else {
        "/home/an/dev/ver/c3i/lib/cepaf_gleam"
    };

    use std::io::Read;
    use std::process::Stdio;
    let spawn_res = Command::new("gleam")
        .arg("check")
        .current_dir(gleam_dir)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn();

    match spawn_res {
        Ok(mut child) => {
            let mut stdout = String::new();
            let mut stderr = String::new();
            if let Some(mut out_pipe) = child.stdout.take() {
                let _ = out_pipe.read_to_string(&mut stdout);
            }
            if let Some(mut err_pipe) = child.stderr.take() {
                let _ = err_pipe.read_to_string(&mut stderr);
            }
            let combined = format!("{}\n{}", stdout, stderr);
            let warnings = combined.matches("warning:").count();
            let errors = combined.matches("error:").count();
            let wait_ok = match child.wait() {
                Ok(status) => status.success(),
                Err(e) if e.raw_os_error() == Some(10) => errors == 0,
                Err(_) => false,
            };
            let data = VerificationResult {
                ok: wait_ok && errors == 0,
                output: combined.chars().take(2000).collect(),
                warnings,
                errors,
            };
            Ok(serde_json::to_string(&data).unwrap_or_else(|_| "{}".into()))
        }
        Err(e) => {
            let data = VerificationResult {
                ok: false,
                output: format!("Failed to run gleam check: {}", e),
                warnings: 0,
                errors: 1,
            };
            Ok(serde_json::to_string(&data).unwrap_or_else(|_| "{}".into()))
        }
    }
}
