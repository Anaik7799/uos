type engine = Rete_ul | Raven_matrix

let gate = function
  | Rete_ul -> Run_safety.Rete_ul
  | Raven_matrix -> Run_safety.Raven_matrix

let authority engine = Run_safety.authority_of_gate (gate engine)

let unavailable_receipt context ~engine ~reason =
  match engine with
  | Rete_ul -> Run_safety.rete_unavailable_receipt context ~reason
  | Raven_matrix -> Run_safety.raven_unavailable_receipt context ~reason

module Rete_ul = struct
  module String_map = Map.Make (String)
  module String_set = Set.Make (String)

  type value = Int of int | String of string | Bool of bool

  type budgets = {
    max_facts : int;
    max_alpha_entries : int;
    max_beta_tokens : int;
    max_agenda : int;
    max_firings : int;
    max_trace_entries : int;
  }

  type condition =
    | Field_eq of string * value
    | Join_eq of string * string
    | Bind of string * string

  type pattern = {
    pattern_id : string;
    fact_kind : string;
    conditions : condition list;
  }

  type value_expr = Literal of value | Variable of string
  type rhs_template = {
    fact_id : string;
    fact_kind : string;
    attrs : (string * value_expr) list;
  }
  type rhs_action =
    | Assert_rhs of rhs_template
    | Update_rhs of rhs_template
    | Retract_rhs of string
    | Block_rhs of string

  type rule = {
    rule_id : string;
    salience : int;
    patterns : pattern list;
    actions : rhs_action list;
  }
  type network = { network_id : string; budgets : budgets; rules : rule list }

  type fact = {
    fact_id : string;
    fact_kind : string;
    attrs : (string * value) list;
    fact_digest : string;
  }
  type delta = Assert_fact of fact | Update_fact of fact | Retract_fact of string
  type binding = (string * value) list
  type token = { bindings : binding; supports : string list; token_digest : string }
  type activation = {
    rule : rule;
    bindings : binding;
    supports : string list;
    activation_digest : string;
  }
  type rule_memory = {
    alpha_count : int;
    tokens : token list;
    activations : activation list;
  }
  type refraction_entry = { activation_digest : string; supports : string list }
  type compiled = {
    context : Run_safety.gate_context;
    network : network;
    digest : string;
    rules_by_kind : rule list String_map.t;
  }
  type session = {
    context : Run_safety.gate_context;
    compiled : compiled;
    facts : fact String_map.t;
    memories : rule_memory String_map.t;
    agenda : activation list;
    refraction : refraction_entry list;
    delta_digests : string list;
    link_count : int;
    unlink_count : int;
    session_digest : string;
  }

  type snapshot = {
    fact_count : int;
    alpha_entry_count : int;
    beta_token_count : int;
    agenda_count : int;
    session_digest : string;
  }
  type trace_entry = {
    ordinal : int;
    rule_id : string;
    activation_digest : string;
    outcome : string;
  }
  type partial_trace = {
    entries : trace_entry list;
    truncated : bool;
    trace_digest : string;
  }
  type delta_receipt = {
    changed : bool;
    delta_digest : string;
    receipt_digest : string;
  }
  type rete_receipt = {
    authority : Run_safety.authority;
    context_digest : string;
    current_head_digest : string;
    current_at_ns : int64;
    network_digest : string;
    input_fact_digest : string;
    session_digest : string;
    fixed_point : bool;
    empty_agenda : bool;
    firing_count : int;
    output_fact_digest : string;
    trace_digest : string;
    receipt_digest : string;
  }
  type static_outcome = Static_accept | Static_block
  type dispatch_receipt = {
    authority : Run_safety.authority;
    context_digest : string;
    current_head_digest : string;
    current_at_ns : int64;
    network_digest : string;
    input_fact_digest : string;
    static_outcome : static_outcome;
    fixed_point : bool;
    empty_agenda : bool;
    rete_receipt_digest : string;
    receipt_digest : string;
  }

  let ( let* ) value continuation =
    match value with Ok result -> continuation result | Error _ as error -> error

  let nonempty value = String.trim value <> ""
  let sha256 text = Digestif.SHA256.(to_hex (digest_string text))
  let digest_json json = sha256 (Yojson.Safe.to_string json)

  let value_json = function
    | Int value -> `Assoc [ ("int", `Int value) ]
    | String value -> `Assoc [ ("string", `String value) ]
    | Bool value -> `Assoc [ ("bool", `Bool value) ]

  let value_equal left right =
    match left, right with
    | Int left, Int right -> left = right
    | String left, String right -> String.equal left right
    | Bool left, Bool right -> left = right
    | (Int _ | String _ | Bool _), _ -> false

  let attrs_json attrs =
    attrs
    |> List.sort (fun (left, _) (right, _) -> String.compare left right)
    |> List.map (fun (name, value) ->
           `Assoc [ ("name", `String name); ("value", value_json value) ])
    |> fun rows -> `List rows

  let fact_json (fact : fact) =
    `Assoc
      [ ("attrs", attrs_json fact.attrs);
        ("factId", `String fact.fact_id);
        ("factKind", `String fact.fact_kind) ]

  let make_fact ~fact_id ~fact_kind ~attrs =
    let names = List.map fst attrs in
    if not (nonempty fact_id && nonempty fact_kind) then
      Error "fact id and kind must be nonempty"
    else if List.exists (fun name -> not (nonempty name)) names then
      Error "fact attribute names must be nonempty"
    else if List.length names <> List.length (List.sort_uniq String.compare names) then
      Error "fact attributes must have unique names"
    else
      let attrs =
        List.sort (fun (left, _) (right, _) -> String.compare left right) attrs
      in
      let provisional = { fact_id; fact_kind; attrs; fact_digest = "" } in
      Ok { provisional with fact_digest = digest_json (fact_json provisional) }

  let condition_json = function
    | Field_eq (field, value) ->
        `Assoc
          [ ("field", `String field); ("kind", `String "field-eq");
            ("value", value_json value) ]
    | Join_eq (field, variable) ->
        `Assoc
          [ ("field", `String field); ("kind", `String "join-eq");
            ("variable", `String variable) ]
    | Bind (variable, field) ->
        `Assoc
          [ ("field", `String field); ("kind", `String "bind");
            ("variable", `String variable) ]

  let pattern_json (pattern : pattern) =
    `Assoc
      [ ("conditions", `List (List.map condition_json pattern.conditions));
        ("factKind", `String pattern.fact_kind);
        ("patternId", `String pattern.pattern_id) ]

  let value_expr_json = function
    | Literal value -> `Assoc [ ("literal", value_json value) ]
    | Variable variable -> `Assoc [ ("variable", `String variable) ]

  let template_json (template : rhs_template) =
    `Assoc
      [ ("attrs",
         `List
           (template.attrs
            |> List.sort (fun (left, _) (right, _) -> String.compare left right)
            |> List.map (fun (name, expression) ->
                   `Assoc
                     [ ("expression", value_expr_json expression);
                       ("name", `String name) ])));
        ("factId", `String template.fact_id);
        ("factKind", `String template.fact_kind) ]

  let action_json = function
    | Assert_rhs template ->
        `Assoc [ ("kind", `String "assert"); ("template", template_json template) ]
    | Update_rhs template ->
        `Assoc [ ("kind", `String "update"); ("template", template_json template) ]
    | Retract_rhs fact_id ->
        `Assoc [ ("factId", `String fact_id); ("kind", `String "retract") ]
    | Block_rhs reason ->
        `Assoc [ ("kind", `String "block"); ("reason", `String reason) ]

  let rule_json (rule : rule) =
    `Assoc
      [ ("actions", `List (List.map action_json rule.actions));
        ("patterns", `List (List.map pattern_json rule.patterns));
        ("ruleId", `String rule.rule_id);
        ("salience", `Int rule.salience) ]

  let budgets_json (budgets : budgets) =
    `Assoc
      [ ("agenda", `Int budgets.max_agenda);
        ("alpha", `Int budgets.max_alpha_entries);
        ("beta", `Int budgets.max_beta_tokens);
        ("facts", `Int budgets.max_facts);
        ("firings", `Int budgets.max_firings);
        ("trace", `Int budgets.max_trace_entries) ]

  let network_json (network : network) =
    `Assoc
      [ ("budgets", budgets_json network.budgets);
        ("networkId", `String network.network_id);
        ("rules", `List (List.map rule_json network.rules)) ]

  let error context message =
    Run_safety.make_gate_error context ~code:Run_safety.Invalid_model ~message
      ~rca_origin:Ops_capability.Control ~hazard_id:"HZ-T6-INTELLIGENCE-01"

  let duplicates values =
    values
    |> List.sort String.compare
    |> List.fold_left
         (fun (previous, duplicates) value ->
           match previous with
           | Some old when String.equal old value -> (Some value, value :: duplicates)
           | _ -> (Some value, duplicates))
         (None, [])
    |> snd |> List.sort_uniq String.compare

  let validate_budgets (budgets : budgets) =
    let values =
      [ budgets.max_facts; budgets.max_alpha_entries; budgets.max_beta_tokens;
        budgets.max_agenda; budgets.max_firings; budgets.max_trace_entries ]
    in
    if List.for_all (fun value -> value > 0) values then Ok ()
    else Error "every Rete_UL budget must be positive"

  let validate_rule (rule : rule) =
    if not (nonempty rule.rule_id) then Error "rule id must be nonempty"
    else if rule.patterns = [] then Error (rule.rule_id ^ " has no patterns")
    else if rule.actions = [] then Error (rule.rule_id ^ " has no actions")
    else
      let pattern_ids =
        List.map (fun (pattern : pattern) -> pattern.pattern_id) rule.patterns
      in
      if duplicates pattern_ids <> [] then Error (rule.rule_id ^ " has duplicate pattern ids")
      else
        let rec patterns bound = function
          | [] -> Ok bound
          | (pattern : pattern) :: rest ->
              if not (nonempty pattern.pattern_id && nonempty pattern.fact_kind) then
                Error (rule.rule_id ^ " has an empty pattern id or kind")
              else
                let rec conditions bound = function
                  | [] -> Ok bound
                  | Field_eq (field, _) :: tail ->
                      if nonempty field then conditions bound tail
                      else Error (rule.rule_id ^ " has an empty field")
                  | Bind (variable, field) :: tail ->
                      if not (nonempty variable && nonempty field) then
                        Error (rule.rule_id ^ " has an empty binding")
                      else if String_set.mem variable bound then
                        Error (rule.rule_id ^ " has a duplicate binding: " ^ variable)
                      else conditions (String_set.add variable bound) tail
                  | Join_eq (field, variable) :: tail ->
                      if not (nonempty field && nonempty variable) then
                        Error (rule.rule_id ^ " has an empty join")
                      else if not (String_set.mem variable bound) then
                        Error (rule.rule_id ^ " has a forward or unknown join: " ^ variable)
                      else conditions bound tail
                in
                let* bound = conditions bound pattern.conditions in
                patterns bound rest
        in
        let* bound = patterns String_set.empty rule.patterns in
        let targets =
          List.filter_map
            (function
              | Assert_rhs template | Update_rhs template -> Some template.fact_id
              | Retract_rhs fact_id -> Some fact_id
              | Block_rhs _ -> None)
            rule.actions
        in
        if duplicates targets <> [] then
          Error (rule.rule_id ^ " has conflicting literal action targets")
        else
          let variables = bound in
          let validate_template (template : rhs_template) =
            let names = List.map fst template.attrs in
            nonempty template.fact_id && nonempty template.fact_kind
            && List.for_all (fun name -> nonempty name) names
            && duplicates names = []
            && List.for_all
                 (fun (_, expression) ->
                   match expression with
                   | Literal _ -> true
                   | Variable variable -> String_set.mem variable variables)
                 template.attrs
          in
          if
            List.for_all
              (function
                | Assert_rhs template | Update_rhs template -> validate_template template
                | Retract_rhs fact_id | Block_rhs fact_id -> nonempty fact_id)
              rule.actions
          then Ok ()
          else Error (rule.rule_id ^ " has an invalid or unbound RHS")

  let compile context (network : network) =
    match validate_budgets network.budgets with
    | Error message -> Error (error context message)
    | Ok () when not (nonempty network.network_id) ->
        Error (error context "network id must be nonempty")
    | Ok () when network.rules = [] -> Error (error context "network has no rules")
    | Ok () ->
        let rule_ids = List.map (fun (rule : rule) -> rule.rule_id) network.rules in
        begin match duplicates rule_ids with
        | _ :: _ -> Error (error context "network has duplicate rule ids")
        | [] ->
            let rec validate = function
              | [] -> Ok ()
              | rule :: rest ->
                  begin match validate_rule rule with
                  | Error message -> Error (error context message)
                  | Ok () -> validate rest
                  end
            in
            let* () = validate network.rules in
            let rules_by_kind =
              List.fold_left
                (fun index rule ->
                  List.fold_left
                    (fun index (pattern : pattern) ->
                      let current =
                        Option.value (String_map.find_opt pattern.fact_kind index)
                          ~default:[]
                      in
                      String_map.add pattern.fact_kind (rule :: current) index)
                    index rule.patterns)
                String_map.empty network.rules
              |> String_map.map (List.sort_uniq (fun (left : rule) (right : rule) ->
                     String.compare left.rule_id right.rule_id))
            in
            Ok
              { context; network; digest = digest_json (network_json network);
                rules_by_kind }
        end

  let compiled_digest (compiled : compiled) = compiled.digest

  let attr (fact : fact) field = List.assoc_opt field fact.attrs

  let alpha_matches (fact : fact) (pattern : pattern) =
    String.equal fact.fact_kind pattern.fact_kind
    && List.for_all
         (function
           | Field_eq (field, expected) ->
               Option.exists (value_equal expected) (attr fact field)
           | Bind (_, field) | Join_eq (field, _) -> Option.is_some (attr fact field))
         pattern.conditions

  let binding_json bindings =
    bindings
    |> List.sort (fun (left, _) (right, _) -> String.compare left right)
    |> List.map (fun (name, value) ->
           `Assoc [ ("name", `String name); ("value", value_json value) ])
    |> fun rows -> `List rows

  let support_json (facts : fact String_map.t) supports =
    supports
    |> List.sort String.compare
    |> List.filter_map (fun fact_id ->
           Option.map
             (fun (fact : fact) ->
               `Assoc
                 [ ("factDigest", `String fact.fact_digest);
                   ("factId", `String fact.fact_id) ])
             (String_map.find_opt fact_id facts))
    |> fun rows -> `List rows

  let make_token (facts : fact String_map.t) (bindings : binding) supports =
    let bindings = List.sort (fun (left, _) (right, _) -> String.compare left right) bindings in
    let supports = List.sort_uniq String.compare supports in
    let token_digest =
      digest_json
        (`Assoc
           [ ("bindings", binding_json bindings);
             ("supports", support_json facts supports) ])
    in
    { bindings; supports; token_digest }

  let extend_token (facts : fact String_map.t) (token : token) (fact : fact)
      (pattern : pattern) =
    if not (alpha_matches fact pattern) then None
    else
      let rec conditions bindings = function
        | [] -> Some bindings
        | Field_eq (field, expected) :: rest ->
            begin match attr fact field with
            | Some observed when value_equal observed expected -> conditions bindings rest
            | Some _ | None -> None
            end
        | Bind (variable, field) :: rest ->
            begin match attr fact field, List.assoc_opt variable bindings with
            | Some observed, None -> conditions ((variable, observed) :: bindings) rest
            | Some observed, Some bound when value_equal observed bound ->
                conditions bindings rest
            | Some _, Some _ | None, _ -> None
            end
        | Join_eq (field, variable) :: rest ->
            begin match attr fact field, List.assoc_opt variable bindings with
            | Some observed, Some bound when value_equal observed bound ->
                conditions bindings rest
            | Some _, Some _ | Some _, None | None, _ -> None
            end
      in
      Option.map
        (fun bindings -> make_token facts bindings (fact.fact_id :: token.supports))
        (conditions token.bindings pattern.conditions)

  let compute_memory (facts : fact String_map.t) (rule : rule) =
    let fact_rows = String_map.bindings facts |> List.map snd in
    let alpha_count =
      List.fold_left
        (fun count pattern ->
          count
          + List.length
              (List.filter (fun (fact : fact) -> alpha_matches fact pattern) fact_rows))
        0 rule.patterns
    in
    let initial = make_token facts [] [] in
    let rec prefixes current all = function
      | [] -> (current, all)
      | pattern :: rest ->
          let next =
            List.concat_map
              (fun (token : token) ->
                fact_rows
                |> List.filter_map (fun (fact : fact) ->
                       extend_token facts token fact pattern))
              current
            |> List.sort_uniq (fun (left : token) (right : token) ->
                   String.compare left.token_digest right.token_digest)
          in
          prefixes next (all @ next) rest
    in
    let final_tokens, tokens = prefixes [ initial ] [] rule.patterns in
    let activations =
      List.map
        (fun (token : token) ->
          let activation_digest =
            digest_json
              (`Assoc
                 [ ("bindings", binding_json token.bindings);
                   ("ruleId", `String rule.rule_id);
                   ("supports", support_json facts token.supports) ])
          in
          { rule; bindings = token.bindings; supports = token.supports;
            activation_digest })
        final_tokens
    in
    { alpha_count; tokens; activations }

  let activation_compare (left : activation) (right : activation) =
    let salience = Int.compare right.rule.salience left.rule.salience in
    if salience <> 0 then salience
    else
      let rule = String.compare left.rule.rule_id right.rule.rule_id in
      if rule <> 0 then rule
      else String.compare left.activation_digest right.activation_digest

  let facts_digest (facts : fact String_map.t) =
    facts |> String_map.bindings
    |> List.map (fun (_, (fact : fact)) -> fact_json fact)
    |> fun rows -> digest_json (`List rows)

  let memory_token_digests (memories : rule_memory String_map.t) =
    memories |> String_map.bindings
    |> List.concat_map (fun (_, (memory : rule_memory)) ->
           List.map (fun (token : token) -> token.token_digest) memory.tokens)
    |> List.sort String.compare

  let agenda_digest (agenda : activation list) =
    agenda
    |> List.map (fun (activation : activation) ->
           `String activation.activation_digest)
    |> fun rows -> digest_json (`List rows)

  let refraction_digest (refraction : refraction_entry list) =
    refraction
    |> List.sort (fun (left : refraction_entry) (right : refraction_entry) ->
           String.compare left.activation_digest right.activation_digest)
    |> List.map (fun (entry : refraction_entry) ->
           `Assoc
             [ ("activationDigest", `String entry.activation_digest);
               ("supports", `List (List.map (fun id -> `String id) entry.supports)) ])
    |> fun rows -> digest_json (`List rows)

  let session_digest_of network_digest (facts : fact String_map.t)
      (memories : rule_memory String_map.t) (agenda : activation list)
      (refraction : refraction_entry list) delta_digests link_count
      unlink_count =
    digest_json
      (`Assoc
         [ ("agenda", `String (agenda_digest agenda));
           ("deltas", `List (List.map (fun digest -> `String digest) delta_digests));
           ("facts", `String (facts_digest facts));
           ("links", `Int link_count);
           ("networkDigest", `String network_digest);
           ("refraction", `String (refraction_digest refraction));
           ("tokens",
            `List (List.map (fun digest -> `String digest)
                     (memory_token_digests memories)));
           ("unlinks", `Int unlink_count) ])

  let counts (memories : rule_memory String_map.t) (agenda : activation list)
      (facts : fact String_map.t) =
    let alpha =
      String_map.fold
        (fun _ (memory : rule_memory) count -> count + memory.alpha_count)
        memories 0
    in
    let beta =
      String_map.fold
        (fun _ (memory : rule_memory) count -> count + List.length memory.tokens)
        memories 0
    in
    (String_map.cardinal facts, alpha, beta, List.length agenda)

  let within_budgets (budgets : budgets) (memories : rule_memory String_map.t)
      (agenda : activation list) (facts : fact String_map.t) =
    let facts_count, alpha, beta, agenda_count = counts memories agenda facts in
    if facts_count > budgets.max_facts then Error "Rete_UL fact budget exhausted"
    else if alpha > budgets.max_alpha_entries then Error "Rete_UL alpha budget exhausted"
    else if beta > budgets.max_beta_tokens then Error "Rete_UL beta budget exhausted"
    else if agenda_count > budgets.max_agenda then Error "Rete_UL agenda budget exhausted"
    else Ok ()

  let agenda_of (memories : rule_memory String_map.t)
      (refraction : refraction_entry list) =
    let refracted =
      List.fold_left
        (fun set (entry : refraction_entry) ->
          String_set.add entry.activation_digest set)
        String_set.empty refraction
    in
    memories |> String_map.bindings
    |> List.concat_map (fun (_, (memory : rule_memory)) -> memory.activations)
    |> List.filter (fun (activation : activation) ->
           not (String_set.mem activation.activation_digest refracted))
    |> List.sort_uniq activation_compare

  let affected_rules (compiled : compiled) kinds =
    String_set.fold
      (fun kind rules ->
        Option.value (String_map.find_opt kind compiled.rules_by_kind) ~default:[]
        |> List.fold_left
             (fun rules (rule : rule) ->
               String_map.add rule.rule_id rule rules)
             rules)
      kinds String_map.empty

  let rebuild (session : session) ~facts ~refraction ~delta_digests ~affected =
    let rules = affected_rules session.compiled affected in
    let memories =
      String_map.fold
        (fun rule_id (rule : rule) memories ->
          String_map.add rule_id (compute_memory facts rule) memories)
        rules session.memories
    in
    let old_tokens = memory_token_digests session.memories |> String_set.of_list in
    let new_tokens = memory_token_digests memories |> String_set.of_list in
    let link_count =
      session.link_count + String_set.cardinal (String_set.diff new_tokens old_tokens)
    in
    let unlink_count =
      session.unlink_count + String_set.cardinal (String_set.diff old_tokens new_tokens)
    in
    let agenda = agenda_of memories refraction in
    let* () = within_budgets session.compiled.network.budgets memories agenda facts in
    let session_digest =
      session_digest_of session.compiled.digest facts memories agenda refraction
        delta_digests link_count unlink_count
    in
    Ok
      { session with facts; memories; agenda; refraction; delta_digests;
        link_count; unlink_count; session_digest }

  let trace_json entries truncated =
    let rows =
      entries
      |> List.map (fun (entry : trace_entry) ->
             `Assoc
               [ ("activationDigest", `String entry.activation_digest);
                 ("ordinal", `Int entry.ordinal);
                 ("outcome", `String entry.outcome);
                 ("ruleId", `String entry.rule_id) ])
    in
    `Assoc [ ("entries", `List rows); ("truncated", `Bool truncated) ]

  let partial entries truncated =
    { entries; truncated; trace_digest = digest_json (trace_json entries truncated) }

  let empty_partial = partial [] false

  let create context (compiled : compiled) =
    if not (Run_safety.same_context context compiled.context) then
      Error (error context "compiled Rete_UL context differs")
    else
      let memories =
        List.fold_left
          (fun memories (rule : rule) ->
            String_map.add rule.rule_id (compute_memory String_map.empty rule) memories)
          String_map.empty compiled.network.rules
      in
      let agenda = [] and refraction = [] and delta_digests = [] in
      let session_digest =
        session_digest_of compiled.digest String_map.empty memories agenda refraction
          delta_digests 0 0
      in
      Ok
        { context; compiled; facts = String_map.empty; memories; agenda; refraction;
          delta_digests; link_count = 0; unlink_count = 0; session_digest }

  let snapshot (session : session) =
    let fact_count, alpha_entry_count, beta_token_count, agenda_count =
      counts session.memories session.agenda session.facts
    in
    { fact_count; alpha_entry_count; beta_token_count; agenda_count;
      session_digest = session.session_digest }

  let delta_json = function
    | Assert_fact fact ->
        `Assoc [ ("fact", fact_json fact); ("kind", `String "assert") ]
    | Update_fact fact ->
        `Assoc [ ("fact", fact_json fact); ("kind", `String "update") ]
    | Retract_fact fact_id ->
        `Assoc [ ("factId", `String fact_id); ("kind", `String "retract") ]

  let delta_receipt (session : session) changed delta_digest =
    let receipt_digest =
      digest_json
        (`Assoc
           [ ("changed", `Bool changed); ("deltaDigest", `String delta_digest);
             ("sessionDigest", `String session.session_digest) ])
    in
    { changed; delta_digest; receipt_digest }

  let invalidate_refraction fact_id (refraction : refraction_entry list) =
    List.filter
      (fun (entry : refraction_entry) -> not (List.mem fact_id entry.supports))
      refraction

  let external_delta context (delta : delta) (session : session) =
    if not (Run_safety.same_context context session.context) then
      Error (error context "Rete_UL session context differs", session, empty_partial)
    else
      let delta_digest = digest_json (delta_json delta) in
      let unchanged () = Ok (session, delta_receipt session false delta_digest) in
      let commit facts changed_id kinds =
        let refraction = invalidate_refraction changed_id session.refraction in
        match
          rebuild session ~facts ~refraction
            ~delta_digests:(session.delta_digests @ [ delta_digest ]) ~affected:kinds
        with
        | Error message -> Error (error context message, session, empty_partial)
        | Ok next -> Ok (next, delta_receipt next true delta_digest)
      in
      match delta with
      | Assert_fact fact ->
          begin match String_map.find_opt fact.fact_id session.facts with
          | Some current when String.equal current.fact_digest fact.fact_digest -> unchanged ()
          | Some _ ->
              Error
                (error context "assert target exists with different content", session,
                 empty_partial)
          | None ->
              commit (String_map.add fact.fact_id fact session.facts) fact.fact_id
                (String_set.singleton fact.fact_kind)
          end
      | Update_fact fact ->
          begin match String_map.find_opt fact.fact_id session.facts with
          | None -> Error (error context "update target does not exist", session, empty_partial)
          | Some current when String.equal current.fact_digest fact.fact_digest -> unchanged ()
          | Some current ->
              commit (String_map.add fact.fact_id fact session.facts) fact.fact_id
                (String_set.of_list [ current.fact_kind; fact.fact_kind ])
          end
      | Retract_fact fact_id ->
          begin match String_map.find_opt fact_id session.facts with
          | None -> Error (error context "retract target does not exist", session, empty_partial)
          | Some current ->
              commit (String_map.remove fact_id session.facts) fact_id
                (String_set.singleton current.fact_kind)
          end

  let assert_fact context (fact : fact) (session : session) =
    external_delta context (Assert_fact fact) session
  let update_fact context (fact : fact) (session : session) =
    external_delta context (Update_fact fact) session
  let retract_fact context ~fact_id (session : session) =
    external_delta context (Retract_fact fact_id) session

  let instantiate bindings (template : rhs_template) =
    let rec attrs result = function
      | [] -> make_fact ~fact_id:template.fact_id ~fact_kind:template.fact_kind
                ~attrs:(List.rev result)
      | (name, Literal value) :: rest -> attrs ((name, value) :: result) rest
      | (name, Variable variable) :: rest ->
          begin match List.assoc_opt variable bindings with
          | None -> Error ("unbound RHS variable: " ^ variable)
          | Some value -> attrs ((name, value) :: result) rest
          end
    in
    attrs [] template.attrs

  let apply_actions (activation : activation) (facts : fact String_map.t) =
    let rec apply facts changed kinds = function
      | [] -> Ok (facts, changed, kinds)
      | Block_rhs reason :: _ -> Error ("rule blocked: " ^ reason)
      | Assert_rhs template :: rest ->
          let* fact = instantiate activation.bindings template in
          begin match String_map.find_opt fact.fact_id facts with
          | None ->
              apply (String_map.add fact.fact_id fact facts)
                (String_set.add fact.fact_id changed)
                (String_set.add fact.fact_kind kinds) rest
          | Some old when String.equal old.fact_digest fact.fact_digest ->
              apply facts changed kinds rest
          | Some _ -> Error ("RHS assert target conflicts: " ^ fact.fact_id)
          end
      | Update_rhs template :: rest ->
          let* fact = instantiate activation.bindings template in
          begin match String_map.find_opt fact.fact_id facts with
          | None -> Error ("RHS update target missing: " ^ fact.fact_id)
          | Some old ->
              apply (String_map.add fact.fact_id fact facts)
                (String_set.add fact.fact_id changed)
                (String_set.add old.fact_kind (String_set.add fact.fact_kind kinds))
                rest
          end
      | Retract_rhs fact_id :: rest ->
          begin match String_map.find_opt fact_id facts with
          | None -> Error ("RHS retract target missing: " ^ fact_id)
          | Some old ->
              apply (String_map.remove fact_id facts)
                (String_set.add fact_id changed)
                (String_set.add old.fact_kind kinds) rest
          end
    in
    apply facts String_set.empty String_set.empty activation.rule.actions

  let add_trace (budgets : budgets) (entries : trace_entry list) truncated
      (activation : activation) outcome =
    if List.length entries >= budgets.max_trace_entries then (entries, true)
    else
      (entries
       @ [ { ordinal = List.length entries + 1; rule_id = activation.rule.rule_id;
             activation_digest = activation.activation_digest; outcome } ],
       truncated)

  let authority_json = function
    | Run_safety.Load_bearing_dispatch_gate ->
        `String "load-bearing-dispatch-gate"
    | Run_safety.Analysis_only -> `String "analysis-only"

  let rete_receipt_json (receipt : rete_receipt) =
    `Assoc
      [ ("authority", authority_json receipt.authority);
        ("contextDigest", `String receipt.context_digest);
        ("currentAtNs", `Intlit (Int64.to_string receipt.current_at_ns));
        ("currentHeadDigest", `String receipt.current_head_digest);
        ("emptyAgenda", `Bool receipt.empty_agenda);
        ("firingCount", `Int receipt.firing_count);
        ("fixedPoint", `Bool receipt.fixed_point);
        ("inputFactDigest", `String receipt.input_fact_digest);
        ("networkDigest", `String receipt.network_digest);
        ("outputFactDigest", `String receipt.output_fact_digest);
        ("sessionDigest", `String receipt.session_digest);
        ("traceDigest", `String receipt.trace_digest) ]

  let valid_digest value =
    String.length value = 64
    && String.for_all
         (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
         value

  let rete_receipt (context : Run_safety.gate_context) input_fact_digest
      (session : session) firing_count (trace : partial_trace) =
    let provisional =
      { authority = Run_safety.Load_bearing_dispatch_gate;
        context_digest = context.Run_safety.context_digest;
        current_head_digest = context.current_head_digest;
        current_at_ns = context.current_at_ns;
        network_digest = session.compiled.digest; input_fact_digest;
        session_digest = session.session_digest;
        fixed_point = session.agenda = []; empty_agenda = session.agenda = [];
        firing_count; output_fact_digest = facts_digest session.facts;
        trace_digest = trace.trace_digest; receipt_digest = "" }
    in
    { provisional with
      receipt_digest = digest_json (rete_receipt_json provisional) }

  let validate_receipt ~(context : Run_safety.gate_context)
      (receipt : rete_receipt) =
    let digests =
      [ receipt.context_digest; receipt.current_head_digest;
        receipt.network_digest; receipt.input_fact_digest;
        receipt.session_digest; receipt.output_fact_digest; receipt.trace_digest;
        receipt.receipt_digest ]
    in
    if
      receipt.authority = Run_safety.Load_bearing_dispatch_gate
      && String.equal receipt.context_digest context.context_digest
      && String.equal receipt.current_head_digest context.current_head_digest
      && Int64.equal receipt.current_at_ns context.current_at_ns
      && receipt.fixed_point && receipt.empty_agenda
      && receipt.firing_count >= 0
      && List.for_all valid_digest digests
      && String.equal receipt.receipt_digest
           (digest_json (rete_receipt_json receipt))
    then Ok ()
    else
      Error
        (Run_safety.make_gate_error context ~code:Run_safety.Invalid_receipt
           ~message:"Rete_UL receipt does not bind the exact context and result"
           ~rca_origin:Ops_capability.Evidence
           ~hazard_id:"HZ-T6-INTELLIGENCE-RECEIPT-01")

  let run_to_fixed_point context (session : session) =
    if not (Run_safety.same_context context session.context) then
      Error (error context "Rete_UL session context differs", session, empty_partial)
    else
      let input_fact_digest = facts_digest session.facts in
      let budgets = session.compiled.network.budgets in
      let rec loop current firing_count entries truncated =
        match current.agenda with
        | [] ->
            let trace = partial entries truncated in
            Ok
              (current,
               rete_receipt context input_fact_digest current firing_count trace)
        | _ :: _ when firing_count >= budgets.max_firings ->
            Error
              (error context "Rete_UL firing budget exhausted", current,
               partial entries truncated)
        | activation :: _ ->
            begin match apply_actions activation current.facts with
            | Error message ->
                let entries, truncated =
                  add_trace budgets entries truncated activation ("error:" ^ message)
                in
                Error (error context message, current, partial entries truncated)
            | Ok (facts, changed, kinds) ->
                let refraction =
                  { activation_digest = activation.activation_digest;
                    supports = activation.supports }
                  :: current.refraction
                  |> fun entries ->
                     String_set.fold invalidate_refraction changed entries
                in
                begin match
                  rebuild current ~facts ~refraction
                    ~delta_digests:current.delta_digests ~affected:kinds
                with
                | Error message ->
                    let entries, truncated =
                      add_trace budgets entries truncated activation ("error:" ^ message)
                    in
                    Error (error context message, current, partial entries truncated)
                | Ok next ->
                    let entries, truncated =
                      add_trace budgets entries truncated activation "fired"
                    in
                    loop next (firing_count + 1) entries truncated
                end
            end
      in
      loop session 0 [] false

  let replay context (compiled : compiled) (deltas : delta list) =
    match create context compiled with
    | Error issue ->
        let fallback =
          { context; compiled; facts = String_map.empty; memories = String_map.empty;
            agenda = []; refraction = []; delta_digests = []; link_count = 0;
            unlink_count = 0; session_digest = sha256 "invalid-replay-session" }
        in
        Error (issue, fallback, empty_partial)
    | Ok initial ->
        let rec apply session = function
          | [] -> run_to_fixed_point context session
          | Assert_fact fact :: rest ->
              begin match assert_fact context fact session with
              | Ok (next, _) -> apply next rest
              | Error failure -> Error failure
              end
          | Update_fact fact :: rest ->
              begin match update_fact context fact session with
              | Ok (next, _) -> apply next rest
              | Error failure -> Error failure
              end
          | Retract_fact fact_id :: rest ->
              begin match retract_fact context ~fact_id session with
              | Ok (next, _) -> apply next rest
              | Error failure -> Error failure
              end
        in
        apply initial deltas

  let static_outcome context (network : network) (facts : fact list) =
    let* compiled = compile context network in
    let* session = create context compiled in
    let rec insert session = function
      | [] -> Ok session
      | fact :: rest ->
          begin match assert_fact context fact session with
          | Ok (next, _) -> insert next rest
          | Error (issue, _, _) -> Error issue
          end
    in
    let* session = insert session facts in
    if
      List.exists
        (fun (activation : activation) ->
          List.exists (function Block_rhs _ -> true | _ -> false)
            activation.rule.actions)
        session.agenda
    then Ok Static_block else Ok Static_accept

  let dispatch_error context message =
    Error
      (Run_safety.make_gate_error context ~code:Run_safety.Invalid_receipt
         ~message ~rca_origin:Ops_capability.Evidence
         ~hazard_id:"HZ-T6-INTELLIGENCE-RECEIPT-01")

  let static_outcome_string = function
    | Static_accept -> "accept"
    | Static_block -> "block"

  let dispatch_receipt_json (receipt : dispatch_receipt) =
    `Assoc
      [ ("authority", authority_json receipt.authority);
        ("contextDigest", `String receipt.context_digest);
        ("currentAtNs", `Intlit (Int64.to_string receipt.current_at_ns));
        ("currentHeadDigest", `String receipt.current_head_digest);
        ("emptyAgenda", `Bool receipt.empty_agenda);
        ("fixedPoint", `Bool receipt.fixed_point);
        ("inputFactDigest", `String receipt.input_fact_digest);
        ("networkDigest", `String receipt.network_digest);
        ("reteReceiptDigest", `String receipt.rete_receipt_digest);
        ("staticOutcome", `String (static_outcome_string receipt.static_outcome)) ]

  let canonical_deltas context facts =
    let ids = List.map (fun (fact : fact) -> fact.fact_id) facts in
    if duplicates ids <> [] then
      dispatch_error context "exact Rete_UL dispatch facts contain duplicate ids"
    else
      facts
      |> List.sort (fun (left : fact) (right : fact) ->
             String.compare left.fact_id right.fact_id)
      |> List.map (fun fact -> Assert_fact fact)
      |> fun deltas -> Ok deltas

  let exact_rete_receipt context network facts =
    let* compiled = compile context network in
    let* deltas = canonical_deltas context facts in
    match replay context compiled deltas with
    | Ok (_, receipt) -> Ok receipt
    | Error (issue, _, _) -> Error issue

  let make_dispatch_receipt (context : Run_safety.gate_context)
      (rete : rete_receipt) outcome =
    let provisional =
      { authority = Run_safety.Load_bearing_dispatch_gate;
        context_digest = context.context_digest;
        current_head_digest = context.current_head_digest;
        current_at_ns = context.current_at_ns;
        network_digest = rete.network_digest;
        input_fact_digest = rete.input_fact_digest;
        static_outcome = outcome;
        fixed_point = rete.fixed_point;
        empty_agenda = rete.empty_agenda;
        rete_receipt_digest = rete.receipt_digest;
        receipt_digest = "" }
    in
    { provisional with
      receipt_digest = digest_json (dispatch_receipt_json provisional) }

  let admit_dispatch context ~network ~facts receipt =
    let* () = validate_receipt ~context receipt in
    let* exact = exact_rete_receipt context network facts in
    if exact <> receipt then
      dispatch_error context
        "Rete_UL receipt differs from the canonical network and fact replay"
    else
      let* outcome = static_outcome context network facts in
      match outcome with
      | Static_block ->
          dispatch_error context "Rete_UL static dispatch outcome is blocked"
      | Static_accept -> Ok (make_dispatch_receipt context exact outcome)

  let validate_dispatch ~context ~network ~facts receipt =
    let* exact_rete = exact_rete_receipt context network facts in
    let* expected = admit_dispatch context ~network ~facts exact_rete in
    if expected = receipt then Ok ()
    else
      dispatch_error context
        "Rete_UL dispatch receipt differs from exact recomputation"

  let hermes_value = function
    | Int value -> Hermes_rete.Value.Int value
    | String value -> Hermes_rete.Value.String value
    | Bool value -> Hermes_rete.Value.Bool value

  let hermes_pattern (pattern : pattern) : Hermes_rete.pattern =
    { pat_kind = pattern.fact_kind; bind_name = None;
      conds =
        List.map
          (function
            | Field_eq (field, value) ->
                Hermes_rete.FieldCmp (field, Hermes_rete.Eq, hermes_value value)
            | Bind (variable, field) -> Hermes_rete.VarBind (variable, field)
            | Join_eq (field, variable) ->
                Hermes_rete.VarCmp (field, Hermes_rete.Eq, variable))
          pattern.conditions }

  let hermes_rete_static_outcome (network : network) (facts : fact list) =
    if
      List.exists
        (fun (rule : rule) ->
          List.exists
            (function Assert_rhs _ | Update_rhs _ | Retract_rhs _ -> true
              | Block_rhs _ -> false)
            rule.actions)
        network.rules
    then Error "Hermes_rete differential oracle supports only static Block rules"
    else
      let wm = Hermes_rete.WM.create () in
      List.iter
        (fun (fact : fact) ->
          Hermes_rete.WM.insert wm fact.fact_kind
            (List.map (fun (name, value) -> (name, hermes_value value)) fact.attrs))
        facts;
      let rules : Hermes_rete.rule list =
        List.map
          (fun (rule : rule) ->
            { Hermes_rete.name = rule.rule_id;
              patterns = List.map hermes_pattern rule.patterns;
              action =
                (fun _ _ ->
                  match
                    List.find_map
                      (function Block_rhs reason -> Some reason | _ -> None)
                      rule.actions
                  with
                  | None -> Ok ()
                  | Some reason -> Error reason) })
          network.rules
      in
      match Hermes_rete.fire_rules wm rules with
      | Ok () -> Ok Static_accept
      | Error _ -> Ok Static_block

  let differential_oracle_authority = Run_safety.Analysis_only

  module For_test = struct
    type receipt_mutation =
      | Authority
      | Context_digest
      | Current_head_digest
      | Current_at_ns
      | Network_digest
      | Input_fact_digest
      | Session_digest
      | Output_fact_digest
      | Trace_digest
      | Fixed_point
      | Empty_agenda
      | Firing_count
      | Receipt_digest

    let mutate_digest value =
      if String.length value = 0 then "0"
      else
        let replacement = if Char.equal value.[0] '0' then '1' else '0' in
        String.mapi (fun index character ->
            if index = 0 then replacement else character) value

    let mutate_receipt (receipt : rete_receipt) = function
      | Authority -> { receipt with authority = Run_safety.Analysis_only }
      | Context_digest ->
          { receipt with context_digest = mutate_digest receipt.context_digest }
      | Current_head_digest ->
          { receipt with
            current_head_digest = mutate_digest receipt.current_head_digest }
      | Current_at_ns ->
          { receipt with current_at_ns = Int64.succ receipt.current_at_ns }
      | Network_digest ->
          { receipt with network_digest = mutate_digest receipt.network_digest }
      | Input_fact_digest ->
          { receipt with
            input_fact_digest = mutate_digest receipt.input_fact_digest }
      | Session_digest ->
          { receipt with session_digest = mutate_digest receipt.session_digest }
      | Output_fact_digest ->
          { receipt with
            output_fact_digest = mutate_digest receipt.output_fact_digest }
      | Trace_digest ->
          { receipt with trace_digest = mutate_digest receipt.trace_digest }
      | Fixed_point -> { receipt with fixed_point = not receipt.fixed_point }
      | Empty_agenda -> { receipt with empty_agenda = not receipt.empty_agenda }
      | Firing_count -> { receipt with firing_count = receipt.firing_count + 1 }
      | Receipt_digest ->
          { receipt with receipt_digest = mutate_digest receipt.receipt_digest }
  end
end

module Raven_matrix = struct
  type engine = Deterministic_mcda_v1
  type direction = Maximize | Minimize

  type budgets = {
    max_alternatives : int;
    max_criteria : int;
    max_cells : int;
    max_constraints : int;
    max_trace_entries : int;
    max_abs_value : int64;
  }

  type criterion = {
    criterion_id : string;
    direction : direction;
    weight_ppm : int;
    scale_min : int64;
    scale_max : int64;
  }

  type alternative = { alternative_id : string; prohibited : bool }
  type cell = {
    alternative_id : string;
    criterion_id : string;
    value : int64;
    evidence_digest : string;
  }

  type relation = At_least | At_most
  type hard_constraint = {
    constraint_id : string;
    alternative_id : string;
    criterion_id : string;
    relation : relation;
    threshold : int64;
    evidence_digest : string;
  }

  type selection_policy = Require_stable | Force_if_feasible of string
  type matrix = {
    matrix_id : string;
    criteria : criterion list;
    alternatives : alternative list;
    cells : cell list;
    constraints : hard_constraint list;
    tie_order : string list;
    selection_policy : selection_policy;
    min_sensitivity_ppm : int;
    budgets : budgets;
  }

  type contribution = {
    alternative_id : string;
    criterion_id : string;
    normalized_ppm : int;
    weighted_ppm : int;
    evidence_digest : string;
  }

  type ranked_alternative = {
    rank : int;
    alternative_id : string;
    score_ppm : int;
    dominated_by : string list;
  }

  type exclusion_reason = Prohibited | Constraint_failed of string list
  type exclusion = { alternative_id : string; reason : exclusion_reason }
  type receipt = {
    engine : engine;
    authority : Run_safety.authority;
    context_digest : string;
    matrix_digest : string;
    ranking : ranked_alternative list;
    contributions : contribution list;
    dominance : (string * string) list;
    exclusions : exclusion list;
    sensitivity_margin_ppm : int;
    stable : bool;
    selected_alternative : string;
    forced : bool;
    decision_trace : string list;
    trace_digest : string;
    receipt_digest : string;
  }

  module String_set = Set.Make (String)

  let ( let* ) value continuation =
    match value with Ok result -> continuation result | Error _ as error -> error

  let sha256 text = Digestif.SHA256.(to_hex (digest_string text))
  let digest_json json = sha256 (Yojson.Safe.to_string json)

  let error context message =
    Error
      (Run_safety.make_gate_error context ~code:Run_safety.Invalid_model ~message
         ~rca_origin:Ops_capability.Control
         ~hazard_id:"HZ-T6-INTELLIGENCE-RAVEN-01")

  let valid_digest value =
    String.length value = 64
    && String.for_all
         (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
         value

  let valid_id value =
    String.length value > 0
    && String.for_all
         (function
           | 'a' .. 'z' | '0' .. '9' | '.' | '_' | '-' -> true
           | _ -> false)
         value

  let unique values =
    List.length values = List.length (List.sort_uniq String.compare values)

  let int64_json value = `Intlit (Int64.to_string value)

  let direction_json = function
    | Maximize -> `String "maximize"
    | Minimize -> `String "minimize"

  let relation_json = function
    | At_least -> `String "at-least"
    | At_most -> `String "at-most"

  let criterion_json (value : criterion) =
    `Assoc
      [ ("criterionId", `String value.criterion_id);
        ("direction", direction_json value.direction);
        ("scaleMax", int64_json value.scale_max);
        ("scaleMin", int64_json value.scale_min);
        ("weightPpm", `Int value.weight_ppm) ]

  let alternative_json (value : alternative) =
    `Assoc
      [ ("alternativeId", `String value.alternative_id);
        ("prohibited", `Bool value.prohibited) ]

  let cell_json (value : cell) =
    `Assoc
      [ ("alternativeId", `String value.alternative_id);
        ("criterionId", `String value.criterion_id);
        ("evidenceDigest", `String value.evidence_digest);
        ("value", int64_json value.value) ]

  let constraint_json (value : hard_constraint) =
    `Assoc
      [ ("alternativeId", `String value.alternative_id);
        ("constraintId", `String value.constraint_id);
        ("criterionId", `String value.criterion_id);
        ("evidenceDigest", `String value.evidence_digest);
        ("relation", relation_json value.relation);
        ("threshold", int64_json value.threshold) ]

  let budgets_json (value : budgets) =
    `Assoc
      [ ("maxAbsValue", int64_json value.max_abs_value);
        ("maxAlternatives", `Int value.max_alternatives);
        ("maxCells", `Int value.max_cells);
        ("maxConstraints", `Int value.max_constraints);
        ("maxCriteria", `Int value.max_criteria);
        ("maxTraceEntries", `Int value.max_trace_entries) ]

  let selection_policy_json = function
    | Require_stable -> `Assoc [ ("kind", `String "require-stable") ]
    | Force_if_feasible alternative_id ->
        `Assoc
          [ ("alternativeId", `String alternative_id);
            ("kind", `String "force-if-feasible") ]

  let matrix_json (value : matrix) =
    let criteria =
      List.sort
        (fun (left : criterion) (right : criterion) ->
          String.compare left.criterion_id right.criterion_id)
        value.criteria
    in
    let alternatives =
      List.sort
        (fun (left : alternative) (right : alternative) ->
          String.compare left.alternative_id right.alternative_id)
        value.alternatives
    in
    let cells =
      List.sort
        (fun (left : cell) (right : cell) ->
          let alternative =
            String.compare left.alternative_id right.alternative_id
          in
          if alternative <> 0 then alternative
          else String.compare left.criterion_id right.criterion_id)
        value.cells
    in
    let constraints =
      List.sort
        (fun (left : hard_constraint) (right : hard_constraint) ->
          String.compare left.constraint_id right.constraint_id)
        value.constraints
    in
    `Assoc
      [ ("alternatives", `List (List.map alternative_json alternatives));
        ("budgets", budgets_json value.budgets);
        ("cells", `List (List.map cell_json cells));
        ("constraints", `List (List.map constraint_json constraints));
        ("criteria", `List (List.map criterion_json criteria));
        ("matrixId", `String value.matrix_id);
        ("minSensitivityPpm", `Int value.min_sensitivity_ppm);
        ("selectionPolicy", selection_policy_json value.selection_policy);
        ("tieOrder", `List (List.map (fun id -> `String id) value.tie_order)) ]

  let find_criterion (value : matrix) criterion_id =
    List.find_opt
      (fun (criterion : criterion) ->
        String.equal criterion.criterion_id criterion_id)
      value.criteria

  let find_cell (value : matrix) alternative_id criterion_id =
    List.find
      (fun (cell : cell) ->
        String.equal cell.alternative_id alternative_id
        && String.equal cell.criterion_id criterion_id)
      value.cells

  let validate_budgets context (value : matrix) =
    let limits = value.budgets in
    if
      Int64.compare limits.max_abs_value 0L <= 0
      || Int64.compare limits.max_abs_value 1_000_000_000_000L > 0
    then error context "Raven_matrix arithmetic bound must be positive and safe"
    else if
      limits.max_alternatives < 1 || limits.max_alternatives > 1_024
      || List.length value.alternatives > limits.max_alternatives
    then error context "Raven_matrix alternative budget exhausted"
    else if
      limits.max_criteria < 1 || limits.max_criteria > 256
      || List.length value.criteria > limits.max_criteria
    then error context "Raven_matrix criterion budget exhausted"
    else if
      limits.max_cells < 1 || limits.max_cells > 262_144
      || List.length value.cells > limits.max_cells
    then error context "Raven_matrix cell budget exhausted"
    else if
      limits.max_constraints < 0 || limits.max_constraints > 65_536
      || List.length value.constraints > limits.max_constraints
    then error context "Raven_matrix constraint budget exhausted"
    else if limits.max_trace_entries < 1 || limits.max_trace_entries > 4_096 then
      error context "Raven_matrix trace budget is invalid"
    else Ok ()

  let validate_id_sets context (value : matrix) =
    let criterion_ids =
      List.map (fun (item : criterion) -> item.criterion_id) value.criteria
    in
    let alternative_ids =
      List.map (fun (item : alternative) -> item.alternative_id) value.alternatives
    in
    let constraint_ids =
      List.map
        (fun (item : hard_constraint) -> item.constraint_id)
        value.constraints
    in
    if not (valid_id value.matrix_id) then
      error context "Raven_matrix identifier is invalid"
    else if List.exists (fun id -> not (valid_id id)) criterion_ids then
      error context "Raven_matrix criterion identifier is invalid"
    else if not (unique criterion_ids) then
      error context "Raven_matrix duplicate criterion identifier"
    else if List.exists (fun id -> not (valid_id id)) alternative_ids then
      error context "Raven_matrix alternative identifier is invalid"
    else if not (unique alternative_ids) then
      error context "Raven_matrix duplicate alternative identifier"
    else if List.exists (fun id -> not (valid_id id)) constraint_ids then
      error context "Raven_matrix constraint identifier is invalid"
    else if not (unique constraint_ids) then
      error context "Raven_matrix duplicate constraint identifier"
    else Ok ()

  let validate_weights context (value : matrix) =
    if value.criteria = [] then error context "Raven_matrix criteria are empty"
    else if
      List.exists
        (fun (criterion : criterion) -> criterion.weight_ppm <= 0)
        value.criteria
    then error context "Raven_matrix criterion weights must be strictly positive"
    else if
      List.exists
        (fun (criterion : criterion) -> criterion.weight_ppm > 1_000_000)
        value.criteria
    then error context "Raven_matrix criterion weights must total one million PPM"
    else
      let total =
        List.fold_left
          (fun total (criterion : criterion) -> total + criterion.weight_ppm)
          0 value.criteria
      in
      if total <> 1_000_000 then
        error context "Raven_matrix criterion weights must total one million PPM"
      else Ok ()

  let validate_tie_order context (value : matrix) =
    let expected =
      List.map (fun (item : alternative) -> item.alternative_id) value.alternatives
      |> List.sort String.compare
    in
    let observed = List.sort String.compare value.tie_order in
    if not (unique value.tie_order) || observed <> expected then
      error context "Raven_matrix tie order must be a duplicate-free total order"
    else Ok ()

  let validate_domains context (value : matrix) =
    let bound = value.budgets.max_abs_value in
    if
      List.exists
        (fun (criterion : criterion) ->
          Int64.compare criterion.scale_min criterion.scale_max >= 0
          || Int64.compare criterion.scale_min (Int64.neg bound) < 0
          || Int64.compare criterion.scale_max bound > 0)
        value.criteria
    then error context "Raven_matrix criterion scale domain is invalid"
    else Ok ()

  let validate_cells context (value : matrix) =
    let criterion_ids =
      value.criteria
      |> List.map (fun (item : criterion) -> item.criterion_id)
      |> String_set.of_list
    in
    let alternative_ids =
      value.alternatives
      |> List.map (fun (item : alternative) -> item.alternative_id)
      |> String_set.of_list
    in
    if
      List.exists
        (fun (cell : cell) ->
          not
            (String_set.mem cell.alternative_id alternative_ids
             && String_set.mem cell.criterion_id criterion_ids))
        value.cells
    then error context "Raven_matrix unknown cell reference"
    else if
      List.exists (fun (cell : cell) -> not (valid_digest cell.evidence_digest))
        value.cells
    then error context "Raven_matrix cell evidence digest is invalid"
    else
      let keys =
        List.map
          (fun (cell : cell) -> cell.alternative_id ^ "\000" ^ cell.criterion_id)
          value.cells
      in
      if not (unique keys) then error context "Raven_matrix duplicate cell"
      else
        let expected =
          List.length value.criteria * List.length value.alternatives
        in
        if List.length value.cells <> expected then
          error context "Raven_matrix requires a complete cell for every pair"
        else if
          List.exists
            (fun (cell : cell) ->
              match find_criterion value cell.criterion_id with
              | None -> true
              | Some criterion ->
                  Int64.compare cell.value criterion.scale_min < 0
                  || Int64.compare cell.value criterion.scale_max > 0)
            value.cells
        then error context "Raven_matrix cell value is outside criterion domain"
        else Ok ()

  let validate_constraints context (value : matrix) =
    let alternative_ids =
      value.alternatives
      |> List.map (fun (item : alternative) -> item.alternative_id)
      |> String_set.of_list
    in
    if
      List.exists
        (fun (constraint_ : hard_constraint) ->
          not (String_set.mem constraint_.alternative_id alternative_ids)
          || Option.is_none (find_criterion value constraint_.criterion_id))
        value.constraints
    then error context "Raven_matrix unknown constraint reference"
    else if
      List.exists
        (fun (constraint_ : hard_constraint) ->
          not (valid_digest constraint_.evidence_digest))
        value.constraints
    then error context "Raven_matrix constraint evidence digest is invalid"
    else if
      List.exists
        (fun (constraint_ : hard_constraint) ->
          match find_criterion value constraint_.criterion_id with
          | None -> true
          | Some criterion ->
              Int64.compare constraint_.threshold criterion.scale_min < 0
              || Int64.compare constraint_.threshold criterion.scale_max > 0)
        value.constraints
    then error context "Raven_matrix constraint value is outside criterion domain"
    else
      let pairs =
        value.constraints
        |> List.map (fun (constraint_ : hard_constraint) ->
               (constraint_.alternative_id, constraint_.criterion_id))
        |> List.sort_uniq compare
      in
      let contradictory =
        List.exists
          (fun (alternative_id, criterion_id) ->
            let related =
              List.filter
                (fun (constraint_ : hard_constraint) ->
                  String.equal constraint_.alternative_id alternative_id
                  && String.equal constraint_.criterion_id criterion_id)
                value.constraints
            in
            let lowers, uppers =
              List.fold_left
                (fun (lowers, uppers) (constraint_ : hard_constraint) ->
                  match constraint_.relation with
                  | At_least -> (constraint_.threshold :: lowers, uppers)
                  | At_most -> (lowers, constraint_.threshold :: uppers))
                ([], []) related
            in
            match lowers, uppers with
            | _ :: _, _ :: _ ->
                let lower = List.fold_left Int64.max Int64.min_int lowers in
                let upper = List.fold_left Int64.min Int64.max_int uppers in
                Int64.compare lower upper > 0
            | _, _ -> false)
          pairs
      in
      if contradictory then error context "Raven_matrix contradictory constraints"
      else Ok ()

  let validate context (value : matrix) =
    let* () = validate_budgets context value in
    let* () = validate_id_sets context value in
    let* () = validate_weights context value in
    let* () = validate_tie_order context value in
    let* () = validate_domains context value in
    let* () = validate_cells context value in
    let* () = validate_constraints context value in
    if value.alternatives = [] then error context "Raven_matrix alternatives are empty"
    else if
      value.min_sensitivity_ppm < 0 || value.min_sensitivity_ppm > 1_000_000
    then error context "Raven_matrix sensitivity threshold is outside PPM range"
    else Ok ()

  let normalized_ppm (criterion : criterion) value =
    let span = Int64.sub criterion.scale_max criterion.scale_min in
    let distance =
      match criterion.direction with
      | Maximize -> Int64.sub value criterion.scale_min
      | Minimize -> Int64.sub criterion.scale_max value
    in
    Int64.div (Int64.mul distance 1_000_000L) span |> Int64.to_int

  let contribution_of (value : matrix) alternative_id
      (criterion : criterion) =
    let cell = find_cell value alternative_id criterion.criterion_id in
    let normalized_ppm = normalized_ppm criterion cell.value in
    let weighted_ppm =
      Int64.div
        (Int64.mul (Int64.of_int normalized_ppm)
           (Int64.of_int criterion.weight_ppm))
        1_000_000L
      |> Int64.to_int
    in
    { alternative_id; criterion_id = criterion.criterion_id; normalized_ppm;
      weighted_ppm; evidence_digest = cell.evidence_digest }

  let constraint_failures (value : matrix) alternative_id =
    value.constraints
    |> List.filter_map (fun (constraint_ : hard_constraint) ->
           if not (String.equal constraint_.alternative_id alternative_id) then None
           else
             let cell =
               find_cell value alternative_id constraint_.criterion_id
             in
             let satisfied =
               match constraint_.relation with
               | At_least -> Int64.compare cell.value constraint_.threshold >= 0
               | At_most -> Int64.compare cell.value constraint_.threshold <= 0
             in
             if satisfied then None else Some constraint_.constraint_id)
    |> List.sort String.compare

  let tie_position (value : matrix) alternative_id =
    let rec find position = function
      | [] -> max_int
      | current :: rest ->
          if String.equal current alternative_id then position
          else find (position + 1) rest
    in
    find 0 value.tie_order

  let better_or_equal (value : matrix) left_id right_id =
    List.for_all
      (fun (criterion : criterion) ->
        let left = (find_cell value left_id criterion.criterion_id).value in
        let right = (find_cell value right_id criterion.criterion_id).value in
        match criterion.direction with
        | Maximize -> Int64.compare left right >= 0
        | Minimize -> Int64.compare left right <= 0)
      value.criteria

  let strictly_better (value : matrix) left_id right_id =
    List.exists
      (fun (criterion : criterion) ->
        let left = (find_cell value left_id criterion.criterion_id).value in
        let right = (find_cell value right_id criterion.criterion_id).value in
        match criterion.direction with
        | Maximize -> Int64.compare left right > 0
        | Minimize -> Int64.compare left right < 0)
      value.criteria

  let ranked_json (row : ranked_alternative) =
    `Assoc
      [ ("alternativeId", `String row.alternative_id);
        ("dominatedBy", `List (List.map (fun id -> `String id) row.dominated_by));
        ("rank", `Int row.rank); ("scorePpm", `Int row.score_ppm) ]

  let contribution_json (row : contribution) =
    `Assoc
      [ ("alternativeId", `String row.alternative_id);
        ("criterionId", `String row.criterion_id);
        ("evidenceDigest", `String row.evidence_digest);
        ("normalizedPpm", `Int row.normalized_ppm);
        ("weightedPpm", `Int row.weighted_ppm) ]

  let exclusion_json (row : exclusion) =
    let reason =
      match row.reason with
      | Prohibited -> `Assoc [ ("kind", `String "prohibited") ]
      | Constraint_failed ids ->
          `Assoc
            [ ("constraintIds", `List (List.map (fun id -> `String id) ids));
              ("kind", `String "constraint-failed") ]
    in
    `Assoc
      [ ("alternativeId", `String row.alternative_id); ("reason", reason) ]

  let decide context (value : matrix) =
    let* () = validate context value in
    let matrix_digest = digest_json (matrix_json value) in
    let exclusions =
      value.alternatives
      |> List.filter_map (fun (alternative : alternative) ->
             if alternative.prohibited then
               Some { alternative_id = alternative.alternative_id; reason = Prohibited }
             else
               match constraint_failures value alternative.alternative_id with
               | [] -> None
               | failures ->
                   Some
                     { alternative_id = alternative.alternative_id;
                       reason = Constraint_failed failures })
      |> List.sort (fun (left : exclusion) (right : exclusion) ->
             String.compare left.alternative_id right.alternative_id)
    in
    let excluded =
      exclusions
      |> List.map (fun (row : exclusion) -> row.alternative_id)
      |> String_set.of_list
    in
    let feasible =
      value.alternatives
      |> List.filter (fun (alternative : alternative) ->
             not (String_set.mem alternative.alternative_id excluded))
      |> List.sort (fun (left : alternative) (right : alternative) ->
             String.compare left.alternative_id right.alternative_id)
    in
    if feasible = [] then error context "Raven_matrix has no feasible alternative"
    else
      let contributions =
        feasible
        |> List.concat_map (fun (alternative : alternative) ->
               value.criteria
               |> List.map (contribution_of value alternative.alternative_id))
        |> List.sort (fun (left : contribution) (right : contribution) ->
               let alternative =
                 String.compare left.alternative_id right.alternative_id
               in
               if alternative <> 0 then alternative
               else String.compare left.criterion_id right.criterion_id)
      in
      let score alternative_id =
        contributions
        |> List.filter (fun (row : contribution) ->
               String.equal row.alternative_id alternative_id)
        |> List.fold_left
             (fun total (row : contribution) -> total + row.weighted_ppm) 0
      in
      let dominance =
        feasible
        |> List.concat_map (fun (left : alternative) ->
               feasible
               |> List.filter_map (fun (right : alternative) ->
                      if
                        not (String.equal left.alternative_id right.alternative_id)
                        && better_or_equal value left.alternative_id
                             right.alternative_id
                        && strictly_better value left.alternative_id
                             right.alternative_id
                      then Some (left.alternative_id, right.alternative_id)
                      else None))
        |> List.sort compare
      in
      let ranked_ids =
        feasible
        |> List.map (fun (alternative : alternative) -> alternative.alternative_id)
        |> List.sort (fun left right ->
               let by_score = Int.compare (score right) (score left) in
               if by_score <> 0 then by_score
               else Int.compare (tie_position value left) (tie_position value right))
      in
      let ranking =
        List.mapi
          (fun index alternative_id ->
            let dominated_by =
              dominance
              |> List.filter_map (fun (left, right) ->
                     if String.equal right alternative_id then Some left else None)
            in
            { rank = index + 1; alternative_id; score_ppm = score alternative_id;
              dominated_by })
          ranked_ids
      in
      let sensitivity_margin_ppm =
        match ranking with
        | first :: second :: _ -> first.score_ppm - second.score_ppm
        | [ _ ] -> 1_000_000
        | [] -> 0
      in
      let stable = sensitivity_margin_ppm >= value.min_sensitivity_ppm in
      let* selected_alternative, forced =
        match value.selection_policy with
        | Require_stable ->
            if not stable then
              error context "Raven_matrix sensitivity margin is below threshold"
            else
              begin match ranking with
              | first :: _ -> Ok (first.alternative_id, false)
              | [] -> error context "Raven_matrix has no feasible alternative"
              end
        | Force_if_feasible alternative_id ->
            if
              not
                (List.exists
                   (fun (candidate : alternative) ->
                     String.equal candidate.alternative_id alternative_id)
                   feasible)
            then error context "Raven_matrix forced selection is not feasible"
            else Ok (alternative_id, true)
      in
      let decision_trace =
        [ "matrix:" ^ matrix_digest ]
        @ List.map
            (fun (alternative : alternative) ->
              "admitted:" ^ alternative.alternative_id)
            feasible
        @ List.map
            (fun (row : exclusion) -> "excluded:" ^ row.alternative_id)
            exclusions
        @ List.map
            (fun (row : ranked_alternative) ->
              Printf.sprintf "rank:%d:%s:%d" row.rank row.alternative_id
                row.score_ppm)
            ranking
        @ [ "selected:" ^ selected_alternative;
            "sensitivity:" ^ string_of_int sensitivity_margin_ppm ]
      in
      if List.length decision_trace > value.budgets.max_trace_entries then
        error context "Raven_matrix trace budget exhausted"
      else
        let trace_digest =
          decision_trace
          |> List.map (fun row -> `String row)
          |> fun rows -> digest_json (`List rows)
        in
        let receipt_json =
          `Assoc
            [ ("authority", `String "load-bearing-dispatch-gate");
              ("contextDigest", `String context.Run_safety.context_digest);
              ("contributions", `List (List.map contribution_json contributions));
              ("dominance",
               `List
                 (List.map
                    (fun (left, right) ->
                      `Assoc
                        [ ("dominates", `String left);
                          ("dominated", `String right) ])
                    dominance));
              ("engine", `String "deterministic-mcda-v1");
              ("exclusions", `List (List.map exclusion_json exclusions));
              ("forced", `Bool forced);
              ("matrixDigest", `String matrix_digest);
              ("ranking", `List (List.map ranked_json ranking));
              ("selectedAlternative", `String selected_alternative);
              ("sensitivityMarginPpm", `Int sensitivity_margin_ppm);
              ("stable", `Bool stable); ("traceDigest", `String trace_digest) ]
        in
        Ok
          { engine = Deterministic_mcda_v1;
            authority = Run_safety.Load_bearing_dispatch_gate;
            context_digest = context.context_digest; matrix_digest; ranking;
            contributions; dominance; exclusions; sensitivity_margin_ppm; stable;
            selected_alternative; forced; decision_trace; trace_digest;
            receipt_digest = digest_json receipt_json }

  let validate_receipt ~context ~matrix receipt =
    match decide context matrix with
    | Error issue -> Error issue
    | Ok expected when expected = receipt -> Ok ()
    | Ok _ ->
        Error
          (Run_safety.make_gate_error context ~code:Run_safety.Invalid_receipt
             ~message:
               "Raven_matrix receipt differs from the recomputed exact decision"
             ~rca_origin:Ops_capability.Evidence
             ~hazard_id:"HZ-T6-INTELLIGENCE-RECEIPT-01")
end
