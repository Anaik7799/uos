//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/crdt/delta_state</module>
////     <fsharp-lineage>N/A — Pure Gleam/BEAM Delta-State CRDT Mesh</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <layer>L7_FEDERATION</layer>
////     <cross-layer-dependencies>
////       <dep layer="L0_CONSTITUTIONAL">cepaf_gleam/c3i/trace13</dep>
////     </cross-layer-dependencies>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-CRDT-001, SC-CRDT-002, SC-GLM-CORE-001, SC-SIL6-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="commutativity">merge(A, B) == merge(B, A)</property>
////     <property name="associativity">merge(merge(A, B), C) == merge(A, merge(B, C))</property>
////     <property name="idempotence">merge(A, A) == A</property>
////     <property name="monotonicity">State monotonically advances in semilattice ordering</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import gleam/int
import gleam/list
import gleam/order.{Eq, Gt, Lt}
import gleam/string

// ---------------------------------------------------------------------------
// Basic Types & Vector Clocks
// ---------------------------------------------------------------------------

pub type NodeId =
  String

/// A causal Dot representing an event produced by a specific node.
pub type Dot {
  Dot(node: NodeId, counter: Int)
}

/// A Vector Clock represented as an association list of node IDs to monotonic counters.
pub type VectorClock =
  List(#(NodeId, Int))

/// Create an empty vector clock.
pub fn empty_clock() -> VectorClock {
  []
}

/// Get the counter for a given node in a vector clock.
pub fn get_clock(clock: VectorClock, node: NodeId) -> Int {
  case list.key_find(clock, node) {
    Ok(c) -> c
    Error(_) -> 0
  }
}

/// Increment the clock counter for a node, returning the updated clock and new dot.
pub fn increment_clock(clock: VectorClock, node: NodeId) -> #(VectorClock, Dot) {
  let current = get_clock(clock, node)
  let next = current + 1
  let updated = list.key_set(clock, node, next)
  #(updated, Dot(node, next))
}

/// Merge two vector clocks taking the pointwise maximum (least upper bound in semilattice).
pub fn merge_clocks(a: VectorClock, b: VectorClock) -> VectorClock {
  // Add all from a updated with max from b
  let merged_from_a =
    list.map(a, fn(entry) {
      let #(node, count_a) = entry
      let count_b = get_clock(b, node)
      #(node, int.max(count_a, count_b))
    })

  // Add any entries in b that were not in a
  let keys_in_a = list.map(a, fn(pair) { pair.0 })
  let missing_from_b =
    list.filter(b, fn(pair) { !list.contains(keys_in_a, pair.0) })

  list.append(merged_from_a, missing_from_b)
}

/// Check if clock A causally dominates (is >= in all components) clock B.
pub fn dominates(a: VectorClock, b: VectorClock) -> Bool {
  list.all(b, fn(pair) {
    let #(node, count_b) = pair
    get_clock(a, node) >= count_b
  })
}

// ---------------------------------------------------------------------------
// LWW-Register (Last-Write-Wins Register with deterministic tie-breaker)
// ---------------------------------------------------------------------------

pub type LWWRegister(a) {
  LWWRegister(value: a, timestamp_us: Int, writer: NodeId)
}

pub fn new_lww_register(
  value: a,
  timestamp_us: Int,
  writer: NodeId,
) -> LWWRegister(a) {
  LWWRegister(value: value, timestamp_us: timestamp_us, writer: writer)
}

pub fn merge_lww(a: LWWRegister(a), b: LWWRegister(a)) -> LWWRegister(a) {
  case int.compare(a.timestamp_us, b.timestamp_us) {
    Gt -> a
    Lt -> b
    Eq ->
      // Deterministic tie-breaker on writer node ID
      case string.compare(a.writer, b.writer) {
        Gt -> a
        _ -> b
      }
  }
}

// ---------------------------------------------------------------------------
// OR-Set (Observed-Remove Set with causal dot tracking)
// ---------------------------------------------------------------------------

pub type ORSet(a) {
  ORSet(elements: List(#(a, Dot)), tombstones: List(Dot))
}

pub fn empty_orset() -> ORSet(a) {
  ORSet(elements: [], tombstones: [])
}

/// Add an element to the OR-Set with a fresh causal dot.
pub fn orset_add(set: ORSet(a), element: a, dot: Dot) -> ORSet(a) {
  ORSet(elements: [#(element, dot), ..set.elements], tombstones: set.tombstones)
}

/// Remove an element from the OR-Set by moving its observed dots into tombstones.
pub fn orset_remove(set: ORSet(a), element: a) -> ORSet(a) {
  let #(matching, remaining) =
    list.partition(set.elements, fn(pair) { pair.0 == element })
  let removed_dots = list.map(matching, fn(pair) { pair.1 })
  ORSet(
    elements: remaining,
    tombstones: list.append(set.tombstones, removed_dots),
  )
}

/// Check if an element is in the OR-Set (must have at least one non-tombstoned dot).
pub fn orset_contains(set: ORSet(a), element: a) -> Bool {
  list.any(set.elements, fn(pair) {
    let #(elem, dot) = pair
    elem == element && !dot_in_list(set.tombstones, dot)
  })
}

/// Returns the list of distinct active elements in the OR-Set.
pub fn orset_read(set: ORSet(a)) -> List(a) {
  let active =
    list.filter(set.elements, fn(pair) {
      !dot_in_list(set.tombstones, pair.1)
    })
  let raw_elems = list.map(active, fn(pair) { pair.0 })
  list.unique(raw_elems)
}

/// Merge two OR-Sets by unioning elements and tombstones, filtering out tombstoned elements.
pub fn merge_orset(a: ORSet(a), b: ORSet(a)) -> ORSet(a) {
  let all_tombstones = list.unique(list.append(a.tombstones, b.tombstones))
  let combined_elements = list.append(a.elements, b.elements)
  let surviving_elements =
    list.filter(combined_elements, fn(pair) {
      !dot_in_list(all_tombstones, pair.1)
    })
  ORSet(
    elements: list.unique(surviving_elements),
    tombstones: all_tombstones,
  )
}

fn dot_in_list(dots: List(Dot), target: Dot) -> Bool {
  list.any(dots, fn(d) { d.node == target.node && d.counter == target.counter })
}

// ---------------------------------------------------------------------------
// PN-Counter (Positive-Negative Counter)
// ---------------------------------------------------------------------------

pub type PNCounter {
  PNCounter(positive: VectorClock, negative: VectorClock)
}

pub fn empty_pncounter() -> PNCounter {
  PNCounter(positive: empty_clock(), negative: empty_clock())
}

pub fn pncounter_increment(
  counter: PNCounter,
  node: NodeId,
  amount: Int,
) -> PNCounter {
  let current = get_clock(counter.positive, node)
  PNCounter(
    positive: list.key_set(counter.positive, node, current + amount),
    negative: counter.negative,
  )
}

pub fn pncounter_decrement(
  counter: PNCounter,
  node: NodeId,
  amount: Int,
) -> PNCounter {
  let current = get_clock(counter.negative, node)
  PNCounter(
    positive: counter.positive,
    negative: list.key_set(counter.negative, node, current + amount),
  )
}

pub fn pncounter_value(counter: PNCounter) -> Int {
  let pos_sum =
    list.fold(counter.positive, 0, fn(acc, pair) { acc + pair.1 })
  let neg_sum =
    list.fold(counter.negative, 0, fn(acc, pair) { acc + pair.1 })
  pos_sum - neg_sum
}

pub fn merge_pncounter(a: PNCounter, b: PNCounter) -> PNCounter {
  PNCounter(
    positive: merge_clocks(a.positive, b.positive),
    negative: merge_clocks(a.negative, b.negative),
  )
}

// ---------------------------------------------------------------------------
// Mesh Delta State Composite
// ---------------------------------------------------------------------------

pub type MeshDeltaState {
  MeshDeltaState(
    origin_node: NodeId,
    epoch_us: Int,
    vector_clock: VectorClock,
    active_workers: ORSet(String),
    task_counters: PNCounter,
    leader_lease: LWWRegister(String),
  )
}

/// Creates a new initial mesh delta state for a node.
pub fn new_mesh_delta_state(node: NodeId, epoch_us: Int) -> MeshDeltaState {
  MeshDeltaState(
    origin_node: node,
    epoch_us: epoch_us,
    vector_clock: [#(node, 1)],
    active_workers: empty_orset(),
    task_counters: empty_pncounter(),
    leader_lease: new_lww_register("none", epoch_us, node),
  )
}

/// Merges two distributed mesh delta states using semilattice LUB operators.
pub fn merge_mesh_states(
  a: MeshDeltaState,
  b: MeshDeltaState,
) -> MeshDeltaState {
  MeshDeltaState(
    origin_node: case string.compare(a.origin_node, b.origin_node) {
      Gt -> a.origin_node
      _ -> b.origin_node
    },
    epoch_us: int.max(a.epoch_us, b.epoch_us),
    vector_clock: merge_clocks(a.vector_clock, b.vector_clock),
    active_workers: merge_orset(a.active_workers, b.active_workers),
    task_counters: merge_pncounter(a.task_counters, b.task_counters),
    leader_lease: merge_lww(a.leader_lease, b.leader_lease),
  )
}
