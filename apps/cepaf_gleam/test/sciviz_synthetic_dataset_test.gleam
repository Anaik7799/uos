// sciviz_synthetic_dataset_test.gleam — Test suite for SciViz Synthetic Datasets and Feature Envelopes
// Validates mathematical invariants, bounds, and properties across all 15 visual envelopes.

import gleam/list
import gleeunit/should
import cepaf_gleam/sciviz/synthetic_dataset.{
  generate_composite_envelope,
  generate_correlation_envelope, generate_flow_envelope,
  generate_genomic_envelope, generate_geospatial_envelope,
  generate_hierarchy_envelope, generate_marginal_envelope,
  generate_mosaic_envelope, generate_network_envelope, generate_ridge_envelope,
  generate_spline_envelope, generate_survival_envelope,
  generate_ternary_envelope, generate_timeseries_envelope,
  generate_uncertainty_envelope, get_all_feature_envelopes,
}

pub fn all_envelopes_count_test() {
  let envelopes = get_all_feature_envelopes()
  list.length(envelopes)
  |> should.equal(15)

  list.all(envelopes, fn(env) { env.verified })
  |> should.be_true()
}

pub fn uncertainty_envelope_test() {
  let dist = generate_uncertainty_envelope()
  dist.sample_size |> should.equal(10_000)
  dist.mean |> should.equal(260.0)
  list.length(dist.intervals) |> should.equal(4)
  list.length(dist.density_curve) |> should.equal(9)
}

pub fn network_envelope_test() {
  let net = generate_network_envelope()
  net.node_count |> should.equal(5)
  net.edge_count |> should.equal(6)
  net.diameter |> should.equal(2)
  should.be_true(net.density >. 0.5)
}

pub fn flow_envelope_test() {
  let flow = generate_flow_envelope()
  flow.total_inflow |> should.equal(100.0)
  flow.total_outflow |> should.equal(70.0)
  flow.retention_rate |> should.equal(0.70)
  list.length(flow.strata) |> should.equal(6)
  list.length(flow.flows) |> should.equal(5)
}

pub fn hierarchy_envelope_test() {
  let hier = generate_hierarchy_envelope()
  hier.total_weight |> should.equal(100.0)
  hier.max_depth |> should.equal(2)
  hier.node_count |> should.equal(4)
}

pub fn survival_envelope_test() {
  let surv = generate_survival_envelope()
  surv.sample_size |> should.equal(1000)
  surv.median_survival_hours |> should.equal(242.5)
  list.length(surv.steps) |> should.equal(7)
}

pub fn ridge_envelope_test() {
  let ridge = generate_ridge_envelope()
  ridge.facet_count |> should.equal(4)
  ridge.overlap_ratio |> should.equal(0.65)
  list.length(ridge.facets) |> should.equal(4)
}

pub fn correlation_envelope_test() {
  let corr = generate_correlation_envelope()
  list.length(corr.variables) |> should.equal(5)
  list.length(corr.cells) |> should.equal(10)
  should.be_true(corr.determinant >. 0.0)
}

pub fn geospatial_envelope_test() {
  let geo = generate_geospatial_envelope()
  list.length(geo.vectors) |> should.equal(6)
  should.be_true(geo.divergence_max >. 0.0)
  should.be_true(geo.vorticity_max >. 0.0)
}

pub fn genomic_envelope_test() {
  let gen = generate_genomic_envelope()
  gen.total_variants |> should.equal(850_000)
  gen.significance_threshold |> should.equal(8.0)
  list.length(gen.variants) |> should.equal(8)
}

pub fn ternary_envelope_test() {
  let tern = generate_ternary_envelope()
  tern.is_normalized |> should.equal(True)
  list.length(tern.points) |> should.equal(4)
  list.each(tern.points, fn(pt) {
    let sum = pt.a +. pt.b +. pt.c
    should.be_true(sum >=. 0.999 && sum <=. 1.001)
  })
}

pub fn timeseries_envelope_test() {
  let ts = generate_timeseries_envelope()
  ts.series_length |> should.equal(5)
  ts.horizon |> should.equal(3)
  list.length(ts.points) |> should.equal(8)
}

pub fn spline_envelope_test() {
  let spl = generate_spline_envelope()
  spl.degrees_of_freedom |> should.equal(5)
  list.length(spl.quantiles) |> should.equal(3)
  list.length(spl.knots) |> should.equal(3)
}

pub fn mosaic_envelope_test() {
  let mos = generate_mosaic_envelope()
  mos.total_observations |> should.equal(1000)
  list.length(mos.cells) |> should.equal(4)
  should.be_true(mos.p_value <. 0.05)
}

pub fn marginal_envelope_test() {
  let marg = generate_marginal_envelope()
  list.length(marg.sample_points) |> should.equal(9)
  should.be_true(marg.pearson_r <. -0.90)
}

pub fn composite_envelope_test() {
  let comp = generate_composite_envelope()
  comp.alignment_verified |> should.equal(True)
  list.length(comp.panels) |> should.equal(3)
}
