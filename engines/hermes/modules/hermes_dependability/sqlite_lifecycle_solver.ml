open Sqlite_lifecycle_model

let read_file path =
  match open_in_bin path with
  | exception exn -> Error (Printexc.to_string exn)
  | channel ->
      Fun.protect
        ~finally:(fun () -> close_in_noerr channel)
        (fun () ->
          match really_input_string channel (in_channel_length channel) with
          | contents -> Ok contents
          | exception exn -> Error (Printexc.to_string exn))

let write_file path contents =
  match open_out_bin path with
  | exception exn -> Error (Printexc.to_string exn)
  | channel ->
      Fun.protect
        ~finally:(fun () -> close_out_noerr channel)
        (fun () ->
          match output_string channel contents; flush channel with
          | () -> Ok ()
          | exception exn -> Error (Printexc.to_string exn))

let remove_if_present path =
  match Sys.remove path with () -> () | exception Sys_error _ -> ()

let close_noerr descriptor =
  match Unix.close descriptor with () -> () | exception Unix.Unix_error _ -> ()

let rec kill_noerr_with kill pid signal =
  match kill pid signal with
  | () -> true
  | exception Unix.Unix_error (Unix.EINTR, _, _) ->
      kill_noerr_with kill pid signal
  | exception Unix.Unix_error _ -> false

let kill_noerr pid signal = kill_noerr_with Unix.kill pid signal

let rec waitpid_retry wait flags pid =
  match wait flags pid with
  | result -> result
  | exception Unix.Unix_error (Unix.EINTR, _, _) ->
      waitpid_retry wait flags pid

let wait_briefly_until deadline_ns =
  let remaining_ns = Int64.sub deadline_ns (Mtime_clock.elapsed_ns ()) in
  if Int64.compare remaining_ns 0L <= 0 then ()
  else
    let remaining_seconds = Int64.to_float remaining_ns /. 1_000_000_000.0 in
    ignore (Unix.select [] [] [] (min 0.01 remaining_seconds))

let rec wait_until pid deadline_ns =
  match waitpid_retry Unix.waitpid [ Unix.WNOHANG; Unix.WUNTRACED ] pid with
  | 0, _ ->
      if Int64.compare (Mtime_clock.elapsed_ns ()) deadline_ns >= 0 then None
      else begin
        wait_briefly_until deadline_ns;
        wait_until pid deadline_ns
      end
  | _, (Unix.WEXITED _ | Unix.WSIGNALED _ as status) -> Some status
  | _, Unix.WSTOPPED _ ->
      if Int64.compare (Mtime_clock.elapsed_ns ()) deadline_ns >= 0 then None
      else begin
        wait_briefly_until deadline_ns;
        wait_until pid deadline_ns
      end

let reap_until pid deadline_ns =
  match wait_until pid deadline_ns with
  | Some _ -> true
  | None -> false
  | exception Unix.Unix_error (Unix.ECHILD, _, _) -> true
  | exception Unix.Unix_error _ -> false

type supervised_result = {
  pid : int option;
  status : (Unix.process_status, string) result;
  reaped : bool;
}

let terminate_and_reap pid ~cleanup_deadline_ns reason =
  ignore (kill_noerr pid Sys.sigterm);
  let grace_deadline =
    Int64.min cleanup_deadline_ns
      (Int64.add (Mtime_clock.elapsed_ns ()) 500_000_000L)
  in
  match wait_until pid grace_deadline with
  | Some _ -> { pid = Some pid; status = Error reason; reaped = true }
  | None | exception _ ->
      ignore (kill_noerr pid Sys.sigkill);
      let reaped = reap_until pid cleanup_deadline_ns in
      { pid = Some pid; status = Error reason; reaped }

let supervise pid ~deadline_ns ~cleanup_deadline_ns ~signal_immediately =
  if signal_immediately then begin
    ignore (kill_noerr pid Sys.sigterm);
    match wait_until pid deadline_ns with
    | Some status -> { pid = Some pid; status = Ok status; reaped = true }
    | None ->
        terminate_and_reap pid ~cleanup_deadline_ns
          "signalled child did not terminate by deadline"
    | exception exn ->
        terminate_and_reap pid ~cleanup_deadline_ns
          ("signal supervision failed: " ^ Printexc.to_string exn)
  end else
    match wait_until pid deadline_ns with
    | Some status -> { pid = Some pid; status = Ok status; reaped = true }
    | None ->
        terminate_and_reap pid ~cleanup_deadline_ns
          "child exceeded monotonic deadline"
    | exception exn ->
        terminate_and_reap pid ~cleanup_deadline_ns
          ("monotonic process supervision failed: " ^ Printexc.to_string exn)

let run_process ~program ~argv ~stdout_path ~stderr_path ~deadline_ns
    ~cleanup_deadline_ns ~signal_immediately =
  let descriptors = ref [] in
  let remember descriptor =
    descriptors := descriptor :: !descriptors;
    descriptor
  in
  let close_descriptors () =
    List.iter close_noerr !descriptors;
    descriptors := []
  in
  match
    let stdout_fd =
      Unix.openfile stdout_path
        [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o600
      |> remember
    in
    let stderr_fd =
      Unix.openfile stderr_path
        [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o600
      |> remember
    in
    let stdin_fd =
      Unix.openfile Filename.null [ Unix.O_RDONLY ] 0o400 |> remember
    in
    Unix.create_process program argv stdin_fd stdout_fd stderr_fd
  with
  | exception exn ->
      close_descriptors ();
      { pid = None; status = Error (Printexc.to_string exn); reaped = true }
  | pid ->
      close_descriptors ();
      supervise pid ~deadline_ns ~cleanup_deadline_ns ~signal_immediately

let status_unavailable ~program = function
  | Unix.WEXITED code ->
      Printf.sprintf "%s exited %d" program code
  | Unix.WSIGNALED signal ->
      Printf.sprintf "%s was signalled (%d)" program signal
  | Unix.WSTOPPED signal ->
      Printf.sprintf "%s was stopped (%d)" program signal

let create_temp_set () =
  let created = ref [] in
  let make prefix suffix =
    let path = Filename.temp_file prefix suffix in
    created := path :: !created;
    path
  in
  match
    let script_path = make "hermes-sqlite-lifecycle-" ".smt2" in
    let stdout_path = make "hermes-sqlite-z3-out-" ".txt" in
    let stderr_path = make "hermes-sqlite-z3-err-" ".txt" in
    (script_path, stdout_path, stderr_path)
  with
  | paths -> Ok (!created, paths)
  | exception exn ->
      List.iter remove_if_present !created;
      Error (Printexc.to_string exn)

type batch_receipt = {
  receipt_batch_id : string;
  receipt_batch_digest : string;
  receipt_elapsed_ns : int64;
  receipt_answers : int;
  receipt_prefix_answers : int;
  receipt_first_unanswered : string option;
  receipt_stdout_bytes : int;
  receipt_stdout_digest : string;
  receipt_stderr_bytes : int;
  receipt_stderr_digest : string;
  receipt_reaped : bool;
  receipt_verdict : verdict;
}

type batch_run = {
  run_verdict : verdict;
  run_receipts : batch_receipt list;
  run_elapsed_ns : int64;
}

let run_z3_script ~script ~deadline_ns ~validate =
  let observed_reaped = ref true in
  let observed_stdout = ref "" in
  let observed_stderr = ref "" in
  let solve_deadline_ns = Int64.sub deadline_ns 2_000_000_000L in
  let verdict =
    if String.trim script = "" then Unavailable "empty SMT-LIB script"
    else
      match create_temp_set () with
      | Error detail ->
          Unavailable ("cannot create solver temporary files: " ^ detail)
      | Ok (created, (script_path, stdout_path, stderr_path)) ->
          Fun.protect
            ~finally:(fun () -> List.iter remove_if_present created)
            (fun () ->
              match write_file script_path script with
              | Error detail ->
                  Unavailable ("cannot write SMT-LIB input: " ^ detail)
              | Ok () ->
                  let remaining_ns =
                    Int64.sub solve_deadline_ns (Mtime_clock.elapsed_ns ())
                  in
                  let timeout_seconds =
                    if Int64.compare remaining_ns 0L <= 0 then 0
                    else
                      max 1
                        (Int64.to_int
                           (Int64.div
                              (Int64.add remaining_ns 999_999_999L)
                              1_000_000_000L))
                  in
                  if timeout_seconds = 0 then
                    Unavailable "global solver deadline exhausted before spawn"
                  else
                    let process =
                      run_process ~program:"z3"
                        ~argv:
                          [| "z3"; Printf.sprintf "-T:%d" timeout_seconds;
                             "-smt2"; script_path |]
                        ~stdout_path ~stderr_path
                        ~deadline_ns:solve_deadline_ns
                        ~cleanup_deadline_ns:deadline_ns
                        ~signal_immediately:false
                    in
                    observed_reaped := process.reaped;
                    let output =
                      match read_file stdout_path, read_file stderr_path with
                      | Error detail, _ | _, Error detail -> Error detail
                      | Ok stdout, Ok stderr ->
                          observed_stdout := stdout;
                          observed_stderr := stderr;
                          Ok (stdout, stderr)
                    in
                    if not process.reaped then
                      Unavailable
                        "z3 supervision returned without a reaped child"
                    else
                      match output with
                      | Error detail ->
                          Unavailable ("cannot read z3 output: " ^ detail)
                      | Ok (stdout, stderr) ->
                          let stderr = String.trim stderr in
                          begin match process.status with
                          | Error detail ->
                              Unavailable
                                ("z3 invocation unavailable: " ^ detail)
                          | Ok (Unix.WEXITED 0)
                            when not (String.equal stderr "") ->
                              Unavailable ("z3 emitted stderr: " ^ stderr)
                          | Ok (Unix.WEXITED 0) -> validate stdout
                          | Ok other ->
                              let detail =
                                status_unavailable ~program:"z3" other
                              in
                              Unavailable
                                (if String.equal stderr "" then detail
                                 else detail ^ ": " ^ stderr)
                          end)
  in
  (verdict, !observed_reaped, !observed_stdout, !observed_stderr)

let run_z3 ~script =
  let deadline_ns = Int64.add (Mtime_clock.elapsed_ns ()) 30_000_000_000L in
  let verdict, _, _, _ =
    run_z3_script ~script ~deadline_ns ~validate:validate_solver_output
  in
  verdict

let canonical_answer_prefix (batch : smt_batch) output =
  let lines =
    output |> String.split_on_char '\n' |> List.map String.trim
    |> List.filter (fun line -> not (String.equal line ""))
  in
  let rec count total expected observed =
    match expected, observed with
    | obligation :: rest, id :: ("sat" | "unsat") :: tail
      when String.equal obligation.id id ->
        count (total + 1) rest tail
    | _, _ -> total
  in
  let answered = count 0 batch.batch_obligations lines in
  let first_unanswered =
    match List.nth_opt batch.batch_obligations answered with
    | None -> None
    | Some obligation -> Some obligation.id
  in
  (answered, first_unanswered)

let run_batch ~deadline_ns (batch : smt_batch) =
  let batch_started = Mtime_clock.elapsed_ns () in
  let verdict, reaped, stdout, stderr =
    if not (batch_is_canonical batch) then
      (Unavailable "batch is not an exact canonical campaign member", true,
       "", "")
    else
      run_z3_script ~script:batch.batch_script ~deadline_ns
        ~validate:(validate_batch_output batch)
  in
  let prefix_answers, first_unanswered = canonical_answer_prefix batch stdout in
  { receipt_batch_id = batch.batch_id;
    receipt_batch_digest = batch.batch_digest;
    receipt_elapsed_ns =
      Int64.sub (Mtime_clock.elapsed_ns ()) batch_started;
    receipt_answers =
      (match verdict with
       | Proved | Refuted _ -> List.length batch.batch_obligations
       | Unavailable _ -> 0);
    receipt_prefix_answers = prefix_answers;
    receipt_first_unanswered = first_unanswered;
    receipt_stdout_bytes = String.length stdout;
    receipt_stdout_digest = sha256 stdout;
    receipt_stderr_bytes = String.length stderr;
    receipt_stderr_digest = sha256 stderr;
    receipt_reaped = reaped; receipt_verdict = verdict }

let run_z3_batches batches =
  let started_ns = Mtime_clock.elapsed_ns () in
  let deadline_ns = Int64.add started_ns 45_000_000_000L in
  if not (batch_manifest_complete batches) then
    { run_verdict = Unavailable "batch manifest is missing, duplicated, or reordered";
      run_receipts = [];
      run_elapsed_ns = Int64.sub (Mtime_clock.elapsed_ns ()) started_ns }
  else
    let rec run receipts = function
      | [] ->
          let receipts = List.rev receipts in
          let answers =
            List.fold_left (fun total item -> total + item.receipt_answers) 0 receipts
          in
          let verdict =
            if answers = List.length obligations then Proved
            else Unavailable "batch answer union is incomplete"
          in
          { run_verdict = verdict; run_receipts = receipts;
            run_elapsed_ns = Int64.sub (Mtime_clock.elapsed_ns ()) started_ns }
      | (batch : smt_batch) :: rest ->
          let receipt = run_batch ~deadline_ns batch in
          begin match receipt.receipt_verdict with
          | Proved -> run (receipt :: receipts) rest
          | Refuted detail ->
              { run_verdict = Refuted (batch.batch_id ^ ": " ^ detail);
                run_receipts = List.rev (receipt :: receipts);
                run_elapsed_ns =
                  Int64.sub (Mtime_clock.elapsed_ns ()) started_ns }
          | Unavailable detail ->
              { run_verdict = Unavailable (batch.batch_id ^ ": " ^ detail);
                run_receipts = List.rev (receipt :: receipts);
                run_elapsed_ns =
                  Int64.sub (Mtime_clock.elapsed_ns ()) started_ns }
          end
    in
    run [] batches

module For_test = struct
  type failure_case =
    | Timeout
    | Signal
    | Stopped
    | Nonzero_exit
    | Spawn_failure
    | Output_open_failure

  type observation = {
    verdict : verdict;
    pid : int option;
    reaped : bool;
    stopped_observed : bool;
  }

  let pid_is_reaped pid =
    match waitpid_retry Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ -> false
    | _, _ -> false
    | exception Unix.Unix_error (Unix.ECHILD, _, _) -> true
    | exception Unix.Unix_error _ -> false

  let reap_retries_eintr () =
    let calls = ref 0 in
    let injected _flags _pid =
      incr calls;
      if !calls = 1 then raise (Unix.Unix_error (Unix.EINTR, "waitpid", ""))
      else (37, Unix.WEXITED 0)
    in
    waitpid_retry injected [] 37 = (37, Unix.WEXITED 0) && !calls = 2

  let kill_retries_eintr () =
    let calls = ref 0 in
    let injected _pid _signal =
      incr calls;
      if !calls = 1 then raise (Unix.Unix_error (Unix.EINTR, "kill", ""))
      else ()
    in
    kill_noerr_with injected 37 Sys.sigkill && !calls = 2

  let stopped_child () =
    match Unix.fork () with
    | 0 ->
        Unix.kill (Unix.getpid ()) Sys.sigstop;
        ignore (Unix.select [] [] [] 10.0);
        Unix._exit 0
    | pid ->
        let now = Mtime_clock.elapsed_ns () in
        let stop_deadline = Int64.add now 500_000_000L in
        let rec await_stop () =
          match
            waitpid_retry Unix.waitpid [ Unix.WNOHANG; Unix.WUNTRACED ] pid
          with
          | 0, _ ->
              if Int64.compare (Mtime_clock.elapsed_ns ()) stop_deadline >= 0
              then false
              else begin
                ignore (Unix.select [] [] [] 0.01);
                await_stop ()
              end
          | _, Unix.WSTOPPED _ -> true
          | _, (Unix.WEXITED _ | Unix.WSIGNALED _) -> false
        in
        let stopped_observed = await_stop () in
        let process =
          terminate_and_reap pid
            ~cleanup_deadline_ns:(Int64.add now 1_500_000_000L)
            "stopped child remained live until explicit cleanup"
        in
        let detail =
          match process.status with
          | Error detail -> detail
          | Ok status -> status_unavailable ~program:"stopped-child" status
        in
        { verdict = Unavailable detail; pid = process.pid;
          reaped = process.reaped; stopped_observed }

  let exercise_failure failure_case =
    if failure_case = Stopped then stopped_child ()
    else
    let created = ref [] in
    let temporary prefix =
      let path = Filename.temp_file prefix ".txt" in
      created := path :: !created;
      path
    in
    match
      let stdout_path =
        match failure_case with
        | Output_open_failure -> Filename.get_temp_dir_name ()
        | Timeout | Signal | Nonzero_exit | Spawn_failure | Stopped ->
            temporary "hermes-solver-test-out-"
      in
      let stderr_path = temporary "hermes-solver-test-err-" in
      let program, argv, deadline_ns, signal_immediately =
        match failure_case with
        | Spawn_failure ->
            ( "/definitely/missing/hermes-z3-process",
              [| "/definitely/missing/hermes-z3-process" |],
              Int64.add (Mtime_clock.elapsed_ns ()) 1_000_000_000L,
              false )
        | Output_open_failure ->
            ( "/usr/bin/sleep", [| "sleep"; "10" |],
              Int64.add (Mtime_clock.elapsed_ns ()) 1_000_000_000L,
              false )
        | Nonzero_exit ->
            ( "/usr/bin/false", [| "false" |],
              Int64.add (Mtime_clock.elapsed_ns ()) 1_000_000_000L,
              false )
        | Timeout ->
            ( "/usr/bin/sleep", [| "sleep"; "10" |],
              Int64.add (Mtime_clock.elapsed_ns ()) 50_000_000L,
              false )
        | Signal ->
            ( "/usr/bin/sleep", [| "sleep"; "10" |],
              Int64.add (Mtime_clock.elapsed_ns ()) 1_000_000_000L,
              true )
        | Stopped -> assert false
      in
      let cleanup_deadline_ns =
        Int64.add deadline_ns 1_000_000_000L
      in
      let process =
        run_process ~program ~argv ~stdout_path ~stderr_path ~deadline_ns
          ~cleanup_deadline_ns ~signal_immediately
      in
      let detail =
        match process.status with
        | Error detail -> detail
        | Ok status -> status_unavailable ~program status
      in
      { verdict = Unavailable detail; pid = process.pid; reaped = process.reaped;
        stopped_observed = false }
    with
    | observation ->
        List.iter remove_if_present !created;
        observation
    | exception exn ->
        List.iter remove_if_present !created;
        { verdict = Unavailable (Printexc.to_string exn); pid = None;
          reaped = true; stopped_observed = false }
end
