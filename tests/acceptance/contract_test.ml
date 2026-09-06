#!/usr/bin/env -S opam exec -- ocaml
#use "./tests/acceptance/contract.ml";;

let checks = ref 0
let check name condition =
  incr checks;
  if not condition then failwith ("contract test failed: " ^ name)

let error_path = function Error error -> error.path | Ok _ -> ""

let valid_case =
  `Assoc
    [ ("id", `String "E02-regression");
      ("given", `Assoc [ ("adapter", `String "missing_adapter"); ("required", `Bool true);
                          ("expected_exit", `Int 0); ("fixture", `String "temporary_isolated") ]);
      ("when", `List [ `Assoc [ ("op", `String "runner.verify") ] ]);
      ("expect", `Assoc [ ("exit_code", `Int 2) ]) ]

let () =
  check "valid acceptance case" (Result.is_ok (decode_acceptance_case valid_case));
  check "outer duplicate rejected"
    (error_path (parse_json_strict "{\"a\":1,\"a\":2}") = "$.a");
  check "nested duplicate rejected"
    (error_path (parse_json_strict "{\"a\":{\"b\":1,\"b\":2}}") = "$.a.b");
  check "malformed JSON rejected" (Result.is_error (parse_json_strict "{"));
  let extra_fixture =
    `Assoc [ ("adapter", `String "missing_adapter"); ("required", `Bool true);
             ("expected_exit", `Int 0); ("fixture", `String "temporary_isolated");
             ("extra", `Bool true) ]
  in
  check "extra fixture field rejected" (Result.is_error (decode_runner_fixture extra_fixture));
  check "missing fixture field rejected"
    (Result.is_error (decode_runner_fixture (`Assoc [ ("adapter", `String "missing_adapter") ])));
  check "wrong fixture type rejected"
    (Result.is_error (decode_runner_fixture
      (`Assoc [ ("adapter", `String "missing_adapter"); ("required", `String "true");
                ("expected_exit", `Int 0); ("fixture", `String "temporary_isolated") ])));
  check "path-like adapter rejected"
    (Result.is_error (decode_runner_fixture
      (`Assoc [ ("adapter", `String "../escape"); ("required", `Bool true);
                ("expected_exit", `Int 0); ("fixture", `String "temporary_isolated") ])));
  let expected = `Assoc [ ("a", `Assoc [ ("b", `List [ `Int 1; `String "x" ]) ]) ] in
  check "recursive assertion passes"
    (assert_expected expected (`Assoc [ ("a", `Assoc [ ("b", `List [ `Int 1; `String "x" ]);
                                                        ("extra", `Bool true) ]) ]) = []);
  let mismatches = assert_expected expected (`Assoc [ ("a", `Assoc [ ("b", `List [ `Int 1; `String "y" ]) ]) ]) in
  check "recursive mismatch path"
    (match mismatches with [ item ] -> item.mismatch_path = "$.a.b[1]" | _ -> false);
  check "numeric type is exact" (assert_expected (`Int 1) (`Float 1.) <> []);
  check "array length is exact" (assert_expected (`List [ `Int 1 ]) (`List [ `Int 1; `Int 2 ]) <> []);
  check "exact object rejects extra"
    (assert_expected ~exact:true (`Assoc [ ("a", `Int 1) ]) (`Assoc [ ("a", `Int 1); ("b", `Int 2) ]) <> []);
  let observation =
    { operation_supported = true; adapter_registered = false; built = true; executed = true;
      passed = false; exit_code = 2; status = Error; passing_tests = 0; children_reaped = true;
      timed_out = false; stdout_overflow = false; stderr_overflow = false; stdout = "";
      stderr = "missing"; duration_ms = 1.; data = None }
  in
  let receipt =
    { receipt_id = "r"; task_id = "E02"; case_id = "E02-regression"; operation = "runner.verify";
      observed_at_utc = "2026-09-06T00:00:00Z";
      manifest = { binding_path = "manifest"; binding_sha256 = String.make 64 'a' };
      candidate = { change_id = String.make 32 'c'; commit_id = String.make 40 'd'; workspace = "/tmp/w" };
      source = { binding_path = "tests/acceptance/run.ml"; binding_sha256 = String.make 64 'e' };
      limits = { receipt_timeout_ms = 1000; receipt_stdout_bytes = 10; receipt_stderr_bytes = 10;
                 receipt_term_grace_ms = 10 };
      observation; assertion_passed = true; assertion_mismatches = [];
      assertion_duration_ms = 0.1; receipt_write_ms = 0.2 }
  in
  let json = receipt_to_yojson receipt in
  check "receipt closed top-level field count"
    (match json with `Assoc fields -> List.length fields = 15 | _ -> false);
  check "receipt has distinct states"
    (Yojson.Basic.Util.member "states" json
     |> Yojson.Basic.Util.member "passed" |> Yojson.Basic.Util.to_bool = false);
  Printf.printf "contract_test: %d checks passed\n" !checks
