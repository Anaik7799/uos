type engine = Ruliad | Stan_model | Z3

let gate = function
  | Ruliad -> Run_safety.Ruliad
  | Stan_model -> Run_safety.Stan_model
  | Z3 -> Run_safety.Z3

let authority engine = Run_safety.authority_of_gate (gate engine)

let unavailable_receipt context ~engine ~reason =
  match engine with
  | Ruliad -> Run_safety.ruliad_unavailable_receipt context ~reason
  | Stan_model -> Run_safety.stan_unavailable_receipt context ~reason
  | Z3 -> Run_safety.z3_unavailable_receipt context ~reason

let sha256 bytes =
  bytes |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let frame value = Printf.sprintf "%d:%s" (String.length value) value
let digest_fields fields = sha256 (String.concat "" (List.map frame fields))

let ( let* ) result continue =
  match result with Ok value -> continue value | Error _ as error -> error

let valid_digest value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let canonical_digest = valid_digest

let valid_identifier value =
  let trimmed = String.trim value in
  value = trimmed && value <> ""
  && String.for_all
       (function '\000' .. '\032' | '\127' -> false | _ -> true)
       value

let float_string value = Printf.sprintf "%.17g" value

let analysis_error context ~code ~message ~rca_origin ~hazard_id =
  Run_safety.make_gate_error context ~code ~message ~rca_origin ~hazard_id

module Ruliad = struct
  module String_set = Set.Make (String)

  type state = { stable_id : string; evidence_digest : string }
  type transition = {
    stable_id : string;
    from_state_id : string;
    to_state_id : string;
    move_digest : string;
  }
  type system = {
    initial_state_id : string;
    states : state list;
    transitions : transition list;
    system_digest : string;
  }
  type bounds = {
    max_states : int;
    max_edges : int;
    max_depth : int;
    max_paths : int64;
  }
  type graph = {
    states : state list;
    transitions : transition list;
    terminal_state_ids : string list;
    state_count : int;
    edge_count : int;
    path_count : int64;
    max_depth : int;
    confluent : bool;
    graph_digest : string;
  }
  type unavailable_reason =
    | State_cap
    | Edge_cap
    | Depth_cap
    | Path_cap
    | Cyclic_relation
  type outcome = Completed of graph | Unavailable of unavailable_reason * graph
  type receipt = {
    authority : Run_safety.authority;
    context_digest : string;
    current_head_digest : string;
    current_at_ns : int64;
    system_digest : string;
    bounds_digest : string;
    outcome : outcome;
    outcome_digest : string;
    receipt_digest : string;
  }

  let compare_state (left : state) (right : state) =
    String.compare left.stable_id right.stable_id

  let compare_transition (left : transition) (right : transition) =
    String.compare left.stable_id right.stable_id

  let state_fields (state : state) =
    [ state.stable_id; state.evidence_digest ]

  let transition_fields (transition : transition) =
    [ transition.stable_id; transition.from_state_id; transition.to_state_id;
      transition.move_digest ]

  let system_digest ~initial_state_id ~states ~transitions =
    digest_fields
      ([ "run-analysis-ruliad-system-v1"; initial_state_id ]
       @ List.concat_map state_fields states
       @ List.concat_map transition_fields transitions)

  let duplicate_values values =
    let rec loop previous duplicates = function
      | [] -> List.rev duplicates
      | value :: rest ->
          let duplicates =
            match previous with
            | Some prior when String.equal prior value -> value :: duplicates
            | Some _ | None -> duplicates
          in
          loop (Some value) duplicates rest
    in
    loop None [] (List.sort String.compare values)

  let make_system ~initial_state_id ~states ~transitions =
    let states = List.sort compare_state states in
    let transitions = List.sort compare_transition transitions in
    let state_ids = List.map (fun (state : state) -> state.stable_id) states in
    let transition_ids =
      List.map (fun (transition : transition) -> transition.stable_id) transitions
    in
    let state_set =
      List.fold_left (fun set id -> String_set.add id set) String_set.empty
        state_ids
    in
    let errors = ref [] in
    let issue message = errors := message :: !errors in
    if not (valid_identifier initial_state_id) then
      issue "Ruliad initial state id is invalid";
    if states = [] then issue "Ruliad system has no states";
    List.iter
      (fun (state : state) ->
        if not (valid_identifier state.stable_id) then
          issue ("invalid Ruliad state id: " ^ state.stable_id);
        if not (valid_digest state.evidence_digest) then
          issue ("invalid Ruliad state evidence digest: " ^ state.stable_id))
      states;
    List.iter
      (fun duplicate -> issue ("duplicate Ruliad state id: " ^ duplicate))
      (duplicate_values state_ids);
    if not (String_set.mem initial_state_id state_set) then
      issue "Ruliad initial state does not resolve";
    List.iter
      (fun (transition : transition) ->
        if not (valid_identifier transition.stable_id) then
          issue ("invalid Ruliad transition id: " ^ transition.stable_id);
        if not (valid_digest transition.move_digest) then
          issue ("invalid Ruliad move digest: " ^ transition.stable_id);
        if not (String_set.mem transition.from_state_id state_set) then
          issue ("unknown Ruliad transition source: " ^ transition.from_state_id);
        if not (String_set.mem transition.to_state_id state_set) then
          issue ("unknown Ruliad transition target: " ^ transition.to_state_id))
      transitions;
    List.iter
      (fun duplicate -> issue ("duplicate Ruliad transition id: " ^ duplicate))
      (duplicate_values transition_ids);
    match List.rev !errors with
    | _ :: _ as errors -> Error errors
    | [] ->
        Ok
          { initial_state_id; states; transitions;
            system_digest =
              system_digest ~initial_state_id ~states ~transitions }

  let bounds_digest bounds =
    digest_fields
      [ "run-analysis-ruliad-bounds-v1"; string_of_int bounds.max_states;
        string_of_int bounds.max_edges; string_of_int bounds.max_depth;
        Int64.to_string bounds.max_paths ]

  let reason_name = function
    | State_cap -> "state-cap"
    | Edge_cap -> "edge-cap"
    | Depth_cap -> "depth-cap"
    | Path_cap -> "path-cap"
    | Cyclic_relation -> "cyclic-relation"

  let graph_digest states transitions terminal_state_ids state_count edge_count
      path_count max_depth confluent =
    digest_fields
      ([ "run-analysis-ruliad-graph-v1"; string_of_int state_count;
         string_of_int edge_count; Int64.to_string path_count;
         string_of_int max_depth; string_of_bool confluent ]
       @ List.concat_map state_fields states
       @ List.concat_map transition_fields transitions
       @ terminal_state_ids)

  let make_graph (system : system) seen_depth expanded transitions ~path_count
      ~confluent =
    let states =
      system.states
      |> List.filter (fun (state : state) -> Hashtbl.mem seen_depth state.stable_id)
    in
    let transitions = List.sort compare_transition transitions in
    let terminal_state_ids =
      states
      |> List.filter_map (fun (state : state) ->
             if String_set.mem state.stable_id expanded
                && not
                     (List.exists
                        (fun (transition : transition) ->
                          String.equal transition.from_state_id state.stable_id)
                        system.transitions)
             then Some state.stable_id else None)
      |> List.sort String.compare
    in
    let max_depth =
      Hashtbl.fold (fun _ depth maximum -> max depth maximum) seen_depth 0
    in
    let state_count = List.length states in
    let edge_count = List.length transitions in
    let graph_digest =
      graph_digest states transitions terminal_state_ids state_count edge_count
        path_count max_depth confluent
    in
    { states; transitions; terminal_state_ids; state_count; edge_count;
      path_count; max_depth; confluent; graph_digest }

  let outcome_digest = function
    | Completed graph ->
        digest_fields [ "run-analysis-ruliad-outcome-v1"; "completed";
                        graph.graph_digest ]
    | Unavailable (reason, graph) ->
        digest_fields
          [ "run-analysis-ruliad-outcome-v1"; "unavailable";
            reason_name reason; graph.graph_digest ]

  let receipt_digest (receipt : receipt) =
    digest_fields
      [ "run-analysis-ruliad-receipt-v1"; "analysis-only";
        receipt.context_digest; receipt.current_head_digest;
        Int64.to_string receipt.current_at_ns; receipt.system_digest;
        receipt.bounds_digest; receipt.outcome_digest ]

  let make_receipt (context : Run_safety.gate_context) (system : system)
      (bounds : bounds) (outcome : outcome) =
    let outcome_digest = outcome_digest outcome in
    let provisional =
      { authority = Run_safety.Analysis_only;
        context_digest = context.context_digest;
        current_head_digest = context.current_head_digest;
        current_at_ns = context.current_at_ns;
        system_digest = system.system_digest;
        bounds_digest = bounds_digest bounds; outcome; outcome_digest;
        receipt_digest = "" }
    in
    { provisional with receipt_digest = receipt_digest provisional }

  let adjacency (system : system) state_id =
    List.filter
      (fun (transition : transition) ->
        String.equal transition.from_state_id state_id)
      system.transitions

  let analyze (context : Run_safety.gate_context) ~bounds (system : system) =
    if bounds.max_states <= 0 || bounds.max_edges <= 0 || bounds.max_depth < 0
       || bounds.max_paths <= 0L
    then
      Error
        (analysis_error context ~code:Run_safety.Invalid_model
           ~message:"Ruliad bounds must be positive and depth nonnegative"
           ~rca_origin:Ops_capability.Control ~hazard_id:"HZ-T6-RULIAD-01")
    else
      let seen_depth = Hashtbl.create (min bounds.max_states 256) in
      let queue = Queue.create () in
      let expanded = ref String_set.empty in
      let accepted_transitions = ref [] in
      let unavailable = ref None in
      Hashtbl.add seen_depth system.initial_state_id 0;
      Queue.add system.initial_state_id queue;
      while not (Queue.is_empty queue) && !unavailable = None do
        let state_id = Queue.pop queue in
        let depth = Hashtbl.find seen_depth state_id in
        let outgoing = adjacency system state_id in
        let rec admit = function
          | [] -> expanded := String_set.add state_id !expanded
          | _ when !unavailable <> None -> ()
          | transition :: rest ->
              if List.length !accepted_transitions >= bounds.max_edges then
                unavailable := Some Edge_cap
              else if depth + 1 > bounds.max_depth then
                unavailable := Some Depth_cap
              else
                let target_known = Hashtbl.mem seen_depth transition.to_state_id in
                if not target_known && Hashtbl.length seen_depth >= bounds.max_states
                then unavailable := Some State_cap
                else begin
                  accepted_transitions := transition :: !accepted_transitions;
                  if not target_known then begin
                    Hashtbl.add seen_depth transition.to_state_id (depth + 1);
                    Queue.add transition.to_state_id queue
                  end;
                  admit rest
                end
        in
        admit outgoing
      done;
      match !unavailable with
      | Some reason ->
          let graph =
            make_graph system seen_depth !expanded !accepted_transitions
              ~path_count:0L ~confluent:false
          in
          Ok (make_receipt context system bounds (Unavailable (reason, graph)))
      | None ->
          let color = Hashtbl.create (Hashtbl.length seen_depth) in
          let paths = Hashtbl.create (Hashtbl.length seen_depth) in
          let rec walk state_id =
            match Hashtbl.find_opt color state_id with
            | Some `Active -> Error `Cycle
            | Some `Done -> Ok (Hashtbl.find paths state_id)
            | None ->
                Hashtbl.add color state_id `Active;
                let outgoing = adjacency system state_id in
                let rec sum total = function
                  | [] -> Ok (if outgoing = [] then 1L else total)
                  | transition :: rest ->
                      let* child = walk transition.to_state_id in
                      if child > Int64.sub bounds.max_paths total then
                        Error `Path_cap
                      else sum (Int64.add total child) rest
                in
                let* total = sum 0L outgoing in
                Hashtbl.replace color state_id `Done;
                Hashtbl.replace paths state_id total;
                Ok total
          in
          begin match walk system.initial_state_id with
          | Error `Cycle ->
              let graph =
                make_graph system seen_depth !expanded !accepted_transitions
                  ~path_count:0L ~confluent:false
              in
              Ok
                (make_receipt context system bounds
                   (Unavailable (Cyclic_relation, graph)))
          | Error `Path_cap ->
              let graph =
                make_graph system seen_depth !expanded !accepted_transitions
                  ~path_count:bounds.max_paths ~confluent:false
              in
              Ok
                (make_receipt context system bounds
                   (Unavailable (Path_cap, graph)))
          | Ok path_count ->
              let graph_without_confluence =
                make_graph system seen_depth !expanded !accepted_transitions
                  ~path_count ~confluent:false
              in
              let confluent =
                List.length graph_without_confluence.terminal_state_ids = 1
              in
              let graph =
                make_graph system seen_depth !expanded !accepted_transitions
                  ~path_count ~confluent
              in
              Ok (make_receipt context system bounds (Completed graph))
          end

  let validate_graph (graph : graph) =
    graph.state_count = List.length graph.states
    && graph.edge_count = List.length graph.transitions
    && graph.max_depth >= 0 && graph.path_count >= 0L
    && valid_digest graph.graph_digest
    && String.equal graph.graph_digest
         (graph_digest graph.states graph.transitions graph.terminal_state_ids
            graph.state_count graph.edge_count graph.path_count graph.max_depth
            graph.confluent)

  let validate_receipt ~(context : Run_safety.gate_context) (receipt : receipt) =
    let outcome_graph =
      match receipt.outcome with
      | Completed graph | Unavailable (_, graph) -> graph
    in
    if not (String.equal context.context_digest receipt.context_digest
            && String.equal context.current_head_digest receipt.current_head_digest
            && context.current_at_ns = receipt.current_at_ns)
    then
      Error
        (analysis_error context ~code:Run_safety.Context_mismatch
           ~message:"Ruliad receipt context mismatch"
           ~rca_origin:Ops_capability.Control ~hazard_id:"HZ-T6-RULIAD-01")
    else if receipt.authority <> Run_safety.Analysis_only
            || not (valid_digest receipt.system_digest)
            || not (valid_digest receipt.bounds_digest)
            || not (validate_graph outcome_graph)
            || not
                 (String.equal receipt.outcome_digest
                    (outcome_digest receipt.outcome))
            || not
                 (String.equal receipt.receipt_digest
                    (receipt_digest receipt))
    then
      Error
        (analysis_error context ~code:Run_safety.Invalid_receipt
           ~message:"Ruliad receipt digest or authority is invalid"
           ~rca_origin:Ops_capability.Evidence ~hazard_id:"HZ-T6-RULIAD-01")
    else Ok ()

  let validate_exact ~context ~system ~bounds receipt =
    match validate_receipt ~context receipt with
    | Error _ as error -> error
    | Ok () ->
        begin match analyze context ~bounds system with
        | Error _ as error -> error
        | Ok expected ->
            match expected.outcome, receipt.outcome with
            | Completed _, Completed _
              when expected.authority = Run_safety.Analysis_only
                   && receipt.authority = Run_safety.Analysis_only
                   && expected = receipt ->
                Ok ()
            | _ ->
                Error
                  (analysis_error context ~code:Run_safety.Invalid_receipt
                     ~message:
                       "Ruliad receipt does not exactly match the completed analysis for the supplied system and bounds"
                     ~rca_origin:Ops_capability.Evidence
                     ~hazard_id:"HZ-T6-RULIAD-01")
        end
end

type ruliad_receipt = Ruliad.receipt

module Stan_model = struct
  type verdict = Passed | Failed
  type observation = {
    scenario_id : string;
    family_id : string;
    sequence : int64;
    verdict : verdict;
    evidence_digest : string;
    observation_digest : string;
  }
  type input = {
    prior_alpha : float;
    prior_beta : float;
    all_families : string list;
    observations : observation list;
    input_digest : string;
  }
  type model_kind = Beta_binomial_analytic_moment_band_v1
  type family_summary = {
    family_id : string;
    scenario_count : int;
    passing_count : int;
    posterior_alpha : float;
    posterior_beta : float;
    mean : float;
    variance : float;
    moment_band_low : float;
    moment_band_high : float;
    latest_observation_digests : string list;
    summary_digest : string;
  }
  type receipt = {
    model : model_kind;
    authority : Run_safety.authority;
    context_digest : string;
    current_head_digest : string;
    current_at_ns : int64;
    input_digest : string;
    model_digest : string;
    summaries : family_summary list;
    unmeasured_families : string list;
    coverage_complete : bool;
    result_digest : string;
    receipt_digest : string;
  }

  let verdict_name = function Passed -> "passed" | Failed -> "failed"

  let observation_digest ~scenario_id ~family_id ~sequence ~verdict
      ~evidence_digest =
    digest_fields
      [ "run-analysis-stan-observation-v1"; scenario_id; family_id;
        Int64.to_string sequence; verdict_name verdict; evidence_digest ]

  let make_observation ~scenario_id ~family_id ~sequence ~verdict
      ~evidence_digest =
    let errors = ref [] in
    if not (valid_identifier scenario_id) then
      errors := "Stan scenario id is invalid" :: !errors;
    if not (valid_identifier family_id) then
      errors := "Stan family id is invalid" :: !errors;
    if sequence < 0L then errors := "Stan sequence is negative" :: !errors;
    if not (valid_digest evidence_digest) then
      errors := "Stan evidence digest is not lowercase SHA-256" :: !errors;
    match List.rev !errors with
    | _ :: _ as errors -> Error errors
    | [] ->
        let observation_digest =
          observation_digest ~scenario_id ~family_id ~sequence ~verdict
            ~evidence_digest
        in
        Ok
          { scenario_id; family_id; sequence; verdict; evidence_digest;
            observation_digest }

  let compare_observation (left : observation) (right : observation) =
    let by_scenario = String.compare left.scenario_id right.scenario_id in
    if by_scenario <> 0 then by_scenario
    else
      let by_sequence = Int64.compare left.sequence right.sequence in
      if by_sequence <> 0 then by_sequence
      else String.compare left.observation_digest right.observation_digest

  let duplicate_values values =
    let rec loop prior duplicates = function
      | [] -> List.rev duplicates
      | value :: rest ->
          let duplicates =
            match prior with
            | Some previous when String.equal previous value -> value :: duplicates
            | Some _ | None -> duplicates
          in
          loop (Some value) duplicates rest
    in
    loop None [] (List.sort String.compare values)

  let observation_fields (observation : observation) =
    [ observation.scenario_id; observation.family_id;
      Int64.to_string observation.sequence; verdict_name observation.verdict;
      observation.evidence_digest; observation.observation_digest ]

  let input_digest ~prior_alpha ~prior_beta ~all_families ~observations =
    digest_fields
      ([ "run-analysis-stan-input-v1"; float_string prior_alpha;
         float_string prior_beta ]
       @ all_families @ List.concat_map observation_fields observations)

  let make_input ~prior_alpha ~prior_beta ~all_families ~observations =
    let all_families = List.sort String.compare all_families in
    let observations = List.sort compare_observation observations in
    let errors = ref [] in
    let issue message = errors := message :: !errors in
    if not (Float.is_finite prior_alpha && prior_alpha > 0.0) then
      issue "Stan prior alpha must be finite and positive";
    if not (Float.is_finite prior_beta && prior_beta > 0.0) then
      issue "Stan prior beta must be finite and positive";
    if all_families = [] then issue "Stan population has no families";
    List.iter
      (fun family ->
        if not (valid_identifier family) then
          issue ("invalid Stan family id: " ^ family))
      all_families;
    List.iter
      (fun duplicate -> issue ("duplicate Stan family id: " ^ duplicate))
      (duplicate_values all_families);
    let family_set =
      List.fold_left (fun set family -> family :: set) [] all_families
    in
    let scenario_family = Hashtbl.create (List.length observations) in
    let scenario_sequences = Hashtbl.create (List.length observations) in
    List.iter
      (fun (observation : observation) ->
        if not (List.mem observation.family_id family_set) then
          issue ("unknown Stan observation family: " ^ observation.family_id);
        if not
             (String.equal observation.observation_digest
                (observation_digest ~scenario_id:observation.scenario_id
                   ~family_id:observation.family_id ~sequence:observation.sequence
                   ~verdict:observation.verdict
                   ~evidence_digest:observation.evidence_digest))
        then issue ("Stan observation digest mismatch: " ^ observation.scenario_id);
        begin match Hashtbl.find_opt scenario_family observation.scenario_id with
        | Some family when not (String.equal family observation.family_id) ->
            issue
              ("Stan scenario appears in multiple families: "
               ^ observation.scenario_id)
        | Some _ -> ()
        | None -> Hashtbl.add scenario_family observation.scenario_id observation.family_id
        end;
        let key =
          observation.scenario_id ^ "\000" ^ Int64.to_string observation.sequence
        in
        if Hashtbl.mem scenario_sequences key then
          issue
            ("Stan scenario has an ambiguous duplicate sequence: "
             ^ observation.scenario_id)
        else Hashtbl.add scenario_sequences key ())
      observations;
    List.iter
      (fun duplicate ->
        issue ("Stan evidence digest is pseudo-replicated: " ^ duplicate))
      (duplicate_values
         (List.map
            (fun (observation : observation) -> observation.evidence_digest)
            observations));
    match List.rev !errors with
    | _ :: _ as errors -> Error errors
    | [] ->
        Ok
          { prior_alpha; prior_beta; all_families; observations;
            input_digest =
              input_digest ~prior_alpha ~prior_beta ~all_families ~observations }

  let model_digest =
    digest_fields
      [ "run-analysis-stan-model-v1"; "beta-binomial";
        "analytic-moment-band"; "latest-per-scenario"; "analysis-only" ]

  let summary_digest (summary : family_summary) =
    digest_fields
      ([ "run-analysis-stan-family-summary-v1"; summary.family_id;
         string_of_int summary.scenario_count;
         string_of_int summary.passing_count;
         float_string summary.posterior_alpha;
         float_string summary.posterior_beta; float_string summary.mean;
         float_string summary.variance; float_string summary.moment_band_low;
         float_string summary.moment_band_high ]
       @ summary.latest_observation_digests)

  let result_digest summaries unmeasured coverage_complete =
    digest_fields
      ([ "run-analysis-stan-result-v1"; string_of_bool coverage_complete ]
       @ List.concat_map
           (fun (summary : family_summary) ->
             [ summary.family_id; summary.summary_digest ])
           summaries
       @ unmeasured)

  let receipt_digest (receipt : receipt) =
    digest_fields
      [ "run-analysis-stan-receipt-v1"; "analysis-only";
        receipt.context_digest; receipt.current_head_digest;
        Int64.to_string receipt.current_at_ns; receipt.input_digest;
        receipt.model_digest; receipt.result_digest ]

  let latest_observations observations =
    let latest = Hashtbl.create (List.length observations) in
    List.iter
      (fun (observation : observation) ->
        match Hashtbl.find_opt latest observation.scenario_id with
        | Some prior when prior.sequence > observation.sequence -> ()
        | Some _ | None -> Hashtbl.replace latest observation.scenario_id observation)
      observations;
    Hashtbl.fold (fun _ observation selected -> observation :: selected) latest []
    |> List.sort compare_observation

  let analyze (context : Run_safety.gate_context) (input : input) =
    let latest = latest_observations input.observations in
    let summaries, unmeasured =
      List.fold_left
        (fun (summaries, unmeasured) family_id ->
          let observations =
            List.filter
              (fun (observation : observation) ->
                String.equal observation.family_id family_id)
              latest
          in
          match observations with
          | [] -> (summaries, family_id :: unmeasured)
          | _ :: _ ->
              let scenario_count = List.length observations in
              let passing_count =
                List.fold_left
                  (fun count (observation : observation) ->
                    match observation.verdict with
                    | Passed -> count + 1
                    | Failed -> count)
                  0 observations
              in
              let posterior =
                Receipt_reliability.posterior ~a:input.prior_alpha
                  ~b:input.prior_beta ~n:scenario_count ~k:passing_count
              in
              let mean = Receipt_reliability.mean posterior in
              let variance = Receipt_reliability.variance posterior in
              let moment_band_low, moment_band_high =
                Receipt_reliability.cred95 posterior
              in
              let latest_observation_digests =
                List.map
                  (fun (observation : observation) ->
                    observation.observation_digest)
                  observations
                |> List.sort String.compare
              in
              let provisional =
                { family_id; scenario_count; passing_count;
                  posterior_alpha = posterior.alpha;
                  posterior_beta = posterior.beta; mean; variance;
                  moment_band_low; moment_band_high;
                  latest_observation_digests; summary_digest = "" }
              in
              let summary =
                { provisional with summary_digest = summary_digest provisional }
              in
              (summary :: summaries, unmeasured))
        ([], []) input.all_families
    in
    let summaries = List.rev summaries in
    let unmeasured_families = List.rev unmeasured in
    let coverage_complete = unmeasured_families = [] in
    let result_digest =
      result_digest summaries unmeasured_families coverage_complete
    in
    let provisional =
      { model = Beta_binomial_analytic_moment_band_v1;
        authority = Run_safety.Analysis_only;
        context_digest = context.context_digest;
        current_head_digest = context.current_head_digest;
        current_at_ns = context.current_at_ns; input_digest = input.input_digest;
        model_digest; summaries; unmeasured_families; coverage_complete;
        result_digest; receipt_digest = "" }
    in
    Ok { provisional with receipt_digest = receipt_digest provisional }

  let valid_summary (summary : family_summary) =
    let posterior : Receipt_reliability.posterior =
      { alpha = summary.posterior_alpha; beta = summary.posterior_beta }
    in
    let low, high = Receipt_reliability.cred95 posterior in
    valid_identifier summary.family_id && summary.scenario_count > 0
    && summary.passing_count >= 0
    && summary.passing_count <= summary.scenario_count
    && Float.is_finite summary.posterior_alpha && summary.posterior_alpha > 0.0
    && Float.is_finite summary.posterior_beta && summary.posterior_beta > 0.0
    && Float.equal summary.mean (Receipt_reliability.mean posterior)
    && Float.equal summary.variance (Receipt_reliability.variance posterior)
    && Float.equal summary.moment_band_low low
    && Float.equal summary.moment_band_high high
    && List.for_all valid_digest summary.latest_observation_digests
    && List.length summary.latest_observation_digests = summary.scenario_count
    && valid_digest summary.summary_digest
    && String.equal summary.summary_digest (summary_digest summary)

  let validate_receipt ~(context : Run_safety.gate_context) (receipt : receipt) =
    if not (String.equal context.context_digest receipt.context_digest
            && String.equal context.current_head_digest receipt.current_head_digest
            && context.current_at_ns = receipt.current_at_ns)
    then
      Error
        (analysis_error context ~code:Run_safety.Context_mismatch
           ~message:"Stan receipt context mismatch"
           ~rca_origin:Ops_capability.Control ~hazard_id:"HZ-T6-STAN-01")
    else if receipt.authority <> Run_safety.Analysis_only
            || receipt.model <> Beta_binomial_analytic_moment_band_v1
            || not (valid_digest receipt.input_digest)
            || not (String.equal receipt.model_digest model_digest)
            || not (List.for_all valid_summary receipt.summaries)
            || receipt.coverage_complete <> (receipt.unmeasured_families = [])
            || not
                 (String.equal receipt.result_digest
                    (result_digest receipt.summaries
                       receipt.unmeasured_families receipt.coverage_complete))
            || not
                 (String.equal receipt.receipt_digest
                    (receipt_digest receipt))
    then
      Error
        (analysis_error context ~code:Run_safety.Invalid_receipt
           ~message:"Stan receipt digest, model, or authority is invalid"
           ~rca_origin:Ops_capability.Evidence ~hazard_id:"HZ-T6-STAN-01")
    else Ok ()

  let validate_exact ~context ~input receipt =
    match validate_receipt ~context receipt with
    | Error _ as error -> error
    | Ok () ->
        begin match analyze context input with
        | Error _ as error -> error
        | Ok expected ->
            if expected.authority = Run_safety.Analysis_only
               && receipt.authority = Run_safety.Analysis_only
               && expected.coverage_complete
               && receipt.coverage_complete
               && expected = receipt
            then Ok ()
            else
              Error
                (analysis_error context ~code:Run_safety.Invalid_receipt
                   ~message:
                     "Stan receipt does not exactly match the coverage-complete analysis for the supplied input"
                   ~rca_origin:Ops_capability.Evidence
                   ~hazard_id:"HZ-T6-STAN-01")
        end
end

type stan_receipt = Stan_model.receipt

module Analysis_linked_z3 = Z3
module Linked_protocol = Run_analysis_z3_worker_protocol

module Z3 = struct
  type backend = Linked_smtml_z3 | Injected_z3_cli

  type process_status =
    | Exited of int
    | Signalled of int
    | Timed_out
    | Spawn_failed
    | Supervision_failed

  type campaign_envelope = {
    maximum_total_elapsed_ms : int;
    maximum_teardown_ms : int;
    maximum_receipt_materialization_ms : int;
    linked_max_allocated_bytes : int64;
    linked_max_heap_words : int;
    linked_worker_executable : string;
    linked_worker_executable_digest : string;
    linked_virtual_memory_bytes : int64;
    linked_cpu_seconds : int;
    linked_maximum_query_bytes : int;
    linked_maximum_output_bytes : int;
    maximum_worker_rss_bytes : int64;
    envelope_digest : string;
  }

  type cli_configuration = {
    executable : string;
    executable_digest : string;
    timeout_ms : int;
    version_probe_timeout_ms : int;
    termination_grace_ms : int;
    maximum_output_bytes : int;
    configuration_digest : string;
  }

  type diagnostic = {
    code : string;
    detail : string;
    detail_digest : string;
    coordinate : Ops_capability.coordinate;
    rca_origin : Ops_capability.rca_origin;
    hazard_id : string;
    diagnostic_digest : string;
  }

  type process_receipt = {
    argv_digest : string;
    timeout_ms : int;
    elapsed_ns : int64;
    status : process_status;
    child_created : bool;
    term_sent : bool;
    kill_sent : bool;
    reaped : bool;
    stdout : string;
    stderr : string;
    stdout_bytes : int;
    stderr_bytes : int;
    stdout_digest : string;
    stderr_digest : string;
    receipt_digest : string;
  }

  type linked_invocation = {
    solver_calls_before : int;
    solver_calls_after : int;
    solver_call_delta : int;
    assertion_count : int;
    invocation_digest : string;
  }

  type backend_receipt = {
    backend : backend;
    obligation_stable_id : string;
    requirement_id : string;
    kind : Run_formal.kind;
    expected : Run_formal.result;
    observed : Run_formal.result;
    query_digest : string;
    query_bytes : int;
    executed_query_digest : string;
    readback_query_digest : string;
    readback_query_bytes : int;
    query_object_identity_stable : bool;
    query_object_identity_digest : string;
    obligation_timeout_ms : int;
    solver_timeout_ms : int;
    solver_id : string;
    solver_version_constraint : string;
    solver_version : string;
    linked_library_version : string option;
    executable_path : string option;
    executable_digest : string option;
    process : process_receipt option;
    linked_invocation : linked_invocation option;
    linked_request_digest : string option;
    linked_limits_digest : string option;
    linked_handshake_digest : string option;
    linked_result_digest : string option;
    diagnostics : diagnostic list;
    receipt_digest : string;
  }

  type admission = Admitted | Blocked
  type row_policy =
    | Preflight_fail_fast
    | Campaign_deadline_partial
    | Full_denominator

  type memory_evidence = {
    envelope_digest : string;
    allocated_before_bytes : int64;
    allocated_after_bytes : int64;
    heap_before_words : int;
    heap_after_words : int;
    within_envelope : bool;
    hard_isolated : bool;
    peak_rss_bytes : int64;
    virtual_memory_limit_bytes : int64;
    cpu_limit_seconds : int;
    worker_executable_digest : string;
    limits_digest : string;
    evidence_digest : string;
  }

  type receipt = {
    authority : Run_safety.authority;
    context_digest : string;
    current_head_digest : string;
    current_at_ns : int64;
    specification_digest : string;
    obligation_set_digest : string;
    cli_configuration_digest : string;
    campaign_envelope_digest : string;
    campaign_elapsed_ns : int64;
    campaign_deadline_exhausted : bool;
    cli_version_process : process_receipt;
    in_process : backend_receipt list;
    cli : backend_receipt list;
    controls_complete : bool;
    laws_complete : bool;
    cross_backend_agreement : bool;
    admission : admission;
    row_policy : row_policy;
    memory_evidence : memory_evidence;
    diagnostics : diagnostic list;
    result_digest : string;
    receipt_digest : string;
  }

  let remove_noerr path =
    match Sys.remove path with () -> () | exception Sys_error _ -> ()

  let digest_file path =
    match open_in_bin path with
    | exception exn -> Error (Printexc.to_string exn)
    | channel ->
        Fun.protect
          ~finally:(fun () -> close_in_noerr channel)
          (fun () ->
            let buffer = Bytes.create 65_536 in
            let rec consume context =
              match input channel buffer 0 (Bytes.length buffer) with
              | 0 ->
                  Ok
                    (Digestif.SHA256.get context
                     |> Digestif.SHA256.to_hex)
              | count ->
                  consume
                    (Digestif.SHA256.feed_bytes context buffer ~off:0
                       ~len:count)
              | exception exn -> Error (Printexc.to_string exn)
            in
            consume (Digestif.SHA256.init ()))

  let worker_executable () =
    Filename.concat (Filename.dirname Sys.executable_name)
      "run_analysis_z3_worker.exe"

  let make_campaign_envelope ~maximum_total_elapsed_ms
      ~linked_max_allocated_bytes ~linked_max_heap_words
      ~linked_virtual_memory_bytes ~linked_cpu_seconds
      ~linked_maximum_query_bytes ~linked_maximum_output_bytes
      ~maximum_worker_rss_bytes =
    let errors = ref [] in
    let reject condition message = if condition then errors := message :: !errors in
    reject
      (maximum_total_elapsed_ms <= 0 || maximum_total_elapsed_ms > 300_000)
      "Z3 campaign elapsed bound must be within 1..300000 ms";
    reject (Int64.compare linked_max_allocated_bytes 0L <= 0)
      "Z3 linked allocated-byte evidence bound must be positive";
    reject (linked_max_heap_words <= 0)
      "Z3 linked heap-word evidence bound must be positive";
    reject (Int64.compare linked_virtual_memory_bytes 0L <= 0)
      "Z3 linked virtual-memory limit must be positive";
    reject (linked_cpu_seconds <= 0)
      "Z3 linked CPU limit must be positive";
    reject (linked_maximum_query_bytes <= 0)
      "Z3 linked query bound must be positive";
    reject (linked_maximum_output_bytes < 4096)
      "Z3 linked output bound must be at least 4096 bytes";
    reject
      (Int64.compare maximum_worker_rss_bytes 0L <= 0
       || Int64.compare maximum_worker_rss_bytes 1_073_741_824L >= 0)
      "Z3 worker RSS admission bound must be positive and below 1 GiB";
    let linked_worker_executable = worker_executable () in
    let linked_worker_executable_digest = digest_file linked_worker_executable in
    begin match linked_worker_executable_digest with
    | Ok _ -> ()
    | Error detail ->
        errors := ("Z3 linked worker unavailable: " ^ detail) :: !errors
    end;
    match List.rev !errors, linked_worker_executable_digest with
    | (_ :: _ as errors), (Ok _ | Error _) -> Error errors
    | [], Ok linked_worker_executable_digest ->
        let maximum_obligation_timeout_ms =
          List.fold_left
            (fun maximum (obligation : Run_formal.obligation) ->
              Int.max maximum obligation.timeout_ms)
            0 Run_formal.obligations
        in
        let maximum_in_flight_worker_timeout_ms =
          Int.min maximum_total_elapsed_ms maximum_obligation_timeout_ms
        in
        let maximum_in_flight_worker_grace_ms =
          Int.min 100 maximum_in_flight_worker_timeout_ms
        in
        (* [run_linked] caps one worker timeout by both the remaining campaign
           time and its obligation timeout.  Once that worker has started,
           [supervise] owns one timeout interval followed by TERM and KILL
           grace intervals.  The campaign starts no later worker after expiry,
           so this is the exact single-in-flight teardown denominator rather
           than an empirical scheduling allowance. *)
        let maximum_teardown_ms =
          maximum_in_flight_worker_timeout_ms
          + (2 * maximum_in_flight_worker_grace_ms)
        in
        let obligation_count = List.length Run_formal.obligations in
        let authoritative_query_bytes =
          List.fold_left
            (fun total (obligation : Run_formal.obligation) ->
              total + String.length obligation.smt2)
            0 Run_formal.obligations
        in
        (* Pure row materialization performs fixed per-row construction plus
           bounded copying and hashing of the authoritative query carriers.
           Declare one millisecond per row and one per started 2 KiB carrier
           block.  Both terms derive from the immutable obligation authority;
           unlike empirical scheduler slack, a denominator or query change
           mechanically changes this digest-bound wall-clock allowance. *)
        let maximum_receipt_materialization_ms =
          obligation_count + ((authoritative_query_bytes + 2_047) / 2_048)
        in
        let envelope_digest =
          digest_fields
            [ "run-analysis-z3-campaign-envelope-v1";
              string_of_int maximum_total_elapsed_ms;
              string_of_int maximum_teardown_ms;
              string_of_int maximum_receipt_materialization_ms;
              Int64.to_string linked_max_allocated_bytes;
              string_of_int linked_max_heap_words; linked_worker_executable;
              linked_worker_executable_digest;
              Int64.to_string linked_virtual_memory_bytes;
              string_of_int linked_cpu_seconds;
              string_of_int linked_maximum_query_bytes;
              string_of_int linked_maximum_output_bytes;
              Int64.to_string maximum_worker_rss_bytes ]
        in
        Ok
          { maximum_total_elapsed_ms; maximum_teardown_ms;
            maximum_receipt_materialization_ms;
            linked_max_allocated_bytes;
            linked_max_heap_words; linked_worker_executable;
            linked_worker_executable_digest; linked_virtual_memory_bytes;
            linked_cpu_seconds; linked_maximum_query_bytes;
            linked_maximum_output_bytes; maximum_worker_rss_bytes;
            envelope_digest }
    | [], Error _ -> assert false

  let supervision_admissible ~status ~child_created ~term_sent ~kill_sent
      ~reaped =
    status = Exited 0 && child_created && reaped
    && not term_sent && not kill_sent

  let query_execution_admissible ~authoritative_digest ~executed_digest
      ~readback_digest ~authoritative_bytes ~readback_bytes
      ~object_identity_stable =
    valid_digest authoritative_digest
    && String.equal authoritative_digest executed_digest
    && String.equal authoritative_digest readback_digest
    && authoritative_bytes > 0 && authoritative_bytes = readback_bytes
    && object_identity_stable

  let make_cli_configuration ~executable ~timeout_ms ~termination_grace_ms
      ~maximum_output_bytes =
    let errors = ref [] in
    let reject condition message = if condition then errors := message :: !errors in
    reject (Filename.is_relative executable)
      "Z3 executable path must be absolute";
    reject (timeout_ms <= 0 || timeout_ms > 60_000)
      "Z3 CLI timeout must be within 1..60000 ms";
    reject
      (termination_grace_ms <= 0 || termination_grace_ms > 5_000
       || termination_grace_ms > timeout_ms)
      "Z3 CLI termination grace must be positive and bounded by timeout";
    reject
      (maximum_output_bytes <= 0 || maximum_output_bytes > 1_048_576)
      "Z3 CLI output bound must be within 1..1048576 bytes";
    let executable_digest =
      if Filename.is_relative executable then Error "relative executable"
      else
        match Unix.stat executable with
        | { Unix.st_kind = Unix.S_REG; _ } -> digest_file executable
        | _ -> Error "Z3 executable is not a regular file"
        | exception exn -> Error (Printexc.to_string exn)
    in
    begin match executable_digest with
    | Ok _ -> ()
    | Error detail -> errors := ("Z3 executable unavailable: " ^ detail) :: !errors
    end;
    match List.rev !errors, executable_digest with
    | [], Ok executable_digest ->
        (* Version discovery is an executable-startup preflight, not a solver
           query.  It receives an independent, bounded two-second startup
           floor while the query retains the caller's shorter timeout. *)
        let version_probe_timeout_ms = Int.max 2_000 timeout_ms in
        let configuration_digest =
          digest_fields
            [ "run-analysis-z3-cli-configuration-v1"; executable;
              executable_digest; string_of_int timeout_ms;
              string_of_int version_probe_timeout_ms;
              string_of_int termination_grace_ms;
              string_of_int maximum_output_bytes ]
        in
        Ok
          { executable; executable_digest; timeout_ms; version_probe_timeout_ms;
            termination_grace_ms; maximum_output_bytes; configuration_digest }
    | errors, (Ok _ | Error _) -> Error errors

  let process_status_string = function
    | Exited code -> "exited:" ^ string_of_int code
    | Signalled signal -> "signalled:" ^ string_of_int signal
    | Timed_out -> "timed-out"
    | Spawn_failed -> "spawn-failed"
    | Supervision_failed -> "supervision-failed"

  let process_receipt_digest receipt =
    digest_fields
      [ "run-analysis-z3-process-receipt-v1"; receipt.argv_digest;
        string_of_int receipt.timeout_ms; Int64.to_string receipt.elapsed_ns;
        process_status_string receipt.status; string_of_bool receipt.child_created;
        string_of_bool receipt.term_sent; string_of_bool receipt.kill_sent;
        string_of_bool receipt.reaped; string_of_int receipt.stdout_bytes;
        string_of_int receipt.stderr_bytes; receipt.stdout_digest;
        receipt.stderr_digest ]

  let make_diagnostic (context : Run_safety.gate_context) ~code ~detail =
    let detail =
      if String.length detail <= 512 then detail else String.sub detail 0 512
    in
    let detail_digest = sha256 detail in
    let coordinate = context.Run_safety.coordinate in
    let rca_origin = Ops_capability.Environment in
    let hazard_id = "HZ-T6-Z3-01" in
    let diagnostic_digest =
      digest_fields
        [ "run-analysis-z3-diagnostic-v1"; code; detail_digest;
          Ops_capability.string_of_level coordinate.level;
          Ops_capability.string_of_phase coordinate.phase;
          Ops_capability.string_of_rca_origin rca_origin; hazard_id ]
    in
    { code; detail; detail_digest; coordinate; rca_origin; hazard_id;
      diagnostic_digest }

  let diagnostic_valid (context : Run_safety.gate_context)
      (diagnostic : diagnostic) =
    valid_identifier diagnostic.code && String.length diagnostic.detail <= 512
    && String.equal diagnostic.detail_digest (sha256 diagnostic.detail)
    && diagnostic.coordinate = context.coordinate
    && diagnostic.rca_origin = Ops_capability.Environment
    && String.equal diagnostic.hazard_id "HZ-T6-Z3-01"
    && String.equal diagnostic.diagnostic_digest
         (digest_fields
            [ "run-analysis-z3-diagnostic-v1"; diagnostic.code;
              diagnostic.detail_digest;
              Ops_capability.string_of_level diagnostic.coordinate.level;
              Ops_capability.string_of_phase diagnostic.coordinate.phase;
              Ops_capability.string_of_rca_origin diagnostic.rca_origin;
              diagnostic.hazard_id ])

  let kind_string = function
    | Run_formal.Negated_law -> "negated-law"
    | Run_formal.False_control -> "false-control"

  let result_string = function
    | Run_formal.Sat -> "sat"
    | Run_formal.Unsat -> "unsat"
    | Run_formal.Unknown -> "unknown"
    | Run_formal.Timeout -> "timeout"
    | Run_formal.Unavailable -> "unavailable"

  let backend_string = function
    | Linked_smtml_z3 -> "linked-smtml-z3"
    | Injected_z3_cli -> "injected-z3-cli"

  let obligation_set_digest () =
    Run_formal.obligations
    |> List.concat_map (fun (obligation : Run_formal.obligation) ->
         [ obligation.stable_id; obligation.requirement_id;
           obligation.query_digest; string_of_int obligation.timeout_ms ])
    |> fun fields -> digest_fields ("run-analysis-z3-obligations-v1" :: fields)

  type capture = {
    path : string;
    channel : out_channel;
    descriptor : Unix.file_descr;
  }

  let create_capture suffix =
    match Filename.open_temp_file ~mode:[ Open_binary ] "run-analysis-z3" suffix with
    | path, initial_channel ->
        close_out initial_channel;
        begin match
          Unix.openfile path [ Unix.O_RDWR; Unix.O_TRUNC; Unix.O_CLOEXEC ] 0o600
        with
        | descriptor ->
            let channel = Unix.out_channel_of_descr descriptor in
            begin match Unix.fchmod descriptor 0o600 with
            | () -> Ok { path; channel; descriptor }
            | exception exn ->
                close_out_noerr channel;
                remove_noerr path;
                Error (Printexc.to_string exn)
            end
        | exception exn ->
            remove_noerr path;
            Error (Printexc.to_string exn)
        end
    | exception exn -> Error (Printexc.to_string exn)

  let close_capture capture =
    close_out_noerr capture.channel;
    remove_noerr capture.path

  type captured_output = {
    text : string;
    bytes : int;
    digest : string;
  }

  let read_capture capture maximum_output_bytes =
    match Unix.LargeFile.lseek capture.descriptor 0L Unix.SEEK_SET with
    | exception exn -> Error (Printexc.to_string exn)
    | _ ->
        let chunk = Bytes.create 65_536 in
        let bounded = Buffer.create (min maximum_output_bytes 65_536) in
        let rec consume context bytes =
          match Unix.read capture.descriptor chunk 0 (Bytes.length chunk) with
          | 0 ->
              Ok
                { text = Buffer.contents bounded; bytes;
                  digest =
                    (Digestif.SHA256.get context |> Digestif.SHA256.to_hex) }
          | count ->
              let remaining = maximum_output_bytes - Buffer.length bounded in
              if remaining > 0 then
                Buffer.add_subbytes bounded chunk 0 (min remaining count);
              let bytes =
                if bytes > max_int - count then max_int else bytes + count
              in
              consume
                (Digestif.SHA256.feed_bytes context chunk ~off:0 ~len:count)
                bytes
          | exception Unix.Unix_error (Unix.EINTR, _, _) ->
              consume context bytes
          | exception exn -> Error (Printexc.to_string exn)
        in
        consume (Digestif.SHA256.init ()) 0

  let ns_of_ms milliseconds = Int64.mul (Int64.of_int milliseconds) 1_000_000L

  let monotonic_add now duration =
    if Int64.compare duration (Int64.sub Int64.max_int now) > 0 then
      Int64.max_int
    else Int64.add now duration

  let rec waitpid_retry flags pid =
    match Unix.waitpid flags pid with
    | result -> result
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> waitpid_retry flags pid

  let wait_briefly deadline_ns =
    let remaining = Int64.sub deadline_ns (Mtime_clock.elapsed_ns ()) in
    if Int64.compare remaining 0L > 0 then
      let seconds = Int64.to_float remaining /. 1_000_000_000.0 in
      match Unix.select [] [] [] (min 0.01 seconds) with
      | _ -> ()
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> ()

  type wait_result =
    | Wait_exited of int
    | Wait_signalled of int
    | Wait_deadline
    | Wait_failed of string

  let rec wait_until pid deadline_ns =
    match waitpid_retry [ Unix.WNOHANG; Unix.WUNTRACED ] pid with
    | 0, _ ->
        if Int64.compare (Mtime_clock.elapsed_ns ()) deadline_ns >= 0 then
          Wait_deadline
        else begin
          wait_briefly deadline_ns;
          wait_until pid deadline_ns
        end
    | _, Unix.WEXITED code -> Wait_exited code
    | _, Unix.WSIGNALED signal -> Wait_signalled signal
    | _, Unix.WSTOPPED _ ->
        if Int64.compare (Mtime_clock.elapsed_ns ()) deadline_ns >= 0 then
          Wait_deadline
        else begin
          wait_briefly deadline_ns;
          wait_until pid deadline_ns
        end
    | exception Unix.Unix_error (Unix.ECHILD, _, _) ->
        Wait_failed "waitpid reported no child"
    | exception exn -> Wait_failed (Printexc.to_string exn)

  let rec signal_retry pid signal =
    match Unix.kill pid signal with
    | () -> true
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> signal_retry pid signal
    | exception Unix.Unix_error _ -> false

  let reap_until pid deadline_ns =
    match wait_until pid deadline_ns with
    | Wait_exited _ | Wait_signalled _ -> true
    | Wait_deadline | Wait_failed _ -> false

  let supervise ?(group = false) pid (configuration : cli_configuration) started_ns =
    let signal signal = signal_retry (if group then -pid else pid) signal in
    let deadline =
      monotonic_add started_ns (ns_of_ms configuration.timeout_ms)
    in
    match wait_until pid deadline with
    | Wait_exited code -> Exited code, true, false, false
    | Wait_signalled signal -> Signalled signal, true, false, false
    | Wait_deadline ->
        ignore (signal Sys.sigterm);
        let grace_deadline =
          monotonic_add (Mtime_clock.elapsed_ns ())
            (ns_of_ms configuration.termination_grace_ms)
        in
        begin match wait_until pid grace_deadline with
        | Wait_exited _ | Wait_signalled _ -> Timed_out, true, true, false
        | Wait_deadline | Wait_failed _ ->
            ignore (signal Sys.sigkill);
            let kill_deadline =
              monotonic_add (Mtime_clock.elapsed_ns ())
                (ns_of_ms configuration.termination_grace_ms)
            in
            Timed_out, reap_until pid kill_deadline, true, true
        end
    | Wait_failed _ ->
        ignore (signal Sys.sigkill);
        let cleanup_deadline =
          monotonic_add (Mtime_clock.elapsed_ns ())
            (ns_of_ms configuration.termination_grace_ms)
        in
        Supervision_failed, reap_until pid cleanup_deadline, false, true

  let make_process_receipt ~argv_digest ~timeout_ms ~elapsed_ns ~status
      ~child_created ~term_sent ~kill_sent ~reaped stdout stderr =
    let provisional =
      { argv_digest; timeout_ms; elapsed_ns; status; child_created; reaped;
        term_sent; kill_sent;
        stdout = stdout.text; stderr = stderr.text;
        stdout_bytes = stdout.bytes; stderr_bytes = stderr.bytes;
        stdout_digest = stdout.digest; stderr_digest = stderr.digest;
        receipt_digest = "" }
    in
    { provisional with receipt_digest = process_receipt_digest provisional }

  let empty_output detail =
    { text = detail; bytes = String.length detail; digest = sha256 detail }

  let run_process ?timeout_ms (configuration : cli_configuration) argv =
    let timeout_ms = Option.value ~default:configuration.timeout_ms timeout_ms in
    let execution_configuration = { configuration with timeout_ms } in
    let argv_digest =
      digest_fields
        ("run-analysis-z3-argv-v1" :: "empty-environment"
         :: Array.to_list argv)
    in
    match create_capture ".stdout" with
    | Error detail ->
        make_process_receipt ~argv_digest ~timeout_ms
          ~elapsed_ns:0L ~status:Spawn_failed ~child_created:false
          ~term_sent:false ~kill_sent:false ~reaped:false
          (empty_output "") (empty_output detail)
    | Ok stdout_capture ->
        Fun.protect
          ~finally:(fun () -> close_capture stdout_capture)
          (fun () ->
            match create_capture ".stderr" with
            | Error detail ->
                make_process_receipt ~argv_digest
                  ~timeout_ms ~elapsed_ns:0L
                  ~status:Spawn_failed ~child_created:false ~term_sent:false
                  ~kill_sent:false ~reaped:false
                  (empty_output "") (empty_output detail)
            | Ok stderr_capture ->
                Fun.protect
                  ~finally:(fun () -> close_capture stderr_capture)
                  (fun () ->
                    let started_ns = Mtime_clock.elapsed_ns () in
                    let status, child_created, reaped, term_sent, kill_sent =
                      match
                        Unix.create_process_env configuration.executable argv [||]
                          Unix.stdin stdout_capture.descriptor
                          stderr_capture.descriptor
                      with
                      | pid ->
                          let status, reaped, term_sent, kill_sent =
                            supervise pid execution_configuration started_ns
                          in
                          status, true, reaped, term_sent, kill_sent
                      | exception _ ->
                          Spawn_failed, false, false, false, false
                    in
                    let elapsed_ns =
                      max 0L (Int64.sub (Mtime_clock.elapsed_ns ()) started_ns)
                    in
                    let stdout =
                      match
                        read_capture stdout_capture
                          configuration.maximum_output_bytes
                      with
                      | Ok output -> output
                      | Error detail -> empty_output ("read failure: " ^ detail)
                    in
                    let stderr =
                      match
                        read_capture stderr_capture
                          configuration.maximum_output_bytes
                      with
                      | Ok output -> output
                      | Error detail -> empty_output ("read failure: " ^ detail)
                    in
                    make_process_receipt ~argv_digest
                      ~timeout_ms ~elapsed_ns ~status
                      ~child_created ~term_sent ~kill_sent ~reaped stdout stderr))

  type query_materialization = {
    executed_digest : string;
    readback_digest : string;
    readback_bytes : int;
    object_identity_stable : bool;
    object_identity_digest : string;
  }

  let file_identity (stats : Unix.stats) =
    string_of_int stats.st_dev ^ ":" ^ string_of_int stats.st_ino

  let with_query_file query use =
    match Filename.temp_dir ~perms:0o700 "run-analysis-z3-" ".query" with
    | exception exn -> Error (Printexc.to_string exn)
    | directory ->
        let path = Filename.concat directory "query.smt2" in
        let channel = ref None in
        Fun.protect
          ~finally:(fun () ->
            Option.iter close_out_noerr !channel;
            remove_noerr path;
            (try Unix.rmdir directory with Unix.Unix_error _ -> ()))
          (fun () ->
            Unix.chmod directory 0o700;
            let descriptor =
              Unix.openfile path
                [ Unix.O_CREAT; Unix.O_EXCL; Unix.O_WRONLY; Unix.O_CLOEXEC ]
                0o600
            in
            Unix.fchmod descriptor 0o600;
            let output = Unix.out_channel_of_descr descriptor in
            channel := Some output;
            output_string output query;
            flush output;
            let before = Unix.fstat descriptor in
            close_out output;
            channel := None;
            let executed_digest = sha256 query in
            match use path with
            | Error _ as error -> error
            | Ok value ->
                let after = Unix.stat path in
                begin match digest_file path with
                | Error _ as error -> error
                | Ok readback_digest ->
                    let readback_bytes = after.st_size in
                    let before_identity = file_identity before in
                    let after_identity = file_identity after in
                    let object_identity_stable =
                      String.equal before_identity after_identity
                    in
                    let object_identity_digest =
                      digest_fields
                        [ "run-analysis-z3-query-object-v1";
                          before_identity; after_identity;
                          string_of_bool object_identity_stable ]
                    in
                    Ok
                      ( value,
                        { executed_digest; readback_digest; readback_bytes;
                          object_identity_stable; object_identity_digest } )
                end)

  let linked_version = Analysis_linked_z3.Version.to_string
  let linked_library_version = "smtml-0.29.0/z3-ocaml-" ^ linked_version

  let backend_receipt_digest receipt =
    let option value = Option.value ~default:"" value in
    digest_fields
      ([ "run-analysis-z3-backend-receipt-v1";
         backend_string receipt.backend; receipt.obligation_stable_id;
         receipt.requirement_id; kind_string receipt.kind;
         result_string receipt.expected; result_string receipt.observed;
         receipt.query_digest; string_of_int receipt.query_bytes;
         receipt.executed_query_digest; receipt.readback_query_digest;
         string_of_int receipt.readback_query_bytes;
         string_of_bool receipt.query_object_identity_stable;
         receipt.query_object_identity_digest;
         string_of_int receipt.obligation_timeout_ms;
         string_of_int receipt.solver_timeout_ms; receipt.solver_id;
         receipt.solver_version_constraint; receipt.solver_version;
         option receipt.linked_library_version; option receipt.executable_path;
         option receipt.executable_digest;
         Option.fold ~none:""
           ~some:(fun (process : process_receipt) -> process.receipt_digest)
           receipt.process;
         Option.fold ~none:""
           ~some:(fun (invocation : linked_invocation) ->
             invocation.invocation_digest)
           receipt.linked_invocation;
         option receipt.linked_request_digest;
         option receipt.linked_limits_digest;
         option receipt.linked_handshake_digest;
         option receipt.linked_result_digest ]
       @ List.map
           (fun (diagnostic : diagnostic) -> diagnostic.diagnostic_digest)
           receipt.diagnostics)

  let make_backend_receipt ~backend ~obligation ~observed ~solver_timeout_ms
      ~solver_version ~linked_library_version ~executable_path
      ~executable_digest ~process ~materialization ~linked_invocation
      ~linked_request_digest ~linked_limits_digest ~linked_handshake_digest
      ~linked_result_digest ~diagnostics =
    let executed_query_digest, readback_query_digest, readback_query_bytes,
        query_object_identity_stable, query_object_identity_digest =
      match materialization with
      | None -> "", "", 0, false, sha256 ""
      | Some (value : query_materialization) ->
          value.executed_digest, value.readback_digest, value.readback_bytes,
          value.object_identity_stable, value.object_identity_digest
    in
    let provisional =
      { backend; obligation_stable_id = obligation.Run_formal.stable_id;
        requirement_id = obligation.requirement_id; kind = obligation.kind;
        expected = obligation.expected; observed;
        query_digest = obligation.query_digest;
        query_bytes = String.length obligation.smt2;
        executed_query_digest; readback_query_digest; readback_query_bytes;
        query_object_identity_stable; query_object_identity_digest;
        obligation_timeout_ms = obligation.timeout_ms; solver_timeout_ms;
        solver_id = obligation.solver_id;
        solver_version_constraint = obligation.solver_version_constraint;
        solver_version; linked_library_version; executable_path;
        executable_digest; process; linked_invocation;
        linked_request_digest; linked_limits_digest;
        linked_handshake_digest; linked_result_digest; diagnostics;
        receipt_digest = "" }
    in
    { provisional with receipt_digest = backend_receipt_digest provisional }

  type linked_row_evidence = {
    peak_rss_bytes : int64;
    limits_digest : string;
  }

  let close_fd_noerr descriptor =
    try Unix.close descriptor with Unix.Unix_error _ -> ()

  let write_fd_all descriptor bytes =
    let rec loop offset =
      if offset = String.length bytes then Ok ()
      else
        match
          Unix.write_substring descriptor bytes offset
            (String.length bytes - offset)
        with
        | 0 -> Error "worker stdin write made no progress"
        | count -> loop (offset + count)
        | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop offset
        | exception exn -> Error (Printexc.to_string exn)
    in
    loop 0

  let remaining_seconds deadline =
    let remaining = Int64.sub deadline (Mtime_clock.elapsed_ns ()) in
    if Int64.compare remaining 0L <= 0 then 0.0
    else Int64.to_float remaining /. 1_000_000_000.0

  let read_fd_line_bounded descriptor maximum deadline =
    let byte = Bytes.create 1 in
    let buffer = Buffer.create (min maximum 512) in
    let rec loop observed =
      if observed >= maximum then Error "linked worker first frame exceeded bound"
      else
        let remaining = remaining_seconds deadline in
        if remaining <= 0.0 then Error "linked worker handshake deadline"
        else
          match Unix.select [ descriptor ] [] [] remaining with
          | [], _, _ -> Error "linked worker handshake deadline"
          | _ ->
              begin match Unix.read descriptor byte 0 1 with
              | 0 -> Error "linked worker closed before handshake"
              | 1 ->
                  let character = Bytes.get byte 0 in
                  Buffer.add_char buffer character;
                  if character = '\n' then Ok (Buffer.contents buffer)
                  else loop (observed + 1)
              | _ -> assert false
              | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop observed
              | exception exn -> Error (Printexc.to_string exn)
              end
    in
    loop 0

  let read_fd_bounded descriptor maximum =
    let chunk = Bytes.create 4096 in
    let buffer = Buffer.create (min maximum 4096) in
    let rec loop observed =
      match Unix.read descriptor chunk 0 (Bytes.length chunk) with
      | 0 -> Ok (Buffer.contents buffer, observed)
      | count ->
          let observed = observed + count in
          if observed > maximum then Error "linked worker output exceeded bound"
          else begin
            Buffer.add_subbytes buffer chunk 0 count;
            loop observed
          end
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop observed
      | exception exn -> Error (Printexc.to_string exn)
    in
    loop 0

  let linked_configuration campaign timeout_ms =
    { executable = campaign.linked_worker_executable;
      executable_digest = campaign.linked_worker_executable_digest;
      timeout_ms; version_probe_timeout_ms = timeout_ms;
      termination_grace_ms = min 100 timeout_ms;
      maximum_output_bytes = campaign.linked_maximum_output_bytes;
      configuration_digest = campaign.envelope_digest }

  let linked_unavailable context campaign obligation ?process detail =
    let diagnostics =
      [ make_diagnostic context ~code:"Z3-LINKED-UNAVAILABLE" ~detail ]
    in
    make_backend_receipt ~backend:Linked_smtml_z3 ~obligation
      ~observed:Run_formal.Unavailable
      ~solver_timeout_ms:obligation.Run_formal.timeout_ms
      ~solver_version:linked_version
      ~linked_library_version:(Some linked_library_version)
      ~executable_path:(Some campaign.linked_worker_executable)
      ~executable_digest:(Some campaign.linked_worker_executable_digest)
      ~process ~materialization:None ~linked_invocation:None
      ~linked_request_digest:None ~linked_limits_digest:None
      ~linked_handshake_digest:None ~linked_result_digest:None ~diagnostics,
    None

  let linked_resource_preflight campaign =
    match Unix.stat campaign.linked_worker_executable with
    | exception exn -> Error (Printexc.to_string exn)
    | stats ->
        let expected =
          Resource_envelope.{ device = stats.st_dev; inode = stats.st_ino }
        in
        let checks =
          Linked_protocol.resource_requirements
            ~worker_path:campaign.linked_worker_executable ~expected
          |> Resource_envelope.preflight
        in
        if not (Resource_envelope.satisfied checks) then
          checks |> Resource_envelope.unmet_checks
          |> List.map Resource_envelope.render_check |> String.concat "; "
          |> Result.error
        else
          match digest_file campaign.linked_worker_executable with
          | Ok digest
            when String.equal digest campaign.linked_worker_executable_digest ->
              Ok ()
          | Ok _ -> Error "linked worker executable digest changed"
          | Error detail -> Error detail

  let run_linked context campaign campaign_deadline obligation =
    let remaining_ms =
      remaining_seconds campaign_deadline *. 1000.0 |> int_of_float
    in
    if remaining_ms <= 0 then
      linked_unavailable context campaign obligation "campaign deadline exhausted"
    else
      match linked_resource_preflight campaign with
      | Error detail -> linked_unavailable context campaign obligation detail
      | Ok () ->
          begin match
            Linked_protocol.make_limits
              ~virtual_memory_bytes:campaign.linked_virtual_memory_bytes
              ~cpu_seconds:campaign.linked_cpu_seconds
              ~maximum_query_bytes:campaign.linked_maximum_query_bytes
              ~maximum_output_bytes:campaign.linked_maximum_output_bytes,
            Linked_protocol.sha256_of_hex
              campaign.linked_worker_executable_digest
          with
          | Error errors, _ ->
              linked_unavailable context campaign obligation
                (String.concat "; " errors)
          | _, Error error ->
              linked_unavailable context campaign obligation
                (Linked_protocol.render_error error)
          | Ok limits, Ok worker_executable_digest ->
              begin match
                Linked_protocol.prepare ~obligation_id:obligation.stable_id
                  ~worker_executable_digest ~query:obligation.smt2 ~limits
              with
              | Error errors ->
                  linked_unavailable context campaign obligation
                    (String.concat "; " errors)
              | Ok prepared ->
                  let stdin_read, stdin_write = Unix.pipe ~cloexec:true () in
                  let stdout_read, stdout_write = Unix.pipe ~cloexec:true () in
                  let stderr_read, stderr_write = Unix.pipe ~cloexec:true () in
                  Fun.protect
                    ~finally:(fun () ->
                      List.iter close_fd_noerr
                        [ stdin_read; stdin_write; stdout_read; stdout_write;
                          stderr_read; stderr_write ])
                    (fun () ->
                      let executable = campaign.linked_worker_executable in
                      let argv =
                        Array.append [| executable |]
                          (Linked_protocol.argv prepared)
                      in
                      let argv_digest =
                        digest_fields
                          ("run-analysis-z3-linked-argv-v1"
                           :: "empty-environment" :: Array.to_list argv)
                      in
                      let timeout_ms =
                        max 1 (min remaining_ms obligation.timeout_ms)
                      in
                      let configuration = linked_configuration campaign timeout_ms in
                      let started_ns = Mtime_clock.elapsed_ns () in
                      match
                        Unix.create_process_env executable argv [||] stdin_read
                          stdout_write stderr_write
                      with
                      | exception exn ->
                          linked_unavailable context campaign obligation
                            (Printexc.to_string exn)
                      | pid ->
                          close_fd_noerr stdin_read;
                          close_fd_noerr stdout_write;
                          close_fd_noerr stderr_write;
                          let local_deadline =
                            monotonic_add started_ns (ns_of_ms timeout_ms)
                            |> Int64.min campaign_deadline
                          in
                          let first_line =
                            read_fd_line_bounded stdout_read
                              campaign.linked_maximum_output_bytes local_deadline
                          in
                          let handshake =
                            match first_line with
                            | Error _ -> None
                            | Ok line ->
                                begin match
                                  Linked_protocol.decode_frame
                                    ~maximum_bytes:
                                      campaign.linked_maximum_output_bytes line
                                with
                                | Ok (Linked_protocol.Handshake handshake)
                                  when Linked_protocol.validate_handshake
                                         ~request:prepared.request handshake = [] ->
                                    Some handshake
                                | Ok (Handshake _ | Result _ | Refusal _) | Error _ ->
                                    None
                                end
                          in
                          let write_result =
                            match handshake with
                            | None -> Error "containment handshake was not admitted"
                            | Some _ ->
                                write_fd_all stdin_write
                                  (Linked_protocol.stdin_bytes prepared)
                          in
                          close_fd_noerr stdin_write;
                          let status, reaped, term_sent, kill_sent =
                            supervise ~group:true pid configuration started_ns
                          in
                          let remaining_stdout =
                            read_fd_bounded stdout_read
                              campaign.linked_maximum_output_bytes
                          in
                          let stderr_result =
                            read_fd_bounded stderr_read
                              campaign.linked_maximum_output_bytes
                          in
                          let elapsed_ns =
                            max 0L
                              (Int64.sub (Mtime_clock.elapsed_ns ()) started_ns)
                          in
                          let stdout =
                            match first_line, remaining_stdout with
                            | Ok first, Ok (remaining, observed)
                              when String.length first + observed
                                   <= campaign.linked_maximum_output_bytes ->
                                let text = first ^ remaining in
                                { text; bytes = String.length text;
                                  digest = sha256 text }
                            | Ok _, Ok _ -> empty_output "linked stdout over bound"
                            | Error detail, _ | _, Error detail -> empty_output detail
                          in
                          let stderr =
                            match stderr_result with
                            | Ok (text, bytes) -> { text; bytes; digest = sha256 text }
                            | Error detail -> empty_output detail
                          in
                          let process =
                            make_process_receipt ~argv_digest ~timeout_ms
                              ~elapsed_ns ~status ~child_created:true ~term_sent
                              ~kill_sent ~reaped stdout stderr
                          in
                          match handshake, write_result with
                          | None, _ | _, Error _ ->
                              linked_unavailable context campaign obligation
                                ~process "linked worker handshake or stdin failed"
                          | Some handshake, Ok () ->
                              begin match
                                Linked_protocol.decode_argv
                                  (Linked_protocol.argv prepared),
                                Linked_protocol.admit_stdin prepared.request
                                  (Linked_protocol.stdin_bytes prepared),
                                Linked_protocol.decode_transcript
                                  ~maximum_bytes:
                                    campaign.linked_maximum_output_bytes stdout.text
                              with
                              | Ok request, Ok query,
                                Ok (Linked_protocol.Completed
                                      { handshake = completed_handshake; result })
                                when supervision_admissible
                                       ~status:process.status
                                       ~child_created:process.child_created
                                       ~term_sent:process.term_sent
                                       ~kill_sent:process.kill_sent
                                       ~reaped:process.reaped
                                     && completed_handshake = handshake
                                     && Linked_protocol.validate_result ~request
                                          ~query ~handshake result = [] ->
                                  let observed =
                                    match result.answer with
                                    | Linked_protocol.Sat -> Run_formal.Sat
                                    | Unsat -> Run_formal.Unsat
                                    | Unknown -> Run_formal.Unknown
                                  in
                                  let capture = result.capture in
                                  let before = capture.file_object_before in
                                  let after = capture.file_object_after in
                                  let stable = before = after in
                                  let identity_digest =
                                    digest_fields
                                      [ "run-analysis-z3-query-object-v1";
                                        string_of_int before.device;
                                        string_of_int before.inode;
                                        string_of_int after.device;
                                        string_of_int after.inode;
                                        string_of_bool stable ]
                                  in
                                  let materialization =
                                    { executed_digest =
                                        Linked_protocol.sha256_to_hex
                                          result.executed_query_digest;
                                      readback_digest =
                                        Linked_protocol.sha256_to_hex
                                          capture.readback_digest;
                                      readback_bytes = capture.readback_bytes;
                                      object_identity_stable = stable;
                                      object_identity_digest = identity_digest }
                                  in
                                  let invocation =
                                    let provisional =
                                      { solver_calls_before = 0;
                                        solver_calls_after = result.solver_call_delta;
                                        solver_call_delta = result.solver_call_delta;
                                        assertion_count = result.assertion_count;
                                        invocation_digest = "" }
                                    in
                                    { provisional with
                                      invocation_digest =
                                        digest_fields
                                          [ "run-analysis-z3-linked-invocation-v1";
                                            obligation.stable_id;
                                            string_of_int result.solver_call_delta;
                                            string_of_int result.assertion_count;
                                            Linked_protocol.sha256_to_hex
                                              result.result_digest ] }
                                  in
                                  let diagnostics =
                                    if observed = Run_formal.Unknown then
                                      [ make_diagnostic context
                                          ~code:"Z3-LINKED-UNKNOWN"
                                          ~detail:"linked Z3 returned Unknown" ]
                                    else []
                                  in
                                  let row =
                                    make_backend_receipt
                                      ~backend:Linked_smtml_z3 ~obligation
                                      ~observed
                                      ~solver_timeout_ms:obligation.timeout_ms
                                      ~solver_version:result.solver_version
                                      ~linked_library_version:
                                        (Some linked_library_version)
                                      ~executable_path:(Some executable)
                                      ~executable_digest:
                                        (Some
                                           campaign.linked_worker_executable_digest)
                                      ~process:(Some process)
                                      ~materialization:(Some materialization)
                                      ~linked_invocation:(Some invocation)
                                      ~linked_request_digest:
                                        (Some
                                           (Linked_protocol.sha256_to_hex
                                              request.request_digest))
                                      ~linked_limits_digest:
                                        (Some
                                           (Linked_protocol.sha256_to_hex
                                              request.limits.limits_digest))
                                      ~linked_handshake_digest:
                                        (Some
                                           (Linked_protocol.sha256_to_hex
                                              handshake.handshake_digest))
                                      ~linked_result_digest:
                                        (Some
                                           (Linked_protocol.sha256_to_hex
                                              result.result_digest))
                                      ~diagnostics
                                  in
                                  row,
                                  Some
                                    { peak_rss_bytes = result.peak_rss_bytes;
                                      limits_digest =
                                        Linked_protocol.sha256_to_hex
                                          request.limits.limits_digest }
                              | Ok _, Ok _,
                                Ok (Linked_protocol.Refused refusal) ->
                                  linked_unavailable context campaign obligation
                                    ~process
                                    ("worker refusal: " ^ refusal.detail)
                              | Ok _, Ok _, Error error ->
                                  linked_unavailable context campaign obligation
                                    ~process
                                    ("transcript decode: "
                                     ^ Linked_protocol.render_error error)
                              | _ ->
                                  linked_unavailable context campaign obligation
                                    ~process
                                    "linked worker transcript validation failed"
                              end)
              end
          end

  let parse_cli_result (process : process_receipt) maximum_output_bytes =
    if process.stdout_bytes > maximum_output_bytes
       || process.stderr_bytes > maximum_output_bytes
    then Error (Run_formal.Unavailable, "Z3 CLI output exceeded declared bound")
    else
      match process.status with
      | Timed_out -> Error (Run_formal.Timeout, "Z3 CLI timed out")
      | Spawn_failed -> Error (Run_formal.Unavailable, "Z3 CLI spawn failed")
      | Supervision_failed ->
          Error (Run_formal.Unavailable, "Z3 CLI supervision failed")
      | Signalled signal ->
          Error
            (Run_formal.Unavailable,
             "Z3 CLI was signalled: " ^ string_of_int signal)
      | Exited code when code <> 0 ->
          Error
            (Run_formal.Unavailable,
             "Z3 CLI exited nonzero: " ^ string_of_int code)
      | Exited 0 when not process.child_created || not process.reaped ->
          Error (Run_formal.Unavailable, "Z3 CLI child was not reaped")
      | Exited 0 when String.trim process.stderr <> "" ->
          Error (Run_formal.Unavailable, "Z3 CLI emitted stderr diagnostics")
      | Exited 0 ->
          begin match String.trim process.stdout with
          | "sat" -> Ok Run_formal.Sat
          | "unsat" -> Ok Run_formal.Unsat
          | "unknown" -> Ok Run_formal.Unknown
          | _ -> Error (Run_formal.Unavailable, "malformed Z3 CLI result")
          end
      | Exited _ -> assert false

  let run_cli context configuration solver_version obligation =
    let process_result =
      with_query_file obligation.Run_formal.smt2 (fun path ->
        Ok
          (run_process configuration
             [| configuration.executable; "-smt2"; path |]))
    in
    let process, materialization, observed, diagnostics =
      match process_result with
      | Ok (process, materialization) ->
          begin match
            parse_cli_result process configuration.maximum_output_bytes
          with
          | Ok observed ->
              let diagnostics =
                if observed = Run_formal.Unknown then
                  [ make_diagnostic context ~code:"Z3-CLI-UNKNOWN"
                      ~detail:"Z3 CLI returned Unknown" ]
                else []
              in
              Some process, Some materialization, observed, diagnostics
          | Error (observed, detail) ->
              Some process, Some materialization, observed,
              [ make_diagnostic context ~code:"Z3-CLI-UNAVAILABLE" ~detail ]
          end
      | Error detail ->
          let process =
            make_process_receipt
              ~argv_digest:
                (digest_fields
                   [ configuration.executable; obligation.stable_id;
                     obligation.query_digest ])
              ~timeout_ms:configuration.timeout_ms ~elapsed_ns:0L
              ~status:Spawn_failed ~child_created:false ~term_sent:false
              ~kill_sent:false ~reaped:false
              (empty_output "") (empty_output detail)
          in
          Some process, None, Run_formal.Unavailable,
          [ make_diagnostic context ~code:"Z3-CLI-UNAVAILABLE" ~detail ]
    in
    make_backend_receipt ~backend:Injected_z3_cli ~obligation ~observed
      ~solver_timeout_ms:configuration.timeout_ms ~solver_version
      ~linked_library_version:None
      ~executable_path:(Some configuration.executable)
      ~executable_digest:(Some configuration.executable_digest)
      ~process ~materialization ~linked_invocation:None
      ~linked_request_digest:None ~linked_limits_digest:None
      ~linked_handshake_digest:None ~linked_result_digest:None ~diagnostics

  let cli_deadline_unavailable context (configuration : cli_configuration)
      solver_version obligation =
    let diagnostics =
      [ make_diagnostic context ~code:"Z3-CAMPAIGN-DEADLINE"
          ~detail:
            "CLI execution was not started before the total campaign deadline" ]
    in
    make_backend_receipt ~backend:Injected_z3_cli ~obligation
      ~observed:Run_formal.Unavailable
      ~solver_timeout_ms:configuration.timeout_ms ~solver_version
      ~linked_library_version:None
      ~executable_path:(Some configuration.executable)
      ~executable_digest:(Some configuration.executable_digest)
      ~process:None ~materialization:None ~linked_invocation:None
      ~linked_request_digest:None ~linked_limits_digest:None
      ~linked_handshake_digest:None ~linked_result_digest:None ~diagnostics

  let process_succeeded (process : process_receipt) =
    process.status = Exited 0 && process.child_created && process.reaped

  let parse_version text =
    match
      String.split_on_char ' ' (String.trim text)
      |> List.filter (fun token -> token <> "")
    with
    | "Z3" :: "version" :: version :: _ ->
        begin match String.split_on_char '.' version with
        | major :: minor :: _ ->
            begin match int_of_string_opt major, int_of_string_opt minor with
            | Some major, Some minor -> Ok (version, major, minor)
            | _ -> Error "Z3 version contains nonnumeric components"
            end
        | _ -> Error "Z3 version has fewer than two components"
        end
    | _ -> Error "Z3 version output is malformed"

  let version_allowed major minor = major = 4 && minor >= 12

  let exact_backend_order (rows : backend_receipt list) =
    List.length rows = List.length Run_formal.obligations
    && List.map (fun row -> row.obligation_stable_id) rows
       = List.map
           (fun (obligation : Run_formal.obligation) -> obligation.stable_id)
           Run_formal.obligations

  let obligation_kind_count kind =
    List.fold_left
      (fun count (obligation : Run_formal.obligation) ->
        if obligation.kind = kind then count + 1 else count)
      0 Run_formal.obligations

  let result_complete kind expected (rows : backend_receipt list) =
    exact_backend_order rows
    && List.for_all
         (fun row -> row.kind <> kind || row.observed = expected)
         rows
    && List.length (List.filter (fun row -> row.kind = kind) rows)
       = obligation_kind_count kind

  let cross_backend_agreement (linked : backend_receipt list)
      (cli : backend_receipt list) =
    exact_backend_order linked && exact_backend_order cli
    && List.for_all2
         (fun left right ->
           String.equal left.obligation_stable_id right.obligation_stable_id
           && left.observed = right.observed)
         linked cli

  let row_result_fields (row : backend_receipt) =
    [ row.obligation_stable_id; result_string row.observed; row.receipt_digest ]

  let memory_evidence_digest (evidence : memory_evidence) =
    digest_fields
      [ "run-analysis-z3-memory-evidence-v1"; evidence.envelope_digest;
        Int64.to_string evidence.allocated_before_bytes;
        Int64.to_string evidence.allocated_after_bytes;
        string_of_int evidence.heap_before_words;
        string_of_int evidence.heap_after_words;
        string_of_bool evidence.within_envelope;
        string_of_bool evidence.hard_isolated;
        Int64.to_string evidence.peak_rss_bytes;
        Int64.to_string evidence.virtual_memory_limit_bytes;
        string_of_int evidence.cpu_limit_seconds;
        evidence.worker_executable_digest; evidence.limits_digest ]

  let unavailable_memory_evidence (campaign : campaign_envelope) =
    let provisional =
      { envelope_digest = campaign.envelope_digest;
        allocated_before_bytes = 0L; allocated_after_bytes = 0L;
        heap_before_words = 0; heap_after_words = 0; within_envelope = false;
        hard_isolated = false; peak_rss_bytes = 0L;
        virtual_memory_limit_bytes = campaign.linked_virtual_memory_bytes;
        cpu_limit_seconds = campaign.linked_cpu_seconds;
        worker_executable_digest = campaign.linked_worker_executable_digest;
        limits_digest = ""; evidence_digest = "" }
    in
    { provisional with evidence_digest = memory_evidence_digest provisional }

  let measured_memory_evidence (campaign : campaign_envelope) evidences =
    match evidences with
    | [] -> unavailable_memory_evidence campaign
    | first :: _ ->
        let peak_rss_bytes =
          List.fold_left
            (fun peak evidence -> Int64.max peak evidence.peak_rss_bytes)
            0L evidences
        in
        let exact_denominator =
          List.length evidences = List.length Run_formal.obligations
        in
        let one_limits_identity =
          valid_digest first.limits_digest
          && List.for_all
               (fun evidence ->
                 String.equal evidence.limits_digest first.limits_digest)
               evidences
        in
        let within_envelope =
          exact_denominator && one_limits_identity
          && Int64.compare peak_rss_bytes 0L > 0
          && Int64.compare peak_rss_bytes campaign.maximum_worker_rss_bytes <= 0
          && Int64.compare peak_rss_bytes 1_073_741_824L < 0
        in
        let provisional =
          { envelope_digest = campaign.envelope_digest;
            allocated_before_bytes = 0L;
            allocated_after_bytes = peak_rss_bytes;
            heap_before_words = 0; heap_after_words = 0;
            within_envelope; hard_isolated = exact_denominator;
            peak_rss_bytes;
            virtual_memory_limit_bytes = campaign.linked_virtual_memory_bytes;
            cpu_limit_seconds = campaign.linked_cpu_seconds;
            worker_executable_digest = campaign.linked_worker_executable_digest;
            limits_digest = first.limits_digest; evidence_digest = "" }
        in
        { provisional with evidence_digest = memory_evidence_digest provisional }

  let receipt_result_digest (receipt : receipt) =
    digest_fields
      ([ "run-analysis-z3-result-v1";
         string_of_bool receipt.controls_complete;
         string_of_bool receipt.laws_complete;
         string_of_bool receipt.cross_backend_agreement;
         (match receipt.admission with Admitted -> "admitted" | Blocked -> "blocked");
         (match receipt.row_policy with
          | Preflight_fail_fast -> "preflight-fail-fast"
          | Campaign_deadline_partial -> "campaign-deadline-partial"
          | Full_denominator -> "full-denominator");
         receipt.memory_evidence.evidence_digest ]
       @ List.concat_map row_result_fields receipt.in_process
       @ List.concat_map row_result_fields receipt.cli
       @ List.map
           (fun (diagnostic : diagnostic) -> diagnostic.diagnostic_digest)
           receipt.diagnostics)

  let receipt_digest (receipt : receipt) =
    digest_fields
      ([ "run-analysis-z3-receipt-v1"; receipt.context_digest;
         receipt.current_head_digest; Int64.to_string receipt.current_at_ns;
         receipt.specification_digest; receipt.obligation_set_digest;
         receipt.cli_configuration_digest;
         receipt.campaign_envelope_digest;
         Int64.to_string receipt.campaign_elapsed_ns;
         string_of_bool receipt.campaign_deadline_exhausted;
         receipt.cli_version_process.receipt_digest; receipt.result_digest ]
       @ List.map
           (fun (row : backend_receipt) -> row.receipt_digest)
           receipt.in_process
       @ List.map
           (fun (row : backend_receipt) -> row.receipt_digest)
           receipt.cli)

  let build_receipt (context : Run_safety.gate_context)
      (campaign : campaign_envelope) (configuration : cli_configuration)
      (version_process : process_receipt)
      (in_process : backend_receipt list) (cli : backend_receipt list)
      (diagnostics : diagnostic list) ~(linked_evidence : linked_row_evidence list)
      ~campaign_elapsed_ns ~campaign_deadline_exhausted =
    let controls_complete =
      result_complete Run_formal.False_control Run_formal.Sat in_process
      && result_complete Run_formal.False_control Run_formal.Sat cli
    in
    let laws_complete =
      result_complete Run_formal.Negated_law Run_formal.Unsat in_process
      && result_complete Run_formal.Negated_law Run_formal.Unsat cli
    in
    let agreement = cross_backend_agreement in_process cli in
    let all_processes_succeeded =
      process_succeeded version_process
      && List.for_all
           (fun (row : backend_receipt) ->
             Option.fold ~none:false ~some:process_succeeded row.process)
           (in_process @ cli)
    in
    let no_diagnostics =
      diagnostics = []
      && List.for_all
           (fun (row : backend_receipt) -> row.diagnostics = [])
           (in_process @ cli)
    in
    let memory_evidence = measured_memory_evidence campaign linked_evidence in
    let admission =
      if controls_complete && laws_complete && agreement
         && all_processes_succeeded && no_diagnostics
         && memory_evidence.hard_isolated && memory_evidence.within_envelope
      then Admitted else Blocked
    in
    let row_policy =
      if in_process = [] && cli = [] then Preflight_fail_fast
      else if exact_backend_order in_process && exact_backend_order cli
              && campaign_deadline_exhausted
      then Campaign_deadline_partial
      else Full_denominator
    in
    let provisional =
      { authority = Run_safety.Load_bearing_dispatch_gate;
        context_digest = context.Run_safety.context_digest;
        current_head_digest = context.current_head_digest;
        current_at_ns = context.current_at_ns;
        specification_digest = Run_formal.specification_digest;
        obligation_set_digest = obligation_set_digest ();
        cli_configuration_digest = configuration.configuration_digest;
        campaign_envelope_digest = campaign.envelope_digest;
        campaign_elapsed_ns; campaign_deadline_exhausted;
        cli_version_process = version_process; in_process; cli;
        controls_complete; laws_complete;
        cross_backend_agreement = agreement; admission; diagnostics;
        row_policy; memory_evidence;
        result_digest = ""; receipt_digest = "" }
    in
    let with_result =
      { provisional with result_digest = receipt_result_digest provisional }
    in
    { with_result with receipt_digest = receipt_digest with_result }

  let blocked_without_rows context campaign configuration version_process diagnostics =
    build_receipt context campaign configuration version_process [] [] diagnostics
      ~linked_evidence:[] ~campaign_elapsed_ns:0L
      ~campaign_deadline_exhausted:false

  let verify (context : Run_safety.gate_context) ~campaign configuration =
    let campaign_started = Mtime_clock.elapsed_ns () in
    let campaign_deadline =
      monotonic_add campaign_started
        (ns_of_ms campaign.maximum_total_elapsed_ms)
    in
    let formal_gaps = Run_formal.validate () in
    if formal_gaps <> [] then
      Error
        (analysis_error context ~code:Run_safety.Invalid_model
           ~message:("formal obligation authority is invalid: "
                     ^ String.concat "; " formal_gaps)
           ~rca_origin:Ops_capability.Specification ~hazard_id:"HZ-T6-Z3-01")
    else
    let version_process =
      run_process ~timeout_ms:configuration.version_probe_timeout_ms
        configuration [| configuration.executable; "-version" |]
    in
    let executable_current =
      match digest_file configuration.executable with
      | Ok digest -> String.equal digest configuration.executable_digest
      | Error _ -> false
    in
    if not executable_current then
      Ok
        (blocked_without_rows context campaign configuration version_process
           [ make_diagnostic context ~code:"Z3-EXECUTABLE-CHANGED"
               ~detail:"Z3 executable content differs from admitted configuration" ])
    else if not (process_succeeded version_process) then
      Ok
        (blocked_without_rows context campaign configuration version_process
           [ make_diagnostic context ~code:"Z3-VERSION-UNAVAILABLE"
               ~detail:"Z3 version probe was not successful and reaped" ])
    else if version_process.stdout_bytes > configuration.maximum_output_bytes
            || version_process.stderr_bytes > configuration.maximum_output_bytes
            || String.trim version_process.stderr <> ""
    then
      Ok
        (blocked_without_rows context campaign configuration version_process
           [ make_diagnostic context ~code:"Z3-VERSION-OUTPUT-BOUND"
               ~detail:"Z3 version probe exceeded its output bound" ])
    else
      match parse_version version_process.stdout with
      | Error detail ->
          Ok
            (blocked_without_rows context campaign configuration version_process
               [ make_diagnostic context ~code:"Z3-VERSION-MALFORMED" ~detail ])
      | Ok (solver_version, major, minor)
        when not (version_allowed major minor) ->
          Ok
            (blocked_without_rows context campaign configuration version_process
               [ make_diagnostic context ~code:"Z3-UNSUPPORTED-VERSION"
                   ~detail:("unsupported Z3 version: " ^ solver_version) ])
      | Ok (_solver_version, _, _)
        when not
          (version_allowed Analysis_linked_z3.Version.major
             Analysis_linked_z3.Version.minor) ->
          Ok
            (blocked_without_rows context campaign configuration version_process
               [ make_diagnostic context ~code:"Z3-LINKED-UNSUPPORTED-VERSION"
                   ~detail:("unsupported linked Z3 version: " ^ linked_version) ])
      | Ok (solver_version, _, _) ->
          let linked_runs =
            List.map
              (run_linked context campaign campaign_deadline)
              Run_formal.obligations
          in
          let in_process = List.map fst linked_runs in
          let linked_evidence = List.filter_map snd linked_runs in
          let cli_deadline_exhausted = ref false in
          let rec run_cli_until_deadline rows = function
            | [] -> List.rev rows
            | obligation :: remaining ->
                if Int64.compare (Mtime_clock.elapsed_ns ()) campaign_deadline >= 0
                then begin
                  cli_deadline_exhausted := true;
                  List.rev rows
                  @ List.map
                      (cli_deadline_unavailable context configuration
                         solver_version)
                      (obligation :: remaining)
                end
                else
                  let row =
                    run_cli context configuration solver_version obligation
                  in
                  run_cli_until_deadline (row :: rows) remaining
          in
          let cli = run_cli_until_deadline [] Run_formal.obligations in
          let campaign_elapsed_ns =
            max 0L
              (Int64.sub (Mtime_clock.elapsed_ns ()) campaign_started)
          in
          let campaign_deadline_exhausted = !cli_deadline_exhausted in
          let deadline_diagnostics =
            if campaign_deadline_exhausted then
              [ make_diagnostic context ~code:"Z3-CAMPAIGN-DEADLINE"
                  ~detail:"the total dual-backend campaign deadline was exhausted" ]
            else []
          in
          let diagnostics =
            List.concat_map
              (fun (row : backend_receipt) -> row.diagnostics)
              (in_process @ cli)
            @ deadline_diagnostics
          in
          Ok
            (build_receipt context campaign configuration version_process in_process cli
               diagnostics ~linked_evidence ~campaign_elapsed_ns
               ~campaign_deadline_exhausted)

  let process_receipt_valid_for ~timeout_valid ~maximum_output_bytes
      (receipt : process_receipt) =
    String.equal receipt.receipt_digest (process_receipt_digest receipt)
    && valid_digest receipt.argv_digest && valid_digest receipt.stdout_digest
    && valid_digest receipt.stderr_digest
    && timeout_valid receipt.timeout_ms
    && receipt.elapsed_ns >= 0L
    && receipt.stdout_bytes >= String.length receipt.stdout
    && receipt.stderr_bytes >= String.length receipt.stderr
    && String.length receipt.stdout <= maximum_output_bytes
    && String.length receipt.stderr <= maximum_output_bytes
    && (if receipt.stdout_bytes <= maximum_output_bytes then
          receipt.stdout_bytes = String.length receipt.stdout
          && String.equal receipt.stdout_digest (sha256 receipt.stdout)
        else String.length receipt.stdout = maximum_output_bytes)
    && (if receipt.stderr_bytes <= maximum_output_bytes then
          receipt.stderr_bytes = String.length receipt.stderr
          && String.equal receipt.stderr_digest (sha256 receipt.stderr)
        else String.length receipt.stderr = maximum_output_bytes)
    && match receipt.status with
       | Exited _ | Signalled _ | Timed_out | Supervision_failed ->
           receipt.child_created && receipt.reaped
       | Spawn_failed -> not receipt.child_created && not receipt.reaped

  let process_receipt_valid (configuration : cli_configuration) receipt =
    process_receipt_valid_for
      ~timeout_valid:(fun timeout -> timeout = configuration.timeout_ms)
      ~maximum_output_bytes:configuration.maximum_output_bytes receipt

  let version_process_receipt_valid (configuration : cli_configuration) receipt =
    process_receipt_valid_for
      ~timeout_valid:(fun timeout ->
        timeout = configuration.version_probe_timeout_ms)
      ~maximum_output_bytes:configuration.maximum_output_bytes receipt

  let obligation_for stable_id =
    List.find_opt
      (fun (obligation : Run_formal.obligation) ->
        String.equal obligation.stable_id stable_id)
      Run_formal.obligations

  let count_occurrences value needle =
    let value_length = String.length value in
    let needle_length = String.length needle in
    let rec count offset total =
      if needle_length = 0 || offset + needle_length > value_length then total
      else if String.sub value offset needle_length = needle then
        count (offset + needle_length) (total + 1)
      else count (offset + 1) total
    in
    count 0 0

  type reconstructed_linked = {
    linked_request : Linked_protocol.request;
    linked_handshake : Linked_protocol.handshake;
    linked_result : Linked_protocol.result;
  }

  let reconstruct_linked campaign obligation process =
    match
      Linked_protocol.make_limits
        ~virtual_memory_bytes:campaign.linked_virtual_memory_bytes
        ~cpu_seconds:campaign.linked_cpu_seconds
        ~maximum_query_bytes:campaign.linked_maximum_query_bytes
        ~maximum_output_bytes:campaign.linked_maximum_output_bytes,
      Linked_protocol.sha256_of_hex campaign.linked_worker_executable_digest
    with
    | Error _, _ | _, Error _ -> None
    | Ok limits, Ok worker_executable_digest ->
        begin match
          Linked_protocol.prepare ~obligation_id:obligation.Run_formal.stable_id
            ~worker_executable_digest ~query:obligation.smt2 ~limits
        with
        | Error _ -> None
        | Ok prepared ->
            let expected_argv =
              Array.append [| campaign.linked_worker_executable |]
                (Linked_protocol.argv prepared)
            in
            let expected_argv_digest =
              digest_fields
                ("run-analysis-z3-linked-argv-v1" :: "empty-environment"
                 :: Array.to_list expected_argv)
            in
            if not (String.equal process.argv_digest expected_argv_digest) then None
            else
              match
                Linked_protocol.decode_argv (Linked_protocol.argv prepared),
                Linked_protocol.admit_stdin prepared.request
                  (Linked_protocol.stdin_bytes prepared),
                Linked_protocol.decode_transcript
                  ~maximum_bytes:campaign.linked_maximum_output_bytes
                  process.stdout
              with
              | Ok decoded_request, Ok query,
                Ok (Linked_protocol.Completed { handshake; result })
                when decoded_request = prepared.request
                     && Linked_protocol.validate_handshake
                          ~request:prepared.request handshake = []
                     && Linked_protocol.validate_result ~request:prepared.request
                          ~query ~handshake result = [] ->
                  Some
                    { linked_request = prepared.request;
                      linked_handshake = handshake; linked_result = result }
              | _ -> None
        end

  let linked_invocation_valid obligation result_digest assertion_count = function
    | None -> false
    | Some invocation ->
        let expected_assertion_count =
          count_occurrences obligation.Run_formal.smt2 "(assert "
        in
        invocation.solver_calls_before = 0
        && invocation.solver_calls_after = 1
        && invocation.solver_call_delta = 1
        && assertion_count = expected_assertion_count
        && invocation.assertion_count = expected_assertion_count
        && String.equal invocation.invocation_digest
             (digest_fields
                [ "run-analysis-z3-linked-invocation-v1";
                  obligation.Run_formal.stable_id; "1";
                  string_of_int invocation.assertion_count; result_digest ])

  let linked_transcript_valid campaign obligation row process =
    match reconstruct_linked campaign obligation process with
    | None -> false
    | Some evidence ->
        let request = evidence.linked_request in
        let handshake = evidence.linked_handshake in
        let result = evidence.linked_result in
        let result_digest = Linked_protocol.sha256_to_hex result.result_digest in
        let capture = result.capture in
        let before = capture.file_object_before in
        let after = capture.file_object_after in
        let object_identity_stable = before = after in
        let object_identity_digest =
          digest_fields
            [ "run-analysis-z3-query-object-v1";
              string_of_int before.device; string_of_int before.inode;
              string_of_int after.device; string_of_int after.inode;
              string_of_bool object_identity_stable ]
        in
        let observed =
          match result.answer with
          | Linked_protocol.Sat -> Run_formal.Sat
          | Unsat -> Run_formal.Unsat
          | Unknown -> Run_formal.Unknown
        in
        row.observed = observed
        && String.equal row.solver_version result.solver_version
        && row.linked_request_digest =
             Some (Linked_protocol.sha256_to_hex request.request_digest)
        && row.linked_limits_digest =
             Some (Linked_protocol.sha256_to_hex request.limits.limits_digest)
        && row.linked_handshake_digest =
             Some (Linked_protocol.sha256_to_hex handshake.handshake_digest)
        && row.linked_result_digest = Some result_digest
        && String.equal row.executed_query_digest
             (Linked_protocol.sha256_to_hex result.executed_query_digest)
        && String.equal row.readback_query_digest
             (Linked_protocol.sha256_to_hex capture.readback_digest)
        && row.readback_query_bytes = capture.readback_bytes
        && row.query_object_identity_stable = object_identity_stable
        && String.equal row.query_object_identity_digest object_identity_digest
        && result.solver_call_delta = 1
        && linked_invocation_valid obligation result_digest
             result.assertion_count row.linked_invocation

  let backend_receipt_valid (context : Run_safety.gate_context)
      (campaign : campaign_envelope) (configuration : cli_configuration)
      (row : backend_receipt) =
    match obligation_for row.obligation_stable_id with
    | None -> false
    | Some obligation ->
        String.equal row.requirement_id obligation.requirement_id
        && row.kind = obligation.kind && row.expected = obligation.expected
        && String.equal row.query_digest obligation.query_digest
        && row.query_bytes = String.length obligation.smt2
        && row.obligation_timeout_ms = obligation.timeout_ms
        && String.equal row.solver_id obligation.solver_id
        && String.equal row.solver_version_constraint
             obligation.solver_version_constraint
        && (row.observed = Run_formal.Unavailable
            || query_execution_admissible
                 ~authoritative_digest:obligation.query_digest
                 ~executed_digest:row.executed_query_digest
                 ~readback_digest:row.readback_query_digest
                 ~authoritative_bytes:(String.length obligation.smt2)
                 ~readback_bytes:row.readback_query_bytes
                 ~object_identity_stable:row.query_object_identity_stable)
        && List.for_all (diagnostic_valid context) row.diagnostics
        && String.equal row.receipt_digest (backend_receipt_digest row)
        && match row.backend with
           | Linked_smtml_z3 ->
               row.solver_timeout_ms = obligation.timeout_ms
               && String.equal row.solver_version linked_version
               && row.linked_library_version = Some linked_library_version
               && row.executable_path = Some campaign.linked_worker_executable
               && row.executable_digest =
                    Some campaign.linked_worker_executable_digest
               && ((Option.fold ~none:false
                      ~some:(fun process ->
                        process_receipt_valid_for
                          ~timeout_valid:(fun timeout ->
                            timeout > 0 && timeout <= obligation.timeout_ms)
                          ~maximum_output_bytes:
                            campaign.linked_maximum_output_bytes process
                        && linked_transcript_valid campaign obligation row process)
                      row.process)
                   || (row.observed = Run_formal.Unavailable
                       && row.process = None
                       && row.linked_invocation = None
                       && row.linked_request_digest = None
                       && row.linked_limits_digest = None
                       && row.linked_handshake_digest = None
                       && row.linked_result_digest = None
                       && row.executed_query_digest = ""
                       && row.readback_query_digest = ""
                       && row.readback_query_bytes = 0
                       && List.exists
                            (fun diagnostic ->
                              String.equal diagnostic.code
                                "Z3-LINKED-UNAVAILABLE"
                              && String.equal diagnostic.detail
                                   "campaign deadline exhausted")
                            row.diagnostics))
           | Injected_z3_cli ->
               row.solver_timeout_ms = configuration.timeout_ms
               && row.linked_library_version = None
               && row.executable_path = Some configuration.executable
               && row.executable_digest = Some configuration.executable_digest
               && row.linked_invocation = None
               && row.linked_request_digest = None
               && row.linked_limits_digest = None
               && row.linked_handshake_digest = None
               && row.linked_result_digest = None
               && (Option.fold ~none:false
                     ~some:(process_receipt_valid configuration) row.process
                   || (row.observed = Run_formal.Unavailable
                       && row.process = None
                       && row.executed_query_digest = ""
                       && row.readback_query_digest = ""
                       && row.readback_query_bytes = 0
                       && not row.query_object_identity_stable
                       && List.exists
                            (fun diagnostic ->
                              String.equal diagnostic.code
                                "Z3-CAMPAIGN-DEADLINE")
                            row.diagnostics))

  let recompute_memory_evidence campaign rows =
    let evidences =
      List.filter_map
        (fun (row : backend_receipt) ->
          match obligation_for row.obligation_stable_id, row.process with
          | Some obligation, Some process ->
              begin match reconstruct_linked campaign obligation process with
              | None -> None
              | Some evidence ->
                  Some
                    { peak_rss_bytes = evidence.linked_result.peak_rss_bytes;
                      limits_digest =
                        Linked_protocol.sha256_to_hex
                          evidence.linked_request.limits.limits_digest }
              end
          | _ -> None)
        rows
    in
    measured_memory_evidence campaign evidences

  let validate_receipt ~(context : Run_safety.gate_context)
      ~(campaign : campaign_envelope) (configuration : cli_configuration)
      (receipt : receipt) =
    let expected_controls =
      result_complete Run_formal.False_control Run_formal.Sat receipt.in_process
      && result_complete Run_formal.False_control Run_formal.Sat receipt.cli
    in
    let expected_laws =
      result_complete Run_formal.Negated_law Run_formal.Unsat receipt.in_process
      && result_complete Run_formal.Negated_law Run_formal.Unsat receipt.cli
    in
    let expected_agreement =
      cross_backend_agreement receipt.in_process receipt.cli
    in
    let expected_memory_evidence =
      recompute_memory_evidence campaign receipt.in_process
    in
    let expected_row_policy =
      if receipt.in_process = [] && receipt.cli = [] then Preflight_fail_fast
      else if exact_backend_order receipt.in_process
              && exact_backend_order receipt.cli
              && receipt.campaign_deadline_exhausted
      then Campaign_deadline_partial
      else Full_denominator
    in
    let expected_admission =
      if expected_controls && expected_laws && expected_agreement
         && process_succeeded receipt.cli_version_process
         && List.for_all
              (fun (row : backend_receipt) ->
                Option.fold ~none:false ~some:process_succeeded row.process)
              (receipt.in_process @ receipt.cli)
         && receipt.diagnostics = []
         && List.for_all
              (fun (row : backend_receipt) -> row.diagnostics = [])
              (receipt.in_process @ receipt.cli)
         && expected_memory_evidence.hard_isolated
         && expected_memory_evidence.within_envelope
      then Admitted else Blocked
    in
    if not
         (String.equal context.context_digest receipt.context_digest
          && String.equal context.current_head_digest receipt.current_head_digest
          && context.current_at_ns = receipt.current_at_ns)
    then
      Error
        (analysis_error context ~code:Run_safety.Context_mismatch
           ~message:"Z3 receipt context mismatch"
           ~rca_origin:Ops_capability.Control ~hazard_id:"HZ-T6-Z3-01")
    else if receipt.authority <> Run_safety.Load_bearing_dispatch_gate
            || not
                 (String.equal receipt.specification_digest
                    Run_formal.specification_digest)
            || not
                 (String.equal receipt.obligation_set_digest
                    (obligation_set_digest ()))
            || not
                 (String.equal receipt.cli_configuration_digest
                    configuration.configuration_digest)
            || not
                 (String.equal receipt.campaign_envelope_digest
                    campaign.envelope_digest)
            || not
                 (String.equal receipt.memory_evidence.envelope_digest
                    campaign.envelope_digest)
            || not
                 (String.equal receipt.memory_evidence.evidence_digest
                    (memory_evidence_digest receipt.memory_evidence))
            || receipt.memory_evidence <> expected_memory_evidence
            || receipt.memory_evidence.virtual_memory_limit_bytes
               <> campaign.linked_virtual_memory_bytes
            || receipt.memory_evidence.cpu_limit_seconds
               <> campaign.linked_cpu_seconds
            || not
                 (String.equal receipt.memory_evidence.worker_executable_digest
                    campaign.linked_worker_executable_digest)
            || (receipt.memory_evidence.hard_isolated
                && (not (valid_digest receipt.memory_evidence.limits_digest)
                    || Int64.compare receipt.memory_evidence.peak_rss_bytes 0L <= 0
                    || Int64.compare receipt.memory_evidence.peak_rss_bytes
                         campaign.maximum_worker_rss_bytes > 0
                    || Int64.compare receipt.memory_evidence.peak_rss_bytes
                         1_073_741_824L >= 0))
            || (receipt.memory_evidence.hard_isolated
                && not
                     (List.for_all
                        (fun (row : backend_receipt) ->
                          row.linked_limits_digest
                            = Some receipt.memory_evidence.limits_digest
                          || (row.observed = Run_formal.Unavailable
                              && row.linked_limits_digest = None
                              && row.process = None))
                        receipt.in_process))
            || not
                 (version_process_receipt_valid configuration
                    receipt.cli_version_process)
            || not
                 (List.for_all
                    (backend_receipt_valid context campaign configuration)
                    (receipt.in_process @ receipt.cli))
            || not (List.for_all (diagnostic_valid context) receipt.diagnostics)
            || receipt.controls_complete <> expected_controls
            || receipt.laws_complete <> expected_laws
            || receipt.cross_backend_agreement <> expected_agreement
            || receipt.admission <> expected_admission
            || receipt.row_policy <> expected_row_policy
            || receipt.campaign_elapsed_ns < 0L
            || receipt.campaign_elapsed_ns
              > ns_of_ms
                   (campaign.maximum_total_elapsed_ms
                    + campaign.maximum_teardown_ms
                    + campaign.maximum_receipt_materialization_ms)
            || not
                 (String.equal receipt.result_digest
                    (receipt_result_digest receipt))
            || not
                 (String.equal receipt.receipt_digest (receipt_digest receipt))
    then
      Error
        (analysis_error context ~code:Run_safety.Invalid_receipt
           ~message:"Z3 receipt identity or admission is invalid"
           ~rca_origin:Ops_capability.Evidence ~hazard_id:"HZ-T6-Z3-01")
    else Ok ()

  module For_test = struct
    type receipt_mutation =
      | Positive_wrong_assertion_count
      | Substituted_linked_request_digest
      | Substituted_linked_handshake_digest
      | Substituted_linked_result_digest

    let substituted_digest value = sha256 ("z3-for-test-mutant:" ^ value)

    let reseal_row (row : backend_receipt) =
      let provisional = { row with receipt_digest = "" } in
      { provisional with receipt_digest = backend_receipt_digest provisional }

    let reseal_receipt (receipt : receipt) in_process =
      let provisional =
        { receipt with in_process; result_digest = ""; receipt_digest = "" }
      in
      let with_result =
        { provisional with result_digest = receipt_result_digest provisional }
      in
      { with_result with receipt_digest = receipt_digest with_result }

    let reseal_invocation obligation_id result_digest invocation =
      { invocation with
        invocation_digest =
          digest_fields
            [ "run-analysis-z3-linked-invocation-v1"; obligation_id;
              string_of_int invocation.solver_call_delta;
              string_of_int invocation.assertion_count; result_digest ] }

    let mutate_row mutation (row : backend_receipt) =
      match mutation with
      | Positive_wrong_assertion_count ->
          begin match row.linked_invocation, row.linked_result_digest with
          | Some invocation, Some result_digest ->
              let provisional =
                { invocation with
                  assertion_count = max 1 (invocation.assertion_count + 1) }
              in
              reseal_row
                { row with
                  linked_invocation =
                    Some
                      (reseal_invocation row.obligation_stable_id result_digest
                         provisional) }
          | _ -> row
          end
      | Substituted_linked_request_digest ->
          begin match row.linked_request_digest with
          | None -> row
          | Some digest ->
              reseal_row
                { row with
                  linked_request_digest = Some (substituted_digest digest) }
          end
      | Substituted_linked_handshake_digest ->
          begin match row.linked_handshake_digest with
          | None -> row
          | Some digest ->
              reseal_row
                { row with
                  linked_handshake_digest = Some (substituted_digest digest) }
          end
      | Substituted_linked_result_digest ->
          begin match row.linked_result_digest, row.linked_invocation with
          | Some digest, Some invocation ->
              let result_digest = substituted_digest digest in
              reseal_row
                { row with linked_result_digest = Some result_digest;
                  linked_invocation =
                    Some
                      (reseal_invocation row.obligation_stable_id result_digest
                         invocation) }
          | _ -> row
          end

    let mutate_receipt mutation receipt =
      match receipt.in_process with
      | [] -> receipt
      | row :: remaining ->
          reseal_receipt receipt (mutate_row mutation row :: remaining)
  end
end

type z3_receipt = Z3.receipt
