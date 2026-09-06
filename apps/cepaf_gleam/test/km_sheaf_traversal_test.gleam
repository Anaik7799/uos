import cepaf_gleam/ui/lustre/km_sheaf_traversal
import gleeunit/should

pub fn block_anchor_extraction_test() {
  let text =
    "Here is a decision rule ^adr-rule-01\nAnother statement ^adr-rule-02"
  let anchors = km_sheaf_traversal.extract_block_anchors(text)
  should.equal(anchors, ["adr-rule-01", "adr-rule-02"])
}

pub fn sheaf_consistency_check_test() {
  let s1 = km_sheaf_traversal.Section("page_a", "state_digest_alpha")
  let s2 = km_sheaf_traversal.Section("page_b", "state_digest_alpha")
  km_sheaf_traversal.check_sheaf_compatibility(s1, s2)
  |> should.be_true()
}

pub fn dung_argumentation_resolution_test() {
  let rule = km_sheaf_traversal.build_dung_framework()
  should.be_true(rule.unattacked_invariants >= 5)
}
