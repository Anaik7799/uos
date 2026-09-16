# SC-RISK-CAT-001: Criticality, Utility, STPA Safety, FMEA Risk Product, and Categorical Evolution Mandate

- **Rule Identifier**: `SC-RISK-CAT-001`
- **Sub-Rules**: `SC-CRIT-UTIL-001` (Criticality & Utility Functors), `SC-STPA-UCA-001` (STPA Safety Lattices), `SC-FMEA-RPN-001` (FMEA Risk Monad), `SC-CO-EVOL-001` (Categorical Co-Evolution)
- **Specification**: `docs/design/20260916-1000-uos-criticality-utility-stpa-fmea-category-theoretic-evolution-spec.md`
- **Decision Record**: `docs/zk/20260916-1000-adr-130-criticality-utility-stpa-fmea-category-theoretic-evolution.md`
- **Tailscale Link**: [http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260916-1000-criticality-utility-stpa-fmea-category-theoretic-evolution-mandate.md](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260916-1000-criticality-utility-stpa-fmea-category-theoretic-evolution-mandate.md)
- **Lean 4 Proofs**: [`formal/lean/Criticality_Utility_STPA_FMEA_Evolution.lean`](file:///home/an/NAS-setup/uos/formal/lean/Criticality_Utility_STPA_FMEA_Evolution.lean)
- **Authority**: Codex Astra (`codex-astra`) & Claude Fable (`L0-fable`) Tri-Sovereign Consensus

#fractal-l0 #fractal-l1 #fractal-l5 #zero-muda #stamp-stpa #criticality #utility #fmea #evolution #dual-sovereign

---

## 1. Principle & Scope

To guarantee mathematical safety, optimal resource allocation, and controlled architectural evolution across all ten fractal layers ($L_0 \dots L_9$) and seven defense holons ($H_0 \dots H_6$), all architectural subsystems, multi-agent swarms, safety controllers, and SDLC/SRE tools MUST comply with the following categorical mandates:

1. **Categorical Criticality & Utility Functors (`SC-CRIT-UTIL-001`)**:
   - Task prioritization MUST be formulated as a bifunctor $\mathcal{K} \times \mathcal{U} \to \mathbf{Chow}$ where decision scores satisfy $\kappa \cdot u \le 10000$.
   - Worker allocation pull queues MUST be monotonic with respect to decision scores, eliminating priority inversion.
2. **STPA Safety Lattices & Exhaustive UCA Fencing (`SC-STPA-UCA-001`)**:
   - All control actions across BEAM actors and native controllers MUST be classified under the 4-fold STPA UCA partition ($UCA_1 \dots UCA_4$).
   - Hazard detection MUST trigger fail-closed safety interlocks that guarantee complete hazard containment.
3. **FMEA Risk Priority Monad & Mitigation Contraction (`SC-FMEA-RPN-001`)**:
   - Component failure modes MUST be evaluated via the graded risk monad $\mathcal{M}_{\text{RPN}}(S, O, D) = S \times O \times D \le 1000$.
   - Architectural mitigations and patch updates MUST strictly satisfy $\text{RPN}' \le \text{RPN}$, precluding regressions.
4. **Categorical Co-Evolution & Specification Distance Contraction (`SC-CO-EVOL-001`)**:
   - Evolutionary mutations across SDLC, SRE, and agent swarms MUST be modeled via the comonad $W_{\text{evol}}$ over slice categories $\mathbf{UOS} / \text{Spec}$.
   - Every evolutionary generation MUST monotonically decrease or preserve distance to canonical formal specifications.
5. **POODAVR Risk-Integrated Lyapunov Stability**:
   - The 7-stage POODAVR loop MUST integrate STPA and FMEA risk metrics, maintaining negative Lyapunov drift: $\dot{V} \le -k V$.

---

## 2. Invariant Rules

### Invariant 1: Criticality-Utility Decision Boundedness (`INV-RISK-01`)
Task profiles satisfy:
$$\text{decision\_score}(p) = p.\kappa \cdot p.u \le 10000$$
Machine-checked by Lean 4 theorem `criticality_utility_bounded_product`.

### Invariant 2: Four-Fold STPA UCA Completeness (`INV-RISK-02`)
Every potential unsafe control action satisfies:
$$\text{uca} \in \{UCA_1, UCA_2, UCA_3, UCA_4\}$$
Machine-checked by Lean 4 theorem `stpa_uca_fourfold_completeness`.

### Invariant 3: Monadic RPN Mitigation Contraction (`INV-RISK-03`)
Mitigation actions strictly reduce or preserve RPN:
$$\text{rpn}(\text{mitigate}(f)) \le \text{rpn}(f)$$
Machine-checked by Lean 4 theorem `fmea_rpn_monadic_contraction`.

### Invariant 4: Evolutionary Specification Contraction (`INV-RISK-04`)
Evolutionary mutations satisfy:
$$\text{spec\_distance}(\text{evolve\_step}(s)) \le \text{spec\_distance}(s)$$
Machine-checked by Lean 4 theorem `evolutionary_fitness_monotonic_growth`.

### Invariant 5: Storage Hardware Hard Denial (`INV-RISK-05`)
The host root OS NVMe drive (`25503L801736`) is unconditionally identified as denied and fails closed against any allocation or modification. Machine-checked by Lean 4 theorem `stamp_hazard_storage_hard_denial`.

---

## 3. Enforcement & Verification

- **Enforcement Gate**: `tools/uos gate G-RISK-CAT` (`tools/uos risk-cat-check`).
- **Lean 4 Proofs**: 10 formal theorems in `formal/lean/Criticality_Utility_STPA_FMEA_Evolution.lean` (123 cumulative theorems in UOS).
- **Checklist Integration**: Enforced under Domain 2 & Domain 4 of `SC-CHECKLIST-001`.
