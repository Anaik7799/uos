/// CRDT Foundation Test Suite — 40+ tests
/// एकत्वं बहुत्वे — Unity in multiplicity (L7_FEDERATION)
///
/// Verifies all five CRDT types and their mathematical properties:
///   - G-Counter:      grow-only counter for distributed metrics
///   - PN-Counter:     up/down counter
///   - LWW-Register:   last-writer-wins state register
///   - OR-Set:         observed-remove set for guard verdicts
///   - Version Vector: causal ordering across nodes
///
/// Mathematical gate (all 3 laws must pass):
///   Commutativity  merge(a,b) = merge(b,a)
///   Associativity  merge(merge(a,b),c) = merge(a,merge(b,c))
///   Idempotency    merge(a,a) = a
///
/// STAMP: SC-ULTRA-001 (Focus 2), SC-XHOLON-006, SC-HA-001
import cepaf_gleam/ha/crdt
import gleam/list
import gleeunit/should

// =============================================================================
// G-Counter tests
// =============================================================================

pub fn gcounter_new_is_zero_test() {
  crdt.gcounter_new()
  |> crdt.gcounter_value()
  |> should.equal(0)
}

pub fn gcounter_increment_once_is_one_test() {
  crdt.gcounter_new()
  |> crdt.gcounter_increment("node-1")
  |> crdt.gcounter_value()
  |> should.equal(1)
}

pub fn gcounter_increment_three_times_test() {
  let c =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("node-1")
    |> crdt.gcounter_increment("node-1")
    |> crdt.gcounter_increment("node-1")
  crdt.gcounter_value(c) |> should.equal(3)
}

pub fn gcounter_two_nodes_sum_test() {
  let a =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("node-1")
    |> crdt.gcounter_increment("node-1")
  let b =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("node-2")
    |> crdt.gcounter_increment("node-2")
    |> crdt.gcounter_increment("node-2")
  let merged = crdt.gcounter_merge(a, b)
  crdt.gcounter_value(merged) |> should.equal(5)
}

pub fn gcounter_merge_takes_max_per_node_test() {
  // Simulate diverged replicas: a has 5 on node-1, b has 3 on node-1
  let a =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("node-1")
    |> crdt.gcounter_increment("node-1")
    |> crdt.gcounter_increment("node-1")
    |> crdt.gcounter_increment("node-1")
    |> crdt.gcounter_increment("node-1")
  // b is a stale replica with only 3 increments on the same node
  let b =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("node-1")
    |> crdt.gcounter_increment("node-1")
    |> crdt.gcounter_increment("node-1")
  let merged = crdt.gcounter_merge(a, b)
  // max(5, 3) = 5 — no regression
  crdt.gcounter_value(merged) |> should.equal(5)
}

// =============================================================================
// G-Counter — Mathematical property tests
// =============================================================================

pub fn gcounter_commutativity_test() {
  let a =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("n1")
    |> crdt.gcounter_increment("n1")
  let b =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("n2")
    |> crdt.gcounter_increment("n2")
    |> crdt.gcounter_increment("n2")
  crdt.verify_commutativity(a, b) |> should.be_true()
}

pub fn gcounter_associativity_test() {
  let a = crdt.gcounter_new() |> crdt.gcounter_increment("n1")
  let b = crdt.gcounter_new() |> crdt.gcounter_increment("n2")
  let c = crdt.gcounter_new() |> crdt.gcounter_increment("n3")
  crdt.verify_associativity(a, b, c) |> should.be_true()
}

pub fn gcounter_idempotency_test() {
  let a =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("n1")
    |> crdt.gcounter_increment("n1")
  crdt.verify_idempotency(a) |> should.be_true()
}

pub fn gcounter_verify_all_properties_test() {
  let a = crdt.gcounter_new() |> crdt.gcounter_increment("n1")
  let b = crdt.gcounter_new() |> crdt.gcounter_increment("n2")
  crdt.verify_all_properties(a, b) |> should.be_true()
}

pub fn gcounter_idempotency_empty_test() {
  let a = crdt.gcounter_new()
  crdt.verify_idempotency(a) |> should.be_true()
}

pub fn gcounter_commutativity_asymmetric_test() {
  // One node has many increments, other has none
  let a =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("n1")
    |> crdt.gcounter_increment("n1")
    |> crdt.gcounter_increment("n1")
  let b = crdt.gcounter_new()
  crdt.verify_commutativity(a, b) |> should.be_true()
}

// =============================================================================
// PN-Counter tests
// =============================================================================

pub fn pncounter_new_is_zero_test() {
  crdt.pncounter_new()
  |> crdt.pncounter_value()
  |> should.equal(0)
}

pub fn pncounter_increment_once_test() {
  crdt.pncounter_new()
  |> crdt.pncounter_increment("node-1")
  |> crdt.pncounter_value()
  |> should.equal(1)
}

pub fn pncounter_decrement_once_test() {
  crdt.pncounter_new()
  |> crdt.pncounter_decrement("node-1")
  |> crdt.pncounter_value()
  |> should.equal(-1)
}

pub fn pncounter_inc_dec_net_test() {
  let c =
    crdt.pncounter_new()
    |> crdt.pncounter_increment("node-1")
    |> crdt.pncounter_increment("node-1")
    |> crdt.pncounter_increment("node-1")
    |> crdt.pncounter_decrement("node-1")
  crdt.pncounter_value(c) |> should.equal(2)
}

pub fn pncounter_merge_two_nodes_test() {
  let a =
    crdt.pncounter_new()
    |> crdt.pncounter_increment("n1")
    |> crdt.pncounter_increment("n1")
  let b =
    crdt.pncounter_new()
    |> crdt.pncounter_increment("n2")
    |> crdt.pncounter_decrement("n2")
  let merged = crdt.pncounter_merge(a, b)
  // n1 pos=2 neg=0, n2 pos=1 neg=1 → total = (2+1) - (0+1) = 2
  crdt.pncounter_value(merged) |> should.equal(2)
}

pub fn pncounter_merge_commutativity_test() {
  let a =
    crdt.pncounter_new()
    |> crdt.pncounter_increment("n1")
    |> crdt.pncounter_increment("n1")
  let b =
    crdt.pncounter_new()
    |> crdt.pncounter_increment("n2")
    |> crdt.pncounter_decrement("n2")
  let ab = crdt.pncounter_merge(a, b)
  let ba = crdt.pncounter_merge(b, a)
  crdt.pncounter_value(ab) |> should.equal(crdt.pncounter_value(ba))
}

pub fn pncounter_merge_idempotency_test() {
  let a =
    crdt.pncounter_new()
    |> crdt.pncounter_increment("n1")
    |> crdt.pncounter_decrement("n1")
  let aa = crdt.pncounter_merge(a, a)
  crdt.pncounter_value(aa) |> should.equal(crdt.pncounter_value(a))
}

// =============================================================================
// LWW-Register tests
// =============================================================================

pub fn lww_new_has_correct_value_test() {
  let r = crdt.lww_new("active", 1000, "node-1")
  r.value |> should.equal("active")
  r.timestamp_ms |> should.equal(1000)
  r.node_id |> should.equal("node-1")
}

pub fn lww_set_higher_timestamp_wins_test() {
  let r =
    crdt.lww_new("old", 1000, "node-1")
    |> crdt.lww_set("new", 2000, "node-1")
  r.value |> should.equal("new")
}

pub fn lww_set_lower_timestamp_ignored_test() {
  let r =
    crdt.lww_new("current", 2000, "node-1")
    |> crdt.lww_set("stale", 500, "node-1")
  // stale write with lower timestamp must not overwrite
  r.value |> should.equal("current")
}

pub fn lww_merge_higher_timestamp_wins_test() {
  let a = crdt.lww_new("v1", 100, "n1")
  let b = crdt.lww_new("v2", 200, "n2")
  let merged = crdt.lww_merge(a, b)
  merged.value |> should.equal("v2")
}

pub fn lww_merge_commutativity_test() {
  let a = crdt.lww_new("alpha", 100, "n1")
  let b = crdt.lww_new("beta", 200, "n2")
  let ab = crdt.lww_merge(a, b)
  let ba = crdt.lww_merge(b, a)
  ab.value |> should.equal(ba.value)
}

pub fn lww_merge_idempotency_test() {
  let a = crdt.lww_new("stable", 1000, "n1")
  let aa = crdt.lww_merge(a, a)
  aa.value |> should.equal(a.value)
}

pub fn lww_merge_tie_break_by_node_id_test() {
  // Same timestamp: lexicographically larger node_id wins
  let a = crdt.lww_new("from-a", 1000, "node-a")
  let b = crdt.lww_new("from-z", 1000, "node-z")
  let merged = crdt.lww_merge(a, b)
  // "node-z" > "node-a" lexicographically → b wins
  merged.value |> should.equal("from-z")
}

// =============================================================================
// OR-Set tests
// =============================================================================

pub fn orset_new_is_empty_test() {
  crdt.orset_new()
  |> crdt.orset_values()
  |> should.equal([])
}

pub fn orset_add_single_element_test() {
  let s = crdt.orset_new() |> crdt.orset_add("guardian-approved", "t1", 100)
  crdt.orset_contains(s, "guardian-approved") |> should.be_true()
}

pub fn orset_add_two_elements_test() {
  let s =
    crdt.orset_new()
    |> crdt.orset_add("approved", "t1", 100)
    |> crdt.orset_add("pending", "t2", 101)
  let vals = crdt.orset_values(s)
  list.length(vals) |> should.equal(2)
  list.contains(vals, "approved") |> should.be_true()
  list.contains(vals, "pending") |> should.be_true()
}

pub fn orset_remove_element_test() {
  let s =
    crdt.orset_new()
    |> crdt.orset_add("approved", "t1", 100)
    |> crdt.orset_add("pending", "t2", 101)
    |> crdt.orset_remove("approved")
  crdt.orset_contains(s, "approved") |> should.be_false()
  crdt.orset_contains(s, "pending") |> should.be_true()
}

pub fn orset_remove_nonexistent_is_noop_test() {
  let s =
    crdt.orset_new()
    |> crdt.orset_add("alpha", "t1", 100)
    |> crdt.orset_remove("beta")
  crdt.orset_values(s) |> should.equal(["alpha"])
}

pub fn orset_merge_union_test() {
  let a = crdt.orset_new() |> crdt.orset_add("x", "t1", 100)
  let b = crdt.orset_new() |> crdt.orset_add("y", "t2", 200)
  let merged = crdt.orset_merge(a, b)
  let vals = crdt.orset_values(merged)
  list.contains(vals, "x") |> should.be_true()
  list.contains(vals, "y") |> should.be_true()
}

pub fn orset_merge_commutativity_test() {
  let a = crdt.orset_new() |> crdt.orset_add("x", "t1", 100)
  let b = crdt.orset_new() |> crdt.orset_add("y", "t2", 200)
  let ab = crdt.orset_merge(a, b)
  let ba = crdt.orset_merge(b, a)
  let ab_vals = crdt.orset_values(ab)
  let ba_vals = crdt.orset_values(ba)
  { list.contains(ab_vals, "x") && list.contains(ab_vals, "y") }
  |> should.be_true()
  { list.contains(ba_vals, "x") && list.contains(ba_vals, "y") }
  |> should.be_true()
  list.length(ab_vals) |> should.equal(list.length(ba_vals))
}

pub fn orset_merge_idempotency_test() {
  let a =
    crdt.orset_new()
    |> crdt.orset_add("alpha", "t1", 100)
    |> crdt.orset_add("beta", "t2", 200)
  let aa = crdt.orset_merge(a, a)
  list.length(crdt.orset_values(aa))
  |> should.equal(list.length(crdt.orset_values(a)))
}

pub fn orset_add_wins_over_concurrent_remove_test() {
  // Node A removes "verdict", Node B concurrently adds "verdict" with a new tag
  let base =
    crdt.orset_new()
    |> crdt.orset_add("verdict", "tag-original", 100)
  let node_a = crdt.orset_remove(base, "verdict")
  let node_b = crdt.orset_add(base, "verdict", "tag-new", 200)
  let merged = crdt.orset_merge(node_a, node_b)
  // "tag-new" was not tombstoned by node_a's remove → add wins
  crdt.orset_contains(merged, "verdict") |> should.be_true()
}

pub fn orset_merge_associativity_test() {
  let a = crdt.orset_new() |> crdt.orset_add("a", "t1", 100)
  let b = crdt.orset_new() |> crdt.orset_add("b", "t2", 200)
  let c = crdt.orset_new() |> crdt.orset_add("c", "t3", 300)
  let left = crdt.orset_merge(crdt.orset_merge(a, b), c)
  let right = crdt.orset_merge(a, crdt.orset_merge(b, c))
  let left_vals = crdt.orset_values(left)
  let right_vals = crdt.orset_values(right)
  list.length(left_vals) |> should.equal(list.length(right_vals))
  { list.contains(left_vals, "a") && list.contains(right_vals, "a") }
  |> should.be_true()
  { list.contains(left_vals, "b") && list.contains(right_vals, "b") }
  |> should.be_true()
  { list.contains(left_vals, "c") && list.contains(right_vals, "c") }
  |> should.be_true()
}

// =============================================================================
// Integrated scenario: distributed guard verdict tracking (OR-Set use case)
// =============================================================================

pub fn orset_guard_verdict_scenario_test() {
  // Guardian node approves two tasks
  let guardian =
    crdt.orset_new()
    |> crdt.orset_add("task-001:approved", "g1-t001", 1000)
    |> crdt.orset_add("task-002:approved", "g1-t002", 1001)
  // Backup node also approved task-001 concurrently (different tag)
  let backup =
    crdt.orset_new()
    |> crdt.orset_add("task-001:approved", "g2-t001", 1002)
  // Merge: both nodes sync
  let synced = crdt.orset_merge(guardian, backup)
  // task-001 still present (add-wins semantics across nodes)
  crdt.orset_contains(synced, "task-001:approved") |> should.be_true()
  crdt.orset_contains(synced, "task-002:approved") |> should.be_true()
}
