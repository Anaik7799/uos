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
    (enumerate_syntax_cases ~path:"dune"
       ~text:"(executable\n (name production_server))" = [])
    "production executable stanzas must not be counted as test cases";
  check
    (enumerate_syntax_cases ~path:"disabled.gleam"
       ~text:"/*\npub fn disabled_test() {\n  should.fail()\n}\n*/" = [])
    "block-commented declarations must not be counted";
  check
    (enumerate_syntax_cases ~path:"literal.gleam"
       ~text:"const example = \"pub fn disabled_test() {\"" = [])
    "declaration-shaped string literals must not be counted";
  check
    (List.for_all
       (fun case -> case.confidence = "LEXICAL_CANDIDATE_NOT_AST_OR_RUNNER_CONFIRMED")
       cases)
    "lexical candidates must not claim registration or AST certainty";

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
  check
    (match parse_json "preparse-depth-control"
       (String.make 65 '[' ^ "null" ^ String.make 65 ']') with
     | Error (Invalid_index _) -> true | _ -> false)
    "excessive raw JSON depth must be rejected before the parser";
  check
    (match parse_json "preparse-nonfinite-control" "{\"x\":NaN}" with
     | Error (Invalid_index _) -> true | _ -> false)
    "raw nonfinite JSON tokens must be rejected before the parser";

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

  let replacement = Filename.temp_file "uos-e04-bound-index-" ".json" in
  Fun.protect
    ~finally:(fun () -> try Unix.unlink replacement with Unix.Unix_error _ -> ())
    (fun () ->
      let write value =
        let channel = open_out_bin replacement in
        Fun.protect ~finally:(fun () -> close_out_noerr channel)
          (fun () -> output_string channel value)
      in
      let second =
        "{\"source_root\":\"/tmp\",\"records\":[{\"path\":\"a\",\"sites\":[],\"parse_status\":\"parsed\",\"execution_status\":\"UNRUN\"}]}"
      in
      let first_prefix = "{\"source_root\":\"/tmp\",\"records\":[]" in
      let first = first_prefix ^ String.make (String.length second - String.length first_prefix - 1) ' ' ^ "}" in
      check (String.length first = String.length second) "replacement control must preserve byte length";
      write first;
      check
        (match verify_ocaml_inventory replacement with
         | Error (Invalid_index _) -> true | _ -> false)
        "inventory parsing without an explicit bound digest must fail closed";
      let report = expect_ok (verify_ocaml_inventory ~expected_sha256:(sha256 first) replacement) in
      check (report.inventory_records = 0) "bound parser must accept its exact descriptor bytes";
      write second;
      check
        (match verify_ocaml_inventory ~expected_sha256:(sha256 first) replacement with
         | Error (Invalid_index _) -> true | _ -> false)
        "a post-binding replacement must fail before parsing different bytes");

  let inventory =
    expect_ok (verify_ocaml_inventory
      ~expected_sha256:"d9b9a71e32de595ff2d04f1dd027ba05ebd743b7c92dc9313bcf155a0f9eb5ee"
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
      ~expected_sha256:"7f2b1f93824211ebd8fe6e37756adc299760952fd7fe879bded1eb5b85cae1c7"
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
      ~expected_sha256:"475739f4b9485b01fee471fd130bb7adc7d2c95351178458f070cc29ccced603"
      ~expected_parts:12 ~expected_records:770)
  in
  check (catalogue.verified_parts = 12 && catalogue.verified_records = 770)
    "all 12 catalogue partitions and 770 records must verify";
  check (catalogue.duplicate_records = 0 && catalogue.unique_records = 770)
    "catalogue records must have unique project/root/path identities";
  check (catalogue.execution_unrun = 770 && catalogue.execution_unknown = 0)
    "catalogue execution state must remain UNRUN";

  let ledger = expect_ok (repository_ledger ()) in
  let ledger_fields = match ledger with `Assoc fields -> fields | _ -> failwith "ledger object" in
  let rows name = match List.assoc name ledger_fields with
    | `List values -> values | _ -> failwith (name ^ " list") in
  let identity = match List.assoc "identity_checks" ledger_fields with
    | `Assoc fields -> fields | _ -> failwith "identity checks" in
  let int name = match List.assoc name identity with `Int value -> value | _ -> -1 in
  let bool name = match List.assoc name identity with `Bool value -> value | _ -> false in
  check (List.length (rows "bindings") = 39)
    "ledger must bind three top indexes and all 36 partitions";
  check (int "source_rows" = 8978 && bool "source_ids_unique")
    "every record in all three scopes must have a unique stable source identity";
  check (int "case_rows" = 25244 && bool "case_ids_unique")
    "all old static case/site rows must have unique stable case identities";
  let accounting = rows "scope_accounting" in
  check
    (List.for_all (function
       | `Assoc fields -> List.assoc_opt "accounting_closed" fields = Some (`Bool true)
       | _ -> false) accounting)
    "every scope must close reviewed plus excluded plus explicit frontier accounting";
  check
    (List.for_all (function
       | `Assoc fields -> List.mem_assoc "source_id" fields && List.mem_assoc "frontier" fields
                          && List.mem_assoc "execution_state" fields
       | _ -> false) (rows "source_records"))
    "every source record must expose identity, frontier and execution state";
  check
    (List.for_all (function
       | `Assoc fields -> List.mem_assoc "case_id" fields && List.mem_assoc "span" fields
                          && List.mem_assoc "oracle_state" fields
                          && List.mem_assoc "browser_class" fields
                          && List.mem_assoc "runner" fields
       | _ -> false) (rows "case_records"))
    "every case candidate must expose ID, span, oracle, browser and runner state";
  let ledger_path = Filename.temp_file "uos-e04-ledger-" ".json" in
  Fun.protect
    ~finally:(fun () -> try Unix.unlink ledger_path with Unix.Unix_error _ -> ())
    (fun () ->
      let ledger_text = Yojson.Basic.to_string ledger ^ "\n" in
      check (String.length ledger_text < max_ledger_bytes) "ledger must fit its publication bound";
      (match write_ledger_atomic ledger_path ledger_text with
       | Error error -> failwith (string_of_error error)
       | Ok () -> ());
      let observed = expect_ok (read_regular_bounded ~limit:max_ledger_bytes ledger_path) in
      check (sha256 observed = sha256 ledger_text) "atomic ledger bytes must match the reviewed ledger");

  Printf.printf "census_test: %d checks passed\n" !checks
