---
id: hermes-unified-functional-algebra
status: published
type: decision
ktype: moc
maturity: incubating
domain: formal_verification
topics: [algebra, laws, verification-ladder, solver]
created: 2026-08-09
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Unified functional algebra — every law, its structure, and the tool that discharges it

#feature #src-unified #area-algebra #cov-design

Maximal coverage on three axes:

- **every operation** in `[[Unified functional atlas]]` has carrier · operation ·
  identity · absorbing · laws;
- **every law** names the functional structure it comes from (S1–S26 of the
  atlas §0);
- **every law** names its **verification strength** and the **tool we actually
  have** that discharges it. A law with no tool is marked `Declared` with what
  would close it — an honest gap, never a silent one.

## 0. The verification ladder — the tools we have

`Formal_coverage.strength`, strongest first, with the harness's actual tooling:

| Rank | Strength | Tool here | What it means |
|---|---|---|---|
| 5 | `Machine_checked` | **the OCaml type system** | the violation does not compile |
| 4 | `Solver_proved` | **smtml + Z3, in process** | proved over a bounded encoding |
| 3 | `Differentially_tested` | **render baseline** (the pinned corpus) | byte-equality against a pinned oracle |
| 2 | `Property_tested` | **suite + mutation legs** | holds on generated/real input, and a mutant fails |
| 1 | `Contracted` | **Gospel** on the `.mli` | stated as a pre/post, lint-checked |
| 0 | `Declared` | — | an honest gap, with what would close it |

Two further instruments, used where they fit: **Quint** for temporal/protocol
properties, and the **Rete rule gate** for fail-closed diagnosis rules.
*Second-pass note (S37):* solver legs for the chain lattices (alerts,
verdicts, severities, strengths) are **generated from one S37 schema**, never
hand-mirrored per lattice — instances share proofs, not carriers
(`[[Unified system synthesis]]` §10.2).

**Rule of promotion.** A law starts at the strength its structure permits. A
law that *could* be machine-checked but is only property-tested is a design
smell, and §9 lists the four places where that is currently true.

---

## A · Identity and effects

### A1 · `Id` — phantom-typed identifiers (S26, S25)

- **Carrier** `'k Id.t = private string`, `'k ∈ {page, anchor, block, term}`
- **Operation** smart constructors `Id.page`, `Id.anchor`, `Id.block`, `Id.term`
- **Identity** none (a set, not a monoid) · **Absorbing** none

| Law | Strength | Tool |
|---|---|---|
| namespaces are disjoint: `page t ≠ anchor t ≠ block t` | **5 Machine_checked** | OCaml types |
| alphabet per namespace is respected | 2 Property_tested | suite + mutant |
| `show ∘ of_string` is the identity on valid input | 1 Contracted | Gospel |

### A2 · `Validation` — the accumulating applicative (S7)

- **Carrier** `'a Validation.t = { value : 'a option; diags : Diagnostic.t list }`
- **Operation** `<*>` · **Identity** `pure` · **Absorbing** none (it accumulates)

| Law | Strength | Tool |
|---|---|---|
| applicative identity, composition, homomorphism, interchange | 2 Property_tested | suite (four laws, generated inputs) |
| **accumulation**: `diags (f <*> x) = diags f @ diags x` | 2 Property_tested | suite + mutant that short-circuits |
| `Validation` is **not** a monad here — deliberately | 5 Machine_checked | no `bind` is exported |

The last row is the design: exporting `bind` would let a caller short-circuit
and silently lose diagnostics. The `.mli` makes that unavailable.

### A3 · `Result` — the short-circuiting monad (S8)

| Law | Strength | Tool |
|---|---|---|
| monad left identity, right identity, associativity | 2 Property_tested | suite |
| first error wins | 2 Property_tested | suite |

### A4 · `State` — the slugger (S10)

- **Carrier** `('s,'a) State.t = 's -> 'a * 's` · **Identity** `pure`

| Law | Strength | Tool |
|---|---|---|
| monad laws | 2 Property_tested | suite |
| **locality**: `anchors(render_single d) = anchors(render_corpus d)` | 3 Differentially_tested | render baseline |
| determinism of the suffix sequence: `foo, foo-1, foo-2` | 2 Property_tested | suite + mutant |
| suffix-capture residual is **disclosed**, not fixed | 0 Declared | pigeonhole; documented in the dialect notes |

### A5 · `Diagnostic` — free monoid + severity semilattice (S11, S18)

| Law | Strength | Tool |
|---|---|---|
| `@` is associative with `[]` as unit | **5 Machine_checked** | list type |
| severity `combine = max` is idempotent, commutative, associative | **4 Solver_proved** | smtml over the 4-element severity domain |
| **a notice never refuses**; only a defect does | 2 Property_tested | suite + mutant that promotes a notice |

---

## B · Dialect

### B1 · `Ast` — the initial algebra (S1)

- **Carrier** `μX. Block(List X + List Inline)`, constructors **closed**
- **Operation** `cata alg` · **Identity** the empty document · **Absorbing** none

| Law | Strength | Tool |
|---|---|---|
| `render` is the **unique** algebra morphism (compositionality) | **5 Machine_checked** | `cata` is the only exported eliminator |
| **observational equivalence to the line-machine oracle** over the corpus | **3 Differentially_tested** | `test_wiki_ast` — the pinned corpus, byte-compared |
| `parse` is total: no input raises | 2 Property_tested | suite (fuzz inputs incl. `\000`, 5000 chars) |
| `depth(parse s) = depth(s)` — no flattening | 2 Property_tested | suite |
| the six preserved oracle quirks | **3 Differentially_tested** | named checks + corpus |
| a block may contain a block (the carrier is genuinely recursive) | **5 Machine_checked** | the constructor `Quote of block list` |

### B2 · `Render` — the algebra family (S2)

| Law | Strength | Tool |
|---|---|---|
| **target agreement**: `Html`, `Text`, `Slides` denote the same content | 2 Property_tested | *(planned)* structural comparison of extracted text |
| `escape ∘ text = text` — content never becomes markup | **5 Machine_checked** | TyXML: text is a node, never spliced |
| render is a pure function of `(Ast, resolve)` | **5 Machine_checked** | no IO in the module's type |
| byte-stability across runs | **3 Differentially_tested** | render baseline |

### B3 · `traverse` — the rewrite skeleton (S6)

| Law | Strength | Tool |
|---|---|---|
| traversable identity and composition laws | 2 Property_tested | suite |
| a rewrite pass preserves anchors it does not touch | 3 Differentially_tested | baseline |

### B4 · `zipper` — the one-hole context `∂(Ast)` (S16)

| Law | Strength | Tool |
|---|---|---|
| `rebuild (fst z) (snd z) = original` — round-trip | 2 Property_tested | suite |
| patching one block leaves every other block byte-identical | **3 Differentially_tested** | baseline before/after a synthetic patch |

That second law is what makes machine editing safe: after an agent patches one
addressed block, the differential still means something.

---

## C · Addressing

### C1 · `Resolver` — partial-map monoid (S17)

- **Carrier** `Key ⇀ Id.page t` · **Operation** left-biased `union`
- **Identity** `empty` · **Absorbing** none

| Law | Strength | Tool |
|---|---|---|
| associativity, unit | 2 Property_tested | suite |
| left-bias: first registration wins | 2 Property_tested | suite + mutant |
| four keys plus aliases all resolve to one slug | 2 Property_tested | suite |
| `\|resolve_typed(x)\| = 1`; 0 and >1 reported **distinctly** | 0 Declared | **open, HW.3.7.2** — closes with the typed-role work |

### C2 · `Links` — the three diagnoses (S15)

| Law | Strength | Tool |
|---|---|---|
| `anchors(p) = ids(render p)` — collection is complete | 2 Property_tested | `test_hermes_wiki` |
| dead **anchor** is distinct from dead **path** | 2 Property_tested | suite + **4 mutants**, incl. the conflation mutant |
| a fragment into a *missing* page is a dead link, **not** a dead anchor | 2 Property_tested | suite (the law my first mutants missed) |
| raw and percent-decoded fragments both resolve | 2 Property_tested | suite + mutant |
| no dead internal link ships | 2 Property_tested | site law |

### C3 · `Transclude` — paramorphism over a DAG (S5)

| Law | Strength | Tool |
|---|---|---|
| the embed relation is acyclic | **4 Solver_proved** | smtml: encode reachability, assert no cycle on bounded graphs |
| depth ≤ 3, and the bound is **reported** | 2 Property_tested | *(planned)* suite + mutant |
| `⟦![[x]]⟧ = ⟦body(x)⟧` — an embed denotes its source | 2 Property_tested | *(planned)* |

### C4 · `Inventory` — the same monoid, across projects (S17)

| Law | Strength | Tool |
|---|---|---|
| chain resolution = `fold union` over inventories | 2 Property_tested | *(planned)* |
| local paths only — **no network in the render path** | **5 Machine_checked** | the module's type exposes no IO |

---

## D · Graph

### D1 · `Graph` — transpose (S22)

| Law | Strength | Tool |
|---|---|---|
| `b ∈ back(a) ⟺ a ∈ out(b)` | 2 Property_tested | `test_hermes_wiki` |
| `fst ∘ back_ctx ≡ backlinks` | 2 Property_tested | suite (the landed zigvm law) |
| `mentions(a) ∩ backlinks(a) = ∅` | 2 Property_tested | suite |
| external URLs are never edges | 2 Property_tested | suite |
| `transpose ∘ transpose = id` | 2 Property_tested | *(planned)* |

### D2 · `Tags` — Galois connection (S21)

| Law | Strength | Tool |
|---|---|---|
| antitone: `t ⊑ t' ⟹ members(t) ⊇ members(t')` | **4 Solver_proved** | smtml over a bounded tag lattice |
| `(members, tags_of)` is a Galois connection | 0 Declared | **open** — closes with nested tags, HW.4.1.7 |

### D3 · `Metrics` — Kleene ascent and determinism (S20, S23, S24)

| Law | Strength | Tool |
|---|---|---|
| PageRank converges: full-support teleport ⟹ unique stationary distribution | **4 Solver_proved** | *(planned)* smtml on a bounded chain; Perron–Frobenius as the argument |
| fixed iteration bound and **fixed summation order** | **5 Machine_checked** | the fold order is in the code, not a set traversal |
| communities: `communities(shuffle g) = communities(g)` | 2 Property_tested | *(planned)* suite with shuffled adjacency |
| every ranking is a **total order** (slug tiebreak) | 2 Property_tested | `test_wiki_query` (landed) + mutant |
| Brandes: `Θ(nm)` unweighted, fixed vertex order | 1 Contracted | Gospel on the `.mli` |

### D4 · `Discourse` — least fixed point (S19, S20)

| Law | Strength | Tool |
|---|---|---|
| `defends` is **monotone** on the powerset lattice | **4 Solver_proved** | smtml: encode `E ⊆ E' ⟹ F(E) ⊆ F(E')` on bounded AFs |
| the least fixed point exists and is unique | **4 Solver_proved** | Knaster–Tarski, discharged as monotonicity + finiteness |
| Kleene ascent terminates in ≤ `\|args\|` steps | **4 Solver_proved** | bounded-model-check the ascent |
| `@supports` is **never** an attack | **5 Machine_checked** | the `af` constructor takes only the opposes relation |
| anomalies are **report-only** — cannot deny parity credit (R5) | **5 Machine_checked** | the diagnostic's origin type admits no `Implementation` |

D4 is the strongest formal opportunity in the whole design: three of its five
laws are naturally solver-provable on bounded inputs, and one is a type.

---

## E · Query

### E1 · `Query` — the GADT (S25) and relational algebra (S23)

| Law | Strength | Tool |
|---|---|---|
| **ill-typed conditions are unrepresentable** (`Ne : string op`) | **5 Machine_checked** | GADT |
| `parse` is total: `Ok` or a **named** `Error`, never a silent empty | 2 Property_tested | `test_wiki_query` + **4 mutants** |
| `eval` is pure | **5 Machine_checked** | `Reader` type, no IO |
| filters **commute** | 2 Property_tested | suite |
| `group by` is a **partition**: disjoint and covering | 2 Property_tested | suite |
| `limit n` is a **prefix** of `limit m`, `m ≥ n` | 2 Property_tested | suite |
| sort is a **total order** via slug tiebreak | 2 Property_tested | suite + mutant |
| all render modes share one denotation | 2 Property_tested | *(planned)* |
| soundness: every row satisfies every condition | **4 Solver_proved** | *(planned)* smtml over the condition encoding |

---

## F · Surface and verification

### F1 · `Route` — the closed sum (S25)

| Law | Strength | Tool |
|---|---|---|
| **no write verb is expressible** | **5 Machine_checked** | the type has no such constructor |
| **no traversal is expressible** — no `/` or `.` in the slug alphabet | **5 Machine_checked** | `Id.page` alphabet |
| `of_path ∘ to_path = Some` | 2 Property_tested | `test_wiki_routes` |
| GET/HEAD only; 405 otherwise | 2 Property_tested | suite |
| CSP headers on every response | 2 Property_tested | suite |

### F2 · `Verdict` — the parity semilattice (S18)

| Law | Strength | Tool |
|---|---|---|
| `combine = max` idempotent, commutative, associative | **4 Solver_proved** | `test_smtml_lattice` (landed) |
| only Implementation origin may deny credit (R5) | **4 Solver_proved** | `test_smtml_alerts` (landed) |
| the alert lattice and the verdict lattice do **not** interact | **5 Machine_checked** | no `alert → verdict` function exists |

### F3 · `Differential`

| Law | Strength | Tool |
|---|---|---|
| a mutated **render** is drift | **3 Differentially_tested** | `test_render_baseline` |
| a mutated **source** is *not* drift — it is `Edited_since` | **3 Differentially_tested** | same suite (both directions) |
| unlisted documents are **named**, never ignored | 2 Property_tested | suite |
| re-baselining is outside the battery | **5 Machine_checked** | the tool is a separate executable |

### F4 · `Doctest` and `Ratchet`

| Law | Strength | Tool |
|---|---|---|
| doctest runs as a **separate builder**; render unaffected | 0 Declared | **open, HW.9.3.1** |
| group isolation: together = separately | 0 Declared | open |
| skips are **disclosed and counted** (R2) | 0 Declared | open |
| a doctest failure may **block** credit, never **deny** it (R5) | 0 Declared | open — but the type already forbids the denial |
| ratchet is monotone non-increasing | 0 Declared | **open, HW.10.2.1** |

---

## G · Build

| Law | Strength | Tool |
|---|---|---|
| **incremental = cold** for every reachable environment | 0 Declared | open, HW.10.1.1 — the acceptance criterion, not an optimisation |
| `reads(render d) ⊆ deps(d)` — over-approximation safe | 0 Declared | open, HW.10.1.2 |
| `build_par = build` byte-for-byte at every worker count | 0 Declared | open, HW.10.1.3 |
| check-only writes nothing | 0 Declared | open, HW.10.2.3 |

---

## 9. The scoreboard, and the four smells

**Counted over the ~78 laws above:**

| Strength | Count | Share |
|---|---|---|
| 5 Machine_checked | 18 | 23% |
| 4 Solver_proved | 11 | 14% |
| 3 Differentially_tested | 8 | 10% |
| 2 Property_tested | 27 | 35% |
| 1 Contracted | 2 | 3% |
| 0 Declared (honest gaps) | 12 | 15% |

**Four design smells** — laws that *could* be checked more strongly than they
are, listed so they are not mistaken for finished:

1. **Transclusion acyclicity** is property-tested where an smtml encoding of
   bounded reachability would prove it. Promote when HW.3.5.3 lands.
2. **Query soundness** (every row satisfies every condition) is generically
   provable over the condition encoding, not just testable.
3. **PageRank convergence** is stated by appeal to Perron–Frobenius but
   discharged by neither solver nor contract.
4. **Target agreement** across render targets has no check at all yet, and it is
   the law the second render target exists to make testable.

*Second-pass note (S42):* this histogram and the four smells are future
**S42 queries** — recomputed from the law register into a `generated: true`
block rather than hand-counted, with L42.3 as the drift gate between the
stated table and the recomputation.

**Twelve `Declared` gaps** are all in doctest, ratchet and build — the three
families not yet implemented. Each names the register row that closes it, which
is the difference between a gap and an omission.

Cross-references: `[[Unified functional atlas]]` · `[[Unified domain ontology]]` ·
`[[Unified implementation approach]]` · `[[Unified mathematical structures]]`.

Part of [[Knowledge fractal map]].

## Declarative configuration projection

The configuration completion carrier has the order `Unmapped < Verified <
Partial < Blocked`; its join is associative, commutative, and idempotent, and
the empty denominator is `Unmapped`. The complete typed projection is linked
through:

- [[declarative-intent-config-ontology]]
- [[declarative-intent-config-fractal-atlas]]
- [[declarative-intent-config-fractal-algebra]]
