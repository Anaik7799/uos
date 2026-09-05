---
id: hermes-imported-20260730-ocaml-scripting-phase7-zk-wiki
status: published
type: reference
generated: false
allow_example_links: true
migrated_from: zigvm/docs/journal/20260730-ocaml-scripting-phase7-zk-wiki.md
ktype: source
maturity: incubating
domain: imported-journals
created: 2026-08-08
---
# Journal: Phase 7 - Megascale Discovery of 50 ZK & Wiki Scripting Usecases

**Date:** July 30, 2026  
**Author:** Cybernetic Architect  
**Status:** APPROVED & ARCHIVED  
**Reference Docs:** `docs/OCAML_SCRIPTING_SOP.md`, `skills/wiki-design/SKILL.md`, `skills/zk-knowledge-base/SKILL.md`

---

## 1. Executive Summary

In Phase 7, we focus our fractal analysis exclusively on the **Wiki and Zettelkasten (ZK)** knowledge base—the system's queryable self-model and primary agentic interface. 

We have identified exactly **50 NEW, highly specialized OCaml scripting targets** distributed across the L0-L9 architecture. These usecases govern Notion-style rendering, Dung grounded semantics, bidirectional graph integrity, MCP agent symbiosis, and temporal anomaly detection. We performed deep STPA and FMEA safety analysis to assign criticality (SIF/EJ) and map their execution boundaries between the compiled harness and standalone external scripts.

---

## 2. Discovery: 50 ZK & Wiki Scripting Usecases (L0 - L9)

### L0: Repository & Environment
1. **`zk_vault_backup_manager.ml`**: Auto-commits and tarballs the `/docs/zk` vault periodically.
2. **`wiki_static_asset_bundler.ml`**: Minimizes and inlines CSS for the static `--docs-wiki` html export.
3. **`zk_frontmatter_schema_enforcer.ml`**: Enforces strict YAML schemas (type, status, aliases) on all ZK markdown files.
4. **`wiki_broken_image_sweeper.ml`**: Scans wiki pages for missing image/asset references.
5. **`zk_git_history_indexer.ml`**: Indexes git commit history into the ZK bi-temporal graph.

### L1: Artifact & Plan
6. **`zk_moc_hierarchy_builder.ml`**: Autogenerates a top-level Index map of content by finding roots in the ZK graph.
7. **`zk_adr_to_task_linker.ml`**: Analyzes ZK ADR notes and cross-references them to SQLite `slice_backlog` entries.
8. **`wiki_breadcrumb_validator.ml`**: Ensures the folder hierarchy cleanly maps to valid breadcrumb trails in the Wiki UI.
9. **`zk_episodic_memory_pruner.ml`**: Archives or summarizes old `docs/zk/episodic/` notes to keep the active graph lean.
10. **`zk_community_cluster_namer.ml`**: Uses TF-IDF to auto-suggest titles for generated MoC (Map of Content) clusters.

### L2: Subsystem & Architecture
11. **`zk_architecture_claim_verifier.ml`**: Scans ZK notes of type `claim` involving system architecture and checks if they are `@supports` by a code reference.
12. **`zk_subsystem_doc_coverage.ml`**: Correlates ZK notes to the 33 Subsystems to identify under-documented architectures.
13. **`wiki_sidebar_tree_generator.ml`**: Dynamically constructs the JSON/HTML for the Notion-like persistent sidebar from the file system.
14. **`zk_graph_betweenness_calculator.ml`**: Calculates Betweenness Centrality for all ZK notes to find crucial architectural chokepoints.
15. **`zk_structural_hole_bridger.ml`**: Proactively suggests creating new notes to connect disparate ZK graph clusters.

### L3: Module & Source
16. **`zk_code_transclusion_updater.ml`**: Verifies that code block transclusions (`![[file.zig#^id]]`) haven't drifted from the source `.zig` files.
17. **`wiki_callout_syntax_linter.ml`**: Validates Obsidian-style callout syntax (`> [!note]`) to ensure correct rendering.
18. **`zk_typed_edge_extractor.ml`**: Parses `[[T|@rel]]` syntax in markdown into a strict OCaml ADT for the graph database.
19. **`zk_block_anchor_uniqueness.ml`**: Ensures all `^id` block anchors are globally unique across the entire wiki.
20. **`zk_source_code_indexer.ml`**: Feeds `src/*.zig` files into the ZK search index with kind `code`.

### L4: Feature Slice & Observability
21. **`zk_query_live_executor.ml`**: Evaluates embedded ```zkquery``` code fences in markdown and replaces them with rendered tables in the wiki export.
22. **`zk_anomaly_dashboard_generator.ml`**: Turns the `--zk-anomalies` output into a beautiful Kanban-style triage board for agents.
23. **`zk_telemetry_vector_embedder.ml`**: Converts SDLC telemetry metrics into ZK nodes for semantic querying.
24. **`wiki_page_readability_scorer.ml`**: Runs Flesch-Kincaid analysis on ZK notes to ensure documentation remains scannable.
25. **`zk_agent_read_heatmap.ml`**: Tracks which ZK notes are most frequently requested by MCP agents to optimize context prompts.

### L5: Representation & Layout
26. **`zk_markdown_to_html_compiler.ml`**: The core pure Model->View compiler that translates ZK markdown into Notion-like HTML.
27. **`wiki_theme_token_injector.ml`**: Injects light/dark mode CSS variables safely into the rendered HTML pages.
28. **`zk_page_rank_calculator.ml`**: Computes Personalized PageRank (PPR) for the ZK graph to surface high-authority notes.
29. **`zk_graph_json_exporter.ml`**: Exports the ZK graph nodes and edges to a JSON format compatible with web visualization libraries.
30. **`zk_semantic_vector_updater.ml`**: Manages the local vector embeddings database, detecting modified ZK notes and recalculating their TF-IDF.

### L6: Operation & Property Laws
31. **`zk_bidirectional_link_prover.ml`**: Mathematically proves the "2-way navigability" law: all wiki pages must have a path back to the index.
32. **`zk_transclusion_cycle_detector.ml`**: Prevents infinite loops caused by ZK notes transcluding each other cyclically.
33. **`zk_discourse_logic_checker.ml`**: Validates Dung grounded semantics; e.g., an `@opposes` edge on a claim requires an `evidence` node.
34. **`zk_query_dsl_fuzzer.ml`**: Fuzzes the `zkquery` string parser to ensure the AST builder doesn't panic on malformed user input.
35. **`wiki_sidebar_state_preserver.ml`**: Generates JavaScript logic to persist sidebar expansion/scroll state across page navigations.

### L7: Generator & Fixture
36. **`zk_mock_vault_generator.ml`**: Generates a randomized ZK vault of 10,000 interlinked notes for stress-testing graph algorithms.
37. **`zk_template_scaffolder.ml`**: Bootstraps new ADRs or Feature notes with pre-filled frontmatter and Notion-style structures.
38. **`zk_search_index_compactor.ml`**: Periodically compacts the SQLite FTS5 full-text search index for the ZK vault to maintain query speed.
39. **`wiki_sitemap_xml_generator.ml`**: Generates standard `sitemap.xml` files for the static `--docs-wiki` output.
40. **`zk_asof_timeline_builder.ml`**: Given a target date, builds a static snapshot of the ZK graph exactly as it existed on that date.

### L8: Mutation
41. **`zk_tag_laundering_preventer.ml`**: Ensures auto-generated MoC pages emit inert forms of tags (e.g., `#tag` -> `\#tag`) to prevent infinite recursion.
42. **`zk_mutant_note_injector.ml`**: Injects fake "disputed" claims into the ZK graph to verify the anomaly detector flags them.
43. **`wiki_html_injection_fuzzer.ml`**: Attempts to inject malicious HTML/JS into ZK markdown to ensure the rendering view is injection-safe.
44. **`zk_edge_deletion_simulator.ml`**: Randomly deletes graph edges in memory to test the resilience of the Personalized PageRank algorithm.
45. **`zk_stale_note_decay_marker.ml`**: Automatically marks ZK notes as `status: decayed` if they haven't been touched or verified in > 6 months.

### L9: Verification & Zero-Trust
46. **`zk_verification_stamp_auditor.ml`**: Checks the `verified_by` and `last_verified` frontmatter against cryptographic commit signatures.
47. **`zk_moc_freeze_enforcer.ml`**: Enforces the law that human-promoted MoC notes (`status: published`) can never be overwritten by the auto-generator.
48. **`zk_graph_isomorphism_checker.ml`**: Verifies that the in-memory OCaml ZK graph representation exactly matches the SQLite persistent representation.
49. **`wiki_gate_coupling_prover.ml`**: Mathematically ensures that the `--zk-anomalies` output is strictly report-only and never couples to the canonical build gate.
50. **`zk_agent_authoring_quarantine.ml`**: Restricts `zk_author_note` outputs to `docs/zk/` and enforces the 64 KiB cap, rejecting oversized agentic dumps.

---

## 3. STPA Safety Analysis

### A. Critical System Hazards (H-ZK)
* **H-ZK-1 (Graph Collapse):** Infinite cycles in transclusions or tag laundering crash the rendering engine or agent MCP tool, stalling all operations.
* **H-ZK-2 (Agentic Poisoning):** An agent dumps 50MB of hallucinated code into a ZK note, crashing the markdown compiler and polluting the vector index.
* **H-ZK-3 (Gate Coupling Violation):** An anomaly in the ZK graph (e.g., an orphaned note) accidentally triggers a build failure in the main harness, violating the report-only policy.

### B. Unsafe Control Actions (UCAs)

| UCA ID | Control Action | Type | Context | Linked Hazard | PMS |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **UCA-ZK-1** | Transclude Note | Applied Too Long | `![[A]]` transcludes `B`, and `B` transcludes `A` without a depth limit. | H-ZK-1 | 14 (L1.2) |
| **UCA-ZK-2** | Author Agent Note | Not Providing | Failing to enforce the 64KiB cap during `zk_author_note`. | H-ZK-2 | 11 (L3.1) |
| **UCA-ZK-3** | Yield Anomalies | Providing Incorrectly | Emitting a non-zero exit code on `--zk-anomalies`, gating a valid Zig code commit. | H-ZK-3 | 15 (L1.1) |

---

## 4. FMEA (Failure Mode and Effects Analysis)

| Failure Mode | Direct Effect | Severity | Likelihood | Prescribed Mitigation |
| :--- | :--- | :--- | :--- | :--- |
| **FM-ZK-XSS: HTML Injection** | A user inputs `<script>` tags in a note, bypassing the markdown parser and executing JS in the `/wiki` view. | 5 (Crit) | 3 (Med) | `zk_markdown_to_html_compiler.ml` must employ strict, proven HTML sanitization libraries (e.g., `omd` or bespoke filtering). |
| **FM-ZK-OOM: Graph Memory Leak** | `zk_graph_betweenness_calculator.ml` loads a 10,000-node graph entirely into memory, OOMing the CI runner. | 4 (Major) | 3 (Med) | Compute graph metrics iteratively using SQLite cursors or streaming graph algorithms. |
| **FM-ZK-TAG: Tag Laundering** | An auto-generated MoC aggregates `#todo` tags and outputs them literally, causing the MoC itself to appear in `#todo` queries indefinitely. | 3 (Mod) | 4 (High) | `zk_tag_laundering_preventer.ml` escapes all generated tags (e.g. `\#todo`). |

---

## 5. Criticality and Utility Prioritization (Top 10)

Ranked by **Safety Influence Factor (SIF)** ($\text{PMS} \times \text{CIF}$) and **Engineering Judgment (EJ)**.

| Rank | Script Target | Layer | PMS | CIF | SIF | Priority Band | Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | `wiki_gate_coupling_prover` | L9 | 15 | 4 | **60** | **P1 (Critical)** | Absolutely prevents documentation anomalies from blocking code releases. |
| **2** | `zk_transclusion_cycle_detector` | L6 | 14 | 3 | **42** | **P1** | Graph infinite loops crash both human UI and agent MCP read tools. |
| **3** | `zk_agent_authoring_quarantine` | L9 | 11 | 4 | **44** | **P1** | Front-line defense against LLM-driven graph corruption and blob flooding. |
| **4** | `zk_bidirectional_link_prover` | L6 | 10 | 4 | **40** | **P2** | Enforces the non-negotiable Notion-design law: no dead ends in the wiki. |
| **5** | `zk_markdown_to_html_compiler`| L5 | 10 | 3 | **30** | **P2** | The core model-to-view mechanism. Must be flawless and XSS-immune. |
| **6** | `zk_tag_laundering_preventer` | L8 | 9 | 3 | **27** | **P2** | Stops recursive tag aggregation bugs from rendering MoCs useless. |
| **7** | `zk_moc_freeze_enforcer` | L9 | 8 | 4 | **32** | **P3** | Protects human-curated index documents from being paved over by scripts. |
| **8** | `zk_frontmatter_schema_enforcer`| L0 | 7 | 4 | **28** | **P3** | Keeps the ZK metadata clean, enabling accurate SQL/vector queries. |
| **9** | `zk_query_live_executor` | L4 | 8 | 3 | **24** | **P3** | Critical for dynamic dashboards. Must strictly isolate query failures. |
| **10** | `zk_discourse_logic_checker` | L6 | 7 | 3 | **21** | **P4** | Validates the algebraic logic of `@supports` and `@opposes` discourse edges. |

---

## 6. Architectural Mapping: Harness vs. External Script

To preserve the `zigvm_harness.exe` execution speed and separation of concerns, we divide these 50 capabilities:

### A. Integrated into the Compiled Harness (`harness/*.ml`)
These **18 targets** perform deep AST generation, require recursive graph algorithms, must enforce strict validation policies on ZK read/write, or participate in the live `/wiki` web server logic.

1. `zk_markdown_to_html_compiler.ml` (View)
2. `zk_transclusion_cycle_detector.ml` (Graph logic)
3. `wiki_gate_coupling_prover.ml` (Harness policy)
4. `zk_agent_authoring_quarantine.ml` (Write guard)
5. `zk_bidirectional_link_prover.ml` (Validation)
6. `zk_tag_laundering_preventer.ml` (Generation safety)
7. `zk_moc_freeze_enforcer.ml` (Policy)
8. `zk_query_live_executor.ml` (Live rendering)
9. `zk_discourse_logic_checker.ml` (Dung semantics logic)
10. `zk_frontmatter_schema_enforcer.ml` (Validation)
11. `zk_block_anchor_uniqueness.ml` (Integrity)
12. `zk_typed_edge_extractor.ml` (Parser)
13. `zk_page_rank_calculator.ml` (Graph math)
14. `zk_graph_betweenness_calculator.ml` (Graph math)
15. `zk_graph_isomorphism_checker.ml` (Validation)
16. `wiki_sidebar_tree_generator.ml` (View)
17. `wiki_theme_token_injector.ml` (View)
18. `zk_query_dsl_fuzzer.ml` (Test runner hook)

### B. Implemented as Standalone External Scripts (`scripts/*.ml`)
These **32 targets** perform asynchronous data synchronization, file-system maintenance, visualization exporting, and agent orchestration.

* **Vault Ops:** `zk_vault_backup_manager`, `zk_search_index_compactor`, `fixture_immutability_guard`, `zk_source_code_indexer`, `zk_git_history_indexer`.
* **Static Assets:** `wiki_static_asset_bundler`, `wiki_sitemap_xml_generator`, `zk_graph_json_exporter`.
* **Generators:** `zk_moc_hierarchy_builder`, `zk_community_cluster_namer`, `zk_template_scaffolder`, `zk_asof_timeline_builder`, `zk_anomaly_dashboard_generator`.
* **Linting & Validation:** `wiki_broken_image_sweeper`, `wiki_breadcrumb_validator`, `wiki_callout_syntax_linter`, `zk_architecture_claim_verifier`, `zk_code_transclusion_updater`.
* **Analysis & Observability:** `zk_adr_to_task_linker`, `zk_episodic_memory_pruner`, `zk_subsystem_doc_coverage`, `zk_structural_hole_bridger`, `zk_telemetry_vector_embedder`, `wiki_page_readability_scorer`, `zk_agent_read_heatmap`, `zk_stale_note_decay_marker`, `zk_verification_stamp_auditor`.
* **Fuzzing & Mutants:** `zk_mock_vault_generator`, `zk_mutant_note_injector`, `wiki_html_injection_fuzzer`, `zk_edge_deletion_simulator`.
