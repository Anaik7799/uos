---
name: smtml-solver-substrate
description: Use the smtml SMT layer in the OCaml harness — the fail-closed judge kernel, tri-backend agreement (Alt-Ergo / z3-textual / z3-inproc), recorded evidence with unsat cores, incremental contexts, and the encoding law patterns. Use when adding any solver-backed law, obligation, audit, or counterexample generator, when a solver outcome must become harness evidence, or when touching harness/zigvm_harness.ml's hia_* family.
---

# smtml solver substrate — the SMT layer of the harness

Governs all SMT work in the OCaml harness. The formal spec is
`docs/formal/harness-intelligence-algebra.md` (Signature O); the placement
analysis is `docs/SMTML_FRACTAL_ANALYSIS.md`; landed laws are L27–L68 in
`--selfcheck-coverage` with mutants MUT-HIA-1..83 in `MUTATION_LOG.md`
(L55–L64 = the Wave-0/1 governance-audit battery — SC-totality, FVSI census,
staleness/unknown-creep totality, UCA-type coverage, rule-name uniqueness,
CAST auto-draft, real-commit obligations, witness-gen, Rocq sidecars; L65–L68 =
the first four Wave-2/3 CLOSED-FORM calibrated instruments (no Stan, all reading
data that ALREADY exists — no schema change) — L65 a Beta-Binomial
mutation-adequacy posterior with a falsifiable credible interval, L66 a
gate-growth high-water-non-regression instrument from `harness_events`, L67 an
Amdahl scaling-efficiency instrument from `scale_band` (e(n)=speedup/n checked
against Amdahl's law: no-superlinear + monotone + floor), L68 a ZK
embeddings-health instrument from `note_vectors` (well-formedness + distinct-rate
floor + no-dominant-cluster, disclosing the ~11.6% structural-block collision);
L54 = the record-cycle switch-fingerprint drift guard; L33 gained a
non-constancy arm — MUT-HIA-51).

## The doctrine (non-negotiable)

> SMT proposes, refutes, ratchets, explains, and generates witnesses.
> Rocq/Lean prove. Rete gates. The pinned OTP differential decides parity.

- Every consultation flows through `smt_judge` (the fail-closed judge:
  polarity × outcome, exhaustive 12-cell match; ONLY decisive
  polarity-matched outcomes are green; Unknown/Timeout/Crash/Unsupported
  are red — SC-SMT-2). Never bypass it, never wrap it.
- Recorded consultations go through `hia_check_recorded`
  (`?checker ?solver ?core_hash`) — the insert precedes the verdict on
  every branch (SC-SMT-1, evidence-totality, L32). The `smt_obligations`
  table is REPORT-ONLY: L29's distance law forbids any Rete rule from
  patterning on intelligence fact classes; SC-SMT-EV-1 forbids gate
  authority without a CIF re-band + SP-SIF-GUARD rule + DIVERGENCE.
- Solver results NEVER write `PROVEN` (SC-SMT-3); counterexamples used in
  fixes must replay as laws/fixtures (SC-SMT-4).

## The backends (and how they must agree)

| Leg | Module | Notes |
|---|---|---|
| Alt-Ergo in-process | `Hia_solver = Smtml.Solver.Batch (Smtml.Altergo_mappings)` | pure-OCaml; DO NOT use under `Solver.Incremental` — the mappings `assert false` on that path (measured, smtml 0.29.0) |
| z3 textual | `hia_z3_outcome` → `hia_smtlib_script` + `Aeon.z3_binary`/`run_timed` | the Aeon gate's own mechanism; also the CORES leg (`?named` asserts + `(get-unsat-core)`, `hia_z3_core`) |
| z3 in-process | `Hia_z3 = Smtml.Solver.Batch (Smtml.Z3_mappings)` | requires smtml built AFTER the `z3` opam package (`opam reinstall smtml` — nop mappings otherwise; L44's availability arm reds on that state) |
| incremental | `Hia_inc = Smtml.Solver.Incremental (Smtml.Z3_mappings)` via `hia_check_inc` | strict push/add/check/pop bracketing (spec §4.2, L46); hot sweeps attribute as `z3-inc` |

The triangle is LAW: L42 (AE ≡ z3-textual over the corpus, absence-red) +
L44 (z3-inproc ≡ AE + attribution counts) + L46 (incremental ≡ batch,
total differential). A new backend = a new homomorphism + an agreement
law; divergence is a red FIXTURE, never resolved by preferring a backend.

## API sharp edges (each cost real time — do not rediscover)

- **`Bool.not (Bool.equal a b)` simplifies to the `Ne` relop, which the
  SMT-LIB printer REFUSES** (`assert false`). Build inequalities with
  `hia_neq` (Naryop Distinct).
- **`Expr.Smtlib.pp` is PARTIAL**: asserts on Triop (ite) and Naryop
  (distinct). The textual leg uses the OWNED total emitter
  `hia_smtlib`/`hia_smtlib_script` — fail-closed (`So_crash`) outside the
  HIA fragment (Val/Symbol/Not/Add-Sub-Mul/And-Or/Eq-Lt-Le/Ite/Distinct).
  Extend the emitter when you extend the fragment; pipe-quote symbols.
- `Relop` has NO `Gt/Ge` — flip operands around `Lt/Le`.
- `Expr.Bool.ite` exists and is polymorphic in branch type; encode finite
  tables as ite-chains with a POISON default so out-of-domain reds loudly.
- Symbols: `Smtml.Symbol.make Ty.Ty_int "name"`; model bindings via
  `Model.get_bindings`/`evaluate`; `Symbol.to_string` returns the bare name.
- The literal-injection pattern (distinct strings ↦ distinct ints) is
  SOUND for Eq/Ne over infinite domains; multi-valued fields (zk `tag`)
  must be ABSTAINED — encoding them as one variable is unsound (L50's
  abstention arm is itself a law).

## Law patterns that must accompany any new use

1. **Fail-closed**: the indecisive-never-green arm.
2. **Counterexample naming**: on refutation, the model must NAME the
   offending element (row/pair/cell/trace) — and a poisoned fixture must
   be shown to be named EXACTLY (the MUT-HIA-12/14 pattern).
3. **Witness replay by an independent kernel**: Sat models replayed
   through the OCaml evaluator/truth-table/step function — and that
   kernel must itself be pinned to ABSOLUTE ground truth first
   (MUT-HIA-28's lesson: relational checks are negation-invariant).
4. **Non-vacuity floors AND scan counts**: a floor that reads the source
   directly cannot see a lazy scanner — return and assert scanned counts
   (MUT-HIA-39's lesson).
5. **Attribution**: distinct solver legs record distinct `solver` values;
   a count law catches provenance laundering (MUT-HIA-18).
6. **Round-trip needs a non-constancy pair**: a law of the form
   `stored == recomputed` (DB round-trip, serialize∘deserialize,
   encode∘decode, replay-key determinism) is SATISFIED by a DEGENERATE
   constant/length-only function — both sides degrade together, so the
   round-trip alone never catches it (MUT-HIA-51: a `+0`-fold
   `hia_formula_hash` sailed through L33's round-trip). Pair every
   round-trip/determinism law with a DISCRIMINATION arm — two
   structurally-distinct inputs must map to DISTINCT outputs.

## Mutation recipes (plant per slice, kill, revert, log)

Seam inversion (Sat↔Unsat), unknown/timeout laundering, emission
truncation (drop trailing asserts), parse inversion, superset cores,
projection shift, attribution constant, scan truncation, **constant/
length-only hash or key (survives a round-trip law → forces the
non-constancy pair, MUT-HIA-51)**, **incremental pop-skip (a leaked
assumption shadows every later check on the shared context — the whole
incremental suite reds, not just the pop-shadow arm, MUT-HIA-50)**. Verify
kills by LAW LINE + exit code (CAST-12) — a compiler kill or a
concurrent-session build failure is NOT a kill; rewrite the mutant until
the law claims it.

## Environment gotchas

- Concurrent sessions mutate the opam switch (a stanc3 build once removed
  smtml mid-mutant); on `Library "smtml" not found`, wait and RE-VERIFY
  any in-flight kill.
- Closure protocol under contention: detached-worktree gate (CAST-zk5) —
  `OPAMSWITCH=<root>` + `ZIGVM_ZIG=<root>/.zig-tools/.../ziglang/zig` +
  `ln -s <root>/third_party/otp <wt>/third_party/otp`.
