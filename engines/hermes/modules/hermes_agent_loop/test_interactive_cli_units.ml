(* Hand-written invariants over the interactive_cli units -- the backstop
   the parity fixtures cannot be. Every law carries a negative control
   where the gotcha has one. *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let () =
  (* ---- shared helpers ---- *)
  check (Interactive_cli_units.floored_mod (-1) 5 = 4)
    "SHARED floored_mod wraps -1 to the last index, not negative (C `mod` would give -1)";
  check (Interactive_cli_units.floored_mod 7 5 = 2) "SHARED floored_mod on a positive overflow";
  check (Interactive_cli_units.floored_mod 0 5 = 0) "CONTROL floored_mod at zero is zero";

  check (Interactive_cli_units.python_int_of_string "10" = Some 10) "SHARED python_int_of_string plain digits";
  check (Interactive_cli_units.python_int_of_string "-5" = Some (-5)) "SHARED python_int_of_string a leading sign";
  check (Interactive_cli_units.python_int_of_string "1_0" = Some 10)
    "SHARED python_int_of_string accepts a digit-separating underscore";
  check
    (Interactive_cli_units.python_int_of_string "0x0A" = None)
    "SHARED python_int_of_string rejects a hex prefix (Python base-10 int() would too; OCaml int_of_string would not)";
  check (Interactive_cli_units.python_int_of_string "_1" = None) "CONTROL a leading underscore is invalid";
  check (Interactive_cli_units.python_int_of_string "1_" = None) "CONTROL a trailing underscore is invalid";
  check (Interactive_cli_units.python_int_of_string "1__0" = None) "CONTROL a doubled underscore is invalid";
  check (Interactive_cli_units.python_int_of_string " 7 " = Some 7) "SHARED python_int_of_string strips whitespace";
  check (Interactive_cli_units.python_int_of_string "" = None) "CONTROL an empty string is not an int";
  check (Interactive_cli_units.python_int_of_string "abc" = None) "CONTROL non-digits are not an int";

  check (Interactive_cli_units.py_capitalize "MyServer" = "Myserver")
    "SHARED py_capitalize lowers every char but the first (Python str.capitalize, not just-uppercase-first)";
  check (Interactive_cli_units.py_capitalize "" = "") "CONTROL py_capitalize on empty is empty";

  (* ---- repl_session ---- *)
  check (Interactive_cli_units.strip_ansi "plain text" = "plain text") "CONTROL strip_ansi is a no-op with no escape byte";
  check (Interactive_cli_units.strip_ansi "\x1b[31mred\x1b[0m" = "red") "REPL strip_ansi removes a complete SGR CSI pair";
  check
    (Interactive_cli_units.strip_ansi "\x1b]0;title\x07x" = "x")
    "REPL strip_ansi removes a BEL-terminated OSC sequence";
  check
    (Interactive_cli_units.strip_ansi "a\x1b\x01b" = "a\x1b\x01b")
    "REPL an ESC whose next byte matches none of CSI/OSC/DCS/nF/Fe (a control byte) stays in the output, backtrack exhausted";

  check
    (Interactive_cli_units.is_status_footer_rule (String.make 10 '-'))
    "REPL a long dash run is a footer rule";
  check
    (not (Interactive_cli_units.is_status_footer_rule "short"))
    "CONTROL a short line is never a footer rule (len < 8 guard)";
  check
    (not (Interactive_cli_units.is_status_footer_rule "12345678"))
    "CONTROL a non-dash 8+ char line is not a footer rule";

  let footer_text =
    "output line\n" ^ String.make 10 '-' ^ "\nRun 'hermes doctor' to check\nRun 'hermes setup' to configure\n"
  in
  check
    (Interactive_cli_units.strip_console_status_footer footer_text = "output line")
    "REPL strip_console_status_footer removes the doctor/setup pair and its rule line";
  check
    (Interactive_cli_units.strip_console_status_footer "just output\n" = "just output")
    "CONTROL text without the footer pattern is only rstripped";

  let sessions =
    [ `Assoc
        [ ("id", `String "abc123"); ("source", `String "cli"); ("message_count", `Int 4);
          ("title", `String "hello") ] ]
  in
  check (Interactive_cli_units.format_sessions [] = "No sessions found.") "CONTROL an empty session list";
  check
    (let out = Interactive_cli_units.format_sessions sessions in
     Interactive_cli_units.contains ~needle:"abc123" out && Interactive_cli_units.contains ~needle:"hello" out)
    "REPL format_sessions renders id and title";
  check
    (let long_id = String.make 40 'x' in
     let out =
       Interactive_cli_units.format_sessions
         [ `Assoc [ ("id", `String long_id); ("source", `Null); ("message_count", `Null); ("title", `Null) ] ]
     in
     Interactive_cli_units.contains ~needle:(String.sub long_id 0 32) out)
    "REPL format_sessions truncates id to 32 via explicit slice before padding";

  check (Interactive_cli_units.clean_summary None = "") "CONTROL clean_summary on None";
  check (Interactive_cli_units.clean_summary (Some "==SUPPRESS==") = "==SUPPRESS==")
    "REPL clean_summary echoes the sentinel's TEXT through unchanged -- `is argparse.SUPPRESS` is \
     identity-based and never fires for a plain string, measured directly against the reference \
     (cli.repl.clean_summary_suppress); a same-text guess would have been wrong (HZ-FIX-01 in miniature)";
  check
    (Interactive_cli_units.clean_summary (Some "  multi   space   text  ") = "multi space text")
    "REPL clean_summary collapses internal whitespace";
  check (Interactive_cli_units.clean_summary (Some "Run `hermes foo") = "")
    "REPL clean_summary blanks a 'Run `hermes ' prefixed summary";

  check
    (Interactive_cli_units.auto_provider_name "https://MyServer.com/v1" = "Myserver.com")
    "REPL auto_provider_name: capitalize() lowers the rest, not just uppercases the first char";
  check
    (Interactive_cli_units.auto_provider_name "http://localhost:8080" = "Local (localhost:8080)")
    "REPL auto_provider_name detects localhost";
  check
    (Interactive_cli_units.auto_provider_name "https://my-runpod-box.proxy.runpod.net"
    = "RunPod (my-runpod-box.proxy.runpod.net)")
    "REPL auto_provider_name detects runpod case-insensitively";

  (match Interactive_cli_units.parse_dashboard_runtime "hermes dashboard --port 9200 --host '[::1]'" with
  | Some (mode, host, port) ->
      check
        (mode = "dashboard" && host = "[::1]" && port = 9200)
        "REPL parse_dashboard_runtime strips only the quote char, not brackets (dashboard_probe_host is a separate function, not chained here)"
  | None -> check false "REPL parse_dashboard_runtime full match");
  check (Interactive_cli_units.parse_dashboard_runtime "hermes chat" = None)
    "CONTROL parse_dashboard_runtime on an unrelated command";
  check
    (Interactive_cli_units.dashboard_probe_host (Some "]]::1[[") = "::1")
    "REPL dashboard_probe_host strips bracket CHARACTERS, not a matched pair";
  check (Interactive_cli_units.dashboard_probe_host (Some "0.0.0.0") = "127.0.0.1")
    "REPL dashboard_probe_host maps the wildcard bind address to loopback";
  check (Interactive_cli_units.dashboard_probe_host None = "127.0.0.1") "CONTROL dashboard_probe_host default";

  check
    (Interactive_cli_units.coalesce_session_name_args [ "-c"; "my"; "session"; "name"; "chat" ]
    = [ "-c"; "my session name"; "chat" ])
    "REPL coalesce_session_name_args joins tokens after -c, stopping at a subcommand";
  check
    (Interactive_cli_units.coalesce_session_name_args [ "chat"; "-c" ] = [ "chat"; "-c" ])
    "CONTROL coalesce_session_name_args with nothing following the flag";

  (* ---- slash_commands ---- *)
  check (Interactive_cli_units.sanitize_telegram_name "My-Bot__Name!!" = "my_bot_name")
    "SLASH sanitize_telegram_name: hyphen->underscore BEFORE the invalid-char strip, then collapse+edge-strip";
  check (Interactive_cli_units.sanitize_slack_name "My-Bot Name!" = "my-botname")
    "SLASH sanitize_slack_name keeps hyphens (no -> _ rewrite) and drops the space+bang";

  let reserved = [ "cmd" ] in
  let long_name = String.make 40 'a' in
  check
    (Interactive_cli_units.clamp_command_names [ (long_name, "d") ] reserved
    = [ (String.sub long_name 0 32, "d") ])
    "SLASH clamp_command_names truncates an over-limit name to 32";
  let clash = String.sub long_name 0 32 in
  check
    (match Interactive_cli_units.clamp_command_names [ (long_name, "d") ] [ clash ] with
     | [ (name, _) ] -> name = String.sub long_name 0 31 ^ "0"
     | _ -> false)
    "SLASH clamp_command_names appends a free digit when the truncated name collides";
  let all_ten_taken = clash :: List.init 10 (fun d -> String.sub long_name 0 31 ^ string_of_int d) in
  check
    (Interactive_cli_units.clamp_command_names [ (long_name, "d") ] all_ten_taken = [])
    "REPL for-else: when all 10 digit suffixes are taken, the entry is skipped, not force-added (mis-port trap)";

  check
    (Interactive_cli_units.nested_mapping (`Assoc [ ("a", `Assoc [ ("b", `Assoc [ ("c", `Int 1) ]) ]) ]) [ "a"; "b" ]
    = `Assoc [ ("c", `Int 1) ])
    "SLASH nested_mapping walks present nested keys";
  check
    (Interactive_cli_units.nested_mapping (`Assoc [ ("a", `Int 1) ]) [ "a"; "b" ] = `Assoc [])
    "CONTROL nested_mapping returns {} when an intermediate node is not a mapping";

  check (Interactive_cli_units.completion_clean "it's a \"test\"\\!" = "its a test!")
    "SLASH completion_clean strips quote and backslash characters";
  check (String.length (Interactive_cli_units.completion_clean (String.make 100 'x')) = 60)
    "SLASH completion_clean truncates to maxlen 60";

  (* ---- terminal_ui ---- *)
  check (Interactive_cli_units.is_boundary "x" 0) "CONTROL index 0 is always a boundary";
  check (Interactive_cli_units.is_boundary "a-b" 2) "TUI a char after a word-boundary char is a boundary";
  check (Interactive_cli_units.is_boundary "myFile" 2) "TUI a camelCase transition (y->F) is a boundary";
  check (not (Interactive_cli_units.is_boundary "abc" 1)) "CONTROL a mid-lowercase-run position is not a boundary";

  check
    (match Interactive_cli_units.fuzzy_score ~label:"skill_units.ml" ~query:"skill" with
     | Some prefix_score -> (
         match Interactive_cli_units.fuzzy_score ~label:"my_skill_file.ml" ~query:"skill" with
         | Some scattered_score -> prefix_score > scattered_score
         | None -> false)
     | None -> false)
    "TUI fuzzy_score ranks a prefix match above the same token found mid-string";
  check (Interactive_cli_units.fuzzy_score ~label:"abc" ~query:"xyz" = None) "CONTROL no match returns None";
  check (Interactive_cli_units.fuzzy_score ~label:"anything" ~query:"" = Some 0.0) "CONTROL an empty query scores 0.0";

  check
    (Interactive_cli_units.filter_indices [ "a"; "b"; "c" ] "" = [ 0; 1; 2 ])
    "CONTROL filter_indices with a blank query returns every index in order";
  check
    (Interactive_cli_units.filter_indices [ "skillet"; "skill"; "other" ] "skill" = [ 1; 0 ])
    "TUI filter_indices ranks the exact/prefix match above the longer partial match";

  check
    (Interactive_cli_units.move_filtered_cursor [ 10; 20; 30 ] 10 0 (-1) = 30)
    "TUI move_filtered_cursor: delta -1 from position 0 wraps to the LAST index via floored modulo";
  check
    (Interactive_cli_units.move_filtered_cursor [ 10; 20; 30 ] 10 0 1 = 20)
    "CONTROL move_filtered_cursor: a forward step is unaffected by the modulo direction";
  check (Interactive_cli_units.reconcile_cursor [] 5 = (5, 0)) "CONTROL reconcile_cursor with nothing filtered";
  check
    (Interactive_cli_units.reconcile_cursor [ 10; 20 ] 99 = (10, 0))
    "TUI reconcile_cursor snaps a cursor not present in filtered to the first entry";
  check
    (Interactive_cli_units.scroll_for_cursor ~scroll_offset:0 ~cursor_pos:9 ~visible_rows:5 ~total_rows:20 = 5)
    "TUI scroll_for_cursor advances the offset when the cursor scrolls past the visible window";
  check
    (Interactive_cli_units.scroll_for_cursor ~scroll_offset:10 ~cursor_pos:2 ~visible_rows:5 ~total_rows:20 = 2)
    "TUI scroll_for_cursor retreats the offset when the cursor moves above it";

  check (Interactive_cli_units.radio_item_plain (`String "plain") = "plain") "CONTROL radio_item_plain on a bare string";
  check
    (Interactive_cli_units.radio_item_plain (`List [ `List [ `String "a"; `String "bold" ]; `List [ `String "b" ] ])
    = "ab")
    "TUI radio_item_plain joins the text half of each (text, style) pair";

  (* ---- approval_prompts ---- *)
  check (Interactive_cli_units.has_allowlist_shell_operator "echo hi && rm -rf /") "APPROVAL detects &&";
  check (not (Interactive_cli_units.has_allowlist_shell_operator "echo hello world")) "CONTROL plain command, no operator";
  check (Interactive_cli_units.unsafe_root_binary "/usr/bin/rm") "APPROVAL unsafe_root_binary resolves the last path segment";
  check (Interactive_cli_units.unsafe_root_binary "mkfs.ext4") "APPROVAL unsafe_root_binary matches an mkfs prefix";
  check (not (Interactive_cli_units.unsafe_root_binary "ls")) "CONTROL a safe binary";

  check (Interactive_cli_units.derive_glob "git status" = Some "git status *")
    "APPROVAL derive_glob: a plain second token is echoed, with a trailing wildcard always appended";
  check (Interactive_cli_units.derive_glob "git -c foo status" = Some "git *")
    "APPROVAL derive_glob: a flag-shaped second token drops the rest to a single wildcard";
  check (Interactive_cli_units.derive_glob "ls" = Some "ls") "CONTROL derive_glob on a single token";
  check (Interactive_cli_units.derive_glob "echo hi && rm -rf /" = None)
    "CONTROL derive_glob refuses a command containing a shell operator";
  check (Interactive_cli_units.derive_glob "rm -rf /" = None) "CONTROL derive_glob refuses an unsafe root binary";

  check (Interactive_cli_units.parse_apply_indices ~spec:"1,3,1" ~total:5 = Ok [ 0; 2 ])
    "APPROVAL parse_apply_indices dedups and converts to zero-based";
  check
    (match Interactive_cli_units.parse_apply_indices ~spec:"abc" ~total:5 with
     | Error msg -> Interactive_cli_units.contains ~needle:"'abc'" msg
     | Ok _ -> false)
    "APPROVAL parse_apply_indices quotes the bad token with Python repr (!r), single-quoted";
  check
    (match Interactive_cli_units.parse_apply_indices ~spec:"9" ~total:3 with Error _ -> true | Ok _ -> false)
    "CONTROL parse_apply_indices rejects an out-of-range selection";
  check
    (match Interactive_cli_units.parse_apply_indices ~spec:"" ~total:3 with Error _ -> true | Ok _ -> false)
    "CONTROL parse_apply_indices with no valid selections";

  check (Interactive_cli_units.is_unsafe_class "recursive DELETE of files") "APPROVAL is_unsafe_class is case-insensitive";
  check (Interactive_cli_units.is_unsafe_class "run rm on the target") "APPROVAL is_unsafe_class matches a standalone word";
  check
    (not (Interactive_cli_units.is_unsafe_class "check the disketted drive"))
    "CONTROL is_unsafe_class: \\b word boundary does not fire inside a longer word";
  check (not (Interactive_cli_units.is_unsafe_class "farm animals")) "CONTROL 'rm' inside 'farm' is not a boundary match";

  (* ---- shell_passthrough ---- *)
  check (Interactive_cli_units.is_bang_command (`String "!ls -la")) "BANG is_bang_command on a bang-prefixed string";
  check (not (Interactive_cli_units.is_bang_command (`String "ls -la"))) "CONTROL a non-bang string";
  check (not (Interactive_cli_units.is_bang_command (`Int 5))) "CONTROL a non-string JSON value is never a bang command";
  check (Interactive_cli_units.parse_bang_command (`String "  !ls -la  ") = "ls -la")
    "BANG parse_bang_command strips surrounding whitespace on both sides of the bang";
  check (Interactive_cli_units.parse_bang_command (`String "ls -la") = "") "CONTROL parse_bang_command on a non-bang string";

  check (Interactive_cli_units.is_remote_shell_session [ ("SSH_CONNECTION", "1.2.3.4 22 5.6.7.8 22") ])
    "BANG is_remote_shell_session detects SSH_CONNECTION";
  check (not (Interactive_cli_units.is_remote_shell_session [])) "CONTROL an empty env is not a remote session";

  check
    (Interactive_cli_units.powershell_write_script "QUJD"
    = "Set-Clipboard -Value ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('QUJD')))")
    "BANG powershell_write_script produces the exact template";

  Printf.printf "interactive_cli units: %d passed, %d failed\n" !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_interactive_cli_units" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_interactive_cli_units ]);
  exit (Suite_telemetry.exit_code self)
