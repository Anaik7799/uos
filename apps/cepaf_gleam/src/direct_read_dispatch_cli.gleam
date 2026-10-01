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
        "Usage: direct_read_dispatch_cli <tool_name> [args_json] [call_id]\n"
        <> "  Tools: query_doctor, query_saplan\n"
        <> "  Strictly requires empty JSON object '{}' as arguments.\n"
        <> "  Launcher environment required: UOS_DIRECT_PLAN, UOS_DIRECT_TASK, UOS_DIRECT_WORKER, UOS_DIRECT_ATTEMPT, UOS_DIRECT_SESSION, UOS_DIRECT_EPOCH",
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
