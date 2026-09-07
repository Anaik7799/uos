// =============================================================================
// [C3I-SIL6-MSTS] BROWSER HARNESS TEST SUITE (SC-CHECKLIST-001, V01)
// =============================================================================

import cepaf_gleam/ui/browser_harness.{PageVerificationReceipt}
import gleam/list
import gleeunit/should

pub fn scan_html_content_cockpit_test() {
  let sample_html =
    "<!DOCTYPE html><html><head><title>UOS Cockpit</title></head><body>"
    <> "<div class=\"header\"><h1>Unified Operational System</h1></div>"
    <> "<div class=\"badge status-healthy\">PASS</div>"
    <> "<div class=\"checklist-accordion\">CHK-01-TIME 20260907-1655- PASS</div>"
    <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/\">Cockpit</a>"
    <> "<div class=\"fractal-layer\">#fractal-l0</div>"
    <> "<div class=\"storage-lock\">Root OS NVMe Serial 25503L801736 Locked</div>"
    <> "<table class=\"grid\"><tr><td>Metric</td><td>Value</td></tr><tr><td>QPS</td><td>50770</td></tr></table>"
    <> "</body></html>"

  let receipt =
    browser_harness.scan_html_content("/", "Cockpit Dashboard", sample_html)

  receipt.status_code |> should.equal(200)
  receipt.has_tailscale_fqdn |> should.be_true
  receipt.has_checklist_accordion |> should.be_true
  receipt.has_storage_serial_lock |> should.be_true
  receipt.has_zero_muda_purity |> should.be_true
  receipt.c1_structure_passed |> should.be_true
  receipt.c2_status_badges_passed |> should.be_true
  receipt.c3_data_grids_passed |> should.be_true
  receipt.all_passed |> should.be_true
  receipt.passed_checkpoints |> should.equal(18)
}

pub fn evaluate_crawl_summary_test() {
  let r1 =
    PageVerificationReceipt(
      route: "/",
      title: "Cockpit Dashboard",
      status_code: 200,
      html_byte_size: 1024,
      element_count: 25,
      has_checklist_accordion: True,
      has_tailscale_fqdn: True,
      has_timestamp_prefix: True,
      has_fractal_tag: True,
      has_zero_muda_purity: True,
      has_storage_serial_lock: True,
      c1_structure_passed: True,
      c2_status_badges_passed: True,
      c3_data_grids_passed: True,
      shannon_entropy: 2.68,
      passed_checkpoints: 18,
      total_checkpoints: 18,
      all_passed: True,
    )

  let r2 =
    PageVerificationReceipt(
      route: "/planning",
      title: "Sa-Plan Execution Cockpit",
      status_code: 200,
      html_byte_size: 2048,
      element_count: 40,
      has_checklist_accordion: True,
      has_tailscale_fqdn: True,
      has_timestamp_prefix: True,
      has_fractal_tag: True,
      has_zero_muda_purity: True,
      has_storage_serial_lock: True,
      c1_structure_passed: True,
      c2_status_badges_passed: True,
      c3_data_grids_passed: True,
      shannon_entropy: 2.72,
      passed_checkpoints: 18,
      total_checkpoints: 18,
      all_passed: True,
    )

  let summary = browser_harness.evaluate_crawl([r1, r2])
  summary.total_pages_scanned |> should.equal(2)
  summary.passed_pages_count |> should.equal(2)
  summary.failed_pages_count |> should.equal(0)
  summary.compliance_percentage |> should.equal(100.0)
  summary.total_checkpoints_passed |> should.equal(36)
}

pub fn canonical_routes_count_test() {
  let count = list.length(browser_harness.canonical_routes)
  { count >= 20 } |> should.be_true
}

pub fn execute_operator_journey_scenario_test() {
  let mock_router = fn(route: String) -> String {
    case route {
      "/" -> "<html><body>Cockpit nas-1.tail55d152.ts.net:4100</body></html>"
      "/ag-ui/cockpit" -> "<html><body>AG-UI 32-Event Real-Time Cockpit SIL-6 FRACTAL LOCK: 25503L801736</body></html>"
      "/ag-ui/manifest" -> "{\"protocol\":\"AG-UI-v1\",\"status\":\"compliant\"}"
      "/checklist" -> "<html><body>Universal Comprehensive Verification Checklist CHK-01-TIME</body></html>"
      "/planning" -> "<html><body>Planning nas-1.tail55d152.ts.net:4100</body></html>"
      "/mirage" -> "<html><body>MirageOS 25503L801736</body></html>"
      _ -> "404 Not Found"
    }
  }

  let receipt = browser_harness.execute_operator_journey_scenario(mock_router)
  receipt.total_steps |> should.equal(6)
  receipt.passed_steps |> should.equal(6)
  receipt.all_passed |> should.be_true
}

