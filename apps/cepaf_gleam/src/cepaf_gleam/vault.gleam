//// Vault — typed Gleam wrapper around `rusty_vault_nif`.
////
//// SC-VAULT-003: All secret reads MUST go through this module.
//// SC-VAULT-013: Secret policy MUST be in `secret_policy` table; no hard-coded TTLs.
////
//// Per .claude/rules/secrets-vault.md.
////
//// SLICE B SKELETON — NIF FFI wired up but body parsing deferred to Slice B
//// continuation. Compileable; emits typed errors; does not yet read real
//// secrets from RustyVault::core.

// =====================================================================
// Types
// =====================================================================

/// Opaque handle to a vault instance. Created by `init/2`, passed to all ops.
pub type VaultHandle

/// Sensitivity tier — used to gate L0 rotations behind Guardian 2oo3 (SC-SIL4-006).
pub type Sensitivity {
  L0
  L3
  L7
}

/// Secret policy. MUST be supplied on every `put`. Stored alongside ciphertext.
pub type SecretPolicy {
  SecretPolicy(
    ttl: Int,
    max_ttl: Int,
    rotation_days: Int,
    sensitivity: Sensitivity,
  )
}

/// Returned by `put` — version metadata for the operator dashboard / sync actor.
pub type VersionInfo {
  VersionInfo(version: Int, lease_id: String)
}

/// Vault state machine (mirrors VaultState enum in lib.rs).
pub type VaultState {
  Sealed
  Unsealing
  Active
  Sealing
  Corrupt
  Halted
}

/// Errors. Exhaustive — every NIF response maps to one of these.
pub type VaultError {
  VaultSealed
  WrongKey
  NotFound(name: String)
  TtlExpired(name: String)
  StorageError(reason: String)
  AlreadyUnsealed
  NifPanic(reason: String)
}

// =====================================================================
// Default policies (operator-tunable per-secret via secret_policy table)
// Per fractal-criticality-matrix.md and plan §4.
// =====================================================================

pub fn policy_l0_hot_key() -> SecretPolicy {
  // Anthropic, OpenRouter, Gemini — 5min TTL, 7d MaxTTL, 30d rotation
  SecretPolicy(ttl: 300, max_ttl: 604_800, rotation_days: 30, sensitivity: L0)
}

pub fn policy_l3_oauth_refresh() -> SecretPolicy {
  // google_oauth_refresh — 1h TTL, 7d MaxTTL, refresh-on-use
  SecretPolicy(ttl: 3600, max_ttl: 604_800, rotation_days: 365, sensitivity: L3)
}

pub fn policy_l3_smtp() -> SecretPolicy {
  // gmail_app_password — 6h TTL, 30d MaxTTL, 90d rotation
  SecretPolicy(
    ttl: 21_600,
    max_ttl: 2_592_000,
    rotation_days: 90,
    sensitivity: L3,
  )
}

pub fn policy_l7_gateway() -> SecretPolicy {
  // telegram_token — 1h TTL, 30d MaxTTL, 365d rotation
  SecretPolicy(
    ttl: 3600,
    max_ttl: 2_592_000,
    rotation_days: 365,
    sensitivity: L7,
  )
}

// =====================================================================
// Public API stubs (Slice B continuation will wire to ffi_*)
// =====================================================================

/// Initialize a sealed vault. Storage and audit paths are absolute filesystem
/// paths under `sub-projects/c3i/data/kms/` (per operator amendment §31).
pub fn init(
  _storage_path: String,
  _audit_path: String,
) -> Result(VaultHandle, VaultError) {
  // TODO Slice B continuation: ffi_init + decode resource arc
  Error(StorageError("vault.init not yet wired (Slice B in progress)"))
}

/// Unseal — Sealed → Active. Master key must be exactly 32 bytes (AES-256).
pub fn unseal(
  _handle: VaultHandle,
  _master_key: BitArray,
) -> Result(Nil, VaultError) {
  // TODO Slice B continuation: ffi_unseal + parse result
  Error(StorageError("vault.unseal not yet wired (Slice B in progress)"))
}

/// Seal — Active → Sealed. Master key zeroized in RAM (SC-VAULT-002).
pub fn seal(_handle: VaultHandle) -> Result(Nil, VaultError) {
  Error(StorageError("vault.seal not yet wired (Slice B in progress)"))
}

/// Query vault state.
pub fn status(_handle: VaultHandle) -> VaultState {
  Sealed
}

/// Write a secret with policy. Per SC-VAULT-013, callers MUST supply explicit
/// policy — no defaults inside this module's get/put surface.
///
/// Pass-3 wiring: delegates to `:rusty_vault_nif.vault_kv_put/5`. Maps the NIF
/// `{:ok, %{version, lease_id}}` / `{:error, :sealed | :storage_error |
/// :ttl_expired}` shape into typed `VersionInfo` / `VaultError`.
pub fn put(
  handle: VaultHandle,
  name: String,
  value: BitArray,
  policy: SecretPolicy,
) -> Result(VersionInfo, VaultError) {
  case nif_kv_put(handle, name, value, policy.ttl, policy.max_ttl) {
    NifPutOk(version, lease_id) ->
      Ok(VersionInfo(version: version, lease_id: lease_id))
    NifPutSealed -> Error(VaultSealed)
    NifPutStorageError ->
      Error(StorageError(
        "rusty_vault_nif vault_kv_put rejected (empty value or store lock)",
      ))
    NifPutTtlExpired -> Error(TtlExpired(name: name))
    NifPutOther(reason) -> Error(StorageError(reason))
  }
}

/// Internal NIF result shape — narrows the dynamic Erlang term into a typed
/// Gleam ADT so downstream pattern matching is exhaustive.
type NifPutResult {
  NifPutOk(version: Int, lease_id: String)
  NifPutSealed
  NifPutStorageError
  NifPutTtlExpired
  NifPutOther(reason: String)
}

@external(erlang, "rusty_vault_safe", "vault_kv_put")
fn nif_kv_put(
  handle: VaultHandle,
  name: String,
  value: BitArray,
  ttl_sec: Int,
  max_ttl_sec: Int,
) -> NifPutResult

/// Read latest version of a secret.
///
/// SC-VAULT-005: hot path — never makes network calls.
/// SC-VAULT-006: returns `TtlExpired(name)` if `now - fetched_at >= max_ttl`.
pub fn get(_handle: VaultHandle, name: String) -> Result(BitArray, VaultError) {
  Error(NotFound(name: name))
}

/// Hard-delete a specific version of a secret.
pub fn destroy(
  _handle: VaultHandle,
  _name: String,
  _version: Int,
) -> Result(Nil, VaultError) {
  Error(StorageError("vault.destroy not yet wired (Slice B in progress)"))
}

/// Renew a lease. SC-VAULT-014: callers should renew when expiry - now < 60s.
pub fn lease_renew(
  _handle: VaultHandle,
  _lease_id: String,
  _ttl_sec: Int,
) -> Result(Int, VaultError) {
  Error(StorageError("vault.lease_renew not yet wired (Slice B in progress)"))
}

// =====================================================================
// Pure freshness classifier (Slice F — Andon dashboard tile + RETE-UL)
//
// SC-VAULT-006: hard-stale (age >= max_ttl) MUST fail-closed.
// Used by:
//   - ui/lustre/secrets_vault.gleam (color tile)
//   - ui/wisp/secret_api.gleam (status JSON)
//   - rules/engine.gleam secret_freshness_rules (RETE-UL)
//   - rules/engine.gleam vault_integrity_rules (offline gate)
//
// This is intentionally a free function (no NIF dependency) so it is
// exhaustively unit-testable and reused by all 4 callers without drift.
// =====================================================================

/// Freshness classification of a secret given the current clock.
pub type Freshness {
  /// age < ttl — hot path, no action
  Fresh
  /// ttl ≤ age < max_ttl AND online — trigger background sync
  SoftStale
  /// ttl ≤ age < max_ttl AND offline — degraded mode, dashboard amber
  SoftStaleOffline
  /// age ≥ max_ttl — FAIL-CLOSED (SC-VAULT-006)
  HardStale
}

/// Pure classifier. Returns `Freshness` from clock + fetched_at + policy + online flag.
///
/// Boundaries (per `secret_freshness_rules` salience 100 / 95 / 90 / 100):
///   age < ttl                       → Fresh
///   ttl ≤ age < max_ttl ∧ online    → SoftStale
///   ttl ≤ age < max_ttl ∧ ¬online   → SoftStaleOffline
///   age ≥ max_ttl                   → HardStale (regardless of online)
///
/// Panics-free: negative ages clamp to 0 (clock skew tolerance).
pub fn classify_freshness(
  now_seconds: Int,
  fetched_at_seconds: Int,
  policy: SecretPolicy,
  online: Bool,
) -> Freshness {
  let raw_age = now_seconds - fetched_at_seconds
  let age = case raw_age < 0 {
    True -> 0
    False -> raw_age
  }
  case age >= policy.max_ttl, age >= policy.ttl, online {
    True, _, _ -> HardStale
    False, True, True -> SoftStale
    False, True, False -> SoftStaleOffline
    False, False, _ -> Fresh
  }
}

/// Aggregate dashboard color from per-secret freshness counts + vault state.
/// SC-VAULT-006: any HardStale → red. Any SoftStale (online or offline) → amber.
/// All Fresh + Active vault → green. Sealed/Corrupt/Halted → red regardless.
pub fn dashboard_color(
  fresh_count: Int,
  soft_stale_count: Int,
  hard_stale_count: Int,
  vault_state: VaultState,
) -> String {
  let _ = fresh_count
  case vault_state, hard_stale_count, soft_stale_count {
    Active, 0, 0 -> "green"
    Active, 0, _ -> "amber"
    Active, _, _ -> "red"
    _, _, _ -> "red"
  }
}
