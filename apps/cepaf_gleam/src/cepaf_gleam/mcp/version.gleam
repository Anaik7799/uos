//// T15 Protocol version negotiation. Only exact supported versions are
//// accepted; there is no silent downgrade to a legacy profile.

import cepaf_gleam/mcp/types.{
  type ProtocolProfile, type ToolError, Legacy20241105, Modern20260728,
  NonRetryable, ToolError,
}

pub const legacy_version = "2024-11-05"
pub const modern_version = "2026-07-28"

pub fn negotiate(version: String) -> Result(ProtocolProfile, ToolError) {
  case version {
    "2024-11-05" -> Ok(Legacy20241105)
    "2026-07-28" -> Ok(Modern20260728)
    _ ->
      Error(ToolError(
        code: "UNSUPPORTED_PROTOCOL_VERSION",
        reason: "No silent downgrade; unsupported MCP protocol version: "
          <> version,
        retryability: NonRetryable,
      ))
  }
}
