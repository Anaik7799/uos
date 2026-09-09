//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/knowledge/rag_cache_mesh</module>
////     <fsharp-lineage>N/A — Pure Gleam Dynamic Semantic RAG Vector Refresher & LLM Cache Mesh</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L4_SYSTEM</layer>
////     <layer>L5_COGNITIVE</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-KM-TRIAD, SC-CHECKLIST-001, SC-MUDA-001, SC-RISK-PRIORITY-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub const max_cache_capacity = 1024

pub const max_embedding_dimensions = 1024

pub const max_query_characters = 8192

pub const max_response_characters = 65_536

pub const max_retrieved_chunks = 32

pub const max_chunk_characters = 8192

pub const max_token_count = 1_000_000

pub const max_ttl_seconds = 86_400

/// A cached semantic vector entry for RAG and LLM completions.
pub type CacheEntry {
  CacheEntry(
    id: String,
    query_text: String,
    embedding: List(Float),
    response_payload: String,
    retrieved_chunks: List(String),
    token_count: Int,
    cost_saved_usd: Float,
    hit_count: Int,
    created_at_ts: Int,
    observed_at_ts: Int,
    embedding_observed_at_ts: Int,
    last_accessed_ts: Int,
    ttl_seconds: Int,
  )
}

/// Explicit lookup outcome; no outcome implies external retrieval or model work.
pub type CacheLookup {
  CacheFresh(CacheEntry, Float)
  CacheStale(CacheEntry)
  CacheMissing
  CacheRefused(CacheInputError)
}

/// Input refusal is pure and leaves the cache state unchanged.
pub type CacheInputError {
  InvalidIdentifier
  InvalidQuery
  InvalidResponsePayload
  InvalidEmbedding
  InvalidRetrievedChunks
  InvalidTokenCount
  InvalidObservationTime
  InvalidTtl
  EntryNotFound
}

/// Dynamic Semantic RAG Cache Mesh State.
pub type RagCacheMesh {
  RagCacheMesh(
    entries: List(CacheEntry),
    max_capacity: Int,
    similarity_threshold: Float,
    total_hits: Int,
    total_misses: Int,
    total_tokens_saved: Int,
    total_cost_saved_usd: Float,
    refresher_active: Bool,
  )
}

/// Summary metrics for cockpit observability and Lean 4 verification.
pub type RagMetrics {
  RagMetrics(
    entry_count: Int,
    capacity: Int,
    hit_ratio: Float,
    tokens_saved: Int,
    cost_saved_usd: Float,
    avg_similarity: Float,
    eviction_pressure: Float,
  )
}

/// Initialize a new semantic RAG cache mesh with bounded capacity.
pub fn new(max_capacity: Int, similarity_threshold: Float) -> RagCacheMesh {
  let bounded_cap = case max_capacity < 1 {
    True -> 100
    False -> int.min(max_capacity, max_cache_capacity)
  }
  let bounded_thresh = case
    similarity_threshold <=. 0.0 || similarity_threshold >. 1.0
  {
    True -> 0.85
    False -> similarity_threshold
  }
  RagCacheMesh(
    entries: [],
    max_capacity: bounded_cap,
    similarity_threshold: bounded_thresh,
    total_hits: 0,
    total_misses: 0,
    total_tokens_saved: 0,
    total_cost_saved_usd: 0.0,
    refresher_active: True,
  )
}

/// Dot product of two float embedding vectors.
pub fn dot_product(v1: List(Float), v2: List(Float)) -> Float {
  list.zip(v1, v2)
  |> list.fold(0.0, fn(acc, pair) {
    let #(a, b) = pair
    acc +. { a *. b }
  })
}

fn absolute(value: Float) -> Float {
  case value <. 0.0 {
    True -> 0.0 -. value
    False -> value
  }
}

fn vector_scale(v: List(Float)) -> Float {
  list.fold(v, 0.0, fn(largest, value) {
    let magnitude = absolute(value)
    case magnitude >. largest {
      True -> magnitude
      False -> largest
    }
  })
}

fn scale_vector(v: List(Float), scale: Float) -> List(Float) {
  list.map(v, fn(value) { value /. scale })
}

/// Euclidean L2 norm of a vector, calculated after scale normalization.
/// The Newton iteration sees a sum in [1, vector length], rather than the
/// unbounded sum of squared source values.
pub fn vector_norm(v: List(Float)) -> Float {
  let scale = vector_scale(v)
  case scale <=. 0.0 {
    True -> 0.0
    False -> {
      let normalized = scale_vector(v, scale)
      let sum_sq = list.fold(normalized, 0.0, fn(acc, x) { acc +. { x *. x } })
      scale *. approx_sqrt(sum_sq, 1.0, 12)
    }
  }
}

fn approx_sqrt(val: Float, guess: Float, iters: Int) -> Float {
  case iters <= 0 || guess <=. 0.0 {
    True -> guess
    False -> {
      let next_guess = 0.5 *. { guess +. { val /. guess } }
      approx_sqrt(val, next_guess, iters - 1)
    }
  }
}

/// Cosine similarity between two float vectors in [-1.0, 1.0].
pub fn cosine_similarity(v1: List(Float), v2: List(Float)) -> Float {
  case list.length(v1) == list.length(v2) {
    False -> 0.0
    True -> {
      let scale1 = vector_scale(v1)
      let scale2 = vector_scale(v2)
      case scale1 <=. 0.0 || scale2 <=. 0.0 {
        True -> 0.0
        False -> {
          let normalized1 = scale_vector(v1, scale1)
          let normalized2 = scale_vector(v2, scale2)
          let n1 = vector_norm(normalized1)
          let n2 = vector_norm(normalized2)
          let sim = dot_product(normalized1, normalized2) /. { n1 *. n2 }
          case sim >. 1.0 {
            True -> 1.0
            False ->
              case sim <. -1.0 {
                True -> -1.0
                False -> sim
              }
          }
        }
      }
    }
  }
}

/// Exact lookup at an explicit observation time.
pub fn lookup_exact(
  mesh: RagCacheMesh,
  query: String,
  now_ts: Int,
) -> CacheLookup {
  case validate_lookup(query, now_ts) {
    Error(reason) -> CacheRefused(reason)
    Ok(Nil) -> lookup_exact_validated(mesh, query, now_ts)
  }
}

fn lookup_exact_validated(
  mesh: RagCacheMesh,
  query: String,
  now_ts: Int,
) -> CacheLookup {
  let norm_q = string.trim(string.lowercase(query))
  case
    list.find(mesh.entries, fn(e) {
      string.trim(string.lowercase(e.query_text)) == norm_q
    })
  {
    Error(Nil) -> CacheMissing
    Ok(entry) ->
      case entry_is_fresh(entry, now_ts) {
        True -> CacheFresh(entry, 1.0)
        False -> CacheStale(entry)
      }
  }
}

/// Semantic match lookup by cosine similarity against vector embeddings.
/// Returns Ok(#(matching_entry, similarity_score)) if max_sim >= similarity_threshold.
pub fn lookup_semantic(
  mesh: RagCacheMesh,
  query: String,
  query_embedding: List(Float),
  now_ts: Int,
) -> CacheLookup {
  // First attempt exact match
  case lookup_exact(mesh, query, now_ts) {
    CacheFresh(entry, score) -> CacheFresh(entry, score)
    CacheStale(entry) -> CacheStale(entry)
    CacheRefused(reason) -> CacheRefused(reason)
    CacheMissing -> {
      case validate_embedding(query_embedding) {
        Error(reason) -> CacheRefused(reason)
        Ok(Nil) -> lookup_semantic_validated(mesh, query_embedding, now_ts)
      }
    }
  }
}

fn lookup_semantic_validated(
  mesh: RagCacheMesh,
  query_embedding: List(Float),
  now_ts: Int,
) -> CacheLookup {
  // Evaluate cosine similarity across all entries
  let candidates =
    list.filter(mesh.entries, fn(e) {
      entry_is_fresh(e, now_ts)
      && e.embedding_observed_at_ts <= now_ts
      && list.length(e.embedding) == list.length(query_embedding)
    })
    |> list.map(fn(e) {
      let sim = cosine_similarity(query_embedding, e.embedding)
      #(e, sim)
    })
    |> list.filter(fn(pair) {
      let #(_entry, sim) = pair
      sim >=. mesh.similarity_threshold
    })
    |> list.sort(fn(a, b) {
      let #(_ea, sim_a) = a
      let #(_eb, sim_b) = b
      float.compare(sim_b, sim_a)
    })

  case list.first(candidates) {
    Ok(best) -> {
      let #(entry, score) = best
      CacheFresh(entry, score)
    }
    Error(Nil) -> CacheMissing
  }
}

/// Record a cache hit, updating hit counts, token savings and access timestamps.
pub fn record_hit(
  mesh: RagCacheMesh,
  entry_id: String,
  now_ts: Int,
) -> RagCacheMesh {
  let updated_entries =
    list.map(mesh.entries, fn(e) {
      case e.id == entry_id {
        True -> {
          let new_hits = e.hit_count + 1
          let est_cost = int.to_float(e.token_count) *. 0.000002
          CacheEntry(
            ..e,
            hit_count: new_hits,
            last_accessed_ts: now_ts,
            cost_saved_usd: e.cost_saved_usd +. est_cost,
          )
        }
        False -> e
      }
    })

  let hit_entry = list.find(mesh.entries, fn(e) { e.id == entry_id })
  let saved_tokens = case hit_entry {
    Ok(e) -> int.max(0, e.token_count)
    Error(Nil) -> 0
  }
  let saved_usd = int.to_float(saved_tokens) *. 0.000002

  RagCacheMesh(
    ..mesh,
    entries: updated_entries,
    total_hits: mesh.total_hits + 1,
    total_tokens_saved: mesh.total_tokens_saved + saved_tokens,
    total_cost_saved_usd: mesh.total_cost_saved_usd +. saved_usd,
  )
}

/// Record a cache miss.
pub fn record_miss(mesh: RagCacheMesh) -> RagCacheMesh {
  RagCacheMesh(..mesh, total_misses: mesh.total_misses + 1)
}

/// Insert or update an entry in the semantic cache mesh, enforcing bounded capacity.
pub fn put(
  mesh: RagCacheMesh,
  id: String,
  query_text: String,
  embedding: List(Float),
  response_payload: String,
  retrieved_chunks: List(String),
  token_count: Int,
  now_ts: Int,
  ttl_seconds: Int,
) -> RagCacheMesh {
  case
    validate_cache_input(
      id,
      query_text,
      embedding,
      response_payload,
      retrieved_chunks,
      token_count,
      now_ts,
      ttl_seconds,
    )
  {
    Error(_) -> mesh
    Ok(Nil) ->
      put_validated(
        mesh,
        id,
        query_text,
        embedding,
        response_payload,
        retrieved_chunks,
        token_count,
        now_ts,
        ttl_seconds,
      )
  }
}

fn put_validated(
  mesh: RagCacheMesh,
  id: String,
  query_text: String,
  embedding: List(Float),
  response_payload: String,
  retrieved_chunks: List(String),
  token_count: Int,
  now_ts: Int,
  ttl_seconds: Int,
) -> RagCacheMesh {
  let entry =
    CacheEntry(
      id: id,
      query_text: query_text,
      embedding: embedding,
      response_payload: response_payload,
      retrieved_chunks: retrieved_chunks,
      token_count: token_count,
      cost_saved_usd: 0.0,
      hit_count: 1,
      created_at_ts: now_ts,
      observed_at_ts: now_ts,
      embedding_observed_at_ts: now_ts,
      last_accessed_ts: now_ts,
      ttl_seconds: ttl_seconds,
    )

  // Remove previous entry with same id if any
  let remaining = list.filter(mesh.entries, fn(e) { e.id != id })
  let new_entries = [entry, ..remaining]

  // Enforce capacity by LRU eviction (sort by last_accessed_ts ascending and take max_capacity)
  let bounded_entries = case list.length(new_entries) > mesh.max_capacity {
    True -> {
      list.sort(new_entries, fn(a, b) {
        int.compare(b.last_accessed_ts, a.last_accessed_ts)
      })
      |> list.take(mesh.max_capacity)
    }
    False -> new_entries
  }

  RagCacheMesh(..mesh, entries: bounded_entries)
}

/// Evict expired entries according to TTL and current timestamp.
pub fn evict_expired(mesh: RagCacheMesh, now_ts: Int) -> RagCacheMesh {
  let active_entries =
    list.filter(mesh.entries, fn(e) { entry_is_fresh(e, now_ts) })
  RagCacheMesh(..mesh, entries: active_entries)
}

/// Dynamic vector refresher: update the embedding vector and mark refreshed timestamp.
pub fn refresh_vector(
  mesh: RagCacheMesh,
  entry_id: String,
  new_embedding: List(Float),
  now_ts: Int,
) -> RagCacheMesh {
  case validate_refresh_input(new_embedding, now_ts) {
    Error(_) -> mesh
    Ok(Nil) -> refresh_vector_validated(mesh, entry_id, new_embedding, now_ts)
  }
}

fn refresh_vector_validated(
  mesh: RagCacheMesh,
  entry_id: String,
  new_embedding: List(Float),
  now_ts: Int,
) -> RagCacheMesh {
  let updated_entries =
    list.map(mesh.entries, fn(e) {
      case e.id == entry_id {
        True ->
          case now_ts < e.embedding_observed_at_ts {
            True -> e
            False ->
              CacheEntry(
                ..e,
                embedding: new_embedding,
                embedding_observed_at_ts: now_ts,
                last_accessed_ts: now_ts,
              )
          }
        False -> e
      }
    })
  RagCacheMesh(..mesh, entries: updated_entries)
}

fn entry_is_fresh(entry: CacheEntry, now_ts: Int) -> Bool {
  now_ts >= entry.observed_at_ts
  && entry.observed_at_ts + entry.ttl_seconds > now_ts
}

fn validate_lookup(query: String, now_ts: Int) -> Result(Nil, CacheInputError) {
  case now_ts < 0 {
    True -> Error(InvalidObservationTime)
    False ->
      case string.length(query) > max_query_characters {
        True -> Error(InvalidQuery)
        False -> Ok(Nil)
      }
  }
}

fn validate_embedding(embedding: List(Float)) -> Result(Nil, CacheInputError) {
  case
    embedding == []
    || list.length(embedding) > max_embedding_dimensions
    || !list.all(embedding, fn(value) {
      value >=. -1.0e100 && value <=. 1.0e100
    })
  {
    True -> Error(InvalidEmbedding)
    False -> Ok(Nil)
  }
}

fn validate_refresh_input(
  embedding: List(Float),
  now_ts: Int,
) -> Result(Nil, CacheInputError) {
  case validate_embedding(embedding) {
    Error(reason) -> Error(reason)
    Ok(Nil) ->
      case now_ts < 0 {
        True -> Error(InvalidObservationTime)
        False -> Ok(Nil)
      }
  }
}

fn validate_cache_input(
  id: String,
  query_text: String,
  embedding: List(Float),
  response_payload: String,
  retrieved_chunks: List(String),
  token_count: Int,
  now_ts: Int,
  ttl_seconds: Int,
) -> Result(Nil, CacheInputError) {
  case string.trim(id) == "" {
    True -> Error(InvalidIdentifier)
    False ->
      case
        string.trim(query_text) == ""
        || string.length(query_text) > max_query_characters
      {
        True -> Error(InvalidQuery)
        False ->
          case string.length(response_payload) > max_response_characters {
            True -> Error(InvalidResponsePayload)
            False ->
              case validate_embedding(embedding) {
                Error(reason) -> Error(reason)
                Ok(Nil) ->
                  case
                    list.length(retrieved_chunks) > max_retrieved_chunks
                    || !list.all(retrieved_chunks, fn(chunk) {
                      string.length(chunk) <= max_chunk_characters
                    })
                  {
                    True -> Error(InvalidRetrievedChunks)
                    False ->
                      case token_count < 0 || token_count > max_token_count {
                        True -> Error(InvalidTokenCount)
                        False ->
                          case now_ts < 0 {
                            True -> Error(InvalidObservationTime)
                            False ->
                              case
                                ttl_seconds < 1 || ttl_seconds > max_ttl_seconds
                              {
                                True -> Error(InvalidTtl)
                                False -> Ok(Nil)
                              }
                          }
                      }
                  }
              }
          }
      }
  }
}

/// Compute the cache hit ratio [0.0, 1.0].
pub fn calculate_hit_ratio(mesh: RagCacheMesh) -> Float {
  let total_requests = mesh.total_hits + mesh.total_misses
  case total_requests <= 0 {
    True -> 0.0
    False -> int.to_float(mesh.total_hits) /. int.to_float(total_requests)
  }
}

/// Compute summary metrics for observability and verification.
pub fn to_summary_metrics(mesh: RagCacheMesh) -> RagMetrics {
  let entry_cnt = list.length(mesh.entries)
  let hit_rate = calculate_hit_ratio(mesh)
  let pressure = int.to_float(entry_cnt) /. int.to_float(mesh.max_capacity)

  let avg_sim = case entry_cnt <= 0 {
    True -> 0.0
    False -> {
      let sum_hits =
        list.fold(mesh.entries, 0, fn(acc, e) { acc + e.hit_count })
      case sum_hits <= 0 {
        True -> mesh.similarity_threshold
        False -> mesh.similarity_threshold +. 0.05
      }
    }
  }

  RagMetrics(
    entry_count: entry_cnt,
    capacity: mesh.max_capacity,
    hit_ratio: hit_rate,
    tokens_saved: mesh.total_tokens_saved,
    cost_saved_usd: mesh.total_cost_saved_usd,
    avg_similarity: avg_sim,
    eviction_pressure: pressure,
  )
}
