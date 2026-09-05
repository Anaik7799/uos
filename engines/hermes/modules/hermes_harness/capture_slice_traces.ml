(* Capture pinned traces for the four remaining agent_loop slices --
   prompt_assembly, context_engine, context_compression, turn_finalization --
   through one adapter that dispatches per declared unit. Offline: every
   measured unit is pure. Deliberate and explicit -- it writes evidence. *)

let git_revision root =
  let command = "git -C " ^ Filename.quote root ^ " rev-parse HEAD" in
  try
    let channel = Unix.open_process_in command in
    Fun.protect
      ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () -> Ok (String.trim (input_line channel)))
  with End_of_file -> Error "cannot determine reference revision"
     | Unix.Unix_error (_, _, message) -> Error message

let scenario_groups =
  [ Parity_compare.prompt_scenarios; Parity_compare.context_scenarios;
    Parity_compare.compress_scenarios; Parity_compare.finalize_scenarios;
    Parity_compare.redact_scenarios; Parity_compare.tool_scenarios;
    Parity_compare.context_file_scenarios; Parity_compare.memory_scenarios;
    Parity_compare.skill_scenarios; Parity_compare.cli_scenarios; Parity_compare.mcp_scenarios;
    Parity_compare.subagent_scenarios ]

let () =
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else "." in
  let reference_root = Bootstrap.reference_root root in
  match Inventory.scan ~root:reference_root with
  | Error message -> prerr_endline message; exit 1
  | Ok entries -> (
      let snapshot_digest = Inventory.snapshot_digest entries in
      match git_revision reference_root with
      | Error message -> prerr_endline message; exit 1
      | Ok reference_revision ->
          let normalizer = Parity_normalizer.default in
          Printf.printf "snapshot: %s\nreference: %s\n\n" snapshot_digest reference_revision;
          let failures = ref 0 in
          let total = ref 0 in
          List.iter
            (fun scenarios ->
              List.iter
                (fun (scenario_id, params_json) ->
                  incr total;
                  let params = match params_json with `Assoc fields -> fields | _ -> [] in
                  let scenario : Reference_capture.scenario =
                    { id = scenario_id; model = ""; messages = []; tools = None; params }
                  in
                  match
                    Reference_capture.capture
                      ~adapter_basename:"agent_loop_units_adapter.py" ~root ~snapshot_digest
                      ~reference_revision ~normalizer scenario
                  with
                  | Error failure ->
                      incr failures;
                      Printf.printf "  %-28s FAILED %s\n" scenario_id
                        (Reference_capture.describe failure)
                  | Ok capture ->
                      (match Reference_capture.save ~root capture with | Error refusal -> incr failures; Printf.printf "  REFUSED %s\n" refusal | Ok path ->
                      Printf.printf "  %-28s %s\n    %s\n" scenario_id capture.normalized_digest
                        (Filename.basename path)))
                scenarios)
            scenario_groups;
          Printf.printf "\ncaptured %d/%d slice scenarios\n" (!total - !failures) !total;
          if !failures > 0 then exit 1)
