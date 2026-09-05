(** Bridge-neutral, nonauthorizing runtime-manifest registry foundation.

    This module owns only the fixed production slot schema and a bounded
    volatile append/replay model.  It imports no bridge, operator, execution,
    or Jujutsu authority and cannot mint a current runtime receipt. *)

type diagnostic_code =
  | Generation_overflow
  | Generation_gap
  | Generation_stale
  | Generation_conflict

type rca_origin = Implementation_origin | Dependency_origin

type diagnostic = private {
  diagnostic_code : diagnostic_code;
  diagnostic_message : string;
  diagnostic_coordinate : string;
  diagnostic_rca_origin : rca_origin;
}

type manifest_generation

val epoch_zero : manifest_generation
val successor : manifest_generation -> (manifest_generation, diagnostic) result
val generation_index : manifest_generation -> int

type registry
type prepared_generation

type prepare_receipt = private {
  prepared_generation_index : int;
  prepared_manifest_digest : string;
  prepared_slot_count : int;
  prepared_slot_schema_digest : string;
  prepared_receipt_digest : string;
  prepared_was_replayed : bool;
}

val create_volatile_registry : unit -> registry

val prepare_generation_schema_once :
  registry -> generation:manifest_generation ->
  manifest:Jj_runtime_manifest.production ->
  (prepared_generation * prepare_receipt, diagnostic) result
(** Nonauthorizing schema preparation only.  Same-row replay is stable;
    skipped generations and changed same-generation manifests fail closed. *)

type generation_state =
  | Generation_absent
  | Generation_schema_prepared
  | Generation_schema_conflict

type generation_readback = private {
  readback_generation_index : int;
  readback_generation_state : generation_state;
  readback_manifest_digest : string option;
  readback_conflicting_manifest_digest : string option;
  readback_receipt_digest : string option;
}

val read_generation :
  registry -> generation:manifest_generation -> generation_readback

val fixed_slot_keys : string list
val fixed_slot_count : int
val slot_schema_digest : string

type registration_prerequisite =
  | Durable_generation_owner
  | Target_registry_current_view
  | Process_registry_current_view
  | Runtime_current_views
  | Activation_current_views
  | Store_current_views
  | Slot_generation_grant_protocol
  | Current_attestation_seal_protocol
  | Manifest_formal_posture_projection

val registration_prerequisites : registration_prerequisite list
val registration_prerequisite_id : registration_prerequisite -> string

type unavailable = private {
  unavailable_operation : string;
  unavailable_prerequisites : registration_prerequisite list;
  unavailable_coordinate : string;
  unavailable_rca_origin : rca_origin;
}

type jj_runtime_manifest_current

val register_current_unavailable :
  registry -> prepared_generation ->
  (jj_runtime_manifest_current, unavailable) result

val production_posture : [ `Implemented_unavailable ]
val source_digest : string

module For_test : sig
  type slot_schema_mutation = Drop_slot | Reorder_slots | Duplicate_slot
  val slot_schema_digest_with_mutation : slot_schema_mutation -> string

  type source_mutation =
    | Drop_generation_order
    | Permit_overwrite
    | Permit_conflict_recovery
    | Drop_slot_schema
    | Permit_test_profile
    | Forge_current
    | Drop_current_prerequisite

  val source_digest_with_mutation : source_mutation -> string
end
