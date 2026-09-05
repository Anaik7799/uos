import cepaf_gleam/db/duckdb
import cepaf_gleam/knowledge/semantic.{
  type Triple, type TriplePattern, Blank, Iri, Literal,
}
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

// =============================================================================
// FFI Wrappers
// =============================================================================

@external(erlang, "cepaf_gleam_ffi", "identity")
fn to_dynamic(a: a) -> Dynamic

@external(erlang, "cepaf_gleam_ffi", "to_string")
fn ffi_to_string(a: Dynamic) -> Result(String, Nil)

// =============================================================================
// Schema & Initialization
// =============================================================================

const schema_sql = "
  CREATE TABLE IF NOT EXISTS triples (
    id INTEGER PRIMARY KEY,
    graph_uri TEXT NOT NULL DEFAULT 'default',
    subject TEXT NOT NULL,
    predicate TEXT NOT NULL,
    object TEXT NOT NULL,
    object_type TEXT NOT NULL,
    object_lang TEXT,
    object_datatype TEXT,
    created_at TEXT NOT NULL DEFAULT (current_timestamp),
    source_rule TEXT,
    confidence REAL DEFAULT 1.0
  );
  CREATE INDEX IF NOT EXISTS idx_triples_spo ON triples(subject, predicate, object);
  CREATE INDEX IF NOT EXISTS idx_triples_pos ON triples(predicate, object, subject);
  CREATE INDEX IF NOT EXISTS idx_triples_osp ON triples(object, subject, predicate);
  CREATE UNIQUE INDEX IF NOT EXISTS idx_triples_unique ON triples(graph_uri, subject, predicate, object);

  CREATE TABLE IF NOT EXISTS graphs (
    uri TEXT PRIMARY KEY,
    title TEXT,
    created_at TEXT NOT NULL DEFAULT (current_timestamp)
  );

  CREATE TABLE IF NOT EXISTS namespaces (
    prefix TEXT PRIMARY KEY,
    uri TEXT NOT NULL
  );
"

/// Ensures the DuckDB triple store schema exists.
pub fn ensure_triple_store() -> Result(Nil, String) {
  duckdb.ensure_schema(schema_sql)
}

// =============================================================================
// Semantic API
// =============================================================================

fn serialize_term(term: semantic.RdfTerm) -> #(String, String, String, String) {
  case term {
    Iri(iri) -> #(iri, "iri", "", "")
    Blank(id) -> #("_:" <> id, "blank", "", "")
    Literal(value, lang, datatype) -> #(value, "literal", lang, datatype)
  }
}

pub fn add_triple(graph_uri: String, triple: Triple) -> Result(Int, String) {
  let sql =
    "
    INSERT INTO triples
      (graph_uri, subject, predicate, object, object_type, object_lang, object_datatype)
    VALUES
      (?, ?, ?, ?, ?, ?, ?);
  "
  let #(subj, _, _, _) = serialize_term(triple.subject)
  let #(obj, obj_type, obj_lang, obj_datatype) = serialize_term(triple.object)

  let params = [
    to_dynamic(graph_uri),
    to_dynamic(subj),
    to_dynamic(triple.predicate),
    to_dynamic(obj),
    to_dynamic(obj_type),
    to_dynamic(obj_lang),
    to_dynamic(obj_datatype),
  ]

  duckdb.execute(sql, params)
}

pub fn query_triples(pattern: TriplePattern) -> Result(List(Triple), String) {
  let #(sql, params) = build_query_sql(pattern)
  use rows <- result.try(duckdb.query(sql, params))
  list.try_map(rows, parse_triple_row)
}

fn build_query_sql(pattern: TriplePattern) -> #(String, List(Dynamic)) {
  let base_sql =
    "SELECT subject, predicate, object, object_type, object_lang, object_datatype FROM triples"
  let filters = []
  let params = []

  let #(filters, params) = case pattern.subject {
    Some(s) -> {
      let #(s_val, _, _, _) = serialize_term(s)
      #(["subject = ?", ..filters], [to_dynamic(s_val), ..params])
    }
    None -> #(filters, params)
  }

  let #(filters, params) = case pattern.predicate {
    Some(p) -> #(["predicate = ?", ..filters], [to_dynamic(p), ..params])
    None -> #(filters, params)
  }

  let #(filters, params) = case pattern.object {
    Some(o) -> {
      let #(o_val, _, _, _) = serialize_term(o)
      #(["object = ?", ..filters], [to_dynamic(o_val), ..params])
    }
    None -> #(filters, params)
  }

  case filters {
    [] -> #(base_sql <> ";", [])
    _ -> {
      let where_clause =
        " WHERE " <> string.join(list.reverse(filters), " AND ")
      #(base_sql <> where_clause <> ";", list.reverse(params))
    }
  }
}

fn parse_triple_row(row: List(Dynamic)) -> Result(Triple, String) {
  case row {
    [s, p, o, ot, ol, od] -> {
      use s_str <- result.try(
        ffi_to_string(s) |> result.replace_error("Invalid subject"),
      )
      use p_str <- result.try(
        ffi_to_string(p) |> result.replace_error("Invalid predicate"),
      )
      use o_str <- result.try(
        ffi_to_string(o) |> result.replace_error("Invalid object"),
      )
      use ot_str <- result.try(
        ffi_to_string(ot) |> result.replace_error("Invalid object type"),
      )
      use ol_str <- result.try(
        ffi_to_string(ol) |> result.replace_error("Invalid object lang"),
      )
      use od_str <- result.try(
        ffi_to_string(od) |> result.replace_error("Invalid object datatype"),
      )

      Ok(
        semantic.Triple(
          subject: Iri(s_str),
          predicate: p_str,
          object: case ot_str {
            "iri" -> Iri(o_str)
            "blank" -> Blank(o_str)
            _ -> Literal(o_str, ol_str, od_str)
          },
        ),
      )
    }
    _ -> Error("Invalid triple row format")
  }
}
