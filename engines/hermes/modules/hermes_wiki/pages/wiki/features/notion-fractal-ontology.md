---
id: hermes-notion-fractal-ontology
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Notion — fractal ontology

#feature #src-notion #area-ontology #cov-analysis

Entities, levels and relations. Companions: `[[Notion — fractal atlas]]`,
`[[Notion — fractal algebra]]`. Unified view: `[[Unified fractal ontology]]`.

## 1. The level structure

Notion's fractal is over **blocks**: the same containment relation recurs at
every scale, and the recursion has no floor.

| Level | Entity | Unit of | Note |
|---|---|---|---|
| **N0** | Workspace | billing, identity | |
| **N1** | Teamspace | membership | optional |
| **N2** | Page | permission, sharing | a page IS a block |
| **N3** | Block | content, addressing | **recursive** — a block contains blocks |
| **N4** | Property | typed metadata | only on database rows |

The load-bearing fact: **a page is a block and a block may contain pages**, so
N2 and N3 are the same level seen twice. Containment is unbounded and
untyped — the opposite of Yuque's four fixed document kinds.

## 2. Entity families

**Blocks (N3)** — the whole content model. Paragraph, heading, list, toggle,
callout, quote, code, table, divider, image, embed, synced block, column list,
template button, AI block. Every one may nest.

**Databases** — not a separate entity. A database is a **collection of pages
with a shared property schema**, and a *view* (table, board, gallery, list,
calendar, timeline, chart) is a rendering of a filtered, sorted, grouped query
over that collection. This is the single most important structural fact about
Notion: **there is no table type; there is a query type.**

**Properties (N4)** — typed columns: title, text, number, select, multi-select,
status, date, person, files, checkbox, url, email, phone, formula, relation,
rollup, created/edited time and by, unique id.

**Relations and rollups** — `relation` is a typed edge between database rows,
**bidirectional by construction**; `rollup` aggregates over the far side. Together
they are a graph with computed folds — the same shape as our typed edges plus
MoC aggregation.

## 3. Relations

| Relation | Cardinality | Notes |
|---|---|---|
| block **contains** block | 1:N, **unbounded depth** | the recursion |
| page **is-a** block | 1:1 | not a distinct kind |
| database **groups** pages | 1:N | by shared property schema |
| view **renders** query | 1:1 | table/board/gallery/list/calendar/timeline |
| row **relates** row | N:M, **symmetric** | shown on both sides automatically |
| rollup **folds** relation | 1:1 | count/sum/percent over the far side |
| block **backlinks** page | derived | inverse of mention |
| page **has** version | 1:N | append-only |

## 4. Where it disagrees with Hermes

| Question | Notion | Hermes |
|---|---|---|
| What is primitive? | the **block**, recursively | the **document**, and evidence about it |
| Is a table a type? | no — a view over a query | no — a rendering of a zkquery result |
| Are relations bidirectional? | yes, automatically | yes — typed edges rendered both ways |
| Is computation in documents? | yes — formulas, rollups | **no** — computation is a law-tested kernel |
| Can a model author content? | yes — AI blocks | **never** in render or verdict |
| Where does content live? | hosted, proprietary | markdown in git |

## 5. What the ontology recommends

Take: **the view-over-query insight** (already ours — HW.5.3.*), **rollup as a
fold over a relation** (HW.4.6.3), **status as a typed lifecycle vocabulary**
(ours), **bidirectional relations** (ours).

Decline, each for a reason already recorded: formulas (uninspectable
computation), AI blocks (a model in the authoring path), hosted storage (the
review surface moves out of git), unbounded block nesting (our AST is
recursive, but the *dialect* stays small deliberately).

Cross-references: `[[Notion — fractal atlas]]` · `[[Notion — fractal algebra]]` ·
`[[Unified fractal ontology]]`.

Part of [[Knowledge fractal map]].
