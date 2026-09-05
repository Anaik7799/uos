type value = Int of int64 | Float of float | State of string
type sample = Measured of { value : value; sampled_at_ns : int64 }
  | Unavailable_observed of { reason : string; sampled_at_ns : int64 }
type source = Run_event | Process_times | Ocaml_gc | Proc_status | Load_average
  | Sqlite_store | Zenoh_transport | Websocket_transport | Snapshot_reconciler
  | Webgl_runtime | Admission_gate | Rete_ul_engine | Deterministic_mcda_v1
  | Safety_analysis | Formal_analysis | Assurance_runner
type unit_ = Count | Nanoseconds | Bytes | Words | Seconds | Ratio | State_unit
type aggregation = Last | Sum | Maximum | Mean | Quantile of int
type objective = Informational | Lower_is_better of { warning : float; critical : float }
  | Higher_is_better of { warning : float; critical : float }
  | Exact_int of int64 | Allowed_states of string list
type freshness = { max_age_ns : int64; future_tolerance_ns : int64 }
type cardinality = { max_series : int; max_labels : int; max_label_length : int }
type unavailable_semantics = Preserve_unavailable | Block_completion | Degrade_observability
type declaration = { id : string; description : string; unit_ : unit_;
  aggregation : aggregation; objective : objective; freshness : freshness;
  cardinality : cardinality; unavailable_semantics : unavailable_semantics;
  sources : source list; fpp_channel : string }
type observation = { metric_id : string; declaration_digest : string;
  run_id : string; subject_id : string; subject_digest : string;
  provenance : Run_model.provenance; coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin; source : source;
  labels : (string * string) list; sample : sample }

module String_set = Set.Make (String)

let ( let* ) value f = match value with Ok result -> f result | Error _ as error -> error

let finite value = match classify_float value with
  | FP_nan | FP_infinite -> false
  | FP_normal | FP_subnormal | FP_zero -> true

let nonempty label value =
  if String.trim value = "" then Error (label ^ " must be nonempty") else Ok ()

let is_identifier_char = function
  | 'a' .. 'z' | '0' .. '9' | '.' | '_' | '-' -> true
  | _ -> false

let identifier label value =
  let* () = nonempty label value in
  if String.for_all is_identifier_char value then Ok ()
  else Error (label ^ " contains a non-canonical character")

let is_hex = function '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true | _ -> false

let digest_text label value =
  if String.length value = 64 && String.for_all is_hex value then Ok ()
  else Error (label ^ " must be a 64-character hexadecimal digest")

let string_of_source = function
  | Run_event -> "run-event" | Process_times -> "process-times"
  | Ocaml_gc -> "ocaml-gc" | Proc_status -> "proc-status"
  | Load_average -> "load-average" | Sqlite_store -> "sqlite-store"
  | Zenoh_transport -> "zenoh-transport"
  | Websocket_transport -> "websocket-transport"
  | Snapshot_reconciler -> "snapshot-reconciler"
  | Webgl_runtime -> "webgl-runtime" | Admission_gate -> "admission-gate"
  | Rete_ul_engine -> "rete-ul" | Deterministic_mcda_v1 -> "deterministic-mcda-v1"
  | Safety_analysis -> "safety-analysis" | Formal_analysis -> "formal-analysis"
  | Assurance_runner -> "assurance-runner"

let string_of_unit = function
  | Count -> "1" | Nanoseconds -> "ns" | Bytes -> "By" | Words -> "words"
  | Seconds -> "s" | Ratio -> "1_ratio" | State_unit -> "state"

let string_of_aggregation = function
  | Last -> "last" | Sum -> "sum" | Maximum -> "maximum" | Mean -> "mean"
  | Quantile value -> "p" ^ string_of_int value

let objective_json = function
  | Informational -> `Assoc [ ("kind", `String "informational") ]
  | Lower_is_better { warning; critical } ->
      `Assoc [ ("critical", `Float critical); ("kind", `String "lower-is-better");
               ("warning", `Float warning) ]
  | Higher_is_better { warning; critical } ->
      `Assoc [ ("critical", `Float critical); ("kind", `String "higher-is-better");
               ("warning", `Float warning) ]
  | Exact_int value ->
      `Assoc [ ("kind", `String "exact-int"); ("value", `Intlit (Int64.to_string value)) ]
  | Allowed_states states ->
      `Assoc [ ("kind", `String "allowed-states");
               ("states", `List (List.map (fun value -> `String value) states)) ]

let unavailable_string = function
  | Preserve_unavailable -> "preserve-unavailable"
  | Block_completion -> "block-completion"
  | Degrade_observability -> "degrade-observability"

let declaration_json declaration =
  `Assoc
    [ ("aggregation", `String (string_of_aggregation declaration.aggregation));
      ("cardinality", `Assoc
         [ ("max_label_length", `Int declaration.cardinality.max_label_length);
           ("max_labels", `Int declaration.cardinality.max_labels);
           ("max_series", `Int declaration.cardinality.max_series) ]);
      ("description", `String declaration.description);
      ("fpp_channel", `String declaration.fpp_channel);
      ("freshness", `Assoc
         [ ("future_tolerance_ns", `Intlit (Int64.to_string declaration.freshness.future_tolerance_ns));
           ("max_age_ns", `Intlit (Int64.to_string declaration.freshness.max_age_ns)) ]);
      ("id", `String declaration.id);
      ("objective", objective_json declaration.objective);
      ("sources", `List (List.map (fun source -> `String (string_of_source source)) declaration.sources));
      ("unavailable_semantics", `String (unavailable_string declaration.unavailable_semantics));
      ("unit", `String (string_of_unit declaration.unit_)) ]

let sha256 text = text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let digest_json json =
  match Run_model.canonical_string json with
  | Ok text -> sha256 text
  | Error error -> sha256 ("invalid-metric-json:" ^ error)

let declaration_digest declaration = digest_json (declaration_json declaration)

let default_freshness = { max_age_ns = 30_000_000_000L; future_tolerance_ns = 1_000_000_000L }
let default_cardinality = { max_series = 4_096; max_labels = 8; max_label_length = 128 }

let declaration ?(aggregation = Last) ?(objective = Informational)
    ?(unavailable_semantics = Preserve_unavailable) ~source ~unit_ id =
  { id; description = "Operations metric " ^ id; unit_; aggregation; objective;
    freshness = default_freshness; cardinality = default_cardinality;
    unavailable_semantics; sources = [ source ];
    fpp_channel = "ops.dashboard.fpp." ^ id }

let unit_for id =
  if String.ends_with ~suffix:"_ns" id then Nanoseconds
  else if String.ends_with ~suffix:".bytes" id then Bytes
  else if String.ends_with ~suffix:"_seconds" id then Seconds
  else if String.ends_with ~suffix:"_words" id || String.ends_with ~suffix:".words" id then Words
  else if List.mem id
      [ "mcda.margin"; "mcda.sensitivity"; "stan.posterior_mean";
        "stan.moment_band"; "assurance.coverage" ] then Ratio
  else if List.mem id
      [ "rete_ul.fixed_point"; "mcda.selection"; "ruliad.confluence";
        "ruliad.nonconfluence"; "z3.cross_path_agreement" ] then State_unit
  else Count

let group source ids =
  List.map (fun id -> declaration ~source ~unit_:(unit_for id) id) ids

let all =
  group Run_event
    [ "run.events.total"; "run.phase.active"; "run.phase.duration_ns";
      "run.suite.discovered"; "run.suite.started"; "run.suite.succeeded";
      "run.suite.failed"; "run.suite.duration_ns" ]
  @ group Process_times
      [ "process.cpu.user_seconds"; "process.cpu.system_seconds";
        "process.cpu.child_user_seconds"; "process.cpu.child_system_seconds" ]
  @ group Ocaml_gc
      [ "ocaml.gc.minor_words"; "ocaml.gc.promoted_words";
        "ocaml.gc.major_words"; "ocaml.gc.heap_words"; "ocaml.gc.live_words";
        "ocaml.gc.free_words"; "ocaml.gc.minor_collections";
        "ocaml.gc.major_collections"; "ocaml.gc.compactions" ]
  @ group Proc_status [ "process.rss.bytes" ]
  @ group Load_average [ "system.load.1m"; "system.load.5m"; "system.load.15m" ]
  @ group Sqlite_store [ "sqlite.event_lag" ]
  @ group Zenoh_transport [ "zenoh.publish_lag_ns"; "zenoh.subscriber_lag_ns" ]
  @ group Websocket_transport [ "websocket.clients"; "websocket.drops" ]
  @ group Snapshot_reconciler
      [ "snapshot.age_ns"; "reconcile.latency_ns"; "render.latency_ns" ]
  @ group Webgl_runtime [ "webgl.frames"; "webgl.context_losses" ]
  @ group Admission_gate [ "admission.gaps" ]
  @ group Rete_ul_engine
      [ "rete_ul.facts"; "rete_ul.alpha_nodes"; "rete_ul.beta_nodes";
        "rete_ul.tokens"; "rete_ul.joins"; "rete_ul.agenda";
        "rete_ul.firings"; "rete_ul.budgets"; "rete_ul.links";
        "rete_ul.fixed_point"; "rete_ul.latency_ns" ]
  @ group Deterministic_mcda_v1
      [ "mcda.alternatives"; "mcda.criteria"; "mcda.cells"; "mcda.exclusions";
        "mcda.constraint_failures"; "mcda.ties"; "mcda.margin";
        "mcda.sensitivity"; "mcda.selection"; "mcda.latency_ns" ]
  @ group Safety_analysis
      [ "stpa.hazards"; "stpa.unsafe_control_actions"; "stpa.constraints";
        "stpa.unmitigated"; "fmea.failure_modes"; "fmea.severity";
        "fmea.occurrence"; "fmea.detection"; "fmea.rpn";
        "fmea.accepted_residuals"; "fmea.gate_latency_ns" ]
  @ group Formal_analysis
      [ "ruliad.states"; "ruliad.edges"; "ruliad.depth"; "ruliad.terminals";
        "ruliad.path_count"; "ruliad.confluence"; "ruliad.cap_hits";
        "ruliad.nonconfluence"; "ruliad.latency_ns"; "stan.scenarios";
        "stan.effective_samples"; "stan.posterior_mean"; "stan.moment_band";
        "stan.invalid_priors"; "stan.unmeasured_families"; "stan.latency_ns";
        "z3.obligations"; "z3.sat"; "z3.unsat"; "z3.unknown"; "z3.timeout";
        "z3.unavailable"; "z3.query_digest_mismatches";
        "z3.cross_path_agreement"; "z3.latency_ns" ]
  @ group Assurance_runner
      [ "assurance.unit.receipts"; "assurance.component.receipts";
        "assurance.system.receipts"; "assurance.tdd.receipts";
        "assurance.bdd.receipts"; "assurance.property.receipts";
        "assurance.fuzz.receipts"; "assurance.chaos.receipts";
        "assurance.stm_model.receipts"; "assurance.performance.receipts";
        "assurance.scalability.receipts"; "assurance.formal.receipts";
        "assurance.mutation.receipts"; "assurance.browser.receipts";
        "assurance.freshness_ns"; "assurance.coverage";
        "assurance.failures"; "assurance.unavailable"; "assurance.latency_ns" ]

let find id = List.find_opt (fun declaration -> String.equal declaration.id id) all

let unique_strings label values =
  let unique = List.sort_uniq String.compare values in
  if List.length values = List.length unique then Ok ()
  else Error (label ^ " must be unique")

let validate_objective = function
  | Informational | Exact_int _ -> Ok ()
  | Lower_is_better { warning; critical } ->
      if finite warning && finite critical && warning < critical then Ok ()
      else Error "lower-is-better thresholds must be finite and ordered"
  | Higher_is_better { warning; critical } ->
      if finite warning && finite critical && warning > critical then Ok ()
      else Error "higher-is-better thresholds must be finite and ordered"
  | Allowed_states states ->
      let* () = if states = [] then Error "allowed states must be nonempty" else Ok () in
      let* () = unique_strings "allowed states" states in
      let rec loop = function [] -> Ok () | value :: rest ->
        let* () = nonempty "allowed state" value in loop rest in
      loop states

let validate_declaration declaration =
  let* () = identifier "metric id" declaration.id in
  let* () = nonempty "metric description" declaration.description in
  let* () = identifier "FPP channel" declaration.fpp_channel in
  let* () =
    if String.starts_with ~prefix:"ops.dashboard.fpp." declaration.fpp_channel
    then Ok () else Error "FPP channel is outside the operations window" in
  let* () = if declaration.sources = [] then Error "metric sources must be nonempty" else Ok () in
  let* () = unique_strings "metric sources" (List.map string_of_source declaration.sources) in
  let* () =
    match declaration.aggregation with Quantile value when value <= 0 || value >= 100 ->
      Error "quantile must be strictly between 0 and 100" | _ -> Ok () in
  let* () = validate_objective declaration.objective in
  let* () =
    if declaration.freshness.max_age_ns <= 0L
       || declaration.freshness.future_tolerance_ns < 0L then
      Error "freshness limits are invalid" else Ok () in
  if declaration.cardinality.max_series <= 0 || declaration.cardinality.max_labels < 0
     || declaration.cardinality.max_label_length <= 0 then
    Error "cardinality bounds are invalid"
  else Ok ()

let validate_declarations declarations =
  let* () = if declarations = [] then Error "metric registry must be nonempty" else Ok () in
  let rec loop = function [] -> Ok () | declaration :: rest ->
    let* () = validate_declaration declaration in loop rest in
  let* () = loop declarations in
  let* () = unique_strings "metric ids" (List.map (fun item -> item.id) declarations) in
  unique_strings "FPP channels" (List.map (fun item -> item.fpp_channel) declarations)

let sample_json = function
  | Measured { value; sampled_at_ns } ->
      let value = match value with
        | Int value -> `Assoc [ ("kind", `String "int"); ("value", `Intlit (Int64.to_string value)) ]
        | Float value -> `Assoc [ ("kind", `String "float"); ("value", `Float value) ]
        | State value -> `Assoc [ ("kind", `String "state"); ("value", `String value) ] in
      `Assoc [ ("availability", `String "measured");
               ("sampled_at_ns", `Intlit (Int64.to_string sampled_at_ns));
               ("value", value) ]
  | Unavailable_observed { reason; sampled_at_ns } ->
      `Assoc [ ("availability", `String "unavailable-observed");
               ("reason", `String reason);
               ("sampled_at_ns", `Intlit (Int64.to_string sampled_at_ns)) ]

let coordinate_json coordinate =
  `Assoc [ ("level", `String (Ops_capability.string_of_level coordinate.Ops_capability.level));
           ("ooda_phase", `String (Ops_capability.string_of_phase coordinate.phase)) ]

let provenance_json provenance =
  `Assoc [ ("authority_digest", `String provenance.Run_model.authority_digest);
           ("configuration_digest", `String provenance.configuration_digest);
           ("executable_digest", `String provenance.executable_digest);
           ("source_clean", `Bool provenance.source_clean);
           ("source_revision", `String provenance.source_revision) ]

let observation_json observation =
  `Assoc
    [ ("coordinate", coordinate_json observation.coordinate);
      ("declaration_digest", `String observation.declaration_digest);
      ("labels", `Assoc (List.map (fun (key, value) -> (key, `String value)) observation.labels));
      ("metric_id", `String observation.metric_id);
      ("provenance", provenance_json observation.provenance);
      ("rca_origin", `String (Ops_capability.string_of_rca_origin observation.rca_origin));
      ("run_id", `String observation.run_id);
      ("sample", sample_json observation.sample);
      ("source", `String (string_of_source observation.source));
      ("subject_digest", `String observation.subject_digest);
      ("subject_id", `String observation.subject_id) ]

let observation_digest observation = digest_json (observation_json observation)

let sampled_at_ns observation = match observation.sample with
  | Measured { sampled_at_ns; _ } | Unavailable_observed { sampled_at_ns; _ } -> sampled_at_ns

let forbidden_label key =
  let key = String.lowercase_ascii key in
  let segments =
    key |> String.map (function '.' | '-' -> '_' | character -> character)
    |> String.split_on_char '_'
  in
  List.exists
    (fun token -> List.mem token segments)
    [ "prompt"; "path"; "credential"; "credentials"; "secret"; "output";
      "bytes"; "token" ]

let validate_labels cardinality labels =
  let* () = if List.length labels > cardinality.max_labels then Error "too many metric labels" else Ok () in
  let* () = unique_strings "metric label keys" (List.map fst labels) in
  let rec loop = function
    | [] -> Ok ()
    | (key, value) :: rest ->
        let* () = identifier "metric label key" key in
        let* () = nonempty "metric label value" value in
        let* () = if forbidden_label key then Error ("forbidden metric label: " ^ key) else Ok () in
        let* () =
          if String.length key <= cardinality.max_label_length
             && String.length value <= cardinality.max_label_length then Ok ()
          else Error "metric label exceeds its length bound" in
        loop rest
  in
  loop labels

let validate_observation ~now_ns observation =
  let* declaration = match find observation.metric_id with
    | Some value -> Ok value | None -> Error ("unmodeled metric: " ^ observation.metric_id) in
  let* () = if String.equal observation.declaration_digest (declaration_digest declaration)
    then Ok () else Error "metric declaration digest mismatch" in
  let* () = Run_model.validate_head ~run_id:observation.run_id ~provenance:observation.provenance in
  let* () = nonempty "subject id" observation.subject_id in
  let* () = digest_text "subject digest" observation.subject_digest in
  let* () = if List.mem observation.source declaration.sources then Ok ()
    else Error "observation source is not declared for this metric" in
  let* () = validate_labels declaration.cardinality observation.labels in
  let sampled_at_ns = sampled_at_ns observation in
  let* () = if now_ns < 0L || sampled_at_ns < 0L then Error "metric time must be nonnegative" else Ok () in
  let* () =
    if sampled_at_ns > now_ns
       && Int64.sub sampled_at_ns now_ns > declaration.freshness.future_tolerance_ns
    then Error "metric sample exceeds its future tolerance" else Ok ()
  in
  let* () =
    if sampled_at_ns <= now_ns && Int64.sub now_ns sampled_at_ns > declaration.freshness.max_age_ns
    then Error "metric sample is stale" else Ok () in
  match observation.sample with
  | Measured { value = Float value; _ } when not (finite value) ->
      Error "metric float must be finite"
  | Measured { value = State value; _ } ->
      let* () = nonempty "metric state" value in
      if String.length value > declaration.cardinality.max_label_length
      then Error "metric state exceeds its length bound" else Ok ()
  | Measured _ -> Ok ()
  | Unavailable_observed { reason; _ } ->
      let* () = nonempty "unavailable reason" reason in
      if String.length reason > 256 then Error "unavailable reason exceeds 256 bytes" else Ok ()

let to_otel_json observation =
  let declaration = find observation.metric_id in
  let availability, value_fields = match observation.sample with
    | Measured { value; _ } ->
        let json = match value with Int v -> `Intlit (Int64.to_string v)
          | Float v -> `Float v | State v -> `String v in
        ("measured", [ ("value", json) ])
    | Unavailable_observed { reason; _ } ->
        ("unavailable-observed", [ ("unavailable_reason", `String reason) ]) in
  let unit_ = match declaration with Some item -> string_of_unit item.unit_ | None -> "unmodeled" in
  `Assoc
    ([ ("availability", `String availability);
       ("coordinate", coordinate_json observation.coordinate);
       ("declaration_digest", `String observation.declaration_digest);
       ("labels", `Assoc (List.map (fun (key, value) -> (key, `String value)) observation.labels));
       ("metric_id", `String observation.metric_id);
       ("provenance", provenance_json observation.provenance);
       ("rca_origin", `String (Ops_capability.string_of_rca_origin observation.rca_origin));
       ("run_id", `String observation.run_id);
       ("sampled_at_ns", `Intlit (Int64.to_string (sampled_at_ns observation)));
       ("source", `String (string_of_source observation.source));
       ("subject_digest", `String observation.subject_digest);
       ("subject_id", `String observation.subject_id);
       ("unit", `String unit_) ] @ value_fields)
