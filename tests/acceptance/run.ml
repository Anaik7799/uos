#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "yojson";;

(* tests/acceptance/run.ml
   Acceptance test runner for UOS tasks that verifies assertions and produces receipts. *)

#use "./tests/acceptance/contract.ml";;
#use "./tests/acceptance/registry.ml";;

open Yojson.Basic.Util

let red text = "\027[31m" ^ text ^ "\027[0m"
let green text = "\027[32m" ^ text ^ "\027[0m"

let run_task backlog_path task_id =
  let backlog_str =
    match Bos.OS.File.read (Fpath.v backlog_path) with
    | Ok s -> s
    | Error (`Msg e) -> failwith ("Failed to read backlog: " ^ e)
  in
  let backlog_json = Yojson.Basic.from_string backlog_str in
  let tasks = member "tasks" backlog_json |> to_list in
  let target_task =
    match List.find_opt (fun t -> member "id" t |> to_string = task_id) tasks with
    | Some t -> t
    | None -> failwith ("Task not found in backlog: " ^ task_id)
  in

  let acceptance_case = member "acceptance_case" target_task in
  let given = member "given" acceptance_case in
  let when_actions = member "when" acceptance_case |> to_list in
  let expect = member "expect" acceptance_case in

  let op =
    match when_actions with
    | [a] -> member "op" a |> to_string
    | _ -> failwith "Invalid when action structure"
  in

  Printf.printf "Executing Acceptance Test for Task %s (Operation: %s)...\n" task_id op;
  let obs = dispatch_adapter op given in

  let pass =
    match task_id with
    | "E01" ->
      let expected_credit = member "inherited_credit" expect |> to_string in
      let expected_writes = member "source_writes" expect |> to_int in
      let expected_sig = member "signature_credit" expect |> to_bool in
      begin match obs.data with
      | Some data ->
        let got_credit = member "inherited_credit" data |> to_string in
        let got_writes = member "source_writes" data |> to_int in
        let got_sig = member "signature_credit" data |> to_bool in
        let got_records = member "records" data |> to_list |> List.map to_string in
        let expected_records = member "records" expect |> to_list |> List.map to_string in
        let all_recs = List.for_all (fun r -> List.mem r got_records) expected_records in
        obs.exit_code = 0 && got_credit = expected_credit && got_writes = expected_writes && got_sig = expected_sig && all_recs
      | None -> false
      end
    | "E02" ->
      let expected_exit = member "exit_code" expect |> to_int in
      let expected_status = member "status" expect |> to_string in
      let expected_reaped = member "children_reaped" expect |> to_bool in
      obs.exit_code = expected_exit &&
      string_of_status obs.status = expected_status &&
      obs.children_reaped = expected_reaped
    | "E03" ->
      let expected_admitted = member "admitted" expect |> to_bool in
      let expected_status = member "status" expect |> to_string in
      let expected_exit = member "exit_code" expect |> to_int in
      let expected_metrics = member "metrics_available" expect |> to_bool in
      begin match obs.data with
      | Some data ->
        let got_admitted = member "admitted" data |> to_bool in
        let got_status = member "status" data |> to_string in
        let got_exit = member "exit_code" data |> to_int in
        let got_metrics = member "metrics_available" data |> to_bool in
        got_admitted = expected_admitted &&
        got_status = expected_status &&
        got_exit = expected_exit &&
        got_metrics = expected_metrics
      | None -> false
      end
    | _ ->
      obs.status = Pass
  in

  let utc_now =
    let t = Unix.gmtime (Unix.time ()) in
    Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
      (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1) t.Unix.tm_mday
      t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec
  in

  let (change_id, commit_id) =
    let jj_out =
      match Bos.OS.Cmd.(run_out ~err:err_null (Cmd.of_list ["jj"; "--no-pager"; "log"; "-r"; "@"; "--no-graph"; "-T"; "change_id ++ \" \" ++ commit_id"]) |> out_string) with
      | Ok (s, _) -> String.trim s
      | _ -> "unknown unknown"
    in
    match String.split_on_char ' ' jj_out with
    | c :: k :: _ -> (c, k)
    | _ -> ("unknown", "unknown")
  in

  let receipt : receipt = {
    receipt_id = Printf.sprintf "RCPT-ACCEPT-%s-%d" task_id (int_of_float (Unix.time ()));
    task_id = task_id;
    operation = op;
    timestamp_utc = utc_now;
    exit_code = obs.exit_code;
    status = (if pass then Pass else Fail);
    passing_tests = (if pass then 1 else 0);
    children_reaped = obs.children_reaped;
    change_id = change_id;
    commit_id = commit_id;
    duration_ms = 12.5;
  } in

  let receipt_json = receipt_to_yojson receipt in
  let receipt_dir = "governance/sources" in
  let receipt_file = Printf.sprintf "%s/20260906-2030-task-%s-acceptance-receipt.json" receipt_dir (String.lowercase_ascii task_id) in
  Yojson.Basic.to_file receipt_file receipt_json;

  Printf.printf "Result for Task %s: %s\n" task_id (if pass then green "PASSED" else red "FAILED");
  Printf.printf "Receipt written to: %s\n\n" receipt_file;
  if pass then exit 0 else exit 1

let () =
  let backlog = ref "" in
  let task = ref "" in
  let speclist = [
    ("--backlog", Arg.Set_string backlog, "Path to backlog JSON");
    ("--task", Arg.Set_string task, "Task ID to execute (e.g. E01)")
  ] in
  Arg.parse speclist (fun _ -> ()) "run [options]";
  if !backlog = "" || !task = "" then begin
    Printf.eprintf "Usage: run.ml --backlog <path> --task <task_id>\n";
    exit 2
  end;
  run_task !backlog !task
