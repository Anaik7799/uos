(* Hand-written invariants over the skills units -- the backstop the parity
   fixtures cannot be. Every law carries a negative control (HZ-FIX-03). *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let () =
  (* ---- skill_discovery ---- *)
  check (Skill_units.normalize_prerequisite_values `Null = []) "SKILL empty prereq value is []";
  check
    (Skill_units.normalize_prerequisite_values (`List [ `String "A"; `String "  "; `String "B" ])
    = [ "A"; "B" ])
    "SKILL prereq list drops blank entries";
  check (Skill_units.normalize_prerequisite_values (`String "X") = [ "X" ])
    "SKILL a bare string prereq wraps to a one-item list";

  check
    (Skill_units.parse_tags (`List [ `String "a"; `Int 0; `String " b " ]) = [ "a"; "b" ])
    "SKILL parse_tags drops Python-falsy entries (0), trims strings";
  check
    (Skill_units.parse_tags (`String "[\"x\", 'y']") = [ "x"; "y" ])
    "SKILL parse_tags unwraps brackets and strips quote chars";
  check (Skill_units.parse_tags `Null = []) "CONTROL a null tags value is empty";

  let skills =
    [ `Assoc [ ("name", `String "b"); ("category", `String "x") ];
      `Assoc [ ("name", `String "a"); ("category", `Null) ] ]
  in
  check
    (match Skill_units.sort_skills skills with
     | [ `Assoc first; _ ] -> List.assoc_opt "name" first = Some (`String "a")
     | _ -> false)
    "SKILL sort_skills puts an empty category before a real one";

  check (Skill_units.skill_lookup_path_error "notes/setup" = None) "SKILL a relative name is fine";
  check
    (Skill_units.skill_lookup_path_error "/etc/passwd" <> None)
    "SKILL a POSIX-absolute name is rejected";
  check
    (Skill_units.skill_lookup_path_error "C:foo" <> None)
    "SKILL a Windows drive-relative name is rejected (the .drive-truthy branch)";
  check
    (Skill_units.skill_lookup_path_error "a/../../etc" <> None)
    "SKILL a traversal component is rejected";
  check (not (Skill_units.has_traversal_component "a/b/c")) "CONTROL a clean path has no traversal";

  (* ---- skill_bundles ---- *)
  check (Skill_units.slugify "Foo_Bar!" = "foo-bar") "SKILL slugify: underscore->hyphen before strip";
  check (Skill_units.slugify "a---b" = "a-b") "SKILL slugify collapses multi-hyphen runs";
  check (Skill_units.slugify "--x--" = "x") "SKILL slugify strips leading/trailing hyphens";

  (* ---- skill_preprocessing ---- *)
  check
    (Skill_units.substitute_template_vars ~content:"go to ${HERMES_SKILL_DIR}/x"
       ~skill_dir:(Some "/skills/foo") ~session_id:None
    = "go to /skills/foo/x")
    "SKILL template var substitutes when present";
  check
    (Skill_units.substitute_template_vars ~content:"id=${HERMES_SESSION_ID}" ~skill_dir:None
       ~session_id:(Some "")
    = "id=${HERMES_SESSION_ID}")
    "SKILL an explicit empty session_id is treated as absent (Python truthiness)";

  check
    (Skill_units.skill_matches_platform_list ~current:"darwin" ~running_in_termux:false
       (`List [ `String "macos" ]))
    "SKILL macos maps to darwin and matches";
  check
    (Skill_units.skill_matches_platform_list ~current:"linux" ~running_in_termux:true
       (`List [ `String "termux" ]))
    "SKILL termux flag matches an explicit termux platform entry";
  check
    (not
       (Skill_units.skill_matches_platform_list ~current:"win32" ~running_in_termux:false
          (`List [ `String "linux" ])))
    "CONTROL a non-matching platform list returns false";
  check (Skill_units.skill_matches_platform_list ~current:"linux" ~running_in_termux:false `Null)
    "SKILL no declared platforms means it matches everywhere";

  check
    (Skill_units.extract_skill_config_vars
       (`Assoc
         [ ("metadata",
            `Assoc
              [ ("hermes",
                 `Assoc
                   [ ("config",
                      `List
                        [ `Assoc
                            [ ("key", `String "k"); ("description", `String "d");
                              ("default", `Int 0) ] ]) ]) ]) ])
    = [ `Assoc
          [ ("key", `String "k"); ("description", `String "d"); ("default", `Int 0);
            ("prompt", `String "d") ] ])
    "SKILL config default:0 is preserved (is-not-None, not truthiness)";

  check (Skill_units.extract_skill_description (`Assoc [ ("description", `String "  'hi'  ") ]) = "hi")
    "SKILL description strips whitespace then quote chars";
  check
    (String.length
       (Skill_units.extract_skill_description
          (`Assoc [ ("description", `String (String.make 80 'x')) ]))
    = 60)
    "SKILL a long description truncates to exactly the 60-char limit";

  (* ---- skill_sync ---- *)
  check
    (Skill_units.canonical_json_bytes (`Assoc [ ("b", `Int 1); ("a", `Int 2) ]) = "{\"a\":2,\"b\":1}")
    "SKILL canonical_json_bytes sorts keys with compact separators";
  check (Skill_units.merge_skill ~base:(Some "h") ~ours:(Some "h") ~theirs:(Some "h") = "either")
    "SKILL merge: unanimous non-empty is either";
  check (Skill_units.merge_skill ~base:None ~ours:None ~theirs:None = "none")
    "SKILL merge: unanimous None is none";
  check (Skill_units.merge_skill ~base:(Some "b") ~ours:(Some "o") ~theirs:(Some "b") = "ours")
    "SKILL merge: only ours changed";
  check (Skill_units.merge_skill ~base:(Some "b") ~ours:(Some "x") ~theirs:(Some "y") = "overlap")
    "SKILL merge: both changed and differ is overlap";
  check (Skill_units.parse_bool (`String "") = Some false)
    "SKILL parse_bool: empty string is False, not unrecognized";
  check (Skill_units.parse_bool (`String "maybe") = None) "SKILL parse_bool: unrecognized is None";
  check (Skill_units.parse_bool (`Bool true) = Some true) "CONTROL a real bool passes through";

  let manifest = Skill_units.build_sync_manifest_bytes [ ("b", true); ("a", false) ] in
  check
    (match Skill_units.parse_sync_manifest manifest with
     | Some [ ("a", false); ("b", true) ] -> true
     | _ -> false)
    "SKILL manifest round-trips through build then parse, sorted";
  check (Skill_units.parse_sync_manifest "not json" = None) "CONTROL unparseable data returns None";

  (* ---- skill_provenance ---- *)
  let allowed, _ =
    Skill_units.should_allow_install ~trust_level:"builtin" ~verdict:"dangerous" ~findings_count:3
      ~force:false
  in
  check (allowed = `Allowed) "SKILL builtin always allows regardless of verdict";
  let ask, _ =
    Skill_units.should_allow_install ~trust_level:"agent-created" ~verdict:"dangerous"
      ~findings_count:1 ~force:false
  in
  check (ask = `NeedsConfirmation) "SKILL agent-created + dangerous asks for confirmation";
  let blocked, _ =
    Skill_units.should_allow_install ~trust_level:"community" ~verdict:"dangerous" ~findings_count:1
      ~force:true
  in
  check (blocked = `Blocked) "SKILL --force cannot override a dangerous community verdict";

  check (Skill_units.determine_verdict [ "low"; "medium" ] = "safe") "SKILL only low/medium is safe";
  check (Skill_units.determine_verdict [ "high" ] = "caution") "SKILL a high finding is caution";
  check (Skill_units.determine_verdict [ "critical"; "low" ] = "dangerous")
    "SKILL any critical finding is dangerous";

  check (Skill_units.resolve_trust_level "anthropics/skills" = "trusted") "SKILL an exact trusted repo";
  check (Skill_units.resolve_trust_level "anthropics/skills/extra" = "trusted")
    "SKILL a trusted-repo prefix match";
  check (Skill_units.resolve_trust_level "skills-sh/agent-created" = "agent-created")
    "SKILL a prefix alias strips before the agent-created check";
  check (Skill_units.resolve_trust_level "randomperson/repo" = "community")
    "CONTROL an unrecognized source is community";

  Printf.printf "skill units: %d passed, %d failed\n" !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_skill_units" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_skill_units ]);
  exit (Suite_telemetry.exit_code self)
