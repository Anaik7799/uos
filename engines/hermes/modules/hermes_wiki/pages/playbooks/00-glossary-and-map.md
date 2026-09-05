# 00 — Glossary and map

Read this before any other playbook. Every term used elsewhere is defined here.

## Glossary

| Term | Definition |
|---|---|
| **Frozen reference** | The pinned Python snapshot under `external/hermes_source/` (snapshot digest recorded by `Inventory`). It is executed, never edited, never reimplemented. |
| **Candidate** | The OCaml implementation in `hermes_harness/` being proved equivalent to the reference. |
| **Slice** | One capability's differential corpus: adapter + capture + candidate + compare scenarios (e.g. `gemini_adapter`). |
| **Scenario** | One input case inside a slice, id `"<slice>.<case>"` (e.g. `"gemini.schema"`, `"budget.exhaust"`). |
| **Fixture (L4)** | The captured, digest-pinned output of the frozen reference for a scenario. Stored via the evidence store; re-digested on load. |
| **Trace (L5)** | A normalized fixture/candidate output pair used for comparison. |
| **Receipt (L6)** | The verifier's record that a comparison ran and what it concluded. |
| **Verdict** | `Verified < Unmapped < Blocked < Divergent` (ranks 0–3). `combine` keeps the higher rank. An empty required roll-up is `Unmapped` (the vacuous-truth guard). |
| **Fractal levels** | L0 product → L1 family → L2 capability → L3 contract → L4 fixture → L5 trace → L6 receipt, plus LX cross-cutting. |
| **Node** | A fractal name: `hermes` (L0), `hermes.<family>` (L1), `hermes.<family>.<capability>` (L2). Defined by `capability_catalog.ml`. |
| **Blueprint / directive** | Desired state: `{id; target; desired; intent; requires}` — see playbook 02. |
| **Reconcile** | Compare desired vs actual per directive → `Satisfied` or `Drift` (with a fractal diagnostic). Report-only; grants nothing. |
| **Converge** | Kleene fixpoint iteration of reconcile until the satisfied set stops growing. Monotone; a shrink is an `Anomaly`. |
| **Drift / runbook** | Residual unsatisfied intents, turned into actions by `drift_rules.ml` (Rust GRL rule engine via FFI). |
| **Fractal diagnostic** | Every finding carries: fractal level + RCA origin (Implementation / Environment / Control / Evidence) + hazard id (`HZ-*`). Only Implementation may deny credit (R5). |
| **Jidoka** | Stop-the-line: on an unexpected failure, halt and report; never patch around it. |
| **Adapter** | A small declared Python file in `hermes_harness/reference_adapter/` that runs ONE frozen function over scenario inputs and prints `{"trace":{"results":[...]}}` JSON on stdout. It makes no decisions. |
| **Gospel contract (L3)** | A `(*@ ... *)` specification in a candidate `.mli`, checked by the `gospel` binary. |

## Architecture in one paragraph

Intent is declared as typed OCaml data (`parity_intent.ml` blueprint). Actual is
measured by running the differential corpus (`parity_compare.ml`) against
digest-pinned captures of the frozen reference, rolled up per fractal node and
family (`evidence_rollup.ml`). `blueprint.ml` reconciles desired vs actual;
`converge.ml` iterates to the fixpoint; `auto_converge.ml` is the live loop and
prints the trajectory plus the residual runbook (`drift_rules.ml`). Nothing in
that loop can grant parity — only new L4–L6 evidence moves `actual` (R10).

## File map (the ones playbooks touch)

| File | Role | Playbook |
|---|---|---|
| `hermes_harness/reference_adapter/⟨slice⟩_adapter.py` | declared adapter for one frozen function | 01 |
| `hermes_harness/capture_⟨slice⟩_traces.ml` | capture executable (writes L4 fixtures) | 01 |
| `hermes_harness/⟨candidate⟩.ml/.mli` | the OCaml candidate module | 01, 04 |
| `hermes_harness/parity_compare.ml` | scenario lists, candidate projections, compare functions, `node_of`/`attribution` | 01 |
| `hermes_harness/test_parity_compare.ml` | the compare test battery | 01 |
| `hermes_harness/compare_reference_traces.ml` | the full differential run (preflighted) | 01, 02 |
| `hermes_harness/capability_catalog.ml` | the fractal node catalog | 01 |
| `hermes_harness/contract_catalog.ml` | L3 contract registry | 04 |
| `hermes_harness/parity_intent.ml` | THE blueprint + family catalog + resolver | 02 |
| `hermes_harness/auto_converge.ml` | live loop; `slice_nodes` lists covered capability nodes | 01, 02 |
| `hermes_harness/parity_dashboard.ml` | KPIs (verified counts, families) | 06 |
| `hermes_harness/formal_specs.ml` | z3-discharged laws | 05 |
| `hermes_harness/proofs/Parity_Lattice.v` | Rocq lattice proofs + pinned extraction | 05 |
| `hermes_harness/specs/parity_frontier.qnt` | Quint model of the intent DAG | 05 |
| `docs/hermes/HANDOVER.md` | session handover state | 06 |
| `docs/hermes/declarative-configuration.md` | the mechanism's reference doc | 06 |

## Command reference (all from repo root)

| Purpose | Command | Expected |
|---|---|---|
| Build everything | `dune build` | exit 0, no output |
| Any test | `dune exec hermes_harness/test_⟨x⟩.exe` | `passed: N failed: 0`, exit 0 |
| Capture a slice's fixtures | `dune exec hermes_harness/capture_⟨slice⟩_traces.exe` | per-scenario `captured` lines, exit 0 |
| Full differential compare | `dune exec hermes_harness/compare_reference_traces.exe` | per-scenario `VERIFIED`/`DIVERGENT`, summary, exit 0 |
| The closed loop | `dune exec hermes_harness/auto_converge.exe` | trajectory + `settled`/`converged` + runbook |
| Dashboard | `dune exec hermes_harness/hermes_harness_report.exe` (see dune for exact name) | KPI table |

## Environment variables (only set when a playbook says so)

| Var | Meaning |
|---|---|
| `HERMES_REFERENCE_PYTHON` | interpreter used to run declared adapters (defaults to the provisioned reference env) |
| `HERMES_GOSPEL` | path/command for the `gospel` binary |
| `HERMES_COQC` | Rocq compiler command — the validated form is `opam exec --switch=rocq-iris -- coqc` |
| `HERMES_Z3` | path to the z3 binary |
| `HERMES_DISABLE_LAZY_INSTALLS` | set to `1` inside adapters whose frozen imports would otherwise try to network-install (bedrock — L-10 discipline) |

## Session learnings you must not re-learn the hard way

| Id | One-line rule |
|---|---|
| L-01 | Adapter sets `PYTHONPATH` so the frozen tree wins over site-packages. |
| L-04 | Compare each scenario against the RIGHT reference profile; a profile mismatch is exclusion-with-reason, not a divergence. |
| L-07/L-08 | Writes are preflighted; a full tmpfs must refuse up front, not crash mid-write. |
| L-09 | Never auto-yes an opam plan you cannot fully see. Never modify a shared switch "additively". |
| L-10 | `logging.disable(logging.CRITICAL)` BEFORE importing frozen modules in an adapter — a frozen logger writing to stdout corrupts capture JSON. |
