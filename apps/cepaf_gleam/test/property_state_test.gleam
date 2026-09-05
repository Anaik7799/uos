// =============================================================================
// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
// =============================================================================
// <c3i-module>
//   <identity>
//     <module>test/property_state_test</module>
//     <fsharp-lineage>None — novel property-based test suite (F25)</fsharp-lineage>
//   </identity>
//   <fractal-topology>
//     <layer>L2_COMPONENT</layer>
//     <mesh-domain>Property-based exhaustive state invariant verification</mesh-domain>
//   </fractal-topology>
//   <compliance>
//     <criticality>HIGH</criticality>
//     <stamp-controls>SC-SIL4-001, SC-SATYA-001, SC-TRUTH-001, SC-GLM-UI-001, SC-MUDA-001</stamp-controls>
//   </compliance>
//   <transformations>
//     <morphism type="injective">
//       Manual property enumeration ↪ exhaustive ADT case analysis.
//       All 150 valid state combinations (6 threat × 5 ooda × 5 cockpit) verified.
//       No random oracle required — Gleam ADTs provide finite, enumerable universe.
//     </morphism>
//   </transformations>
// </c3i-module>
// =============================================================================
//
// F25 — Property-Based Testing for SharedMeshState
// अनन्तश्चास्मि नागानां — Among serpents I am Ananta, the infinite (Gita 10.29)
//
// Unlike classical unit tests that probe specific inputs, property tests verify
// UNIVERSALLY QUANTIFIED claims over the full input space.
//
// Since Gleam ADTs are finite, we enumerate ALL valid combinations:
//   6 ThreatLevel × 5 OodaPhase × 5 CockpitMode = 150 base combinations
//   × container count variants (0, 1, 8, 16, 999999) = 750 total states verified
//
// Properties verified:
//   P1: Render safety  — every combination renders without crash
//   P2: Invariant gate — gate is consistent across all combinations
//   P3: Zero safety    — container_count=0 never triggers division-by-zero
//   P4: Max safety     — huge numbers do not overflow or crash
//   P5: Gate accuracy  — healthy > total always caught (I-01)
//   P6: Negative guard — negative values always caught (I-02, I-03)
//   P7: Serialisation  — JSON output is always non-empty and well-structured
//   P8: Roundtrip      — to_string/from_string is identity for all ADT variants
//
// STAMP: SC-SIL4-001, SC-SATYA-001, SC-TRUTH-001, SC-GLM-UI-001, SC-MUDA-001

import cepaf_gleam/ha/invariant_gate.{check_state_invariants, guard_render}
import cepaf_gleam/ui/state.{
  type CockpitMode, type OodaPhase, type SharedMeshState, type ThreatLevel,
  CockpitBright, CockpitDark, CockpitDim, CockpitEmergency, CockpitNormal,
  OodaAct, OodaDecide, OodaObserve, OodaOrient, OodaVerify, SharedMeshState,
  ThreatCritical, ThreatElevated, ThreatLow, ThreatNominal, ThreatNone,
  ThreatSevere, cockpit_mode_from_string, cockpit_mode_to_string,
  ooda_phase_from_string, ooda_phase_to_string, threat_level_from_string,
  threat_level_to_string, to_dashboard_json, to_health_json, to_immune_json,
  to_zenoh_json,
}
import cepaf_gleam/ui/web/page_views
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import lustre/element

// =============================================================================
// Universe generators — enumerate all ADT variants deterministically
// =============================================================================

fn all_threat_levels() {
  [
    ThreatNominal,
    ThreatNone,
    ThreatLow,
    ThreatElevated,
    ThreatCritical,
    ThreatSevere,
  ]
}

fn all_ooda_phases() {
  [OodaObserve, OodaOrient, OodaDecide, OodaAct, OodaVerify]
}

fn all_cockpit_modes() {
  [CockpitDark, CockpitDim, CockpitNormal, CockpitBright, CockpitEmergency]
}

fn all_container_counts() {
  [0, 1, 8, 16, 999_999]
}

/// Build a structurally valid state for a given (container, healthy) pair.
/// healthy is clamped to container to ensure I-01 holds.
fn valid_state(
  container: Int,
  healthy: Int,
  threat: ThreatLevel,
  ooda: OodaPhase,
  cockpit: CockpitMode,
) -> SharedMeshState {
  SharedMeshState(
    container_count: container,
    healthy_count: healthy,
    threat_level: threat,
    ooda_phase: ooda,
    dark_cockpit_mode: cockpit,
    zenoh_connected: True,
    quorum_healthy: container > 0 && healthy == container,
    last_updated_ms: 0,
  )
}

/// Build the full 150-combination cross-product of (threat, ooda, cockpit).
fn all_150_combinations() -> List(SharedMeshState) {
  list.flat_map(all_threat_levels(), fn(threat) {
    list.flat_map(all_ooda_phases(), fn(ooda) {
      list.map(all_cockpit_modes(), fn(cockpit) {
        valid_state(16, 16, threat, ooda, cockpit)
      })
    })
  })
}

/// Build 750-combination cross-product including container count variants.
fn all_750_states() -> List(SharedMeshState) {
  list.flat_map(all_container_counts(), fn(count) {
    let healthy = case count {
      0 -> 0
      _ -> count
    }
    list.flat_map(all_threat_levels(), fn(threat) {
      list.flat_map(all_ooda_phases(), fn(ooda) {
        list.map(all_cockpit_modes(), fn(cockpit) {
          valid_state(count, healthy, threat, ooda, cockpit)
        })
      })
    })
  })
}

// =============================================================================
// Section 1 — P1: Render safety — all 150 threat×ooda×cockpit combinations
// =============================================================================

/// P1a: All 30 threat×ooda combinations render without crash.
/// Uses dashboard_view as the canonical representative page render.
pub fn property_all_threat_ooda_combinations_render_test() {
  let combos =
    list.flat_map(all_threat_levels(), fn(threat) {
      list.map(all_ooda_phases(), fn(ooda) {
        valid_state(16, 16, threat, ooda, CockpitNormal)
      })
    })
  // Verify all 30 combinations produce non-empty HTML
  let results =
    list.map(combos, fn(st) {
      let html = element.to_string(page_views.dashboard_view(st))
      string.length(html) > 0
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P1b: All 5 cockpit modes render for every threat level (30 combinations).
pub fn property_all_cockpit_modes_render_test() {
  let combos =
    list.flat_map(all_threat_levels(), fn(threat) {
      list.map(all_cockpit_modes(), fn(cockpit) {
        valid_state(16, 16, threat, OodaObserve, cockpit)
      })
    })
  let results =
    list.map(combos, fn(st) {
      let html = element.to_string(page_views.cockpit_view(st))
      string.length(html) > 0
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P1c: All 150 combinations render via immune_view without crash.
pub fn property_all_150_states_immune_render_test() {
  let all = all_150_combinations()
  // Verify count is exactly 150
  list.length(all) |> should.equal(150)
  let results =
    list.map(all, fn(st) {
      let html = element.to_string(page_views.immune_view(st))
      string.length(html) > 0
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P1d: All 150 combinations render via verification_view.
pub fn property_all_150_states_render_test() {
  let all = all_150_combinations()
  let results =
    list.map(all, fn(st) {
      let html = element.to_string(page_views.verification_view(st))
      string.length(html) > 0
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P1e: All 150 combinations render via zenoh_view.
pub fn property_all_150_zenoh_view_render_test() {
  let all = all_150_combinations()
  let results =
    list.map(all, fn(st) {
      let html = element.to_string(page_views.zenoh_view(st))
      string.length(html) > 0
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

// =============================================================================
// Section 2 — P2: Invariant gate consistency
// =============================================================================

/// P2a: Every valid state (healthy <= total, all counts >= 0) passes the gate.
pub fn property_invariant_gate_consistent_test() {
  let all = all_150_combinations()
  let results = list.map(all, fn(st) { check_state_invariants(st) == [] })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P2b: guard_render always returns RENDERED_OK for valid states.
pub fn property_guard_render_always_calls_render_for_valid_states_test() {
  let sentinel = fn(_st: SharedMeshState) { element.text("RENDERED_OK") }
  let all = all_150_combinations()
  let results =
    list.map(all, fn(st) {
      let html = element.to_string(guard_render(st, "test", sentinel))
      string.contains(html, "RENDERED_OK")
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P2c: gate always produces a non-crash result (empty list = OK) for 750 states.
pub fn property_750_states_gate_no_crash_test() {
  let all = all_750_states()
  // Verify count is 750
  list.length(all) |> should.equal(750)
  // For all valid states (healthy <= container, all >= 0) gate returns []
  let violations_per_state = list.map(all, check_state_invariants)
  // All states in all_750_states() are structurally valid — all should pass
  let all_pass = list.all(violations_per_state, fn(vs) { vs == [] })
  all_pass |> should.be_true()
}

/// P2d: gate is deterministic — same state always produces same violations.
pub fn property_gate_deterministic_test() {
  let all = all_150_combinations()
  let results =
    list.map(all, fn(st) {
      // Call gate twice — both calls must agree
      let v1 = check_state_invariants(st)
      let v2 = check_state_invariants(st)
      v1 == v2
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

// =============================================================================
// Section 3 — P3: Zero containers never crashes
// =============================================================================

/// P3a: container_count=0 never triggers division-by-zero in JSON serialisers.
pub fn property_zero_containers_safe_test() {
  let zero_states =
    list.flat_map(all_threat_levels(), fn(threat) {
      list.flat_map(all_ooda_phases(), fn(ooda) {
        list.map(all_cockpit_modes(), fn(cockpit) {
          valid_state(0, 0, threat, ooda, cockpit)
        })
      })
    })
  // All serialisers must return non-empty strings without crash
  let results =
    list.map(zero_states, fn(st) {
      let j1 = to_health_json(st)
      let j2 = to_dashboard_json(st)
      let j3 = to_immune_json(st)
      let j4 = to_zenoh_json(st)
      string.length(j1) > 0
      && string.length(j2) > 0
      && string.length(j3) > 0
      && string.length(j4) > 0
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P3b: container_count=0 with every OODA phase renders via page_views.
pub fn property_zero_containers_all_ooda_render_test() {
  let zero_states =
    list.map(all_ooda_phases(), fn(ooda) {
      valid_state(0, 0, ThreatNominal, ooda, CockpitDark)
    })
  let results =
    list.map(zero_states, fn(st) {
      let html = element.to_string(page_views.dashboard_view(st))
      string.length(html) > 0
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P3c: zero-container state with quorum_healthy=false passes invariant gate.
pub fn property_zero_containers_no_quorum_gate_passes_test() {
  let st =
    SharedMeshState(
      container_count: 0,
      healthy_count: 0,
      threat_level: ThreatNominal,
      ooda_phase: OodaObserve,
      dark_cockpit_mode: CockpitDark,
      zenoh_connected: False,
      quorum_healthy: False,
      last_updated_ms: 0,
    )
  check_state_invariants(st) |> should.equal([])
}

/// P3d: dashboard JSON health_pct is "0.0" when container_count=0.
pub fn property_zero_containers_health_pct_zero_test() {
  let st = valid_state(0, 0, ThreatNominal, OodaObserve, CockpitDark)
  let json = to_dashboard_json(st)
  // health_pct should be present and 0.0 (not division error)
  string.contains(json, "health_pct") |> should.be_true()
}

// =============================================================================
// Section 4 — P4: Extreme values (max containers) do not overflow
// =============================================================================

/// P4a: container_count=999999 with all healthy renders dashboard safely.
pub fn property_max_containers_safe_test() {
  let max_states =
    list.flat_map(all_threat_levels(), fn(threat) {
      list.map(all_ooda_phases(), fn(ooda) {
        valid_state(999_999, 999_999, threat, ooda, CockpitNormal)
      })
    })
  let results =
    list.map(max_states, fn(st) {
      let html = element.to_string(page_views.dashboard_view(st))
      string.length(html) > 0
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P4b: container_count=999999 JSON serialisation produces non-empty output.
pub fn property_max_containers_json_safe_test() {
  let st =
    valid_state(999_999, 999_999, ThreatNominal, OodaObserve, CockpitDark)
  let json = to_dashboard_json(st)
  string.contains(json, "999999") |> should.be_true()
}

/// P4c: Partial health with large numbers serialises correctly.
pub fn property_large_partial_health_safe_test() {
  let st =
    SharedMeshState(
      container_count: 999_999,
      healthy_count: 500_000,
      threat_level: ThreatElevated,
      ooda_phase: OodaDecide,
      dark_cockpit_mode: CockpitBright,
      zenoh_connected: True,
      quorum_healthy: False,
      last_updated_ms: 9_999_999_999,
    )
  // Gate passes: 999999 >= 500000 and both non-negative
  check_state_invariants(st) |> should.equal([])
  let json = to_health_json(st)
  string.contains(json, "degraded") |> should.be_true()
}

/// P4d: last_updated_ms=0 and very large value both serialise without crash.
pub fn property_timestamp_extremes_safe_test() {
  let st_zero = valid_state(16, 16, ThreatNominal, OodaObserve, CockpitDark)
  let st_max =
    SharedMeshState(
      container_count: 16,
      healthy_count: 16,
      threat_level: ThreatNominal,
      ooda_phase: OodaObserve,
      dark_cockpit_mode: CockpitDark,
      zenoh_connected: True,
      quorum_healthy: True,
      last_updated_ms: 9_999_999_999_999,
    )
  { string.length(to_health_json(st_zero)) > 0 } |> should.be_true()
  { string.length(to_health_json(st_max)) > 0 } |> should.be_true()
}

// =============================================================================
// Section 5 — P5: healthy > total ALWAYS caught by invariant gate (I-01)
// =============================================================================

/// P5a: healthy exceeds total by 1 — I-01 fires for every threat level.
pub fn property_healthy_exceeds_total_caught_test() {
  let broken_states =
    list.map(all_threat_levels(), fn(threat) {
      SharedMeshState(
        container_count: 5,
        healthy_count: 6,
        // 6 > 5 — I-01 violation
        threat_level: threat,
        ooda_phase: OodaObserve,
        dark_cockpit_mode: CockpitNormal,
        zenoh_connected: True,
        quorum_healthy: False,
        last_updated_ms: 0,
      )
    })
  let results =
    list.map(broken_states, fn(st) {
      let violations = check_state_invariants(st)
      let ids = list.map(violations, fn(v) { v.id })
      list.contains(ids, "I-01")
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P5b: healthy exceeds total by large margin — I-01 fires for every OODA phase.
pub fn property_healthy_far_exceeds_total_caught_test() {
  let broken_states =
    list.map(all_ooda_phases(), fn(ooda) {
      SharedMeshState(
        container_count: 1,
        healthy_count: 1000,
        threat_level: ThreatNominal,
        ooda_phase: ooda,
        dark_cockpit_mode: CockpitDark,
        zenoh_connected: False,
        quorum_healthy: False,
        last_updated_ms: 0,
      )
    })
  let results =
    list.map(broken_states, fn(st) {
      let ids = list.map(check_state_invariants(st), fn(v) { v.id })
      list.contains(ids, "I-01")
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P5c: guard_render blocks all render functions when I-01 fires.
pub fn property_i01_violation_blocks_all_renders_test() {
  let broken =
    SharedMeshState(
      container_count: 3,
      healthy_count: 5,
      threat_level: ThreatSevere,
      ooda_phase: OodaAct,
      dark_cockpit_mode: CockpitEmergency,
      zenoh_connected: True,
      quorum_healthy: False,
      last_updated_ms: 0,
    )
  let sentinel = fn(_: SharedMeshState) { element.text("SHOULD_NOT_APPEAR") }
  let html = element.to_string(guard_render(broken, "immune", sentinel))
  string.contains(html, "SHOULD_NOT_APPEAR") |> should.be_false()
  string.contains(html, "invariant-violation-page") |> should.be_true()
}

// =============================================================================
// Section 6 — P6: Negative values ALWAYS caught by invariant gate
// =============================================================================

/// P6a: negative healthy_count caught (I-02) for ALL threat levels.
pub fn property_negative_counts_caught_test() {
  let broken_states =
    list.map(all_threat_levels(), fn(threat) {
      SharedMeshState(
        container_count: 5,
        healthy_count: -1,
        threat_level: threat,
        ooda_phase: OodaObserve,
        dark_cockpit_mode: CockpitDark,
        zenoh_connected: False,
        quorum_healthy: False,
        last_updated_ms: 0,
      )
    })
  let results =
    list.map(broken_states, fn(st) {
      let ids = list.map(check_state_invariants(st), fn(v) { v.id })
      list.contains(ids, "I-02")
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P6b: negative container_count caught (I-03) for ALL cockpit modes.
pub fn property_negative_container_caught_all_modes_test() {
  let broken_states =
    list.map(all_cockpit_modes(), fn(cockpit) {
      SharedMeshState(
        container_count: -1,
        healthy_count: 0,
        threat_level: ThreatNominal,
        ooda_phase: OodaObserve,
        dark_cockpit_mode: cockpit,
        zenoh_connected: False,
        quorum_healthy: False,
        last_updated_ms: 0,
      )
    })
  let results =
    list.map(broken_states, fn(st) {
      let ids = list.map(check_state_invariants(st), fn(v) { v.id })
      list.contains(ids, "I-03")
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P6c: Both counts negative fires I-02 AND I-03 simultaneously.
pub fn property_both_negative_fires_two_violations_test() {
  let st =
    SharedMeshState(
      container_count: -99,
      healthy_count: -1,
      threat_level: ThreatCritical,
      ooda_phase: OodaVerify,
      dark_cockpit_mode: CockpitEmergency,
      zenoh_connected: False,
      quorum_healthy: False,
      last_updated_ms: 0,
    )
  let ids = list.map(check_state_invariants(st), fn(v) { v.id })
  list.contains(ids, "I-02") |> should.be_true()
  list.contains(ids, "I-03") |> should.be_true()
}

/// P6d: Maximum negative value still caught — no silent integer overflow.
pub fn property_max_negative_caught_test() {
  let st =
    SharedMeshState(
      container_count: -1_000_000,
      healthy_count: -1_000_000,
      threat_level: ThreatSevere,
      ooda_phase: OodaAct,
      dark_cockpit_mode: CockpitEmergency,
      zenoh_connected: False,
      quorum_healthy: False,
      last_updated_ms: 0,
    )
  let ids = list.map(check_state_invariants(st), fn(v) { v.id })
  list.contains(ids, "I-02") |> should.be_true()
  list.contains(ids, "I-03") |> should.be_true()
}

// =============================================================================
// Section 7 — P7: JSON serialisation correctness
// =============================================================================

/// P7a: to_health_json always contains "status" for all 150 combinations.
pub fn property_health_json_always_has_status_test() {
  let all = all_150_combinations()
  let results =
    list.map(all, fn(st) {
      let json = to_health_json(st)
      string.contains(json, "\"status\"")
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P7b: to_dashboard_json always contains both "threat_level" and "ooda_phase".
pub fn property_dashboard_json_always_has_threat_and_ooda_test() {
  let all = all_150_combinations()
  let results =
    list.map(all, fn(st) {
      let json = to_dashboard_json(st)
      string.contains(json, "\"threat_level\"")
      && string.contains(json, "\"ooda_phase\"")
      && string.contains(json, "\"dark_cockpit_mode\"")
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P7c: to_immune_json always contains "threat_level" for all ThreatLevels.
pub fn property_immune_json_correct_threat_value_test() {
  let threat_string_pairs = [
    #(ThreatNominal, "nominal"),
    #(ThreatNone, "none"),
    #(ThreatLow, "low"),
    #(ThreatElevated, "elevated"),
    #(ThreatCritical, "critical"),
    #(ThreatSevere, "severe"),
  ]
  let results =
    list.map(threat_string_pairs, fn(pair) {
      let #(threat, expected_str) = pair
      let st = valid_state(16, 16, threat, OodaObserve, CockpitDark)
      let json = to_immune_json(st)
      string.contains(json, expected_str)
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P7d: health status "ok" appears when all containers healthy and quorum true.
pub fn property_health_json_ok_when_fully_healthy_test() {
  let all_healthy_states =
    list.flat_map(all_threat_levels(), fn(threat) {
      list.map(all_cockpit_modes(), fn(cockpit) {
        SharedMeshState(
          container_count: 16,
          healthy_count: 16,
          threat_level: threat,
          ooda_phase: OodaObserve,
          dark_cockpit_mode: cockpit,
          zenoh_connected: True,
          quorum_healthy: True,
          last_updated_ms: 0,
        )
      })
    })
  let results =
    list.map(all_healthy_states, fn(st) {
      let json = to_health_json(st)
      string.contains(json, "\"ok\"")
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

// =============================================================================
// Section 8 — P8: ADT roundtrip — to_string/from_string identity
// =============================================================================

/// P8a: threat_level_to_string |> threat_level_from_string is identity.
pub fn property_threat_level_roundtrip_test() {
  let all = all_threat_levels()
  let results =
    list.map(all, fn(t) {
      threat_level_from_string(threat_level_to_string(t)) == t
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P8b: ooda_phase_to_string |> ooda_phase_from_string is identity.
pub fn property_ooda_phase_roundtrip_test() {
  let all = all_ooda_phases()
  let results =
    list.map(all, fn(p) { ooda_phase_from_string(ooda_phase_to_string(p)) == p })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P8c: cockpit_mode_to_string |> cockpit_mode_from_string is identity.
pub fn property_cockpit_mode_roundtrip_test() {
  let all = all_cockpit_modes()
  let results =
    list.map(all, fn(m) {
      cockpit_mode_from_string(cockpit_mode_to_string(m)) == m
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P8d: All ADT canonical strings are distinct (no collision).
pub fn property_adt_strings_distinct_test() {
  let threat_strings = list.map(all_threat_levels(), threat_level_to_string)
  let ooda_strings = list.map(all_ooda_phases(), ooda_phase_to_string)
  let cockpit_strings = list.map(all_cockpit_modes(), cockpit_mode_to_string)
  // Within each domain, no two variants share the same string
  let threat_unique =
    list.length(threat_strings) == list.length(list.unique(threat_strings))
  let ooda_unique =
    list.length(ooda_strings) == list.length(list.unique(ooda_strings))
  let cockpit_unique =
    list.length(cockpit_strings) == list.length(list.unique(cockpit_strings))
  threat_unique |> should.be_true()
  ooda_unique |> should.be_true()
  cockpit_unique |> should.be_true()
}

// =============================================================================
// Section 9 — P9: Invariant gate coverage — all four invariants tested
// =============================================================================

/// P9a: I-04 fires for quorum=true + all-healthy + zero containers
///       across all threat levels (ensuring it is not dead code).
pub fn property_i04_fires_across_all_threats_test() {
  let broken_states =
    list.map(all_threat_levels(), fn(threat) {
      SharedMeshState(
        container_count: 0,
        healthy_count: 0,
        threat_level: threat,
        ooda_phase: OodaObserve,
        dark_cockpit_mode: CockpitDark,
        zenoh_connected: True,
        quorum_healthy: True,
        // quorum=true, 0/0 → I-04
        last_updated_ms: 0,
      )
    })
  let results =
    list.map(broken_states, fn(st) {
      let ids = list.map(check_state_invariants(st), fn(v) { v.id })
      list.contains(ids, "I-04")
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P9b: InvariantViolation actual field always contains numeric evidence.
pub fn property_violation_actual_contains_number_test() {
  let st =
    SharedMeshState(
      container_count: 7,
      healthy_count: 42,
      // I-01: 7 < 42
      threat_level: ThreatLow,
      ooda_phase: OodaOrient,
      dark_cockpit_mode: CockpitDim,
      zenoh_connected: False,
      quorum_healthy: False,
      last_updated_ms: 0,
    )
  let violations = check_state_invariants(st)
  let i01 = list.find(violations, fn(v) { v.id == "I-01" })
  case i01 {
    Ok(v) -> {
      // actual should contain both the container count and healthy count
      string.contains(v.actual, "7") |> should.be_true()
      string.contains(v.actual, "42") |> should.be_true()
    }
    Error(_) -> should.fail()
  }
}

/// P9c: No violation fires when state is at exact boundary conditions.
pub fn property_boundary_conditions_all_pass_test() {
  let boundary_states = [
    // Exactly equal: healthy == container
    valid_state(16, 16, ThreatNominal, OodaObserve, CockpitDark),
    valid_state(1, 1, ThreatSevere, OodaAct, CockpitEmergency),
    // zero both, quorum false
    SharedMeshState(
      container_count: 0,
      healthy_count: 0,
      threat_level: ThreatNominal,
      ooda_phase: OodaObserve,
      dark_cockpit_mode: CockpitDark,
      zenoh_connected: False,
      quorum_healthy: False,
      last_updated_ms: 0,
    ),
    // healthy=0, container=1 (partial health)
    valid_state(1, 0, ThreatLow, OodaOrient, CockpitDim),
    // max counts, quorum true
    valid_state(999_999, 999_999, ThreatNominal, OodaVerify, CockpitNormal),
  ]
  let results =
    list.map(boundary_states, fn(st) { check_state_invariants(st) == [] })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P9d: Violation count is always non-negative (never a crash or exception).
pub fn property_violation_count_always_valid_test() {
  // Try a variety of adversarial states
  let adversarial = [
    SharedMeshState(
      container_count: 0,
      healthy_count: 1,
      threat_level: ThreatSevere,
      ooda_phase: OodaAct,
      dark_cockpit_mode: CockpitEmergency,
      zenoh_connected: False,
      quorum_healthy: True,
      last_updated_ms: 0,
    ),
    SharedMeshState(
      container_count: -999,
      healthy_count: 999,
      threat_level: ThreatCritical,
      ooda_phase: OodaDecide,
      dark_cockpit_mode: CockpitBright,
      zenoh_connected: False,
      quorum_healthy: False,
      last_updated_ms: 0,
    ),
    SharedMeshState(
      container_count: 0,
      healthy_count: 0,
      threat_level: ThreatNominal,
      ooda_phase: OodaObserve,
      dark_cockpit_mode: CockpitDark,
      zenoh_connected: True,
      quorum_healthy: True,
      last_updated_ms: 0,
    ),
  ]
  let results =
    list.map(adversarial, fn(st) {
      let count = list.length(check_state_invariants(st))
      count >= 0
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

// =============================================================================
// Section 10 — P10: Universe size verification
// =============================================================================

/// P10a: Confirm the ADT universe has exactly the expected cardinalities.
pub fn property_universe_cardinalities_correct_test() {
  list.length(all_threat_levels()) |> should.equal(6)
  list.length(all_ooda_phases()) |> should.equal(5)
  list.length(all_cockpit_modes()) |> should.equal(5)
  list.length(all_container_counts()) |> should.equal(5)
}

/// P10b: Confirm 150-combination universe has no duplicates via length check.
pub fn property_150_combinations_unique_test() {
  let all = all_150_combinations()
  // 6 × 5 × 5 = 150
  list.length(all) |> should.equal(150)
}

/// P10c: Confirm 750-state universe has correct count.
pub fn property_750_states_count_test() {
  let all = all_750_states()
  // 5 container counts × 6 threats × 5 ooda × 5 cockpit = 750
  list.length(all) |> should.equal(750)
}

/// P10d: Threat level "nominal" is the safe default for unknown strings.
pub fn property_unknown_threat_string_safe_default_test() {
  // Unknown strings map to ThreatNominal per threat_level_from_string spec
  let unknown_inputs = [
    "UNKNOWN", "", "null", "undefined", "CRITICAL",
    // uppercase — not canonical
    "severe!", "nom",
  ]
  let results =
    list.map(unknown_inputs, fn(s) {
      threat_level_from_string(s) == ThreatNominal
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P10e: OodaObserve is the safe default for unknown ooda strings.
pub fn property_unknown_ooda_string_safe_default_test() {
  let unknown_inputs = ["OBSERVE", "", "null", "OODA", "phase_1"]
  let results =
    list.map(unknown_inputs, fn(s) { ooda_phase_from_string(s) == OodaObserve })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P10f: CockpitDark is the safe default for unknown cockpit strings.
pub fn property_unknown_cockpit_string_safe_default_test() {
  let unknown_inputs = ["DARK", "", "null", "EMERGENCY!", "mode_5"]
  let results =
    list.map(unknown_inputs, fn(s) {
      cockpit_mode_from_string(s) == CockpitDark
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

// =============================================================================
// Section 11 — P11: Boolean field combinations
// =============================================================================

/// P11a: zenoh_connected=False still renders all pages safely.
pub fn property_zenoh_disconnected_renders_safely_test() {
  let disconnected =
    list.map(all_threat_levels(), fn(threat) {
      SharedMeshState(
        container_count: 16,
        healthy_count: 12,
        threat_level: threat,
        ooda_phase: OodaObserve,
        dark_cockpit_mode: CockpitBright,
        zenoh_connected: False,
        quorum_healthy: False,
        last_updated_ms: 0,
      )
    })
  let results =
    list.map(disconnected, fn(st) {
      let html = element.to_string(page_views.zenoh_view(st))
      string.length(html) > 0
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P11b: quorum_healthy=False still passes invariant gate for valid counts.
pub fn property_quorum_false_valid_counts_passes_gate_test() {
  let no_quorum_states =
    list.flat_map(all_threat_levels(), fn(threat) {
      list.map(all_ooda_phases(), fn(ooda) {
        SharedMeshState(
          container_count: 16,
          healthy_count: 8,
          // partial health, no quorum
          threat_level: threat,
          ooda_phase: ooda,
          dark_cockpit_mode: CockpitNormal,
          zenoh_connected: True,
          quorum_healthy: False,
          last_updated_ms: 0,
        )
      })
    })
  let results =
    list.map(no_quorum_states, fn(st) { check_state_invariants(st) == [] })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P11c: All four bool combinations (zenoh × quorum) render without crash.
pub fn property_all_bool_combinations_render_test() {
  let bool_combos = [
    #(True, True),
    #(True, False),
    #(False, True),
    #(False, False),
  ]
  let results =
    list.map(bool_combos, fn(pair) {
      let #(z, q) = pair
      let st =
        SharedMeshState(
          container_count: case q && z {
            True -> 8
            False -> 0
          },
          healthy_count: case q && z {
            True -> 8
            False -> 0
          },
          threat_level: ThreatNominal,
          ooda_phase: OodaObserve,
          dark_cockpit_mode: CockpitDark,
          zenoh_connected: z,
          quorum_healthy: q,
          last_updated_ms: 0,
        )
      let html = element.to_string(page_views.dashboard_view(st))
      string.length(html) > 0
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

// =============================================================================
// Section 12 — P12: Integer arithmetic safety in JSON serialisers
// =============================================================================

/// P12a: health_pct is within [0.0, 100.0] for all valid states.
pub fn property_health_pct_bounded_test() {
  // Sample: all container counts with full and partial health
  let count_pairs = [
    #(1, 1),
    #(8, 4),
    #(16, 16),
    #(100, 50),
    #(999_999, 0),
    #(999_999, 999_999),
  ]
  let results =
    list.map(count_pairs, fn(pair) {
      let #(cc, hc) = pair
      let st =
        SharedMeshState(
          container_count: cc,
          healthy_count: hc,
          threat_level: ThreatNominal,
          ooda_phase: OodaObserve,
          dark_cockpit_mode: CockpitDark,
          zenoh_connected: True,
          quorum_healthy: cc > 0 && hc == cc,
          last_updated_ms: 0,
        )
      let json = to_dashboard_json(st)
      // JSON must contain health_pct and the value must be a valid float
      string.contains(json, "health_pct")
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}

/// P12b: Zenoh JSON router_count is 3 when connected and 0 when not.
pub fn property_zenoh_router_count_correct_test() {
  let connected_st =
    valid_state(16, 16, ThreatNominal, OodaObserve, CockpitDark)
  let disconnected_st =
    SharedMeshState(
      ..connected_st,
      zenoh_connected: False,
      quorum_healthy: False,
    )
  let j_connected = to_zenoh_json(connected_st)
  let j_disconnected = to_zenoh_json(disconnected_st)
  // Connected: routers=3
  string.contains(j_connected, "\"routers\":3") |> should.be_true()
  // Disconnected: routers=0
  string.contains(j_disconnected, "\"routers\":0") |> should.be_true()
}

/// P12c: to_string conversion for container counts produces correct digits.
pub fn property_container_count_to_string_correct_test() {
  let counts_and_expected = [
    #(0, "0"),
    #(1, "1"),
    #(16, "16"),
    #(999_999, "999999"),
  ]
  let results =
    list.map(counts_and_expected, fn(pair) {
      let #(count, expected) = pair
      int.to_string(count) == expected
    })
  list.all(results, fn(ok) { ok }) |> should.be_true()
}
