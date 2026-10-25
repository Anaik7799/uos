---
name: algebraic-fractal-structures
description: Apply ZigVM algebraic analysis, design, implementation, law-suite, mutation, documentation, and harness rules across fractal layers. Use when changing ZigVM behavior, adding rules/skills, reviewing subsystem completeness, planning a slice, or implementing components that must preserve oracle/final/homomorphism discipline.
---

# Algebraic Fractal Structures

Use this skill to keep ZigVM work algebraic at every scale.

## Required Reads

Before changing behavior, read:

1. `AGENTS.md`
2. `HANDOFF.md`
3. `ROADMAP.md`
4. `OTP30_PARITY_PLAN.md` (program plan of record for OTP 30-rc equivalence)
5. `CODEBASE_MAP.md`
6. `ALGEBRAIC_FRACTAL_RULES.md`
7. `ALGEBRAIC_RULES_USAGE.md`
8. `ALGEBRAIC_DOC_REVIEW.md`
9. `ALGEBRAIC_PROGRAMMING_REFERENCES.md`
10. Owning `src/*.zig` module doc-comment

## Workflow

1. Classify the target layer: repository, artifact, subsystem, module, feature,
   representation, operation, generator/fixture, mutation, or verification.
2. Classify the target stratum: A core algebra, B engine/interpretation, or C
   substrate.
3. Classify the data-structure family from `ALGEBRAIC_FRACTAL_RULES.md`.
4. Fill the component packet: carrier, denotation, operations, observations,
   invariants, oracle, final encoding, laws, generators, negative cases,
   mutant targets, docs, and harness evidence. If the slice touches a
   controller or an evidence path, also fill the safety packet of
   `ALGEBRAIC_FRACTAL_RULES.md` §10 (control actions → UCA refs →
   constraints → FMEA delta → priority → mechanization) per
   `skills/stpa-safety-protocol/SKILL.md`.
5. Derive the weakest Stepanov/EOP/ADD concept requirements: operations,
   associated types, equality/order/hash behavior, traversal category,
   ownership, initial/final encoding status, generator shape, and complexity.
6. Write the semantic domain before editing code.
7. Identify the oracle and final encoding. If the slice is semantic-only,
   state that explicitly and add laws anyway.
8. Add laws named after algebraic properties: homomorphism, monoid,
   round-trip, idempotence, total order, partial bijection, transparency,
   exactness, or rejection.
9. Add seeded positive tests, negative tests, boundary tests, and
   concept-requirement tests.
10. Record at least two mutant targets in `MUTATION_LOG.md`.
11. Sync docs: module comment, `HANDOFF.md`, `ROADMAP.md`, `CODEBASE_MAP.md`,
    `IMPLEMENTATION_PLAN.md`, `ALGEBRAIC_RULES_USAGE.md`, and
    `ALGEBRAIC_DOC_REVIEW.md`, and `ALGEBRAIC_PROGRAMMING_REFERENCES.md` when
    the rule map changes.
12. Run `opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD"`.
    The default gate is DAG-driven (incremental + parallel, harness-P7);
    `--sequential` is the preserved oracle path. A slice touching the harness
    ENGINE (db/vgraph/vcache/vsched/zshard/supervisor_memory) must also keep
    the engine battery green: `--selfcheck-db`, `--selfcheck-graph`,
    `--selfcheck-cache`, `--selfcheck-sched`, `--selfcheck-shard`,
    `--selfcheck-parallel`, `--selfcheck-ooda` — the engine is itself a
    Stratum-B controller admitted by the homomorphism `Φ`
    (`par_inc ≡ seq_cold`) against the sequential oracle, with a TLA+ model
    (`docs/formal/`) covering the interleavings the seeded laws sample.
13. Inspect or cite the latest SQLite run status.
14. If the slice touches OTP-parity surface (opcode/BIF/suite/bench coverage),
    also follow `skills/otp-conformance-protocol/SKILL.md` and keep the
    conformance ledgers and ratchets green.
15. Run the loop as OODA at every scale (plan §10): observe harness/fact
    state → orient via ledgers and safety priorities → decide the smallest
    law-carrying slice → act; verification sits inside every loop
    (failing-first, review, gate, ratchet), and every red becomes a
    permanent law, mutant, CAST entry, or rule — never only a fix.

## Non-Negotiables

- Keep ZigVM implementation code in Zig under `src/`.
- Keep harness logic in OCaml under `harness/`, and all workspace
  automation/scripting in OCaml under `scripts/` per
  `docs/OCAML_SCRIPTING_SOP.md` (no shell/Python/Node anywhere).
- For every VM data structure, document carrier, denotation, operations,
  observations, invariants, laws, and mutation targets.
- For every generic algorithm, state the weakest concept requirements and
  validate that the implementation does not depend on a stronger capability.
- Do not admit final encodings by intuition; use oracle/final homomorphism,
  differential state equality, trace equivalence, or an explicitly scoped
  semantic precursor.
- Do not let substrate behavior become semantic denotation.
- Do not close a slice with passing tests only; completion requires laws,
  mutant targets, docs, and harness evidence.
- **A checker over a structured format needs the format's algebra, not a
  substring scan.** If a rule reasons about a construct — a table, markup, a
  config grammar — model the construct: state its ontology, its signature, its
  semantic domain, and admit the fast encoding against an oracle. The failure
  mode is not a missed defect, it is a CONFIDENT WRONG ANSWER whose proposed
  remedy corrupts the artifact it was protecting. Both instances of this in the
  programme are written up: `docs/design/TABLE_ALGEBRA.md` (a pipe counter
  reported an append-only ledger of pipe-delimited records as 33 malformed
  table rows) and `docs/design/HTML_ALGEBRA.md` (byte scans counted markup
  inside comments, scripts and attribute values). The tell is a rule whose
  precision you cannot state.
- **A solver obligation must be the NEGATION, and it needs a live control.** An
  SMT stage that asserts the THEOREM is trivially satisfiable and proves
  nothing; assert its negation and require `Unsat`, with `Unknown` failing
  closed. Then add a negative control that MUST come back `Sat`, or the stage
  cannot distinguish a proof from a solver answering `Unsat` unconditionally —
  and make that control a NON-trivial claim, because a tautology is Sat for no
  reason at all (`MUT-TAG-3` survived exactly that). Worked example:
  `verify_tagging_smt` in the formal gate.
- **A mutation score does not measure the code — it measures the LAW.** A mutant
  is scored against the SAME fixture the law uses, so the two share a blind spot
  and cannot corroborate each other. A slice this week scored 2/2 on mutants,
  passed its own law, and corrupted `maps:fold_1`. Any slice that changes how
  real programs execute needs at least one law that runs a REAL artifact
  end-to-end; constructed fixtures test what you thought of, a real module tests
  what the compiler actually emits. Full argument: `docs/TESTING_DISCIPLINES.md`
  §7.
- **Enumerate positions; never argue "by symmetry".** Four defects in one week
  were one shape — a SYMMETRIC FIXTURE OVER ASYMMETRIC CODE. The JIT emitter
  helpers destroy different registers depending on which operand is a frame slot
  (`emitYAddr` takes r10, `emitWriteDst` takes rcx), so `swap x,y` and
  `swap y,x` are different code; every fixture tested one. If the implementation
  can distinguish two arguments, the law must too. "By symmetry" is a claim
  ABOUT THE CODE and it is the claim most likely to be false.
- **Hold generated artifacts to a stricter standard than authored ones.** A
  defect a renderer absorbs is acceptable in something a human wrote and is a
  bug in a generator — reproducible across everything it emits — when we
  produced it. Make that split mechanical, not a matter of review.

## Component Lookup

Use `ALGEBRAIC_FRACTAL_RULES.md` section 4 for component-specific rules.
Use section 5 for data-structure families and section 6 for programming rules.
Use `ALGEBRAIC_PROGRAMMING_REFERENCES.md` for concept extraction, regularity,
whole-part semantics, iterator/range discipline, copying, rearrangement,
ADD-style initial encodings, law discovery, generators, and semantics freeze.
Use `ALGEBRAIC_RULES_USAGE.md` section 7 for cross-cutting law locations.

Current next best target is **whatever the kanban `next_slice` returns** (MCP
`next_slice` / `--ooda-observe`) — routed by criticality, never a hard-coded epoch
named in a doc (any epoch number written here goes stale; the numbered epochs
E0–E46+ and the S-epoch/`gap-*` fronts are all in `DIVERGENCE_LOG.md` and the
kanban). The former standalone targets (S22 `duplicate_bag`, term-level
bitstrings, ETF `BIT_BINARY_EXT`) are long resolved.

## Fractal FP atlas synchronization

Treat the governance registry as another finite algebraic structure: exact
paths are the carrier, `classify` is the observation, and non-empty image is the
conditional trigger. For a governed change, update its packet, regenerate all
eleven views, run `--selfcheck-fractal-fp-atlas` plus `--wiki-audit`, and record
`phase:atlas_sync`. Never infer evidence from the token; exact-head gate results
remain authority. Empty image means no atlas ceremony.
