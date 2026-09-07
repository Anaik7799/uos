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
import gleam/string

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

/// Sheaf hypergraph containing interconnected KM artifacts.
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

  SheafGraph(
    nodes: [adr77, adr76, adr75, wiki_moc, stamp_sil6],
    total_transclusions: 7,
    cohomology_score: 0.985,
  )
}

/// Add or update a node in the sheaf graph.
pub fn add_node(graph: SheafGraph, node: SheafNode) -> SheafGraph {
  let filtered = list.filter(graph.nodes, fn(n) { n.id != node.id })
  SheafGraph(..graph, nodes: [node, ..filtered])
}

/// Add a bidirectional transclusion link between two nodes in the sheaf.
pub fn add_transclusion(
  graph: SheafGraph,
  from_id: String,
  to_id: String,
) -> SheafGraph {
  let updated_nodes =
    list.map(graph.nodes, fn(n) {
      case n.id == from_id {
        True -> {
          let outs = case list.contains(n.outbound_transclusions, to_id) {
            True -> n.outbound_transclusions
            False -> [to_id, ..n.outbound_transclusions]
          }
          SheafNode(..n, outbound_transclusions: outs)
        }
        False ->
          case n.id == to_id {
            True -> {
              let ins = case list.contains(n.inbound_references, from_id) {
                True -> n.inbound_references
                False -> [from_id, ..n.inbound_references]
              }
              SheafNode(..n, inbound_references: ins)
            }
            False -> n
          }
      }
    })
  SheafGraph(
    ..graph,
    nodes: updated_nodes,
    total_transclusions: graph.total_transclusions + 1,
  )
}

/// Lookup all transcluded neighbor nodes for a given node.
pub fn lookup_transclusions(
  graph: SheafGraph,
  node_id: String,
) -> List(SheafNode) {
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
          Ok(
            QueryResult(
              node: n,
              relevance_score: total_score,
              transclusion_chain: n.outbound_transclusions,
            ),
          )
        False -> Error(Nil)
      }
    })

  list.sort(scored, fn(a, b) {
    float.compare(b.relevance_score, a.relevance_score)
  })
}

/// Compute Sheaf Cohomology Gluing Consistency: ratio of matched bidirectional links.
pub fn compute_cohomology_consistency(graph: SheafGraph) -> Float {
  let total_nodes = list.length(graph.nodes)
  case total_nodes == 0 {
    True -> 1.0
    False -> {
      let consistency_sum =
        list.fold(graph.nodes, 0.0, fn(acc, n) {
          let out_count = list.length(n.outbound_transclusions)
          case out_count == 0 {
            True -> acc +. 1.0
            False -> {
              let valid_targets =
                list.count(n.outbound_transclusions, fn(out_id) {
                  list.any(graph.nodes, fn(cand) { cand.id == out_id })
                })
              acc +. int.to_float(valid_targets) /. int.to_float(out_count)
            }
          }
        })
      consistency_sum /. int.to_float(total_nodes)
    }
  }
}
