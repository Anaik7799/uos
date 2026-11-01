/-
# Ruliad.Entropy — branchial Shannon entropy and the 2.50-bit gate

The system gates on branchial / fractal-layer entropy at `H ≥ 2.50 bits`
(`CHK-09-MATH`, and `KMP-ENTROPY` in `tools/km-gate`). That threshold is used
operationally but has never been tied to anything provable. This module supplies
the missing arithmetic, and in particular the structural consequence:

  **a 2.50-bit floor is unsatisfiable with fewer than six distinct branches.**

So a corpus with five tags, or a multiway frontier with five states, cannot pass
the gate no matter how the mass is arranged. The gate is a statement about
branch *count* as much as about balance.

Reused from Mathlib: `Real.negMulLog`, `Real.negMulLog_nonneg`,
`Real.log_le_sub_one_of_pos`, `Real.logb`, `Real.log_pow`, `Real.log_lt_log`,
`Finset.single_le_sum`.
-/
import Mathlib.Analysis.SpecialFunctions.Log.NegMulLog
import Mathlib.Analysis.SpecialFunctions.Log.Base

namespace Ruliad.Entropy

open Finset Real

/-- A distribution over branches: the shape both `branchial_entropy` and the KM
fractal-layer histogram actually carry. -/
structure BranchDist (ι : Type*) [Fintype ι] where
  p : ι → ℝ
  nonneg : ∀ i, 0 ≤ p i
  sum_one : ∑ i, p i = 1

variable {ι : Type*} [Fintype ι]

theorem BranchDist.le_one (d : BranchDist ι) (i : ι) : d.p i ≤ 1 := by
  calc d.p i ≤ ∑ j, d.p j := Finset.single_le_sum (fun j _ => d.nonneg j) (mem_univ i)
    _ = 1 := d.sum_one

/-- Shannon entropy in **nats**. -/
noncomputable def H (d : BranchDist ι) : ℝ := ∑ i, Real.negMulLog (d.p i)

/-- Shannon entropy in **bits**: the unit the gate is written in. -/
noncomputable def Hbits (d : BranchDist ι) : ℝ := H d / Real.log 2

theorem H_nonneg (d : BranchDist ι) : 0 ≤ H d :=
  Finset.sum_nonneg fun i _ => Real.negMulLog_nonneg (d.nonneg i) (d.le_one i)

theorem Hbits_nonneg (d : BranchDist ι) : 0 ≤ Hbits d :=
  div_nonneg (H_nonneg d) (Real.log_nonneg (by norm_num))

/-! ## Maximum entropy (Gibbs)

Per-branch form of Gibbs' inequality, via `log x ≤ x - 1`. Stated for one term so
the zero-probability case is handled where it actually arises, instead of being
excluded by a side condition nobody can discharge for a real histogram. -/

theorem negMulLog_sub_le {k : ℝ} (hk : 0 < k) {p : ℝ} (hp : 0 ≤ p) :
    Real.negMulLog p - p * Real.log k ≤ 1 / k - p := by
  rcases eq_or_lt_of_le hp with rfl | hpos
  · simp only [Real.negMulLog, neg_zero, zero_mul, sub_zero]
    positivity
  · have hpk : 0 < p * k := mul_pos hpos hk
    have hlog : Real.log (1 / (p * k)) ≤ 1 / (p * k) - 1 :=
      Real.log_le_sub_one_of_pos (by positivity)
    have hexp : Real.negMulLog p - p * Real.log k = p * Real.log (1 / (p * k)) := by
      rw [Real.log_div one_ne_zero (ne_of_gt hpk), Real.log_one,
        Real.log_mul (ne_of_gt hpos) (ne_of_gt hk), Real.negMulLog]
      ring
    rw [hexp]
    calc p * Real.log (1 / (p * k)) ≤ p * (1 / (p * k) - 1) :=
          mul_le_mul_of_nonneg_left hlog hp
      _ = 1 / k - p := by field_simp
      _ ≤ 1 / k - p := le_refl _

/-- **Maximum entropy.** Entropy never exceeds the log of the number of branches. -/
theorem H_le_log_card (d : BranchDist ι) [Nonempty ι] :
    H d ≤ Real.log (Fintype.card ι) := by
  have hk : (0 : ℝ) < (Fintype.card ι : ℝ) := by exact_mod_cast Fintype.card_pos
  have hsum := Finset.sum_le_sum (fun i (_ : i ∈ (univ : Finset ι)) =>
    negMulLog_sub_le hk (d.nonneg i))
  have hL : ∑ i, (Real.negMulLog (d.p i) - d.p i * Real.log (Fintype.card ι))
      = H d - Real.log (Fintype.card ι) := by
    unfold H
    rw [Finset.sum_sub_distrib, ← Finset.sum_mul, d.sum_one, one_mul]
  have hR : ∑ _i : ι, ((1 : ℝ) / (Fintype.card ι : ℝ) - d.p _i) = 0 := by
    rw [Finset.sum_sub_distrib, Finset.sum_const, card_univ, nsmul_eq_mul, d.sum_one,
      show (Fintype.card ι : ℝ) * (1 / (Fintype.card ι : ℝ)) = 1 by field_simp, sub_self]
  rw [hL, hR] at hsum
  linarith

/-- Entropy in bits never exceeds `logb 2` of the branch count. -/
theorem Hbits_le_logb_card (d : BranchDist ι) [Nonempty ι] :
    Hbits d ≤ Real.logb 2 (Fintype.card ι) := by
  have hlog2 : (0 : ℝ) < Real.log 2 := Real.log_pos (by norm_num)
  rw [Hbits, Real.logb, div_le_div_iff_of_pos_right hlog2]
  exact H_le_log_card d

/-! ## The gate -/

/-- `logb 2 5 < 5/2`, because `25 < 32`. The whole 2.50-bit threshold turns on
this one integer comparison. -/
theorem logb_five_lt : Real.logb 2 5 < 5 / 2 := by
  have hlog2 : (0 : ℝ) < Real.log 2 := Real.log_pos (by norm_num)
  have h25 : Real.log ((5 : ℝ) ^ (2 : ℕ)) < Real.log ((2 : ℝ) ^ (5 : ℕ)) :=
    Real.log_lt_log (by norm_num) (by norm_num)
  rw [Real.log_pow, Real.log_pow] at h25
  push_cast at h25
  rw [Real.logb, div_lt_iff₀ hlog2]
  linarith

/-- **The 2.50-bit floor forces at least six branches.**

A distribution over five or fewer branches cannot reach 2.50 bits. So when
`tools/km-gate` reports `KMP-ENTROPY` below the floor, no reweighting of an
existing five-way split can fix it — the taxonomy needs more occupied classes. -/
theorem six_branches_of_gate (d : BranchDist ι) [Nonempty ι]
    (hgate : (5 : ℝ) / 2 ≤ Hbits d) : 6 ≤ Fintype.card ι := by
  by_contra hlt
  have hcard : Fintype.card ι ≤ 5 := by omega
  have hcardpos : (0 : ℝ) < (Fintype.card ι : ℝ) := by exact_mod_cast Fintype.card_pos
  have hmono : Real.logb 2 (Fintype.card ι) ≤ Real.logb 2 5 :=
    (Real.logb_le_logb (by norm_num) hcardpos (by norm_num)).mpr (by exact_mod_cast hcard)
  have := le_trans hgate (le_trans (Hbits_le_logb_card d) hmono)
  exact absurd (lt_of_le_of_lt this logb_five_lt) (lt_irrefl _)

/-- Contrapositive, in the form a gate implementation can use: five or fewer
occupied classes ⇒ the 2.50-bit check *must* fail. -/
theorem gate_fails_of_few_branches (d : BranchDist ι) [Nonempty ι]
    (hcard : Fintype.card ι ≤ 5) : Hbits d < 5 / 2 := by
  have hcardpos : (0 : ℝ) < (Fintype.card ι : ℝ) := by exact_mod_cast Fintype.card_pos
  have hmono : Real.logb 2 (Fintype.card ι) ≤ Real.logb 2 5 :=
    (Real.logb_le_logb (by norm_num) hcardpos (by norm_num)).mpr (by exact_mod_cast hcard)
  exact lt_of_le_of_lt (le_trans (Hbits_le_logb_card d) hmono) logb_five_lt

end Ruliad.Entropy
