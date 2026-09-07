#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "digestif.ocaml,yojson";;

#use "./tests/acceptance/registry.ml";;

(** Generic, candidate-bound acceptance runner.  [run_task] is importable;
    command-line parsing runs only when this file is the direct script. *)

let immutable_manifest_sha256 =
  "b706f9a99dfaf6018772b2a819084ea3373a3ee720ed774b57e7f92792d8ee02"

let runner_source_path = "tests/acceptance/registry.ml"
let maximum_manifest_bytes = 4 * 1024 * 1024
let bound_source_paths =
  [ "tools/verification/candidate_snapshot.ml";
    "tests/acceptance/contract.ml";
    "tests/acceptance/process_supervisor.ml";
    "tests/acceptance/registry.ml";
    "tests/acceptance/run.ml";
    "tests/acceptance/golden/receipt.schema.json";
    "tests/acceptance/compiler_diagnostics.ml";
    "apps/cepaf_gleam/gleam.toml";
    "apps/cepaf_gleam/manifest.toml";
    "apps/cepaf_gleam/test/c3i_knowledge_actor_test.gleam";
    "apps/cepaf_gleam/test/c3i_knowledge_runtime_test.gleam";
    "apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_runtime.gleam";
    "apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_actor.gleam";
    "apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_ingestion_actor.gleam" ]

type case_execution = {
  case : acceptance_case;
  observation : observation;
  mismatches : assertion_mismatch list;
  assertion_passed : bool;
  assertion_duration_ms : float;
}

type task_execution = {
  execution : case_execution;
  receipt : receipt;
  receipt_path : string option;
}

type checked_file = {
  checked_bytes : string;
  checked_binding : binding;
  checked_stat : Unix.stats;
}

let same_file before after =
  before.Unix.st_dev = after.Unix.st_dev
  && before.Unix.st_ino = after.Unix.st_ino
  && before.Unix.st_kind = after.Unix.st_kind
  && before.Unix.st_uid = after.Unix.st_uid
  && before.Unix.st_size = after.Unix.st_size
  && before.Unix.st_mtime = after.Unix.st_mtime
  && before.Unix.st_ctime = after.Unix.st_ctime

let validate_regular ~maximum path stat =
  if stat.Unix.st_kind <> Unix.S_REG then Error (path ^ ": expected regular file")
  else if stat.Unix.st_uid <> Unix.getuid () then Error (path ^ ": owner mismatch")
  else if stat.Unix.st_size < 0 || stat.Unix.st_size > maximum then
    Error (path ^ ": exceeds byte limit")
  else Ok ()

let read_descriptor_bounded ~maximum descriptor =
  let buffer = Bytes.create 65_536 in
  let contents = Buffer.create (min maximum 65_536) in
  let rec loop total =
    let request = min 65_536 (maximum - total + 1) in
    let count = Unix.read descriptor buffer 0 request in
    if count = 0 then Ok (Buffer.contents contents)
    else if total > maximum - count then Error "descriptor exceeds byte limit"
    else begin
      Buffer.add_subbytes contents buffer 0 count;
      loop (total + count)
    end
  in
  loop 0

let read_checked_file ~maximum path =
  try
    let before = Unix.lstat path in
    match validate_regular ~maximum path before with
    | Error _ as error -> error
    | Ok () ->
        let descriptor =
          Unix.openfile path [ Unix.O_RDONLY; Unix.O_CLOEXEC; Unix.O_NONBLOCK ] 0
        in
        Fun.protect ~finally:(fun () -> Unix.close descriptor) (fun () ->
          let opened = Unix.fstat descriptor in
          if not (same_file before opened) then
            Error (path ^ ": changed before descriptor validation")
          else
            match validate_regular ~maximum path opened with
            | Error _ as error -> error
            | Ok () ->
                match read_descriptor_bounded ~maximum descriptor with
                | Error message -> Error (path ^ ": " ^ message)
                | Ok bytes ->
                    let closed_view = Unix.fstat descriptor in
                    let after = Unix.lstat path in
                    if not (same_file opened closed_view && same_file opened after) then
                      Error (path ^ ": changed while being read")
                    else
                      Ok
                        { checked_bytes = bytes;
                          checked_binding =
                            { binding_path = path;
                              binding_sha256 = sha256_string bytes };
                          checked_stat = opened })
  with Sys_error message | Unix.Unix_error (_, _, message) -> Error (path ^ ": " ^ message)

let read_regular_bounded ~maximum path =
  match read_checked_file ~maximum path with
  | Error _ as error -> error
  | Ok checked -> Ok checked.checked_bytes

let rec read_binding_set acc = function
  | [] -> Ok (List.rev acc)
  | path :: rest ->
      match read_checked_file ~maximum:1_048_576 path with
      | Error _ as error -> error
      | Ok checked -> read_binding_set (checked.checked_binding :: acc) rest

let binding_sets_equal left right =
  List.length left = List.length right
  && List.for_all2
       (fun a b ->
         a.binding_path = b.binding_path
         && a.binding_sha256 = b.binding_sha256)
       left right

let load_acceptance_case ~expected_manifest_sha256 backlog_path task_id =
  match read_regular_bounded ~maximum:maximum_manifest_bytes backlog_path with
  | Error _ as error -> error
  | Ok bytes ->
      let digest = sha256_string bytes in
      if digest <> expected_manifest_sha256 then
        Error
          (Printf.sprintf "manifest digest mismatch: expected %s, observed %s"
             expected_manifest_sha256 digest)
      else
        match parse_json_strict bytes with
        | Error error -> Error (string_of_contract_error error)
        | Ok manifest ->
            match decode_task_acceptance task_id manifest with
            | Error error -> Error (string_of_contract_error error)
            | Ok case -> Ok (case, digest)

let execute_case case =
  match case.actions with
  | [ action ] ->
      let operation_started = monotonic_now () in
      let observed = dispatch_operation action.op case.given in
      let observation =
        { observed with
          duration_ms = (monotonic_now () -. operation_started) *. 1000. }
      in
      let assertion_started = monotonic_now () in
      let mismatches = assert_expected case.expect (observation_projection observation) in
      let assertion_duration_ms = (monotonic_now () -. assertion_started) *. 1000. in
      let meaningful_expectation =
        match case.expect with `Assoc fields -> fields <> [] | _ -> false
      in
      let mismatches =
        if meaningful_expectation then mismatches
        else
          mismatch "$.expect" "expectation object must be nonempty"
            (Some case.expect) None :: mismatches
      in
      let assertion_passed =
        observation.operation_supported && meaningful_expectation && mismatches = []
      in
      { case; observation; mismatches; assertion_passed; assertion_duration_ms }
  | _ ->
      let observation =
        error_observation ~operation_supported:false ~built:false ~executed:false
          "this runner version requires exactly one action"
      in
      let mismatch =
        mismatch "$.when" "unsupported action count" None
          (Some (`Int (List.length case.actions)))
      in
      { case; observation; mismatches = [ mismatch ]; assertion_passed = false;
        assertion_duration_ms = 0. }

let identity_limits =
  { timeout_ms = 5_000; stdout_limit = 4096; stderr_limit = 4096; term_grace_ms = 100 }

let current_identity () =
  let template = "change_id ++ \"\\n\" ++ commit_id ++ \"\\n\"" in
  let result =
    run_bounded identity_limits
      [ "jj"; "--no-pager"; "log"; "-r"; "@"; "--no-graph"; "-T"; template ]
  in
  match result.termination, result.stdout_truncated, result.stderr_truncated with
  | Exited 0, false, false ->
      (match String.split_on_char '\n' (String.trim result.stdout) with
       | [ change_id; commit_id ]
         when String.length change_id >= 32 && String.length commit_id = 40 ->
           Ok { change_id; commit_id; workspace = Unix.realpath (Sys.getcwd ()) }
       | _ -> Error "jj identity output has the wrong shape")
  | _ -> Error ("could not bind current candidate identity: " ^ result.stderr)

let utc_now () =
  let tm = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

let timestamp_prefix () =
  let tm = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d%02d%02d-%02d%02d"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_sec

let invocation_nonce () =
  Printf.sprintf "%Ld-%08x" (Mtime_clock.elapsed_ns ()) (Random.bits ())

let ensure_directory path =
  if Sys.file_exists path then
    if not (Sys.is_directory path) then Error (path ^ ": receipt directory is not a directory")
    else Ok ()
  else
    try Unix.mkdir path 0o700; Ok ()
    with Unix.Unix_error (_, _, message) -> Error (path ^ ": " ^ message)

let write_all descriptor bytes =
  let rec loop offset =
    if offset < String.length bytes then
      let wrote = Unix.write_substring descriptor bytes offset (String.length bytes - offset) in
      if wrote = 0 then failwith "zero-byte receipt write" else loop (offset + wrote)
  in
  loop 0

let atomic_write path bytes =
  let directory = Filename.dirname path in
  let basename = Filename.basename path in
  let temporary =
    Filename.concat directory
      (Printf.sprintf ".%s.%d.%08x.tmp" basename (Unix.getpid ()) (Random.bits ()))
  in
  let descriptor =
    Unix.openfile temporary [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL ] 0o600
  in
  let renamed = ref false in
  Fun.protect
    ~finally:(fun () ->
      (try Unix.close descriptor with Unix.Unix_error _ -> ());
      if not !renamed then (try Unix.unlink temporary with Unix.Unix_error _ -> ()))
    (fun () ->
      write_all descriptor bytes;
      Unix.fsync descriptor;
      Unix.close descriptor;
      Unix.rename temporary path;
      renamed := true;
      let directory_fd = Unix.openfile directory [ Unix.O_RDONLY ] 0 in
      Fun.protect ~finally:(fun () -> Unix.close directory_fd)
        (fun () -> Unix.fsync directory_fd))

let safe_task_name value =
  String.map
    (function 'A' .. 'Z' as c -> Char.lowercase_ascii c
            | 'a' .. 'z' | '0' .. '9' | '-' | '_' as c -> c
            | _ -> '_')
    value

let run_task ?(emit_receipt = true)
    ?(receipt_dir = "/tmp/uos-acceptance-receipts")
    ?(expected_manifest_sha256 = immutable_manifest_sha256)
    ?expected_candidate_commit backlog_path task_id =
  match load_acceptance_case ~expected_manifest_sha256 backlog_path task_id with
  | Error _ as error -> error
  | Ok (case, manifest_digest) ->
      match current_identity () with
      | Error _ as error -> error
      | Ok candidate ->
          match expected_candidate_commit with
          | Some expected when candidate.commit_id <> expected ->
              Error
                (Printf.sprintf "candidate revision mismatch: expected %s, observed %s"
                   expected candidate.commit_id)
          | _ ->
              match read_binding_set [] bound_source_paths with
              | Error _ as error -> error
              | Ok sources ->
                  let execution = execute_case case in
                  match
                    load_acceptance_case ~expected_manifest_sha256 backlog_path task_id,
                    current_identity (),
                    read_binding_set [] bound_source_paths
                  with
                  | Ok (case_after, digest_after), Ok candidate_after, Ok sources_after
                    when digest_after = manifest_digest
                         && case_after = case
                         && candidate_after = candidate
                         && binding_sets_equal sources sources_after ->
                      let operation =
                        match case.actions with
                        | [ action ] -> action.op
                        | _ -> "runner.invalid-actions"
                      in
                      let nonce = invocation_nonce () in
                      let receipt_id =
                        Printf.sprintf "RCPT-ACCEPT-%s-%s-%s"
                          task_id (timestamp_prefix ()) nonce
                      in
                      let base_receipt calibration_ms =
                        { receipt_id; task_id; case_id = case.case_id; operation;
                          observed_at_utc = utc_now ();
                          manifest = { binding_path = backlog_path;
                                       binding_sha256 = manifest_digest };
                          candidate; sources;
                          limits = execution.observation.applied_limits;
                          observation = execution.observation;
                          assertion_passed = execution.assertion_passed;
                          assertion_mismatches = execution.mismatches;
                          assertion_duration_ms = execution.assertion_duration_ms;
                          receipt_write_calibration_ms = calibration_ms }
                      in
                      if not emit_receipt then
                        Ok { execution; receipt = base_receipt 0.; receipt_path = None }
                      else (
                        match ensure_directory receipt_dir with
                        | Error _ as error -> error
                        | Ok () -> (
                            let path =
                              Filename.concat receipt_dir
                                (Printf.sprintf "%s-%s-task-%s-acceptance-receipt.json"
                                   (timestamp_prefix ()) nonce (safe_task_name task_id))
                            in
                            try
                              (* This separately named calibration measures the same
                                 serializer and fsync/rename path.  The final receipt is
                                 subsequently published by one atomic write. *)
                              let calibration = path ^ ".calibration" in
                              let calibration_receipt = base_receipt 0. in
                              let started = monotonic_now () in
                              atomic_write calibration
                                (Yojson.Basic.to_string
                                   (receipt_to_yojson calibration_receipt) ^ "\n");
                              let calibration_ms =
                                (monotonic_now () -. started) *. 1000.
                              in
                              Unix.unlink calibration;
                              let final_receipt = base_receipt calibration_ms in
                              atomic_write path
                                (Yojson.Basic.pretty_to_string
                                   (receipt_to_yojson final_receipt) ^ "\n");
                              Ok { execution; receipt = final_receipt;
                                   receipt_path = Some path }
                            with
                            | Sys_error message | Failure message ->
                                Error ("receipt write failed: " ^ message)
                            | Unix.Unix_error (_, _, message) ->
                                Error ("receipt write failed: " ^ message)))
                  | Ok _, Ok _, Ok _ ->
                      Error "candidate, manifest, or source binding changed during execution"
                  | Error message, _, _ | _, Error message, _ | _, _, Error message ->
                      Error ("post-execution binding failed: " ^ message)

let direct_invocation () =
  Filename.basename Sys.argv.(0) = "run.ml"

let main () =
  let backlog = ref "" in
  let task = ref "" in
  let receipt_dir = ref "/tmp/uos-acceptance-receipts" in
  let options =
    [ ("--backlog", Arg.Set_string backlog, "Path to immutable backlog JSON");
      ("--task", Arg.Set_string task, "Task ID");
      ("--receipt-dir", Arg.Set_string receipt_dir, "Atomic receipt directory") ]
  in
  Arg.parse options (fun _ -> raise (Arg.Bad "positional arguments are not accepted"))
    "run.ml --backlog PATH --task ID";
  if !backlog = "" || !task = "" then begin
    prerr_endline "run.ml: --backlog and --task are required";
    2
  end else
    match run_task ~receipt_dir:!receipt_dir !backlog !task with
    | Error message ->
        prerr_endline ("acceptance runner error: " ^ message);
        2
    | Ok result ->
        Printf.printf "task=%s case=%s operation=%s assertion=%s underlying=%s passing_tests=%d\n"
          !task result.execution.case.case_id result.receipt.operation
          (if result.execution.assertion_passed then "PASS" else "FAIL")
          (string_of_status result.execution.observation.status)
          result.execution.observation.passing_tests;
        Option.iter (Printf.printf "receipt=%s\n") result.receipt_path;
        if result.execution.assertion_passed then 0 else 1

let () = if direct_invocation () then exit (main ())
