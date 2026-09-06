open Core

module Store = Sa_plan.Store

let require law condition =
  if condition then Printf.printf "ok %s\n%!" law
  else (prerr_endline ("FAIL " ^ law); exit 1)

let ok = function Ok value -> value | Error error -> failwith error

let mapping_request =
  Store.
    { domain = Sa_plan;
      ooda_slice_id = "cp-05";
      idempotency_key = "cp-05-key";
      source_fingerprint = "source-a";
      dependency_snapshot = "[]";
      prompt_ledger_hash = "prompt-a";
      safety_packet_hash = "safety-a";
      formal_evidence_hash = "formal-a";
      sa_plan_id = Some "cp05-plan";
      sa_task_id = Some "cp05-task";
      lifecycle_state = "preflighted";
      created_at_ns = 1L }

let () =
  let path = (Stdlib.Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "zigvm-sa-plan-lease-test.sqlite3") in
  if Stdlib.Sys.file_exists path then Stdlib.Sys.remove path;
  let store = ok (Store.open_db path) in
  ok
    (Store.create_plan store ~id:"cp05-plan" ~name:"control-plane/bridge"
       ~title:"cp05" ~now_ns:1L);
  ok
    (Store.create_task store ~plan_id:"cp05-plan" ~id:"cp05-task"
       ~name:"control-plane/bridge/05-leases" ~title:"cp05" ~parent_id:None
       ~dependencies:[] ~priority:0 ~now_ns:1L);
  let mapping = ok (Store.ensure_bridge_mapping store mapping_request) in
  let first =
    ok
      (Store.claim_bridge_lease store ~mapping_id:mapping.id ~owner:"worker-a"
         ~lease_id:"lease-a" ~now_ns:100L ~lease_ns:50L)
  in
  require "LAW CP05-FIRST-CLAIM-ASSIGNS-FENCE-ONE"
    (Int64.equal first.fencing_token 1L && String.equal first.owner "worker-a"
     && Int64.equal first.expires_at_ns 150L);
  require "LAW CP05-LIVE-LEASE-REJECTS-SECOND-OWNER"
    (Result.is_error
       (Store.claim_bridge_lease store ~mapping_id:mapping.id ~owner:"worker-b"
          ~lease_id:"lease-b" ~now_ns:149L ~lease_ns:50L));
  let reclaimed =
    ok
      (Store.claim_bridge_lease store ~mapping_id:mapping.id ~owner:"worker-b"
         ~lease_id:"lease-b" ~now_ns:151L ~lease_ns:50L)
  in
  require "LAW CP05-EXPIRED-RECLAIM-ADVANCES-FENCE"
    (Int64.equal reclaimed.fencing_token 2L && String.equal reclaimed.owner "worker-b");
  require "LAW CP05-STALE-FENCE-CANNOT-TRANSITION"
    (Result.is_error
       (Store.complete_bridge_task store ~mapping_id:mapping.id ~owner:"worker-a"
          ~lease_id:"lease-a" ~fencing_token:first.fencing_token ~result:"stale"
          ~now_ns:160L));
  require "LAW CP05-WRONG-FENCE-CANNOT-TRANSITION"
    (Result.is_error
       (Store.complete_bridge_task store ~mapping_id:mapping.id ~owner:"worker-b"
          ~lease_id:"lease-b" ~fencing_token:first.fencing_token ~result:"wrong-fence"
          ~now_ns:160L));
  ok
    (Store.complete_bridge_task store ~mapping_id:mapping.id ~owner:"worker-b"
       ~lease_id:"lease-b" ~fencing_token:reclaimed.fencing_token ~result:"green"
       ~now_ns:160L);
  require "LAW CP05-CURRENT-FENCE-COMPLETES-TASK"
    (match ok (Store.find_task store ~plan_id:"cp05-plan" ~id_or_name:"cp05-task") with
     | Some task -> String.equal task.state "completed"
     | None -> false);
  Store.close store;
  let reopened = ok (Store.open_db path) in
  require "LAW CP05-RESTART-PRESERVES-FENCED-COMPLETION"
    (match ok (Store.find_task reopened ~plan_id:"cp05-plan" ~id_or_name:"cp05-task") with
     | Some task -> String.equal task.state "completed"
     | None -> false);
  require "LAW CP05-COMPLETED-TASK-CANNOT-BE-RECLAIMED"
    (Result.is_error
       (Store.claim_bridge_lease reopened ~mapping_id:mapping.id ~owner:"worker-c"
          ~lease_id:"lease-c" ~now_ns:1000L ~lease_ns:50L));
  Store.close reopened;
  Stdlib.Sys.remove path
