//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/prajna/orchestrator_cmd</module>
////   <fsharp-lineage>Cepaf.Prajna.OrchestratorCmd</fsharp-lineage></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology></c3i-module>

pub type PrajnaCommandType {
  StatusCmd
  StartCmd
  StopCmd
  RestartCmd
  ScaleCmd(replicas: Int)
}

pub type PrajnaCommandStatus {
  Created
  Armed
  Executing
  PrajnaCompleted
  PrajnaFailed(reason: String)
}

pub type PrajnaCommand {
  PrajnaCommand(
    id: String,
    command_type: PrajnaCommandType,
    target: String,
    status: PrajnaCommandStatus,
    issued_by: String,
    armed_by: String,
    timestamp: String,
  )
}

pub fn requires_two_key(cmd_type: PrajnaCommandType) -> Bool {
  case cmd_type {
    StopCmd -> True
    RestartCmd -> True
    ScaleCmd(_) -> True
    StatusCmd -> False
    StartCmd -> False
  }
}

pub fn create_command(
  id: String,
  command_type: PrajnaCommandType,
  target: String,
  issued_by: String,
  timestamp: String,
) -> PrajnaCommand {
  PrajnaCommand(
    id: id,
    command_type: command_type,
    target: target,
    status: Created,
    issued_by: issued_by,
    armed_by: "",
    timestamp: timestamp,
  )
}

pub fn arm(
  cmd: PrajnaCommand,
  armed_by: String,
) -> Result(PrajnaCommand, String) {
  case cmd.status {
    Created ->
      case requires_two_key(cmd.command_type) {
        True ->
          case armed_by == cmd.issued_by {
            True -> Error("Two-key commands require different operators")
            False -> Ok(PrajnaCommand(..cmd, status: Armed, armed_by: armed_by))
          }
        False -> Ok(PrajnaCommand(..cmd, status: Armed, armed_by: armed_by))
      }
    _ -> Error("Can only arm a Created command")
  }
}

pub fn confirm(cmd: PrajnaCommand) -> Result(PrajnaCommand, String) {
  case cmd.status {
    Armed -> Ok(PrajnaCommand(..cmd, status: Executing))
    _ -> Error("Can only confirm an Armed command")
  }
}

pub fn complete(
  cmd: PrajnaCommand,
  success: Bool,
  reason: String,
) -> PrajnaCommand {
  case success {
    True -> PrajnaCommand(..cmd, status: PrajnaCompleted)
    False -> PrajnaCommand(..cmd, status: PrajnaFailed(reason))
  }
}
