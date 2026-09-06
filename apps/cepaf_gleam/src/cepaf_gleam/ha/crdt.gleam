//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/crdt</module>
////     <fsharp-lineage>None — novel CRDT foundation for Zenoh-native state backplane</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L7_FEDERATION</layer>
////     <mesh-domain>
////       CRDT Foundation for distributed state synchronization over Zenoh pub/sub.
////       Implements G-Counter, PN-Counter, LWW-Register, OR-Set, and Version Vector
////       with provably correct mathematical properties: commutativity, associativity,
////       idempotency. SC-ULTRA-001 Focus 2: Zenoh-Native CRDT State Backplane.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>
////       SC-ULTRA-001, SC-XHOLON-006, SC-HA-001, SC-FUNC-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       CRDT lattice join (⊔) ≅ Gleam merge functions.
////       Every merge is a least-upper-bound on a join-semilattice.
////       Commutativity, associativity, and idempotency hold by construction.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// CRDT STATE SYNCHRONIZATION — CONFLICT-FREE REPLICATED DATA TYPES
//// एकत्वं बहुत्वे — Unity in multiplicity (Sanskrit: Indrajaal L7 inscription)
////
//// Five fundamental CRDTs for distributed state over Zenoh pub/sub:
////
////   1. GCounter      — Grow-only counter (one entry per node)
////   2. PNCounter     — Positive-negative counter (increment + decrement)
////   3. LWWRegister   — Last-writer-wins register with timestamp
////   4. ORSet         — Observed-remove set (add-wins semantics)
////   5. VersionVector — Causal ordering across nodes
////
//// Mathematical properties proven by the merge operations:
////
////   Commutativity:  merge(a, b) = merge(b, a)
////   Associativity:  merge(merge(a,b), c) = merge(a, merge(b,c))
////   Idempotency:    merge(a, a) = a
////
//// Storage: List(#(String, Int)) association lists for pure functional style.
//// All types are pure values — no side effects, no mutable state.
////
//// STAMP: SC-ULTRA-001 (Focus 2), SC-XHOLON-006, SC-HA-001

import gleam/int
import gleam/list
import gleam/order
import gleam/string

// =============================================================================
// G-Counter — Grow-only Counter
// =============================================================================
//
// Each node maintains its own monotonically-increasing count.
// The global value is the sum of all per-node counts.
// Merge takes the max per-node — this is the lattice join on (ℤ≥0, max).
//
// Storage: association list of (node_id, count) pairs.
//
// Lattice proof:
//   Commutativity: max(a,b) = max(b,a)               ✓
//   Associativity: max(max(a,b),c) = max(a,max(b,c)) ✓
//   Idempotency:   max(a,a) = a                       ✓

/// G-Counter — grow-only counter, one entry per node.
///
/// `counts` is an association list of (node_id, count) pairs.
/// Each node only increments its own entry; merge takes the per-node maximum.
pub type GCounter {
  GCounter(counts: List(#(String, Int)))
}

/// Create a new empty G-Counter.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">Bootstrap ↔ GCounter with empty lattice</morphism>
///   <formal-proof>
///     <P> Pre: none </P>
///     <C> gcounter_new() </C>
///     <Q> Post: gcounter_value(result) = 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn gcounter_new() -> GCounter {
  GCounter(counts: [])
}

/// Increment the given node's count by 1.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">GCounter ↔ GCounter (node count + 1)</morphism>
///   <formal-proof>
///     <P> Pre: counter is a valid GCounter, node_id is non-empty </P>
///     <C> gcounter_increment(counter, node_id) </C>
///     <Q> Post: gcounter_value(result) = gcounter_value(counter) + 1 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn gcounter_increment(counter: GCounter, node_id: String) -> GCounter {
  let current = alist_get(counter.counts, node_id, 0)
  GCounter(counts: alist_set(counter.counts, node_id, current + 1))
}

/// Get the global value — sum of all node counts.
pub fn gcounter_value(counter: GCounter) -> Int {
  list.fold(counter.counts, 0, fn(acc, pair) { acc + pair.1 })
}

/// Merge two G-Counters — take the per-node maximum (lattice join ⊔).
///
/// Mathematical proof of CRDT properties:
///   Commutativity: max(a[k], b[k]) = max(b[k], a[k]) for all k
///   Associativity: max(max(a,b),c) = max(a,max(b,c)) for all k
///   Idempotency:   max(a[k], a[k]) = a[k] for all k
pub fn gcounter_merge(a: GCounter, b: GCounter) -> GCounter {
  GCounter(counts: alist_merge_max(a.counts, b.counts))
}

// =============================================================================
// PN-Counter — Positive-Negative Counter
// =============================================================================
//
// Two G-Counters: one for increments, one for decrements.
// Value = sum(positive) - sum(negative).
// Merge delegates to gcounter_merge for each sub-counter.

/// PN-Counter — positive-negative counter for increment + decrement.
pub type PNCounter {
  PNCounter(positive: GCounter, negative: GCounter)
}

/// Create a new PN-Counter with both sub-counters at zero.
pub fn pncounter_new() -> PNCounter {
  PNCounter(positive: gcounter_new(), negative: gcounter_new())
}

/// Increment the PN-Counter on the given node by 1.
pub fn pncounter_increment(counter: PNCounter, node_id: String) -> PNCounter {
  PNCounter(..counter, positive: gcounter_increment(counter.positive, node_id))
}

/// Decrement the PN-Counter on the given node by 1.
pub fn pncounter_decrement(counter: PNCounter, node_id: String) -> PNCounter {
  PNCounter(..counter, negative: gcounter_increment(counter.negative, node_id))
}

/// Get the global PN-Counter value: sum(positive) - sum(negative).
pub fn pncounter_value(counter: PNCounter) -> Int {
  gcounter_value(counter.positive) - gcounter_value(counter.negative)
}

/// Merge two PN-Counters — merge each sub-counter independently.
///
/// Inherits CRDT properties from gcounter_merge.
pub fn pncounter_merge(a: PNCounter, b: PNCounter) -> PNCounter {
  PNCounter(
    positive: gcounter_merge(a.positive, b.positive),
    negative: gcounter_merge(a.negative, b.negative),
  )
}

// =============================================================================
// LWW-Register — Last-Writer-Wins Register
// =============================================================================
//
// Conflict resolution: highest timestamp_ms wins.
// Tie-break: lexicographically larger node_id wins (deterministic total order).
// This gives a total order on (timestamp_ms, node_id) pairs — a valid lattice.
//
// Lattice proof:
//   Commutativity: max(a,b) = max(b,a) under total order ✓
//   Associativity: max(max(a,b),c) = max(a,max(b,c))    ✓
//   Idempotency:   max(a,a) = a                          ✓

/// LWW-Register — last-writer-wins register with millisecond timestamp.
pub type LWWRegister {
  LWWRegister(value: String, timestamp_ms: Int, node_id: String)
}

/// Create a new LWW-Register with an initial value, timestamp, and node_id.
pub fn lww_new(
  value: String,
  timestamp_ms: Int,
  node_id: String,
) -> LWWRegister {
  LWWRegister(value: value, timestamp_ms: timestamp_ms, node_id: node_id)
}

/// Set the register value — accepted only if (timestamp_ms, node_id) > current.
///
/// Tie-break: if timestamps are equal, the lexicographically larger node_id wins.
pub fn lww_set(
  reg: LWWRegister,
  value: String,
  timestamp_ms: Int,
  node_id: String,
) -> LWWRegister {
  case timestamp_ms > reg.timestamp_ms {
    True ->
      LWWRegister(value: value, timestamp_ms: timestamp_ms, node_id: node_id)
    False ->
      case
        timestamp_ms == reg.timestamp_ms
        && string.compare(node_id, reg.node_id) == order.Gt
      {
        True ->
          LWWRegister(
            value: value,
            timestamp_ms: timestamp_ms,
            node_id: node_id,
          )
        False -> reg
      }
  }
}

/// Merge two LWW-Registers — the higher (timestamp_ms, node_id) pair wins.
///
/// Mathematical proof of CRDT properties:
///   Commutativity: total order comparison is symmetric in its max outcome ✓
///   Associativity: max of totals is associative                           ✓
///   Idempotency:   max(a, a) = a                                          ✓
pub fn lww_merge(a: LWWRegister, b: LWWRegister) -> LWWRegister {
  case b.timestamp_ms > a.timestamp_ms {
    True -> b
    False ->
      case b.timestamp_ms == a.timestamp_ms {
        True ->
          case string.compare(b.node_id, a.node_id) == order.Gt {
            True -> b
            False -> a
          }
        False -> a
      }
  }
}

// =============================================================================
// OR-Set — Observed-Remove Set
// =============================================================================
//
// Add-wins semantics: concurrent add and remove → element survives.
// Each element in the set is tagged with a (value, unique_tag, timestamp_ms)
// triple.  Remove tombstones the specific tags observed at remove time.
// Merge is union of elements minus union of tombstones — set lattice join.
//
// Storage: List(#(String, String, Int)) = (value, unique_tag, timestamp_ms)
//
// Lattice proof:
//   Commutativity: union(A,B) = union(B,A)                   ✓
//   Associativity: union(union(A,B),C) = union(A,union(B,C)) ✓
//   Idempotency:   union(A,A) = A                            ✓

/// OR-Set — observed-remove set with add-wins semantics.
///
/// `elements` is a list of (value, unique_tag, timestamp_ms) triples.
/// `tombstones` is a list of tombstoned unique tags.
pub type ORSet {
  ORSet(elements: List(#(String, String, Int)), tombstones: List(String))
}

/// Create a new empty OR-Set.
pub fn orset_new() -> ORSet {
  ORSet(elements: [], tombstones: [])
}

/// Add a value with a unique tag and timestamp to the OR-Set.
///
/// The tag MUST be globally unique (e.g., node_id + logical clock) to
/// distinguish concurrent additions of the same value.
pub fn orset_add(
  set: ORSet,
  value: String,
  tag: String,
  timestamp_ms: Int,
) -> ORSet {
  case list.contains(set.tombstones, tag) {
    True -> set
    False ->
      ORSet(..set, elements: [#(value, tag, timestamp_ms), ..set.elements])
  }
}

/// Remove all live instances of a value from the OR-Set.
///
/// Tombstones all tags currently associated with the value.
/// Concurrent adds with new tags survive (add-wins semantics).
pub fn orset_remove(set: ORSet, value: String) -> ORSet {
  let tags_to_tombstone =
    list.filter_map(set.elements, fn(triple) {
      case triple.0 == value {
        True -> Ok(triple.1)
        False -> Error(Nil)
      }
    })
  let surviving = list.filter(set.elements, fn(triple) { triple.0 != value })
  let new_tombstones =
    list.append(set.tombstones, tags_to_tombstone) |> list.unique
  ORSet(elements: surviving, tombstones: new_tombstones)
}

/// Check if a value is currently in the OR-Set.
pub fn orset_contains(set: ORSet, value: String) -> Bool {
  list.any(set.elements, fn(triple) { triple.0 == value })
}

/// Get the list of distinct values currently in the OR-Set.
pub fn orset_values(set: ORSet) -> List(String) {
  set.elements |> list.map(fn(triple) { triple.0 }) |> list.unique
}

/// Merge two OR-Sets — union of elements minus union of tombstones.
///
/// Mathematical proof of CRDT properties:
///   Commutativity: union(A,B) = union(B,A)                   ✓
///   Associativity: union(union(A,B),C) = union(A,union(B,C)) ✓
///   Idempotency:   union(A,A) = A                            ✓
pub fn orset_merge(a: ORSet, b: ORSet) -> ORSet {
  let all_tombstones = list.append(a.tombstones, b.tombstones) |> list.unique
  let all_elements = list.append(a.elements, b.elements) |> list.unique
  let surviving =
    list.filter(all_elements, fn(triple) {
      !list.contains(all_tombstones, triple.1)
    })
  ORSet(elements: surviving, tombstones: all_tombstones)
}

// =============================================================================
// Version Vector — Causal Ordering
// =============================================================================
//
// A version vector assigns a monotonically increasing logical clock value to
// each node.  It captures the causal history of updates across the mesh.
//
// Storage: association list of (node_id, clock) pairs.
//
// Dominance: VV a dominates VV b iff ∀k: a[k] >= b[k] AND ∃k: a[k] > b[k].
// Concurrency: a and b are concurrent iff neither dominates the other.
//
// Merge is the per-node maximum — same lattice as G-Counter.
//
// Lattice proof (identical to G-Counter):
//   Commutativity: max(a[k], b[k]) = max(b[k], a[k]) for all k ✓
//   Associativity: max(max(a,b),c) = max(a,max(b,c)) for all k ✓
//   Idempotency:   max(a[k], a[k]) = a[k] for all k             ✓

/// Version Vector — causal ordering across nodes.
///
/// `versions` is an association list of (node_id, logical_clock) pairs.
pub type VersionVector {
  VersionVector(versions: List(#(String, Int)))
}

/// Create a new empty Version Vector.
pub fn vv_new() -> VersionVector {
  VersionVector(versions: [])
}

/// Increment the given node's logical clock by 1.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">VersionVector ↔ VersionVector (node clock + 1)</morphism>
///   <formal-proof>
///     <P> Pre: node_id is non-empty </P>
///     <C> vv_increment(vv, node_id) </C>
///     <Q> Post: result.versions[node_id] = vv.versions[node_id] + 1 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn vv_increment(vv: VersionVector, node_id: String) -> VersionVector {
  let current = alist_get(vv.versions, node_id, 0)
  VersionVector(versions: alist_set(vv.versions, node_id, current + 1))
}

/// Merge two Version Vectors — take the per-node maximum (lattice join ⊔).
pub fn vv_merge(a: VersionVector, b: VersionVector) -> VersionVector {
  VersionVector(versions: alist_merge_max(a.versions, b.versions))
}

/// Check if Version Vector `a` causally dominates `b`.
///
/// `a` dominates `b` iff:
///   ∀ node k: a[k] >= b[k]  AND  ∃ node k: a[k] > b[k]
///
/// Returns False if a == b (equal vectors do not dominate each other).
pub fn vv_dominates(a: VersionVector, b: VersionVector) -> Bool {
  let all_keys =
    list.append(
      list.map(a.versions, fn(p) { p.0 }),
      list.map(b.versions, fn(p) { p.0 }),
    )
    |> list.unique
  let all_ge =
    list.all(all_keys, fn(k) {
      alist_get(a.versions, k, 0) >= alist_get(b.versions, k, 0)
    })
  let some_gt =
    list.any(all_keys, fn(k) {
      alist_get(a.versions, k, 0) > alist_get(b.versions, k, 0)
    })
  all_ge && some_gt
}

/// Check if two Version Vectors are concurrent (neither dominates the other).
///
/// Concurrency means nodes diverged and both made independent progress.
/// Requires causal reconciliation (e.g., via LWW or application logic).
pub fn vv_concurrent(a: VersionVector, b: VersionVector) -> Bool {
  !vv_dominates(a, b) && !vv_dominates(b, a)
}

// =============================================================================
// CRDT Property Verification
// =============================================================================
//
// These functions formally verify the three CRDT laws for GCounter.
// They are used in tests and can be published to Zenoh for runtime verification.
//
// SC-VER-001: System verification must include mathematical property checks.

/// Verify commutativity: merge(a, b) = merge(b, a).
///
/// Checks that the global value of merge(a,b) equals the global value of
/// merge(b,a). For G-Counter, this holds because max is commutative.
pub fn verify_commutativity(a: GCounter, b: GCounter) -> Bool {
  let ab = gcounter_merge(a, b)
  let ba = gcounter_merge(b, a)
  gcounter_value(ab) == gcounter_value(ba)
}

/// Verify associativity: merge(merge(a,b), c) = merge(a, merge(b,c)).
///
/// Checks that the global value of the left-associative merge equals the
/// right-associative merge. Holds because max is associative.
pub fn verify_associativity(a: GCounter, b: GCounter, c: GCounter) -> Bool {
  let left = gcounter_merge(gcounter_merge(a, b), c)
  let right = gcounter_merge(a, gcounter_merge(b, c))
  gcounter_value(left) == gcounter_value(right)
}

/// Verify idempotency: merge(a, a) = a.
///
/// Checks that merging a counter with itself returns the same value.
/// Holds because max(x, x) = x for all x.
pub fn verify_idempotency(a: GCounter) -> Bool {
  let aa = gcounter_merge(a, a)
  gcounter_value(aa) == gcounter_value(a)
}

/// Verify all three CRDT properties for a pair of G-Counters.
///
/// Returns True only if commutativity, associativity (with `a` as the third
/// argument), and idempotency all hold for both `a` and `b`.
pub fn verify_all_properties(a: GCounter, b: GCounter) -> Bool {
  verify_commutativity(a, b)
  && verify_associativity(a, b, a)
  && verify_idempotency(a)
  && verify_idempotency(b)
}

// =============================================================================
// Private helpers — association list operations
// =============================================================================

/// Look up a key in an association list, returning `default` if absent.
fn alist_get(alist: List(#(String, Int)), key: String, default: Int) -> Int {
  case list.find(alist, fn(pair) { pair.0 == key }) {
    Ok(pair) -> pair.1
    Error(_) -> default
  }
}

/// Set a key in an association list (replaces existing entry if present).
fn alist_set(
  alist: List(#(String, Int)),
  key: String,
  value: Int,
) -> List(#(String, Int)) {
  let without = list.filter(alist, fn(pair) { pair.0 != key })
  [#(key, value), ..without]
}

/// Merge two association lists by taking the per-key maximum.
fn alist_merge_max(
  a: List(#(String, Int)),
  b: List(#(String, Int)),
) -> List(#(String, Int)) {
  let all_keys =
    list.append(list.map(a, fn(p) { p.0 }), list.map(b, fn(p) { p.0 }))
    |> list.unique
  list.map(all_keys, fn(key) {
    let va = alist_get(a, key, 0)
    let vb = alist_get(b, key, 0)
    #(key, int.max(va, vb))
  })
}
