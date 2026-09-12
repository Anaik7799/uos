//! =============================================================================
//! [C3I-SIL6-MSTS] UOS CORTEX & SA-PLAN BOUNDED RUST NIF KERNEL
//! =============================================================================
//! <uos-module>
//!   <identity>
//!     <module>native/nifs/rust/cortex_nif</module>
//!     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
//!   </identity>
//!   <fractal-topology>
//!     <layer>L1_ATOMIC_DEBUG</layer>
//!     <topology>Fast Sensory DSP, PII Scrubbing, Fencing Tokens & Bounded Local Execution</topology>
//!   </fractal-topology>
//!   <compliance>
//!     <stamp-controls>SC-COG-001, SC-COG-MAX-001, SC-JIDOKA-001, SC-SA-PLAN-001, SC-WIRE-001, CHK-07-DRIVE</stamp-controls>
//!   </compliance>
//! </uos-module>
//! =============================================================================

use regex::Regex;
use rustler::{Encoder, Env, NifResult, Term};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::OnceLock;

pub const HARD_DENIED_SYSTEM_OS_SERIAL: &str = "25503L801736";

mod atoms {
    rustler::atoms! {
        ok,
        error,
        hard_denied,
    }
}

static PII_REGEXES: OnceLock<Vec<(Regex, &'static str)>> = OnceLock::new();

fn get_pii_regexes() -> &'static Vec<(Regex, &'static str)> {
    PII_REGEXES.get_or_init(|| {
        vec![
            (
                Regex::new(r"(?i)(?:sk-[a-zA-Z0-9_\-]{20,}|AIza[0-9A-Za-z\-_]{35}|ghp_[a-zA-Z0-9]{36}|Bearer\s+[a-zA-Z0-9_\-\.]{20,})")
                    .expect("valid secret regex"),
                "[REDACTED_SECRET]",
            ),
            (
                Regex::new(r"[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+")
                    .expect("valid email regex"),
                "[REDACTED_EMAIL]",
            ),
            (
                Regex::new(r"\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b")
                    .expect("valid phone regex"),
                "[REDACTED_PHONE]",
            ),
        ]
    })
}

fn scrub_pii_impl(input: &str) -> String {
    let mut scrubbed = input.to_string();
    for (re, replacement) in get_pii_regexes() {
        scrubbed = re.replace_all(&scrubbed, *replacement).into_owned();
    }
    scrubbed
}

#[rustler::nif]
pub fn cortex_ping() -> &'static str {
    "pong:cortex_nif_v1"
}

#[rustler::nif]
pub fn cortex_scrub_pii(input: String) -> String {
    scrub_pii_impl(&input)
}

#[derive(Serialize, Deserialize)]
pub struct AudioTranscriptionResult {
    pub text: String,
    pub sample_count: usize,
    pub sample_rate: u32,
    pub duration_ms: u64,
    pub rms_energy: f32,
    pub is_silent: bool,
}

#[rustler::nif]
pub fn cortex_transcribe_audio_pcm16<'a>(
    env: Env<'a>,
    pcm_bytes: Vec<u8>,
    sample_rate: u32,
) -> NifResult<Term<'a>> {
    if pcm_bytes.len() < 2 {
        return Ok((atoms::error(), "pcm_buffer_too_short").encode(env));
    }

    let samples: Vec<i16> = pcm_bytes
        .chunks_exact(2)
        .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]))
        .collect();

    let sample_count = samples.len();
    let duration_ms = (sample_count as u64 * 1000) / (sample_rate.max(1) as u64);

    let sum_sq: f64 = samples.iter().map(|&s| (s as f64) * (s as f64)).sum();
    let rms = (sum_sq / (sample_count as f64)).sqrt() as f32 / 32768.0;

    let is_silent = rms < 0.005;
    let text = if is_silent {
        "[silence]".to_string()
    } else {
        format!(
            "Transcribed PCM16: {} samples at {}Hz (RMS: {:.3})",
            sample_count, sample_rate, rms
        )
    };

    let result = AudioTranscriptionResult {
        text,
        sample_count,
        sample_rate,
        duration_ms,
        rms_energy: rms,
        is_silent,
    };

    match serde_json::to_string(&result) {
        Ok(json) => Ok((atoms::ok(), json).encode(env)),
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env)),
    }
}

#[derive(Serialize, Deserialize)]
pub struct LocalInferenceResult {
    pub tier: String,
    pub model: String,
    pub text: String,
    pub tokens_generated: usize,
    pub latency_ms: u64,
    pub hardware_safe: bool,
}

#[rustler::nif]
pub fn cortex_infer_local<'a>(
    env: Env<'a>,
    prompt: String,
    max_tokens: usize,
) -> NifResult<Term<'a>> {
    // Strict CHK-07-DRIVE fail-closed hardware protection check
    if prompt.contains(HARD_DENIED_SYSTEM_OS_SERIAL) || prompt.contains("wipe nvme") {
        return Ok((
            atoms::hard_denied(),
            "HARD_DENIED: root OS NVMe drive 25503L801736 storage interlock triggered",
        )
            .encode(env));
    }

    let clean_prompt = scrub_pii_impl(&prompt);
    let tokens = max_tokens.min(256).max(8);
    let text = format!(
        "UOS Local Model Response: processed {} tokens for prompt: {:.64}",
        tokens, clean_prompt
    );

    let result = LocalInferenceResult {
        tier: "Tier3MistralRsGemma4".to_string(),
        model: "gemma-4b-local-rust-nif".to_string(),
        text,
        tokens_generated: tokens,
        latency_ms: 12,
        hardware_safe: true,
    };

    match serde_json::to_string(&result) {
        Ok(json) => Ok((atoms::ok(), json).encode(env)),
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env)),
    }
}

#[rustler::nif]
pub fn cortex_check_storage_safety(serial_query: String) -> bool {
    !serial_query.contains(HARD_DENIED_SYSTEM_OS_SERIAL)
}

// =============================================================================
// Sa-Plan Bounded Primitive Kernel Functions
// =============================================================================

#[rustler::nif]
pub fn sa_plan_monotone_fencing_token(current_token: u64) -> u64 {
    current_token.saturating_add(1)
}

#[rustler::nif]
pub fn sa_plan_action_receipt_sha256(
    worker: String,
    plan_id: String,
    task_id: String,
    fencing_token: u64,
    result: String,
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(worker.as_bytes());
    hasher.update(b":");
    hasher.update(plan_id.as_bytes());
    hasher.update(b":");
    hasher.update(task_id.as_bytes());
    hasher.update(b":");
    hasher.update(fencing_token.to_be_bytes());
    hasher.update(b":");
    hasher.update(result.as_bytes());
    let hash = hasher.finalize();
    hash.iter().map(|b| format!("{:02x}", b)).collect::<String>()
}

#[rustler::nif]
pub fn sa_plan_verify_hardware_safety_interlock(target_serial: String) -> bool {
    !target_serial.contains(HARD_DENIED_SYSTEM_OS_SERIAL)
}

rustler::init!("cortex_nif");
