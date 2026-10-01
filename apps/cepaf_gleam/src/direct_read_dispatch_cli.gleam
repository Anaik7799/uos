//// =============================================================================
//// [C3I-SIL6-MSTS] Direct Bounded Read Dispatch CLI (SC-JIDOKA-001, SC-COG-001)
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>direct_read_dispatch_cli</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L4_TRANSPORT</layer>
////     <topology>Local Process CLI Entrypoint for Direct Bounded Read Dispatch</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-JIDOKA-001, SC-SA-PLAN-001, SC-COG-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/harness/direct_read_dispatch as direct
import cepaf_gleam/harness/tool_fenced_dispatcher as td
import gleam/io
import gleam/json

@external(erlang, "cepaf_gleam_ffi", "get_arguments")
fn get_arguments() -> List(String)

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

pub fn main() {
  let args = get_arguments()
  case args {
    ["--help"] -> {
      io.println(
        "Usage: direct_read_dispatch_cli <tool_name> [args_json] [call_id]\n\n"
        <> "Tools:\n"
        <> "  query_doctor  - Truthful health & EV-93 provenance projection\n"
        <> "  query_saplan  - Truthful sanitized task counts & states for bound plan\n\n"
        <> "Arguments:\n"
        <> "  args_json     - Strictly requires empty JSON object '{}' (defaults to '{}' if omitted).\n"
        <> "                  JSON whitespace is permitted (e.g. '{ }'), but blank/primitives/arrays are rejected.\n"
        <> "  call_id       - Optional caller ID (1..64 chars, defaults to 'cli-<tool_name>').\n\n"
        <> "Mandatory Launcher Environment Variables (all 7 required, zero fallback):\n"
        <> "  UOS_DIRECT_ROLE=direct_read  (strictly requires 'direct_read')\n"
        <> "  UOS_DIRECT_PLAN              (canonical Sa-plan ID, e.g. uos/direct-dispatch/20261001-0440)\n"
        <> "  UOS_DIRECT_TASK              (executing task ID, e.g. AGY_FIX)\n"
        <> "  UOS_DIRECT_WORKER            (assigned worker identity)\n"
        <> "  UOS_DIRECT_ATTEMPT           (positive integer attempt number)\n"
        <> "  UOS_DIRECT_SESSION           (coordinator session holding lease)\n"
        <> "  UOS_DIRECT_EPOCH             (coordinator epoch integer >= 1)\n\n"
        <> "Practical Invocation Example:\n"
        <> "  export UOS_DIRECT_ROLE=\"direct_read\"\n"
        <> "  export UOS_DIRECT_PLAN=\"uos/direct-dispatch/20261001-0440\"\n"
        <> "  export UOS_DIRECT_TASK=\"AGY_FIX\"\n"
        <> "  export UOS_DIRECT_WORKER=\"agy-direct-dispatch-20261001\"\n"
        <> "  export UOS_DIRECT_ATTEMPT=\"1\"\n"
        <> "  export UOS_DIRECT_SESSION=\"codex-direct-dispatch-20261001\"\n"
        <> "  export UOS_DIRECT_EPOCH=\"1\"\n"
        <> "  erl +S 2:2 +A 2 -noshell -pa build/dev/erlang/*/ebin -eval 'direct_read_dispatch_cli:main()' -- query_doctor\n",
      )
      halt(0)
    }

    [tool_name] -> execute_cli(tool_name, "{}", "cli-" <> tool_name)

    [tool_name, args_json] ->
      execute_cli(tool_name, args_json, "cli-" <> tool_name)

    [tool_name, args_json, call_id] ->
      execute_cli(tool_name, args_json, call_id)

    _ -> {
      io.println(
        json.object([
          #("status", json.string("error")),
          #(
            "message",
            json.string(
              "Invalid CLI arguments. Run with --help for usage information.",
            ),
          ),
        ])
        |> json.to_string,
      )
      halt(1)
    }
  }
}

fn execute_cli(tool_name: String, args_json: String, call_id: String) {
  let proposal = td.ToolProposal(call_id, tool_name, args_json)
  let outcome = direct.dispatch(proposal)
  case outcome {
    td.Dispatched(id, name, result_json) -> {
      io.println(
        json.object([
          #("status", json.string("dispatched")),
          #("call_id", json.string(id)),
          #("tool_name", json.string(name)),
          #("result", json.string(result_json)),
        ])
        |> json.to_string,
      )
      halt(0)
    }

    td.FencedAndonHalt(code, reason) -> {
      io.println(
        json.object([
          #("status", json.string("andon_halt")),
          #("code", json.int(code)),
          #("reason", json.string(reason)),
        ])
        |> json.to_string,
      )
      halt(1)
    }
  }
}
