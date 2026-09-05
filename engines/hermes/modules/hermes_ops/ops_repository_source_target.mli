(** Fail-closed Task-9 repository-source target foundation.

    Only the pure target, role, effect, A0-operation, and prerequisite
    denominators are constructible.  The production root owner, target
    registration, observation receipts, and A0 Current receipt remain
    abstract and unconstructible until their native owners are Current.  No
    manifest, secret scan, source byte, path, cwd, environment, executable,
    process, network value, callback, caller digest, or event payload crosses
    this interface. *)

type owner
type production_root_authority
type registration
type source_current_receipt
type tree_current_receipt
type object_current_receipt
type a0_operation_readbacks
type a0_current_receipt

type unavailable_prerequisite =
  | Target_owner_part_current
  | Production_root_config_current
  | Controlled_filesystem_observer
  | Dependency_authority_current
  | External_resource_host_current
  | Jujutsu_operation_readbacks_current
  | Event_prefix_current
  | Effect_target_registry_current

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
  Jj_runtime_manifest.target_repository_source Jj_runtime_manifest.declaration
val target_protocol : Jj_target_protocol.t
val accepted_roles : Jj_action_kind.auxiliary_role list
val accepted_effects : Run_topology.effect_kind list

(** Exact ordered A0 Jujutsu-operation readback denominator. *)
val a0_operations : Jj_operation.t list

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]

val create_owner_unavailable : unit -> (owner, diagnostic list) result
(** Exact temporary boundary while the distinct repository-source owner part,
    configured production root, controlled observers, and Current readbacks do
    not exist.  It constructs no owner, authority, registry, or receipt. *)

val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_operation_source
    | Drop_topology_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_source_role
    | Drop_tree_role
    | Drop_object_role
    | Add_role
    | Drop_effect
    | Add_effect
    | Drop_a0_operation
    | Reorder_a0_operations
    | Duplicate_a0_operation
    | Drop_prerequisite
    | Reorder_prerequisites
    | Add_raw_root
    | Add_raw_path
    | Add_source_bytes
    | Add_manifest_input
    | Add_secret_scan_input
    | Add_environment
    | Add_process
    | Add_network
    | Add_probe_callback
    | Accept_caller_digest
    | Promote_disposable_receipt
    | Add_current_constructor

  val source_digest_with_mutation : source_mutation -> string
end
