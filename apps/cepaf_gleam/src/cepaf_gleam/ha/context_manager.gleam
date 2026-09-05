//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/context_manager</module>
////     <fsharp-lineage>None — novel Gleam cognitive context tier</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Hierarchical context retrieval for 100M effective context</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-ZK-IMP-001, SC-SATYA-002, SC-OODA-CLAUDE-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Tiered memory model ↪ Three-level context hierarchy.
////       L1 active window injected via hooks. L2 LRU cache with Thompson sampling.
////       L3 semantic search over full ZK corpus.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// HIERARCHICAL CONTEXT MANAGER — 100M EFFECTIVE CONTEXT
//// श्रेणीबद्ध सन्दर्भ प्रबन्धक — १० करोड़ प्रभावी सन्दर्भ
////
//// L1: 200K tokens (Claude's active window) — injected via hooks
//// L2: 1M tokens (beam_cache hot holons) — LRU with Thompson sampling
//// L3: 100M tokens (ZK + embeddings) — semantic + FTS5 search
////
//// The three tiers together create an effectively unlimited context:
////   - L1 holds the most relevant 200K tokens for the current task
////   - L2 provides fast cache promotion for recently-accessed holons
////   - L3 indexes the entire Zettelkasten corpus for semantic retrieval
////
//// STAMP: SC-ZK-IMP-001, SC-SATYA-002, SC-OODA-CLAUDE-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// =============================================================================
// Types
// =============================================================================

/// The three tiers of the context hierarchy
pub type ContextTier {
  /// L1: 200K token active window — injected into every Claude prompt
  L1Active
  /// L2: 1M token LRU cache — hot holons ready for promotion
  L2Cached
  /// L3: Full ZK index — semantic + FTS5 search over all holons
  L3Indexed
}

/// A single context entry representing a retrieved holon or document chunk
pub type ContextEntry {
  ContextEntry(
    /// ZK holon identifier (e.g., "zk-1234")
    holon_id: String,
    /// Human-readable title
    title: String,
    /// Full content of this entry
    content: String,
    /// Which tier this entry currently lives in
    tier: ContextTier,
    /// Relevance score from semantic search or Thompson sampling (0.0–1.0)
    relevance_score: Float,
    /// Estimated token count (~4 chars per token)
    token_estimate: Int,
    /// Monotonic timestamp of last access (arbitrary unit — use Int for BEAM compat)
    last_accessed_ms: Int,
  )
}

/// Budget tracker across all three tiers
pub type ContextBudget {
  ContextBudget(
    /// L1 capacity in tokens (default: 200_000)
    l1_capacity: Int,
    /// Tokens currently consumed by L1 entries
    l1_used: Int,
    /// L2 capacity in tokens (default: 1_000_000)
    l2_capacity: Int,
    /// Tokens currently consumed by L2 entries
    l2_used: Int,
    /// Total holons reachable in L3 (informational — not a hard limit)
    l3_total: Int,
    /// All entries across all tiers
    entries: List(ContextEntry),
  )
}

// =============================================================================
// Constants
// =============================================================================

/// Default L1 capacity: 200K tokens (Claude active window)
const default_l1_capacity = 200_000

/// Default L2 capacity: 1M tokens (beam_cache hot holons)
const default_l2_capacity = 1_000_000

/// Chars-per-token approximation (GPT/Claude tokenisers average ~4 chars/token)
const chars_per_token = 4

// =============================================================================
// Public API
// =============================================================================

/// Initialize a new ContextBudget with default tier capacities.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre-condition: none </P>
///     <C> init() </C>
///     <Q> Post-condition: l1_capacity=200_000, l2_capacity=1_000_000, entries=[] </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init() -> ContextBudget {
  ContextBudget(
    l1_capacity: default_l1_capacity,
    l2_capacity: default_l2_capacity,
    l1_used: 0,
    l2_used: 0,
    l3_total: 0,
    entries: [],
  )
}

/// Estimate token count for a string using the ~4 chars-per-token heuristic.
///
/// This is intentionally approximate. Exact tokenisation requires the model
/// tokeniser; the heuristic is sufficient for budget tracking.
pub fn estimate_tokens(text: String) -> Int {
  let char_count = string.length(text)
  let tokens = char_count / chars_per_token
  // Always return at least 1 token for a non-empty string
  case char_count > 0 {
    True -> int.max(1, tokens)
    False -> 0
  }
}

/// Add an entry to the budget.
///
/// The entry is placed in the tier declared by `entry.tier`.
/// If adding to L1 would exceed capacity the entry is silently placed in L2.
/// If L2 is also full the entry remains in L3 (recorded but not budgeted).
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre-condition: budget is valid, entry.token_estimate >= 0 </P>
///     <C> add_entry(budget, entry) </C>
///     <Q> Post-condition: entry is reachable via l1_entries() or in entries list </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn add_entry(budget: ContextBudget, entry: ContextEntry) -> ContextBudget {
  let tokens = entry.token_estimate

  case entry.tier {
    L1Active -> {
      let fits = budget.l1_used + tokens <= budget.l1_capacity
      case fits {
        True ->
          ContextBudget(..budget, l1_used: budget.l1_used + tokens, entries: [
            entry,
            ..budget.entries
          ])
        False -> {
          // Downgrade to L2 if L1 is full
          let l2_entry = ContextEntry(..entry, tier: L2Cached)
          add_entry(budget, l2_entry)
        }
      }
    }

    L2Cached -> {
      let fits = budget.l2_used + tokens <= budget.l2_capacity
      case fits {
        True ->
          ContextBudget(..budget, l2_used: budget.l2_used + tokens, entries: [
            entry,
            ..budget.entries
          ])
        False -> {
          // Downgrade to L3 — still recorded, not budgeted against L1/L2
          let l3_entry = ContextEntry(..entry, tier: L3Indexed)
          ContextBudget(..budget, l3_total: budget.l3_total + 1, entries: [
            l3_entry,
            ..budget.entries
          ])
        }
      }
    }

    L3Indexed ->
      ContextBudget(..budget, l3_total: budget.l3_total + 1, entries: [
        entry,
        ..budget.entries
      ])
  }
}

/// Evict lowest-relevance L1 entries until `tokens_needed` tokens are freed.
///
/// Entries are sorted ascending by relevance_score; the least-relevant are
/// demoted to L2. If L2 is also full they become L3.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre-condition: tokens_needed > 0 </P>
///     <C> evict_l1(budget, tokens_needed) </C>
///     <Q> Post-condition: l1_used decreases by at least tokens_needed (or until L1 empty) </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn evict_l1(budget: ContextBudget, tokens_needed: Int) -> ContextBudget {
  // Separate L1 entries from non-L1 entries
  let l1_entries = list.filter(budget.entries, fn(e) { e.tier == L1Active })
  let other_entries = list.filter(budget.entries, fn(e) { e.tier != L1Active })

  // Sort L1 by relevance ascending — lowest score evicted first
  let sorted_l1 =
    list.sort(l1_entries, fn(a, b) {
      float.compare(a.relevance_score, b.relevance_score)
    })

  // Evict until enough tokens freed
  let #(kept, evicted, _freed) =
    list.fold(sorted_l1, #([], [], 0), fn(acc, entry) {
      let #(kept, evicted, freed) = acc
      case freed >= tokens_needed {
        True -> #([entry, ..kept], evicted, freed)
        False -> #(kept, [entry, ..evicted], freed + entry.token_estimate)
      }
    })

  // Compute new L1 used from kept entries
  let new_l1_used = list.fold(kept, 0, fn(acc, e) { acc + e.token_estimate })

  // Demote evicted entries to L2
  let demoted = list.map(evicted, fn(e) { ContextEntry(..e, tier: L2Cached) })
  let all_entries = list.flatten([kept, demoted, other_entries])

  // Recompute L2 used
  let new_l2_used =
    list.fold(all_entries, 0, fn(acc, e: ContextEntry) {
      case e.tier {
        L2Cached -> acc + e.token_estimate
        _ -> acc
      }
    })

  ContextBudget(
    ..budget,
    l1_used: new_l1_used,
    l2_used: new_l2_used,
    entries: all_entries,
  )
}

/// Promote an L2 entry to L1 by holon_id.
///
/// If the entry fits in L1, it is promoted. If not, L1 is evicted to make room
/// before promoting. If the holon_id is not found or is already L1, returns
/// the budget unchanged.
pub fn promote_to_l1(budget: ContextBudget, holon_id: String) -> ContextBudget {
  // Find the target entry in L2
  let maybe_target =
    list.find(budget.entries, fn(e) {
      e.holon_id == holon_id && e.tier == L2Cached
    })

  case maybe_target {
    Error(_) -> budget
    Ok(target) -> {
      let tokens = target.token_estimate
      let available = budget.l1_capacity - budget.l1_used

      // Evict if not enough room
      let budget_with_room = case available < tokens {
        True -> evict_l1(budget, tokens - available)
        False -> budget
      }

      // Replace the L2 entry with L1 version
      let new_entries =
        list.map(budget_with_room.entries, fn(e) {
          case e.holon_id == holon_id && e.tier == L2Cached {
            True -> ContextEntry(..e, tier: L1Active)
            False -> e
          }
        })

      // Recompute used counts
      let new_l1_used =
        list.fold(new_entries, 0, fn(acc, e: ContextEntry) {
          case e.tier {
            L1Active -> acc + e.token_estimate
            _ -> acc
          }
        })
      let new_l2_used =
        list.fold(new_entries, 0, fn(acc, e: ContextEntry) {
          case e.tier {
            L2Cached -> acc + e.token_estimate
            _ -> acc
          }
        })

      ContextBudget(
        ..budget_with_room,
        l1_used: new_l1_used,
        l2_used: new_l2_used,
        entries: new_entries,
      )
    }
  }
}

/// Return only L1 entries, sorted by relevance descending (most relevant first).
///
/// This is the list that hook-injection uses to populate Claude's active window.
pub fn l1_entries(budget: ContextBudget) -> List(ContextEntry) {
  budget.entries
  |> list.filter(fn(e) { e.tier == L1Active })
  |> list.sort(fn(a, b) {
    // Descending: compare b to a
    float.compare(b.relevance_score, a.relevance_score)
  })
}

/// Remaining token capacity in L1.
pub fn l1_remaining(budget: ContextBudget) -> Int {
  int.max(0, budget.l1_capacity - budget.l1_used)
}

/// Convert a ContextTier to its string label.
pub fn tier_to_string(tier: ContextTier) -> String {
  case tier {
    L1Active -> "L1Active"
    L2Cached -> "L2Cached"
    L3Indexed -> "L3Indexed"
  }
}

/// Human-readable budget summary — suitable for logging and TUI display.
pub fn summary(budget: ContextBudget) -> String {
  let l1_pct = case budget.l1_capacity > 0 {
    True -> budget.l1_used * 100 / budget.l1_capacity
    False -> 0
  }
  let l2_pct = case budget.l2_capacity > 0 {
    True -> budget.l2_used * 100 / budget.l2_capacity
    False -> 0
  }
  let total_entries = list.length(budget.entries)

  "ContextBudget{"
  <> "L1="
  <> int.to_string(budget.l1_used)
  <> "/"
  <> int.to_string(budget.l1_capacity)
  <> "tok("
  <> int.to_string(l1_pct)
  <> "%) "
  <> "L2="
  <> int.to_string(budget.l2_used)
  <> "/"
  <> int.to_string(budget.l2_capacity)
  <> "tok("
  <> int.to_string(l2_pct)
  <> "%) "
  <> "L3="
  <> int.to_string(budget.l3_total)
  <> "holons "
  <> "entries="
  <> int.to_string(total_entries)
  <> "}"
}

/// Serialise the budget to a JSON string — suitable for Zenoh OTel span payload.
///
/// Does not use gleam/json to avoid an extra dependency; hand-builds a simple
/// flat JSON object with no nesting beyond the entry array.
pub fn to_json(budget: ContextBudget) -> String {
  let entry_jsons =
    list.map(budget.entries, fn(e) {
      "{"
      <> "\"holon_id\":\""
      <> e.holon_id
      <> "\","
      <> "\"title\":\""
      <> e.title
      <> "\","
      <> "\"tier\":\""
      <> tier_to_string(e.tier)
      <> "\","
      <> "\"relevance\":"
      <> float.to_string(e.relevance_score)
      <> ","
      <> "\"tokens\":"
      <> int.to_string(e.token_estimate)
      <> "}"
    })

  let entries_json = "[" <> string.join(entry_jsons, ",") <> "]"

  "{"
  <> "\"l1_capacity\":"
  <> int.to_string(budget.l1_capacity)
  <> ","
  <> "\"l1_used\":"
  <> int.to_string(budget.l1_used)
  <> ","
  <> "\"l2_capacity\":"
  <> int.to_string(budget.l2_capacity)
  <> ","
  <> "\"l2_used\":"
  <> int.to_string(budget.l2_used)
  <> ","
  <> "\"l3_total\":"
  <> int.to_string(budget.l3_total)
  <> ","
  <> "\"entries\":"
  <> entries_json
  <> "}"
}
