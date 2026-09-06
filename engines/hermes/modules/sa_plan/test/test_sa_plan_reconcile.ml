(* cp-11 law suite: recover and reconcile every interrupted close loop. *)

module Store = Sa_plan.Store
module Reconcile = Sa_plan_reconcile

let require law condition =
  if condition then Printf.printf "ok LAW %s\n%!" law
  else (
    prerr_endline ("FAIL LAW " ^ law);
    exit 1)

let ok = function Ok value -> value | Error error -> failwith error

(* Each namespace gets a unique ooda_slice_id AND idempotency_key: reusing the
   same slice id with a different key is rejected as provenance drift. *)
let mapping_request tag =
  Store.
    {
      domain = Sa_plan;
      ooda_slice_id = "cp-11-" ^ tag;
      idempotency_key = "cp-11-key-" ^ tag;
      source_fingerprint = "source-" ^ tag;
      dependency_snapshot = "[]";
      prompt_ledger_hash = "prompt-" ^ tag;
      safety_packet_hash = "safety-" ^ tag;
      formal_evidence_hash = "formal-" ^ tag;
      sa_plan_id = Some "cp11-plan";
      sa_task_id = Some ("cp11-task-" ^ tag);
      lifecycle_state = "preflighted";
      created_at_ns = 1L;
    }

let make_namespace store tag =
  ok
    (Store.create_task store ~plan_id:"cp11-plan" ~id:("cp11-task-" ^ tag)
       ~name:("control-plane/bridge/11-reconcile-" ^ tag)
       ~title:("cp11 " ^ tag) ~parent_id:None ~dependencies:[] ~priority:0
       ~now_ns:1L);
  ok (Store.ensure_bridge_mapping store (mapping_request tag))

let task_state store tag =
  match
    ok
      (Store.find_task store ~plan_id:"cp11-plan"
         ~id_or_name:("cp11-task-" ^ tag))
  with
  | Some (view : Store.task_view) -> view.state
  | None -> "missing"

let () =
  let path = (Stdlib.Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "zigvm-sa-plan-reconcile-test.sqlite3") in
  if Sys.file_exists path then Sys.remove path;
  let store = ok (Store.open_db path) in
  ok
    (Store.create_plan store ~id:"cp11-plan" ~name:"control-plane/bridge-11"
       ~title:"cp11" ~now_ns:1L);

  (* --- Namespace A: expired lease, no completion receipt. --- *)
  let a : Store.bridge_mapping = make_namespace store "a" in
  let first : Store.bridge_lease =
    ok
      (Store.claim_bridge_lease store ~mapping_id:a.id ~owner:"worker-a"
         ~lease_id:"lease-a" ~now_ns:100L ~lease_ns:50L)
  in
  (* Two reconciliations at the SAME now_ns, before any further mutation. *)
  let decision_a1 = ok (Reconcile.reconcile_task store ~mapping_id:a.id ~now_ns:200L) in
  let decision_a2 = ok (Reconcile.reconcile_task store ~mapping_id:a.id ~now_ns:200L) in
  let not_completed_after = not (String.equal (task_state store "a") "completed") in
  (* The task must remain claimable by a FRESH fenced claim with a HIGHER fence. *)
  let fresh : Store.bridge_lease =
    ok
      (Store.claim_bridge_lease store ~mapping_id:a.id ~owner:"worker-b"
         ~lease_id:"lease-b" ~now_ns:200L ~lease_ns:50L)
  in
  require "CP11-NO-INFERRED-COMPLETION"
    ((match fst decision_a1 with
     | Reconcile.Reclaim_expired_lease -> true
     | _ -> false)
    && not_completed_after
    && Int64.compare fresh.fencing_token first.fencing_token > 0);

  (* --- Namespace B: live (unexpired) lease. --- *)
  let b : Store.bridge_mapping = make_namespace store "b" in
  let live : Store.bridge_lease =
    ok
      (Store.claim_bridge_lease store ~mapping_id:b.id ~owner:"worker-a"
         ~lease_id:"lease-b-live" ~now_ns:100L ~lease_ns:50L)
  in
  let decision_b = ok (Reconcile.reconcile_task store ~mapping_id:b.id ~now_ns:120L) in
  let lease_after =
    match ok (Store.find_bridge_lease store ~mapping_id:b.id) with
    | Some (l : Store.bridge_lease) ->
        String.equal l.owner live.owner
        && String.equal l.lease_id live.lease_id
        && Int64.equal l.fencing_token live.fencing_token
        && Int64.equal l.expires_at_ns live.expires_at_ns
    | None -> false
  in
  require "CP11-LIVE-LEASE-NOOP"
    ((match fst decision_b with
     | Reconcile.No_action _ -> true
     | _ -> false)
    && lease_after
    && not (String.equal (task_state store "b") "completed"));

  (* --- Idempotence: same now_ns => same stable decision, no state regress. --- *)
  let decision_b2 = ok (Reconcile.reconcile_task store ~mapping_id:b.id ~now_ns:120L) in
  require "CP11-IDEMPOTENT-DECISION"
    (fst decision_a1 = fst decision_a2
    && fst decision_b = fst decision_b2
    && not (String.equal (task_state store "a") "completed")
    && not (String.equal (task_state store "b") "completed"));

  (* --- Namespace C: interrupted close-loop command (result "pending"). --- *)
  let c : Store.bridge_mapping = make_namespace store "c" in
  let recorded : Store.bridge_command_receipt =
    ok
      (Store.record_bridge_command store ~mapping_id:c.id
         ~command_id:Reconcile.close_loop_command_id ~request_hash:"hash-c"
         ~result:"pending" ~recorded_at_ns:10L)
  in
  let decision_c = ok (Reconcile.reconcile_task store ~mapping_id:c.id ~now_ns:100L) in
  let command_untouched =
    match
      ok
        (Store.find_bridge_command store ~mapping_id:c.id
           ~command_id:Reconcile.close_loop_command_id)
    with
    | Some (r : Store.bridge_command_receipt) ->
        String.equal r.result recorded.result
        && String.equal r.request_hash recorded.request_hash
    | None -> false
  in
  require "CP11-INTERRUPTED-COMMAND-FAILS-CLOSED"
    ((match fst decision_c with
     | Reconcile.Fail_interrupted_command -> true
     | _ -> false)
    && command_untouched
    && not (String.equal (task_state store "c") "completed"));

  (* --- Totality: every constructed state yields Ok; unknown id yields Error. --- *)
  let d : Store.bridge_mapping = make_namespace store "d" in
  let quiescent_ok =
    match Reconcile.reconcile_task store ~mapping_id:d.id ~now_ns:100L with
    | Ok (Reconcile.No_action _, _) -> true
    | _ -> false
  in
  let unknown_is_error =
    match
      Reconcile.reconcile_task store ~mapping_id:"no-such-mapping"
        ~now_ns:100L
    with
    | Error _ -> true
    | Ok _ -> false
  in
  require "CP11-DECISION-TOTALITY" (quiescent_ok && unknown_is_error);

  Store.close store;
  Sys.remove path
