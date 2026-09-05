(* interactive_cli units, reproduced faithfully from the frozen
   hermes_cli/console_engine.py, hermes_cli/main.py, hermes_cli/commands.py,
   hermes_cli/completion.py, hermes_cli/curses_ui.py,
   hermes_cli/approvals_suggest.py, hermes_cli/bang_shell.py,
   hermes_cli/clipboard.py and tools/ansi_strip.py (each read completely
   before writing, per the parallel four-agent survey of the whole family).
   Parity is measured by the cli.* scenarios, never assumed.

   ASCII-scoped, matching this session's established convention for
   Skill_units/Memory_units: Python's str.lower/.strip/.capitalize are
   Unicode-aware; the functions below use ASCII-only case folding and
   whitespace sets. Divergence is possible only for non-ASCII input, which
   none of the fixtures below exercise.

   Excluded, disclosed here rather than silently dropped:
     - `_contains_shell_syntax` + `_split_line` (console_engine.py) -- POSIX
       shlex tokenization (backslash escapes, quote handling, word
       splitting) is its own porting task, not a one-liner; nothing else in
       repl_session depends on it.
     - `_walk` / `generate_bash` / `generate_zsh` / `generate_fish`
       (completion.py) -- `_walk`'s true input is a live argparse object
       graph; a faithful port needs a captured JSON fixture of `_walk`'s
       output shape for the real `hermes` parser tree, which is a separate
       probing task from porting the string-template generators themselves.
     - `hermes_cli/main.py`'s config-contaminated helpers
       (`gateway_help_lines`, `slack_native_slashes`, etc.) and
       `_relative_time`/`_is_profile_api_key_provider`/`_all_aux_tasks` --
       each reads config.yaml, the wall clock, or does plugin-discovery I/O
       despite a pure-looking signature (flagged non-candidates by the
       survey).
     - `approval_mode.py` in full -- its only two functions read/write
       persistent config; there is no pure candidate, confirmed by reading
       the whole 87-line file, not a scope cut.
     - `normalize_command` / `build_proposals` / `Proposal.add_example`
       (approvals_suggest.py) -- `normalize_command` resolves `$HOME`
       /`$HERMES_HOME` and real filesystem symlinks internally; its output
       depends on the host, not just its argument, so it and everything
       that calls it are excluded rather than falsely measured as pure.
     - `bang_shell_enabled` (bang_shell.py) -- reads `os.getenv` directly
       with no parameter to inject it; not a "plain data in" candidate as
       literally written (the survey's own judgment: trivially fixable, but
       that is a refactor of the frozen reference, not its actual behavior).
     - `hermes_cli/clipboard.py` beyond the two functions below -- every
       other function shells out to a platform clipboard tool or does
       filesystem I/O by design.
     - `ui-tui/src` -- 100% TypeScript/TSX, not part of the Python
       reference tree the OCaml candidate is compared against. *)

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

let is_ws c = String.contains ascii_ws c

let split_whitespace s =
  let n = String.length s in
  let result = ref [] in
  let i = ref 0 in
  while !i < n do
    while !i < n && is_ws s.[!i] do incr i done;
    let start = !i in
    while !i < n && not (is_ws s.[!i]) do incr i done;
    if !i > start then result := String.sub s start (!i - start) :: !result
  done;
  List.rev !result

let replace_all ~needle ~replacement s =
  if needle = "" then s
  else begin
    let buf = Buffer.create (String.length s) in
    let nlen = String.length needle and slen = String.length s in
    let i = ref 0 in
    while !i < slen do
      if !i + nlen <= slen && String.sub s !i nlen = needle then begin
        Buffer.add_string buf replacement;
        i := !i + nlen
      end else begin
        Buffer.add_char buf s.[!i];
        incr i
      end
    done;
    Buffer.contents buf
  end

let last_segment sep s =
  match String.rindex_opt s sep with
  | Some idx -> String.sub s (idx + 1) (String.length s - idx - 1)
  | None -> s

let floored_mod x n = ((x mod n) + n) mod n

let ljust width s =
  let n = String.length s in
  if n >= width then s else s ^ String.make (width - n) ' '

let rjust width s =
  let n = String.length s in
  if n >= width then s else String.make (width - n) ' ' ^ s

(* Python str.capitalize(): first char upper, EVERY OTHER char lower -- not
   merely "uppercase the first character". OCaml's String.capitalize_ascii
   only touches the first char, a real behavioral divergence for mixed-case
   input (survey-flagged, high-value gotcha). *)
let py_capitalize s =
  if s = "" then s
  else
    let first = Char.uppercase_ascii s.[0] in
    let rest = String.lowercase_ascii (String.sub s 1 (String.length s - 1)) in
    String.make 1 first ^ rest

(* Python repr() for the ASCII/control-char range this module's error
   messages exercise -- single-quoted default, double-quoted only when the
   text contains a single quote and no double quote, matching the frozen
   `{part!r}` in parse_apply_indices. Duplicated from Tool_units.py_repr per
   this session's no-cross-import-for-one-function convention. *)
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

(* Python's base-10 int(str): strips surrounding whitespace, optional
   leading sign, digits with single underscores allowed strictly BETWEEN
   two digits (not leading/trailing/doubled), and -- unlike OCaml's
   int_of_string -- rejects 0x/0o/0b prefixes outright since 'x'/'o'/'b'
   are not digits. *)
let python_int_of_string s =
  let s = strip s in
  let n = String.length s in
  if n = 0 then None
  else
    let start = if s.[0] = '+' || s.[0] = '-' then 1 else 0 in
    if start >= n then None
    else begin
      let valid = ref true in
      let digits = Buffer.create n in
      let prev_was_digit = ref false in
      let prev_was_underscore = ref false in
      for i = start to n - 1 do
        let c = s.[i] in
        if c >= '0' && c <= '9' then begin
          Buffer.add_char digits c;
          prev_was_digit := true;
          prev_was_underscore := false
        end else if c = '_' then begin
          if (not !prev_was_digit) || !prev_was_underscore then valid := false;
          prev_was_digit := false;
          prev_was_underscore := true
        end else valid := false
      done;
      if !prev_was_underscore then valid := false;
      if (not !valid) || Buffer.length digits = 0 then None
      else
        try
          let value = int_of_string (Buffer.contents digits) in
          Some (if start = 1 && s.[0] = '-' then -value else value)
        with _ -> None
    end

(* ================================================================ *)
(* Slice: repl_session (console_engine.py, main.py)                 *)
(* ================================================================ *)

(* Ported from tools/ansi_strip.py's _ANSI_ESCAPE_RE, byte-for-byte,
   including the backtrack-to-single-byte fallback when a CSI/OSC/DCS
   sequence never terminates (Python re alternation tries each branch in
   source order at a given start position; when the whole branch fails the
   engine backtracks to the NEXT alternative, not the next position). Byte-
   level, not Unicode-codepoint-level: ANSI control sequences are
   themselves byte patterns, so this is faithful for the terminal-emitted
   codes the caller strips (SGR color codes, OSC title-setting). *)
let has_escape_byte s =
  String.exists (fun c -> let n = Char.code c in n = 0x1b || (n >= 0x80 && n <= 0x9f)) s

let is_between lo hi c =
  let n = Char.code c in
  n >= lo && n <= hi

(* '[' [0x30-0x3f]* [0x20-0x2f]* [0x40-0x7e] *)
let match_csi_tail s start n =
  let i = ref start in
  while !i < n && is_between 0x30 0x3f s.[!i] do incr i done;
  while !i < n && is_between 0x20 0x2f s.[!i] do incr i done;
  if !i < n && is_between 0x40 0x7e s.[!i] then Some (!i + 1) else None

(* ']' [\s\S]*? (BEL | ESC '\\') -- non-greedy: shortest match to the first terminator *)
let match_osc_tail s start n =
  let rec scan i =
    if i >= n then None
    else if s.[i] = '\x07' then Some (i + 1)
    else if s.[i] = '\x1b' && i + 1 < n && s.[i + 1] = '\\' then Some (i + 2)
    else scan (i + 1)
  in
  scan start

(* [PX^_] [\s\S]*? ESC '\\' *)
let match_dcs_tail s start n =
  let rec scan i =
    if i >= n then None
    else if s.[i] = '\x1b' && i + 1 < n && s.[i + 1] = '\\' then Some (i + 2)
    else scan (i + 1)
  in
  scan start

(* [0x20-0x2f]+ [0x30-0x7e] *)
let match_nf s start n =
  let i = ref start in
  while !i < n && is_between 0x20 0x2f s.[!i] do incr i done;
  if !i > start && !i < n && is_between 0x30 0x7e s.[!i] then Some (!i + 1) else None

let try_a1 s start n = if start < n && s.[start] = '[' then match_csi_tail s (start + 1) n else None
let try_a2 s start n = if start < n && s.[start] = ']' then match_osc_tail s (start + 1) n else None

let try_a3 s start n =
  if start < n && (let c = s.[start] in c = 'P' || c = 'X' || c = '^' || c = '_')
  then match_dcs_tail s (start + 1) n
  else None

let try_a4 s start n = match_nf s start n
let try_a5 s start n = if start < n && is_between 0x30 0x7e s.[start] then Some (start + 1) else None

let match_esc_tail s start n =
  match try_a1 s start n with
  | Some e -> Some e
  | None -> (
      match try_a2 s start n with
      | Some e -> Some e
      | None -> (
          match try_a3 s start n with
          | Some e -> Some e
          | None -> ( match try_a4 s start n with Some e -> Some e | None -> try_a5 s start n)))

let match_9b_tail s start n = match_csi_tail s start n

(* 0x9d [\s\S]*? (BEL | 0x9c) *)
let match_9d_tail s start n =
  let rec scan i =
    if i >= n then None
    else if s.[i] = '\x07' then Some (i + 1)
    else if Char.code s.[i] = 0x9c then Some (i + 1)
    else scan (i + 1)
  in
  scan start

let strip_ansi text =
  if not (has_escape_byte text) then text
  else begin
    let n = String.length text in
    let buf = Buffer.create n in
    let i = ref 0 in
    while !i < n do
      let code = Char.code text.[!i] in
      if code = 0x1b then (
        match match_esc_tail text (!i + 1) n with
        | Some e -> i := e
        | None ->
            Buffer.add_char buf text.[!i];
            incr i)
      else if code = 0x9b then (
        match match_9b_tail text (!i + 1) n with Some e -> i := e | None -> incr i)
      else if code = 0x9d then (
        match match_9d_tail text (!i + 1) n with Some e -> i := e | None -> incr i)
      else if code >= 0x80 && code <= 0x9f then incr i
      else begin
        Buffer.add_char buf text.[!i];
        incr i
      end
    done;
    Buffer.contents buf
  end

let box_drawing_horizontal = "\xe2\x94\x80" (* U+2500, UTF-8 *)

(* Length check counts UTF-8 bytes, not Unicode codepoints -- a boundary-
   precise divergence is possible for input containing multi-byte
   characters exactly at the 8-unit threshold. Disclosed, not fixture-
   tested: real footer-rule lines are pure ASCII dashes/box-drawing runs
   well past the threshold either way. *)
let is_status_footer_rule line =
  let stripped = strip (strip_ansi line) in
  if String.length stripped < 8 then false
  else
    let normalized = replace_all ~needle:box_drawing_horizontal ~replacement:"-" stripped in
    String.for_all (fun c -> c = '-') normalized

let splitlines text = String.split_on_char '\n' text

let strip_console_status_footer text =
  let lines = ref (Array.of_list (splitlines text)) in
  let len () = Array.length !lines in
  let pop () = lines := Array.sub !lines 0 (len () - 1) in
  let last () = !lines.(len () - 1) in
  while len () > 0 && strip (strip_ansi (last ())) = "" do
    pop ()
  done;
  if len () < 2 then rstrip_charset ascii_ws text
  else begin
    let last_line = strip (strip_ansi (last ())) in
    let prev_line = strip (strip_ansi !lines.(len () - 2)) in
    if
      not
        (starts_with "Run 'hermes doctor'" prev_line && starts_with "Run 'hermes setup'" last_line)
    then rstrip_charset ascii_ws text
    else begin
      lines := Array.sub !lines 0 (len () - 2);
      while len () > 0 && strip (strip_ansi (last ())) = "" do
        pop ()
      done;
      if len () > 0 && is_status_footer_rule (last ()) then pop ();
      rstrip_charset ascii_ws (String.concat "\n" (Array.to_list !lines))
    end
  end

(* :<N / :>N are PADDING ONLY -- they never truncate. The frozen code
   truncates via explicit slices ([:32], [:12], [:60]) before formatting;
   a port that conflates "format width" with "truncate to width" diverges
   on any over-width id/title. *)
let format_sessions sessions =
  if sessions = [] then "No sessions found."
  else begin
    let truncate n s = if String.length s > n then String.sub s 0 n else s in
    let header = ljust 32 "ID" ^ " " ^ ljust 12 "Source" ^ " " ^ rjust 5 "Msgs" ^ "  Title / Preview" in
    let rule = String.make 82 '-' in
    let row session =
      let get name = match session with `Assoc fields -> ( match List.assoc_opt name fields with Some v -> v | None -> `Null) | _ -> `Null in
      let str_or_default default = function `String s -> s | `Null -> default | v -> Yojson.Safe.to_string v in
      let sid = truncate 32 (str_or_default "" (get "id")) in
      let source = truncate 12 (str_or_default "-" (get "source")) in
      let messages =
        match get "message_count" with `Int i -> string_of_int i | `Null -> "0" | v -> Yojson.Safe.to_string v
      in
      let title =
        match get "title" with
        | `String s when s <> "" -> s
        | _ -> ( match get "preview" with `String s -> s | _ -> "")
      in
      let title = truncate 60 (replace_all ~needle:"\n" ~replacement:" " title) in
      ljust 32 sid ^ " " ^ ljust 12 source ^ " " ^ rjust 5 messages ^ "  " ^ title
    in
    String.concat "\n" (header :: rule :: List.map row sessions)
  end

(* `text is argparse.SUPPRESS` in the frozen reference is an OBJECT-IDENTITY
   check, not a value comparison. Measured directly against the reference
   (cli.repl's clean_summary_suppress case): a plain string equal in TEXT to
   the sentinel's value ("==SUPPRESS==") does NOT take that branch, because a
   string arriving through any boundary that isn't the literal
   `argparse.SUPPRESS` constant is never the same object by `is` -- the
   reference echoes it straight through the rest of the pipeline instead.
   OCaml's `string option` parameter has no representation of "the sentinel
   object" distinct from its text, so that branch is unreachable for any
   value this candidate can be called with; omitted rather than
   miscoded to fire on the sentinel's text. *)
let clean_summary = function
  | None -> ""
  | Some text when text = "" -> ""
  | Some text ->
      let summary = String.concat " " (split_whitespace text) in
      if summary = "" then "" else if starts_with "Run `hermes " summary then "" else summary

let strip_v1_suffix s =
  if ends_with "/v1/" s then String.sub s 0 (String.length s - 4)
  else if ends_with "/v1" s then String.sub s 0 (String.length s - 3)
  else s

let split_first_segment sep s =
  match String.index_opt s sep with Some idx -> String.sub s 0 idx | None -> s

let auto_provider_name base_url =
  let clean = replace_all ~needle:"https://" ~replacement:"" base_url in
  let clean = replace_all ~needle:"http://" ~replacement:"" clean in
  let clean = rstrip_charset "/" clean in
  let clean = strip_v1_suffix clean in
  let name = split_first_segment '/' clean in
  if contains ~needle:"localhost" name || contains ~needle:"127.0.0.1" name then
    Printf.sprintf "Local (%s)" name
  else if contains ~needle:"runpod" (lower name) then Printf.sprintf "RunPod (%s)" name
  else py_capitalize name

let find_flag_value ~flag ~capture text =
  let n = String.length text in
  let flen = String.length flag in
  let rec scan i =
    if i + flen > n then None
    else if String.sub text i flen = flag && (i = 0 || is_ws text.[i - 1]) then
      let after = i + flen in
      if after < n && text.[after] = '=' then (
        match capture text (after + 1) with Some v -> Some v | None -> scan (i + 1))
      else if after < n && is_ws text.[after] then begin
        let j = ref after in
        while !j < n && is_ws text.[!j] do incr j done;
        match capture text !j with Some v -> Some v | None -> scan (i + 1)
      end
      else scan (i + 1)
    else scan (i + 1)
  in
  scan 0

let capture_digits text start =
  let n = String.length text in
  let j = ref start in
  while !j < n && text.[!j] >= '0' && text.[!j] <= '9' do incr j done;
  if !j > start then Some (String.sub text start (!j - start)) else None

let capture_host_token text start =
  let n = String.length text in
  if start >= n then None
  else if text.[start] = '"' then (
    match String.index_from_opt text (start + 1) '"' with
    | Some close -> Some (String.sub text start (close - start + 1))
    | None -> None)
  else if text.[start] = '\'' then (
    match String.index_from_opt text (start + 1) '\'' with
    | Some close -> Some (String.sub text start (close - start + 1))
    | None -> None)
  else begin
    let j = ref start in
    while !j < n && not (is_ws text.[!j]) do incr j done;
    if !j > start then Some (String.sub text start (!j - start)) else None
  end

let parse_dashboard_runtime command =
  let mode =
    if
      contains ~needle:"hermes dashboard" command
      || contains ~needle:"hermes_cli.main dashboard" command
      || contains ~needle:"hermes_cli/main.py dashboard" command
    then Some "dashboard"
    else if
      contains ~needle:"hermes serve" command
      || contains ~needle:"hermes_cli.main serve" command
      || contains ~needle:"hermes_cli/main.py serve" command
    then Some "serve"
    else None
  in
  match mode with
  | None -> None
  | Some mode -> (
      let port =
        match find_flag_value ~flag:"--port" ~capture:capture_digits command with
        | Some digits -> ( try Some (int_of_string digits) with _ -> None)
        | None -> Some 9119
      in
      match port with
      | None -> None
      | Some port ->
          let host =
            match find_flag_value ~flag:"--host" ~capture:capture_host_token command with
            | Some token ->
                let stripped = strip_charset "\"'" token in
                if stripped = "" then "127.0.0.1" else stripped
            | None -> "127.0.0.1"
          in
          Some (mode, host, port))

let dashboard_probe_host host =
  let host = match host with None | Some "" -> "127.0.0.1" | Some h -> h in
  let normalized = strip_charset "[]" (strip host) in
  if normalized = "" || normalized = "0.0.0.0" || normalized = "::" then "127.0.0.1" else normalized

let session_subcommands =
  [ "chat"; "model"; "gateway"; "setup"; "whatsapp"; "whatsapp-cloud"; "login"; "logout"; "auth";
    "status"; "cron"; "doctor"; "config"; "pairing"; "skills"; "tools"; "mcp"; "sessions"; "insights";
    "version"; "update"; "uninstall"; "profile"; "dashboard"; "serve"; "desktop"; "gui"; "honcho";
    "claw"; "plugins"; "security"; "acp"; "webhook"; "memory"; "dump"; "debug"; "backup"; "import";
    "completion"; "logs" ]

let session_flags = [ "-c"; "--continue"; "-r"; "--resume" ]

let coalesce_session_name_args argv =
  let argv = Array.of_list argv in
  let n = Array.length argv in
  let result = ref [] in
  let i = ref 0 in
  while !i < n do
    let token = argv.(!i) in
    if List.mem token session_flags then begin
      result := token :: !result;
      incr i;
      let parts = ref [] in
      while
        !i < n
        && (not (starts_with "-" argv.(!i)))
        && not (List.mem argv.(!i) session_subcommands)
      do
        parts := argv.(!i) :: !parts;
        incr i
      done;
      if !parts <> [] then result := String.concat " " (List.rev !parts) :: !result
    end
    else begin
      result := token :: !result;
      incr i
    end
  done;
  List.rev !result

(* ================================================================ *)
(* Slice: slash_commands (commands.py, completion.py)               *)
(* ================================================================ *)

let is_alnum_underscore c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '_'
let is_alnum_underscore_hyphen c = is_alnum_underscore c || c = '-'

let keep_chars pred s =
  let buf = Buffer.create (String.length s) in
  String.iter (fun c -> if pred c then Buffer.add_char buf c) s;
  Buffer.contents buf

let collapse_runs target s =
  let buf = Buffer.create (String.length s) in
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = target then begin
      Buffer.add_char buf target;
      while !i < n && s.[!i] = target do
        incr i
      done
    end
    else begin
      Buffer.add_char buf s.[!i];
      incr i
    end
  done;
  Buffer.contents buf

let sanitize_telegram_name raw =
  let name = lower raw in
  let name = replace_all ~needle:"-" ~replacement:"_" name in
  let name = keep_chars is_alnum_underscore name in
  let name = collapse_runs '_' name in
  strip_charset "_" name

let slack_name_limit = 32

let sanitize_slack_name raw =
  let name = lower raw in
  let name = keep_chars is_alnum_underscore_hyphen name in
  let name = strip_charset "-_" name in
  if String.length name > slack_name_limit then String.sub name 0 slack_name_limit else name

let cmd_name_limit = 32

(* Python's `for digit in range(10): ... else: continue` -- the else-clause
   fires only when the loop completes WITHOUT break. A straightforward
   OCaml translation must track "found a free digit" explicitly (the
   `try_digit` recursion below) rather than relying on fall-through, or the
   "all 10 digits exhausted -> skip this entry" branch silently never fires
   or always fires (survey-flagged, routinely mis-ported). *)
let clamp_command_names entries reserved =
  let used = ref reserved in
  let mem x = List.mem x !used in
  let add x = used := x :: !used in
  let truncate n s = if String.length s > n then String.sub s 0 n else s in
  let result = ref [] in
  List.iter
    (fun (name, desc) ->
      let resolved =
        if String.length name > cmd_name_limit then begin
          let candidate = truncate cmd_name_limit name in
          if mem candidate then begin
            let prefix = truncate (cmd_name_limit - 1) name in
            let rec try_digit d =
              if d > 9 then None
              else
                let c = prefix ^ string_of_int d in
                if mem c then try_digit (d + 1) else Some c
            in
            try_digit 0
          end
          else Some candidate
        end
        else Some name
      in
      match resolved with
      | None -> ()
      | Some name ->
          if mem name then ()
          else begin
            add name;
            result := (name, desc) :: !result
          end)
    entries;
  List.rev !result

let nested_mapping (root : Yojson.Safe.t) (path : string list) : Yojson.Safe.t =
  let rec walk node = function
    | [] -> ( match node with `Assoc _ -> node | _ -> `Assoc [])
    | key :: rest -> (
        match node with
        | `Assoc fields -> ( match List.assoc_opt key fields with Some next -> walk next rest | None -> `Assoc [])
        | _ -> `Assoc [])
  in
  walk root path

let completion_clean ?(maxlen = 60) text =
  let text = replace_all ~needle:"'" ~replacement:"" text in
  let text = replace_all ~needle:"\"" ~replacement:"" text in
  let text = replace_all ~needle:"\\" ~replacement:"" text in
  if String.length text > maxlen then String.sub text 0 maxlen else text

(* ================================================================ *)
(* Slice: terminal_ui (curses_ui.py)                                *)
(* ================================================================ *)

let is_word_boundary_char c = c = '-' || c = '_' || c = '/' || c = '.' || c = ' '

let is_boundary target index =
  if index = 0 then true
  else
    let prev = target.[index - 1] in
    if is_word_boundary_char prev then true
    else
      let cur = target.[index] in
      Char.lowercase_ascii prev = prev && Char.lowercase_ascii cur <> cur && Char.uppercase_ascii cur = cur

let token_score ~orig ~lower ~token =
  let score = ref 0.0 in
  let prev = ref (-1) in
  let search_from = ref 0 in
  let positions = ref [] in
  let ok = ref true in
  String.iter
    (fun ch ->
      if !ok then
        match String.index_from_opt lower !search_from ch with
        | None -> ok := false
        | Some idx ->
            positions := idx :: !positions;
            score := !score +. 1.0;
            if !prev >= 0 && idx = !prev + 1 then score := !score +. 5.0
            else if !prev >= 0 then score := !score -. float_of_int (min (idx - !prev - 1) 3);
            if is_boundary orig idx then score := !score +. 3.0;
            if idx = 0 then score := !score +. 5.0;
            prev := idx;
            search_from := idx + 1)
    token;
  if not !ok then None
  else begin
    let positions = List.rev !positions in
    (match positions with
    | first :: _ when first = 0 && List.nth positions (List.length positions - 1) = List.length positions - 1 ->
        score := !score +. 8.0
    | _ -> ());
    if lower = token then score := !score +. 20.0;
    score := !score -. (float_of_int (String.length lower) *. 0.01);
    Some !score
  end

let fuzzy_score ~label ~query =
  let lower_label = lower label in
  let tokens = split_whitespace (lower query) in
  if tokens = [] then Some 0.0
  else begin
    let rec go total = function
      | [] -> Some total
      | token :: rest -> (
          match token_score ~orig:label ~lower:lower_label ~token with
          | None -> None
          | Some s -> go (total +. s) rest)
    in
    go 0.0 tokens
  end

let filter_indices items query =
  let q = strip query in
  if q = "" then List.mapi (fun i _ -> i) items
  else begin
    let scored = ref [] in
    List.iteri
      (fun i label ->
        match fuzzy_score ~label ~query:q with Some score -> scored := (i, score) :: !scored | None -> ())
      items;
    let scored = List.rev !scored in
    let sorted =
      List.stable_sort
        (fun (i1, s1) (i2, s2) -> if s1 <> s2 then compare s2 s1 else compare i1 i2)
        scored
    in
    List.map fst sorted
  end

let reconcile_cursor filtered cursor =
  match filtered with
  | [] -> (cursor, 0)
  | first :: _ ->
      let cursor = if List.mem cursor filtered then cursor else first in
      let rec index_of i = function [] -> 0 | x :: rest -> if x = cursor then i else index_of (i + 1) rest in
      (cursor, index_of 0 filtered)

let move_filtered_cursor filtered cursor cursor_pos delta =
  match filtered with
  | [] -> cursor
  | _ ->
      let n = List.length filtered in
      List.nth filtered (floored_mod (cursor_pos + delta) n)

let scroll_for_cursor ~scroll_offset ~cursor_pos ~visible_rows ~total_rows =
  let visible_rows = max 1 visible_rows in
  let scroll_offset =
    if cursor_pos < scroll_offset then cursor_pos
    else if cursor_pos >= scroll_offset + visible_rows then cursor_pos - visible_rows + 1
    else scroll_offset
  in
  max 0 (min scroll_offset (max 0 (total_rows - visible_rows)))

let radio_item_plain (item : Yojson.Safe.t) =
  match item with
  | `String s -> s
  | `List parts ->
      String.concat "" (List.filter_map (function `List (`String text :: _) -> Some text | _ -> None) parts)
  | _ -> ""

(* ================================================================ *)
(* Slice: approval_prompts (approvals_suggest.py)                   *)
(* ================================================================ *)

let has_allowlist_shell_operator command =
  contains ~needle:"\n" command
  || contains ~needle:"&&" command
  || contains ~needle:"||" command
  || String.exists (fun c -> c = ';' || c = '&' || c = '|' || c = '<' || c = '>' || c = '`') command
  || contains ~needle:"$(" command

let unsafe_root_binaries =
  [ "rm"; "rmdir"; "unlink"; "shred"; "dd"; "fdisk"; "parted"; "wipefs"; "sudo"; "doas"; "su"; "chmod";
    "chown"; "chgrp"; "kill"; "killall"; "pkill"; "halt"; "shutdown"; "reboot"; "poweroff"; "init";
    "del"; "format"; "truncate"; "mkswap" ]

let unsafe_root_binary token =
  let tok = lower (last_segment '/' token) in
  List.mem tok unsafe_root_binaries || starts_with "mkfs" tok

let derive_glob normalized =
  if has_allowlist_shell_operator normalized then None
  else
    match split_whitespace normalized with
    | [] -> None
    | first :: rest ->
        if unsafe_root_binary first then None
        else (
          match rest with
          | [] -> Some first
          | second :: _ ->
              if starts_with "-" second || String.exists (fun c -> c = '*' || c = '?' || c = '[' || c = '$') second
              then Some (first ^ " *")
              else Some (first ^ " " ^ second ^ " *"))

let parse_apply_indices ~spec ~total =
  let parts = String.split_on_char ',' spec in
  let indices = ref [] in
  let error = ref None in
  List.iter
    (fun part ->
      if !error = None then begin
        let part = strip part in
        if part <> "" then
          match python_int_of_string part with
          | None ->
              error := Some (Printf.sprintf "invalid selection %s — expected numbers like 1,3" (py_repr part))
          | Some n ->
              if n < 1 || n > total then
                error := Some (Printf.sprintf "selection %d out of range (1..%d)" n total)
              else if not (List.mem (n - 1) !indices) then indices := !indices @ [ n - 1 ]
      end)
    parts;
  match !error with
  | Some e -> Error e
  | None -> if !indices = [] then Error "no valid selections in --apply" else Ok !indices

let is_word_char c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_'

(* Python \b is Unicode-\w-aware; this checks ASCII word chars only, the
   module's usual disclosed scope. *)
let contains_word ~word text =
  let wlen = String.length word and tlen = String.length text in
  let rec scan i =
    if i + wlen > tlen then false
    else
      let hit = String.sub text i wlen = word in
      let left_ok = i = 0 || not (is_word_char text.[i - 1]) in
      let right_ok = i + wlen = tlen || not (is_word_char text.[i + wlen]) in
      (hit && left_ok && right_ok) || scan (i + 1)
  in
  scan 0

let has_kill_process_pattern text = contains ~needle:"kill process" text || contains ~needle:"kill all process" text

(* "shell" + any single non-newline byte + "rc" -- the frozen pattern's `.`
   (any-char-except-newline) between two literal fragments. *)
let has_shell_dot_rc text =
  let n = String.length text in
  let rec scan i =
    if i + 5 + 1 + 2 > n then false
    else if String.sub text i 5 = "shell" && text.[i + 5] <> '\n' && String.sub text (i + 6) 2 = "rc" then true
    else scan (i + 1)
  in
  scan 0

(* The 36-entry pattern list, read directly from tools/approval.py:55-92
   (verified by count against the frozen source, not the survey's prose
   summary). Joined with `|` and IGNORECASE in the frozen reference; each
   is a plain case-insensitive substring test here except the 8 \b-bounded
   words, the "kill (?:all )?process" alternation, and "shell.rc"'s
   any-char wildcard, handled above. For a pure boolean OR-of-alternatives
   result, alternation-priority order does not change the outcome. *)
let is_unsafe_class description =
  let text = lower description in
  contains ~needle:"delete" text
  || contains_word ~word:"rm" text
  || contains ~needle:"destro" text
  || contains ~needle:"wipe" text
  || contains ~needle:"format" text
  || contains_word ~word:"disk" text
  || contains ~needle:"block device" text
  || contains ~needle:"fork bomb" text
  || has_kill_process_pattern text
  || contains ~needle:"kill all" text
  || contains ~needle:"self-termination" text
  || contains_word ~word:"sudo" text
  || contains ~needle:"privilege" text
  || contains ~needle:"credential" text
  || contains_word ~word:"ssh" text
  || has_shell_dot_rc text
  || contains ~needle:"system config" text
  || contains ~needle:"system file" text
  || contains_word ~word:"sql" text
  || contains_word ~word:"chown" text
  || contains_word ~word:"chmod" text
  || contains ~needle:"writable" text
  || contains ~needle:"overwrite" text
  || contains ~needle:"in-place edit" text
  || contains ~needle:"pipe" text
  || contains ~needle:"obfuscation" text
  || contains ~needle:"remote content" text
  || contains ~needle:"remote script" text
  || contains ~needle:"heredoc" text
  || contains ~needle:"encoded" text
  || contains ~needle:"command substitution" text
  || contains ~needle:"process substitution" text
  || contains_word ~word:"dd" text
  || contains ~needle:"shutdown" text
  || contains ~needle:"reboot" text
  || contains ~needle:"hardline" text

(* ================================================================ *)
(* Slice: shell_passthrough (bang_shell.py, clipboard.py)           *)
(* ================================================================ *)

let is_bang_command (text : Yojson.Safe.t) =
  match text with `String s -> starts_with "!" (strip s) | _ -> false

let parse_bang_command (text : Yojson.Safe.t) =
  match text with
  | `String s ->
      let stripped = strip s in
      if starts_with "!" stripped then strip (String.sub stripped 1 (String.length stripped - 1)) else ""
  | _ -> ""

let is_remote_shell_session env =
  let get k = match List.assoc_opt k env with Some v -> v | None -> "" in
  get "SSH_CONNECTION" <> "" || get "SSH_TTY" <> "" || get "SSH_CLIENT" <> ""

let powershell_write_script b64 =
  "Set-Clipboard -Value ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('" ^ b64
  ^ "')))"
