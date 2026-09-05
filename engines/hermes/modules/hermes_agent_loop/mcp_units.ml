(* mcp units, reproduced faithfully from the frozen tools/mcp_tool.py,
   tools/mcp_schema_cache.py, tools/schema_sanitizer.py, tools/mcp_oauth.py,
   tools/mcp_oauth_manager.py, hermes_cli/mcp_config.py,
   hermes_cli/mcp_catalog.py, mcp_serve.py and hermes_cli/mcp_security.py
   (each read completely via a parallel survey of the whole family before
   writing a line of candidate code). Parity is measured by the mcp.*
   scenarios, never assumed.

   ASCII-scoped, matching this session's established convention: Python's
   str.lower/.upper/.strip and \w are Unicode-aware; the functions below use
   ASCII-only case folding, whitespace and word-char sets. Divergence is
   possible only for non-ASCII input, which none of the fixtures exercise.

   Excluded, disclosed here rather than silently dropped:
     - Everything stateful in mcp_tool.py (MCPServerTask, SamplingHandler,
       ElicitationHandler), mcp_oauth.py's callback HTTP server and
       HermesTokenStorage, mcp_oauth_manager.py's MCPOAuthManager,
       mcp_config.py/mcp_catalog.py's prompts/config.yaml/git-clone I/O,
       mcp_stdio_watchdog.py and mcp_startup.py (no pure core in either,
       confirmed by reading both files in full), EventBridge in
       mcp_serve.py, and hermes_tools_mcp_server.py's _signature_from_schema
       (returns a live inspect.Signature object, not plain data).
     - config_fingerprint's ensure_ascii=true escaping: Python's json.dumps
       defaults to escaping non-ASCII bytes as \uXXXX; this candidate emits
       UTF-8 literally. Divergence is possible only for non-ASCII
       command/args/url content, which the fixtures avoid.
     - _mcp_resource_filename / _mcp_image_extension_for_mime_type: both
       fall back to Python's mimetypes.guess_extension, which lazily reads
       /etc/mime.types and can differ by host -- the same hazard class as
       clock/random.
     - _row_to_index_entry's created_at/updated_at: the frozen _iso reads
       the local timezone via datetime.fromtimestamp with no tz argument;
       the reference adapter pins TZ=UTC before calling this op so the
       differential is meaningful, and this candidate implements pure-UTC
       epoch<->ISO conversion accordingly (whole seconds only; a fractional-
       second timestamp's microseconds are not replicated).
     - _validate_remote_mcp_url: signals failure via a raised exception
       rather than a return value in the frozen reference; out of scope as
       a differential candidate without redesigning its error channel.
     - _apply_mcp_preset: mutates its input dict AND returns a separate
       tuple, a mutation-aliasing convention this port does not carry. *)

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
      end
      else begin
        Buffer.add_char buf s.[!i];
        incr i
      end
    done;
    Buffer.contents buf
  end

let is_alnum_underscore c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_'
let is_word_char = is_alnum_underscore

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

(* order-preserving assoc "set": update value in place if the key already
   exists, append at the end if it's new -- mirrors Python's dict[key] =
   value, which is why dict output in this file is insertion-order, not
   sorted (load-bearing for _normalize_mcp_input_schema below). *)
let assoc_set key value fields =
  if List.mem_assoc key fields then List.map (fun (k, v) -> if k = key then (k, value) else (k, v)) fields
  else fields @ [ (key, value) ]

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
        end
        else if c = '_' then begin
          if (not !prev_was_digit) || !prev_was_underscore then valid := false;
          prev_was_digit := false;
          prev_was_underscore := true
        end
        else valid := false
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
(* Slice: mcp_client (mcp_tool.py, mcp_schema_cache.py, schema_sanitizer.py) *)
(* ================================================================ *)

let rec rewrite_local_refs (node : Yojson.Safe.t) : Yojson.Safe.t =
  match node with
  | `Assoc fields ->
      let normalized =
        List.map
          (fun (key, value) ->
            if key = "properties" || key = "patternProperties" then
              match value with
              | `Assoc props -> (key, `Assoc (List.map (fun (pn, ps) -> (pn, rewrite_local_refs ps)) props))
              | other -> (key, rewrite_local_refs other)
            else
              let out_key = if key = "definitions" then "$defs" else key in
              (out_key, rewrite_local_refs value))
          fields
      in
      let normalized =
        match List.assoc_opt "$ref" normalized with
        | Some (`String r) when starts_with "#/definitions/" r ->
            let prefix_len = String.length "#/definitions/" in
            let suffix = String.sub r prefix_len (String.length r - prefix_len) in
            assoc_set "$ref" (`String ("#/$defs/" ^ suffix)) normalized
        | _ -> normalized
      in
      `Assoc normalized
  | `List items -> `List (List.map rewrite_local_refs items)
  | other -> other

let rec strip_nullable_unions ?(keep_nullable_hint = true) (node : Yojson.Safe.t) : Yojson.Safe.t =
  match node with
  | `List items -> `List (List.map (strip_nullable_unions ~keep_nullable_hint) items)
  | `Assoc fields ->
      let stripped = List.map (fun (k, v) -> (k, strip_nullable_unions ~keep_nullable_hint v)) fields in
      let try_collapse key =
        match List.assoc_opt key stripped with
        | Some (`List variants) ->
            let non_null =
              List.filter
                (function `Assoc vf -> List.assoc_opt "type" vf <> Some (`String "null") | _ -> true)
                variants
            in
            if List.length non_null = 1 && List.length non_null <> List.length variants then begin
              let base_fields = match List.hd non_null with `Assoc f -> f | _ -> [] in
              let replacement =
                if keep_nullable_hint && not (List.mem_assoc "nullable" base_fields) then
                  assoc_set "nullable" (`Bool true) base_fields
                else base_fields
              in
              let replacement =
                List.fold_left
                  (fun acc meta_key ->
                    match List.assoc_opt meta_key stripped with
                    | Some meta_value when not (List.mem_assoc meta_key acc) ->
                        if meta_key = "default" && List.mem_assoc "$ref" acc then acc
                        else assoc_set meta_key meta_value acc
                    | _ -> acc)
                  replacement [ "title"; "description"; "default"; "examples" ]
              in
              Some (strip_nullable_unions ~keep_nullable_hint (`Assoc replacement))
            end
            else None
        | _ -> None
      in
      (match try_collapse "anyOf" with
      | Some result -> result
      | None -> ( match try_collapse "oneOf" with Some result -> result | None -> `Assoc stripped))
  | other -> other

let rec repair_object_shape (node : Yojson.Safe.t) : Yojson.Safe.t =
  match node with
  | `List items -> `List (List.map repair_object_shape items)
  | `Assoc fields ->
      let repaired = List.map (fun (k, v) -> (k, repair_object_shape v)) fields in
      let has_type = match List.assoc_opt "type" repaired with Some v -> json_truthy v | None -> false in
      let repaired =
        if (not has_type) && (List.mem_assoc "properties" repaired || List.mem_assoc "required" repaired)
        then assoc_set "type" (`String "object") repaired
        else repaired
      in
      let is_object_type = List.assoc_opt "type" repaired = Some (`String "object") in
      let repaired =
        if is_object_type then
          match List.assoc_opt "properties" repaired with
          | Some (`Assoc _) -> repaired
          | _ -> assoc_set "properties" (`Assoc []) repaired
        else repaired
      in
      let repaired =
        if is_object_type then
          match List.assoc_opt "required" repaired with
          | Some (`List required) ->
              let props = match List.assoc_opt "properties" repaired with Some (`Assoc p) -> p | _ -> [] in
              let valid = List.filter (function `String r -> List.mem_assoc r props | _ -> false) required in
              if List.length valid <> List.length required then
                if valid <> [] then assoc_set "required" (`List valid) repaired
                else List.filter (fun (k, _) -> k <> "required") repaired
              else repaired
          | _ -> repaired
        else repaired
      in
      `Assoc repaired
  | other -> other

let normalize_mcp_input_schema (schema : Yojson.Safe.t) : Yojson.Safe.t =
  let is_falsy = function `Null -> true | `Assoc [] -> true | _ -> false in
  if is_falsy schema then `Assoc [ ("type", `String "object"); ("properties", `Assoc []) ]
  else
    let normalized = rewrite_local_refs schema in
    let normalized = strip_nullable_unions ~keep_nullable_hint:true normalized in
    let normalized = repair_object_shape normalized in
    match normalized with
    | `Assoc fields ->
        if List.assoc_opt "type" fields = Some (`String "object") && not (List.mem_assoc "properties" fields)
        then `Assoc (assoc_set "properties" (`Assoc []) fields)
        else `Assoc fields
    | _ -> `Assoc [ ("type", `String "object"); ("properties", `Assoc []) ]

(* Compact, key-sorted JSON matching Python's json.dumps(sort_keys=True,
   separators=(",", ":")) -- WITHOUT ensure_ascii's \uXXXX escaping of
   non-ASCII bytes (default True in Python); disclosed above. *)
let json_compact_sorted (value : Yojson.Safe.t) : string =
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
        List.iteri (fun i v -> if i > 0 then Buffer.add_char buf ','; go v) items;
        Buffer.add_char buf ']'
    | `Assoc fields ->
        let sorted = List.sort (fun (a, _) (b, _) -> compare a b) fields in
        Buffer.add_char buf '{';
        List.iteri
          (fun i (k, v) ->
            if i > 0 then Buffer.add_char buf ',';
            quote k;
            Buffer.add_char buf ':';
            go v)
          sorted;
        Buffer.add_char buf '}'
    | other -> Buffer.add_string buf (Yojson.Safe.to_string other)
  in
  go value;
  Buffer.contents buf

let config_fingerprint (config : Yojson.Safe.t) =
  let field name = match config with `Assoc f -> List.assoc_opt name f | _ -> None in
  let or_empty_list = function Some (`List l) -> `List l | _ -> `List [] in
  let tools_filter = match field "tools" with Some (`Assoc f) -> f | _ -> [] in
  let sorted_strings key =
    match List.assoc_opt key tools_filter with
    | Some (`List items) ->
        let strs = List.filter_map (function `String s -> Some s | _ -> None) items in
        `List (List.map (fun s -> `String s) (List.sort compare strs))
    | _ -> `List []
  in
  let payload =
    `Assoc
      [ ("command", Option.value (field "command") ~default:`Null);
        ("args", or_empty_list (field "args"));
        ("url", Option.value (field "url") ~default:`Null);
        ("transport", Option.value (field "transport") ~default:`Null);
        ("tools_include", sorted_strings "include");
        ("tools_exclude", sorted_strings "exclude") ]
  in
  let raw = json_compact_sorted payload in
  let digest = Memory_units.system_prompt_hash raw in
  String.sub digest 0 16

let normalize_name_filter (value : Yojson.Safe.t) : string list =
  match value with
  | `Null -> []
  | `String s -> [ s ]
  | `List items -> List.map python_str items
  | _ -> []

(* fnmatch.fnmatchcase glob semantics: * = any run (incl none), ? = one
   char, [seq] = one char in seq, [!seq] = negation with '!', NOT '^' like
   regex -- a real porting trap, flagged by the survey. *)
let fnmatch_case pattern text =
  let plen = String.length pattern and tlen = String.length text in
  let rec match_at pi ti =
    if pi = plen then ti = tlen
    else
      match pattern.[pi] with
      | '*' ->
          let rec try_from j = match_at (pi + 1) j || (j < tlen && try_from (j + 1)) in
          try_from ti
      | '?' -> ti < tlen && match_at (pi + 1) (ti + 1)
      | '[' -> (
          let close =
            let rec find j = if j >= plen then None else if pattern.[j] = ']' && j > pi + 1 then Some j else find (j + 1) in
            find (pi + 1)
          in
          match close with
          | None -> ti < tlen && pattern.[pi] = text.[ti] && match_at (pi + 1) (ti + 1)
          | Some close_idx ->
              ti < tlen
              &&
              let negate = pattern.[pi + 1] = '!' in
              let set_start = if negate then pi + 2 else pi + 1 in
              let in_set =
                let rec scan j =
                  if j >= close_idx then false
                  else if j + 2 < close_idx && pattern.[j + 1] = '-' then
                    (text.[ti] >= pattern.[j] && text.[ti] <= pattern.[j + 2]) || scan (j + 3)
                  else text.[ti] = pattern.[j] || scan (j + 1)
                in
                scan set_start
              in
              let matched = if negate then not in_set else in_set in
              matched && match_at (close_idx + 1) (ti + 1))
      | c -> ti < tlen && text.[ti] = c && match_at (pi + 1) (ti + 1)
  in
  match_at 0 0

let matches_name_filter ~tool_name (patterns : Yojson.Safe.t) =
  let patterns = normalize_name_filter patterns in
  if patterns = [] then false
  else if List.mem tool_name patterns then true
  else
    List.exists
      (fun p -> (contains ~needle:"*" p || contains ~needle:"?" p || contains ~needle:"[" p) && fnmatch_case p tool_name)
      patterns

let mcp_tool_name_prefix = "mcp__"
let mcp_name_delim = "__"

let sanitize_mcp_name_component value =
  let buf = Buffer.create (String.length value) in
  String.iter (fun c -> Buffer.add_char buf (if is_alnum_underscore c then c else '_')) value;
  Buffer.contents buf

let mcp_prefixed_tool_name ~server_name ~tool_name =
  mcp_tool_name_prefix ^ sanitize_mcp_name_component server_name ^ mcp_name_delim ^ sanitize_mcp_name_component tool_name

(* ================================================================ *)
(* Slice: mcp_oauth (mcp_oauth.py, mcp_oauth_manager.py)             *)
(* ================================================================ *)

let figma_dcr_client_name = "Claude Code"
let figma_default_scope = "mcp:connect"

let is_figma_remote_mcp ~server_name ~server_url =
  let url = lower (Option.value server_url ~default:"") in
  let name = lower (Option.value server_name ~default:"") in
  if contains ~needle:"mcp.figma.com" url || contains ~needle:"figma.com/mcp" url then true
  else contains ~needle:"figma" name && (url = "" || contains ~needle:"figma" url)

let humanize_oauth_registration_error ~server_name ~exc ~server_url =
  let msg = exc in
  let lowered = lower msg in
  if (not (contains ~needle:"403" msg)) && not (contains ~needle:"forbidden" lowered) then None
  else
    let looks_like_registration =
      contains ~needle:"regist" lowered || contains ~needle:"client registration" lowered
      || contains ~needle:"dcr" lowered || contains ~needle:"dynamic client" lowered
      || List.mem (strip lowered) [ "forbidden"; "403 forbidden"; "http 403: forbidden" ]
      || (contains ~needle:"403" msg && contains ~needle:"forbidden" lowered)
    in
    if not looks_like_registration then None
    else if is_figma_remote_mcp ~server_name:(Some server_name) ~server_url then
      Some
        (Printf.sprintf
           "'%s' is Figma's remote MCP — DCR is allowlisted by exact client_name (\"%s\" and \"Codex\" work; \
            most other names 403). Hermes defaults to client_name: %s automatically. If you set \
            oauth.client_name yourself, change it to one of those, or clear it and re-run:\n\
           \  hermes mcp login %s"
           server_name figma_dcr_client_name (py_repr figma_dcr_client_name) server_name)
    else
      Some
        (Printf.sprintf
           "'%s' only allows pre-approved OAuth clients — it rejected client registration (403), so no \
            browser flow can start. Options: set oauth.client_name to a name the provider allowlists, add a \
            pre-registered client (oauth: {client_id: ..., client_secret: ...}), or use the provider's \
            stdio / API-key / local server instead."
           server_name)

let apply_oauth_provider_defaults ~cfg ~server_name ~server_url =
  if is_figma_remote_mcp ~server_name:(Some server_name) ~server_url then begin
    let fields = match cfg with `Assoc f -> f | _ -> [] in
    let get k fs = Option.value (List.assoc_opt k fs) ~default:`Null in
    let fields =
      if not (json_truthy (get "client_name" fields)) then
        assoc_set "client_name" (`String figma_dcr_client_name) fields
      else fields
    in
    let fields =
      if not (json_truthy (get "scope" fields)) then assoc_set "scope" (`String figma_default_scope) fields
      else fields
    in
    let fields =
      if not (json_truthy (get "token_endpoint_auth_method" fields)) then
        assoc_set "token_endpoint_auth_method" (`String "client_secret_post") fields
      else fields
    in
    `Assoc fields
  end
  else cfg

let safe_filename name =
  let buf = Buffer.create (String.length name) in
  String.iter (fun c -> Buffer.add_char buf (if is_alnum_underscore c || c = '-' then c else '_')) name;
  let cleaned = strip_charset "_" (Buffer.contents buf) in
  let truncated = if String.length cleaned > 128 then String.sub cleaned 0 128 else cleaned in
  if truncated = "" then "default" else truncated

(* Minimal scheme://netloc/path splitter, sufficient for well-formed MCP
   OAuth endpoint URLs -- not a general URI parser. *)
let url_split url =
  match String.index_opt url ':' with
  | None -> ("", "", url)
  | Some colon_idx ->
      let scheme = String.sub url 0 colon_idx in
      let rest = String.sub url (colon_idx + 1) (String.length url - colon_idx - 1) in
      if starts_with "//" rest then begin
        let after_slashes = String.sub rest 2 (String.length rest - 2) in
        let n = String.length after_slashes in
        let netloc_end =
          let rec find i = if i >= n then n else if after_slashes.[i] = '/' || after_slashes.[i] = '?' || after_slashes.[i] = '#' then i else find (i + 1) in
          find 0
        in
        let netloc = String.sub after_slashes 0 netloc_end in
        let rest2 = String.sub after_slashes netloc_end (n - netloc_end) in
        let rest2_len = String.length rest2 in
        let path_end =
          let rec find i = if i >= rest2_len then rest2_len else if rest2.[i] = '?' || rest2.[i] = '#' then i else find (i + 1) in
          find 0
        in
        (scheme, netloc, String.sub rest2 0 path_end)
      end
      else (scheme, "", rest)

(* Python's urlsplit lowercases `scheme` internally; the frozen code relies
   on that and only explicitly .lower()s netloc. This hand-rolled splitter
   doesn't lowercase at parse time, so both sides are lowered here instead
   -- same net comparison result. *)
let same_endpoint a b =
  let scheme_a, netloc_a, path_a = url_split a in
  let scheme_b, netloc_b, path_b = url_split b in
  lower scheme_a = lower scheme_b
  && lower netloc_a = lower netloc_b
  && rstrip_charset "/" path_a = rstrip_charset "/" path_b

(* ================================================================ *)
(* Slice: mcp_configuration (mcp_config.py, mcp_catalog.py)          *)
(* ================================================================ *)

let strip_bearer_prefix token =
  let stripped = strip token in
  if String.length stripped >= 7 && lower (String.sub stripped 0 7) = "bearer " then
    strip (String.sub stripped 7 (String.length stripped - 7))
  else stripped

let env_var_name_re_ok key =
  let key = if ends_with "\n" key then String.sub key 0 (String.length key - 1) else key in
  String.length key > 0
  && (let c = key.[0] in (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c = '_')
  && String.for_all is_alnum_underscore key

let split_first_eq text =
  match String.index_opt text '=' with
  | None -> None
  | Some idx -> Some (String.sub text 0 idx, String.sub text (idx + 1) (String.length text - idx - 1))

let parse_env_assignments raw_env =
  let rec go acc = function
    | [] -> Ok acc
    | item :: rest -> (
        let text = strip item in
        if text = "" then go acc rest
        else
          match split_first_eq text with
          | None -> Error (Printf.sprintf "Invalid --env value %s (expected KEY=VALUE)" (py_repr text))
          | Some (key, value) -> (
              let key = strip key in
              if key = "" then Error (Printf.sprintf "Invalid --env value %s (missing variable name)" (py_repr text))
              else if not (env_var_name_re_ok key) then
                Error (Printf.sprintf "Invalid --env variable name %s" (py_repr key))
              else go (assoc_set key value acc) rest))
  in
  go [] raw_env

let install_dir_var = "${INSTALL_DIR}"

let expand_install_dir ~value ~install_dir =
  if not (contains ~needle:install_dir_var value) then Ok value
  else
    match install_dir with
    | None -> Error (Printf.sprintf "manifest references %s but no install block exists" install_dir_var)
    | Some dir -> Ok (replace_all ~needle:install_dir_var ~replacement:dir value)

let env_key_for_server name =
  let upper = String.uppercase_ascii name in
  let buf = Buffer.create (String.length upper) in
  String.iter (fun c -> Buffer.add_char buf (if is_alnum_underscore c then c else '_')) upper;
  "MCP_" ^ strip_charset "_" (Buffer.contents buf) ^ "_API_KEY"

let bearer_auth_headers name = [ ("Authorization", "Bearer ${" ^ env_key_for_server name ^ "}") ]

(* Only exercised where install_dir resolution succeeds; expand_install_dir
   is separately, directly testable for its own error path. *)
let build_server_config ~transport_type ~command ~args ~env ~url ~auth_type ~name ~install_dir =
  let resolve v = match expand_install_dir ~value:v ~install_dir with Ok r -> r | Error _ -> v in
  match transport_type with
  | "stdio" ->
      let cfg = [ ("command", `String (resolve (Option.value command ~default:""))) ] in
      let cfg = match args with [] -> cfg | args -> cfg @ [ ("args", `List (List.map (fun a -> `String (resolve a)) args)) ] in
      let cfg = match env with [] -> cfg | env -> cfg @ [ ("env", `Assoc (List.map (fun (k, v) -> (k, `String v)) env)) ] in
      `Assoc cfg
  | "http" ->
      let cfg = [ ("url", `String (Option.value url ~default:"")) ] in
      let cfg =
        if auth_type = "oauth" then cfg @ [ ("auth", `String "oauth") ]
        else if auth_type = "api_key" then
          cfg @ [ ("headers", `Assoc (List.map (fun (k, v) -> (k, `String v)) (bearer_auth_headers name))) ]
        else cfg
      in
      `Assoc cfg
  | _ -> `Assoc []

(* ================================================================ *)
(* Slice: mcp_server_surface (mcp_serve.py)                          *)
(* ================================================================ *)

let extract_message_content (msg : Yojson.Safe.t) : string =
  let content = match msg with `Assoc f -> Option.value (List.assoc_opt "content" f) ~default:(`String "") | _ -> `String "" in
  match content with
  | `List parts ->
      let text_parts =
        List.filter_map
          (function
            | `Assoc pf when List.assoc_opt "type" pf = Some (`String "text") -> (
                match List.assoc_opt "text" pf with Some (`String t) -> Some t | _ -> Some "")
            | _ -> None)
          parts
      in
      String.concat "\n" text_parts
  | other -> if json_truthy other then python_str other else ""

let find_media_tags text =
  let n = String.length text in
  let results = ref [] in
  let i = ref 0 in
  while !i < n do
    if !i + 6 <= n && String.sub text !i 6 = "MEDIA:" then begin
      let j = ref (!i + 6) in
      while !j < n && is_ws text.[!j] do incr j done;
      let start = !j in
      while !j < n && not (is_ws text.[!j]) do incr j done;
      if !j > start then begin
        results := `Assoc [ ("type", `String "media"); ("path", `String (String.sub text start (!j - start))) ] :: !results;
        i := !j
      end
      else incr i
    end
    else incr i
  done;
  List.rev !results

let extract_attachments (msg : Yojson.Safe.t) : Yojson.Safe.t list =
  let fields = match msg with `Assoc f -> f | _ -> [] in
  let content = Option.value (List.assoc_opt "content" fields) ~default:(`String "") in
  let from_parts =
    match content with
    | `List parts ->
        List.filter_map
          (function
            | `Assoc pf ->
                let ptype = match List.assoc_opt "type" pf with Some (`String t) -> t | _ -> "" in
                if ptype = "image_url" then
                  let url =
                    match List.assoc_opt "image_url" pf with
                    | Some (`Assoc iu) -> ( match List.assoc_opt "url" iu with Some (`String u) -> u | _ -> "")
                    | _ -> ""
                  in
                  if url <> "" then Some (`Assoc [ ("type", `String "image"); ("url", `String url) ]) else None
                else if ptype = "image" then
                  let url =
                    match List.assoc_opt "url" pf with
                    | Some (`String u) -> u
                    | Some _ -> ""
                    | None -> (
                        match List.assoc_opt "source" pf with
                        | Some (`Assoc src) -> ( match List.assoc_opt "url" src with Some (`String u) -> u | _ -> "")
                        | _ -> "")
                  in
                  if url <> "" then Some (`Assoc [ ("type", `String "image"); ("url", `String url) ]) else None
                else if ptype <> "text" then Some (`Assoc [ ("type", `String ptype); ("data", `Assoc pf) ])
                else None
            | _ -> None)
          parts
    | _ -> []
  in
  let text = extract_message_content msg in
  let from_media = if text = "" then [] else find_media_tags text in
  from_parts @ from_media

(* Pure-UTC epoch<->ISO conversion; whole seconds only (see module header). *)
let iso_of_epoch_utc seconds =
  let tm = Unix.gmtime seconds in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d" (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

let iso_of_ts (ts : Yojson.Safe.t) : string =
  if not (json_truthy ts) then ""
  else
    match (match ts with `Int n -> Some (float_of_int n) | `Float f -> Some f | _ -> None) with
    | None -> ""
    | Some seconds -> ( try iso_of_epoch_utc seconds with _ -> "")

let row_to_index_entry (row : Yojson.Safe.t) : Yojson.Safe.t =
  let fields = match row with `Assoc f -> f | _ -> [] in
  let get k = Option.value (List.assoc_opt k fields) ~default:`Null in
  let origin_from_json =
    match get "origin_json" with
    | `String s when s <> "" -> ( try Some (Yojson.Safe.from_string s) with _ -> None)
    | _ -> None
  in
  let origin =
    match origin_from_json with
    | Some (`Assoc (_ :: _) as o) -> o
    | _ ->
        `Assoc
          [ ("platform", get "source"); ("chat_id", get "chat_id"); ("chat_type", get "chat_type");
            ("thread_id", get "thread_id"); ("user_id", get "user_id") ]
  in
  let origin_fields = match origin with `Assoc f -> f | _ -> [] in
  let int_of_field k =
    match get k with
    | `Int n -> n
    | `Float f -> int_of_float f
    | `Bool b -> if b then 1 else 0
    | _ -> 0
  in
  let input_tokens = int_of_field "input_tokens" in
  let output_tokens = int_of_field "output_tokens" in
  let chat_type =
    match get "chat_type" with
    | `String s when s <> "" -> `String s
    | _ -> Option.value (List.assoc_opt "chat_type" origin_fields) ~default:(`String "")
  in
  let display_name =
    match get "display_name" with
    | `String s when s <> "" -> `String s
    | _ -> ( match List.assoc_opt "chat_name" origin_fields with Some (`String s) when s <> "" -> `String s | _ -> `String "")
  in
  let started_at = get "started_at" in
  let last_active_or_started = if json_truthy (get "last_active") then get "last_active" else started_at in
  `Assoc
    [ ("session_id", `String (python_str (get "id")));
      ("session_key", (match get "session_key" with `Null -> `String "" | v -> v));
      ("platform", (match get "source" with `Null -> `String "" | v -> v));
      ("chat_type", chat_type);
      ("display_name", display_name);
      ("origin", origin);
      ("created_at", `String (iso_of_ts started_at));
      ("updated_at", `String (iso_of_ts last_active_or_started));
      ("input_tokens", `Int input_tokens);
      ("output_tokens", `Int output_tokens);
      ("total_tokens", `Int (input_tokens + output_tokens)) ]

(* OCaml's Unix module has gmtime but no timegm (no libc binding exposed);
   Howard Hinnant's days_from_civil, a standard branch-free proleptic-
   Gregorian day count, stands in for it. *)
let days_from_civil y m d =
  let y = if m <= 2 then y - 1 else y in
  let era = (if y >= 0 then y else y - 399) / 400 in
  let yoe = y - (era * 400) in
  let mp = (m + 9) mod 12 in
  let doy = ((153 * mp) + 2) / 5 + d - 1 in
  let doe = (yoe * 365) + (yoe / 4) - (yoe / 100) + doy in
  (era * 146097) + doe - 719468

let parse_iso_to_epoch s =
  Scanf.sscanf s "%d-%d-%dT%d:%d:%d" (fun y mo d h mi se ->
      float_of_int ((days_from_civil y mo d * 86400) + (h * 3600) + (mi * 60) + se))

let ts_float (ts : Yojson.Safe.t) : float =
  match ts with
  | `Int n -> float_of_int n
  | `Float f -> f
  | `String s when s <> "" -> ( match float_of_string_opt s with Some f -> f | None -> ( try parse_iso_to_epoch s with _ -> 0.0))
  | _ -> 0.0

let coerce_int (value : Yojson.Safe.t) ~default ~minimum ~maximum =
  let coerced =
    match value with
    | `Int n -> n
    | `Float f -> int_of_float f
    | `Bool b -> if b then 1 else 0
    | `String s -> ( match python_int_of_string s with Some n -> n | None -> default)
    | _ -> default
  in
  max minimum (min coerced maximum)

(* ================================================================ *)
(* Slice: mcp_supervision (mcp_security.py)                          *)
(* ================================================================ *)

let shell_interpreters =
  [ "bash"; "sh"; "zsh"; "dash"; "fish"; "cmd"; "cmd.exe"; "powershell"; "powershell.exe"; "pwsh"; "pwsh.exe" ]

let ioc_substrings =
  [ "AAAAC3NzaC1lZDI1NTE5AAAAICBoh1oDC4DnsO1m5mJ4yfEKrQebaFh"; "hermes-0day"; "60.165.167."; "118.182.244.156";
    "61.178.123.196" ]

(* shlex.split(text, posix=True) is a real shell lexer; the frozen source
   also branches on os.name for posix=(os.name != "nt"), an ambient
   platform read pinned to posix=True here (this project's actual
   deployment target). Handles single/double quotes and backslash escapes;
   raises-equivalent (falls back to whitespace-split) on unbalanced quotes,
   matching the frozen except ValueError fallback. *)
let shlex_split text =
  let n = String.length text in
  let tokens = ref [] in
  let buf = Buffer.create 16 in
  let has_token = ref false in
  let flush () =
    if !has_token then begin
      tokens := Buffer.contents buf :: !tokens;
      Buffer.clear buf;
      has_token := false
    end
  in
  let i = ref 0 in
  let unbalanced = ref false in
  (try
     while !i < n do
       let c = text.[!i] in
       if is_ws c then begin
         flush ();
         incr i
       end
       else if c = '\'' then begin
         has_token := true;
         incr i;
         let closed = ref false in
         while (not !closed) && !i < n do
           if text.[!i] = '\'' then begin
             closed := true;
             incr i
           end
           else begin
             Buffer.add_char buf text.[!i];
             incr i
           end
         done;
         if not !closed then raise Exit
       end
       else if c = '"' then begin
         has_token := true;
         incr i;
         let closed = ref false in
         while (not !closed) && !i < n do
           if text.[!i] = '"' then begin
             closed := true;
             incr i
           end
           else if text.[!i] = '\\' && !i + 1 < n && (text.[!i + 1] = '"' || text.[!i + 1] = '\\') then begin
             Buffer.add_char buf text.[!i + 1];
             i := !i + 2
           end
           else begin
             Buffer.add_char buf text.[!i];
             incr i
           end
         done;
         if not !closed then raise Exit
       end
       else if c = '\\' && !i + 1 < n then begin
         has_token := true;
         Buffer.add_char buf text.[!i + 1];
         i := !i + 2
       end
       else begin
         has_token := true;
         Buffer.add_char buf c;
         incr i
       end
     done;
     flush ()
   with Exit -> unbalanced := true);
  if !unbalanced then
    List.rev
      (List.filter (fun s -> s <> "")
         (String.split_on_char ' ' (String.map (fun c -> if is_ws c then ' ' else c) text)))
  else List.rev !tokens

let posix_basename path =
  match String.rindex_opt path '/' with
  | Some idx -> String.sub path (idx + 1) (String.length path - idx - 1)
  | None -> path

let command_basename (command : Yojson.Safe.t) =
  let text = strip (match command with `Null -> "" | `String s -> s | other -> python_str other) in
  if text = "" then ""
  else
    let parts = shlex_split text in
    let first = match parts with p :: _ -> p | [] -> text in
    lower (posix_basename first)

let inline_script (args : Yojson.Safe.t) =
  match args with
  | `Null -> ""
  | `List items -> String.concat " " (List.map python_str items)
  | other -> python_str other

let entry_text (entry : Yojson.Safe.t) =
  let fields = match entry with `Assoc f -> f | _ -> [] in
  let command = match List.assoc_opt "command" fields with Some v when json_truthy v -> python_str v | _ -> "" in
  let args_text = inline_script (Option.value (List.assoc_opt "args" fields) ~default:`Null) in
  let env_parts =
    match List.assoc_opt "env" fields with
    | Some (`Assoc env) -> List.map (fun (_, v) -> python_str v) env
    | _ -> []
  in
  String.concat " " (command :: args_text :: env_parts)

let is_word_dot_hyphen c = is_word_char c || c = '.' || c = '-'

(* (?<![\w.-])WORD(?![\w.-]), case-insensitive: neither side of the match
   may be a word/dot/hyphen char. Wider exclusion set than plain \b. *)
let contains_isolated ~word text =
  let wlen = String.length word and tlen = String.length text in
  let word = lower word in
  let rec scan i =
    if i + wlen > tlen then false
    else
      let hit = lower (String.sub text i wlen) = word in
      let left_ok = i = 0 || not (is_word_dot_hyphen text.[i - 1]) in
      let right_ok = i + wlen = tlen || not (is_word_dot_hyphen text.[i + wlen]) in
      (hit && left_ok && right_ok) || scan (i + 1)
  in
  scan 0

(* \bWORD\b, case-insensitive, boundaries checked only against \w
   (word=alnum+underscore) -- '.'/'-' inside WORD are not re-examined. *)
let contains_word_ci ~word text =
  let wlen = String.length word and tlen = String.length text in
  let word = lower word in
  let rec scan i =
    if i + wlen > tlen then false
    else
      let hit = lower (String.sub text i wlen) = word in
      let left_ok = i = 0 || not (is_word_char text.[i - 1]) in
      let right_ok = i + wlen = tlen || not (is_word_char text.[i + wlen]) in
      (hit && left_ok && right_ok) || scan (i + 1)
  in
  scan 0

(* WORD\b -- right boundary only (matches \.env\b, crontab\b, .bashrc\b etc,
   none of which anchor their left edge in the frozen pattern). *)
let ends_with_word_boundary_ci ~word text =
  let wlen = String.length word and tlen = String.length text in
  let word = lower word in
  let rec scan i =
    if i + wlen > tlen then false
    else
      let hit = lower (String.sub text i wlen) = word in
      let right_ok = i + wlen = tlen || not (is_word_char text.[i + wlen]) in
      (hit && right_ok) || scan (i + 1)
  in
  scan 0

let egress_pattern_matches text =
  List.exists (fun tool -> contains_isolated ~word:tool text) [ "curl"; "wget"; "nc"; "ncat"; "socat" ]
  || contains ~needle:"/dev/tcp/" (lower text)
  || contains_word_ci ~word:"Invoke-WebRequest" text
  || contains_word_ci ~word:"Invoke-RestMethod" text
  || contains_word_ci ~word:"System.Net.WebClient" text

(* \b-X\s+POST\b: \b immediately before a non-word char ('-') holds only
   when the PRECEDING char is a word char -- so "curl -X POST" (space
   before -X) does NOT satisfy this alternative on its own; only something
   like "curl-X POST" would. Reproduced literally, verified empirically
   against the reference rather than "corrected". *)
let contains_dash_x_post text =
  let n = String.length text in
  let rec scan i =
    if i + 2 > n then false
    else if lower (String.sub text i 2) = "-x" && i > 0 && is_word_char text.[i - 1] then begin
      let j = ref (i + 2) in
      let ws_start = !j in
      while !j < n && is_ws text.[!j] do incr j done;
      if !j > ws_start && !j + 4 <= n && lower (String.sub text !j 4) = "post" && (!j + 4 = n || not (is_word_char text.[!j + 4]))
      then true
      else scan (i + 1)
    end
    else scan (i + 1)
  in
  scan 0

let has_lt_then_token text =
  let n = String.length text in
  let rec scan i =
    if i >= n then false
    else if text.[i] = '<' then begin
      let j = ref (i + 1) in
      while !j < n && is_ws text.[!j] do incr j done;
      if !j < n && not (is_ws text.[!j]) then true else scan (i + 1)
    end
    else scan (i + 1)
  in
  scan 0

let exfil_hint_pattern_matches text =
  ends_with_word_boundary_ci ~word:".env" text
  || contains ~needle:"--data-binary" (lower text)
  || contains ~needle:"--data-raw" (lower text)
  || contains_dash_x_post text
  || contains_word_ci ~word:"POST" text
  || has_lt_then_token text

let has_pam_module text =
  let text = lower text in
  let n = String.length text in
  let rec scan i =
    if i + 4 > n then false
    else if String.sub text i 4 = "pam_" then begin
      let j = ref (i + 4) in
      while !j < n && (is_word_char text.[!j] || text.[!j] = '-') do incr j done;
      if !j > i + 4 && !j + 3 <= n && String.sub text !j 3 = ".so" then true else scan (i + 1)
    end
    else scan (i + 1)
  in
  scan 0

let persistence_pattern_matches text =
  contains ~needle:"authorized_keys" (lower text)
  || contains ~needle:".ssh/" (lower text)
  || ends_with_word_boundary_ci ~word:"/etc/ssh" text
  || ends_with_word_boundary_ci ~word:"/etc/pam.d" text
  || has_pam_module text
  || contains ~needle:"/etc/sudoers" (lower text)
  || contains ~needle:"/etc/cron" (lower text)
  || ends_with_word_boundary_ci ~word:"crontab" text
  || contains ~needle:"/etc/rc.local" (lower text)
  || contains ~needle:"/etc/systemd" (lower text)
  || ends_with_word_boundary_ci ~word:".bashrc" text
  || ends_with_word_boundary_ci ~word:".bash_profile" text
  || ends_with_word_boundary_ci ~word:".profile" text
  || ends_with_word_boundary_ci ~word:".zshrc" text

let validate_mcp_server_entry ~name (entry : Yojson.Safe.t) : string list =
  match entry with
  | `Assoc fields -> (
      let flat = entry_text entry in
      match List.find_opt (fun ioc -> contains ~needle:ioc flat) ioc_substrings with
      | Some ioc ->
          [ Printf.sprintf "MCP server '%s' contains a known hermes-0day indicator-of-compromise ('%s')" name ioc ]
      | None -> (
          let command = Option.value (List.assoc_opt "command" fields) ~default:`Null in
          let basename = command_basename command in
          if not (List.mem basename shell_interpreters) then []
          else
            let script = inline_script (Option.value (List.assoc_opt "args" fields) ~default:`Null) in
            if script = "" then []
            else begin
              let command_str = match command with `String s -> s | other -> python_str other in
              let issues = ref [] in
              if egress_pattern_matches script then begin
                let issue =
                  Printf.sprintf "MCP server '%s' uses shell interpreter '%s' with network egress in args" name
                    command_str
                in
                let issue = if exfil_hint_pattern_matches script then issue ^ " and exfiltration-shaped arguments" else issue in
                issues := issue :: !issues
              end;
              if persistence_pattern_matches script then
                issues :=
                  Printf.sprintf
                    "MCP server '%s' uses shell interpreter '%s' to write to an OS persistence surface (SSH \
                     keys / PAM / sudoers / cron / shell rc) — this is the hermes-0day backdoor shape, not a \
                     real MCP server"
                    name command_str
                  :: !issues;
              List.rev !issues
            end))
  | _ -> []

let is_mcp_server_entry_suspicious ~name entry = validate_mcp_server_entry ~name entry <> []
