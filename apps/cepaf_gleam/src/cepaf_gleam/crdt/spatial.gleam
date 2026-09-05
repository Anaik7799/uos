//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/crdt/spatial</module>
////     <fsharp-lineage>None — novel Gleam implementation</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <mesh-domain>Spatial CRDT for canvas/hologram convergence</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-BIO-EVO-001, SC-HA-001, SC-MOKSHA-006</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="constructive">
////       Conflict-free spatial state: LWW per element, union of tombstones.
////       Two replicas always converge to identical state after merge.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// SPATIAL CRDT — Conflict-Free Replicated Spatial Data Type
//// स्थानिक सीआरडीटी — संघर्ष-मुक्त प्रतिकृत स्थानिक डेटा
////
//// Extends CRDT foundation with 3D spatial elements, LWW merge semantics,
//// spatial queries (radius, bounding box), and convergence verification.
////
//// STAMP: SC-BIO-EVO-001, SC-HA-001, SC-MOKSHA-006

import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// 3D vector.
pub type Vec3 {
  Vec3(x: Float, y: Float, z: Float)
}

/// A spatial element in the CRDT.
pub type SpatialElement {
  SpatialElement(
    id: String,
    position: Vec3,
    rotation: Vec3,
    scale: Vec3,
    timestamp: Int,
    node_id: String,
  )
}

/// The full spatial CRDT state.
pub type SpatialCRDT {
  SpatialCRDT(
    elements: List(SpatialElement),
    removed_ids: List(String),
    version: Int,
  )
}

/// Operations on the spatial CRDT.
pub type SpatialOp {
  Insert(element: SpatialElement)
  Move(id: String, new_position: Vec3)
  Remove(id: String)
  Transform(id: String, new_rotation: Vec3, new_scale: Vec3)
}

/// Create a zero vector.
pub fn vec3_zero() -> Vec3 {
  Vec3(0.0, 0.0, 0.0)
}

/// Create a vector.
pub fn vec3(x: Float, y: Float, z: Float) -> Vec3 {
  Vec3(x, y, z)
}

/// Create an empty spatial CRDT.
pub fn new() -> SpatialCRDT {
  SpatialCRDT(elements: [], removed_ids: [], version: 0)
}

/// Apply an operation to the CRDT with LWW semantics.
pub fn apply_op(
  crdt: SpatialCRDT,
  op: SpatialOp,
  timestamp: Int,
  node_id: String,
) -> SpatialCRDT {
  case op {
    Insert(elem) -> {
      let tagged =
        SpatialElement(..elem, timestamp: timestamp, node_id: node_id)
      let filtered = list.filter(crdt.elements, fn(e) { e.id != elem.id })
      SpatialCRDT(
        ..crdt,
        elements: [tagged, ..filtered],
        version: crdt.version + 1,
      )
    }
    Move(id, pos) -> {
      let updated =
        list.map(crdt.elements, fn(e) {
          case e.id == id {
            True ->
              SpatialElement(
                ..e,
                position: pos,
                timestamp: timestamp,
                node_id: node_id,
              )
            False -> e
          }
        })
      SpatialCRDT(..crdt, elements: updated, version: crdt.version + 1)
    }
    Remove(id) ->
      SpatialCRDT(
        elements: list.filter(crdt.elements, fn(e) { e.id != id }),
        removed_ids: [id, ..crdt.removed_ids],
        version: crdt.version + 1,
      )
    Transform(id, rot, scl) -> {
      let updated =
        list.map(crdt.elements, fn(e) {
          case e.id == id {
            True ->
              SpatialElement(
                ..e,
                rotation: rot,
                scale: scl,
                timestamp: timestamp,
                node_id: node_id,
              )
            False -> e
          }
        })
      SpatialCRDT(..crdt, elements: updated, version: crdt.version + 1)
    }
  }
}

/// Merge two CRDT replicas. LWW per element, union of tombstones.
pub fn merge(a: SpatialCRDT, b: SpatialCRDT) -> SpatialCRDT {
  let all_removed = list.append(a.removed_ids, b.removed_ids) |> dedup
  let all_elements = merge_elements(a.elements, b.elements)
  let alive =
    list.filter(all_elements, fn(e) { !list.contains(all_removed, e.id) })
  SpatialCRDT(
    elements: alive,
    removed_ids: all_removed,
    version: int.max(a.version, b.version) + 1,
  )
}

fn merge_elements(
  a: List(SpatialElement),
  b: List(SpatialElement),
) -> List(SpatialElement) {
  let b_ids = list.map(b, fn(e) { e.id })
  let a_only = list.filter(a, fn(e) { !list.contains(b_ids, e.id) })
  let merged_shared =
    list.filter_map(a, fn(ea) {
      case list.find(b, fn(eb) { eb.id == ea.id }) {
        Ok(eb) ->
          case ea.timestamp >= eb.timestamp {
            True -> Ok(ea)
            False -> Ok(eb)
          }
        Error(_) -> Error(Nil)
      }
    })
  let a_ids = list.map(a, fn(e) { e.id })
  let b_only = list.filter(b, fn(e) { !list.contains(a_ids, e.id) })
  list.flatten([a_only, merged_shared, b_only])
}

/// Count elements.
pub fn element_count(crdt: SpatialCRDT) -> Int {
  list.length(crdt.elements)
}

/// Find element by ID.
pub fn find_element(
  crdt: SpatialCRDT,
  id: String,
) -> Result(SpatialElement, Nil) {
  list.find(crdt.elements, fn(e) { e.id == id })
}

/// Euclidean distance between two 3D points.
pub fn distance(a: Vec3, b: Vec3) -> Float {
  let dx = b.x -. a.x
  let dy = b.y -. a.y
  let dz = b.z -. a.z
  sqrt(dx *. dx +. dy *. dy +. dz *. dz)
}

/// Find all elements within radius of center.
pub fn elements_in_radius(
  crdt: SpatialCRDT,
  center: Vec3,
  radius: Float,
) -> List(SpatialElement) {
  list.filter(crdt.elements, fn(e) { distance(e.position, center) <=. radius })
}

/// Bounding box: (min_corner, max_corner).
pub fn bounding_box(crdt: SpatialCRDT) -> #(Vec3, Vec3) {
  case crdt.elements {
    [] -> #(vec3_zero(), vec3_zero())
    [first, ..rest] -> {
      let init = #(first.position, first.position)
      list.fold(rest, init, fn(acc, e) {
        let #(mn, mx) = acc
        #(
          Vec3(
            x: float.min(mn.x, e.position.x),
            y: float.min(mn.y, e.position.y),
            z: float.min(mn.z, e.position.z),
          ),
          Vec3(
            x: float.max(mx.x, e.position.x),
            y: float.max(mx.y, e.position.y),
            z: float.max(mx.z, e.position.z),
          ),
        )
      })
    }
  }
}

/// Check if two replicas have converged (same elements by id+timestamp).
pub fn converged(a: SpatialCRDT, b: SpatialCRDT) -> Bool {
  let a_sorted = list.sort(a.elements, fn(x, y) { string.compare(x.id, y.id) })
  let b_sorted = list.sort(b.elements, fn(x, y) { string.compare(x.id, y.id) })
  elements_equal(a_sorted, b_sorted)
}

fn elements_equal(a: List(SpatialElement), b: List(SpatialElement)) -> Bool {
  case a, b {
    [], [] -> True
    [ea, ..ra], [eb, ..rb] ->
      ea.id == eb.id && ea.timestamp == eb.timestamp && elements_equal(ra, rb)
    _, _ -> False
  }
}

/// Summary string.
pub fn summary(crdt: SpatialCRDT) -> String {
  "SpatialCRDT(elements="
  <> int.to_string(element_count(crdt))
  <> ", removed="
  <> int.to_string(list.length(crdt.removed_ids))
  <> ", version="
  <> int.to_string(crdt.version)
  <> ")"
}

// -- Helpers ------------------------------------------------------------------

fn sqrt(x: Float) -> Float {
  case x <=. 0.0 {
    True -> 0.0
    False -> newton_sqrt(x, x /. 2.0, 0)
  }
}

fn newton_sqrt(x: Float, guess: Float, iter: Int) -> Float {
  case iter >= 10 {
    True -> guess
    False -> {
      let next = { guess +. x /. guess } /. 2.0
      newton_sqrt(x, next, iter + 1)
    }
  }
}

fn dedup(items: List(String)) -> List(String) {
  do_dedup(items, [])
}

fn do_dedup(items: List(String), seen: List(String)) -> List(String) {
  case items {
    [] -> list.reverse(seen)
    [h, ..t] ->
      case list.contains(seen, h) {
        True -> do_dedup(t, seen)
        False -> do_dedup(t, [h, ..seen])
      }
  }
}
