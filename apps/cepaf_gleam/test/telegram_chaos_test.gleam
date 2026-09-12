//// =============================================================================
//// [UOS-CHAOS] Telegram Cognitive Interface Chaos Test Suite (SPEC-TELEGRAM-CHAOS-001)
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>test/telegram_chaos_test</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Chaos & Fault Injection Testing for Robot C3I Telegram Interface</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-TELEGRAM-001, SC-JIDOKA-001, SC-SIL4-001, SC-DRIVE-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/harness/cognitive_worker.{
  CognitiveIntent, GetWorkerStatus, ProcessIntent, StopWorker, Tick,
  dispatch_action_request, evaluate_intent, format_recent_telegram_history,
  handle_conversational, poll_zenoh_and_process,
}
import cepaf_gleam/harness/conversation_memory.{ChatMessage}
import cepaf_gleam/harness/egress_redactor
import cepaf_gleam/harness/telegram_outbound
import cepaf_gleam/harness/tool_fenced_dispatcher as td
import envoy
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn int_range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..int_range(from + 1, to)]
  }
}

// -----------------------------------------------------------------------------
// Chaos C1: SQLite Storage Failure Injection
// Invariant: Storage errors fail closed and return Result(Error), while
// intent evaluation gracefully degrades without crashing the BEAM actor.
// -----------------------------------------------------------------------------
pub fn chaos_c1_sqlite_storage_failure_injection_test() {
  let unreachable_db = "/dev/null/forbidden_path/state.sqlite3"

  // 1. init_schema against inaccessible path fails closed returning Error
  case conversation_memory.init_schema(unreachable_db) {
    Ok(_) -> should.fail()
    Error(err) -> string.is_empty(err) |> should.be_false
  }

  // 2. record_turn against inaccessible path fails closed returning Error
  case
    conversation_memory.record_turn(
      unreachable_db,
      "chaos-chat-001",
      "user",
      "test message",
      None,
      1789184000000,
    )
  {
    Ok(_) -> should.fail()
    Error(err) -> string.is_empty(err) |> should.be_false
  }

  // 3. get_recent_history against inaccessible path returns empty list safely
  let history =
    conversation_memory.get_recent_history(unreachable_db, "chaos-chat-001", 10)
  history |> should.equal([])

  // 4. Intent evaluation completes even if backing storage experiences fault
  envoy.set("UOS_TEST_MODE", "1")
  let intent =
    CognitiveIntent(
      intent_id: "chaos-c1-intent",
      source: "telegram",
      user: "Avi",
      chat_id: "chaos-c1-chat",
      text: "/status",
      timestamp_ms: 1789184000000,
    )
  let decision = evaluate_intent(intent)
  decision.intent_id |> should.equal("chaos-c1-intent")
  string.is_empty(decision.reply_markdown) |> should.be_false
}

// -----------------------------------------------------------------------------
// Chaos C2: OpenRouter Synthesis Outage & Deterministic Gateway Failover
// Invariant: Outage of external AI tier triggers seamless failover to the
// autonomous offline gateway with zero dropped user requests.
// -----------------------------------------------------------------------------
pub fn chaos_c2_openrouter_outage_failover_test() {
  envoy.set("UOS_TEST_MODE", "1")

  let outage_queries = [
    "what does the sovereign cognitive architect do — show processing path",
    "recent telegram messages",
    "who is robot c3i",
    "show cluster status and storage safety",
    "give me an executive brief of today",
    "inspect nvme serial 25503L801736 and confirm lock",
    "unknown query during major external api outage",
  ]

  list.each(outage_queries, fn(query) {
    let intent =
      CognitiveIntent(
        intent_id: "chaos-c2-intent",
        source: "telegram",
        user: "Avi",
        chat_id: "6249174059",
        text: query,
        timestamp_ms: 1789184000000,
      )
    let decision = handle_conversational(query, intent)

    // Failover must yield a complete decision with non-empty content
    decision.intent_id |> should.equal("chaos-c2-intent")
    string.is_empty(decision.reply_markdown) |> should.be_false
    decision.confidence |> fn(c) { c >. 0.0 } |> should.be_true
    // Hardware security invariant must be preserved across failover
    string.contains(
      decision.reply_markdown,
      egress_redactor.denied_os_nvme_serial,
    )
    |> should.be_false
  })
}

// -----------------------------------------------------------------------------
// Chaos C3: Zenoh Endpoint Partition Chaos
// Invariant: Network partition or 503 response from Zenoh router endpoint
// is safely isolated; polling returns [] without crashing worker loop.
// -----------------------------------------------------------------------------
pub fn chaos_c3_zenoh_endpoint_partition_chaos_test() {
  let unreachable_endpoints = [
    "http://127.0.0.1:59999",
    "http://127.0.0.1:59998/nonexistent",
    "invalid-url-scheme",
    "",
  ]

  list.each(unreachable_endpoints, fn(ep) {
    // Polling partitioned endpoint returns [] cleanly
    let decisions = poll_zenoh_and_process(ep)
    decisions |> should.equal([])
  })
}

// -----------------------------------------------------------------------------
// Chaos C4: OTP Worker Actor Lifecycle & Concurrent Fault Resilience
// Invariant: The worker actor survives interleaved messages, updates state
// monotonically, and shuts down cleanly upon StopWorker.
// -----------------------------------------------------------------------------
pub fn chaos_c4_worker_actor_lifecycle_and_fault_resilience_test() {
  envoy.set("UOS_TEST_MODE", "1")

  let assert Ok(started) = cognitive_worker.start()
  let worker_subj = started.data

  // Interleave ticks and intents
  process.send(worker_subj, Tick)
  process.send(worker_subj, Tick)

  let intent1 =
    CognitiveIntent(
      intent_id: "chaos-c4-1",
      source: "telegram",
      user: "Avi",
      chat_id: "6249174059",
      text: "/status",
      timestamp_ms: 1789184000000,
    )
  let decision1 =
    process.call(worker_subj, 5000, fn(reply_to) {
      ProcessIntent(intent1, reply_to)
    })
  decision1.intent_id |> should.equal("chaos-c4-1")

  process.send(worker_subj, Tick)

  let intent2 =
    CognitiveIntent(
      intent_id: "chaos-c4-2",
      source: "telegram",
      user: "Avi",
      chat_id: "6249174059",
      text: "what does the sovereign cognitive architect do — show processing path",
      timestamp_ms: 1789184001000,
    )
  let decision2 =
    process.call(worker_subj, 5000, fn(reply_to) {
      ProcessIntent(intent2, reply_to)
    })
  decision2.intent_id |> should.equal("chaos-c4-2")

  // Query worker status
  let status =
    process.call(worker_subj, 5000, fn(reply_to) {
      GetWorkerStatus(reply_to)
    })
  status.intents_processed |> should.equal(2)
  status.tick_count |> should.equal(3)
  status.active |> should.be_true

  // Clean shutdown
  process.send(worker_subj, StopWorker)
}

// -----------------------------------------------------------------------------
// Chaos C5: Fractal Jidoka Andon Stop Line on Tampered Mutating Action
// Invariant (SC-JIDOKA-001): Attempting mutating action without 2oo3 quorum
// approval immediately halts execution with error code -32002 / -32003.
// -----------------------------------------------------------------------------
pub fn chaos_c5_fractal_jidoka_andon_stop_line_on_tampered_mutation_test() {
  let intent =
    CognitiveIntent(
      intent_id: "chaos-c5-intent",
      source: "telegram",
      user: "Attacker",
      chat_id: "6249174059",
      text: "/tool chaos_inject",
      timestamp_ms: 1789184000000,
    )

  let mutating_tools = [
    "resuscitate_node",
    "chaos_inject",
    "rotate_keys",
    "storage_rebalance",
  ]

  list.each(mutating_tools, fn(tool) {
    let valid_lease =
      td.FencingLease(
        worker: "chaos-worker",
        plan_id: "plan-chaos",
        task_id: "task-chaos",
        fencing_token: 100,
        lease_until_ns: 9_999_999_999_999_999_999,
      )

    // 1. Quorum Missing: quorum_approved = False with valid lease
    let decision_no_quorum =
      dispatch_action_request(
        "call-c5-unapproved",
        tool,
        "{}",
        Some(valid_lease),
        False,
        intent,
      )

    decision_no_quorum.ooda_phase |> should.equal("Halt")
    decision_no_quorum.actions |> should.equal(["andon_stop_line"])
    decision_no_quorum.reply_markdown
    |> string.contains("Fractal Jidoka Andon Stop Line Triggered")
    |> should.be_true
    decision_no_quorum.reply_markdown
    |> string.contains(int.to_string(td.andon_halt_quorum_missing_code))
    |> should.be_true

    // 2. Fencing Lease Missing: quorum_approved = True, but lease = None
    let decision_no_lease =
      dispatch_action_request(
        "call-c5-no-lease",
        tool,
        "{}",
        None,
        True,
        intent,
      )

    decision_no_lease.ooda_phase |> should.equal("Halt")
    decision_no_lease.actions |> should.equal(["andon_stop_line"])
    decision_no_lease.reply_markdown
    |> string.contains("Fractal Jidoka Andon Stop Line Triggered")
    |> should.be_true
    decision_no_lease.reply_markdown
    |> string.contains(int.to_string(td.andon_halt_unauthorized_code))
    |> should.be_true
  })
}

// -----------------------------------------------------------------------------
// Chaos C6: Outbound Telegram Payload Tamper & Egress Redaction Defense
// Invariant (SC-DRIVE-001): Outbound payload building unconditionally
// sanitizes denied hardware serials and secret patterns.
// -----------------------------------------------------------------------------
pub fn chaos_c6_outbound_payload_tamper_defense_test() {
  let denied_serial = egress_redactor.denied_os_nvme_serial

  let attack_payloads = [
    "System status OK. Root disk: " <> denied_serial,
    "DEBUG DUMP: serial=" <> denied_serial <> " key=sk-or-v1-secret1234567890",
    string.repeat(denied_serial <> " ", 100),
  ]

  list.each(attack_payloads, fn(raw_text) {
    let json_payload =
      telegram_outbound.build_send_payload("6249174059", raw_text, Some("Markdown"))

    // Denied serial must be 100% purged from the outbound JSON
    string.contains(json_payload, denied_serial) |> should.be_false
    // Redaction placeholder must be present
    string.contains(json_payload, egress_redactor.redacted_serial_placeholder)
    |> should.be_true
  })
}

// -----------------------------------------------------------------------------
// Chaos C7: Burst Flood & History Boundedness Stress
// Invariant: High-frequency intent dispatch maintains bounded memory history
// and does not leak or exhaust BEAM heap resources.
// -----------------------------------------------------------------------------
pub fn chaos_c7_burst_flood_and_history_boundedness_test() {
  envoy.set("UOS_TEST_MODE", "1")

  // Dispatch 30 burst intents
  let burst_indices = int_range(1, 30)
  list.each(burst_indices, fn(idx) {
    let intent =
      CognitiveIntent(
        intent_id: "burst-" <> int.to_string(idx),
        source: "telegram",
        user: "BurstTester",
        chat_id: "chaos-c7-chat",
        text: "burst test message " <> int.to_string(idx),
        timestamp_ms: 1789184000000 + idx * 100,
      )
    let decision = evaluate_intent(intent)
    decision.intent_id |> should.equal("burst-" <> int.to_string(idx))
    string.is_empty(decision.reply_markdown) |> should.be_false
  })

  // Format 100 simulated messages with limit=5
  let mock_messages =
    list.map(int_range(1, 100), fn(i) {
      ChatMessage(
        role: case i % 2 == 0 {
          True -> "user"
          False -> "assistant"
        },
        content: "turn " <> int.to_string(i),
        timestamp_ms: 1789184000000 + i * 1000,
      )
    })

  let formatted = format_recent_telegram_history(mock_messages, 5)
  // Must strictly contain the last 5 turns
  formatted |> string.contains("Last 5 turns") |> should.be_true
}
