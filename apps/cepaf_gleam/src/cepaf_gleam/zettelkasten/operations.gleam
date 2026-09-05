//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/zettelkasten/operations</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-IKE-001, SC-SMRITI-131, SC-COG-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Operational use cases for the Zettelkasten — 25 processes from the metacognition vision.
//// Each function represents one operational enablement use case.
//// STAMP: SC-IKE-001, SC-SMRITI-131, SC-COG-001

import cepaf_gleam/zettelkasten/ingestion
import cepaf_gleam/zettelkasten/linker
import cepaf_gleam/zettelkasten/metrics
import cepaf_gleam/zettelkasten/rules
import cepaf_gleam/zettelkasten/search
import cepaf_gleam/zettelkasten/trust
import cepaf_gleam/zettelkasten/types.{
  type Holon, type HolonEdge, Anecdote, Atomic, Axiom, CacheLearningSource,
  Ecosystem, Evidence, Fast, GitCommitSource, Holon, Hypothesis,
  InteractionSource, Medium, Molecular, OodaDecisionSource, Organism,
  PipelineTraceSource, SessionSummarySource,
}
import gleam/list
import gleam/option.{None, Some}
import gleam/string

// =============================================================================
// UC01: Cortex RAG — query before LLM inference
// =============================================================================

/// Build RAG context for an operator query by searching the Zettelkasten.
pub fn cortex_rag_context(query: String, holons: List(Holon)) -> String {
  let results =
    search.search_in_memory(holons, search.query(query) |> search.with_limit(3))
  let ctx = search.to_rag_context(query, results)
  search.rag_context_to_string(ctx)
}

// =============================================================================
// UC02: OODA Precedent — search past decisions
// =============================================================================

/// Find past OODA decisions relevant to current facts.
pub fn ooda_find_precedent(
  current_facts: String,
  holons: List(Holon),
) -> List(search.SearchResult) {
  let q =
    search.query(current_facts)
    |> search.with_level(Organism)
    |> search.with_limit(3)
  search.search_in_memory(holons, q)
}

// =============================================================================
// UC04: Inference Grounding — inject zettel context into system prompt
// =============================================================================

/// Build a grounded system prompt by injecting Zettelkasten context.
pub fn grounded_system_prompt(
  base_prompt: String,
  query: String,
  holons: List(Holon),
) -> String {
  let context = cortex_rag_context(query, holons)
  case context {
    "" -> base_prompt
    ctx -> base_prompt <> "\n\n" <> ctx
  }
}

// =============================================================================
// UC05: Knowledge Loop Close — capture interaction as new zettel
// =============================================================================

/// Create a zettel from an operator interaction (question + answer).
pub fn capture_interaction(
  chat_id: String,
  intent_id: String,
  question: String,
  answer: String,
  timestamp: String,
) -> Holon {
  let content = "Q: " <> question <> "\nA: " <> answer
  let uuid = "int-" <> ingestion.compute_content_hash(content)
  Holon(
    uuid: uuid,
    title: "Interaction: " <> string.slice(question, 0, 60),
    content: content,
    tags: ["interaction", "chat-" <> chat_id],
    level: Atomic,
    rhetorical: Anecdote,
    entropy: 0.0,
    decay_rate: Fast,
    source: InteractionSource(chat_id: chat_id, intent_id: intent_id),
    content_hash: ingestion.compute_content_hash(content),
    cluster: Some("interactions"),
    stamp_refs: linker.extract_stamp_refs(content),
    created_at: timestamp,
    updated_at: timestamp,
    verified_at: None,
  )
}

// =============================================================================
// UC06: Gateway Personalization — operator behavior profile
// =============================================================================

/// Build an operator interest profile from their interaction zettels.
pub fn operator_profile(chat_id: String, holons: List(Holon)) -> List(String) {
  holons
  |> list.filter(fn(h) { list.any(h.tags, fn(t) { t == "chat-" <> chat_id }) })
  |> list.flat_map(fn(h) { h.tags })
  |> list.filter(fn(t) { !string.starts_with(t, "chat-") && t != "interaction" })
  |> count_unique
  |> list.sort(fn(a, b) {
    case a.1 > b.1 {
      True -> order.Lt
      False ->
        case a.1 < b.1 {
          True -> order.Gt
          False -> order.Eq
        }
    }
  })
  |> list.map(fn(pair) { pair.0 })
  |> list.take(5)
}

import gleam/order

// =============================================================================
// UC07: Drift Detection — code vs spec freshness
// =============================================================================

/// Detect drift between code zettels and spec zettels.
/// Returns pairs where code is newer than spec by more than threshold days.
pub fn detect_drift(
  holons: List(Holon),
  edges: List(HolonEdge),
) -> List(#(String, String)) {
  // Find code→spec edges
  edges
  |> list.filter(fn(e) { e.link_type == types.Code })
  |> list.filter_map(fn(e) {
    let source = list.find(holons, fn(h) { h.uuid == e.source_id })
    let target = list.find(holons, fn(h) { h.uuid == e.target_id })
    case source, target {
      Ok(code_h), Ok(spec_h) ->
        case spec_h.rhetorical == Axiom || spec_h.rhetorical == Hypothesis {
          True ->
            case spec_h.entropy >. 0.5 && code_h.entropy <. 0.3 {
              True -> Ok(#(code_h.title, spec_h.title))
              False -> Error(Nil)
            }
          False -> Error(Nil)
        }
      _, _ -> Error(Nil)
    }
  })
}

// =============================================================================
// UC08: Teaching/Onboarding — hierarchy-based surfacing
// =============================================================================

/// Surface knowledge for a new operator, starting from ecosystem level.
pub fn onboarding_sequence(holons: List(Holon)) -> List(Holon) {
  let ecosystem =
    list.filter(holons, fn(h) { h.level == Ecosystem && h.entropy <. 0.5 })
  let molecular =
    list.filter(holons, fn(h) {
      h.level == Molecular && h.rhetorical == Axiom && h.entropy <. 0.3
    })
  let key_constraints =
    list.filter(holons, fn(h) {
      h.level == Atomic && h.rhetorical == Axiom && h.entropy <. 0.2
    })
  list.flatten([
    trust.rank_by_trust(ecosystem) |> list.take(5),
    trust.rank_by_trust(molecular) |> list.take(5),
    trust.rank_by_trust(key_constraints) |> list.take(5),
  ])
}

// =============================================================================
// UC09: Compliance Check — constraint → code edge verification
// =============================================================================

/// Check which constraint zettels have no implementing code edges.
pub fn compliance_gaps(
  holons: List(Holon),
  edges: List(HolonEdge),
) -> List(String) {
  let constraint_holons =
    list.filter(holons, fn(h) { h.rhetorical == Axiom && h.stamp_refs != [] })
  constraint_holons
  |> list.filter(fn(h) {
    let inbound_code =
      list.filter(edges, fn(e) {
        e.target_id == h.uuid && e.link_type == types.Code
      })
    inbound_code == []
  })
  |> list.flat_map(fn(h) { h.stamp_refs })
}

// =============================================================================
// UC10: Evolution Chronicle — temporal reconstruction
// =============================================================================

/// Reconstruct system state at a point in time (holons created before timestamp).
pub fn state_at_time(
  holons: List(Holon),
  before_timestamp: String,
) -> List(Holon) {
  list.filter(holons, fn(h) {
    string.compare(h.created_at, before_timestamp) != order.Gt
  })
}

// =============================================================================
// UC11-15: Auto-Zettel Generation
// =============================================================================

/// UC11: Create zettel from git commit.
pub fn zettel_from_commit(
  sha: String,
  message: String,
  timestamp: String,
) -> Holon {
  let content = "Git commit " <> sha <> ": " <> message
  Holon(
    uuid: "git-" <> string.slice(sha, 0, 8),
    title: "Commit: " <> string.slice(message, 0, 60),
    content: content,
    tags: ["git", "commit"],
    level: Atomic,
    rhetorical: Evidence,
    entropy: 0.0,
    decay_rate: Medium,
    source: GitCommitSource(sha: sha),
    content_hash: ingestion.compute_content_hash(content),
    cluster: Some("git"),
    stamp_refs: linker.extract_stamp_refs(message),
    created_at: timestamp,
    updated_at: timestamp,
    verified_at: None,
  )
}

/// UC12: Create zettel from pipeline trace.
pub fn zettel_from_trace(
  intent_id: String,
  classification: String,
  model: String,
  latency_ms: Int,
  timestamp: String,
) -> Holon {
  let content =
    "Intent "
    <> intent_id
    <> ": "
    <> classification
    <> " via "
    <> model
    <> " ("
    <> int_to_string(latency_ms)
    <> "ms)"
  Holon(
    uuid: "trace-" <> string.slice(intent_id, 0, 8),
    title: "Trace: "
      <> classification
      <> " "
      <> int_to_string(latency_ms)
      <> "ms",
    content: content,
    tags: ["trace", classification],
    level: Atomic,
    rhetorical: Evidence,
    entropy: 0.0,
    decay_rate: Fast,
    source: PipelineTraceSource(intent_id: intent_id),
    content_hash: ingestion.compute_content_hash(content),
    cluster: Some("traces"),
    stamp_refs: [],
    created_at: timestamp,
    updated_at: timestamp,
    verified_at: None,
  )
}

/// UC13: Create zettel from OODA decision.
pub fn zettel_from_ooda(
  cycle_id: String,
  phase: String,
  decision: String,
  rule_fired: String,
  timestamp: String,
) -> Holon {
  let content =
    "OODA "
    <> cycle_id
    <> " "
    <> phase
    <> ": "
    <> decision
    <> " (rule: "
    <> rule_fired
    <> ")"
  Holon(
    uuid: "ooda-" <> string.slice(cycle_id, 0, 8),
    title: "OODA: " <> decision,
    content: content,
    tags: ["ooda", phase],
    level: Atomic,
    rhetorical: Evidence,
    entropy: 0.0,
    decay_rate: Fast,
    source: OodaDecisionSource(cycle_id: cycle_id),
    content_hash: ingestion.compute_content_hash(content),
    cluster: Some("ooda"),
    stamp_refs: [],
    created_at: timestamp,
    updated_at: timestamp,
    verified_at: None,
  )
}

/// UC14: Create zettel from cache write (learning event).
pub fn zettel_from_cache(
  prompt_hash: String,
  question: String,
  answer_preview: String,
  timestamp: String,
) -> Holon {
  let content = "Learned: " <> question <> " → " <> answer_preview
  Holon(
    uuid: "cache-" <> string.slice(prompt_hash, 0, 8),
    title: "Learned: " <> string.slice(question, 0, 50),
    content: content,
    tags: ["cache", "learned"],
    level: Atomic,
    rhetorical: Anecdote,
    entropy: 0.0,
    decay_rate: Fast,
    source: CacheLearningSource(prompt_hash: prompt_hash),
    content_hash: ingestion.compute_content_hash(content),
    cluster: Some("cache"),
    stamp_refs: [],
    created_at: timestamp,
    updated_at: timestamp,
    verified_at: None,
  )
}

/// UC15: Create session summary zettel.
pub fn zettel_from_session(
  session_id: String,
  topics: List(String),
  decisions: List(String),
  unfinished: List(String),
  timestamp: String,
) -> Holon {
  let content =
    "Session "
    <> session_id
    <> "\n"
    <> "Topics: "
    <> string.join(topics, ", ")
    <> "\n"
    <> "Decisions: "
    <> string.join(decisions, ", ")
    <> "\n"
    <> "Unfinished: "
    <> string.join(unfinished, ", ")
  Holon(
    uuid: "session-" <> string.slice(session_id, 0, 8),
    title: "Session: " <> string.join(list.take(topics, 2), " + "),
    content: content,
    tags: ["session", ..topics],
    level: Organism,
    rhetorical: Evidence,
    entropy: 0.0,
    decay_rate: Medium,
    source: SessionSummarySource(session_id: session_id),
    content_hash: ingestion.compute_content_hash(content),
    cluster: Some("sessions"),
    stamp_refs: linker.extract_stamp_refs(content),
    created_at: timestamp,
    updated_at: timestamp,
    verified_at: None,
  )
}

// =============================================================================
// UC18: Knowledge Gap Detection
// =============================================================================

/// Track search misses — topics asked about but not found.
pub fn detect_knowledge_gaps(
  queries: List(String),
  holons: List(Holon),
) -> List(#(String, Int)) {
  queries
  |> list.map(fn(q) {
    let results =
      search.search_in_memory(holons, search.query(q) |> search.with_limit(1))
    #(q, list.length(results))
  })
  |> list.filter(fn(pair) { pair.1 == 0 })
  |> count_queries
}

// =============================================================================
// UC22: Knowledge Health Dashboard
// =============================================================================

/// Generate a comprehensive health report.
pub fn health_report(holons: List(Holon), edges: List(HolonEdge)) -> String {
  let m = metrics.compute(holons, edges)
  let health = metrics.health_grade(m)
  let alerts = rules.evaluate_knowledge(holons, edges)
  let #(crit, high, med, _low) = rules.count_by_severity(alerts)

  "Knowledge Health: "
  <> metrics.health_label(health)
  <> "\n"
  <> "Holons: "
  <> int_to_string(m.total_holons)
  <> " (fresh:"
  <> int_to_string(m.fresh_count)
  <> " aging:"
  <> int_to_string(m.aging_count)
  <> " rotting:"
  <> int_to_string(m.rotting_count)
  <> ")\n"
  <> "Edges: "
  <> int_to_string(m.total_edges)
  <> "\n"
  <> "Orphans: "
  <> int_to_string(m.orphan_count)
  <> "\n"
  <> "Alerts: "
  <> int_to_string(crit)
  <> " critical, "
  <> int_to_string(high)
  <> " high, "
  <> int_to_string(med)
  <> " medium\n"
  <> "Levels: eco="
  <> int_to_string(m.level_distribution.ecosystem)
  <> " mol="
  <> int_to_string(m.level_distribution.molecular)
  <> " org="
  <> int_to_string(m.level_distribution.organism)
  <> " atom="
  <> int_to_string(m.level_distribution.atomic)
}

// =============================================================================
// Helpers
// =============================================================================

fn count_unique(items: List(String)) -> List(#(String, Int)) {
  list.fold(items, [], fn(acc: List(#(String, Int)), item: String) {
    case list.find(acc, fn(pair: #(String, Int)) { pair.0 == item }) {
      Ok(#(_, count)) ->
        list.map(acc, fn(pair: #(String, Int)) {
          case pair.0 == item {
            True -> #(item, count + 1)
            False -> pair
          }
        })
      Error(_) -> [#(item, 1), ..acc]
    }
  })
}

fn count_queries(items: List(#(String, Int))) -> List(#(String, Int)) {
  list.fold(items, [], fn(acc: List(#(String, Int)), item: #(String, Int)) {
    let key = item.0
    case list.find(acc, fn(pair: #(String, Int)) { pair.0 == key }) {
      Ok(#(_, count)) ->
        list.map(acc, fn(pair: #(String, Int)) {
          case pair.0 == key {
            True -> #(key, count + 1)
            False -> pair
          }
        })
      Error(_) -> [#(key, 1), ..acc]
    }
  })
}

fn int_to_string(n: Int) -> String {
  case n < 0 {
    True -> "-" <> int_to_string(-n)
    False ->
      case n < 10 {
        True ->
          case n {
            0 -> "0"
            1 -> "1"
            2 -> "2"
            3 -> "3"
            4 -> "4"
            5 -> "5"
            6 -> "6"
            7 -> "7"
            8 -> "8"
            _ -> "9"
          }
        False -> int_to_string(n / 10) <> int_to_string(n % 10)
      }
  }
}
