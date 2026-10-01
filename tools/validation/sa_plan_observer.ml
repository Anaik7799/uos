(* Private bounded READ-ONLY Sa-plan observer CLI.
   Reuses Live_plan.read verbatim: READONLY open, PRAGMA query_only=ON, BEGIN
   snapshot, 1001/10001 row limits, ROLLBACK. No schema creation and no SQL of
   my own. Authority is NONE; this tool observes.

   CORRECTION to an earlier header in this file, which claimed "no write of any
   kind". READONLY plus query_only excludes LOGICAL mutation: no row, table or
   index is changed, which the tests assert by comparing the full observation
   digest across reads. It does NOT exclude SQLite reader housekeeping. Reading
   a WAL-mode database creates -wal and -shm if absent and updates the -shm
   read marks, which is permitted and expected per
   https://www.sqlite.org/wal.html (read-only section: a read-only connection
   needs the -wal and -shm files to exist or to be creatable, and a reader
   transaction pins an end mark). Measured here: on a cold database -wal goes
   absent -> present at 0 bytes and -shm absent -> present at 32768 bytes; with
   an active WAL held open by a writer the main file and the WAL frame bytes are
   unchanged and only -shm content moves. The strict all-sidecars assertion is
   retained as a recorded failure rather than relaxed. *)

let max_stdout_bytes = 262144
let max_id_len = 200
let valid_states = ["available"; "executing"; "completed"; "failed"; "blocked"]
let max_self_deadline_ms = 60000

exception Usage
exception Refuse of string

let usage_text =
  "usage: sa_plan_observer --db <absolute-path> --plan <plan_id> \
   [--task <task_id>] [--state <state>] [--deadline-ms <n>]"

(* Fixed vocabulary only. No path, no row content, no exception text escapes. *)
let refuse why = raise (Refuse why)

let ok_id s =
  let n = String.length s in
  n > 0 && n <= max_id_len
  && String.for_all (fun c ->
         (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
         || (c >= '0' && c <= '9') || c = '-' || c = '_' || c = '/' || c = '.') s

let rec parse args (db, plan, task, state, dl) =
  match args with
  | [] -> (db, plan, task, state, dl)
  | "--db" :: v :: r -> parse r (Some v, plan, task, state, dl)
  | "--plan" :: v :: r -> parse r (db, Some v, task, state, dl)
  | "--task" :: v :: r -> parse r (db, plan, Some v, state, dl)
  | "--state" :: v :: r -> parse r (db, plan, task, Some v, dl)
  | "--deadline-ms" :: v :: r -> parse r (db, plan, task, state, Some v)
  | _ -> raise Usage

let main () =
  let argv = Array.to_list Sys.argv in
  let args = match argv with _ :: r -> r | [] -> [] in
  if args = [] then raise Usage;
  let db, plan, task, state, dl = parse args (None, None, None, None, None) in
  (* SELF-LIMIT. The transport cannot signal an arbitrary OS child, so a pinned
     child must bound itself. Exit 124 matches the existing repository
     convention for a child-enforced timeout. *)
  (match dl with
   | None -> ()
   | Some v ->
       let n = try int_of_string v with _ -> refuse "invalid_deadline_ms" in
       if n <= 0 || n > max_self_deadline_ms then refuse "invalid_deadline_ms";
       Sys.set_signal Sys.sigalrm
         (Sys.Signal_handle (fun _ -> prerr_endline "refused: self_deadline_exceeded"; exit 124));
       ignore (Unix.setitimer Unix.ITIMER_REAL
                 { Unix.it_interval = 0.0; Unix.it_value = float_of_int n /. 1000.0 }));
  let db = match db with Some d -> d | None -> raise Usage in
  let plan = match plan with Some p -> p | None -> raise Usage in
  if String.length db = 0 || db.[0] <> '/' then
    refuse "database_path_must_be_absolute";
  if String.length db > 4096 then refuse "database_path_too_long";
  if not (ok_id plan) then refuse "invalid_plan_id";
  (match task with
   | Some t when not (ok_id t) -> refuse "invalid_task_id"
   | _ -> ());
  (match state with
   | Some s when not (List.mem s valid_states) -> refuse "invalid_state_filter"
   | _ -> ());
  let tasks =
    try Live_plan.read ~path:db ~plan with
    | Priority.Invalid m ->
        (* Live_plan messages are fixed strings and carry no private data. *)
        refuse ("sa_plan_refusal: " ^ m)
    | Sqlite3.Error _ -> refuse "database_unreadable"
    | Unix.Unix_error _ -> refuse "database_unreadable"
    | Sys_error _ -> refuse "database_unreadable"
  in
  (* Digest covers the FULL authoritative observation, before any filtering. *)
  let full_digest = Live_plan.digest tasks in
  let selected =
    tasks
    |> List.filter (fun (t : Live_plan.task) ->
           (match task with Some x -> t.Live_plan.id = x | None -> true)
           && match state with Some s -> t.Live_plan.state = s | None -> true)
  in
  let doc =
    `Assoc
      [ ("observer", `String "uos.sa_plan.observer.v1");
        ("authority", `String "NONE");
        ("runtime_admission", `String "NOT_GRANTED");
        ("note", `String "read-only observation; not an authorization grant");
        ("plan_id", `String plan);
        ("observed_tasks_total", `Int (List.length tasks));
        ("selected_count", `Int (List.length selected));
        ("full_observation_sha256", `String full_digest);
        ("tasks", `List (List.map Live_plan.to_json selected)) ]
  in
  let out = Yojson.Basic.to_string doc in
  if String.length out > max_stdout_bytes then
    refuse "observation_output_exceeds_bound";
  print_string out;
  print_newline ()

let () =
  try main () with
  | Usage ->
      prerr_endline usage_text;
      exit 2
  | Refuse why ->
      prerr_endline ("refused: " ^ why);
      exit 3
  | _ ->
      prerr_endline "refused: observation_failed";
      exit 4
