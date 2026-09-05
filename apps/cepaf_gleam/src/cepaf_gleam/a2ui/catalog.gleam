//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/a2ui/catalog</module></identity>
////   <fractal-topology><layer>L2_COMPONENT</layer></fractal-topology>
////   <compliance><stamp-controls>SC-A2UI-002, SC-A2UI-004, SC-FILESIZE-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Trusted component registry — the security boundary for A2UI.
//// Thin facade delegating to core_catalog, wave1_catalog, wave2_catalog.
//// Agents can ONLY request components registered in this catalog.
//// विभागशः — Division into parts (Gita 18.41)
//// STAMP: SC-A2UI-002, SC-A2UI-004

import cepaf_gleam/a2ui/core_catalog
import cepaf_gleam/a2ui/schema.{type ComponentSpec, type FractalLayer}
import cepaf_gleam/a2ui/wave1_catalog
import cepaf_gleam/a2ui/wave2_catalog
import gleam/dict.{type Dict}
import gleam/list
import gleam/result

/// The component catalog — maps type names to specs.
pub type Catalog {
  Catalog(components: Dict(String, ComponentSpec))
}

/// Build the default c3i component catalog with all 233 registered components.
pub fn default_catalog() -> Catalog {
  let components =
    list.flatten([
      core_catalog.components(),
      wave1_catalog.components(),
      wave2_catalog.components(),
    ])
  Catalog(components: dict.from_list(components))
}

/// Look up a component spec by type name.
pub fn lookup(
  catalog: Catalog,
  component_type: String,
) -> Result(ComponentSpec, String) {
  dict.get(catalog.components, component_type)
  |> result.replace_error(
    "Component '" <> component_type <> "' not in catalog (SC-A2UI-002)",
  )
}

/// Check if a component type is registered.
pub fn is_registered(catalog: Catalog, component_type: String) -> Bool {
  dict.has_key(catalog.components, component_type)
}

/// Get all component types for a specific fractal layer.
pub fn components_for_layer(
  catalog: Catalog,
  layer: FractalLayer,
) -> List(ComponentSpec) {
  dict.values(catalog.components)
  |> list.filter(fn(spec) { spec.layer == layer })
}

/// Count total registered components.
pub fn component_count(catalog: Catalog) -> Int {
  dict.size(catalog.components)
}
