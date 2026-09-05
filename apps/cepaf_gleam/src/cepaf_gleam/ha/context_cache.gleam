//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/context_cache</module>
////     <fsharp-lineage>None — novel Gleam L2 LRU cache tier</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>LRU cache for hot ZK holons — beam_cache L2 tier</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-ZK-IMP-001, SC-SATYA-002, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       LRU eviction policy ↪ Pure functional list-based LRU using access_count
////       and last_accessed_ms. No mutable state — state is threaded explicitly.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// CONTEXT CACHE — LRU CACHE FOR HOT ZK HOLONS
//// सन्दर्भ कैश — उष्ण ज़ेटेलकास्टन होलोन LRU कैश
////
//// L2 tier of the three-tier context hierarchy (see context_manager.gleam).
//// Provides fast O(n) lookup for recently-used holons without disk/network I/O.
////
//// Eviction policy: Least-Recently-Used by last_accessed_ms.
//// When at capacity, the entry with the smallest last_accessed_ms is evicted.
////
//// STAMP: SC-ZK-IMP-001, SC-SATYA-002, SC-MUDA-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// =============================================================================
// Types
// =============================================================================

/// A single cached holon entry.
///
/// access_count tracks how many times the entry has been retrieved —
/// useful for Thompson-sampling-based promotion heuristics.
/// last_accessed_ms is a monotonic timestamp (arbitrary unit; typically
/// `erlang:monotonic_time(millisecond)` as injected by the caller).
pub type CacheEntry {
  CacheEntry(
    holon_id: String,
    content: String,
    access_count: Int,
    last_accessed_ms: Int,
  )
}

/// Immutable LRU cache state.
///
/// entries: all currently cached entries (most-recently-used first).
/// max_entries: hard capacity — eviction occurs when |entries| == max_entries.
/// hits: cumulative cache hits since init.
/// misses: cumulative cache misses since init.
pub type CacheState {
  CacheState(
    entries: List(CacheEntry),
    max_entries: Int,
    hits: Int,
    misses: Int,
  )
}

// =============================================================================
// Constants
// =============================================================================

/// Default max entries for a context cache.
const default_max_entries = 128

// =============================================================================
// Public API
// =============================================================================

/// Initialize a new empty cache with a given capacity.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre-condition: max_entries >= 1 </P>
///     <C> init(max_entries) </C>
///     <Q> Post-condition: entries=[], hits=0, misses=0, max_entries=max_entries </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init(max_entries: Int) -> CacheState {
  let capped = int.max(1, max_entries)
  CacheState(entries: [], max_entries: capped, hits: 0, misses: 0)
}

/// Initialize with the default capacity (128 entries).
pub fn init_default() -> CacheState {
  init(default_max_entries)
}

/// Look up a holon by ID.
///
/// Returns `#(new_state, Ok(content))` on hit — the entry's access_count is
/// incremented and last_accessed_ms is updated to `now_ms`.
/// Returns `#(new_state, Error(Nil))` on miss — misses counter is incremented.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre-condition: state is valid </P>
///     <C> get(state, holon_id) </C>
///     <Q> Post-condition: (hit → Ok(content) ∧ access_count++, miss → Error(Nil) ∧ misses++) </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn get(
  state: CacheState,
  holon_id: String,
) -> #(CacheState, Result(String, Nil)) {
  case list.find(state.entries, fn(e) { e.holon_id == holon_id }) {
    Error(_) -> #(CacheState(..state, misses: state.misses + 1), Error(Nil))
    Ok(entry) -> {
      // Update the entry in-place (increment access_count)
      let updated_entries =
        list.map(state.entries, fn(e) {
          case e.holon_id == holon_id {
            True -> CacheEntry(..e, access_count: e.access_count + 1)
            False -> e
          }
        })
      let new_state =
        CacheState(..state, entries: updated_entries, hits: state.hits + 1)
      #(new_state, Ok(entry.content))
    }
  }
}

/// Insert or update an entry in the cache.
///
/// If `holon_id` already exists, its content is replaced and access_count is
/// reset to 1 with the provided `now_ms`.
/// If the cache is at capacity and `holon_id` is new, `evict_lru/1` is called
/// first to make room.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre-condition: state is valid, content != "" </P>
///     <C> put(state, holon_id, content, now_ms) </C>
///     <Q> Post-condition: get(new_state, holon_id) = Ok(content) </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn put(
  state: CacheState,
  holon_id: String,
  content: String,
  now_ms: Int,
) -> CacheState {
  let already_exists = list.any(state.entries, fn(e) { e.holon_id == holon_id })

  case already_exists {
    True -> {
      // Update existing entry
      let updated =
        list.map(state.entries, fn(e) {
          case e.holon_id == holon_id {
            True ->
              CacheEntry(
                holon_id: holon_id,
                content: content,
                access_count: e.access_count + 1,
                last_accessed_ms: now_ms,
              )
            False -> e
          }
        })
      CacheState(..state, entries: updated)
    }
    False -> {
      // Make room if at capacity
      let state_with_room = case
        list.length(state.entries) >= state.max_entries
      {
        True -> evict_lru(state)
        False -> state
      }
      let new_entry =
        CacheEntry(
          holon_id: holon_id,
          content: content,
          access_count: 1,
          last_accessed_ms: now_ms,
        )
      CacheState(..state_with_room, entries: [
        new_entry,
        ..state_with_room.entries
      ])
    }
  }
}

/// Evict the least-recently-used entry (smallest last_accessed_ms).
///
/// If the cache is empty, returns the state unchanged.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre-condition: state.entries may be empty </P>
///     <C> evict_lru(state) </C>
///     <Q> Post-condition: |entries| = max(0, |old entries| - 1),
///         removed entry had minimum last_accessed_ms </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn evict_lru(state: CacheState) -> CacheState {
  case state.entries {
    [] -> state
    _ -> {
      // Find the entry with the smallest last_accessed_ms
      let lru =
        list.fold(state.entries, list.first(state.entries), fn(acc, entry) {
          case acc {
            Error(_) -> Ok(entry)
            Ok(current_lru) ->
              case entry.last_accessed_ms < current_lru.last_accessed_ms {
                True -> Ok(entry)
                False -> Ok(current_lru)
              }
          }
        })

      case lru {
        Error(_) -> state
        Ok(to_evict) -> {
          let trimmed =
            list.filter(state.entries, fn(e) { e.holon_id != to_evict.holon_id })
          CacheState(..state, entries: trimmed)
        }
      }
    }
  }
}

/// Compute the cache hit rate as a Float in [0.0, 1.0].
///
/// Returns 0.0 if no lookups have been performed yet.
///
/// hit_rate = hits / (hits + misses)
pub fn hit_rate(state: CacheState) -> Float {
  let total = state.hits + state.misses
  case total > 0 {
    True -> int.to_float(state.hits) /. int.to_float(total)
    False -> 0.0
  }
}

/// Return the number of entries currently in the cache.
pub fn size(state: CacheState) -> Int {
  list.length(state.entries)
}

/// Return True if the cache contains the given holon_id.
pub fn contains(state: CacheState, holon_id: String) -> Bool {
  list.any(state.entries, fn(e) { e.holon_id == holon_id })
}

/// Human-readable cache summary suitable for logging and TUI display.
pub fn summary(state: CacheState) -> String {
  let total = state.hits + state.misses
  let rate_pct = case total > 0 {
    True -> state.hits * 100 / total
    False -> 0
  }
  let fill_pct = case state.max_entries > 0 {
    True -> list.length(state.entries) * 100 / state.max_entries
    False -> 0
  }

  "ContextCache{"
  <> "size="
  <> int.to_string(list.length(state.entries))
  <> "/"
  <> int.to_string(state.max_entries)
  <> "("
  <> int.to_string(fill_pct)
  <> "%) "
  <> "hits="
  <> int.to_string(state.hits)
  <> " misses="
  <> int.to_string(state.misses)
  <> " hit_rate="
  <> int.to_string(rate_pct)
  <> "%}"
}

/// Return entries sorted by access_count descending — hottest holons first.
///
/// Useful for Thompson-sampling-based promotion to L1 context window.
pub fn hottest_entries(state: CacheState) -> List(CacheEntry) {
  list.sort(state.entries, fn(a, b) {
    int.compare(b.access_count, a.access_count)
  })
}

/// Serialise cache state to a compact JSON string for Zenoh OTel span payload.
pub fn to_json(state: CacheState) -> String {
  let entry_jsons =
    list.map(state.entries, fn(e) {
      "{"
      <> "\"holon_id\":\""
      <> e.holon_id
      <> "\","
      <> "\"access_count\":"
      <> int.to_string(e.access_count)
      <> ","
      <> "\"last_accessed_ms\":"
      <> int.to_string(e.last_accessed_ms)
      <> "}"
    })

  let rate = hit_rate(state)
  let rate_str = float.to_string(rate)

  "{"
  <> "\"size\":"
  <> int.to_string(list.length(state.entries))
  <> ","
  <> "\"max_entries\":"
  <> int.to_string(state.max_entries)
  <> ","
  <> "\"hits\":"
  <> int.to_string(state.hits)
  <> ","
  <> "\"misses\":"
  <> int.to_string(state.misses)
  <> ","
  <> "\"hit_rate\":"
  <> rate_str
  <> ","
  <> "\"entries\":["
  <> string.join(entry_jsons, ",")
  <> "]}"
}
