(* The ruliad rule catalog is an artifact, not prose: complete (definition, all
   supplied concepts, PCE, observers), sourced (every rule cites a reference),
   mapped (every rule names what it means IN THIS HARNESS), and honest about
   enforcement (Enforced names the test/module; Advisory says why not). *)

let () =
  let open Ruliad_rules in
  (* Unique, non-empty ids. *)
  let ids = List.map (fun r -> r.id) rules in
  assert (List.length (List.sort_uniq compare ids) = List.length ids);
  assert (List.for_all (fun id -> String.trim id <> "") ids);

  (* Substantive statements, mappings and sources -- no token gestures. *)
  List.iter
    (fun r ->
      assert (String.length r.statement > 40);
      assert (String.length r.harness_mapping > 40);
      assert (String.length r.source > 10))
    rules;

  (* The canonical concepts are all present. *)
  List.iter
    (fun id -> assert (List.exists (fun r -> r.id = id) rules))
    [ "RUL-DEF"; "RUL-PCE"; "RUL-IRREDUCIBILITY"; "RUL-CAUSAL-INVARIANCE";
      "RUL-MULTIWAY"; "RUL-RULE-SPACE"; "RUL-OBSERVER"; "RUL-EMERGENCE";
      "RUL-FORECAST-LIMIT"; "RUL-MEMOIZATION" ];

  (* Every Enforced rule names a real anchor (a module or test that exists). *)
  List.iter
    (fun r ->
      match r.enforcement with
      | Enforced anchor ->
          (* bare names live under hermes_harness/; a path with '/' is
             repo-relative (the diagnostic moved into the self-contained
             wiki folder) *)
          let path =
            if String.contains anchor '/' then anchor
            else Filename.concat "modules/hermes_harness" anchor
          in
          assert (Sys.file_exists path)
      | Advisory reason -> assert (String.length reason > 20))
    rules;

  (* References: the catalog carries the full bibliography, including MathWorld
     and the concept sources supplied with the directive. *)
  assert (List.length references >= 8);
  assert (List.exists (fun (name, _) -> name = "mathworld-ruliad") references);
  assert (List.exists (fun (name, _) -> name = "hashlife-paper") references);
  List.iter (fun (_, citation) -> assert (String.length citation > 15)) references;

  Printf.printf "ruliad_rules: ok (%d rules, %d references)\n" (List.length rules)
    (List.length references)

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_ruliad_rules" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_ruliad_rules ]);
  exit (Suite_telemetry.exit_code self)
