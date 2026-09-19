// =============================================================================
// crdt_sets.gleam — Conflict-Free Replicated Data Types (LWW-Element-Set & OR-Set)
// STAMP: SC-SIL6-001, SC-CRDT-001, SC-LATTICE-001
// Codex Astra Mode: Monotonic Join-Semilattice with Commutative State Sync
// =============================================================================

import gleam/list
import gleam/set.{type Set}

// -----------------------------------------------------------------------------
// 1. LWW-Element-Set (Last-Write-Wins Element Set)
// -----------------------------------------------------------------------------

pub type LwwEntry(a) {
  LwwEntry(element: a, timestamp_ns: Int)
}

pub type LwwElementSet(a) {
  LwwElementSet(add_set: List(LwwEntry(a)), remove_set: List(LwwEntry(a)))
}

pub fn new_lww_set() -> LwwElementSet(a) {
  LwwElementSet(add_set: [], remove_set: [])
}

pub fn lww_add(set: LwwElementSet(a), element: a, timestamp_ns: Int) -> LwwElementSet(a) {
  LwwElementSet(
    ..set,
    add_set: [LwwEntry(element, timestamp_ns), ..set.add_set],
  )
}

pub fn lww_remove(set: LwwElementSet(a), element: a, timestamp_ns: Int) -> LwwElementSet(a) {
  LwwElementSet(
    ..set,
    remove_set: [LwwEntry(element, timestamp_ns), ..set.remove_set],
  )
}

pub fn lww_contains(set: LwwElementSet(a), element: a) -> Bool {
  // Find latest add timestamp
  let latest_add =
    list.filter(set.add_set, fn(entry) { entry.element == element })
    |> list.fold(0, fn(acc, entry) {
      case entry.timestamp_ns > acc {
        True -> entry.timestamp_ns
        False -> acc
      }
    })

  // Find latest remove timestamp
  let latest_rem =
    list.filter(set.remove_set, fn(entry) { entry.element == element })
    |> list.fold(0, fn(acc, entry) {
      case entry.timestamp_ns > acc {
        True -> entry.timestamp_ns
        False -> acc
      }
    })

  latest_add > 0 && latest_add > latest_rem
}

pub fn lww_merge(s1: LwwElementSet(a), s2: LwwElementSet(a)) -> LwwElementSet(a) {
  LwwElementSet(
    add_set: list.append(s1.add_set, s2.add_set),
    remove_set: list.append(s1.remove_set, s2.remove_set),
  )
}

// -----------------------------------------------------------------------------
// 2. OR-Set (Observed-Removed Set) with Unique Tag Lattice
// -----------------------------------------------------------------------------

pub type OrEntry(a) {
  OrEntry(element: a, tag: String)
}

pub type OrSet(a) {
  OrSet(add_set: List(OrEntry(a)), tombstone_tags: Set(String))
}

pub fn new_or_set() -> OrSet(a) {
  OrSet(add_set: [], tombstone_tags: set.new())
}

pub fn or_add(set: OrSet(a), element: a, unique_tag: String) -> OrSet(a) {
  OrSet(
    ..set,
    add_set: [OrEntry(element, unique_tag), ..set.add_set],
  )
}

pub fn or_remove(set: OrSet(a), element: a) -> OrSet(a) {
  // Add all active tags for this element to tombstone tags
  let tags_to_tombstone =
    list.filter(set.add_set, fn(entry) { entry.element == element })
    |> list.map(fn(entry) { entry.tag })
    |> set.from_list

  OrSet(
    ..set,
    tombstone_tags: set.union(set.tombstone_tags, tags_to_tombstone),
  )
}

pub fn or_contains(set: OrSet(a), element: a) -> Bool {
  list.any(set.add_set, fn(entry) {
    entry.element == element && !set.contains(set.tombstone_tags, entry.tag)
  })
}

pub fn or_merge(s1: OrSet(a), s2: OrSet(a)) -> OrSet(a) {
  OrSet(
    add_set: list.append(s1.add_set, s2.add_set),
    tombstone_tags: set.union(s1.tombstone_tags, s2.tombstone_tags),
  )
}
