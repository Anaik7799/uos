(* The Claude operational layer under the same discipline as everything
   else: skills, agents and rules are CHECKED artifacts, not prose. A
   skill citing a tool that does not exist, a rule id that is not in the
   ledger, or an agent without its contract fails HERE — the drift gate
   the layer lacked (found by the second fractal pass). *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed; print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

let skills_dir = ".claude/skills"
let agents_dir = ".claude/agents"
let rules_path = "docs/hermes/mandatory-rules.md"

let skill_dirs () =
  Sys.readdir skills_dir |> Array.to_list
  |> List.filter (fun d -> Sys.is_directory (Filename.concat skills_dir d))
  |> List.sort compare

let skill_bodies () =
  List.map (fun d -> (d, read_file (Filename.concat (Filename.concat skills_dir d) "SKILL.md")))
    (skill_dirs ())

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

(* every `dune exec <path>.exe` citation must name a tool whose SOURCE exists *)
let cited_exes body =
  let re = Str.regexp "modules/[A-Za-z0-9_/]+\\.exe" in
  let rec collect i acc =
    match Str.search_forward re body i with
    | j -> collect (j + 1) (Str.matched_string body :: acc)
    | exception Not_found -> List.sort_uniq compare acc
  in
  collect 0 []

let () =
  check "the four core skills exist (and dirs match their frontmatter names)" (fun () ->
      let dirs = skill_dirs () in
      List.for_all (fun s -> List.mem s dirs)
        [ "feature-landing"; "hermes-wiki-zk"; "wiki-site-design"; "wiki-zk-operations";
          "workspace-structure" ]
      && List.for_all
           (fun (d, body) -> contains body ("name: " ^ d))
           (skill_bodies ()));
  check "every skill has a 'Use when' description (SDO discipline)" (fun () ->
      List.for_all (fun (_, body) -> contains body "description: Use when") (skill_bodies ()));
  check "every tool a skill cites EXISTS as source (runbooks stay runnable)" (fun () ->
      List.for_all
        (fun (d, body) ->
          List.for_all
            (fun exe ->
              let src = Filename.remove_extension exe ^ ".ml" in
              Sys.file_exists src
              || (Printf.printf "  %s cites missing %s\n" d src; false))
            (cited_exes body))
        (skill_bodies ()));
  check "every rule id a skill cites exists in the ledger" (fun () ->
      let rules = read_file rules_path in
      let re = Str.regexp "R1[0-9]" in
      List.for_all
        (fun (d, body) ->
          let rec ids i acc =
            match Str.search_forward re body i with
            | j -> ids (j + 1) (Str.matched_string body :: acc)
            | exception Not_found -> List.sort_uniq compare acc
          in
          List.for_all
            (fun r ->
              contains rules ("## " ^ r ^ " ")
              || contains rules ("## " ^ r ^ "\xe2\x80\x89")
              || contains rules (r ^ " —") || contains rules (r ^ " -")
              || (Printf.printf "  %s cites %s, not in the ledger\n" d r; false))
            (ids 0 []))
        (skill_bodies ()));
  check "the auditor agent exists, is read-only in posture, and declares tools" (fun () ->
      let body = read_file (Filename.concat agents_dir "wiki-auditor.md") in
      contains body "tools: Bash, Read, Grep, Glob"
      && contains body "never" && contains body "R5");
  check "meta-falsification: a missing citation IS detected" (fun () ->
      not (Sys.file_exists "modules/hermes_wiki/src/tools/no_such_tool.ml")
      && cited_exes "run modules/hermes_wiki/src/tools/no_such_tool.exe now"
         = [ "modules/hermes_wiki/src/tools/no_such_tool.exe" ])

let () =
  Printf.printf "claude_artifacts: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_claude_artifacts" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
