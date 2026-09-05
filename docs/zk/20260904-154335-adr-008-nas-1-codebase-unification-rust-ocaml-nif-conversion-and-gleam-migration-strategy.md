---
id: 61a07c34-67f8-7d3f-b893-2b83c97eb86b
status: draft
last_verified: 2026-09-04
verified_by: agent
---
# ADR-008: NAS-1 Codebase Unification, Rust/OCaml NIF Conversion, and Gleam Migration Strategy

_Decision record (ADR) — captured in the Zettelkasten as part of the SDLC/SRE loop._

## Context (as-is)

To achieve Zero Muda and eliminate operational fragmentation across nas-1, disparate shell scripts, Python daemons, and standalone binaries are unified under the CEPAF Gleam OTP supervision hierarchy on Erlang OTP 27, converting compute-heavy Rust and OCaml logic into Erlang NIFs and migrating coordination, routing, and state machine logic to pure Gleam.

## Decision (to-be)

Unify all nas-1 operational code under the Gleam/BEAM supervisor root; migrate OODA coordination, task state machines, HTTP/WS routing, and SLO monitoring to pure Gleam; convert/preserve TPM crypto, hardware storage inspection, formal verification, Bayesian inference, and SMT sandboxing as hardened Erlang NIFs bound to dirty CPU schedulers.

## Agent reasoning

Gleam on BEAM provides unparalleled fault tolerance, actor isolation, and type safety for orchestration, while Erlang NIFs execute within the VM process space with zero IPC serialization latency. Quarantining heavy compute behind ERL_NIF_DIRTY_JOB_CPU_BOUND schedulers prevents scheduler starvation and preserves sub-millisecond API responsiveness.

## Criteria · Architecture

Gleam Master Root Supervisor (cepaf_gleam_sup) orchestrating Wisp HTTP/WS Router, OODA Loop Actor, Telemetry/SLO Monitor, Rust NIF Enclave (rusty_vault, nas_setup, rule_engine, graphene), and OCaml NIF Enclave (c3i_ocaml, stan_ad, z3_sandbox, ruliad).

## Criteria · Test

9,767 Gleam tests passing, C-ABI embedded NUL rejection, fail-closed buffer overflow handling, OCaml exception interception, and pure SQLite WAL header parsing.

## Criteria · Docs

Documented in 2026-09-04-unified-operational-system-design-plan.md (Section 28), 2026-09-04-claude-codex-review-dossier.md (Section 14), and 2026-09-04-source-backed-operational-catalogue.md (Section 6).

## Tradeoffs

NIF crashes can potentially crash the entire BEAM VM if not rigorously guarded; mitigated via strict catch_unwind in Rust, exception trapping in OCaml, and process group sandboxing for SMT solvers.

## Alternatives — what else could be done

External daemon IPC over Unix domain sockets was rejected due to serialization overhead, lack of unified supervisor tree recovery, and operational drift.

#decision #adr