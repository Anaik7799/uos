import gleam/dynamic/decode.{type Decoder}
import gleam/list
import gleam/result
import gleam/string
import sqlight

pub opaque type Database {
  Database(connection: sqlight.Connection)
}

pub opaque type Value {
  Value(value: sqlight.Value)
}

pub type DatabaseError {
  SqliteFailure(code: Int, message: String, offset: Int)
  UnexpectedRowCount(expected: Int, actual: Int)
  StaticSqlContainsNul
  SqlContainsNul
  InvalidReadOnlyPath
}

pub fn open(path: String) -> Result(Database, DatabaseError) {
  sqlight.open(path)
  |> result.map(Database)
  |> result.map_error(from_sqlight_error)
}

/// Open an existing database with SQLite's read-only mode, not a mutable
/// `query_only` setting. The pinned sqlight/esqlite build must support URI names.
///
/// Accept only absolute POSIX paths with a single leading slash. Caller-supplied
/// URIs, relative paths, NUL, `?`, `#`, `%`, and backslash are rejected rather
/// than reinterpreted or escaped. Legitimate filenames using those special
/// characters are deliberately unsupported by this bounded planning API.
/// This does not establish path confinement, snapshot fixity, or a capability
/// boundary for arbitrary SQL; the planning-only NIF and close semantics remain.
pub fn open_read_only(path: String) -> Result(Database, DatabaseError) {
  let ambiguous =
    list.any(["\u{0}", "?", "#", "%", "\\"], fn(part) {
      string.contains(path, part)
    })
  case
    string.starts_with(path, "/")
    && !string.starts_with(path, "//")
    && !ambiguous
  {
    True -> open("file:" <> path <> "?mode=ro&cache=private")
    False -> Error(InvalidReadOnlyPath)
  }
}

pub fn close(database: Database) -> Result(Nil, DatabaseError) {
  let Database(connection) = database
  sqlight.close(connection)
  |> result.map_error(from_sqlight_error)
}

/// Execute audited, static SQL such as schema or seed migrations. Values must
/// never be interpolated into this entrypoint.
pub fn exec_static(
  database: Database,
  sql: String,
) -> Result(Nil, DatabaseError) {
  case string.contains(sql, "\u{0}") {
    True -> Error(StaticSqlContainsNul)
    False -> {
      let Database(connection) = database
      sqlight.exec(sql, on: connection)
      |> result.map_error(from_sqlight_error)
    }
  }
}

/// Execute one parameterized statement that is not expected to return rows.
pub fn execute(
  database: Database,
  sql: String,
  arguments: List(Value),
) -> Result(Nil, DatabaseError) {
  use rows <- result.try(query(database, sql, arguments, decode.dynamic))
  case rows {
    [] -> Ok(Nil)
    rows -> Error(UnexpectedRowCount(expected: 0, actual: list.length(rows)))
  }
}

/// Reject NUL in SQL text before calling SQLite; parameter-bound values retain
/// their exact contents, including NUL bytes.
pub fn query(
  database: Database,
  sql: String,
  arguments: List(Value),
  decoder: Decoder(a),
) -> Result(List(a), DatabaseError) {
  case string.contains(sql, "\u{0}") {
    True -> Error(SqlContainsNul)
    False -> {
      let Database(connection) = database
      sqlight.query(
        sql,
        on: connection,
        with: list.map(arguments, fn(value) {
          let Value(value) = value
          value
        }),
        expecting: decoder,
      )
      |> result.map_error(from_sqlight_error)
    }
  }
}

pub fn int(value: Int) -> Value {
  Value(sqlight.int(value))
}

pub fn text(value: String) -> Value {
  Value(sqlight.text(value))
}

pub fn blob(value: BitArray) -> Value {
  Value(sqlight.blob(value))
}

pub fn null() -> Value {
  Value(sqlight.null())
}

pub fn scalar_text(
  database: Database,
  sql: String,
) -> Result(String, DatabaseError) {
  let decoder = {
    use value <- decode.field(0, decode.string)
    decode.success(value)
  }
  use rows <- result.try(query(database, sql, [], decoder))
  case rows {
    [value] -> Ok(value)
    rows -> Error(UnexpectedRowCount(expected: 1, actual: list_length(rows)))
  }
}

pub fn scalar_int(
  database: Database,
  sql: String,
) -> Result(Int, DatabaseError) {
  let decoder = {
    use value <- decode.field(0, decode.int)
    decode.success(value)
  }
  use rows <- result.try(query(database, sql, [], decoder))
  case rows {
    [value] -> Ok(value)
    rows -> Error(UnexpectedRowCount(expected: 1, actual: list_length(rows)))
  }
}

fn list_length(items: List(a)) -> Int {
  items
  |> list.length
}

fn from_sqlight_error(error: sqlight.Error) -> DatabaseError {
  let sqlight.SqlightError(code, message, offset) = error
  SqliteFailure(
    code: sqlight.error_code_to_int(code),
    message: message,
    offset: offset,
  )
}
