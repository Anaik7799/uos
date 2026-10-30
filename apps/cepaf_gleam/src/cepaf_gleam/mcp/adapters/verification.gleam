//// Verification Gate Family Adapter (4 tools): verification_run, run_selfcheck,
//// run_gate, preflight_check. Uses a closed CheckId allowlist so arbitrary
//// command strings are rejected fail-closed; missing provers stay formally
//// unrun and output/exit disagreement can never be reported as Complete.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/types.{
  type Outcome, Complete, EvidenceRecord, NonRetryable, Refused, Retryable,
  type ToolError, ToolError,
}
import gleam/int
import gleam/json
import gleam/list
import gleam/string

pub type CheckId {
  GleamCheck
  VfsSelfCheck
  GateJournal
  GateDiagram
  GateChecklist
  PreflightToolchain
  BoundedZ3Control
}

pub type CheckRunnerResult {
  CheckExecuted(exit_code: Int, stdout: String, duration_ms: Int)
  ProverMissing(prover_name: String)
  CheckTimedOut(budget_ms: Int)
}

pub const verification_tools = [
  "verification_run",
  "run_selfcheck",
  "run_gate",
  "preflight_check",
]

pub fn is_verification_tool(tool_name: String) -> Bool {
  list.contains(verification_tools, tool_name)
}

pub fn parse_check_id(raw: String) -> Result(CheckId, ToolError) {
  case string.trim(raw) {
    "gleam_check" -> Ok(GleamCheck)
    "vfs_self_check" -> Ok(VfsSelfCheck)
    "gate_journal" -> Ok(GateJournal)
    "gate_diagram" -> Ok(GateDiagram)
    "gate_checklist" -> Ok(GateChecklist)
    "preflight_toolchain" -> Ok(PreflightToolchain)
    "bounded_z3_control" -> Ok(BoundedZ3Control)
    other ->
      Error(ToolError(
        "DISALLOWED_CHECK_ID",
        "Check id is not in the closed allowlist: " <> other,
        NonRetryable,
      ))
  }
}

pub fn execute_verification(
  tool_name: String,
  check_raw: String,
  candidate: String,
  runner: fn(CheckId) -> CheckRunnerResult,
) -> Outcome {
  case is_verification_tool(tool_name) {
    False ->
      Refused(ToolError(
        "UNSUPPORTED_VERIFICATION_TOOL",
        "Unsupported tool in verification adapter: " <> tool_name,
        NonRetryable,
      ))
    True ->
      case parse_check_id(check_raw) {
        Error(error) -> Refused(error)
        Ok(check_id) ->
          case runner(check_id) {
            ProverMissing(prover_name) ->
              Refused(ToolError(
                "PROVER_UNRUN_MISSING_TOOL",
                "Missing prover: " <> prover_name <> " (formal_state=unrun)",
                NonRetryable,
              ))
            CheckTimedOut(budget_ms) ->
              Refused(ToolError(
                "VERIFICATION_TIMEOUT",
                "Verification check exceeded budget_ms="
                  <> int.to_string(budget_ms),
                Retryable,
              ))
            CheckExecuted(exit_code, stdout, duration_ms) ->
              classify_execution(
                tool_name,
                check_id,
                candidate,
                exit_code,
                stdout,
                duration_ms,
              )
          }
      }
  }
}

fn classify_execution(
  tool_name: String,
  check_id: CheckId,
  candidate: String,
  exit_code: Int,
  stdout: String,
  duration_ms: Int,
) -> Outcome {
  case exit_code != 0 {
    True ->
      Refused(ToolError(
        "VERIFICATION_CHECK_FAILED",
        "Check exited non-zero (exit_code=" <> int.to_string(exit_code) <> ")",
        NonRetryable,
      ))
    False ->
      case output_disagrees(stdout) {
        True ->
          Refused(ToolError(
            "OUTPUT_EXIT_DISAGREEMENT",
            "Exit code 0 disagrees with failure text in output",
            NonRetryable,
          ))
        False -> {
          let bounded = bound_stdout(stdout)
          let payload =
            json.object([
              #("tool", json.string(tool_name)),
              #("check_id", json.string(check_id_name(check_id))),
              #("exit_code", json.int(exit_code)),
              #("duration_ms", json.int(duration_ms)),
              #("stdout", json.string(bounded)),
              #("stdout_truncated", json.bool(bounded != stdout)),
              #("verified", json.bool(True)),
              #("execution_state", json.string("observed")),
            ])
            |> json.to_string
          Complete(
            payload,
            EvidenceRecord(
              candidate: candidate,
              route: "public",
              tool: tool_name,
              declaration_state: "declared",
              implementation_state: "implemented",
              execution_state: "observed",
              formal_state: formal_state_for(check_id),
              admission_state: "not_admitted",
              output_sha256: files.digest(payload),
            ),
          )
        }
      }
  }
}

fn output_disagrees(stdout: String) -> Bool {
  string.contains(stdout, "FAIL") || string.contains(stdout, "ERROR:")
}

fn bound_stdout(output: String) -> String {
  case string.length(output) > 2000 {
    True -> string.slice(output, 0, 2000) <> "\n...[truncated]"
    False -> output
  }
}

fn check_id_name(check_id: CheckId) -> String {
  case check_id {
    GleamCheck -> "gleam_check"
    VfsSelfCheck -> "vfs_self_check"
    GateJournal -> "gate_journal"
    GateDiagram -> "gate_diagram"
    GateChecklist -> "gate_checklist"
    PreflightToolchain -> "preflight_toolchain"
    BoundedZ3Control -> "bounded_z3_control"
  }
}

fn formal_state_for(check_id: CheckId) -> String {
  case check_id {
    BoundedZ3Control -> "verified"
    _ -> "unrun"
  }
}
