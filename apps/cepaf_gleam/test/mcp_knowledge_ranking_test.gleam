import cepaf_gleam/mcp/adapters/knowledge as km
import cepaf_gleam/mcp/types.{Complete}
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleeunit/should

fn corpus() {
  let rows = [
    #("docs/wiki/alpha-beta.md", "public", "# Topic\nbody"),
    #("docs/wiki/z.md", "public", "# ALPHA BETA\nbody"),
    #("docs/wiki/private.md", "private", "# ALPHA BETA"),
    #("docs/zk/adr-001.md", "public", "# ΣΊΓΜΑ CAFÉ\nRepeated αλφα"),
    #("docs/zk/adr-010.md", "public", "# ADR-001 reference"),
  ]
  list.fold(
    rows,
    km.new_corpus("/workspace", ["public", "private"], 4096, 8),
    fn(c, r) { km.with_entry(c, km.CorpusEntry(r.0, km.RegularFile, r.1, r.2)) },
  )
}

fn paths(query: String, limit: String) -> List(String) {
  let assert Complete(body, _) =
    km.execute(
      corpus(),
      ["public"],
      "knowledge_search",
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

pub fn path_rank_precedes_heading_rank_and_private_scope_is_excluded_test() {
  paths("ALPHA BETA", "5")
  |> should.equal(["docs/wiki/alpha-beta.md", "docs/wiki/z.md"])
}

pub fn unicode_search_preserves_case_and_diacritic_matching_test() {
  paths("café", "5") |> should.equal(["docs/zk/adr-001.md"])
  paths("ΣΊΓΜΑ", "5") |> should.equal(["docs/zk/adr-001.md"])
  paths("αλφα", "5") |> should.equal(["docs/zk/adr-001.md"])
}

pub fn exact_adr_does_not_match_body_reference_or_longer_identifier_test() {
  paths("ADR-001", "5") |> should.equal(["docs/zk/adr-001.md"])
}

pub fn limits_empty_matches_and_normalized_transclusion_are_preserved_test() {
  paths("ALPHA BETA", "1") |> should.equal(["docs/wiki/alpha-beta.md"])
  paths("missing", "5") |> should.equal([])
  paths("[[zk:ADR-001]]", "5") |> should.equal(["docs/zk/adr-001.md"])
}
