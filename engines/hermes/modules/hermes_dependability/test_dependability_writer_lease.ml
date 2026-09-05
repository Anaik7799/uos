open Dependability_writer_lease

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.eprintf "FAILED: %s\n" name
  end

let get = function Ok value -> value | Error _ -> failwith "valid fixture refused"

let id make value = get (make value)

let clock lifetime_ns =
  get
    (Dependability_clock.observe
       ~max_pair_span_ns:Dependability_clock.maximum_pair_span_ns
       ~lifetime_ns)

let contract ~operation ~lifetime_ns =
  get
    (prepare_acquisition
       ~lease:(id Jj_id.Lease.make "lease-01")
       ~repository:(id Jj_id.Repository.make "repository-01")
       ~workspace:(id Jj_id.Workspace.make "workspace-01")
       ~expected_operation:operation
       ~expected_change:(id Jj_id.Change.make "change-before-01")
       ~expected_commit:(id Jj_id.Commit.make "commit-before-01")
       ~holder:(id Jj_id.Approval.make "approved-plan-01")
       ~operator_quiescence:(id Jj_id.Receipt.make "quiescence-01")
       ~observed_at:(clock lifetime_ns))

let unavailable code = function
  | Error diagnostic ->
      diagnostic_code diagnostic = code
      && diagnostic_coordinate diagnostic = "L2.Task6.WriterLease"
      && diagnostic_origin diagnostic = Evidence
  | Ok () -> false

let () =
  let expected = id Jj_id.Operation.make "operation-before-01" in
  let changed = id Jj_id.Operation.make "operation-after-01" in
  let prepared = contract ~operation:expected ~lifetime_ns:1_000_000_000L in
  let initial = initial_state prepared in
  check "W1 prepared acquisition binds identity and is nonauthorizing"
    (String.length (acquisition_digest prepared) = 64
     && contract_is_current initial
     && permits_acquisition_request initial
     && not (permits_next_governed_action initial));

  check "W2 every production prerequisite is exact typed unavailable"
    (List.for_all
       (fun (prerequisite, code) ->
          unavailable code (prerequisite_status prerequisite))
       [ (Physical_owner_lock_backend,
          "physical-owner-lock-backend-unavailable");
         (Approval_current_carrier,
          "approval-current-carrier-unavailable");
         (Authority_writer_fence_transition,
          "authority-writer-fence-transition-unavailable");
         (Authority_role_session_fence,
          "authority-role-session-fence-unavailable");
         (Nominal_writer_peer_open_fence,
          "nominal-writer-peer-open-fence-unavailable") ]
     && production_posture = `Implemented_unavailable);

  let head_fenced =
    get
      (observe initial ~now:(clock 1_000_000_000L)
         ~observed_operation:changed ~external_writer_detected:false
         ~mutation_state:Not_started)
  in
  check "W3 changed operation fences the contract"
    (fence_reason head_fenced = Some Head_changed
     && not (contract_is_current head_fenced)
     && not (permits_acquisition_request head_fenced));

  let external_fenced =
    get
      (observe initial ~now:(clock 1_000_000_000L)
         ~observed_operation:expected ~external_writer_detected:true
         ~mutation_state:Not_started)
  in
  check "W4 a sensed external writer fences the contract"
    (fence_reason external_fenced = Some External_writer_detected
     && not (permits_next_governed_action external_fenced));

  let absorbed =
    get
      (observe head_fenced ~now:(clock 1_000_000_000L)
         ~observed_operation:expected ~external_writer_detected:false
         ~mutation_state:Not_started)
  in
  check "W5 a fence is absorbing"
    (fence_reason absorbed = Some Head_changed
     && not (contract_is_current absorbed));

  let expiring = contract ~operation:expected ~lifetime_ns:1L in
  let expired_during_started =
    get
      (observe (initial_state expiring) ~now:(clock 1_000_000_000L)
         ~observed_operation:expected ~external_writer_detected:false
         ~mutation_state:Started)
  in
  check "W6 expiry during a started mutation permits only completion and full readback"
    (fence_reason expired_during_started
       = Some Lease_expired_during_started_mutation
     && started_mutation_may_complete expired_during_started
     && requires_full_readback expired_during_started
     && readback_requirement expired_during_started
        = Full_supervision_readback_required
     && not (permits_next_governed_action expired_during_started));

  check "W7 source authority kills every named writer-lease mutant"
    (String.length source_digest = 64
     && List.for_all
          (fun mutation ->
             source_digest <> For_test.source_digest_with_mutation mutation)
          [ For_test.Invent_physical_lock;
            Drop_approval_current;
            Drop_authority_fence_transition;
            Accept_raw_time;
            Permit_after_fence;
            Kill_started_mutation_on_expiry;
            Skip_full_readback;
            Forge_current_owner ]);

  let self =
    Suite_telemetry.observe ~suite:"test_dependability_writer_lease"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_writer_lease ]);
  exit (Suite_telemetry.exit_code self)
