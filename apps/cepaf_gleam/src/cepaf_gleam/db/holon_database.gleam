// STAMP: SC-HOLON-002, SC-GLM-CORE-002
// AOR: AOR-HOLON-002, AOR-GLM-005
// Criticality: Level 2 (HIGH) - Holon Database Abstraction
//
// Unified database interface supporting SQLite, DuckDB, Postgres,
// in-memory, Zenoh KV, and hybrid storage backends.

import gleam/json

// =============================================================================
// Types
// =============================================================================

pub type HolonDbType {
  HolonSQLite
  HolonDuckDB
  HolonPostgres
  HolonInMemory
  HolonZenohKV
  HolonHybrid
}

pub type QueryType {
  Select
  Insert
  Update
  Delete
  CreateTable
  DropTable
  AlterTable
  Vacuum
  Checkpoint
  BeginTx
  CommitTx
}

pub type IsolationLevel {
  ReadUncommitted
  ReadCommitted
  RepeatableRead
  Serializable
}

pub type TransactionState {
  TxIdle
  TxActive
  TxCommitted
  TxRolledBack
  TxFailed
}

pub type DatabaseRequest {
  DatabaseRequest(query: String, params: List(String), db_type: HolonDbType)
}

pub type DatabaseResponse {
  DbSuccess(rows_affected: Int)
  DbError(message: String)
  DbRows(data: List(List(String)))
}

pub type HolonDbConfig {
  HolonDbConfig(
    path: String,
    db_type: HolonDbType,
    max_connections: Int,
    wal_mode: Bool,
  )
}

pub type HolonDbStats {
  HolonDbStats(
    total_queries: Int,
    failed_queries: Int,
    avg_latency_ms: Float,
    db_size_bytes: Int,
  )
}

// =============================================================================
// FFI Stubs
// =============================================================================

pub fn open(config: HolonDbConfig) -> Result(String, String) {
  let _ = config
  panic as "NYI: requires SQLite/DuckDB FFI (SC-HOLON-002)"
}

pub fn close(handle: String) -> Result(Nil, String) {
  let _ = handle
  panic as "NYI: requires FFI (SC-HOLON-002)"
}

pub fn execute(
  handle: String,
  query: String,
  params: List(String),
) -> Result(DatabaseResponse, String) {
  let _ = handle
  let _ = query
  let _ = params
  panic as "NYI: requires FFI (SC-HOLON-002)"
}

pub fn query(
  handle: String,
  sql: String,
  params: List(String),
) -> Result(DatabaseResponse, String) {
  let _ = handle
  let _ = sql
  let _ = params
  panic as "NYI: requires FFI (SC-HOLON-002)"
}

pub fn begin_transaction(
  handle: String,
  level: IsolationLevel,
) -> Result(String, String) {
  let _ = handle
  let _ = level
  panic as "NYI: requires FFI (SC-HOLON-002)"
}

pub fn commit(tx_handle: String) -> Result(Nil, String) {
  let _ = tx_handle
  panic as "NYI: requires FFI (SC-HOLON-002)"
}

pub fn rollback(tx_handle: String) -> Result(Nil, String) {
  let _ = tx_handle
  panic as "NYI: requires FFI (SC-HOLON-002)"
}

pub fn get_stats(handle: String) -> Result(HolonDbStats, String) {
  let _ = handle
  panic as "NYI: requires FFI (SC-HOLON-002)"
}

pub fn vacuum(handle: String) -> Result(Nil, String) {
  let _ = handle
  panic as "NYI: requires FFI (SC-HOLON-002)"
}

// =============================================================================
// Pure Helper Functions
// =============================================================================

pub fn db_type_to_string(t: HolonDbType) -> String {
  case t {
    HolonSQLite -> "sqlite"
    HolonDuckDB -> "duckdb"
    HolonPostgres -> "postgres"
    HolonInMemory -> "in_memory"
    HolonZenohKV -> "zenoh_kv"
    HolonHybrid -> "hybrid"
  }
}

pub fn query_type_to_string(t: QueryType) -> String {
  case t {
    Select -> "SELECT"
    Insert -> "INSERT"
    Update -> "UPDATE"
    Delete -> "DELETE"
    CreateTable -> "CREATE TABLE"
    DropTable -> "DROP TABLE"
    AlterTable -> "ALTER TABLE"
    Vacuum -> "VACUUM"
    Checkpoint -> "CHECKPOINT"
    BeginTx -> "BEGIN"
    CommitTx -> "COMMIT"
  }
}

pub fn isolation_to_string(l: IsolationLevel) -> String {
  case l {
    ReadUncommitted -> "READ UNCOMMITTED"
    ReadCommitted -> "READ COMMITTED"
    RepeatableRead -> "REPEATABLE READ"
    Serializable -> "SERIALIZABLE"
  }
}

pub fn tx_state_to_string(s: TransactionState) -> String {
  case s {
    TxIdle -> "idle"
    TxActive -> "active"
    TxCommitted -> "committed"
    TxRolledBack -> "rolled_back"
    TxFailed -> "failed"
  }
}

pub fn default_config(path: String) -> HolonDbConfig {
  HolonDbConfig(
    path: path,
    db_type: HolonSQLite,
    max_connections: 1,
    wal_mode: True,
  )
}

pub fn config_to_json(c: HolonDbConfig) -> json.Json {
  json.object([
    #("path", json.string(c.path)),
    #("db_type", json.string(db_type_to_string(c.db_type))),
    #("max_connections", json.int(c.max_connections)),
    #("wal_mode", json.bool(c.wal_mode)),
  ])
}

pub fn stats_to_json(s: HolonDbStats) -> json.Json {
  json.object([
    #("total_queries", json.int(s.total_queries)),
    #("failed_queries", json.int(s.failed_queries)),
    #("avg_latency_ms", json.float(s.avg_latency_ms)),
    #("db_size_bytes", json.int(s.db_size_bytes)),
  ])
}

pub fn response_to_json(r: DatabaseResponse) -> json.Json {
  case r {
    DbSuccess(rows_affected) ->
      json.object([
        #("type", json.string("success")),
        #("rows_affected", json.int(rows_affected)),
      ])
    DbError(message) ->
      json.object([
        #("type", json.string("error")),
        #("message", json.string(message)),
      ])
    DbRows(data) ->
      json.object([
        #("type", json.string("rows")),
        #("data", json.array(data, fn(row) { json.array(row, json.string) })),
      ])
  }
}
