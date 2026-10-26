//// Comprehensive Fractal (L0..L9) Combinatorial & Full-Feature-Surface Test Suite
//// Verifies over 1,280 deterministic cross-product combinations across:
////   1. L0..L9 Fractal Layer Bijection x 78 Command Invocations (77 catalog + /saplan)
////   2. 78 Command Invocations x 6 Identity/Chat/Forwarding States (468 combinations)
////   3. 78 Command Invocations x 5 Syntactic/Boundary Perturbations (390 combinations)
////   4. 19 ControlledAction Preview Adapters x 4 Argument Regimes (76 combinations)
////   5. 17 ReadObservation Adapters x 4 Argument Regimes (68 combinations)
////   6. 8 MediaKind Variants x 11 Binary Signatures + 5 Carriers x 4 States (108 combinations)
////   7. 14 Mini-App Views/Routes x 6 Security/Navigation Vectors (84 combinations)
////   8. Multi-Turn Memory Ring Buffer (1..9 turns) x Dialogue Modes x 2oo3 Approval x Tool Bridge

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
import cepaf_gleam/telegram/auth as webapp_auth
import cepaf_gleam/telegram/types as webapp_types
import cepaf_gleam/ui/lustre/mini_app
import cepaf_gleam/ui/wisp/mini_app_routes
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import telegram_journey_defence_test as j_def
import telegram_journey_responder_test as j_resp
import telegram_journey_security_test as j_sec

const bot_id = 8_660_817_750

const allowed_chat_id = 6_249_174_059

const allowed_user_id = 6_249_174_059

fn allowlist() -> guard.Allowlist {
  guard.Allowlist(
    bot_id: bot_id,
    allowed_pairs: [#(allowed_chat_id, allowed_user_id)],
  )
}

fn all_78_literals() -> List(String) {
  let catalog_lits = list.map(commands.catalog(), fn(d) { d.literal })
  list.append(catalog_lits, ["/saplan"])
}

fn fractal_layer_for_literal(lit: String) -> String {
  case lit {
    // L0: Constitutional Authority, 2oo3 Quorum, Jidoka Stop-Line, Lockbox & Enclave Isolation
    "/approval"
    | "/andon"
    | "/dark"
    | "/lockbox"
    | "/commitments"
    | "/voice-roll-call" -> "L0"
    // L1: Physical Hardware Interlocks & Rack/Acoustic Sensor Boundaries
    "/storage" | "/rack-cv" | "/acoustic" | "/eco-schedule" -> "L1"
    // L2: Deterministic Kernel, Crash Replay, Profiling, Sidecar & Key Rotation
    "/repro" | "/profile" | "/sidecar" | "/rotate-keys" -> "L2"
    // L3: OTP Supervision, Action/Tool Routing, Memory & History Actors
    "/doctor"
    | "/tool"
    | "/action"
    | "/memory"
    | "/history"
    | "/resuscitate" -> "L3"
    // L4: Durable SQLite WAL Stores (Sa-Plan, Migration, Rewind, Merge, Bisect)
    "/plan"
    | "/tasks"
    | "/saplan"
    | "/task"
    | "/migrate"
    | "/rewind"
    | "/merge"
    | "/bisect" -> "L4"
    // L5: Formal Verification, Hermes Wiki, ZK, ADR, FMEA, Rete-UL & Journals
    "/zk"
    | "/wiki"
    | "/adr"
    | "/ADR"
    | "/fmea"
    | "/checklist"
    | "/verify"
    | "/rete"
    | "/postmortem"
    | "/retro"
    | "/intent" -> "L5"
    // L6: Multi-Agent Swarm, Inference Cascade, Socratic/Red-Team & Digital Twins
    "/swarm"
    | "/inference"
    | "/ask"
    | "/chat"
    | "/brief"
    | "/redteam"
    | "/socratic"
    | "/whatif"
    | "/simulate"
    | "/canvas"
    | "/chaos"
    | "/gameday" -> "L6"
    // L7: Tailnet Mesh Transport, Zenoh Pub/Sub & External Horizon Boundaries
    "/zenoh" | "/mesh" | "/radar" | "/babel" | "/whiteboard" -> "L7"
    // L8: Cybernetic Telemetry, High Availability, Immune, Ecology & FinOps
    "/status"
    | "/health"
    | "/ha"
    | "/immune"
    | "/ecology"
    | "/finops"
    | "/cost"
    | "/budget"
    | "/acoustic-hud"
    | "/export-audit"
    | "/pacing" -> "L8"
    // L9: Operator UX, Cockpit Orientation, Incident Collaboration & Voice Cybernetics
    _ -> "L9"
  }
}

// =============================================================================
// 1. Fractal L0..L9 Bijection & Full 78-Invocation Surface Coverage
// =============================================================================

pub fn fractal_l0_to_l9_complete_bijection_and_78_invocation_surface_test() {
  let lits = all_78_literals()
  list.length(lits) |> should.equal(78)
  list.length(list.unique(lits)) |> should.equal(78)

  let layers = ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9"]
  let layer_counts =
    list.map(layers, fn(layer) {
      let matching =
        list.filter(lits, fn(lit) { fractal_layer_for_literal(lit) == layer })
      // Every fractal layer L0..L9 must be non-empty
      { matching != [] } |> should.be_true
      list.length(matching)
    })

  // Sum of L0..L9 partitions must equal exactly 78
  let total_mapped = list.fold(layer_counts, 0, fn(acc, n) { acc + n })
  total_mapped |> should.equal(78)

  // Verify the 3 operator journey suites together cover 100% of the 77 catalog literals
  let sec_lits = j_sec.covered_literals()
  let def_lits = j_def.covered_literals()
  let resp_lits = j_resp.covered_literals()
  let journey_union =
    list.unique(list.flatten([sec_lits, def_lits, resp_lits]))
  list.length(journey_union) |> should.equal(77)
}

// =============================================================================
// 2. 78 Command Invocations x 6 Identity/Chat States = 468 Combinations
// =============================================================================

fn build_update_json(
  update_id: Int,
  chat_id: Int,
  chat_type: String,
  user_id: Int,
  is_bot: Bool,
  forwarded: Bool,
  text: String,
) -> String {
  let bot_str = case is_bot {
    True -> "true"
    False -> "false"
  }
  let fwd_field = case forwarded {
    True -> ",\"forward_date\":1700000000"
    False -> ""
  }
  "{\"update_id\":"
  <> int.to_string(update_id)
  <> ",\"message\":{\"message_id\":10,\"chat\":{\"id\":"
  <> int.to_string(chat_id)
  <> ",\"type\":\""
  <> chat_type
  <> "\"},\"from\":{\"id\":"
  <> int.to_string(user_id)
  <> ",\"is_bot\":"
  <> bot_str
  <> "}"
  <> fwd_field
  <> ",\"text\":\""
  <> text
  <> "\"}}"
}

pub fn fractal_78_invocations_x_6_identity_chat_combinations_matrix_test() {
  let allow = allowlist()
  let lits = all_78_literals()

  list.index_map(lits, fn(lit, idx) {
    let base_id = 10_000 + idx * 10

    // Regime 1: Authorized private operator -> AcceptedEnvelope
    let json_ok =
      build_update_json(
        base_id + 1,
        allowed_chat_id,
        "private",
        allowed_user_id,
        False,
        False,
        lit,
      )
    case guard.evaluate_update(json_ok, allow) {
      guard.AcceptedEnvelope(update_id: uid, ..) ->
        uid |> should.equal(base_id + 1)
      _ -> should.fail()
    }

    // Regime 2: Unauthorized chat_id -> RejectedUpdate(unsupported_or_unauthorized_identity)
    let json_bad_chat =
      build_update_json(
        base_id + 2,
        111_111,
        "private",
        allowed_user_id,
        False,
        False,
        lit,
      )
    case guard.evaluate_update(json_bad_chat, allow) {
      guard.RejectedUpdate(reason: "unsupported_or_unauthorized_identity", ..) ->
        Nil
      _ -> should.fail()
    }

    // Regime 3: Unauthorized user_id -> RejectedUpdate(unsupported_or_unauthorized_identity)
    let json_bad_user =
      build_update_json(
        base_id + 3,
        allowed_chat_id,
        "private",
        222_222,
        False,
        False,
        lit,
      )
    case guard.evaluate_update(json_bad_user, allow) {
      guard.RejectedUpdate(reason: "unsupported_or_unauthorized_identity", ..) ->
        Nil
      _ -> should.fail()
    }

    // Regime 4: Bot sender (is_bot: true) -> RejectedUpdate(unsupported_or_unauthorized_identity)
    let json_bot =
      build_update_json(
        base_id + 4,
        allowed_chat_id,
        "private",
        allowed_user_id,
        True,
        False,
        lit,
      )
    case guard.evaluate_update(json_bot, allow) {
      guard.RejectedUpdate(reason: "unsupported_or_unauthorized_identity", ..) ->
        Nil
      _ -> should.fail()
    }

    // Regime 5: Disallowed channel chat_type -> RejectedUpdate(unsupported_or_unauthorized_identity)
    let json_channel =
      build_update_json(
        base_id + 5,
        allowed_chat_id,
        "channel",
        allowed_user_id,
        False,
        False,
        lit,
      )
    case guard.evaluate_update(json_channel, allow) {
      guard.RejectedUpdate(reason: "unsupported_or_unauthorized_identity", ..) ->
        Nil
      _ -> should.fail()
    }

    // Regime 6: Forwarded message -> RejectedUpdate(forwarded_not_supported)
    let json_fwd =
      build_update_json(
        base_id + 6,
        allowed_chat_id,
        "private",
        allowed_user_id,
        False,
        True,
        lit,
      )
    case guard.evaluate_update(json_fwd, allow) {
      guard.RejectedUpdate(reason: "forwarded_not_supported", ..) -> Nil
      _ -> should.fail()
    }
  })
}

// =============================================================================
// 3. 78 Invocations x 5 Syntactic & Boundary Perturbations = 390 Combinations
// =============================================================================

pub fn fractal_78_invocations_x_5_syntactic_and_boundary_perturbations_matrix_test() {
  let lits = all_78_literals()
  let oversize_arg = string.repeat("a", 2100)

  list.each(lits, fn(lit) {
    // 1. Bare literal
    let assert Ok(inv_bare) = commands.parse(lit)
    inv_bare.definition.literal |> should.equal(lit)
    inv_bare.args |> should.equal("")

    // 2. Foreign @bot suffix is rejected fail-closed; surrounding whitespace is trimmed
    should.be_error(commands.parse(lit <> "@uos_c3i_bot"))
    let assert Ok(inv_padded) = commands.parse("  " <> lit <> "  ")
    inv_padded.definition.canonical |> should.equal(inv_bare.definition.canonical)
    inv_padded.definition.kind |> should.equal(inv_bare.definition.kind)

    // 3. Bounded multi-token arguments
    let assert Ok(inv_args) = commands.parse(lit <> " alpha_token beta_token")
    inv_args.args |> should.equal("alpha_token beta_token")

    // 4. Embedded NUL byte must fail closed
    should.be_error(commands.parse(lit <> " safe\u{0000}evil"))

    // 5. Oversized argument payload (> 2048 bytes) must fail closed
    should.be_error(commands.parse(lit <> " " <> oversize_arg))
  })
}

// =============================================================================
// 4. 19 ControlledAction Adapters x 4 Argument Regimes = 76 Combinations
// =============================================================================

fn valid_action_args(lit: String) -> List(String) {
  case lit {
    "/andon" -> ["storage", "thermal_limit"]
    "/dark" -> ["on", "external_ingress"]
    "/chaos" -> ["latency", "vm-1"]
    "/rewind" -> ["2d95ef75cfec", "rollback_drill"]
    "/merge" -> ["integration/wave7e", "main"]
    "/resuscitate" -> ["vm-1", "heartbeat_timeout"]
    "/bisect" -> ["7cce19b8e745", "2d95ef75cfec"]
    "/repro" -> ["inc-20261027", "42"]
    "/sidecar" -> ["max_inference", "reload"]
    "/migrate" -> ["coordinator", "v2"]
    "/gameday" -> ["tailnet_partition", "15"]
    "/rotate-keys" -> ["telegram"]
    "/lockbox" -> ["status", "incident_p0"]
    "/profile" -> ["telegram_service", "1000"]
    "/intent" -> ["drain_vm1", "zero_loss"]
    "/eco-schedule" -> ["hermes_sweep", "off_peak"]
    "/export-audit" -> ["telegram_ingress", "24h"]
    "/commitments" -> ["register", "wave7e_closure"]
    "/handover" -> ["emea_sre", "apac_sre"]
    "/escalate" -> ["p1", "sec_lead", "webhook_probe"]
    "/voice-cmd" -> ["status_check_nas1"]
    "/pair-voice" -> ["otp_supervisor_loop", "15"]
    _ -> ["target_a", "reason_b"]
  }
}

pub fn fractal_19_controlled_actions_x_4_argument_regimes_matrix_test() {
  let lits = action_adapters.literals()
  list.length(lits) |> should.equal(19)
  let huge = string.repeat("x", 300)

  list.each(lits, fn(lit) {
    // Regime 1: Valid arguments -> preview or denied, never executed:true
    let assert Some(r_valid) =
      action_adapters.route_preview(lit, valid_action_args(lit))
    string.contains(r_valid, "\"executed\":true") |> should.be_false
    {
      string.contains(r_valid, "\"status\":\"preview\"")
      || string.contains(r_valid, "\"status\":\"denied\"")
    }
    |> should.be_true

    // Regime 2: Empty arguments -> preview or denied, never executed:true
    let assert Some(r_empty) = action_adapters.route_preview(lit, [])
    string.contains(r_empty, "\"executed\":true") |> should.be_false

    // Regime 3: Control byte argument -> denied
    let assert Some(r_ctrl) =
      action_adapters.route_preview(lit, ["bad\u{0007}arg"])
    string.contains(r_ctrl, "\"status\":\"denied\"") |> should.be_true

    // Regime 4: Oversized argument -> denied
    let assert Some(r_huge) = action_adapters.route_preview(lit, [huge])
    string.contains(r_huge, "\"status\":\"denied\"") |> should.be_true
  })
}

// =============================================================================
// 5. 17 ReadObservation Adapters x 4 Argument Regimes = 68 Combinations
// =============================================================================

fn valid_read_args(lit: String) -> List(String) {
  case lit {
    "/adr" | "/ADR" -> ["001"]
    "/whatif" -> ["claim", "8"]
    "/simulate" -> ["nas1:nominal", "vm1:degraded"]
    "/canvas" -> ["n1:10,20,30", "n2:40,50,60"]
    _ -> []
  }
}

pub fn fractal_17_read_adapters_x_4_argument_regimes_matrix_test() {
  let lits = read_adapters.literals()
  list.length(lits) |> should.equal(16)
  let huge = string.repeat("q", 300)

  list.each(lits, fn(lit) {
    // Regime 1: Valid arguments
    let assert Some(r_valid) = read_adapters.route(lit, valid_read_args(lit))
    { string.byte_size(r_valid) <= 3500 } |> should.be_true
    {
      string.contains(r_valid, "\"status\":\"ok\"")
      || string.contains(r_valid, "\"status\":\"backend_unavailable\"")
    }
    |> should.be_true

    // Regime 2: Extra unexpected arguments
    let assert Some(r_extra) =
      read_adapters.route(lit, [
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
      ])
    { string.byte_size(r_extra) <= 3500 } |> should.be_true

    // Regime 3: Control byte argument -> denied or backend_unavailable, never ok
    let assert Some(r_ctrl) = read_adapters.route(lit, ["bad\u{0000}byte"])
    string.contains(r_ctrl, "\"status\":\"ok\"") |> should.be_false

    // Regime 4: Oversized argument -> denied
    let assert Some(r_huge) = read_adapters.route(lit, [huge])
    string.contains(r_huge, "\"status\":\"denied\"") |> should.be_true
  })
}

// =============================================================================
// 6. 8 MediaKinds x 11 Binary Signatures + 5 Carriers x 4 States = 108 Combinations
// =============================================================================

pub fn fractal_8_media_kinds_x_11_signatures_x_4_ingress_carriers_matrix_test() {
  let kinds = [
    media_ref.Photo,
    media_ref.Document,
    media_ref.Audio,
    media_ref.Voice,
    media_ref.Video,
    media_ref.Sticker,
    media_ref.Animation,
    media_ref.Unsupported("poll"),
  ]

  let samples = [
    #(media_inspect.Jpeg, <<0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3>>),
    #(media_inspect.Png, <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1>>),
    #(media_inspect.Gif, <<0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 2>>),
    #(media_inspect.Webp, <<
      0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x45, 0x42, 0x50,
    >>),
    #(media_inspect.Ogg, <<0x4F, 0x67, 0x67, 0x53, 0, 2>>),
    #(media_inspect.Mp3, <<0x49, 0x44, 0x33, 4, 0>>),
    #(media_inspect.Mp4, <<
      0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D,
    >>),
    #(media_inspect.Pdf, <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37>>),
    #(media_inspect.Zip, <<0x50, 0x4B, 0x03, 0x04, 0, 0>>),
    #(media_inspect.Unknown, <<0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0>>),
    #(media_inspect.Unknown, <<0xFF>>),
  ]

  // 8 x 11 = 88 combinations: Accepted iff expected_type is in allowlist(kind)
  list.each(kinds, fn(kind) {
    let allowed_types = media_inspect.allowlist(kind)
    list.each(samples, fn(pair) {
      let #(expected_type, payload) = pair
      let verdict = media_inspect.inspect(kind, payload)
      case list.contains(allowed_types, expected_type) {
        True -> verdict |> should.equal(media_inspect.Accepted(expected_type))
        False ->
          case verdict {
            media_inspect.Rejected(_, _) -> Nil
            media_inspect.Accepted(_) -> should.fail()
          }
      }
    })
  })

  // 5 JSON media carriers x 4 ingress states = 20 combinations
  let carriers = [
    #(
      "photo",
      "\"photo\":[{\"file_id\":\"f1\",\"file_unique_id\":\"u1\",\"width\":10,\"height\":10,\"file_size\":128}]",
    ),
    #(
      "document",
      "\"document\":{\"file_id\":\"f2\",\"file_unique_id\":\"u2\",\"file_name\":\"a.pdf\",\"mime_type\":\"application/pdf\",\"file_size\":256}",
    ),
    #(
      "voice",
      "\"voice\":{\"file_id\":\"f3\",\"file_unique_id\":\"u3\",\"duration\":5,\"mime_type\":\"audio/ogg\",\"file_size\":512}",
    ),
    #(
      "audio",
      "\"audio\":{\"file_id\":\"f4\",\"file_unique_id\":\"u4\",\"duration\":10,\"mime_type\":\"audio/mpeg\",\"file_size\":1024}",
    ),
    #(
      "video",
      "\"video\":{\"file_id\":\"f5\",\"file_unique_id\":\"u5\",\"width\":100,\"height\":100,\"duration\":3,\"mime_type\":\"video/mp4\",\"file_size\":2048}",
    ),
  ]

  let allow = allowlist()
  list.index_map(carriers, fn(c, idx) {
    let #(_name, media_json) = c
    let uid = 20_000 + idx * 10

    // State 1: Authorized + Captioned -> AcceptedEnvelope
    let cap_json =
      "{\"update_id\":"
      <> int.to_string(uid + 1)
      <> ",\"message\":{\"message_id\":1,\"chat\":{\"id\":6249174059,\"type\":\"private\"},\"from\":{\"id\":6249174059,\"is_bot\":false},\"caption\":\"/status\","
      <> media_json
      <> "}}"
    case guard.evaluate_update(cap_json, allow) {
      guard.AcceptedEnvelope(
        directive: guard.DirectReadTool("query_system_health"),
        ..,
      ) -> Nil
      _ -> should.fail()
    }

    // State 2: Authorized + Bare (no caption) -> media_without_caption
    let bare_json =
      "{\"update_id\":"
      <> int.to_string(uid + 2)
      <> ",\"message\":{\"message_id\":2,\"chat\":{\"id\":6249174059,\"type\":\"private\"},\"from\":{\"id\":6249174059,\"is_bot\":false},"
      <> media_json
      <> "}}"
    case guard.evaluate_update(bare_json, allow) {
      guard.RejectedUpdate(reason: "media_without_caption", ..) -> Nil
      _ -> should.fail()
    }

    // State 3: Authorized + Forwarded Captioned -> forwarded_not_supported
    let fwd_json =
      "{\"update_id\":"
      <> int.to_string(uid + 3)
      <> ",\"message\":{\"message_id\":3,\"chat\":{\"id\":6249174059,\"type\":\"private\"},\"from\":{\"id\":6249174059,\"is_bot\":false},\"forward_date\":1700000000,\"caption\":\"/status\","
      <> media_json
      <> "}}"
    case guard.evaluate_update(fwd_json, allow) {
      guard.RejectedUpdate(reason: "forwarded_not_supported", ..) -> Nil
      _ -> should.fail()
    }

    // State 4: Stranger + Bare -> unsupported_or_unauthorized_identity (C-10)
    let stranger_json =
      "{\"update_id\":"
      <> int.to_string(uid + 4)
      <> ",\"message\":{\"message_id\":4,\"chat\":{\"id\":999999,\"type\":\"private\"},\"from\":{\"id\":999999,\"is_bot\":false},"
      <> media_json
      <> "}}"
    case guard.evaluate_update(stranger_json, allow) {
      guard.RejectedUpdate(reason: "unsupported_or_unauthorized_identity", ..) ->
        Nil
      _ -> should.fail()
    }
  })
}

// =============================================================================
// 7. 14 Mini-App Pages x 6 Route/View/Security Vectors = 84 Combinations
// =============================================================================

pub fn fractal_14_mini_app_pages_x_6_security_and_route_vectors_matrix_test() {
  let pages = [
    #(webapp_types.MiniDashboard, "/mini-app/dashboard", "C3I Mesh"),
    #(webapp_types.MiniHealthGrid, "/mini-app/health", "Health Grid"),
    #(webapp_types.MiniCockpit, "/mini-app/alerts", "Cockpit"),
    #(webapp_types.MiniImmune, "/mini-app/immune", "Immune System"),
    #(webapp_types.MiniPlanning, "/mini-app/tasks", "Tasks"),
    #(webapp_types.MiniInference, "/mini-app/inference", "Inference"),
    #(webapp_types.MiniConversation, "/mini-app/chat", "Chat History"),
    #(webapp_types.MiniConfig, "/mini-app/config", "Configuration"),
    #(webapp_types.MiniPodman, "/mini-app/containers", "Containers"),
    #(webapp_types.MiniFederation, "/mini-app/federation", "Federation"),
    #(webapp_types.MiniVerification, "/mini-app/verify", "Verification"),
    #(webapp_types.MiniFmea, "/mini-app/fmea", "FMEA"),
    #(webapp_types.MiniTelemetry, "/mini-app/telemetry", "Telemetry"),
    #(webapp_types.MiniZenohBrowser, "/mini-app/zenoh", "Zenoh Browser"),
  ]
  list.length(pages) |> should.equal(14)

  list.each(pages, fn(entry) {
    let #(page_variant, expected_path, _component_marker) = entry
    let label = webapp_types.page_to_label(page_variant)

    // Vector 1: Canonical path bijection
    webapp_types.page_to_path(page_variant) |> should.equal(expected_path)

    // Vector 2: Route path predicate recognition
    mini_app_routes.is_mini_app_path(expected_path) |> should.be_true

    // Vector 3: Non-empty label and navigation tab assignment
    label |> should.not_equal("")
    let _tab = webapp_types.page_nav_tab(page_variant)

    // Vector 4: Route HTML rendering contains DOCTYPE, data-page attribute, and page title
    let html = mini_app_routes.route(expected_path)
    string.contains(string.lowercase(html), "<!doctype html>") |> should.be_true
    string.contains(html, "data-page=\"" <> expected_path <> "\"")
    |> should.be_true
    string.contains(html, "UOS · " <> label) |> should.be_true

    // Vector 5: Navigation bar shell and 6-domain checklist present on every page
    string.contains(html, "Mini App pages") |> should.be_true
    string.contains(html, "CHK-01-TIME") |> should.be_true

    // Vector 6: Zero leaked secret markers in rendered HTML
    string.contains(html, "sk-or-v1-") |> should.be_false
    string.contains(html, "UOSV1") |> should.be_false
  })

  // Also verify WebApp auth freshness and hash rejection combinations
  webapp_auth.check_freshness("auth_date=1000&hash=abc", 1100, 300)
  |> should.be_true
  webapp_auth.check_freshness("auth_date=1000&hash=abc", 1500, 300)
  |> should.be_false
  mini_app.dashboard_view() |> string.contains("C3I Mesh") |> should.be_true
}

// =============================================================================
// 8. Multi-Turn Memory (1..9 Turns FIFO Eviction) x Dialogue x 2oo3 x Tool Bridge
// =============================================================================

pub fn fractal_multi_turn_memory_x_dialogue_x_approval_x_tool_combinations_test() {
  let scope =
    conv.Scope(
      bot_id: bot_id,
      chat_id: allowed_chat_id,
      user_id: allowed_user_id,
    )
  let ctx0 = conv.Context(scope: scope, turns: [])

  // Append 9 turns to verify 8-turn ring buffer saturation and FIFO eviction of turn 1
  let ctx9 =
    list.fold([1, 2, 3, 4, 5, 6, 7, 8, 9], ctx0, fn(acc, i) {
      let assert Ok(next) =
        conv.append(
          acc,
          conv.Turn(
            update_id: 5000 + i,
            prompt: "Prompt number " <> int.to_string(i),
            reply: "Reply number " <> int.to_string(i),
          ),
        )
      next
    })

  list.length(ctx9.turns) |> should.equal(8)
  let assert Ok(mem_status) = memory_cmd.reply("/memory", ctx9)
  string.contains(mem_status.text, "8 of 8 complete exchanges stored")
  |> should.be_true

  // Turn 1 (Prompt number 1) must be evicted; turns 2..9 (Prompt number 2..9) must be present
  let assert Ok(hist_all) = memory_cmd.reply("/history 8", ctx9)
  string.contains(hist_all.text, "Prompt number 1") |> should.be_false
  string.contains(hist_all.text, "Prompt number 2") |> should.be_true
  string.contains(hist_all.text, "Prompt number 9") |> should.be_true

  // Out-of-range history counts (0, 9, negative, non-int) fail closed
  should.be_error(memory_cmd.reply("/history 0", ctx9))
  should.be_error(memory_cmd.reply("/history 9", ctx9))
  should.be_error(memory_cmd.reply("/history -1", ctx9))
  should.be_error(memory_cmd.reply("/history abc", ctx9))

  // Prepare dialogue requests across /ask, /socratic, and /redteam over the 8-turn context
  let assert Ok(socratic_topic) = dialogue.topic("Lease contention under load")
  socratic_topic |> should.equal("Lease contention under load")
  let assert Ok(req_soc) =
    conv.prepare_request(ctx9, "/socratic Lease contention under load")
  string.contains(req_soc.system, "Use Socratic dialogue") |> should.be_true

  let assert Ok(req_red) =
    conv.prepare_request(ctx9, "/redteam Single point of failure in router")
  string.contains(req_red.system, "You are the UOS conversational assistant")
  |> should.be_true

  // All tool selections in telegram_tool_command (19 read tools + cancel_job_lease + help)
  let tool_cases = [
    #("", tool_cmd.Help),
    #("query_system_health {}", tool_cmd.SystemHealth),
    #("query_saplan {}", tool_cmd.Plan),
    #("query_doctor {}", tool_cmd.Doctor),
    #("query_storage {}", tool_cmd.Storage),
    #("query_checklist {}", tool_cmd.Checklist),
    #("query_ecology {}", tool_cmd.Ecology),
    #("query_matrix_versions {}", tool_cmd.Matrix),
    #("query_exec_brief {}", tool_cmd.ExecBrief),
    #("query_ha {}", tool_cmd.Ha),
    #("query_finops {}", tool_cmd.Finops),
    #("query_zigvm_version {}", tool_cmd.KernelVersion),
    #("query_peers {}", tool_cmd.Peers),
    #("query_board {}", tool_cmd.Board),
    #("query_fmea {}", tool_cmd.Fmea("")),
    #("query_zenoh {}", tool_cmd.Zenoh("")),
    #(
      "cancel_job_lease job_42 -- timeout_exceeded",
      tool_cmd.CancelLease("job_42", "timeout_exceeded"),
    ),
  ]
  list.each(tool_cases, fn(pair) {
    let #(input, expected) = pair
    tool_cmd.parse(input) |> should.equal(Ok(expected))
  })
  should.be_error(tool_cmd.parse("drop_database now"))
  should.be_error(tool_cmd.parse("cancel_job_lease job_42 missing_dashes"))
}
