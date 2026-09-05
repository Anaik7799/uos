open Dependability_intent
open Dependability_surface

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let get = function Ok value -> value | Error diagnostic ->
  failwith (diagnostic_code_name diagnostic.code)

let digest character = String.make 64 character

let source : source_authority =
  { source_revision = "0123456789abcdef";
    source_clean = true;
    configuration_digest = digest 'c';
    authority_digest = digest 'a';
    build_digest = digest 'b';
    provenance_digest = digest 'd' }

let coordinate phase : Ops_capability.coordinate =
  { level = Ops_capability.L2; phase }

let activity_path =
  [ coordinate Ops_capability.Observe; coordinate Ops_capability.Orient;
    coordinate Ops_capability.Decide; coordinate Ops_capability.Act;
    coordinate Ops_capability.Observe ]

let criterion id predicate =
  match make_criterion ~id ~description:("criterion " ^ id) ~predicate with
  | Ok value -> value
  | Error message -> failwith message

let policy () =
  let reliability_schedule =
    match
      make_reliability_schedule ~sequential_oracle_attempts:32
        ~bounded_parallel_attempts:268 ~lane_count:5
    with
    | Ok value -> value
    | Error message -> failwith message
  in
  match
    make_policy ~confidence_ppm:950_000 ~maximum_incident_rate_ppm:10_000
      ~attempts:300 ~per_child_timeout_ns:30_000_000_000L
      ~maximum_failures:0 ~minimum_overlap_gc_cycles:1 ~reliability_schedule
      ~require_formal:true ~require_crash_window:true ~require_full_gate:true ()
  with
  | Ok value -> value
  | Error message -> failwith message

let intent_with ~request_id ~activity_id ~run_id operation =
  match
    make ~request_id ~activity_id ~run_id ~operation ~activity_path
      ~target:Sqlite_run_event_store ~plane:Both_planes ~policy:(policy ())
      ~criteria:
        [ criterion "exit-zero" Exit_zero;
          criterion "no-signal" No_signal;
          criterion "overlap" (Metric_at_least ("gc.overlap", 1L)) ]
      ~source
  with
  | Ok value -> value
  | Error message -> failwith message

let intent operation =
  intent_with ~request_id:"surface-request-001"
    ~activity_id:"dependability.sqlite.surface" ~run_id:"surface-run-001"
    operation

let request action = make_request ~action ~intent:(intent (operation_of_action action)) |> get

let replace_once ~needle ~replacement text =
  let needle_length = String.length needle in
  let rec locate index =
    if index + needle_length > String.length text then None
    else if String.sub text index needle_length = needle then Some index
    else locate (index + 1)
  in
  match locate 0 with
  | None -> failwith ("missing mutation needle: " ^ needle)
  | Some index ->
      String.sub text 0 index ^ replacement
      ^ String.sub text (index + needle_length)
          (String.length text - index - needle_length)

let normalized observation = normalized_result_json observation.result

let dispatch_all execute request =
  [ dispatch_api ~execute request;
    dispatch_cli ~execute (cli_argv request);
    dispatch_mcp ~execute ~method_name:mcp_method_name
      ~payload:(canonical_request_json request);
    dispatch_zenoh ~execute ~key:(zenoh_key request)
      ~payload:(canonical_request_json request) () ]

let all_equal = function
  | [] -> false
  | first :: rest -> List.for_all (String.equal first) rest

let has_error_code expected = function
  | Stdlib.Result.Error diagnostic -> diagnostic.code = expected
  | Ok _ -> false

let independent_request_json action intent =
  `Assoc
    [ ("action", `String (action_name action));
      ("intent",
       Yojson.Safe.from_string (Dependability_intent.canonical_json intent)) ]
  |> Yojson.Safe.to_string

let independent_envelope_json transport request_json =
  `Assoc
    [ ("request", Yojson.Safe.from_string request_json);
      ("version", `Int 1);
      ("transport", `String (transport_name transport)) ]
  |> Yojson.Safe.to_string

let json_member key = function
  | `Assoc fields -> List.assoc_opt key fields
  | _ -> None

let schema_property key schema =
  match json_member "properties" schema with
  | Some (`Assoc properties) -> List.assoc_opt key properties
  | _ -> None

let closed_object_schema schema =
  match
    json_member "type" schema,
    json_member "additionalProperties" schema,
    json_member "required" schema,
    json_member "properties" schema
  with
  | Some (`String "object"), Some (`Bool false), Some (`List required),
    Some (`Assoc properties) ->
      let required =
        required
        |> List.filter_map (function `String value -> Some value | _ -> None)
        |> List.sort_uniq String.compare
      in
      required = (List.map fst properties |> List.sort_uniq String.compare)
  | _ -> false

let () =
  let full = request Verify_full in
  let reliability = request Verify_reliability in
  let decoded = decode_request_json (canonical_request_json full) |> get in
  check "S1 canonical request roundtrip reconstructs the private intent"
    (action decoded = Verify_full
     && String.equal (semantic_digest decoded) (semantic_digest full)
     && String.equal (canonical_request_json decoded)
          (canonical_request_json full));
  check "S2 the surface semantic digest is exactly the intent digest"
    (String.equal (semantic_digest full)
       (Dependability_intent.digest (intent_of_request full))
     && String.equal (semantic_digest reliability)
          (Dependability_intent.digest (intent_of_request reliability)));

  let success_execute intent =
    make_success ~intent ~receipt_digest:(digest '1')
      ~effect_digest:(digest '2') ~readback_digest:(digest '3') |> get
  in
  let successes = dispatch_all success_execute full in
  check "S3 OCaml CLI MCP and Zenoh successes normalize identically"
    (successes |> List.map normalized |> all_equal);
  check "S4 transport is retained outside normalized semantic identity"
    (List.map (fun observation -> observation.transport) successes
     = [ Ocaml_api; Cli; Mcp; Zenoh ]);
  check "S5 passed receipts preserve exact verdict and all authority digests"
    (List.for_all
       (fun observation ->
         match observation.result with
         | Success receipt ->
             receipt.verdict = Passed
             && receipt.receipt_digest = digest '1'
             && receipt.effect_digest = digest '2'
             && receipt.readback_digest = digest '3'
         | Error _ -> false)
       successes);

  let failure_execute intent =
    make_failure ~intent:(Some intent) ~verdict:Unavailable_observed
      ~code:Dispatch_unavailable ~detail:"Task 7 bridge is unavailable"
      ~coordinate:{ level = Ops_capability.L4; phase = Ops_capability.Act }
      ~rca_origin:Ops_capability.Control ~hazard_id:"HZ-SURFACE-BRIDGE-01"
      ~receipt_digest:(digest '4') ~effect_digest:(digest '5')
      ~readback_digest:(digest '6') |> get
  in
  let failures = dispatch_all failure_execute full in
  check "S6 OCaml CLI MCP and Zenoh errors normalize identically"
    (failures |> List.map normalized |> all_equal);
  check "S7 normalized errors retain exact diagnostic and authority fields"
    (List.for_all
       (fun observation ->
         match observation.result with
         | Success _ -> false
         | Error failure ->
             failure.verdict = Unavailable_observed
             && failure.diagnostic.code = Dispatch_unavailable
             && String.length failure.diagnostic.detail_digest = 64
             && failure.diagnostic.coordinate
                = { level = Ops_capability.L4; phase = Ops_capability.Act }
             && failure.diagnostic.rca_origin = Ops_capability.Control
             && failure.diagnostic.hazard_id = "HZ-SURFACE-BRIDGE-01"
             && failure.receipt_digest = digest '4'
             && failure.effect_digest = digest '5'
             && failure.readback_digest = digest '6')
       failures);

  let calls = ref 0 in
  let recording_execute intent =
    incr calls;
    success_execute intent
  in
  ignore (dispatch_api ~execute:recording_execute full);
  check "S8 one admitted request makes exactly one recording-dispatch call"
    (!calls = 1);

  check "S9 CLI emits and accepts the required full verification alias"
    (match cli_argv full with
     | "verify" :: "--full" :: "--require-complete" :: _ ->
         Result.is_ok (decode_cli (cli_argv full))
     | _ -> false);
  check "S10 reliability is a distinct closed CLI action"
    (action (decode_cli (cli_argv reliability) |> get) = Verify_reliability);
  check "S11 MCP owns one dedicated closed method and schema"
    (mcp_method_name = "hermes_dependability_verify"
     && Result.is_ok
          (decode_mcp ~method_name:mcp_method_name
             ~payload:(canonical_request_json full))
     && Result.is_error
          (decode_mcp ~method_name:"hermes_completion"
             ~payload:(canonical_request_json full))
     && String.contains (Yojson.Safe.to_string mcp_schema) 'V');

  let request_json = canonical_request_json full in
  let unknown_field =
    replace_once ~needle:"{\"action\""
      ~replacement:"{\"raw_sql\":\"select 1\",\"action\"" request_json
  in
  check "S12 malformed and unknown fields fail before dispatch"
    (Result.is_error (decode_request_json "{")
     && Result.is_error (decode_request_json unknown_field));
  let unknown_action =
    replace_once ~needle:"verify-full" ~replacement:"destroy" request_json
  in
  check "S13 unknown actions fail closed"
    (Result.is_error (decode_request_json unknown_action));
  let invoke =
    replace_once ~needle:"verify-full" ~replacement:"invoke" request_json
  in
  check "S14 generic Invoke is rejected on every textual ingress"
    (Result.is_error (decode_request_json invoke)
     && Result.is_error
          (decode_cli [ "verify"; "invoke"; "--intent-json";
                        Dependability_intent.canonical_json (intent Verify_full) ])
     && Result.is_error
          (decode_mcp ~method_name:mcp_method_name ~payload:invoke)
     && Result.is_error
          (decode_zenoh
             ~key:"hermes/v1/control/dependability/both/invoke"
             ~payload:request_json));
  let unknown_target =
    replace_once ~needle:"sqlite.run-event-store"
      ~replacement:"sqlite.unknown-store" request_json
  in
  check "S15 unknown targets fail closed"
    (Result.is_error (decode_request_json unknown_target));
  check "S16 Zenoh versioned key plane and action must agree with its payload"
    (Result.is_ok
       (decode_zenoh ~key:(zenoh_key full) ~payload:request_json)
     && Result.is_error
          (decode_zenoh
             ~key:"hermes/v1/control/dependability/data/verify-full"
             ~payload:request_json)
     && Result.is_error
          (decode_zenoh
             ~key:"hermes/v1/control/dependability/both/verify-reliability"
             ~payload:request_json));
  check "S17 transport mutation changes only envelope identity"
    (let semantic = semantic_digest full in
     let envelopes =
       [ Ocaml_api; Cli; Mcp; Zenoh ]
       |> List.map (fun transport -> canonical_envelope_json ~transport full)
     in
     List.length (List.sort_uniq String.compare envelopes) = 4
     && List.for_all
          (fun transport ->
            let decoded =
              decode_envelope_json ~expected_transport:transport
                (canonical_envelope_json ~transport full) |> get
            in
            String.equal semantic (semantic_digest decoded))
          [ Ocaml_api; Cli; Mcp; Zenoh ]);
  check "S18 digest and verdict constructors reject noncanonical authority"
    (Result.is_error
       (make_success ~intent:(intent Verify_full)
          ~receipt_digest:(String.make 64 'A') ~effect_digest:(digest '2')
          ~readback_digest:(digest '3'))
     && Result.is_error
          (make_failure ~intent:(Some (intent Verify_full)) ~verdict:Passed
             ~code:Invalid_receipt ~detail:"impossible success error"
             ~coordinate:{ level = Ops_capability.L4; phase = Ops_capability.Act }
             ~rca_origin:Ops_capability.Implementation
             ~hazard_id:"HZ-SURFACE-RECEIPT-01"
             ~receipt_digest:(digest '1') ~effect_digest:(digest '2')
             ~readback_digest:(digest '3')));

  let cold_intent =
    intent_with ~request_id:"surface-request-cold-002"
      ~activity_id:"dependability.sqlite.surface.cold"
      ~run_id:"surface-run-cold-002" Verify_full
  in
  let cold_json = independent_request_json Verify_full cold_intent in
  check "S19 canonical bytes decode without prior in-process registration"
    (match decode_request_json cold_json with
     | Ok decoded ->
         action decoded = Verify_full
         && String.equal (semantic_digest decoded)
              (Dependability_intent.digest cold_intent)
         && String.equal (canonical_request_json decoded) cold_json
     | Stdlib.Result.Error _ -> false);
  check "S20 cold CLI MCP and Zenoh codecs reconstruct the same intent"
    (let cli =
       decode_cli
         [ "verify"; "--full"; "--require-complete"; "--intent-json";
           Dependability_intent.canonical_json cold_intent ]
     in
     let mcp = decode_mcp ~method_name:mcp_method_name ~payload:cold_json in
     let zenoh =
       decode_zenoh
         ~key:"hermes/v1/control/dependability/both/verify-full"
         ~payload:cold_json
     in
     match cli, mcp, zenoh with
     | Ok cli, Ok mcp, Ok zenoh ->
         List.for_all
           (fun decoded ->
             String.equal (semantic_digest decoded)
               (Dependability_intent.digest cold_intent))
           [ cli; mcp; zenoh ]
     | _ -> false);
  check "S21 cold envelopes bind explicit transport and remain restart-decodable"
    (List.for_all
       (fun transport ->
         let encoded = independent_envelope_json transport cold_json in
         match decode_envelope_json ~expected_transport:transport encoded with
         | Ok decoded ->
             String.equal (semantic_digest decoded)
               (Dependability_intent.digest cold_intent)
         | Stdlib.Result.Error _ -> false)
       [ Ocaml_api; Cli; Mcp; Zenoh ]);
  let nested_unknown =
    replace_once ~needle:"{\"activity_id\""
      ~replacement:"{\"raw_path\":\"/tmp/injected\",\"activity_id\""
      cold_json
  in
  check "S22 structural decoder distinguishes unknown top and nested fields"
    (has_error_code Unknown_field (decode_request_json unknown_field)
     && has_error_code Unknown_field (decode_request_json nested_unknown));
  let cold_destroy =
    replace_once ~needle:"verify-full" ~replacement:"destroy" cold_json
  in
  let cold_invoke =
    replace_once ~needle:"verify-full" ~replacement:"invoke" cold_json
  in
  let cold_target =
    replace_once ~needle:"sqlite.run-event-store"
      ~replacement:"sqlite.unknown-store" cold_json
  in
  check "S23 structural decoder classifies action target and duplicate failures"
    (has_error_code Unknown_action (decode_request_json cold_destroy)
     && has_error_code Generic_invoke_forbidden
          (decode_request_json cold_invoke)
     && has_error_code Unknown_target (decode_request_json cold_target)
     && has_error_code Malformed_request
          (decode_request_json
             "{\"action\":\"verify-full\",\"action\":\"verify-full\",\"intent\":{}}"));
  let normalized_failure verdict coordinate =
    make_failure ~intent:(Some (intent Verify_full)) ~verdict
      ~code:Invalid_receipt ~detail:"normalized failure witness"
      ~coordinate ~rca_origin:Ops_capability.Implementation
      ~hazard_id:"HZ-SURFACE-NORMALIZATION-01"
      ~receipt_digest:(digest '7') ~effect_digest:(digest '8')
      ~readback_digest:(digest '9') |> get
  in
  let failed_result =
    normalized_failure Failed
      { level = Ops_capability.L4; phase = Ops_capability.Act }
  in
  let unavailable_result =
    normalized_failure Unavailable_observed
      { level = Ops_capability.L4; phase = Ops_capability.Act }
  in
  let skipped_result =
    normalized_failure Skipped
      { level = Ops_capability.L4; phase = Ops_capability.Act }
  in
  let rendered_verdict result =
    match Yojson.Safe.from_string (normalized_result_json result) with
    | `Assoc fields ->
        begin match List.assoc_opt "verdict" fields with
        | Some (`String value) -> Some value
        | _ -> None
        end
    | _ -> None
  in
  check "S24 normalized failure identity preserves the exact closed verdict"
    (rendered_verdict failed_result = Some "failed"
     && rendered_verdict unavailable_result = Some "unavailable-observed"
     && rendered_verdict skipped_result = Some "skipped"
     && List.length
          (List.sort_uniq String.compare
             (List.map normalized_result_json
                [ failed_result; unavailable_result; skipped_result ]))
        = 3);
  let coordinate_mutant =
    normalized_failure Failed
      { level = Ops_capability.L3; phase = Ops_capability.Orient }
  in
  let failure_digest = function
    | Error failure -> failure.result_digest
    | Success _ -> assert false
  in
  let rendered_coordinate result =
    match Yojson.Safe.from_string (normalized_result_json result) with
    | `Assoc result_fields ->
        begin match List.assoc_opt "diagnostic" result_fields with
        | Some (`Assoc diagnostic_fields) ->
            begin match List.assoc_opt "coordinate" diagnostic_fields with
            | Some (`Assoc coordinate_fields) ->
                begin match
                  List.assoc_opt "level" coordinate_fields,
                  List.assoc_opt "phase" coordinate_fields
                with
                | Some (`String level), Some (`String phase) ->
                    Some (level, phase)
                | _ -> None
                end
            | _ -> None
            end
        | _ -> None
        end
    | _ -> None
  in
  check "S25 normalized failure digest binds the full fractal coordinate"
    (failure_digest failed_result <> failure_digest coordinate_mutant
     && rendered_coordinate failed_result = Some ("L4", "act")
     && rendered_coordinate coordinate_mutant = Some ("L3", "orient"));
  let mismatch_calls = ref 0 in
  let mismatched_execute _ =
    incr mismatch_calls;
    make_success ~intent:(intent Verify_reliability)
      ~receipt_digest:(digest '1') ~effect_digest:(digest '2')
      ~readback_digest:(digest '3') |> get
  in
  let mismatch_observations = dispatch_all mismatched_execute full in
  let missing_intent_execute _ =
    incr mismatch_calls;
    make_failure ~intent:None ~verdict:Unavailable_observed
      ~code:Dispatch_unavailable ~detail:"unbound backend result"
      ~coordinate:{ level = Ops_capability.L4; phase = Ops_capability.Act }
      ~rca_origin:Ops_capability.Control ~hazard_id:"HZ-SURFACE-BRIDGE-01"
      ~receipt_digest:(digest '4') ~effect_digest:(digest '5')
      ~readback_digest:(digest '6') |> get
  in
  let missing_intent_observation =
    dispatch_api ~execute:missing_intent_execute full
  in
  let rejected_for_request observation =
    match observation.result with
    | Success _ -> false
    | Error failure ->
        failure.verdict = Failed
        && failure.diagnostic.code = Invalid_receipt
        && failure.intent_digest = Some (semantic_digest full)
        && failure.action = Some Verify_full
  in
  check "S26 dispatcher rejects wrong or absent result authority without retry"
    (List.for_all rejected_for_request mismatch_observations
     && rejected_for_request missing_intent_observation
     && !mismatch_calls = 5
     && mismatch_observations |> List.map normalized |> all_equal);
  check "S27 MCP verify schema is recursively closed and decoder-correspondent"
    (match json_member "inputSchema" mcp_schema with
     | Some input when closed_object_schema input ->
         begin match schema_property "intent" input with
         | Some intent_schema when closed_object_schema intent_schema ->
             begin match
               schema_property "policy" intent_schema,
               schema_property "source" intent_schema,
               schema_property "activity_path" intent_schema,
               schema_property "criteria" intent_schema
             with
             | Some policy_schema, Some source_schema,
               Some (`Assoc activity_fields), Some (`Assoc criteria_fields) ->
                 let item_schema fields = List.assoc_opt "items" fields in
                 closed_object_schema policy_schema
                 && closed_object_schema source_schema
                 && (match schema_property "reliability_schedule" policy_schema with
                     | Some schedule_schema -> closed_object_schema schedule_schema
                     | None -> false)
                 && (match item_schema activity_fields with
                     | Some coordinate_schema ->
                         closed_object_schema coordinate_schema
                     | None -> false)
                 && (match item_schema criteria_fields with
                     | Some criterion_schema -> closed_object_schema criterion_schema
                     | None -> false)
             | _ -> false
             end
         | _ -> false
         end
     | _ -> false);
  check "S28 canonical envelope requires explicit version one"
    (let encoded = canonical_envelope_json ~transport:Mcp full in
     match Yojson.Safe.from_string encoded with
     | `Assoc fields ->
         List.assoc_opt "version" fields = Some (`Int 1)
         && Result.is_ok (decode_envelope_json ~expected_transport:Mcp encoded)
         && has_error_code Malformed_request
              (decode_envelope_json ~expected_transport:Mcp
                 (replace_once ~needle:"\"version\":1"
                    ~replacement:"\"version\":2" encoded))
     | _ -> false);
  let status_query =
    make_status_query ~request_id:"surface-status-001"
      ~intent_digest:(semantic_digest full) |> get
  in
  let status_payload = canonical_status_query_json status_query in
  let effect_calls_before_status = !mismatch_calls in
  let status_observation =
    dispatch_mcp_status ~method_name:mcp_status_method_name
      ~payload:status_payload ~current:(Some (success_execute (intent Verify_full)))
    |> get
  in
  check "S29 status is a separate closed read-only MCP projection"
    (mcp_status_method_name = "hermes_dependability_status"
     && mcp_status_method_name <> mcp_method_name
     && (match json_member "inputSchema" mcp_status_schema with
         | Some schema -> closed_object_schema schema
         | None -> false)
     && Result.is_ok
          (decode_mcp_status ~method_name:mcp_status_method_name
             ~payload:status_payload)
     && Result.is_error
          (decode_mcp_status ~method_name:mcp_method_name
             ~payload:status_payload)
     && status_observation.status_query.status_request_id
        = "surface-status-001"
     && status_observation.current_result <> None
     && String.length status_observation.status_digest = 64
     && !mismatch_calls = effect_calls_before_status);

  Printf.printf "dependability_surface: %d passed, %d failed\n" !passed !failed;
  let self = Suite_telemetry.observe ~suite:"test_dependability_surface" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_dependability_core; Stanza.hermes_dependability_sqlite; Stanza.hermes_dependability_solver; Stanza.hermes_dependability_process; Stanza.hermes_dependability_topology ]);
  exit (Suite_telemetry.exit_code self)
