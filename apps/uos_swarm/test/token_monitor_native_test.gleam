import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import uos_swarm/token_monitor_native as n

pub fn pending_and_multiresponse_pi_usage_is_unknown_test() {
  n.parse(
    "pi_sdk",
    "openrouter",
    "id",
    "pi",
    "deepseek",
    "{\"assistant_starts\":2,\"tool_executions\":0,\"settled\":null,\"result\":{\"stopReason\":\"pending\",\"usage\":{\"input\":1,\"output\":2,\"cacheRead\":3,\"cacheWrite\":4,\"totalTokens\":10}}}",
  )
  |> should.equal(Error("nonfinal_or_multiresponse_pi_receipt"))
}

pub fn native_invocation_identity_mismatch_refused_test() {
  n.parse(
    "claude_cli",
    "claude",
    "other",
    "claude",
    "mixed",
    "{\"type\":\"result\",\"session_id\":\"actual\"}",
  )
  |> should.equal(Error("native_invocation_id_mismatch"))
}

fn pi(raw: String) {
  let final =
    string.replace(
      raw,
      "{\"result\":",
      "{\"assistant_starts\":1,\"tool_executions\":0,\"settled\":{\"type\":\"agent_settled\",\"aborted\":false},\"result\":",
    )
  n.parse("pi_sdk", "openrouter", "request-1", "pi", "deepseek", final)
}

pub fn native_pi_distinct_input_classes_test() {
  let assert Ok(r) =
    pi(
      "{\"result\":{\"stopReason\":\"stop\",\"usage\":{\"input\":10,\"output\":20,\"cacheRead\":30,\"cacheWrite\":40,\"reasoning\":5,\"totalTokens\":100,\"cost\":{\"total\":0.001}}}}",
    )
  let assert Some(u) = r.usage
  u.input_tokens |> should.equal(10)
  u.cache_read |> should.equal(30)
  r.reasoning_tokens |> should.equal(Some(5))
  r.estimated_nanodollars |> should.equal(Some(1_000_000))
}

pub fn native_claude_does_not_add_model_usage_test() {
  let assert Ok(r) =
    n.parse(
      "claude_cli",
      "claude",
      "session-1",
      "claude",
      "mixed",
      "{\"type\":\"result\",\"session_id\":\"session-1\",\"is_error\":true,\"total_cost_usd\":2,\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"cache_read_input_tokens\":3,\"cache_creation_input_tokens\":4},\"modelUsage\":{\"x\":{\"inputTokens\":999999}}}",
    )
  let assert Some(u) = r.usage
  u.input_tokens |> should.equal(1)
  r.failed |> should.equal(True)
  r.reasoning_tokens |> should.equal(None)
  r.estimated_nanodollars |> should.equal(Some(2_000_000_000))
}

pub fn deepseek_cache_is_subset_not_additional_test() {
  let assert Ok(r) =
    n.parse(
      "deepseek_chat",
      "deepseek",
      "id",
      "pi",
      "deepseek",
      "{\"id\":\"id\",\"object\":\"chat.completion\",\"usage\":{\"prompt_tokens\":70,\"completion_tokens\":30,\"prompt_cache_hit_tokens\":50,\"prompt_cache_miss_tokens\":20,\"total_tokens\":100,\"completion_tokens_details\":{\"reasoning_tokens\":10}}}",
    )
  let assert Some(u) = r.usage
  u.input_tokens |> should.equal(20)
  u.cache_read |> should.equal(50)
  u.output_tokens |> should.equal(30)
}

pub fn inconsistent_totals_refuse_test() {
  pi(
    "{\"result\":{\"stopReason\":\"stop\",\"usage\":{\"input\":10,\"output\":20,\"cacheRead\":30,\"cacheWrite\":40,\"totalTokens\":105}}}",
  )
  |> should.equal(Error("inconsistent_total"))
}

pub fn missing_cache_usage_is_unknown_test() {
  pi(
    "{\"result\":{\"stopReason\":\"error\",\"usage\":{\"input\":10,\"output\":20}}}",
  )
  |> should.equal(Error("unknown_usage_schema"))
}

pub fn duplicate_keys_and_nonfinite_refuse_test() {
  pi("{\"result\":{},\"result\":{}}")
  |> should.equal(Error("invalid_raw_receipt_json"))
  pi("{\"x\":NaN}") |> should.equal(Error("invalid_raw_receipt_json"))
}

fn agy_receipt(raw: String) {
  n.parse(
    "agy_cli",
    "antigravity",
    "conversation-1",
    "agy",
    "gemini-4-argon-medium",
    raw,
  )
}

fn agy_sample() {
  "{\"conversation_id\":\"conversation-1\",\"status\":\"SUCCESS\",\"num_turns\":1,\"usage\":{\"input_tokens\":33735,\"output_tokens\":581,\"thinking_tokens\":0,\"cache_read_tokens\":0,\"total_tokens\":34316}}"
}

pub fn native_agy_observed_usage_has_unknown_cost_test() {
  let assert Ok(r) = agy_receipt(agy_sample())
  let assert Some(u) = r.usage
  u.input_tokens |> should.equal(33_735)
  u.output_tokens |> should.equal(581)
  r.reasoning_tokens |> should.equal(Some(0))
  r.estimated_nanodollars |> should.equal(None)
  r.failed |> should.equal(False)
}

pub fn native_agy_identity_and_terminal_controls_test() {
  agy_receipt(string.replace(agy_sample(), "conversation-1", "other"))
  |> should.equal(Error("nonfinal_or_mismatched_agy_receipt"))
  agy_receipt(string.replace(agy_sample(), "SUCCESS", "RUNNING"))
  |> should.equal(Error("nonfinal_or_mismatched_agy_receipt"))
  agy_receipt(string.replace(agy_sample(), "\"num_turns\":1", "\"num_turns\":2"))
  |> should.equal(Error("nonfinal_or_mismatched_agy_receipt"))
}

pub fn native_agy_duplicate_and_warning_prefix_refused_test() {
  agy_receipt(string.replace(
    agy_sample(),
    "\"status\":\"SUCCESS\"",
    "\"status\":\"SUCCESS\",\"status\":\"SUCCESS\"",
  ))
  |> should.equal(Error("invalid_raw_receipt_json"))
  agy_receipt("warning: unexpected prefix\n" <> agy_sample())
  |> should.equal(Error("invalid_raw_receipt_json"))
}

pub fn native_agy_inconsistent_total_refused_test() {
  agy_receipt(string.replace(agy_sample(), "34316", "34317"))
  |> should.equal(Error("inconsistent_total"))
}

pub fn native_agy_unknown_cache_and_thinking_overlap_not_guessed_test() {
  let assert Error(_) =
    agy_receipt(string.replace(
      agy_sample(),
      "\"cache_read_tokens\":0",
      "\"cache_read_tokens\":10",
    ))
  let assert Error(_) =
    agy_receipt(string.replace(
      agy_sample(),
      "\"thinking_tokens\":0",
      "\"thinking_tokens\":10",
    ))
}

pub fn native_agy_missing_or_negative_counts_refused_test() {
  let assert Error(_) =
    agy_receipt(string.replace(agy_sample(), "\"input_tokens\":33735,", ""))
  let assert Error(_) = agy_receipt(string.replace(agy_sample(), "33735", "-1"))
}
