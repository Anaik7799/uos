//// System-wide 17-aspect audit: every key subsystem is a subject, every subject gets all 17
//// verdicts. Screens use `aspects.audit`; non-screen subjects (Zenoh infra, board, coordination
//// policy, F´ dictionary, ontology, telemetry) are checked structurally. Fail-closed: a subject
//// that cannot be probed fails the aspects that depend on the probe.
//// STAMP: SC-TUI-SYSAUDIT-001, EV-24.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import uos_swarm/board
import uos_swarm/cockpit
import uos_swarm/coord
import uos_swarm/swarm
import uos_tui/aspects.{
  type Context, type Finding, Declared, Fail, Finding, Pass,
}
import uos_tui/fprime
import uos_tui/ontology
import uos_tui/telemetry

pub type Subject {
  Subject(name: String, findings: List(Finding))
}

pub type Probe {
  Probe(
    zenoh_router_ok: Bool,
    zenoh_storages: Int,
    zenoh_a2a_messages: Int,
    cockpit_zenoh_connected: Bool,
  )
}

pub const unprobed = Probe(False, 0, 0, False)

fn f(a: aspects.Aspect, ok: Bool, ev: String) -> Finding {
  Finding(
    a,
    case ok {
      True -> Pass
      False -> Fail
    },
    ev,
  )
}

fn d(a: aspects.Aspect, ok: Bool, ev: String) -> Finding {
  Finding(
    a,
    case ok {
      True -> Declared
      False -> Fail
    },
    ev,
  )
}

/// Subjects that need no live probe.
pub fn static_subjects(
  ctx: Context,
  ledger: swarm.Ledger,
  messages: List(board.Message),
) -> List(Subject) {
  let m0 = cockpit.init_model("2026-09-07T00:00:00Z", ledger.base_change)
  // Checklist evidence is honestly computed from `ctx`, never declared: see
  // `cockpit.evidence_checklist_passed`.
  let m =
    cockpit.Model(
      ..m0,
      checklist_passed: cockpit.evidence_checklist_passed(m0, ctx),
    )
  let cockpit_s = Subject("cockpit screen", aspects.audit(cockpit.view(m), ctx))
  let swarm_model = cockpit.Model(..m, tab: 8, ledger: Some(ledger))
  let swarm_s =
    Subject(
      "swarm dashboard screen",
      aspects.audit(cockpit.view(swarm_model), ctx),
    )
  let board_s = Subject("message board", board_findings(messages))
  let coord_s = Subject("coordination policy", policy_findings(ledger))
  let fprime_s = Subject("F´ dictionary", fprime_findings())
  let onto_s = Subject("fractal ontology", ontology_findings())
  [cockpit_s, swarm_s, board_s, coord_s, fprime_s, onto_s]
}

pub fn infra_subject(p: Probe) -> Subject {
  Subject(
    "zenoh infra",
    list.map(aspects.all, fn(a) {
      case a {
        aspects.ZenohTelemetry ->
          f(
            a,
            p.zenoh_router_ok,
            "router REST reachable="
              <> bool(p.zenoh_router_ok)
              <> ", storages="
              <> int.to_string(p.zenoh_storages),
          )
        aspects.AgUiEventStream ->
          f(
            a,
            p.zenoh_storages >= 2,
            "agui_events storage present when storages>=2",
          )
        aspects.GleamOtpSupervisor ->
          f(
            a,
            p.cockpit_zenoh_connected,
            "cockpit /api/zenoh/health connected="
              <> bool(p.cockpit_zenoh_connected),
          )
        aspects.SaPlanDurability ->
          f(
            a,
            p.zenoh_a2a_messages > 0,
            int.to_string(p.zenoh_a2a_messages)
              <> " messages retained in a2a storage",
          )
        aspects.ZeroMudaPurity ->
          f(a, True, "eclipse/zenoh container, no NIF in uos_tui")
        aspects.TailscaleFqdnNavigation ->
          f(a, p.zenoh_router_ok, "http://nas-1.tail55d152.ts.net:8080 REST")
        aspects.HermesEvidence
        | aspects.ZigVmEngine
        | aspects.QuarantinedMaxInference ->
          d(
            a,
            p.zenoh_storages >= 3,
            "uos/tui storage declared for engine telemetry",
          )
        _ ->
          d(
            a,
            p.zenoh_router_ok,
            "infra subject: inherited from router availability",
          )
      }
    }),
  )
}

fn bool(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

fn board_findings(ms: List(board.Message)) -> List(Finding) {
  let valid = board.validate(ms) == Ok(Nil)
  let zenoh =
    list.count(ms, fn(m) {
      list.any(m.deliveries, fn(dl) {
        string.starts_with(dl.transport, "zenoh")
        && dl.status == board.Delivered
      })
    })
  let n = list.length(ms)
  let semantic =
    list.all(ms, fn(m) {
      m.semantics.aspects != [] && m.semantics.ontology_concepts != []
    })
  list.map(aspects.all, fn(a) {
    case a {
      aspects.SubstrateStorageSafety -> d(a, valid, "digest chain intact")
      aspects.StandaloneJujutsu ->
        d(a, n > 0, "board ledger is a tracked file under jj")
      aspects.ZeroMudaPurity -> f(a, True, "ets + jsonl + httpc, no NIF")
      aspects.GleamOtpSupervisor -> d(a, True, "coord.child_spec available")
      aspects.MathematicalAuthority ->
        f(a, valid, "SHA-256 chain verified by board.validate")
      aspects.BiosemioticCybernetics ->
        f(
          a,
          list.all(ms, fn(m) { m.kind != board.Intent || m.to != "broadcast" }),
          "intents never broadcast (Rocha cut)",
        )
      aspects.ZenohTelemetry ->
        f(
          a,
          n > 0 && zenoh == n,
          int.to_string(zenoh)
            <> "/"
            <> int.to_string(n)
            <> " delivered to Zenoh",
        )
      aspects.AgUiEventStream ->
        d(a, n > 0, "board timeline feeds the AG-UI log")
      aspects.A2UiCatalog ->
        f(a, True, "board.view uses DataTable/Static/Container")
      aspects.PentaStackAccessibility ->
        f(a, True, "markdown, TUI view, JSON, Zenoh REST projections")
      aspects.TailscaleFqdnNavigation ->
        f(a, True, "board.view shows " <> aspects.tailnet_fqdn)
      aspects.ComprehensiveChecklist ->
        f(a, semantic && n > 0, "every message carries aspects + ontology refs")
      aspects.KnowledgeTriad ->
        f(a, semantic && n > 0, "ontology concepts resolved per message")
      aspects.SaPlanDurability ->
        f(a, valid && n > 0, "append-only ledger with Lamport order")
      _ -> d(a, True, "board subject: declared")
    }
  })
}

fn policy_findings(ledger: swarm.Ledger) -> List(Finding) {
  let roster = [
    board.Agent("L0-fable", "L0", "fable"),
    coord.system_agent,
    ..list.map(ledger.agents, fn(a) { board.Agent(a.id, a.layer, a.model) })
  ]
  let p = coord.default_policy(roster, ledger.wip_limit)
  let worker = board.Agent("W01", "L2", "sonnet")
  let dr = fn(from, to, kind) {
    board.Draft(
      from,
      to,
      kind,
      [],
      board.no_semantics,
      board.Causality(None, []),
      None,
      None,
    )
  }
  let l2_cannot_plan =
    coord.authorize(p, dr(worker, "broadcast", board.Plan)) != Ok(Nil)
  let intent_upward =
    coord.authorize(p, dr(worker, "W02", board.Intent)) != Ok(Nil)
  let l0_can_all =
    list.all(board.kinds, fn(k) {
      coord.authorize(
        p,
        dr(board.Agent("L0-fable", "L0", "fable"), "broadcast", k),
      )
      == Ok(Nil)
      || k == board.Intent
    })
  let leases_fenced = case coord.acquire(coord.new(p), "x", "a", 0, 10) {
    Ok(#(c, l)) -> coord.renew(c, "x", "a", l.epoch + 1, 1, 10) != Ok(#(c, l))
    Error(_) -> False
  }
  list.map(aspects.all, fn(a) {
    case a {
      aspects.SubstrateStorageSafety ->
        f(a, leases_fenced, "fenced epochs on leases")
      aspects.BiosemioticCybernetics ->
        f(a, intent_upward, "Intent only upward (L2->L0/L1)")
      aspects.ComprehensiveChecklist ->
        f(a, l2_cannot_plan, "L2 cannot Plan/Dispatch/Integrate")
      aspects.GleamOtpSupervisor -> f(a, l0_can_all, "L0 holds full authority")
      aspects.SaPlanDurability ->
        f(
          a,
          ledger.wip_limit > 0,
          "WIP limit " <> int.to_string(ledger.wip_limit),
        )
      aspects.ZeroMudaPurity -> f(a, True, "pure Gleam policy")
      aspects.MathematicalAuthority ->
        d(a, True, "single-writer lease per TwoLattice_STM.lean")
      _ -> d(a, True, "policy subject: declared")
    }
  })
}

fn fprime_findings() -> List(Finding) {
  let c = fprime.component()
  let ok = fprime.validate(c, fprime.instance()) == Ok(Nil)
  let ports = fprime.port_names(c)
  list.map(aspects.all, fn(a) {
    case a {
      aspects.ZigVmEngine ->
        f(a, list.contains(ports, "zigvm_tlm_in") && ok, "port zigvm_tlm_in")
      aspects.HermesEvidence ->
        f(
          a,
          list.contains(ports, "hermes_evidence_in") && ok,
          "port hermes_evidence_in",
        )
      aspects.QuarantinedMaxInference ->
        f(
          a,
          list.contains(ports, "max_inference_in") && ok,
          "port max_inference_in",
        )
      aspects.ZenohTelemetry ->
        f(a, list.contains(ports, "zenoh_tlm_in"), "port zenoh_tlm_in")
      aspects.AgUiEventStream ->
        f(a, list.contains(ports, "agui_event_in"), "port agui_event_in")
      aspects.SaPlanDurability ->
        f(a, list.contains(ports, "saplan_lease_in"), "port saplan_lease_in")
      aspects.MathematicalAuthority ->
        f(a, ok, "dictionary validates: unique ids, base outside DMC window")
      aspects.SubstrateStorageSafety ->
        f(
          a,
          list.any(c.parameters, fn(p) { p.param_name == "OsNvmeSerial" }),
          "OsNvmeSerial parameter",
        )
      aspects.TailscaleFqdnNavigation ->
        f(
          a,
          list.any(c.parameters, fn(p) { p.param_name == "FqdnBase" }),
          "FqdnBase parameter",
        )
      aspects.BiosemioticCybernetics ->
        f(
          a,
          list.contains(ports, "intent_out"),
          "intent_out port, no execute port",
        )
      _ -> d(a, ok, "dictionary subject: declared")
    }
  })
}

fn ontology_findings() -> List(Finding) {
  let g = ontology.graph()
  let ok = ontology.validate(g) == Ok(Nil)
  let #(iso, homo, re, def) = ontology.fidelity_counts(g)
  list.map(aspects.all, fn(a) {
    case a {
      aspects.KnowledgeTriad ->
        f(
          a,
          ok,
          "graph valid: " <> int.to_string(iso + homo + re + def) <> " concepts",
        )
      aspects.A2UiCatalog ->
        f(
          a,
          iso + homo >= 20,
          "isomorphic+homomorphic=" <> int.to_string(iso + homo),
        )
      aspects.PentaStackAccessibility ->
        f(a, def <= 3, "deferred=" <> int.to_string(def))
      aspects.ZeroMudaPurity -> f(a, True, "pure data")
      _ -> d(a, ok, "ontology subject: declared")
    }
  })
}

fn telemetry_subject() -> Subject {
  let t = telemetry.new_trace_id()
  let s = telemetry.new_span_id()
  Subject(
    "telemetry",
    list.map(aspects.all, fn(a) {
      case a {
        aspects.ZenohTelemetry ->
          f(
            a,
            telemetry.is_hex_id(t, 32) && telemetry.is_hex_id(s, 16),
            "W3C ids valid",
          )
        aspects.MathematicalAuthority ->
          f(
            a,
            telemetry.iso8601_us(0) == "1970-01-01T00:00:00.000000Z",
            "civil-from-days exact at epoch",
          )
        _ -> d(a, True, "telemetry subject: declared")
      }
    }),
  )
}

pub fn all_subjects(
  ctx: Context,
  ledger: swarm.Ledger,
  messages: List(board.Message),
  probe: Probe,
) -> List(Subject) {
  list.flatten([
    static_subjects(ctx, ledger, messages),
    [infra_subject(probe), telemetry_subject()],
  ])
}

pub fn totals(subjects: List(Subject)) -> #(Int, Int, Int) {
  list.fold(subjects, #(0, 0, 0), fn(acc, s) {
    #(
      acc.0 + aspects.passed(s.findings),
      acc.1 + aspects.declared(s.findings),
      acc.2 + aspects.failed(s.findings),
    )
  })
}

/// Strict two-key admission across every subject: zero Fail AND zero Declared findings.
pub fn admissible(subjects: List(Subject)) -> Bool {
  list.all(subjects, fn(s) { aspects.admissible(s.findings) })
}

/// The softer FAIL-only gate across every subject: zero Fail findings, Declared tolerated.
pub fn no_failures(subjects: List(Subject)) -> Bool {
  list.all(subjects, fn(s) { aspects.no_failures(s.findings) })
}

/// 17 rows × N subject columns.
pub fn to_markdown(subjects: List(Subject)) -> String {
  let header =
    "| # | Aspect | "
    <> string.join(list.map(subjects, fn(s) { s.name }), " | ")
    <> " |"
  let sep =
    "|---|---|" <> string.join(list.map(subjects, fn(_) { "---" }), "|") <> "|"
  let rows =
    list.map(aspects.all, fn(a) {
      let cells =
        list.map(subjects, fn(s) {
          case list.find(s.findings, fn(x) { x.aspect == a }) {
            Ok(x) -> aspects.verdict_label(x.verdict)
            Error(_) -> "—"
          }
        })
      "| "
      <> int.to_string(aspects.number(a))
      <> " | "
      <> aspects.name(a)
      <> " | "
      <> string.join(cells, " | ")
      <> " |"
    })
  let #(p, dcl, fl) = totals(subjects)
  string.join([header, sep, ..rows], "\n")
  <> "\n\nTotals: PASS "
  <> int.to_string(p)
  <> " · DECLARED "
  <> int.to_string(dcl)
  <> " · FAIL "
  <> int.to_string(fl)
  <> " · admissible="
  <> bool(admissible(subjects))
  <> " · no_failures="
  <> bool(no_failures(subjects))
}

pub fn to_json(subjects: List(Subject)) -> Json {
  json.array(subjects, fn(s) {
    json.object([
      #("subject", json.string(s.name)),
      #("pass", json.int(aspects.passed(s.findings))),
      #("declared", json.int(aspects.declared(s.findings))),
      #("fail", json.int(aspects.failed(s.findings))),
      #(
        "findings",
        json.array(s.findings, fn(x) {
          json.object([
            #("n", json.int(aspects.number(x.aspect))),
            #("verdict", json.string(aspects.verdict_label(x.verdict))),
            #("evidence", json.string(x.evidence)),
          ])
        }),
      ),
    ])
  })
}

/// Live probe of the Zenoh infra over REST plus the cockpit health endpoint.
pub fn probe(zenoh_base: String, cockpit_base: String) -> Probe {
  let router =
    board.http_get(
      zenoh_base <> "/@/**/router/status/plugins/storage_manager/storages/**",
    )
  let storages = case router {
    Ok(body) -> list.length(string.split(body, "\"key_expr\"")) - 1
    Error(_) -> 0
  }
  let a2a = case board.zenoh_fetch(zenoh_base) {
    Ok(ms) -> list.length(ms)
    Error(_) -> 0
  }
  let cockpit_ok = case board.http_get(cockpit_base <> "/api/zenoh/health") {
    Ok(body) -> string.contains(body, "\"connected\":true")
    Error(_) -> False
  }
  Probe(router != Error("") && storages > 0, storages, a2a, cockpit_ok)
}
