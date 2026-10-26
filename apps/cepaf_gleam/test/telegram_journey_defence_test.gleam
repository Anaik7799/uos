//// Dispatcher-layer journeys for the DEFENCE / HIGH AVAILABILITY use case
//// (SC-TELEGRAM-JOURNEY-001, docs/design/20261026-0215-telegram-journey-defence-ha.md).
////
//// Each journey is an ordered list of Telegram messages. Every step is walked
//// through the real dispatcher decision chain, in the same order the Telegram
//// service uses:
////   1. telegram_ingress_guard.classify_directive(text)
////   2. telegram_read_adapters.route(name, args)       (read adapters first)
////   3. telegram_action_adapters.route_preview(name, args)
////   4. otherwise the historical arm of the service.
////
//// Why some arms assert the classify verdict only: a DirectReadTool arm
//// (/status, /ha, /storage, /doctor ...) and a historical PreservedDirective
//// arm (/zenoh, /rete, /aspects, /fmea, /search, /approval, conversation)
//// are answered inside telegram_service from live service state (store,
//// observer, host probes, Zenoh REST). That state does not exist in a pure
//// dispatcher test, so asserting a reply here would fabricate it. For those
//// arms the test pins the classify verdict AND proves that neither adapter
//// router claims the literal, so the historical arm is the one that answers.
//// The reply class of those steps is exercised by the real-traffic runbook.
////
//// Nothing here touches the network, a service, var/, or any credential.

import cepaf_gleam/harness/telegram_action_adapters as action_adapters
import cepaf_gleam/harness/telegram_commands as commands
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_read_adapters as read_adapters
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

/// What a step must resolve to in the current dispatcher.
pub type Arm {
  /// classify_directive -> DirectReadTool(tool); service-state reply.
  Direct(tool: String)
  /// classify_directive -> PreservedDirective(name, args) owned by no adapter;
  /// the service's historical arm answers.
  Historical(name: String, args: List(String))
  /// read_adapters.route answers; JSON status and substrings are asserted.
  ReadAdapter(status: String, needles: List(String))
  /// action_adapters.route_preview answers; JSON status and substrings asserted.
  ActionPreview(status: String, needles: List(String))
  /// classify_directive -> DeniedMutation(tool, _).
  Denied(tool: String)
}

pub type Step {
  Step(text: String, arm: Arm)
}

// ---------------------------------------------------------------------------
// Journey 1: degraded mesh and homeostasis check
// ---------------------------------------------------------------------------

pub fn journey_1_steps() -> List(Step) {
  [
    Step("/status", Direct("query_system_health")),
    Step("/ha", Direct("query_ha")),
    Step(
      "/zenoh indrajaal/l2/health/homeostasis",
      Historical("/zenoh", ["indrajaal/l2/health/homeostasis"]),
    ),
    Step(
      "/mesh",
      ReadAdapter("ok", [
        "\"backend\":\"cepaf_gleam/config/mesh_source\"",
        "\"deployment_confirmed\":false",
      ]),
    ),
    Step(
      "/simulate zenoh:partitioned mesh:degraded peer:nominal",
      // Defect found in wave 5 and repaired in wave 6: the catalog used to
      // canonicalise /simulate to /whatif, so the peer-quorum simulation was
      // unreachable from a Telegram message. It now answers from the pure
      // peer simulator and says so.
      ReadAdapter("ok", [
        "\"backend\":\"cepaf_gleam/zenoh/peer_simulator\"",
        "\"scenario\":\"peer_mesh_quorum\"",
        "\"subject\":\"simulated peers, not the live mesh\"",
      ]),
    ),
    Step(
      "/immune",
      ReadAdapter("backend_unavailable", [
        "\"backend\":\"cepaf_gleam/immune/system\"",
      ]),
    ),
    Step(
      "/rete watchdog=false,mesh_running=true,high_drift=true",
      Historical("/rete", ["watchdog=false,mesh_running=true,high_drift=true"]),
    ),
    Step(
      "the mesh looks slow, what should I check first",
      Historical("conversational", [
        "the mesh looks slow, what should I check first",
      ]),
    ),
  ]
}

// ---------------------------------------------------------------------------
// Journey 2: immune / andon escalation with approval preview
// ---------------------------------------------------------------------------

pub fn journey_2_steps() -> List(Step) {
  [
    Step(
      "/escalate 120",
      ActionPreview("preview", [
        "\"confidence\":\"simulated\"",
        "\"staleness_level\":\"degraded\"",
        "\"runbook_id\":\"RB-009\"",
        "\"notification_sent\":false",
        "\"approval_required\":true",
        "\"authority\":\"NONE\"",
      ]),
    ),
    Step("/escalate 90000", ActionPreview("denied", ["age_out_of_range"])),
    Step(
      "/dark emergency",
      ActionPreview("preview", [
        "\"confidence\":\"declared\"",
        "\"global_state_mutated\":false",
        "\"reversible_by\":\"/dark dark\"",
        "\"approval_required\":true",
      ]),
    ),
    Step(
      "/andon modular_max timeout_failure",
      ActionPreview("preview", [
        "\"confidence\":\"simulated\"",
        "\"effect\":\"andon_trip_record_only\"",
        "\"process_signalled\":false",
        "\"predicted_after_phase\":\"stopped\"",
        "\"approval_required\":true",
        "\"authority\":\"NONE\"",
      ]),
    ),
    Step("/andon modular_max", ActionPreview("denied", ["usage: /andon"])),
    Step("/approval", Historical("/approval", [])),
    Step(
      "/approval propose tg-123",
      Historical("/approval_manage", ["propose", "tg-123"]),
    ),
    // Unsigned free-text approval must never authorize anything.
    Step("/approval approve tg-123", Denied("/approval")),
  ]
}

// ---------------------------------------------------------------------------
// Journey 3: chaos gameday rehearsal in simulation
// ---------------------------------------------------------------------------

pub fn journey_3_steps() -> List(Step) {
  [
    Step(
      "/whatif claim 4",
      ReadAdapter("ok", [
        "\"backend\":\"cepaf_gleam/planning/sa_plan_simulator\"",
        "\"subject\":\"synthetic task, not a live Sa-plan task\"",
        "\"granted\":1",
        "\"rejected\":3",
      ]),
    ),
    Step(
      "/whatif zombie 100 200",
      ReadAdapter("ok", [
        "\"subject\":\"synthetic task, not a live lease\"",
        "\"reaped\":true",
      ]),
    ),
    Step(
      "/whatif retry 3",
      ReadAdapter("ok", [
        "\"subject\":\"synthetic job, not a live Oban job\"",
        "\"state\":\"dead\"",
      ]),
    ),
    Step("/whatif zenoh-router-kill", ReadAdapter("denied", ["Usage: /whatif"])),
    Step(
      "/gameday packet-loss-moderate",
      ActionPreview("preview", [
        "\"confidence\":\"simulated\"",
        "\"andon_tripped\":false",
        "\"containment_preserved\":true",
        "\"real_effects\":\"none\"",
      ]),
    ),
    Step(
      "/gameday packet-loss-catastrophic",
      ActionPreview("preview", [
        "\"confidence\":\"simulated\"",
        "\"response\":\"andon_emergency_halt\"",
        "\"andon_tripped\":true",
        "\"real_effects\":\"none\"",
      ]),
    ),
    Step(
      "/gameday worker-oom",
      ActionPreview("preview", [
        "\"response\":\"hot_reload_triggered\"",
        "\"real_effects\":\"none\"",
      ]),
    ),
    Step(
      "/chaos zenoh-network-partition",
      ActionPreview("preview", [
        "\"confidence\":\"declared\"",
        "\"guardian_required_for_live\":true",
        "\"real_effects\":\"none\"",
      ]),
    ),
    Step("/chaos no-such-scenario", ActionPreview("denied", ["usage: /chaos"])),
    Step(
      "/rewind 5",
      ActionPreview("preview", [
        "\"confidence\":\"simulated\"",
        "\"store_mutations\":0",
        "\"history\":\"declared reference history; no live store read\"",
      ]),
    ),
  ]
}

// ---------------------------------------------------------------------------
// Journey 4: storage interlock, capacity and standby readiness
// ---------------------------------------------------------------------------

pub fn journey_4_steps() -> List(Step) {
  [
    Step("/storage", Direct("query_storage")),
    Step("/nvme", Direct("query_storage")),
    // A read command with arguments is refused, never reinterpreted.
    Step("/storage now", Denied("query_storage")),
    Step("/ecology", Direct("query_ecology")),
    Step("/finops", Direct("query_finops")),
    Step("/budget", Direct("query_finops")),
    Step(
      "/eco-schedule",
      ActionPreview("preview", [
        "\"confidence\":\"simulated\"",
        "\"backend\":\"ecology/daily_budget\"",
        "\"authority\":\"NONE\"",
      ]),
    ),
    Step(
      "/sidecar forward",
      ActionPreview("preview", [
        "\"runtime_mode\":\"simulation_only\"",
        "\"runtime_observation\":\"unknown\"",
        "\"admission\":\"unverified\"",
        "\"backend\":\"unavailable:mirage_unikernel_daemon\"",
        "\"authority\":\"NONE\"",
      ]),
    ),
    Step("/sidecar everything", ActionPreview("denied", ["usage: /sidecar"])),
    Step(
      "/export-audit",
      ActionPreview("preview", [
        "\"backend\":\"unavailable:rusty_vault_nif\"",
        "\"authority\":\"NONE\"",
      ]),
    ),
    Step(
      "/inference",
      ReadAdapter("ok", [
        "\"backend\":\"cepaf_gleam/ui/lustre/inference_tier\"",
        "\"live_status\":\"not_observed\"",
      ]),
    ),
    Step(
      "/radar",
      ReadAdapter("backend_unavailable", [
        "\"backend\":\"cepaf_gleam/ui/lustre/biosemiotics_radar\"",
      ]),
    ),
    Step(
      "/acoustic-hud",
      ReadAdapter("ok", [
        "\"kind\":\"shruti_lattice_self_audit\"",
        "\"live_sensor\":\"not_observed\"",
      ]),
    ),
  ]
}

// ---------------------------------------------------------------------------
// Journey 5: verification scorecard and FMEA
// ---------------------------------------------------------------------------

pub fn journey_5_steps() -> List(Step) {
  [
    Step("/doctor", Direct("query_doctor")),
    Step("/ev", Direct("query_doctor")),
    Step("/checklist", Direct("query_checklist")),
    Step("/aspects", Historical("/aspects", [""])),
    Step("/aspects A04", Historical("/aspects", ["A04"])),
    Step("/fmea", Direct("query_fmea")),
    Step(
      "/fmea s2-policy-status-correction",
      Historical("/fmea", ["s2-policy-status-correction"]),
    ),
    Step("/blast-radius", Denied("/blast-radius")),
    Step("/blast-radius uos_sup", Historical("/blast-radius", ["uos_sup"])),
    // Wave 6b: /verify is preserved for the service's VerifyDispatch, which
    // executes only a signed verify packet and otherwise answers that
    // verification is not configured. No adapter owns the literal.
    Step("/verify", Historical("/verify", [])),
    Step("/verification", Historical("/verify", [])),
    Step("/sutra", Direct("query_matrix_versions")),
    Step("/search andon", Historical("/search", ["andon"])),
    Step("/wiki ha", Historical("/knowledge", ["wiki", "ha"])),
    Step("/km mesh", Historical("/knowledge", ["all", "mesh"])),
    Step(
      "/adr",
      ReadAdapter("ok", ["\"backend\":\"cepaf_gleam/harness/files (docs/zk)\""]),
    ),
  ]
}

// ---------------------------------------------------------------------------
// Journey 6: recovery, resuscitation preview and shift handover
// ---------------------------------------------------------------------------

pub fn journey_6_steps() -> List(Step) {
  [
    Step("/plan", Direct("query_saplan")),
    Step("/tasks", Direct("query_saplan")),
    Step("/board", Direct("query_board")),
    Step("/peers", Direct("query_peers")),
    Step(
      "/resuscitate modular_max",
      ActionPreview("preview", [
        "\"confidence\":\"simulated\"",
        "\"predicted_after_phase\":\"recovering\"",
        "\"completion_requires\":\"engaged_backend_probe_receipt\"",
        "\"process_restarted\":false",
        "\"approval_required\":true",
      ]),
    ),
    Step(
      "/resuscitate nothing",
      ActionPreview("denied", ["usage: /resuscitate"]),
    ),
    Step(
      "/repro s2-policy-status-correction",
      ActionPreview("preview", [
        "\"executes_commands\":false",
        "\"task_state\":\"not_observed\"",
      ]),
    ),
    Step(
      "/commitments",
      ActionPreview("preview", [
        "\"tasks_observed\":0",
        "\"execute\":\"backend_unavailable:cepaf_gleam/harness/telegram_task_command\"",
      ]),
    ),
    Step(
      "/handover mesh-degraded-shift",
      ActionPreview("preview", [
        "\"sections\":13",
        "\"docs_directory_untouched\":true",
        "\"authority\":\"NONE\"",
      ]),
    ),
    Step(
      "/postmortem",
      ReadAdapter("ok", [
        "\"backend\":\"cepaf_gleam/harness/files (docs/journal)\"",
        "\"keyword\":\"postmortem\"",
      ]),
    ),
    Step("/exec-brief", Direct("query_exec_brief")),
    Step("/messages", Historical("/messages", [])),
    Step(
      "/socratic why did the mesh partition",
      Historical("/socratic", ["why did the mesh partition"]),
    ),
    Step("/help", Historical("/help", [])),
  ]
}

fn all_journeys() -> List(List(Step)) {
  [
    journey_1_steps(),
    journey_2_steps(),
    journey_3_steps(),
    journey_4_steps(),
    journey_5_steps(),
    journey_6_steps(),
  ]
}

// ---------------------------------------------------------------------------
// Walker
// ---------------------------------------------------------------------------

fn status_of(reply: String) -> Result(String, Nil) {
  json.parse(reply, {
    use s <- decode.field("status", decode.string)
    decode.success(s)
  })
  |> result_to_nil
}

fn result_to_nil(r: Result(a, b)) -> Result(a, Nil) {
  case r {
    Ok(v) -> Ok(v)
    Error(_) -> Error(Nil)
  }
}

fn check_reply(
  label: String,
  reply: String,
  status: String,
  needles: List(String),
) -> List(String) {
  let status_failures = case status_of(reply) {
    Ok(actual) if actual == status -> []
    Ok(actual) -> [label <> ": status " <> actual <> " expected " <> status]
    Error(_) -> [label <> ": reply is not a JSON object with a status"]
  }
  let needle_failures =
    list.filter_map(needles, fn(needle) {
      case string.contains(reply, needle) {
        True -> Error(Nil)
        False -> Ok(label <> ": missing " <> needle)
      }
    })
  let bound_failures = case string.byte_size(reply) <= 3500 {
    True -> []
    False -> [label <> ": reply exceeds the 3500 byte bound"]
  }
  list.flatten([status_failures, needle_failures, bound_failures])
}

/// Returns the list of failure descriptions for one step (empty = pass).
pub fn walk_step(step: Step) -> List(String) {
  let verdict = guard.classify_directive(step.text)
  let label = step.text
  case step.arm, verdict {
    Direct(tool), guard.DirectReadTool(actual) if actual == tool -> []
    Direct(tool), other -> [
      label
      <> ": expected DirectReadTool "
      <> tool
      <> " got "
      <> describe(other),
    ]
    Denied(tool), guard.DeniedMutation(actual, _) if actual == tool -> []
    Denied(tool), other -> [
      label
      <> ": expected DeniedMutation "
      <> tool
      <> " got "
      <> describe(other),
    ]
    Historical(name, args), guard.PreservedDirective(actual_name, actual_args)
      if actual_name == name && actual_args == args
    ->
      case
        read_adapters.route(name, args),
        action_adapters.route_preview(name, args)
      {
        None, None -> []
        _, _ -> [label <> ": an adapter claims a historical-arm literal"]
      }
    Historical(name, _), other -> [
      label
      <> ": expected PreservedDirective "
      <> name
      <> " got "
      <> describe(other),
    ]
    ReadAdapter(status, needles), guard.PreservedDirective(name, args) ->
      case read_adapters.route(name, args) {
        Some(reply) -> check_reply(label, reply, status, needles)
        None -> [label <> ": read_adapters.route returned None"]
      }
    ReadAdapter(_, _), other -> [
      label
      <> ": expected PreservedDirective (read adapter) got "
      <> describe(other),
    ]
    ActionPreview(status, needles), guard.PreservedDirective(name, args) ->
      case
        read_adapters.route(name, args),
        action_adapters.route_preview(name, args)
      {
        None, Some(reply) -> check_reply(label, reply, status, needles)
        Some(_), _ -> [label <> ": a read adapter shadows the action preview"]
        None, None -> [label <> ": action_adapters.route_preview returned None"]
      }
    ActionPreview(_, _), other -> [
      label
      <> ": expected PreservedDirective (action preview) got "
      <> describe(other),
    ]
  }
}

fn describe(verdict: guard.ParsedDirective) -> String {
  case verdict {
    guard.DirectReadTool(t) -> "DirectReadTool(" <> t <> ")"
    guard.PreservedDirective(n, a) ->
      "PreservedDirective(" <> n <> ", [" <> string.join(a, "|") <> "])"
    guard.DeniedMutation(t, r) -> "DeniedMutation(" <> t <> ", " <> r <> ")"
    guard.UnknownDirective(n) -> "UnknownDirective(" <> n <> ")"
  }
}

fn walk(steps: List(Step)) -> List(String) {
  list.flat_map(steps, walk_step)
}

// ---------------------------------------------------------------------------
// One test per journey
// ---------------------------------------------------------------------------

pub fn journey_1_degraded_mesh_and_homeostasis_test() {
  walk(journey_1_steps()) |> should.equal([])
}

pub fn journey_2_immune_andon_escalation_with_approval_preview_test() {
  walk(journey_2_steps()) |> should.equal([])
}

pub fn journey_3_chaos_gameday_rehearsal_in_simulation_test() {
  walk(journey_3_steps()) |> should.equal([])
}

pub fn journey_4_storage_interlock_and_standby_readiness_test() {
  walk(journey_4_steps()) |> should.equal([])
}

pub fn journey_5_verification_scorecard_and_fmea_test() {
  walk(journey_5_steps()) |> should.equal([])
}

pub fn journey_6_recovery_resuscitation_and_handover_test() {
  walk(journey_6_steps()) |> should.equal([])
}

// ---------------------------------------------------------------------------
// Coverage
// ---------------------------------------------------------------------------

fn first_word(text: String) -> String {
  case string.split(string.trim(text), " ") {
    [first, ..] -> first
    [] -> ""
  }
}

/// Every distinct slash literal a step of this use case sends, in first-use
/// order. Free-text conversational steps contribute nothing.
pub fn covered_literals() -> List(String) {
  all_journeys()
  |> list.flatten
  |> list.map(fn(step) { first_word(step.text) })
  |> list.filter(fn(word) { string.starts_with(word, "/") })
  |> list.unique
}

pub fn every_step_literal_exists_in_the_catalog_test() {
  let catalog_literals =
    list.map(commands.catalog(), fn(definition) { definition.literal })
  let missing =
    list.filter(covered_literals(), fn(lit) {
      !list.contains(catalog_literals, lit)
    })
  missing |> should.equal([])
}

pub fn adapter_steps_name_literals_their_adapter_actually_owns_test() {
  let bad =
    all_journeys()
    |> list.flatten
    |> list.filter_map(fn(step) {
      let lit = first_word(step.text)
      case step.arm {
        ReadAdapter(_, _) ->
          case list.contains(read_adapters.literals(), lit) {
            True -> Error(Nil)
            False -> Ok(lit)
          }
        ActionPreview(_, _) ->
          case list.contains(action_adapters.literals(), lit) {
            True -> Error(Nil)
            False -> Ok(lit)
          }
        _ -> Error(Nil)
      }
    })
  bad |> should.equal([])
}

pub fn no_step_expects_an_executed_or_duplicate_class_test() {
  // A plain message can never reach `executed` or `duplicate`; the journey
  // specs must not expect them.
  let offenders =
    all_journeys()
    |> list.flatten
    |> list.filter(fn(step) {
      case step.arm {
        ReadAdapter(status, _) | ActionPreview(status, _) ->
          status == "executed" || status == "duplicate"
        _ -> False
      }
    })
  offenders |> should.equal([])
}

pub fn journey_count_and_step_totals_are_pinned_test() {
  list.length(all_journeys()) |> should.equal(6)
  list.length(list.flatten(all_journeys())) |> should.equal(69)
}
