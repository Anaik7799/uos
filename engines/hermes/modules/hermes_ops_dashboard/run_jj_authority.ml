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

let constituent_kinds =
  [ Jj_source_authority; Run_topology; Run_fpp_authority; Run_mbse;
    Run_formal_relation; Module_intent; Ops_config_declaration;
    Run_root_bootstrap; Dependability_filesystem_protocol;
    Dependability_clock_protocol; Dependability_process_protocol;
    Dependability_approval_protocol; Dependability_writer_lease_protocol;
    Jj_target_protocol; Jj_dependency_schema; Run_dependency_authority;
    Run_swarm_preparation; Jj_runtime_manifest_schema;
    Jj_runtime_current_protocol; Run_jj_runtime_registry;
    Jj_recovery_transition_port_protocol; Jj_completion_store_protocol ]

let constituent_kind_id = function
  | Jj_source_authority -> "jj-source-authority"
  | Run_topology -> "run-topology"
  | Run_fpp_authority -> "run-fpp-authority"
  | Run_mbse -> "run-mbse"
  | Run_formal_relation -> "run-formal-relation"
  | Module_intent -> "module-intent"
  | Ops_config_declaration -> "ops-config-declaration"
  | Run_root_bootstrap -> "run-root-bootstrap"
  | Dependability_filesystem_protocol ->
      "dependability-filesystem-protocol"
  | Dependability_clock_protocol -> "dependability-clock-protocol"
  | Dependability_process_protocol -> "dependability-process-protocol"
  | Dependability_approval_protocol -> "dependability-approval-protocol"
  | Dependability_writer_lease_protocol ->
      "dependability-writer-lease-protocol"
  | Jj_target_protocol -> "jj-target-protocol"
  | Jj_dependency_schema -> "jj-dependency-schema"
  | Run_dependency_authority -> "run-dependency-authority"
  | Run_swarm_preparation -> "run-swarm-preparation"
  | Jj_runtime_manifest_schema -> "jj-runtime-manifest-schema"
  | Jj_runtime_current_protocol -> "jj-runtime-current-protocol"
  | Run_jj_runtime_registry -> "run-jj-runtime-registry"
  | Jj_recovery_transition_port_protocol ->
      "jj-recovery-transition-port-protocol"
  | Jj_completion_store_protocol -> "jj-completion-store-protocol"

type constituent = {
  kind : constituent_kind;
  id : string;
  digest : string;
}

type diagnostic_code =
  | Jj_source_incomplete
  | Constituent_denominator_mismatch
  | Constituent_duplicate
  | Constituent_digest_invalid
  | Boundary_dependency_forbidden
  | Current_prerequisites_unavailable

type diagnostic = {
  code : diagnostic_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
}

let diagnostic_code diagnostic = diagnostic.code
let diagnostic_message diagnostic = diagnostic.message
let diagnostic_coordinate diagnostic = diagnostic.coordinate
let diagnostic_origin diagnostic = diagnostic.rca_origin

let diagnostic code message rca_origin =
  { code; message;
    coordinate =
      { Ops_capability.level = Ops_capability.L5;
        phase = Ops_capability.Orient };
    rca_origin }

let jj_source_result = Jj_source_authority.source_digest ()

let jj_source_digest =
  match jj_source_result with
  | Ok value -> value
  | Error _ -> ""

let mbse_digest =
  let manifest : Run_mbse.manifest = Run_mbse.manifest in
  manifest.Run_mbse.source_digest

let digest_for_kind = function
  | Jj_source_authority -> jj_source_digest
  | Run_topology -> Run_topology.source_digest
  | Run_fpp_authority -> Run_fpp_authority.source_digest
  | Run_mbse -> mbse_digest
  | Run_formal_relation -> Run_formal_relation.campaign_digest
  | Module_intent -> Module_intent.source_digest
  | Ops_config_declaration -> Ops_config.declaration_digest
  | Run_root_bootstrap -> Run_root_bootstrap.source_digest
  | Dependability_filesystem_protocol -> Dependability_filesystem.source_digest
  | Dependability_clock_protocol -> Dependability_clock.source_digest
  | Dependability_process_protocol ->
      Dependability_process_protocol.source_digest
  | Dependability_approval_protocol -> Dependability_approval.source_digest
  | Dependability_writer_lease_protocol ->
      Dependability_writer_lease.source_digest
  | Jj_target_protocol -> Jj_target_protocol.source_digest
  | Jj_dependency_schema -> Jj_dependency_schema.source_digest
  | Run_dependency_authority -> Run_dependency_authority.source_digest
  | Run_swarm_preparation -> Run_swarm_preparation.source_digest
  | Jj_runtime_manifest_schema -> Jj_runtime_manifest.source_digest
  | Jj_runtime_current_protocol -> Jj_runtime_current_protocol.source_digest
  | Run_jj_runtime_registry -> Run_jj_runtime_registry.source_digest
  | Jj_recovery_transition_port_protocol ->
      Jj_recovery_transition_port_protocol.source_digest
  | Jj_completion_store_protocol -> Jj_completion_store_protocol.source_digest

let constituents =
  List.map
    (fun kind ->
      { kind; id = constituent_kind_id kind; digest = digest_for_kind kind })
    constituent_kinds

let constituent_count = List.length constituents
let constituent_id constituent = constituent.id
let constituent_digest constituent = constituent.digest

let boundary_laws =
  [ "bridge-neutral"; "operator-neutral"; "target-declaration-only";
    "no-aggregate-ops"; "no-current-forgery";
    "no-digest-string-substitution" ]

let current_laws =
  [ "runtime-manifest-current-required";
    "all-static-sources-current-required";
    "no-current-from-digest-string" ]

type snapshot = {
  snapshot_constituents : constituent list;
  snapshot_boundary_laws : string list;
  snapshot_current_laws : string list;
}

let canonical_snapshot =
  { snapshot_constituents = constituents;
    snapshot_boundary_laws = boundary_laws;
    snapshot_current_laws = current_laws }

let is_lower_hex = function
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false

let valid_digest value =
  String.length value = 64 && String.for_all is_lower_hex value

let validate_snapshot snapshot =
  let ids = List.map constituent_id snapshot.snapshot_constituents in
  let expected_ids = List.map constituent_kind_id constituent_kinds in
  let errors = ref [] in
  let add code message =
    errors :=
      diagnostic code message Ops_capability.Specification :: !errors
  in
  begin match jj_source_result with
  | Ok _ -> ()
  | Error _ ->
      add Jj_source_incomplete
        "the pure Jujutsu source authority has unavailable constituents"
  end;
  if List.length ids <> List.length (List.sort_uniq String.compare ids) then
    add Constituent_duplicate "the authority constituent identity duplicates";
  if ids <> expected_ids then
    add Constituent_denominator_mismatch
      "the authority constituent denominator or order differs";
  List.iter
    (fun constituent ->
      if constituent.id <> constituent_kind_id constituent.kind
         || not (valid_digest constituent.digest)
      then
        add Constituent_digest_invalid
          ("invalid source digest for " ^ constituent.id))
    snapshot.snapshot_constituents;
  if snapshot.snapshot_boundary_laws <> boundary_laws then
    add Boundary_dependency_forbidden
      "a bridge/operator/concrete-target/aggregate-Ops dependency was added";
  if snapshot.snapshot_current_laws <> current_laws then
    add Current_prerequisites_unavailable
      "currentness was weakened or replaced by a digest string";
  List.rev !errors

let sha256 value = Digestif.SHA256.(to_hex (digest_string value))

let digest_snapshot snapshot =
  let rows =
    List.map
      (fun constituent ->
        Jj_id.length_frame [ constituent.id; constituent.digest ])
      snapshot.snapshot_constituents
  in
  Jj_id.length_frame
    [ "run-jj-authority-v1"; Jj_id.length_frame rows;
      Jj_id.length_frame snapshot.snapshot_boundary_laws;
      Jj_id.length_frame snapshot.snapshot_current_laws ]
  |> sha256

let compose snapshot =
  match validate_snapshot snapshot with
  | [] -> Ok (digest_snapshot snapshot)
  | errors -> Error errors

let source_digest () = compose canonical_snapshot

type static_sources_current = unit
type current_receipt = unit

type current_prerequisite =
  | Static_constituent_current of constituent_kind
  | Observed_runtime_manifest_current

let current_prerequisites =
  List.map (fun kind -> Static_constituent_current kind) constituent_kinds
  @ [ Observed_runtime_manifest_current ]

let current_prerequisite_id = function
  | Static_constituent_current kind ->
      "static-current:" ^ constituent_kind_id kind
  | Observed_runtime_manifest_current ->
      "observed-runtime-manifest-current"

let unavailable_current prerequisite =
  Error
    (diagnostic Current_prerequisites_unavailable
       (current_prerequisite_id prerequisite ^ " is not constructible")
       Ops_capability.Specification)

let current_prerequisite_status = unavailable_current

let current_receipt ~static:_ ~runtime_manifest:_ =
  Error
    (diagnostic Current_prerequisites_unavailable
       "runtime manifest and all static source current receipts are unavailable"
       Ops_capability.Specification)

let production_posture = `Implemented_unavailable

module For_test = struct
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

  let remove_kind kind rows =
    List.filter (fun constituent -> constituent.kind <> kind) rows

  let mutate mutation =
    match mutation with
    | Drop_constituent kind ->
        { canonical_snapshot with
          snapshot_constituents = remove_kind kind constituents }
    | Reorder_constituents ->
        { canonical_snapshot with
          snapshot_constituents = List.rev constituents }
    | Duplicate_constituent ->
        { canonical_snapshot with
          snapshot_constituents =
            (match constituents with
             | [] -> []
             | first :: _ -> first :: constituents) }
    | Mismatch_constituent_digest ->
        { canonical_snapshot with
          snapshot_constituents =
            (match constituents with
             | [] -> []
             | first :: rest ->
                 { first with digest = "not-a-source-digest" } :: rest) }
    | Add_bridge_dependency ->
        { canonical_snapshot with
          snapshot_boundary_laws = "import:run-swarm-bridge" :: boundary_laws }
    | Add_operator_dependency ->
        { canonical_snapshot with
          snapshot_boundary_laws = "import:run-operator-authority" :: boundary_laws }
    | Add_concrete_target_dependency ->
        { canonical_snapshot with
          snapshot_boundary_laws = "import:concrete-target" :: boundary_laws }
    | Add_aggregate_ops_dependency ->
        { canonical_snapshot with
          snapshot_boundary_laws = "import:aggregate-ops" :: boundary_laws }
    | Forge_current_receipt ->
        { canonical_snapshot with
          snapshot_current_laws = "forge-current" :: current_laws }
    | Drop_runtime_manifest_current ->
        { canonical_snapshot with
          snapshot_current_laws =
            List.filter
              (fun law -> law <> "runtime-manifest-current-required")
              current_laws }
    | Drop_static_sources_current ->
        { canonical_snapshot with
          snapshot_current_laws =
            List.filter
              (fun law -> law <> "all-static-sources-current-required")
              current_laws }
    | Substitute_digest_string ->
        { canonical_snapshot with
          snapshot_current_laws = "digest-string-is-current" :: current_laws }

  let mutation_refuses mutation =
    validate_snapshot (mutate mutation) <> []

  let source_digest_with_mutation mutation = compose (mutate mutation)
end
