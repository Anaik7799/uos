// Zettelkasten Comprehensive Test Suite
// Tests for the L5_COGNITIVE knowledge graph modules: types, entropy, trust, search, linker.
// SC-SMRITI-131, SC-IKE-001..003, SC-SMRITI-130, SC-SMRITI-140
// Coverage: HolonLevel, DecayRate, RhetoricalFunction, entropy decay, trust scoring,
//           search query builder, in-memory search, linker STAMP extraction.

import cepaf_gleam/zettelkasten/entropy
import cepaf_gleam/zettelkasten/linker
import cepaf_gleam/zettelkasten/search
import cepaf_gleam/zettelkasten/trust
import cepaf_gleam/zettelkasten/types
import gleam/list
import gleam/option
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// =============================================================================
// Helpers — build test Holons
// =============================================================================

fn make_holon(
  uuid: String,
  title: String,
  content: String,
  level: types.HolonLevel,
  rhetorical: types.RhetoricalFunction,
  entropy_val: Float,
  decay: types.DecayRate,
) -> types.Holon {
  types.Holon(
    uuid: uuid,
    title: title,
    content: content,
    tags: ["test"],
    level: level,
    rhetorical: rhetorical,
    entropy: entropy_val,
    decay_rate: decay,
    source: types.ManualSource(author: "test"),
    content_hash: "sha256:abc123",
    cluster: option.None,
    stamp_refs: [],
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-01T00:00:00Z",
    verified_at: option.None,
  )
}

fn fresh_axiom() -> types.Holon {
  make_holon(
    "h-1",
    "Architectural Decision",
    "The system MUST use Zenoh. SC-ZMOF-001 mandates it.",
    types.Ecosystem,
    types.Axiom,
    0.1,
    types.Slow,
  )
}

fn stale_anecdote() -> types.Holon {
  make_holon(
    "h-2",
    "Chat conversation",
    "User said the system is fast",
    types.Atomic,
    types.Anecdote,
    0.85,
    types.Fast,
  )
}

// =============================================================================
// C1: types — HolonLevel and level_to_string
// =============================================================================

pub fn level_to_string_atomic_test() {
  types.level_to_string(types.Atomic)
  |> should.equal("atomic")
}

pub fn level_to_string_molecular_test() {
  types.level_to_string(types.Molecular)
  |> should.equal("molecular")
}

pub fn level_to_string_organism_test() {
  types.level_to_string(types.Organism)
  |> should.equal("organism")
}

pub fn level_to_string_ecosystem_test() {
  types.level_to_string(types.Ecosystem)
  |> should.equal("ecosystem")
}

// =============================================================================
// C2: types — DecayRate and decay_to_string
// =============================================================================

pub fn decay_to_string_slow_test() {
  types.decay_to_string(types.Slow)
  |> should.equal("slow")
}

pub fn decay_to_string_medium_test() {
  types.decay_to_string(types.Medium)
  |> should.equal("medium")
}

pub fn decay_to_string_fast_test() {
  types.decay_to_string(types.Fast)
  |> should.equal("fast")
}

// =============================================================================
// C3: types — trust_for (RhetoricalFunction → base trust)
// =============================================================================

pub fn trust_for_axiom_is_one_test() {
  types.trust_for(types.Axiom).value
  |> should.equal(1.0)
}

pub fn trust_for_evidence_is_point_nine_test() {
  types.trust_for(types.Evidence).value
  |> should.equal(0.9)
}

pub fn trust_for_hypothesis_is_point_five_test() {
  types.trust_for(types.Hypothesis).value
  |> should.equal(0.5)
}

pub fn trust_for_anecdote_is_point_three_test() {
  types.trust_for(types.Anecdote).value
  |> should.equal(0.3)
}

// =============================================================================
// C4: types — level_for_path and rhetorical_for_path
// =============================================================================

pub fn level_for_path_architecture_is_ecosystem_test() {
  types.level_for_path("docs/architecture/SYSTEM.md")
  |> should.equal(types.Ecosystem)
}

pub fn level_for_path_journal_is_organism_test() {
  types.level_for_path("docs/journal/2026-01-01-session.md")
  |> should.equal(types.Organism)
}

pub fn level_for_path_plans_is_molecular_test() {
  types.level_for_path("docs/plans/roadmap.md")
  |> should.equal(types.Molecular)
}

pub fn level_for_path_rules_is_atomic_test() {
  types.level_for_path(".claude/rules/my-rule.md")
  |> should.equal(types.Atomic)
}

pub fn rhetorical_for_path_rules_is_axiom_test() {
  types.rhetorical_for_path(".claude/rules/my-rule.md")
  |> should.equal(types.Axiom)
}

pub fn rhetorical_for_path_architecture_is_axiom_test() {
  types.rhetorical_for_path("docs/architecture/SYSTEM.md")
  |> should.equal(types.Axiom)
}

pub fn rhetorical_for_path_journal_is_evidence_test() {
  types.rhetorical_for_path("docs/journal/2026-01-01.md")
  |> should.equal(types.Evidence)
}

// =============================================================================
// C5: types — decay_for_level
// =============================================================================

pub fn decay_for_level_ecosystem_is_slow_test() {
  types.decay_for_level(types.Ecosystem)
  |> should.equal(types.Slow)
}

pub fn decay_for_level_atomic_is_fast_test() {
  types.decay_for_level(types.Atomic)
  |> should.equal(types.Fast)
}

pub fn decay_for_level_molecular_is_medium_test() {
  types.decay_for_level(types.Molecular)
  |> should.equal(types.Medium)
}

// =============================================================================
// C6: types — link_type_to_string
// =============================================================================

pub fn link_type_wiki_test() {
  types.link_type_to_string(types.Wiki)
  |> should.equal("wiki")
}

pub fn link_type_semantic_test() {
  types.link_type_to_string(types.Semantic)
  |> should.equal("semantic")
}

pub fn link_type_code_test() {
  types.link_type_to_string(types.Code)
  |> should.equal("code")
}

pub fn link_type_backlink_test() {
  types.link_type_to_string(types.Backlink)
  |> should.equal("backlink")
}

// =============================================================================
// C7: entropy module
// =============================================================================

pub fn daily_increment_slow_is_small_test() {
  entropy.daily_entropy_increment(types.Slow)
  |> should.equal(0.003)
}

pub fn daily_increment_medium_test() {
  entropy.daily_entropy_increment(types.Medium)
  |> should.equal(0.01)
}

pub fn daily_increment_fast_test() {
  entropy.daily_entropy_increment(types.Fast)
  |> should.equal(0.03)
}

pub fn entropy_after_zero_days_unchanged_test() {
  entropy.entropy_after_days(0.2, types.Slow, 0)
  |> should.equal(0.2)
}

pub fn entropy_after_days_increases_test() {
  let result = entropy.entropy_after_days(0.0, types.Fast, 10)
  { result >. 0.0 } |> should.be_true()
}

pub fn entropy_clamped_at_one_test() {
  let result = entropy.entropy_after_days(0.9, types.Fast, 100)
  { result <=. 1.0 } |> should.be_true()
}

pub fn entropy_label_fresh_test() {
  entropy.entropy_label(0.1)
  |> should.equal("fresh")
}

pub fn entropy_label_aging_test() {
  entropy.entropy_label(0.5)
  |> should.equal("aging")
}

pub fn entropy_label_rotting_test() {
  entropy.entropy_label(0.8)
  |> should.equal("rotting")
}

pub fn entropy_label_excluded_test() {
  entropy.entropy_label(0.95)
  |> should.equal("excluded")
}

pub fn is_fresh_true_test() {
  let h = make_holon("x", "t", "c", types.Atomic, types.Axiom, 0.1, types.Slow)
  entropy.is_fresh(h)
  |> should.be_true()
}

pub fn is_fresh_false_test() {
  let h = make_holon("x", "t", "c", types.Atomic, types.Axiom, 0.5, types.Slow)
  entropy.is_fresh(h)
  |> should.be_false()
}

pub fn is_rotting_true_test() {
  let h = make_holon("x", "t", "c", types.Atomic, types.Axiom, 0.8, types.Slow)
  entropy.is_rotting(h)
  |> should.be_true()
}

pub fn is_excluded_from_rag_test() {
  let h = make_holon("x", "t", "c", types.Atomic, types.Axiom, 0.95, types.Slow)
  entropy.is_excluded_from_rag(h)
  |> should.be_true()
}

pub fn verify_resets_entropy_test() {
  let h = make_holon("x", "t", "c", types.Atomic, types.Axiom, 0.9, types.Slow)
  let verified = entropy.verify(h, "2026-04-14T00:00:00Z")
  verified.entropy
  |> should.equal(0.0)
}

pub fn apply_daily_decay_increases_entropy_test() {
  let h = make_holon("x", "t", "c", types.Atomic, types.Axiom, 0.0, types.Fast)
  let decayed = entropy.apply_daily_decay(h)
  { decayed.entropy >. 0.0 } |> should.be_true()
}

pub fn days_until_rotting_slow_is_large_test() {
  let h =
    make_holon("x", "t", "c", types.Ecosystem, types.Axiom, 0.0, types.Slow)
  let days = entropy.days_until_rotting(h)
  { days > 100 } |> should.be_true()
}

// =============================================================================
// C8: trust module
// =============================================================================

pub fn effective_trust_fresh_axiom_is_high_test() {
  let h = fresh_axiom()
  let t = trust.effective_trust(h)
  { t >=. 0.8 } |> should.be_true()
}

pub fn effective_trust_stale_anecdote_is_low_test() {
  let h = stale_anecdote()
  let t = trust.effective_trust(h)
  { t <. 0.1 } |> should.be_true()
}

pub fn trust_label_high_test() {
  trust.trust_label(0.9)
  |> should.equal("high")
}

pub fn trust_label_medium_test() {
  trust.trust_label(0.6)
  |> should.equal("medium")
}

pub fn trust_label_low_test() {
  trust.trust_label(0.3)
  |> should.equal("low")
}

pub fn trust_label_untrusted_test() {
  trust.trust_label(0.1)
  |> should.equal("untrusted")
}

pub fn authority_rank_axiom_test() {
  trust.authority_rank(types.Axiom)
  |> should.equal(4)
}

pub fn authority_rank_anecdote_test() {
  trust.authority_rank(types.Anecdote)
  |> should.equal(1)
}

pub fn is_rag_eligible_fresh_axiom_test() {
  trust.is_rag_eligible(fresh_axiom())
  |> should.be_true()
}

pub fn is_rag_eligible_stale_anecdote_false_test() {
  trust.is_rag_eligible(stale_anecdote())
  |> should.be_false()
}

pub fn aggregate_trust_empty_is_zero_test() {
  trust.aggregate_trust([])
  |> should.equal(0.0)
}

pub fn aggregate_trust_single_holon_test() {
  let t = trust.aggregate_trust([fresh_axiom()])
  { t >. 0.0 } |> should.be_true()
}

pub fn rank_by_trust_orders_highest_first_test() {
  let holons = [stale_anecdote(), fresh_axiom()]
  let ranked = trust.rank_by_trust(holons)
  case ranked {
    [first, ..] -> {
      { first.uuid == "h-1" } |> should.be_true()
    }
    [] -> should.fail()
  }
}

pub fn filter_trusted_excludes_low_trust_test() {
  let holons = [fresh_axiom(), stale_anecdote()]
  let result = trust.filter_trusted(holons, 0.5)
  list.length(result)
  |> should.equal(1)
}

// =============================================================================
// C9: search module — query builder
// =============================================================================

pub fn search_query_defaults_test() {
  let q = search.query("zenoh mesh")
  q.text
  |> should.equal("zenoh mesh")
  q.max_entropy
  |> should.equal(0.9)
  q.limit
  |> should.equal(5)
}

pub fn search_with_limit_test() {
  let q = search.query("test") |> search.with_limit(10)
  q.limit
  |> should.equal(10)
}

pub fn search_with_max_entropy_test() {
  let q = search.query("test") |> search.with_max_entropy(0.5)
  q.max_entropy
  |> should.equal(0.5)
}

pub fn search_with_level_test() {
  let q = search.query("test") |> search.with_level(types.Ecosystem)
  case q.level_filter {
    option.Some(level) -> level |> should.equal(types.Ecosystem)
    option.None -> should.fail()
  }
}

pub fn search_to_fts5_query_produces_or_test() {
  // Words > 2 chars joined with OR
  let q = search.query("zenoh mesh topology")
  let fts = search.to_fts5_query(q)
  { fts != "" } |> should.be_true()
}

// =============================================================================
// C10: search_in_memory — filtering
// =============================================================================

pub fn search_in_memory_finds_by_content_test() {
  let holons = [fresh_axiom(), stale_anecdote()]
  let q = search.query("zenoh")
  let results = search.search_in_memory(holons, q)
  list.length(results)
  |> should.equal(1)
}

pub fn search_in_memory_excludes_high_entropy_test() {
  let holons = [fresh_axiom(), stale_anecdote()]
  // stale anecdote has entropy 0.85 — excluded when max_entropy = 0.5
  let q = search.query("user") |> search.with_max_entropy(0.5)
  let results = search.search_in_memory(holons, q)
  list.length(results)
  |> should.equal(0)
}

pub fn search_in_memory_level_filter_test() {
  let holons = [fresh_axiom(), stale_anecdote()]
  // fresh_axiom is Ecosystem; stale_anecdote is Atomic
  let q = search.query("the") |> search.with_level(types.Ecosystem)
  let results = search.search_in_memory(holons, q)
  list.length(results)
  |> should.equal(1)
}

pub fn rag_context_empty_results_test() {
  let ctx = search.to_rag_context("my query", [])
  search.rag_context_to_string(ctx)
  |> should.equal("")
}

pub fn rag_context_nonempty_results_test() {
  let h = fresh_axiom()
  let r =
    search.SearchResult(
      holon: h,
      relevance: 0.9,
      snippet: "Architecture decision about Zenoh...",
    )
  let ctx = search.to_rag_context("zenoh", [r])
  let s = search.rag_context_to_string(ctx)
  { s != "" } |> should.be_true()
}

// =============================================================================
// C11: linker — extract_stamp_refs
// =============================================================================

pub fn extract_stamp_refs_finds_sc_refs_test() {
  let content = "This satisfies SC-ZMOF-001 and SC-SIL4-007 requirements."
  let refs = linker.extract_stamp_refs(content)
  { list.length(refs) >= 2 } |> should.be_true()
}

pub fn extract_stamp_refs_deduplicates_test() {
  let content = "SC-ZMOF-001 SC-ZMOF-001 SC-SIL4-001"
  let refs = linker.extract_stamp_refs(content)
  { list.length(refs) <= 2 } |> should.be_true()
}

pub fn extract_stamp_refs_empty_content_test() {
  linker.extract_stamp_refs("")
  |> should.equal([])
}

pub fn extract_stamp_refs_no_refs_test() {
  linker.extract_stamp_refs("No constraints here just plain text")
  |> should.equal([])
}
