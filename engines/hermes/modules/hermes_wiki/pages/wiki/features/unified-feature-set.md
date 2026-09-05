---
id: hermes-unified-feature-set
status: published
type: decision
ktype: moc
maturity: incubating
domain: formal_verification
topics: [feature-set, use-cases, selection, non-set]
created: 2026-08-09
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Unified feature set — the maximal admissible set, with use cases and the chosen design

#feature #src-unified #area-design #cov-analysis

The **normative** layer. The five analytical documents describe what the six
systems are; this one decides what *we build*, picking the best design for each
capability across all surfaces and saying why.

Companion normative documents: `[[Unified domain ontology]]`,
`[[Unified functional atlas]]`, `[[Unified functional algebra]]`,
`[[Unified implementation approach]]`. Analytical basis:
`[[Unified fractal ontology]]`, `[[Unified fractal atlas]]`,
`[[Unified fractal algebra]]`, `[[Unified mathematical structures]]`,
`[[Meta-unification]]`.

## 0. The selection rule

From `[[Meta-unification]]`: **borrow freely across derived layers; borrow
across primitives only by changing the primitive, and price that honestly.**

So a design is admissible here iff it preserves the four properties the
harness's primitive requires:

| P | Property | Violated by |
|---|---|---|
| **P1** | the canonical form has a canonical serialisation | Lake, Notion blocks |
| **P2** | `render` and `verdict` are **functions** | any generative authoring path |
| **P3** | `render` performs no IO and imports nothing | link previews, autodoc, network fetch |
| **P4** | invalid states are unrepresentable where cheaply possible | untyped resolvers, open block types |

Everything below is admissible. Where a comparator's design is better than ours
*and* admissible, we take theirs and say so. Where it is better and
inadmissible, the exclusion invariant is named.

## 1. Corpus and identity — 9 features

**Use case.** *A note is written, moved, renamed and cited over years, and no
citation may break.*

| Feature | Chosen design | From | Why this one |
|---|---|---|---|
| Corpus membership | `git ls-files` | Hermes | Membership is reviewable in a diff and cannot drift between renderer and tests. |
| Page identity | content-derived slug | Hermes / Obsidian | `slug ∘ move_dir = slug` — reorganising never breaks a link. Yuque's total containment buys the opposite and costs this. |
| Collision handling | group-qualified **and reported** | Hermes | Silent renames are the failure mode; a notice makes the URL explicable. |
| Slug override | `slug:` frontmatter | Docusaurus | Turns disambiguation from a derivation into a decision, and is the migration tool for preserving an inbound URL. |
| Aliases | `aliases:` as extra resolver keys | Obsidian | The only thing that makes a *title* editable; without it retitling silently orphans inbound links. |
| Stable id | frontmatter `id`, else derived | Hermes | A rename must not break an evidence citation. |
| Two-axis visibility | `draft` ⊕ `unlisted` ⊕ `listed` | Docusaurus | Our single `status` cannot express "published but not indexed" — the normal state of in-progress writing. |
| Container exemption | an inbox form outside the containment rule | Yuque (小记) | A total rule needs a *named* escape hatch to be liveable. Adopted as a pattern even though our containment is not total. |
| Foreign corpus ingest | third corpus root | — | The product's own 382-document site: a foreign-authored stress corpus **and** a parity artifact. |

## 2. Dialect — 22 features

**Use case.** *A specification carries procedures, warnings, checklists, quoted
source and diagrams, and renders identically for ten years.*

| Feature | Chosen design | From | Why |
|---|---|---|---|
| Block carrier | `μX. Block(List X + List Inline)`, **closed** constructors | Docusaurus mdast, closed by us | Recursive lifts the ceiling; closed keeps `render` total. Landed. |
| Fence metadata | `Code_block {lang; meta}` | Docusaurus | One type change gates five features. |
| Ordered lists · rules · task items · strikethrough | CommonMark / GFM | spec | Normative grammars exist; conform. Landed. |
| Callouts | `> [!type]` with 13 aliased kinds, `+`/`-` folding | Obsidian **form**, Docusaurus **nesting rule** | Obsidian's degrades to a readable blockquote and composes with our blockquote parser; Docusaurus's colon-count nesting is the more robust depth rule. Best of both. |
| Nested lists · `<details>` · tabs | fall out of the carrier | — | Free once the carrier is recursive. |
| `[TOC]` | built with the **same slugger** the renderer uses | Hermes | Ids and links cannot disagree — a defect class removed rather than tested. |
| Footnotes | `[^n]` | GitHub ext. | Not in the GFM spec, so it is a **dialect choice we author** and pin. |
| Unclaimed-directive lint | report constructs seen but not interpreted | Sphinx | Closes the silent-no-op class: authors currently get plain text and no warning. |
| `seealso` · `rubric` · index · productionlist | Sphinx directives | Sphinx | `productionlist` matters here: we document three grammars as inert fences today. |
| Math · Mermaid · Graphviz | **server-side** to inline SVG/markup | ours, against all five | P3. Every comparator ships client JS; none can, under `default-src 'none'`. |
| Diagrams from the model | generate from the ontology, not by hand | Sphinx `inheritance_diagram` | A diagram generated from the model **cannot drift from it**. |
| MDX / cards / plugins | **excluded** | — | P2/P4: executable content removes "content cannot become markup" as a type-level guarantee. |

## 3. Addressing — 14 features

**Use case.** *An evidence note cites one sentence of a spec; the spec is
reworded; the citation must still point at that sentence or fail loudly.*

| Feature | Chosen design | From | Why |
|---|---|---|---|
| Wikilinks | resolved or **visibly missing** | Obsidian / Hermes | Silent rot is the enemy. |
| Resolver | four keys → one slug | Hermes | Link by whatever you remember; friction here stops people linking at all. |
| Heading anchors | github-slugger, stateful, **local** | Docusaurus | Deep links copied from GitHub resolve; single-page render ≡ corpus render. |
| Pinned heading id | `{#custom-id}` | Docusaurus | `anchor ∘ retitle = anchor`. |
| **Block anchors** | `^id`, `[A-Za-z0-9-]`, keeps `^` | Obsidian | One primitive unlocking block links, transclusion targets, statement-level search hits and grounded citation. Namespaces disjoint **by construction**. |
| Multi-level fragments | `[[Note#H1#H2]]` | Obsidian | Our fragment parser is single-level. |
| Anchor collection | per page, complete | Docusaurus | Prerequisite for the next row. |
| **Broken-anchor validation** | a diagnosis **distinct** from broken link | Docusaurus | Different fixes ⟹ different diagnoses. Landed. |
| Typed reference roles | `Kind × Name ⇀ Target` | Sphinx | A wrong resolution becomes *detectable* rather than plausible. |
| **Ambiguity is an error** | `\|resolve\| = 1`, 0 and >1 reported distinctly | Sphinx `:any:` | We report at the definition site and are silent at the *use* site — where the reader is actually harmed. |
| Nitpicky mode | fail on any unresolved reference, `!` opt-out | Sphinx | Strict with a **disclosed** exception that leaves a mark. |
| Glossary + `:term:` | undefined term ⟹ diagnostic | Sphinx | Our private vocabulary (parity, divergence, oracle, fractal level) is defined in prose, inconsistently. |
| Transclusion | `![[x]]` / `![[x#^id]]`, DAG, depth 3, **bound reported** | Obsidian, hardened | Ends copy-paste drift; the reported bound is ours. |
| Reference inventory | publish + consume, **local paths only** | Sphinx intersphinx | The only inter-corpus mechanism in the survey; P3 forces local-only. |

## 4. Graph — 12 features

**Use case.** *Which claims in this corpus still stand, and which notes would
fragment it if they were wrong?*

| Feature | Chosen design | From | Why |
|---|---|---|---|
| Backlinks | derived inverse **with citing line** | Hermes | Derived cannot go stale; the line turns navigation into an argument summary. |
| Unlinked mentions | title match, disjoint from backlinks | Obsidian | Latent structure as actionable work. |
| Typed edges | `[[T\|@rel]]`, rendered both ways | Hermes / Notion relations | Edges with meaning are the raw material for §4's reasoning. |
| Nested tags | prefix order, antitone into members | Obsidian | Our corpus already fakes it with `cov-`/`area-`/`src-` prefixes. |
| PageRank / PPR | `αQ + (1−α)1sᵀ`, full support, fixed summation order | classical | One kernel serving navigation *and* search ranking. |
| Communities | **constrained** label propagation | ours, correcting Raghavan | LPA is non-deterministic by construction; determinism is required because the baseline pins output. |
| Betweenness | Brandes, fixed vertex order | classical | Finds the notes whose staleness is most dangerous. |
| Structural holes | report-only | InfraNodus lineage | The one metric that suggests **what to write next**. |
| Similarity | TF·IDF cosine, fences excluded | classical | Finds notes about the same thing with no shared tags or links. |
| MoCs | community-grounded, degree > 0, ties by slug | zigvm / LYT | A directory MoC re-presents the filing decision; a community MoC surfaces a grouping nobody declared. |
| **Grounded semantics** | least fixed point of `F_AF`; `@opposes` is attack, `@supports` is defence | Dung | **No occupant anywhere in the survey.** Makes anomalies structural: a claim with no support, a claim the fixed point rules out. |
| Local graph | per-note neighbourhood | Obsidian | The global graph is an overview; the local one is what people navigate with. |

## 5. Query — 12 features

**Use case.** *"Every published claim with no supporting evidence, by
centrality"* — answered inside a document, reviewable in a diff.

Grammar and evaluator **landed** this session. Chosen design: zigvm's shape,
Dataview's repeat-in-any-order pipeline rule, plus `group by` which is missing
in both Notion and Obsidian.

The decisive property is **totality** — every input yields `Ok` or a *named*
`Error`. Dataview evaluates JS and can throw; Notion constrains via UI. Ours is
the only one where an empty result always means "no matches" rather than
possibly "your query was malformed", and that distinction is what makes it safe
to embed a query inside a document.

Renderings (table · board · gallery · list · chart) are `render_mode(eval q)` —
one denotation, many presentations, from Notion's view-over-query factoring.

## 6. Surface — 18 features

**Use case.** *A reviewer opens the corpus over Tailscale, finds a statement,
and cites it — and an agent does the same over JSON.*

| Feature | Chosen design | From | Why |
|---|---|---|---|
| Route ADT | closed sum type; write verb **unrepresentable** | Hermes | The only P4-strength guarantee in the survey. |
| CSP / headers | `default-src 'none'` on every response | Hermes | What makes the no-embed, no-script exclusions coherent. |
| R15 FQDN gate | fail-closed, degradation disclosed | Hermes | Reachability as a runtime check, not an operator promise. |
| Declared navigation | toctree with `:maxdepth:`, `:glob:`, `:hidden:`, `:numbered:` | Sphinx | Reading order becomes an authored decision, not an accident of filing. |
| Node attributes | `visible`, `url`, `open_window` | **Yuque** | Strictly richer than Sphinx: `visible=false` hides without orphaning, and `url` lets the tree hold non-documents. |
| Unreachable check | diagnostic unless `:orphan:` | Sphinx | Distinguishes "unreachable by accident" from "deliberately standalone". |
| Pagination | `pagination_next/prev`, mutually inverse | Docusaurus | A graph is useless for onboarding; this is the narrative path. |
| Search | full-text + block hits + code, PPR-ranked | Sphinx + Obsidian + ours | The corpus has **no search at all** today. Block hits need `^id`. |
| Client-side index | generated, digest-pinned | Sphinx | Makes the static export fully useful offline. |
| JSON API | GET-only through the route ADT | Notion / Yuque | The read model already serialises; only the route is missing. |
| Second render target | plain text | Sphinx `text` builder | Makes "structure separated from presentation" **testable**, not claimed. |
| Presentation rendering | slides from one source | **Yuque** | Commercial proof of the same law; no second authoring step. |
| Extensionless URLs · single-file export | `dirhtml` / `singlehtml` | Sphinx | URLs stop leaking the delivery format; one file for archival. |
| As-of query · timeline | graph at any commit | zigvm | The **structural** half of history — git gives file history only. |
| Reading ergonomics | rail+scrollspy, copy-code (Dream surface); back-to-top, skip-to-content (both) | Docusaurus | Split by surface: the static export keeps its no-script law. |

## 7. Verification and build — 20 features

**Use case.** *Nothing ships that cannot be checked, and no check passes for the
wrong reason.*

This is the family where we lead, and where Sphinx supplies the ladder we are
climbing.

| Feature | Chosen design | From | Why |
|---|---|---|---|
| Render differential | `digest(render(parse d))` per document, four verdicts | Hermes | **Exists nowhere else.** Requires P1. |
| Defects vs notices | defect refuses, notice reports | Hermes | A notice that refuses is a false alarm, and a gate that cries wolf gets bypassed. |
| **Ratchet** | `warnings(HEAD) ≤ warnings(HEAD~1)` | Sphinx `-W` + zigvm 0/0 | Our split is the right *classification*; nothing stops the count growing. |
| **Unified reconciliation core** (S36) | declared vs derived, residue computed; `status` prefers the probe **by construction** | Hermes, second pass | Seven landed declare/probe sites become instances of one functor, and the ratchet's gauges get a deterministic residue to count. Register row HW.8.2.7. |
| Typed suppression | suppress a **code**, not a file | Sphinx | Replaces `allow_example_links`, which disables every link in a file because one line quotes the grammar. |
| Mutation legs | break it, prove the test fails | Hermes | The only L6.5 occupant. It caught a hole in my own tests this session. |
| Doctest | separate builder; groups, setup/cleanup, `:skipif:` | Sphinx | **The most Hermes-aligned feature in the survey**: our corpus documents assert their examples and execute none. |
| Doc coverage | fail-closed; **names, not counts** | Sphinx | `Formal_coverage` answers "what is verified"; nothing answers "what is documented". |
| `literalinclude` | file slices by marker | Sphinx | We quote OCaml by copy-paste; marker slicing makes drift impossible by construction. |
| Interface extraction | **static parse of `.mli`**, never import | ours, correcting Sphinx | P3: autodoc imports modules, so build-time side effects execute. Take the idea, reject the mechanism. |
| Linkcheck | separate build | Sphinx | Network state can never fail a render or perturb the baseline. |
| Dependency tracking → incremental → parallel | in that order | Sphinx | Soundness before speed: `incremental = cold` for every reachable env. Parallelism is unsound before deps are explicit. |
| Check-only build | writes nothing | Sphinx `dummy` | Removes the temptation to inspect output as a proxy for validity. |

## 8. The deliberate non-set

Recorded once, with the property each would cost:

| Excluded | Costs |
|---|---|
| Rich canonical form (Lake, blocks) | **P1** — the render differential becomes meaningless |
| Any generative authoring or answer path | **P2** — every law becomes unstatable |
| Link previews, autodoc import, hosted search | **P3** — determinism |
| MDX, plugins, third-party cards, formulas | **P2/P4** — totality of render |
| Real-time co-editing | the commit, which is the review unit |
| Hosted identity and permission lattice | a second authorisation system that can disagree with the first |
| Sitemap / JSON-LD / RSS | **conditional** on R15 only; returns if the internal-only assumption changes |
| One global severity carrier | **R5** — `alert → verdict` would typecheck; structure-level cause in `[[Unified system synthesis]]` §10.2 |
| Evidence store as a CRDT | **R3/P1** — a same-key/different-payload replay must refuse, never merge; structure-level cause in `[[Unified system synthesis]]` §10.3 |

## 9. Totals

**≈107 admissible features** across seven families. Against the register's 281
rows: 90 already Built, 55 Excluded with invariants, 9 fork-gated, and the
remainder the derivable backlog that `Feature_register.priority` orders.

The synthesis adds no new capability that the register lacks — it **chooses
among designs** for capabilities the register already tracks, which is why no
rows were added and several rows now name a specific upstream design.

Cross-references: `[[Unified domain ontology]]` · `[[Unified functional atlas]]` ·
`[[Unified functional algebra]]` · `[[Unified implementation approach]]` ·
`[[Meta-unification]]`.

Part of [[Knowledge fractal map]].
