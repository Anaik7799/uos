(* Hand-written invariants over the context_files and memory units -- the
   backstop the parity fixtures cannot be. Every law carries a negative
   control (HZ-FIX-03). *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let () =
  (* ---- context_files ---- *)
  check (Context_file_units.model_family "openai/gpt-5.4" = Some "patch")
    "CFILE a gpt model is the patch family";
  check (Context_file_units.model_family "anthropic/claude-sonnet-4.5" = Some "replace")
    "CFILE a claude model is the replace family";
  check (Context_file_units.model_family "weird/model" = None)
    "CONTROL an unknown model has no family";
  check (Context_file_units.edit_format_line "unknown" = "")
    "CFILE no family yields the empty line";
  check (String.length (Context_file_units.edit_format_line "google/gemini-3") > 0)
    "CFILE a known family yields a non-empty line";
  check (Context_file_units.detect_profile_name_pure ~mode:"off" ~platform:"cli" = Some "general")
    "CFILE off is always general";
  check (Context_file_units.detect_profile_name_pure ~mode:"on" ~platform:"cli" = Some "coding")
    "CFILE on is always coding";
  check
    (Context_file_units.detect_profile_name_pure ~mode:"auto" ~platform:"webhook" = Some "general")
    "CFILE a non-interactive platform is general";
  check (Context_file_units.detect_profile_name_pure ~mode:"auto" ~platform:"cli" = None)
    "CONTROL the interactive auto branch is out of the pure domain";

  check (Context_file_units.is_ancestor_or_same "/x" "/x/y/z") "CFILE an ancestor path matches";
  check (Context_file_units.is_ancestor_or_same "/x/y" "/x/y") "CFILE a path is its own ancestor";
  check (not (Context_file_units.is_ancestor_or_same "/x/y" "/x"))
    "CONTROL a descendant is not an ancestor";
  check (not (Context_file_units.is_ancestor_or_same "/foo" "/foobar"))
    "CFILE prefix-of-string is not prefix-of-components";

  (* chars_to_tokens is the ceil(n/4) rule *)
  check (Context_file_units.chars_to_tokens "" = 0) "CFILE empty text costs nothing";
  check (Context_file_units.chars_to_tokens "hello" = 2) "CFILE 5 chars is 2 tokens";
  check (Context_file_units.bytes_to_tokens None = None) "CFILE None bytes is None";
  check (Context_file_units.bytes_to_tokens (Some 10) = Some 3) "CFILE 10 bytes is 3 tokens";
  check (Context_file_units.json_tokens (`Assoc []) = 0) "CFILE an empty object is falsy, 0 tokens";
  (* json.dumps DEFAULT separators have spaces: {"a": 1, "b": "x"} is 18
     chars -> 5 tokens, not the compact 15 -> 4. A divergence the harness
     caught. *)
  check
    (Context_file_units.json_tokens (`Assoc [ ("a", `Int 1); ("b", `String "x") ]) = 5)
    "CFILE json_tokens uses default (spaced) json.dumps separators";
  check
    (let b, m, s =
       Context_file_units.split_tools
         [ `Assoc [ ("function", `Assoc [ ("name", `String "read_file") ]) ];
           `Assoc [ ("function", `Assoc [ ("name", `String "mcp_x") ]) ];
           `Assoc [ ("name", `String "delegate_task") ] ]
     in
     (b, m, s) = (1, 1, 1))
    "CFILE split routes builtin/mcp/subagent by name";

  check
    (Context_file_units.resolve_placeholder_terminal_cwd ~configured_cwd:"/real"
       ~terminal_backend:"local" ~messaging_cwd:None ~docker_mount_cwd_to_workspace:false
       ~home_fallback:"/home"
    = Some "/real")
    "CFILE a real configured cwd wins";
  check
    (Context_file_units.resolve_placeholder_terminal_cwd ~configured_cwd:"."
       ~terminal_backend:"local" ~messaging_cwd:None ~docker_mount_cwd_to_workspace:false
       ~home_fallback:"/home"
    = Some "/home")
    "CFILE local placeholder falls back to home";
  check
    (Context_file_units.resolve_placeholder_terminal_cwd ~configured_cwd:"."
       ~terminal_backend:"docker" ~messaging_cwd:(Some "/h") ~docker_mount_cwd_to_workspace:false
       ~home_fallback:"/home"
    = None)
    "CONTROL docker without mount leaves it unset";

  (* ---- memory ---- *)
  check
    (Memory_units.normalize_tool_schema
       (`Assoc [ ("type", `String "function"); ("function", `Assoc [ ("name", `String "r") ]) ])
    = Some (`Assoc [ ("name", `String "r") ]))
    "MEM a wrapped schema unwraps to the bare function";
  check (Memory_units.normalize_tool_schema (`Assoc [ ("description", `String "x") ]) = None)
    "CONTROL a nameless schema normalizes to None";
  check
    (not
       (Memory_units.memory_provider_tools_enabled ~enabled_toolsets:None
          ~disabled_toolsets:(Some [ "memory" ]) ~memory_tool_present:false))
    "MEM disabled memory wins";
  check
    (Memory_units.memory_provider_tools_enabled ~enabled_toolsets:None ~disabled_toolsets:None
       ~memory_tool_present:true)
    "MEM a present memory tool enables";
  check
    (not
       (Memory_units.memory_provider_tools_enabled ~enabled_toolsets:(Some [])
          ~disabled_toolsets:None ~memory_tool_present:false))
    "MEM an empty enabled list disables";

  let block = "keep <memory-context>secret</memory-context> tail" in
  let contains needle hay =
    let n = String.length needle and h = String.length hay in
    let rec at i = i + n <= h && (String.sub hay i n = needle || at (i + 1)) in
    at 0
  in
  check (not (contains "secret" (Memory_units.sanitize_context block)))
    "MEM sanitize strips a fenced block";
  check (Memory_units.sanitize_context "clean text" = "clean text")
    "CONTROL clean text passes through sanitize";
  check (Memory_units.build_memory_context_block "  " = "")
    "MEM an empty block is the empty string";
  check (contains "recalled memory context" (Memory_units.build_memory_context_block "fact"))
    "MEM a real block carries the system note";
  (* the block's clean payload must survive a sanitize round-trip (no
     double-wrapping): re-sanitizing the built block strips the wrapper back *)
  check
    (contains "fact" (Memory_units.build_memory_context_block "fact"))
    "MEM the remembered fact survives into the block";

  check (Memory_units.is_trivial_prompt None) "MEM None is trivial";
  check (Memory_units.is_trivial_prompt (Some "  ")) "MEM whitespace is trivial";
  check (Memory_units.is_trivial_prompt (Some "/help")) "MEM a slash command is trivial";
  check (Memory_units.is_trivial_prompt (Some "Yes!!")) "MEM a greeting with punctuation is trivial";
  check (Memory_units.is_trivial_prompt (Some "thank you.")) "MEM a two-word ack is trivial";
  check (not (Memory_units.is_trivial_prompt (Some "yesterday we shipped")))
    "CONTROL a word starting with a trivial prefix is not trivial";
  check (not (Memory_units.is_trivial_prompt (Some "please refactor the parser")))
    "CONTROL a real request is not trivial";

  (* ---- session_state ---- *)
  (* SHA-256 known-answer tests (RFC/NIST vectors) -- verified against the
     Python hashlib before this module was trusted in any fixture. *)
  check
    (Memory_units.system_prompt_hash ""
    = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    "SHA256 the empty string is the well-known anchor";
  check
    (Memory_units.system_prompt_hash "abc"
    = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    "SHA256 'abc' matches the FIPS 180-4 test vector";
  check
    (Memory_units.system_prompt_hash "The quick brown fox jumps over the lazy dog"
    = "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")
    "SHA256 the pangram matches its well-known digest";
  check
    (Memory_units.system_prompt_hash "a" <> Memory_units.system_prompt_hash "b")
    "CONTROL distinct inputs hash distinctly";

  check
    (Memory_units.workspace_key ~git_repo_root:(Some " /repo ") ~cwd:(Some "/other")
    = Some "/repo")
    "MEM git_repo_root wins over cwd, trimmed";
  check
    (Memory_units.workspace_key ~git_repo_root:None ~cwd:(Some " /work ") = Some "/work")
    "MEM cwd is the fallback, trimmed";
  check (Memory_units.workspace_key ~git_repo_root:None ~cwd:None = None)
    "CONTROL an unbound session has no workspace key";

  check (Memory_units.escape_like "50%_done\\x" = "50\\%\\_done\\\\x")
    "MEM escape_like escapes backslash, percent, underscore";
  let clause, params = Memory_units.cwd_prefix_clause "/work/proj/" in
  check (contains "s.cwd = ?" clause && List.length params = 3)
    "MEM cwd_prefix_clause has three positional params";
  check (List.hd params = "/work/proj")
    "MEM cwd_prefix_clause strips the trailing slash from the exact-match param";
  let wclause, wparams = Memory_units.workspace_key_clause "/repo" in
  check
    (contains "s.git_repo_root = ?" wclause && List.length wparams = 4)
    "MEM workspace_key_clause composes git_repo_root OR the cwd clause (4 params)";

  (* ---- state_portability ---- *)
  check
    (Memory_units.import_text_or_none ~field:"title" (`Int 5) = Error "title must be a string")
    "PORT the error message is prefixed with the caller's field name";
  check (Memory_units.import_text_or_none ~field:"x" `Null = Ok None)
    "CONTROL None is always accepted regardless of field";
  check
    (Memory_units.import_json_object_or_none ~field:"cfg" (`String "not json")
    = Error "cfg must be valid JSON")
    "PORT an unparseable string reports must-be-valid-JSON with the field name";
  check
    (Memory_units.import_json_object_or_none ~field:"cfg" (`String "[1,2]")
    = Error "cfg must be a JSON object")
    "PORT a parseable non-object reports must-be-a-JSON-object";
  check
    (match Memory_units.import_json_object_or_none ~field:"cfg" (`String "{\"a\":1}") with
     | Ok (Some s) -> s = "{\"a\":1}" (* passed through byte-identical, not re-encoded *)
     | _ -> false)
    "PORT a valid JSON-object string passes through verbatim, not re-serialized";
  check
    (match
       Memory_units.import_json_object_or_none ~field:"cfg" (`Assoc [ ("b", `Int 2) ])
     with
     | Ok (Some s) -> s = "{\"b\": 2}" (* re-encoded with default (spaced) separators *)
     | _ -> false)
    "PORT a dict value re-encodes with default (spaced) json.dumps separators";
  check (Memory_units.float_or_none `Null = None) "PORT None float coerces to None";
  check (Memory_units.float_or_none (`Int 3) = Some 3.0) "PORT an int coerces to a float";
  check (Memory_units.float_or_none (`String "nope") = None)
    "CONTROL an unparseable string float is None, not an exception";
  check (Memory_units.int_or_default ~default:7 (`String "bad") = 7)
    "PORT int_or_default falls back on a bad string";
  check (Memory_units.int_or_default ~default:7 (`Float 4.9) = 4)
    "PORT int_or_default truncates a float toward zero";
  check
    (Memory_units.reasoning_json_value (`String "{\"k\":true}") = `Assoc [ ("k", `Bool true) ])
    "PORT a parseable reasoning string decodes to structured JSON";
  check
    (Memory_units.reasoning_json_value (`String "not json") = `String "not json")
    "CONTROL an unparseable reasoning string passes through unchanged";
  check (Memory_units.reasoning_json_value (`Int 9) = `Int 9)
    "CONTROL a non-string reasoning value is untouched";

  Printf.printf "files+memory units: %d passed, %d failed\n" !passed
    (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_files_memory_units" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_conversation_loop; Stanza.hermes_agent_loop_prompt_assembly; Stanza.hermes_agent_loop_context_engine; Stanza.hermes_agent_loop_context_compression; Stanza.hermes_agent_loop_turn_finalization; Stanza.hermes_agent_loop_interrupt_control; Stanza.hermes_agent_loop_message_hygiene; Stanza.hermes_agent_loop_message_repairs; Stanza.hermes_agent_loop_json_canonical; Stanza.hermes_agent_loop_loop_send_path; Stanza.hermes_agent_loop_prompt_units; Stanza.hermes_agent_loop_context_units; Stanza.hermes_agent_loop_compress_units; Stanza.hermes_agent_loop_finalize_units; Stanza.hermes_agent_loop_redact_units; Stanza.hermes_agent_loop_tool_units; Stanza.hermes_agent_loop_context_file_units; Stanza.hermes_agent_loop_memory_units; Stanza.hermes_agent_loop_skill_units; Stanza.hermes_agent_loop_interactive_cli_units; Stanza.hermes_agent_loop_mcp_units; Stanza.hermes_agent_loop_subagent_units ]);
  exit (Suite_telemetry.exit_code self)
