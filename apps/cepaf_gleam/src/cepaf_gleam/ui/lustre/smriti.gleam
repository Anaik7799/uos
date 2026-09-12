/// Lustre component for Smriti Knowledge plane (SC-GLM-UI-001).
/// Tracks catalog entries, embeddings, search queries, and similarity.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
pub type SmritiModel {
  SmritiModel(
    catalog_entries: Int,
    embeddings_stored: Int,
    search_queries: Int,
    avg_similarity: Float,
    // P2-2: Semantic cache stats
    cache_entries: Int,
    cache_hit_rate: Float,
    cache_total_hits: Int,
    cache_total_misses: Int,
  )
}

pub type SmritiMsg {
  EntryIngested
  SearchPerformed(Float)
  EmbeddingStored
  RefreshSmriti
  // P2-2: Cache stats update
  CacheStatsUpdated(entries: Int, hit_rate: Float, hits: Int, misses: Int)
}

pub fn init() -> SmritiModel {
  SmritiModel(
    catalog_entries: 0,
    embeddings_stored: 0,
    search_queries: 0,
    avg_similarity: 0.0,
    cache_entries: 0,
    cache_hit_rate: 0.0,
    cache_total_hits: 0,
    cache_total_misses: 0,
  )
}

pub fn update(model: SmritiModel, msg: SmritiMsg) -> SmritiModel {
  case msg {
    EntryIngested ->
      SmritiModel(..model, catalog_entries: model.catalog_entries + 1)
    SearchPerformed(similarity) ->
      SmritiModel(
        ..model,
        search_queries: model.search_queries + 1,
        avg_similarity: similarity,
      )
    EmbeddingStored ->
      SmritiModel(..model, embeddings_stored: model.embeddings_stored + 1)
    RefreshSmriti -> model
    CacheStatsUpdated(entries, hit_rate, hits, misses) ->
      SmritiModel(..model, cache_entries: entries, cache_hit_rate: hit_rate,
        cache_total_hits: hits, cache_total_misses: misses)
  }
}

pub fn total_entries(model: SmritiModel) -> Int {
  model.catalog_entries
}

pub fn has_embeddings(model: SmritiModel) -> Bool {
  model.embeddings_stored > 0
}

// =============================================================================
// NIF-backed data loading (SC-WIRE-001: real ops data)
// =============================================================================

import cepaf_gleam/c3i/nif
import gleam/dynamic/decode
import gleam/json

/// Load real cache stats from NIF → Rust → SemanticCache table
pub fn load_cache_from_nif() -> #(Int, Float) {
  let raw = nif.cache_stats()
  let decoder = {
    use entries <- decode.field("entries", decode.int)
    use hit_rate <- decode.field("hit_rate", decode.float)
    decode.success(#(entries, hit_rate))
  }
  case json.parse(raw, decoder) {
    Ok(r) -> r
    Error(_) -> #(0, 0.0)
  }
}
