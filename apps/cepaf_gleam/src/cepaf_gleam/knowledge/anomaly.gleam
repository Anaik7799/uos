//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/knowledge/anomaly</module>
////     <fsharp-lineage>Cepaf.Knowledge.AnomalyDetector.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Pattern Recognition & Anomaly Detection</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-KNOWLEDGE-002, SC-AI-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       F# `Seq.fold` over Graphs ≅ Gleam recursive list folds over Nodes.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/knowledge/domain.{type KnowledgeNode}
import gleam/list

pub type Anomaly {
  HighEntropy(node_id: String, entropy: Float)
  HighDrift(node_id: String, drift: Float)
  InvalidRhetoric(node_id: String, message: String)
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> List of domain KnowledgeNodes. </P>
///     <C> detect_anomalies(nodes, entropy_threshold, drift_threshold) </C>
///     <Q> Returns a list of detected Anomalies without mutating state. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn detect_anomalies(
  nodes: List(KnowledgeNode),
  entropy_threshold: Float,
  drift_threshold: Float,
) -> List(Anomaly) {
  list.fold(nodes, [], fn(acc, node) {
    let acc = case node.entropy >. entropy_threshold {
      True -> [HighEntropy(node.id, node.entropy), ..acc]
      False -> acc
    }

    let acc = case node.drift >. drift_threshold {
      True -> [HighDrift(node.id, node.drift), ..acc]
      False -> acc
    }

    acc
  })
  |> list.reverse
}
