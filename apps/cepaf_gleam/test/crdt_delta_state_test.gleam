// =============================================================================
// [C3I-SIL6-MSTS] CRDT DELTA-STATE ALGEBRA TEST SUITE (SC-CRDT-001)
// =============================================================================

import cepaf_gleam/crdt/delta_state.{
  Dot, MeshDeltaState, dominates, empty_orset, empty_pncounter, get_clock,
  merge_clocks, merge_lww, merge_mesh_states, merge_orset, merge_pncounter,
  new_lww_register, new_mesh_delta_state, orset_add, orset_contains,
  orset_remove, pncounter_decrement, pncounter_increment, pncounter_value,
}
import gleeunit/should

pub fn vector_clock_semilattice_properties_test() {
  let c1 = [#("node-a", 3), #("node-b", 1)]
  let c2 = [#("node-a", 2), #("node-b", 4), #("node-c", 1)]

  // Idempotence: merge(c1, c1) == c1
  let m_self = merge_clocks(c1, c1)
  get_clock(m_self, "node-a") |> should.equal(3)
  get_clock(m_self, "node-b") |> should.equal(1)

  // Commutativity: merge(c1, c2) == merge(c2, c1)
  let m12 = merge_clocks(c1, c2)
  let m21 = merge_clocks(c2, c1)
  get_clock(m12, "node-a") |> should.equal(get_clock(m21, "node-a"))
  get_clock(m12, "node-b") |> should.equal(get_clock(m21, "node-b"))
  get_clock(m12, "node-c") |> should.equal(get_clock(m21, "node-c"))
  get_clock(m12, "node-a") |> should.equal(3)
  get_clock(m12, "node-b") |> should.equal(4)
  get_clock(m12, "node-c") |> should.equal(1)

  // Causal dominance
  dominates(m12, c1) |> should.be_true()
  dominates(m12, c2) |> should.be_true()
  dominates(c1, m12) |> should.be_false()
}

pub fn lww_register_convergence_test() {
  let reg1 = new_lww_register("leader-a", 1000, "node-1")
  let reg2 = new_lww_register("leader-b", 2000, "node-2")

  // Higher timestamp wins
  let winner = merge_lww(reg1, reg2)
  winner.value |> should.equal("leader-b")

  // Equal timestamp uses deterministic node id tie-breaker
  let tie1 = new_lww_register("state-a", 5000, "node-alpha")
  let tie2 = new_lww_register("state-b", 5000, "node-beta")
  let tie_winner = merge_lww(tie1, tie2)
  tie_winner.writer |> should.equal("node-beta")
}

pub fn orset_add_remove_convergence_test() {
  let set0 = empty_orset()

  // Node 1 adds "worker-alpha" with dot (node-1, 1)
  let set1 = orset_add(set0, "worker-alpha", Dot("node-1", 1))
  orset_contains(set1, "worker-alpha") |> should.be_true()

  // Node 2 concurrently adds "worker-beta" with dot (node-2, 1)
  let set2 = orset_add(set0, "worker-beta", Dot("node-2", 1))

  // Merge sets
  let merged = merge_orset(set1, set2)
  orset_contains(merged, "worker-alpha") |> should.be_true()
  orset_contains(merged, "worker-beta") |> should.be_true()

  // Remove "worker-alpha" on node 1
  let removed1 = orset_remove(merged, "worker-alpha")
  orset_contains(removed1, "worker-alpha") |> should.be_false()
  orset_contains(removed1, "worker-beta") |> should.be_true()

  // Re-add "worker-alpha" with a newer dot (node-1, 2)
  let readded = orset_add(removed1, "worker-alpha", Dot("node-1", 2))
  orset_contains(readded, "worker-alpha") |> should.be_true()
}

pub fn pncounter_increment_decrement_test() {
  let cnt0 = empty_pncounter()

  // Node A increments 10, Node B increments 5
  let cnt_a = pncounter_increment(cnt0, "node-a", 10)
  let cnt_b = pncounter_increment(cnt0, "node-b", 5)

  // Node A decrements 3
  let cnt_a2 = pncounter_decrement(cnt_a, "node-a", 3)

  let merged = merge_pncounter(cnt_a2, cnt_b)
  // Total: (10 + 5) - 3 = 12
  pncounter_value(merged) |> should.equal(12)
}

pub fn mesh_delta_state_composition_test() {
  let state_nas1 = new_mesh_delta_state("nas-1", 1_700_000_000_000_000)
  let state_vm1 = new_mesh_delta_state("vm-1", 1_700_000_000_100_000)

  // nas-1 registers claude-worker
  let s_nas1 =
    MeshDeltaState(
      ..state_nas1,
      active_workers: orset_add(
        state_nas1.active_workers,
        "claude-worker",
        Dot("nas-1", 1),
      ),
      task_counters: pncounter_increment(
        state_nas1.task_counters,
        "nas-1",
        4,
      ),
    )

  // vm-1 registers codex-worker
  let s_vm1 =
    MeshDeltaState(
      ..state_vm1,
      active_workers: orset_add(
        state_vm1.active_workers,
        "codex-worker",
        Dot("vm-1", 1),
      ),
      task_counters: pncounter_increment(state_vm1.task_counters, "vm-1", 7),
      leader_lease: new_lww_register(
        "vm-1",
        1_700_000_000_200_000,
        "vm-1",
      ),
    )

  let unified = merge_mesh_states(s_nas1, s_vm1)

  // Both workers visible
  orset_contains(unified.active_workers, "claude-worker") |> should.be_true()
  orset_contains(unified.active_workers, "codex-worker") |> should.be_true()

  // Combined counter: 4 + 7 = 11
  pncounter_value(unified.task_counters) |> should.equal(11)

  // Leader lease won by higher timestamp vm-1
  unified.leader_lease.value |> should.equal("vm-1")
}
