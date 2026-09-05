---
id: hermes-docusaurus-fractal-algebra
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Docusaurus — fractal algebra

#feature #src-docusaurus #area-algebra #cov-analysis

## 1. The content carrier — the initial algebra

- **Carrier** `mdast ≅ μX. Node(content) + List X` — the **initial algebra** of
  a polynomial functor
- **Operation** `render` as a **catamorphism** `cata : (F A → A) → μF → A`
- **Identity** the empty document
- **Absorbing** none
- **Laws**
  - *depth preservation*: `depth(parse s) = depth(s)` — no flattening
  - *catamorphism*: `render` is the unique F-algebra morphism out of `μF`, so
    it is compositional by construction

**HERMES.** `Wiki_ast` is now the same shape with a **closed** constructor set,
admitted by observational equivalence to the line-machine oracle over the whole
corpus. The `Loose of block` constructor is ours alone — it captures a quirk of
the oracle (a paragraph flushed inside an open list) that faithfulness required.

## 2. Slugging

- **Carrier** heading text → anchor
- **Operation** `Slugger.slug : String → State → (Anchor × State)` — a **state
  monad**, not a pure function
- **Identity** a fresh slugger per document
- **Absorbing** none
- **Laws**
  - *github-slugger semantics*: lowercase, spaces→hyphens, punctuation
    stripped, duplicates get `-1`, `-2`, …
  - *locality*: one slugger per document ⟹ `anchors(render_single d) =
    anchors(render_corpus d)`
  - *pigeonhole residual*: a generated `section-1` can claim the slug a later
    literal "Section 1" would own — a property of every suffix scheme, disclosed
    rather than fixed

**HERMES.** Identical, including the disclosed residual. `{#custom-id}`
(HW.3.2.3) adds the escape: a pinned id makes `anchor ∘ retitle = anchor`.

## 3. Link integrity — two predicates, not one

- **Carrier** `(links, anchors)` collected per rendered page
- **Operation** `isPathBrokenLink`, `isAnchorBrokenLink` — **separate**
- **Identity** a page with no links
- **Absorbing** any broken link under the build gate
- **Laws**
  - *completeness*: `anchors(p) = ids(render p)`
  - *distinct diagnosis*: `resolve(t) = Some p ∧ f ∉ anchors(p)` is a broken
    **anchor**, reported apart from a broken **path**, because the fixes differ
  - *encoding tolerance*: raw and percent-decoded fragments both accepted

**HERMES.** Landed as HW.3.4.2–3 this session, including percent-decoding and
the law that a fragment into a *missing* page is a dead link, **not** a dead
anchor — reporting it twice would make the two diagnoses agree about nothing.

## 4. Visibility — two independent axes

- **Carrier** `{draft, unlisted, listed}`
- **Operation** projection into the build and into the index
- **Identity** `listed`
- **Absorbing** `draft` (absent from the build entirely)
- **Laws** *mutual exclusion and totality*: exactly one holds ·
  `draft ⟹ ∉ build` · `unlisted ⟹ ∈ build ∧ ∉ index ∧ ∉ search`

**HERMES.** Our single `status` cannot express "published but not indexed" —
the normal state of most in-progress writing. HW.1.4.1.

## 5. Ordering and pagination

- **Carrier** sibling documents
- **Operation** `sidebar_position` as a total order, `pagination_next/prev` as
  an explicit successor relation
- **Laws** *totality and antisymmetry* of the order · *mutual inverse*:
  `next(a) = b ⟹ prev(b) = a` · *acyclicity*

**HERMES.** HW.1.3.11 and HW.1.3.14. The inverse law is the one that makes a
narrative path trustworthy.

## 6. MDX — the excluded algebra

- **Carrier** markdown with embedded JSX
- **Operation** compile to React components
- **Laws** none — arbitrary components execute

**HERMES — exclusion invariant.** `⟦render⟧` emits no executable content, so
"content cannot become markup" stays a *type-level* guarantee (TyXML) rather
than an escaping convention. Admitting MDX would remove the property that makes
the render differential meaningful.

Cross-references: `[[Docusaurus — fractal ontology]]` · `[[Docusaurus — fractal atlas]]` ·
`[[Unified fractal algebra]]`.

Part of [[Knowledge fractal map]].
