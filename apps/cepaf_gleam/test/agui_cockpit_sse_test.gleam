import cepaf_gleam/ui/lustre/agui_cockpit
import gleam/string
import gleeunit/should

pub fn agui_cockpit_sse_rendering_test() {
  let html = agui_cockpit.view()

  // Verify core structural elements
  html |> should.not_equal("")
  
  // Verify Tailscale links
  string.contains(html, "http://nas-1.tail55d152.ts.net:4100") |> should.be_true()
  string.contains(html, "http://vm-1.tail55d152.ts.net:8088") |> should.be_true()

  // Verify CRDT and Homeostasis cards
  string.contains(html, "CRDT Mesh Sync") |> should.be_true()
  string.contains(html, "Biomorphic Homeostasis") |> should.be_true()
  string.contains(html, "Browser Journey Verification") |> should.be_true()

  // Verify Comprehensive Checklist
  string.contains(html, "Universal Comprehensive Verification Checklist (18/18 PASS)") |> should.be_true()
}
