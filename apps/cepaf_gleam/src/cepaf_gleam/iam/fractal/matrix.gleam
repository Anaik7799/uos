//// =============================================================================
//// [C3I-SIL6-MSTS] iam/fractal/matrix — full L0-L7 × 12-objects = 96-cell
//// fractal coverage matrix.
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/iam/fractal/matrix</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-FRAC-RRF-001..010</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// Aggregates the per-layer binding modules into a single matrix the
//// dashboard, CPIG matrix, and tests query. SC-FRAC-RRF-001 demands the
//// matrix be present and concrete.

import cepaf_gleam/iam/fractal/l0_constitutional
import cepaf_gleam/iam/fractal/l1_atomic
import cepaf_gleam/iam/fractal/l2_component
import cepaf_gleam/iam/fractal/l3_transaction
import cepaf_gleam/iam/fractal/l4_system
import cepaf_gleam/iam/fractal/l5_cognitive
import cepaf_gleam/iam/fractal/l6_ecosystem
import cepaf_gleam/iam/fractal/l7_federation
import cepaf_gleam/iam/objects.{type FractalCell}

/// All 96 cells = 8 layers × 12 objects.
pub fn all_cells() -> List(FractalCell) {
  [
    l0_constitutional.cells(),
    l1_atomic.cells(),
    l2_component.cells(),
    l3_transaction.cells(),
    l4_system.cells(),
    l5_cognitive.cells(),
    l6_ecosystem.cells(),
    l7_federation.cells(),
  ]
  |> flatten
}

pub type Coverage {
  Coverage(layers: Int, objects: Int, cells: Int)
}

/// Returns total coverage. Expected: 8 layers × 12 objects = 96 cells.
pub fn coverage() -> Coverage {
  let cells = all_cells()
  Coverage(
    layers: 8,
    objects: list_length(objects.all_objects()),
    cells: list_length(cells),
  )
}

fn flatten(xs: List(List(a))) -> List(a) {
  case xs {
    [] -> []
    [h, ..t] -> append(h, flatten(t))
  }
}

fn append(a: List(a), b: List(a)) -> List(a) {
  case a {
    [] -> b
    [h, ..t] -> [h, ..append(t, b)]
  }
}

fn list_length(xs: List(a)) -> Int {
  case xs {
    [] -> 0
    [_, ..t] -> 1 + list_length(t)
  }
}
