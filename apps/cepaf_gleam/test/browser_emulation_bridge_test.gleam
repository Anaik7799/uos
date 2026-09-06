import cepaf_gleam/verification/browser_emulation_bridge.{
  BrowserSuiteSpec, C3IPlaywright, C3IWallaby, IndrajaalCdp, ZigvmTyxml,
  aggregate_browser_metrics, execute_browser_suite,
}
import gleam/list
import gleeunit/should

pub fn execute_single_suite_test() {
  let suite =
    BrowserSuiteSpec(
      id: "B-C3I-01",
      name: "Planning E2E Suite",
      engine: C3IPlaywright,
      target_route: "/planning",
      test_count: 6,
      efficacy: 0.95,
      effectiveness: 0.96,
    )
  let result = execute_browser_suite(suite)
  should.equal(result.suite_id, "B-C3I-01")
  should.equal(result.name, "Planning E2E Suite")
  should.equal(result.passed_count, 6)
  should.equal(result.failed_count, 0)
  should.equal(result.efficacy, 0.95)
  should.equal(result.effectiveness, 0.96)
}

pub fn aggregate_multiple_suites_metrics_test() {
  let suites = [
    BrowserSuiteSpec(
      "B-C3I-01",
      "Planning E2E",
      C3IPlaywright,
      "/planning",
      6,
      0.95,
      0.96,
    ),
    BrowserSuiteSpec(
      "B-IND-01",
      "31-Page Nav",
      IndrajaalCdp,
      "/",
      31,
      0.98,
      0.99,
    ),
    BrowserSuiteSpec(
      "B-WAL-01",
      "Wallaby Flow",
      C3IWallaby,
      "/dashboard",
      4,
      0.9,
      0.92,
    ),
    BrowserSuiteSpec(
      "B-ZIG-01",
      "Tyxml Structural",
      ZigvmTyxml,
      "/docs",
      10,
      1.0,
      1.0,
    ),
  ]
  let results = list.map(suites, execute_browser_suite)
  let metrics = aggregate_browser_metrics(results)
  should.equal(metrics.total_suites, 4)
  should.equal(metrics.total_tests, 51)
  should.equal(metrics.all_passing, True)
  // Mean efficacy: (0.95 + 0.98 + 0.90 + 1.0) / 4 = 3.83 / 4 = 0.9575
  // Mean effectiveness: (0.96 + 0.99 + 0.92 + 1.0) / 4 = 3.87 / 4 = 0.9675
  should.equal(metrics.mean_efficacy, 0.9575)
  should.equal(metrics.mean_effectiveness, 0.9675)
}
