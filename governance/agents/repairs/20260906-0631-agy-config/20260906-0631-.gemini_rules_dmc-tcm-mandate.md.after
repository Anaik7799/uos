---
trigger: always_on
---

# DMC & TCM Behavioral Rule Mandate

- **Authority:** `UOS-CANONICAL-AGENT-POLICY`
- **Domain:** Denotational Meta-Calculus (DMC) & Type Class Morphisms (TCM)
- **Status:** ACTIVE & ENFORCED

---

## 1. Core Invariants Enforced by Mandate

1. **No Hallucinated Syntax**:
   - Autonomous agents cannot invent types, fields, endpoints, or foreign function interfaces.
   - Every emitted type or call must map directly to an extracted cell in the OCaml Central Registry (`engines/hermes`), typed Gleam record (`apps/cepaf_gleam`), or Zig packed struct (`engines/zigvm`).

2. **Deterministic Verification Prior to Admission**:
   - Every state transition or code change must satisfy two-key verification:
     $$\text{Trust} = \text{Fresh Empirical Behavior} \land \text{Formal Specification}$$
   - Any unverified, unrun, mock, or planned state yields strictly 0 operational credit (`indicatorTrust == 0`).

3. **Fail-Closed Zero-Trust Interception**:
   - All MCP tool dispatches are trapped by `run_agent_dispatch_hook.exe` before execution.
   - Any payload containing embedded NUL bytes (`memchr` code `-2`) or unparameterized raw SQL syntax (`code -3`) is terminated fail-closed with immediate process halt.

4. **Two-Lattice Memory Non-Interference**:
   - Telemetry and monitoring observations live in an isolated read ring buffer and cannot mutate authoritative SQLite WAL evidence ledgers.
   - Writer transactions require single-writer exclusive leases with monotonically increasing epochs (`TwoLattice_STM.lean`).

5. **Spatiotemporal Coeffects & Clock Drift Thresholds**:
   - Host monotonic time governs all event sequences (`cordis_spatiotemporal_spec.json`).
   - Clock drift $< 2.0\text{s}$ is nominal; $2.0\text{s} - 5.0\text{s}$ issues a system warning; drift $> 10.0\text{s}$ immediately halts transaction admission.
