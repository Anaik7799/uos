//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/zettelkasten/search</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SMRITI-131, SC-SMRITI-133</stamp-controls></compliance>
//// </c3i-module>
////
//// Knowledge search — FTS5 query builder and result types.
//// STAMP: SC-SMRITI-131 (FTS5), SC-SMRITI-133 (query timeout < 500ms)

import cepaf_gleam/zettelkasten/types.{type Holon, type HolonLevel}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Search query with filters.
pub type SearchQuery {
  SearchQuery(
    text: String,
    level_filter: Option(HolonLevel),
    cluster_filter: Option(String),
    max_entropy: Float,
    limit: Int,
  )
}

/// Search result with relevance score.
pub type SearchResult {
  SearchResult(holon: Holon, relevance: Float, snippet: String)
}

/// RAG context — top-N search results formatted for LLM injection.
pub type RagContext {
  RagContext(query: String, results: List(SearchResult), total_chars: Int)
}

/// Build a default search query.
pub fn query(text: String) -> SearchQuery {
  SearchQuery(
    text: text,
    level_filter: None,
    cluster_filter: None,
    max_entropy: 0.9,
    limit: 5,
  )
}

/// Filter by holon level.
pub fn with_level(q: SearchQuery, level: HolonLevel) -> SearchQuery {
  SearchQuery(..q, level_filter: Some(level))
}

/// Filter by cluster.
pub fn with_cluster(q: SearchQuery, cluster: String) -> SearchQuery {
  SearchQuery(..q, cluster_filter: Some(cluster))
}

/// Set max entropy (exclude stale results).
pub fn with_max_entropy(q: SearchQuery, max: Float) -> SearchQuery {
  SearchQuery(..q, max_entropy: max)
}

/// Set result limit.
pub fn with_limit(q: SearchQuery, limit: Int) -> SearchQuery {
  SearchQuery(..q, limit: limit)
}

/// Build FTS5 MATCH query string for SQLite.
pub fn to_fts5_query(q: SearchQuery) -> String {
  let words = string.split(q.text, " ")
  let cleaned =
    words
    |> list.filter(fn(w) { string.length(string.trim(w)) > 2 })
    |> list.map(fn(w) { "\"" <> string.trim(w) <> "\"" })
  string.join(cleaned, " OR ")
}

/// Build the full SQL WHERE clause.
pub fn to_sql_where(q: SearchQuery) -> String {
  let clauses = ["holons_fts MATCH '" <> to_fts5_query(q) <> "'"]

  let clauses = case q.level_filter {
    Some(level) ->
      list.append(clauses, ["level = '" <> types.level_to_string(level) <> "'"])
    None -> clauses
  }

  let clauses = case q.cluster_filter {
    Some(cluster) -> list.append(clauses, ["cluster = '" <> cluster <> "'"])
    None -> clauses
  }

  let clauses =
    list.append(clauses, [
      "entropy <= " <> float_to_string_approx(q.max_entropy),
    ])

  string.join(clauses, " AND ")
}

/// In-memory search (for testing without SQLite).
pub fn search_in_memory(
  holons: List(Holon),
  q: SearchQuery,
) -> List(SearchResult) {
  holons
  |> list.filter(fn(h) { h.entropy <=. q.max_entropy })
  |> list.filter(fn(h) {
    case q.level_filter {
      Some(level) -> h.level == level
      None -> True
    }
  })
  |> list.filter(fn(h) {
    case q.cluster_filter {
      Some(cluster) -> h.cluster == Some(cluster)
      None -> True
    }
  })
  |> list.filter(fn(h) {
    let lower_content = string.lowercase(h.content)
    let lower_title = string.lowercase(h.title)
    let search_terms = string.split(string.lowercase(q.text), " ")
    list.any(search_terms, fn(term) {
      string.contains(lower_content, term) || string.contains(lower_title, term)
    })
  })
  |> list.map(fn(h) {
    let snippet = string.slice(h.content, 0, 120) <> "..."
    let trust = types.trust_for(h.rhetorical).value *. { 1.0 -. h.entropy }
    SearchResult(holon: h, relevance: trust, snippet: snippet)
  })
  |> sort_by_relevance
  |> list.take(q.limit)
}

/// Format search results as RAG context for LLM injection.
pub fn to_rag_context(
  query_text: String,
  results: List(SearchResult),
) -> RagContext {
  let total =
    list.fold(results, 0, fn(acc, r) { acc + string.length(r.snippet) })
  RagContext(query: query_text, results: results, total_chars: total)
}

/// Format RAG context as a string for system prompt injection.
pub fn rag_context_to_string(ctx: RagContext) -> String {
  case ctx.results {
    [] -> ""
    results -> {
      let header = "Relevant system knowledge for: " <> ctx.query <> "\n"
      let body =
        results
        |> list.map(fn(r) { "- [" <> r.holon.title <> "] " <> r.snippet })
        |> string.join("\n")
      header <> body
    }
  }
}

// Helpers
fn sort_by_relevance(results: List(SearchResult)) -> List(SearchResult) {
  list.sort(results, fn(a, b) {
    case a.relevance >. b.relevance {
      True -> order.Lt
      False ->
        case a.relevance <. b.relevance {
          True -> order.Gt
          False -> order.Eq
        }
    }
  })
}

import gleam/order

fn float_to_string_approx(f: Float) -> String {
  let whole = float_truncate(f)
  let frac = float_truncate({ f -. int_to_float(whole) } *. 100.0)
  int_to_string(whole) <> "." <> int_to_string(frac)
}

fn float_truncate(f: Float) -> Int {
  case f >=. 0.0 {
    True -> positive_truncate(f, 0)
    False -> 0 - positive_truncate(0.0 -. f, 0)
  }
}

fn positive_truncate(f: Float, acc: Int) -> Int {
  case f <. 1.0 {
    True -> acc
    False -> positive_truncate(f -. 1.0, acc + 1)
  }
}

fn int_to_float(n: Int) -> Float {
  case n {
    0 -> 0.0
    1 -> 1.0
    _ -> {
      let half = int_to_float(n / 2)
      let rem = case n % 2 {
        0 -> 0.0
        _ -> 1.0
      }
      half +. half +. rem
    }
  }
}

fn int_to_string(n: Int) -> String {
  case n < 0 {
    True -> "-" <> int_to_string(-n)
    False ->
      case n < 10 {
        True ->
          case n {
            0 -> "0"
            1 -> "1"
            2 -> "2"
            3 -> "3"
            4 -> "4"
            5 -> "5"
            6 -> "6"
            7 -> "7"
            8 -> "8"
            _ -> "9"
          }
        False -> int_to_string(n / 10) <> int_to_string(n % 10)
      }
  }
}
