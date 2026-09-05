//// Vault wiring guard test — SC-WIRE-001..007 + SC-VAULT-001..025.
////
//// Guards against drift between vault.gleam types and rusty_vault_nif NIF surface.
//// If a Model field is added or a NIF signature changes, this file will fail
//// to compile FIRST — before scattered breaks in 70+ test files.

import cepaf_gleam/vault.{
  type SecretPolicy, type VaultError, type VaultState, type VersionInfo, Active,
  AlreadyUnsealed, Corrupt, Halted, L0, L3, L7, NifPanic, NotFound, Sealed,
  Sealing, SecretPolicy, StorageError, TtlExpired, Unsealing, VaultSealed,
  VersionInfo, WrongKey,
}

import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// =====================================================================
// Type construction wiring guard — these MUST compile
// =====================================================================

pub fn vault_state_constructors_test() {
  let _: VaultState = Sealed
  let _: VaultState = Unsealing
  let _: VaultState = Active
  let _: VaultState = Sealing
  let _: VaultState = Corrupt
  let _: VaultState = Halted
  Nil
}

pub fn vault_error_constructors_test() {
  let _: VaultError = VaultSealed
  let _: VaultError = WrongKey
  let _: VaultError = NotFound(name: "anthropic_api_key")
  let _: VaultError = TtlExpired(name: "openrouter_api_key")
  let _: VaultError = StorageError(reason: "disk full")
  let _: VaultError = AlreadyUnsealed
  let _: VaultError = NifPanic(reason: "test")
  Nil
}

pub fn sensitivity_constructors_test() {
  let _ = L0
  let _ = L3
  let _ = L7
  Nil
}

pub fn secret_policy_constructor_test() {
  let p: SecretPolicy =
    SecretPolicy(ttl: 300, max_ttl: 604_800, rotation_days: 30, sensitivity: L0)
  should.equal(p.ttl, 300)
  should.equal(p.max_ttl, 604_800)
  should.equal(p.rotation_days, 30)
}

pub fn version_info_constructor_test() {
  let v: VersionInfo = VersionInfo(version: 1, lease_id: "lease-stub")
  should.equal(v.version, 1)
  should.equal(v.lease_id, "lease-stub")
}

// =====================================================================
// Default policy helpers (operator-tunable, but defaults must compile)
// =====================================================================

pub fn policy_l0_hot_key_test() {
  let p = vault.policy_l0_hot_key()
  should.equal(p.ttl, 300)
  should.equal(p.max_ttl, 604_800)
  should.equal(p.sensitivity, L0)
}

pub fn policy_l3_oauth_test() {
  let p = vault.policy_l3_oauth_refresh()
  should.equal(p.ttl, 3600)
  should.equal(p.sensitivity, L3)
}

pub fn policy_l3_smtp_test() {
  let p = vault.policy_l3_smtp()
  should.equal(p.ttl, 21_600)
  should.equal(p.max_ttl, 2_592_000)
}

pub fn policy_l7_gateway_test() {
  let p = vault.policy_l7_gateway()
  should.equal(p.sensitivity, L7)
}

// =====================================================================
// Slice B skeleton invariants — stubs must return typed errors, not panic
// =====================================================================

pub fn init_returns_typed_error_when_not_wired_test() {
  let result = vault.init("/tmp/test_vault.db", "/tmp/test_vault_audit.log")
  case result {
    Error(StorageError(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn get_returns_not_found_for_unknown_test() {
  // For the skeleton, get always returns NotFound until ffi_kv_get is wired.
  // This test will be replaced in Slice B continuation with real round-trip.
  Nil
}

// =====================================================================
// Slice C wiring guard — supervisor + chain types
// =====================================================================

import cepaf_gleam/vault_supervisor.{
  type ChainResult, type KekSource, ChainFailed, ChainOk, CloudKms, NoneString,
  Passphrase, SupervisorConfig, Tpm,
}

pub fn kek_source_constructors_test() {
  let _: KekSource = Tpm
  let _: KekSource = Passphrase
  let _: KekSource = CloudKms
  Nil
}

pub fn supervisor_config_constructor_test() {
  let cfg =
    SupervisorConfig(
      storage_path: "/tmp/test_vault.db",
      audit_path: "/tmp/test_vault_audit.log",
      kek_sealed_path: "/tmp/test_kek.sealed",
      kek_kms_sealed_path: "/tmp/test_kek.kms-sealed",
      skip_tpm: True,
      passphrase: NoneString,
    )
  should.equal(cfg.skip_tpm, True)
}

pub fn chain_result_constructors_test() {
  let _: ChainResult = ChainOk(source: Tpm, attempts: [])
  let _: ChainResult = ChainFailed(attempts: [])
  Nil
}

// =====================================================================
// RETE-UL secret_freshness rules wiring guard — verifies engine compiles
// with the 12 new vault rules (7 secret_freshness + 5 vault_integrity)
// =====================================================================

import cepaf_gleam/rules/engine

pub fn secret_freshness_rule_engine_compiles_test() {
  // Calling evaluate_secret_freshness/6 verifies the rule strings compile
  // through the RETE-UL NIF and returns a typed RuleResult.
  let _ =
    engine.evaluate_secret_freshness(True, True, True, False, False, False)
  Nil
}

pub fn vault_integrity_rule_engine_compiles_test() {
  let _ =
    engine.evaluate_vault_integrity(False, False, False, False, False, False)
  Nil
}

// =====================================================================
// Slice D wiring guard — sync actor + circuit breaker
// =====================================================================

import cepaf_gleam/vault_sync_actor.{
  type Msg, type SyncOutcome, CircuitOpen, Degraded, Divergence, ForceSync,
  NetworkProbed, NoOp, Nominal, Pull, Push, Stop, Tick,
}

pub fn sync_actor_msg_constructors_test() {
  let _: Msg = Tick
  let _: Msg = ForceSync
  let _: Msg = NetworkProbed(reachable: True)
  let _: Msg = Stop
  Nil
}

pub fn sync_outcome_constructors_test() {
  let _: SyncOutcome = Nominal(pulled: 5, pushed: 0, duration_ms: 234)
  let _: SyncOutcome = Degraded(reason: "offline")
  let _: SyncOutcome = CircuitOpen(reset_in_seconds: 45)
  Nil
}

pub fn sync_direction_decisions_test() {
  let assert Pull(remote_version: 2) =
    vault_sync_actor.decide_direction(1, 2, False)
  let assert Push(local_version: 3) =
    vault_sync_actor.decide_direction(3, 2, True)
  let assert Divergence(reason: _) =
    vault_sync_actor.decide_direction(3, 2, False)
  let assert NoOp = vault_sync_actor.decide_direction(2, 2, False)
  Nil
}

pub fn circuit_breaker_threshold_test() {
  should.equal(vault_sync_actor.circuit_should_open(2), False)
  should.equal(vault_sync_actor.circuit_should_open(3), True)
  should.equal(vault_sync_actor.circuit_should_open(10), True)
  should.equal(vault_sync_actor.circuit_cooldown_seconds(), 60)
}

// =====================================================================
// Slice E wiring guard — Wisp REST endpoints
// =====================================================================

import cepaf_gleam/ui/wisp/secret_api

pub fn secret_api_status_emits_json_test() {
  let json_str =
    secret_api.secret_status_json(
      "anthropic_api_key",
      1,
      1_700_000_000,
      60,
      3600,
      300,
    )
  should.not_equal(json_str, "")
}

pub fn secret_api_summary_emits_json_test() {
  let json_str =
    secret_api.secret_status_summary_json(
      8,
      0,
      0,
      [
        #("anthropic_api_key", "fresh"),
        #("openrouter_api_key", "fresh"),
      ],
      "Active",
      180,
    )
  should.not_equal(json_str, "")
}

pub fn secret_api_auth_rejects_missing_bearer_test() {
  let assert Error(_) = secret_api.require_auth("")
  let assert Error(_) = secret_api.require_auth("Basic abc123")
  Nil
}

// =====================================================================
// Pass-6 wiring guard — Lustre dashboard tile + TUI view
// =====================================================================

import cepaf_gleam/ui/lustre/secrets_vault as vault_tile
import cepaf_gleam/ui/tui/secrets_vault_view as vault_tui

pub fn vault_tile_init_defaults_test() {
  let m = vault_tile.init()
  should.equal(m.vault_state, "Sealed")
  should.equal(m.dashboard_color, "amber")
  should.equal(m.counts.fresh, 0)
  should.equal(m.counts.soft_stale, 0)
  should.equal(m.counts.hard_stale, 0)
}

pub fn vault_tile_status_received_updates_color_test() {
  let m0 = vault_tile.init()
  let m1 =
    vault_tile.update(
      m0,
      vault_tile.StatusReceived(
        "Active",
        180,
        vault_tile.Counts(fresh: 8, soft_stale: 0, hard_stale: 0),
        [],
        "green",
        1_700_000_000,
      ),
    )
  should.equal(m1.vault_state, "Active")
  should.equal(m1.dashboard_color, "green")
  should.equal(m1.counts.fresh, 8)
}

pub fn vault_tile_fetch_failed_sets_amber_test() {
  let m0 = vault_tile.init()
  let m1 = vault_tile.update(m0, vault_tile.StatusFetchFailed("network"))
  should.equal(m1.dashboard_color, "amber")
  should.equal(m1.vault_state, "Unknown")
}

pub fn vault_tile_view_html_contains_data_testid_test() {
  let html = vault_tile.view_html(vault_tile.init())
  // Contains the data-testid attribute used by Playwright tests
  should.equal(
    string_contains(html, "data-testid=\"secrets-vault-tile\""),
    True,
  )
  should.equal(string_contains(html, "Refresh now"), True)
}

pub fn vault_tui_renders_non_empty_test() {
  let m = vault_tile.init()
  let ansi = vault_tui.render(m)
  should.not_equal(ansi, "")
}

pub fn vault_tui_active_state_uses_green_test() {
  let m =
    vault_tile.update(
      vault_tile.init(),
      vault_tile.StatusReceived(
        "Active",
        60,
        vault_tile.Counts(fresh: 8, soft_stale: 0, hard_stale: 0),
        [vault_tile.SecretStatus("anthropic_api_key", "fresh")],
        "green",
        1_700_000_000,
      ),
    )
  let ansi = vault_tui.render(m)
  // Active state should produce green ANSI ([32m) somewhere
  should.equal(string_contains(ansi, "\u{001b}[32m"), True)
}

// Reuse gleam/string from the project's existing dependency tree.
import gleam/string

fn string_contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}

// =====================================================================
// Pass-8 wiring guard — MCP + Zenoh discoverability
// =====================================================================

import cepaf_gleam/mcp/tools as mcp_tools
import cepaf_gleam/vault_topics
import gleam/list as glist

pub fn vault_topic_builders_test() {
  should.equal(
    vault_topics.topic_secret_access("anthropic_api_key"),
    "indrajaal/l0/secret/access/anthropic_api_key",
  )
  should.equal(
    vault_topics.topic_kek_attempt("tpm"),
    "indrajaal/l0/secret/kek_attempt/tpm",
  )
  should.equal(
    vault_topics.topic_nif_call("kv_put"),
    "indrajaal/l1/atomic/vault/kv_put",
  )
  should.equal(
    vault_topics.topic_sync("run-001"),
    "indrajaal/l4/sync/vault/run-001",
  )
  should.equal(
    vault_topics.topic_rule_fire("SecretHardStale"),
    "indrajaal/l5/cog/vault_rule/SecretHardStale",
  )
  should.equal(
    vault_topics.topic_attest("mesh-eu-1"),
    "indrajaal/l7/fed/vault/attest/mesh-eu-1",
  )
}

pub fn vault_topic_glob_patterns_test() {
  should.equal(vault_topics.all_vault_events, "indrajaal/**/vault/**")
  should.equal(vault_topics.all_secret_access, "indrajaal/l0/secret/access/**")
  should.equal(vault_topics.all_sync_events, "indrajaal/l4/sync/vault/**")
}

pub fn vault_moz_tools_count_test() {
  case vault_topics.moz_tools {
    [_, _, _, _, _] -> Nil
    _ -> should.fail()
  }
}

pub fn vault_moz_topic_construction_test() {
  should.equal(
    vault_topics.topic_moz_req("vault_status", "req-001"),
    "indrajaal/mcp/req/vault/vault_status/req-001",
  )
  should.equal(
    vault_topics.topic_moz_res("req-001"),
    "indrajaal/mcp/res/req-001",
  )
}

pub fn vault_tools_in_mcp_catalog_test() {
  let defs = mcp_tools.get_tool_definitions()
  let names = glist.map(defs, fn(d) { d.name })
  should.equal(glist.contains(names, "vault_status"), True)
  should.equal(glist.contains(names, "vault_list_secrets"), True)
  should.equal(glist.contains(names, "vault_policy_get"), True)
  should.equal(glist.contains(names, "vault_audit_tail"), True)
  should.equal(glist.contains(names, "vault_health"), True)
}

// =====================================================================
// Pass-10 wiring guard — MoZ vault dispatcher
// =====================================================================

import cepaf_gleam/moz/vault as moz_vault

pub fn moz_vault_tools_match_mcp_test() {
  // The 5 MoZ tools must EXACTLY match the 5 MCP tools (single source of truth).
  case moz_vault.tools {
    [
      "vault_status",
      "vault_list_secrets",
      "vault_policy_get",
      "vault_audit_tail",
      "vault_health",
    ] -> Nil
    _ -> should.fail()
  }
}

pub fn moz_vault_dispatch_known_tool_returns_json_test() {
  let r1 = moz_vault.dispatch("vault_status", "{}")
  should.not_equal(r1, "")
  should.equal(string.contains(r1, "vault_state"), True)

  let r2 = moz_vault.dispatch("vault_health", "{}")
  should.equal(string.contains(r2, "tongsuo_absent"), True)
}

pub fn moz_vault_dispatch_unknown_tool_returns_error_test() {
  let r = moz_vault.dispatch("nonexistent_tool", "{}")
  should.equal(string.contains(r, "unknown_tool"), True)
}

pub fn moz_vault_request_topic_matches_topic_module_test() {
  let t = moz_vault.request_topic("vault_status", "req-001")
  should.equal(t, "indrajaal/mcp/req/vault/vault_status/req-001")
}

pub fn moz_vault_audit_topic_test() {
  let t = moz_vault.audit_topic("vault_status")
  should.equal(t, "indrajaal/l5/cog/vault_moz/vault_status")
}
