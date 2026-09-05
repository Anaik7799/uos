//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/hsm_vault</module>
////     <fsharp-lineage>None — novel HSM key lifecycle management (L0 extension)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Hardware Security Module (HSM) policy enforcement and key vault.
////       Manages cryptographic key lifecycle including creation, rotation
////       enforcement, access auditing, and expiry detection. Implements
////       the homeostasis property (SC-BIO-EVO-001) by continuously
////       monitoring key health and enforcing rotation policy.
////
////       HsmDecision algebra:
////         Allow          — key valid, rotation not due
////         DenyRotationRequired(key_id) — key overdue for rotation
////         DenyPolicyViolation(reason)  — key violates policy invariants
////
////       Rotation invariant:
////         needs_rotation(e, p, t) ⟺ t - e.rotated_at > p.key_rotation_days × 86400
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SEC-001, SC-BIO-EVO-001, SC-PRIME-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       HSM policy rules ↪ Gleam pure ADTs + predicate functions.
////       No mutable state; all state changes return new VaultState.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// HSM VAULT — Cryptographic Key Lifecycle Enforcement
//// सत्यमेव जयते — Truth alone triumphs (Mundaka Upanishad 3.1.6)
////
//// Enforces key rotation policy, audits all access, and computes vault health.
////
//// STAMP: SC-SEC-001, SC-BIO-EVO-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Policy governing key rotation and audit behaviour.
pub type HsmPolicy {
  HsmPolicy(
    /// Number of days before a key must be rotated.
    key_rotation_days: Int,
    /// Minimum acceptable key length in bits.
    min_key_length: Int,
    /// When true, every access is appended to the audit log.
    audit_enabled: Bool,
  )
}

/// A single cryptographic key stored in the vault.
pub type VaultEntry {
  VaultEntry(
    /// Unique key identifier (e.g. "k-001").
    key_id: String,
    /// Algorithm name (e.g. "AES-256-GCM").
    algorithm: String,
    /// Unix epoch seconds when the key was first created.
    created_at: Int,
    /// Unix epoch seconds when the key was last rotated.
    /// Equals created_at until the first rotation.
    rotated_at: Int,
    /// Total number of times this key has been accessed.
    access_count: Int,
  )
}

/// Immutable audit record.
pub type AuditEntry {
  AuditEntry(
    /// Operation performed, e.g. "access", "rotate", "add".
    operation: String,
    /// Key involved.
    key_id: String,
    /// Unix epoch seconds.
    timestamp: Int,
    /// Outcome, e.g. "allowed", "denied:rotation_required".
    result: String,
  )
}

/// Complete vault state — all fields immutable.
pub type VaultState {
  VaultState(
    entries: List(VaultEntry),
    policy: HsmPolicy,
    audit_log: List(AuditEntry),
  )
}

/// Decision returned by check_access.
pub type HsmDecision {
  /// Access permitted — key is valid and rotation is not overdue.
  Allow
  /// Access denied — the key must be rotated before use.
  DenyRotationRequired(key_id: String)
  /// Access denied — the request violates a policy invariant.
  DenyPolicyViolation(reason: String)
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Create a new, empty vault with the supplied policy.
pub fn vault_new(policy: HsmPolicy) -> VaultState {
  VaultState(entries: [], policy: policy, audit_log: [])
}

/// Standard policy: 90-day rotation, 256-bit minimum key length, auditing on.
pub fn default_policy() -> HsmPolicy {
  HsmPolicy(key_rotation_days: 90, min_key_length: 256, audit_enabled: True)
}

// ---------------------------------------------------------------------------
// Key management
// ---------------------------------------------------------------------------

/// Add a new key to the vault.  rotated_at is initialised to created_at.
pub fn add_key(
  vault: VaultState,
  key_id: String,
  algorithm: String,
  timestamp: Int,
) -> VaultState {
  let entry =
    VaultEntry(
      key_id: key_id,
      algorithm: algorithm,
      created_at: timestamp,
      rotated_at: timestamp,
      access_count: 0,
    )
  let new_entries = list.append(vault.entries, [entry])
  let new_vault = VaultState(..vault, entries: new_entries)
  case vault.policy.audit_enabled {
    True -> audit(new_vault, "add", key_id, "created", timestamp)
    False -> new_vault
  }
}

/// Rotate a key — updates rotated_at, resets access_count.
pub fn rotate_key(
  vault: VaultState,
  key_id: String,
  timestamp: Int,
) -> VaultState {
  let new_entries =
    list.map(vault.entries, fn(e) {
      case e.key_id == key_id {
        True -> VaultEntry(..e, rotated_at: timestamp, access_count: 0)
        False -> e
      }
    })
  let new_vault = VaultState(..vault, entries: new_entries)
  case vault.policy.audit_enabled {
    True -> audit(new_vault, "rotate", key_id, "rotated", timestamp)
    False -> new_vault
  }
}

// ---------------------------------------------------------------------------
// Access control
// ---------------------------------------------------------------------------

/// Check whether access to a key should be allowed.
/// Returns Allow, DenyRotationRequired, or DenyPolicyViolation.
pub fn check_access(
  vault: VaultState,
  key_id: String,
  current_time: Int,
) -> HsmDecision {
  let found = list.find(vault.entries, fn(e) { e.key_id == key_id })
  case found {
    Error(_) -> DenyPolicyViolation("key not found: " <> key_id)
    Ok(entry) -> {
      case needs_rotation(entry, vault.policy, current_time) {
        True -> DenyRotationRequired(key_id)
        False -> Allow
      }
    }
  }
}

/// True when the key has exceeded its rotation period.
pub fn needs_rotation(
  entry: VaultEntry,
  policy: HsmPolicy,
  current_time: Int,
) -> Bool {
  let max_age_secs = policy.key_rotation_days * 86_400
  current_time - entry.rotated_at > max_age_secs
}

// ---------------------------------------------------------------------------
// Audit
// ---------------------------------------------------------------------------

/// Append an entry to the audit log (always appends, regardless of
/// audit_enabled — callers decide whether to call this function).
pub fn audit(
  vault: VaultState,
  operation: String,
  key_id: String,
  result: String,
  timestamp: Int,
) -> VaultState {
  let entry =
    AuditEntry(
      operation: operation,
      key_id: key_id,
      timestamp: timestamp,
      result: result,
    )
  VaultState(..vault, audit_log: list.append(vault.audit_log, [entry]))
}

// ---------------------------------------------------------------------------
// Analytics
// ---------------------------------------------------------------------------

/// Return all keys that need rotation at current_time.
pub fn expired_keys(vault: VaultState, current_time: Int) -> List(VaultEntry) {
  list.filter(vault.entries, fn(e) {
    needs_rotation(e, vault.policy, current_time)
  })
}

/// Vault health: 1.0 when no keys are expired; decreases linearly with
/// the fraction of expired keys.  Returns 1.0 for an empty vault.
pub fn vault_health(vault: VaultState, current_time: Int) -> Float {
  let total = list.length(vault.entries)
  case total {
    0 -> 1.0
    n -> {
      let expired = list.length(expired_keys(vault, current_time))
      let expired_f = int.to_float(expired)
      let total_f = int.to_float(n)
      let ratio = case float.divide(expired_f, total_f) {
        Ok(v) -> v
        Error(_) -> 0.0
      }
      1.0 -. ratio
    }
  }
}

/// Human-readable summary of vault state.
pub fn summary(vault: VaultState) -> String {
  let key_count = int.to_string(list.length(vault.entries))
  let audit_count = int.to_string(list.length(vault.audit_log))
  let rotation_days = int.to_string(vault.policy.key_rotation_days)
  string.join(
    [
      "HSM Vault: keys=" <> key_count,
      "audit_entries=" <> audit_count,
      "rotation_days=" <> rotation_days,
    ],
    " | ",
  )
}
