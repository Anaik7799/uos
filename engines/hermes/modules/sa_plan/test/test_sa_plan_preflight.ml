module Store = Sa_plan.Store
module Preflight = Sa_plan_preflight

let require law condition =
  if condition then Printf.printf "ok %s\n%!" law
  else (prerr_endline ("FAIL " ^ law); exit 1)

let ok = function Ok value -> value | Error error -> failwith error

let mapping_request =
  Store.
    { domain = Otp_parity;
      ooda_slice_id = "cp-04";
      idempotency_key = "cp-04-key";
      source_fingerprint = "source-a";
      dependency_snapshot = "dependencies-a";
      prompt_ledger_hash = "prompt-a";
      safety_packet_hash = "safety-a";
      formal_evidence_hash = "formal-a";
      sa_plan_id = Some "cp04-plan";
      sa_task_id = Some "cp04-task";
      lifecycle_state = "materialized";
      created_at_ns = 1L }

let packet (mapping : Store.bridge_mapping) =
  let plan_id = match mapping.sa_plan_id with Some id -> id | None -> failwith "test mapping plan id" in
  let task_id = match mapping.sa_task_id with Some id -> id | None -> failwith "test mapping task id" in
  Preflight.
    { mapping;
      identity =
        { domain = mapping.domain;
          ooda_slice_id = mapping.ooda_slice_id;
          sa_plan_id = plan_id;
          sa_task_id = task_id };
      lease = { owner = "worker-a"; lease_id = "lease-a"; fencing_token = 7L; expires_at_ns = 10_000L };
      safety =
        { packet_hash = "safety-a";
          stpa_analysis_hash = "stpa-a";
          fmea_analysis_hash = "fmea-a";
          uca_guard_id = "uca-a" };
      evidence =
        { prompt_ledger_hash = "prompt-a";
          formal_evidence_hash = "formal-a";
          baseline_gate_stamp = "gate-a";
          gate_run_id = "run-a" };
      revision =
        { source_fingerprint = "source-a";
          dependency_snapshot = "dependencies-a";
          commit_sha = "0123456789abcdef" };
      packet_hash = "packet-a";
      recorded_at_ns = 2L }

let () =
  let path = (Stdlib.Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "zigvm-preflight-test.sqlite3") in
  if Sys.file_exists path then Sys.remove path;
  let store = ok (Store.open_db path) in
  ok (Store.create_plan store ~id:"cp04-plan" ~name:"control-plane/bridge" ~title:"cp04" ~now_ns:1L);
  ok
    (Store.create_task store ~plan_id:"cp04-plan" ~id:"cp04-task"
       ~name:"control-plane/bridge/04-preflight" ~title:"cp04"
       ~parent_id:None ~dependencies:[] ~priority:0 ~now_ns:1L);
  let mapping = ok (Store.ensure_bridge_mapping store mapping_request) in
  let complete = packet mapping in
  let task () =
    match ok (Store.find_task store ~plan_id:"cp04-plan" ~id_or_name:"cp04-task") with
    | Some value -> value
    | None -> failwith "materialized preflight task missing"
  in
  let reject_without_task_mutation law candidate =
    let before = task () in
    let rejected = Result.is_error (Preflight.admit store ~now_ns:9L candidate) in
    let after = task () in
    require law
      (rejected && String.equal before.state after.state
       && before.attempt = after.attempt
       && Option.equal String.equal before.worker after.worker)
  in
  reject_without_task_mutation "LAW CP04-REJECTS-MISSING-IDENTITY-NO-TASK-MUTATION"
    { complete with identity = { complete.identity with ooda_slice_id = "" } };
  reject_without_task_mutation "LAW CP04-REJECTS-INVALID-IDENTITY-NO-TASK-MUTATION"
    { complete with identity = { complete.identity with sa_task_id = "other-task" } };
  reject_without_task_mutation "LAW CP04-REJECTS-MISSING-LEASE-NO-TASK-MUTATION"
    { complete with lease = { complete.lease with owner = "" } };
  reject_without_task_mutation "LAW CP04-REJECTS-INVALID-FENCE-NO-TASK-MUTATION"
    { complete with lease = { complete.lease with fencing_token = 0L } };
  reject_without_task_mutation "LAW CP04-REJECTS-EXPIRED-LEASE-NO-TASK-MUTATION"
    { complete with lease = { complete.lease with expires_at_ns = 9L } };
  reject_without_task_mutation "LAW CP04-REJECTS-MISSING-STPA-PACKET-NO-TASK-MUTATION"
    { complete with safety = { complete.safety with stpa_analysis_hash = "" } };
  reject_without_task_mutation "LAW CP04-REJECTS-SAFETY-PROVENANCE-DRIFT-NO-TASK-MUTATION"
    { complete with safety = { complete.safety with packet_hash = "different-safety" } };
  reject_without_task_mutation "LAW CP04-REJECTS-MISSING-EVIDENCE-NO-TASK-MUTATION"
    { complete with evidence = { complete.evidence with baseline_gate_stamp = "" } };
  reject_without_task_mutation "LAW CP04-REJECTS-EVIDENCE-PROVENANCE-DRIFT-NO-TASK-MUTATION"
    { complete with evidence = { complete.evidence with formal_evidence_hash = "different-formal" } };
  reject_without_task_mutation "LAW CP04-REJECTS-MISSING-REVISION-NO-TASK-MUTATION"
    { complete with revision = { complete.revision with commit_sha = "" } };
  reject_without_task_mutation "LAW CP04-REJECTS-REVISION-PROVENANCE-DRIFT-NO-TASK-MUTATION"
    { complete with revision = { complete.revision with source_fingerprint = "different-source" } };
  let admitted = ok (Preflight.admit store ~now_ns:9L complete) in
  require "LAW CP04-ADMITS-COMPLETE-BOUND-PACKET"
    (String.equal admitted.decision "admitted" && String.equal admitted.mapping_id mapping.id);
  Store.close store;
  Sys.remove path
