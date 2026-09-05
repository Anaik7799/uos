//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/cell_architecture</module>
////     <fsharp-lineage>None — novel cell-based blast radius isolation (F39)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <mesh-domain>
////       Cell-Based Architecture — F39.
////       Each fractal layer (L0-L7) is an independent fault-isolation cell.
////       Failures are contained within cells; isolation prevents cascade spread.
////       The CellGrid models the full 8-cell mesh and tracks blast radius state.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>
////       SC-HA-001, SC-SIL4-015, SC-FUNC-003, SC-GLM-UI-003, SC-MUDA-001,
////       SC-ULTRA-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Google SRE "blast radius isolation" ↪ Gleam pure CellGrid state machine.
////       BlastRadius is an immutable ADT; isolation is a pure state transform;
////       caller owns persistence and Zenoh publishing (SC-ZMOF-001).
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// CELL-BASED ARCHITECTURE — BLAST RADIUS ISOLATION
//// बहूनि मे व्यतीतानि जन्मानि — Many births have passed (Gita 4.5)
////
//// Each fractal layer is an independent cell. When a cell fails it can be
//// isolated so the blast radius does not spread to its dependents. The
//// isolation decision is pure and reversible — the mesh operator (Rust
//// planning_daemon) owns the side-effects (container stop/restart).
////
//// Cell dependency topology (mirrors health_cascade.gleam):
////   L0 Constitutional : []            (foundation)
////   L1 Atomic/Debug   : ["cell-L0"]
////   L2 Component      : ["cell-L0", "cell-L1"]
////   L3 Transaction    : ["cell-L0", "cell-L1", "cell-L2"]
////   L4 System         : ["cell-L0", "cell-L3"]
////   L5 Cognitive      : ["cell-L0", "cell-L3", "cell-L4"]
////   L6 Ecosystem      : ["cell-L0", "cell-L4"]
////   L7 Federation     : ["cell-L0", "cell-L5", "cell-L6"]
////
//// STAMP: SC-HA-001, SC-SIL4-015, SC-FUNC-003, SC-MUDA-001

import gleam/int
import gleam/json
import gleam/list

// ---------------------------------------------------------------------------
// Core types
// ---------------------------------------------------------------------------

/// Blast radius scope for a single cell or the overall grid.
pub type BlastRadius {
  /// Failure stays within this cell — dependents are unaffected.
  Contained
  /// Failure is propagating toward dependent cells.
  Spreading
  /// Failure has reached all reachable cells.
  SystemWide
}

/// A single fault-isolation cell representing one fractal layer.
pub type Cell {
  Cell(
    /// Unique cell identifier, e.g. "cell-L0"
    id: String,
    /// Fractal layer name, e.g. "L0_CONSTITUTIONAL"
    layer: String,
    /// True when the cell passes its health checks.
    healthy: Bool,
    /// True when the cell has been deliberately isolated (blast-radius
    /// containment). An isolated cell stops receiving traffic and its
    /// failures cannot spread to dependents.
    isolated: Bool,
    /// Named components that live inside this cell.
    components: List(String),
    /// Cell IDs this cell directly depends on. Failure propagates along
    /// these edges when isolation is NOT active.
    dependencies: List(String),
    /// Current blast-radius state for this cell.
    blast_radius: BlastRadius,
  )
}

/// The full 8-cell mesh grid (one cell per fractal layer L0-L7).
pub type CellGrid {
  CellGrid(
    cells: List(Cell),
    total_cells: Int,
    healthy_cells: Int,
    isolated_cells: Int,
    /// Aggregate blast radius across the entire grid.
    system_blast_radius: BlastRadius,
  )
}

// ---------------------------------------------------------------------------
// Constructor helpers
// ---------------------------------------------------------------------------

fn make_cell(
  id: String,
  layer: String,
  components: List(String),
  dependencies: List(String),
) -> Cell {
  Cell(
    id: id,
    layer: layer,
    healthy: True,
    isolated: False,
    components: components,
    dependencies: dependencies,
    blast_radius: Contained,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise a fully-healthy 8-cell grid with the canonical L0-L7 topology.
pub fn init_grid() -> CellGrid {
  let cells = [
    make_cell(
      "cell-L0",
      "L0_CONSTITUTIONAL",
      ["guardian", "psi-invariants", "emergency-stop"],
      [],
    ),
    make_cell(
      "cell-L1",
      "L1_ATOMIC_DEBUG",
      ["otel-nif", "zenoh-nif", "debug-trace"],
      ["cell-L0"],
    ),
    make_cell(
      "cell-L2",
      "L2_COMPONENT",
      ["a2ui-catalog", "lustre-forms", "badge-renderer"],
      ["cell-L0", "cell-L1"],
    ),
    make_cell(
      "cell-L3",
      "L3_TRANSACTION",
      ["sqlite-smriti", "planning-manager", "state-diff"],
      ["cell-L0", "cell-L1", "cell-L2"],
    ),
    make_cell(
      "cell-L4",
      "L4_SYSTEM",
      ["podman-client", "boot-dag", "build-history"],
      ["cell-L0", "cell-L3"],
    ),
    make_cell(
      "cell-L5",
      "L5_COGNITIVE",
      ["cortex-reacts", "mcp-server", "ooda-supervisor"],
      ["cell-L0", "cell-L3", "cell-L4"],
    ),
    make_cell(
      "cell-L6",
      "L6_ECOSYSTEM",
      ["zenoh-router", "mesh-topology", "quorum-routers"],
      ["cell-L0", "cell-L4"],
    ),
    make_cell(
      "cell-L7",
      "L7_FEDERATION",
      ["gateway-telegram", "version-vectors", "leader-election"],
      ["cell-L0", "cell-L5", "cell-L6"],
    ),
  ]
  recompute_grid(cells)
}

/// Mark a cell as isolated.  An isolated cell's failures cannot propagate to
/// dependents.  Returns an updated CellGrid; pure — no side-effects.
pub fn isolate_cell(grid: CellGrid, cell_id: String) -> CellGrid {
  let updated =
    list.map(grid.cells, fn(c) {
      case c.id == cell_id {
        True -> Cell(..c, isolated: True, blast_radius: Contained)
        False -> c
      }
    })
  recompute_grid(updated)
}

/// Restore a previously-isolated cell back to active participation.
pub fn restore_cell(grid: CellGrid, cell_id: String) -> CellGrid {
  let updated =
    list.map(grid.cells, fn(c) {
      case c.id == cell_id {
        True -> Cell(..c, isolated: False)
        False -> c
      }
    })
  recompute_grid(updated)
}

/// Mark a cell as unhealthy and propagate blast-radius state to dependents
/// that are NOT isolated.  Returns an updated CellGrid.
pub fn mark_unhealthy(grid: CellGrid, cell_id: String) -> CellGrid {
  // Step 1: mark the target cell unhealthy
  let step1 =
    list.map(grid.cells, fn(c) {
      case c.id == cell_id {
        True -> Cell(..c, healthy: False, blast_radius: Spreading)
        False -> c
      }
    })
  // Step 2: propagate Spreading to direct dependents if NOT isolated
  let step2 =
    list.map(step1, fn(c) {
      let depends_on_failed =
        list.any(c.dependencies, fn(dep) {
          let parent =
            list.find(step1, fn(p) { p.id == dep })
            |> fn(r) {
              case r {
                Ok(p) -> p
                Error(_) -> c
              }
            }
          !parent.healthy && !parent.isolated
        })
      case depends_on_failed && !c.isolated {
        True -> Cell(..c, blast_radius: Spreading)
        False -> c
      }
    })
  recompute_grid(step2)
}

/// Mark a previously-unhealthy cell as healthy again.
pub fn mark_healthy(grid: CellGrid, cell_id: String) -> CellGrid {
  let updated =
    list.map(grid.cells, fn(c) {
      case c.id == cell_id {
        True -> Cell(..c, healthy: True, blast_radius: Contained)
        False -> c
      }
    })
  recompute_grid(updated)
}

/// Compute the overall system blast radius from the current cell states.
pub fn blast_radius(grid: CellGrid) -> BlastRadius {
  grid.system_blast_radius
}

/// Serialise the CellGrid to a JSON string for Zenoh publishing.
pub fn to_json(grid: CellGrid) -> String {
  let cells_json =
    list.map(grid.cells, fn(c) {
      json.object([
        #("id", json.string(c.id)),
        #("layer", json.string(c.layer)),
        #("healthy", json.bool(c.healthy)),
        #("isolated", json.bool(c.isolated)),
        #("components", json.array(c.components, fn(s) { json.string(s) })),
        #("dependencies", json.array(c.dependencies, fn(s) { json.string(s) })),
        #("blast_radius", json.string(blast_radius_to_string(c.blast_radius))),
      ])
    })
  json.object([
    #("cells", json.array(cells_json, fn(x) { x })),
    #("total_cells", json.int(grid.total_cells)),
    #("healthy_cells", json.int(grid.healthy_cells)),
    #("isolated_cells", json.int(grid.isolated_cells)),
    #(
      "system_blast_radius",
      json.string(blast_radius_to_string(grid.system_blast_radius)),
    ),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// Query helpers
// ---------------------------------------------------------------------------

/// Find a cell by ID. Returns Error(Nil) when not found.
pub fn find_cell(grid: CellGrid, cell_id: String) -> Result(Cell, Nil) {
  list.find(grid.cells, fn(c) { c.id == cell_id })
}

/// True when all cells are healthy and none are isolated.
pub fn is_fully_healthy(grid: CellGrid) -> Bool {
  grid.healthy_cells == grid.total_cells && grid.isolated_cells == 0
}

/// Number of unhealthy, non-isolated cells (active failures).
pub fn active_failure_count(grid: CellGrid) -> Int {
  list.length(list.filter(grid.cells, fn(c) { !c.healthy && !c.isolated }))
}

/// Human-readable summary line for TUI display.
pub fn summary(grid: CellGrid) -> String {
  "CellGrid: "
  <> int.to_string(grid.healthy_cells)
  <> "/"
  <> int.to_string(grid.total_cells)
  <> " healthy, "
  <> int.to_string(grid.isolated_cells)
  <> " isolated — blast_radius="
  <> blast_radius_to_string(grid.system_blast_radius)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn blast_radius_to_string(br: BlastRadius) -> String {
  case br {
    Contained -> "contained"
    Spreading -> "spreading"
    SystemWide -> "system_wide"
  }
}

/// Recompute aggregate counters and system blast-radius from cell list.
fn recompute_grid(cells: List(Cell)) -> CellGrid {
  let total = list.length(cells)
  let healthy = list.length(list.filter(cells, fn(c) { c.healthy }))
  let isolated = list.length(list.filter(cells, fn(c) { c.isolated }))
  let spreading =
    list.any(cells, fn(c) { c.blast_radius == Spreading && !c.isolated })
  let system_br = case spreading {
    True ->
      case healthy == 0 {
        True -> SystemWide
        False -> Spreading
      }
    False -> Contained
  }
  CellGrid(
    cells: cells,
    total_cells: total,
    healthy_cells: healthy,
    isolated_cells: isolated,
    system_blast_radius: system_br,
  )
}
