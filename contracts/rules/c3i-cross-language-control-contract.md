# C3I Cross-Language Control Contract

- **Authority:** `UOS-CANONICAL-AGENT-POLICY` (§5.1)
- **Domain:** Distributed Cross-Language Control Plane & Fractal Observability
- **Status:** ACTIVE & ENFORCED

---

## 1. Domain Separation Invariant

Every C3I control and operational role is mapped to an explicit single-language authority:

| Architectural Role | Language Authority | Subsystem Path | Primary Responsibilities |
| :--- | :--- | :--- | :--- |
| **Supervision & Intent** | Gleam / OTP | `apps/cepaf_gleam`, `apps/indrajaal_gleam` | Root supervisor tree (`uos_sup.gleam`), Holon actor swarms, Prajna circuit breakers, Lyapunov hysteresis, 2oo3 guardian consensus |
| **Evidence & Differential Oracle** | Hermes / OCaml | `engines/hermes` | Authoritative SQLite WAL ledgers, Gospel contracts, Z3 worker protocol, Rete-UL rule engine, Zero-Trust dispatch interceptor |
| **Deterministic Runtime** | ZigVM / Zig | `engines/zigvm` | Bytecode VM, linear arenas, descriptor-relative VFS backend, lockless ring buffers |
| **Bounded Kernels & Safety** | Rust / C-ABI | `native/`, `ops/kubernetes/nas-k8s-lab` | Short bounded NIF shims, hardware serial denial interlock (`25503L801736`) |
| **Isolated AI Inference** | Modular MAX / Mojo | `services/inference/max` | Confined Python daemon (`max_worker.py`) via length-delimited JSON-RPC |
| **Mathematical Authority** | Lean 4 & Quint | `formal/lean/`, `formal/quint/` | Machine-checked proofs (`Traceability.lean`, `TwoLattice_STM.lean`) and Quint simulation (`parity_frontier.qnt`) |

---

## 2. Invariants & Communication Protocols

1. **No Cross-Language State Leakage**:
   - Gleam actors do not share mutable memory with ZigVM or Rust. All communication occurs over typed message passing, BEAM ports, or bounded NIF dispatch facades.
2. **Fail-Closed Zero-Trust Interception**:
   - All tool dispatches across languages pass through `run_agent_dispatch_hook.exe` before execution, verifying payload bounds and SHA-256 cryptographic digests.
3. **Universal C3I Structured Telemetry**:
   - All components, regardless of source language, MUST emit JSON lines formatted per `contracts/evidence/c3i_fractal_observability_spec.json`, containing 128-bit W3C OTel `trace_id`, microsecond timestamps, and fractal layer identifiers ($L_0 \dots L_9$).
4. **Permanent Zero-Muda Standard**:
   - Zero Bevy, zero Graphite across all languages, configurations, builds, and dependencies.
