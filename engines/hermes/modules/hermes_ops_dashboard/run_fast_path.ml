type strategy = Reference | Incremental | Snapshot_then_suffix | Aggregated_graph
type semantic_oracle = { id : string; digest : string }
type resource_budget = { max_age_ns : int64; future_tolerance_ns : int64;
  max_cost : float }
type cost_evidence = Measured_cost of { value : float; sampled_at_ns : int64;
    receipt_digest : string }
  | Estimated_cost of { value : float; estimated_at_ns : int64; model_digest : string }
  | Cost_unavailable of { reason : string }
type admission = Gate_admitted of { gate_id : string; receipt_digest : string }
  | Gate_not_admitted of { gate_id : string; reason : string }
type fallback_kind = Missing_or_unavailable | Stale | Malformed | Out_of_domain
  | Non_equivalent | Not_admitted | Cost_exceeded
type diagnostic = { kind : fallback_kind; message : string;
  coordinate : Ops_capability.coordinate; rca_origin : Ops_capability.rca_origin }
type reason = Below_low | Above_high | Hysteresis_hold | Reference_fallback
type policy = { version : string; metric_id : string; low_threshold : float;
  high_threshold : float; oracle : semantic_oracle;
  equivalent_strategies : (strategy * string) list; budget : resource_budget;
  admission : admission }
type decision = { strategy : strategy; reason : reason;
  observation_digest : string option; cost_digest : string option; policy_digest : string;
  threshold_version : string; oracle : semantic_oracle; budget : resource_budget;
  decided_at_ns : int64; diagnostic : diagnostic option }

type selection = {
  context_digest : string;
  activity_digest : string;
  activity_authority_digest : string;
  decision : decision;
  selection_digest : string;
}

let finite value = match classify_float value with
  | FP_nan | FP_infinite -> false
  | FP_normal | FP_subnormal | FP_zero -> true

let strategy_string = function
  | Reference -> "reference" | Incremental -> "incremental"
  | Snapshot_then_suffix -> "snapshot-then-suffix"
  | Aggregated_graph -> "aggregated-graph"

let sha256 text = text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let policy_json policy =
  let admission = match policy.admission with
    | Gate_admitted { gate_id; receipt_digest } ->
        `Assoc [ ("gate_id", `String gate_id); ("kind", `String "admitted");
                 ("receipt_digest", `String receipt_digest) ]
    | Gate_not_admitted { gate_id; reason } ->
        `Assoc [ ("gate_id", `String gate_id); ("kind", `String "not-admitted");
                 ("reason", `String reason) ] in
  `Assoc
    [ ("admission", admission);
      ("budget", `Assoc [ ("max_age_ns", `Intlit (Int64.to_string policy.budget.max_age_ns));
                           ("future_tolerance_ns",
                            `Intlit (Int64.to_string policy.budget.future_tolerance_ns));
                           ("max_cost", `Float policy.budget.max_cost) ]);
      ("equivalent_strategies", `List
         (List.map (fun (strategy, digest) ->
              `Assoc [ ("digest", `String digest);
                       ("strategy", `String (strategy_string strategy)) ])
            (List.sort
               (fun (left, _) (right, _) ->
                 String.compare (strategy_string left) (strategy_string right))
               policy.equivalent_strategies)));
      ("high_threshold", `Float policy.high_threshold);
      ("low_threshold", `Float policy.low_threshold);
      ("metric_id", `String policy.metric_id);
      ("oracle", `Assoc [ ("digest", `String policy.oracle.digest);
                           ("id", `String policy.oracle.id) ]);
      ("version", `String policy.version) ]

let policy_digest policy =
  match Run_model.canonical_string (policy_json policy) with
  | Ok text -> sha256 text
  | Error error -> sha256 ("invalid-policy:" ^ error)

let is_hex = function '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true | _ -> false
let valid_digest value = String.length value = 64 && String.for_all is_hex value
let nonempty value = String.trim value <> ""

let validate_policy policy =
  if not (nonempty policy.version && nonempty policy.metric_id
          && nonempty policy.oracle.id && valid_digest policy.oracle.digest) then
    Error (Malformed, "policy identity or oracle digest is invalid")
  else if not (finite policy.low_threshold && finite policy.high_threshold
               && policy.low_threshold < policy.high_threshold) then
    Error (Malformed, "thresholds must be finite and strictly ordered")
  else if policy.budget.max_age_ns <= 0L || policy.budget.future_tolerance_ns < 0L
          || not (finite policy.budget.max_cost)
          || policy.budget.max_cost < 0. then
    Error (Malformed, "resource budget is invalid")
  else
    let names = List.map (fun (strategy, _) -> strategy_string strategy)
        policy.equivalent_strategies in
    if List.length names <> List.length (List.sort_uniq String.compare names) then
      Error (Malformed, "equivalent strategies must be unique")
    else if List.exists (fun (strategy, digest) -> strategy = Reference || not (valid_digest digest))
        policy.equivalent_strategies then
      Error (Malformed, "equivalence receipts must name non-reference strategies and valid digests")
    else match policy.admission with
      | Gate_not_admitted { gate_id; reason } when nonempty gate_id && nonempty reason ->
          Error (Not_admitted, "admission gate refused: " ^ reason)
      | Gate_not_admitted _ -> Error (Malformed, "admission refusal must be explained")
      | Gate_admitted { gate_id; receipt_digest }
        when nonempty gate_id && valid_digest receipt_digest -> Ok ()
      | Gate_admitted _ -> Error (Malformed, "admission receipt is invalid")

let fallback ?cost_digest policy observation ~now_ns kind message =
  { strategy = Reference; reason = Reference_fallback;
    observation_digest = Some (Run_metrics.observation_digest observation);
    cost_digest;
    policy_digest = policy_digest policy; threshold_version = policy.version;
    oracle = policy.oracle; budget = policy.budget; decided_at_ns = now_ns;
    diagnostic = Some { kind; message; coordinate = observation.Run_metrics.coordinate;
                        rca_origin = Ops_capability.Control } }

let equivalent (policy : policy) strategy =
  strategy = Reference
  || List.exists
       (fun (candidate, digest) -> candidate = strategy && String.equal digest policy.oracle.digest)
       policy.equivalent_strategies

let cost_json = function
  | Measured_cost { value; sampled_at_ns; receipt_digest } ->
      `Assoc [ ("kind", `String "measured");
               ("receipt_digest", `String receipt_digest);
               ("sampled_at_ns", `Intlit (Int64.to_string sampled_at_ns));
               ("value", `String (Printf.sprintf "%.17g" value)) ]
  | Estimated_cost { value; estimated_at_ns; model_digest } ->
      `Assoc [ ("estimated_at_ns", `Intlit (Int64.to_string estimated_at_ns));
               ("kind", `String "estimated");
               ("model_digest", `String model_digest);
               ("value", `String (Printf.sprintf "%.17g" value)) ]
  | Cost_unavailable { reason } ->
      `Assoc [ ("kind", `String "unavailable-observed"); ("reason", `String reason) ]

let cost_digest cost =
  match Run_model.canonical_string (cost_json cost) with
  | Ok text -> sha256 text
  | Error error -> sha256 ("invalid-cost:" ^ error)

let validate_cost budget ~now_ns = function
  | Cost_unavailable { reason } ->
      if nonempty reason then Error (Missing_or_unavailable, reason)
      else Error (Malformed, "unavailable cost evidence requires a reason")
  | Measured_cost { value; sampled_at_ns; receipt_digest } ->
      if not (finite value) || value < 0. || not (valid_digest receipt_digest) then
        Error (Malformed, "measured cost evidence is malformed")
      else if now_ns < 0L || sampled_at_ns < 0L
              || (sampled_at_ns > now_ns
                  && Int64.sub sampled_at_ns now_ns > budget.future_tolerance_ns)
              || (sampled_at_ns <= now_ns
                  && Int64.sub now_ns sampled_at_ns > budget.max_age_ns) then
        Error (Stale, "measured cost evidence is outside the freshness budget")
      else if value > budget.max_cost then
        Error (Cost_exceeded, "measured cost exceeds the fast-path budget")
      else Ok ()
  | Estimated_cost { value; estimated_at_ns; model_digest } ->
      if not (finite value) || value < 0. || not (valid_digest model_digest) then
        Error (Malformed, "estimated cost evidence is malformed")
      else if now_ns < 0L || estimated_at_ns < 0L
              || (estimated_at_ns > now_ns
                  && Int64.sub estimated_at_ns now_ns > budget.future_tolerance_ns)
              || (estimated_at_ns <= now_ns
                  && Int64.sub now_ns estimated_at_ns > budget.max_age_ns) then
        Error (Stale, "estimated cost evidence is outside the freshness budget")
      else if value > budget.max_cost then
        Error (Cost_exceeded, "estimated cost exceeds the fast-path budget")
      else Ok ()

let choose policy ~previous ~now_ns ~cost observation =
  let cost_digest = cost_digest cost in
  let fallback kind message =
    fallback ~cost_digest policy observation ~now_ns kind message
  in
  match validate_policy policy with
  | Error (kind, message) -> fallback kind message
  | Ok () ->
      let sampled_at = Run_metrics.sampled_at_ns observation in
      if not (String.equal observation.metric_id policy.metric_id) then
        fallback Malformed "observation metric does not match policy"
      else match Run_metrics.validate_observation ~now_ns observation with
        | Error message ->
            let kind =
              if String.equal message "metric sample is stale"
                 || String.equal message "metric sample exceeds its future tolerance"
              then Stale else Malformed
            in
            fallback kind message
        | Ok () when sampled_at <= now_ns
                     && Int64.sub now_ns sampled_at > policy.budget.max_age_ns ->
            fallback Stale "observation is outside the fast-path freshness budget"
        | Ok () -> begin match validate_cost policy.budget ~now_ns cost with
          | Error (kind, message) -> fallback kind message
          | Ok () ->
            match observation.sample with
            | Run_metrics.Unavailable_observed { reason; _ } ->
                fallback Missing_or_unavailable reason
            | Measured { value; _ } ->
                let numeric = match value with
                  | Int value -> Ok (Int64.to_float value)
                  | Float value when finite value -> Ok value
                  | Float _ -> Error "non-finite observation is outside the fast-path domain"
                  | State _ -> Error "state-valued observation is outside the numeric fast-path domain"
                in
                begin match numeric with
                | Error message -> fallback Out_of_domain message
                | Ok numeric ->
                let candidate, reason =
                  if numeric <= policy.low_threshold then Incremental, Below_low
                  else if numeric >= policy.high_threshold then Snapshot_then_suffix, Above_high
                  else match previous with
                    | Some decision
                      when String.equal decision.policy_digest (policy_digest policy)
                           && decision.diagnostic = None
                           && decision.strategy <> Reference
                           && equivalent policy decision.strategy ->
                        decision.strategy, Hysteresis_hold
                    | _ -> Aggregated_graph, Hysteresis_hold
                in
                if not (equivalent policy candidate) then
                  fallback Non_equivalent
                    "candidate fast path lacks an exact semantic-equivalence receipt"
                else
                  { strategy = candidate; reason;
                    observation_digest = Some (Run_metrics.observation_digest observation);
                    cost_digest = Some cost_digest;
                    policy_digest = policy_digest policy; threshold_version = policy.version;
                    oracle = policy.oracle; budget = policy.budget; decided_at_ns = now_ns;
                    diagnostic = None }
                end
        end

let selected_strategy selection = selection.decision.strategy
let selection_digest selection = selection.selection_digest

let selection_digest_of ~context_digest ~activity_digest
    ~activity_authority_digest decision =
  String.concat "\x1f"
    [ "run-fast-path-selection-v2"; context_digest; activity_digest;
      activity_authority_digest; strategy_string decision.strategy;
      decision.policy_digest; Int64.to_string decision.decided_at_ns ]
  |> sha256

let v2_diagnostic (context : Run_safety.gate_context) kind message =
  { kind; message; coordinate = context.Run_safety.coordinate;
    rca_origin = Ops_capability.Control }

let validate_selection ~(context : Run_safety.gate_context)
    ~(activity : Run_topology.admitted_activity) (selection : selection) =
  let activity_digest = Run_topology.admitted_activity_digest activity in
  let activity_authority_digest =
    Run_topology.admitted_activity_authority_digest activity
  in
  let expected_digest =
    selection_digest_of ~context_digest:context.context_digest ~activity_digest
      ~activity_authority_digest selection.decision
  in
  let errors = ref [] in
  let reject condition kind message =
    if condition then errors := v2_diagnostic context kind message :: !errors
  in
  reject (not (String.equal selection.context_digest context.context_digest))
    Not_admitted "selection context differs";
  reject (not (String.equal selection.activity_digest activity_digest))
    Not_admitted "selection activity differs";
  reject
    (not (String.equal selection.activity_authority_digest
            activity_authority_digest))
    Not_admitted "selection topology authority differs";
  reject (selection.decision.strategy <> Reference) Non_equivalent
    "only the reference strategy is dispatch-admissible";
  reject (Option.is_some selection.decision.diagnostic) Not_admitted
    "selection contains a fallback diagnostic";
  reject (not (String.equal selection.selection_digest expected_digest))
    Malformed "selection digest differs";
  match List.rev !errors with [] -> Ok () | errors -> Error errors

let rec choose_v2 ~(context : Run_safety.gate_context)
    ~(activity : Run_topology.admitted_activity) ~(policy : policy)
    ~(previous : selection option) ~(now_ns : int64) ~(cost : cost_evidence)
    (_observation : Run_metrics.observation) =
  let lowercase_digest value =
    valid_digest value && String.equal value (String.lowercase_ascii value)
  in
  if not (lowercase_digest policy.oracle.digest)
     || List.exists
          (fun (_, digest) -> not (lowercase_digest digest))
          policy.equivalent_strategies
  then Error [ v2_diagnostic context Malformed
                 "fast-path authority digests must be lowercase SHA-256" ]
  else
    match previous with
    | Some selection ->
        (match validate_selection ~context ~activity selection with
         | Error _ as error -> error
         | Ok () ->
             choose_v2 ~context ~activity ~policy ~previous:None ~now_ns ~cost
               _observation)
    | None ->
        let candidate = choose policy ~previous:None ~now_ns ~cost _observation in
        (match candidate.diagnostic with
         | Some diagnostic -> Error [ diagnostic ]
         | None ->
             let decision =
               { candidate with strategy = Reference;
                 reason = Reference_fallback; diagnostic = None }
             in
             let context_digest = context.context_digest in
             let activity_digest =
               Run_topology.admitted_activity_digest activity
             in
             let activity_authority_digest =
               Run_topology.admitted_activity_authority_digest activity
             in
             let selection_digest =
               selection_digest_of ~context_digest ~activity_digest
                 ~activity_authority_digest decision
             in
             Ok { context_digest; activity_digest; activity_authority_digest;
                  decision; selection_digest })
