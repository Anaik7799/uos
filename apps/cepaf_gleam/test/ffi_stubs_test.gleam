// Test pure helpers in FFI modules: db/holon_database, db/cross_holon,
// db/transaction_manager, bridge/jsonrpc, bridge/commands,
// smriti/catalog, smriti/semantic

import cepaf_gleam/bridge/commands
import cepaf_gleam/bridge/jsonrpc
import cepaf_gleam/db/cross_holon.{
  CrossHolonRequest, FirstWriterWins, LastWriterWins, MergeAll,
}
import cepaf_gleam/db/holon_database.{
  HolonDuckDB, HolonHybrid, HolonInMemory, HolonPostgres, HolonSQLite,
  HolonZenohKV,
}
import cepaf_gleam/db/transaction_manager.{
  TxAborted, TxAborting, TxCommitting, TxDeadlocked, TxDone, TxPending,
  TxRunning, TxTimedOut,
}
import cepaf_gleam/smriti/catalog
import cepaf_gleam/smriti/semantic
import gleam/float
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

// =============================================================================
// db/holon_database tests
// =============================================================================

pub fn holon_db_type_to_string_all_variants_test() {
  holon_database.db_type_to_string(HolonSQLite) |> should.equal("sqlite")
  holon_database.db_type_to_string(HolonDuckDB) |> should.equal("duckdb")
  holon_database.db_type_to_string(HolonPostgres) |> should.equal("postgres")
  holon_database.db_type_to_string(HolonInMemory) |> should.equal("in_memory")
  holon_database.db_type_to_string(HolonZenohKV) |> should.equal("zenoh_kv")
  holon_database.db_type_to_string(HolonHybrid) |> should.equal("hybrid")
}

pub fn holon_db_default_config_test() {
  let config = holon_database.default_config("/data/holon.db")
  config.path |> should.equal("/data/holon.db")
  config.db_type |> should.equal(HolonSQLite)
  config.max_connections |> should.equal(1)
  config.wal_mode |> should.be_true
}

pub fn holon_db_config_to_json_test() {
  let config = holon_database.default_config("/data/test.db")
  let json_str = json.to_string(holon_database.config_to_json(config))
  string.contains(json_str, "\"path\"") |> should.be_true
  string.contains(json_str, "sqlite") |> should.be_true
  string.contains(json_str, "wal_mode") |> should.be_true
}

// =============================================================================
// db/cross_holon tests
// =============================================================================

pub fn cross_holon_conflict_resolution_to_string_test() {
  cross_holon.conflict_resolution_to_string(LastWriterWins)
  |> should.equal("last_writer_wins")
  cross_holon.conflict_resolution_to_string(FirstWriterWins)
  |> should.equal("first_writer_wins")
  cross_holon.conflict_resolution_to_string(MergeAll)
  |> should.equal("merge_all")
}

pub fn cross_holon_request_to_json_test() {
  let req =
    CrossHolonRequest(
      source_holon: "holon-a",
      target_holon: "holon-b",
      operation: "sync",
      payload: "{}",
    )
  let json_str = json.to_string(cross_holon.request_to_json(req))
  string.contains(json_str, "holon-a") |> should.be_true
  string.contains(json_str, "holon-b") |> should.be_true
  string.contains(json_str, "sync") |> should.be_true
}

// =============================================================================
// db/transaction_manager tests
// =============================================================================

pub fn tx_status_to_string_all_variants_test() {
  transaction_manager.status_to_string(TxPending) |> should.equal("pending")
  transaction_manager.status_to_string(TxRunning) |> should.equal("running")
  transaction_manager.status_to_string(TxCommitting)
  |> should.equal("committing")
  transaction_manager.status_to_string(TxAborting) |> should.equal("aborting")
  transaction_manager.status_to_string(TxDone) |> should.equal("done")
  transaction_manager.status_to_string(TxAborted) |> should.equal("aborted")
  transaction_manager.status_to_string(TxTimedOut) |> should.equal("timed_out")
  transaction_manager.status_to_string(TxDeadlocked)
  |> should.equal("deadlocked")
}

pub fn tx_is_terminal_test() {
  transaction_manager.is_terminal(TxDone) |> should.be_true
  transaction_manager.is_terminal(TxAborted) |> should.be_true
  transaction_manager.is_terminal(TxTimedOut) |> should.be_true
  transaction_manager.is_terminal(TxDeadlocked) |> should.be_true
  transaction_manager.is_terminal(TxPending) |> should.be_false
  transaction_manager.is_terminal(TxRunning) |> should.be_false
  transaction_manager.is_terminal(TxCommitting) |> should.be_false
  transaction_manager.is_terminal(TxAborting) |> should.be_false
}

pub fn tx_default_timeout_ms_test() {
  transaction_manager.default_timeout_ms() |> should.equal(30_000)
}

// =============================================================================
// bridge/jsonrpc tests
// =============================================================================

pub fn jsonrpc_success_response_valid_json_test() {
  let resp = jsonrpc.success_response(1, json.string("ok"))
  string.contains(resp, "\"jsonrpc\"") |> should.be_true
  string.contains(resp, "\"2.0\"") |> should.be_true
  string.contains(resp, "\"result\"") |> should.be_true
  string.contains(resp, "\"id\"") |> should.be_true
}

pub fn jsonrpc_error_response_test() {
  let resp = jsonrpc.error_response(2, -32_600, "Invalid request")
  string.contains(resp, "\"error\"") |> should.be_true
  string.contains(resp, "Invalid request") |> should.be_true
  string.contains(resp, "-32600") |> should.be_true
}

pub fn jsonrpc_parse_error_format_test() {
  let resp = jsonrpc.parse_error()
  string.contains(resp, "\"jsonrpc\"") |> should.be_true
  string.contains(resp, "Parse error") |> should.be_true
  string.contains(resp, "-32700") |> should.be_true
}

// =============================================================================
// bridge/commands tests
// =============================================================================

pub fn bridge_command_to_string_test() {
  commands.command_to_string(commands.ContainerList)
  |> should.equal("container.list")
  commands.command_to_string(commands.HealthCheck)
  |> should.equal("health.check")
  commands.command_to_string(commands.MeshStatus)
  |> should.equal("mesh.status")
  commands.command_to_string(commands.OodaRun)
  |> should.equal("ooda.run")
  commands.command_to_string(commands.FractalStatus)
  |> should.equal("fractal.status")
}

pub fn bridge_all_commands_count_test() {
  let cmds = commands.all_commands()
  list.length(cmds) |> should.equal(10)
}

pub fn bridge_parse_command_valid_test() {
  commands.parse_command("container.list") |> should.be_ok
  commands.parse_command("health.check") |> should.be_ok
  commands.parse_command("mesh.status") |> should.be_ok
}

pub fn bridge_parse_command_invalid_test() {
  commands.parse_command("nonexistent.cmd") |> should.be_error
}

// =============================================================================
// smriti/catalog tests
// =============================================================================

pub fn catalog_new_entry_test() {
  let entry = catalog.new_entry("e-1", "Boot Module", "core", "Boot logic")
  entry.id |> should.equal("e-1")
  entry.name |> should.equal("Boot Module")
  entry.category |> should.equal("core")
  entry.description |> should.equal("Boot logic")
  entry.tags |> should.equal([])
}

pub fn catalog_matches_query_matching_test() {
  let entry =
    catalog.CatalogEntry(
      id: "e-2",
      name: "Zenoh Client",
      category: "zenoh",
      description: "Real-time messaging",
      tags: ["networking", "pubsub"],
      created_at: "2024-01-01",
    )
  let query =
    catalog.CatalogQuery(
      category: option.Some("zenoh"),
      tags: ["networking"],
      search_text: option.Some("messaging"),
      limit: 10,
    )
  catalog.matches_query(entry, query) |> should.be_true
}

pub fn catalog_matches_query_non_matching_test() {
  let entry =
    catalog.CatalogEntry(
      id: "e-3",
      name: "Podman Driver",
      category: "podman",
      description: "Container management",
      tags: ["containers"],
      created_at: "2024-01-01",
    )
  let query =
    catalog.CatalogQuery(
      category: option.Some("zenoh"),
      tags: [],
      search_text: None,
      limit: 10,
    )
  catalog.matches_query(entry, query) |> should.be_false
}

pub fn catalog_entry_to_json_test() {
  let entry = catalog.new_entry("e-4", "Test Entry", "test", "For testing")
  let json_str = json.to_string(catalog.entry_to_json(entry))
  string.contains(json_str, "\"id\"") |> should.be_true
  string.contains(json_str, "e-4") |> should.be_true
  string.contains(json_str, "Test Entry") |> should.be_true
}

// =============================================================================
// smriti/semantic tests
// =============================================================================

pub fn semantic_dot_product_test() {
  // [1,2,3] . [4,5,6] = 4+10+18 = 32
  semantic.dot_product([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])
  |> should.equal(32.0)
}

pub fn semantic_dot_product_empty_test() {
  semantic.dot_product([], []) |> should.equal(0.0)
}

pub fn semantic_cosine_similarity_identical_vectors_test() {
  let v = [1.0, 2.0, 3.0]
  let result = semantic.cosine_similarity(v, v)
  result |> should.be_ok
  let assert Ok(sim) = result
  // Identical vectors should have similarity ~1.0
  let diff = float.absolute_value(sim -. 1.0)
  should.be_true(diff <. 0.001)
}

pub fn semantic_cosine_similarity_zero_vector_test() {
  semantic.cosine_similarity([0.0, 0.0], [1.0, 2.0]) |> should.be_error
}

pub fn semantic_normalize_test() {
  let v = [3.0, 4.0]
  let normalized = semantic.normalize(v)
  // magnitude of [3,4] = 5, so normalized = [0.6, 0.8]
  list.length(normalized) |> should.equal(2)
  let assert [x, y] = normalized
  let x_diff = float.absolute_value(x -. 0.6)
  let y_diff = float.absolute_value(y -. 0.8)
  should.be_true(x_diff <. 0.001)
  should.be_true(y_diff <. 0.001)
}

pub fn semantic_normalize_zero_vector_test() {
  let v = [0.0, 0.0, 0.0]
  let normalized = semantic.normalize(v)
  normalized |> should.equal([0.0, 0.0, 0.0])
}

pub fn semantic_magnitude_test() {
  // magnitude of [3,4] = 5
  let mag = semantic.magnitude([3.0, 4.0])
  let diff = float.absolute_value(mag -. 5.0)
  should.be_true(diff <. 0.001)
}
