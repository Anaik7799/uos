/// NET-SLICE-1 Network Slicing Registry — 15-test suite
/// Layer: L6_ECOSYSTEM
/// STAMP: SC-ZMOF-001, SC-ZMOF-COMMS-001, SC-HA-001, SC-MUDA-001
///
/// Covers:
///   registry construction + default QoS               (NS-1)
///   create_slice upsert behaviour                      (NS-2)
///   activate / deactivate lifecycle                    (NS-3)
///   assign_topic to existing matching slice            (NS-4)
///   assign_topic fallback to highest-priority slice    (NS-5)
///   assign_topic CreateNew when no slice qualifies     (NS-6)
///   assign_topic Reject when min_priority > 100        (NS-7)
///   slice_count / active_slices queries                (NS-8)
///   summary string content                             (NS-9)
///   reliability_to_string ADT coverage                 (NS-10)
///   pre-built QoS factories                            (NS-11)
import cepaf_gleam/ha/network_slicing.{
  Assign, BestEffort, CreateNew, Guaranteed, Lossy, QosPolicy, Reject,
  activate_slice, active_slices, assign_topic, control_plane_qos, create_slice,
  deactivate_slice, default_qos, health_qos, registry_new, reliability_to_string,
  slice_count, summary, telemetry_qos,
}
import gleam/list
import gleam/string
import gleeunit/should

// ===========================================================================
// registry_new and default_qos (NS-1)
// ===========================================================================

pub fn registry_new_starts_empty_test() {
  let r = registry_new()
  slice_count(r) |> should.equal(0)
}

pub fn default_qos_priority_is_20_test() {
  let q = default_qos()
  q.priority |> should.equal(20)
}

pub fn default_qos_reliability_is_best_effort_test() {
  let q = default_qos()
  case q.reliability {
    BestEffort -> should.be_true(True)
    _ -> should.fail()
  }
}

// ===========================================================================
// create_slice upsert (NS-2)
// ===========================================================================

pub fn create_slice_adds_to_registry_test() {
  let r =
    registry_new()
    |> create_slice("ctrl", ["indrajaal/l0/**"], control_plane_qos())
  slice_count(r) |> should.equal(1)
}

pub fn create_slice_upsert_keeps_count_stable_test() {
  let r =
    registry_new()
    |> create_slice("ctrl", ["indrajaal/l0/**"], control_plane_qos())
    |> create_slice(
      "ctrl",
      ["indrajaal/l0/**", "indrajaal/l1/**"],
      control_plane_qos(),
    )
  slice_count(r) |> should.equal(1)
}

pub fn create_slice_two_distinct_ids_test() {
  let r =
    registry_new()
    |> create_slice("ctrl", ["indrajaal/l0/**"], control_plane_qos())
    |> create_slice("telem", ["indrajaal/otel/**"], telemetry_qos())
  slice_count(r) |> should.equal(2)
}

// ===========================================================================
// activate / deactivate lifecycle (NS-3)
// ===========================================================================

pub fn new_slice_is_active_test() {
  let r =
    registry_new()
    |> create_slice("ctrl", ["indrajaal/l0/**"], control_plane_qos())
  list.length(active_slices(r)) |> should.equal(1)
}

pub fn deactivate_removes_from_active_slices_test() {
  let r =
    registry_new()
    |> create_slice("ctrl", ["indrajaal/l0/**"], control_plane_qos())
    |> deactivate_slice("ctrl")
  list.length(active_slices(r)) |> should.equal(0)
}

pub fn activate_restores_slice_test() {
  let r =
    registry_new()
    |> create_slice("ctrl", ["indrajaal/l0/**"], control_plane_qos())
    |> deactivate_slice("ctrl")
    |> activate_slice("ctrl")
  list.length(active_slices(r)) |> should.equal(1)
}

// ===========================================================================
// assign_topic (NS-4, NS-5, NS-6, NS-7)
// ===========================================================================

pub fn assign_topic_to_matching_slice_test() {
  let r =
    registry_new()
    |> create_slice("ctrl", ["indrajaal/l0"], control_plane_qos())
  let #(_, decision) = assign_topic(r, "indrajaal/l0/const/guardian", 0)
  case decision {
    Assign(id) -> id |> should.equal("ctrl")
    _ -> should.fail()
  }
}

pub fn assign_topic_falls_back_to_highest_priority_test() {
  let r =
    registry_new()
    |> create_slice("low", ["other/**"], telemetry_qos())
    |> create_slice(
      "hi",
      ["different/**"],
      QosPolicy(
        name: "hi",
        priority: 80,
        max_bandwidth_kbps: 512,
        latency_budget_ms: 100,
        reliability: Guaranteed,
      ),
    )
  let #(_, decision) = assign_topic(r, "indrajaal/l5/cog/trace", 0)
  case decision {
    Assign(id) -> id |> should.equal("hi")
    _ -> should.fail()
  }
}

pub fn assign_topic_create_new_when_no_slice_meets_priority_test() {
  let r =
    registry_new()
    |> create_slice("telem", ["indrajaal/otel/**"], telemetry_qos())
  let #(_, decision) = assign_topic(r, "new/topic", 90)
  case decision {
    CreateNew(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn assign_topic_reject_when_min_priority_above_100_test() {
  let r = registry_new()
  let #(_, decision) = assign_topic(r, "any/topic", 101)
  case decision {
    Reject(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn assign_topic_adds_topic_to_slice_test() {
  let r =
    registry_new()
    |> create_slice("ctrl", ["indrajaal/l0/**"], control_plane_qos())
  let #(updated, _) = assign_topic(r, "indrajaal/l0/const/new_topic", 0)
  let active = active_slices(updated)
  let topic_count =
    list.fold(active, 0, fn(acc, s) { acc + list.length(s.topics) })
  let ok = topic_count > 1
  ok |> should.be_true
}

// ===========================================================================
// summary (NS-9)
// ===========================================================================

pub fn summary_contains_total_count_test() {
  let r =
    registry_new()
    |> create_slice("ctrl", [], control_plane_qos())
    |> create_slice("telem", [], telemetry_qos())
  let s = summary(r)
  string.contains(s, "total=2") |> should.be_true
}

pub fn summary_contains_active_count_test() {
  let r =
    registry_new()
    |> create_slice("ctrl", [], control_plane_qos())
    |> deactivate_slice("ctrl")
    |> create_slice("telem", [], telemetry_qos())
  let s = summary(r)
  string.contains(s, "active=1") |> should.be_true
}

// ===========================================================================
// reliability_to_string ADT coverage (NS-10)
// ===========================================================================

pub fn reliability_guaranteed_to_string_test() {
  reliability_to_string(Guaranteed) |> should.equal("guaranteed")
}

pub fn reliability_best_effort_to_string_test() {
  reliability_to_string(BestEffort) |> should.equal("best-effort")
}

pub fn reliability_lossy_to_string_test() {
  reliability_to_string(Lossy) |> should.equal("lossy")
}

// ===========================================================================
// Pre-built QoS factories (NS-11)
// ===========================================================================

pub fn control_plane_qos_is_guaranteed_test() {
  let q = control_plane_qos()
  case q.reliability {
    Guaranteed -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn health_qos_priority_above_70_test() {
  let q = health_qos()
  let ok = q.priority >= 70
  ok |> should.be_true
}

pub fn telemetry_qos_priority_below_30_test() {
  let q = telemetry_qos()
  let ok = q.priority < 30
  ok |> should.be_true
}
