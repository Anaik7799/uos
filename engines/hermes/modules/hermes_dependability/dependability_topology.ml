type component = { stable_id : string; purpose : string }
type direction = Input | Output

type port_kind =
  | Intent
  | Admitted_plan
  | Effect_request
  | Attempt_receipt
  | Formal_receipt
  | Evidence
  | Diagnostic

type port = {
  stable_id : string;
  component_id : string;
  name : string;
  direction : direction;
  kind : port_kind;
}

type edge = {
  stable_id : string;
  from_component : string;
  from_port : string;
  to_component : string;
  to_port : string;
  kind : port_kind;
}

type command = {
  stable_id : string;
  component_id : string;
  fpp_name : string;
}

type channel = {
  stable_id : string;
  component_id : string;
  metric_id : string option;
  fpp_name : string;
}

type lifecycle_transition = { signal : string; target_state : string }
type lifecycle_state = {
  stable_id : string;
  transitions : lifecycle_transition list;
}

type lifecycle = {
  stable_id : string;
  component_id : string;
  initial_state : string;
  states : lifecycle_state list;
}

type requirement = {
  stable_id : string;
  statement : string;
  verifier_id : string;
  covered_elements : string list;
}

type authority = {
  components : component list;
  ports : port list;
  edges : edge list;
  commands : command list;
  channels : channel list;
  lifecycle : lifecycle;
  requirements : requirement list;
}

let component_names =
  [ "dependabilityGateway"; "identityMaterializer"; "formalOracle";
    "swarmBridge"; "effectAuthority"; "processAttempt";
    "evidenceAuthority"; "journalOracle"; "aggregator";
    "metricsProjector" ]

let component_purposes =
  [ "Admit the two closed dependability verification intents";
    "Materialize exact source, configuration, toolchain, and binary identity";
    "Project bounded formal-model receipts without claiming external proof";
    "Represent the sole admitted Swarm execution handoff";
    "Bind admitted plans to closed typed effect requests";
    "Represent bounded child-process attempt receipts";
    "Join formal and process receipts into committed evidence";
    "Project kernel-journal availability and crash-match evidence";
    "Aggregate evidence into one honest terminal verdict";
    "Project the complete dependability telemetry dictionary" ]

let components =
  List.map2
    (fun stable_id purpose -> { stable_id; purpose })
    component_names component_purposes

let port component_id name direction kind =
  { stable_id = "port." ^ component_id ^ "." ^ name;
    component_id; name; direction; kind }

let ports =
  [ port "dependabilityGateway" "intentOut" Output Intent;
    port "identityMaterializer" "intentIn" Input Intent;
    port "identityMaterializer" "formalPlanOut" Output Admitted_plan;
    port "identityMaterializer" "swarmPlanOut" Output Admitted_plan;
    port "formalOracle" "admittedIn" Input Admitted_plan;
    port "formalOracle" "formalOut" Output Formal_receipt;
    port "formalOracle" "diagnosticOut" Output Diagnostic;
    port "swarmBridge" "admittedIn" Input Admitted_plan;
    port "swarmBridge" "effectOut" Output Effect_request;
    port "effectAuthority" "effectIn" Input Effect_request;
    port "effectAuthority" "effectOut" Output Effect_request;
    port "processAttempt" "effectIn" Input Effect_request;
    port "processAttempt" "evidenceAttemptOut" Output Attempt_receipt;
    port "processAttempt" "journalAttemptOut" Output Attempt_receipt;
    port "processAttempt" "diagnosticOut" Output Diagnostic;
    port "evidenceAuthority" "attemptIn" Input Attempt_receipt;
    port "evidenceAuthority" "formalIn" Input Formal_receipt;
    port "evidenceAuthority" "evidenceOut" Output Evidence;
    port "journalOracle" "attemptIn" Input Attempt_receipt;
    port "journalOracle" "evidenceOut" Output Evidence;
    port "journalOracle" "diagnosticOut" Output Diagnostic;
    port "aggregator" "evidenceIn" Input Evidence;
    port "aggregator" "journalIn" Input Evidence;
    port "aggregator" "resultOut" Output Evidence;
    port "metricsProjector" "evidenceIn" Input Evidence;
    port "metricsProjector" "formalDiagnosticIn" Input Diagnostic;
    port "metricsProjector" "processDiagnosticIn" Input Diagnostic;
    port "metricsProjector" "journalDiagnosticIn" Input Diagnostic ]

let edge stable_id kind from_component from_port to_component to_port =
  { stable_id; kind; from_component; from_port; to_component; to_port }

let edges =
  [ edge "edge.gateway-identity" Intent
      "dependabilityGateway" "intentOut" "identityMaterializer" "intentIn";
    edge "edge.identity-formal" Admitted_plan
      "identityMaterializer" "formalPlanOut" "formalOracle" "admittedIn";
    edge "edge.identity-swarm" Admitted_plan
      "identityMaterializer" "swarmPlanOut" "swarmBridge" "admittedIn";
    edge "edge.swarm-effect" Effect_request
      "swarmBridge" "effectOut" "effectAuthority" "effectIn";
    edge "edge.effect-process" Effect_request
      "effectAuthority" "effectOut" "processAttempt" "effectIn";
    edge "edge.process-evidence" Attempt_receipt
      "processAttempt" "evidenceAttemptOut" "evidenceAuthority" "attemptIn";
    edge "edge.process-journal" Attempt_receipt
      "processAttempt" "journalAttemptOut" "journalOracle" "attemptIn";
    edge "edge.formal-evidence" Formal_receipt
      "formalOracle" "formalOut" "evidenceAuthority" "formalIn";
    edge "edge.evidence-aggregator" Evidence
      "evidenceAuthority" "evidenceOut" "aggregator" "evidenceIn";
    edge "edge.journal-aggregator" Evidence
      "journalOracle" "evidenceOut" "aggregator" "journalIn";
    edge "edge.aggregator-metrics" Evidence
      "aggregator" "resultOut" "metricsProjector" "evidenceIn";
    edge "edge.formal-diagnostic" Diagnostic
      "formalOracle" "diagnosticOut" "metricsProjector" "formalDiagnosticIn";
    edge "edge.process-diagnostic" Diagnostic
      "processAttempt" "diagnosticOut" "metricsProjector" "processDiagnosticIn";
    edge "edge.journal-diagnostic" Diagnostic
      "journalOracle" "diagnosticOut" "metricsProjector" "journalDiagnosticIn" ]

let commands =
  [ { stable_id = "VERIFY_RELIABILITY";
      component_id = "dependabilityGateway";
      fpp_name = "VERIFY_RELIABILITY" };
    { stable_id = "VERIFY_FULL";
      component_id = "dependabilityGateway";
      fpp_name = "VERIFY_FULL" } ]

let metric_ids =
  [ "dependability.intents.admitted"; "dependability.intents.blocked";
    "dependability.identity.mismatches"; "dependability.graph.nodes";
    "dependability.graph.dirty"; "dependability.cache.hits";
    "dependability.cache.misses"; "dependability.attempts.required";
    "dependability.attempts.started"; "dependability.attempts.completed";
    "dependability.children.exited"; "dependability.children.signalled";
    "dependability.children.timed_out"; "dependability.children.skipped";
    "dependability.stdout.bytes"; "dependability.stderr.bytes";
    "dependability.gc.overlap_cycles"; "dependability.sqlite.close_attempts";
    "dependability.sqlite.close_busy"; "dependability.sqlite.close_failures";
    "dependability.journal.available"; "dependability.journal.crash_matches";
    "dependability.formal.proved"; "dependability.formal.refuted";
    "dependability.formal.unavailable"; "dependability.mutants.killed";
    "dependability.mutants.survived"; "dependability.events.committed";
    "dependability.events.readback_mismatches";
    "dependability.surface.equivalence_mismatches";
    "dependability.elapsed_ns"; "dependability.upper_incident_rate_ppm" ]

let fpp_identifier value =
  value
  |> String.map (fun c ->
         match c with
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> Char.uppercase_ascii c
         | _ -> '_')

let channels =
  List.map
    (fun metric_id ->
      { stable_id = "channel." ^ metric_id;
        component_id = "metricsProjector";
        metric_id = Some metric_id;
        fpp_name = fpp_identifier metric_id })
    metric_ids

let lifecycle =
  { stable_id = "DependabilityLifecycle"; component_id = "aggregator";
    initial_state = "Declared";
    states =
      [ { stable_id = "Declared";
          transitions = [ { signal = "admit"; target_state = "Admitted" } ] };
        { stable_id = "Admitted";
          transitions = [ { signal = "execute"; target_state = "Executing" } ] };
        { stable_id = "Executing";
          transitions = [ { signal = "aggregate"; target_state = "Aggregating" } ] };
        { stable_id = "Aggregating";
          transitions =
            [ { signal = "verify"; target_state = "Verified" };
              { signal = "refute"; target_state = "Refuted" };
              { signal = "observeUnavailable";
                target_state = "Unavailable_observed" } ] };
        { stable_id = "Verified"; transitions = [] };
        { stable_id = "Refuted"; transitions = [] };
        { stable_id = "Unavailable_observed"; transitions = [] } ] }

let covered_elements_of (components : component list) (ports : port list)
    (edges : edge list) (commands : command list) (channels : channel list)
    (lifecycle : lifecycle) =
  let lifecycle_elements =
    lifecycle.stable_id
    :: List.concat_map
         (fun (state : lifecycle_state) ->
           ("state." ^ state.stable_id)
           :: List.map
                (fun (transition : lifecycle_transition) ->
                  String.concat "."
                    [ "transition"; state.stable_id; transition.signal;
                      transition.target_state ])
                state.transitions)
         lifecycle.states
  in
  List.map (fun (component : component) -> component.stable_id) components
  @ List.map
      (fun (component : component) -> "instance." ^ component.stable_id)
      components
  @ List.map (fun (port : port) -> port.stable_id) ports
  @ List.map (fun (edge : edge) -> edge.stable_id) edges
  @ List.map (fun (command : command) -> command.stable_id) commands
  @ List.map (fun (channel : channel) -> channel.stable_id) channels
  @ [ "port-kind.intent"; "port-kind.admitted_plan";
      "port-kind.effect_request"; "port-kind.attempt_receipt";
      "port-kind.formal_receipt"; "port-kind.evidence";
      "port-kind.diagnostic" ]
  @ lifecycle_elements

let covered_element_ids (value : authority) =
  covered_elements_of value.components value.ports value.edges value.commands
    value.channels value.lifecycle

let graph_covered_elements =
  covered_elements_of components ports edges commands channels lifecycle

let requirements =
  [ { stable_id = "HZ-SQL-FIN-01";
      statement =
        "Every explicit SQLite statement finalization keeps the statement live across the foreign call";
      verifier_id = "verify.sqlite-lifecycle";
      covered_elements =
        [ "formalOracle"; "processAttempt"; "evidenceAuthority";
          "journalOracle"; "aggregator" ] };
    { stable_id = "REQ-DEPENDABILITY-GRAPH-FPP";
      statement =
        "Every typed authority component, port, edge, command, channel, and lifecycle state has one FPP projection";
      verifier_id = "verify.graph-fpp-correspondence";
      covered_elements = graph_covered_elements } ]

let authority =
  { components; ports; edges; commands; channels; lifecycle; requirements }

let string_of_direction = function Input -> "input" | Output -> "output"

let string_of_port_kind = function
  | Intent -> "intent"
  | Admitted_plan -> "admitted_plan"
  | Effect_request -> "effect_request"
  | Attempt_receipt -> "attempt_receipt"
  | Formal_receipt -> "formal_receipt"
  | Evidence -> "evidence"
  | Diagnostic -> "diagnostic"

let json_string_list values = `List (List.map (fun value -> `String value) values)

let json_of_authority (value : authority) =
  `Assoc
    [ ("components",
       `List
         (List.map
            (fun (item : component) ->
              `Assoc
                [ ("purpose", `String item.purpose);
                  ("stableId", `String item.stable_id) ])
            value.components));
      ("ports",
       `List
         (List.map
            (fun (item : port) ->
              `Assoc
                [ ("componentId", `String item.component_id);
                  ("direction", `String (string_of_direction item.direction));
                  ("kind", `String (string_of_port_kind item.kind));
                  ("name", `String item.name);
                  ("stableId", `String item.stable_id) ])
            value.ports));
      ("edges",
       `List
         (List.map
            (fun (item : edge) ->
              `Assoc
                [ ("fromComponent", `String item.from_component);
                  ("fromPort", `String item.from_port);
                  ("kind", `String (string_of_port_kind item.kind));
                  ("stableId", `String item.stable_id);
                  ("toComponent", `String item.to_component);
                  ("toPort", `String item.to_port) ])
            value.edges));
      ("commands",
       `List
         (List.map
            (fun (item : command) ->
              `Assoc
                [ ("componentId", `String item.component_id);
                  ("fppName", `String item.fpp_name);
                  ("stableId", `String item.stable_id) ])
            value.commands));
      ("channels",
       `List
         (List.map
            (fun (item : channel) ->
              `Assoc
                [ ("componentId", `String item.component_id);
                  ("fppName", `String item.fpp_name);
                  ("metricId",
                   match item.metric_id with
                   | Some id -> `String id
                   | None -> `Null);
                  ("stableId", `String item.stable_id) ])
            value.channels));
      ("lifecycle",
       `Assoc
         [ ("componentId", `String value.lifecycle.component_id);
           ("initialState", `String value.lifecycle.initial_state);
           ("stableId", `String value.lifecycle.stable_id);
           ("states",
            `List
              (List.map
                 (fun (state : lifecycle_state) ->
                   `Assoc
                     [ ("stableId", `String state.stable_id);
                       ("transitions",
                        `List
                          (List.map
                             (fun (transition : lifecycle_transition) ->
                               `Assoc
                                 [ ("signal", `String transition.signal);
                                   ("targetState",
                                    `String transition.target_state) ])
                             state.transitions)) ])
                 value.lifecycle.states)) ]);
      ("requirements",
       `List
         (List.map
            (fun (item : requirement) ->
              `Assoc
                [ ("coveredElements", json_string_list item.covered_elements);
                  ("stableId", `String item.stable_id);
                  ("statement", `String item.statement);
                  ("verifierId", `String item.verifier_id) ])
            value.requirements)) ]

let source_digest_of value =
  value |> json_of_authority |> Yojson.Safe.to_string
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let source_digest = source_digest_of authority

let source_digest_constants digest =
  List.init 8 (fun index ->
      let word = String.sub digest (index * 8) 8 in
      (Printf.sprintf "DEPENDABILITY_SOURCE_DIGEST_%d" index,
       int_of_string ("0x" ^ word)))

let fpp_port_name = function
  | Intent -> "DependabilityIntent"
  | Admitted_plan -> "DependabilityAdmittedPlan"
  | Effect_request -> "DependabilityEffectRequest"
  | Attempt_receipt -> "DependabilityAttemptReceipt"
  | Formal_receipt -> "DependabilityFormalReceipt"
  | Evidence -> "DependabilityEvidence"
  | Diagnostic -> "DependabilityDiagnostic"

let fpp_machine (value : lifecycle) =
  let signals =
    value.states
    |> List.concat_map (fun (state : lifecycle_state) -> state.transitions)
    |> List.map (fun (transition : lifecycle_transition) -> transition.signal)
    |> List.sort_uniq String.compare
    |> List.map (fun signal_name ->
           { Fpp_model.signal_name = signal_name; signal_type = None })
  in
  Fpp_model.Internal_machine
    { machine_name = value.stable_id; signals; guards = []; actions = [];
      states =
        List.map
          (fun (state : lifecycle_state) ->
            { Fpp_model.state_name = state.stable_id; entry = []; exit_ = [];
              transitions =
                List.map
                  (fun (transition : lifecycle_transition) ->
                    { Fpp_model.on_signal = transition.signal; guard = None;
                      do_actions = [];
                      target = Fpp_model.To_state transition.target_state })
                  state.transitions })
          value.states;
      choices = []; initial = ([], value.initial_state) }

let fpp_component (value : authority) (item : component) =
  let component_commands =
    List.filter
      (fun (command : command) -> command.component_id = item.stable_id)
      value.commands
  in
  let component_channels =
    List.filter
      (fun (channel : channel) -> channel.component_id = item.stable_id)
      value.channels
  in
  let owns_lifecycle = value.lifecycle.component_id = item.stable_id in
  { Fpp_model.comp_name = item.stable_id;
    kind = if owns_lifecycle then Fpp_model.Active else Fpp_model.Passive;
    ports =
      value.ports
      |> List.filter (fun (port : port) -> port.component_id = item.stable_id)
      |> List.map (fun (port : port) ->
             Fpp_model.General
               { name = port.name; port = fpp_port_name port.kind;
                 direction =
                   (match port.direction with
                    | Input -> Fpp_model.Sync_input
                    | Output -> Fpp_model.Output);
                 count = 1 });
    commands =
      List.mapi
        (fun opcode (command : command) ->
          { Fpp_model.cmd_name = command.fpp_name; opcode;
            cmd_kind = Fpp_model.Sync_cmd;
            cmd_params =
              [ ("intentId", Fpp_model.Prim (Fpp_model.String (Some 128))) ] })
        component_commands;
    events = [];
    channels =
      List.mapi
        (fun chan_id (channel : channel) ->
          { Fpp_model.chan_name = channel.fpp_name; chan_id;
            chan_type = Fpp_model.Prim Fpp_model.U64;
            update = Fpp_model.On_change; chan_format = None;
            low = None; high = None })
        component_channels;
    parameters = []; records = []; containers = []; internal_ports = [];
    machines =
      if owns_lifecycle then [ ("lifecycle", value.lifecycle.stable_id) ] else [];
    matched = [] }

let to_fpp_model (value : authority) =
  let fpp_components = List.map (fpp_component value) value.components in
  let instances =
    List.mapi
      (fun index (component : Fpp_model.component) ->
        let active = component.kind = Fpp_model.Active in
        { Fpp_model.inst_name = component.comp_name;
          of_component = component.comp_name;
          base_id = 0x5000 + (index * 0x100);
          queue_size = if active then Some 32 else None;
          stack_size = if active then Some 65_536 else None;
          inst_priority = if active then Some 20 else None;
          cpu = None })
      fpp_components
  in
  let endpoint ep_instance ep_port =
    { Fpp_model.ep_instance = ep_instance; ep_port; ep_index = None }
  in
  let connections =
    List.map
      (fun (edge : edge) ->
        { Fpp_model.from_ = endpoint edge.from_component edge.from_port;
          to_ = endpoint edge.to_component edge.to_port })
      value.edges
  in
  { Fpp_model.model_name = "HermesDependability";
    type_defs = [];
    port_defs =
      [ Intent; Admitted_plan; Effect_request; Attempt_receipt;
        Formal_receipt; Evidence; Diagnostic ]
      |> List.map (fun kind ->
             { Fpp_model.port_name = fpp_port_name kind;
               params =
                 [ ("payload",
                    Fpp_model.Prim (Fpp_model.String (Some 4096))) ];
               return_type = None });
    constants = source_digest_constants (source_digest_of value);
    components = fpp_components;
    machines = [ fpp_machine value.lifecycle ];
    instances;
    topologies =
      [ { Fpp_model.topo_name = "Dependability";
          members =
            List.map
              (fun (instance : Fpp_model.instance) -> instance.inst_name)
              instances;
          graphs =
            [ Fpp_model.Direct
                { graph_name = "DependabilityTypedFlow"; connections } ] } ] }

let model = to_fpp_model authority

let source_digest_of_model (value : Fpp_model.model) =
  let rec words index accumulator =
    if index = 8 then Some (String.concat "" (List.rev accumulator))
    else
      match
        List.assoc_opt
          (Printf.sprintf "DEPENDABILITY_SOURCE_DIGEST_%d" index)
          value.constants
      with
      | None -> None
      | Some word when word < 0 || word > 0xffff_ffff -> None
      | Some word -> words (index + 1) (Printf.sprintf "%08x" word :: accumulator)
  in
  words 0 []

let dictionary () =
  Fpp_model.to_dictionary ~project_version:source_digest model
    ~topology:"Dependability"

let lifecycle_paths (value : lifecycle) =
  let find_state stable_id =
    List.find_opt
      (fun (state : lifecycle_state) -> state.stable_id = stable_id)
      value.states
  in
  let rec walk visited reversed_path stable_id =
    if List.mem stable_id visited then []
    else
      match find_state stable_id with
      | None -> []
      | Some state ->
          let reversed_path = stable_id :: reversed_path in
          begin match state.transitions with
          | [] -> [ List.rev reversed_path ]
          | transitions ->
              List.concat_map
                (fun (transition : lifecycle_transition) ->
                  walk (stable_id :: visited) reversed_path
                    transition.target_state)
                transitions
          end
  in
  walk [] [] value.initial_state

let coordinate_gap hazard message =
  Printf.sprintf "L3/contract RCA=Specification HZ=%s %s" hazard message

let nonempty value = String.trim value <> ""
let unique values = List.length values = List.length (List.sort_uniq compare values)

let safe_fpp_identifier value =
  let body = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
    | _ -> false
  in
  String.length value > 0
  && (match value.[0] with
      | 'a' .. 'z' | 'A' .. 'Z' | '_' -> true
      | _ -> false)
  && String.for_all body value

let identifier_gaps (value : authority) =
  let lifecycle_identifiers =
    value.lifecycle.stable_id
    :: value.lifecycle.component_id
    :: List.concat_map
         (fun (state : lifecycle_state) ->
           state.stable_id
           :: List.concat_map
                (fun (transition : lifecycle_transition) ->
                  [ transition.signal; transition.target_state ])
                state.transitions)
         value.lifecycle.states
  in
  let fixed_projection_identifiers =
    [ "HermesDependability"; "Dependability";
      "DependabilityTypedFlow"; "payload"; "intentId"; "lifecycle" ]
    @ List.map fpp_port_name
        [ Intent; Admitted_plan; Effect_request; Attempt_receipt;
          Formal_receipt; Evidence; Diagnostic ]
    @ List.init 8 (fun index ->
          Printf.sprintf "DEPENDABILITY_SOURCE_DIGEST_%d" index)
  in
  let identifiers =
    List.map
      (fun (component : component) -> component.stable_id)
      value.components
    @ List.concat_map
        (fun (port : port) -> [ port.component_id; port.name ])
        value.ports
    @ List.concat_map
        (fun (edge : edge) ->
          [ edge.from_component; edge.from_port; edge.to_component;
            edge.to_port ])
        value.edges
    @ List.concat_map
        (fun (command : command) ->
          [ command.component_id; command.fpp_name ])
        value.commands
    @ List.concat_map
        (fun (channel : channel) ->
          [ channel.component_id; channel.fpp_name ])
        value.channels
    @ lifecycle_identifiers @ fixed_projection_identifiers
  in
  identifiers
  |> List.filter_map (fun identifier ->
         if safe_fpp_identifier identifier then None
         else
           Some
             (coordinate_gap "HZ-DEP-FPP-NAME-01"
                (Printf.sprintf "unsafe FPP identifier %S" identifier)))
  |> List.sort_uniq String.compare

let port_flow_gaps (value : authority) =
  let gaps = ref [] in
  let add condition message =
    if not condition then
      gaps := coordinate_gap "HZ-DEP-FLOW-01" message :: !gaps
  in
  let component_exists stable_id =
    List.exists
      (fun (component : component) -> component.stable_id = stable_id)
      value.components
  in
  let find_ports component_id name =
    List.filter
      (fun (port : port) ->
        port.component_id = component_id && port.name = name)
      value.ports
  in
  add
    (unique (List.map (fun (port : port) -> port.stable_id) value.ports))
    "port stable identifiers are not unique";
  add
    (unique
       (List.map
          (fun (port : port) -> port.component_id, port.name)
          value.ports))
    "component-local port names are not unique";
  add
    (unique (List.map (fun (edge : edge) -> edge.stable_id) value.edges))
    "edge stable identifiers are not unique";
  List.iter
    (fun (port : port) ->
      add (component_exists port.component_id)
        ("port " ^ port.stable_id ^ " names an unknown component");
      add (nonempty port.name)
        ("port " ^ port.stable_id ^ " has an empty name");
      add
        (List.exists
           (fun (edge : edge) ->
             (edge.from_component = port.component_id
              && edge.from_port = port.name)
             || (edge.to_component = port.component_id
                 && edge.to_port = port.name))
           value.edges)
        ("port " ^ port.stable_id ^ " is dangling"))
    value.ports;
  List.iter
    (fun (edge : edge) ->
      match
        (find_ports edge.from_component edge.from_port,
         find_ports edge.to_component edge.to_port)
      with
      | [ from_port ], [ to_port ] ->
          add (from_port.direction = Output)
            ("edge " ^ edge.stable_id ^ " does not start at an output");
          add (to_port.direction = Input)
            ("edge " ^ edge.stable_id ^ " does not end at an input");
          add
            (from_port.kind = edge.kind && to_port.kind = edge.kind)
            ("edge " ^ edge.stable_id ^ " changes its typed flow kind")
      | _ ->
          add false ("edge " ^ edge.stable_id ^ " has an unresolved endpoint"))
    value.edges;
  List.rev !gaps

let exact_lifecycle_paths =
  [ [ "Declared"; "Admitted"; "Executing"; "Aggregating"; "Verified" ];
    [ "Declared"; "Admitted"; "Executing"; "Aggregating"; "Refuted" ];
    [ "Declared"; "Admitted"; "Executing"; "Aggregating";
      "Unavailable_observed" ] ]

let projection_gaps (value : authority) (projection : Fpp_model.model) =
  let gaps = ref [] in
  let add condition message =
    if not condition then
      gaps := coordinate_gap "HZ-DEP-GRAPH-FPP-01" message :: !gaps
  in
  add (projection = to_fpp_model value)
    "projection is not structurally equal to the complete canonical FPP model";
  add
    (List.map
       (fun (component : Fpp_model.component) -> component.comp_name)
       projection.components
     = List.map (fun (component : component) -> component.stable_id)
         value.components)
    "component projection does not correspond to authority order";
  add (List.length projection.instances = List.length value.components)
    "instance projection is not one per authority component";
  let expected_ports =
    List.map
      (fun (port : port) ->
        (port.component_id, port.name, fpp_port_name port.kind,
         string_of_direction port.direction))
      value.ports
  in
  let projected_ports =
    List.concat_map
      (fun (component : Fpp_model.component) ->
        List.filter_map
          (function
            | Fpp_model.General general ->
                let direction =
                  match general.direction with
                  | Fpp_model.Output -> "output"
                  | Fpp_model.Sync_input | Fpp_model.Guarded_input
                  | Fpp_model.Async_input _ -> "input"
                in
                Some
                  (component.comp_name, general.name, general.port, direction)
            | Fpp_model.Special _ -> None)
          component.ports)
      projection.components
  in
  add (projected_ports = expected_ports)
    "typed port projection differs from authority";
  let expected_commands =
    List.map
      (fun (command : command) ->
        (command.component_id, command.fpp_name))
      value.commands
  in
  let projected_commands =
    List.concat_map
      (fun (component : Fpp_model.component) ->
        List.map
          (fun (command : Fpp_model.command) ->
            (component.comp_name, command.cmd_name))
          component.commands)
      projection.components
  in
  add (projected_commands = expected_commands)
    "command projection differs from authority";
  let expected_channels =
    let rec enumerate counts accumulator = function
      | [] -> List.rev accumulator
      | (channel : channel) :: rest ->
          let chan_id =
            Option.value (List.assoc_opt channel.component_id counts)
              ~default:0
          in
          let counts =
            (channel.component_id, chan_id + 1)
            :: List.remove_assoc channel.component_id counts
          in
          enumerate counts
            ((channel.component_id, channel.fpp_name, chan_id) :: accumulator)
            rest
    in
    enumerate [] [] value.channels
  in
  let projected_channels =
    List.concat_map
      (fun (component : Fpp_model.component) ->
        List.map
          (fun (channel : Fpp_model.channel) ->
            (component.comp_name, channel.chan_name, channel.chan_id))
          component.channels)
      projection.components
  in
  add (projected_channels = expected_channels)
    "telemetry channel projection differs from authority";
  let expected_edges =
    List.map
      (fun (edge : edge) ->
        (edge.from_component, edge.from_port, edge.to_component, edge.to_port))
      value.edges
  in
  let projected_edges =
    List.concat_map
      (fun (topology : Fpp_model.topology) ->
        List.concat_map
          (function
            | Fpp_model.Direct direct ->
                List.map
                  (fun (connection : Fpp_model.connection) ->
                    (connection.from_.ep_instance, connection.from_.ep_port,
                     connection.to_.ep_instance, connection.to_.ep_port))
                  direct.connections
            | Fpp_model.Pattern _ -> [])
          topology.graphs)
      projection.topologies
  in
  add (projected_edges = expected_edges)
    "typed edge projection differs from authority";
  add (List.length projection.machines = 1)
    "lifecycle projection is not exactly one FPP state machine";
  add (source_digest_of_model projection = Some (source_digest_of value))
    "projected model does not carry the source authority digest";
  List.rev !gaps

type interval = { owner : string; instance : string; first : int; last : int }

let intervals_of_model owner (value : Fpp_model.model) =
  let gaps = ref [] in
  let intervals =
    List.filter_map
      (fun (instance : Fpp_model.instance) ->
        match
          List.find_opt
            (fun (component : Fpp_model.component) ->
              component.comp_name = instance.of_component)
            value.components
        with
        | None ->
            gaps :=
              coordinate_gap "HZ-DEP-ID-01"
                (Printf.sprintf "%s.%s names unknown component %s" owner
                   instance.inst_name instance.of_component)
              :: !gaps;
            None
        | Some component ->
            let span = Fpp_model.id_span component in
            if instance.base_id < 0 || span <= 0
               || instance.base_id > max_int - span
            then begin
              gaps :=
                coordinate_gap "HZ-DEP-ID-01"
                  (Printf.sprintf "%s.%s has invalid or overflowing interval"
                     owner instance.inst_name)
                :: !gaps;
              None
            end else
              Some
                { owner; instance = instance.inst_name;
                  first = instance.base_id; last = instance.base_id + span })
      value.instances
  in
  (List.rev !gaps, intervals)

let overlap left right = left.first < right.last && right.first < left.last

let overlap_gap left right =
  coordinate_gap "HZ-DEP-ID-01"
    (Printf.sprintf "%s.%s [%d,%d) overlaps %s.%s [%d,%d)"
       left.owner left.instance left.first left.last right.owner right.instance
       right.first right.last)

let rec internal_overlap_gaps = function
  | [] -> []
  | left :: rest ->
      List.filter_map
        (fun right -> if overlap left right then Some (overlap_gap left right)
          else None)
        rest
      @ internal_overlap_gaps rest

let window_gaps ~others =
  let structural, own = intervals_of_model "dependability" model in
  let reserved =
    List.filter_map
      (fun interval ->
        if interval.first < 0x5000 || interval.last > 0x6000 then
          Some
            (coordinate_gap "HZ-DEP-ID-01"
               (Printf.sprintf "%s.%s [%d,%d) leaves reserved [20480,24576)"
                  interval.owner interval.instance interval.first interval.last))
        else None)
      own
  in
  let external_gaps =
    List.concat_map
      (fun (owner, other_model) ->
        let other_structural, outside = intervals_of_model owner other_model in
        let cross =
          List.concat_map
            (fun other_interval ->
              List.filter_map
                (fun own_interval ->
                  if overlap other_interval own_interval then
                    Some (overlap_gap other_interval own_interval)
                  else None)
                own)
            outside
        in
        other_structural @ internal_overlap_gaps outside @ cross)
      others
  in
  structural @ reserved @ internal_overlap_gaps own @ external_gaps

let validate_authority (value : authority) =
  let gaps = ref [] in
  let add hazard condition message =
    if not condition then gaps := coordinate_gap hazard message :: !gaps
  in
  add "HZ-DEP-TOPOLOGY-01"
    (List.map (fun (component : component) -> component.stable_id)
       value.components
     = component_names)
    "component census is not the closed ten-component authority";
  add "HZ-DEP-TOPOLOGY-01"
    (List.for_all
       (fun (component : component) -> nonempty component.purpose)
       value.components)
    "a component purpose is empty";
  add "HZ-DEP-COMMAND-01"
    (value.commands = commands)
    "command authority does not preserve the exact closed identifiers and FPP names";
  add "HZ-DEP-COMMAND-01"
    (unique (List.map (fun (command : command) -> command.stable_id)
               value.commands)
     && unique
          (List.map (fun (command : command) -> command.fpp_name)
             value.commands)
     && List.for_all
          (fun (command : command) ->
            command.component_id = "dependabilityGateway"
            && nonempty command.fpp_name
            && command.stable_id <> "Invoke"
            && command.fpp_name <> "INVOKE")
          value.commands)
    "commands are duplicated, unresolved, empty, or contain generic Invoke";
  add "HZ-DEP-METRIC-01"
    (value.channels = channels)
    "telemetry mapping does not preserve exact metric, stable, and FPP names";
  add "HZ-DEP-METRIC-01"
    (unique (List.map (fun (channel : channel) -> channel.stable_id)
               value.channels)
     && unique
          (List.map (fun (channel : channel) -> channel.fpp_name)
             value.channels)
     && List.for_all
          (fun (channel : channel) ->
            channel.component_id = "metricsProjector"
            && nonempty channel.fpp_name)
          value.channels)
    "telemetry channels are duplicated, unresolved, or empty";
  add "HZ-DEP-LIFECYCLE-01"
    (value.lifecycle = lifecycle
     && value.lifecycle.component_id = "aggregator"
     && lifecycle_paths value.lifecycle = exact_lifecycle_paths
     && List.map
          (fun (state : lifecycle_state) -> state.stable_id)
          value.lifecycle.states
        = [ "Declared"; "Admitted"; "Executing"; "Aggregating";
            "Verified"; "Refuted"; "Unavailable_observed" ])
    "lifecycle is not the closed honest three-terminal state machine";
  add "HZ-DEP-REQUIREMENT-01"
    (List.map
       (fun (requirement : requirement) ->
         (requirement.stable_id, requirement.verifier_id))
       value.requirements
     = [ ("HZ-SQL-FIN-01", "verify.sqlite-lifecycle");
         ("REQ-DEPENDABILITY-GRAPH-FPP",
          "verify.graph-fpp-correspondence") ])
    "required SQLite and graph/FPP verifiers are not closed and explicit";
  add "HZ-DEP-REQUIREMENT-01"
    (match
       List.find_opt
         (fun (requirement : requirement) ->
           requirement.stable_id = "REQ-DEPENDABILITY-GRAPH-FPP")
         value.requirements
     with
     | Some requirement ->
         requirement.covered_elements = covered_element_ids value
         && unique requirement.covered_elements
     | None -> false)
    "graph/FPP requirement does not cover every projected authority element";
  let expected_port_ids =
    List.map (fun (port : port) -> port.stable_id) ports
  in
  add "HZ-DEP-FLOW-01"
    (value.ports = ports
     && List.map (fun (port : port) -> port.stable_id) value.ports
        = expected_port_ids)
    "port authority contains a deletion, insertion, or reorder";
  let expected_edge_ids =
    List.map (fun (edge : edge) -> edge.stable_id) edges
  in
  add "HZ-DEP-FLOW-01"
    (value.edges = edges
     && List.map (fun (edge : edge) -> edge.stable_id) value.edges
        = expected_edge_ids)
    "edge authority contains a deletion, insertion, or reorder";
  gaps := List.rev_append (port_flow_gaps value) !gaps;
  gaps := List.rev_append (identifier_gaps value) !gaps;
  let projection = to_fpp_model value in
  gaps := List.rev_append (projection_gaps value projection) !gaps;
  let fpp_gaps = Fpp_model.validate projection in
  add "HZ-DEP-FPP-01" (fpp_gaps = [])
    (Printf.sprintf "FPP projection has %d structural diagnostics"
       (List.length fpp_gaps));
  List.rev !gaps

let validate () = validate_authority authority @ window_gaps ~others:[]
