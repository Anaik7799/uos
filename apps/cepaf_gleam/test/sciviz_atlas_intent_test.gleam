//// [C3I-SIL6-MSTS] TEST CONTRACT
//// <c3i-test>
////   <identity><module>test/sciviz_atlas_intent_test</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL..L9_SOVEREIGNTY</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SCIVIZ-001, SC-INTENT-ATLAS-001, SC-CHECKLIST-001</stamp-controls></compliance>
//// </c3i-test>

import gleeunit/should
import gleam/option.{None}
import gleam/string
import cepaf_gleam/sciviz/atlas_intent.{
  type VisualAtlasState, AnalyzeCorrelation, AtlasMorphism,
  CartesianCoord, ExploreDistribution, MarkPoint, MarkLine,
  U0PhysicalCanvas, U1DataDomain, U2StatMeasure, U3NormalizedUnit,
  U4CoordManifold, U5FacetSubspaces, U6GeomGrob, U7GuideInverse,
  U8ThemedSurface, U9TelemetryStream, ValuationSuccess, ValuationVetoed,
  VisualAtlasState, chart_to_int, chart_to_string, compose_morphisms,
  default_aesthetic_intent, evaluate_visual_intent, int_to_chart,
}
import cepaf_gleam/sciviz/schema.{
  Point2D, Scale2D, SciVizPlot, default_dark_cockpit_theme,
}

fn initial_test_state() -> VisualAtlasState {
  let default_scale =
    Scale2D(
      x_min: 0.0,
      x_max: 100.0,
      y_min: 0.0,
      y_max: 100.0,
      target_w: 800.0,
      target_h: 500.0,
    )

  let plot =
    SciVizPlot(
      title: "Initial Test State",
      width: 800.0,
      height: 500.0,
      theme: default_dark_cockpit_theme(),
      scale: default_scale,
      data_series: [],
      geoms: [],
      layers: [],
      scene_root: schema.SceneNode(
        id: "root",
        translate: Point2D(0.0, 0.0),
        rotate_deg: 0.0,
        scale: 1.0,
        visual: schema.VisualCircle(0.0, 0.0, 0.0, "none"),
        children: [],
      ),
    )

  VisualAtlasState(
    chart: U0PhysicalCanvas,
    epoch: 0,
    plot: plot,
    constitutional_health: 1.0,
    receipt_sha256: "0000000000000000000000000000000000000000000000000000000000000000",
  )
}

pub fn visual_charts_bijective_mapping_test() {
  chart_to_int(U0PhysicalCanvas) |> should.equal(0)
  chart_to_int(U1DataDomain) |> should.equal(1)
  chart_to_int(U2StatMeasure) |> should.equal(2)
  chart_to_int(U3NormalizedUnit) |> should.equal(3)
  chart_to_int(U4CoordManifold) |> should.equal(4)
  chart_to_int(U5FacetSubspaces) |> should.equal(5)
  chart_to_int(U6GeomGrob) |> should.equal(6)
  chart_to_int(U7GuideInverse) |> should.equal(7)
  chart_to_int(U8ThemedSurface) |> should.equal(8)
  chart_to_int(U9TelemetryStream) |> should.equal(9)

  int_to_chart(0) |> should.equal(Ok(U0PhysicalCanvas))
  int_to_chart(4) |> should.equal(Ok(U4CoordManifold))
  int_to_chart(9) |> should.equal(Ok(U9TelemetryStream))
  int_to_chart(10) |> should.be_error

  chart_to_string(U4CoordManifold) |> should.equal("U4_CoordManifold")
  chart_to_string(U6GeomGrob) |> should.equal("U6_GeomGrob")
}

pub fn morphism_composition_and_cocycle_test() {
  let m01 =
    AtlasMorphism(
      source_chart: U0PhysicalCanvas,
      target_chart: U1DataDomain,
      morphism_name: "ingest",
      is_bijective: True,
    )
  let m12 =
    AtlasMorphism(
      source_chart: U1DataDomain,
      target_chart: U2StatMeasure,
      morphism_name: "stat_bin",
      is_bijective: True,
    )
  let m24 =
    AtlasMorphism(
      source_chart: U2StatMeasure,
      target_chart: U4CoordManifold,
      morphism_name: "coord_polar",
      is_bijective: True,
    )

  // Cocycle composition phi_12 o phi_01 = phi_02
  let composed = compose_morphisms(m01, m12)
  composed |> should.be_ok

  case composed {
    Ok(m02) -> {
      m02.source_chart |> should.equal(U0PhysicalCanvas)
      m02.target_chart |> should.equal(U2StatMeasure)
      m02.morphism_name |> should.equal("ingest ∘ stat_bin")

      // Associativity (m01 o m12) o m24
      let composed_full = compose_morphisms(m02, m24)
      composed_full |> should.be_ok
    }
    Error(_) -> panic as "Composition failed unexpectedly"
  }

  // Mismatch error detection
  let mismatch = compose_morphisms(m01, m24)
  mismatch |> should.be_error
}

pub fn declarative_intent_valuation_pipeline_test() {
  let state = initial_test_state()
  let points = [
    Point2D(10.0, 25.0),
    Point2D(20.0, 45.0),
    Point2D(30.0, 85.0),
    Point2D(40.0, 60.0),
  ]

  let intent =
    atlas_intent.VisualIntent(
      intent_id: "intent-telemetry-perf-01",
      goal: AnalyzeCorrelation(x_metric: "cpu_load", y_metric: "latency_us"),
      dataset_name: "c3i_cluster_telemetry",
      data_points: points,
      aesthetics: default_aesthetic_intent("cpu_load", "latency_us"),
      marks: [MarkPoint(size: 5.0, color: "#38bdf8"), MarkLine(stroke_width: 2.0, color: "#10b981")],
      coordinate: CartesianCoord,
      faceting: None,
      theme: default_dark_cockpit_theme(),
      target_chart: U6GeomGrob,
      preserves_zero_muda: True,
      target_drive_serial: "SAFE_NVME_VOLUME_01",
    )

  let outcome = evaluate_visual_intent(intent, state)
  case outcome {
    ValuationSuccess(final_state, svg) -> {
      final_state.chart |> should.equal(U6GeomGrob)
      final_state.epoch |> should.equal(1)
      string.length(final_state.receipt_sha256) |> should.equal(64)
      string.contains(svg, "<svg") |> should.be_true
      string.contains(svg, "<circle") |> should.be_true
      string.contains(svg, "Zero-Muda Pure SVG") |> should.be_true
      string.contains(svg, "<script") |> should.be_false
    }
    ValuationVetoed(_, reason) -> panic as { "Valuation failed: " <> reason }
  }
}

pub fn hardware_safety_storage_interlock_test() {
  let state = initial_test_state()
  let dangerous_intent =
    atlas_intent.VisualIntent(
      intent_id: "intent-malicious-wipe",
      goal: ExploreDistribution(metric: "raw_bytes"),
      dataset_name: "denied_host_nvme",
      data_points: [Point2D(1.0, 1.0)],
      aesthetics: default_aesthetic_intent("x", "y"),
      marks: [MarkPoint(size: 3.0, color: "#ff0000")],
      coordinate: CartesianCoord,
      faceting: None,
      theme: default_dark_cockpit_theme(),
      target_chart: U1DataDomain,
      preserves_zero_muda: True,
      target_drive_serial: "25503L801736", // HARD DENIED OS SERIAL
    )

  let outcome = evaluate_visual_intent(dangerous_intent, state)
  case outcome {
    ValuationSuccess(_, _) -> panic as "Dangerous intent must be vetoed"
    ValuationVetoed(id, reason) -> {
      id |> should.equal("intent-malicious-wipe")
      string.contains(reason, "25503L801736") |> should.be_true
    }
  }
}

pub fn zero_muda_enforcement_test() {
  let state = initial_test_state()
  let muda_intent =
    atlas_intent.VisualIntent(
      intent_id: "intent-bevy-injection",
      goal: ExploreDistribution(metric: "entity_count"),
      dataset_name: "muda_dataset",
      data_points: [Point2D(1.0, 1.0)],
      aesthetics: default_aesthetic_intent("x", "y"),
      marks: [MarkPoint(size: 3.0, color: "#ff0000")],
      coordinate: CartesianCoord,
      faceting: None,
      theme: default_dark_cockpit_theme(),
      target_chart: U1DataDomain,
      preserves_zero_muda: False, // MUDA VIOLATION
      target_drive_serial: "SAFE_NVME_VOLUME_01",
    )

  let outcome = evaluate_visual_intent(muda_intent, state)
  case outcome {
    ValuationSuccess(_, _) -> panic as "Muda intent must be vetoed"
    ValuationVetoed(id, reason) -> {
      id |> should.equal("intent-bevy-injection")
      string.contains(reason, "ZeroMudaViolation") |> should.be_true
    }
  }
}

pub fn constitutional_health_degraded_veto_test() {
  let degraded_state = VisualAtlasState(..initial_test_state(), constitutional_health: 0.70)
  let intent =
    atlas_intent.VisualIntent(
      intent_id: "intent-on-degraded-system",
      goal: ExploreDistribution(metric: "latency"),
      dataset_name: "telemetry",
      data_points: [Point2D(1.0, 1.0)],
      aesthetics: default_aesthetic_intent("x", "y"),
      marks: [MarkPoint(size: 3.0, color: "#ff0000")],
      coordinate: CartesianCoord,
      faceting: None,
      theme: default_dark_cockpit_theme(),
      target_chart: U6GeomGrob,
      preserves_zero_muda: True,
      target_drive_serial: "SAFE_NVME_VOLUME_01",
    )

  let outcome = evaluate_visual_intent(intent, degraded_state)
  case outcome {
    ValuationSuccess(_, _) -> panic as "Degraded system intent must be vetoed"
    ValuationVetoed(id, reason) -> {
      id |> should.equal("intent-on-degraded-system")
      string.contains(reason, "SystemHealthDegraded") |> should.be_true
    }
  }
}
