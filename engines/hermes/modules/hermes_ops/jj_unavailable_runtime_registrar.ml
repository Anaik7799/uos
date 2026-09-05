type registration = |

type unavailable_prerequisite =
  | Manifest_typed_unavailable_formal_posture_current
  | Formal_unavailability_reason_attestation_current
  | Formal_unavailability_source_attestation_current
  | Formal_unavailability_context_attestation_current
  | Durable_generation_owner_current
  | Epoch_zero_prepared_generation_current
  | Epoch_zero_target_formal_grant_current
  | Epoch_zero_process_formal_grant_current
  | Epoch_zero_activation_formal_grant_current
  | Target_formal_unavailable_owner_claim_current
  | Process_formal_unavailable_owner_claim_current
  | Activation_formal_unavailable_owner_claim_current
  | Target_formal_unavailable_attestation_seal_current
  | Process_formal_unavailable_attestation_seal_current
  | Activation_formal_unavailable_attestation_seal_current
  | Target_formal_unavailable_view_registration_current
  | Process_formal_unavailable_view_registration_current
  | Activation_formal_unavailable_view_registration_current
  | Epoch_zero_formal_product_closer_current
  | Epoch_zero_publication_current
  | Epoch_zero_readback_current
  | Stale_epoch_zero_fence_current
  | Epoch_one_concrete_formal_successor_current

type diagnostic = {
  prerequisite : unavailable_prerequisite;
  message : string;
  coordinate : string;
  origin : [ `Evidence ];
}

let diagnostic_prerequisite diagnostic = diagnostic.prerequisite
let diagnostic_message diagnostic = diagnostic.message
let diagnostic_coordinate diagnostic = diagnostic.coordinate
let diagnostic_origin diagnostic = diagnostic.origin

let epoch_zero = Run_jj_runtime_registry.epoch_zero
let target_declaration = Jj_runtime_manifest.target_formal_unavailable
let process_declaration = Jj_runtime_manifest.process_formal_unavailable
let activation_declaration = Jj_runtime_manifest.activation_formal_unavailable

let slot_ids =
  [ "target.formal"; "process.formal"; "activation.formal" ]

let reason_ids =
  [ "target-not-landed"; "process-not-landed"; "activation-not-landed" ]

let binding_ids =
  [ "target.formal->formal-unavailable:target-not-landed";
    "process.formal->formal-unavailable:process-not-landed";
    "activation.formal->formal-unavailable:activation-not-landed" ]

let lifecycle_law_ids =
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

let prerequisites =
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

let prerequisite_id = function
  | Manifest_typed_unavailable_formal_posture_current ->
      "manifest-typed-unavailable-formal-posture-current"
  | Formal_unavailability_reason_attestation_current ->
      "formal-unavailability-reason-attestation-current"
  | Formal_unavailability_source_attestation_current ->
      "formal-unavailability-source-attestation-current"
  | Formal_unavailability_context_attestation_current ->
      "formal-unavailability-context-attestation-current"
  | Durable_generation_owner_current -> "durable-generation-owner-current"
  | Epoch_zero_prepared_generation_current ->
      "epoch-zero-prepared-generation-current"
  | Epoch_zero_target_formal_grant_current ->
      "epoch-zero-target-formal-grant-current"
  | Epoch_zero_process_formal_grant_current ->
      "epoch-zero-process-formal-grant-current"
  | Epoch_zero_activation_formal_grant_current ->
      "epoch-zero-activation-formal-grant-current"
  | Target_formal_unavailable_owner_claim_current ->
      "target-formal-unavailable-owner-claim-current"
  | Process_formal_unavailable_owner_claim_current ->
      "process-formal-unavailable-owner-claim-current"
  | Activation_formal_unavailable_owner_claim_current ->
      "activation-formal-unavailable-owner-claim-current"
  | Target_formal_unavailable_attestation_seal_current ->
      "target-formal-unavailable-attestation-seal-current"
  | Process_formal_unavailable_attestation_seal_current ->
      "process-formal-unavailable-attestation-seal-current"
  | Activation_formal_unavailable_attestation_seal_current ->
      "activation-formal-unavailable-attestation-seal-current"
  | Target_formal_unavailable_view_registration_current ->
      "target-formal-unavailable-view-registration-current"
  | Process_formal_unavailable_view_registration_current ->
      "process-formal-unavailable-view-registration-current"
  | Activation_formal_unavailable_view_registration_current ->
      "activation-formal-unavailable-view-registration-current"
  | Epoch_zero_formal_product_closer_current ->
      "epoch-zero-formal-product-closer-current"
  | Epoch_zero_publication_current -> "epoch-zero-publication-current"
  | Epoch_zero_readback_current -> "epoch-zero-readback-current"
  | Stale_epoch_zero_fence_current -> "stale-epoch-zero-fence-current"
  | Epoch_one_concrete_formal_successor_current ->
      "epoch-one-concrete-formal-successor-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/jj-unavailable-runtime-registrar";
    origin = `Evidence }

let production_posture = `Implemented_unavailable

let register_epoch_zero_unavailable () =
  Error (List.map diagnostic prerequisites)

let prerequisite_ids = List.map prerequisite_id prerequisites

let declaration_id declaration =
  Jj_id.length_frame
    [ Jj_runtime_manifest.declaration_key declaration;
      Jj_runtime_manifest.declaration_digest declaration ]

let source_fields ~epoch ~target ~process ~activation ~slots ~reasons
    ~bindings ~laws ~missing =
  [ ("schema", "jj-unavailable-runtime-registrar-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("runtime-current-protocol-source", Jj_runtime_current_protocol.source_digest);
    ("runtime-registry-source", Run_jj_runtime_registry.source_digest);
    ("epoch-zero", epoch);
    ("target-formal-declaration", target);
    ("process-formal-declaration", process);
    ("activation-formal-declaration", activation);
    ("formal-slot-order", String.concat "," slots);
    ("formal-reason-order", String.concat "," reasons);
    ("formal-binding-order", String.concat "," bindings);
    ("lifecycle-law-order", String.concat "," laws);
    ("missing-prerequisites", String.concat "," missing);
    ("epoch-nonzero-registration", "refused");
    ("epoch-zero-concrete-target", "refused");
    ("epoch-zero-concrete-process", "refused");
    ("epoch-zero-concrete-activation", "refused");
    ("mixed-formal-posture", "refused");
    ("reason-requirement", "exact-attestation-required");
    ("source-requirement", "exact-attestation-required");
    ("context-requirement", "exact-current-attestation-required");
    ("target-grant-requirement", "same-slot-generation-current-required");
    ("process-grant-requirement", "same-slot-generation-current-required");
    ("activation-grant-requirement", "same-slot-generation-current-required");
    ("target-cross-slot-grant", "refused");
    ("process-cross-slot-grant", "refused");
    ("activation-cross-slot-grant", "refused");
    ("target-claim-requirement", "exact-current-required");
    ("process-claim-requirement", "exact-current-required");
    ("activation-claim-requirement", "exact-current-required");
    ("target-seal-requirement", "exact-grant-plus-claim-required");
    ("process-seal-requirement", "exact-grant-plus-claim-required");
    ("activation-seal-requirement", "exact-grant-plus-claim-required");
    ("cross-generation-use", "refused");
    ("grant-reuse", "refused-consumed-once");
    ("changed-row-replay", "absorbing-conflict");
    ("epoch-zero-overwrite", "refused-append-only");
    ("formal-product-partial", "refused");
    ("publish-before-close", "refused");
    ("generation-rollback", "refused");
    ("stale-epoch-zero-use", "refused");
    ("epoch-one-unavailable-formal", "refused");
    ("current-executable-registration", "absent");
    ("activation-capability-projection", "absent");
    ("target-current-projection", "absent");
    ("process-current-projection", "absent");
    ("activation-current-projection", "absent");
    ("generic-registrar", "absent");
    ("caller-digest", "rejected");
    ("callback", "absent");
    ("registrar-promotion", "implemented-unavailable");
    ("registry-projection", "absent");
    ("generation-grant-projection", "absent");
    ("current-attestation-projection", "absent");
    ("database-projection", "absent");
    ("store-projection", "absent");
    ("repository-mutation", "absent");
    ("process-effect", "absent");
    ("registration-completion-credit", "forbidden");
    ("registration-parity-credit", "forbidden");
    ("production-posture", "implemented-unavailable") ]

let digest fields =
  fields
  |> List.map (fun (name, value) -> Jj_id.length_frame [ name; value ])
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let canonical_fields () =
  source_fields
    ~epoch:(string_of_int (Run_jj_runtime_registry.generation_index epoch_zero))
    ~target:(declaration_id target_declaration)
    ~process:(declaration_id process_declaration)
    ~activation:(declaration_id activation_declaration)
    ~slots:slot_ids ~reasons:reason_ids ~bindings:binding_ids
    ~laws:lifecycle_law_ids ~missing:prerequisite_ids

let source_digest = canonical_fields () |> digest

module For_test = struct
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_runtime_current_protocol_source
    | Drop_runtime_registry_source
    | Drop_target_declaration
    | Substitute_target_available
    | Drop_process_declaration
    | Substitute_process_available
    | Drop_activation_declaration
    | Substitute_activation_available
    | Drop_slot
    | Reorder_slots
    | Duplicate_slot
    | Drop_reason
    | Reorder_reasons
    | Substitute_reason
    | Drop_binding
    | Reorder_bindings
    | Duplicate_binding
    | Cross_bind_reason
    | Drop_lifecycle_law
    | Reorder_lifecycle_laws
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_epoch_nonzero
    | Permit_concrete_target_epoch_zero
    | Permit_concrete_process_epoch_zero
    | Permit_concrete_activation_epoch_zero
    | Permit_mixed_formal_posture
    | Permit_missing_reason
    | Permit_missing_source
    | Permit_missing_context
    | Permit_target_without_grant
    | Permit_process_without_grant
    | Permit_activation_without_grant
    | Permit_target_cross_slot_grant
    | Permit_process_cross_slot_grant
    | Permit_activation_cross_slot_grant
    | Permit_target_without_claim
    | Permit_process_without_claim
    | Permit_activation_without_claim
    | Permit_target_without_seal
    | Permit_process_without_seal
    | Permit_activation_without_seal
    | Permit_cross_generation
    | Permit_grant_reuse
    | Permit_same_row_changed_replay
    | Permit_overwrite_epoch_zero
    | Permit_partial_formal_product
    | Permit_publish_before_close
    | Permit_rollback_generation
    | Permit_stale_epoch_zero_use
    | Permit_unavailable_epoch_one
    | Register_current_executable
    | Expose_activation_capability
    | Expose_target_current
    | Expose_process_current
    | Expose_activation_current
    | Add_generic_registrar
    | Accept_caller_digest
    | Add_callback
    | Promote_unavailable_registrar
    | Expose_registry
    | Expose_generation_grant
    | Expose_current_attestation
    | Expose_database
    | Expose_store
    | Add_repository_mutation
    | Add_process_effect
    | Promote_registration_to_completion_credit
    | Promote_registration_to_parity_credit

  let drop_field name fields =
    List.filter
      (fun (candidate, _) -> not (String.equal candidate name))
      fields

  let replace_field name value fields =
    List.map
      (fun ((candidate, _) as field) ->
        if String.equal candidate name then (candidate, value) else field)
      fields

  let source_digest_with_mutation mutation =
    let fields = canonical_fields () in
    let replace name value = replace_field name value fields in
    let mutated_fields =
      match mutation with
      | Drop_runtime_manifest_source ->
          drop_field "runtime-manifest-source" fields
      | Drop_runtime_current_protocol_source ->
          drop_field "runtime-current-protocol-source" fields
      | Drop_runtime_registry_source ->
          drop_field "runtime-registry-source" fields
      | Drop_target_declaration ->
          drop_field "target-formal-declaration" fields
      | Substitute_target_available ->
          replace "target-formal-declaration"
            (declaration_id Jj_runtime_manifest.target_formal_available)
      | Drop_process_declaration ->
          drop_field "process-formal-declaration" fields
      | Substitute_process_available ->
          replace "process-formal-declaration"
            (declaration_id Jj_runtime_manifest.process_formal_available)
      | Drop_activation_declaration ->
          drop_field "activation-formal-declaration" fields
      | Substitute_activation_available ->
          replace "activation-formal-declaration"
            (declaration_id Jj_runtime_manifest.activation_formal_available)
      | Drop_slot ->
          replace "formal-slot-order" (String.concat "," (List.tl slot_ids))
      | Reorder_slots ->
          replace "formal-slot-order" (String.concat "," (List.rev slot_ids))
      | Duplicate_slot ->
          replace "formal-slot-order"
            (String.concat "," ("target.formal" :: slot_ids))
      | Drop_reason ->
          replace "formal-reason-order"
            (String.concat "," (List.tl reason_ids))
      | Reorder_reasons ->
          replace "formal-reason-order"
            (String.concat "," (List.rev reason_ids))
      | Substitute_reason ->
          replace "formal-reason-order"
            (String.concat ","
               ("target-available" :: List.tl reason_ids))
      | Drop_binding ->
          replace "formal-binding-order"
            (String.concat "," (List.tl binding_ids))
      | Reorder_bindings ->
          replace "formal-binding-order"
            (String.concat "," (List.rev binding_ids))
      | Duplicate_binding ->
          replace "formal-binding-order"
            (String.concat "," (List.hd binding_ids :: binding_ids))
      | Cross_bind_reason ->
          replace "formal-binding-order"
            (String.concat ","
               ("target.formal->formal-unavailable:process-not-landed"
                :: List.tl binding_ids))
      | Drop_lifecycle_law ->
          replace "lifecycle-law-order"
            (String.concat "," (List.tl lifecycle_law_ids))
      | Reorder_lifecycle_laws ->
          replace "lifecycle-law-order"
            (String.concat "," (List.rev lifecycle_law_ids))
      | Drop_prerequisite ->
          replace "missing-prerequisites"
            (String.concat "," (List.tl prerequisite_ids))
      | Reorder_prerequisites ->
          replace "missing-prerequisites"
            (String.concat "," (List.rev prerequisite_ids))
      | Duplicate_prerequisite ->
          replace "missing-prerequisites"
            (String.concat ","
               ("manifest-typed-unavailable-formal-posture-current"
                :: prerequisite_ids))
      | Substitute_prerequisite ->
          replace "missing-prerequisites"
            (String.concat ","
               ("manifest-formal-posture-substituted"
                :: List.tl prerequisite_ids))
      | Permit_epoch_nonzero -> replace "epoch-nonzero-registration" "permitted"
      | Permit_concrete_target_epoch_zero ->
          replace "epoch-zero-concrete-target" "permitted"
      | Permit_concrete_process_epoch_zero ->
          replace "epoch-zero-concrete-process" "permitted"
      | Permit_concrete_activation_epoch_zero ->
          replace "epoch-zero-concrete-activation" "permitted"
      | Permit_mixed_formal_posture ->
          replace "mixed-formal-posture" "permitted"
      | Permit_missing_reason -> replace "reason-requirement" "optional"
      | Permit_missing_source -> replace "source-requirement" "optional"
      | Permit_missing_context -> replace "context-requirement" "optional"
      | Permit_target_without_grant ->
          replace "target-grant-requirement" "optional"
      | Permit_process_without_grant ->
          replace "process-grant-requirement" "optional"
      | Permit_activation_without_grant ->
          replace "activation-grant-requirement" "optional"
      | Permit_target_cross_slot_grant ->
          replace "target-cross-slot-grant" "permitted"
      | Permit_process_cross_slot_grant ->
          replace "process-cross-slot-grant" "permitted"
      | Permit_activation_cross_slot_grant ->
          replace "activation-cross-slot-grant" "permitted"
      | Permit_target_without_claim ->
          replace "target-claim-requirement" "optional"
      | Permit_process_without_claim ->
          replace "process-claim-requirement" "optional"
      | Permit_activation_without_claim ->
          replace "activation-claim-requirement" "optional"
      | Permit_target_without_seal ->
          replace "target-seal-requirement" "optional"
      | Permit_process_without_seal ->
          replace "process-seal-requirement" "optional"
      | Permit_activation_without_seal ->
          replace "activation-seal-requirement" "optional"
      | Permit_cross_generation -> replace "cross-generation-use" "permitted"
      | Permit_grant_reuse -> replace "grant-reuse" "permitted"
      | Permit_same_row_changed_replay ->
          replace "changed-row-replay" "stable-replay"
      | Permit_overwrite_epoch_zero ->
          replace "epoch-zero-overwrite" "permitted"
      | Permit_partial_formal_product ->
          replace "formal-product-partial" "permitted"
      | Permit_publish_before_close ->
          replace "publish-before-close" "permitted"
      | Permit_rollback_generation ->
          replace "generation-rollback" "permitted"
      | Permit_stale_epoch_zero_use ->
          replace "stale-epoch-zero-use" "permitted"
      | Permit_unavailable_epoch_one ->
          replace "epoch-one-unavailable-formal" "permitted"
      | Register_current_executable ->
          replace "current-executable-registration" "present"
      | Expose_activation_capability ->
          replace "activation-capability-projection" "exposed"
      | Expose_target_current ->
          replace "target-current-projection" "exposed"
      | Expose_process_current ->
          replace "process-current-projection" "exposed"
      | Expose_activation_current ->
          replace "activation-current-projection" "exposed"
      | Add_generic_registrar -> replace "generic-registrar" "present"
      | Accept_caller_digest -> replace "caller-digest" "accepted"
      | Add_callback -> replace "callback" "present"
      | Promote_unavailable_registrar ->
          replace "registrar-promotion" "available"
      | Expose_registry -> replace "registry-projection" "exposed"
      | Expose_generation_grant ->
          replace "generation-grant-projection" "exposed"
      | Expose_current_attestation ->
          replace "current-attestation-projection" "exposed"
      | Expose_database -> replace "database-projection" "exposed"
      | Expose_store -> replace "store-projection" "exposed"
      | Add_repository_mutation -> replace "repository-mutation" "present"
      | Add_process_effect -> replace "process-effect" "present"
      | Promote_registration_to_completion_credit ->
          replace "registration-completion-credit" "permitted"
      | Promote_registration_to_parity_credit ->
          replace "registration-parity-credit" "permitted"
    in
    digest mutated_fields
end
