---
name: harness-supervisor
description: Run the multilayer agentic OODA loop (L0 program / L1 subsystem / L2 slice / L3 verifier) over the harness's SQLite memory to pick, dispatch, and accept law-carrying slices cost-effectively. Use when orchestrating zigvm program work across agents, when deciding the next slice, when assigning model tiers to work, or when recording a cycle outcome.
---

# Harness Supervisor — the Tier-2 OODA loop

**ZERO-CONTEXT BOOTSTRAP:** to resume the autonomous program in a fresh
session, follow `docs/AUTONOMOUS_RUNBOOK.md` — it contains the standing
mandate, the live-position queries, the loop, the L2 brief template, the L3
verification recipe, and the gotcha ledger. The kanban
(`slice_backlog`/`cycle_outcome`/`oodalog` in `harness/state/zigvm_harness.sqlite3`)
is the single source of truth for position — never prose snapshots.

Tier 1 is the OCaml harness (the deterministic judge). Tier 2 — this skill —
is the agentic control loop above it. Tier 2 NEVER contains harness logic;
it reads and writes the harness's SQLite memory through the documented CLI.
Database access must go through the harness or authored OCaml code. Never use
a direct database client, Python binding, shell SQL, or non-OCaml adapter.
All program plans, task transitions, leases and completions are likewise
owned by the OCaml `Sa_plan.Store`; prose TODOs and agent reports are
read-only projections.

## The loop (every layer, every cycle)

1. **Observe** — MCP-first: call the `observe` tool of the `zigvm-harness`
   MCP server (`.mcp.json`) if available; else run:
   `opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD" --ooda-observe`
   Likewise `facts`/`next_slice`/`record_cycle`/`run_gate`/`run_selfcheck`
   are MCP tools first, CLI second.
   The JSON is self-contained: dirty frontier, latest run, observed unit
   costs, the slice backlog, recent cycle outcomes, and the `next_slice`
   pull signal. Do NOT re-derive this from tree reads (token muda).
2. **Orient** — criticality × safety-priority × dep-readiness. An open
   SIF-class UCA on a slice's path blocks acceptance (check
   `--safety-status`). The ledgers are the work queue; `DIVERGENCE_LOG.md`
   bounds what a slice may claim.
3. **Decide** — take `next_slice` (or justify a deviation in the oodalog).
   Set the model tier and token budget per the tiering table below.
4. **Act** — dispatch per the layer map; on completion run the canonical
   gate, then close the loop with the DURABLE Zero-Trust CLI:
   `opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD" --record-cycle <slice> ok "<notes>"`
   (MCP `record_cycle` is the same decision; NEVER a hand SQL insert — the
   rete gate must mediate). The green stamp is keyed to the EXACT commit:
   commit first, re-run the gate on that commit, then record. A red gate
   gets a `CAST_LOG.md` entry before any re-run.

## Layers

- **L0 program supervisor** (this session's top loop): owns the backlog,
  budgets, and acceptance. Never implements.
- **L1 subsystem supervisors**: one per truly-independent workstream only
  (`superpowers:dispatching-parallel-agents`).
- **L2 slice workers**: one law-carrying algebraic slice each
  (`skills/algebraic-fractal-structures/SKILL.md` is binding), in git
  worktrees when mutating in parallel (`superpowers:using-git-worktrees`).
- **L3 adversarial verifiers**: refute each landed slice (laws re-run,
  mutant replay, review). A null/dead-agent verdict is a FAILURE — require
  explicit confirmation (fail-closed).

## Model tiering (cost-effective execution)

The harness's laws — not the model — are the quality gate, so work routes to
the cheapest tier that can satisfy the gate:

| Work class | Tier | Why |
|---|---|---|
| Epoch/slice design, semantic domains, law discovery, safety packets, divergence triage | Fable/Opus (high effort) | judgment-heavy; errors here are expensive downstream |
| Slice implementation against a written plan with stated laws | Opus (or Sonnet for narrow, well-specified slices) | the laws + gate verify the output mechanically |
| Mechanical steps: doc syncs, mutant replays, ledger regeneration, checkbox ticks, corpus additions from a given template | Sonnet/Haiku, low effort | fully checkable by the doc-gate/skill-validator/selfchecks; cheap failure, cheap retry |
| L3 verification (refute a claim, re-run laws) | mid tier, diverse lenses | independence matters more than raw capability |

Budget rule: spend tokens where the ledger flips are (the Pareto slice is always
the highest-criticality dep-ready `next_slice` row — self-updating, never a
hard-coded epoch); mechanical tails go to cheap tiers; every tier's output must
pass the SAME gate — trust the gate, not the model.

## Hard rules

- The canonical gate is the only completion evidence:
  `opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD"`
  *(Note: `record_cycle` is fail-closed-gated by the Rete-UL Zero-Trust rule
  matcher. If blocked, read the REJECT message, then check facts through
  `--verify-cycle SLICE NOTES` with the exact `record_cycle` context,
  harness/MCP operations, and `--check-guards`. `/bonsai` is a
  real read-only Bonsai frontend over Dream HTTP, but there is no live Zenoh UI
  pipe and the dashboard cannot mint or mutate gate evidence.)*
- `--sequential` is the preserved oracle path; `--selfcheck-parallel` (Φ)
  guards the DAG gate. Never weaken either.
- Every slice: laws first → implement → ≥2 mutants killed → safety packet →
  doc sync → green gate → commit → push (shared tree; commit promptly).
- Selfcheck battery for harness-engine changes: `--selfcheck-db`,
  `--selfcheck-graph`, `--selfcheck-cache`, `--selfcheck-sched`,
  `--selfcheck-shard`, `--selfcheck-parallel`, `--selfcheck-ooda`.
- Any helper tooling the supervisor spawns or generates is OCaml-only
  (`scripts/` fleet, `docs/OCAML_SCRIPTING_SOP.md`) — never ad-hoc shell.

## Fractal FP atlas synchronization

During Observe, project the exact-commit changed paths once. If the typed atlas
classifier has a non-empty image, add the bounded repair/regeneration work to
the active Sa-plan task, require `--selfcheck-fractal-fp-atlas` and
`--wiki-audit`, and include `phase:atlas_sync` at completion. Do not burden an
empty-image ZigVM slice, and never accept the phase token in place of the
exact-head Green Stamp.
