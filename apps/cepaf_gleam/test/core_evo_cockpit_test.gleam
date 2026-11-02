import cepaf_gleam/ui/lustre/core_evo_cockpit
import cepaf_gleam/ui/tui/core_evo_view
import cepaf_gleam/ui/wisp/core_evo_api
import cepaf_gleam/ui/wisp/router
import gleam/http.{Get}
import gleam/http/request
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

fn get_path(path: String) {
  request.new()
  |> request.set_method(Get)
  |> request.set_path(path)
  |> router.handle_request()
}

pub fn lustre_core_evo_cockpit_renders_honest_provenance_and_tables_test() {
  let html = core_evo_cockpit.view()
  string.contains(html, "uos-core-evo-cockpit") |> should.be_true()
  string.contains(
    html,
    "UOS-CORE-EVO Zero-Muda Holonic Hive, Bionic Services &amp; OTP 29 FPP Actor Cockpit",
  )
  |> should.be_true()
  string.contains(html, "EV-93") |> should.be_true()
  string.contains(html, "EV-94..109 NOT_ADMITTED") |> should.be_true()
  string.contains(html, "NOT_GRANTED (system_admitted=false)")
  |> should.be_true()
  string.contains(html, "-82.9%") |> should.be_true()
  string.contains(html, "1.01%") |> should.be_true()
  string.contains(html, "4000 bps") |> should.be_true()
  string.contains(html, "6000 bps") |> should.be_true()
  string.contains(html, "core_effect_fence") |> should.be_true()
  string.contains(html, "core_fpp_actor_twin_mesh") |> should.be_true()
  string.contains(html, "[REDACTED_SYSTEM_OS_SERIAL]") |> should.be_true()
  string.contains(
    html,
    "20261101-1721-uos-core-evo-mcp-zenoh-hive-bionic-services-and-dashboard-wiki.md",
  )
  |> should.be_true()
  string.contains(
    html,
    "20261101-1721-core-evo-zero-muda-holonic-hive-zenoh-mcp-and-cockpit-decision.md",
  )
  |> should.be_true()
  string.contains(
    html,
    "20261101-1711-uos-core-evo-benefits-features-mcp-zenoh-hive-services-master-journal.md",
  )
  |> should.be_true()
  string.contains(html, "100% GREEN") |> should.be_false()
  string.contains(html, ">ADMITTED<") |> should.be_false()
}

pub fn lustre_core_evo_cockpit_includes_all_six_checklist_domains_and_18_codes_test() {
  let html = core_evo_cockpit.view()
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

pub fn cockpit_escapes_untrusted_service_and_command_fields_against_xss_test() {
  let malicious = "<script>alert(\"xss\")</script> & 'inj'"
  let svc =
    core_evo_api.CoreEvoServiceRecord(
      id: malicious,
      name: malicious,
      layer: malicious,
      substrate: malicious,
      protection_and_capability: malicious,
    )
  let rendered_svc = core_evo_cockpit.render_service_rows([svc])
  string.contains(rendered_svc, malicious) |> should.be_false()
  string.contains(
    rendered_svc,
    "&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt; &amp; &#39;inj&#39;",
  )
  |> should.be_true()

  let cmd =
    core_evo_api.CoreEvoCommandRecord(
      id: malicious,
      surface: malicious,
      invocation: malicious,
      role_or_topic: malicious,
      description: malicious,
    )
  let rendered_cmd = core_evo_cockpit.render_command_rows([cmd])
  string.contains(rendered_cmd, malicious) |> should.be_false()
  string.contains(rendered_cmd, "&lt;script&gt;") |> should.be_true()
}

pub fn wisp_core_evo_api_and_router_endpoints_return_expected_contracts_test() {
  let status_str = core_evo_api.status_json() |> json.to_string()
  string.contains(status_str, "\"plane\":\"uos_core_evo\"") |> should.be_true()
  string.contains(status_str, "\"backend\":\"otp29_zero_muda_holonic_hive\"")
  |> should.be_true()
  string.contains(status_str, "\"admitted_ev_ceiling\":93") |> should.be_true()
  string.contains(status_str, "\"system_admitted\":false") |> should.be_true()

  let hive_str = core_evo_api.hive_json() |> json.to_string()
  string.contains(hive_str, "\"holons_total\":170") |> should.be_true()
  string.contains(hive_str, "\"states_verified\":4080") |> should.be_true()
  string.contains(hive_str, "\"invariants_proved\":12") |> should.be_true()

  let services_str = core_evo_api.services_json() |> json.to_string()
  string.contains(services_str, "\"service_count\":8") |> should.be_true()
  string.contains(services_str, "\"module_count\":7") |> should.be_true()
  string.contains(services_str, "\"fpp_holon_actors\":40") |> should.be_true()

  let fpp_str = core_evo_api.fpp_actors_json() |> json.to_string()
  string.contains(fpp_str, "\"actor_count\":40") |> should.be_true()
  string.contains(fpp_str, "\"domains_covered\":4") |> should.be_true()
  string.contains(fpp_str, "\"layers_covered\":10") |> should.be_true()
  string.contains(fpp_str, "l1_intel_zlp_v3_lean_zig_hyperplane")
  |> should.be_true()
  string.contains(fpp_str, "l9_intel_tri_sovereign_release_authority")
  |> should.be_true()

  let page_resp = get_path("/core-evo")
  page_resp.status |> should.equal(200)
  string.contains(page_resp.body, "uos-core-evo-cockpit") |> should.be_true()
  string.contains(
    page_resp.body,
    "40 Intelligent NASA FPP Actors &amp; Digital Twins",
  )
  |> should.be_true()
  string.contains(page_resp.body, "l0_apps_iam_guardian_gate")
  |> should.be_true()
  string.contains(page_resp.body, "l9_intel_tri_sovereign_release_authority")
  |> should.be_true()

  let fpp_resp = get_path("/api/v1/core-evo/fpp-actors")
  fpp_resp.status |> should.equal(200)
  string.contains(fpp_resp.body, "\"actor_count\":40") |> should.be_true()
  string.contains(fpp_resp.body, "\"AUTONOMOUS_SELF_HEAL\"") |> should.be_true()

  let twin_str = core_evo_api.bionic_token_twin_json() |> json.to_string()
  string.contains(twin_str, "\"schema\":\"uos.core_evo.bionic_token_twin.v5\"")
  |> should.be_true()
  string.contains(twin_str, "\"fastpath_profile_count\":8") |> should.be_true()
  string.contains(twin_str, "\"watchdog_count\":8") |> should.be_true()
  string.contains(twin_str, "\"fractal_surface_count\":10") |> should.be_true()
  string.contains(twin_str, "\"math_domains_total\":13") |> should.be_true()
  string.contains(twin_str, "\"math_domains_verified\":13") |> should.be_true()
  string.contains(twin_str, "\"math_all_theorems_hold\":true")
  |> should.be_true()
  string.contains(twin_str, "\"MATH-13\"") |> should.be_true()

  let twin_resp = get_path("/api/v1/core-evo/bionic-token-twin")
  twin_resp.status |> should.equal(200)
  string.contains(twin_resp.body, "\"math_all_theorems_hold\":true")
  |> should.be_true()
  string.contains(twin_resp.body, "\"property_total_trials\":1000")
  |> should.be_true()

  // Verify live_corpus Poka-Yoke for /wiki/holons and [[wiki:...]] / [[zk:...]] syntax examples
  let holons_resp = get_path("/wiki/holons")
  holons_resp.status |> should.equal(200)
  let wiki_dots_resp = get_path("/wiki/...")
  wiki_dots_resp.status |> should.equal(200)
  let zk_dots_resp = get_path("/zk/...")
  zk_dots_resp.status |> should.equal(200)
  let agents_resp = get_path("/files/AGENTS.md")
  agents_resp.status |> should.equal(200)
  string.contains(agents_resp.body, "href=\"/wiki/...\"") |> should.be_false()
  string.contains(agents_resp.body, "href=\"/zk/...\"") |> should.be_false()

  let status_resp = get_path("/api/v1/core-evo/status")
  status_resp.status |> should.equal(200)
  string.contains(status_resp.body, "\"backend\":\"otp29_zero_muda_holonic_hive\"")
  |> should.be_true()
  string.contains(status_resp.body, "\"admitted_ev_ceiling\":93")
  |> should.be_true()
  string.contains(status_resp.body, "\"system_admitted\":false")
  |> should.be_true()

  let health_resp = get_path("/api/core-evo/health")
  health_resp.status |> should.equal(200)
  string.contains(health_resp.body, "\"plane\":\"uos_core_evo\"")
  |> should.be_true()

  let hive_resp = get_path("/api/v1/core-evo/hive")
  hive_resp.status |> should.equal(200)
  string.contains(hive_resp.body, "\"states_verified\":4080")
  |> should.be_true()
  string.contains(hive_resp.body, "\"untouched_margin_bps\":4000")
  |> should.be_true()

  let svc_resp = get_path("/api/v1/core-evo/services")
  svc_resp.status |> should.equal(200)
  string.contains(svc_resp.body, "\"service_count\":8") |> should.be_true()
  string.contains(svc_resp.body, "\"module_count\":7") |> should.be_true()
  string.contains(svc_resp.body, "\"zero_muda\":true") |> should.be_true()
}

pub fn tui_core_evo_view_renders_ansi_plain_and_sanitizes_control_bytes_test() {
  let ansi = core_evo_view.render()
  string.contains(ansi, "\u{001b}[1;36m") |> should.be_true()
  string.contains(ansi, "UOS-CORE-EVO Zero-Muda Holonic Hive")
  |> should.be_true()
  string.contains(ansi, "EV-93 ceiling") |> should.be_true()
  string.contains(ansi, "system_admitted=false") |> should.be_true()

  let plain = core_evo_view.render_plain()
  string.contains(plain, "\u{001b}") |> should.be_false()
  string.contains(plain, "OTP 29.0.5 (ERTS 17.0.5)") |> should.be_true()
  string.contains(plain, "[REDACTED_SYSTEM_OS_SERIAL]") |> should.be_true()

  let dirty =
    "safe\u{001b}[31mred\u{009b}32mc1csi\u{009d}0;title\u{009c}\u{0007}bell\nnext\ttab"
  let clean = core_evo_view.sanitize_terminal_text(dirty)
  string.contains(clean, "\u{001b}") |> should.be_false()
  string.contains(clean, "\u{009b}") |> should.be_false()
  string.contains(clean, "\u{009d}") |> should.be_false()
  string.contains(clean, "\u{009c}") |> should.be_false()
  string.contains(clean, "\u{0007}") |> should.be_false()
  string.contains(clean, "\n") |> should.be_false()
  string.contains(clean, "\t") |> should.be_false()
  clean |> should.equal("safe[31mred32mc1csi0;titlebell next tab")
}
