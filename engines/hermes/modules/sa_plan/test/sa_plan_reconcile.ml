(* cp-11: recover and reconcile every interrupted close loop
   (control-plane/bridge/11-reconcile).

   Semantic domain: reconciliation denotes a TOTAL function
     observed durable bridge state at now_ns
       (mapping ⊗ mapped task ⊗ current lease ⊗ close-loop command receipt)
     -> decision ∈ { Reclaim_expired_lease, Fail_interrupted_command,
                     No_action reason }
   The closure lattice is exactly these three constructors — no pending or
   unknown state exists. The decision is a pure function of observed durable
   truth (the store is read; reconciliation rows are appended as receipts),
   so reconciliation at a fixed now_ns is idempotent: re-running yields the
   same decision and never regresses lease, command, or task state.

   Oracle / final encoding: the oracle is the decision table below, read
   directly off the durable observations in priority order
     completed-task > live-lease > expired-lease > pending-command > quiet;
   this module IS that initial encoding — there is deliberately no separate
   optimized final encoding, the table is executed literally. The durable
   Sa_plan.Store (fenced leases, effectively-once command receipts) is the
   observation source; nothing is mocked.

   Fail-closed contract (the core law, CP11-NO-INFERRED-COMPLETION):
   reconciliation NEVER infers completion after loss. An expired lease with
   no completion receipt makes the task reclaimable (a fresh fenced claim
   observes a strictly higher fence); an interrupted close-loop command
   (result still "pending") is failed-closed, never re-executed. Every store
   error and every unknown mapping id is surfaced as [Error detail] — never
   an exception, never a fabricated decision. *)

module Store = Sa_plan.Store

type decision =
  | Reclaim_expired_lease
  | Fail_interrupted_command
  | No_action of string

let close_loop_command_id = "close-loop"

let ( let* ) result f =
  match result with Ok value -> f value | Error e -> Error e

(* The mapped Sa-plan task counts as carrying a completion receipt only when
   the durable task row itself is in state "completed". *)
let task_completed store (mapping : Store.bridge_mapping) =
  match (mapping.sa_plan_id, mapping.sa_task_id) with
  | Some plan_id, Some task_id -> (
      let* task = Store.find_task store ~plan_id ~id_or_name:task_id in
      match task with
      | Some (view : Store.task_view) ->
          Ok (String.equal view.state "completed")
      | None -> Ok false)
  | _ -> Ok false

let record_receipt store ~mapping_id ~kind ~outcome ~now_ns =
  Store.record_bridge_reconciliation store ~mapping_id ~kind ~outcome
    ~recorded_at_ns:now_ns

let reconcile_task store ~mapping_id ~now_ns =
  match
    let* mapping_opt = Store.find_bridge_mapping store ~id:mapping_id in
    match mapping_opt with
    | None ->
        Error (Printf.sprintf "reconcile: unknown mapping id %s" mapping_id)
    | Some mapping -> (
        let* completed = task_completed store mapping in
        if completed then
          Ok
            ( No_action "task-already-completed",
              Printf.sprintf "mapping %s: task carries a completion receipt"
                mapping_id )
        else
          let* lease_opt = Store.find_bridge_lease store ~mapping_id in
          match lease_opt with
          | Some (lease : Store.bridge_lease)
            when Int64.compare lease.expires_at_ns now_ns >= 0 ->
              (* Live lease: reconciliation is a no-op on task truth. *)
              Ok
                ( No_action "live-lease",
                  Printf.sprintf
                    "mapping %s: lease %s owner=%s fence=%Ld live until %Ld \
                     (now %Ld)"
                    mapping_id lease.lease_id lease.owner lease.fencing_token
                    lease.expires_at_ns now_ns )
          | Some (lease : Store.bridge_lease) ->
              (* Expired lease, no completion receipt: reclaimable. NEVER
                 complete the task here. *)
              let outcome =
                Printf.sprintf
                  "observed fence=%Ld owner=%s lease=%s expired_at=%Ld \
                   now=%Ld -> task reclaimable by a fresh fenced claim"
                  lease.fencing_token lease.owner lease.lease_id
                  lease.expires_at_ns now_ns
              in
              let* () =
                record_receipt store ~mapping_id ~kind:"expired-lease"
                  ~outcome ~now_ns
              in
              Ok (Reclaim_expired_lease, outcome)
          | None -> (
              let* command_opt =
                Store.find_bridge_command store ~mapping_id
                  ~command_id:close_loop_command_id
              in
              match command_opt with
              | Some (receipt : Store.bridge_command_receipt)
                when String.equal receipt.result "pending" ->
                  (* Interrupted close-loop command: fail closed, never
                     re-execute. *)
                  let* () =
                    record_receipt store ~mapping_id
                      ~kind:"interrupted-command" ~outcome:"failed-closed"
                      ~now_ns
                  in
                  Ok
                    ( Fail_interrupted_command,
                      Printf.sprintf
                        "mapping %s: command %s recorded_at=%Ld still \
                         pending -> failed-closed, not re-executed"
                        mapping_id receipt.command_id receipt.recorded_at_ns
                    )
              | Some (receipt : Store.bridge_command_receipt) ->
                  Ok
                    ( No_action "command-settled",
                      Printf.sprintf
                        "mapping %s: command %s settled with result %S"
                        mapping_id receipt.command_id receipt.result )
              | None ->
                  Ok
                    ( No_action "quiescent",
                      Printf.sprintf
                        "mapping %s: no lease, no close-loop command"
                        mapping_id )))
  with
  | (Ok _ | Error _) as result -> result
  | exception exn ->
      Error ("reconcile: exception: " ^ Printexc.to_string exn)
