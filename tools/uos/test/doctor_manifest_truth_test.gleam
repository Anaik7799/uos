import gleam/list
import gleeunit/should
import main

fn observed(manifest) {
  main.doctor_manifest_results(manifest, fn(path) { path == "present.md" })
}
pub fn empty_and_comments_never_pass_test() {
  list.each(["", "\n", "  \n# history only\n"], fn(value) {
    observed(value) |> main.doctor_manifest_passes |> should.be_false()
  })
}
pub fn valid_inventory_is_scoped_positive_control_test() {
  observed("1\tpresent.md\tObserved file")
  |> should.equal([#("1", "INVENTORY", "Observed file")])
  observed("1\tpresent.md\tObserved file") |> main.doctor_manifest_passes |> should.be_true()
}
pub fn malformed_identity_and_shape_refuse_test() {
  list.each(["x", "abc\tpresent.md\tlabel", "0\tpresent.md\tlabel",
    "-1\tpresent.md\tlabel", "01\tpresent.md\tlabel", "1\t\tlabel",
    "1\tpresent.md\t", "1\tpresent.md\tlabel\textra"], fn(value) {
    observed(value) |> main.doctor_manifest_passes |> should.be_false()
  })
}
pub fn duplicate_ev_refuses_even_existing_artifacts_test() {
  observed("1\tpresent.md\tfirst\n1\tpresent.md\tsecond")
  |> main.doctor_manifest_passes |> should.be_false()
}
pub fn missing_unknown_and_quarantined_refuse_test() {
  list.each(["1\tmissing.md\tmissing", "1\t-\tunverifiable",
    "94\tpresent.md\tquarantined"], fn(value) {
    observed(value) |> main.doctor_manifest_passes |> should.be_false()
  })
}
pub fn unsafe_artifact_paths_never_observed_test() {
  list.each(["/present.md", "../present.md", "a/../present.md", "a//b",
    "a\\b", "a\u{0}b"], fn(path) {
    main.doctor_manifest_results("1\t" <> path <> "\tlabel",
      fn(_) { panic as "malformed path must not reach artifact observer" })
    |> main.doctor_manifest_passes |> should.be_false()
  })
}
