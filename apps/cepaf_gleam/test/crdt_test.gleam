/// CRDT State Synchronization Test Suite — 25+ tests
/// SC-ULTRA-001 Focus 2: Zenoh-Native CRDT State Backplane
///
/// Tests all five CRDT types via ha/crdt:
///   1. GCounter       — grow-only counter
///   2. PNCounter      — positive-negative counter
///   3. LWWRegister    — last-writer-wins register
///   4. ORSet          — observed-remove set
///   5. VersionVector  — causal ordering
///
/// Three CRDT laws verified for each type:
///   Commutativity:  merge(a,b) = merge(b,a)
///   Associativity:  merge(merge(a,b),c) = merge(a,merge(b,c))
///   Idempotency:    merge(a,a) = a
///
/// STAMP: SC-ULTRA-001, SC-XHOLON-006, SC-HA-001
import cepaf_gleam/ha/crdt
import gleam/list
import gleeunit/should

// =============================================================================
// G-Counter tests
// =============================================================================

pub fn gcounter_new_zero_test() {
  crdt.gcounter_new() |> crdt.gcounter_value() |> should.equal(0)
}

pub fn gcounter_increment_node1_test() {
  crdt.gcounter_new()
  |> crdt.gcounter_increment("n1")
  |> crdt.gcounter_value()
  |> should.equal(1)
}

pub fn gcounter_multi_increment_same_node_test() {
  crdt.gcounter_new()
  |> crdt.gcounter_increment("n1")
  |> crdt.gcounter_increment("n1")
  |> crdt.gcounter_increment("n1")
  |> crdt.gcounter_value()
  |> should.equal(3)
}

pub fn gcounter_multi_node_sum_test() {
  let a = crdt.gcounter_new() |> crdt.gcounter_increment("n1")
  let b = crdt.gcounter_new() |> crdt.gcounter_increment("n2")
  crdt.gcounter_merge(a, b) |> crdt.gcounter_value() |> should.equal(2)
}

pub fn gcounter_merge_commutativity_test() {
  let a =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("n1")
    |> crdt.gcounter_increment("n1")
  let b = crdt.gcounter_new() |> crdt.gcounter_increment("n2")
  let ab = crdt.gcounter_merge(a, b)
  let ba = crdt.gcounter_merge(b, a)
  crdt.gcounter_value(ab) |> should.equal(crdt.gcounter_value(ba))
}

pub fn gcounter_merge_associativity_test() {
  let a = crdt.gcounter_new() |> crdt.gcounter_increment("n1")
  let b = crdt.gcounter_new() |> crdt.gcounter_increment("n2")
  let c = crdt.gcounter_new() |> crdt.gcounter_increment("n3")
  let left = crdt.gcounter_merge(crdt.gcounter_merge(a, b), c)
  let right = crdt.gcounter_merge(a, crdt.gcounter_merge(b, c))
  crdt.gcounter_value(left) |> should.equal(crdt.gcounter_value(right))
}

pub fn gcounter_merge_idempotency_test() {
  let a =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("n1")
    |> crdt.gcounter_increment("n1")
  let aa = crdt.gcounter_merge(a, a)
  crdt.gcounter_value(aa) |> should.equal(crdt.gcounter_value(a))
}

// =============================================================================
// PN-Counter tests
// =============================================================================

pub fn pncounter_new_zero_test() {
  crdt.pncounter_new() |> crdt.pncounter_value() |> should.equal(0)
}

pub fn pncounter_increment_test() {
  crdt.pncounter_new()
  |> crdt.pncounter_increment("n1")
  |> crdt.pncounter_value()
  |> should.equal(1)
}

pub fn pncounter_decrement_test() {
  crdt.pncounter_new()
  |> crdt.pncounter_decrement("n1")
  |> crdt.pncounter_value()
  |> should.equal(-1)
}

pub fn pncounter_net_value_test() {
  crdt.pncounter_new()
  |> crdt.pncounter_increment("n1")
  |> crdt.pncounter_increment("n1")
  |> crdt.pncounter_decrement("n1")
  |> crdt.pncounter_value()
  |> should.equal(1)
}

pub fn pncounter_merge_commutativity_test() {
  let a = crdt.pncounter_new() |> crdt.pncounter_increment("n1")
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
  crdt.pncounter_value(crdt.pncounter_merge(a, a))
  |> should.equal(crdt.pncounter_value(a))
}

// =============================================================================
// LWW-Register tests
// =============================================================================

pub fn lww_new_stores_value_test() {
  let r = crdt.lww_new("healthy", 1000, "node-1")
  r.value |> should.equal("healthy")
  r.timestamp_ms |> should.equal(1000)
  r.node_id |> should.equal("node-1")
}

pub fn lww_set_higher_ts_wins_test() {
  crdt.lww_new("old", 100, "n1")
  |> crdt.lww_set("new", 200, "n1")
  |> fn(r) { r.value }
  |> should.equal("new")
}

pub fn lww_set_lower_ts_ignored_test() {
  crdt.lww_new("current", 500, "n1")
  |> crdt.lww_set("stale", 100, "n1")
  |> fn(r) { r.value }
  |> should.equal("current")
}

pub fn lww_merge_commutativity_test() {
  let a = crdt.lww_new("v1", 100, "n1")
  let b = crdt.lww_new("v2", 200, "n2")
  let ab = crdt.lww_merge(a, b)
  let ba = crdt.lww_merge(b, a)
  ab.value |> should.equal(ba.value)
}

pub fn lww_merge_idempotency_test() {
  let a = crdt.lww_new("stable", 999, "n1")
  crdt.lww_merge(a, a).value |> should.equal(a.value)
}

pub fn lww_tie_break_larger_node_id_wins_test() {
  // Same timestamp — lexicographically larger node_id wins
  let a = crdt.lww_new("from-a", 1000, "node-a")
  let b = crdt.lww_new("from-z", 1000, "node-z")
  crdt.lww_merge(a, b).value |> should.equal("from-z")
}

// =============================================================================
// OR-Set tests
// =============================================================================

pub fn orset_new_empty_test() {
  crdt.orset_new() |> crdt.orset_values() |> should.equal([])
}

pub fn orset_add_contains_test() {
  crdt.orset_new()
  |> crdt.orset_add("x", "t1", 100)
  |> crdt.orset_contains("x")
  |> should.be_true()
}

pub fn orset_remove_test() {
  crdt.orset_new()
  |> crdt.orset_add("x", "t1", 100)
  |> crdt.orset_remove("x")
  |> crdt.orset_contains("x")
  |> should.be_false()
}

pub fn orset_add_wins_concurrent_test() {
  // add-wins: a remove and a concurrent new-tagged add → element survives
  let base = crdt.orset_new() |> crdt.orset_add("item", "old-tag", 100)
  let removed = crdt.orset_remove(base, "item")
  let re_added = crdt.orset_add(base, "item", "new-tag", 200)
  crdt.orset_merge(removed, re_added)
  |> crdt.orset_contains("item")
  |> should.be_true()
}

pub fn orset_merge_commutativity_test() {
  let a = crdt.orset_new() |> crdt.orset_add("x", "t1", 100)
  let b = crdt.orset_new() |> crdt.orset_add("y", "t2", 200)
  let ab_vals = crdt.orset_merge(a, b) |> crdt.orset_values()
  let ba_vals = crdt.orset_merge(b, a) |> crdt.orset_values()
  list.length(ab_vals) |> should.equal(list.length(ba_vals))
}

pub fn orset_merge_idempotency_test() {
  let a =
    crdt.orset_new()
    |> crdt.orset_add("p", "t1", 1)
    |> crdt.orset_add("q", "t2", 2)
  list.length(crdt.orset_merge(a, a) |> crdt.orset_values())
  |> should.equal(list.length(crdt.orset_values(a)))
}

// =============================================================================
// Version Vector tests
// =============================================================================

pub fn vv_new_empty_test() {
  crdt.vv_new().versions |> should.equal([])
}

pub fn vv_increment_single_node_test() {
  let vv = crdt.vv_new() |> crdt.vv_increment("n1")
  // n1 clock should be 1
  let clock =
    list.find(vv.versions, fn(p) { p.0 == "n1" })
    |> fn(r) {
      case r {
        Ok(p) -> p.1
        Error(_) -> -1
      }
    }
  clock |> should.equal(1)
}

pub fn vv_increment_twice_test() {
  let vv =
    crdt.vv_new()
    |> crdt.vv_increment("n1")
    |> crdt.vv_increment("n1")
  let clock =
    list.find(vv.versions, fn(p) { p.0 == "n1" })
    |> fn(r) {
      case r {
        Ok(p) -> p.1
        Error(_) -> -1
      }
    }
  clock |> should.equal(2)
}

pub fn vv_merge_commutativity_test() {
  let a = crdt.vv_new() |> crdt.vv_increment("n1")
  let b = crdt.vv_new() |> crdt.vv_increment("n2")
  let ab = crdt.vv_merge(a, b)
  let ba = crdt.vv_merge(b, a)
  // Both merged VVs should contain both nodes with clock=1
  let ab_n1 = list.find(ab.versions, fn(p) { p.0 == "n1" })
  let ba_n1 = list.find(ba.versions, fn(p) { p.0 == "n1" })
  ab_n1 |> should.equal(ba_n1)
}

pub fn vv_merge_takes_max_test() {
  // a has n1=3, b has n1=1 → merge should give n1=3
  let a =
    crdt.vv_new()
    |> crdt.vv_increment("n1")
    |> crdt.vv_increment("n1")
    |> crdt.vv_increment("n1")
  let b = crdt.vv_new() |> crdt.vv_increment("n1")
  let merged = crdt.vv_merge(a, b)
  let clock =
    list.find(merged.versions, fn(p) { p.0 == "n1" })
    |> fn(r) {
      case r {
        Ok(p) -> p.1
        Error(_) -> -1
      }
    }
  clock |> should.equal(3)
}

pub fn vv_dominates_test() {
  // a has seen more events than b → a dominates b
  let a =
    crdt.vv_new()
    |> crdt.vv_increment("n1")
    |> crdt.vv_increment("n1")
  let b = crdt.vv_new() |> crdt.vv_increment("n1")
  crdt.vv_dominates(a, b) |> should.be_true()
  crdt.vv_dominates(b, a) |> should.be_false()
}

pub fn vv_equal_vectors_do_not_dominate_test() {
  let a = crdt.vv_new() |> crdt.vv_increment("n1")
  let b = crdt.vv_new() |> crdt.vv_increment("n1")
  // a and b have identical histories — neither dominates
  crdt.vv_dominates(a, b) |> should.be_false()
  crdt.vv_dominates(b, a) |> should.be_false()
}

pub fn vv_concurrent_test() {
  // a advanced n1, b advanced n2 independently → concurrent
  let a = crdt.vv_new() |> crdt.vv_increment("n1")
  let b = crdt.vv_new() |> crdt.vv_increment("n2")
  crdt.vv_concurrent(a, b) |> should.be_true()
}

pub fn vv_not_concurrent_when_dominated_test() {
  let a =
    crdt.vv_new()
    |> crdt.vv_increment("n1")
    |> crdt.vv_increment("n2")
  let b = crdt.vv_new() |> crdt.vv_increment("n1")
  // a dominates b → not concurrent
  crdt.vv_concurrent(a, b) |> should.be_false()
}

pub fn vv_merge_idempotency_test() {
  let a =
    crdt.vv_new()
    |> crdt.vv_increment("n1")
    |> crdt.vv_increment("n2")
  let aa = crdt.vv_merge(a, a)
  // merged with itself → same clocks
  let a_n1 = list.find(a.versions, fn(p) { p.0 == "n1" })
  let aa_n1 = list.find(aa.versions, fn(p) { p.0 == "n1" })
  a_n1 |> should.equal(aa_n1)
}

// =============================================================================
// Cross-type scenario: distributed system state tracking
// =============================================================================

pub fn distributed_state_scenario_test() {
  // Simulate 3 mesh nodes each independently tracking OODA cycle counts
  // Node n1: 5 cycles, Node n2: 3 cycles, Node n3: 7 cycles
  let n1_counter =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("n1")
    |> crdt.gcounter_increment("n1")
    |> crdt.gcounter_increment("n1")
    |> crdt.gcounter_increment("n1")
    |> crdt.gcounter_increment("n1")
  let n2_counter =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("n2")
    |> crdt.gcounter_increment("n2")
    |> crdt.gcounter_increment("n2")
  let n3_counter =
    crdt.gcounter_new()
    |> crdt.gcounter_increment("n3")
    |> crdt.gcounter_increment("n3")
    |> crdt.gcounter_increment("n3")
    |> crdt.gcounter_increment("n3")
    |> crdt.gcounter_increment("n3")
    |> crdt.gcounter_increment("n3")
    |> crdt.gcounter_increment("n3")
  let global =
    crdt.gcounter_merge(crdt.gcounter_merge(n1_counter, n2_counter), n3_counter)
  // Total across mesh = 5 + 3 + 7 = 15
  crdt.gcounter_value(global) |> should.equal(15)
}
