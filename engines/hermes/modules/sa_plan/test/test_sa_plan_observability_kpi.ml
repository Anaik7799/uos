(* Law suite for Sa_plan_observability_kpi (cp-12-observability).
   Prints "ok LAW <NAME>" per law; exits 1 on the first failure. *)

module Store = Sa_plan.Store
module Kpi = Sa_plan_observability_kpi

let require law condition =
  if condition then Printf.printf "ok %s\n%!" law
  else (prerr_endline ("FAIL " ^ law); exit 1)

let ok = function Ok value -> value | Error error -> failwith error

let contains ~haystack ~needle =
  let hl = String.length haystack and nl = String.length needle in
  let rec go i = i + nl <= hl && (String.sub haystack i nl = needle || go (i + 1)) in
  go 0

let () =
  let path = (Stdlib.Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "zigvm-sa-plan-kpi-test.sqlite3") in
  if Sys.file_exists path then Sys.remove path;
  let store = ok (Store.open_db path) in
  ok
    (Store.create_plan store ~id:"cp12-plan" ~name:"control-plane/kpi"
       ~title:"cp12" ~now_ns:1L);
  let task id name =
    ok
      (Store.create_task store ~plan_id:"cp12-plan" ~id ~name ~title:id
         ~parent_id:None ~dependencies:[] ~priority:0 ~now_ns:1L)
  in
  task "cp12-t1" "control-plane/kpi/01-completed";
  task "cp12-t2" "control-plane/kpi/02-available";
  task "cp12-t3" "control-plane/kpi/03-executing-live";
  task "cp12-t4" "control-plane/kpi/04-executing-expired";
  (* t1: completed. *)
  ignore
    (ok
       (Store.claim_task store ~plan_id:"cp12-plan" ~task_id:"cp12-t1"
          ~worker:"kpi-w" ~now_ns:10L ~lease_ns:100L));
  ok
    (Store.complete_task store ~plan_id:"cp12-plan" ~task_id:"cp12-t1"
       ~worker:"kpi-w" ~result:"green" ~now_ns:20L);
  (* t3: executing with a lease live at now=500 (until 1100). *)
  ignore
    (ok
       (Store.claim_task store ~plan_id:"cp12-plan" ~task_id:"cp12-t3"
          ~worker:"kpi-w" ~now_ns:100L ~lease_ns:1000L));
  (* t4: executing with a lease expired at now=500 (until 110). *)
  ignore
    (ok
       (Store.claim_task store ~plan_id:"cp12-plan" ~task_id:"cp12-t4"
          ~worker:"kpi-w" ~now_ns:100L ~lease_ns:10L));
  (* One pending job; one completed job (not pending). *)
  ignore
    (ok
       (Store.enqueue_job store ~id:"cp12-j1" ~name:"cp12/job-pending"
          ~queue:"cp12-kpi" ~worker:"noop" ~args:"{}" ~max_attempts:3
          ~now_ns:50L));
  ignore
    (ok
       (Store.enqueue_job store ~id:"cp12-j2" ~name:"cp12/job-done"
          ~queue:"cp12-kpi-done" ~worker:"noop" ~args:"{}" ~max_attempts:3
          ~now_ns:50L));
  ignore
    (ok
       (Store.claim_job store ~queue:"cp12-kpi-done" ~worker:"kpi-w"
          ~now_ns:60L ~lease_ns:100L));
  ignore
    (ok
       (Store.complete_job store ~id_or_name:"cp12-j2" ~worker:"kpi-w"
          ~outcome:(`Ok "done") ~now_ns:70L));
  (* One open workflow; one completed workflow (not open). *)
  ok (Store.start_workflow store ~id:"cp12-w1" ~name:"cp12/wf-open" ~now_ns:80L);
  ok (Store.start_workflow store ~id:"cp12-w2" ~name:"cp12/wf-done" ~now_ns:80L);
  ok
    (Store.complete_workflow store ~id_or_name:"cp12-w2" ~result:"done"
       ~now_ns:90L);

  let observe () =
    let tasks = ok (Store.list_tasks store ~plan_id:"cp12-plan") in
    let observations = ok (Store.list_task_observations store ~plan_id:"cp12-plan") in
    let jobs = ok (Store.list_jobs store ~queue:None) in
    let workflows = ok (Store.list_workflows store) in
    Marshal.to_string (tasks, observations, jobs, workflows) []
  in

  let before = observe () in
  let kpi = ok (Kpi.snapshot store ~plan_id:"cp12-plan" ~now_ns:500L) in
  let after = observe () in
  require "LAW CP12-READ-ONLY" (String.equal before after);

  require "LAW CP12-PARTITION-TOTALITY"
    (kpi.Kpi.total = 4
     && kpi.Kpi.total
        = kpi.Kpi.completed + kpi.Kpi.available + kpi.Kpi.executing
          + kpi.Kpi.blocked_or_other
     && kpi.Kpi.completed = 1 && kpi.Kpi.available = 1 && kpi.Kpi.executing = 2
     && kpi.Kpi.blocked_or_other = 0 && kpi.Kpi.lease_live = 1
     && kpi.Kpi.lease_expired = 1 && kpi.Kpi.jobs_pending = 1
     && kpi.Kpi.workflows_open = 1);

  let kpi_again = ok (Kpi.snapshot store ~plan_id:"cp12-plan" ~now_ns:500L) in
  require "LAW CP12-DETERMINISM" (kpi = kpi_again);

  require "LAW CP12-UNKNOWN-PLAN-FAILS-CLOSED"
    (match Kpi.snapshot store ~plan_id:"cp12-no-such-plan" ~now_ns:500L with
    | Error _ -> true
    | Ok _ -> false);

  (* t4's lease expired at 110: age(500)=390, age(900)=790; larger now_ns
     never decreases the age for the same durable state. *)
  let later = ok (Kpi.snapshot store ~plan_id:"cp12-plan" ~now_ns:900L) in
  require "LAW CP12-LEASE-AGE-MONOTONE"
    (match (kpi.Kpi.oldest_executing_age_ns, later.Kpi.oldest_executing_age_ns) with
    | Some early_age, Some late_age ->
        Int64.equal early_age 390L && Int64.equal late_age 790L
        && Int64.compare late_age early_age >= 0
    | _ -> false);

  let json = Kpi.to_json kpi in
  require "LAW CP12-JSON-CARRIES-ALL-FIELDS"
    (List.for_all
       (fun field -> contains ~haystack:json ~needle:("\"" ^ field ^ "\""))
       [ "plan_id"; "total"; "completed"; "available"; "executing";
         "blocked_or_other"; "lease_live"; "lease_expired"; "jobs_pending";
         "workflows_open"; "oldest_executing_age_ns" ]
     && contains ~haystack:json ~needle:"\"plan_id\":\"cp12-plan\""
     && contains
          ~haystack:
            (Kpi.to_json { kpi with Kpi.plan_id = "quote\"back\\slash\x01" })
          ~needle:"quote\\\"back\\\\slash\\u0001");

  Store.close store;
  Sys.remove path
