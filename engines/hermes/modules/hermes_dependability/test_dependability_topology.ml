open Dependability_topology

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf
      "L4/behavioral RCA=Evidence HZ=HZ-DEP-TOPOLOGY-TEST-01 FAILED: %s\n"
      name
  end

let ids get values = List.map get values

let sorted_unique values =
  List.sort_uniq String.compare values

let dictionary_project_version = function
  | `Assoc fields ->
      begin match List.assoc_opt "metadata" fields with
      | Some (`Assoc metadata) ->
          begin match List.assoc_opt "projectVersion" metadata with
          | Some (`String digest) -> Some digest
          | _ -> None
          end
      | _ -> None
      end
  | _ -> None

let expected_metric_fpp_name value =
  value
  |> String.map (fun character ->
         match character with
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' ->
             Char.uppercase_ascii character
         | _ -> '_')

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

let lifecycle_signal_paths (value : lifecycle) =
  let state stable_id =
    List.find_opt
      (fun (item : lifecycle_state) -> item.stable_id = stable_id)
      value.states
  in
  let rec walk visited stable_id =
    if List.mem stable_id visited then []
    else
      match state stable_id with
      | None -> []
      | Some { transitions = []; _ } -> [ [] ]
      | Some item ->
          List.concat_map
            (fun (transition : lifecycle_transition) ->
              walk (stable_id :: visited) transition.target_state
              |> List.map (fun path ->
                     (stable_id, transition.signal, transition.target_state)
                     :: path))
            item.transitions
  in
  walk [] value.initial_state

let mutate_authority_command_name () =
  match authority.commands with
  | command :: remaining ->
      { authority with
        commands = { command with fpp_name = "VERIFY_RELIABILITY_X" } :: remaining }
  | [] -> authority

let mutate_authority_signal signal =
  match authority.lifecycle.states with
  | state :: remaining_states ->
      begin match state.transitions with
      | transition :: remaining_transitions ->
          { authority with
            lifecycle =
              { authority.lifecycle with
                states =
                  { state with
                    transitions =
                      { transition with signal } :: remaining_transitions }
                  :: remaining_states } }
      | [] -> authority
      end
  | [] -> authority

let mutate_duplicate_port () =
  match authority.ports with
  | port :: _ ->
      { authority with
        ports = { port with stable_id = port.stable_id ^ ".duplicate" }
                :: authority.ports }
  | [] -> authority

let mutate_projected_signal (value : Fpp_model.model) =
  match value.machines with
  | Fpp_model.Internal_machine machine :: remaining_machines ->
      begin match machine.states with
      | state :: remaining_states ->
          begin match state.transitions with
          | transition :: remaining_transitions ->
              { value with
                machines =
                  Fpp_model.Internal_machine
                    { machine with
                      states =
                        { state with
                          transitions =
                            { transition with
                              on_signal = transition.on_signal ^ "Mutant" }
                            :: remaining_transitions }
                        :: remaining_states }
                  :: remaining_machines }
          | [] -> value
          end
      | [] -> value
      end
  | _ -> value

let mutate_projected_instance (value : Fpp_model.model) =
  match value.instances with
  | instance :: remaining ->
      { value with
        instances = { instance with base_id = instance.base_id + 1 } :: remaining }
  | [] -> value

let mutate_projected_port (value : Fpp_model.model) =
  match value.components with
  | component :: remaining_components ->
      begin match component.ports with
      | Fpp_model.General port :: remaining_ports ->
          { value with
            components =
              { component with
                ports = Fpp_model.General { port with count = port.count + 1 }
                        :: remaining_ports }
              :: remaining_components }
      | _ -> value
      end
  | [] -> value

let mutate_projected_command (value : Fpp_model.model) =
  match value.components with
  | component :: remaining_components ->
      begin match component.commands with
      | command :: remaining_commands ->
          { value with
            components =
              { component with
                commands =
                  { command with opcode = command.opcode + 7; cmd_params = [] }
                  :: remaining_commands }
              :: remaining_components }
      | [] -> value
      end
  | [] -> value

let mutate_projected_channel (value : Fpp_model.model) =
  let rec components reversed = function
    | [] -> value.components
    | component :: remaining ->
        begin match component.Fpp_model.channels with
        | channel :: remaining_channels ->
            List.rev_append reversed
              ({ component with
                 channels =
                   { channel with
                     chan_type = Fpp_model.Prim Fpp_model.I64;
                     update = Fpp_model.Always }
                   :: remaining_channels }
               :: remaining)
        | [] -> components (component :: reversed) remaining
        end
  in
  { value with components = components [] value.components }

let exhaustive_covered_elements (value : authority) =
  let lifecycle_elements =
    value.lifecycle.stable_id
    :: List.concat_map
         (fun (state : lifecycle_state) ->
           ("state." ^ state.stable_id)
           :: List.map
                (fun (transition : lifecycle_transition) ->
                  String.concat "."
                    [ "transition"; state.stable_id; transition.signal;
                      transition.target_state ])
                state.transitions)
         value.lifecycle.states
  in
  List.map (fun (component : component) -> component.stable_id) value.components
  @ List.map
      (fun (component : component) -> "instance." ^ component.stable_id)
      value.components
  @ List.map (fun (port : port) -> port.stable_id) value.ports
  @ List.map (fun (edge : edge) -> edge.stable_id) value.edges
  @ List.map (fun (command : command) -> command.stable_id) value.commands
  @ List.map (fun (channel : channel) -> channel.stable_id) value.channels
  @ [ "port-kind.intent"; "port-kind.admitted_plan";
      "port-kind.effect_request"; "port-kind.attempt_receipt";
      "port-kind.formal_receipt"; "port-kind.evidence";
      "port-kind.diagnostic" ]
  @ lifecycle_elements

let externally_overlapping_model () =
  match model.instances with
  | first :: second :: _ ->
      { model with
        instances =
          [ { first with base_id = 0x7000 };
            { second with base_id = 0x7000 } ] }
  | _ -> model

let adjacent_external_model () =
  match model.instances with
  | instance :: _ ->
      begin match
        List.find_opt
          (fun (component : Fpp_model.component) ->
            component.comp_name = instance.of_component)
          model.components
      with
      | Some component ->
          { model with
            instances =
              [ { instance with
                  base_id = 0x5000 - Fpp_model.id_span component } ] }
      | None -> model
      end
  | [] -> model

let required_components =
  [ "dependabilityGateway"; "identityMaterializer"; "formalOracle";
    "swarmBridge"; "effectAuthority"; "processAttempt";
    "evidenceAuthority"; "journalOracle"; "aggregator";
    "metricsProjector" ]

let required_metrics =
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

let () =
  check "F1 generic dependability authority validates without a dangling element"
    (validate () = [] && Fpp_model.validate model = []);
  check "F2 exact generic component census is closed and nonempty"
    (ids (fun (component : component) -> component.stable_id)
       authority.components
       = required_components);
  check "F3 commands are closed typed actions with no generic Invoke fallback"
    (List.map
       (fun (command : command) -> command.stable_id, command.fpp_name)
       authority.commands
       = [ "VERIFY_RELIABILITY", "VERIFY_RELIABILITY";
           "VERIFY_FULL", "VERIFY_FULL" ]
     && List.for_all
          (fun (command : command) ->
            not (String.equal command.stable_id "Invoke")
            && not (String.equal command.fpp_name "INVOKE"))
          authority.commands
     && validate_authority (mutate_authority_command_name ()) <> []);
  check "F4 lifecycle is Declared-Admitted-Executing-Aggregating to three honest terminals"
    (lifecycle_paths authority.lifecycle
     = [ [ "Declared"; "Admitted"; "Executing"; "Aggregating"; "Verified" ];
         [ "Declared"; "Admitted"; "Executing"; "Aggregating"; "Refuted" ];
         [ "Declared"; "Admitted"; "Executing"; "Aggregating";
           "Unavailable_observed" ] ]
     && lifecycle_signal_paths authority.lifecycle
        = [ [ "Declared", "admit", "Admitted";
              "Admitted", "execute", "Executing";
              "Executing", "aggregate", "Aggregating";
              "Aggregating", "verify", "Verified" ];
            [ "Declared", "admit", "Admitted";
              "Admitted", "execute", "Executing";
              "Executing", "aggregate", "Aggregating";
              "Aggregating", "refute", "Refuted" ];
            [ "Declared", "admit", "Admitted";
              "Admitted", "execute", "Executing";
              "Executing", "aggregate", "Aggregating";
              "Aggregating", "observeUnavailable",
              "Unavailable_observed" ] ]
     && validate_authority (mutate_authority_signal "admitMutant") <> []);
  check "F5 every required metric has exactly one typed FPP telemetry channel"
    (let mapped =
       authority.channels
       |> List.filter_map (fun (channel : channel) -> channel.metric_id)
     in
     sorted_unique mapped = sorted_unique required_metrics
     && List.length mapped = List.length required_metrics
     && List.for_all
          (fun (channel : channel) ->
            match channel.metric_id with
            | Some metric_id ->
                channel.stable_id = "channel." ^ metric_id
                && channel.fpp_name = expected_metric_fpp_name metric_id
            | None -> false)
          authority.channels
     && (match authority.channels with
         | channel :: channels ->
             validate_authority
               { authority with
                 channels =
                   { channel with fpp_name = channel.fpp_name ^ "_X" }
                   :: channels }
             <> []
         | [] -> false));
  check "F6 ports and edges preserve typed intent, evidence, receipt, and diagnostic flow"
    (port_flow_gaps authority = []
     && List.for_all
          (fun kind ->
            List.exists (fun (port : port) -> port.kind = kind) authority.ports)
          [ Intent; Admitted_plan; Effect_request; Attempt_receipt;
            Formal_receipt; Evidence; Diagnostic ]
     && port_flow_gaps (mutate_duplicate_port ()) <> []);
  check "F7 HZ-SQL-FIN-01 and graph/FPP correspondence have explicit verifiers"
    (List.exists
       (fun (requirement : requirement) ->
         requirement.stable_id = "HZ-SQL-FIN-01"
         && requirement.verifier_id = "verify.sqlite-lifecycle")
       authority.requirements
     && List.exists
          (fun (requirement : requirement) ->
            requirement.stable_id = "REQ-DEPENDABILITY-GRAPH-FPP"
            && requirement.verifier_id = "verify.graph-fpp-correspondence")
          authority.requirements);
  check "F7b graph/FPP requirement covers every projected authority element"
    (match
       List.find_opt
         (fun (requirement : requirement) ->
           requirement.stable_id = "REQ-DEPENDABILITY-GRAPH-FPP")
         authority.requirements
     with
     | Some requirement ->
         sorted_unique requirement.covered_elements
         = sorted_unique (exhaustive_covered_elements authority)
         && List.length requirement.covered_elements
            = List.length (exhaustive_covered_elements authority)
     | None -> false);
  check "F8 reserved 0x5000..0x5fff identifiers are internally and externally disjoint"
    (window_gaps
       ~others:
         [ ("harness", Harness_topology.model); ("wiki", Wiki_topology.model);
           ("ops", Ops_topology.model);
           ("completion", Ops_completion_topology.model);
           ("operations", Run_topology.model) ]
     = []);
  check "F8b an external internal-overlap mutant is rejected outside our window"
    (window_gaps ~others:[ "outside-overlap", externally_overlapping_model () ]
     <> []);
  check "F8c a half-open interval adjacent to 0x5000 is accepted"
    (window_gaps ~others:[ "adjacent", adjacent_external_model () ] = []);
  check "F9 model, dictionary, and source authority share one deterministic digest"
    (String.length source_digest = 64
     && source_digest = source_digest_of authority
     && source_digest_of_model model = Some source_digest
     && match dictionary (), dictionary () with
        | Ok first, Ok second ->
            first = second
            && dictionary_project_version first = Some source_digest
            && String.length (Yojson.Safe.to_string first) > 100
        | Error _, _ | _, Error _ -> false);
  check "F9b source digest changes with exact projection semantics and escapes prose"
    (let renamed = mutate_authority_command_name () in
     let resignalled = mutate_authority_signal "admitMutant" in
     let escaped =
       match authority.components, authority.requirements with
       | component :: components, requirement :: requirements ->
           { authority with
             components =
               { component with purpose = "quote=\" slash=\\ newline=\n" }
               :: components;
             requirements =
               { requirement with statement = "format \"%s\" \\ escaped" }
               :: requirements }
       | _ -> authority
     in
     source_digest_of renamed <> source_digest
     && source_digest_of resignalled <> source_digest
     && String.length (source_digest_of escaped) = 64
     && source_digest_of escaped = source_digest_of escaped
     && source_digest_of escaped <> source_digest);
  check "F9c exhaustive correspondence kills omitted FPP field mutants"
    (List.for_all
       (fun mutated -> projection_gaps authority mutated <> [])
       [ mutate_projected_signal model; mutate_projected_instance model;
         mutate_projected_port model; mutate_projected_command model;
         mutate_projected_channel model ]);
  check "F9d every emitted FPP identifier is safe and unsafe names fail closed"
    (List.for_all
       (fun (component : component) -> safe_fpp_identifier component.stable_id)
       authority.components
     && List.for_all
          (fun (port : port) -> safe_fpp_identifier port.name)
          authority.ports
     && List.for_all
          (fun (command : command) -> safe_fpp_identifier command.fpp_name)
          authority.commands
     && List.for_all
          (fun (channel : channel) -> safe_fpp_identifier channel.fpp_name)
          authority.channels
     && List.for_all
          (fun (state : lifecycle_state) ->
            safe_fpp_identifier state.stable_id
            && List.for_all
                 (fun (transition : lifecycle_transition) ->
                   safe_fpp_identifier transition.signal
                   && safe_fpp_identifier transition.target_state)
                 state.transitions)
          authority.lifecycle.states
     && identifier_gaps (mutate_authority_signal "bad signal{\"") <> []
     && (match authority.commands with
         | command :: commands ->
             identifier_gaps
               { authority with
                 commands = { command with fpp_name = "9 bad-name" } :: commands }
             <> []
         | [] -> false)
     && (match authority.channels with
         | channel :: channels ->
             identifier_gaps
               { authority with
                 channels =
                   { channel with fpp_name = "bad channel%" } :: channels }
             <> []
         | [] -> false));
  check "F10 channel deletion, duplicate command, and interval overlap are killed mutants"
    (match authority.channels, authority.commands with
     | _ :: remaining_channels, command :: _ ->
         validate_authority { authority with channels = remaining_channels } <> []
         && validate_authority
              { authority with commands = command :: authority.commands } <> []
         && window_gaps
              ~others:[ "outside-overlap", externally_overlapping_model () ]
            <> []
     | _ -> false);

  Printf.printf "dependability_topology: %d passed, %d failed\n" !passed !failed;
  let self = Suite_telemetry.observe ~suite:"test_dependability_topology" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_dependability_topology ]);
  exit (Suite_telemetry.exit_code self)
