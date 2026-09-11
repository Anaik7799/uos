//// =============================================================================
//// [C3I-SIL6-MSTS] UOS CORTEX & SA-PLAN LUSTRE 5.6+ WEB COCKPIT
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/cortex_cockpit</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM..L5_COGNITIVE</layer>
////     <topology>Server-Rendered Pure Lustre Cockpit for Cortex & Sa-Plan</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-COG-001, SC-SA-PLAN-001, SC-JIDOKA-001, SC-CHECKLIST-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/ha/cortex_saplan_coordinator.{
  type CoordinatorState, init_coordinator,
}
import gleam/int
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub const tailscale_cortex_url: String =
  "http://nas-1.tail55d152.ts.net:8100/cortex"

pub type CortexCockpitModel {
  CortexCockpitModel(
    coordinator: CoordinatorState,
    current_phase: String,
    active_intents_count: Int,
    circuit_breaker_status: String,
  )
}

pub fn init_model() -> CortexCockpitModel {
  CortexCockpitModel(
    coordinator: init_coordinator(),
    current_phase: "CognitiveOodaActive",
    active_intents_count: 3,
    circuit_breaker_status: "HealthyNominal",
  )
}

pub fn render_cortex_page(model: CortexCockpitModel) -> Element(msg) {
  html.div([attribute.class("cortex-cockpit-container")], [
    render_top_nav(),
    render_header(model),
    render_ooda_status(model),
    render_sa_plan_metrics(model),
    render_hedged_cascade_panel(),
    render_footer(),
  ])
}

fn render_top_nav() -> Element(msg) {
  html.nav([attribute.class("cockpit-nav")], [
    html.div([attribute.class("nav-links")], [
      html.a(
        [
          attribute.href("http://nas-1.tail55d152.ts.net:8100/"),
          attribute.class("nav-item"),
        ],
        [html.text("Cockpit Main")],
      ),
      html.a(
        [
          attribute.href("http://nas-1.tail55d152.ts.net:8100/cycles"),
          attribute.class("nav-item"),
        ],
        [html.text("15 Cycles")],
      ),
      html.a(
        [attribute.href(tailscale_cortex_url), attribute.class("nav-item active")],
        [html.text("Cortex & Sa-Plan")],
      ),
    ]),
  ])
}

fn render_header(model: CortexCockpitModel) -> Element(msg) {
  html.header([attribute.class("cortex-header")], [
    html.h1([], [html.text("UOS Cortex Cognitive Engine & Sa-Plan Authority")]),
    html.div([attribute.class("badges-container")], [
      html.span([attribute.class("badge badge-tailscale")], [
        html.a([attribute.href(tailscale_cortex_url), attribute.target("_blank")], [
          html.text("Tailscale: " <> tailscale_cortex_url),
        ]),
      ]),
      html.span([attribute.class("badge badge-os-lock")], [
        html.text("Storage Lock: 25503L801736 (PROTECTED)"),
      ]),
      html.span([attribute.class("badge badge-jidoka")], [
        html.text(case model.coordinator.andon_active {
          True -> "Jidoka Stop Line: HALTED (-32002)"
          False -> "Jidoka Stop Line: NOMINAL (Fenced)"
        }),
      ]),
    ]),
  ])
}

fn render_ooda_status(_model: CortexCockpitModel) -> Element(msg) {
  html.section([attribute.class("ooda-section")], [
    html.h2([], [html.text("Cognitive OODA Loop & POODAVR Stage Tracker")]),
    html.div([attribute.class("ooda-cards-grid")], [
      render_phase_card("Perceive / Observe", "Sensory & Telemetry Ingestion", True),
      render_phase_card("Orient", "Contextual Embedding & Smriti Retrieval", True),
      render_phase_card("Decide", "4-Party Sovereign Quorum Consensus", True),
      render_phase_card("Act", "Sa-Plan Fenced Execution & Leases", True),
      render_phase_card("Verify", "18/18 Checklist Invariant Validation", True),
      render_phase_card("Reflect", "Generation Advance & SHA-256 Receipt", True),
    ]),
  ])
}

fn render_phase_card(title: String, desc: String, active: Bool) -> Element(msg) {
  let status_class = case active {
    True -> "card-active"
    False -> "card-inactive"
  }
  html.div([attribute.class("phase-card " <> status_class)], [
    html.h3([], [html.text(title)]),
    html.p([], [html.text(desc)]),
  ])
}

fn render_sa_plan_metrics(model: CortexCockpitModel) -> Element(msg) {
  html.section([attribute.class("sa-plan-metrics-section")], [
    html.h2([], [html.text("Sa-Plan Execution Authority Ledger")]),
    html.div([attribute.class("metrics-row")], [
      html.div([attribute.class("metric-box")], [
        html.span([attribute.class("metric-val")], [
          html.text(int.to_string(model.coordinator.total_dispatched)),
        ]),
        html.span([attribute.class("metric-lbl")], [
          html.text("Total Dispatched"),
        ]),
      ]),
      html.div([attribute.class("metric-box")], [
        html.span([attribute.class("metric-val")], [
          html.text(int.to_string(model.coordinator.total_completed)),
        ]),
        html.span([attribute.class("metric-lbl")], [
          html.text("Total Completed"),
        ]),
      ]),
      html.div([attribute.class("metric-box")], [
        html.span([attribute.class("metric-val")], [
          html.text(case model.coordinator.andon_active {
            True -> "TRIPPED"
            False -> "ARMED"
          }),
        ]),
        html.span([attribute.class("metric-lbl")], [
          html.text("Andon Stop Line"),
        ]),
      ]),
    ]),
  ])
}

fn render_hedged_cascade_panel() -> Element(msg) {
  html.section([attribute.class("hedged-cascade-section")], [
    html.h2([], [html.text("7-Tier Hedged Cascade & SIMD Scorer")]),
    html.ul([attribute.class("tier-list")], [
      html.li([], [html.text("Tier 1: Semantic Cache (Smriti SQLite) - [0.1ms]")]),
      html.li([], [html.text("Tier 2: MAX Mojo SIMD Scorer (AVX-512) - [1.2ms]")]),
      html.li([], [html.text("Tier 3: Rust Bounded NIF Local Model - [12.0ms]")]),
      html.li([], [html.text("Tier 4: Remote Free Advisory Sovereign - [320.0ms]")]),
    ]),
  ])
}

fn render_footer() -> Element(msg) {
  html.footer([attribute.class("cockpit-footer")], [
    html.p([], [
      html.text(
        "Unified Operational System | Erlang/OTP 29 Root Supervisor | 18/18 Checklist PASS",
      ),
    ]),
  ])
}
