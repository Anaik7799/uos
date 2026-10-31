//// OTP29 single-pass guarded JSON. Native grammar, decoded strings, unique
//// object members and depth are checked before any envelope projection.
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/types

pub type InspectError {
  InvalidJsonSyntax
  DepthExceeded
  DuplicateKey(String)
  NulByteForbidden
}

@external(erlang, "mcp_stdio_ffi", "mcp_json_strict_inspect")
pub fn native_inspect(raw: String, max_depth: Int) -> Result(value.Value, InspectError)

@external(erlang, "mcp_stdio_ffi", "mcp_json_stream_decode")
pub fn stream_decode(chunks: List(BitArray), max_depth: Int) -> Result(value.Value, InspectError)

pub fn inspect(raw: String, transport: String) -> Result(value.Value, types.ToolError) {
  case native_inspect(raw, 32) {
    Ok(v) -> Ok(v)
    Error(e) -> Error(case e {
      InvalidJsonSyntax -> types.ToolError("INVALID_JSON_SYNTAX", "Invalid JSON syntax", types.NonRetryable)
      DepthExceeded -> types.ToolError(transport <> "_JSON_DEPTH_EXCEEDED", "Frame exceeds maximum JSON nesting depth32", types.NonRetryable)
      DuplicateKey(key) -> types.ToolError("DUPLICATE_JSON_KEY", "duplicate object member '" <> key <> "'", types.NonRetryable)
      NulByteForbidden -> types.ToolError(transport <> "_NUL_BYTE_FORBIDDEN", "Decoded NUL bytes are forbidden", types.NonRetryable)
    })
  }
}

@external(erlang, "mcp_stdio_ffi", "mcp_json_encode_checked")
pub fn encode_checked(fields: List(#(String,value.Value))) -> Result(String,String)

@external(erlang, "mcp_stdio_ffi", "mcp_json_format_checked")
pub fn format_checked(fields: List(#(String,value.Value))) -> Result(String,String)
