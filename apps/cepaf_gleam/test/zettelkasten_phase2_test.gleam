import cepaf_gleam/zettelkasten/export
import cepaf_gleam/zettelkasten/rules
import cepaf_gleam/zettelkasten/search
import cepaf_gleam/zettelkasten/types
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Test holon constructor
// =============================================================================

fn h(
  uuid: String,
  title: String,
  level: types.HolonLevel,
  rhetorical: types.RhetoricalFunction,
  entropy: Float,
  stamps: List(String),
  cluster: option.Option(String),
) -> types.Holon {
  types.Holon(
    uuid: uuid,
    title: title,
    content: "Content for " <> title,
    tags: ["test"],
    level: level,
    rhetorical: rhetorical,
    entropy: entropy,
    decay_rate: types.Medium,
    source: types.ManualSource(author: "test"),
    content_hash: "hash-" <> uuid,
    cluster: cluster,
    stamp_refs: stamps,
    created_at: "2026-04-11",
    updated_at: "2026-04-11",
    verified_at: None,
  )
}

// =============================================================================
// Rules tests — Knowledge RETE-UL
// =============================================================================

pub fn rules_no_alerts_on_healthy_graph_test() {
  let holons = [
    h(
      "h1",
      "Architecture",
      types.Ecosystem,
      types.Axiom,
      0.1,
      [],
      Some("architecture"),
    ),
    h("h2", "Plan", types.Molecular, types.Hypothesis, 0.2, [], Some("plans")),
  ]
  let edges = [types.HolonEdge("h1", "h2", types.Wiki, 1.0)]
  let alerts = rules.evaluate_knowledge(holons, edges)
  list.length(alerts) |> should.equal(0)
}

pub fn rules_stale_architecture_alert_test() {
  let holons = [
    h(
      "h1",
      "Old Architecture",
      types.Ecosystem,
      types.Axiom,
      0.8,
      [],
      Some("architecture"),
    ),
  ]
  let alerts = rules.evaluate_knowledge(holons, [])
  // At least 1 alert (StaleArchitecture), may also have orphan alerts
  { list.length(alerts) >= 1 } |> should.be_true
  let stale_alerts =
    list.filter(alerts, fn(a) {
      case a.0 {
        rules.StaleArchitecture(_, _, _) -> True
        _ -> False
      }
    })
  list.length(stale_alerts) |> should.equal(1)
}

pub fn rules_orphaned_constraint_alert_test() {
  let holons = [
    h(
      "h1",
      "Zenoh Rule",
      types.Atomic,
      types.Axiom,
      0.0,
      ["SC-ZENOH-001"],
      Some("constraints"),
    ),
  ]
  // No edges → constraint is orphaned
  let alerts = rules.evaluate_knowledge(holons, [])
  let orphaned =
    list.filter(alerts, fn(a) {
      case a.0 {
        rules.OrphanedConstraint(_) -> True
        _ -> False
      }
    })
  list.length(orphaned) |> should.equal(1)
}

pub fn rules_no_orphan_when_connected_test() {
  let holons = [
    h(
      "h1",
      "Zenoh Rule",
      types.Atomic,
      types.Axiom,
      0.0,
      ["SC-ZENOH-001"],
      Some("constraints"),
    ),
    h("h2", "Zenoh Module", types.Atomic, types.Evidence, 0.0, [], Some("code")),
  ]
  let edges = [types.HolonEdge("h2", "h1", types.Code, 1.0)]
  let alerts = rules.evaluate_knowledge(holons, edges)
  let orphaned =
    list.filter(alerts, fn(a) {
      case a.0 {
        rules.OrphanedConstraint(_) -> True
        _ -> False
      }
    })
  list.length(orphaned) |> should.equal(0)
}

pub fn rules_incident_recurrence_test() {
  let past_incidents = [
    h(
      "inc1",
      "March 24 Deletion",
      types.Organism,
      types.Evidence,
      0.3,
      [],
      None,
    )
    |> fn(holon) { types.Holon(..holon, tags: ["file_deletion", "git_clean"]) },
  ]
  let alerts = rules.check_incident_recurrence("file_deletion", past_incidents)
  list.length(alerts) |> should.equal(1)
}

pub fn rules_no_incident_match_test() {
  let past_incidents = [
    h(
      "inc1",
      "March 24 Deletion",
      types.Organism,
      types.Evidence,
      0.3,
      [],
      None,
    )
    |> fn(holon) { types.Holon(..holon, tags: ["file_deletion"]) },
  ]
  let alerts = rules.check_incident_recurrence("cpu_spike", past_incidents)
  list.length(alerts) |> should.equal(0)
}

pub fn rules_count_by_severity_test() {
  let alerts = [
    #(rules.StaleArchitecture("a", 0.8, 30), rules.High),
    #(rules.OrphanedConstraint("SC-X"), rules.Medium),
    #(rules.RotCountExceeded(50, 100, 0.5), rules.Critical),
  ]
  let #(c, h, m, l) = rules.count_by_severity(alerts)
  c |> should.equal(1)
  h |> should.equal(1)
  m |> should.equal(1)
  l |> should.equal(0)
}

pub fn rules_severity_label_test() {
  rules.severity_label(rules.Critical) |> should.equal("CRITICAL")
  rules.severity_label(rules.Low) |> should.equal("LOW")
}

// =============================================================================
// Search tests — FTS5 query builder + in-memory search
// =============================================================================

pub fn search_default_query_test() {
  let q = search.query("apoptosis schedule")
  q.limit |> should.equal(5)
  { q.max_entropy >. 0.89 } |> should.be_true
}

pub fn search_with_level_filter_test() {
  let q = search.query("zenoh") |> search.with_level(types.Ecosystem)
  q.level_filter |> should.equal(Some(types.Ecosystem))
}

pub fn search_with_cluster_filter_test() {
  let q = search.query("zenoh") |> search.with_cluster("architecture")
  q.cluster_filter |> should.equal(Some("architecture"))
}

pub fn search_fts5_query_builds_or_test() {
  let q = search.query("apoptosis schedule container")
  let fts = search.to_fts5_query(q)
  string.contains(fts, "OR") |> should.be_true
  string.contains(fts, "apoptosis") |> should.be_true
}

pub fn search_fts5_filters_short_words_test() {
  let q = search.query("a an the apoptosis")
  let fts = search.to_fts5_query(q)
  // "a", "an" are <= 2 chars, filtered out
  string.contains(fts, "the") |> should.be_true
  string.contains(fts, "apoptosis") |> should.be_true
}

pub fn search_in_memory_finds_matching_test() {
  let holons = [
    h(
      "h1",
      "Apoptosis Design",
      types.Ecosystem,
      types.Axiom,
      0.1,
      [],
      Some("architecture"),
    ),
    h(
      "h2",
      "Planning Tasks",
      types.Molecular,
      types.Hypothesis,
      0.2,
      [],
      Some("plans"),
    ),
  ]
  let q = search.query("apoptosis")
  let results = search.search_in_memory(holons, q)
  list.length(results) |> should.equal(1)
  case results {
    [r] -> r.holon.title |> should.equal("Apoptosis Design")
    _ -> should.be_true(False)
  }
}

pub fn search_in_memory_respects_entropy_filter_test() {
  let holons = [
    h("h1", "Stale Doc", types.Atomic, types.Anecdote, 0.95, [], None),
  ]
  let q = search.query("stale") |> search.with_max_entropy(0.9)
  let results = search.search_in_memory(holons, q)
  list.length(results) |> should.equal(0)
}

pub fn search_in_memory_respects_level_filter_test() {
  let holons = [
    h("h1", "Zenoh Arch", types.Ecosystem, types.Axiom, 0.0, [], None),
    h("h2", "Zenoh Config", types.Atomic, types.Evidence, 0.0, [], None),
  ]
  let q = search.query("zenoh") |> search.with_level(types.Ecosystem)
  let results = search.search_in_memory(holons, q)
  list.length(results) |> should.equal(1)
}

pub fn search_in_memory_respects_limit_test() {
  let holons = [
    h("h1", "Doc Alpha", types.Atomic, types.Evidence, 0.0, [], None),
    h("h2", "Doc Beta", types.Atomic, types.Evidence, 0.0, [], None),
    h("h3", "Doc Gamma", types.Atomic, types.Evidence, 0.0, [], None),
  ]
  let q = search.query("doc") |> search.with_limit(2)
  let results = search.search_in_memory(holons, q)
  list.length(results) |> should.equal(2)
}

pub fn search_rag_context_format_test() {
  let holons = [
    h("h1", "Apoptosis Guide", types.Ecosystem, types.Axiom, 0.0, [], None),
  ]
  let results = search.search_in_memory(holons, search.query("apoptosis"))
  let ctx = search.to_rag_context("apoptosis", results)
  let formatted = search.rag_context_to_string(ctx)
  string.contains(formatted, "Relevant system knowledge") |> should.be_true
  string.contains(formatted, "Apoptosis Guide") |> should.be_true
}

pub fn search_empty_rag_context_test() {
  let ctx = search.to_rag_context("nothing", [])
  search.rag_context_to_string(ctx) |> should.equal("")
}

// =============================================================================
// Export tests — Obsidian vault
// =============================================================================

pub fn export_frontmatter_contains_uuid_test() {
  let holon =
    h("uuid-123", "Test Doc", types.Atomic, types.Evidence, 0.3, [], None)
  let md = export.holon_to_obsidian(holon, [])
  string.contains(md, "uuid: uuid-123") |> should.be_true
}

pub fn export_frontmatter_contains_level_test() {
  let holon = h("h1", "Arch Doc", types.Ecosystem, types.Axiom, 0.0, [], None)
  let md = export.holon_to_obsidian(holon, [])
  string.contains(md, "level: ecosystem") |> should.be_true
}

pub fn export_frontmatter_contains_entropy_test() {
  let holon = h("h1", "Doc", types.Atomic, types.Evidence, 0.42, [], None)
  let md = export.holon_to_obsidian(holon, [])
  string.contains(md, "entropy: 0.42") |> should.be_true
}

pub fn export_includes_content_test() {
  let holon = h("h1", "Doc", types.Atomic, types.Evidence, 0.0, [], None)
  let md = export.holon_to_obsidian(holon, [])
  string.contains(md, "Content for Doc") |> should.be_true
}

pub fn export_includes_stamp_refs_test() {
  let holon =
    h(
      "h1",
      "Rule",
      types.Atomic,
      types.Axiom,
      0.0,
      ["SC-ZENOH-001", "SC-FUNC-001"],
      None,
    )
  let md = export.holon_to_obsidian(holon, [])
  string.contains(md, "SC-ZENOH-001") |> should.be_true
  string.contains(md, "STAMP References") |> should.be_true
}

pub fn export_includes_backlinks_test() {
  let holon = h("h1", "Target", types.Atomic, types.Evidence, 0.0, [], None)
  let edges = [types.HolonEdge("h2", "h1", types.Wiki, 1.0)]
  let md = export.holon_to_obsidian(holon, edges)
  string.contains(md, "Backlinks") |> should.be_true
  string.contains(md, "[[h2]]") |> should.be_true
}

pub fn export_no_backlinks_when_none_test() {
  let holon = h("h1", "Orphan", types.Atomic, types.Evidence, 0.0, [], None)
  let md = export.holon_to_obsidian(holon, [])
  string.contains(md, "Backlinks") |> should.be_false
}

pub fn export_index_contains_sections_test() {
  let holons = [
    h("h1", "Arch Vision", types.Ecosystem, types.Axiom, 0.0, [], None),
    h("h2", "Deploy Plan", types.Molecular, types.Hypothesis, 0.0, [], None),
    h("h3", "Session Log", types.Organism, types.Evidence, 0.0, [], None),
  ]
  let index = export.generate_index(holons)
  string.contains(index, "Architecture (Ecosystem)") |> should.be_true
  string.contains(index, "Specifications (Molecular)") |> should.be_true
  string.contains(index, "Sessions (Organism)") |> should.be_true
  string.contains(index, "[[Arch Vision]]") |> should.be_true
}

pub fn export_obsidian_config_is_json_test() {
  let config = export.obsidian_config()
  string.contains(config, "strictLineBreaks") |> should.be_true
}

pub fn export_vault_filename_sanitizes_test() {
  let holon =
    h("h1", "What/Is:This?", types.Atomic, types.Evidence, 0.0, [], None)
  let filename = export.vault_filename(holon)
  string.contains(filename, "/") |> should.be_false
  string.contains(filename, ":") |> should.be_false
  string.contains(filename, "?") |> should.be_false
  string.ends_with(filename, ".md") |> should.be_true
}
