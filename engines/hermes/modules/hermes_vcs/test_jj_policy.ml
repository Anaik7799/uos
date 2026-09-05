let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let get = function Ok value -> value | Error _ -> failwith "valid fixture rejected"

let repository = get (Jj_id.Repository.make "repo-main")
let workspace = get (Jj_id.Workspace.make "workspace-main")
let operation = get (Jj_id.Operation.make "op-1")
let changed_operation = get (Jj_id.Operation.make "op-2")
let change = get (Jj_id.Change.make "change-1")
let commit = get (Jj_id.Commit.make "commit-1")
let holder = get (Jj_id.Approval.make "operator-1")
let lease_id = get (Jj_id.Lease.make "lease-1")
let quiescence = get (Jj_id.Receipt.make "quiescence-1")

let lease_claim : Jj_writer_lease.claim =
  { lease_id; repository; workspace; expected_operation = operation;
    expected_change = change; expected_commit = commit; holder;
    expires_at_epoch = 200L; fence_epoch = 7L;
    operator_quiescence = quiescence; release_readback = None }

let policy_tests () =
  check "P1 at-operation observation cannot request snapshotting"
    (Jj_policy.evaluate Jj_policy.Observe_only ~snapshot_requested:true
       Jj_operation.Status_at_operation
     = Jj_policy.Deny Jj_policy.Snapshot_forbidden);
  check "P2 working-copy snapshot requires mutation authority"
    (Jj_policy.evaluate Jj_policy.Observe_only ~snapshot_requested:false
       Jj_operation.Working_copy_snapshot
     = Jj_policy.Deny Jj_policy.Insufficient_authority
     && Jj_policy.evaluate Jj_policy.Local_mutation ~snapshot_requested:false
          Jj_operation.Working_copy_snapshot = Jj_policy.Permit);
  check "P3 fetch requires its mutation-bearing fetch authority"
    (Jj_policy.evaluate Jj_policy.Observe_only ~snapshot_requested:false
       Jj_operation.Git_fetch = Jj_policy.Deny Jj_policy.Insufficient_authority
     && Jj_policy.evaluate Jj_policy.Fetch ~snapshot_requested:false
          Jj_operation.Git_fetch = Jj_policy.Permit);
  check "P4 local approval cannot authorize rewrite recovery or remote work"
    (List.for_all
       (fun op ->
          Jj_policy.evaluate Jj_policy.Local_mutation ~snapshot_requested:false op
          = Jj_policy.Deny Jj_policy.Insufficient_authority)
       [ Jj_operation.Rebase; Jj_operation.Operation_restore;
         Jj_operation.Git_fetch; Jj_operation.Git_push ]);
  check "P5 recovery authority cannot publish"
    (Jj_policy.evaluate Jj_policy.Recovery ~snapshot_requested:false
       Jj_operation.Git_push = Jj_policy.Deny Jj_policy.Insufficient_authority);
  check "P6 deny overrides permit"
    (Jj_policy.combine Jj_policy.Permit
       (Jj_policy.Deny Jj_policy.Stale_authority)
     = Jj_policy.Deny Jj_policy.Stale_authority
     && Jj_policy.combine (Jj_policy.Deny Jj_policy.Stale_authority)
          Jj_policy.Permit = Jj_policy.Deny Jj_policy.Stale_authority);
  check "P7 destructive-local and history-rewrite capabilities cannot cross"
    (Jj_policy.evaluate Jj_policy.Destructive_local ~snapshot_requested:false
       Jj_operation.Rebase = Jj_policy.Deny Jj_policy.Insufficient_authority
     && Jj_policy.evaluate Jj_policy.History_rewrite ~snapshot_requested:false
          Jj_operation.Bookmark_delete
        = Jj_policy.Deny Jj_policy.Insufficient_authority);
  check "P8 policy source digest binds authority denominator and decisions"
    (String.length Jj_policy.source_digest = 64
     && Jj_policy.source_digest
        <> Jj_policy.For_test.source_digest_with_mutation
             Jj_policy.For_test.Drop_authority
     && Jj_policy.source_digest
        <> Jj_policy.For_test.source_digest_with_mutation
             Jj_policy.For_test.Change_decision)

let lease_tests () =
  let current = get (Jj_writer_lease.validate ~now_epoch:100L lease_claim) in
  check "L1 a current validation-only witness permits a subsequent action"
    (Jj_writer_lease.permits_next current
     && not (Jj_writer_lease.requires_full_readback current));
  let changed =
    Jj_writer_lease.observe current ~now_epoch:110L
      ~observed_operation:changed_operation ~external_writer_detected:false
      ~mutation_state:Jj_writer_lease.Not_started
  in
  check "L2 changed head absorbs the lease"
    (not (Jj_writer_lease.permits_next changed));
  let apparently_restored =
    Jj_writer_lease.observe changed ~now_epoch:111L
      ~observed_operation:operation ~external_writer_detected:false
      ~mutation_state:Jj_writer_lease.Not_started
  in
  check "L3 stale lease is absorbing even if the head appears restored"
    (not (Jj_writer_lease.permits_next apparently_restored));
  let external_state =
    Jj_writer_lease.observe current ~now_epoch:110L
      ~observed_operation:operation ~external_writer_detected:true
      ~mutation_state:Jj_writer_lease.Not_started
  in
  check "L4 detected external writer fences later actions"
    (not (Jj_writer_lease.permits_next external_state));
  let expired_started =
    Jj_writer_lease.observe current ~now_epoch:201L
      ~observed_operation:operation ~external_writer_detected:false
      ~mutation_state:Jj_writer_lease.Started
  in
  check "L5 expiry during started mutation forces readback and fences later work"
    (not (Jj_writer_lease.permits_next expired_started)
     && Jj_writer_lease.started_mutation_may_complete expired_started
     && Jj_writer_lease.requires_full_readback expired_started);
  check "L5b only expiry during a started mutation preserves that mutation"
    (not (Jj_writer_lease.started_mutation_may_complete changed)
     && not (Jj_writer_lease.started_mutation_may_complete external_state));
  check "L6 invalid fence and already-expired claim are refused"
    (Result.is_error
       (Jj_writer_lease.validate ~now_epoch:100L
          { lease_claim with fence_epoch = 0L })
     && Result.is_error
          (Jj_writer_lease.validate ~now_epoch:201L lease_claim))

let carrier_tests () =
  let open Mainline_carrier_policy in
  check "C1 private runtime classes default to Exclude"
    (List.for_all
       (fun artifact -> default_disposition artifact = Exclude)
       [ Credential; Authentication_header; Cache; Session; Trust_record;
         Machine_id; Raw_database; Sidecar; Build_tree; Browser_runtime_media;
         Private_agent_state ]);
  check "C2 source and deterministic projections have least-privilege defaults"
    (default_disposition Source = Track
     && default_disposition Deterministic_evolution_projection
        = Sanitize_and_track
     && default_disposition Evidence_digest = Digest_only);
  let source =
    { artifact = Source; requested = Track; size_bytes = 10;
      deterministic = true; allowlisted_projection = false;
      public_identity = "modules/a.ml" }
  in
  let projection =
    { artifact = Deterministic_evolution_projection;
      requested = Sanitize_and_track; size_bytes = 10; deterministic = true;
      allowlisted_projection = true; public_identity = "work/item-1" }
  in
  check "C3 only allowlisted deterministic projections enter source closure"
    (admit projection = Admitted Sanitize_and_track
     && admit { projection with allowlisted_projection = false }
        = Refused Projection_not_allowlisted
     && admit { projection with deterministic = false }
        = Refused Nondeterministic_projection);
  check "C4 denial overrides a requested weaker-looking disposition"
    (admit { source with artifact = Credential; requested = Digest_only }
     = Refused Class_excluded);
  check "C5 source-only closure excludes digest-only and private carriers"
    (match source_only_closure
       [ source; projection;
         { source with artifact = Evidence_digest; requested = Digest_only;
                       public_identity = "evidence/digest-1" } ]
     with
     | Ok admitted -> List.length admitted = 2
     | Error _ -> false);
  check "C6 carrier inputs and closure denominator are bounded"
    (admit { source with size_bytes = max_artifact_bytes + 1 }
     = Refused Artifact_too_large
     && Result.is_error
          (source_only_closure
             (List.init (max_closure_entries + 1) (fun _ -> source))));
  check "C7 redaction is independent of private value"
    (redacted_identity ~public_identity:"credential" ~private_value:"alpha"
     = redacted_identity ~public_identity:"credential" ~private_value:"beta")

let approval_digest character =
  get (Jj_approval.Digest.make (String.make 64 character))

let approval_context () =
  let request_id = get (Jj_id.Request.make "approval-request") in
  let occurrence =
    Jj_campaign_action.release_request ~request_id
    |> Jj_campaign_action.standalone_phase_declarations |> List.hd
  in
  let approval_reference = get (Jj_id.Approval.make "approval-reference") in
  let receipt = get (Jj_id.Receipt.make "release-receipt") in
  let payload =
    get
      (Jj_campaign_action.approval_payload ~approval_reference ~occurrence
         ~phase_context:(Jj_campaign_action.Approval_release receipt)
         ~constraints:
           [ Jj_campaign_action.Authorized_phase; Exact_head;
             Bounded_resources ]
         ~expected_identities:
           [ Jj_campaign_action.Expected_repository repository;
             Expected_workspace workspace; Expected_operation operation ])
  in
  { Jj_approval.payload; plan = approval_digest 'a'; design = approval_digest 'b';
    head = operation; repository; workspace; phase = "release";
    branch = get (Jj_approval.Branch.make "release-branch");
    actor = get (Jj_approval.Actor.make "operator-1");
    host = get (Jj_approval.Host.make "host-1"); expires_at_epoch = 200L;
    journal_position = get (Jj_approval.Journal_position.make 19L);
    occurrence_nonce = Jj_campaign_action.occurrence_nonce occurrence;
    capability_references =
      [ get (Jj_approval.Capability.make "capability-local-mutation");
        get (Jj_approval.Capability.make "capability-readback") ] }

let approval_error expected = function
  | Error actual -> actual = expected
  | Ok _ -> false

let approval_tests () =
  let expected = approval_context () in
  check "A1 exact current approval validates"
    (Result.is_ok
       (Jj_approval.validate ~now_epoch:100L ~expected ~presented:expected));
  check "A2 stale approval is absorbing"
    (approval_error Jj_approval.Expired
       (Jj_approval.validate ~now_epoch:200L ~expected ~presented:expected));
  check "A3 reordered or subset capabilities refuse"
    (approval_error Jj_approval.Capability_references_mismatch
       (Jj_approval.validate ~now_epoch:100L ~expected
          ~presented:{ expected with capability_references =
            List.rev expected.capability_references })
     && approval_error Jj_approval.Capability_references_mismatch
          (Jj_approval.validate ~now_epoch:100L ~expected
             ~presented:{ expected with capability_references =
               [ List.hd expected.capability_references ] }));
  let capability = List.hd expected.capability_references in
  check "A4 duplicate capability references refuse"
    (approval_error Jj_approval.Duplicate_capability_reference
       (Jj_approval.validate ~now_epoch:100L ~expected
          ~presented:{ expected with capability_references =
            [ capability; capability ] }));
  check "A5 phase and branch crossing refuse"
    (approval_error Jj_approval.Phase_mismatch
       (Jj_approval.validate ~now_epoch:100L ~expected
          ~presented:{ expected with phase = "formal" })
     && approval_error Jj_approval.Branch_mismatch
          (Jj_approval.validate ~now_epoch:100L ~expected
             ~presented:{ expected with branch =
               get (Jj_approval.Branch.make "completion-branch") }));
  check "A6 target substitutions refuse"
    (approval_error Jj_approval.Head_mismatch
       (Jj_approval.validate ~now_epoch:100L ~expected
          ~presented:{ expected with head = changed_operation })
     && approval_error Jj_approval.Repository_mismatch
          (Jj_approval.validate ~now_epoch:100L ~expected
             ~presented:{ expected with repository =
               get (Jj_id.Repository.make "repository-other") })
     && approval_error Jj_approval.Workspace_mismatch
          (Jj_approval.validate ~now_epoch:100L ~expected
             ~presented:{ expected with workspace =
               get (Jj_id.Workspace.make "workspace-other") }));
  check "A7 occurrence nonce substitution refuses"
    (approval_error Jj_approval.Occurrence_nonce_mismatch
       (Jj_approval.validate ~now_epoch:100L ~expected
          ~presented:{ expected with occurrence_nonce = "nonce-substitute" }));
  check "A8 plan and design are independently bound"
    (approval_error Jj_approval.Plan_mismatch
       (Jj_approval.validate ~now_epoch:100L ~expected
          ~presented:{ expected with plan = approval_digest 'c' })
     && approval_error Jj_approval.Design_mismatch
          (Jj_approval.validate ~now_epoch:100L ~expected
             ~presented:{ expected with design = approval_digest 'd' }));
  check "A9 actor host expiry and journal position are independently bound"
    (approval_error Jj_approval.Actor_mismatch
       (Jj_approval.validate ~now_epoch:100L ~expected
          ~presented:{ expected with actor =
            get (Jj_approval.Actor.make "operator-2") })
     && approval_error Jj_approval.Host_mismatch
          (Jj_approval.validate ~now_epoch:100L ~expected
             ~presented:{ expected with host =
               get (Jj_approval.Host.make "host-2") })
     && approval_error Jj_approval.Expiry_mismatch
          (Jj_approval.validate ~now_epoch:100L ~expected
             ~presented:{ expected with expires_at_epoch = 201L })
     && approval_error Jj_approval.Journal_position_mismatch
          (Jj_approval.validate ~now_epoch:100L ~expected
             ~presented:{ expected with journal_position =
               get (Jj_approval.Journal_position.make 20L) }));
  check "A10 witness digest is deterministic and non-authorizing"
    (match
       Jj_approval.validate ~now_epoch:100L ~expected ~presented:expected,
       Jj_approval.validate ~now_epoch:101L ~expected ~presented:expected
     with
     | Ok left, Ok right ->
         String.equal (Jj_approval.witness_digest left)
           (Jj_approval.witness_digest right)
     | _ -> false);
  check "A11 approval source digest binds validation fields and digest bound"
    (String.length Jj_approval.source_digest = 64
     && Jj_approval.source_digest
        <> Jj_approval.For_test.source_digest_with_mutation
             Jj_approval.For_test.Change_digest_bound
     && Jj_approval.source_digest
        <> Jj_approval.For_test.source_digest_with_mutation
             Jj_approval.For_test.Drop_validation_field)

let () =
  policy_tests ();
  lease_tests ();
  carrier_tests ();
  approval_tests ();
  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 33 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_policy"
    ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vcs ]);
  exit (Suite_telemetry.exit_code self)
