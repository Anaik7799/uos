/-
# Ruliad.Branchial — branchial space, and the deployed distance formula

Two things live here.

**1. The branchial relation.** Two states are branchially related at depth `n`
when a common ancestor reaches both in exactly `n` steps. It is reflexive and
symmetric, and — stated as a theorem, not a caveat — it is **not transitive**.
Anything that treats `branchial_distance` as a metric on states, rather than as
a chordal distance on an embedding, is relying on something false.

**2. `simd_ruliad_branchial_distance`.** The deployed Mojo kernel
(`services/inference/max/max_kernel.mojo:349`) computes
`D = sqrt(2 * (1 - cos_sim))`, clamped to `[0, 2]`. This module proves that
formula *is* the Euclidean distance between unit vectors, so the triangle
inequality the merge gate implicitly assumes comes for free from
`PseudoMetricSpace`, and the clamp is shown to agree with the formula at both
endpoints rather than being an arbitrary guard.
-/
import Ruliad.Core
import Mathlib.Analysis.InnerProductSpace.Basic
import Mathlib.Analysis.SpecialFunctions.Sqrt

namespace Ruliad.Branchial

open Ruliad

variable {α : Type*}

/-! ## Step-indexed reachability (a foliation of the multiway graph) -/

/-- `StepsN R n a b`: `b` is reached from `a` in exactly `n` rule applications. -/
inductive StepsN (R : α → α → Prop) : Nat → α → α → Prop where
  | zero (a : α) : StepsN R 0 a a
  | succ {n : Nat} {a b c : α} : StepsN R n a b → R b c → StepsN R (n + 1) a c

theorem StepsN.toSteps {R : α → α → Prop} {n : Nat} {a b : α}
    (h : StepsN R n a b) : Steps R a b := by
  induction h with
  | zero => exact .refl
  | succ _ hr ih => exact .tail ih hr

/-- Branchial relatedness at depth `n`: a shared ancestor, equal elapsed steps.
This is the "same slice of the multiway graph" relation. -/
def CoReach (R : α → α → Prop) (n : Nat) (a b : α) : Prop :=
  ∃ root, StepsN R n root a ∧ StepsN R n root b

theorem CoReach.refl {R : α → α → Prop} {n : Nat} {a b : α}
    (h : StepsN R n a b) : CoReach R n b b := ⟨a, h, h⟩

theorem CoReach.symm {R : α → α → Prop} {n : Nat} {a b : α}
    (h : CoReach R n a b) : CoReach R n b a :=
  let ⟨root, ha, hb⟩ := h; ⟨root, hb, ha⟩

/-- **Branchial relatedness is not transitive.** Witness: three leaves at depth 1
under two different roots, where `b` is shared but `a` and `c` are not.

`R`: `0 → 1`, `0 → 2`, `3 → 2`, `3 → 4`. Then `1 ~ 2` (root 0) and `2 ~ 4`
(root 3), but `1 ≁ 4`: no state reaches both in one step. -/
private def BadR : Nat → Nat → Prop := fun x y =>
  (x = 0 ∧ y = 1) ∨ (x = 0 ∧ y = 2) ∨ (x = 3 ∧ y = 2) ∨ (x = 3 ∧ y = 4)

theorem branchial_not_transitive :
    ¬ ∀ (R : Nat → Nat → Prop) (n : Nat) (a b c : Nat),
        CoReach R n a b → CoReach R n b c → CoReach R n a c := by
  intro htrans
  have h01 : StepsN BadR 1 0 1 := .succ (.zero 0) (by unfold BadR; tauto)
  have h02 : StepsN BadR 1 0 2 := .succ (.zero 0) (by unfold BadR; tauto)
  have h32 : StepsN BadR 1 3 2 := .succ (.zero 3) (by unfold BadR; tauto)
  have h34 : StepsN BadR 1 3 4 := .succ (.zero 3) (by unfold BadR; tauto)
  obtain ⟨root, hr1, hr4⟩ := htrans BadR 1 1 2 4 ⟨0, h01, h02⟩ ⟨3, h32, h34⟩
  cases hr1 with
  | succ hz h1 =>
    cases hz with
    | zero =>
      cases hr4 with
      | succ hz' h4 =>
        cases hz' with
        | zero =>
          unfold BadR at h1 h4
          rcases h1 with ⟨ha, hb⟩ | ⟨ha, hb⟩ | ⟨ha, hb⟩ | ⟨ha, hb⟩ <;>
            rcases h4 with ⟨hc, hd⟩ | ⟨hc, hd⟩ | ⟨hc, hd⟩ | ⟨hc, hd⟩ <;> omega

/-! ## The deployed distance formula -/

/-- Exactly `simd_ruliad_branchial_distance`: the chordal distance with the
kernel's two clamps. -/
noncomputable def bdist (sim : ℝ) : ℝ :=
  if 1 ≤ sim then 0
  else if sim ≤ -1 then 2
  else Real.sqrt (2 * (1 - sim))

theorem bdist_nonneg (sim : ℝ) : 0 ≤ bdist sim := by
  unfold bdist
  split
  · exact le_refl 0
  · split
    · norm_num
    · exact Real.sqrt_nonneg _

theorem bdist_le_two (sim : ℝ) : bdist sim ≤ 2 := by
  unfold bdist
  split
  · norm_num
  · split
    · exact le_refl 2
    · rename_i h1 h2
      have hs : 2 * (1 - sim) ≤ 4 := by
        simp only [not_le] at h2
        linarith
      calc Real.sqrt (2 * (1 - sim)) ≤ Real.sqrt 4 := Real.sqrt_le_sqrt hs
        _ = 2 := by
            rw [show (4 : ℝ) = 2 ^ 2 by norm_num, Real.sqrt_sq (by norm_num : (0:ℝ) ≤ 2)]

/-- Identical branches are at distance zero. -/
theorem bdist_self : bdist 1 = 0 := by simp [bdist]

/-- The upper clamp is not arbitrary: at `sim = -1` the formula already gives 2,
so clamping is continuous rather than a discontinuous guard. -/
theorem bdist_formula_at_neg_one : Real.sqrt (2 * (1 - (-1 : ℝ))) = 2 := by
  norm_num
  rw [show (4 : ℝ) = 2 ^ 2 by norm_num, Real.sqrt_sq (by norm_num : (0:ℝ) ≤ 2)]

/-- Likewise at the lower clamp: the formula gives 0 at `sim = 1`. -/
theorem bdist_formula_at_one : Real.sqrt (2 * (1 - (1 : ℝ))) = 0 := by norm_num

/-- **More similar is never further apart**, on the unclamped interval. This is
the property the merge gate's ordering actually depends on. -/
theorem bdist_antitone_core {s t : ℝ} (hs : -1 < s) (ht : t < 1) (hst : s ≤ t) :
    bdist t ≤ bdist s := by
  unfold bdist
  rw [ite_eq_right (by linarith : ¬ (1 : ℝ) ≤ t), ite_eq_right (by linarith : ¬ t ≤ -1)]
  by_cases h1 : (1 : ℝ) ≤ s
  · exact absurd ht (not_lt.mpr (le_trans h1 hst))
  · rw [ite_eq_right h1, ite_eq_right (by linarith : ¬ s ≤ -1)]
    exact Real.sqrt_le_sqrt (by linarith)

/-! ## Why the triangle inequality holds

The formula is the Euclidean distance between unit vectors, so it inherits a
genuine metric from the ambient inner product space. The merge gate may compose
distances; this is the theorem that licenses it. -/

variable {E : Type*} [NormedAddCommGroup E] [InnerProductSpace ℝ E]

/-- `sqrt (2 (1 - ⟪a,b⟫))` **is** `dist a b` for unit vectors. -/
theorem dist_eq_bdist_inner {a b : E} (ha : ‖a‖ = 1) (hb : ‖b‖ = 1) :
    dist a b = Real.sqrt (2 * (1 - inner ℝ a b)) := by
  have hsq : ‖a - b‖ ^ 2 = 2 * (1 - inner ℝ a b) := by
    rw [norm_sub_sq_real, ha, hb]
    ring
  rw [dist_eq_norm, ← hsq, Real.sqrt_sq (norm_nonneg _)]

/-- Consequently the deployed distance satisfies the triangle inequality on unit
embeddings — inherited, not assumed. -/
theorem bdist_triangle {a b c : E} (ha : ‖a‖ = 1) (hb : ‖b‖ = 1) (hc : ‖c‖ = 1) :
    Real.sqrt (2 * (1 - inner ℝ a c)) ≤
      Real.sqrt (2 * (1 - inner ℝ a b)) + Real.sqrt (2 * (1 - inner ℝ b c)) := by
  rw [← dist_eq_bdist_inner ha hc, ← dist_eq_bdist_inner ha hb, ← dist_eq_bdist_inner hb hc]
  exact dist_triangle a b c

end Ruliad.Branchial
