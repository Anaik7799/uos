# Domain glossary — the ubiquitous language

One agreed word per concept. If a term appears in code, copy, a Figma layer, a
journal or a conversation, it means what it means here.

This glossary is **projected from the real registries**, not invented: product
terms come from `COPY_DECK.md`, `PLANNING_SITEMAP_FLOWS.md` and the page
manifest; structural terms come from the OCaml registries and
`docs/ONTOLOGY.md`. Where a term has a tempting near-synonym, the "not to be
confused with" column is the load-bearing part — most domain confusion in this
program has come from two words being used for one thing, or one word for two.

Companion documents: [[DOMAIN_MODEL]] (how these relate),
[[BEGINNERS_GUIDE]] (how to work with them), [[ONTOLOGY]] (the class model).

## 1. Product domain — what the user works with

| Term | Meaning | Canonically defined in | Not to be confused with |
|---|---|---|---|
| **Project** | A workspace holding sources, their graph, and the artifacts made from it. | page registry (`Project inventory`) | *Graph* — a project has one graph; the project is the container. |
| **Source** | Something imported: text, a document, a web page, a feed, media, or another knowledge graph. | feature family *Acquire* | *Statement* — a source yields many statements. |
| **Import job** | One durable unit of ingestion work, moving through `queued · running · retrying · complete · failed · cancelled`. | page manifest (P16 states) | *Source* — a job processes sources; it is the work, not the material. |
| **Statement** | A unit of admitted text, traceable to its source. The evidence unit of the whole product. | flows doc ("statements-as-evidence") | *Concept* — a statement is the sentence; a concept is what it mentions. |
| **Concept** | A node in the graph, derived from statements. | copy deck (graph panel rows) | *Topic* — a topic is a group of concepts. |
| **Edge** | A relation between two concepts, derived from their co-occurrence in statements. | copy deck (graph panel rows) | *Link* — reserved for wiki/ZK links between documents. |
| **Topic** (topical cluster, community) | A group of concepts that hang together structurally. | feature family *Analyze*; copy deck | *Category* — topics are found in the data, not assigned by hand. |
| **Gap** (structural gap) | A place where topics are weakly connected — a finding, not an error. | copy deck (insight cards) | *Error* — a gap is a legitimate result about the text. |
| **Bridge** | A topic or concept connecting otherwise separate topics. | copy deck (insight cards) | *Gap* — a bridge joins, a gap separates. |
| **Graph** | The whole structure of concepts and edges over a project. | page registry (`Interactive graph`) | *Ontology* — the ontology is this repo's self-model, not user data. |
| **Note / saved view** | An authored artifact over a graph: a written note, or a preserved selection/camera state. | feature family *Publish* | *Export* — a saved view stays inside; an export leaves. |
| **Export** | A materialized rendering of a graph or view in a chosen format. | page registry (`Export center`) | *Share* — sharing changes visibility; exporting produces a file. |
| **Visibility** | Whether an artifact is private or shared, and with whom. | feature family *Publish* | *Permission* — team access is a separate surface. |
| **Provider** | An external model or service the product can call. | page registry (`Model and provider settings`) | *Integration* — a provider is called by us; an integration calls us. |
| **Quota** | The remaining allowance against a provider or plan. | feature family *Govern* | *Limit* — a quota is measured and displayed; never fabricated. |
| **Retention / deletion** | How long user data is kept, and its removal. Deletion is the one deliberately irreversible act in the product. | page registry (`Privacy, retention, and deletion`) | *Archiving* — deletion does not keep a copy. |

## 2. Structural domain — what the design and build work with

| Term | Meaning | Canonically defined in | Not to be confused with |
|---|---|---|---|
| **Capability** | One thing the product can do, identified `F<family>.<n>` across seven families. | `docs/ontology/INFRANODUS_FRACTAL_CLOSURE.json` | *Feature family* — the family is the group (Acquire, Explore, Analyze, Publish, Integrate, Govern). |
| **Page / screen** | One addressable surface, identified `P<nn>` with a route. | `harness/ui_web/ui_page_registry.ml` | *View* — a page may render several views. |
| **Route** | The URL path a page answers on. | page registry | *Board/wiki route* — those serve published evidence, not the product. |
| **State** | A named condition a page or component can be in (`empty`, `loading`, `error`, `unavailable`, `saved`, …). | page manifest | *Status* — status is a value shown; state is what the surface is doing. |
| **Event** | Something the user or system does that a surface must respond to. | component contracts | *Action* — the action is the handler; the event is the occurrence. |
| **Flow** | An end-to-end user journey across pages, `F1`–`F5`, including its failure exits. | `PLANNING_SITEMAP_FLOWS.md` | *Capability family* — same letter, different axis; flows are journeys. |
| **Component** | A reusable interface part with a contract. | `harness/ui_web/ui_component_contract.ml` | *Variant* — a variant is one configuration of a component. |
| **Contract** | The declared role, test id, variants, events and minimum size of a component. | same file | *Implementation* — the contract is the promise; Bonsai is the keeping of it. |
| **Token** | A named design value — colour, spacing, type, radius. | `harness/figma_design.ml` → `tokens.json`/`tokens.css` | *Literal* — a hard-coded value that bypasses the token is a defect. |
| **Copy** | The real words a surface shows. | `COPY_DECK.md` | *Placeholder* — placeholder text is not copy and must not survive into layout. |
| **Mode** | The intent class of a surface — Persuade, Operate, Read, Experience — which decides how much expression is appropriate. | envelope §14 | *Theme* — light/dark is a theme; mode is about purpose. |
| **Scenario** | A traceable case binding a page, component, state and its evidence. | `docs/ontology/INFRANODUS_SCENARIO_MANIFEST.json` | *Test* — a scenario is the case; the law is the executable check. |

## 3. Evidence and governance terms

These decide whether a claim is allowed to stand. The full beginner treatment
is [[BEGINNERS_GUIDE]] §14.

| Term | Meaning |
|---|---|
| **Carrier** | The thing that holds a value. The OCaml algebra is the authoritative carrier; text, Figma, Stitch and the wiki are projections. |
| **Projection** | A generated picture of a carrier. Never authority, however convincing. |
| **Proposal** | External generator output. An idea awaiting judgement, never a decision. |
| **Law** | An executable check of a stated property, named after the property. |
| **Mutant** | A deliberate break planted to prove a law can fail. A law no mutant can break is decorative. |
| **Byte-EQ** | Identical byte for byte to the reference — the strongest claim available. |
| **EQUIV** | Equivalent in meaning but not byte-identical. Must be disclosed as such. |
| **`Unavailable_observed`** | Looked for, not available, with named evidence for re-checking. An honest result, not a failure. |
| **Disclosure** | A visible statement of a deviation. Always admissible; silence never is. |

## 4. Words we deliberately do not use

| Avoid | Because | Say instead |
|---|---|---|
| "verified" for a mockup | Only the running UI proves appearance. | "drawn", "projected", or "captured" |
| "done" without a stamp | Completion is a gate verdict, not an opinion. | "landed and gate-green", or "open" |
| "should work" | Untested assertion in evidence prose. | "checked: …", or "not yet checked" |
| "roughly" with a number | An unmeasured number reads as measured. | give the measurement, or say it is unmeasured |
