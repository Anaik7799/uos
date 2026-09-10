//// =============================================================================
//// [C3I-SIL6-MSTS] UOS Conversation Memory Subsystem (SC-COG-001, SC-STATE-001)
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/harness/conversation_memory</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <topology>Durable Multi-Turn Telegram Conversation Memory</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-COG-001, SC-STATE-001, SC-DRIVE-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/harness/egress_redactor
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

pub const default_db_path: String = "var/telegram/state.sqlite3"

pub type SqliteConn

@external(erlang, "cepaf_gleam_ffi", "sqlite_open")
fn sqlite_open(path: String) -> Result(SqliteConn, String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_exec")
fn sqlite_exec(conn: SqliteConn, sql: String) -> Result(Int, String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_q")
fn sqlite_q(
  conn: SqliteConn,
  sql: String,
  params: List(Dynamic),
) -> Result(List(List(Dynamic)), String)

@external(erlang, "cepaf_gleam_ffi", "sqlite_close")
fn sqlite_close(conn: SqliteConn) -> Nil

@external(erlang, "cepaf_gleam_ffi", "identity")
fn dyn_string(value: String) -> Dynamic

@external(erlang, "cepaf_gleam_ffi", "identity")
fn dyn_int(value: Int) -> Dynamic

pub type ChatMessage {
  ChatMessage(role: String, content: String, timestamp_ms: Int)
}

/// Resolves path checking relative working directory and absolute canonical repo path.
pub fn resolve_db_path(path: String) -> String {
  case simplifile.is_file(path) {
    Ok(True) -> path
    _ -> {
      let repo_path = "/home/an/NAS-setup/uos/" <> path
      case simplifile.is_file(repo_path) {
        Ok(True) -> repo_path
        _ -> path
      }
    }
  }
}

/// Ensures the conversation_history table and index exist in SQLite.
pub fn init_schema(db_path: String) -> Result(Nil, String) {
  let resolved = resolve_db_path(db_path)
  use conn <- result.try(sqlite_open(resolved))
  let ddl =
    "CREATE TABLE IF NOT EXISTS conversation_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      chat_id TEXT NOT NULL,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      tool_calls TEXT,
      timestamp_ms INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_conv_chat_time ON conversation_history(chat_id, timestamp_ms);"

  let res = sqlite_exec(conn, ddl)
  sqlite_close(conn)
  case res {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("init_conversation_history_failed: " <> err)
  }
}

/// Record a message turn into conversation memory.
/// Ensures sensitive hardware identifiers are redacted before persisting.
pub fn record_turn(
  db_path: String,
  chat_id: String,
  role: String,
  content: String,
  tool_calls: Option(String),
  timestamp_ms: Int,
) -> Result(Nil, String) {
  let sanitized_content =
    string.replace(
      content,
      egress_redactor.denied_os_nvme_serial,
      egress_redactor.redacted_serial_placeholder,
    )
  let tool_calls_str = case tool_calls {
    Some(t) ->
      string.replace(
        t,
        egress_redactor.denied_os_nvme_serial,
        egress_redactor.redacted_serial_placeholder,
      )
    None -> ""
  }

  let resolved = resolve_db_path(db_path)
  use conn <- result.try(sqlite_open(resolved))
  let sql =
    "INSERT INTO conversation_history (chat_id, role, content, tool_calls, timestamp_ms)
     VALUES (?, ?, ?, ?, ?);"
  let params = [
    dyn_string(chat_id),
    dyn_string(role),
    dyn_string(sanitized_content),
    dyn_string(tool_calls_str),
    dyn_int(timestamp_ms),
  ]
  let res = sqlite_q(conn, sql, params)
  sqlite_close(conn)
  case res {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("record_turn_failed: " <> err)
  }
}

/// Fetch recent conversation history for a given chat_id, in chronological order.
pub fn get_recent_history(
  db_path: String,
  chat_id: String,
  limit: Int,
) -> List(ChatMessage) {
  let resolved = resolve_db_path(db_path)
  case sqlite_open(resolved) {
    Error(_) -> []
    Ok(conn) -> {
      let sql =
        "SELECT role, content, timestamp_ms FROM conversation_history
         WHERE chat_id = ? ORDER BY id DESC LIMIT ?;"
      let params = [dyn_string(chat_id), dyn_int(limit)]
      let rows_res = sqlite_q(conn, sql, params)
      sqlite_close(conn)

      case rows_res {
        Error(_) -> []
        Ok(rows) -> {
          let messages =
            list.filter_map(rows, fn(row) {
              case row {
                [r_dyn, c_dyn, ts_dyn, ..] -> {
                  case
                    decode.run(r_dyn, decode.string),
                    decode.run(c_dyn, decode.string),
                    decode.run(ts_dyn, decode.int)
                  {
                    Ok(r), Ok(c), Ok(ts) -> Ok(ChatMessage(r, c, ts))
                    _, _, _ -> Error(Nil)
                  }
                }
                _ -> Error(Nil)
              }
            })
          list.reverse(messages)
        }
      }
    }
  }
}

/// Clear history for a specific chat_id (e.g. on /reset or /clear directive).
pub fn clear_history(db_path: String, chat_id: String) -> Result(Nil, String) {
  let resolved = resolve_db_path(db_path)
  use conn <- result.try(sqlite_open(resolved))
  let sql = "DELETE FROM conversation_history WHERE chat_id = ?;"
  let res = sqlite_q(conn, sql, [dyn_string(chat_id)])
  sqlite_close(conn)
  case res {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error("clear_history_failed: " <> err)
  }
}

/// Count total recorded turns for a chat.
pub fn count_turns(db_path: String, chat_id: String) -> Int {
  let resolved = resolve_db_path(db_path)
  case sqlite_open(resolved) {
    Error(_) -> 0
    Ok(conn) -> {
      let sql = "SELECT COUNT(*) FROM conversation_history WHERE chat_id = ?;"
      let res = sqlite_q(conn, sql, [dyn_string(chat_id)])
      sqlite_close(conn)
      case res {
        Ok([[count_dyn, ..], ..]) -> {
          case decode.run(count_dyn, decode.int) {
            Ok(c) -> c
            Error(_) -> 0
          }
        }
        _ -> 0
      }
    }
  }
}
