module Materialize = Sa_plan_materialize
module Store = Sa_plan.Store

let require law condition = if condition then Printf.printf "ok %s\n%!" law else (prerr_endline ("FAIL " ^ law); exit 1)
let ok = function Ok value -> value | Error error -> failwith error
let () =
  let path = (Stdlib.Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "zigvm-materialize-test.sqlite3") in
  if Sys.file_exists path then Sys.remove path;
  let store = ok (Store.open_db path) in
  let mapping = Store.{ domain = Otp_parity; ooda_slice_id = "cp-03"; idempotency_key = "cp-03-key"; source_fingerprint = "source-a"; dependency_snapshot = "[]"; prompt_ledger_hash = "prompt"; safety_packet_hash = "safety"; formal_evidence_hash = "formal"; sa_plan_id = Some "cp03-plan"; sa_task_id = Some "cp03-task"; lifecycle_state = "selected"; created_at_ns = 1L } in
  let selection = Materialize.{ plan_id = "cp03-plan"; plan_name = "zigvm/otp/cp03"; plan_title = "cp03"; task_id = "cp03-task"; task_title = "cp03 task"; name = "zigvm/otp/cp03/task"; mapping } in
  let first = ok (Materialize.materialize store selection) in
  require "LAW CP03-CREATES-HIERARCHICAL-RECEIPT" (String.equal first.task.name selection.name);
  let replay = ok (Materialize.materialize store selection) in
  require "LAW CP03-IDEMPOTENT-REPLAY" (String.equal first.mapping.id replay.mapping.id && String.equal first.task.id replay.task.id);
  require "LAW CP03-PROVENANCE-DRIFT-REJECTED" (Result.is_error (Materialize.materialize store { selection with mapping = { mapping with source_fingerprint = "drift" } }));
  Store.close store; Sys.remove path
