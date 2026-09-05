// Smriti catalog and semantic test — SC-SMRITI-001, SC-SMRITI-002
// Tests catalog new_entry/matches_query and semantic cosine_similarity/normalize
// using verified public API from smriti/catalog.gleam and smriti/semantic.gleam

import cepaf_gleam/smriti/catalog.{CatalogQuery, matches_query, new_entry}
import cepaf_gleam/smriti/semantic.{
  Embedding, cosine_similarity, dot_product, euclidean_distance, magnitude,
  normalize,
}
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ── catalog.new_entry ─────────────────────────────────────────────────────────

pub fn new_entry_id_test() {
  let e = new_entry("e001", "Auth Module", "security", "JWT token validation")
  e.id |> should.equal("e001")
}

pub fn new_entry_name_test() {
  let e = new_entry("e002", "Zenoh Router", "mesh", "Core message bus")
  e.name |> should.equal("Zenoh Router")
}

pub fn new_entry_category_test() {
  let e = new_entry("e003", "OODA FSM", "cognitive", "State machine")
  e.category |> should.equal("cognitive")
}

pub fn new_entry_description_test() {
  let e = new_entry("e004", "NIF Bridge", "system", "Rust NIF integration")
  e.description |> should.equal("Rust NIF integration")
}

pub fn new_entry_empty_tags_test() {
  let e = new_entry("e005", "X", "y", "z")
  e.tags |> should.equal([])
}

pub fn new_entry_empty_created_at_test() {
  let e = new_entry("e006", "X", "y", "z")
  e.created_at |> should.equal("")
}

// ── catalog.matches_query ─────────────────────────────────────────────────────

pub fn matches_query_no_filter_test() {
  let e = new_entry("e1", "My Module", "code", "Some description")
  let q = CatalogQuery(category: None, tags: [], search_text: None, limit: 10)
  matches_query(e, q) |> should.equal(True)
}

pub fn matches_query_category_match_test() {
  let e = new_entry("e2", "Router", "mesh", "Zenoh mesh router")
  let q =
    CatalogQuery(category: Some("mesh"), tags: [], search_text: None, limit: 10)
  matches_query(e, q) |> should.equal(True)
}

pub fn matches_query_category_no_match_test() {
  let e = new_entry("e3", "Router", "mesh", "Zenoh mesh router")
  let q =
    CatalogQuery(
      category: Some("security"),
      tags: [],
      search_text: None,
      limit: 10,
    )
  matches_query(e, q) |> should.equal(False)
}

pub fn matches_query_text_match_name_test() {
  let e = new_entry("e4", "Zenoh Router", "mesh", "Message bus")
  let q =
    CatalogQuery(
      category: None,
      tags: [],
      search_text: Some("zenoh"),
      limit: 10,
    )
  matches_query(e, q) |> should.equal(True)
}

pub fn matches_query_text_match_description_test() {
  let e = new_entry("e5", "Module", "core", "Handles JWT authentication")
  let q =
    CatalogQuery(category: None, tags: [], search_text: Some("jwt"), limit: 10)
  matches_query(e, q) |> should.equal(True)
}

pub fn matches_query_text_no_match_test() {
  let e = new_entry("e6", "Logger", "observability", "OTEL exporter")
  let q =
    CatalogQuery(
      category: None,
      tags: [],
      search_text: Some("kubernetes"),
      limit: 10,
    )
  matches_query(e, q) |> should.equal(False)
}

pub fn matches_query_text_case_insensitive_test() {
  let e = new_entry("e7", "Cortex Engine", "cognitive", "OODA cycle")
  let q =
    CatalogQuery(
      category: None,
      tags: [],
      search_text: Some("CORTEX"),
      limit: 10,
    )
  matches_query(e, q) |> should.equal(True)
}

pub fn matches_query_empty_tags_always_match_test() {
  let e = new_entry("e8", "X", "y", "z")
  let q = CatalogQuery(category: None, tags: [], search_text: None, limit: 5)
  matches_query(e, q) |> should.equal(True)
}

pub fn matches_query_combined_filters_pass_test() {
  let e = new_entry("e9", "Auth NIF", "security", "Rust authentication NIF")
  let q =
    CatalogQuery(
      category: Some("security"),
      tags: [],
      search_text: Some("auth"),
      limit: 10,
    )
  matches_query(e, q) |> should.equal(True)
}

pub fn matches_query_combined_filters_fail_category_test() {
  let e = new_entry("e10", "Auth NIF", "security", "Rust authentication NIF")
  let q =
    CatalogQuery(
      category: Some("mesh"),
      tags: [],
      search_text: Some("auth"),
      limit: 10,
    )
  matches_query(e, q) |> should.equal(False)
}

// ── semantic.cosine_similarity ────────────────────────────────────────────────

pub fn cosine_similarity_identical_vectors_test() {
  let v = [1.0, 0.0, 0.0]
  case cosine_similarity(v, v) {
    Ok(s) -> {
      // cos(0) = 1.0
      should.be_true(s >. 0.99)
    }
    Error(_) -> should.fail()
  }
}

pub fn cosine_similarity_orthogonal_vectors_test() {
  let a = [1.0, 0.0]
  let b = [0.0, 1.0]
  case cosine_similarity(a, b) {
    Ok(s) -> {
      // cos(90°) = 0.0
      should.be_true(s <. 0.01 && s >. -0.01)
    }
    Error(_) -> should.fail()
  }
}

pub fn cosine_similarity_zero_vector_error_test() {
  let a = [0.0, 0.0]
  let b = [1.0, 0.0]
  case cosine_similarity(a, b) {
    Ok(_) -> should.fail()
    Error(_) -> should.be_true(True)
  }
}

pub fn cosine_similarity_opposite_vectors_test() {
  let a = [1.0, 0.0]
  let b = [-1.0, 0.0]
  case cosine_similarity(a, b) {
    Ok(s) -> {
      // cos(180°) = -1.0
      should.be_true(s <. -0.99)
    }
    Error(_) -> should.fail()
  }
}

// ── semantic.normalize ────────────────────────────────────────────────────────

pub fn normalize_unit_vector_test() {
  let v = [3.0, 4.0]
  let n = normalize(v)
  let mag = magnitude(n)
  // Magnitude of normalized vector should be ~1.0
  should.be_true(mag >. 0.99 && mag <. 1.01)
}

pub fn normalize_zero_vector_unchanged_test() {
  let v = [0.0, 0.0, 0.0]
  let n = normalize(v)
  n |> should.equal([0.0, 0.0, 0.0])
}

pub fn normalize_already_unit_test() {
  let v = [1.0, 0.0, 0.0]
  let n = normalize(v)
  let mag = magnitude(n)
  should.be_true(mag >. 0.99 && mag <. 1.01)
}

// ── semantic.dot_product ──────────────────────────────────────────────────────

pub fn dot_product_basic_test() {
  let a = [1.0, 2.0, 3.0]
  let b = [4.0, 5.0, 6.0]
  dot_product(a, b) |> should.equal(32.0)
}

pub fn dot_product_zero_test() {
  let a = [1.0, 0.0]
  let b = [0.0, 1.0]
  dot_product(a, b) |> should.equal(0.0)
}

pub fn dot_product_negative_test() {
  let a = [1.0, -1.0]
  let b = [1.0, 1.0]
  dot_product(a, b) |> should.equal(0.0)
}

// ── semantic.magnitude ────────────────────────────────────────────────────────

pub fn magnitude_pythagorean_test() {
  let v = [3.0, 4.0]
  let m = magnitude(v)
  // sqrt(9 + 16) = 5.0
  should.be_true(m >. 4.99 && m <. 5.01)
}

pub fn magnitude_zero_vector_test() {
  let v = [0.0, 0.0]
  magnitude(v) |> should.equal(0.0)
}

pub fn magnitude_unit_vector_test() {
  let v = [1.0, 0.0, 0.0]
  let m = magnitude(v)
  should.be_true(m >. 0.99 && m <. 1.01)
}

// ── semantic.euclidean_distance ───────────────────────────────────────────────

pub fn euclidean_distance_same_point_test() {
  let v = [1.0, 2.0, 3.0]
  euclidean_distance(v, v) |> should.equal(0.0)
}

pub fn euclidean_distance_unit_apart_test() {
  let a = [0.0, 0.0]
  let b = [3.0, 4.0]
  let d = euclidean_distance(a, b)
  should.be_true(d >. 4.99 && d <. 5.01)
}

// ── Embedding construction ────────────────────────────────────────────────────

pub fn embedding_vector_test() {
  let e = Embedding(vector: [0.1, 0.2, 0.3], dimension: 3)
  e.dimension |> should.equal(3)
  e.vector |> should.equal([0.1, 0.2, 0.3])
}
