/// QoS Policy Engine Tests — traffic class admission and enforcement (SC-HA-001)
///
/// 15 tests covering: engine_new, default_rules, admit_flow, remove_flow,
/// enforce, total_cpu_usage, flow_count, traffic_class_to_string, summary.
///
/// Layer: L4_SYSTEM
/// STAMP: SC-HA-001, SC-BIO-EVO-001, SC-MUDA-001
///
/// "Do nothing which is of no use." — Miyamoto Musashi
import cepaf_gleam/ha/qos_policy.{
  type TrafficClass, ActiveFlow, Admit, Batch, BestEffort, Critical, Interactive,
  Preempt, Reject, Throttle, admit_flow, default_rules, enforce, engine_new,
  flow_count, remove_flow, summary, total_cpu_usage, traffic_class_to_string,
}
import gleam/list
import gleeunit/should

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn make_flow(id: String, tc: TrafficClass, cpu: Float) {
  ActiveFlow(
    id: id,
    traffic_class: tc,
    cpu_usage: cpu,
    memory_usage: 0.0,
    started_at: 0,
  )
}

// ===========================================================================
// 1. engine_new / default_rules
// ===========================================================================

pub fn engine_new_starts_with_no_flows_test() {
  let engine = engine_new(default_rules())
  flow_count(engine) |> should.equal(0)
}

pub fn default_rules_has_four_entries_test() {
  list.length(default_rules()) |> should.equal(4)
}

pub fn default_rules_includes_critical_class_test() {
  let rules = default_rules()
  let has_critical = list.any(rules, fn(r) { r.traffic_class == Critical })
  has_critical |> should.be_true()
}

// ===========================================================================
// 2. admit_flow — success path
// ===========================================================================

pub fn admit_flow_returns_admit_decision_test() {
  let engine = engine_new(default_rules())
  let flow = make_flow("f-001", Critical, 0.1)
  let #(_, decision) = admit_flow(engine, flow)
  case decision {
    Admit(_) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn admit_flow_adds_flow_to_engine_test() {
  let engine = engine_new(default_rules())
  let flow = make_flow("f-002", Interactive, 0.05)
  let #(new_engine, _) = admit_flow(engine, flow)
  flow_count(new_engine) |> should.equal(1)
}

pub fn admit_flow_reject_when_no_capacity_test() {
  let engine = engine_new(default_rules())
  // Exceed total CPU by trying to admit a flow larger than 100%
  let huge_flow = make_flow("f-big", BestEffort, 1.5)
  let #(_, decision) = admit_flow(engine, huge_flow)
  case decision {
    Reject(_) -> should.be_true(True)
    Preempt(_) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

// ===========================================================================
// 3. remove_flow
// ===========================================================================

pub fn remove_flow_decrements_count_test() {
  let engine = engine_new(default_rules())
  let flow = make_flow("f-003", Batch, 0.1)
  let #(e1, _) = admit_flow(engine, flow)
  let e2 = remove_flow(e1, "f-003")
  flow_count(e2) |> should.equal(0)
}

pub fn remove_flow_on_empty_engine_is_safe_test() {
  let engine = engine_new(default_rules())
  let e2 = remove_flow(engine, "nonexistent")
  flow_count(e2) |> should.equal(0)
}

// ===========================================================================
// 4. total_cpu_usage
// ===========================================================================

pub fn total_cpu_usage_zero_when_no_flows_test() {
  let engine = engine_new(default_rules())
  total_cpu_usage(engine) |> should.equal(0.0)
}

pub fn total_cpu_usage_sums_all_flows_test() {
  let engine = engine_new(default_rules())
  let f1 = make_flow("f-004", Critical, 0.1)
  let f2 = make_flow("f-005", Interactive, 0.2)
  let #(e1, _) = admit_flow(engine, f1)
  let #(e2, _) = admit_flow(e1, f2)
  let usage = total_cpu_usage(e2)
  { usage >. 0.29 && usage <. 0.31 } |> should.be_true()
}

// ===========================================================================
// 5. enforce
// ===========================================================================

pub fn enforce_returns_empty_decisions_when_all_within_limits_test() {
  let engine = engine_new(default_rules())
  let flow = make_flow("f-006", Critical, 0.1)
  let #(e1, _) = admit_flow(engine, flow)
  let #(_, decisions) = enforce(e1)
  list.length(decisions) |> should.equal(0)
}

pub fn enforce_throttles_flow_exceeding_class_limit_test() {
  let engine = engine_new(default_rules())
  // BestEffort max_cpu_pct = 10, so 0.5 (50%) should exceed it
  let flow = make_flow("f-007", BestEffort, 0.5)
  let #(e1, _) = admit_flow(engine, flow)
  let #(_, decisions) = enforce(e1)
  let has_throttle =
    list.any(decisions, fn(d) {
      case d {
        Throttle(_) -> True
        _ -> False
      }
    })
  has_throttle |> should.be_true()
}

// ===========================================================================
// 6. traffic_class_to_string
// ===========================================================================

pub fn traffic_class_to_string_critical_test() {
  traffic_class_to_string(Critical) |> should.equal("critical")
}

pub fn traffic_class_to_string_best_effort_test() {
  traffic_class_to_string(BestEffort) |> should.equal("best_effort")
}

// ===========================================================================
// 7. summary
// ===========================================================================

pub fn summary_non_empty_test() {
  let engine = engine_new(default_rules())
  let s = summary(engine)
  { s != "" } |> should.be_true()
}
