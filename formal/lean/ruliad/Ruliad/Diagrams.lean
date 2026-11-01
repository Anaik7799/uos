/-
# Ruliad.Diagrams — the confluence lattice

The implication lattice around confluence, in the vocabulary of
[`leanprover/cslib`](https://github.com/leanprover/cslib) `Foundations/Relation/Confluence.lean`
(Apache-2.0): `Diamond`, `SemiConfluent`, `ChurchRosser`, `Normalizing`,
`Convergent`, `Commute`. Names are deliberately the same so that a later
toolchain bump can swap this module for a `require` on cslib without touching
the modules above it.

**cslib is not a dependency here, and cannot currently be one:** it pins
`leanprover/lean4:v4.36.0-rc2` against this repository's pinned 4.33.0, and a
Lake workspace has exactly one toolchain. Adopting it means bumping Lean for
every file under `formal/lean/`, which is an operator decision, not a local one.
-/
import Ruliad.Core

namespace Ruliad

open Relation

variable {α : Type*} {R R₁ R₂ : α → α → Prop}

/-! ## Strengthenings of confluence -/

/-- One step each side, rejoined in at most one step each. The strongest and
cheapest-to-check condition. -/
def Diamond (R : α → α → Prop) : Prop :=
  ∀ a b c, R a b → R a c → ∃ d, ReflGen R b d ∧ ReflGen R c d

/-- One step against many, rejoined. Equivalent to confluence, and the form
Mathlib's `church_rosser` consumes. -/
def SemiConfluent (R : α → α → Prop) : Prop :=
  ∀ a b c, R a b → Steps R a c → Joinable R b c

/-- Convertible states are joinable. -/
def ChurchRosser (R : α → α → Prop) : Prop :=
  ∀ a b, EqvGen R a b → Joinable R a b

theorem Diamond.to_semiConfluent (h : Diamond R) : SemiConfluent R := by
  intro a b c hab hac
  exact church_rosser (fun x y z hy hz =>
    let ⟨d, hyd, hzd⟩ := h x y z hy hz
    ⟨d, hyd, hzd.to_reflTransGen⟩) (ReflTransGen.single hab) hac

theorem Diamond.to_confluent (h : Diamond R) : Confluent R := by
  intro a b c hab hac
  exact church_rosser (fun x y z hy hz =>
    let ⟨d, hyd, hzd⟩ := h x y z hy hz
    ⟨d, hyd, hzd.to_reflTransGen⟩) hab hac

/-- Semi-confluence gives confluence. The induction that makes `church_rosser`
usable from a one-step-versus-many hypothesis. -/
theorem SemiConfluent.to_confluent (h : SemiConfluent R) : Confluent R := by
  intro a b c hab
  induction hab with
  | refl => intro hac; exact ⟨c, hac, .refl⟩
  | @tail d e hde hef ih =>
    intro hac
    obtain ⟨g, hdg, hcg⟩ := ih hac
    obtain ⟨k, hek, hgk⟩ := h d e g hef hdg
    exact ⟨k, hek, hcg.trans hgk⟩

theorem Confluent.to_churchRosser (h : Confluent R) : ChurchRosser R := by
  intro a b hab
  induction hab with
  | rel _ _ hr => exact ⟨_, ReflTransGen.single hr, .refl⟩
  | refl => exact Joinable.rfl _
  | symm _ _ _ ih => exact ih.symm
  | trans x y z _ _ ihxy ihyz =>
    obtain ⟨d, hxd, hyd⟩ := ihxy
    obtain ⟨e, hye, hze⟩ := ihyz
    obtain ⟨f, hdf, hef⟩ := h y d e hyd hye
    exact ⟨f, hxd.trans hdf, hze.trans hef⟩

theorem Confluent.to_locallyConfluent (h : Confluent R) : LocallyConfluent R :=
  fun a b c hab hac => h a b c (ReflTransGen.single hab) (ReflTransGen.single hac)

/-! ## Normal forms -/

/-- Every state reaches some normal form. -/
def Normalizing (R : α → α → Prop) : Prop := ∀ a, ∃ b, Steps R a b ∧ NormalForm R b

/-- Terminating and confluent: every state has exactly one normal form. -/
def Convergent (R : α → α → Prop) : Prop := Confluent R ∧ Terminating R

theorem Terminating.to_normalizing (ht : Terminating R) : Normalizing R := by
  intro a
  refine WellFounded.induction ht (C := fun x => ∃ b, Steps R x b ∧ NormalForm R b) a ?_
  intro x ih
  by_cases hnf : ∀ y, ¬ R x y
  · exact ⟨x, .refl, hnf⟩
  · obtain ⟨y, hy⟩ := not_forall.mp hnf
    obtain ⟨b, hyb, hb⟩ := ih y (not_not.mp hy)
    exact ⟨b, ReflTransGen.head (not_not.mp hy) hyb, hb⟩

/-- **The operational payoff.** A convergent system assigns every state exactly
one normal form: a well-defined, observer-independent answer. -/
theorem Convergent.unique_normal (h : Convergent R) (a : α) :
    ∃! b, Steps R a b ∧ NormalForm R b := by
  obtain ⟨b, hab, hb⟩ := h.2.to_normalizing a
  refine ⟨b, ⟨hab, hb⟩, ?_⟩
  intro c hc
  exact (unique_normalForm h.1 hc.1 hab hc.2 hb)

theorem Convergent.of_newman (ht : Terminating R) (hlc : LocallyConfluent R) :
    Convergent R := ⟨newman ht hlc, ht⟩

/-! ## Commutation (Hindley–Rosen)

Commutation of two rule sets is what lets a system be analysed rule-family by
rule-family instead of all at once. The definitions and the cheap implications
are here; the full Hindley–Rosen theorem is **not proved** — see the gap note. -/

/-- Two rule sets commute: divergence with one step of each can be rejoined. -/
def Commute (R₁ R₂ : α → α → Prop) : Prop :=
  ∀ a b c, Steps R₁ a b → Steps R₂ a c → ∃ d, Steps R₂ b d ∧ Steps R₁ c d

/-- One step of each, rejoined in at most one step each. -/
def DiamondCommute (R₁ R₂ : α → α → Prop) : Prop :=
  ∀ a b c, R₁ a b → R₂ a c → ∃ d, ReflGen R₂ b d ∧ ReflGen R₁ c d

theorem Commute.self_iff_confluent : Commute R R ↔ Confluent R := by
  constructor
  · intro h a b c hab hac
    obtain ⟨d, hbd, hcd⟩ := h a b c hab hac
    exact ⟨d, hbd, hcd⟩
  · intro h a b c hab hac
    obtain ⟨d, hbd, hcd⟩ := h a b c hab hac
    exact ⟨d, hbd, hcd⟩

theorem Commute.symm (h : Commute R₁ R₂) : Commute R₂ R₁ := by
  intro a b c hab hac
  obtain ⟨d, hbd, hcd⟩ := h a c b hac hab
  exact ⟨d, hcd, hbd⟩

/-- The union of two rule sets, as a relation. A rulial slice containing two
rule families is exactly this. -/
def Union (R₁ R₂ : α → α → Prop) : α → α → Prop := fun a b => R₁ a b ∨ R₂ a b

theorem steps_union_left (h : Steps R₁ a b) : Steps (Union R₁ R₂) a b := by
  induction h with
  | refl => exact .refl
  | tail _ hr ih => exact ReflTransGen.tail ih (Or.inl hr)

theorem steps_union_right (h : Steps R₂ a b) : Steps (Union R₁ R₂) a b := by
  induction h with
  | refl => exact .refl
  | tail _ hr ih => exact ReflTransGen.tail ih (Or.inr hr)

/-- Joining inside one family still joins inside the union, so a per-family
analysis is never *weaker* than a whole-system one. -/
theorem joinable_union_of_left (h : Joinable R₁ a b) : Joinable (Union R₁ R₂) a b :=
  let ⟨d, ha, hb⟩ := h; ⟨d, steps_union_left ha, steps_union_left hb⟩

theorem joinable_union_of_right (h : Joinable R₂ a b) : Joinable (Union R₁ R₂) a b :=
  let ⟨d, ha, hb⟩ := h; ⟨d, steps_union_right ha, steps_union_right hb⟩

/-!
### Gap, stated rather than papered over

**Hindley–Rosen, terminating case, is now proved** — see
`Ruliad.Bridge.confluent_union_of_terminating`: a combined rule set whose union
terminates is confluent as soon as each family is locally confluent and the
families commute locally. Rule-family-wise analysis is licensed under
termination.

Still open: the **classical** form without termination,
`Confluent R₁ → Confluent R₂ → Commute R₁ R₂ → Confluent (Union R₁ R₂)`. The
tiling argument needs a nested induction over an interleaved `ReflTransGen` in
the union. A combined rule set can be confluent without terminating, so the
restriction is real and not cosmetic.
-/

end Ruliad
