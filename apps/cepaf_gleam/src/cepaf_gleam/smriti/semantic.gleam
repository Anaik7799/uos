// STAMP: SC-SMRITI-002, SC-GLM-CORE-002
// AOR: AOR-SMRITI-002, AOR-GLM-005
// Criticality: Level 2 (HIGH) - Smriti Semantic Search
//
// Vector embedding generation, storage, and similarity search
// for semantic knowledge retrieval in the Smriti subsystem.
// Includes pure vector math operations for cosine distance,
// dot product, and embedding normalization.

import gleam/float
import gleam/json
import gleam/list
import gleam/order
import gleam/result

// =============================================================================
// Types
// =============================================================================

pub type Embedding {
  Embedding(vector: List(Float), dimension: Int)
}

pub type SimilarityResult {
  SimilarityResult(id: String, score: Float, entry: String)
}

// =============================================================================
// FFI Stubs
// =============================================================================

pub fn generate_embedding(text: String) -> Result(Embedding, String) {
  let _ = text
  panic as "NYI: requires LLM API (SC-SMRITI-002)"
}

pub fn store_embedding(id: String, embedding: Embedding) -> Result(Nil, String) {
  let _ = id
  let _ = embedding
  panic as "NYI: requires vector DB (SC-SMRITI-002)"
}

pub fn search_similar(
  query_embedding: Embedding,
  top_k: Int,
) -> Result(List(SimilarityResult), String) {
  let _ = query_embedding
  let _ = top_k
  panic as "NYI: requires vector DB (SC-SMRITI-002)"
}

// =============================================================================
// Pure Helper Functions
// =============================================================================

/// Compute cosine similarity between two vectors.
/// Returns Error for zero-magnitude vectors.
pub fn cosine_similarity(
  a: List(Float),
  b: List(Float),
) -> Result(Float, String) {
  let mag_a = magnitude(a)
  let mag_b = magnitude(b)
  let denom = float.multiply(mag_a, mag_b)
  case float.compare(denom, 0.0) {
    order.Gt -> {
      let dot = dot_product(a, b)
      float.divide(dot, denom)
      |> result.map_error(fn(_) {
        "Cannot calculate similarity with zero-magnitude vector"
      })
    }
    _ -> Error("Cannot calculate similarity with zero-magnitude vector")
  }
}

/// Compute dot product of two vectors.
pub fn dot_product(a: List(Float), b: List(Float)) -> Float {
  list.zip(a, b)
  |> list.fold(0.0, fn(acc, pair) {
    let #(x, y) = pair
    float.add(acc, float.multiply(x, y))
  })
}

/// Normalize a vector to unit length.
/// Returns the original vector for zero-magnitude vectors.
pub fn normalize(v: List(Float)) -> List(Float) {
  let mag = magnitude(v)
  case float.compare(mag, 0.0) {
    order.Gt ->
      list.map(v, fn(x) {
        float.divide(x, mag)
        |> result.unwrap(0.0)
      })
    _ -> v
  }
}

pub fn embedding_to_json(e: Embedding) -> json.Json {
  json.object([
    #("vector", json.array(e.vector, json.float)),
    #("dimension", json.int(e.dimension)),
  ])
}

// =============================================================================
// Internal Helpers
// =============================================================================

/// Compute the magnitude (L2 norm) of a vector.
pub fn magnitude(v: List(Float)) -> Float {
  let sum_sq =
    list.fold(v, 0.0, fn(acc, x) { float.add(acc, float.multiply(x, x)) })
  sqrt_approx(sum_sq)
}

/// Euclidean distance between two vectors.
pub fn euclidean_distance(a: List(Float), b: List(Float)) -> Float {
  let sum_sq =
    list.zip(a, b)
    |> list.fold(0.0, fn(acc, pair) {
      let #(x, y) = pair
      let diff = float.subtract(x, y)
      float.add(acc, float.multiply(diff, diff))
    })
  sqrt_approx(sum_sq)
}

fn sqrt_approx(x: Float) -> Float {
  case float.compare(x, 0.0) {
    order.Gt -> newton_sqrt(x, float.divide(x, 2.0) |> result.unwrap(1.0), 0)
    _ -> 0.0
  }
}

fn newton_sqrt(x: Float, guess: Float, iterations: Int) -> Float {
  case iterations >= 50 {
    True -> guess
    False -> {
      let next =
        float.divide(
          float.add(guess, float.divide(x, guess) |> result.unwrap(0.0)),
          2.0,
        )
        |> result.unwrap(guess)
      let diff = float.absolute_value(float.subtract(next, guess))
      case float.compare(diff, 0.0000001) {
        order.Lt -> next
        _ -> newton_sqrt(x, next, iterations + 1)
      }
    }
  }
}
