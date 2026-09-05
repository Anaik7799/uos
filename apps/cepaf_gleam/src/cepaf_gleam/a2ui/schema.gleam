//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/a2ui/schema</module></identity>
////   <fractal-topology><layer>L2_COMPONENT</layer></fractal-topology>
////   <compliance><stamp-controls>SC-A2UI-001, SC-A2UI-005</stamp-controls></compliance>
//// </c3i-module>
////
//// A2UI JSON schema types — defines the declarative component specification
//// that agents use to propose UI. No executable code — JSON data only.
//// STAMP: SC-A2UI-001, SC-A2UI-005

import gleam/json
import gleam/option.{type Option, None, Some}

/// Fractal layer assignment for a component.
pub type FractalLayer {
  L0Constitutional
  L1AtomicDebug
  L2Component
  L3Transaction
  L4System
  L5Cognitive
  L6Ecosystem
  L7Federation
}

/// A component specification in the A2UI catalog.
pub type ComponentSpec {
  ComponentSpec(
    component_type: String,
    layer: FractalLayer,
    description: String,
    required_props: List(PropSpec),
    optional_props: List(PropSpec),
  )
}

/// A property specification.
pub type PropSpec {
  PropSpec(name: String, prop_type: PropType, description: String)
}

/// Property types that A2UI supports.
pub type PropType {
  StringProp
  IntProp
  FloatProp
  BoolProp
  JsonProp
  ListProp(item_type: PropType)
  EnumProp(values: List(String))
}

/// A component instance proposed by an agent.
pub type ComponentProposal {
  ComponentProposal(
    id: String,
    component_type: String,
    props: json.Json,
    children: List(ComponentProposal),
    binding: Option(DataBinding),
  )
}

/// Data binding from shared state path to component prop.
pub type DataBinding {
  DataBinding(state_path: String, prop_name: String, transform: Option(String))
}

/// Convert a FractalLayer to string.
pub fn layer_to_string(layer: FractalLayer) -> String {
  case layer {
    L0Constitutional -> "L0_CONSTITUTIONAL"
    L1AtomicDebug -> "L1_ATOMIC_DEBUG"
    L2Component -> "L2_COMPONENT"
    L3Transaction -> "L3_TRANSACTION"
    L4System -> "L4_SYSTEM"
    L5Cognitive -> "L5_COGNITIVE"
    L6Ecosystem -> "L6_ECOSYSTEM"
    L7Federation -> "L7_FEDERATION"
  }
}

/// Serialize a ComponentProposal to JSON.
pub fn proposal_to_json(proposal: ComponentProposal) -> json.Json {
  json.object([
    #("id", json.string(proposal.id)),
    #("type", json.string(proposal.component_type)),
    #("props", proposal.props),
    #("children", json.array(proposal.children, proposal_to_json)),
    #("binding", case proposal.binding {
      Some(b) ->
        json.object([
          #("state_path", json.string(b.state_path)),
          #("prop_name", json.string(b.prop_name)),
          #("transform", case b.transform {
            Some(t) -> json.string(t)
            None -> json.null()
          }),
        ])
      None -> json.null()
    }),
  ])
}
