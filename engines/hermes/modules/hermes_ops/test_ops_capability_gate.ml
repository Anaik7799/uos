let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false ->
      incr failed;
      Printf.printf "FAILED: %s\n" name
  | exception exn ->
      incr failed;
      Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let declared_names kind =
  Ops_capability.all
  |> List.filter (fun (declaration : Ops_capability.declaration) ->
         declaration.kind = kind)
  |> List.map (fun (declaration : Ops_capability.declaration) ->
         match String.split_on_char '.' declaration.id with
         | _prefix :: rest -> String.concat "." rest
         | [] -> declaration.id)
  |> List.sort_uniq compare

let () =
  check "N3 mandatory-rules prose is a total projection of OCaml rule ids"
    (fun () ->
      Ops_capability_gate.projected_rule_ids
        ~path:"docs/hermes/mandatory-rules.md"
      = Ops_capability.rule_ids ());
  check "N3b mandatory-rules prose is an exact projection of OCaml rule titles"
    (fun () ->
      Ops_capability_gate.projected_rule_titles
        ~path:"docs/hermes/mandatory-rules.md"
      = Ops_capability.rule_titles);
  check "N4 every tracked repository skill is declared exactly once" (fun () ->
      let projected =
        Ops_capability_gate.tracked_skill_names ~root:".claude/skills"
      in
      projected <> [] && declared_names Ops_capability.Skill = projected);
  check "N5 every tracked Claude agent is declared exactly once" (fun () ->
      let projected =
        Ops_capability_gate.tracked_agent_names ~root:".claude/agents"
      in
      projected <> [] && declared_names Ops_capability.Agent = projected);
  check "S1 registry validation reports no schema/dependency/projection gaps"
    (fun () -> Ops_capability_gate.validate ~root:"." = []);
  Printf.printf "ops_capability_gate: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_capability_gate" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability ]);
  exit (Suite_telemetry.exit_code self)
