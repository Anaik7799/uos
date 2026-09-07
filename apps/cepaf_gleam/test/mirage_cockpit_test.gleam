// Unified Operational System (UOS) - MirageOS Cockpit & Triple-Interface Tests
// Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001, SC-GLM-UI-001

import cepaf_gleam/services/mirage_migration_engine
import cepaf_gleam/services/mirage_unikernel_daemon
import cepaf_gleam/ui/lustre/mirage_cockpit
import cepaf_gleam/ui/tui/mirage_view
import cepaf_gleam/ui/wisp/mirage_api
import cepaf_gleam/ui/wisp/router
import gleam/http.{Get}
import gleam/http/request
import gleam/json
import gleam/string
import gleeunit/should

pub fn lustre_mirage_cockpit_renders_html_test() {
  let html = mirage_cockpit.view()
  string.contains(html, "uos-mirage-cockpit") |> should.be_true()
  string.contains(html, "MirageOS Unikernel & Subsystem Migration Cockpit")
  |> should.be_true()
  // Tailscale FQDN URL link
  string.contains(html, "http://nas-1.tail55d152.ts.net:4100/api/v1/mirage/candidates")
  |> should.be_true()
  // 18/18 Checklist codes
  string.contains(html, "CHK-01-TIME") |> should.be_true()
  string.contains(html, "CHK-07-DRIVE") |> should.be_true()
  string.contains(html, "CHK-13-HERMES") |> should.be_true()
  string.contains(html, "CHK-18-JJ") |> should.be_true()
  // All 7 candidate IDs
  string.contains(html, "MIG-01-INGRESS") |> should.be_true()
  string.contains(html, "MIG-02-SANDBOX") |> should.be_true()
  string.contains(html, "MIG-03-DNS") |> should.be_true()
  string.contains(html, "MIG-04-CRYPTO") |> should.be_true()
  string.contains(html, "MIG-05-LEDGER") |> should.be_true()
  string.contains(html, "MIG-06-FORWARD") |> should.be_true()
  string.contains(html, "MIG-07-SOLVER") |> should.be_true()
  // Non-negotiable boundary protections
  string.contains(html, "25503L801736") |> should.be_true()
  string.contains(html, "uos_sup.gleam") |> should.be_true()
  // Solo5 6-syscall sandbox
  string.contains(html, "sys_read") |> should.be_true()
  string.contains(html, "sys_write") |> should.be_true()
  string.contains(html, "sys_exit") |> should.be_true()
}

pub fn wisp_mirage_api_candidates_json_test() {
  let candidates = mirage_migration_engine.get_migration_candidates()
  let j = mirage_api.candidates_json(candidates)
  let serialized = json.to_string(j)
  string.contains(serialized, "\"total_candidates\":7") |> should.be_true()
  string.contains(serialized, "\"total_ram_savings_mb\":1092")
  |> should.be_true()
  string.contains(serialized, "MIG-01-INGRESS") |> should.be_true()
}

pub fn wisp_mirage_api_safety_eval_test() {
  let safe_res = mirage_migration_engine.evaluate_non_negotiable_safety("mirage-dns")
  let safe_json = mirage_api.safety_eval_json("mirage-dns", safe_res)
  string.contains(json.to_string(safe_json), "\"eligible\":true")
  |> should.be_true()

  let blocked_res =
    mirage_migration_engine.evaluate_non_negotiable_safety("uos_sup.gleam")
  let blocked_json =
    mirage_api.safety_eval_json("uos_sup.gleam", blocked_res)
  string.contains(json.to_string(blocked_json), "\"eligible\":false")
  |> should.be_true()
}

pub fn wisp_mirage_api_unikernel_status_test() {
  let state = mirage_unikernel_daemon.new_daemon_state()
  let j = mirage_api.unikernel_status_json(state)
  let serialized = json.to_string(j)
  string.contains(serialized, "\"max_memory_mb\":64") |> should.be_true()
  string.contains(serialized, "\"total_boots\":0") |> should.be_true()
}

pub fn tui_mirage_view_renders_ansi_test() {
  let candidates = mirage_migration_engine.get_migration_candidates()
  let output = mirage_view.render(candidates)
  string.contains(output, "MirageOS Unikernel & Subsystem Migration Dashboard")
  |> should.be_true()
  string.contains(output, "1092 MB") |> should.be_true()
  string.contains(output, "MIG-01-INGRESS") |> should.be_true()
  string.contains(output, "Non-Negotiable Boundaries") |> should.be_true()
}

pub fn router_mirage_api_endpoint_test() {
  let res_body = router.route("/api/v1/mirage/candidates")
  string.contains(res_body, "\"total_candidates\":7") |> should.be_true()
  string.contains(res_body, "MIG-01-INGRESS") |> should.be_true()

  let status_body = router.route("/api/v1/mirage/status")
  string.contains(status_body, "\"max_memory_mb\":64") |> should.be_true()
}

pub fn router_mirage_html_endpoint_test() {
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/mirage")
  let res = router.handle_request(req)
  res.status |> should.equal(200)
  string.contains(res.body, "MirageOS Unikernel & Subsystem Migration Cockpit")
  |> should.be_true()
}
