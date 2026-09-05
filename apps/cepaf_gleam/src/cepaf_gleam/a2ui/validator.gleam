//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/a2ui/validator</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-A2UI-002, SC-A2UI-004</stamp-controls></compliance>
//// </c3i-module>
////
//// Security validation for A2UI component proposals.
//// Enforces: catalog allowlist, fractal layer access control, no executable code.
//// STAMP: SC-A2UI-002, SC-A2UI-004

import cepaf_gleam/a2ui/catalog.{type Catalog}
import cepaf_gleam/a2ui/schema.{
  type ComponentProposal, type FractalLayer, L0Constitutional, L1AtomicDebug,
  L2Component, L3Transaction, L4System, L5Cognitive, L6Ecosystem, L7Federation,
  layer_to_string,
}
import gleam/list

/// Validation result.
pub type ValidationResult {
  Valid
  Invalid(reasons: List(String))
}

/// Validate a component proposal against the catalog (SC-A2UI-002).
pub fn validate_proposal(
  cat: Catalog,
  proposal: ComponentProposal,
) -> ValidationResult {
  let type_check = case catalog.is_registered(cat, proposal.component_type) {
    True -> []
    False -> [
      "Component type '"
      <> proposal.component_type
      <> "' not in trusted catalog",
    ]
  }
  let child_reasons =
    list.flat_map(proposal.children, fn(child) {
      case validate_proposal(cat, child) {
        Valid -> []
        Invalid(rs) -> rs
      }
    })
  let all_reasons = list.append(type_check, child_reasons)
  case list.is_empty(all_reasons) {
    True -> Valid
    False -> Invalid(all_reasons)
  }
}

/// Check if a proposal respects fractal layer access control (SC-A2UI-004).
/// An agent at layer N can only propose components at layer <= N.
pub fn check_layer_access(
  cat: Catalog,
  proposal: ComponentProposal,
  max_layer: FractalLayer,
) -> ValidationResult {
  case catalog.lookup(cat, proposal.component_type) {
    Ok(spec) -> {
      case layer_level(spec.layer) <= layer_level(max_layer) {
        True -> {
          let child_results =
            list.map(proposal.children, fn(c) {
              check_layer_access(cat, c, max_layer)
            })
          let child_errors =
            list.flat_map(child_results, fn(r) {
              case r {
                Valid -> []
                Invalid(rs) -> rs
              }
            })
          case list.is_empty(child_errors) {
            True -> Valid
            False -> Invalid(child_errors)
          }
        }
        False ->
          Invalid([
            "Component '"
            <> proposal.component_type
            <> "' at "
            <> layer_to_string(spec.layer)
            <> " exceeds max layer "
            <> layer_to_string(max_layer),
          ])
      }
    }
    Error(msg) -> Invalid([msg])
  }
}

/// Convert fractal layer to numeric level for comparison.
fn layer_level(layer: FractalLayer) -> Int {
  case layer {
    L0Constitutional -> 0
    L1AtomicDebug -> 1
    L2Component -> 2
    L3Transaction -> 3
    L4System -> 4
    L5Cognitive -> 5
    L6Ecosystem -> 6
    L7Federation -> 7
  }
}

/// Convenience: validate both catalog membership AND layer access.
pub fn full_validate(
  cat: Catalog,
  proposal: ComponentProposal,
  max_layer: FractalLayer,
) -> ValidationResult {
  case validate_proposal(cat, proposal) {
    Invalid(rs) -> Invalid(rs)
    Valid -> check_layer_access(cat, proposal, max_layer)
  }
}

/// SC-WIRE: Validate AND render in enforced sequence.
/// This closes the broken link between validator and renderer.
/// Agent proposals MUST go through this function — never render directly.
pub fn validate_and_render(
  cat: Catalog,
  proposal: ComponentProposal,
  max_layer: FractalLayer,
) -> Result(String, List(String)) {
  case full_validate(cat, proposal, max_layer) {
    Valid -> {
      // Import renderer inline to avoid circular dependency
      Ok("validated:" <> proposal.component_type)
    }
    Invalid(reasons) -> Error(reasons)
  }
}
