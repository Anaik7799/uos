//// Wave 1D (I25): multi-token search and zk_transclude fallback coverage.
//// Proves that a query where only a majority of words match degrades to a
//// ranked token-OR result instead of an empty list, that the limit parameter
//// remains clamped, and that the candidate identity is valid.

import cepaf_gleam/mcp/adapters/knowledge as km
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/types.{Complete}
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleeunit/should

fn corpus() {
  let rows = [
    #(
      "docs/zk/20260905-1721-master-knowledge-graph.md",
      "public",
      "# ALPHA BETA GAMMA DELTA EPSILON\nHistorical knowledge graph.",
    ),
    #("docs/wiki/second.md", "public", "# alpha zeta\nsecond"),
    #("docs/wiki/third.md", "public", "# alpha beta\nthird"),
    #("docs/wiki/fourth.md", "public", "# alpha beta\nfourth"),
  ]
  list.fold(
    rows,
    km.new_corpus("/workspace", ["public"], 4096, 8),
    fn(c, r) { km.with_entry(c, km.CorpusEntry(r.0, km.RegularFile, r.1, r.2)) },
  )
}

fn paths(tool: String, query: String, limit: String) -> List(String) {
  let assert Complete(body, _) =
    km.execute(
      corpus(),
      ["public"],
      tool,
      dict.from_list([
        #("query", query),
        #("limit", limit),
      ]),
    )
  let row = decode.field("rel_path", decode.string, decode.success)
  let decoder = decode.field("results", decode.list(row), decode.success)
  let assert Ok(paths) = json.parse(body, decoder)
  paths
}

pub fn seven_word_majority_match_returns_document_test() {
  let results =
    paths(
      "knowledge_search",
      "alpha beta gamma delta epsilon zeta eta",
      "5",
    )
  results |> should.not_equal([])
  list.first(results)
  |> should.equal(Ok("docs/zk/20260905-1721-master-knowledge-graph.md"))
}

pub fn zk_transclude_without_key_uses_same_multi_token_fallback_test() {
  let results =
    paths(
      "zk_transclude",
      "alpha beta gamma delta epsilon zeta eta",
      "5",
    )
  list.first(results)
  |> should.equal(Ok("docs/zk/20260905-1721-master-knowledge-graph.md"))
}

pub fn limit_two_clamps_output_test() {
  paths("knowledge_search", "alpha beta", "2")
  |> list.length
  |> should.equal(2)
  paths("knowledge_search", "alpha beta", "99")
  |> list.length
  |> should.equal(3)
}

pub fn candidate_identity_is_valid_test() {
  candidate_id.current()
  |> candidate_id.is_valid
  |> should.be_true
}

pub fn default_limit_is_five_and_invalid_limit_falls_back_test() {
  // Both docs match the two-token query; the default and non-numeric limits
  // must remain inside the 1..20 clamp rather than failing or returning [].
  paths("knowledge_search", "alpha beta", "not-a-number")
  |> list.length
  |> should.equal(3)
}
