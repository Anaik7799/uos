type reference_claim = Reference_model_not_equivalence
type otp_reference = { release : string; pin_file : string; claim : reference_claim }

let otp_reference =
  { release = "30.0-rc0"; pin_file = "third_party/OTP30_PIN";
    claim = Reference_model_not_equivalence }

type restart_strategy = One_for_one | One_for_all | Rest_for_one
type restart_type = Permanent | Transient | Temporary
type shutdown = Graceful of int | Brutal_kill
type child_role = Gateway | Policy | Adapter_worker | Evidence_store
  | Recovery_worker | Telemetry_worker

type child_spec = {
  child_id : string;
  role : child_role;
  restart : restart_type;
  shutdown : shutdown;
  mailbox_capacity : int;
  resource_budget_id : string;
  recovery_id : string;
}

type restart_intensity = { max_restarts : int; window_ms : int }
type supervisor_declaration = {
  supervisor_id : string;
  strategy : restart_strategy;
  intensity : restart_intensity;
  children : child_spec list;
}
type supervisor_spec = Supervisor of supervisor_declaration

let nonempty value = String.trim value <> ""
let unique values = List.length values = List.length (List.sort_uniq String.compare values)

let make_supervisor declaration =
  let gaps = ref [] in
  let add condition message = if not condition then gaps := message :: !gaps in
  add (nonempty declaration.supervisor_id) "supervisor identity is empty";
  add (declaration.intensity.max_restarts > 0) "restart intensity is not positive";
  add (declaration.intensity.window_ms > 0) "restart window is not positive";
  add (declaration.children <> []) "supervisor has no children";
  let ids = List.map (fun child -> child.child_id) declaration.children in
  add (List.for_all nonempty ids && unique ids) "child identities are empty or duplicate";
  List.iter
    (fun child ->
      add (child.mailbox_capacity > 0) (child.child_id ^ " mailbox is unbounded");
      add (nonempty child.resource_budget_id) (child.child_id ^ " lacks resource budget");
      add (nonempty child.recovery_id) (child.child_id ^ " lacks recovery identity");
      match child.shutdown with
      | Graceful timeout -> add (timeout > 0) (child.child_id ^ " shutdown is unbounded")
      | Brutal_kill -> ())
    declaration.children;
  match List.rev !gaps with [] -> Ok (Supervisor declaration) | gaps -> Error gaps

type exit_reason = Normal | Shutdown | Abnormal | Resource_exhausted | Indeterminate

let restartable restart reason =
  match restart, reason with
  | Temporary, _ -> false
  | Transient, (Normal | Shutdown) -> false
  | Transient, (Abnormal | Resource_exhausted | Indeterminate) -> true
  | Permanent, _ -> true

let restart_set (Supervisor declaration) ~failed_child ~reason =
  match List.find_opt (fun child -> child.child_id = failed_child) declaration.children with
  | None -> []
  | Some failed when not (restartable failed.restart reason) -> []
  | Some _ ->
      begin match declaration.strategy with
      | One_for_one -> [ failed_child ]
      | One_for_all -> List.map (fun child -> child.child_id) declaration.children
      | Rest_for_one ->
          let rec suffix = function
            | [] -> []
            | child :: rest ->
                if child.child_id = failed_child then
                  List.map (fun item -> item.child_id) (child :: rest)
                else suffix rest
          in
          suffix declaration.children
      end

type restart_decision = Restart_allowed | Escalate

let restart_decision (Supervisor declaration) ~now_ms ~failure_times_ms =
  let lower = now_ms - declaration.intensity.window_ms in
  let current =
    List.fold_left
      (fun count time -> if time >= lower && time <= now_ms then count + 1 else count)
      0 failure_times_ms
  in
  if current >= declaration.intensity.max_restarts then Escalate else Restart_allowed

type mailbox = { capacity : int; mutable depth : int }
type enqueue_result = Accepted | Rejected_full

let mailbox ~capacity =
  if capacity <= 0 then invalid_arg "mailbox capacity must be positive";
  { capacity; depth = 0 }

let enqueue mailbox =
  if mailbox.depth >= mailbox.capacity then Rejected_full
  else begin mailbox.depth <- mailbox.depth + 1; Accepted end

let dequeue mailbox =
  if mailbox.depth = 0 then false
  else begin mailbox.depth <- mailbox.depth - 1; true end

let mailbox_depth mailbox = mailbox.depth

type resource_scope = { resources : string list; mutable closed : bool }
let scope resources = { resources = List.sort_uniq String.compare resources; closed = false }
let close_scope scope = scope.closed <- true
let scope_open_resources scope = if scope.closed then 0 else List.length scope.resources

type uca_type = Not_provided | Provided_incorrectly | Wrong_timing | Applied_too_long
type stpa_uca = {
  uca_id : string;
  uca_type : uca_type;
  controller : string;
  control_action : string;
  context : string;
  hazard_ids : string list;
  constraint_ids : string list;
}

let stpa_ucas =
  [ { uca_id = "UCA-EA-01"; uca_type = Not_provided;
      controller = "externalAccessSupervisor"; control_action = "refuse unsafe intent";
      context = "validation, authorization, or target evidence is absent";
      hazard_ids = [ "HZ-EA-UNAUTHORIZED" ]; constraint_ids = [ "SC-EA-01" ] };
    { uca_id = "UCA-EA-02"; uca_type = Provided_incorrectly;
      controller = "externalAccessPolicy"; control_action = "admit intent";
      context = "authority, digest, target, redaction, or budget disagrees";
      hazard_ids = [ "HZ-EA-WRONG-TARGET"; "HZ-EA-SECRET" ];
      constraint_ids = [ "SC-EA-02"; "SC-EA-03" ] };
    { uca_id = "UCA-EA-03"; uca_type = Wrong_timing;
      controller = "Run_swarm_bridge"; control_action = "apply effect";
      context = "authority is stale, cancellation won, or retry races readback";
      hazard_ids = [ "HZ-EA-DUPLICATE"; "HZ-EA-STALE" ];
      constraint_ids = [ "SC-EA-04"; "SC-EA-05" ] };
    { uca_id = "UCA-EA-04"; uca_type = Applied_too_long;
      controller = "externalAccessSupervisor"; control_action = "retain resource";
      context = "child, statement, socket, lock, or credential outlives its scope";
      hazard_ids = [ "HZ-EA-LEAK"; "HZ-EA-EXHAUSTION" ];
      constraint_ids = [ "SC-EA-06"; "SC-EA-07" ] } ]

type failure_mode = {
  failure_id : string;
  component_id : string;
  effect_description : string;
  detection : string;
  recovery : string;
  severity : int;
  occurrence : int;
  detectability : int;
}

let mode failure_id component_id effect_description detection recovery severity occurrence detectability =
  { failure_id; component_id; effect_description; detection; recovery;
    severity; occurrence; detectability }

let fmea =
  [ mode "FM-EA-01" "gateway" "unauthorized effect" "authorization mutant" "fence and refuse" 5 2 1;
    mode "FM-EA-02" "policy" "wrong target" "target digest readback" "no-replay reconcile" 5 2 2;
    mode "FM-EA-03" "adapter" "duplicate effect" "apply-once conflict" "return prior receipt" 5 2 1;
    mode "FM-EA-04" "sqlite" "partial transaction" "transaction state" "rollback or indeterminate" 5 2 2;
    mode "FM-EA-05" "process" "unreaped child" "child census" "terminate group and reap" 4 3 2;
    mode "FM-EA-06" "network" "partition or timeout" "bounded deadline" "cancel and retry policy" 4 4 2;
    mode "FM-EA-07" "evidence" "missing terminal event" "contiguity check" "fence completion" 5 2 1;
    mode "FM-EA-08" "redaction" "credential disclosure" "secret mutant and sink guard" "block receipt and rotate" 5 2 2;
    mode "FM-EA-09" "supervisor" "restart storm" "restart intensity" "escalate supervisor" 4 3 1;
    mode "FM-EA-10" "mailbox" "unbounded growth" "capacity saturation" "reject and backpressure" 4 3 1;
    mode "FM-EA-11" "oracle" "false formal green" "SAT control and mutant" "mark unavailable/refuted" 5 2 1;
    mode "FM-EA-12" "prediction" "overconfident forecast" "calibration and confidence guard" "downgrade to unknown" 4 3 2 ]

let validate_fmea () =
  let gaps = ref [] in
  let ids = List.map (fun item -> item.failure_id) fmea in
  if not (unique ids) then gaps := "FMEA identities duplicate" :: !gaps;
  List.iter
    (fun item ->
      if not (nonempty item.component_id && nonempty item.effect_description
              && nonempty item.detection && nonempty item.recovery)
      then gaps := (item.failure_id ^ " is incomplete") :: !gaps;
      if List.exists (fun score -> score < 1 || score > 5)
          [ item.severity; item.occurrence; item.detectability ]
      then gaps := (item.failure_id ^ " score is outside 1..5") :: !gaps)
    fmea;
  List.rev !gaps

type assurance_tool = Stpa | Fmea | Rete_ul | Stanc | Z3 | Rocq | Iris | Quint
type assurance_role = {
  tool : assurance_tool;
  obligation : string;
  credit_limit : string;
  required_control : string;
  current_adapter : string;
}

let assurance =
  [ { tool = Stpa; obligation = "unsafe control action completeness";
      credit_limit = "safety constraints only"; required_control = "all four UCA types";
      current_adapter = "typed OCaml safety registry" };
    { tool = Fmea; obligation = "failure-mode detection and recovery totality";
      credit_limit = "risk orientation only"; required_control = "score bounds and named detection";
      current_adapter = "typed OCaml FMEA registry" };
    { tool = Rete_ul; obligation = "admission-rule fixed point and rule reachability";
      credit_limit = "admission recommendation only"; required_control = "naive-engine differential and budget";
      current_adapter = "Unavailable_observed until controlled Rete-UL owner" };
    { tool = Stanc; obligation = "posterior reliability calibration";
      credit_limit = "annotation only"; required_control = "prior sensitivity and posterior predictive check";
      current_adapter = "Unavailable_observed until controlled stanc owner" };
    { tool = Z3; obligation = "authorization dominance and bounded lifecycle relations";
      credit_limit = "named theorem only"; required_control = "negation Unsat plus live Sat mutant";
      current_adapter = "in-process Smtml Z3 owner" };
    { tool = Rocq; obligation = "lifecycle and restart closure theorem";
      credit_limit = "artifact theorem only"; required_control = "compiled proof, no admitted axioms";
      current_adapter = "Unavailable_observed until controlled Rocq owner" };
    { tool = Iris; obligation = "resource ownership and concurrent cleanup separation logic";
      credit_limit = "resource theorem only"; required_control = "proofmode compile plus semantic link";
      current_adapter = "Unavailable_observed until controlled Iris owner" };
    { tool = Quint; obligation = "temporal safety, liveness, and recovery traces";
      credit_limit = "bounded model only"; required_control = "holds invariant plus violated false control";
      current_adapter = "Unavailable_observed until controlled Quint owner" } ]

let validate_assurance () =
  let gaps = ref [] in
  let tools = List.map (fun item -> item.tool) assurance in
  if tools <> [ Stpa; Fmea; Rete_ul; Stanc; Z3; Rocq; Iris; Quint ] then
    gaps := "assurance tool denominator or order differs" :: !gaps;
  let obligations = List.map (fun item -> item.obligation) assurance in
  if not (unique obligations) then gaps := "assurance roles overlap" :: !gaps;
  List.iter
    (fun item ->
      if not (nonempty item.obligation && nonempty item.credit_limit
              && nonempty item.required_control && nonempty item.current_adapter)
      then gaps := "assurance role is incomplete" :: !gaps)
    assurance;
  List.rev !gaps

type signal = Mailbox_saturation | Restart_storm | Latency_growth
  | Error_rate_growth | Resource_leak | Readback_mismatch
type prediction_input = {
  signal : signal;
  current_value : float;
  limit : float;
  derivative : float;
  confidence : float;
}
type prediction_verdict = Stable | Watch | Intervention_recommended | Insufficient_evidence
type prediction = {
  verdict : prediction_verdict;
  confidence : float;
  horizon_ms : int;
  hypotheses : string list;
  next_measurement : string;
  safe_action : string;
}

let signal_name = function
  | Mailbox_saturation -> "mailbox saturation"
  | Restart_storm -> "restart storm"
  | Latency_growth -> "latency growth"
  | Error_rate_growth -> "error-rate growth"
  | Resource_leak -> "resource leak"
  | Readback_mismatch -> "readback mismatch"

let predict (input : prediction_input) =
  let confidence = max 0. (min 1. input.confidence) in
  let remaining = input.limit -. input.current_value in
  let horizon_ms =
    if input.derivative <= 0. || remaining <= 0. then 0
    else int_of_float (1000. *. remaining /. input.derivative)
  in
  let hypotheses =
    [ signal_name input.signal ^ " is caused by sustained arrival or failure rate";
      signal_name input.signal ^ " is a transient measurement or downstream blockage" ]
  in
  if confidence < 0.5 then
    { verdict = Insufficient_evidence; confidence; horizon_ms = 0; hypotheses;
      next_measurement = "collect another bounded run-scoped sample and discriminator";
      safe_action = "preserve bounds and do not escalate evidence credit" }
  else if input.current_value >= input.limit
          || (horizon_ms > 0 && horizon_ms <= 5_000) then
    { verdict = Intervention_recommended; confidence; horizon_ms; hypotheses;
      next_measurement = "measure arrival, service, restart, and readback rates separately";
      safe_action = "apply backpressure, fence new effects, and preserve current receipts" }
  else if input.derivative > 0. then
    { verdict = Watch; confidence; horizon_ms; hypotheses;
      next_measurement = "sample the same metric at the declared interval";
      safe_action = "retain admission bounds and prepare a no-effect mitigation" }
  else
    { verdict = Stable; confidence; horizon_ms = 0; hypotheses;
      next_measurement = "continue bounded SLI sampling";
      safe_action = "no effect; keep current guardrails" }

type plane = Control_plane | Data_plane
type ooda_phase = Observe | Orient | Decide | Act
type communication = Request | Classification | Validation | Authorization
  | Preflight | Admission | Effect_request | Readback | Receipt | Telemetry
type metric_spec = {
  metric_id : string;
  unit_name : string;
  limit : float;
  retention_samples : int;
  freshness_ms : int;
}
type predictive_path = {
  path_id : string;
  resource : External_access.resource;
  level : Ops_capability.level;
  component_id : string;
  communication : communication;
  plane : plane;
  phase : ooda_phase;
  metrics : metric_spec list;
  prediction_target : string;
  safe_action_policy : string;
}

let path_step resource index level component communication plane phase target action =
  let prefix = "predictive.external-access." ^ External_access.resource_name resource in
  let path_id = prefix ^ "." ^ string_of_int index in
  { path_id; resource; level; component_id = component; communication; plane; phase;
    metrics =
      [ { metric_id = path_id ^ ".value"; unit_name = "ratio"; limit = 100.;
          retention_samples = 256; freshness_ms = 30_000 } ];
    prediction_target = target; safe_action_policy = action }

let paths_for resource =
  let adapter = External_access.adapter_id resource in
  [ path_step resource 0 Ops_capability.L0 "externalAccessGateway" Request
      Control_plane Observe "arrival pressure" "retain admission bound";
    path_step resource 1 L1 "externalAccessPolicy" Classification
      Control_plane Orient "classification drift" "refuse unknown family";
    path_step resource 2 L2 "externalAccessPolicy" Validation
      Control_plane Decide "validation refusal rate" "preserve all invariants";
    path_step resource 3 L3 "externalAccessPolicy" Authorization
      Control_plane Decide "authorization denial rate" "fence unauthorized target";
    path_step resource 4 L3 adapter Preflight Data_plane Decide
      "resource exhaustion horizon" "backpressure before exhaustion";
    path_step resource 5 L3 "Run_swarm_bridge" Admission Control_plane Act
      "admission latency" "refuse stale authority";
    path_step resource 6 L4 adapter Effect_request Data_plane Act
      "effect saturation" "apply once or refuse";
    path_step resource 7 L5 "externalAccessEvidenceAuthority" Readback Data_plane Observe
      "readback mismatch probability" "fence completion and reconcile";
    path_step resource 8 L6 "externalAccessEvidenceAuthority" Receipt Data_plane Observe
      "terminal receipt lag" "preserve event contiguity";
    path_step resource 9 LX "externalAccessTelemetry" Telemetry Data_plane Observe
      "telemetry freshness" "downgrade stale prediction" ]

let predictive_paths = List.concat_map paths_for External_access.resources

let predictive_coverage_gaps paths =
  let gaps = ref [] in
  let ids = List.map (fun path -> path.path_id) paths in
  if not (unique ids) then gaps := "predictive path identities duplicate" :: !gaps;
  List.iter
    (fun resource ->
      let resource_paths = List.filter (fun path -> path.resource = resource) paths in
      if List.length resource_paths <> 10 then
        gaps := (External_access.resource_name resource ^ " does not have ten authored path cells") :: !gaps)
    External_access.resources;
  let levels = paths |> List.map (fun path -> path.level) |> List.sort_uniq compare in
  if levels <> [ Ops_capability.L0; L1; L2; L3; L4; L5; L6; LX ] then
    gaps := "predictive paths do not cover L0-L6 plus LX" :: !gaps;
  let phases = paths |> List.map (fun path -> path.phase) |> List.sort_uniq compare in
  if phases <> [ Observe; Orient; Decide; Act ] then
    gaps := "predictive paths do not cover Fast OODA" :: !gaps;
  let planes = paths |> List.map (fun path -> path.plane) |> List.sort_uniq compare in
  if planes <> [ Control_plane; Data_plane ] then
    gaps := "predictive paths do not cover control and data planes" :: !gaps;
  List.iter
    (fun path ->
      if not (nonempty path.component_id && nonempty path.prediction_target
              && nonempty path.safe_action_policy && path.metrics <> []) then
        gaps := (path.path_id ^ " lacks component, target, action, or metric") :: !gaps;
      List.iter
        (fun metric ->
          if not (nonempty metric.metric_id && nonempty metric.unit_name
                  && Float.is_finite metric.limit && metric.limit > 0.
                  && metric.retention_samples > 0 && metric.freshness_ms > 0) then
            gaps := (metric.metric_id ^ " has invalid metric policy") :: !gaps)
        path.metrics)
    paths;
  List.rev !gaps

type sample = {
  path_id : string;
  metric_id : string;
  observed_at_ns : int64;
  value : float;
  source_digest : string;
  run_id : string;
}
type sample_refusal = Unknown_path | Unknown_metric | Invalid_value
  | Invalid_identity | Non_monotonic_time | Series_capacity_reached
  | Store_capacity_reached
type series = { path_id : string; metric_id : string; mutable observations : sample list }
type state_store = { max_series : int; max_samples : int; mutable series : series list }

let create_state_store ~max_series ~max_samples_per_series =
  if max_series <= 0 || max_samples_per_series <= 1 then
    invalid_arg "predictive state bounds must be positive and retain two samples";
  { max_series; max_samples = max_samples_per_series; series = [] }

let find_path path_id =
  List.find_opt (fun (path : predictive_path) -> path.path_id = path_id) predictive_paths
let find_metric (path : predictive_path) metric_id =
  List.find_opt (fun (metric : metric_spec) -> metric.metric_id = metric_id) path.metrics
let find_series store path_id metric_id =
  List.find_opt (fun (series : series) -> series.path_id = path_id && series.metric_id = metric_id) store.series

let observe_sample store (sample : sample) =
  match find_path sample.path_id with
  | None -> Error Unknown_path
  | Some path ->
      begin match find_metric path sample.metric_id with
      | None -> Error Unknown_metric
      | Some _ when not (Float.is_finite sample.value) -> Error Invalid_value
      | Some _ when sample.observed_at_ns < 0L || not (nonempty sample.run_id)
                    || String.length sample.source_digest <> 64 -> Error Invalid_identity
      | Some _ ->
          begin match find_series store sample.path_id sample.metric_id with
          | None when List.length store.series >= store.max_series -> Error Store_capacity_reached
          | None ->
              store.series <- { path_id = sample.path_id; metric_id = sample.metric_id;
                                observations = [ sample ] } :: store.series;
              Ok ()
          | Some series ->
              let latest = match List.rev series.observations with [] -> None | item :: _ -> Some item in
              begin match latest with
              | Some previous when Int64.compare sample.observed_at_ns previous.observed_at_ns <= 0 ->
                  Error Non_monotonic_time
              | _ when List.length series.observations >= store.max_samples ->
                  Error Series_capacity_reached
              | _ -> series.observations <- series.observations @ [ sample ]; Ok ()
              end
          end
      end

let samples store ~path_id ~metric_id =
  match find_series store path_id metric_id with None -> [] | Some series -> series.observations

type quality = {
  sample_count : int;
  monotonic : bool;
  current : bool;
  source_consistent : bool;
  prediction_ready : bool;
}

let quality store ~now_ns ~path_id ~metric_id =
  let values = samples store ~path_id ~metric_id in
  let rec monotonic = function
    | [] | [ _ ] -> true
    | left :: ((right :: _) as rest) ->
        Int64.compare left.observed_at_ns right.observed_at_ns < 0 && monotonic rest
  in
  let source_consistent =
    match values with
    | [] -> false
    | first :: rest -> List.for_all (fun sample -> sample.source_digest = first.source_digest) rest
  in
  let current =
    match List.rev values, find_path path_id with
    | latest :: _, Some path ->
        begin match find_metric path metric_id with
        | None -> false
        | Some metric ->
            let max_age = Int64.mul (Int64.of_int metric.freshness_ms) 1_000_000L in
            Int64.compare now_ns latest.observed_at_ns >= 0
            && Int64.compare (Int64.sub now_ns latest.observed_at_ns) max_age <= 0
        end
    | _ -> false
  in
  let sample_count = List.length values in
  let monotonic = monotonic values in
  { sample_count; monotonic; current; source_consistent;
    prediction_ready = sample_count >= 3 && monotonic && current && source_consistent }

let signal_of_communication = function
  | Request | Classification | Validation | Authorization | Admission -> Error_rate_growth
  | Preflight -> Resource_leak
  | Effect_request -> Mailbox_saturation
  | Readback -> Readback_mismatch
  | Receipt | Telemetry -> Latency_growth

let predict_series store ~now_ns ~path_id ~metric_id =
  let state_quality = quality store ~now_ns ~path_id ~metric_id in
  match List.rev (samples store ~path_id ~metric_id), find_path path_id with
  | latest :: previous :: _, Some path ->
      begin match find_metric path metric_id with
      | None -> predict { signal = Error_rate_growth; current_value = 0.; limit = 1.;
                          derivative = 0.; confidence = 0. }
      | Some metric ->
          let delta_ns = Int64.sub latest.observed_at_ns previous.observed_at_ns in
          let derivative =
            if delta_ns <= 0L then 0.
            else (latest.value -. previous.value) *. 1_000_000_000.
                 /. Int64.to_float delta_ns
          in
          let confidence =
            if state_quality.prediction_ready then
              min 0.95 (0.5 +. (float_of_int state_quality.sample_count *. 0.05))
            else 0.25
          in
          predict { signal = signal_of_communication path.communication;
                    current_value = latest.value; limit = metric.limit;
                    derivative; confidence }
      end
  | _ -> predict { signal = Error_rate_growth; current_value = 0.; limit = 1.;
                   derivative = 0.; confidence = 0. }

type complexity = Constant | Linear_in_children
type runtime_operation = {
  operation_id : string;
  time_complexity : complexity;
  space_complexity : complexity;
  bound : string;
}

let runtime_operations =
  [ { operation_id = "mailbox.enqueue"; time_complexity = Constant;
      space_complexity = Constant; bound = "declared mailbox capacity" };
    { operation_id = "mailbox.dequeue"; time_complexity = Constant;
      space_complexity = Constant; bound = "declared mailbox capacity" };
    { operation_id = "supervisor.restart-intensity"; time_complexity = Linear_in_children;
      space_complexity = Constant; bound = "declared restart history window" };
    { operation_id = "supervisor.restart-set"; time_complexity = Linear_in_children;
      space_complexity = Linear_in_children; bound = "declared child denominator" };
    { operation_id = "prediction.forecast"; time_complexity = Constant;
      space_complexity = Constant; bound = "two hypotheses and one action" } ]

let validate_runtime () =
  validate_fmea () @ validate_assurance ()
  @ predictive_coverage_gaps predictive_paths
  @ (if List.map (fun item -> item.uca_type) stpa_ucas
          |> List.sort_uniq compare
        = [ Not_provided; Provided_incorrectly; Wrong_timing; Applied_too_long ]
     then [] else [ "STPA UCA type coverage differs" ])
  @ (if List.for_all
          (fun operation -> nonempty operation.operation_id && nonempty operation.bound)
          runtime_operations
     then [] else [ "runtime performance contract is incomplete" ])
