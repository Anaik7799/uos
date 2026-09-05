type evidence_credit =
  | No_credit
  | Discovery_credit
  | Structural_credit
  | Differential_credit

type surface = Ocaml_api | Cli | Mcp | Zenoh
type lifecycle = Declared | Implemented | Current | Unavailable_observed
type applicability = Applicable | Not_applicable of string
type availability = Available_structural | Unavailable_observed_status | Blocked_status

type row = {
  row_id : string;
  capability_id : string;
  ontology_id : string;
  coordinate : string;
  target : Dependability_intent.target;
  intent : Dependability_intent.operation option;
  surface : surface;
  applicability : applicability;
  availability : availability;
  graph_units : string list;
  fpp_elements : string list;
  formal_obligations : string list;
  native_tests : string list;
  metric_ids : string list;
  receipt_kinds : string list;
  currentness_dependencies : string list;
  residuals : string list;
  source_credit : evidence_credit;
  projected_credit : evidence_credit;
  plane : Dependability_intent.plane;
  owner : string;
  lifecycle : lifecycle;
}

let surface_name = function
  | Ocaml_api -> "ocaml-api"
  | Cli -> "cli"
  | Mcp -> "mcp"
  | Zenoh -> "zenoh"

let operation_name = function
  | Dependability_intent.Prove_lifecycle -> "prove-lifecycle"
  | Dependability_intent.Verify_reliability -> "verify-reliability"
  | Dependability_intent.Verify_full -> "verify-full"

let row_identity capability_id target surface =
  String.concat "|"
    [ capability_id; Dependability_intent.target_id target; surface_name surface ]

type specification = {
  capability_id : string;
  graph_units : string list;
  fpp_elements : string list;
  formal_obligations : string list;
  native_tests : string list;
  metric_ids : string list;
  receipt_kinds : string list;
  currentness_dependencies : string list;
  residuals : string list;
  source_credit : evidence_credit;
  projected_credit : evidence_credit;
  plane : Dependability_intent.plane;
  owner : string;
}

type currentness_control = {
  control_id : string;
  authority_digest : string;
}

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let canonical_sha256 value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let currentness_control_ids =
  [ "current-Run_swarm_bridge"; "current-four-surface-adapters";
    "exact-authority-digest"; "exact-build-digest";
    "exact-configuration-digest"; "exact-source-digest";
    "live-z3-identity"; "policy-digest"; "same-run-journal-cursors" ]

let currentness_controls =
  List.map
    (fun control_id ->
      { control_id;
        authority_digest =
          sha256
            ("hermes-dependability-currentness-control-v1\000" ^ control_id) })
    currentness_control_ids

let find_currentness_control control_id =
  List.find_opt
    (fun (control : currentness_control) -> control.control_id = control_id)
    currentness_controls

let bind_currentness_dependency control_id =
  match find_currentness_control control_id with
  | Some control -> control.control_id ^ "@" ^ control.authority_digest
  | None -> invalid_arg ("unknown atlas currentness control: " ^ control_id)

let resolve_currentness_dependency encoded =
  match String.split_on_char '@' encoded with
  | [ control_id; authority_digest ] ->
      begin match find_currentness_control control_id with
      | Some control
        when canonical_sha256 authority_digest
             && authority_digest = control.authority_digest ->
          Some control
      | Some _ | None -> None
      end
  | _ -> None

let common_currentness =
  [ "exact-source-digest"; "exact-configuration-digest";
    "exact-authority-digest"; "exact-build-digest"; "policy-digest" ]

let unavailable_execution =
  [ "execution unavailable until intelligence admission and Run_swarm_bridge land" ]

let specification ~capability_id ~graph_units ~fpp_elements ~formal_obligations
    ~native_tests ~metric_ids ~receipt_kinds ~currentness_dependencies ~residuals
    ~source_credit ~projected_credit =
  { capability_id; graph_units; fpp_elements; formal_obligations; native_tests;
    metric_ids; receipt_kinds;
    currentness_dependencies =
      List.map bind_currentness_dependency currentness_dependencies;
    residuals; source_credit;
    projected_credit; plane = Dependability_intent.Both_planes;
    owner = "hermes-dependability" }

let statement_spec =
  specification ~capability_id:"sqlite.statement-lifetime"
    ~graph_units:[ "lifecycle-model"; "native-focused" ]
    ~fpp_elements:
      [ "effectAuthority"; "StatementLifecycle"; "FinalizeCommand";
        "FinalizeEvent" ]
    ~formal_obligations:
      [ "one finalize transition"; "no use after finalize";
        "explicit finalize and GC finalizer cannot both own release" ]
    ~native_tests:[ "test_sqlite_lifecycle_model" ]
    ~metric_ids:[ "sqlite.statements.open"; "sqlite.finalize.attempts" ]
    ~receipt_kinds:[ "lifecycle-model"; "native-focused" ]
    ~currentness_dependencies:common_currentness
    ~residuals:[ "native GC-overlap receipt remains unavailable" ]
    ~source_credit:Structural_credit ~projected_credit:Structural_credit

let close_spec =
  specification ~capability_id:"sqlite.database-close"
    ~graph_units:[ "lifecycle-model"; "native-focused" ]
    ~fpp_elements:
      [ "effectAuthority"; "DatabaseCloseLifecycle"; "CloseCommand";
        "CloseEvent" ]
    ~formal_obligations:
      [ "close acknowledgement follows physical release";
        "db_close=false cannot transition to Closed" ]
    ~native_tests:[ "test_sqlite_lifecycle_model" ]
    ~metric_ids:[ "sqlite.close.attempts"; "sqlite.close.refusals" ]
    ~receipt_kinds:[ "lifecycle-model"; "native-focused" ]
    ~currentness_dependencies:common_currentness
    ~residuals:[ "native busy-then-finalize receipt remains unavailable" ]
    ~source_credit:Structural_credit ~projected_credit:Structural_credit

let actor_spec =
  specification ~capability_id:"sqlite.actor-cleanup"
    ~graph_units:[ "native-focused" ]
    ~fpp_elements:
      [ "effectAuthority"; "evidenceAuthority"; "RunEventStore";
        "DrainEvent"; "JoinEvent" ]
    ~formal_obligations:
      [ "one elected closer"; "failure drain is total";
        "writer join precedes Closed" ]
    ~native_tests:[ "test_sqlite_lifecycle_model" ]
    ~metric_ids:[ "sqlite.actor.pending"; "sqlite.actor.closed" ]
    ~receipt_kinds:[ "lifecycle-model"; "native-focused" ]
    ~currentness_dependencies:common_currentness
    ~residuals:[ "live Run_event_store actor receipt remains unavailable" ]
    ~source_credit:Structural_credit ~projected_credit:Structural_credit

let process_spec =
  specification ~capability_id:"sqlite.process-reliability"
    ~graph_units:[ "process-reliability" ]
    ~fpp_elements:
      [ "swarmBridge"; "processAttempt"; "evidenceAuthority";
        "SwarmVerifier"; "NativeStressWorker"; "PermitReceipt" ]
    ~formal_obligations:
      [ "global attempt ids are exactly 0..299";
        "parallel receipts equal sequential oracle";
        "signalled child is a terminal failed receipt" ]
    ~native_tests:[ "dependability 300-process Swarm campaign" ]
    ~metric_ids:
      [ "dependability.attempts.required"; "dependability.attempts.completed";
        "dependability.children.signalled" ]
    ~receipt_kinds:[ "process-attempt"; "reliability-aggregate" ]
    ~currentness_dependencies:("current-Run_swarm_bridge" :: common_currentness)
    ~residuals:unavailable_execution ~source_credit:No_credit
    ~projected_credit:No_credit

let crash_spec =
  specification ~capability_id:"sqlite.kernel-crash-window"
    ~graph_units:[ "crash-window" ]
    ~fpp_elements:
      [ "journalOracle"; "CrashWindowOracle"; "JournalCursor";
        "CrashMatchEvent" ]
    ~formal_obligations:[ "cursor interval is bounded"; "unavailable journal cannot pass" ]
    ~native_tests:[ "bounded kernel-journal crash query" ]
    ~metric_ids:[ "sqlite.kernel_crash.matches"; "sqlite.journal.available" ]
    ~receipt_kinds:[ "journal-window" ]
    ~currentness_dependencies:("same-run-journal-cursors" :: common_currentness)
    ~residuals:unavailable_execution ~source_credit:No_credit
    ~projected_credit:No_credit

let formal_spec =
  specification ~capability_id:"sqlite.lifecycle-formal"
    ~graph_units:[ "lifecycle-model"; "lifecycle-smt" ]
    ~fpp_elements:
      [ "formalOracle"; "FormalChecker"; "LifecycleObligationEvent" ]
    ~formal_obligations:
      [ "exhaustive finite lifecycle laws"; "SMT theorem negation is Unsat";
        "healthy Sat control"; "named mutant Sat witness" ]
    ~native_tests:[ "test_sqlite_lifecycle_model"; "test_sqlite_lifecycle_smt" ]
    ~metric_ids:
      [ "dependability.formal.proved"; "dependability.formal.refuted";
        "dependability.formal.unavailable" ]
    ~receipt_kinds:[ "formal-model"; "formal-smt"; "mutant-witness" ]
    ~currentness_dependencies:("live-z3-identity" :: common_currentness)
    ~residuals:[ "formal proof is finite-model credit, not native differential credit" ]
    ~source_credit:Structural_credit ~projected_credit:Structural_credit

let fpp_spec =
  specification ~capability_id:"sqlite.fpp-mbse"
    ~graph_units:[ "fpp-mbse" ]
    ~fpp_elements:
      [ "identityMaterializer"; "aggregator"; "metricsProjector";
        "IntentAdmission"; "FingerprintGraph"; "FormalChecker";
        "SwarmVerifier"; "NativeStressWorker"; "CrashWindowOracle";
        "EvidenceAuthority"; "MetricsTracePublisher"; "SurfaceGateway" ]
    ~formal_obligations:
      [ "ontology-atlas homomorphism"; "graph-FPP topology agreement";
        "SysML OML MMS FPP projections share one authority" ]
    ~native_tests:[ "test_dependability_meta" ]
    ~metric_ids:[ "dependability.model.dangling" ]
    ~receipt_kinds:[ "fpp-validation"; "mbse-projection" ]
    ~currentness_dependencies:common_currentness
    ~residuals:[ "generated FPP and MBSE projections are outside the pure core slice" ]
    ~source_credit:Structural_credit ~projected_credit:Structural_credit

let surface_spec =
  specification ~capability_id:"sqlite.four-surfaces"
    ~graph_units:[ "full-gate" ]
    ~fpp_elements:
      [ "dependabilityGateway"; "SurfaceGateway";
        "DependabilityVerifyCommand" ]
    ~formal_obligations:
      [ "four requests normalize to one digest";
        "four receipts and errors normalize equivalently";
        "transport cannot promote evidence" ]
    ~native_tests:[ "test_dependability_surface" ]
    ~metric_ids:[ "dependability.surface.requests"; "dependability.surface.errors" ]
    ~receipt_kinds:[ "surface-request"; "surface-receipt" ]
    ~currentness_dependencies:("current-four-surface-adapters" :: common_currentness)
    ~residuals:
      [ "canonical four-surface codecs are focused-tested; live CLI, MCP server, Zenoh network, and Run_swarm_bridge execution remain unavailable until Task 7" ]
    ~source_credit:No_credit ~projected_credit:No_credit

let row (spec : specification) ~target ~intent ~surface ~availability ~lifecycle =
  let ontology =
    match Dependability_ontology.find spec.capability_id with
    | Some node -> node
    | None -> invalid_arg ("missing ontology specification: " ^ spec.capability_id)
  in
  { row_id = row_identity spec.capability_id target surface;
    capability_id = spec.capability_id; ontology_id = spec.capability_id;
    coordinate = ontology.coordinate; target; intent; surface;
    applicability = Applicable; availability; graph_units = spec.graph_units;
    fpp_elements = spec.fpp_elements; formal_obligations = spec.formal_obligations;
    native_tests = spec.native_tests; metric_ids = spec.metric_ids;
    receipt_kinds = spec.receipt_kinds;
    currentness_dependencies = spec.currentness_dependencies;
    residuals =
      (match availability with
       | Available_structural -> spec.residuals
       | Unavailable_observed_status | Blocked_status ->
           ("mapping unavailable on " ^ surface_name surface) :: spec.residuals);
    source_credit = spec.source_credit;
    projected_credit = spec.projected_credit; plane = spec.plane; owner = spec.owner;
    lifecycle }

let all_surfaces = [ Ocaml_api; Cli; Mcp; Zenoh ]

let rows_for_targets ?(ocaml_available = true) (spec : specification) targets
    operation =
  List.concat_map
    (fun target ->
      List.map
        (fun surface ->
          let available = ocaml_available && surface = Ocaml_api in
          row spec ~target ~intent:(Some operation) ~surface
            ~availability:
              (if available then Available_structural
               else Unavailable_observed_status)
            ~lifecycle:(if available then Implemented else Unavailable_observed))
        all_surfaces)
    targets

let rows =
  rows_for_targets statement_spec Dependability_intent.all_targets
    Dependability_intent.Prove_lifecycle
  @ rows_for_targets close_spec Dependability_intent.all_targets
      Dependability_intent.Prove_lifecycle
  @ rows_for_targets formal_spec Dependability_intent.all_targets
      Dependability_intent.Prove_lifecycle
  @ rows_for_targets fpp_spec Dependability_intent.all_targets
      Dependability_intent.Prove_lifecycle
  @ rows_for_targets actor_spec
      [ Dependability_intent.Sqlite_run_event_store ]
      Dependability_intent.Prove_lifecycle
  @ rows_for_targets ~ocaml_available:false process_spec
      [ Dependability_intent.Sqlite_run_event_store ]
      Dependability_intent.Verify_reliability
  @ rows_for_targets ~ocaml_available:false crash_spec
      [ Dependability_intent.Sqlite_run_event_store ]
      Dependability_intent.Verify_full
  @ rows_for_targets ~ocaml_available:false surface_spec
      [ Dependability_intent.Sqlite_run_event_store ]
      Dependability_intent.Verify_full

let find id =
  List.find_opt (fun (row : row) -> row.capability_id = id) rows

let find_mapping ~capability_id ~target ~surface =
  List.find_opt
    (fun (row : row) ->
      row.capability_id = capability_id && row.target = target
      && row.surface = surface)
    rows

let credit_rank_local = function
  | No_credit -> 0
  | Discovery_credit -> 1
  | Structural_credit -> 2
  | Differential_credit -> 3

let duplicates values =
  let rec loop found = function
    | left :: (right :: _ as rest) when left = right -> loop (left :: found) rest
    | _ :: rest -> loop found rest
    | [] -> List.sort_uniq String.compare found
  in
  loop [] (List.sort String.compare values)

let strings_present values =
  values <> [] && List.for_all (fun value -> String.trim value <> "") values

let ontology_applies target (node : Dependability_ontology.node) =
  match node.applicability with
  | Dependability_ontology.Framework_wide -> true
  | Dependability_ontology.Targets targets -> List.mem target targets

let validate () =
  let row_ids = List.map (fun (row : row) -> row.row_id) rows in
  let mapping_ids =
    List.map
      (fun (row : row) ->
        row_identity row.capability_id row.target row.surface)
      rows
  in
  let errors =
    duplicates row_ids |> List.map (fun id -> "duplicate atlas row: " ^ id)
  in
  let errors =
    duplicates mapping_ids
    |> List.fold_left
         (fun errors id -> ("duplicate capability-target-surface mapping: " ^ id) :: errors)
         errors
  in
  let errors =
    let control_ids =
      List.map
        (fun (control : currentness_control) -> control.control_id)
        currentness_controls
    and control_digests =
      List.map
        (fun (control : currentness_control) -> control.authority_digest)
        currentness_controls
    in
    let registry_valid =
      List.sort String.compare control_ids
      = List.sort String.compare currentness_control_ids
      && duplicates control_ids = []
      && duplicates control_digests = []
      && List.for_all canonical_sha256 control_digests
    in
    if registry_valid then errors
    else "atlas currentness-control registry is not canonical" :: errors
  in
  let errors =
    List.fold_left
      (fun errors (row : row) ->
        let required_lists =
          [ ("graph units", row.graph_units); ("FPP elements", row.fpp_elements);
            ("formal obligations", row.formal_obligations);
            ("native tests", row.native_tests); ("metrics", row.metric_ids);
            ("receipt kinds", row.receipt_kinds);
            ("currentness", row.currentness_dependencies);
            ("residuals", row.residuals) ]
        in
        let errors =
          if row.row_id <> row_identity row.capability_id row.target row.surface
             || String.trim row.coordinate = "" || String.trim row.owner = ""
          then ("incomplete atlas identity: " ^ row.row_id) :: errors else errors
        in
        let errors =
          List.fold_left
            (fun errors (label, values) ->
              if strings_present values then errors
              else (Printf.sprintf "missing %s: %s" label row.row_id) :: errors)
            errors required_lists
        in
        let errors =
          let unresolved =
            List.filter
              (fun dependency ->
                resolve_currentness_dependency dependency = None)
              row.currentness_dependencies
          in
          if unresolved = []
             && duplicates row.currentness_dependencies = []
          then errors
          else ("unresolved currentness dependency: " ^ row.row_id) :: errors
        in
        let errors =
          if credit_rank_local row.projected_credit <= credit_rank_local row.source_credit
          then errors else ("projection promotes credit: " ^ row.row_id) :: errors
        in
        let errors =
          match row.intent with
          | None -> errors
          | Some operation
            when List.mem operation (Dependability_intent.operations_for_target row.target) -> errors
          | Some _ -> ("intent is not applicable to target: " ^ row.row_id) :: errors
        in
        let errors =
          match row.applicability, row.availability, row.lifecycle with
          | Applicable, Available_structural, (Implemented | Current) -> errors
          | Applicable, (Unavailable_observed_status | Blocked_status),
            (Declared | Unavailable_observed) -> errors
          | Not_applicable reason, _, _ when String.trim reason <> "" -> errors
          | _ -> ("applicability/availability/lifecycle mismatch: " ^ row.row_id) :: errors
        in
        match Dependability_ontology.find row.ontology_id with
        | None -> ("missing ontology node: " ^ row.ontology_id) :: errors
        | Some node when not (ontology_applies row.target node) ->
            ("ontology applicability drift: " ^ row.row_id) :: errors
        | Some node when node.coordinate <> row.coordinate ->
            ("coordinate drift: " ^ row.row_id) :: errors
        | Some node ->
            let unresolved =
              List.filter (fun metric -> not (List.mem metric node.metric_ids)) row.metric_ids
            in
            if unresolved = [] then errors
            else ("metric drift: " ^ row.row_id) :: errors)
      errors rows
  in
  let errors =
    List.fold_left
      (fun errors target ->
        if
          List.exists
            (fun (row : row) ->
              row.target = target && row.applicability = Applicable)
            rows
        then errors
        else ("atlas target coverage missing: " ^ Dependability_intent.target_id target) :: errors)
      errors Dependability_intent.all_targets
  in
  let errors =
    Dependability_ontology.nodes
    |> List.fold_left
         (fun errors (node : Dependability_ontology.node) ->
           match node.scale, node.applicability with
           | Dependability_ontology.Capability, Dependability_ontology.Targets targets ->
               List.fold_left
                 (fun errors target ->
                   if List.for_all
                        (fun surface ->
                          List.exists
                            (fun (row : row) ->
                              row.ontology_id = node.id && row.target = target
                              && row.surface = surface)
                            rows)
                        all_surfaces
                   then errors
                   else ("atlas applicability missing: " ^ node.id ^ " -> "
                         ^ Dependability_intent.target_id target) :: errors)
                 errors targets
           | Dependability_ontology.Capability,
             Dependability_ontology.Framework_wide -> errors
           | (Dependability_ontology.Framework | Dependability_ontology.Target), _ ->
               errors)
         errors
  in
  let surface_rows =
    List.filter
      (fun (row : row) -> row.capability_id = "sqlite.four-surfaces")
      rows
  in
  let errors =
    if
      (List.map (fun (row : row) -> row.surface) surface_rows
       |> List.sort_uniq compare)
      = (List.sort compare [ Ocaml_api; Cli; Mcp; Zenoh ])
      && List.for_all
           (fun (row : row) ->
             row.target = Dependability_intent.Sqlite_run_event_store)
           surface_rows
    then errors else "four-surface applicability is not exact" :: errors
  in
  List.sort_uniq String.compare errors

let credit_name = function
  | No_credit -> "none"
  | Discovery_credit -> "discovery"
  | Structural_credit -> "structural"
  | Differential_credit -> "differential"

let lifecycle_name = function
  | Declared -> "declared"
  | Implemented -> "implemented"
  | Current -> "current"
  | Unavailable_observed -> "unavailable-observed"

let availability_name = function
  | Available_structural -> "available-structural"
  | Unavailable_observed_status -> "unavailable-observed"
  | Blocked_status -> "blocked"

let plane_name = function
  | Dependability_intent.Control_plane -> "control-plane"
  | Dependability_intent.Data_plane -> "data-plane"
  | Dependability_intent.Both_planes -> "both-planes"

let json_strings values =
  values |> List.sort String.compare |> List.map (fun value -> `String value)

let row_json (row : row) =
  `Assoc
    [ ("applicability",
       `String (match row.applicability with Applicable -> "applicable"
                | Not_applicable _ -> "not-applicable"));
      ("availability", `String (availability_name row.availability));
      ("capability_id", `String row.capability_id);
      ("coordinate", `String row.coordinate);
      ("currentness", `List (json_strings row.currentness_dependencies));
      ("formal", `List (json_strings row.formal_obligations));
      ("fpp", `List (json_strings row.fpp_elements));
      ("graph_units", `List (json_strings row.graph_units));
      ("intent",
       match row.intent with None -> `Null | Some operation -> `String (operation_name operation));
      ("lifecycle", `String (lifecycle_name row.lifecycle));
      ("metrics", `List (json_strings row.metric_ids));
      ("native_tests", `List (json_strings row.native_tests));
      ("ontology_id", `String row.ontology_id); ("owner", `String row.owner);
      ("plane", `String (plane_name row.plane));
      ("projected_credit", `String (credit_name row.projected_credit));
      ("receipts", `List (json_strings row.receipt_kinds));
      ("residuals", `List (json_strings row.residuals));
      ("row_id", `String row.row_id);
      ("source_credit", `String (credit_name row.source_credit));
      ("surface", `String (surface_name row.surface));
      ("target", `String (Dependability_intent.target_id row.target)) ]

let meta_view () =
  rows |> List.sort (fun left right -> String.compare left.row_id right.row_id)
  |> List.map row_json
  |> fun row_values ->
  `Assoc [ ("rows", `List row_values); ("summary_total", `Int (List.length rows)) ]
  |> Yojson.Safe.to_string

let digest = meta_view () |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
let summary_total = List.length rows
