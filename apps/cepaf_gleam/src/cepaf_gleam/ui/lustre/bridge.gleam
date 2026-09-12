/// Lustre component for Bridge/MCP plane (SC-GLM-UI-001).
/// Tracks JSON-RPC methods, command implementation progress.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import gleam/int
import gleam/list

pub type GatewayDispatch {
  GatewayDispatch(channel: String, text: String, timestamp: String, status: String)
}

pub type BridgeModel {
  BridgeModel(
    jsonrpc_methods: List(String),
    commands_total: Int,
    commands_implemented: Int,
    commands_stub: Int,
    // P3-7: Gateway approval dispatch history
    gateway_history: List(GatewayDispatch),
  )
}

pub type BridgeMsg {
  CommandExecuted(String)
  MethodCalled(String)
  RefreshBridge
}

pub fn init() -> BridgeModel {
  BridgeModel(
    jsonrpc_methods: [],
    commands_total: 0,
    gateway_history: [],
    commands_implemented: 0,
    commands_stub: 0,
  )
}

pub fn update(model: BridgeModel, msg: BridgeMsg) -> BridgeModel {
  case msg {
    CommandExecuted(_cmd) ->
      BridgeModel(..model, commands_implemented: model.commands_implemented + 1)
    MethodCalled(method) ->
      case list.contains(model.jsonrpc_methods, method) {
        True -> model
        False ->
          BridgeModel(..model, jsonrpc_methods: [
            method,
            ..model.jsonrpc_methods
          ])
      }
    RefreshBridge -> model
  }
}

pub fn implementation_percent(model: BridgeModel) -> Float {
  case model.commands_total {
    0 -> 0.0
    _ ->
      int.to_float(model.commands_implemented)
      /. int.to_float(model.commands_total)
      *. 100.0
  }
}

pub fn most_used_command(model: BridgeModel) -> String {
  case model.jsonrpc_methods {
    [first, ..] -> first
    [] -> "none"
  }
}
