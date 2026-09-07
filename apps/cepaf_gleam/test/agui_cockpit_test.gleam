// =============================================================================
// [C3I-SIL6-MSTS] AG-UI COCKPIT LUSTRE VIEW TEST SUITE (SC-AGUI-001, SC-GLM-UI-001)
// =============================================================================

import cepaf_gleam/ui/lustre/agui_cockpit
import cepaf_gleam/ui/wisp/router
import gleam/string
import gleeunit/should

pub fn agui_cockpit_view_test() {
  let html = agui_cockpit.view()

  // Verify page structure and title
  string.contains(html, "AG-UI 32-Event Real-Time Cockpit") |> should.be_true()
  string.contains(html, "SIL-6 FRACTAL") |> should.be_true()
  string.contains(html, "ZERO-MUDA") |> should.be_true()
  string.contains(html, "LOCK: 25503L801736") |> should.be_true()

  // Verify Tailscale links
  string.contains(html, "http://nas-1.tail55d152.ts.net:4100/ag-ui/events/sse")
  |> should.be_true()
  string.contains(html, "http://nas-1.tail55d152.ts.net:4100/ag-ui/manifest")
  |> should.be_true()

  // Verify 18/18 Comprehensive Verification Checklist
  string.contains(
    html,
    "Universal Comprehensive Verification Checklist (18/18 PASS)",
  )
  |> should.be_true()
  string.contains(html, "CHK-01-TIME") |> should.be_true()
  string.contains(html, "CHK-07-DRIVE") |> should.be_true()
  string.contains(html, "CHK-10-9MOD") |> should.be_true()
  string.contains(html, "CHK-18-JJ") |> should.be_true()

  // Verify 7 Event Categories
  string.contains(html, "Lifecycle (5)") |> should.be_true()
  string.contains(html, "Text (4)") |> should.be_true()
  string.contains(html, "Tool (5)") |> should.be_true()
  string.contains(html, "State (3)") |> should.be_true()
  string.contains(html, "Activity (2)") |> should.be_true()
  string.contains(html, "Reasoning (7)") |> should.be_true()
  string.contains(html, "Special (6)") |> should.be_true()

  // Verify Real-Time Lyapunov Sparkline SVG
  string.contains(html, "Real-Time Lyapunov &lambda;(t) Sparkline")
  |> should.be_true()
  string.contains(html, "<svg width=\"100%\" height=\"48\" viewBox=\"0 0 240 48\"")
  |> should.be_true()
}

pub fn agui_cockpit_router_test() {
  let out = router.route("/ag-ui/cockpit")
  string.contains(out, "AG-UI 32-Event Real-Time Cockpit") |> should.be_true()
  string.contains(out, "Universal Comprehensive Verification Checklist")
  |> should.be_true()
}
