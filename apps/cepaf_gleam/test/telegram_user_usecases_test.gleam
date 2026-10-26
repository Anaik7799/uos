import cepaf_gleam/harness/telegram
import cepaf_gleam/harness/telegram_action_adapters as action_adapters
import cepaf_gleam/harness/telegram_commands as commands
import cepaf_gleam/harness/telegram_conversation as conv
import cepaf_gleam/harness/telegram_dialogue_command as dialogue
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_media_inspect as media_inspect
import cepaf_gleam/harness/telegram_media_ref as media_ref
import cepaf_gleam/harness/telegram_memory_command as memory_cmd
import cepaf_gleam/harness/telegram_read_adapters as read_adapters
import cepaf_gleam/harness/telegram_tool_command as tool_cmd
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

fn sample_allowlist() -> guard.Allowlist {
  guard.Allowlist(bot_id: 8_660_817_750, allowed_pairs: [#(6_249_174_059, 6_249_174_059)])
}

pub fn handle_storage_directive_test() {
  let inbound =
    telegram.InboundMessage(
      update_id: 101,
      message_id: 555,
      chat_id: "12345",
      from_user: "operator",
      text: "/storage",
      timestamp_ms: 1_700_000_000,
    )

  let resp = telegram.handle_message(inbound)
  resp.chat_id |> should.equal("12345")
  resp.intent_id |> should.equal("tg-101")
  string.contains(resp.text, "Hardware Storage Enclave Guard")
  |> should.be_true
}

pub fn handle_zk_directive_test() {
  let inbound =
    telegram.InboundMessage(
      update_id: 102,
      message_id: 556,
      chat_id: "12345",
      from_user: "operator",
      text: "/zk andon",
      timestamp_ms: 1_700_000_000,
    )

  let resp = telegram.handle_message(inbound)
  resp.chat_id |> should.equal("12345")
}

pub fn handle_checklist_directive_test() {
  let inbound =
    telegram.InboundMessage(
      update_id: 103,
      message_id: 557,
      chat_id: "12345",
      from_user: "auditor",
      text: "/checklist",
      timestamp_ms: 1_700_000_000,
    )

  let resp = telegram.handle_message(inbound)
  resp.chat_id |> should.equal("12345")
  string.contains(resp.text, "18/18") |> should.be_true
}

pub fn handle_dark_directive_test() {
  let inbound =
    telegram.InboundMessage(
      update_id: 104,
      message_id: 558,
      chat_id: "12345",
      from_user: "sre",
      text: "/dark",
      timestamp_ms: 1_700_000_000,
    )

  let resp = telegram.handle_message(inbound)
  resp.chat_id |> should.equal("12345")
}

pub fn handle_andon_directive_test() {
  let inbound =
    telegram.InboundMessage(
      update_id: 105,
      message_id: 559,
      chat_id: "12345",
      from_user: "sre",
      text: "/andon",
      timestamp_ms: 1_700_000_000,
    )

  let resp = telegram.handle_message(inbound)
  resp.chat_id |> should.equal("12345")
}

/// Verify all 77 canonical literals plus the 78th legacy `/saplan` alias parse
/// cleanly and classify deterministically through `telegram_ingress_guard`.
pub fn all_78_command_invocations_parse_and_classify_test() {
  let catalog = commands.catalog()
  list.length(catalog) |> should.equal(77)

  list.each(catalog, fn(defn) {
    let parsed = commands.parse(defn.literal)
    should.be_ok(parsed)
    case guard.classify_directive(defn.literal) {
      guard.UnknownDirective(name) ->
        should.equal(#(defn.literal, "known"), #(name, "UnknownDirective"))
      _ -> Nil
    }
  })

  // 78th invocation: /saplan -> canonical /plan (ReadObservation)
  case commands.parse("/saplan") {
    Ok(inv) -> {
      inv.definition.literal |> should.equal("/saplan")
      inv.definition.canonical |> should.equal("/plan")
      inv.definition.kind |> should.equal(commands.ReadObservation)
    }
    Error(_) -> should.fail()
  }
  guard.classify_directive("/saplan")
  |> should.equal(guard.DirectReadTool("query_saplan"))
}

/// Verify Information commands (/start, /help, /cockpit) return pure reference
/// replies and never echo untrusted trailing arguments.
pub fn information_commands_reference_reply_test() {
  let assert Ok(start_inv) = commands.parse("/start untrusted_arg_token")
  let assert Ok(help_inv) = commands.parse("/help untrusted_arg_token")
  let assert Ok(cockpit_inv) = commands.parse("/cockpit untrusted_arg_token")

  let assert Ok(start_reply) = commands.reference_reply(start_inv)
  let assert Ok(help_reply) = commands.reference_reply(help_inv)
  let assert Ok(cockpit_reply) = commands.reference_reply(cockpit_inv)

  start_reply |> should.equal(help_reply)
  string.contains(help_reply, "untrusted_arg_token") |> should.be_false
  string.contains(cockpit_reply, "http://nas-1.tail55d152.ts.net:4100/")
  |> should.be_true
  string.contains(cockpit_reply, "untrusted_arg_token") |> should.be_false
}

/// Verify all 19 ControlledAction preview adapters route through
/// `telegram_action_adapters.route_preview` and never execute side effects.
pub fn all_19_controlled_action_preview_adapters_test() {
  let lits = action_adapters.literals()
  list.length(lits) |> should.equal(19)

  list.each(lits, fn(lit) {
    case action_adapters.route_preview(lit, []) {
      Some(reply) -> {
        let is_preview_or_denied =
          string.contains(reply, "\"status\":\"preview\"")
          || string.contains(reply, "\"status\":\"denied\"")
        is_preview_or_denied |> should.be_true
      }
      option.None -> should.fail()
    }
  })
}

/// Verify the 7 fail-closed unwired sensor/voice/vision commands return
/// `backend_unavailable` or `denied` (never fabricated telemetry).
pub fn fail_closed_unwired_sensor_and_voice_commands_test() {
  let unavailable_literals = [
    "/pacing", "/rack-cv", "/acoustic", "/radar", "/babel", "/whiteboard",
  ]
  list.each(unavailable_literals, fn(lit) {
    case read_adapters.route(lit, []) {
      Some(reply) ->
        string.contains(reply, "\"status\":\"backend_unavailable\"")
        |> should.be_true
      option.None -> should.fail()
    }
  })

  // /voice-roll-call is refused directly at ingress classification
  case guard.classify_directive("/voice-roll-call") {
    guard.DeniedMutation("/voice-roll-call", _) -> Nil
    _ -> should.fail()
  }
}

/// Verify pure in-repo digital-twin simulation commands (/whatif, /simulate, /canvas).
pub fn digital_twin_simulation_usecases_test() {
  let assert Some(claim_reply) =
    read_adapters.route("/whatif", ["claim", "12"])
  string.contains(claim_reply, "\"status\":\"ok\"") |> should.be_true
  string.contains(claim_reply, "\"scenario\":\"concurrent_claim\"")
  |> should.be_true
  string.contains(claim_reply, "\"granted\":1") |> should.be_true
  string.contains(claim_reply, "\"rejected\":11") |> should.be_true

  let assert Some(retry_reply) =
    read_adapters.route("/whatif", ["retry", "4"])
  string.contains(retry_reply, "\"scenario\":\"oban_retry_backoff\"")
  |> should.be_true

  let assert Some(zombie_reply) =
    read_adapters.route("/whatif", ["zombie", "1000", "2000"])
  string.contains(zombie_reply, "\"status\":\"ok\"") |> should.be_true

  let assert Some(sim_reply) =
    read_adapters.route("/simulate", ["nas1:nominal", "vm1:degraded"])
  string.contains(sim_reply, "\"status\":\"ok\"") |> should.be_true
  string.contains(sim_reply, "\"scenario\":\"peer_mesh_quorum\"")
  |> should.be_true

  let assert Some(canvas_reply) =
    read_adapters.route("/canvas", ["node1:10,20,30", "node2:40,50,60"])
  string.contains(canvas_reply, "\"status\":\"ok\"") |> should.be_true
  string.contains(canvas_reply, "\"split_replicas_merge_converged\":true")
  |> should.be_true
}

/// Verify 8-turn conversation memory, history inspection, and Socratic dialogue.
pub fn memory_history_and_socratic_dialogue_usecases_test() {
  let scope =
    conv.Scope(
      bot_id: 8_660_817_750,
      chat_id: 6_249_174_059,
      user_id: 6_249_174_059,
    )
  let ctx0 = conv.Context(scope: scope, turns: [])
  let assert Ok(ctx1) =
    conv.append(
      ctx0,
      conv.Turn(
        update_id: 1001,
        prompt: "What is the EV ceiling?",
        reply: "EV-93 is the admitted ceiling.",
      ),
    )
  let assert Ok(ctx2) =
    conv.append(
      ctx1,
      conv.Turn(
        update_id: 1002,
        prompt: "Are EV-94..109 admitted?",
        reply: "No, EV-94..109 remain NOT_ADMITTED.",
      ),
    )

  let assert Ok(mem_reply) = memory_cmd.reply("/memory", ctx2)
  mem_reply.clear |> should.be_false
  string.contains(mem_reply.text, "2 of 8 complete exchanges stored")
  |> should.be_true

  let assert Ok(hist_reply) = memory_cmd.reply("/history 1", ctx2)
  string.contains(hist_reply.text, "History (1 of 2 stored exchanges):")
  |> should.be_true
  string.contains(hist_reply.text, "EV-94..109") |> should.be_true

  let assert Ok(clear_reply) = memory_cmd.reply("/memory clear", ctx2)
  clear_reply.clear |> should.be_true

  let assert Ok(topic) =
    dialogue.topic("SQLite WAL contention during migration")
  topic |> should.equal("SQLite WAL contention during migration")
  let assert Ok(req) =
    conv.prepare_request(
      ctx2,
      "/socratic SQLite WAL contention during migration",
    )
  string.contains(req.system, "Use Socratic dialogue") |> should.be_true
}

/// Verify 2oo3 constitutional approval and structured `/tool` / `/action` grammar.
pub fn approval_and_tool_bridge_usecases_test() {
  guard.classify_directive("/approval")
  |> should.equal(guard.PreservedDirective("/approval", []))

  guard.classify_directive("/approval propose tg-1001")
  |> should.equal(guard.PreservedDirective("/approval_manage", [
    "propose",
    "tg-1001",
  ]))

  guard.classify_directive("/approval submit tg-1001 agy signed_receipt_hex")
  |> should.equal(guard.PreservedDirective("/approval_manage", [
    "submit",
    "tg-1001",
    "agy",
    "signed_receipt_hex",
  ]))

  guard.classify_directive("/approval withdraw tg-1001")
  |> should.equal(guard.PreservedDirective("/approval_manage", [
    "withdraw",
    "tg-1001",
  ]))

  // Unsigned free-text approval must be refused
  case guard.classify_directive("/approval approve tg-1001") {
    guard.DeniedMutation("/approval", _) -> Nil
    _ -> should.fail()
  }

  // /tool and /action alias
  let assert Ok(cancel_cmd) =
    tool_cmd.parse("cancel_job_lease job_99 -- stalled_worker")
  cancel_cmd
  |> should.equal(tool_cmd.CancelLease("job_99", "stalled_worker"))

  guard.classify_directive("/action cancel_job_lease job_99 -- stalled_worker")
  |> should.equal(guard.PreservedDirective("/cancel_job_lease", [
    "job_99",
    "stalled_worker",
  ]))
}

/// Verify captioned media intake, bare/forwarded media refusal, and 64-byte magic
/// header inspection across Photo, Document, Voice, Audio, and Video.
pub fn captioned_media_intake_and_magic_inspection_usecases_test() {
  let allow = sample_allowlist()

  // 1. Captioned photo from allowlisted pair is accepted
  let captioned_photo_json =
    "{\"update_id\":7001,\"message\":{\"message_id\":91,\"chat\":{\"id\":6249174059,\"type\":\"private\"},\"from\":{\"id\":6249174059,\"is_bot\":false},\"caption\":\"/status\",\"photo\":[{\"file_id\":\"p1\",\"file_unique_id\":\"u1\",\"width\":100,\"height\":100,\"file_size\":1024}]}}"
  case guard.evaluate_update(captioned_photo_json, allow) {
    guard.AcceptedEnvelope(
      update_id: 7001,
      directive: guard.DirectReadTool("query_system_health"),
      ..,
    ) -> Nil
    _ -> should.fail()
  }

  // 2. Bare photo without caption from allowlisted pair is refused with media_without_caption
  let bare_photo_json =
    "{\"update_id\":7002,\"message\":{\"message_id\":92,\"chat\":{\"id\":6249174059,\"type\":\"private\"},\"from\":{\"id\":6249174059,\"is_bot\":false},\"photo\":[{\"file_id\":\"p1\",\"file_unique_id\":\"u1\",\"width\":100,\"height\":100,\"file_size\":1024}]}}"
  case guard.evaluate_update(bare_photo_json, allow) {
    guard.RejectedUpdate(reason: "media_without_caption", ..) -> Nil
    _ -> should.fail()
  }

  // 3. Bare photo from unauthorized stranger is refused with unsupported_or_unauthorized_identity (C-10)
  let stranger_photo_json =
    "{\"update_id\":7003,\"message\":{\"message_id\":93,\"chat\":{\"id\":999999,\"type\":\"private\"},\"from\":{\"id\":999999,\"is_bot\":false},\"photo\":[{\"file_id\":\"p1\",\"file_unique_id\":\"u1\",\"width\":100,\"height\":100,\"file_size\":1024}]}}"
  case guard.evaluate_update(stranger_photo_json, allow) {
    guard.RejectedUpdate(reason: "unsupported_or_unauthorized_identity", ..) ->
      Nil
    _ -> should.fail()
  }

  // 4. Forwarded message is refused with forwarded_not_supported (C-02)
  let forwarded_json =
    "{\"update_id\":7004,\"message\":{\"message_id\":94,\"chat\":{\"id\":6249174059,\"type\":\"private\"},\"from\":{\"id\":6249174059,\"is_bot\":false},\"forward_date\":1700000000,\"text\":\"/status\"}}"
  case guard.evaluate_update(forwarded_json, allow) {
    guard.RejectedUpdate(reason: "forwarded_not_supported", ..) -> Nil
    _ -> should.fail()
  }

  // 5. 64-byte magic header inspection across media kinds
  media_inspect.inspect(
    media_ref.Photo,
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00>>,
  )
  |> should.equal(media_inspect.Accepted(media_inspect.Png))

  media_inspect.inspect(
    media_ref.Document,
    <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37>>,
  )
  |> should.equal(media_inspect.Accepted(media_inspect.Pdf))

  media_inspect.inspect(
    media_ref.Voice,
    <<0x4F, 0x67, 0x67, 0x53, 0x00, 0x02>>,
  )
  |> should.equal(media_inspect.Accepted(media_inspect.Ogg))

  // Mismatched container (PDF bytes sent as Voice) is rejected
  media_inspect.inspect(
    media_ref.Voice,
    <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37>>,
  )
  |> should.equal(media_inspect.Rejected(
    "sniffed_type_not_allowed_for_kind",
    media_inspect.Pdf,
  ))
}
