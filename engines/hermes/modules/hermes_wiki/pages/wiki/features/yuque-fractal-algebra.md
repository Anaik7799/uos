---
id: hermes-yuque-fractal-algebra
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Yuque — fractal algebra

#feature #src-yuque #area-algebra #cov-analysis

Carrier · operation · identity · absorbing · laws, per feature family — the
same shape `Fractal_ontology.algebra` uses for our own components, so the two
can be compared without translation. Entities in
`[[Yuque — fractal ontology]]`; maps in `[[Yuque — fractal atlas]]`.

Laws are stated as they must hold **for Yuque**; a `HERMES` line follows where
our answer differs, because the difference is usually the interesting part.

## 1. Containment (Y0–Y1)

- **Carrier** documents, knowledge bases, spaces
- **Operation** `place : doc → base → doc` (assign to a container)
- **Identity** none — there is no "no base", and that absence is the feature
- **Absorbing** none
- **Laws**
  - *totality*: `∀d. ∃!b. contains(b, d)` — every document has exactly one
    base. The only enforced structural constraint in the whole survey.
  - *scope inheritance*: permission, publication and search scope are
    properties of `b`, inherited by `d`.
  - *exemption*: `小记` quick notes are outside the carrier. A total rule with
    a named escape hatch, rather than a rule with exceptions.

**HERMES.** Our `group` is `basename ∘ parent ∘ path` — a *derivation*, so the
law is `group ∘ move_dir ≠ group` (it changes) while `slug ∘ move_dir = slug`
(identity is preserved). We chose stable identity over stable containment;
Yuque chose the reverse. Both are defensible; only one of them can be a
constraint.

## 2. Navigation (Y2)

- **Carrier** TOC nodes over a base
- **Operation** `attach : node → parent → tree`
- **Identity** the root node
- **Absorbing** none
- **Laws**
  - *tree*: single root, acyclic, every document positioned exactly once.
  - *visibility is presentational*: `visible = false` removes a node from the
    sidebar **without** removing it from the tree — so hiding never orphans.
  - *nodes need not be documents*: a `url` node points outside the base, and
    `open_window` is a rendering hint on it.

**HERMES.** No TOC carrier exists today. HW.6.8.1 would add one; this algebra
argues it should carry `visible` and `url` from the outset, because retrofitting
a node attribute after the tree has authored content is a migration.

## 3. Format and projection — the load-bearing one

- **Carrier** document bodies: `Lake`, `Markdown`, `Html`
- **Operation** `project : Lake → Format → Body`
- **Identity** `Lake` under the identity projection
- **Absorbing** none
- **Laws**
  - *canonicity*: `Lake` is authoritative; every other body is a function of
    it. Two readers of the same document cannot disagree.
  - *projection is a homomorphism only in the structure it can express*:
    `project(markdown)` preserves what markdown can carry and **discards the
    rest**. Formally `project_md` has no left inverse — `parse_md ∘ project_md
    ≠ id` on Lake, because the constructs markdown cannot name are gone.
  - *draft independence*: `bodyDraftLake` and `bodyLake` are separate carriers;
    editing one does not change the other until `publish`.

**HERMES — the inversion, stated precisely.** Our canonical form is markdown,
so:

```
their world:   Lake  ──project──▶  markdown        (lossy, no inverse)
our world:     markdown ──parse──▶ AST ──render──▶ HTML   (lossy the OTHER way)
```

Both pipelines lose information; the question is *what survives in the form you
review*. Ours survives in the diff, which is why `digest(render(parse d))` is a
meaningful gate and `digest(Lake)` would not be — a rich structured form has
many byte representations of one document, so a digest over it is not a
statement about content.

That is the formal reason the render baseline and Lake are incompatible, and
it is worth stating once rather than re-deciding: **a differential gate
requires a canonical form with a canonical serialisation.** Markdown has one.
Lake, by design, does not need one.

## 4. Document kinds (Y3)

- **Carrier** `{doc, board, sheet, datatable}`
- **Operation** none — kind is assigned at creation and immutable
- **Identity** n/a (a set, not a monoid)
- **Absorbing** n/a
- **Laws**
  - *typed at birth*: no conversion between kinds.
  - *renderings are not kinds*: `演示模式` is a second rendering of a `doc`,
    which is why it needs no conversion and no second source.

**HERMES.** One storage kind, and `type:` classifies the *claim* (note ·
question · claim · evidence · decision · reference), not the content. The two
axes are orthogonal: `(storage kind) × (discourse type)`. We could add Yuque's
axis without disturbing ours, and the presentation-mode law is the one worth
importing — `render_slides` and `render_page` over one AST, agreeing on
content by construction.

## 5. Cards (Y4)

- **Carrier** blocks with an associated renderer
- **Operation** `embed : card → doc → doc`
- **Identity** the empty card (renders nothing)
- **Absorbing** a failing card — its blast radius is the document that
  contains it
- **Laws**
  - *arbitrary renderer*: a card may be a widget, an editor, or a third-party
    component. Expressive, and unbounded.

**HERMES.** Same slot, opposite trust model. A `​```zkquery` fence is a card
whose renderer is `parse` then `eval` — **total** (every input yields `Ok` or
a named `Error`) and **pure** (same inputs, same rows). So our absorbing
element is not "a failing card" but a *named error rendered in place*, and the
blast radius is one block rather than one document.

## 6. Collaboration and versions

- **Carrier** document versions
- **Operation** `commit : body → history → history` (append)
- **Identity** the empty history
- **Absorbing** none — `restore` appends rather than truncating
- **Laws**
  - *append-only*: history grows; restoring an old version writes a new one.
  - *permission lattice*: `read ⊑ comment ⊑ edit`, a total order per
    principal per base, with independent action toggles (copy, share,
    download) that are **advisory**, not enforceable against a reader who can
    already render.

**HERMES.** Git is the same append-only monoid with a stronger property: the
history is content-addressed, so "what did this say" is answerable without
trusting the server. Our permission lattice is degenerate — one level, repo
access — and R15 replaces per-object permission with reachability. And we make
no copy-prevention claim at all, because it is not a property a renderer can
have.

## 7. AI surface

- **Carrier** prompt, corpus, generated text
- **Operation** `generate : prompt × corpus → text`
- **Identity** none
- **Absorbing** none
- **Laws** — none stated by the product, and this is the point. Generation is
  not required to be deterministic, reproducible, or citation-bearing.

**HERMES — the categorical exclusion, algebraically.** Our verdict path
requires `⟦render⟧` and `⟦verdict⟧` to be *functions* of their inputs. A model
in either path makes them relations, and every downstream law (determinism,
the render differential, parity credit) is stated over functions. So the
exclusion is not a preference about AI; it is what the rest of the algebra
requires.

The nearest thing we build instead is HW.6.3.5: a **deterministic** answer path
whose result carries mandatory citations — `answer : question → (text ×
citation list)` with `citations ≠ []`. Fewer questions answered, and the
answers are evidence.

## 8. Summary — the four laws worth importing

| From | Law | Register id |
|---|---|---|
| Navigation | `visible = false` hides without orphaning; nodes may be URLs | HW.6.8.1–2 |
| Format | one source, several render targets, agreeing by construction | HW.6.9.3 |
| Containment | a total rule needs a named exemption to be liveable | — (would shape HW.1.4.1) |
| Cards | an embedded renderer must be total, or its failure takes the page | HW.5.4.1 (already ours) |

And the one law worth importing **as a prohibition**: a differential gate
requires a canonical serialisation, so any move toward a richer canonical form
must first say what replaces the render baseline.

Cross-references: `[[Yuque — fractal ontology]]` · `[[Yuque — fractal atlas]]` ·
`docs/hermes/features-audit-implementation-plan.md`.

Part of [[Knowledge fractal map]].
