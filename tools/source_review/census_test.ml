#use "./tools/source_review/census.ml";;

let checks = ref 0

let check condition message =
  incr checks;
  if not condition then failwith message

let expect_ok = function Ok value -> value | Error error -> failwith (string_of_error error)

let fixture =
  { files = [ "registered_test.ml"; "helper.ml"; "journal.md"; "unreadable.md" ];
    registered_tests = [ "registered_test.ml" ];
    ast_sites = 3;
    unreadable = [ "unreadable.md" ] }

let () =
  let reference = expect_ok (classify_reference fixture) in
  let final = expect_ok (classify fixture) in
  check (observe_summary reference = observe_summary final)
    "reference and fold interpretations must be observationally equivalent";
  check (final.files_accounted = 4) "all unique scoped files must be accounted";
  check (final.unreadable_count = 1) "unreadable inputs must remain explicit";
  check (not final.complete_review) "indexed or unreadable files cannot be called close-read";
  check (final.executed_tests = 0) "classification must not manufacture execution";
  check (final.registered_test_files = 1) "registration counts files, not assertions";
  check (final.ast_sites = 3) "AST site evidence is retained separately";
  check (List.length final.review_frontier = 4) "every non-close-read file remains in the frontier";
  check
    (final.files_accounted = final.reviewed_files + final.classified_exclusions + final.frontier_count)
    "reviewed, excluded and frontier states must close the scoped-file accounting equation";
  check
    (List.length (List.sort_uniq String.compare (List.map (fun row -> row.source_id) final.records)) = 4)
    "stable source identifiers must be unique";
  check
    (match classify { fixture with files = "registered_test.ml" :: fixture.files } with
     | Error (Invalid_input _) -> true | _ -> false)
    "duplicate files must fail closed";
  check
    (match classify { fixture with registered_tests = [ "absent.ml" ] } with
     | Error (Invalid_input _) -> true | _ -> false)
    "registered tests must be scoped files";
  check
    (match classify { fixture with unreadable = [ "../escape" ] } with
     | Error (Invalid_input _) -> true | _ -> false)
    "unreadable locators must be scoped canonical files";
  let excluded = expect_ok (classify
    { files = [ "artifact.cmo"; "open.md" ]; registered_tests = [];
      ast_sites = 0; unreadable = [] }) in
  check
    (excluded.classified_exclusions = 1 && excluded.frontier_count = 1
     && excluded.files_accounted = 2)
    "generated/binary exclusions must be disjoint from the remaining frontier";

  let syntax_text =
    String.concat "\n"
      [ "(test"; " (name census_test))";
        "import gleeunit/should";
        "pub fn one_test() {"; "  result |> should.equal(1)"; "}";
        "pub fn two_test() {"; "  result |> should.be_true"; "}";
        "use ExUnit.Case";
        "test \"three\" do"; "  assert result"; "end";
        "Feature: bounded census";
        "Scenario: fourth"; "Given a source"; "Then it is classified";
        "Scenario Outline: fifth"; "When the table is expanded"; "Then one case exists" ]
  in
  let cases = enumerate_syntax_cases ~path:"fixture.txt" ~text:syntax_text in
  check (List.length cases = 6)
    "Dune, Gleeunit, ExUnit and Gherkin declarations must each count once";
  check
    (List.fold_left (fun count case -> count + List.length case.oracle_lines) 0 cases = 7)
    "assertions and Gherkin steps must attach as oracle lines, not cases";
  check
    (List.length (List.sort_uniq String.compare (List.map (fun case -> case.case_id) cases)) = 6)
    "case identifiers must be stable and unique";
  check
    (List.for_all (fun case -> case.span.start_line <= case.span.end_line) cases)
    "every enumerated case must retain a nonempty source span";
  check
    (List.exists (fun (case : syntax_case) -> List.mem "import gleeunit/should" case.imports) cases)
    "import edges must remain attached to enumerated cases";
  check
    (List.exists (fun case -> List.mem "should.equal" case.calls) cases)
    "call edges must be enumerated independently from declarations";

  check
    (match validate_json_tree "duplicate-control"
       (`Assoc [ ("x", `Int 1); ("x", `Int 2) ]) with
     | Error (Invalid_index _) -> true | _ -> false)
    "duplicate JSON fields must fail closed";
  check
    (match validate_json_tree "nonfinite-control" (`Float nan) with
     | Error (Invalid_index _) -> true | _ -> false)
    "nonfinite JSON numbers must fail closed";
  let rec nested depth value = if depth = 0 then value else nested (depth - 1) (`List [ value ]) in
  check
    (match validate_json_tree "depth-control" (nested 65 `Null) with
     | Error (Invalid_index _) -> true | _ -> false)
    "excessively nested JSON must fail closed";

  let regular = Filename.temp_file "uos-e04-regular-" ".json" in
  let link = regular ^ ".link" in
  Fun.protect
    ~finally:(fun () ->
      (try Unix.unlink link with Unix.Unix_error _ -> ());
      (try Unix.unlink regular with Unix.Unix_error _ -> ()))
    (fun () ->
      let channel = open_out_bin regular in
      output_string channel "abc";
      close_out channel;
      check
        (verify_artifact_digest regular
          "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
         = Ok ())
        "artifact bindings must accept the exact observed SHA256";
      check
        (match verify_artifact_digest regular (String.make 64 '0') with
         | Error (Invalid_index _) -> true | _ -> false)
        "artifact bindings must reject a stale SHA256";
      check
        (match read_regular_bounded ~limit:2 regular with
         | Error (Io_error _) -> true | _ -> false)
        "bounded reads must reject over-quota regular files";
      Unix.symlink regular link;
      check
        (match read_regular_bounded ~limit:16 link with
         | Error (Io_error _) -> true | _ -> false)
        "bounded reads must reject symlink leaves");

  let inventory =
    expect_ok (verify_ocaml_inventory
      "docs/journal/20260906-0428-ocaml-web-tests-inventory.json")
  in
  check (inventory.inventory_records = 161) "OCaml inventory must retain 161 source records";
  check (inventory.raw_sites = 1479) "raw OCaml site count must reconcile to 1479";
  check (inventory.unique_sites = 1479 && inventory.duplicate_sites = 0)
    "the 1479 OCaml sites must be unique by source/kind/label/span";
  check (inventory.parsed_records = 161 && inventory.unrun_records = 161)
    "parsed and executed states must remain distinct";

  let corpus =
    expect_ok (verify_partitioned_index
      ~index_path:"docs/design/20260906-0631-source-corpus-index.json"
      ~expected_parts:24 ~expected_records:8047)
  in
  check (corpus.verified_parts = 24 && corpus.verified_records = 8047)
    "all 24 corpus partitions and 8047 records must verify";
  check (corpus.duplicate_records = 0 && corpus.unique_records = 8047)
    "corpus records must have unique project/root/path identities";
  check (corpus.execution_unrun = 8044 && corpus.execution_unknown = 3)
    "corpus execution states must preserve UNRUN and UNKNOWN";

  let catalogue =
    expect_ok (verify_partitioned_index
      ~index_path:"docs/design/20260906-0631-cross-project-test-catalogue.json"
      ~expected_parts:12 ~expected_records:770)
  in
  check (catalogue.verified_parts = 12 && catalogue.verified_records = 770)
    "all 12 catalogue partitions and 770 records must verify";
  check (catalogue.duplicate_records = 0 && catalogue.unique_records = 770)
    "catalogue records must have unique project/root/path identities";
  check (catalogue.execution_unrun = 770 && catalogue.execution_unknown = 0)
    "catalogue execution state must remain UNRUN";

  Printf.printf "census_test: %d checks passed\n" !checks
