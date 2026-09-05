(* The formal-coverage registry under test: completeness is fail-closed in
   every direction (components vs ontology, aspects x4, scenarios vs BDD
   catalog, interactions vs topology, cited files vs the filesystem), the
   census cross-checks against independent recomputation, the declared
   intent reconciles clean — and every law is meta-falsified: fabricated
   inputs must produce gaps, or the law proves nothing. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false ->
      incr failed;
      print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let show gaps = List.iter (fun g -> print_endline ("  gap: " ^ g)) gaps

(* ------------------------------------------------------- completeness *)

let () =
  check "every ontology component has exactly one entry, no orphans" (fun () ->
      match Formal_coverage.component_gaps () with [] -> true | g -> show g; false);
  check "every entry claims all four aspect dimensions" (fun () ->
      match Formal_coverage.aspect_gaps () with [] -> true | g -> show g; false);
  check "every BDD scenario is backed by a component's formal artifacts" (fun () ->
      match Formal_coverage.scenario_gaps () with [] -> true | g -> show g; false);
  check "every topology interaction is governed by an entry" (fun () ->
      match Formal_coverage.interaction_gaps () with [] -> true | g -> show g; false);
  check "every cited anchor file exists on disk" (fun () ->
      match Formal_coverage.missing_files () with [] -> true | g -> show g; false);
  check "every entry carries at least one artifact and one anchor" (fun () ->
      List.for_all
        (fun (e : Formal_coverage.entry) ->
          e.Formal_coverage.artifacts <> [] && e.Formal_coverage.files <> [])
        Formal_coverage.entries);
  check "evidence_store models the immutable import planner" (fun () ->
      match Formal_coverage.entry_for "evidence_store" with
      | None -> false
      | Some entry ->
          List.mem "modules/hermes_harness/test_evidence_import.ml" entry.files
          && List.exists
               (fun artifact ->
                 String.equal (Formal_coverage.cite artifact)
                   "test_evidence_import: read-only superset planning, canonical digest binding, conflict and schema rejection")
               entry.artifacts);
  check "every populated fractal level is fully covered at Property rank or better"
    (fun () ->
      List.for_all
        (fun (_, components, covered) -> components = covered)
        (Formal_coverage.level_coverage ())
      && Formal_coverage.level_coverage () <> [])

(* ------------------------------------------------------------- grading *)

let () =
  check "the system floor is Property_tested or better (no bare Declared entries)"
    (fun () -> Formal_coverage.system_grade () >= 2);
  check "the algebra peak is machine-checked (Rocq)" (fun () ->
      match Formal_coverage.entry_for "parity_algebra" with
      | Some e -> Formal_coverage.grade e = 5
      | None -> false);
  check "the control plane carries solver proofs" (fun () ->
      match
        (Formal_coverage.entry_for "homeostasis", Formal_coverage.entry_for "harness_config")
      with
      | Some h, Some c -> Formal_coverage.grade h >= 4 && Formal_coverage.grade c >= 4
      | _ -> false);
  check "rank orders strengths strongest-first" (fun () ->
      Formal_coverage.(
        rank (Machine_checked "") > rank (Solver_proved "")
        && rank (Solver_proved "") > rank (Differentially_tested "")
        && rank (Differentially_tested "") > rank (Property_tested "")
        && rank (Property_tested "") > rank (Contracted "")
        && rank (Contracted "") > rank (Declared "")))

(* -------------------------------------------------------------- census *)

let () =
  let census = Formal_coverage.census () in
  let count key =
    match List.assoc_opt key census with Some n -> n | None -> -1
  in
  check "census: ontology components match the live ontology" (fun () ->
      count "ontology.components" = List.length Fractal_ontology.components);
  check "census: ontology edges match, and the relation split sums to the total"
    (fun () ->
      count "ontology.edges" = List.length Fractal_ontology.atlas
      && count "ontology.edges.derives_from" + count "ontology.edges.governs"
         + count "ontology.edges.constrains" + count "ontology.edges.observes"
         = count "ontology.edges");
  check "census: topology instances match the model" (fun () ->
      count "topology.instances"
      = List.length Harness_topology.model.Fpp_model.instances);
  check "census: direct connections and pattern graphs match the topology" (fun () ->
      count "topology.direct_connections"
      = List.length (Harness_topology.direct_connections ())
      && count "topology.pattern_graphs" = 4);
  check "census: machine sizes match the ConvergeLoop data" (fun () ->
      count "machine.states" = 6 && count "machine.signals" = 6
      && count "machine.transitions" > 0 && count "machine.choices" = 1);
  check "census: BDD catalog counts match" (fun () ->
      count "usecases.generic" = List.length Fpp_usecases.generic
      && count "usecases.workflows" = List.length Fpp_usecases.workflows);
  check "census: dictionary entry counts come from the emitted dictionary" (fun () ->
      count "dictionary.commands" > 0 && count "dictionary.events" > 0
      && count "dictionary.channels" > 0 && count "dictionary.parameters" = 4);
  check "census is deterministic" (fun () ->
      Formal_coverage.census () = Formal_coverage.census ());
  check "every port definition is instantiated at least once (no dead ports)"
    (fun () ->
      List.for_all (fun (_, n) -> n >= 1) (Formal_coverage.port_def_usage ()));
  check "every type definition is referenced at least once (no dead types)"
    (fun () ->
      List.for_all (fun (_, n) -> n >= 1) (Formal_coverage.type_def_usage ()));
  check "census: zenoh seams are counted from the live model, not asserted" (fun () ->
      count "zenoh.topics_live" = List.length Formal_coverage.zenoh_live_topics
      && count "zenoh.channels_eligible" = count "dictionary.channels"
      && count "zenoh.events_pager_eligible" >= 4
      && count "zenoh.seams_identified" = List.length Formal_coverage.zenoh_seams
      && List.for_all
           (fun (seam, rationale) ->
             String.length seam > 0 && String.length rationale > 20)
           Formal_coverage.zenoh_seams
      && List.exists (fun (seam, _) -> seam = "forbidden: evidence and verdict flows")
           Formal_coverage.zenoh_seams);
  check "port usage sums to the general-port instance population" (fun () ->
      let total =
        List.fold_left (fun acc (_, n) -> acc + n) 0 (Formal_coverage.port_def_usage ())
      in
      let general =
        List.fold_left
          (fun acc (c : Fpp_model.component) ->
            acc
            + List.length
                (List.filter
                   (function Fpp_model.General _ -> true | Fpp_model.Special _ -> false)
                   c.Fpp_model.ports))
          0 Harness_topology.model.Fpp_model.components
      in
      total = general)

(* -------------------------------------------------- declarative intent *)

let () =
  check "the declared intent reconciles clean (converged)" (fun () ->
      match Formal_coverage.reconcile () with [] -> true | g -> show g; false);
  check "intent covers the system floor and the named peaks" (fun () ->
      List.exists
        (fun (r : Formal_coverage.requirement) -> r.Formal_coverage.subject = "system-floor")
        Formal_coverage.intent
      && List.length Formal_coverage.intent >= 4)

(* ---------------------------------------------------- meta-falsification *)

let () =
  check "the component law can fail (fabricated component)" (fun () ->
      Formal_coverage.gaps_against ~label:"component" ~known:[ "ghost_component" ]
        ~claimed:(List.map (fun (e : Formal_coverage.entry) -> e.Formal_coverage.component)
                    Formal_coverage.entries)
      <> []);
  check "the scenario law can fail (fabricated scenario)" (fun () ->
      Formal_coverage.gaps_against ~label:"scenario" ~known:[ "a scenario nobody wrote" ]
        ~claimed:[] <> []);
  check "the interaction law can fail (fabricated connection)" (fun () ->
      Formal_coverage.gaps_against ~label:"interaction" ~known:[ "ghost->ghost" ]
        ~claimed:[] <> []);
  check "the orphan direction fails too (claimed but unknown)" (fun () ->
      Formal_coverage.gaps_against ~label:"component" ~known:[]
        ~claimed:[ "made_up_entry" ] <> [])

(* ---------------------------------------------------------------- grid *)

let () =
  let grid = Formal_coverage.grid () in
  List.iter print_endline grid;
  check "the grid renders one line per entry plus the header" (fun () ->
      List.length grid >= List.length Formal_coverage.entries)

let () =
  Printf.printf "formal_coverage: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_formal_coverage" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_formal_coverage ]);
  exit (Suite_telemetry.exit_code self)
