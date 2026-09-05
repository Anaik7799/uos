# Hermes Implementation Approach
**Timestamp**: 2026-08-10T10:27:00+02:00
**Location**: `modules/swarm/docs/migration/IMPLEMENTATION_APPROACH.md`

## 1. Pure OCaml 5 Mandate
All agentic reasoning, memory management, FPP routing, and CLI interaction is implemented strictly in OCaml 5 (`swarm_algebra.ml`, `swarm_agents.ml`, `swarm_cli.ml`). 
- **NO Python/JS/Go Bridges**: AI logic executes natively in OCaml.
- **Multicore Eio**: The Conductor agent utilizes OCaml 5 Domain parallelism to spin up the $N$ Elastic Fabric executor threads.

## 2. Declarative Intent Over Imperative Scripts
Agents are not summoned via scripts (e.g. `python run_agent.py --task xyz`).
Implementation is achieved by constructing a **SysML Declarative Intent DAG** (`intent_config.ml`). 
The `Synthesizer` reads the intent, determines the topological width, and the `Conductor` dynamically spawns the necessary $N$ fibers.

## 3. Autonomous MIQ Service Injection
The implementation utilizes an `auto_allocate_miq` loop. The Swarm engine automatically wraps tasks in necessary cognitive algorithms based on the Fractal Layer:
- If a task touches $L_X$ (Control), it is auto-wrapped in `STPA` (System-Theoretic Process Analysis) and `Fast_OODA`.
- If a task touches $L_2$ (Component), it passes through `STAN` (Statistical auditing) and `Rete_UL` (Rules Engine).

## 4. Cyber-Physical Zenoh Integration
Implementation of the CRDT state is physically routed through Eclipse Zenoh (`swarm_zenoh.ml`). 
- The `Topologist` publishes state vectors asynchronously.
- The `Sensorium` ingests 20kHz physical hardware data from external robotics.
This decouples cognitive reasoning from high-throughput physical I/O drag.

## 5. Formal Verification CI/CD
Implementation is gated by the Omni-Prover suite. Before any topological mutation is permitted into `master`, it must mathematically pass:
1. Deadlock acyclic proofs (Rocq)
2. Eio fiber separation logic (Iris)
3. Nanosecond deadline enforcement (Lean 4)
4. CRDT mesh consistency (Quint)
