---
id: hermes-yuque-fractal-atlas
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Yuque — fractal atlas

#feature #src-yuque #area-atlas #cov-analysis

The maps: static structure, control flow, data and format flow, and the
level-by-level view. Ontology in `[[Yuque — fractal ontology]]`; laws in
`[[Yuque — fractal algebra]]`. Bound and sourcing are stated in the ontology §0
and apply here unchanged.

## 1. Static structure

```
空间 Space ─────────────────────────── Y0  membership (optional)
  └── 知识库 Knowledge base ────────── Y1  permission · publication · search
        ├── 目录 TOC tree ──────────── Y2  reading order · visibility
        │     └── node {editNode, url, open_window, visible}
        └── 文稿 Document ──────────── Y3  authorship · versions
              ├── kind: 文档 | 画板 | 工作表 | 数据表
              ├── body: Lake (canonical)
              │     ├── → markdown   (projection, lossy)
              │     └── → HTML       (projection)
              ├── draft: Lake        (second content state)
              └── 卡片 Card ────────── Y4  arbitrary renderer
小记 Quick note ─────────────────────── exempt from Y1 containment
```

Two edges carry the design: the **total** `base contains doc` (the constraint
no other surveyed tool enforces) and the **lossy** `Lake → markdown`
(the difference between an export and a source).

## 2. Control flow — the authoring loop

```
author ──edit──▶ draft Lake ──publish──▶ Lake ──┬──▶ HTML  (read surface)
                     ▲                          ├──▶ markdown (API/export)
                     │                          └──▶ slides (演示模式)
                     └── history ◀── version snapshot
reader ──comment──▶ thread ──resolve──▶ (closed)
agent  ──API v2──▶ repos · docs · toc ──▶ same Lake
```

Three properties are visible in this shape:

- **Publication is a state transition**, not a metadata edit. Draft and
  published are two bodies, so "what is live" never depends on interpreting a
  field.
- **Every surface reads the same canonical body.** The API, the reader and
  the slide renderer are projections of one truth, which is why they cannot
  disagree.
- **The agent path is the same path.** Yuque's MCP servers drive the public
  v2 API, not a private one.

The Hermes analogue for comparison:

```
author ──edit .md──▶ git commit ──▶ corpus (canonical markdown)
                                      ├──▶ HTML   (render_markdown)
                                      ├──▶ JSON   (read model, HW.6.2.1)
                                      └──▶ text   (second target, HW.6.9.3)
gate ──render baseline──▶ digest differential ──▶ Checked | Drifted | …
```

Same shape, different pivot: their canonical form is rich and the review
surface is the editor; ours is plain and the review surface is the diff. Ours
adds a leg they have no counterpart for — the **render differential**, which
is only possible because the canonical form is bytes a digest can pin.

## 3. Data and format flow

```
                    ┌──────────────┐
   editor ─────────▶│  Lake (JSON) │◀──────── API write
                    └──────┬───────┘
                           │  serialise
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
        markdown        HTML          slides
        (lossy)      (render)      (re-paginate)
```

`format=markdown|html|lake` on the read path; `bodyDraftLake` alongside
`bodyLake` on the write path. The projection arrows are **one-way**: nothing
in the surveyed API reconstructs Lake from markdown without loss, which is
what makes markdown an export rather than a source.

For us the diagram inverts, and the inversion is the whole argument:

```
        markdown (canonical, in git)
            │  parse                 ← Wiki_ast, HW.2.0.1
            ▼
          AST (recursive blocks)
            │  render                ← catamorphism
            ▼
          HTML / text / JSON
```

Because the canonical form is the input to a digest, we get a differential
gate. Because theirs is a structured document tree, they get richness we
cannot cheaply express. Neither is free.

## 4. The four document kinds as a map

| Kind | Carrier | Hermes position |
|---|---|---|
| 文档 doc | block tree | **native** — our only kind |
| 画板 board | freeform canvas | split: generated diagrams wanted (HW.7.5.3), drawn ones excluded (HW.7.6.1) |
| 工作表 sheet | cells + formulas | excluded — computation belongs in kernels (HW.1.3.8) |
| 数据表 data table | typed records | **derived** instead — zkquery rows, no stored copy (HW.5.*) |

The pattern: where Yuque adds a *storage* kind, we either decline it or
replace it with a *derivation* over the one kind we have. That is the same
move as backlinks (derived, never stored) applied to tabular data.

## 5. Level-by-level, against the harness levels

Our fractal is over **evidence** (L0 product → L6 receipt, plus LX control);
Yuque's is over **containment**. They are not the same axis, and conflating
them would be an R9 error. The honest mapping is by *what each level is the
unit of*:

| Yuque | is the unit of | Nearest Hermes construct | Same axis? |
|---|---|---|---|
| Y0 space | membership | — (no membership model) | no |
| Y1 base | permission, publication, search | corpus root + group | partly — ours is descriptive |
| Y2 toc node | reading order, visibility | nothing today (HW.6.8.1 planned) | yes |
| Y3 document | authorship, versions | page + frontmatter | yes |
| Y4 card | embedded behaviour | zkquery fence (HW.5.4.1) | yes |
| Lake | canonical form | markdown source | yes — opposite choice |

## 6. Atlas verdict

What Yuque demonstrates that the other four comparators do not:

1. **A containment constraint can be a product feature.** Forcing every
   document into a base is the only *enforced* structural rule in the survey.
2. **A canonical form with declared projections is a coherent alternative**
   to markdown-as-source — coherent, and incompatible with a digest gate.
3. **Presentation mode proves the second-render-target law commercially.**
   One document, two renderings, no second authoring step.
4. **Navigation can be data with per-node attributes**, richer than any
   toctree surveyed.

What it does not change: every AI path stays excluded, real-time co-editing
stays excluded, and third-party cards stay excluded — each for a reason
already recorded, and none of them weakened by seeing Yuque ship them well.

Cross-references: `[[Yuque — fractal ontology]]` · `[[Yuque — fractal algebra]]`.

Part of [[Knowledge fractal map]].
