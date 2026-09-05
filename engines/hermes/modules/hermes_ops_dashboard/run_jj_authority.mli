(** Bridge-neutral static authority for the controlled-Jujutsu cone.

    This module composes only pure/source, topology, FPP, MBSE, static formal,
    configuration, root-bootstrap and lower protocol declarations.  It imports
    no bridge, operator, concrete target, or aggregate Ops implementation. *)

type constituent_kind =
  | Jj_source_authority
  | Run_topology
  | Run_fpp_authority
  | Run_mbse
  | Run_formal_relation
  | Module_intent
  | Ops_config_declaration
  | Run_root_bootstrap
  | Dependability_filesystem_protocol
  | Dependability_clock_protocol
  | Dependability_process_protocol
  | Dependability_approval_protocol
  | Dependability_writer_lease_protocol
  | Jj_target_protocol
  | Jj_dependency_schema
  | Run_dependency_authority
  | Run_swarm_preparation
  | Jj_runtime_manifest_schema
  | Jj_runtime_current_protocol
  | Run_jj_runtime_registry
  | Jj_recovery_transition_port_protocol
  | Jj_completion_store_protocol

val constituent_kinds : constituent_kind list
val constituent_kind_id : constituent_kind -> string

type constituent = private {
  kind : constituent_kind;
  id : string;
  digest : string;
}

val constituents : constituent list
val constituent_count : int
val constituent_id : constituent -> string
val constituent_digest : constituent -> string

type diagnostic_code =
  | Jj_source_incomplete
  | Constituent_denominator_mismatch
  | Constituent_duplicate
  | Constituent_digest_invalid
  | Boundary_dependency_forbidden
  | Current_prerequisites_unavailable

type diagnostic = private {
  code : diagnostic_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
}

val diagnostic_code : diagnostic -> diagnostic_code
val diagnostic_message : diagnostic -> string
val diagnostic_coordinate : diagnostic -> Ops_capability.coordinate
val diagnostic_origin : diagnostic -> Ops_capability.rca_origin

val boundary_laws : string list
val source_digest : unit -> (string, diagnostic list) result
(** Length-frames every exact ordered constituent.  There is no caller row or
    digest input, and any missing/duplicate/reordered/invalid row refuses. *)

type static_sources_current
type current_receipt

type current_prerequisite =
  | Static_constituent_current of constituent_kind
  | Observed_runtime_manifest_current

val current_prerequisites : current_prerequisite list
val current_prerequisite_id : current_prerequisite -> string
val current_prerequisite_status :
  current_prerequisite -> (unit, diagnostic) result

val current_receipt :
  static:static_sources_current ->
  runtime_manifest:Run_jj_runtime_registry.jj_runtime_manifest_current ->
  (current_receipt, diagnostic) result
(** Typed unavailable until the runtime registry can construct its opaque
    current manifest and an exact-head owner can construct all static source
    currentness.  No digest string can substitute for either receipt. *)

val production_posture : [ `Implemented_unavailable ]

module For_test : sig
  type mutation =
    | Drop_constituent of constituent_kind
    | Reorder_constituents
    | Duplicate_constituent
    | Mismatch_constituent_digest
    | Add_bridge_dependency
    | Add_operator_dependency
    | Add_concrete_target_dependency
    | Add_aggregate_ops_dependency
    | Forge_current_receipt
    | Drop_runtime_manifest_current
    | Drop_static_sources_current
    | Substitute_digest_string

  val mutation_refuses : mutation -> bool
  val source_digest_with_mutation :
    mutation -> (string, diagnostic list) result
end
