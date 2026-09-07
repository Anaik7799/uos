import cepaf_gleam/api/denotational_intent_router
import cepaf_gleam/verification/browser_emulation_bridge
import cepaf_gleam/verification/dmc_biosemiotics_interlock
import cepaf_gleam/verification/evidence_truth
import gleam/list
import gleeunit/should

pub fn verification_endpoint_shared_state_test() {
  let decision = evidence_truth.unrun()
  decision.status |> should.equal("UNRUN")
  decision.admitted |> should.be_false()
  decision.metrics_available |> should.be_false()
}

pub fn denotational_intent_authorization_test() {
  let safe_payload =
    denotational_intent_router.IntentPayload(
      actor: "test_operator",
      action: "verify_intent",
      target: "storage_subsystem",
      device_serial: "SAFE_STORAGE_NVME_01",
    )
  let resp = denotational_intent_router.evaluate_intent_api(safe_payload)
  resp.authorized |> should.be_true()
  resp.status_code |> should.equal(200)

  let locked_payload =
    denotational_intent_router.IntentPayload(
      actor: "malicious_actor",
      action: "wipe_os_disk",
      target: "storage_subsystem",
      device_serial: dmc_biosemiotics_interlock.hard_denied_system_os_serial,
    )
  let locked_resp =
    denotational_intent_router.evaluate_intent_api(locked_payload)
  locked_resp.authorized |> should.be_false()
  locked_resp.status_code |> should.equal(403)
}

pub fn dmc_rocha_and_storage_lock_test() {
  let cut = dmc_biosemiotics_interlock.verify_rocha_cut(True)
  cut |> should.equal(dmc_biosemiotics_interlock.RochaDecoupled)

  let lock =
    dmc_biosemiotics_interlock.check_hardware_safety_interlock(
      dmc_biosemiotics_interlock.hard_denied_system_os_serial,
    )
  case lock {
    dmc_biosemiotics_interlock.AccessDenied(_) -> should.be_true(True)
    dmc_biosemiotics_interlock.AccessGranted -> should.be_true(False)
  }
}

pub fn browser_suites_aggregation_test() {
  let suites = [
    browser_emulation_bridge.BrowserSuiteSpec(
      id: "BS-01",
      name: "Playwright E2E",
      engine: browser_emulation_bridge.C3IPlaywright,
      target_route: "/dashboard",
      test_count: 18,
      efficacy: 1.0,
      effectiveness: 1.0,
    ),
    browser_emulation_bridge.BrowserSuiteSpec(
      id: "BS-02",
      name: "Wallaby Browser Integration",
      engine: browser_emulation_bridge.C3IWallaby,
      target_route: "/planning",
      test_count: 14,
      efficacy: 1.0,
      effectiveness: 1.0,
    ),
  ]
  let results = list.map(suites, browser_emulation_bridge.execute_browser_suite)
  let metrics = browser_emulation_bridge.aggregate_browser_metrics(results)
  metrics.total_suites |> should.equal(2)
  metrics.total_tests |> should.equal(32)
  metrics.all_passing |> should.be_true()
}
