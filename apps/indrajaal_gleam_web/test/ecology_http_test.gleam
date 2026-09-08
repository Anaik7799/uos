import indrajaal/ecology_http
import gleam/string
import gleeunit/should

pub fn ecology_html_render_test() {
  let html = ecology_http.render_ecology_html()
  string.contains(html, "UOS LIVING 21-HOLON SWARM ECOLOGY") |> should.be_true()
  string.contains(html, "Comprehensive Verification Checklist Status: 18/18 PASS") |> should.be_true()
  string.contains(html, "CHK-01-TIME") |> should.be_true()
  string.contains(html, "CHK-07-DRIVE") |> should.be_true()
  string.contains(html, "hive-mind-decider") |> should.be_true()
  string.contains(html, "prajna-homeostasis") |> should.be_true()
  string.contains(html, "HARMONIC CONSONANCE") |> should.be_true()
}
