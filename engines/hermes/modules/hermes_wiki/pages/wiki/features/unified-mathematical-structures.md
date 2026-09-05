---
id: hermes-unified-mathematical-structures
status: published
type: reference
ktype: moc
maturity: incubating
domain: formal_verification
topics: [mathematics, lattices, theorems, serialisation]
created: 2026-08-09
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Unified mathematical structures

#feature #src-unified #area-algebra #cov-analysis

The formal catalogue: which mathematical object each layer actually **is**,
across all six systems. This is the load-bearing half of the unification —
`[[Unified fractal ontology]]` says what the entities are,
`[[Unified fractal algebra]]` gives carrier/operation/laws per family, and this
document names the structures and states what each one buys.

A structure is listed only where the laws genuinely hold, not where the analogy
is decorative. Where a tool violates a law, that is recorded — a violated law is
information.

## 1. The catalogue

| # | Structure | Where it appears | What it buys |
|---|---|---|---|
| 1 | **Initial algebra** `μX. F(X)` | mdast; `Wiki_ast`; Notion blocks | `render` is a **catamorphism** — compositional by construction, and depth is preserved |
| 2 | **Free monoid** | link path composition; version history; URL segments | associativity ⟹ order-independent concatenation; history append is total |
| 3 | **Merkle DAG** | git; the render baseline | history verifiable **without trusting the server**; a digest is a statement about content |
| 4 | **Transpose of a relation** | backlinks everywhere | `b ∈ back(a) ⟺ a ∈ out(b)` — derived, so it **cannot go stale** |
| 5 | **Partition (kernel of a map)** | `group by`; Notion grouping; communities | `a ~ b ⟺ f a = f b` ⟹ **disjoint and covering**, for free |
| 6 | **Galois connection / formal context** | tags ⇄ documents; nested tags; the index | faceted filtering is lattice **meet**; the concept lattice is derived, not declared |
| 7 | **Complete lattice + Knaster–Tarski** | grounded semantics (HW.4.4.1) | the least fixed point of a monotone operator **exists and is unique** — one answer to "which claims stand" |
| 8 | **Join-semilattice** | the parity lattice `Verified<Unmapped<Blocked<Divergent` | `combine = max` is associative, commutative, idempotent ⟹ **order-independent** verdict merge; *second pass:* the chain is **graded** (S37) with a per-site empty policy — the unit is a site declaration, not algebra — and carries a min-meet dual, the system floor |
| 9 | **Partial map monoid** | four-key resolver; intersphinx inventory chain | left-biased union is associative with the empty map as unit ⟹ resolution order is a **stated policy**, not an accident |
| 10 | **State monad** | the stateful heading slugger | duplicate anchors get suffixes deterministically; **locality** = one slugger per document |
| 11 | **Total order (with tiebreak)** | zkquery `sort`; sidebar_position | a **total** order ⟹ deterministic output ⟹ the result is **pinnable** by a digest |
| 12 | **Prefix / monotone order** | `limit n` ⊑ `limit m`; nested tags | `limit` is a **prefix**, so a bounded view never disagrees with an unbounded one |
| 13 | **Relational algebra** | Notion views; Dataview; Bases; zkquery | select/sort/group/limit **commute** where independent — one denotation, many renderings |
| 14 | **DAG + bounded unfolding** | transclusion; `include`; dependency tracking | acyclicity ⟹ termination; a reported bound ⟹ no silent truncation |
| 15 | **Homomorphism (non-invertible)** | Lake → markdown; blocks → markdown | a projection **loses** what the target cannot name — this is what "export" means |
| 16 | **Chain (total order)** | permissions `read ⊑ comment ⊑ edit` | inheritance down a containment tree is well-defined |
| 17 | **Closed sum type** | route ADT; `Wiki_ast.block`; discourse types | invalid states are **unrepresentable** — the only guarantee stronger than "enforced" |
| 18 | **Function vs relation** | render, verdict — with or without a model | a *function* can be differentiated, cached, replayed and pinned; a *relation* cannot |

## 2. The five structures that carry the harness

Of the eighteen, five are load-bearing here, in the sense that removing any one
breaks a guarantee we actually rely on.

**(1) Initial algebra.** `Wiki_ast` is `μX. Block(List X + List Inline)`. Being
initial is what makes `render` the *unique* F-algebra morphism out of the
carrier — so compositionality is not a coding convention but a theorem. Landed
this session (HW.2.0.1), admitted by observational equivalence to the
line-machine oracle over the whole corpus.

**(3) Merkle DAG.** The render baseline is `digest(render(parse d))` per
document. This is a statement about content **only because markdown has a
canonical serialisation**. §4 below is the proof obligation this rests on.

**(8) Join-semilattice.** The parity lattice with `combine = max`. Idempotent,
commutative, associative ⟹ merging verdicts in any order gives the same answer,
which is why evidence can be collected concurrently and combined later.

**(11) Total order.** Every ranking in the system carries a slug tiebreak.
Without it, sorting is a *preorder*, ties resolve by input order, and the output
stops being a function of the corpus — at which point the digest gate reports
drift that means nothing. `Wiki_query`'s determinism law is exactly this.

**(17) Closed sum type.** The route ADT has no write constructor and no `/` or
`.` in its slug alphabet, so a write verb and a path traversal are
*unrepresentable*. This is the fourth modal strength from the ontology §4, and
we reach it in exactly two places.

## 3. Structures the comparators have and we do not

| Structure | Whose | Ours to build |
|---|---|---|
| Galois connection over nested tags (6) | Obsidian | HW.4.1.7 — the antitone law becomes checkable |
| Partial map monoid across projects (9) | Sphinx intersphinx | HW.3.8.1–2 |
| Knaster–Tarski over an attack graph (7) | **nobody** | HW.4.4.1 — the deepest open item |
| Kernel-partition for aggregates (5) | Notion rollup | HW.4.6.3 |
| DAG + bounded unfolding (14) | Obsidian embeds, Sphinx include | HW.3.5.3 |

Structure 7 has no occupant anywhere in the survey. Grounded semantics over
`@supports`/`@opposes` would make anomalies **structural** — a claim with no
inbound support, a claim the least fixed point rules out — and it is computed,
so it cannot flatter us.

## 4. The central theorem of the unification

> **A differential gate requires a canonical serialisation.**

*Statement.* Let `C` be the canonical form and `σ : C → Bytes` its
serialisation. A digest gate compares `hash(σ(c))` across runs and reads
inequality as "the content changed".

*Requirement.* This is sound only if `σ` is **injective up to the equivalence
the gate cares about** — that is, if two byte-strings differ, the content
genuinely differs.

*Markdown.* `σ` is the identity: the canonical form **is** the bytes. Injective
trivially. A digest is therefore a statement about content.

*Lake / Notion blocks.* The canonical form is a structured tree with many valid
serialisations (key order, whitespace, id assignment, formatting metadata). `σ`
is not injective in the required direction — two serialisations of the *same*
document differ in bytes. A digest over it reports change that is not content
change, so the gate produces false drift and is abandoned.

*Corollary.* Yuque and Notion cannot have a render differential **for
structural reasons**, not for want of engineering. Obsidian, Docusaurus and
Sphinx can and do not. Hermes can and does.

*Consequence for us.* Any future move toward a richer canonical form must
first say **what replaces the render baseline**. This is recorded as an
importable *prohibition* in `[[Yuque — fractal algebra]]` §3 and restated here
because it is the one conclusion that constrains our roadmap.

*Demarcation (second pass).* S36 generalises the **gate** — pinned vs
recomputed, with a computed residue — as a reconciliation instance; the
canonical-serialisation requirement stays the primitive it rests on
(`[[Unified system synthesis]]` §14). Two passes converging on the same
bedrock is evidence it is bedrock.

## 5. The second theorem — why no model is in the path

> **`⟦render⟧` and `⟦verdict⟧` must be functions.**

Every law in the harness quantifies over inputs: determinism (`same input, same
output`), the differential (`digest is a function of content`), replay,
incremental-build soundness (`incremental = cold`), parity credit (`only L4–L6
differential evidence grants parity`).

A generative model in either path makes them **relations**: one input, many
admissible outputs. Every law above becomes unstatable — not false, *unstatable*,
because there is no unique output to quantify over.

So the exclusion of AI from the render and verdict paths is not a preference
about AI. It is what structure (18) requires, and it is why the nearest thing we
build instead — HW.6.3.5 — is a **deterministic** answer path with mandatory
citations: `answer : question → (text × citation list)` with `citations ≠ []`.
Fewer questions answered; the answers are evidence.

## 6. Structures deliberately not adopted

| Structure | Where | Why declined |
|---|---|---|
| Free monad over open block types | Notion, MDX, cards, plugins | unbounded constructors ⟹ `render` cannot be total |
| Per-row expression evaluation | Notion formulas, Yuque sheets | a document's meaning stops being a function of its bytes |
| CRDT / OT convergence | real-time co-editing | removes the commit, and the commit is the review unit |
| Hosted identity lattice | Notion, Yuque permissions | a second authorisation system that can disagree with the first |

Each is a coherent structure; each buys expressiveness by giving up a property
this harness needs.

Cross-references: `[[Unified fractal ontology]]` · `[[Unified fractal atlas]]` ·
`[[Unified fractal algebra]]` · `[[Meta-unification]]`.

Part of [[Knowledge fractal map]].
