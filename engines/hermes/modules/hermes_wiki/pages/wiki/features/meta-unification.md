---
id: hermes-meta-unification
status: published
type: claim
ktype: moc
maturity: incubating
domain: formal_verification
topics: [meta, unification, fractal, register]
created: 2026-08-09
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Meta-unification — one view that explains all six systems

#feature #src-unified #area-meta #cov-analysis

The other four unified documents describe. This one **explains**: a single
claim that predicts, for any of the six systems, which features it will do well
and which it will do badly — without looking at its feature list.

Typed `claim` rather than `reference`, because it is falsifiable and I state
below what would falsify it.

## 1. The claim

> **Each system makes exactly one layer primitive and derives the rest. What a
> system makes primitive, it does excellently. What it derives, it does
> adequately. What it can neither make primitive nor derive from its primitive,
> it cannot do at all — and no amount of engineering changes that, because the
> obstruction is the choice of primitive, not the size of the backlog.**

The six primitives, using the families from `[[Unified fractal ontology]]` §2:

| System | Primitive layer | Everything else is… |
|---|---|---|
| **Notion** | F5 Derivation — the block, recursively, and views over collections | derived from blocks |
| **Obsidian** | F2 Addressing + F3 Graph — the file and the link | derived from the index |
| **Docusaurus** | F2 + partial F6 — the route and the build | derived from the build |
| **Sphinx** | F6 Verification — the checked reference | derived from the environment |
| **Yuque** | F1 Containment + F4 Projection — the base and Lake | derived from the canonical body |
| **Hermes** | F6 over **evidence** — the digest, the law, the differential | derived from the corpus |

## 2. The claim's predictions, checked

A claim that only describes is worthless. Here is what it *predicts*, checked
against the survey.

**Prediction 1 — Notion cannot verify.** Its primitive is the live block; there
is no build step, so there is no seam where a gate could stand. *Observed:* zero
verification features across the entire product. Not "few" — zero.

**Prediction 2 — Yuque cannot have a differential gate**, even though it is a
disciplined engineering organisation. Its primitive includes a rich canonical
form, which has no canonical serialisation. *Observed:* no digest gate; and the
proof that this is structural, not an oversight, is in
`[[Unified mathematical structures]]` §4.

**Prediction 3 — Obsidian's graph work is excellent and its verification is
absent, but the absence is a choice rather than an obstruction**, because its
primitive (files on disk) *does* admit a gate. *Observed:* exactly this —
best-in-class backlinks, mentions, block addressing; no link checking at all,
despite the files being right there.

**Prediction 4 — Sphinx will have the deepest reference and executability story
and no knowledge graph.** *Observed:* nitpicky, typed domains, intersphinx,
doctest, coverage, linkcheck — and no backlinks, no mentions, no clustering.

**Prediction 5 — Hermes will be strong where evidence is the question and weak
at everything a knowledge tool does for a reader.** *Observed, and it stung:*
this session found the corpus had **no ordered lists, no dividers, no
checkboxes, no callouts, no search**. Table stakes for every comparator, absent
here — because none of them is an evidence question.

Five predictions, five confirmations, including one against our own interest.

## 3. What would falsify it

- A system with a rich hosted canonical form that nonetheless ships a
  content-digest gate that is not merely a change-feed.
- A system whose primitive is verification but which also leads on knowledge
  graph *and* on authoring ergonomics.
- Hermes closing all 136 open register rows without the primitive changing —
  which would mean the claim's "cannot do at all" clause is empty and the claim
  reduces to "priorities differ".

The third is the honest one to watch. The claim is only interesting if the
obstruction is real, and the way to find out is to keep building and see which
rows resist.

## 4. Why this predicts the register's shape

The register's 281 features, 136 open, sort into three classes under the claim,
and the classification matches the readiness labels arrived at independently:

| Class | Meaning | Count | Register signature |
|---|---|---|---|
| **Derivable** | expressible from our primitive | ~144 | `Ready` or `Blocked` — a matter of work |
| **Fork-gated** | needs a policy decision that touches the primitive | 9 | `Forked 1..4` |
| **Foreclosed** | contradicts the primitive | 55 | `Excluded`, each with an exclusion invariant |

The 55 exclusions are not a backlog we declined; they are the **shape of the
primitive seen from outside**. Every one has an invariant that holds *because*
the feature is absent — `render` does no network IO, the build imports nothing,
no LLM occurs in `⟦render⟧` or any verdict. That is why the register records
exclusion invariants rather than reasons: a reason is an opinion, an invariant
is a checkable commitment.

## 5. The two theorems, restated as consequences of the claim

Both are proved in `[[Unified mathematical structures]]`; here is why the claim
makes them inevitable rather than surprising.

**A differential gate requires a canonical serialisation** (§4 there). If your
primitive is a rich structured document, "the content" is an equivalence class
over serialisations, and a digest names a representative rather than the class.
The gate is not hard to build; it is not *meaningful*.

**Render and verdict must be functions** (§5 there). If your primitive is
evidence, every law you state quantifies over inputs. A generative model makes
those relations, and the laws become unstatable — not false, unstatable. So the
AI exclusion is not a stance about AI; it is what the primitive requires.

Each theorem is the claim's "cannot do at all" clause instantiated once.

## 6. What a system should borrow, and what it cannot

The claim gives a rule for reading the whole survey:

> **Borrow freely across derived layers. Borrow across primitives only by
> changing your primitive — and price that change honestly.**

Applied to us, everything already in the plan is a derived-layer borrow:

- from **Obsidian**: block anchors, transclusion, nested tags, aliases — F2/F3,
  and our primitive sits above both
- from **Sphinx**: typed references, nitpicky, doctest, coverage, inventories —
  same family as ours, so these are the *easiest* borrows in the survey
- from **Docusaurus**: the recursive carrier, anchor validation, frontmatter,
  visibility split — derived-layer, and two of them landed this session
- from **Notion**: view-over-query, rollup-as-fold — derived
- from **Yuque**: TOC node attributes, the second render target, the exemption
  pattern — derived

And the things we cannot borrow without changing what Hermes is: Lake-style
canonical richness, live co-editing, plugin/card/MDX extensibility, in-document
computation, and any generative authoring path. Each appears in the register as
`Excluded` with an invariant, and §5 says why each one is a primitive change
rather than a feature.

## 7. The reflexive test

The claim should apply to itself. Its primitive is *explanation by
obstruction*, so it should be good at saying what is impossible and poor at
saying what is valuable. That is exactly its failure mode: it cannot tell you
whether callouts matter more than footnotes, because both are derivable and the
claim is silent inside that class.

Which is correct, and worth stating: **for ranking within the derivable class,
the claim is useless and `Feature_register.priority` is the tool** —
`3·criticality + 2·utility + |gates|`, computed rather than argued. The two
instruments cover different questions, and neither substitutes for the other.

## 8. Summary

- Six systems, six primitives, one lattice (`[[Unified fractal ontology]]`).
- Verification is a control-flow *possibility*, not a diligence property
  (`[[Unified fractal atlas]]` §2).
- 34 family laws; Hermes holds 24, 8 open with register ids, 2 declined
  (`[[Unified fractal algebra]]` §7).
- 18 mathematical structures; 5 load-bearing here; 1 (Knaster–Tarski over an
  attack graph) with **no occupant in the survey** and open as HW.4.4.1
  (`[[Unified mathematical structures]]`).
- The claim predicted five observations, one against our own interest, and
  names what would falsify it.

Cross-references: `[[Unified fractal ontology]]` · `[[Unified fractal atlas]]` ·
`[[Unified fractal algebra]]` · `[[Unified mathematical structures]]` · the
fifteen per-tool documents · `docs/hermes/features-audit-implementation-plan.md`.

Part of [[Knowledge fractal map]].
