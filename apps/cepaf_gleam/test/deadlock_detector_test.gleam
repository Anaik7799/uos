// =============================================================================
// deadlock_detector_test.gleam — 2PL Distributed Deadlock Detection Tests
// STAMP: SC-SIL6-001, SC-2PL-001, SC-DEADLOCK-001
// =============================================================================

import cepaf_gleam/ha/deadlock_detector.{
  add_wait_edge, detect_deadlock, new_wfg, remove_all_for_tx,
  select_deadlock_victim,
}
import gleam/option.{None, Some}
import gleeunit/should

pub fn wfg_acyclic_no_deadlock_test() {
  // Chain: T1 -> T2 -> T3 -> T4 (Acyclic)
  let wfg =
    new_wfg()
    |> add_wait_edge("tx-1", "tx-2")
    |> add_wait_edge("tx-2", "tx-3")
    |> add_wait_edge("tx-3", "tx-4")

  detect_deadlock(wfg) |> should.equal(None)
}

pub fn wfg_2_cycle_deadlock_test() {
  // Mutual wait: T1 -> T2 and T2 -> T1 (Cycle)
  let wfg =
    new_wfg()
    |> add_wait_edge("tx-1", "tx-2")
    |> add_wait_edge("tx-2", "tx-1")

  let res = detect_deadlock(wfg)
  should.be_true(option.is_some(res))
}

pub fn wfg_3_cycle_deadlock_test() {
  // 3-way circular wait: T1 -> T2 -> T3 -> T1
  let wfg =
    new_wfg()
    |> add_wait_edge("tx-1", "tx-2")
    |> add_wait_edge("tx-2", "tx-3")
    |> add_wait_edge("tx-3", "tx-1")

  let res = detect_deadlock(wfg)
  should.be_true(option.is_some(res))
}

pub fn wfg_deadlock_resolution_test() {
  // Create circular wait: T1 -> T2 -> T3 -> T1
  let wfg =
    new_wfg()
    |> add_wait_edge("tx-1", "tx-2")
    |> add_wait_edge("tx-2", "tx-3")
    |> add_wait_edge("tx-3", "tx-1")

  let res = detect_deadlock(wfg)
  should.be_true(option.is_some(res))
  let assert Some(cycle) = res

  // Select deterministic victim
  let victim = select_deadlock_victim(cycle)
  should.be_true(option.is_some(victim))
  let assert Some(v) = victim

  // Aborting victim and removing all its edges must restore acyclicity
  let repaired_wfg = remove_all_for_tx(wfg, v)
  detect_deadlock(repaired_wfg) |> should.equal(None)
}
