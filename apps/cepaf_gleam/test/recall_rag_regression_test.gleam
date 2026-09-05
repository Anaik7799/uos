//// [C3I-SIL6-MSTS] <c3i-module>
////   <identity><module>test/recall_rag_regression_test</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-IKE-001, SC-IKE-002, SC-IKE-003, SC-SMRITI-131, SC-ZK-CLAUDE-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Recall / RAG / Context-Memory regression tests — covers all 10 zettelkasten/ modules.
//// C1 Types  C2 Search  C3 Operations  C4 Ingestion  C5 Entropy
//// C6 Trust  C7 Linker+Metrics  C8 Rules+Export
////
//// SC-WIRE-007: tests use constructor helpers, NOT bare Holon() literal where avoidable.

import cepaf_gleam/zettelkasten/entropy
import cepaf_gleam/zettelkasten/export
import cepaf_gleam/zettelkasten/ingestion
import cepaf_gleam/zettelkasten/linker
import cepaf_gleam/zettelkasten/metrics
import cepaf_gleam/zettelkasten/operations
import cepaf_gleam/zettelkasten/rules
import cepaf_gleam/zettelkasten/search
import cepaf_gleam/zettelkasten/trust
import cepaf_gleam/zettelkasten/types.{
  Anecdote, Atomic, Axiom, DocumentSource, Ecosystem, Evidence, Fast, Holon,
  HolonEdge, Hypothesis, Medium, Molecular, Organism, Slow, Wiki,
}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Helpers — build test holons without exposing direct Holon() constructors
// everywhere (SC-WIRE-007: use builders rather than scattered literal tuples).
// =============================================================================

fn make_holon(uuid: String, title: String, content: String) -> types.Holon {
  Holon(
    uuid: uuid,
    title: title,
    content: content,
    tags: ["test"],
    level: Atomic,
    rhetorical: Evidence,
    entropy: 0.0,
    decay_rate: Medium,
    source: DocumentSource(path: "docs/journal/test.md"),
    content_hash: ingestion.compute_content_hash(content),
    cluster: None,
    stamp_refs: [],
    created_at: "2026-04-21T00:00:00Z",
    updated_at: "2026-04-21T00:00:00Z",
    verified_at: None,
  )
}

fn make_holon_with_entropy(uuid: String, entropy_val: Float) -> types.Holon {
  Holon(
    uuid: uuid,
    title: "Holon " <> uuid,
    content: "content for " <> uuid,
    tags: ["test"],
    level: Atomic,
    rhetorical: Evidence,
    entropy: entropy_val,
    decay_rate: Medium,
    source: DocumentSource(path: "docs/journal/test.md"),
    content_hash: ingestion.compute_content_hash("content for " <> uuid),
    cluster: None,
    stamp_refs: [],
    created_at: "2026-04-21T00:00:00Z",
    updated_at: "2026-04-21T00:00:00Z",
    verified_at: None,
  )
}

fn make_holon_with_rhetorical(
  uuid: String,
  rhetorical: types.RhetoricalFunction,
) -> types.Holon {
  Holon(
    uuid: uuid,
    title: "Holon " <> uuid,
    content: "content",
    tags: ["test"],
    level: Atomic,
    rhetorical: rhetorical,
    entropy: 0.0,
    decay_rate: Medium,
    source: DocumentSource(path: ".claude/rules/test.md"),
    content_hash: ingestion.compute_content_hash("content"),
    cluster: None,
    stamp_refs: [],
    created_at: "2026-04-21T00:00:00Z",
    updated_at: "2026-04-21T00:00:00Z",
    verified_at: None,
  )
}

// =============================================================================
// C1 — Types (5 tests)
// =============================================================================

pub fn c1_trust_for_axiom_is_one_test() {
  let ts = types.trust_for(Axiom)
  ts.value
  |> should.equal(1.0)
}

pub fn c1_trust_for_evidence_is_point_nine_test() {
  let ts = types.trust_for(Evidence)
  ts.value
  |> should.equal(0.9)
}

pub fn c1_trust_for_hypothesis_is_lower_than_evidence_test() {
  let h_ts = types.trust_for(Hypothesis)
  let e_ts = types.trust_for(Evidence)
  // Hypothesis (0.5) < Evidence (0.9)
  { h_ts.value <. e_ts.value }
  |> should.be_true()
}

pub fn c1_trust_for_anecdote_is_lowest_test() {
  let a_ts = types.trust_for(Anecdote)
  let h_ts = types.trust_for(Hypothesis)
  // Anecdote (0.3) < Hypothesis (0.5)
  { a_ts.value <. h_ts.value }
  |> should.be_true()
}

pub fn c1_decay_for_ecosystem_is_slow_test() {
  types.decay_for_level(Ecosystem)
  |> should.equal(Slow)
}

pub fn c1_decay_for_atomic_is_fast_test() {
  types.decay_for_level(Atomic)
  |> should.equal(Fast)
}

pub fn c1_decay_for_organism_is_medium_test() {
  types.decay_for_level(Organism)
  |> should.equal(Medium)
}

pub fn c1_level_for_path_architecture_is_ecosystem_test() {
  types.level_for_path("docs/architecture/FRACTAL.md")
  |> should.equal(Ecosystem)
}

pub fn c1_level_for_path_journal_is_organism_test() {
  types.level_for_path("docs/journal/2026-04-21.md")
  |> should.equal(Organism)
}

pub fn c1_level_for_path_rules_is_atomic_test() {
  types.level_for_path(".claude/rules/muda.md")
  |> should.equal(Atomic)
}

pub fn c1_level_for_path_plans_is_molecular_test() {
  types.level_for_path("docs/plans/plan-x.md")
  |> should.equal(Molecular)
}

pub fn c1_rhetorical_for_path_rules_is_axiom_test() {
  types.rhetorical_for_path(".claude/rules/something.md")
  |> should.equal(Axiom)
}

pub fn c1_rhetorical_for_path_journal_is_evidence_test() {
  types.rhetorical_for_path("docs/journal/session.md")
  |> should.equal(Evidence)
}

pub fn c1_rhetorical_for_path_specs_is_hypothesis_test() {
  types.rhetorical_for_path("specs/allium/ignition.allium")
  |> should.equal(Hypothesis)
}

pub fn c1_self_knowledge_architecture_is_identity_test() {
  types.self_knowledge_for_path("docs/architecture/SYSTEM.md")
  |> should.equal(types.Identity)
}

pub fn c1_self_knowledge_journal_is_history_test() {
  types.self_knowledge_for_path("docs/journal/2026-04-21.md")
  |> should.equal(types.History)
}

pub fn c1_self_knowledge_rules_is_constraints_test() {
  types.self_knowledge_for_path(".claude/rules/build.md")
  |> should.equal(types.Constraints)
}

// =============================================================================
// C2 — Search (5 tests)
// =============================================================================

pub fn c2_query_constructor_creates_valid_search_query_test() {
  let q = search.query("zenoh mesh topology")
  q.text
  |> should.equal("zenoh mesh topology")
  q.limit
  |> should.equal(5)
  q.level_filter
  |> should.equal(None)
}

pub fn c2_with_limit_sets_limit_test() {
  let q = search.query("ooda") |> search.with_limit(10)
  q.limit
  |> should.equal(10)
}

pub fn c2_with_level_sets_level_filter_test() {
  let q = search.query("allium") |> search.with_level(Ecosystem)
  q.level_filter
  |> should.equal(Some(Ecosystem))
}

pub fn c2_search_in_memory_finds_matching_holons_test() {
  let h1 = make_holon("h1", "Zenoh Mesh", "zenoh pub/sub topology for c3i mesh")
  let h2 = make_holon("h2", "Podman", "container lifecycle management")
  let holons = [h1, h2]
  let q = search.query("zenoh")
  let results = search.search_in_memory(holons, q)
  list.length(results)
  |> should.equal(1)
  let first = results |> list.first |> should.be_ok
  first.holon.uuid
  |> should.equal("h1")
}

pub fn c2_search_in_memory_respects_level_filter_test() {
  let atom =
    Holon(..make_holon("h-atom", "Atomic holon", "zenoh stuff"), level: Atomic)
  let eco =
    Holon(
      ..make_holon("h-eco", "Ecosystem holon", "zenoh architecture"),
      level: Ecosystem,
    )
  let holons = [atom, eco]
  let q = search.query("zenoh") |> search.with_level(Ecosystem)
  let results = search.search_in_memory(holons, q)
  // Only the ecosystem-level one should match the level filter
  list.length(results)
  |> should.equal(1)
  let first = results |> list.first |> should.be_ok
  first.holon.uuid
  |> should.equal("h-eco")
}

pub fn c2_search_in_memory_excludes_stale_holons_test() {
  let fresh = make_holon("fresh", "Fresh knowledge", "zenoh otel spans")
  let stale =
    Holon(
      ..make_holon("stale", "Stale knowledge", "zenoh spans"),
      entropy: 0.95,
    )
  let holons = [fresh, stale]
  let q = search.query("zenoh") |> search.with_max_entropy(0.9)
  let results = search.search_in_memory(holons, q)
  list.any(results, fn(r) { r.holon.uuid == "stale" })
  |> should.be_false()
}

pub fn c2_to_rag_context_formats_correctly_test() {
  let h = make_holon("h1", "OODA Loop", "observe orient decide act")
  let sr =
    search.SearchResult(holon: h, relevance: 0.9, snippet: "observe orient…")
  let ctx = search.to_rag_context("ooda", [sr])
  ctx.query
  |> should.equal("ooda")
  list.length(ctx.results)
  |> should.equal(1)
  // total_chars should be > 0 (snippet is non-empty)
  { ctx.total_chars > 0 }
  |> should.be_true()
}

pub fn c2_rag_context_to_string_empty_when_no_results_test() {
  let ctx = search.to_rag_context("no matches", [])
  search.rag_context_to_string(ctx)
  |> should.equal("")
}

pub fn c2_rag_context_to_string_contains_query_and_title_test() {
  let h = make_holon("h1", "Guardian Protocol", "guardian approval required")
  let sr =
    search.SearchResult(
      holon: h,
      relevance: 0.95,
      snippet: "guardian approval required…",
    )
  let ctx = search.to_rag_context("guardian", [sr])
  let text = search.rag_context_to_string(ctx)
  string.contains(text, "guardian")
  |> should.be_true()
  string.contains(text, "Guardian Protocol")
  |> should.be_true()
}

// =============================================================================
// C3 — Operations (5 tests)
// =============================================================================

pub fn c3_cortex_rag_context_returns_empty_for_no_match_test() {
  let holons = [make_holon("h1", "Podman", "container runtime lifecycle")]
  let result = operations.cortex_rag_context("zenoh mesh unknown topic", holons)
  // When nothing matches, returns empty string (per rag_context_to_string)
  result
  |> should.equal("")
}

pub fn c3_cortex_rag_context_returns_context_when_match_test() {
  let h =
    make_holon("h1", "OODA Cycle", "the ooda loop drives all agent decisions")
  let result = operations.cortex_rag_context("ooda decisions", [h])
  // Non-empty when match found
  { string.length(result) > 0 }
  |> should.be_true()
}

pub fn c3_ooda_find_precedent_filters_to_organism_level_test() {
  let atom_h =
    Holon(
      ..make_holon("a1", "Atomic decision", "restart container decision"),
      level: Atomic,
    )
  let org_h =
    Holon(
      ..make_holon(
        "o1",
        "Session journal",
        "restart container decision recorded",
      ),
      level: Organism,
    )
  let holons = [atom_h, org_h]
  let results = operations.ooda_find_precedent("restart container", holons)
  // Only organism-level holons
  list.all(results, fn(r) { r.holon.level == Organism })
  |> should.be_true()
}

pub fn c3_grounded_system_prompt_injects_context_test() {
  let h =
    make_holon("h1", "SIL-6 Architecture", "sil-6 biomorphic mesh overview")
  let base = "You are a C3I agent."
  let result = operations.grounded_system_prompt(base, "sil-6 biomorphic", [h])
  string.contains(result, base)
  |> should.be_true()
  // Context should be appended when a match exists
  { string.length(result) > string.length(base) }
  |> should.be_true()
}

pub fn c3_grounded_system_prompt_returns_base_when_no_match_test() {
  let holons = [make_holon("h1", "Podman containers", "container lifecycle")]
  let base = "You are a C3I agent."
  let result =
    operations.grounded_system_prompt(base, "quantum entanglement", holons)
  result
  |> should.equal(base)
}

pub fn c3_capture_interaction_creates_valid_holon_test() {
  let h =
    operations.capture_interaction(
      "chat-42",
      "intent-001",
      "What is the OODA loop?",
      "The OODA loop is observe, orient, decide, act.",
      "2026-04-21T00:00:00Z",
    )
  // Level must be Atomic (interaction = immediate fact)
  h.level
  |> should.equal(Atomic)
  // Rhetorical must be Anecdote (chat input)
  h.rhetorical
  |> should.equal(Anecdote)
  // Decay must be Fast
  h.decay_rate
  |> should.equal(Fast)
  // UUID starts with "int-"
  string.starts_with(h.uuid, "int-")
  |> should.be_true()
  // Content contains both Q and A
  string.contains(h.content, "What is the OODA loop?")
  |> should.be_true()
}

pub fn c3_capture_pipeline_trace_creates_valid_holon_test() {
  let h =
    operations.zettel_from_trace(
      "intent-abc123",
      "complex",
      "gemini-3-flash",
      987,
      "2026-04-21T00:00:00Z",
    )
  h.level
  |> should.equal(Atomic)
  h.rhetorical
  |> should.equal(Evidence)
  h.decay_rate
  |> should.equal(Fast)
  string.starts_with(h.uuid, "trace-")
  |> should.be_true()
  string.contains(h.content, "intent-abc123")
  |> should.be_true()
  string.contains(h.content, "987")
  |> should.be_true()
}

// =============================================================================
// C4 — Ingestion (4 tests)
// =============================================================================

pub fn c4_compute_content_hash_is_deterministic_test() {
  let content = "# My Document\n\nThis is a test of the ingestion pipeline."
  let hash1 = ingestion.compute_content_hash(content)
  let hash2 = ingestion.compute_content_hash(content)
  hash1
  |> should.equal(hash2)
}

pub fn c4_compute_content_hash_differs_for_different_content_test() {
  let hash1 = ingestion.compute_content_hash("content A")
  let hash2 = ingestion.compute_content_hash("content B")
  { hash1 == hash2 }
  |> should.be_false()
}

pub fn c4_parse_document_small_file_becomes_single_holon_test() {
  let content = "# Small File\n\nJust a short note."
  let holons =
    ingestion.parse_document(
      "docs/journal/small.md",
      content,
      "test-uuid",
      "2026-04-21T00:00:00Z",
    )
  // < 100 lines → single holon
  list.length(holons)
  |> should.equal(1)
}

pub fn c4_parse_document_assigns_correct_level_from_path_test() {
  let content = "# Architecture Doc\n\nSystem overview."
  let holons =
    ingestion.parse_document(
      "docs/architecture/SYSTEM.md",
      content,
      "arch-001",
      "2026-04-21T00:00:00Z",
    )
  let h = holons |> list.first |> should.be_ok
  h.level
  |> should.equal(Ecosystem)
}

pub fn c4_parse_document_assigns_axiom_rhetorical_for_rules_path_test() {
  let content = "# Rule File\n\nSome constraint content."
  let holons =
    ingestion.parse_document(
      ".claude/rules/my-rule.md",
      content,
      "rule-001",
      "2026-04-21T00:00:00Z",
    )
  let h = holons |> list.first |> should.be_ok
  h.rhetorical
  |> should.equal(Axiom)
}

pub fn c4_parse_document_entropy_starts_at_zero_test() {
  let content = "# Fresh Document\n\nBrand new content."
  let holons =
    ingestion.parse_document(
      "docs/plans/plan.md",
      content,
      "plan-001",
      "2026-04-21T00:00:00Z",
    )
  let h = holons |> list.first |> should.be_ok
  h.entropy
  |> should.equal(0.0)
}

pub fn c4_extract_title_reads_h1_header_test() {
  let title =
    ingestion.extract_title("# My Great Title\n\nContent.", "fallback.md")
  title
  |> should.equal("My Great Title")
}

pub fn c4_extract_title_uses_fallback_when_no_header_test() {
  let title = ingestion.extract_title("just some raw text", "fallback-path.md")
  // No header → uses first 80 chars of first line
  { string.length(title) > 0 }
  |> should.be_true()
}

// =============================================================================
// C5 — Entropy (3 tests)
// =============================================================================

pub fn c5_fresh_holon_has_zero_entropy_test() {
  let h = make_holon("h1", "Fresh", "brand new content")
  entropy.is_fresh(h)
  |> should.be_true()
}

pub fn c5_entropy_increases_after_days_test() {
  let initial = 0.0
  let after_10_days = entropy.entropy_after_days(initial, Medium, 10)
  // Medium rate = 0.01/day → after 10 days = 0.10
  { after_10_days >. initial }
  |> should.be_true()
  { after_10_days >=. 0.09 && after_10_days <=. 0.11 }
  |> should.be_true()
}

pub fn c5_fast_decay_is_faster_than_slow_test() {
  let fast_increment = entropy.daily_entropy_increment(Fast)
  let slow_increment = entropy.daily_entropy_increment(Slow)
  { fast_increment >. slow_increment }
  |> should.be_true()
}

pub fn c5_medium_decay_is_between_fast_and_slow_test() {
  let fast = entropy.daily_entropy_increment(Fast)
  let medium = entropy.daily_entropy_increment(Medium)
  let slow = entropy.daily_entropy_increment(Slow)
  { medium <. fast && medium >. slow }
  |> should.be_true()
}

pub fn c5_entropy_clamped_at_one_test() {
  let result = entropy.entropy_after_days(0.95, Fast, 100)
  result
  |> should.equal(1.0)
}

pub fn c5_entropy_label_fresh_test() {
  entropy.entropy_label(0.1)
  |> should.equal("fresh")
}

pub fn c5_entropy_label_aging_test() {
  entropy.entropy_label(0.5)
  |> should.equal("aging")
}

pub fn c5_entropy_label_rotting_test() {
  entropy.entropy_label(0.75)
  |> should.equal("rotting")
}

pub fn c5_entropy_label_excluded_test() {
  entropy.entropy_label(0.95)
  |> should.equal("excluded")
}

pub fn c5_verify_resets_entropy_to_zero_test() {
  let h = Holon(..make_holon("h1", "Aging doc", "content"), entropy: 0.65)
  let verified = entropy.verify(h, "2026-04-21T12:00:00Z")
  verified.entropy
  |> should.equal(0.0)
  verified.verified_at
  |> should.equal(Some("2026-04-21T12:00:00Z"))
}

pub fn c5_is_rotting_threshold_test() {
  let h_below = Holon(..make_holon("h1", "Test", "content"), entropy: 0.65)
  let h_above = Holon(..make_holon("h2", "Test", "content"), entropy: 0.75)
  entropy.is_rotting(h_below)
  |> should.be_false()
  entropy.is_rotting(h_above)
  |> should.be_true()
}

pub fn c5_days_until_rotting_fast_is_less_than_slow_test() {
  let h_fast =
    Holon(
      ..make_holon("h1", "Fast holon", "content"),
      decay_rate: Fast,
      entropy: 0.0,
    )
  let h_slow =
    Holon(
      ..make_holon("h2", "Slow holon", "content"),
      decay_rate: Slow,
      entropy: 0.0,
    )
  let fast_days = entropy.days_until_rotting(h_fast)
  let slow_days = entropy.days_until_rotting(h_slow)
  { fast_days < slow_days }
  |> should.be_true()
}

// =============================================================================
// C6 — Trust (3 tests)
// =============================================================================

pub fn c6_axiom_trust_is_one_test() {
  let ts = types.trust_for(Axiom)
  ts.value
  |> should.equal(1.0)
}

pub fn c6_authority_rank_order_test() {
  // Axiom > Evidence > Hypothesis > Anecdote
  let axiom_rank = trust.authority_rank(Axiom)
  let evidence_rank = trust.authority_rank(Evidence)
  let hypothesis_rank = trust.authority_rank(Hypothesis)
  let anecdote_rank = trust.authority_rank(Anecdote)
  { axiom_rank > evidence_rank }
  |> should.be_true()
  { evidence_rank > hypothesis_rank }
  |> should.be_true()
  { hypothesis_rank > anecdote_rank }
  |> should.be_true()
}

pub fn c6_trust_scores_in_valid_range_test() {
  let functions = [Axiom, Evidence, Hypothesis, Anecdote]
  let all_valid =
    list.all(functions, fn(f) {
      let ts = types.trust_for(f)
      ts.value >=. 0.0 && ts.value <=. 1.0
    })
  all_valid
  |> should.be_true()
}

pub fn c6_effective_trust_decreases_with_entropy_test() {
  let h_fresh = make_holon_with_rhetorical("h1", Axiom)
  let h_stale = Holon(..h_fresh, uuid: "h2", entropy: 0.5)
  let trust_fresh = trust.effective_trust(h_fresh)
  let trust_stale = trust.effective_trust(h_stale)
  { trust_fresh >. trust_stale }
  |> should.be_true()
}

pub fn c6_filter_trusted_removes_low_trust_holons_test() {
  let high_t = make_holon_with_rhetorical("h1", Axiom)
  let low_t = make_holon_with_rhetorical("h2", Anecdote)
  let holons = [high_t, low_t]
  let trusted = trust.filter_trusted(holons, 0.5)
  // Anecdote at 0.0 entropy = 0.3 effective trust < 0.5 threshold
  list.any(trusted, fn(h) { h.uuid == "h2" })
  |> should.be_false()
  // Axiom at 0.0 entropy = 1.0 effective trust >= 0.5 threshold
  list.any(trusted, fn(h) { h.uuid == "h1" })
  |> should.be_true()
}

pub fn c6_rag_eligible_excludes_very_stale_holons_test() {
  let fresh = make_holon_with_rhetorical("h1", Axiom)
  let excluded = Holon(..fresh, uuid: "h2", entropy: 0.95)
  trust.is_rag_eligible(fresh)
  |> should.be_true()
  trust.is_rag_eligible(excluded)
  |> should.be_false()
}

pub fn c6_aggregate_trust_empty_list_returns_zero_test() {
  trust.aggregate_trust([])
  |> should.equal(0.0)
}

pub fn c6_rank_by_trust_orders_axiom_first_test() {
  let anecdote_h = make_holon_with_rhetorical("h1", Anecdote)
  let axiom_h = make_holon_with_rhetorical("h2", Axiom)
  let evidence_h = make_holon_with_rhetorical("h3", Evidence)
  let ranked = trust.rank_by_trust([anecdote_h, evidence_h, axiom_h])
  let first = ranked |> list.first |> should.be_ok
  first.uuid
  |> should.equal("h2")
}

// =============================================================================
// C7 — Linker + Metrics (3 tests)
// =============================================================================

pub fn c7_extract_stamp_refs_finds_sc_patterns_test() {
  let content = "This implements SC-WIRE-001 and SC-GLM-UI-002 constraints."
  let refs = linker.extract_stamp_refs(content)
  list.any(refs, fn(r) { string.contains(r, "SC-WIRE-001") })
  |> should.be_true()
  list.any(refs, fn(r) { string.contains(r, "SC-GLM-UI-002") })
  |> should.be_true()
}

pub fn c7_extract_stamp_refs_ignores_non_sc_words_test() {
  let content = "This is a regular sentence without any STAMP references."
  let refs = linker.extract_stamp_refs(content)
  list.length(refs)
  |> should.equal(0)
}

pub fn c7_extract_stamp_refs_deduplicates_test() {
  let content = "SC-IKE-001 is mentioned twice. SC-IKE-001 again."
  let refs = linker.extract_stamp_refs(content)
  list.length(refs)
  |> should.equal(1)
}

pub fn c7_find_orphans_identifies_disconnected_holons_test() {
  let ids = ["h1", "h2", "h3"]
  let edges = [
    HolonEdge(source_id: "h1", target_id: "h2", link_type: Wiki, weight: 1.0),
  ]
  let orphans = linker.find_orphans(ids, edges)
  // h3 has no edges
  list.any(orphans, fn(id) { id == "h3" })
  |> should.be_true()
  // h1 and h2 are connected
  list.any(orphans, fn(id) { id == "h1" })
  |> should.be_false()
  list.any(orphans, fn(id) { id == "h2" })
  |> should.be_false()
}

pub fn c7_graph_density_zero_for_single_node_test() {
  linker.graph_density(1, 0)
  |> should.equal(0.0)
}

pub fn c7_graph_density_complete_graph_test() {
  // Complete graph: 4 nodes, 12 edges (directed)
  let density = linker.graph_density(4, 12)
  { density >=. 0.99 && density <=. 1.01 }
  |> should.be_true()
}

pub fn c7_metrics_compute_counts_correctly_test() {
  let h1 = make_holon_with_entropy("h1", 0.1)
  // fresh
  let h2 = make_holon_with_entropy("h2", 0.5)
  // aging
  let h3 = make_holon_with_entropy("h3", 0.75)
  // rotting
  let holons = [h1, h2, h3]
  let edges = []
  let m = metrics.compute(holons, edges)
  m.total_holons
  |> should.equal(3)
  m.fresh_count
  |> should.equal(1)
  m.aging_count
  |> should.equal(1)
  m.rotting_count
  |> should.equal(1)
  m.orphan_count
  |> should.equal(3)
}

pub fn c7_metrics_health_grade_thriving_when_fresh_and_dense_test() {
  // Build 5 fresh, high-trust holons with edges between them
  let holons =
    list.map(["a", "b", "c", "d", "e"], fn(id) {
      make_holon_with_rhetorical(id, Axiom)
    })
  // Connect all with edges to avoid orphan penalty
  let edges = [
    HolonEdge(source_id: "a", target_id: "b", link_type: Wiki, weight: 1.0),
    HolonEdge(source_id: "b", target_id: "c", link_type: Wiki, weight: 1.0),
    HolonEdge(source_id: "c", target_id: "d", link_type: Wiki, weight: 1.0),
    HolonEdge(source_id: "d", target_id: "e", link_type: Wiki, weight: 1.0),
    HolonEdge(source_id: "e", target_id: "a", link_type: Wiki, weight: 1.0),
  ]
  let m = metrics.compute(holons, edges)
  let grade = metrics.health_grade(m)
  // All fresh, avg trust close to 0.9 (Evidence), minimal orphans
  grade
  |> should.equal(metrics.Thriving)
}

pub fn c7_metrics_health_label_test() {
  metrics.health_label(metrics.Thriving)
  |> should.equal("THRIVING")
  metrics.health_label(metrics.Critical)
  |> should.equal("CRITICAL")
}

pub fn c7_level_distribution_counted_test() {
  let holons = [
    Holon(..make_holon("e1", "Eco", "content"), level: Ecosystem),
    Holon(..make_holon("m1", "Mol", "content"), level: Molecular),
    Holon(..make_holon("m2", "Mol2", "content"), level: Molecular),
    Holon(..make_holon("o1", "Org", "content"), level: Organism),
    Holon(..make_holon("a1", "Atom", "content"), level: Atomic),
    Holon(..make_holon("a2", "Atom2", "content"), level: Atomic),
    Holon(..make_holon("a3", "Atom3", "content"), level: Atomic),
  ]
  let m = metrics.compute(holons, [])
  m.level_distribution.ecosystem
  |> should.equal(1)
  m.level_distribution.molecular
  |> should.equal(2)
  m.level_distribution.organism
  |> should.equal(1)
  m.level_distribution.atomic
  |> should.equal(3)
}

// =============================================================================
// C8 — Rules + Export (2 tests)
// =============================================================================

pub fn c8_orphan_surge_detected_when_over_20_percent_test() {
  // Build 11 holons all with no edges → 100% orphan rate (>20%)
  let holons =
    list.map(["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k"], fn(id) {
      make_holon(id, "Holon " <> id, "content " <> id)
    })
  let edges = []
  let alerts = rules.evaluate_knowledge(holons, edges)
  let has_orphan_surge =
    list.any(alerts, fn(a) {
      case a.0 {
        rules.OrphanSurge(_, _) -> True
        _ -> False
      }
    })
  has_orphan_surge
  |> should.be_true()
}

pub fn c8_stale_architecture_detected_test() {
  let rotting_arch =
    Holon(
      ..make_holon("arch1", "Architecture Document", "system design overview"),
      level: Ecosystem,
      entropy: 0.75,
    )
  let holons = [rotting_arch]
  let edges = []
  let alerts = rules.evaluate_knowledge(holons, edges)
  let has_stale_arch =
    list.any(alerts, fn(a) {
      case a.0 {
        rules.StaleArchitecture(_, _, _) -> True
        _ -> False
      }
    })
  has_stale_arch
  |> should.be_true()
}

pub fn c8_count_by_severity_works_correctly_test() {
  let h_rotting =
    Holon(
      ..make_holon("arch1", "Ecosystem Doc", "architecture overview"),
      level: Ecosystem,
      entropy: 0.75,
    )
  let alerts = rules.evaluate_knowledge([h_rotting], [])
  let #(crit, high, med, low) = rules.count_by_severity(alerts)
  // StaleArchitecture is High severity — high should be >= 1
  { high >= 1 }
  |> should.be_true()
  // non-negative counts
  { crit >= 0 && med >= 0 && low >= 0 }
  |> should.be_true()
}

pub fn c8_rot_count_exceeded_triggers_at_threshold_test() {
  // Build 12 holons: 5 rotting (5/12 ≈ 41.7% > 30% threshold)
  let holons =
    list.map(
      ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"],
      fn(id) {
        let entropy_val = case id {
          "a" | "b" | "c" | "d" | "e" -> 0.75
          _ -> 0.1
        }
        Holon(
          ..make_holon(id, "H " <> id, "content " <> id),
          entropy: entropy_val,
        )
      },
    )
  let alerts = rules.evaluate_knowledge(holons, [])
  let has_rot_exceeded =
    list.any(alerts, fn(a) {
      case a.0 {
        rules.RotCountExceeded(_, _, _) -> True
        _ -> False
      }
    })
  has_rot_exceeded
  |> should.be_true()
}

pub fn c8_export_holon_to_obsidian_contains_frontmatter_test() {
  let h = make_holon("h1", "Test Holon", "# Test Holon\n\nContent here.")
  let md = export.holon_to_obsidian(h, [])
  string.starts_with(md, "---")
  |> should.be_true()
  string.contains(md, "uuid: h1")
  |> should.be_true()
  string.contains(md, "level: atomic")
  |> should.be_true()
}

pub fn c8_vault_filename_sanitises_slashes_test() {
  let h = make_holon("h1", "docs/architecture/SYSTEM", "content")
  let filename = export.vault_filename(h)
  string.contains(filename, "/")
  |> should.be_false()
  string.ends_with(filename, ".md")
  |> should.be_true()
}

pub fn c8_generate_index_contains_section_headers_test() {
  let eco =
    Holon(
      ..make_holon("e1", "Architecture Overview", "architecture content"),
      level: Ecosystem,
    )
  let org =
    Holon(
      ..make_holon("o1", "Session Journal", "session content"),
      level: Organism,
    )
  let index = export.generate_index([eco, org])
  string.contains(index, "Architecture (Ecosystem)")
  |> should.be_true()
  string.contains(index, "Sessions (Organism)")
  |> should.be_true()
}

pub fn c8_severity_label_test() {
  rules.severity_label(rules.Critical)
  |> should.equal("CRITICAL")
  rules.severity_label(rules.High)
  |> should.equal("HIGH")
  rules.severity_label(rules.Medium)
  |> should.equal("MEDIUM")
  rules.severity_label(rules.Low)
  |> should.equal("LOW")
}
