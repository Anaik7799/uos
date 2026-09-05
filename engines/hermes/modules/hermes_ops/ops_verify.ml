(* Verification as a swarm DAG — see ops_verify.mli for the laws. *)

type verdict = Passed | Failed | Skipped

type profile = Fast | Full

type monitoring_path = Control_path | Data_path

type capture_observation = {
  deadline_expired : bool;
  residual_group_terminated : bool;
  direct_child_reaped : bool;
  bytes : int;
}

type monitoring_metric = {
  id : string;
  channel : string;
  path : monitoring_path;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  value : int64;
}

type case_result = {
  name : string;
  verdict : verdict;
  exit_code : int;
  output : string;
  detail : string;
  duration_ms : float;
  capture : capture_observation option;
}

type report = {
  profile : profile;
  cases : case_result list;
  passed : int;
  failed : int;
  skipped : int;
  bytes_captured : int;
  wall_ms : float;
  monitoring : monitoring_metric list;
}

let string_of_verdict = function
  | Passed -> "PASS"
  | Failed -> "FAIL"
  | Skipped -> "SKIP"

let string_of_profile = function Fast -> "fast" | Full -> "full"

(* ------------------------------------------------------------ process

   TOTAL, and it captures the REAL exit status from the direct child with
   [waitpid]. Reading a pipe to EOF is not a process-completion contract:
   a descendant may inherit the descriptor and keep it open indefinitely.
   Every failure path here produces a value. *)
let capture_command ?timeout_seconds (cmd : string) =
  (* One nonblocking merged pipe, one private process group, and a parent-owned
     deadline.  A suite may fork a grandchild that inherits stdout; waiting for
     pipe EOF after the suite process exits would then hang forever.  We reap
     the direct child, drain currently available bytes, and terminate any
     residual group members before closing the descriptor. *)
  let read_fd, write_fd = Unix.pipe ~cloexec:true () in
  let group_executable = "/usr/bin/setsid" in
  match
    Unix.create_process group_executable
      [| group_executable; "/bin/sh"; "-c"; cmd |]
      Unix.stdin write_fd write_fd
  with
  | exception error ->
      Unix.close read_fd;
      Unix.close write_fd;
      let output = "could not start: " ^ Printexc.to_string error in
      (127, output,
       { deadline_expired = false; residual_group_terminated = false;
         direct_child_reaped = false; bytes = String.length output })
  | pid ->
      Unix.close write_fd;
      Unix.set_nonblock read_fd;
      let buffer = Buffer.create 4096 in
      let chunk = Bytes.create 65_536 in
      let rec drain () =
        match Unix.read read_fd chunk 0 (Bytes.length chunk) with
        | 0 -> ()
        | count -> Buffer.add_subbytes buffer chunk 0 count; drain ()
        | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> ()
        | exception Unix.Unix_error (Unix.EINTR, _, _) -> drain ()
        | exception _ -> ()
      in
      let kill_group signal =
        try Unix.kill (-pid) signal; true with Unix.Unix_error _ -> false
      in
      let status_code = function
        | Unix.WEXITED code -> code
        | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> 128 + signal
      in
      let deadline =
        Option.map (fun seconds -> Unix.gettimeofday () +. float seconds)
          timeout_seconds
      in
      let rec await () =
        drain ();
        match Unix.waitpid [ Unix.WNOHANG ] pid with
        | waited, status when waited = pid ->
            let residual_group_terminated = kill_group Sys.sigterm in
            drain ();
            (status_code status, false, residual_group_terminated, true)
        | _ ->
            begin match deadline with
            | Some limit when Unix.gettimeofday () >= limit ->
                let term_sent = kill_group Sys.sigterm in
                ignore (Unix.select [] [] [] 0.1);
                let kill_sent = kill_group Sys.sigkill in
                let _, status = Unix.waitpid [] pid in
                drain ();
                let code = status_code status in
                ((if code = 0 then 124 else code), true,
                 term_sent || kill_sent, true)
            | _ ->
                let pause =
                  match deadline with
                  | None -> 0.1
                  | Some limit -> max 0.0 (min 0.1 (limit -. Unix.gettimeofday ()))
                in
                ignore (Unix.select [ read_fd ] [] [] pause);
                await ()
            end
      in
      let code, deadline_expired, residual_group_terminated,
          direct_child_reaped =
        Fun.protect ~finally:(fun () -> Unix.close read_fd) await
      in
      let output = Buffer.contents buffer in
      (code, output,
       { deadline_expired; residual_group_terminated; direct_child_reaped;
         bytes = String.length output })

let run_capture ?timeout_seconds cmd =
  let code, output, _ = capture_command ?timeout_seconds cmd in
  (code, output)

(* A full verification profile includes external/live-facing suites.  A
   missing service must become a failed receipt, not an unbounded wait.  The
   timeout is deliberately a verifier containment boundary: it does not turn
   a timeout into success, and the resulting non-zero status is rendered in
   full like every other suite failure. *)
let suite_timeout_seconds = 120

let executable_file path =
  try
    not (Sys.is_directory path)
    && (Unix.access path [ Unix.X_OK ]; true)
  with Sys_error _ | Unix.Unix_error _ -> false

let resolve_executable executable =
  if not (Filename.is_relative executable) then
    if executable_file executable then Some executable else None
  else
    match Sys.getenv_opt "PATH" with
    | None -> None
    | Some path ->
        path |> String.split_on_char ':'
        |> List.find_map (fun directory ->
               let directory = if directory = "" then "." else directory in
               let candidate = Filename.concat directory executable in
               if executable_file candidate then
                 Some
                   (if Filename.is_relative candidate then
                      Filename.concat (Sys.getcwd ()) candidate
                    else candidate)
               else None)

let configured_z3 () =
  match Sys.getenv_opt "HERMES_Z3" with
  | Some executable when String.trim executable <> "" ->
      resolve_executable executable
  | Some _ | None -> resolve_executable "z3"

let suite_command ?z3 ~name ~exe () =
  let base =
    Printf.sprintf "timeout %ds %s" suite_timeout_seconds
      (Filename.quote exe)
  in
  if String.equal name "test_run_operator_authority" then
    let solver = Option.value z3 ~default:(Option.value (configured_z3 ()) ~default:"z3") in
    base ^ " --z3 " ^ Filename.quote solver
  else base

(* ---------------------------------------------------------- discovery

   DERIVED from the tree, never a hand-kept list: a list stops covering a
   suite the moment someone adds one, and nobody notices because the count
   still looks healthy. *)
let rec test_sources_under root =
  if not (Sys.file_exists root) || not (Sys.is_directory root) then []
  else
    Sys.readdir root |> Array.to_list
    |> List.concat_map (fun entry ->
           let path = Filename.concat root entry in
           if path = "modules/hermes_wiki/import" || entry = "_build" then []
           else
             match Sys.is_directory path with
             | true -> test_sources_under path
             | false
               when Filename.check_suffix entry ".ml"
                    && String.length entry > 5
                    && String.sub entry 0 5 = "test_" ->
                 [ path ]
             | false -> []
             | exception Sys_error _ -> [])

let roots_of_profile = function
  | Fast -> [ "modules/hermes_wiki/test"; "modules/hermes_ops" ]
  | Full ->
      if not (Sys.file_exists "modules") then []
      else
        Sys.readdir "modules" |> Array.to_list |> List.sort compare
        |> List.filter_map (fun entry ->
               let path = Filename.concat "modules" entry in
               match Sys.is_directory path with
               | true -> Some path
               | false -> None
               | exception Sys_error _ -> None)

let discover_suites profile =
  (* Fast preserves the sub-two-minute wiki+ops feedback contract. Full
     walks each direct production module root and admits every test source
     into the receipt. The imported zigvm tree is data-only and outside the
     Dune test surface, so it is explicitly excluded during traversal. *)
  let roots = roots_of_profile profile in
  let sources =
    List.concat_map test_sources_under roots
    |> List.map (fun src -> (Filename.remove_extension (Filename.basename src), src))
  in
  sources
  |> List.map (fun (name, src) ->
         (name, Filename.concat "_build/default" (Filename.remove_extension src ^ ".exe")))
  |> List.sort_uniq compare

(* --------------------------------------------------------- the summary

   A suite's own last "N passed, M failed" line IS its summary; reusing it
   keeps one source of truth for what a suite claims. When it prints no
   such line the exit code decides, and the detail says so rather than
   inventing a count. *)
let summary_line output =
  let lines = String.split_on_char '\n' output in
  let has_summary l =
    let n = String.length l in
    let rec go i = i + 7 <= n && (String.sub l i 7 = "passed," || go (i + 1)) in
    n > 0 && go 0
  in
  match List.filter has_summary lines with
  | [] -> None
  | ls -> Some (String.trim (List.nth ls (List.length ls - 1)))

let classify name exe =
  let started = Unix.gettimeofday () in
  if not (Sys.file_exists exe) then
    { name; verdict = Skipped; exit_code = 0; output = "";
      detail = "not built: " ^ exe; duration_ms = 0.0; capture = None }
  else
    let command = suite_command ~name ~exe () in
    let code, output, capture =
      capture_command ~timeout_seconds:(suite_timeout_seconds + 5) command
    in
    let duration_ms = (Unix.gettimeofday () -. started) *. 1000.0 in
    let detail =
      match summary_line output with
      | Some s -> s
      | None -> Printf.sprintf "no summary line; exit %d" code
    in
    { name; verdict = (if code = 0 then Passed else Failed); exit_code = code; output; detail;
      duration_ms; capture = Some capture }

(* The counts derive from the cases — see the mli. *)
let summarise ?(profile = Fast) ?(wall_ms = 0.0) cases =
  let count v = List.length (List.filter (fun c -> c.verdict = v) cases) in
  let coordinate level phase : Ops_capability.coordinate = { level; phase } in
  let metric id channel path coordinate rca_origin value =
    { id; channel; path; coordinate; rca_origin; value = Int64.of_int value }
  in
  let captures = List.filter_map (fun case -> case.capture) cases in
  let captured_bytes =
    List.fold_left (fun total case -> total + String.length case.output) 0 cases
  in
  let count_capture predicate = List.length (List.filter predicate captures) in
  let missing_summaries =
    List.length
      (List.filter
         (fun case -> String.starts_with ~prefix:"no summary line" case.detail)
         cases)
  in
  let max_duration_ms =
    List.fold_left (fun current case -> Float.max current case.duration_ms) 0.0 cases
    |> Float.ceil |> int_of_float
  in
  let monitoring =
    [ metric "ops.verify.control.suites.admitted" "control_suites_admitted"
        Control_path (coordinate Ops_capability.L2 Ops_capability.Decide)
        Ops_capability.Control (List.length cases);
      metric "ops.verify.control.suites.terminal" "control_suites_terminal"
        Control_path (coordinate Ops_capability.L6 Ops_capability.Act)
        Ops_capability.Control (List.length cases);
      metric "ops.verify.control.scheduler.parallelism_limit"
        "control_parallelism_limit" Control_path
        (coordinate Ops_capability.L3 Ops_capability.Decide) Ops_capability.Control
        (Sop_execution.default_max_parallelism ());
      metric "ops.verify.control.suites.timeout" "control_suites_timeout"
        Control_path (coordinate Ops_capability.L5 Ops_capability.Observe)
        Ops_capability.Implementation
        (count_capture (fun capture -> capture.deadline_expired));
      metric "ops.verify.control.process.spawn_failures"
        "control_process_spawn_failures" Control_path
        (coordinate Ops_capability.L4 Ops_capability.Observe) Ops_capability.Environment
        (count_capture (fun capture -> not capture.direct_child_reaped));
      metric "ops.verify.control.wall_ms" "control_wall_ms" Control_path
        (coordinate Ops_capability.L6 Ops_capability.Observe) Ops_capability.Control
        (Float.ceil wall_ms |> int_of_float);
      metric "ops.verify.data.bytes.captured" "data_bytes_captured" Data_path
        (coordinate Ops_capability.L5 Ops_capability.Observe) Ops_capability.Evidence
        captured_bytes;
      metric "ops.verify.data.pipe.residual_groups_terminated"
        "data_residual_groups_terminated" Data_path
        (coordinate Ops_capability.L5 Ops_capability.Act) Ops_capability.Implementation
        (count_capture (fun capture -> capture.residual_group_terminated));
      metric "ops.verify.data.children.reaped" "data_children_reaped" Data_path
        (coordinate Ops_capability.L5 Ops_capability.Observe) Ops_capability.Evidence
        (count_capture (fun capture -> capture.direct_child_reaped));
      metric "ops.verify.data.summary.missing" "data_summaries_missing" Data_path
        (coordinate Ops_capability.L6 Ops_capability.Orient) Ops_capability.Evidence
        missing_summaries;
      metric "ops.verify.data.case.max_duration_ms" "data_case_max_duration_ms"
        Data_path (coordinate Ops_capability.L5 Ops_capability.Observe)
        Ops_capability.Evidence max_duration_ms ]
  in
  { profile;
    cases;
    passed = count Passed;
    failed = count Failed;
    skipped = count Skipped;
    bytes_captured = captured_bytes;
    wall_ms; monitoring }

let monitoring_gaps report =
  let required =
    [ "ops.verify.control.suites.admitted";
      "ops.verify.control.suites.terminal";
      "ops.verify.control.scheduler.parallelism_limit";
      "ops.verify.control.suites.timeout";
      "ops.verify.control.process.spawn_failures";
      "ops.verify.control.wall_ms";
      "ops.verify.data.bytes.captured";
      "ops.verify.data.pipe.residual_groups_terminated";
      "ops.verify.data.children.reaped";
      "ops.verify.data.summary.missing";
      "ops.verify.data.case.max_duration_ms" ]
  in
  let observed = List.map (fun metric -> metric.id) report.monitoring in
  let gaps = ref [] in
  List.iter
    (fun id -> if not (List.mem id observed) then gaps := ("missing metric " ^ id) :: !gaps)
    required;
  if List.length observed <> List.length (List.sort_uniq String.compare observed) then
    gaps := "duplicate monitoring metric id" :: !gaps;
  let value id =
    List.find_opt (fun metric -> String.equal metric.id id) report.monitoring
    |> Option.map (fun metric -> metric.value)
  in
  if value "ops.verify.control.suites.admitted"
     <> value "ops.verify.control.suites.terminal"
  then gaps := "control path has non-terminal admitted suites" :: !gaps;
  if value "ops.verify.data.bytes.captured" <> Some (Int64.of_int report.bytes_captured)
  then gaps := "data-path byte metric differs from report bytes" :: !gaps;
  List.rev !gaps

(* ------------------------------------------------ the declarative intent

   One step per suite, each depending on the build step, so the build runs
   ONCE and the suites then run in parallel — Sop_execution spawns a Domain
   per ready step. The results are threaded out through a table rather than
   the step payloads, because a payload is a string and a case_result is
   not. *)
let run ?(profile = Fast) ?(build = true) () =
  let started = Unix.gettimeofday () in
  let suites = discover_suites profile in
  let results : (string, case_result) Hashtbl.t = Hashtbl.create 64 in
  let record r = Hashtbl.replace results r.name r in
  let build_step =
    { Sop_execution.step_id = "build";
      name = "dune build";
      assigned_agent = "agent_1";
      dependencies = [];
      action =
        (fun _ _ ->
          if not build then ("skipped", (0, 0))
          else
            let code, out, capture = capture_command "dune build --pkg=disabled 2>&1" in
            if code = 0 then ("ok", (0, 0))
            else begin
              record
                { name = "dune build"; verdict = Failed; exit_code = code; output = out;
                  detail = "the tree does not build"; duration_ms = 0.0;
                  capture = Some capture };
              ("failed", (0, 0))
            end) }
  in
  let suite_steps =
    List.map
      (fun (name, exe) ->
        { Sop_execution.step_id = "suite_" ^ name;
          name;
          assigned_agent = "agent_4";
          dependencies = [ "build" ];
          (* (0, 0): nothing here measures tokens, and a plausible number
             would be an invented measurement in a dashboard that reports
             it as fact (R16). *)
          action = (fun _ _ -> record (classify name exe); (name, (0, 0))) })
      suites
  in
  let _ =
    Sop_execution.execute_sop_workflow ~steps:(build_step :: suite_steps) ()
  in
  let cases =
    Hashtbl.fold (fun _ v acc -> v :: acc) results []
    |> List.sort (fun a b -> compare a.name b.name)
  in
  summarise ~profile ~wall_ms:((Unix.gettimeofday () -. started) *. 1000.0) cases

(* ------------------------------------------------------------- render

   On success: one line. On failure: every failing suite's own bytes, in
   full, FIRST — economy on the happy path is fine, but a quiet failure is
   the thing this repository exists to prevent. A skip is always named,
   never folded into the pass count (R2). *)
let render ?(require_complete = false) r =
  let b = Buffer.create 4096 in
  let monitoring_gaps = monitoring_gaps r in
  List.iter
    (fun gap -> Buffer.add_string b ("MONITORING GAP: " ^ gap ^ "\n"))
    monitoring_gaps;
  List.iter
    (fun c ->
      if c.verdict = Failed then
        Buffer.add_string b
          (Printf.sprintf "\n===== FAILED: %s (exit %d) =====\n%s\n" c.name c.exit_code c.output))
    r.cases;
  List.iter
    (fun c ->
      if c.verdict = Skipped then
        Buffer.add_string b (Printf.sprintf "SKIPPED (disclosed): %s — %s\n" c.name c.detail))
    r.cases;
  let metric id =
    r.monitoring
    |> List.find_opt (fun metric -> String.equal metric.id id)
    |> Option.map (fun metric -> Int64.to_string metric.value)
    |> Option.value ~default:"unavailable"
  in
  let missing_summary_names =
    r.cases
    |> List.filter_map (fun case ->
           if String.starts_with ~prefix:"no summary line" case.detail then
             Some case.name
           else None)
  in
  let missing_summary_receipt =
    match missing_summary_names with
    | [] -> metric "ops.verify.data.summary.missing"
    | names ->
        Printf.sprintf "%s[%s]"
          (metric "ops.verify.data.summary.missing") (String.concat "," names)
  in
  Buffer.add_string b
    (Printf.sprintf "verify: profile=%s · %d passed, %d failed, %d skipped · %d suites · %.1fs · %d bytes kept out of context · control=%s/%s p=%s timeout=%s spawn=%s · data=reaped:%s residual:%s missing:%s max:%sms\n"
       (string_of_profile r.profile) r.passed r.failed r.skipped (List.length r.cases)
       (r.wall_ms /. 1000.0) r.bytes_captured
       (metric "ops.verify.control.suites.terminal")
       (metric "ops.verify.control.suites.admitted")
       (metric "ops.verify.control.scheduler.parallelism_limit")
       (metric "ops.verify.control.suites.timeout")
       (metric "ops.verify.control.process.spawn_failures")
       (metric "ops.verify.data.children.reaped")
       (metric "ops.verify.data.pipe.residual_groups_terminated")
       missing_summary_receipt
       (metric "ops.verify.data.case.max_duration_ms"));
  (Buffer.contents b,
   if r.failed > 0 || monitoring_gaps <> []
      || (require_complete && r.skipped > 0)
   then 1 else 0)
