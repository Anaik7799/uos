type outcome = Succeeded | Refused | Failed | Timed_out | Indeterminate

type declaration = {
  trace_id : string;
  span_id : string;
  parent_span_id : string option;
  run_id : string;
  request_id : string;
  intent_id : string;
  attempt_id : string option;
  path_id : string;
  metric_id : string;
  observed_at_ns : int64;
  duration_ns : int64;
  value : float;
  outcome : outcome;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
  event_code : string;
  source_digest : string;
  prediction_verdict : External_access_runtime.prediction_verdict;
}

type observation = {
  declaration : declaration;
  path : External_access_runtime.predictive_path;
  metric : External_access_runtime.metric_spec;
}

let nonempty value = String.trim value <> ""
let bounded_identity value = nonempty value && String.length value <= 128
let is_hex value =
  String.for_all
    (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
    value

let find_path path_id =
  List.find_opt
    (fun (path : External_access_runtime.predictive_path) -> path.path_id = path_id)
    External_access_runtime.predictive_paths

let find_metric path metric_id =
  List.find_opt
    (fun (metric : External_access_runtime.metric_spec) -> metric.metric_id = metric_id)
    path.External_access_runtime.metrics

let observe declaration =
  let gaps = ref [] in
  let add condition message = if not condition then gaps := message :: !gaps in
  add (String.length declaration.trace_id = 32 && is_hex declaration.trace_id)
    "trace identity is not 128-bit lowercase hexadecimal";
  add (String.length declaration.span_id = 16 && is_hex declaration.span_id)
    "span identity is not 64-bit lowercase hexadecimal";
  add (match declaration.parent_span_id with None -> true | Some value ->
         String.length value = 16 && is_hex value && value <> declaration.span_id)
    "parent span identity is invalid or self-referential";
  List.iter
    (fun (name, value) -> add (bounded_identity value) (name ^ " identity is invalid"))
    [ "run", declaration.run_id; "request", declaration.request_id;
      "intent", declaration.intent_id; "hazard", declaration.hazard_id;
      "event", declaration.event_code ];
  add (match declaration.attempt_id with None -> true | Some value -> bounded_identity value)
    "attempt identity is invalid";
  add (declaration.observed_at_ns >= 0L && declaration.duration_ns >= 0L)
    "observation time or duration is negative";
  add (Float.is_finite declaration.value) "metric value is not finite";
  add (String.length declaration.source_digest = 64 && is_hex declaration.source_digest)
    "source digest is not lowercase SHA-256";
  let path = find_path declaration.path_id in
  add (Option.is_some path) "predictive path is unknown";
  let metric = Option.bind path (fun path -> find_metric path declaration.metric_id) in
  add (Option.is_some metric) "metric is not owned by the predictive path";
  match List.rev !gaps, path, metric with
  | [], Some path, Some metric -> Ok { declaration; path; metric }
  | gaps, _, _ -> Error gaps

let is_child ~parent ~child =
  child.declaration.parent_span_id = Some parent.declaration.span_id
  && child.declaration.trace_id = parent.declaration.trace_id
  && child.declaration.run_id = parent.declaration.run_id
  && child.declaration.request_id = parent.declaration.request_id
  && child.declaration.intent_id = parent.declaration.intent_id

let level_name = function
  | Ops_capability.L0 -> "L0" | L1 -> "L1" | L2 -> "L2" | L3 -> "L3"
  | L4 -> "L4" | L5 -> "L5" | L6 -> "L6" | LX -> "LX"

let phase_name = function
  | External_access_runtime.Observe -> "Observe" | Orient -> "Orient"
  | Decide -> "Decide" | Act -> "Act"

let plane_name = function
  | External_access_runtime.Control_plane -> "control" | Data_plane -> "data"

let origin_name = function
  | Ops_capability.Specification -> "Specification"
  | Implementation -> "Implementation" | Environment -> "Environment"
  | Evidence -> "Evidence" | Control -> "Control"

let outcome_name = function
  | Succeeded -> "succeeded" | Refused -> "refused" | Failed -> "failed"
  | Timed_out -> "timed-out" | Indeterminate -> "indeterminate"

let prediction_name = function
  | External_access_runtime.Stable -> "stable" | Watch -> "watch"
  | Intervention_recommended -> "intervention-recommended"
  | Insufficient_evidence -> "insufficient-evidence"

let attributes item =
  let declaration = item.declaration in
  [ "trace.id", declaration.trace_id; "span.id", declaration.span_id;
    "run.id", declaration.run_id; "request.id", declaration.request_id;
    "intent.id", declaration.intent_id; "path.id", declaration.path_id;
    "metric.id", declaration.metric_id; "fractal.level", level_name item.path.level;
    "ooda.phase", phase_name item.path.phase; "plane", plane_name item.path.plane;
    "rca.origin", origin_name declaration.rca_origin;
    "hazard.id", declaration.hazard_id; "event.code", declaration.event_code;
    "outcome", outcome_name declaration.outcome;
    "prediction.verdict", prediction_name declaration.prediction_verdict;
    "source.digest", declaration.source_digest ]

type log_record = {
  trace_id : string;
  span_id : string;
  parent_span_id : string option;
  path_id : string;
  level : Ops_capability.level;
  phase : External_access_runtime.ooda_phase;
  plane : External_access_runtime.plane;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
  event_code : string;
  outcome : outcome;
  observed_at_ns : int64;
  duration_ns : int64;
}

let log_record item =
  let declaration = item.declaration in
  { trace_id = declaration.trace_id; span_id = declaration.span_id;
    parent_span_id = declaration.parent_span_id; path_id = declaration.path_id;
    level = item.path.level; phase = item.path.phase; plane = item.path.plane;
    rca_origin = declaration.rca_origin; hazard_id = declaration.hazard_id;
    event_code = declaration.event_code; outcome = declaration.outcome;
    observed_at_ns = declaration.observed_at_ns; duration_ns = declaration.duration_ns }

type logging_contract = {
  path_id : string;
  metric_ids : string list;
  required_dimensions : string list;
  max_attributes : int;
  redaction_policy : string;
}

let required_dimensions =
  [ "trace.id"; "span.id"; "run.id"; "request.id"; "intent.id"; "path.id";
    "metric.id"; "fractal.level"; "ooda.phase"; "plane"; "rca.origin";
    "hazard.id"; "event.code"; "outcome"; "prediction.verdict"; "source.digest" ]

let logging_contracts =
  List.map
    (fun (path : External_access_runtime.predictive_path) ->
      { path_id = path.path_id;
        metric_ids = List.map (fun (metric : External_access_runtime.metric_spec) -> metric.metric_id) path.metrics;
        required_dimensions; max_attributes = 20;
        redaction_policy = "metadata-only; no target, SQL, prompt, credential, or payload" })
    External_access_runtime.predictive_paths

let logging_coverage_gaps () =
  let gaps = ref [] in
  let path_ids =
    External_access_runtime.predictive_paths
    |> List.map (fun (path : External_access_runtime.predictive_path) -> path.path_id)
  in
  let contract_ids = List.map (fun contract -> contract.path_id) logging_contracts in
  if contract_ids <> path_ids then gaps := "logging contract denominator or order differs" :: !gaps;
  List.iter
    (fun contract ->
      if contract.metric_ids = [] || contract.required_dimensions <> required_dimensions
         || contract.max_attributes < List.length required_dimensions
         || not (nonempty contract.redaction_policy)
      then gaps := (contract.path_id ^ " logging contract is incomplete") :: !gaps)
    logging_contracts;
  List.rev !gaps

type tuning_action = No_change | Apply_backpressure | Scale_workers
  | Reduce_concurrency | Investigate_readback
type execution = Recommendation_only
type tuning_recommendation = {
  action : tuning_action;
  execution : execution;
  evidence_ids : string list;
  confidence : float;
  rationale : string;
  next_measurement : string;
}

let tune observations =
  let evidence_ids =
    observations |> List.map (fun item -> item.declaration.event_code)
    |> List.sort_uniq String.compare
  in
  let readback_failure =
    List.exists
      (fun item ->
        item.path.communication = External_access_runtime.Readback
        && item.declaration.outcome <> Succeeded)
      observations
  in
  let saturation =
    List.exists
      (fun item -> item.declaration.value /. item.metric.limit >= 0.9)
      observations
  in
  let timed_out = List.exists (fun item -> item.declaration.outcome = Timed_out) observations in
  if readback_failure then
    { action = Investigate_readback; execution = Recommendation_only; evidence_ids;
      confidence = 0.85; rationale = "typed readback observation is non-success";
      next_measurement = "compare terminal event, effect receipt, and readback digest" }
  else if saturation then
    { action = Apply_backpressure; execution = Recommendation_only; evidence_ids;
      confidence = 0.8; rationale = "one bounded metric is at or above 90 percent";
      next_measurement = "separate arrival, service, and queueing rates" }
  else if timed_out then
    { action = Reduce_concurrency; execution = Recommendation_only; evidence_ids;
      confidence = 0.65; rationale = "timeout observed without causal attribution";
      next_measurement = "measure service time, saturation, and downstream latency" }
  else
    { action = No_change; execution = Recommendation_only; evidence_ids;
      confidence = 0.5; rationale = "no declared tuning trigger observed";
      next_measurement = "continue bounded run-scoped measurements" }

let validate () =
  logging_coverage_gaps ()
  @ (if List.length required_dimensions <= 20 then [] else [ "attribute bound is exceeded" ])
  @ (if List.exists (fun unsafe -> List.mem unsafe required_dimensions)
          [ "target"; "sql"; "prompt"; "credential"; "payload" ]
     then [ "unsafe high-cardinality dimension is declared" ] else [])
