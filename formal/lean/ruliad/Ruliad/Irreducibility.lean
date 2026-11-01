/-
# Ruliad.Irreducibility — what "you have to run it" can and cannot mean

Computational irreducibility is the claim that no shortcut predicts a system's
behaviour: you have to run it. That phrase covers two very different kinds of
statement, and conflating them is how the vocabulary stops meaning anything.

**Provable here.** Bounded reachability is decidable for a finitely branching
rule system (`boundedReach`, sound and complete), and no *uniform* step bound
exists: for the simplest possible counter system, the number of steps to a
normal form is unbounded over initial states, so no fixed-depth search answers
reachability in general. That is the precise, modest content of "you have to
run it".

**Not provable here, and not claimed.** That reachability is *undecidable*, or
that no polynomial-time shortcut exists, for any particular rule set. Those need
a universality construction for that rule set — a simulation of a universal
machine — which this module does not contain. Mathlib has the machinery
(`Mathlib/Computability/`, `Turing`, `Nat.Partrec.Code`); wiring a specific
Wolfram-model rule to it is a separate piece of work, and until it exists,
"irreducible" must not be asserted of any rule here.
-/
import Ruliad.Core
import Ruliad.Branchial
import Ruliad.Causal
import Mathlib.Data.List.Basic

namespace Ruliad.Irreducibility

open Ruliad Ruliad.Branchial

variable {α : Type*}

/-! ## Finitely branching systems -/

/-- A rule system given by its successor function: what an implementation
actually has, as opposed to an abstract relation. -/
structure Branching (α : Type*) where
  succs : α → List α

/-- The relation a successor function induces. -/
def Branching.rel (B : Branching α) (a b : α) : Prop := b ∈ B.succs a

instance (B : Branching α) [DecidableEq α] (a b : α) : Decidable (B.rel a b) := by
  unfold Branching.rel; infer_instance

/-- Every state reachable in at most `n` steps. This is the bounded search an
engine can actually perform. -/
def boundedReach (B : Branching α) (a : α) : Nat → List α
  | 0 => [a]
  | n + 1 => (boundedReach B a n).flatMap fun x => x :: B.succs x

theorem mem_boundedReach_zero (B : Branching α) (a : α) : a ∈ boundedReach B a 0 := by
  simp [boundedReach]

theorem boundedReach_mono (B : Branching α) (a : α) :
    ∀ (n : Nat) (x : α), x ∈ boundedReach B a n → x ∈ boundedReach B a (n + 1) := by
  intro n x hx
  simp only [boundedReach, List.mem_flatMap]
  exact ⟨x, hx, by simp⟩

/-- **Soundness of bounded search.** Everything it reports is genuinely
reachable: a bounded search never invents a state. -/
theorem boundedReach_sound (B : Branching α) (a : α) :
    ∀ (n : Nat) (x : α), x ∈ boundedReach B a n → Steps B.rel a x := by
  intro n
  induction n with
  | zero => intro x hx; simp only [boundedReach, List.mem_singleton] at hx; exact hx ▸ .refl
  | succ n ih =>
    intro x hx
    simp only [boundedReach, List.mem_flatMap, List.mem_cons] at hx
    obtain ⟨y, hy, hxy⟩ := hx
    rcases hxy with rfl | hmem
    · exact ih x hy
    · exact Relation.ReflTransGen.tail (ih y hy) hmem

/-- Invert one `StepsN` step. -/
theorem stepsN_succ_inv {R : α → α → Prop} {n : Nat} {a c : α}
    (h : StepsN R (n + 1) a c) : ∃ b, StepsN R n a b ∧ R b c := by
  cases h with
  | succ hp hs => exact ⟨_, hp, hs⟩

/-- **Completeness of bounded search at its own depth.** Anything reachable in
exactly `n` steps is found by depth `n`. Together with soundness, the engine's
answer at a given depth is exactly right — the limitation is the depth, not the
search. -/
theorem boundedReach_complete (B : Branching α) (a : α) :
    ∀ (n : Nat) (x : α), StepsN B.rel n a x → x ∈ boundedReach B a n := by
  intro n
  induction n with
  | zero =>
    intro x hx
    cases hx
    exact mem_boundedReach_zero B a
  | succ n ih =>
    intro x hx
    obtain ⟨y, hprev, hstep⟩ := stepsN_succ_inv hx
    simp only [boundedReach, List.mem_flatMap, List.mem_cons]
    exact ⟨y, ih y hprev, Or.inr hstep⟩

/-- So bounded reachability is decidable: an engine can always answer "within
`n` steps?". -/
instance (B : Branching α) [DecidableEq α] (a x : α) (n : Nat) :
    Decidable (x ∈ boundedReach B a n) := by infer_instance

/-! ## No uniform step bound

The simplest possible system: a counter that decrements to zero. Its normal form
is reached in exactly `n` steps from `n`, so the step count is unbounded across
initial states. No fixed depth suffices for all of them. -/

/-- Decrement-to-zero. -/
def counter : Branching Nat where
  succs := fun n => match n with | 0 => [] | m + 1 => [m]

theorem counter_rel_iff {a b : Nat} : counter.rel a b ↔ a = b + 1 := by
  cases a with
  | zero => simp [Branching.rel, counter]
  | succ m => simp [Branching.rel, counter, eq_comm]

theorem counter_normalForm_zero : NormalForm counter.rel 0 := by
  intro b hb
  rw [counter_rel_iff] at hb
  omega

/-- From `n`, exactly `n` steps reach the normal form. -/
theorem counter_stepsN : ∀ n : Nat, StepsN counter.rel n n 0
  | 0 => StepsN.zero 0
  | n + 1 => Ruliad.Causal.stepsN_head (counter_stepsN n) (by rw [counter_rel_iff])

/-- **No uniform step bound.** For every candidate depth `k` there is an initial
state whose computation is longer. A bounded search is therefore always
incomplete for *some* input, which is the precise sense in which the system has
to be run rather than consulted. -/
theorem no_uniform_step_bound (k : Nat) :
    ∃ (a : Nat) (n : Nat), k < n ∧ StepsN counter.rel n a 0 ∧ NormalForm counter.rel 0 :=
  ⟨k + 1, k + 1, by omega, counter_stepsN (k + 1), counter_normalForm_zero⟩

/-!
### The boundary, restated

`no_uniform_step_bound` says a *fixed depth* cannot answer every instance. It
does **not** say reachability is undecidable: for `counter` it plainly is
decidable — `a` reaches `0` always, in `a` steps. Irreducibility in the strong
sense is a statement about a *universal* rule set, and this module proves
nothing of the kind for any rule set in this repository. Any claim that a UOS
rule system is computationally irreducible is, at present, unsupported.
-/

end Ruliad.Irreducibility
