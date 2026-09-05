// STAMP: SC-KNOW-001
// AOR: AOR-KNOW-001
// Criticality: Level 1 (CRITICAL) - Semantic Storage
//
// DuckDB Semantic Storage Wrapper and SPO/POS/OSP Indexing.

import cepaf_gleam/knowledge/semantic.{type RdfTerm, type Triple}
import gleam/dict.{type Dict}

/// Represents the semantic triple store.
pub type SemanticStore {
  SemanticStore(
    triples: List(Triple),
    // Simplified in-memory indexes for SPO, POS, OSP
    spo_index: Dict(String, Dict(String, List(String))),
    pos_index: Dict(String, Dict(String, List(String))),
    osp_index: Dict(String, Dict(String, List(String))),
  )
}

pub fn new_store() -> SemanticStore {
  SemanticStore(
    triples: [],
    spo_index: dict.new(),
    pos_index: dict.new(),
    osp_index: dict.new(),
  )
}

fn term_to_string(term: RdfTerm) -> String {
  case term {
    semantic.Iri(i) -> "<" <> i <> ">"
    semantic.Blank(b) -> "_:" <> b
    semantic.Literal(v, lang, datatype) ->
      "\"" <> v <> "\"@" <> lang <> "^^" <> datatype
  }
}

pub fn insert(store: SemanticStore, triple: Triple) -> SemanticStore {
  let s = term_to_string(triple.subject)
  let p = triple.predicate
  let o = term_to_string(triple.object)

  // Basic index update helper
  let update_index = fn(
    idx: Dict(String, Dict(String, List(String))),
    k1: String,
    k2: String,
    v: String,
  ) {
    let sub_idx = case dict.get(idx, k1) {
      Ok(sub) -> sub
      Error(_) -> dict.new()
    }
    let values = case dict.get(sub_idx, k2) {
      Ok(vals) -> [v, ..vals]
      Error(_) -> [v]
    }
    dict.insert(idx, k1, dict.insert(sub_idx, k2, values))
  }

  SemanticStore(
    triples: [triple, ..store.triples],
    spo_index: update_index(store.spo_index, s, p, o),
    pos_index: update_index(store.pos_index, p, o, s),
    osp_index: update_index(store.osp_index, o, s, p),
  )
}
