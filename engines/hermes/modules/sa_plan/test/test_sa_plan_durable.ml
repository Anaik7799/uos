open Core

module Management = Sa_plan.Management
module Store = Sa_plan.Store
module Control = Sa_plan.Control_plane

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

let with_store f =
  let path = (Stdlib.Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "zigvm-sa-plan-test.sqlite3") in
  Exn.protect
    ~f:(fun () -> f path)
    ~finally:(fun () ->
      if Stdlib.Sys.file_exists path then Stdlib.Sys.remove path)

let () =
  let v3_path = (Stdlib.Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "zigvm-sa-plan-v3-upgrade.sqlite3") in
  if Stdlib.Sys.file_exists v3_path then Stdlib.Sys.remove v3_path;
  let legacy = Sqlite3.db_open v3_path in
  require "LAW CP02-V3-FIXTURE-SETUP" (Poly.equal (Sqlite3.exec legacy "CREATE TABLE sa_plan_plan(id TEXT PRIMARY KEY,name TEXT,title TEXT NOT NULL,graph_fingerprint TEXT NOT NULL,created_at_ns INTEGER NOT NULL); CREATE TABLE sa_plan_task(plan_id TEXT NOT NULL,id TEXT NOT NULL,name TEXT,ordinal INTEGER NOT NULL,parent_id TEXT,task_type TEXT NOT NULL,title TEXT NOT NULL,estimate_points INTEGER,priority INTEGER NOT NULL,state TEXT NOT NULL,worker TEXT,lease_until_ns INTEGER,attempt INTEGER NOT NULL,result TEXT,completed_at_ns INTEGER,PRIMARY KEY(plan_id,id)); CREATE TABLE sa_plan_schema_meta(singleton INTEGER PRIMARY KEY,version INTEGER NOT NULL); INSERT INTO sa_plan_plan VALUES('v3-plan','legacy/plans/v3','v3','graph',0); INSERT INTO sa_plan_task VALUES('v3-plan','v3-task','legacy/tasks/v3',0,NULL,'story','v3 task',NULL,0,'available',NULL,NULL,0,NULL,NULL); INSERT INTO sa_plan_schema_meta VALUES(1,3)") Sqlite3.Rc.OK);
  require "LAW CP02-V3-FIXTURE-CLOSE" (Sqlite3.db_close legacy);
  let upgraded = or_fail (Store.open_db v3_path) in
  require "LAW C02-CANONICAL-V3-UPGRADE-TO-V6"
    (Store.schema_version upgraded = 6
     && Option.is_some (or_fail (Store.find_plan upgraded ~id_or_name:"v3-plan"))
     && Option.is_some (or_fail (Store.find_task upgraded ~plan_id:"v3-plan" ~id_or_name:"v3-task")));
  Store.close upgraded;
  let reopened_v3 = or_fail (Store.open_db v3_path) in
  require "LAW C02-V6-REOPEN-DOES-NOT-REGRESS" (Store.schema_version reopened_v3 = 6);
  Store.close reopened_v3;
  Stdlib.Sys.remove v3_path;
  let malformed_path = (Stdlib.Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "zigvm-sa-plan-malformed-v4.sqlite3") in
  if Stdlib.Sys.file_exists malformed_path then Stdlib.Sys.remove malformed_path;
  let malformed = Sqlite3.db_open malformed_path in
  require "LAW CP02-MALFORMED-V4-FIXTURE-SETUP"
    (Poly.equal (Sqlite3.exec malformed "CREATE TABLE sa_plan_schema_meta(singleton INTEGER PRIMARY KEY,version INTEGER NOT NULL); INSERT INTO sa_plan_schema_meta VALUES(1,4)") Sqlite3.Rc.OK);
  require "LAW CP02-MALFORMED-V4-FIXTURE-CLOSE" (Sqlite3.db_close malformed);
  require "LAW CP02-MALFORMED-V4-FAILS-CLOSED" (Result.is_error (Store.open_db malformed_path));
  Stdlib.Sys.remove malformed_path;
  with_store (fun path ->
      let nodes =
        [ node "t1" "carrier";
          node ~dependencies:[ "t1" ] "t2" "interpreter";
          node ~dependencies:[ "t2" ] "t3" "verification" ]
      in
      let store = or_fail (Store.open_db path) in
      or_fail
        (Store.register_plan store ~id:"closure" ~title:"Fractal closure"
           ~nodes);
      let initial = or_fail (Store.summary store ~plan_id:"closure") in
      require "LAW SA-PLAN-REGISTER-TOTALITY"
        (initial.total = 3 && initial.completed = 0 && initial.ready = 1);
      let first =
        or_fail
          (Store.claim_next store ~plan_id:"closure" ~worker:"worker-a"
             ~now_ns:1_000L ~lease_ns:100L)
      in
      require "LAW SA-PLAN-DEPENDENCY-ORDER"
        (Option.value_map first ~default:false ~f:(fun claim ->
             String.equal claim.task_id "t1" && claim.attempt = 1));
      let second_store = or_fail (Store.open_db path) in
      let duplicate =
        or_fail
          (Store.claim_next second_store ~plan_id:"closure" ~worker:"worker-b"
             ~now_ns:1_050L ~lease_ns:100L)
      in
      require "MUT-SAPLAN-2-COMPARE-AND-SET-CLAIM"
        (Option.is_none duplicate);
      Store.close second_store;
      Store.close store;
      let reopened = or_fail (Store.open_db path) in
      let after_restart = or_fail (Store.summary reopened ~plan_id:"closure") in
      require "LAW SA-PLAN-PROCESS-RESTART-DURABILITY"
        (after_restart.total = 3 && after_restart.executing = 1);
      or_fail
        (Store.complete_task reopened ~plan_id:"closure" ~task_id:"t1"
           ~worker:"worker-a" ~result:"green" ~now_ns:1_060L);
      let second =
        or_fail
          (Store.claim_next reopened ~plan_id:"closure" ~worker:"worker-b"
             ~now_ns:1_070L ~lease_ns:100L)
      in
      require "MUT-SAPLAN-1-DEPENDENCY-GUARD"
        (Option.value_map second ~default:false ~f:(fun claim ->
             String.equal claim.task_id "t2"));
      let activity_first =
        or_fail
          (Store.complete_activity reopened ~workflow_id:"wf-closure"
             ~activity_id:"task-t1" ~result:"first" ~now_ns:1_080L)
      in
      let activity_replay =
        or_fail
          (Store.complete_activity reopened ~workflow_id:"wf-closure"
             ~activity_id:"task-t1" ~result:"different" ~now_ns:1_090L)
      in
      require "LAW SA-PLAN-ACTIVITY-IDEMPOTENCE"
        (String.equal activity_first "first"
         && String.equal activity_replay "first");
      Store.close reopened);
  with_store (fun path ->
      let store = or_fail (Store.open_db path) in
      or_fail
        (Store.register_plan store ~id:"lease" ~title:"Lease recovery"
           ~nodes:[ node "a" "leased work" ]);
      ignore
        (or_fail
           (Store.claim_next store ~plan_id:"lease" ~worker:"worker-a"
              ~now_ns:2_000L ~lease_ns:100L));
      let reclaimed =
        or_fail
          (Store.claim_next store ~plan_id:"lease" ~worker:"worker-b"
             ~now_ns:2_101L ~lease_ns:100L)
      in
      require "LAW SA-PLAN-EXPIRED-LEASE-RECLAIM"
        (Option.value_map reclaimed ~default:false ~f:(fun claim ->
             String.equal claim.task_id "a" && claim.attempt = 2));
      let cyclic =
        Store.register_plan store ~id:"cycle" ~title:"Invalid"
          ~nodes:
            [ node ~dependencies:[ "b" ] "a" "a";
              node ~dependencies:[ "a" ] "b" "b" ]
      in
      require "LAW SA-PLAN-CYCLE-REJECTION" (Result.is_error cyclic);
      Store.close store)
  ;
  with_store (fun path ->
      let store = or_fail (Store.open_db path) in
      or_fail
        (Store.register_plan store ~id:"selection" ~title:"Selection evidence"
           ~nodes:[ node "risk" "Safety-critical work" ]);
      let factors =
        Store.{ stpa = 100; fema = 252; criticality = 90;
                dependency = 30; standards = 80; agent_fit = 70 }
      in
      or_fail
        (Store.record_selection store ~plan_id:"selection" ~task_id:"risk"
           ~actor:"codex" ~old_priority:None ~new_priority:95 ~factors
           ~rationale:"STPA hazard dominates" ~now_ns:3_000L);
      let evidence =
        or_fail
          (Store.latest_selection store ~plan_id:"selection" ~task_id:"risk")
      in
      require "LAW SA-PLAN-SELECTION-EVIDENCE-DURABLE"
        (Option.value_map evidence ~default:false ~f:(fun evidence ->
             evidence.new_priority = 95
             && evidence.factors.stpa = 100
             && String.equal evidence.actor "codex"));
      Store.close store;
      let reopened = or_fail (Store.open_db path) in
      let replayed =
        or_fail
          (Store.latest_selection reopened ~plan_id:"selection" ~task_id:"risk")
      in
      require "LAW SA-PLAN-SELECTION-RESTART-REPLAY"
        (Option.is_some replayed);
      Store.close reopened)
  ;
  with_store (fun path ->
      let store = or_fail (Store.open_db path) in
      or_fail
        (Store.create_plan store ~id:"manual-plan"
           ~name:"zigvm/documentation/manual" ~title:"Unified manual"
           ~now_ns:4_000L);
      let plan_by_id =
        or_fail (Store.find_plan store ~id_or_name:"manual-plan")
      and plan_by_name =
        or_fail
          (Store.find_plan store ~id_or_name:"zigvm/documentation/manual")
      in
      require "LAW SA-PLAN-ID-NAME-LOOKUP"
        (Option.value_map plan_by_id ~default:false ~f:(fun plan ->
             String.equal plan.id "manual-plan"
             && String.equal plan.name "zigvm/documentation/manual")
         && Option.value_map plan_by_name ~default:false ~f:(fun plan ->
              String.equal plan.id "manual-plan"
              && String.equal plan.name "zigvm/documentation/manual"));
      or_fail
        (Store.rename_plan store ~id_or_name:"manual-plan"
           ~new_name:"zigvm/documentation/unified-manual" ~now_ns:4_005L);
      require "LAW SA-PLAN-RENAME-ID-STABILITY"
        (Option.value_map
           (or_fail
              (Store.find_plan store
                 ~id_or_name:"zigvm/documentation/unified-manual"))
           ~default:false ~f:(fun plan -> String.equal plan.id "manual-plan"));
      or_fail
        (Store.create_task store ~plan_id:"manual-plan" ~id:"write"
           ~name:"zigvm/documentation/manual/write" ~title:"Write manual"
           ~parent_id:None ~dependencies:[] ~priority:80 ~now_ns:4_010L);
      or_fail
        (Store.create_task store ~plan_id:"manual-plan" ~id:"publish"
           ~name:"zigvm/documentation/manual/publish" ~title:"Publish manual"
           ~parent_id:(Some "write") ~dependencies:[ "write" ] ~priority:70
           ~now_ns:4_020L);
      let direct_claim =
        or_fail
          (Store.claim_task store ~plan_id:"manual-plan" ~task_id:"write"
             ~worker:"manual-worker" ~now_ns:4_025L ~lease_ns:1_000L)
      in
      require "LAW SA-PLAN-SPECIFIC-TASK-CLAIM"
        (String.equal direct_claim.task_id "write" && direct_claim.attempt = 1);
      or_fail
        (Store.release_task store ~plan_id:"manual-plan" ~task_id:"write"
           ~worker:"manual-worker" ~now_ns:4_026L);
      require "LAW SA-PLAN-OWNER-ONLY-RELEASE"
        (Result.is_error
           (Store.release_task store ~plan_id:"manual-plan" ~task_id:"write"
              ~worker:"wrong-worker" ~now_ns:4_027L));
      require "LAW SA-PLAN-NAME-REQUIRED"
        (Result.is_error
           (Store.create_task store ~plan_id:"manual-plan" ~id:"bad"
              ~name:"not-hierarchical" ~title:"Bad" ~parent_id:None
              ~dependencies:[] ~priority:0 ~now_ns:4_030L));
      require "LAW SA-PLAN-NAME-UNIQUE"
        (Result.is_error
           (Store.create_task store ~plan_id:"manual-plan" ~id:"duplicate"
              ~name:"zigvm/documentation/manual/write" ~title:"Duplicate"
              ~parent_id:None ~dependencies:[] ~priority:0 ~now_ns:4_040L));
      let before =
        or_fail
          (Store.find_task store ~plan_id:"manual-plan" ~id_or_name:"write")
      in
      or_fail
        (Store.rename_task store ~plan_id:"manual-plan" ~id_or_name:"write"
           ~new_name:"zigvm/documentation/manual/author" ~now_ns:4_050L);
      let after =
        or_fail
          (Store.find_task store ~plan_id:"manual-plan"
             ~id_or_name:"zigvm/documentation/manual/author")
      in
      require "LAW SA-PLAN-RENAME-ID-STABILITY"
        (Option.value_map before ~default:false ~f:(fun old_task ->
             Option.value_map after ~default:false ~f:(fun new_task ->
                 String.equal old_task.id new_task.id
                 && String.equal new_task.id "write")));
      require "LAW SA-PLAN-DEPENDENCY-TOTALITY"
        (Result.is_error
           (Store.create_task store ~plan_id:"manual-plan" ~id:"orphan"
              ~name:"zigvm/documentation/manual/orphan" ~title:"Orphan"
              ~parent_id:None ~dependencies:[ "missing" ] ~priority:0
              ~now_ns:4_060L));
      Store.close store;
      let reopened = or_fail (Store.open_db path) in
      let renamed =
        or_fail
          (Store.find_task reopened ~plan_id:"manual-plan" ~id_or_name:"write")
      in
      require "LAW SA-PLAN-NAMED-RESTART-REPLAY"
        (Option.value_map renamed ~default:false ~f:(fun task ->
             String.equal task.name "zigvm/documentation/manual/author"));
      Store.close reopened)
  ;
  with_store (fun path ->
      let store = or_fail (Store.open_db path) in
      let enqueued =
        or_fail
          (Store.enqueue_job store ~id:"job-1"
             ~name:"zigvm/documentation/manual/render" ~queue:"docs"
             ~worker:"renderer" ~args:"{}" ~max_attempts:2 ~now_ns:5_000L)
      in
      require "LAW SA-PLAN-JOB-NAME-REQUIRED"
        (String.equal enqueued.name "zigvm/documentation/manual/render");
      let claimed =
        or_fail
          (Store.claim_job store ~queue:"docs" ~worker:"worker-a"
             ~now_ns:5_010L ~lease_ns:100L)
      in
      require "LAW SA-PLAN-JOB-LEASE-CAS"
        (Option.value_map claimed ~default:false ~f:(fun job ->
             job.attempt = 1
             && Poly.equal job.state Store.Job_executing)
         && Option.is_none
              (or_fail
                 (Store.claim_job store ~queue:"docs" ~worker:"worker-b"
                    ~now_ns:5_020L ~lease_ns:100L)));
      let retry =
        or_fail
          (Store.complete_job store ~id_or_name:"job-1" ~worker:"worker-a"
             ~outcome:(`Error "transient") ~now_ns:5_030L)
      in
      require "LAW SA-PLAN-JOB-BOUNDED-RETRY"
        (Poly.equal retry.state Store.Job_retry && retry.attempt = 1);
      let reclaimed =
        or_fail
          (Store.claim_job store ~queue:"docs" ~worker:"worker-b"
             ~now_ns:retry.available_at_ns ~lease_ns:100L)
      in
      let reclaimed = Option.value_exn reclaimed in
      let discarded =
        or_fail
          (Store.complete_job store ~id_or_name:reclaimed.id
             ~worker:"worker-b" ~outcome:(`Error "terminal")
             ~now_ns:Int64.(retry.available_at_ns + 10L))
      in
      require "LAW SA-PLAN-JOB-ATTEMPT-BOUND"
        (discarded.attempt = 2
         && Poly.equal discarded.state Store.Job_discarded);
      or_fail
        (Store.start_workflow store ~id:"workflow-1"
           ~name:"zigvm/documentation/manual/publication" ~now_ns:7_000L);
      let first =
        or_fail
          (Store.complete_workflow_activity store
             ~workflow_id_or_name:"workflow-1" ~id:"render"
             ~name:"zigvm/documentation/manual/publication/render"
             ~idempotency_key:"render-v1" ~result:"digest-1"
             ~now_ns:7_010L)
      and replay =
        or_fail
          (Store.complete_workflow_activity store
             ~workflow_id_or_name:"workflow-1" ~id:"render"
             ~name:"zigvm/documentation/manual/publication/render"
             ~idempotency_key:"render-v1" ~result:"digest-2"
             ~now_ns:7_020L)
      in
      require "LAW SA-PLAN-WORKFLOW-ACTIVITY-IDEMPOTENCE"
        (String.equal first "digest-1" && String.equal replay "digest-1");
      or_fail
        (Store.complete_workflow store ~id_or_name:"workflow-1"
           ~result:"published" ~now_ns:7_030L);
      require "LAW SA-PLAN-WORKFLOW-TERMINAL-REJECTION"
        (Result.is_error
           (Store.complete_workflow_activity store
              ~workflow_id_or_name:"workflow-1" ~id:"verify"
              ~name:"zigvm/documentation/manual/publication/verify"
              ~idempotency_key:"verify-v1" ~result:"green"
              ~now_ns:7_040L));
      let history =
        or_fail (Store.workflow_history store ~id_or_name:"workflow-1")
      in
      require "LAW SA-PLAN-WORKFLOW-EVENT-ORDER"
        (List.equal String.equal
           (List.map history ~f:(fun event -> event.Store.kind))
           [ "workflow_started"; "activity_completed";
             "workflow_completed" ]);
      Store.close store;
      let reopened = or_fail (Store.open_db path) in
      let jobs = or_fail (Store.list_jobs reopened ~queue:(Some "docs")) in
      let history =
        or_fail (Store.workflow_history reopened ~id_or_name:"workflow-1")
      in
      require "LAW SA-PLAN-JOB-WORKFLOW-RESTART-REPLAY"
        (List.length jobs = 1 && List.length history = 3);
      Store.close reopened)
  ;
  with_store (fun path ->
      let store = or_fail (Store.open_db path) in
      let request =
        Store.
          { domain = Control.Otp_parity; ooda_slice_id = "cp-02-schema";
            idempotency_key = "materialize-cp-02"; source_fingerprint = "source-a";
            dependency_snapshot = "[]"; prompt_ledger_hash = "prompt-a";
            safety_packet_hash = "safety-a"; formal_evidence_hash = "formal-a";
            sa_plan_id = None; sa_task_id = None; lifecycle_state = "observed";
            created_at_ns = 8_000L }
      in
      require "LAW CP02-PAIRED-IDENTITY-REJECTS-ONE-SIDED"
        (Result.is_error
           (Store.ensure_bridge_mapping store
              { request with ooda_slice_id = "one-sided"; idempotency_key = "one-sided";
                             sa_plan_id = Some "missing" }));
      require "LAW CP02-PAIRED-IDENTITY-REJECTS-MISSING-TASK"
        (Result.is_error
           (Store.ensure_bridge_mapping store
              { request with ooda_slice_id = "missing-pair"; idempotency_key = "missing-pair";
                             sa_plan_id = Some "missing"; sa_task_id = Some "missing" }));
      or_fail (Store.create_plan store ~id:"bridge-plan" ~name:"zigvm/bridge" ~title:"Bridge" ~now_ns:7_900L);
      or_fail (Store.create_task store ~plan_id:"bridge-plan" ~id:"bridge-task" ~name:"zigvm/bridge/task" ~title:"Bridge task" ~parent_id:None ~dependencies:[] ~priority:0 ~now_ns:7_901L);
      require "LAW CP02-PAIRED-IDENTITY-ACCEPTS-REAL-TASK"
        (Result.is_ok
           (Store.ensure_bridge_mapping store
              { request with ooda_slice_id = "real-pair"; idempotency_key = "real-pair";
                             sa_plan_id = Some "bridge-plan"; sa_task_id = Some "bridge-task" }));
      let mapping = or_fail (Store.ensure_bridge_mapping store request) in
      let replay = or_fail (Store.ensure_bridge_mapping store request) in
      require "LAW CP02-MAPPING-UNIQUE-IDEMPOTENCY"
        (String.equal mapping.id replay.id && Int64.equal mapping.version 0L);
      require "LAW CP02-MAPPING-CONFLICT-REJECTED"
        (Result.is_error
           (Store.ensure_bridge_mapping store
              { request with idempotency_key = "other-key" }));
      require "LAW CP02-IMMUTABLE-MAPPING-DRIFT-REJECTED"
        (List.for_all
           [ { request with source_fingerprint = "source-drift" };
             { request with dependency_snapshot = "[drift]" };
             { request with prompt_ledger_hash = "prompt-drift" };
             { request with safety_packet_hash = "safety-drift" };
             { request with formal_evidence_hash = "formal-drift" } ]
           ~f:(fun drift -> Result.is_error (Store.ensure_bridge_mapping store drift)));
      require "LAW CP02-IDEMPOTENCY-KEY-REUSE-REJECTED"
        (Result.is_error
           (Store.ensure_bridge_mapping store
              { request with domain = Control.Fdc; ooda_slice_id = "fdc-cp-02" }));
      let receipt =
        or_fail
          (Store.record_bridge_command store ~mapping_id:mapping.id
             ~command_id:"command-1" ~request_hash:"request-a" ~result:"accepted"
             ~recorded_at_ns:8_001L)
      in
      let replay_receipt =
        or_fail
          (Store.record_bridge_command store ~mapping_id:mapping.id
             ~command_id:"command-1" ~request_hash:"request-a" ~result:"ignored"
             ~recorded_at_ns:8_002L)
      in
      require "LAW CP02-COMMAND-EFFECTIVELY-ONCE"
        (not receipt.replayed && replay_receipt.replayed
         && String.equal replay_receipt.result "accepted");
      require "LAW CP02-COMMAND-HASH-CONFLICT-REJECTED"
        (Result.is_error
           (Store.record_bridge_command store ~mapping_id:mapping.id
              ~command_id:"command-1" ~request_hash:"different" ~result:"bad"
              ~recorded_at_ns:8_003L));
      let other_mapping =
        or_fail (Store.ensure_bridge_mapping store
                   { request with domain = Control.Fdc; ooda_slice_id = "cp-02-global-command";
                                  idempotency_key = "other-mapping" })
      in
      require "LAW CP02-GLOBAL-COMMAND-ID-REUSE-REJECTED"
        (Result.is_error
           (Store.record_bridge_command store ~mapping_id:other_mapping.id
              ~command_id:"command-1" ~request_hash:"request-a" ~result:"bad"
              ~recorded_at_ns:8_003L));
      let event_one =
        or_fail
          (Store.append_bridge_event store ~mapping_id:mapping.id ~kind:"observed"
             ~payload:"{}" ~occurred_at_ns:8_004L)
      and event_two =
        or_fail
          (Store.append_bridge_event store ~mapping_id:mapping.id ~kind:"oriented"
             ~payload:"{}" ~occurred_at_ns:8_005L)
      in
      require "LAW CP02-MONOTONE-EVENT-SEQUENCE-VERSION"
        (Int64.equal event_one.sequence 1L && Int64.equal event_one.version 1L
         && Int64.equal event_two.sequence 2L && Int64.equal event_two.version 2L);
      let atomic =
        or_fail
          (Store.record_command_and_enqueue_outbox store ~mapping_id:mapping.id
             ~command_id:"command-2" ~request_hash:"request-b" ~result:"queued"
             ~event_kind:"preflighted" ~event_payload:"{}" ~endpoint:"https://receiver"
             ~outbox_id:"outbox-1"
             ~recorded_at_ns:8_006L)
      in
      require "LAW CP02-OUTBOX-ATOMIC-WITH-RECEIPT-EVENT"
        (not atomic.receipt.replayed && Int64.equal atomic.event.sequence 3L
         && Poly.equal atomic.outbox.state Store.Outbox_pending);
      let atomic_replay =
        or_fail
          (Store.record_command_and_enqueue_outbox store ~mapping_id:mapping.id
             ~command_id:"command-2" ~request_hash:"request-b" ~result:"changed"
             ~event_kind:"changed" ~event_payload:"changed" ~endpoint:"https://changed"
             ~outbox_id:"different-outbox" ~recorded_at_ns:8_006L)
      in
      require "LAW CP02-ATOMIC-COMMAND-REPLAY-RETURNS-ORIGINAL"
        (atomic_replay.receipt.replayed
         && Int64.equal atomic_replay.event.sequence atomic.event.sequence
         && String.equal atomic_replay.outbox.id atomic.outbox.id);
      let before_failure = event_two.version in
      require "LAW CP02-ROLLBACK-NO-PARTIAL-BRIDGE-STATE"
        (Result.is_error
           (Store.record_command_and_enqueue_outbox store ~mapping_id:mapping.id
              ~command_id:"command-bad" ~request_hash:"request-bad" ~result:"bad"
              ~event_kind:"bad" ~event_payload:"{}" ~endpoint:"https://receiver"
              ~outbox_id:"outbox-1"
              ~recorded_at_ns:8_007L)
         && Option.is_none
              (or_fail (Store.find_bridge_command store ~mapping_id:mapping.id
                          ~command_id:"command-bad"))
         && Int64.equal (or_fail (Store.append_bridge_event store ~mapping_id:mapping.id
                        ~kind:"post-rollback" ~payload:"{}" ~occurred_at_ns:8_007L)).version
            Int64.(before_failure + 2L));
      let ack_one = or_fail (Store.ack_bridge_outbox store ~consumer:"receiver-a" ~outbox_id:atomic.outbox.id ~acknowledged_at_ns:8_008L) in
      let ack_two = or_fail (Store.ack_bridge_outbox store ~consumer:"receiver-a" ~outbox_id:atomic.outbox.id ~acknowledged_at_ns:8_009L) in
      require "LAW CP02-CONSUMER-ACK-IDEMPOTENT" (not ack_one.replayed && ack_two.replayed
        && Poly.equal ack_two.outbox.state Store.Outbox_delivered);
      ignore
        (or_fail
           (Store.record_bridge_preflight store ~mapping_id:mapping.id
              ~packet_hash:"packet-a" ~decision:"admitted" ~recorded_at_ns:8_010L));
      ignore
        (or_fail
           (Store.record_bridge_reconciliation store ~mapping_id:mapping.id
              ~kind:"scan" ~outcome:"clean" ~recorded_at_ns:8_011L));
      Store.close store;
      let reopened = or_fail (Store.open_db path) in
      require "LAW CP05-V5-REOPEN-DURABILITY"
        (Option.is_some (or_fail (Store.find_bridge_command reopened ~mapping_id:mapping.id ~command_id:"command-2")));
      Store.close reopened)
