#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "yojson";;

(* @agent_intent Acceptance test for Task E01 (candidate.snapshot):
   Asserts fixture E01-regression against tools/verification/candidate_snapshot.ml. *)

open Bos
open Yojson.Basic.Util

let red text = "\027[31m" ^ text ^ "\027[0m"
let green text = "\027[32m" ^ text ^ "\027[0m"

let run_cmd args =
  match OS.Cmd.(run_out ~err:err_null (Cmd.of_list args) |> out_string) with
  | Ok (res, (_, `Exited 0)) -> String.trim res
  | _ -> failwith "Failed to execute command"

let test_e01_regression () =
  let fixture = {|{
    "candidate": "current-jj",
    "evidence_candidate": "older-jj",
    "source_mode": "read_only",
    "clock_source": "chrony",
    "inherited_claim": "all_passed"
  }|} in

  let tool_path = "tools/verification/candidate_snapshot.ml" in
  let out_json = run_cmd ["ocaml"; tool_path; "--fixture"; fixture] in
  let json = Yojson.Basic.from_string out_json in

  let inherited_credit = member "inherited_credit" json |> to_string in
  let source_writes = member "source_writes" json |> to_int in
  let signature_credit = member "signature_credit" json |> to_bool in
  let records = member "records" json |> to_list |> List.map to_string in

  let expected_records = [
    "change_id"; "commit_id"; "dirty_manifest"; "served_build";
    "tool_versions"; "clock_receipt"
  ] in

  let all_records_present =
    List.for_all (fun r -> List.mem r records) expected_records
  in

  let pass =
    inherited_credit = "STALE" &&
    source_writes = 0 &&
    signature_credit = false &&
    all_records_present
  in

  Printf.printf "Acceptance Case: E01-regression\n";
  Printf.printf "  - inherited_credit = %s (expected STALE) : %s\n"
    inherited_credit (if inherited_credit = "STALE" then green "PASS" else red "FAIL");
  Printf.printf "  - source_writes = %d (expected 0) : %s\n"
    source_writes (if source_writes = 0 then green "PASS" else red "FAIL");
  Printf.printf "  - signature_credit = %b (expected false) : %s\n"
    signature_credit (if not signature_credit then green "PASS" else red "FAIL");
  Printf.printf "  - all 6 required records present : %s\n"
    (if all_records_present then green "PASS" else red "FAIL");

  if not pass then failwith "E01-regression assertion failed";

  (* Positive Control: matching candidate *)
  let matching_fixture = {|{
    "candidate": "current-jj",
    "evidence_candidate": "current-jj",
    "source_mode": "read_only",
    "clock_source": "chrony",
    "inherited_claim": "all_passed"
  }|} in
  let out_pos = run_cmd ["ocaml"; tool_path; "--fixture"; matching_fixture] in
  let json_pos = Yojson.Basic.from_string out_pos in
  let pos_credit = member "inherited_credit" json_pos |> to_string in
  let pos_sig = member "signature_credit" json_pos |> to_bool in
  Printf.printf "Positive Control Case:\n";
  Printf.printf "  - inherited_credit = %s (expected SUPPORTED) : %s\n"
    pos_credit (if pos_credit = "SUPPORTED" then green "PASS" else red "FAIL");
  Printf.printf "  - signature_credit = %b (expected true) : %s\n"
    pos_sig (if pos_sig then green "PASS" else red "FAIL");

  if pos_credit <> "SUPPORTED" || not pos_sig then
    failwith "Positive control assertion failed";

  Printf.printf "\n%s Task E01 acceptance suite passed 100%% green.\n" (green "[PASS]")

let () =
  try
    test_e01_regression ();
    exit 0
  with Failure msg ->
    Printf.eprintf "%s: %s\n" (red "[FAIL]") msg;
    exit 1
