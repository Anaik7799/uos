#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "yojson";;

(* tests/acceptance/runner_test.ml
   Acceptance test for Task E02 (runner.verify):
   Verifies that unknown/missing adapters fail honestly with exit code 2 and ERROR status. *)

#use "./tests/acceptance/contract.ml";;
#use "./tests/acceptance/registry.ml";;

let red text = "\027[31m" ^ text ^ "\027[0m"
let green text = "\027[32m" ^ text ^ "\027[0m"

let test_e02_regression () =
  Printf.printf "Executing Acceptance Case: E02-regression (runner.verify)...\n";
  let fixture = `Assoc [
    ("adapter", `String "missing_adapter");
    ("required", `Bool true);
    ("expected_exit", `Int 0);
    ("fixture", `String "temporary_isolated")
  ] in

  (* Dispatch unknown adapter *)
  let obs = dispatch_adapter "runner.verify" fixture in

  let expected_exit = 2 in
  let expected_status = Error in
  let expected_passing = 0 in
  let expected_reaped = true in

  let pass =
    obs.exit_code = expected_exit &&
    obs.status = expected_status &&
    obs.passing_tests = expected_passing &&
    obs.children_reaped = expected_reaped
  in

  Printf.printf "  - exit_code = %d (expected %d) : %s\n"
    obs.exit_code expected_exit (if obs.exit_code = expected_exit then green "PASS" else red "FAIL");
  Printf.printf "  - status = %s (expected ERROR) : %s\n"
    (string_of_status obs.status) (if obs.status = expected_status then green "PASS" else red "FAIL");
  Printf.printf "  - passing_tests = %d (expected %d) : %s\n"
    obs.passing_tests expected_passing (if obs.passing_tests = expected_passing then green "PASS" else red "FAIL");
  Printf.printf "  - children_reaped = %b (expected %b) : %s\n"
    obs.children_reaped expected_reaped (if obs.children_reaped = expected_reaped then green "PASS" else red "FAIL");

  if not pass then failwith "E02-regression assertion failed";

  (* Positive control *)
  let pos_obs = dispatch_adapter "candidate.snapshot" (`Assoc [("candidate", `String "current-jj"); ("evidence_candidate", `String "current-jj")]) in
  Printf.printf "Positive Control Case (registered adapter):\n";
  Printf.printf "  - exit_code = %d (expected 0) : %s\n"
    pos_obs.exit_code (if pos_obs.exit_code = 0 then green "PASS" else red "FAIL");
  Printf.printf "  - status = %s (expected PASS) : %s\n"
    (string_of_status pos_obs.status) (if pos_obs.status = Pass then green "PASS" else red "FAIL");

  if pos_obs.exit_code <> 0 || pos_obs.status <> Pass then
    failwith "Positive control failed";

  Printf.printf "\n%s Task E02 acceptance suite passed 100%% green.\n" (green "[PASS]")

let () =
  try
    test_e02_regression ();
    exit 0
  with Failure msg ->
    Printf.eprintf "%s: %s\n" (red "[FAIL]") msg;
    exit 1
