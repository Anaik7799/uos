open Core

module Management = Sa_plan.Management
module Observation = Sa_plan.Observability
module Pipeline = Sa_plan.Pipeline_telemetry
module Store = Sa_plan.Store

let require label condition =
  if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let or_fail = function
  | Ok value -> value
  | Error message -> failwith message

let node ?parent ?(dependencies = []) id title =
  Management.
    { id; parent_id = parent; task_type = Story; title;
      estimate_points = Some 1; dependencies }

let find_task snapshot id =
  List.find_exn snapshot.Observation.tasks ~f:(fun task ->
      String.equal task.Observation.task.Store.id id)

let remove_store_files path =
  List.iter [ path; path ^ "-wal"; path ^ "-shm" ] ~f:(fun candidate ->
      if Stdlib.Sys.file_exists candidate then Stdlib.Sys.remove candidate)

let () =
  let timing =
    Pipeline.server_timing ~total_ns:4_000_000L
      [ Pipeline.stage ~name:"store_open" ~duration_ns:1_000_000L;
        Pipeline.stage ~name:"dispatch" ~duration_ns:2_000_000L ]
  in
  require "LAW SA-PLAN-PIPELINE-STAGE-TOTALITY"
    (String.is_substring timing ~substring:"store_open;dur=1.000"
     && String.is_substring timing ~substring:"dispatch;dur=2.000"
     && String.is_substring timing ~substring:"total;dur=4.000");
  let path = (Stdlib.Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "zigvm-sa-plan-observability-test.sqlite3") in
  remove_store_files path;
  Exn.protect
    ~f:(fun () ->
      let store = or_fail (Store.open_db path) in
      or_fail
        (Store.register_plan store ~id:"observe" ~title:"Observe durable work"
           ~nodes:
             [ node "foundation" "Foundation";
               node ~dependencies:[ "foundation" ] "projection" "Projection" ]);
      ignore
        (or_fail
           (Store.claim_task store ~plan_id:"observe" ~task_id:"foundation"
              ~worker:"worker-a" ~now_ns:1_000L ~lease_ns:500L));
      ignore
        (or_fail
           (Store.enqueue_job store ~id:"job-1"
              ~name:"zigvm/sa-plan/observability/project" ~queue:"ui"
              ~worker:"projector" ~args:"{}" ~max_attempts:2 ~now_ns:1_000L));
      let job_claim =
        Option.value_exn (or_fail
           (Store.claim_job store ~queue:"ui" ~worker:"worker-a"
              ~now_ns:1_010L ~lease_ns:100L)) in
      ignore
        (or_fail
           (Store.complete_job store ~id_or_name:"job-1" ~worker:"worker-a"
              ~expected_attempt:job_claim.attempt ~outcome:(`Error "transient") ~now_ns:1_020L));
      or_fail
        (Store.start_workflow_with_input store ~id:"workflow-1"
           ~name:"zigvm/sa-plan/observability/workflow" ~kind:"projection"
           ~input:"observe" ~now_ns:1_000L);
      ignore
        (or_fail
           (Store.complete_workflow_activity store
              ~workflow_id_or_name:"workflow-1" ~id:"activity-1"
              ~name:"zigvm/sa-plan/observability/snapshot"
              ~idempotency_key:"snapshot-1" ~result:"green" ~now_ns:1_030L));
      let snapshot =
        or_fail (Observation.observe store ~plan_id:"observe" ~now_ns:1_040L)
      in
      let foundation = find_task snapshot "foundation"
      and projection = find_task snapshot "projection" in
      require "LAW SA-PLAN-OBSERVATION-LEASE-TRUTH"
        (Option.equal Int64.equal foundation.lease_until_ns (Some 1_500L)
         && Option.equal String.equal foundation.task.worker (Some "worker-a"));
      require "LAW SA-PLAN-OBSERVATION-DEPENDENCY-TRUTH"
        (List.equal String.equal projection.dependencies [ "foundation" ]
         && not projection.ready);
      require "LAW SA-PLAN-OBSERVATION-RETRY-TRUTH"
        (List.exists snapshot.jobs ~f:(fun job ->
             Poly.equal job.Store.state Store.Job_retry
             && job.attempt = 1 && job.max_attempts = 2));
      require "LAW SA-PLAN-OBSERVATION-WORKFLOW-HISTORY-TRUTH"
        (List.exists snapshot.workflows ~f:(fun workflow ->
             String.equal workflow.Store.id "workflow-1"
             && List.length workflow.events = 2));
      require "LAW SA-PLAN-OBSERVATION-BUDGET-METRIC-TRUTH"
        (snapshot.budgets.estimated_points = 2
         && snapshot.budgets.retry_capacity_remaining = 1
         && snapshot.metrics.leased_tasks = 1
         && snapshot.metrics.retrying_jobs = 1);
      let json = Observation.to_yojson snapshot |> Yojson.Safe.to_string
      and text = Observation.to_text snapshot in
      require "LAW SA-PLAN-OBSERVATION-READ-ONLY"
        (String.is_substring json ~substring:"\"read_only\":true"
         && not (String.is_substring json ~substring:"complete_task")
         && String.is_substring text ~substring:"read-only=true");
      Store.close store)
    ~finally:(fun () -> remove_store_files path)
