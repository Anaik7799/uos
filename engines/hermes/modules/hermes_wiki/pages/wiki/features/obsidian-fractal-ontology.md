---
id: hermes-obsidian-fractal-ontology
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Obsidian — fractal ontology

#feature #src-obsidian #area-ontology #cov-analysis

## 1. The level structure

Obsidian's fractal is over **addressing**: the same "point at a thing" relation
recurs at four granularities, and each level is the unit of *reference*.

| Level | Entity | Unit of | Addressed by |
|---|---|---|---|
| **O0** | Vault | identity, sync | a folder |
| **O1** | Folder | organisation only | a path |
| **O2** | Note (a file) | authorship, versions | `[[Title]]` |
| **O3** | Heading | section | `[[Note#Heading]]`, nestable `#H1#H2` |
| **O4** | Block | statement | `[[Note#^id]]` |

**O1 is deliberately weak.** Obsidian's stated philosophy is that folders are
not the organising principle — links are. The graph, not the tree, carries
structure. That is the exact opposite of Yuque's enforced containment, and it
is the same choice Hermes made (our group is derived and non-load-bearing).

The load-bearing fact is **O4**: a *statement* is addressable. No other
comparator except Yuque's card model gets below the section, and none makes
sub-document addressing part of the link syntax.

## 2. Entity families

**Files** — plain markdown on disk, no database. The vault is a folder; the
app is a lens. Ownership is the point: notes outlive the tool.

**Links** — `[[Title]]`, `[[Title|display]]`, `[[Note#Heading]]`,
`[[Note#^blockid]]`, and embeds `![[…]]`. Block ids are Latin letters, digits
and dashes; placement is block-kind-dependent (end-of-line for a paragraph, own
line for lists/quotes/callouts/tables).

**The graph** — outlinks, backlinks (derived inverse), unlinked mentions, tags
(flat and nested), and the local/global graph views.

**Properties** — YAML frontmatter, typed in the UI.

**Bases (2025)** — `.base` YAML files defining filtered, formula-bearing views
over notes. Convergent with Dataview and with our zkquery.

**Plugins** — the extension surface: Dataview, Kanban, Excalidraw, spaced
repetition, graph analysis. Community capability rather than core.

## 3. Relations

| Relation | Cardinality | Notes |
|---|---|---|
| vault **contains** note | 1:N | folders optional and non-semantic |
| note **has** heading | 1:N | nestable address `#H1#H2` |
| note **has** block id | 1:N | author-pinned, `^`-prefixed |
| note **links** target | N:M | resolved or visibly unresolved |
| note **backlinks** note | derived | inverse; never stored |
| note **mentions** note | derived | title match WITHOUT a link |
| note **embeds** target | N:M | must be acyclic |
| note **tagged** tag | N:M | tags are hierarchical by prefix |

## 4. Where it disagrees with Hermes

Almost nowhere — this is the closest comparator to us. The real differences:

| Question | Obsidian | Hermes |
|---|---|---|
| Extension model | plugins (JS) | law-tested kernels only |
| Queries | Dataview (JS) / Bases (YAML) | zkquery — total, no JS |
| Verification | none | render differential, laws, mutation legs |
| Read surface | the app | a served/static site, read-only by type |
| Block ids | ✓ core | HW.3.3.1, now unblocked |

## 5. What the ontology recommends

Take, in order: **block ids `^id`** (HW.3.3.1 — one addressing scheme for
links, embeds, search hits and citation), **transclusion** (HW.3.5.*),
**nested tags** (HW.4.1.7), **aliases** (HW.1.2.7), **unlinked mentions**
(already ours).

Decline: the plugin model, and JS-evaluated queries — for the same reason in
both cases, that an unbounded extension surface cannot carry laws.

Cross-references: `[[Obsidian — fractal atlas]]` · `[[Obsidian — fractal algebra]]`.

Part of [[Knowledge fractal map]].
