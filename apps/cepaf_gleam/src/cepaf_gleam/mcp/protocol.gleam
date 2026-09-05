import gleam/json.{type Json}
import gleam/option.{type Option}

pub type McpRequest {
  McpRequest(method: String, params: Option(Json), id: Option(String))
}

pub type McpResponse {
  McpResponse(
    jsonrpc: String,
    result: Option(Json),
    error: Option(McpError),
    id: Option(String),
  )
}

pub type McpError {
  McpError(code: Int, message: String, data: Option(Json))
}

pub type ToolDefinition {
  ToolDefinition(name: String, description: String, input_schema: Json)
}
