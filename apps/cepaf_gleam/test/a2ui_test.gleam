// A2UI module tests — schema, catalog, validator, renderer, bindings.
//
// STAMP: SC-A2UI-001, SC-A2UI-002, SC-A2UI-003, SC-A2UI-004, SC-A2UI-005

import cepaf_gleam/a2ui/bindings
import cepaf_gleam/a2ui/catalog
import cepaf_gleam/a2ui/renderer.{AnsiOutput, HtmlOutput, JsonOutput}
import cepaf_gleam/a2ui/schema.{
  ComponentProposal, DataBinding, L0Constitutional, L1AtomicDebug, L2Component,
  L3Transaction, L4System, L5Cognitive, L6Ecosystem, L7Federation,
  layer_to_string, proposal_to_json,
}
import cepaf_gleam/a2ui/validator.{Invalid, Valid}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// schema — layer_to_string
// =============================================================================

pub fn layer_to_string_l0_test() {
  layer_to_string(L0Constitutional)
  |> should.equal("L0_CONSTITUTIONAL")
}

pub fn layer_to_string_l1_test() {
  layer_to_string(L1AtomicDebug)
  |> should.equal("L1_ATOMIC_DEBUG")
}

pub fn layer_to_string_l2_test() {
  layer_to_string(L2Component)
  |> should.equal("L2_COMPONENT")
}

pub fn layer_to_string_l3_test() {
  layer_to_string(L3Transaction)
  |> should.equal("L3_TRANSACTION")
}

pub fn layer_to_string_l4_test() {
  layer_to_string(L4System)
  |> should.equal("L4_SYSTEM")
}

pub fn layer_to_string_l5_test() {
  layer_to_string(L5Cognitive)
  |> should.equal("L5_COGNITIVE")
}

pub fn layer_to_string_l6_test() {
  layer_to_string(L6Ecosystem)
  |> should.equal("L6_ECOSYSTEM")
}

pub fn layer_to_string_l7_test() {
  layer_to_string(L7Federation)
  |> should.equal("L7_FEDERATION")
}

// =============================================================================
// schema — proposal_to_json
// =============================================================================

pub fn proposal_to_json_contains_id_test() {
  let proposal =
    ComponentProposal(
      id: "p1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  let serialized = json.to_string(proposal_to_json(proposal))
  serialized |> string.contains("p1") |> should.be_true
}

pub fn proposal_to_json_contains_type_test() {
  let proposal =
    ComponentProposal(
      id: "p2",
      component_type: "alert",
      props: json.object([]),
      children: [],
      binding: None,
    )
  let serialized = json.to_string(proposal_to_json(proposal))
  serialized |> string.contains("alert") |> should.be_true
}

pub fn proposal_to_json_with_binding_test() {
  let binding =
    DataBinding(state_path: "/health", prop_name: "text", transform: None)
  let proposal =
    ComponentProposal(
      id: "p3",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: Some(binding),
    )
  let serialized = json.to_string(proposal_to_json(proposal))
  serialized |> string.contains("/health") |> should.be_true
  serialized |> string.contains("text") |> should.be_true
}

pub fn proposal_to_json_null_binding_test() {
  let proposal =
    ComponentProposal(
      id: "p4",
      component_type: "button",
      props: json.object([]),
      children: [],
      binding: None,
    )
  let serialized = json.to_string(proposal_to_json(proposal))
  serialized |> string.contains("null") |> should.be_true
}

// =============================================================================
// catalog — default_catalog
// =============================================================================

pub fn default_catalog_has_12_or_more_components_test() {
  let cat = catalog.default_catalog()
  { catalog.component_count(cat) > 11 } |> should.be_true
}

pub fn catalog_lookup_badge_succeeds_test() {
  let cat = catalog.default_catalog()
  catalog.lookup(cat, "badge") |> should.be_ok
}

pub fn catalog_lookup_unknown_fails_test() {
  let cat = catalog.default_catalog()
  catalog.lookup(cat, "unknown_xyz") |> should.be_error
}

pub fn catalog_is_registered_badge_true_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "badge") |> should.be_true
}

pub fn catalog_is_registered_unknown_false_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "definitely_not_real") |> should.be_false
}

pub fn catalog_components_for_layer_l0_returns_subset_test() {
  let cat = catalog.default_catalog()
  let l0_components = catalog.components_for_layer(cat, L0Constitutional)
  { l0_components != [] } |> should.be_true
  list.all(l0_components, fn(spec) { spec.layer == L0Constitutional })
  |> should.be_true
}

pub fn catalog_components_for_layer_l2_contains_badge_test() {
  let cat = catalog.default_catalog()
  let l2_components = catalog.components_for_layer(cat, L2Component)
  list.any(l2_components, fn(spec) { spec.component_type == "badge" })
  |> should.be_true
}

// =============================================================================
// validator
// =============================================================================

pub fn validate_proposal_valid_for_registered_type_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "v1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.validate_proposal(cat, proposal) |> should.equal(Valid)
}

pub fn validate_proposal_invalid_for_unregistered_type_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "v2",
      component_type: "rogue_component",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case validator.validate_proposal(cat, proposal) {
    Invalid(_) -> Nil
    Valid -> should.fail()
  }
}

pub fn check_layer_access_passes_for_valid_layer_test() {
  let cat = catalog.default_catalog()
  // badge is L2Component; max_layer is L4System (level 4 >= level 2)
  let proposal =
    ComponentProposal(
      id: "la1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.check_layer_access(cat, proposal, L4System)
  |> should.equal(Valid)
}

pub fn check_layer_access_fails_when_component_exceeds_max_layer_test() {
  let cat = catalog.default_catalog()
  // topology is L6Ecosystem; max_layer is L2Component (level 2 < level 6)
  let proposal =
    ComponentProposal(
      id: "la2",
      component_type: "topology",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case validator.check_layer_access(cat, proposal, L2Component) {
    Invalid(_) -> Nil
    Valid -> should.fail()
  }
}

pub fn full_validate_combines_catalog_and_layer_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "fv1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.full_validate(cat, proposal, L7Federation)
  |> should.equal(Valid)
}

pub fn full_validate_rejects_unregistered_component_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "fv2",
      component_type: "evil_script",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case validator.full_validate(cat, proposal, L7Federation) {
    Invalid(_) -> Nil
    Valid -> should.fail()
  }
}

// =============================================================================
// renderer
// =============================================================================

pub fn render_to_html_target_produces_html_output_test() {
  let proposal =
    ComponentProposal(
      id: "r1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.HtmlTarget) {
    HtmlOutput(_) -> Nil
    _ -> should.fail()
  }
}

pub fn render_to_ansi_target_produces_ansi_output_test() {
  let proposal =
    ComponentProposal(
      id: "r2",
      component_type: "alert",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.AnsiTarget) {
    AnsiOutput(_) -> Nil
    _ -> should.fail()
  }
}

pub fn render_to_json_target_produces_json_output_test() {
  let proposal =
    ComponentProposal(
      id: "r3",
      component_type: "button",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.JsonTarget) {
    JsonOutput(_) -> Nil
    _ -> should.fail()
  }
}

pub fn render_html_contains_id_attribute_test() {
  let proposal =
    ComponentProposal(
      id: "myid",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.HtmlTarget) {
    HtmlOutput(html) -> html |> string.contains("myid") |> should.be_true
    _ -> should.fail()
  }
}

pub fn render_ansi_contains_component_id_test() {
  let proposal =
    ComponentProposal(
      id: "ansiid",
      component_type: "progress",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.AnsiTarget) {
    AnsiOutput(text) -> text |> string.contains("ansiid") |> should.be_true
    _ -> should.fail()
  }
}

// =============================================================================
// bindings
// =============================================================================

pub fn validate_path_ok_for_slash_prefix_test() {
  bindings.validate_path("/valid/path")
  |> should.be_ok
}

pub fn validate_path_error_for_no_slash_test() {
  bindings.validate_path("no-slash")
  |> should.be_error
}

pub fn new_binding_creates_binding_test() {
  let result = bindings.new_binding("/state/health", "text")
  result |> should.be_ok
  case result {
    Ok(b) -> {
      b.state_path |> should.equal("/state/health")
      b.prop_name |> should.equal("text")
    }
    Error(_) -> should.fail()
  }
}

pub fn new_binding_rejects_invalid_path_test() {
  bindings.new_binding("bad-path", "text")
  |> should.be_error
}

pub fn extract_bindings_finds_binding_in_proposal_test() {
  let binding =
    DataBinding(state_path: "/data/x", prop_name: "value", transform: None)
  let proposal =
    ComponentProposal(
      id: "eb1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: Some(binding),
    )
  let found = bindings.extract_bindings(proposal)
  list.length(found) |> should.equal(1)
}

pub fn extract_bindings_empty_when_no_bindings_test() {
  let proposal =
    ComponentProposal(
      id: "eb2",
      component_type: "button",
      props: json.object([]),
      children: [],
      binding: None,
    )
  bindings.extract_bindings(proposal)
  |> list.length
  |> should.equal(0)
}

pub fn binding_count_correct_for_nested_proposals_test() {
  let binding = DataBinding(state_path: "/x", prop_name: "p", transform: None)
  let child =
    ComponentProposal(
      id: "child",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: Some(binding),
    )
  let parent =
    ComponentProposal(
      id: "parent",
      component_type: "button",
      props: json.object([]),
      children: [child],
      binding: None,
    )
  bindings.binding_count(parent) |> should.equal(1)
}
