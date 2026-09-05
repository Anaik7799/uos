(* Hand-written invariants over the tool_execution units -- the backstop the
   parity fixtures cannot be. Every law carries a negative control
   (HZ-FIX-03). *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let () =
  (* registry: the estimate is ceil(chars/4) of compact json. *)
  check (Tool_units.estimate_tokens_from_schemas [] = 0) "REGISTRY empty defs cost nothing";
  let one = `Assoc [ ("a", `Int 1) ] in
  (* {"a":1} is 7 chars -> ceil(7/4) = 2 *)
  check (Tool_units.estimate_tokens_from_schemas [ one ] = 2)
    "REGISTRY a 7-char def estimates to 2 tokens";
  check
    (Tool_units.estimate_tokens_from_schemas [ one; one ]
    > Tool_units.estimate_tokens_from_schemas [ one ])
    "LAW the estimate is monotone in the def list";
  check (not (Tool_units.should_activate ~enabled:"off" ~deferrable_tokens:100))
    "REGISTRY off never activates";
  check (not (Tool_units.should_activate ~enabled:"auto" ~deferrable_tokens:0))
    "REGISTRY zero deferrable never activates";
  check (Tool_units.should_activate ~enabled:"auto" ~deferrable_tokens:1)
    "CONTROL a deferrable token activates";
  check
    (Tool_units.listing_token_budget ~threshold_pct:5.0 ~listing_max_tokens:8000
       ~context_length:None
    = 8000)
    "REGISTRY the unknown-window leg is min(max, 10000)";
  check
    (Tool_units.listing_token_budget ~threshold_pct:1.0 ~listing_max_tokens:8000
       ~context_length:(Some 200000)
    = 2000)
    "REGISTRY the pct leg wins when smaller";

  (* dispatch: destructive commands at shell boundaries only. *)
  check (Tool_units.is_destructive_command "rm -rf x") "DISPATCH rm at start is destructive";
  check (Tool_units.is_destructive_command "make && rm out")
    "DISPATCH rm after a shell join is destructive";
  check (not (Tool_units.is_destructive_command "confirm-rm now"))
    "CONTROL rm inside a word is not";
  check (not (Tool_units.is_destructive_command "git status"))
    "CONTROL a safe git subcommand is not";
  check (Tool_units.is_destructive_command "git reset --hard")
    "DISPATCH git reset is destructive";
  check (Tool_units.is_destructive_command "echo x > f") "DISPATCH single > overwrites";
  check (not (Tool_units.is_destructive_command "echo x >> f"))
    "CONTROL append >> does not";
  check (not (Tool_units.is_destructive_command "")) "CONTROL the empty command is safe";

  (* approval: the accepted-word set, exactly. *)
  check (Tool_units.normalize_enabled (`String " APPROVE ")) "APPROVAL approve normalizes on";
  check (not (Tool_units.normalize_enabled (`String "maybe"))) "CONTROL garbage is off";
  check (not (Tool_units.normalize_enabled (`Int 1)))
    "APPROVAL a non-bool non-string is off (even truthy)";

  (* patch: the parser round-trips structure and refuses hollow updates. *)
  let ops, err =
    Tool_units.parse_v4a_patch
      "*** Begin Patch\n*** Update File: a.ml\n@@ ctx @@\n keep\n-old\n+new\n*** End Patch"
  in
  check (err = None && List.length ops = 1) "PATCH one update parses";
  (match ops with
   | [ op ] ->
       check (op.Tool_units.op_kind = "OperationType.UPDATE") "PATCH the kind is UPDATE";
       check
         (match op.Tool_units.hunks with
          | [ h ] ->
              h.Tool_units.context_hint = Some "ctx"
              && List.map (fun (l : Tool_units.hunk_line) -> (l.prefix, l.content)) h.lines
                 = [ (" ", "keep"); ("-", "old"); ("+", "new") ]
          | _ -> false)
         "PATCH the hunk carries hint and prefixed lines"
   | _ -> check false "PATCH expected exactly one operation");
  let _, err_hollow =
    Tool_units.parse_v4a_patch "*** Begin Patch\n*** Update File: b.ml\n*** End Patch"
  in
  check (err_hollow <> None) "PATCH an update with no hunks errors";
  (* The frozen !r error formatting uses single quotes -- a divergence the
     harness caught against an earlier %S. *)
  check
    (err_hollow = Some "Parse error: UPDATE 'b.ml': no hunks found")
    "PATCH the hollow-update error quotes the path Python-repr style";
  (* An empty @@ @@ marker yields a single-space hint (regex backtracking),
     not None and not "" -- both earlier candidate guesses the harness
     refuted. *)
  let ops_sp, _ =
    Tool_units.parse_v4a_patch
      "*** Begin Patch\n*** Update File: e.ml\n@@ @@\n ctx\n+x\n*** End Patch"
  in
  check
    (match ops_sp with
     | [ op ] -> (
         match op.Tool_units.hunks with
         | [ h ] -> h.Tool_units.context_hint = Some " "
         | _ -> false)
     | _ -> false)
    "PATCH an empty @@ @@ marker yields a single-space context hint";
  check (Tool_units.parse_v4a_patch "" = ([], None)) "CONTROL the empty patch is empty, not an error";

  (* result: canonical args and the failure classifier. *)
  check
    (Tool_units.canonical_tool_args (`Assoc [ ("b", `Int 1); ("a", `Int 2) ])
    = Ok "{\"a\":2,\"b\":1}")
    "RESULT canonical args sort compactly";
  check
    (Tool_units.classify_tool_failure ~tool_name:"terminal"
       ~result:(Some "{\"exit_code\": 3}")
    = (true, " [exit 3]"))
    "RESULT a nonzero exit classifies failed with its suffix";
  check
    (Tool_units.classify_tool_failure ~tool_name:"web_search" ~result:(Some "Error: x")
    = (true, " [error]"))
    "RESULT an Error prefix classifies failed";
  check
    (Tool_units.classify_tool_failure ~tool_name:"write_file"
       ~result:(Some "{\"bytes_written\": 5}")
    = (false, ""))
    "CONTROL a landed write never classifies failed";
  check
    (Tool_units.file_mutation_result_landed ~tool_name:"read_file"
       ~result:"{\"success\": true}"
    = false)
    "CONTROL a non-mutating tool never lands";

  Printf.printf "tool units: %d passed, %d failed\n" !passed
    (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_tool_units" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_tool_units ]);
  exit (Suite_telemetry.exit_code self)
