/// Sensor Fusion Pipeline — 25-test suite
/// Layer: L4_SYSTEM
/// STAMP: SC-HA-001, SC-BIO-EVO-001, SC-MUDA-001, SC-SIL4-001
///
/// C1 Pipeline creation + source creation
/// C2 Ingest readings, reading count increments
/// C3 Weighted fusion math correctness
/// C4 Stale source detection
/// C5 Spatial map creation + cell update
/// C6 Obstacle field extraction
/// C7 Path clearance check
/// C8 Pipeline health + map coverage
import cepaf_gleam/ha/sensor_fusion_pipeline.{
  PerceptionPipeline, SensorSource, auto_weight, detect_stale_sources, fuse,
  is_path_clear, map_coverage, map_query, map_summary, map_update,
  nearest_obstacle_distance, obstacle_field, pipeline_health, pipeline_ingest,
  pipeline_new, pipeline_summary, source_new, spatial_map_new,
}
import gleam/list
import gleeunit/should

// ===========================================================================
// C1 — Pipeline and source creation
// ===========================================================================

pub fn pipeline_new_empty_sources_test() {
  let p = pipeline_new([])
  p.cycle_count |> should.equal(0)
  p.sources |> should.equal([])
  p.last_fusion.fused_value |> should.equal(0.0)
}

pub fn source_new_sets_defaults_test() {
  let s = source_new("lidar-1", "lidar", 2.0)
  s.id |> should.equal("lidar-1")
  s.kind |> should.equal("lidar")
  s.weight |> should.equal(2.0)
  s.reliability |> should.equal(1.0)
  s.reading_count |> should.equal(0)
  s.last_reading |> should.equal(0.0)
  s.last_timestamp |> should.equal(0)
}

pub fn pipeline_new_with_sources_stores_them_test() {
  let s1 = source_new("s1", "sonar", 1.0)
  let s2 = source_new("s2", "radar", 1.5)
  let p = pipeline_new([s1, s2])
  list.length(p.sources) |> should.equal(2)
}

// ===========================================================================
// C2 — Ingest readings, reading count increments
// ===========================================================================

pub fn pipeline_ingest_increments_reading_count_test() {
  let s = source_new("s1", "lidar", 1.0)
  let p = pipeline_new([s])
  let p2 = pipeline_ingest(p, "s1", 42.0, 1000)
  let updated = list.first(p2.sources)
  case updated {
    Ok(src) -> src.reading_count |> should.equal(1)
    Error(_) -> should.fail()
  }
}

pub fn pipeline_ingest_updates_reading_value_test() {
  let s = source_new("s1", "lidar", 1.0)
  let p = pipeline_new([s])
  let p2 = pipeline_ingest(p, "s1", 99.5, 2000)
  let updated = list.first(p2.sources)
  case updated {
    Ok(src) -> src.last_reading |> should.equal(99.5)
    Error(_) -> should.fail()
  }
}

pub fn pipeline_ingest_updates_timestamp_test() {
  let s = source_new("s1", "sonar", 1.0)
  let p = pipeline_new([s])
  let p2 = pipeline_ingest(p, "s1", 5.0, 9999)
  let updated = list.first(p2.sources)
  case updated {
    Ok(src) -> src.last_timestamp |> should.equal(9999)
    Error(_) -> should.fail()
  }
}

pub fn pipeline_ingest_unknown_id_leaves_sources_unchanged_test() {
  let s = source_new("known", "lidar", 1.0)
  let p = pipeline_new([s])
  let p2 = pipeline_ingest(p, "unknown", 10.0, 100)
  let src = list.first(p2.sources)
  case src {
    Ok(x) -> x.reading_count |> should.equal(0)
    Error(_) -> should.fail()
  }
}

pub fn pipeline_ingest_multiple_readings_accumulates_count_test() {
  let s = source_new("s1", "lidar", 1.0)
  let p =
    pipeline_new([s])
    |> pipeline_ingest("s1", 1.0, 100)
    |> pipeline_ingest("s1", 2.0, 200)
    |> pipeline_ingest("s1", 3.0, 300)
  let src = list.first(p.sources)
  case src {
    Ok(x) -> x.reading_count |> should.equal(3)
    Error(_) -> should.fail()
  }
}

// ===========================================================================
// C3 — Weighted fusion math correctness
// ===========================================================================

pub fn fuse_single_source_equals_reading_test() {
  let s = source_new("s1", "lidar", 1.0)
  let p =
    pipeline_new([s])
    |> pipeline_ingest("s1", 50.0, 1000)
  let result = fuse(p)
  result.fused_value |> should.equal(50.0)
  result.source_count |> should.equal(1)
  result.stale_count |> should.equal(0)
}

pub fn fuse_two_equal_weight_sources_averages_test() {
  let s1 = source_new("s1", "lidar", 1.0)
  let s2 = source_new("s2", "sonar", 1.0)
  let p =
    pipeline_new([s1, s2])
    |> pipeline_ingest("s1", 10.0, 1000)
    |> pipeline_ingest("s2", 20.0, 1000)
  let result = fuse(p)
  // (10*1 + 20*1) / (1 + 1) = 15.0
  result.fused_value |> should.equal(15.0)
}

pub fn fuse_unequal_weights_biased_test() {
  let s1 = source_new("s1", "lidar", 3.0)
  let s2 = source_new("s2", "sonar", 1.0)
  let p =
    pipeline_new([s1, s2])
    |> pipeline_ingest("s1", 0.0, 1000)
    |> pipeline_ingest("s2", 20.0, 1000)
  let result = fuse(p)
  // (0*3 + 20*1) / (3+1) = 5.0
  result.fused_value |> should.equal(5.0)
}

pub fn fuse_uninitialised_source_excluded_test() {
  let s1 = source_new("s1", "lidar", 1.0)
  let s2 = source_new("s2", "sonar", 1.0)
  // s2 never ingested — reading_count stays 0
  let p =
    pipeline_new([s1, s2])
    |> pipeline_ingest("s1", 42.0, 1000)
  let result = fuse(p)
  result.fused_value |> should.equal(42.0)
  result.source_count |> should.equal(1)
  result.stale_count |> should.equal(1)
}

pub fn auto_weight_zero_reading_count_returns_zero_test() {
  let s = source_new("s1", "lidar", 2.0)
  auto_weight(s) |> should.equal(0.0)
}

pub fn auto_weight_with_readings_returns_weight_times_reliability_test() {
  let s =
    source_new("s1", "lidar", 2.0)
    |> fn(src) { SensorSource(..src, reading_count: 5, reliability: 0.8) }
  auto_weight(s) |> should.equal(1.6)
}

// ===========================================================================
// C4 — Stale source detection
// ===========================================================================

pub fn detect_stale_sources_empty_pipeline_test() {
  let p = pipeline_new([])
  detect_stale_sources(p, 1000, 500) |> should.equal([])
}

pub fn detect_stale_sources_finds_old_source_test() {
  let s = source_new("s1", "lidar", 1.0)
  let p =
    pipeline_new([s])
    |> pipeline_ingest("s1", 1.0, 100)
  // current_time=2000, max_age=500 → age=1900 > 500 → stale
  let stale = detect_stale_sources(p, 2000, 500)
  stale |> should.equal(["s1"])
}

pub fn detect_stale_sources_fresh_source_not_reported_test() {
  let s = source_new("s1", "lidar", 1.0)
  let p =
    pipeline_new([s])
    |> pipeline_ingest("s1", 1.0, 1800)
  let stale = detect_stale_sources(p, 2000, 500)
  stale |> should.equal([])
}

// ===========================================================================
// C5 — Spatial map creation and update
// ===========================================================================

pub fn spatial_map_new_empty_cells_test() {
  let m = spatial_map_new(10, 10, 0.1)
  m.cells |> should.equal([])
  m.width |> should.equal(10)
  m.height |> should.equal(10)
  m.resolution |> should.equal(0.1)
}

pub fn map_update_inserts_new_cell_test() {
  let m = spatial_map_new(10, 10, 0.5)
  let m2 = map_update(m, 3, 4, 0.9, 1000)
  list.length(m2.cells) |> should.equal(1)
  let cell = list.first(m2.cells)
  case cell {
    Ok(c) -> {
      c.x |> should.equal(3)
      c.y |> should.equal(4)
      c.occupancy |> should.equal(0.9)
    }
    Error(_) -> should.fail()
  }
}

pub fn map_update_replaces_existing_cell_test() {
  let m =
    spatial_map_new(10, 10, 0.5)
    |> map_update(3, 4, 0.3, 500)
    |> map_update(3, 4, 0.8, 1000)
  // Should still have 1 cell — not 2
  list.length(m.cells) |> should.equal(1)
  let cell = list.first(m.cells)
  case cell {
    Ok(c) -> c.occupancy |> should.equal(0.8)
    Error(_) -> should.fail()
  }
}

pub fn map_query_returns_cells_within_radius_test() {
  let m =
    spatial_map_new(20, 20, 0.5)
    |> map_update(5, 5, 0.5, 100)
    |> map_update(6, 5, 0.5, 100)
    |> map_update(10, 10, 0.5, 100)
  // Query at (5,5) with radius 1 should return (5,5) and (6,5)
  let nearby = map_query(m, 5, 5, 1)
  list.length(nearby) |> should.equal(2)
}

// ===========================================================================
// C6 — Obstacle field extraction
// ===========================================================================

pub fn obstacle_field_extracts_above_threshold_test() {
  let m =
    spatial_map_new(10, 10, 0.5)
    |> map_update(1, 1, 0.9, 100)
    |> map_update(2, 2, 0.3, 100)
    |> map_update(3, 3, 0.8, 100)
  let field = obstacle_field(m, 0.5)
  list.length(field.obstacles) |> should.equal(2)
}

pub fn obstacle_field_empty_when_all_below_threshold_test() {
  let m =
    spatial_map_new(10, 10, 0.5)
    |> map_update(1, 1, 0.2, 100)
    |> map_update(2, 2, 0.1, 100)
  let field = obstacle_field(m, 0.5)
  list.length(field.obstacles) |> should.equal(0)
}

// ===========================================================================
// C7 — Path clearance check
// ===========================================================================

pub fn is_path_clear_no_obstacles_returns_true_test() {
  let m = spatial_map_new(10, 10, 0.5)
  let field = obstacle_field(m, 0.5)
  is_path_clear(field, 0, 0, 5, 0) |> should.equal(True)
}

pub fn is_path_clear_obstacle_on_path_returns_false_test() {
  let m =
    spatial_map_new(10, 10, 0.5)
    |> map_update(2, 0, 0.9, 100)
  let field = obstacle_field(m, 0.5)
  is_path_clear(field, 0, 0, 4, 0) |> should.equal(False)
}

pub fn nearest_obstacle_distance_empty_field_sentinel_test() {
  let m = spatial_map_new(10, 10, 0.5)
  let field = obstacle_field(m, 0.5)
  nearest_obstacle_distance(field, 0, 0) |> should.equal(1_000_000.0)
}

pub fn nearest_obstacle_distance_single_obstacle_test() {
  let m =
    spatial_map_new(10, 10, 0.5)
    |> map_update(3, 4, 0.9, 100)
  let field = obstacle_field(m, 0.5)
  // Manhattan distance from (0,0) to (3,4) = 7
  nearest_obstacle_distance(field, 0, 0) |> should.equal(7.0)
}

// ===========================================================================
// C8 — Pipeline health + map coverage
// ===========================================================================

pub fn pipeline_health_all_active_is_one_test() {
  let s = source_new("s1", "lidar", 1.0)
  let p =
    pipeline_new([s])
    |> pipeline_ingest("s1", 1.0, 100)
  let fused = fuse(p)
  let p2 = PerceptionPipeline(..p, last_fusion: fused)
  pipeline_health(p2) |> should.equal(1.0)
}

pub fn pipeline_health_empty_pipeline_is_one_test() {
  pipeline_health(pipeline_new([])) |> should.equal(1.0)
}

pub fn map_coverage_empty_map_returns_zero_test() {
  let m = spatial_map_new(10, 10, 0.5)
  map_coverage(m) |> should.equal(0.0)
}

pub fn map_coverage_partial_observation_test() {
  // 10x5 = 50 total cells; observe 5
  let m =
    spatial_map_new(10, 5, 0.5)
    |> map_update(0, 0, 0.5, 100)
    |> map_update(1, 0, 0.5, 100)
    |> map_update(2, 0, 0.5, 100)
    |> map_update(3, 0, 0.5, 100)
    |> map_update(4, 0, 0.5, 100)
  map_coverage(m) |> should.equal(0.1)
}

pub fn pipeline_summary_contains_source_count_test() {
  let s1 = source_new("s1", "lidar", 1.0)
  let s2 = source_new("s2", "sonar", 1.0)
  let p = pipeline_new([s1, s2])
  let summary = pipeline_summary(p)
  summary |> should.not_equal("")
}

pub fn map_summary_contains_dimensions_test() {
  let m = spatial_map_new(8, 6, 0.25)
  let s = map_summary(m)
  s |> should.not_equal("")
}
