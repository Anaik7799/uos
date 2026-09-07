import cepaf_gleam/services/mirage_migration_engine
import cepaf_gleam/services/mirage_unikernel_daemon
import cepaf_gleam/ui/lustre/mirage_cockpit
import cepaf_gleam/ui/tui/mirage_view
import cepaf_gleam/ui/wisp/mirage_api
import cepaf_gleam/ui/wisp/router
import gleam/http.{Get}
import gleam/http/request
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

pub fn lustre_cockpit_labels_projection_and_unknown_runtime_test() {
  let html = mirage_cockpit.view()
  string.contains(html, "uos-mirage-cockpit") |> should.be_true()
  string.contains(html, "MirageOS Migration Projection Cockpit")
  |> should.be_true()
  string.contains(html, "static_migration_projection") |> should.be_true()
  string.contains(html, "Deployment admission:</strong> NOT_VERIFIED")
  |> should.be_true()
  string.contains(html, "Health: <code>unknown</code>") |> should.be_true()
  string.contains(html, "measured RAM delta: unknown") |> should.be_true()
  string.contains(html, "20260907-1037-mirage-benchmark-contract.md")
  |> should.be_true()
  string.contains(html, "MB CONSERVED") |> should.be_false()
  string.contains(html, "100% GREEN") |> should.be_false()
  string.contains(html, ">ADMITTED<") |> should.be_false()
}

pub fn lustre_cockpit_keeps_all_checklist_requirements_unverified_test() {
  let html = mirage_cockpit.view()
  [
    "Domain 1: Metadata, Timestamp, and Tailscale Navigation",
    "Domain 2: Zero-Muda Purity and Storage Safety",
    "Domain 3: Testing Gold Standard and Math Gates",
    "Domain 4: Cross-Language Control and Observability",
    "Domain 5: Tri-Sovereign Governance and Jujutsu Monorepo",
  ]
  |> list.each(fn(domain) { string.contains(html, domain) |> should.be_true() })
  [
    "CHK-01",
    "CHK-02",
    "CHK-03",
    "CHK-04",
    "CHK-05",
    "CHK-06",
    "CHK-07",
    "CHK-08",
    "CHK-09",
    "CHK-10",
    "CHK-11",
    "CHK-12",
    "CHK-13",
    "CHK-14",
    "CHK-15",
    "CHK-16",
    "CHK-17",
    "CHK-18",
  ]
  |> list.each(fn(code) { string.contains(html, code) |> should.be_true() })
  string.contains(html, "No all-green claim is made") |> should.be_true()
}

pub fn cockpit_escapes_public_candidate_and_observation_fields_test() {
  let malicious = "<script>alert(\"x\")</script> & 'tail'"
  let candidate =
    mirage_migration_engine.MigrationCandidate(
      id: malicious,
      name: malicious,
      layer: malicious,
      current_tech: malicious,
      mirage_target: malicious,
      target_sil_level: 6,
      projected_ram_saving_mb: 1,
      projected_speedup_pct: 1.0,
      status: mirage_migration_engine.Mapped,
      estimate_basis: mirage_migration_engine.ConfiguredProjection(malicious),
      admission: mirage_migration_engine.AdmissionUnverified(malicious),
    )
  let rows = mirage_cockpit.render_candidate_rows([candidate])
  string.contains(rows, malicious) |> should.be_false()
  string.contains(
    rows,
    "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; &#39;tail&#39;",
  )
  |> should.be_true()

  let state =
    mirage_unikernel_daemon.MirageDaemonState(
      ..mirage_unikernel_daemon.new_daemon_state(),
      observation: mirage_unikernel_daemon.RuntimeUnobserved(malicious),
    )
  let observation = mirage_cockpit.render_observation(state)
  string.contains(observation, malicious) |> should.be_false()
  string.contains(observation, "&lt;script&gt;") |> should.be_true()
  string.contains(observation, "&quot;x&quot;") |> should.be_true()
  string.contains(observation, "&amp; &#39;tail&#39;") |> should.be_true()
}

pub fn candidates_api_separates_projection_from_measurement_test() {
  let serialized =
    mirage_migration_engine.get_migration_candidates()
    |> mirage_api.candidates_json
    |> json.to_string

  string.contains(
    serialized,
    "\"evidence_scope\":\"static_migration_projection\"",
  )
  |> should.be_true()
  string.contains(serialized, "\"deployment_admission\":\"NOT_VERIFIED\"")
  |> should.be_true()
  string.contains(serialized, "\"projected_ram_savings_mb\":1092")
  |> should.be_true()
  string.contains(serialized, "\"measured_ram_savings_mb\":null")
  |> should.be_true()
  string.contains(serialized, "\"verified_admitted_count\":0")
  |> should.be_true()
  string.contains(serialized, "\"declared_stage\":\"Mapped\"")
  |> should.be_true()
  string.contains(serialized, "\"status\":\"NOT_VERIFIED\"")
  |> should.be_true()
}

pub fn safety_api_does_not_turn_screening_into_admission_test() {
  let safe_result =
    mirage_migration_engine.evaluate_non_negotiable_safety("mirage-dns")
  let safe_json =
    mirage_api.safety_eval_json("mirage-dns", safe_result)
    |> json.to_string
  string.contains(safe_json, "\"eligible\":true") |> should.be_true()
  string.contains(safe_json, "still requires empirical and formal evidence")
  |> should.be_true()

  let blocked_result =
    mirage_migration_engine.evaluate_non_negotiable_safety("uos_sup.gleam")
  let blocked_json =
    mirage_api.safety_eval_json("uos_sup.gleam", blocked_result)
    |> json.to_string
  string.contains(blocked_json, "\"eligible\":false") |> should.be_true()
}

pub fn status_api_is_unknown_simulation_and_counts_lifecycle_test() {
  let state = mirage_unikernel_daemon.new_daemon_state()
  let initial = mirage_api.unikernel_status_json(state) |> json.to_string
  string.contains(initial, "\"runtime_mode\":\"simulation_only\"")
  |> should.be_true()
  string.contains(initial, "\"health\":\"unknown\"") |> should.be_true()
  string.contains(initial, "\"simulated_running_instances_count\":0")
  |> should.be_true()

  let assert Ok(#(state, _)) =
    mirage_unikernel_daemon.simulate_boot_unikernel(
      state,
      "sim-1",
      "simulation",
      mirage_unikernel_daemon.TargetSolo5Hvt,
      16,
    )
  let assert Ok(state) =
    mirage_unikernel_daemon.simulate_terminate_unikernel(state, "sim-1")
  let terminated = mirage_api.unikernel_status_json(state) |> json.to_string
  string.contains(terminated, "\"simulated_running_instances_count\":0")
  |> should.be_true()
  string.contains(terminated, "\"simulated_terminated_instances_count\":1")
  |> should.be_true()
  string.contains(terminated, "\"status\":\"simulated_terminated\"")
  |> should.be_true()
}

pub fn tui_uses_same_projection_and_runtime_labels_test() {
  let candidates = mirage_migration_engine.get_migration_candidates()
  let state = mirage_unikernel_daemon.new_daemon_state()
  let output = mirage_view.render(candidates, state)
  string.contains(output, "Migration Projection Dashboard") |> should.be_true()
  string.contains(output, "Verified admitted:") |> should.be_true()
  string.contains(output, "1092 MB (unmeasured)") |> should.be_true()
  string.contains(output, "simulation_only") |> should.be_true()
  string.contains(output, "health=unknown") |> should.be_true()
  string.contains(output, "projection-only") |> should.be_true()
}

pub fn cepaf_router_exposes_truthful_mirage_json_test() {
  let candidates = router.route("/api/v1/mirage/candidates")
  string.contains(candidates, "\"deployment_admission\":\"NOT_VERIFIED\"")
  |> should.be_true()
  let status = router.route("/api/v1/mirage/status")
  string.contains(status, "\"runtime_mode\":\"simulation_only\"")
  |> should.be_true()
  let hyp = router.route("/api/v1/mirage/hypervisors")
  string.contains(
    hyp,
    "\"overall_readiness\":\"solo5_hardware_virtualized_and_spt_verified\"",
  )
  |> should.be_true()
  string.contains(hyp, "\"dev_kvm_present\":true")
  |> should.be_true()
  string.contains(hyp, "solo5-hvt")
  |> should.be_true()
  string.contains(hyp, "solo5-spt")
  |> should.be_true()
  string.contains(hyp, "\"passed\":true")
  |> should.be_true()
}

pub fn cepaf_router_exposes_projection_html_test() {
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/mirage")
  let response = router.handle_request(req)
  response.status |> should.equal(200)
  string.contains(response.body, "MirageOS Migration Projection Cockpit")
  |> should.be_true()
}
