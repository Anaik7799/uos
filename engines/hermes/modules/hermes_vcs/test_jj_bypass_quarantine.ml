let failures = ref []
let passed = ref 0

let check name condition =
  if condition then incr passed else failures := name :: !failures

let read path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let contains source needle =
  let source_length = String.length source in
  let needle_length = String.length needle in
  let rec loop offset =
    if offset + needle_length > source_length then false
    else if String.sub source offset needle_length = needle then true
    else loop (offset + 1)
  in
  loop 0

let () =
  let controller = read "modules/hermes_vcs/jj_controller.ml" in
  let mcp = read "modules/hermes_vcs/jj_mcp.ml" in
  let adapter = read "modules/swarm/jj_swarm_adapter.ml" in
  let vcs_dune = read "modules/hermes_vcs/dune" in
  let swarm_dune = read "modules/swarm/dune" in
  let skill = read ".claude/skills/jujutsu-vcs/SKILL.md" in
  check "Q1 forbidden controller shell renderer removed from production source"
    (not (contains controller "synthesize_jj_command")
     && not (contains controller "Unix.system"));
  check "Q2 forbidden MCP executor removed from production source"
    (not (contains mcp "open Jj_controller")
     && not (contains mcp "execute_intent"));
  check "Q3 forbidden direct Swarm adapter removed from production source"
    (not (contains adapter "Jj_controller.execute_intent"));
  check "Q4 VCS Dune excludes controller MCP and unix ownership"
    (not (contains vcs_dune "jj_controller")
     && not (contains vcs_dune "jj_mcp")
     && not (contains vcs_dune "unix")
     && contains vcs_dune "(libraries digestif)");
  check "Q5 Swarm Dune excludes direct adapter and hermes_vcs edge"
    (not (contains swarm_dune "jj_swarm_adapter")
     && not (contains swarm_dune "hermes_vcs"));
  check "Q6 Jujutsu skill excludes raw execution instructions"
    (not (contains skill "jj describe")
     && not (contains skill "jj new")
     && not (contains skill "jj undo")
     && not (contains skill "jj git"));
  List.iter (fun name -> Printf.printf "BYPASS: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let self =
    Suite_telemetry.observe ~suite:"test_jj_bypass_quarantine"
      ~passed:!passed ~failed ~skipped:0
  in
  Printf.printf "Jujutsu bypass denominator: 6 required absence checks\n";
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vcs ]);
  exit (Suite_telemetry.exit_code self)
