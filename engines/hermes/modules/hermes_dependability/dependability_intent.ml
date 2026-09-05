type target =
  | Sqlite_run_event_store
  | Sqlite_sa_plan_store
  | Sqlite_ops_completion_history
  | Sqlite_evidence_store

type plane = Control_plane | Data_plane | Both_planes

type operation = Prove_lifecycle | Verify_reliability | Verify_full

type success_predicate =
  | Exit_zero
  | No_signal
  | Metric_at_least of string * int64
  | No_matching_crash

type criterion = {
  id : string;
  description : string;
  predicate : success_predicate;
}

type source_authority = {
  source_revision : string;
  source_clean : bool;
  configuration_digest : string;
  authority_digest : string;
  build_digest : string;
  provenance_digest : string;
}

type reliability_schedule = {
  sequential_oracle_attempts : int;
  bounded_parallel_attempts : int;
  lane_count : int;
  permit_topology_digest : string;
}

type policy = {
  confidence_ppm : int;
  maximum_incident_rate_ppm : int;
  attempts : int;
  per_child_timeout_ns : int64;
  maximum_failures : int;
  minimum_overlap_gc_cycles : int;
  reliability_schedule : reliability_schedule;
  require_formal : bool;
  require_crash_window : bool;
  require_full_gate : bool;
}

type t = {
  request_id : string;
  activity_id : string;
  run_id : string;
  operation : operation;
  activity_path : Ops_capability.coordinate list;
  target : target;
  plane : plane;
  policy : policy;
  criteria : criterion list;
  source : source_authority;
}

let all_targets =
  [ Sqlite_run_event_store; Sqlite_sa_plan_store;
    Sqlite_ops_completion_history; Sqlite_evidence_store ]

let target_id = function
  | Sqlite_run_event_store -> "sqlite.run-event-store"
  | Sqlite_sa_plan_store -> "sqlite.sa-plan-store"
  | Sqlite_ops_completion_history -> "sqlite.ops-completion-history"
  | Sqlite_evidence_store -> "sqlite.evidence-store"

let target_coordinate = function
  | Sqlite_run_event_store -> "L2/dependability/sqlite/run-event-store"
  | Sqlite_sa_plan_store -> "L2/dependability/sqlite/sa-plan-store"
  | Sqlite_ops_completion_history ->
      "L2/dependability/sqlite/ops-completion-history"
  | Sqlite_evidence_store -> "L2/dependability/sqlite/evidence-store"

let target_hazards _ = [ "HZ-SQL-FIN-01"; "HZ-DET-01" ]

let target_sources = function
  | Sqlite_run_event_store ->
      [ "modules/hermes_ops_dashboard/run_event_store.ml";
        "modules/hermes_ops_dashboard/run_event_store.mli";
        "modules/hermes_ops_dashboard/test_run_event_store.ml";
        "modules/hermes_ops_dashboard/dune" ]
  | Sqlite_sa_plan_store -> [ "modules/sa_plan/sa_plan_store.ml" ]
  | Sqlite_ops_completion_history ->
      [ "modules/hermes_ops/ops_completion_history.ml" ]
  | Sqlite_evidence_store ->
      [ "modules/hermes_harness/evidence_store.ml" ]

let operations_for_target = function
  | Sqlite_run_event_store ->
      [ Prove_lifecycle; Verify_reliability; Verify_full ]
  | Sqlite_sa_plan_store
  | Sqlite_ops_completion_history
  | Sqlite_evidence_store -> [ Prove_lifecycle; Verify_full ]

let ops_planes = function
  | Control_plane -> [ Ops_capability.Control_plane ]
  | Data_plane -> [ Ops_capability.Data_plane ]
  | Both_planes ->
      [ Ops_capability.Control_plane; Ops_capability.Data_plane ]

let ppm_denominator = 1_000_000

let sha256_string text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let required_attempts ~confidence_ppm ~maximum_incident_rate_ppm =
  if confidence_ppm <= 0 || confidence_ppm >= ppm_denominator then
    Error "confidence_ppm must be strictly between 0 and 1000000"
  else if
    maximum_incident_rate_ppm <= 0
    || maximum_incident_rate_ppm >= ppm_denominator
  then
    Error
      "maximum_incident_rate_ppm must be strictly between 0 and 1000000"
  else
    let confidence = float_of_int confidence_ppm /. float_of_int ppm_denominator in
    let incident =
      float_of_int maximum_incident_rate_ppm /. float_of_int ppm_denominator
    in
    let estimate = log (1.0 -. confidence) /. log (1.0 -. incident) in
    if Float.is_finite estimate && estimate > 0.0
       && estimate <= float_of_int max_int
    then Ok (int_of_float (ceil estimate))
    else Error "reliability budget is outside the supported integer range"

let partition_attempts ~offset ~attempts ~lanes =
  List.init lanes (fun lane ->
      let rec collect index values =
        if index >= attempts then List.rev values
        else collect (index + lanes) ((offset + index) :: values)
      in
      collect lane [])

let make_reliability_schedule ~sequential_oracle_attempts
    ~bounded_parallel_attempts ~lane_count =
  if sequential_oracle_attempts <= 0 then
    Error "sequential_oracle_attempts must be positive"
  else if bounded_parallel_attempts <= 0 then
    Error "bounded_parallel_attempts must be positive"
  else if lane_count < 2 then
    Error "lane_count must provide at least two bounded-parallel permit lanes"
  else if lane_count > bounded_parallel_attempts then
    Error "lane_count cannot exceed bounded_parallel_attempts"
  else if sequential_oracle_attempts > max_int - bounded_parallel_attempts then
    Error "reliability schedule attempt sum overflows"
  else
    let partitions =
      partition_attempts ~offset:sequential_oracle_attempts
        ~attempts:bounded_parallel_attempts ~lanes:lane_count
    in
    let permit_topology_digest =
      (Printf.sprintf "sequential-chain=%d\nparallel-attempts=%d\n"
         sequential_oracle_attempts bounded_parallel_attempts
      ^ (partitions
        |> List.mapi (fun lane indices ->
               Printf.sprintf "permit-lane-%d=%s" lane
                 (indices |> List.map string_of_int |> String.concat ","))
        |> String.concat "\n"))
      |> sha256_string
    in
    Ok
      { sequential_oracle_attempts; bounded_parallel_attempts; lane_count;
        permit_topology_digest }

let make_policy ~confidence_ppm ~maximum_incident_rate_ppm ~attempts
    ~per_child_timeout_ns ~maximum_failures ~minimum_overlap_gc_cycles
    ~reliability_schedule ~require_formal ~require_crash_window
    ~require_full_gate () =
  match required_attempts ~confidence_ppm ~maximum_incident_rate_ppm with
  | Error _ as error -> error
  | Ok required when attempts < required ->
      Error
        (Printf.sprintf "attempts=%d is below the derived minimum=%d" attempts
           required)
  | Ok _ when attempts <= 0 -> Error "attempts must be positive"
  | Ok _ when Int64.compare per_child_timeout_ns 0L <= 0 ->
      Error "per_child_timeout_ns must be positive"
  | Ok _ when maximum_failures < 0 || maximum_failures >= attempts ->
      Error "maximum_failures must be nonnegative and below attempts"
  | Ok _ when minimum_overlap_gc_cycles <= 0 ->
      Error "minimum_overlap_gc_cycles must be positive"
  | Ok _
    when reliability_schedule.sequential_oracle_attempts
         > max_int - reliability_schedule.bounded_parallel_attempts ->
      Error "reliability schedule attempt sum overflows"
  | Ok _
    when reliability_schedule.sequential_oracle_attempts
         + reliability_schedule.bounded_parallel_attempts
         <> attempts ->
      Error "reliability schedule must partition the exact attempt denominator"
  | Ok _ ->
      Ok
        { confidence_ppm; maximum_incident_rate_ppm; attempts;
          per_child_timeout_ns; maximum_failures; minimum_overlap_gc_cycles;
          reliability_schedule; require_formal; require_crash_window;
          require_full_gate }

let has_forbidden_control text =
  let rec loop index =
    if index = String.length text then false
    else
      match text.[index] with
      | '\000' .. '\031' | '\127' | ';' -> true
      | _ -> loop (index + 1)
  in
  loop 0

let valid_identifier text =
  let text = String.trim text in
  text <> "" && not (has_forbidden_control text)
  && String.for_all
       (function
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' | ':' ->
             true
         | _ -> false)
       text

let make_criterion ~id ~description ~predicate =
  if not (valid_identifier id) then Error "criterion id is invalid"
  else if String.trim description = "" || has_forbidden_control description then
    Error "criterion description is empty or contains a forbidden character"
  else
    match predicate with
    | Metric_at_least (metric, value)
      when (not (valid_identifier metric)) || Int64.compare value 0L < 0 ->
        Error "metric criterion has an invalid id or negative lower bound"
    | Exit_zero | No_signal | No_matching_crash | Metric_at_least _ ->
        Ok { id; description; predicate }

let is_hex_digit = function
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false

let valid_digest text =
  String.length text = 64 && String.for_all is_hex_digit text

let validate_source source =
  if not source.source_clean then Error "source authority is dirty"
  else if not (valid_identifier source.source_revision) then
    Error "source revision is empty or malformed"
  else if not (valid_digest source.configuration_digest) then
    Error "configuration digest must be exactly 64 hexadecimal characters"
  else if not (valid_digest source.authority_digest) then
    Error "authority digest must be exactly 64 hexadecimal characters"
  else if not (valid_digest source.build_digest) then
    Error "build digest must be exactly 64 hexadecimal characters"
  else if not (valid_digest source.provenance_digest) then
    Error "provenance digest must be exactly 64 hexadecimal characters"
  else Ok ()

let policy_matches_operation operation policy =
  match operation with
  | Prove_lifecycle -> policy.require_formal
  | Verify_reliability ->
      policy.require_crash_window && policy.maximum_failures = 0
  | Verify_full ->
      policy.require_formal && policy.require_crash_window
      && policy.require_full_gate && policy.maximum_failures = 0

let has_frozen_first_campaign policy =
  policy.attempts = 300
  && policy.reliability_schedule.sequential_oracle_attempts = 32
  && policy.reliability_schedule.bounded_parallel_attempts = 268
  && policy.reliability_schedule.lane_count = 5

let valid_activity_path path =
  let phases = List.map (fun (coordinate : Ops_capability.coordinate) -> coordinate.phase) path in
  match phases with
  | [ Ops_capability.Observe; Ops_capability.Orient; Ops_capability.Decide;
      Ops_capability.Act; Ops_capability.Observe ] -> true
  | _ -> false

let make ~request_id ~activity_id ~run_id ~operation ~activity_path ~target
    ~plane ~policy ~criteria ~source =
  if not (valid_identifier request_id) then Error "request id is invalid"
  else if not (valid_identifier activity_id) then Error "activity id is invalid"
  else if not (valid_identifier run_id) then Error "run id is invalid"
  else if not (valid_activity_path activity_path) then
    Error "activity path must be causal Observe-Orient-Decide-Act-Observe"
  else if not (List.mem operation (operations_for_target target)) then
    Error "operation is not applicable to the selected target"
  else if
    target = Sqlite_run_event_store
    && (operation = Verify_reliability || operation = Verify_full)
    && not (has_frozen_first_campaign policy)
  then Error "run-event-store reliability uses the frozen 32+268 / five-lane campaign"
  else if criteria = [] then Error "at least one success criterion is required"
  else
    let criterion_ids = List.map (fun criterion -> criterion.id) criteria in
    if List.length criterion_ids <> List.length (List.sort_uniq String.compare criterion_ids)
    then Error "criterion ids must be unique"
    else
      match validate_source source with
      | Error _ as error -> error
      | Ok () when not (policy_matches_operation operation policy) ->
          Error
            "policy does not satisfy the selected dependability operation"
      | Ok () ->
          Ok
            { request_id; activity_id; run_id; operation; activity_path; target;
              plane; policy;
              criteria = List.sort (fun left right -> String.compare left.id right.id) criteria;
              source }

let request_id intent = intent.request_id
let activity_id intent = intent.activity_id
let run_id intent = intent.run_id
let operation intent = intent.operation
let activity_path_of_intent intent = intent.activity_path
let target intent = intent.target
let plane intent = intent.plane
let policy_of_intent intent = intent.policy
let criteria intent = intent.criteria
let source intent = intent.source

let attempts policy = policy.attempts
let maximum_failures policy = policy.maximum_failures
let maximum_parallelism policy = policy.reliability_schedule.lane_count
let reliability_schedule policy = policy.reliability_schedule
let sequential_oracle_attempts schedule = schedule.sequential_oracle_attempts
let bounded_parallel_attempts schedule = schedule.bounded_parallel_attempts
let lane_count schedule = schedule.lane_count
let sequential_attempt_ids schedule =
  List.init schedule.sequential_oracle_attempts Fun.id
let parallel_attempt_ids schedule =
  List.init schedule.bounded_parallel_attempts (fun index ->
      schedule.sequential_oracle_attempts + index)
let all_attempt_ids schedule =
  sequential_attempt_ids schedule @ parallel_attempt_ids schedule
let parallel_lane_partitions schedule =
  partition_attempts ~offset:schedule.sequential_oracle_attempts
    ~attempts:schedule.bounded_parallel_attempts ~lanes:schedule.lane_count
let permit_topology_digest schedule = schedule.permit_topology_digest
let per_child_timeout_ns policy = policy.per_child_timeout_ns
let minimum_overlap_gc_cycles policy = policy.minimum_overlap_gc_cycles
let require_formal policy = policy.require_formal
let require_crash_window policy = policy.require_crash_window
let require_full_gate policy = policy.require_full_gate

let plane_name = function
  | Control_plane -> "control-plane"
  | Data_plane -> "data-plane"
  | Both_planes -> "both-planes"

let operation_name = function
  | Prove_lifecycle -> "prove-lifecycle"
  | Verify_reliability -> "verify-reliability"
  | Verify_full -> "verify-full"

let coordinate_json (coordinate : Ops_capability.coordinate) =
  `Assoc
    [ ("level", `String (Ops_capability.string_of_level coordinate.level));
      ("phase", `String (Ops_capability.string_of_phase coordinate.phase)) ]

let predicate_json = function
  | Exit_zero -> `Assoc [ ("kind", `String "exit-zero") ]
  | No_signal -> `Assoc [ ("kind", `String "no-signal") ]
  | No_matching_crash -> `Assoc [ ("kind", `String "no-matching-crash") ]
  | Metric_at_least (metric, minimum) ->
      `Assoc
        [ ("kind", `String "metric-at-least"); ("metric", `String metric);
          ("minimum", `Intlit (Int64.to_string minimum)) ]

let criterion_json criterion =
  `Assoc
    [ ("id", `String criterion.id);
      ("description", `String criterion.description);
      ("predicate", predicate_json criterion.predicate) ]

let policy_json policy =
  let schedule = policy.reliability_schedule in
  `Assoc
    [ ("attempts", `Int policy.attempts);
      ("confidence_ppm", `Int policy.confidence_ppm);
      ("maximum_failures", `Int policy.maximum_failures);
      ("maximum_incident_rate_ppm", `Int policy.maximum_incident_rate_ppm);
      ("maximum_parallelism", `Int policy.reliability_schedule.lane_count);
      ("minimum_overlap_gc_cycles", `Int policy.minimum_overlap_gc_cycles);
      ( "reliability_schedule",
        `Assoc
          [ ("bounded_parallel_attempts", `Int schedule.bounded_parallel_attempts);
            ("lane_count", `Int schedule.lane_count);
            ("permit_topology_digest", `String schedule.permit_topology_digest);
            ("sequential_oracle_attempts", `Int schedule.sequential_oracle_attempts) ] );
      ( "per_child_timeout_ns",
        `Intlit (Int64.to_string policy.per_child_timeout_ns) );
      ("require_crash_window", `Bool policy.require_crash_window);
      ("require_formal", `Bool policy.require_formal);
      ("require_full_gate", `Bool policy.require_full_gate) ]

let source_json source =
  `Assoc
    [ ("authority_digest", `String source.authority_digest);
      ("build_digest", `String source.build_digest);
      ("configuration_digest", `String source.configuration_digest);
      ("provenance_digest", `String source.provenance_digest);
      ("source_clean", `Bool source.source_clean);
      ("source_revision", `String source.source_revision) ]

let sha256 json =
  json |> Yojson.Safe.to_string |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let target_digest intent =
  `Assoc [ ("target", `String (target_id intent.target)) ] |> sha256

let policy_digest intent = policy_json intent.policy |> sha256

let criteria_digest intent =
  `List (List.map criterion_json intent.criteria) |> sha256

let source_digest intent = source_json intent.source |> sha256

let canonical_json intent =
  `Assoc
    [ ("activity_id", `String intent.activity_id);
      ("activity_path", `List (List.map coordinate_json intent.activity_path));
      ("criteria", `List (List.map criterion_json intent.criteria));
      ("operation", `String (operation_name intent.operation));
      ("plane", `String (plane_name intent.plane));
      ("policy", policy_json intent.policy);
      ("request_id", `String intent.request_id);
      ("run_id", `String intent.run_id);
      ("source", source_json intent.source);
      ("target", `String (target_id intent.target)) ]
  |> Yojson.Safe.to_string

let digest intent =
  intent |> canonical_json |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex
