let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let get = function
  | Ok value -> value
  | Error errors -> failwith (String.concat "; " errors)

let names = List.map Zellij_intent.session_name Zellij_intent.all_sessions

let observed ?(command_present = true) ?(session_live = true)
    ?(cwd_matches = true) session =
  Zellij_algebra.make_observation ~session ~command_present ~session_live
    ~cwd_matches

let all_live = List.map observed Zellij_intent.all_sessions

let () =
  check "I1 session carrier is exactly zlt-1 through zlt-6"
    (names = [ "zlt-1"; "zlt-2"; "zlt-3"; "zlt-4"; "zlt-5"; "zlt-6" ]);
  check "I2 session names round-trip and foreign names fail closed"
    (List.for_all
       (fun session ->
         Zellij_intent.session_of_string (Zellij_intent.session_name session)
         = Some session)
       Zellij_intent.all_sessions
    && Zellij_intent.session_of_string "z3" = None
    && Zellij_intent.session_of_string "zlt-7" = None
    && Zellij_intent.session_of_string "" = None);
  let intent = get (Zellij_intent.default ()) in
  check "I3 default intent is valid, canonical, and digest-bound"
    (Zellij_intent.validate intent = []
    && Zellij_intent.workspace_root intent = "/home/an/dev/ver/harness-bionic"
    && Zellij_intent.shell intent = "/usr/bin/zsh"
    && Zellij_intent.sessions intent = Zellij_intent.all_sessions
    && String.length (Zellij_intent.digest intent) = 64
    && Zellij_intent.canonical_json intent
       = Zellij_intent.canonical_json (get (Zellij_intent.default ()))
    && Zellij_intent.digest intent
       = Zellij_intent.digest (get (Zellij_intent.default ())));
  check "A1 normalization rejects duplicate session observations"
    (match
       Zellij_algebra.normalize
         [ observed Zellij_intent.Zlt_1; observed Zellij_intent.Zlt_1 ]
     with
    | Error errors -> errors <> []
    | Ok _ -> false);
  check "A2 empty and partial observations cannot be complete"
    ((not (Zellij_algebra.complete []))
    && not (Zellij_algebra.complete [ observed Zellij_intent.Zlt_1 ]));
  check "A3 exact six-of-six live observation is complete"
    (Zellij_algebra.complete all_live);
  check "A4 any missing command, session, or cwd blocks completeness"
    ((not
        (Zellij_algebra.complete
           (observed ~command_present:false Zellij_intent.Zlt_1
           :: List.tl all_live)))
    && (not
          (Zellij_algebra.complete
             (observed ~session_live:false Zellij_intent.Zlt_1
             :: List.tl all_live)))
    && not
         (Zellij_algebra.complete
            (observed ~cwd_matches:false Zellij_intent.Zlt_1 :: List.tl all_live))
    );
  let exact_mapping =
    List.map
      (fun session -> (Zellij_intent.session_name session, session))
      Zellij_intent.all_sessions
  in
  check "A5 commands and sessions form an exact name-preserving bijection"
    (Zellij_algebra.command_session_bijection exact_mapping
    && (not
          (Zellij_algebra.command_session_bijection
             (("z3", Zellij_intent.Zlt_3) :: List.tl exact_mapping)))
    && not (Zellij_algebra.command_session_bijection (List.tl exact_mapping)));
  let absent =
    List.map (observed ~session_live:false) Zellij_intent.all_sessions
  in
  let ensured_once = Zellij_algebra.ensure_session Zellij_intent.Zlt_4 absent in
  check "A6 ensure is idempotent and changes only the selected session"
    (Zellij_algebra.ensure_session Zellij_intent.Zlt_4 ensured_once
     = ensured_once
    && List.for_all
         (fun observation ->
           Zellij_algebra.session_live observation
           = (Zellij_algebra.session observation = Zellij_intent.Zlt_4))
         ensured_once);
  check "A7 normalized union is commutative and idempotent"
    (let left =
       [
         observed ~session_live:false Zellij_intent.Zlt_1;
         observed Zellij_intent.Zlt_2;
       ]
     in
     let right =
       [
         observed Zellij_intent.Zlt_1;
         observed ~cwd_matches:false Zellij_intent.Zlt_2;
       ]
     in
     Zellij_algebra.union left right = Zellij_algebra.union right left
     && Zellij_algebra.union left left = Zellij_algebra.normalize left);
  check "O1 ontology is total with one L0, one L1, six L2, and L3-L6/LX"
    (Zellij_ontology.validate () = []
    && List.length
         (List.filter
            (fun node -> Zellij_ontology.level node = Zellij_ontology.L0)
            Zellij_ontology.nodes)
       = 1
    && List.length
         (List.filter
            (fun node -> Zellij_ontology.level node = Zellij_ontology.L1)
            Zellij_ontology.nodes)
       = 1
    && List.length
         (List.filter
            (fun node -> Zellij_ontology.level node = Zellij_ontology.L2)
            Zellij_ontology.nodes)
       = 6
    && List.for_all
         (fun level ->
           List.exists
             (fun node -> Zellij_ontology.level node = level)
             Zellij_ontology.nodes)
         [
           Zellij_ontology.L3;
           Zellij_ontology.L4;
           Zellij_ontology.L5;
           Zellij_ontology.L6;
           Zellij_ontology.LX;
         ]);
  check "O2 every ontology node has substantive algebra and evidence fields"
    (List.for_all
       (fun node ->
         Zellij_ontology.id node <> ""
         && Zellij_ontology.carrier node <> ""
         && Zellij_ontology.operations node <> []
         && Zellij_ontology.observations node <> []
         && Zellij_ontology.invariants node <> []
         && Zellij_ontology.hazards node <> []
         && Zellij_ontology.sources node <> [])
       Zellij_ontology.nodes);
  check "O3 ontology validation detects a dangling parent negative control"
    (match Zellij_ontology.nodes with
    | node :: tail ->
        Zellij_ontology.validate_nodes
          (Zellij_ontology.with_parent node (Some "missing-parent") :: tail)
        <> []
    | [] -> false);
  check "T1 atomic atlas is total and every ontology edge resolves"
    (Zellij_atlas.validate () = []
    && List.for_all
         (fun row ->
           Option.is_some (Zellij_ontology.find (Zellij_atlas.ontology_id row)))
         Zellij_atlas.rows);
  check "T2 every declared session has attach ensure observe and verify rows"
    (List.for_all
       (fun session ->
         List.for_all
           (fun operation ->
             Zellij_atlas.has_session_operation ~session ~operation)
           [
             Zellij_atlas.Attach;
             Zellij_atlas.Ensure;
             Zellij_atlas.Observe;
             Zellij_atlas.Verify;
           ])
       Zellij_intent.all_sessions);
  check "T3 documentation inventory is nonempty and grants no semantic credit"
    (Zellij_atlas.documentation_pages <> []
    && List.for_all
         (fun row ->
           Zellij_atlas.lifecycle row = Zellij_atlas.Documented_only
           && Zellij_atlas.credit row = Zellij_atlas.No_credit
           && Option.is_some (Zellij_atlas.documentation_url row))
         Zellij_atlas.documentation_pages);
  check "T4 atlas rejects documentation-credit leakage negative control"
    (match Zellij_atlas.documentation_pages with
    | row :: tail ->
        Zellij_atlas.validate_rows
          (Zellij_atlas.with_credit row Zellij_atlas.Structural_credit :: tail)
        <> []
    | [] -> false);
  check "T5 atlas rejects one missing session-operation row"
    (match
       List.find_opt
         (fun row ->
           Zellij_atlas.session row = Some Zellij_intent.Zlt_6
           && Zellij_atlas.operation row = Some Zellij_atlas.Verify)
         Zellij_atlas.rows
     with
    | None -> false
    | Some missing ->
        Zellij_atlas.validate_rows
          (List.filter
             (fun row -> Zellij_atlas.id row <> Zellij_atlas.id missing)
             Zellij_atlas.rows)
        <> []);
  let telemetry =
    Suite_telemetry.observe ~suite:"test_zellij_model" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit telemetry ~targets:[]);
  exit (Suite_telemetry.exit_code telemetry)
