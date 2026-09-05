type diagnostic_code =
  | Invalid_event_source
  | Invalid_current_authority
  | Invalid_intent
  | Invalid_admission
  | Invalid_action_registry
  | Invalid_plan

type diagnostic = {
  code : diagnostic_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
}

type error_code =
  | Event_authority_unavailable
  | Execution_refused
  | Event_append_failure
  | Effect_failure
  | Projection_invalid
  | Readback_invalid

type error = {
  code : error_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
}

type event_source_kind = Production | Test

type event_sources = {
  wall_now_ns : unit -> int64;
  monotonic_now_ns : unit -> int64;
  event_id : run_id:string -> sequence:int64 -> string;
  readback_agrees : bool;
  kind : event_source_kind;
}

type action_status = Action_succeeded | Action_failed

type action_receipt = {
  action_id : string;
  action_digest : string;
  request_digest : string;
  effect_receipt_digest : string;
  output_digest : string;
  attempt_count : int;
  status : action_status;
}

type result = {
  run_id : string;
  authority_digest : string;
  admission_digest : string;
  plan_digest : string;
  ordered_action_receipts : action_receipt list;
  engine_projection_digest : string;
  initial_head_sequence : int64;
  initial_head_digest : string;
  final_head_sequence : int64;
  final_head_digest : string;
  attempt_event_count : int;
  complete_stream_digest : string;
  result_digest : string;
}

type execution_outcome = (result, error) Stdlib.result
type execution_claim_state = Running | Finished of execution_outcome

type execution_claims = {
  mutex : Mutex.t;
  condition : Condition.t;
  states : (string, execution_claim_state) Hashtbl.t;
}

type execution_faults = {
  mutex : Mutex.t;
  preparation_failures : (string, int) Hashtbl.t;
  mutable terminal_append_failure : string option;
}

type event_authority = {
  store : Run_event_store.t;
  context : Run_safety.gate_context;
  sources : event_sources;
  allocation_lock : Mutex.t;
  execution_faults : execution_faults;
  execution_claims : execution_claims;
}

type current_authority = {
  event_authority : event_authority;
  context : Run_safety.gate_context;
  authority_digest : string;
}

type typed_intent = {
  context : Run_safety.gate_context;
  current_authority : current_authority;
  activity : Run_topology.admitted_activity;
  activity_digest : string;
  topology_authority_digest : string;
  module_intent_digest : string;
  fpp_authority_digest : string;
  debug_authority_digest : string;
  external_access_authority_digest : string;
  intent_digest : string;
}

type admission = {
  context : Run_safety.gate_context;
  intent : typed_intent;
  current_authority : current_authority;
  assurance : Run_assurance.admitted_bundle;
  fast_path : Run_fast_path.selection;
  admission_digest : string;
}

type action_registry = {
  activity_id : string;
  activity_digest : string;
  topology_authority_digest : string;
  actions : Run_topology.declarative_action list;
  action_digests : string list;
  registry_digest : string;
}

type admitted_plan = {
  admission_ids : string list;
  plan_ids : string list;
  admission_digest : string;
  registry_digest : string;
  ordered_action_ids : string list;
  ordered_action_digests : string list;
  graph_digest : string;
  plan_digest : string;
}

let engine_call_count = Atomic.make 0
let preparation_call_count = Atomic.make 0

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let redacted_evidence_output receipt =
  let evidence = Run_effect_authority.target_receipt_evidence receipt in
  evidence
  |> Run_effect_authority.redacted_evidence_json
  |> Run_model.canonical_string
  |> Result.get_ok

let digest_fields fields =
  fields
  |> List.map (fun field -> Printf.sprintf "%d:%s" (String.length field) field)
  |> String.concat ""
  |> sha256

let authority_error (context : Run_safety.gate_context) message =
  Error
    { code = Event_authority_unavailable; message;
      coordinate = context.coordinate; rca_origin = Ops_capability.Control;
      hazard_id = "HZ-SWARM-BRIDGE-01" }

let diagnostic (context : Run_safety.gate_context) (code : diagnostic_code)
    message : diagnostic =
  { code; message; coordinate = context.Run_safety.coordinate;
    rca_origin = Ops_capability.Control; hazard_id = "HZ-SWARM-BRIDGE-01" }

let static_diagnostic code message : diagnostic =
  { code; message;
    coordinate = { level = Ops_capability.L2; phase = Ops_capability.Decide };
    rca_origin = Ops_capability.Control; hazard_id = "HZ-SWARM-BRIDGE-01" }

let coordinate_equal (left : Ops_capability.coordinate)
    (right : Ops_capability.coordinate) =
  left.level = right.level && left.phase = right.phase

let exact_context (left : Run_safety.gate_context)
    (right : Run_safety.gate_context) =
  let left_head = left.current_head in
  let right_head = right.current_head in
  String.equal left.run_id right.run_id
  && String.equal left.request_id right.request_id
  && String.equal left.activity_id right.activity_id
  && Run_model.equal_provenance left.provenance right.provenance
  && coordinate_equal left.coordinate right.coordinate
  && left.plane = right.plane
  && String.equal left.current_head_digest right.current_head_digest
  && Int64.equal left.current_at_ns right.current_at_ns
  && String.equal left.context_digest right.context_digest
  && String.equal left_head.run_id right_head.run_id
  && Run_model.equal_provenance left_head.provenance right_head.provenance
  && Int64.equal left_head.head_sequence right_head.head_sequence
  && String.equal left_head.head_event_digest right_head.head_event_digest
  && Int64.equal left_head.observed_at_ns right_head.observed_at_ns
  && Int64.equal left_head.current_at_ns right_head.current_at_ns
  && Int64.equal left_head.expires_at_ns right_head.expires_at_ns
  && Int64.equal left_head.observed_monotonic_ns
       right_head.observed_monotonic_ns
  && Int64.equal left_head.expires_monotonic_ns right_head.expires_monotonic_ns
  && String.equal left_head.authority_digest right_head.authority_digest
  && String.equal left_head.receipt_digest right_head.receipt_digest

let source_sample context sources =
  try
    let wall_now_ns = sources.wall_now_ns () in
    let monotonic_now_ns = sources.monotonic_now_ns () in
    let first_sequence = Int64.succ context.Run_safety.current_head.head_sequence in
    let second_sequence = Int64.succ first_sequence in
    let first_id =
      sources.event_id ~run_id:context.run_id ~sequence:first_sequence in
    let second_id =
      sources.event_id ~run_id:context.run_id ~sequence:second_sequence in
    if not sources.readback_agrees then Error "full event readback disagrees"
    else if String.trim first_id = "" || String.trim second_id = "" then
      Error "event ids must be nonempty"
    else if String.equal first_id second_id then Error "event ids must be unique"
    else Ok (wall_now_ns, monotonic_now_ns)
  with exn ->
    Error ("event source failed: " ^ Printexc.to_string exn)

let revalidate_context (authority : event_authority)
    (context : Run_safety.gate_context) =
  match source_sample context authority.sources with
  | Error message -> authority_error context message
  | Ok (wall_now_ns, monotonic_now_ns) ->
      let validation =
        match authority.sources.kind with
        | Production ->
            Run_safety.revalidate_gate_context_current_head
              ~store:authority.store context
        | Test ->
            Run_safety.For_test.revalidate_gate_context_current_head_at
              ~wall_now_ns ~monotonic_now_ns ~store:authority.store
              context
      in
      Result.map_error
        (fun (issue : Run_safety.gate_error) ->
          { code = Event_authority_unavailable; message = issue.message;
            coordinate = issue.coordinate; rca_origin = issue.rca_origin;
            hazard_id = issue.hazard_id })
        validation

let revalidate_event_authority (authority : event_authority) =
  revalidate_context authority authority.context

let production_event_sources =
  { wall_now_ns =
      (fun () -> Int64.of_float (Unix.gettimeofday () *. 1_000_000_000.));
    monotonic_now_ns = Mtime_clock.elapsed_ns;
    event_id =
      (fun ~run_id ~sequence -> Printf.sprintf "%s-%Ld" run_id sequence);
    readback_agrees = true;
    kind = Production }

let create_event_authority ~(store : Run_event_store.t)
    ~(context : Run_safety.gate_context) ~(sources : event_sources) =
  let authority =
    { store; context; sources; allocation_lock = Mutex.create ();
      execution_faults =
        { mutex = Mutex.create (); preparation_failures = Hashtbl.create 5;
          terminal_append_failure = None };
      execution_claims =
        { mutex = Mutex.create (); condition = Condition.create ();
          states = Hashtbl.create 3 } }
  in
  match revalidate_event_authority authority with
  | Error _ as error -> error
  | Ok () -> Ok authority

let current_authority (authority : event_authority) =
  match revalidate_event_authority authority with
  | Error _ as error -> error
  | Ok () ->
      let context = authority.context in
      Ok
        { event_authority = authority; context;
          authority_digest =
            digest_fields
              [ context.context_digest; context.current_head_digest;
                context.current_head.head_event_digest;
                context.current_head.authority_digest ] }

let resolve_intent ~(context : Run_safety.gate_context)
    ~(current_authority : current_authority)
    ~(activity : Run_topology.admitted_activity) =
  match revalidate_event_authority current_authority.event_authority with
  | Error issue ->
      Error [ diagnostic context Invalid_current_authority issue.message ]
  | Ok () ->
      begin match
        revalidate_context current_authority.event_authority context
      with
      | Error issue ->
          Error [ diagnostic context Invalid_current_authority issue.message ]
      | Ok () when not (exact_context context current_authority.context) ->
          Error
            [ diagnostic context Invalid_current_authority
                "intent context differs from the exact current authority" ]
      | Ok () ->
          let activity_digest = Run_topology.admitted_activity_digest activity in
          let topology_authority_digest =
            Run_topology.admitted_activity_authority_digest activity in
          let module_intent_digest = Module_intent.source_digest in
          let fpp_authority_digest = Run_fpp_authority.source_digest in
          let debug_authority_digest = Debug_intent.source_digest in
          let external_access_authority_digest = External_access.source_digest in
          Ok
            { context; current_authority; activity; activity_digest;
              topology_authority_digest; module_intent_digest;
              fpp_authority_digest; debug_authority_digest;
              external_access_authority_digest;
              intent_digest =
                digest_fields
                  [ context.context_digest; current_authority.authority_digest;
                    activity_digest; topology_authority_digest;
                    module_intent_digest; fpp_authority_digest;
                    debug_authority_digest; external_access_authority_digest ] }
      end

let intent_authority_digests intent =
  (intent.module_intent_digest, intent.fpp_authority_digest)

let intent_debug_authority_digest intent = intent.debug_authority_digest

let intent_external_access_authority_digest intent =
  intent.external_access_authority_digest

let admit ~(context : Run_safety.gate_context) ~(intent : typed_intent)
    ~(current_authority : current_authority)
    ~(assurance : Run_assurance.admitted_bundle)
    ~(fast_path : Run_fast_path.selection) =
  let reject message = Error [ diagnostic context Invalid_admission message ] in
  match revalidate_event_authority current_authority.event_authority with
  | Error issue -> reject issue.message
  | Ok () ->
      begin match
        revalidate_context current_authority.event_authority context
      with
      | Error issue -> reject issue.message
      | Ok ()
        when not
          (exact_context context intent.context
           && exact_context context current_authority.context
           && String.equal intent.current_authority.authority_digest
                current_authority.authority_digest) ->
          reject "admission carriers do not share the exact current context"
      | Ok () ->
        begin match Run_assurance.validate_bundle ~context assurance with
      | Error issues ->
          reject
            (String.concat "; "
               (List.map (fun (issue : Run_safety.gate_error) -> issue.message)
                  issues))
      | Ok () ->
          begin match
            Run_fast_path.validate_selection ~context ~activity:intent.activity
              fast_path
          with
          | Error issues ->
              reject
                (String.concat "; "
                   (List.map
                      (fun (issue : Run_fast_path.diagnostic) -> issue.message)
                      issues))
          | Ok () ->
              Ok
                { context; intent; current_authority; assurance; fast_path;
                  admission_digest =
                    digest_fields
                      [ context.context_digest; intent.intent_digest;
                        current_authority.authority_digest;
                        assurance.bundle_digest;
                        Run_fast_path.selection_digest fast_path ] }
          end
        end
      end

let validate_action_declaration (activity : Run_topology.declarative_activity) =
  match Run_topology.admit_activity ~stable_id:activity.stable_id with
  | Error issues ->
      Error
        [ static_diagnostic Invalid_action_registry
            (String.concat "; " issues) ]
  | Ok canonical ->
      let canonical_declaration = Run_topology.admitted_declaration canonical in
      let activity_digest = Run_topology.activity_digest_of activity in
      let expected_digest = Run_topology.admitted_activity_digest canonical in
      if activity.actions = [] then
        Error
          [ static_diagnostic Invalid_action_registry
              "the canonical admitted action denominator must be nonempty" ]
      else if not (String.equal activity_digest expected_digest)
              || activity <> canonical_declaration
      then
        Error
          [ static_diagnostic Invalid_action_registry
              "the action declaration differs from the closed topology authority" ]
      else
        let action_digests =
          List.map Run_topology.action_digest_of activity.actions in
        let topology_authority_digest =
          Run_topology.admitted_activity_authority_digest canonical in
        Ok
          { activity_id = activity.stable_id; activity_digest;
            topology_authority_digest; actions = activity.actions;
            action_digests;
            registry_digest =
              digest_fields
                (activity.stable_id :: activity_digest
                 :: topology_authority_digest :: action_digests) }

let action_registry ~(activity : Run_topology.admitted_activity) =
  validate_action_declaration (Run_topology.admitted_declaration activity)

let unique_strings values =
  List.length values = List.length (List.sort_uniq String.compare values)

let admission_ids (admission : admission) =
  [ "context:" ^ admission.context.context_digest;
    "intent:" ^ admission.intent.intent_digest;
    "current-authority:" ^ admission.current_authority.authority_digest;
    "assurance:" ^ admission.assurance.bundle_digest;
    "fast-path:" ^ Run_fast_path.selection_digest admission.fast_path;
    "admission:" ^ admission.admission_digest ]

let action_graph_fields (action : Run_topology.declarative_action) =
  [ action.stable_id; action.command_id; action.assigned_agent_id;
    String.concat "\x1f" action.dependency_ids; action.selector_id;
    action.required_capability_id;
    String.concat "\x1f" action.context_requirement_ids;
    action.target_component_id; action.preparation_id;
    Run_topology.action_digest_of action ]

let expected_plan ~(admission : admission) ~(action_registry : action_registry) =
  let admission_ids = admission_ids admission in
  let ordered_action_ids =
    List.map
      (fun (action : Run_topology.declarative_action) -> action.stable_id)
      action_registry.actions
  in
  let ordered_action_digests = action_registry.action_digests in
  let plan_ids = action_registry.activity_id :: ordered_action_ids in
  let graph_digest =
    digest_fields
      ("run-swarm-bridge-action-graph-v1" :: action_registry.activity_id
       :: List.concat_map action_graph_fields action_registry.actions)
  in
  let plan_digest =
    digest_fields
      ([ "run-swarm-bridge-plan-v1"; admission.admission_digest;
         action_registry.registry_digest; graph_digest ]
       @ admission_ids @ plan_ids @ ordered_action_digests)
  in
  { admission_ids; plan_ids; admission_digest = admission.admission_digest;
    registry_digest = action_registry.registry_digest; ordered_action_ids;
    ordered_action_digests; graph_digest; plan_digest }

let validate_admission (admission : admission) =
  let context = admission.context in
  let reject message =
    Error [ diagnostic context Invalid_admission message ]
  in
  match revalidate_event_authority admission.current_authority.event_authority with
  | Error issue -> reject issue.message
  | Ok ()
    when not
      (exact_context context admission.intent.context
       && exact_context context admission.current_authority.context
       && String.equal admission.intent.current_authority.authority_digest
            admission.current_authority.authority_digest) ->
      reject "plan admission carriers do not share the exact current context"
  | Ok () ->
      begin match Run_assurance.validate_bundle ~context admission.assurance with
      | Error issues ->
          reject
            (String.concat "; "
               (List.map (fun (issue : Run_safety.gate_error) -> issue.message)
                  issues))
      | Ok () ->
          begin match
            Run_fast_path.validate_selection ~context
              ~activity:admission.intent.activity admission.fast_path
          with
          | Error issues ->
              reject
                (String.concat "; "
                   (List.map
                      (fun (issue : Run_fast_path.diagnostic) -> issue.message)
                      issues))
          | Ok () ->
              let expected_digest =
                digest_fields
                  [ context.context_digest; admission.intent.intent_digest;
                    admission.current_authority.authority_digest;
                    admission.assurance.bundle_digest;
                    Run_fast_path.selection_digest admission.fast_path ]
              in
              if String.equal admission.admission_digest expected_digest then Ok ()
              else reject "admission digest differs from its exact carriers"
          end
      end

let validate_registry_for_admission (admission : admission)
    (registry : action_registry) =
  let context = admission.context in
  match action_registry ~activity:admission.intent.activity with
  | Error issues -> Error issues
  | Ok expected when registry = expected -> Ok ()
  | Ok _ ->
      Error
        [ diagnostic context Invalid_action_registry
            "action registry differs from the admitted topology authority" ]

let validate_plan ~(admission : admission) ~(action_registry : action_registry)
    (plan : admitted_plan) =
  let reject message =
    Error [ diagnostic admission.context Invalid_plan message ]
  in
  match validate_admission admission with
  | Error issues -> Error issues
  | Ok () ->
      begin match validate_registry_for_admission admission action_registry with
      | Error issues -> Error issues
      | Ok () ->
          let expected = expected_plan ~admission ~action_registry in
          if not (unique_strings plan.admission_ids) then
            reject "admission identities must be unique"
          else if not (unique_strings plan.plan_ids) then
            reject "plan identities must be unique"
          else if plan.admission_ids <> expected.admission_ids then
            reject "plan admission identities differ"
          else if plan.plan_ids <> expected.plan_ids then
            reject "plan identities differ"
          else if not (String.equal plan.admission_digest expected.admission_digest)
          then reject "plan admission digest differs"
          else if not (String.equal plan.registry_digest expected.registry_digest)
          then reject "plan registry digest differs"
          else if plan.ordered_action_ids <> expected.ordered_action_ids
                  || plan.ordered_action_digests
                     <> expected.ordered_action_digests
          then reject "plan action order or action digests differ"
          else if not (String.equal plan.graph_digest expected.graph_digest) then
            reject "plan graph digest differs"
          else if not (String.equal plan.plan_digest expected.plan_digest) then
            reject "plan digest differs"
          else Ok ()
      end

let admit_plan ~(admission : admission) ~(action_registry : action_registry) =
  match validate_admission admission with
  | Error issues -> Error issues
  | Ok () ->
      begin match validate_registry_for_admission admission action_registry with
      | Error issues -> Error issues
      | Ok () ->
          let plan = expected_plan ~admission ~action_registry in
          begin match validate_plan ~admission ~action_registry plan with
          | Ok () -> Ok plan
          | Error issues -> Error issues
          end
      end

let admitted_plan_digest (plan : admitted_plan) = plan.plan_digest

let execution_identity ~run_id ~(activity : Run_topology.admitted_activity) =
  let declaration = Run_topology.admitted_declaration activity in
  digest_fields
    [ "run-swarm-execution-identity-v1"; run_id; declaration.stable_id;
      Run_topology.admitted_activity_digest activity;
      Run_topology.admitted_activity_authority_digest activity;
      Run_topology.source_digest ]

type attempt_record = {
  action_id : string;
  assigned_agent_id : string;
  attempt : int;
  dependency_input_digest : string;
  request_digest : string;
  effect_receipt_digest : string;
  output : string;
  output_digest : string;
  lifecycle : Run_model.lifecycle;
  event_digests : string list;
}

let action_receipt_fields (receipt : action_receipt) =
  let status = match receipt.status with
    | Action_succeeded -> "succeeded"
    | Action_failed -> "failed"
  in
  [ receipt.action_id; receipt.action_digest; receipt.request_digest;
    receipt.effect_receipt_digest; receipt.output_digest;
    string_of_int receipt.attempt_count; status ]

let complete_stream_digest events =
  digest_fields
    ("run-swarm-bridge-complete-stream-v1"
     :: List.map (fun (event : Run_model.event) -> event.digest) events)

let result_digest_of (receipt : result) =
  digest_fields
    ([ "run-swarm-bridge-result-v2"; receipt.run_id;
       receipt.authority_digest; receipt.admission_digest; receipt.plan_digest;
       receipt.engine_projection_digest;
       Int64.to_string receipt.initial_head_sequence;
       receipt.initial_head_digest; Int64.to_string receipt.final_head_sequence;
       receipt.final_head_digest; string_of_int receipt.attempt_event_count;
       receipt.complete_stream_digest ]
     @ List.concat_map action_receipt_fields receipt.ordered_action_receipts)

let execution_error (context : Run_safety.gate_context) code message =
  Error
    { code; message; coordinate = context.coordinate;
      rca_origin = Ops_capability.Control; hazard_id = "HZ-SWARM-BRIDGE-01" }

let with_mutex mutex f =
  Mutex.lock mutex;
  match f () with
  | value -> Mutex.unlock mutex; value
  | exception exn -> Mutex.unlock mutex; raise exn

let last = function [] -> None | values -> Some (List.hd (List.rev values))

let append_attempt_event (authority : event_authority) ~kind ~action_id
    ~attempt ~payload =
  with_mutex authority.allocation_lock (fun () ->
    let injected_terminal_failure =
      kind = Run_model.Swarm_step_terminal
      && with_mutex authority.execution_faults.mutex (fun () ->
           match authority.execution_faults.terminal_append_failure with
           | Some expected when String.equal expected action_id ->
               authority.execution_faults.terminal_append_failure <- None;
               true
           | Some _ | None -> false)
    in
    if injected_terminal_failure then Error "injected terminal append failure"
    else
    let context = authority.context in
    match Run_event_store.events authority.store ~run_id:context.run_id with
    | Error message -> Error message
    | Ok events ->
        begin match last events with
        | None -> Error "event authority has no current head"
        | Some head ->
            begin match
              try
                Ok (authority.sources.wall_now_ns (),
                    authority.sources.monotonic_now_ns ())
              with exn ->
                Error ("event source failed: " ^ Printexc.to_string exn)
            with
            | Error _ as error -> error
            | Ok (wall_now_ns, monotonic_now_ns)
              when wall_now_ns < head.occurred_at_ns
                   || monotonic_now_ns < head.monotonic_at_ns ->
                Error "event source clocks moved behind the durable head"
            | Ok (wall_now_ns, monotonic_now_ns) ->
                let sequence = Int64.succ head.sequence in
                let event_id =
                  authority.sources.event_id ~run_id:context.run_id ~sequence
                in
                if String.trim event_id = ""
                   || List.exists
                        (fun (event : Run_model.event) ->
                          String.equal event.event_id event_id)
                        events
                then Error "event source returned an empty or reused event id"
                else
                  begin match
                    Run_model.make ~run_id:context.run_id ~sequence ~event_id
                      ~kind ~subject:(Run_model.Attempt (action_id, attempt))
                      ~plane:context.plane ~coordinate:context.coordinate
                      ~rca_origin:Ops_capability.Control ~occurred_at_ns:wall_now_ns
                      ~monotonic_at_ns:monotonic_now_ns
                      ~provenance:context.provenance ~payload
                      ~previous_digest:(Some head.digest)
                  with
                  | Error _ as error -> error
                  | Ok event ->
                      begin match Run_event_store.append authority.store event with
                      | Error _ as error -> error
                      | Ok () when not authority.sources.readback_agrees ->
                          Error "full event readback disagrees"
                      | Ok () ->
                          begin match
                            Run_event_store.events authority.store
                              ~run_id:context.run_id
                          with
                          | Error _ as error -> error
                          | Ok readback ->
                              begin match last readback with
                              | Some observed
                                when Int64.equal observed.sequence event.sequence
                                     && String.equal observed.digest event.digest ->
                                  Ok event
                              | Some _ | None ->
                                  Error "appended event is not the durable head"
                              end
                          end
                      end
                  end
            end
        end)

let effect_error_bytes = function
  | Run_effect_authority.Invalid_request issue
  | Run_effect_authority.Target_unavailable issue
  | Run_effect_authority.Ledger_failure issue -> issue.bytes
  | Run_effect_authority.Key_reused_with_different_request conflict ->
      conflict.diagnostic.bytes
  | Run_effect_authority.Indeterminate (_, issue) -> issue.bytes

let terminal_payload ~plan_digest ~action_id ~attempt ~lifecycle
    ~dependency_input_digest ~request_digest ~effect_receipt_digest ~output =
  `Assoc
    [ ("action_id", `String action_id);
      ("attempt", `Int attempt);
      ("dependency_input_digest", `String dependency_input_digest);
      ("effect_receipt_digest", `String effect_receipt_digest);
      ("lifecycle", `String (Run_model.string_of_lifecycle lifecycle));
      ("output", `String output);
      ("output_digest", `String (sha256 output));
      ("plan_digest", `String plan_digest);
      ("request_digest", `String request_digest) ]

let next_durable_attempt (authority : event_authority) ~action_id =
  match Run_event_store.events authority.store ~run_id:authority.context.run_id with
  | Error message -> Error message
  | Ok events ->
      let maximum =
        List.fold_left
          (fun maximum (event : Run_model.event) ->
            match event.subject with
            | Run_model.Attempt (observed_action_id, attempt)
              when String.equal observed_action_id action_id ->
                Int.max maximum attempt
            | _ -> maximum)
          (-1) events
      in
      if maximum = Int.max_int then Error "durable attempt identity overflow"
      else Ok (maximum + 1)

let make_step ~(authority : event_authority) ~(plan : admitted_plan)
    ~execution_identity ~(activity : Run_topology.admitted_activity)
    ~(interpreter : Run_effect_authority.interpreter) ~records ~records_lock
    (action : Run_topology.declarative_action) =
  let first_attempt =
    match next_durable_attempt authority ~action_id:action.stable_id with
    | Ok value -> value
    | Error message -> failwith ("durable attempt readback failed: " ^ message)
  in
  let attempt_counter = Atomic.make first_attempt in
  let no_replay_reason = Atomic.make None in
  let append kind attempt payload =
    append_attempt_event authority ~kind ~action_id:action.stable_id ~attempt
      ~payload
  in
  let action_callback assigned_agent_id input_payload =
    let attempt = Atomic.fetch_and_add attempt_counter 1 in
    let ready_payload =
      `Assoc
        [ ("action_id", `String action.stable_id);
          ("action_invocation_entry", `Bool true);
          ("attempt", `Int attempt);
          ("plan_digest", `String plan.plan_digest);
          ("scheduler_ready", `Bool false) ]
    in
    match append Run_model.Swarm_step_ready attempt ready_payload with
    | Error message -> failwith ("ready append failed: " ^ message)
    | Ok ready_event ->
        let running_payload =
          `Assoc
            [ ("action_id", `String action.stable_id);
              ("attempt", `Int attempt);
              ("plan_digest", `String plan.plan_digest) ]
        in
        begin match append Run_model.Swarm_step_running attempt running_payload with
        | Error message -> failwith ("running append failed: " ^ message)
        | Ok running_event ->
            let terminal_failure ~dependency_input_digest ~request_digest message =
              let payload =
                terminal_payload ~plan_digest:plan.plan_digest
                  ~action_id:action.stable_id ~attempt
                  ~lifecycle:Run_model.Failed ~dependency_input_digest
                  ~request_digest ~effect_receipt_digest:"" ~output:message
              in
              begin match append Run_model.Swarm_step_terminal attempt payload with
              | Error _ -> ()
              | Ok terminal_event ->
                  let record =
                    { action_id = action.stable_id; assigned_agent_id; attempt;
                      dependency_input_digest; request_digest;
                      effect_receipt_digest = ""; output = message;
                      output_digest = sha256 message;
                      lifecycle = Run_model.Failed;
                      event_digests =
                        [ ready_event.digest; running_event.digest;
                          terminal_event.digest ] }
                  in
                  with_mutex records_lock (fun () ->
                    records := record :: !records)
              end;
              ("bridge:action-failed:" ^ message, (0, 0))
            in
            begin match Atomic.get no_replay_reason with
            | Some reason ->
              ignore
                (terminal_failure ~dependency_input_digest:""
                   ~request_digest:""
                   (reason ^ "; replay forbidden"));
              failwith (reason ^ "; effect replay forbidden")
            | None -> ()
            end;
            let injected_preparation_failure =
              with_mutex authority.execution_faults.mutex (fun () ->
                match
                  Hashtbl.find_opt authority.execution_faults.preparation_failures
                    action.stable_id
                with
                | Some remaining when remaining > 0 ->
                    if remaining = 1 then
                      Hashtbl.remove
                        authority.execution_faults.preparation_failures
                        action.stable_id
                    else
                      Hashtbl.replace
                        authority.execution_faults.preparation_failures
                        action.stable_id (remaining - 1);
                    true
                | Some _ | None -> false)
            in
            let prepared =
              try
                ignore (Atomic.fetch_and_add preparation_call_count 1);
                if injected_preparation_failure then
                  Error "injected pure preparation failure"
                else
                  Run_swarm_preparation.prepare ~execution_identity
                    ~activity ~action ~input_payload
              with exn -> Error (Printexc.to_string exn)
            in
            begin match prepared with
            | Error message ->
                ignore
                  (terminal_failure ~dependency_input_digest:""
                     ~request_digest:"" message);
                failwith message
            | Ok prepared ->
                begin match
                  Run_effect_authority.make_request
                    ~effect_kind:prepared.effect_kind
                    ~request_bytes:prepared.request_bytes
                with
                | Error issue ->
                    ignore (terminal_failure
                      ~dependency_input_digest:prepared.dependency_input_digest
                      ~request_digest:prepared.request_digest issue.bytes);
                    failwith "effect request construction failed"
                | Ok request ->
                    let applied =
                      try
                        `Result
                          (Run_effect_authority.apply_once interpreter
                             ~idempotency_key:prepared.idempotency_key request)
                      with exn -> `Raised (Printexc.to_string exn)
                    in
                    begin match applied with
                    | `Raised message ->
                        Atomic.set no_replay_reason
                          (Some "effect application raised without a safe replay receipt");
                        ignore (terminal_failure
                          ~dependency_input_digest:prepared.dependency_input_digest
                          ~request_digest:request.request_digest message);
                        failwith "effect application raised; replay forbidden"
                    | `Result (Error issue) ->
                        let message = effect_error_bytes issue in
                        Atomic.set no_replay_reason
                          (Some "effect authority refused or became indeterminate");
                        ignore (terminal_failure
                          ~dependency_input_digest:prepared.dependency_input_digest
                          ~request_digest:request.request_digest
                          message);
                        failwith "effect authority refused; replay forbidden"
                    | `Result (Ok receipt) ->
                        let output = redacted_evidence_output receipt in
                        let payload =
                          terminal_payload ~plan_digest:plan.plan_digest
                            ~action_id:action.stable_id ~attempt
                            ~lifecycle:Run_model.Succeeded
                            ~dependency_input_digest:
                              prepared.dependency_input_digest
                            ~request_digest:request.request_digest
                            ~effect_receipt_digest:receipt.receipt_digest ~output
                        in
                        begin match
                          append Run_model.Swarm_step_terminal attempt payload
                        with
                        | Error message ->
                            Atomic.set no_replay_reason
                              (Some "effect has no durable terminal event");
                            failwith
                              ("terminal append failed after effect: " ^ message)
                        | Ok terminal_event ->
                            let record =
                              { action_id = action.stable_id; assigned_agent_id;
                                attempt;
                                dependency_input_digest =
                                  prepared.dependency_input_digest;
                                request_digest = request.request_digest;
                                effect_receipt_digest = receipt.receipt_digest;
                                output; output_digest = sha256 output;
                                lifecycle = Run_model.Succeeded;
                                event_digests =
                                  [ ready_event.digest; running_event.digest;
                                    terminal_event.digest ] }
                            in
                            with_mutex records_lock (fun () ->
                              records := record :: !records);
                            (output, (0, 0))
                        end
                    end
                end
            end
        end
  in
  ({ Sop_execution.step_id = action.stable_id; name = action.command_id;
     assigned_agent = action.assigned_agent_id;
     dependencies = action.dependency_ids; action = action_callback }
    : Sop_execution.step)

let validate_execution_readback ~(admission : admission)
    ~(authority : event_authority) ~(plan : admitted_plan)
    ~(initial_events : Run_model.event list)
    ~(actions : Run_topology.declarative_action list)
    ~(records : attempt_record list)
    (engine : Sop_execution.workflow_execution_result) =
  let context = authority.context in
  let reject code message = execution_error context code message in
  let sorted values = List.sort String.compare values in
  let action_ids = List.map (fun (a : Run_topology.declarative_action) -> a.stable_id) actions in
  let result_ids = List.map (fun (r : Sop_execution.step_result) -> r.step_id) engine.step_results in
  if action_ids <> result_ids
     || List.length result_ids <> List.length (List.sort_uniq String.compare result_ids)
  then reject Projection_invalid
      "engine result order is not exactly bijective with the admitted plan"
  else if not engine.replay_verified then
    reject Projection_invalid "engine history replay did not verify"
  else if List.exists
      (fun (row : Sop_execution.step_result) -> row.status <> Sop_execution.Completed)
      engine.step_results
  then reject Projection_invalid "engine returned a non-completed step"
  else
    let records_for action_id =
      records
      |> List.filter (fun row -> String.equal row.action_id action_id)
      |> List.sort (fun left right -> Int.compare left.attempt right.attempt)
    in
    let initial_attempt_for action_id =
      initial_events
      |> List.fold_left
           (fun maximum (event : Run_model.event) ->
             match event.subject with
             | Run_model.Attempt (observed_action_id, attempt)
               when String.equal observed_action_id action_id ->
                 Int.max maximum attempt
             | _ -> maximum)
           (-1)
      |> (fun maximum -> maximum + 1)
    in
    let valid_attempt_chain action_id =
      let chain = records_for action_id in
      let rec contiguous expected = function
        | [] -> true
        | row :: rest ->
            row.attempt = expected && contiguous (expected + 1) rest
      in
      match List.rev chain with
      | [] -> false
      | final :: prior_rev ->
          contiguous (initial_attempt_for action_id) chain
          && final.lifecycle = Run_model.Succeeded
          && final.effect_receipt_digest <> ""
          && List.for_all
               (fun row ->
                 row.lifecycle = Run_model.Failed
                 && String.equal row.effect_receipt_digest "")
               prior_rev
    in
    if not (List.for_all valid_attempt_chain action_ids) then
      reject Readback_invalid
        "each action requires contiguous failed preparations followed by one success"
    else
    let successful_record action_id =
      records_for action_id
      |> List.find_opt (fun row -> row.lifecycle = Run_model.Succeeded)
    in
    let output_of action_id =
      successful_record action_id |> Option.map (fun row -> row.output)
    in
    let result_valid (result : Sop_execution.step_result) =
      match
        List.find_opt
          (fun (action : Run_topology.declarative_action) ->
            String.equal action.stable_id result.step_id)
          actions,
        successful_record result.step_id
      with
      | Some action, Some record ->
          String.equal result.agent_id action.assigned_agent_id
          && String.equal result.output_payload record.output
          && String.equal record.output_digest (sha256 record.output)
          && String.equal result.input_payload
               (action.dependency_ids
                |> List.filter_map output_of
                |> Sop_execution.For_test.dependency_payload)
          && String.equal record.dependency_input_digest
               (digest_fields
                  [ "run-swarm-dependency-input-v1"; action.stable_id;
                    result.input_payload ])
      | _ -> false
    in
    if not (List.for_all result_valid engine.step_results) then
      reject Projection_invalid "engine outputs or dependency inputs differ from durable receipts"
    else
      match Run_event_store.events authority.store ~run_id:context.run_id with
      | Error message -> reject Readback_invalid message
      | Ok events ->
          let initial_digests = List.map (fun (event : Run_model.event) -> event.digest) initial_events in
          let prefix, suffix =
            let rec split count acc remaining =
              if count = 0 then List.rev acc, remaining
              else match remaining with
                | [] -> List.rev acc, []
                | value :: rest -> split (count - 1) (value :: acc) rest
            in
            split (List.length initial_events) [] events
          in
          let prefix_digests = List.map (fun (event : Run_model.event) -> event.digest) prefix in
          let observed_attempt_digests = List.map (fun (event : Run_model.event) -> event.digest) suffix in
          let recorded_attempt_digests =
            records |> List.concat_map (fun row -> row.event_digests) |> sorted
          in
          if prefix_digests <> initial_digests then
            reject Readback_invalid "the pre-execution durable prefix changed"
          else if List.length suffix <> 3 * List.length records
                  || sorted observed_attempt_digests <> recorded_attempt_digests
          then reject Readback_invalid "full attempt-event readback differs"
          else
            begin match Run_snapshot.fold initial_events, Run_snapshot.fold events with
            | Error message, _ | _, Error message ->
                reject Readback_invalid message
            | Ok initial_snapshot, Ok snapshot
              when (Run_snapshot.counts snapshot).attempts_terminal
                   - (Run_snapshot.counts initial_snapshot).attempts_terminal
                   <> List.length records ->
                reject Readback_invalid "terminal attempt count differs"
            | Ok _, Ok _ ->
                let ordered_action_receipts =
                  List.map
                    (fun (action : Run_topology.declarative_action) ->
                      let chain = records_for action.stable_id in
                      let successful =
                        match successful_record action.stable_id with
                        | Some row -> row
                        | None -> assert false
                      in
                      { action_id = action.stable_id;
                        action_digest = Run_topology.action_digest_of action;
                        request_digest = successful.request_digest;
                        effect_receipt_digest =
                          successful.effect_receipt_digest;
                        output_digest = successful.output_digest;
                        attempt_count = List.length chain;
                        status = Action_succeeded })
                    actions
                in
                let engine_projection_digest =
                  digest_fields
                    ("run-swarm-bridge-engine-projection-v1"
                     :: List.concat_map
                          (fun (action : Run_topology.declarative_action) ->
                            let successful =
                              match successful_record action.stable_id with
                              | Some row -> row
                              | None -> assert false
                            in
                            [ action.stable_id; action.assigned_agent_id;
                              successful.dependency_input_digest;
                              successful.output_digest; "completed" ])
                          actions)
                in
                let initial_head =
                  match last initial_events with Some value -> value | None -> assert false
                in
                let final_head =
                  match last events with Some value -> value | None -> assert false
                in
                let provisional =
                  { run_id = context.run_id;
                    authority_digest =
                      admission.current_authority.authority_digest;
                    admission_digest = admission.admission_digest;
                    plan_digest = plan.plan_digest; ordered_action_receipts;
                    engine_projection_digest;
                    initial_head_sequence = initial_head.sequence;
                    initial_head_digest = initial_head.digest;
                    final_head_sequence = final_head.sequence;
                    final_head_digest = final_head.digest;
                    attempt_event_count = List.length suffix;
                    complete_stream_digest = complete_stream_digest events;
                    result_digest = "" }
                in
                Ok
                  { provisional with
                    result_digest = result_digest_of provisional }
            end

let execute_once ~(admission : admission) ~(authority : event_authority)
    ~(interpreter : Run_effect_authority.interpreter)
    ~(plan : admitted_plan) =
  let context = admission.context in
  if authority != admission.current_authority.event_authority
     || not (exact_context authority.context context)
  then execution_error context Execution_refused
      "execution authority differs from the admitted physical event authority"
  else
    match action_registry ~activity:admission.intent.activity with
    | Error issues ->
        execution_error context Execution_refused
          (String.concat "; "
             (List.map (fun (issue : diagnostic) -> issue.message) issues))
    | Ok registry ->
        begin match validate_plan ~admission ~action_registry:registry plan with
        | Error issues ->
            execution_error context Execution_refused
              (String.concat "; "
                 (List.map (fun (issue : diagnostic) -> issue.message) issues))
        | Ok () ->
            begin match
              Run_effect_authority.validate_admitted_interpreter
                ~activity:admission.intent.activity interpreter
            with
            | Error issues ->
                execution_error context Execution_refused
                  (String.concat "; "
                     (List.map
                        (fun (issue : Run_effect_authority.diagnostic) ->
                          issue.bytes)
                        issues))
            | Ok () ->
            begin match Run_event_store.events authority.store ~run_id:context.run_id with
            | Error message -> execution_error context Readback_invalid message
            | Ok initial_events ->
                begin match last initial_events with
                | None -> execution_error context Readback_invalid "event stream is empty"
                | Some head
                  when not
                    (Int64.equal head.sequence context.current_head.head_sequence
                     && String.equal head.digest
                          context.current_head.head_event_digest) ->
                    execution_error context Execution_refused
                      "durable head advanced before the engine call"
                | Some _ ->
                    let records = ref [] in
                    let records_lock = Mutex.create () in
                    let actions = registry.actions in
                    let execution_identity =
                      execution_identity ~run_id:context.run_id
                        ~activity:admission.intent.activity
                    in
                    let steps =
                      List.map
                        (make_step ~authority ~plan ~execution_identity
                           ~activity:admission.intent.activity ~interpreter
                           ~records ~records_lock)
                        actions
                    in
                    ignore (Atomic.fetch_and_add engine_call_count 1);
                    let engine =
                      Sop_execution.execute_sop_workflow ~steps ()
                    in
                    let records = with_mutex records_lock (fun () -> !records) in
                    validate_execution_readback ~admission ~authority ~plan
                      ~initial_events ~actions ~records engine
                end
            end
            end
        end

type claim_acquisition = Lead | Follow of execution_outcome

let execution_claim_key (admission : admission) (plan : admitted_plan) =
  digest_fields
    ([ "run-swarm-bridge-execution-claim-v1"; admission.admission_digest;
       plan.admission_digest; plan.registry_digest; plan.graph_digest;
       plan.plan_digest ]
     @ plan.admission_ids @ plan.plan_ids @ plan.ordered_action_ids
     @ plan.ordered_action_digests)

let acquire_execution_claim (claims : execution_claims) key =
  Mutex.lock claims.mutex;
  let rec await () =
    match Hashtbl.find_opt claims.states key with
    | None ->
        Hashtbl.add claims.states key Running;
        Mutex.unlock claims.mutex;
        Lead
    | Some (Finished outcome) ->
        Mutex.unlock claims.mutex;
        Follow outcome
    | Some Running ->
        Condition.wait claims.condition claims.mutex;
        await ()
  in
  await ()

let finish_execution_claim (claims : execution_claims) key outcome =
  Mutex.lock claims.mutex;
  Hashtbl.replace claims.states key (Finished outcome);
  Condition.broadcast claims.condition;
  Mutex.unlock claims.mutex

let await_existing_execution_claim (claims : execution_claims) key =
  Mutex.lock claims.mutex;
  let rec await () =
    match Hashtbl.find_opt claims.states key with
    | None -> Mutex.unlock claims.mutex; None
    | Some (Finished outcome) -> Mutex.unlock claims.mutex; Some outcome
    | Some Running ->
        Condition.wait claims.condition claims.mutex;
        await ()
  in
  await ()

let validate_admission_structure (admission : admission) =
  let context = admission.context in
  let reject message =
    Error [ diagnostic context Invalid_admission message ]
  in
  let current = admission.current_authority in
  let intent = admission.intent in
  let expected_current_authority_digest =
    digest_fields
      [ context.context_digest; context.current_head_digest;
        context.current_head.head_event_digest;
        context.current_head.authority_digest ]
  in
  let expected_activity_digest =
    Run_topology.admitted_activity_digest intent.activity
  in
  let expected_topology_authority_digest =
    Run_topology.admitted_activity_authority_digest intent.activity
  in
  let expected_intent_digest =
    digest_fields
      [ context.context_digest; expected_current_authority_digest;
        expected_activity_digest; expected_topology_authority_digest;
        Module_intent.source_digest; Run_fpp_authority.source_digest;
        Debug_intent.source_digest; External_access.source_digest ]
  in
  if not
      (exact_context context intent.context
       && exact_context context current.context
       && intent.current_authority.event_authority
            == current.event_authority
       && String.equal intent.current_authority.authority_digest
            current.authority_digest)
  then reject "structural admission carriers do not share exact authority"
  else if not
      (String.equal current.authority_digest
         expected_current_authority_digest
       && String.equal intent.activity_digest expected_activity_digest
       && String.equal intent.topology_authority_digest
            expected_topology_authority_digest
       && String.equal intent.module_intent_digest Module_intent.source_digest
       && String.equal intent.fpp_authority_digest Run_fpp_authority.source_digest
       && String.equal intent.debug_authority_digest Debug_intent.source_digest
       && String.equal intent.external_access_authority_digest
            External_access.source_digest
       && String.equal intent.intent_digest expected_intent_digest)
  then reject "structural intent or current-authority identity differs"
  else
    match Run_assurance.validate_bundle ~context admission.assurance with
    | Error issues ->
        reject
          (String.concat "; "
             (List.map (fun (issue : Run_safety.gate_error) -> issue.message)
                issues))
    | Ok () ->
        begin match
          Run_fast_path.validate_selection ~context ~activity:intent.activity
            admission.fast_path
        with
        | Error issues ->
            reject
              (String.concat "; "
                 (List.map
                    (fun (issue : Run_fast_path.diagnostic) -> issue.message)
                    issues))
        | Ok () ->
            let expected_admission_digest =
              digest_fields
                [ context.context_digest; intent.intent_digest;
                  current.authority_digest; admission.assurance.bundle_digest;
                  Run_fast_path.selection_digest admission.fast_path ]
            in
            if String.equal admission.admission_digest expected_admission_digest
            then Ok ()
            else reject "structural admission digest differs from its carriers"
        end

let validate_plan_structure ~(admission : admission)
    ~(action_registry : action_registry) (plan : admitted_plan) =
  let expected = expected_plan ~admission ~action_registry in
  if plan = expected then Ok ()
  else
    Error
      [ diagnostic admission.context Invalid_plan
          "structural plan differs from the exact admitted topology" ]

let execution_preflight ~(admission : admission)
    ~(interpreter : Run_effect_authority.interpreter) ~(plan : admitted_plan) =
  let context = admission.context in
  match action_registry ~activity:admission.intent.activity with
  | Error issues ->
      execution_error context Execution_refused
        (String.concat "; "
           (List.map (fun (issue : diagnostic) -> issue.message) issues))
  | Ok registry ->
      begin match validate_admission_structure admission with
      | Error issues ->
          execution_error context Execution_refused
            (String.concat "; "
               (List.map (fun (issue : diagnostic) -> issue.message) issues))
      | Ok () ->
          begin match
            validate_plan_structure ~admission ~action_registry:registry plan
          with
          | Error issues ->
              execution_error context Execution_refused
                (String.concat "; "
                   (List.map (fun (issue : diagnostic) -> issue.message) issues))
          | Ok () ->
              begin match
                Run_effect_authority.validate_admitted_interpreter
                  ~activity:admission.intent.activity interpreter
              with
              | Ok () -> Ok ()
              | Error issues ->
                  execution_error context Execution_refused
                    (String.concat "; "
                       (List.map
                          (fun (issue : Run_effect_authority.diagnostic) ->
                            issue.bytes)
                          issues))
              end
          end
      end

let execute ~(admission : admission) ~(authority : event_authority)
    ~(interpreter : Run_effect_authority.interpreter)
    ~(plan : admitted_plan) =
  let context = admission.context in
  if authority != admission.current_authority.event_authority
     || not (exact_context authority.context context)
  then execution_error context Execution_refused
      "execution authority differs from the admitted physical event authority"
  else
    match execution_preflight ~admission ~interpreter ~plan with
    | Error _ as refusal -> refusal
    | Ok () ->
        let key = execution_claim_key admission plan in
        begin match await_existing_execution_claim authority.execution_claims key with
        | Some outcome -> outcome
        | None ->
            begin match acquire_execution_claim authority.execution_claims key with
            | Follow outcome -> outcome
            | Lead ->
                let outcome =
                  match execute_once ~admission ~authority ~interpreter ~plan with
                  | outcome -> outcome
                  | exception exn ->
                      execution_error context Projection_invalid
                        ("bridge execution raised: " ^ Printexc.to_string exn)
                in
                finish_execution_claim authority.execution_claims key outcome;
                outcome
            end
        end

let payload_string name (event : Run_model.event) =
  match event.payload with
  | `Assoc fields ->
      begin match List.assoc_opt name fields with
      | Some (`String value) -> Some value
      | Some _ | None -> None
      end
  | _ -> None

let validate_result ~(admission : admission) ~(authority : event_authority)
    ~(interpreter : Run_effect_authority.interpreter) ~(plan : admitted_plan)
    (receipt : result) =
  let context = admission.context in
  let reject message = execution_error context Readback_invalid message in
  if authority != admission.current_authority.event_authority
     || not (exact_context authority.context context)
  then reject "result authority differs from the admitted physical authority"
  else
    match action_registry ~activity:admission.intent.activity with
    | Error issues ->
        reject
          (String.concat "; "
             (List.map (fun (issue : diagnostic) -> issue.message) issues))
    | Ok registry ->
        let expected_plan = expected_plan ~admission ~action_registry:registry in
        if plan <> expected_plan then reject "result plan is not canonical"
        else if not (String.equal receipt.run_id context.run_id) then
          reject "result run identity differs"
        else if not
            (String.equal receipt.authority_digest
               admission.current_authority.authority_digest)
        then reject "result authority identity differs"
        else if not
            (String.equal receipt.admission_digest admission.admission_digest)
        then reject "result admission identity differs"
        else if not (String.equal receipt.plan_digest plan.plan_digest) then
          reject "result plan identity differs"
        else if receipt.initial_head_sequence
                  <> context.current_head.head_sequence
                || not
                     (String.equal receipt.initial_head_digest
                        context.current_head.head_event_digest)
        then reject "result initial head differs from admission"
        else
          match Run_event_store.events authority.store ~run_id:context.run_id with
          | Error message -> reject message
          | Ok events ->
              let attempt_events =
                List.filter
                  (fun (event : Run_model.event) ->
                    event.sequence > receipt.initial_head_sequence)
                  events
              in
              let prefix_events =
                List.filter
                  (fun (event : Run_model.event) ->
                    event.sequence <= receipt.initial_head_sequence)
                  events
              in
              let is_attempt_event (event : Run_model.event) =
                match event.kind, event.subject with
                | (Run_model.Swarm_step_ready
                  | Run_model.Swarm_step_running
                  | Run_model.Swarm_step_terminal), Run_model.Attempt _ -> true
                | _ -> false
              in
              begin match last events with
              | None -> reject "result stream is empty"
              | Some final_head
                when final_head.sequence <> receipt.final_head_sequence
                     || not
                          (String.equal final_head.digest
                             receipt.final_head_digest) ->
                  reject "result final head differs from durable readback"
              | Some _
                when receipt.attempt_event_count <> List.length attempt_events
                     || not (List.for_all is_attempt_event attempt_events) ->
                  reject "result attempt-event denominator differs"
              | Some _
                when not
                  (String.equal receipt.complete_stream_digest
                     (complete_stream_digest events)) ->
                  reject "result complete-stream digest differs"
              | Some _ ->
                  begin match Run_snapshot.fold events with
                  | Error message -> reject message
                  | Ok snapshot ->
                      let derive_action
                          (action : Run_topology.declarative_action) =
                        let initial_attempt =
                          prefix_events
                          |> List.fold_left
                               (fun maximum (event : Run_model.event) ->
                                 match event.subject with
                                 | Run_model.Attempt
                                     (observed_action_id, attempt)
                                   when String.equal observed_action_id
                                          action.stable_id ->
                                     Int.max maximum attempt
                                 | _ -> maximum)
                               (-1)
                          |> (fun maximum -> maximum + 1)
                        in
                        let terminals =
                          attempt_events
                          |> List.filter_map
                               (fun (event : Run_model.event) ->
                                 match event.kind, event.subject with
                                 | Run_model.Swarm_step_terminal,
                                   Run_model.Attempt (action_id, attempt)
                                   when String.equal action_id action.stable_id ->
                                     Some (attempt, event)
                                 | _ -> None)
                          |> List.sort (fun (left, _) (right, _) ->
                               Int.compare left right)
                        in
                        let rec contiguous expected = function
                          | [] -> true
                          | (attempt, _) :: rest ->
                              attempt = expected
                              && contiguous (expected + 1) rest
                        in
                        match List.rev terminals with
                        | [] -> None
                        | (final_attempt, terminal) :: prior_rev ->
                            let lifecycle event =
                              payload_string "lifecycle" event
                            in
                            if not (contiguous initial_attempt terminals)
                               || lifecycle terminal <> Some "succeeded"
                               || not
                                    (List.for_all
                                       (fun (_, event) ->
                                         lifecycle event = Some "failed")
                                       prior_rev)
                               || Run_snapshot.attempt_state snapshot
                                    ~step:action.stable_id ~attempt:final_attempt
                                  <> Some
                                       (Run_snapshot.Attempt_terminal
                                          Run_model.Succeeded)
                            then None
                            else
                              begin match
                                payload_string "request_digest" terminal,
                                payload_string "effect_receipt_digest" terminal,
                                payload_string "output" terminal,
                                payload_string "output_digest" terminal,
                                payload_string "dependency_input_digest" terminal
                              with
                              | Some request_digest,
                                Some effect_receipt_digest, Some output,
                                Some output_digest, Some dependency_input_digest
                                when String.equal output_digest (sha256 output)
                                     && String.length effect_receipt_digest = 64 ->
                                  Some
                                    ({ action_id = action.stable_id;
                                       action_digest =
                                         Run_topology.action_digest_of action;
                                       request_digest; effect_receipt_digest;
                                       output_digest;
                                       attempt_count = List.length terminals;
                                       status = Action_succeeded },
                                     dependency_input_digest)
                              | _ -> None
                              end
                      in
                      let derived = List.map derive_action registry.actions in
                      if List.exists Option.is_none derived then
                        reject "a durable action receipt could not be reconstructed"
                      else
                        let derived = List.filter_map Fun.id derived in
                        let action_receipts : action_receipt list =
                          List.map fst derived
                        in
                        let engine_projection_digest =
                          digest_fields
                            ("run-swarm-bridge-engine-projection-v1"
                             :: (List.map2
                                   (fun (action : Run_topology.declarative_action)
                                        ((action_receipt : action_receipt),
                                         dependency_digest) ->
                                     [ action.stable_id;
                                       action.assigned_agent_id;
                                       dependency_digest;
                                       action_receipt.output_digest;
                                       "completed" ])
                                   registry.actions derived
                                 |> List.concat))
                        in
                        if receipt.ordered_action_receipts <> action_receipts then
                          reject "ordered action receipts differ from durable readback"
                        else if not
                            (String.equal receipt.engine_projection_digest
                               engine_projection_digest)
                        then reject "engine projection digest differs"
                        else if not
                            (String.equal receipt.result_digest
                               (result_digest_of receipt))
                        then reject "result digest differs"
                        else
                          let execution_identity =
                            execution_identity ~run_id:context.run_id
                              ~activity:admission.intent.activity
                          in
                          let query_matches
                              (action : Run_topology.declarative_action)
                              (action_receipt : action_receipt) =
                            let idempotency_key =
                              Run_swarm_preparation.idempotency_key
                                ~execution_identity
                                ~activity:admission.intent.activity ~action
                            in
                            match
                              Run_effect_authority.query interpreter
                                ~idempotency_key
                            with
                            | Ok (Some (Run_effect_authority.Applied observed)) ->
                                String.equal observed.idempotency_key
                                  idempotency_key
                                && String.equal observed.request_digest
                                     action_receipt.request_digest
                                && String.equal observed.receipt_digest
                                     action_receipt.effect_receipt_digest
                                && String.equal
                                     (sha256
                                        (redacted_evidence_output observed))
                                     action_receipt.output_digest
                            | Ok None
                            | Ok (Some (Run_effect_authority.Pending _))
                            | Ok (Some
                                    (Run_effect_authority.Indeterminate_effect _))
                            | Error _ -> false
                          in
                          if
                            List.for_all2 query_matches registry.actions
                              receipt.ordered_action_receipts
                          then Ok ()
                          else reject
                              "effect ledger differs from terminal action receipts"
                  end
              end

module For_test = struct
  type intent_mutation =
    | Debug_authority_digest
    | External_access_authority_digest

  let mutate_intent mutation (intent : typed_intent) =
    match mutation with
    | Debug_authority_digest ->
        { intent with
          debug_authority_digest =
            sha256 (intent.debug_authority_digest ^ ":mutant") }
    | External_access_authority_digest ->
        { intent with
          external_access_authority_digest =
            sha256 (intent.external_access_authority_digest ^ ":mutant") }

  let intent_authorities_current (intent : typed_intent) =
    String.equal intent.module_intent_digest Module_intent.source_digest
    && String.equal intent.fpp_authority_digest Run_fpp_authority.source_digest
    && String.equal intent.debug_authority_digest Debug_intent.source_digest
    && String.equal intent.external_access_authority_digest
         External_access.source_digest

  let event_sources ~wall_now_ns ~monotonic_now_ns ~event_id ~readback_agrees =
    { wall_now_ns; monotonic_now_ns; event_id; readback_agrees; kind = Test }

  let action_registry_from_declaration = validate_action_declaration

  let validate_admission_identities ~(context : Run_safety.gate_context)
      ~intent_context_digest
      ~current_context_digest ~assurance_context_digest
      ~selection_context_digest =
    let expected = context.Run_safety.context_digest in
    if
      List.for_all (String.equal expected)
        [ intent_context_digest; current_context_digest;
          assurance_context_digest; selection_context_digest ]
    then Ok ()
    else
      Error
        [ diagnostic context Invalid_admission
            "admission identities differ from the exact context digest" ]

  type registry_mutation =
    | Registry_activity_identity
    | Registry_action_order
    | Registry_digest

  let mutate_action_registry mutation (registry : action_registry) =
    match mutation with
    | Registry_activity_identity ->
        { registry with activity_id = registry.activity_id ^ ":mutant" }
    | Registry_action_order ->
        { registry with actions = List.rev registry.actions;
                        action_digests = List.rev registry.action_digests }
    | Registry_digest ->
        { registry with
          registry_digest = sha256 (registry.registry_digest ^ ":mutant") }

  type plan_mutation =
    | Duplicate_admission_id
    | Duplicate_plan_id
    | Plan_action_order
    | Plan_graph_digest
    | Plan_digest

  let mutate_plan mutation (plan : admitted_plan) =
    match mutation with
    | Duplicate_admission_id ->
        { plan with admission_ids = plan.admission_ids @ plan.admission_ids }
    | Duplicate_plan_id ->
        { plan with plan_ids = plan.plan_ids @ plan.plan_ids }
    | Plan_action_order ->
        { plan with ordered_action_ids = List.rev plan.ordered_action_ids;
                    ordered_action_digests = List.rev plan.ordered_action_digests }
    | Plan_graph_digest ->
        { plan with graph_digest = sha256 (plan.graph_digest ^ ":mutant") }
    | Plan_digest ->
        { plan with plan_digest = sha256 (plan.plan_digest ^ ":mutant") }

  let validate_plan = validate_plan

  type result_mutation =
    | Result_authority_identity
    | Result_admission_identity
    | Result_plan_identity
    | Result_action_order
    | Result_action_digest
    | Result_request_digest
    | Result_effect_digest
    | Result_output_digest
    | Result_attempt_count
    | Result_action_status
    | Result_engine_projection
    | Result_initial_head
    | Result_final_head
    | Result_attempt_event_count
    | Result_complete_stream
    | Result_digest

  let mutant_digest value = sha256 (value ^ ":mutant")

  let mutate_first_action update (result : result) =
    let fallback =
      { action_id = "action.mutant"; action_digest = String.make 64 '0';
        request_digest = String.make 64 '1';
        effect_receipt_digest = String.make 64 '2';
        output_digest = String.make 64 '3'; attempt_count = 1;
        status = Action_succeeded }
    in
    match result.ordered_action_receipts with
    | [] -> { result with ordered_action_receipts = [ update fallback ] }
    | first :: rest ->
        { result with ordered_action_receipts = update first :: rest }

  let mutate_result mutation (result : result) =
    match mutation with
    | Result_authority_identity ->
        { result with authority_digest = mutant_digest result.authority_digest }
    | Result_admission_identity ->
        { result with admission_digest = mutant_digest result.admission_digest }
    | Result_plan_identity ->
        { result with plan_digest = mutant_digest result.plan_digest }
    | Result_action_order ->
        { result with
          ordered_action_receipts = List.rev result.ordered_action_receipts }
    | Result_action_digest ->
        mutate_first_action
          (fun row ->
            { row with action_digest = mutant_digest row.action_digest })
          result
    | Result_request_digest ->
        mutate_first_action
          (fun row ->
            { row with request_digest = mutant_digest row.request_digest })
          result
    | Result_effect_digest ->
        mutate_first_action
          (fun row ->
            { row with
              effect_receipt_digest = mutant_digest row.effect_receipt_digest })
          result
    | Result_output_digest ->
        mutate_first_action
          (fun row ->
            { row with output_digest = mutant_digest row.output_digest })
          result
    | Result_attempt_count ->
        mutate_first_action
          (fun row -> { row with attempt_count = row.attempt_count + 1 }) result
    | Result_action_status ->
        mutate_first_action
          (fun row -> { row with status = Action_failed }) result
    | Result_engine_projection ->
        { result with
          engine_projection_digest =
            mutant_digest result.engine_projection_digest }
    | Result_initial_head ->
        { result with initial_head_sequence = Int64.succ result.initial_head_sequence;
                      initial_head_digest = mutant_digest result.initial_head_digest }
    | Result_final_head ->
        { result with final_head_sequence = Int64.succ result.final_head_sequence;
                      final_head_digest = mutant_digest result.final_head_digest }
    | Result_attempt_event_count ->
        { result with attempt_event_count = result.attempt_event_count + 1 }
    | Result_complete_stream ->
        { result with
          complete_stream_digest = mutant_digest result.complete_stream_digest }
    | Result_digest ->
        { result with result_digest = mutant_digest result.result_digest }

  let reset_engine_call_count () = Atomic.set engine_call_count 0
  let engine_call_count () = Atomic.get engine_call_count
  let reset_preparation_call_count () = Atomic.set preparation_call_count 0
  let preparation_call_count () = Atomic.get preparation_call_count

  let arm_preparation_failures authority ~action_id ~count =
    if String.trim action_id = "" then Error "action id must be nonempty"
    else if count < 1 || count > 2 then
      Error "preparation failure count must be one or two"
    else
      with_mutex authority.execution_faults.mutex (fun () ->
        Hashtbl.replace authority.execution_faults.preparation_failures action_id
          count;
        Ok ())

  let fail_next_terminal_append authority ~action_id =
    if String.trim action_id = "" then Error "action id must be nonempty"
    else
      with_mutex authority.execution_faults.mutex (fun () ->
        authority.execution_faults.terminal_append_failure <- Some action_id;
        Ok ())

end
