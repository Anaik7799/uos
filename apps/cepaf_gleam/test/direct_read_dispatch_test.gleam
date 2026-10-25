//// apps/cepaf_gleam/test/direct_read_dispatch_test.gleam
//// Formal Invariant Verification & Bounded Direct Read Dispatch Falsifiers
//// Invariants: DD-01 through DD-10 (docs/design/20261001-0443-direct-tool-dispatch-invariants.json)
//// Contracts: SC-JIDOKA-001, SC-SA-PLAN-001, SC-COG-001, SC-PROVENANCE-001

import cepaf_gleam/harness/clock
import cepaf_gleam/harness/cognitive_worker
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/direct_read_dispatch as direct
import cepaf_gleam/harness/doctor_projection
import cepaf_gleam/harness/tool_fenced_dispatcher as td
import envoy
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

@external(erlang, "erlang", "put")
fn put_state(key: String, val: Int) -> dynamic.Dynamic

@external(erlang, "erlang", "get")
fn get_state(key: String) -> Int

fn make_test_binding() -> dev.Binding {
  dev.Binding(
    role: "direct_read",
    plan: "uos/direct-dispatch/20261001-0440",
    task: "FIXTURE_TASK",
    worker: "fixture-worker",
    attempt: 1,
    session: "fixture-session",
    epoch: 1,
  )
}

fn make_test_proposal(
  call_id: String,
  tool: String,
  args: String,
) -> td.ToolProposal {
  td.ToolProposal(call_id, tool, args)
}

// =============================================================================
// DD-02: Tool Allowlist Falsifiers
// =============================================================================

pub fn allowlist_positive_query_doctor_test() {
  let proposal = make_test_proposal("call-01", "query_doctor", "{}")
  direct.validate_tool_proposal(proposal) |> should.be_ok
}

pub fn allowlist_positive_query_saplan_test() {
  let proposal = make_test_proposal("call-02", "query_saplan", "{}")
  direct.validate_tool_proposal(proposal) |> should.be_ok
}

pub fn allowlist_refuses_mutating_tools_test() {
  let mutating_tools = [
    "resuscitate_node",
    "chaos_inject",
    "rotate_keys",
    "storage_rebalance",
  ]
  let binding = make_test_binding()
  let dummy_fencer = fn(_b, _ms) {
    let assert Ok(clk) = clock.observe()
    Ok(dev.Fence(clk, 9_999_999_999_999, 9_999_999_999_999))
  }
  let dummy_executor = fn(_t, _b) { Ok("{}") }

  list.each(mutating_tools, fn(tool) {
    let proposal = make_test_proposal("call-mut", tool, "{}")
    let outcome =
      direct.dispatch_with_fencer(
        proposal,
        binding,
        dummy_fencer,
        dummy_executor,
      )
    case outcome {
      td.FencedAndonHalt(code, reason) -> {
        code |> should.equal(-32_001)
        string.contains(reason, "not in direct read allowlist")
        |> should.be_true
      }
      td.Dispatched(_, _, _) -> panic as "mutating tool must not be dispatched"
    }
  })
}

pub fn allowlist_refuses_unknown_tools_test() {
  let binding = make_test_binding()
  let dummy_fencer = fn(_b, _ms) {
    let assert Ok(clk) = clock.observe()
    Ok(dev.Fence(clk, 9_999_999_999_999, 9_999_999_999_999))
  }
  let dummy_executor = fn(_t, _b) { Ok("{}") }
  let proposal =
    make_test_proposal("call-unk", "arbitrary_subprocess_exec", "{}")
  let outcome =
    direct.dispatch_with_fencer(proposal, binding, dummy_fencer, dummy_executor)
  case outcome {
    td.FencedAndonHalt(code, reason) -> {
      code |> should.equal(-32_001)
      string.contains(reason, "not in direct read allowlist") |> should.be_true
    }
    td.Dispatched(_, _, _) -> panic as "unknown tool must not be dispatched"
  }
}

// =============================================================================
// DD-06: Strict Empty JSON Object Arguments Validation Falsifiers
// =============================================================================

pub fn argument_validation_accepts_empty_object_test() {
  let proposal = make_test_proposal("call-args-ok1", "query_doctor", "{}")
  direct.validate_tool_proposal(proposal) |> should.be_ok
}

pub fn argument_validation_accepts_whitespace_empty_object_test() {
  let proposal1 = make_test_proposal("call-args-ok2", "query_doctor", "{ }")
  direct.validate_tool_proposal(proposal1) |> should.be_ok

  let proposal2 = make_test_proposal("call-args-ok3", "query_doctor", "{\n\t }")
  direct.validate_tool_proposal(proposal2) |> should.be_ok
}

pub fn argument_validation_refuses_blank_and_whitespace_only_test() {
  let blanks = ["", " ", "  ", "\t", "\n\t "]
  list.each(blanks, fn(b) {
    let proposal = make_test_proposal("call-blank", "query_doctor", b)
    case direct.validate_tool_proposal(proposal) {
      Error(td.FencedAndonHalt(code, reason)) -> {
        code |> should.equal(-32_000)
        string.contains(reason, "strictly requires empty JSON object")
        |> should.be_true
      }
      _ -> panic as "blank/whitespace-only arguments must be rejected"
    }
  })
}

pub fn argument_validation_refuses_primitives_test() {
  let primitives = ["123", "\"hello\"", "true", "false", "null"]
  list.each(primitives, fn(p) {
    let proposal = make_test_proposal("call-prim", "query_doctor", p)
    case direct.validate_tool_proposal(proposal) {
      Error(td.FencedAndonHalt(code, reason)) -> {
        code |> should.equal(-32_000)
        string.contains(reason, "strictly requires empty JSON object")
        |> should.be_true
      }
      _ -> panic as "JSON primitives must be rejected"
    }
  })
}

pub fn argument_validation_refuses_arrays_test() {
  let arrays = ["[]", "[1, 2]", "[\"{}\"]"]
  list.each(arrays, fn(arr) {
    let proposal = make_test_proposal("call-arr", "query_doctor", arr)
    case direct.validate_tool_proposal(proposal) {
      Error(td.FencedAndonHalt(code, reason)) -> {
        code |> should.equal(-32_000)
        string.contains(reason, "strictly requires empty JSON object")
        |> should.be_true
      }
      _ -> panic as "JSON arrays must be rejected"
    }
  })
}

pub fn argument_validation_refuses_non_empty_object_test() {
  let proposal =
    make_test_proposal("call-args-1", "query_doctor", "{\"filter\":\"all\"}")
  case direct.validate_tool_proposal(proposal) {
    Error(td.FencedAndonHalt(code, reason)) -> {
      code |> should.equal(-32_000)
      string.contains(reason, "strictly requires empty JSON object")
      |> should.be_true
    }
    _ -> panic as "non-empty args must be rejected"
  }
}

pub fn argument_validation_refuses_malformed_json_test() {
  let proposal =
    make_test_proposal("call-args-2", "query_doctor", "{not-valid-json")
  case direct.validate_tool_proposal(proposal) {
    Error(td.FencedAndonHalt(code, reason)) -> {
      code |> should.equal(-32_000)
      string.contains(reason, "strictly requires empty JSON object")
      |> should.be_true
    }
    _ -> panic as "malformed json must be rejected"
  }
}

pub fn argument_validation_refuses_oversized_args_test() {
  let oversized = "{" <> string.repeat(" ", 300) <> "}"
  let proposal = make_test_proposal("call-args-3", "query_doctor", oversized)
  case direct.validate_tool_proposal(proposal) {
    Error(td.FencedAndonHalt(code, reason)) -> {
      code |> should.equal(-32_000)
      string.contains(reason, "exceed bound") |> should.be_true
    }
    _ -> panic as "oversized args must be rejected"
  }
}

pub fn call_id_validation_falsifiers_test() {
  // Empty call_id
  let empty_id = make_test_proposal("", "query_doctor", "{}")
  case direct.validate_tool_proposal(empty_id) {
    Error(td.FencedAndonHalt(code, _)) -> code |> should.equal(-32_000)
    _ -> panic as "empty call_id must be rejected"
  }

  // Oversized call_id (>64 bytes)
  let long_id = make_test_proposal(string.repeat("a", 65), "query_doctor", "{}")
  case direct.validate_tool_proposal(long_id) {
    Error(td.FencedAndonHalt(code, _)) -> code |> should.equal(-32_000)
    _ -> panic as "oversized call_id must be rejected"
  }

  // Invalid chars (spaces, semicolons)
  let invalid_chars = make_test_proposal("call id; drop", "query_doctor", "{}")
  case direct.validate_tool_proposal(invalid_chars) {
    Error(td.FencedAndonHalt(code, _)) -> code |> should.equal(-32_000)
    _ -> panic as "invalid call_id characters must be rejected"
  }
}

// =============================================================================
// DD-03, DD-04 & DD-05: Authority Fencing Falsifiers
// =============================================================================

pub fn pre_fence_failure_halts_closed_test() {
  let binding = make_test_binding()
  let proposal = make_test_proposal("call-fence-1", "query_doctor", "{}")
  let failing_pre_fencer = fn(_b, _ms) {
    Error("task_role_attempt_lease_or_dependency_fence")
  }
  let dummy_executor = fn(_t, _b) { Ok("{}") }

  let outcome =
    direct.dispatch_with_fencer(
      proposal,
      binding,
      failing_pre_fencer,
      dummy_executor,
    )
  case outcome {
    td.FencedAndonHalt(code, reason) -> {
      code |> should.equal(td.andon_halt_unauthorized_code)
      string.contains(reason, "Authority fence failed before observation")
      |> should.be_true
      string.contains(reason, "task_role_attempt_lease_or_dependency_fence")
      |> should.be_true
    }
    td.Dispatched(_, _, _) -> panic as "pre-fence failure must halt closed"
  }
}

pub fn post_fence_failure_discards_observation_test() {
  let binding = make_test_binding()
  let proposal = make_test_proposal("call-fence-2", "query_doctor", "{}")
  let _ = put_state("flaky_fence_count", 0)
  let flaky_fencer = fn(_b, _ms) {
    let count = get_state("flaky_fence_count")
    let _ = put_state("flaky_fence_count", count + 1)
    case count {
      0 -> {
        let assert Ok(clk) = clock.observe()
        Ok(dev.Fence(clk, 9_999_999_999_999, 9_999_999_999_999))
      }
      _ -> Error("coordinator_lease_expired_after_observation")
    }
  }
  let dummy_executor = fn(_t, _b) { Ok("{\"doctor\":\"healthy\"}") }

  let outcome =
    direct.dispatch_with_fencer(proposal, binding, flaky_fencer, dummy_executor)
  case outcome {
    td.FencedAndonHalt(code, reason) -> {
      code |> should.equal(td.andon_halt_unauthorized_code)
      string.contains(reason, "Authority fence failed after observation")
      |> should.be_true
      string.contains(reason, "coordinator_lease_expired_after_observation")
      |> should.be_true
    }
    td.Dispatched(_, _, _) ->
      panic as "post-fence failure must discard output and halt closed"
  }
}

// =============================================================================
// DD-07: Tool Truth in cognitive_worker.execute_harness_tool
// =============================================================================

pub fn execute_harness_tool_mutations_refuse_test() {
  let mutating = [
    "resuscitate_node",
    "chaos_inject",
    "rotate_keys",
    "storage_rebalance",
  ]
  list.each(mutating, fn(tool) {
    let res = cognitive_worker.execute_harness_tool(tool, "{}")
    res |> should.be_error
    let assert Error(msg) = res
    string.contains(
      msg,
      "unavailable: live 2oo3 constitutional consensus executor not connected",
    )
    |> should.be_true
    string.contains(msg, "simulated mutation barred") |> should.be_true
  })
}

pub fn execute_harness_tool_zigvm_subprocess_barred_test() {
  let res = cognitive_worker.execute_harness_tool("invoke_zigvm", "{}")
  res |> should.be_error
  let assert Error(msg) = res
  string.contains(msg, "arbitrary subprocess execution prohibited")
  |> should.be_true
}

pub fn execute_harness_tool_static_diagnostics_report_unobserved_test() {
  let diagnostics = [
    "query_inference_tier",
    "query_voice_status",
    "query_ooda_phase",
    "query_ruliology",
    "query_traces_recent",
    "query_checklist",
    "query_zk_adrs",
    "query_wiki_index",
  ]
  list.each(diagnostics, fn(diag) {
    let res = cognitive_worker.execute_harness_tool(diag, "{}")
    res |> should.be_ok
    let assert Ok(json_str) = res
    string.contains(json_str, "UNOBSERVED") |> should.be_true
    string.contains(json_str, "\"observed_in_query\":false") |> should.be_true
    // Negative assertions: must NOT report fabricated green counts or fake EV numbers
    string.contains(json_str, "18/18 GREEN") |> should.be_false
    string.contains(json_str, "EV-108") |> should.be_false
    string.contains(json_str, "EV-109") |> should.be_false
    string.contains(json_str, "EV-110") |> should.be_false
  })
}

// =============================================================================
// DD-09: SQL LIMIT 257 Sentinel & Sanitized Sa-Plan Representation
// =============================================================================

pub fn format_sanitized_saplan_omits_private_payloads_test() {
  let tasks = [
    direct.SanitizedTask("TASK_A", "executing"),
    direct.SanitizedTask("TASK_B", "completed"),
    direct.SanitizedTask("TASK_C", "available"),
  ]
  let json_str = direct.format_sanitized_saplan("test/plan-01", tasks)

  // Positive assertions: contains counts and state
  string.contains(json_str, "\"plan_id\":\"test/plan-01\"") |> should.be_true
  string.contains(json_str, "\"total_tasks\":3") |> should.be_true
  string.contains(json_str, "\"executing\":1") |> should.be_true
  string.contains(json_str, "\"completed\":1") |> should.be_true
  string.contains(json_str, "\"available\":1") |> should.be_true
  string.contains(json_str, "\"blocked\":0") |> should.be_true

  // Negative assertions: NO private fields, NO results, NO errors, NO secrets
  string.contains(json_str, "result_payload") |> should.be_false
  string.contains(json_str, "output_json") |> should.be_false
  string.contains(json_str, "error_trace") |> should.be_false
  string.contains(json_str, "session_token") |> should.be_false
}

fn make_tasks(n: Int, acc: List(json.Json)) -> List(json.Json) {
  case n <= 0 {
    True -> acc
    False -> {
      let t =
        json.object([
          #("id", json.string("task-" <> int.to_string(n))),
          #("state", json.string("available")),
        ])
      make_tasks(n - 1, [t, ..acc])
    }
  }
}

pub fn sentinel_256_tasks_passes_test() {
  let tasks = make_tasks(256, [])
  let raw = json.array(tasks, fn(x) { x }) |> json.to_string
  let parsed = direct.parse_sanitized_tasks(raw)
  parsed |> should.be_ok
  let assert Ok(task_list) = parsed
  list.length(task_list) |> should.equal(256)
  let formatted = direct.format_sanitized_saplan("test/plan-256", task_list)
  string.contains(formatted, "\"total_tasks\":256") |> should.be_true
}

pub fn sentinel_257_tasks_rejected_test() {
  let tasks = make_tasks(257, [])
  let raw = json.array(tasks, fn(x) { x }) |> json.to_string
  let parsed = direct.parse_sanitized_tasks(raw)
  parsed |> should.be_error
  let assert Error(err) = parsed
  string.contains(err, "task_count_exceeds_limit_256") |> should.be_true
}

// =============================================================================
// DD-08: Read Repeat Idempotency
// =============================================================================

pub fn repeat_observation_is_idempotent_test() {
  let binding = make_test_binding()
  let proposal = make_test_proposal("call-rep-01", "query_doctor", "{}")
  let dummy_fencer = fn(_b, _ms) {
    let assert Ok(clk) = clock.observe()
    Ok(dev.Fence(clk, 9_999_999_999_999, 9_999_999_999_999))
  }
  let dummy_executor = fn(_t, _b) {
    Ok(doctor_projection.project() |> doctor_projection.to_json)
  }

  let outcome1 =
    direct.dispatch_with_fencer(proposal, binding, dummy_fencer, dummy_executor)
  let outcome2 =
    direct.dispatch_with_fencer(proposal, binding, dummy_fencer, dummy_executor)

  case outcome1, outcome2 {
    td.Dispatched(id1, name1, res1), td.Dispatched(id2, name2, res2) -> {
      id1 |> should.equal(id2)
      name1 |> should.equal(name2)
      res1 |> should.equal(res2)
      string.contains(res1, "admitted_ev_ceiling") |> should.be_true
    }
    _, _ -> panic as "repeated read observation must succeed idempotently"
  }
}

// =============================================================================
// DD-01: Launcher Environment Validation Falsifiers
// =============================================================================

fn setup_valid_env() {
  envoy.set("UOS_DIRECT_ROLE", "direct_read")
  envoy.set("UOS_DIRECT_PLAN", "uos/direct-dispatch/20261001-0440")
  envoy.set("UOS_DIRECT_TASK", "FIXTURE_TASK")
  envoy.set("UOS_DIRECT_WORKER", "fixture-worker")
  envoy.set("UOS_DIRECT_ATTEMPT", "1")
  envoy.set("UOS_DIRECT_SESSION", "fixture-session")
  envoy.set("UOS_DIRECT_EPOCH", "1")
}

pub fn launcher_env_valid_binding_test() {
  setup_valid_env()
  let res = direct.load_direct_binding()
  res |> should.be_ok
  let assert Ok(b) = res
  b.role |> should.equal("direct_read")
  b.plan |> should.equal("uos/direct-dispatch/20261001-0440")
  b.task |> should.equal("FIXTURE_TASK")
  b.worker |> should.equal("fixture-worker")
  b.attempt |> should.equal(1)
  b.session |> should.equal("fixture-session")
  b.epoch |> should.equal(1)
}

pub fn launcher_env_requires_direct_read_role_test() {
  setup_valid_env()
  envoy.set("UOS_DIRECT_ROLE", "development")
  direct.load_direct_binding()
  |> should.equal(Error("invalid_direct_role_expected_direct_read"))

  envoy.set("UOS_DIRECT_ROLE", "other_role")
  direct.load_direct_binding()
  |> should.equal(Error("invalid_direct_role_expected_direct_read"))

  envoy.unset("UOS_DIRECT_ROLE")
  direct.load_direct_binding()
  |> should.equal(Error("role_binding_missing"))
}

pub fn launcher_env_requires_all_6_fields_test() {
  setup_valid_env()
  envoy.unset("UOS_DIRECT_PLAN")
  direct.load_direct_binding() |> should.equal(Error("plan_binding_missing"))

  setup_valid_env()
  envoy.unset("UOS_DIRECT_TASK")
  direct.load_direct_binding() |> should.equal(Error("task_binding_missing"))

  setup_valid_env()
  envoy.unset("UOS_DIRECT_WORKER")
  direct.load_direct_binding() |> should.equal(Error("worker_binding_missing"))

  setup_valid_env()
  envoy.unset("UOS_DIRECT_ATTEMPT")
  direct.load_direct_binding() |> should.equal(Error("attempt_binding_missing"))

  setup_valid_env()
  envoy.unset("UOS_DIRECT_SESSION")
  direct.load_direct_binding() |> should.equal(Error("session_binding_missing"))

  setup_valid_env()
  envoy.unset("UOS_DIRECT_EPOCH")
  direct.load_direct_binding() |> should.equal(Error("epoch_binding_missing"))
}

pub fn launcher_env_rejects_harness_fallback_test() {
  // Clear all DIRECT env vars
  envoy.unset("UOS_DIRECT_ROLE")
  envoy.unset("UOS_DIRECT_PLAN")
  envoy.unset("UOS_DIRECT_TASK")
  envoy.unset("UOS_DIRECT_WORKER")
  envoy.unset("UOS_DIRECT_ATTEMPT")
  envoy.unset("UOS_DIRECT_SESSION")
  envoy.unset("UOS_DIRECT_EPOCH")

  // Set HARNESS env vars
  envoy.set("UOS_HARNESS_ROLE", "development")
  envoy.set("UOS_HARNESS_PLAN", "uos/direct-dispatch/20261001-0440")
  envoy.set("UOS_HARNESS_TASK", "FIXTURE_TASK")
  envoy.set("UOS_HARNESS_WORKER", "fixture-worker")
  envoy.set("UOS_HARNESS_ATTEMPT", "1")
  envoy.set("UOS_HARNESS_SESSION", "fixture-session")
  envoy.set("UOS_HARNESS_EPOCH", "1")

  // Must fail closed with role_binding_missing; NO fallback to HARNESS
  direct.load_direct_binding() |> should.equal(Error("role_binding_missing"))

  // Cleanup harness env
  envoy.unset("UOS_HARNESS_ROLE")
  envoy.unset("UOS_HARNESS_PLAN")
  envoy.unset("UOS_HARNESS_TASK")
  envoy.unset("UOS_HARNESS_WORKER")
  envoy.unset("UOS_HARNESS_ATTEMPT")
  envoy.unset("UOS_HARNESS_SESSION")
  envoy.unset("UOS_HARNESS_EPOCH")
}

// =============================================================================
// Shared development.evaluate_task_window Boundary Invariants (Deterministic)
// =============================================================================

pub fn evaluate_task_window_rejects_direct_read_role_test() {
  let binding = make_test_binding()
  // role is "direct_read"
  // development.evaluate_task_window strictly requires role == "development".
  let res =
    dev.evaluate_task_window(
      binding,
      "executing",
      binding.worker,
      binding.attempt,
      9_999_999_999_999,
      0,
      1_000_000_000,
      10_000,
    )
  res |> should.equal(Error("task_role_attempt_lease_or_dependency_fence"))
}

pub fn evaluate_task_window_rejects_completed_state_test() {
  let dev_binding =
    dev.Binding(
      "development",
      "test-plan",
      "test-task",
      "test-worker",
      1,
      "test-session",
      1,
    )
  let res =
    dev.evaluate_task_window(
      dev_binding,
      "completed",
      dev_binding.worker,
      dev_binding.attempt,
      9_999_999_999_999,
      0,
      1_000_000_000,
      10_000,
    )
  res |> should.equal(Error("task_role_attempt_lease_or_dependency_fence"))
}

pub fn evaluate_task_window_rejects_wrong_worker_test() {
  let dev_binding =
    dev.Binding(
      "development",
      "test-plan",
      "test-task",
      "test-worker",
      1,
      "test-session",
      1,
    )
  let res =
    dev.evaluate_task_window(
      dev_binding,
      "executing",
      "other-worker",
      dev_binding.attempt,
      9_999_999_999_999,
      0,
      1_000_000_000,
      10_000,
    )
  res |> should.equal(Error("task_role_attempt_lease_or_dependency_fence"))
}

pub fn evaluate_task_window_rejects_wrong_attempt_test() {
  let dev_binding =
    dev.Binding(
      "development",
      "test-plan",
      "test-task",
      "test-worker",
      1,
      "test-session",
      1,
    )
  let res =
    dev.evaluate_task_window(
      dev_binding,
      "executing",
      dev_binding.worker,
      2,
      9_999_999_999_999,
      0,
      1_000_000_000,
      10_000,
    )
  res |> should.equal(Error("task_role_attempt_lease_or_dependency_fence"))
}

pub fn evaluate_task_window_rejects_blocked_task_test() {
  let dev_binding =
    dev.Binding(
      "development",
      "test-plan",
      "test-task",
      "test-worker",
      1,
      "test-session",
      1,
    )
  let res =
    dev.evaluate_task_window(
      dev_binding,
      "executing",
      dev_binding.worker,
      dev_binding.attempt,
      9_999_999_999_999,
      1,
      1_000_000_000,
      10_000,
    )
  res |> should.equal(Error("task_role_attempt_lease_or_dependency_fence"))
}

pub fn evaluate_task_window_rejects_expired_deadline_test() {
  let dev_binding =
    dev.Binding(
      "development",
      "test-plan",
      "test-task",
      "test-worker",
      1,
      "test-session",
      1,
    )
  let now_ns = 1_000_000_000
  let expired_deadline = now_ns + 5_000_000
  // requires 10_000 ms = 10_000_000_000 ns
  let res =
    dev.evaluate_task_window(
      dev_binding,
      "executing",
      dev_binding.worker,
      dev_binding.attempt,
      expired_deadline,
      0,
      now_ns,
      10_000,
    )
  res |> should.equal(Error("task_role_attempt_lease_or_dependency_fence"))
}

pub fn evaluate_task_window_accepts_valid_development_lease_test() {
  let dev_binding =
    dev.Binding(
      "development",
      "test-plan",
      "test-task",
      "test-worker",
      1,
      "test-session",
      1,
    )
  let now_ns = 1_000_000_000
  let valid_deadline = now_ns + 30_000_000_000
  let res =
    dev.evaluate_task_window(
      dev_binding,
      "executing",
      dev_binding.worker,
      dev_binding.attempt,
      valid_deadline,
      0,
      now_ns,
      10_000,
    )
  res |> should.equal(Ok(Nil))
}

// =============================================================================
// Live Canonical Positive Probe (Separate from Unit Suite)
// Accepts trusted loader binding from environment; asserts actual live results.
// Missing or refused authority halts/panics nonzero.
// =============================================================================

pub fn live_canonical_positive_probe() {
  let binding = case direct.load_direct_binding() {
    Ok(b) -> b
    Error(err) ->
      panic as {
        "Live probe failed: launcher binding missing/invalid: " <> err
      }
  }

  // 1. Dispatch real query_doctor under live authority
  let doc_proposal = td.ToolProposal("live-doc-probe", "query_doctor", "{}")
  case direct.dispatch(doc_proposal) {
    td.Dispatched(id, name, result_json) -> {
      id |> should.equal("live-doc-probe")
      name |> should.equal("query_doctor")
      string.contains(result_json, "\"admitted_ev_ceiling\":93")
      |> should.be_true
      string.contains(result_json, "\"doctor_status\":\"UNOBSERVED_RUNTIME\"")
      |> should.be_true
      string.contains(result_json, "\"zero_muda\":null") |> should.be_true
      io.println("PASS: Live canonical query_doctor dispatched successfully!")
    }
    td.FencedAndonHalt(code, reason) ->
      panic as {
        "Live query_doctor failed with code "
        <> string.inspect(code)
        <> ": "
        <> reason
      }
  }

  // 2. Dispatch real query_saplan under live authority
  let saplan_proposal =
    td.ToolProposal("live-saplan-probe", "query_saplan", "{}")
  case direct.dispatch(saplan_proposal) {
    td.Dispatched(id, name, result_json) -> {
      id |> should.equal("live-saplan-probe")
      name |> should.equal("query_saplan")
      string.contains(result_json, "\"plan_id\":\"" <> binding.plan <> "\"")
      |> should.be_true
      string.contains(result_json, "\"total_tasks\":13") |> should.be_true
      string.contains(result_json, "\"tasks\":") |> should.be_true
      io.println(
        "PASS: Live canonical query_saplan dispatched successfully (13 tasks observed)!",
      )
    }
    td.FencedAndonHalt(code, reason) ->
      panic as {
        "Live query_saplan failed with code "
        <> string.inspect(code)
        <> ": "
        <> reason
      }
  }

  io.println("PASS: ALL LIVE CANONICAL POSITIVE PROBES PASSED")
}

// =============================================================================
// Deterministic Unit Suite Entrypoint
// =============================================================================

pub fn main() {
  allowlist_positive_query_doctor_test()
  allowlist_positive_query_saplan_test()
  allowlist_refuses_mutating_tools_test()
  allowlist_refuses_unknown_tools_test()

  argument_validation_accepts_empty_object_test()
  argument_validation_accepts_whitespace_empty_object_test()
  argument_validation_refuses_blank_and_whitespace_only_test()
  argument_validation_refuses_primitives_test()
  argument_validation_refuses_arrays_test()
  argument_validation_refuses_non_empty_object_test()
  argument_validation_refuses_malformed_json_test()
  argument_validation_refuses_oversized_args_test()

  call_id_validation_falsifiers_test()

  pre_fence_failure_halts_closed_test()
  post_fence_failure_discards_observation_test()

  execute_harness_tool_mutations_refuse_test()
  execute_harness_tool_zigvm_subprocess_barred_test()
  execute_harness_tool_static_diagnostics_report_unobserved_test()

  format_sanitized_saplan_omits_private_payloads_test()
  sentinel_256_tasks_passes_test()
  sentinel_257_tasks_rejected_test()

  repeat_observation_is_idempotent_test()

  launcher_env_valid_binding_test()
  launcher_env_requires_direct_read_role_test()
  launcher_env_requires_all_6_fields_test()
  launcher_env_rejects_harness_fallback_test()

  evaluate_task_window_rejects_direct_read_role_test()
  evaluate_task_window_rejects_completed_state_test()
  evaluate_task_window_rejects_wrong_worker_test()
  evaluate_task_window_rejects_wrong_attempt_test()
  evaluate_task_window_rejects_blocked_task_test()
  evaluate_task_window_rejects_expired_deadline_test()
  evaluate_task_window_accepts_valid_development_lease_test()

  io.println(
    "PASS: ALL 32 DETERMINISTIC DIRECT READ DISPATCH UNIT TESTS PASSED",
  )
}
