# 20260906-0428 ZigVM OCaml HTML, Wiki, ZK and KM Tests: UOS Gleam Mapping

Observed host time: 2026-09-06T04:59:01Z (source review continued after this synchronized clock receipt). **Status: source inventory verified; migration proposed; original OCaml preserved.**

Tags: #fractal-l0 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #zk-adr #zero-muda #km-triad #tailscale-web #checklist-nav

Navigation: Command & Control — [Cockpit](http://nas-1.tail55d152.ts.net:4100/), [Planning](http://nas-1.tail55d152.ts.net:4100/planning), [AG-UI](http://nas-1.tail55d152.ts.net:4100/ag-ui/events); Knowledge Base — [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki), [ZK](http://nas-1.tail55d152.ts.net:4100/zk), [KM](http://nas-1.tail55d152.ts.net:4100/km); Repository & Governance — [Files](http://nas-1.tail55d152.ts.net:4100/files), [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist).

Breadcrumb: [UOS](http://nas-1.tail55d152.ts.net:4100/) / [Files](http://nas-1.tail55d152.ts.net:4100/files) / docs / journal / OCaml web test inventory.

Artifacts: [This report](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260906-0428-ocaml-web-tests-gleam-mapping.md) · [Full source and assertion inventory, JSON](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260906-0428-ocaml-web-tests-inventory.json) · [Individual checks, CSV](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260906-0428-ocaml-web-test-cases.csv) · [Reproducible source selection](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260906-0428-ocaml-web-test-sources.json) · [OCaml extractor](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260906-0428-ocaml-web-test-inventory.ml).

Use the document viewer's Rendered/Raw toggle. Source links below identify local, unchanged ZigVM files; the evidence contains absolute paths and line numbers without importing their implementations into UOS.

## 1. Scope & Trigger

The operator requested a classified list of HTML, wiki, Zettelkasten (ZK), and knowledge-management (KM) tests in ZigVM's OCaml code, an assessment of using them to test UOS's Gleam web UI, and preservation of the original OCaml code.

**Yes: the behavioral contracts can largely become additional Gleam tests.** Pure transformations fit Gleeunit; service behavior needs UOS-specific integration fixtures; layout and interaction require an actual browser; native compiler and formal checks retain a separate OCaml/Hermes boundary. This report proposes that mapping. It does not claim that the ports have been implemented or that any listed source suite passed during this audit.

The scoped inventory contains **64 test/law/runner source files**, **97 supporting tools**, and **1478 statically extracted assertion or check/declaration sites in the primary files**. A source site can execute many times, occur in alternative branches, or belong to a helper. Wrappers delegate to shared laws. These numbers are not independent test-case totals, executed counts, or coverage percentages.

## 2. Pre-State Assessment

### Source identity and preservation

Read-only source: `/home/an/dev/ver/zigvm`, observed HEAD `3cf87fedbc51e37c64eee057c30a553f9d346170`. The selected files already contained 6 dirty/untracked entries. The inventory binds the actual working bytes with SHA-256, rather than treating HEAD as a clean snapshot. All 161 selected source files matched their captured digests when the report was generated. No source suite, browser workflow, writer, or live database was executed or imported.

Selection covers named web/wiki/ZK tests, the laws their drivers call, selected embedded selftests, relevant knowledge-graph/visualization tests, and all directly matched `harness/wiki_*.ml`, `harness/zk_*.ml`, `scripts/wiki_*.ml`, and `scripts/zk_*.ml` auxiliaries. Core implementation companions already represented by their dedicated test drivers are excluded from the auxiliary count. Generated Quint code, third-party dependencies, compiled artifacts, and unrelated VM/SA-plan suites are outside this inventory. The source-selection JSON records every inclusion and scope restriction.

### Actual UOS test surface

The installed package manifests pin Lustre **5.6.0**, Gleeunit **1.9.0**, Mist **6.0.2**, and Wisp **2.2.2**. Existing useful starting points include:

| Existing UOS source | Observed coverage | Extension needed |
|---|---|---|
| [lustre_knowledge_explorer_test.gleam](/home/an/NAS-setup/uos/apps/cepaf_gleam/test/lustre_knowledge_explorer_test.gleam:16) | Four tests for defaults, search/tab/filter/selection updates and inspected view representation | Assert rendered Lustre elements and real click behavior; supply corpus fixtures |
| [zettelkasten_comprehensive_test.gleam](/home/an/NAS-setup/uos/apps/cepaf_gleam/test/zettelkasten_comprehensive_test.gleam:1) | ZK types, entropy/trust, search filters, RAG context and reference extraction | Add the OCaml backlink, transclusion, graph, query and lifecycle contracts where UOS implements those capabilities |
| [knowledge_annotation_actor_test.gleam](/home/an/NAS-setup/uos/apps/cepaf_gleam/test/knowledge_annotation_actor_test.gleam:14) | Document annotations, missing-metadata rejection and actor lifecycle | Bind annotations to fixture documents and rendered pages |
| [page_checker_test.gleam](/home/an/NAS-setup/uos/apps/cepaf_gleam/test/page_checker_test.gleam:18) | Page-alignment calculation, error classification and escalation state | Feed real UOS response bodies through the same checks |
| [unified_fractal_web_verification_test.gleam](/home/an/NAS-setup/uos/apps/cepaf_gleam/test/unified_fractal_web_verification_test.gleam:665) | Catalog checks and OCaml-inspired law helpers | Replace renderer mocks with the renderer used by the product |
| [verification_endpoints_test.gleam](/home/an/NAS-setup/uos/apps/indrajaal_gleam_web/test/verification_endpoints_test.gleam:8) | Direct function calls and aggregation assertions | Exercise the actual HTTP routing, response status, headers and body |

These observations come from source inspection, not a fresh execution of the existing Gleam suites.

## 3. Execution Detail

### Classification and portability

| Code | Gleam approach | What must be retained or adapted |
|---|---|---|
| **G1** | Re-express the contract in Gleeunit against real pure UOS functions or Lustre elements | Translate fixtures/types and expected semantics; retain the OCaml source as reference |
| **G2** | Adapt to Gleam integration tests | Use actual Mist/Wisp handlers, supervised OTP workers, isolated storage and sanitized corpus fixtures; split mixed pure/integration suites |
| **G3** | Gleam-owned scenario and verdict with real browser observations | Keep or adapt a browser driver boundary; screenshots, DOM behavior, network and layout cannot be certified by string or record checks |
| **G4** | Keep native/formal authority and test the boundary from Gleam | OCaml parsing/type guarantees, Gospel/SMT and solver witness checks do not become proofs by translating them into booleans |
| **S** | Supporting tool, excluded from the primary test-source count | A report generator, analyzer, mutator or unfinished script is not automatically a test |

Assignments describe the primary migration mode. A mixed file may need several Gleam test groups. The original OCaml files remain unchanged in every mode.

### Complete primary source list

The count column lists extracted static sites, including dynamic check-call templates. A zero means a driver/observer delegates to another module or uses decision logic outside the extractor's assertion forms; it does not mean the file has no useful verification behavior.

#### Browser automation

| Source | Sites | What it checks and coverage | UOS use | Browser |
|---|---:|---|---|---|
| [harness/test_journal_playwright_contract.ml](/home/an/dev/ver/zigvm/harness/test_journal_playwright_contract.ml) | 10 | Ten pure observation/decision tests, including wrong page/title/digest, overflow, remote assets, missing prompts and page-error mutants. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_playwright_controller.ml](/home/an/dev/ver/zigvm/harness/test_playwright_controller.ml) | 35 | 35 controller checks for breakpoints, touch targets, selectors, artifacts and protocol/source authority; mixed unit and file-integration coverage. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/journal_html_playwright.ml](/home/an/dev/ver/zigvm/harness/journal_html_playwright.ml) | 0 | Real browser observations of title/body identity, journal evidence, resource requests, overflow and screenshots at configured viewports. | **G3** — Gleam scenario/verdict with separately supervised real browser observations. | Actual browser driver (UNRUN here) |
| [harness/journal_bundle_dashboard_playwright.ml](/home/an/dev/ver/zigvm/harness/journal_bundle_dashboard_playwright.ml) | 0 | Real dashboard browser/layout observations, console/page errors and screenshot evidence. | **G3** — Gleam scenario/verdict with separately supervised real browser observations. | Actual browser driver (UNRUN here) |
| [harness/bonsai_ui_playwright.ml](/home/an/dev/ver/zigvm/harness/bonsai_ui_playwright.ml) | 0 | Real browser observations of the Bonsai UI, loading, layout, errors and external resource requests. | **G3** — Gleam scenario/verdict with separately supervised real browser observations. | Actual browser driver (UNRUN here) |
| [harness/zigvm_playwright.ml](/home/an/dev/ver/zigvm/harness/zigvm_playwright.ml) | 0 | Real full-UI browser controller, viewports and project/graph/note user journeys; scope selectors and write fixtures to UOS. | **G3** — Gleam scenario/verdict with separately supervised real browser observations. | Actual browser driver (UNRUN here) |
| [harness/infranodus_full_ui_playwright.ml](/home/an/dev/ver/zigvm/harness/infranodus_full_ui_playwright.ml) | 0 | Full InfraNodus UI browser orchestration; map relevant knowledge/workspace journeys to UOS routes. | **G3** — Gleam scenario/verdict with separately supervised real browser observations. | Actual browser driver (UNRUN here) |

#### Concurrency and scale

| Source | Sites | What it checks and coverage | UOS use | Browser |
|---|---:|---|---|---|
| [harness/test_wiki_selfcheck_parallel.ml](/home/an/dev/ver/zigvm/harness/test_wiki_selfcheck_parallel.ml) | 8 | Ordered results, exactly-once visits, worker bounds, accounting and duplicate/missing-visit negative controls. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/wiki_pipeline_scale.ml](/home/an/dev/ver/zigvm/harness/wiki_pipeline_scale.ml) | 0 | Corpus build/render scaling measurements; performance observations require fresh thresholds and hardware context. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |

#### Formal and gate isolation

| Source | Sites | What it checks and coverage | UOS use | Browser |
|---|---:|---|---|---|
| [harness/wiki_gate_coupling_prover.ml](/home/an/dev/ver/zigvm/harness/wiki_gate_coupling_prover.ml) | 11 | Rete fact-space separation so documentation diagnostics cannot mint a gate-admission verdict. | **G4** — Retain bounded native/compiler/solver oracle; Gleam tests typed boundary. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_tag_laundering_preventer.ml](/home/an/dev/ver/zigvm/harness/zk_tag_laundering_preventer.ml) | 7 | Seven tagged laws for normalization/idempotence and honest feature-status classification. | **G4** — Retain bounded native/compiler/solver oracle; Gleam tests typed boundary. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_query_dsl_fuzzer.ml](/home/an/dev/ver/zigvm/harness/zk_query_dsl_fuzzer.ml) | 7 | Seeded query fuzzing plus seven bounded SMT satisfiability/witness/mutation laws. | **G4** — Retain bounded native/compiler/solver oracle; Gleam tests typed boundary. | No browser in these selected checks; native/VDOM/fixture observations |

#### HTML markup, Markdown and safety

| Source | Sites | What it checks and coverage | UOS use | Browser |
|---|---:|---|---|---|
| [harness/test_typed_html.ml](/home/an/dev/ver/zigvm/harness/test_typed_html.ml) | 7 | Route-derived hrefs, hostile text/attribute escaping, nonempty route index, same-host assets, doctype, report-only markup boundary. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_journal_markdown_html.ml](/home/an/dev/ver/zigvm/harness/test_journal_markdown_html.ml) | 9 | Deterministic HTML, exact prompt preservation, escaped code, provenance, embedded image/video/download evidence. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/wiki_render_laws.ml](/home/an/dev/ver/zigvm/harness/wiki_render_laws.ml) | 46 | 46 named shell/page laws: navigation, query errors, graphs, memory, edit forms, tags, note cards, timelines and inert JSON islands. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/markdown_ast_laws.ml](/home/an/dev/ver/zigvm/harness/markdown_ast_laws.ml) | 59 | Markdown blocks/inlines, normalizer controls, 300 seeded fuzz documents, corpus baseline, token preservation, slug locality and amendments. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/json_embed_laws.ml](/home/an/dev/ver/zigvm/harness/json_embed_laws.ml) | 13 | JSON round-trip, numeric fidelity, control characters, script-closing payloads, seeded fuzzing and fail-closed re-encoding. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/self_render_laws.ml](/home/an/dev/ver/zigvm/harness/self_render_laws.ml) | 8 | Living-ontology HTML escaping, required sections, empty evidence, row arity, CSS fidelity and remote resources. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/slo_render_laws.ml](/home/an/dev/ver/zigvm/harness/slo_render_laws.ml) | 7 | Dashboard CSS fidelity, escaping, doctype, sections and asset isolation. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/slugger_laws.ml](/home/an/dev/ver/zigvm/harness/slugger_laws.ml) | 5 | Five laws over seeded heading sequences: uniqueness, validity, justified suffixes, determinism and coherent counts. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |

#### Knowledge database views

| Source | Sites | What it checks and coverage | UOS use | Browser |
|---|---:|---|---|---|
| [harness/notion.ml](/home/an/dev/ver/zigvm/harness/notion.ml) | 48 | selftest: 48 assertion sites for rich blocks, table/board/gallery/list/calendar/timeline views, typed properties and safe editor seed JSON. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |

#### Knowledge graph randomized properties

| Source | Sites | What it checks and coverage | UOS use | Browser |
|---|---:|---|---|---|
| [harness/test_properties.ml](/home/an/dev/ver/zigvm/harness/test_properties.ml) | 9 | Nine selected QCheck declarations: PageRank/PPR distributions and degeneration, cosine laws, vector codec/quantization and reachability. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |

#### Knowledge graphs and visualization

| Source | Sites | What it checks and coverage | UOS use | Browser |
|---|---:|---|---|---|
| [harness/test_graph_processing.ml](/home/an/dev/ver/zigvm/harness/test_graph_processing.ml) | 12 | Language, synonyms, protected terms, stop-word filtering, inspectable aliases and deterministic graph construction. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_graph_analytics.ml](/home/an/dev/ver/zigvm/harness/test_graph_analytics.ml) | 17 | Topic/excerpt retention, weighted relations, structure and ordered trends. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_graph_intelligence.ml](/home/an/dev/ver/zigvm/harness/test_graph_intelligence.ml) | 21 | Normalization, PageRank, community partition, graph exports and SQLite graph persistence. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_graph_intelligence_workspace.ml](/home/an/dev/ver/zigvm/harness/test_graph_intelligence_workspace.ml) | 7 | Revision-bound retrieval, evidence-grounded summaries, ontology review and generated-note content. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_graph_export.ml](/home/an/dev/ver/zigvm/harness/test_graph_export.ml) | 15 | Source JSON and graph exports with retained statements, graph identity and reproducible output. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_graph_revision.ml](/home/an/dev/ver/zigvm/harness/test_graph_revision.ml) | 12 | Revision increments, node editing/merging, visibility projection, undo/history and playback frames. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_workspace_graph_geometry.ml](/home/an/dev/ver/zigvm/harness/test_workspace_graph_geometry.ml) | 7 | Graph canvas geometry, coordinates and view transformations. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_viz.ml](/home/an/dev/ver/zigvm/harness/test_viz.ml) | 29 | Visualization algebra, dataset/encoding construction and specification checks; not proof that browser pixels are correct. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/viz_algebra_laws.ml](/home/an/dev/ver/zigvm/harness/viz_algebra_laws.ml) | 12 | Typed visualization specification/render laws and escaping. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/vec.ml](/home/an/dev/ver/zigvm/harness/vec.ml) | 16 | selftest: 16 assertion sites for vector encoding, metrics, quantization and nearest-neighbor behavior. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_fractal_fp_atlas_render.ml](/home/an/dev/ver/zigvm/harness/test_fractal_fp_atlas_render.ml) | 0 | Standalone driver calling Fractal_fp_atlas_laws.render ~root:"."; inspect shared renderer/laws, do not double-count. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_fractal_diagram_atlas.ml](/home/an/dev/ver/zigvm/harness/test_fractal_diagram_atlas.ml) | 7 | Fractal diagram/SVG rendering, content completeness and deterministic output. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/fractal_fp_atlas_laws.ml](/home/an/dev/ver/zigvm/harness/fractal_fp_atlas_laws.ml) | 30 | Thirty named tuple laws for atlas core, registry, rendered views and symmetric source markers. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |

#### Live corpus, lints and integrated gates

| Source | Sites | What it checks and coverage | UOS use | Browser |
|---|---:|---|---|---|
| [harness/zigvm_harness.ml](/home/an/dev/ver/zigvm/harness/zigvm_harness.ml) | 223 | Scoped functions only: doc_lint_laws, lint_report_laws, typed_html_laws and selfcheck_wiki; includes live corpus, source guards, scratch writes and bounded formal checks. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |

#### Publication and evidence integrity

| Source | Sites | What it checks and coverage | UOS use | Browser |
|---|---:|---|---|---|
| [harness/test_journal_bundle.ml](/home/an/dev/ver/zigvm/harness/test_journal_bundle.ml) | 15 | Content identity, artifact ordering and bundle invariants. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_journal_bundle_digest.ml](/home/an/dev/ver/zigvm/harness/test_journal_bundle_digest.ml) | 7 | Content fingerprints and digest sensitivity/determinism. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_journal_bundle_io.ml](/home/an/dev/ver/zigvm/harness/test_journal_bundle_io.ml) | 8 | Bounded artifact/file handling and content preservation. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_journal_bundle_transaction.ml](/home/an/dev/ver/zigvm/harness/test_journal_bundle_transaction.ml) | 7 | Prepare/commit/recovery of publication targets and transaction error paths. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_journal_bundle_telemetry.ml](/home/an/dev/ver/zigvm/harness/test_journal_bundle_telemetry.ml) | 11 | Publication telemetry shape, counters and observations. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/publication_chaos_laws.ml](/home/an/dev/ver/zigvm/harness/publication_chaos_laws.ml) | 10 | Ten crash/error laws: rollback before/mid/after rename, no orphan files or residue, idempotent recovery and a real successful-commit control. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_web_pipeline_telemetry.ml](/home/an/dev/ver/zigvm/harness/test_web_pipeline_telemetry.ml) | 3 | Web publication/pipeline telemetry contracts. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |

#### Web routes, components and state

| Source | Sites | What it checks and coverage | UOS use | Browser |
|---|---:|---|---|---|
| [harness/route_laws.ml](/home/an/dev/ver/zigvm/harness/route_laws.ml) | 30 | Route parse/print round trips, hostile identifiers, HTTP methods and source-route consistency. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/web_laws.ml](/home/an/dev/ver/zigvm/harness/web_laws.ml) | 26 | Request/response algebra, dispatch and route-policy invariants; adapt to the UOS request boundary. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_route_algebra.ml](/home/an/dev/ver/zigvm/harness/test_route_algebra.ml) | 0 | Standalone driver for Route_laws.run; avoid counting the same law twice. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_web_algebra.ml](/home/an/dev/ver/zigvm/harness/test_web_algebra.ml) | 0 | Standalone driver for Web_laws.run; avoid counting the same law twice. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_ui_route.ml](/home/an/dev/ver/zigvm/harness/test_ui_route.ml) | 6 | Typed UI route encoding, decoding and invalid-route handling. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_ui_page_registry.ml](/home/an/dev/ver/zigvm/harness/test_ui_page_registry.ml) | 8 | Page registry uniqueness, route coverage and contract metadata. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_ui_component_contract.ml](/home/an/dev/ver/zigvm/harness/test_ui_component_contract.ml) | 11 | Component contracts and registry coverage; adapt component identities to Lustre. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_ui_traceability.ml](/home/an/dev/ver/zigvm/harness/test_ui_traceability.ml) | 10 | Page/component/design traceability and evidence associations. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_ui_pages.ml](/home/an/dev/ver/zigvm/harness/test_ui_pages.ml) | 13 | Virtual-DOM selectors, labels, disabled controls, graph state and note-editor affordances; compiled JavaScript bundle, not a browser execution receipt. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_ui_state.ml](/home/an/dev/ver/zigvm/harness/test_ui_state.ml) | 15 | UI update/state-machine transitions and selected view state. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_workspace_ui_state.ml](/home/an/dev/ver/zigvm/harness/test_workspace_ui_state.ml) | 26 | Workspace search, filters, selections and project/graph edit state. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_slo_render.ml](/home/an/dev/ver/zigvm/harness/test_slo_render.ml) | 0 | Standalone driver for Slo_render_laws.run. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_dream_backend.ml](/home/an/dev/ver/zigvm/harness/test_dream_backend.ml) | 73 | Dream application request/response, permissions and workspace endpoints; rewrite against actual Mist/Wisp handlers. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |

#### Wiki and ZK corpus semantics

| Source | Sites | What it checks and coverage | UOS use | Browser |
|---|---:|---|---|---|
| [harness/docs_wiki_laws.ml](/home/an/dev/ver/zigvm/harness/docs_wiki_laws.ml) | 91 | 91 named check sites over synthetic and live corpora: blocks, links/backlinks, tags, search, graphs, MoCs and navigation. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_wiki_shell.ml](/home/an/dev/ver/zigvm/harness/test_wiki_shell.ml) | 0 | Driver for wiki_render_laws.run and markdown_ast_laws.run; shared definitions, not additional independent cases. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_zk_page_visibility.ml](/home/an/dev/ver/zigvm/harness/test_zk_page_visibility.ml) | 2 | Public/internal/private classifications, explicit metadata and private tags; six fixture rows plus an internal law check. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_wiki_dep_sheaf.ml](/home/an/dev/ver/zigvm/harness/test_wiki_dep_sheaf.ml) | 4 | Dependency closure, isolation between components and bounded traversal depth. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_zk_doctest_runner.ml](/home/an/dev/ver/zigvm/harness/test_zk_doctest_runner.ml) | 5 | Code-fence extraction and delimiter/quote balance checks; does not compile or execute OCaml examples. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_zk_mbse_projection.ml](/home/an/dev/ver/zigvm/harness/test_zk_mbse_projection.ml) | 2 | MBSE ledger serialization and round-trip of capability coordinates and evidence fields. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/test_logseq_profile.ml](/home/an/dev/ver/zigvm/harness/test_logseq_profile.ml) | 12 | Lossless file/profile interpretation, page/block references, properties/tasks, catalog partition and missing/duplicate-row mutants. | **G2** — Split pure laws from adapted Mist/Wisp/OTP and isolated storage integration. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/docs_wiki.ml](/home/an/dev/ver/zigvm/harness/docs_wiki.ml) | 386 | selftest: 386 assertion sites across wiki rendering, ZK authoring, search, backlinks, graph science, query DSL, transclusion and KM lifecycle. | **G1** — Gleeunit over real Gleam transforms/Lustre views; translate fixture semantics. | No browser in these selected checks; native/VDOM/fixture observations |


### The large embedded wiki/ZK/KM selftest

[Docs_wiki.selftest](/home/an/dev/ver/zigvm/harness/docs_wiki.ml:4371) contains 386 assertion sites. It is substantially broader than the 16 mock rendering fixtures currently collected by UOS's OCaml-parity helper. Its main families are:

| Family | Assertions and scenarios to carry forward |
|---|---|
| Markdown and safe markup | Blocks/inlines, literal code, escaping, malformed/empty input, safe JSON data islands |
| Identity and authoring | Slugs, deterministic UUIDs, frontmatter/status, authoring round-trip, confined paths, safe forms |
| Links and discovery | Resolved/missing/aliased wiki links, backlink symmetry, contextual backlinks, unlinked mentions, indexed-versus-naive mention search |
| Navigation and search | Index completeness, tags, note cards, reading-order permutation, search payload completeness and caps |
| Graph science | Degree, PageRank/PPR stochasticity, seed locality, dangling nodes, graph endpoints, reachability and inferred links |
| Discourse and reasoning | Typed support/opposition edges, inbound support, grounded IN/OUT/UNDEC labels, cycles and self-attacks |
| Query DSL | Parse failures, all-note query, filter soundness/commutation, numeric comparisons, deterministic sort, prefix limits and JSON results |
| Transclusion | Whole note and block embeds, link resolution within embeds, missing-target chips, cycles and depth limits |
| Communities and MoCs | Partition completeness, deterministic community IDs, betweenness, structural holes, entry points, freshness and promotion freeze |
| KM memory and lifecycle | Safe memory views, provenance, episodic-note isolation, bounded episode compaction and decision envelopes |
| Temporal knowledge | Half-open edge intervals, snapshot reconstruction, re-added edges, append stability and churn |
| Feature evidence | Coverage semilattice, malformed entries, partition/roll-up consistency and agreement with query results |
| Rich documentation | Callouts, read-only tasks, table of contents and explicit anchors |
| Retrieval chunks | Token-stream conservation, chunk boundaries, stable IDs, duplicate-content disambiguation and empty-input behavior |

The CSV preserves each extracted assertion's source location. Loop expansions are deliberately not invented. For example, the coverage algebra checks all triples of a finite domain from a few assertion sites.

### Auxiliary tools and incomplete implementations

There are 97 auxiliary sources: 32 harness modules and 65 scripts. Six scripts explicitly fail closed with an `[UNIMPLEMENTED]` message. In particular, the named accessibility and dark-mode scripts do **not** establish WCAG or contrast coverage. Other utilities may generate reports, inspect files, calculate metrics or mutate fixtures; their names alone are not proof of a test or an enforcement gate.

| Source | Sites | What it checks and coverage | UOS use | Browser |
|---|---:|---|---|---|
| [scripts/wiki_sidebar_scroll_sync_generator.ml](/home/an/dev/ver/zigvm/scripts/wiki_sidebar_scroll_sync_generator.ml) | 0 | Auxiliary wiki sidebar scroll sync generator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_todo_checkbox_sweeper.ml](/home/an/dev/ver/zigvm/scripts/wiki_todo_checkbox_sweeper.ml) | 0 | Auxiliary wiki todo checkbox sweeper; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_arch_decision_tree_builder.ml](/home/an/dev/ver/zigvm/scripts/wiki_arch_decision_tree_builder.ml) | 0 | Auxiliary wiki arch decision tree builder; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_temporal_snapshot_differ.ml](/home/an/dev/ver/zigvm/scripts/zk_temporal_snapshot_differ.ml) | 0 | Auxiliary zk temporal snapshot differ; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_tag_taxonomy_exporter.ml](/home/an/dev/ver/zigvm/scripts/zk_tag_taxonomy_exporter.ml) | 0 | Auxiliary zk tag taxonomy exporter; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_abandoned_draft_pruner.ml](/home/an/dev/ver/zigvm/scripts/zk_abandoned_draft_pruner.ml) | 0 | Auxiliary zk abandoned draft pruner; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_lfs_asset_manager.ml](/home/an/dev/ver/zigvm/scripts/wiki_lfs_asset_manager.ml) | 0 | Auxiliary wiki lfs asset manager; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_telemetry_alert_mapper.ml](/home/an/dev/ver/zigvm/scripts/zk_telemetry_alert_mapper.ml) | 0 | Auxiliary zk telemetry alert mapper; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_type_definition_linker.ml](/home/an/dev/ver/zigvm/scripts/zk_type_definition_linker.ml) | 0 | Auxiliary zk type definition linker; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_graph_force_directed_layout.ml](/home/an/dev/ver/zigvm/scripts/zk_graph_force_directed_layout.ml) | 0 | Auxiliary zk graph force directed layout; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_inline_comment_extractor.ml](/home/an/dev/ver/zigvm/scripts/wiki_inline_comment_extractor.ml) | 0 | Auxiliary wiki inline comment extractor; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_changelog_to_zk_sync.ml](/home/an/dev/ver/zigvm/scripts/wiki_changelog_to_zk_sync.ml) | 0 | Auxiliary wiki changelog to zk sync; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_mcp_tool_schema_documenter.ml](/home/an/dev/ver/zigvm/scripts/zk_mcp_tool_schema_documenter.ml) | 0 | Auxiliary zk mcp tool schema documenter; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_dark_mode_contrast_checker.ml](/home/an/dev/ver/zigvm/scripts/wiki_dark_mode_contrast_checker.ml) | 0 | Auxiliary wiki dark mode contrast checker; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_subsystem_boundary_visualizer.ml](/home/an/dev/ver/zigvm/scripts/zk_subsystem_boundary_visualizer.ml) | 0 | Auxiliary zk subsystem boundary visualizer; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_adr_decision_log_generator.ml](/home/an/dev/ver/zigvm/scripts/zk_adr_decision_log_generator.ml) | 0 | Auxiliary zk adr decision log generator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_agent_prompt_effectiveness_scorer.ml](/home/an/dev/ver/zigvm/scripts/zk_agent_prompt_effectiveness_scorer.ml) | 0 | Auxiliary zk agent prompt effectiveness scorer; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_fixture_to_markdown_converter.ml](/home/an/dev/ver/zigvm/scripts/wiki_fixture_to_markdown_converter.ml) | 0 | Auxiliary wiki fixture to markdown converter; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_feature_flag_doc_sync.ml](/home/an/dev/ver/zigvm/scripts/zk_feature_flag_doc_sync.ml) | 0 | Auxiliary zk feature flag doc sync; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_dummy_vault_for_benchmarking.ml](/home/an/dev/ver/zigvm/scripts/zk_dummy_vault_for_benchmarking.ml) | 0 | Auxiliary zk dummy vault for benchmarking; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_symlink_detector.ml](/home/an/dev/ver/zigvm/scripts/wiki_symlink_detector.ml) | 0 | Auxiliary wiki symlink detector; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_editor_config_generator.ml](/home/an/dev/ver/zigvm/scripts/zk_editor_config_generator.ml) | 0 | Auxiliary zk editor config generator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_onboarding_guide_generator.ml](/home/an/dev/ver/zigvm/scripts/wiki_onboarding_guide_generator.ml) | 0 | Auxiliary wiki onboarding guide generator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_shell_alias_installer.ml](/home/an/dev/ver/zigvm/scripts/zk_shell_alias_installer.ml) | 0 | Auxiliary zk shell alias installer; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_template_variable_substitutor.ml](/home/an/dev/ver/zigvm/scripts/zk_template_variable_substitutor.ml) | 0 | Auxiliary zk template variable substitutor; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_accessibility_auditor.ml](/home/an/dev/ver/zigvm/scripts/wiki_accessibility_auditor.ml) | 0 | Auxiliary wiki accessibility auditor; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_data_flow_diagram_generator.ml](/home/an/dev/ver/zigvm/scripts/zk_data_flow_diagram_generator.ml) | 0 | Auxiliary zk data flow diagram generator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_incident_postmortem_linker.ml](/home/an/dev/ver/zigvm/scripts/zk_incident_postmortem_linker.ml) | 0 | Auxiliary zk incident postmortem linker; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_error_code_cataloger.ml](/home/an/dev/ver/zigvm/scripts/zk_error_code_cataloger.ml) | 0 | Auxiliary zk error code cataloger; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_tech_debt_aggregator.ml](/home/an/dev/ver/zigvm/scripts/zk_tech_debt_aggregator.ml) | 0 | Auxiliary zk tech debt aggregator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_component_maturity_scorer.ml](/home/an/dev/ver/zigvm/scripts/wiki_component_maturity_scorer.ml) | 0 | Auxiliary wiki component maturity scorer; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_adr_status_tracker.ml](/home/an/dev/ver/zigvm/scripts/zk_adr_status_tracker.ml) | 0 | Auxiliary zk adr status tracker; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_search_index_size_monitor.ml](/home/an/dev/ver/zigvm/scripts/wiki_search_index_size_monitor.ml) | 0 | Auxiliary wiki search index size monitor; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_release_notes_assembler.ml](/home/an/dev/ver/zigvm/scripts/wiki_release_notes_assembler.ml) | 0 | Auxiliary wiki release notes assembler; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_security_threat_modeler.ml](/home/an/dev/ver/zigvm/scripts/zk_security_threat_modeler.ml) | 0 | Auxiliary zk security threat modeler; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_deprecated_usage_warner.ml](/home/an/dev/ver/zigvm/scripts/wiki_deprecated_usage_warner.ml) | 0 | Auxiliary wiki deprecated usage warner; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_typography_scale_enforcer.ml](/home/an/dev/ver/zigvm/scripts/wiki_typography_scale_enforcer.ml) | 0 | Auxiliary wiki typography scale enforcer; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_note_length_histogram_generator.ml](/home/an/dev/ver/zigvm/scripts/zk_note_length_histogram_generator.ml) | 0 | Auxiliary zk note length histogram generator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_deployment_env_validator.ml](/home/an/dev/ver/zigvm/scripts/wiki_deployment_env_validator.ml) | 0 | Auxiliary wiki deployment env validator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_bottleneck_predictor.ml](/home/an/dev/ver/zigvm/scripts/zk_bottleneck_predictor.ml) | 0 | Auxiliary zk bottleneck predictor; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_sprint_goal_extractor.ml](/home/an/dev/ver/zigvm/scripts/zk_sprint_goal_extractor.ml) | 0 | Auxiliary zk sprint goal extractor; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_user_journey_pathfinder.ml](/home/an/dev/ver/zigvm/scripts/zk_user_journey_pathfinder.ml) | 0 | Auxiliary zk user journey pathfinder; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_allocator_pattern_cataloger.ml](/home/an/dev/ver/zigvm/scripts/zk_allocator_pattern_cataloger.ml) | 0 | Auxiliary zk allocator pattern cataloger; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_link_density_evaluator.ml](/home/an/dev/ver/zigvm/scripts/zk_link_density_evaluator.ml) | 0 | Auxiliary zk link density evaluator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_frontmatter_json_schema_exporter.ml](/home/an/dev/ver/zigvm/scripts/zk_frontmatter_json_schema_exporter.ml) | 0 | Auxiliary zk frontmatter json schema exporter; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_opam_deps_checker.ml](/home/an/dev/ver/zigvm/scripts/zk_opam_deps_checker.ml) | 1 | Auxiliary zk opam deps checker; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_gitignore_auditor.ml](/home/an/dev/ver/zigvm/scripts/zk_gitignore_auditor.ml) | 0 | Auxiliary zk gitignore auditor; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_conflict_resolution_helper.ml](/home/an/dev/ver/zigvm/scripts/zk_conflict_resolution_helper.ml) | 0 | Auxiliary zk conflict resolution helper; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_epic_to_slice_validator.ml](/home/an/dev/ver/zigvm/scripts/zk_epic_to_slice_validator.ml) | 0 | Auxiliary zk epic to slice validator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_rss_feed_generator.ml](/home/an/dev/ver/zigvm/scripts/wiki_rss_feed_generator.ml) | 0 | Auxiliary wiki rss feed generator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_semantic_similarity_clusterer.ml](/home/an/dev/ver/zigvm/scripts/zk_semantic_similarity_clusterer.ml) | 0 | Auxiliary zk semantic similarity clusterer; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_orphaned_block_anchor_sweeper.ml](/home/an/dev/ver/zigvm/scripts/zk_orphaned_block_anchor_sweeper.ml) | 0 | Auxiliary zk orphaned block anchor sweeper; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_markdown_table_formatter.ml](/home/an/dev/ver/zigvm/scripts/zk_markdown_table_formatter.ml) | 0 | Auxiliary zk markdown table formatter; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_ci_artifact_sweeper.ml](/home/an/dev/ver/zigvm/scripts/wiki_ci_artifact_sweeper.ml) | 0 | Auxiliary wiki ci artifact sweeper; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_cross_cutting_concern_tracker.ml](/home/an/dev/ver/zigvm/scripts/zk_cross_cutting_concern_tracker.ml) | 0 | Auxiliary zk cross cutting concern tracker; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_responsive_css_validator.ml](/home/an/dev/ver/zigvm/scripts/wiki_responsive_css_validator.ml) | 0 | Auxiliary wiki responsive css validator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_slo_sli_dashboarder.ml](/home/an/dev/ver/zigvm/scripts/wiki_slo_sli_dashboarder.ml) | 0 | Auxiliary wiki slo sli dashboarder; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_mutant_code_context_fetcher.ml](/home/an/dev/ver/zigvm/scripts/zk_mutant_code_context_fetcher.ml) | 0 | Auxiliary zk mutant code context fetcher; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_system_context_mapper.ml](/home/an/dev/ver/zigvm/scripts/wiki_system_context_mapper.ml) | 0 | Auxiliary wiki system context mapper; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/wiki_performance_benchmark_plotter.ml](/home/an/dev/ver/zigvm/scripts/wiki_performance_benchmark_plotter.ml) | 0 | Auxiliary wiki performance benchmark plotter; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_meeting_notes_action_itemizer.ml](/home/an/dev/ver/zigvm/scripts/zk_meeting_notes_action_itemizer.ml) | 0 | Auxiliary zk meeting notes action itemizer; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_vault_permissions_guard.ml](/home/an/dev/ver/zigvm/scripts/zk_vault_permissions_guard.ml) | 0 | Auxiliary zk vault permissions guard; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_flaky_test_runbook_generator.ml](/home/an/dev/ver/zigvm/scripts/zk_flaky_test_runbook_generator.ml) | 0 | Auxiliary zk flaky test runbook generator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_query_performance_profiler.ml](/home/an/dev/ver/zigvm/scripts/zk_query_performance_profiler.ml) | 0 | Auxiliary zk query performance profiler; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [scripts/zk_backlog_aging_report.ml](/home/an/dev/ver/zigvm/scripts/zk_backlog_aging_report.ml) | 0 | Auxiliary zk backlog aging report; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_query_performance_profiler.ml](/home/an/dev/ver/zigvm/harness/zk_query_performance_profiler.ml) | 0 | Auxiliary zk query performance profiler; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_agent_write_quota_enforcer.ml](/home/an/dev/ver/zigvm/harness/zk_agent_write_quota_enforcer.ml) | 0 | Auxiliary zk agent write quota enforcer; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_graph_isomorphism_checker.ml](/home/an/dev/ver/zigvm/harness/zk_graph_isomorphism_checker.ml) | 0 | Auxiliary zk graph isomorphism checker; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_discourse_edge_inverter.ml](/home/an/dev/ver/zigvm/harness/zk_discourse_edge_inverter.ml) | 0 | Auxiliary zk discourse edge inverter; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_sqlite_db_encryption_wrapper.ml](/home/an/dev/ver/zigvm/harness/zk_sqlite_db_encryption_wrapper.ml) | 0 | Auxiliary zk sqlite db encryption wrapper; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_block_anchor_uniqueness.ml](/home/an/dev/ver/zigvm/harness/zk_block_anchor_uniqueness.ml) | 0 | Auxiliary zk block anchor uniqueness; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_page_rank_calculator.ml](/home/an/dev/ver/zigvm/harness/zk_page_rank_calculator.ml) | 0 | Auxiliary zk page rank calculator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_mcp_auth_token_validator.ml](/home/an/dev/ver/zigvm/harness/zk_mcp_auth_token_validator.ml) | 0 | Auxiliary zk mcp auth token validator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_moc_freeze_enforcer.ml](/home/an/dev/ver/zigvm/harness/zk_moc_freeze_enforcer.ml) | 0 | Auxiliary zk moc freeze enforcer; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_graph_betweenness_calculator.ml](/home/an/dev/ver/zigvm/harness/zk_graph_betweenness_calculator.ml) | 0 | Auxiliary zk graph betweenness calculator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_transclusion_depth_limiter.ml](/home/an/dev/ver/zigvm/harness/zk_transclusion_depth_limiter.ml) | 0 | Auxiliary zk transclusion depth limiter; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_query_ast_mutator.ml](/home/an/dev/ver/zigvm/harness/zk_query_ast_mutator.ml) | 0 | Auxiliary zk query ast mutator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_comptime_logic_documenter.ml](/home/an/dev/ver/zigvm/harness/zk_comptime_logic_documenter.ml) | 0 | Auxiliary zk comptime logic documenter; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_law_to_test_traceability_matrix.ml](/home/an/dev/ver/zigvm/harness/zk_law_to_test_traceability_matrix.ml) | 0 | Auxiliary zk law to test traceability matrix; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/wiki_theme_token_injector.ml](/home/an/dev/ver/zigvm/harness/wiki_theme_token_injector.ml) | 0 | Auxiliary wiki theme token injector; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_gate_isolation_prover.ml](/home/an/dev/ver/zigvm/harness/zk_gate_isolation_prover.ml) | 0 | Auxiliary zk gate isolation prover; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_transclusion_loop_injector.ml](/home/an/dev/ver/zigvm/harness/zk_transclusion_loop_injector.ml) | 0 | Auxiliary zk transclusion loop injector; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_doc_to_code_coverage_runner.ml](/home/an/dev/ver/zigvm/harness/zk_doc_to_code_coverage_runner.ml) | 0 | Auxiliary zk doc to code coverage runner; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/wiki_content_security_policy_generator.ml](/home/an/dev/ver/zigvm/harness/wiki_content_security_policy_generator.ml) | 0 | Auxiliary wiki content security policy generator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/wiki_cache_poisoning_detector.ml](/home/an/dev/ver/zigvm/harness/wiki_cache_poisoning_detector.ml) | 0 | Auxiliary wiki cache poisoning detector; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_markdown_to_html_compiler.ml](/home/an/dev/ver/zigvm/harness/zk_markdown_to_html_compiler.ml) | 0 | Auxiliary zk markdown to html compiler; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_formal_spec_to_doc_prover.ml](/home/an/dev/ver/zigvm/harness/zk_formal_spec_to_doc_prover.ml) | 0 | Auxiliary zk formal spec to doc prover; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_query_live_executor.ml](/home/an/dev/ver/zigvm/harness/zk_query_live_executor.ml) | 0 | Auxiliary zk query live executor; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_typed_edge_extractor.ml](/home/an/dev/ver/zigvm/harness/zk_typed_edge_extractor.ml) | 0 | Auxiliary zk typed edge extractor; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/wiki_snippet_executor_validator.ml](/home/an/dev/ver/zigvm/harness/wiki_snippet_executor_validator.ml) | 0 | Auxiliary wiki snippet executor validator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_api_contract_doc_verifier.ml](/home/an/dev/ver/zigvm/harness/zk_api_contract_doc_verifier.ml) | 0 | Auxiliary zk api contract doc verifier; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/wiki_sidebar_tree_generator.ml](/home/an/dev/ver/zigvm/harness/wiki_sidebar_tree_generator.ml) | 0 | Auxiliary wiki sidebar tree generator; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_frontmatter_schema_enforcer.ml](/home/an/dev/ver/zigvm/harness/zk_frontmatter_schema_enforcer.ml) | 0 | Auxiliary zk frontmatter schema enforcer; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_contradiction_prover.ml](/home/an/dev/ver/zigvm/harness/zk_contradiction_prover.ml) | 0 | Auxiliary zk contradiction prover; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_compliance_audit_trail_exporter.ml](/home/an/dev/ver/zigvm/harness/zk_compliance_audit_trail_exporter.ml) | 0 | Auxiliary zk compliance audit trail exporter; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_discourse_logic_checker.ml](/home/an/dev/ver/zigvm/harness/zk_discourse_logic_checker.ml) | 0 | Auxiliary zk discourse logic checker; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |
| [harness/zk_cryptographic_note_signer.ml](/home/an/dev/ver/zigvm/harness/zk_cryptographic_note_signer.ml) | 0 | Auxiliary zk cryptographic note signer; inventory records source and implementation signals, without assuming an executable test suite. | **S** — Reference utility; promote only with actual assertions and observed execution. | No browser in these selected checks; native/VDOM/fixture observations |


## 4. Root Cause Analysis

The main migration risk is confusing a test's name or aggregate result with observation of the UOS UI.

1. [ocaml_parity_verifier.gleam:204](/home/an/NAS-setup/uos/apps/cepaf_gleam/src/cepaf_gleam/verification/ocaml_parity_verifier.gleam:204) calls `mock_ast_render_block`; inline laws call `mock_ast_render_inline`. They validate those helpers, not the product document renderer.
2. [browser_emulation_bridge.gleam:44](/home/an/NAS-setup/uos/apps/cepaf_gleam/src/cepaf_gleam/verification/browser_emulation_bridge.gleam:44) sets `passed_count` from the supplied `test_count` and sets `failed_count` to zero. It does not launch or observe a browser.
3. [ocaml_differential_oracle.gleam:36](/home/an/NAS-setup/uos/apps/cepaf_gleam/src/cepaf_gleam/verification/ocaml_differential_oracle.gleam:36) decides mapping parity using `file_count == 432`; its digest comparator only compares supplied strings. Neither operation demonstrates equivalent OCaml and Gleam executions.
4. [indrajaal_gleam_web.gleam:914](/home/an/NAS-setup/uos/apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam:914) obtains raw document text, processes custom tags, and calls browser-side `marked.parse` (with a JavaScript fallback). A successful HTTP response or a Gleam string-rendering test does not cover the resulting DOM, link behavior or injection handling.

The earlier journal's claim that all OCaml testing functionality had already been ported is broader than these observed implementations support. This inventory therefore treats current parity, browser execution and port completeness as unverified rather than adopting that claim.

## 5. Fix Taxonomy

This appendix records the static ZigVM inventory within the wider cross-project audit. Newly authored UOS checks and browser observations are reported separately; the listed OCaml ports remain proposed.

| Proposed Gleam test group | Original families | Real UOS target and required assertions |
|---|---|---|
| `html_safety_test` | typed HTML, JSON embedding, wiki shell | Production Lustre/document rendering; hostile text/attributes/URLs remain data, valid document structure, meaningful empty states |
| `markdown_contract_test` | Markdown AST, Docs_wiki render laws | Actual parser/renderer selected by UOS; headings, lists, tables, fences, TOC, exact content preservation and defined normalization |
| `wiki_navigation_test` | route/web laws, wiki shell | Actual wiki/ZK/KM/file routes; current item, breadcrumbs, sidebar, previous/next, rendered/raw toggle and full Tailnet links |
| `zk_links_and_transclusion_test` | Docs_wiki, dependency sheaf | UOS corpus model; backlink symmetry, alias/missing-target handling, contextual links, cycle/depth rejection |
| `zk_query_and_search_test` | query DSL, QCheck, vector selftest | Real ZK query/search implementation; filter soundness, order and limit laws, empty and malformed queries, deterministic retrieval |
| `knowledge_graph_laws_test` | graph suites, PPR, grounded semantics | UOS graph functions; probability distributions, partitions, reachable endpoints, graph revisions and evidence-grounded summaries |
| `km_lifecycle_test` | MoCs, temporal edges, episodic notes, MBSE, Logseq | UOS KM models; stable IDs, author/provenance retention, stale/frozen states, bounded history and round-trip preservation |
| `knowledge_view_test` | Notion views, UI state/components | Real `knowledge_explorer.view` and update functions; table/board/list/calendar equivalents only where implemented, selection/filter state, safe empty/error states |
| `web_http_contract_test` | Dream backend, live wiki selfcheck | Actual Mist/Wisp handler or isolated test listener; status, MIME type, content identity, path confinement, permissions, missing files and JSON validity |
| `publication_recovery_test` | journal bundle, crash laws | UOS publication worker and isolated temporary files; failed writes, rollback, recovery idempotence and non-vacuous successful commit |
| `wiki_worker_test` | parallel selfcheck and scaling | Supervised BEAM workers; ordered output, exactly-once accounting, timeout/crash handling, bounded worker counts and measured latency |
| `web_browser_contract_test` | real Playwright runners | Actual served UOS UI; clicks, keyboard focus, toggle/copy behavior, mobile overflow, touch targets, console/network errors and captured artifacts |
| `ocaml_oracle_boundary_test` | solver/native law families | Bounded process protocol; fixture ID, original/candidate revisions, result/digest payload, witness, timeout/error and explicit disagreement handling |

Gleeunit discovers `_test` functions, and Lustre exposes element rendering plus view-query helpers suitable for the pure view layer. Those are practical existing building blocks, not a substitute for browser observation. [Gleeunit documentation](https://hexdocs.pm/gleeunit/gleeunit.html), [Lustre element documentation](https://lustre.hexdocs.pm/lustre/element.html), [Lustre view queries](https://hexdocs.pm/lustre/lustre/dev/query.html). The same needed rendering/query functions were also checked in UOS's installed Lustre 5.6.0 source.

## 6. Patterns & Anti-Patterns Discovered

Preserve the original implementation as an independent reference. Write new Gleam tests against the functions and routes the product actually uses. Share fixture meaning and expected contracts, not a second mock implementation. Give each migrated case an origin path, function, line, fixture ID, source digest and UOS revision.

Retain negative controls: dropped backlinks, malformed input, duplicate/missing worker visits, altered digests, wrong routes and failed writes must produce failures. Empty required suites and unavailable browser/solver observations must remain `UNRUN` or `Blocked`. Never generate passing totals from expected counts.

Port semantics deliberately. ZigVM's relative `.html` links and blanket remote-URL restrictions need adaptation to UOS's full Tailscale FQDN policy: same-origin absolute navigation is allowed. Source-specific Markdown quirks, generated slug formats, CSS classes, and Oracle byte serialization are not automatically UOS requirements. Prefer semantic DOM/AST comparison with narrowly declared normalization; preserve whitespace in inline/code content and test that the normalizer detects meaningful changes.

The source also contains weak checks worth strengthening in the new suite: `docs_wiki_laws.ml` includes an empty-output length check that cannot fail and a `linked-not-mention` expression ending in `&& false`. The original remains untouched. `test_wiki_selfcheck_parallel.ml` prints “34 laws passed,” but the visible six worker configurations produce 24 checks plus four final checks: its printed count should not be treated as an inventory oracle.

## 7. Verification Matrix

| Verification | Result and scope |
|---|---|
| OCaml AST inventory | 161 selected source files parsed without executing them |
| Source identity | HEAD and selected dirty-file manifest recorded; SHA-256 bound to actual working bytes |
| Source preservation | 161/161 captured source digests unchanged at report generation |
| Primary source/check classification | 64 files; 1478 extracted sites; wrappers and dynamic expansion explicitly disclosed |
| Auxiliary classification | 97 tools excluded from primary count; six explicit unfinished scripts identified |
| UOS target review | Actual Gleam source, package manifests and selected existing tests inspected |
| Original OCaml tests | **UNRUN**; no assertion here that they pass |
| Proposed Gleam ports | **PLANNED**; no port implementation or passing result claimed |
| Browser, benchmarks, solvers and full system tests | **UNRUN** in this inventory task |
| UOS documentation gates and live report | Not executed by this static appendix; source preservation is recorded in the inventory JSON |

<details>
<summary>Comprehensive verification checklist — 5 domains, 18 checkpoints</summary>

The checklist records this task's scope. Runtime checkpoints left unrun are not passing states. The repository `checklist` command independently checks contract/file presence and cannot certify these runtime behaviors.

### Domain 1: Metadata, Timestamp & Tailscale Navigation

- [x] **CHK-01-TIME**: Synchronized host time observed; all new artifact names use YYYYMMDD-HHSS.
- [x] **CHK-02-TAIL**: Full clickable Tailnet navigation and artifact links included.
- [x] **CHK-03-FRACT**: Applicable fractal layers assigned.
- [x] **CHK-04-KM**: Knowledge lineage linked through [canonical KM article](http://nas-1.tail55d152.ts.net:4100/files/docs/wiki/20260905-1721-uos-master-knowledge-graph-and-living-ontology.md), [[wiki:20260905-1721-uos-master-knowledge-graph-and-living-ontology]] and [[zk:ADR-001]]; transclusion execution remains unrun.

### Domain 2: Zero-Muda Purity & Storage Safety

- [x] **CHK-05-MUDA**: This task adds evidence and an OCaml inventory helper; no forbidden runtime/dependency added.
- [x] **CHK-06-GRAPH**: No foreign NIF or graph runtime introduced.
- [x] **CHK-07-DRIVE**: No drive operation or storage-interlock change; interlock runtime test unrun.

### Domain 3: Testing Gold Standard & Mathematical Gates

- [ ] **CHK-08-C1C8**: UI categories mapped; full UI execution **UNRUN**.
- [ ] **CHK-09-MATH**: No fresh mathematical-gate result; **UNRUN**.
- [ ] **CHK-10-9MOD**: Source modalities classified; nine-modality execution **UNRUN**.
- [ ] **CHK-11-REGR**: Proposed regression mapping supplied; full regression execution **UNRUN**.

### Domain 4: Cross-Language Control & Observability

- [x] **CHK-12-GLEAM**: Proposed supervision and tests remain in Gleam/OTP.
- [x] **CHK-13-HERMES**: Native/formal OCaml evidence authority retained.
- [x] **CHK-14-ZIGVM**: Original ZigVM source bytes preserved.
- [x] **CHK-15-MAX**: Inference daemon boundary unchanged and uninvolved.
- [ ] **CHK-16-OTEL**: Telemetry test sources classified; live end-to-end trace verification **UNRUN**.

### Domain 5: Tri-Sovereign Governance & Jujutsu Monorepo

- [ ] **CHK-17-SOV**: This is a single-agent inventory, with no new tri-sovereign admission claimed.
- [x] **CHK-18-JJ**: Standalone Jujutsu used for UOS review; no Git mutation.

</details>

## 8. Files Modified

This appendix comprises the five linked inventory/report artifacts; the wider audit also creates UOS verification checks and browser evidence. The `.ml` artifact is a newly authored, read-only inventory extractor; it parses original source and writes its output under `/tmp`. Original ZigVM OCaml, imported Hermes OCaml, UOS application code, existing tests, and prior journals remain unchanged by this inventory task.

To reproduce the extraction, invoke the linked OCaml extractor with the linked source-selection JSON and a fresh `/tmp` output filename using the already installed OCaml compiler, Bos, Yojson and compiler-libs. The extractor checks source identity while reading, has bounded file sizes/counts, and does not load or run inspected code. The final JSON also records source-preservation comparison and the generated artifacts' checks.

## 9. Architectural Observations

The appropriate target is a layered test system:

ASCII companion (same nodes and directed edges as the Mermaid source):

```text
S -> C -> U -> P -> D
     C -> I -> H -> D
     C -> B -> W -> D
S -> O ----------> D
S preserved sources; C contracts/fixtures; U unit/property; I integration;
B browser observations; O bounded native oracle; P model/view;
H HTTP/state; W served UI; D revision-bound differential evidence.
```

~~~mermaid
flowchart TD
  S[Preserved ZigVM OCaml sources] --> C[Origin-linked contracts and fixtures]
  C --> U[Gleam unit and property tests]
  C --> I[Gleam service and worker integration tests]
  C --> B[Real browser scenario observations]
  S --> O[Independent bounded OCaml or formal oracle]
  U --> P[Actual UOS model and Lustre views]
  I --> H[Actual UOS HTTP handlers and isolated state]
  B --> W[Served UOS web UI]
  O --> D[Revision-bound differential evidence]
  P --> D
  H --> D
  W --> D
~~~

The diagram is a proposed architecture. It does not claim that a browser or oracle bridge already performs those executions. Keep the browser/solver processes isolated and supervised; Gleam owns scheduling, typed requests, timeouts and result classification.

## 10. Remaining Gaps

The inventory answers feasibility and identifies the tests; implementation remains a separate phase. The first useful change is to connect test fixtures to the real UOS rendering/HTTP path and make missing observations fail closed. Next add wiki/ZK/KM semantic contracts, then isolated publication/worker tests, and finally browser journeys and independent oracle comparisons.

Native TyXML structural type guarantees require an explicit UOS type/validation design. An OCaml delimiter-balance doctest is not compiler execution; a real Gleam doctest needs the Gleam compiler. Ocaml-specific solver witnesses, Gospel contracts and finite-domain proofs retain native authority until separately reconstructed and verified. Browser accessibility and contrast need real DOM/computed-style observations; the unfinished source scripts supply no passing coverage.

The audit is scoped to the listed sources and current working bytes. It does not certify every OCaml file in ZigVM or all existing UOS functionality. External writers were not quiesced because no source implementation was admitted; future fixture/code admission must follow UOS's source-governance requirements.

## 11. Metrics Summary

Source files: 64 primary + 97 auxiliary. Extracted primary sites: 1478. Runtime executions of original sources: 0. Coverage percentages: not measured. Actual browser drivers in the primary list: 5.

Chrony reported normal leap status with observed host-to-NTP offset 0.000086308 seconds slow. This is distinct from a model-clock or agent-context delta; neither of those was inferred.

## 12. STAMP & Constitutional Alignment

The principal hazard is false evidence: a dashboard can advertise passing UI coverage while receiving no UI observations. The proposed control is an explicit chain from source contract to fixture, real product operation, recorded observation and independently checkable verdict. Counts, mock renderers and successful transport alone cannot admit a capability.

This audit preserves dirty external sources and avoids live DB/WAL/SHM, credential material, compiler caches and generated dependency imports. It performs no source admission, deployment, service restart, destructive storage operation or external communication. Jujutsu records the UOS evidence additions.

## 13. Conclusion

Most HTML/wiki/ZK/KM behavior contracts can become additional Gleam tests for UOS. The full classified source list and individual assertion locations are supplied. Original OCaml is preserved as reference and, where appropriate, independent native authority. The present UOS mocks and supplied-count checks are not evidence that those contracts already test the production web UI.

Previous: [Installed skills repair](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260906-0300-installed-skills-repair-journal.md). Next: [Full inventory](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260906-0428-ocaml-web-tests-inventory.json).

System footer: [nas-1 Tailnet cockpit](http://nas-1.tail55d152.ts.net:4100/) · [vm-1 peer runtime](http://vm-1.tail55d152.ts.net:8088) · UOS target: OTP 29; runtime health is not certified by this source inventory.
