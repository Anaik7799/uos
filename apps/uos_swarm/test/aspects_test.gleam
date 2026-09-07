import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import prng
import uos_swarm/cockpit
import uos_tui/aspects.{type Context, type Finding, Context, Fail, Pass}
import uos_tui/geometry.{Size}
import uos_tui/layout.{Cells, Vertical}
import uos_tui/style
import uos_tui/widget

fn model() -> cockpit.Model {
  cockpit.Model(
    ..cockpit.init_model("2026-09-06T21:23:36Z", "kxqzrlmp"),
    lease_epoch: 3,
  )
}

fn ctx() -> Context {
  cockpit.context(model(), Size(120, 40), True, ["gleam_stdlib", "gleam_otp"])
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

pub fn fqdn_missing_fails_aspect_14_test() {
  let without =
    widget.Container(
      "root",
      Vertical,
      [#(Cells(1), widget.Static("s", "no link here", style.none))],
      False,
      "",
    )
  verdict(aspects.audit(without, ctx()), aspects.TailscaleFqdnNavigation)
  |> should.equal(Fail)
  verdict(
    aspects.audit(cockpit.view(model()), ctx()),
    aspects.TailscaleFqdnNavigation,
  )
  |> should.equal(Pass)
}

pub fn checklist_shape_enforced_test() {
  let short =
    widget.Checklist(
      "c",
      [widget.ChecklistDomain("D1", [widget.ChecklistItem("A", "a", True)])],
      [],
      None,
    )
  verdict(aspects.audit(short, ctx()), aspects.ComprehensiveChecklist)
  |> should.equal(Fail)
}

pub fn checklist_unmet_items_fail_and_list_ids_test() {
  // A correctly-shaped 5-domain/18-item checklist with everything unmet except the few ids
  // that `cockpit.evidence_checklist_passed` could actually evidence in-process. CHK-08-C1C8
  // has no in-process evidence source, so it must always be reported as unmet here.
  let full =
    widget.Checklist(
      "c",
      cockpit.checklist_domains([
        "CHK-02-TAIL", "CHK-05-MUDA", "CHK-06-GRAPH", "CHK-07-DRIVE",
        "CHK-12-GLEAM", "CHK-16-OTEL", "CHK-18-JJ",
      ]),
      [],
      None,
    )
  let f = aspects.audit(full, ctx())
  verdict(f, aspects.ComprehensiveChecklist) |> should.equal(Fail)
  case list.find(f, fn(x) { x.aspect == aspects.ComprehensiveChecklist }) {
    Ok(finding) -> string.contains(finding.evidence, "CHK-08") |> should.be_true
    Error(_) -> should.fail()
  }
}

pub fn barred_dependency_fails_zero_muda_test() {
  let c = Context(..ctx(), dependencies: ["gleam_stdlib", "bevy_ecs"])
  verdict(aspects.audit(cockpit.view(model()), c), aspects.ZeroMudaPurity)
  |> should.equal(Fail)
}

pub fn unlocked_or_unprobed_interlock_fails_test() {
  verdict(
    aspects.audit(
      cockpit.view(model()),
      Context(..ctx(), interlock: aspects.Unlocked),
    ),
    aspects.SubstrateStorageSafety,
  )
  |> should.equal(Fail)
  verdict(
    aspects.audit(
      cockpit.view(model()),
      Context(..ctx(), interlock: aspects.Unprobed),
    ),
    aspects.SubstrateStorageSafety,
  )
  |> should.equal(Fail)
}

pub fn git_vcs_fails_aspect_2_test() {
  verdict(
    aspects.audit(cockpit.view(model()), Context(..ctx(), vcs: aspects.Git)),
    aspects.StandaloneJujutsu,
  )
  |> should.equal(Fail)
}

pub fn unsupervised_runtime_declared_aspect_4_test() {
  verdict(
    aspects.audit(cockpit.view(model()), Context(..ctx(), supervised: False)),
    aspects.GleamOtpSupervisor,
  )
  |> should.equal(aspects.Declared)
}

pub fn engine_ports_only_reach_declared_test() {
  let f = aspects.audit(cockpit.view(model()), ctx())
  verdict(f, aspects.ZigVmEngine) |> should.equal(aspects.Declared)
  verdict(f, aspects.HermesEvidence) |> should.equal(aspects.Declared)
  verdict(f, aspects.QuarantinedMaxInference) |> should.equal(aspects.Declared)
  verdict(
    aspects.audit(cockpit.view(model()), Context(..ctx(), engine_ports: [])),
    aspects.ZigVmEngine,
  )
  |> should.equal(Fail)
}

pub fn sa_plan_requires_live_lease_test() {
  let m = cockpit.Model(..model(), lease_epoch: 0, tab: 5)
  let c = cockpit.context(m, Size(120, 40), True, ["gleam_stdlib"])
  // No live lease epoch observed is Declared (soft), not Fail: the table is mounted, the
  // epoch is simply not yet evidenced by a real coordinator in this invocation.
  verdict(aspects.audit(cockpit.view(m), c), aspects.SaPlanDurability)
  |> should.equal(aspects.Declared)
  let m = cockpit.Model(..m, lease_epoch: 9)
  verdict(
    aspects.audit(
      cockpit.view(m),
      cockpit.context(m, Size(120, 40), True, ["gleam_stdlib"]),
    ),
    aspects.SaPlanDurability,
  )
  |> should.equal(Pass)
}

pub fn km_transclusions_required_test() {
  let plain = widget.Static("s", aspects.tailnet_fqdn, style.none)
  verdict(aspects.audit(plain, ctx()), aspects.KnowledgeTriad)
  |> should.equal(Fail)
}

pub fn verdict_labels_test() {
  aspects.verdict_label(Pass) |> should.equal("PASS")
  aspects.verdict_label(aspects.Declared) |> should.equal("DECLARED")
  aspects.verdict_label(Fail) |> should.equal("FAIL")
}
