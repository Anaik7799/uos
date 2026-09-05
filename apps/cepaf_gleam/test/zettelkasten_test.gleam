import cepaf_gleam/zettelkasten/entropy
import cepaf_gleam/zettelkasten/ingestion
import cepaf_gleam/zettelkasten/linker
import cepaf_gleam/zettelkasten/metrics
import cepaf_gleam/zettelkasten/trust
import cepaf_gleam/zettelkasten/types
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Types tests — Five forms of self-knowledge
// =============================================================================

pub fn trust_for_axiom_is_highest_test() {
  types.trust_for(types.Axiom).value |> should.equal(1.0)
}

pub fn trust_for_evidence_test() {
  types.trust_for(types.Evidence).value |> should.equal(0.9)
}

pub fn trust_for_hypothesis_test() {
  types.trust_for(types.Hypothesis).value |> should.equal(0.5)
}

pub fn trust_for_anecdote_is_lowest_test() {
  types.trust_for(types.Anecdote).value |> should.equal(0.3)
}

pub fn level_for_architecture_path_test() {
  types.level_for_path("docs/architecture/vision.md")
  |> should.equal(types.Ecosystem)
}

pub fn level_for_journal_path_test() {
  types.level_for_path("docs/journal/20260410.md")
  |> should.equal(types.Organism)
}

pub fn level_for_plan_path_test() {
  types.level_for_path("docs/plans/decomposition.md")
  |> should.equal(types.Molecular)
}

pub fn level_for_allium_path_test() {
  types.level_for_path("specs/allium/ignition.allium")
  |> should.equal(types.Molecular)
}

pub fn level_for_rules_path_test() {
  types.level_for_path(".claude/rules/wiring-guard.md")
  |> should.equal(types.Atomic)
}

pub fn rhetorical_for_rules_is_axiom_test() {
  types.rhetorical_for_path(".claude/rules/constraint.md")
  |> should.equal(types.Axiom)
}

pub fn rhetorical_for_architecture_is_axiom_test() {
  types.rhetorical_for_path("docs/architecture/vision.md")
  |> should.equal(types.Axiom)
}

pub fn rhetorical_for_specs_is_hypothesis_test() {
  types.rhetorical_for_path("specs/allium/ignition.allium")
  |> should.equal(types.Hypothesis)
}

pub fn rhetorical_for_journal_is_evidence_test() {
  types.rhetorical_for_path("docs/journal/session.md")
  |> should.equal(types.Evidence)
}

pub fn self_knowledge_architecture_is_identity_test() {
  types.self_knowledge_for_path("docs/architecture/vision.md")
  |> should.equal(types.Identity)
}

pub fn self_knowledge_journal_is_history_test() {
  types.self_knowledge_for_path("docs/journal/session.md")
  |> should.equal(types.History)
}

pub fn self_knowledge_allium_is_intent_test() {
  types.self_knowledge_for_path("specs/allium/ignition.allium")
  |> should.equal(types.Intent)
}

pub fn self_knowledge_rules_is_constraints_test() {
  types.self_knowledge_for_path(".claude/rules/wiring.md")
  |> should.equal(types.Constraints)
}

pub fn decay_for_ecosystem_is_slow_test() {
  types.decay_for_level(types.Ecosystem) |> should.equal(types.Slow)
}

pub fn decay_for_atomic_is_fast_test() {
  types.decay_for_level(types.Atomic) |> should.equal(types.Fast)
}

pub fn level_to_string_test() {
  types.level_to_string(types.Molecular) |> should.equal("molecular")
}

pub fn link_type_to_string_test() {
  types.link_type_to_string(types.Code) |> should.equal("code")
}

// =============================================================================
// Entropy tests — Forgetting curve
// =============================================================================

fn make_test_holon(entropy: Float, decay: types.DecayRate) -> types.Holon {
  types.Holon(
    uuid: "test-1",
    title: "Test Holon",
    content: "Test content",
    tags: [],
    level: types.Atomic,
    rhetorical: types.Evidence,
    entropy: entropy,
    decay_rate: decay,
    source: types.ManualSource(author: "test"),
    content_hash: "abc123",
    cluster: None,
    stamp_refs: [],
    created_at: "2026-04-11",
    updated_at: "2026-04-11",
    verified_at: None,
  )
}

pub fn slow_decay_increment_test() {
  entropy.daily_entropy_increment(types.Slow) |> should.equal(0.003)
}

pub fn medium_decay_increment_test() {
  entropy.daily_entropy_increment(types.Medium) |> should.equal(0.01)
}

pub fn fast_decay_increment_test() {
  entropy.daily_entropy_increment(types.Fast) |> should.equal(0.03)
}

pub fn entropy_after_zero_days_unchanged_test() {
  entropy.entropy_after_days(0.5, types.Medium, 0) |> should.equal(0.5)
}

pub fn entropy_after_10_days_medium_test() {
  let result = entropy.entropy_after_days(0.0, types.Medium, 10)
  // 0.0 + 0.01 * 10 = 0.1
  { result >. 0.09 && result <. 0.11 } |> should.be_true
}

pub fn entropy_clamped_at_1_test() {
  entropy.entropy_after_days(0.95, types.Fast, 100) |> should.equal(1.0)
}

pub fn entropy_clamped_at_0_test() {
  entropy.entropy_after_days(0.0, types.Slow, 0) |> should.equal(0.0)
}

pub fn is_fresh_below_03_test() {
  make_test_holon(0.2, types.Medium) |> entropy.is_fresh |> should.be_true
}

pub fn is_not_fresh_above_03_test() {
  make_test_holon(0.5, types.Medium) |> entropy.is_fresh |> should.be_false
}

pub fn is_rotting_above_07_test() {
  make_test_holon(0.8, types.Medium) |> entropy.is_rotting |> should.be_true
}

pub fn is_not_rotting_below_07_test() {
  make_test_holon(0.5, types.Medium) |> entropy.is_rotting |> should.be_false
}

pub fn excluded_from_rag_above_09_test() {
  make_test_holon(0.95, types.Medium)
  |> entropy.is_excluded_from_rag
  |> should.be_true
}

pub fn not_excluded_below_09_test() {
  make_test_holon(0.7, types.Medium)
  |> entropy.is_excluded_from_rag
  |> should.be_false
}

pub fn verify_resets_entropy_test() {
  let holon = make_test_holon(0.8, types.Medium)
  let verified = entropy.verify(holon, "2026-04-11T12:00:00Z")
  verified.entropy |> should.equal(0.0)
  verified.verified_at |> should.equal(Some("2026-04-11T12:00:00Z"))
}

pub fn apply_daily_decay_increases_entropy_test() {
  let holon = make_test_holon(0.0, types.Fast)
  let decayed = entropy.apply_daily_decay(holon)
  { decayed.entropy >. 0.02 } |> should.be_true
}

pub fn entropy_label_fresh_test() {
  entropy.entropy_label(0.1) |> should.equal("fresh")
}

pub fn entropy_label_aging_test() {
  entropy.entropy_label(0.5) |> should.equal("aging")
}

pub fn entropy_label_rotting_test() {
  entropy.entropy_label(0.8) |> should.equal("rotting")
}

pub fn entropy_label_excluded_test() {
  entropy.entropy_label(0.95) |> should.equal("excluded")
}

pub fn days_until_rotting_fresh_slow_test() {
  let holon = make_test_holon(0.0, types.Slow)
  let days = entropy.days_until_rotting(holon)
  // 0.7 / 0.003 = 233.3 → 234 days
  { days > 230 && days < 240 } |> should.be_true
}

pub fn days_until_rotting_fresh_fast_test() {
  let holon = make_test_holon(0.0, types.Fast)
  let days = entropy.days_until_rotting(holon)
  // 0.7 / 0.03 = 23.3 → 24 days
  { days > 22 && days < 26 } |> should.be_true
}

pub fn days_until_rotting_already_rotting_test() {
  let holon = make_test_holon(0.8, types.Medium)
  entropy.days_until_rotting(holon) |> should.equal(0)
}

// =============================================================================
// Trust tests — Knowledge authority
// =============================================================================

pub fn effective_trust_fresh_axiom_test() {
  let holon = make_test_holon(0.0, types.Slow)
  let h = types.Holon(..holon, rhetorical: types.Axiom)
  let t = trust.effective_trust(h)
  // 1.0 * (1.0 - 0.0) = 1.0
  t |> should.equal(1.0)
}

pub fn effective_trust_degraded_axiom_test() {
  let holon = make_test_holon(0.5, types.Slow)
  let h = types.Holon(..holon, rhetorical: types.Axiom)
  let t = trust.effective_trust(h)
  // 1.0 * (1.0 - 0.5) = 0.5
  t |> should.equal(0.5)
}

pub fn effective_trust_rotting_anecdote_test() {
  let holon = make_test_holon(0.9, types.Fast)
  let h = types.Holon(..holon, rhetorical: types.Anecdote)
  let t = trust.effective_trust(h)
  // 0.3 * (1.0 - 0.9) = 0.03
  { t <. 0.04 } |> should.be_true
}

pub fn rag_eligible_fresh_axiom_test() {
  let holon = make_test_holon(0.0, types.Slow)
  let h = types.Holon(..holon, rhetorical: types.Axiom)
  trust.is_rag_eligible(h) |> should.be_true
}

pub fn rag_ineligible_excluded_test() {
  let holon = make_test_holon(0.95, types.Fast)
  trust.is_rag_eligible(holon) |> should.be_false
}

pub fn trust_label_high_test() {
  trust.trust_label(0.9) |> should.equal("high")
}

pub fn trust_label_medium_test() {
  trust.trust_label(0.6) |> should.equal("medium")
}

pub fn trust_label_low_test() {
  trust.trust_label(0.3) |> should.equal("low")
}

pub fn trust_label_untrusted_test() {
  trust.trust_label(0.05) |> should.equal("untrusted")
}

pub fn authority_rank_ordering_test() {
  let axiom = trust.authority_rank(types.Axiom)
  let evidence = trust.authority_rank(types.Evidence)
  let hypothesis = trust.authority_rank(types.Hypothesis)
  let anecdote = trust.authority_rank(types.Anecdote)
  { axiom > evidence } |> should.be_true
  { evidence > hypothesis } |> should.be_true
  { hypothesis > anecdote } |> should.be_true
}

pub fn aggregate_trust_empty_test() {
  trust.aggregate_trust([]) |> should.equal(0.0)
}

pub fn filter_trusted_removes_low_test() {
  let h1 = make_test_holon(0.0, types.Slow)
  let h1 = types.Holon(..h1, rhetorical: types.Axiom, uuid: "h1")
  let h2 = make_test_holon(0.95, types.Fast)
  let h2 = types.Holon(..h2, rhetorical: types.Anecdote, uuid: "h2")
  let filtered = trust.filter_trusted([h1, h2], 0.1)
  list.length(filtered) |> should.equal(1)
}

// =============================================================================
// Linker tests — Auto-linking
// =============================================================================

pub fn extract_stamp_refs_finds_sc_test() {
  let content =
    "This module implements SC-ZENOH-001 and SC-GLM-UI-002 compliance."
  let refs = linker.extract_stamp_refs(content)
  list.contains(refs, "SC-ZENOH-001") |> should.be_true
  list.contains(refs, "SC-GLM-UI-002") |> should.be_true
}

pub fn extract_stamp_refs_empty_content_test() {
  linker.extract_stamp_refs("no stamps here") |> should.equal([])
}

pub fn extract_stamp_refs_deduplicates_test() {
  let content = "SC-ZENOH-001 is referenced twice: SC-ZENOH-001"
  let refs = linker.extract_stamp_refs(content)
  list.length(refs) |> should.equal(1)
}

pub fn extract_module_refs_finds_gleam_paths_test() {
  let content = "Import from cepaf_gleam/ui/lustre/app for dashboard"
  let refs = linker.extract_module_refs(content)
  list.contains(refs, "cepaf_gleam/ui/lustre/app") |> should.be_true
}

pub fn extract_file_refs_finds_gleam_files_test() {
  let content = "See src/cepaf_gleam/ui/lustre/planning.gleam for details"
  let refs = linker.extract_file_refs(content)
  list.length(refs) |> should.equal(1)
}

pub fn extract_file_refs_finds_rust_files_test() {
  let content = "Implemented in native/planning_daemon/src/cortex.rs"
  let refs = linker.extract_file_refs(content)
  list.length(refs) |> should.equal(1)
}

pub fn link_by_stamp_creates_edges_test() {
  let content = "SC-ZENOH-001 requires mesh connectivity"
  let mapping = [#("SC-ZENOH-001", "holon-zenoh")]
  let edges = linker.link_by_stamp("holon-source", content, mapping)
  list.length(edges) |> should.equal(1)
}

pub fn link_bidirectional_creates_two_edges_test() {
  let edges = linker.link_bidirectional("a", "b", 0.8)
  list.length(edges) |> should.equal(2)
}

pub fn find_orphans_detects_unconnected_test() {
  let edges = [types.HolonEdge("a", "b", types.Wiki, 1.0)]
  let orphans = linker.find_orphans(["a", "b", "c"], edges)
  list.contains(orphans, "c") |> should.be_true
  list.contains(orphans, "a") |> should.be_false
}

pub fn graph_density_complete_graph_test() {
  // 3 nodes, 6 edges (complete directed graph) → density = 6/(3*2) = 1.0
  let d = linker.graph_density(3, 6)
  { d >. 0.99 } |> should.be_true
}

pub fn graph_density_empty_test() {
  linker.graph_density(5, 0) |> should.equal(0.0)
}

pub fn graph_density_single_node_test() {
  linker.graph_density(1, 0) |> should.equal(0.0)
}

// =============================================================================
// Ingestion tests — Document parsing
// =============================================================================

pub fn extract_title_from_h1_test() {
  ingestion.extract_title("# My Title\nContent here", "fallback")
  |> should.equal("My Title")
}

pub fn extract_title_from_h2_test() {
  ingestion.extract_title("## Section Title\nContent", "fallback")
  |> should.equal("Section Title")
}

pub fn extract_title_from_allium_comment_test() {
  ingestion.extract_title("-- allium: 3\n-- My Spec", "fallback")
  |> should.equal("allium: 3")
}

pub fn extract_title_fallback_on_empty_test() {
  ingestion.extract_title("", "fallback")
  |> should.equal("fallback")
}

pub fn parse_small_document_single_holon_test() {
  let content = "# Small Doc\nJust a few lines\nNothing much"
  let holons =
    ingestion.parse_document(
      "docs/plans/small.md",
      content,
      "test",
      "2026-04-11",
    )
  list.length(holons) |> should.equal(1)
}

pub fn parse_document_assigns_correct_level_test() {
  let content = "# Architecture\nSystem overview"
  let holons =
    ingestion.parse_document(
      "docs/architecture/overview.md",
      content,
      "arch",
      "2026-04-11",
    )
  case holons {
    [h, ..] -> h.level |> should.equal(types.Ecosystem)
    [] -> should.be_true(False)
  }
}

pub fn parse_document_assigns_correct_rhetorical_test() {
  let content = "# Rule\nSC-FUNC-001 must pass"
  let holons =
    ingestion.parse_document(
      ".claude/rules/func.md",
      content,
      "rule",
      "2026-04-11",
    )
  case holons {
    [h, ..] -> h.rhetorical |> should.equal(types.Axiom)
    [] -> should.be_true(False)
  }
}

pub fn parse_document_extracts_stamps_test() {
  let content = "# Rule\nSC-FUNC-001 and SC-ZENOH-002 apply"
  let holons =
    ingestion.parse_document(
      ".claude/rules/func.md",
      content,
      "rule",
      "2026-04-11",
    )
  case holons {
    [h, ..] -> { list.length(h.stamp_refs) >= 1 } |> should.be_true
    [] -> should.be_true(False)
  }
}

pub fn compute_content_hash_deterministic_test() {
  let h1 = ingestion.compute_content_hash("hello world")
  let h2 = ingestion.compute_content_hash("hello world")
  h1 |> should.equal(h2)
}

pub fn compute_content_hash_different_for_different_content_test() {
  let h1 = ingestion.compute_content_hash("hello")
  let h2 = ingestion.compute_content_hash("world")
  { h1 != h2 } |> should.be_true
}

pub fn summarize_results_test() {
  let results = [
    ingestion.IngestionResult("a.md", 3, 5, []),
    ingestion.IngestionResult("b.md", 2, 1, ["warning"]),
  ]
  let summary = ingestion.summarize(results)
  string.contains(summary, "2 documents") |> should.be_true
  string.contains(summary, "5 holons") |> should.be_true
}

// =============================================================================
// Metrics tests — Knowledge graph health
// =============================================================================

fn make_holons_for_metrics() -> List(types.Holon) {
  let fresh = make_test_holon(0.1, types.Slow)
  let aging = make_test_holon(0.5, types.Medium)
  let rotting = make_test_holon(0.8, types.Fast)
  [
    types.Holon(..fresh, uuid: "h1", level: types.Ecosystem),
    types.Holon(..aging, uuid: "h2", level: types.Molecular),
    types.Holon(..rotting, uuid: "h3", level: types.Atomic),
  ]
}

pub fn metrics_compute_counts_test() {
  let holons = make_holons_for_metrics()
  let edges = [types.HolonEdge("h1", "h2", types.Wiki, 1.0)]
  let m = metrics.compute(holons, edges)
  m.total_holons |> should.equal(3)
  m.total_edges |> should.equal(1)
  m.fresh_count |> should.equal(1)
  m.aging_count |> should.equal(1)
  m.rotting_count |> should.equal(1)
}

pub fn metrics_orphan_detection_test() {
  let holons = make_holons_for_metrics()
  let edges = [types.HolonEdge("h1", "h2", types.Wiki, 1.0)]
  let m = metrics.compute(holons, edges)
  // h3 has no edges
  m.orphan_count |> should.equal(1)
}

pub fn metrics_level_distribution_test() {
  let holons = make_holons_for_metrics()
  let m = metrics.compute(holons, [])
  m.level_distribution.ecosystem |> should.equal(1)
  m.level_distribution.molecular |> should.equal(1)
  m.level_distribution.atomic |> should.equal(1)
}

pub fn health_grade_thriving_test() {
  let m =
    metrics.KnowledgeGraphMetrics(
      total_holons: 100,
      total_edges: 500,
      fresh_count: 95,
      aging_count: 4,
      rotting_count: 1,
      excluded_count: 0,
      orphan_count: 2,
      avg_entropy: 0.1,
      avg_trust: 0.85,
      density: 0.05,
      level_distribution: metrics.LevelDistribution(50, 30, 15, 5),
    )
  metrics.health_grade(m) |> should.equal(metrics.Thriving)
}

pub fn health_grade_critical_test() {
  let m =
    metrics.KnowledgeGraphMetrics(
      total_holons: 100,
      total_edges: 10,
      fresh_count: 10,
      aging_count: 20,
      rotting_count: 40,
      excluded_count: 30,
      orphan_count: 50,
      avg_entropy: 0.8,
      avg_trust: 0.2,
      density: 0.001,
      level_distribution: metrics.LevelDistribution(80, 10, 8, 2),
    )
  metrics.health_grade(m) |> should.equal(metrics.Critical)
}

pub fn health_label_test() {
  metrics.health_label(metrics.Thriving) |> should.equal("THRIVING")
  metrics.health_label(metrics.Critical) |> should.equal("CRITICAL")
}

pub fn project_growth_test() {
  let #(holons, _edges) = metrics.project_growth(500, 360, 4.0, 3)
  // 500 + 360*3 = 1580
  holons |> should.equal(1580)
}

pub fn empty_graph_metrics_test() {
  let m = metrics.compute([], [])
  m.total_holons |> should.equal(0)
  m.avg_entropy |> should.equal(0.0)
  m.avg_trust |> should.equal(0.0)
}
