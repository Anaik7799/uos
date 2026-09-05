import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

pub type DbConnection

pub type DbType {
  SQLite
  DuckDB
}

pub type DbMessage {
  Query(
    sql: String,
    params: List(Dynamic),
    reply_to: Subject(Result(List(Dynamic), String)),
  )
  Execute(sql: String, reply_to: Subject(Result(Int, String)))
  Shutdown
}

pub type DbState {
  DbState(conn: DbConnection, db_type: DbType, path: String)
}

@external(erlang, "cepaf_gleam_ffi", "sqlite_open")
fn sqlite_open(path: String) -> Result(DbConnection, String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_exec")
fn sqlite_exec(conn: DbConnection, sql: String) -> Result(Int, String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_q")
fn sqlite_q(
  conn: DbConnection,
  sql: String,
  params: List(Dynamic),
) -> Result(List(Dynamic), String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_close")
fn sqlite_close(conn: DbConnection) -> Nil

@external(erlang, "cepaf_gleam_ffi", "duckdb_open")
fn duckdb_open(path: String) -> Result(DbConnection, String)

@external(erlang, "cepaf_gleam_ffi", "duckdb_connection")
fn duckdb_connection(db: DbConnection) -> Result(DbConnection, String)

@external(erlang, "cepaf_gleam_ffi", "duckdb_query")
fn duckdb_query(conn: DbConnection, sql: String) -> Result(DbConnection, String)

@external(erlang, "cepaf_gleam_ffi", "duckdb_fetch_all")
fn duckdb_fetch_all(res: DbConnection) -> Result(List(Dynamic), String)

pub fn start(
  path: String,
  db_type: DbType,
) -> Result(Subject(DbMessage), String) {
  let conn_res = case db_type {
    SQLite -> sqlite_open(path)
    DuckDB -> {
      case duckdb_open(path) {
        Ok(db) -> duckdb_connection(db)
        Error(e) -> Error(e)
      }
    }
  }

  case conn_res {
    Ok(conn) -> {
      case db_type {
        SQLite -> {
          let _ =
            sqlite_exec(
              conn,
              "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;",
            )
          Nil
        }
        DuckDB -> Nil
      }

      let res =
        actor.new(DbState(conn: conn, db_type: db_type, path: path))
        |> actor.on_message(handle_message)
        |> actor.start()

      case res {
        Ok(started) -> Ok(started.data)
        Error(_) -> Error("Failed to start database actor")
      }
    }
    Error(e) -> Error(e)
  }
}

fn handle_message(
  state: DbState,
  message: DbMessage,
) -> actor.Next(DbState, DbMessage) {
  case message {
    Query(sql, params, reply_to) -> {
      let res = case state.db_type {
        SQLite -> sqlite_q(state.conn, sql, params)
        DuckDB -> {
          // Duckdbex currently doesn't support parameterized queries easily via this FFI
          // For now we assume simple queries or handle interpolation elsewhere
          case duckdb_query(state.conn, sql) {
            Ok(result_set) -> duckdb_fetch_all(result_set)
            Error(e) -> Error(e)
          }
        }
      }
      process.send(reply_to, res)
      actor.continue(state)
    }
    Execute(sql, reply_to) -> {
      let res = case state.db_type {
        SQLite -> sqlite_exec(state.conn, sql)
        DuckDB -> {
          case duckdb_query(state.conn, sql) {
            Ok(_) -> Ok(0)
            Error(e) -> Error(e)
          }
        }
      }
      process.send(reply_to, res)
      actor.continue(state)
    }
    Shutdown -> {
      case state.db_type {
        SQLite -> sqlite_close(state.conn)
        DuckDB -> Nil
        // Duckdbex handles GC
      }
      actor.stop()
    }
  }
}

pub fn query(
  hub: Subject(DbMessage),
  sql: String,
  params: List(Dynamic),
  timeout_ms: Int,
) -> Result(List(Dynamic), String) {
  process.call(hub, timeout_ms, Query(sql, params, _))
}

pub fn execute(
  hub: Subject(DbMessage),
  sql: String,
  timeout_ms: Int,
) -> Result(Int, String) {
  process.call(hub, timeout_ms, Execute(sql, _))
}
