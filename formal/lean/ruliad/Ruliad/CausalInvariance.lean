/-
# Ruliad.CausalInvariance — order independence, and the diagnosis laws

`engines/hermes/modules/hermes_vision/vision_ruliad.ml` enumerates 3^6 = 729
reachable diagnosis states and checks three laws on each, with permuted fact
orders. Its own header makes the right identification: *causal invariance is
exactly the order-independence claim*. Exhaustive enumeration over a finite
space is strong evidence; it is still evidence about that space only.

This module proves the general statements:

* `orderIndependent_sup_foldl` — a rule engine that accumulates verdicts into a
  join-semilattice is order independent for **every** input, not 729 of them.
  That is the structural reason `order_dependent () = []` comes out empty.
* `blame_absent`, `blame_cascade`, `blame_none_iff` — the unmeasured-blame and
  cascade laws, for lists of any length.
* `blame_not_orderIndependent` — and the honest converse: blame *does* depend on
  stage order. That is not a defect, because stage order is the ontology order,
  not the fact-arrival order. Conflating the two is the mistake this theorem
  makes impossible to state by accident.
-/
import Ruliad.Core
import Mathlib.Data.List.Perm.Basic
import Mathlib.Order.Lattice

namespace Ruliad.CausalInvariance

/-- A verdict function does not depend on the order its inputs arrived in. -/
def OrderIndependent {F V : Type*} (f : List F → V) : Prop :=
  ∀ l l' : List F, l.Perm l' → f l = f l'

/-- A left fold whose step function is right-commutative is order independent.
Reuses Mathlib's `List.Perm.foldl_eq`. -/
theorem orderIndependent_foldl {F V : Type*} (f : V → F → V) (b : V)
    [RightCommutative f] : OrderIndependent (fun l => l.foldl f b) :=
  fun _ _ hp => hp.foldl_eq b

instance instRightCommutativeSup {V : Type*} [SemilatticeSup V] :
    RightCommutative (· ⊔ · : V → V → V) :=
  ⟨fun b x y => by rw [sup_assoc, sup_comm x y, ← sup_assoc]⟩

/-- **The general form of the vision ruliology law.** Accumulating into a
join-semilattice is order independent over the whole input space. -/
theorem orderIndependent_sup_foldl {V : Type*} [SemilatticeSup V] (b : V) :
    OrderIndependent (fun l : List V => l.foldl (· ⊔ ·) b) :=
  orderIndependent_foldl (· ⊔ ·) b

/-! ## The diagnosis stage model -/

/-- One stage's measured verdict, as in the vision pipeline. -/
inductive Verdict where
  | live
  | absent
  | unknown
  deriving DecidableEq, Repr

/-- Blame the earliest failing stage. `unknown` is never blamed: an unmeasured
stage is not an accused stage. -/
def blameFrom : Nat → List Verdict → Option Nat
  | _, [] => none
  | i, Verdict.absent :: _ => some i
  | i, Verdict.live :: vs => blameFrom (i + 1) vs
  | i, Verdict.unknown :: vs => blameFrom (i + 1) vs

/-- Index of the blamed stage, if any. -/
def blame (vs : List Verdict) : Option Nat := blameFrom 0 vs

theorem blameFrom_spec : ∀ (vs : List Verdict) (i j : Nat), blameFrom i vs = some j →
    i ≤ j ∧ vs[j - i]? = some Verdict.absent ∧
      ∀ m, m < j - i → vs[m]? ≠ some Verdict.absent := by
  intro vs
  induction vs with
  | nil => intro i j h; simp [blameFrom] at h
  | cons v t ih =>
    intro i j h
    cases v with
    | absent =>
      simp only [blameFrom, Option.some.injEq] at h
      subst h
      refine ⟨le_refl _, ?_, ?_⟩
      · simp
      · intro m hm; omega
    | live =>
      simp only [blameFrom] at h
      obtain ⟨hle, hget, hfirst⟩ := ih (i + 1) j h
      refine ⟨by omega, ?_, ?_⟩
      · have : j - i = (j - (i + 1)) + 1 := by omega
        rw [this]
        simpa using hget
      · intro m hm
        match m with
        | 0 => simp
        | k + 1 =>
          have hk : k < j - (i + 1) := by omega
          simpa using hfirst k hk
    | unknown =>
      simp only [blameFrom] at h
      obtain ⟨hle, hget, hfirst⟩ := ih (i + 1) j h
      refine ⟨by omega, ?_, ?_⟩
      · have : j - i = (j - (i + 1)) + 1 := by omega
        rw [this]
        simpa using hget
      · intro m hm
        match m with
        | 0 => simp
        | k + 1 =>
          have hk : k < j - (i + 1) := by omega
          simpa using hfirst k hk

/-- **Unmeasured stages are never blamed, and neither are live ones.** The
blamed index always points at an `absent` measurement. -/
theorem blame_absent {vs : List Verdict} {i : Nat} (h : blame vs = some i) :
    vs[i]? = some Verdict.absent := by
  obtain ⟨_, hget, _⟩ := blameFrom_spec vs 0 i h
  simpa using hget

/-- **The cascade law.** Nothing upstream of the blamed stage had failed, so a
downstream victim of an earlier failure is never the accused. -/
theorem blame_cascade {vs : List Verdict} {i : Nat} (h : blame vs = some i) :
    ∀ j, j < i → vs[j]? ≠ some Verdict.absent := by
  obtain ⟨_, _, hfirst⟩ := blameFrom_spec vs 0 i h
  intro j hj
  exact hfirst j (by omega)

theorem blameFrom_none : ∀ (vs : List Verdict) (i : Nat),
    blameFrom i vs = none → ∀ v ∈ vs, v ≠ Verdict.absent := by
  intro vs
  induction vs with
  | nil => intro i _ v hv; simp at hv
  | cons w t ih =>
    intro i h v hv
    cases w with
    | absent => simp [blameFrom] at h
    | live =>
      simp only [blameFrom] at h
      rcases List.mem_cons.mp hv with rfl | hmem
      · simp
      · exact ih (i + 1) h v hmem
    | unknown =>
      simp only [blameFrom] at h
      rcases List.mem_cons.mp hv with rfl | hmem
      · simp
      · exact ih (i + 1) h v hmem

theorem blameFrom_none_of_no_absent : ∀ (vs : List Verdict) (i : Nat),
    (∀ v ∈ vs, v ≠ Verdict.absent) → blameFrom i vs = none := by
  intro vs
  induction vs with
  | nil => intro i _; rfl
  | cons w t ih =>
    intro i h
    cases w with
    | absent => exact absurd rfl (h Verdict.absent (by simp))
    | live => simp only [blameFrom]; exact ih (i + 1) (fun v hv => h v (by simp [hv]))
    | unknown => simp only [blameFrom]; exact ih (i + 1) (fun v hv => h v (by simp [hv]))

/-- **Nothing is blamed exactly when nothing failed.** The vision module reports
`undiagnosed` rather than assuming it empty; this says what that report means. -/
theorem blame_none_iff {vs : List Verdict} :
    blame vs = none ↔ ∀ v ∈ vs, v ≠ Verdict.absent :=
  ⟨blameFrom_none vs 0, blameFrom_none_of_no_absent vs 0⟩

/-- **The honest converse.** Blame is *not* invariant under permuting the stage
list, and must not be: stage order is the ontology's causal order. Fact-arrival
order independence (`orderIndependent_sup_foldl`) and stage-order dependence are
different claims, and only the first one is a law. -/
theorem blame_not_orderIndependent : ¬ OrderIndependent blame := by
  intro h
  have hp : [Verdict.live, Verdict.absent].Perm [Verdict.absent, Verdict.live] :=
    List.Perm.swap Verdict.absent Verdict.live []
  have hcontra := h _ _ hp
  simp [blame, blameFrom] at hcontra

end Ruliad.CausalInvariance
