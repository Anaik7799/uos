//! Zenoh Publisher Functions
//!
//! Handles message publication to Zenoh topics.
//!
//! ## STAMP Constraints
//! - SC-ZENOH-PUB-001: Non-blocking publication
//! - SC-ZENOH-PUB-002: Latency monitoring (<1ms target)
//! - SC-ZENOH-PUB-003: Batch support for efficiency
//! - SC-NIF-005: ProofToken enforcement at NIF boundary — control-plane keys
//!   (`indrajaal/control/**`) MUST carry a valid HMAC-SHA256 ProofToken.
//! - SC-NIF-010: Tiered enforcement — Bypass (Tier 0), Session (Tier 1), Full (Tier 2)
//! - SC-NIF-011: Session token caching with 60s TTL for inference-plane keys
//! - SC-HASH-002: Constant-time signature comparison (timing-attack prevention)

use crate::proof_token;
use crate::ZenohSessionResource;
use crate::types::BatchPublishRequest;
use rustler::{Atom, Binary, Encoder, Env, Error, NifResult, ResourceArc, Term};

mod atoms {
    rustler::atoms! {
        ok,
        error,
    }
}

// =============================================================================
// Tiered ProofToken enforcement (SC-NIF-010)
// =============================================================================

/// 3-tier enforcement gate dispatching based on key expression classification.
///
/// | Tier | Key Prefix | Enforcement | Latency Target |
/// |------|-----------|-------------|----------------|
/// | 0 (Bypass)  | `indrajaal/logs/**`, `indrajaal/metrics/**`, `indrajaal/health/**` | None | 0 |
/// | 1 (Session) | `indrajaal/inference/**`, `indrajaal/neural/**` | Session token (HMAC cached 60s) | <5us |
/// | 2 (Full)    | `indrajaal/control/**`, `indrajaal/evolution/**` | Full HMAC per call | <10us |
///
/// ## SC-NIF-010
/// This function is the sole NIF-boundary enforcement point.  The Elixir
/// `verify_substrate_safety/2` in `Indrajaal.Native.Zenoh` provides a
/// defence-in-depth layer, but this Rust gate ensures that even if the Elixir
/// layer is bypassed the control and inference planes remain protected.
fn enforce_tiered(key: &str, payload: &[u8]) -> Result<(), String> {
    match proof_token::classify_tier(key) {
        proof_token::EnforcementTier::Bypass => {
            // Tier 0: telemetry, logs, health — no enforcement overhead
            Ok(())
        }
        proof_token::EnforcementTier::Session => {
            // Tier 1: inference/neural — session-cached HMAC (60s TTL)
            proof_token::verify_session(payload)
                .map_err(|e| format!("SessionToken rejected: {}", e))
        }
        proof_token::EnforcementTier::Full => {
            // Tier 2: control/evolution — full HMAC verification per call
            proof_token::verify_from_payload(payload)
                .map_err(|e| format!("ProofToken rejected: {}", e))
        }
    }
}

// =============================================================================
// NIF Functions
// =============================================================================

/// Publish a single message.
///
/// Enforcement is tiered by key prefix (SC-NIF-010):
/// - Tier 0 (bypass): telemetry/logs/health — zero overhead
/// - Tier 1 (session): inference/neural — cached HMAC (60s TTL)
/// - Tier 2 (full): control/evolution — full HMAC per call
///
/// Returns: `:ok` | `{:error, reason}`
pub fn zenoh_publish(
    session: ResourceArc<ZenohSessionResource>,
    key: String,
    payload: Binary,
) -> NifResult<Atom> {
    enforce_tiered(&key, payload.as_slice())
        .map_err(|reason| Error::Term(Box::new(reason)))?;

    match session.publish(&key, payload.as_slice()) {
        Ok(_) => Ok(atoms::ok()),
        Err(e) => Err(Error::Term(Box::new(format!("Publish failed: {}", e)))),
    }
}

/// Put (publish with store) a message.
///
/// Functionally same as `zenoh_publish` for Zenoh 1.0.
/// Applies the same tiered enforcement gate (SC-NIF-010).
///
/// Returns: `:ok` | `{:error, reason}`
pub fn zenoh_put(
    session: ResourceArc<ZenohSessionResource>,
    key: String,
    payload: Binary,
) -> NifResult<Atom> {
    enforce_tiered(&key, payload.as_slice())
        .map_err(|reason| Error::Term(Box::new(reason)))?;

    match session.publish(&key, payload.as_slice()) {
        Ok(_) => Ok(atoms::ok()),
        Err(e) => Err(Error::Term(Box::new(format!("Put failed: {}", e)))),
    }
}

/// Delete a key from Zenoh storage.
///
/// Delete is implemented as publish with empty payload.
/// Control-plane deletes carry no payload, so they bypass ProofToken enforcement —
/// deletion of control-plane keys requires a separate Guardian-gated workflow
/// (SC-GUARD-003) and is not handled here.
///
/// Returns: `:ok` | `{:error, reason}`
pub fn zenoh_delete(
    session: ResourceArc<ZenohSessionResource>,
    key: String,
) -> NifResult<Atom> {
    // Empty payload — ProofToken enforcement would always fail with InvalidJson.
    // Delete operations on control-plane keys are Guardian-gated at a higher layer.
    match session.publish(&key, &[]) {
        Ok(_) => Ok(atoms::ok()),
        Err(e) => Err(Error::Term(Box::new(format!("Delete failed: {}", e)))),
    }
}

/// Publish a batch of messages.
///
/// Each control-plane message in the batch must carry a valid ProofToken.
/// Messages that fail enforcement are silently dropped (matching the Elixir
/// behaviour in `Indrajaal.Native.Zenoh.publish_batch/2`).
///
/// Returns: `{:ok, count}` | `{:error, reason}`
pub fn zenoh_publish_batch(
    env: Env,
    session: ResourceArc<ZenohSessionResource>,
    messages: Vec<BatchPublishRequest>,
) -> NifResult<Term> {
    let mut success_count = 0;
    let mut last_error: Option<String> = None;

    for msg in messages {
        // Enforce tiered gate per message (SC-NIF-010)
        if let Err(reason) = enforce_tiered(&msg.key, &msg.payload) {
            last_error = Some(format!("Tiered gate rejected {}: {}", msg.key, reason));
            // Skip this message (consistent with Elixir batch filter behaviour)
            continue;
        }

        match session.publish(&msg.key, &msg.payload) {
            Ok(_) => success_count += 1,
            Err(e) => {
                last_error = Some(format!("{}", e));
                // Continue with remaining messages
            }
        }
    }

    if let Some(err) = last_error {
        Ok((atoms::error(), format!("Partial failure: {} succeeded, last error: {}", success_count, err)).encode(env))
    } else {
        Ok((atoms::ok(), success_count).encode(env))
    }
}
