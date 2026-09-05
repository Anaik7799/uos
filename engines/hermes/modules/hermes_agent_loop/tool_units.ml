(* tool_execution units, reproduced faithfully from the frozen tools/ and
   agent/ modules (each read completely before writing; parity is measured by
   the tool.* scenarios, never assumed). One pure callable per slice:

     tool_registry        estimate_tokens_from_schemas, should_activate,
                          listing_token_budget (tools/tool_search.py)
     tool_dispatch        _is_destructive_command (agent/tool_dispatch_helpers.py)
     approval_policy      _normalize_enabled (tools/write_approval.py)
     file_operations      parse_v4a_patch (tools/patch_parser.py)
     result_normalization canonical_tool_args, classify_tool_failure,
                          file_mutation_result_landed (agent/tool_guardrails.py,
                          agent/tool_result_classification.py)

   Excluded, disclosed beside each scenario: everything registry/approval/
   dispatch that touches the tool registry, the filesystem, contextvars, or
   config.yaml -- those are impure resolution layers over the pure cores
   measured here. *)

(* ---- a compact JSON serializer matching Python json.dumps ----
   ensure_ascii=false, separators=(",",":"); sort_keys optional. Emits the
   dumps control shorthands and passes UTF-8 through. For the char-count use
   (estimate) and the canonical use, the two flags below select the exact
   frozen call. *)
let json_compact ~sort_keys (value : Yojson.Safe.t) : string =
  let buffer = Buffer.create 128 in
  let add_string text =
    Buffer.add_char buffer '"';
    String.iter
      (fun c ->
        match c with
        | '"' -> Buffer.add_string buffer "\\\""
        | '\\' -> Buffer.add_string buffer "\\\\"
        | '\n' -> Buffer.add_string buffer "\\n"
        | '\t' -> Buffer.add_string buffer "\\t"
        | '\r' -> Buffer.add_string buffer "\\r"
        | '\b' -> Buffer.add_string buffer "\\b"
        | '\012' -> Buffer.add_string buffer "\\f"
        | c when Char.code c < 0x20 ->
            Buffer.add_string buffer (Printf.sprintf "\\u%04x" (Char.code c))
        | c -> Buffer.add_char buffer c)
      text;
    Buffer.add_char buffer '"'
  in
  let rec go = function
    | `Null -> Buffer.add_string buffer "null"
    | `Bool b -> Buffer.add_string buffer (if b then "true" else "false")
    | `Int n -> Buffer.add_string buffer (string_of_int n)
    | `Intlit s -> Buffer.add_string buffer s
    | `Float f -> Buffer.add_string buffer (Yojson.Safe.to_string (`Float f))
    | `String s -> add_string s
    | `List items ->
        Buffer.add_char buffer '[';
        List.iteri (fun i v -> if i > 0 then Buffer.add_char buffer ','; go v) items;
        Buffer.add_char buffer ']'
    | `Assoc fields ->
        let fields =
          if sort_keys then List.sort (fun (a, _) (b, _) -> String.compare a b) fields
          else fields
        in
        Buffer.add_char buffer '{';
        List.iteri
          (fun i (k, v) ->
            if i > 0 then Buffer.add_char buffer ',';
            add_string k;
            Buffer.add_char buffer ':';
            go v)
          fields;
        Buffer.add_char buffer '}'
  in
  go value;
  Buffer.contents buffer

(* utf8 length in code points is NOT what Python len() counts for a str built
   from bytes we passed through; but scenario tool-defs are ASCII, so byte
   length equals character length. Guarded by clean scenario construction. *)

(* ---- tool_registry ---- *)

(* estimate_tokens_from_schemas: sum of compact-json lengths, chars/4, ceil. *)
let chars_per_token = 4.0

let estimate_tokens_from_schemas tool_defs =
  let total =
    List.fold_left
      (fun acc td -> acc + String.length (json_compact ~sort_keys:false td))
      0 tool_defs
  in
  int_of_float (Float.ceil (float_of_int total /. chars_per_token))

(* should_activate: off -> false; no deferrable tokens -> false; else true. *)
let should_activate ~enabled ~deferrable_tokens =
  if enabled = "off" then false else if deferrable_tokens <= 0 then false else true

(* listing_token_budget: min(listing_max_tokens, pct of context or 10K), >= 0. *)
let listing_token_budget ~threshold_pct ~listing_max_tokens ~context_length =
  let pct_leg =
    match context_length with
    | Some cl when cl > 0 -> int_of_float (float_of_int cl *. (threshold_pct /. 100.0))
    | _ -> 10_000
  in
  max 0 (min listing_max_tokens pct_leg)

(* ---- tool_dispatch ---- *)

(* _is_destructive_command: a destructive command at a shell boundary, or an
   overwriting single-> redirect. The frozen regexes, reproduced as scanners. *)
let is_space c = c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012' || c = '\011'

let destructive_commands =
  (* each: the literal, then how the frozen alternative ends *)
  [ ("rm", `Ws); ("rmdir", `Ws); ("cp", `Ws); ("install", `Ws); ("mv", `Ws);
    ("sed", `SedI); ("truncate", `Ws); ("dd", `Ws); ("shred", `Ws); ("git", `GitSub) ]

let is_destructive_command cmd =
  let n = String.length cmd in
  if n = 0 then false
  else begin
    let boundary_before j =
      j = 0 || is_space cmd.[j - 1] || cmd.[j - 1] = ';' || cmd.[j - 1] = '`'
      || (j >= 2 && String.sub cmd (j - 2) 2 = "&&")
      || (j >= 2 && String.sub cmd (j - 2) 2 = "||")
    in
    let starts_at prefix j =
      j + String.length prefix <= n && String.sub cmd j (String.length prefix) = prefix
    in
    let ws_run j =
      let rec go k = if k < n && is_space cmd.[k] then go (k + 1) else k in
      go j
    in
    let one_ws j = j < n && is_space cmd.[j] in
    let command_at j =
      List.exists
        (fun (lit, ending) ->
          starts_at lit j
          &&
          let after = j + String.length lit in
          match ending with
          | `Ws -> one_ws after
          | `SedI ->
              (* sed\s+-i : one-or-more spaces then "-i" *)
              let e = ws_run after in
              e > after && starts_at "-i" e
          | `GitSub ->
              (* git\s+(reset|clean|checkout)\s *)
              let e = ws_run after in
              e > after
              && List.exists
                   (fun sub -> starts_at sub e && one_ws (e + String.length sub))
                   [ "reset"; "clean"; "checkout" ])
        destructive_commands
    in
    let destructive =
      let rec scan j =
        if j >= n then false
        else if boundary_before j && command_at j then true
        else scan (j + 1)
      in
      scan 0
    in
    (* _REDIRECT_OVERWRITE: [^>]>[^>] | ^>[^>] *)
    let redirect =
      let rec scan k =
        if k >= n then false
        else if
          cmd.[k] = '>' && k + 1 < n && cmd.[k + 1] <> '>'
          && (k = 0 || cmd.[k - 1] <> '>')
        then true
        else scan (k + 1)
      in
      scan 0
    in
    destructive || redirect
  end

(* ---- approval_policy ---- *)

(* _normalize_enabled: bool passes through; a string is truthy iff it is one
   of the accepted words; anything else is false. *)
let normalize_enabled = function
  | `Bool b -> b
  | `String s ->
      List.mem
        (String.lowercase_ascii (String.trim s))
        [ "on"; "true"; "yes"; "1"; "approve"; "enabled" ]
  | _ -> false

(* ---- result_normalization ---- *)

(* canonical_tool_args: sorted compact json, ensure_ascii=false. Raises when
   the argument is not a mapping -- reproduced as a variant so the caller can
   report the frozen TypeError shape. *)
let canonical_tool_args = function
  | `Assoc _ as args -> Ok (json_compact ~sort_keys:true args)
  | _ -> Error "tool args must be a mapping"

let file_mutating_tool_names = [ "write_file"; "patch" ]

let assoc_field name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let truthy = function
  | `Null | `Bool false | `String "" | `List [] | `Assoc [] | `Int 0 -> false
  | `Float f -> f <> 0.0
  | _ -> true

(* file_mutation_result_landed: proof a write/patch landed. *)
let file_mutation_result_landed ~tool_name ~result =
  if not (List.mem tool_name file_mutating_tool_names) then false
  else
    match Yojson.Safe.from_string (String.trim result) with
    | exception _ -> false
    | (`Assoc _ as data) ->
        let has_error = match assoc_field "error" data with Some v -> truthy v | None -> false in
        if has_error then false
        else if tool_name = "write_file" then assoc_field "bytes_written" data <> None
        else if tool_name = "patch" then assoc_field "success" data = Some (`Bool true)
        else false
    | _ -> false

(* classify_tool_failure: the safety-fallback classifier, mirroring
   agent.display._detect_tool_failure. Returns (failed, suffix). *)
let classify_tool_failure ~tool_name ~result =
  match result with
  | None -> (false, "")
  | Some result ->
      if file_mutation_result_landed ~tool_name ~result then (false, "")
      else if tool_name = "terminal" then (
        match Yojson.Safe.from_string result with
        | `Assoc _ as data -> (
            match assoc_field "exit_code" data with
            | Some (`Int code) when code <> 0 -> (true, Printf.sprintf " [exit %d]" code)
            | _ -> (false, ""))
        | _ -> (false, "")
        | exception _ -> (false, ""))
      else begin
        let memory_full =
          if tool_name = "memory" then (
            match Yojson.Safe.from_string result with
            | `Assoc _ as data ->
                assoc_field "success" data = Some (`Bool false)
                && (match assoc_field "error" data with
                   | Some (`String e) ->
                       let needle = "exceed the limit" in
                       let n = String.length needle and h = String.length e in
                       let rec at i = i + n <= h && (String.sub e i n = needle || at (i + 1)) in
                       at 0
                   | _ -> false)
            | _ -> false
            | exception _ -> false)
          else false
        in
        if memory_full then (true, " [full]")
        else begin
          let head = if String.length result > 500 then String.sub result 0 500 else result in
          let lower = String.lowercase_ascii head in
          let contains needle =
            let n = String.length needle and h = String.length lower in
            let rec at i = i + n <= h && (String.sub lower i n = needle || at (i + 1)) in
            at 0
          in
          let starts_error =
            String.length result >= 5 && String.sub result 0 5 = "Error"
          in
          if contains "\"error\"" || contains "\"failed\"" || starts_error then (true, " [error]")
          else (false, "")
        end
      end

(* ---- file_operations: parse_v4a_patch ----
   A faithful port of the frozen line-oriented parser. Returns the operation
   list and an optional error string, mirroring the (operations, error) tuple.
   Operations serialize exactly as dataclasses.asdict renders them, including
   the Enum stringified by json default=str: "OperationType.UPDATE" etc. *)

type hunk_line = { prefix : string; content : string }
type hunk = { context_hint : string option; lines : hunk_line list }
type operation = {
  op_kind : string;      (* "OperationType.ADD" | ...UPDATE | ...DELETE | ...MOVE *)
  file_path : string;
  new_path : string option;
  hunks : hunk list;
  content : string option;
}

let strip s =
  let is_ws c = c = ' ' || c = '\t' || c = '\r' || c = '\n' || c = '\012' || c = '\011' in
  let n = String.length s in
  let i = ref 0 and j = ref (n - 1) in
  while !i < n && is_ws s.[!i] do incr i done;
  while !j >= !i && is_ws s.[!j] do decr j done;
  if !j < !i then "" else String.sub s !i (!j - !i + 1)

let starts_with prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

(* Match "***<ws>Kind<ws>File:<rest>" returning the trimmed rest, mirroring
   re.match(r'\*\*\*\s*Kind\s+File:\s*(.+)'). \s* / \s+ are one-or-more/zero
   runs of Python whitespace; the (.+) is greedy and then .strip()ed by the
   caller. *)
let is_pyws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012' || c = '\011'

let match_marker kind line =
  let n = String.length line in
  if not (starts_with "***" line) then None
  else begin
    let i = ref 3 in
    while !i < n && is_pyws line.[!i] do incr i done;
    if not (starts_with kind (String.sub line !i (n - !i))) then None
    else begin
      i := !i + String.length kind;
      (* \s+ File: — at least one ws required before File *)
      let ws_start = !i in
      while !i < n && is_pyws line.[!i] do incr i done;
      if !i = ws_start then None
      else if not (starts_with "File:" (String.sub line !i (n - !i))) then None
      else begin
        i := !i + String.length "File:";
        while !i < n && is_pyws line.[!i] do incr i done;
        if !i >= n then None else Some (String.sub line !i (n - !i))
      end
    end
  end

(* Move needs the "src -> dst" split from re.match(r'...:\s*(.+?)\s*->\s*(.+)'). *)
let match_move line =
  match match_marker "Move" line with
  | None -> None
  | Some rest -> (
      (* the lazy source group runs up to the first arrow; surrounding
         whitespace is stripped from both sides *)
      let n = String.length rest in
      let rec find i =
        if i >= n then None
        else if rest.[i] = '-' && i + 1 < n && rest.[i + 1] = '>' then Some i
        else find (i + 1)
      in
      match find 0 with
      | None -> None
      | Some arrow ->
          let src = strip (String.sub rest 0 arrow) in
          let dst = strip (String.sub rest (arrow + 2) (n - arrow - 2)) in
          Some (src, dst))

(* re.match of @@ then \s* then a lazy non-empty group then \s* then @@, on a
   line starting with @@. Two frozen subtleties the harness caught, both
   reproduced here: the group must match at least one character, AND the
   leading \s* is GREEDY-with-backtrack, so "@@ @@" matches with the leading
   \s* backtracked to empty and the single space AS the group -- the hint is
   " " (a space), not None and not "". The engine tries the largest leading
   whitespace first and shrinks it until a non-empty group followed by
   optional trailing whitespace and a closing @@ is found. *)
let context_hint_of line =
  if not (starts_with "@@" line) then None
  else begin
    let n = String.length line in
    let max_leading =
      let rec go k = if k < n && is_pyws line.[k] then go (k + 1) else k - 2 in
      go 2
    in
    let result = ref None in
    let w = ref max_leading in
    while !result = None && !w >= 0 do
      let content_start = 2 + !w in
      let c = ref 1 in
      while !result = None && content_start + !c <= n do
        let content_end = content_start + !c in
        let k = ref content_end in
        while !k < n && is_pyws line.[!k] do incr k done;
        if !k + 1 < n && line.[!k] = '@' && line.[!k + 1] = '@' then
          result := Some (String.sub line content_start (content_end - content_start))
        else incr c
      done;
      decr w
    done;
    !result
  end

(* Python's repr() of a string, for the {path!r} error formatting -- single
   quotes unless the string holds a single quote and no double quote, with
   the usual escapes. The harness caught %S (double quotes) diverging from
   the frozen !r (single quotes). *)
let py_repr s =
  let has c = String.exists (fun x -> x = c) s in
  let quote = if has '\'' && not (has '"') then '"' else '\'' in
  let buffer = Buffer.create (String.length s + 2) in
  Buffer.add_char buffer quote;
  String.iter
    (fun c ->
      if c = quote then (Buffer.add_char buffer '\\'; Buffer.add_char buffer c)
      else
        match c with
        | '\\' -> Buffer.add_string buffer "\\\\"
        | '\n' -> Buffer.add_string buffer "\\n"
        | '\r' -> Buffer.add_string buffer "\\r"
        | '\t' -> Buffer.add_string buffer "\\t"
        | c when Char.code c < 0x20 || Char.code c = 0x7f ->
            Buffer.add_string buffer (Printf.sprintf "\\x%02x" (Char.code c))
        | c -> Buffer.add_char buffer c)
    s;
  Buffer.add_char buffer quote;
  Buffer.contents buffer

let parse_v4a_patch patch_content =
  let raw_lines = String.split_on_char '\n' patch_content in
  let lines =
    List.map
      (fun l ->
        let n = String.length l in
        if n > 0 && l.[n - 1] = '\r' then String.sub l 0 (n - 1) else l)
      raw_lines
    |> Array.of_list
  in
  let total = Array.length lines in
  (* markers must occupy the whole line: reproduce the two anchored regexes
     ^\*\*\*\s*(Begin|End)\s+Patch\s*$ *)
  let whole_marker word line =
    let n = String.length line in
    if not (starts_with "***" line) then false
    else begin
      let i = ref 3 in
      while !i < n && is_pyws line.[!i] do incr i done;
      if not (starts_with word (String.sub line !i (n - !i))) then false
      else begin
        i := !i + String.length word;
        let ws0 = !i in
        while !i < n && is_pyws line.[!i] do incr i done;
        if !i = ws0 then false (* need \s+ *)
        else if not (starts_with "Patch" (String.sub line !i (n - !i))) then false
        else begin
          i := !i + String.length "Patch";
          while !i < n && is_pyws line.[!i] do incr i done;
          !i = n
        end
      end
    end
  in
  let start_idx = ref None and end_idx = ref None in
  (try
     Array.iteri
       (fun i line ->
         if whole_marker "Begin" line then start_idx := Some i
         else if whole_marker "End" line then (end_idx := Some i; raise Exit))
       lines
   with Exit -> ());
  let start_i = match !start_idx with Some i -> i | None -> -1 in
  let end_i = match !end_idx with Some i -> i | None -> total in
  let operations = ref [] in
  let current_op = ref None in
  let current_hunk = ref None in
  let flush_hunk () =
    match (!current_op, !current_hunk) with
    | Some op, Some h when h.lines <> [] ->
        current_op := Some { op with hunks = op.hunks @ [ { h with lines = h.lines } ] }
    | _ -> ()
  in
  let push_op () =
    (match !current_op with Some op -> operations := !operations @ [ op ] | None -> ());
    current_op := None
  in
  let i = ref (start_i + 1) in
  while !i < end_i do
    let line = lines.(!i) in
    (match match_marker "Update" line with
     | Some path ->
         flush_hunk (); push_op ();
         current_op :=
           Some { op_kind = "OperationType.UPDATE"; file_path = strip path; new_path = None;
                  hunks = []; content = None };
         current_hunk := None
     | None -> (
       match match_marker "Add" line with
       | Some path ->
           flush_hunk (); push_op ();
           current_op :=
             Some { op_kind = "OperationType.ADD"; file_path = strip path; new_path = None;
                    hunks = []; content = None };
           current_hunk := Some { context_hint = None; lines = [] }
       | None -> (
         match match_marker "Delete" line with
         | Some path ->
             flush_hunk (); push_op ();
             current_op :=
               Some { op_kind = "OperationType.DELETE"; file_path = strip path;
                      new_path = None; hunks = []; content = None };
             push_op ();
             current_hunk := None
         | None -> (
           match match_move line with
           | Some (src, dst) ->
               flush_hunk (); push_op ();
               current_op :=
                 Some { op_kind = "OperationType.MOVE"; file_path = src;
                        new_path = Some dst; hunks = []; content = None };
               push_op ();
               current_hunk := None
           | None ->
               if starts_with "@@" line then begin
                 match !current_op with
                 | Some _ ->
                     flush_hunk ();
                     current_hunk := Some { context_hint = context_hint_of line; lines = [] }
                 | None -> ()
               end
               else if !current_op <> None && line <> "" then begin
                 if !current_hunk = None then current_hunk := Some { context_hint = None; lines = [] };
                 let h = match !current_hunk with Some h -> h | None -> assert false in
                 let add prefix content =
                   current_hunk := Some { h with lines = h.lines @ [ { prefix; content } ] }
                 in
                 if starts_with "+" line then add "+" (String.sub line 1 (String.length line - 1))
                 else if starts_with "-" line then add "-" (String.sub line 1 (String.length line - 1))
                 else if starts_with " " line then add " " (String.sub line 1 (String.length line - 1))
                 else if starts_with "\\" line then ()
                 else add " " line
               end))));
    incr i
  done;
  flush_hunk ();
  push_op ();
  let operations = !operations in
  if operations = [] then (operations, None)
  else begin
    let errors = ref [] in
    List.iter
      (fun op ->
        if op.file_path = "" then errors := !errors @ [ "Operation with empty file path" ];
        if op.op_kind = "OperationType.UPDATE" && op.hunks = [] then
          errors := !errors @ [ Printf.sprintf "UPDATE %s: no hunks found" (py_repr op.file_path) ];
        if op.op_kind = "OperationType.MOVE" && op.new_path = None then
          errors :=
            !errors
            @ [ Printf.sprintf "MOVE %s: missing destination path (expected 'src -> dst')"
                  (py_repr op.file_path) ])
      operations;
    if !errors <> [] then ([], Some ("Parse error: " ^ String.concat "; " !errors))
    else (operations, None)
  end

let operation_to_json op : Yojson.Safe.t =
  let opt = function None -> `Null | Some s -> `String s in
  `Assoc
    [ ("operation", `String op.op_kind);
      ("file_path", `String op.file_path);
      ("new_path", opt op.new_path);
      ("hunks",
       `List
         (List.map
            (fun h ->
              `Assoc
                [ ("context_hint", opt h.context_hint);
                  ("lines",
                   `List
                     (List.map
                        (fun l -> `Assoc [ ("prefix", `String l.prefix); ("content", `String l.content) ])
                        h.lines)) ])
            op.hunks));
      ("content", opt op.content) ]
