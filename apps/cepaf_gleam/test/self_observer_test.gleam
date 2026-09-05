//// =============================================================================
//// [C3I-SIL6-MSTS] SELF-OBSERVER TESTS
//// =============================================================================
//// आत्मानं रथिनं विद्धि — Know the Self as the rider (Katha Upanishad 1.3.3)
////
//// Tests for the self-observation actor (Satya Plan Sprint 2).
//// Verifies:
////   - Init state is clean
////   - All 12 invariants pass with healthy default state
////   - Invariant violations detected with deliberately broken state
////   - Mismatch counting and accumulation
////   - status_string formatting
////   - worst_severity ranking
////   - Derivation helper functions
////
//// STAMP: SC-SATYA-001, SC-TRUTH-001, SC-SIL4-001, SC-GLM-UI-001

import cepaf_gleam/ha/self_observer.{
  AllTruthful, Critical, High, Low, Medium, MismatchDetected, SelfObserverState,
  TruthMismatch, check_with_state, derive_antibody_count, derive_health_score,
  derive_health_status, derive_router_count, derive_weather_label,
  derive_zenoh_status, init, status_string, worst_severity,
}
import cepaf_gleam/ui/state.{
  CockpitBright, CockpitDark, OodaDecide, OodaObserve, SharedMeshState,
  ThreatCritical, ThreatElevated, ThreatLow, ThreatNominal, ThreatNone,
  ThreatSevere, default_state,
}
import gleam/string
import gleeunit/should

// =============================================================================
// Section 1: Init state
// =============================================================================

pub fn init_check_count_zero_test() {
  let st = init()
  st.check_count |> should.equal(0)
}

pub fn init_match_count_zero_test() {
  let st = init()
  st.match_count |> should.equal(0)
}

pub fn init_mismatch_count_zero_test() {
  let st = init()
  st.mismatch_count |> should.equal(0)
}

pub fn init_last_check_timestamp_zero_test() {
  let st = init()
  st.last_check_timestamp |> should.equal(0)
}

pub fn init_mismatches_empty_test() {
  let st = init()
  st.mismatches |> should.equal([])
}

// =============================================================================
// Section 2: Default state produces AllTruthful
// =============================================================================

pub fn default_state_all_truthful_test() {
  let obs = init()
  let mesh = default_state()
  let #(_new_obs, result) = check_with_state(obs, mesh)
  result |> should.equal(AllTruthful)
}

pub fn default_state_increments_check_count_test() {
  let obs = init()
  let mesh = default_state()
  let #(new_obs, _) = check_with_state(obs, mesh)
  new_obs.check_count |> should.equal(1)
}

pub fn default_state_increments_match_count_test() {
  let obs = init()
  let mesh = default_state()
  let #(new_obs, _) = check_with_state(obs, mesh)
  new_obs.match_count |> should.equal(1)
}

pub fn default_state_mismatch_count_stays_zero_test() {
  let obs = init()
  let mesh = default_state()
  let #(new_obs, _) = check_with_state(obs, mesh)
  new_obs.mismatch_count |> should.equal(0)
}

pub fn default_state_mismatches_list_empty_test() {
  let obs = init()
  let mesh = default_state()
  let #(new_obs, _) = check_with_state(obs, mesh)
  new_obs.mismatches |> should.equal([])
}

// =============================================================================
// Section 3: Invariant I-01 — quorum+nominal → health ≥ 80
// =============================================================================

pub fn i01_healthy_nominal_score_is_92_test() {
  let score =
    derive_health_score(SharedMeshState(
      container_count: 16,
      healthy_count: 16,
      threat_level: ThreatNominal,
      ooda_phase: OodaObserve,
      dark_cockpit_mode: CockpitDark,
      zenoh_connected: True,
      quorum_healthy: True,
      last_updated_ms: 0,
    ))
  score |> should.equal(92)
}

pub fn i01_healthy_none_score_is_92_test() {
  let score =
    derive_health_score(SharedMeshState(
      container_count: 16,
      healthy_count: 16,
      threat_level: ThreatNone,
      ooda_phase: OodaObserve,
      dark_cockpit_mode: CockpitDark,
      zenoh_connected: True,
      quorum_healthy: True,
      last_updated_ms: 0,
    ))
  score |> should.equal(92)
}

pub fn i01_violation_detected_quorum_false_nominal_test() {
  // quorum_healthy=false with ThreatNominal is a self-contradictory state:
  // I-02 fires because ThreatNominal → weather should be "Clear" but score=35
  // (quorum=False) → weather="Stormy". I-02 reports this contradiction.
  let obs = init()
  let mesh =
    SharedMeshState(
      container_count: 16,
      healthy_count: 16,
      threat_level: ThreatNominal,
      ooda_phase: OodaObserve,
      dark_cockpit_mode: CockpitDark,
      zenoh_connected: True,
      quorum_healthy: False,
      last_updated_ms: 0,
    )
  // I-01 is skipped (quorum=False). I-06 passes (score=35 <80).
  // I-02 fires: ThreatNominal but weather="Stormy" → MismatchDetected.
  let #(_, result) = check_with_state(obs, mesh)
  case result {
    MismatchDetected(_) -> True |> should.be_true()
    AllTruthful -> should.fail()
  }
}

// =============================================================================
// Section 4: Invariant I-02 — ThreatNominal → weather "Clear"
// =============================================================================

pub fn i02_nominal_weather_is_clear_test() {
  let score = derive_health_score(default_state())
  let label = derive_weather_label(score)
  label |> should.equal("Clear")
}

pub fn i02_score_below_80_gives_partly_cloudy_test() {
  derive_weather_label(79) |> should.equal("Partly cloudy")
}

pub fn i02_score_below_60_gives_stormy_test() {
  derive_weather_label(59) |> should.equal("Stormy")
}

pub fn i02_score_exactly_80_gives_clear_test() {
  derive_weather_label(80) |> should.equal("Clear")
}

// =============================================================================
// Section 5: Invariant I-03 — CriticalSevere → dark_cockpit ≠ "dark"
// =============================================================================

pub fn i03_critical_threat_dark_mode_is_violation_test() {
  let obs = init()
  let mesh =
    SharedMeshState(
      container_count: 16,
      healthy_count: 8,
      threat_level: ThreatCritical,
      ooda_phase: OodaDecide,
      dark_cockpit_mode: CockpitDark,
      zenoh_connected: True,
      quorum_healthy: False,
      last_updated_ms: 0,
    )
  let #(_, result) = check_with_state(obs, mesh)
  // I-03 violation: ThreatCritical + dark_cockpit_mode="dark"
  case result {
    MismatchDetected(mismatches: ms) -> {
      // Should contain I-03 violation
      let has_i03 =
        list_any(ms, fn(m) { m.value_id == "I-03:dark_cockpit_mode" })
      has_i03 |> should.be_true()
    }
    AllTruthful ->
      // This should NOT be truthful — I-03 must fire
      should.fail()
  }
}

pub fn i03_critical_threat_bright_mode_is_ok_test() {
  let obs = init()
  let mesh =
    SharedMeshState(
      container_count: 16,
      healthy_count: 16,
      threat_level: ThreatCritical,
      ooda_phase: OodaDecide,
      dark_cockpit_mode: CockpitBright,
      zenoh_connected: True,
      quorum_healthy: True,
      last_updated_ms: 0,
    )
  let #(_, result) = check_with_state(obs, mesh)
  // I-03 satisfied: dark_cockpit_mode ≠ "dark"
  // Check I-03 does NOT fire
  case result {
    AllTruthful -> True |> should.be_true()
    MismatchDetected(mismatches: ms) -> {
      let has_i03 =
        list_any(ms, fn(m) { m.value_id == "I-03:dark_cockpit_mode" })
      has_i03 |> should.be_false()
    }
  }
}

// =============================================================================
// Section 6: Invariant I-04 — container_count ≥ healthy_count
// =============================================================================

pub fn i04_equal_counts_is_ok_test() {
  let obs = init()
  let mesh =
    SharedMeshState(..default_state(), container_count: 10, healthy_count: 10)
  let #(_, result) = check_with_state(obs, mesh)
  case result {
    AllTruthful -> True |> should.be_true()
    MismatchDetected(mismatches: ms) -> {
      let has_i04 =
        list_any(ms, fn(m) { m.value_id == "I-04:container_geometry" })
      has_i04 |> should.be_false()
    }
  }
}

pub fn i04_healthy_exceeds_container_is_violation_test() {
  let obs = init()
  let mesh =
    SharedMeshState(..default_state(), container_count: 10, healthy_count: 11)
  let #(_, result) = check_with_state(obs, mesh)
  case result {
    MismatchDetected(mismatches: ms) -> {
      let has_i04 =
        list_any(ms, fn(m) { m.value_id == "I-04:container_geometry" })
      has_i04 |> should.be_true()
    }
    AllTruthful -> should.fail()
  }
}

// =============================================================================
// Section 7: Invariant I-05 — zenoh_connected → status "active"
// =============================================================================

pub fn i05_zenoh_connected_status_is_active_test() {
  derive_zenoh_status(True) |> should.equal("active")
}

pub fn i05_zenoh_disconnected_status_is_inactive_test() {
  derive_zenoh_status(False) |> should.equal("inactive")
}

// =============================================================================
// Section 8: Invariants I-09, I-10 — antibody counts
// =============================================================================

pub fn i09_threat_low_antibodies_3_test() {
  derive_antibody_count(ThreatLow) |> should.equal(3)
}

pub fn i09_threat_elevated_antibodies_3_test() {
  derive_antibody_count(ThreatElevated) |> should.equal(3)
}

pub fn i10_threat_critical_antibodies_12_test() {
  derive_antibody_count(ThreatCritical) |> should.equal(12)
}

pub fn i10_threat_severe_antibodies_12_test() {
  derive_antibody_count(ThreatSevere) |> should.equal(12)
}

pub fn i09_threat_nominal_antibodies_0_test() {
  derive_antibody_count(ThreatNominal) |> should.equal(0)
}

pub fn i09_threat_none_antibodies_0_test() {
  derive_antibody_count(ThreatNone) |> should.equal(0)
}

// =============================================================================
// Section 9: Invariants I-07, I-08 — derived health status
// =============================================================================

pub fn i07_all_healthy_quorum_status_ok_test() {
  let mesh =
    SharedMeshState(
      ..default_state(),
      container_count: 16,
      healthy_count: 16,
      quorum_healthy: True,
    )
  derive_health_status(mesh) |> should.equal("ok")
}

pub fn i08_majority_unhealthy_status_critical_test() {
  let mesh =
    SharedMeshState(
      ..default_state(),
      container_count: 10,
      healthy_count: 4,
      quorum_healthy: False,
    )
  // healthy_count(4) ≤ container_count/2(5) → "critical"
  derive_health_status(mesh) |> should.equal("critical")
}

pub fn i07_i08_degraded_majority_healthy_test() {
  let mesh =
    SharedMeshState(
      ..default_state(),
      container_count: 10,
      healthy_count: 6,
      quorum_healthy: False,
    )
  // 6 > 10/2=5 → "degraded"
  derive_health_status(mesh) |> should.equal("degraded")
}

// =============================================================================
// Section 10: Invariant I-11 — zenoh disconnected → 0 routers
// =============================================================================

pub fn i11_disconnected_zero_routers_test() {
  derive_router_count(False) |> should.equal(0)
}

pub fn i11_connected_three_routers_test() {
  derive_router_count(True) |> should.equal(3)
}

// =============================================================================
// Section 11: Mismatch counting and accumulation
// =============================================================================

pub fn mismatch_count_increments_on_violation_test() {
  let obs = init()
  // I-04 violation: healthy > container
  let bad_mesh =
    SharedMeshState(..default_state(), container_count: 5, healthy_count: 10)
  let #(new_obs, _) = check_with_state(obs, bad_mesh)
  new_obs.mismatch_count |> should.equal(1)
  new_obs.match_count |> should.equal(0)
}

pub fn mismatches_accumulate_across_checks_test() {
  let obs = init()
  let bad_mesh =
    SharedMeshState(..default_state(), container_count: 5, healthy_count: 10)
  let #(obs2, _) = check_with_state(obs, bad_mesh)
  let #(obs3, _) = check_with_state(obs2, bad_mesh)
  obs3.mismatch_count |> should.equal(2)
  obs3.check_count |> should.equal(2)
}

// =============================================================================
// Section 12: status_string formatting
// =============================================================================

pub fn status_string_contains_checks_test() {
  let obs =
    SelfObserverState(
      check_count: 5,
      match_count: 4,
      mismatch_count: 1,
      last_check_timestamp: 5,
      mismatches: [],
    )
  let s = status_string(obs)
  s |> string_contains_check("checks: 5")
}

pub fn status_string_contains_truth_rate_test() {
  let obs =
    SelfObserverState(
      check_count: 4,
      match_count: 4,
      mismatch_count: 0,
      last_check_timestamp: 4,
      mismatches: [],
    )
  let s = status_string(obs)
  s |> string_contains_check("100%")
}

pub fn status_string_zero_checks_shows_na_test() {
  let obs = init()
  let s = status_string(obs)
  s |> string_contains_check("N/A")
}

// =============================================================================
// Section 13: worst_severity ranking
// =============================================================================

pub fn worst_severity_empty_is_low_test() {
  worst_severity(init()) |> should.equal(Low)
}

pub fn worst_severity_single_critical_test() {
  let obs =
    SelfObserverState(
      check_count: 1,
      match_count: 0,
      mismatch_count: 1,
      last_check_timestamp: 1,
      mismatches: [
        TruthMismatch(
          value_id: "I-03:dark_cockpit_mode",
          expected: "not dark",
          actual: "dark",
          severity: Critical,
        ),
      ],
    )
  worst_severity(obs) |> should.equal(Critical)
}

pub fn worst_severity_picks_highest_test() {
  let obs =
    SelfObserverState(
      check_count: 2,
      match_count: 0,
      mismatch_count: 2,
      last_check_timestamp: 2,
      mismatches: [
        TruthMismatch(
          value_id: "I-09:antibodies",
          expected: "3",
          actual: "0",
          severity: Medium,
        ),
        TruthMismatch(
          value_id: "I-04:container_geometry",
          expected: "container ≥ healthy",
          actual: "5 < 10",
          severity: High,
        ),
      ],
    )
  worst_severity(obs) |> should.equal(High)
}

// =============================================================================
// Helpers
// =============================================================================

fn list_any(items: List(a), pred: fn(a) -> Bool) -> Bool {
  case items {
    [] -> False
    [h, ..rest] ->
      case pred(h) {
        True -> True
        False -> list_any(rest, pred)
      }
  }
}

fn string_contains_check(actual: String, needle: String) -> Nil {
  string.contains(actual, needle)
  |> should.be_true()
}
