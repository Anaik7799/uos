type toml_value =
  | String_value of string
  | Bool_value of bool

let failures = ref 0
let passes = ref 0

let check name f =
  match f () with
  | true ->
      incr passes;
      Printf.printf "PASS %s\n" name
  | false ->
      incr failures;
      Printf.printf "FAIL %s\n" name
  | exception exn ->
      incr failures;
      Printf.printf "FAIL %s (%s)\n" name (Printexc.to_string exn)

let read_lines path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      let rec loop acc =
        match input_line ic with
        | line -> loop (line :: acc)
        | exception End_of_file -> List.rev acc
      in
      loop [])

let read_file path = String.concat "\n" (read_lines path)

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec search offset =
    offset + needle_length <= haystack_length
    &&
    (String.sub haystack offset needle_length = needle
    || search (offset + 1))
  in
  needle_length > 0 && search 0

let split_once character value =
  match String.index_opt value character with
  | None -> None
  | Some index ->
      Some
        ( String.sub value 0 index,
          String.sub value (index + 1) (String.length value - index - 1) )

let strip_suffix suffix value =
  let suffix_length = String.length suffix in
  let value_length = String.length value in
  if value_length >= suffix_length
     && String.sub value (value_length - suffix_length) suffix_length = suffix
  then Some (String.sub value 0 (value_length - suffix_length))
  else None

let regular_file path =
  Sys.file_exists path && not (Sys.is_directory path)

let symlink_resolves_to link target =
  let stats = Unix.lstat link in
  stats.Unix.st_kind = Unix.S_LNK
  && Unix.realpath link = Unix.realpath target

let resolves_same left right =
  Sys.file_exists left && Sys.file_exists right
  && Unix.realpath left = Unix.realpath right

let names_with_file ~root ~relative =
  match Sys.readdir root with
  | exception Sys_error _ -> []
  | names ->
      names |> Array.to_list
      |> List.filter (fun name ->
             regular_file (Filename.concat (Filename.concat root name) relative))
      |> List.sort_uniq compare

let names_with_suffix ~root ~suffix =
  match Sys.readdir root with
  | exception Sys_error _ -> []
  | names ->
      names |> Array.to_list |> List.filter_map (strip_suffix suffix)
      |> List.sort_uniq compare

let unescape_basic_string value =
  let length = String.length value in
  if length < 2 || value.[0] <> '"' || value.[length - 1] <> '"' then
    invalid_arg ("not a TOML basic string: " ^ value);
  let buffer = Buffer.create length in
  let rec loop index =
    if index >= length - 1 then Buffer.contents buffer
    else if value.[index] <> '\\' then (
      Buffer.add_char buffer value.[index];
      loop (index + 1))
    else if index + 1 >= length - 1 then
      invalid_arg "unterminated TOML escape"
    else
      let decoded =
        match value.[index + 1] with
        | '"' -> '"'
        | '\\' -> '\\'
        | 'n' -> '\n'
        | 'r' -> '\r'
        | 't' -> '\t'
        | other -> other
      in
      Buffer.add_char buffer decoded;
      loop (index + 2)
  in
  loop 1

let parse_toml path =
  let values = Hashtbl.create 16 in
  let section = ref "" in
  let multiline = ref None in
  let add key value =
    if Hashtbl.mem values key then invalid_arg ("duplicate TOML key: " ^ key);
    Hashtbl.add values key value
  in
  let qualified key =
    if !section = "" then key else !section ^ "." ^ key
  in
  List.iter
    (fun raw_line ->
      let line = String.trim raw_line in
      match !multiline with
      | Some (key, reversed_lines) ->
          if line = "\"\"\"" then (
            add key
              (String_value (String.concat "\n" (List.rev reversed_lines)));
            multiline := None)
          else multiline := Some (key, raw_line :: reversed_lines)
      | None ->
          if line = "" || line.[0] = '#' then ()
          else if line.[0] = '[' && line.[String.length line - 1] = ']' then
            section :=
              String.sub line 1 (String.length line - 2) |> String.trim
          else
            match split_once '=' line with
            | None -> invalid_arg ("unsupported TOML line: " ^ line)
            | Some (raw_key, raw_value) ->
                let key = qualified (String.trim raw_key) in
                let raw_value = String.trim raw_value in
                if raw_value = "\"\"\"" then multiline := Some (key, [])
                else if raw_value = "true" then add key (Bool_value true)
                else if raw_value = "false" then add key (Bool_value false)
                else add key (String_value (unescape_basic_string raw_value)))
    (read_lines path);
  (match !multiline with
  | None -> ()
  | Some (key, _) -> invalid_arg ("unterminated TOML multiline key: " ^ key));
  values

let toml_string values key =
  match Hashtbl.find_opt values key with
  | Some (String_value value) -> value
  | Some (Bool_value _) -> invalid_arg ("TOML key is not a string: " ^ key)
  | None -> invalid_arg ("missing TOML key: " ^ key)

let toml_bool values key =
  match Hashtbl.find_opt values key with
  | Some (Bool_value value) -> value
  | Some (String_value _) -> invalid_arg ("TOML key is not a boolean: " ^ key)
  | None -> invalid_arg ("missing TOML key: " ^ key)

let parse_frontmatter path =
  let lines = read_lines path in
  match lines with
  | "---" :: rest ->
      let fields = Hashtbl.create 8 in
      let rec collect = function
        | [] -> invalid_arg ("unterminated frontmatter: " ^ path)
        | "---" :: _ -> fields
        | line :: tail ->
            (match split_once ':' line with
            | None -> ()
            | Some (key, value) ->
                Hashtbl.replace fields (String.trim key) (String.trim value));
            collect tail
      in
      collect rest
  | _ -> invalid_arg ("missing frontmatter: " ^ path)

let frontmatter fields key =
  match Hashtbl.find_opt fields key with
  | Some value when value <> "" -> value
  | _ -> invalid_arg ("missing frontmatter key: " ^ key)

let body_after_frontmatter path =
  match read_lines path with
  | "---" :: rest ->
      let rec drop = function
        | [] -> invalid_arg ("unterminated frontmatter: " ^ path)
        | "---" :: body -> String.concat "\n" body |> String.trim
        | _ :: tail -> drop tail
      in
      drop rest
  | _ -> invalid_arg ("missing frontmatter: " ^ path)

let hook_command document event =
  let open Yojson.Safe.Util in
  let groups = document |> member "hooks" |> member event |> to_list in
  let group = List.hd groups in
  let handlers = group |> member "hooks" |> to_list in
  List.hd handlers |> member "command" |> to_string

let hook_timeout_ms document event =
  let open Yojson.Safe.Util in
  let groups = document |> member "hooks" |> member event |> to_list in
  let group = List.hd groups in
  let handlers = group |> member "hooks" |> to_list in
  List.hd handlers |> member "timeout" |> to_int

let object_has_only_key expected = function
  | `Assoc [ (actual, _) ] -> String.equal actual expected
  | _ -> false

let agy_hook_command document =
  let open Yojson.Safe.Util in
  document |> member "host-clock" |> member "PreInvocation" |> to_list
  |> List.hd |> member "command" |> to_string

let agy_hook_timeout document =
  let open Yojson.Safe.Util in
  document |> member "host-clock" |> member "PreInvocation" |> to_list
  |> List.hd |> member "timeout" |> to_int

let expected_agy_hook =
  "opam exec --switch=/home/an/dev/ver/zigvm -- dune exec --root "
  ^ "/home/an/dev/ver/harness-bionic "
  ^ "modules/system_engg/run_agent_time_hook.exe"

let claude_agent_names () = names_with_suffix ~root:".claude/agents" ~suffix:".md"
let codex_agent_names () = names_with_suffix ~root:".codex/agents" ~suffix:".toml"
let agy_agent_names () = names_with_file ~root:".agents/agents" ~relative:"agent.md"

let user_skill_names root = names_with_file ~root ~relative:"SKILL.md"

let () =
  check "canonical AGENTS.md exists" (fun () -> regular_file "AGENTS.md");
  check "CLAUDE.md resolves to AGENTS.md" (fun () ->
      symlink_resolves_to "CLAUDE.md" "AGENTS.md");
  check "CODEX.md resolves to AGENTS.md" (fun () ->
      symlink_resolves_to "CODEX.md" "AGENTS.md");
  check "GEMINI.md resolves to AGENTS.md" (fun () ->
      symlink_resolves_to "GEMINI.md" "AGENTS.md");
  check "shared instructions route to mandatory rules and handover" (fun () ->
      let body = read_file "AGENTS.md" in
      contains body "docs/hermes/mandatory-rules.md"
      && contains body "docs/hermes/HANDOVER.md"
      && contains body ".claude/skills"
      && contains body ".codex/agents");
  check "AGY and Gemini repository skills are one exact tree" (fun () ->
      symlink_resolves_to ".agents/skills" ".claude/skills");
  check "Claude, Codex, and Agy agent denominators are identical" (fun () ->
      let expected = claude_agent_names () in
      expected <> [] && codex_agent_names () = expected
      && agy_agent_names () = expected);
  check "every Agy agent preserves Claude identity and system prompt" (fun () ->
      claude_agent_names ()
      |> List.for_all (fun name ->
             let source_path = Filename.concat ".claude/agents" (name ^ ".md") in
             let agy_path =
               Filename.concat (Filename.concat ".agents/agents" name) "agent.md"
             in
             let source = parse_frontmatter source_path in
             let projection = parse_frontmatter agy_path in
             frontmatter source "name" = frontmatter projection "name"
             && frontmatter source "description"
                = frontmatter projection "description"
             && body_after_frontmatter source_path
                = body_after_frontmatter agy_path));
  check "Agy agent projections use bounded native policy" (fun () ->
      claude_agent_names ()
      |> List.for_all (fun name ->
             let path =
               Filename.concat (Filename.concat ".agents/agents" name) "agent.md"
             in
             let body = read_file path in
             List.for_all (contains body)
               [ "mainAgent: true"; "subagent: true"; "model: inherit";
                 "commandExecutionPolicy: sandbox"; "- view_file";
                 "- grep_search"; "- run_command" ]));
  check "Agy wiki auditor exposes no file-write tool" (fun () ->
      let body = read_file ".agents/agents/wiki-auditor/agent.md" in
      not (contains body "replace_file_content")
      && not (contains body "write_to_file"));
  check "wiki auditor selector and posture are preserved" (fun () ->
      let source = parse_frontmatter ".claude/agents/wiki-auditor.md" in
      let adapter = parse_toml ".codex/agents/wiki-auditor.toml" in
      let instructions = toml_string adapter "developer_instructions" in
      frontmatter source "name" = toml_string adapter "name"
      && frontmatter source "description" = toml_string adapter "description"
      && toml_string adapter "sandbox_mode" = "read-only"
      && List.for_all (contains instructions)
           [ "--pin";
             "--apply";
             "Git mutations";
             "wiki_audit.exe";
             "wiki_dashboard.exe";
             "fractal.level";
             "fractal.origin";
             "never deny parity credit" ]);
  check "debugging supervisor selector and read-only posture are preserved" (fun () ->
      let source =
        parse_frontmatter ".claude/agents/hermes-debugging-supervisor.md"
      in
      let adapter =
        parse_toml ".codex/agents/hermes-debugging-supervisor.toml"
      in
      let instructions = toml_string adapter "developer_instructions" in
      let agy =
        read_file ".agents/agents/hermes-debugging-supervisor/agent.md"
      in
      frontmatter source "name" = toml_string adapter "name"
      && frontmatter source "description" = toml_string adapter "description"
      && toml_string adapter "sandbox_mode" = "read-only"
      && not (contains agy "replace_file_content")
      && not (contains agy "write_to_file")
      && List.for_all (contains instructions)
           [ "Debug_intent"; "Debug_protocol"; "discriminating measurement";
             "Run_swarm_bridge"; "Implementation-origin L4-L6";
             "Never call raw SOP execution" ]);
  check "completion supervisor selector and bounded write posture are preserved" (fun () ->
      let source = parse_frontmatter ".claude/agents/hermes-completion-supervisor.md" in
      let adapter = parse_toml ".codex/agents/hermes-completion-supervisor.toml" in
      let instructions = toml_string adapter "developer_instructions" in
      frontmatter source "name" = toml_string adapter "name"
      && frontmatter source "description" = toml_string adapter "description"
      && toml_string adapter "sandbox_mode" = "workspace-write"
      && List.for_all (contains instructions)
           [ "Ops_capability";
             "Ops_command";
             "Ops_governance";
             "Sop_execution";
             "OCaml API, CLI, MCP, and Zenoh";
             "Observe, Orient, Decide, Act, closing Observe";
             "SysML";
             "OpenMBEE MMS";
             "STPA and FMEA";
             "Verified, Partial, or Unavailable_observed";
             "Only accepted L4-L6 differential evidence grants parity" ]);
  check "full symbiosis selector and privacy posture are preserved" (fun () ->
      let source = parse_frontmatter ".claude/agents/full-symbiosis-supervisor.md" in
      let adapter = parse_toml ".codex/agents/full-symbiosis-supervisor.toml" in
      let instructions = toml_string adapter "developer_instructions" in
      frontmatter source "name" = toml_string adapter "name"
      && frontmatter source "description" = toml_string adapter "description"
      && toml_string adapter "sandbox_mode" = "workspace-write"
      && List.for_all (contains instructions)
           [ "Ops_capability"; "native adapters"; "bounded OCaml executables";
             "governed Swarm boundary"; "credentials"; "permission grants";
             "Verified, Partial, or Unavailable_observed" ]);
  check "Codex lifecycle hooks preserve Claude modes" (fun () ->
      let document = Yojson.Safe.from_file ".codex/hooks.json" in
      hook_command document "SessionStart"
      = "bash /home/an/.claude/hooks/claude-time-sync.sh session"
      && hook_command document "UserPromptSubmit"
         = "bash /home/an/.claude/hooks/claude-time-sync.sh prompt");
  check "Gemini lifecycle hooks preserve Claude modes natively" (fun () ->
      let document = Yojson.Safe.from_file ".gemini/settings.json" in
      object_has_only_key "hooks" document
      && hook_command document "SessionStart"
         = "bash /home/an/.claude/hooks/claude-time-sync.sh session"
      && hook_command document "BeforeAgent"
         = "bash /home/an/.claude/hooks/claude-time-sync.sh prompt");
  check "Gemini lifecycle hooks preserve the five-second timeout" (fun () ->
      let document = Yojson.Safe.from_file ".gemini/settings.json" in
      hook_timeout_ms document "SessionStart" = 5_000
      && hook_timeout_ms document "BeforeAgent" = 5_000);
  check "Agy lifecycle hook uses its native PreInvocation schema" (fun () ->
      let document = Yojson.Safe.from_file ".agents/hooks.json" in
      object_has_only_key "host-clock" document
      && agy_hook_command document = expected_agy_hook
      && agy_hook_timeout document = 10);
  check "Agy lifecycle adapter is repository-authored OCaml" (fun () ->
      regular_file "modules/system_engg/agent_time_hook.ml"
      && regular_file "modules/system_engg/run_agent_time_hook.ml"
      && not (Sys.file_exists ".agents/claude-time-sync.sh"));
  check "Codex project config enables hooks and agents" (fun () ->
      let config = parse_toml ".codex/config.toml" in
      toml_bool config "features.hooks" && toml_bool config "agents.enabled");
  check "Claude clock oracle remains executable" (fun () ->
      Unix.access "/home/an/.claude/hooks/claude-time-sync.sh" [ Unix.X_OK ];
      true);
  let claude_user_skills = user_skill_names "/home/an/.claude/skills" in
  let agy_user_skills = user_skill_names "/home/an/.agents/skills" in
  let gemini_user_skills = user_skill_names "/home/an/.gemini/config/skills" in
  check "Claude, Agy, and Gemini user-skill denominators are identical" (fun () ->
      claude_user_skills <> [] && agy_user_skills = claude_user_skills
      && gemini_user_skills = claude_user_skills
      && List.mem "full-symbiosis" claude_user_skills);
  List.iter
    (fun name ->
      check ("shared user skill carrier " ^ name) (fun () ->
          let claude = Filename.concat "/home/an/.claude/skills" name in
          let agy = Filename.concat "/home/an/.agents/skills" name in
          let gemini = Filename.concat "/home/an/.gemini/config/skills" name in
          resolves_same claude agy && resolves_same claude gemini))
    claude_user_skills;
  check "full-symbiosis user skill retains the Codex source carrier" (fun () ->
      let source = "/home/an/.codex/skills/full-symbiosis" in
      resolves_same source "/home/an/.claude/skills/full-symbiosis"
      && resolves_same source "/home/an/.agents/skills/full-symbiosis"
      && resolves_same source "/home/an/.gemini/config/skills/full-symbiosis");
  Printf.printf "agent_surface_sync: %d passed, %d failed\n" !passes !failures;
  if !failures > 0 then exit 1
