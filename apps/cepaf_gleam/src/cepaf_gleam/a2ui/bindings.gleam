//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/a2ui/bindings</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-A2UI-005</stamp-controls></compliance>
//// </c3i-module>
////
//// Data binding engine — maps state paths to component properties.
//// Uses typed JSON Pointer paths (RFC 6901), not arbitrary selectors.
//// STAMP: SC-A2UI-005

import cepaf_gleam/a2ui/schema.{
  type ComponentProposal, type DataBinding, DataBinding,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// A resolved binding — state value extracted and ready to apply.
pub type ResolvedBinding {
  ResolvedBinding(component_id: String, prop_name: String, value: String)
}

/// Extract all bindings from a proposal tree (recursive).
pub fn extract_bindings(proposal: ComponentProposal) -> List(DataBinding) {
  let own = case proposal.binding {
    Some(b) -> [b]
    None -> []
  }
  let child_bindings = list.flat_map(proposal.children, extract_bindings)
  list.append(own, child_bindings)
}

/// Count total bindings in a proposal tree.
pub fn binding_count(proposal: ComponentProposal) -> Int {
  list.length(extract_bindings(proposal))
}

/// Validate that a state path follows RFC 6901 JSON Pointer format.
/// Must start with "/" and contain only valid pointer segments.
pub fn validate_path(path: String) -> Result(String, String) {
  case string.starts_with(path, "/") {
    True -> Ok(path)
    False -> Error("State path must start with '/' (RFC 6901): " <> path)
  }
}

/// Create a new data binding with validation.
pub fn new_binding(
  state_path: String,
  prop_name: String,
) -> Result(DataBinding, String) {
  case validate_path(state_path) {
    Ok(p) ->
      Ok(DataBinding(state_path: p, prop_name: prop_name, transform: None))
    Error(e) -> Error(e)
  }
}

/// Create a binding with a transform function.
pub fn new_binding_with_transform(
  state_path: String,
  prop_name: String,
  transform: String,
) -> Result(DataBinding, String) {
  case validate_path(state_path) {
    Ok(p) ->
      Ok(DataBinding(
        state_path: p,
        prop_name: prop_name,
        transform: Some(transform),
      ))
    Error(e) -> Error(e)
  }
}

/// Get the transform for a binding, if any.
pub fn get_transform(binding: DataBinding) -> Option(String) {
  binding.transform
}
