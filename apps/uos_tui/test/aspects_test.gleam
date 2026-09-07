import gleam/list
import gleam/option.{None}
import gleeunit/should
import prng
import uos_tui/aspects.{type Context, type Finding, Context, Fail, Pass}
import uos_tui/geometry.{Size}
import uos_tui/layout.{Cells, Fraction, Vertical}
import uos_tui/style
import uos_tui/widget.{
  type ChecklistDomain, ChecklistDomain, ChecklistItem, Column,
}

/// The library's own (cockpit-free) 5-domain/18-item checklist fixture, every item marked
/// met: this test audits the `aspects` library against a screen the library itself composes
/// directly from `uos_tui/widget`, not against any swarm/cockpit application screen.
fn checklist_domains() -> List(ChecklistDomain) {
  let item = fn(id, label) { ChecklistItem(id, label, True) }
  [
    ChecklistDomain("D1 Metadata & Tailscale", [
      item("CHK-01-TIME", "YYYYMMDD-HHSS- prefix"),
      item("CHK-02-TAIL", "Tailscale FQDN links"),
      item("CHK-03-FRACT", "fractal layer tags"),
      item("CHK-04-KM", "wiki/zk transclusions"),
    ]),
    ChecklistDomain("D2 Zero-Muda & Storage", [
      item("CHK-05-MUDA", "0 Bevy 0 Graphite"),
      item("CHK-06-GRAPH", "no Graphene NIF"),
      item("CHK-07-DRIVE", "NVMe " <> aspects.os_nvme_serial <> " locked"),
    ]),
    ChecklistDomain("D3 Testing Gold Std", [
      item("CHK-08-C1C8", "C1-C8 coverage"),
      item("CHK-09-MATH", "4 math gates"),
      item("CHK-10-9MOD", "9 modalities green"),
      item("CHK-11-REGR", "UI regression"),
    ]),
    ChecklistDomain("D4 Cross-Language", [
      item("CHK-12-GLEAM", "OTP supervisor"),
      item("CHK-13-HERMES", "Hermes evidence"),
      item("CHK-14-ZIGVM", "ZigVM kernel"),
      item("CHK-15-MAX", "MAX quarantine"),
      item("CHK-16-OTEL", "C3I telemetry"),
    ]),
    ChecklistDomain("D5 Governance & VCS", [
      item("CHK-17-SOV", "tri-sovereign consensus"),
      item("CHK-18-JJ", "standalone jj"),
    ]),
  ]
}

/// A widget tree assembled directly from `uos_tui/widget`, standing in for the small demo
/// screen a library caller (e.g. `uos_tui/gallery`) composes: a status bar carrying the
/// mandatory Tailscale FQDN and the denied NVMe serial, a properly-shaped checklist, a
/// `DataTable#sa-plan-tasks`, a `Log#ag-ui-stream`, and the wiki/zk transclusion text --
/// everything the 17 aspects look for, with no `cockpit` import anywhere.
fn screen() -> widget.Widget(Nil) {
  let header =
    widget.Header("header", "uos_tui", aspects.tailnet_fqdn, style.none)
  let status =
    widget.StatusBar("status", [
      widget.StatusField("", aspects.tailnet_fqdn, style.none),
    ])
  let checklist = widget.Checklist("checklist", checklist_domains(), [], None)
  let table =
    widget.DataTable(
      "sa-plan-tasks",
      [Column("task", Fraction(1))],
      [["demo task"]],
      0,
      None,
      None,
    )
  let log = widget.Log("ag-ui-stream", ["line one"], 0)
  let km =
    widget.Static(
      "km",
      "[[wiki:20260906-1730-uos-omni-fractal-matrix-and-17-aspect-wiki]] [[zk:20260905-1801-moc-uos-unified-master]]",
      style.none,
    )
  let footer = widget.Footer("footer", [])
  let progress = widget.ProgressBar("progress", 1.0, "done")
  widget.Container(
    "root",
    Vertical,
    [
      #(Cells(1), header),
      #(Cells(1), status),
      #(Cells(9), checklist),
      #(Cells(4), table),
      #(Cells(4), log),
      #(Cells(1), km),
      #(Cells(1), footer),
      #(Cells(1), progress),
    ],
    False,
    "",
  )
}

/// The audit context a library caller supplies directly (no `cockpit.context`): a real
/// `probe_interlock()` reading of this host, `Jujutsu("test")`, the same F´/lean/telemetry
/// declarations `cockpit.context` used to carry (captured here before that module's
/// deletion), `supervised: False` (this test is never started under a supervisor), and
/// `lease_epoch: 0` (no live lease observed).
fn ctx() -> Context {
  Context(
    interlock: aspects.probe_interlock(),
    vcs: aspects.Jujutsu("test"),
    dependencies: ["gleam_stdlib", "gleam_otp"],
    supervised: False,
    engine_ports: [
      "zigvm_tlm_in", "hermes_evidence_in", "max_inference_in", "zenoh_tlm_in",
      "agui_event_in", "saplan_lease_in",
    ],
    lean_proof_refs: [
      "formal/lean/Traceability.lean", "formal/lean/TwoLattice_STM.lean",
    ],
    rocha_cut_declared: True,
    telemetry_channels: [
      "FrameCount", "FrameMicros", "ScreenDepth", "CockpitMode",
    ],
    lease_epoch: 0,
    size: Size(120, 40),
  )
}

fn verdict(findings: List(Finding), aspect: aspects.Aspect) -> aspects.Verdict {
  case list.find(findings, fn(f) { f.aspect == aspect }) {
    Ok(f) -> f.verdict
    Error(_) -> Fail
  }
}

pub fn all_seventeen_numbered_test() {
  aspects.all |> list.map(aspects.number) |> should.equal(prng.range(1, 17))
  aspects.all
  |> list.map(aspects.name)
  |> list.unique
  |> list.length
  |> should.equal(17)
}

pub fn empty_context_fails_closed_test() {
  let findings =
    aspects.audit(
      widget.Static("s", "hello", style.none),
      aspects.empty_context(Size(10, 1)),
    )
  // 15 Fail, 1 Declared (GleamOtpSupervisor: unsupervised is Declared, not Fail), 1 Pass.
  aspects.failed(findings) |> should.equal(15)
  aspects.declared(findings) |> should.equal(1)
  verdict(findings, aspects.PentaStackAccessibility) |> should.equal(Pass)
  aspects.no_failures(findings) |> should.be_false
  aspects.admissible(findings) |> should.be_false
}

pub fn library_screen_has_no_failures_test() {
  let findings = aspects.audit(screen(), ctx())
  aspects.failed(findings) |> should.equal(0)
  aspects.no_failures(findings) |> should.be_true
  // Several aspects can only be Declared without a live supervised runtime and coordinator.
  aspects.admissible(findings) |> should.be_false
}

pub fn interlock_passes_on_this_host_test() {
  // This host really does carry the denied NVMe serial (`aspects.os_nvme_serial`), so the
  // real (unmocked) `probe_interlock()` locks and the aspect can honestly Pass.
  aspects.probe_interlock()
  |> should.equal(aspects.Locked(aspects.os_nvme_serial))
  verdict(aspects.audit(screen(), ctx()), aspects.SubstrateStorageSafety)
  |> should.equal(Pass)
}

pub fn fqdn_aspect_passes_test() {
  verdict(aspects.audit(screen(), ctx()), aspects.TailscaleFqdnNavigation)
  |> should.equal(Pass)
}

pub fn transclusion_aspect_passes_test() {
  verdict(aspects.audit(screen(), ctx()), aspects.KnowledgeTriad)
  |> should.equal(Pass)
}

pub fn unsupervised_runtime_declared_test() {
  verdict(aspects.audit(screen(), ctx()), aspects.GleamOtpSupervisor)
  |> should.equal(aspects.Declared)
}

pub fn checklist_shape_enforced_test() {
  let short =
    widget.Checklist(
      "c",
      [ChecklistDomain("D1", [ChecklistItem("A", "a", True)])],
      [],
      None,
    )
  verdict(aspects.audit(short, ctx()), aspects.ComprehensiveChecklist)
  |> should.equal(Fail)
}

pub fn barred_dependency_fails_zero_muda_test() {
  let c = Context(..ctx(), dependencies: ["gleam_stdlib", "bevy_ecs"])
  verdict(aspects.audit(screen(), c), aspects.ZeroMudaPurity)
  |> should.equal(Fail)
}

pub fn git_vcs_fails_aspect_2_test() {
  verdict(
    aspects.audit(screen(), Context(..ctx(), vcs: aspects.Git)),
    aspects.StandaloneJujutsu,
  )
  |> should.equal(Fail)
}

pub fn sa_plan_declared_without_live_lease_test() {
  verdict(aspects.audit(screen(), ctx()), aspects.SaPlanDurability)
  |> should.equal(aspects.Declared)
  let live_ctx = Context(..ctx(), lease_epoch: 9)
  verdict(aspects.audit(screen(), live_ctx), aspects.SaPlanDurability)
  |> should.equal(Pass)
}

pub fn verdict_labels_test() {
  aspects.verdict_label(Pass) |> should.equal("PASS")
  aspects.verdict_label(aspects.Declared) |> should.equal("DECLARED")
  aspects.verdict_label(Fail) |> should.equal("FAIL")
}
