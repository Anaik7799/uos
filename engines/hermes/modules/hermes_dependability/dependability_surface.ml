type transport = Ocaml_api | Cli | Mcp | Zenoh
type action = Verify_reliability | Verify_full
type verdict = Passed | Failed | Unavailable_observed | Skipped

type diagnostic_code =
  | Malformed_request
  | Unknown_field
  | Unknown_action
  | Unknown_target
  | Plane_mismatch
  | Generic_invoke_forbidden
  | Invalid_intent
  | Invalid_receipt
  | Dispatch_unavailable

type diagnostic = {
  code : diagnostic_code;
  detail_digest : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
}

type success = {
  intent_digest : string;
  action : action;
  verdict : verdict;
  receipt_digest : string;
  effect_digest : string;
  readback_digest : string;
  result_digest : string;
}

type failure = {
  intent_digest : string option;
  action : action option;
  verdict : verdict;
  diagnostic : diagnostic;
  receipt_digest : string;
  effect_digest : string;
  readback_digest : string;
  result_digest : string;
}

type normalized_result = Success of success | Error of failure
type request = { action : action; intent : Dependability_intent.t }
type observation = { transport : transport; result : normalized_result }
type status_query = {
  status_request_id : string;
  status_intent_digest : string;
}
type status_observation = {
  status_query : status_query;
  current_result : normalized_result option;
  status_digest : string;
}
type executor = Dependability_intent.t -> normalized_result

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let operation_of_action = function
  | Verify_reliability -> Dependability_intent.Verify_reliability
  | Verify_full -> Dependability_intent.Verify_full

let action_name = function
  | Verify_reliability -> "verify-reliability"
  | Verify_full -> "verify-full"

let transport_name = function
  | Ocaml_api -> "ocaml-api"
  | Cli -> "cli"
  | Mcp -> "mcp"
  | Zenoh -> "zenoh"

let diagnostic_code_name = function
  | Malformed_request -> "malformed-request"
  | Unknown_field -> "unknown-field"
  | Unknown_action -> "unknown-action"
  | Unknown_target -> "unknown-target"
  | Plane_mismatch -> "plane-mismatch"
  | Generic_invoke_forbidden -> "generic-invoke-forbidden"
  | Invalid_intent -> "invalid-intent"
  | Invalid_receipt -> "invalid-receipt"
  | Dispatch_unavailable -> "dispatch-unavailable"

let diagnostic code detail =
  { code; detail_digest = sha256 detail;
    coordinate = { Ops_capability.level = Ops_capability.L4;
                   phase = Ops_capability.Observe };
    rca_origin = Ops_capability.Control;
    hazard_id = "HZ-SURFACE-ADMISSION-01" }

let make_request ~action ~intent =
  if Dependability_intent.operation intent = operation_of_action action then
    Ok { action; intent }
  else
    Stdlib.Result.Error
      (diagnostic Invalid_intent "action and intent operation disagree")

let action request = request.action
let intent_of_request request = request.intent
let semantic_digest request = Dependability_intent.digest request.intent

let canonical_request_json request =
  `Assoc
    [ ("action", `String (action_name request.action));
      ("intent", Yojson.Safe.from_string
         (Dependability_intent.canonical_json request.intent)) ]
  |> Yojson.Safe.to_string

let ( let* ) result continuation =
  match result with
  | Ok value -> continuation value
  | Stdlib.Result.Error _ as error -> error

let parse_error code detail = Stdlib.Result.Error (diagnostic code detail)

let object_fields ~expected = function
  | `Assoc fields ->
      let keys = List.map fst fields in
      if List.length keys <> List.length (List.sort_uniq String.compare keys)
      then parse_error Malformed_request "duplicate JSON object field"
      else
        begin match List.find_opt (fun key -> not (List.mem key expected)) keys with
        | Some key -> parse_error Unknown_field ("unknown field: " ^ key)
        | None ->
            begin match List.find_opt (fun key -> not (List.mem key keys)) expected with
            | Some key -> parse_error Malformed_request ("missing field: " ^ key)
            | None -> Ok fields
            end
        end
  | _ -> parse_error Malformed_request "expected JSON object"

let member fields key =
  match List.assoc_opt key fields with
  | Some value -> Ok value
  | None -> parse_error Malformed_request ("missing field: " ^ key)

let string_value name = function
  | `String value -> Ok value
  | _ -> parse_error Malformed_request (name ^ " must be a string")

let bool_value name = function
  | `Bool value -> Ok value
  | _ -> parse_error Malformed_request (name ^ " must be a Boolean")

let int_value name = function
  | `Int value -> Ok value
  | `Intlit value ->
      begin match int_of_string_opt value with
      | Some value -> Ok value
      | None -> parse_error Invalid_intent (name ^ " is outside the integer range")
      end
  | _ -> parse_error Malformed_request (name ^ " must be an integer")

let int64_value name = function
  | `Int value -> Ok (Int64.of_int value)
  | `Intlit value ->
      begin match Int64.of_string_opt value with
      | Some value -> Ok value
      | None -> parse_error Invalid_intent (name ^ " is outside the int64 range")
      end
  | _ -> parse_error Malformed_request (name ^ " must be an integer")

let list_value name = function
  | `List values -> Ok values
  | _ -> parse_error Malformed_request (name ^ " must be an array")

let field parser fields key =
  let* value = member fields key in
  parser key value

let action_of_name = function
  | "verify-reliability" -> Ok Verify_reliability
  | "verify-full" -> Ok Verify_full
  | "invoke" ->
      parse_error Generic_invoke_forbidden "generic Invoke is forbidden"
  | value -> parse_error Unknown_action ("unknown action: " ^ value)

let target_of_name = function
  | "sqlite.run-event-store" -> Ok Dependability_intent.Sqlite_run_event_store
  | "sqlite.sa-plan-store" -> Ok Dependability_intent.Sqlite_sa_plan_store
  | "sqlite.ops-completion-history" ->
      Ok Dependability_intent.Sqlite_ops_completion_history
  | "sqlite.evidence-store" -> Ok Dependability_intent.Sqlite_evidence_store
  | value -> parse_error Unknown_target ("unknown target: " ^ value)

let plane_of_name = function
  | "control-plane" -> Ok Dependability_intent.Control_plane
  | "data-plane" -> Ok Dependability_intent.Data_plane
  | "both-planes" -> Ok Dependability_intent.Both_planes
  | value -> parse_error Plane_mismatch ("unknown plane: " ^ value)

let level_of_name = function
  | "L0" -> Ok Ops_capability.L0
  | "L1" -> Ok Ops_capability.L1
  | "L2" -> Ok Ops_capability.L2
  | "L3" -> Ok Ops_capability.L3
  | "L4" -> Ok Ops_capability.L4
  | "L5" -> Ok Ops_capability.L5
  | "L6" -> Ok Ops_capability.L6
  | "LX" -> Ok Ops_capability.LX
  | value -> parse_error Invalid_intent ("unknown coordinate level: " ^ value)

let phase_of_name = function
  | "observe" -> Ok Ops_capability.Observe
  | "orient" -> Ok Ops_capability.Orient
  | "decide" -> Ok Ops_capability.Decide
  | "act" -> Ok Ops_capability.Act
  | value -> parse_error Invalid_intent ("unknown OODA phase: " ^ value)

let parse_coordinate json =
  let* fields = object_fields ~expected:[ "level"; "phase" ] json in
  let* level_text = field string_value fields "level" in
  let* phase_text = field string_value fields "phase" in
  let* level = level_of_name level_text in
  let* phase = phase_of_name phase_text in
  Ok { Ops_capability.level; phase }

let rec traverse parser = function
  | [] -> Ok []
  | value :: rest ->
      let* parsed = parser value in
      let* parsed_rest = traverse parser rest in
      Ok (parsed :: parsed_rest)

let parse_predicate json =
  match json with
  | `Assoc fields ->
      let keys = List.map fst fields in
      if List.length keys <> List.length (List.sort_uniq String.compare keys)
      then parse_error Malformed_request "duplicate predicate field"
      else
        let* kind = field string_value fields "kind" in
        begin match kind with
        | "exit-zero" | "no-signal" | "no-matching-crash" ->
            let* _ = object_fields ~expected:[ "kind" ] json in
            Ok
              (match kind with
               | "exit-zero" -> Dependability_intent.Exit_zero
               | "no-signal" -> Dependability_intent.No_signal
               | _ -> Dependability_intent.No_matching_crash)
        | "metric-at-least" ->
            let* fields =
              object_fields ~expected:[ "kind"; "metric"; "minimum" ] json
            in
            let* metric = field string_value fields "metric" in
            let* minimum = field int64_value fields "minimum" in
            Ok (Dependability_intent.Metric_at_least (metric, minimum))
        | value ->
            parse_error Invalid_intent ("unknown success predicate: " ^ value)
        end
  | _ -> parse_error Malformed_request "predicate must be an object"

let parse_criterion json =
  let* fields =
    object_fields ~expected:[ "id"; "description"; "predicate" ] json
  in
  let* id = field string_value fields "id" in
  let* description = field string_value fields "description" in
  let* predicate_json = member fields "predicate" in
  let* predicate = parse_predicate predicate_json in
  match Dependability_intent.make_criterion ~id ~description ~predicate with
  | Ok value -> Ok value
  | Error detail -> parse_error Invalid_intent detail

let parse_schedule json =
  let* fields =
    object_fields
      ~expected:
        [ "bounded_parallel_attempts"; "lane_count";
          "permit_topology_digest"; "sequential_oracle_attempts" ]
      json
  in
  let* bounded_parallel_attempts =
    field int_value fields "bounded_parallel_attempts"
  in
  let* lane_count = field int_value fields "lane_count" in
  let* permit_topology_digest =
    field string_value fields "permit_topology_digest"
  in
  let* sequential_oracle_attempts =
    field int_value fields "sequential_oracle_attempts"
  in
  match
    Dependability_intent.make_reliability_schedule
      ~sequential_oracle_attempts ~bounded_parallel_attempts ~lane_count
  with
  | Error detail -> parse_error Invalid_intent detail
  | Ok schedule
    when Dependability_intent.permit_topology_digest schedule
         <> permit_topology_digest ->
      parse_error Invalid_intent "permit topology digest disagrees with schedule"
  | Ok schedule -> Ok schedule

let parse_policy json =
  let* fields =
    object_fields
      ~expected:
        [ "attempts"; "confidence_ppm"; "maximum_failures";
          "maximum_incident_rate_ppm"; "maximum_parallelism";
          "minimum_overlap_gc_cycles"; "reliability_schedule";
          "per_child_timeout_ns"; "require_crash_window"; "require_formal";
          "require_full_gate" ]
      json
  in
  let* attempts = field int_value fields "attempts" in
  let* confidence_ppm = field int_value fields "confidence_ppm" in
  let* maximum_failures = field int_value fields "maximum_failures" in
  let* maximum_incident_rate_ppm =
    field int_value fields "maximum_incident_rate_ppm"
  in
  let* maximum_parallelism = field int_value fields "maximum_parallelism" in
  let* minimum_overlap_gc_cycles =
    field int_value fields "minimum_overlap_gc_cycles"
  in
  let* schedule_json = member fields "reliability_schedule" in
  let* reliability_schedule = parse_schedule schedule_json in
  let* per_child_timeout_ns =
    field int64_value fields "per_child_timeout_ns"
  in
  let* require_crash_window =
    field bool_value fields "require_crash_window"
  in
  let* require_formal = field bool_value fields "require_formal" in
  let* require_full_gate = field bool_value fields "require_full_gate" in
  if
    maximum_parallelism
    <> Dependability_intent.lane_count reliability_schedule
  then parse_error Invalid_intent "maximum parallelism disagrees with schedule"
  else
    match
      Dependability_intent.make_policy ~confidence_ppm
        ~maximum_incident_rate_ppm ~attempts ~per_child_timeout_ns
        ~maximum_failures ~minimum_overlap_gc_cycles ~reliability_schedule
        ~require_formal ~require_crash_window ~require_full_gate ()
    with
    | Ok policy -> Ok policy
    | Error detail -> parse_error Invalid_intent detail

let parse_source json =
  let* fields =
    object_fields
      ~expected:
        [ "authority_digest"; "build_digest"; "configuration_digest";
          "provenance_digest"; "source_clean"; "source_revision" ]
      json
  in
  let* authority_digest = field string_value fields "authority_digest" in
  let* build_digest = field string_value fields "build_digest" in
  let* configuration_digest =
    field string_value fields "configuration_digest"
  in
  let* provenance_digest = field string_value fields "provenance_digest" in
  let* source_clean = field bool_value fields "source_clean" in
  let* source_revision = field string_value fields "source_revision" in
  Ok
    { Dependability_intent.source_revision; source_clean; configuration_digest;
      authority_digest; build_digest; provenance_digest }

let decode_intent_json json =
  let* fields =
    object_fields
      ~expected:
        [ "activity_id"; "activity_path"; "criteria"; "operation"; "plane";
          "policy"; "request_id"; "run_id"; "source"; "target" ]
      json
  in
  let* activity_id = field string_value fields "activity_id" in
  let* activity_path_json = field list_value fields "activity_path" in
  let* activity_path = traverse parse_coordinate activity_path_json in
  let* criteria_json = field list_value fields "criteria" in
  let* criteria = traverse parse_criterion criteria_json in
  let* operation_text = field string_value fields "operation" in
  let* operation_action = action_of_name operation_text in
  let operation = operation_of_action operation_action in
  let* plane_text = field string_value fields "plane" in
  let* plane = plane_of_name plane_text in
  let* policy_json = member fields "policy" in
  let* policy = parse_policy policy_json in
  let* request_id = field string_value fields "request_id" in
  let* run_id = field string_value fields "run_id" in
  let* source_json = member fields "source" in
  let* source = parse_source source_json in
  let* target_text = field string_value fields "target" in
  let* target = target_of_name target_text in
  match
    Dependability_intent.make ~request_id ~activity_id ~run_id ~operation
      ~activity_path ~target ~plane ~policy ~criteria ~source
  with
  | Ok intent -> Ok intent
  | Error detail -> parse_error Invalid_intent detail

let decode_request_value json =
  let* fields = object_fields ~expected:[ "action"; "intent" ] json in
  let* action_text = field string_value fields "action" in
  let* action = action_of_name action_text in
  let* intent_json = member fields "intent" in
  let* intent = decode_intent_json intent_json in
  make_request ~action ~intent

let decode_request_json encoded =
  match Yojson.Safe.from_string encoded with
  | json -> decode_request_value json
  | exception Yojson.Json_error detail -> parse_error Malformed_request detail

let canonical_envelope_json ~transport request =
  `Assoc
    [ ("request", Yojson.Safe.from_string (canonical_request_json request));
      ("version", `Int 1);
      ("transport", `String (transport_name transport)) ]
  |> Yojson.Safe.to_string

let decode_envelope_json ~expected_transport encoded =
  let transport_of_name = function
    | "ocaml-api" -> Ok Ocaml_api
    | "cli" -> Ok Cli
    | "mcp" -> Ok Mcp
    | "zenoh" -> Ok Zenoh
    | value -> parse_error Malformed_request ("unknown transport: " ^ value)
  in
  match Yojson.Safe.from_string encoded with
  | exception Yojson.Json_error detail -> parse_error Malformed_request detail
  | json ->
      let* fields =
        object_fields ~expected:[ "request"; "version"; "transport" ] json
      in
      let* version = field int_value fields "version" in
      if version <> 1 then
        parse_error Malformed_request "unsupported dependability envelope version"
      else
      let* transport_text = field string_value fields "transport" in
      let* observed_transport = transport_of_name transport_text in
      if observed_transport <> expected_transport then
        parse_error Plane_mismatch "envelope transport disagrees with ingress"
      else
        let* request_json = member fields "request" in
        decode_request_value request_json

let cli_argv request =
  match request.action with
  | Verify_full ->
      [ "verify"; "--full"; "--require-complete"; "--intent-json";
        Dependability_intent.canonical_json request.intent ]
  | Verify_reliability ->
      [ "verify"; "--reliability"; "--intent-json";
        Dependability_intent.canonical_json request.intent ]

let decode_cli argv =
  if List.mem "invoke" argv then
    parse_error Generic_invoke_forbidden "generic Invoke is forbidden"
  else
    let argv = match argv with "dependability" :: rest -> rest | rest -> rest in
    match argv with
    | [ "verify"; "--full"; "--require-complete"; "--intent-json";
        encoded ] ->
        begin match Yojson.Safe.from_string encoded with
        | json ->
            let* intent = decode_intent_json json in
            make_request ~action:Verify_full ~intent
        | exception Yojson.Json_error detail ->
            parse_error Malformed_request detail
        end
    | [ "verify"; "--reliability"; "--intent-json"; encoded ] ->
        begin match Yojson.Safe.from_string encoded with
        | json ->
            let* intent = decode_intent_json json in
            make_request ~action:Verify_reliability ~intent
        | exception Yojson.Json_error detail ->
            parse_error Malformed_request detail
        end
    | _ -> parse_error Malformed_request "invalid dependability CLI arguments"

let mcp_method_name = "hermes_dependability_verify"

let string_schema = `Assoc [ ("type", `String "string") ]
let integer_schema = `Assoc [ ("type", `String "integer") ]
let boolean_schema = `Assoc [ ("type", `String "boolean") ]

let enum_schema values =
  `Assoc
    [ ("type", `String "string");
      ("enum", `List (List.map (fun value -> `String value) values)) ]

let array_schema items =
  `Assoc [ ("type", `String "array"); ("items", items) ]

let closed_object properties =
  `Assoc
    [ ("type", `String "object");
      ("properties", `Assoc properties);
      ("required", `List (List.map (fun (key, _) -> `String key) properties));
      ("additionalProperties", `Bool false) ]

let coordinate_schema =
  closed_object
    [ ("level", enum_schema [ "L0"; "L1"; "L2"; "L3"; "L4"; "L5"; "L6"; "LX" ]);
      ("phase", enum_schema [ "observe"; "orient"; "decide"; "act" ]) ]

let predicate_schema =
  let kind value = ("kind", enum_schema [ value ]) in
  `Assoc
    [ ("oneOf",
       `List
         [ closed_object [ kind "exit-zero" ];
           closed_object [ kind "no-signal" ];
           closed_object [ kind "no-matching-crash" ];
           closed_object
             [ kind "metric-at-least"; ("metric", string_schema);
               ("minimum", integer_schema) ] ]) ]

let criterion_schema =
  closed_object
    [ ("id", string_schema); ("description", string_schema);
      ("predicate", predicate_schema) ]

let schedule_schema =
  closed_object
    [ ("bounded_parallel_attempts", integer_schema);
      ("lane_count", integer_schema);
      ("permit_topology_digest", string_schema);
      ("sequential_oracle_attempts", integer_schema) ]

let policy_schema =
  closed_object
    [ ("attempts", integer_schema); ("confidence_ppm", integer_schema);
      ("maximum_failures", integer_schema);
      ("maximum_incident_rate_ppm", integer_schema);
      ("maximum_parallelism", integer_schema);
      ("minimum_overlap_gc_cycles", integer_schema);
      ("reliability_schedule", schedule_schema);
      ("per_child_timeout_ns", integer_schema);
      ("require_crash_window", boolean_schema);
      ("require_formal", boolean_schema);
      ("require_full_gate", boolean_schema) ]

let source_schema =
  closed_object
    [ ("authority_digest", string_schema); ("build_digest", string_schema);
      ("configuration_digest", string_schema);
      ("provenance_digest", string_schema);
      ("source_clean", boolean_schema); ("source_revision", string_schema) ]

let intent_schema =
  closed_object
    [ ("activity_id", string_schema);
      ("activity_path", array_schema coordinate_schema);
      ("criteria", array_schema criterion_schema);
      ("operation", enum_schema [ "verify-reliability"; "verify-full" ]);
      ("plane", enum_schema [ "control-plane"; "data-plane"; "both-planes" ]);
      ("policy", policy_schema); ("request_id", string_schema);
      ("run_id", string_schema); ("source", source_schema);
      ("target",
       enum_schema
         [ "sqlite.run-event-store"; "sqlite.sa-plan-store";
           "sqlite.ops-completion-history"; "sqlite.evidence-store" ]) ]

let mcp_schema =
  `Assoc
    [ ("name", `String mcp_method_name);
      ("description",
       `String
         "Verify_reliability or Verify_full using one canonical dependability intent");
      ("inputSchema",
       closed_object
         [ ("action", enum_schema [ "verify-reliability"; "verify-full" ]);
           ("intent", intent_schema) ]) ]

let decode_mcp ~method_name ~payload =
  if method_name <> mcp_method_name then
    Stdlib.Result.Error
      (diagnostic Unknown_action "unknown MCP method")
  else decode_request_json payload

let status_digest_valid value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let status_request_id_valid value =
  String.trim value <> ""
  && String.for_all
       (function
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' | ':' ->
             true
         | _ -> false)
       value

let make_status_query ~request_id ~intent_digest =
  if not (status_request_id_valid request_id) then
    parse_error Invalid_intent "status request id is invalid"
  else if not (status_digest_valid intent_digest) then
    parse_error Invalid_intent
      "status intent digest must be lowercase SHA-256"
  else
    Ok
      { status_request_id = request_id;
        status_intent_digest = intent_digest }

let canonical_status_query_json query =
  `Assoc
    [ ("intent_digest", `String query.status_intent_digest);
      ("request_id", `String query.status_request_id) ]
  |> Yojson.Safe.to_string

let mcp_status_method_name = "hermes_dependability_status"

let mcp_status_schema =
  `Assoc
    [ ("name", `String mcp_status_method_name);
      ("description",
       `String "Read one immutable dependability result by semantic intent digest");
      ("inputSchema",
       closed_object
         [ ("intent_digest", string_schema); ("request_id", string_schema) ]) ]

let decode_mcp_status ~method_name ~payload =
  if method_name <> mcp_status_method_name then
    parse_error Unknown_action "unknown MCP status method"
  else
    match Yojson.Safe.from_string payload with
    | exception Yojson.Json_error detail -> parse_error Malformed_request detail
    | json ->
        let* fields =
          object_fields ~expected:[ "intent_digest"; "request_id" ] json
        in
        let* intent_digest = field string_value fields "intent_digest" in
        let* request_id = field string_value fields "request_id" in
        make_status_query ~request_id ~intent_digest

let dispatch_mcp_status ~method_name ~payload ~current =
  let* status_query = decode_mcp_status ~method_name ~payload in
  let current_intent_digest = function
    | Success receipt -> Some receipt.intent_digest
    | Error failure -> failure.intent_digest
  in
  match current with
  | Some result
    when current_intent_digest result
         <> Some status_query.status_intent_digest ->
      parse_error Invalid_receipt "status snapshot belongs to another intent"
  | None | Some _ ->
      let current_digest =
        match current with
        | None -> `Null
        | Some (Success receipt) -> `String receipt.result_digest
        | Some (Error failure) -> `String failure.result_digest
      in
      let payload =
        `Assoc
          [ ("current_result_digest", current_digest);
            ("query",
             Yojson.Safe.from_string
               (canonical_status_query_json status_query)) ]
      in
      Ok
        { status_query; current_result = current;
          status_digest = sha256 (Yojson.Safe.to_string payload) }

let plane_name = function
  | Dependability_intent.Control_plane -> "control"
  | Dependability_intent.Data_plane -> "data"
  | Dependability_intent.Both_planes -> "both"

let zenoh_key request =
  String.concat "/"
    [ "hermes"; "v1"; "control"; "dependability";
      plane_name (Dependability_intent.plane request.intent);
      action_name request.action ]

let plane_name_of_intent intent =
  plane_name (Dependability_intent.plane intent)

let decode_zenoh ~key ~payload =
  match String.split_on_char '/' key with
  | [ "hermes"; "v1"; "control"; "dependability"; plane; action_text ] ->
      begin match action_of_name action_text, decode_request_json payload with
      | Error diagnostic, _ | _, Error diagnostic ->
          Stdlib.Result.Error diagnostic
      | Ok key_action, Ok request when key_action <> request.action ->
          Stdlib.Result.Error
            (diagnostic Plane_mismatch "Zenoh key action disagrees with payload")
      | Ok _, Ok request
        when plane <> plane_name_of_intent request.intent ->
          Stdlib.Result.Error
            (diagnostic Plane_mismatch "Zenoh key plane disagrees with payload")
      | Ok _, Ok request -> Ok request
      end
  | _ ->
      Stdlib.Result.Error
        (diagnostic Malformed_request "invalid Zenoh dependability key")

let verdict_name = function
  | Passed -> "passed"
  | Failed -> "failed"
  | Unavailable_observed -> "unavailable-observed"
  | Skipped -> "skipped"

let result_payload ~intent_digest ~action ~verdict ~diagnostic
    ~receipt_digest ~effect_digest ~readback_digest =
  `Assoc
    [ ("action", match action with None -> `Null | Some value -> `String (action_name value));
      ("diagnostic", diagnostic);
      ("effect_digest", `String effect_digest);
      ("intent_digest", match intent_digest with None -> `Null | Some value -> `String value);
      ("readback_digest", `String readback_digest);
      ("receipt_digest", `String receipt_digest);
      ("verdict", `String (verdict_name verdict)) ]

let diagnostic_json diagnostic =
  `Assoc
    [ ("code", `String (diagnostic_code_name diagnostic.code));
      ("coordinate",
       `Assoc
         [ ("level",
            `String
              (Ops_capability.string_of_level diagnostic.coordinate.level));
           ("phase",
            `String
              (Ops_capability.string_of_phase diagnostic.coordinate.phase)) ]);
      ("detail_digest", `String diagnostic.detail_digest);
      ("hazard_id", `String diagnostic.hazard_id);
      ("rca_origin", `String (Ops_capability.string_of_rca_origin diagnostic.rca_origin)) ]

let canonical_digest value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let valid_hazard_id value =
  String.trim value <> ""
  && String.for_all
       (function
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' | ':' ->
             true
         | _ -> false)
       value

let digests_are_canonical receipt_digest effect_digest readback_digest =
  List.for_all canonical_digest
    [ receipt_digest; effect_digest; readback_digest ]

let make_success ~intent ~receipt_digest ~effect_digest ~readback_digest =
  if not (digests_are_canonical receipt_digest effect_digest readback_digest)
  then
    Stdlib.Result.Error
      (diagnostic Invalid_receipt "receipt digests must be lowercase SHA-256")
  else match Dependability_intent.operation intent with
  | Dependability_intent.Prove_lifecycle ->
      Stdlib.Result.Error
        (diagnostic Invalid_intent "operation is not exposed by this surface")
  | (Dependability_intent.Verify_reliability
    | Dependability_intent.Verify_full) as operation ->
      let action =
        match operation with
        | Dependability_intent.Verify_reliability -> Verify_reliability
        | Dependability_intent.Verify_full -> Verify_full
        | Dependability_intent.Prove_lifecycle -> assert false
      in
      let intent_digest = Dependability_intent.digest intent in
      let payload =
        result_payload ~intent_digest:(Some intent_digest) ~action:(Some action)
          ~verdict:Passed ~diagnostic:`Null ~receipt_digest ~effect_digest
          ~readback_digest
      in
      Ok
        (Success
           { intent_digest; action; verdict = Passed; receipt_digest;
             effect_digest; readback_digest;
             result_digest = sha256 (Yojson.Safe.to_string payload) })

let make_failure ~intent ~verdict ~code ~detail ~coordinate ~rca_origin
    ~hazard_id ~receipt_digest ~effect_digest ~readback_digest =
  if verdict = Passed then
    Stdlib.Result.Error
      (diagnostic Invalid_receipt "an error carrier cannot have Passed verdict")
  else if String.trim detail = "" then
    Stdlib.Result.Error
      (diagnostic Invalid_receipt "diagnostic detail is empty")
  else if not (valid_hazard_id hazard_id) then
    Stdlib.Result.Error
      (diagnostic Invalid_receipt "diagnostic hazard id is invalid")
  else if not (digests_are_canonical receipt_digest effect_digest readback_digest)
  then
    Stdlib.Result.Error
      (diagnostic Invalid_receipt "receipt digests must be lowercase SHA-256")
  else
    let action_result =
      match Option.map Dependability_intent.operation intent with
      | None -> Ok None
      | Some Dependability_intent.Verify_reliability ->
          Ok (Some Verify_reliability)
      | Some Dependability_intent.Verify_full -> Ok (Some Verify_full)
      | Some Dependability_intent.Prove_lifecycle ->
          Stdlib.Result.Error
            (diagnostic Invalid_intent
               "operation is not exposed by this surface")
    in
    match action_result with
    | Stdlib.Result.Error _ as error -> error
    | Ok action ->
        let diagnostic =
          { code; detail_digest = sha256 detail; coordinate; rca_origin;
            hazard_id }
        in
        let intent_digest = Option.map Dependability_intent.digest intent in
        let payload =
          result_payload ~intent_digest ~action ~verdict
            ~diagnostic:(diagnostic_json diagnostic) ~receipt_digest
            ~effect_digest ~readback_digest
        in
        Ok
          (Error
             { intent_digest; action; verdict; diagnostic; receipt_digest;
               effect_digest; readback_digest;
               result_digest = sha256 (Yojson.Safe.to_string payload) })

let normalized_result_json = function
  | Success receipt ->
      `Assoc
        [ ("action", `String (action_name receipt.action));
          ("diagnostic", `Null);
          ("effect_digest", `String receipt.effect_digest);
          ("intent_digest", `String receipt.intent_digest);
          ("readback_digest", `String receipt.readback_digest);
          ("receipt_digest", `String receipt.receipt_digest);
          ("result_digest", `String receipt.result_digest);
          ("verdict", `String (verdict_name receipt.verdict)) ]
      |> Yojson.Safe.to_string
  | Error failure ->
      `Assoc
        [ ("action", match failure.action with
             | None -> `Null | Some value -> `String (action_name value));
          ("diagnostic", diagnostic_json failure.diagnostic);
          ("effect_digest", `String failure.effect_digest);
          ("intent_digest", match failure.intent_digest with
             | None -> `Null | Some value -> `String value);
          ("readback_digest", `String failure.readback_digest);
          ("receipt_digest", `String failure.receipt_digest);
          ("result_digest", `String failure.result_digest);
          ("verdict", `String (verdict_name failure.verdict)) ]
      |> Yojson.Safe.to_string

let result_identity = function
  | Success receipt -> receipt.result_digest
  | Error failure -> failure.result_digest

let result_agrees request = function
  | Success receipt ->
      receipt.intent_digest = semantic_digest request
      && receipt.action = request.action && receipt.verdict = Passed
  | Error failure ->
      failure.intent_digest = Some (semantic_digest request)
      && failure.action = Some request.action && failure.verdict <> Passed

let reject_mismatched_result request observed =
  let expected_digest = semantic_digest request in
  let rejected_digest = result_identity observed in
  let absent =
    sha256 ("invalid-result:" ^ expected_digest ^ ":" ^ rejected_digest)
  in
  match
    make_failure ~intent:(Some request.intent) ~verdict:Failed
      ~code:Invalid_receipt
      ~detail:
        ("result authority disagrees with request " ^ expected_digest ^ ":"
       ^ rejected_digest)
      ~coordinate:{ level = Ops_capability.L4; phase = Ops_capability.Act }
      ~rca_origin:Ops_capability.Implementation
      ~hazard_id:"HZ-SURFACE-RECEIPT-01" ~receipt_digest:absent
      ~effect_digest:absent ~readback_digest:absent
  with
  | Ok result -> result
  | Stdlib.Result.Error _ -> assert false

let validate_execution_result request observed =
  if result_agrees request observed then observed
  else reject_mismatched_result request observed

let dispatch_api ~execute request =
  let observed = execute request.intent in
  { transport = Ocaml_api;
    result = validate_execution_result request observed }

let rejected transport diagnostic =
  let absent = sha256 ("absent:" ^ diagnostic_code_name diagnostic.code) in
  let result =
    match
      make_failure ~intent:None ~verdict:Failed ~code:diagnostic.code
        ~detail:diagnostic.detail_digest ~coordinate:diagnostic.coordinate
        ~rca_origin:diagnostic.rca_origin ~hazard_id:diagnostic.hazard_id
        ~receipt_digest:absent ~effect_digest:absent ~readback_digest:absent
    with
    | Ok value -> value
    | Stdlib.Result.Error _ -> assert false
  in
  { transport; result }

let dispatch_decoded ~transport ~execute = function
  | Ok request ->
      let observed = execute request.intent in
      { transport; result = validate_execution_result request observed }
  | Stdlib.Result.Error diagnostic -> rejected transport diagnostic

let dispatch_cli ~execute argv =
  dispatch_decoded ~transport:Cli ~execute (decode_cli argv)

let dispatch_mcp ~execute ~method_name ~payload =
  dispatch_decoded ~transport:Mcp ~execute
    (decode_mcp ~method_name ~payload)

let dispatch_zenoh ~execute ~key ~payload () =
  dispatch_decoded ~transport:Zenoh ~execute (decode_zenoh ~key ~payload)
