//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/knowledge/sheaf_engine</module>
////     <fsharp-lineage>N/A — Pure Gleam Sheaf Knowledge Hypergraph & Transclusion Engine</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L5_COGNITIVE</layer>
////     <layer>L6_ECOSYSTEM</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-KM-TRIAD, SC-CHECKLIST-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Bounds for the in-memory directed simple graph, including self-links.
pub const max_nodes = 64

pub const max_edges = 256

pub const max_id_bytes = 256

pub const max_text_bytes = 1024

pub const max_tags = 16

pub type GraphError {
  NodeLimit
  EdgeLimit
  MetadataLimit
  InvalidGraph
  MissingNode(String)
}

/// Document category in the KM Triad.
pub type SheafDocType {
  ZkAdr
  HermesWiki
  StampSafety
  LivingOntology
}

/// A node in the semantic sheaf knowledge graph.
pub type SheafNode {
  SheafNode(
    id: String,
    title: String,
    doc_type: SheafDocType,
    fractal_layer: String,
    tags: List(String),
    outbound_transclusions: List(String),
    inbound_references: List(String),
    centrality_score: Float,
  )
}

/// Legacy public record for a bounded directed knowledge graph. The score is
/// adjacency reciprocity, not a mathematical cohomology or corpus-truth proof.
/// Prefer checked operations; public record construction alone is unvalidated.
pub type SheafGraph {
  SheafGraph(
    nodes: List(SheafNode),
    total_transclusions: Int,
    cohomology_score: Float,
  )
}

/// Query search result with relevance and citation trace.
pub type QueryResult {
  QueryResult(
    node: SheafNode,
    relevance_score: Float,
    transclusion_chain: List(String),
  )
}

/// Convert doc type to human-readable string.
pub fn doc_type_to_string(dt: SheafDocType) -> String {
  case dt {
    ZkAdr -> "zk-adr"
    HermesWiki -> "hermes-wiki"
    StampSafety -> "stamp-safety"
    LivingOntology -> "living-ontology"
  }
}

/// Initialize default knowledge sheaf populated with foundational ADRs and MOCs.
pub fn init_sheaf_graph() -> SheafGraph {
  let adr77 =
    SheafNode(
      id: "ADR-077",
      title: "Century Milestone Swarm Harmony",
      doc_type: ZkAdr,
      fractal_layer: "L0",
      tags: ["#zk-adr", "#century-milestone", "#pid-tuner", "#lean4-harmony"],
      outbound_transclusions: ["ADR-076", "ADR-075", "WIKI-MOC-MASTER"],
      inbound_references: [],
      centrality_score: 0.96,
    )
  let adr76 =
    SheafNode(
      id: "ADR-076",
      title: "Decentralized Work-Stealing Swarm Mesh",
      doc_type: ZkAdr,
      fractal_layer: "L6",
      tags: ["#zk-adr", "#work-stealing", "#topology-view", "#lean4-fairness"],
      outbound_transclusions: ["ADR-075", "WIKI-MOC-MASTER"],
      inbound_references: ["ADR-077"],
      centrality_score: 0.91,
    )
  let adr75 =
    SheafNode(
      id: "ADR-075",
      title: "Delta-CRDT Version Vector Mesh",
      doc_type: ZkAdr,
      fractal_layer: "L7",
      tags: ["#zk-adr", "#crdt-mesh", "#delta-mutator", "#lean4-algebra"],
      outbound_transclusions: ["WIKI-MOC-MASTER"],
      inbound_references: ["ADR-077", "ADR-076"],
      centrality_score: 0.88,
    )
  let wiki_moc =
    SheafNode(
      id: "WIKI-MOC-MASTER",
      title: "UOS Unified Knowledge Master MOC",
      doc_type: HermesWiki,
      fractal_layer: "L5",
      tags: ["#wiki-moc", "#km-triad", "#living-ontology"],
      outbound_transclusions: ["STAMP-SC-SIL6"],
      inbound_references: ["ADR-077", "ADR-076", "ADR-075"],
      centrality_score: 0.99,
    )
  let stamp_sil6 =
    SheafNode(
      id: "STAMP-SC-SIL6",
      title: "SIL-6 STAMP/STPA Safety & Drive Interlock Specification",
      doc_type: StampSafety,
      fractal_layer: "L0",
      tags: ["#stamp-safety", "#sil-6", "#zero-muda", "#drive-lock"],
      outbound_transclusions: [],
      inbound_references: ["WIKI-MOC-MASTER"],
      centrality_score: 0.94,
    )

  rebuild([adr77, adr76, adr75, wiki_moc, stamp_sil6])
}

// Traversal stops at limit+1; do not take unbounded list lengths first.
fn within(items: List(a), remaining: Int) -> Bool {
  case items {
    [] -> True
    [_, ..rest] -> remaining > 0 && within(rest, remaining - 1)
  }
}

fn unique(items: List(String)) -> Bool {
  case items {
    [] -> True
    [first, ..rest] -> !list.contains(rest, first) && unique(rest)
  }
}

fn valid_id(id: String) -> Bool {
  id != "" && string.byte_size(id) <= max_id_bytes
}

fn node_shape(node: SheafNode) -> Result(Nil, GraphError) {
  case
    within(node.tags, max_tags)
    && within(node.outbound_transclusions, max_nodes)
    && within(node.inbound_references, max_nodes)
    && valid_id(node.id)
    && string.byte_size(node.title) <= max_text_bytes
    && string.byte_size(node.fractal_layer) <= max_text_bytes
    && list.all(node.tags, fn(t) { string.byte_size(t) <= max_text_bytes })
    && list.all(node.outbound_transclusions, valid_id)
    && list.all(node.inbound_references, valid_id)
    && node.centrality_score >=. 0.0
    && node.centrality_score <=. 1.0
  {
    True -> Ok(Nil)
    False -> Error(MetadataLimit)
  }
}

fn shape(graph: SheafGraph) -> Result(Nil, GraphError) {
  use _ <- result.try(case within(graph.nodes, max_nodes) {
    True -> Ok(Nil)
    False -> Error(NodeLimit)
  })
  use _ <- result.try(list.try_each(graph.nodes, node_shape))
  let references =
    list.fold(graph.nodes, 0, fn(n, node) {
      n
      + list.length(node.outbound_transclusions)
      + list.length(node.inbound_references)
    })
  case references <= max_edges * 2 {
    True -> Ok(Nil)
    False -> Error(EdgeLimit)
  }
}

fn edge_count(nodes: List(SheafNode)) -> Int {
  list.fold(nodes, 0, fn(n, node) {
    n + list.length(node.outbound_transclusions)
  })
}

/// Validate public record constructors before using them as a graph. Cached
/// fields must match the actual reciprocal adjacency; externally built values
/// are not trusted merely because they have the SheafGraph type.
pub fn validate_graph(graph: SheafGraph) -> Result(Nil, GraphError) {
  use _ <- result.try(shape(graph))
  let count = edge_count(graph.nodes)
  case count > max_edges {
    True -> Error(EdgeLimit)
    False ->
      case
        compute_cohomology_consistency(graph) == 1.0
        && graph.total_transclusions == count
        && graph.cohomology_score == 1.0
      {
        True -> Ok(Nil)
        False -> Error(InvalidGraph)
      }
  }
}

fn rebuild(nodes: List(SheafNode)) -> SheafGraph {
  let updated =
    list.map(nodes, fn(node) {
      let inbound =
        list.filter_map(nodes, fn(source) {
          case list.contains(source.outbound_transclusions, node.id) {
            True -> Ok(source.id)
            False -> Error(Nil)
          }
        })
      SheafNode(..node, inbound_references: list.sort(inbound, string.compare))
    })
  let graph = SheafGraph(updated, edge_count(updated), 0.0)
  SheafGraph(..graph, cohomology_score: compute_cohomology_consistency(graph))
}

/// Replace metadata and outgoing edges for this ID. Existing edges from other
/// nodes are retained. The input inbound_references is a bounded cache field,
/// ignored and rebuilt from all outgoing edges. Missing targets and duplicate
/// outgoing IDs are refused; self-links are allowed and counted once.
pub fn try_add_node(
  graph: SheafGraph,
  node: SheafNode,
) -> Result(SheafGraph, GraphError) {
  use _ <- result.try(validate_graph(graph))
  use _ <- result.try(node_shape(node))
  use _ <- result.try(case unique(node.outbound_transclusions) {
    True -> Ok(Nil)
    False -> Error(InvalidGraph)
  })
  let filtered = list.filter(graph.nodes, fn(n) { n.id != node.id })
  use _ <- result.try(case list.length(filtered) < max_nodes {
    True -> Ok(Nil)
    False -> Error(NodeLimit)
  })
  let nodes = [node, ..filtered]
  use _ <- result.try(
    list.try_each(node.outbound_transclusions, fn(target) {
      case list.any(nodes, fn(n) { n.id == target }) {
        True -> Ok(Nil)
        False -> Error(MissingNode(target))
      }
    }),
  )
  case edge_count(nodes) <= max_edges {
    True -> Ok(rebuild(nodes))
    False -> Error(EdgeLimit)
  }
}

/// Compatibility wrapper: any checked refusal returns the original graph.
/// Use try_add_node when a caller needs the reason for refusal.
pub fn add_node(graph: SheafGraph, node: SheafNode) -> SheafGraph {
  result.unwrap(try_add_node(graph, node), graph)
}

/// Compatibility wrapper for a directed edge and its reciprocal inbound index.
/// Any checked refusal preserves the complete original graph.
pub fn add_transclusion(
  graph: SheafGraph,
  from_id: String,
  to_id: String,
) -> SheafGraph {
  result.unwrap(try_add_transclusion(graph, from_id, to_id), graph)
}

pub fn try_add_transclusion(
  graph: SheafGraph,
  from_id: String,
  to_id: String,
) -> Result(SheafGraph, GraphError) {
  use _ <- result.try(validate_graph(graph))
  use _ <- result.try(case valid_id(from_id) && valid_id(to_id) {
    True -> Ok(Nil)
    False -> Error(MetadataLimit)
  })
  use source <- result.try(
    list.find(graph.nodes, fn(n) { n.id == from_id })
    |> result.map_error(fn(_) { MissingNode(from_id) }),
  )
  use _ <- result.try(case list.any(graph.nodes, fn(n) { n.id == to_id }) {
    True -> Ok(Nil)
    False -> Error(MissingNode(to_id))
  })
  case list.contains(source.outbound_transclusions, to_id) {
    True -> Ok(graph)
    False ->
      case graph.total_transclusions < max_edges {
        False -> Error(EdgeLimit)
        True ->
          Ok(
            rebuild(
              list.map(graph.nodes, fn(n) {
                case n.id == from_id {
                  True ->
                    SheafNode(..n, outbound_transclusions: [
                      to_id,
                      ..n.outbound_transclusions
                    ])
                  False -> n
                }
              }),
            ),
          )
      }
  }
}

/// Lookup all transcluded neighbor nodes for a given node.
pub fn lookup_transclusions(
  graph: SheafGraph,
  node_id: String,
) -> List(SheafNode) {
  case validate_graph(graph) {
    Error(_) -> []
    Ok(_) -> lookup_valid(graph, node_id)
  }
}

fn lookup_valid(graph: SheafGraph, node_id: String) -> List(SheafNode) {
  case list.find(graph.nodes, fn(n) { n.id == node_id }) {
    Ok(target) -> {
      list.filter(graph.nodes, fn(n) {
        list.contains(target.outbound_transclusions, n.id)
        || list.contains(target.inbound_references, n.id)
      })
    }
    Error(_) -> []
  }
}

/// Execute fast semantic query matching titles, tags, and content keywords.
pub fn semantic_search(
  graph: SheafGraph,
  query: String,
  min_relevance: Float,
) -> List(QueryResult) {
  case validate_graph(graph) {
    Error(_) -> []
    Ok(_) ->
      case string.byte_size(query) <= max_text_bytes {
        True -> search_valid(graph, query, min_relevance)
        False -> []
      }
  }
}

fn search_valid(
  graph: SheafGraph,
  query: String,
  min_relevance: Float,
) -> List(QueryResult) {
  let query_lower = string.lowercase(query)
  let scored =
    list.filter_map(graph.nodes, fn(n) {
      let title_match = case
        string.contains(string.lowercase(n.title), query_lower)
      {
        True -> 0.6
        False -> 0.0
      }
      let id_match = case string.contains(string.lowercase(n.id), query_lower) {
        True -> 0.8
        False -> 0.0
      }
      let tag_match =
        list.fold(n.tags, 0.0, fn(acc, tag) {
          case string.contains(string.lowercase(tag), query_lower) {
            True -> acc +. 0.3
            False -> acc
          }
        })
      let total_score =
        float.min(
          1.0,
          title_match +. id_match +. tag_match +. n.centrality_score *. 0.2,
        )

      case total_score >=. min_relevance {
        True ->
          Ok(QueryResult(
            node: n,
            relevance_score: total_score,
            transclusion_chain: n.outbound_transclusions,
          ))
        False -> Error(Nil)
      }
    })

  list.sort(scored, fn(a, b) {
    float.compare(b.relevance_score, a.relevance_score)
  })
}

/// Observed reciprocal-adjacency ratio, not mathematical sheaf cohomology.
/// Each distinct outgoing edge with exactly one reciprocal inbound entry counts
/// two matched adjacency entries. Dangling, one-sided and duplicate entries add
/// to the denominator without matching. Isolated nodes do not inflate the score.
/// Empty well-shaped graphs score 1; malformed IDs/over-budget graphs score 0.
/// The historic field/function name remains for source compatibility.
pub fn compute_cohomology_consistency(graph: SheafGraph) -> Float {
  case shape(graph) {
    Error(_) -> 0.0
    Ok(_) ->
      case unique(list.map(graph.nodes, fn(n) { n.id })) {
        False -> 0.0
        True -> {
          let total =
            list.fold(graph.nodes, 0, fn(acc, n) {
              acc
              + list.length(n.outbound_transclusions)
              + list.length(n.inbound_references)
            })
          let matched =
            list.fold(graph.nodes, 0, fn(acc, source) {
              acc
              + 2
              * list.count(source.outbound_transclusions, fn(target_id) {
                list.count(source.outbound_transclusions, fn(id) {
                  id == target_id
                })
                == 1
                && list.any(graph.nodes, fn(target) {
                  target.id == target_id
                  && list.count(target.inbound_references, fn(id) {
                    id == source.id
                  })
                  == 1
                })
              })
            })
          case total {
            0 -> 1.0
            _ -> int.to_float(matched) /. int.to_float(total)
          }
        }
      }
  }
}
