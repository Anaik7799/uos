open Core

module Observation = Sa_plan.Observation
module Store = Sa_plan.Store

let max_input_bytes = 65_536

let emit json =
  Yojson.Safe.to_string json |> Out_channel.output_string stdout;
  Out_channel.output_char stdout '\n';
  Out_channel.flush stdout

let fail_json code message =
  emit (`Assoc [ "status", `String "error"; "error", `String message ]);
  exit code

let read_stdin_bounded () =
  let chunk = Bytes.create 4_096 in
  let buffer = Buffer.create 4_096 in
  let rec loop total =
    let count = Stdlib.input Stdlib.stdin chunk 0 (Bytes.length chunk) in
    if count = 0 then Ok (Buffer.contents buffer)
    else if total + count > max_input_bytes then
      Error (Printf.sprintf "stdin exceeds %d bytes" max_input_bytes)
    else begin
      Buffer.add_subbytes buffer chunk ~pos:0 ~len:count;
      loop (total + count)
    end
  in
  loop 0

let parse_input () =
  match read_stdin_bounded () with
  | Error message -> fail_json 64 message
  | Ok bytes ->
      (try Yojson.Safe.from_string bytes
       with Yojson.Json_error message -> fail_json 64 ("invalid JSON: " ^ message))

let run_hash () =
  match Observation.computed_payload_hash_of_yojson (parse_input ()) with
  | Error message -> fail_json 64 message
  | Ok payload_hash ->
      emit
        (`Assoc
          [ "status", `String "hash_computed";
            "payload_hash", `String payload_hash ])

let run_ingest path =
  let source, observation =
    match Observation.of_yojson (parse_input ()) with
    | Ok value -> value
    | Error message -> fail_json 64 message
  in
  let store =
    match Store.open_db path with
    | Ok store -> store
    | Error message -> fail_json 70 message
  in
  let result =
    Exn.protect
    ~f:(fun () -> Observation.ingest store source observation)
    ~finally:(fun () -> Store.close store)
  in
  match result with
  | Error message -> fail_json 70 message
  | Ok outcome ->
      emit (Observation.outcome_to_yojson outcome);
      (match outcome with
      | Observation.Observation_accepted _ -> ()
      | Reconciliation_required _ -> exit 2)

let usage () =
  fail_json 64 "usage: sa-plan-observation hash | ingest --db PATH"

let () =
  match Array.to_list (Sys.get_argv ()) with
  | [ _; "hash" ] -> run_hash ()
  | [ _; "ingest"; "--db"; path ] when not (String.is_empty path) ->
      run_ingest path
  | _ -> usage ()
