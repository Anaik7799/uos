---
migrated_from: docs/zk/20260807-hermes-fractal-compliance.md (zigvm-era tree, authored for Hermes)
---
# Architectural Decision: Strict Compliance with Fractal Atlas Topology

**Date:** August 7, 2026
**Topic:** Hermes OCaml System Evolution & Structural Integrity

## Decision
All future code evolution, feature additions, and system integrations for the Hermes Agent port must be strictly compliant with the existing Fractal Atlas (`agent/hermes_atlas.ml` and the topology defined in `docs/wiki/hermes-ocaml-topology.md`).

## Rationale
- **Algebraic Homeostasis:** The Hermes project relies on a rigorously defined ontology (Agents, MemoryNodes, GatewayNodes, Skills). Introducing ad-hoc components that do not map to these established nodes and edges (e.g., `Spawns`, `Remembers`, `ExecutesOn`) breaks the topological mapping.
- **Verification Gate Consistency:** The SDLC and Rete-UL verification gates monitor system health based on this predefined fractal structure. Deviations will trigger L0-L9 safety boundaries in the Autonomous Execution Engine (AEE).
- **Preventing Architectural Drift:** By forcing all new capabilities to express themselves through the existing structural language (e.g., as a new `SkillNode` or a new `ExecutionBackend`), we guarantee that the codebase remains mathematically trackable and logically consistent over its entire lifecycle.