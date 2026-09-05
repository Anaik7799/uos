// STAMP: SC-BRIDGE-002, SC-GLM-CORE-002
// AOR: AOR-BRIDGE-002, AOR-GLM-005
// Criticality: Level 2 (HIGH) - Bridge Command Dispatch
//
// Defines the command vocabulary for the F#-Gleam bridge and
// dispatches commands to appropriate subsystem handlers.

import gleam/json

// =============================================================================
// Types
// =============================================================================

pub type BridgeCommand {
  ContainerList
  ContainerStart(name: String)
  ContainerStop(name: String)
  ContainerRestart(name: String)
  ContainerInspect(name: String)
  HealthCheck
  MeshStatus
  OodaRun
  GuardianValidate(operation: String)
  FractalStatus
}

pub type BridgeResponse {
  BridgeOk(data: String)
  BridgeErr(message: String)
}

// =============================================================================
// FFI Stubs
// =============================================================================

pub fn dispatch(cmd: BridgeCommand) -> Result(BridgeResponse, String) {
  let _ = cmd
  panic as "NYI: requires Podman/Zenoh FFI (SC-BRIDGE-002)"
}

pub fn dispatch_json(raw_json: String) -> Result(String, String) {
  let _ = raw_json
  panic as "NYI: requires JSON parse + dispatch (SC-BRIDGE-002)"
}

// =============================================================================
// Pure Helper Functions
// =============================================================================

pub fn command_to_string(cmd: BridgeCommand) -> String {
  case cmd {
    ContainerList -> "container.list"
    ContainerStart(name) -> "container.start:" <> name
    ContainerStop(name) -> "container.stop:" <> name
    ContainerRestart(name) -> "container.restart:" <> name
    ContainerInspect(name) -> "container.inspect:" <> name
    HealthCheck -> "health.check"
    MeshStatus -> "mesh.status"
    OodaRun -> "ooda.run"
    GuardianValidate(op) -> "guardian.validate:" <> op
    FractalStatus -> "fractal.status"
  }
}

pub fn parse_command(method: String) -> Result(BridgeCommand, String) {
  case method {
    "container.list" -> Ok(ContainerList)
    "health.check" -> Ok(HealthCheck)
    "mesh.status" -> Ok(MeshStatus)
    "ooda.run" -> Ok(OodaRun)
    "fractal.status" -> Ok(FractalStatus)
    _ -> Error("Unknown command: " <> method)
  }
}

pub fn response_to_json(r: BridgeResponse) -> json.Json {
  case r {
    BridgeOk(data) ->
      json.object([
        #("status", json.string("ok")),
        #("data", json.string(data)),
      ])
    BridgeErr(message) ->
      json.object([
        #("status", json.string("error")),
        #("message", json.string(message)),
      ])
  }
}

pub fn all_commands() -> List(String) {
  [
    "container.list",
    "container.start",
    "container.stop",
    "container.restart",
    "container.inspect",
    "health.check",
    "mesh.status",
    "ooda.run",
    "guardian.validate",
    "fractal.status",
  ]
}
