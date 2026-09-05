type effect_kind = Run_topology.effect_kind =
  | Dependability_process_attempt
  | Verification_suite_execution
  | Durable_artifact_publication
  | External_resource_observation
  | Repository_source_observation
  | Approval_nonce_consumption
  | Writer_lease_transition
  | Production_activation_transition
  | Network_scope_transition
  | Credential_lease_transition
  | Controlled_filesystem_materialization
  | Candidate_tree_verification
  | Jujutsu_observation
  | Jujutsu_local_mutation
  | Jujutsu_history_rewrite
  | Jujutsu_recovery
  | Jujutsu_remote_synchronization
  | Jujutsu_remote_publish
  | Formal_oracle_execution

type diagnostic_code =
  | Invalid_effect_request
  | Invalid_effect_target
  | Effect_kind_not_accepted
  | Invalid_idempotency_key
  | Effect_key_conflict
  | Effect_target_failure
  | Effect_receipt_invalid
  | Effect_ledger_unavailable
  | Effect_interpreter_closed
  | Invalid_target_registry_schema
  | Target_registry_schema_conflict

type hazard =
  | Effect_request_invalid
  | Effect_target_invalid
  | Effect_kind_unauthorized
  | Effect_identity_conflict
  | Effect_outcome_uncertain
  | Effect_ledger_corrupt

type diagnostic = {
  code : diagnostic_code;
  bytes : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard : hazard;
}

type request = {
  effect_kind : effect_kind;
  request_bytes : string;
  request_digest : string;
}

type disposition = First_applied | Replayed

type evidence_disposition = Evidence_succeeded | Evidence_unavailable

type redacted_evidence = {
  evidence_receipt_id : string;
  evidence_digest : string;
  evidence_disposition : evidence_disposition;
}

type target_receipt = {
  idempotency_key : string;
  request_digest : string;
  target_authority_digest : string;
  disposition : disposition;
  evidence : redacted_evidence;
  receipt_digest : string;
}

type target = {
  target_id : string;
  authority_digest : string;
  accepted_kinds : effect_kind list;
  target_digest : string;
  target_apply_once :
    idempotency_key:string -> request -> (target_receipt, string) result;
  target_query :
    idempotency_key:string -> (target_receipt option, string) result;
}

type target_registry = {
  activity : Run_topology.admitted_activity;
  activity_digest : string;
  topology_authority_digest : string;
  target : target;
}

type target_authority_status = Concrete_target_authority_unavailable

type action_target_binding = {
  binding_activity_id : string;
  binding_action_id : string;
  binding_target_component_id : string;
  binding_effect_kind : effect_kind;
  binding_target_authority_digest : string option;
  binding_target_authority_status : target_authority_status;
  binding_dependency_schema_id : string;
}

type jj_target_registry_schema = {
  schema_bindings : action_target_binding list;
  schema_digest_value : string;
}

type prepared_target_schema = {
  prepared_target_schema_digest : string;
  prepared_target_binding_count : int;
  prepared_target_receipt_digest : string;
}

type target_registry_cell_state =
  | Target_registry_uninitialized
  | Target_registry_prepared of prepared_target_schema
  | Target_registry_conflict

type jj_target_registry = target_registry_cell_state Atomic.t

type target_schema_receipt = {
  target_schema_digest : string;
  target_schema_binding_count : int;
  target_schema_receipt_digest : string;
  target_schema_was_replayed : bool;
}

type target_schema_state =
  | Target_schema_uninitialized
  | Target_schema_prepared
  | Target_schema_conflict

type target_registry_prerequisite =
  | Concrete_target_authority_digests
  | Task9_target_current_views
  | Request_bound_phase_action_registry
  | Conditional_action_control_registry

type target_registry_unavailable = {
  target_registry_unavailable_operation : string;
  target_registry_missing_prerequisites : target_registry_prerequisite list;
}

type jj_target_registry_current = |

type pending = {
  idempotency_key : string;
  request_digest : string;
  target_authority_digest : string;
}

type indeterminate = {
  idempotency_key : string;
  request_digest : string;
  target_authority_digest : string;
  diagnostic_bytes : string;
  no_replay : bool;
}

type state =
  | Pending of pending
  | Applied of target_receipt
  | Indeterminate_effect of indeterminate

type key_conflict = {
  idempotency_key : string;
  persisted_digest : string;
  observed_digest : string;
  diagnostic : diagnostic;
}

type error =
  | Invalid_request of diagnostic
  | Key_reused_with_different_request of key_conflict
  | Target_unavailable of diagnostic
  | Indeterminate of state * diagnostic
  | Ledger_failure of diagnostic

type receipt = target_receipt

type admitted_registry_identity = {
  activity_digest : string;
  topology_authority_digest : string;
  target_digest : string;
  effect_kinds_digest : string;
}

type interpreter = {
  database : Dependability_sqlite.owned_database;
  target : target;
  admitted_identity : admitted_registry_identity option;
  coordinate : Ops_capability.coordinate;
  mutex : Mutex.t;
  mutable closed : bool;
}

let string_of_effect_kind = Run_topology.effect_kind_id

let string_of_diagnostic_code = function
  | Invalid_effect_request -> "invalid-effect-request"
  | Invalid_effect_target -> "invalid-effect-target"
  | Effect_kind_not_accepted -> "effect-kind-not-accepted"
  | Invalid_idempotency_key -> "invalid-idempotency-key"
  | Effect_key_conflict -> "effect-key-conflict"
  | Effect_target_failure -> "effect-target-failure"
  | Effect_receipt_invalid -> "effect-receipt-invalid"
  | Effect_ledger_unavailable -> "effect-ledger-unavailable"
  | Effect_interpreter_closed -> "effect-interpreter-closed"
  | Invalid_target_registry_schema -> "invalid-target-registry-schema"
  | Target_registry_schema_conflict -> "target-registry-schema-conflict"

let string_of_hazard = function
  | Effect_request_invalid -> "HZ-EFFECT-REQUEST-01"
  | Effect_target_invalid -> "HZ-EFFECT-TARGET-01"
  | Effect_kind_unauthorized -> "HZ-EFFECT-AUTHZ-01"
  | Effect_identity_conflict -> "HZ-EFFECT-IDENTITY-01"
  | Effect_outcome_uncertain -> "HZ-EFFECT-INDETERMINATE-01"
  | Effect_ledger_corrupt -> "HZ-EFFECT-LEDGER-01"

let default_coordinate =
  { Ops_capability.level = Ops_capability.L3; phase = Ops_capability.Act }

let diagnostic ?(coordinate = default_coordinate) ~code ~bytes ~rca_origin
    ~hazard () : diagnostic =
  { code; bytes; coordinate; rca_origin; hazard }

let sha256 bytes =
  bytes |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let frame value = Printf.sprintf "%d:%s" (String.length value) value

let canonical fields = fields |> List.map frame |> String.concat ""

let digest_fields fields = sha256 (canonical fields)

let valid_digest value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let valid_identifier value =
  let trimmed = String.trim value in
  String.equal value trimmed && not (String.equal value "")
  && String.for_all
       (function '\000' .. '\032' | '\127' -> false | _ -> true)
       value

let make_request ~effect_kind ~request_bytes =
  if String.equal request_bytes "" then
    Error
      (diagnostic ~code:Invalid_effect_request
         ~bytes:"request_bytes must be nonempty"
         ~rca_origin:Ops_capability.Control ~hazard:Effect_request_invalid ())
  else
    let request_digest =
      digest_fields
        [ "run-effect-request-v1"; string_of_effect_kind effect_kind;
          request_bytes ]
    in
    Ok ({ effect_kind; request_bytes; request_digest } : request)

let string_of_disposition = function
  | First_applied -> "first-applied"
  | Replayed -> "replayed"

let string_of_evidence_disposition = function
  | Evidence_succeeded -> "succeeded"
  | Evidence_unavailable -> "unavailable"

let make_redacted_evidence ~receipt_id ~evidence_digest ~disposition =
  if not (valid_identifier receipt_id) || String.length receipt_id > 256 then
    Error
      (diagnostic ~code:Effect_receipt_invalid
         ~bytes:"evidence receipt id must be 1..256 trimmed control-free bytes"
         ~rca_origin:Ops_capability.Control ~hazard:Effect_request_invalid ())
  else if not (valid_digest evidence_digest) then
    Error
      (diagnostic ~code:Effect_receipt_invalid
         ~bytes:"evidence digest must be lowercase SHA-256"
         ~rca_origin:Ops_capability.Control ~hazard:Effect_request_invalid ())
  else
    Ok { evidence_receipt_id = receipt_id; evidence_digest;
         evidence_disposition = disposition }

let evidence_receipt_id evidence = evidence.evidence_receipt_id
let evidence_digest evidence = evidence.evidence_digest
let evidence_disposition evidence = evidence.evidence_disposition
let target_receipt_evidence receipt = receipt.evidence

let redacted_evidence_json evidence =
  `Assoc
    [ ("disposition",
       `String (string_of_evidence_disposition evidence.evidence_disposition));
      ("evidenceDigest", `String evidence.evidence_digest);
      ("receiptId", `String evidence.evidence_receipt_id);
      ("schema", `String "redacted-evidence-v1") ]

let evidence_projection evidence =
  redacted_evidence_json evidence |> Yojson.Safe.to_string

let evidence_of_projection bytes =
  try
    let json = Yojson.Safe.from_string bytes in
    let open Yojson.Safe.Util in
    let schema = json |> member "schema" |> to_string in
    let receipt_id = json |> member "receiptId" |> to_string in
    let evidence_digest = json |> member "evidenceDigest" |> to_string in
    let disposition =
      match json |> member "disposition" |> to_string with
      | "succeeded" -> Ok Evidence_succeeded
      | "unavailable" -> Ok Evidence_unavailable
      | _ -> Error "redacted evidence disposition is unknown"
    in
    if schema <> "redacted-evidence-v1" then
      Error "redacted evidence schema differs"
    else if not (valid_identifier receipt_id) || String.length receipt_id > 256
    then Error "redacted evidence receipt id is invalid"
    else if not (valid_digest evidence_digest) then
      Error "redacted evidence digest is invalid"
    else
      match disposition with
      | Error _ as error -> error
      | Ok evidence_disposition ->
          Ok { evidence_receipt_id = receipt_id; evidence_digest;
               evidence_disposition }
  with Yojson.Json_error _ | Yojson.Safe.Util.Type_error _ ->
    Error "redacted evidence JSON is malformed"

let target_receipt_digest ~idempotency_key ~request_digest
    ~target_authority_digest ~disposition ~evidence =
  digest_fields
    [ "run-effect-target-receipt-v1"; idempotency_key; request_digest;
      target_authority_digest; string_of_disposition disposition;
      evidence.evidence_receipt_id; evidence.evidence_digest;
      string_of_evidence_disposition evidence.evidence_disposition ]

let make_target_receipt ~idempotency_key ~(request : request)
    ~target_authority_digest
    ~disposition ~(evidence : redacted_evidence) =
  if not (valid_identifier idempotency_key) then
    Error
      (diagnostic ~code:Invalid_idempotency_key
         ~bytes:"idempotency_key must be nonempty, trimmed, and control-free"
         ~rca_origin:Ops_capability.Control ~hazard:Effect_request_invalid ())
  else if not (valid_digest target_authority_digest) then
    Error
      (diagnostic ~code:Invalid_effect_target
         ~bytes:"target_authority_digest must be lowercase SHA-256"
         ~rca_origin:Ops_capability.Control ~hazard:Effect_target_invalid ())
  else
    let receipt_digest =
      target_receipt_digest ~idempotency_key
        ~request_digest:request.request_digest ~target_authority_digest
        ~disposition ~evidence
    in
    Ok
      ({ idempotency_key; request_digest = request.request_digest;
        target_authority_digest; disposition; evidence; receipt_digest }
        : target_receipt)

let target_digest_of ~target_id ~authority_digest ~accepted_kinds =
  digest_fields
    ([ "run-effect-target-v1"; target_id; authority_digest ]
     @ List.map string_of_effect_kind (List.sort_uniq compare accepted_kinds))

let make_target ~target_id ~authority_digest ~accepted_kinds ~apply_once ~query =
  let canonical_kinds = List.sort_uniq compare accepted_kinds in
  if not (valid_identifier target_id) then
    Error
      (diagnostic ~code:Invalid_effect_target
         ~bytes:"target_id must be nonempty, trimmed, and control-free"
         ~rca_origin:Ops_capability.Control ~hazard:Effect_target_invalid ())
  else if not (valid_digest authority_digest) then
    Error
      (diagnostic ~code:Invalid_effect_target
         ~bytes:"authority_digest must be lowercase SHA-256"
         ~rca_origin:Ops_capability.Control ~hazard:Effect_target_invalid ())
  else if accepted_kinds = [] then
    Error
      (diagnostic ~code:Invalid_effect_target
         ~bytes:"accepted_kinds must be nonempty"
         ~rca_origin:Ops_capability.Control ~hazard:Effect_target_invalid ())
  else if List.length canonical_kinds <> List.length accepted_kinds then
    Error
      (diagnostic ~code:Invalid_effect_target
         ~bytes:"accepted_kinds contains duplicates"
         ~rca_origin:Ops_capability.Control ~hazard:Effect_target_invalid ())
  else
    let target_digest =
      target_digest_of ~target_id ~authority_digest
        ~accepted_kinds:canonical_kinds in
    Ok
      { target_id; authority_digest; accepted_kinds = canonical_kinds;
        target_digest; target_apply_once = apply_once; target_query = query }

let expected_target_authority_digest ~activity ~target_id ~accepted_kinds =
  digest_fields
    ([ "run-effect-admitted-target-v2";
       Run_topology.admitted_activity_authority_digest activity;
       Run_topology.admitted_activity_digest activity; target_id ]
     @ List.map string_of_effect_kind accepted_kinds)

let invalid_target bytes =
  diagnostic ~code:Invalid_effect_target ~bytes
    ~rca_origin:Ops_capability.Control ~hazard:Effect_target_invalid ()

let activity_identity_gaps activity =
  let declaration = Run_topology.admitted_declaration activity in
  let gaps = ref [] in
  if Run_topology.admitted_activity_authority_digest activity
     <> Run_topology.source_digest
  then gaps := "admitted activity topology authority digest is stale" :: !gaps;
  if Run_topology.admitted_activity_digest activity
     <> Run_topology.activity_digest_of declaration
  then gaps := "admitted activity digest does not bind its declaration" :: !gaps;
  List.rev !gaps

let register_target ~activity ~target_id ~authority_digest ~accepted_kinds
    ~apply_once ~query : (target_registry, diagnostic list) result =
  let declaration = Run_topology.admitted_declaration activity in
  let gaps = ref (activity_identity_gaps activity) in
  if target_id <> declaration.target_component_id then
    gaps := "target id differs from the admitted topology activity" :: !gaps;
  if accepted_kinds <> declaration.effect_kinds then
    gaps := "accepted effect kinds differ from the admitted topology activity"
      :: !gaps;
  let expected_authority_digest =
    expected_target_authority_digest ~activity ~target_id
      ~accepted_kinds in
  if authority_digest <> expected_authority_digest then
    gaps := "target authority digest does not bind the admitted activity"
      :: !gaps;
  let gaps = List.rev !gaps in
  if gaps <> [] then Error (List.map invalid_target gaps)
  else
    match
      make_target ~target_id ~authority_digest ~accepted_kinds ~apply_once
        ~query
    with
    | Error issue -> Error [ issue ]
    | Ok target ->
        Ok
          { activity;
            activity_digest = Run_topology.admitted_activity_digest activity;
            topology_authority_digest =
              Run_topology.admitted_activity_authority_digest activity;
            target }

let binding_dependency_schema_id activity_id
    (action : Run_topology.declarative_action) =
  digest_fields
    ([ "jj-action-dependency-schema-v1"; activity_id; action.stable_id;
       Run_topology.action_work_id action.work;
       action.required_capability_id ]
     @ action.dependency_ids @ action.context_requirement_ids)

let canonical_action_target_bindings () =
  Run_topology.task7a_declaration_activities
  |> List.concat_map (fun (activity : Run_topology.declarative_activity) ->
       Run_topology.declarative_activity_actions activity
       |> List.map (fun (action : Run_topology.declarative_action) ->
            { binding_activity_id = activity.stable_id;
              binding_action_id = action.stable_id;
              binding_target_component_id = action.target_component_id;
              binding_effect_kind = action.effect_kind;
              binding_target_authority_digest = None;
              binding_target_authority_status =
                Concrete_target_authority_unavailable;
              binding_dependency_schema_id =
                binding_dependency_schema_id activity.stable_id action }))

let target_authority_status_id = function
  | Concrete_target_authority_unavailable ->
      "concrete-target-authority-unavailable"

let action_target_binding_fields binding =
  [ binding.binding_activity_id; binding.binding_action_id;
    binding.binding_target_component_id;
    string_of_effect_kind binding.binding_effect_kind;
    Option.value binding.binding_target_authority_digest
      ~default:"target-authority-digest:unavailable";
    target_authority_status_id binding.binding_target_authority_status;
    binding.binding_dependency_schema_id ]

let target_registry_schema_digest_of bindings =
  digest_fields
    ([ "jj-action-target-registry-schema-v1";
       Run_topology.task7a_declaration_digest;
       Run_topology.task7a_static_template_digest;
       Run_topology.task7a_action_work_class_digest ]
     @ List.concat_map action_target_binding_fields bindings)

let schema_of_bindings schema_bindings =
  { schema_bindings;
    schema_digest_value = target_registry_schema_digest_of schema_bindings }

let canonical_jj_target_registry_schema () =
  schema_of_bindings (canonical_action_target_bindings ())

let jj_target_registry_bindings schema = schema.schema_bindings
let jj_target_registry_schema_digest schema = schema.schema_digest_value

let invalid_registry_schema bytes =
  diagnostic ~code:Invalid_target_registry_schema ~bytes
    ~rca_origin:Ops_capability.Control ~hazard:Effect_target_invalid ()

let validate_jj_target_registry_schema_exact schema =
  let expected = canonical_jj_target_registry_schema () in
  let gaps = ref [] in
  let add gap = gaps := gap :: !gaps in
  if schema.schema_bindings <> expected.schema_bindings then
    add "action-to-target membership/order differs from Task-7A topology";
  if schema.schema_digest_value <> target_registry_schema_digest_of schema.schema_bindings
  then add "action-to-target schema digest does not bind its rows";
  let identities =
    List.map
      (fun binding ->
        binding.binding_activity_id ^ "\000" ^ binding.binding_action_id)
      schema.schema_bindings
  in
  if List.length identities
     <> List.length (List.sort_uniq String.compare identities)
  then add "action-to-target identities duplicate";
  if List.exists
       (fun binding ->
         binding.binding_target_authority_digest <> None
         || binding.binding_target_authority_status
            <> Concrete_target_authority_unavailable)
       schema.schema_bindings
  then add "schema forges unavailable Task-9 target authority";
  match List.rev !gaps with
  | [] -> Ok ()
  | gaps -> Error (List.map invalid_registry_schema gaps)

let create_jj_target_registry () = Atomic.make Target_registry_uninitialized

let target_schema_receipt prepared replayed =
  { target_schema_digest = prepared.prepared_target_schema_digest;
    target_schema_binding_count = prepared.prepared_target_binding_count;
    target_schema_receipt_digest = prepared.prepared_target_receipt_digest;
    target_schema_was_replayed = replayed }

let target_registry_conflict () =
  [ diagnostic ~code:Target_registry_schema_conflict
      ~bytes:"action-to-target registry schema is conflict-fenced"
      ~rca_origin:Ops_capability.Control ~hazard:Effect_identity_conflict () ]

let rec prepare_jj_target_registry_schema registry schema =
  let before = Atomic.get registry in
  match before with
  | Target_registry_conflict -> Error (target_registry_conflict ())
  | Target_registry_prepared prepared
    when prepared.prepared_target_schema_digest = schema.schema_digest_value ->
      Ok (target_schema_receipt prepared true)
  | Target_registry_prepared _ ->
      if Atomic.compare_and_set registry before Target_registry_conflict then
        Error (target_registry_conflict ())
      else prepare_jj_target_registry_schema registry schema
  | Target_registry_uninitialized ->
      begin match validate_jj_target_registry_schema_exact schema with
      | Error _ as error -> error
      | Ok () ->
          let prepared =
            { prepared_target_schema_digest = schema.schema_digest_value;
              prepared_target_binding_count = List.length schema.schema_bindings;
              prepared_target_receipt_digest =
                digest_fields
                  [ "jj-action-target-registry-prepared-v1";
                    schema.schema_digest_value;
                    string_of_int (List.length schema.schema_bindings) ] }
          in
          if
            Atomic.compare_and_set registry before
              (Target_registry_prepared prepared)
          then Ok (target_schema_receipt prepared false)
          else prepare_jj_target_registry_schema registry schema
      end

let prepare_jj_target_registry_schema_once registry =
  prepare_jj_target_registry_schema registry
    (canonical_jj_target_registry_schema ())

let jj_target_registry_schema_state registry =
  match Atomic.get registry with
  | Target_registry_uninitialized -> Target_schema_uninitialized
  | Target_registry_prepared _ -> Target_schema_prepared
  | Target_registry_conflict -> Target_schema_conflict

let target_registry_prerequisites =
  [ Concrete_target_authority_digests; Task9_target_current_views;
    Request_bound_phase_action_registry;
    Conditional_action_control_registry ]

let jj_target_registry_current_posture = `Implemented_unavailable

let close_jj_target_registry_current_unavailable _registry _receipt =
  Error
    { target_registry_unavailable_operation = "close-jj-target-registry-current";
      target_registry_missing_prerequisites = target_registry_prerequisites }

module Closed = Dependability_sqlite.Closed_operation

type stored_row = Closed.effect_row = {
  schema_version : int;
  stored_key : string;
  stored_request_digest : string;
  stored_target_digest : string;
  stored_target_authority_digest : string;
  stored_effect_kind : string;
  stored_state : string;
  stored_disposition : string option;
  stored_output : string option;
  stored_output_digest : string option;
  stored_receipt_digest : string option;
  stored_diagnostic : string option;
  stored_no_replay : bool;
  stored_row_digest : string;
}

let ( let* ) result continue =
  match result with Ok value -> continue value | Error _ as error -> error

let option_field = function None -> "none" | Some value -> "some:" ^ value

let row_digest row =
  digest_fields
    [ "run-effect-ledger-row-v1"; string_of_int row.schema_version;
      row.stored_key; row.stored_request_digest; row.stored_target_digest;
      row.stored_target_authority_digest; row.stored_effect_kind;
      row.stored_state; option_field row.stored_disposition;
      option_field row.stored_output; option_field row.stored_output_digest;
      option_field row.stored_receipt_digest;
      option_field row.stored_diagnostic;
      if row.stored_no_replay then "no-replay" else "replay-allowed" ]

let effect_kind_of_string = function
  | "dependability-process-attempt" -> Ok Dependability_process_attempt
  | "verification-suite-execution" -> Ok Verification_suite_execution
  | "durable-artifact-publication" -> Ok Durable_artifact_publication
  | "external-resource-observation" -> Ok External_resource_observation
  | "repository-source-observation" -> Ok Repository_source_observation
  | "approval-nonce-consumption" -> Ok Approval_nonce_consumption
  | "writer-lease-transition" -> Ok Writer_lease_transition
  | "production-activation-transition" -> Ok Production_activation_transition
  | "network-scope-transition" -> Ok Network_scope_transition
  | "credential-lease-transition" -> Ok Credential_lease_transition
  | "controlled-filesystem-materialization" ->
      Ok Controlled_filesystem_materialization
  | "candidate-tree-verification" -> Ok Candidate_tree_verification
  | "jujutsu-observation" -> Ok Jujutsu_observation
  | "jujutsu-local-mutation" -> Ok Jujutsu_local_mutation
  | "jujutsu-history-rewrite" -> Ok Jujutsu_history_rewrite
  | "jujutsu-recovery" -> Ok Jujutsu_recovery
  | "jujutsu-remote-synchronization" -> Ok Jujutsu_remote_synchronization
  | "jujutsu-remote-publish" -> Ok Jujutsu_remote_publish
  | "formal-oracle-execution" -> Ok Formal_oracle_execution
  | value -> Error ("unknown effect kind: " ^ value)

let disposition_of_string = function
  | "first-applied" -> Ok First_applied
  | "replayed" -> Ok Replayed
  | value -> Error ("unknown target receipt disposition: " ^ value)

let ledger_diagnostic (interpreter : interpreter) ~code ~bytes ~rca_origin
    ~hazard =
  diagnostic ~coordinate:interpreter.coordinate ~code ~bytes ~rca_origin
    ~hazard ()

let initial_ledger_diagnostic coordinate bytes =
  diagnostic ~coordinate ~code:Effect_ledger_unavailable ~bytes
    ~rca_origin:Ops_capability.Implementation ~hazard:Effect_ledger_corrupt ()

let query_stored_row database idempotency_key =
  match Closed.execute database (Closed.Effect_read idempotency_key) with
  | Ok row -> Ok row
  | Error error -> Error (Closed.string_of_error error)

let validate_stored_row (row : stored_row) =
  let* effect_kind = effect_kind_of_string row.stored_effect_kind in
  if row.schema_version <> 1 then Error "effect ledger schema version is not 1"
  else if not (valid_identifier row.stored_key) then
    Error "effect ledger key is invalid"
  else if
    not
      (valid_digest row.stored_request_digest
       && valid_digest row.stored_target_digest
       && valid_digest row.stored_target_authority_digest
       && valid_digest row.stored_row_digest)
  then Error "effect ledger contains a noncanonical digest"
  else if row.stored_row_digest <> row_digest row then
    Error "effect ledger row digest mismatch"
  else
    match row.stored_state with
    | "pending"
      when row.stored_disposition = None && row.stored_output = None
           && row.stored_output_digest = None
           && row.stored_receipt_digest = None
           && row.stored_diagnostic = None && not row.stored_no_replay ->
        Ok
          (effect_kind,
           Pending
             ({ idempotency_key = row.stored_key;
               request_digest = row.stored_request_digest;
               target_authority_digest = row.stored_target_authority_digest }
               : pending))
    | "applied" ->
        begin match row.stored_disposition, row.stored_output,
                    row.stored_output_digest, row.stored_receipt_digest,
                    row.stored_diagnostic, row.stored_no_replay with
        | Some disposition, Some evidence_bytes,
          Some evidence_projection_digest, Some receipt_digest, None, false ->
            let* disposition = disposition_of_string disposition in
            let* evidence = evidence_of_projection evidence_bytes in
            let expected_projection_digest = sha256 evidence_bytes in
            let expected_receipt_digest =
              target_receipt_digest ~idempotency_key:row.stored_key
                ~request_digest:row.stored_request_digest
                ~target_authority_digest:row.stored_target_authority_digest
                ~disposition ~evidence
            in
            if evidence_projection_digest <> expected_projection_digest then
              Error "effect ledger redacted evidence projection digest mismatch"
            else if receipt_digest <> expected_receipt_digest then
              Error "effect ledger target receipt digest mismatch"
            else
              Ok
                (effect_kind,
                 Applied
                   ({ idempotency_key = row.stored_key;
                     request_digest = row.stored_request_digest;
                     target_authority_digest =
                       row.stored_target_authority_digest;
                     disposition; evidence; receipt_digest } : target_receipt))
        | _ -> Error "effect ledger Applied row has invalid nullable fields"
        end
    | "indeterminate"
      when row.stored_disposition = None && row.stored_output = None
           && row.stored_output_digest = None
           && row.stored_receipt_digest = None
           && Option.exists (fun bytes -> bytes <> "") row.stored_diagnostic
           && row.stored_no_replay ->
        Ok
          (effect_kind,
           Indeterminate_effect
             ({ idempotency_key = row.stored_key;
               request_digest = row.stored_request_digest;
               target_authority_digest = row.stored_target_authority_digest;
               diagnostic_bytes = Option.get row.stored_diagnostic;
               no_replay = true } : indeterminate))
    | "pending" | "indeterminate" ->
        Error ("effect ledger " ^ row.stored_state ^ " row has invalid fields")
    | state -> Error ("unknown effect ledger state: " ^ state)

let initialize_ledger database =
  match Closed.execute database Closed.Effect_initialize_v1 with
  | Ok () -> Ok ()
  | Error error -> Error (Closed.string_of_error error)

let pending_row (target : target) idempotency_key (request : request) =
  let row =
    { schema_version = 1; stored_key = idempotency_key;
      stored_request_digest = request.request_digest;
      stored_target_digest = target.target_digest;
      stored_target_authority_digest = target.authority_digest;
      stored_effect_kind = string_of_effect_kind request.effect_kind;
      stored_state = "pending"; stored_disposition = None;
      stored_output = None; stored_output_digest = None;
      stored_receipt_digest = None; stored_diagnostic = None;
      stored_no_replay = false; stored_row_digest = "" }
  in
  { row with stored_row_digest = row_digest row }

let insert_pending database row =
  match Closed.execute database (Closed.Effect_insert_pending row) with
  | Ok readback -> let* _ = validate_stored_row readback in Ok readback
  | Error error -> Error (Closed.string_of_error error)

let validate_target_receipt (target : target) idempotency_key
    (request : request) (receipt : target_receipt) =
  let expected_receipt_digest =
    target_receipt_digest ~idempotency_key:receipt.idempotency_key
      ~request_digest:receipt.request_digest
      ~target_authority_digest:receipt.target_authority_digest
      ~disposition:receipt.disposition ~evidence:receipt.evidence
  in
  if receipt.idempotency_key <> idempotency_key then
    Error "target receipt idempotency key mismatch"
  else if receipt.request_digest <> request.request_digest then
    Error "target receipt request digest mismatch"
  else if receipt.target_authority_digest <> target.authority_digest then
    Error "target receipt authority digest mismatch"
  else if not (valid_identifier receipt.evidence.evidence_receipt_id)
          || String.length receipt.evidence.evidence_receipt_id > 256
          || not (valid_digest receipt.evidence.evidence_digest)
  then Error "target receipt redacted evidence is invalid"
  else if receipt.receipt_digest <> expected_receipt_digest then
    Error "target receipt digest mismatch"
  else Ok receipt

let applied_row (pending : stored_row) (receipt : target_receipt) =
  let evidence_bytes = evidence_projection receipt.evidence in
  let row =
    { pending with stored_state = "applied";
      stored_disposition = Some (string_of_disposition receipt.disposition);
      stored_output = Some evidence_bytes;
      stored_output_digest = Some (sha256 evidence_bytes);
      stored_receipt_digest = Some receipt.receipt_digest;
      stored_diagnostic = None; stored_no_replay = false;
      stored_row_digest = "" }
  in
  { row with stored_row_digest = row_digest row }

let indeterminate_row (pending : stored_row) diagnostic_bytes =
  let row =
    { pending with stored_state = "indeterminate";
      stored_disposition = None; stored_output = None;
      stored_output_digest = None; stored_receipt_digest = None;
      stored_diagnostic = Some diagnostic_bytes; stored_no_replay = true;
      stored_row_digest = "" }
  in
  { row with stored_row_digest = row_digest row }

let replace_pending database ~pending ~replacement =
  match
    Closed.execute database
      (Closed.Effect_cas_pending { expected = pending; replacement })
  with
  | Ok readback -> let* _ = validate_stored_row readback in Ok readback
  | Error error -> Error (Closed.string_of_error error)

let open_interpreter_with_identity ~database ~target ~admitted_identity
    ~coordinate =
  match initialize_ledger database with
  | Ok () ->
      Ok
        { database; target; admitted_identity; coordinate;
          mutex = Mutex.create (); closed = false }
  | Error bytes -> Error (Ledger_failure (initial_ledger_diagnostic coordinate bytes))

let open_interpreter ~database ~target ~coordinate =
  open_interpreter_with_identity ~database ~target ~admitted_identity:None
    ~coordinate

let registry_gaps (registry : target_registry) =
  let declaration = Run_topology.admitted_declaration registry.activity in
  let gaps = ref (activity_identity_gaps registry.activity) in
  if registry.activity_digest
     <> Run_topology.admitted_activity_digest registry.activity
  then gaps := "registry activity digest differs" :: !gaps;
  if registry.topology_authority_digest <> Run_topology.source_digest then
    gaps := "registry topology authority digest is stale" :: !gaps;
  if registry.target.target_id <> declaration.target_component_id then
    gaps := "registry target id differs from topology" :: !gaps;
  if registry.target.accepted_kinds <> declaration.effect_kinds then
    gaps := "registry effect kinds differ from topology" :: !gaps;
  let expected_authority_digest =
    expected_target_authority_digest ~activity:registry.activity
      ~target_id:registry.target.target_id
      ~accepted_kinds:registry.target.accepted_kinds in
  if registry.target.authority_digest <> expected_authority_digest then
    gaps := "registry target authority digest differs" :: !gaps;
  List.rev !gaps

let effect_kinds_digest effect_kinds =
  digest_fields
    ("run-effect-kind-denominator-v1"
     :: List.map string_of_effect_kind effect_kinds)

let admitted_registry_identity (registry : target_registry) =
  let declaration = Run_topology.admitted_declaration registry.activity in
  { activity_digest = registry.activity_digest;
    topology_authority_digest = registry.topology_authority_digest;
    target_digest = registry.target.target_digest;
    effect_kinds_digest = effect_kinds_digest declaration.effect_kinds }

let open_admitted_interpreter ~database ~registry ~coordinate =
  match registry_gaps registry with
  | [] ->
      open_interpreter_with_identity ~database ~target:registry.target
        ~admitted_identity:(Some (admitted_registry_identity registry))
        ~coordinate
  | gaps ->
      Error
        (Target_unavailable
           (diagnostic ~coordinate ~code:Invalid_effect_target
              ~bytes:(String.concat "; " gaps)
              ~rca_origin:Ops_capability.Control
              ~hazard:Effect_target_invalid ()))

let validate_admitted_interpreter ~activity interpreter =
  let declaration = Run_topology.admitted_declaration activity in
  let expected_activity_digest = Run_topology.activity_digest_of declaration in
  let expected_topology_authority_digest = Run_topology.source_digest in
  let expected_target_id = declaration.target_component_id in
  let expected_effect_kinds = declaration.effect_kinds in
  let expected_target_authority_digest =
    expected_target_authority_digest ~activity ~target_id:expected_target_id
      ~accepted_kinds:expected_effect_kinds in
  let expected_target_digest =
    target_digest_of ~target_id:expected_target_id
      ~authority_digest:expected_target_authority_digest
      ~accepted_kinds:expected_effect_kinds in
  let expected_effect_kinds_digest =
    effect_kinds_digest expected_effect_kinds in
  let gaps = ref (activity_identity_gaps activity) in
  let add message = gaps := message :: !gaps in
  if Run_topology.admitted_activity_digest activity
     <> expected_activity_digest
  then add "admitted interpreter activity is not current canonical activity";
  if Run_topology.admitted_activity_authority_digest activity
     <> expected_topology_authority_digest
  then add "admitted interpreter topology authority is not current";
  if interpreter.target.target_id <> expected_target_id then
    add "interpreter target id differs from current activity";
  if interpreter.target.authority_digest <> expected_target_authority_digest then
    add "interpreter target authority differs from current activity";
  if interpreter.target.accepted_kinds <> expected_effect_kinds then
    add "interpreter effect denominator differs from current activity";
  if interpreter.target.target_digest <> expected_target_digest then
    add "interpreter target digest differs from current activity";
  begin match interpreter.admitted_identity with
  | None -> add "interpreter has no retained admitted registry identity"
  | Some identity ->
      if identity.activity_digest <> expected_activity_digest then
        add "retained activity digest differs from current activity";
      if identity.topology_authority_digest
         <> expected_topology_authority_digest
      then add "retained topology authority digest is not current";
      if identity.target_digest <> expected_target_digest then
        add "retained target digest differs from current activity";
      if identity.effect_kinds_digest <> expected_effect_kinds_digest then
        add "retained effect denominator digest differs from current activity"
  end;
  match List.rev !gaps with
  | [] -> Ok ()
  | gaps ->
      Error
        (List.map
           (fun bytes ->
             diagnostic ~coordinate:interpreter.coordinate
               ~code:Invalid_effect_target ~bytes
               ~rca_origin:Ops_capability.Control
               ~hazard:Effect_target_invalid ())
           gaps)

let locked interpreter body =
  Mutex.lock interpreter.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock interpreter.mutex) body

let interpreter_closed interpreter =
  ledger_diagnostic interpreter ~code:Effect_interpreter_closed
    ~bytes:"effect interpreter is closed" ~rca_origin:Ops_capability.Control
    ~hazard:Effect_request_invalid

let ledger_failure interpreter bytes =
  Ledger_failure
    (ledger_diagnostic interpreter ~code:Effect_ledger_unavailable ~bytes
       ~rca_origin:Ops_capability.Implementation ~hazard:Effect_ledger_corrupt)

let invalid_key interpreter =
  Invalid_request
    (ledger_diagnostic interpreter ~code:Invalid_idempotency_key
       ~bytes:"idempotency_key must be nonempty, trimmed, and control-free"
       ~rca_origin:Ops_capability.Control ~hazard:Effect_request_invalid)

let indeterminate_error interpreter state code bytes =
  let issue =
    ledger_diagnostic interpreter ~code ~bytes
      ~rca_origin:Ops_capability.Environment ~hazard:Effect_outcome_uncertain
  in
  Indeterminate (state, issue)

let persist_indeterminate interpreter pending bytes code =
  let replacement = indeterminate_row pending bytes in
  match
    replace_pending interpreter.database ~pending ~replacement
  with
  | Error error -> Error (ledger_failure interpreter error)
  | Ok stored ->
      begin match validate_stored_row stored with
      | Ok (_, (Indeterminate_effect _ as state)) ->
          Error (indeterminate_error interpreter state code bytes)
      | Ok (_, (Pending _ | Applied _)) ->
          Error (ledger_failure interpreter "indeterminate CAS readback has wrong state")
      | Error error -> Error (ledger_failure interpreter error)
      end

let persist_applied interpreter pending receipt =
  let replacement = applied_row pending receipt in
  match replace_pending interpreter.database ~pending ~replacement with
  | Error error -> Error (ledger_failure interpreter error)
  | Ok stored ->
      begin match validate_stored_row stored with
      | Ok (_, Applied receipt) -> Ok receipt
      | Ok (_, (Pending _ | Indeterminate_effect _)) ->
          Error (ledger_failure interpreter "Applied CAS readback has wrong state")
      | Error error -> Error (ledger_failure interpreter error)
      end

let conflict interpreter idempotency_key persisted_digest observed_digest =
  let diagnostic =
    ledger_diagnostic interpreter ~code:Effect_key_conflict
      ~bytes:"idempotency key is already bound to a different request digest"
      ~rca_origin:Ops_capability.Control ~hazard:Effect_identity_conflict
  in
  Key_reused_with_different_request
    { idempotency_key; persisted_digest; observed_digest; diagnostic }

let state_of_row interpreter row =
  match validate_stored_row row with
  | Error error -> Error (ledger_failure interpreter error)
  | Ok (effect_kind, state) ->
      if row.stored_target_digest <> interpreter.target.target_digest
         || row.stored_target_authority_digest <> interpreter.target.authority_digest
      then Error (ledger_failure interpreter "effect ledger target identity mismatch")
      else if not (List.mem effect_kind interpreter.target.accepted_kinds) then
        Error (ledger_failure interpreter "effect ledger kind is not accepted by target")
      else Ok state

let resolve_pending interpreter (pending_row : stored_row) (request : request) =
  let idempotency_key = pending_row.stored_key in
  let uncertain code bytes =
    persist_indeterminate interpreter pending_row bytes code
  in
  let reconcile_after_failure failure_bytes =
    let queried_after_failure =
      match interpreter.target.target_query ~idempotency_key with
      | result -> Ok result
      | exception exn -> Error (Printexc.to_string exn)
    in
    match queried_after_failure with
    | Ok (Ok (Some receipt)) ->
        begin match
          validate_target_receipt interpreter.target idempotency_key request
            receipt
        with
        | Ok receipt -> persist_applied interpreter pending_row receipt
        | Error receipt_bytes ->
            uncertain Effect_receipt_invalid
              (failure_bytes ^ "; post-failure receipt invalid: "
               ^ receipt_bytes)
        end
    | Ok (Ok None) -> uncertain Effect_target_failure failure_bytes
    | Error query_bytes | Ok (Error query_bytes) ->
        uncertain Effect_target_failure
          (failure_bytes ^ "; post-failure target-native query failed: "
           ^ query_bytes)
  in
  let queried =
    match interpreter.target.target_query ~idempotency_key with
    | result -> Ok result
    | exception exn -> Error (Printexc.to_string exn)
  in
  match queried with
  | Error bytes ->
      Error
        (Target_unavailable
           (ledger_diagnostic interpreter ~code:Effect_target_failure
              ~bytes:("target-native query failed: " ^ bytes)
              ~rca_origin:Ops_capability.Environment
              ~hazard:Effect_outcome_uncertain))
  | Ok (Error bytes) ->
      Error
        (Target_unavailable
           (ledger_diagnostic interpreter ~code:Effect_target_failure
              ~bytes:("target-native query failed: " ^ bytes)
              ~rca_origin:Ops_capability.Environment
              ~hazard:Effect_outcome_uncertain))
  | Ok (Ok (Some receipt)) ->
      begin match
        validate_target_receipt interpreter.target idempotency_key request receipt
      with
      | Ok receipt -> persist_applied interpreter pending_row receipt
      | Error bytes -> uncertain Effect_receipt_invalid bytes
      end
  | Ok (Ok None) ->
      let applied =
        match interpreter.target.target_apply_once ~idempotency_key request with
        | result -> Ok result
        | exception exn -> Error (Printexc.to_string exn)
      in
      begin match applied with
      | Error bytes -> reconcile_after_failure bytes
      | Ok (Error bytes) -> reconcile_after_failure bytes
      | Ok (Ok receipt) ->
          begin match
            validate_target_receipt interpreter.target idempotency_key request receipt
          with
          | Ok receipt -> persist_applied interpreter pending_row receipt
          | Error bytes -> uncertain Effect_receipt_invalid bytes
          end
      end

let apply_once interpreter ~idempotency_key (request : request) =
  locked interpreter (fun () ->
    if interpreter.closed then Error (Invalid_request (interpreter_closed interpreter))
    else if not (valid_identifier idempotency_key) then Error (invalid_key interpreter)
    else if not (List.mem request.effect_kind interpreter.target.accepted_kinds) then
      Error
        (Invalid_request
           (ledger_diagnostic interpreter ~code:Effect_kind_not_accepted
              ~bytes:
                ("target does not accept "
                 ^ string_of_effect_kind request.effect_kind)
              ~rca_origin:Ops_capability.Control
              ~hazard:Effect_kind_unauthorized))
    else
      match query_stored_row interpreter.database idempotency_key with
      | Error error -> Error (ledger_failure interpreter error)
      | Ok (Some row) when row.stored_request_digest <> request.request_digest ->
          Error
            (conflict interpreter idempotency_key row.stored_request_digest
               request.request_digest)
      | Ok (Some row) ->
          begin match state_of_row interpreter row with
          | Error _ as error -> error
          | Ok (Applied receipt) -> Ok receipt
          | Ok (Indeterminate_effect _ as state) ->
              Error
                (indeterminate_error interpreter state Effect_target_failure
                   "effect outcome is durably indeterminate and cannot be replayed")
          | Ok (Pending _) -> resolve_pending interpreter row request
          end
      | Ok None ->
          let pending = pending_row interpreter.target idempotency_key request in
          begin match insert_pending interpreter.database pending with
          | Error error -> Error (ledger_failure interpreter error)
          | Ok stored ->
              if stored.stored_request_digest <> request.request_digest then
                Error
                  (conflict interpreter idempotency_key
                     stored.stored_request_digest request.request_digest)
              else
                begin match state_of_row interpreter stored with
                | Error _ as error -> error
                | Ok (Applied receipt) -> Ok receipt
                | Ok (Indeterminate_effect _ as state) ->
                    Error
                      (indeterminate_error interpreter state Effect_target_failure
                         "effect outcome is durably indeterminate and cannot be replayed")
                | Ok (Pending _) -> resolve_pending interpreter stored request
                end
          end)

let query interpreter ~idempotency_key =
  locked interpreter (fun () ->
    if interpreter.closed then Error (Invalid_request (interpreter_closed interpreter))
    else if not (valid_identifier idempotency_key) then Error (invalid_key interpreter)
    else
      match query_stored_row interpreter.database idempotency_key with
      | Error error -> Error (ledger_failure interpreter error)
      | Ok None -> Ok None
      | Ok (Some row) ->
          begin match state_of_row interpreter row with
          | Ok state -> Ok (Some state)
          | Error _ as error -> error
          end)

let close interpreter =
  locked interpreter (fun () -> interpreter.closed <- true)

module For_test = struct
  type admitted_identity_mutation =
    | Activity_digest
    | Topology_authority_digest
    | Target_digest
    | Effect_kinds_digest

  let mutate_digest value = sha256 (value ^ ":mutant")

  let mutate_admitted_identity mutation interpreter =
    let admitted_identity =
      Option.map
        (fun identity ->
          match mutation with
          | Activity_digest ->
              { identity with
                activity_digest = mutate_digest identity.activity_digest }
          | Topology_authority_digest ->
              { identity with
                topology_authority_digest =
                  mutate_digest identity.topology_authority_digest }
          | Target_digest ->
              { identity with
                target_digest = mutate_digest identity.target_digest }
          | Effect_kinds_digest ->
              { identity with
                effect_kinds_digest = mutate_digest identity.effect_kinds_digest })
        interpreter.admitted_identity
    in
    { interpreter with admitted_identity }

  type target_schema_mutation =
    | Drop_action_binding
    | Add_action_binding
    | Duplicate_action_binding
    | Reorder_action_bindings
    | Cross_activity_binding
    | Swap_target_component
    | Swap_effect_kind
    | Change_dependency_schema
    | Forge_target_authority

  let mutate_first change bindings =
    match bindings with [] -> [] | first :: rest -> change first :: rest

  let mutate_jj_target_registry_schema mutation =
    let canonical = canonical_action_target_bindings () in
    let mutated =
      match mutation, canonical with
      | Drop_action_binding, [] -> []
      | Drop_action_binding, _ :: rest -> rest
      | Add_action_binding, [] -> []
      | Add_action_binding, first :: _ ->
          canonical
          @ [ { first with
                binding_action_id = first.binding_action_id ^ ".extra" } ]
      | Duplicate_action_binding, [] -> []
      | Duplicate_action_binding, first :: _ -> first :: canonical
      | Reorder_action_bindings, bindings -> List.rev bindings
      | Cross_activity_binding, [] -> []
      | Cross_activity_binding, (first :: _ as bindings) ->
          let foreign_activity_id =
            bindings
            |> List.find_map (fun binding ->
                 if binding.binding_activity_id
                    <> first.binding_activity_id
                 then Some binding.binding_activity_id else None)
            |> Option.value ~default:"task7a.cross-activity"
          in
          mutate_first
            (fun binding ->
              { binding with binding_activity_id = foreign_activity_id })
            bindings
      | Swap_target_component, bindings ->
          mutate_first
            (fun binding ->
              { binding with
                binding_target_component_id = "task9-target.swapped.unavailable" })
            bindings
      | Swap_effect_kind, bindings ->
          mutate_first
            (fun binding ->
              { binding with
                binding_effect_kind =
                  (if binding.binding_effect_kind = Jujutsu_observation then
                     Jujutsu_local_mutation
                   else Jujutsu_observation) })
            bindings
      | Change_dependency_schema, bindings ->
          mutate_first
            (fun binding ->
              { binding with
                binding_dependency_schema_id =
                  mutate_digest binding.binding_dependency_schema_id })
            bindings
      | Forge_target_authority, bindings ->
          mutate_first
            (fun binding ->
              { binding with
                binding_target_authority_digest = Some (String.make 64 'f') })
            bindings
    in
    schema_of_bindings mutated

  let prepare_jj_target_registry_schema_with_mutation registry mutation =
    prepare_jj_target_registry_schema registry
      (mutate_jj_target_registry_schema mutation)
end
