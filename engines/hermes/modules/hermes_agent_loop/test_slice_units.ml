(* Hand-written invariants over the four slice-unit modules -- the backstop
   the parity fixtures cannot be. Every law carries a negative control
   (HZ-FIX-03). *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let () =
  (* --- prompt: frontmatter strip --- *)
  check
    (Prompt_units.strip_yaml_frontmatter "---\nk: v\n---\nbody" = "body")
    "FRONTMATTER a fenced block strips to the body";
  check
    (Prompt_units.strip_yaml_frontmatter "---\nk: v\nno close"
    = "---\nk: v\nno close")
    "FRONTMATTER no closing fence keeps the original";
  check
    (Prompt_units.strip_yaml_frontmatter "---\nk: v\n---\n" = "---\nk: v\n---\n")
    "FRONTMATTER an empty body returns the ORIGINAL content";
  check
    (Prompt_units.strip_yaml_frontmatter "plain" = "plain")
    "CONTROL plain content is untouched";
  (* idempotence: a stripped body never strips again unless it is itself
     fenced -- and then stripping is still stable on the fixpoint *)
  let once = Prompt_units.strip_yaml_frontmatter "---\nk: v\n---\nreal body" in
  check
    (Prompt_units.strip_yaml_frontmatter once = once)
    "LAW frontmatter strip is idempotent on its output";

  (* --- prompt: budget --- *)
  check
    (Prompt_units.dynamic_context_file_max_chars None = 20_000)
    "BUDGET unknown window takes the floor";
  check
    (Prompt_units.dynamic_context_file_max_chars (Some 100_000) = 24_000)
    "BUDGET the mid window scales as int(cl * 4 * 0.06)";
  check
    (Prompt_units.dynamic_context_file_max_chars (Some 10_000_000) = 500_000)
    "BUDGET the ceiling caps a huge window";
  (* monotone: a larger window never shrinks the budget *)
  let budgets =
    List.map (fun l -> Prompt_units.dynamic_context_file_max_chars (Some l))
      [ 1; 1_000; 50_000; 100_000; 500_000; 5_000_000; 50_000_000 ]
  in
  let rec monotone = function
    | a :: (b :: _ as rest) -> a <= b && monotone rest
    | _ -> true
  in
  check (monotone budgets) "LAW the budget is monotone in the window";
  check (List.exists (fun b -> b <> List.hd budgets) budgets)
    "CONTROL the budget actually varies over the range";

  (* --- context: parser laws --- *)
  let refs = Context_units.parse_context_references "a @file:x.ml b @diff c" in
  check (List.length refs = 2) "PARSE two references parse from mixed text";
  (* offsets index the ORIGINAL message: raw is recoverable by slicing *)
  check
    (List.for_all
       (fun (r : Context_units.reference) ->
         String.sub "a @file:x.ml b @diff c" r.start (r.finish - r.start) = r.raw)
       refs)
    "LAW start/end recover raw by slicing the original";
  check
    (Context_units.parse_context_references "me@file:x" = [])
    "LAW the lookbehind bars a word character before @";
  check
    (Context_units.parse_context_references "see @file:x" <> [])
    "CONTROL the same reference parses after a space";

  (* quoting round-trip: a quoted value re-parses to the same target *)
  let round_trips value =
    let quoted = Context_units.format_reference_value value in
    match Context_units.parse_context_references ("@file:" ^ quoted) with
    | [ r ] -> r.target = value
    | _ -> false
  in
  check (round_trips "src/main.ml") "LAW quote/parse round-trips a clean path";
  check (round_trips "a b.txt") "LAW quote/parse round-trips a spaced path";
  check
    (not (round_trips "has space and ` \" ' every quote"))
    "CONTROL an unquotable value does not round-trip (frozen limitation, shared)";

  (* --- compress: marker round-trip --- *)
  let names = [ "alpha"; "beta" ] in
  let markers = String.concat "\n" (List.map Compress_units.skill_pruned_marker names) in
  check
    (Compress_units.extract_pruned_skill_names markers = names)
    "LAW extract inverts marker emission, in order";
  check
    (Compress_units.extract_pruned_skill_names "no markers here" = [])
    "CONTROL extraction over plain text is empty";
  let reinjected = Compress_units.reinject_pruned_skill_markers "summary." names in
  check
    (List.for_all
       (fun name -> List.mem name (Compress_units.extract_pruned_skill_names reinjected))
       names)
    "LAW reinjection makes every requested marker extractable";
  check
    (Compress_units.reinject_pruned_skill_markers reinjected names = reinjected)
    "LAW reinjection is idempotent";
  check
    (Compress_units.reinject_pruned_skill_markers "s" [] = "s")
    "CONTROL no names, no change";

  (* --- finalize --- *)
  let call = `Assoc [ ("id", `String "t") ] in
  check
    (Finalize_units.is_pure_tool_call_tail
       (`Assoc [ ("content", `Null); ("tool_calls", `List [ call ]) ]))
    "TAIL calls with no text is a pure tail";
  check
    (not
       (Finalize_units.is_pure_tool_call_tail
          (`Assoc [ ("content", `String "answer"); ("tool_calls", `List [ call ]) ])))
    "CONTROL visible text is not a pure tail";
  check
    (Finalize_units.count_diff_lines "--- a\n+++ b\n+x\n-y\n+z" = (2, 1))
    "DIFF headers are excluded from the counts";
  check
    (Finalize_units.count_diff_lines "" = (0, 0))
    "CONTROL an empty diff counts nothing";
  check (Finalize_units.format_elapsed 12.44 = "12.4s") "ELAPSED sub-minute formats to 0.1s";
  check (Finalize_units.format_elapsed 65.0 = "1m05s") "ELAPSED minutes zero-pad the seconds";
  check (Finalize_units.format_elapsed (-3.0) = "0.0s") "ELAPSED negatives clamp to zero";
  check (Finalize_units.pluralize 1 "entries" = "1 entry") "PLURAL ies singularizes to y";
  check (Finalize_units.pluralize 3 "files" = "3 files") "CONTROL plural counts stay plural";

  Printf.printf "slice units: %d passed, %d failed\n" !passed
    (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_slice_units" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_conversation_loop; Stanza.hermes_agent_loop_prompt_assembly; Stanza.hermes_agent_loop_context_engine; Stanza.hermes_agent_loop_context_compression; Stanza.hermes_agent_loop_turn_finalization; Stanza.hermes_agent_loop_interrupt_control; Stanza.hermes_agent_loop_message_hygiene; Stanza.hermes_agent_loop_message_repairs; Stanza.hermes_agent_loop_json_canonical; Stanza.hermes_agent_loop_loop_send_path; Stanza.hermes_agent_loop_prompt_units; Stanza.hermes_agent_loop_context_units; Stanza.hermes_agent_loop_compress_units; Stanza.hermes_agent_loop_finalize_units; Stanza.hermes_agent_loop_redact_units; Stanza.hermes_agent_loop_tool_units; Stanza.hermes_agent_loop_context_file_units; Stanza.hermes_agent_loop_memory_units; Stanza.hermes_agent_loop_skill_units; Stanza.hermes_agent_loop_interactive_cli_units; Stanza.hermes_agent_loop_mcp_units; Stanza.hermes_agent_loop_subagent_units ]);
  exit (Suite_telemetry.exit_code self)
