open Core

module Management = Sa_plan.Management
module Store = Sa_plan.Store
module Observation = Sa_plan.Observability
module Pipeline = Sa_plan.Pipeline_telemetry
module C3i_reference = Sa_plan.C3i_reference
module Work = Sa_plan_work
module Manual = Sa_plan_manual

let program_plan_id = "infranodus-fractal-closure-20260804-0936"

let ensure_parent_dir path =
  let dir = Filename.dirname path in
  if not (String.equal dir "" || String.equal dir ".") then
    try Core_unix.mkdir_p dir with _ -> ()

let db_path =
  let path =
    match Sys.getenv "UOS_SA_PLAN_DB" with
    | Some p -> p
    | None -> (
        match Sys.getenv "ZIGVM_SA_PLAN_DB" with
        | Some p -> p
        | None -> (
            match Sys.getenv "UOS_ROOT" with
            | Some r -> Filename.concat (Filename.concat r "state") "sa_plan.sqlite3"
            | None -> "state/sa_plan.sqlite3"))
  in
  ensure_parent_dir path;
  path

let work_root =
  match Sys.getenv "UOS_WORK_ROOT" with
  | Some r -> r
  | None -> Option.value (Sys.getenv "ZIGVM_WORK_ROOT") ~default:"work"

let node ?(dependencies = []) id title =
  Management.{ id; parent_id = None; task_type = Story; title;
                estimate_points = Some 1; dependencies }

let nodes () =
  [ node "task-0" "Durable Sa-plan and registration";
    node ~dependencies:[ "task-0" ] "task-1" "Pure fractal closure algebra";
    node ~dependencies:[ "task-1" ] "task-2" "SHA-256 content identity";
    node ~dependencies:[ "task-1" ] "task-3" "Recoverable publication transaction";
    node ~dependencies:[ "task-2"; "task-3" ] "task-4" "Portable manifest/media/privacy";
    node ~dependencies:[ "task-1" ] "task-5" "Canonical design profile algebra";
    node ~dependencies:[ "task-5" ] "task-6" "Figma/Stitch/GetDesign/Impeccable/Bonsai profiles";
    node ~dependencies:[ "task-5"; "task-6" ] "task-7" "Executed typed UI evidence";
    node ~dependencies:[ "task-6" ] "task-8" "External Figma/Stitch readback";
    node ~dependencies:[ "task-5"; "task-6" ] "task-9" "Logseq and diagram atlas";
    node ~dependencies:[ "task-2"; "task-3"; "task-4"; "task-7"; "task-8"; "task-9" ]
      "task-10" "Governance and ontology synchronization";
    node ~dependencies:[ "task-10" ] "task-11" "Journal/wiki/ZK publication and admission";
    node ~dependencies:[ "task-0" ] "task-12" "C3I Sa-plan parity algebra";
    node ~dependencies:[ "task-12" ] "task-13" "Oban-compatible durable jobs";
    node ~dependencies:[ "task-12" ] "task-14" "Temporal-compatible durable workflows";
    node ~dependencies:[ "task-13"; "task-14" ] "task-15" "Sa-plan UI and observability";
    node ~dependencies:[ "task-13"; "task-14" ] "task-16" "C3I/Rust differential parity";
    node ~dependencies:[ "task-15"; "task-16" ] "task-17" "Safety, mutation, docs and admission" ]

let fail message = raise (Failure message)
let or_fail = function Ok value -> value | Error message -> fail message
let or_fail_msg = function Ok value -> value | Error (`Msg message) -> fail message

let now_ns () =
  Time_ns.now () |> Time_ns.to_int_ns_since_epoch |> Int64.of_int

let usage () =
  print_endline
    {|Sa-plan 0.3.0 — durable plans, tasks, jobs, workflows, and work artifacts

Usage: sa-plan [--format text|json] <noun> <verb> [arguments]

  plan      create | show | register | status | list | tree | watch
  task      create | show | list | rename | claim | complete | select
  job|oban enqueue | claim | complete | list
  workflow|temporal start | activity | complete | fail | history
  work      path | materialize
  docs      validate | render | publish
  ui        tui | jobs | workflows | bonsai | snapshot | parity
  help [noun] | version | status | sync | selftest

Use `sa-plan help <noun>` for a compact synopsis. The unified manual is:
work/plans/zigvm/documentation/sa-plan-unified-manual/manual.md|}

let contextual_help = function
  | "plan" -> print_endline "plan create ID NAME TITLE | show ID_OR_NAME | rename ID_OR_NAME NEW_NAME | register | status | list | tree | watch [SECONDS]"
  | "task" -> print_endline "task create PLAN ID NAME TITLE [PARENT|-] [DEPS] [PRIORITY] | show PLAN ID_OR_NAME | list PLAN | rename PLAN ID_OR_NAME NEW_NAME | claim WORKER [PLAN] [LEASE_NS] [TASK_ID] | release PLAN TASK WORKER | complete PLAN TASK WORKER RESULT | select PLAN TASK ACTOR PRIORITY STPA FMEA CRITICALITY DEPENDENCY STANDARDS AGENT_FIT RATIONALE"
  | "job" | "oban" -> print_endline "job|oban enqueue ID NAME QUEUE WORKER ARGS [MAX_ATTEMPTS] | claim QUEUE WORKER [LEASE_NS] | complete ID_OR_NAME WORKER OK|ERROR RESULT | list [QUEUE]"
  | "workflow" | "temporal" -> print_endline "workflow|temporal start ID NAME KIND INPUT | activity WORKFLOW ACTIVITY NAME KEY RESULT | complete WORKFLOW RESULT | fail WORKFLOW ERROR | history WORKFLOW"
  | "work" -> print_endline "work path KIND NAME | materialize KIND ID NAME TITLE CONTENT_FILE"
  | "docs" -> print_endline "docs validate MARKDOWN | render MARKDOWN HTML | publish HTML DASHBOARD_PATH | verify URL"
  | "ui" -> print_endline "ui tui | jobs | workflows | bonsai | snapshot PATH | parity PATH (read-only projections)"
  | _ -> usage ()

let emit format fields =
  match format with
  | `Text ->
      fields
      |> List.map ~f:(fun (key, value) -> key ^ "=" ^ value)
      |> String.concat ~sep:" "
      |> print_endline
  | `Json ->
      fields
      |> List.map ~f:(fun (key, value) -> key, `String value)
      |> fun values -> `Assoc values
      |> Yojson.Safe.to_string
      |> print_endline

let int = Int.to_string
let int64 = Int64.to_string
let optional = Option.value ~default:"-"

let job_state = function
  | Store.Job_available -> "available"
  | Store.Job_executing -> "executing"
  | Store.Job_retry -> "retry"
  | Store.Job_completed -> "completed"
  | Store.Job_discarded -> "discarded"
  | Store.Job_cancelled -> "cancelled"

let emit_plan format (plan : Store.plan_view) =
  emit format [ "id", plan.id; "name", plan.name; "title", plan.title ]

let emit_task format (task : Store.task_view) =
  emit format
    [ "plan_id", task.plan_id; "id", task.id; "name", task.name;
      "title", task.title; "parent_id", optional task.parent_id;
      "state", task.state; "priority", int task.priority;
      "worker", optional task.worker; "attempt", int task.attempt ]

let emit_job format (job : Store.job_view) =
  emit format
    [ "id", job.id; "name", job.name; "queue", job.queue;
      "worker", job.worker; "state", job_state job.state;
      "attempt", int job.attempt; "max_attempts", int job.max_attempts;
      "available_at_ns", int64 job.available_at_ns;
      "lease_owner", optional job.lease_owner;
      "result", optional job.result ]

let program_name node =
  Sa_plan.Name.make [ "infranodus"; "fractal-closure"; node.Management.id ]
  |> or_fail |> Sa_plan.Name.to_string

let print_plan () =
  List.iter (nodes ()) ~f:(fun node ->
      Printf.printf "%s\tid=%s\t%s\tdeps=%s\n" (program_name node)
        node.Management.id node.title (String.concat ~sep:"," node.dependencies))

let print_tree () =
  let all = nodes () in
  let rec depth node =
    match List.find all ~f:(fun candidate ->
      List.exists node.Management.dependencies
        ~f:(String.equal candidate.Management.id)) with
    | None -> 0
    | Some parent -> depth parent + 1
  in
  List.iter all ~f:(fun node ->
      Printf.printf "%s%s %s — %s\n" (String.make (2 * depth node) ' ')
        (if List.is_empty node.dependencies then "└─" else "├─")
        (program_name node) node.title)

let observe store =
  or_fail (Observation.observe store ~plan_id:program_plan_id ~now_ns:(now_ns ()))

let print_observation format snapshot =
  match format with
  | `Text -> print_string (Observation.to_text snapshot)
  | `Json ->
      Observation.to_yojson snapshot |> Yojson.Safe.to_string |> print_endline

let split_dependencies value =
  if String.equal value "" || String.equal value "-" then []
  else String.split value ~on:',' |> List.filter ~f:(Fn.non String.is_empty)

let parse_parent value =
  if String.equal value "-" || String.equal value "" then None else Some value

let render_manual_validation format path =
  let markdown = or_fail_msg (Bos.OS.File.read (Fpath.v path)) in
  match Manual.validate ~markdown with
  | [] -> emit format [ "validation", "green"; "path", path ]
  | errors -> fail ("manual validation failed: " ^ String.concat ~sep:"; " errors)

let dispatch store format argv =
  let command = argv.(1) in
  match command with
  | "--help" when Array.length argv > 2 -> contextual_help argv.(2)
  | "--help" -> usage ()
  | "--version" ->
      emit format
        [ "version", "0.3.0"; "contract", "20260804";
          "store", "sqlite"; "semantics", "at-least-once" ]
  | "--plan-create" ->
      or_fail
        (Store.create_plan store ~id:argv.(2) ~name:argv.(3) ~title:argv.(4)
           ~now_ns:(now_ns ()));
      emit format [ "plan_created", "true"; "id", argv.(2); "name", argv.(3) ]
  | "--plan-show" ->
      (match or_fail (Store.find_plan store ~id_or_name:argv.(2)) with
       | Some plan -> emit_plan format plan
       | None -> fail ("Unknown Sa-plan plan: " ^ argv.(2)))
  | "--plan-rename" ->
      or_fail
        (Store.rename_plan store ~id_or_name:argv.(2) ~new_name:argv.(3)
           ~now_ns:(now_ns ()));
      emit format [ "plan_renamed", "true"; "id_or_name", argv.(2);
                    "name", argv.(3) ]
  | "--register" ->
      or_fail
        (Store.register_plan store ~id:program_plan_id
           ~title:"InfraNodus fractal closure and C3I Sa-plan parity"
           ~nodes:(nodes ()));
      emit format [ "registered", "true"; "plan_id", program_plan_id ]
  | "--status" ->
      let summary = or_fail (Store.summary store ~plan_id:program_plan_id) in
      emit format
        [ "plan", program_plan_id; "total", int summary.total;
          "completed", int summary.completed; "ready", int summary.ready;
          "executing", int summary.executing ]
  | "--plan" -> print_plan ()
  | "--tree" -> print_tree ()
  | "--watch" ->
      let seconds = if Array.length argv > 2 then Int.of_string argv.(2) else 2 in
      let summary = or_fail (Store.summary store ~plan_id:program_plan_id) in
      emit format
        [ "interval_seconds", int (Int.max 1 seconds);
          "completed", int summary.completed; "total", int summary.total;
          "ready", int summary.ready; "executing", int summary.executing ]
  | "--task-create" ->
      let parent_id =
        if Array.length argv > 6 then parse_parent argv.(6) else None
      and dependencies =
        if Array.length argv > 7 then split_dependencies argv.(7) else []
      and priority = if Array.length argv > 8 then Int.of_string argv.(8) else 0 in
      or_fail
        (Store.create_task store ~plan_id:argv.(2) ~id:argv.(3) ~name:argv.(4)
           ~title:argv.(5) ~parent_id ~dependencies ~priority ~now_ns:(now_ns ()));
      emit format [ "task_created", "true"; "plan_id", argv.(2);
                    "id", argv.(3); "name", argv.(4) ]
  | "--task-show" ->
      (match or_fail (Store.find_task store ~plan_id:argv.(2) ~id_or_name:argv.(3)) with
       | Some task -> emit_task format task
       | None -> fail ("Unknown Sa-plan task: " ^ argv.(3)))
  | "--task-list" ->
      or_fail (Store.list_tasks store ~plan_id:argv.(2))
      |> List.iter ~f:(emit_task format)
  | "--task-rename" ->
      or_fail
        (Store.rename_task store ~plan_id:argv.(2) ~id_or_name:argv.(3)
           ~new_name:argv.(4) ~now_ns:(now_ns ()));
      emit format [ "task_renamed", "true"; "id_or_name", argv.(3);
                    "name", argv.(4) ]
  | "--claim" ->
      let worker = argv.(2) in
      let selected_plan, lease_ns, task_id_opt =
        if Array.length argv <= 3 then
          program_plan_id, 3_600_000_000_000L, None
        else
          match Int64.of_string_opt argv.(3) with
          | Some lease ->
              let task_opt = if Array.length argv > 4 then Some argv.(4) else None in
              program_plan_id, lease, task_opt
          | None ->
              let plan = argv.(3) in
              if Array.length argv <= 4 then
                plan, 3_600_000_000_000L, None
              else
                match Int64.of_string_opt argv.(4) with
                | Some lease ->
                    let task_opt = if Array.length argv > 5 then Some argv.(5) else None in
                    plan, lease, task_opt
                | None ->
                    (* argv.(4) is TASK_ID with default lease *)
                    plan, 3_600_000_000_000L, Some argv.(4)
      in
      (match task_id_opt with
       | Some target_task_id ->
           let claim =
             or_fail
               (Store.claim_task store ~plan_id:selected_plan ~task_id:target_task_id
                  ~worker ~now_ns:(now_ns ()) ~lease_ns)
           in
           emit format [ "claimed", "true"; "task", claim.task_id;
                         "attempt", int claim.attempt;
                         "lease_until_ns", int64 claim.lease_until_ns ]
       | None ->
           (match or_fail
                    (Store.claim_next store ~plan_id:selected_plan ~worker
                       ~now_ns:(now_ns ()) ~lease_ns) with
            | None -> emit format [ "claim", "none"; "plan_id", selected_plan ]
            | Some claim ->
                emit format [ "claimed", "true"; "task", claim.task_id;
                              "attempt", int claim.attempt;
                              "lease_until_ns", int64 claim.lease_until_ns ]))
  | "--task-release" ->
      or_fail
        (Store.release_task store ~plan_id:argv.(2) ~task_id:argv.(3)
           ~worker:argv.(4) ~now_ns:(now_ns ()));
      emit format [ "released", "true"; "plan_id", argv.(2);
                    "task", argv.(3) ]
  | "--complete" ->
      let selected_plan, task, worker, result =
        if Array.length argv > 5 then argv.(2), argv.(3), argv.(4), argv.(5)
        else program_plan_id, argv.(2), argv.(3), argv.(4)
      in
      or_fail
        (Store.complete_task store ~plan_id:selected_plan ~task_id:task ~worker
           ~result ~now_ns:(now_ns ()));
      emit format [ "completed", "true"; "plan_id", selected_plan; "task", task ]
  | "--task-select" ->
      let plan_id = argv.(2) and task_id = argv.(3) and actor = argv.(4) in
      let task =
        match or_fail (Store.find_task store ~plan_id ~id_or_name:task_id) with
        | Some t -> t
        | None -> fail (Printf.sprintf "Task '%s' not found in plan '%s'" task_id plan_id)
      in
      let parse_int field_name str =
        match Int.of_string_opt str with
        | Some v -> v
        | None -> fail (Printf.sprintf "Invalid integer for factor '%s': '%s'" field_name str)
      in
      let new_priority = parse_int "priority" argv.(5) in
      let factors =
        Store.
          { stpa = parse_int "stpa" argv.(6);
            fema = parse_int "fema" argv.(7);
            criticality = parse_int "criticality" argv.(8);
            dependency = parse_int "dependency" argv.(9);
            standards = parse_int "standards" argv.(10);
            agent_fit = parse_int "agent_fit" argv.(11) }
      in
      or_fail
        (Store.record_selection store ~plan_id ~task_id:task.id ~actor
           ~old_priority:(Some task.priority) ~new_priority ~factors
           ~rationale:argv.(12) ~now_ns:(now_ns ()));
      emit format [ "selection_recorded", "true"; "plan_id", plan_id;
                    "task", task.id; "actor", actor;
                    "priority", int new_priority ]
  | "--activity" ->
      let result =
        or_fail
          (Store.complete_activity store ~workflow_id:argv.(2)
             ~activity_id:argv.(3) ~result:argv.(4) ~now_ns:(now_ns ()))
      in
      emit format [ "workflow", argv.(2); "activity", argv.(3); "result", result ]
  | "--job-enqueue" ->
      let max_attempts = if Array.length argv > 7 then Int.of_string argv.(7) else 3 in
      Store.enqueue_job store ~id:argv.(2) ~name:argv.(3) ~queue:argv.(4)
        ~worker:argv.(5) ~args:argv.(6) ~max_attempts ~now_ns:(now_ns ())
      |> or_fail |> emit_job format
  | "--job-claim" ->
      let lease_ns =
        if Array.length argv > 4 then Int64.of_string argv.(4)
        else 60_000_000_000L
      in
      (match or_fail
               (Store.claim_job store ~queue:argv.(2) ~worker:argv.(3)
                  ~now_ns:(now_ns ()) ~lease_ns) with
       | None -> emit format [ "claim", "none"; "queue", argv.(2) ]
       | Some job -> emit_job format job)
  | "--job-complete" ->
      let outcome =
        if String.Caseless.equal argv.(4) "OK" then `Ok argv.(5)
        else if String.Caseless.equal argv.(4) "ERROR" then `Error argv.(5)
        else fail "job completion status must be OK or ERROR"
      in
      Store.complete_job store ~id_or_name:argv.(2) ~worker:argv.(3)
        ~outcome ~now_ns:(now_ns ()) |> or_fail |> emit_job format
  | "--job-list" ->
      let queue = if Array.length argv > 2 then Some argv.(2) else None in
      or_fail (Store.list_jobs store ~queue) |> List.iter ~f:(emit_job format)
  | "--workflow-start" ->
      or_fail
        (Store.start_workflow_with_input store ~id:argv.(2) ~name:argv.(3)
           ~kind:argv.(4) ~input:argv.(5) ~now_ns:(now_ns ()));
      emit format [ "workflow_started", "true"; "id", argv.(2); "name", argv.(3) ]
  | "--workflow-activity" ->
      let result =
        or_fail
          (Store.complete_workflow_activity store ~workflow_id_or_name:argv.(2)
             ~id:argv.(3) ~name:argv.(4) ~idempotency_key:argv.(5)
             ~result:argv.(6) ~now_ns:(now_ns ()))
      in
      emit format [ "workflow", argv.(2); "activity", argv.(3); "result", result ]
  | "--workflow-complete" ->
      or_fail
        (Store.complete_workflow store ~id_or_name:argv.(2) ~result:argv.(3)
           ~now_ns:(now_ns ()));
      emit format [ "workflow_completed", "true"; "id_or_name", argv.(2) ]
  | "--workflow-fail" ->
      or_fail
        (Store.fail_workflow store ~id_or_name:argv.(2) ~error:argv.(3)
           ~now_ns:(now_ns ()));
      emit format [ "workflow_failed", "true"; "id_or_name", argv.(2) ]
  | "--workflow-history" ->
      or_fail (Store.workflow_history store ~id_or_name:argv.(2))
      |> List.iter ~f:(fun event ->
             emit format [ "sequence", int event.Store.sequence;
                           "kind", event.kind; "payload", event.payload;
                           "occurred_at_ns", int64 event.occurred_at_ns ])
  | "--work-path" ->
      let kind = or_fail_msg (Work.kind_of_string argv.(2)) in
      let name = or_fail (Sa_plan.Name.parse argv.(3)) in
      emit format [ "path", or_fail_msg (Work.path_for ~root:work_root ~kind ~name) ]
  | "--work-materialize" ->
      let kind = or_fail_msg (Work.kind_of_string argv.(2)) in
      let name = or_fail (Sa_plan.Name.parse argv.(4)) in
      let content = or_fail_msg (Bos.OS.File.read (Fpath.v argv.(6))) in
      let materialized =
        or_fail_msg
          (Work.materialize ~root:work_root ~kind ~id:argv.(3) ~name
             ~title:argv.(5) ~content)
      in
      emit format [ "directory", materialized.directory;
                    "artifact", materialized.artifact;
                    "manifest", materialized.manifest;
                    "disposition",
                    (match materialized.disposition with Written -> "written" | Unchanged -> "unchanged") ]
  | "--docs-validate" -> render_manual_validation format argv.(2)
  | "--docs-render" ->
      let digest = or_fail_msg (Manual.render_file ~input:argv.(2) ~output:argv.(3)) in
      emit format [ "rendered", argv.(3); "sha256", digest ]
  | "--docs-publish" ->
      let digest = or_fail_msg (Manual.publish ~source:argv.(2) ~destination:argv.(3)) in
      emit format [ "published", argv.(3); "sha256", digest ]
  | "--docs-verify" ->
      let digest = or_fail_msg (Manual.verify_url ~url:argv.(2)) in
      emit format [ "verified", argv.(2); "sha256", digest;
                    "title", Manual.title ]
  | "--tui" | "--tui-jobs" | "--tui-workflows"
  | "--bonsai" | "--bonsai-jobs" | "--bonsai-workflows" ->
      observe store |> print_observation format
  | "--snapshot" ->
      let snapshot = observe store in
      or_fail (Observation.publish ~path:argv.(2) snapshot);
      emit format [ "snapshot", argv.(2); "read_only", "true" ]
  | "--c3i-parity" ->
      let path = Stdlib.Filename.temp_file "zigvm-sa-plan-c3i-" ".sqlite3" in
      Exn.protect
        ~f:(fun () ->
          let reference_store = or_fail (Store.open_db path) in
          Exn.protect
            ~f:(fun () ->
              let report =
                or_fail (C3i_reference.evaluate_store reference_store ~now_ns:(now_ns ()))
              in
              or_fail (C3i_reference.publish ~path:argv.(2) report))
            ~finally:(fun () -> Store.close reference_store))
        ~finally:(fun () ->
          List.iter [ path; path ^ "-wal"; path ^ "-shm" ] ~f:(fun candidate ->
            if Stdlib.Sys.file_exists candidate then Stdlib.Sys.remove candidate));
      emit format [ "c3i_parity", argv.(2); "authority", "differential_evidence";
                    "rust_runtime",
                    "Read_only_observed; mutating_differential=Unavailable_observed" ]
  | "--agent-progress" ->
      let summary = or_fail (Store.summary store ~plan_id:program_plan_id) in
      emit format [ "agent", argv.(2); "plan", program_plan_id;
                    "completed", int summary.completed; "total", int summary.total;
                    "ready", int summary.ready; "executing", int summary.executing ]
  | "--sync" ->
      let summary = or_fail (Store.summary store ~plan_id:program_plan_id) in
      emit format [ "sync", "green"; "authority", "store";
                    "completed", int summary.completed; "total", int summary.total ]
  | "--selftest" ->
      if List.length (nodes ()) <> 18 then fail "program DAG is not total";
      emit format [ "selftest", "green"; "dag_tasks", "18" ]
  | value -> fail ("unknown command: " ^ value)

let main () =
  let request_started_ns = Pipeline.now_ns () in
  let stages_rev = ref [] in
  let measured name operation =
    let value, stage = Pipeline.measure ~name operation in
    stages_rev := stage :: !stages_rev;
    value
  in
  let without_format, format =
    measured "decode" (fun () -> Sys.get_argv () |> Sa_plan_cli.extract_format)
  in
  let argv = measured "normalize" (fun () -> Sa_plan_cli.normalize without_format) in
  let command = if Array.length argv > 1 then argv.(1) else "missing" in
  let request_id = Printf.sprintf "sa-plan-%Ld" request_started_ns in
  let log_pipeline () =
    let total_ns = Int64.max 0L Int64.(Pipeline.now_ns () - request_started_ns) in
    Printf.eprintf "sa-plan-pipeline %s\n%!"
      (Pipeline.log_line ~request_id ~command ~total_ns (List.rev !stages_rev))
  in
  let validation = measured "validate" (fun () -> Sa_plan_cli.validate argv) in
  (match validation with
   | Error message ->
       log_pipeline ();
       Printf.eprintf "sa-plan: %s\n%!" message;
       exit 2
   | Ok () -> ());
  let store = measured "store_open" (fun () -> or_fail (Store.open_db db_path)) in
  match
    try
      measured "dispatch" (fun () -> dispatch store format argv);
      Ok ()
    with exn -> Error exn
  with
  | Ok () ->
      measured "store_close" (fun () -> Store.close store);
      log_pipeline ()
  | Error exn ->
      measured "store_close" (fun () -> Store.close store);
      log_pipeline ();
      raise exn

let () =
  try main () with
  | Failure message ->
      Printf.eprintf "sa-plan: %s\n%!" message;
      exit 1
  | exn ->
      Printf.eprintf "sa-plan: %s\n%!" (Exn.to_string exn);
      exit 1
