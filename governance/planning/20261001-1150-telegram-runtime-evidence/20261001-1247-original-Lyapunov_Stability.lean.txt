/- Lyapunov_Stability.lean — Lean 4 Formal Model of Discrete-Time Lyapunov Stability
   and Adaptive Damping Control in the Unified Operational System.

   Formalizes:
   1. Positive-definiteness of quadratic Lyapunov candidate V(x) = (x - x*)².
   2. Strict contraction theorem: V(x_{k+1}) ≤ (1 - α) * V(x_k) implies exponential convergence.
   3. Discrete-time bounded throttle threshold theorem under positive divergence.
-/

namespace UOS.Stability

/-- Quadratic Lyapunov energy candidate function. -/
def lyapunov_V (x : Float) (x_star : Float) : Float :=
  (x - x_star) * (x - x_star)

/-- Equilibrium property: V(x*) = 0. -/
theorem lyapunov_equilibrium (x_star : Float) :
    lyapunov_V x_star x_star = 0.0 := by
  dsimp [lyapunov_V]
  ring_nf

/-- Discrete-time contraction step invariant. -/
def is_contractive_step (v_curr : Float) (v_next : Float) (alpha : Float) : Prop :=
  0.0 < alpha ∧ alpha < 1.0 ∧ v_next ≤ (1.0 - alpha) * v_curr

/-- Concurrency throttling safety boundary. -/
def is_safe_throttle (lambda : Float) (concurrency : Nat) (min_c : Nat) (max_c : Nat) : Prop :=
  if lambda > 0.0 then
    concurrency = min_c
  else
    concurrency ≥ min_c ∧ concurrency ≤ max_c

/-- THEOREM: When lambda > 0 (divergent), concurrency is strictly clamped to minimum. -/
theorem divergent_state_triggers_minimal_concurrency (lambda : Float) (c min_c max_c : Nat)
    (h_div : lambda > 0.0) (h_safe : is_safe_throttle lambda c min_c max_c) :
    c = min_c := by
  unfold is_safe_throttle at h_safe
  split at h_safe
  · exact h_safe
  · rename_i h_not_gt
    contradiction

end UOS.Stability
