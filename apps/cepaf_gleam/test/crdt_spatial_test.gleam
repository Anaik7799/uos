/// Spatial CRDT Tests — C1-C8 Gold Standard
/// STAMP: SC-BIO-EVO-001, SC-HA-001, SC-MOKSHA-006
import cepaf_gleam/crdt/spatial
import gleam/list
import gleeunit/should

// C1: Structure
pub fn new_crdt_empty_test() {
  let c = spatial.new()
  spatial.element_count(c) |> should.equal(0)
}

pub fn vec3_creation_test() {
  let v = spatial.vec3(1.0, 2.0, 3.0)
  { v.x >. 0.99 } |> should.be_true()
}

// C2: Insert + Find
pub fn insert_element_test() {
  let elem =
    spatial.SpatialElement(
      "a",
      spatial.vec3(1.0, 0.0, 0.0),
      spatial.vec3_zero(),
      spatial.vec3(1.0, 1.0, 1.0),
      100,
      "node1",
    )
  let c = spatial.new() |> spatial.apply_op(spatial.Insert(elem), 100, "node1")
  spatial.element_count(c) |> should.equal(1)
}

pub fn find_element_test() {
  let elem =
    spatial.SpatialElement(
      "b",
      spatial.vec3(2.0, 3.0, 0.0),
      spatial.vec3_zero(),
      spatial.vec3(1.0, 1.0, 1.0),
      100,
      "n1",
    )
  let c = spatial.new() |> spatial.apply_op(spatial.Insert(elem), 100, "n1")
  let found = spatial.find_element(c, "b")
  case found {
    Ok(e) -> e.id |> should.equal("b")
    _ -> should.fail()
  }
}

// C3: Move + Transform
pub fn move_element_test() {
  let elem =
    spatial.SpatialElement(
      "m",
      spatial.vec3(0.0, 0.0, 0.0),
      spatial.vec3_zero(),
      spatial.vec3(1.0, 1.0, 1.0),
      100,
      "n1",
    )
  let c =
    spatial.new()
    |> spatial.apply_op(spatial.Insert(elem), 100, "n1")
    |> spatial.apply_op(
      spatial.Move("m", spatial.vec3(5.0, 5.0, 5.0)),
      200,
      "n1",
    )
  case spatial.find_element(c, "m") {
    Ok(e) -> { e.position.x >. 4.9 } |> should.be_true()
    _ -> should.fail()
  }
}

// C4: Remove
pub fn remove_element_test() {
  let elem =
    spatial.SpatialElement(
      "r",
      spatial.vec3(1.0, 0.0, 0.0),
      spatial.vec3_zero(),
      spatial.vec3(1.0, 1.0, 1.0),
      100,
      "n1",
    )
  let c =
    spatial.new()
    |> spatial.apply_op(spatial.Insert(elem), 100, "n1")
    |> spatial.apply_op(spatial.Remove("r"), 200, "n1")
  spatial.element_count(c) |> should.equal(0)
}

// C5: Distance
pub fn distance_test() {
  let d =
    spatial.distance(spatial.vec3(0.0, 0.0, 0.0), spatial.vec3(3.0, 4.0, 0.0))
  { d >. 4.99 && d <. 5.01 } |> should.be_true()
}

pub fn distance_zero_test() {
  spatial.distance(spatial.vec3_zero(), spatial.vec3_zero())
  |> should.equal(0.0)
}

// C6: Radius query
pub fn elements_in_radius_test() {
  let c =
    spatial.new()
    |> spatial.apply_op(
      spatial.Insert(spatial.SpatialElement(
        "near",
        spatial.vec3(1.0, 0.0, 0.0),
        spatial.vec3_zero(),
        spatial.vec3(1.0, 1.0, 1.0),
        100,
        "n1",
      )),
      100,
      "n1",
    )
    |> spatial.apply_op(
      spatial.Insert(spatial.SpatialElement(
        "far",
        spatial.vec3(100.0, 0.0, 0.0),
        spatial.vec3_zero(),
        spatial.vec3(1.0, 1.0, 1.0),
        100,
        "n1",
      )),
      100,
      "n1",
    )
  let nearby = spatial.elements_in_radius(c, spatial.vec3_zero(), 5.0)
  list.length(nearby) |> should.equal(1)
}

// C7: Merge + Convergence
pub fn merge_replicas_test() {
  let elem_a =
    spatial.SpatialElement(
      "x",
      spatial.vec3(1.0, 0.0, 0.0),
      spatial.vec3_zero(),
      spatial.vec3(1.0, 1.0, 1.0),
      100,
      "n1",
    )
  let elem_b =
    spatial.SpatialElement(
      "y",
      spatial.vec3(0.0, 1.0, 0.0),
      spatial.vec3_zero(),
      spatial.vec3(1.0, 1.0, 1.0),
      100,
      "n2",
    )
  let a = spatial.new() |> spatial.apply_op(spatial.Insert(elem_a), 100, "n1")
  let b = spatial.new() |> spatial.apply_op(spatial.Insert(elem_b), 100, "n2")
  let merged = spatial.merge(a, b)
  spatial.element_count(merged) |> should.equal(2)
}

pub fn merge_lww_test() {
  let old =
    spatial.SpatialElement(
      "z",
      spatial.vec3(1.0, 0.0, 0.0),
      spatial.vec3_zero(),
      spatial.vec3(1.0, 1.0, 1.0),
      100,
      "n1",
    )
  let newer =
    spatial.SpatialElement(
      "z",
      spatial.vec3(9.0, 0.0, 0.0),
      spatial.vec3_zero(),
      spatial.vec3(1.0, 1.0, 1.0),
      200,
      "n2",
    )
  let a = spatial.new() |> spatial.apply_op(spatial.Insert(old), 100, "n1")
  let b = spatial.new() |> spatial.apply_op(spatial.Insert(newer), 200, "n2")
  let merged = spatial.merge(a, b)
  case spatial.find_element(merged, "z") {
    Ok(e) -> { e.position.x >. 8.9 } |> should.be_true()
    _ -> should.fail()
  }
}

pub fn convergence_test() {
  let elem =
    spatial.SpatialElement(
      "c",
      spatial.vec3(1.0, 2.0, 3.0),
      spatial.vec3_zero(),
      spatial.vec3(1.0, 1.0, 1.0),
      100,
      "n1",
    )
  let a = spatial.new() |> spatial.apply_op(spatial.Insert(elem), 100, "n1")
  let b = spatial.new() |> spatial.apply_op(spatial.Insert(elem), 100, "n1")
  spatial.converged(a, b) |> should.be_true()
}

// C8: Bounding box + Summary
pub fn bounding_box_test() {
  let c =
    spatial.new()
    |> spatial.apply_op(
      spatial.Insert(spatial.SpatialElement(
        "p1",
        spatial.vec3(-1.0, -2.0, 0.0),
        spatial.vec3_zero(),
        spatial.vec3(1.0, 1.0, 1.0),
        100,
        "n1",
      )),
      100,
      "n1",
    )
    |> spatial.apply_op(
      spatial.Insert(spatial.SpatialElement(
        "p2",
        spatial.vec3(3.0, 4.0, 5.0),
        spatial.vec3_zero(),
        spatial.vec3(1.0, 1.0, 1.0),
        100,
        "n1",
      )),
      100,
      "n1",
    )
  let #(mn, mx) = spatial.bounding_box(c)
  { mn.x <. -0.9 } |> should.be_true()
  { mx.x >. 2.9 } |> should.be_true()
}

pub fn summary_nonempty_test() {
  let s = spatial.summary(spatial.new())
  { s != "" } |> should.be_true()
}
