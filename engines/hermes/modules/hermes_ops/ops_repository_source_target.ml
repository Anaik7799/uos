type owner = |
type production_root_authority = |
type registration = |
type source_current_receipt = |
type tree_current_receipt = |
type object_current_receipt = |
type a0_operation_readbacks = |
type a0_current_receipt = |

type unavailable_prerequisite =
  | Target_owner_part_current
  | Production_root_config_current
  | Controlled_filesystem_observer
  | Dependency_authority_current
  | External_resource_host_current
  | Jujutsu_operation_readbacks_current
  | Event_prefix_current
  | Effect_target_registry_current

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

let runtime_declaration = Jj_runtime_manifest.target_repository_source
let target_protocol = Jj_target_protocol.Repository_source
let accepted_roles =
  [ Jj_action_kind.Observe_repository_source; Jj_action_kind.Observe_tree;
    Jj_action_kind.Observe_object ]
let accepted_effects = [ Run_topology.Repository_source_observation ]

let a0_operations =
  [ Jj_operation.Operation_head; Jj_operation.Status_at_operation;
    Jj_operation.Resolve_list_at_operation;
    Jj_operation.Operation_log_at_operation;
    Jj_operation.Revision_log_at_operation;
    Jj_operation.Bookmark_list_at_operation;
    Jj_operation.Workspace_list_at_operation;
    Jj_operation.Remote_list_at_operation;
    Jj_operation.Diff_summary_at_operation;
    Jj_operation.Diff_stat_at_operation;
    Jj_operation.Diff_patch_at_operation ]

let prerequisites =
  [ Target_owner_part_current; Production_root_config_current;
    Controlled_filesystem_observer; Dependency_authority_current;
    External_resource_host_current; Jujutsu_operation_readbacks_current;
    Event_prefix_current; Effect_target_registry_current ]

let production_posture = `Implemented_unavailable

let prerequisite_id = function
  | Target_owner_part_current -> "target-owner-part-current"
  | Production_root_config_current -> "production-root-config-current"
  | Controlled_filesystem_observer -> "controlled-filesystem-observer"
  | Dependency_authority_current -> "dependency-authority-current"
  | External_resource_host_current -> "external-resource-host-current"
  | Jujutsu_operation_readbacks_current ->
      "jujutsu-operation-readbacks-current"
  | Event_prefix_current -> "event-prefix-current"
  | Effect_target_registry_current -> "effect-target-registry-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/ops-repository-source-target";
    origin = `Evidence }

let create_owner_unavailable () = Error (List.map diagnostic prerequisites)

let role_ids = List.map Jj_action_kind.auxiliary_role_key accepted_roles
let effect_ids = List.map Run_topology.effect_kind_id accepted_effects
let operation_id operation =
  let declaration : Jj_operation.declaration =
    Jj_operation.declaration operation
  in
  declaration.Jj_operation.key

let operation_ids = List.map operation_id a0_operations
let prerequisite_ids = List.map prerequisite_id prerequisites

let source_fields ~roles ~effects ~operations ~missing =
  [ ("schema", "ops-repository-source-target-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("target-protocol-source", Jj_target_protocol.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("operation-source", Jj_operation.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("runtime-declaration-key",
     Jj_runtime_manifest.declaration_key runtime_declaration);
    ("runtime-declaration-digest",
     Jj_runtime_manifest.declaration_digest runtime_declaration);
    ("target-protocol", Jj_target_protocol.key target_protocol);
    ("accepted-roles", String.concat "," roles);
    ("accepted-effects", String.concat "," effects);
    ("a0-operation-order", String.concat "," operations);
    ("missing-prerequisites", String.concat "," missing);
    ("manifest-input", "absent:owner-constructed");
    ("secret-scan-input", "absent:owner-constructed");
    ("raw-root", "absent");
    ("raw-path", "absent");
    ("source-bytes", "absent");
    ("environment", "absent");
    ("process", "absent");
    ("network", "absent");
    ("probe-callback", "absent");
    ("caller-digest", "rejected");
    ("disposable-receipt", "never-promoted");
    ("current-constructor", "absent");
    ("production-posture", "implemented-unavailable") ]

let digest fields =
  fields
  |> List.map (fun (name, value) -> Jj_id.length_frame [ name; value ])
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let source_digest =
  source_fields ~roles:role_ids ~effects:effect_ids
    ~operations:operation_ids ~missing:prerequisite_ids
  |> digest

module For_test = struct
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

  let drop_first = function [] -> [] | _ :: tail -> tail

  let replace_field name value fields =
    List.map
      (fun ((candidate, _) as field) ->
        if String.equal candidate name then (candidate, value) else field)
      fields

  let source_digest_with_mutation mutation =
    let roles, effects, operations, missing, mutate_fields =
      match mutation with
      | Drop_runtime_manifest_source ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "runtime-manifest-source" "")
      | Drop_target_protocol_source ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "target-protocol-source" "")
      | Drop_action_kind_source ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "action-kind-source" "")
      | Drop_operation_source ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "operation-source" "")
      | Drop_topology_source ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "topology-source" "")
      | Drop_runtime_declaration ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           fun fields ->
             fields
             |> replace_field "runtime-declaration-key" ""
             |> replace_field "runtime-declaration-digest" "")
      | Substitute_runtime_declaration ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           fun fields ->
             fields
             |> replace_field "runtime-declaration-key"
                  (Jj_runtime_manifest.declaration_key
                     Jj_runtime_manifest.target_external_resource)
             |> replace_field "runtime-declaration-digest"
                  (Jj_runtime_manifest.declaration_digest
                     Jj_runtime_manifest.target_external_resource))
      | Drop_target_protocol ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "target-protocol" "")
      | Drop_source_role ->
          (List.filter
             (fun role -> not (String.equal role "observe-repository-source"))
             role_ids,
           effect_ids, operation_ids, prerequisite_ids, Fun.id)
      | Drop_tree_role ->
          (List.filter (fun role -> not (String.equal role "observe-tree"))
             role_ids,
           effect_ids, operation_ids, prerequisite_ids, Fun.id)
      | Drop_object_role ->
          (List.filter (fun role -> not (String.equal role "observe-object"))
             role_ids,
           effect_ids, operation_ids, prerequisite_ids, Fun.id)
      | Add_role ->
          (role_ids @ [ "observe-external-resource" ], effect_ids,
           operation_ids, prerequisite_ids, Fun.id)
      | Drop_effect ->
          (role_ids, [], operation_ids, prerequisite_ids, Fun.id)
      | Add_effect ->
          (role_ids, effect_ids @ [ "jujutsu-observation" ], operation_ids,
           prerequisite_ids, Fun.id)
      | Drop_a0_operation ->
          (role_ids, effect_ids, drop_first operation_ids, prerequisite_ids,
           Fun.id)
      | Reorder_a0_operations ->
          (role_ids, effect_ids, List.rev operation_ids, prerequisite_ids,
           Fun.id)
      | Duplicate_a0_operation ->
          let operations =
            match operation_ids with
            | [] -> []
            | first :: _ -> first :: operation_ids
          in
          (role_ids, effect_ids, operations, prerequisite_ids, Fun.id)
      | Drop_prerequisite ->
          (role_ids, effect_ids, operation_ids, drop_first prerequisite_ids,
           Fun.id)
      | Reorder_prerequisites ->
          (role_ids, effect_ids, operation_ids, List.rev prerequisite_ids,
           Fun.id)
      | Add_raw_root ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "raw-root" "public-string")
      | Add_raw_path ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "raw-path" "public-string")
      | Add_source_bytes ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "source-bytes" "public-bytes")
      | Add_manifest_input ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "manifest-input" "caller-supplied")
      | Add_secret_scan_input ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "secret-scan-input" "caller-supplied")
      | Add_environment ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "environment" "public-map")
      | Add_process ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "process" "public-handle")
      | Add_network ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "network" "public-handle")
      | Add_probe_callback ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "probe-callback" "public-function")
      | Accept_caller_digest ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "caller-digest" "accepted")
      | Promote_disposable_receipt ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "disposable-receipt" "promoted-current")
      | Add_current_constructor ->
          (role_ids, effect_ids, operation_ids, prerequisite_ids,
           replace_field "current-constructor" "public")
    in
    source_fields ~roles ~effects ~operations ~missing
    |> mutate_fields |> digest
end
