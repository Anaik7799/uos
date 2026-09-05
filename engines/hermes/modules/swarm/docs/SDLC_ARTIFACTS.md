# Swarm Module: Full SDLC & MBASE Fractal Architecture

This document defines the complete System Development Life Cycle (SDLC) artifacts, following the MBASE, FPP, and OML (OpenMBEE) standards for the newly isolated `modules/swarm` subsystem. 

## 1. Requirements Engineering (MBASE L0-L1)

### 1.1 Purpose
The `swarm` module provides a massively parallel, strictly OCaml-backed 5-agent execution engine capable of synthesizing Directed Acyclic Graph (DAG) execution paths from pure Declarative Intent.

### 1.2 Core Requirements
- **FR1: Fractal Ontology Mapping**: Agents, state transitions, and behaviors must map directly to the 7 fractal layers (`L0_product` to `LX_control`).
- **FR2: Declarative Intent Synthesis**: The system must expose an intent configuration API allowing operators to define goals (`Intent`) without specifying procedural steps.
- **FR3: OCaml 5 Parallelism**: SOP steps must be resolved topographically and executed in parallel across `Domain` instances.
- **FR4: Fractal Telemetry**: All state transitions must emit structured fractal telemetry for observability.
- **FR5: System Services Resilience**: Must integrate `JobManager` (Oban-like), `Temporal` (durable state), and `Homeostasis` (immune recovery).

## 2. System Design (SysML & Fractal Algebra L2-L3)

### 2.1 Fractal Algebra
The swarm operates on a mathematically provable **Fractal Algebra** framework.
- **Morphism**: `Intent -> Plan -> Execution -> Telemetry`.
- **Commutativity Law**: Parallel execution of independent DAG branches must result in identical final CRDT state merges (verified via Irmin).
- **Idempotency Law**: Replaying a `JobManager` step must yield the same output digest without duplicating side effects.

### 2.2 Component Topology
1. **`swarm_ontology.ml`**: The specific vocabulary, MIQ services, and SysML mappings for the swarm.
2. **`swarm_algebra.ml`**: Equational laws, purely functional boundaries, and state transition types.
3. **`swarm_agents.ml`**: The individual actor structures (`agent_1` through `agent_5`) and their capability catalogs.
4. **`intent_config.ml` & `swarm_api.ml`**: The declarative intent YAML parsers and OCaml combinator APIs.
5. **`swarm_fpp.ml`**: The explicit MBASE formalizations for MIQ cybernetics (`Rete_UL`, `Fast_OODA`, `Raven`, `STPA`, `FEMA`, `STAN`, `Ruliad`).
6. **`swarm_memory.ml`**: The autonomous Agentic Memory Substrate (Working, Episodic, Semantic, and Procedural models).
7. **`swarm_km.ml`**: The native Knowledge Management bridging to the Hermes Wiki and ZK system data.

## 3. Implementation (FPP L4-L5)

- Implemented entirely in OCaml, enforcing memory safety and type-level constraints.
- Utilizes `Eio` for fiber-based effect handling and concurrency inside `Domain` boundaries.
- Cross-references the `hermes_harness_formal_coverage` metrics to ensure zero test gaps.

## 4. Testing & Verification (L6)

- **Formal Gap Analysis**: Verified via `test_formal_coverage.exe`.
- **Stress & Concurrency**: Verified via `test_sop_execution_stress.ml`.
- **Property-Based Testing**: Validates the Fractal Algebraic laws (commutativity, idempotency) using `qcheck` (future extension).

## 5. Declarative Intent Config (User Surface)

The primary entrypoint for the swarm is `intent_config.ml`. 

**Command Surface:**
```bash
# Execute a swarm plan from a declarative intent file
dune exec modules/swarm/bin/swarm_cli.exe -- apply intent.yaml

# Generate the formal coverage and telemetry report
dune exec modules/swarm/bin/swarm_cli.exe -- report telemetry
```

**Example Intent Config (`intent.yaml`):**
```yaml
intent:
  target: "Full Codebase Refactor"
  constraints:
    - parallelism: "max"
    - integrity: "benchmark"
  capabilities:
    - "code_synthesis"
    - "formal_verification"
  success_criteria:
    - "0 dune test failures"
    - "100% formal gap coverage"
```
