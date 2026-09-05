let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin incr failed; Printf.printf "FAILED: %s\n" name end

let get = function Ok value -> value | Error _ -> failwith "valid value refused"

let production_manifest ~formal_available =
  let open Jj_runtime_manifest in
  production
    ~target_jj ~target_external_resource ~target_repository_source
    ~target_approval ~target_writer_lease ~target_transition
    ~target_mutation_frontier ~target_network_scope ~target_credential_lease
    ~target_filesystem_materialization ~target_candidate_verification
    ~target_release ~target_completion_receipt
    ~target_formal:(if formal_available then target_formal_available
                    else target_formal_unavailable)
    ~process_jujutsu ~process_candidate
    ~process_formal:(if formal_available then process_formal_available
                    else process_formal_unavailable)
    ~runtime_core ~runtime_operator ~runtime_recovery_port_vault
    ~activation_production ~activation_candidate ~activation_release
    ~activation_formal:(if formal_available then activation_formal_available
                       else activation_formal_unavailable)
    ~store_authority ~store_dispatch ~store_recovery_vault ~store_effect_event
    ~store_completion_receipt

let () =
  let open Run_jj_runtime_registry in
  let unavailable_manifest = get (production_manifest ~formal_available:false) in
  let available_manifest = get (production_manifest ~formal_available:true) in
  let epoch_one = get (successor epoch_zero) in
  check "JR1 production registration remains typed unavailable"
    (production_posture = `Implemented_unavailable
     && List.length registration_prerequisites = 9
     && List.mem Target_registry_current_view registration_prerequisites
     && List.mem Current_attestation_seal_protocol registration_prerequisites);
  check "JR2 fixed production schema is exact and mutation-sensitive"
    (fixed_slot_keys = Jj_runtime_manifest.production_slot_keys
     && fixed_slot_count = Jj_runtime_manifest.slot_count
     && fixed_slot_count = 29
     && String.length slot_schema_digest = 64
     && List.for_all
          (fun mutation ->
            slot_schema_digest
            <> For_test.slot_schema_digest_with_mutation mutation)
          [ For_test.Drop_slot; Reorder_slots; Duplicate_slot ]);
  let registry = create_volatile_registry () in
  let first =
    prepare_generation_schema_once registry ~generation:epoch_zero
      ~manifest:unavailable_manifest
  in
  let replay =
    prepare_generation_schema_once registry ~generation:epoch_zero
      ~manifest:unavailable_manifest
  in
  check "JR3 same generation/manifest replay is stable"
    (match first, replay with
     | Ok (_, first_receipt), Ok (_, replay_receipt) ->
         not first_receipt.prepared_was_replayed
         && replay_receipt.prepared_was_replayed
         && first_receipt.prepared_receipt_digest
            = replay_receipt.prepared_receipt_digest
         && first_receipt.prepared_slot_count = 29
     | _ -> false);
  let skipped_registry = create_volatile_registry () in
  let skipped =
    prepare_generation_schema_once skipped_registry ~generation:epoch_one
      ~manifest:available_manifest
  in
  check "JR4 generations are contiguous and append-only"
    (match skipped with
     | Error { diagnostic_code = Generation_gap; _ } ->
         begin match
           prepare_generation_schema_once skipped_registry
             ~generation:epoch_zero ~manifest:unavailable_manifest,
           prepare_generation_schema_once skipped_registry
             ~generation:epoch_one ~manifest:available_manifest
         with Ok _, Ok _ -> true | _ -> false end
     | _ -> false);
  let conflict =
    prepare_generation_schema_once registry ~generation:epoch_zero
      ~manifest:available_manifest
  in
  let conflict_replay =
    prepare_generation_schema_once registry ~generation:epoch_zero
      ~manifest:unavailable_manifest
  in
  check "JR5 changed same-generation declaration conflicts absorbingly"
    (match conflict, conflict_replay with
     | Error { diagnostic_code = Generation_conflict; _ },
       Error { diagnostic_code = Generation_conflict; _ } -> true
     | _ -> false);
  let readback = read_generation registry ~generation:epoch_zero in
  check "JR6 schema readback exposes conflict without currentness credit"
    (readback.readback_generation_index = 0
     && readback.readback_generation_state = Generation_schema_conflict
     && Option.is_some readback.readback_manifest_digest
     && Option.is_some readback.readback_conflicting_manifest_digest
     && readback.readback_manifest_digest
        <> readback.readback_conflicting_manifest_digest
     && Option.is_some readback.readback_receipt_digest);
  check "JR7 preparation cannot bypass absent current-view/grant prerequisites"
    (match first with
     | Error _ -> false
     | Ok (prepared, _) ->
         begin match register_current_unavailable registry prepared with
         | Error unavailable ->
             unavailable.unavailable_operation = "register-current"
             && unavailable.unavailable_prerequisites
                = registration_prerequisites
             && unavailable.unavailable_rca_origin = Dependency_origin
         | Ok current -> (match current with _ -> false)
         end);
  let source_mutations =
    [ For_test.Drop_generation_order; Permit_overwrite;
      Permit_conflict_recovery; Drop_slot_schema; Permit_test_profile;
      Forge_current; Drop_current_prerequisite ]
  in
  check "JR8 source digest binds replay/conflict/profile/currentness laws"
    (String.length source_digest = 64
     && List.for_all
          (fun mutation ->
            source_digest <> For_test.source_digest_with_mutation mutation)
          source_mutations);
  Printf.printf "run_jj_runtime_registry: %d passed, %d failed\n"
    !passed !failed;
  let telemetry =
    Suite_telemetry.observe ~suite:"test_run_jj_runtime_registry"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit telemetry ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code telemetry)
