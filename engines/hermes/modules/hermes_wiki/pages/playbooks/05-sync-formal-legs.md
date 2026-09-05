# 05 — Sync the formal legs

The formal tools are **differentials**: each one re-derives a property the
OCaml claims, from an independent artifact. When the OCaml changes, the
matching leg MUST be re-synced or its test fails — that failure is the leg
working. Never silence it; re-sync it.

## Which change triggers which leg (lookup table)

| You changed… | Re-sync | How |
|---|---|---|
| `parity_intent.ml` blueprint (add/remove directive, change `requires`) | Quint | step A |
| `parity_algebra.ml` (verdicts, combine, roll_up) | Rocq + z3 + smtml | steps B, C |
| `harness_config.ml` algebra (fold, Gate) | z3 (Gate law) | step C |
| Hazard/countermeasure tables | Rete rules + drift rules tests | step D |
| Verification receipts accumulate | Stan (nothing to edit — rerun) | step E |

## Step A — Quint (the intent DAG differential)

1. ACTION: Edit `hermes_harness/specs/parity_frontier.qnt` so its intent set,
   `requires` edges, and state count mirror the new blueprint exactly. The
   model is small — pattern-match the existing entries.
2. VERIFY: `dune exec hermes_harness/test_quint_frontier.exe` → `failed: 0`.
   The test runs `quint` and cross-checks its verdicts (e.g. `reqClosed`
   Holds, `notConverged` Violated) against the OCaml `Converge` results.
3. IF-FAIL with a verdict mismatch: the model and the code disagree — find
   which one reflects the intended blueprint and fix THAT one. A mismatch is
   the differential catching a desync (it has done so before); never edit the
   test's expectations to agree with a wrong side.
4. IF-FAIL because `quint` is not installed: Blocked (Environment) — report;
   do not skip the test.

## Step B — Rocq (machine-checked lattice) + pinned extraction

1. ACTION: If a lattice law changed, update `hermes_harness/proofs/Parity_Lattice.v`.
   Keep `Require Import List PeanoNat` at the TOP (so `combine` shadows
   `List.combine` — moving it breaks the file).
2. Re-extract: the extraction target is `generated_rocq/parity_lattice_extracted.ml`;
   run coqc via the pinned switch: the validated command form is
   `opam exec --switch=rocq-iris -- coqc` (set `HERMES_COQC` to exactly that).
3. VERIFY: `dune exec hermes_harness/test_rocq_lattice.exe` → `failed: 0`.
   This test byte-pins the extraction — a stale extraction fails it BY DESIGN.
4. IF-FAIL on freshness: you changed the .v without re-extracting (or vice
   versa). Re-extract and re-run. Never update the pin to hide a desync.

## Step C — z3 + smtml (discharged laws)

1. ACTION: If `combine`/`roll_up`/`gate_verdict` semantics changed, update the
   emitted tables in `hermes_harness/formal_specs.ml` — the specs are generated
   FROM the code under test, so usually only the law list needs review.
2. VERIFY: `dune exec hermes_harness/test_formal_specs.exe` (z3 CLI; honors
   `HERMES_Z3`) and the smtml in-process test → both green.
3. IF z3 is absent: Blocked — report. Never mark a law discharged that wasn't.

## Step D — Rete + Rust rule engine (drift → runbook)

1. ACTION: If hazards/countermeasures/drift vocabulary changed, update the
   GRL rules under `rust/drift_engine/` and/or `hermes_harness/drift_rules.ml`
   mappings.
2. VERIFY: `dune exec hermes_harness/test_drift_rules.exe` and
   `dune exec hermes_harness/test_rust_rules.exe` → green.
3. KNOWN PITFALL: the vendored GRL parser is lenient (fail-open on malformed
   rules — recorded finding). Treat a silently-ignored rule as a defect: the
   OCaml side must validate rule presence/count, and the tests pin that.

## Step E — Stan (receipt reliability)

Nothing to edit when receipts accumulate — re-run the reliability report and
confirm posteriors update. If a slice's pass posterior DEGRADES while its
compare is still green, report it (that is early warning, not noise).

## The one meta-rule

A formal leg that fails after your change is **doing its job**. The order is
always: understand which side is wrong → fix that side → re-run. It is never:
delete the check, loosen the assertion, or re-pin to the new output without
understanding why it changed.
