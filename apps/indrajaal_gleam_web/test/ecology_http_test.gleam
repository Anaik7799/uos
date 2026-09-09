import cepaf_gleam/ecology/living_swarm
import gleam/http/request
import gleam/string
import gleeunit/should
import indrajaal/ecology_http

pub fn ecology_html_render_test() {
  let html = ecology_http.render_ecology_html(living_swarm.init_living_swarm())
  string.contains(html, "UOS LIVING SWARM ECOLOGY") |> should.be_true()
  string.contains(
    html,
    "Comprehensive Verification Checklist: evidence required",
  )
  |> should.be_true()
  string.contains(html, "18/18 PASS") |> should.be_false()
  string.contains(html, "CHK-01-TIME") |> should.be_true()
  string.contains(html, "CHK-07-DRIVE") |> should.be_true()
  string.contains(html, "hive-mind-decider") |> should.be_true()
  string.contains(html, "prajna-homeostasis") |> should.be_true()
  string.contains(html, "ucon") |> should.be_true()
  string.contains(html, "indrajaal") |> should.be_true()
  string.contains(html, "HARMONIC CONSONANCE") |> should.be_true()
}

pub fn unavailable_runtime_is_http_503_test() {
  let assert Ok(req) =
    request.to("http://nas-1.tail55d152.ts.net:4100/api/v1/ecology/swarm")
  ecology_http.handle_snapshot(req, Error("swarm_unavailable")).status
  |> should.equal(503)
}

pub fn supplied_live_cycle_is_rendered_without_reinitialization_test() {
  let initial = living_swarm.init_living_swarm()
  let state = living_swarm.SwarmEcology(..initial, cycle_counter: 42)
  let html = ecology_http.render_ecology_html(state)
  string.contains(html, "id=\"ecology-cycle\">42</span>") |> should.be_true
  string.contains(html, "external system bindings are absent") |> should.be_true
  string.contains(html, "id=\"ecology-refresh-status\"") |> should.be_true
  string.contains(html, "Last displayed snapshot retained") |> should.be_true
}
