---
id: hermes-obsidian-fractal-algebra
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Obsidian — fractal algebra

#feature #src-obsidian #area-algebra #cov-analysis

## 1. Addressing

- **Carrier** `Address = Note | Note×Heading | Note×BlockId`
- **Operation** `resolve : Address ⇀ Target` (partial)
- **Identity** the note's own address (`[[#Heading]]` within a note)
- **Absorbing** an unresolvable address — rendered **visibly unresolved**, never
  silently dropped
- **Laws**
  - *namespace disjointness*: block ids keep `^`, so pinned and generated
    anchors cannot collide **by construction**
  - *alphabet narrowing*: block ids are `[A-Za-z0-9-]`, strictly narrower than
    the note-name alphabet — a parser that assumes one alphabet is wrong
  - *stability*: `resolve(Note#^id)` is invariant under edits to the block's
    text; `resolve(Note#Heading)` is not

**HERMES.** Ours matches at the first two levels and gains the third with
HW.3.3.1. The narrowing law is recorded because assuming one alphabet is
exactly the class of mistake that produced our underscore route-parser defect.

## 2. The link graph

- **Carrier** a directed multigraph over notes
- **Operation** composition of edges (paths)
- **Identity** the empty edge set
- **Absorbing** none
- **Laws**
  - *backlinks is the transpose*: `b ∈ backlinks(a) ⟺ a ∈ outlinks(b)` — the
    adjacency relation and its converse, so backlinks are **derived and cannot
    go stale**
  - *mentions are the complement*: `mentions(a) ∩ backlinks(a) = ∅`
  - *external URLs are not edges*: otherwise centrality measures whatever is
    cited most, not what the corpus is about

**HERMES.** All three are landed laws (`fst ∘ back_ctx ≡ backlinks` is the
strengthened form — we carry the citing line too).

## 3. Transclusion

- **Carrier** embed references
- **Operation** unfolding `![[x]]` to the target's content
- **Identity** a note embedding nothing
- **Absorbing** a cycle — which must be **detected**, not unfolded
- **Laws** *acyclicity* (the embed relation is a DAG) · *denotation*:
  `⟦![[x]]⟧ = ⟦body(x)⟧`, so drift between copy and source is unrepresentable

**HERMES.** HW.3.5.1–3, now unblocked. Our addition is that the depth bound is
**reported** rather than silently truncating.

## 4. Tags — a Galois connection

- **Carrier** `(Notes, Tags, incidence)` — a **formal context**
- **Operation** `members : Tag → Set Note`, `tags : Note → Set Tag`
- **Laws**
  - *antitone*: `t ⊑ t'` (prefix order) ⟹ `members(t) ⊇ members(t')`
  - the pair `(members, tags)` is a **Galois connection**, so the closed sets
    form a concept lattice — faceted filtering is lattice meet

**HERMES.** Flat tags today; HW.4.1.7 makes the prefix order real, at which
point the antitone law becomes checkable. Our corpus already *fakes* the
hierarchy with `cov-`, `area-`, `src-` prefixes.

## 5. Queries (Dataview / Bases)

- **Carrier** notes as rows
- **Operation** `FROM ∘ WHERE ∘ SORT ∘ GROUP BY ∘ FLATTEN ∘ LIMIT`
- **Laws** *data commands repeat in any order* (a pipeline, not a fixed clause
  order) · Dataview evaluates **JS**, so totality is not guaranteed

**HERMES.** `Wiki_query` takes the pipeline shape and rejects the JS: every
input yields `Ok` or a **named** `Error`, so an empty result always means "no
matches". That is the one place we are strictly stronger than both Dataview and
Bases.

## 6. Plugins — the excluded algebra

- **Carrier** arbitrary JS with vault access
- **Laws** none

**HERMES — exclusion invariant.** Every capability is a law-tested kernel. The
cost of a plugin API is that no property of the whole system remains provable.

Cross-references: `[[Obsidian — fractal ontology]]` · `[[Obsidian — fractal atlas]]` ·
`[[Unified fractal algebra]]`.

Part of [[Knowledge fractal map]].
