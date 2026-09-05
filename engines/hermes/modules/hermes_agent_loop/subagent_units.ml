(* subagents units, reproduced faithfully from the frozen
   agent/subagent_lifecycle.py, tools/delegate_tool.py,
   agent/delegation_context.py, tools/async_delegation.py,
   tools/delegation_live_log.py, agent/moa_loop.py, agent/moa_trace.py,
   agent/message_content.py, hermes_cli/kanban_swarm.py and
   tools/kanban_tools.py (each read completely via a parallel survey of the
   whole family before writing a line of candidate code). Parity is
   measured by the subagents.* scenarios, never assumed.

   ASCII-scoped, matching this session's established convention: Python's
   str.lower/.strip/.split()/.splitlines()/.isalnum() are Unicode-aware
   (full Unicode whitespace/case/word tables, an 8-separator line-boundary
   set); the functions below use ASCII-only equivalents. Every len()/slice
   in the frozen source also counts Unicode CODE POINTS, not bytes; this
   candidate counts bytes. Divergence is possible only for non-ASCII input,
   which none of the fixtures exercise.

   Excluded, disclosed here rather than silently dropped:
     - Everything touching the live thread registry, futures, ContextVars,
       or *_SECRET (subagent_lifecycle.py's launch/status/wait/cancel/
       result/reconnect; delegation_context.py's is_delegated_child_context
       etc.); SubagentHandle.from_dict's own Python behavior (zero runtime
       type validation on a dataclass) is replicated only in the one
       dimension a statically-typed port CAN replicate -- key presence --
       not in "a wrongly-typed field is silently accepted", which has no
       meaningful OCaml analogue.
     - delegate_tool.py's TOOLSETS-registry-dependent family
       (_is_mcp_toolset_name, _expand_parent_toolsets, etc.) and
       _trim_summary_with_footer (its docstring claims "Deterministic." but
       it stamps datetime.now() and a machine path into its own output via
       a real filesystem write -- not reproducible).
     - _recover_tasks_from_json_string: its error path interpolates
       CPython's own json.JSONDecodeError message text verbatim, which no
       other JSON parser reproduces byte-for-byte; only the success path is
       portable and it is not a distinct enough candidate on its own.
     - async_delegation.py's claim_event_delivery (uuid4 + os.getpid),
       complete/release_event_delivery (thin SQL wrappers), and
       has_live_for_session (reads a live module-global dict under a lock).
     - moa_loop.py's _redact_reference_text (needs agent.redact, out of
       these anchor files) and _completed_response_as_stream_chunk (both
       its input and output are Python-runtime SDK objects, not plain
       data).
     - kanban_tools.py's env-reading predicates (_is_delegated_child_context
       and friends) -- real logic once the environment is threaded as an
       explicit parameter, but not as literally written.
     - _slot_reasoning_config / _aggregator_reasoning_config / _slot_runtime
       / _maybe_apply_moa_cache_control -- explicitly documented in the
       frozen source as doing real I/O (config reads, catalog resolution). *)

let lower = String.lowercase_ascii

let contains ~needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec at i = i + n <= h && (String.sub haystack i n = needle || at (i + 1)) in
  n = 0 || at 0

let starts_with prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

let ends_with suffix s =
  let sl = String.length suffix and n = String.length s in
  n >= sl && String.sub s (n - sl) sl = suffix

let ascii_ws = " \t\n\r\012\011"
let is_ws c = String.contains ascii_ws c

let strip_charset chars s =
  let is_in c = String.contains chars c in
  let n = String.length s in
  let i = ref 0 and j = ref (n - 1) in
  while !i < n && is_in s.[!i] do incr i done;
  while !j >= !i && is_in s.[!j] do decr j done;
  if !j < !i then "" else String.sub s !i (!j - !i + 1)

let rstrip_charset chars s =
  let is_in c = String.contains chars c in
  let n = String.length s in
  let j = ref (n - 1) in
  while !j >= 0 && is_in s.[!j] do decr j done;
  String.sub s 0 (!j + 1)

let strip s = strip_charset ascii_ws s
let rstrip s = rstrip_charset ascii_ws s

let lstrip s =
  let n = String.length s in
  let i = ref 0 in
  while !i < n && is_ws s.[!i] do incr i done;
  String.sub s !i (n - !i)

let is_alnum_underscore c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_'

let python_str = function
  | `String s -> s
  | `Bool true -> "True"
  | `Bool false -> "False"
  | `Null -> "None"
  | `Int n -> string_of_int n
  | other -> Yojson.Safe.to_string other

let json_truthy = function
  | `Null | `Bool false | `String "" | `List [] | `Assoc [] | `Int 0 -> false
  | `Float f -> f <> 0.0
  | _ -> true

let field_of (value : Yojson.Safe.t) key = match value with `Assoc fields -> List.assoc_opt key fields | _ -> None

(* Python's "MEDIA:"-style splitlines: this candidate splits on '\n' only,
   the common case for the message/log text this module handles; the other
   7 Unicode line separators are a disclosed gap. *)
let splitlines text = String.split_on_char '\n' text

(* order-preserving assoc "set": update value in place if the key already
   exists, append at the end if new -- mirrors Python's dict[key] = value /
   {**a, **b} merge semantics (load-bearing for merge_slot_extra_body). *)
let assoc_set key value fields =
  if List.mem_assoc key fields then List.map (fun (k, v) -> if k = key then (k, value) else (k, v)) fields
  else fields @ [ (key, value) ]

(* json.dumps(value, ensure_ascii=False) with DEFAULT (spaced) separators
   and NO key sorting -- the shape used by _stringify_tool_content and
   _render_tool_calls. *)
let json_spaced_unsorted (value : Yojson.Safe.t) : string =
  let buf = Buffer.create 256 in
  let quote s =
    Buffer.add_char buf '"';
    String.iter
      (fun c ->
        match c with
        | '"' -> Buffer.add_string buf "\\\""
        | '\\' -> Buffer.add_string buf "\\\\"
        | '\n' -> Buffer.add_string buf "\\n"
        | '\r' -> Buffer.add_string buf "\\r"
        | '\t' -> Buffer.add_string buf "\\t"
        | c when Char.code c < 0x20 -> Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
        | c -> Buffer.add_char buf c)
      s;
    Buffer.add_char buf '"'
  in
  let rec go = function
    | `Null -> Buffer.add_string buf "null"
    | `Bool b -> Buffer.add_string buf (if b then "true" else "false")
    | `Int n -> Buffer.add_string buf (string_of_int n)
    | `Float f -> Buffer.add_string buf (Printf.sprintf "%g" f)
    | `String s -> quote s
    | `List items ->
        Buffer.add_char buf '[';
        List.iteri (fun i v -> if i > 0 then Buffer.add_string buf ", "; go v) items;
        Buffer.add_char buf ']'
    | `Assoc fields ->
        Buffer.add_char buf '{';
        List.iteri
          (fun i (k, v) ->
            if i > 0 then Buffer.add_string buf ", ";
            quote k;
            Buffer.add_string buf ": ";
            go v)
          fields;
        Buffer.add_char buf '}'
    | other -> Buffer.add_string buf (Yojson.Safe.to_string other)
  in
  go value;
  Buffer.contents buf

(* json.dumps(value, sort_keys=True) -- DEFAULT (spaced) separators, default
   ensure_ascii=True. The ensure_ascii \uXXXX escaping of non-ASCII bytes is
   NOT implemented (disclosed, ASCII-scoped like the rest of this module);
   used only for a byte-length ceiling check where fixtures stay ASCII. *)
let json_sorted_spaced (value : Yojson.Safe.t) : string =
  let buf = Buffer.create 256 in
  let quote s =
    Buffer.add_char buf '"';
    String.iter
      (fun c ->
        match c with
        | '"' -> Buffer.add_string buf "\\\""
        | '\\' -> Buffer.add_string buf "\\\\"
        | '\n' -> Buffer.add_string buf "\\n"
        | '\r' -> Buffer.add_string buf "\\r"
        | '\t' -> Buffer.add_string buf "\\t"
        | c when Char.code c < 0x20 -> Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
        | c -> Buffer.add_char buf c)
      s;
    Buffer.add_char buf '"'
  in
  let rec go = function
    | `Null -> Buffer.add_string buf "null"
    | `Bool b -> Buffer.add_string buf (if b then "true" else "false")
    | `Int n -> Buffer.add_string buf (string_of_int n)
    | `Float f -> Buffer.add_string buf (Printf.sprintf "%g" f)
    | `String s -> quote s
    | `List items ->
        Buffer.add_char buf '[';
        List.iteri (fun i v -> if i > 0 then Buffer.add_string buf ", "; go v) items;
        Buffer.add_char buf ']'
    | `Assoc fields ->
        let sorted = List.sort (fun (a, _) (b, _) -> compare a b) fields in
        Buffer.add_char buf '{';
        List.iteri
          (fun i (k, v) ->
            if i > 0 then Buffer.add_string buf ", ";
            quote k;
            Buffer.add_string buf ": ";
            go v)
          sorted;
        Buffer.add_char buf '}'
    | other -> Buffer.add_string buf (Yojson.Safe.to_string other)
  in
  go value;
  Buffer.contents buf

let hex_to_bytes hex =
  let n = String.length hex / 2 in
  String.init n (fun i -> Char.chr (int_of_string ("0x" ^ String.sub hex (i * 2) 2)))

let sha256_bytes s = hex_to_bytes (Memory_units.Sha256.hex_digest s)

(* HMAC-SHA256, built on the existing from-scratch SHA-256 (Memory_units) --
   no HMAC primitive existed in this codebase yet. *)
let hmac_sha256_hex ~key ~message =
  let block_size = 64 in
  let key = if String.length key > block_size then sha256_bytes key else key in
  let key = key ^ String.make (block_size - String.length key) '\000' in
  let xor_pad pad = String.init block_size (fun i -> Char.chr (Char.code key.[i] lxor pad)) in
  let inner = sha256_bytes (xor_pad 0x36 ^ message) in
  Memory_units.Sha256.hex_digest (xor_pad 0x5c ^ inner)

(* ================================================================ *)
(* Slice: subagent_lifecycle (subagent_lifecycle.py)                 *)
(* ================================================================ *)

let subagent_handle_fields =
  [ "contract_version"; "subagent_id"; "parent_session_id"; "correlation_id"; "created_at"; "provider"; "model";
    "role"; "depth"; "capability" ]

(* Python's dataclass constructor, called via double-star dict unpacking,
   does ZERO runtime type validation (no __post_init__): a wrongly-typed
   but key-complete input
   succeeds silently. A statically-typed OCaml port cannot construct an
   ill-typed record in the first place, so this candidate replicates the
   ONE dimension it can: key completeness, not value typing -- any missing
   required key is the same "Malformed subagent handle." error; a present
   key's JSON value passes through unexamined, echoing the reference's own
   type-laxity as far as a JSON representation allows. *)
(* Python's dataclass constructor, called via double-star dict unpacking,
   rejects BOTH a missing required field (TypeError: missing argument) AND
   an unexpected key (TypeError: unexpected keyword argument) -- both are
   caught and rewrapped as the same "Malformed subagent handle." message,
   so an exact key-set match (not just superset) is required here too. *)
let subagent_handle_from_dict (value : Yojson.Safe.t) : (Yojson.Safe.t, string) result =
  match value with
  | `Assoc fields ->
      let given_keys = List.map fst fields in
      if
        List.for_all (fun key -> List.mem_assoc key fields) subagent_handle_fields
        && List.for_all (fun key -> List.mem key subagent_handle_fields) given_keys
      then Ok (`Assoc (List.map (fun key -> (key, List.assoc key fields)) subagent_handle_fields))
      else Error "Malformed subagent handle."
  | _ -> Error "Malformed subagent handle."

let subagent_handle_to_dict (handle : Yojson.Safe.t) : Yojson.Safe.t =
  match handle with
  | `Assoc fields -> `Assoc (List.filter_map (fun key -> Option.map (fun v -> (key, v)) (List.assoc_opt key fields)) subagent_handle_fields)
  | other -> other

let max_goal_chars = 16000
let max_context_chars = 32000
let max_metadata_bytes = 8192

let dedup xs = List.fold_left (fun acc x -> if List.mem x acc then acc else acc @ [ x ]) [] xs

let validate_request ~goal ~context ~role ~timeout_seconds ~working_directory ~blocked_tools ~metadata
    ~allowed_toolsets ~known_toolsets ~parent_enabled_toolsets : (unit, string) result =
  if strip goal = "" || String.length goal > max_goal_chars then
    Error "goal must be a non-empty string of at most 16000 characters."
  else if (match context with Some c -> String.length c > max_context_chars | None -> false) then
    Error "context must be a string of at most 32000 characters."
  else if role <> "leaf" && role <> "orchestrator" then Error "role must be 'leaf' or 'orchestrator'."
  else if timeout_seconds <> None then
    Error "Per-launch timeout is not supported; configure delegation timeout explicitly."
  else if working_directory <> None then
    Error "working_directory is not supported because Hermes delegates use isolated task environments."
  else if blocked_tools <> [] then
    Error "Per-tool blocking is not supported; use allowed_toolsets. Hermes always blocks unsafe child tools."
  else
    let metadata_bytes = String.length (json_sorted_spaced metadata) in
    if metadata_bytes > max_metadata_bytes then Error "metadata exceeds 8192 bytes."
    else (
      match allowed_toolsets with
      | [] -> Ok ()
      | allowed -> (
          let unknown = dedup (List.filter (fun t -> not (List.mem t known_toolsets)) allowed) in
          if unknown <> [] then
            Error (Printf.sprintf "Unknown toolsets: %s." (String.concat ", " (List.sort compare unknown)))
          else
            match parent_enabled_toolsets with
            | None -> Ok ()
            | Some enabled -> if List.for_all (fun t -> List.mem t enabled) allowed then Ok () else Error "Requested toolsets would broaden parent permissions."))

(* _SECRET is a fresh random 32 bytes generated once per process start in
   the frozen reference -- not reproducible from outside the live process.
   Reshaped to take the secret as an explicit parameter; the harness
   injects a fixed secret on both sides. *)
let capability ~secret ~subagent_id ~parent_session_id ~created_at =
  let value = Printf.sprintf "%s|%s|%.6f" subagent_id (Option.value parent_session_id ~default:"") created_at in
  hmac_sha256_hex ~key:secret ~message:value

(* ================================================================ *)
(* Slice: delegation (delegate_tool.py, delegation_context.py)       *)
(* ================================================================ *)

let build_child_system_prompt ~goal ~context ~workspace_path ~role ~max_spawn_depth ~child_depth =
  let parts = ref [ "You are a focused subagent working on a specific delegated task."; ""; Printf.sprintf "YOUR TASK:\n%s" goal ] in
  (match context with
  | Some c when strip c <> "" -> parts := !parts @ [ Printf.sprintf "\nCONTEXT:\n%s" c ]
  | _ -> ());
  (match workspace_path with
  | Some w when strip w <> "" ->
      parts :=
        !parts
        @ [ Printf.sprintf "\nWORKSPACE PATH:\n%s\nUse this exact path for local repository/workdir operations unless the task explicitly says otherwise." w ]
  | _ -> ());
  parts :=
    !parts
    @ [ "\nComplete this task using the tools available to you. When finished, provide a clear, concise summary of:\n\
         - What you did\n\
         - What you found or accomplished\n\
         - Any files you created or modified\n\
         - Any issues encountered\n\n\
         Important workspace rule: Never assume a repository lives at /workspace/... or any other container-style path unless the task/context explicitly gives that path. If no exact local path is provided, discover it first before issuing git/workdir-specific commands.\n\n\
         Keep your final summary tight: lead with outcomes, prefer bullet points over paragraphs, and don't replay your whole process. Your response is returned to the parent agent as a summary, and overlong summaries crowd out the parent's context window." ];
  if role = "orchestrator" then begin
    let child_note =
      if child_depth + 1 >= max_spawn_depth then
        "Your own children MUST be leaves (cannot delegate further) because they would be at the depth floor — you cannot pass role='orchestrator' to your own delegate_task calls."
      else
        "Your own children can themselves be orchestrators or leaves, depending on the `role` you pass to delegate_task. Default is 'leaf'; pass role='orchestrator' explicitly when a child needs to further decompose its work."
    in
    parts :=
      !parts
      @ [ Printf.sprintf
            "\n## Subagent Spawning (Orchestrator Role)\nYou have access to the `delegate_task` tool and CAN spawn your own subagents to parallelize independent work.\n\n\
             WHEN to delegate:\n\
             - The goal decomposes into 2+ independent subtasks that can run in parallel (e.g. research A and B simultaneously).\n\
             - A subtask is reasoning-heavy and would flood your context with intermediate data.\n\n\
             WHEN NOT to delegate:\n\
             - Single-step mechanical work — do it directly.\n\
             - Trivial tasks you can execute in one or two tool calls.\n\
             - Re-delegating your entire assigned goal to one worker (that's just pass-through with no value added).\n\n\
             Coordinate your workers' results and synthesize them before reporting back to your parent. You are responsible for the final summary, not your workers.\n\n\
             NOTE: You are at depth %d. The delegation tree is capped at max_spawn_depth=%d. %s"
            child_depth max_spawn_depth child_note ]
  end;
  String.concat "\n" !parts

let stringify_tool_content (content : Yojson.Safe.t) : string =
  match content with
  | `Null -> ""
  | `String s -> s
  | `List items ->
      let parts =
        List.map
          (function
            | `Assoc pf as item -> ( match List.assoc_opt "text" pf with Some (`String t) -> t | _ -> json_spaced_unsorted item)
            | other -> python_str other)
          items
      in
      String.concat "\n" parts
  | `Assoc _ as d -> json_spaced_unsorted d
  | other -> python_str other

let looks_like_error_output (content : string) : bool =
  if content = "" then false
  else
    let head = lstrip content in
    let json_hit =
      if starts_with "{" head || starts_with "[" head then (
        try
          match Yojson.Safe.from_string content with
          | `Assoc pf ->
              let error_truthy = match List.assoc_opt "error" pf with Some v -> json_truthy v | None -> false in
              if error_truthy then true
              else
                let status = lower (strip (match List.assoc_opt "status" pf with Some (`String s) -> s | _ -> "")) in
                List.mem status [ "error"; "failed"; "failure"; "timeout" ]
          | _ -> false
        with _ -> false)
      else false
    in
    if json_hit then true
    else
      let first = match splitlines content with l :: _ -> lower (strip l) | [] -> "" in
      starts_with "error:" first || starts_with "failed:" first || starts_with "traceback " first || starts_with "exception:" first

let extract_output_tail (result : Yojson.Safe.t) ~max_entries ~max_chars : Yojson.Safe.t list =
  match field_of result "messages" with
  | Some (`List messages) ->
      let pending_call_by_id = Hashtbl.create 16 in
      List.iter
        (function
          | `Assoc mf when List.assoc_opt "role" mf = Some (`String "assistant") ->
              let tool_calls = match List.assoc_opt "tool_calls" mf with Some (`List l) -> l | _ -> [] in
              List.iter
                (fun tc ->
                  let tc_id = match field_of tc "id" with Some (`String s) when s <> "" -> Some s | _ -> None in
                  let fn = match field_of tc "function" with Some (`Assoc _ as f) -> f | _ -> `Assoc [] in
                  let fn_name = match field_of fn "name" with Some (`String s) when s <> "" -> s | _ -> "tool" in
                  match tc_id with Some id -> Hashtbl.replace pending_call_by_id id fn_name | None -> ())
                tool_calls
          | _ -> ())
        messages;
      let tail = ref [] in
      (try
         List.iter
           (fun msg ->
             if List.length !tail >= max_entries then raise Exit;
             match msg with
             | `Assoc mf when List.assoc_opt "role" mf = Some (`String "tool") ->
                 let content_raw = Option.value (List.assoc_opt "content" mf) ~default:(`String "") in
                 let content = stringify_tool_content content_raw in
                 let is_error = looks_like_error_output content in
                 let tool_call_id = match List.assoc_opt "tool_call_id" mf with Some (`String s) when s <> "" -> s | _ -> "" in
                 let tool_name = Option.value (Hashtbl.find_opt pending_call_by_id tool_call_id) ~default:"tool" in
                 let preview = if String.length content > max_chars then String.sub content 0 max_chars else content in
                 tail := `Assoc [ ("tool", `String tool_name); ("preview", `String preview); ("is_error", `Bool is_error) ] :: !tail
             | _ -> ())
           (List.rev messages)
       with Exit -> ());
      !tail
  | _ -> []

let delegated_child_env_marker = "HERMES_DELEGATED_CHILD_CONTEXT"

let kanban_env_keys =
  [ "HERMES_KANBAN_TASK"; "HERMES_KANBAN_RUN_ID"; "HERMES_KANBAN_WORKSPACE"; "HERMES_KANBAN_WORKSPACES_ROOT";
    "HERMES_KANBAN_CLAIM_LOCK"; "HERMES_KANBAN_BOARD"; "HERMES_KANBAN_DB" ]

let scrub_kanban_env (env : (string * string) list) : (string * string) list =
  let cleaned = List.filter (fun (k, _) -> not (List.mem k kanban_env_keys)) env in
  assoc_set delegated_child_env_marker "1" cleaned

let normalize_role = function
  | None -> "leaf"
  | Some "" -> "leaf"
  | Some r ->
      let r_norm = lower (strip r) in
      if r_norm = "leaf" || r_norm = "orchestrator" then r_norm else "leaf"

let normalized_runtime_url value = rstrip_charset "/" (strip (Option.value value ~default:""))

let model_hidden_task_fields = [ "acp_command"; "acp_args" ]

let strip_model_hidden_task_fields (tasks : Yojson.Safe.t) : Yojson.Safe.t =
  match tasks with
  | `List items ->
      let changed = ref false in
      let stripped =
        List.map
          (function
            | `Assoc fields ->
                let kept = List.filter (fun (k, _) -> not (List.mem k model_hidden_task_fields)) fields in
                if List.length kept <> List.length fields then changed := true;
                `Assoc kept
            | other -> other)
          items
      in
      if !changed then `List stripped else tasks
  | other -> other

(* ================================================================ *)
(* Slice: async_delegation (async_delegation.py, delegation_live_log.py) *)
(* ================================================================ *)

(* round(x, 1): Python 3 uses round-half-to-even on the binary float, not
   round-half-away-from-zero -- round(0.25,1)=0.2, round(0.35,1)=0.3. *)
let round1 x =
  (* Delegate to the C library's correctly-rounded binary64->decimal
     conversion (glibc printf) rather than hand-rolling round-half-to-even
     in floating point -- a naive scale/round/unscale is itself subject to
     intermediate rounding error at exactly the boundary cases this matters
     for. Both this and Python's round() are "correctly round to N decimal
     places"; there is only one right answer per IEEE 754 outside the
     true-tie case, where both follow round-to-even. *)
  float_of_string (Printf.sprintf "%.1f" x)

let children_activity_from_token (token : Yojson.Safe.t list option) ~now : Yojson.Safe.t option =
  match token with
  | None -> None
  | Some parts ->
      Some
        (`List
          (List.map
             (fun part ->
               match part with
               | `List (api_calls :: current_tool :: rest) ->
                   let base = [ ("api_calls", api_calls); ("current_tool", current_tool) ] in
                   let extra =
                     match rest with
                     | ts :: _ -> (
                         match ts with
                         | `Int n -> [ ("seconds_since_activity", `Float (round1 (Float.max 0.0 (now -. float_of_int n)))) ]
                         | `Float f -> [ ("seconds_since_activity", `Float (round1 (Float.max 0.0 (now -. f)))) ]
                         | _ -> [])
                     | [] -> []
                   in
                   `Assoc (base @ extra)
               | _ -> `Null)
             parts))

(* str(text or ""): ANY falsy text (None, 0, 0.0, "", [], {}, False)
   collapses to "" -- not str(text). *)
let one_line (text : Yojson.Safe.t) ~limit : string =
  let s = if json_truthy text then python_str text else "" in
  let s = String.concat " " (List.filter (fun t -> t <> "") (String.split_on_char ' ' (String.map (fun c -> if is_ws c then ' ' else c) s))) in
  if String.length s > limit then
    let omitted = String.length s - limit in
    Printf.sprintf "%s \xe2\x80\xa6(+%d chars)" (String.sub s 0 limit) omitted
  else s

(* Despite the -> bool annotation, Python's and/or return an OPERAND, not a
   coerced boolean: with every selector at its "" default, this returns the
   string "" itself, not False. Modeled here returning the RAW disjunction
   result as a string (empty = falsy), matching what a differential harness
   comparing raw return values (not truth-tested) would actually see. *)
(* `X and (a == b)` does NOT return X when the comparison holds -- `and`
   returns whichever operand DECIDES the result: X itself when X is falsy
   (short-circuits without evaluating the comparison), otherwise the
   comparison's own boolean result (even when that result is False). Wrong
   on the first pass: assumed the clause returned the matched selector
   string; the reference proved otherwise ("raw": true, not "raw": "k1").
   Chained with `or`, the whole expression's static type is genuinely
   EITHER a string (every selector falsy/absent) or a bool (the first
   present selector's match outcome) -- not consistently one or the other,
   hence the Yojson.Safe.t return type here instead of a plain string. *)
let matches_session_selectors ~record ~session_key ~origin_ui_session_id ~parent_session_id : Yojson.Safe.t =
  let get k = match field_of record k with Some (`String s) -> s | _ -> "" in
  let clause selector field_name : Yojson.Safe.t = if selector = "" then `String "" else `Bool (get field_name = selector) in
  let is_truthy = function `Bool b -> b | `String s -> s <> "" | _ -> false in
  let c1 = clause origin_ui_session_id "origin_ui_session_id" in
  if is_truthy c1 then c1
  else
    let c2 = clause session_key "session_key" in
    if is_truthy c2 then c2 else clause parent_session_id "parent_session_id"

(* ================================================================ *)
(* Slice: mixture_of_agents (moa_loop.py, moa_trace.py, message_content.py) *)
(* ================================================================ *)

let non_text_part_types = [ "image"; "image_url"; "input_image"; "audio"; "input_audio" ]
let text_keys = [ "text"; "content"; "input_text"; "output_text"; "summary_text" ]

let text_from_part (part : Yojson.Safe.t) : string =
  match part with
  | `Null -> ""
  | `String s -> s
  | _ ->
      let part_type = lower (strip (match field_of part "type" with Some (`String t) -> t | _ -> "")) in
      if List.mem part_type non_text_part_types then ""
      else
        let rec find = function [] -> "" | key :: rest -> ( match field_of part key with Some (`String t) -> t | _ -> find rest) in
        find text_keys

(* Dict-shaped content with no recognized text field falls to Python's
   str(dict) (its repr) in the frozen reference -- not reproduced here
   (disclosed); no fixture exercises that exact fallback. *)
let flatten_message_text ?(sep = "\n") (content : Yojson.Safe.t) : string =
  match content with
  | `Null -> ""
  | `String s -> s
  | `List parts -> String.concat sep (List.filter (fun c -> c <> "") (List.map text_from_part parts))
  | other ->
      let text = text_from_part other in
      if text <> "" then text else python_str other

let render_tool_calls (tool_calls : Yojson.Safe.t) : string =
  let calls = match tool_calls with `List items -> items | _ -> [] in
  let lines =
    List.map
      (fun tc ->
        let fn = match field_of tc "function" with Some (`Assoc _ as f) -> f | _ -> `Assoc [] in
        let fn_name = match field_of fn "name" with Some (`String s) when s <> "" -> Some s | _ -> None in
        let fn_args = field_of fn "arguments" in
        let top_name = match field_of tc "name" with Some (`String s) when s <> "" -> Some s | _ -> None in
        let name = match fn_name with Some n -> n | None -> ( match top_name with Some n -> n | None -> "tool") in
        let args_text = match fn_args with Some (`String s) -> s | None | Some `Null -> "" | Some other -> json_spaced_unsorted other in
        if args_text <> "" then Printf.sprintf "[called tool: %s(%s)]" name args_text else Printf.sprintf "[called tool: %s]" name)
      calls
  in
  String.concat "\n" lines

let truncate_tool_result text ~budget =
  if text = "" || String.length text <= budget then text
  else
    let half = budget / 2 in
    let omitted = String.length text - (2 * half) in
    Printf.sprintf "%s\n[... %d chars omitted ...]\n%s" (String.sub text 0 half) omitted (String.sub text (String.length text - half) half)

(* Exact inverse of _attach_reference_guidance's three shapes (string
   merge, trailing text part, appended user message) -- kept adjacent so
   the two evolve together in the frozen reference; a drifting separator
   or shape makes the peel silently no-op (the historical bug #72626 this
   function exists to fix). Branch order matters: exact-message-equality
   (shape c) is checked BEFORE suffix-endswith (shape a). Always returns a
   fresh list, mirroring the frozen function's own explicit non-mutation
   contract (its sibling _attach_reference_guidance mutates in place and
   returns None; not ported, since a differential harness needs a return
   value to compare). *)
let peel_reference_guidance ~guidance (messages : Yojson.Safe.t list) : Yojson.Safe.t list =
  if (not (json_truthy guidance)) || messages = [] then messages
  else
    let guidance_text = python_str guidance in
    let messages_arr = Array.of_list messages in
    let n = Array.length messages_arr in
    let last = messages_arr.(n - 1) in
    match last with
    | `Assoc last_fields when List.assoc_opt "role" last_fields = Some (`String "user") -> (
        let init = Array.to_list (Array.sub messages_arr 0 (n - 1)) in
        let content = Option.value (List.assoc_opt "content" last_fields) ~default:`Null in
        if content = `String guidance_text then init
        else
          let suffix = "\n\n" ^ guidance_text in
          match content with
          | `String s when ends_with suffix s ->
              let peeled = assoc_set "content" (`String (String.sub s 0 (String.length s - String.length suffix))) last_fields in
              init @ [ `Assoc peeled ]
          | `List (_ :: _ as parts) -> (
              let last_part = List.nth parts (List.length parts - 1) in
              let init_parts = List.filteri (fun i _ -> i < List.length parts - 1) parts in
              match last_part with
              | `Assoc lp_fields when (match List.assoc_opt "type" lp_fields with Some (`String t) -> t | _ -> "text") = "text" ->
                  let text = match List.assoc_opt "text" lp_fields with Some (`String t) -> t | _ -> "" in
                  if text = suffix || text = guidance_text then
                    if init_parts = [] then init else init @ [ `Assoc (assoc_set "content" (`List init_parts) last_fields) ]
                  else if ends_with suffix text then
                    let new_part = assoc_set "text" (`String (String.sub text 0 (String.length text - String.length suffix))) lp_fields in
                    init @ [ `Assoc (assoc_set "content" (`List (init_parts @ [ `Assoc new_part ])) last_fields) ]
                  else messages
              | _ -> messages)
          | _ -> messages)
    | _ -> messages

let advisory_instruction =
  "[The conversation above is the current state of the task. Give your most intelligent judgement: what is going on, what should happen next, what risks or mistakes you see, and how the acting agent should proceed.]"

let reference_messages ~tool_result_budget (messages : Yojson.Safe.t list) : Yojson.Safe.t list =
  let rendered = ref [] in
  let last_user_content = ref None in
  List.iter
    (fun msg ->
      let role = match field_of msg "role" with Some (`String r) -> r | _ -> "" in
      let content = Option.value (field_of msg "content") ~default:`Null in
      let text = flatten_message_text content in
      if role = "system" then ()
      else if role = "user" then begin
        let text = if strip text = "" && (match content with `List (_ :: _) -> true | _ -> false) then "[user sent non-text content (e.g. an image attachment)]" else text in
        if strip text = "" then ()
        else begin
          last_user_content := Some text;
          rendered := ("user", text) :: !rendered
        end
      end
      else if role = "assistant" then begin
        let parts = ref [] in
        if strip text <> "" then parts := strip text :: !parts;
        let calls_text = render_tool_calls (Option.value (field_of msg "tool_calls") ~default:`Null) in
        if calls_text <> "" then parts := calls_text :: !parts;
        let parts = List.rev !parts in
        if parts <> [] then rendered := ("assistant", String.concat "\n" parts) :: !rendered
      end
      else if role = "tool" then begin
        let result_text = truncate_tool_result text ~budget:tool_result_budget in
        let block = Printf.sprintf "[tool result: %s]" result_text in
        match !rendered with
        | ("assistant", prev_content) :: rest -> rendered := ("assistant", prev_content ^ "\n" ^ block) :: rest
        | _ -> rendered := ("assistant", block) :: !rendered
      end)
    messages;
  let rendered_list = List.rev !rendered in
  let rendered_list =
    match List.rev rendered_list with (role, _) :: _ when role = "assistant" -> rendered_list @ [ ("user", advisory_instruction) ] | _ -> rendered_list
  in
  if rendered_list = [] then (
    match !last_user_content with
    | Some text -> [ `Assoc [ ("role", `String "user"); ("content", `String text) ] ]
    | None ->
        let rec find_last_user = function
          | [] -> []
          | msg :: rest -> (
              match field_of msg "role" with
              | Some (`String "user") ->
                  let fallback_text = flatten_message_text (Option.value (field_of msg "content") ~default:`Null) in
                  if strip fallback_text <> "" then [ `Assoc [ ("role", `String "user"); ("content", `String fallback_text) ] ] else find_last_user rest
              | _ -> find_last_user rest)
        in
        find_last_user (List.rev messages))
  else List.map (fun (role, content) -> `Assoc [ ("role", `String role); ("content", `String content) ]) rendered_list

let is_failed_reference text =
  let sentinel = lower (lstrip text) in
  starts_with "[failed:" sentinel || starts_with "[skipped:" sentinel

let successful_references (reference_outputs : Yojson.Safe.t list) =
  List.filter (function `List [ _; `String text; _ ] -> not (is_failed_reference text) | _ -> true) reference_outputs

let failed_reference_labels (reference_outputs : Yojson.Safe.t list) =
  List.filter_map
    (function `List [ `String label; `String text; _ ] -> if is_failed_reference text then Some label else None | _ -> None)
    reference_outputs

let degraded_notice failed_labels policy =
  if failed_labels = [] || lower (strip policy) = "silent" then "" else Printf.sprintf "[Reference models unavailable: %s]" (String.concat ", " failed_labels)

let preset_temperature (preset : Yojson.Safe.t) key =
  match field_of preset key with
  | None | Some `Null -> None
  | Some (`String s) when strip s = "" -> None
  | Some (`String s) -> float_of_string_opt s
  | Some (`Int n) -> Some (float_of_int n)
  | Some (`Float f) -> Some f
  | Some (`Bool b) -> Some (if b then 1.0 else 0.0)
  | Some _ -> None

let slot_label (slot : Yojson.Safe.t) =
  let get k = match field_of slot k with Some (`String s) -> s | _ -> "" in
  let label = Printf.sprintf "%s:%s" (strip (get "provider")) (strip (get "model")) in
  let effort = strip (get "reasoning_effort") in
  if effort <> "" then Printf.sprintf "%s[reasoning=%s]" label effort else label

let merge_slot_extra_body (slot_extra_body : Yojson.Safe.t) (caller_extra_body : Yojson.Safe.t) : Yojson.Safe.t =
  match slot_extra_body with
  | `Assoc (_ :: _ as slot_fields) -> (
      match caller_extra_body with
      | `Assoc caller_fields -> `Assoc (List.fold_left (fun acc (k, v) -> assoc_set k v acc) slot_fields caller_fields)
      | other -> if json_truthy other then other else `Assoc slot_fields)
  | _ -> caller_extra_body

let sanitize_session_id (session_id : string option) : string =
  match session_id with
  | None | Some "" -> "unknown-session"
  | Some s -> String.map (fun c -> if is_alnum_underscore c || c = '-' || c = '.' then c else '_') s

(* ================================================================ *)
(* Slice: kanban_swarm (kanban_swarm.py, kanban_tools.py)            *)
(* ================================================================ *)

(* Python str.split(sep, maxsplit): at most maxsplit splits -> up to
   maxsplit+1 parts; remaining separators stay glued into the last part. *)
let split_maxsplit ~sep ~maxsplit s =
  let parts = ref [] in
  let remaining = ref s in
  let count = ref 0 in
  let continue_ = ref true in
  while !continue_ do
    if !count >= maxsplit then begin
      parts := !remaining :: !parts;
      continue_ := false
    end
    else
      match String.index_opt !remaining sep with
      | None ->
          parts := !remaining :: !parts;
          continue_ := false
      | Some idx ->
          parts := String.sub !remaining 0 idx :: !parts;
          remaining := String.sub !remaining (idx + 1) (String.length !remaining - idx - 1);
          incr count
  done;
  List.rev !parts

(* SwarmWorkerSpec is a dataclass with two fields parse_worker_arg never
   sets explicitly -- priority: int = 0 and max_runtime_seconds: Optional[int]
   = None -- but dataclasses.asdict(spec) (called by the adapter) serializes
   every field, defaults included. Missing on the first pass: the candidate
   emitted only the four fields the function body actually assigns. *)
let parse_worker_arg raw : (Yojson.Safe.t, string) result =
  let parts = List.map strip (split_maxsplit ~sep:':' ~maxsplit:2 raw) in
  match parts with
  | p0 :: p1 :: rest ->
      let skills =
        match rest with [ p2 ] when p2 <> "" -> List.filter (fun s -> s <> "") (List.map strip (String.split_on_char ',' p2)) | _ -> []
      in
      Ok
        (`Assoc
          [ ("profile", `String p0); ("title", `String p1); ("body", `String p1); ("skills", `List (List.map (fun s -> `String s) skills));
            ("priority", `Int 0); ("max_runtime_seconds", `Null) ])
  | _ -> Error "worker must be profile:title or profile:title:skill,skill"

let require_text value field_name = let text = strip value in if text = "" then Error (Printf.sprintf "%s is required" field_name) else Ok text

let swarm_context ~root_id ~goal =
  Printf.sprintf
    "\n\n## Swarm protocol\n- Swarm root / shared blackboard: `%s`.\n- Read sibling/parent handoffs from Kanban context before working.\n- Put machine-readable facts in completion metadata.\n- Put cross-worker notes on the root task using structured comments.\n- Goal: %s\n"
    root_id (strip goal)

let parse_bool_arg (args : Yojson.Safe.t) name ~default : bool * string option =
  match field_of args name with
  | None | Some `Null -> (default, None)
  | Some (`Bool b) -> (b, None)
  | Some other ->
      let text = lower (strip (python_str other)) in
      if List.mem text [ "true"; "1"; "yes" ] then (true, None)
      else if List.mem text [ "false"; "0"; "no" ] then (false, None)
      else (default, Some (Printf.sprintf "%s must be a boolean or 'true'/'false'" name))

(* json.dumps({"ok": True, **fields}): no sort_keys -- "ok" first, then
   fields in caller order; default (spaced) separators. *)
let ok_envelope fields = json_spaced_unsorted (`Assoc (("ok", `Bool true) :: fields))

let normalize_profile (value : Yojson.Safe.t) : string option =
  match value with
  | `Null -> None
  | other ->
      let text = strip (python_str other) in
      if text = "" || List.mem (lower text) [ "none"; "-"; "null" ] then None else Some text
