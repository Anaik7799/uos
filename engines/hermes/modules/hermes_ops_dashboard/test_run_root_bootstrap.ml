open Run_root_bootstrap

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.eprintf "FAILED: %s\n" name
  end

let get = function Ok value -> value | Error _ -> failwith "valid fixture refused"

let clock () =
  get
    (Dependability_clock.observe
       ~max_pair_span_ns:Dependability_clock.maximum_pair_span_ns
       ~lifetime_ns:30_000_000_000L)

let digest character =
  get
    (Dependability_authority_store.Digest.make
       (String.make 64 character))

let with_authority f =
  let registry =
    get (Dependability_sqlite_test_protocol.create ~maximum_live:1)
  in
  let registry, lease =
    get
      (Dependability_sqlite_test_protocol.acquire registry
         Dependability_sqlite_test_protocol.In_memory)
  in
  let location =
    get (Dependability_sqlite_test_protocol.reference registry lease)
  in
  let bootstrap =
    get
      (Dependability_authority_store.prepare_bootstrap
         ~build:(digest 'a') ~root:(digest 'b') ~configuration:(digest 'c')
         ~host:(digest 'd') ~pins:(digest 'e') ~observed_at:(clock ()))
  in
  let lower =
    get
      (Dependability_authority_store.open_first_or_successor
         ~location ~bootstrap)
  in
  let result = f lower in
  ignore (Dependability_sqlite_test_protocol.release registry lease);
  result

let unavailable code = function
  | Error diagnostic ->
      diagnostic_code diagnostic = code
      && diagnostic_coordinate diagnostic = "L2.Task6.RootBootstrap"
      && diagnostic_origin diagnostic = Evidence
  | Ok _ -> false

let () =
  with_authority (fun lower ->
      let root = get (compose_lower_operational_once lower) in
      check "R1 lower root is explicitly distribution-only"
        (lower_bundle_posture root = `Lower_distribution_only
         && production_posture = `Implemented_unavailable);
      let parts = get (split_operational_once root) in
      check "R2 the operational root split is one-shot"
        (match split_operational_once root with
         | Error diagnostic ->
             diagnostic_code diagnostic = "operational-split-conflict"
         | Ok _ -> false);
      check "R3 Task8 view and owner packages fail with exact native blockers"
        (unavailable "target-entry-inventory-current-carrier-unavailable"
           (take_target_read_only_views parts)
         && unavailable "effect-prefix-current-carrier-unavailable"
              (take_effect_read_only_views parts)
         && unavailable "event-prefix-current-carrier-unavailable"
              (take_event_read_only_views parts)
         && unavailable "target-entry-inventory-current-carrier-unavailable"
              (take_target_owner_parts parts)
         && unavailable "abandonment-producer-seal-bundle-unavailable"
              (take_abandonment_authority_part parts)
         && unavailable "dispatch-conditional-decision-capability-unavailable"
              (take_conditional_interpreter_part parts));
      check "R4 exact lower authority roles and peer fences are distributed"
        (Result.is_ok (take_approval_nonce parts)
         && Result.is_ok (take_approval_dormancy parts)
         && Result.is_ok (take_approval_abandonment parts)
         && Result.is_ok (take_writer_fence parts)
         && Result.is_ok (take_production_activation parts)
         && Result.is_ok (take_recovery_port_issuer parts)
         && Result.is_ok (take_recovery_port_lifecycle parts)
         && Result.is_ok (take_lifecycle parts)
         && Result.is_ok (take_writer_open parts)
         && Result.is_ok (take_dispatch_open parts)
         && Result.is_ok (take_vault_open parts)
         && Result.is_ok (take_completion_open parts));
      check "R5 each distributed part is independently one-shot"
        (match take_writer_open parts with
         | Error diagnostic ->
             diagnostic_code diagnostic = "operational-part-already-taken"
         | Ok _ -> false));

  check "R6 absent current inventory and recovery fences fail closed"
    (List.for_all
       (fun (prerequisite, code) ->
          unavailable code (prerequisite_status prerequisite))
       [ (Five_owner_inventory_current_carriers,
          "five-owner-inventory-current-carriers-unavailable");
         (Peer_inventory_fence_bundle,
          "peer-inventory-fence-bundle-unavailable");
         (Authority_recovery_bound_session,
          "authority-recovery-bound-session-unavailable");
         (Recovery_only_terminal_current_carrier,
          "recovery-only-terminal-current-carrier-unavailable") ]);

  check "R7 native recovery inventory carrier seams are constructible types"
    (List.for_all
       (fun prerequisite -> Result.is_ok (prerequisite_status prerequisite))
       [ Dispatch_abandonment_inventory_current_carrier;
         Dispatch_conditional_inventory_current_carrier;
         Authority_approval_inventory_current_carrier ]);

  check "R8 remaining Task8 package prerequisites stay explicitly unavailable"
    (List.for_all
       (fun (prerequisite, code) ->
          unavailable code (prerequisite_status prerequisite))
       [ (Target_entry_inventory_current_carrier,
          "target-entry-inventory-current-carrier-unavailable");
         (Effect_prefix_current_carrier,
          "effect-prefix-current-carrier-unavailable");
         (Event_prefix_current_carrier,
          "event-prefix-current-carrier-unavailable");
         (Mutation_frontier_current_carrier,
          "mutation-frontier-current-carrier-unavailable");
         (Quiescent_or_fenced_current_carrier,
          "quiescent-or-fenced-current-carrier-unavailable");
         (Before_after_current_carrier,
          "before-after-current-carrier-unavailable");
         (Abandonment_producer_seal_bundle,
          "abandonment-producer-seal-bundle-unavailable");
         (Dispatch_abandonment_writer_capability,
          "dispatch-abandonment-writer-capability-unavailable");
         (Dispatch_conditional_decision_capability,
          "dispatch-conditional-decision-capability-unavailable") ]);

  check "R9 source authority kills every lower-bootstrap and Task8 package mutant"
    (String.length source_digest = 64
     && List.for_all
          (fun mutation ->
             source_digest <> For_test.source_digest_with_mutation mutation)
          [ For_test.Duplicate_operational_split;
            Duplicate_part_take;
            Forge_inventory_current;
            Invent_generic_producer_seal;
            Drop_peer_inventory_fence;
            Cast_recovery_phase;
            Promote_without_terminal;
            Add_upper_task8_view;
            Forge_target_read_only_view;
            Forge_effect_read_only_view;
            Forge_event_read_only_view;
            Forge_abandonment_authority_part;
            Forge_conditional_interpreter_part;
            Forge_abandonment_recovery_part;
            Skip_abandonment_recovery_phase;
            Drop_task8_prerequisite_schema;
            Reorder_task8_package_order;
            Flatten_native_recovery_inventory_join;
            Expose_recovery_finish_constructor ]);

  let self =
    Suite_telemetry.observe ~suite:"test_run_root_bootstrap"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
