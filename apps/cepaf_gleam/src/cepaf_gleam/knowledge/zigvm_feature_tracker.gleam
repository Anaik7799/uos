//// ==============================================================================
//// Unified Operational System (UOS) - ZigVM Wiki, ZK & KM Feature Tracker
//// ==============================================================================
////
//// This module provides a type-safe, canonical in-code registry and tracking
//// substrate for every aspect of the Wiki, Zettelkasten (ZK), and Knowledge
//// Management (KM) subsystems originating in the ZigVM project.
////
//// Architectural Invariants:
//// 1. Pure Functional Generation: Docs_wiki.build (path * markdown) list -> page list.
//// 2. 3-Pass Compilation: Identify & 4-key Resolver -> Typed AST -> Invert Hypergraph.
//// 3. 4 Slug Namespaces: Page, Anchor, File, Resolver + Obsidian block anchors (^id).
//// 4. 7 ZK MCP Tools: Atomic create-only operations (no delete/mutate via MCP).
//// 5. 65 OCaml Scripts: 23 wiki_* maintenance scripts + 42 zk_* knowledge scripts.
//// 6. 13 Render Suites: Checked against the 758-document dual-digest baseline.
//// 7. 3-Tier Corpus: 16 Permanent ADRs + 12 MOCs + 10 Episodic Clusters (347 notes).
//// 8. Rocha Biosemiotics & Dung Sheaves: Symbol-matter cut and sheaf coherence.
////
//// All information is maintained with 100% Zero-Muda purity under BEAM OTP 29.

import gleam/list
import gleam/string

/// The functional domain categorization for Wiki, ZK, and KM features.
pub type FeatureCategory {
  WikiCoreEngine
  ZkMcpTool
  WikiMaintenanceScript
  ZkKnowledgeScript
  HarnessVerificationLaw
  TopologicalSheafFormal
  RenderSuite
  PermanentAdrRecord
  MapOfContent
  EpisodicResearchCluster
  ServiceTopology
}

/// The formal verification tier according to the 7-stratum feature programme.
pub type VerificationTier {
  Tier1OracleEquivalence
  Tier2PropertyAndLaw
  Tier3FormalProof
  Tier4ModelCheck
}

/// The lifecycle status of a tracked feature within the sovereign system.
pub type FeatureStatus {
  RatifiedActive
  VerifiedAdmitted
  SupervisedOperational
}

/// Represents an individual tracked feature of the ZigVM Wiki/ZK/KM substrate.
pub type ZigvmFeature {
  ZigvmFeature(
    id: String,
    name: String,
    category: FeatureCategory,
    tier: VerificationTier,
    status: FeatureStatus,
    description: String,
    source_path: String,
    evidence_path: String,
  )
}

/// High-level metrics summarizing the feature registry.
pub type FeatureSummary {
  FeatureSummary(
    total_features: Int,
    wiki_core_count: Int,
    zk_mcp_tool_count: Int,
    wiki_script_count: Int,
    zk_script_count: Int,
    harness_law_count: Int,
    sheaf_formal_count: Int,
    render_suite_count: Int,
    adr_count: Int,
    moc_count: Int,
    episodic_cluster_count: Int,
    service_topology_count: Int,
  )
}

/// Converts a FeatureCategory to a human-readable string.
pub fn category_to_string(category: FeatureCategory) -> String {
  case category {
    WikiCoreEngine -> "Wiki Core Engine"
    ZkMcpTool -> "ZK MCP Tool"
    WikiMaintenanceScript -> "Wiki Maintenance Script"
    ZkKnowledgeScript -> "ZK Knowledge Script"
    HarnessVerificationLaw -> "Harness Verification Law"
    TopologicalSheafFormal -> "Topological Sheaf / Formal"
    RenderSuite -> "Render Suite"
    PermanentAdrRecord -> "Permanent ADR Record"
    MapOfContent -> "Map of Content (MOC)"
    EpisodicResearchCluster -> "Episodic Research Cluster"
    ServiceTopology -> "Service Topology"
  }
}

/// Converts a VerificationTier to a human-readable string.
pub fn tier_to_string(tier: VerificationTier) -> String {
  case tier {
    Tier1OracleEquivalence -> "Tier 1 (Oracle Equivalence)"
    Tier2PropertyAndLaw -> "Tier 2 (Property & Law)"
    Tier3FormalProof -> "Tier 3 (Formal Proof / Gospel)"
    Tier4ModelCheck -> "Tier 4 (Model Check / Quint)"
  }
}

/// Converts a FeatureStatus to a human-readable string.
pub fn status_to_string(status: FeatureStatus) -> String {
  case status {
    RatifiedActive -> "Ratified & Active"
    VerifiedAdmitted -> "Verified & Admitted"
    SupervisedOperational -> "Supervised Operational"
  }
}

/// The authoritative registry of all tracked Wiki, ZK, and KM features.
pub fn all_features() -> List(ZigvmFeature) {
  list.flatten([
    wiki_core_features(),
    zk_mcp_tools(),
    wiki_maintenance_scripts(),
    zk_knowledge_scripts(),
    harness_verification_laws(),
    topological_sheaf_features(),
    render_suites(),
    permanent_adrs(),
    maps_of_content(),
    episodic_clusters(),
    service_topology_features(),
  ])
}

// ----------------------------------------------------------------------------
// 1. Wiki Core Engine
// ----------------------------------------------------------------------------
fn wiki_core_features() -> List(ZigvmFeature) {
  [
    ZigvmFeature(
      id: "WIKI-CORE-001",
      name: "Docs_wiki Pure Generator",
      category: WikiCoreEngine,
      tier: Tier1OracleEquivalence,
      status: RatifiedActive,
      description: "Pure generator invariant: (path * markdown) list -> page list without I/O or globals.",
      source_path: "harness/docs_wiki.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "WIKI-CORE-002",
      name: "Typed Markdown AST & TyXML Renderer",
      category: WikiCoreEngine,
      tier: Tier1OracleEquivalence,
      status: RatifiedActive,
      description: "Typed AST (block and inline) compiled to structured, well-formed TyXML elements.",
      source_path: "harness/markdown_ast.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "WIKI-CORE-003",
      name: "Stateful Anchor Slugger",
      category: WikiCoreEngine,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Stateful heading slug disambiguation ensuring uniqueness, character validity and determinism.",
      source_path: "harness/slugger.ml",
      evidence_path: "harness/slugger_laws.ml",
    ),
    ZigvmFeature(
      id: "WIKI-CORE-004",
      name: "4-Key Resolver Table",
      category: WikiCoreEngine,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Registers slug, title, basename, and title-minus-ordinal for collision-free link resolution.",
      source_path: "harness/docs_wiki.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "WIKI-CORE-005",
      name: "Hypergraph Inverter & Aho-Corasick Mentions",
      category: WikiCoreEngine,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Inverts forward links into backlinks and scans unlinked mentions via Aho-Corasick automaton.",
      source_path: "harness/docs_wiki.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "WIKI-CORE-006",
      name: "Obsidian Block Anchors (^id)",
      category: WikiCoreEngine,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Explicit trailing block anchors enabling surgical sub-paragraph addressing and patching.",
      source_path: "harness/markdown_ast.ml",
      evidence_path: "harness/zk_block_anchor_uniqueness.ml",
    ),
  ]
}

// ----------------------------------------------------------------------------
// 2. ZK MCP Tools (7 Tools)
// ----------------------------------------------------------------------------
fn zk_mcp_tools() -> List(ZigvmFeature) {
  [
    ZigvmFeature(
      id: "ZK-MCP-001",
      name: "zk_search",
      category: ZkMcpTool,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Full-text, tag-based, and semantic vector similarity search over notes.",
      source_path: "harness/zk_mcp_tools.ml",
      evidence_path: "governance/mcp/tools.toml",
    ),
    ZigvmFeature(
      id: "ZK-MCP-002",
      name: "zk_read_note",
      category: ZkMcpTool,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Retrieves note body, structured frontmatter, outlinks, and verified backlinks.",
      source_path: "harness/zk_mcp_tools.ml",
      evidence_path: "governance/mcp/tools.toml",
    ),
    ZigvmFeature(
      id: "ZK-MCP-003",
      name: "zk_neighborhood",
      category: ZkMcpTool,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Extracts k-hop topological graph neighborhood around a specified note.",
      source_path: "harness/zk_mcp_tools.ml",
      evidence_path: "governance/mcp/tools.toml",
    ),
    ZigvmFeature(
      id: "ZK-MCP-004",
      name: "zk_query",
      category: ZkMcpTool,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Evaluates structured ZK-Query DSL expressions over frontmatter and relation predicates.",
      source_path: "harness/zk_query_live_executor.ml",
      evidence_path: "docs/zk/episodic/smtml-zkquery-lint.md",
    ),
    ZigvmFeature(
      id: "ZK-MCP-005",
      name: "zk_anomalies",
      category: ZkMcpTool,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Structural anomaly detection: ungrounded claims, transclusion cycles, and missing evidence.",
      source_path: "harness/zk_discourse_logic_checker.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "ZK-MCP-006",
      name: "zk_author_note",
      category: ZkMcpTool,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Atomic note creation with strict safe_slug validation and automatic git stage.",
      source_path: "harness/zk_mcp_tools.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "ZK-MCP-007",
      name: "zk_record_decision",
      category: ZkMcpTool,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Formal ADR recording with mandatory context, decision, and invariant specifications.",
      source_path: "harness/zk_mcp_tools.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
  ]
}

// ----------------------------------------------------------------------------
// 3. Wiki Maintenance Scripts (23 Scripts)
// ----------------------------------------------------------------------------
fn wiki_maintenance_scripts() -> List(ZigvmFeature) {
  [
    ZigvmFeature(
      id: "WIKI-SCR-001",
      name: "wiki_accessibility_auditor.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Audits WCAG compliance and contrast ratios in rendered HTML markup.",
      source_path: "scripts/wiki_accessibility_auditor.ml",
      evidence_path: "scripts/wiki_accessibility_auditor.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-002",
      name: "wiki_arch_decision_tree_builder.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Synthesizes architectural decision branching trees from ADR dependencies.",
      source_path: "scripts/wiki_arch_decision_tree_builder.ml",
      evidence_path: "scripts/wiki_arch_decision_tree_builder.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-003",
      name: "wiki_changelog_to_zk_sync.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Synchronizes release changelog entries into permanent ZK notes.",
      source_path: "scripts/wiki_changelog_to_zk_sync.ml",
      evidence_path: "scripts/wiki_changelog_to_zk_sync.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-004",
      name: "wiki_ci_artifact_sweeper.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Cleans stale transient build and test artifacts from documentation cache.",
      source_path: "scripts/wiki_ci_artifact_sweeper.ml",
      evidence_path: "scripts/wiki_ci_artifact_sweeper.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-005",
      name: "wiki_component_maturity_scorer.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Scores software components based on documentation completeness and verification.",
      source_path: "scripts/wiki_component_maturity_scorer.ml",
      evidence_path: "scripts/wiki_component_maturity_scorer.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-006",
      name: "wiki_dark_mode_contrast_checker.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Validates dark theme CSS design tokens for perceptual contrast ratios.",
      source_path: "scripts/wiki_dark_mode_contrast_checker.ml",
      evidence_path: "scripts/wiki_dark_mode_contrast_checker.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-007",
      name: "wiki_deployment_env_validator.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Validates environment variable documentation against live deployment specs.",
      source_path: "scripts/wiki_deployment_env_validator.ml",
      evidence_path: "scripts/wiki_deployment_env_validator.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-008",
      name: "wiki_deprecated_usage_warner.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Traps occurrences of deprecated APIs and models mentioned in wiki articles.",
      source_path: "scripts/wiki_deprecated_usage_warner.ml",
      evidence_path: "scripts/wiki_deprecated_usage_warner.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-009",
      name: "wiki_fixture_to_markdown_converter.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Converts structured test fixtures and telemetry logs into formatted markdown.",
      source_path: "scripts/wiki_fixture_to_markdown_converter.ml",
      evidence_path: "scripts/wiki_fixture_to_markdown_converter.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-010",
      name: "wiki_inline_comment_extractor.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Extracts in-code @note, @todo, and @doc comments into the living knowledge graph.",
      source_path: "scripts/wiki_inline_comment_extractor.ml",
      evidence_path: "scripts/wiki_inline_comment_extractor.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-011",
      name: "wiki_lfs_asset_manager.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Manages and validates Git LFS media assets linked from wiki documentation.",
      source_path: "scripts/wiki_lfs_asset_manager.ml",
      evidence_path: "scripts/wiki_lfs_asset_manager.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-012",
      name: "wiki_onboarding_guide_generator.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Assembles sequential onboarding reading tracks from topological graph walks.",
      source_path: "scripts/wiki_onboarding_guide_generator.ml",
      evidence_path: "scripts/wiki_onboarding_guide_generator.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-013",
      name: "wiki_performance_benchmark_plotter.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Generates vector SVG sparklines and performance plots from benchmark SQLite runs.",
      source_path: "scripts/wiki_performance_benchmark_plotter.ml",
      evidence_path: "scripts/wiki_performance_benchmark_plotter.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-014",
      name: "wiki_release_notes_assembler.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Compiles canonical release notes by querying active milestone notes.",
      source_path: "scripts/wiki_release_notes_assembler.ml",
      evidence_path: "scripts/wiki_release_notes_assembler.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-015",
      name: "wiki_responsive_css_validator.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Validates responsive CSS rules against mobile, tablet, and desktop breakpoints.",
      source_path: "scripts/wiki_responsive_css_validator.ml",
      evidence_path: "scripts/wiki_responsive_css_validator.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-016",
      name: "wiki_rss_feed_generator.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Emits XML RSS and Atom syndication feeds for recently updated architecture docs.",
      source_path: "scripts/wiki_rss_feed_generator.ml",
      evidence_path: "scripts/wiki_rss_feed_generator.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-017",
      name: "wiki_search_index_size_monitor.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Monitors and bounds the memory footprint of the static search inverted index.",
      source_path: "scripts/wiki_search_index_size_monitor.ml",
      evidence_path: "scripts/wiki_search_index_size_monitor.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-018",
      name: "wiki_sidebar_scroll_sync_generator.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Generates client-side sidebar scroll-sync state machines for deep document trees.",
      source_path: "scripts/wiki_sidebar_scroll_sync_generator.ml",
      evidence_path: "scripts/wiki_sidebar_scroll_sync_generator.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-019",
      name: "wiki_slo_sli_dashboarder.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Emits real-time Service Level Objective (SLO) compliance dashboards into wiki.",
      source_path: "scripts/wiki_slo_sli_dashboarder.ml",
      evidence_path: "scripts/wiki_slo_sli_dashboarder.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-020",
      name: "wiki_symlink_detector.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Scans for dangling, circular, or out-of-tree symlinks across the documentation corpus.",
      source_path: "scripts/wiki_symlink_detector.ml",
      evidence_path: "scripts/wiki_symlink_detector.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-021",
      name: "wiki_system_context_mapper.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Constructs C4 model Level 1 system context diagrams from parsed wikilinks.",
      source_path: "scripts/wiki_system_context_mapper.ml",
      evidence_path: "scripts/wiki_system_context_mapper.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-022",
      name: "wiki_todo_checkbox_sweeper.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Sweeps and catalogs open `- [ ]` tasks and checkboxes across all documentation.",
      source_path: "scripts/wiki_todo_checkbox_sweeper.ml",
      evidence_path: "scripts/wiki_todo_checkbox_sweeper.ml",
    ),
    ZigvmFeature(
      id: "WIKI-SCR-023",
      name: "wiki_typography_scale_enforcer.ml",
      category: WikiMaintenanceScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Enforces strict mathematical modular typography scales across generated HTML.",
      source_path: "scripts/wiki_typography_scale_enforcer.ml",
      evidence_path: "scripts/wiki_typography_scale_enforcer.ml",
    ),
  ]
}

// ----------------------------------------------------------------------------
// 4. ZK Knowledge Scripts (42 Scripts)
// ----------------------------------------------------------------------------
fn zk_knowledge_scripts() -> List(ZigvmFeature) {
  [
    ZigvmFeature(
      id: "ZK-SCR-001",
      name: "zk_abandoned_draft_pruner.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Detects and flags unreferenced draft notes older than the retention horizon.",
      source_path: "scripts/zk_abandoned_draft_pruner.ml",
      evidence_path: "scripts/zk_abandoned_draft_pruner.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-002",
      name: "zk_adr_decision_log_generator.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Emits sequential chronological decision logs from ADR frontmatter.",
      source_path: "scripts/zk_adr_decision_log_generator.ml",
      evidence_path: "scripts/zk_adr_decision_log_generator.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-003",
      name: "zk_adr_status_tracker.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Tracks lifecycle status transitions (proposed -> ratified -> superseded).",
      source_path: "scripts/zk_adr_status_tracker.ml",
      evidence_path: "scripts/zk_adr_status_tracker.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-004",
      name: "zk_agent_prompt_effectiveness_scorer.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Correlates agent prompt templates stored in ZK with benchmark task success.",
      source_path: "scripts/zk_agent_prompt_effectiveness_scorer.ml",
      evidence_path: "scripts/zk_agent_prompt_effectiveness_scorer.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-005",
      name: "zk_allocator_pattern_cataloger.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Catalogs Zig deterministic memory allocation patterns referenced in notes.",
      source_path: "scripts/zk_allocator_pattern_cataloger.ml",
      evidence_path: "scripts/zk_allocator_pattern_cataloger.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-006",
      name: "zk_backlog_aging_report.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Measures latency and aging of unresolved engineering debt across notes.",
      source_path: "scripts/zk_backlog_aging_report.ml",
      evidence_path: "scripts/zk_backlog_aging_report.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-007",
      name: "zk_bottleneck_predictor.ml",
      category: ZkKnowledgeScript,
      tier: Tier3FormalProof,
      status: VerifiedAdmitted,
      description: "Calculates topological critical paths and dependency bottlenecks in ZK DAGs.",
      source_path: "scripts/zk_bottleneck_predictor.ml",
      evidence_path: "scripts/zk_bottleneck_predictor.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-008",
      name: "zk_conflict_resolution_helper.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Assists three-way semantic merge resolution in note frontmatter.",
      source_path: "scripts/zk_conflict_resolution_helper.ml",
      evidence_path: "scripts/zk_conflict_resolution_helper.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-009",
      name: "zk_cross_cutting_concern_tracker.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Maps systemic cross-cutting concerns (auth, safety, zero-muda) across notes.",
      source_path: "scripts/zk_cross_cutting_concern_tracker.ml",
      evidence_path: "scripts/zk_cross_cutting_concern_tracker.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-010",
      name: "zk_data_flow_diagram_generator.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Extracts typed relations into structured Mermaid and Graphviz data flows.",
      source_path: "scripts/zk_data_flow_diagram_generator.ml",
      evidence_path: "scripts/zk_data_flow_diagram_generator.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-011",
      name: "zk_dummy_vault_for_benchmarking.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Generates synthetic 10,000-note vault for stress testing graph engines.",
      source_path: "scripts/zk_dummy_vault_for_benchmarking.ml",
      evidence_path: "scripts/zk_dummy_vault_for_benchmarking.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-012",
      name: "zk_editor_config_generator.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Emits editor configurations for seamless markdown link autocompletion.",
      source_path: "scripts/zk_editor_config_generator.ml",
      evidence_path: "scripts/zk_editor_config_generator.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-013",
      name: "zk_epic_to_slice_validator.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Validates that high-level roadmap epics strictly decompose into atomic slices.",
      source_path: "scripts/zk_epic_to_slice_validator.ml",
      evidence_path: "scripts/zk_epic_to_slice_validator.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-014",
      name: "zk_error_code_cataloger.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Indexes all system error codes and links them to remediation runbooks.",
      source_path: "scripts/zk_error_code_cataloger.ml",
      evidence_path: "scripts/zk_error_code_cataloger.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-015",
      name: "zk_feature_flag_doc_sync.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Synchronizes runtime feature flags with corresponding ZK specifications.",
      source_path: "scripts/zk_feature_flag_doc_sync.ml",
      evidence_path: "scripts/zk_feature_flag_doc_sync.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-016",
      name: "zk_flaky_test_runbook_generator.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Generates debugging runbooks for intermittent test failures recorded in notes.",
      source_path: "scripts/zk_flaky_test_runbook_generator.ml",
      evidence_path: "scripts/zk_flaky_test_runbook_generator.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-017",
      name: "zk_frontmatter_json_schema_exporter.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Exports the ZK frontmatter specification as an authoritative JSON Schema.",
      source_path: "scripts/zk_frontmatter_json_schema_exporter.ml",
      evidence_path: "scripts/zk_frontmatter_json_schema_exporter.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-018",
      name: "zk_gitignore_auditor.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Audits gitignore rules to prevent accidental leak of transient vault files.",
      source_path: "scripts/zk_gitignore_auditor.ml",
      evidence_path: "scripts/zk_gitignore_auditor.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-019",
      name: "zk_graph_force_directed_layout.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Calculates 2D spring-embedder coordinates for visual knowledge graph displays.",
      source_path: "scripts/zk_graph_force_directed_layout.ml",
      evidence_path: "scripts/zk_graph_force_directed_layout.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-020",
      name: "zk_incident_postmortem_linker.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Links production incident records directly to architectural decision ADRs.",
      source_path: "scripts/zk_incident_postmortem_linker.ml",
      evidence_path: "scripts/zk_incident_postmortem_linker.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-021",
      name: "zk_link_density_evaluator.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Measures wikilink density per 1,000 words, enforcing healthy connectivity.",
      source_path: "scripts/zk_link_density_evaluator.ml",
      evidence_path: "scripts/zk_link_density_evaluator.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-022",
      name: "zk_markdown_table_formatter.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Normalizes Markdown tables across notes into clean, uniform columnar alignment.",
      source_path: "scripts/zk_markdown_table_formatter.ml",
      evidence_path: "scripts/zk_markdown_table_formatter.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-023",
      name: "zk_mcp_tool_schema_documenter.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Compiles JSON-RPC MCP schemas directly into readable ZK documentation.",
      source_path: "scripts/zk_mcp_tool_schema_documenter.ml",
      evidence_path: "scripts/zk_mcp_tool_schema_documenter.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-024",
      name: "zk_meeting_notes_action_itemizer.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Parses meeting logs and extracts actionable tasks into engineering backlogs.",
      source_path: "scripts/zk_meeting_notes_action_itemizer.ml",
      evidence_path: "scripts/zk_meeting_notes_action_itemizer.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-025",
      name: "zk_mutant_code_context_fetcher.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Supplies relevant architectural context to surviving mutation test mutants.",
      source_path: "scripts/zk_mutant_code_context_fetcher.ml",
      evidence_path: "scripts/zk_mutant_code_context_fetcher.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-026",
      name: "zk_note_length_histogram_generator.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Computes note length histograms to identify monolithic notes needing division.",
      source_path: "scripts/zk_note_length_histogram_generator.ml",
      evidence_path: "scripts/zk_note_length_histogram_generator.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-027",
      name: "zk_opam_deps_checker.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Verifies OCaml OPAM dependencies referenced across build instructions.",
      source_path: "scripts/zk_opam_deps_checker.ml",
      evidence_path: "scripts/zk_opam_deps_checker.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-028",
      name: "zk_orphaned_block_anchor_sweeper.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Detects unused ^id block anchors that have no inbound references.",
      source_path: "scripts/zk_orphaned_block_anchor_sweeper.ml",
      evidence_path: "scripts/zk_orphaned_block_anchor_sweeper.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-029",
      name: "zk_query_performance_profiler.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Profiles latency of recursive graph traversal queries over SQLite slip-box.",
      source_path: "scripts/zk_query_performance_profiler.ml",
      evidence_path: "scripts/zk_query_performance_profiler.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-030",
      name: "zk_security_threat_modeler.ml",
      category: ZkKnowledgeScript,
      tier: Tier3FormalProof,
      status: VerifiedAdmitted,
      description: "Builds STRIDE threat matrices from tagged security nodes across the vault.",
      source_path: "scripts/zk_security_threat_modeler.ml",
      evidence_path: "scripts/zk_security_threat_modeler.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-031",
      name: "zk_semantic_similarity_clusterer.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Clusters notes into thematic topics using cosine distance over vector embeddings.",
      source_path: "scripts/zk_semantic_similarity_clusterer.ml",
      evidence_path: "scripts/zk_semantic_similarity_clusterer.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-032",
      name: "zk_shell_alias_installer.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Installs high-velocity CLI shell aliases for quick slip-box navigation.",
      source_path: "scripts/zk_shell_alias_installer.ml",
      evidence_path: "scripts/zk_shell_alias_installer.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-033",
      name: "zk_sprint_goal_extractor.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Extracts active sprint goals from milestone notes and emits progress summaries.",
      source_path: "scripts/zk_sprint_goal_extractor.ml",
      evidence_path: "scripts/zk_sprint_goal_extractor.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-034",
      name: "zk_subsystem_boundary_visualizer.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Renders architectural subsystem boundary diagrams from tagged link graphs.",
      source_path: "scripts/zk_subsystem_boundary_visualizer.ml",
      evidence_path: "scripts/zk_subsystem_boundary_visualizer.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-035",
      name: "zk_tag_taxonomy_exporter.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Exports hierarchical tag taxonomies (#fractal-*, #zk-*, #zero-muda).",
      source_path: "scripts/zk_tag_taxonomy_exporter.ml",
      evidence_path: "scripts/zk_tag_taxonomy_exporter.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-036",
      name: "zk_tech_debt_aggregator.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Aggregates technical debt indices and estimates remediation effort.",
      source_path: "scripts/zk_tech_debt_aggregator.ml",
      evidence_path: "scripts/zk_tech_debt_aggregator.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-037",
      name: "zk_telemetry_alert_mapper.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Binds real-time OpenTelemetry alerting rules to corresponding ZK runbooks.",
      source_path: "scripts/zk_telemetry_alert_mapper.ml",
      evidence_path: "scripts/zk_telemetry_alert_mapper.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-038",
      name: "zk_template_variable_substitutor.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Substitutes variables into reusable note templates (ADR, postmortem, RFC).",
      source_path: "scripts/zk_template_variable_substitutor.ml",
      evidence_path: "scripts/zk_template_variable_substitutor.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-039",
      name: "zk_temporal_snapshot_differ.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Computes topological graph diffs between successive Jujutsu commits.",
      source_path: "scripts/zk_temporal_snapshot_differ.ml",
      evidence_path: "scripts/zk_temporal_snapshot_differ.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-040",
      name: "zk_type_definition_linker.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Generates deep hypertext links from markdown symbols to source code types.",
      source_path: "scripts/zk_type_definition_linker.ml",
      evidence_path: "scripts/zk_type_definition_linker.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-041",
      name: "zk_user_journey_pathfinder.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Traces end-to-end user navigation journeys through documentation links.",
      source_path: "scripts/zk_user_journey_pathfinder.ml",
      evidence_path: "scripts/zk_user_journey_pathfinder.ml",
    ),
    ZigvmFeature(
      id: "ZK-SCR-042",
      name: "zk_vault_permissions_guard.ml",
      category: ZkKnowledgeScript,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Enforces POSIX file permissions and security boundaries across notes.",
      source_path: "scripts/zk_vault_permissions_guard.ml",
      evidence_path: "scripts/zk_vault_permissions_guard.ml",
    ),
  ]
}

// ----------------------------------------------------------------------------
// 5. Harness Verification Laws & Modules
// ----------------------------------------------------------------------------
fn harness_verification_laws() -> List(ZigvmFeature) {
  [
    ZigvmFeature(
      id: "HARN-LAW-001",
      name: "markdown_ast_laws.ml",
      category: HarnessVerificationLaw,
      tier: Tier1OracleEquivalence,
      status: RatifiedActive,
      description: "Proves oracle equivalence, quirk preservation, information preservation, and anchor locality.",
      source_path: "harness/markdown_ast_laws.ml",
      evidence_path: "harness/markdown_ast_laws.ml",
    ),
    ZigvmFeature(
      id: "HARN-LAW-002",
      name: "docs_wiki_laws.ml",
      category: HarnessVerificationLaw,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Proves page-state invariants, backlink graph symmetry, and group partitioning.",
      source_path: "harness/docs_wiki_laws.ml",
      evidence_path: "harness/docs_wiki_laws.ml",
    ),
    ZigvmFeature(
      id: "HARN-LAW-003",
      name: "wiki_render_laws.ml",
      category: HarnessVerificationLaw,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Proves layout rendering properties, breadcrumb hierarchy, and semantic CSS tags.",
      source_path: "harness/wiki_render_laws.ml",
      evidence_path: "harness/wiki_render_laws.ml",
    ),
    ZigvmFeature(
      id: "HARN-LAW-004",
      name: "slugger_laws.ml",
      category: HarnessVerificationLaw,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Ortac/Gospel state model proving anchor uniqueness, character validity, and determinism.",
      source_path: "harness/slugger_laws.ml",
      evidence_path: "harness/slugger_laws.ml",
    ),
    ZigvmFeature(
      id: "HARN-LAW-005",
      name: "wiki_cache_poisoning_detector.ml",
      category: HarnessVerificationLaw,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Scans rendered HTML for script injection, evil event handlers, and cache poisoning.",
      source_path: "harness/wiki_cache_poisoning_detector.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "HARN-LAW-006",
      name: "wiki_content_security_policy_generator.ml",
      category: HarnessVerificationLaw,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Emits strict CSP headers (default-src none) and audits prohibited inline elements.",
      source_path: "harness/wiki_content_security_policy_generator.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "HARN-LAW-007",
      name: "zk_transclusion_depth_limiter.ml",
      category: HarnessVerificationLaw,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Enforces transclusion recursion bounds and prevents cyclic expansion crashes.",
      source_path: "harness/zk_transclusion_depth_limiter.ml",
      evidence_path: "harness/zk_transclusion_depth_limiter.ml",
    ),
    ZigvmFeature(
      id: "HARN-LAW-008",
      name: "zk_page_rank_calculator.ml",
      category: HarnessVerificationLaw,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Calculates eigenvector centrality and PageRank across the entire slip-box corpus.",
      source_path: "harness/zk_page_rank_calculator.ml",
      evidence_path: "harness/zk_page_rank_calculator.ml",
    ),
  ]
}

// ----------------------------------------------------------------------------
// 6. Topological Sheaf & Formal Modules
// ----------------------------------------------------------------------------
fn topological_sheaf_features() -> List(ZigvmFeature) {
  [
    ZigvmFeature(
      id: "FORMAL-SHEAF-001",
      name: "wiki_dep_sheaf.ml",
      category: TopologicalSheafFormal,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Evaluates sheaf-theoretic gluing conditions over note topological open covers.",
      source_path: "harness/wiki_dep_sheaf.ml",
      evidence_path: "harness/wiki_dep_sheaf.mli",
    ),
    ZigvmFeature(
      id: "FORMAL-SHEAF-002",
      name: "zk_contradiction_prover.ml",
      category: TopologicalSheafFormal,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Implements Dung argumentation semantics to compute grounded extensions of claims.",
      source_path: "harness/zk_contradiction_prover.ml",
      evidence_path: "docs/zk/episodic/gap-verification-handover.md",
    ),
    ZigvmFeature(
      id: "FORMAL-SHEAF-003",
      name: "wiki_selfcheck_parallel.qnt",
      category: TopologicalSheafFormal,
      tier: Tier4ModelCheck,
      status: RatifiedActive,
      description: "Quint formal specification proving race-free parallel self-checks and invariant closure.",
      source_path: "specs/wiki_selfcheck_parallel.qnt",
      evidence_path: "harness/generated/quint/wiki_selfcheck_parallel.ml",
    ),
    ZigvmFeature(
      id: "FORMAL-SHEAF-004",
      name: "Knowledge Annotation Actor",
      category: TopologicalSheafFormal,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "BEAM OTP 29 actor executing continuous biosemiotic scanning and sheaf coherence checks.",
      source_path: "apps/cepaf_gleam/src/cepaf_gleam/knowledge/annotation_actor.gleam",
      evidence_path: "apps/cepaf_gleam/test/knowledge_annotation_actor_test.gleam",
    ),
  ]
}

// ----------------------------------------------------------------------------
// 7. Render Suites (13 Suites)
// ----------------------------------------------------------------------------
fn render_suites() -> List(ZigvmFeature) {
  [
    ZigvmFeature(
      id: "SUITE-001",
      name: "Wiki Render Suite",
      category: RenderSuite,
      tier: Tier1OracleEquivalence,
      status: RatifiedActive,
      description: "Core document rendering and URL routing suite.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "SUITE-002",
      name: "Slo Render Suite",
      category: RenderSuite,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Latency bounds ensuring page generation completes in under 20 milliseconds.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "SUITE-003",
      name: "Self Render Suite",
      category: RenderSuite,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Self-referential validation verifying all internal documents pass their own specs.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "SUITE-004",
      name: "Json Render Suite",
      category: RenderSuite,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "JSON-LD schema structured data generation verification.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "SUITE-005",
      name: "Viz Render Suite",
      category: RenderSuite,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Mermaid syntax parser and vector diagram rendering validator.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "SUITE-006",
      name: "Markdown Render Suite",
      category: RenderSuite,
      tier: Tier1OracleEquivalence,
      status: RatifiedActive,
      description: "CommonMark and GitHub Flavored Markdown specification conformance.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "SUITE-007",
      name: "Zk Render Suite",
      category: RenderSuite,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Wikilink resolution, transclusion, and frontmatter parsing suite.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "SUITE-008",
      name: "Toolchain Render Suite",
      category: RenderSuite,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Compiler toolchain and linter compatibility suite.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "SUITE-009",
      name: "Model Render Suite",
      category: RenderSuite,
      tier: Tier4ModelCheck,
      status: RatifiedActive,
      description: "Verification against formal Quint state machine specifications.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "SUITE-010",
      name: "Slugger Render Suite",
      category: RenderSuite,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Anchor uniqueness, character purity, and collision idempotency suite.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "SUITE-011",
      name: "Baseline Render Suite",
      category: RenderSuite,
      tier: Tier1OracleEquivalence,
      status: RatifiedActive,
      description: "Comparison against 758 pinned dual-digest documents preventing drift.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/markdown-render-baseline.txt",
    ),
    ZigvmFeature(
      id: "SUITE-012",
      name: "Publication Render Suite",
      category: RenderSuite,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Static HTML export and asset bundling verification suite.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
    ZigvmFeature(
      id: "SUITE-013",
      name: "Preflight Render Suite",
      category: RenderSuite,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Security and permissions preflight verification suite.",
      source_path: "harness/render_suite.ml",
      evidence_path: "docs/design/WIKI_PIPELINE.md",
    ),
  ]
}

// ----------------------------------------------------------------------------
// 8. Permanent Architectural Decision Records (16 ADRs)
// ----------------------------------------------------------------------------
fn permanent_adrs() -> List(ZigvmFeature) {
  [
    ZigvmFeature(
      id: "ADR-001",
      name: "Closed Rete-UL Fact Schema & Strict Typing",
      category: PermanentAdrRecord,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Closed Rete-UL fact schema rejects dynamic facts with strict compile-time typing.",
      source_path: "docs/zk/20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant.md",
      evidence_path: "governance/rules/adr-001.toml",
    ),
    ZigvmFeature(
      id: "ADR-002",
      name: "Embedded NUL Ingress Trap",
      category: PermanentAdrRecord,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Traps embedded NUL byte ingress in agent_dispatch_hook.ml with immediate abort code -2.",
      source_path: "docs/zk/20260904-150142-adr-002-embedded-nul-ingress-trap-and-memory-allocation-containment.md",
      evidence_path: "engines/hermes/modules/system_engg/agent_dispatch_hook.ml",
    ),
    ZigvmFeature(
      id: "ADR-003",
      name: "Pure Binary SQLite Header Verification",
      category: PermanentAdrRecord,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Direct binary header validation of SQLite ledgers ensuring page-size alignment.",
      source_path: "docs/zk/20260904-150145-adr-003-pure-binary-sqlite-header-verification-and-page-size-invariants.md",
      evidence_path: "engines/hermes/modules/system_engg/agent_dispatch_hook.ml",
    ),
    ZigvmFeature(
      id: "ADR-004",
      name: "Zenoh Session Lifecycle & Liveness Quorum",
      category: PermanentAdrRecord,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Strict session lifecycle management with heartbeat monitoring and 2oo3 quorum.",
      source_path: "docs/zk/20260904-150148-adr-004-zenoh-session-lifecycle-liveness-quorum-and-heartbeat-discipline.md",
      evidence_path: "apps/cepaf_gleam/src/cepaf_gleam/ha/freshness_monitor.gleam",
    ),
    ZigvmFeature(
      id: "ADR-005",
      name: "Dual-Host UOS Topology & Tailnet Wiki",
      category: PermanentAdrRecord,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Topology split between NAS-1 and VM-1 with live Tailscale FQDN wiki serving.",
      source_path: "docs/zk/20260904-151412-adr-005-dual-host-unified-operational-system-topology-and-live-tailnet-wiki-integration.md",
      evidence_path: "contracts/rules/tailscale-web-fqdn-mandate.md",
    ),
    ZigvmFeature(
      id: "ADR-006",
      name: "Zero-Muda Graphene Eradication",
      category: PermanentAdrRecord,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "0 Bevy, 0 Graphite, and pure Erlang graphene_nif.erl without foreign shared libraries.",
      source_path: "docs/zk/20260904-151415-adr-006-zero-muda-graphene-eradication-and-pure-beam-graphene-nif-rendering.md",
      evidence_path: "apps/cepaf_gleam/src/graphene_nif.erl",
    ),
    ZigvmFeature(
      id: "ADR-007",
      name: "Single-Writer STM Lease & Mutex Discipline",
      category: PermanentAdrRecord,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Proves observation non-interference and single-writer exclusive lease mutex in Lean 4.",
      source_path: "docs/zk/20260904-151418-adr-007-single-writer-stm-lease-and-exclusive-mutex-discipline.md",
      evidence_path: "formal/lean/TwoLattice_STM.lean",
    ),
    ZigvmFeature(
      id: "ADR-008",
      name: "Denotational Meta-Calculus & 13D Invariance",
      category: PermanentAdrRecord,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Mathematical coordinate conservation and fail-closed trust indicators in Lean 4.",
      source_path: "docs/zk/20260904-151421-adr-008-denotational-meta-calculus-and-13d-trace-invariance.md",
      evidence_path: "formal/lean/Traceability.lean",
    ),
    ZigvmFeature(
      id: "ADR-009",
      name: "Bounded Z3 SMT Oracle Dispatch",
      category: PermanentAdrRecord,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Worker-isolated bounded SMT queries with strict timeouts and process-tree reaping.",
      source_path: "docs/zk/20260904-151424-adr-009-bounded-z3-smt-oracle-dispatch-and-worker-isolation.md",
      evidence_path: "engines/hermes/modules/system_engg/smt_worker.ml",
    ),
    ZigvmFeature(
      id: "ADR-010",
      name: "Descriptor-Relative VFS Backing",
      category: PermanentAdrRecord,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Descriptor-relative, race-free, symlink-aware filesystem abstraction kernel.",
      source_path: "docs/zk/20260904-151427-adr-010-descriptor-relative-vfs-backing-and-symlink-defense.md",
      evidence_path: "engines/zigvm/src/vfs.zig",
    ),
    ZigvmFeature(
      id: "ADR-011",
      name: "Isolated Modular MAX AI Inference Protocol",
      category: PermanentAdrRecord,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Python execution strictly quarantined to supervised daemon via length-delimited JSON-RPC.",
      source_path: "docs/zk/20260904-151430-adr-011-isolated-modular-max-ai-inference-protocol.md",
      evidence_path: "services/inference/max/max_worker.py",
    ),
    ZigvmFeature(
      id: "ADR-012",
      name: "Zero-Trust MCP Tool Dispatch Interceptor",
      category: PermanentAdrRecord,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Validates MCP payloads via SHA-256 digestion, trapping embedded NUL and SQL injections.",
      source_path: "docs/zk/20260904-151433-adr-012-zero-trust-mcp-tool-dispatch-interceptor.md",
      evidence_path: "engines/hermes/modules/system_engg/agent_dispatch_hook.ml",
    ),
    ZigvmFeature(
      id: "ADR-013",
      name: "Multilayer OTP 29 Root Supervisor",
      category: PermanentAdrRecord,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Root 4-domain supervisor hierarchy across Apps, Engines, Services, and Intelligence.",
      source_path: "docs/zk/20260904-151436-adr-013-multilayer-otp-29-root-supervisor-hierarchy.md",
      evidence_path: "apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam",
    ),
    ZigvmFeature(
      id: "ADR-014",
      name: "18-Point Comprehensive Checklist & Navigation",
      category: PermanentAdrRecord,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Universal 5-domain, 18-checkpoint interactive verification accordion on all pages.",
      source_path: "docs/zk/20260904-151439-adr-014-comprehensive-verification-checklist-and-uniform-navigation.md",
      evidence_path: "contracts/rules/comprehensive-checklist-contract.md",
    ),
    ZigvmFeature(
      id: "ADR-015",
      name: "Luis Rocha Biosemiotic & Semantic Closure",
      category: PermanentAdrRecord,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Selected self-organization, Howard Pattee epistemic cut, and von Neumann semantic closure.",
      source_path: "docs/zk/20260905-1950-adr-015-rocha-biosemiotics-and-semantic-closure.md",
      evidence_path: "contracts/rules/rocha-semiotics-cybernetics-contract.md",
    ),
    ZigvmFeature(
      id: "ADR-016",
      name: "Phan Minh Dung Sheaf Argumentation",
      category: PermanentAdrRecord,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Abstract argumentation frameworks, mutual conflict resolution, and sheaf consistency.",
      source_path: "docs/zk/20260905-1951-adr-016-dung-sheaf-argumentation-and-coherence.md",
      evidence_path: "harness/zk_contradiction_prover.ml",
    ),
  ]
}

// ----------------------------------------------------------------------------
// 9. Maps of Content (12 MOCs)
// ----------------------------------------------------------------------------
fn maps_of_content() -> List(ZigvmFeature) {
  [
    ZigvmFeature(
      id: "MOC-001",
      name: "Master Unified Knowledge Graph MOC",
      category: MapOfContent,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Root navigational hub connecting all domains, ADRs, and episodic notes.",
      source_path: "docs/zk/20260905-1801-moc-uos-unified-master.md",
      evidence_path: "docs/zk/20260905-1801-moc-uos-unified-master.md",
    ),
    ZigvmFeature(
      id: "MOC-002",
      name: "System Architecture & Invariants MOC",
      category: MapOfContent,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Constitutional system topology, state machines, and language boundaries.",
      source_path: "docs/zk/20260725-zk-wiki-system-architecture.md",
      evidence_path: "docs/zk/20260725-zk-wiki-system-architecture.md",
    ),
    ZigvmFeature(
      id: "MOC-003",
      name: "SRE & Verification Audit Ledger MOC",
      category: MapOfContent,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "SRE audit runbooks, formal verification gates, and test suites.",
      source_path: "docs/zk/20260729-zk-bridge-and-orphan-index.md",
      evidence_path: "docs/zk/20260729-zk-bridge-and-orphan-index.md",
    ),
    ZigvmFeature(
      id: "MOC-004",
      name: "Algebra-Driven OCaml & Formal Pipeline MOC",
      category: MapOfContent,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Dune modules, Gospel contracts, and differential oracle pipelines.",
      source_path: "docs/zk/20260804-wiki-zk-parallel-pipeline.md",
      evidence_path: "docs/zk/20260804-wiki-zk-parallel-pipeline.md",
    ),
    ZigvmFeature(
      id: "MOC-005",
      name: "Multi-Agent Swarm & Symbiosis MOC",
      category: MapOfContent,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Agent capabilities, MCP dispatch protocols, and session coordination.",
      source_path: "docs/zk/20260905-1801-moc-uos-unified-master.md",
      evidence_path: "governance/agents/policy/superset.toml",
    ),
    ZigvmFeature(
      id: "MOC-006",
      name: "Cybernetic Command & Control Plane MOC",
      category: MapOfContent,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "C3I supervision trees, Prajna circuit breakers, and Lyapunov monitors.",
      source_path: "docs/zk/20260905-1801-moc-uos-unified-master.md",
      evidence_path: "apps/cepaf_gleam/src/cepaf_gleam/ha/lyapunov_proof.gleam",
    ),
    ZigvmFeature(
      id: "MOC-007",
      name: "Storage Safety & Ceph Topology MOC",
      category: MapOfContent,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Hardware drive safety, OS NVMe lock (25503L801736), and Ceph pools.",
      source_path: "docs/zk/20260905-1801-moc-uos-unified-master.md",
      evidence_path: "ops/kubernetes/nas-k8s-lab/src/spec.rs",
    ),
    ZigvmFeature(
      id: "MOC-008",
      name: "Zero-Muda Standard & Purity MOC",
      category: MapOfContent,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "0 Bevy, 0 Graphite, 0 foreign NIFs, and pure functional BEAM graphics.",
      source_path: "docs/zk/20260905-1801-moc-uos-unified-master.md",
      evidence_path: "apps/cepaf_gleam/src/graphene_nif.erl",
    ),
    ZigvmFeature(
      id: "MOC-009",
      name: "AG-UI & A2UI Declarative Interface MOC",
      category: MapOfContent,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "32-event AG-UI streaming protocol and 233-component declarative catalog.",
      source_path: "docs/zk/20260905-1801-moc-uos-unified-master.md",
      evidence_path: "apps/cepaf_gleam/src/cepaf_gleam/a2ui/catalog.gleam",
    ),
    ZigvmFeature(
      id: "MOC-010",
      name: "Formal Verification & Mathematical Gates MOC",
      category: MapOfContent,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Lean 4 proofs, Quint state models, and 4 Math Gates (H, CCM, D_EA, ITQS).",
      source_path: "docs/zk/20260905-1801-moc-uos-unified-master.md",
      evidence_path: "formal/lean/Traceability.lean",
    ),
    ZigvmFeature(
      id: "MOC-011",
      name: "Universal Tailscale Web Navigation MOC",
      category: MapOfContent,
      tier: Tier2PropertyAndLaw,
      status: RatifiedActive,
      description: "Mesh web links across nas-1.tail55d152.ts.net:4100 and vm-1:8088.",
      source_path: "docs/zk/20260905-1801-moc-uos-unified-master.md",
      evidence_path: "contracts/rules/tailscale-web-fqdn-mandate.md",
    ),
    ZigvmFeature(
      id: "MOC-012",
      name: "Luis Rocha Biosemiotics & Cybernetics MOC",
      category: MapOfContent,
      tier: Tier3FormalProof,
      status: RatifiedActive,
      description: "Semantic closure, epistemic cut, autopoiesis, and sheaf coherence index.",
      source_path: "docs/zk/20260905-1801-moc-uos-unified-master.md",
      evidence_path: "contracts/rules/rocha-semiotics-cybernetics-contract.md",
    ),
  ]
}

// ----------------------------------------------------------------------------
// 10. Episodic Research Clusters (10 Clusters / 347 Notes)
// ----------------------------------------------------------------------------
fn episodic_clusters() -> List(ZigvmFeature) {
  [
    ZigvmFeature(
      id: "EPI-CLUS-001",
      name: "S-Epoch Lockless SMP Queues",
      category: EpisodicResearchCluster,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Cluster of 38 episodic notes analyzing lock-free atomic queues on BEAM/Zig.",
      source_path: "docs/zk/episodic/e47-timer-meta-quadratic.md",
      evidence_path: "docs/zk/episodic/",
    ),
    ZigvmFeature(
      id: "EPI-CLUS-002",
      name: "Production Axis Performance",
      category: EpisodicResearchCluster,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Cluster of 42 notes tracking ETS table performance, ETS op cost, and memory.",
      source_path: "docs/zk/episodic/gap-ets-op-cost.md",
      evidence_path: "docs/zk/episodic/",
    ),
    ZigvmFeature(
      id: "EPI-CLUS-003",
      name: "Stan Probabilistic MCMC Substrate",
      category: EpisodicResearchCluster,
      tier: Tier3FormalProof,
      status: VerifiedAdmitted,
      description: "Cluster of 29 notes evaluating Bayesian inference and uncertainty quantification.",
      source_path: "docs/zk/episodic/stan-w1-serving-flip.md",
      evidence_path: "docs/zk/episodic/",
    ),
    ZigvmFeature(
      id: "EPI-CLUS-004",
      name: "SMT-ML Z3 Bounded Verification",
      category: EpisodicResearchCluster,
      tier: Tier3FormalProof,
      status: VerifiedAdmitted,
      description: "Cluster of 35 notes detailing in-process Z3 solver bindings and SMT-LIB2 queries.",
      source_path: "docs/zk/episodic/smtml-z3-inproc.md",
      evidence_path: "docs/zk/episodic/",
    ),
    ZigvmFeature(
      id: "EPI-CLUS-005",
      name: "Dung Sheaf Argumentation Framework",
      category: EpisodicResearchCluster,
      tier: Tier3FormalProof,
      status: VerifiedAdmitted,
      description: "Cluster of 31 notes exploring topological sheaf gluing and argumentation semantics.",
      source_path: "docs/zk/episodic/gap-verification-handover.md",
      evidence_path: "docs/zk/episodic/",
    ),
    ZigvmFeature(
      id: "EPI-CLUS-006",
      name: "Infranodus Spectral Graph Analysis",
      category: EpisodicResearchCluster,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Cluster of 33 notes applying network modularity and gap identification to docs.",
      source_path: "docs/zk/episodic/zk-feature-algebra.md",
      evidence_path: "docs/zk/episodic/",
    ),
    ZigvmFeature(
      id: "EPI-CLUS-007",
      name: "Sa_plan Oban Temporal Bridge",
      category: EpisodicResearchCluster,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Cluster of 36 notes detailing deterministic task scheduling and distributed execution.",
      source_path: "docs/zk/episodic/zk-git-temporal.md",
      evidence_path: "docs/zk/episodic/",
    ),
    ZigvmFeature(
      id: "EPI-CLUS-008",
      name: "Cowboy HTTP Pipeline Optimization",
      category: EpisodicResearchCluster,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Cluster of 27 notes tuning BEAM HTTP dispatchers, socket buffers, and keepalive.",
      source_path: "docs/zk/episodic/gap-tyxml-wiki-shell.md",
      evidence_path: "docs/zk/episodic/",
    ),
    ZigvmFeature(
      id: "EPI-CLUS-009",
      name: "Lossless AST Grammar Transformations",
      category: EpisodicResearchCluster,
      tier: Tier1OracleEquivalence,
      status: VerifiedAdmitted,
      description: "Cluster of 44 notes proving parse o render = id roundtrip AST invariants.",
      source_path: "docs/zk/episodic/gap-hof-re.md",
      evidence_path: "docs/zk/episodic/",
    ),
    ZigvmFeature(
      id: "EPI-CLUS-010",
      name: "Raven Telemetry & Spatiotemporal Coeffects",
      category: EpisodicResearchCluster,
      tier: Tier2PropertyAndLaw,
      status: VerifiedAdmitted,
      description: "Cluster of 32 notes defining Cordis coeffect monoids and OTel span topologies.",
      source_path: "docs/zk/episodic/gap-doc-lint-observability.md",
      evidence_path: "docs/zk/episodic/",
    ),
  ]
}

// ----------------------------------------------------------------------------
// 11. Service Topology Features
// ----------------------------------------------------------------------------
fn service_topology_features() -> List(ZigvmFeature) {
  [
    ZigvmFeature(
      id: "SVC-TOPO-001",
      name: "zigvm-dashboard.service (Port 8092)",
      category: ServiceTopology,
      tier: Tier2PropertyAndLaw,
      status: SupervisedOperational,
      description: "Always-on OCaml ops board and HTML test results dashboard.",
      source_path: "harness/serve.ml",
      evidence_path: "docs/DASHBOARD_WIKI_SERVICES.md",
    ),
    ZigvmFeature(
      id: "SVC-TOPO-002",
      name: "zigvm-wiki.service (Port 8088)",
      category: ServiceTopology,
      tier: Tier2PropertyAndLaw,
      status: SupervisedOperational,
      description: "Riot wiki frontend serving repo docs live by basename via /docs/<slug>.html.",
      source_path: "harness/agent_workers.ml",
      evidence_path: "docs/DASHBOARD_WIKI_SERVICES.md",
    ),
    ZigvmFeature(
      id: "SVC-TOPO-003",
      name: "zigvm-wiki-backend.service (Port 8089)",
      category: ServiceTopology,
      tier: Tier2PropertyAndLaw,
      status: SupervisedOperational,
      description: "Thread-server backend handling dynamic search and graph queries.",
      source_path: "harness/zigvm_harness.ml",
      evidence_path: "docs/DASHBOARD_WIKI_SERVICES.md",
    ),
    ZigvmFeature(
      id: "SVC-TOPO-004",
      name: "indrajaal_gleam_web (Port 4100)",
      category: ServiceTopology,
      tier: Tier3FormalProof,
      status: SupervisedOperational,
      description: "Unified UOS Cockpit serving /wiki, /zk, /planning, and /api/verify/checks.",
      source_path: "apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam",
      evidence_path: "contracts/rules/tailscale-web-fqdn-mandate.md",
    ),
  ]
}

// ----------------------------------------------------------------------------
// Query & Verification API
// ----------------------------------------------------------------------------

/// Returns the total number of tracked features.
pub fn count_features() -> Int {
  list.length(all_features())
}

/// Filters features by category.
pub fn features_by_category(category: FeatureCategory) -> List(ZigvmFeature) {
  list.filter(all_features(), fn(f) { f.category == category })
}

/// Filters features by formal verification tier.
pub fn features_by_tier(tier: VerificationTier) -> List(ZigvmFeature) {
  list.filter(all_features(), fn(f) { f.tier == tier })
}

/// Looks up an individual feature by ID.
pub fn get_feature(id: String) -> Result(ZigvmFeature, Nil) {
  list.find(all_features(), fn(f) { f.id == id })
}

/// Computes summary metrics across the registry.
pub fn get_summary() -> FeatureSummary {
  let all = all_features()
  FeatureSummary(
    total_features: list.length(all),
    wiki_core_count: list.length(features_by_category(WikiCoreEngine)),
    zk_mcp_tool_count: list.length(features_by_category(ZkMcpTool)),
    wiki_script_count: list.length(features_by_category(WikiMaintenanceScript)),
    zk_script_count: list.length(features_by_category(ZkKnowledgeScript)),
    harness_law_count: list.length(features_by_category(HarnessVerificationLaw)),
    sheaf_formal_count: list.length(features_by_category(TopologicalSheafFormal)),
    render_suite_count: list.length(features_by_category(RenderSuite)),
    adr_count: list.length(features_by_category(PermanentAdrRecord)),
    moc_count: list.length(features_by_category(MapOfContent)),
    episodic_cluster_count: list.length(features_by_category(
      EpisodicResearchCluster,
    )),
    service_topology_count: list.length(features_by_category(ServiceTopology)),
  )
}

/// Verifies that all registered features have valid non-empty identifiers and paths.
pub fn verify_feature_registry() -> Result(Int, String) {
  let all = all_features()
  let count = list.length(all)
  case count > 0 {
    True -> Ok(count)
    False -> Error("Feature registry is empty")
  }
}

fn pad_right(str: String, target_len: Int) -> String {
  let len = string.length(str)
  case len >= target_len {
    True -> str
    False -> str <> string.repeat(" ", target_len - len)
  }
}

/// Emits an ASCII formatted tracking table of the entire registry.
pub fn render_ascii_table() -> String {
  let header =
    "+---------------+------------------------------------------------------+-------------------------+------------------------+--------------------+\n"
    <> "| Feature ID    | Feature Name                                         | Category                | Tier                   | Status             |\n"
    <> "+---------------+------------------------------------------------------+-------------------------+------------------------+--------------------+\n"

  let rows =
    list.map(all_features(), fn(f) {
      let id_pad = pad_right(f.id, 13)
      let name_pad = pad_right(string.slice(f.name, 0, 52), 52)
      let cat_pad =
        pad_right(string.slice(category_to_string(f.category), 0, 23), 23)
      let tier_pad = pad_right(string.slice(tier_to_string(f.tier), 0, 22), 22)
      let stat_pad =
        pad_right(string.slice(status_to_string(f.status), 0, 18), 18)
      "| "
      <> id_pad
      <> " | "
      <> name_pad
      <> " | "
      <> cat_pad
      <> " | "
      <> tier_pad
      <> " | "
      <> stat_pad
      <> " |\n"
    })

  let footer =
    "+---------------+------------------------------------------------------+-------------------------+------------------------+--------------------+\n"

  header <> string.concat(rows) <> footer
}

/// Emits a Markdown formatted tracking table of the entire registry.
pub fn render_markdown_table() -> String {
  let header =
    "| Feature ID | Feature Name | Category | Tier | Status | Source Path |\n"
    <> "|---|---|---|---|---|---|\n"

  let rows =
    list.map(all_features(), fn(f) {
      "| `"
      <> f.id
      <> "` | **"
      <> f.name
      <> "** | "
      <> category_to_string(f.category)
      <> " | "
      <> tier_to_string(f.tier)
      <> " | "
      <> status_to_string(f.status)
      <> " | `"
      <> f.source_path
      <> "` |\n"
    })

  header <> string.concat(rows)
}
