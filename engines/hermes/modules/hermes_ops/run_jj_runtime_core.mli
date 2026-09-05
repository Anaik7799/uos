(** Pure, nonauthorizing Task-9 runtime profile validation.

    This module validates only closed request subsets and exports the nominal
    runtime-core manifest declaration.  It exposes no executable, argv, cwd,
    environment, path, process registry, Current receipt, activation, target,
    bridge, or dispatch operation. *)

type diagnostic_code =
  | Process_schema_denominator_mismatch
  | Profile_subset_mismatch
  | Live_process_source_unfrozen
  | Process_registry_current_unavailable
  | Recovery_only_current_unavailable
  | Release_terminal_cleanup_denominator_unavailable

type diagnostic = private {
  code : diagnostic_code;
  message : string;
  coordinate : string;
  origin : [ `Specification | `Evidence | `Control ];
}

val diagnostic_code : diagnostic -> diagnostic_code
val diagnostic_message : diagnostic -> string
val diagnostic_coordinate : diagnostic -> string
val diagnostic_origin :
  diagnostic -> [ `Specification | `Evidence | `Control ]
val string_of_diagnostic_code : diagnostic_code -> string

type live_prerequisite =
  | Frozen_process_source_authority
  | Process_registry_current_carrier
  | Recovery_only_current_receipt
  | Release_terminal_cleanup_denominator

val live_prerequisite_status :
  live_prerequisite -> (unit, diagnostic) result
val live_preparation_posture : [ `Implemented_unavailable ]

type production_profile
type candidate_profile
type formal_profile
type recovery_only_profile
type release_profile

type _ profile =
  | Production : production_profile profile
  | Candidate : candidate_profile profile
  | Formal : formal_profile profile
  | Recovery_only : recovery_only_profile profile
  | Release : release_profile profile

type packed_profile = Profile : 'profile profile -> packed_profile
val profiles : packed_profile list
val profile_id : 'profile profile -> string

type 'profile validated_subset

val validate_subset :
  'profile profile -> ('profile validated_subset, diagnostic) result
(** Production, candidate, and formal subsets are pure and nonauthorizing.
    Recovery_only refuses without its typed current Jj receipt.  Release
    refuses until its exact terminal-cleanup constructors are frozen. *)

val subset_profile_id : 'profile validated_subset -> string
val subset_count : 'profile validated_subset -> int
val subset_digest : 'profile validated_subset -> string

val runtime_core_declaration :
  Jj_runtime_manifest.runtime_core Jj_runtime_manifest.declaration
val source_digest : string

module For_test : sig
  val process_request_ids : string list
  val process_request_slots : (string * string) list
  val manifest_process_slot_ids : string list
  val process_schema_digest : string

  type source_mutation =
    | Drop_jujutsu_request
    | Drop_candidate_request
    | Drop_formal_request
    | Duplicate_request
    | Swap_process_slot
    | Drop_manifest_process_slot
    | Add_argv_field
    | Add_executable_field
    | Add_cwd_field
    | Add_environment_field
    | Add_path_field
    | Permit_live_preparation
    | Invent_process_registry_current
    | Guess_release_terminal_cleanup
    | Add_current_constructor
    | Add_activation_constructor

  val source_digest_with_mutation : source_mutation -> string
end
