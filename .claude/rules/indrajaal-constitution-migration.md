# Indrajaal Constitution Migration Rule (SC-CONST-MIG-001)

## Mandate & Scope
All fundamental constitutional invariants from Indrajaal are migrated, ratified, and formally proved in UOS under Lean 4 (`formal/lean/Constitutional_Invariants.lean`) and Gleam/OTP (`apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam`).

## Core Invariants & Axioms
1. **Six Invariant Axioms ($\Psi_0 \dots \Psi_5$)**:
   - $\Psi_0$ Existence: System preserves operational integrity; crash loops fail closed.
   - $\Psi_1$ Regeneration: Self-healing actors reboot within restart budgets.
   - $\Psi_2$ History: Append-only audit logging; zero in-place ledger mutations.
   - $\Psi_3$ Verification: Two-key verification required (formal model + runtime proof).
   - $\Psi_4$ Human Alignment: HITL Guardian consent required for high-criticality actions.
   - $\Psi_5$ Truthfulness: Ground-truth observed data prioritized over model hallucinations.
2. **$\Omega_0$ Founder Precedence**: Guardian veto is absolute, unchallengeable, and irrevocable (`SC-CONST-007`).
3. **$\Omega_{0.5}$ Mutual Termination**: Immediate fail-closed abort if invariant consensus collapses.
4. **Audit Completeness (`SC-CONST-008`)**: Every state transition mints an immutable cryptographic receipt.
5. **Verified Rollback Path (`SC-CONST-009`)**: Reconfigurations require a pre-tested rollback snapshot.
6. **Real-Time Constitutional Health (`SC-CONST-010`)**: Streaming $H_C \in [0.0, 1.0]$ across Zenoh.
