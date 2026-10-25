-- Executed floating-point counterexamples; not kernel proofs of Float axioms.
#eval ("atlas_identity_overflow", (((1.0 : Float) * ((Float.ofNat (2^2048) + 1.0) / (Float.ofNat (2^2048) + 1.0))).toBits), ((1.0 : Float) * 1.0).toBits)
#eval ("atlas_cocycle_rounding", (((0.1 : Float) * 3.0) * (1.0 / 3.0)).toBits, ((0.1 : Float) * 1.0).toBits)
#eval ("atlas_residual_rounding", (((0.1 : Float) * 3.0) * (1.0 / 3.0) - 0.1))
#eval ("atlas_residual_infinity", (((1.0 : Float)/0.0) - ((1.0 : Float)/0.0)))
#eval ("lyapunov_infinity", let x : Float := 1.0/0.0; ((x-x)*(x-x)).toBits, (0.0 : Float).toBits)
#eval ("century_infinite_gamma_zero_error", let g : Float := 1.0/0.0; ((0.0 : Float)*0.0+g*(0.0*0.0)).toBits, (0.0 : Float).toBits)
