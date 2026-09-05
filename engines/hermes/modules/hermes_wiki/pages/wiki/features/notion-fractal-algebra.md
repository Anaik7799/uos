---
id: hermes-notion-fractal-algebra
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Notion — fractal algebra

#feature #src-notion #area-algebra #cov-analysis

## 1. Blocks

- **Carrier** `Block ::= Leaf(content) | Node(content, Block list)` — the free
  monad shape; unbounded depth
- **Operation** `insert : Block → Block → position → Block`
- **Identity** the empty block list
- **Absorbing** none
- **Laws** *containment is a tree* (single parent, acyclic) · *page ≡ block*, so
  every page operation is a block operation

**HERMES.** `Wiki_ast.block` is the same recursive shape with a **closed**
constructor set. Theirs is open and unbounded; ours is closed so that `render`
is total and the dialect is reviewable.

## 2. Databases and views — relational algebra

- **Carrier** collections of pages with a shared property schema
- **Operation** `view = render_mode ∘ limit ∘ group ∘ sort ∘ filter`
- **Identity** the unfiltered, unsorted, ungrouped collection
- **Absorbing** a filter matching nothing (the empty view)
- **Laws**
  - *filters commute*: `filter a ∘ filter b = filter b ∘ filter a`
  - *group by is the kernel of a property*: `a ~ b ⟺ prop(a) = prop(b)` — a
    partition, hence disjoint and covering
  - *views share one denotation*: every view of a query shows the same rows

**HERMES.** `Wiki_query` proves the same three laws (commute, partition,
one denotation across render modes) as executable checks. Notion's are implied
by the implementation; ours are `test_wiki_query`.

## 3. Relations and rollups

- **Carrier** typed edges between rows
- **Operation** `relate : row → row → edge`, `rollup : relation → fold → value`
- **Identity** the empty relation
- **Absorbing** none
- **Laws** *symmetry*: `relate(a,b) ⟹ relate(b,a)` is maintained automatically ·
  *rollup is a fold*: `count`, `sum`, `percent` are monoid homomorphisms over
  the far side, so the aggregate is order-independent

**HERMES.** Typed edges `[[T|@rel]]` render both directions (HW.4.1.5); rollup
is HW.4.6.3 and inherits the same order-independence requirement.

## 4. Formulas — the excluded algebra

- **Carrier** expressions over row properties
- **Operation** evaluation per row
- **Laws** none stated; a formula may reference other formulas

**HERMES — exclusion invariant.** `⟦render d⟧` is a pure function of `d` and
the corpus, with no per-note computation. The cost of admitting formulas is
that a document's meaning stops being a function of its bytes.

## 5. AI blocks — the excluded algebra

- **Carrier** prompt × context → content
- **Laws** none — generation is not required to be deterministic or citing

**HERMES — exclusion invariant** (stated once for all five comparators): the
verdict path requires `⟦render⟧` and `⟦verdict⟧` to be **functions**. A model
makes them relations, and every downstream law is stated over functions.

## 6. Permissions and versions

- Permission: a chain `view ⊑ comment ⊑ edit ⊑ full`, per principal per page,
  **inherited down the block tree** — so the containment tree and the
  permission lattice are the same order.
- Versions: a free monoid on edits; restore appends.

**HERMES.** Permission is degenerate (repo access + R15 reachability); versions
are git's content-addressed Merkle DAG, which is strictly stronger than a
version list because history is verifiable without trusting the server.

Cross-references: `[[Notion — fractal ontology]]` · `[[Notion — fractal atlas]]` ·
`[[Unified fractal algebra]]`.

Part of [[Knowledge fractal map]].
