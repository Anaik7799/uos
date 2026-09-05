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
    let gleam_dir = if std::path::Path::new("lib/cepaf_gleam/gleam.toml").exists() {
        "lib/cepaf_gleam"
    } else if std::path::Path::new("gleam.toml").exists() {
        "."
    } else {
        "/home/an/dev/ver/c3i/lib/cepaf_gleam"
    };

    let output = Command::new("gleam")
        .arg("check")
        .current_dir(gleam_dir)
        .output();

    match output {
        Ok(out) => {
            let stdout = String::from_utf8_lossy(&out.stdout).to_string();
            let stderr = String::from_utf8_lossy(&out.stderr).to_string();
            let combined = format!("{}\n{}", stdout, stderr);
            let warnings = combined.matches("warning:").count();
            let errors = combined.matches("error:").count();
            let data = VerificationResult {
                ok: out.status.success(),
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
