import Std

/- Exact reference and bounded-observation contracts.
   This is an explicitly different carrier from IEEE Float, not a proof of the
   five preserved false unrestricted Float claims. Runtime correspondence must
   be checked separately at the candidate revision. No deployment authority. -/
namespace UOS.TelegramNumeric

abbrev Chart := Fin 10

def scale (i : Chart) : Rat := (i.val + 1 : Nat)

theorem scale_nonzero (i : Chart) : scale i ≠ 0 := by
  intro h
  have hn : i.val + 1 = 0 := Rat.natCast_eq_zero_iff.mp h
  omega

def transition (i j : Chart) (x : Rat) : Rat := x * (scale j / scale i)

theorem transition_identity (i : Chart) (x : Rat) :
    transition i i x = x := by
  have hi := Rat.mul_inv_cancel (scale i) (scale_nonzero i)
  simp only [transition, Rat.div_def]
  rw [hi]
  exact Rat.mul_one x

theorem transition_cocycle (i j k : Chart) (x : Rat) :
    transition j k (transition i j x) = transition i k x := by
  have hj := Rat.mul_inv_cancel (scale j) (scale_nonzero j)
  simp only [transition, Rat.div_def]
  grind

def coboundary (i j k : Chart) (x : Rat) : Rat :=
  transition j k (transition i j x) - transition i k x

theorem atlas_residual_zero (i j k : Chart) (x : Rat) :
    coboundary i j k x = 0 := by
  simp [coboundary, transition_cocycle, Rat.sub_self]

def energy (x target : Rat) : Rat := (x - target) * (x - target)

theorem energy_equilibrium (target : Rat) : energy target target = 0 := by
  simp [energy, Rat.sub_self]

def composite (x target integral gamma : Rat) : Rat :=
  energy x target + gamma * (integral * integral)

theorem composite_equilibrium (target gamma : Rat) :
    composite target target 0 gamma = 0 := by
  simp [composite, energy_equilibrium, Rat.mul_zero, Rat.add_zero]

/- The observation gate is finite and explicit: no empty chart set, at most
   ten charts, at most 1000 triple comparisons, finite nonnegative tolerance
   represented here as an exact rational, and the measured residual bound.
   It proves acceptance semantics, NOT global H^1 vanishing or stability. -/
structure Observation where
  charts : Nat
  comparisons : Nat
  maximumResidual : Rat
  tolerance : Rat
deriving Repr

def accepted (o : Observation) : Bool :=
  decide (1 ≤ o.charts ∧ o.charts ≤ 10 ∧
    o.comparisons = o.charts * o.charts * o.charts ∧
    0 ≤ o.maximumResidual ∧ 0 < o.tolerance ∧
    o.maximumResidual < o.tolerance)

theorem accepted_bounded (o : Observation) (h : accepted o = true) :
    1 ≤ o.charts ∧ o.charts ≤ 10 ∧
    o.comparisons ≤ 1000 ∧
    0 ≤ o.maximumResidual ∧ o.maximumResidual < o.tolerance := by
  simp only [accepted, decide_eq_true_eq] at h
  rcases h with ⟨hl, hu, hc, hr, _, ht⟩
  have h2 := Nat.mul_le_mul hu hu
  have h3 := Nat.mul_le_mul h2 hu
  exact ⟨hl, hu, by omega, hr, ht⟩

theorem empty_refused (o : Observation) (h : o.charts = 0) :
    accepted o = false := by simp [accepted, h]

theorem oversize_refused (o : Observation) (h : 10 < o.charts) :
    accepted o = false := by
  simp only [accepted, decide_eq_false_iff_not]
  omega

theorem positive_control :
    accepted ⟨10, 1000, 0, 1 / 10000⟩ = true := by
  simp [accepted]
  grind

theorem inconsistent_measurement_refused :
    accepted ⟨10, 999, 0, 1 / 10000⟩ = false := by decide

#print axioms transition_identity
#print axioms transition_cocycle
#print axioms atlas_residual_zero
#print axioms energy_equilibrium
#print axioms composite_equilibrium
#print axioms accepted_bounded
#print axioms empty_refused
#print axioms oversize_refused
#print axioms positive_control
#print axioms inconsistent_measurement_refused

end UOS.TelegramNumeric
