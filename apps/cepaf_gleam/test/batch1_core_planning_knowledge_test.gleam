// Batch 1: Core / Planning / Knowledge module tests
// Covers: core/result, core/boot, planning/enforcer, planning/safety_kernel,
//         knowledge/domain, knowledge/anomaly, knowledge/semantic (dot_product only)

import cepaf_gleam/core/boot
import cepaf_gleam/core/result as cresult
import cepaf_gleam/knowledge/anomaly
import cepaf_gleam/knowledge/domain as kdomain
import cepaf_gleam/knowledge/semantic
import cepaf_gleam/planning/enforcer
import cepaf_gleam/planning/safety_kernel
import gleam/dict
import gleam/option
import gleeunit/should

// =============================================================================
// core/result tests
// =============================================================================

pub fn lift2_both_ok_test() {
  let add = fn(a, b) { a + b }
  cresult.lift2(add, Ok(3), Ok(4))
  |> should.equal(Ok(7))
}

pub fn lift2_first_error_test() {
  let add = fn(a, b) { a + b }
  cresult.lift2(add, Error("err1"), Ok(4))
  |> should.equal(Error("err1"))
}

pub fn lift2_second_error_test() {
  let add = fn(a, b) { a + b }
  cresult.lift2(add, Ok(3), Error("err2"))
  |> should.equal(Error("err2"))
}

pub fn lift2_both_error_returns_first_test() {
  let add = fn(a, b) { a + b }
  cresult.lift2(add, Error("first"), Error("second"))
  |> should.equal(Error("first"))
}

pub fn lift3_all_ok_test() {
  let add3 = fn(a, b, c) { a + b + c }
  cresult.lift3(add3, Ok(1), Ok(2), Ok(3))
  |> should.equal(Ok(6))
}

pub fn lift3_first_error_test() {
  let add3 = fn(a, b, c) { a + b + c }
  cresult.lift3(add3, Error("e"), Ok(2), Ok(3))
  |> should.equal(Error("e"))
}

pub fn lift3_third_error_test() {
  let add3 = fn(a, b, c) { a + b + c }
  cresult.lift3(add3, Ok(1), Ok(2), Error("e3"))
  |> should.equal(Error("e3"))
}

pub fn traverse_all_ok_test() {
  let parse = fn(x) {
    case x > 0 {
      True -> Ok(x * 2)
      False -> Error("negative")
    }
  }
  cresult.traverse(over: [1, 2, 3], with: parse)
  |> should.equal(Ok([2, 4, 6]))
}

pub fn traverse_with_error_test() {
  let parse = fn(x) {
    case x > 0 {
      True -> Ok(x * 2)
      False -> Error("negative")
    }
  }
  cresult.traverse(over: [1, -1, 3], with: parse)
  |> should.equal(Error("negative"))
}

pub fn traverse_empty_list_test() {
  let parse = fn(x) { Ok(x) }
  cresult.traverse(over: [], with: parse)
  |> should.equal(Ok([]))
}

pub fn partition_mixed_test() {
  let results = [Ok(1), Error("a"), Ok(2), Error("b"), Ok(3)]
  cresult.partition(results)
  |> should.equal(#([1, 2, 3], ["a", "b"]))
}

pub fn partition_all_ok_test() {
  let results = [Ok(1), Ok(2)]
  cresult.partition(results)
  |> should.equal(#([1, 2], []))
}

pub fn partition_all_error_test() {
  let results: List(Result(Int, String)) = [Error("x"), Error("y")]
  cresult.partition(results)
  |> should.equal(#([], ["x", "y"]))
}

pub fn partition_empty_test() {
  let results: List(Result(Int, String)) = []
  cresult.partition(results)
  |> should.equal(#([], []))
}

pub fn default_with_ok_test() {
  cresult.default_with(Ok(42), fn(_e) { 0 })
  |> should.equal(42)
}

pub fn default_with_error_test() {
  cresult.default_with(Error("missing"), fn(e) {
    case e {
      "missing" -> -1
      _ -> 0
    }
  })
  |> should.equal(-1)
}

pub fn require_true_test() {
  cresult.require(True, if_false: "must be true")
  |> should.equal(Ok(Nil))
}

pub fn require_false_test() {
  cresult.require(False, if_false: "condition failed")
  |> should.equal(Error("condition failed"))
}

pub fn ignore_ok_with_ok_test() {
  cresult.ignore_ok(Ok(42))
  |> should.equal(Ok(Nil))
}

pub fn ignore_ok_with_error_test() {
  cresult.ignore_ok(Error("err"))
  |> should.equal(Error("err"))
}

pub fn tap_ok_returns_original_test() {
  // tap should return the original Ok value unchanged
  cresult.tap(Ok(99), for: fn(_v) { Nil })
  |> should.equal(Ok(99))
}

pub fn tap_error_returns_error_test() {
  cresult.tap(Error("nope"), for: fn(_v) { Nil })
  |> should.equal(Error("nope"))
}

pub fn iter_ok_test() {
  // iter with Ok should call the function (we just verify no crash)
  cresult.iter(Ok(1), for: fn(_v) { Nil })
  |> should.equal(Nil)
}

pub fn iter_error_does_nothing_test() {
  cresult.iter(Error("x"), for: fn(_v) { Nil })
  |> should.equal(Nil)
}

pub fn iter_error_with_error_test() {
  cresult.iter_error(Error("problem"), for: fn(_e) { Nil })
  |> should.equal(Nil)
}

pub fn iter_error_with_ok_does_nothing_test() {
  cresult.iter_error(Ok(1), for: fn(_e) { Nil })
  |> should.equal(Nil)
}

// =============================================================================
// core/boot tests
// =============================================================================

pub fn start_boot_initial_state_test() {
  let state = boot.start_boot()
  state.current_stage
  |> should.equal(boot.Stage1InitializeSystem)

  state.completed_stages
  |> should.equal([])
}

pub fn execute_stage_success_advances_test() {
  let state = boot.start_boot()
  let action = fn(_s) { Ok(boot.BootState(boot.Stage1InitializeSystem, [])) }

  let result = boot.execute_stage(state, action)
  case result {
    Ok(next) -> {
      next.current_stage
      |> should.equal(boot.Stage2LoadConfiguration)
      // Stage1 should be in completed list
      next.completed_stages
      |> should.equal([boot.Stage1InitializeSystem])
    }
    Error(_) -> should.fail()
  }
}

pub fn execute_stage_failure_test() {
  let state = boot.start_boot()
  let action = fn(_s) {
    Error(boot.BootError(boot.Stage1InitializeSystem, "disk failure"))
  }

  let result = boot.execute_stage(state, action)
  case result {
    Ok(_) -> should.fail()
    Error(err) -> {
      err.stage
      |> should.equal(boot.Stage1InitializeSystem)
      err.reason
      |> should.equal("disk failure")
    }
  }
}

pub fn run_full_sequence_success_test() {
  let initial = boot.start_boot()
  let ok_action = fn(_s) { Ok(boot.BootState(boot.Stage1InitializeSystem, [])) }

  // Run 3 successful stages
  let actions = [ok_action, ok_action, ok_action]
  let result = boot.run_full_sequence(initial, actions)
  case result {
    Ok(final_state) -> {
      // After 3 stages from Stage1, we should be at Stage4
      final_state.current_stage
      |> should.equal(boot.Stage4StartServices)
    }
    Error(_) -> should.fail()
  }
}

pub fn run_full_sequence_fails_midway_test() {
  let initial = boot.start_boot()
  let ok_action = fn(_s) { Ok(boot.BootState(boot.Stage1InitializeSystem, [])) }
  let fail_action = fn(_s) {
    Error(boot.BootError(boot.Stage2LoadConfiguration, "config missing"))
  }

  let actions = [ok_action, fail_action, ok_action]
  let result = boot.run_full_sequence(initial, actions)
  case result {
    Ok(_) -> should.fail()
    Error(err) -> {
      err.reason
      |> should.equal("config missing")
    }
  }
}

pub fn run_full_sequence_empty_actions_test() {
  let initial = boot.start_boot()
  let result = boot.run_full_sequence(initial, [])
  case result {
    Ok(state) -> {
      state.current_stage
      |> should.equal(boot.Stage1InitializeSystem)
    }
    Error(_) -> should.fail()
  }
}

// =============================================================================
// planning/safety_kernel tests
// =============================================================================

pub fn validate_proof_token_valid_test() {
  safety_kernel.validate_proof_token(
    "STAMP-token",
    "update",
    "ai:agent1:gpt4",
    "2025-01-01T00:00:00Z",
    300_000,
  )
  |> should.equal(Ok(Nil))
}

pub fn validate_proof_token_invalid_test() {
  safety_kernel.validate_proof_token(
    "bad-token",
    "update",
    "ai:agent1:gpt4",
    "2025-01-01T00:00:00Z",
    300_000,
  )
  |> should.equal(Error("Invalid proof token: Missing STAMP signature"))
}

pub fn execute_with_rollback_success_test() {
  let snapshot = 10
  let modifier = fn(x) { Ok(x + 5) }
  let safety_check = fn(_x) { Ok(Nil) }

  safety_kernel.execute_with_rollback(snapshot, modifier, safety_check)
  |> should.equal(Ok(15))
}

pub fn execute_with_rollback_safety_violation_test() {
  let snapshot = 10
  let modifier = fn(x) { Ok(x + 100) }
  let safety_check = fn(x) {
    case x > 50 {
      True -> Error("value too high")
      False -> Ok(Nil)
    }
  }

  safety_kernel.execute_with_rollback(snapshot, modifier, safety_check)
  |> should.equal(Error(
    "Safety Violation: value too high. Automatic Rollback triggered.",
  ))
}

pub fn execute_with_rollback_modifier_fails_test() {
  let snapshot = 10
  let modifier = fn(_x) { Error("computation error") }
  let safety_check = fn(_x) { Ok(Nil) }

  safety_kernel.execute_with_rollback(snapshot, modifier, safety_check)
  |> should.equal(Error("Execution Failed: computation error"))
}

// =============================================================================
// planning/enforcer tests
// =============================================================================

fn make_ctx(
  agent: enforcer.AgentType,
  path: String,
  op: String,
  token: option.Option(String),
) -> enforcer.RequestContext {
  enforcer.RequestContext(
    agent_type: agent,
    requested_path: path,
    operation: op,
    timestamp: "2025-01-01T00:00:00Z",
    stack_trace: option.None,
    ip_address: option.None,
    additional_context: dict.new(),
    proof_token: token,
  )
}

pub fn enforcer_human_non_todolist_allowed_test() {
  let ctx =
    make_ctx(enforcer.Human("user1"), "/some/path.md", "read", option.None)
  let result = enforcer.enforce_access(ctx, 0, 5)
  case result {
    enforcer.Allowed(_) -> should.equal(True, True)
    _ -> should.fail()
  }
}

pub fn enforcer_human_todolist_denied_test() {
  let ctx =
    make_ctx(
      enforcer.Human("user1"),
      "/PROJECT_TODOLIST.md",
      "write",
      option.None,
    )
  let result = enforcer.enforce_access(ctx, 0, 5)
  case result {
    enforcer.Denied(reason, _) -> {
      reason
      |> should.equal(
        "SC-TODO-001 VIOLATION: Direct manual modification of PROJECT_TODOLIST.md is strictly PROHIBITED.",
      )
    }
    _ -> should.fail()
  }
}

pub fn enforcer_unknown_agent_todolist_denied_test() {
  let ctx =
    make_ctx(
      enforcer.UnknownAgent("anon"),
      "/PROJECT_TODOLIST.md",
      "write",
      option.None,
    )
  let result = enforcer.enforce_access(ctx, 0, 5)
  case result {
    enforcer.Denied(reason, _) -> {
      reason
      |> should.equal(
        "SC-TODO-001 VIOLATION: Anonymous modification of PROJECT_TODOLIST.md is strictly PROHIBITED.",
      )
    }
    _ -> should.fail()
  }
}

pub fn enforcer_ai_todolist_no_token_denied_test() {
  let ctx =
    make_ctx(
      enforcer.AIAgent("bot1", "gpt4"),
      "/PROJECT_TODOLIST.md",
      "write",
      option.None,
    )
  let result = enforcer.enforce_access(ctx, 0, 5)
  case result {
    enforcer.Denied(reason, _) -> {
      reason
      |> should.equal(
        "SC-TODO-001 VIOLATION: Modification of PROJECT_TODOLIST.md requires a valid Prometheus ProofToken.",
      )
    }
    _ -> should.fail()
  }
}

pub fn enforcer_ai_todolist_valid_token_allowed_test() {
  let ctx =
    make_ctx(
      enforcer.AIAgent("bot1", "gpt4"),
      "/PROJECT_TODOLIST.md",
      "write",
      option.Some("STAMP-token"),
    )
  let result = enforcer.enforce_access(ctx, 0, 5)
  case result {
    enforcer.Allowed(_) -> should.equal(True, True)
    _ -> should.fail()
  }
}

pub fn enforcer_ai_non_todolist_no_token_denied_test() {
  let ctx =
    make_ctx(
      enforcer.AIAgent("bot1", "gpt4"),
      "/other/file.md",
      "read",
      option.None,
    )
  let result = enforcer.enforce_access(ctx, 0, 5)
  case result {
    enforcer.Denied(_, _) -> should.equal(True, True)
    _ -> should.fail()
  }
}

pub fn enforcer_ai_non_todolist_valid_token_allowed_test() {
  let ctx =
    make_ctx(
      enforcer.AIAgent("bot1", "gpt4"),
      "/other/file.md",
      "read",
      option.Some("STAMP-token"),
    )
  let result = enforcer.enforce_access(ctx, 0, 5)
  case result {
    enforcer.Allowed(_) -> should.equal(True, True)
    _ -> should.fail()
  }
}

pub fn enforcer_circuit_open_on_threshold_test() {
  // When violation_count >= threshold, circuit opens regardless of validation
  let ctx =
    make_ctx(
      enforcer.UnknownAgent("anon"),
      "/some/file.md",
      "write",
      option.None,
    )
  let result = enforcer.enforce_access(ctx, 10, 5)
  case result {
    enforcer.CircuitOpen(agent_id, count) -> {
      agent_id
      |> should.equal("unknown:anon")
      count
      |> should.equal(10)
    }
    _ -> should.fail()
  }
}

pub fn enforcer_unknown_agent_non_todolist_denied_test() {
  let ctx =
    make_ctx(
      enforcer.UnknownAgent("anon"),
      "/some/file.md",
      "read",
      option.None,
    )
  let result = enforcer.enforce_access(ctx, 0, 5)
  case result {
    enforcer.Denied(reason, _) -> {
      reason
      |> should.equal("Unknown agents are denied by default")
    }
    _ -> should.fail()
  }
}

pub fn enforcer_system_process_no_token_denied_test() {
  let ctx =
    make_ctx(
      enforcer.SystemProcess("proc1"),
      "/some/file.md",
      "update",
      option.None,
    )
  let result = enforcer.enforce_access(ctx, 0, 5)
  case result {
    enforcer.Denied(_, _) -> should.equal(True, True)
    _ -> should.fail()
  }
}

pub fn enforcer_system_process_with_token_allowed_test() {
  let ctx =
    make_ctx(
      enforcer.SystemProcess("proc1"),
      "/some/file.md",
      "update",
      option.Some("STAMP-token"),
    )
  let result = enforcer.enforce_access(ctx, 0, 5)
  case result {
    enforcer.Allowed(_) -> should.equal(True, True)
    _ -> should.fail()
  }
}

// =============================================================================
// knowledge/domain tests
// =============================================================================

pub fn level_to_string_atomic_test() {
  kdomain.level_to_string(kdomain.Atomic)
  |> should.equal("atomic")
}

pub fn level_to_string_molecular_test() {
  kdomain.level_to_string(kdomain.Molecular)
  |> should.equal("molecular")
}

pub fn level_to_string_organism_test() {
  kdomain.level_to_string(kdomain.Organism)
  |> should.equal("organism")
}

pub fn level_to_string_ecosystem_test() {
  kdomain.level_to_string(kdomain.Ecosystem)
  |> should.equal("ecosystem")
}

pub fn rhetorical_to_string_axiom_test() {
  kdomain.rhetorical_to_string(kdomain.Axiom)
  |> should.equal("axiom")
}

pub fn rhetorical_to_string_hypothesis_test() {
  kdomain.rhetorical_to_string(kdomain.Hypothesis)
  |> should.equal("hypothesis")
}

pub fn rhetorical_to_string_evidence_test() {
  kdomain.rhetorical_to_string(kdomain.Evidence)
  |> should.equal("evidence")
}

// =============================================================================
// knowledge/anomaly tests
// =============================================================================

fn make_node(id: String, entropy: Float, drift: Float) -> kdomain.KnowledgeNode {
  kdomain.KnowledgeNode(
    id: id,
    title: "Node " <> id,
    level: kdomain.Atomic,
    rhetorical: kdomain.Axiom,
    entropy: entropy,
    drift: drift,
    tags: [],
  )
}

pub fn detect_anomalies_no_anomalies_test() {
  let nodes = [make_node("n1", 0.1, 0.1), make_node("n2", 0.2, 0.2)]

  anomaly.detect_anomalies(nodes, 0.5, 0.5)
  |> should.equal([])
}

pub fn detect_anomalies_high_entropy_test() {
  let nodes = [make_node("n1", 0.9, 0.1), make_node("n2", 0.2, 0.1)]

  let result = anomaly.detect_anomalies(nodes, 0.5, 0.5)
  result
  |> should.equal([anomaly.HighEntropy("n1", 0.9)])
}

pub fn detect_anomalies_high_drift_test() {
  let nodes = [make_node("n1", 0.1, 0.8), make_node("n2", 0.1, 0.1)]

  let result = anomaly.detect_anomalies(nodes, 0.5, 0.5)
  result
  |> should.equal([anomaly.HighDrift("n1", 0.8)])
}

pub fn detect_anomalies_both_anomalies_test() {
  let nodes = [make_node("n1", 0.9, 0.8)]

  let result = anomaly.detect_anomalies(nodes, 0.5, 0.5)
  result
  |> should.equal([anomaly.HighEntropy("n1", 0.9), anomaly.HighDrift("n1", 0.8)])
}

pub fn detect_anomalies_multiple_nodes_test() {
  let nodes = [
    make_node("n1", 0.9, 0.1),
    make_node("n2", 0.1, 0.9),
    make_node("n3", 0.1, 0.1),
  ]

  let result = anomaly.detect_anomalies(nodes, 0.5, 0.5)
  result
  |> should.equal([
    anomaly.HighEntropy("n1", 0.9),
    anomaly.HighDrift("n2", 0.9),
  ])
}

pub fn detect_anomalies_empty_list_test() {
  anomaly.detect_anomalies([], 0.5, 0.5)
  |> should.equal([])
}

pub fn detect_anomalies_exact_threshold_not_flagged_test() {
  // Threshold check is strictly greater-than, so equal should NOT flag
  let nodes = [make_node("n1", 0.5, 0.5)]
  anomaly.detect_anomalies(nodes, 0.5, 0.5)
  |> should.equal([])
}

// =============================================================================
// knowledge/semantic tests (dot_product only - magnitude/cosine use FFI sqrt)
// =============================================================================

pub fn dot_product_basic_test() {
  semantic.dot_product([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])
  |> should.equal(32.0)
}

pub fn dot_product_zeros_test() {
  semantic.dot_product([0.0, 0.0], [1.0, 2.0])
  |> should.equal(0.0)
}

pub fn dot_product_single_element_test() {
  semantic.dot_product([3.0], [7.0])
  |> should.equal(21.0)
}

pub fn dot_product_empty_vectors_test() {
  semantic.dot_product([], [])
  |> should.equal(0.0)
}

pub fn dot_product_negative_values_test() {
  semantic.dot_product([1.0, -2.0], [-3.0, 4.0])
  |> should.equal(-11.0)
}
