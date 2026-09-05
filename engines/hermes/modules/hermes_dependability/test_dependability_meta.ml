open Dependability_algebra

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin incr failed; Printf.printf "FAILED: %s\n" name end

let all_availability = [ Available; Unavailable_observed; Blocked; Indeterminate ]
let all_credit = [ No_credit; Discovery_credit; Structural_credit; Differential_credit ]
let all_verdict =
  [ Satisfied; Refuted; Evidence_unavailable; Not_executed;
    Verdict_indeterminate ]

let digest character = String.make 64 character

let canonical_sha256 value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let parse_currentness_binding value =
  match String.split_on_char '@' value with
  | [ dependency_id; authority_digest ]
    when String.trim dependency_id <> ""
         && canonical_sha256 authority_digest ->
      Some (dependency_id, authority_digest)
  | _ -> None

let get = function Ok value -> value | Error message -> failwith message

let coordinate phase : Ops_capability.coordinate =
  { level = Ops_capability.L2; phase }

let activity_path =
  [ coordinate Ops_capability.Observe; coordinate Ops_capability.Orient;
    coordinate Ops_capability.Decide; coordinate Ops_capability.Act;
    coordinate Ops_capability.Observe ]

let graph_intent =
  let schedule =
    get
      (Dependability_intent.make_reliability_schedule
         ~sequential_oracle_attempts:32 ~bounded_parallel_attempts:268
         ~lane_count:5)
  in
  let policy =
    get
      (Dependability_intent.make_policy ~confidence_ppm:950_000
         ~maximum_incident_rate_ppm:10_000 ~attempts:300
         ~per_child_timeout_ns:30_000_000_000L ~maximum_failures:0
         ~minimum_overlap_gc_cycles:1 ~reliability_schedule:schedule
         ~require_formal:true ~require_crash_window:true ~require_full_gate:true
         ())
  in
  let criterion =
    get
      (Dependability_intent.make_criterion ~id:"exit"
         ~description:"zero exit" ~predicate:Dependability_intent.Exit_zero)
  in
  let source : Dependability_intent.source_authority =
    { source_revision = "0123456789abcdef"; source_clean = true;
      configuration_digest = digest 'c'; authority_digest = digest 'a';
      build_digest = digest 'b'; provenance_digest = digest 'd' }
  in
  get
    (Dependability_intent.make ~request_id:"meta-graph-request"
       ~activity_id:"dependability.sqlite.full" ~run_id:"meta-graph-run"
       ~operation:Dependability_intent.Verify_full ~activity_path
       ~target:Dependability_intent.Sqlite_run_event_store
       ~plane:Dependability_intent.Both_planes ~policy ~criteria:[ criterion ]
       ~source)

let admitted_graph =
  let inputs =
    Dependability_graph.required_inputs graph_intent
    |> List.map
         (fun (requirement : Dependability_graph.input_requirement) ->
           { Dependability_graph.key = requirement.key; kind = requirement.kind;
             state =
               Dependability_graph.Present
                 (match requirement.expected_digest with
                  | Some value -> value
                  | None -> digest 'a') })
  in
  match Dependability_graph.build ~inputs graph_intent with
  | Ok graph -> graph
  | Error errors -> failwith (String.concat "; " errors)

let authority_topology : projected_topology =
  { topology_components =
      List.map
        (fun (component : Dependability_topology.component) ->
          component.stable_id)
        Dependability_topology.authority.components;
    topology_edges =
      List.map
        (fun (edge : Dependability_topology.edge) ->
          (edge.from_component, edge.from_port, edge.to_component, edge.to_port))
        Dependability_topology.authority.edges }

let projection_topology : projected_topology =
  let connections =
    Dependability_topology.model.topologies
    |> List.concat_map (fun (topology : Fpp_model.topology) -> topology.graphs)
    |> List.concat_map (function
         | Fpp_model.Direct { connections; _ } -> connections
         | Fpp_model.Pattern _ -> [])
  in
  { topology_components =
      List.map
        (fun (instance : Fpp_model.instance) -> instance.inst_name)
        Dependability_topology.model.instances;
    topology_edges =
      List.map
        (fun (connection : Fpp_model.connection) ->
          ( connection.from_.ep_instance, connection.from_.ep_port,
            connection.to_.ep_instance, connection.to_.ep_port ))
        connections }

let graph_node id : Dependability_graph.node =
  { id; kind = Dependability_graph.Formal_model; dependencies = []; inputs = [];
    criticality = 50; cache_policy = Dependability_graph.Reusable }

let () =
  check "A1 availability meet is associative, commutative, and idempotent"
    (List.for_all
       (fun a ->
         meet_availability a a = a
         && List.for_all
              (fun b ->
                meet_availability a b = meet_availability b a
                && List.for_all
                     (fun c ->
                       meet_availability (meet_availability a b) c
                       = meet_availability a (meet_availability b c))
                     all_availability)
              all_availability)
       all_availability);
  check "A2 unavailable, blocked, and indeterminate cannot project to Available"
    (List.for_all
       (fun value -> project_availability value <> Available)
       [ Unavailable_observed; Blocked; Indeterminate ]);
  check "A3 dependency taint is a monotone idempotent closure"
    (let edges = [ ("a", "b"); ("b", "c"); ("x", "y") ] in
     let once = taint_closure ~edges [ "a" ] in
     once = [ "a"; "b"; "c" ]
     && taint_closure ~edges once = once
     && List.for_all (fun id -> List.mem id (taint_closure ~edges [ "a"; "x" ])) once);
  check "A4 credit, verdict, and taint carriers obey exhaustive semilattice laws"
    (List.for_all
       (fun a ->
         join_credit a a = a
         && List.for_all
              (fun b ->
                join_credit a b = join_credit b a
                && List.for_all
                     (fun c ->
                       join_credit (join_credit a b) c
                       = join_credit a (join_credit b c))
                     all_credit)
              all_credit)
       all_credit
     && List.for_all
          (fun a ->
            meet_verdict a a = a
            && List.for_all
                 (fun b ->
                   meet_verdict a b = meet_verdict b a
                   && List.for_all
                        (fun c ->
                          meet_verdict (meet_verdict a b) c
                          = meet_verdict a (meet_verdict b c))
                        all_verdict)
                 all_verdict)
          all_verdict
     && combine_taint Clean Clean = Clean
     && combine_taint Clean Tainted = Tainted
     && combine_taint Tainted Clean = Tainted
     && combine_taint Tainted Tainted = Tainted
     && join_credit No_credit Differential_credit = Differential_credit
     && join_credit Discovery_credit Structural_credit = Structural_credit
     && meet_verdict Satisfied Not_executed = Not_executed
     && meet_verdict Evidence_unavailable Refuted = Refuted);
  check "A5 criticality, refinement, and evolution are bounded and non-vacuous"
    (match make_criticality 20, make_criticality 90,
           make_coordinate ~level:"L2" ~path:[ "sqlite" ],
           make_coordinate ~level:"L2" ~path:[ "sqlite"; "close" ] with
     | Ok low, Ok high, Ok parent, Ok child ->
         criticality_value (max_criticality low high) = 90
         && refines ~parent ~child && refines ~parent ~child:parent
         && not (refines ~parent:child ~child:parent)
         && advance_lifecycle Declared Admitted = Ok Admitted
         && advance_lifecycle Current Stale = Ok Stale
         && advance_lifecycle Stale Admitted = Ok Admitted
         && (match advance_lifecycle Declared Current with Error _ -> true | Ok _ -> false)
         && (match make_criticality 101 with Error _ -> true | Ok _ -> false)
     | _ -> false);
  check "A6 graph composition has identity and associative disjoint union"
    (let a = [ graph_node "a" ] and b = [ graph_node "b" ]
     and c = [ graph_node "c" ] in
     compose_graph [] a = Ok a
     && compose_graph a [] = Ok a
     && (match compose_graph a b, compose_graph b c with
         | Ok ab, Ok bc ->
             compose_graph ab c =
             (match compose_graph a bc with Ok abc -> Ok abc | Error e -> Error e)
         | _ -> false)
     && (match compose_graph a a with Error _ -> true | Ok _ -> false));
  check "A7 sequential and parallel receipts normalize to the same attempt map"
    (let make id verdict value =
       match make_observation ~attempt_id:id ~verdict
               ~observation_digest:(digest value) with
       | Ok observation -> observation
       | Error message -> failwith message
     in
     let expected = [ 0; 1; 2 ] in
     let sequential =
       [ make 0 Satisfied 'a'; make 1 Evidence_unavailable 'b';
         make 2 Refuted 'c' ]
     in
     observations_equivalent ~expected_attempt_ids:expected ~sequential
       ~parallel:(List.rev sequential)
     && not
          (observations_equivalent ~expected_attempt_ids:expected ~sequential
             ~parallel:[ make 0 Satisfied 'a'; make 1 Satisfied 'b';
                         make 2 Refuted 'c' ])
     && (match normalize_observations ~expected_attempt_ids:expected
                   (List.hd sequential :: sequential) with
         | Error _ -> true | Ok _ -> false)
     && (match make_observation ~attempt_id:3 ~verdict:Satisfied
                   ~observation_digest:(String.make 64 'A') with
         | Error _ -> true | Ok _ -> false));
  check "A8 Fast OODA closes only with a causal Observe-Orient-Decide-Act-Observe trace"
    (closes_ooda [ Observe "before"; Orient "before"; Decide "plan";
                   Act "receipt"; Observe "receipt" ]
     && not (closes_ooda [ Observe "before"; Orient "before"; Decide "plan";
                           Act "receipt"; Observe "other" ]));
  check "MUT.EVOLUTION.SKIP and MUT.GRAPH.COLLIDE are killed"
    ((match advance_lifecycle Declared Current with Error _ -> true | Ok _ -> false)
     && (match compose_graph [ graph_node "same" ] [ graph_node "same" ] with
         | Error _ -> true | Ok _ -> false));
  check "MUT.RECEIPT.DROP_ATTEMPT is killed by total normalization"
    (let observation =
       match make_observation ~attempt_id:0 ~verdict:Satisfied
               ~observation_digest:(digest 'a') with
       | Ok value -> value
       | Error message -> failwith message
     in
     match normalize_observations ~expected_attempt_ids:[ 0; 1 ] [ observation ] with
     | Error _ -> true
     | Ok _ -> false);
  check "MUT.VERDICT.PERMUTE is killed by fail-closed verdict order"
    (meet_verdict Satisfied Not_executed = Not_executed
     && meet_verdict Not_executed Evidence_unavailable = Evidence_unavailable
     && meet_verdict Evidence_unavailable Verdict_indeterminate
        = Verdict_indeterminate
     && meet_verdict Verdict_indeterminate Refuted = Refuted);
  check "O1 dependability ontology is total and acyclic"
    (Dependability_ontology.validate () = []
     && Dependability_ontology.nodes <> []);
  check "O2 every ontology node has coordinate, RCA, hazard, source, and evidence posture"
    (List.for_all
       (fun (node : Dependability_ontology.node) ->
         node.id <> "" && node.coordinate <> "" && node.rca_origin <> ""
         && node.hazards <> [] && node.sources <> []
         && node.evidence_posture <> ""
         && (match node.applicability with
             | Dependability_ontology.Framework_wide -> true
             | Dependability_ontology.Targets targets -> targets <> []))
       Dependability_ontology.nodes);
  check "O3 hazard, metric, and source links resolve and every target has admission/evidence/closure"
    (let hazard_ids =
       List.map (fun (hazard : Dependability_ontology.hazard) -> hazard.hazard_id)
         Dependability_ontology.hazards
     and metric_ids =
       List.map (fun (metric : Dependability_ontology.metric) -> metric.metric_id)
         Dependability_ontology.metrics
     and source_ids =
       List.map (fun (source : Dependability_ontology.source) -> source.source_id)
         Dependability_ontology.sources
     in
     let applies target (node : Dependability_ontology.node) =
       match node.applicability with
       | Dependability_ontology.Framework_wide -> true
       | Dependability_ontology.Targets targets -> List.mem target targets
     in
     List.for_all
       (fun (node : Dependability_ontology.node) ->
         List.for_all (fun id -> List.mem id hazard_ids) node.hazards
         && List.for_all (fun id -> List.mem id metric_ids) node.metric_ids
         && List.for_all (fun id -> List.mem id source_ids) node.sources)
       Dependability_ontology.nodes
     &&
     let rec descends_from ancestor_id (node : Dependability_ontology.node) =
       match node.parent_id with
       | None -> false
       | Some parent when parent = ancestor_id -> true
       | Some parent ->
           begin match Dependability_ontology.find parent with
           | None -> false
           | Some parent_node -> descends_from ancestor_id parent_node
           end
     in
     List.for_all
       (fun target ->
         let target_node =
           List.find_opt
             (fun (node : Dependability_ontology.node) ->
               match node.component_kind with
               | Dependability_ontology.Target_component actual -> actual = target
               | _ -> false)
             Dependability_ontology.nodes
         in
         match target_node with
         | None -> false
         | Some target_node ->
             List.exists
               (fun (evidence : Dependability_ontology.node) ->
                 applies target evidence
                 && evidence.path_role = Dependability_ontology.Evidence_path
                 && descends_from target_node.id evidence
                 && List.exists
                      (fun (closure : Dependability_ontology.node) ->
                        applies target closure
                        && closure.path_role = Dependability_ontology.Closure_path
                        && descends_from evidence.id closure)
                      Dependability_ontology.nodes)
               Dependability_ontology.nodes)
       Dependability_intent.all_targets);
  check "O4 ontology currentness is typed by canonical authority and diagnostic digests"
    (List.for_all
       (fun (node : Dependability_ontology.node) ->
         match String.split_on_char ':' node.provenance with
         | [ "currentness"; "unavailable"; authority_digest;
             diagnostic_digest ] ->
             canonical_sha256 authority_digest
             && canonical_sha256 diagnostic_digest
             && (match node.evidence_currentness with
                 | Dependability_ontology.Currentness_unavailable
                     { authority_digest = typed_authority;
                       diagnostic_digest = typed_diagnostic } ->
                     typed_authority = authority_digest
                     && typed_diagnostic = diagnostic_digest
                 | Dependability_ontology.Current_evidence _
                 | Dependability_ontology.Stale_evidence _ -> false)
         | _ -> false)
       Dependability_ontology.nodes);
  check "T1 atlas has exactly one row per atomic capability-target-surface mapping"
    (Dependability_atlas.validate () = []
     && List.length Dependability_atlas.rows
        = List.length (List.sort_uniq compare
            (List.map (fun (row : Dependability_atlas.row) -> row.row_id)
               Dependability_atlas.rows)));
  check "T2 SQLite lifecycle, close, stress, crash, formal, FPP, and surfaces are distinct rows"
    (List.for_all
       (fun id -> Dependability_atlas.find id <> None)
       [ "sqlite.statement-lifetime"; "sqlite.database-close";
         "sqlite.actor-cleanup"; "sqlite.process-reliability";
         "sqlite.kernel-crash-window"; "sqlite.lifecycle-formal";
         "sqlite.fpp-mbse"; "sqlite.four-surfaces" ]);
  check "T3 atlas mappings are applicable, availability-explicit, and not blanket-expanded"
    (let surfaces =
       [ Dependability_atlas.Ocaml_api; Dependability_atlas.Cli;
         Dependability_atlas.Mcp; Dependability_atlas.Zenoh ]
     in
     let targets_of (node : Dependability_ontology.node) =
       match node.applicability with
       | Dependability_ontology.Framework_wide -> Dependability_intent.all_targets
       | Dependability_ontology.Targets targets -> targets
     in
     List.for_all
       (fun (row : Dependability_atlas.row) ->
         row.applicability = Dependability_atlas.Applicable
         && List.mem row.target Dependability_intent.all_targets
         && (match row.intent with
             | None -> true
             | Some operation ->
                 List.mem operation
                   (Dependability_intent.operations_for_target row.target)))
       Dependability_atlas.rows
     && List.for_all
          (fun (node : Dependability_ontology.node) ->
            match node.scale with
            | Dependability_ontology.Framework | Dependability_ontology.Target -> true
            | Dependability_ontology.Capability ->
                List.for_all
                  (fun target ->
                    List.for_all
                      (fun surface ->
                        Dependability_atlas.find_mapping
                          ~capability_id:node.id ~target ~surface
                        <> None)
                      surfaces)
                  (targets_of node))
          Dependability_ontology.nodes
     && List.exists
          (fun (row : Dependability_atlas.row) ->
            row.surface = Dependability_atlas.Mcp
            && row.availability = Dependability_atlas.Unavailable_observed_status)
          Dependability_atlas.rows
     && List.exists
          (fun (row : Dependability_atlas.row) ->
            row.surface = Dependability_atlas.Ocaml_api
            && row.availability = Dependability_atlas.Available_structural)
          Dependability_atlas.rows
     && List.exists
          (fun (row : Dependability_atlas.row) ->
            row.target = Dependability_intent.Sqlite_sa_plan_store)
          Dependability_atlas.rows
     && List.exists
          (fun (row : Dependability_atlas.row) ->
            row.target = Dependability_intent.Sqlite_run_event_store)
          Dependability_atlas.rows);
  check "T4 atlas meta view and digest are deterministic and summary-derived"
    (let first = Dependability_atlas.meta_view () in
     first = Dependability_atlas.meta_view ()
     && String.length Dependability_atlas.digest = 64
     && Dependability_atlas.summary_total = List.length Dependability_atlas.rows);
  check "T5 every atlas currentness dependency resolves to one digest-bound control"
    (let expected_ids =
       [ "current-Run_swarm_bridge"; "current-four-surface-adapters";
         "exact-authority-digest"; "exact-build-digest";
         "exact-configuration-digest"; "exact-source-digest";
         "live-z3-identity"; "policy-digest";
         "same-run-journal-cursors" ]
     in
     let encoded =
       List.concat_map
         (fun (row : Dependability_atlas.row) -> row.currentness_dependencies)
         Dependability_atlas.rows
     in
     let parsed = List.filter_map parse_currentness_binding encoded in
     List.length parsed = List.length encoded
     && (List.map fst parsed |> List.sort_uniq String.compare)
        = List.sort String.compare expected_ids
     && List.for_all
          (fun dependency_id ->
            match
              parsed
              |> List.filter_map (fun (actual_id, authority_digest) ->
                   if actual_id = dependency_id then Some authority_digest else None)
              |> List.sort_uniq String.compare
            with
            | [ authority_digest ] -> canonical_sha256 authority_digest
            | _ -> false)
          expected_ids
     && (List.map snd parsed |> List.sort_uniq String.compare |> List.length)
        = List.length expected_ids);
  check "T6 surface metadata credits focused codecs but keeps live execution unavailable"
    (let surface_node = Dependability_ontology.find "sqlite.four-surfaces" in
     let surface_rows =
       List.filter
         (fun (row : Dependability_atlas.row) ->
           row.capability_id = "sqlite.four-surfaces")
         Dependability_atlas.rows
     in
     let expected_implementation_paths =
       [ "modules/hermes_dependability/dependability_intent.ml";
         "modules/hermes_dependability/dependability_intent.mli";
         "modules/hermes_dependability/dependability_surface.ml";
         "modules/hermes_dependability/dependability_surface.mli" ]
     in
     match surface_node with
     | None -> false
     | Some node ->
         node.evidence_status = Dependability_ontology.Execution_unavailable
         && List.sort String.compare node.implementation_paths
            = List.sort String.compare expected_implementation_paths
         && node.test_paths
            = [ "modules/hermes_dependability/test_dependability_surface.ml" ]
         && List.mem "source.surface" node.sources
         && node.evidence_posture =
              "canonical v1 four-surface codecs, normalized receipts, recording dispatcher, and read-only status projection focused-tested; live CLI, MCP server, Zenoh network, and Run_swarm_bridge execution unavailable until Task 7"
         && surface_rows <> []
         && List.for_all
              (fun (row : Dependability_atlas.row) ->
                row.availability = Dependability_atlas.Unavailable_observed_status
                && row.lifecycle = Dependability_atlas.Unavailable_observed
                && row.source_credit = No_credit
                && row.projected_credit = No_credit
                && List.mem "test_dependability_surface" row.native_tests
                && List.mem
                     "canonical four-surface codecs are focused-tested; live CLI, MCP server, Zenoh network, and Run_swarm_bridge execution remain unavailable until Task 7"
                     row.residuals)
              surface_rows);
  check "H1 ontology-to-atlas projection is a coordinate-preserving homomorphism"
    (atlas_homomorphism ~ontology:Dependability_ontology.nodes
       ~atlas:Dependability_atlas.rows);
  check "H2 no atlas or surface projection can promote evidence credit"
    (projection_preserves_credit Dependability_atlas.rows
     && List.exists
          (fun (row : Dependability_atlas.row) -> row.source_credit <> No_credit)
          Dependability_atlas.rows);
  check "MUT.CREDIT.PROMOTE is killed on a non-No_credit row"
    (match
       List.find_opt
         (fun (row : Dependability_atlas.row) -> row.source_credit = Structural_credit)
         Dependability_atlas.rows
     with
     | None -> false
     | Some row ->
         not
           (projection_preserves_credit
              ({ row with projected_credit = Differential_credit }
               :: List.filter
                    (fun (candidate : Dependability_atlas.row) ->
                      candidate.row_id <> row.row_id)
                    Dependability_atlas.rows)));
  check "H3 atlas rollup/drill-down round-trips and graph/FPP topology agrees"
    (let graph = admitted_graph in
     let dependency_mutant =
       List.map
         (fun (node : Dependability_graph.node) ->
           if node.id = "lifecycle-smt" then
             { node with dependencies = [ "identity-admission" ] }
           else node)
         graph
     in
     rollup_roundtrip Dependability_atlas.rows
     && Dependability_topology.validate () = []
     && graph_fpp_topology_agreement ~graph ~atlas:Dependability_atlas.rows
          ~authority:authority_topology ~projection:projection_topology
     && not
          (graph_fpp_topology_agreement ~graph:dependency_mutant
             ~atlas:Dependability_atlas.rows ~authority:authority_topology
             ~projection:projection_topology)
     && not
          (graph_fpp_topology_agreement ~graph:(List.tl graph)
             ~atlas:Dependability_atlas.rows ~authority:authority_topology
             ~projection:projection_topology));
  check "MUT.TOPOLOGY.DROP_GRAPH_UNIT is killed"
    (not
       (graph_fpp_topology_agreement ~graph:(List.tl admitted_graph)
          ~atlas:Dependability_atlas.rows ~authority:authority_topology
          ~projection:projection_topology));
  check "MUT.FPP.DROP_EDGE is killed by exact authority/projection topology"
    (let projection =
       { projection_topology with
         topology_edges = List.tl projection_topology.topology_edges }
     in
     not
       (graph_fpp_topology_agreement ~graph:admitted_graph
          ~atlas:Dependability_atlas.rows ~authority:authority_topology
          ~projection));

  Printf.printf "dependability_meta: %d passed, %d failed\n" !passed !failed;
  let self = Suite_telemetry.observe ~suite:"test_dependability_meta" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_dependability_core; Stanza.hermes_dependability_sqlite; Stanza.hermes_dependability_solver; Stanza.hermes_dependability_process; Stanza.hermes_dependability_topology ]);
  exit (Suite_telemetry.exit_code self)
