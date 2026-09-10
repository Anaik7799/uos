//// =============================================================================
//// [C3I-SIL6-MSTS] UOS Tool Fenced Dispatcher (SC-JIDOKA-001, SC-COG-001)
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/harness/tool_fenced_dispatcher</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <topology>Fail-Closed Monotonic Fencing Dispatcher for Model Tool Proposals</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-JIDOKA-001, SC-SA-PLAN-001, SC-COG-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const andon_halt_unauthorized_code: Int = -32_002
pub const andon_halt_quorum_missing_code: Int = -32_003

pub type ToolProposal {
  ToolProposal(call_id: String, tool_name: String, args_json: String)
}

pub type FencingLease {
  FencingLease(
    worker: String,
    plan_id: String,
    task_id: String,
    fencing_token: Int,
    lease_until_ns: Int,
  )
}

pub type DispatchOutcome {
  Dispatched(call_id: String, tool_name: String, result_json: String)
  FencedAndonHalt(code: Int, reason: String)
}

/// Mutating operations that strictly require 2oo3 constitutional consensus.
pub fn is_mutating_tool(tool_name: String) -> Bool {
  case tool_name {
    "resuscitate_node" | "chaos_inject" | "rotate_keys" | "storage_rebalance" ->
      True
    _ -> False
  }
}

/// Parse tool proposal from raw JSON (as emitted by Gemma 4 / OpenAI compatible function call).
pub fn parse_tool_proposal(raw_json: String) -> Result(ToolProposal, String) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use function_obj <- decode.field("function", {
      use name <- decode.field("name", decode.string)
      use arguments <- decode.field("arguments", decode.string)
      decode.success(#(name, arguments))
    })
    let #(name, args) = function_obj
    decode.success(ToolProposal(id, name, args))
  }

  json.parse(raw_json, decoder)
  |> result.replace_error("invalid_tool_proposal_json")
}

/// Fenced dispatch interceptor. Models propose actions; only authenticated,
/// leased, and quorum-cleared callers can execute side effects.
pub fn dispatch_fenced_proposal(
  proposal: ToolProposal,
  lease_opt: Option(FencingLease),
  current_time_ns: Int,
  quorum_approved: Bool,
  authority_verified: Bool,
  execution_fn: fn(String, String) -> Result(String, String),
) -> DispatchOutcome {
  case lease_opt {
    None ->
      FencedAndonHalt(
        andon_halt_unauthorized_code,
        "Fractal Jidoka Andon Halt: Non-sa-plan task execution attempted. SC-JIDOKA-001 forbids ad-hoc un-ledgered plan execution.",
      )

    Some(lease) -> {
      // Validate canonical lease authority first (L3: reject invented/caller-supplied leases)
      case authority_verified {
        False ->
          FencedAndonHalt(
            andon_halt_unauthorized_code,
            "Fractal Jidoka Andon Halt: Unverified lease authority. Caller-supplied lease lacks canonical Sa-plan proof.",
          )
        True -> {
          // Validate lease parameters
          case
            string.trim(lease.worker) != "",
            lease.fencing_token > 0,
            lease.lease_until_ns > current_time_ns
          {
            False, _, _ ->
              FencedAndonHalt(
                andon_halt_unauthorized_code,
                "Invalid worker identity in sa-plan lease.",
              )
            _, False, _ ->
              FencedAndonHalt(
                andon_halt_unauthorized_code,
                "Non-positive fencing token rejected.",
              )
            _, _, False ->
              FencedAndonHalt(
                andon_halt_unauthorized_code,
                "Expired sa-plan lease token.",
              )
            True, True, True -> {
              // Check mutating operation quorum requirement
              case is_mutating_tool(proposal.tool_name), quorum_approved {
                True, False ->
                  FencedAndonHalt(
                    andon_halt_quorum_missing_code,
                    "Constitutional Quorum Violation: Mutating tool '"
                      <> proposal.tool_name
                      <> "' requires 2oo3 consensus before execution.",
                  )
                _, _ -> {
                  case execution_fn(proposal.tool_name, proposal.args_json) {
                    Ok(output_json) ->
                      Dispatched(proposal.call_id, proposal.tool_name, output_json)
                    Error(err) ->
                      FencedAndonHalt(
                        -32_000,
                        "Tool execution internal error: " <> err,
                      )
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Serialize tool return message for conversation history in OpenRouter format.
pub fn format_tool_return_message(
  call_id: String,
  tool_name: String,
  content: String,
) -> json.Json {
  json.object([
    #("role", json.string("tool")),
    #("tool_call_id", json.string(call_id)),
    #("name", json.string(tool_name)),
    #("content", json.string(content)),
  ])
}
