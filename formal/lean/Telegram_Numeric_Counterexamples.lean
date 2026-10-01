import Denotational_Atlas_Cohomology
import Lyapunov_Stability
import Century_Harmony
set_option maxRecDepth 10000
set_option maxHeartbeats 1000000
namespace UOS.TelegramNumericCounterexamples

theorem finite_cocycle_false : ¬ UOS.Cohomology.transition_cocycle_unproved_claim := by
  intro h
  have claimed := h 0 2 4 (0.1 : Float)
  have different : UOS.Cohomology.transitionMorphism 2 4
      (UOS.Cohomology.transitionMorphism 0 2 (0.1 : Float)) ≠
      UOS.Cohomology.transitionMorphism 0 4 (0.1 : Float) := by decide +kernel
  exact different claimed

#print axioms finite_cocycle_false

theorem unrestricted_identity_false : ¬ UOS.Cohomology.transition_identity_unproved_claim := by
  intro h
  have claimed := h (2 ^ 2048) (1.0 : Float)
  have different : UOS.Cohomology.transitionMorphism (2 ^ 2048) (2 ^ 2048) (1.0 : Float) ≠
      (1.0 : Float) * 1.0 := by decide +kernel
  exact different claimed

theorem finite_residual_not_zero : ¬ UOS.Cohomology.h1_cohomology_vanishing_unproved_claim := by
  intro h
  have claimed := h 0 2 4 (0.1 : Float)
  have different : UOS.Cohomology.cechCoboundary 0 2 4 (0.1 : Float) ≠ 0.0 := by decide +kernel
  exact different claimed

theorem unrestricted_energy_false : ¬ UOS.Stability.lyapunov_equilibrium_unproved_claim := by
  intro h
  have claimed := h ((1.0 : Float) / 0.0)
  have different : UOS.Stability.lyapunov_V ((1.0 : Float) / 0.0) ((1.0 : Float) / 0.0) ≠ 0.0 := by decide +kernel
  exact different claimed

theorem unrestricted_composite_false : ¬ UOS.CenturyHarmony.composite_energy_equilibrium_unproved_claim := by
  intro h
  let s : UOS.CenturyHarmony.SwarmNodeState := ⟨0, 0.0, 0.0, 0.0⟩
  have claimed := h s ((1.0 : Float) / 0.0) rfl rfl
  have different : UOS.CenturyHarmony.composite_energy s ((1.0 : Float) / 0.0) ≠ 0.0 := by decide +kernel
  exact different claimed

#print axioms unrestricted_identity_false
#print axioms finite_residual_not_zero
#print axioms unrestricted_energy_false
#print axioms unrestricted_composite_false

end UOS.TelegramNumericCounterexamples
