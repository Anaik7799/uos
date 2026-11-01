/-
# Ruliad.Causal — runs, foliations, and well-defined time

Causal invariance is proved in `Ruliad.Core` as confluence. This module supplies
the other half of the Wolfram-model picture: the **foliation**, the slicing of a
multiway graph into time steps, and the conditions under which "the time of a
state" is a well-defined quantity rather than an artefact of the path taken.

The centrepiece is `unique_path_length`: when every rule application advances a
time function by exactly one, any two computations reaching the same state have
the **same length**. That is what licenses talking about a state's cosmological
time at all, and it is false without the uniformity hypothesis — so the
hypothesis is stated, not assumed away.
-/
import Ruliad.Core
import Ruliad.Branchial

namespace Ruliad.Causal

open Ruliad Ruliad.Branchial

variable {α : Type*} {R : α → α → Prop}

/-! ## Runs -/

/-- A run: the explicit list of intermediate states of a computation. The
multiway graph records that a path exists; a run is the path. -/
inductive Run (R : α → α → Prop) : α → List α → α → Prop where
  | nil (a : α) : Run R a [] a
  | cons {a b c : α} {l : List α} : R a b → Run R b l c → Run R a (b :: l) c

theorem Run.toSteps {a b : α} {l : List α} (h : Run R a l b) : Steps R a b := by
  induction h with
  | nil => exact .refl
  | cons hr _ ih => exact Relation.ReflTransGen.head hr ih

/-- Append one step to the end of a run. `Steps` is built at the tail and a run
at the head, so this is the lemma that connects them. -/
theorem Run.snoc {a b c : α} {l : List α} (h : Run R a l b) :
    R b c → Run R a (l ++ [c]) c := by
  induction h with
  | nil => intro hbc; simpa using Run.cons hbc (Run.nil c)
  | cons hr _ ih => intro hbc; exact Run.cons hr (ih hbc)

/-- Every computation is witnessed by a run: existence of a path and existence
of a reduction are the same claim. -/
theorem exists_run_of_steps {a b : α} (h : Steps R a b) : ∃ l, Run R a l b := by
  induction h with
  | refl => exact ⟨[], Run.nil _⟩
  | tail _ hxy ih =>
    obtain ⟨l, hl⟩ := ih
    exact ⟨_, hl.snoc hxy⟩

/-- Insert a step at the head of a counted computation. -/
theorem stepsN_head {n : Nat} {a b c : α} (h : StepsN R n b c) :
    R a b → StepsN R (n + 1) a c := by
  induction h with
  | zero => intro hab; exact StepsN.succ (StepsN.zero a) hab
  | succ _ hyz ih => intro hab; exact StepsN.succ (ih hab) hyz

/-- A run's length is its step count. -/
theorem run_length_eq_stepsN {a b : α} {l : List α} (h : Run R a l b) :
    StepsN R l.length a b := by
  induction h with
  | nil => exact StepsN.zero _
  | cons hxy _ ih =>
    simp only [List.length_cons]
    exact stepsN_head ih hxy

/-! ## Step counting -/

theorem exists_stepsN_of_steps {a b : α} (h : Steps R a b) : ∃ n, StepsN R n a b := by
  induction h with
  | refl => exact ⟨0, StepsN.zero _⟩
  | tail _ hr ih =>
    obtain ⟨n, hn⟩ := ih
    exact ⟨n + 1, StepsN.succ hn hr⟩

theorem steps_of_stepsN {n : Nat} {a b : α} (h : StepsN R n a b) : Steps R a b :=
  StepsN.toSteps h

/-! ## Foliations

A foliation assigns a time to every state so that one rule application advances
time by exactly one. It is the formal content of a "slice" of the multiway
graph. -/

/-- `time` foliates `R`: every step advances time by exactly one. -/
def Foliation (R : α → α → Prop) (time : α → Nat) : Prop :=
  ∀ x y, R x y → time y = time x + 1

/-- Along any computation, elapsed time is the number of steps. -/
theorem foliation_time {time : α → Nat} (hf : Foliation R time) {n : Nat} {a b : α}
    (h : StepsN R n a b) : time b = time a + n := by
  induction h with
  | zero => simp
  | @succ m x y z hxy hyz ih =>
    rw [hf y z hyz, ih, Nat.add_assoc]

/-- **Cosmological time is well defined.** Under a foliation, any two
computations reaching the same state took the same number of steps. Without the
uniformity hypothesis this fails, which is exactly why a multiway graph needs a
foliation before "the time of a state" means anything. -/
theorem unique_path_length {time : α → Nat} (hf : Foliation R time) {m n : Nat} {a b : α}
    (hm : StepsN R m a b) (hn : StepsN R n a b) : m = n := by
  have h1 := foliation_time hf hm
  have h2 := foliation_time hf hn
  omega

/-- A foliated system has no cycles: time strictly increases, so nothing returns
to itself. Causal loops are excluded by the existence of a foliation, not by
fiat. -/
theorem foliation_acyclic {time : α → Nat} (hf : Foliation R time) {n : Nat} {a : α}
    (h : StepsN R n a a) : n = 0 := by
  have := foliation_time hf h
  omega

/-- No step is a self-loop. -/
theorem foliation_irrefl {time : α → Nat} (hf : Foliation R time) (a : α) : ¬ R a a := by
  intro h
  have := hf a a h
  omega

/-! ## Causally independent events -/

/-- Two events out of the same state are **causally independent** when they
reach distinct states that rejoin in one step each: neither consumed what the
other needed. This is the local shape whose global closure is causal invariance. -/
def Independent (R : α → α → Prop) (a b c : α) : Prop :=
  R a b ∧ R a c ∧ b ≠ c ∧ ∃ d, R b d ∧ R c d

/-- Independent events rejoin on the **next** slice: both orderings land at time
`time a + 2`. Reordering independent events changes nothing observable, which is
the event-level content of causal invariance. -/
theorem independent_rejoins_next_slice {time : α → Nat} (hf : Foliation R time)
    {a b c : α} (h : Independent R a b c) :
    ∃ d, R b d ∧ R c d ∧ time d = time a + 2 := by
  obtain ⟨hab, hac, _, d, hbd, hcd⟩ := h
  refine ⟨d, hbd, hcd, ?_⟩
  rw [hf b d hbd, hf a b hab]

/-- Independence is symmetric in the two events. -/
theorem Independent.symm {a b c : α} (h : Independent R a b c) : Independent R a c b := by
  obtain ⟨hab, hac, hne, d, hbd, hcd⟩ := h
  exact ⟨hac, hab, hne.symm, d, hcd, hbd⟩

/-- Local confluence is exactly "every divergent pair is reconcilable", so a
locally confluent system has no irreconcilable event pair. -/
theorem joinable_of_locallyConfluent (hlc : LocallyConfluent R) {a b c : α}
    (hab : R a b) (hac : R a c) : Joinable R b c := hlc a b c hab hac

/-- Under a foliation, states joined from a common ancestor are joined at a time
no earlier than their own. -/
theorem join_time_ge {time : α → Nat} (hf : Foliation R time) {b c d : α}
    (hbd : Steps R b d) (_hcd : Steps R c d) : time b ≤ time d := by
  obtain ⟨n, hn⟩ := exists_stepsN_of_steps hbd
  have := foliation_time hf hn
  omega

/-!
### Scope, and where the event-level graph lives

This module proves **state-level** causal structure: runs, foliations, time,
independent pairs. Wolfram's causal graph is a graph on **events**, which needs
produce/consume provenance that `List.diff` does not record.

That is no longer a gap: `Ruliad.CausalGraph` supplies it by tokenizing
hyperedges, so an event names exactly what it consumed and produced, and proves
`causal_forward` — no event consumes a token produced by a later event, i.e. the
causal graph is a DAG oriented with the update order.
-/

end Ruliad.Causal
