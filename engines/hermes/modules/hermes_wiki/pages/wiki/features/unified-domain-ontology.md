---
id: hermes-unified-domain-ontology
status: published
type: decision
ktype: moc
maturity: incubating
domain: formal_verification
topics: [ontology, entities, relations, invariants]
created: 2026-08-09
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Unified domain ontology — the entity model we build to

#feature #src-unified #area-ontology #cov-design

The **normative** ontology: not "what do the six systems have" (that is
`[[Unified fractal ontology]]`) but "what entities does the unified design
declare, with what modal strength". Every entity here has an OCaml type in
`[[Unified implementation approach]]`.

## 0. Modal strength is part of every declaration

From the analytical ontology §4, and used here as a required field: an entity
or relation is declared at exactly one strength, and the strength is the design.

| Strength | Meaning | Enforcement |
|---|---|---|
| **derived** | computed; cannot go stale | a function, plus a law |
| **declared** | authored and believed | a frontmatter field |
| **enforced** | the system refuses violating states | a gate diagnostic |
| **type-level** | violating states are unrepresentable | the OCaml type |

Preference order when a choice exists: **type-level > derived > enforced >
declared.** Derived outranks enforced because a derived value needs no gate at
all; declared is last because it is the only one that can silently be wrong.
*Second-pass addendum:* the order now has an **executable form** — S36's
`status`/`residue` (`[[Unified system synthesis]]` §13): the probe outranks
the declaration by construction, and their difference is a computed residue.

## 1. Entities

| # | Entity | Strength | Structure | Carrier | Notes |
|---|---|---|---|---|---|
| E1 | **Corpus** | derived | **Store comonad** (S12) — a corpus focused at a page | `git ls-files` over declared roots | membership reviewable in a diff |
| E2 | **Document** | derived | element of the comonad's carrier | a tracked `.md` file | unit of authorship and version |
| E3 | **Slug** | derived | **phantom-typed** `Id.page t` (S26) | `slugify(basename)`, group-qualified | `slug ∘ move_dir = slug` |
| E4 | **Stable id** | declared, else derived | option, with a derivation as default | frontmatter `id` | survives rename |
| E5 | **Alias** | declared | summand of the **partial-map monoid** (S17) | frontmatter `aliases` | extra resolver keys |
| E6 | **Group** | derived | a fibre of `group : Doc → String` — its **kernel** (S23) | parent directory basename | descriptive, deliberately not a constraint |
| E7 | **Visibility** | declared | **closed sum** (S25); a 3-element poset by exposure | `draft` \| `unlisted` \| `listed` | mutually exclusive and total |
| E8 | **Discourse type** | declared | closed sum **+ an `Unknown` escape** (honest, not total) | note·question·claim·evidence·decision·reference | classifies the *claim* |
| E9 | **Currency** | declared + derived | a **lens** (S13) into `Meta`, plus a derived predicate | stamps → overdue | decay computed, never stored |
| E10 | **Block** | derived | **initial algebra of a polynomial functor** (S1) | `μX. Block(List X + List Inline)`, closed | recursive; landed |
| E11 | **Heading anchor** | derived, overridable | **State monad** (S10), one run per document | stateful slugger; `{#id}` pins | locality is the law |
| E12 | **Block anchor** | declared | phantom type (S26) + **zipper focus** `∂(Ast)` (S16) | ` ^id`, `[A-Za-z0-9-]`, retains `^` | disjoint from E11 by construction |
| E13 | **Link** | derived | edge of a **directed multigraph** (S22) | `[[target]]`, relative `.md` | resolved or visibly missing |
| E14 | **Fragment reference** | derived | a **dependent pair** `(p : page) × anchor(p)` in spirit | `(target, anchor)` | validated separately from E13 |
| E15 | **Typed edge** | declared | **labelled** edge; the `opposes` label is the attack relation of an AF | `[[T\|@rel]]` | substrate for S19 |
| E16 | **Tag** | declared | **Galois connection** with documents (S21); prefix **free monoid** | `#a/b/c` | antitone into members |
| E17 | **Nav node** | declared | **rose tree**: free monad over a finite branching functor, used first-order | `{doc` \| `url; visible; children}` | Yuque attributes on a Sphinx tree |
| E18 | **Query** | declared | **GADT** — the typing rule lives in the type (S25) | zkquery AST | a query is a document |
| E19 | **Term** | declared | phantom-typed key into a partial map (S17, S26) | glossary entry | undefined use ⟹ diagnostic |
| E20 | **Inventory entry** | derived | element of the **partial-map monoid** (S17), chained by fold | `name ⇀ uri` | published and consumed |
| E21 | **Test block** | declared | member of a group; groups **partition** blocks (S23) | doctest member | executable documentation |
| E22 | **Diagnostic** | derived | **free monoid** under `@` (S11); severity is a **join-semilattice** (S18) | level, origin, severity | defect refuses, notice reports |
| E23 | **Digest** | derived | function into a discrete set; **not** a homomorphism — see §4 | `sha256(render(parse d))` | the gate's witness |

Twenty-three entities; **fourteen derived**, seven declared, two mixed. That
ratio is the design: most of what the system knows is computed, so most of what
it knows cannot be stale.

## 2. Relations

| # | Relation | Strength | Structure | Law |
|---|---|---|---|---|
| R1 | corpus ∋ document | derived | indexed family | membership = tracked |
| R2 | document → slug | derived | injection into `Id.page t` (S26) | injective; collisions reported |
| R3 | document → group | derived | **kernel** of `group` (S23) | `group ∘ reroot = group` |
| R4 | key ⇀ slug | derived | **partial-map monoid**, left-biased (S17) | four keys + aliases; first registration wins |
| R5 | document → blocks | derived | **hylomorphism** (S4) | `parse`, total |
| R6 | block → anchors | derived | **catamorphism** (S2) | `anchors(p) = ids(render p)` |
| R7 | document → outlinks | derived | **optic traversal** (S15) | external URLs excluded |
| R8 | **outlinks → backlinks** | derived | **relation transpose** (S22) | `b ∈ back(a) ⟺ a ∈ out(b)` |
| R9 | backlinks → citing line | derived | transpose with a witness | `fst ∘ back_ctx ≡ backlinks` |
| R10 | title → mentions | derived | set complement over the transpose | `mentions ∩ backlinks = ∅` |
| R11 | fragment ref → anchor | **enforced** | dependent-pair check | unresolved ⟹ diagnostic, distinct from R7 |
| R12 | reference → kind | **type-level** | indexed partial map (S25) | `Kind × Name ⇀ Target` |
| R13 | embed → target | **enforced** | **paramorphism** over a DAG (S5) | acyclic, depth ≤ 3, bound reported |
| R14 | tag ⊑ tag | derived | **Galois connection**, antitone (S21) | prefix order; `members` antitone |
| R15 | nav node → document | declared | rose tree | unreachable ⟹ diagnostic unless orphan |
| R16 | query → rows | derived | **Reader** (S9) + total order (S24) | pure; slug tiebreak |
| R17 | edge set → grounded extension | derived | **lfp, Knaster–Tarski + Kleene** (S19, S20) | least fixed point of `F_AF` |
| R18 | document → digest | derived | function into a discrete set | the differential |
| R19 | route → response | **type-level** | **closed sum** (S25) | no write verb; no traversal |
| R20 | test block → group | declared | **partition** (S23) | isolation across groups |
| R21 | corpus → per-page view | derived | **Store comonad `extend`** (S12) | one pass computes every page's derived view |
| R22 | diagnostics | derived | **free monoid** (S11) + **join-semilattice** on severity (S18) | collection is order-independent; severity merges by max |
| R23 | verdicts | derived | **join-semilattice** (S18) | `combine = max`: idempotent, commutative, associative |

## 2b. The categorical reading

The ontology is not a loose collection of types; the entities and relations
form a small category, and three constructions in it do real work.

**Objects and arrows.** Objects are the carriers (`Corpus`, `Document`, `Ast`,
`Graph`, `Query`, `Diagnostic`, `Digest`); arrows are the derived functions of
§2. Composition is function composition, and the identity arrow on `Document`
is the reason `slug ∘ move_dir = slug` is stateable at all.

**The three functors that matter.**

| Functor | From → to | Preserves | Used for |
|---|---|---|---|
| `parse` | source bytes → `Ast` | structure, not bytes | R5 |
| `render_T` | `Ast` → target `T` | denotation across targets | R6, and the second-render-target law |
| `Graph.of_corpus` | `Corpus` → `Graph` | edges, dropping content | R7–R10 |

`render_T` is an **F-algebra morphism**, so the family `{Html, Text, Slides}`
is a family of algebras over one carrier — which is exactly why adding a target
cannot change what a document *means*.

**The adjunction we deliberately do not have.** A rich canonical form would
give a free⊣forgetful pair between structured documents and text. We refuse it
because the forgetful direction is lossy (`[[Unified mathematical structures]]`
§4), and with it goes the digest. Recording the refusal is the point: it is a
structure a reader would expect to find, and its absence is load-bearing.
*Co-presentation (second pass, S38):* the refusal generalises — every
load-bearing absence (this adjunction; `alert → verdict`; telemetry back into
any verdict; auditor writes into the corpus) is a catalogue row of
`Absent_arrow.absences`: the category is presented by its arrows **and its
named non-arrows**, which turns "we do not have that arrow" from an oversight
into a checkable claim.

**Fixed points, twice.** `Discourse.grounded` is a least fixed point on the
powerset lattice (S19, unique by Knaster–Tarski, computed by Kleene ascent
S20). `Metrics.pagerank` is a fixed point of an affine map on ℝⁿ, unique by
Perron–Frobenius when the teleport vector has full support. Both are *computed*
with stated bounds, never iterated to convergence-by-hope.

**Two monoid actions.** `Slugger` is a state monad, which is the action of the
free monoid of heading texts on the anchor-set; `Resolver` union is a monoid
action of key-sets on lookup. Both are associative, and both associativities
are checkable properties rather than comments.

## 3. The five invariants that define the model

Stated as the things a reviewer should check any change against.

**I1 — Identity survives movement.** `slug ∘ move_dir = slug`. Consequence:
containment can never be a constraint (E6 is descriptive). This is the trade
against Yuque, taken deliberately.

**I2 — Anchors are namespaced by construction.** Generated anchors (E11) and
pinned block ids (E12) cannot collide because the latter retain `^`. No gate
needed — the alphabets differ.

**I3 — Derived values are never stored.** Backlinks, mentions, rows, rankings,
digests. Anything stored can disagree with its source; anything derived cannot.

**I4 — Every reference resolves or is diagnosed.** Three distinct diagnoses,
because three distinct fixes: dead document (R7), dead anchor (R11), ambiguous
reference (R12). Reporting them together would make them useless.

**I5 — The canonical form is bytes.** E23 exists only because E2 is a file. Any
proposal that enriches the canonical form must first say what replaces the
differential.

## 4. What this ontology deliberately does not declare

| Not declared | Why |
|---|---|
| User, membership, permission | repo access + R15 is the model; a second one could disagree |
| Document kind (doc/board/sheet) | one storage kind; E8 classifies the claim instead |
| Draft *body* | E7 is a visibility state over one body — no merge story needed |
| Stored rows, stored backlinks | I3 |
| Card / plugin / component | totality of render |
| Model, prompt, generation | P2 — render and verdict must be functions |

## 5. Mapping to the register

Every entity and relation above corresponds to `HW.*` rows. The ontology is the
*shape*; the register is the *state*. Where they disagree, the register is
authoritative because it is executable — `Feature_register.status` prefers a
live probe over a declaration, and `test_feature_register` fails on
disagreement.

Cross-references: `[[Unified feature set]]` · `[[Unified functional atlas]]` ·
`[[Unified functional algebra]]` · `[[Unified implementation approach]]`.

Part of [[Knowledge fractal map]].
