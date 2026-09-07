//! Audit-span emission for every IAM write operation.
//!
//! Phase 1: stub that writes a tracing event. Phase 2+ wires this into the
//! existing `c3i_nif::zenoh_nif` publisher so spans land on
//! `indrajaal/l0/iam/{action}`.
//!
//! SC-FERRISKEY-NIF-006 — every write NIF emits an audit span.
//! SC-GCP-IAM audit family — Cloud Audit Logs export rides on the same span.

use serde_json::Value;
use tracing::info;

/// Emit an audit event. Phase 1 implementation only writes to the local
/// `tracing` subscriber; Phase 2 will additionally publish to Zenoh.
pub fn emit(action: &str, payload: &Value) {
    info!(target: "ferriskey_nif::audit", action = action, payload = %payload);
}
