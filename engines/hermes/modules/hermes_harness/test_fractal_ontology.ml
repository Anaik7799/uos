(* Battle-testing the fractal ontology.

   The ontology's value is entirely in its completeness, so the tests are
   mostly completeness tests. An ontology with a gap is worse than none: it
   looks like the system has been analysed when part of it has not. *)

let passed = ref 0
let failures = ref []

let check condition label detail =
  if condition then incr passed
  else failures := (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

(* ------------------------------------------------------------- UNIT layer *)

let unit_layer () =
  check (Fractal_ontology.components <> []) "UNIT components exist" "";
  check (List.length Fractal_ontology.aspects = 11) "UNIT eleven aspects declared" "";
  check (List.length Fractal_ontology.levels = 8) "UNIT eight levels declared" "";
  let names = List.map Fractal_ontology.aspect_name Fractal_ontology.aspects in
  check
    (List.length (List.sort_uniq compare names) = 11)
    "UNIT aspect names are distinct" "";
  let level_names = List.map Fractal_ontology.level_name Fractal_ontology.levels in
  check
    (List.length (List.sort_uniq compare level_names) = 8)
    "UNIT level names are distinct" "";
  check
    (Fractal_ontology.component "parity_algebra" <> None)
    "UNIT lookup finds a component" "";
  check (Fractal_ontology.component "nope" = None) "UNIT lookup rejects unknown" ""

(* -------------------------------------------------------- STRUCTURE layer *)
(* The completeness enforcement. These are the tests that make the ontology an
   artifact rather than a document. *)

let structure_layer () =
  (* Every component addresses every aspect. A gap is a failing test, which is
     the only way an ontology stays true as the system grows. *)
  List.iter
    (fun (component : Fractal_ontology.component) ->
      let missing = Fractal_ontology.missing_aspects component in
      check (missing = [])
        ("STRUCTURE " ^ component.id ^ " addresses every aspect")
        (String.concat "," (List.map Fractal_ontology.aspect_name missing)))
    Fractal_ontology.components;

  (* No coverage claim may be a token gesture. A one-word "yes" is how a
     completeness table becomes theatre. *)
  List.iter
    (fun (component : Fractal_ontology.component) ->
      let vacuous = Fractal_ontology.vacuous_claims component in
      check (vacuous = [])
        ("STRUCTURE " ^ component.id ^ " makes substantive claims")
        (String.concat "," (List.map Fractal_ontology.aspect_name vacuous)))
    Fractal_ontology.components;

  (* Every component declares a complete algebra. A component whose composition
     is unspecified is one whose aggregation behaviour nobody decided. *)
  List.iter
    (fun (component : Fractal_ontology.component) ->
      let a = component.algebra in
      check
        (a.carrier <> "" && a.operation <> "" && a.identity <> "" && a.absorbing <> ""
       && a.laws <> [])
        ("STRUCTURE " ^ component.id ^ " declares a complete algebra") "")
    Fractal_ontology.components;

  (* Component ids are unique: a duplicate would make the atlas ambiguous. *)
  let ids = List.map (fun (c : Fractal_ontology.component) -> c.id) Fractal_ontology.components in
  check
    (List.length (List.sort_uniq compare ids) = List.length ids)
    "STRUCTURE component ids are unique" "";

  (* Every evidence level except the control plane has at least one component,
     so no level of the fractal is unrepresented. *)
  List.iter
    (fun level ->
      let present =
        List.exists (fun (c : Fractal_ontology.component) -> c.level = level)
          Fractal_ontology.components
      in
      check present
        ("STRUCTURE level " ^ Fractal_ontology.level_name level ^ " has a component") "")
    [ Fractal_ontology.L2_capability; L3_contract; L4_fixture; L5_trace; L6_receipt;
      LX_control ]

(* ------------------------------------------------------------ ATLAS layer *)

let atlas_layer () =
  (* Every edge connects declared components: a dangling edge is a lie about
     the structure. *)
  List.iter
    (fun (edge : Fractal_ontology.edge) ->
      check
        (Fractal_ontology.component edge.source <> None)
        "ATLAS edge source is a declared component" edge.source;
      check
        (Fractal_ontology.component edge.target <> None)
        "ATLAS edge target is a declared component" edge.target)
    Fractal_ontology.atlas;

  (* No self-edges: a component does not derive from itself. *)
  List.iter
    (fun (edge : Fractal_ontology.edge) ->
      check (edge.source <> edge.target) "ATLAS no self-edges" edge.source)
    Fractal_ontology.atlas;

  (* The evidence chain terminates: following Derives_from from the top reaches
     the inventory, which is the foundation everything rests on. *)
  let path = Fractal_ontology.evidence_path "parity_algebra" in
  check (List.length path >= 4) "ATLAS evidence path is a real chain"
    (String.concat " -> " path);
  check
    (List.nth path (List.length path - 1) = "inventory")
    "ATLAS evidence path grounds in the inventory" (String.concat " -> " path);

  (* Derives_from is acyclic: an evidence chain that loops proves nothing.
     Walking every component must terminate. *)
  List.iter
    (fun (component : Fractal_ontology.component) ->
      let path = Fractal_ontology.evidence_path component.id in
      check
        (List.length path = List.length (List.sort_uniq compare path))
        "ATLAS evidence path has no repeats" (String.concat " -> " path))
    Fractal_ontology.components;

  (* Relations are distinct and named. *)
  let relations =
    List.map Fractal_ontology.relation_name
      [ Fractal_ontology.Derives_from; Governs; Constrains; Observes ]
  in
  check (List.length (List.sort_uniq compare relations) = 4) "ATLAS relations are distinct" "";

  (* Observability reaches the components that can deny or block credit: an
     unobserved component cannot be diagnosed. *)
  List.iter
    (fun target ->
      check
        (List.exists
           (fun (e : Fractal_ontology.edge) ->
             e.relation = Fractal_ontology.Observes && e.target = target)
           Fractal_ontology.atlas)
        ("ATLAS " ^ target ^ " is observed") "")
    [ "reference_capture"; "gospel_contracts"; "parity_algebra" ]

(* -------------------------------------------------------------- BDD layer *)

let bdd_layer () =
  (* Given a component that declares an aspect not applicable, then it must say
     why: an unexamined aspect and an excluded one look identical otherwise. *)
  List.iter
    (fun (component : Fractal_ontology.component) ->
      List.iter
        (fun (aspect, claim) ->
          match claim with
          | Fractal_ontology.Not_applicable reason ->
              check
                (String.length reason > 20)
                ("BDD " ^ component.id ^ " justifies N/A for "
               ^ Fractal_ontology.aspect_name aspect)
                reason
          | Fractal_ontology.Addressed _ -> ())
        component.coverage)
    Fractal_ontology.components;

  (* Given the SDLC and SRE aspects, every component must address them: they are
     the ones most often skipped, and the ones an operator needs most. *)
  List.iter
    (fun (component : Fractal_ontology.component) ->
      check
        (Fractal_ontology.covered component Fractal_ontology.Sdlc <> None)
        ("BDD " ^ component.id ^ " has an SDLC claim") "";
      check
        (Fractal_ontology.covered component Fractal_ontology.Sre <> None)
        ("BDD " ^ component.id ^ " has an SRE claim") "")
    Fractal_ontology.components;

  (* Given the integrity aspect, no component may declare it not applicable:
     every component in an evidence chain can, in principle, record something
     unverified. *)
  List.iter
    (fun (component : Fractal_ontology.component) ->
      match Fractal_ontology.covered component Fractal_ontology.Integrity with
      | Some (Fractal_ontology.Addressed _) -> incr passed
      | Some (Fractal_ontology.Not_applicable reason) ->
          check false ("BDD " ^ component.id ^ " must address integrity") reason
      | None -> check false ("BDD " ^ component.id ^ " must address integrity") "absent")
    Fractal_ontology.components

(* --------------------------------------------------------- PROPERTY layer *)

let property_layer () =
  (* Rendering is total and non-trivial for every component. *)
  List.iter
    (fun (component : Fractal_ontology.component) ->
      let rendered = Fractal_ontology.render_component component in
      check (String.length rendered > 200) "PROPERTY component renders substantively"
        component.id;
      (* The rendering must mention every aspect, or the report hides a gap. *)
      List.iter
        (fun aspect ->
          let name = Fractal_ontology.aspect_name aspect in
          let rec contains index =
            index + String.length name <= String.length rendered
            && (String.sub rendered index (String.length name) = name
               || contains (index + 1))
          in
          check (contains 0) "PROPERTY rendering names every aspect"
            (component.id ^ "/" ^ name))
        Fractal_ontology.aspects)
    Fractal_ontology.components;

  (* edges_from and edges_to agree with the atlas. *)
  List.iter
    (fun (component : Fractal_ontology.component) ->
      let out = Fractal_ontology.edges_from component.id in
      check
        (List.for_all (fun (e : Fractal_ontology.edge) -> e.source = component.id) out)
        "PROPERTY edges_from filters correctly" component.id;
      let incoming = Fractal_ontology.edges_to component.id in
      check
        (List.for_all (fun (e : Fractal_ontology.edge) -> e.target = component.id) incoming)
        "PROPERTY edges_to filters correctly" component.id)
    Fractal_ontology.components;

  (* Not-applicable must stay rare. If most aspects are excused, the ontology
     has stopped saying anything. *)
  List.iter
    (fun (component : Fractal_ontology.component) ->
      check
        (Fractal_ontology.not_applicable_count component <= 3)
        ("PROPERTY " ^ component.id ^ " excuses at most three aspects")
        (string_of_int (Fractal_ontology.not_applicable_count component)))
    Fractal_ontology.components

(* ------------------------------------------------------------ CHAOS layer *)

let chaos_layer () =
  (* A component with an empty id or no coverage would break the invariants
     above; construct one and confirm the detectors fire, so the tests are
     testing something rather than passing vacuously. *)
  let broken =
    { Fractal_ontology.id = "broken"; level = Fractal_ontology.LX_control;
      module_path = "nowhere"; purpose = "a deliberately incomplete component";
      algebra =
        { carrier = ""; operation = ""; identity = ""; laws = []; absorbing = "" };
      coverage = [ (Fractal_ontology.Structural, Fractal_ontology.Addressed "short") ] }
  in
  check
    (List.length (Fractal_ontology.missing_aspects broken) = 10)
    "CHAOS a gap-ridden component is detected"
    (string_of_int (List.length (Fractal_ontology.missing_aspects broken)));
  check
    (Fractal_ontology.vacuous_claims broken <> [])
    "CHAOS a token claim is detected" "";
  check
    (String.length (Fractal_ontology.render_component broken) > 0)
    "CHAOS a broken component still renders" "";

  (* A dangling edge is detectable, so the atlas test is meaningful. *)
  let dangling = { Fractal_ontology.source = "nope"; relation = Derives_from; target = "inventory" } in
  check (Fractal_ontology.component dangling.source = None)
    "CHAOS a dangling edge source is detectable" "";

  (* evidence_path on an unknown id terminates rather than looping. *)
  check (Fractal_ontology.evidence_path "unknown" = [ "unknown" ])
    "CHAOS evidence path of an unknown component terminates" ""

let () =
  print_endline "fractal ontology suite";
  List.iter
    (fun (name, layer) ->
      layer ();
      Printf.printf "  %-12s done\n" name)
    [ ("unit", unit_layer); ("structure", structure_layer); ("atlas", atlas_layer);
      ("bdd", bdd_layer); ("property", property_layer); ("chaos", chaos_layer) ];
  Printf.printf "\ncomponents: %d   aspects: %d   edges: %d\npassed: %d   failed: %d\n"
    (List.length Fractal_ontology.components)
    (List.length Fractal_ontology.aspects)
    (List.length Fractal_ontology.atlas)
    !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_fractal_ontology" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_fractal_ontology ]);
  exit (Suite_telemetry.exit_code self)
