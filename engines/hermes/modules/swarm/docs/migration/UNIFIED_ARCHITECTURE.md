# Hermes Unified Architecture
**Timestamp**: 2026-08-10T10:27:00+02:00
**Location**: `modules/swarm/docs/migration/UNIFIED_ARCHITECTURE.md`

## 1. Structural Paradigm: SysML, OML, & OpenMBEE
The overarching Hermes architecture abandons arbitrary agent design in favor of strict Model-Based Systems Engineering (MBSE).
- **SysML**: System components, data flows, and state machines are modeled mathematically.
- **OML (Ontological Modeling Language)**: Governs the vocabulary.
- **OpenMBEE**: The collaborative MBSE platform semantics are mapped natively into OCaml types (`swarm_ontology.ml`).

## 2. The Theoretical Core
### Fractal Ontology & Atlas
The world is mapped into 7 strict operational layers ($L_0$ to $L_6$ and an orthogonal control layer $L_X$):
- $L_0$: Target/Product
- $L_1$: Domain Subsystems
- $L_2$: Interacting Components
- $L_3$: Cybernetic Assemblies
- $L_4$: Specific Parts
- $L_5$: Physical/Data Material
- $L_X$: Universal Governance

### Fractal Algebra
Agent interactions are strictly algebraic. DAG synthesis is a monoidal composition where state merging is Associative, Commutative, and Idempotent (ACI), enforcing deterministic output regardless of async processing order.

### FPP (Fractal Product Process)
The execution ports (`swarm_fpp.ml`). Everything flows through `Sync_input`, `Async_input`, or `Output`. FPP maps the conceptual SysML nodes directly into executable OCaml port contracts.

## 3. The 15+N+M CPS Swarm Topology
The realization of the MBSE design.
- **15 Static Core Agents**: Divided into Cognitive (`Synthesizer`, `Neural Weaver`), Verification (`Bayesian Critic`, `Byzantine Sentinel`), Physics (`Kinematic Weaver`, `Fluidic Controller`), and Data routing (`Topologist`, `Sensorium`).
- **N Elastic Executors**: The $N$ physical/computational Eio fibers spun up by the `Conductor`.
- **M Fractal Satellites**: Isolated domain experts called upon dynamically.

## 4. Formal Technology Stack
- **Mesh Data**: **Zenoh** (Edge-optimized Pub/Sub for CRDTs and physical telemetry).
- **Provers**: **Quint** (TLA+ State bounds), **Iris** (Concurrency Separation), **Rocq** (Deadlock theorems), **Lean 4** (RTOS timing limits).
- **Memory**: **Zettelkasten (ZK)** for Semantic Graph, distributed **CRDTs** for Working Memory.
