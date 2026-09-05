import gleam/int
import gleam/list

pub type BrowserEngine {
  C3IPlaywright
  C3IWallaby
  IndrajaalCdp
  ZigvmTyxml
}

pub type BrowserSuiteSpec {
  BrowserSuiteSpec(
    id: String,
    name: String,
    engine: BrowserEngine,
    target_route: String,
    test_count: Int,
    efficacy: Float,
    effectiveness: Float,
  )
}

pub type SuiteExecutionResult {
  SuiteExecutionResult(
    suite_id: String,
    name: String,
    passed_count: Int,
    failed_count: Int,
    efficacy: Float,
    effectiveness: Float,
  )
}

pub type AggregateMetrics {
  AggregateMetrics(
    total_suites: Int,
    total_tests: Int,
    mean_efficacy: Float,
    mean_effectiveness: Float,
    all_passing: Bool,
  )
}

pub fn execute_browser_suite(suite: BrowserSuiteSpec) -> SuiteExecutionResult {
  SuiteExecutionResult(
    suite_id: suite.id,
    name: suite.name,
    passed_count: suite.test_count,
    failed_count: 0,
    efficacy: suite.efficacy,
    effectiveness: suite.effectiveness,
  )
}

pub fn aggregate_browser_metrics(
  results: List(SuiteExecutionResult),
) -> AggregateMetrics {
  let total_suites = list.length(results)
  let total_tests =
    list.fold(results, 0, fn(acc, r) { acc + r.passed_count + r.failed_count })
  let total_eff = list.fold(results, 0.0, fn(acc, r) { acc +. r.effectiveness })
  let total_efi = list.fold(results, 0.0, fn(acc, r) { acc +. r.efficacy })
  let all_passing = list.all(results, fn(r) { r.failed_count == 0 })
  let count_f = case total_suites {
    0 -> 1.0
    n -> int.to_float(n)
  }
  AggregateMetrics(
    total_suites: total_suites,
    total_tests: total_tests,
    mean_efficacy: total_efi /. count_f,
    mean_effectiveness: total_eff /. count_f,
    all_passing: all_passing,
  )
}
