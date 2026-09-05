# Hermes OCaml Topology

This document describes the structural mapping of the Hermes OCaml port to the original Python architecture.

## Directory Map

*   `agent/`: The Core Brain.
    *   `hermes_ontology.ml`: Fundamental models (Agent, Skill, Memory).
    *   `hermes_algebra.ml`: Pure state transitions.
    *   `hermes_feature_set.ml`: Capability routing.
    *   `hermes_atlas.ml`: Graph topology.
    *   `hermes_rete.ml` & `hermes_rules.ml`: The autonomous rule engine.
    *   `hermes_agent.ml`: Main orchestrator.
*   `skills/`: Reusable agent capabilities.
    *   `hermes_skills.ml`: Built-in skills (Browser, MLOps Data Gen).
*   `tools/`: Isolated execution functions (Docker, IO).
*   `providers/`: LLM integrations (OpenRouter).
*   `gateway/`: Messaging protocol bridges (Discord, Telegram).
*   `tui_gateway/`: Terminal UI integration.
    *   `hermes_ratatui_ffi.ml`: Linkage to `external/hermes_tui_rs`.
*   `hermes_cli/`: Application entrypoints.
*   `hermes_harness/`: The parity control plane. Distinct from `agent/`: it does
    not run Hermes, it decides what has been *proven* about the OCaml port
    against the frozen Python reference.
    *   `inventory.ml`: Deterministic frozen-source snapshot and digest.
    *   `evidence_store.ml`: Append-only SQLite evidence; every immutable table
        rejects a same-key/different-payload replay.
    *   `feature_catalog.ml`, `capability_catalog.ml`: L1 families and the 95
        source-anchored L2 capability slices, with their dependency graph.
    *   `fractal_catalog.ml`: Emits the L0-L2 `fractal_node` tree.
    *   `reference_artifacts.ml`: Digest-pinned frozen source and doc artifacts
        attached to every L2 node.
    *   `contract_catalog.ml`, `gospel_check.ml`, `gospel_stubs/`: The L3 layer.
        Contracts are Gospel-specified `.mli` interfaces; only a `checked`
        verdict counts.
    *   `hermes_plan.ml` + `hermes_plan_bridge.ml`: Sa-plan projection, run out
        of process because Sa-plan collides with the harness-local `Core`.
*   `external/`: Third-party dependencies and original sources.
    *   `hermes_source/`: The original Python codebase for reference and behavioral parity.
    *   `hermes_tui_rs/`: Rust library for Ratatui TUI.

## Proof Topology

`agent/` and `hermes_harness/` are two different fractals and must not be
conflated. The agent ontology is fractal over *runtime* structure — an agent
contains sub-agents of the same type. The harness fractal is over *evidence*:
L0 product, L1 family, L2 capability, L3 contract, L4 fixture, L5 normalized
trace, L6 verifier receipt. A node in one has no meaning in the other, and
adding capability slices or contracts to the agent ontology would be exactly
the architectural drift `docs/zk/20260807-hermes-fractal-compliance.md` warns
against.

Only L4-L6 grants parity credit. Catalogs, artifacts, Sa-plan tasks and checked
contracts are discovery or obligation facts.

## Control Flow & Rete Homeostasis
The system enforces behavioral bounds using the `hermes_rete.ml` Rete-UL engine. This ensures that memory states (e.g., solved complex tasks) autonomously trigger required state transitions (e.g., automated skill acquisition) without relying on ad-hoc loop control logic.