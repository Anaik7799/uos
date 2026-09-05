(* context_files units, reproduced faithfully from the frozen agent/
   coding_context.py, agent/subdirectory_hints.py, agent/context_breakdown.py
   and gateway/cwd_placeholder.py (each read completely before writing; parity
   is measured by the cfile.* scenarios, never assumed).

   Excluded, disclosed beside the scenarios: the workspace-detection branch of
   _detect_profile_name (git/marker/home stat calls) and the contextvars /
   filesystem paths of runtime_cwd.py -- impure resolution layers over the
   pure cores measured here. *)

let lower = String.lowercase_ascii

let contains ~needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec at i = i + n <= h && (String.sub haystack i n = needle || at (i + 1)) in
  n = 0 || at 0

(* ---- coding_context: edit-format family ---- *)

(* _EDIT_FORMAT_GUIDANCE, first match wins in declaration order. *)
let edit_format_guidance =
  [ ("patch", [ "gpt"; "codex" ],
     "- Edit format: author new files with `write_file`; for edits to existing \
      code use `patch` with `mode='patch'` (V4A diff) — including single-file \
      edits. It's the edit format you handle most reliably.");
    ("replace",
     [ "claude"; "sonnet"; "opus"; "haiku"; "gemini"; "gemma"; "deepseek"; "qwen";
       "kimi"; "glm"; "grok"; "hermes"; "llama"; "mistral"; "devstral"; "minimax" ],
     "- Edit format: author new files with `write_file`; for edits to existing \
      code prefer `patch` in `mode='replace'` — match a unique snippet and swap \
      it. Reach for `mode='patch'` (V4A) only when an edit genuinely spans \
      several files at once.") ]

let model_family model =
  match model with
  | "" -> None
  | model ->
      let lowered = lower model in
      List.find_map
        (fun (family, needles, _line) ->
          if List.exists (fun n -> contains ~needle:n lowered) needles then Some family
          else None)
        edit_format_guidance

let edit_format_line model =
  match model_family model with
  | None -> ""
  | Some family ->
      let _, _, line = List.find (fun (f, _, _) -> f = family) edit_format_guidance in
      line

(* _detect_profile_name, PURE branches only: off / on / non-interactive
   platform. auto|focus with an interactive platform runs the filesystem
   workspace probe and is out of scope. *)
let interactive_coding_platforms = [ "cli"; "tui"; "acp"; "desktop"; "" ]

let detect_profile_name_pure ~mode ~platform =
  if mode = "off" then Some "general"
  else if mode = "on" then Some "coding"
  else if
    platform <> ""
    && not (List.mem (lower (String.trim platform)) interactive_coding_platforms)
  then Some "general"
  else None (* the workspace-detection branch — out of the pure domain *)

(* ---- subdirectory_hints: pathlib relative_to semantics ---- *)

(* _is_ancestor_or_same: a is ancestor-or-same of b iff a's path components
   are a prefix of b's. Reproduces PurePosixPath.relative_to over "/"-split
   parts (leading "/" contributes the root part). *)
let path_parts p =
  let raw = String.split_on_char '/' p in
  let non_empty = List.filter (fun s -> s <> "") raw in
  if String.length p > 0 && p.[0] = '/' then "/" :: non_empty else non_empty

let is_ancestor_or_same a b =
  let pa = path_parts a and pb = path_parts b in
  let rec prefix xs ys =
    match (xs, ys) with
    | [], _ -> true
    | _, [] -> false
    | x :: xr, y :: yr -> x = y && prefix xr yr
  in
  prefix pa pb

(* ---- context_breakdown: token accounting and tool split ---- *)

let chars_to_tokens text = if text = "" then 0 else (String.length text + 3) / 4

let bytes_to_tokens = function None -> None | Some size -> Some ((size + 3) / 4)

(* json_tokens serializes with json.dumps DEFAULT separators (", " and ": "
   — with spaces), ensure_ascii=false, keys in insertion order. NOT compact:
   the harness caught a compact serializer here (18 chars vs 15 → 5 tokens
   vs 4). Scenario values are ASCII so byte length equals Python len. *)
let rec json_default (value : Yojson.Safe.t) : string =
  match value with
  | `Null -> "null"
  | `Bool b -> if b then "true" else "false"
  | `Int n -> string_of_int n
  | `Intlit s -> s
  | `Float f -> Yojson.Safe.to_string (`Float f)
  | `String s ->
      let b = Buffer.create (String.length s + 2) in
      Buffer.add_char b '"';
      String.iter
        (fun c ->
          match c with
          | '"' -> Buffer.add_string b "\\\""
          | '\\' -> Buffer.add_string b "\\\\"
          | '\n' -> Buffer.add_string b "\\n"
          | '\t' -> Buffer.add_string b "\\t"
          | '\r' -> Buffer.add_string b "\\r"
          | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
          | c -> Buffer.add_char b c)
        s;
      Buffer.add_char b '"';
      Buffer.contents b
  | `List items -> "[" ^ String.concat ", " (List.map json_default items) ^ "]"
  | `Assoc fields ->
      "{"
      ^ String.concat ", "
          (List.map (fun (k, v) -> json_default (`String k) ^ ": " ^ json_default v) fields)
      ^ "}"

(* Python `not value` is falsy for None/empty-string/empty-list/empty-dict/0. *)
let json_tokens value =
  let falsy =
    match value with
    | `Null | `String "" | `List [] | `Assoc [] | `Bool false | `Int 0 -> true
    | `Float f -> f = 0.0
    | _ -> false
  in
  if falsy then 0 else chars_to_tokens (json_default value)

let tool_name tool =
  match tool with
  | `Assoc _ -> (
      match (match tool with `Assoc f -> List.assoc_opt "function" f | _ -> None) with
      | Some (`Assoc fn) -> (
          match List.assoc_opt "name" fn with Some (`String n) -> n | _ -> "")
      | _ -> (
          match (match tool with `Assoc f -> List.assoc_opt "name" f | _ -> None) with
          | Some (`String n) -> n
          | _ -> ""))
  | _ -> ""

let subagent_tool_names = [ "delegate_task" ]

(* _split_tools returns (builtin, mcp, subagent) counts here (the shapes are
   preserved by the reference; counts suffice to prove the routing). *)
let split_tools tools =
  List.fold_left
    (fun (builtin, mcp, subagent) tool ->
      let name = tool_name tool in
      if String.length name >= 4 && String.sub name 0 4 = "mcp_" then
        (builtin, mcp + 1, subagent)
      else if List.mem name subagent_tool_names then (builtin, mcp, subagent + 1)
      else (builtin + 1, mcp, subagent))
    (0, 0, 0) tools

(* ---- cwd_placeholder: TERMINAL_CWD resolution ---- *)

let cwd_placeholders = [ "."; "auto"; "cwd" ]

let resolve_placeholder_terminal_cwd ~configured_cwd ~terminal_backend ~messaging_cwd
    ~docker_mount_cwd_to_workspace ~home_fallback =
  if configured_cwd <> "" && not (List.mem configured_cwd cwd_placeholders) then
    Some configured_cwd
  else begin
    let backend = lower (String.trim (if terminal_backend = "" then "local" else terminal_backend)) in
    if backend = "local" then begin
      let messaging = String.trim (Option.value messaging_cwd ~default:"") in
      Some (if messaging <> "" then messaging else home_fallback)
    end
    else if backend = "docker" && docker_mount_cwd_to_workspace then begin
      let messaging = String.trim (Option.value messaging_cwd ~default:"") in
      if messaging <> "" && not (List.mem messaging cwd_placeholders) then Some messaging
      else None
    end
    else None
  end
