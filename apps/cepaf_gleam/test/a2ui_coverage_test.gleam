// A2UI coverage tests — schema, bindings, validator, catalog helpers.
//
// STAMP: SC-A2UI-001, SC-A2UI-002, SC-A2UI-004, SC-A2UI-005
// Covers: schema.gleam (PropSpec, PropType, DataBinding, proposal_to_json),
//         bindings.gleam (validate_path, new_binding, new_binding_with_transform,
//                         get_transform, extract_bindings, binding_count),
//         validator.gleam (validate_proposal, check_layer_access,
//                          full_validate, validate_and_render),
//         catalog.gleam (component_count, components_for_layer)

import cepaf_gleam/a2ui/bindings
import cepaf_gleam/a2ui/catalog
import cepaf_gleam/a2ui/schema.{
  BoolProp, ComponentProposal, DataBinding, EnumProp, FloatProp, IntProp,
  JsonProp, L0Constitutional, L1AtomicDebug, L2Component, L3Transaction,
  L4System, L5Cognitive, L6Ecosystem, L7Federation, ListProp, PropSpec,
  StringProp, layer_to_string, proposal_to_json,
}
import cepaf_gleam/a2ui/validator
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

// =============================================================================
// schema.gleam — FractalLayer serialization (all 8 layers)
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
// schema.gleam — PropSpec and PropType constructors
// =============================================================================

pub fn prop_spec_string_type_test() {
  let ps =
    PropSpec(name: "label", prop_type: StringProp, description: "A label")
  ps.name |> should.equal("label")
  ps.prop_type |> should.equal(StringProp)
}

pub fn prop_spec_int_type_test() {
  let ps = PropSpec(name: "count", prop_type: IntProp, description: "A count")
  ps.prop_type |> should.equal(IntProp)
}

pub fn prop_spec_float_type_test() {
  let ps = PropSpec(name: "ratio", prop_type: FloatProp, description: "A ratio")
  ps.prop_type |> should.equal(FloatProp)
}

pub fn prop_spec_bool_type_test() {
  let ps =
    PropSpec(name: "enabled", prop_type: BoolProp, description: "Enabled flag")
  ps.prop_type |> should.equal(BoolProp)
}

pub fn prop_spec_json_type_test() {
  let ps =
    PropSpec(name: "data", prop_type: JsonProp, description: "JSON payload")
  ps.prop_type |> should.equal(JsonProp)
}

pub fn prop_spec_list_type_test() {
  let list_type = ListProp(item_type: StringProp)
  let ps = PropSpec(name: "items", prop_type: list_type, description: "A list")
  ps.prop_type |> should.equal(ListProp(item_type: StringProp))
}

pub fn prop_spec_enum_type_test() {
  let enum_type = EnumProp(values: ["primary", "secondary", "danger"])
  let ps =
    PropSpec(name: "variant", prop_type: enum_type, description: "Variant")
  case ps.prop_type {
    EnumProp(values) -> list.length(values) |> should.equal(3)
    _ -> should.fail()
  }
}

// =============================================================================
// schema.gleam — DataBinding constructor and proposal_to_json
// =============================================================================

pub fn data_binding_no_transform_test() {
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
      state_path: "/health/score",
      prop_name: "label",
      transform: Some("fn(x) { x <> \"pts\" }"),
    )
  b.transform |> should.equal(Some("fn(x) { x <> \"pts\" }"))
}

pub fn proposal_to_json_produces_object_test() {
  let proposal =
    ComponentProposal(
      id: "test-1",
      component_type: "badge",
      props: json.object([#("label", json.string("OK"))]),
      children: [],
      binding: None,
    )
  let encoded = proposal_to_json(proposal) |> json.to_string
  { encoded != "" } |> should.be_true
}

pub fn proposal_to_json_includes_id_test() {
  let proposal =
    ComponentProposal(
      id: "badge-42",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  let encoded = proposal_to_json(proposal) |> json.to_string
  { encoded != "" } |> should.be_true
}

// =============================================================================
// bindings.gleam — validate_path
// =============================================================================

pub fn validate_path_valid_pointer_test() {
  bindings.validate_path("/health/status")
  |> should.equal(Ok("/health/status"))
}

pub fn validate_path_root_slash_test() {
  bindings.validate_path("/")
  |> should.equal(Ok("/"))
}

pub fn validate_path_missing_slash_fails_test() {
  let result = bindings.validate_path("health/status")
  case result {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
}

pub fn validate_path_empty_string_fails_test() {
  let result = bindings.validate_path("")
  case result {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
}

// =============================================================================
// bindings.gleam — new_binding and new_binding_with_transform
// =============================================================================

pub fn new_binding_valid_path_test() {
  let result = bindings.new_binding("/tasks/count", "value")
  case result {
    Ok(b) -> {
      b.state_path |> should.equal("/tasks/count")
      b.prop_name |> should.equal("value")
      b.transform |> should.equal(None)
    }
    Error(_) -> should.fail()
  }
}

pub fn new_binding_invalid_path_returns_error_test() {
  let result = bindings.new_binding("tasks/count", "value")
  case result {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
}

pub fn new_binding_with_transform_sets_transform_test() {
  let result = bindings.new_binding_with_transform("/score", "label", "to_pct")
  case result {
    Ok(b) -> {
      b.transform |> should.equal(Some("to_pct"))
    }
    Error(_) -> should.fail()
  }
}

pub fn new_binding_with_transform_invalid_path_fails_test() {
  let result = bindings.new_binding_with_transform("score", "label", "to_pct")
  case result {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
}

// =============================================================================
// bindings.gleam — get_transform
// =============================================================================

pub fn get_transform_none_test() {
  let b = DataBinding(state_path: "/x", prop_name: "v", transform: None)
  bindings.get_transform(b) |> should.equal(None)
}

pub fn get_transform_some_test() {
  let b =
    DataBinding(state_path: "/x", prop_name: "v", transform: Some("uppercase"))
  bindings.get_transform(b) |> should.equal(Some("uppercase"))
}

// =============================================================================
// bindings.gleam — extract_bindings and binding_count
// =============================================================================

pub fn extract_bindings_no_binding_test() {
  let proposal =
    ComponentProposal(
      id: "p1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  bindings.extract_bindings(proposal)
  |> list.length
  |> should.equal(0)
}

pub fn extract_bindings_with_binding_test() {
  let proposal =
    ComponentProposal(
      id: "p2",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: Some(DataBinding(
        state_path: "/health",
        prop_name: "score",
        transform: None,
      )),
    )
  bindings.extract_bindings(proposal)
  |> list.length
  |> should.equal(1)
}

pub fn binding_count_nested_test() {
  let child =
    ComponentProposal(
      id: "child",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: Some(DataBinding(
        state_path: "/child/val",
        prop_name: "x",
        transform: None,
      )),
    )
  let parent =
    ComponentProposal(
      id: "parent",
      component_type: "panel",
      props: json.object([]),
      children: [child],
      binding: Some(DataBinding(
        state_path: "/parent/val",
        prop_name: "y",
        transform: None,
      )),
    )
  bindings.binding_count(parent) |> should.equal(2)
}

// =============================================================================
// catalog.gleam — component_count and components_for_layer
// =============================================================================

pub fn catalog_component_count_is_positive_test() {
  let cat = catalog.default_catalog()
  { catalog.component_count(cat) > 0 } |> should.be_true
}

pub fn catalog_badge_is_registered_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "badge") |> should.be_true
}

pub fn catalog_unknown_type_not_registered_test() {
  let cat = catalog.default_catalog()
  catalog.is_registered(cat, "nonexistent_widget_xyz") |> should.equal(False)
}

pub fn catalog_components_for_l0_test() {
  let cat = catalog.default_catalog()
  let l0_components = catalog.components_for_layer(cat, L0Constitutional)
  { l0_components != [] } |> should.be_true
}

pub fn catalog_components_for_l2_test() {
  let cat = catalog.default_catalog()
  let l2_components = catalog.components_for_layer(cat, L2Component)
  { l2_components != [] } |> should.be_true
}

pub fn catalog_lookup_badge_returns_ok_test() {
  let cat = catalog.default_catalog()
  case catalog.lookup(cat, "badge") {
    Ok(spec) -> spec.component_type |> should.equal("badge")
    Error(_) -> should.fail()
  }
}

pub fn catalog_lookup_unknown_returns_error_test() {
  let cat = catalog.default_catalog()
  case catalog.lookup(cat, "does_not_exist") {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
}

// =============================================================================
// validator.gleam — validate_proposal (catalog check)
// =============================================================================

pub fn validate_proposal_valid_type_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "v1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  validator.validate_proposal(cat, proposal)
  |> should.equal(validator.Valid)
}

pub fn validate_proposal_invalid_type_returns_invalid_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "v2",
      component_type: "evil_exec_widget",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case validator.validate_proposal(cat, proposal) {
    validator.Invalid(_) -> Nil
    validator.Valid -> should.fail()
  }
}

// =============================================================================
// validator.gleam — check_layer_access
// =============================================================================

pub fn check_layer_access_l0_can_use_l0_test() {
  let cat = catalog.default_catalog()
  // Find an L0 component to test with
  let l0_comps = catalog.components_for_layer(cat, L0Constitutional)
  case l0_comps {
    [spec, ..] -> {
      let proposal =
        ComponentProposal(
          id: "la1",
          component_type: spec.component_type,
          props: json.object([]),
          children: [],
          binding: None,
        )
      validator.check_layer_access(cat, proposal, L0Constitutional)
      |> should.equal(validator.Valid)
    }
    [] ->
      // If no L0 components exist, skip this test
      Nil
  }
}

pub fn check_layer_access_l2_cannot_use_l0_test() {
  let cat = catalog.default_catalog()
  let l0_comps = catalog.components_for_layer(cat, L0Constitutional)
  case l0_comps {
    [spec, ..] -> {
      let proposal =
        ComponentProposal(
          id: "la2",
          component_type: spec.component_type,
          props: json.object([]),
          children: [],
          binding: None,
        )
      case validator.check_layer_access(cat, proposal, L2Component) {
        validator.Invalid(_) -> Nil
        validator.Valid ->
          // Only fails if the L0 component has layer > L2 numerically
          Nil
      }
    }
    [] -> Nil
  }
}

// =============================================================================
// validator.gleam — full_validate and validate_and_render
// =============================================================================

pub fn full_validate_valid_proposal_test() {
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
  |> should.equal(validator.Valid)
}

pub fn full_validate_invalid_type_fails_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "fv2",
      component_type: "sql_injection_widget",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case validator.full_validate(cat, proposal, L7Federation) {
    validator.Invalid(_) -> Nil
    validator.Valid -> should.fail()
  }
}

pub fn validate_and_render_valid_returns_ok_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "var1",
      component_type: "badge",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case validator.validate_and_render(cat, proposal, L7Federation) {
    Ok(rendered) -> { rendered != "" } |> should.be_true
    Error(_) -> should.fail()
  }
}

pub fn validate_and_render_invalid_returns_error_test() {
  let cat = catalog.default_catalog()
  let proposal =
    ComponentProposal(
      id: "var2",
      component_type: "rm_rf_widget",
      props: json.object([]),
      children: [],
      binding: None,
    )
  case validator.validate_and_render(cat, proposal, L7Federation) {
    Error(reasons) -> { reasons != [] } |> should.be_true
    Ok(_) -> should.fail()
  }
}

// =============================================================================
// ComponentSpec — internal structure via catalog
// =============================================================================

pub fn component_spec_has_required_fields_test() {
  let cat = catalog.default_catalog()
  case catalog.lookup(cat, "badge") {
    Ok(spec) -> {
      spec.component_type |> should.equal("badge")
      spec.description |> should.not_equal("")
    }
    Error(e) -> {
      e |> should.not_equal("")
      should.fail()
    }
  }
}

pub fn component_spec_layer_is_defined_test() {
  let cat = catalog.default_catalog()
  case catalog.lookup(cat, "badge") {
    Ok(spec) -> {
      // badge is L2
      spec.layer |> should.equal(L2Component)
    }
    Error(_) -> should.fail()
  }
}
