//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/testing/fractal_matrix</module>
////     <fsharp-lineage>Cepaf.Testing.FractalMatrix</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L1_ATOMIC_DEBUG</layer>
////     <mesh-domain>Fractal BDD Coverage Matrix</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-BDD-001, SC-MATH-COV-001, SC-GLM-TST-001</stamp-controls>
////   </compliance>
//// </c3i-module>
////
//// Fractal BDD Coverage Matrix — enumerates ALL tab components across
//// 15 pages × 8 fractal layers × 7 BDD levels for 100% coverage planning.
//// STAMP: SC-BDD-001, SC-MATH-COV-001, SC-GLM-TST-001, SC-GLM-TST-002

import cepaf_gleam/ui/domain.{
  type FractalLayer, type Page, Cockpit, Dashboard, Federation, HealthGrid,
  Immune, Kms, Knowledge, L0Constitutional, L1AtomicDebug, L2Component,
  L3Transaction, L4System, L5Cognitive, L6Ecosystem, L7Federation, Mcp,
  Metabolic, Planning, Podman, Substrate, Telemetry, Verification, Zenoh,
  page_fractal_layer, page_to_label,
}
import gleam/int
import gleam/list

// =============================================================================
// BDD Level Types (7 levels per SC-BDD-001)
// =============================================================================

pub type BddLevel {
  BddUnit
  BddIntegration
  BddContract
  BddComponent
  BddSystem
  BddAcceptance
  BddVisual
}

pub fn bdd_level_to_string(level: BddLevel) -> String {
  case level {
    BddUnit -> "Unit"
    BddIntegration -> "Integration"
    BddContract -> "Contract"
    BddComponent -> "Component"
    BddSystem -> "System"
    BddAcceptance -> "Acceptance"
    BddVisual -> "Visual"
  }
}

pub fn all_bdd_levels() -> List(BddLevel) {
  [
    BddUnit, BddIntegration, BddContract, BddComponent, BddSystem, BddAcceptance,
    BddVisual,
  ]
}

pub fn bdd_level_count() -> Int {
  7
}

// =============================================================================
// Element Specification
// =============================================================================

/// A single UI element within a tab, with its BDD coverage plan.
pub type ElementSpec {
  ElementSpec(
    id: String,
    element_type: String,
    category: String,
    bdd_levels: List(BddLevel),
    monitoring_sec: Int,
  )
}

// =============================================================================
// Tab Element Inventory
// =============================================================================

/// Complete inventory of all elements for one page/tab.
pub type TabElementInventory {
  TabElementInventory(
    page: Page,
    layer: FractalLayer,
    elements: List(ElementSpec),
    bdd_coverage: Float,
  )
}

// =============================================================================
// BDD Coverage Cell (page × layer × level)
// =============================================================================

pub type BddCell {
  BddCell(
    page: Page,
    layer: FractalLayer,
    level: BddLevel,
    test_count: Int,
    covered: Bool,
  )
}

// =============================================================================
// Rust TUI 12-Tab Mapping (from tui.rs split-test)
// =============================================================================

pub type RustTab {
  RustTab(index: Int, name: String, elements: String, monitoring_sec: Int)
}

/// All 12 Rust TUI tabs from run_split_test() in tui.rs:2561-2574
pub fn rust_tabs() -> List(RustTab) {
  [
    RustTab(0, "Swarm", "Matrix, Logs, Table", 60),
    RustTab(1, "Governor", "Sparkline, Heatmap", 60),
    RustTab(2, "Checks", "State Vector", 15),
    RustTab(3, "Trace", "OTel Flame Bars", 30),
    RustTab(4, "Topology", "Tiered ANSI Mesh", 15),
    RustTab(5, "Build", "Oracle EMA Predict", 30),
    RustTab(6, "NIF", "Substrate Guard", 10),
    RustTab(7, "Recovery", "FMEA RPN Matrix", 20),
    RustTab(8, "Fractal", "L0-L7 Health Tree", 45),
    RustTab(9, "Security", "Axiom 0.1 Enforcement", 10),
    RustTab(10, "Logs", "tui-logger Buffer", 60),
    RustTab(11, "Agent UI", "CoT Dialogue Marquee", 45),
  ]
}

pub fn rust_tab_count() -> Int {
  12
}

// =============================================================================
// All 15 Gleam Pages
// =============================================================================

pub fn all_pages() -> List(Page) {
  [
    Dashboard, Planning, Immune, Knowledge, Zenoh, Cockpit, Verification,
    Substrate, Metabolic, Podman, Mcp, Kms, Telemetry, Federation, HealthGrid,
  ]
}

pub fn page_count() -> Int {
  15
}

// =============================================================================
// Element Enumeration Per Page
// =============================================================================

/// Generate standard elements for any page based on its fractal layer.
fn standard_elements(page: Page) -> List(ElementSpec) {
  let label = page_to_label(page)
  let layer = page_fractal_layer(page)
  let base_monitoring = case layer {
    L0Constitutional -> 45
    L1AtomicDebug -> 30
    L2Component -> 20
    L3Transaction -> 35
    L4System -> 40
    L5Cognitive -> 35
    L6Ecosystem -> 40
    L7Federation -> 45
  }

  [
    // C1: Page Structure
    ElementSpec(
      label <> "_init",
      "model_init",
      "C1",
      [BddUnit, BddComponent],
      base_monitoring,
    ),
    ElementSpec(
      label <> "_view",
      "view_render",
      "C1",
      [BddUnit, BddComponent, BddVisual],
      base_monitoring,
    ),
    // C2: Status Badges
    ElementSpec(
      label <> "_health_badge",
      "status_badge",
      "C2",
      [BddUnit, BddComponent, BddVisual],
      base_monitoring,
    ),
    // C3: Data Grid
    ElementSpec(
      label <> "_data_grid",
      "data_table",
      "C3",
      [BddUnit, BddIntegration, BddComponent],
      base_monitoring,
    ),
    // C4: Timeline
    ElementSpec(
      label <> "_tick",
      "temporal_update",
      "C4",
      [BddUnit, BddIntegration, BddSystem],
      base_monitoring,
    ),
    // C5: Interactive
    ElementSpec(
      label <> "_navigate",
      "navigation",
      "C5",
      [BddUnit, BddAcceptance],
      10,
    ),
    ElementSpec(
      label <> "_action",
      "action_button",
      "C5",
      [BddUnit, BddIntegration, BddAcceptance],
      base_monitoring,
    ),
    // C6: Media/Rich
    ElementSpec(
      label <> "_dark_cockpit",
      "dark_cockpit_mode",
      "C6",
      [BddUnit, BddComponent, BddVisual],
      base_monitoring,
    ),
    // C7: AI Advisory
    ElementSpec(
      label <> "_agui_event",
      "agui_event_flow",
      "C7",
      [BddUnit, BddIntegration, BddSystem],
      base_monitoring,
    ),
    // C8: Action Button (safety)
    ElementSpec(
      label <> "_error_handling",
      "error_boundary",
      "C8",
      [BddUnit, BddIntegration, BddContract, BddSystem],
      base_monitoring,
    ),
    // Zenoh OTel
    ElementSpec(
      label <> "_zenoh_span",
      "otel_span",
      "Zenoh",
      [BddUnit, BddIntegration, BddSystem],
      base_monitoring,
    ),
    // Monitoring
    ElementSpec(
      label <> "_30s_monitor",
      "temporal_stability",
      "Monitor",
      [BddSystem, BddAcceptance],
      30,
    ),
  ]
}

/// Enumerate ALL tab elements across all 15 pages.
pub fn enumerate_all_tab_elements() -> List(TabElementInventory) {
  all_pages()
  |> list.map(fn(page) {
    let elements = standard_elements(page)
    let total_levels =
      list.fold(elements, 0, fn(acc, el) { acc + list.length(el.bdd_levels) })
    let max_levels = list.length(elements) * bdd_level_count()
    let coverage = case max_levels {
      0 -> 0.0
      _ -> int.to_float(total_levels) /. int.to_float(max_levels)
    }
    TabElementInventory(
      page: page,
      layer: page_fractal_layer(page),
      elements: elements,
      bdd_coverage: coverage,
    )
  })
}

/// Total element count across all tabs.
pub fn total_element_count() -> Int {
  enumerate_all_tab_elements()
  |> list.fold(0, fn(acc, inv) { acc + list.length(inv.elements) })
}

/// Total BDD cells: pages × elements × levels.
pub fn total_bdd_cells() -> Int {
  let inventories = enumerate_all_tab_elements()
  list.fold(inventories, 0, fn(acc, inv) {
    list.fold(inv.elements, acc, fn(a, el) { a + list.length(el.bdd_levels) })
  })
}

// =============================================================================
// BDD Matrix Generation (15 pages × 8 layers × 7 levels)
// =============================================================================

/// Generate the full BDD coverage matrix.
pub fn bdd_level_matrix() -> List(BddCell) {
  let inventories = enumerate_all_tab_elements()
  list.flat_map(inventories, fn(inv) {
    list.flat_map(all_bdd_levels(), fn(level) {
      let tests_at_level =
        list.filter(inv.elements, fn(el) { list.contains(el.bdd_levels, level) })
      [
        BddCell(
          page: inv.page,
          layer: inv.layer,
          level: level,
          test_count: list.length(tests_at_level),
          covered: tests_at_level != [],
        ),
      ]
    })
  })
}

/// Count of covered BDD cells.
pub fn covered_cells() -> Int {
  bdd_level_matrix()
  |> list.filter(fn(c) { c.covered })
  |> list.length
}

/// BDD matrix coverage ratio (covered / total cells).
pub fn matrix_coverage() -> Float {
  let total = list.length(bdd_level_matrix())
  let covered = covered_cells()
  case total {
    0 -> 0.0
    _ -> int.to_float(covered) /. int.to_float(total)
  }
}

// =============================================================================
// Monitoring Time Planning
// =============================================================================

/// Total planned monitoring time across all elements (seconds).
pub fn total_monitoring_seconds() -> Int {
  enumerate_all_tab_elements()
  |> list.fold(0, fn(acc, inv) {
    list.fold(inv.elements, acc, fn(a, el) { a + el.monitoring_sec })
  })
}

/// Per-tab monitoring summary.
pub type TabMonitoringSummary {
  TabMonitoringSummary(
    page: Page,
    element_count: Int,
    total_sec: Int,
    min_sec: Int,
    max_sec: Int,
  )
}

pub fn monitoring_plan() -> List(TabMonitoringSummary) {
  enumerate_all_tab_elements()
  |> list.map(fn(inv) {
    let secs = list.map(inv.elements, fn(el) { el.monitoring_sec })
    let total = list.fold(secs, 0, fn(a, s) { a + s })
    let min_s = list.fold(secs, 999, fn(a, s) { int.min(a, s) })
    let max_s = list.fold(secs, 0, fn(a, s) { int.max(a, s) })
    TabMonitoringSummary(
      page: inv.page,
      element_count: list.length(inv.elements),
      total_sec: total,
      min_sec: min_s,
      max_sec: max_s,
    )
  })
}
