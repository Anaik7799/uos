type fractal = Operations_runtime | Evidence_chain
type coverage = Fractal_ontology.coverage = Addressed of string | Not_applicable of string
type lifecycle = Operations_run of Run_model.lifecycle
  | Governance_declaration of Ops_capability.lifecycle
type availability = Available | Unavailable_observed of string | Planned of string
type authority = Executable | Projection | Oracle | Report_only
type rule_engine = Not_rule_engine | Naive_forward_chainer | Rete_ul_engine
type aspect_evidence = Implemented_observed of string
  | Applicable_unverified of string | Planned_unavailable of string
type component = { id : string; module_path : string; purpose : string;
  level : Ops_capability.level; fractal : fractal;
  availability : availability; authority : authority; rule_engine : rule_engine;
  substantiated_aspects : Fractal_ontology.aspect list;
  aspect_evidence : (Fractal_ontology.aspect * aspect_evidence) list;
  coverage : (Fractal_ontology.aspect * coverage) list }

let authority_name = function
  | Executable -> "executable" | Projection -> "projection"
  | Oracle -> "oracle" | Report_only -> "report-only"

let evidence_for ~id ~purpose ~availability ~substantiated aspect =
  let aspect_name = Fractal_ontology.aspect_name aspect in
  match availability with
  | Planned reason ->
      Planned_unavailable
        (Printf.sprintf "%s %s is planned but unavailable: %s" id aspect_name reason)
  | Unavailable_observed reason ->
      Applicable_unverified
        (Printf.sprintf "%s %s applies but its implementation evidence is unavailable: %s"
           id aspect_name reason)
  | Available when List.mem aspect substantiated ->
      Implemented_observed
        (Printf.sprintf "%s %s is substantiated by the current module boundary: %s"
           id aspect_name purpose)
  | Available ->
      Applicable_unverified
        (Printf.sprintf "%s %s applies but has no accepted current receipt" id aspect_name)

let evidence_name = function
  | Implemented_observed _ -> "implemented-observed"
  | Applicable_unverified _ -> "applicable-unverified"
  | Planned_unavailable _ -> "planned-unavailable"

let coverage_statement ~id ~module_path ~purpose ~authority aspect evidence =
  let posture = evidence_name evidence in
  match aspect with
  | Fractal_ontology.Structural ->
      Printf.sprintf "%s is bounded by %s for %s; evidence=%s"
        id module_path purpose posture
  | Control ->
      Printf.sprintf "%s control authority is %s; evidence=%s"
        id (authority_name authority) posture
  | Data ->
      Printf.sprintf "%s data inputs, outputs, identity, and retention remain explicit; evidence=%s"
        id posture
  | Observability ->
      Printf.sprintf "%s diagnostics, metrics, and RCA visibility are applicable; evidence=%s"
        id posture
  | Performance ->
      Printf.sprintf "%s latency, cost, and resource bounds are applicable; evidence=%s" id posture
  | Scalability ->
      Printf.sprintf "%s workload growth and boundedness are applicable; evidence=%s" id posture
  | Availability ->
      Printf.sprintf "%s dependency absence and degraded behavior are explicit; evidence=%s" id posture
  | Integrity ->
      Printf.sprintf "%s cannot gain completion credit from this ontology projection; evidence=%s"
        id posture
  | Security ->
      Printf.sprintf "%s trust boundaries and authority escalation are applicable; evidence=%s"
        id posture
  | Sdlc ->
      Printf.sprintf "%s change, test, review, and exact-head gates are applicable; evidence=%s"
        id posture
  | Sre ->
      Printf.sprintf "%s operation, failure response, and recovery are applicable; evidence=%s"
        id posture

let coverage ~id ~module_path ~purpose ~authority aspect_evidence =
  List.map
    (fun aspect ->
      let evidence = List.assoc aspect aspect_evidence in
      (aspect, Addressed
         (coverage_statement ~id ~module_path ~purpose ~authority aspect evidence)))
    Fractal_ontology.aspects

let component ?(level = Ops_capability.LX) ?(fractal = Operations_runtime)
    ?(availability = Available) ?(authority = Executable)
    ?(rule_engine = Not_rule_engine) ?(addressed = []) id module_path purpose =
  let substantiated_aspects =
    match availability with
    | Available -> List.sort_uniq compare (Fractal_ontology.Structural :: addressed)
    | Planned _ | Unavailable_observed _ -> []
  in
  let aspect_evidence =
    List.map
      (fun aspect ->
        (aspect, evidence_for ~id ~purpose ~availability ~substantiated:substantiated_aspects aspect))
      Fractal_ontology.aspects
  in
  { id; module_path; purpose; level; fractal; availability; authority; rule_engine;
    substantiated_aspects; aspect_evidence;
    coverage = coverage ~id ~module_path ~purpose ~authority aspect_evidence }

let planned reason = Planned reason
let unavailable reason = Unavailable_observed reason

let all =
  [ component "prompt" "modules/hermes_ops/ops_command.ml"
      "Typed task objective entering the declarative command algebra";
    component "command" "modules/hermes_ops/ops_command_service.ml"
      "Validated control-plane command resolved from a declarative intent";
    component ~rule_engine:Naive_forward_chainer "rete_naive"
      "modules/hermes_harness/hermes_rete.ml"
      "Naive differential forward chainer; it has no alpha/beta Rete network";
    component ~availability:(planned "no bounded alpha/beta Rete_UL engine is present")
      ~authority:Projection ~rule_engine:Rete_ul_engine "rete_ul"
      "modules/hermes_harness/rete_ul.ml"
      "Target bounded Rete_UL mediation, unavailable until engine and trace receipts exist";
    component ~availability:(planned "no dedicated Raven/MCDA module is present")
      ~authority:Projection "raven_matrix"
      "modules/hermes_ops_dashboard/run_raven_matrix.ml"
      "Target deterministic decision matrix with no external ML verdict authority";
    component ~availability:(unavailable "only obligation declarations are present; no current STPA analysis receipt")
      ~authority:Projection "stpa" "modules/hermes_ops/ops_governance.ml"
      "STPA hazard and unsafe-control-action obligation declaration";
    component ~availability:(unavailable "only obligation declarations are present; no current FMEA analysis receipt")
      ~authority:Projection "fmea" "modules/hermes_ops/ops_governance.ml"
      "FMEA residual-risk obligation declaration";
    component ~authority:Report_only ~addressed:[ Fractal_ontology.Data ]
      "ruliad" "modules/hermes_harness/ruliad.ml"
      "Bounded multiway rule-space analysis without verdict authority";
    component ~authority:Report_only "stan" "modules/hermes_harness/receipt_reliability.ml"
      "Beta-Binomial reliability annotation without parity authority";
    component ~authority:Oracle "z3" "modules/hermes_ops/ops_formal.ml"
      "External-solver runner; each solver verdict remains separately available or unavailable";
    component ~addressed:[ Fractal_ontology.Sdlc ] "assurance" "modules/hermes_ops/ops_verify.ml"
      "Current exact-head assurance receipt aggregation";
    component
      ~addressed:
        [ Fractal_ontology.Control; Integrity; Security; Sdlc; Sre ]
      "swarm_bridge" "modules/hermes_ops_dashboard/run_swarm_bridge.ml"
      "Sole exact-head admission, apply-once effect, durable attempt, and Swarm execution authority";
    component "swarm" "modules/swarm/sop_execution.ml"
      "Non-creditable domain-wave scheduler invoked only by the admitted bridge";
    component "run" "modules/hermes_ops_dashboard/run_model.ml"
      "One exact-head operations execution identity";
    component ~level:Ops_capability.L5 ~fractal:Evidence_chain "event"
      "modules/hermes_ops_dashboard/run_model.ml"
      "Canonical append-only observation of operations behavior, not parity by itself";
    component ~fractal:Evidence_chain
      ~addressed:[ Fractal_ontology.Security; Sdlc; Sre ] "store"
      "modules/hermes_ops_dashboard/run_event_store.ml"
      "Single-writer immutable run-event authority";
    component ~addressed:[ Fractal_ontology.Observability; Sre ]
      "resource_sampler" "modules/hermes_ops_dashboard/run_resource_sampler.ml"
      "Fail-closed process and host observation boundary";
    component ~fractal:Evidence_chain
      ~addressed:[ Fractal_ontology.Observability; Data; Sdlc ] "metrics"
      "modules/hermes_ops_dashboard/run_metrics.ml"
      "Closed metric and FPP-channel authority";
    component ~fractal:Evidence_chain
      ~addressed:[ Fractal_ontology.Observability; Data; Sdlc ] "diagnostics"
      "modules/hermes_ops_dashboard/run_trace.ml"
      "Fractally correlated OTLP diagnostics and traces";
    component ~addressed:[ Fractal_ontology.Performance; Sdlc ]
      "fast_path" "modules/hermes_ops_dashboard/run_fast_path.ml"
      "Hysteretic, equivalence-gated data-path selection";
    component ~fractal:Evidence_chain
      ~addressed:[ Fractal_ontology.Observability; Data; Sdlc ] "trace"
      "modules/hermes_ops_dashboard/run_trace.ml"
      "Bounded W3C trace graph for one exact-head run";
    component ~fractal:Evidence_chain "completion_criterion"
      "modules/hermes_ops_dashboard/run_algebra.ml"
      "Non-vacuous current-run completion criterion";
    component ~level:Ops_capability.L6 ~fractal:Evidence_chain
      ~availability:(planned "no typed completion-receipt carrier is implemented")
      ~authority:Projection "completion_receipt"
      "modules/hermes_ops_dashboard/run_completion_receipt.ml"
      "Target operations-completion receipt, explicitly not automatic parity credit";
    component ~authority:Projection "zenoh" "modules/hermes_harness/hermes_zenoh.ml"
      "Control/data state projection transport";
    component ~availability:(planned "Task 5+ Dream server module is absent")
      ~authority:Projection "dream" "modules/hermes_ops_dashboard/run_server.ml"
      "Same-origin HTTP and WebSocket projection boundary";
    component ~availability:(planned "Task 5+ Bonsai reducer module is absent")
      ~authority:Projection "bonsai" "modules/hermes_ops_dashboard/run_bonsai_domain.ml"
      "Pure browser read-model reducer";
    component ~availability:(planned "Task 5+ WebGL scene module is absent")
      ~authority:Projection "webgl" "modules/hermes_ops_dashboard/run_webgl_scene.ml"
      "Declarative multidimensional visualization projection";
    component ~availability:(planned "Task 5+ typed table intent module is absent")
      ~authority:Projection "table" "modules/hermes_ops_dashboard/run_ui_intent.ml"
      "Accessible bounded tabular projection";
    component ~fractal:Evidence_chain
      ~availability:(planned "Task 5+ projection receipt carrier is absent")
      ~authority:Projection "projection_receipt"
      "modules/hermes_ops_dashboard/run_ui_intent.ml"
      "Observational delivery receipt with no admission authority";
    component ~fractal:Evidence_chain "projection_criterion"
      "modules/hermes_ops_dashboard/run_algebra.ml"
      "Read-surface freshness criterion separated from completion";
    component "run_ontology" "modules/hermes_ops_dashboard/run_ontology.ml"
      "Total operations component/aspect registry";
    component "run_atlas" "modules/hermes_ops_dashboard/run_atlas.ml"
      "Continuous typed paths without visualization-to-admission flow";
    component ~addressed:[ Fractal_ontology.Data; Sdlc ]
      "run_algebra" "modules/hermes_ops_dashboard/run_algebra.ml"
      "Executable fold, projection, RCA, and OODA laws" ]

let components = List.map (fun component -> component.id) all
let find id = List.find_opt (fun component -> String.equal component.id id) all

let ( let* ) value f = match value with Ok result -> f result | Error _ as error -> error

let unique label values =
  if List.length values = List.length (List.sort_uniq String.compare values) then Ok ()
  else Error (label ^ " must be unique")

let absent_module_ids =
  [ "rete_ul"; "raven_matrix"; "completion_receipt"; "dream"; "bonsai";
    "webgl"; "table"; "projection_receipt" ]

let constrained_authority id =
  if List.mem id
      [ "rete_ul"; "raven_matrix"; "stpa"; "fmea"; "completion_receipt";
        "zenoh"; "dream"; "bonsai"; "webgl"; "table";
        "projection_receipt" ]
  then Some Projection
  else if List.mem id [ "ruliad"; "stan" ] then Some Report_only
  else if String.equal id "z3" then Some Oracle
  else None

let validate_component component =
  let* () =
    if String.trim component.id = "" || String.trim component.module_path = ""
       || String.trim component.purpose = "" then Error "ontology identity must be nonempty"
    else Ok () in
  let aspects = List.map fst component.coverage in
  let* () = unique (component.id ^ " aspects")
      (List.map Fractal_ontology.aspect_name aspects) in
  let expected = List.map Fractal_ontology.aspect_name Fractal_ontology.aspects
      |> List.sort String.compare in
  let observed = List.map Fractal_ontology.aspect_name aspects |> List.sort String.compare in
  let* () = if expected = observed then Ok () else Error (component.id ^ " does not cover all eleven aspects") in
  let evidence_aspects = List.map fst component.aspect_evidence in
  let* () = unique (component.id ^ " aspect-evidence keys")
      (List.map Fractal_ontology.aspect_name evidence_aspects) in
  let observed_evidence =
    List.map Fractal_ontology.aspect_name evidence_aspects |> List.sort String.compare in
  let* () =
    if expected = observed_evidence then Ok ()
    else Error (component.id ^ " does not type all eleven aspect evidence postures")
  in
  let* () = unique (component.id ^ " substantiated aspects")
      (List.map Fractal_ontology.aspect_name component.substantiated_aspects) in
  let* () =
    if List.for_all (fun aspect -> List.mem aspect Fractal_ontology.aspects)
        component.substantiated_aspects
    then Ok () else Error (component.id ^ " has an unknown substantiated aspect")
  in
  let* () =
    match component.availability with
    | Available -> Ok ()
    | Planned reason | Unavailable_observed reason ->
        if String.trim reason = "" then Error (component.id ^ " availability reason is empty")
        else Ok ()
  in
  let* () =
    if List.mem component.id absent_module_ids && component.availability = Available
    then Error (component.id ^ " has no implementation module and cannot be available")
    else Ok ()
  in
  let* () =
    match constrained_authority component.id with
    | None -> Ok ()
    | Some expected when component.authority = expected -> Ok ()
    | Some _ -> Error (component.id ^ " exceeds its declared authority")
  in
  let* () =
    match component.rule_engine with
    | Not_rule_engine -> Ok ()
    | Naive_forward_chainer ->
        if String.equal component.id "rete_naive"
           && String.equal component.module_path "modules/hermes_harness/hermes_rete.ml"
           && component.availability = Available then Ok ()
        else Error "the Hermes naive forward chainer is mislabeled"
    | Rete_ul_engine ->
        if String.equal component.id "rete_ul" && component.availability <> Available
        then Ok () else Error "Rete_UL cannot be promoted without its bounded engine"
  in
  let expected_evidence =
    List.map
      (fun aspect ->
        (aspect, evidence_for ~id:component.id ~purpose:component.purpose
           ~availability:component.availability
           ~substantiated:component.substantiated_aspects aspect))
      Fractal_ontology.aspects
  in
  let* () =
    if component.aspect_evidence = expected_evidence then Ok ()
    else Error (component.id ^ " aspect evidence posture is unsubstantiated")
  in
  let* () =
    if List.for_all
        (fun (_, evidence) ->
          let reason = match evidence with Implemented_observed reason
            | Applicable_unverified reason | Planned_unavailable reason -> reason in
          String.trim reason <> "")
        component.aspect_evidence
    then Ok () else Error (component.id ^ " has an empty aspect evidence reason")
  in
  let rec claims = function
    | [] -> Ok ()
    | (_aspect, claim) :: rest ->
        let text = match claim with Addressed text | Not_applicable text -> text in
        let* () = if String.trim text = "" then Error (component.id ^ " has an empty coverage claim") else Ok () in
        let* () = match claim with
          | Not_applicable _ ->
              Error (component.id ^ " cannot mark a mandatory systems aspect not applicable")
          | Addressed _ -> Ok () in
        claims rest
  in
  claims component.coverage

let validate_components declarations =
  let* () = if declarations = [] then Error "operations ontology must be nonempty" else Ok () in
  let* () = unique "operations component ids" (List.map (fun item -> item.id) declarations) in
  let rec loop = function [] -> Ok () | component :: rest ->
    let* () = validate_component component in loop rest in
  loop declarations

let validate () = validate_components all
