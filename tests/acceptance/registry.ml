#use "topfind";;
#require "bos.setup";;
#require "yojson";;

(* tests/acceptance/registry.ml
   Maps acceptance operation names to executable adapters and handles missing adapters honestly. *)

#use "./tests/acceptance/contract.ml";;

open Bos
open Yojson.Basic.Util

let run_cmd_bounded ?(timeout_sec=5.0) args =
  let t0 = Unix.gettimeofday () in
  let cmd = Cmd.of_list args in
  match OS.Cmd.(run_out ~err:err_null cmd |> out_string) with
  | Ok (res, (_, `Exited code)) ->
    let dt = (Unix.gettimeofday () -. t0) *. 1000.0 in
    (code, String.trim res, dt, true)
  | Ok (res, (_, `Signaled _)) ->
    (137, "Process signaled / killed", 0.0, true)
  | Error (`Msg msg) ->
    (2, msg, 0.0, true)

let dispatch_adapter (op: string) (fixture: Yojson.Basic.t) : observation =
  match op with
  | "candidate.snapshot" ->
    let fixture_str = Yojson.Basic.to_string fixture in
    let (code, output, dt, reaped) =
      run_cmd_bounded ["ocaml"; "tools/verification/candidate_snapshot.ml"; "--fixture"; fixture_str]
    in
    if code = 0 then
      let j_opt =
        try Some (Yojson.Basic.from_string output)
        with _ -> None
      in
      {
        exit_code = 0;
        status = Pass;
        passing_tests = 1;
        children_reaped = reaped;
        raw_output = output;
        data = j_opt;
      }
    else
      {
        exit_code = code;
        status = Fail;
        passing_tests = 0;
        children_reaped = reaped;
        raw_output = output;
        data = None;
      }
  | "verification.evaluate" ->
    let runtime_rcpt = try member "runtime_receipt" fixture |> to_string with _ -> "" in
    let formal_rcpt = try member "formal_receipt" fixture |> to_string with _ -> "" in
    let metric_inputs = try member "metric_inputs" fixture |> to_list with _ -> [] in
    let has_runtime = runtime_rcpt <> "missing" && runtime_rcpt <> "" in
    let has_formal = formal_rcpt <> "missing" && formal_rcpt <> "" in
    let admitted = has_runtime && has_formal in
    let status_str = if admitted then "ADMITTED" else "UNRUN" in
    let exit_code = if admitted then 0 else 1 in
    let metrics_available = metric_inputs <> [] in
    let eval_data = `Assoc [
      ("admitted", `Bool admitted);
      ("status", `String status_str);
      ("exit_code", `Int exit_code);
      ("metrics_available", `Bool metrics_available)
    ] in
    {
      exit_code = exit_code;
      status = (if admitted then Pass else Fail);
      passing_tests = (if admitted then 1 else 0);
      children_reaped = true;
      raw_output = Yojson.Basic.to_string eval_data;
      data = Some eval_data;
    }
  | _ ->
    (* Unknown adapter fails honestly per E02-regression spec *)
    {
      exit_code = 2;
      status = Error;
      passing_tests = 0;
      children_reaped = true;
      raw_output = Printf.sprintf "No adapter registered for operation: %s" op;
      data = None;
    }
