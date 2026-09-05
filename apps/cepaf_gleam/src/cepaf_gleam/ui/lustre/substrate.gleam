/// Lustre component for Substrate plane (SC-GLM-UI-001).
/// Manages governor actions, DB connections, and file operations.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import gleam/list
import gleam/option.{type Option, None, Some}

pub type SubstrateModel {
  SubstrateModel(
    governor_action: Option(GovernorAction),
    db_connections: List(DbConnection),
    file_ops: List(FileOp),
  )
}

pub type GovernorAction {
  GovernorAction(name: String, state: String, timestamp: Int)
}

pub type DbConnection {
  DbConnection(id: String, database: String, status: String, latency_ms: Int)
}

pub type FileOp {
  FileOp(path: String, operation: String, status: String, timestamp: Int)
}

pub type SubstrateMsg {
  GovernorUpdated(GovernorAction)
  DbStatsReceived(List(DbConnection))
  RefreshSubstrate
}

pub fn init() -> SubstrateModel {
  SubstrateModel(governor_action: None, db_connections: [], file_ops: [])
}

pub fn update(model: SubstrateModel, msg: SubstrateMsg) -> SubstrateModel {
  case msg {
    GovernorUpdated(action) ->
      SubstrateModel(..model, governor_action: Some(action))
    DbStatsReceived(conns) -> SubstrateModel(..model, db_connections: conns)
    RefreshSubstrate -> model
  }
}

pub fn active_connections(model: SubstrateModel) -> List(DbConnection) {
  list.filter(model.db_connections, fn(c) { c.status == "active" })
}

pub fn connection_count(model: SubstrateModel) -> Int {
  list.length(model.db_connections)
}
