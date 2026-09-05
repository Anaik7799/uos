type model_entry = {
  owner : Fpp_window_authority.owner;
  model : Fpp_model.model;
}

let all =
  [ { owner = Fpp_window_authority.Harness; model = Harness_topology.model };
    { owner = Fpp_window_authority.Wiki; model = Wiki_topology.model };
    { owner = Fpp_window_authority.Ops_monitor; model = Ops_topology.model };
    { owner = Fpp_window_authority.Completion; model = Ops_completion_topology.model };
    { owner = Fpp_window_authority.Operations; model = Run_topology.model } ]

let models () = List.map (fun item -> (item.owner, item.model)) all

let entry_of_owner entries owner =
  List.find_opt (fun item -> item.owner = owner) entries

let diagnostics_for entries =
  List.concat_map (fun item -> Fpp_model.validate item.model) entries

let diagnostics () = diagnostics_for all

let module_mapping_gaps_for entries =
  Module_intent.all
  |> List.concat_map (fun (intent : Module_intent.t) ->
         match intent.fpp with
         | Module_intent.Fpp_not_applicable _ -> []
         | Module_intent.Fpp_components mappings ->
             mappings
             |> List.concat_map (fun (owner, components) ->
                    match entry_of_owner entries owner with
                    | None ->
                        [ Printf.sprintf "%s maps to missing FPP owner %s"
                            intent.stable_id (Fpp_window_authority.owner_name owner) ]
                    | Some entry ->
                        let names =
                          List.map (fun (component : Fpp_model.component) -> component.comp_name)
                            entry.model.components
                        in
                        components
                        |> List.filter_map (fun component ->
                               if List.mem component names then None
                               else Some (Printf.sprintf "%s maps to missing %s component %s"
                                  intent.stable_id
                                  (Fpp_window_authority.owner_name owner) component))))

let module_mapping_gaps () = module_mapping_gaps_for all

let fpp_identifier value =
  String.map
    (fun character ->
      if
        (character >= 'a' && character <= 'z')
        || (character >= 'A' && character <= 'Z')
        || (character >= '0' && character <= '9')
      then character
      else '_')
    value

let debug_mapping_gaps_for entries =
  Debug_intent.all
  |> List.concat_map (fun (intent : Debug_intent.t) ->
         let mapping = intent.fpp in
         let owner = Fpp_window_authority.Operations in
         if
           not
             (String.equal mapping.owner
                (Fpp_window_authority.owner_name owner))
         then
           [ Printf.sprintf "%s maps to unexpected FPP owner %s"
               intent.stable_id mapping.owner ]
         else
           match entry_of_owner entries owner with
           | None ->
               [ Printf.sprintf "%s maps to missing FPP owner %s"
                   intent.stable_id mapping.owner ]
           | Some entry ->
               let component =
                 List.find_opt
                   (fun (item : Fpp_model.component) ->
                     String.equal item.comp_name mapping.component)
                   entry.model.components
               in
               begin match component with
               | None ->
                   [ Printf.sprintf "%s maps to missing %s component %s"
                       intent.stable_id mapping.owner mapping.component ]
               | Some component ->
                   let gaps = ref [] in
                   if
                     not
                       (List.exists
                          (fun (item : Fpp_model.channel) ->
                            String.equal item.chan_name mapping.channel)
                          component.channels)
                   then gaps :=
                     Printf.sprintf "%s maps to missing channel %s"
                       intent.stable_id mapping.channel
                     :: !gaps;
                   let event_name =
                     "DebugFailure_" ^ fpp_identifier intent.failure_family
                   in
                   if
                     not
                       (List.exists
                          (fun (item : Fpp_model.event) ->
                            String.equal item.event_name event_name)
                          component.events)
                   then gaps :=
                     Printf.sprintf "%s has no FPP event carrier"
                       intent.stable_id
                     :: !gaps;
                   if
                     not
                       (List.exists
                          (fun (item : Fpp_model.command) ->
                            List.exists
                              (fun (command : Run_topology.gate_command) ->
                                String.equal command.intent_id intent.stable_id
                                && String.equal command.stable_id item.cmd_name)
                              Run_topology.authority.gate_commands)
                          component.commands)
                   then gaps :=
                     Printf.sprintf "%s has no FPP command carrier"
                       intent.stable_id
                     :: !gaps;
                   if
                     not
                       (List.exists
                          (fun (item : Fpp_model.parameter) ->
                            item.default = Some intent.stable_id)
                          component.parameters)
                   then gaps :=
                     Printf.sprintf "%s has no FPP parameter carrier"
                       intent.stable_id
                     :: !gaps;
                   List.rev !gaps
               end)

let debug_mapping_gaps () = debug_mapping_gaps_for all

let window_gaps entries =
  entries
  |> List.concat_map (fun entry ->
         Fpp_window_authority.rows entry.owner entry.model
         |> List.concat_map (fun (row : Fpp_window_authority.row) ->
                let prefix = Fpp_window_authority.owner_name row.owner ^ "/" ^ row.instance_id in
                let gaps = ref [] in
                let add message = gaps := (prefix ^ ": " ^ message) :: !gaps in
                if row.declared_model_name <> row.observed_model_name then add "model name differs from registry";
                if not row.allocation_present then add "declared allocation is absent";
                if not row.component_present then add "declared component is absent";
                if row.observed_instance_id <> row.instance_id then add "instance identity differs";
                if row.observed_component_id <> row.component_id then add "component identity differs";
                if row.declared_base_id >= 0 && row.observed_base_id <> row.declared_base_id then
                  add "base id differs from allocation authority";
                if row.span <= 0 then add "component id span is non-positive";
                List.rev !gaps))

let unique values = List.length values = List.length (List.sort_uniq compare values)

let validate_entries entries =
  let gaps = ref [] in
  let add message = gaps := message :: !gaps in
  let owners = List.map (fun item -> item.owner) entries in
  if owners <> Fpp_window_authority.owners then add "FPP owner denominator or order differs";
  if not (unique owners) then add "FPP owner occurs more than once";
  List.iter
    (fun item ->
      if item.model.model_name <> Fpp_window_authority.declared_model_name item.owner then
        add (Fpp_window_authority.owner_name item.owner ^ " model name differs from authority"))
    entries;
  List.iter (fun diagnostic -> add (Fractal_diagnostic.render diagnostic)) (diagnostics_for entries);
  List.iter add (window_gaps entries);
  List.iter add (module_mapping_gaps_for entries);
  List.iter add (debug_mapping_gaps_for entries);
  List.rev !gaps

let validate () = validate_entries all

let canonical_entry item =
  String.concat "|"
    [ Fpp_window_authority.owner_name item.owner;
      item.model.model_name; Fpp_model.to_fpp item.model ]

let portfolio_source_digest =
  let payload =
    String.concat "\n"
      (Fpp_window_authority.allocation_digest () :: Module_intent.source_digest
       :: Debug_intent.source_digest
       :: List.map canonical_entry all)
  in
  Digestif.SHA256.(to_hex (digest_string payload))

type jujutsu_fragment = {
  effect_kind_ids : string list;
  operation_activity_ids : string list;
  phase_template_ids : string list;
  conditional_template_ids : string list;
  candidate_action_ids : string list;
  formal_action_ids : string list;
  work_class_ids : string list;
  completion_work_ids : string list;
  static_templates_digest : string;
  lifecycle_state_ids : string list;
  conditional_state_ids : string list;
  conditional_event_ids : string list;
  conditional_channel_ids : string list;
  live_activation_claim : bool;
}

let operation_activity_id operation =
  "activity.jj." ^ (Jj_operation.declaration operation).key

let candidate_action_id step =
  "action.candidate." ^ Jj_action_kind.candidate_step_key step

let topology_template_ids template_class =
  Run_topology.task7a_static_templates
  |> List.filter_map (fun template ->
       if template.Run_topology.template_class = template_class then
         Some template.template_stable_id
       else None)

let jujutsu_fragment =
  { effect_kind_ids =
      List.map Run_topology.effect_kind_id Run_topology.effect_kinds;
    operation_activity_ids = List.map operation_activity_id Jj_operation.all;
    phase_template_ids =
      topology_template_ids Run_topology.Standalone_phase_template;
    conditional_template_ids =
      topology_template_ids Run_topology.Conditional_family_template;
    candidate_action_ids =
      List.map candidate_action_id Jj_action_kind.candidate_steps;
    formal_action_ids = [];
    work_class_ids = Run_topology.task7a_action_work_class_ids;
    completion_work_ids = Run_topology.task7a_completion_receipt_work_ids;
    static_templates_digest = Run_topology.task7a_static_template_digest;
    lifecycle_state_ids =
      List.map Run_topology.controlled_lifecycle_state_id
        Run_topology.controlled_lifecycle_states;
    conditional_state_ids =
      List.map Run_topology.conditional_control_state_id
        Run_topology.conditional_control_states;
    conditional_event_ids =
      List.map Run_topology.conditional_control_event_id
        Run_topology.conditional_control_events;
    conditional_channel_ids =
      List.map Run_topology.conditional_channel_kind_id
        Run_topology.conditional_channel_kinds;
    live_activation_claim = false }

let jujutsu_effect_kind_ids fragment = fragment.effect_kind_ids
let jujutsu_operation_activity_ids fragment = fragment.operation_activity_ids
let standalone_phase_template_ids fragment = fragment.phase_template_ids
let conditional_family_template_ids fragment = fragment.conditional_template_ids
let candidate_verification_action_ids fragment = fragment.candidate_action_ids
let formal_oracle_action_ids fragment = fragment.formal_action_ids
let action_work_class_ids fragment = fragment.work_class_ids
let completion_receipt_work_ids fragment = fragment.completion_work_ids
let static_template_digest fragment = fragment.static_templates_digest
let controlled_lifecycle_state_ids fragment = fragment.lifecycle_state_ids
let conditional_control_state_ids fragment = fragment.conditional_state_ids
let conditional_control_event_ids fragment = fragment.conditional_event_ids
let conditional_channel_kind_ids fragment = fragment.conditional_channel_ids

let canonical_fragment fragment =
  [ fragment.effect_kind_ids; fragment.operation_activity_ids;
    fragment.phase_template_ids; fragment.conditional_template_ids;
    fragment.candidate_action_ids; fragment.formal_action_ids;
    fragment.work_class_ids; fragment.completion_work_ids;
    [ fragment.static_templates_digest ];
    fragment.lifecycle_state_ids; fragment.conditional_state_ids;
    fragment.conditional_event_ids; fragment.conditional_channel_ids;
    [ string_of_bool fragment.live_activation_claim ] ]
  |> List.map (String.concat "\031") |> String.concat "\030"

let jujutsu_fragment_digest fragment =
  fragment |> canonical_fragment |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let unique values =
  List.length values = List.length (List.sort_uniq String.compare values)

let validate_fragment fragment =
  let gaps = ref [] in
  let exact label expected observed =
    if expected <> observed then gaps := (label ^ " denominator differs") :: !gaps
  in
  exact "effect-kind"
    (List.map Run_topology.effect_kind_id Run_topology.effect_kinds)
    fragment.effect_kind_ids;
  exact "Jujutsu operation activity"
    (List.map operation_activity_id Jj_operation.all)
    fragment.operation_activity_ids;
  exact "standalone phase template"
    (topology_template_ids Run_topology.Standalone_phase_template)
    fragment.phase_template_ids;
  exact "conditional family template"
    (topology_template_ids Run_topology.Conditional_family_template)
    fragment.conditional_template_ids;
  exact "candidate verification action"
    (List.map candidate_action_id Jj_action_kind.candidate_steps)
    fragment.candidate_action_ids;
  exact "formal oracle action"
    []
    fragment.formal_action_ids;
  exact "action work class" Run_topology.task7a_action_work_class_ids
    fragment.work_class_ids;
  exact "completion receipt work"
    Run_topology.task7a_completion_receipt_work_ids fragment.completion_work_ids;
  if fragment.static_templates_digest
     <> Run_topology.task7a_static_template_digest
  then gaps := "static template digest differs" :: !gaps;
  exact "controlled lifecycle state"
    (List.map Run_topology.controlled_lifecycle_state_id
       Run_topology.controlled_lifecycle_states)
    fragment.lifecycle_state_ids;
  exact "conditional control state"
    (List.map Run_topology.conditional_control_state_id
       Run_topology.conditional_control_states)
    fragment.conditional_state_ids;
  exact "conditional control event"
    (List.map Run_topology.conditional_control_event_id
       Run_topology.conditional_control_events)
    fragment.conditional_event_ids;
  exact "conditional channel kind"
    (List.map Run_topology.conditional_channel_kind_id
       Run_topology.conditional_channel_kinds)
    fragment.conditional_channel_ids;
  List.iter
    (fun (label, values) ->
      if values = [] then gaps := (label ^ " denominator is empty") :: !gaps;
      if not (unique values) then gaps := (label ^ " denominator duplicates") :: !gaps)
    [ ("effect-kind", fragment.effect_kind_ids);
      ("operation", fragment.operation_activity_ids);
      ("phase-template", fragment.phase_template_ids);
      ("conditional-template", fragment.conditional_template_ids);
      ("candidate", fragment.candidate_action_ids);
      ("work-class", fragment.work_class_ids);
      ("completion-work", fragment.completion_work_ids);
      ("lifecycle", fragment.lifecycle_state_ids);
      ("conditional-state", fragment.conditional_state_ids);
      ("conditional-event", fragment.conditional_event_ids);
      ("conditional-channel", fragment.conditional_channel_ids) ];
  if fragment.live_activation_claim then
    gaps := "Task-7A fragment claims live activation" :: !gaps;
  List.rev !gaps

let jujutsu_fragment_gaps () = validate_fragment jujutsu_fragment
let activation_posture = `Implemented_unavailable

let source_digest =
  String.concat "\000"
    [ portfolio_source_digest; Run_topology.task7a_declaration_digest;
      jujutsu_fragment_digest jujutsu_fragment;
      "activation:implemented-unavailable" ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let receipt_json () =
  let valid =
    List.length
      (List.filter
         (fun item ->
           item.model.model_name = Fpp_window_authority.declared_model_name item.owner
           && Fpp_model.validate item.model = [])
         all)
  in
  let mapped, not_applicable =
    List.fold_left
      (fun (mapped, excluded) (item : Module_intent.t) ->
        match item.fpp with
        | Module_intent.Fpp_components _ -> (mapped + 1, excluded)
        | Module_intent.Fpp_not_applicable _ -> (mapped, excluded + 1))
      (0, 0) Module_intent.all
  in
  `Assoc
    [ ("authority", `String "Run_fpp_authority");
      ("source_digest", `String source_digest);
      ("task7a_declaration_digest",
       `String Run_topology.task7a_declaration_digest);
      ("jujutsu_fragment_digest",
       `String (jujutsu_fragment_digest jujutsu_fragment));
      ("jujutsu_fragment_gaps",
       `Int (List.length (jujutsu_fragment_gaps ())));
      ("activation_posture", `String "implemented-unavailable");
      ("allocation_digest", `String (Fpp_window_authority.allocation_digest ()));
      ("module_intent_digest", `String Module_intent.source_digest);
      ("debug_intent_digest", `String Debug_intent.source_digest);
      ("model_total", `Int (List.length all));
      ("model_valid", `Int valid);
      ("model_owners",
       `List (List.map (fun item -> `String (Fpp_window_authority.owner_name item.owner)) all));
      ("module_interface_total", `Int (List.length Module_intent.all));
      ("module_fpp_mapped", `Int mapped);
      ("module_fpp_not_applicable", `Int not_applicable);
      ("module_mapping_gaps", `Int (List.length (module_mapping_gaps ())));
      ("debug_intent_total", `Int (List.length Debug_intent.all));
      ("debug_mapping_gaps", `Int (List.length (debug_mapping_gaps ()))) ]

module For_test = struct
  type mutation =
    Drop_wiki | Duplicate_harness | Rename_ops_model | Drop_mapped_component
    | Drop_debug_component | Drop_debug_event
  let mutate = function
    | Drop_wiki -> List.filter (fun item -> item.owner <> Fpp_window_authority.Wiki) all
    | Duplicate_harness ->
        begin match all with [] -> [] | first :: _ -> first :: all end
    | Rename_ops_model ->
        List.map
          (fun item ->
            if item.owner = Fpp_window_authority.Ops_monitor then
              { item with model = { item.model with model_name = "MutatedOps" } }
            else item)
          all
    | Drop_mapped_component ->
        List.map
          (fun item ->
            if item.owner = Fpp_window_authority.Harness then
              { item with model = { item.model with components =
                  List.filter (fun (component : Fpp_model.component) ->
                    component.comp_name <> "inventory") item.model.components } }
            else item)
          all
    | Drop_debug_component ->
        List.map
          (fun item ->
            if item.owner = Fpp_window_authority.Operations then
              { item with model = { item.model with components =
                  List.filter (fun (component : Fpp_model.component) ->
                    component.comp_name <> "completionGate") item.model.components } }
            else item)
          all
    | Drop_debug_event ->
        List.map
          (fun item ->
            if item.owner = Fpp_window_authority.Operations then
              { item with model = { item.model with components =
                  List.map
                    (fun (component : Fpp_model.component) ->
                      if component.comp_name = "completionGate" then
                        { component with events = [] }
                      else component)
                    item.model.components } }
            else item)
          all
  let validate_entries = validate_entries

  type fragment_mutation =
    | Drop_jujutsu_effect
    | Duplicate_operation_activity
    | Drop_conditional_channel
    | Claim_live_activation
    | Drop_phase_template
    | Flatten_conditional_template
    | Swap_completion_receipt_work

  let mutate_fragment = function
    | Drop_jujutsu_effect ->
        { jujutsu_fragment with
          effect_kind_ids =
            (match jujutsu_fragment.effect_kind_ids with
             | [] -> []
             | _ :: rest -> rest) }
    | Duplicate_operation_activity ->
        { jujutsu_fragment with
          operation_activity_ids =
            (match jujutsu_fragment.operation_activity_ids with
             | [] -> [ "activity.jj.duplicate"; "activity.jj.duplicate" ]
             | first :: _ -> first :: jujutsu_fragment.operation_activity_ids) }
    | Drop_conditional_channel ->
        { jujutsu_fragment with
          conditional_channel_ids =
            (match jujutsu_fragment.conditional_channel_ids with
             | [] -> []
             | _ :: rest -> rest) }
    | Claim_live_activation ->
        { jujutsu_fragment with live_activation_claim = true }
    | Drop_phase_template ->
        { jujutsu_fragment with
          phase_template_ids =
            (match jujutsu_fragment.phase_template_ids with
             | [] -> [] | _ :: rest -> rest) }
    | Flatten_conditional_template ->
        { jujutsu_fragment with
          conditional_template_ids = [ "flattened-conditional-actions" ] }
    | Swap_completion_receipt_work ->
        { jujutsu_fragment with
          completion_work_ids =
            List.rev jujutsu_fragment.completion_work_ids }

  let validate_fragment = validate_fragment
end
