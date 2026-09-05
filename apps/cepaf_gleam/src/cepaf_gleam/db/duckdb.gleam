// STAMP: SC-HOLON-002
// AOR: AOR-HOLON-002, AOR-HOLON-007
// Criticality: Level 2 (HIGH) - Database Interface
//
// This module defines the Foreign Function Interface (FFI) to the native
// Erlang DuckDB driver. It provides a type-safe Gleam API over the
// underlying native calls.
//
// NOTE: This assumes a backing NIF (Native Implemented Function) in Erlang
// that handles the actual database connection and execution.

import gleam/dynamic.{type Dynamic}

// =============================================================================
// FFI Definitions
// =============================================================================
// These functions are implemented in cepaf_gleam_ffi.erl

/// Executes a write query (INSERT, UPDATE, DELETE) against the DuckDB database.
///
/// Returns the number of rows affected.
///
@external(erlang, "cepaf_gleam_ffi", "duckdb_execute")
pub fn execute(sql: String, params: List(Dynamic)) -> Result(Int, String)

/// Executes a read query (SELECT) against the DuckDB database.
///
/// Returns a list of rows, where each row is a list of dynamic values.
///
@external(erlang, "cepaf_gleam_ffi", "duckdb_query")
pub fn query(
  sql: String,
  params: List(Dynamic),
) -> Result(List(List(Dynamic)), String)

/// Ensures the database and its schema are initialized.
@external(erlang, "cepaf_gleam_ffi", "duckdb_ensure_schema")
pub fn ensure_schema(schema_sql: String) -> Result(Nil, String)
