// =============================================================================
// crdt_sets_test.gleam — CRDT LWW-Element-Set & OR-Set Invariant Tests
// STAMP: SC-SIL6-001, SC-CRDT-001, SC-LATTICE-001
// =============================================================================

import cepaf_gleam/ha/crdt_sets.{
  lww_add, lww_contains, lww_merge, lww_remove, new_lww_set, new_or_set,
  or_add, or_contains, or_merge, or_remove,
}
import gleeunit/should

pub fn lww_add_remove_lifecycle_test() {
  let s0 = new_lww_set()

  // Initially empty
  lww_contains(s0, "task-1") |> should.be_false

  // Add at t=100
  let s1 = lww_add(s0, "task-1", 100)
  lww_contains(s1, "task-1") |> should.be_true

  // Remove at t=150
  let s2 = lww_remove(s1, "task-1", 150)
  lww_contains(s2, "task-1") |> should.be_false

  // Re-add at t=200
  let s3 = lww_add(s2, "task-1", 200)
  lww_contains(s3, "task-1") |> should.be_true
}

pub fn lww_concurrent_merge_commutativity_test() {
  let s_a =
    new_lww_set()
    |> lww_add("item-alpha", 100)
    |> lww_add("item-beta", 200)
    |> lww_remove("item-gamma", 300)

  let s_b =
    new_lww_set()
    |> lww_remove("item-alpha", 150) // Removed after add
    |> lww_add("item-gamma", 250) // Added before remove
    |> lww_add("item-delta", 400)

  // Merge A with B
  let m_ab = lww_merge(s_a, s_b)
  // Merge B with A
  let m_ba = lww_merge(s_b, s_a)

  // item-alpha was added at 100, removed at 150 -> false in both
  lww_contains(m_ab, "item-alpha") |> should.be_false
  lww_contains(m_ba, "item-alpha") |> should.be_false

  // item-beta was added at 200 -> true in both
  lww_contains(m_ab, "item-beta") |> should.be_true
  lww_contains(m_ba, "item-beta") |> should.be_true

  // item-gamma was added at 250, removed at 300 -> false in both
  lww_contains(m_ab, "item-gamma") |> should.be_false
  lww_contains(m_ba, "item-gamma") |> should.be_false

  // item-delta was added at 400 -> true in both
  lww_contains(m_ab, "item-delta") |> should.be_true
  lww_contains(m_ba, "item-delta") |> should.be_true
}

pub fn or_set_tag_isolation_test() {
  let s0 = new_or_set()

  // Node 1 adds "key" with tag "tag-1"
  let s1 = or_add(s0, "user-session", "tag-replica-1")
  or_contains(s1, "user-session") |> should.be_true

  // Node 2 adds "key" with tag "tag-2" concurrently
  let s2 = or_add(s0, "user-session", "tag-replica-2")

  // Node 1 removes "user-session" (tombstones "tag-replica-1")
  let s1_rem = or_remove(s1, "user-session")
  or_contains(s1_rem, "user-session") |> should.be_false

  // Merge Node 1's remove with Node 2's add
  let merged = or_merge(s1_rem, s2)

  // Crucial OR-Set invariant: "tag-replica-2" was not observed by Node 1 during remove,
  // so the concurrent add wins and element remains present!
  or_contains(merged, "user-session") |> should.be_true

  // Removing from merged tombstones "tag-replica-2" as well
  let fully_removed = or_remove(merged, "user-session")
  or_contains(fully_removed, "user-session") |> should.be_false
}

pub fn or_set_idempotence_and_associativity_test() {
  let s =
    new_or_set()
    |> or_add("e1", "tag-1")
    |> or_add("e2", "tag-2")

  // Idempotence: merge(s, s) == s
  let s_idem = or_merge(s, s)
  or_contains(s_idem, "e1") |> should.be_true
  or_contains(s_idem, "e2") |> should.be_true
  or_contains(s_idem, "e3") |> should.be_false
}
