---
name: formal-verification-pipeline
description: Model and prove ZigVM Tier-1 safety bounds via Quint (distributed state) and Rocq/Lean (memory safety, linearizability), feeding the STPA to Rete-UL enforcement chain.
---

# Formal Verification Pipeline

This skill governs the integration of formal verification tools (Rocq, Lean, Quint) into the ZigVM ecosystem. It operates above the Zig compiler and the OCaml Truth Maintenance System (Rete-UL).

## 1. Scope
- **Quint (TLA+)**: Used to model distributed state interactions, Vector Clocks, CRDT convergence, and Gossip-boot algorithms over the Tailscale Zero-IP mesh.
- **Rocq (Coq) / Lean**: Used to prove the memory safety (No-Alias Arena bounds) and Wait-Free Linearizability of complex ADTs (e.g., Lock-Free ETS HAMT).

## 2. Process
1. **Identify Criticality**: If a new module touches Tier 1 boundaries (Memory Arenas, Global State, Concurrency, Networking), it must enter the formal pipeline.
2. **Model in Quint**: Draft the temporal state machine. **LIVE as of e20-t5**:
   the model is now MACHINE-EXECUTED — the `quint` stage (folded into
   `--verify-formal`, see below) runs every `specs/*.qnt` that declares `inv_*`
   invariants fail-closed, so a violated model invariant reddens the gate. Declare
   invariants as `val inv_… = { … }` and provide an instantiated `*_test` module
   (concrete `const`s) so the stage has a runnable main.
3. **Prove in Rocq**: Generate inductive types in `proofs/*.v`. Validate via `coqc`.
   Rocq carries the EXHAUSTIVE/inductive guarantee; the quint stage carries the
   complementary machine-EXECUTION of the same invariants (bounded seeded
   simulation, not exhaustive Apalache).
4. **Enforce in Rete-UL** — **LIVE as of fv-1 (2026-07-22), no longer future-tense**:
   the enforcement is now MECHANICAL, in two mutually-reinforcing places:
   - **The coqc gate stage** (`--verify-formal`, folded into the canonical
     default gate) runs `opam exec -- coqc` over every `proofs/*.v` and **fails
     closed**: any proof that does not compile, or that contains
     `Admitted`/`admit`/`Axiom`/`Abort`, turns the gate **RED**. Each proof's
     result is logged to SQLite (`formal-gate` / `formal-proof` events).
   - **The proof registry** (`proofs/REGISTRY.md`) is the total map from each
     Tier-1 module to `PROVEN | PROOF-PENDING(reason)` (REGISTRY TOTALITY: no
     blank status). The gate enforces PROVEN-IMPLIES-COMPILES.
   - **The Rete-UL Tier-1 rule** (`FV-Tier1` in `harness/rete_rules.ml`) blocks a
     Tier-1 `record_cycle` unless it cites a PROVEN registry entry or carries a
     visible, ledgered PROOF-PENDING acknowledgement (the conformance-`UNTESTED`
     discipline for proofs).
5. **Implement in Zig**: Construct the mathematically proven Data-Oriented Design (DOD).

## 3. Tooling
- `opam exec -- coqc --version` — confirm Rocq/Coq (Rocq 9.1.1 pinned). The gate
  discovers `coqc` via `opam exec` and is RED if it is absent (fail-closed).
- `quint --version` — confirm Quint (0.32.0 pinned; `npm i -g @informalsystems/quint`).
  The `--verify-formal` gate's **Quint model-check stage** (`verify_quint`, e20-t5)
  discovers `quint` via `$ZIGVM_QUINT` else PATH and is RED if it is absent
  (fail-closed, matching `coqc`). It runs `quint run --main <spec>_test --invariant
  "<conj of inv_*>" --max-steps 20 --max-samples 200 --seed 0x1` over every
  `specs/*.qnt` with declared invariants; a violated invariant / ill-typed spec
  REDs the gate. This is bounded seed-pinned **simulation**, NOT exhaustive
  Apalache (`quint verify`, JVM) — the latter's cold-start hangs and is not
  gate-viable; the exhaustive guarantee stays with the paired Rocq proof.
- `opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD" --verify-formal`
  — run the formal gate stage standalone (proofs + registry cross-checks + the
  TIER1-BLOCK / registry-parser laws). Build artifacts (`.vo`/`.glob`/…) go to a
  per-root `$TMPDIR` scratch dir — **never** committed (they are gitignored).
- Use VS Code with `vscoq` for interactive mathematical expansions.

## 4. Registry discipline (fv-1)
`proofs/REGISTRY.md` is a REQUIRED doc (the doc-gate reddens on its removal). Seed
rows at fv-1: `ets_hamt.zig → HAMT_Safety.v PROVEN`; `crdt.zig/gossip.zig →
PROOF-PENDING(fv-mesh)`; `dist.zig → PROOF-PENDING(fv-dist)`. The retrofit slices
`fv-mesh` / `fv-dist` / `fv-arena` flip PENDING rows to PROVEN — already-merged
modules are NOT retroactively RED; PROOF-PENDING is their honest, visible state.
