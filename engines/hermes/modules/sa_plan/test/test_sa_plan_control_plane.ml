module Control = Sa_plan.Control_plane
module Oracle = Sa_plan.Control_plane_oracle
module Quint = Sa_plan_ooda_bridge

let require label condition =
  if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let identity =
  { Control.ooda_slice_id = "cp-01-contract";
    sa_plan_id = "ooda-sa-plan-control-plane-bridge-20260804-153451";
    sa_task_id = "cp-01-contract";
    lease_id = "lease-cp-01-a";
    gate_run_id = "gate-cp-01-a";
    commit_sha = "0123456789abcdef";
    cycle_id = "cycle-cp-01-a" }

let evidence =
  { Control.id = "evidence-green"; kind = "gate"; digest = "sha256:green" }

let advance id target = Control.Advance { command_id = id; target; evidence = [ evidence ] }
let claim id = Control.Claim { command_id = id; owner = "worker-a"; lease_id = identity.lease_id; fencing_token = 7L }
let progress id target = Control.Progress { command_id = id; owner = "worker-a"; fencing_token = 7L; target; evidence = [ evidence ] }
let complete id = Control.Complete { command_id = id; owner = "worker-a"; fencing_token = 7L; evidence = [ evidence ] }

let commands =
  [ advance "c1" Control.Oriented;
    advance "c2" Control.Selected;
    advance "c3" Control.Materialized;
    advance "c4" Control.Preflighted;
    claim "c5";
    progress "c6" Control.Executing;
    progress "c7" Control.Verifying;
    progress "c8" Control.Verified;
    progress "c9" Control.Recorded;
    complete "c10" ]

let result_or_fail = function Ok value -> value | Error error -> failwith (Control.string_of_error error)
let option_or_fail = function Some value -> value | None -> failwith "unexpected disabled Quint transition"

let quint_phase = function
  | Control.Observed -> 0 | Control.Oriented -> 1 | Control.Selected -> 2
  | Control.Materialized -> 3 | Control.Preflighted -> 4 | Control.Leased -> 5
  | Control.Executing -> 6 | Control.Verifying -> 7 | Control.Verified -> 8
  | Control.Recorded -> 9 | Control.Completed -> 10
  | Control.Blocked | Control.Deferred | Control.Expired | Control.Retryable_failure
  | Control.Permanent_failure | Control.Reconciled -> -1

let require_quint_invariants phase state =
  require (Printf.sprintf "LAW CP-QUINT-PHASE-DOMAIN-%d" phase) (Quint.inv_phase_domain state);
  require (Printf.sprintf "LAW CP-QUINT-VERSION-PROGRESS-%d" phase) (Quint.inv_version_matches_progress state);
  require (Printf.sprintf "LAW CP-QUINT-FENCE-BOUND-%d" phase) (Quint.inv_fence_monotone_bound state);
  require (Printf.sprintf "LAW CP-QUINT-COMPLETION-UNIQUE-%d" phase) (Quint.inv_completion_unique state);
  require (Printf.sprintf "LAW CP-QUINT-COMPLETION-TERMINAL-%d" phase) (Quint.inv_completion_requires_terminal state)

let () =
  let initial = result_or_fail (Control.create ~domain:Control.Otp_parity ~identity) in
  require "LAW CP-REJECTS-EMPTY-COMMAND-ID"
    (match Control.apply initial (advance "" Control.Oriented) with
     | Error Control.Empty_command_id -> true | _ -> false);
  let preflighted = result_or_fail (Control.replay initial (List.filteri (fun index _ -> index < 4) commands)) in
  require "LAW CP-REJECTS-EMPTY-LEASE-OWNER"
    (match Control.apply preflighted
       (Control.Claim { command_id = "empty-owner"; owner = ""; lease_id = identity.lease_id; fencing_token = 7L }) with
     | Error Control.Empty_owner -> true | _ -> false);
  require "LAW CP-REJECTS-NONPOSITIVE-FENCING-TOKEN"
    (match Control.apply preflighted
       (Control.Claim { command_id = "zero-fence"; owner = "worker-a"; lease_id = identity.lease_id; fencing_token = 0L }) with
     | Error (Control.Non_positive_fencing_token 0L) -> true | _ -> false);
  let quint_steps =
    [ Quint.orient, List.nth commands 0; Quint.decide_selected, List.nth commands 1;
      Quint.materialize, List.nth commands 2; Quint.preflight, List.nth commands 3;
      Quint.claim, List.nth commands 4; Quint.execute, List.nth commands 5;
      Quint.start_verification, List.nth commands 6; Quint.verify, List.nth commands 7;
      Quint.record, List.nth commands 8; Quint.complete, List.nth commands 9 ]
  in
  require_quint_invariants 0 Quint.init;
  require "LAW CP-QUINT-OBSERVATIONAL-AGREEMENT-0"
    (Quint.init.Quint.phase = quint_phase (Control.observe initial).state
     && Quint.init.Quint.version = Int64.to_int (Control.observe initial).version
     && Quint.init.Quint.fence = 0 && Quint.init.Quint.completion_count = 0);
  let _, _ =
    List.fold_left
      (fun (quint_state, control_state) (quint_step, command) ->
        let quint_state = option_or_fail (quint_step quint_state) in
        let control_state = result_or_fail (Control.apply control_state command) in
        let observed = Control.observe control_state in
        require_quint_invariants quint_state.Quint.phase quint_state;
        require (Printf.sprintf "LAW CP-QUINT-OBSERVATIONAL-AGREEMENT-%d" quint_state.Quint.phase)
          (quint_state.Quint.phase = quint_phase observed.state
           && quint_state.Quint.version = Int64.to_int observed.version
           && quint_state.Quint.fence = (if Option.is_some observed.lease then 1 else 0)
           && quint_state.Quint.completion_count = (if observed.state = Control.Completed then 1 else 0));
        quint_state, control_state)
      (Quint.init, initial) quint_steps
  in
  let final = result_or_fail (Control.replay initial commands) in
  let observation = Control.observe final in
  require "LAW CP-MONOTONIC-VERSION" (observation.version = 10L && observation.state = Control.Completed);
  let replayed = result_or_fail (Control.apply final (complete "c10")) in
  require "LAW CP-IDEMPOTENT-COMMAND-REPLAY"
    ((Control.observe replayed).version = observation.version && Control.observe replayed = observation);
  require "MUT-CP-OWNER-FENCE-ENFORCEMENT"
    (match Control.apply (result_or_fail (Control.replay initial (List.rev (List.tl (List.rev commands)))))
       (Control.Complete { command_id = "wrong-owner"; owner = "worker-b"; fencing_token = 7L; evidence = [ evidence ] }) with
     | Error (Control.Owner_mismatch _) -> true
     | _ -> false);
  require "LAW CP-FENCE-ENFORCEMENT"
    (match Control.apply (result_or_fail (Control.replay initial (List.rev (List.tl (List.rev commands)))))
       (Control.Complete { command_id = "wrong-fence"; owner = "worker-a"; fencing_token = 8L; evidence = [ evidence ] }) with
     | Error (Control.Fence_mismatch _) -> true
     | _ -> false);
  require "MUT-CP-TERMINAL-COMPLETION-UNIQUENESS"
    (match Control.apply final (complete "different-completion") with
     | Error Control.Terminal_state -> true
     | _ -> false);
  let prefix, suffix = (List.filteri (fun i _ -> i < 5) commands, List.filteri (fun i _ -> i >= 5) commands) in
  let chunked = result_or_fail (Control.replay (result_or_fail (Control.replay initial prefix)) suffix) in
  require "LAW CP-REPLAY-CHUNKING" (Control.observe chunked = observation);
  let oracle = Oracle.replay (Oracle.create ~domain:Control.Otp_parity ~identity) commands in
  require "LAW CP-ORACLE-FINAL-OBSERVATIONAL-AGREEMENT" (Oracle.observe oracle = observation);
  let seeded = Random.State.make [| 20260804; 17 |] in
  for trial = 1 to 32 do
    let trace = if Random.State.bool seeded then commands else commands @ [ complete "c10" ] in
    let candidate = result_or_fail (Control.replay initial trace) in
    let oracle_candidate = Oracle.replay (Oracle.create ~domain:Control.Otp_parity ~identity) trace in
    require (Printf.sprintf "LAW CP-SEEDED-ORACLE-%02d" trial)
      (Control.observe candidate = Oracle.observe oracle_candidate)
  done
