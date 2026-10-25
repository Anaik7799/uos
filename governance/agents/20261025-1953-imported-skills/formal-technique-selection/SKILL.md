---
name: formal-technique-selection
description: Decide WHICH formal/algebraic technique fits a task by matching the technique to the SHAPE of the subject — ruliology (rewrite systems), Z3/SMT (decidable formulas), Rete-UL (fact→verdict gate), ADD algebra (homomorphism/lattice/order), Rocq (deep invariants), Lean (proof-carrying code), Aeon (refinement types→SMT), Quint/TLA+ (concurrency), ML (label-rich suggestions). Use when promoting a report-only module to a law-carrying guard, when picking a verification method for a new slice, or whenever tempted to apply a solver/prover to something — to tell real technique-fit from technique-theater. Every fit carries an independent oracle and honest non-fit boundaries.
---

# Formal Technique Selection — match the technique to the shape

For Sa-plan-governed work, formal/SMT/Rocq results enter and exit through a
typed OCaml Store event linked to a task and exact revision; a proof report
cannot mutate plan state directly.

The mistake this skill prevents is **technique-theater**: bolting Z3 onto prose,
"proving" a rule base that has no formula, running a fuzzer against a
reimplementation of the thing under test, or reporting a solver's own `sat`/`unsat`
as if it were evidence. A technique earns its place only when the subject has the
**shape** the technique decides, and only when an **independent oracle** admits the
result. Pick by shape first; if no shape matches, the honest answer is a heuristic
that says so — not a solver wearing a lab coat.

Read this alongside `skills/algebraic-fractal-structures/SKILL.md` (the law-carrying
slice workflow) and `docs/formal/knowledge-systems-algebra.md` §7 (the governance
ring: ruliology frame, Rete-UL isolation, the Rocq/Aeon mechanization ladder).

## The one-screen decision table

| The subject's SHAPE | Technique | The oracle (what admits it) | Repo mechanics | Reference slice |
|---|---|---|---|---|
| a **rewrite system** (X ↦ Y normalization: escaping, expansion, compilation, peephole) | **Ruliology** — confluence, termination, critical pairs, normal forms | the *real* transform being modelled, or the property's fixpoint | `--selfcheck-tag-laundering`: normal-form/idempotence/termination over `E: #tag ↦ \#tag` | DIVERGENCE 690 |
| a **decidable formula** (LIA, bitvector, FP, string equality, bool) | **Z3/SMT** (smtml native `Solver.Batch(Z3_mappings)`) | an **independent** re-derivation of the answer (evaluate the model; refute on a sample) | `--selfcheck-smt-equivalence`: `(e1≠e2)` UNSAT decides mutant equivalence | DIVERGENCE 685/688 |
| **gate-critical harness facts → verdict** (build state, ledgers, run status) | **Rete-UL** forward-chaining | fail-closed gate mediation over `Rete_rules.all_rules` | the Zero-Trust `record_cycle` gate; `--selfcheck-gate-coupling` proves isolation | DIVERGENCE 669 |
| any **carrier + operations** (the universal frame) | **ADD algebra** — homomorphism, monoid, lattice, total-order, round-trip, idempotence, rejection | an **oracle encoding** ≠ the final encoding (initial vs final) | every `--selfcheck-*`; `denote(final)=denote(oracle)` | all 7 promotions |
| a **deep invariant** that must hold across drift (aliasing, ordering, safety) | **Rocq/Coq** (Tier-1, coqc fail-closed) | the machine-checked proof term | `--verify-formal` coqc stage; `--check-proof-staleness` guards drift | DIVERGENCE 668/672 |
| a **verified property that must also EXECUTE** as trusted code (proof-carrying code) | **Lean** (proof → freestanding-C extraction → OCaml FFI) | the Lean kernel proof **and** a freshness gate binding the extracted C to the `.lean` source | `--verify-lean` (type-check) + `--codegen-lean` (`proofs/lean/Kernel.lean` → `harness/generated/lean/lean_kernel.c`, `lean_ffi.ml`) | Kernel.lean / Lockstep_Freshness.lean |
| a **spec expressed as refinement types** (data whose type carries a logical predicate: `{v:Int \| v>0}`) | **Aeon** (refinement/liquid types, predicates discharged to SMT) | the Z3 discharge of each refinement obligation, **plus** native-vs-reference differential | `aeon_lang.ml` (pure-OCaml checker, Z3-CLI backend); `--codegen-aeon` (`specs/aeon/*.ae`→OCaml); `--aeon-corpus` (native≡Python-Aeon) | aeon-native |
| **concurrency / temporal** (interleavings, liveness, fairness) | **Quint / TLA+** (model check) | the model checker over the state space | `--verify-formal` quint stage; `docs/formal/*.tla` | E20-T5 |
| **label-rich ranking / prediction** (enough real labels to learn from) | **ML / OCANNL** (report-only SUGGESTION class) | a downstream law/SMT check (the sandwich: ML suggests → SMT checks → laws admit) | never a guard by itself; label-starved today | OCANNL_FRACTAL_ANALYSIS.md |

If the subject fits **no** row, do not manufacture a fit. Ship a heuristic that
prints `[LIMITATION]`/`[NOTE]` naming what it cannot decide, exactly as the
report-only support modules do.

## How to decide, in order

1. **Name the subject precisely.** Not "the MoC module" — "the `#tag → \#tag`
   escape transform." Not "the query analyzer" — "the `WHERE FIELD op N` numeric
   fragment." The shape lives in the precise noun.
2. **Ask: is it a rewrite, a formula, a fact→verdict, a carrier-with-ops, a deep
   invariant, a concurrency property, or a learning problem?** That is the table's
   left column. One subject can host several (the tag-escaper is a rewrite system
   *and* an algebra — ruliology gives the richer law set).
3. **Confirm non-vacuity in the live repo.** A crisp technique over an empty
   subject is still make-work. Grep the corpus/source: are there transclusions,
   numeric WHERE-clauses, published MoCs, declarative rule conditions to reason
   over? Zero live instances → at best an *armed regression guard*, and say so.
4. **Identify the independent oracle.** The technique's output must be admitted by
   something that is *not the technique itself*. No oracle → no law, only a report.
5. **Refuse if it's theater.** If steps 2–4 don't land, write the honest
   heuristic. `INAPPLICABLE (not merely unwired)` is a valid, respected verdict.

## Per-technique field guide

### Ruliology (rewriting-system theory)
**Fits:** anything that normalizes one form to another — tag-escaping, transclusion
expansion, markdown→HTML, ETF/term canonicalization, dispatch peephole rewrites,
MoC generation (the fixpoint-immunity theorem). The ZK/wiki layer is a *nest* of
rewrite systems; most carry no confluence/termination law yet — the richest open
seam.
**Laws it yields:** NORMAL-FORM soundness (no redex survives), IDEMPOTENCE (the
normal form is a fixpoint), TERMINATION (a well-founded measure → 0), CONFLUENCE
(unique normal form; **orthogonal** systems — non-overlapping redexes — are
confluent *by construction*, so state it rather than brute-force it), TRANSPARENCY
(the rewrite is a homomorphism on the non-redex projection).
**Oracle:** the *real* transform (e.g. the actual `Docs_wiki` indexer for what
counts as a redex), never a re-transcription of it.

### Z3/SMT (decision procedures)
**Fits:** a genuine decision problem in a decidable theory — expression equivalence
(`(e≠e')` UNSAT), query-condition unsat/redundancy/subsumption (LIA + string eq),
tag-bit disjointness/decodability (bitvector), layout-padding optimality (ILP),
tolerance-bound violation (QF_FP).
**Backend:** smtml native — `module S = Smtml.Solver.Batch(Smtml.Z3_mappings)`;
the `z3` opam package (4.16.0) supplies the binding. Typed `Expr` combinators:
`Ty.Binop.{Add,Sub,Mul}`, `Ty.Unop.Neg`, `Ty.Relop.{Eq,Ne,Lt,Le}` — **no Gt/Ge**,
write `a>b` as `b<a`. Model via `S.model`/`Model.get_bindings`.
**Oracle (the non-negotiable):** never trust the solver's own verdict. A `sat` is
validated by **evaluating the returned model** with an independent evaluator; an
`unsat` is **refutation-tested** on a seeded sample. See `equivalent_mutant_classifier`.
**Theory coverage:** LIA + bool (mutant-equiv/688, query-sat/692) AND **QF_FP**
(float-finiteness/706 — `fp.isNaN`/`fp.isInfinite`/`fp.sqrt`/`fp.div` decide the
Erlang no-NaN/±Inf-terms invariant). **Capability caveat:** smtml's NATIVE Z3
backend does NOT wire the FP predicates (`Unsupported operator "is_nan"`) — for
QF_FP, emit SMT-LIB2 `(set-logic QF_FP)` over `(_ FloatingPoint 11 53)` and shell
to the Z3 CLI (`.aeon-tools/bin/z3`, aeon's path), exactly as `equivalent_mutant`
did before smtml's LIA path matured. Also: smtml *constant-folds* all-literal FP
ops in its own evaluator (throws `Eval_error`) — keep operands symbolic.
**Does NOT fit:** prose ("spec matches its doc" is not a formula), or a rule base
with **zero declarative conditions** (the Rete rules discriminate in opaque OCaml
actions — nothing to encode). Both are marked `INAPPLICABLE (not merely unwired)`.

### Rete-UL (forward-chaining fact→verdict)
**Fits:** the gate-critical decision "given these harness facts, is the cycle
admitted?" — the Zero-Trust `record_cycle` mediator.
**Hard boundary:** the gate is **decoupled from doc/wiki vocabulary** (DIVERGENCE
669: `consumed_kinds(all_rules) ∩ doc_report_kinds = ∅`). Wiring a ZK/wiki/doc
analysis into a gate rule would make a rule consume a doc fact-kind and **breach
that isolation** — a category error. Rete-UL is *not* the vehicle for the zk_*
modules; keep them standalone and report-only. It is also single-pass (no
unlinking, not the Rete algorithm) — the guarantee is fail-closed mediation, not
incremental matching.

### ADD algebra (the universal frame)
Every promotion is structured this way regardless of the headline technique: one
**initial/oracle** encoding, one **final** encoding, and a homomorphism law
`denote(final) = denote(oracle)`, plus monoid/lattice/order/round-trip/idempotence/
rejection laws as the carrier admits. If you can't name the oracle and final
encodings, you don't yet have a law-carrying slice.

### Rocq/Coq
**Fits:** deep invariants that must survive source drift — aliasing, per-pair
ordering, CRDT convergence. Expensive; reserve for foundational properties. The
proof term is the oracle; `--check-proof-staleness` guards the proof↔source
correspondence (it caught 6 stale Tier-1 proofs, DIVERGENCE 668/672). A
self-contained `.v` compiles regardless of source drift, so the staleness guard is
mandatory alongside the coqc stage.

### Lean (proof-carrying code)
**Fits:** a property you must both *prove* and *run as trusted code* — Lean proves
a kernel invariant, then **extracts freestanding C** (`Kernel.lean` →
`harness/generated/lean/lean_kernel.c`) linked into the harness via `lean_ffi.ml`.
This is the rung Rocq doesn't cover: not just "the invariant holds" but "the
executable that ships *is* the verified object."
**Oracle (two-part):** the Lean kernel proof (`--verify-lean` type-checks the
`.lean` fail-closed) **and** a **freshness gate** asserting the generated C
byte-matches the current source (regenerate with `--codegen-lean`). The extracted
C is the one boundary-rule exception to "no non-Zig implementation" precisely
because it is *generated from a verified source*, not hand-authored — treat a
freshness mismatch as red, never hand-edit the generated C.

### Aeon (refinement types → SMT)
**Fits:** a specification naturally expressed as **data whose type carries a
predicate** — `{v:Int | v>0}`, `{xs:list | sorted xs}`. Aeon is the pure-OCaml
refinement/liquid-type checker (`aeon_lang.ml`) that discharges each refinement
obligation to **Z3** (the CLI backend — the historical reason the smtml-native Z3
work consolidated on aeon's path). Reach for it when the property lives at the
*type boundary of a value* rather than as a standalone theorem (Rocq/Lean) or a
one-shot query (raw Z3): the predicate travels with the data and is re-checked at
every construction/use site.
**Oracle:** the Z3 discharge of each obligation, **plus** the native-vs-reference
differential — `--aeon-corpus` measures the pure-OCaml Aeon against the shipped
Python-Aeon reference over Aeon's own corpus (equivalence is the cross-check), and
`--codegen-aeon` keeps `specs/aeon/*.ae` → generated OCaml fresh in the gate.
**Relation to raw Z3/SMT:** same solver, different altitude — raw SMT decides a
*single formula* you built (mutant equivalence, a WHERE-clause); Aeon decides a
*refinement obligation attached to a type* across a whole program. Use raw SMT for
a bounded decision; use Aeon when the spec is a type discipline.

### Quint/TLA+, ML/OCANNL
Quint/TLA+ for **interleavings and liveness** the seeded laws only sample.
ML/OCANNL only where **real labels exist**, and only as a report-only SUGGESTION
that a law or SMT check then admits (the sandwich doctrine) — it is label-starved
here, so no ML guard today; do not add ML make-work.

The mechanization ladder (`docs/formal/knowledge-systems-algebra.md` §7): each rung
— coqc → quint → lean → aeon → smtml — arms the formal gate from a different angle;
land one rung per slice, and keep each rung's freshness/staleness guard green so a
proof or extraction can never silently drift from the source it certifies.

## The independent-oracle principle (the through-line)

A technique's output is evidence only if something independent admits it:

- SMT `sat` → evaluate the model with your own evaluator (WITNESS-VALIDITY).
- SMT `unsat` → refute it on a seeded sample of the oracle (SAMPLED-AGREEMENT).
- a rewrite's "normal form" → run the *real* consumer (the live indexer) on the
  output and confirm ∅ (NORMAL-FORM vs the real oracle).
- a detector's finding → a FIDELITY law that the detector equals the real
  ground-truth extractor on a fixture battery (this is what caught the
  tag-laundering module's 57 phantom violations).

Trusting the tool to certify itself is vacuous. If you cannot find an independent
oracle, you have a report, not a guard.

## Promoting a module with the chosen technique (the workflow)

Once the shape → technique → oracle is fixed, follow the law-carrying slice loop
(`algebraic-fractal-structures`): semantic domain → oracle & final encoding →
named laws (≥5, one per algebraic/ruliological property) → **≥2 mutants each
killing a DISTINCT law** → a `--check-X` (fail-closed verdict) + `--selfcheck-X`
(the law battery) wired into `zigvm_harness.ml` (action / label / arg / dispatch /
handler) → docs (module doc-comment, DIVERGENCE_LOG, MUTATION_LOG,
ALGEBRAIC_RULES_USAGE) → green gate → `--record-cycle`. Keep it **standalone, not in
the default gate and not gate authority** unless measured — SMT/ZK evidence never
gains gate authority without a CIF re-band (SC-SMT-EV-1), and doc guards must stay
off the gate to preserve 669 isolation. Fail closed if the backend (z3) is absent.

## Worked precedents (the 7 promotions)

- **db_integrity_checker** (659) — ADD/oracle: SQLite pragmas as the external
  ground truth. Airtight.
- **formal_proof_staleness_guard** (668) — ADD/order: git commit-time freshness
  lattice (Fresh<Stale). Found 6 stale proofs → re-attested (672).
- **wiki_gate_coupling_prover** (669) — ADD/set: `consumed_kinds ∩ doc_kinds = ∅`.
  Proves the Rete-UL isolation this skill relies on.
- **stratum_c_quarantine_auditor** (673) — ADD/graph: no Stratum-A `@import` into
  `substrate/`. Clean-now regression guard.
- **equivalent_mutant_classifier** (685/688) — Z3/SMT: expression-mutant equivalence,
  admitted against an OCaml evaluator oracle (the independent-oracle template).
- **zk_tag_laundering_preventer** (690) — Ruliology: the `#tag ↦ \#tag` escape
  rewrite, oracle = the real `Docs_wiki.build … .tags` indexer. Its FIDELITY law
  exposed that the prior "57 laundering violations" were an artifact of the
  module's own wrong oracle (the generator was already inert) — the case study in
  why the oracle must be the *real* consumer.
- **zk_query_dsl_fuzzer track B** (692) — Z3/SMT: zkquery WHERE-clause
  satisfiability + redundancy over the *live* `Docs_wiki.zkquery_parse` (LIA +
  string-code abstraction), oracle = an OCaml predicate-evaluator. Discharged the
  module's own "no SMT" limitation and fixed the "reimplemented grammar" smell by
  consuming the real parser (LIVE-PARSER-FIDELITY law).

## Non-fit registry (correctly refused — keep refusing)

- **SMT on prose** (`zk_formal_spec_to_doc_prover`): "a spec matches its doc" is not
  a decision problem → syntactic cross-reference + `INAPPLICABLE` note.
- **SMT on the Rete rules** (`rete_rule_redundancy_checker`): 0 declarative
  conditions → nothing to encode → `INAPPLICABLE`.
- **Ruliology/SMT on empty corpus features** (transclusion, `^id` anchors,
  `@opposes` edges, published MoCs = 0): armed regression guard at best; never
  claim a live finding.
- **Rete-UL on zk_* modules**: would breach 669 gate-coupling isolation.
- **ML anywhere as a guard**: label-starved → report-only suggestion only.

When in doubt, prefer the honest heuristic that names its limit over the
impressive-looking technique that decides nothing.
