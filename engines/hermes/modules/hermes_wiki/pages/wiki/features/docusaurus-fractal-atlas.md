---
id: hermes-docusaurus-fractal-atlas
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Docusaurus — fractal atlas

#feature #src-docusaurus #area-atlas #cov-analysis

## 1. Static structure

```
Site (docusaurus.config) ───────────── D0
  └── Plugin content set ───────────── D1   docs | blog | pages
        └── Version × Locale ───────── D2   parallel trees
              └── Document (MDX) ───── D3   one route
                    └── mdast Node ─── D4   μX. Node + List X   ← RECURSIVE
sidebars.ts ── explicit ordering ── sidebar_position ── pagination_next/prev
```

## 2. Control flow

```
sources ──remark (13 plugins)──▶ mdast ──▶ MDX compile ──▶ React
                                              │
routes ◀── slug / sidebar ───────────────────┤
                                              ├──▶ collect links + ANCHORS
                                              └──▶ brokenLinks: path? anchor?
                                                        │
                                                   FAIL the build
static export ◀── prerender ── bundle ── theme (scrollspy, copy-code, …)
```

The seam worth copying is `collect anchors → validate separately from paths`.
Two predicates, because a dead fragment and a dead page have different fixes.

## 3. Data flow

```
MDX source (canonical)
   │ remark
   ▼
 mdast  ── recursive ──▶ MDX/JSX ──▶ React ──▶ HTML
   │
   └──▶ toc extraction, heading ids (github-slugger), anchor set
```

Canonical form is source text — so, as with Obsidian and Sphinx, a digest gate
would work. Docusaurus spends its budget on routing and reference integrity
instead.

## 4. The structural-ceiling map

```
depth-2 carrier:   List( Block( List Inline ) )
                        ▲ no block constructor contains a block
                        │
   consequences ────────┼── nested lists flatten
                        ├── admonitions cannot hold code or lists
                        ├── <details> impossible
                        └── tabs impossible

μ-recursive:       μX. Block( List X + List Inline )
                        ▲ all four become expressible at once
```

Hermes was **below** the depth-2 line (a line machine) until HW.2.0.1. This
diagram is the reason that feature ranked first at priority 35.

## 5. Atlas verdict

Docusaurus contributes the single most consequential *diagnosis* in the survey
(the carrier ceiling), the cheapest correctness win (anchor validation as a
distinct predicate), the richest frontmatter vocabulary, and the reading-
ergonomics layer. It contributes nothing to knowledge-graph structure — it has
none — and its MDX choice is the one we most firmly decline.

Cross-references: `[[Docusaurus — fractal ontology]]` · `[[Docusaurus — fractal algebra]]`.

Part of [[Knowledge fractal map]].
