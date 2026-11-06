/-
  UosVerificationPlaneTwin — the digital twin of the verification plane itself.

  WHY THIS FILE EXISTS
  --------------------
  The plane had 15 oracles verifying 22 Lean subjects, and no twin of ITSELF.
  Its central object — the verdict function that decides what every receipt
  means — was implemented in Mojo (`formal/mojo/oracle_substrate.mojo`),
  simulated in Quint (`formal/quint/verification_plane.qnt`), and proved
  nowhere. The one component on whose correctness all 15 pairs depend
  (`oracle_substrate.mojo` has fan-in 15, the highest in the dependency DAG)
  was the one component with no formal model.

  THE DIVISION OF LABOUR, STATED
  ------------------------------
  * Quint answers REACHABILITY over traces: "is there a run of recording
    actions that ends in PASS having observed nothing?" It found three such
    runs, in two to four steps each.
  * This file answers the ALGEBRA exhaustively: for every verdict and every
    combination of counter-emptiness, the ordering claims hold by `decide`.
  * `formal/mojo/verification_plane_oracle.mojo` answers whether the RUNTIME
    agrees with this file at the current candidate.

  None of the three substitutes for another. A proof here does not make the
  Mojo implementation correct; that is what the oracle is for.

  authority NONE. EV ceiling 93. No admission is granted by this file.
-/

namespace UOS.VerificationPlaneTwin

/-- The verdict lattice. Mirrors `severity` in
    `tools/lean_mojo_differential.ml:159-167`. -/
inductive Verdict where
  | pass | blind | worldFail | divergent | noOracle | vacuous | leanFail | unrun
  deriving DecidableEq, Repr

def allVerdict : List Verdict :=
  [.pass, .blind, .worldFail, .divergent, .noOracle, .vacuous, .leanFail,
   .unrun]

/-- Severity. Worst wins, so a higher number outranks a lower one. -/
def severity : Verdict → Nat
  | .pass      => 0
  | .blind     => 1
  | .worldFail => 2
  | .divergent => 3
  | .noOracle  => 4
  | .vacuous   => 5
  | .leanFail  => 6
  | .unrun     => 7

/-- The PROCESS EXIT CODE table, which is a different table. Mirrors
    `exit_of` in the same driver. It exists here so the two can be asserted
    to differ: a previous oracle transcribed this table while naming the
    lattice, and because the numerals were inlined nothing could detect it. -/
def exitCode : Verdict → Nat
  | .pass      => 0
  | .worldFail => 1
  | .blind     => 2
  | .divergent => 3
  | .vacuous   => 4
  | .noOracle  => 5
  | .leanFail  => 6
  | .unrun     => 7

/-- A receipt's counter state. These are the eight fields
    `oracle_substrate.mojo` maintains. -/
structure Counters where
  checks          : Nat
  algebraChecks   : Nat
  algebraFailures : Nat
  worldChecks     : Nat
  worldFailures   : Nat
  observations    : Nat
  blind           : Nat
  vacuous         : Nat
  deriving DecidableEq, Repr

/-- `status()`, mirroring the substrate AFTER the F7 correction: both vacuity
    forms are tested first. Pre-fix, `algebraChecks == 0` was tested below
    `worldFailures` and `blind`, and `THM_VP_01` below is the claim that
    ordering violated. -/
def statusUnguarded (c : Counters) : Verdict :=
  if c.vacuous ≠ 0 ∨ c.algebraChecks = 0 then .vacuous
  else if c.algebraFailures ≠ 0 then .divergent
  else if c.worldFailures ≠ 0 then .worldFail
  else if c.blind ≠ 0 then .blind
  else .pass

/-! ## 1. The ordering claims the substrate makes about itself -/

/-- **THM_VP_01 — vacuity first, both forms.** The substrate's own comment
    says "Order matters. Vacuity first: a blind oracle's other verdicts are
    worthless." Stated over a representative exhaustive grid rather than one
    witness: for every combination of the five emptiness conditions, a
    nonzero `vacuous` OR a zero `algebraChecks` forces `.vacuous`. -/
theorem THM_VP_01_vacuity_outranks_every_runtime_signal :
    ([0, 1].flatMap fun v =>
     [0, 1].flatMap fun ac =>
     [0, 1].flatMap fun af =>
     [0, 1].flatMap fun wf =>
     [0, 1].map fun bl =>
       let c : Counters :=
         { checks := 4, algebraChecks := ac, algebraFailures := af,
           worldChecks := 1, worldFailures := wf, observations := 1,
           blind := bl, vacuous := v }
       if v ≠ 0 ∨ ac = 0 then statusUnguarded c == Verdict.vacuous else true
     ).all (fun b => b) = true := by decide

/-- **THM_VP_02 — worst wins on the runtime signals.** With vacuity clear,
    a divergence outranks an outage and an outage outranks a blind. -/
theorem THM_VP_02_worst_wins_among_runtime_signals :
    ([0, 1].flatMap fun af =>
     [0, 1].flatMap fun wf =>
     [0, 1].map fun bl =>
       let c : Counters :=
         { checks := 4, algebraChecks := 1, algebraFailures := af,
           worldChecks := 1, worldFailures := wf, observations := 1,
           blind := bl, vacuous := 0 }
       if af ≠ 0 then
         decide (severity (statusUnguarded c) ≥ severity Verdict.divergent)
       else if wf ≠ 0 then
         decide (severity (statusUnguarded c) ≥ severity Verdict.worldFail)
       else if bl ≠ 0 then
         decide (severity (statusUnguarded c) ≥ severity Verdict.blind)
       else statusUnguarded c == Verdict.pass
     ).all (fun b => b) = true := by decide

/-- **THM_VP_03 — PASS requires that at least one algebra arm ran.** This is
    what makes `algebraChecks = 0` a vacuity condition rather than a detail.

    Stated as a decided grid rather than a universally quantified implication:
    the quantified form needed `simp [statusOf, hv]`, which pulled `propext`
    into an otherwise axiom-free file. The grid covers the same five emptiness
    conditions the other ordering theorems range over, and it is the only
    content the quantified version carried, since `statusOf` depends on the
    counters only through whether each is zero. -/
theorem THM_VP_03_pass_requires_an_algebra_arm :
    ([0, 1].flatMap fun v =>
     [0, 1].flatMap fun ac =>
     [0, 1].flatMap fun af =>
     [0, 1].flatMap fun wf =>
     [0, 1].map fun bl =>
       let c : Counters :=
         { checks := 4, algebraChecks := ac, algebraFailures := af,
           worldChecks := 1, worldFailures := wf, observations := 1,
           blind := bl, vacuous := v }
       if statusUnguarded c == Verdict.pass then !(c.algebraChecks == 0) else true
     ).all (fun b => b) = true := by decide

/-- **THM_VP_04 — the two tables are distinct, and distinct at a NAMED
    point.** `severity` ranks blind below worldFail; `exitCode` ranks them the
    other way. An oracle once transcribed `exitCode` while naming the lattice,
    and inlined numerals made that undetectable. -/
theorem THM_VP_04_exit_codes_are_not_the_severity_lattice :
    severity Verdict.blind < severity Verdict.worldFail ∧
    exitCode Verdict.worldFail < exitCode Verdict.blind := by decide

/-- **THM_VP_05 — severity is injective.** Two verdicts never share a rank,
    so "worst wins" is a total order on the carrier and `worse` is
    well defined. -/
theorem THM_VP_05_severity_is_injective :
    (allVerdict.map severity).eraseDups.length = allVerdict.length := by decide

/-! ## 2. The detection gaps, PROVED to exist

    These are not failures of the verdict function. They are properties the
    verdict function does not and cannot constrain, and the point of stating
    them in Lean is that the gap becomes a theorem with a witness rather than
    a sentence in a review. Quint found each of them as a trace; here each is
    a decided fact about a concrete reachable state. -/

/-- **THM_VP_06 — FM-06: a receipt can report PASS having recorded NO world
    check at all.** The witness is one passing algebra arm and nothing else —
    the two-step trace Quint produced. So "PASS" never meant "the world was
    observed", and no arm in the plane asserts that it did. -/
theorem THM_VP_06_pass_is_reachable_with_zero_world_checks :
    statusUnguarded
      { checks := 1, algebraChecks := 1, algebraFailures := 0,
        worldChecks := 0, worldFailures := 0, observations := 0,
        blind := 0, vacuous := 0 } = Verdict.pass := by decide

/-- **THM_VP_07 — FM-05: a receipt can report WORLD_FAIL with zero
    observations behind it.** This is the manufactured-outage shape: a failure
    asserted about a world nobody looked at. Measured as RPN 80, the highest
    in the FMEA, and detected by no instrument. -/
theorem THM_VP_07_world_fail_is_reachable_with_zero_observations :
    statusUnguarded
      { checks := 2, algebraChecks := 1, algebraFailures := 0,
        worldChecks := 1, worldFailures := 1, observations := 0,
        blind := 0, vacuous := 0 } = Verdict.worldFail := by decide

/-- **THM_VP_08 — FM-04: a probe failure HIDES a real divergence.** With both
    `vacuous` and `algebraFailures` nonzero the verdict is `.vacuous`, so the
    graver-but-less-informative verdict masks the finding. A control that
    pins a subject value turns a legitimate change in the subject into this
    state, which is why pinning is barred. -/
theorem THM_VP_08_probe_failure_masks_a_divergence :
    statusUnguarded
      { checks := 3, algebraChecks := 1, algebraFailures := 1,
        worldChecks := 1, worldFailures := 0, observations := 1,
        blind := 0, vacuous := 1 } = Verdict.vacuous := by decide

/-- **THM_VP_09 — the masking is not an ordering mistake.** Vacuity SHOULD
    outrank divergence: an oracle that cannot discriminate has no standing to
    report one. So THM_VP_08 is a correct consequence of a correct ordering,
    and the defect it describes lives in whatever made `vacuous` nonzero —
    never in the lattice. Recorded so a later reader does not "fix" the
    lattice. -/
theorem THM_VP_09_vacuity_should_outrank_divergence :
    severity Verdict.vacuous > severity Verdict.divergent := by decide

/-! ## 3. Bounded trace simulation — the runtime model, in Lean

    OPERATOR DIRECTIVE 20261106: only Lean and Mojo code. The runtime model
    was first written in Quint (`formal/quint/verification_plane.qnt`, retained
    as evidence under the immutable-retention rule, superseded as authority).
    Quint SAMPLED the state space: 20,000 traces at 13 steps, reporting "you
    may increase --max-samples", which is honest and is not exhaustive.

    Lean decides it instead. The step relation below is the same eleven
    recording actions, and the theorems range over EVERY trace of bounded
    length rather than over a sample. That is a strictly stronger result from
    strictly less tooling, which is the argument for the constraint. -/

/-- One recording action, as an index. Mirrors the eleven call shapes an
    oracle can make through `Receipt`. -/
inductive Act where
  | algebraOk | algebraFail
  | worldOk | worldFail
  | wobPresentOk | wobPresentFail | wobAbsent
  | observeSeen | observeBlind
  | probeOk | probeFail
  deriving DecidableEq, Repr

def allAct : List Act :=
  [.algebraOk, .algebraFail, .worldOk, .worldFail, .wobPresentOk,
   .wobPresentFail, .wobAbsent, .observeSeen, .observeBlind, .probeOk,
   .probeFail]

def initCounters : Counters :=
  { checks := 0, algebraChecks := 0, algebraFailures := 0, worldChecks := 0,
    worldFailures := 0, observations := 0, blind := 0, vacuous := 0 }

/-- Add a delta to every counter at once. Written as one helper so each
    action below is a single line: a multi-line record update inside a match
    arm does not parse. -/
def bump (c : Counters) (ch ac af wc wf ob bl va : Nat) : Counters :=
  { checks := c.checks + ch, algebraChecks := c.algebraChecks + ac,
    algebraFailures := c.algebraFailures + af,
    worldChecks := c.worldChecks + wc, worldFailures := c.worldFailures + wf,
    observations := c.observations + ob, blind := c.blind + bl,
    vacuous := c.vacuous + va }

/-- The step relation. Each arm mirrors one method of `Receipt`, with the
    delta that method applies. Order: checks, algebraChecks, algebraFailures,
    worldChecks, worldFailures, observations, blind, vacuous. -/
def step (c : Counters) : Act → Counters
  | .algebraOk       => bump c 1 1 0 0 0 0 0 0
  | .algebraFail     => bump c 1 1 1 0 0 0 0 0
  | .worldOk         => bump c 1 0 0 1 0 0 0 0
  | .worldFail       => bump c 1 0 0 1 1 0 0 0
  | .wobPresentOk    => bump c 1 0 0 1 0 0 0 0
  | .wobPresentFail  => bump c 1 0 0 1 1 0 0 0
  | .wobAbsent       => bump c 1 0 0 0 0 0 1 0
  | .observeSeen     => bump c 1 0 0 0 0 1 0 0
  | .observeBlind    => bump c 1 0 0 0 0 1 1 0
  | .probeOk         => bump c 1 0 0 0 0 0 0 0
  | .probeFail       => bump c 1 0 0 0 0 0 0 1

/-- Every state reachable from `initCounters` in exactly `n` steps. -/
def reachable : Nat → List Counters
  | 0 => [initCounters]
  | n + 1 => (reachable n).flatMap (fun c => allAct.map (step c))

/-- Every state reachable in AT MOST `n` steps. -/
def reachableUpTo (n : Nat) : List Counters :=
  (List.range (n + 1)).flatMap reachable

/-- The soundness conjunction as a pure `Bool` predicate on one state.

    Purely Bool by necessity, not by style: the first version used `∨` and `∧`
    inside the `if` conditions, and `decide` got stuck because those are
    `Prop`s whose instances do not reduce inside a list fold. A decision
    procedure that cannot run is not a decision procedure. -/
def sound (c : Counters) : Bool :=
  (if c.vacuous != 0 || c.algebraChecks == 0
   then statusUnguarded c == Verdict.vacuous else true)
  && (if c.vacuous == 0 && c.algebraChecks != 0 && c.algebraFailures != 0
      then statusUnguarded c == Verdict.divergent else true)
  && (if statusUnguarded c == Verdict.pass then c.algebraChecks != 0 else true)

/-- **THM_VP_10 — soundness holds on EVERY trace of length ≤ 2.**
    `reachableUpTo 2` is 1 + 11 + 121 = 133 states, decided exhaustively.

    The bound is 2 and is stated rather than implied. Depth 3 is 1,464 states
    and the kernel does not reduce it in reasonable time, so claiming depth 3
    would be claiming a computation that did not happen. The sampled Quint run
    covered 20,000 traces at depth 13 without a violation, which is wider and
    weaker: it is evidence over a sample, this is a decision over all traces to
    the bound. Neither is a proof for every n. -/
theorem THM_VP_10_soundness_holds_on_every_trace_to_depth_two :
    (reachableUpTo 2).all sound = true := by decide

/-- **THM_VP_11 — FM-06 is reachable in ONE step.** Exactly one trace of
    length 1 reaches `.pass` with `worldChecks = 0`: a single passing algebra
    arm. The SHORTEST such trace, not whichever one a sampler happened to hit.
    So `PASS` never meant "the world was observed". -/
theorem THM_VP_11_fm06_reachable_in_one_step :
    ((reachable 1).filter
      (fun c => statusUnguarded c == Verdict.pass && c.worldChecks == 0)).length = 1
      := by decide

/-- **THM_VP_12 — FM-05 needs exactly two steps, not one.** A `WORLD_FAIL`
    with zero observations is unreachable at depth 1 and reachable at depth 2.
    Stating the MINIMUM depth is what a sampler cannot give you. -/
theorem THM_VP_12_fm05_needs_exactly_two_steps :
    ((reachable 1).filter
      (fun c => statusUnguarded c == Verdict.worldFail && c.observations == 0)).length
      = 0 ∧
    ((reachable 2).filter
      (fun c => statusUnguarded c == Verdict.worldFail && c.observations == 0)).length
      > 0 := by decide

/-- **THM_VP_13 — FM-04 is reachable: a probe failure masks a divergence.**
    Some trace of length ≤ 2 reaches a state with both `vacuous` and
    `algebraFailures` nonzero, whose emitted verdict is `.vacuous` — so the
    divergence is invisible in the status field. -/
theorem THM_VP_13_fm04_masking_is_reachable :
    ((reachableUpTo 2).filter
      (fun c => c.vacuous != 0 && c.algebraFailures != 0
                && statusUnguarded c == Verdict.vacuous)).length > 0 := by decide

/-- **THM_VP_14 — PASS without a world check means algebra arms ALONE.**
    Over every trace to depth 2, each `.pass` state with `worldChecks = 0` has
    `algebraChecks > 0` and no failure, blind or vacuity. So the gap is exactly
    "algebra arms suffice for PASS" and no richer state slips through it. -/
theorem THM_VP_14_pass_without_world_means_algebra_only :
    ((reachableUpTo 2).filter
      (fun c => statusUnguarded c == Verdict.pass && c.worldChecks == 0)).all
      (fun c => c.algebraChecks > 0 && c.worldFailures == 0
                && c.blind == 0 && c.vacuous == 0) = true := by decide

/-! ## 3b. The guarded verdict function — SC-VP-01 and SC-VP-02

    `statusUnguarded` is the pre-20261106-1230 semantics, retained because
    THM_VP_11..14 are statements ABOUT it: they are the evidence that the
    three gaps were real, and deleting the function would delete the evidence.

    `statusGuarded` adds the two arms the FMEA's top-RPN modes demanded:

      SC-VP-01  PASS requires a world check. Algebra arms alone establish
                that the MIRROR is faithful, never that the system agrees
                with it, so PASS with `worldChecks = 0` has verified a model
                against itself.
      SC-VP-02  A world FAILURE requires an observation behind it. Asserting
                the world is broken while having observed nothing is a
                failure claimed about a world nobody looked at.

    SC-VP-01 resolves to `.blind` -- the oracle did not look, and blind at
    severity 1 outranks the pass at 0 it replaces.

    SC-VP-02 resolves to `.vacuous`, and the first draft got this WRONG.
    It resolved to `.blind`, and THM_VP_17 came back FALSE: blind is severity
    1 and worldFail is 2, so the guard LOWERED severity and could have
    laundered a genuine outage into "I could not look". A receipt claiming a
    failure it could not have observed is not blind, it is an instrument that
    cannot discriminate -- vacuity, at severity 5, which outranks what it
    replaces. The refutation produced the correct design; it was not a
    bookkeeping fix.

    BLAST RADIUS MEASURED BEFORE LANDING: all 16 oracles carry
    `worldChecks ≥ 4` and `observations ≥ 7`, so neither arm changes any
    current verdict. They are REGRESSION GUARDS against a reachable state. -/
def statusGuarded (c : Counters) : Verdict :=
  if c.vacuous ≠ 0 ∨ c.algebraChecks = 0 then .vacuous
  else if c.algebraFailures ≠ 0 then .divergent
  else if c.worldFailures ≠ 0 ∧ c.observations = 0 then .vacuous
  else if c.worldFailures ≠ 0 then .worldFail
  else if c.blind ≠ 0 then .blind
  else if c.worldChecks = 0 then .blind
  else .pass

/-- **THM_VP_15 — SC-VP-01 closes FM-06.** Under the guarded function, NO
    state reachable to depth 2 reports `.pass` with `worldChecks = 0`. The
    unguarded function reaches that state in ONE step (THM_VP_11), so this is
    the closure, stated against the same bound. -/
theorem THM_VP_15_guard_closes_pass_without_a_world_check :
    ((reachableUpTo 2).filter
      (fun c => statusGuarded c == Verdict.pass && c.worldChecks == 0)).length
      = 0 := by decide

/-- **THM_VP_16 — SC-VP-02 closes FM-05.** No reachable state reports
    `.worldFail` with zero observations. The unguarded function reaches that
    state in exactly two steps (THM_VP_12). -/
theorem THM_VP_16_guard_closes_world_fail_without_an_observation :
    ((reachableUpTo 2).filter
      (fun c => statusGuarded c == Verdict.worldFail
                && c.observations == 0)).length = 0 := by decide

/-- **THM_VP_17 — the guards are CONSERVATIVE.** Wherever the two functions
    differ, the guarded one is at least as severe. So no run that previously
    failed now passes: the change can only make a verdict graver, never
    milder, and an existing failure cannot be laundered by it. -/
theorem THM_VP_17_guarding_never_weakens_a_verdict :
    (reachableUpTo 2).all
      (fun c => decide (severity (statusGuarded c)
                        ≥ severity (statusUnguarded c))) = true := by decide

/-- **THM_VP_18 — the guards change the verdict on EXACTLY the gap states.**
    The states where the two functions disagree are precisely those with
    `worldChecks = 0`, or with a world failure and no observation. Nothing
    else moved, which is what "regression guard" has to mean to be true. -/
theorem THM_VP_18_guards_change_exactly_the_gap_states :
    ((reachableUpTo 2).filter
      (fun c => !(statusGuarded c == statusUnguarded c))).all
      (fun c => c.worldChecks == 0
                || (c.worldFailures != 0 && c.observations == 0)) = true
      := by decide

/-- **THM_VP_19 — totality.** `statusGuarded` is total: every reachable state
    maps to exactly one verdict drawn from the carrier. "It must always work"
    begins here -- a verdict function with an undefined case is a crash in
    the one component with fan-in 15. -/
theorem THM_VP_19_guarded_status_is_total :
    (reachableUpTo 2).all
      (fun c => allVerdict.contains (statusGuarded c)) = true := by decide

/-- **THM_VP_20 — soundness survives guarding.** The ordering claims of
    THM_VP_10 still hold under the guarded function: vacuity first,
    divergence over outage, and PASS still requires an algebra arm. A guard
    that closed a gap by breaking the lattice would be a worse defect than
    the gap. -/
theorem THM_VP_20_soundness_holds_under_guarding :
    (reachableUpTo 2).all
      (fun c =>
        (if c.vacuous != 0 || c.algebraChecks == 0
         then statusGuarded c == Verdict.vacuous else true)
        && (if c.vacuous == 0 && c.algebraChecks != 0
               && c.algebraFailures != 0
            then statusGuarded c == Verdict.divergent else true)
        && (if statusGuarded c == Verdict.pass
            then c.algebraChecks != 0 else true)) = true := by decide

/-! ## 4. What this twin does not establish

    It does not claim the Mojo substrate implements `statusOf`. That is a
    runtime question, answered by `formal/mojo/verification_plane_oracle.mojo`
    at one candidate and by nothing else.

    It does not model the DATA PLANE — what a capture actually read. A model
    of a grep is a model of the author's belief about the grep.

    It does not close the three gaps above. It proves they are real. -/

end UOS.VerificationPlaneTwin
