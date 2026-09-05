(* Harness-controlled capture of frozen-reference traces into pinned fixtures.

   Scenarios are OCaml values, not a config file: they are part of the build,
   type-checked, and reviewable in the same place as everything else that
   decides what parity means.

   This is a deliberate, explicit step rather than part of `verify`. A capture
   writes new evidence, and evidence that appears as a side effect of a routine
   command is evidence nobody chose to trust. *)

let scenarios : Reference_capture.scenario list =
  [ { id = "chat.minimal"; model = "openai/gpt-5.4";
      messages = [ `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ];
      tools = None; params = [] };
    { id = "chat.system_prefix"; model = "openai/gpt-5.4";
      messages =
        [ `Assoc [ ("role", `String "system"); ("content", `String "be terse") ];
          `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ];
      tools = None; params = [] };
    { id = "chat.max_tokens"; model = "openai/gpt-5.4";
      messages = [ `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ];
      tools = None; params = [ ("max_tokens", `Int 256) ] };
    { id = "chat.anthropic_model"; model = "anthropic/claude-sonnet-4.5";
      messages = [ `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ];
      tools = None; params = [] };
    { id = "chat.with_tools"; model = "openai/gpt-5.4";
      messages = [ `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ];
      tools =
        Some
          (`List
            [ `Assoc
                [ ("type", `String "function");
                  ("function",
                   `Assoc
                     [ ("name", `String "lookup");
                       ("description", `String "look something up");
                       ("parameters", `Assoc [ ("type", `String "object") ]) ]) ] ]);
      params = [] };
    (* Broadening scenarios, all profile-independent so the generic reference is
       a fair oracle: message passthrough, the developer-role swap across model
       families, and multi-tool passthrough. Each was probed against the frozen
       reference before being added. *)
    { id = "chat.multi_turn"; model = "openai/gpt-5.4";
      messages =
        [ `Assoc [ ("role", `String "user"); ("content", `String "a") ];
          `Assoc [ ("role", `String "assistant"); ("content", `String "b") ];
          `Assoc [ ("role", `String "user"); ("content", `String "c") ] ];
      tools = None; params = [] };
    { id = "chat.codex_developer"; model = "openai/codex-mini";
      messages =
        [ `Assoc [ ("role", `String "system"); ("content", `String "s") ];
          `Assoc [ ("role", `String "user"); ("content", `String "u") ] ];
      tools = None; params = [] };
    { id = "chat.anthropic_system"; model = "anthropic/claude-sonnet-4.5";
      messages =
        [ `Assoc [ ("role", `String "system"); ("content", `String "s") ];
          `Assoc [ ("role", `String "user"); ("content", `String "u") ] ];
      tools = None; params = [] };
    { id = "chat.two_tools"; model = "openai/gpt-5.4";
      messages = [ `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ];
      tools =
        Some
          (`List
            [ `Assoc [ ("type", `String "function");
                       ("function", `Assoc [ ("name", `String "a") ]) ];
              `Assoc [ ("type", `String "function");
                       ("function", `Assoc [ ("name", `String "b") ]) ] ]);
      params = [] }

  ]

let git_revision root =
  let command = "git -C " ^ Filename.quote root ^ " rev-parse HEAD" in
  try
    let channel = Unix.open_process_in command in
    Fun.protect
      ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () -> Ok (String.trim (input_line channel)))
  with End_of_file -> Error "cannot determine reference revision"
     | Unix.Unix_error (_, _, message) -> Error message

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
          Printf.printf "snapshot: %s\nreference: %s\nnormalization: %s\n\n"
            snapshot_digest reference_revision
            (Parity_normalizer.describe normalizer);
          let failures = ref 0 in
          List.iter
            (fun (scenario : Reference_capture.scenario) ->
              match
                Reference_capture.capture ~root ~snapshot_digest ~reference_revision
                  ~normalizer scenario
              with
              | Error failure ->
                  incr failures;
                  Printf.printf "  %-24s FAILED %s\n" scenario.id
                    (Reference_capture.describe failure)
              | Ok capture ->
                  (match Reference_capture.save ~root capture with | Error refusal -> incr failures; Printf.printf "  REFUSED %s\n" refusal | Ok path ->
                  Printf.printf "  %-24s %s\n    %s\n" scenario.id
                    capture.normalized_digest
                    (Filename.basename path)))
            scenarios;
          Printf.printf "\ncaptured %d/%d scenarios\n"
            (List.length scenarios - !failures)
            (List.length scenarios);
          if !failures > 0 then exit 1)
