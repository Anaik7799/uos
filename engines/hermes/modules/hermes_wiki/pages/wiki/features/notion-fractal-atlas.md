---
id: hermes-notion-fractal-atlas
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Notion — fractal atlas

#feature #src-notion #area-atlas #cov-analysis

## 1. Static structure

```
Workspace ─────────────────────────── N0
  └── Teamspace ───────────────────── N1  membership
        └── Page  ≡  Block ─────────── N2/N3  (the SAME level, twice)
              ├── Block ────────────── recursive, unbounded
              │     └── Block …
              ├── (if database row) Property ─ N4
              └── Relation ──▶ row in another database
Database  =  { pages sharing a property schema }
View      =  render(query(database))     table | board | gallery | list
                                         calendar | timeline | chart
```

## 2. Control flow

```
author ──block ops──▶ page tree ──▶ live doc (no publish step)
                          │
                          ├── share ──▶ permission scope
                          ├── publish ──▶ public site
                          └── history ──▶ version list

query ──filter──▶ sort ──▶ group ──▶ view render
AI    ──prompt──▶ block content        (in the authoring path)
```

Note the absence: **there is no build**. The document is live, so there is no
render differential to take, and no place a gate could stand. This is the
structural reason Notion has nothing resembling our baseline.

## 3. Data flow

```
                blocks (canonical, hosted)
                   │
      ┌────────────┼────────────┬─────────────┐
      ▼            ▼            ▼             ▼
   web render   API (JSON)   export         views
                             md/html/pdf/csv (query renderings)
```

Canonical form is the hosted block tree. Markdown is an **export**, exactly as
in Yuque — and for the same consequence: no canonical serialisation, so no
digest gate.

## 4. The database layer as a map

| View | Query shape | Hermes analogue |
|---|---|---|
| Table | rows | `HW.5.3.1` (built) |
| Board | group by status | `HW.5.3.2` + `group by` (grammar built) |
| Gallery | rows + cover | `HW.5.3.4` |
| List | rows, minimal | `HW.5.3.5` |
| Calendar | group by date | `HW.5.3.7` — excluded |
| Timeline | date range | `HW.6.6.2` — but ours is graph history, not scheduling |
| Chart | aggregate | `HW.5.3.6` |

Every one is `render_mode(eval(query))`. We reached the same factoring; the
difference is that our rows are **derived from notes** with no stored copy.

## 5. Atlas verdict

Notion's fractal is the deepest of the five (unbounded block recursion) and the
least verifiable (no build, no canonical serialisation, computation inside
documents). It contributes the **view-over-query** factoring and the
**relation+rollup** pair; it contributes nothing to verification, because its
architecture has no seam where verification could attach.

Cross-references: `[[Notion — fractal ontology]]` · `[[Notion — fractal algebra]]`.

Part of [[Knowledge fractal map]].
