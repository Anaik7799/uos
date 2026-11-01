//// UOS-ZLP-v3 Supervised Lean 4.33.0 + Zig 0.16.0 + Gleam/OTP 29.0.5 + MCP +
//// Zenoh Port Hyperplane Browser Cockpit (GET /zlp).
//// STAMP: SC-GLM-UI-001, SC-CHECKLIST-001, SC-HARNESS-MCP-001, SC-ZLP-PORT-001

import cepaf_gleam/mcp/transports/zlp_hyperplane
import cepaf_gleam/ui/wisp/zlp_api.{
  type ZlpExportKernel, type ZlpShardObservation, type ZlpTheoremRecord,
}
import gleam/int
import gleam/list
import gleam/string

const spec_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261101-1225-uos-zlp-v3-lean4-zig-otp29-zenoh-hyperplane-spec.md"

const wiki_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/wiki/20261101-1248-uos-zlp-v3-supervised-lean4-zig-otp29-zenoh-hyperplane.md"

const zk_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20261101-1248-zlp-v3-supervised-otp29-port-hyperplane-decision.md"

const sop_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/sop/20261101-1248-uos-zlp-v3-hyperplane-operations-and-verification-sop.md"

const contract_url = "http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261101-1410-zlp-hyperplane-port-contract.md"

const skill_url = "http://nas-1.tail55d152.ts.net:4100/files/.agents/skills/uos-zlp-hyperplane/SKILL.md"

const lean_url = "http://nas-1.tail55d152.ts.net:4100/files/formal/lean/UosZlpHyperplane.lean"

pub fn view() -> String {
  let binary_available = zlp_hyperplane.is_binary_available()
  let pool_running = zlp_hyperplane.is_running()
  let shards = zlp_api.observe_shards()
  let theorems = zlp_api.get_theorems()
  let exports = zlp_api.get_export_kernels()
  let runtime_label = zlp_api.runtime_status_label(binary_available, pool_running)

  "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>UOS-ZLP-v3 Hyperplane Cockpit</title></head><body style=\"margin:0;background:#0a0e17;color:#e0e6ed;font-family:system-ui,-apple-system,sans-serif\">"
  <> "<div class=\"uos-zlp-cockpit\" style=\"box-sizing:border-box;width:100%;max-width:100%;overflow-x:auto;padding:1.5rem;background:#0a0e17;color:#e0e6ed\">"
  <> "<style>.uos-zlp-cockpit{overflow-wrap:anywhere}.uos-zlp-cockpit a{color:#4fd1c5}.uos-zlp-cockpit table{display:block;overflow-x:auto;max-width:100%;color:#e0e6ed;background:#0a0e17;border-collapse:collapse}.uos-zlp-cockpit th,.uos-zlp-cockpit td{color:#e0e6ed;background:#0a0e17;border-bottom:1px solid #34435b;padding:.5rem;min-width:6rem;text-align:left}.uos-zlp-cockpit th{color:#b7c7db}.uos-zlp-cockpit code{color:#9ae6b4;background:transparent}@media(max-width:480px){.uos-zlp-cockpit{padding:.75rem!important}.uos-zlp-cockpit section{padding:.75rem!important}.uos-zlp-cockpit table{font-size:.875rem}}</style>"
  <> "<nav style=\"margin-bottom:1rem;padding-bottom:.75rem;border-bottom:1px solid #243044\">"
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/\">Cockpit</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/zenoh\">Zenoh Mesh</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/planning\">Planning</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/wiki\">Hermes Wiki</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/zk\">ZigVM ZK</a> &middot; "
  <> "<strong><code>http://nas-1.tail55d152.ts.net:4100/zlp</code></strong></nav>"
  <> "<header><h1 style=\"color:#00d4aa\">UOS-ZLP-v3 Supervised Lean 4 + Zig + OTP 29 + Zenoh Port Hyperplane</h1>"
  <> "<p>OS-isolated OTP 29 port pool linking <code>Lean 4.33.0</code> C-ABI kernels with <code>Zig 0.16.0</code> Zen 5 AVX-512 Two-Lane <code>epoll</code> + <code>eventfd</code> framing and Dual-ETS Zenoh SSE auto-replay.</p>"
  <> "<p><strong>Evidence scope:</strong> candidate_development_observation &middot; <strong>Admitted EV ceiling:</strong> <code>EV-"
  <> int.to_string(zlp_hyperplane.admitted_ev_ceiling)
  <> "</code> &middot; <strong>System admission:</strong> <code>NOT_GRANTED (system_admitted=false)</code></p></header>"
  <> render_runtime_summary(runtime_label, binary_available, pool_running, shards)
  <> "<section><h2>Live JSON Telemetry &amp; #km-triad Corpus Links</h2>"
  <> "<p><a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/zlp/status\">Runtime status JSON</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/zlp/theorems\">21-Theorem &amp; C-ABI JSON</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/zlp/lanes\">Two-Lane Zen 5 Architecture JSON</a></p>"
  <> "<p><a href=\""
  <> contract_url
  <> "\">Contract SC-ZLP-PORT-001</a> &middot; <a href=\""
  <> spec_url
  <> "\">Design &amp; Math Spec</a> &middot; <a href=\""
  <> wiki_url
  <> "\">Hermes Wiki Guide</a> &middot; <a href=\""
  <> zk_url
  <> "\">ZK Decision Note</a> &middot; <a href=\""
  <> sop_url
  <> "\">Operations SOP</a> &middot; <a href=\""
  <> skill_url
  <> "\">Agent Skill</a> &middot; <a href=\""
  <> lean_url
  <> "\">UosZlpHyperplane.lean</a></p></section>"
  <> "<section><h2>Supervised Dual-ETS Port Shards</h2><table><thead><tr>"
  <> "<th>Shard</th><th>Status</th><th>OS PID</th><th>Active SSE Subs</th><th>In-Flight Heavy</th><th>Perceus Excl</th>"
  <> "</tr></thead><tbody>"
  <> render_shard_rows(shards)
  <> "</tbody></table></section>"
  <> "<section><h2>8 Exported Lean 4.33.0 @[export] C-ABI Kernels</h2><table><thead><tr>"
  <> "<th>C Symbol</th><th>Lean Definition</th><th>Execution Lane</th><th>Purpose</th>"
  <> "</tr></thead><tbody>"
  <> render_export_rows(exports)
  <> "</tbody></table></section>"
  <> "<section><h2>21 Zero-Sorry Lean 4.33.0 Mechanized Theorems</h2><table><thead><tr>"
  <> "<th>ID</th><th>Theorem</th><th>Layer</th><th>Contract</th><th>Mechanized Invariant</th>"
  <> "</tr></thead><tbody>"
  <> render_theorem_rows(theorems)
  <> "</tbody></table></section>"
  <> render_checklist()
  <> "<section style=\"border:1px solid #ff6b6b;padding:1rem;margin-top:1rem\"><h2>Non-Negotiable Constitutional Boundaries</h2>"
  <> "<p>Gleam/OTP retains sole policy and effect authority (<code>SC-HARNESS-MCP-001</code>, Theorem <code>T10</code>). In-process Lean NIFs are barred (<code>SC-ZLP-PORT-001</code>). Root NVMe <code>[REDACTED_SYSTEM_OS_SERIAL]</code>, standalone Jujutsu (<code>.jj/</code>), and <code>EV-93</code> ceiling remain strictly enforced.</p></section>"
  <> "<footer style=\"margin-top:1rem;padding-top:.75rem;border-top:1px solid #243044\"><a href=\"http://nas-1.tail55d152.ts.net:4100/\">UOS Cockpit</a> &middot; <a href=\"http://nas-1.tail55d152.ts.net:4100/wiki\">Wiki</a> &middot; <a href=\"http://nas-1.tail55d152.ts.net:4100/zk\">ZK</a> &middot; UOS footer: component and cockpit observations do not grant global system admission.</footer>"
  <> "</div></body></html>"
}

fn render_runtime_summary(
  runtime_label: String,
  binary_available: Bool,
  pool_running: Bool,
  shards: List(ZlpShardObservation),
) -> String {
  let total_subs = list.fold(shards, 0, fn(acc, s) { acc + s.active_subs })
  "<section style=\"border:1px solid #34435b;padding:1rem;margin:1rem 0\">"
  <> "<h2>Runtime Observation</h2><ul>"
  <> "<li>Status: <code>"
  <> escape_html(runtime_label)
  <> "</code></li>"
  <> "<li>Port binary (<code>var/zlp/uos_zlp_v3_port</code>): <code>"
  <> bool_label(binary_available)
  <> "</code></li>"
  <> "<li>OTP 29 shard supervisor (<code>uos_zlp_sup</code>): <code>"
  <> bool_label(pool_running)
  <> "</code></li>"
  <> "<li>Observed healthy shards: <code>"
  <> int.to_string(list.length(shards))
  <> "</code> &middot; Active Zenoh SSE subscriptions: <code>"
  <> int.to_string(total_subs)
  <> "</code></li>"
  <> "<li>Two-Key CLI Gate: <code>bash tools/uos-cli zlp-check</code> (<code>G-ZLP</code>)</li>"
  <> "</ul></section>"
}

pub fn render_shard_rows(shards: List(ZlpShardObservation)) -> String {
  case shards {
    [] ->
      "<tr><td colspan=\"6\"><code>pool_stopped_or_unobserved</code> — call <code>zlp_hyperplane.ensure_started(shards: 4)</code> or run <code>bash tools/uos-cli zlp-check</code></td></tr>"
    _ ->
      shards
      |> list.map(fn(s) {
        "<tr><td><code>"
        <> int.to_string(s.shard_id)
        <> "</code></td><td><code>"
        <> escape_html(s.status)
        <> "</code></td><td><code>"
        <> int.to_string(s.os_pid)
        <> "</code></td><td>"
        <> int.to_string(s.active_subs)
        <> "</td><td>"
        <> int.to_string(s.in_flight_heavy)
        <> "</td><td>"
        <> int.to_string(s.perceus_excl)
        <> "</td></tr>"
      })
      |> string.join("")
  }
}

pub fn render_export_rows(exports: List(ZlpExportKernel)) -> String {
  exports
  |> list.map(fn(k) {
    "<tr><td><code>"
    <> escape_html(k.c_symbol)
    <> "</code></td><td><code>"
    <> escape_html(k.lean_fn)
    <> "</code></td><td>"
    <> escape_html(k.lane)
    <> "</td><td>"
    <> escape_html(k.purpose)
    <> "</td></tr>"
  })
  |> string.join("")
}

pub fn render_theorem_rows(theorems: List(ZlpTheoremRecord)) -> String {
  theorems
  |> list.map(fn(t) {
    "<tr><td><code>"
    <> escape_html(t.id)
    <> "</code></td><td><code>"
    <> escape_html(t.name)
    <> "</code></td><td>"
    <> escape_html(t.layer)
    <> "</td><td><code>"
    <> escape_html(t.contract)
    <> "</code></td><td>"
    <> escape_html(t.statement)
    <> "</td></tr>"
  })
  |> string.join("")
}

fn render_checklist() -> String {
  "<details style=\"border:1px solid #f5a623;padding:1rem;margin:1rem 0\"><summary>Comprehensive verification checklist — fleet obligations</summary>"
  <> "<p>No all-green fleet admission claim is made by this cockpit surface; run <code>bash tools/uos-cli zlp-check</code> for candidate-bound two-key verification.</p>"
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

fn bool_label(flag: Bool) -> String {
  case flag {
    True -> "true"
    False -> "false"
  }
}

pub fn escape_html(input: String) -> String {
  input
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
}
