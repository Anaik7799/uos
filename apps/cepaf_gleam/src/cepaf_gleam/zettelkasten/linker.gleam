//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/zettelkasten/linker</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SMRITI-141, SC-IKE-003</stamp-controls></compliance>
//// </c3i-module>
////
//// Auto-linker for Zettelkasten knowledge graph.
//// Extracts SC-* references, module names, file paths → creates edges.
//// STAMP: SC-SMRITI-141 (lineage chain), SC-IKE-003 (drift detection)

import cepaf_gleam/zettelkasten/types.{
  type HolonEdge, Backlink, Code, HolonEdge, Wiki,
}
import gleam/list
import gleam/string

/// Extract SC-* constraint references from content.
pub fn extract_stamp_refs(content: String) -> List(String) {
  content
  |> string.split(" ")
  |> list.filter_map(fn(word) {
    let cleaned = string.trim(word)
    case string.starts_with(cleaned, "SC-") {
      True -> {
        // Extract SC-XXX-NNN pattern
        let parts = string.split(cleaned, "-")
        case list.length(parts) >= 3 {
          True -> Ok(clean_stamp_ref(cleaned))
          False -> Error(Nil)
        }
      }
      False -> Error(Nil)
    }
  })
  |> list.unique
}

/// Extract module references from content (cepaf_gleam/path/to/module patterns).
pub fn extract_module_refs(content: String) -> List(String) {
  content
  |> string.split(" ")
  |> list.filter_map(fn(word) {
    let cleaned = string.trim(word)
    case string.contains(cleaned, "/") && string.contains(cleaned, ".gleam") {
      True -> Ok(cleaned)
      False ->
        case string.starts_with(cleaned, "cepaf_gleam/") {
          True -> Ok(cleaned)
          False -> Error(Nil)
        }
    }
  })
  |> list.unique
}

/// Extract file path references from content.
pub fn extract_file_refs(content: String) -> List(String) {
  content
  |> string.split(" ")
  |> list.filter_map(fn(word) {
    let cleaned = string.trim(word)
    case
      string.ends_with(cleaned, ".gleam")
      || string.ends_with(cleaned, ".rs")
      || string.ends_with(cleaned, ".md")
      || string.ends_with(cleaned, ".allium")
      || string.ends_with(cleaned, ".tla")
    {
      True ->
        case string.contains(cleaned, "/") {
          True -> Ok(cleaned)
          False -> Error(Nil)
        }
      False -> Error(Nil)
    }
  })
  |> list.unique
}

/// Generate edges from a holon's content to other holons by STAMP ref.
/// source_id: the holon being analyzed
/// stamp_to_holon: mapping from SC-* ref to target holon UUID
pub fn link_by_stamp(
  source_id: String,
  content: String,
  stamp_to_holon: List(#(String, String)),
) -> List(HolonEdge) {
  let refs = extract_stamp_refs(content)
  refs
  |> list.filter_map(fn(ref) {
    case list.find(stamp_to_holon, fn(pair) { pair.0 == ref }) {
      Ok(#(_, target_id)) ->
        Ok(HolonEdge(
          source_id: source_id,
          target_id: target_id,
          link_type: Code,
          weight: 0.8,
        ))
      Error(_) -> Error(Nil)
    }
  })
}

/// Generate bidirectional edges (wiki + backlink) between two holons.
pub fn link_bidirectional(
  source_id: String,
  target_id: String,
  weight: Float,
) -> List(HolonEdge) {
  [
    HolonEdge(
      source_id: source_id,
      target_id: target_id,
      link_type: Wiki,
      weight: weight,
    ),
    HolonEdge(
      source_id: target_id,
      target_id: source_id,
      link_type: Backlink,
      weight: weight,
    ),
  ]
}

/// Count edges per holon (connectivity metric).
pub fn edge_count_for(holon_id: String, edges: List(HolonEdge)) -> Int {
  list.filter(edges, fn(e) {
    e.source_id == holon_id || e.target_id == holon_id
  })
  |> list.length
}

/// Find orphaned holons (zero edges).
pub fn find_orphans(
  holon_ids: List(String),
  edges: List(HolonEdge),
) -> List(String) {
  list.filter(holon_ids, fn(id) { edge_count_for(id, edges) == 0 })
}

/// Compute graph density: edges / (nodes * (nodes - 1))
pub fn graph_density(node_count: Int, edge_count: Int) -> Float {
  case node_count <= 1 {
    True -> 0.0
    False -> {
      let max_edges = node_count * { node_count - 1 }
      case max_edges > 0 {
        True -> int_to_float(edge_count) /. int_to_float(max_edges)
        False -> 0.0
      }
    }
  }
}

// Helpers
fn clean_stamp_ref(s: String) -> String {
  s
  |> string.replace(",", "")
  |> string.replace(".", "")
  |> string.replace(")", "")
  |> string.replace("(", "")
  |> string.replace("]", "")
  |> string.replace("[", "")
  |> string.trim
}

fn int_to_float(n: Int) -> Float {
  case n {
    0 -> 0.0
    1 -> 1.0
    _ -> {
      let half = int_to_float(n / 2)
      let rem = case n % 2 {
        0 -> 0.0
        _ -> 1.0
      }
      half +. half +. rem
    }
  }
}
