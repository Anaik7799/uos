// =========================================================================
// verification_plane.qnt — Quint runtime model of the UOS verification
// plane's CONTROL PLANE: the verdict state machine every oracle receipt
// passes through.
//
// WHY A RUNTIME MODEL AND NOT A PROOF
// -----------------------------------
// Lean proves properties of the verdict ALGEBRA at a candidate. It cannot
// express reachability over a sequence of recording actions: "is there a run
// of arm registrations that ends in PASS having observed nothing?" is a
// question about traces, not about arithmetic. That is the question Quint
// answers, and it is exactly the shape of three failure modes the FMEA
// measured as MANIFESTS UNDETECTED.
//
// WHAT IS MODELLED
// ----------------
// The substrate's counters and its status() function, as implemented in
// formal/mojo/oracle_substrate.mojo. The actions are the five recording
// calls an oracle can make. The invariants are the claims the substrate's
// own docstrings make about itself.
//
// HONEST BOUNDARY
// ---------------
// This models the CONTROL PLANE only -- the verdict function and its
// counters. It does not model the data plane (what a capture actually read),
// because a model of a grep is a model of the author's belief about the grep.
// A Quint invariant holding here says the verdict function cannot reach a
// state; it says nothing about whether the measurement feeding it was sound.
//
// authority NONE. EV ceiling 93. No admission.
// =========================================================================

module verification_plane {

  // ---- the verdict lattice, severity-ordered (worst wins) ---------------
  // Mirrors `severity` in tools/lean_mojo_differential.ml:159-167.
  type Verdict =
    | PASS
    | BLIND
    | WORLD_FAIL
    | DIVERGENT
    | NO_ORACLE
    | VACUOUS
    | LEAN_FAIL
    | UNRUN

  pure def severity(v: Verdict): int =
    match v {
    PASS         => 0
    | BLIND      => 1
    | WORLD_FAIL => 2
    | DIVERGENT  => 3
    | NO_ORACLE  => 4
    | VACUOUS    => 5
    | LEAN_FAIL  => 6
    | UNRUN      => 7
    }

  // ---- the receipt counters, as the substrate holds them ----------------
  var checks: int
  var algebra_checks: int
  var algebra_failures: int
  var world_checks: int
  var world_failures: int
  var observations: int
  var blind: int
  var vacuous: int

  // ---- status(), mirroring oracle_substrate.mojo after the F7 fix -------
  // Both vacuity forms are tested FIRST. Pre-fix, `algebra_checks == 0` sat
  // below world_failures and blind; that ordering is what INV_VACUITY_FIRST
  // below would have refuted.
  pure def status_of(ac: int, af: int, wf: int, bl: int, vac: int): Verdict =
    if (vac != 0 or ac == 0) VACUOUS
    else if (af != 0) DIVERGENT
    else if (wf != 0) WORLD_FAIL
    else if (bl != 0) BLIND
    else PASS

  def status: Verdict =
    status_of(algebra_checks, algebra_failures, world_failures, blind, vacuous)

  action init = all {
    checks' = 0, algebra_checks' = 0, algebra_failures' = 0,
    world_checks' = 0, world_failures' = 0, observations' = 0,
    blind' = 0, vacuous' = 0
  }

  // ---- the five recording actions --------------------------------------
  action algebra(ok: bool): bool = all {
    checks' = checks + 1,
    algebra_checks' = algebra_checks + 1,
    algebra_failures' = if (ok) algebra_failures else algebra_failures + 1,
    world_checks' = world_checks, world_failures' = world_failures,
    observations' = observations, blind' = blind, vacuous' = vacuous
  }

  action world(ok: bool): bool = all {
    checks' = checks + 1,
    world_checks' = world_checks + 1,
    world_failures' = if (ok) world_failures else world_failures + 1,
    algebra_checks' = algebra_checks, algebra_failures' = algebra_failures,
    observations' = observations, blind' = blind, vacuous' = vacuous
  }

  // `field_present` false routes to BLIND, never to a world failure: the
  // world_or_blind contract.
  action world_or_blind(field_present: bool, value_ok: bool): bool =
    if (field_present)
      world(value_ok)
    else all {
      checks' = checks + 1, blind' = blind + 1,
      algebra_checks' = algebra_checks, algebra_failures' = algebra_failures,
      world_checks' = world_checks, world_failures' = world_failures,
      observations' = observations, vacuous' = vacuous
    }

  action observe(raw_nonempty: bool): bool = all {
    checks' = checks + 1,
    observations' = observations + 1,
    blind' = if (raw_nonempty) blind else blind + 1,
    algebra_checks' = algebra_checks, algebra_failures' = algebra_failures,
    world_checks' = world_checks, world_failures' = world_failures,
    vacuous' = vacuous
  }

  action mutation_probe(wrong_is_rejected: bool): bool = all {
    checks' = checks + 1,
    vacuous' = if (wrong_is_rejected) vacuous else vacuous + 1,
    algebra_checks' = algebra_checks, algebra_failures' = algebra_failures,
    world_checks' = world_checks, world_failures' = world_failures,
    observations' = observations, blind' = blind
  }

  action step = any {
    algebra(true), algebra(false),
    world(true), world(false),
    world_or_blind(true, true), world_or_blind(true, false),
    world_or_blind(false, false),
    observe(true), observe(false),
    mutation_probe(true), mutation_probe(false)
  }

  // =====================================================================
  // INVARIANTS -- each one is a claim the substrate makes about itself
  // =====================================================================

  // The substrate's status() comment: "Order matters. Vacuity first: a blind
  // oracle's other verdicts are worthless." Both vacuity forms must win.
  val INV_VACUITY_FIRST: bool =
    (vacuous != 0 or algebra_checks == 0) implies (status == VACUOUS)

  // A probe failure must never be masked by any other signal.
  val INV_PROBE_FAILURE_IS_SUPREME: bool =
    (vacuous != 0) implies (severity(status) >= severity(VACUOUS))

  // Worst wins: the emitted verdict is at least as severe as every signal
  // the receipt carries.
  val INV_WORST_WINS: bool = and {
    (algebra_failures != 0) implies (severity(status) >= severity(DIVERGENT)),
    (world_failures != 0 and algebra_failures == 0 and vacuous == 0
       and algebra_checks != 0) implies (severity(status) >= severity(WORLD_FAIL)),
    (blind != 0 and world_failures == 0 and algebra_failures == 0
       and vacuous == 0 and algebra_checks != 0)
       implies (severity(status) >= severity(BLIND))
  }

  // PASS requires that at least one algebra arm ran. This is the invariant
  // that makes "algebra_checks == 0" a vacuity condition at all.
  val INV_PASS_REQUIRES_ALGEBRA: bool =
    (status == PASS) implies (algebra_checks > 0)

  // ---- THE THREE FMEA MODES, AS REACHABILITY QUESTIONS -----------------
  //
  // These are stated as invariants the model is EXPECTED TO REFUTE. A
  // counterexample is the finding: it is a concrete trace in which the
  // control plane reaches a verdict the plane should not be able to emit.
  // Stating them as invariants rather than as prose is what makes the FMEA's
  // MANIFESTS rows reproducible by a tool instead of by a careful reader.

  // FM-06: can a run report PASS having never recorded a world check?
  // If this is refutable, an oracle can pass while observing nothing.
  val INV_NO_PASS_WITHOUT_A_WORLD_CHECK: bool =
    (status == PASS) implies (world_checks > 0)

  // FM-05: can a run report WORLD_FAIL with no observation at all behind it?
  // That is the manufactured-outage shape: a failure asserted about a world
  // nobody looked at.
  val INV_NO_WORLD_FAIL_WITHOUT_AN_OBSERVATION: bool =
    (world_failures > 0) implies (observations > 0)

  // FM-04: can a probe failure (VACUOUS) coexist with a real divergence, so
  // that the graver-but-less-informative verdict hides the finding?
  val INV_PROBE_FAILURE_NEVER_HIDES_A_DIVERGENCE: bool =
    not(vacuous > 0 and algebra_failures > 0)

  // All four soundness invariants together, for a single run.
  val SOUNDNESS: bool = and {
    INV_VACUITY_FIRST,
    INV_PROBE_FAILURE_IS_SUPREME,
    INV_WORST_WINS,
    INV_PASS_REQUIRES_ALGEBRA
  }
}
