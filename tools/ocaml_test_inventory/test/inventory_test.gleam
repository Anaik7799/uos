import envoy
import gleam/list
import gleeunit
import gleeunit/should
import ocaml_test_inventory/files
import ocaml_test_inventory/inventory.{
  CannotRead, CensusInput, Changed, Entry, Indexed, Missing, NotFound,
  Unreadable, UnreadableDepth,
}
import simplifile

pub fn main() {
  gleeunit.main()
}

pub fn altered_bytes_fail_preservation_test() {
  inventory.verify_entries(
    [
      Entry(
        "fixture.ml",
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      ),
    ],
    fn(_) { Ok(<<"abd":utf8>>) },
  )
  |> should.equal([Changed("fixture.ml")])
}

const abc_sha = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

pub fn known_sha256_and_matching_bytes_test() {
  inventory.digest(<<"abc":utf8>>) |> should.equal(abc_sha)
  inventory.verify_entries([Entry("fixture.ml", abc_sha)], fn(_) {
    Ok(<<"abc":utf8>>)
  })
  |> should.equal([])
}

pub fn missing_and_unreadable_are_distinct_test() {
  inventory.verify_entries([Entry("absent.ml", abc_sha)], fn(_) {
    Error(NotFound)
  })
  |> should.equal([Missing("absent.ml")])
  inventory.verify_entries([Entry("denied.ml", abc_sha)], fn(_) {
    Error(CannotRead)
  })
  |> should.equal([Unreadable("denied.ml")])
}

pub fn invalid_inventory_never_invokes_reader_test() {
  let invalid_sets = [
    [],
    [Entry("a.ml", abc_sha), Entry("a.ml", abc_sha)],
    [Entry("safe.ml", abc_sha), Entry("../escape.ml", abc_sha)],
    [Entry("/absolute.ml", abc_sha)],
    [Entry("a//b.ml", abc_sha)],
    [Entry("./a.ml", abc_sha)],
    [Entry("a/../b.ml", abc_sha)],
    [Entry("a\\b.ml", abc_sha)],
    [Entry("nul\u{0}.ml", abc_sha)],
    [Entry("a.ml", "abcd")],
    [
      Entry(
        "a.ml",
        "za7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      ),
    ],
  ]
  list.each(invalid_sets, fn(entries) {
    inventory.verify_entries(entries, fn(_) {
      panic as "invalid input caused read"
    })
    |> list.is_empty
    |> should.be_false
  })
}

pub fn real_file_matching_altered_and_missing_test() {
  let assert Ok(root) = envoy.get("UOS_INVENTORY_TEST_ROOT")
  let path = root <> "/fixture.ml"
  let entries = [Entry("fixture.ml", abc_sha)]
  let assert Ok(_) = simplifile.write(path, "abc")
  files.verify(root, entries) |> should.equal([])
  let assert Ok(_) = simplifile.write(path, "abd")
  files.verify(root, entries) |> should.equal([Changed("fixture.ml")])
  simplifile.read(path) |> should.equal(Ok("abd"))
  let assert Ok(_) = simplifile.delete_file(path)
  files.verify(root, entries) |> should.equal([Missing("fixture.ml")])
}

pub fn symlinks_and_directories_are_not_read_test() {
  let assert Ok(root) = envoy.get("UOS_INVENTORY_TEST_ROOT")
  let target = root <> "/target.ml"
  let link = root <> "/link.ml"
  let assert Ok(_) = simplifile.write(target, "abc")
  let assert Ok(_) = simplifile.create_symlink(target, link)
  files.verify(root, [Entry("link.ml", abc_sha)])
  |> should.equal([Unreadable("link.ml")])
  files.read_checked(root) |> should.equal(Error(CannotRead))
  let assert Ok(_) = simplifile.delete_file(link)
  let assert Ok(_) = simplifile.delete_file(target)
}

pub fn noncanonical_roots_are_rejected_test() {
  list.each(["/", "/tmp/", "relative", "/tmp/../tmp"], fn(root) {
    files.verify(root, [Entry("fixture.ml", abc_sha)])
    |> list.is_empty
    |> should.be_false
  })
}

pub fn census_oracle_and_fold_are_observationally_equal_test() {
  let input =
    CensusInput(
      files: [
        "registered_test.ml",
        "helper.ml",
        "journal.md",
        "unreadable.md",
      ],
      registered_tests: ["registered_test.ml"],
      ast_sites: 3,
      unreadable: ["unreadable.md"],
    )
  let assert Ok(reference) = inventory.classify_census_reference(input)
  let assert Ok(final) = inventory.classify_census(input)
  inventory.observe_census(final)
  |> should.equal(inventory.observe_census(reference))
  final.files_accounted |> should.equal(4)
  final.unreadable_count |> should.equal(1)
  final.complete_review |> should.be_false
  final.executed_tests |> should.equal(0)
  final.registered_test_files |> should.equal(1)
  final.ast_sites |> should.equal(3)
  list.length(final.review_frontier) |> should.equal(4)
  final.files_accounted
  |> should.equal(
    final.reviewed_files + final.classified_exclusions + final.frontier_count,
  )
}

pub fn census_invalid_scope_fails_closed_test() {
  let invalid = [
    CensusInput([], [], 0, []),
    CensusInput(["a.ml", "a.ml"], ["a.ml"], 1, []),
    CensusInput(["a.ml"], ["absent.ml"], 1, []),
    CensusInput(["a.ml"], [], -1, []),
    CensusInput(["../escape.ml"], [], 0, []),
  ]
  list.each(invalid, fn(input) {
    inventory.classify_census(input) |> should.be_error
  })
}

pub fn census_exclusions_and_frontier_are_disjoint_test() {
  let input =
    CensusInput(
      files: ["artifact.cmo", "open.md"],
      registered_tests: [],
      ast_sites: 0,
      unreadable: [],
    )
  let assert Ok(summary) = inventory.classify_census(input)
  summary.files_accounted |> should.equal(2)
  summary.classified_exclusions |> should.equal(1)
  summary.frontier_count |> should.equal(1)
  summary.reviewed_files |> should.equal(0)
}

pub fn read_observation_does_not_claim_hash_or_close_review_test() {
  let assert Ok(root) = envoy.get("UOS_INVENTORY_TEST_ROOT")
  let path = root <> "/observed.ml"
  let assert Ok(_) = simplifile.write(path, "let observed = true")
  files.observe_read(root, "observed.ml") |> should.equal(Indexed)
  let assert Ok(_) = simplifile.delete_file(path)
  files.observe_read(root, "observed.ml") |> should.equal(UnreadableDepth)
}
