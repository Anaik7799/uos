//// Dispatcher-layer security-incident journeys (SC-TELEGRAM-JOURNEY-001,
//// contract docs/design/20261026-0210). Spec: docs/design/20261026-0215-
//// telegram-journey-security-incident.md.
////
//// Each step is walked through the same pure layers the service uses:
//// `telegram_ingress_guard.classify_directive` (or `evaluate_update` for
//// ingress and attachment steps), then `telegram_read_adapters.route` for
//// read literals and `telegram_action_adapters.route_preview` for
//// ControlledAction literals. The expected class is the JSON "status" of the
//// reply the dispatcher really produces; nothing here expects a fabricated
//// success. DirectReadTool and service-owned arms (approval ledger, memory,
//// knowledge, search, zenoh, rete, cockpit) are executed by
//// telegram_service, not by this layer: for them the test asserts the
//// classify verdict shape only and that no adapter claims the literal.

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

type Field {
  Has(String)
  Is(String, String)
}

type Expect {
  /// Update from a user outside the allowlist: tombstone, no reply.
  Stranger(reason: String)
  /// Photo with caption and no text from the allowlisted user: tombstone.
  Attachment(reason: String)
  /// classify -> DirectReadTool(tool); the service executes it.
  DirectRead(tool: String)
  /// classify -> PreservedDirective(name, _) owned by the service, not an adapter.
  ServiceOwned(name: String)
  /// classify -> Preserved; read adapter reply with this status and fields.
  ReadReply(status: String, fields: List(Field))
  /// classify -> Preserved; action preview reply with this status and fields.
  ActionReply(status: String, fields: List(Field))
  ClassifyDenied(name: String)
  ClassifyUnknown(name: String)
}

type Step {
  Step(
    id: String,
    literal: String,
    text: String,
    family: String,
    expect: Expect,
  )
}

const bot_id = 4242

const allowed_chat = 7001

const allowed_user = 8001

const stranger_user = 9999

fn allowlist() -> guard.Allowlist {
  guard.Allowlist(bot_id, [#(allowed_chat, allowed_user)])
}

fn message_update(user: Int, fields: List(#(String, json.Json))) -> String {
  json.object([
    #("update_id", json.int(100)),
    #(
      "message",
      json.object([
        #("message_id", json.int(10)),
        #(
          "chat",
          json.object([
            #("id", json.int(allowed_chat)),
            #("type", json.string("private")),
          ]),
        ),
        #(
          "from",
          json.object([#("id", json.int(user)), #("is_bot", json.bool(False))]),
        ),
        ..fields
      ]),
    ),
  ])
  |> json.to_string
}

fn rejection_reason(raw: String) -> String {
  case guard.evaluate_update(raw, allowlist()) {
    guard.RejectedUpdate(reason: reason, ..) -> reason
    guard.AcceptedEnvelope(..) -> "ACCEPTED"
    guard.UnidentifiedRejection(reason) -> "UNIDENTIFIED:" <> reason
  }
}

fn status_of(reply: String) -> String {
  case
    json.parse(reply, {
      use status <- decode.field("status", decode.string)
      decode.success(status)
    })
  {
    Ok(status) -> status
    Error(_) -> "UNPARSEABLE"
  }
}

fn has_field(reply: String, key: String) -> Bool {
  case
    json.parse(reply, {
      use value <- decode.field(key, decode.dynamic)
      decode.success(value)
    })
  {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn string_field(reply: String, key: String) -> String {
  case
    json.parse(reply, {
      use value <- decode.field(key, decode.string)
      decode.success(value)
    })
  {
    Ok(value) -> value
    Error(_) -> "MISSING_OR_NOT_STRING"
  }
}

fn check_fields(id: String, reply: String, fields: List(Field)) -> Nil {
  list.each(fields, fn(field) {
    case field {
      Has(key) ->
        should.equal(#(id, key, has_field(reply, key)), #(id, key, True))
      Is(key, value) ->
        should.equal(#(id, key, string_field(reply, key)), #(id, key, value))
    }
  })
}

fn run_step(step: Step) -> Nil {
  let Step(id, _, text, _, expect) = step
  case expect {
    Stranger(reason) ->
      should.equal(
        #(
          id,
          rejection_reason(
            message_update(stranger_user, [#("text", json.string(text))]),
          ),
        ),
        #(id, reason),
      )
    Attachment(reason) ->
      should.equal(
        #(
          id,
          rejection_reason(
            message_update(allowed_user, [
              #("caption", json.string("/status")),
              #(
                "photo",
                json.array([1], fn(i) {
                  json.object([
                    #("file_id", json.string("placeholder-file-id")),
                    #("width", json.int(i)),
                    #("height", json.int(i)),
                  ])
                }),
              ),
            ]),
          ),
        ),
        #(id, reason),
      )
    DirectRead(tool) ->
      should.equal(#(id, guard.classify_directive(text)), #(
        id,
        guard.DirectReadTool(tool),
      ))
    ServiceOwned(name) ->
      case guard.classify_directive(text) {
        guard.PreservedDirective(got, args) -> {
          should.equal(#(id, got), #(id, name))
          should.equal(#(id, read_adapters.route(got, args)), #(id, None))
          should.equal(#(id, action_adapters.route_preview(got, args)), #(
            id,
            None,
          ))
        }
        other ->
          should.equal(#(id, string.inspect(other)), #(id, "PreservedDirective"))
      }
    ReadReply(status, fields) ->
      case guard.classify_directive(text) {
        guard.PreservedDirective(name, args) ->
          case read_adapters.route(name, args) {
            Some(reply) -> {
              should.equal(#(id, status_of(reply)), #(id, status))
              check_fields(id, reply, fields)
            }
            None ->
              should.equal(#(id, "no read adapter"), #(id, "a read reply"))
          }
        other ->
          should.equal(#(id, string.inspect(other)), #(id, "PreservedDirective"))
      }
    ActionReply(status, fields) ->
      case guard.classify_directive(text) {
        guard.PreservedDirective(name, args) ->
          case action_adapters.route_preview(name, args) {
            Some(reply) -> {
              should.equal(#(id, status_of(reply)), #(id, status))
              check_fields(id, reply, fields)
            }
            None ->
              should.equal(#(id, "no action adapter"), #(id, "a preview reply"))
          }
        other ->
          should.equal(#(id, string.inspect(other)), #(id, "PreservedDirective"))
      }
    ClassifyDenied(name) ->
      case guard.classify_directive(text) {
        guard.DeniedMutation(got, reason) -> {
          should.equal(#(id, got), #(id, name))
          should.be_true(string.trim(reason) != "")
        }
        other ->
          should.equal(#(id, string.inspect(other)), #(id, "DeniedMutation"))
      }
    ClassifyUnknown(name) ->
      should.equal(#(id, guard.classify_directive(text)), #(
        id,
        guard.UnknownDirective(name),
      ))
  }
}

fn walk(steps: List(Step)) -> Nil {
  list.each(steps, run_step)
}

fn step_literal(step: Step) -> String {
  step.literal
}

/// Every literal any security journey touches, deduplicated.
pub fn covered_literals() -> List(String) {
  journeys()
  |> list.flat_map(fn(journey) { journey.1 })
  |> list.map(step_literal)
  |> list.filter(fn(literal) { literal != "" })
  |> list.unique
}

fn sec_j1() -> List(Step) {
  [
    Step(
      "SEC-J1/S1",
      "/status",
      "/status",
      "F4",
      Stranger("unsupported_or_unauthorized_identity"),
    ),
    Step("SEC-J1/S2", "", "/nosuch", "F4", ClassifyUnknown("/nosuch")),
    Step("SEC-J1/S3", "", "/status\u{0}", "F4", ClassifyDenied("invalid_input")),
    Step(
      "SEC-J1/S4",
      "/status",
      "/status",
      "F4",
      DirectRead("query_system_health"),
    ),
    Step("SEC-J1/S5", "/peers", "/peers", "F6", DirectRead("query_peers")),
    Step("SEC-J1/S6", "/zenoh", "/zenoh", "F6", ServiceOwned("/zenoh")),
    Step(
      "SEC-J1/S7",
      "/immune",
      "/immune",
      "F9",
      ReadReply("backend_unavailable", [
        Has("backend"),
        Has("reason"),
        Is("backend", "cepaf_gleam/immune/system"),
      ]),
    ),
    Step(
      "SEC-J1/S8",
      "/rete",
      "/rete watchdog=false,mesh_running=false",
      "F4",
      ServiceOwned("/rete"),
    ),
    Step(
      "SEC-J1/S9",
      "/andon",
      "/andon modular_max provider_failure",
      "F6",
      ActionReply("preview", [
        Is("confidence", "simulated"),
        Has("effect_id"),
        Has("approval_required"),
        Is("authority", "NONE"),
      ]),
    ),
  ]
}

fn sec_j2() -> List(Step) {
  [
    Step(
      "SEC-J2/S1",
      "/search",
      "/search credential",
      "F7",
      ServiceOwned("/search"),
    ),
    Step("SEC-J2/S2", "/nvme", "/nvme", "F4", DirectRead("query_storage")),
    Step(
      "SEC-J2/S3",
      "/lockbox",
      "/lockbox seal credential_exposure_suspected",
      "F3",
      ActionReply("preview", [
        Is("confidence", "declared"),
        Has("effect_id"),
        Is("execute", "unavailable:vault_kek"),
        Has("approval_required"),
        Is("authority", "NONE"),
      ]),
    ),
    Step(
      "SEC-J2/S4",
      "/lockbox",
      "/lockbox unseal credential_exposure_suspected",
      "F4",
      ActionReply("denied", [Has("reason")]),
    ),
    Step(
      "SEC-J2/S5",
      "/rotate-keys",
      "/rotate-keys 90 120",
      "F3",
      ActionReply("preview", [
        Is("confidence", "declared"),
        Has("effect_id"),
        Is("policy_decision", "overdue"),
        Has("execute"),
      ]),
    ),
    Step(
      "SEC-J2/S6",
      "/export-audit",
      "/export-audit event=get_failed_stale limit=100",
      "F3",
      ActionReply("preview", [
        Is("confidence", "declared"),
        Has("effect_id"),
        Is("backend", "unavailable:rusty_vault_nif"),
        Has("never_exported"),
      ]),
    ),
    Step("SEC-J2/S7", "/approval", "/approval", "F3", ServiceOwned("/approval")),
    Step(
      "SEC-J2/S8",
      "/approval",
      "/approval propose tg-4501",
      "F1",
      ServiceOwned("/approval_manage"),
    ),
    Step(
      "SEC-J2/S9",
      "/tool",
      "/tool cancel_job_lease j1 -- credential_scare_hold",
      "F3",
      ServiceOwned("/cancel_job_lease"),
    ),
  ]
}

fn sec_j3() -> List(Step) {
  [
    Step(
      "SEC-J3/S1",
      "",
      "(photo, caption /status)",
      "F8",
      Attachment("missing_or_malformed_message_identity"),
    ),
    Step(
      "SEC-J3/S2",
      "/rack-cv",
      "/rack-cv",
      "F8",
      ReadReply("backend_unavailable", [
        Has("backend"),
        Has("reason"),
        Is("backend", "cepaf_gleam/harness/multimodal_features"),
      ]),
    ),
    Step(
      "SEC-J3/S3",
      "/acoustic",
      "/acoustic",
      "F8",
      ReadReply("backend_unavailable", [
        Has("backend"),
        Has("reason"),
        Is("backend", "cepaf_gleam/services/max_inference_daemon"),
      ]),
    ),
    Step(
      "SEC-J3/S4",
      "/whiteboard",
      "/whiteboard",
      "F8",
      ReadReply("backend_unavailable", [
        Has("backend"),
        Has("reason"),
        Is("backend", "cepaf_gleam/harness/telegram_collab.handle_whiteboard"),
      ]),
    ),
    Step(
      "SEC-J3/S5",
      "/babel",
      "/babel",
      "F8",
      ReadReply("backend_unavailable", [
        Has("backend"),
        Has("reason"),
        Is("backend", "cepaf_gleam/harness/telegram_collab.handle_babel"),
      ]),
    ),
    Step(
      "SEC-J3/S6",
      "/sidecar",
      "/sidecar sandbox",
      "F9",
      ActionReply("preview", [
        Is("confidence", "simulated"),
        Has("effect_id"),
        Is("runtime_mode", "simulation_only"),
        Is("admission", "unverified"),
        Is("backend", "unavailable:mirage_unikernel_daemon"),
      ]),
    ),
    Step(
      "SEC-J3/S7",
      "/verification",
      "/verification",
      "F3",
      ClassifyDenied("/verify"),
    ),
  ]
}

fn sec_j4() -> List(Step) {
  [
    Step(
      "SEC-J4/S1",
      "/mesh",
      "/mesh",
      "F6",
      ReadReply("ok", [
        Has("backend"),
        Has("observation"),
        Is("backend", "cepaf_gleam/config/mesh_source"),
      ]),
    ),
    Step("SEC-J4/S2", "/peers", "/peers", "F6", DirectRead("query_peers")),
    Step("SEC-J4/S3", "/board", "/board", "F6", DirectRead("query_board")),
    Step(
      "SEC-J4/S4",
      "/zenoh",
      "/zenoh indrajaal/l0/const/andon/halt",
      "F6",
      ServiceOwned("/zenoh"),
    ),
    Step("SEC-J4/S5", "/ha", "/ha", "F9", DirectRead("query_ha")),
    Step(
      "SEC-J4/S6",
      "/whatif",
      "/whatif zombie 100 200",
      "F3",
      ReadReply("ok", [
        Has("backend"),
        Has("observation"),
        Is("backend", "cepaf_gleam/planning/sa_plan_simulator"),
      ]),
    ),
    Step(
      "SEC-J4/S7",
      "/whatif",
      "/whatif claim 5",
      "F3",
      ReadReply("ok", [
        Has("backend"),
        Has("observation"),
        Is("backend", "cepaf_gleam/planning/sa_plan_simulator"),
      ]),
    ),
    Step(
      "SEC-J4/S8",
      "/simulate",
      "/simulate n1:partitioned n2:nominal n3:nominal",
      "F9",
      ReadReply("denied", [Has("reason"), Is("command", "/whatif")]),
    ),
    Step(
      "SEC-J4/S9",
      "/chaos",
      "/chaos zenoh-network-partition",
      "F9",
      ActionReply("preview", [
        Is("confidence", "declared"),
        Has("effect_id"),
        Is("real_effects", "none"),
        Has("execute"),
      ]),
    ),
    Step(
      "SEC-J4/S10",
      "/gameday",
      "/gameday packet-loss-moderate",
      "F9",
      ActionReply("preview", [
        Is("confidence", "simulated"),
        Has("effect_id"),
        Is("real_effects", "none"),
      ]),
    ),
    Step(
      "SEC-J4/S11",
      "/resuscitate",
      "/resuscitate modular_max",
      "F6",
      ActionReply("preview", [
        Is("confidence", "simulated"),
        Has("effect_id"),
        Has("approval_required"),
        Is("completion_requires", "engaged_backend_probe_receipt"),
      ]),
    ),
  ]
}

fn sec_j5() -> List(Step) {
  [
    Step(
      "SEC-J5/S1",
      "/repro",
      "/repro tg-1",
      "F3",
      ActionReply("preview", [
        Is("confidence", "declared"),
        Has("effect_id"),
        Is("effect", "none"),
        Has("packet_contains"),
      ]),
    ),
    Step(
      "SEC-J5/S2",
      "/bisect",
      "/bisect abc1 abc9 8",
      "F3",
      ActionReply("preview", [
        Is("confidence", "simulated"),
        Has("effect_id"),
        Has("plan"),
      ]),
    ),
    Step(
      "SEC-J5/S3",
      "/rewind",
      "/rewind 3",
      "F3",
      ActionReply("preview", [
        Is("confidence", "simulated"),
        Has("effect_id"),
        Has("replay_before_sha256"),
        Has("replay_after_sha256"),
      ]),
    ),
    Step(
      "SEC-J5/S4",
      "/export-audit",
      "/export-audit",
      "F3",
      ActionReply("preview", [
        Is("confidence", "declared"),
        Has("effect_id"),
        Is("backend", "unavailable:rusty_vault_nif"),
      ]),
    ),
    Step(
      "SEC-J5/S5",
      "/escalate",
      "/escalate 3600",
      "F6",
      ActionReply("preview", [
        Is("confidence", "simulated"),
        Has("effect_id"),
        Is("staleness_level", "dead"),
        Is("runbook_severity", "P0"),
        Has("approval_required"),
      ]),
    ),
    Step(
      "SEC-J5/S6",
      "/escalate",
      "/escalate 90",
      "F6",
      ActionReply("preview", [
        Is("confidence", "simulated"),
        Has("effect_id"),
        Is("staleness_level", "stale"),
        Is("runbook_severity", "P2"),
      ]),
    ),
    Step(
      "SEC-J5/S7",
      "/dark",
      "/dark emergency",
      "F5",
      ActionReply("preview", [
        Is("confidence", "declared"),
        Has("effect_id"),
        Is("target_mode", "emergency"),
        Has("approval_required"),
      ]),
    ),
    Step(
      "SEC-J5/S8",
      "/approval",
      "/approval propose tg-4502",
      "F1",
      ServiceOwned("/approval_manage"),
    ),
    Step(
      "SEC-J5/S9",
      "/approval",
      "/approval submit tg-4502 operator signed-receipt-placeholder",
      "F1",
      ServiceOwned("/approval_manage"),
    ),
  ]
}

fn sec_j6() -> List(Step) {
  [
    Step(
      "SEC-J6/S1",
      "/handover",
      "/handover incident-20261026",
      "F3",
      ActionReply("preview", [
        Is("confidence", "observed"),
        Has("effect_id"),
        Is("slug", "incident-20261026"),
        Has("sections"),
      ]),
    ),
    Step(
      "SEC-J6/S2",
      "/handover",
      "/handover",
      "F4",
      ActionReply("denied", [Has("reason")]),
    ),
    Step(
      "SEC-J6/S3",
      "/commitments",
      "/commitments",
      "F3",
      ActionReply("preview", [
        Is("confidence", "declared"),
        Has("effect_id"),
        Is(
          "execute",
          "backend_unavailable:cepaf_gleam/harness/telegram_task_command",
        ),
      ]),
    ),
    Step(
      "SEC-J6/S4",
      "/postmortem",
      "/postmortem",
      "F3",
      ReadReply("ok", [
        Has("backend"),
        Has("observation"),
        Is("backend", "cepaf_gleam/harness/files (docs/journal)"),
      ]),
    ),
    Step(
      "SEC-J6/S5",
      "/retro",
      "/retro 5",
      "F3",
      ReadReply("ok", [
        Has("backend"),
        Has("observation"),
        Is("backend", "cepaf_gleam/harness/files (docs/journal)"),
      ]),
    ),
    Step(
      "SEC-J6/S6",
      "/adr",
      "/adr 1",
      "F7",
      ReadReply("ok", [
        Has("backend"),
        Has("observation"),
        Is("backend", "cepaf_gleam/harness/files (docs/zk)"),
      ]),
    ),
    Step("SEC-J6/S7", "/plan", "/plan", "F3", DirectRead("query_saplan")),
    Step("SEC-J6/S8", "/finops", "/finops", "F3", DirectRead("query_finops")),
    Step(
      "SEC-J6/S9",
      "/exec-brief",
      "/exec-brief",
      "F7",
      DirectRead("query_exec_brief"),
    ),
    Step(
      "SEC-J6/S10",
      "/messages",
      "/messages",
      "F2",
      ServiceOwned("/messages"),
    ),
    Step("SEC-J6/S11", "/cockpit", "/cockpit", "F5", ServiceOwned("/cockpit")),
    Step(
      "SEC-J6/S12",
      "/checklist",
      "/checklist",
      "F5",
      DirectRead("query_checklist"),
    ),
  ]
}

fn journeys() -> List(#(String, List(Step))) {
  [
    #("SEC-J1", sec_j1()),
    #("SEC-J2", sec_j2()),
    #("SEC-J3", sec_j3()),
    #("SEC-J4", sec_j4()),
    #("SEC-J5", sec_j5()),
    #("SEC-J6", sec_j6()),
  ]
}

/// SEC-J1 Suspicious ingress: 9 steps.
pub fn sec_j1_suspicious_ingress_test() {
  walk(sec_j1())
}

/// SEC-J2 Credential-exposure scare: 9 steps.
pub fn sec_j2_credential_exposure_scare_test() {
  walk(sec_j2())
}

/// SEC-J3 Hostile media attachment: 7 steps.
pub fn sec_j3_hostile_media_attachment_test() {
  walk(sec_j3())
}

/// SEC-J4 Swarm and mesh anomaly: 11 steps.
pub fn sec_j4_swarm_mesh_anomaly_test() {
  walk(sec_j4())
}

/// SEC-J5 Evidence export and escalation: 9 steps.
pub fn sec_j5_evidence_export_and_escalation_test() {
  walk(sec_j5())
}

/// SEC-J6 Post-incident handover: 12 steps.
pub fn sec_j6_post_incident_handover_test() {
  walk(sec_j6())
}

pub fn every_literal_is_in_the_catalog_test() {
  let catalog = list.map(commands.catalog(), fn(d) { d.literal })
  list.each(covered_literals(), fn(literal) {
    should.equal(#(literal, list.contains(catalog, literal)), #(literal, True))
  })
}

pub fn every_literal_step_text_parses_to_its_literal_test() {
  list.each(list.flat_map(journeys(), fn(j) { j.1 }), fn(step) {
    case step.literal {
      "" -> Nil
      literal ->
        case commands.parse(step.text) {
          Ok(invocation) ->
            should.equal(#(step.id, invocation.definition.literal), #(
              step.id,
              literal,
            ))
          Error(_) ->
            should.equal(#(step.id, "parse error"), #(step.id, literal))
        }
    }
  })
}

pub fn six_journeys_with_unique_ids_and_known_families_test() {
  let all = journeys()
  should.equal(list.length(all), 6)
  let ids = list.flat_map(all, fn(j) { list.map(j.1, fn(s) { s.id }) })
  should.equal(list.length(list.unique(ids)), list.length(ids))
  let families = ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9"]
  list.each(list.flat_map(all, fn(j) { j.1 }), fn(s) {
    should.equal(#(s.id, list.contains(families, s.family)), #(s.id, True))
  })
}

pub fn the_set_covers_all_nine_families_test() {
  let used =
    list.flat_map(journeys(), fn(j) { list.map(j.1, fn(s) { s.family }) })
  list.each(["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9"], fn(f) {
    should.equal(#(f, list.contains(used, f)), #(f, True))
  })
}

pub fn no_plain_message_expects_an_executed_or_duplicate_reply_test() {
  list.each(list.flat_map(journeys(), fn(j) { j.1 }), fn(step) {
    case step.expect {
      ReadReply(status, _) | ActionReply(status, _) ->
        should.equal(
          #(
            step.id,
            list.contains(
              ["ok", "preview", "denied", "backend_unavailable"],
              status,
            ),
          ),
          #(step.id, True),
        )
      _ -> Nil
    }
  })
}

pub fn covered_literals_has_no_duplicates_test() {
  should.equal(
    list.length(covered_literals()),
    list.length(list.unique(covered_literals())),
  )
}
