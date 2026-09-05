---
id: hermes-unified-implementation-approach
status: published
type: decision
ktype: moc
maturity: incubating
domain: formal_verification
topics: [implementation, typing, modules, sequencing]
created: 2026-08-09
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Unified implementation approach — OCaml, fully typed, verifiable with the tools we have

#feature #src-unified #area-design #cov-design

How the design in `[[Unified feature set]]`, `[[Unified domain ontology]]` and
`[[Unified functional atlas]]` becomes OCaml modules, in what order, and how
each step is discharged by a tool that already exists in this repository.

**Constraint accepted throughout:** *checkable by the tools we have.* No step
below assumes a tool the harness does not already run — OCaml's type system,
smtml+Z3 in process, Gospel on `.mli`s, Quint, the render differential, the
suites, and the Rete gate.

## 1. Typing discipline — five rules, applied without exception

| # | Rule | Rationale | Cost of breaking it |
|---|---|---|---|
| **T1** | **Make the illegal unrepresentable before writing a check.** | Machine_checked outranks everything below it. | A runtime check is a law that can be forgotten. |
| **T2** | **Abstract every identifier behind a phantom-typed smart constructor.** | slug ≠ anchor ≠ block id. | The underscore-alphabet defect that bit the route parser. |
| **T3** | **Totality in the type.** Fallible functions return `result`/`option`; nothing raises. | An empty result must never be ambiguous with an error. | The silent-empty-query failure mode. |
| **T4** | **Purity except at three leaves.** `Corpus_io`, `Serve`, `Verify_io`. | Purity is the precondition for property tests, solver encodings and the digest. | Determinism, and with it the baseline. |
| **T5** | **Every `.mli` states the law, not the mechanism.** | The interface is where a reviewer meets the contract. | Laws drift from code into comments. |

**T1 in practice — where the design chose a type over a check:**

```ocaml
(* the route ADT has no write constructor: a write is UNREPRESENTABLE *)
type route = Index | Note of Id.page Id.t | … | Api of Api.t

(* the GADT makes `where words != 3` unrepresentable in the AST *)
type _ op = Eq : 'a op | Ne : string op | Lt : int op | …

(* `Validation` exports no `bind`: a caller cannot short-circuit and lose diags *)
val ( <*> ) : ('a -> 'b) t -> 'a t -> 'b t   (* and no `bind` *)

(* the argumentation frame takes only the attack relation:
   `@supports` cannot be passed as an attack *)
val of_attacks : (Id.page Id.t * Id.page Id.t) list -> af
```

*Second-pass extension (L38.1):* T1 has a dual — every **refusal** lives at a
visible seam, and the seams are catalogued (`Absent_arrow.absences`): an arrow
the design forbids is a named, checkable row, never an undocumented gap.

## 2. Module plan — what exists, what is new

| Module | Status | Contents | Structures |
|---|---|---|---|
| `Id` | **new** | phantom-typed identifiers | S25, S26 |
| `Validation` | **new** | accumulating applicative | S7 |
| `Optic` | **new** | lens · prism · traversal, monomorphic over `Ast` | S13–S15 |
| `Wiki_ast` | **landed** | initial algebra, `parse`, `render` | S1–S4 |
| `Wiki_ast` (extend) | new work | `cata`/`para`/`traverse`/`zipper` exposed | S2, S5, S6, S16 |
| `Hermes_wiki` | **landed** | corpus, resolver, links, anchors, graph | S17, S22 |
| `Hermes_wiki` (split) | refactor | into `Corpus`, `Resolver`, `Links`, `Graph` | S12 |
| `Wiki_query` | **landed** | grammar, total parser, evaluator, fences | S8, S9, S23, S24 |
| `Wiki_query` (extend) | new work | GADT conditions | S25 |
| `Metrics` | new | pagerank · communities · betweenness · similarity | S20, S23, S24 |
| `Discourse` | new | argumentation frame, grounded extension | S19, S20 |
| `Nav` | new | declared tree, reachability | rose tree |
| `Search` | new | index, block hits, PPR ranking | S24 |
| `Inventory` | new | publish/consume | S17 |
| `Doctest` | new | collect, run (separate builder) | S23 |
| `Doc_coverage` | new | census over `.mli` interfaces | — |
| `Ratchet` | new | monotone warning count | S18 |
| `Reconcile` | new, second pass | declared vs derived, residue, fail-closed totalisation | S36 |
| `Graded_chain` + `Solver_leg` | new, second pass | one chain schema; solver legs generated per instance | S37 |
| `Absent_arrow` | new, second pass | the catalogue of load-bearing non-arrows | S38 |
| `Law_register` | new, second pass | laws as rows; scoreboard and smells as queries | S42 |
| `Feature_register` | **landed** | 278 rows, live probes, priority | — |

Fifteen new modules (four from the second pass), three refactors, five
already landed. The refactor of
`Hermes_wiki` into four modules is what makes `Corpus` a Store comonad rather
than a record with derived fields attached.

## 3. Sequencing — by what each step unblocks, not by size

Ordered so that every step is verifiable when it lands, and no step depends on
a later one.

**Phase I — foundations that make later laws type-level.**
`Id` · `Validation` · `Optic`. Nothing user-visible; everything after is
stronger because of them. Discharge: OCaml types + applicative-law suite.

**Phase II — the addressing ladder.** `^id` block anchors (HW.3.3.1) → the
`zipper` → transclusion (HW.3.5.*). Depends on Phase I's `Id`. Discharge:
suites + **smtml for acyclicity** + baseline for the patch-locality law.

**Phase III — the reference layer.** Typed roles → ambiguity-as-error →
nitpicky → glossary → inventory. Depends on `Id` and `Resolver`. Discharge:
type-level for the kind index, suites for the rest.

**Phase IV — the graph kernels.** PageRank → constrained communities →
betweenness → similarity → **grounded semantics**. Discharge: **smtml for
monotonicity, fixed-point existence and ascent termination** — the strongest
formal opportunity in the design.

**Phase V — surfaces.** JSON API → search (needs Phase II for block hits and
Phase IV for PPR) → declared navigation → as-of timeline.

**Phase VI — the build family.** Ratchet → typed suppression → check-only →
dependency tracking → incremental → parallel. Strictly in that order:
*soundness before speed*, and parallelism is unsound before dependencies are
explicit.

**Phase VII — executable documentation.** `literalinclude` → doctest → doc
coverage. Last because it is the largest genuinely new capability and it needs
fence metadata from the AST.

## 4. Verification plan — per phase, with the tool named

| Phase | Primary tool | The law that gates the phase |
|---|---|---|
| I | OCaml types | the illegal does not compile |
| II | **smtml** + baseline | embed relation acyclic; patching one block leaves others byte-identical |
| III | types + suites | `\|resolve_typed(x)\| = 1`, 0 and >1 distinct |
| IV | **smtml** | `defends` monotone; lfp unique; ascent ≤ `\|args\|` steps |
| V | suites + route laws | `of_path ∘ to_path = Some`; no write verb |
| VI | **the ratchet itself** | `warnings(HEAD) ≤ warnings(HEAD~1)` |
| VII | doctest builder | documentation executes; skips disclosed |

**Every phase additionally re-runs the render differential**, which is the one
check that spans them all: if a change alters any pinned document's rendering,
it says so, and accepting that is a separate deliberate act.

**Every new law gets a mutation leg.** This session's evidence for why: three
mutants died immediately against the anchor work, and a fourth — conflating a
dead anchor with a dead link — *passed everything*, revealing that I had pinned
only one direction of a two-directional law. A law without a mutation leg is a
law nobody has confirmed works.

## 5. Where the design picks a specific upstream, and why

| Surface | Chosen | Over | Reason |
|---|---|---|---|
| Block carrier | Docusaurus mdast shape, **closed** constructors | Notion's open block tree | recursion lifts the ceiling; closure keeps `render` total |
| Callout syntax | Obsidian `> [!type]` | Docusaurus `:::type` | degrades to a readable blockquote; composes with the existing parser |
| Callout **nesting** | Docusaurus colon-count model | Obsidian `>`-stacking | depth in the delimiter is unambiguous |
| Query grammar | zigvm zkquery + Dataview's repeat-any-order rule | Bases `.base` YAML | a fence is reviewable in a diff and citable by wikilink |
| Query typing | **GADT** | runtime field/op checks | ill-typed conditions become unrepresentable |
| Navigation | Sphinx toctree + **Yuque node attributes** | either alone | `visible` hides without orphaning; `url` holds non-documents |
| Reference checking | Sphinx nitpicky + `:any:` ambiguity | Docusaurus link check alone | errors where the reader is harmed — the use site |
| Anchor validation | Docusaurus's **two predicates** | one combined check | different fixes ⟹ different diagnoses |
| Doc extraction | **static `.mli` parse** | Sphinx autodoc | the build must import nothing |
| Diagrams | server-side SVG | every comparator's client JS | CSP `default-src 'none'` holds |
| Canonical form | **markdown in git** | Lake / Notion blocks | the digest gate requires a canonical serialisation |

## 6. What this approach refuses, restated as engineering constraints

| Refusal | Constraint it preserves | Where enforced |
|---|---|---|
| no generative authoring or answer path | `⟦render⟧`, `⟦verdict⟧` are **functions** | absence of the code path |
| no imports at build time | determinism | `Doc_coverage` parses, never evaluates |
| no network in the render path | determinism | module types expose no IO |
| no plugin/card/MDX surface | totality of `render` | closed constructor sets |
| no stored derived values | derived cannot go stale | no such fields in the types |
| no second permission system | one access model | no user/role types exist |

Each refusal is visible in a **type or an absent module**, not only in prose —
which is the difference between a policy and a guarantee.

## 7. Honest bounds

- **Solver coverage is bounded-model, not general.** smtml discharges laws over
  *bounded* graphs, tag lattices and severity domains. That is real evidence and
  it is not a proof for all inputs; `Formal_coverage` records it as
  `Solver_proved` with the bound stated, never as `Machine_checked`.
- **Gospel is used on two interfaces**, not all of them. Extending it is cheap
  and is not scheduled here.
- **Quint is available and unused** in this design. The natural target is the
  build state machine of Phase VI (incremental/parallel), which is temporal in
  a way property tests are awkward for.
- **Four laws are under-verified** and named in `[[Unified functional algebra]]`
  §9 rather than left to be discovered.
- **Twelve laws are `Declared`** — all in doctest, ratchet and build, the three
  families not yet implemented. Each names the register row that closes it.
- **Emptiness is unprovable.** An absent arrow (S38) is never solver-provable —
  no encoding certifies that no code path exists; the visible seam plus the
  structure suite is the whole guarantee.
- **This is a plan, not a state.** `Feature_register` is authoritative for what
  is actually built; `test_feature_register` fails if this document and the
  system disagree.

Cross-references: `[[Unified feature set]]` · `[[Unified domain ontology]]` ·
`[[Unified functional atlas]]` · `[[Unified functional algebra]]` ·
`[[Meta-unification]]` · `docs/hermes/features-audit-implementation-plan.md`.

Part of [[Knowledge fractal map]].
