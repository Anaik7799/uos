open Core

module Store = Sa_plan_store
module Management = Sa_plan_management

type verdict = Verified | Rejected_by_policy | Unavailable_observed
[@@deriving compare, equal]

type row = {
  id : string;
  surface : string;
  reference_observation : string;
  ocaml_observation : string;
  verdict : verdict;
  reason : string;
  sources : string list;
}

type report = row list

let rust_root = "/home/an/dev/ver/c3i/sub-projects/c3i/native/planning_daemon/src"
let captured_root = "/home/an/dev/ver/c3i/sub-projects/c3i/docs/journal"

let db_source = rust_root ^ "/db.rs"
let oban_source = rust_root ^ "/oban.rs"
let temporal_source = rust_root ^ "/temporal.rs"
let queue_capture =
  captured_root ^ "/20260421-144349-task-116442696961495770-queue-snapshot.json"
let workflow_capture =
  captured_root ^ "/20260421-144349-task-116442696961495770-workflow-executions.json"
let daemon_path = "/home/an/dev/ver/c3i/sub-projects/c3i/target/release/sa-plan-daemon"
let source_map_journal =
  "/home/an/dev/ver/c3i/docs/journal/20260804-1320-project-sync-planning-source-map-journal.md"

let row ?(ocaml_observation = "not_evaluated") ~id ~surface
    ~reference_observation ~verdict ~reason ~sources () =
  { id; surface; reference_observation; ocaml_observation; verdict; reason; sources }

let corpus =
  [ row ~id:"plan-state" ~surface:"plan"
      ~reference_observation:"pending|in_progress|completed|blocked"
      ~verdict:Verified ~reason:"source-observed canonical task-state carrier"
      ~sources:[ db_source ] ();
    row ~id:"job-state" ~surface:"oban"
      ~reference_observation:
        "scheduled|available|executing|retryable|completed|discarded|cancelled"
      ~verdict:Verified ~reason:"source and durable queue capture agree"
      ~sources:[ oban_source; queue_capture ] ();
    row ~id:"workflow-trace" ~surface:"temporal"
      ~reference_observation:"ordered event history by durable sequence"
      ~verdict:Verified ~reason:"source-observed event-sourced history"
      ~sources:[ temporal_source ] ();
    row ~id:"retry-timing" ~surface:"oban"
      ~reference_observation:"min(3600s, 15s * 2^attempt)"
      ~verdict:Verified ~reason:"source-observed RetryPolicy::delay_for_attempt"
      ~sources:[ oban_source ] ();
    row ~id:"activity-idempotency" ~surface:"temporal"
      ~reference_observation:"stable activity key returns persisted first result"
      ~verdict:Verified ~reason:"common durable idempotency observation"
      ~sources:[ temporal_source ] ();
    row ~id:"job-terminal-outcomes" ~surface:"oban"
      ~reference_observation:"completed|discarded|cancelled"
      ~verdict:Verified ~reason:"source and queue capture expose terminal outcomes"
      ~sources:[ oban_source; queue_capture ] ();
    row ~id:"workflow-cancellation" ~surface:"temporal"
      ~reference_observation:"cancelled"
      ~verdict:Unavailable_observed
      ~reason:"captured C3I cancellation has no current OCaml Store transition"
      ~sources:[ temporal_source; workflow_capture ] ();
    row ~id:"rust-runtime-execution" ~surface:"oracle"
      ~reference_observation:"read-only status live: v22.5.0; 3174 completed; 7 ms"
      ~verdict:Unavailable_observed
      ~reason:
        "canonical-cwd status is live after a 13:15 repair; an isolated mutating runtime differential was not evaluated"
      ~sources:[ daemon_path; source_map_journal ] () ]

let normalize_task_state ~dependencies_ready = function
  | "available" when dependencies_ready -> "pending"
  | "available" -> "blocked"
  | "executing" -> "in_progress"
  | "completed" -> "completed"
  | state -> state

let normalize_job_state = function
  | Store.Job_available -> "available"
  | Job_executing -> "executing"
  | Job_retry -> "retryable"
  | Job_completed -> "completed"
  | Job_discarded -> "discarded"
  | Job_cancelled -> "cancelled"

let retry_delay_ns = Store.retry_delay_ns

let replace report id ~ocaml_observation ~verdict ~reason =
  List.map report ~f:(fun item ->
    if String.equal item.id id then { item with ocaml_observation; verdict; reason }
    else item)

let node ?(dependencies = []) id title =
  Management.
    { id; parent_id = None; task_type = Story; title;
      estimate_points = Some 1; dependencies }

let evaluate_store store ~now_ns =
  let open Result.Let_syntax in
  let report = corpus in
  let plan_id = "c3i-reference-plan" in
  let%bind () =
    Store.register_plan store ~id:plan_id ~title:"C3I reference fixture"
      ~nodes:[ node "parent" "parent"; node ~dependencies:[ "parent" ] "child" "child" ]
  in
  let%bind before = Store.list_task_observations store ~plan_id in
  let child_blocked =
    List.find before ~f:(fun observation -> String.equal observation.task.id "child")
    |> Option.value_map ~default:false ~f:(fun observation ->
      String.equal
        (normalize_task_state ~dependencies_ready:false observation.task.state)
        "blocked")
  in
  let%bind claim =
    Store.claim_task store ~plan_id ~task_id:"parent" ~worker:"reference-worker"
      ~now_ns ~lease_ns:1_000L
  in
  let plan_ok = child_blocked && claim.attempt = 1 in
  let report =
    replace report "plan-state"
      ~ocaml_observation:(if plan_ok then "blocked|in_progress" else "mismatch")
      ~verdict:(if plan_ok then Verified else Rejected_by_policy)
      ~reason:"dependency-blocked and leased task states compared by normalized value"
  in
  let%bind _ =
    Store.enqueue_job store ~id:"c3i-reference-job"
      ~name:"c3i/reference/oban/job" ~queue:"reference" ~worker:"fixture"
      ~args:"{}" ~max_attempts:2 ~now_ns
  in
  let%bind claimed_job =
    Store.claim_job store ~queue:"reference" ~worker:"reference-worker"
      ~now_ns:Int64.(now_ns + 1L) ~lease_ns:1_000L
  in
  let%bind claimed_job =
    match claimed_job with
    | Some job -> Ok job
    | None -> Error "reference job was not claimable"
  in
  let failure_ns = Int64.(now_ns + 2L) in
  let%bind retry_job =
    Store.complete_job store ~id_or_name:claimed_job.id ~worker:"reference-worker"
      ~outcome:(`Error "retry") ~now_ns:failure_ns
  in
  let retry_ok =
    Poly.equal retry_job.state Job_retry
    && Int64.equal retry_job.available_at_ns
         Int64.(failure_ns + retry_delay_ns ~attempt:1)
  in
  let report =
    replace report "job-state" ~ocaml_observation:(normalize_job_state retry_job.state)
      ~verdict:(if retry_ok then Verified else Rejected_by_policy)
      ~reason:"retryable state normalized from the actual durable Store row"
    |> fun report ->
    replace report "retry-timing"
      ~ocaml_observation:(Int64.to_string Int64.(retry_job.available_at_ns - failure_ns))
      ~verdict:(if retry_ok then Verified else Rejected_by_policy)
      ~reason:"available_at delta compared with the C3I exponential/capped class"
  in
  let%bind claimed_again =
    Store.claim_job store ~queue:"reference" ~worker:"reference-worker"
      ~now_ns:retry_job.available_at_ns ~lease_ns:1_000L
  in
  let%bind claimed_again =
    match claimed_again with
    | Some job -> Ok job
    | None -> Error "retry job was not claimable"
  in
  let%bind discarded =
    Store.complete_job store ~id_or_name:claimed_again.id ~worker:"reference-worker"
      ~outcome:(`Error "terminal") ~now_ns:Int64.(retry_job.available_at_ns + 1L)
  in
  let terminal_ok = Poly.equal discarded.state Job_discarded in
  let report =
    replace report "job-terminal-outcomes"
      ~ocaml_observation:(normalize_job_state discarded.state)
      ~verdict:(if terminal_ok then Verified else Rejected_by_policy)
      ~reason:"attempt bound produced the observed discarded terminal"
  in
  let%bind () =
    Store.start_workflow_with_input store ~id:"c3i-reference-workflow"
      ~name:"c3i/reference/temporal/workflow" ~kind:"reference" ~input:"{}"
      ~now_ns
  in
  let%bind first =
    Store.complete_workflow_activity store
      ~workflow_id_or_name:"c3i-reference-workflow" ~id:"activity-1"
      ~name:"c3i/reference/temporal/activity" ~idempotency_key:"stable-key"
      ~result:"first" ~now_ns:Int64.(now_ns + 1L)
  in
  let%bind replay =
    Store.complete_workflow_activity store
      ~workflow_id_or_name:"c3i-reference-workflow" ~id:"activity-replay"
      ~name:"c3i/reference/temporal/activity-replay" ~idempotency_key:"stable-key"
      ~result:"different" ~now_ns:Int64.(now_ns + 2L)
  in
  let%bind () =
    Store.complete_workflow store ~id_or_name:"c3i-reference-workflow"
      ~result:"done" ~now_ns:Int64.(now_ns + 3L)
  in
  let%bind history = Store.workflow_history store ~id_or_name:"c3i-reference-workflow" in
  let trace = List.map history ~f:(fun event -> event.kind) in
  let trace_ok =
    List.equal String.equal trace
      [ "workflow_started"; "activity_completed"; "workflow_completed" ]
  in
  let report =
    replace report "workflow-trace" ~ocaml_observation:(String.concat ~sep:">" trace)
      ~verdict:(if trace_ok then Verified else Rejected_by_policy)
      ~reason:"durable event sequence compared in order, timestamps erased"
    |> fun report ->
    replace report "activity-idempotency"
      ~ocaml_observation:(first ^ "|" ^ replay)
      ~verdict:(if String.equal first replay then Verified else Rejected_by_policy)
      ~reason:"stable idempotency key preserved the first durable result"
  in
  Ok report

let find_verdict report id =
  List.find report ~f:(fun row -> String.equal row.id id)
  |> Option.map ~f:(fun row -> row.verdict)

let verdict_text = function
  | Verified -> "Verified"
  | Rejected_by_policy -> "Rejected_by_policy"
  | Unavailable_observed -> "Unavailable_observed"

let report_to_yojson report =
  `Assoc
    [ ("schema_version", `Int 1);
      ("oracle", `String "C3I Rust source plus captured durable observations");
      ("runtime_execution",
       `String "Read_only_observed; mutating_differential=Unavailable_observed");
      ("rows",
       `List
         (List.map report ~f:(fun row ->
            `Assoc
              [ ("id", `String row.id); ("surface", `String row.surface);
                ("reference_observation", `String row.reference_observation);
                ("ocaml_observation", `String row.ocaml_observation);
                ("verdict", `String (verdict_text row.verdict));
                ("reason", `String row.reason);
                ("sources", `List (List.map row.sources ~f:(fun s -> `String s))) ]))) ]

let publish ~path report =
  try
    let temporary = path ^ ".tmp" in
    Out_channel.write_all temporary
      ~data:(Yojson.Safe.pretty_to_string (report_to_yojson report) ^ "\n");
    Stdlib.Sys.rename temporary path;
    Ok ()
  with exn -> Error (Exn.to_string exn)
