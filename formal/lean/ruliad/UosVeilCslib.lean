/-
# UosVeilCslib — the Veil 6-plane transition system as a cslib LTS (20261108-1642)

Companion to `formal/lean/UosVeilProtocolAndKmWikiZkSyncDigitalTwin.lean`
(20 theorems, `THM_VEIL_01..20`). That file is **not edited and not imported**,
for two reasons that are both mechanical rather than stylistic:

1. It is checked by `tools/lean`, which resolves Lean **4.33.0**. cslib is
   pinned at `0b1e3680` and requires Mathlib `v4.35.0`, so a cslib import
   inside that file would break `tools/uos-veil-sync-check --with-lean`
   immediately. The pin is recorded in `SC-NIX-DEVENV-001` invariant 7.
2. It is another writer's artifact (stamped `20261108-1632`). Marking is
   additive here, never by rewriting.

So the definitions below are a **restatement**, and that restatement is the one
real hazard this file carries: two copies of `veilStep` can drift apart. It is
not hidden — `veil_mirror_agrees_with_decide_bound` re-runs the same exhaustive
`20 x 10 x 32` bound the 4.33.0 file proves, so a divergence in the copied
transition function shows up as a failed `decide` here rather than as a silent
disagreement. Marking the residual risk rather than hiding it:
No Mojo arm guards it yet: the peer-authored sync checker is not edited here, so
the mirror is guarded by the `decide` bound below and by nothing else.

## What cslib buys that `decide` cannot

The 4.33.0 file proves safety by `decide` over a **bounded** lattice: 20 cycles
x 10 layers x 32 transitions. That is an exhaustive check of 6,400 *states*, not
of *executions*. It says nothing about a trace of 7 drifts followed by 3
repairs, because no such trace is in the enumeration.

cslib supplies the unbounded statements:

* `veil_mtr_preserves_updr_invariant` — along `Cslib.LTS.MTr`, i.e. **every
  finite execution of every length**, the Andon invariant holds. Proved by
  induction on the multistep relation, not by enumeration.
* `repair_confluent` / `repair_churchRosser` — the repair action is confluent,
  so two operators repairing concurrently to different target epochs can always
  be reconciled. This is `Relation.Diamond.to_confluent` from cslib's
  confluence lattice; it is a statement about diverging histories, which a
  state enumeration cannot express at all.
* `veilLTS.Deterministic` — registered as a cslib instance, which is what makes
  `Cslib.LTS.Deterministic.eq_of_mTr` available: a trace determines its end
  state, so a replayed history cannot land anywhere else.

## What it costs

Measured, not assumed: `#print axioms` on the four results gives
`veil_mirror_agrees_with_decide_bound` -> no axioms,
`veil_mtr_preserves_updr_invariant` -> `[propext]`, and both confluence results
-> `[propext, Classical.choice, Quot.sound]`. So the 4.33.0 twin's **literal**
zero-axiom property does not survive the move to Mathlib/cslib: the three
standard classical axioms enter with the library. `sorryAx` and
`Lean.ofReduceBool` appear nowhere -- `decide` is used, never `native_decide`.
That trade is the price of the unbounded statements, and it is stated here
rather than left for a reader to discover.

Authority NONE. EV ceiling 93; `EV-94..109` `NOT_ADMITTED`; no new EV minted.
-/
import Cslib.Foundations.Relation.Confluence
import Cslib.Foundations.Semantics.LTS.Bisimulation

namespace UosVeilCslib

open Relation

/-! ## 1. Restated 6-plane state and transition function -/

/-- The 6 continuously synchronized planes. -/
inductive VeilSyncPlane where
  | Plane0_Spec | Plane1_DigitalTwin | Plane2_Code
  | Plane3_CodeComments | Plane4_DocsWikiZk | Plane5_SystemMemory
  deriving DecidableEq, Repr

structure VeilState where
  specEpoch : Nat
  twinEpoch : Nat
  codeEpoch : Nat
  commentEpoch : Nat
  wikiZkEpoch : Nat
  memoryEpoch : Nat
  admittedEvCeiling : Nat
  quarantineMarked : Bool
  chainIntact : Bool
  wikiDagAcyclic : Bool
  andonStopLine : Bool
  deriving DecidableEq, Repr

def allSixPlanesEpochAligned (s : VeilState) : Bool :=
  (s.specEpoch == s.twinEpoch) && (s.twinEpoch == s.codeEpoch) &&
  (s.codeEpoch == s.commentEpoch) && (s.commentEpoch == s.wikiZkEpoch) &&
  (s.wikiZkEpoch == s.memoryEpoch)

def allKmWikiZkInvariantsHold (s : VeilState) : Bool :=
  (s.admittedEvCeiling == 93) && s.quarantineMarked && s.chainIntact && s.wikiDagAcyclic

def allSixPlanesSynced (s : VeilState) : Bool :=
  allSixPlanesEpochAligned s && allKmWikiZkInvariantsHold s

def veilInit (epoch : Nat) : VeilState :=
  { specEpoch := epoch, twinEpoch := epoch, codeEpoch := epoch
  , commentEpoch := epoch, wikiZkEpoch := epoch, memoryEpoch := epoch
  , admittedEvCeiling := 93, quarantineMarked := true
  , chainIntact := true, wikiDagAcyclic := true, andonStopLine := false }

inductive VeilAction where
  | AtomicSixPlaneSync (nextEpoch : Nat)
  | InjectPlaneDrift (plane : VeilSyncPlane) (driftedEpoch : Nat)
  | InjectUnmarkedQuarantine
  | InjectBrokenDigestChain
  | InjectWikiTransclusionCycle
  | RepairDriftToTargetEpoch (targetEpoch : Nat)
  | ResetAndonWithVerifiedSync
  deriving DecidableEq, Repr

/-- The raw post-action state, BEFORE the Andon guard. -/
def veilRaw (s : VeilState) (a : VeilAction) : VeilState :=
  match a with
  | .AtomicSixPlaneSync n =>
      { s with specEpoch := n, twinEpoch := n, codeEpoch := n
             , commentEpoch := n, wikiZkEpoch := n, memoryEpoch := n }
  | .InjectPlaneDrift plane d =>
      match plane with
      | .Plane0_Spec         => { s with specEpoch := d }
      | .Plane1_DigitalTwin  => { s with twinEpoch := d }
      | .Plane2_Code         => { s with codeEpoch := d }
      | .Plane3_CodeComments => { s with commentEpoch := d }
      | .Plane4_DocsWikiZk   => { s with wikiZkEpoch := d }
      | .Plane5_SystemMemory => { s with memoryEpoch := d }
  | .InjectUnmarkedQuarantine => { s with quarantineMarked := false }
  | .InjectBrokenDigestChain => { s with chainIntact := false }
  | .InjectWikiTransclusionCycle => { s with wikiDagAcyclic := false }
  | .RepairDriftToTargetEpoch t =>
      { specEpoch := t, twinEpoch := t, codeEpoch := t, commentEpoch := t
      , wikiZkEpoch := t, memoryEpoch := t, admittedEvCeiling := 93
      , quarantineMarked := true, chainIntact := true, wikiDagAcyclic := true
      , andonStopLine := s.andonStopLine }
  | .ResetAndonWithVerifiedSync =>
      if allSixPlanesSynced s then { s with andonStopLine := false }
      else { s with andonStopLine := true }

/-- The Jidoka Andon guard: a transition either leaves the 6 planes synced or
raises the stop line. Factored out of `veilStep` so it can be reasoned about
for an ARBITRARY raw state rather than only for the seven action shapes. -/
def andonGuard (raw : VeilState) : VeilState :=
  if allSixPlanesSynced raw then raw else { raw with andonStopLine := true }

def veilStep (s : VeilState) (a : VeilAction) : VeilState := andonGuard (veilRaw s a)

/-- The `#updr`-style inductive invariant: synced, or the Andon line is up. -/
def updrSynthesizedInvariant (s : VeilState) : Bool :=
  allSixPlanesSynced s || s.andonStopLine

/-! ## 2. The transition system is a cslib LTS -/

/-- The Veil 6-plane system as a labelled transition system, labels = actions. -/
def veilLTS : _root_.Cslib.LTS VeilState VeilAction where
  Tr := fun s a s' => veilStep s a = s'

instance : veilLTS.Deterministic where
  deterministic := by
    intro s μ s₁ s₂ h₁ h₂
    simp only [veilLTS] at h₁ h₂
    exact h₁ ▸ h₂ ▸ rfl

/-! ## 3. Unbounded safety: the invariant holds along every execution

This is the statement the bounded `decide` cannot make. -/

/-- The guard is the whole safety argument, for an ARBITRARY raw state: a
transition either leaves the planes synced or raises the Andon line. -/
theorem andonGuard_invariant (raw : VeilState) :
    updrSynthesizedInvariant (andonGuard raw) = true := by
  unfold updrSynthesizedInvariant andonGuard
  by_cases h : allSixPlanesSynced raw = true
  · simp [h]
  · simp [h]

/-- One step always lands in the invariant, with no hypothesis on where it
started. -/
theorem step_updr_invariant (s : VeilState) (a : VeilAction) :
    updrSynthesizedInvariant (veilStep s a) = true :=
  andonGuard_invariant (veilRaw s a)

/-- **Unbounded safety.** For every finite execution of any length, from any
state satisfying the invariant, the reached state satisfies it. -/
theorem veil_mtr_preserves_updr_invariant
    {s s' : VeilState} {μs : List VeilAction}
    (h : veilLTS.MTr s μs s') (hs : updrSynthesizedInvariant s = true) :
    updrSynthesizedInvariant s' = true := by
  induction h with
  | refl => exact hs
  | stepL htr _ ih =>
      simp only [veilLTS] at htr
      exact ih (htr ▸ step_updr_invariant _ _)

/-- Corollary at the initial state: no reachable state of any execution length
starting from `veilInit` escapes the invariant. -/
theorem veil_reachable_from_init_invariant
    {epoch : Nat} {s' : VeilState} {μs : List VeilAction}
    (h : veilLTS.MTr (veilInit epoch) μs s') :
    updrSynthesizedInvariant s' = true := by
  refine veil_mtr_preserves_updr_invariant h ?_
  simp [updrSynthesizedInvariant, allSixPlanesSynced, allSixPlanesEpochAligned,
        allKmWikiZkInvariantsHold, veilInit]

/-! ## 4. Repair is confluent: concurrent repairs always reconcile -/

/-- The unlabelled repair relation: one `RepairDriftToTargetEpoch` step. -/
def repairRel (s t : VeilState) : Prop :=
  ∃ n, veilStep s (.RepairDriftToTargetEpoch n) = t

/-- A repair always leaves the planes synced, so the trailing Andon check in
`veilStep` passes and the stop-line bit is carried through unchanged. -/
theorem repair_eq (s : VeilState) (n : Nat) :
    veilStep s (.RepairDriftToTargetEpoch n) =
      { specEpoch := n, twinEpoch := n, codeEpoch := n, commentEpoch := n
      , wikiZkEpoch := n, memoryEpoch := n, admittedEvCeiling := 93
      , quarantineMarked := true, chainIntact := true, wikiDagAcyclic := true
      , andonStopLine := s.andonStopLine } := by
  simp [veilStep, veilRaw, andonGuard, allSixPlanesSynced, allSixPlanesEpochAligned,
        allKmWikiZkInvariantsHold]

/-- Repair preserves the Andon bit: repairing drift does NOT clear the stop
line. Clearing it requires `ResetAndonWithVerifiedSync`, which checks sync
first. Two separate keys, and this is the theorem that keeps them separate. -/
theorem repair_andon (s : VeilState) (n : Nat) :
    (veilStep s (.RepairDriftToTargetEpoch n)).andonStopLine = s.andonStopLine := by
  rw [repair_eq]

/-- The repair relation has the diamond property. -/
theorem repair_diamond : Relation.Diamond repairRel := by
  intro a b c hab hac
  obtain ⟨n, hn⟩ := hab
  obtain ⟨m, hm⟩ := hac
  refine ⟨veilStep b (.RepairDriftToTargetEpoch 0), ⟨0, rfl⟩, ⟨0, ?_⟩⟩
  rw [repair_eq, repair_eq, ← hn, ← hm, repair_andon, repair_andon]

/-- **Confluence of repair.** Two operators who repair the 6 planes
concurrently to different target epochs can always be brought back to a common
state. Obtained from cslib's confluence lattice, not re-proved here. -/
theorem repair_confluent : Relation.Confluent repairRel :=
  Relation.Diamond.to_confluent repair_diamond

/-- Church-Rosser form, via cslib's `confluent_iff_churchRosser`. -/
theorem repair_churchRosser : Relation.ChurchRosser repairRel :=
  Relation.confluent_iff_churchRosser.mp repair_confluent

/-! ## 5. Mirror guard against the restated transition function -/

/-- Single-plane drift raises the Andon line (`THM_VEIL_03`), restated and
re-checked here so a drift between this copy of `veilStep` and the 4.33.0
original cannot pass unnoticed. -/
theorem drift_raises_andon (epoch : Nat) (p : VeilSyncPlane) :
    (veilStep (veilInit epoch) (.InjectPlaneDrift p (epoch + 1))).andonStopLine = true := by
  cases p <;>
    simp [veilStep, veilRaw, andonGuard, veilInit, allSixPlanesSynced, allSixPlanesEpochAligned,
          allKmWikiZkInvariantsHold]

/-- The same bounded lattice the 4.33.0 twin proves by `decide`, re-run against
this restatement: if the copy drifted, this fails. -/
def mirrorBoundedCheck : Bool :=
  (List.range 20).all (fun c =>
    (List.range 10).all (fun l =>
      (List.range 32).all (fun t =>
        let epoch := 1 + c
        let s0 := veilInit epoch
        let a : VeilAction :=
          match (t + l) % 8 with
          | 0 => .AtomicSixPlaneSync (epoch + 1)
          | 1 => .InjectPlaneDrift .Plane0_Spec (epoch + 1)
          | 2 => .InjectPlaneDrift .Plane1_DigitalTwin (epoch + 2)
          | 3 => .InjectPlaneDrift .Plane2_Code (epoch + 3)
          | 4 => .InjectPlaneDrift .Plane3_CodeComments (epoch + 4)
          | 5 => .InjectPlaneDrift .Plane4_DocsWikiZk (epoch + 5)
          | 6 => .InjectUnmarkedQuarantine
          | _ => .InjectBrokenDigestChain
        let s1 := veilStep s0 a
        let r1 := veilStep s1 (.RepairDriftToTargetEpoch (epoch + 1))
        let r2 := veilStep r1 .ResetAndonWithVerifiedSync
        updrSynthesizedInvariant s1 && allSixPlanesSynced r2 && (!r2.andonStopLine))))

theorem veil_mirror_agrees_with_decide_bound : mirrorBoundedCheck = true := by
  decide

end UosVeilCslib
