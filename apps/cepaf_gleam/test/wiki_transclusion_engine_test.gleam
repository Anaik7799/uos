import cepaf_gleam/ui/lustre/wiki_transclusion_engine
import gleeunit/should

pub fn extract_transclusion_tags_test() {
  let doc = "See [[wiki:20260905-1801-corpus]] and [[zk:ADR-001]] for details."
  let tags = wiki_transclusion_engine.extract_transclusion_tags(doc)
  should.equal(tags, [
    wiki_transclusion_engine.WikiTag("20260905-1801-corpus"),
    wiki_transclusion_engine.ZkTag("ADR-001"),
  ])
}

pub fn cycle_guard_detection_test() {
  // Depth 17 exceeds maximum allowed depth of 16
  wiki_transclusion_engine.check_transclusion_depth(17)
  |> should.equal(wiki_transclusion_engine.DepthExceeded)

  wiki_transclusion_engine.check_transclusion_depth(5)
  |> should.equal(wiki_transclusion_engine.DepthSafe)
}

pub fn parsoid_roundtrip_fidelity_test() {
  let input = "# Heading\nParagraph with [[wiki:test]] content."
  let ast = wiki_transclusion_engine.parse_to_ast(input)
  let serialized = wiki_transclusion_engine.serialize_ast(ast)
  should.equal(serialized, input)
}

pub fn myers_diff_computation_test() {
  let old_lines = ["line 1", "line 2", "line 3"]
  let new_lines = ["line 1", "line 2 modified", "line 3", "line 4"]
  let diff = wiki_transclusion_engine.compute_simple_diff(old_lines, new_lines)
  should.be_true(diff.additions >= 1)
}
