//// Vault Zenoh topic catalog — discoverable namespace for vault operations.
////
//// SC-VAULT-009 (every NIF call emits Zenoh envelope) requires a known,
//// stable topic family that AI agents and external observers can subscribe
//// to without guessing.
////
//// Per ZK [zk-c065c63bc60c618a] MCP-via-Zenoh pattern + [zk-bb4de67d97f807ac]
//// consult-the-running-system anti-pattern (no selector guessing).
////
//// Used by:
////   - rusty_vault_nif on every NIF call (emit envelope)
////   - vault_sync_actor on each sync cycle
////   - operator dashboard (subscribe for live tile updates)
////   - audit reconciliation cron (replay audit topics)
////   - cross-mesh federation (SC-CPIG-FED) for distributed vault state

// =====================================================================
// Topic prefixes (per fractal layer)
// =====================================================================

/// L0 Constitutional — secret access events (every vault.get/put fires here)
pub const l0_secret_access_prefix: String = "indrajaal/l0/secret/access/"

/// L0 Constitutional — secret expired (hard-stale, fail-closed)
pub const l0_secret_expired_prefix: String = "indrajaal/l0/secret/expired/"

/// L0 Constitutional — vault unseal failed (P0)
pub const l0_unseal_failed: String = "indrajaal/l0/secret/unseal_failed"

/// L0 Constitutional — KEK chain attempt audit
pub const l0_kek_attempt_prefix: String = "indrajaal/l0/secret/kek_attempt/"

/// L1 Atomic / NIF — per-NIF-call timing + result
pub const l1_nif_call_prefix: String = "indrajaal/l1/atomic/vault/"

/// L3 Transaction — KV operations (put/get/destroy)
pub const l3_kv_op_prefix: String = "indrajaal/l3/txn/vault/"

/// L4 System — sync actor outcomes (per 5-min tick)
pub const l4_sync_prefix: String = "indrajaal/l4/sync/vault/"

/// L4 System — Cloud KMS DR fallback events
pub const l4_kms_dr_prefix: String = "indrajaal/l4/system/kms_dr/"

/// L5 Cognitive — RETE-UL rule firings (secret_freshness + vault_integrity)
pub const l5_rule_fire_prefix: String = "indrajaal/l5/cog/vault_rule/"

/// L6 Ecosystem — version vector + mesh-wide consistency
pub const l6_version_prefix: String = "indrajaal/l6/eco/vault/version/"

/// L7 Federation — cross-mesh attestation (Ed25519-signed leases)
pub const l7_attest_prefix: String = "indrajaal/l7/fed/vault/attest/"

/// MoZ (MCP-over-Zenoh) — request/response for vault tools
pub const moz_req_prefix: String = "indrajaal/mcp/req/vault/"

pub const moz_res_prefix: String = "indrajaal/mcp/res/"

// =====================================================================
// Topic builders (avoid string concatenation in callers)
// =====================================================================

pub fn topic_secret_access(name: String) -> String {
  l0_secret_access_prefix <> name
}

pub fn topic_secret_expired(name: String) -> String {
  l0_secret_expired_prefix <> name
}

pub fn topic_kek_attempt(source: String) -> String {
  // source ∈ {"tpm","passphrase","kms"}
  l0_kek_attempt_prefix <> source
}

pub fn topic_nif_call(op: String) -> String {
  // op ∈ {"init","unseal","seal","kv_put","kv_get",...}
  l1_nif_call_prefix <> op
}

pub fn topic_kv_op(op: String) -> String {
  l3_kv_op_prefix <> op
}

pub fn topic_sync(run_id: String) -> String {
  l4_sync_prefix <> run_id
}

pub fn topic_rule_fire(rule_name: String) -> String {
  l5_rule_fire_prefix <> rule_name
}

pub fn topic_version(secret_name: String) -> String {
  l6_version_prefix <> secret_name
}

pub fn topic_attest(mesh_id: String) -> String {
  l7_attest_prefix <> mesh_id
}

pub fn topic_moz_req(tool: String, request_id: String) -> String {
  moz_req_prefix <> tool <> "/" <> request_id
}

pub fn topic_moz_res(request_id: String) -> String {
  moz_res_prefix <> request_id
}

// =====================================================================
// Discovery glob patterns (for subscribers)
// =====================================================================

/// Subscribe to all vault events (omnibus subscriber)
pub const all_vault_events: String = "indrajaal/**/vault/**"

/// Subscribe to all secret access events (audit log consumers)
pub const all_secret_access: String = "indrajaal/l0/secret/access/**"

/// Subscribe to all P0 vault alarms (operator notification)
pub const all_p0_alarms: String = "indrajaal/l0/secret/{expired,unseal_failed}/**"

/// Subscribe to all sync events (federation peers)
pub const all_sync_events: String = "indrajaal/l4/sync/vault/**"

/// Subscribe to all MoZ vault requests (cross-mesh tool invocation)
pub const all_moz_vault_req: String = "indrajaal/mcp/req/vault/**"

// =====================================================================
// MoZ tool surface (what cross-mesh agents invoke)
// =====================================================================

/// 5 vault MCP tools registered Pass-8 in mcp/tools.gleam.
/// Mirrored here for MoZ discovery: agents publish to
/// indrajaal/mcp/req/vault/<tool>/<id> and listen on indrajaal/mcp/res/<id>.
pub const moz_tools: List(String) = [
  "vault_status",
  "vault_list_secrets",
  "vault_policy_get",
  "vault_audit_tail",
  "vault_health",
]
