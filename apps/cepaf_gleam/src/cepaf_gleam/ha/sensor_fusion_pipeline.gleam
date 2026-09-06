//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/sensor_fusion_pipeline</module>
////     <fsharp-lineage>None — novel multi-source sensor fusion for SLAM and
////       obstacle detection in the biomorphic perception layer</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Weighted multi-source sensor fusion pipeline with Kalman-like
////       reliability weighting, 2-D spatial SLAM mapping, and obstacle field
////       extraction.  Supports the biomorphic homeostasis loop (Ψ₁) by giving
////       the OODA Orient phase a consistent, noise-reduced picture of the
////       physical environment.
////
////       Fusion equation (weighted average):
////
////         fused = Σ(rᵢ × wᵢ × reading_i) / Σ(rᵢ × wᵢ)
////
////       where rᵢ is the per-source reliability ∈ [0,1] and wᵢ is the
////       configured weight > 0.  Sources with zero readings contribute
////       auto_weight = 0 (not yet initialised).
////
////       Spatial map uses Manhattan-distance neighbourhood queries; obstacle
////       fields are derived by thresholding occupancy probability.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-BIO-EVO-001, SC-MUDA-001, SC-SIL4-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Weighted-average sensor fusion ↪ Gleam pure value types.
////       All state is passed by value; no mutable globals.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 arithmetic — adequate for obstacle / SLAM mapping;
////       not for safety actuation.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// SENSOR FUSION PIPELINE — WEIGHTED MULTI-SOURCE PERCEPTION
//// समस्थिति — Homeostasis: the system senses and maintains equilibrium (Gita 2.48)
////
//// STAMP: SC-HA-001, SC-BIO-EVO-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A single sensor source in the fusion pipeline.
pub type SensorSource {
  SensorSource(
    /// Unique identifier for this source
    id: String,
    /// Sensor kind string (e.g. "lidar", "sonar", "camera")
    kind: String,
    /// Configured fusion weight (> 0)
    weight: Float,
    /// Source reliability ∈ [0, 1]  — degrades on fault, recovers on ack
    reliability: Float,
    /// Most recent reading value
    last_reading: Float,
    /// Unix-epoch millisecond timestamp of last ingest
    last_timestamp: Int,
    /// Total number of readings ingested
    reading_count: Int,
  )
}

/// Output of one fusion cycle across all active sources.
pub type FusedPerception {
  FusedPerception(
    /// Noise-reduced fused value
    fused_value: Float,
    /// Confidence ∈ [0, 1] — derived from weighted reliability of sources used
    confidence: Float,
    /// Number of sources that contributed to this fusion
    source_count: Int,
    /// Number of stale / zero-reading sources excluded
    stale_count: Int,
  )
}

/// Running state of the perception pipeline.
pub type PerceptionPipeline {
  PerceptionPipeline(
    /// Registered sensor sources
    sources: List(SensorSource),
    /// Result of the most recent fuse/1 call
    last_fusion: FusedPerception,
    /// Monotonically increasing count of fuse/1 calls
    cycle_count: Int,
  )
}

/// A single occupancy cell in the 2-D spatial map.
pub type MapCell {
  MapCell(
    /// Grid X coordinate
    x: Int,
    /// Grid Y coordinate
    y: Int,
    /// Occupancy probability ∈ [0, 1]
    occupancy: Float,
    /// Timestamp of last observation (Unix epoch ms)
    last_observed: Int,
    /// Confidence in the occupancy value ∈ [0, 1]
    confidence: Float,
  )
}

/// 2-D occupancy grid representing the environment.
pub type SpatialMap {
  SpatialMap(
    /// All known cells (sparse representation)
    cells: List(MapCell),
    /// Metres per grid cell
    resolution: Float,
    /// Grid width in cells
    width: Int,
    /// Grid height in cells
    height: Int,
  )
}

/// Derived obstacle field — cells whose occupancy exceeds a threshold.
pub type ObstacleField {
  ObstacleField(
    /// Cells classified as obstacles
    obstacles: List(MapCell),
    /// Safe-passage radius in grid cells
    safe_radius: Float,
  )
}

// ---------------------------------------------------------------------------
// Pipeline API
// ---------------------------------------------------------------------------

/// Create a new pipeline with the given source list and a zeroed initial fusion.
pub fn pipeline_new(sources: List(SensorSource)) -> PerceptionPipeline {
  PerceptionPipeline(
    sources: sources,
    last_fusion: FusedPerception(
      fused_value: 0.0,
      confidence: 0.0,
      source_count: 0,
      stale_count: 0,
    ),
    cycle_count: 0,
  )
}

/// Construct a new SensorSource with default reliability 1.0 and zero readings.
pub fn source_new(id: String, kind: String, weight: Float) -> SensorSource {
  SensorSource(
    id: id,
    kind: kind,
    weight: weight,
    reliability: 1.0,
    last_reading: 0.0,
    last_timestamp: 0,
    reading_count: 0,
  )
}

/// Ingest a new reading for a specific source identified by `source_id`.
/// Updates `last_reading`, `last_timestamp`, and increments `reading_count`.
/// Sources not found are left unchanged.
pub fn pipeline_ingest(
  pipeline: PerceptionPipeline,
  source_id: String,
  reading: Float,
  timestamp: Int,
) -> PerceptionPipeline {
  let updated_sources =
    list.map(pipeline.sources, fn(src) {
      case src.id == source_id {
        True ->
          SensorSource(
            ..src,
            last_reading: reading,
            last_timestamp: timestamp,
            reading_count: src.reading_count + 1,
          )
        False -> src
      }
    })
  PerceptionPipeline(..pipeline, sources: updated_sources)
}

/// Compute the effective weight for a source.
/// Returns weight × reliability when the source has at least one reading,
/// otherwise 0.0 (uninitialised source contributes nothing).
pub fn auto_weight(source: SensorSource) -> Float {
  case source.reading_count > 0 {
    True -> source.weight *. source.reliability
    False -> 0.0
  }
}

/// Perform one weighted-average fusion pass across all sources.
///
/// fused = Σ(reading_i × w_i) / Σ(w_i)   where w_i = auto_weight(src_i)
///
/// Sources with auto_weight = 0 are counted as stale.
/// If total_weight = 0, fused_value = 0 and confidence = 0.
pub fn fuse(pipeline: PerceptionPipeline) -> FusedPerception {
  let sources = pipeline.sources

  let weighted_sum =
    list.fold(sources, 0.0, fn(acc, src) {
      acc +. src.last_reading *. auto_weight(src)
    })

  let total_weight =
    list.fold(sources, 0.0, fn(acc, src) { acc +. auto_weight(src) })

  let active_sources = list.filter(sources, fn(src) { auto_weight(src) >. 0.0 })

  let stale_count = list.length(sources) - list.length(active_sources)

  let fused_value = case total_weight >. 0.0 {
    True -> weighted_sum /. total_weight
    False -> 0.0
  }

  let total_reliability =
    list.fold(active_sources, 0.0, fn(acc, src) { acc +. src.reliability })

  let active_count = list.length(active_sources)

  let confidence = case active_sources {
    [] -> 0.0
    _ -> total_reliability /. int.to_float(active_count)
  }

  FusedPerception(
    fused_value: fused_value,
    confidence: confidence,
    source_count: active_count,
    stale_count: stale_count,
  )
}

/// Return a list of source IDs whose last reading is older than `max_age`
/// milliseconds relative to `current_time`.
pub fn detect_stale_sources(
  pipeline: PerceptionPipeline,
  current_time: Int,
  max_age: Int,
) -> List(String) {
  list.filter_map(pipeline.sources, fn(src) {
    case current_time - src.last_timestamp > max_age {
      True -> Ok(src.id)
      False -> Error(Nil)
    }
  })
}

/// Pipeline health score ∈ [0, 1].
/// Computed as 1 - (stale_count / total_count).
/// Returns 1.0 when no sources are registered.
pub fn pipeline_health(pipeline: PerceptionPipeline) -> Float {
  let total = list.length(pipeline.sources)
  case total > 0 {
    False -> 1.0
    True -> {
      let stale_count = pipeline.last_fusion.stale_count
      let ratio = int.to_float(stale_count) /. int.to_float(total)
      1.0 -. ratio
    }
  }
}

/// Human-readable summary of the pipeline state.
pub fn pipeline_summary(pipeline: PerceptionPipeline) -> String {
  let src_count = int.to_string(list.length(pipeline.sources))
  let cycles = int.to_string(pipeline.cycle_count)
  let fused =
    float.to_string(
      float.round(pipeline.last_fusion.fused_value *. 1000.0)
      |> int.to_float()
      |> fn(x) { x /. 1000.0 },
    )
  string.concat([
    "PerceptionPipeline{sources=",
    src_count,
    ", cycles=",
    cycles,
    ", last_fused=",
    fused,
    "}",
  ])
}

// ---------------------------------------------------------------------------
// Spatial mapping API
// ---------------------------------------------------------------------------

/// Create an empty spatial map with given dimensions and resolution.
pub fn spatial_map_new(
  width: Int,
  height: Int,
  resolution: Float,
) -> SpatialMap {
  SpatialMap(cells: [], resolution: resolution, width: width, height: height)
}

/// Update or insert a map cell at (x, y).
/// If a cell already exists at the coordinate, its occupancy and confidence
/// are replaced; otherwise a new cell is appended.
pub fn map_update(
  map: SpatialMap,
  x: Int,
  y: Int,
  occupancy: Float,
  timestamp: Int,
) -> SpatialMap {
  let exists = list.any(map.cells, fn(c) { c.x == x && c.y == y })

  let new_cell =
    MapCell(
      x: x,
      y: y,
      occupancy: occupancy,
      last_observed: timestamp,
      confidence: 1.0,
    )

  let updated_cells = case exists {
    True ->
      list.map(map.cells, fn(c) {
        case c.x == x && c.y == y {
          True -> new_cell
          False -> c
        }
      })
    False -> list.append(map.cells, [new_cell])
  }
  SpatialMap(..map, cells: updated_cells)
}

/// Return all cells within Manhattan distance `radius` of (x, y).
pub fn map_query(
  map: SpatialMap,
  x: Int,
  y: Int,
  radius: Int,
) -> List(MapCell) {
  list.filter(map.cells, fn(c) {
    int.absolute_value(c.x - x) + int.absolute_value(c.y - y) <= radius
  })
}

/// Extract all cells whose occupancy exceeds `threshold` as an obstacle field.
pub fn obstacle_field(map: SpatialMap, threshold: Float) -> ObstacleField {
  let obstacles = list.filter(map.cells, fn(c) { c.occupancy >. threshold })
  ObstacleField(obstacles: obstacles, safe_radius: 1.0)
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Generate an inclusive integer range [from, to] as a list.
fn int_range(from: Int, to: Int) -> List(Int) {
  do_int_range(from, to, [])
  |> list.reverse
}

fn do_int_range(from: Int, to: Int, acc: List(Int)) -> List(Int) {
  case from > to {
    True -> acc
    False -> do_int_range(from + 1, to, [from, ..acc])
  }
}

/// Check whether the straight-line path between (x1,y1) and (x2,y2) is free
/// of obstacles.
///
/// Uses an integer Bresenham-like step: iterates along the axis with the
/// larger delta and checks each integer cell against the obstacle list.
pub fn is_path_clear(
  field: ObstacleField,
  x1: Int,
  y1: Int,
  x2: Int,
  y2: Int,
) -> Bool {
  let dx = int.absolute_value(x2 - x1)
  let dy = int.absolute_value(y2 - y1)
  let steps = case dx > dy {
    True -> dx
    False -> dy
  }
  case steps == 0 {
    True -> True
    False -> {
      let step_indices = int_range(0, steps)
      list.all(step_indices, fn(i) {
        let cx = x1 + { i * { x2 - x1 } } / steps
        let cy = y1 + { i * { y2 - y1 } } / steps
        case list.any(field.obstacles, fn(obs) { obs.x == cx && obs.y == cy }) {
          True -> False
          False -> True
        }
      })
    }
  }
}

/// Manhattan distance from (x, y) to the nearest obstacle in the field.
/// Returns a large sentinel (1_000_000.0) when the field has no obstacles.
pub fn nearest_obstacle_distance(
  field: ObstacleField,
  x: Int,
  y: Int,
) -> Float {
  case field.obstacles {
    [] -> 1_000_000.0
    _ -> {
      list.fold(field.obstacles, 1_000_000.0, fn(min_dist, obs) {
        let d =
          int.to_float(
            int.absolute_value(obs.x - x) + int.absolute_value(obs.y - y),
          )
        case d <. min_dist {
          True -> d
          False -> min_dist
        }
      })
    }
  }
}

/// Fraction of map cells that have been observed at least once (confidence > 0).
/// Returns 0.0 for an empty map.
pub fn map_coverage(map: SpatialMap) -> Float {
  let total_cells = map.width * map.height
  case total_cells > 0 {
    False -> 0.0
    True -> {
      let observed =
        list.length(list.filter(map.cells, fn(c) { c.confidence >. 0.0 }))
      int.to_float(observed) /. int.to_float(total_cells)
    }
  }
}

/// Human-readable summary of the spatial map.
pub fn map_summary(map: SpatialMap) -> String {
  let cell_count = int.to_string(list.length(map.cells))
  let w = int.to_string(map.width)
  let h = int.to_string(map.height)
  string.concat([
    "SpatialMap{",
    w,
    "x",
    h,
    ", cells=",
    cell_count,
    "}",
  ])
}
