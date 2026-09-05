type t = {
  action_id : string;
  effect_kind : Run_topology.effect_kind;
  request_bytes : string;
  request_digest : string;
  dependency_input_digest : string;
  idempotency_key : string;
}

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let digest_fields fields =
  fields
  |> List.map (fun field -> Printf.sprintf "%d:%s" (String.length field) field)
  |> String.concat ""
  |> sha256

let string_of_effect_kind = Run_topology.effect_kind_id

let string_of_verification_profile = function
  | Run_topology.Verification_fast -> "fast"
  | Run_topology.Verification_full -> "full"

let json_fields_of_work = function
  | Run_topology.Topology_gate ->
      [ ("work_kind", `String "topology-gate") ]
  | Run_topology.Repository_build { profile; build_command } ->
      [ ("work_kind", `String "repository-build");
        ("profile_id", `String (string_of_verification_profile profile));
        ("build_command", `String build_command) ]
  | Run_topology.Repository_verification_suite
      { profile; suite_id; executable } ->
      [ ("work_kind", `String "repository-verification-suite");
        ("profile_id", `String (string_of_verification_profile profile));
        ("suite_id", `String suite_id);
        ("executable", `String executable) ]
  | work ->
      [ ("work_kind", `String "closed-task7a-work");
        ("work_id", `String (Run_topology.action_work_id work)) ]

let unique values =
  List.length values = List.length (List.sort_uniq String.compare values)

let canonical_action ~(activity : Run_topology.admitted_activity)
    (action : Run_topology.declarative_action) =
  let declaration = Run_topology.admitted_declaration activity in
  let actions = Run_topology.admitted_actions activity in
  match Run_topology.admit_activity ~stable_id:declaration.stable_id with
  | Error issues -> Error (String.concat "; " issues)
  | Ok current
    when not
      (String.equal (Run_topology.admitted_activity_digest current)
         (Run_topology.admitted_activity_digest activity)
       && String.equal
            (Run_topology.admitted_activity_authority_digest current)
            (Run_topology.admitted_activity_authority_digest activity)
       && Run_topology.admitted_declaration current = declaration) ->
      Error "admitted activity differs from the current topology authority"
  | Ok _ ->
      let action_ids =
        List.map
          (fun (item : Run_topology.declarative_action) -> item.stable_id)
          actions
      in
      let action_digests = List.map Run_topology.action_digest_of actions in
      if actions = [] then Error "admitted activity action denominator is empty"
      else if not (unique action_ids) then
        Error "admitted activity action identities are duplicated"
      else if not (unique action_digests) then
        Error "admitted activity action digests are duplicated"
      else
        match
          List.filter
            (fun (item : Run_topology.declarative_action) ->
              String.equal item.stable_id action.stable_id)
            actions
        with
        | [ expected ]
          when expected = action
               && String.equal (Run_topology.action_digest_of expected)
                    (Run_topology.action_digest_of action) ->
            Ok expected
        | [ _ ] -> Error "action differs from its admitted canonical member"
        | [] -> Error "action is not a member of the admitted activity"
        | _ :: _ :: _ -> Error "action identity is duplicated in the activity"

let idempotency_key ~execution_identity ~activity
    ~(action : Run_topology.declarative_action) =
  let declaration = Run_topology.admitted_declaration activity in
  digest_fields
    [ "run-swarm-effect-key-v3"; execution_identity; declaration.stable_id;
      Run_topology.admitted_activity_digest activity;
      Run_topology.admitted_activity_authority_digest activity; action.stable_id;
      Run_topology.action_digest_of action; action.preparation_id;
      action.target_component_id; string_of_effect_kind action.effect_kind ]

let prepare ~execution_identity ~activity
    ~(action : Run_topology.declarative_action) ~input_payload =
  if String.length execution_identity <> 64 then
    Error "execution identity is malformed"
  else
    match canonical_action ~activity action with
    | Error _ as error -> error
    | Ok action ->
        let declaration = Run_topology.admitted_declaration activity in
        let dependency_input_digest =
          digest_fields
            [ "run-swarm-dependency-input-v2"; declaration.stable_id;
              Run_topology.admitted_activity_digest activity;
              action.stable_id; input_payload ]
        in
        let request_json =
          `Assoc
            ([ ("activity_id", `String declaration.stable_id);
              ("activity_digest",
               `String (Run_topology.admitted_activity_digest activity));
              ("topology_authority_digest",
               `String
                 (Run_topology.admitted_activity_authority_digest activity));
              ("action_id", `String action.stable_id);
              ("assigned_agent_id", `String action.assigned_agent_id);
              ("command_id", `String action.command_id);
              ("dependency_ids",
               `List (List.map (fun value -> `String value)
                        action.dependency_ids));
              ("dependency_input_digest", `String dependency_input_digest);
              ("execution_identity", `String execution_identity);
              ("action_digest",
               `String (Run_topology.action_digest_of action));
              ("preparation_id", `String action.preparation_id);
              ("target_component_id", `String action.target_component_id);
              ("effect_kind", `String (string_of_effect_kind action.effect_kind));
              ("version", `String "run-swarm-preparation-v3") ]
             @ json_fields_of_work action.work)
        in
        begin match Run_model.canonical_string request_json with
        | Error message -> Error message
        | Ok request_bytes ->
            let request_digest = sha256 request_bytes in
            let idempotency_key =
              idempotency_key ~execution_identity ~activity ~action
            in
            Ok
              { action_id = action.stable_id; effect_kind = action.effect_kind;
                request_bytes; request_digest; dependency_input_digest;
                idempotency_key }
        end

let request_field_order =
  [ "activity_id"; "activity_digest"; "topology_authority_digest";
    "action_id"; "assigned_agent_id"; "command_id"; "dependency_ids";
    "dependency_input_digest"; "execution_identity"; "action_digest";
    "preparation_id"; "target_component_id"; "effect_kind"; "version";
    "work_projection_fields" ]

let effect_denominator =
  Run_topology.effect_kinds
  |> List.map Run_topology.effect_kind_id
  |> String.concat ","

let source_fields =
  [ ("schema-version", "run-swarm-preparation-v3");
    ("request-field-order", String.concat "," request_field_order);
    ("effect-denominator", effect_denominator);
    ("work-class-denominator",
     String.concat "," Run_topology.task7a_action_work_class_ids);
    ("work-class-digest", Run_topology.task7a_action_work_class_digest);
    ("completion-receipt-subdenominator",
     String.concat "," Run_topology.task7a_completion_receipt_work_ids);
    ("completion-receipt-digest",
     Run_topology.task7a_completion_receipt_work_digest);
    ("work-projection-fields",
     "topology-gate(work_kind);repository-build(work_kind,profile_id,build_command);repository-verification-suite(work_kind,profile_id,suite_id,executable);closed-task7a-work(work_kind,work_id)");
    ("dependency-input-fields",
     "run-swarm-dependency-input-v2,activity_id,activity_digest,action_id,input_payload");
    ("idempotency-fields",
     "run-swarm-effect-key-v3,execution_identity,activity_id,activity_digest,topology_authority_digest,action_id,action_digest,preparation_id,target_component_id,effect_kind");
    ("refusal-posture",
     "exact-current-admitted-action-only;malformed-execution-refused;no-execution") ]

let source_digest_of fields =
  fields
  |> List.concat_map (fun (name, value) -> [ name; value ])
  |> digest_fields

let source_digest = source_digest_of source_fields

module For_test = struct
  type source_mutation =
    | Drop_schema_version
    | Drop_activity_identity_field
    | Drop_topology_authority_field
    | Drop_action_identity_field
    | Drop_assignment_field
    | Drop_command_field
    | Drop_dependency_ids_field
    | Drop_dependency_input_field
    | Drop_execution_identity_field
    | Drop_action_digest_field
    | Drop_preparation_id_field
    | Drop_target_component_field
    | Drop_effect_kind_field
    | Reorder_request_fields
    | Drop_effect_denominator
    | Drop_work_class_denominator
    | Drop_completion_receipt_subdenominator
    | Drop_work_projection_fields
    | Drop_idempotency_fields
    | Enable_noncanonical_action

  let drop_field field fields =
    List.filter (fun candidate -> not (String.equal candidate field)) fields

  let drop_source name fields =
    List.filter (fun (candidate, _) -> not (String.equal candidate name)) fields

  let replace_source name value fields =
    List.map
      (fun ((candidate, _) as field) ->
        if String.equal candidate name then (candidate, value) else field)
      fields

  let request_fields_without field =
    request_field_order |> drop_field field |> String.concat ","

  let request_fields_without_activity_identity =
    request_field_order
    |> drop_field "activity_id"
    |> drop_field "activity_digest"
    |> String.concat ","

  let source_digest_with_mutation mutation =
    let fields =
      match mutation with
      | Drop_schema_version -> drop_source "schema-version" source_fields
      | Drop_activity_identity_field ->
          replace_source "request-field-order"
            request_fields_without_activity_identity source_fields
      | Drop_topology_authority_field ->
          replace_source "request-field-order"
            (request_fields_without "topology_authority_digest") source_fields
      | Drop_action_identity_field ->
          replace_source "request-field-order"
            (request_fields_without "action_id") source_fields
      | Drop_assignment_field ->
          replace_source "request-field-order"
            (request_fields_without "assigned_agent_id") source_fields
      | Drop_command_field ->
          replace_source "request-field-order"
            (request_fields_without "command_id") source_fields
      | Drop_dependency_ids_field ->
          replace_source "request-field-order"
            (request_fields_without "dependency_ids") source_fields
      | Drop_dependency_input_field ->
          replace_source "request-field-order"
            (request_fields_without "dependency_input_digest") source_fields
      | Drop_execution_identity_field ->
          replace_source "request-field-order"
            (request_fields_without "execution_identity") source_fields
      | Drop_action_digest_field ->
          replace_source "request-field-order"
            (request_fields_without "action_digest") source_fields
      | Drop_preparation_id_field ->
          replace_source "request-field-order"
            (request_fields_without "preparation_id") source_fields
      | Drop_target_component_field ->
          replace_source "request-field-order"
            (request_fields_without "target_component_id") source_fields
      | Drop_effect_kind_field ->
          replace_source "request-field-order"
            (request_fields_without "effect_kind") source_fields
      | Reorder_request_fields ->
          replace_source "request-field-order"
            (request_field_order |> List.rev |> String.concat ",") source_fields
      | Drop_effect_denominator ->
          drop_source "effect-denominator" source_fields
      | Drop_work_class_denominator ->
          source_fields
          |> drop_source "work-class-denominator"
          |> drop_source "work-class-digest"
      | Drop_completion_receipt_subdenominator ->
          source_fields
          |> drop_source "completion-receipt-subdenominator"
          |> drop_source "completion-receipt-digest"
      | Drop_work_projection_fields ->
          drop_source "work-projection-fields" source_fields
      | Drop_idempotency_fields ->
          drop_source "idempotency-fields" source_fields
      | Enable_noncanonical_action ->
          replace_source "refusal-posture" "accept-substituted-action" source_fields
    in
    source_digest_of fields
end
