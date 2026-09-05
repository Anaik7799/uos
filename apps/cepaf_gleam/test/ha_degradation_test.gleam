/// HA Degradation FSM tests — F11 Formal Graceful Degradation Levels
/// SC-SIL4-001, SC-HA-001, SC-FUNC-001, SC-FUNC-003
/// Layer: L4_SYSTEM
import cepaf_gleam/ha/degradation.{
  DegradedService, EmergencyMode, FullOperation, SafeState,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// C1: init state
// ---------------------------------------------------------------------------

pub fn init_level_is_full_operation_test() {
  degradation.init().level |> should.equal(FullOperation)
}

pub fn init_has_twelve_active_functions_test() {
  list.length(degradation.init().active_functions) |> should.equal(12)
}

pub fn init_has_zero_disabled_functions_test() {
  list.length(degradation.init().disabled_functions) |> should.equal(0)
}

pub fn init_timestamp_is_zero_test() {
  degradation.init().since_timestamp |> should.equal(0)
}

// ---------------------------------------------------------------------------
// C2: degrade transitions
// ---------------------------------------------------------------------------

pub fn degrade_full_to_degraded_test() {
  let s = degradation.init() |> degradation.degrade("test")
  s.level |> should.equal(DegradedService)
}

pub fn degrade_degraded_to_emergency_test() {
  let s =
    degradation.init()
    |> degradation.degrade("step1")
    |> degradation.degrade("step2")
  s.level |> should.equal(EmergencyMode)
}

pub fn degrade_emergency_to_safe_test() {
  let s =
    degradation.init()
    |> degradation.degrade("a")
    |> degradation.degrade("b")
    |> degradation.degrade("c")
  s.level |> should.equal(SafeState)
}

pub fn degrade_safe_stays_safe_test() {
  let s =
    degradation.init()
    |> degradation.degrade("a")
    |> degradation.degrade("b")
    |> degradation.degrade("c")
    |> degradation.degrade("d")
  s.level |> should.equal(SafeState)
}

// ---------------------------------------------------------------------------
// C3: recover transitions
// ---------------------------------------------------------------------------

pub fn recover_safe_to_emergency_test() {
  let s =
    degradation.init()
    |> degradation.degrade("a")
    |> degradation.degrade("b")
    |> degradation.degrade("c")
    |> degradation.recover()
  s.level |> should.equal(EmergencyMode)
}

pub fn recover_emergency_to_degraded_test() {
  let s =
    degradation.init()
    |> degradation.degrade("a")
    |> degradation.degrade("b")
    |> degradation.recover()
  s.level |> should.equal(DegradedService)
}

pub fn recover_degraded_to_full_test() {
  let s =
    degradation.init()
    |> degradation.degrade("a")
    |> degradation.recover()
  s.level |> should.equal(FullOperation)
}

pub fn recover_full_stays_full_test() {
  let s = degradation.init() |> degradation.recover()
  s.level |> should.equal(FullOperation)
}

// ---------------------------------------------------------------------------
// C4: functions_at_level — availability counts
// ---------------------------------------------------------------------------

pub fn full_operation_twelve_active_zero_disabled_test() {
  let #(active, disabled) = degradation.functions_at_level(FullOperation)
  list.length(active) |> should.equal(12)
  list.length(disabled) |> should.equal(0)
}

pub fn degraded_service_eight_active_four_disabled_test() {
  let #(active, disabled) = degradation.functions_at_level(DegradedService)
  list.length(active) |> should.equal(8)
  list.length(disabled) |> should.equal(4)
}

pub fn emergency_mode_four_active_eight_disabled_test() {
  let #(active, disabled) = degradation.functions_at_level(EmergencyMode)
  list.length(active) |> should.equal(4)
  list.length(disabled) |> should.equal(8)
}

pub fn safe_state_zero_active_twelve_disabled_test() {
  let #(active, disabled) = degradation.functions_at_level(SafeState)
  list.length(active) |> should.equal(0)
  list.length(disabled) |> should.equal(12)
}

// ---------------------------------------------------------------------------
// C5: function_available predicate
// ---------------------------------------------------------------------------

pub fn guardian_gate_available_in_emergency_test() {
  let s =
    degradation.init()
    |> degradation.degrade("a")
    |> degradation.degrade("b")
  degradation.function_available(s, "guardian_gate") |> should.be_true()
}

pub fn ui_dashboard_not_available_in_degraded_test() {
  let s = degradation.init() |> degradation.degrade("a")
  degradation.function_available(s, "ui_dashboard") |> should.be_false()
}

pub fn nothing_available_in_safe_state_test() {
  let s =
    degradation.init()
    |> degradation.degrade("a")
    |> degradation.degrade("b")
    |> degradation.degrade("c")
  degradation.function_available(s, "guardian_gate") |> should.be_false()
  degradation.function_available(s, "nif_pipeline") |> should.be_false()
}

// ---------------------------------------------------------------------------
// C6: level ordering and labels
// ---------------------------------------------------------------------------

pub fn level_to_int_ordering_test() {
  degradation.level_to_int(FullOperation) |> should.equal(0)
  degradation.level_to_int(DegradedService) |> should.equal(1)
  degradation.level_to_int(EmergencyMode) |> should.equal(2)
  degradation.level_to_int(SafeState) |> should.equal(3)
}

pub fn level_to_string_labels_test() {
  degradation.level_to_string(FullOperation) |> should.equal("FullOperation")
  degradation.level_to_string(DegradedService)
  |> should.equal("DegradedService")
  degradation.level_to_string(EmergencyMode) |> should.equal("EmergencyMode")
  degradation.level_to_string(SafeState) |> should.equal("SafeState")
}

// ---------------------------------------------------------------------------
// C7: JSON serialisation
// ---------------------------------------------------------------------------

pub fn to_json_contains_level_key_test() {
  let json_str = degradation.init() |> degradation.to_json()
  string.contains(json_str, "\"level\"") |> should.be_true()
}

pub fn to_json_full_operation_has_correct_level_test() {
  let json_str = degradation.init() |> degradation.to_json()
  string.contains(json_str, "FullOperation") |> should.be_true()
}

pub fn to_json_safe_state_has_zero_active_test() {
  let json_str =
    degradation.init()
    |> degradation.degrade("a")
    |> degradation.degrade("b")
    |> degradation.degrade("c")
    |> degradation.to_json()
  string.contains(json_str, "\"active_count\":0") |> should.be_true()
  string.contains(json_str, "\"disabled_count\":12") |> should.be_true()
}

pub fn to_json_contains_reason_test() {
  let json_str =
    degradation.init()
    |> degradation.degrade("disk_full")
    |> degradation.to_json()
  string.contains(json_str, "disk_full") |> should.be_true()
}
