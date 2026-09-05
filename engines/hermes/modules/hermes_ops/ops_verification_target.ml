type status = Passed | Failed | Skipped
type availability = Available | Unavailable

type capture =
  | Executed of { exit_code : int; output : string }
  | Executable_unavailable of { executable : string; reason : string }

type run_capture = Run_topology.action_work -> capture

type observation = {
  action_id : string;
  action_digest : string;
  status : status;
  availability : availability;
  exit_code : int option;
  output : string;
  output_bytes : int;
  output_digest : string;
  output_truncated : bool;
}

type diagnostic_code =
  | Invalid_activity
  | Invalid_prepared_request
  | Unsupported_work
  | Capture_failure
  | Invalid_observation

type diagnostic = {
  code : diagnostic_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
}

type registration = {
  registry : Run_effect_authority.target_registry;
  observations : (string, observation) Hashtbl.t;
  observations_mutex : Mutex.t;
}

let target_registry registration = registration.registry

let maximum_observation_output_bytes = 4096

let coordinate =
  { Ops_capability.level = Ops_capability.L2; phase = Ops_capability.Act }

let diagnostic code message =
  { code; message; coordinate; rca_origin = Ops_capability.Control;
    hazard_id = "HZ-OPS-VERIFICATION-TARGET-01" }

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let digest_fields fields =
  fields
  |> List.map (fun field -> Printf.sprintf "%d:%s" (String.length field) field)
  |> String.concat ""
  |> sha256

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

let with_mutex mutex body =
  Mutex.lock mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock mutex) body

let status_string = function
  | Passed -> "passed" | Failed -> "failed" | Skipped -> "skipped"

let availability_string = function
  | Available -> "available" | Unavailable -> "unavailable"

let bounded_output output =
  let output_bytes = String.length output in
  let output_truncated = output_bytes > maximum_observation_output_bytes in
  let bounded =
    if output_truncated then String.sub output 0 maximum_observation_output_bytes
    else output
  in
  (bounded, output_bytes, sha256 output, output_truncated)

let observation ~action_id ~action_digest ~status ~availability ~exit_code
    full_output =
  let output, output_bytes, output_digest, output_truncated =
    bounded_output full_output
  in
  { action_id; action_digest; status; availability; exit_code; output;
    output_bytes; output_digest; output_truncated }

let observation_json (item : observation) =
  `Assoc
    [ ("action_digest", `String item.action_digest);
      ("action_id", `String item.action_id);
      ("availability", `String (availability_string item.availability));
      ("exit_code",
       match item.exit_code with None -> `Null | Some code -> `Int code);
      ("output", `String item.output);
      ("output_bytes", `Int item.output_bytes);
      ("output_digest", `String item.output_digest);
      ("output_truncated", `Bool item.output_truncated);
      ("status", `String (status_string item.status));
      ("version", `String "ops-verification-observation-v1") ]

let observation_bytes item = Run_model.canonical_string (observation_json item)

let exact_field_names expected fields =
  let observed = List.map fst fields |> List.sort String.compare in
  observed = List.sort String.compare expected

let field name fields = List.assoc_opt name fields

let string_field name fields =
  match field name fields with Some (`String value) -> Some value | _ -> None

let string_list_field name fields =
  match field name fields with
  | Some (`List values) ->
      let strings =
        List.filter_map
          (function `String value -> Some value | _ -> None)
          values
      in
      if List.length strings = List.length values then Some strings else None
  | _ -> None

let exact_canonical_json bytes =
  try
    let json = Yojson.Safe.from_string bytes in
    match Run_model.canonical_string json with
    | Ok canonical when String.equal canonical bytes -> Ok json
    | Ok _ -> Error "request bytes are not canonical JSON"
    | Error message -> Error message
  with Yojson.Json_error message -> Error message

let string_of_effect_kind = Run_topology.effect_kind_id

let string_of_verification_profile = function
  | Run_topology.Verification_fast -> "fast"
  | Run_topology.Verification_full -> "full"

let projected_work_fields = function
  | Run_topology.Topology_gate ->
      ([ "work_kind" ], fun fields ->
         string_field "work_kind" fields = Some "topology-gate")
  | Run_topology.Repository_build { profile; build_command } ->
      ([ "work_kind"; "profile_id"; "build_command" ], fun fields ->
         string_field "work_kind" fields = Some "repository-build"
         && string_field "profile_id" fields
            = Some (string_of_verification_profile profile)
         && string_field "build_command" fields = Some build_command)
  | Run_topology.Repository_verification_suite
      { profile; suite_id; executable } ->
      ([ "work_kind"; "profile_id"; "suite_id"; "executable" ],
       fun fields ->
         string_field "work_kind" fields
           = Some "repository-verification-suite"
         && string_field "profile_id" fields
            = Some (string_of_verification_profile profile)
         && string_field "suite_id" fields = Some suite_id
         && string_field "executable" fields = Some executable)
  | work ->
      ([ "work_kind"; "work_id" ], fun fields ->
         string_field "work_kind" fields = Some "closed-task7a-work"
         && string_field "work_id" fields
            = Some (Run_topology.action_work_id work))

let closed_work (action : Run_topology.declarative_action) =
  match action.work with
  | Run_topology.Repository_build
      { profile = Run_topology.Verification_full; build_command }
    when String.equal action.stable_id "action.verify-repository.build"
         && String.equal build_command "dune build --pkg=disabled 2>&1" ->
      Ok action.work
  | Run_topology.Repository_verification_suite
      { profile = Run_topology.Verification_full; suite_id; executable }
    when valid_identifier suite_id && valid_identifier executable
         && String.equal action.stable_id
              ("action.verify-repository.suite." ^ suite_id) ->
      Ok action.work
  | Run_topology.Topology_gate
  | Run_topology.Repository_build _
  | Run_topology.Repository_verification_suite _ ->
      Error "action work is not a closed full repository verification action"
  | work ->
      Error
        ("action work belongs to another closed target: "
         ^ Run_topology.action_work_id work)

let prepared_action declaration (request : Run_effect_authority.request) =
  if request.effect_kind <> Run_topology.Verification_suite_execution then
    Error "effect request kind differs from repository verification"
  else
    match exact_canonical_json request.request_bytes with
    | Error message -> Error message
    | Ok (`Assoc fields) ->
        begin match string_field "action_id" fields with
        | None -> Error "prepared request action identity is absent"
        | Some action_id ->
          begin match
            List.find_opt
              (fun (action : Run_topology.declarative_action) ->
                String.equal action.stable_id action_id)
              declaration.Run_topology.actions
          with
          | None -> Error "prepared request action is not admitted"
          | Some action ->
            let work_names, work_matches = projected_work_fields action.work in
            let expected_fields =
              [ "activity_id"; "activity_digest";
                "topology_authority_digest"; "action_id";
                "assigned_agent_id"; "command_id"; "dependency_ids";
                "dependency_input_digest"; "execution_identity";
                "action_digest"; "preparation_id"; "target_component_id";
                "effect_kind"; "version" ] @ work_names
            in
            if not (exact_field_names expected_fields fields) then
              Error "prepared request field denominator differs"
            else begin match
            string_field "activity_id" fields,
            string_field "activity_digest" fields,
            string_field "topology_authority_digest" fields,
            string_field "action_id" fields,
            string_field "assigned_agent_id" fields,
            string_field "command_id" fields,
            string_list_field "dependency_ids" fields,
            string_field "dependency_input_digest" fields,
            string_field "execution_identity" fields,
            string_field "action_digest" fields,
            string_field "preparation_id" fields,
            string_field "target_component_id" fields,
            string_field "effect_kind" fields,
            string_field "version" fields
          with
          | Some activity_id, Some activity_digest,
            Some topology_authority_digest, Some _action_id,
            Some assigned_agent_id, Some command_id,
            Some dependency_ids, Some dependency_input_digest,
            Some execution_identity, Some action_digest, Some preparation_id,
            Some target_component_id, Some effect_kind, Some version ->
                  let expected_action_digest = Run_topology.action_digest_of action in
                  if not
                      (String.equal activity_id declaration.stable_id
                       && String.equal activity_digest
                            (Run_topology.activity_digest_of declaration)
                       && String.equal topology_authority_digest
                            Run_topology.source_digest
                       && String.equal assigned_agent_id action.assigned_agent_id
                       && String.equal command_id action.command_id
                       && dependency_ids = action.dependency_ids
                       && valid_digest dependency_input_digest
                       && valid_digest execution_identity
                       && String.equal action_digest expected_action_digest
                       && String.equal preparation_id action.preparation_id
                       && String.equal target_component_id
                            action.target_component_id
                       && String.equal effect_kind
                            (string_of_effect_kind action.effect_kind)
                       && String.equal version "run-swarm-preparation-v3"
                       && work_matches fields)
                  then Error "prepared request differs from its admitted action"
                  else
                    begin match closed_work action with
                    | Ok work -> Ok (action, work)
                    | Error message -> Error message
                    end
          | _ -> Error "prepared request contains a field of the wrong type"
          end
          end
        end
    | Ok _ -> Error "prepared request must be a JSON object"

let make_registry ~(activity : Run_topology.admitted_activity) ~run_capture =
  let declaration = Run_topology.admitted_declaration activity in
  if not (String.equal declaration.stable_id "activity.verify-repository") then
    Error
      [ diagnostic Invalid_activity
          "only activity.verify-repository may register this target" ]
  else
    let target_id = declaration.target_component_id in
    let accepted_kinds = [ Run_topology.Verification_suite_execution ] in
    let authority_digest =
      Run_effect_authority.expected_target_authority_digest ~activity
        ~target_id ~accepted_kinds
    in
    let receipts : (string, Run_effect_authority.target_receipt) Hashtbl.t =
      Hashtbl.create (List.length declaration.actions)
    in
    let observations : (string, observation) Hashtbl.t =
      Hashtbl.create (List.length declaration.actions)
    in
    let receipts_mutex = Mutex.create () in
    let apply_once ~idempotency_key
        (request : Run_effect_authority.request) =
      with_mutex receipts_mutex (fun () ->
        match Hashtbl.find_opt receipts idempotency_key with
        | Some receipt when String.equal receipt.request_digest
                              request.Run_effect_authority.request_digest ->
            Ok receipt
        | Some _ -> Error "idempotency key is already bound to another request"
        | None ->
            begin match prepared_action declaration request with
            | Error message -> Error message
            | Ok (action, work) ->
                let capture =
                  try Ok (run_capture work)
                  with exn -> Error (Printexc.to_string exn)
                in
                begin match capture with
                | Error message -> Error ("capture raised: " ^ message)
                | Ok capture ->
                    let observed =
                      match capture with
                      | Executed { exit_code; output } ->
                          observation ~action_id:action.stable_id
                            ~action_digest:(Run_topology.action_digest_of action)
                            ~status:(if exit_code = 0 then Passed else Failed)
                            ~availability:Available ~exit_code:(Some exit_code)
                            output
                      | Executable_unavailable { executable; reason } ->
                          let expected_executable =
                            match work with
                            | Run_topology.Repository_build { build_command; _ } ->
                                build_command
                            | Run_topology.Repository_verification_suite
                                { executable; _ } -> executable
                            | work ->
                                ignore (Run_topology.action_work_id work);
                                ""
                          in
                          if not (String.equal executable expected_executable)
                          then
                            observation ~action_id:"" ~action_digest:""
                              ~status:Skipped ~availability:Unavailable
                              ~exit_code:None "unavailable executable differs"
                          else
                            observation ~action_id:action.stable_id
                              ~action_digest:
                                (Run_topology.action_digest_of action)
                              ~status:Skipped ~availability:Unavailable
                              ~exit_code:None reason
                    in
                    if not (String.equal observed.action_id action.stable_id)
                    then Error "capture unavailable executable differs from work"
                    else
                      begin match observation_bytes observed with
                      | Error message -> Error message
                      | Ok observation_bytes ->
                          let receipt_id =
                            digest_fields
                              [ "ops-verification-evidence-receipt-v1";
                                idempotency_key; request.request_digest;
                                observed.action_digest ]
                          in
                          let evidence_disposition =
                            match observed.availability with
                            | Available ->
                                Run_effect_authority.Evidence_succeeded
                            | Unavailable ->
                                Run_effect_authority.Evidence_unavailable
                          in
                          begin match
                            Run_effect_authority.make_redacted_evidence
                              ~receipt_id
                              ~evidence_digest:(sha256 observation_bytes)
                              ~disposition:evidence_disposition
                          with
                          | Error issue -> Error issue.bytes
                          | Ok evidence ->
                              begin match
                                Run_effect_authority.make_target_receipt
                                  ~idempotency_key ~request
                                  ~target_authority_digest:authority_digest
                                  ~disposition:
                                    Run_effect_authority.First_applied
                                  ~evidence
                              with
                              | Error issue -> Error issue.bytes
                              | Ok receipt ->
                                  Hashtbl.add receipts idempotency_key receipt;
                                  Hashtbl.add observations receipt_id observed;
                                  Ok receipt
                              end
                          end
                      end
                end
            end)
    in
    let query ~idempotency_key =
      with_mutex receipts_mutex (fun () ->
        Ok (Hashtbl.find_opt receipts idempotency_key))
    in
    match
      Run_effect_authority.register_target ~activity ~target_id
        ~authority_digest ~accepted_kinds
        ~apply_once ~query
    with
    | Ok registry ->
        Ok { registry; observations; observations_mutex = receipts_mutex }
    | Error issues ->
        Error
          (List.map
             (fun (issue : Run_effect_authority.diagnostic) ->
               diagnostic Invalid_activity issue.bytes)
             issues)

let observation_of_receipt registration
    (receipt : Run_effect_authority.receipt) =
  let reject message = Error (diagnostic Invalid_observation message) in
  let evidence = Run_effect_authority.target_receipt_evidence receipt in
  let receipt_id = Run_effect_authority.evidence_receipt_id evidence in
  let observed =
    with_mutex registration.observations_mutex (fun () ->
      Hashtbl.find_opt registration.observations receipt_id)
  in
  match observed with
  | None -> reject "observation receipt identity is not owned by this target"
  | Some observed ->
      let status_coherent =
        match observed.status, observed.availability, observed.exit_code with
        | Passed, Available, Some 0 -> true
        | Failed, Available, Some code -> code <> 0
        | Skipped, Unavailable, None -> true
        | _ -> false
      in
      let evidence_coherent =
        match observed.availability,
              Run_effect_authority.evidence_disposition evidence with
        | Available, Run_effect_authority.Evidence_succeeded
        | Unavailable, Run_effect_authority.Evidence_unavailable -> true
        | _ -> false
      in
      let length = String.length observed.output in
      let truncation_coherent =
        length <= maximum_observation_output_bytes
        && observed.output_bytes >= length
        && observed.output_truncated = (observed.output_bytes > length)
        && (observed.output_truncated
            || String.equal observed.output_digest (sha256 observed.output))
      in
      begin match observation_bytes observed with
      | Error message -> reject message
      | Ok bytes ->
          if not
              (valid_identifier observed.action_id
               && valid_digest observed.action_digest
               && valid_digest observed.output_digest
               && status_coherent && evidence_coherent && truncation_coherent
               && String.equal (sha256 bytes)
                    (Run_effect_authority.evidence_digest evidence))
          then reject "owner-held observation differs from redacted evidence"
          else Ok observed
      end
