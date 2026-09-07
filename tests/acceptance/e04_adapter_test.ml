#use "./tests/acceptance/registry.ml";;
#use "./tools/source_review/census.ml";;
#use "./tests/acceptance/e04_adapter.ml";;

let checks = ref 0
let check condition message = incr checks; if not condition then failwith message

let given =
  `Assoc
    [ ("files", `List (List.map (fun value -> `String value)
        [ "registered_test.ml"; "helper.ml"; "journal.md"; "unreadable.md" ]));
      ("registered_tests", `List [ `String "registered_test.ml" ]);
      ("ast_sites", `Int 3);
      ("unreadable", `List [ `String "unreadable.md" ]) ]

let () =
  let observation = census_classify_operation given in
  check observation.operation_supported "operation must be supported";
  check observation.adapter_registered "adapter must be registered";
  check (observation.built && observation.executed && observation.passed)
    "classification path must execute and pass";
  check (observation.exit_code = 0 && observation.status = Status_pass)
    "successful classification must report exit zero/PASS";
  let projection = observation_projection observation in
  let expected =
    `Assoc [ ("files_accounted", `Int 4); ("unreadable", `Int 1);
             ("complete_review", `Bool false); ("executed_tests", `Int 0) ]
  in
  check (assert_expected expected projection = []) "manifest expectation must match observations";
  let with_extra = match given with `Assoc fields -> `Assoc (("expect", `Assoc []) :: fields) | _ -> assert false in
  check (not (census_classify_operation with_extra).executed)
    "extra fields must fail before execution";
  let duplicate = match given with `Assoc fields -> `Assoc (("ast_sites", `Int 3) :: fields) | _ -> assert false in
  check (not (census_classify_operation duplicate).executed)
    "duplicate fields must fail before execution";
  let wrong_type = match given with
    | `Assoc fields -> `Assoc (("ast_sites", `String "3") :: List.remove_assoc "ast_sites" fields)
    | _ -> assert false
  in
  check (not (census_classify_operation wrong_type).executed)
    "wrong field types must fail before execution";
  Printf.printf "e04_adapter_test: %d checks passed\n" !checks

