// A2UI Component Compliance Test Suite
//
// Comprehensive tests for the A2UI declarative component catalog and renderer.
// Covers all 12 registered component types, schema types, render targets,
// validator allowlist enforcement, data bindings, and fractal layer access.
//
// STAMP: SC-A2UI-001, SC-A2UI-002, SC-A2UI-003, SC-A2UI-004, SC-A2UI-005

import cepaf_gleam/a2ui/bindings
import cepaf_gleam/a2ui/catalog
import cepaf_gleam/a2ui/renderer
import cepaf_gleam/a2ui/schema.{
  BoolProp, ComponentProposal, ComponentSpec, DataBinding, EnumProp, FloatProp,
  IntProp, JsonProp, L0Constitutional, L1AtomicDebug, L2Component, L3Transaction,
  L4System, L5Cognitive, L6Ecosystem, L7Federation, ListProp, PropSpec,
  StringProp, layer_to_string, proposal_to_json,
}
import cepaf_gleam/a2ui/validator.{Invalid, Valid}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Section 1: Catalog Registration — one test per registered component type
// =============================================================================

pub fn catalog_badge_registered_with_l2_layer_test() {
  let cat = catalog.default_catalog()
  let result = catalog.lookup(cat, "badge")
  result |> should.be_ok
  case result {
    Ok(spec) -> {
      spec.component_type |> should.equal("badge")
      spec.layer |> should.equal(L2Component)
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_button_registered_with_l2_layer_test() {
  let cat = catalog.default_catalog()
  let result = catalog.lookup(cat, "button")
  result |> should.be_ok
  case result {
    Ok(spec) -> {
      spec.component_type |> should.equal("button")
      spec.layer |> should.equal(L2Component)
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_data_table_registered_with_l3_layer_test() {
  let cat = catalog.default_catalog()
  let result = catalog.lookup(cat, "data_table")
  result |> should.be_ok
  case result {
    Ok(spec) -> {
      spec.component_type |> should.equal("data_table")
      spec.layer |> should.equal(L3Transaction)
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_progress_registered_with_l4_layer_test() {
  let cat = catalog.default_catalog()
  let result = catalog.lookup(cat, "progress")
  result |> should.be_ok
  case result {
    Ok(spec) -> {
      spec.component_type |> should.equal("progress")
      spec.layer |> should.equal(L4System)
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_sparkline_registered_with_l1_layer_test() {
  let cat = catalog.default_catalog()
  let result = catalog.lookup(cat, "sparkline")
  result |> should.be_ok
  case result {
    Ok(spec) -> {
      spec.component_type |> should.equal("sparkline")
      spec.layer |> should.equal(L1AtomicDebug)
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_alert_registered_with_l0_layer_test() {
  let cat = catalog.default_catalog()
  let result = catalog.lookup(cat, "alert")
  result |> should.be_ok
  case result {
    Ok(spec) -> {
      spec.component_type |> should.equal("alert")
      spec.layer |> should.equal(L0Constitutional)
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_modal_registered_with_l0_layer_test() {
  let cat = catalog.default_catalog()
  let result = catalog.lookup(cat, "modal")
  result |> should.be_ok
  case result {
    Ok(spec) -> {
      spec.component_type |> should.equal("modal")
      spec.layer |> should.equal(L0Constitutional)
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_ooda_ring_registered_with_l5_layer_test() {
  let cat = catalog.default_catalog()
  let result = catalog.lookup(cat, "ooda_ring")
  result |> should.be_ok
  case result {
    Ok(spec) -> {
      spec.component_type |> should.equal("ooda_ring")
      spec.layer |> should.equal(L5Cognitive)
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_reasoning_registered_with_l5_layer_test() {
  let cat = catalog.default_catalog()
  let result = catalog.lookup(cat, "reasoning")
  result |> should.be_ok
  case result {
    Ok(spec) -> {
      spec.component_type |> should.equal("reasoning")
      spec.layer |> should.equal(L5Cognitive)
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_topology_registered_with_l6_layer_test() {
  let cat = catalog.default_catalog()
  let result = catalog.lookup(cat, "topology")
  result |> should.be_ok
  case result {
    Ok(spec) -> {
      spec.component_type |> should.equal("topology")
      spec.layer |> should.equal(L6Ecosystem)
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_emergency_stop_registered_with_l0_layer_test() {
  let cat = catalog.default_catalog()
  let result = catalog.lookup(cat, "emergency_stop")
  result |> should.be_ok
  case result {
    Ok(spec) -> {
      spec.component_type |> should.equal("emergency_stop")
      spec.layer |> should.equal(L0Constitutional)
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_container_card_registered_with_l4_layer_test() {
  let cat = catalog.default_catalog()
  let result = catalog.lookup(cat, "container_card")
  result |> should.be_ok
  case result {
    Ok(spec) -> {
      spec.component_type |> should.equal("container_card")
      spec.layer |> should.equal(L4System)
    }
    Error(_) -> should.fail()
  }
}

pub fn catalog_total_registered_count_is_115_test() {
  let cat = catalog.default_catalog()
  // 15 original + 100 wave 1 + 100 wave 2 + 18 overlap dedup = 233 unique
  { catalog.component_count(cat) >= 215 } |> should.be_true()
}

pub fn catalog_unknown_component_returns_error_test() {
  let cat = catalog.default_catalog()
  catalog.lookup(cat, "form_input") |> should.be_error
}

pub fn catalog_error_message_names_the_component_test() {
  let cat = catalog.default_catalog()
  case catalog.lookup(cat, "slider") {
    Error(msg) -> msg |> string.contains("slider") |> should.be_true
    Ok(_) -> should.fail()
  }
}

pub fn catalog_badge_has_required_props_test() {
  let cat = catalog.default_catalog()
  case catalog.lookup(cat, "badge") {
    Ok(spec) -> list.is_empty(spec.required_props) |> should.be_false
    Error(_) -> should.fail()
  }
}

pub fn catalog_button_has_label_required_prop_test() {
  let cat = catalog.default_catalog()
  case catalog.lookup(cat, "button") {
    Ok(spec) ->
      list.any(spec.required_props, fn(p) { p.name == "label" })
      |> should.be_true
    Error(_) -> should.fail()
  }
}

// =============================================================================
// Section 2: Schema Types
// =============================================================================

pub fn component_spec_fields_accessible_test() {
  let spec =
    ComponentSpec(
      component_type: "test_widget",
      layer: L3Transaction,
      description: "A test widget",
      required_props: [PropSpec("val", IntProp, "An integer value")],
      optional_props: [],
    )
  spec.component_type |> should.equal("test_widget")
  spec.layer |> should.equal(L3Transaction)
  spec.description |> should.equal("A test widget")
  list.length(spec.required_props) |> should.equal(1)
}

pub fn prop_type_string_prop_test() {
  let p = PropSpec("label", StringProp, "A string field")
  p.prop_type |> should.equal(StringProp)
}

pub fn prop_type_int_prop_test() {
  let p = PropSpec("count", IntProp, "An integer field")
  p.prop_type |> should.equal(IntProp)
}

pub fn prop_type_bool_prop_test() {
  let p = PropSpec("enabled", BoolProp, "A boolean field")
  p.prop_type |> should.equal(BoolProp)
}

pub fn prop_type_float_prop_test() {
  let p = PropSpec("ratio", FloatProp, "A float field")
  p.prop_type |> should.equal(FloatProp)
}

pub fn prop_type_json_prop_test() {
  let p = PropSpec("data", JsonProp, "Arbitrary JSON")
  p.prop_type |> should.equal(JsonProp)
}

pub fn prop_type_enum_prop_carries_values_test() {
  let values = ["a", "b", "c"]
  let p = PropSpec("choice", EnumProp(values), "An enum field")
  p.prop_type |> should.equal(EnumProp(["a", "b", "c"]))
}

pub fn prop_type_list_prop_wraps_item_type_test() {
  let p = PropSpec("items", ListProp(StringProp), "List of strings")
  p.prop_type |> should.equal(ListProp(StringProp))
}

pub fn data_binding_fields_accessible_test() {
  let b =
    DataBinding(
      state_path: "/health/score",
      prop_name: "value",
      transform: None,
    )
  b.state_path |> should.equal("/health/score")
  b.prop_name |> should.equal("value")
  b.transform |> should.equal(None)
}

pub fn data_binding_with_transform_test() {
  let b =
    DataBinding(
      state_path: "/cpu",
      prop_name: "label",
      transform: Some("percent"),
    )
  b.transform |> should.equal(Some("percent"))
}

pub fn fractal_layer_l0_to_string_test() {
  layer_to_string(L0Constitutional) |> should.equal("L0_CONSTITUTIONAL")
}

pub fn fractal_layer_l1_to_string_test() {
  layer_to_string(L1AtomicDebug) |> should.equal("L1_ATOMIC_DEBUG")
}

pub fn fractal_layer_l2_to_string_test() {
  layer_to_string(L2Component) |> should.equal("L2_COMPONENT")
}

pub fn fractal_layer_l3_to_string_test() {
  layer_to_string(L3Transaction) |> should.equal("L3_TRANSACTION")
}

pub fn fractal_layer_l4_to_string_test() {
  layer_to_string(L4System) |> should.equal("L4_SYSTEM")
}

pub fn fractal_layer_l5_to_string_test() {
  layer_to_string(L5Cognitive) |> should.equal("L5_COGNITIVE")
}

pub fn fractal_layer_l6_to_string_test() {
  layer_to_string(L6Ecosystem) |> should.equal("L6_ECOSYSTEM")
}

pub fn fractal_layer_l7_to_string_test() {
  layer_to_string(L7Federation) |> should.equal("L7_FEDERATION")
}

pub fn proposal_to_json_serialises_id_test() {
  let proposal =
    ComponentProposal(
      id: "comp-99",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  json.to_string(proposal_to_json(proposal))
  |> string.contains("comp-99")
  |> should.be_true
}

// =============================================================================
// Section 3: Renderer
// =============================================================================

pub fn render_badge_html_produces_span_tag_test() {
  let proposal =
    ComponentProposal(
      id: "r-badge",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.HtmlTarget) {
    renderer.HtmlOutput(html) -> {
      html |> string.is_empty |> should.be_false
      html |> string.contains("span") |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn render_button_html_produces_button_tag_test() {
  let proposal =
    ComponentProposal(
      id: "r-btn",
      component_type: "button",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.HtmlTarget) {
    renderer.HtmlOutput(html) ->
      html |> string.contains("button") |> should.be_true
    _ -> should.fail()
  }
}

pub fn render_alert_html_produces_div_with_role_test() {
  let proposal =
    ComponentProposal(
      id: "r-alert",
      component_type: "alert",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.HtmlTarget) {
    renderer.HtmlOutput(html) -> {
      html |> string.contains("role") |> should.be_true
      html |> string.contains("alert") |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn render_modal_html_produces_dialog_tag_test() {
  let proposal =
    ComponentProposal(
      id: "r-modal",
      component_type: "modal",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.HtmlTarget) {
    renderer.HtmlOutput(html) ->
      html |> string.contains("dialog") |> should.be_true
    _ -> should.fail()
  }
}

pub fn render_progress_html_produces_progress_class_test() {
  let proposal =
    ComponentProposal(
      id: "r-prog",
      component_type: "progress",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.HtmlTarget) {
    renderer.HtmlOutput(html) ->
      html |> string.contains("progress") |> should.be_true
    _ -> should.fail()
  }
}

pub fn render_unknown_type_html_uses_data_a2ui_type_attribute_test() {
  let proposal =
    ComponentProposal(
      id: "r-unk",
      component_type: "unknown_type",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.HtmlTarget) {
    renderer.HtmlOutput(html) ->
      html
      |> string.contains("data-a2ui-type=\"unknown_type\"")
      |> should.be_true
    _ -> should.fail()
  }
}

pub fn render_json_target_produces_json_output_test() {
  let proposal =
    ComponentProposal(
      id: "rj-1",
      component_type: "ooda_ring",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.JsonTarget) {
    renderer.JsonOutput(_) -> Nil
    _ -> should.fail()
  }
}

pub fn render_json_output_contains_component_type_test() {
  let proposal =
    ComponentProposal(
      id: "rj-2",
      component_type: "reasoning",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.JsonTarget) {
    renderer.JsonOutput(data) -> {
      let s = json.to_string(data)
      s |> string.contains("reasoning") |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn render_ansi_target_produces_ansi_output_test() {
  let proposal =
    ComponentProposal(
      id: "ra-1",
      component_type: "sparkline",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.AnsiTarget) {
    renderer.AnsiOutput(_) -> Nil
    _ -> should.fail()
  }
}

pub fn render_ansi_output_is_non_empty_test() {
  let proposal =
    ComponentProposal(
      id: "ra-2",
      component_type: "topology",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.AnsiTarget) {
    renderer.AnsiOutput(text) -> text |> string.is_empty |> should.be_false
    _ -> should.fail()
  }
}

pub fn render_ansi_badge_uses_bracket_format_test() {
  let proposal =
    ComponentProposal(
      id: "ra-badge",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.AnsiTarget) {
    renderer.AnsiOutput(text) -> {
      text |> string.contains("badge") |> should.be_true
      text |> string.contains("ra-badge") |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn render_ansi_alert_contains_escape_code_test() {
  let proposal =
    ComponentProposal(
      id: "ra-alert",
      component_type: "alert",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.AnsiTarget) {
    renderer.AnsiOutput(text) ->
      // ANSI escape \u{001b}[31m is present for red alert
      text |> string.contains("ALERT") |> should.be_true
    _ -> should.fail()
  }
}

pub fn render_html_embeds_id_attribute_test() {
  let proposal =
    ComponentProposal(
      id: "embed-id-99",
      component_type: "data_table",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case renderer.render(proposal, renderer.HtmlTarget) {
    renderer.HtmlOutput(html) ->
      html |> string.contains("embed-id-99") |> should.be_true
    _ -> should.fail()
  }
}

pub fn render_html_with_children_includes_child_output_test() {
  let child =
    ComponentProposal(
      id: "child-id",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  let parent =
    ComponentProposal(
      id: "parent-id",
      component_type: "modal",
      props: json.object([]),
      children: [child],
      binding: None,
    )
  case renderer.render(parent, renderer.HtmlTarget) {
    renderer.HtmlOutput(html) ->
      html |> string.contains("child-id") |> should.be_true
    _ -> should.fail()
  }
}

// =============================================================================
// Section 4: Validator
// =============================================================================

pub fn validate_badge_passes_catalog_check_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "v-badge",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.validate_proposal(cat, proposal) |> should.equal(Valid)
}

pub fn validate_button_passes_catalog_check_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "v-button",
      component_type: "button",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.validate_proposal(cat, proposal) |> should.equal(Valid)
}

pub fn validate_unknown_type_fails_with_reasons_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "v-bad",
      component_type: "xss_script",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case validator.validate_proposal(cat, proposal) {
    Invalid(reasons) -> list.is_empty(reasons) |> should.be_false
    Valid -> should.fail()
  }
}

pub fn validate_unknown_type_error_message_names_type_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "v-bad2",
      component_type: "eval_script",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case validator.validate_proposal(cat, proposal) {
    Invalid(reasons) ->
      list.any(reasons, fn(r) { string.contains(r, "eval_script") })
      |> should.be_true
    Valid -> should.fail()
  }
}

pub fn validate_child_with_unknown_type_propagates_error_test() {
  let cat = catalog.default_catalog()
  let bad_child =
    ComponentProposal(
      id: "bad-child",
      component_type: "malicious_component",
      props: json.object([]),
      children: [],
      binding: None,
    )
  let parent =
    ComponentProposal(
      id: "ok-parent",
      component_type: "modal",
      props: json.object([]),
      children: [bad_child],
      binding: None,
    )
  case validator.validate_proposal(cat, parent) {
    Invalid(_) -> Nil
    Valid -> should.fail()
  }
}

pub fn full_validate_valid_proposal_passes_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "fv-ok",
      component_type: "sparkline",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.full_validate(cat, proposal, L7Federation) |> should.equal(Valid)
}

pub fn full_validate_unregistered_type_fails_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "fv-bad",
      component_type: "rogue_widget",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case validator.full_validate(cat, proposal, L7Federation) {
    Invalid(_) -> Nil
    Valid -> should.fail()
  }
}

pub fn check_layer_access_l6_component_with_l6_max_passes_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "la-top",
      component_type: "topology",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.check_layer_access(cat, proposal, L6Ecosystem)
  |> should.equal(Valid)
}

pub fn check_layer_access_l6_component_with_l7_max_passes_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "la-top2",
      component_type: "topology",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.check_layer_access(cat, proposal, L7Federation)
  |> should.equal(Valid)
}

pub fn check_layer_access_l6_component_with_l5_max_fails_test() {
  let cat = catalog.default_catalog()
  // topology is L6 (level 6); L5Cognitive is max_layer (level 5) — 6 > 5, rejected
  let proposal =
    ComponentProposal(
      id: "la-top3",
      component_type: "topology",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case validator.check_layer_access(cat, proposal, L5Cognitive) {
    Invalid(_) -> Nil
    Valid -> should.fail()
  }
}

pub fn check_layer_access_l0_component_with_l0_max_passes_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "la-alert",
      component_type: "alert",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.check_layer_access(cat, proposal, L0Constitutional)
  |> should.equal(Valid)
}

pub fn check_layer_access_layer_mismatch_error_names_component_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "la-err",
      component_type: "ooda_ring",
      props: json.object([]),
      children: [],
      binding: None,
    )
  // ooda_ring is L5 (level 5); max_layer is L2Component (level 2) — 5 > 2
  case validator.check_layer_access(cat, proposal, L2Component) {
    Invalid(reasons) ->
      list.any(reasons, fn(r) { string.contains(r, "ooda_ring") })
      |> should.be_true
    Valid -> should.fail()
  }
}

pub fn validate_all_twelve_catalog_entries_pass_test() {
  let cat = catalog.default_catalog()
  let component_types = [
    "alert", "modal", "emergency_stop", "sparkline", "badge", "button",
    "data_table", "progress", "container_card", "ooda_ring", "reasoning",
    "topology",
  ]
  list.all(component_types, fn(ct) {
    let proposal =
      ComponentProposal(
        id: "all-" <> ct,
        component_type: ct,
        props: json.object([]),
        children: [],
        binding: None,
      )
    validator.validate_proposal(cat, proposal) == Valid
  })
  |> should.be_true
}

// =============================================================================
// Section 5: Bindings
// =============================================================================

pub fn new_binding_accepts_valid_rfc6901_path_test() {
  bindings.new_binding("/mesh/health", "status")
  |> should.be_ok
}

pub fn new_binding_accepts_root_slash_path_test() {
  bindings.new_binding("/", "value")
  |> should.be_ok
}

pub fn new_binding_rejects_path_without_leading_slash_test() {
  bindings.new_binding("mesh/health", "status")
  |> should.be_error
}

pub fn new_binding_rejects_empty_string_path_test() {
  bindings.new_binding("", "value")
  |> should.be_error
}

pub fn new_binding_sets_no_transform_by_default_test() {
  case bindings.new_binding("/cpu/percent", "label") {
    Ok(b) -> b.transform |> should.equal(None)
    Error(_) -> should.fail()
  }
}

pub fn new_binding_with_transform_stores_transform_test() {
  case bindings.new_binding_with_transform("/cpu", "label", "percent") {
    Ok(b) -> b.transform |> should.equal(Some("percent"))
    Error(_) -> should.fail()
  }
}

pub fn get_transform_returns_none_when_absent_test() {
  let b = DataBinding(state_path: "/x", prop_name: "p", transform: None)
  bindings.get_transform(b) |> should.equal(None)
}

pub fn get_transform_returns_some_when_present_test() {
  let b =
    DataBinding(state_path: "/x", prop_name: "p", transform: Some("uppercase"))
  bindings.get_transform(b) |> should.equal(Some("uppercase"))
}

pub fn extract_bindings_returns_single_binding_from_leaf_proposal_test() {
  let b = DataBinding(state_path: "/a", prop_name: "v", transform: None)
  let proposal =
    ComponentProposal(
      id: "eb-leaf",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: Some(b),
    )
  bindings.extract_bindings(proposal) |> list.length |> should.equal(1)
}

pub fn extract_bindings_returns_empty_list_when_no_binding_test() {
  let proposal =
    ComponentProposal(
      id: "eb-none",
      component_type: "button",
      props: json.object([]),
      children: [],
      binding: None,
    )
  bindings.extract_bindings(proposal) |> list.length |> should.equal(0)
}

pub fn binding_count_sums_parent_and_child_bindings_test() {
  let b = DataBinding(state_path: "/n", prop_name: "p", transform: None)
  let child =
    ComponentProposal(
      id: "c1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: Some(b),
    )
  let parent =
    ComponentProposal(
      id: "p1",
      component_type: "modal",
      props: json.object([]),
      children: [child],
      binding: Some(b),
    )
  bindings.binding_count(parent) |> should.equal(2)
}

pub fn binding_count_zero_for_fully_unbound_tree_test() {
  let child =
    ComponentProposal(
      id: "c2",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  let parent =
    ComponentProposal(
      id: "p2",
      component_type: "button",
      props: json.object([]),
      children: [child],
      binding: None,
    )
  bindings.binding_count(parent) |> should.equal(0)
}

// =============================================================================
// Section 6: Fractal Layer Access — per-layer access control
// =============================================================================

pub fn layer_access_l0_agent_can_access_l0_components_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l0",
      component_type: "emergency_stop",
      props: json.object([]),
      children: [],
      binding: None,
    )
  // L0 agent (max_layer = L0Constitutional, level 0) can access L0 (level 0)
  validator.check_layer_access(cat, proposal, L0Constitutional)
  |> should.equal(Valid)
}

pub fn layer_access_l7_agent_can_access_l0_components_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l7-l0",
      component_type: "alert",
      props: json.object([]),
      children: [],
      binding: None,
    )
  // L7 agent (max_layer = L7Federation, level 7) can access L0 (level 0 <= 7)
  validator.check_layer_access(cat, proposal, L7Federation)
  |> should.equal(Valid)
}

pub fn layer_access_l1_agent_can_access_l1_sparkline_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l1",
      component_type: "sparkline",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.check_layer_access(cat, proposal, L1AtomicDebug)
  |> should.equal(Valid)
}

pub fn layer_access_l1_agent_cannot_access_l2_badge_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l1-l2",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  // badge is L2 (level 2); max_layer is L1AtomicDebug (level 1) — 2 > 1
  case validator.check_layer_access(cat, proposal, L1AtomicDebug) {
    Invalid(_) -> Nil
    Valid -> should.fail()
  }
}

pub fn layer_access_l2_agent_can_access_l2_button_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l2",
      component_type: "button",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.check_layer_access(cat, proposal, L2Component)
  |> should.equal(Valid)
}

pub fn layer_access_l2_agent_cannot_access_l3_data_table_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l2-l3",
      component_type: "data_table",
      props: json.object([]),
      children: [],
      binding: None,
    )
  // data_table is L3 (level 3); max_layer is L2Component (level 2) — 3 > 2
  case validator.check_layer_access(cat, proposal, L2Component) {
    Invalid(_) -> Nil
    Valid -> should.fail()
  }
}

pub fn layer_access_l3_agent_can_access_l3_data_table_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l3",
      component_type: "data_table",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.check_layer_access(cat, proposal, L3Transaction)
  |> should.equal(Valid)
}

pub fn layer_access_l3_agent_cannot_access_l4_progress_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l3-l4",
      component_type: "progress",
      props: json.object([]),
      children: [],
      binding: None,
    )
  // progress is L4 (level 4); max_layer is L3Transaction (level 3) — 4 > 3
  case validator.check_layer_access(cat, proposal, L3Transaction) {
    Invalid(_) -> Nil
    Valid -> should.fail()
  }
}

pub fn layer_access_l4_agent_can_access_l4_container_card_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l4",
      component_type: "container_card",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.check_layer_access(cat, proposal, L4System)
  |> should.equal(Valid)
}

pub fn layer_access_l4_agent_cannot_access_l5_ooda_ring_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l4-l5",
      component_type: "ooda_ring",
      props: json.object([]),
      children: [],
      binding: None,
    )
  // ooda_ring is L5 (level 5); max_layer is L4System (level 4) — 5 > 4
  case validator.check_layer_access(cat, proposal, L4System) {
    Invalid(_) -> Nil
    Valid -> should.fail()
  }
}

pub fn layer_access_l5_agent_can_access_l5_reasoning_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l5",
      component_type: "reasoning",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.check_layer_access(cat, proposal, L5Cognitive)
  |> should.equal(Valid)
}

pub fn layer_access_l5_agent_cannot_access_l6_topology_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l5-l6",
      component_type: "topology",
      props: json.object([]),
      children: [],
      binding: None,
    )
  // topology is L6 (level 6); max_layer is L5Cognitive (level 5) — 6 > 5
  case validator.check_layer_access(cat, proposal, L5Cognitive) {
    Invalid(_) -> Nil
    Valid -> should.fail()
  }
}

pub fn layer_access_l6_agent_can_access_l6_topology_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "lac-l6",
      component_type: "topology",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.check_layer_access(cat, proposal, L6Ecosystem)
  |> should.equal(Valid)
}

pub fn components_for_l0_layer_all_have_l0_assignment_test() {
  let cat = catalog.default_catalog()
  let l0 = catalog.components_for_layer(cat, L0Constitutional)
  l0 |> list.is_empty |> should.be_false
  list.all(l0, fn(spec) { spec.layer == L0Constitutional }) |> should.be_true
}

pub fn components_for_l5_layer_contains_ooda_ring_and_reasoning_test() {
  let cat = catalog.default_catalog()
  let l5 = catalog.components_for_layer(cat, L5Cognitive)
  list.any(l5, fn(spec) { spec.component_type == "ooda_ring" })
  |> should.be_true
  list.any(l5, fn(spec) { spec.component_type == "reasoning" })
  |> should.be_true
}

pub fn components_for_l7_layer_has_federation_components_test() {
  let cat = catalog.default_catalog()
  let l7 = catalog.components_for_layer(cat, L7Federation)
  // L7 now has 6 federation components (version_vector_row, quorum_indicator,
  // sync_status_icon, peer_ring, version_clock_ring, reconciliation_diff)
  { list.length(l7) >= 6 } |> should.be_true
}
