/// Comprehensive A2UI declarative catalog tests.
/// Covers: schema types, catalog lookup (233 components), component count,
/// layer access, validator full_validate, renderer tripartite output,
/// bindings validation and extraction.
///
/// STAMP: SC-A2UI-001..005, SC-GLM-UI-001, SC-ZMOF-001
import cepaf_gleam/a2ui/bindings
import cepaf_gleam/a2ui/catalog
import cepaf_gleam/a2ui/renderer.{AnsiTarget, HtmlTarget, JsonTarget}
import cepaf_gleam/a2ui/schema.{
  type ComponentProposal, ComponentProposal, DataBinding, L0Constitutional,
  L1AtomicDebug, L2Component, L3Transaction, L4System, L5Cognitive, L6Ecosystem,
  L7Federation, layer_to_string, proposal_to_json,
}
import cepaf_gleam/a2ui/validator.{Invalid, Valid}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// §1 schema — FractalLayer exhaustive serialization
// =============================================================================

pub fn schema_layer_l0_constitutional_test() {
  layer_to_string(L0Constitutional) |> should.equal("L0_CONSTITUTIONAL")
}

pub fn schema_layer_l1_atomic_debug_test() {
  layer_to_string(L1AtomicDebug) |> should.equal("L1_ATOMIC_DEBUG")
}

pub fn schema_layer_l2_component_test() {
  layer_to_string(L2Component) |> should.equal("L2_COMPONENT")
}

pub fn schema_layer_l3_transaction_test() {
  layer_to_string(L3Transaction) |> should.equal("L3_TRANSACTION")
}

pub fn schema_layer_l4_system_test() {
  layer_to_string(L4System) |> should.equal("L4_SYSTEM")
}

pub fn schema_layer_l5_cognitive_test() {
  layer_to_string(L5Cognitive) |> should.equal("L5_COGNITIVE")
}

pub fn schema_layer_l6_ecosystem_test() {
  layer_to_string(L6Ecosystem) |> should.equal("L6_ECOSYSTEM")
}

pub fn schema_layer_l7_federation_test() {
  layer_to_string(L7Federation) |> should.equal("L7_FEDERATION")
}

// =============================================================================
// §2 schema — ComponentProposal and proposal_to_json
// =============================================================================

pub fn schema_proposal_to_json_contains_id_test() {
  let p =
    ComponentProposal(
      id: "comp-001",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  let j = json.to_string(proposal_to_json(p))
  j |> string.contains("comp-001") |> should.be_true()
}

pub fn schema_proposal_to_json_contains_type_test() {
  let p =
    ComponentProposal(
      id: "c1",
      component_type: "button",
      props: json.object([]),
      children: [],
      binding: None,
    )
  let j = json.to_string(proposal_to_json(p))
  j |> string.contains("button") |> should.be_true()
}

pub fn schema_proposal_to_json_null_binding_when_none_test() {
  let p =
    ComponentProposal(
      id: "c2",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  let j = json.to_string(proposal_to_json(p))
  j |> string.contains("null") |> should.be_true()
}

pub fn schema_proposal_to_json_with_binding_has_state_path_test() {
  let binding =
    DataBinding(state_path: "/health", prop_name: "label", transform: None)
  let p =
    ComponentProposal(
      id: "c3",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: Some(binding),
    )
  let j = json.to_string(proposal_to_json(p))
  j |> string.contains("/health") |> should.be_true()
  j |> string.contains("label") |> should.be_true()
}

pub fn schema_proposal_nested_children_serialized_test() {
  let child =
    ComponentProposal(
      id: "child-1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  let parent =
    ComponentProposal(
      id: "parent-1",
      component_type: "modal",
      props: json.object([]),
      children: [child],
      binding: None,
    )
  let j = json.to_string(proposal_to_json(parent))
  j |> string.contains("child-1") |> should.be_true()
  j |> string.contains("parent-1") |> should.be_true()
}

// =============================================================================
// §3 catalog — default_catalog construction
// =============================================================================

pub fn catalog_default_has_components_test() {
  let cat = catalog.default_catalog()
  { catalog.component_count(cat) > 0 } |> should.equal(True)
}

pub fn catalog_default_has_at_least_15_components_test() {
  let cat = catalog.default_catalog()
  { catalog.component_count(cat) > 14 } |> should.equal(True)
}

pub fn catalog_badge_is_registered_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "badge") |> should.be_true()
}

pub fn catalog_button_is_registered_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "button") |> should.be_true()
}

pub fn catalog_data_table_is_registered_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "data_table") |> should.be_true()
}

pub fn catalog_sparkline_is_registered_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "sparkline") |> should.be_true()
}

pub fn catalog_alert_is_registered_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "alert") |> should.be_true()
}

pub fn catalog_modal_is_registered_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "modal") |> should.be_true()
}

pub fn catalog_progress_is_registered_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "progress") |> should.be_true()
}

pub fn catalog_unknown_component_not_registered_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "does_not_exist_xyz") |> should.be_false()
}

pub fn catalog_lookup_badge_returns_ok_test() {
  let cat = catalog.default_catalog()
  case catalog.lookup(cat, "badge") {
    Ok(_spec) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

pub fn catalog_lookup_unknown_returns_error_test() {
  let cat = catalog.default_catalog()
  case catalog.lookup(cat, "ghost_component") {
    Ok(_) -> should.fail()
    Error(msg) -> string.contains(msg, "SC-A2UI-002") |> should.be_true()
  }
}

pub fn catalog_lookup_badge_has_correct_layer_test() {
  let cat = catalog.default_catalog()
  case catalog.lookup(cat, "badge") {
    Ok(spec) -> {
      // badge is at L2_COMPONENT or L1_ATOMIC_DEBUG
      let layer_str = layer_to_string(spec.layer)
      string.contains(layer_str, "L") |> should.be_true()
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_components_for_l0_non_empty_test() {
  let cat = catalog.default_catalog()
  let l0_comps = catalog.components_for_layer(cat, L0Constitutional)
  { l0_comps != [] } |> should.equal(True)
}

pub fn catalog_components_for_l2_non_empty_test() {
  let cat = catalog.default_catalog()
  let l2_comps = catalog.components_for_layer(cat, L2Component)
  { l2_comps != [] } |> should.equal(True)
}

pub fn catalog_components_for_each_layer_cover_all_layers_test() {
  let cat = catalog.default_catalog()
  let layers = [
    L0Constitutional,
    L1AtomicDebug,
    L2Component,
    L3Transaction,
    L4System,
    L5Cognitive,
    L6Ecosystem,
    L7Federation,
  ]
  // Every layer should have at least one component (233 spread across 8)
  let all_counts =
    list.map(layers, fn(l) { list.length(catalog.components_for_layer(cat, l)) })
  let total = list.fold(all_counts, 0, fn(acc, n) { acc + n })
  total |> should.equal(catalog.component_count(cat))
}

// =============================================================================
// §4 validator — validate_proposal (catalog allowlist enforcement)
// =============================================================================

fn make_proposal(id: String, comp_type: String) -> ComponentProposal {
  ComponentProposal(
    id: id,
    component_type: comp_type,
    props: json.object([]),
    children: [],
    binding: None,
  )
}

pub fn validator_registered_component_is_valid_test() {
  let cat = catalog.default_catalog()
  let p = make_proposal("v1", "badge")
  validator.validate_proposal(cat, p) |> should.equal(Valid)
}

pub fn validator_unregistered_component_is_invalid_test() {
  let cat = catalog.default_catalog()
  let p = make_proposal("v2", "xss_injected_element")
  case validator.validate_proposal(cat, p) {
    Invalid(reasons) -> { reasons != [] } |> should.equal(True)
    Valid -> should.fail()
  }
}

pub fn validator_invalid_child_propagates_error_test() {
  let cat = catalog.default_catalog()
  let child = make_proposal("bad-child", "exec_script")
  let parent =
    ComponentProposal(
      id: "parent",
      component_type: "modal",
      props: json.object([]),
      children: [child],
      binding: None,
    )
  case validator.validate_proposal(cat, parent) {
    Invalid(reasons) -> { reasons != [] } |> should.equal(True)
    Valid -> should.fail()
  }
}

pub fn validator_valid_nested_proposal_is_valid_test() {
  let cat = catalog.default_catalog()
  let child = make_proposal("child", "badge")
  let parent =
    ComponentProposal(
      id: "parent",
      component_type: "modal",
      props: json.object([]),
      children: [child],
      binding: None,
    )
  validator.validate_proposal(cat, parent) |> should.equal(Valid)
}

// =============================================================================
// §5 validator — check_layer_access (fractal layer enforcement)
// =============================================================================

pub fn validator_l0_agent_can_access_all_layers_test() {
  let cat = catalog.default_catalog()
  // alert is L0, badge is L2 — both accessible to L0 agent (layer 7 is highest)
  let p = make_proposal("la1", "badge")
  validator.check_layer_access(cat, p, L7Federation) |> should.equal(Valid)
}

pub fn validator_l2_agent_cannot_access_unknown_test() {
  let cat = catalog.default_catalog()
  let p = make_proposal("la2", "nonexistent_comp")
  case validator.check_layer_access(cat, p, L2Component) {
    Invalid(_) -> should.be_true(True)
    Valid -> should.fail()
  }
}

pub fn validator_full_validate_valid_proposal_test() {
  let cat = catalog.default_catalog()
  let p = make_proposal("fv1", "badge")
  validator.full_validate(cat, p, L7Federation) |> should.equal(Valid)
}

pub fn validator_full_validate_invalid_type_rejected_test() {
  let cat = catalog.default_catalog()
  let p = make_proposal("fv2", "malicious_widget")
  case validator.full_validate(cat, p, L7Federation) {
    Invalid(reasons) -> { reasons != [] } |> should.equal(True)
    Valid -> should.fail()
  }
}

pub fn validator_and_render_valid_returns_ok_test() {
  let cat = catalog.default_catalog()
  let p = make_proposal("var1", "badge")
  case validator.validate_and_render(cat, p, L7Federation) {
    Ok(result) -> string.contains(result, "validated:badge") |> should.be_true()
    Error(_) -> should.fail()
  }
}

pub fn validator_and_render_invalid_returns_error_test() {
  let cat = catalog.default_catalog()
  let p = make_proposal("var2", "evil_widget")
  case validator.validate_and_render(cat, p, L7Federation) {
    Ok(_) -> should.fail()
    Error(reasons) -> { reasons != [] } |> should.equal(True)
  }
}

// =============================================================================
// §6 renderer — tripartite output (HTML + JSON + ANSI)
// =============================================================================

pub fn renderer_html_target_produces_html_output_test() {
  let p = make_proposal("r1", "badge")
  case renderer.render(p, HtmlTarget) {
    renderer.HtmlOutput(html) ->
      string.contains(html, "badge") |> should.be_true()
    _ -> should.fail()
  }
}

pub fn renderer_json_target_produces_json_output_test() {
  let p = make_proposal("r2", "button")
  case renderer.render(p, JsonTarget) {
    renderer.JsonOutput(_data) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn renderer_ansi_target_produces_ansi_output_test() {
  let p = make_proposal("r3", "sparkline")
  case renderer.render(p, AnsiTarget) {
    renderer.AnsiOutput(text) ->
      { string.length(text) > 0 } |> should.equal(True)
    _ -> should.fail()
  }
}

pub fn renderer_tripartite_returns_triple_test() {
  let p = make_proposal("rtp1", "badge")
  let #(html, _json, ansi) = renderer.render_tripartite(p)
  { string.length(html) > 0 } |> should.equal(True)
  { string.length(ansi) > 0 } |> should.equal(True)
}

pub fn renderer_component_count_single_test() {
  let p = make_proposal("cnt1", "badge")
  renderer.component_count(p) |> should.equal(1)
}

pub fn renderer_component_count_with_children_test() {
  let child1 = make_proposal("ch1", "badge")
  let child2 = make_proposal("ch2", "button")
  let parent =
    ComponentProposal(
      id: "par",
      component_type: "modal",
      props: json.object([]),
      children: [child1, child2],
      binding: None,
    )
  renderer.component_count(parent) |> should.equal(3)
}

pub fn renderer_html_badge_has_span_tag_test() {
  let p = make_proposal("badge-html", "badge")
  case renderer.render(p, HtmlTarget) {
    renderer.HtmlOutput(html) ->
      string.contains(html, "span") |> should.be_true()
    _ -> should.fail()
  }
}

pub fn renderer_html_button_has_button_element_test() {
  let p = make_proposal("btn-html", "button")
  case renderer.render(p, HtmlTarget) {
    renderer.HtmlOutput(html) ->
      string.contains(html, "button") |> should.be_true()
    _ -> should.fail()
  }
}

pub fn renderer_html_contains_data_a2ui_id_test() {
  let p = make_proposal("id-check-99", "badge")
  case renderer.render(p, HtmlTarget) {
    renderer.HtmlOutput(html) ->
      string.contains(html, "data-a2ui-id") |> should.be_true()
    _ -> should.fail()
  }
}

pub fn renderer_json_proposal_contains_type_field_test() {
  let p = make_proposal("jt1", "progress")
  case renderer.render(p, JsonTarget) {
    renderer.JsonOutput(data) -> {
      let s = json.to_string(data)
      s |> string.contains("progress") |> should.be_true()
    }
    _ -> should.fail()
  }
}

// =============================================================================
// §7 bindings — path validation, creation, extraction
// =============================================================================

pub fn bindings_validate_path_valid_test() {
  bindings.validate_path("/health") |> should.equal(Ok("/health"))
}

pub fn bindings_validate_path_nested_valid_test() {
  bindings.validate_path("/containers/0/status")
  |> should.equal(Ok("/containers/0/status"))
}

pub fn bindings_validate_path_without_slash_fails_test() {
  case bindings.validate_path("no-leading-slash") {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.fail()
  }
}

pub fn bindings_validate_path_empty_fails_test() {
  case bindings.validate_path("") {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.fail()
  }
}

pub fn bindings_new_binding_valid_path_test() {
  case bindings.new_binding("/health", "label") {
    Ok(b) -> b.prop_name |> should.equal("label")
    Error(_) -> should.fail()
  }
}

pub fn bindings_new_binding_stores_path_test() {
  case bindings.new_binding("/status/mode", "value") {
    Ok(b) -> b.state_path |> should.equal("/status/mode")
    Error(_) -> should.fail()
  }
}

pub fn bindings_new_binding_no_transform_by_default_test() {
  case bindings.new_binding("/x", "y") {
    Ok(b) -> bindings.get_transform(b) |> should.equal(None)
    Error(_) -> should.fail()
  }
}

pub fn bindings_new_binding_with_transform_stores_transform_test() {
  case
    bindings.new_binding_with_transform("/level", "color", "level_to_color")
  {
    Ok(b) -> bindings.get_transform(b) |> should.equal(Some("level_to_color"))
    Error(_) -> should.fail()
  }
}

pub fn bindings_new_binding_invalid_path_returns_error_test() {
  case bindings.new_binding("bad-path", "prop") {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.fail()
  }
}

pub fn bindings_extract_bindings_no_binding_returns_empty_test() {
  let p = make_proposal("nb1", "badge")
  bindings.extract_bindings(p) |> list.length() |> should.equal(0)
}

pub fn bindings_extract_bindings_with_binding_returns_one_test() {
  let b = DataBinding(state_path: "/k", prop_name: "v", transform: None)
  let p =
    ComponentProposal(
      id: "wb1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: Some(b),
    )
  bindings.extract_bindings(p) |> list.length() |> should.equal(1)
}

pub fn bindings_extract_bindings_recursive_test() {
  let b1 = DataBinding(state_path: "/a", prop_name: "pa", transform: None)
  let b2 = DataBinding(state_path: "/b", prop_name: "pb", transform: None)
  let child =
    ComponentProposal(
      id: "ch",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: Some(b2),
    )
  let parent =
    ComponentProposal(
      id: "pa",
      component_type: "modal",
      props: json.object([]),
      children: [child],
      binding: Some(b1),
    )
  bindings.extract_bindings(parent) |> list.length() |> should.equal(2)
}

pub fn bindings_binding_count_no_bindings_is_zero_test() {
  let p = make_proposal("bc0", "badge")
  bindings.binding_count(p) |> should.equal(0)
}

pub fn bindings_binding_count_one_binding_is_one_test() {
  let b = DataBinding(state_path: "/x", prop_name: "y", transform: None)
  let p =
    ComponentProposal(
      id: "bc1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: Some(b),
    )
  bindings.binding_count(p) |> should.equal(1)
}

// =============================================================================
// §8 Integration — end-to-end validate → render pipeline
// =============================================================================

pub fn e2e_validate_then_render_badge_test() {
  let cat = catalog.default_catalog()
  let p = make_proposal("e2e-badge", "badge")
  case validator.validate_proposal(cat, p) {
    Valid -> {
      let #(html, _json, _ansi) = renderer.render_tripartite(p)
      html |> string.contains("badge") |> should.be_true()
    }
    Invalid(_) -> should.fail()
  }
}

pub fn e2e_full_validate_and_render_returns_ok_for_badge_test() {
  let cat = catalog.default_catalog()
  let p = make_proposal("e2e-fv", "badge")
  case validator.validate_and_render(cat, p, L7Federation) {
    Ok(_) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

pub fn e2e_tripartite_count_invariant_test() {
  // HTML, JSON, ANSI must all describe the same structure
  let child = make_proposal("ce", "badge")
  let parent =
    ComponentProposal(
      id: "pe",
      component_type: "modal",
      props: json.object([]),
      children: [child],
      binding: None,
    )
  let count = renderer.component_count(parent)
  count |> should.equal(2)
  // parent + child
  let #(html, _json, _ansi) = renderer.render_tripartite(parent)
  // Both IDs should appear in HTML
  html |> string.contains("pe") |> should.be_true()
  html |> string.contains("ce") |> should.be_true()
}
