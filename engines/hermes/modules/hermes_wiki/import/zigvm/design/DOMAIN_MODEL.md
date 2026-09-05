# Functional domain model

What the product is *about*, as entities and relations — independent of any
screen, framework or canvas. Screens come later and are chosen to serve this;
if a screen and this model disagree, the model is the question to settle first.

**Provenance, stated plainly:** this model is *projected* from the existing
registries — the page manifest, the flows and feature families, the component
contracts and the copy deck. It does not introduce new domain concepts. Where a
relation is asserted here but not yet mechanically enforced anywhere, it is
marked ○ rather than left to look official.

Terms are defined once in [[DOMAIN_GLOSSARY]]. Structure and governance live in
[[ONTOLOGY]] and [[FIGMA_FRACTAL_STPA_ENVELOPE]]; how to work with all of it is
[[BEGINNERS_GUIDE]].

## 1. The core: text becomes structure

The product's single idea is that **text has structure, and the structure is
worth seeing.** Everything else serves that.

```
   SOURCE                 STATEMENT              CONCEPT ──edge── CONCEPT
   text, document,   ──►  admitted unit    ──►   a node in the graph
   web, feed, media,      of text, always         │
   another graph          traceable to its        └──grouped into──► TOPIC
        │                 source                                      │
        │                                                             │
    IMPORT JOB                                          findings over topics:
    queued → running → retrying                          GAP (weakly joined)
      → complete | failed | cancelled                    BRIDGE (joins them)

   All of the above lives inside a PROJECT, and together the concepts
   and edges of a project ARE its GRAPH.

   From the graph the user makes:
      NOTE / SAVED VIEW  (stays inside)      EXPORT  (leaves, as a file)
                                             SHARE   (changes visibility)
```

## 2. Entities

| Entity | Identity | Holds | Lifecycle |
|---|---|---|---|
| **Project** | user-scoped | sources, one graph, notes/views | created → active → deleted |
| **Source** | within a project | raw imported material and its origin | added → processed → superseded |
| **Import job** | per ingestion request | which sources, and progress | `queued · running · retrying · complete · failed · cancelled` |
| **Statement** | within a source | one admitted unit of text | admitted (immutable thereafter) |
| **Concept** | within a graph | a node | appears when admitted by ≥1 statement |
| **Edge** | concept pair, within a graph | a relation and its strength | derived, recomputed with the graph |
| **Topic** | within a graph | a set of concepts | derived |
| **Gap / Bridge** | over topics | a structural finding | derived, presented as a finding |
| **Note / saved view** | within a project | authored text, or a preserved selection/camera | created → edited → saved → deleted |
| **Export** | per request | a rendering in a chosen format | requested → generating → ready \| failed |
| **Provider** | per account | an external model/service and its quota | unconfigured → configured → unavailable |
| **Account / team / subscription** | per user or org | identity, access, plan | evidence-gated surfaces |

## 3. Relations

```
  Project 1 ──── * Source 1 ──── * Statement * ──── * Concept
     │                                                  │  *
     │                                                  │  │ edge
     │                                                  │  *
     │                                                  ▼
     │                                               Concept
     │
     ├── 1 ──── 1 Graph  = ( Concepts , Edges )  over the project
     │              │
     │              ├── * Topic        (groups concepts)
     │              └── * Gap/Bridge   (relates topics)
     │
     ├── * Note / saved view   → references Concepts and Statements
     └── * Export              → renders a Graph or a saved view
```

Read the important one aloud: **a concept exists because statements admit it,
and a statement exists because a source contained it.** That chain is why the
product can always answer "why is this here?" — and why breaking it would be
worse than any visual defect.

## 4. Invariants

| # | Invariant | Enforced by |
|---|---|---|
| D1 | Every statement is traceable to exactly one source. | ○ domain rule; surfaced by the statements view |
| D2 | Every concept is admitted by at least one statement. | ○ domain rule |
| D3 | Every edge connects two concepts in the same graph. | ○ domain rule |
| D4 | A derived value (counts, metrics, topics, gaps) is computed from state, never fixed at a constant. | Copy and evidence honesty rules; the fabricated-constant prohibition |
| D5 | A number shown to a user was measured; if it cannot be, the surface says so rather than inventing it. | `COPY_DECK.md` (`observed, not fabricated`) |
| D6 | Deletion is the only irreversible act, and it is confirmed explicitly. | Flow F5 design |
| D7 | An import job always reaches a terminal state; failure is a first-class outcome with retry/skip. | Page manifest states (P16); flow F1 failure exits |

○ = a stated domain rule, not yet mechanized. Listed so the gap is visible
rather than assumed handled.

## 5. Domain → interface

The functional model above maps onto the interface through registries, in this
order. Each arrow is a design decision, and each has a home:

```
  capabilities (F-families)     what the product can do
        │                       docs/ontology/INFRANODUS_FRACTAL_CLOSURE.json
        ▼
  flows F1–F5                   how a user gets something done, incl. failures
        │                       docs/design/PLANNING_SITEMAP_FLOWS.md
        ▼
  pages P01–P37 + routes        where it happens
        │                       harness/ui_web/ui_page_registry.ml
        ▼
  states + events               what each surface can be doing
        │                       docs/ontology/INFRANODUS_PAGE_MANIFEST.json
        ▼
  components + contracts        what it is built from
        │                       harness/ui_web/ui_component_contract.ml
        ▼
  copy + tokens                 what it says and how it looks
                                docs/design/COPY_DECK.md · tokens.json/css
```

The six feature families — **Acquire · Explore · Analyze · Publish · Integrate
· Govern** — partition the capabilities, and each flow crosses several of them.
That is the intended shape: families group what the product *can* do, flows
describe what a person *does*.

## 6. What this model does not cover

Stated so no one reads silence as completeness: pricing and plan mechanics,
team permission semantics beyond the surfaces listed, provider-specific
behaviour, and anything about the VM itself (a different domain entirely —
see `CODEBASE_MAP.md`). External account surfaces remain evidence-gated and are
reported as observed, never assumed.
