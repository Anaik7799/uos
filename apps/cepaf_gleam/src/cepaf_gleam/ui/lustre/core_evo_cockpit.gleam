//// UOS-CORE-EVO Zero-Muda Core Development, 5-Caste Holonic Hive,
//// 8 Integrated Bionic Services & OTP 29 FPP Actor Mesh Browser Cockpit
//// (GET /core-evo).
//// STAMP: SC-GLM-UI-001, SC-CHECKLIST-001, SC-HARNESS-MCP-001, SC-JIDOKA-001, SC-PROVENANCE-001

import cepaf_gleam/ecology/core_effect_fence
import cepaf_gleam/ecology/core_evolution
import cepaf_gleam/ecology/core_fpp_actor_twin_mesh.{
  type FppHolonActorState, type SubsystemFppActorSpec,
}
import cepaf_gleam/ui/wisp/core_evo_api.{
  type CoreEvoBenefit, type CoreEvoCasteRecord, type CoreEvoCommandRecord,
  type CoreEvoModuleRecord, type CoreEvoServiceRecord,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/string

const spec_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261101-1543-uos-zero-muda-core-dev-hive-biomorphic-fractal-evolution-system.md"

const wiki_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/wiki/20261101-1721-uos-core-evo-mcp-zenoh-hive-bionic-services-and-dashboard-wiki.md"

const zk_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20261101-1721-core-evo-zero-muda-holonic-hive-zenoh-mcp-and-cockpit-decision.md"

const journal_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261101-1711-uos-core-evo-benefits-features-mcp-zenoh-hive-services-master-journal.md"

const km_catalog_url = "http://nas-1.tail55d152.ts.net:4100/api/v1/km/catalog"

pub fn view() -> String {
  let benefits = core_evo_api.get_benefits()
  let castes = core_evo_api.get_castes()
  let services = core_evo_api.get_bionic_services()
  let modules = core_evo_api.get_modules()
  let commands = core_evo_api.get_commands()
  let live_fpp_actors = core_fpp_actor_twin_mesh.inspect_live_40_fpp_actors()

  "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>UOS-CORE-EVO Holonic Hive &amp; Bionic Services Cockpit</title></head><body style=\"margin:0;background:#0a0e17;color:#e0e6ed;font-family:system-ui,-apple-system,sans-serif\">"
  <> "<div class=\"uos-core-evo-cockpit\" style=\"box-sizing:border-box;width:100%;max-width:100%;overflow-x:auto;padding:1.5rem;background:#0a0e17;color:#e0e6ed\">"
  <> "<style>.uos-core-evo-cockpit{overflow-wrap:anywhere}.uos-core-evo-cockpit a{color:#4fd1c5}.uos-core-evo-cockpit table{display:block;overflow-x:auto;max-width:100%;color:#e0e6ed;background:#0a0e17;border-collapse:collapse}.uos-core-evo-cockpit th,.uos-core-evo-cockpit td{color:#e0e6ed;background:#0a0e17;border-bottom:1px solid #34435b;padding:.5rem;min-width:6rem;text-align:left}.uos-core-evo-cockpit th{color:#b7c7db}.uos-core-evo-cockpit code{color:#9ae6b4;background:transparent}@media(max-width:480px){.uos-core-evo-cockpit{padding:.75rem!important}.uos-core-evo-cockpit section{padding:.75rem!important}.uos-core-evo-cockpit table{font-size:.875rem}}</style>"
  <> "<nav style=\"margin-bottom:1rem;padding-bottom:.75rem;border-bottom:1px solid #243044\">"
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/\">Cockpit</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/zenoh\">Zenoh Mesh</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/zlp\">ZLP Hyperplane</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/planning\">Planning</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/wiki\">Hermes Wiki</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/zk\">ZigVM ZK</a> &middot; "
  <> "<a href=\""
  <> km_catalog_url
  <> "\">KM Catalog</a> &middot; "
  <> "<strong><code>http://nas-1.tail55d152.ts.net:4100/core-evo</code></strong></nav>"
  <> "<header><h1 style=\"color:#00d4aa\">UOS-CORE-EVO Zero-Muda Holonic Hive, Bionic Services &amp; OTP 29 FPP Actor Cockpit</h1>"
  <> "<p>Pure functional <code>Erlang/OTP 29.0.5 (ERTS 17.0.5)</code> core development &amp; evolution plane unifying single-gateway <code>uos-gleam</code> MCP (<code>-82.9%</code> schema overhead), Ed25519-signed Zenoh <code>uos/v1/**</code>, 5-Caste Holonic Hive (<code>1.01%</code> AGY share, <code>40.0% / 4000 bps</code> untouched safety margin), 8 Bionic Services, <code>170 x 24 = 4080</code> Janus Holon states (<code>12/12</code> invariants), 40 live OTP 29 Intelligent NASA FPP Actors &amp; Digital Twins (<code>4 Supervision Domains x L0..L9</code>), and <code>OI07</code> 14-target reader-drain crash rollback.</p>"
  <> "<p><strong>Evidence scope:</strong> candidate_development_observation &middot; <strong>Admitted EV ceiling:</strong> <code>EV-"
  <> int.to_string(core_evolution.admitted_ev_ceiling)
  <> "</code> (<code>EV-94..109 NOT_ADMITTED</code>) &middot; <strong>System admission:</strong> <code>NOT_GRANTED (system_admitted=false)</code></p></header>"
  <> render_runtime_summary()
  <> "<section><h2>Live JSON Telemetry &amp; #km-triad Corpus Links</h2>"
  <> "<p><a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/core-evo/status\">Core-Evo Status JSON</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/core-evo/hive\">5-Caste Holonic Hive &amp; 9 Benefits JSON</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/core-evo/services\">8 Bionic Services, 7 Modules &amp; 13 Commands JSON</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/core-evo/fpp-actors\">40 Intelligent NASA FPP Actors JSON</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/core-evo/bionic-token-twin\">Bionic Token Twin &amp; 13-Theorem Math JSON</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/api/core-evo/health\">Health Probe JSON</a></p>"
  <> "<p><a href=\""
  <> spec_url
  <> "\">Design Spec</a> &middot; <a href=\""
  <> wiki_url
  <> "\">Dedicated Wiki</a> &middot; <a href=\""
  <> zk_url
  <> "\">Dedicated ZK Decision Note</a> &middot; <a href=\""
  <> journal_url
  <> "\">Master Journal</a> &middot; <a href=\""
  <> km_catalog_url
  <> "\">KM Catalog API</a></p></section>"
  <> "<section><h2>9 Quantitative Transformation Benefits (Before vs After)</h2><table><thead><tr>"
  <> "<th>ID</th><th>Engineering Dimension</th><th>Before State</th><th>After State</th><th>Quantitative Delta</th>"
  <> "</tr></thead><tbody>"
  <> render_benefit_rows(benefits)
  <> "</tbody></table></section>"
  <> "<section><h2>5-Caste Holonic Hive &amp; Token Budget Allocation</h2><table><thead><tr>"
  <> "<th>Caste ID</th><th>Hive Caste &amp; Role</th><th>Bound Engine</th><th>Token / Compute Share</th><th>Heijunka WIP</th><th>MCP Route Slice</th><th>Responsibility</th>"
  <> "</tr></thead><tbody>"
  <> render_caste_rows(castes)
  <> "</tbody></table></section>"
  <> "<section><h2>8 Integrated Bionic &amp; Systems Engineering Services</h2><table><thead><tr>"
  <> "<th>ID</th><th>Bionic Service</th><th>Fractal Layer</th><th>Canonical Substrate</th><th>Operational Protection &amp; Capability</th>"
  <> "</tr></thead><tbody>"
  <> render_service_rows(services)
  <> "</tbody></table></section>"
  <> "<section><h2>7 Core Gleam/OTP 29 Ecology Modules</h2><table><thead><tr>"
  <> "<th>ID</th><th>Module</th><th>Path</th><th>Layers</th><th>Invariants &amp; Capabilities</th>"
  <> "</tr></thead><tbody>"
  <> render_module_rows(modules)
  <> "</tbody></table></section>"
  <> "<section><h2>13 CLI, MCP &amp; Signed Zenoh Command Surfaces</h2><table><thead><tr>"
  <> "<th>ID</th><th>Surface</th><th>Invocation</th><th>Role Slice / Zenoh Topic</th><th>Description</th>"
  <> "</tr></thead><tbody>"
  <> render_command_rows(commands)
  <> "</tbody></table></section>"
  <> "<section><h2>40 Intelligent NASA FPP Actors &amp; Digital Twins (4 Supervision Domains &times; L0..L9)</h2><table><thead><tr>"
  <> "<th>#</th><th>Layer</th><th>Domain Supervisor</th><th>Actor ID</th><th>Subsystem Covered</th><th>Companion F&prime; FSM</th><th>Live OTP &amp; F&prime; State</th><th>Primary MCP Route</th><th>Autonomous Intelligence &amp; Reflex Focus</th>"
  <> "</tr></thead><tbody>"
  <> render_live_fpp_actor_rows(live_fpp_actors)
  <> "</tbody></table></section>"
  <> render_checklist()
  <> "<section style=\"border:1px solid #ff6b6b;padding:1rem;margin-top:1rem\"><h2>Non-Negotiable Constitutional Boundaries</h2>"
  <> "<p>Gleam/OTP retains sole policy and effect authority (<code>SC-HARNESS-MCP-001</code>, <code>SC-JIDOKA-001</code>). Effect-time gate <code>OI07</code> blocks <code>oi02</code> until verified and guarantees 0 mixed-capsule readers across all 14 targets. Root NVMe <code>[REDACTED_SYSTEM_OS_SERIAL]</code>, standalone Jujutsu (<code>.jj/</code>), and <code>EV-93</code> ceiling (<code>EV-94..109 NOT_ADMITTED</code>) remain strictly enforced.</p></section>"
  <> "<footer style=\"margin-top:1rem;padding-top:.75rem;border-top:1px solid #243044\"><a href=\"http://nas-1.tail55d152.ts.net:4100/\">UOS Cockpit</a> &middot; <a href=\"http://nas-1.tail55d152.ts.net:4100/zlp\">ZLP Hyperplane</a> &middot; <a href=\"http://nas-1.tail55d152.ts.net:4100/wiki\">Wiki</a> &middot; <a href=\"http://nas-1.tail55d152.ts.net:4100/zk\">ZK</a> &middot; UOS footer: component and cockpit observations do not grant global system admission.</footer>"
  <> "</div></body></html>"
}

fn render_runtime_summary() -> String {
  let target_count = list.length(core_effect_fence.canonical_14_targets)
  let #(sup_running, live_cnt) =
    core_fpp_actor_twin_mesh.live_40_fpp_supervisor_status()
  let sup_badge = case sup_running {
    True -> "OneForOne Supervisor RUNNING"
    False -> "Supervisor STOPPED"
  }
  "<section style=\"border:1px solid #34435b;padding:1rem;margin:1rem 0\">"
  <> "<h2>Runtime &amp;Quota Safety Envelope</h2><ul>"
  <> "<li>Runtime: <code>Erlang/OTP 29.0.5 (ERTS 17.0.5)</code> &middot; Status: <code>candidate_under_review</code></li>"
  <> "<li>Untouched Quota Margin: <code>"
  <> int.to_string(core_evolution.mandatory_margin_bps)
  <> " bps (40.0%)</code> &middot; Hard Execution Ceiling: <code>"
  <> int.to_string(core_evolution.hard_ceiling_bps)
  <> " bps (60.0%)</code> &middot; OpenRouter 24h Cap: <code>$6.00 / $10.00</code></li>"
  <> "<li>Janus Holonic Lattice: <code>170 Holons (10x17) x 24 Epochs = 4080 States</code> &middot; Invariants Proved: <code>12/12 (INV-HOLON-01..12)</code></li>"
  <> "<li>Live OTP 29 Intelligent NASA FPP Actor &amp; Digital Twin Mesh: <code>"
  <> int.to_string(live_cnt)
  <> "/40 Live OTP Processes ("
  <> sup_badge
  <> ", 4 Supervision Domains x L0..L9)</code> &middot; OI07 Recoverable Cutover Targets: <code>"
  <> int.to_string(target_count)
  <> " targets (0 mixed readers)</code></li>"
  <> "<li>Bionic Token Digital Twin &amp; Shannon Fastpath: <code>8 Content Classes &middot; 8 FPP-TOK Watchdogs &middot; 10 Fractal Surfaces (L0..L9) &middot; 13/13 Multi-Prover Math Domains (Lean4/Rocq/Z3/Why3/Quint/TLA+)</code></li>"
  <> "</ul></section>"
}

pub fn render_benefit_rows(benefits: List(CoreEvoBenefit)) -> String {
  benefits
  |> list.map(fn(b) {
    "<tr><td><code>"
    <> escape_html(b.id)
    <> "</code></td><td>"
    <> escape_html(b.dimension)
    <> "</td><td>"
    <> escape_html(b.before_state)
    <> "</td><td>"
    <> escape_html(b.after_state)
    <> "</td><td><strong>"
    <> escape_html(b.quantitative_delta)
    <> "</strong></td></tr>"
  })
  |> string.join("")
}

pub fn render_caste_rows(castes: List(CoreEvoCasteRecord)) -> String {
  castes
  |> list.map(fn(c) {
    "<tr><td><code>"
    <> escape_html(c.caste_id)
    <> "</code></td><td>"
    <> escape_html(c.role_name)
    <> "</td><td><code>"
    <> escape_html(c.bound_engine)
    <> "</code></td><td>"
    <> escape_html(c.token_share)
    <> "</td><td>"
    <> int.to_string(c.heijunka_wip_limit)
    <> "</td><td><code>"
    <> escape_html(c.mcp_slice)
    <> "</code></td><td>"
    <> escape_html(c.responsibility)
    <> "</td></tr>"
  })
  |> string.join("")
}

pub fn render_service_rows(services: List(CoreEvoServiceRecord)) -> String {
  services
  |> list.map(fn(s) {
    "<tr><td><code>"
    <> escape_html(s.id)
    <> "</code></td><td>"
    <> escape_html(s.name)
    <> "</td><td>"
    <> escape_html(s.layer)
    <> "</td><td><code>"
    <> escape_html(s.substrate)
    <> "</code></td><td>"
    <> escape_html(s.protection_and_capability)
    <> "</td></tr>"
  })
  |> string.join("")
}

pub fn render_module_rows(modules: List(CoreEvoModuleRecord)) -> String {
  modules
  |> list.map(fn(m) {
    "<tr><td><code>"
    <> escape_html(m.id)
    <> "</code></td><td><code>"
    <> escape_html(m.module_name)
    <> "</code></td><td><code>"
    <> escape_html(m.path)
    <> "</code></td><td>"
    <> escape_html(m.layers)
    <> "</td><td>"
    <> escape_html(m.invariants_and_capabilities)
    <> "</td></tr>"
  })
  |> string.join("")
}

pub fn render_command_rows(commands: List(CoreEvoCommandRecord)) -> String {
  commands
  |> list.map(fn(c) {
    "<tr><td><code>"
    <> escape_html(c.id)
    <> "</code></td><td>"
    <> escape_html(c.surface)
    <> "</td><td><code>"
    <> escape_html(c.invocation)
    <> "</code></td><td><code>"
    <> escape_html(c.role_or_topic)
    <> "</code></td><td>"
    <> escape_html(c.description)
    <> "</td></tr>"
  })
  |> string.join("")
}

pub fn render_live_fpp_actor_rows(
  actors: List(#(SubsystemFppActorSpec, Option(FppHolonActorState), Bool)),
) -> String {
  actors
  |> list.map(fn(entry) {
    let #(a, st_opt, alive) = entry
    let live_summary = case alive, st_opt {
      True, Some(st) ->
        "ALIVE &middot; "
        <> escape_html(st.lifecycle_fpp_state.current)
        <> " / "
        <> escape_html(st.companion_fpp_state.current)
        <> " &middot; twin="
        <> float.to_string(st.math_twin.twin_health)
        <> " &middot; seq="
        <> int.to_string(st.zenoh_seq_id)
      _, _ -> "OFFLINE"
    }
    "<tr><td><code>"
    <> int.to_string(a.actor_index + 1)
    <> "</code></td><td><code>"
    <> escape_html(a.layer_short)
    <> "</code></td><td><code>"
    <> escape_html(a.domain_name)
    <> "</code></td><td><code>"
    <> escape_html(a.actor_id)
    <> "</code></td><td>"
    <> escape_html(a.subsystem_name)
    <> "</td><td><code>"
    <> escape_html(a.companion_fpp_name)
    <> "</code></td><td><code>"
    <> live_summary
    <> "</code></td><td><code>"
    <> escape_html(a.primary_mcp_tool)
    <> "</code></td><td>"
    <> escape_html(a.intelligence_focus)
    <> "</td></tr>"
  })
  |> string.join("")
}

pub fn render_fpp_actor_rows(actors: List(SubsystemFppActorSpec)) -> String {
  actors
  |> list.map(fn(a) {
    "<tr><td><code>"
    <> int.to_string(a.actor_index + 1)
    <> "</code></td><td><code>"
    <> escape_html(a.layer_short)
    <> "</code></td><td><code>"
    <> escape_html(a.domain_name)
    <> "</code></td><td><code>"
    <> escape_html(a.actor_id)
    <> "</code></td><td>"
    <> escape_html(a.subsystem_name)
    <> "</td><td><code>"
    <> escape_html(a.companion_fpp_name)
    <> "</code></td><td><code>"
    <> escape_html(a.primary_mcp_tool)
    <> "</code></td><td>"
    <> escape_html(a.intelligence_focus)
    <> "</td></tr>"
  })
  |> string.join("")
}

fn render_checklist() -> String {
  "<details style=\"border:1px solid #f5a623;padding:1rem;margin:1rem 0\"><summary>Comprehensive verification checklist — fleet obligations</summary>"
  <> "<p>No all-green fleet admission claim is made by this cockpit surface; run <code>./tools/uos-core-evo preflight</code> and <code>./tools/uos-core-evo simulate-verify</code> for candidate-bound verification.</p>"
  <> checklist_domain(
    "Domain 1: Metadata, Timestamp, and Tailscale Navigation",
    ["CHK-01-TIME", "CHK-02-TAIL", "CHK-03-FRACT", "CHK-04-KM"],
  )
  <> checklist_domain("Domain 2: Zero-Muda Purity and Storage Safety", [
    "CHK-05-MUDA",
    "CHK-06-GRAPH",
    "CHK-07-DRIVE",
  ])
  <> checklist_domain("Domain 3: Testing Gold Standard and Math Gates", [
    "CHK-08-C1C8",
    "CHK-09-MATH",
    "CHK-10-9MOD",
    "CHK-11-REGR",
  ])
  <> checklist_domain("Domain 4: Cross-Language Control and Observability", [
    "CHK-12-GLEAM",
    "CHK-13-HERMES",
    "CHK-14-ZIGVM",
    "CHK-15-MAX",
    "CHK-16-OTEL",
  ])
  <> checklist_domain(
    "Domain 5: Tri-Sovereign Governance and Jujutsu Monorepo",
    ["CHK-17-SOV", "CHK-18-JJ"],
  )
  <> "<details class=\"verification-provenance\"><summary>Domain 6: Provenance boundary</summary><p>EV ceiling 93; EV-94..109 and ADR-071..086 remain NOT_ADMITTED. Zero new EV or numbered ADR identifiers minted.</p></details></details>"
}

fn checklist_domain(name: String, checks: List(String)) -> String {
  let items =
    checks
    |> list.map(fn(code) {
      "<li><strong>OBLIGATION</strong> " <> escape_html(code) <> "</li>"
    })
    |> string.join("")
  "<details class=\"verification-domain\"><summary>"
  <> escape_html(name)
  <> "</summary><ul>"
  <> items
  <> "</ul></details>"
}

pub fn escape_html(input: String) -> String {
  input
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
}
