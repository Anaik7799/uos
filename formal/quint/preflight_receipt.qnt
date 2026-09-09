// Preflight receipt lifecycle — temporal model (SC-NIX-DEVENV-001).
//
// Companion to:
//   engines/hermes/modules/hermes_toolchain/preflight_algebra.{ml,mli}
//   formal/lean/Preflight_Verdict_Algebra.lean
//   tools/preflight  (--receipt, --max-age)
//
// The Lean file proves the receipt PREDICATE is correct in isolation. This model
// asks the different, temporal question: across arbitrary interleavings of clock
// ticks, checker edits, resolver-table edits and preflight runs, can a caller
// ever accept a cached verdict it should not have?
//
// That is not the same question. A predicate can be correct at every instant and
// still be consulted at the wrong one — which is precisely the shape of the bug
// this whole effort keeps rediscovering: the check was fine, the observable was
// stale or coarse.

module preflight_receipt {
  val MAX_AGE = 3

  // Digests are modelled as integers: only equality matters, and an unbounded
  // string domain would make the state space uninteresting rather than truer.
  type Receipt = {
    present: bool,
    passed: bool,
    epoch: int,
    checker: int,
    table: int,
  }

  var clock: int
  var checkerNow: int          // sha256 of tools/preflight
  var tableNow: int            // sha256 of tools/lib/uos-toolchain.sh
  var receipt: Receipt
  var toolchainHealthy: bool   // the ground truth the preflight observes
  var accepted: bool           // a caller accepted a cached PASS this step
  var acceptedAge: int
  var acceptedChecker: int
  var acceptedTable: int
  var acceptedStatus: bool

  val NO_RECEIPT = { present: false, passed: false, epoch: 0, checker: 0, table: 0 }

  action init = all {
    clock' = 0,
    checkerNow' = 1,
    tableNow' = 1,
    receipt' = NO_RECEIPT,
    toolchainHealthy' = true,
    accepted' = false,
    acceptedAge' = 0,
    acceptedChecker' = 0,
    acceptedTable' = 0,
    acceptedStatus' = false,
  }

  // The freshness/provenance predicate, mirroring receipt_valid exactly.
  def valid(r: Receipt, now: int): bool = and {
    r.present,
    r.passed,
    now >= r.epoch,
    now - r.epoch <= MAX_AGE,
    r.checker == checkerNow,
    r.table == tableNow,
  }

  action tick = all {
    clock' = clock + 1,
    checkerNow' = checkerNow, tableNow' = tableNow, receipt' = receipt,
    toolchainHealthy' = toolchainHealthy,
    accepted' = false, acceptedAge' = 0, acceptedChecker' = 0,
    acceptedTable' = 0, acceptedStatus' = false,
  }

  // Editing the checker or the resolver table is exactly the event that must
  // void every prior receipt.
  action editChecker = all {
    checkerNow' = checkerNow + 1,
    clock' = clock, tableNow' = tableNow, receipt' = receipt,
    toolchainHealthy' = toolchainHealthy,
    accepted' = false, acceptedAge' = 0, acceptedChecker' = 0,
    acceptedTable' = 0, acceptedStatus' = false,
  }

  action editTable = all {
    tableNow' = tableNow + 1,
    clock' = clock, checkerNow' = checkerNow, receipt' = receipt,
    toolchainHealthy' = toolchainHealthy,
    accepted' = false, acceptedAge' = 0, acceptedChecker' = 0,
    acceptedTable' = 0, acceptedStatus' = false,
  }

  // The toolchain can break at any moment (a profile swap, a garbage collection,
  // a hand-materialised tree that was always incomplete).
  action breakToolchain = all {
    toolchainHealthy' = false,
    clock' = clock, checkerNow' = checkerNow, tableNow' = tableNow,
    receipt' = receipt,
    accepted' = false, acceptedAge' = 0, acceptedChecker' = 0,
    acceptedTable' = 0, acceptedStatus' = false,
  }

  action repairToolchain = all {
    toolchainHealthy' = true,
    clock' = clock, checkerNow' = checkerNow, tableNow' = tableNow,
    receipt' = receipt,
    accepted' = false, acceptedAge' = 0, acceptedChecker' = 0,
    acceptedTable' = 0, acceptedStatus' = false,
  }

  // A full sweep: observes the CURRENT toolchain with the CURRENT checker and
  // table, and stamps the receipt with both digests.
  action runPreflight = all {
    receipt' = {
      present: true,
      passed: toolchainHealthy,
      epoch: clock,
      checker: checkerNow,
      table: tableNow,
    },
    clock' = clock, checkerNow' = checkerNow, tableNow' = tableNow,
    toolchainHealthy' = toolchainHealthy,
    accepted' = false, acceptedAge' = 0, acceptedChecker' = 0,
    acceptedTable' = 0, acceptedStatus' = false,
  }

  // A caller (hook, gate, SRE loop) accepts the cached verdict instead of
  // running the sweep. Guarded by `valid`; the invariants below check the guard.
  action acceptCached = all {
    valid(receipt, clock),
    accepted' = true,
    acceptedAge' = clock - receipt.epoch,
    acceptedChecker' = receipt.checker,
    acceptedTable' = receipt.table,
    acceptedStatus' = receipt.passed,
    clock' = clock, checkerNow' = checkerNow, tableNow' = tableNow,
    receipt' = receipt, toolchainHealthy' = toolchainHealthy,
  }

  action step = any {
    tick,
    editChecker,
    editTable,
    breakToolchain,
    repairToolchain,
    runPreflight,
    acceptCached,
  }

  // INV-1: a cached verdict is never accepted beyond its age bound.
  val inv_no_stale_accept = accepted implies (acceptedAge >= 0 and acceptedAge <= MAX_AGE)

  // INV-2: a cached verdict is never accepted after the checker or the resolver
  // table changed. This is the property that stops a PASS lending its confidence
  // to code it never examined.
  val inv_no_foreign_accept =
    accepted implies (acceptedChecker == checkerNow and acceptedTable == tableNow)

  // INV-3: a cached FAIL is never accepted as a pass.
  val inv_no_fail_accept = accepted implies acceptedStatus

  // INV-4: the property that actually matters operationally. If a caller accepts
  // a cached PASS, then the toolchain was healthy WHEN THE RECEIPT WAS WRITTEN
  // and nothing has invalidated that observation since. It deliberately does NOT
  // claim the toolchain is healthy NOW: a receipt is evidence about the past, and
  // the age bound is what makes that evidence usable rather than true.
  val inv_accept_implies_observed_healthy =
    accepted implies (receipt.present and receipt.passed)

  val inv_all = and {
    inv_no_stale_accept,
    inv_no_foreign_accept,
    inv_no_fail_accept,
    inv_accept_implies_observed_healthy,
  }
}
