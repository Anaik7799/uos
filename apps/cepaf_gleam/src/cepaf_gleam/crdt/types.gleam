//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/crdt/types</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-ULTRA-001, SC-XHOLON-006</stamp-controls></compliance>
//// </c3i-module>
////
//// Conflict-free Replicated Data Types for Zenoh-native state backplane.
//// Mathematical properties: commutative, associative, idempotent merge.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string

/// Last-Writer-Wins Register — timestamp-based conflict resolution
pub type LwwRegister {
  LwwRegister(value: String, timestamp: Int, node_id: String)
}

/// Grow-only Counter — per-node increment, sum for value
pub type GCounter {
  GCounter(counts: Dict(String, Int))
}

/// Positive-Negative Counter — two G-Counters for inc/dec
pub type PNCounter {
  PNCounter(positive: Dict(String, Int), negative: Dict(String, Int))
}

/// Observed-Remove Set — add-wins semantics with unique tags
pub type ORSetEntry {
  ORSetEntry(element: String, tag: String, timestamp: Int)
}

pub type ORSet {
  ORSet(entries: List(ORSetEntry), removed_tags: List(String))
}

// =============================================================================
// LWW-Register operations
// =============================================================================

pub fn lww_new(value: String, node_id: String, timestamp: Int) -> LwwRegister {
  LwwRegister(value: value, timestamp: timestamp, node_id: node_id)
}

pub fn lww_set(
  reg: LwwRegister,
  value: String,
  node_id: String,
  timestamp: Int,
) -> LwwRegister {
  case timestamp > reg.timestamp {
    True -> LwwRegister(value: value, timestamp: timestamp, node_id: node_id)
    False ->
      case
        timestamp == reg.timestamp
        && string.compare(node_id, reg.node_id) == order.Gt
      {
        True ->
          LwwRegister(value: value, timestamp: timestamp, node_id: node_id)
        False -> reg
      }
  }
}

pub fn lww_merge(a: LwwRegister, b: LwwRegister) -> LwwRegister {
  lww_set(a, b.value, b.node_id, b.timestamp)
}

// =============================================================================
// G-Counter operations
// =============================================================================

pub fn gcounter_new() -> GCounter {
  GCounter(counts: dict.new())
}

pub fn gcounter_increment(
  counter: GCounter,
  node_id: String,
  delta: Int,
) -> GCounter {
  let current = dict.get(counter.counts, node_id) |> result.unwrap(0)
  GCounter(counts: dict.insert(counter.counts, node_id, current + delta))
}

pub fn gcounter_value(counter: GCounter) -> Int {
  dict.fold(counter.counts, 0, fn(acc, _k, v) { acc + v })
}

pub fn gcounter_merge(a: GCounter, b: GCounter) -> GCounter {
  let all_keys =
    list.append(dict.keys(a.counts), dict.keys(b.counts)) |> list.unique
  let merged =
    list.fold(all_keys, dict.new(), fn(acc, key) {
      let va = dict.get(a.counts, key) |> result.unwrap(0)
      let vb = dict.get(b.counts, key) |> result.unwrap(0)
      dict.insert(acc, key, int.max(va, vb))
    })
  GCounter(counts: merged)
}

// =============================================================================
// PN-Counter operations
// =============================================================================

pub fn pncounter_new() -> PNCounter {
  PNCounter(positive: dict.new(), negative: dict.new())
}

pub fn pncounter_increment(
  counter: PNCounter,
  node_id: String,
  delta: Int,
) -> PNCounter {
  let current = dict.get(counter.positive, node_id) |> result.unwrap(0)
  PNCounter(
    ..counter,
    positive: dict.insert(counter.positive, node_id, current + delta),
  )
}

pub fn pncounter_decrement(
  counter: PNCounter,
  node_id: String,
  delta: Int,
) -> PNCounter {
  let current = dict.get(counter.negative, node_id) |> result.unwrap(0)
  PNCounter(
    ..counter,
    negative: dict.insert(counter.negative, node_id, current + delta),
  )
}

pub fn pncounter_value(counter: PNCounter) -> Int {
  let pos = dict.fold(counter.positive, 0, fn(acc, _k, v) { acc + v })
  let neg = dict.fold(counter.negative, 0, fn(acc, _k, v) { acc + v })
  pos - neg
}

pub fn pncounter_merge(a: PNCounter, b: PNCounter) -> PNCounter {
  PNCounter(
    positive: merge_dicts(a.positive, b.positive),
    negative: merge_dicts(a.negative, b.negative),
  )
}

// =============================================================================
// OR-Set operations
// =============================================================================

pub fn orset_new() -> ORSet {
  ORSet(entries: [], removed_tags: [])
}

pub fn orset_add(
  set: ORSet,
  element: String,
  tag: String,
  timestamp: Int,
) -> ORSet {
  let entry = ORSetEntry(element: element, tag: tag, timestamp: timestamp)
  ORSet(..set, entries: [entry, ..set.entries])
}

pub fn orset_remove(set: ORSet, element: String) -> ORSet {
  let tags_to_remove =
    list.filter_map(set.entries, fn(e) {
      case e.element == element {
        True -> Ok(e.tag)
        False -> Error(Nil)
      }
    })
  ORSet(
    entries: list.filter(set.entries, fn(e) { e.element != element }),
    removed_tags: list.append(set.removed_tags, tags_to_remove),
  )
}

pub fn orset_elements(set: ORSet) -> List(String) {
  set.entries |> list.map(fn(e) { e.element }) |> list.unique
}

pub fn orset_merge(a: ORSet, b: ORSet) -> ORSet {
  let all_entries = list.append(a.entries, b.entries)
  let all_removed = list.append(a.removed_tags, b.removed_tags) |> list.unique
  let surviving =
    list.filter(all_entries, fn(e) { !list.contains(all_removed, e.tag) })
  ORSet(entries: surviving, removed_tags: all_removed)
}

// =============================================================================
// Helpers
// =============================================================================

fn merge_dicts(
  a: Dict(String, Int),
  b: Dict(String, Int),
) -> Dict(String, Int) {
  let all_keys = list.append(dict.keys(a), dict.keys(b)) |> list.unique
  list.fold(all_keys, dict.new(), fn(acc, key) {
    let va = dict.get(a, key) |> result.unwrap(0)
    let vb = dict.get(b, key) |> result.unwrap(0)
    dict.insert(acc, key, int.max(va, vb))
  })
}
