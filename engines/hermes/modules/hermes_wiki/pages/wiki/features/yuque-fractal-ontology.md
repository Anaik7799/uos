---
id: hermes-yuque-fractal-ontology
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Yuque — fractal ontology

#feature #src-yuque #area-ontology #cov-analysis

What Yuque's entities *are*, how they nest, and which of its distinctions
are load-bearing rather than presentational. Companion documents:
`[[Yuque — fractal atlas]]` (the maps) and `[[Yuque — fractal algebra]]`
(carrier, operation, identity, laws).

## 0. Scope and honest bound

**This is a survey, not a download.** `yuque.com` is a single-page
application whose product surface sits behind authentication, and its help
centre is itself a Yuque knowledge base rendered client-side. What was
actually read: the public marketing pages, the official Node SDK and its
resource list, the v2 API shape as documented by the SDK and by three
independent MCP servers, the official AI-ecosystem site, and Chinese-language
product documentation and reviews. Feature names are given in Chinese with
translation because several have no established English name.

Consequences to keep in view: **version drift** (Yuque ships continuously and
the AI surface changed materially in 2023 and 2025), and **depth asymmetry**
— the API surface is documented precisely, the editor surface only
descriptively. Where a claim rests on a secondary source it is stated as such
rather than asserted flatly.

## 1. The level structure

Yuque is fractal in the same sense this harness is: the same containment
relation recurs at four scales, and each level is the unit of *something* —
permission, publication, or identity.

| Level | Entity | Unit of | Mandatory? |
|---|---|---|---|
| **Y0** | 空间 Space / group | membership | no — a personal account has none |
| **Y1** | 知识库 Knowledge base | permission · publication · search scope | **yes** for documents |
| **Y2** | 目录 TOC node | reading order · visibility | yes — every doc has a position |
| **Y3** | 文稿 Document (four kinds) | authorship · version history | — |
| **Y4** | 卡片 Card / block | embedded behaviour | — |

The load-bearing fact is at **Y1**: a document *cannot exist outside a
knowledge base*. Yuque's own product writing states this as deliberate — the
hierarchy is enforced "from the source" so that users acquire the habit of
knowledge management rather than accumulating loose files.

That is a **prescriptive** container. Ours is **descriptive**: a Hermes group
is the parent directory's basename, computed after the fact, and a note may
live anywhere under a corpus root. The distinction matters because it decides
whether "which base?" is a question the system can refuse to leave unanswered.

## 2. The entity families

### 2.1 Containers (Y0–Y2)

`空间` → `知识库` → `目录节点`. Only the middle one is mandatory. The TOC node
is the interesting entity: it is **not** derived from storage. It carries
`editNode`, `url`, `open_window` and `visible`, which means a node may be

- a document in this base,
- an **external URL** (so the tree holds non-documents), or
- a **hidden** structural placeholder (present in the tree, absent from the
  sidebar).

Sphinx's `toctree` has the hidden case; nothing surveyed has the *external
node* case. This is the richest navigation model of the five comparators.

### 2.2 Documents (Y3) — a typed kind at the top level

Four kinds, not one: `文档` doc · `画板` board · `工作表` sheet · `数据表` data
table. Plus two lifecycle-adjacent forms: `演示模式` presentation mode (a
*rendering* of a doc, not a kind) and `小记` quick notes (a fragment that is
exempt from Y1's containment rule).

The ontological claim is that **document kind is a first-class type**, decided
at creation and not convertible. Notion takes the opposite view — everything
is a page of blocks, and a "database" is a view. Obsidian takes a third — a
file is a file, and kind is a plugin's interpretation.

Hermes is closest to Obsidian: one kind, `type:` in frontmatter as a
*discourse* classification (note · question · claim · evidence · decision ·
reference) rather than a storage or editor kind. Ours classifies **what a
document asserts**; Yuque's classifies **what a document is made of**. These
are orthogonal, and we could adopt Yuque's axis without disturbing ours.

### 2.3 Content (Y4)

`卡片` cards — Yuque's own description is that a card may be "a feature, an
independent editor, or a small widget", with a third-party registration path.
A card is therefore a **block whose renderer is arbitrary code**.

Our fenced `​```zkquery` block is the same ontological shape reached from the
opposite direction: a block whose renderer is a *total, law-tested evaluator*.
Same slot in the ontology, opposite trust model.

### 2.4 The format entity — Lake

`Lake` is Yuque's canonical document representation. The API exposes
`bodyLake` (canonical), `body` (markdown projection), `bodyHTML` (HTML
projection) and `bodyDraftLake` (an unpublished second body).

This makes **format an entity in its own right**, with a designated
authoritative member and derived projections. That is the deepest structural
difference from Hermes, and §4 of the algebra document treats it formally.

## 3. Relations

| Relation | Cardinality | Notes |
|---|---|---|
| space **owns** base | 1:N | optional level |
| base **contains** doc | 1:N, **total on docs** | the enforced constraint |
| toc node **positions** doc | 1:1 | a doc has exactly one position |
| toc node **points to** url | 0:1 | the non-document escape |
| doc **has** kind | 1:1, immutable | typed at creation |
| doc **has** lake body | 1:1 | canonical |
| doc **projects to** markdown / html | 1:N, **lossy** | not inverses |
| doc **has** draft body | 0:1 | a second content state |
| doc **contains** card | 1:N | arbitrary renderer |
| doc **has** version | 1:N | append-only, restorable |
| base **grants** permission | N:M | read · comment · edit, plus action toggles |

The two relations with the most consequence are `base contains doc` (total,
which no other surveyed tool enforces) and `doc projects to markdown` (lossy,
which is what separates "export" from "source").

## 4. Where the ontologies disagree with ours

| Question | Yuque | Hermes |
|---|---|---|
| Can a document be homeless? | **No** — Y1 containment is total | Yes — group is derived, not required |
| What is authoritative? | Lake, a rich proprietary form | **Markdown**, a plain diffable form |
| Is markdown lossy? | Yes, it is a projection | No, it is the source |
| Is document kind typed? | Yes, four kinds, immutable | One kind; `type:` classifies the CLAIM |
| Is navigation authored? | Yes, an editable tree with attributes | No, derived from directories |
| Is draft a separate body? | Yes (`bodyDraftLake`) | No — one body, a visibility state |
| Who may write? | Anyone with permission, in real time | Nobody over HTTP; the route ADT forbids it |
| Does a model participate? | Yes, in writing and answering | **Never** in render or verdict |

None of these is a defect on either side; each is a different answer to "what
is the review surface?" Yuque's answer is the editor, so richness is free and
diffability is expensive. Ours is git, so diffability is free and richness is
expensive.

## 5. What this ontology recommends we take

Ranked, with the reason:

1. **TOC node attributes** (`visible`, `url`) — the richest navigation model
   surveyed, and it subsumes Sphinx's `:hidden:`/`:orphan:` in one field.
2. **Presentation mode as a second render target** — the same law our planned
   text export states: one source, several renderings, and the separation of
   structure from presentation becomes *testable* rather than claimed.
3. **The quick-note exemption** — an inbox that is deliberately outside the
   containment rule. It is what makes a strict rule liveable.
4. **Search scoped by container** — trivially available once the container
   relation exists.

And what it recommends we **decline**, with the reason stated once so it need
not be re-argued: Lake-style canonical richness (it moves review out of git),
real-time co-editing (it removes the reviewable commit), third-party cards and
embeds (unbounded surface, and CSP), spreadsheet formulas (uninspectable
computation in documents), and every AI writing path (a model must not be able
to author what the system later treats as evidence).

Cross-references: `[[Yuque — fractal atlas]]` · `[[Yuque — fractal algebra]]` ·
the register in `docs/hermes/features-audit-implementation-plan.md`.

Part of [[Knowledge fractal map]].
