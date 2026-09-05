import gleam/dynamic.{type Dynamic}

// =============================================================================
// SQLite FFI Definitions
// =============================================================================

pub type DbConnection

@external(erlang, "cepaf_gleam_ffi", "sqlite_open")
pub fn open(path: String) -> Result(DbConnection, String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_exec")
pub fn execute(conn: DbConnection, sql: String) -> Result(Int, String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_q")
pub fn query(
  conn: DbConnection,
  sql: String,
  params: List(Dynamic),
) -> Result(List(List(Dynamic)), String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_close")
pub fn close(conn: DbConnection) -> Nil

/// Ensures the database and its schema are initialized.
pub fn ensure_schema(
  conn: DbConnection,
  schema_sql: String,
) -> Result(Nil, String) {
  case execute(conn, schema_sql) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(e)
  }
}
