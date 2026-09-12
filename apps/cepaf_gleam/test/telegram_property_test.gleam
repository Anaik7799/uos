//// =============================================================================
//// [UOS-PROP] Telegram Cognitive Interface Property Test Suite (SPEC-TELEGRAM-PROP-001)
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>test/telegram_property_test</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Universally Quantified Properties for Robot C3I Telegram Interface</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-TELEGRAM-001, SC-SIL4-001, SC-DRIVE-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/harness/cognitive_worker.{
  CognitiveIntent, decode_intent, evaluate_intent,
  extract_directives_from_response, format_recent_telegram_history,
  strip_directive_lines,
}
import cepaf_gleam/harness/conversation_memory.{ChatMessage}
import cepaf_gleam/harness/egress_redactor
import cepaf_gleam/harness/telegram_outbound
import envoy
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

// -----------------------------------------------------------------------------
// Property P1: Turn Deduplication Idempotence
// dedup(dedup(L)) == dedup(L) AND dedup(M repeated k times) == 1
// -----------------------------------------------------------------------------
pub fn property_p1_turn_deduplication_idempotence_test() {
  let repetitions = [1, 2, 3, 5, 10, 20]
  list.each(repetitions, fn(k) {
    let raw_msgs =
      list.repeat(ChatMessage("user", "query-" <> int.to_string(k), 1789184000000), k)
    let formatted = format_recent_telegram_history(raw_msgs, 10)
    // Regardless of how many duplicates, exactly 1 turn is rendered
    formatted |> string.contains("Last 1 turns") |> should.be_true
  })
}

// -----------------------------------------------------------------------------
// Property P2: Hardware OS NVMe Zero-Leak Invariant
// forall s in strings with denied serial, redact(s) does not contain denied serial
// -----------------------------------------------------------------------------
pub fn property_p2_hardware_nvme_zero_leak_invariant_test() {
  let denied_serial = egress_redactor.denied_os_nvme_serial
  let test_cases = [
    denied_serial,
    "prefix_" <> denied_serial,
    denied_serial <> "_suffix",
    "before " <> denied_serial <> " middle " <> denied_serial <> " after",
    string.repeat(denied_serial <> " ", 50),
    "{\"disk\": \"" <> denied_serial <> "\"}",
  ]

  list.each(test_cases, fn(input) {
    let redacted = egress_redactor.redact_system_secrets(input)
    redacted |> string.contains(denied_serial) |> should.be_false
    redacted |> string.contains(egress_redactor.redacted_serial_placeholder) |> should.be_true
  })
}

// -----------------------------------------------------------------------------
// Property P3: Telegram Chunk Length Bound Invariant
// forall s of length L, forall c in chunk_text(s, 4096), length(c) <= 4096
// -----------------------------------------------------------------------------
pub fn property_p3_chunk_length_bound_invariant_test() {
  let lengths = [0, 1, 10, 100, 4095, 4096, 4097, 8192, 12288, 20000]
  list.each(lengths, fn(len) {
    let s = string.repeat("A", len)
    let chunks = telegram_outbound.chunk_text(s, 4096)
    list.all(chunks, fn(chunk) {
      string.length(chunk) <= 4096
    })
    |> should.be_true
  })
}

// -----------------------------------------------------------------------------
// Property P4: Telegram Chunk Losslessness / Reconstruction Invariant
// forall s, join(chunk_text(s, 4096)) == s
// -----------------------------------------------------------------------------
pub fn property_p4_chunk_reconstruction_lossless_test() {
  let sample_texts = [
    "",
    "Short single-line message.",
    string.repeat("Paragraph line with spaces and words.\n", 120),
    string.repeat("AlphaBetaGammaDelta", 300),
    string.repeat("1234567890\n", 450),
  ]

  list.each(sample_texts, fn(text) {
    let chunks = telegram_outbound.chunk_text(text, 4096)
    let reconstructed = string.join(chunks, "")
    reconstructed |> should.equal(text)
  })
}

// -----------------------------------------------------------------------------
// Property P5: Directive Extraction & Stripping Invariant
// -----------------------------------------------------------------------------
pub fn property_p5_directive_extraction_and_stripping_test() {
  let narrative_lines = [
    "Here is the high-level system analysis.",
    "DIRECTIVE: /status",
    "Next, checking active storage.",
    "DIRECTIVE: /storage",
    "All subsystems verified nominal.",
  ]
  let joined_narrative = string.join(narrative_lines, "\n")

  let extracted = extract_directives_from_response(joined_narrative)
  extracted |> should.equal(["/status", "/storage"])

  let stripped = strip_directive_lines(joined_narrative)
  stripped |> string.contains("DIRECTIVE:") |> should.be_false
  stripped |> string.contains("Here is the high-level system analysis.") |> should.be_true
  stripped |> string.contains("All subsystems verified nominal.") |> should.be_true
}

// -----------------------------------------------------------------------------
// Property P6: CognitiveIntent JSON Decoding Completeness
// -----------------------------------------------------------------------------
pub fn property_p6_intent_json_decoding_completeness_test() {
  let ids = ["intent-1", "intent-999", "cog-alpha", "uuid-78478741"]
  let users = ["Avi", "Operator", "AGY", "AutonomousClient"]

  list.each(ids, fn(id) {
    list.each(users, fn(user) {
      let json_str =
        json.object([
          #("intent_id", json.string(id)),
          #("source", json.string("telegram")),
          #("user", json.string(user)),
          #("chat_id", json.string("6249174059")),
          #("text", json.string("system status")),
          #("timestamp_ms", json.int(1789184000000)),
        ])
        |> json.to_string

      case decode_intent(json_str) {
        Ok(intent) -> {
          intent.intent_id |> should.equal(id)
          intent.user |> should.equal(user)
          intent.chat_id |> should.equal("6249174059")
          intent.text |> should.equal("system status")
        }
        Error(_) -> should.fail()
      }
    })
  })
}

// -----------------------------------------------------------------------------
// Property P7: Confidence Score Boundedness (0.0 <= confidence <= 1.0)
// -----------------------------------------------------------------------------
pub fn property_p7_confidence_score_boundedness_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let queries = [
    "/status",
    "/plan",
    "/storage",
    "/aspects",
    "/peers",
    "/board",
    "/doctor",
    "/checklist",
    "/messages 10",
    "who are you",
    "what does the sovereign cognitive architect do — show processing path",
    "show last 10 telegram messages",
  ]

  list.each(queries, fn(q) {
    let intent =
      CognitiveIntent(
        intent_id: "prop-conf-" <> q,
        source: "telegram",
        user: "Avi",
        chat_id: "6249174059",
        text: q,
        timestamp_ms: 1789184000000,
      )
    let decision = evaluate_intent(intent)
    let valid_conf = decision.confidence >=. 0.0 && decision.confidence <=. 1.0
    valid_conf |> should.be_true
  })
}

// -----------------------------------------------------------------------------
// Property P8: Non-Empty Decision Invariants
// -----------------------------------------------------------------------------
pub fn property_p8_non_empty_decision_invariants_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let test_texts = [
    "status",
    "who are you",
    "what is happening",
    "lean formal proof",
    "acoustic vibration fft",
    "rack-cv vision",
    "/messages",
  ]

  list.each(test_texts, fn(txt) {
    let intent =
      CognitiveIntent(
        intent_id: "prop-inv-" <> txt,
        source: "telegram",
        user: "Avi",
        chat_id: "6249174059",
        text: txt,
        timestamp_ms: 1789184000000,
      )
    let decision = evaluate_intent(intent)
    decision.intent_id |> should.equal(intent.intent_id)
    decision.timestamp_ms |> fn(ts) { ts > 0 } |> should.be_true
    string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
    list.length(decision.actions) |> fn(cnt) { cnt > 0 } |> should.be_true
  })
}
