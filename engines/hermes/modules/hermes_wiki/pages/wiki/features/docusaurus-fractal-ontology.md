---
id: hermes-docusaurus-fractal-ontology
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Docusaurus — fractal ontology

#feature #src-docusaurus #area-ontology #cov-analysis

Included although the prompt named four comparators: dropping it would lose
information, and it is the source of the structural-ceiling finding that
shaped the whole implementation plan.

## 1. The level structure

Docusaurus's fractal is over **the build**: every level is something the
generator resolves, routes and emits.

| Level | Entity | Unit of |
|---|---|---|
| **D0** | Site (config, plugins, presets) | build |
| **D1** | Plugin content set (docs · blog · pages) | routing namespace |
| **D2** | Version / locale | a parallel content tree |
| **D3** | Document (MDX) | a route |
| **D4** | Node (mdast) | **recursive** content |

The load-bearing fact is **D4**: `mdast` is a genuine recursive
`μX. Node + List X`, and the 2026-08-07 analysis measured that zigvm's carrier
was **not** — depth exactly 2. One type fact explained four gaps at once
(nested lists, admonitions that cannot hold blocks, `<details>`, tabs). That
finding is why HW.2.0.1 exists and why it was the top of the priority queue.

## 2. Entity families

**Content** — MDX (markdown + JSX), 13 remark plugins: admonitions,
contentTitle, details, head, headings, mdx1Compat, mermaid,
resolveMarkdownLinks, toc, transformImage, transformLinks, unusedDirectives.

**Frontmatter (21 doc fields)** — id, title, slug, description, keywords,
image, tags, sidebar_position, sidebar_label, sidebar_class_name,
sidebar_custom_props, sidebar_key, displayed_sidebar, pagination_label,
pagination_next, pagination_prev, hide_title, hide_table_of_contents,
custom_edit_url, last_update, parse_number_prefixes.

**Visibility** — two independent axes: `draft` (excluded from the build) and
`unlisted` (built and reachable, absent from indexes and search).

**Routing and links** — slug derivation, the stateful GitHub slugger,
`{#custom-id}`, and `brokenLinks.ts` with **two separate predicates**:
`isPathBrokenLink` and `isAnchorBrokenLink`.

**Theme** — right-rail ToC with scrollspy, copy-code, back-to-top,
skip-to-content, tabs, admonitions.

## 3. Relations

| Relation | Cardinality | Notes |
|---|---|---|
| site **loads** plugin | 1:N | the extension surface |
| plugin **owns** content set | 1:1 | routing namespace |
| content set **has** version × locale | 1:N | parallel trees |
| document **routes to** URL | 1:1 | slug or override |
| document **positions in** sidebar | 1:1 | `sidebar_position` |
| document **paginates to** document | 0:1 each way | `pagination_next/prev` |
| node **contains** node | 1:N **recursive** | the ceiling-lifting fact |
| page **emits** anchors | 1:N | collected for validation |
| link **targets** path × anchor | N:1 | **two** distinct failure modes |

## 4. Where it disagrees with Hermes

| Question | Docusaurus | Hermes |
|---|---|---|
| Is content executable? | **yes** — MDX is JSX | no; content can never become markup |
| Is the AST recursive? | yes | **now yes** (HW.2.0.1, landed) |
| Are anchors validated? | yes, separately from paths | **now yes** (HW.3.4.3, landed) |
| Visibility axes | two (draft, unlisted) | one (`status`) — HW.1.4.1 open |
| Extension model | plugins + themes | law-tested kernels only |
| Display layer | rich, client-side | split by surface (Fork 4) |

## 5. What the ontology recommends

Already taken: the recursive carrier (HW.2.0.1) and anchor validation
(HW.3.4.3), both landed this session.

Still to take: the **21-field frontmatter** subset (`sidebar_position`,
`pagination_next/prev`, `description`, `keywords`, `slug`), the **two-axis
visibility split** (HW.1.4.1), **`{#custom-id}`** (HW.3.2.3), and the
**display layer** under Fork 4.

Decline: MDX and the plugin/theme API — executable content is the opposite of a
total, escapable renderer, and its absence is what makes the render
differential meaningful.

Cross-references: `[[Docusaurus — fractal atlas]]` · `[[Docusaurus — fractal algebra]]`.

Part of [[Knowledge fractal map]].
