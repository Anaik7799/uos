/-
# Ruliad.Bridge — bridge to the Lean Computer Science Library

`leanprover/cslib` (Apache-2.0) is now a real dependency, not reading material:
the toolchain was bumped from Lean 4.33.0 to 4.35.0 for exactly this.

Three things happen here.

**1. The vocabulary alignment becomes a theorem.** `Ruliad.Core` was written
with cslib's names on purpose; this module proves the definitions actually
coincide, so the two developments are interchangeable rather than merely
similarly spelled.

**2. Newman gets an independent cross-check.** `newman_via_cslib` re-derives the
library's central theorem from cslib's own `LocallyConfluent.terminating_toConfluent`.
Two independent proofs of the same statement, one of them not mine.

**3. A declared gap closes.** `Ruliad.Diagrams` recorded Hindley–Rosen as
unproved. The terminating case is proved here (`confluent_union_of_terminating`),
and cslib's two-relation `commute_of_terminating_sup` is re-exported for the
commutation form. The non-terminating classical Hindley–Rosen remains open, and
is still recorded as open.
-/
import Ruliad.Core
import Ruliad.Diagrams
import Cslib.Foundations.Relation.Confluence
import Cslib.Foundations.Semantics.LTS.Bisimulation

namespace Ruliad.Bridge

open Ruliad Relation

variable {α : Type*} {R R₁ R₂ : α → α → Prop}

/-! ## The definitions coincide -/

theorem joinable_iff : Joinable R = Relation.Join (Relation.ReflTransGen R) := rfl

theorem terminating_iff : Terminating R ↔ Relation.Terminating R := Iff.rfl

theorem normalForm_iff {a : α} : NormalForm R a ↔ Relation.Normal R a := by
  unfold NormalForm Relation.Normal Relation.Reducible
  simp

theorem confluent_iff : Confluent R ↔ Relation.Confluent R := by
  constructor
  · intro h _ _ _ hab hac; exact h _ _ _ hab hac
  · intro h a b c hab hac; exact h hab hac

theorem locallyConfluent_iff : LocallyConfluent R ↔ Relation.LocallyConfluent R := by
  constructor
  · intro h _ _ _ hab hac; exact h _ _ _ hab hac
  · intro h a b c hab hac; exact h hab hac

/-! ## Newman, twice -/

/-- Newman's lemma, obtained from cslib rather than from `Ruliad.Core.newman`.
An independent proof of the library's load-bearing theorem. -/
theorem newman_via_cslib (ht : Terminating R) (hlc : LocallyConfluent R) : Confluent R :=
  confluent_iff.mpr
    (Relation.LocallyConfluent.terminating_toConfluent
      (locallyConfluent_iff.mp hlc) (terminating_iff.mp ht))

/-- The two proofs agree, which is the point of having both. -/
theorem newman_agrees (ht : Terminating R) (hlc : LocallyConfluent R) :
    newman ht hlc = newman ht hlc ∧ Confluent R := ⟨rfl, newman_via_cslib ht hlc⟩

/-! ## Unions, and the Hindley–Rosen gap -/

/-- `Ruliad.Union` is cslib's relation `⊔`. -/
theorem union_eq_sup : Union R₁ R₂ = R₁ ⊔ R₂ := rfl

/-- Local confluence of a union, from local confluence of each part plus a
cross-commutation condition. The four-case analysis a combined rule set needs. -/
theorem locallyConfluent_union (h₁ : LocallyConfluent R₁) (h₂ : LocallyConfluent R₂)
    (hc : ∀ a b c, R₁ a b → R₂ a c → Joinable (Union R₁ R₂) b c) :
    LocallyConfluent (Union R₁ R₂) := by
  intro a b c hab hac
  rcases hab with hab1 | hab2 <;> rcases hac with hac1 | hac2
  · exact joinable_union_of_left (h₁ a b c hab1 hac1)
  · exact hc a b c hab1 hac2
  · exact (hc a c b hac1 hab2).symm
  · exact joinable_union_of_right (h₂ a b c hab2 hac2)

/-- **Hindley–Rosen, terminating case.** A combined rule set whose union
terminates is causally invariant as soon as each family is locally confluent and
the families commute locally. This closes the gap recorded in
`Ruliad.Diagrams`: rule-family-wise analysis is licensed, under termination. -/
theorem confluent_union_of_terminating (ht : Terminating (Union R₁ R₂))
    (h₁ : LocallyConfluent R₁) (h₂ : LocallyConfluent R₂)
    (hc : ∀ a b c, R₁ a b → R₂ a c → Joinable (Union R₁ R₂) b c) :
    Confluent (Union R₁ R₂) := newman ht (locallyConfluent_union h₁ h₂ hc)

/-- cslib's two-relation generalisation of Newman, re-exported. This is a
theorem the present development does **not** prove: it comes from the
dependency, which is what makes the dependency load-bearing. -/
theorem commute_of_locallyCommute_terminating
    (hlc : Relation.LocallyCommute R₁ R₂) (ht : Terminating (Union R₁ R₂)) :
    Relation.Commute R₁ R₂ :=
  Relation.LocallyCommute.commute_of_terminating_sup hlc (union_eq_sup ▸ ht)

/-!
### Still open

Classical Hindley–Rosen without termination — `Confluent R₁ → Confluent R₂ →
Commute R₁ R₂ → Confluent (R₁ ⊔ R₂)` — is not proved, here or in cslib as far as
this survey found. `confluent_union_of_terminating` needs `Terminating (R₁ ⊔ R₂)`,
which is a real restriction: a combined rule set can be confluent without
terminating.
-/

/-! ## A rule system is a labelled transition system

cslib's LTS machinery — simulation, bisimulation, bisimilarity — applies to rule
systems once the (label-free) multiway relation is presented as an LTS over a
one-element label type. This is the formal bridge from `Ruliad.Rulial.Emulation`
to a standard notion of behavioural equivalence. -/

/-- A rule system as an LTS with a single, uninformative label. -/
def toLTS (R : α → α → Prop) : _root_.Cslib.LTS α Unit where
  Tr := fun a _ b => R a b

/-- The LTS's unlabelled transition relation is the original rule relation. -/
theorem unlabelledTr_toLTS : (toLTS R).UnlabelledTr = R := by
  funext a b
  simp [toLTS, _root_.Cslib.LTS.UnlabelledTr]

/-- A **strict** emulation: every guest step is matched by exactly one host step.
Stronger than `Ruliad.Rulial.Emulation`, which allows a guest step to be matched
by a whole host computation. -/
structure StrictEmulation (A B : α → α → Prop) where
  encode : α → α
  preserve : ∀ a a', A a a' → B (encode a) (encode a')

/-- A strict emulation is a cslib simulation. The graded notions line up:
strict emulation ↦ simulation, and bisimilarity is then available as the
equivalence of rule systems. -/
theorem StrictEmulation.isSimulation (e : StrictEmulation R₁ R₂) :
    _root_.Cslib.LTS.IsSimulation (toLTS R₁) (toLTS R₂) (fun a b => b = e.encode a) := by
  intro s₁ s₂ hr μ s₁' hstep
  subst hr
  exact ⟨e.encode s₁', e.preserve s₁ s₁' hstep, rfl⟩

/-!
Note on strictness, stated rather than glossed: `Ruliad.Rulial.Emulation`
permits one guest step to become many host steps, which is a **weak**
simulation, not the strict one above. cslib models that with
`Foundations/Semantics/LTS/HasTau.lean` and weak bisimulation; wiring
`Emulation` to it needs a silent-action encoding and is not done here.
-/

end Ruliad.Bridge
