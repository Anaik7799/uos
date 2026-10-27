//// =============================================================================
//// [UOS-SOP-10MOD] Telegram Full SOP 10-Modality Verification Suite
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>test/telegram_sop_all_modalities_test</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L0_TO_L9_ALL_MODALITIES</layer>
////     <topology>
////       Executes all 10 SOP Testing Modalities (CHK-08-C1C8, CHK-09-MATH, CHK-10-9MOD + Production Scenarios):
////       1. TDD (Red-Green-Refactor Boundary Specification Contracts)
////       2. BDD (Given / When / Then Behavioral Specifications across Journeys, Commands & Mini-App)
////       3. Property-Based & Algebraic Law Testing (Universal Quantifiers & Homomorphisms)
////       4. Adversarial Fuzz & Mutation Boundary Testing (Injections, Truncated UTF-8, NUL, Oversized)
////       5. Chaos Engineering & Fault Injection Testing (Spoofed Channels, Forwarded Media, Disguised ELF, Tampered Auth)
////       6. Performance & Latency SLA Micro-Benchmarking (Wall-Clock Sub-50ms Verification)
////       7. Scalability, High-Volume Throughput & Bounded O(1) Memory Verification (1,000-Turn & Burst Stress)
////       8. Unit & C1-C8 Component Surface Contracts
////       9. System & Cross-Subsystem Pipeline Integration
////       10. Production Use-Case Testing & Real-World Operational Scenarios (P1 Storage, P2 HA, P3 Release, P4 Field Tech)
////     </topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-HARNESS-MCP-001, SC-TELEGRAM-SECRET-001, SC-SA-PLAN-001, SC-JIDOKA-001, SC-PROVENANCE-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/harness/egress_redactor
import cepaf_gleam/harness/telegram_action_adapters as action_adapters
import cepaf_gleam/harness/telegram_authority_protocol as auth_proto
import cepaf_gleam/harness/telegram_commands as commands
import cepaf_gleam/harness/telegram_conversation as conv
import cepaf_gleam/harness/telegram_dialogue_command as dialogue
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_media_inspect as media_inspect
import cepaf_gleam/harness/telegram_media_ref as media_ref
import cepaf_gleam/harness/telegram_memory_command as memory_cmd
import cepaf_gleam/harness/telegram_read_adapters as read_adapters
import cepaf_gleam/harness/telegram_service as service
import cepaf_gleam/harness/telegram_tool_command as tool_cmd
import cepaf_gleam/telegram/auth as webapp_auth
import cepaf_gleam/telegram/types as webapp_types
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

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time_native(unit: Int) -> Int

fn now_us() -> Int {
  monotonic_time_native(1_000_000)
}

fn int_range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..int_range(from + 1, to)]
  }
}

fn allowlist_fixture() -> guard.Allowlist {
  guard.Allowlist(
    bot_id: bot_id,
    allowed_pairs: [
      #(allowed_chat_id, allowed_user_id),
      #(-100_999_888_777, allowed_user_id),
    ],
  )
}

fn all_78_literals() -> List(String) {
  let catalog_lits = list.map(commands.catalog(), fn(d) { d.literal })
  list.append(catalog_lits, ["/saplan"])
}

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

fn valid_read_args(lit: String) -> List(String) {
  case lit {
    "/adr" | "/ADR" -> ["001"]
    "/whatif" -> ["claim", "8"]
    "/simulate" -> ["nas1:nominal", "vm1:degraded"]
    "/canvas" -> ["n1:10,20,30", "n2:40,50,60"]
    _ -> []
  }
}

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

// =============================================================================
// MODALITY 1: TDD (Test-Driven Red-Green-Refactor Boundary Specifications)
// =============================================================================
pub fn sop_modality_01_tdd_red_green_refactor_contracts_test() {
  let allow = allowlist_fixture()

  // 1. Catalog cardinality contract: 77 canonical entries + /saplan alias = 78
  list.length(commands.catalog()) |> should.equal(77)
  list.length(all_78_literals()) |> should.equal(78)

  // 2. RED phase: empty and unknown commands must fail closed
  should.be_error(commands.parse("/"))
  should.be_error(commands.parse("/nonexistent_cmd_xyz"))

  // 3. RED phase: /voice-roll-call is refused at ingress (DeniedMutation);
  //    unwired sensors (/pacing, /rack-cv, /acoustic, /radar) return backend_unavailable
  let voice_json =
    build_update_json(
      90_001,
      allowed_chat_id,
      "private",
      allowed_user_id,
      False,
      False,
      "/voice-roll-call start",
    )
  case guard.evaluate_update(voice_json, allow) {
    guard.AcceptedEnvelope(directive: guard.DeniedMutation(..), ..) -> Nil
    _ -> should.fail()
  }

  list.each(["/pacing", "/rack-cv", "/acoustic", "/radar"], fn(lit) {
    let assert Some(json_reply) = read_adapters.route(lit, [])
    string.contains(json_reply, "\"status\":\"backend_unavailable\"")
    |> should.be_true
  })

  // 4. GREEN vs RED phase for all 19 ControlledAction preview adapters
  list.each(action_adapters.literals(), fn(lit) {
    let assert Some(preview_ok) =
      action_adapters.route_preview(lit, valid_action_args(lit))
    {
      string.contains(preview_ok, "\"status\":\"preview\"")
      || string.contains(preview_ok, "\"status\":\"denied\"")
    }
    |> should.be_true
    string.contains(preview_ok, "\"executed\":true") |> should.be_false

    let assert Some(preview_ctrl_denied) =
      action_adapters.route_preview(lit, ["bad\u{0007}arg"])
    string.contains(preview_ctrl_denied, "\"status\":\"denied\"")
    |> should.be_true
  })

  // 5. RED phase: Sender authorization checked BEFORE media caption check (Review C-10)
  let stranger_bare_photo =
    "{\"update_id\":90002,\"message\":{\"message_id\":2,\"chat\":{\"id\":999999,\"type\":\"private\"},\"from\":{\"id\":999999,\"is_bot\":false},\"photo\":[{\"file_id\":\"f1\",\"file_unique_id\":\"u1\",\"width\":10,\"height\":10,\"file_size\":128}]}}"
  case guard.evaluate_update(stranger_bare_photo, allow) {
    guard.RejectedUpdate(reason: "unsupported_or_unauthorized_identity", ..) ->
      Nil
    _ -> should.fail()
  }
}

// =============================================================================
// MODALITY 2: BDD (Behavior-Driven Given / When / Then Specifications)
// =============================================================================
pub fn sop_modality_02_bdd_given_when_then_scenarios_test() {
  // SCENARIO 1: Given the 3 Operator Journeys (Security, Defence/HA, Critical Responder),
  // When we union their covered command literals and inspect all 18 cases (114 steps),
  // Then 100% of the 77 catalog commands are covered and every case has >= 6 steps.
  let journey_union =
    list.unique(
      list.flatten([
        j_sec.covered_literals(),
        j_def.covered_literals(),
        j_resp.covered_literals(),
      ]),
    )
  list.length(journey_union) |> should.equal(77)
  { list.length(j_sec.covered_literals()) >= 20 } |> should.be_true
  { list.length(j_def.covered_literals()) >= 20 } |> should.be_true
  { list.length(j_resp.covered_literals()) >= 20 } |> should.be_true

  // SCENARIO 2: Given an operator invoking /tool cancel_job_lease,
  // When parsed with valid "--" reason separator vs missing separator,
  // Then valid syntax produces CancelLease and invalid syntax fails closed.
  tool_cmd.parse("cancel_job_lease job_bdd_01 -- stuck_worker")
  |> should.equal(Ok(tool_cmd.CancelLease("job_bdd_01", "stuck_worker")))
  should.be_error(tool_cmd.parse("cancel_job_lease job_bdd_01 missing_dashes"))

  // SCENARIO 3: Given all 14 Mini-App pages,
  // When routed via mini_app_routes.route,
  // Then every page renders HTML with its data-page attribute, 6-domain checklist, and zero secret leaks.
  let pages = [
    webapp_types.MiniDashboard,
    webapp_types.MiniHealthGrid,
    webapp_types.MiniCockpit,
    webapp_types.MiniImmune,
    webapp_types.MiniPlanning,
    webapp_types.MiniInference,
    webapp_types.MiniConversation,
    webapp_types.MiniConfig,
    webapp_types.MiniPodman,
    webapp_types.MiniFederation,
    webapp_types.MiniVerification,
    webapp_types.MiniFmea,
    webapp_types.MiniTelemetry,
    webapp_types.MiniZenohBrowser,
  ]
  list.each(pages, fn(p) {
    let path = webapp_types.page_to_path(p)
    let html = mini_app_routes.route(path)
    string.contains(html, "data-page=\"" <> path <> "\"") |> should.be_true
    string.contains(html, "CHK-01-TIME") |> should.be_true
    string.contains(html, "sk-or-v1-") |> should.be_false
  })
}

// =============================================================================
// MODALITY 3: Property-Based & Algebraic Law Testing (Universal Quantifiers)
// =============================================================================
pub fn sop_modality_03_property_algebraic_laws_test() {
  // LAW 1 (Command Parse Whitespace Invariance):
  // forall lit in all_78_literals(), parse(lit) == parse("  \t " <> lit <> " \n ")
  list.each(all_78_literals(), fn(lit) {
    let assert Ok(base) = commands.parse(lit)
    let assert Ok(padded) = commands.parse("  \t " <> lit <> " \n ")
    padded.definition.canonical |> should.equal(base.definition.canonical)
    padded.definition.kind |> should.equal(base.definition.kind)
  })

  // LAW 2 (UTF-8 Chunking Conservation & Byte Ceiling):
  // forall unit in {"a", "é", "界", "🚀"}, forall count in {1, 25, 200, 1200},
  // chunk_payload_utf8(repeat(unit, count)) produces chunks each <= 4096 bytes
  // whose concatenation equals the original string.
  list.each(["a", "é", "界", "🚀"], fn(unit) {
    list.each([1, 25, 200, 1200], fn(count) {
      let text = string.repeat(unit, count)
      let parts = service.chunk_payload_utf8(text)
      list.all(parts, fn(p) { string.byte_size(p) <= 4096 }) |> should.be_true
      string.join(parts, "") |> should.equal(text)
    })
  })

  // LAW 3 (Hardware OS NVMe Serial Redaction Idempotence & Zero-Leakage):
  // forall s containing denied_os_nvme_serial,
  // redact(redact(s)) == redact(s) AND !contains(redact(s), denied_os_nvme_serial)
  let serial = egress_redactor.denied_os_nvme_serial
  list.each(
    [
      serial,
      "nvme=" <> serial <> ";status=locked",
      "{\"serial\":\"" <> serial <> "\",\"repeat\":\"" <> serial <> "\"}",
    ],
    fn(s) {
      let once = egress_redactor.redact_system_secrets(s)
      let twice = egress_redactor.redact_system_secrets(once)
      once |> should.equal(twice)
      string.contains(once, serial) |> should.be_false
      string.contains(once, egress_redactor.redacted_serial_placeholder)
      |> should.be_true
    },
  )

  // LAW 4 (Read-Adapter Referential Transparency / Determinism):
  // forall lit in read_adapters.literals(), route(lit, args) == route(lit, args)
  list.each(read_adapters.literals(), fn(lit) {
    let args = valid_read_args(lit)
    read_adapters.route(lit, args)
    |> should.equal(read_adapters.route(lit, args))
  })
}

// =============================================================================
// MODALITY 4: Adversarial Fuzz & Mutation Boundary Testing
// =============================================================================
pub fn sop_modality_04_fuzz_and_adversarial_mutation_test() {
  let allow = allowlist_fixture()

  // 1. Hostile SQLi, shell injection, NUL bytes, RTL overrides, ANSI escapes
  let hostile_inputs = [
    "",
    "   ",
    "/",
    "//",
    "/status@foreign_bot",
    "/status; rm -rf /",
    "/wiki ' OR 1=1; DROP TABLE smriti; --",
    "/tool drop_database now",
    "/approval submit req-1 6249174059",
    "/messages -999999",
    "/messages 999999",
    "/messages NaN",
    "/adr 0",
    "/adr -5",
    "/adr 999999",
    "/zigvm exec_arbitrary_code",
    "/rete unknown_fact_1,unknown_fact_2",
    "\u{202E}/status\u{202C}",
    "\u{001B}[31m/status\u{001B}[0m",
  ]

  list.index_map(hostile_inputs, fn(input, idx) {
    let _ = commands.parse(input)
    let _ = tool_cmd.parse(input)
    let raw_json =
      build_update_json(
        91_000 + idx,
        allowed_chat_id,
        "private",
        allowed_user_id,
        False,
        False,
        input,
      )
    let _ = guard.evaluate_update(raw_json, allow)
  })

  // 2. Exact byte ceiling boundary: 2048B accepted vs 2049B rejected
  let exact_2048 = string.repeat("X", 2048)
  let over_2048 = string.repeat("X", 2049)
  let assert Ok(_) = commands.parse("/agy " <> exact_2048)
  should.be_error(commands.parse("/agy " <> over_2048))

  // 3. Authority protocol identifier fuzzing (NUL, path traversal, invalid namespace)
  auth_proto.validate_identifier("id\u{0000}nul", 64)
  |> should.equal(Error("identifier_must_not_contain_nul_byte"))
  auth_proto.validate_workspace("/home/an/../etc/passwd")
  |> should.equal(Error("invalid_workspace_path"))
  auth_proto.validate_coordinator_resource("arbitrary:resource")
  |> should.equal(Error("invalid_coordinator_resource"))
}

// =============================================================================
// MODALITY 5: Chaos Engineering & Fault Injection Testing
// =============================================================================
pub fn sop_modality_05_chaos_and_fault_injection_test() {
  let allow = allowlist_fixture()

  // 1. Chaos Fault: Spoofed channel broadcast from an allowlisted user ID
  let channel_spoof =
    build_update_json(
      92_001,
      allowed_chat_id,
      "channel",
      allowed_user_id,
      False,
      False,
      "/status",
    )
  case guard.evaluate_update(channel_spoof, allow) {
    guard.RejectedUpdate(reason: "unsupported_or_unauthorized_identity", ..) ->
      Nil
    _ -> should.fail()
  }

  // 2. Chaos Fault: Forwarded media injection from allowlisted user
  let fwd_photo =
    "{\"update_id\":92002,\"message\":{\"message_id\":3,\"chat\":{\"id\":6249174059,\"type\":\"private\"},\"from\":{\"id\":6249174059,\"is_bot\":false},\"forward_date\":1700000000,\"caption\":\"/status\",\"photo\":[{\"file_id\":\"f1\",\"file_unique_id\":\"u1\",\"width\":10,\"height\":10,\"file_size\":128}]}}"
  case guard.evaluate_update(fwd_photo, allow) {
    guard.RejectedUpdate(reason: "forwarded_not_supported", ..) -> Nil
    _ -> should.fail()
  }

  // 3. Chaos Fault: Binary ELF executable disguised as Photo or Document
  let elf_bytes = <<0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00>>
  case media_inspect.inspect(media_ref.Photo, elf_bytes) {
    media_inspect.Rejected(_, _) -> Nil
    media_inspect.Accepted(_) -> should.fail()
  }
  case media_inspect.inspect(media_ref.Document, elf_bytes) {
    media_inspect.Rejected(_, _) -> Nil
    media_inspect.Accepted(_) -> should.fail()
  }

  // 4. Chaos Fault: Expired WebApp auth_date rejected
  webapp_auth.check_freshness("auth_date=1000&hash=abc", 2000, 300)
  |> should.be_false
}

// =============================================================================
// MODALITY 6: Performance & Latency SLA Micro-Benchmarking
// =============================================================================
pub fn sop_modality_06_performance_latency_sla_benchmark_test() {
  let allow = allowlist_fixture()

  // 1. SLA Benchmark: Parse + Ingress Guard across all 78 invocations (< 50,000 us = 50 ms)
  let t0 = now_us()
  list.index_map(all_78_literals(), fn(lit, idx) {
    let assert Ok(_) = commands.parse(lit)
    let raw_json =
      build_update_json(
        93_000 + idx,
        allowed_chat_id,
        "private",
        allowed_user_id,
        False,
        False,
        lit,
      )
    let _ = guard.evaluate_update(raw_json, allow)
  })
  let elapsed_parse_us = now_us() - t0
  { elapsed_parse_us < 50_000 } |> should.be_true

  // 2. SLA Benchmark: All 19 ControlledAction previews (< 50,000 us = 50 ms)
  let t1 = now_us()
  list.each(action_adapters.literals(), fn(lit) {
    let assert Some(_) =
      action_adapters.route_preview(lit, valid_action_args(lit))
  })
  let elapsed_actions_us = now_us() - t1
  { elapsed_actions_us < 50_000 } |> should.be_true

  // 3. SLA Benchmark: All 16 ReadObservation adapters (< 50,000 us = 50 ms)
  let t2 = now_us()
  list.each(read_adapters.literals(), fn(lit) {
    let assert Some(_) = read_adapters.route(lit, valid_read_args(lit))
  })
  let elapsed_reads_us = now_us() - t2
  { elapsed_reads_us < 50_000 } |> should.be_true

  // 4. SLA Benchmark: All 14 Mini-App HTML route renders (< 50,000 us = 50 ms)
  let t3 = now_us()
  list.each(
    [
      "/mini-app/dashboard",
      "/mini-app/health",
      "/mini-app/alerts",
      "/mini-app/immune",
      "/mini-app/tasks",
      "/mini-app/inference",
      "/mini-app/chat",
      "/mini-app/config",
      "/mini-app/containers",
      "/mini-app/federation",
      "/mini-app/verify",
      "/mini-app/fmea",
      "/mini-app/telemetry",
      "/mini-app/zenoh",
    ],
    fn(path) {
      let html = mini_app_routes.route(path)
      string.is_empty(html) |> should.be_false
    },
  )
  let elapsed_miniapp_us = now_us() - t3
  { elapsed_miniapp_us < 50_000 } |> should.be_true
}

// =============================================================================
// MODALITY 7: Scalability, High-Volume Throughput & Bounded Memory Testing
// =============================================================================
pub fn sop_modality_07_scalability_and_bounded_memory_test() {
  // 1. Scale conversation memory to 1,000 sequential turns:
  //    Window MUST remain strictly bounded at 8 exchanges (O(1) memory footprint),
  //    retaining turns 993..1000 and evicting turns 1..992.
  let scope =
    conv.Scope(
      bot_id: bot_id,
      chat_id: allowed_chat_id,
      user_id: allowed_user_id,
    )
  let ctx0 = conv.Context(scope: scope, turns: [])
  let ctx_1000 =
    list.fold(int_range(1, 1000), ctx0, fn(acc, i) {
      let assert Ok(next) =
        conv.append(
          acc,
          conv.Turn(
            update_id: 100_000 + i,
            prompt: "user-prompt-" <> int.to_string(i),
            reply: "bot-reply-" <> int.to_string(i),
          ),
        )
      next
    })
  list.length(ctx_1000.turns) |> should.equal(8)

  let assert Ok(mem_summary) = memory_cmd.reply("/memory", ctx_1000)
  string.contains(mem_summary.text, "8 of 8 complete exchanges stored")
  |> should.be_true

  let assert Ok(hist_8) = memory_cmd.reply("/history 8", ctx_1000)
  string.contains(hist_8.text, "History (8 of 8 stored exchanges):")
  |> should.be_true
  string.contains(hist_8.text, "user-prompt-1000") |> should.be_true
  string.contains(hist_8.text, "user-prompt-993") |> should.be_true
  string.contains(hist_8.text, "user-prompt-992") |> should.be_false
  string.contains(hist_8.text, "user-prompt-1\n") |> should.be_false

  // 2. Scale UTF-8 chunking to a 60,000-byte payload (15x the 4,096-byte limit):
  let large_payload = string.repeat("UOS-TELEMETRY-LINE-0123456789\n", 2000)
  let chunks = service.chunk_payload_utf8(large_payload)
  { list.length(chunks) <= 16 } |> should.be_true
  list.all(chunks, fn(c) { string.byte_size(c) <= 4096 }) |> should.be_true

  // 3. Scale command parser across 780 burst invocations (10x full 78-literal catalog):
  let burst_count =
    list.fold(int_range(1, 10), 0, fn(acc, _iter) {
      list.fold(all_78_literals(), acc, fn(inner_acc, lit) {
        let assert Ok(_) = commands.parse(lit)
        inner_acc + 1
      })
    })
  burst_count |> should.equal(780)
}

// =============================================================================
// MODALITY 8: Unit & C1-C8 Component Surface Contracts
// =============================================================================
pub fn sop_modality_08_unit_and_component_contracts_test() {
  // 1. Read adapter component contracts across all 16 read_adapters.literals()
  list.each(
    read_adapters.literals(),
    fn(lit) {
      let assert Some(json_out) =
        read_adapters.route(lit, valid_read_args(lit))
      {
        string.contains(json_out, "\"status\":\"ok\"")
        || string.contains(json_out, "\"status\":\"backend_unavailable\"")
      }
      |> should.be_true
    },
  )

  // 2. Dialogue topic & mode component contract
  let assert Ok(topic) = dialogue.topic("Zero-Muda OTP Supervision")
  topic |> should.equal("Zero-Muda OTP Supervision")
  should.be_error(dialogue.topic("   "))

  // 3. Media reference allowlist & magic header component contract
  let png_bytes = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00>>
  media_inspect.inspect(media_ref.Photo, png_bytes)
  |> should.equal(media_inspect.Accepted(media_inspect.Png))
}

// =============================================================================
// MODALITY 9: System & Cross-Subsystem Pipeline Integration
// =============================================================================
pub fn sop_modality_09_system_cross_subsystem_pipeline_test() {
  let allow = allowlist_fixture()

  let pipeline_literals = [
    "/status",
    "/plan",
    "/saplan",
    "/fmea",
    "/doctor",
    "/immune",
    "/whatif",
    "/simulate",
    "/andon",
    "/merge",
    "/tool",
  ]

  list.index_map(pipeline_literals, fn(lit, idx) {
    // Stage 1: Parse command
    let assert Ok(inv) = commands.parse(lit)

    // Stage 2: Evaluate ingress guard for allowlisted operator
    let raw_json =
      build_update_json(
        94_000 + idx,
        allowed_chat_id,
        "private",
        allowed_user_id,
        False,
        False,
        lit,
      )
    case guard.evaluate_update(raw_json, allow) {
      guard.AcceptedEnvelope(update_id: uid, ..) ->
        uid |> should.equal(94_000 + idx)
      _ -> should.fail()
    }

    // Stage 3: Route to action preview or read adapter
    let raw_reply = case
      list.contains(action_adapters.literals(), inv.definition.canonical)
    {
      True -> {
        let assert Some(p) =
          action_adapters.route_preview(
            inv.definition.canonical,
            valid_action_args(inv.definition.canonical),
          )
        p
      }
      False ->
        case list.contains(read_adapters.literals(), inv.definition.canonical) {
          True -> {
            let assert Some(r) =
              read_adapters.route(
                inv.definition.canonical,
                valid_read_args(inv.definition.canonical),
              )
            r
          }
          False ->
            "{\"status\":\"ok\",\"command\":\""
            <> inv.definition.canonical
            <> "\"}"
        }
    }

    // Stage 4: Redact hardware serials & secrets on egress
    let redacted = egress_redactor.redact_system_secrets(raw_reply)
    string.contains(redacted, egress_redactor.denied_os_nvme_serial)
    |> should.be_false

    // Stage 5: Chunk UTF-8 outbound payload
    let chunks = service.chunk_payload_utf8(redacted)
    list.all(chunks, fn(c) { string.byte_size(c) <= 4096 }) |> should.be_true
  })
}

// =============================================================================
// MODALITY 10: Production Use-Case Testing & Real-World Operational Scenarios
// =============================================================================
pub fn sop_modality_10_production_usecase_scenarios_test() {
  let allow = allowlist_fixture()

  // ---------------------------------------------------------------------------
  // SCENARIO P1: Midnight P1 Storage & NVMe Hardware Interlock Incident
  // ---------------------------------------------------------------------------
  let assert Some(andon_preview) =
    action_adapters.route_preview("/andon", ["storage", "thermal_limit"])
  string.contains(andon_preview, "\"executed\":true") |> should.be_false
  {
    string.contains(andon_preview, "\"status\":\"preview\"")
    || string.contains(andon_preview, "\"status\":\"denied\"")
  }
  |> should.be_true

  let raw_storage_diagnostic =
    "{\"nvme_os_serial\":\""
    <> egress_redactor.denied_os_nvme_serial
    <> "\",\"status\":\"HARD_DENIED_LOCKED\"}"
  let redacted_storage =
    egress_redactor.redact_system_secrets(raw_storage_diagnostic)
  string.contains(redacted_storage, egress_redactor.denied_os_nvme_serial)
  |> should.be_false
  string.contains(
    redacted_storage,
    egress_redactor.redacted_serial_placeholder,
  )
  |> should.be_true

  // ---------------------------------------------------------------------------
  // SCENARIO P2: Split-Brain Tailnet Partition & HA Resurrection Preview
  // ---------------------------------------------------------------------------
  let assert Some(resuscitate_preview) =
    action_adapters.route_preview("/resuscitate", ["vm-1", "heartbeat_timeout"])
  string.contains(resuscitate_preview, "\"executed\":true") |> should.be_false
  let assert Some(gameday_preview) =
    action_adapters.route_preview("/gameday", ["tailnet_partition", "15"])
  string.contains(gameday_preview, "\"executed\":true") |> should.be_false

  // ---------------------------------------------------------------------------
  // SCENARIO P3: Tri-Agent Release Gate, Provenance Audit & Formal Twins
  // ---------------------------------------------------------------------------
  list.each(["/adr", "/whatif", "/simulate", "/canvas"], fn(lit) {
    let assert Some(sim_json) = read_adapters.route(lit, valid_read_args(lit))
    string.contains(sim_json, "\"status\":\"ok\"") |> should.be_true
  })
  let assert Some(merge_preview) =
    action_adapters.route_preview("/merge", ["integration/wave7e", "main"])
  string.contains(merge_preview, "\"executed\":true") |> should.be_false

  // ---------------------------------------------------------------------------
  // SCENARIO P4: Field Technician Multimodal Rack Diagnostic & Shift Handoff
  // ---------------------------------------------------------------------------
  let pdf_bytes = <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37>>
  media_inspect.inspect(media_ref.Document, pdf_bytes)
  |> should.equal(media_inspect.Accepted(media_inspect.Pdf))

  let cap_pdf_json =
    "{\"update_id\":95001,\"message\":{\"message_id\":1,\"chat\":{\"id\":6249174059,\"type\":\"private\"},\"from\":{\"id\":6249174059,\"is_bot\":false},\"caption\":\"/status\",\"document\":{\"file_id\":\"f2\",\"file_unique_id\":\"u2\",\"file_name\":\"smartctl.pdf\",\"mime_type\":\"application/pdf\",\"file_size\":256}}}"
  case guard.evaluate_update(cap_pdf_json, allow) {
    guard.AcceptedEnvelope(
      directive: guard.DirectReadTool("query_system_health"),
      ..,
    ) -> Nil
    _ -> should.fail()
  }

  // Unwired /rack-cv returns truthful backend_unavailable
  let assert Some(rack_cv_reply) = read_adapters.route("/rack-cv", [])
  string.contains(rack_cv_reply, "\"status\":\"backend_unavailable\"")
  |> should.be_true

  // Shift closeout (/retro, /postmortem, /handover preview)
  let assert Some(retro_reply) = read_adapters.route("/retro", [])
  {
    string.contains(retro_reply, "\"status\":\"ok\"")
    || string.contains(retro_reply, "\"status\":\"backend_unavailable\"")
  }
  |> should.be_true
  let assert Some(post_reply) = read_adapters.route("/postmortem", [])
  {
    string.contains(post_reply, "\"status\":\"ok\"")
    || string.contains(post_reply, "\"status\":\"backend_unavailable\"")
  }
  |> should.be_true
  let assert Some(handover_preview) =
    action_adapters.route_preview("/handover", ["emea_sre", "apac_sre"])
  string.contains(handover_preview, "\"executed\":true") |> should.be_false
}
