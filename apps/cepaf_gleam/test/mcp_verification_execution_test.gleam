import cepaf_gleam/mcp/adapters/verification
import cepaf_gleam/mcp/dispatch
import cepaf_gleam/mcp/supervisor as mcp_sup
import cepaf_gleam/mcp/types.{Complete, NonRetryable, Refused}
import gleam/list
import gleam/string
import gleeunit/should

pub fn nonzero_exit_never_returns_verified_test() {
  let outcome =
    verification.execute_verification(
      "verification_run",
      "gleam_check",
      "uos-mcp",
      fn(_check) { verification.CheckExecuted(1, "all tests passed", 5) },
    )
  case outcome {
    Refused(error) -> {
      error.code |> should.equal("VERIFICATION_CHECK_FAILED")
      string.contains(error.reason, "exit_code=1") |> should.be_true()
    }
    Complete(_, _) -> should.fail()
    _ -> should.fail()
  }
}

pub fn missing_prover_is_unrun_test() {
  let outcome =
    verification.execute_verification(
      "run_gate",
      "bounded_z3_control",
      "uos-mcp",
      fn(_check) { verification.ProverMissing("z3") },
    )
  case outcome {
    Refused(error) -> {
      error.code |> should.equal("PROVER_UNRUN_MISSING_TOOL")
      string.contains(error.reason, "formal_state=unrun") |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn failed_check_does_not_poison_next_worker_test() {
  let assert Ok(pool) = mcp_sup.start_worker_pool(size: 2)
  let initial_generation = mcp_sup.active_worker_generation(pool)

  // A failed verification check is a normal refusal, never a worker crash.
  let failed =
    verification.execute_verification(
      "run_gate",
      "gate_journal",
      "uos-mcp",
      fn(_check) { verification.CheckExecuted(1, "FAIL", 3) },
    )
  case failed {
    Refused(error) -> error.code |> should.equal("VERIFICATION_CHECK_FAILED")
    _ -> should.fail()
  }

  let #(outcome, pool_after) =
    dispatch.execute_on_pool(
      pool,
      route: "public",
      tool: "plan_status",
      intent_id: "after-failed-check-01",
      simulate: dispatch.SimulateSuccess("{\"status\":\"ok\"}"),
    )
  case outcome {
    Complete(value, _) -> value |> should.equal("{\"status\":\"ok\"}")
    _ -> should.fail()
  }
  mcp_sup.active_worker_generation(pool_after)
  |> should.equal(initial_generation)
}

pub fn disallowed_check_id_shell_injection_refused_test() {
  let malicious = ["; rm -rf /", "$(whoami)", "`id`", "sh -c echo"]
  list.each(malicious, fn(check_raw) {
    let outcome =
      verification.execute_verification(
        "verification_run",
        check_raw,
        "uos-mcp",
        fn(_check) { verification.CheckExecuted(0, "ok", 1) },
      )
    case outcome {
      Refused(error) -> {
        error.code |> should.equal("DISALLOWED_CHECK_ID")
        error.retryability |> should.equal(NonRetryable)
      }
      _ -> should.fail()
    }
  })
}

pub fn output_and_exit_agree_test() {
  let outcome =
    verification.execute_verification(
      "preflight_check",
      "preflight_toolchain",
      "uos-mcp",
      fn(_check) { verification.CheckExecuted(0, "all checks passed", 7) },
    )
  case outcome {
    Complete(payload, evidence) -> {
      evidence.execution_state |> should.equal("observed")
      string.contains(payload, "\"verified\":true") |> should.be_true()
    }
    _ -> should.fail()
  }

  // Exit code 0 plus failure text in output is disagreement: never Complete.
  let disagreement =
    verification.execute_verification(
      "preflight_check",
      "preflight_toolchain",
      "uos-mcp",
      fn(_check) { verification.CheckExecuted(0, "FAIL: toolchain missing", 7) },
    )
  case disagreement {
    Refused(error) -> error.code |> should.equal("OUTPUT_EXIT_DISAGREEMENT")
    _ -> should.fail()
  }
}
