(* verify_fence_fixture.exe DB PLAN TASK WORKER MAPPING_KEY LEASE_ID LEASE_NS

   Prepares an ISOLATED Sa-plan database for a service-level test of the
   Telegram /verify dispatch: a plan, a task, a bridge mapping, an executing
   task claim by WORKER with a live lease, and a bridge lease bound to that
   claim. Prints one JSON line with the identities the test must bind:
   {mapping_id, attempt, fencing_token, lease_until_ns, expires_at_ns}.

   Test fixture only. It is never run against the canonical store: the caller
   passes a temporary database path, and the Store API refuses nothing here
   because the database is new. Times come from the host clock so the live
   fence checks of the service see an unexpired lease. *)

module Store = Sa_plan.Store

let ok = function
  | Ok value -> value
  | Error error ->
      prerr_endline ("verify_fence_fixture: " ^ error);
      exit 2

let () =
  match Sys.argv with
  | [| _; db; plan; task; worker; key; lease_id; lease_ns |] ->
      let now_ns = Int64.of_float (Unix.gettimeofday () *. 1e9) in
      let lease_ns = Int64.of_string lease_ns in
      let store = ok (Store.open_db db) in
      ok
        (Store.create_plan store ~id:plan ~name:(plan ^ "/tests")
           ~title:"isolated verify fixture" ~now_ns);
      ok
        (Store.create_task store ~plan_id:plan ~id:task
           ~name:(plan ^ "/" ^ task) ~title:task ~parent_id:None
           ~dependencies:[] ~priority:1 ~now_ns);
      let request =
        Store.
          { domain = Sa_plan;
            ooda_slice_id = key;
            idempotency_key = key;
            source_fingerprint = "source-a";
            dependency_snapshot = "[]";
            prompt_ledger_hash = "prompt-a";
            safety_packet_hash = "safety-a";
            formal_evidence_hash = "formal-a";
            sa_plan_id = Some plan;
            sa_task_id = Some task;
            lifecycle_state = "preflighted";
            created_at_ns = now_ns }
      in
      let mapping = ok (Store.ensure_bridge_mapping store request) in
      let claim =
        ok (Store.claim_task store ~plan_id:plan ~task_id:task ~worker ~now_ns ~lease_ns)
      in
      let lease =
        ok
          (Store.bind_bridge_to_claimed_task store ~mapping_id:mapping.id
             ~owner:worker ~expected_attempt:claim.attempt ~lease_id ~now_ns
             ~lease_ns)
      in
      Store.close store;
      Printf.printf
        "{\"mapping_id\":\"%s\",\"attempt\":%d,\"fencing_token\":%Ld,\"lease_until_ns\":%Ld,\"expires_at_ns\":%Ld}\n"
        mapping.id claim.attempt lease.fencing_token claim.lease_until_ns
        lease.expires_at_ns
  | _ ->
      prerr_endline
        "usage: verify_fence_fixture.exe DB PLAN TASK WORKER MAPPING_KEY LEASE_ID LEASE_NS";
      exit 2
