import cepaf_gleam/ui/lustre/zlp_cockpit
import cepaf_gleam/ui/tui/zlp_view
import cepaf_gleam/ui/wisp/router
import cepaf_gleam/ui/wisp/zlp_api
import gleam/http.{Get}
import gleam/http/request
import gleam/list
import gleam/string
import gleeunit/should

fn get_path(path: String) {
  request.new()
  |> request.set_method(Get)
  |> request.set_path(path)
  |> router.handle_request()
}

pub fn lustre_cockpit_renders_honest_provenance_and_hyperplane_tables_test() {
  let html = zlp_cockpit.view()
  string.contains(html, "uos-zlp-cockpit") |> should.be_true()
  string.contains(
    html,
    "UOS-ZLP-v3 Supervised Lean 4 + Zig + OTP 29 + Zenoh Port Hyperplane",
  )
  |> should.be_true()
  string.contains(html, "EV-93") |> should.be_true()
  string.contains(html, "NOT_GRANTED (system_admitted=false)")
  |> should.be_true()
  string.contains(html, "uos_zlp_verify_frame") |> should.be_true()
  string.contains(html, "uos_zlp_heavy_graph_digest") |> should.be_true()
  string.contains(html, "T01_wire_header_roundtrip") |> should.be_true()
  string.contains(html, "T20_graceful_drain_reaches_zero") |> should.be_true()
  string.contains(
    html,
    "20261101-1410-zlp-hyperplane-port-contract.md",
  )
  |> should.be_true()
  string.contains(html, ".agents/skills/uos-zlp-hyperplane/SKILL.md")
  |> should.be_true()
  string.contains(html, "100% GREEN") |> should.be_false()
  string.contains(html, ">ADMITTED<") |> should.be_false()
}

pub fn lustre_cockpit_includes_all_six_checklist_domains_and_18_codes_test() {
  let html = zlp_cockpit.view()
  [
    "Domain 1: Metadata, Timestamp, and Tailscale Navigation",
    "Domain 2: Zero-Muda Purity and Storage Safety",
    "Domain 3: Testing Gold Standard and Math Gates",
    "Domain 4: Cross-Language Control and Observability",
    "Domain 5: Tri-Sovereign Governance and Jujutsu Monorepo",
    "Domain 6: Provenance boundary",
  ]
  |> list.each(fn(domain) { string.contains(html, domain) |> should.be_true() })
  [
    "CHK-01-TIME",
    "CHK-02-TAIL",
    "CHK-03-FRACT",
    "CHK-04-KM",
    "CHK-05-MUDA",
    "CHK-06-GRAPH",
    "CHK-07-DRIVE",
    "CHK-08-C1C8",
    "CHK-09-MATH",
    "CHK-10-9MOD",
    "CHK-11-REGR",
    "CHK-12-GLEAM",
    "CHK-13-HERMES",
    "CHK-14-ZIGVM",
    "CHK-15-MAX",
    "CHK-16-OTEL",
    "CHK-17-SOV",
    "CHK-18-JJ",
  ]
  |> list.each(fn(code) { string.contains(html, code) |> should.be_true() })
}

pub fn cockpit_escapes_untrusted_theorem_and_shard_fields_against_xss_test() {
  let malicious = "<script>alert(\"xss\")</script> & 'inj'"
  let thm =
    zlp_api.ZlpTheoremRecord(
      id: malicious,
      name: malicious,
      layer: malicious,
      contract: malicious,
      statement: malicious,
    )
  let rendered_thm = zlp_cockpit.render_theorem_rows([thm])
  string.contains(rendered_thm, malicious) |> should.be_false()
  string.contains(
    rendered_thm,
    "&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt; &amp; &#39;inj&#39;",
  )
  |> should.be_true()

  let shard =
    zlp_api.ZlpShardObservation(
      shard_id: 1,
      status: malicious,
      os_pid: 4242,
      active_subs: 2,
      in_flight_heavy: 0,
      perceus_excl: 1,
    )
  let rendered_shard = zlp_cockpit.render_shard_rows([shard])
  string.contains(rendered_shard, malicious) |> should.be_false()
  string.contains(rendered_shard, "&lt;script&gt;") |> should.be_true()
}

pub fn wisp_zlp_api_and_router_endpoints_return_expected_contracts_test() {
  let page_resp = get_path("/zlp")
  page_resp.status |> should.equal(200)
  string.contains(page_resp.body, "uos-zlp-cockpit") |> should.be_true()

  let status_resp = get_path("/api/v1/zlp/status")
  status_resp.status |> should.equal(200)
  string.contains(status_resp.body, "\"backend\":\"uos_zlp_v3_otp29_port\"")
  |> should.be_true()
  string.contains(status_resp.body, "\"admitted_ev_ceiling\":93")
  |> should.be_true()
  string.contains(status_resp.body, "\"system_admitted\":false")
  |> should.be_true()

  let health_resp = get_path("/api/zlp/health")
  health_resp.status |> should.equal(200)
  string.contains(health_resp.body, "\"plane\":\"zlp_hyperplane\"")
  |> should.be_true()

  let thm_resp = get_path("/api/v1/zlp/theorems")
  thm_resp.status |> should.equal(200)
  string.contains(thm_resp.body, "\"theorem_count\":21") |> should.be_true()
  string.contains(thm_resp.body, "\"export_kernel_count\":8")
  |> should.be_true()
  string.contains(thm_resp.body, "\"zero_sorry_ax\":true") |> should.be_true()

  let lanes_resp = get_path("/api/v1/zlp/lanes")
  lanes_resp.status |> should.equal(200)
  string.contains(
    lanes_resp.body,
    "\"isolation_model\":\"otp29_open_port_packet4_parallelism_true\"",
  )
  |> should.be_true()
  string.contains(lanes_resp.body, "\"hol_blocking_on_fast_lane\":false")
  |> should.be_true()
}

pub fn tui_zlp_view_renders_ansi_dashboard_and_boundaries_test() {
  let sample_shard =
    zlp_api.ZlpShardObservation(
      shard_id: 1,
      status: "healthy",
      os_pid: 99001,
      active_subs: 3,
      in_flight_heavy: 0,
      perceus_excl: 1,
    )
  let ansi = zlp_view.render_snapshot(True, True, [sample_shard])
  string.contains(
    ansi,
    "UOS-ZLP-v3 Supervised Lean 4 + Zig + OTP 29 + Zenoh Hyperplane",
  )
  |> should.be_true()
  string.contains(ansi, "21 (0 sorryAx)") |> should.be_true()
  string.contains(ansi, "99001") |> should.be_true()
  string.contains(ansi, "SC-ZLP-PORT-001") |> should.be_true()
  string.contains(ansi, "system_admitted=false") |> should.be_true()
}
