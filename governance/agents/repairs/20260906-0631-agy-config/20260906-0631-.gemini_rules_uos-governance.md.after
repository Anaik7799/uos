---
trigger: always_on
---

# UOS Monorepo Governance Rule

## Mandates
1. Target VCS: standalone, non-colocated Jujutsu only (`.jj/`). Native Git mutation commands are strictly barred.
2. Strict Zero-Muda: Zero Bevy, zero Graphite across dependencies, crates, runtime, APIs, and history.
3. Architecture Boundaries:
   - Supervision, policy, intent, APIs: Gleam/OTP (`apps/cepaf_gleam`, `apps/indrajaal_gleam`)
   - Deterministic Runtime: ZigVM (`engines/zigvm`)
   - Formal Evidence & Oracles: Hermes (`engines/hermes`)
   - Isolated Inference: Modular MAX/Mojo (`services/inference/max` - Python confined exclusively here)
4. Explicit Sequencing Constraint:
   - Physical Storage and Kubernetes activation are strictly deferred until Harness and Hermes/ZigVM engines are fully complete and operational.
5. Evidence States:
   discovered -> classified -> mapped -> implemented -> built -> executed -> passed -> verified -> admitted
6. 13-Section Journal entry required after each completed task.
