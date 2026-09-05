import gleam/crypto
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleeunit/should
import simplifile
import uos_planning_ledger/database
import uos_planning_ledger/digest

/// Run only this module: `gleam run -m database_test`. In particular, this must
/// not discover the materializer tests or read their external input allowlist.
pub fn main() {
  let assert Ok(Nil) = run_database_tests([DatabaseTest], [Verbose])
}

type TestModule {
  DatabaseTest
}

type TestOption {
  Verbose
}

@external(erlang, "gleeunit_ffi", "run_eunit")
fn run_database_tests(
  modules: List(TestModule),
  options: List(TestOption),
) -> Result(Nil, Dynamic)

pub fn executes_static_schema_and_round_trips_parameterized_blob_test() {
  let assert Ok(db) =
    database.open("file:uos-ledger-test?mode=memory&cache=private")
  let assert Ok(Nil) =
    database.exec_static(
      db,
      "CREATE TABLE sample (id INTEGER PRIMARY KEY, payload BLOB NOT NULL) STRICT;",
    )

  let bytes = <<0, 1, 2, 255>>
  let assert Ok(Nil) =
    database.execute(db, "INSERT INTO sample (id, payload) VALUES (?, ?);", [
      database.int(1),
      database.blob(bytes),
    ])

  let row_decoder = {
    use storage_class <- decode.field(0, decode.string)
    use byte_count <- decode.field(1, decode.int)
    use stored <- decode.field(2, decode.bit_array)
    decode.success(#(storage_class, byte_count, stored))
  }
  let assert Ok([#("blob", 4, stored)]) =
    database.query(
      db,
      "SELECT typeof(payload), length(payload), payload FROM sample WHERE id = ?;",
      [database.int(1)],
      row_decoder,
    )
  stored |> should.equal(bytes)
  database.close(db) |> should.equal(Ok(Nil))
}

pub fn scalar_queries_preserve_sqlite_integrity_results_test() {
  let assert Ok(db) =
    database.open("file:uos-ledger-scalar?mode=memory&cache=private")
  let assert Ok(Nil) =
    database.exec_static(db, "CREATE TABLE item (id INTEGER) STRICT;")
  database.scalar_text(db, "PRAGMA integrity_check;")
  |> should.equal(Ok("ok"))
  database.close(db) |> should.equal(Ok(Nil))
}

pub fn static_sql_rejects_embedded_nul_test() {
  let assert Ok(db) =
    database.open("file:uos-ledger-nul?mode=memory&cache=private")
  database.exec_static(db, "SELECT '\u{0}';")
  |> should.equal(Error(database.StaticSqlContainsNul))
  database.close(db) |> should.equal(Ok(Nil))
}

pub fn query_rejects_embedded_nul_in_sql_text_test() {
  let assert Ok(db) = database.open(":memory:")
  let decoder = {
    use value <- decode.field(0, decode.int)
    decode.success(value)
  }
  let response = database.query(db, "SELECT 7;\u{0}SELECT 8;", [], decoder)
  database.close(db) |> should.equal(Ok(Nil))
  response |> should.equal(Error(database.SqlContainsNul))
}

pub fn execute_rejects_embedded_nul_before_any_mutation_test() {
  let assert Ok(db) = database.open(":memory:")
  let assert Ok(Nil) =
    database.exec_static(db, "CREATE TABLE item (id INTEGER) STRICT;")
  let response =
    database.execute(db, "INSERT INTO item VALUES (1);\u{0}SELECT 2;", [])
  let count = database.scalar_int(db, "SELECT count(*) FROM item;")
  database.close(db) |> should.equal(Ok(Nil))
  response |> should.equal(Error(database.SqlContainsNul))
  count |> should.equal(Ok(0))
}

pub fn bound_text_nul_round_trips_without_sql_text_rejection_test() {
  let assert Ok(db) = database.open(":memory:")
  let assert Ok(Nil) =
    database.exec_static(db, "CREATE TABLE item (payload TEXT) STRICT;")
  let assert Ok(Nil) =
    database.execute(db, "INSERT INTO item VALUES (?);", [
      database.text("before\u{0}after"),
    ])
  let decoder = {
    use value <- decode.field(0, decode.string)
    decode.success(value)
  }
  let response =
    database.query(
      db,
      "SELECT payload FROM item WHERE payload = ?;",
      [database.text("before\u{0}after")],
      decoder,
    )
  database.close(db) |> should.equal(Ok(Nil))
  response |> should.equal(Ok(["before\u{0}after"]))
}

pub fn read_only_open_cannot_write_even_with_query_only_disabled_test() {
  let directory = new_test_directory()
  let path = directory <> "/database space é.sqlite3"
  let assert Ok(writable) = database.open(path)
  let assert Ok(Nil) =
    database.exec_static(
      writable,
      "CREATE TABLE item (id INTEGER) STRICT; INSERT INTO item VALUES (1);",
    )
  database.close(writable) |> should.equal(Ok(Nil))

  let assert Ok(read_only) = database.open_read_only(path)
  let before = database.scalar_int(read_only, "SELECT count(*) FROM item;")
  let assert Ok(Nil) =
    database.exec_static(read_only, "PRAGMA query_only = OFF;")
  let insertion =
    database.execute(read_only, "INSERT INTO item VALUES (?);", [
      database.int(2),
    ])
  let after = database.scalar_int(read_only, "SELECT count(*) FROM item;")
  let closed = database.close(read_only)
  simplifile.delete(directory) |> should.equal(Ok(Nil))

  before |> should.equal(Ok(1))
  let assert Error(database.SqliteFailure(code: code, ..)) = insertion
  // SQLITE_READONLY is the primary SQLite result code 8.
  code |> should.equal(8)
  after |> should.equal(Ok(1))
  closed |> should.equal(Ok(Nil))
}

pub fn read_only_open_does_not_create_a_missing_database_test() {
  let directory = new_test_directory()
  let path = directory <> "/missing.sqlite3"
  let response = database.open_read_only(path)
  case response {
    Ok(db) -> database.close(db) |> should.equal(Ok(Nil))
    Error(_) -> Nil
  }
  let created = simplifile.exists(path, follow_links: False)
  simplifile.delete(directory) |> should.equal(Ok(Nil))

  response |> should.be_error
  created |> should.equal(Ok(False))
}

pub fn read_only_open_rejects_uri_and_path_ambiguity_test() {
  let directory = new_test_directory()
  let paths = [
    "",
    ":memory:",
    "file::memory:?mode=memory",
    "." <> directory <> "/relative.sqlite3",
    "/" <> directory <> "/authority.sqlite3",
    directory <> "/nul\u{0}suffix.sqlite3",
    directory <> "/query?mode=rwc",
    directory <> "/fragment#suffix.sqlite3",
    directory <> "/percent%3fmode=rwc",
    directory <> "/backslash\\name.sqlite3",
  ]
  let responses =
    list.map(paths, fn(path) {
      case database.open_read_only(path) {
        Ok(db) -> {
          database.close(db) |> should.equal(Ok(Nil))
          Ok(Nil)
        }
        Error(error) -> Error(error)
      }
    })
  let created = simplifile.read_directory(directory)
  simplifile.delete(directory) |> should.equal(Ok(Nil))

  list.each(responses, fn(response) {
    response |> should.equal(Error(database.InvalidReadOnlyPath))
  })
  created |> should.equal(Ok([]))
}

fn new_test_directory() -> String {
  let directory =
    "/tmp/uos-database-test-"
    <> digest.sha256_hex(crypto.strong_random_bytes(32))
  let assert Ok(Nil) = simplifile.create_directory(directory)
  directory
}
