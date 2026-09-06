//// 17-Aspect audit (UOS `EV-24` 17 Aspect Processes, wiki 20260906-1730).
//// Every aspect is a structural, deterministic check over the composed widget tree and the
//// driver context. Verdicts are fail-closed: anything not positively evidenced is `Fail`;
//// aspects that can only be evidenced by declaration (dictionary bindings) return `Declared`.
//// STAMP: SC-TUI-ASPECT-001.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import uos_tui/frame
import uos_tui/geometry.{type Size}
import uos_tui/render
import uos_tui/widget.{type Widget}

pub const tailnet_fqdn = "http://nas-1.tail55d152.ts.net:4100"

pub const os_nvme_serial = "25503L801736"

pub type Aspect {
  SubstrateStorageSafety
  StandaloneJujutsu
  ZeroMudaPurity
  GleamOtpSupervisor
  ZigVmEngine
  HermesEvidence
  MathematicalAuthority
  BiosemioticCybernetics
  QuarantinedMaxInference
  ZenohTelemetry
  AgUiEventStream
  A2UiCatalog
  PentaStackAccessibility
  TailscaleFqdnNavigation
  ComprehensiveChecklist
  KnowledgeTriad
  SaPlanDurability
}

pub const all = [
  SubstrateStorageSafety,
  StandaloneJujutsu,
  ZeroMudaPurity,
  GleamOtpSupervisor,
  ZigVmEngine,
  HermesEvidence,
  MathematicalAuthority,
  BiosemioticCybernetics,
  QuarantinedMaxInference,
  ZenohTelemetry,
  AgUiEventStream,
  A2UiCatalog,
  PentaStackAccessibility,
  TailscaleFqdnNavigation,
  ComprehensiveChecklist,
  KnowledgeTriad,
  SaPlanDurability,
]

pub fn number(aspect: Aspect) -> Int {
  case aspect {
    SubstrateStorageSafety -> 1
    StandaloneJujutsu -> 2
    ZeroMudaPurity -> 3
    GleamOtpSupervisor -> 4
    ZigVmEngine -> 5
    HermesEvidence -> 6
    MathematicalAuthority -> 7
    BiosemioticCybernetics -> 8
    QuarantinedMaxInference -> 9
    ZenohTelemetry -> 10
    AgUiEventStream -> 11
    A2UiCatalog -> 12
    PentaStackAccessibility -> 13
    TailscaleFqdnNavigation -> 14
    ComprehensiveChecklist -> 15
    KnowledgeTriad -> 16
    SaPlanDurability -> 17
  }
}

pub fn name(aspect: Aspect) -> String {
  case aspect {
    SubstrateStorageSafety -> "Substrate & Hardware Storage Safety"
    StandaloneJujutsu -> "Standalone Jujutsu Monorepo Discipline"
    ZeroMudaPurity -> "Zero-Muda Purity & Waste Elimination"
    GleamOtpSupervisor -> "Gleam/OTP Root Supervisor"
    ZigVmEngine -> "ZigVM Deterministic Engine & VFS Laws"
    HermesEvidence -> "Hermes Formal Evidence & Gospel"
    MathematicalAuthority -> "Mathematical Authority & Conservation"
    BiosemioticCybernetics -> "Biosemiotic Cybernetics & Rocha Cut"
    QuarantinedMaxInference -> "Quarantined Modular MAX Inference"
    ZenohTelemetry -> "Zenoh OoZ & MoZ Mesh Telemetry"
    AgUiEventStream -> "AG-UI 32-Event SSE Stream"
    A2UiCatalog -> "A2UI Declarative Catalog"
    PentaStackAccessibility -> "Penta-Stack Multi-Interface Accessibility"
    TailscaleFqdnNavigation -> "Universal Tailscale FQDN Web Navigation"
    ComprehensiveChecklist -> "Comprehensive Verification Checklist"
    KnowledgeTriad -> "Knowledge Management Triad"
    SaPlanDurability -> "Sa-Plan & Bionic Durable Workflows"
  }
}

pub type Verdict {
  Pass
  Declared
  Fail
}

pub type Finding {
  Finding(aspect: Aspect, verdict: Verdict, evidence: String)
}

pub type Interlock {
  Locked(serial: String)
  Unlocked
  Unprobed
}

pub type Vcs {
  Jujutsu(change_id: String)
  Git
  UnknownVcs
}

/// Facts the driver knows that the widget tree cannot show by itself.
pub type Context {
  Context(
    interlock: Interlock,
    vcs: Vcs,
    dependencies: List(String),
    supervised: Bool,
    engine_ports: List(String),
    lean_proof_refs: List(String),
    rocha_cut_declared: Bool,
    telemetry_channels: List(String),
    lease_epoch: Int,
    size: Size,
  )
}

/// A context with nothing evidenced (every aspect fails except pure structural ones).
pub fn empty_context(size: Size) -> Context {
  Context(Unprobed, UnknownVcs, [], False, [], [], False, [], 0, size)
}

fn all_text(widget: Widget(msg)) -> String {
  widget |> widget.flatten |> list.flat_map(widget.texts) |> string.join("\n")
}

fn find_kind(widget: Widget(msg), kind: String) -> Option(Widget(msg)) {
  widget
  |> widget.flatten
  |> list.find(fn(w) { widget.kind_of(w) == kind })
  |> option.from_result
}

fn barred(deps: List(String)) -> List(String) {
  list.filter(deps, fn(d) {
    let d = string.lowercase(d)
    string.contains(d, "bevy") || string.contains(d, "graphite")
  })
}

/// Audit one composed screen against all 17 aspects.
pub fn audit(widget: Widget(msg), ctx: Context) -> List(Finding) {
  let text = all_text(widget)
  list.map(all, fn(aspect) { check(aspect, widget, text, ctx) })
}

fn check(
  aspect: Aspect,
  widget: Widget(msg),
  text: String,
  ctx: Context,
) -> Finding {
  case aspect {
    SubstrateStorageSafety ->
      case ctx.interlock, string.contains(text, os_nvme_serial) {
        Locked(serial), True if serial == os_nvme_serial ->
          Finding(
            aspect,
            Pass,
            "interlock probed Locked(" <> serial <> ") and serial displayed",
          )
        Locked(_), _ ->
          Finding(aspect, Fail, "interlock serial mismatch or not displayed")
        Unlocked, _ -> Finding(aspect, Fail, "interlock reports Unlocked")
        Unprobed, _ -> Finding(aspect, Fail, "interlock never probed")
      }
    StandaloneJujutsu ->
      case ctx.vcs {
        Jujutsu(change) if change != "" ->
          Finding(aspect, Pass, "jj change " <> change)
        Jujutsu(_) -> Finding(aspect, Fail, "jj declared without change id")
        Git -> Finding(aspect, Fail, "git working copy")
        UnknownVcs -> Finding(aspect, Fail, "vcs unknown")
      }
    ZeroMudaPurity ->
      case barred(ctx.dependencies), ctx.dependencies {
        _, [] -> Finding(aspect, Fail, "dependency manifest not supplied")
        [], deps ->
          Finding(
            aspect,
            Pass,
            "0 barred among " <> string.inspect(list.length(deps)) <> " deps",
          )
        bad, _ ->
          Finding(aspect, Fail, "barred deps: " <> string.join(bad, ","))
      }
    GleamOtpSupervisor ->
      case ctx.supervised {
        True -> Finding(aspect, Pass, "runtime started as supervised child")
        False -> Finding(aspect, Fail, "runtime not under a supervisor")
      }
    ZigVmEngine -> port_declared(aspect, ctx, "zigvm_tlm_in")
    HermesEvidence -> port_declared(aspect, ctx, "hermes_evidence_in")
    MathematicalAuthority ->
      case ctx.lean_proof_refs {
        [] -> Finding(aspect, Fail, "no Lean proof reference bound")
        refs ->
          Finding(aspect, Declared, "bound proofs: " <> string.join(refs, ","))
      }
    BiosemioticCybernetics ->
      case ctx.rocha_cut_declared {
        True ->
          Finding(
            aspect,
            Declared,
            "Rocha cut declared: intents emitted, never executed by the TUI",
          )
        False -> Finding(aspect, Fail, "no Rocha cut declaration")
      }
    QuarantinedMaxInference -> port_declared(aspect, ctx, "max_inference_in")
    ZenohTelemetry ->
      case ctx.telemetry_channels {
        [] -> Finding(aspect, Fail, "no telemetry channels emitted")
        chans ->
          Finding(
            aspect,
            Pass,
            string.inspect(list.length(chans)) <> " channels emitted",
          )
      }
    AgUiEventStream ->
      case find_by_id(widget, "ag-ui-stream") {
        Some(widget.Log(..)) ->
          Finding(aspect, Pass, "Log#ag-ui-stream mounted")
        _ -> Finding(aspect, Fail, "no Log widget with id ag-ui-stream")
      }
    A2UiCatalog -> {
      let kinds =
        widget |> widget.flatten |> list.map(widget.kind_of) |> list.unique
      let n = list.length(kinds)
      case n >= 8 {
        True ->
          Finding(
            aspect,
            Pass,
            string.inspect(n)
              <> "/"
              <> string.inspect(list.length(widget.catalog))
              <> " catalog families composed",
          )
        False ->
          Finding(
            aspect,
            Fail,
            "only "
              <> string.inspect(n)
              <> " catalog families composed (need 8)",
          )
      }
    }
    PentaStackAccessibility -> {
      let f = render.compose(widget, ctx.size, None, render.dark)
      case frame.is_well_formed(f), frame.to_text(f) != "" {
        True, True ->
          Finding(
            aspect,
            Pass,
            "frame well-formed at "
              <> string.inspect(ctx.size)
              <> ", text and ANSI projections available",
          )
        False, _ ->
          Finding(aspect, Fail, "frame violates width/height invariant")
        _, False -> Finding(aspect, Fail, "empty text projection")
      }
    }
    TailscaleFqdnNavigation ->
      case string.contains(text, tailnet_fqdn) {
        True -> Finding(aspect, Pass, "FQDN link present")
        False ->
          Finding(aspect, Fail, "no " <> tailnet_fqdn <> " link on screen")
      }
    ComprehensiveChecklist ->
      case find_kind(widget, "Checklist") {
        Some(widget.Checklist(_, domains, _, _)) -> {
          let items =
            list.fold(domains, 0, fn(acc, d) { acc + list.length(d.items) })
          case list.length(domains), items {
            5, 18 -> Finding(aspect, Pass, "5 domains / 18 checkpoints mounted")
            d, i ->
              Finding(
                aspect,
                Fail,
                string.inspect(d)
                  <> " domains / "
                  <> string.inspect(i)
                  <> " items (need 5/18)",
              )
          }
        }
        _ -> Finding(aspect, Fail, "no Checklist widget")
      }
    KnowledgeTriad ->
      case string.contains(text, "[[wiki:") && string.contains(text, "[[zk:") {
        True -> Finding(aspect, Pass, "wiki and zk transclusions present")
        False ->
          Finding(
            aspect,
            Fail,
            "missing [[wiki:...]] or [[zk:...]] transclusion",
          )
      }
    SaPlanDurability ->
      case find_by_id(widget, "sa-plan-tasks"), ctx.lease_epoch > 0 {
        Some(widget.DataTable(..)), True ->
          Finding(
            aspect,
            Pass,
            "sa-plan table mounted, lease epoch "
              <> string.inspect(ctx.lease_epoch),
          )
        Some(widget.DataTable(..)), False ->
          Finding(aspect, Fail, "sa-plan table without a live lease epoch")
        _, _ -> Finding(aspect, Fail, "no DataTable#sa-plan-tasks")
      }
  }
}

fn port_declared(aspect: Aspect, ctx: Context, port: String) -> Finding {
  case list.contains(ctx.engine_ports, port) {
    True ->
      Finding(aspect, Declared, "port " <> port <> " declared in F´ dictionary")
    False -> Finding(aspect, Fail, "port " <> port <> " missing")
  }
}

fn find_by_id(widget: Widget(msg), id: String) -> Option(Widget(msg)) {
  widget.find(widget, id)
}

pub fn passed(findings: List(Finding)) -> Int {
  list.count(findings, fn(f) { f.verdict == Pass })
}

pub fn declared(findings: List(Finding)) -> Int {
  list.count(findings, fn(f) { f.verdict == Declared })
}

pub fn failed(findings: List(Finding)) -> Int {
  list.count(findings, fn(f) { f.verdict == Fail })
}

/// Admission is fail-closed: any Fail blocks.
pub fn admissible(findings: List(Finding)) -> Bool {
  failed(findings) == 0
}

pub fn verdict_label(v: Verdict) -> String {
  case v {
    Pass -> "PASS"
    Declared -> "DECLARED"
    Fail -> "FAIL"
  }
}
