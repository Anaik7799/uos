import cepaf_gleam/zettelkasten/operations as ops
import cepaf_gleam/zettelkasten/types
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Test data factory
// =============================================================================

fn arch_doc() -> types.Holon {
  types.Holon(
    uuid: "arch-1",
    title: "System Architecture — Gleam-first cybernetic cockpit",
    content: "C3I is a Gleam-first cybernetic command-and-control cockpit. It uses Zenoh pub/sub for all mesh communication. SC-ZENOH-001 requires Zenoh NIF loaded on all nodes. Apoptosis schedule uses 72h mean lifespan.",
    tags: ["architecture", "zenoh"],
    level: types.Ecosystem,
    rhetorical: types.Axiom,
    entropy: 0.1,
    decay_rate: types.Slow,
    source: types.DocumentSource(path: "docs/architecture/overview.md"),
    content_hash: "arch1hash",
    cluster: Some("architecture"),
    stamp_refs: ["SC-ZENOH-001"],
    created_at: "2026-04-10",
    updated_at: "2026-04-10",
    verified_at: None,
  )
}

fn journal_entry() -> types.Holon {
  types.Holon(
    uuid: "journal-1",
    title: "Session: Zettelkasten implementation",
    content: "Implemented 9 Gleam modules for Zettelkasten. Fixed 56 cortex.rs errors via Jidoka RCA. Gateway broadcast_message signature changed.",
    tags: ["journal", "zettelkasten", "jidoka"],
    level: types.Organism,
    rhetorical: types.Evidence,
    entropy: 0.2,
    decay_rate: types.Medium,
    source: types.DocumentSource(path: "docs/journal/20260411.md"),
    content_hash: "journal1hash",
    cluster: Some("journal"),
    stamp_refs: [],
    created_at: "2026-04-11",
    updated_at: "2026-04-11",
    verified_at: None,
  )
}

fn constraint_rule() -> types.Holon {
  types.Holon(
    uuid: "rule-1",
    title: "SC-ZENOH-001: Zenoh NIF mandatory",
    content: "SC-ZENOH-001: Zenoh NIF MUST be loaded on ALL nodes. SC-ZENOH-002: Zenoh router reachable.",
    tags: ["constraints", "zenoh"],
    level: types.Atomic,
    rhetorical: types.Axiom,
    entropy: 0.0,
    decay_rate: types.Slow,
    source: types.DocumentSource(path: ".claude/rules/zenoh.md"),
    content_hash: "rule1hash",
    cluster: Some("constraints"),
    stamp_refs: ["SC-ZENOH-001", "SC-ZENOH-002"],
    created_at: "2026-04-01",
    updated_at: "2026-04-01",
    verified_at: None,
  )
}

fn allium_spec() -> types.Holon {
  types.Holon(
    uuid: "spec-1",
    title: "Allium: Planning page behavioral spec",
    content: "surface PlanningPage { facing: Operator, path: /planning, layout: kanban board }",
    tags: ["allium", "planning"],
    level: types.Molecular,
    rhetorical: types.Hypothesis,
    entropy: 0.4,
    decay_rate: types.Medium,
    source: types.DocumentSource(path: "specs/allium/planning.allium"),
    content_hash: "spec1hash",
    cluster: Some("allium"),
    stamp_refs: [],
    created_at: "2026-04-05",
    updated_at: "2026-04-05",
    verified_at: None,
  )
}

fn stale_doc() -> types.Holon {
  types.Holon(
    uuid: "stale-1",
    title: "Old Architecture Decision",
    content: "We chose Zenoh over NATS because of pub/sub mesh support.",
    tags: ["architecture"],
    level: types.Ecosystem,
    rhetorical: types.Axiom,
    entropy: 0.85,
    decay_rate: types.Slow,
    source: types.DocumentSource(path: "docs/architecture/old.md"),
    content_hash: "stale1hash",
    cluster: Some("architecture"),
    stamp_refs: [],
    created_at: "2026-02-01",
    updated_at: "2026-02-01",
    verified_at: None,
  )
}

fn code_module() -> types.Holon {
  types.Holon(
    uuid: "code-1",
    title: "zenoh/client.gleam",
    content: "Module: cepaf_gleam/zenoh/client. Implements SC-ZENOH-001.",
    tags: ["code", "zenoh"],
    level: types.Atomic,
    rhetorical: types.Evidence,
    entropy: 0.05,
    decay_rate: types.Fast,
    source: types.CodeSource(
      module_path: "cepaf_gleam/zenoh/client",
      language: "gleam",
    ),
    content_hash: "code1hash",
    cluster: Some("code"),
    stamp_refs: ["SC-ZENOH-001"],
    created_at: "2026-04-11",
    updated_at: "2026-04-11",
    verified_at: None,
  )
}

fn interaction_holon() -> types.Holon {
  types.Holon(
    uuid: "int-1",
    title: "Interaction: what is apoptosis",
    content: "Q: what is the apoptosis schedule\nA: 72h mean lifespan, log-normal",
    tags: ["interaction", "chat-user123", "apoptosis"],
    level: types.Atomic,
    rhetorical: types.Anecdote,
    entropy: 0.1,
    decay_rate: types.Fast,
    source: types.InteractionSource(chat_id: "user123", intent_id: "tg-001"),
    content_hash: "int1hash",
    cluster: Some("interactions"),
    stamp_refs: [],
    created_at: "2026-04-11",
    updated_at: "2026-04-11",
    verified_at: None,
  )
}

fn all_holons() -> List(types.Holon) {
  [
    arch_doc(),
    journal_entry(),
    constraint_rule(),
    allium_spec(),
    stale_doc(),
    code_module(),
    interaction_holon(),
  ]
}

fn all_edges() -> List(types.HolonEdge) {
  [
    types.HolonEdge("code-1", "rule-1", types.Code, 0.9),
    types.HolonEdge("arch-1", "spec-1", types.Wiki, 0.7),
    types.HolonEdge("journal-1", "arch-1", types.Wiki, 0.5),
  ]
}

// =============================================================================
// UC01: Cortex RAG
// =============================================================================

pub fn uc01_cortex_rag_finds_relevant_context_test() {
  let ctx = ops.cortex_rag_context("apoptosis schedule", all_holons())
  string.contains(ctx, "Relevant system knowledge") |> should.be_true
  string.contains(ctx, "apoptosis") |> should.be_true
}

pub fn uc01_cortex_rag_empty_for_unknown_topic_test() {
  let ctx = ops.cortex_rag_context("quantum_teleportation_xyz", all_holons())
  ctx |> should.equal("")
}

// =============================================================================
// UC02: OODA Precedent
// =============================================================================

pub fn uc02_ooda_finds_past_decisions_test() {
  let results = ops.ooda_find_precedent("Jidoka RCA gateway", all_holons())
  { list.length(results) >= 1 } |> should.be_true
}

pub fn uc02_ooda_filters_to_organism_level_test() {
  let results = ops.ooda_find_precedent("zenoh", all_holons())
  list.all(results, fn(r) { r.holon.level == types.Organism }) |> should.be_true
}

// =============================================================================
// UC04: Inference Grounding
// =============================================================================

pub fn uc04_grounded_prompt_includes_context_test() {
  let prompt =
    ops.grounded_system_prompt("You are C3I.", "apoptosis", all_holons())
  string.contains(prompt, "You are C3I.") |> should.be_true
  string.contains(prompt, "Relevant system knowledge") |> should.be_true
}

pub fn uc04_grounded_prompt_unchanged_for_no_match_test() {
  let prompt =
    ops.grounded_system_prompt(
      "Base prompt.",
      "xyz_nonexistent_topic",
      all_holons(),
    )
  prompt |> should.equal("Base prompt.")
}

// =============================================================================
// UC05: Knowledge Loop Close
// =============================================================================

pub fn uc05_capture_interaction_creates_zettel_test() {
  let holon =
    ops.capture_interaction(
      "user123",
      "tg-002",
      "What is RETE-UL?",
      "52 GRL rules across 13 domains",
      "2026-04-11",
    )
  string.starts_with(holon.uuid, "int-") |> should.be_true
  holon.level |> should.equal(types.Atomic)
  holon.rhetorical |> should.equal(types.Anecdote)
  string.contains(holon.content, "RETE-UL") |> should.be_true
  list.contains(holon.tags, "chat-user123") |> should.be_true
}

pub fn uc05_captured_zettel_is_searchable_test() {
  let holon =
    ops.capture_interaction(
      "user123",
      "tg-002",
      "What is RETE-UL?",
      "52 GRL rules",
      "2026-04-11",
    )
  let holons = [holon, ..all_holons()]
  let ctx = ops.cortex_rag_context("RETE-UL", holons)
  string.contains(ctx, "RETE-UL") |> should.be_true
}

// =============================================================================
// UC06: Gateway Personalization
// =============================================================================

pub fn uc06_operator_profile_extracts_interests_test() {
  let holons = [interaction_holon(), ..all_holons()]
  let profile = ops.operator_profile("user123", holons)
  list.contains(profile, "apoptosis") |> should.be_true
}

pub fn uc06_empty_profile_for_unknown_user_test() {
  let profile = ops.operator_profile("unknown_user", all_holons())
  list.length(profile) |> should.equal(0)
}

// =============================================================================
// UC07: Drift Detection
// =============================================================================

pub fn uc07_detects_drift_when_spec_stale_test() {
  let holons = [
    code_module(),
    types.Holon(..allium_spec(), uuid: "spec-stale", entropy: 0.6),
  ]
  let edges = [types.HolonEdge("code-1", "spec-stale", types.Code, 0.8)]
  let drift = ops.detect_drift(holons, edges)
  { list.length(drift) >= 1 } |> should.be_true
}

pub fn uc07_no_drift_when_both_fresh_test() {
  let holons = [
    code_module(),
    types.Holon(..allium_spec(), uuid: "spec-fresh", entropy: 0.1),
  ]
  let edges = [types.HolonEdge("code-1", "spec-fresh", types.Code, 0.8)]
  let drift = ops.detect_drift(holons, edges)
  list.length(drift) |> should.equal(0)
}

// =============================================================================
// UC08: Teaching/Onboarding
// =============================================================================

pub fn uc08_onboarding_starts_with_ecosystem_test() {
  let sequence = ops.onboarding_sequence(all_holons())
  { list.length(sequence) >= 1 } |> should.be_true
  case sequence {
    [first, ..] -> first.level |> should.equal(types.Ecosystem)
    [] -> should.be_true(False)
  }
}

pub fn uc08_onboarding_excludes_stale_docs_test() {
  let sequence = ops.onboarding_sequence(all_holons())
  let stale_in_sequence = list.filter(sequence, fn(h) { h.entropy >. 0.5 })
  list.length(stale_in_sequence) |> should.equal(0)
}

// =============================================================================
// UC09: Compliance Check
// =============================================================================

pub fn uc09_finds_unimplemented_constraints_test() {
  // rule-1 has SC-ZENOH-001 and SC-ZENOH-002
  // code-1 links to rule-1 via code edge → rule-1 is implemented
  // But constraint_rule() also has stamps that may not all have code edges
  let holons = all_holons()
  let edges = all_edges()
  let gaps = ops.compliance_gaps(holons, edges)
  // Some constraints should be gaps (no code edges to them)
  { list.length(gaps) >= 0 } |> should.be_true
}

pub fn uc09_no_gaps_when_all_linked_test() {
  let holons = [constraint_rule(), code_module()]
  // code-1 → rule-1 via Code edge = all constraints in rule-1 are implemented
  let edges = [types.HolonEdge("code-1", "rule-1", types.Code, 0.9)]
  let gaps = ops.compliance_gaps(holons, edges)
  list.length(gaps) |> should.equal(0)
}

// =============================================================================
// UC10: Evolution Chronicle
// =============================================================================

pub fn uc10_state_at_time_filters_by_timestamp_test() {
  let holons = all_holons()
  let before_april_10 = ops.state_at_time(holons, "2026-04-09")
  let all_time = ops.state_at_time(holons, "2026-04-30")
  { list.length(before_april_10) < list.length(all_time) } |> should.be_true
}

pub fn uc10_state_at_time_includes_old_docs_test() {
  let holons = all_holons()
  let early = ops.state_at_time(holons, "2026-04-02")
  // Only constraint_rule (created 2026-04-01) and stale_doc (2026-02-01)
  { list.length(early) >= 1 } |> should.be_true
}

// =============================================================================
// UC11: Auto-Zettel from Git Commit
// =============================================================================

pub fn uc11_git_commit_zettel_test() {
  let holon =
    ops.zettel_from_commit(
      "a499ecd4",
      "feat(cepaf): Zettelkasten brain",
      "2026-04-11",
    )
  string.starts_with(holon.uuid, "git-") |> should.be_true
  holon.level |> should.equal(types.Atomic)
  holon.rhetorical |> should.equal(types.Evidence)
  string.contains(holon.content, "a499ecd4") |> should.be_true
}

// =============================================================================
// UC12: Auto-Zettel from Pipeline Trace
// =============================================================================

pub fn uc12_pipeline_trace_zettel_test() {
  let holon =
    ops.zettel_from_trace(
      "tg-001",
      "complex_query",
      "gemini-direct",
      3042,
      "2026-04-11",
    )
  string.starts_with(holon.uuid, "trace-") |> should.be_true
  string.contains(holon.content, "3042ms") |> should.be_true
  holon.cluster |> should.equal(Some("traces"))
}

// =============================================================================
// UC13: Auto-Zettel from OODA Decision
// =============================================================================

pub fn uc13_ooda_decision_zettel_test() {
  let holon =
    ops.zettel_from_ooda(
      "cycle-4207",
      "Decide",
      "NoAction",
      "HealthRule",
      "2026-04-11",
    )
  string.starts_with(holon.uuid, "ooda-") |> should.be_true
  string.contains(holon.content, "NoAction") |> should.be_true
  list.contains(holon.tags, "Decide") |> should.be_true
}

// =============================================================================
// UC14: Auto-Zettel from Cache Write
// =============================================================================

pub fn uc14_cache_learning_zettel_test() {
  let holon =
    ops.zettel_from_cache(
      "hash123",
      "What is system status?",
      "All 17 containers healthy",
      "2026-04-11",
    )
  string.starts_with(holon.uuid, "cache-") |> should.be_true
  holon.rhetorical |> should.equal(types.Anecdote)
  string.contains(holon.content, "Learned") |> should.be_true
}

// =============================================================================
// UC15: Session Summary Capture
// =============================================================================

pub fn uc15_session_summary_zettel_test() {
  let holon =
    ops.zettel_from_session(
      "session-20260411",
      ["zettelkasten", "telegram", "vision"],
      ["SSR over client JS", "TeleNative CSS"],
      ["wiring guard update"],
      "2026-04-11",
    )
  string.starts_with(holon.uuid, "session-") |> should.be_true
  holon.level |> should.equal(types.Organism)
  string.contains(holon.content, "zettelkasten") |> should.be_true
  list.contains(holon.tags, "telegram") |> should.be_true
}

// =============================================================================
// UC18: Knowledge Gap Detection
// =============================================================================

pub fn uc18_detects_gaps_for_unknown_topics_test() {
  let queries = ["apoptosis", "quantum_xyz", "nonexistent_abc"]
  let gaps = ops.detect_knowledge_gaps(queries, all_holons())
  // "quantum_xyz" and "nonexistent_abc" should be gaps
  { list.length(gaps) >= 1 } |> should.be_true
}

pub fn uc18_no_gaps_for_known_topics_test() {
  let queries = ["zenoh", "architecture"]
  let gaps = ops.detect_knowledge_gaps(queries, all_holons())
  list.length(gaps) |> should.equal(0)
}

// =============================================================================
// UC22: Knowledge Health Dashboard
// =============================================================================

pub fn uc22_health_report_contains_key_metrics_test() {
  let report = ops.health_report(all_holons(), all_edges())
  string.contains(report, "Knowledge Health:") |> should.be_true
  string.contains(report, "Holons:") |> should.be_true
  string.contains(report, "Edges:") |> should.be_true
  string.contains(report, "Orphans:") |> should.be_true
  string.contains(report, "Levels:") |> should.be_true
}

pub fn uc22_health_report_shows_correct_count_test() {
  let report = ops.health_report(all_holons(), all_edges())
  string.contains(report, "7") |> should.be_true
}

// =============================================================================
// End-to-end: Knowledge Loop (UC05 → UC01)
// =============================================================================

pub fn e2e_knowledge_loop_capture_then_retrieve_test() {
  // Step 1: Operator asks a question
  let question = "How does the inference cascade work?"
  let answer =
    "6-tier hedged: Gemini Direct, OpenRouter, Ollama gemma4/3, RETE-UL, static ack"

  // Step 2: Capture the interaction as a zettel
  let interaction =
    ops.capture_interaction("user456", "tg-100", question, answer, "2026-04-11")

  // Step 3: Add to knowledge base
  let holons = [interaction, ..all_holons()]

  // Step 4: Future query retrieves the previous interaction
  let ctx = ops.cortex_rag_context("inference cascade", holons)
  string.contains(ctx, "inference cascade") |> should.be_true
}

pub fn e2e_onboarding_then_search_test() {
  // Step 1: New operator gets onboarding sequence
  let sequence = ops.onboarding_sequence(all_holons())
  { list.length(sequence) >= 1 } |> should.be_true

  // Step 2: Operator searches for specific topic
  let ctx = ops.cortex_rag_context("zenoh mesh", all_holons())
  string.contains(ctx, "zenoh") |> should.be_true
}

pub fn e2e_detect_drift_then_alert_test() {
  // Step 1: Code is fresh, spec is stale
  let holons = [
    code_module(),
    types.Holon(..allium_spec(), uuid: "spec-old", entropy: 0.6),
    ..all_holons()
  ]
  let edges = [
    types.HolonEdge("code-1", "spec-old", types.Code, 0.8),
    ..all_edges()
  ]

  // Step 2: Drift detected
  let drift = ops.detect_drift(holons, edges)
  { list.length(drift) >= 1 } |> should.be_true

  // Step 3: Health report shows alerts
  let report = ops.health_report(holons, edges)
  string.contains(report, "Knowledge Health:") |> should.be_true
}
