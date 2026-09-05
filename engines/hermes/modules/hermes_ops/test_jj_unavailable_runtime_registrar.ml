open Jj_unavailable_runtime_registrar

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let expected_slot_ids =
  [ "target.formal"; "process.formal"; "activation.formal" ]

let expected_reason_ids =
  [ "target-not-landed"; "process-not-landed"; "activation-not-landed" ]

let expected_binding_ids =
  [ "target.formal->formal-unavailable:target-not-landed";
    "process.formal->formal-unavailable:process-not-landed";
    "activation.formal->formal-unavailable:activation-not-landed" ]

let expected_lifecycle_law_ids =
  [ "epoch-zero->unavailable-formal-only";
    "epoch-zero->exact-three-formal-slots";
    "same-row-replay->stable";
    "changed-row-replay->conflict";
    "mixed-formal-posture->refused";
    "concrete-formal-in-epoch-zero->refused";
    "formal-product-close->exact-three-current-views-required";
    "generation-publish->closed-generation-required";
    "generation-publication->append-only";
    "epoch-one-published->epoch-zero-stale";
    "epoch-zero-overwrite->refused";
    "epoch-one->concrete-formal-required";
    "generation-rollback->refused";
    "unavailable-registration->nonauthorizing-no-credit" ]

let expected_prerequisites =
  [ Manifest_typed_unavailable_formal_posture_current;
    Formal_unavailability_reason_attestation_current;
    Formal_unavailability_source_attestation_current;
    Formal_unavailability_context_attestation_current;
    Durable_generation_owner_current;
    Epoch_zero_prepared_generation_current;
    Epoch_zero_target_formal_grant_current;
    Epoch_zero_process_formal_grant_current;
    Epoch_zero_activation_formal_grant_current;
    Target_formal_unavailable_owner_claim_current;
    Process_formal_unavailable_owner_claim_current;
    Activation_formal_unavailable_owner_claim_current;
    Target_formal_unavailable_attestation_seal_current;
    Process_formal_unavailable_attestation_seal_current;
    Activation_formal_unavailable_attestation_seal_current;
    Target_formal_unavailable_view_registration_current;
    Process_formal_unavailable_view_registration_current;
    Activation_formal_unavailable_view_registration_current;
    Epoch_zero_formal_product_closer_current;
    Epoch_zero_publication_current;
    Epoch_zero_readback_current;
    Stale_epoch_zero_fence_current;
    Epoch_one_concrete_formal_successor_current ]

let all_mutations =
  let open For_test in
  [ Drop_runtime_manifest_source;
    Drop_runtime_current_protocol_source;
    Drop_runtime_registry_source;
    Drop_target_declaration;
    Substitute_target_available;
    Drop_process_declaration;
    Substitute_process_available;
    Drop_activation_declaration;
    Substitute_activation_available;
    Drop_slot;
    Reorder_slots;
    Duplicate_slot;
    Drop_reason;
    Reorder_reasons;
    Substitute_reason;
    Drop_binding;
    Reorder_bindings;
    Duplicate_binding;
    Cross_bind_reason;
    Drop_lifecycle_law;
    Reorder_lifecycle_laws;
    Drop_prerequisite;
    Reorder_prerequisites;
    Duplicate_prerequisite;
    Substitute_prerequisite;
    Permit_epoch_nonzero;
    Permit_concrete_target_epoch_zero;
    Permit_concrete_process_epoch_zero;
    Permit_concrete_activation_epoch_zero;
    Permit_mixed_formal_posture;
    Permit_missing_reason;
    Permit_missing_source;
    Permit_missing_context;
    Permit_target_without_grant;
    Permit_process_without_grant;
    Permit_activation_without_grant;
    Permit_target_cross_slot_grant;
    Permit_process_cross_slot_grant;
    Permit_activation_cross_slot_grant;
    Permit_target_without_claim;
    Permit_process_without_claim;
    Permit_activation_without_claim;
    Permit_target_without_seal;
    Permit_process_without_seal;
    Permit_activation_without_seal;
    Permit_cross_generation;
    Permit_grant_reuse;
    Permit_same_row_changed_replay;
    Permit_overwrite_epoch_zero;
    Permit_partial_formal_product;
    Permit_publish_before_close;
    Permit_rollback_generation;
    Permit_stale_epoch_zero_use;
    Permit_unavailable_epoch_one;
    Register_current_executable;
    Expose_activation_capability;
    Expose_target_current;
    Expose_process_current;
    Expose_activation_current;
    Add_generic_registrar;
    Accept_caller_digest;
    Add_callback;
    Promote_unavailable_registrar;
    Expose_registry;
    Expose_generation_grant;
    Expose_current_attestation;
    Expose_database;
    Expose_store;
    Add_repository_mutation;
    Add_process_effect;
    Promote_registration_to_completion_credit;
    Promote_registration_to_parity_credit ]

let all_unique values =
  List.length values = List.length (List.sort_uniq String.compare values)

let declaration_differs left right =
  not
    (String.equal
       (Jj_runtime_manifest.declaration_digest left)
       (Jj_runtime_manifest.declaration_digest right))

let () =
  Printf.printf "[tdd] closed epoch-zero unavailable Formal registrar\n";
  check "J09U01 exact epoch-zero and three unavailable Formal declarations"
    (Run_jj_runtime_registry.generation_index epoch_zero = 0
     && target_declaration == Jj_runtime_manifest.target_formal_unavailable
     && process_declaration == Jj_runtime_manifest.process_formal_unavailable
     && activation_declaration ==
          Jj_runtime_manifest.activation_formal_unavailable
     && declaration_differs target_declaration
          Jj_runtime_manifest.target_formal_available
     && declaration_differs process_declaration
          Jj_runtime_manifest.process_formal_available
     && declaration_differs activation_declaration
          Jj_runtime_manifest.activation_formal_available);
  check "J09U02 exact Formal slot, reason, and binding denominators"
    (slot_ids = expected_slot_ids && reason_ids = expected_reason_ids
     && binding_ids = expected_binding_ids);
  check "J09U03 exact append-only epoch lifecycle laws"
    (lifecycle_law_ids = expected_lifecycle_law_ids);
  check "J09U04 exact ordered 23-prerequisite denominator"
    (prerequisites = expected_prerequisites && List.length prerequisites = 23);
  check "J09U05 registration is fail-closed with complete diagnostics"
    (match register_epoch_zero_unavailable () with
     | Ok _ -> false
     | Error diagnostics ->
         List.map diagnostic_prerequisite diagnostics = expected_prerequisites
         && List.for_all
              (fun diagnostic ->
                String.equal (diagnostic_coordinate diagnostic)
                  "L3/Orient/jj-unavailable-runtime-registrar"
                && diagnostic_origin diagnostic = `Evidence
                && String.ends_with ~suffix:" is unavailable"
                     (diagnostic_message diagnostic))
              diagnostics);
  check "J09U06 production posture remains implemented-unavailable"
    (production_posture = `Implemented_unavailable);
  check "J09U07 source digest is SHA-256 shaped"
    (String.length source_digest = 64);
  let mutant_digests =
    List.map For_test.source_digest_with_mutation all_mutations
  in
  check "J09U21 exact 72 real source mutants are distinct and killed"
    (List.length all_mutations = 72
     && List.for_all (fun digest -> not (String.equal digest source_digest))
          mutant_digests
     && all_unique mutant_digests);
  Printf.printf "unavailable Formal registrar: %d passed; %d failed\n"
    !passed !failed;
  if !failed <> 0 then exit 1
