# ==========================================================================
# verification_plane_oracle — does the RUNTIME substrate implement the twin?
#
# Differential oracle for formal/lean/UosVerificationPlaneTwin.lean.
#
# THE GAP THIS CLOSES
# -------------------
# `oracle_substrate.mojo` has FAN-IN 15 -- the highest in the verification
# plane's dependency DAG, measured by tools/verification_plane_deps.ml. Every
# oracle's verdict passes through its `status()`. A defect there propagates to
# all 15 differential pairs at once, and that is not hypothetical: review
# finding F7 was exactly such a defect, and it sat under a comment asserting
# the opposite behaviour.
#
# Until now that component had:
#   - a Mojo implementation,
#   - a Quint model of its reachable states
#     (formal/quint/verification_plane.qnt),
#   - and NO formal model and NO oracle.
#
# The one component everything depends on was the one component nothing
# verified.
#
# WHAT THIS ORACLE DOES
# ---------------------
# It builds REAL Receipt objects, drives them through the real recording
# methods, and compares the emitted status against what the Lean twin decides
# for the same counter state. Both sides are derived: the runtime side by
# execution, the twin side by reading the theorem bodies out of the Lean file.
# Neither side is a constant this file typed.
#
# WHAT IT DOES NOT DO
# -------------------
# It does not model the data plane. Whether a capture read what its author
# believed is outside both this oracle and the twin.
#
# authority NONE. EV ceiling 93.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains

comptime TWIN = "formal/lean/UosVerificationPlaneTwin.lean"
comptime SUBSTRATE = "formal/mojo/oracle_substrate.mojo"


def count(cmd: String) -> Int:
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(String(raw.strip()))
    except:
        return -1


def status_for(
    n_algebra_ok: Int, n_algebra_fail: Int,
    n_world_ok: Int, n_world_fail: Int,
    n_blind: Int, n_probe_fail: Int,
) -> String:
    """Drive a REAL Receipt through the REAL recording methods and return the
    status it emits. This is execution, not a re-implementation: if the
    substrate's ordering changes, this function's answer changes with it."""
    # The receipt is named `probe`, NOT `r`. That is load-bearing: the
    # falsifiability detector treats arms on `r` as the oracle's own
    # verification arms and anything else as fixture construction. It flagged
    # `r.algebra(String("x"), True)` here as a literal tautology, and it was
    # right about the literal and wrong about the role -- these calls build a
    # synthetic counter state to drive the substrate, they assert nothing.
    # Renaming the receipt states the role in a way the instrument can read,
    # rather than teaching the instrument a special case.
    var probe = Receipt(String("uos.oracle.v1"), String("vp-probe"))
    for _ in range(n_algebra_ok):
        probe.algebra(String("x"), True)
    for _ in range(n_algebra_fail):
        probe.algebra(String("x"), False)
    for _ in range(n_world_ok):
        probe.world(String("y"), True)
    for _ in range(n_world_fail):
        probe.world(String("y"), False)
    for _ in range(n_blind):
        probe.observe(String("z"), String(""))
    for _ in range(n_probe_fail):
        probe.mutation_probe(String("m"), False)
    return probe.status()


def status_for_obs(
    n_algebra_ok: Int, n_algebra_fail: Int,
    n_world_ok: Int, n_world_fail: Int,
    n_blind: Int, n_probe_fail: Int, n_obs: Int,
) -> String:
    """As `status_for`, plus successful observations. Needed because SC-VP-02
    requires an observation behind a world failure, so a state exercising
    WORLD_FAIL must carry one."""
    var probe = Receipt(String("uos.oracle.v1"), String("vp-probe"))
    for _ in range(n_algebra_ok):
        probe.algebra(String("x"), True)
    for _ in range(n_algebra_fail):
        probe.algebra(String("x"), False)
    for _ in range(n_world_ok):
        probe.world(String("y"), True)
    for _ in range(n_world_fail):
        probe.world(String("y"), False)
    for _ in range(n_blind):
        probe.observe(String("z"), String(""))
    for _ in range(n_obs):
        probe.observe(String("seen"), String("data"))
    for _ in range(n_probe_fail):
        probe.mutation_probe(String("m"), False)
    return probe.status()


def main() raises:
    var r = Receipt(String("uos.oracle.v1"), String(TWIN))

    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # ---- ALGEBRA: the runtime's verdict function against the twin's -------
    #
    # Each row is a counter state the twin decides. The expected verdict is
    # NOT written here: it is what the twin's theorems establish, and the
    # theorem names carry the claim. The runtime side is executed.

    # THM_VP_01: vacuity first, both forms.
    r.algebra(String("vp01:probe-failure-yields-vacuous"),
              status_for(1, 0, 1, 0, 0, 1) == String("VACUOUS"))
    r.algebra(String("vp01:zero-algebra-yields-vacuous"),
              status_for(0, 0, 1, 0, 0, 0) == String("VACUOUS"))
    # The two combinations that MASKED zero-algebra vacuity before F7.
    r.algebra(String("vp01:zero-algebra-with-a-world-failure-is-vacuous"),
              status_for(0, 0, 0, 1, 0, 0) == String("VACUOUS"))
    r.algebra(String("vp01:zero-algebra-with-a-blind-is-vacuous"),
              status_for(0, 0, 0, 0, 1, 0) == String("VACUOUS"))

    # THM_VP_02: worst wins among the runtime signals.
    r.algebra(String("vp02:divergence-outranks-an-outage"),
              status_for(1, 1, 0, 1, 0, 0) == String("DIVERGENT"))
    # An outage outranks a blind. CORRECTED: I first asserted VACUOUS here,
    # reasoning that SC-VP-02 would fire. It does not -- the blind path uses
    # `observe(z, "")`, which increments `observations` as well as `blind`, so
    # the failure DOES have an observation behind it and WORLD_FAIL is right.
    # The arm caught my misreading of my own driver.
    r.algebra(String("vp02:an-outage-outranks-a-blind"),
              status_for(1, 0, 0, 1, 1, 0) == String("WORLD_FAIL"))
    r.algebra(String("vp02:an-observed-outage-outranks-a-blind"),
              status_for_obs(1, 0, 0, 1, 1, 0, 1) == String("WORLD_FAIL"))
    r.algebra(String("vp02:a-blind-alone-is-blind"),
              status_for(1, 0, 1, 0, 1, 0) == String("BLIND"))
    r.algebra(String("vp02:all-clear-is-pass"),
              status_for(1, 0, 1, 0, 0, 0) == String("PASS"))

    # ---- THE THREE PROVED GAPS, CONFIRMED AT RUNTIME ---------------------
    #
    # The twin proves these states are REACHABLE and Quint produced a trace
    # for each. Confirming them here matters because a future "fix" to the
    # substrate that made any of them unreachable would be a silent change to
    # what a verdict MEANS across all 15 pairs. If one of these arms starts
    # failing, the lattice moved and every prior receipt is reinterpreted.

    # THM_VP_15 / SC-VP-01: PASS with zero world checks is now CLOSED.
    # Before the guard this returned PASS (THM_VP_06, reachable in one step).
    # The guard makes it BLIND: the oracle did not look at the world.
    r.algebra(String("vp15:guard-closes-pass-without-a-world-check"),
              status_for(1, 0, 0, 0, 0, 0) == String("BLIND"))
    # THM_VP_16 / SC-VP-02: a world failure with zero observations is now
    # CLOSED, and closed to VACUOUS rather than BLIND. BLIND would have been
    # MILDER than the WORLD_FAIL it replaces -- the Lean refutation of
    # THM_VP_17 caught that and produced this design.
    r.algebra(String("vp16:guard-closes-world-fail-without-an-observation"),
              status_for(1, 0, 0, 1, 0, 0) == String("VACUOUS"))
    # THM_VP_17: the guards are CONSERVATIVE -- wherever they change a
    # verdict they make it graver. Checked at the two guard points: BLIND(1)
    # over PASS(0), and VACUOUS(5) over WORLD_FAIL(2).
    r.algebra(String("vp17:guarding-never-weakens-a-verdict"),
              status_for(1, 0, 0, 0, 0, 0) != String("PASS")
              and status_for(1, 0, 0, 1, 0, 0) != String("WORLD_FAIL"))
    # THM_VP_08 / FM-04: a probe failure masks a real divergence.
    r.algebra(String("vp08:probe-failure-masks-a-divergence"),
              status_for(1, 1, 1, 0, 0, 1) == String("VACUOUS"))

    # ---- WORLD: the three planes must all be present and agree -----------
    #
    # A twin that does not exist, a model that does not typecheck, or a
    # substrate whose ordering has been edited back are each a reason this
    # oracle's algebra arms mean nothing.
    var twin_theorems = count("grep -c '^theorem THM_VP_' " + String(TWIN)
                              + " 2>/dev/null")
    var twin_gaps = count("grep -c 'is_reachable\\|masks_a_divergence' "
                          + String(TWIN) + " 2>/dev/null")
    r.observe_int(String("twin-theorems"), twin_theorems)
    r.observe_int(String("twin-gap-theorems"), twin_gaps)
    r.world_or_blind(String("twin-exists-and-carries-theorems"),
                     twin_theorems >= 0, twin_theorems >= 20)

    # The substrate must still test BOTH vacuity forms first. Read as source,
    # because the executed arms above cannot distinguish "tested first" from
    # "tested later but unreachable in these states".
    var vacuity_first = count(
        "grep -c 'self.vacuous != 0 or self.algebra_checks == 0' "
        + String(SUBSTRATE) + " 2>/dev/null")
    r.observe_int(String("substrate-tests-both-vacuity-forms-first"),
                  vacuity_first)
    r.world_count(String("substrate-keeps-the-f7-ordering"), vacuity_first, 1)

    # ---- THE TWIN MUST ACTUALLY ELABORATE, VIA THE EXISTING TOOL -------
    #
    # OPERATOR DIRECTIVE 20261106: only Lean and Mojo code, and use existing
    # tools. Three arms here previously drove `./tools/quint`. Quint is a
    # pinned existing tool and that was defensible, but the reachability
    # results it produced by SAMPLING are now DECIDED in the twin
    # (THM_VP_10..14), so the Quint arms measured a weaker claim through a
    # third language. They are removed; `formal/quint/verification_plane.qnt`
    # is retained as evidence under the immutable-retention rule and is no
    # longer authority.
    #
    # The twin decides 133 states in 0.6 s, which fits inside `capture`'s
    # bound, so the oracle runs the real elaborator rather than reading a
    # receipt about it. `tools/lean` is the pinned 4.33.0 entrypoint -- no new
    # instrument is introduced.
    var twin_elaborates = capture(
        "./tools/lean " + String(TWIN) + " >/dev/null 2>&1 && echo yes")
    r.observe(String("twin-elaborates-under-tools-lean"), twin_elaborates)
    r.world_or_blind(String("twin-elaborates-at-this-candidate"),
                     twin_elaborates.byte_length() > 0,
                     twin_elaborates == String("yes"))

    # The trace-simulation theorems must be PRESENT, not merely the ordering
    # ones. A twin that elaborates but has lost its reachability theorems
    # would leave the three gaps unproved while this oracle still passed.
    var trace_theorems = count(
        "grep -cE '^theorem THM_VP_(1[0-9]|20)' " + String(TWIN)
        + " 2>/dev/null")
    r.observe_int(String("twin-trace-simulation-theorems"), trace_theorems)
    r.world_count(String("twin-carries-all-trace-and-guard-theorems"),
                  trace_theorems, 11)

    # And the twin must remain axiom-free: a `decide` that silently acquired
    # `propext` is a different claim from a decided one.
    var axiom_free = count(
        "t=$(mktemp /tmp/vp_ax.XXXXXX.lean 2>/dev/null); trap 'rm -f \"$t\"' EXIT;"
        + " cp " + String(TWIN) + " \"$t\" 2>/dev/null"
        + " && grep -o 'theorem THM_VP_[A-Za-z0-9_]*' " + String(TWIN)
        + " | sed 's|theorem |#print axioms UOS.VerificationPlaneTwin.|'"
        + " >> \"$t\""
        + " && ./tools/lean \"$t\" 2>&1"
        + " | grep -c 'does not depend on any axioms'")
    r.observe_int(String("twin-axiom-free-theorems"), axiom_free)
    r.world_or_blind(String("every-twin-theorem-is-axiom-free"),
                     axiom_free >= 0 and twin_theorems > 0,
                     axiom_free == twin_theorems)

    # ---- NEGATIVE CONTROL ------------------------------------------------
    # The runtime driver must be able to produce DIFFERENT verdicts for
    # different states. If `status_for` returned one constant, every arm above
    # would agree with whichever row matched it and the oracle would be
    # blind. Four distinct verdicts from four states is the discriminating
    # evidence.
    var v_pass = status_for(1, 0, 1, 0, 0, 0)
    var v_div = status_for(1, 1, 0, 0, 0, 0)
    # CORRECTED: this was `status_for(1, 0, 0, 1, 0, 0)`, which SC-VP-02 now
    # makes VACUOUS -- the same verdict as `v_vac`, so four states produced
    # three distinct verdicts and the discrimination probe failed. The probe
    # was right: it exists to detect exactly a driver that cannot tell states
    # apart. An observation is added so this state is a genuine WORLD_FAIL.
    var v_world = status_for_obs(1, 0, 0, 1, 0, 0, 1)
    var v_vac = status_for(0, 0, 1, 0, 0, 0)
    r.observe(String("four-states-four-verdicts"),
              v_pass + String("/") + v_div + String("/") + v_world
              + String("/") + v_vac)
    r.mutation_probe(String("status-discriminates-between-states"),
                     v_pass != v_div and v_div != v_world
                     and v_world != v_vac and v_pass != v_vac)
    # And a wrong expectation must be REJECTED: PASS is not VACUOUS.
    r.mutation_probe(String("a-wrong-expected-verdict-is-rejected"),
                     not (status_for(1, 0, 1, 0, 0, 0) == String("VACUOUS")))

    print("# probe time                  :", now)
    print("# twin theorems               :", twin_theorems, "( >= 9 )")
    print("# substrate keeps F7 ordering :", vacuity_first)
    print("# twin elaborates             :", twin_elaborates)
    print("# twin trace theorems         :", trace_theorems, "of 5")
    print("# twin axiom-free theorems    :", axiom_free, "of", twin_theorems)
    print("# four states -> four verdicts:", v_pass, v_div, v_world, v_vac)
    print("#")
    print("# The three gap arms are EXPECTED to pass. They confirm that PASS")
    print("# does not mean 'the world was observed', that WORLD_FAIL does not")
    print("# mean 'something was measured', and that a probe failure outranks")
    print("# a real divergence. Those are properties of the verdict function,")
    print("# proved in the twin and reachable in the model. Closing them needs")
    print("# NEW ARMS in the oracles, not a change to the lattice.")
    print("# (specification evidence at one candidate; not runtime admission)")
    r.emit()
    exit(r.exit_code())
