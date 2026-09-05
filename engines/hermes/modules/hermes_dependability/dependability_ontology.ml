type scale = Framework | Target | Capability
type kind = Controller | Controlled_process | Evidence | Formal_model | Surface

type component_kind =
  | Framework_component
  | Target_component of Dependability_intent.target
  | Statement_lifecycle_component
  | Database_close_component
  | Actor_cleanup_component
  | Process_reliability_component
  | Crash_window_component
  | Lifecycle_formal_component
  | Fpp_mbse_component
  | Surface_gateway_component
  | Evidence_path_component of Dependability_intent.target
  | Closure_path_component of Dependability_intent.target

type oracle_kind =
  | No_oracle
  | Finite_transition_oracle
  | Z3_oracle
  | Native_sqlite_oracle
  | Swarm_process_oracle
  | Kernel_journal_oracle
  | Projection_oracle

type metric_kind = Counter | Gauge | Histogram | State_metric
type path_role = Admission_path | Evidence_path | Closure_path
type applicability = Framework_wide | Targets of Dependability_intent.target list
type evidence_status =
  | Declared_only
  | Implemented_structural
  | Tested_structural
  | Execution_unavailable
  | Differentially_verified

type evidence_currentness =
  | Current_evidence of {
      authority_digest : string;
      receipt_digest : string;
    }
  | Stale_evidence of {
      authority_digest : string;
      observed_digest : string;
    }
  | Currentness_unavailable of {
      authority_digest : string;
      diagnostic_digest : string;
    }

type hazard = { hazard_id : string; description : string }
type metric = { metric_id : string; metric_kind : metric_kind }
type source = { source_id : string; path : string }

type node = {
  id : string;
  parent_id : string option;
  coordinate : string;
  scale : scale;
  kind : kind;
  component_kind : component_kind;
  oracle_kind : oracle_kind;
  applicability : applicability;
  path_role : path_role;
  evidence_status : evidence_status;
  evidence_currentness : evidence_currentness;
  rca_origin : string;
  controller : string;
  controlled_process : string;
  control_actions : string list;
  feedback : string list;
  losses : string list;
  hazards : string list;
  unsafe_control_actions : string list;
  fmea : string list;
  safety_constraints : string list;
  sources : string list;
  implementation_paths : string list;
  test_paths : string list;
  metric_ids : string list;
  evidence_posture : string;
  provenance : string;
  owner : string;
  evolution_version : int;
}

let hazards =
  [ { hazard_id = "HZ-SQL-FIN-01";
      description = "SQLite lifetime release races or acknowledges false closure" };
    { hazard_id = "HZ-DET-01";
      description = "Verification evidence is nondeterministic or falsely promoted" } ]

let metrics =
  [ { metric_id = "dependability.graph.nodes"; metric_kind = Gauge };
    { metric_id = "dependability.criteria.failed"; metric_kind = Counter };
    { metric_id = "sqlite.statements.open"; metric_kind = Gauge };
    { metric_id = "sqlite.finalize.attempts"; metric_kind = Counter };
    { metric_id = "sqlite.close.attempts"; metric_kind = Counter };
    { metric_id = "sqlite.close.refusals"; metric_kind = Counter };
    { metric_id = "sqlite.actor.pending"; metric_kind = Gauge };
    { metric_id = "sqlite.actor.closed"; metric_kind = State_metric };
    { metric_id = "dependability.attempts.required"; metric_kind = Gauge };
    { metric_id = "dependability.attempts.completed"; metric_kind = Counter };
    { metric_id = "dependability.children.signalled"; metric_kind = Counter };
    { metric_id = "sqlite.kernel_crash.matches"; metric_kind = Counter };
    { metric_id = "sqlite.journal.available"; metric_kind = State_metric };
    { metric_id = "dependability.formal.proved"; metric_kind = Counter };
    { metric_id = "dependability.formal.refuted"; metric_kind = Counter };
    { metric_id = "dependability.formal.unavailable"; metric_kind = Counter };
    { metric_id = "dependability.model.dangling"; metric_kind = Gauge };
    { metric_id = "dependability.surface.requests"; metric_kind = Counter };
    { metric_id = "dependability.surface.errors"; metric_kind = Counter } ]

let sources =
  [ { source_id = "source.overlap-map"; path = "docs/hermes/zigvm-overlap-map.md" };
    { source_id = "source.intent";
      path = "modules/hermes_dependability/dependability_intent.ml" };
    { source_id = "source.graph";
      path = "modules/hermes_dependability/dependability_graph.ml" };
    { source_id = "source.algebra";
      path = "modules/hermes_dependability/dependability_algebra.ml" };
    { source_id = "source.ontology";
      path = "modules/hermes_dependability/dependability_ontology.ml" };
    { source_id = "source.atlas";
      path = "modules/hermes_dependability/dependability_atlas.ml" };
    { source_id = "source.surface";
      path = "modules/hermes_dependability/dependability_surface.ml" };
    { source_id = "source.sqlite-effect";
      path = "modules/hermes_dependability/dependability_sqlite.ml" };
    { source_id = "source.sqlite-model";
      path = "modules/hermes_dependability/sqlite_lifecycle_model.ml" };
    { source_id = "source.sqlite-solver";
      path = "modules/hermes_dependability/sqlite_lifecycle_solver.ml" };
    { source_id = "source.test-core";
      path = "modules/hermes_dependability/test_dependability_core.ml" };
    { source_id = "source.test-graph";
      path = "modules/hermes_dependability/test_dependability_graph.ml" };
    { source_id = "source.test-meta";
      path = "modules/hermes_dependability/test_dependability_meta.ml" };
    { source_id = "source.test-sqlite-model";
      path = "modules/hermes_dependability/test_sqlite_lifecycle_model.ml" };
    { source_id = "source.test-sqlite-smt";
      path = "modules/hermes_dependability/test_sqlite_lifecycle_smt.ml" };
    { source_id = "source.target.run-event-store";
      path = "modules/hermes_ops_dashboard/run_event_store.ml" };
    { source_id = "source.target.sa-plan-store";
      path = "modules/sa_plan/sa_plan_store.ml" };
    { source_id = "source.target.ops-completion-history";
      path = "modules/hermes_ops/ops_completion_history.ml" };
    { source_id = "source.target.evidence-store";
      path = "modules/hermes_harness/evidence_store.ml" } ]

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let source_authority_rows source_ids =
  source_ids
  |> List.map (fun source_id ->
         match
           List.find_opt
             (fun (source : source) -> source.source_id = source_id)
             sources
         with
         | Some source -> source.source_id ^ "=" ^ source.path
         | None -> source_id ^ "=<unresolved>")
  |> List.sort String.compare

let currentness_authority_digest ~id ~sources:source_ids ~implementation_paths
    ~test_paths ~evolution_version ~origin =
  [ "ontology-id=" ^ id; "origin=" ^ origin;
    "evolution=" ^ string_of_int evolution_version ]
  @ List.map (fun value -> "source=" ^ value)
      (source_authority_rows source_ids)
  @ List.map (fun value -> "implementation=" ^ value)
      (List.sort String.compare implementation_paths)
  @ List.map (fun value -> "test=" ^ value)
      (List.sort String.compare test_paths)
  |> String.concat "\n" |> sha256

let all_targets = Dependability_intent.all_targets
let sqlite_hazards = [ "HZ-SQL-FIN-01"; "HZ-DET-01" ]
let losses = [ "L-EVIDENCE-FALSE-GREEN"; "L-AVAILABILITY-CRASH" ]
let ucas = [ "UCA-SQL-FIN-01" ]
let fmea = [ "FM-SQL-DOUBLE-FINALIZE"; "FM-SQL-CLOSE-IGNORED" ]
let constraints = [ "SC-SQL-SINGLE-OWNER"; "SC-SQL-CLOSE-ACK" ]
let provenance = "ZigVM P1-P7 algebra; Hermes strengthened refinement"
let owner = "hermes-dependability"

let make ~id ~parent_id ~coordinate ~scale ~kind ~component_kind ~oracle_kind
    ~applicability ~path_role ~evidence_status ~rca_origin ~controller
    ~controlled_process ~control_actions ~feedback ~losses ~hazards
    ~unsafe_control_actions ~fmea ~safety_constraints ~sources
    ~implementation_paths ~test_paths ~metric_ids ~evidence_posture ~provenance
    ~owner ~evolution_version =
  let authority_digest =
    currentness_authority_digest ~id ~sources ~implementation_paths ~test_paths
      ~evolution_version ~origin:provenance
  in
  let diagnostic_digest =
    sha256 ("pure-core-currentness-receipt-unavailable:" ^ authority_digest)
  in
  let evidence_currentness =
    Currentness_unavailable { authority_digest; diagnostic_digest }
  in
  let provenance =
    String.concat ":"
      [ "currentness"; "unavailable"; authority_digest; diagnostic_digest ]
  in
  { id; parent_id; coordinate; scale; kind; component_kind; oracle_kind;
    applicability; path_role; evidence_status; evidence_currentness; rca_origin; controller;
    controlled_process; control_actions; feedback; losses; hazards;
    unsafe_control_actions; fmea; safety_constraints; sources;
    implementation_paths; test_paths; metric_ids; evidence_posture; provenance;
    owner; evolution_version }

let target_node target source_id source_path test_path =
  let target_id = Dependability_intent.target_id target in
  make ~id:("target." ^ target_id) ~parent_id:(Some "dependability.framework")
    ~coordinate:("L1/dependability/" ^ String.map (function '.' -> '/' | c -> c) target_id)
    ~scale:Target ~kind:Controlled_process ~component_kind:(Target_component target)
    ~oracle_kind:No_oracle ~applicability:(Targets [ target ])
    ~path_role:Admission_path ~evidence_status:Implemented_structural
    ~rca_origin:"Control" ~controller:"DependabilityAdmission"
    ~controlled_process:(target_id ^ " SQLite component")
    ~control_actions:[ "admit target"; "bind source authority" ]
    ~feedback:[ "target digest"; "admission error" ] ~losses
    ~hazards:sqlite_hazards ~unsafe_control_actions:ucas ~fmea
    ~safety_constraints:constraints ~sources:[ source_id ]
    ~implementation_paths:[ source_path ] ~test_paths:[ test_path ]
    ~metric_ids:[ "dependability.criteria.failed" ]
    ~evidence_posture:"implemented source identity; execution credit unavailable"
    ~provenance ~owner ~evolution_version:1

let target_path_nodes target source_id source_path test_path =
  let target_id = Dependability_intent.target_id target in
  let target_node_id = "target." ^ target_id in
  let evidence_id = "path." ^ target_id ^ ".evidence" in
  let evidence =
    make ~id:evidence_id ~parent_id:(Some target_node_id)
      ~coordinate:
        ("L2/dependability/" ^ String.map (function '.' -> '/' | c -> c) target_id
         ^ "/evidence")
      ~scale:Target ~kind:Evidence ~component_kind:(Evidence_path_component target)
      ~oracle_kind:No_oracle ~applicability:(Targets [ target ])
      ~path_role:Evidence_path ~evidence_status:Implemented_structural
      ~rca_origin:"Control" ~controller:"DependabilityEvidencePath"
      ~controlled_process:(target_id ^ " evidence admission path")
      ~control_actions:[ "bind structural evidence"; "refuse execution promotion" ]
      ~feedback:[ "evidence identity"; "currentness unavailable" ] ~losses
      ~hazards:sqlite_hazards ~unsafe_control_actions:ucas ~fmea
      ~safety_constraints:constraints ~sources:[ source_id ]
      ~implementation_paths:[ source_path ] ~test_paths:[ test_path ]
      ~metric_ids:[ "dependability.criteria.failed" ]
      ~evidence_posture:"target evidence path is structural only"
      ~provenance ~owner ~evolution_version:1
  in
  let closure =
    make ~id:("path." ^ target_id ^ ".closure")
      ~parent_id:(Some evidence_id)
      ~coordinate:
        ("L2/dependability/" ^ String.map (function '.' -> '/' | c -> c) target_id
         ^ "/closure")
      ~scale:Target ~kind:Controlled_process
      ~component_kind:(Closure_path_component target) ~oracle_kind:No_oracle
      ~applicability:(Targets [ target ]) ~path_role:Closure_path
      ~evidence_status:Execution_unavailable ~rca_origin:"Control"
      ~controller:"DependabilityClosurePath"
      ~controlled_process:(target_id ^ " terminal evidence closure")
      ~control_actions:[ "observe terminal receipt"; "close without promotion" ]
      ~feedback:[ "terminal posture"; "unavailable receipt" ] ~losses
      ~hazards:sqlite_hazards ~unsafe_control_actions:ucas ~fmea
      ~safety_constraints:constraints ~sources:[ source_id ]
      ~implementation_paths:[ source_path ] ~test_paths:[ test_path ]
      ~metric_ids:[ "dependability.criteria.failed" ]
      ~evidence_posture:"runtime closure receipt unavailable in the pure core"
      ~provenance ~owner ~evolution_version:1
  in
  [ evidence; closure ]

let capability ~id ~coordinate ~kind ~component_kind ~oracle_kind ~applicability
    ~path_role ~evidence_status ~controller ~controlled_process ~control_actions
    ~feedback ~sources ~implementation_paths ~test_paths ~metric_ids
    ~evidence_posture =
  make ~id ~parent_id:(Some "dependability.framework") ~coordinate
    ~scale:Capability ~kind ~component_kind ~oracle_kind ~applicability ~path_role
    ~evidence_status ~rca_origin:"Control" ~controller ~controlled_process
    ~control_actions ~feedback ~losses ~hazards:sqlite_hazards
    ~unsafe_control_actions:ucas ~fmea ~safety_constraints:constraints ~sources
    ~implementation_paths ~test_paths ~metric_ids ~evidence_posture ~provenance
    ~owner ~evolution_version:1

let base_nodes =
  [ make ~id:"dependability.framework" ~parent_id:None
      ~coordinate:"L0/dependability" ~scale:Framework ~kind:Controller
      ~component_kind:Framework_component ~oracle_kind:No_oracle
      ~applicability:Framework_wide ~path_role:Admission_path
      ~evidence_status:Tested_structural ~rca_origin:"Control"
      ~controller:"IntentAdmission" ~controlled_process:"dependability evidence pipeline"
      ~control_actions:[ "admit typed intent"; "reject ambiguous intent" ]
      ~feedback:[ "graph identity"; "completion posture" ] ~losses
      ~hazards:sqlite_hazards ~unsafe_control_actions:ucas ~fmea
      ~safety_constraints:constraints
      ~sources:[ "source.intent"; "source.graph"; "source.overlap-map" ]
      ~implementation_paths:
        [ "modules/hermes_dependability/dependability_intent.ml";
          "modules/hermes_dependability/dependability_graph.ml" ]
      ~test_paths:
        [ "modules/hermes_dependability/test_dependability_core.ml";
          "modules/hermes_dependability/test_dependability_graph.ml" ]
      ~metric_ids:[ "dependability.graph.nodes" ]
      ~evidence_posture:"pure authority tested; execution credit unavailable"
      ~provenance ~owner ~evolution_version:1;
    target_node Dependability_intent.Sqlite_run_event_store
      "source.target.run-event-store" "modules/hermes_ops_dashboard/run_event_store.ml"
      "modules/hermes_ops_dashboard/test_run_event_store.ml";
    target_node Dependability_intent.Sqlite_sa_plan_store
      "source.target.sa-plan-store" "modules/sa_plan/sa_plan_store.ml"
      "modules/sa_plan/test_sa_plan_store.ml";
    target_node Dependability_intent.Sqlite_ops_completion_history
      "source.target.ops-completion-history"
      "modules/hermes_ops/ops_completion_history.ml"
      "modules/hermes_ops/test_ops_completion_history.ml";
    target_node Dependability_intent.Sqlite_evidence_store
      "source.target.evidence-store" "modules/hermes_harness/evidence_store.ml"
      "modules/hermes_harness/test_evidence_store.ml";
    capability ~id:"sqlite.statement-lifetime"
      ~coordinate:"L2/dependability/sqlite/statement-lifetime"
      ~kind:Controlled_process ~component_kind:Statement_lifecycle_component
      ~oracle_kind:Native_sqlite_oracle ~applicability:(Targets all_targets)
      ~path_role:Evidence_path ~evidence_status:Tested_structural
      ~controller:"StatementLifetime" ~controlled_process:"SQLite prepared statement"
      ~control_actions:[ "prepare"; "step"; "finalize" ]
      ~feedback:[ "finalize result"; "live statement count" ]
      ~sources:[ "source.sqlite-effect"; "source.sqlite-model" ]
      ~implementation_paths:[ "modules/hermes_dependability/dependability_sqlite.ml" ]
      ~test_paths:[ "modules/hermes_dependability/test_sqlite_lifecycle_model.ml" ]
      ~metric_ids:[ "sqlite.statements.open"; "sqlite.finalize.attempts" ]
      ~evidence_posture:"finite and effect code tested structurally; native overlap unavailable";
    capability ~id:"sqlite.database-close"
      ~coordinate:"L2/dependability/sqlite/database-close"
      ~kind:Controlled_process ~component_kind:Database_close_component
      ~oracle_kind:Native_sqlite_oracle ~applicability:(Targets all_targets)
      ~path_role:Closure_path ~evidence_status:Tested_structural
      ~controller:"DatabaseCloseAuthority" ~controlled_process:"SQLite database handle"
      ~control_actions:[ "quiesce"; "close"; "acknowledge" ]
      ~feedback:[ "busy refusal"; "terminal close receipt" ]
      ~sources:[ "source.sqlite-effect"; "source.sqlite-model" ]
      ~implementation_paths:[ "modules/hermes_dependability/dependability_sqlite.ml" ]
      ~test_paths:[ "modules/hermes_dependability/test_sqlite_lifecycle_model.ml" ]
      ~metric_ids:[ "sqlite.close.attempts"; "sqlite.close.refusals" ]
      ~evidence_posture:"bounded close authority tested structurally; execution unavailable";
    capability ~id:"sqlite.actor-cleanup"
      ~coordinate:"L2/dependability/sqlite/actor-cleanup" ~kind:Controller
      ~component_kind:Actor_cleanup_component ~oracle_kind:Finite_transition_oracle
      ~applicability:(Targets [ Dependability_intent.Sqlite_run_event_store ])
      ~path_role:Evidence_path ~evidence_status:Implemented_structural
      ~controller:"RunEventStoreCleanup" ~controlled_process:"Run event store writer actor"
      ~control_actions:[ "drain"; "elect closer"; "join" ]
      ~feedback:[ "generation receipt"; "writer terminal receipt" ]
      ~sources:[ "source.sqlite-model"; "source.target.run-event-store" ]
      ~implementation_paths:[ "modules/hermes_dependability/sqlite_lifecycle_model.ml" ]
      ~test_paths:[ "modules/hermes_dependability/test_sqlite_lifecycle_model.ml" ]
      ~metric_ids:[ "sqlite.actor.pending"; "sqlite.actor.closed" ]
      ~evidence_posture:"finite actor refinement implemented; native actor receipt unavailable";
    capability ~id:"sqlite.process-reliability"
      ~coordinate:"L2/dependability/sqlite/process-reliability" ~kind:Evidence
      ~component_kind:Process_reliability_component ~oracle_kind:Swarm_process_oracle
      ~applicability:(Targets [ Dependability_intent.Sqlite_run_event_store ])
      ~path_role:Evidence_path ~evidence_status:Execution_unavailable
      ~controller:"SwarmVerifier" ~controlled_process:"300 process attempt effects"
      ~control_actions:[ "admit attempt"; "observe child"; "aggregate" ]
      ~feedback:[ "attempt receipt"; "aggregate verdict" ]
      ~sources:[ "source.graph"; "source.target.run-event-store" ]
      ~implementation_paths:[ "modules/hermes_dependability/dependability_graph.ml" ]
      ~test_paths:[ "modules/hermes_dependability/test_dependability_graph.ml" ]
      ~metric_ids:
        [ "dependability.attempts.required"; "dependability.attempts.completed";
          "dependability.children.signalled" ]
      ~evidence_posture:"300-node topology implemented; Swarm execution unavailable";
    capability ~id:"sqlite.kernel-crash-window"
      ~coordinate:"L2/dependability/sqlite/kernel-crash-window" ~kind:Evidence
      ~component_kind:Crash_window_component ~oracle_kind:Kernel_journal_oracle
      ~applicability:(Targets [ Dependability_intent.Sqlite_run_event_store ])
      ~path_role:Evidence_path ~evidence_status:Execution_unavailable
      ~controller:"CrashWindowOracle" ~controlled_process:"bounded kernel journal interval"
      ~control_actions:[ "open cursor"; "close cursor"; "match" ]
      ~feedback:[ "journal availability"; "crash match" ]
      ~sources:[ "source.graph" ]
      ~implementation_paths:[ "modules/hermes_dependability/dependability_graph.ml" ]
      ~test_paths:[ "modules/hermes_dependability/test_dependability_graph.ml" ]
      ~metric_ids:[ "sqlite.kernel_crash.matches"; "sqlite.journal.available" ]
      ~evidence_posture:"declarative graph node only; journal oracle unavailable";
    capability ~id:"sqlite.lifecycle-formal"
      ~coordinate:"L3/dependability/sqlite/lifecycle-formal" ~kind:Formal_model
      ~component_kind:Lifecycle_formal_component ~oracle_kind:Z3_oracle
      ~applicability:(Targets all_targets) ~path_role:Evidence_path
      ~evidence_status:Tested_structural ~controller:"FormalChecker"
      ~controlled_process:"SQLite lifetime finite transition authority"
      ~control_actions:[ "explore"; "prove negation"; "run satisfiable control" ]
      ~feedback:[ "theorem verdict"; "mutant witness" ]
      ~sources:[ "source.sqlite-model"; "source.sqlite-solver" ]
      ~implementation_paths:
        [ "modules/hermes_dependability/sqlite_lifecycle_model.ml";
          "modules/hermes_dependability/sqlite_lifecycle_solver.ml" ]
      ~test_paths:
        [ "modules/hermes_dependability/test_sqlite_lifecycle_model.ml";
          "modules/hermes_dependability/test_sqlite_lifecycle_smt.ml" ]
      ~metric_ids:
        [ "dependability.formal.proved"; "dependability.formal.refuted";
          "dependability.formal.unavailable" ]
      ~evidence_posture:"finite model and live solver tested; native semantics separate";
    capability ~id:"sqlite.fpp-mbse"
      ~coordinate:"L3/dependability/sqlite/fpp-mbse" ~kind:Controller
      ~component_kind:Fpp_mbse_component ~oracle_kind:Projection_oracle
      ~applicability:(Targets all_targets) ~path_role:Evidence_path
      ~evidence_status:Implemented_structural ~controller:"FppMbseProjection"
      ~controlled_process:"typed system projections"
      ~control_actions:[ "validate"; "project" ]
      ~feedback:[ "topology agreement"; "dangling link" ]
      ~sources:[ "source.ontology"; "source.atlas"; "source.algebra" ]
      ~implementation_paths:
        [ "modules/hermes_dependability/dependability_ontology.ml";
          "modules/hermes_dependability/dependability_atlas.ml";
          "modules/hermes_dependability/dependability_algebra.ml" ]
      ~test_paths:[ "modules/hermes_dependability/test_dependability_meta.ml" ]
      ~metric_ids:[ "dependability.model.dangling" ]
      ~evidence_posture:"typed semantic authority implemented; generated projections unavailable";
    capability ~id:"sqlite.four-surfaces"
      ~coordinate:"L4/dependability/sqlite/four-surfaces" ~kind:Surface
      ~component_kind:Surface_gateway_component ~oracle_kind:No_oracle
      ~applicability:(Targets [ Dependability_intent.Sqlite_run_event_store ])
      ~path_role:Closure_path ~evidence_status:Execution_unavailable
      ~controller:"SurfaceGateway" ~controlled_process:"four declarative command surfaces"
      ~control_actions:[ "normalize request"; "normalize receipt" ]
      ~feedback:[ "surface error"; "canonical receipt" ]
      ~sources:[ "source.intent"; "source.atlas"; "source.surface" ]
      ~implementation_paths:
        [ "modules/hermes_dependability/dependability_intent.ml";
          "modules/hermes_dependability/dependability_intent.mli";
          "modules/hermes_dependability/dependability_surface.ml";
          "modules/hermes_dependability/dependability_surface.mli" ]
      ~test_paths:[ "modules/hermes_dependability/test_dependability_surface.ml" ]
      ~metric_ids:[ "dependability.surface.requests"; "dependability.surface.errors" ]
      ~evidence_posture:
        "canonical v1 four-surface codecs, normalized receipts, recording dispatcher, and read-only status projection focused-tested; live CLI, MCP server, Zenoh network, and Run_swarm_bridge execution unavailable until Task 7" ]

let nodes =
  base_nodes
  @ target_path_nodes Dependability_intent.Sqlite_run_event_store
      "source.target.run-event-store"
      "modules/hermes_ops_dashboard/run_event_store.ml"
      "modules/hermes_ops_dashboard/test_run_event_store.ml"
  @ target_path_nodes Dependability_intent.Sqlite_sa_plan_store
      "source.target.sa-plan-store" "modules/sa_plan/sa_plan_store.ml"
      "modules/sa_plan/test_sa_plan_store.ml"
  @ target_path_nodes Dependability_intent.Sqlite_ops_completion_history
      "source.target.ops-completion-history"
      "modules/hermes_ops/ops_completion_history.ml"
      "modules/hermes_ops/test_ops_completion_history.ml"
  @ target_path_nodes Dependability_intent.Sqlite_evidence_store
      "source.target.evidence-store"
      "modules/hermes_harness/evidence_store.ml"
      "modules/hermes_harness/test_evidence_store.ml"

let find id = List.find_opt (fun (node : node) -> node.id = id) nodes

let duplicate_strings values =
  let rec loop found = function
    | left :: (right :: _ as rest) when left = right -> loop (left :: found) rest
    | _ :: rest -> loop found rest
    | [] -> List.sort_uniq String.compare found
  in
  loop [] (List.sort String.compare values)

let nonempty values =
  values <> [] && List.for_all (fun value -> String.trim value <> "") values

let canonical_digest value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let validate () =
  let ids = List.map (fun (node : node) -> node.id) nodes in
  let hazard_ids = List.map (fun (hazard : hazard) -> hazard.hazard_id) hazards in
  let metric_ids = List.map (fun (metric : metric) -> metric.metric_id) metrics in
  let source_ids = List.map (fun (source : source) -> source.source_id) sources in
  let errors =
    duplicate_strings ids |> List.map (fun id -> "duplicate ontology id: " ^ id)
  in
  let errors =
    [ ("hazard", hazard_ids); ("metric", metric_ids); ("source", source_ids) ]
    |> List.fold_left
         (fun errors (label, values) ->
           duplicate_strings values
           |> List.fold_left
                (fun errors id -> ("duplicate " ^ label ^ " id: " ^ id) :: errors)
                errors)
         errors
  in
  let errors =
    List.fold_left
      (fun errors (node : node) ->
        let required_lists =
          [ ("control actions", node.control_actions); ("feedback", node.feedback);
            ("losses", node.losses); ("hazards", node.hazards);
            ("unsafe control actions", node.unsafe_control_actions);
            ("FMEA", node.fmea); ("safety constraints", node.safety_constraints);
            ("sources", node.sources); ("implementation paths", node.implementation_paths);
            ("test paths", node.test_paths); ("metrics", node.metric_ids) ]
        in
        let errors =
          if String.trim node.id = "" || String.trim node.coordinate = ""
             || String.trim node.rca_origin = "" || String.trim node.controller = ""
             || String.trim node.controlled_process = "" || String.trim node.provenance = ""
             || String.trim node.owner = "" || String.trim node.evidence_posture = ""
          then ("incomplete ontology identity: " ^ node.id) :: errors else errors
        in
        let errors =
          List.fold_left
            (fun errors (label, values) ->
              if nonempty values then errors else ("missing " ^ label ^ ": " ^ node.id) :: errors)
            errors required_lists
        in
        let errors =
          List.fold_left
            (fun errors hazard ->
              if List.mem hazard hazard_ids then errors
              else ("unresolved hazard: " ^ node.id ^ " -> " ^ hazard) :: errors)
            errors node.hazards
        in
        let errors =
          List.fold_left
            (fun errors metric ->
              if List.mem metric metric_ids then errors
              else ("unresolved metric: " ^ node.id ^ " -> " ^ metric) :: errors)
            errors node.metric_ids
        in
        let errors =
          List.fold_left
            (fun errors source ->
              if List.mem source source_ids then errors
              else ("unresolved source: " ^ node.id ^ " -> " ^ source) :: errors)
            errors node.sources
        in
        let errors =
          match node.applicability with
          | Framework_wide -> errors
          | Targets targets
            when targets <> []
                 && List.length targets = List.length (List.sort_uniq compare targets)
                 && List.for_all (fun target -> List.mem target all_targets) targets -> errors
          | Targets _ -> ("invalid applicability: " ^ node.id) :: errors
        in
        let errors =
          match node.component_kind, node.applicability with
          | Target_component target, Targets [ applicable ] when target = applicable -> errors
          | Target_component _, _ -> ("target component applicability mismatch: " ^ node.id) :: errors
          | Framework_component, Framework_wide -> errors
          | Framework_component, Targets _ -> ("framework applicability mismatch: " ^ node.id) :: errors
          | Evidence_path_component target, Targets [ applicable ]
            when target = applicable -> errors
          | Closure_path_component target, Targets [ applicable ]
            when target = applicable -> errors
          | (Evidence_path_component _ | Closure_path_component _), _ ->
              ("path component applicability mismatch: " ^ node.id) :: errors
          | ( Statement_lifecycle_component | Database_close_component
            | Actor_cleanup_component | Process_reliability_component
            | Crash_window_component | Lifecycle_formal_component
            | Fpp_mbse_component | Surface_gateway_component ), _ -> errors
        in
        let expected_authority_digest =
          currentness_authority_digest ~id:node.id ~sources:node.sources
            ~implementation_paths:node.implementation_paths
            ~test_paths:node.test_paths ~evolution_version:node.evolution_version
            ~origin:provenance
        in
        let errors =
          match node.evidence_currentness with
          | Current_evidence { authority_digest; receipt_digest } ->
              if authority_digest = expected_authority_digest
                 && canonical_digest authority_digest
                 && canonical_digest receipt_digest
                 && node.provenance
                    = String.concat ":"
                        [ "currentness"; "current"; authority_digest;
                          receipt_digest ]
              then errors else ("invalid current evidence binding: " ^ node.id) :: errors
          | Stale_evidence { authority_digest; observed_digest } ->
              if authority_digest = expected_authority_digest
                 && canonical_digest authority_digest
                 && canonical_digest observed_digest
                 && authority_digest <> observed_digest
                 && node.provenance
                    = String.concat ":"
                        [ "currentness"; "stale"; authority_digest;
                          observed_digest ]
              then errors else ("invalid stale evidence binding: " ^ node.id) :: errors
          | Currentness_unavailable { authority_digest; diagnostic_digest } ->
              let expected_diagnostic =
                sha256
                  ("pure-core-currentness-receipt-unavailable:"
                   ^ authority_digest)
              in
              if authority_digest = expected_authority_digest
                 && diagnostic_digest = expected_diagnostic
                 && canonical_digest authority_digest
                 && canonical_digest diagnostic_digest
                 && node.provenance
                    = String.concat ":"
                        [ "currentness"; "unavailable"; authority_digest;
                          diagnostic_digest ]
              then errors
              else ("invalid unavailable currentness binding: " ^ node.id) :: errors
        in
        let errors =
          match node.evidence_status, node.evidence_currentness with
          | Differentially_verified, Current_evidence _ when node.test_paths <> [] ->
              errors
          | Differentially_verified, _ ->
              ("false differential evidence status: " ^ node.id) :: errors
          | ( Declared_only | Implemented_structural | Tested_structural
            | Execution_unavailable ), _ -> errors
        in
        if node.evolution_version > 0 then errors
        else ("non-positive evolution version: " ^ node.id) :: errors)
      errors nodes
  in
  let errors =
    List.fold_left
      (fun errors (node : node) ->
        match node.parent_id with
        | None -> errors
        | Some parent when List.mem parent ids -> errors
        | Some parent -> ("missing ontology parent: " ^ node.id ^ " -> " ^ parent) :: errors)
      errors nodes
  in
  let rec parent_cycle path id =
    if List.mem id path then true
    else
      match find id with
      | None | Some { parent_id = None; _ } -> false
      | Some { parent_id = Some parent; _ } -> parent_cycle (id :: path) parent
  in
  let errors =
    List.fold_left
      (fun errors (node : node) ->
        if parent_cycle [] node.id then ("ontology parent cycle: " ^ node.id) :: errors
        else errors)
      errors nodes
  in
  let applies target (node : node) =
    match node.applicability with
    | Framework_wide -> true
    | Targets targets -> List.mem target targets
  in
  let rec descends_from ancestor_id (node : node) =
    match node.parent_id with
    | None -> false
    | Some parent when parent = ancestor_id -> true
    | Some parent ->
        begin match find parent with
        | None -> false
        | Some parent_node -> descends_from ancestor_id parent_node
        end
  in
  let errors =
    List.fold_left
      (fun errors target ->
        let target_nodes =
          List.filter
            (fun (node : node) ->
              match node.component_kind with Target_component actual -> actual = target | _ -> false)
            nodes
        in
        let roles =
          [ (Admission_path, "admission"); (Evidence_path, "evidence");
            (Closure_path, "closure") ]
        in
        let errors =
          if List.length target_nodes = 1 then errors
          else ("target ontology node is not singular: " ^ Dependability_intent.target_id target) :: errors
        in
        let errors =
          List.fold_left
            (fun errors (role, label) ->
              if
                List.exists
                  (fun (node : node) ->
                    applies target node && node.path_role = role)
                  nodes
              then errors
              else
                (Printf.sprintf "target has no %s path: %s" label
                   (Dependability_intent.target_id target)) :: errors)
            errors roles
        in
        match target_nodes with
        | [ target_node ] ->
            let reachable =
              List.exists
                (fun (evidence : node) ->
                  applies target evidence && evidence.path_role = Evidence_path
                  && descends_from target_node.id evidence
                  && List.exists
                       (fun (closure : node) ->
                         applies target closure
                         && closure.path_role = Closure_path
                         && descends_from evidence.id closure)
                       nodes)
                nodes
            in
            if reachable then errors
            else
              ("target has no reachable admission-evidence-closure path: "
               ^ Dependability_intent.target_id target) :: errors
        | _ -> errors)
      errors all_targets
  in
  List.sort_uniq String.compare errors
