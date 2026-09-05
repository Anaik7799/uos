import cepaf_gleam/verification/unified_verification_supervisor.{
  type PatrolReport, PatrolReport, patrol_healthy, run_verification_patrol,
}
import gleeunit/should

pub fn system_patrol_execution_test() {
  let report: PatrolReport = run_verification_patrol()
  should.equal(report.web_checks_count, 18)
  should.equal(report.browser_suites_count, 64)
  should.equal(report.ocaml_subsystems_count, 17)
  should.equal(report.all_green, True)
  should.equal(patrol_healthy(report), True)
  should.equal(
    report,
    PatrolReport(
      web_checks_count: 18,
      browser_suites_count: 64,
      ocaml_subsystems_count: 17,
      all_green: True,
    ),
  )
}
