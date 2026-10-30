//// Evidence classification and four-state separation (declaration, implementation,
//// observed execution, formal verification, and admission).

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/types.{
  type EvidenceRecord, type Outcome, Complete, EvidenceRecord, NonRetryable,
  Refused, ToolError,
}
import gleam/dynamic/decode
import gleam/json
import gleam/string

pub fn classify_backend_payload(
  route: String,
  tool: String,
  payload: String,
  candidate: String,
) -> Outcome {
  let trimmed = string.trim(payload)
  case is_nested_jsonrpc_error(trimmed) {
    True ->
      Refused(ToolError(
        "NESTED_JSONRPC_ERROR",
        "Backend returned nested JSON-RPC error envelope",
        NonRetryable,
      ))
    False ->
      case is_unavailable_payload(trimmed) {
        True ->
          Refused(ToolError("TOOL_UNAVAILABLE", trimmed, NonRetryable))
        False ->
          case is_backend_error_payload(trimmed) {
            True ->
              Refused(ToolError("BACKEND_ERROR", trimmed, NonRetryable))
            False ->
              Complete(
                payload,
                EvidenceRecord(
                  candidate: candidate,
                  route: route,
                  tool: tool,
                  declaration_state: "declared",
                  implementation_state: "implemented",
                  execution_state: "observed",
                  formal_state: "unrun",
                  admission_state: "not_admitted",
                  output_sha256: files.digest(payload),
                ),
              )
          }
      }
  }
}

fn is_nested_jsonrpc_error(text: String) -> Bool {
  let decoder = {
    use _ <- decode.field("jsonrpc", decode.string)
    use _ <- decode.field("error", decode.dynamic)
    decode.success(True)
  }
  case json.parse(text, decoder) {
    Ok(True) -> True
    _ -> False
  }
}

fn is_unavailable_payload(text: String) -> Bool {
  string.starts_with(text, "UNAVAILABLE:")
  || string.contains(text, "\"status\":\"UNAVAILABLE\"")
}

fn is_backend_error_payload(text: String) -> Bool {
  let error_decoder = {
    use _ <- decode.field("error", decode.dynamic)
    decode.success(True)
  }
  let ok_decoder = {
    use ok <- decode.field("ok", decode.bool)
    decode.success(!ok)
  }
  let status_decoder = {
    use status <- decode.field("status", decode.string)
    decode.success(string.lowercase(status) == "error")
  }
  case
    json.parse(text, error_decoder),
    json.parse(text, ok_decoder),
    json.parse(text, status_decoder)
  {
    Ok(True), _, _ | _, Ok(True), _ | _, _, Ok(True) -> True
    _, _, _ -> False
  }
}
