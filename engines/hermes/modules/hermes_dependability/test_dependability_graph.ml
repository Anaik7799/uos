open Dependability_intent
open Dependability_graph

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin incr failed; Printf.printf "FAILED: %s\n" name end

let source : source_authority =
  { source_revision = "0123456789abcdef"; source_clean = true;
    configuration_digest = String.make 64 'c'; authority_digest = String.make 64 'a';
    build_digest = String.make 64 'b'; provenance_digest = String.make 64 'd' }

let coordinate phase : Ops_capability.coordinate =
  { level = Ops_capability.L2; phase }

let activity_path =
  [ coordinate Ops_capability.Observe; coordinate Ops_capability.Orient;
    coordinate Ops_capability.Decide; coordinate Ops_capability.Act;
    coordinate Ops_capability.Observe ]

let get = function Ok value -> value | Error message -> failwith message

let schedule =
  get
    (make_reliability_schedule ~sequential_oracle_attempts:32
       ~bounded_parallel_attempts:268 ~lane_count:5)

let intent =
  let policy =
    get
      (make_policy ~confidence_ppm:950_000 ~maximum_incident_rate_ppm:10_000
         ~attempts:300 ~per_child_timeout_ns:30_000_000_000L
         ~maximum_failures:0 ~minimum_overlap_gc_cycles:1
         ~reliability_schedule:schedule ~require_formal:true
         ~require_crash_window:true ~require_full_gate:true ())
  in
  let criteria =
    [ get (make_criterion ~id:"exit" ~description:"zero exit" ~predicate:Exit_zero) ]
  in
  get
    (make ~request_id:"graph-request" ~activity_id:"dependability.sqlite.full"
       ~run_id:"graph-run" ~operation:Verify_full ~activity_path
       ~target:Sqlite_run_event_store ~plane:Both_planes ~policy ~criteria ~source)

let ids nodes = List.map (fun node -> node.id) nodes

let digest_char character = String.make 64 character

let materialize (requirement : input_requirement) : input_fact =
  { key = requirement.key; kind = requirement.kind;
    state =
      Present
        (match requirement.expected_digest with
         | Some digest -> digest
         | None -> digest_char 'a') }

let graph_inputs = required_inputs intent |> List.map materialize

let build_graph inputs =
  match build ~inputs intent with
  | Ok nodes -> nodes
  | Error errors -> failwith (String.concat "; " errors)

let binding character : authority_binding =
  { target_digest = digest_char character; policy_digest = digest_char 'b';
    criteria_digest = digest_char 'c'; source_digest = digest_char 'd';
    configuration_digest = digest_char 'e'; toolchain_digest = digest_char 'f';
    executable_digest = digest_char '1'; topology_digest = digest_char '2';
    receipt_digest = digest_char '3' }

let raises_invalid_argument body =
  match body () with
  | _ -> false
  | exception Invalid_argument _ -> true

let () =
  let nodes = build_graph graph_inputs in
  check "G1 SQLite graph materializes 300 globally identified attempts and five permit chains"
    (let attempts =
       List.filter_map
         (fun node ->
           match node.kind with Process_attempt attempt -> Some (node, attempt) | _ -> None)
         nodes
     in
     let permits =
       List.filter_map
         (fun node -> match node.kind with Permit_capacity lane -> Some (node, lane) | _ -> None)
         nodes
     in
     let attempt_ids = List.map (fun (_, attempt) -> attempt.attempt_id) attempts in
     let sequential =
       attempts
       |> List.filter_map (fun (node, attempt) ->
              match attempt.phase with Sequential_oracle -> Some (node, attempt) | _ -> None)
     in
     let parallel =
       attempts
       |> List.filter_map (fun (node, attempt) ->
              match attempt.phase with
              | Bounded_parallel { lane } -> Some (node, attempt, lane)
              | Sequential_oracle -> None)
     in
     let aggregate = List.find (fun node -> node.id = "process-reliability") nodes in
     List.length attempts = 300
     && List.sort_uniq Int.compare attempt_ids = List.init 300 Fun.id
     && (List.map (fun (_, attempt) -> attempt.attempt_id) sequential
         |> List.sort Int.compare) = List.init 32 Fun.id
     && (List.map (fun (_, attempt, _) -> attempt.attempt_id) parallel
         |> List.sort Int.compare) = List.init 268 (fun index -> index + 32)
     && (List.map snd permits |> List.sort Int.compare) = List.init 5 Fun.id
     && List.for_all
          (fun (node, _) ->
            List.exists
              (fun fact ->
                fact.key = "config:permit-topology"
                && fact.state = Present (permit_topology_digest schedule))
              node.inputs)
          permits
     && List.sort String.compare aggregate.dependencies
        = (attempts |> List.map (fun (node, _) -> node.id) |> List.sort String.compare));
  check "G2 graph validates and topological order covers every node once"
    (validate nodes = []
     && let ordered = topo_order nodes |> ids in
        List.length ordered = List.length nodes
        && List.sort_uniq compare ordered = List.sort_uniq compare (ids nodes));
  check "G2b source, configuration, tool, executable, interface, test, and helper inputs are total"
    (let requirements = required_inputs intent in
     let keys =
       List.map (fun (requirement : input_requirement) -> requirement.key)
         requirements
     in
     let required_files =
       [ "modules/hermes_dependability/dependability_abandonment_protocol.ml";
         "modules/hermes_dependability/dependability_abandonment_protocol.mli";
         "modules/hermes_dependability/dependability_algebra.ml";
         "modules/hermes_dependability/dependability_algebra.mli";
         "modules/hermes_dependability/dependability_approval.ml";
         "modules/hermes_dependability/dependability_approval.mli";
         "modules/hermes_dependability/dependability_approval_crypto.ml";
         "modules/hermes_dependability/dependability_approval_crypto.mli";
         "modules/hermes_dependability/dependability_atlas.ml";
         "modules/hermes_dependability/dependability_atlas.mli";
         "modules/hermes_dependability/dependability_authority_store.ml";
         "modules/hermes_dependability/dependability_authority_store.mli";
         "modules/hermes_dependability/dependability_clock.ml";
         "modules/hermes_dependability/dependability_clock.mli";
         "modules/hermes_dependability/dependability_completion_store.ml";
         "modules/hermes_dependability/dependability_completion_store.mli";
         "modules/hermes_dependability/dependability_credential.ml";
         "modules/hermes_dependability/dependability_credential.mli";
         "modules/hermes_dependability/dependability_dispatch_store.ml";
         "modules/hermes_dependability/dependability_dispatch_store.mli";
         "modules/hermes_dependability/dependability_filesystem.ml";
         "modules/hermes_dependability/dependability_filesystem.mli";
         "modules/hermes_dependability/dependability_graph.ml";
         "modules/hermes_dependability/dependability_graph.mli";
         "modules/hermes_dependability/dependability_intent.ml";
         "modules/hermes_dependability/dependability_intent.mli";
         "modules/hermes_dependability/dependability_network.ml";
         "modules/hermes_dependability/dependability_network.mli";
         "modules/hermes_dependability/dependability_ontology.ml";
         "modules/hermes_dependability/dependability_ontology.mli";
         "modules/hermes_dependability/dependability_owner_inventory.ml";
         "modules/hermes_dependability/dependability_owner_inventory.mli";
         "modules/hermes_dependability/dependability_process.ml";
         "modules/hermes_dependability/dependability_process.mli";
         "modules/hermes_dependability/dependability_process_fixture.ml";
         "modules/hermes_dependability/dependability_process_protocol.ml";
         "modules/hermes_dependability/dependability_process_protocol.mli";
         "modules/hermes_dependability/dependability_process_test_protocol.ml";
         "modules/hermes_dependability/dependability_process_test_protocol.mli";
         "modules/hermes_dependability/dependability_recovery_vault.ml";
         "modules/hermes_dependability/dependability_recovery_vault.mli";
         "modules/hermes_dependability/dependability_sqlite.ml";
         "modules/hermes_dependability/dependability_sqlite.mli";
         "modules/hermes_dependability/dependability_sqlite_location.ml";
         "modules/hermes_dependability/dependability_sqlite_location.mli";
         "modules/hermes_dependability/dependability_sqlite_test_protocol.ml";
         "modules/hermes_dependability/dependability_sqlite_test_protocol.mli";
         "modules/hermes_dependability/dependability_surface.ml";
         "modules/hermes_dependability/dependability_surface.mli";
         "modules/hermes_dependability/dune";
         "modules/hermes_dependability/sqlite_lifecycle_model.ml";
         "modules/hermes_dependability/sqlite_lifecycle_model.mli";
         "modules/hermes_dependability/sqlite_lifecycle_solver.ml";
         "modules/hermes_dependability/sqlite_lifecycle_solver.mli";
         "modules/hermes_dependability/test_dependability_abandonment_protocol.ml";
         "modules/hermes_dependability/test_dependability_approval.ml";
         "modules/hermes_dependability/test_dependability_approval_crypto.ml";
         "modules/hermes_dependability/test_dependability_authority_store.ml";
         "modules/hermes_dependability/test_dependability_clock.ml";
         "modules/hermes_dependability/test_dependability_completion_store.ml";
         "modules/hermes_dependability/test_dependability_core.ml";
         "modules/hermes_dependability/test_dependability_credential.ml";
         "modules/hermes_dependability/test_dependability_dispatch_store.ml";
         "modules/hermes_dependability/test_dependability_filesystem.ml";
         "modules/hermes_dependability/test_dependability_graph.ml";
         "modules/hermes_dependability/test_dependability_meta.ml";
         "modules/hermes_dependability/test_dependability_network.ml";
         "modules/hermes_dependability/test_dependability_owner_inventory.ml";
         "modules/hermes_dependability/test_dependability_process.ml";
         "modules/hermes_dependability/test_dependability_process_protocol.ml";
         "modules/hermes_dependability/test_dependability_recovery_vault.ml";
         "modules/hermes_dependability/test_dependability_sqlite_location.ml";
         "modules/hermes_dependability/test_dependability_surface.ml";
         "modules/hermes_dependability/test_dependability_topology.ml";
         "modules/hermes_dependability/test_sqlite_lifecycle_model.ml";
         "modules/hermes_dependability/test_sqlite_lifecycle_smt.ml";
         "modules/hermes_dependability/dependability_topology.ml";
         "modules/hermes_dependability/dependability_topology.mli";
         "modules/hermes_dependability/dependability_writer_lease.ml";
         "modules/hermes_dependability/dependability_writer_lease.mli";
         "modules/hermes_dependability/test_dependability_writer_lease.ml";
         "modules/hermes_ops_dashboard/run_root_bootstrap.ml";
         "modules/hermes_ops_dashboard/run_root_bootstrap.mli";
         "modules/hermes_ops_dashboard/test_run_root_bootstrap.ml";
         "modules/hermes_ops_dashboard/run_event_store.ml";
         "modules/hermes_ops_dashboard/run_event_store.mli";
         "modules/hermes_ops_dashboard/test_run_event_store.ml";
         "modules/hermes_ops_dashboard/dune" ]
     in
     List.length keys = List.length (List.sort_uniq String.compare keys)
     && List.for_all (fun path -> List.mem ("source:" ^ path) keys) required_files
     && List.for_all (fun key -> List.mem key keys)
          [ "config:intent"; "config:policy"; "config:criteria";
            "config:source-authority"; "config:permit-topology";
            "tool:ocaml"; "tool:z3"; "tool:sqlite3-ocaml"; "tool:swarm";
            "tool:kernel-journal"; "tool:fpp"; "tool:mbse";
            "executable:process-attempt" ]
     && (match build ~inputs:(List.tl graph_inputs) intent with Error _ -> true | Ok _ -> false)
     && (match build ~inputs:(List.hd graph_inputs :: graph_inputs) intent with
         | Error _ -> true | Ok _ -> false));
  check "G2c sequential and five-lane permit dependencies prove the bounded topology"
    (let by_id id = List.find (fun node -> node.id = id) nodes in
     let attempt_id value = Printf.sprintf "process-attempt-%03d" value in
     let sequential_ok =
       List.for_all
         (fun id ->
           let expected = if id = 0 then "native-focused" else attempt_id (id - 1) in
           (by_id (attempt_id id)).dependencies = [ expected ])
         (List.init 32 Fun.id)
     in
     let parallel_ok =
       parallel_lane_partitions schedule
       |> List.mapi (fun lane attempts ->
              let rec check_chain previous = function
                | [] -> true
                | id :: rest ->
                    (by_id (attempt_id id)).dependencies = [ previous ]
                    && check_chain (attempt_id id) rest
              in
              check_chain (Printf.sprintf "permit-lane-%d" lane) attempts)
       |> List.for_all Fun.id
     in
     sequential_ok && parallel_ok);
  let sample : node =
    { id = "sample"; kind = Formal_model; dependencies = [];
      inputs =
        [ { key = "a"; kind = Source_input; state = Present (digest_char 'a') };
          { key = "b"; kind = Tool_input; state = Present (digest_char 'b') } ];
      criticality = 90;
      cache_policy = Reusable }
  in
  let fp = fingerprint sample ~parents:[] in
  check "G3 fingerprints are deterministic and content complete"
    (fp = fingerprint sample ~parents:[]
     && fp <> fingerprint
                  { sample with
                    inputs =
                      [ { key = "a"; kind = Source_input;
                          state = Present (digest_char 'f') } ] }
                  ~parents:[]
     && fp <> fingerprint { sample with id = "renamed" } ~parents:[]
     && fp <> fingerprint sample ~parents:[ ("parent", digest_char '6') ]);
  check "G4 missing and unreadable are distinct closed states, never collapsed"
    (let with_state state =
       fingerprint
         { sample with inputs = [ { key = "missing"; kind = Source_input; state } ] }
         ~parents:[]
     in
     let missing = with_state Missing in
     let unreadable = with_state (Unreadable (digest_char '7')) in
     let present = with_state (Present (digest_char '8')) in
     missing <> unreadable && missing <> present && unreadable <> present);
  let fps = fingerprints nodes in
  let authorities = List.map (fun (id, _) -> (id, binding 'a')) fps in
  let passed_cache =
    List.map
      (fun (id, fp) ->
        (id, { fingerprint = fp; authority = binding 'a'; verdict = Passed }))
      fps
  in
  check "G5 cold frontier is total and an unchanged exact Passed cache is minimal"
    (dirty_frontier ~fingerprints:fps ~authorities ~cache:[] nodes
        = ids (topo_order nodes)
     && dirty_frontier ~fingerprints:fps ~authorities ~cache:passed_cache nodes
        = (nodes |> List.filter (fun n -> n.cache_policy = Always_run) |> ids));
  let failed_cache =
    List.map
      (fun (id, fp) ->
        let verdict =
          if String.equal id "lifecycle-model" then Failed "mutant"
          else Passed
        in
        (id, { fingerprint = fp; authority = binding 'a'; verdict }))
      fps
  in
  let dirty = dirty_frontier ~fingerprints:fps ~authorities ~cache:failed_cache nodes in
  check "G6 failure re-runs and taints every dependent but not an independent predecessor"
    (List.mem "lifecycle-model" dirty && List.mem "lifecycle-smt" dirty
     && List.mem "native-focused" dirty && List.mem "full-gate" dirty
     && not (List.mem "identity-admission" dirty));
  check "G7 unavailable, skipped, corrupt, or fingerprint-drifted cache never becomes a hit"
    (List.for_all
       (fun verdict ->
         let cache =
           List.map
             (fun (id, fp) ->
               (id, { fingerprint = fp; authority = binding 'a';
                      verdict = if id = "lifecycle-model" then verdict else Passed }))
             fps
         in
         List.mem "lifecycle-model"
           (dirty_frontier ~fingerprints:fps ~authorities ~cache nodes))
       [ Unavailable "z3"; Skipped; Corrupt "bad-json" ]
     && let cache =
          List.map
            (fun (id, fp) ->
              (id, { fingerprint = if id = "lifecycle-model" then fp ^ "x" else fp;
                     authority = binding 'a'; verdict = Passed }))
            fps
        in
        List.mem "lifecycle-model"
          (dirty_frontier ~fingerprints:fps ~authorities ~cache nodes));
  check "G8 duplicate, unknown, self, and cyclic dependencies fail closed"
    (List.for_all
       (fun mutant -> validate mutant <> [])
       [ sample :: sample :: [];
         [ { sample with dependencies = [ "unknown" ] } ];
         [ { sample with dependencies = [ "sample" ] } ];
         [ { sample with id = "x"; dependencies = [ "y" ] };
           { sample with id = "y"; dependencies = [ "x" ] } ] ]);
  check "G9 duplicate materialized identities and malformed content digests fail closed"
    (validate
       [ { sample with inputs = List.hd sample.inputs :: sample.inputs } ] <> []
     && validate
          [ { sample with
              inputs =
                [ { key = "bad"; kind = Source_input; state = Present "not-sha256" } ] } ]
        <> []
     && validate
          [ { sample with
              inputs =
                [ { key = "uppercase"; kind = Source_input;
                    state = Present (String.make 64 'A') } ] } ]
        <> []);
  check "G10 duplicate or unknown fingerprint/cache frontier identities are rejected"
    (let one_id, one_fp = List.hd fps in
     let one_cache =
       { fingerprint = one_fp; authority = binding 'a'; verdict = Passed }
     in
     raises_invalid_argument (fun () ->
         dirty_frontier ~fingerprints:((one_id, one_fp) :: fps) ~authorities
           ~cache:passed_cache nodes)
     && raises_invalid_argument (fun () ->
            dirty_frontier ~fingerprints:fps ~authorities
              ~cache:(("unknown-frontier", one_cache) :: passed_cache) nodes));
  check "G11 a bare Passed bit cannot reuse work under any authority drift"
    (let authority_mutants =
       [ { (binding 'a') with target_digest = digest_char '1' };
         { (binding 'a') with policy_digest = digest_char '2' };
         { (binding 'a') with criteria_digest = digest_char '3' };
         { (binding 'a') with source_digest = digest_char '4' };
         { (binding 'a') with configuration_digest = digest_char '5' };
         { (binding 'a') with toolchain_digest = digest_char '6' };
         { (binding 'a') with executable_digest = digest_char '7' };
         { (binding 'a') with topology_digest = digest_char '8' };
         { (binding 'a') with receipt_digest = digest_char '9' } ]
     in
     List.for_all
       (fun mutant ->
         let cache =
           List.map
             (fun (id, fp) ->
               (id, { fingerprint = fp;
                      authority = if id = "lifecycle-model" then mutant else binding 'a';
                      verdict = Passed }))
             fps
         in
         List.mem "lifecycle-model"
           (dirty_frontier ~fingerprints:fps ~authorities ~cache nodes))
       authority_mutants);
  check "G12 permit topology validation rejects extra capacity, foreign lanes, and rewired permits"
    (let permit_zero =
       List.find
         (fun node -> match node.kind with Permit_capacity 0 -> true | _ -> false)
         nodes
     in
     let extra_permit =
       { permit_zero with id = "permit-lane-extra"; kind = Permit_capacity 0 }
     in
     let foreign_lane =
       List.map
         (fun node ->
           match node.kind with
           | Process_attempt { attempt_id = 32; _ } ->
               { node with
                 kind = Process_attempt
                          { attempt_id = 32;
                            phase = Bounded_parallel { lane = 5 } } }
           | _ -> node)
         nodes
     in
     let rewired_permit =
       List.map
         (fun node ->
           match node.kind with
           | Permit_capacity 0 -> { node with dependencies = [ "lifecycle-model" ] }
           | _ -> node)
         nodes
     in
     validate (extra_permit :: nodes) <> []
     && validate foreign_lane <> []
     && validate rewired_permit <> []);
  check "G13 surface and event-store reads are routed into every consuming fingerprint"
    (let find_node id = List.find (fun (node : node) -> node.id = id) nodes in
     let has_source path (node : node) =
       List.exists
         (fun (input : input_fact) -> input.key = "source:" ^ path)
         node.inputs
     in
     let binds_all paths node = List.for_all (fun path -> has_source path node) paths in
     let surface_sources =
       [ "modules/hermes_dependability/dependability_surface.ml";
         "modules/hermes_dependability/dependability_surface.mli";
         "modules/hermes_dependability/test_dependability_surface.ml" ]
     in
     let event_store_sources =
       [ "modules/hermes_ops_dashboard/run_event_store.ml";
         "modules/hermes_ops_dashboard/run_event_store.mli";
         "modules/hermes_ops_dashboard/test_run_event_store.ml";
         "modules/hermes_ops_dashboard/dune" ]
     in
     let process_attempts =
       List.filter
         (fun (node : node) ->
           match node.kind with Process_attempt _ -> true | _ -> false)
         nodes
     in
     let requirement_keys =
       required_inputs intent
       |> List.map (fun (input : input_requirement) -> input.key)
     in
     List.for_all
       (fun path -> List.mem ("source:" ^ path) requirement_keys)
       (surface_sources @ event_store_sources)
     && binds_all surface_sources (find_node "fpp-mbse")
     && binds_all surface_sources (find_node "full-gate")
     && binds_all event_store_sources (find_node "native-focused")
     && List.for_all (binds_all event_store_sources) process_attempts
     && binds_all event_store_sources (find_node "full-gate"));

  Printf.printf "dependability_graph: %d passed, %d failed\n" !passed !failed;
  let self = Suite_telemetry.observe ~suite:"test_dependability_graph" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_dependability_core; Stanza.hermes_dependability_sqlite; Stanza.hermes_dependability_solver; Stanza.hermes_dependability_process; Stanza.hermes_dependability_topology ]);
  exit (Suite_telemetry.exit_code self)
