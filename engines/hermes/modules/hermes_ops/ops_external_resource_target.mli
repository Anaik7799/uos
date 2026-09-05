(** Fail-closed Task-9 external-resource target foundation.

    Only the pure singleton target/role/effect denominator is constructible.
    The operational owner, registration, and host-current receipt remain
    abstract and unconstructible until root bootstrap supplies a distinct
    external-resource target part and the controlled resource observer can
    produce receipt-bound evidence.  No raw host, path, environment,
    executable, probe, callback, event payload, or effect output crosses this
    interface. *)

type owner
type registration
type host_current_receipt

type unavailable_prerequisite =
  | Target_owner_part_current
  | Controlled_resource_observer
  | Receipt_bound_resource_envelope
  | Event_effect_readback_current

type diagnostic = private {
  prerequisite : unavailable_prerequisite;
  message : string;
  coordinate : string;
  origin : [ `Evidence ];
}

val diagnostic_prerequisite : diagnostic -> unavailable_prerequisite
val diagnostic_message : diagnostic -> string
val diagnostic_coordinate : diagnostic -> string
val diagnostic_origin : diagnostic -> [ `Evidence ]

val runtime_declaration :
  Jj_runtime_manifest.target_external_resource Jj_runtime_manifest.declaration
val target_protocol : Jj_target_protocol.t
val accepted_roles : Jj_action_kind.auxiliary_role list
val accepted_effects : Run_topology.effect_kind list

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]

val create_owner_unavailable : unit -> (owner, diagnostic list) result
(** Exact temporary boundary while the nominal per-target bootstrap part does
    not exist.  It always returns all missing owner/evidence prerequisites and
    constructs no owner, target registry, or Current receipt. *)

val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_topology_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_role
    | Add_role
    | Drop_effect
    | Add_effect
    | Drop_owner_part
    | Drop_resource_observer
    | Drop_receipt_bound_envelope
    | Drop_event_effect_readback
    | Add_raw_host
    | Add_raw_path
    | Add_environment
    | Add_executable
    | Add_probe_callback
    | Promote_unavailable_evidence
    | Add_current_constructor

  val source_digest_with_mutation : source_mutation -> string
end
