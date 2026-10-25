---
name: stpa-safety-protocol
description: Apply STPA, UCA identification and prioritisation (PMS/CIF/SIF + EJ + P-Matrix), CAST incident analysis, and FMEA to zigvm program work at every fractal layer. Use when adding or changing controllers or evidence paths (harness modes, engines, schedulers, SQLite writers, baselines), when a gate or conformance run goes red, when opening or closing an epoch, when filling a slice safety packet, or when updating SAFETY_ANALYSIS.md or CAST_LOG.md.
---

# STPA Safety Protocol

Program-as-control-system safety. Sources pinned in `SAFETY_ANALYSIS.md`
(STPA Handbook, CAST Handbook, *Engineering a Safer World*,
arXiv:2508.10446). Fractal obligations: `ALGEBRAIC_FRACTAL_RULES.md` §10.

For Sa-plan-governed work, the OCaml Store is the sole control-plane entry and
exit: STPA/FMEA packets attach to durable task/events and cannot be accepted
from MCP, UI, agent prose or a Rete/ruliological note alone.

## When a slice touches a controller or evidence path

1. Fill the safety packet (§10): control actions touched → four UCA types
   considered → SC-* honored → FMEA delta → priority → mechanization.
2. New UCAs get five parts (Source, Type, Control Action, Context,
   [Hazards]) and a priority: PMS from the §6.1 sub-loss table (worst
   linked sub-loss wins), CIF from §6.2, SIF = PMS × CIF, EJ = mean of
   C/D/O/K/E scores 1–5 with one-line rationale, band per §6.3 thresholds.
3. Every new constraint states its enforcement: harness check, R1
   production (once available), or process rule — prose-only constraints
   are a gap and must be listed as such.
4. Ship the SAFETY_ANALYSIS.md delta in the same slice; the reviewer
   checks it like any spec item.

## When a gate, suite, or conformance run goes red

1. SC-4.2: no re-run "to see if it passes" before a cause note. If the
   cause is trivial and local (your own code under test), fix normally.
   If the red implicates the judge, evidence, or concurrency, open a CAST
   entry in `CAST_LOG.md` FIRST (events → hazard state → control-structure
   flaws / process-model drift → systemic fixes → residuals).
2. A CAST entry closes only when fixes are verified (churn/negative tests)
   and residuals are tracked (FMEA rows or S1 items).

## At epoch start / exit

- Start: extend §2 control structure and the UCA/constraint/FMEA tables
  for the epoch's new control actions (boot, OS I/O, SMP, JIT…), before
  implementation.
- Exit: confirm no open P1 constraint gaps for the epoch's surface; the
  epoch review cites the safety deltas.

## Mechanized state (S0 and later)

The harness owns safety state in SQLite (`safety_losses`,
`safety_controllers`, `safety_control_actions`, `safety_ucas`,
`safety_constraints`): `--safety-sync` seeds/updates rows idempotently
from the OCaml seed module; `--safety-status` reports constraints by
status and UCAs by band, and fails on referential breaks (UCA without CA,
SC without UCA, SIF ≠ PMS×CIF). Doc and DB must agree — the sync's
totality check is the law. EJ Monte-Carlo sensitivity (W-6) perturbs
factor scores ±1, seeded, N=1000, and reports band stability.

Constraint-enforcement rete rules follow the SP-SIF-GUARD shape: opt-in via
a poka-yoke token in the cycle's slice/notes, fail-closed on the declaring
path, facts projected from REALITY (source content, DB rows, the git diff)
— never notes-self-attestation. Live examples: `SP-SIF-GUARD` (`uca:`/`ca:`/
`aor:` + `guard:`), `FV-Tier1` (Tier-1 + PROVEN registry), `SP-SMP-LOCKGATE`
(`smp-lock:` + the SMP law trio projected from `src/` content, DIVERGENCE
614). When a new constraint's enforcement is "harness check", prefer this
shape and give it a live law battery under `--verify-formal`.

## Hard rules

- Worst-case discipline: UCAs are assessed in worst-case context even
  where safeguards exist (Handbook p.37: prevent UCAs *even if safeguards
  do exist*).
- The four UCA types are complete; consider all four every time. The mechanized
  ledger now carries ≥1 row of EACH canonical type — `wrong_timing` was closed by
  UCA-11.2 (the SMP per-pair-order fault on CA-11; §13) — and `--selfcheck-coverage`
  **L59** guards that coverage: a re-seed cannot silently drop a type back to zero.
  `--selfcheck-coverage` **L55** additionally rejects a prose-only "Enforced" SC.
- Priorities order work; they never excuse P2/P3 hazards from constraints.
- Safety rows ratchet like coverage: constraints never silently weaken.
- Automation controllers are in scope: the OCaml script fleet is
  CTRL-OCAML-SCRIPT / CTRL-HARNESS-MOD (`SAFETY_ANALYSIS.md` §11,
  UCA-SCRIPT-1..4; process rule `docs/OCAML_SCRIPTING_SOP.md`) — scripts
  are report-only and may never write gate evidence.

## Harness-engine controllers (harness-P1..P10)

The parallel/incremental gate added evidence-path controllers, each with FMEA
rows in `SAFETY_ANALYSIS.md` §5 and laws in the engine selfcheck battery:
CTRL-DB (writer-actor; LAW P1), CTRL-GRAPH (fingerprints; LAW P2), CTRL-CACHE
(dirty frontier; LAW P3 — the cardinal not-both: no unit both cached-green
and dirty), CTRL-SCHED (executor+scheduler; LAW P4/P5), CTRL-SHARD
(suite sharding; LAW P6 shard-union ≡ monolith), CTRL-GATE (DAG gate + Φ;
`--selfcheck-parallel`), CTRL-OODA (supervisor memory; LAW P8), CTRL-L0..L3
(Tier-2 orchestration; procedural, `skills/harness-supervisor/SKILL.md`).
The standing cardinal constraint: **no false-green** — a cached/parallel/
sharded path may never report verified what the sequential-cold oracle would
not. Any engine red gets a `CAST_LOG.md` entry before re-run, like any gate.

## Fractal FP atlas synchronization

Atlas-governed changes traverse `CA-49` → `UCA-49.1` → enforced `SC-49.1`.
Confirm the exact diff was completely projected, the typed classifier is
non-empty only for governed surfaces, all eleven projections were regenerated,
and `--selfcheck-fractal-fp-atlas` plus `--wiki-audit` are green. Record
`phase:atlas_sync`; it is a trace token, not safety or gate evidence.
