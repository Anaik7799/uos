let checks = ref 0
let failures = ref 0

let check name condition =
  incr checks;
  if not condition then begin incr failures; Printf.eprintf "FAIL: %s\n" name end

let provenance : Run_model.provenance =
  { source_revision = "80f93278"; source_clean = true;
    configuration_digest = String.make 64 'a'; authority_digest = String.make 64 'b';
    executable_digest = String.make 64 'c' }

let coordinate : Ops_capability.coordinate =
  { level = Ops_capability.L2; phase = Ops_capability.Observe }

let make ?(run_id = "run-1") ?(sequence = 0L) ?(event_id = "event-0")
    ?(kind = Run_model.Run_declared) ?(subject = Run_model.Run)
    ?(payload = `Assoc []) ?previous_digest ?(provenance = provenance) () =
  Run_model.make ~run_id ~sequence ~event_id ~kind ~subject
    ~plane:Ops_capability.Control_plane ~coordinate ~rca_origin:Ops_capability.Control
    ~occurred_at_ns:(Int64.add 100L sequence) ~monotonic_at_ns:(Int64.add 50L sequence)
    ~provenance ~payload ~previous_digest

let event_exn = function Ok event -> event | Error error -> failwith error
let snapshot_exn = function Ok snapshot -> snapshot | Error error -> failwith error
let applied = function Ok (Run_snapshot.Applied snapshot) -> snapshot | _ -> failwith "expected Applied"

let next previous ~kind ~subject ?(payload = `Assoc []) event_id =
  event_exn
    (make ~sequence:(Int64.succ previous.Run_model.sequence) ~event_id ~kind ~subject
       ~payload ~previous_digest:previous.digest ())

let lifecycle_payload value = `Assoc [ ("lifecycle", `String value) ]

let advance snapshot previous ~kind ~subject ?payload event_id =
  let event = next previous ~kind ~subject ?payload event_id in
  (applied (Run_snapshot.apply snapshot event), event)

let phase_cycle snapshot previous phase name =
  let active, started =
    advance snapshot previous ~kind:Run_model.Phase_started
      ~subject:(Run_model.Phase phase) (name ^ "-started")
  in
  advance active started ~kind:Run_model.Phase_finished
    ~subject:(Run_model.Phase phase) (name ^ "-finished")

let () =
  Printf.printf "[unit] deterministic snapshot fold and validated head\n";
  check "first accepted sequence is explicitly zero" (Run_snapshot.first_sequence = 0L);
  check "empty refuses an empty run id"
    (match Run_snapshot.empty ~run_id:"" ~provenance with Error _ -> true | Ok _ -> false);
  check "empty refuses an invalid exact head"
    (match Run_snapshot.empty ~run_id:"run-1"
             ~provenance:{ provenance with executable_digest = "bad" } with
     | Error _ -> true | Ok _ -> false);
  let initial = snapshot_exn (Run_snapshot.empty ~run_id:"run-1" ~provenance) in
  let declared = event_exn (make ()) in
  let declared_snapshot = applied (Run_snapshot.apply initial declared) in
  check "declaration establishes sequence identity"
    (Run_snapshot.last_sequence declared_snapshot = 0L
     && Run_snapshot.last_digest declared_snapshot = Some declared.digest
     && Run_snapshot.lifecycle declared_snapshot = Run_model.Declared);
  check "same identity and digest replay is idempotent"
    (match Run_snapshot.apply declared_snapshot declared with
     | Ok (Run_snapshot.Duplicate same) -> Run_snapshot.last_sequence same = 0L
     | _ -> false);
  let divergent_id = event_exn (make ~payload:(`Assoc [ ("changed", `Bool true) ]) ()) in
  check "same event identity with different digest is rejected"
    (match Run_snapshot.apply declared_snapshot divergent_id with Error _ -> true | _ -> false);
  let divergent_sequence = event_exn (make ~event_id:"other-at-zero" ()) in
  check "same sequence with different identity is rejected"
    (match Run_snapshot.apply declared_snapshot divergent_sequence with Error _ -> true | _ -> false);
  let gap = event_exn (make ~sequence:2L ~event_id:"gap" ~kind:Run_model.Heartbeat
                         ~previous_digest:declared.digest ()) in
  check "a forward sequence gap is reported without mutation"
    (match Run_snapshot.apply declared_snapshot gap with
     | Ok (Run_snapshot.Gap { expected; observed }) ->
         expected = 1L && observed = 2L
         && Run_snapshot.last_sequence declared_snapshot = 0L
     | _ -> false);
  let bad_chain = event_exn (make ~sequence:1L ~event_id:"bad-chain" ~kind:Run_model.Heartbeat
                               ~previous_digest:(String.make 64 'f') ()) in
  check "a contiguous event with a wrong previous digest is rejected"
    (match Run_snapshot.apply declared_snapshot bad_chain with Error _ -> true | _ -> false);
  let wrong_run = event_exn (make ~run_id:"run-2" ~sequence:1L ~event_id:"wrong-run"
                               ~kind:Run_model.Heartbeat ~previous_digest:declared.digest ()) in
  check "cross-run event injection is rejected"
    (match Run_snapshot.apply declared_snapshot wrong_run with Error _ -> true | _ -> false);
  let stale_provenance = { provenance with source_revision = "stale" } in
  let stale = event_exn (make ~sequence:1L ~event_id:"stale" ~kind:Run_model.Heartbeat
                           ~previous_digest:declared.digest ~provenance:stale_provenance ()) in
  check "exact-head provenance drift is rejected"
    (match Run_snapshot.apply declared_snapshot stale with Error _ -> true | _ -> false);

  Printf.printf "[bdd] explicit phase and lifecycle transition table\n";
  let early_start = next declared ~kind:Run_model.Run_started ~subject:Run_model.Run
      "start-before-admission-complete" in
  check "run cannot start before Admission completes"
    (match Run_snapshot.apply declared_snapshot early_start with Error _ -> true | _ -> false);
  let admitted, admission_started =
    advance declared_snapshot declared ~kind:Run_model.Phase_started
      ~subject:(Run_model.Phase Run_model.Admission) "admission-started"
  in
  check "Admission start moves lifecycle to admitted"
    (Run_snapshot.lifecycle admitted = Run_model.Admitted);
  let after_admission, admission_finished =
    advance admitted admission_started ~kind:Run_model.Phase_finished
      ~subject:(Run_model.Phase Run_model.Admission) "admission-finished"
  in
  let running, run_started =
    advance after_admission admission_finished ~kind:Run_model.Run_started
      ~subject:Run_model.Run "run-started"
  in
  check "completed Admission permits run start"
    (Run_snapshot.lifecycle running = Run_model.Running);
  let early_finish = next run_started ~kind:Run_model.Run_finished ~subject:Run_model.Run
      ~payload:(lifecycle_payload "succeeded") "finish-before-publication" in
  check "run cannot finish before Publication completes"
    (match Run_snapshot.apply running early_finish with Error _ -> true | _ -> false);
  let skipped_phase = next run_started ~kind:Run_model.Phase_started
      ~subject:(Run_model.Phase Run_model.Discovery) "skip-authority" in
  check "a phase cannot skip its causal predecessor"
    (match Run_snapshot.apply running skipped_phase with Error _ -> true | _ -> false);
  let suite_outside_phase = next run_started ~kind:Run_model.Suite_discovered
      ~subject:(Run_model.Suite "outside") "suite-outside-phase" in
  check "suite cannot be discovered outside active Suite_execution"
    (match Run_snapshot.apply running suite_outside_phase with Error _ -> true | _ -> false);

  let after_authority, authority_finished =
    phase_cycle running run_started Run_model.Authority_preflight "authority"
  in
  let after_discovery, discovery_finished =
    phase_cycle after_authority authority_finished Run_model.Discovery "discovery"
  in
  let after_build, build_finished =
    phase_cycle after_discovery discovery_finished Run_model.Build "build"
  in
  let dispatch_active, dispatch_started =
    advance after_build build_finished ~kind:Run_model.Phase_started
      ~subject:(Run_model.Phase Run_model.Dispatch) "dispatch-started"
  in

  Printf.printf "[feature] private Swarm attempt transition algebra\n";
  let terminal_before_ready = next dispatch_started ~kind:Run_model.Swarm_step_terminal
      ~subject:(Run_model.Attempt ("build", 0)) "terminal-before-ready" in
  check "swarm attempt cannot terminate before ready"
    (match Run_snapshot.apply dispatch_active terminal_before_ready with Error _ -> true | _ -> false);
  let running_before_ready = next dispatch_started ~kind:Run_model.Swarm_step_running
      ~subject:(Run_model.Attempt ("build", 0)) "running-before-ready" in
  check "swarm attempt cannot run before ready"
    (match Run_snapshot.apply dispatch_active running_before_ready with Error _ -> true | _ -> false);
  let attempt_ready_snapshot, attempt_ready =
    advance dispatch_active dispatch_started ~kind:Run_model.Swarm_step_ready
      ~subject:(Run_model.Attempt ("build", 0)) "attempt-0-ready"
  in
  check "ready attempt is read-only observable"
    (Run_snapshot.attempt_state attempt_ready_snapshot ~step:"build" ~attempt:0
     = Some Run_snapshot.Attempt_ready);
  check "exact ready replay remains idempotent"
    (match Run_snapshot.apply attempt_ready_snapshot attempt_ready with
     | Ok (Run_snapshot.Duplicate _) -> true | _ -> false);
  let ready_repeat = next attempt_ready ~kind:Run_model.Swarm_step_ready
      ~subject:(Run_model.Attempt ("build", 0)) "attempt-0-ready-again" in
  check "a new ready identity cannot reuse an active attempt"
    (match Run_snapshot.apply attempt_ready_snapshot ready_repeat with Error _ -> true | _ -> false);
  let attempt_running_snapshot, attempt_running =
    advance attempt_ready_snapshot attempt_ready ~kind:Run_model.Swarm_step_running
      ~subject:(Run_model.Attempt ("build", 0)) "attempt-0-running"
  in
  check "ready advances to running"
    (Run_snapshot.attempt_state attempt_running_snapshot ~step:"build" ~attempt:0
     = Some Run_snapshot.Attempt_running);
  let running_repeat = next attempt_running ~kind:Run_model.Swarm_step_running
      ~subject:(Run_model.Attempt ("build", 0)) "attempt-0-running-again" in
  check "a running transition cannot repeat under a new identity"
    (match Run_snapshot.apply attempt_running_snapshot running_repeat with Error _ -> true | _ -> false);
  let attempt_terminal_snapshot, attempt_terminal =
    advance attempt_running_snapshot attempt_running ~kind:Run_model.Swarm_step_terminal
      ~subject:(Run_model.Attempt ("build", 0)) ~payload:(lifecycle_payload "succeeded")
      "attempt-0-terminal"
  in
  check "running advances to terminal"
    (Run_snapshot.attempt_state attempt_terminal_snapshot ~step:"build" ~attempt:0
     = Some (Run_snapshot.Attempt_terminal Run_model.Succeeded));
  let reuse_terminal = next attempt_terminal ~kind:Run_model.Swarm_step_ready
      ~subject:(Run_model.Attempt ("build", 0)) "attempt-0-reuse" in
  check "terminal attempt absorbs reuse"
    (match Run_snapshot.apply attempt_terminal_snapshot reuse_terminal with Error _ -> true | _ -> false);
  let terminal_without_outcome = next attempt_running ~kind:Run_model.Swarm_step_terminal
      ~subject:(Run_model.Attempt ("build", 0)) "attempt-0-terminal-no-outcome" in
  check "swarm terminal requires an explicit terminal lifecycle payload"
    (match Run_snapshot.apply attempt_running_snapshot terminal_without_outcome with
     | Error _ -> true | _ -> false);
  let retry_snapshot, retry_ready =
    advance attempt_terminal_snapshot attempt_terminal ~kind:Run_model.Swarm_step_ready
      ~subject:(Run_model.Attempt ("build", 1)) "attempt-1-ready"
  in
  check "a distinct retry attempt id is independent"
    (Run_snapshot.attempt_state retry_snapshot ~step:"build" ~attempt:0
       = Some (Run_snapshot.Attempt_terminal Run_model.Succeeded)
     && Run_snapshot.attempt_state retry_snapshot ~step:"build" ~attempt:1
        = Some Run_snapshot.Attempt_ready
     && (Run_snapshot.counts retry_snapshot).attempts_ready = 2
     && (Run_snapshot.counts retry_snapshot).attempts_running = 1
     && (Run_snapshot.counts retry_snapshot).attempts_terminal = 1);

  let finish_with_retry_ready = next retry_ready ~kind:Run_model.Phase_finished
      ~subject:(Run_model.Phase Run_model.Dispatch) "dispatch-finish-retry-ready" in
  check "Dispatch cannot finish with a ready admitted attempt"
    (match Run_snapshot.apply retry_snapshot finish_with_retry_ready with
     | Error _ -> true | _ -> false);
  let retry_running_snapshot, retry_running =
    advance retry_snapshot retry_ready ~kind:Run_model.Swarm_step_running
      ~subject:(Run_model.Attempt ("build", 1)) "attempt-1-running"
  in
  let finish_with_retry_running = next retry_running ~kind:Run_model.Phase_finished
      ~subject:(Run_model.Phase Run_model.Dispatch) "dispatch-finish-retry-running" in
  check "Dispatch cannot finish with a running admitted attempt"
    (match Run_snapshot.apply retry_running_snapshot finish_with_retry_running with
     | Error _ -> true | _ -> false);

  let retry_terminal_snapshot, retry_terminal =
    advance retry_running_snapshot retry_running ~kind:Run_model.Swarm_step_terminal
      ~subject:(Run_model.Attempt ("build", 1)) ~payload:(lifecycle_payload "succeeded")
      "attempt-1-terminal"
  in
  check "retry terminal preserves its outcome"
    (Run_snapshot.attempt_state retry_terminal_snapshot ~step:"build" ~attempt:1
     = Some (Run_snapshot.Attempt_terminal Run_model.Succeeded));

  let after_dispatch, dispatch_finished =
    advance retry_terminal_snapshot retry_terminal ~kind:Run_model.Phase_finished
      ~subject:(Run_model.Phase Run_model.Dispatch) "dispatch-finished"
  in
  let suite_phase, suite_phase_started =
    advance after_dispatch dispatch_finished ~kind:Run_model.Phase_started
      ~subject:(Run_model.Phase Run_model.Suite_execution) "suite-execution-started"
  in
  let suite_pending, suite_discovered =
    advance suite_phase suite_phase_started ~kind:Run_model.Suite_discovered
      ~subject:(Run_model.Suite "codec") "suite-discovered"
  in
  let child_pending_finish = next suite_discovered ~kind:Run_model.Phase_finished
      ~subject:(Run_model.Phase Run_model.Suite_execution) "suite-phase-finish-pending" in
  check "Suite_execution cannot finish with a pending child"
    (match Run_snapshot.apply suite_pending child_pending_finish with Error _ -> true | _ -> false);
  let suite_active, suite_started =
    advance suite_pending suite_discovered ~kind:Run_model.Suite_started
      ~subject:(Run_model.Suite "codec") "suite-started"
  in
  let child_active_finish = next suite_started ~kind:Run_model.Phase_finished
      ~subject:(Run_model.Phase Run_model.Suite_execution) "suite-phase-finish-active" in
  check "Suite_execution cannot finish with an active child"
    (match Run_snapshot.apply suite_active child_active_finish with Error _ -> true | _ -> false);
  let suite_succeeded, suite_finished =
    advance suite_active suite_started ~kind:Run_model.Suite_finished
      ~subject:(Run_model.Suite "codec") ~payload:(lifecycle_payload "succeeded")
      "suite-finished"
  in
  let after_suites, suites_phase_finished =
    advance suite_succeeded suite_finished ~kind:Run_model.Phase_finished
      ~subject:(Run_model.Phase Run_model.Suite_execution) "suite-execution-finished"
  in
  let after_aggregation, aggregation_finished =
    phase_cycle after_suites suites_phase_finished Run_model.Aggregation "aggregation"
  in
  let after_completion, completion_finished =
    phase_cycle after_aggregation aggregation_finished Run_model.Completion_admission "completion"
  in
  let after_publication, publication_finished =
    phase_cycle after_completion completion_finished Run_model.Publication "publication"
  in
  let terminal, run_finished =
    advance after_publication publication_finished ~kind:Run_model.Run_finished
      ~subject:Run_model.Run ~payload:(lifecycle_payload "succeeded") "run-finished"
  in
  check "full causal table permits successful terminal admission"
    (Run_snapshot.lifecycle terminal = Run_model.Succeeded && Run_snapshot.is_terminal terminal);
  let after_terminal = next run_finished ~kind:Run_model.Heartbeat ~subject:Run_model.Run "too-late" in
  check "terminal lifecycle absorbs every new identity"
    (match Run_snapshot.apply terminal after_terminal with Error _ -> true | _ -> false);
  check "terminal duplicate remains idempotent"
    (match Run_snapshot.apply terminal run_finished with Ok (Run_snapshot.Duplicate _) -> true | _ -> false);
  let summary = Run_snapshot.summary terminal in
  check "summary exposes exact head and terminal state"
    (summary.run_id = "run-1" && summary.last_digest = Some run_finished.digest
     && summary.terminal && summary.source_revision = provenance.source_revision
     && summary.configuration_digest = provenance.configuration_digest
     && summary.authority_digest = provenance.authority_digest
     && summary.executable_digest = provenance.executable_digest);

  Printf.printf "[chaos] false success and child failure\n";
  let suite_failed_snapshot, suite_failed =
    advance suite_active suite_started ~kind:Run_model.Suite_finished
      ~subject:(Run_model.Suite "codec") ~payload:(lifecycle_payload "failed")
      "suite-failed"
  in
  let failed_after_suites, failed_suites_finished =
    advance suite_failed_snapshot suite_failed ~kind:Run_model.Phase_finished
      ~subject:(Run_model.Phase Run_model.Suite_execution) "failed-suite-execution-finished"
  in
  let failed_after_aggregation, failed_aggregation_finished =
    phase_cycle failed_after_suites failed_suites_finished Run_model.Aggregation "failed-aggregation"
  in
  let failed_after_completion, failed_completion_finished =
    phase_cycle failed_after_aggregation failed_aggregation_finished
      Run_model.Completion_admission "failed-completion"
  in
  let failed_after_publication, failed_publication_finished =
    phase_cycle failed_after_completion failed_completion_finished Run_model.Publication
      "failed-publication"
  in
  let false_success = next failed_publication_finished ~kind:Run_model.Run_finished
      ~subject:Run_model.Run ~payload:(lifecycle_payload "succeeded") "false-success" in
  check "Succeeded is forbidden when any suite failed"
    (match Run_snapshot.apply failed_after_publication false_success with Error _ -> true | _ -> false);
  let honest_failure = next failed_publication_finished ~kind:Run_model.Run_finished
      ~subject:Run_model.Run ~payload:(lifecycle_payload "failed") "honest-failure" in
  check "failed child permits an honest Failed run terminal"
    (match Run_snapshot.apply failed_after_publication honest_failure with
     | Ok (Run_snapshot.Applied result) -> Run_snapshot.lifecycle result = Run_model.Failed
     | _ -> false);

  let failed_attempt_snapshot, failed_attempt =
    advance attempt_running_snapshot attempt_running ~kind:Run_model.Swarm_step_terminal
      ~subject:(Run_model.Attempt ("build", 0)) ~payload:(lifecycle_payload "failed")
      "attempt-0-failed"
  in
  check "failed attempt terminal preserves its outcome"
    (Run_snapshot.attempt_state failed_attempt_snapshot ~step:"build" ~attempt:0
     = Some (Run_snapshot.Attempt_terminal Run_model.Failed));
  let failed_attempt_after_dispatch, failed_attempt_dispatch_finished =
    advance failed_attempt_snapshot failed_attempt ~kind:Run_model.Phase_finished
      ~subject:(Run_model.Phase Run_model.Dispatch) "failed-attempt-dispatch-finished"
  in
  let failed_attempt_suite_phase, failed_attempt_suite_phase_started =
    advance failed_attempt_after_dispatch failed_attempt_dispatch_finished
      ~kind:Run_model.Phase_started ~subject:(Run_model.Phase Run_model.Suite_execution)
      "failed-attempt-suite-phase-started"
  in
  let failed_attempt_suite_pending, failed_attempt_suite_discovered =
    advance failed_attempt_suite_phase failed_attempt_suite_phase_started
      ~kind:Run_model.Suite_discovered ~subject:(Run_model.Suite "codec")
      "failed-attempt-suite-discovered"
  in
  let failed_attempt_suite_active, failed_attempt_suite_started =
    advance failed_attempt_suite_pending failed_attempt_suite_discovered
      ~kind:Run_model.Suite_started ~subject:(Run_model.Suite "codec")
      "failed-attempt-suite-started"
  in
  let failed_attempt_suite_succeeded, failed_attempt_suite_finished =
    advance failed_attempt_suite_active failed_attempt_suite_started
      ~kind:Run_model.Suite_finished ~subject:(Run_model.Suite "codec")
      ~payload:(lifecycle_payload "succeeded") "failed-attempt-suite-finished"
  in
  let failed_attempt_after_suites, failed_attempt_suites_finished =
    advance failed_attempt_suite_succeeded failed_attempt_suite_finished
      ~kind:Run_model.Phase_finished ~subject:(Run_model.Phase Run_model.Suite_execution)
      "failed-attempt-suite-phase-finished"
  in
  let failed_attempt_after_aggregation, failed_attempt_aggregation_finished =
    phase_cycle failed_attempt_after_suites failed_attempt_suites_finished
      Run_model.Aggregation "failed-attempt-aggregation"
  in
  let failed_attempt_after_completion, failed_attempt_completion_finished =
    phase_cycle failed_attempt_after_aggregation failed_attempt_aggregation_finished
      Run_model.Completion_admission "failed-attempt-completion"
  in
  let failed_attempt_after_publication, failed_attempt_publication_finished =
    phase_cycle failed_attempt_after_completion failed_attempt_completion_finished
      Run_model.Publication "failed-attempt-publication"
  in
  let failed_attempt_false_success =
    next failed_attempt_publication_finished ~kind:Run_model.Run_finished
      ~subject:Run_model.Run ~payload:(lifecycle_payload "succeeded")
      "failed-attempt-false-success"
  in
  check "Succeeded is forbidden when any admitted attempt failed"
    (match Run_snapshot.apply failed_attempt_after_publication failed_attempt_false_success with
     | Error _ -> true | _ -> false);
  let failed_attempt_honest_failure =
    next failed_attempt_publication_finished ~kind:Run_model.Run_finished
      ~subject:Run_model.Run ~payload:(lifecycle_payload "failed")
      "failed-attempt-honest-failure"
  in
  check "failed attempt permits an honest Failed run terminal"
    (match Run_snapshot.apply failed_attempt_after_publication failed_attempt_honest_failure with
     | Ok (Run_snapshot.Applied result) -> Run_snapshot.lifecycle result = Run_model.Failed
     | _ -> false);

  Printf.printf "[property] seeded stream permutations and replay stability\n";
  let random = Random.State.make [| 0x4f4f4441; 0x5245504c |] in
  let rec split_at count acc values =
    if count = 0 then (List.rev acc, values)
    else match values with
      | [] -> (List.rev acc, [])
      | value :: rest -> split_at (count - 1) (value :: acc) rest
  in
  for repetition = 0 to 99 do
    let length = 2 + Random.State.int random 31 in
    let rec build previous remaining acc =
      if remaining = 0 then List.rev acc
      else
        let sequence = Int64.succ previous.Run_model.sequence in
        let event = event_exn
            (make ~sequence ~event_id:(Printf.sprintf "p-%d-%Ld" repetition sequence)
               ~kind:Run_model.Heartbeat ~previous_digest:previous.digest ()) in
        build event (remaining - 1) (event :: acc)
    in
    let ordered = build declared length [] in
    let offset = 1 + Random.State.int random (length - 1) in
    let prefix, suffix = split_at offset [] ordered in
    let permuted = suffix @ prefix in
    let observed = (List.hd permuted).Run_model.sequence in
    check ("permutation exposes gap " ^ string_of_int repetition)
      (match Run_snapshot.apply declared_snapshot (List.hd permuted) with
       | Ok (Run_snapshot.Gap { expected; observed = actual }) ->
           expected = 1L && actual = observed
           && Run_snapshot.last_sequence declared_snapshot = 0L
       | _ -> false);
    let final_snapshot =
      List.fold_left
        (fun snapshot event -> applied (Run_snapshot.apply snapshot event))
        declared_snapshot ordered
    in
    check ("ordered stream reaches exact sequence " ^ string_of_int repetition)
      (Run_snapshot.last_sequence final_snapshot = Int64.of_int length);
    let stale_index = Random.State.int random length in
    let stale_original = List.nth ordered stale_index in
    let previous_digest =
      if stale_index = 0 then declared.digest else (List.nth ordered (stale_index - 1)).digest
    in
    let stale_event = event_exn
        (make ~sequence:stale_original.sequence
           ~event_id:(Printf.sprintf "stale-%d-%d" repetition stale_index)
           ~kind:Run_model.Heartbeat ~previous_digest ())
    in
    check ("stale permutation is refused without mutation " ^ string_of_int repetition)
      (match Run_snapshot.apply final_snapshot stale_event with
       | Error _ -> Run_snapshot.last_sequence final_snapshot = Int64.of_int length
       | _ -> false);
    check ("valid stale duplicate remains idempotent " ^ string_of_int repetition)
      (match Run_snapshot.apply final_snapshot stale_original with
       | Ok (Run_snapshot.Duplicate same) ->
           Run_snapshot.last_sequence same = Int64.of_int length
       | _ -> false)
  done;
  check "empty fold refuses invented state" (match Run_snapshot.fold [] with Error _ -> true | _ -> false);
  Printf.printf "run_snapshot: %d checks, %d failures\n" !checks !failures;
  let self =
    Suite_telemetry.observe ~suite:"test_run_snapshot"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
