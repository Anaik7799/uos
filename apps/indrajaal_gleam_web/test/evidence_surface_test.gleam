import gleam/string
import gleeunit/should
import indrajaal_gleam_web

pub fn accordion_renders_shared_unrun_state_test() {
  let html = indrajaal_gleam_web.render_checklist_accordion()
  html |> string.contains("UNRUN &bull; 0/18 OBSERVED") |> should.be_true()
  html |> string.contains("metrics unavailable") |> should.be_true()
  html |> string.contains("18/18 VERIFIED") |> should.be_false()
}

pub fn api_payload_reports_the_same_shared_state_test() {
  let #(status_code, body) = indrajaal_gleam_web.verification_checks_payload()
  status_code |> should.equal(503)
  body |> string.contains("\"status\":\"UNRUN\"") |> should.be_true()
  body |> string.contains("\"metrics_available\":false") |> should.be_true()
  body |> string.contains("\"admitted\":false") |> should.be_true()
}
