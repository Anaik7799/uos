---
id: hermes-obsidian-fractal-atlas
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Obsidian — fractal atlas

#feature #src-obsidian #area-atlas #cov-analysis

## 1. Static structure

```
Vault (a folder) ──────────────────── O0
  └── Folder (organisation only) ──── O1   NON-semantic
        └── Note (.md on disk) ─────── O2   [[Title]]
              ├── Heading ──────────── O3   [[Note#H]], nests #H1#H2
              ├── Block  ^id ───────── O4   [[Note#^id]]   ← the deep one
              ├── frontmatter properties
              └── #tag / #tag/nested
graph = (notes, links)      derived: backlinks, mentions, communities
```

## 2. Control flow

```
author ──edit file──▶ disk ──watch──▶ index ──▶ graph
                                        ├──▶ backlinks pane
                                        ├──▶ local / global graph
                                        ├──▶ Dataview / Bases views
                                        └──▶ search
sync   ──▶ vault replicas      publish ──▶ hosted site
```

Everything downstream of `disk` is **derived and rebuilt**, which is why
Obsidian never has to migrate: the file is the truth and the index is
disposable. Hermes makes the identical bet, and adds the one thing Obsidian
lacks — a **gate** over the derived output (the render differential).

## 3. Data flow

```
markdown on disk  (canonical — no export step exists)
      │ parse
      ▼
   index: links · headings · blocks · tags · properties
      │
      ├──▶ render (live preview / reading view)
      ├──▶ graph analytics (plugins)
      └──▶ queries (Dataview JS / Bases YAML)
```

Note what is missing versus Yuque and Notion: **there is no projection step**,
because the canonical form is already the interchange form. This is the
property that makes a digest gate possible, and Obsidian does not use it.

## 4. The addressing ladder

| Address | Granularity | Stability under edit | Hermes |
|---|---|---|---|
| `[[Note]]` | document | survives retitle only with an alias | ✓ (aliases →HW.1.2.7) |
| `[[Note#H]]` | section | breaks on rewording | ✓ (+`{#id}` →HW.3.2.3) |
| `[[Note#H1#H2]]` | subsection | breaks on rewording | ✗ — our fragment parser is single-level |
| `[[Note#^id]]` | **statement** | **survives everything** | →HW.3.3.1 |

The ladder is the atlas's main lesson: **stability increases as granularity
gets finer**, because a pinned id is author-chosen while a heading anchor is
content-derived.

## 5. Atlas verdict

Obsidian is the comparator whose *architecture* we share and whose *discipline*
we exceed. It contributes the addressing ladder, transclusion, unlinked
mentions and nested tags. It contributes nothing to verification — and, unlike
Notion, that is a choice rather than a structural impossibility: the files are
right there, and a differential gate would work.

Cross-references: `[[Obsidian — fractal ontology]]` · `[[Obsidian — fractal algebra]]`.

Part of [[Knowledge fractal map]].
