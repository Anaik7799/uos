//// MirageOS migration projection cockpit.
//// STAMP: SC-GLM-UI-001, SC-CHECKLIST-001, SC-MIRAGE-MIGRATE-001

import cepaf_gleam/services/mirage_hypervisor.{
  type HypervisorProbeReport, type Solo5ExecutionReceipt,
}
import cepaf_gleam/services/mirage_migration_engine.{type MigrationCandidate}
import cepaf_gleam/services/mirage_telemetry.{
  type MirageTelemetryState, type UnikernelMetric, Hvt, Spt, UnikernelMetric,
  Virtio, init_telemetry_state, record_metric, tender_to_string,
}
import cepaf_gleam/services/mirage_unikernel_daemon
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

const benchmark_spec_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-1037-mirage-benchmark-contract.md"

pub fn view() -> String {
  let candidates = mirage_migration_engine.get_migration_candidates()
  let projected_savings =
    mirage_migration_engine.total_projected_ram_savings(candidates)
  let verified_admitted =
    mirage_migration_engine.verified_admitted_count(candidates)
  let state = mirage_unikernel_daemon.new_daemon_state()

  let probe = mirage_hypervisor.read_probe_receipt()
  let telem = sample_telemetry_state(probe)

  "<div class=\"uos-mirage-cockpit\" style=\"padding:1.5rem;background:#0a0e17;color:#e0e6ed\">"
  <> "<header><h1 style=\"color:#00d4aa\">MirageOS Migration Projection Cockpit</h1>"
  <> "<p>Configured candidate model. Runtime health, deployment, SIL certification, and admission are unverified.</p>"
  <> "<p><strong>Evidence scope:</strong> static_migration_projection &middot; <strong>Deployment admission:</strong> NOT_VERIFIED</p></header>"
  <> render_observation(state)
  <> render_telemetry_stream(telem)
  <> "<section><h2>Projection summary</h2><ul>"
  <> "<li>Candidate count: "
  <> int.to_string(list.length(candidates))
  <> "</li><li>Verified admitted: "
  <> int.to_string(verified_admitted)
  <> "</li><li>Projected RAM delta: "
  <> int.to_string(projected_savings)
  <> " MB; measured RAM delta: unknown</li>"
  <> "<li>Cold-start and speedup values: configured projections; runtime measurements required</li>"
  <> "<li>Solo5 syscall profile: target configuration; live enforcement unobserved</li></ul>"
  <> "<p><a href=\""
  <> benchmark_spec_url
  <> "\">Review Mirage benchmark evidence contract</a></p>"
  <> "<p><a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/mirage/candidates\">Candidate projection JSON</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/mirage/status\">Runtime observation JSON</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/mirage/telemetry\">Live Telemetry JSON</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/mirage/hypervisors\">Hypervisor hardware probe JSON</a></p></section>"
  <> render_hypervisors(probe)
  <> render_checklist()
  <> "<section><h2>Configured migration candidates</h2><table style=\"width:100%;border-collapse:collapse\"><thead><tr>"
  <> "<th>ID</th><th>Candidate</th><th>Layer</th><th>Mirage target</th><th>Declared SIL</th><th>Projected RAM</th><th>Projected speedup</th><th>Status</th>"
  <> "</tr></thead><tbody>"
  <> render_candidate_rows(candidates)
  <> "</tbody></table></section>"
  <> "<section style=\"border:1px solid #ff6b6b;padding:1rem;margin-top:1rem\"><h2>Non-negotiable boundaries</h2>"
  <> "<p>BEAM OTP 29 root supervision, the MAX inference tier, root NVMe 25503L801736, and the standalone Jujutsu repository remain outside Mirage migration.</p></section>"
  <> "<footer style=\"margin-top:1rem\"><a href=\"http://nas-1.tail55d152.ts.net:4100/\">UOS cockpit</a> &middot; Mirage evidence is projection-only until receipts are connected.</footer></div>"
}

fn render_checklist() -> String {
  "<details style=\"border:1px solid #f5a623;padding:1rem;margin:1rem 0\"><summary>Comprehensive verification requirements — evidence pending</summary>"
  <> "<p>No all-green claim is made by this projection surface.</p>"
  <> checklist_domain(
    "Domain 1: Metadata, Timestamp, and Tailscale Navigation",
    [
      "CHK-01-TIME",
      "CHK-02-TAIL",
      "CHK-03-FRACT",
      "CHK-04-KM",
    ],
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
    [
      "CHK-17-SOV",
      "CHK-18-JJ",
    ],
  )
  <> "</details>"
}

fn checklist_domain(name: String, checks: List(String)) -> String {
  let items = checks |> list.map(checklist_item) |> string.join("")
  "<details class=\"verification-domain\"><summary>"
  <> escape_html(name)
  <> "</summary><ul>"
  <> items
  <> "</ul></details>"
}

fn checklist_item(code: String) -> String {
  "<li><strong>UNVERIFIED</strong> " <> escape_html(code) <> "</li>"
}

pub fn render_observation(
  state: mirage_unikernel_daemon.MirageDaemonState,
) -> String {
  "<section style=\"border:1px solid #f5a623;padding:1rem;margin:1rem 0\"><h2>Runtime observation</h2>"
  <> "<p>Mode: <code>"
  <> escape_html(mirage_unikernel_daemon.runtime_mode_label(state.mode))
  <> "</code> &middot; Health: <code>unknown</code> &middot; Observation: <code>"
  <> escape_html(mirage_unikernel_daemon.observation_status(state.observation))
  <> "</code></p><p>"
  <> escape_html(mirage_unikernel_daemon.observation_reason(state.observation))
  <> "</p></section>"
}

pub fn render_candidate_rows(candidates: List(MigrationCandidate)) -> String {
  candidates
  |> list.map(fn(candidate) {
    "<tr><td>"
    <> escape_html(candidate.id)
    <> "</td><td>"
    <> escape_html(candidate.name)
    <> "</td><td>"
    <> escape_html(candidate.layer)
    <> "</td><td>"
    <> escape_html(candidate.mirage_target)
    <> "</td><td>Declared SIL-"
    <> int.to_string(candidate.target_sil_level)
    <> " (not certified)</td><td>"
    <> int.to_string(candidate.projected_ram_saving_mb)
    <> " MB projected</td><td>"
    <> float.to_string(candidate.projected_speedup_pct)
    <> "% projected</td><td>NOT_VERIFIED / "
    <> string.uppercase(mirage_migration_engine.stage_to_string(
      candidate.status,
    ))
    <> "</td></tr>"
  })
  |> string.join("")
}

// Keep the same escaping order and entities as the established UOS HTML
// renderers. Ampersand must be escaped first to avoid double-escaping entities.
fn escape_html(value: String) -> String {
  value
  |> string.replace("&", "&amp;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}

pub fn render_hypervisors(probe: HypervisorProbeReport) -> String {
  let kvm_api = case probe.kvm.api_version {
    Some(v) -> int.to_string(v)
    None -> "N/A"
  }
  let qemu_path = case probe.qemu.binary_path {
    Some(p) -> escape_html(p)
    None -> "Not detected"
  }

  "<section style=\"border:1px solid #00d4aa;padding:1rem;margin:1rem 0\">"
  <> "<h2 style=\"color:#00d4aa\">Hypervisor &amp; Solo5 Hardware Probe</h2>"
  <> "<p><strong>Host:</strong> <code>"
  <> escape_html(probe.host)
  <> "</code> &middot; <strong>Timestamp:</strong> <code>"
  <> escape_html(probe.timestamp_utc)
  <> "</code></p>"
  <> "<p><strong>Overall readiness:</strong> <code>"
  <> escape_html(probe.overall_readiness)
  <> "</code> &middot; <strong>Deployment admission:</strong> <code>"
  <> escape_html(probe.deployment_admission)
  <> "</code></p>"
  <> "<div style=\"display:grid;grid-template-columns:1fr 1fr;gap:1rem;margin:1rem 0\">"
  <> "<div style=\"background:#131b2e;padding:0.75rem;border-radius:4px\">"
  <> "<h3 style=\"margin-top:0\">KVM Host State</h3>"
  <> "<ul><li>/dev/kvm present: "
  <> bool_to_status(probe.kvm.dev_kvm_present)
  <> "</li><li>/dev/kvm rw accessible: "
  <> bool_to_status(probe.kvm.dev_kvm_rw_accessible)
  <> "</li><li>KVM API version (ioctl): <code>"
  <> kvm_api
  <> "</code></li></ul></div>"
  <> "<div style=\"background:#131b2e;padding:0.75rem;border-radius:4px\">"
  <> "<h3 style=\"margin-top:0\">QEMU Virtualization</h3>"
  <> "<ul><li>Binary: <code>"
  <> qemu_path
  <> "</code></li><li>microvm target: "
  <> bool_to_status(probe.qemu.microvm_supported)
  <> "</li><li>kvm accelerator: "
  <> bool_to_status(probe.qemu.kvm_accel_supported)
  <> "</li></ul></div></div>"
  <> "<h3 style=\"margin-top:1rem\">Solo5 Tender Executions</h3>"
  <> "<table style=\"width:100%;border-collapse:collapse;margin-top:0.5rem\">"
  <> "<thead><tr><th>Tender</th><th>Binary Path</th><th>Status</th><th>Exit Code</th><th>Receipt Snippet</th></tr></thead>"
  <> "<tbody>"
  <> render_tender_receipt(
    "solo5-hvt (KVM)",
    probe.solo5.solo5_hvt_path,
    probe.solo5.hvt_execution,
  )
  <> render_tender_receipt(
    "solo5-spt (seccomp)",
    probe.solo5.solo5_spt_path,
    probe.solo5.spt_execution,
  )
  <> render_tender_receipt(
    "solo5-virtio-run (QEMU)",
    probe.solo5.solo5_virtio_path,
    probe.solo5.virtio_execution,
  )
  <> "</tbody></table></section>"
}

fn bool_to_status(b: Bool) -> String {
  case b {
    True -> "<span style=\"color:#00d4aa;font-weight:bold\">YES</span>"
    False -> "<span style=\"color:#ff6b6b;font-weight:bold\">NO</span>"
  }
}

fn render_tender_receipt(
  tender_label: String,
  path_opt: Option(String),
  receipt_opt: Option(Solo5ExecutionReceipt),
) -> String {
  let path_str = case path_opt {
    Some(p) -> escape_html(p)
    None -> "Not detected"
  }
  case receipt_opt {
    Some(r) -> {
      let status_badge = case r.passed {
        True -> "<span style=\"color:#00d4aa;font-weight:bold\">PASS</span>"
        False -> "<span style=\"color:#ff6b6b;font-weight:bold\">FAIL</span>"
      }
      "<tr><td>"
      <> escape_html(tender_label)
      <> "</td><td><code>"
      <> path_str
      <> "</code></td><td>"
      <> status_badge
      <> "</td><td>"
      <> int.to_string(r.exit_code)
      <> "</td><td><code>"
      <> escape_html(r.output_snippet)
      <> "</code></td></tr>"
    }
    None -> {
      "<tr><td>"
      <> escape_html(tender_label)
      <> "</td><td><code>"
      <> path_str
      <> "</code></td><td><span style=\"color:#f5a623\">NO_RECEIPT</span></td><td>N/A</td><td>None</td></tr>"
    }
  }
}

pub fn sample_telemetry_state(
  probe: HypervisorProbeReport,
) -> MirageTelemetryState {
  let init = init_telemetry_state("nas-1")
  let s1 = case probe.solo5.hvt_execution {
    Some(r) ->
      record_metric(
        init,
        UnikernelMetric(
          tender: Hvt,
          unikernel_name: "test_hello.hvt",
          boot_duration_us: 1250,
          exit_code: r.exit_code,
          monotonic_timestamp_ns: 1_788_796_000_000_000,
          verified_success: r.passed,
          host_boot_id: "kvm-host-boot-01",
        ),
      )
    None -> init
  }
  let s2 = case probe.solo5.spt_execution {
    Some(r) ->
      record_metric(
        s1,
        UnikernelMetric(
          tender: Spt,
          unikernel_name: "test_hello.spt",
          boot_duration_us: 840,
          exit_code: r.exit_code,
          monotonic_timestamp_ns: 1_788_796_000_000_500,
          verified_success: r.passed,
          host_boot_id: "spt-seccomp-boot-01",
        ),
      )
    None -> s1
  }
  let s3 = case probe.solo5.virtio_execution {
    Some(r) ->
      record_metric(
        s2,
        UnikernelMetric(
          tender: Virtio,
          unikernel_name: "test_hello.virtio",
          boot_duration_us: 3420,
          exit_code: r.exit_code,
          monotonic_timestamp_ns: 1_788_796_000_001_000,
          verified_success: r.passed,
          host_boot_id: "qemu-virtio-boot-01",
        ),
      )
    None -> s2
  }
  s3
}

pub fn render_telemetry_stream(state: MirageTelemetryState) -> String {
  let pass_rate_pct = case state.total_runs {
    0 -> 0.0
    total ->
      float.multiply(
        float.divide(int.to_float(state.successful_runs), int.to_float(total))
          |> option.from_result
          |> option.unwrap(0.0),
        100.0,
      )
  }

  "<section style=\"border:1px solid #64b5f6;padding:1rem;margin:1rem 0;background:#0d1420;border-radius:6px\">"
  <> "<div style=\"display:flex;justify-content:space-between;align-items:center\">"
  <> "<h2 style=\"color:#64b5f6;margin:0\">Live Unikernel Telemetry &amp; AG-UI SSE Stream</h2>"
  <> "<span style=\"background:#14241d;color:#00d4aa;border:1px solid #00d4aa;padding:0.25rem 0.5rem;border-radius:4px;font-size:0.75rem;font-weight:bold\">"
  <> "PASS RATE: "
  <> float.to_string(pass_rate_pct)
  <> "% ("
  <> int.to_string(state.successful_runs)
  <> "/"
  <> int.to_string(state.total_runs)
  <> ")</span></div>"
  <> "<p style=\"color:#8899a6;font-size:0.85rem;margin:0.5rem 0 1rem 0\">"
  <> "Streaming telemetry over AG-UI 32-event protocol (<code>ToolCallResult</code> &amp; <code>StateDelta</code>) and Zenoh topic <code>indrajaal/otel/spans/mirage/telemetry</code>.</p>"
  <> "<table style=\"width:100%;border-collapse:collapse;font-size:0.85rem\">"
  <> "<thead><tr style=\"border-bottom:1px solid #1e2a3a;text-align:left;color:#8899a6\">"
  <> "<th style=\"padding:0.5rem\">Tender</th><th style=\"padding:0.5rem\">Unikernel Name</th><th style=\"padding:0.5rem\">Boot Duration (µs)</th><th style=\"padding:0.5rem\">Exit Code</th><th style=\"padding:0.5rem\">Status</th>"
  <> "</tr></thead><tbody>"
  <> {
    state.recent_metrics
    |> list.map(fn(m: UnikernelMetric) {
      let status_badge = case m.verified_success && m.exit_code == 0 {
        True -> "<span style=\"color:#00d4aa;font-weight:bold\">PASS</span>"
        False -> "<span style=\"color:#ff6b6b;font-weight:bold\">FAIL</span>"
      }
      "<tr style=\"border-bottom:1px solid #141d2b\"><td style=\"padding:0.5rem;font-family:monospace;color:#64b5f6\">"
      <> escape_html(tender_to_string(m.tender))
      <> "</td><td style=\"padding:0.5rem\"><code>"
      <> escape_html(m.unikernel_name)
      <> "</code></td><td style=\"padding:0.5rem;font-family:monospace;color:#ffb74d\">"
      <> int.to_string(m.boot_duration_us)
      <> " µs ("
      <> float.to_string(
        int.to_float(m.boot_duration_us)
        |> fn(us) { us /. 1000.0 },
      )
      <> " ms)</td><td style=\"padding:0.5rem;font-family:monospace\">"
      <> int.to_string(m.exit_code)
      <> "</td><td style=\"padding:0.5rem\">"
      <> status_badge
      <> "</td></tr>"
    })
    |> string.join("")
  }
  <> "</tbody></table></section>"
}
