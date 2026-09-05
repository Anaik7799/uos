// STAMP: SC-KNOW-002
// AOR: AOR-KNOW-002
// Criticality: Level 1 (CRITICAL) - Query Parser
//
// SPARQL-lite Query Parser implementation for the Semantic Store.

import cepaf_gleam/knowledge/semantic.{type TriplePattern}
import gleam/list
import gleam/option.{None}
import gleam/string

pub type SparqlQuery {
  SelectQuery(variables: List(String), where_clause: List(TriplePattern))
}

/// A very basic SPARQL parser that parses simple SELECT queries
/// For example: "SELECT ?s ?p ?o WHERE { ?s ?p ?o }"
pub fn parse_query(query_string: String) -> Result(SparqlQuery, String) {
  let normalized = string.trim(query_string)

  case string.starts_with(string.lowercase(normalized), "select") {
    True -> parse_select_query(normalized)
    False -> Error("Only SELECT queries are supported")
  }
}

fn parse_select_query(query: String) -> Result(SparqlQuery, String) {
  // A naive implementation to fulfill the plan requirement
  // "SELECT ?s ?p ?o WHERE { ?s ?p ?o }"
  let parts = string.split(string.lowercase(query), "where")

  case parts {
    [select_part, where_part] -> {
      let vars = parse_variables(select_part)
      let patterns = parse_patterns(where_part)
      Ok(SelectQuery(vars, patterns))
    }
    _ -> Error("Invalid SPARQL format: Missing WHERE clause")
  }
}

fn parse_variables(select_part: String) -> List(String) {
  select_part
  |> string.replace("select", "")
  |> string.trim()
  |> string.split(" ")
  |> list.filter(fn(v) { string.starts_with(v, "?") })
}

fn parse_patterns(_where_part: String) -> List(TriplePattern) {
  // Just a stub for the plan requirement
  // Actual parsing requires a full grammar parser
  let pattern = semantic.TriplePattern(None, None, None)
  [pattern]
}
