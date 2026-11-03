import cepaf_gleam/harness/agent_capabilities as a
import cepaf_gleam/harness/agent_ecology
import cepaf_gleam/harness/agent_meta_policy as m
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleeunit/should

fn now() -> m.ClockData {
  m.ClockData("host-data", "boot-data", "vm-data", 100, -200)
}

pub fn h_and_l_coordinates_are_independent_data_test() {
  list.length(m.roles()) |> should.equal(4)
  list.each(m.roles(), fn(role) {
    list.each([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], fn(n) {
      let assert Ok(l) = m.layer(n)
      m.layer_number(l) |> should.equal(n)
      { m.role_depth(role) <= 3 } |> should.be_true
    })
  })
  m.layer(-1) |> result.is_error |> should.be_true
  m.layer(10) |> result.is_error |> should.be_true
  m.effect_authority() |> should.be_false
  string.contains(agent_ecology.format_ecology_summary(), m.summary())
  |> should.be_true
}

pub fn configurable_capacity_matches_independent_level_expansion_test() {
  list.each([0, 1, 2, 3], fn(d) {
    list.each([1, 2, 3, 4, 8], fn(f) {
      let assert Ok(c) = m.config(d, f, 1024, 1024)
      // Independent explicit breadth levels, no production recursion.
      let levels = [1, f, f * f, f * f * f]
      let expected =
        list.take(levels, d + 1) |> list.fold(0, fn(a, b) { a + b })
      m.tree_capacity(c) |> should.equal(expected)
      m.capacity(c, Some(1024), Some(1024)) |> should.equal(Ok(expected))
    })
  })
  m.tree_capacity(m.default_config()) |> should.equal(15)
  let assert Ok(wider) = m.config(3, 3, 40, 64)
  m.tree_capacity(wider) |> should.equal(40)
  m.capacity(wider, Some(9), Some(7)) |> should.equal(Ok(7))
  m.capacity(wider, Some(0), Some(7)) |> should.equal(Ok(0))
  m.capacity(wider, None, Some(7)) |> result.is_error |> should.be_true
  m.config(4, 2, 4, 64) |> result.is_error |> should.be_true
  m.config(3, 9, 4, 64) |> result.is_error |> should.be_true
}

pub fn immutable_owner_epoch_revision_fence_test() {
  let assert Ok(s) = m.new(m.default_config(), "owner-data", 7)
  let f = m.fence_data(s)
  let assert Ok(next) = m.note(s, f, "source-observation-data")
  m.fence_data(next).revision |> should.equal(1)
  m.latest_note(s) |> should.equal(None)
  m.latest_note(next) |> should.equal(Some("source-observation-data"))
  m.note(next, f, "stale") |> result.is_error |> should.be_true
  m.check_fence(next, m.FenceData("other", 7, 1))
  |> result.is_error
  |> should.be_true
  m.check_fence(next, m.FenceData("owner-data", 8, 1))
  |> result.is_error
  |> should.be_true
  m.note(next, m.fence_data(next), "source-observation-data")
  |> result.is_error
  |> should.be_true
}

fn root() -> m.State {
  let assert Ok(c) = m.config(3, 2, 4, 64)
  let assert Ok(s) = m.new(c, "owner-data", 1)
  let assert Ok(s) =
    m.observe_capacity(
      s,
      m.fence_data(s),
      m.CapacityObservationData(8, 8, now(), 900, -150),
    )
  let assert Ok(s) =
    m.reserve_root(s, m.fence_data(s), "root", a.Codex, Some(8), Some(8), now())
  s
}

pub fn reservation_consumes_root_global_and_parent_slots_together_test() {
  let s = running_root()
  m.used(s) |> should.equal(1)
  let assert Ok(s) =
    m.reserve_child(
      s,
      m.fence_data(s),
      "root",
      "left",
      a.Pi,
      Some(8),
      Some(8),
      now(),
    )
  let assert Ok(s) =
    m.reserve_child(
      s,
      m.fence_data(s),
      "root",
      "right",
      a.Agy,
      Some(8),
      Some(8),
      now(),
    )
  m.used(s) |> should.equal(3)
  m.children_used(s, "root") |> should.equal(2)
  m.reserve_child(
    s,
    m.fence_data(s),
    "root",
    "third",
    a.Claude,
    Some(8),
    Some(8),
    now(),
  )
  |> result.is_error
  |> should.be_true
  let assert Ok(s) =
    m.bind_scope(
      s,
      m.fence_data(s),
      "left",
      scope("left-worker", "left-session"),
    )
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "left", m.BeginStart, now())
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "left", m.ObserveRunning, now())
  let assert Ok(full) =
    m.reserve_child(
      s,
      m.fence_data(s),
      "left",
      "worker",
      a.Claude,
      Some(8),
      Some(8),
      now(),
    )
  m.used(full) |> should.equal(4)
  m.reserve_child(
    full,
    m.fence_data(full),
    "right",
    "over",
    a.Claude,
    Some(8),
    Some(8),
    now(),
  )
  |> result.is_error
  |> should.be_true
  m.used(s) |> should.equal(3)
  m.reserve_root(s, m.fence_data(s), "again", a.Codex, Some(8), Some(8), now())
  |> result.is_error
  |> should.be_true
  m.reserve_child(
    s,
    m.fence_data(s),
    "left",
    "root",
    a.Claude,
    Some(8),
    Some(8),
    now(),
  )
  |> result.is_error
  |> should.be_true
}

fn scope(worker: String, session: String) -> m.ScopeData {
  let assert Ok(l) = m.layer(6)
  m.ScopeData(
    "plan",
    worker,
    worker,
    session,
    1,
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    [a.KnowledgeRead],
    [l],
    1000,
    -100,
  )
}

pub fn child_scope_attenuates_and_cannot_overwrite_test() {
  let s = root()
  let parent = scope("root-worker", "root-session")
  let assert Ok(s) = m.bind_scope(s, m.fence_data(s), "root", parent)
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "root", m.BeginStart, now())
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "root", m.ObserveRunning, now())
  let assert Ok(s) =
    m.reserve_child(
      s,
      m.fence_data(s),
      "root",
      "child",
      a.Pi,
      Some(8),
      Some(8),
      now(),
    )
  let child = scope("child-worker", "child-session")
  m.bind_scope(
    s,
    m.fence_data(s),
    "child",
    m.ScopeData(..child, capabilities: [a.ToolExecution]),
  )
  |> result.is_error
  |> should.be_true
  m.bind_scope(
    s,
    m.fence_data(s),
    "child",
    m.ScopeData(..child, expires_mono: 0),
  )
  |> result.is_error
  |> should.be_true
  m.bind_scope(s, m.fence_data(s), "child", parent)
  |> result.is_error
  |> should.be_true
  let assert Ok(next) = m.bind_scope(s, m.fence_data(s), "child", child)
  m.bind_scope(next, m.fence_data(next), "child", child)
  |> result.is_error
  |> should.be_true
  m.used(next) |> should.equal(2)
}

fn running_root() -> m.State {
  let s = root()
  let assert Ok(s) =
    m.bind_scope(
      s,
      m.fence_data(s),
      "root",
      scope("root-worker", "root-session"),
    )
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "root", m.BeginStart, now())
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "root", m.ObserveRunning, now())
  s
}

pub fn disjoint_lifecycle_keeps_every_uncertain_slot_test() {
  list.each(
    [m.Reserved, m.Starting, m.Running, m.Cancelling, m.CleanupUnknown],
    fn(p) { m.active(p) |> should.be_true },
  )
  m.active(m.Released) |> should.be_false
  let reserved = root()
  m.lifecycle(reserved, m.fence_data(reserved), "root", m.BeginStart, now())
  |> result.is_error
  |> should.be_true
  let running = running_root()
  let assert Ok(cancelling) =
    m.lifecycle(
      running,
      m.fence_data(running),
      "root",
      m.RequestCancellation,
      now(),
    )
  let assert Ok(unknown) =
    m.lifecycle(
      cancelling,
      m.fence_data(cancelling),
      "root",
      m.ObserveCleanupUnknown,
      now(),
    )
  list.each([reserved, running, cancelling, unknown], fn(s) {
    m.used(s) |> should.equal(1)
  })
  m.lifecycle(unknown, m.fence_data(unknown), "root", m.BeginStart, now())
  |> result.is_error
  |> should.be_true
}

pub fn cleanup_releases_data_capacity_without_refunding_unknown_cost_test() {
  let s = root()
  let assert Ok(s) =
    m.record_liability(
      s,
      m.fence_data(s),
      "root",
      "ledger-ref-data",
      250_000_000,
    )
  let assert Ok(s) = m.record_cost_unknown(s, m.fence_data(s), "root")
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "root", m.RequestCancellation, now())
  let assert Ok(unknown) =
    m.lifecycle(s, m.fence_data(s), "root", m.ObserveCleanupUnknown, now())
  m.used(unknown) |> should.equal(1)
  m.retained_liability(unknown) |> should.equal(250_000_000)
  let assert Ok(released) =
    m.record_cleanup(
      unknown,
      m.fence_data(unknown),
      "root",
      "untrusted-reap-ref",
    )
  m.used(released) |> should.equal(0)
  m.retained_liability(released) |> should.equal(250_000_000)
  m.record_cleanup(released, m.fence_data(released), "root", "again")
  |> result.is_error
  |> should.be_true
  m.reserve_root(
    released,
    m.fence_data(released),
    "new-root",
    a.Codex,
    Some(8),
    Some(8),
    now(),
  )
  |> result.is_error
  |> should.be_true
  m.record_liability(released, m.fence_data(released), "root", "new", 1)
  |> result.is_error
  |> should.be_true
}

fn running_child(s: m.State, parent: String, id: String) -> m.State {
  let assert Ok(s) =
    m.reserve_child(
      s,
      m.fence_data(s),
      parent,
      id,
      a.Pi,
      Some(8),
      Some(8),
      now(),
    )
  let assert Ok(s) =
    m.bind_scope(s, m.fence_data(s), id, scope(id, id <> "-session"))
  let assert Ok(s) = m.lifecycle(s, m.fence_data(s), id, m.BeginStart, now())
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), id, m.ObserveRunning, now())
  s
}

pub fn review_custody_data_has_separate_leaf_route_and_immutable_reference_test() {
  let s =
    running_root()
    |> running_child("root", "coordinator")
    |> running_child("coordinator", "implementer")
  let c = scope("reviewer", "review-session")
  let custody =
    m.CustodyData(
      "custodian",
      "custody-session",
      "reviewer",
      "review-session",
      c.candidate,
    )
  let assert Ok(s) =
    m.assign_review(
      s,
      m.fence_data(s),
      "implementer",
      "review",
      a.Claude,
      c,
      custody,
      Some(8),
      Some(8),
      now(),
    )
  m.used(s) |> should.equal(4)
  m.lifecycle(s, m.fence_data(s), "review", m.BeginStart, now())
  |> result.is_error
  |> should.be_true
  let assert Ok(s) =
    m.review_lifecycle(
      s,
      m.fence_data(s),
      "review",
      custody,
      m.BeginStart,
      now(),
    )
  let assert Ok(s) =
    m.review_lifecycle(
      s,
      m.fence_data(s),
      "review",
      custody,
      m.ObserveRunning,
      now(),
    )
  let assert Ok(s) =
    m.record_review(
      s,
      m.fence_data(s),
      "review",
      custody,
      c.candidate,
      "untrusted-review-ref",
    )
  m.record_review(
    s,
    m.fence_data(s),
    "review",
    custody,
    c.candidate,
    "overwrite",
  )
  |> result.is_error
  |> should.be_true
  m.reserve_child(
    s,
    m.fence_data(s),
    "review",
    "extra",
    a.Codex,
    Some(8),
    Some(8),
    now(),
  )
  |> result.is_error
  |> should.be_true
  m.effect_authority() |> should.be_false
}

pub fn stopped_parent_cannot_reserve_and_refusal_preserves_snapshot_test() {
  let s = running_root()
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "root", m.RequestCancellation, now())
  let before = m.nodes(s)
  m.reserve_child(
    s,
    m.fence_data(s),
    "root",
    "blocked",
    a.Pi,
    Some(8),
    Some(8),
    now(),
  )
  |> result.is_error
  |> should.be_true
  let assert Ok(s) =
    m.record_cleanup(s, m.fence_data(s), "root", "cleanup-data")
  m.reserve_child(
    s,
    m.fence_data(s),
    "root",
    "blocked",
    a.Pi,
    Some(8),
    Some(8),
    now(),
  )
  |> result.is_error
  |> should.be_true
  list.length(before) |> should.equal(list.length(m.nodes(s)))
  m.revision_capacity(m.FenceData("data", 1, 999_999_997), 3) |> should.be_true
  m.revision_capacity(m.FenceData("data", 1, 999_999_998), 3) |> should.be_false
  m.revision_capacity(m.FenceData("data", 1, 1_000_000_000), 1)
  |> should.be_false
}

pub fn dual_clock_capacity_expiry_and_local_high_water_test() {
  let s = running_root()
  let later = m.ClockData(..now(), utc: 110, mono: -190)
  let assert Ok(next) =
    m.reserve_child(
      s,
      m.fence_data(s),
      "root",
      "child",
      a.Pi,
      Some(8),
      Some(8),
      later,
    )
  m.check_clock(next, m.ClockData(..now(), utc: 105, mono: -195))
  |> result.is_error
  |> should.be_true
  m.reserve_child(
    next,
    m.fence_data(next),
    "root",
    "stale",
    a.Pi,
    Some(8),
    Some(8),
    m.ClockData(..later, mono: -150),
  )
  |> result.is_error
  |> should.be_true
  m.inspect_intent(s, m.fence_data(s), "root", m.ClockData(..now(), utc: 1000))
  |> result.is_error
  |> should.be_true
  m.inspect_intent(s, m.fence_data(s), "root", m.ClockData(..now(), mono: -100))
  |> result.is_error
  |> should.be_true
  m.check_clock(s, m.ClockData(..now(), domain: "other-vm"))
  |> result.is_error
  |> should.be_true
  m.inspect_intent(s, m.fence_data(s), "root", now())
  |> should.equal(Ok(a.AdmissionRequired))
}

pub fn execution_hold_preserves_independently_routed_review_data_test() {
  let s =
    running_root()
    |> running_child("root", "coordinator")
    |> running_child("coordinator", "implementer")
  let c = scope("reviewer", "review-session")
  let custody =
    m.CustodyData(
      "custodian",
      "custody-session",
      "reviewer",
      "review-session",
      c.candidate,
    )
  let assert Ok(s) =
    m.assign_review(
      s,
      m.fence_data(s),
      "implementer",
      "review",
      a.Claude,
      c,
      custody,
      Some(8),
      Some(8),
      now(),
    )
  let assert Ok(held) =
    m.hold_execution(s, m.fence_data(s), "root", "scope-ended-data")
  m.used(held) |> should.equal(4)
  list.each(m.nodes(held), fn(n) {
    n.phase
    |> should.equal(case n.role {
      m.H3Review -> m.Reserved
      _ -> m.Cancelling
    })
  })
  let assert Ok(held) =
    m.review_lifecycle(
      held,
      m.fence_data(held),
      "review",
      custody,
      m.BeginStart,
      now(),
    )
  m.inspect_intent(held, m.fence_data(held), "implementer", now())
  |> result.is_error
  |> should.be_true
  m.used(held) |> should.equal(4)
}

// Independent direct interpretation; no production occupancy helper calls.
fn oracle_count(rows: List(m.NodeData), parent: Option(String)) -> Int {
  list.fold(rows, 0, fn(total, n) {
    let counted = case n.phase {
      m.Reserved | m.Starting | m.Running | m.Cancelling | m.CleanupUnknown -> 1
      m.Released -> 0
    }
    total
    + case parent {
      None -> counted
      Some(id) ->
        case n.parent == Some(id) {
          True -> counted
          False -> 0
        }
    }
  })
}

fn check_counts(s: m.State) {
  let v = m.snapshot(s)
  v.capacity_used |> should.equal(oracle_count(v.nodes, None))
  { v.capacity_used <= v.config.global_slots } |> should.be_true
  { v.capacity_used <= v.config.tree_bound } |> should.be_true
  list.each(v.nodes, fn(n) {
    m.children_used(s, n.id) |> should.equal(oracle_count(v.nodes, Some(n.id)))
    { m.children_used(s, n.id) <= v.config.fanout } |> should.be_true
  })
  v.authority |> should.equal(a.AdmissionRequired)
}

pub fn ordinary_full_hierarchy_hold_cleanup_trace_matches_count_oracle_test() {
  let s0 = running_root()
  let s1 = running_child(s0, "root", "coordinator")
  let s2 = running_child(s1, "coordinator", "implementer")
  let c = scope("reviewer", "review-session")
  let custody =
    m.CustodyData(
      "custodian",
      "custody-session",
      "reviewer",
      "review-session",
      c.candidate,
    )
  let assert Ok(s3) =
    m.assign_review(
      s2,
      m.fence_data(s2),
      "implementer",
      "review",
      a.Claude,
      c,
      custody,
      Some(8),
      Some(8),
      now(),
    )
  let assert Ok(s4) =
    m.review_lifecycle(
      s3,
      m.fence_data(s3),
      "review",
      custody,
      m.BeginStart,
      now(),
    )
  let assert Ok(s5) =
    m.review_lifecycle(
      s4,
      m.fence_data(s4),
      "review",
      custody,
      m.ObserveRunning,
      now(),
    )
  let assert Ok(s6) =
    m.record_review(
      s5,
      m.fence_data(s5),
      "review",
      custody,
      c.candidate,
      "review-reference-data",
    )
  let assert Ok(s7) =
    m.hold_execution(s6, m.fence_data(s6), "root", "ordinary-completion-data")
  m.record_cleanup(
    s7,
    m.fence_data(s7),
    "implementer",
    "cannot-release-before-review",
  )
  |> result.is_error
  |> should.be_true
  let assert Ok(s8) =
    m.review_lifecycle(
      s7,
      m.fence_data(s7),
      "review",
      custody,
      m.RequestCancellation,
      now(),
    )
  let assert Ok(s9) =
    m.review_cleanup(
      s8,
      m.fence_data(s8),
      "review",
      custody,
      "review-cleanup-data",
    )
  let assert Ok(s10) =
    m.record_cleanup(s9, m.fence_data(s9), "implementer", "worker-cleanup-data")
  let assert Ok(s11) =
    m.record_cleanup(
      s10,
      m.fence_data(s10),
      "coordinator",
      "subsystem-cleanup-data",
    )
  let assert Ok(s12) =
    m.record_cleanup(s11, m.fence_data(s11), "root", "root-cleanup-data")
  list.each(
    [s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12],
    check_counts,
  )
  m.used(s12) |> should.equal(0)
  list.length(m.nodes(s12)) |> should.equal(4)
  let assert Ok(review) = list.find(m.nodes(s12), fn(n) { n.id == "review" })
  review.review_receipt |> should.equal(Some("review-reference-data"))
  m.source_attribution(review)
  |> should.equal(a.InferenceUnspecified(a.ClaudeRuntime))
}

pub fn paid_data_requires_liability_and_never_rearms_unknown_test() {
  let s = root()
  let paid =
    m.ScopeData(..scope("root-worker", "root-session"), capabilities: [
      a.AdvisoryCompletion,
    ])
  let assert Ok(s) = m.bind_scope(s, m.fence_data(s), "root", paid)
  m.lifecycle(s, m.fence_data(s), "root", m.BeginStart, now())
  |> result.is_error
  |> should.be_true
  let assert Ok(s) =
    m.record_liability(
      s,
      m.fence_data(s),
      "root",
      "ledger-liability-data",
      250_000_000,
    )
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "root", m.BeginStart, now())
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "root", m.ObserveRunning, now())
  let assert Ok(s) = m.record_cost_unknown(s, m.fence_data(s), "root")
  m.inspect_intent(s, m.fence_data(s), "root", now())
  |> result.is_error
  |> should.be_true
  m.reserve_child(
    s,
    m.fence_data(s),
    "root",
    "retry",
    a.Pi,
    Some(8),
    Some(8),
    now(),
  )
  |> result.is_error
  |> should.be_true
  m.retained_liability(s) |> should.equal(250_000_000)
  check_counts(s)
}

pub fn ecology_shares_meta_view_and_preserves_original_observation_test() {
  let s = running_root()
  let original = m.snapshot(s).observation
  let assert Ok(s) =
    m.reserve_child(
      s,
      m.fence_data(s),
      "root",
      "child",
      a.Agy,
      Some(8),
      Some(8),
      m.ClockData(..now(), utc: 120, mono: -180),
    )
  m.snapshot(s).observation |> should.equal(original)
  m.snapshot(s).checked_at
  |> should.equal(Some(m.ClockData(..now(), utc: 120, mono: -180)))
  string.contains(
    agent_ecology.format_agent_meta(Some(s)),
    "capacity-used DATA: 2",
  )
  |> should.be_true
  string.contains(
    agent_ecology.format_agent_meta(None),
    "runtime owner UNIMPLEMENTED",
  )
  |> should.be_true
  let assert Ok(l9) = agent_ecology.meta_layer(agent_ecology.L9SREHomeostasis)
  m.layer_number(l9) |> should.equal(9)
}

pub fn hold_does_not_depend_on_note_capacity_or_duplicate_reason_test() {
  let s = running_root()
  let labels =
    list.map([0, 1, 2, 3, 4, 5, 6, 7], fn(n) {
      case n {
        0 -> "a"
        1 -> "b"
        2 -> "c"
        3 -> "d"
        4 -> "e"
        5 -> "f"
        6 -> "g"
        _ -> "h"
      }
    })
  let all =
    list.flat_map(labels, fn(a) {
      list.map(["1", "2", "3", "4"], fn(b) { a <> b })
    })
  let filled =
    list.fold(all, s, fn(s, label) {
      let assert Ok(next) = m.note(s, m.fence_data(s), label)
      next
    })
  m.note(filled, m.fence_data(filled), "overflow")
  |> result.is_error
  |> should.be_true
  let assert Ok(held) =
    m.hold_execution(filled, m.fence_data(filled), "root", "a1")
  let assert Ok(held) = m.hold_execution(held, m.fence_data(held), "root", "a1")
  m.snapshot(held).hold_reason |> should.equal(Some("a1"))
  let assert Ok(root) = list.find(m.nodes(held), fn(n) { n.id == "root" })
  root.phase |> should.equal(m.Cancelling)
}

pub fn reported_free_advisory_data_needs_no_invented_positive_liability_test() {
  let s = root()
  let advice =
    m.ScopeData(..scope("root-worker", "root-session"), capabilities: [
      a.AdvisoryCompletion,
    ])
  let assert Ok(s) = m.bind_scope(s, m.fence_data(s), "root", advice)
  let assert Ok(s) =
    m.record_free_cost(
      s,
      m.fence_data(s),
      "root",
      "unverified-fee-free-evidence",
    )
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "root", m.BeginStart, now())
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "root", m.ObserveRunning, now())
  m.inspect_intent(s, m.fence_data(s), "root", now())
  |> should.equal(Ok(a.AdmissionRequired))
  m.retained_liability(s) |> should.equal(0)
  m.snapshot(s).unknown_cost_nodes |> should.equal(0)
  m.record_liability(s, m.fence_data(s), "root", "invented", 1)
  |> result.is_error
  |> should.be_true
  let assert Ok(s) = m.record_cost_unknown(s, m.fence_data(s), "root")
  m.inspect_intent(s, m.fence_data(s), "root", now())
  |> result.is_error
  |> should.be_true
  m.snapshot(s).unknown_cost_nodes |> should.equal(1)
  m.effect_authority() |> should.be_false
}

pub fn formerly_reported_free_unknown_cost_blocks_scaleup_without_claiming_zero_bill_test() {
  let s = root()
  let assert Ok(s) =
    m.bind_scope(
      s,
      m.fence_data(s),
      "root",
      scope("root-worker", "root-session"),
    )
  let assert Ok(s) =
    m.record_free_cost(s, m.fence_data(s), "root", "initial-free-report")
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "root", m.BeginStart, now())
  let assert Ok(s) =
    m.lifecycle(s, m.fence_data(s), "root", m.ObserveRunning, now())
  let assert Ok(s) = m.record_cost_unknown(s, m.fence_data(s), "root")
  m.snapshot(s).unknown_cost_nodes |> should.equal(1)
  m.retained_liability(s) |> should.equal(0)
  m.reserve_child(
    s,
    m.fence_data(s),
    "root",
    "no-scale-up",
    a.Pi,
    Some(8),
    Some(8),
    now(),
  )
  |> result.is_error
  |> should.be_true
  let assert Ok(s) =
    m.hold_execution(s, m.fence_data(s), "root", "cost-unknown-data")
  let assert Ok(s) =
    m.record_cleanup(s, m.fence_data(s), "root", "cleanup-ref-data")
  m.snapshot(s).unknown_cost_nodes |> should.equal(1)
  m.used(s) |> should.equal(0)
}
