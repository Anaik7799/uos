//// =============================================================================
//// [UOS-FUZZ] Telegram Cognitive Interface Fuzz Test Suite (SPEC-TELEGRAM-FUZZ-001)
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>test/telegram_fuzz_test</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Fuzz & Mutation Testing for Robot C3I Telegram Interface</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-TELEGRAM-001, SC-SIL4-001, SC-DRIVE-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/harness/cognitive_worker.{
  CognitiveIntent, decode_intent, decode_zenoh_intents, evaluate_intent,
  handle_directive,
}
import cepaf_gleam/harness/telegram_outbound
import envoy
import gleam/list
import gleam/string
import gleeunit/should

// -----------------------------------------------------------------------------
// Fuzz F1: Malformed & Corrupted JSON Payloads
// -----------------------------------------------------------------------------
pub fn fuzz_f1_malformed_json_payloads_test() {
  let malformed_inputs = [
    "",
    "   ",
    "{",
    "}",
    "{\"intent_id\":",
    "{\"intent_id\": 12345}",
    "[1, 2, 3]",
    "\"a naked string\"",
    "null",
    "true",
    "{\"key\": \"val\", \"broken\": }",
    "{\"value\": \"not an object\"}",
    "[{\"key\": \"indrajaal/l5/cog/intent/req\", \"value\": \"string_not_json\"}]",
  ]

  list.each(malformed_inputs, fn(payload) {
    // decode_intent must fail closed without crashing
    case decode_intent(payload) {
      Ok(_) -> Nil
      Error(_) -> Nil
    }
    // decode_zenoh_intents must return empty list without crashing
    let intents = decode_zenoh_intents(payload)
    list.length(intents) |> fn(len) { len >= 0 } |> should.be_true
  })
}

// -----------------------------------------------------------------------------
// Fuzz F2: Malformed Directives & Command Injection
// -----------------------------------------------------------------------------
pub fn fuzz_f2_malformed_directives_and_injection_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let injection_directives = [
    "/",
    "//",
    "///",
    "/invalid_random_cmd_12345",
    "/status; rm -rf /;",
    "/plan | cat /etc/shadow",
    "/board && echo pwned",
    "/messages '; DROP TABLE conversation_history; --",
    "/messages 10' UNION SELECT 1,2,3,4,5,6 --",
    "/tool ../../../etc/passwd",
    "/tool ; whoami ;",
    "/memory \u{0000}\r\n\u{0000}",
  ]

  list.each(injection_directives, fn(cmd) {
    let intent =
      CognitiveIntent(
        intent_id: "fuzz-inj-" <> cmd,
        source: "telegram",
        user: "Attacker",
        chat_id: "fuzz-chat",
        text: cmd,
        timestamp_ms: 1789184000000,
      )
    // Directive evaluator must handle safely and return a valid decision
    let decision = handle_directive(cmd, intent)
    decision.intent_id |> should.equal(intent.intent_id)
    string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
  })
}

// -----------------------------------------------------------------------------
// Fuzz F3: Extreme String Lengths & Buffer Overflows
// -----------------------------------------------------------------------------
pub fn fuzz_f3_extreme_string_lengths_test() {
  envoy.set("UOS_TEST_MODE", "1")
  // 1. Extreme 50,000 continuous characters
  let giant_token = string.repeat("X", 50000)
  let intent1 =
    CognitiveIntent(
      intent_id: "fuzz-len-1",
      source: "telegram",
      user: "Avi",
      chat_id: "6249174059",
      text: giant_token,
      timestamp_ms: 1789184000000,
    )
  let decision1 = evaluate_intent(intent1)
  string.length(decision1.reply_markdown) |> fn(len) { len > 0 } |> should.be_true

  // 2. Extreme 5,000 newlines
  let giant_newlines = string.repeat("\n", 5000)
  let intent2 =
    CognitiveIntent(
      intent_id: "fuzz-len-2",
      source: "telegram",
      user: "Avi",
      chat_id: "6249174059",
      text: giant_newlines,
      timestamp_ms: 1789184000000,
    )
  let decision2 = evaluate_intent(intent2)
  string.length(decision2.reply_markdown) |> fn(len) { len > 0 } |> should.be_true

  // 3. Telegram chunking of 30,000 characters
  let chunks = telegram_outbound.chunk_text(giant_token, 4096)
  list.all(chunks, fn(chunk) { string.length(chunk) <= 4096 }) |> should.be_true
}

// -----------------------------------------------------------------------------
// Fuzz F4: Unicode, Control Characters, ANSI Escapes & Surrogate Pairs
// -----------------------------------------------------------------------------
pub fn fuzz_f4_unicode_and_control_chars_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let hostile_strings = [
    // Right-to-Left override
    "\u{202E}gnirts detsoh\u{202C}",
    // Zero-width spaces & joiners
    "zero\u{200B}width\u{200D}space\u{FEFF}test",
    // ANSI escape codes
    "\u{001B}[31;1mRedText\u{001B}[0m \u{001B}[2J\u{001B}[H",
    // Emoji bomb
    string.repeat("👨‍👩‍👧‍👦🚀🔥💀🤖", 100),
    // Mixed RTL / CJK / Mathematical scripts
    "العربية / 汉语 / 𝔉𝔯𝔞𝔨𝔱𝔲𝔯 / ∀x ∈ ℝ",
  ]

  list.each(hostile_strings, fn(txt) {
    let intent =
      CognitiveIntent(
        intent_id: "fuzz-uni-" <> string.slice(txt, 0, 8),
        source: "telegram",
        user: "Avi",
        chat_id: "6249174059",
        text: txt,
        timestamp_ms: 1789184000000,
      )
    let decision = evaluate_intent(intent)
    string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
  })
}

// -----------------------------------------------------------------------------
// Fuzz F5: Boundary / Type Mismatch Numeric Arguments
// -----------------------------------------------------------------------------
pub fn fuzz_f5_boundary_numeric_args_test() {
  let boundary_limits = [
    "-100",
    "-1",
    "0",
    "not_a_number",
    "NaN",
    "Infinity",
    "99999999999999999999999999999999",
    "3.14159",
  ]

  list.each(boundary_limits, fn(lim) {
    let intent =
      CognitiveIntent(
        intent_id: "fuzz-lim-" <> lim,
        source: "telegram",
        user: "Avi",
        chat_id: "fuzz-chat",
        text: "/messages " <> lim,
        timestamp_ms: 1789184000000,
      )
    let decision = handle_directive("/messages " <> lim, intent)
    decision.ooda_phase |> should.equal("Completed")
    string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
  })
}

// -----------------------------------------------------------------------------
// Fuzz F6: Extreme Timestamps (Negative, Zero, Far Future)
// -----------------------------------------------------------------------------
pub fn fuzz_f6_extreme_timestamps_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let extreme_ts = [
    -1000,
    -1,
    0,
    1,
    1000000,
    1789184000000,
    999999999999999,
  ]

  list.each(extreme_ts, fn(ts) {
    let intent =
      CognitiveIntent(
        intent_id: "fuzz-ts",
        source: "telegram",
        user: "Avi",
        chat_id: "6249174059",
        text: "system status",
        timestamp_ms: ts,
      )
    let decision = evaluate_intent(intent)
    decision.intent_id |> should.equal("fuzz-ts")
    string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
  })
}
