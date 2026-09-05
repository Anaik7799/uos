type manifest = { source_digest : string; component_ids : string list;
  port_ids : string list; channel_ids : string list; requirement_ids : string list;
  edge_ids : string list; lifecycle_machine_ids : string list;
  fault_event_ids : string list; gate_command_ids : string list;
  activity_ids : string list }

open Run_topology

let manifest =
  { source_digest = Run_topology.source_digest;
    component_ids = List.map
        (fun (item : Run_topology.component) -> item.stable_id)
        Run_topology.authority.components;
    port_ids = List.map
        (fun (item : Run_topology.port) -> item.stable_id)
        Run_topology.authority.ports;
    channel_ids = List.map
        (fun (item : Run_topology.channel) -> item.stable_id)
        Run_topology.authority.channels;
    requirement_ids = List.map
        (fun (item : Run_topology.requirement) -> item.stable_id)
        Run_topology.authority.requirements;
    edge_ids = List.map
        (fun (item : Run_topology.edge) -> item.stable_id)
        Run_topology.authority.edges;
    lifecycle_machine_ids = List.map
        (fun (item : Run_topology.lifecycle_machine) -> item.stable_id)
        Run_topology.authority.lifecycle_machines;
    fault_event_ids = List.map
        (fun (item : Run_topology.fault_event) -> item.stable_id)
        Run_topology.authority.fault_events;
    gate_command_ids = List.map
        (fun (item : Run_topology.gate_command) -> item.stable_id)
        Run_topology.authority.gate_commands;
    activity_ids = List.map
        (fun (item : Run_topology.declarative_activity) -> item.stable_id)
        Run_topology.authority.activities }

let sanitize value =
  "Ops_"
  ^ String.map
      (function
        | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' as character -> character
        | _ -> '_')
      value

let escape_sysml value =
  let buffer = Buffer.create (String.length value + 16) in
  String.iter
    (fun character ->
      match character with
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\t' -> Buffer.add_string buffer "\\t"
      | '\r' -> Buffer.add_string buffer "\\r"
      | character when Char.code character < 0x20 ->
          Buffer.add_string buffer (Printf.sprintf "\\u%04X" (Char.code character))
      | character -> Buffer.add_char buffer character)
    value;
  Buffer.contents buffer

let escape_turtle value =
  let buffer = Buffer.create (String.length value + 16) in
  String.iter
    (fun character ->
      match character with
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\t' -> Buffer.add_string buffer "\\t"
      | '\r' -> Buffer.add_string buffer "\\r"
      | character when Char.code character < 0x20 ->
          Buffer.add_string buffer (Printf.sprintf "\\u%04X" (Char.code character))
      | character -> Buffer.add_char buffer character)
    value;
  Buffer.contents buffer

let kind_name = function
  | Run_topology.Intent -> "Intent" | Evidence -> "Evidence" | State -> "State"
  | Telemetry -> "Telemetry" | Scene -> "Scene"

let direction_name = function
  | Run_topology.Input -> "Input" | Output -> "Output"

let edge_kind_name = function
  | Run_topology.Admission -> "Admission" | Execution -> "Execution"
  | Evidence_flow -> "EvidenceFlow" | State_flow -> "StateFlow"
  | Projection -> "Projection"

let fault_severity_name = function
  | Run_topology.Fault_diagnostic -> "Diagnostic"
  | Fault_warning -> "Warning"
  | Fault_fatal -> "Fatal"

let gate_kind_name = function
  | Run_topology.Formal_gate -> "Formal"
  | Stress_gate -> "Stress"
  | Reliability_gate -> "Reliability"
  | Full_gate -> "Full"
  | Swarm_verification -> "SwarmVerification"

let effect_kind_name = Run_topology.effect_kind_id

let json_strings values = `List (List.map (fun value -> `String value) values)

let miq_route_json (route : Run_topology.miq_route) =
  `Assoc
    [ ("selectorId", `String route.selector_id);
      ("requiredCapabilityId", `String route.required_capability_id);
      ("assignedAgentId", `String route.assigned_agent_id) ]

let action_work_fields = function
  | Run_topology.Topology_gate ->
      [ ("workKind", `String "topology-gate") ]
  | Repository_build { profile; build_command } ->
      [ ("workKind", `String "repository-build");
        ("profileId", `String
           (match profile with Verification_fast -> "fast"
            | Verification_full -> "full"));
        ("buildCommand", `String build_command) ]
  | Repository_verification_suite { profile; suite_id; executable } ->
      [ ("workKind", `String "repository-verification-suite");
        ("profileId", `String
           (match profile with Verification_fast -> "fast"
            | Verification_full -> "full"));
        ("suiteId", `String suite_id);
        ("executable", `String executable) ]
  | (Clock_work _ | Filesystem_work _ | External_resource_work _
    | Repository_source_work _ | Approval_nonce_work _ | Writer_lease_work _
    | Network_scope_work _ | Credential_lease_work _
    | Activation_transition_work _ | Mutation_frontier_work _
    | Materialization_work _ | Candidate_verification_work _
    | Formal_oracle_work _ | Jujutsu_work _ | Jujutsu_readback_work _
    | Completion_receipt_work _) as work ->
      [ ("workKind", `String "closed-task7a-work");
        ("workId", `String (Run_topology.action_work_id work)) ]

let action_json (item : Run_topology.declarative_action) =
  `Assoc
    ([ ("stableId", `String item.stable_id);
      ("commandId", `String item.command_id);
      ("assignedAgentId", `String item.assigned_agent_id);
      ("dependencyIds", json_strings item.dependency_ids);
      ("selectorId", `String item.selector_id);
      ("requiredCapabilityId", `String item.required_capability_id);
      ("contextRequirementIds", json_strings item.context_requirement_ids);
      ("targetComponentId", `String item.target_component_id);
      ("effectKind", `String (effect_kind_name item.effect_kind));
      ("preparationId", `String item.preparation_id) ]
     @ action_work_fields item.work)

let actions_json (item : Run_topology.declarative_activity) =
  `List (List.map action_json item.actions)

let activity_fields (item : Run_topology.declarative_activity) =
  [ ("actions", Yojson.Safe.to_string (actions_json item));
    ("targetState", item.target_state);
    ("requiredCapabilityIds",
     Yojson.Safe.to_string (json_strings item.required_capability_ids));
    ("contextRequirementIds",
     Yojson.Safe.to_string (json_strings item.context_requirement_ids));
    ("miqRoutes",
     Yojson.Safe.to_string (`List (List.map miq_route_json item.miq_routes)));
    ("effectKinds",
     Yojson.Safe.to_string
       (json_strings (List.map effect_kind_name item.effect_kinds)));
    ("commandIds", Yojson.Safe.to_string (json_strings item.command_ids));
    ("constraints", Yojson.Safe.to_string (json_strings item.constraints));
    ("successCriteria",
     Yojson.Safe.to_string (json_strings item.success_criteria)) ]

let activity_payload_fields (item : Run_topology.declarative_activity) =
  [ ("actions", actions_json item);
    ("bridgeId", `String item.bridge_component_id);
      ("targetId", `String item.target_component_id);
      ("targetState", `String item.target_state);
      ("intent", `String item.intent);
      ("requiredCapabilityIds", json_strings item.required_capability_ids);
      ("contextRequirementIds", json_strings item.context_requirement_ids);
      ("miqRoutes", `List (List.map miq_route_json item.miq_routes));
      ("effectKinds",
       json_strings (List.map effect_kind_name item.effect_kinds));
      ("commandIds", json_strings item.command_ids);
      ("constraints", json_strings item.constraints);
      ("successCriteria", json_strings item.success_criteria) ]

let activity_json (item : Run_topology.declarative_activity) =
  `Assoc
    (("stableId", `String item.stable_id) :: activity_payload_fields item)

let oml_blocks () =
  let open Hermes_sysml.Sysml_types in
  List.map
    (fun (component : Run_topology.component) ->
      let ports =
        Run_topology.authority.ports
        |> List.filter (fun (item : Run_topology.port) ->
               item.component_id = component.stable_id)
        |> List.map (fun (item : Run_topology.port) : Hermes_sysml.Sysml_types.part_def ->
             { id = sanitize item.stable_id; name = item.name;
               type_id = "Operations" ^ kind_name item.kind ^ "Port";
               multiplicity = (if item.count = 1 then Single else Collection) })
      in
      let values =
        Run_topology.authority.channels
        |> List.filter (fun (item : Run_topology.channel) ->
               item.component_id = component.stable_id)
        |> List.map (fun (item : Run_topology.channel) : Hermes_sysml.Sysml_types.value_property ->
             { id = sanitize item.stable_id; name = item.stable_id;
               property_type = String; multiplicity = Single })
      in
      { Hermes_sysml.Sysml_types.id = sanitize component.stable_id;
        name = component.purpose; supertypes = [ "OperationsComponent" ];
        parts = ports; value_properties = values })
    Run_topology.authority.components

let sysml_v2 () =
  let buffer = Buffer.create 131_072 in
  let add fmt = Printf.ksprintf (Buffer.add_string buffer) fmt in
  add "// GENERATED from Run_topology.authority; do not edit.\n";
  add "package HermesOperations {\n";
  add "  attribute sourceDigest : String = \"%s\";\n" manifest.source_digest;
  List.iter
    (fun (item : Run_topology.component) ->
      add "  part def %s { attribute stableId : String = \"%s\"; attribute purpose : String = \"%s\"; }\n"
        (sanitize item.stable_id) (escape_sysml item.stable_id)
        (escape_sysml item.purpose))
    Run_topology.authority.components;
  List.iter
    (fun (item : Run_topology.port) ->
      add "  port def %s { attribute stableId : String = \"%s\"; attribute ownerId : String = \"%s\"; attribute direction : String = \"%s\"; attribute payloadKind : String = \"%s\"; attribute count : Integer = %d; }\n"
        (sanitize item.stable_id) (escape_sysml item.stable_id)
        (escape_sysml item.component_id) (direction_name item.direction)
        (kind_name item.kind) item.count)
    Run_topology.authority.ports;
  List.iter
    (fun (item : Run_topology.channel) ->
      add "  attribute def %s { attribute stableId : String = \"%s\"; attribute ownerId : String = \"%s\"; attribute fppName : String = \"%s\"; }\n"
        (sanitize item.stable_id) (escape_sysml item.stable_id)
        (escape_sysml item.component_id) (escape_sysml item.fpp_name))
    Run_topology.authority.channels;
  List.iter
    (fun (item : Run_topology.requirement) ->
      add "  requirement def %s { attribute stableId : String = \"%s\"; attribute verifierId : String = \"%s\"; attribute source : String = \"%s\"; attribute statement : String = \"%s\"; }\n"
        (sanitize item.stable_id) (escape_sysml item.stable_id)
        (escape_sysml item.verifier_id) (escape_sysml item.source)
        (escape_sysml item.statement))
    Run_topology.authority.requirements;
  List.iter
    (fun (item : Run_topology.lifecycle_machine) ->
      add "  state def %s { attribute stableId : String = \"%s\"; attribute ownerId : String = \"%s\"; attribute instanceId : String = \"%s\"; attribute initialState : String = \"%s\"; attribute stateIds : String = \"%s\"; }\n"
        (sanitize item.stable_id) (escape_sysml item.stable_id)
        (escape_sysml item.component_id) (escape_sysml item.instance_id)
        (escape_sysml item.initial_state)
        (escape_sysml
           (String.concat ","
              (List.map (fun (state : Run_topology.lifecycle_state) ->
                 state.stable_id) item.states))))
    Run_topology.authority.lifecycle_machines;
  List.iter
    (fun (item : Run_topology.fault_event) ->
      add "  event def %s { attribute stableId : String = \"%s\"; attribute ownerId : String = \"%s\"; attribute severity : String = \"%s\"; attribute format : String = \"%s\"; }\n"
        (sanitize item.stable_id) (escape_sysml item.stable_id)
        (escape_sysml item.component_id) (fault_severity_name item.severity)
        (escape_sysml item.format))
    Run_topology.authority.fault_events;
  List.iter
    (fun (item : Run_topology.gate_command) ->
      add "  action def %s { attribute stableId : String = \"%s\"; attribute ownerId : String = \"%s\"; attribute gateKind : String = \"%s\"; attribute intentId : String = \"%s\"; }\n"
        (sanitize item.stable_id) (escape_sysml item.stable_id)
        (escape_sysml item.component_id) (gate_kind_name item.kind)
        (escape_sysml item.intent_id))
    Run_topology.authority.gate_commands;
  List.iter
    (fun (item : Run_topology.declarative_activity) ->
      add "  action def %s { attribute stableId : String = \"%s\"; attribute bridgeId : String = \"%s\"; attribute targetId : String = \"%s\"; attribute intent : String = \"%s\";"
        (sanitize item.stable_id) (escape_sysml item.stable_id)
        (escape_sysml item.bridge_component_id)
        (escape_sysml item.target_component_id) (escape_sysml item.intent);
      List.iter
        (fun (name, value) ->
          add " attribute %s : String = \"%s\";" name (escape_sysml value))
        (activity_fields item);
      add " }\n")
    Run_topology.authority.activities;
  List.iter
    (fun (item : Run_topology.edge) ->
      add "  connection def %s { attribute stableId : String = \"%s\"; attribute kind : String = \"%s\"; attribute sourceId : String = \"%s\"; attribute targetId : String = \"%s\"; }\n"
        (sanitize item.stable_id) (escape_sysml item.stable_id)
        (edge_kind_name item.kind) (escape_sysml item.from_component)
        (escape_sysml item.to_component))
    Run_topology.authority.edges;
  add "}\n";
  Buffer.contents buffer

let turtle_row buffer kind stable_id fields =
  let add fmt = Printf.ksprintf (Buffer.add_string buffer) fmt in
  add "ops:%s a ops:%s ; ops:stableId \"%s\""
    (sanitize stable_id) kind (escape_turtle stable_id);
  List.iter
    (fun (name, value) -> add " ; ops:%s \"%s\"" name (escape_turtle value))
    fields;
  add " .\n"

let oml_owl () =
  let buffer = Buffer.create 131_072 in
  let add fmt = Printf.ksprintf (Buffer.add_string buffer) fmt in
  add "# GENERATED from Run_topology.authority; do not edit.\n";
  add "@prefix ops: <https://hermes.local/operations#> .\n";
  add "@prefix owl: <http://www.w3.org/2002/07/owl#> .\n";
  add "ops:HermesOperations a owl:Ontology .\n";
  add "ops:model ops:sourceDigest \"%s\" .\n" manifest.source_digest;
  List.iter
    (fun (item : Run_topology.component) ->
      turtle_row buffer "Component" item.stable_id [ ("purpose", item.purpose) ])
    Run_topology.authority.components;
  List.iter
    (fun (item : Run_topology.port) ->
      turtle_row buffer "Port" item.stable_id
        [ ("ownerId", item.component_id); ("direction", direction_name item.direction);
          ("payloadKind", kind_name item.kind) ])
    Run_topology.authority.ports;
  List.iter
    (fun (item : Run_topology.channel) ->
      turtle_row buffer "Channel" item.stable_id
        [ ("ownerId", item.component_id); ("fppName", item.fpp_name) ])
    Run_topology.authority.channels;
  List.iter
    (fun (item : Run_topology.requirement) ->
      turtle_row buffer "Requirement" item.stable_id
        [ ("verifierId", item.verifier_id); ("source", item.source);
          ("statement", item.statement) ])
    Run_topology.authority.requirements;
  List.iter
    (fun (item : Run_topology.lifecycle_machine) ->
      turtle_row buffer "LifecycleMachine" item.stable_id
        [ ("ownerId", item.component_id); ("instanceId", item.instance_id);
          ("initialState", item.initial_state);
          ("stateIds", String.concat ","
             (List.map (fun (state : Run_topology.lifecycle_state) ->
                state.stable_id) item.states)) ])
    Run_topology.authority.lifecycle_machines;
  List.iter
    (fun (item : Run_topology.fault_event) ->
      turtle_row buffer "FaultEvent" item.stable_id
        [ ("ownerId", item.component_id);
          ("severity", fault_severity_name item.severity);
          ("format", item.format) ])
    Run_topology.authority.fault_events;
  List.iter
    (fun (item : Run_topology.gate_command) ->
      turtle_row buffer "GateCommand" item.stable_id
        [ ("ownerId", item.component_id); ("gateKind", gate_kind_name item.kind);
          ("intentId", item.intent_id) ])
    Run_topology.authority.gate_commands;
  List.iter
    (fun (item : Run_topology.declarative_activity) ->
      turtle_row buffer "DeclarativeActivity" item.stable_id
        ([ ("bridgeId", item.bridge_component_id);
           ("targetId", item.target_component_id); ("intent", item.intent) ]
         @ activity_fields item))
    Run_topology.authority.activities;
  List.iter
    (fun (item : Run_topology.edge) ->
      turtle_row buffer "Edge" item.stable_id
        [ ("edgeKind", edge_kind_name item.kind);
          ("sourceId", item.from_component); ("targetId", item.to_component) ])
    Run_topology.authority.edges;
  Buffer.contents buffer

let manifest_json value =
  `Assoc
    [ ("sourceDigest", `String value.source_digest);
      ("componentIds", json_strings value.component_ids);
      ("portIds", json_strings value.port_ids);
      ("channelIds", json_strings value.channel_ids);
      ("requirementIds", json_strings value.requirement_ids);
      ("edgeIds", json_strings value.edge_ids);
      ("lifecycleMachineIds", json_strings value.lifecycle_machine_ids);
      ("faultEventIds", json_strings value.fault_event_ids);
      ("gateCommandIds", json_strings value.gate_command_ids);
      ("activityIds", json_strings value.activity_ids) ]

let element_json kind stable_id fields =
  `Assoc ([ ("kind", `String kind); ("stableId", `String stable_id) ] @ fields)

let openmbee_mms () =
  let components =
    List.map
      (fun (item : Run_topology.component) ->
        element_json "component" item.stable_id
          [ ("name", `String item.stable_id); ("documentation", `String item.purpose) ])
      Run_topology.authority.components
  in
  let ports =
    List.map
      (fun (item : Run_topology.port) ->
        element_json "port" item.stable_id
          [ ("ownerId", `String item.component_id); ("name", `String item.name);
            ("direction", `String (direction_name item.direction));
            ("payloadKind", `String (kind_name item.kind)); ("count", `Int item.count) ])
      Run_topology.authority.ports
  in
  let channels =
    List.map
      (fun (item : Run_topology.channel) ->
        element_json "channel" item.stable_id
          ([ ("ownerId", `String item.component_id); ("fppName", `String item.fpp_name) ]
           @ match item.metric_id with None -> [] | Some id -> [ ("metricId", `String id) ]))
      Run_topology.authority.channels
  in
  let requirements =
    List.map
      (fun (item : Run_topology.requirement) ->
        element_json "requirement" item.stable_id
          [ ("statement", `String item.statement); ("verifierId", `String item.verifier_id);
            ("source", `String item.source);
            ("coveredElements", json_strings item.covered_elements) ])
      Run_topology.authority.requirements
  in
  let edges =
    List.map
      (fun (item : Run_topology.edge) ->
        element_json "edge" item.stable_id
          [ ("edgeKind", `String (edge_kind_name item.kind));
            ("sourceId", `String item.from_component); ("sourcePort", `String item.from_port);
            ("targetId", `String item.to_component); ("targetPort", `String item.to_port) ])
      Run_topology.authority.edges
  in
  let lifecycle_machines =
    List.map
      (fun (item : Run_topology.lifecycle_machine) ->
        element_json "lifecycle-machine" item.stable_id
          [ ("ownerId", `String item.component_id);
            ("instanceId", `String item.instance_id);
            ("initialState", `String item.initial_state);
            ("stateIds", json_strings
               (List.map (fun (state : Run_topology.lifecycle_state) ->
                  state.stable_id) item.states)) ])
      Run_topology.authority.lifecycle_machines
  in
  let fault_events =
    List.map
      (fun (item : Run_topology.fault_event) ->
        element_json "fault-event" item.stable_id
          [ ("ownerId", `String item.component_id);
            ("severity", `String (fault_severity_name item.severity));
            ("format", `String item.format) ])
      Run_topology.authority.fault_events
  in
  let gate_commands =
    List.map
      (fun (item : Run_topology.gate_command) ->
        element_json "gate-command" item.stable_id
          [ ("ownerId", `String item.component_id);
            ("gateKind", `String (gate_kind_name item.kind));
            ("intentId", `String item.intent_id) ])
      Run_topology.authority.gate_commands
  in
  let activities =
    List.map
      (fun (item : Run_topology.declarative_activity) ->
        element_json "declarative-activity" item.stable_id
          (activity_payload_fields item))
      Run_topology.authority.activities
  in
  `Assoc
    [ ("schema", `String "openmbee-mms-element-projection/v1");
      ("authority", `String "Run_topology.authority");
      ("sourceDigest", `String manifest.source_digest);
      ("manifest", manifest_json manifest);
      ("elements", `List
         (components @ ports @ channels @ requirements @ edges
          @ lifecycle_machines @ fault_events @ gate_commands @ activities)) ]
  |> Yojson.Safe.pretty_to_string

let fpp_dictionary () =
  match
    Fpp_model.to_dictionary ~project_version:manifest.source_digest
      Run_topology.model ~topology:"HermesOperations"
  with
  | Error message ->
      `Assoc
        [ ("error", `String message); ("sourceDigest", `String manifest.source_digest) ]
      |> Yojson.Safe.pretty_to_string
  | Ok (`Assoc fields) ->
      `Assoc
        (fields
         @ [ ("operationsModel", manifest_json manifest);
             ("operationsActivities",
              `List
                (List.map activity_json Run_topology.authority.activities)) ])
      |> Yojson.Safe.pretty_to_string
  | Ok _ ->
      `Assoc
        [ ("error", `String "FPP dictionary is not an object");
          ("sourceDigest", `String manifest.source_digest) ]
      |> Yojson.Safe.pretty_to_string

let outputs () =
  [ ("generated/mbse/operations/operations.sysml", sysml_v2 ());
    ("generated/mbse/operations/operations.ttl", oml_owl ());
    ("generated/mbse/operations/operations-mms.json", openmbee_mms ());
    ("generated/mbse/operations/operations-fpp.json", fpp_dictionary ()) ]

let find_substring ~needle text =
  let width = String.length needle and length = String.length text in
  let rec loop index =
    if index + width > length then None
    else if String.sub text index width = needle then Some index
    else loop (index + 1)
  in
  if width = 0 then Some 0 else loop 0

let contains text needle = Option.is_some (find_substring ~needle text)

let decoded_quoted_after marker text =
  match find_substring ~needle:marker text with
  | None -> None
  | Some marker_index ->
      let start = marker_index + String.length marker in
      let length = String.length text in
      let buffer = Buffer.create 1_024 in
      let rec loop index escaped =
        if index >= length then None
        else
          let character = text.[index] in
          if character = '"' && not escaped then
            try Some (Scanf.unescaped (Buffer.contents buffer))
            with Scanf.Scan_failure _ -> None
          else begin
            Buffer.add_char buffer character;
            loop (index + 1) (character = '\\' && not escaped)
          end
      in
      loop start false

let action_graph_from_quoted ~activity_id marker text =
  let activity_line =
    String.split_on_char '\n' text
    |> List.find_opt (fun line -> contains line activity_id)
  in
  match Option.bind activity_line (decoded_quoted_after marker) with
  | None -> None
  | Some encoded ->
      begin
        try Some (Yojson.Safe.from_string encoded)
        with Yojson.Json_error _ -> None
      end

let action_graph_from_json ~activity_id ~container text =
  try
    match Yojson.Safe.from_string text with
    | `Assoc fields ->
        begin match List.assoc_opt container fields with
        | Some (`List elements) ->
            List.find_map
              (function
                | `Assoc fields
                  when List.assoc_opt "stableId" fields
                       = Some (`String activity_id) ->
                    List.assoc_opt "actions" fields
                | _ -> None)
              elements
        | _ -> None
        end
    | _ -> None
  with Yojson.Json_error _ -> None

let rec normalize_json = function
  | `Assoc fields ->
      `Assoc
        (fields
         |> List.map (fun (name, value) -> (name, normalize_json value))
         |> List.sort (fun (left, _) (right, _) -> String.compare left right))
  | `List values -> `List (List.map normalize_json values)
  | value -> value

let equal_action_graph left right =
  normalize_json left = normalize_json right

let quoted_after marker line =
  match find_substring ~needle:marker line with
  | None -> None
  | Some index ->
      let first = index + String.length marker in
      begin match String.index_from_opt line first '"' with
      | None -> None
      | Some last -> Some (String.sub line first (last - first))
      end

let starts prefix line = String.starts_with ~prefix line

let manifest_of_sysml text =
  let digest = ref None and components = ref [] and ports = ref []
  and channels = ref [] and requirements = ref [] and edges = ref []
  and lifecycle_machines = ref [] and fault_events = ref []
  and gate_commands = ref [] and activities = ref [] in
  List.iter
    (fun line ->
      if starts "  attribute sourceDigest" line then
        digest := quoted_after "attribute sourceDigest : String = \"" line
      else
        match quoted_after "attribute stableId : String = \"" line with
        | None -> ()
        | Some id when starts "  part def " line -> components := id :: !components
        | Some id when starts "  port def " line -> ports := id :: !ports
        | Some id when starts "  attribute def " line -> channels := id :: !channels
        | Some id when starts "  requirement def " line -> requirements := id :: !requirements
        | Some id when starts "  connection def " line -> edges := id :: !edges
        | Some id when starts "  state def " line ->
            lifecycle_machines := id :: !lifecycle_machines
        | Some id when starts "  event def " line -> fault_events := id :: !fault_events
        | Some id when starts "  action def " line && contains line "gateKind" ->
            gate_commands := id :: !gate_commands
        | Some id when starts "  action def " line && contains line "bridgeId" ->
            activities := id :: !activities
        | Some _ -> ())
    (String.split_on_char '\n' text);
  match !digest with
  | None -> Error "SysML source digest is missing"
  | Some source_digest -> Ok
      { source_digest; component_ids = List.rev !components; port_ids = List.rev !ports;
        channel_ids = List.rev !channels; requirement_ids = List.rev !requirements;
        edge_ids = List.rev !edges;
        lifecycle_machine_ids = List.rev !lifecycle_machines;
        fault_event_ids = List.rev !fault_events;
        gate_command_ids = List.rev !gate_commands;
        activity_ids = List.rev !activities }

let manifest_of_turtle text =
  let digest = ref None and components = ref [] and ports = ref []
  and channels = ref [] and requirements = ref [] and edges = ref []
  and lifecycle_machines = ref [] and fault_events = ref []
  and gate_commands = ref [] and activities = ref [] in
  let capture kind target line =
    let marker = " a ops:" ^ kind ^ " ; ops:stableId \"" in
    match quoted_after marker line with None -> () | Some id -> target := id :: !target
  in
  List.iter
    (fun line ->
      if starts "ops:model ops:sourceDigest" line then
        digest := quoted_after "ops:model ops:sourceDigest \"" line
      else begin
        capture "Component" components line; capture "Port" ports line;
        capture "Channel" channels line; capture "Requirement" requirements line;
        capture "Edge" edges line; capture "LifecycleMachine" lifecycle_machines line;
        capture "FaultEvent" fault_events line; capture "GateCommand" gate_commands line;
        capture "DeclarativeActivity" activities line
      end)
    (String.split_on_char '\n' text);
  match !digest with
  | None -> Error "Turtle source digest is missing"
  | Some source_digest -> Ok
      { source_digest; component_ids = List.rev !components; port_ids = List.rev !ports;
        channel_ids = List.rev !channels; requirement_ids = List.rev !requirements;
        edge_ids = List.rev !edges;
        lifecycle_machine_ids = List.rev !lifecycle_machines;
        fault_event_ids = List.rev !fault_events;
        gate_command_ids = List.rev !gate_commands;
        activity_ids = List.rev !activities }

let strings_field name fields =
  match List.assoc_opt name fields with
  | Some (`List values) ->
      let rec collect acc = function
        | [] -> Ok (List.rev acc)
        | `String value :: rest -> collect (value :: acc) rest
        | _ -> Error (name ^ " must contain strings")
      in
      collect [] values
  | _ -> Error (name ^ " is missing")

let manifest_of_json = function
  | `Assoc fields ->
      begin match List.assoc_opt "sourceDigest" fields with
      | Some (`String source_digest) ->
          let ( let* ) result f = match result with Ok value -> f value | Error _ as error -> error in
          let* component_ids = strings_field "componentIds" fields in
          let* port_ids = strings_field "portIds" fields in
          let* channel_ids = strings_field "channelIds" fields in
          let* requirement_ids = strings_field "requirementIds" fields in
          let* edge_ids = strings_field "edgeIds" fields in
          let* lifecycle_machine_ids = strings_field "lifecycleMachineIds" fields in
          let* fault_event_ids = strings_field "faultEventIds" fields in
          let* gate_command_ids = strings_field "gateCommandIds" fields in
          let* activity_ids = strings_field "activityIds" fields in
          Ok { source_digest; component_ids; port_ids; channel_ids; requirement_ids;
            edge_ids; lifecycle_machine_ids; fault_event_ids; gate_command_ids;
            activity_ids }
      | _ -> Error "manifest sourceDigest is missing"
      end
  | _ -> Error "manifest must be an object"

let parse_json label text =
  try Ok (Yojson.Safe.from_string text)
  with Yojson.Json_error message -> Error (label ^ " JSON is invalid: " ^ message)

let manifest_of_mms text =
  let ( let* ) result f = match result with Ok value -> f value | Error _ as error -> error in
  let* json = parse_json "MMS" text in
  match json with
  | `Assoc fields ->
      begin match List.assoc_opt "manifest" fields with
      | Some value -> manifest_of_json value
      | None -> Error "MMS manifest is missing"
      end
  | _ -> Error "MMS payload must be an object"

let manifest_of_fpp text =
  let ( let* ) result f = match result with Ok value -> f value | Error _ as error -> error in
  let* json = parse_json "FPP" text in
  match json with
  | `Assoc fields ->
      begin match List.assoc_opt "operationsModel" fields with
      | Some value -> manifest_of_json value
      | None -> Error "FPP operationsModel manifest is missing"
      end
  | _ -> Error "FPP dictionary must be an object"

let validate () =
  let gaps = ref (Run_topology.validate ()) in
  let add text = gaps := text :: !gaps in
  let projected_identifiers =
    manifest.component_ids @ manifest.port_ids @ manifest.channel_ids
    @ manifest.requirement_ids @ manifest.edge_ids
    @ manifest.lifecycle_machine_ids @ manifest.fault_event_ids
    @ manifest.gate_command_ids @ manifest.activity_ids
    |> List.map sanitize
  in
  if List.length projected_identifiers
     <> List.length (List.sort_uniq String.compare projected_identifiers)
  then add "sanitized MBSE identifiers collide";
  if List.length (oml_blocks ()) <> List.length manifest.component_ids then
    add "OML block denominator differs from component authority";
  let surfaces =
    [ ("SysML", manifest_of_sysml (sysml_v2 ()));
      ("Turtle", manifest_of_turtle (oml_owl ()));
      ("MMS", manifest_of_mms (openmbee_mms ()));
      ("FPP", manifest_of_fpp (fpp_dictionary ())) ]
  in
  List.iter
    (fun (name, observed) ->
      match observed with
      | Error message -> add (name ^ " correspondence unavailable: " ^ message)
      | Ok value when value <> manifest -> add (name ^ " manifest differs from authority")
      | Ok _ -> ())
    surfaces;
  List.iter
    (fun (activity : Run_topology.declarative_activity) ->
      let activity_id = activity.stable_id in
      let expected_action_graph = actions_json activity in
      let action_surfaces =
        [ ("SysML",
           action_graph_from_quoted ~activity_id
             "attribute actions : String = \"" (sysml_v2 ()));
          ("Turtle",
           action_graph_from_quoted ~activity_id "ops:actions \"" (oml_owl ()));
          ("MMS",
           action_graph_from_json ~activity_id ~container:"elements"
             (openmbee_mms ()));
          ("FPP",
           action_graph_from_json ~activity_id
             ~container:"operationsActivities" (fpp_dictionary ())) ]
      in
      List.iter
        (fun (name, observed) ->
          match observed with
          | None ->
              add (name ^ " action graph is missing or malformed for "
                   ^ activity_id)
          | Some value when not (equal_action_graph value expected_action_graph) ->
              add (name ^ " action graph differs from ordered topology authority for "
                   ^ activity_id)
          | Some _ -> ())
        action_surfaces)
    Run_topology.authority.activities;
  let activity_tokens =
    [ "targetState"; "requiredCapabilityIds"; "contextRequirementIds";
      "miqRoutes"; "effectKinds"; "commandIds"; "constraints";
      "successCriteria" ]
    @ List.concat_map
        (fun (item : Run_topology.declarative_activity) ->
          [ item.target_state ] @ item.required_capability_ids
          @ item.context_requirement_ids
          @ List.concat_map
              (fun (route : Run_topology.miq_route) ->
                [ route.selector_id; route.required_capability_id;
                  route.assigned_agent_id ])
              item.miq_routes
          @ List.map effect_kind_name item.effect_kinds)
        Run_topology.authority.activities
  in
  List.iter
    (fun (path, content) ->
      List.iter
        (fun token ->
          if not (contains content token) then
            add (Printf.sprintf "%s omits activity carrier %s" path token))
        activity_tokens)
    (outputs ());
  List.iter
    (fun (path, content) ->
      if String.trim path = "" || String.trim content = "" then
        add ("empty generated projection: " ^ path))
    (outputs ());
  List.rev !gaps
