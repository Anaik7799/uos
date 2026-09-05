/// F15 Log Correlation + F13 OTel Trace Context — 20-test suite
/// Layer: L1_ATOMIC_DEBUG
/// STAMP: SC-LOG-001, SC-OTEL-002, SC-GLM-ZEN-001
/// Ultrathink: Focus #7 (Cryptographic Event Sourcing), #5 (Formal Verification)
///
/// ज्योतिषामपि तज्ज्योतिः — The light of all lights (Gita 13.17)
import cepaf_gleam/ha/correlated_log
import cepaf_gleam/ha/trace_context
import gleam/string
import gleeunit/should

// ===========================================================================
// trace_context: generate_id/1
// ===========================================================================

pub fn generate_id_32_chars_test() {
  trace_context.generate_id(32)
  |> string.length()
  |> should.equal(32)
}

pub fn generate_id_16_chars_test() {
  trace_context.generate_id(16)
  |> string.length()
  |> should.equal(16)
}

pub fn generate_id_is_lowercase_hex_test() {
  let id = trace_context.generate_id(32)
  // All characters must be in 0-9a-f
  id
  |> string.to_graphemes()
  |> list.all(fn(ch) { string.contains("0123456789abcdef", ch) })
  |> should.be_true()
}

pub fn generate_id_two_calls_differ_test() {
  let a = trace_context.generate_id(32)
  let b = trace_context.generate_id(32)
  // Statistically guaranteed to differ with 128-bit entropy
  should.not_equal(a, b)
}

// ===========================================================================
// trace_context: new_trace/2
// ===========================================================================

pub fn new_trace_has_32_char_trace_id_test() {
  trace_context.new_trace("render_planning", "L5")
  |> fn(ctx) { string.length(ctx.trace_id) }
  |> should.equal(32)
}

pub fn new_trace_has_16_char_span_id_test() {
  trace_context.new_trace("nif_plan_status", "L1")
  |> fn(ctx) { string.length(ctx.span_id) }
  |> should.equal(16)
}

pub fn new_trace_has_empty_parent_span_test() {
  trace_context.new_trace("root_op", "L3")
  |> fn(ctx) { ctx.parent_span_id }
  |> should.equal("")
}

pub fn new_trace_stores_operation_test() {
  trace_context.new_trace("ooda_decide", "L5")
  |> fn(ctx) { ctx.operation }
  |> should.equal("ooda_decide")
}

pub fn new_trace_stores_layer_test() {
  trace_context.new_trace("guardian_check", "L0")
  |> fn(ctx) { ctx.layer }
  |> should.equal("L0")
}

pub fn new_trace_start_time_positive_test() {
  trace_context.new_trace("zenoh_pub", "L6")
  |> fn(ctx) { ctx.start_time > 0 }
  |> should.be_true()
}

// ===========================================================================
// trace_context: child_span/3
// ===========================================================================

pub fn child_span_inherits_trace_id_test() {
  let parent = trace_context.new_trace("parent_op", "L5")
  let child = trace_context.child_span(parent, "child_op", "L1")
  child.trace_id
  |> should.equal(parent.trace_id)
}

pub fn child_span_has_different_span_id_test() {
  let parent = trace_context.new_trace("parent_op", "L5")
  let child = trace_context.child_span(parent, "child_op", "L1")
  should.not_equal(child.span_id, parent.span_id)
}

pub fn child_span_parent_span_id_matches_parent_test() {
  let parent = trace_context.new_trace("parent_op", "L5")
  let child = trace_context.child_span(parent, "child_op", "L1")
  child.parent_span_id
  |> should.equal(parent.span_id)
}

pub fn child_span_stores_own_operation_test() {
  let parent = trace_context.new_trace("cortex_decide", "L5")
  let child = trace_context.child_span(parent, "nif_call", "L1")
  child.operation
  |> should.equal("nif_call")
}

// ===========================================================================
// trace_context: formatting
// ===========================================================================

pub fn to_traceparent_format_test() {
  let ctx = trace_context.new_trace("test_op", "L3")
  let tp = trace_context.to_traceparent(ctx)
  // Must start with "00-" and contain exactly 4 segments
  tp
  |> string.starts_with("00-")
  |> should.be_true()
}

pub fn to_traceparent_ends_with_sampled_flag_test() {
  let ctx = trace_context.new_trace("test_op", "L3")
  trace_context.to_traceparent(ctx)
  |> string.ends_with("-01")
  |> should.be_true()
}

pub fn log_prefix_contains_layer_test() {
  let ctx = trace_context.new_trace("immune_scan", "L0")
  trace_context.log_prefix(ctx)
  |> string.contains("L:L0")
  |> should.be_true()
}

pub fn attach_to_json_adds_trace_field_test() {
  let ctx = trace_context.new_trace("render_cockpit", "L5")
  let json = "{\"status\":\"ok\"}"
  trace_context.attach_to_json(ctx, json)
  |> string.contains("_trace")
  |> should.be_true()
}

pub fn attach_to_json_preserves_original_field_test() {
  let ctx = trace_context.new_trace("render_cockpit", "L5")
  let json = "{\"status\":\"ok\"}"
  trace_context.attach_to_json(ctx, json)
  |> string.contains("\"status\":\"ok\"")
  |> should.be_true()
}

pub fn attach_to_json_non_object_unchanged_test() {
  let ctx = trace_context.new_trace("render_cockpit", "L5")
  let not_json = "[1,2,3]"
  trace_context.attach_to_json(ctx, not_json)
  |> should.equal(not_json)
}

// ===========================================================================
// correlated_log: log/3 and formatting
// ===========================================================================

pub fn log_entry_stores_message_test() {
  let ctx = trace_context.new_trace("plan_search", "L3")
  correlated_log.log(correlated_log.Info, "search returned 5 results", ctx)
  |> fn(e) { e.message }
  |> should.equal("search returned 5 results")
}

pub fn log_entry_stores_level_test() {
  let ctx = trace_context.new_trace("guardian_veto", "L0")
  correlated_log.log(correlated_log.Critical, "guardian vetoed action", ctx)
  |> fn(e) { e.level }
  |> should.equal(correlated_log.Critical)
}

pub fn log_entry_timestamp_positive_test() {
  let ctx = trace_context.new_trace("zenoh_query", "L6")
  correlated_log.log(correlated_log.Debug, "zenoh msg received", ctx)
  |> fn(e) { e.timestamp > 0 }
  |> should.be_true()
}

pub fn log_entry_trace_id_propagated_test() {
  let ctx = trace_context.new_trace("db_write", "L3")
  correlated_log.log(correlated_log.Warn, "slow query >100ms", ctx)
  |> fn(e) { e.trace.trace_id }
  |> should.equal(ctx.trace_id)
}

pub fn format_contains_level_test() {
  let ctx = trace_context.new_trace("nif_immune", "L0")
  let entry =
    correlated_log.log(correlated_log.Error, "nif returned error", ctx)
  correlated_log.format(entry)
  |> string.contains("ERROR")
  |> should.be_true()
}

pub fn format_plain_contains_message_test() {
  let ctx = trace_context.new_trace("boot_seq", "L4")
  let entry = correlated_log.log(correlated_log.Info, "tier 1 started", ctx)
  correlated_log.format_plain(entry)
  |> string.contains("tier 1 started")
  |> should.be_true()
}

pub fn to_json_contains_trace_id_test() {
  let ctx = trace_context.new_trace("moz_tool_call", "L5")
  let entry = correlated_log.log(correlated_log.Info, "tool invoked", ctx)
  correlated_log.to_json(entry)
  |> string.contains(ctx.trace_id)
  |> should.be_true()
}

pub fn to_json_contains_severity_test() {
  let ctx = trace_context.new_trace("federation_sync", "L7")
  let entry = correlated_log.log(correlated_log.Warn, "quorum degraded", ctx)
  correlated_log.to_json(entry)
  |> string.contains("\"severity\":\"WARN\"")
  |> should.be_true()
}

pub fn to_json_contains_severity_number_test() {
  let ctx = trace_context.new_trace("cascade_check", "L6")
  let entry = correlated_log.log(correlated_log.Error, "cascade depth 3", ctx)
  correlated_log.to_json(entry)
  // Error severity_number = 17
  |> string.contains("\"severity_number\":17")
  |> should.be_true()
}

pub fn filter_by_level_keeps_above_threshold_test() {
  let ctx = trace_context.new_trace("batch_test", "L3")
  let entries = [
    correlated_log.log(correlated_log.Debug, "debug msg", ctx),
    correlated_log.log(correlated_log.Info, "info msg", ctx),
    correlated_log.log(correlated_log.Warn, "warn msg", ctx),
    correlated_log.log(correlated_log.Error, "error msg", ctx),
  ]
  correlated_log.filter_by_level(entries, correlated_log.Warn)
  |> list.length()
  |> should.equal(2)
}

pub fn filter_by_trace_isolates_one_trace_test() {
  let ctx_a = trace_context.new_trace("op_a", "L3")
  let ctx_b = trace_context.new_trace("op_b", "L5")
  let entries = [
    correlated_log.log(correlated_log.Info, "msg for a", ctx_a),
    correlated_log.log(correlated_log.Info, "msg for b", ctx_b),
    correlated_log.log(correlated_log.Warn, "warn for a", ctx_a),
  ]
  correlated_log.filter_by_trace(entries, ctx_a.trace_id)
  |> list.length()
  |> should.equal(2)
}

pub fn level_to_string_debug_test() {
  correlated_log.level_to_string(correlated_log.Debug)
  |> should.equal("DEBUG")
}

pub fn level_to_otel_severity_critical_test() {
  correlated_log.level_to_otel_severity(correlated_log.Critical)
  |> should.equal(21)
}

import gleam/list
