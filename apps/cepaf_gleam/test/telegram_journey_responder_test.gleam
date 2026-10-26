//// Dispatcher-layer journeys for the critical responder (SC-TELEGRAM-JOURNEY-001,
//// docs/design/20261026-0215-telegram-journey-critical-responder.md).
////
//// Each step is walked through the same three functions the Telegram service
//// calls, in the same order: `guard.classify_directive`, then
//// `read_adapters.route`, then `action_adapters.route_preview`.
//// - `Routed` steps assert the JSON "status" class and the required fields of
////   the adapter reply.
//// - `Direct` (DirectReadTool) and `Service` (a PreservedDirective answered by
////   the service's own arm or the historical reference reply) steps assert the
////   classify verdict only: their reply is built from live service state
////   (observer, coordinator, conversation model) that this layer cannot reach,
////   and this test never fabricates it. For `Service` steps the test also
////   proves no adapter owns the literal, so the arm really is the service's.
//// - `Refused` and `Unknown` steps assert the typed refusal at classify.
//// No network, no process, no Telegram traffic, no authority.

import cepaf_gleam/harness/telegram_action_adapters as action_adapters
import cepaf_gleam/harness/telegram_commands as commands
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_read_adapters as read_adapters
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string

pub type Expect {
  /// classify -> DirectReadTool(tool); reply built by the service from live state.
  Direct(tool: String)
  /// classify -> PreservedDirective(name, args); no adapter routes it, so the
  /// service arm or conversation path answers.
  Service(name: String, args: List(String))
  /// classify -> PreservedDirective(name, args) and `reference_reply` is Ok.
  Reference(name: String, needle: String)
  /// classify -> PreservedDirective(name, args); an adapter reply has this
  /// "status" class (or `alt` when the backend depends on the host, "" = none),
  /// these fields, and this confidence ("" = not asserted).
  Routed(
    name: String,
    args: List(String),
    class: String,
    fields: List(String),
    confidence: String,
    alt: String,
  )
  /// classify -> DeniedMutation(tool, _).
  Refused(tool: String)
  /// classify -> UnknownDirective(name).
  Unknown(name: String)
}

pub type Step {
  Step(n: Int, text: String, expect: Expect)
}

const ok_fields = ["status", "command", "backend", "observation"]

const unavailable_fields = ["status", "command", "backend", "reason"]

const denied_fields = ["status", "command", "reason"]

const preview_fields = ["status", "effect_id", "confidence"]

fn ok(name, args) {
  Routed(name, args, "ok", ok_fields, "", "")
}

fn ok_env(name, args) {
  Routed(name, args, "ok", ok_fields, "", "backend_unavailable")
}

fn unavailable(name, args) {
  Routed(name, args, "backend_unavailable", unavailable_fields, "", "")
}

fn usage(name, args) {
  Routed(name, args, "denied", denied_fields, "", "")
}

fn preview(name, args, confidence) {
  Routed(name, args, "preview", preview_fields, confidence, "")
}

fn number(texts: List(#(String, Expect))) -> List(Step) {
  list.index_map(texts, fn(pair, i) { Step(i + 1, pair.0, pair.1) })
}

/// R1: first 60 seconds on a phone.
pub fn journey_first_minute() -> List(Step) {
  number([
    #("/start", Reference("/help", "UOS Telegram commands")),
    #("/help", Reference("/help", "/status")),
    #("/cockpit", Reference("/cockpit", commands.cockpit_url)),
    #("/status", Direct("query_system_health")),
    #("/health", Direct("query_system_health")),
    #("/ha", Direct("query_ha")),
    #("/doctor", Direct("query_doctor")),
    #("/ev", Direct("query_doctor")),
    #("/checklist", Direct("query_checklist")),
    #("/aspects", Service("/aspects", [""])),
    #("/aspects A99", Refused("/aspects")),
    #("/exec-brief", Direct("query_exec_brief")),
    #("/sutra", Direct("query_matrix_versions")),
    #("/status now", Refused("query_system_health")),
    #("/fakecmd", Unknown("/fakecmd")),
  ])
}

/// R2: situational picture and field sensors, including honest absence.
pub fn journey_situational_picture() -> List(Step) {
  number([
    #("/plan", Direct("query_saplan")),
    #("/tasks", Direct("query_saplan")),
    #("/task t1", Service("/task", ["t1"])),
    #("/task", Refused("/task")),
    #("/board", Direct("query_board")),
    #("/peers", Direct("query_peers")),
    #("/zenoh", Service("/zenoh", [""])),
    #("/zenoh https://example.invalid", Refused("/zenoh")),
    #("/mesh", ok_env("/mesh", [])),
    #("/storage", Direct("query_storage")),
    #("/nvme", Direct("query_storage")),
    #("/ecology", Direct("query_ecology")),
    #("/finops", Direct("query_finops")),
    #("/budget", Direct("query_finops")),
    #("/zigvm", Direct("query_zigvm_version")),
    #("/inference", ok("/inference", [])),
    #("/inference now", usage("/inference", ["now"])),
    #("/immune", unavailable("/immune", [])),
    #("/rack-cv", unavailable("/rack-cv", [])),
    #("/acoustic", unavailable("/acoustic", [])),
    #("/acoustic-hud", ok("/acoustic-hud", [])),
    #("/radar", unavailable("/radar", [])),
    #("/pacing", unavailable("/pacing", [])),
    #("/pacing nap", unavailable("/pacing", ["nap"])),
  ])
}

/// R3: knowledge in the field and pure what-if simulation.
pub fn journey_knowledge_and_whatif() -> List(Step) {
  number([
    #("/wiki homeostasis", Service("/knowledge", ["wiki", "homeostasis"])),
    #("/zk adr", Service("/knowledge", ["zk", "adr"])),
    #("/km provenance", Service("/knowledge", ["all", "provenance"])),
    #("/search lease", Service("/search", ["lease"])),
    #("/adr", ok_env("/adr", [])),
    #("/adr 10", ok_env("/adr", ["10"])),
    #("/adr ten", usage("/adr", ["ten"])),
    #(
      "/blast-radius cepaf_gleam/harness/telegram_service",
      Service("/blast-radius", ["cepaf_gleam@harness@telegram_service"]),
    ),
    #("/blast-radius", Refused("/blast-radius")),
    #("/whatif claim 3", ok("/whatif", ["claim 3"])),
    #("/whatif retry 3", ok("/whatif", ["retry 3"])),
    #("/whatif zombie 100 200", ok("/whatif", ["zombie 100 200"])),
    #("/whatif claim 99", usage("/whatif", ["claim 99"])),
    // /simulate canonicalizes to /whatif, so its own peer-mesh grammar is
    // unreachable through the dispatcher and the reply is the /whatif usage.
    #(
      "/simulate a:nominal b:degraded",
      usage("/whatif", ["a:nominal b:degraded"]),
    ),
    #("/canvas a:1,2,3 b:4,5,6", ok("/canvas", ["a:1,2,3 b:4,5,6"])),
    #("/canvas", usage("/canvas", [])),
    #("/whiteboard", unavailable("/whiteboard", [])),
    #("/babel", unavailable("/babel", [])),
  ])
}

/// R4: bounded action behind approval. Every action is a read-only preview.
pub fn journey_bounded_action() -> List(Step) {
  number([
    #("/approval", Service("/approval", [])),
    #("/approval approve tg-123", Refused("/approval")),
    #(
      "/approval propose tg-123",
      Service("/approval_manage", ["propose", "tg-123"]),
    ),
    #("/approval propose bad", Refused("/approval")),
    #("/tool help", Service("/tool_help", [])),
    #("/action help", Service("/tool_help", [])),
    #("/tool query_peers", Direct("query_peers")),
    #("/tool shell ls", Refused("/tool")),
    #("/andon", usage("/andon", [])),
    #(
      "/andon modular_max watchdog_stall",
      preview("/andon", ["modular_max watchdog_stall"], "simulated"),
    ),
    #("/escalate 120", preview("/escalate", ["120"], "simulated")),
    #("/escalate 99999", usage("/escalate", ["99999"])),
    #("/dark dim", preview("/dark", ["dim"], "declared")),
    #(
      "/resuscitate modular_max",
      preview("/resuscitate", ["modular_max"], "simulated"),
    ),
    #(
      "/chaos sa-plan-daemon-kill",
      preview("/chaos", ["sa-plan-daemon-kill"], "declared"),
    ),
    #("/gameday worker-oom", preview("/gameday", ["worker-oom"], "simulated")),
    #(
      "/lockbox seal credential_suspected",
      preview("/lockbox", ["seal credential_suspected"], "declared"),
    ),
    #("/rotate-keys 90 40", preview("/rotate-keys", ["90 40"], "declared")),
    #("/sidecar ingress", preview("/sidecar", ["ingress"], "simulated")),
    #("/rewind 5", preview("/rewind", ["5"], "simulated")),
    #("/repro task-1", preview("/repro", ["task-1"], "declared")),
    #("/bisect abcd ef01", preview("/bisect", ["abcd ef01"], "simulated")),
    // The merge preview's own status is backend_unavailable: no integration lease exists.
    #(
      "/merge zkuzwnup",
      Routed(
        "/merge",
        ["zkuzwnup"],
        "backend_unavailable",
        ["status", "effect_id", "backend", "requires"],
        "declared",
        "",
      ),
    ),
    #(
      "/migrate MIG-02-SANDBOX discovered",
      preview("/migrate", ["MIG-02-SANDBOX discovered"], "simulated"),
    ),
    #("/eco-schedule jobs=5", preview("/eco-schedule", ["jobs=5"], "simulated")),
    #("/pair-voice alpha", preview("/pair-voice", ["alpha"], "declared")),
    #("/pair-voice Alpha", usage("/pair-voice", ["Alpha"])),
    // Denied at classify: no adapter owns these literals.
    #("/verify", Refused("/verify")),
    #("/verification", Refused("/verify")),
    #("/voice-roll-call", Refused("/voice-roll-call")),
  ])
}

/// R5: handover, evidence export, memory and retrospectives.
pub fn journey_handover_and_memory() -> List(Step) {
  number([
    #("/handover", usage("/handover", [])),
    #("/handover shift-a", preview("/handover", ["shift-a"], "observed")),
    #("/commitments", preview("/commitments", [], "declared")),
    #(
      "/export-audit limit=10",
      preview("/export-audit", ["limit=10"], "declared"),
    ),
    #("/memory", Service("/memory", [])),
    #("/history", Service("/messages", [])),
    #("/messages", Service("/messages", [])),
    #("/retro", ok_env("/retro", [])),
    #("/retro 3", ok_env("/retro", ["3"])),
    #("/postmortem", ok_env("/postmortem", [])),
    #("/postmortem 0", usage("/postmortem", ["0"])),
  ])
}

/// R6: conversation fallback.
pub fn journey_conversation_fallback() -> List(Step) {
  number([
    #(
      "the pump room is flooding, what should I check first",
      Service("conversational", [
        "the pump room is flooding, what should I check first",
      ]),
    ),
    #(
      "/agy summarize the open risks",
      Service("/agy", ["summarize the open risks"]),
    ),
    #(
      "/socratic why did the lease expire",
      Service("/socratic", ["why did the lease expire"]),
    ),
    #("/socratic", Refused("/socratic")),
    #("/AGY hello", Unknown("/AGY")),
  ])
}

pub fn journeys() -> List(#(String, List(Step))) {
  [
    #("R1 first minute", journey_first_minute()),
    #("R2 situational picture", journey_situational_picture()),
    #("R3 knowledge and what-if", journey_knowledge_and_whatif()),
    #("R4 bounded action", journey_bounded_action()),
    #("R5 handover and memory", journey_handover_and_memory()),
    #("R6 conversation fallback", journey_conversation_fallback()),
  ]
}

fn first_token(text: String) -> String {
  case string.split(text, " ") {
    [first, ..] -> first
    [] -> ""
  }
}

/// Distinct catalog literals exercised by these journeys, in catalog order.
pub fn covered_literals() -> List(String) {
  let used =
    journeys()
    |> list.flat_map(fn(j) { j.1 })
    |> list.filter(fn(step) {
      case step.expect {
        Unknown(_) -> False
        Service("conversational", _) -> False
        _ -> True
      }
    })
    |> list.map(fn(step) { first_token(step.text) })
  commands.catalog()
  |> list.map(fn(d) { d.literal })
  |> list.filter(fn(literal) { list.contains(used, literal) })
}

// ---------------------------------------------------------------- walking

fn reply_status(reply: String) -> String {
  let decoder = {
    use status <- decode.field("status", decode.string)
    decode.success(status)
  }
  case json.parse(reply, decoder) {
    Ok(status) -> status
    Error(_) -> "unparseable"
  }
}

fn reply_confidence(reply: String) -> String {
  let decoder = {
    use value <- decode.field("confidence", decode.string)
    decode.success(value)
  }
  case json.parse(reply, decoder) {
    Ok(value) -> value
    Error(_) -> "absent"
  }
}

fn reply_keys(reply: String) -> List(String) {
  case json.parse(reply, decode.dict(decode.string, decode.dynamic)) {
    Ok(entries) -> dict.keys(entries)
    Error(_) -> []
  }
}

fn describe(journey: String, step: Step) -> String {
  journey <> " step " <> string.inspect(step.n) <> " `" <> step.text <> "`: "
}

fn route(name: String, args: List(String)) -> option.Option(String) {
  case read_adapters.route(name, args) {
    Some(reply) -> Some(reply)
    None -> action_adapters.route_preview(name, args)
  }
}

fn walk(journey: String, step: Step) -> Nil {
  let where = describe(journey, step)
  let verdict = guard.classify_directive(step.text)
  case step.expect, verdict {
    Direct(tool), guard.DirectReadTool(actual) ->
      case tool == actual {
        True -> Nil
        False ->
          panic as {
            where <> "expected DirectReadTool " <> tool <> " got " <> actual
          }
      }
    Service(name, args), guard.PreservedDirective(actual, actual_args) -> {
      case name == actual && args == actual_args {
        True -> Nil
        False ->
          panic as {
            where
            <> "expected Preserved "
            <> name
            <> " "
            <> string.inspect(args)
            <> " got "
            <> actual
            <> " "
            <> string.inspect(actual_args)
          }
      }
      case route(actual, actual_args) {
        None -> Nil
        Some(_) ->
          panic as {
            where <> "an adapter owns " <> actual <> "; the step must be Routed"
          }
      }
    }
    Reference(name, needle), guard.PreservedDirective(actual, actual_args) -> {
      case name == actual {
        True -> Nil
        False ->
          panic as {
            where <> "expected Preserved " <> name <> " got " <> actual
          }
      }
      case route(actual, actual_args) {
        None -> Nil
        Some(_) -> panic as { where <> "an adapter owns " <> actual }
      }
      let assert Ok(invocation) = commands.parse(step.text)
      case commands.reference_reply(invocation) {
        Ok(text) ->
          case string.contains(text, needle) {
            True -> Nil
            False -> panic as { where <> "reference reply lacks " <> needle }
          }
        Error(_) -> panic as { where <> "no reference reply" }
      }
    }
    Routed(name, args, class, fields, confidence, alt),
      guard.PreservedDirective(actual, actual_args)
    -> {
      case name == actual && args == actual_args {
        True -> Nil
        False ->
          panic as {
            where
            <> "expected Preserved "
            <> name
            <> " "
            <> string.inspect(args)
            <> " got "
            <> actual
            <> " "
            <> string.inspect(actual_args)
          }
      }
      case route(actual, actual_args) {
        None -> panic as { where <> "no adapter replied for " <> actual }
        Some(reply) -> {
          let status = reply_status(reply)
          case status == class || { alt != "" && status == alt } {
            True -> Nil
            False ->
              panic as {
                where
                <> "expected status "
                <> class
                <> " got "
                <> status
                <> " in "
                <> reply
              }
          }
          // Field presence is asserted for the primary class only; an alt
          // reply is the host-dependent truthful refusal.
          case status == class {
            False -> Nil
            True -> {
              let keys = reply_keys(reply)
              case list.all(fields, fn(f) { list.contains(keys, f) }) {
                True -> Nil
                False ->
                  panic as { where <> "missing required field in " <> reply }
              }
              case confidence == "" || reply_confidence(reply) == confidence {
                True -> Nil
                False ->
                  panic as {
                    where
                    <> "expected confidence "
                    <> confidence
                    <> " got "
                    <> reply_confidence(reply)
                  }
              }
            }
          }
        }
      }
    }
    Refused(tool), guard.DeniedMutation(actual, _) ->
      case tool == actual {
        True -> Nil
        False ->
          panic as {
            where <> "expected DeniedMutation " <> tool <> " got " <> actual
          }
      }
    Unknown(name), guard.UnknownDirective(actual) ->
      case name == actual {
        True -> Nil
        False ->
          panic as {
            where <> "expected UnknownDirective " <> name <> " got " <> actual
          }
      }
    _, _ ->
      panic as {
        where <> "unexpected classify verdict " <> string.inspect(verdict)
      }
  }
}

fn walk_journey(name: String, steps: List(Step)) -> Nil {
  list.each(steps, fn(step) { walk(name, step) })
}

pub fn journey_r1_first_minute_test() {
  walk_journey("R1 first minute", journey_first_minute())
}

pub fn journey_r2_situational_picture_test() {
  walk_journey("R2 situational picture", journey_situational_picture())
}

pub fn journey_r3_knowledge_and_whatif_test() {
  walk_journey("R3 knowledge and what-if", journey_knowledge_and_whatif())
}

pub fn journey_r4_bounded_action_test() {
  walk_journey("R4 bounded action", journey_bounded_action())
}

pub fn journey_r5_handover_and_memory_test() {
  walk_journey("R5 handover and memory", journey_handover_and_memory())
}

pub fn journey_r6_conversation_fallback_test() {
  walk_journey("R6 conversation fallback", journey_conversation_fallback())
}

pub fn every_step_literal_exists_in_catalog_test() {
  let catalog = list.map(commands.catalog(), fn(d) { d.literal })
  journeys()
  |> list.each(fn(journey) {
    list.each(journey.1, fn(step) {
      case step.expect {
        // Deliberate negative steps: an unknown or wrongly cased literal, and
        // plain text, are not catalog entries by design.
        Unknown(_) -> Nil
        Service("conversational", _) -> Nil
        _ ->
          case list.contains(catalog, first_token(step.text)) {
            True -> Nil
            False ->
              panic as {
                describe(journey.0, step)
                <> "literal is not in commands.catalog()"
              }
          }
      }
    })
  })
}

pub fn covered_literals_are_the_responder_set_test() {
  let required = [
    "/start", "/help", "/cockpit", "/plan", "/tasks", "/sutra", "/ev", "/nvme",
    "/doctor", "/finops", "/budget", "/exec-brief", "/checklist", "/aspects",
    "/ha", "/storage", "/ecology", "/zigvm", "/blast-radius", "/canvas",
    "/whiteboard", "/babel", "/pacing", "/radar", "/whatif", "/simulate",
    "/rewind", "/repro", "/bisect", "/merge", "/commitments", "/migrate",
    "/lockbox", "/rotate-keys", "/sidecar", "/eco-schedule", "/pair-voice",
    "/dark", "/chaos", "/gameday", "/resuscitate", "/export-audit", "/inference",
    "/immune", "/rack-cv", "/acoustic", "/acoustic-hud", "/mesh", "/verify",
    "/verification", "/voice-roll-call",
  ]
  let covered = covered_literals()
  list.each(required, fn(literal) {
    case list.contains(covered, literal) {
      True -> Nil
      False -> panic as { "responder journeys do not cover " <> literal }
    }
  })
}
