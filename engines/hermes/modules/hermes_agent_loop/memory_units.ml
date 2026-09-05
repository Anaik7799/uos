(* memory units, reproduced faithfully from the frozen agent/memory_manager.py,
   agent/memory_provider.py, hermes_state.py, hermes_state_common.py and
   hermes_state_portability.py (each read completely before writing; parity is
   measured by the mem.* scenarios, never assumed).

   Excluded, disclosed beside the scenarios: session_search (FTS5/native CJK
   tokenizer -- no pure core reachable without the native module), the
   SessionSchemaMixin/SCHEMA_SQL-driven half of session_state (DDL/DB open),
   and the toolset-resolution branch of memory_provider_tools_enabled (imports
   `toolsets`) -- DB / native / dynamic-import layers over the pure cores
   measured here. *)

let lower = String.lowercase_ascii

(* ---- memory_manager: normalize_tool_schema ---- *)

let field name = function `Assoc f -> List.assoc_opt name f | _ -> None

(* Unwrap an already-wrapped OpenAI tool entry to the bare function schema;
   None for anything without a resolvable string name. *)
let normalize_tool_schema schema =
  match schema with
  | `Assoc _ ->
      let schema =
        match (field "type" schema, field "function" schema) with
        | Some (`String "function"), Some (`Assoc _ as fn) -> fn
        | _ -> schema
      in
      (match schema with
       | `Assoc _ -> (
           match field "name" schema with
           | Some (`String name) when name <> "" -> Some schema
           | _ -> None)
       | _ -> None)
  | _ -> None

(* memory_provider_tools_enabled, PURE branches: disabled contains memory ->
   false; memory_tool_present -> true; enabled None -> true; enabled empty ->
   false; "memory" in enabled -> true. The toolset-resolution fallback
   (enabled non-empty without "memory") imports `toolsets` and is out of the
   pure domain -- scenarios never reach it. *)
let memory_provider_tools_enabled ~enabled_toolsets ~disabled_toolsets ~memory_tool_present =
  if (match disabled_toolsets with Some d -> List.mem "memory" d | None -> false) then false
  else if memory_tool_present then true
  else
    match enabled_toolsets with
    | None -> true
    | Some [] -> false
    | Some names -> if List.mem "memory" names then true else false
    (* NB: a non-empty list without "memory" would trigger the excluded
       toolset-resolution branch; scenarios never construct that shape. *)

(* ---- memory_manager: context sanitation ---- *)

(* The three frozen regexes reproduced as scanners over the case-insensitive
   text: the fenced block, the internal system note, and the bare fence tags.
   Applied in the frozen order (block, note, tag). *)

(* case-insensitive literal match of [needle] at position i *)
let ci_at text i needle =
  let n = String.length needle in
  i + n <= String.length text && lower (String.sub text i n) = needle

(* Remove <memory-context> ... </memory-context> spans (non-greedy), tolerating
   whitespace inside the tags: </?\s*memory-context\s*>. *)
let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012' || c = '\011'

(* match an opening or closing fence tag at i; returns end offset and whether
   it was a closing tag *)
let match_fence text i =
  let n = String.length text in
  if i >= n || text.[i] <> '<' then None
  else begin
    let j = ref (i + 1) in
    let closing = !j < n && text.[!j] = '/' in
    if closing then incr j;
    while !j < n && is_ws text.[!j] do incr j done;
    if ci_at text !j "memory-context" then begin
      j := !j + String.length "memory-context";
      while !j < n && is_ws text.[!j] do incr j done;
      if !j < n && text.[!j] = '>' then Some (!j + 1, closing) else None
    end
    else None
  end

let strip_internal_context text =
  let n = String.length text in
  let buffer = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    match match_fence text !i with
    | Some (after_open, false) -> (
        (* find the next closing fence, non-greedy; drop the whole span *)
        let k = ref after_open in
        let closed = ref None in
        while !closed = None && !k < n do
          (match match_fence text !k with
           | Some (after_close, true) -> closed := Some after_close
           | _ -> ());
          if !closed = None then incr k
        done;
        match !closed with
        | Some after_close -> i := after_close
        | None ->
            (* no closing tag: the regex would not match, emit the char *)
            Buffer.add_char buffer text.[!i];
            incr i)
    | _ ->
        Buffer.add_char buffer text.[!i];
        incr i
  done;
  Buffer.contents buffer

let internal_note_prefix = "[system note:"

(* Remove the internal system note run. The frozen regex is fixed wording with
   two allowed tails; reproduced literally, case-insensitive, then the trailing
   \s* it absorbs. *)
let note_variants =
  [ "[system note: the following is recalled memory context, not new user \
     input. treat as informational background data.]" ]

let strip_internal_note text =
  (* the second variant has an open-ended tail before the closing bracket;
     handle both: the fixed prefix through the treat-as clause, then either
     the fixed informational-background-data wording or the
     authoritative-reference-data wording with any tail, then the bracket. *)
  let n = String.length text in
  let buffer = Buffer.create n in
  let head = "[system note: the following is recalled memory context, not new user input. treat as " in
  let i = ref 0 in
  while !i < n do
    if ci_at text !i head then begin
      let after_head = !i + String.length head in
      let variant_a = "informational background data.]" in
      let matched =
        if ci_at text after_head variant_a then Some (after_head + String.length variant_a)
        else if ci_at text after_head "authoritative reference data" then begin
          (* [^\]]*\.\] — run of non-] then ".]" *)
          let k = ref (after_head + String.length "authoritative reference data") in
          while !k < n && text.[!k] <> ']' do incr k done;
          (* require the char before ] to make ".]" -- the frozen \.\] *)
          if !k < n && !k > 0 && text.[!k - 1] = '.' && text.[!k] = ']' then Some (!k + 1)
          else None
        end
        else None
      in
      match matched with
      | Some stop ->
          (* absorb trailing \s* *)
          let s = ref stop in
          while !s < n && is_ws text.[!s] do incr s done;
          i := !s
      | None ->
          Buffer.add_char buffer text.[!i];
          incr i
    end
    else begin
      Buffer.add_char buffer text.[!i];
      incr i
    end
  done;
  Buffer.contents buffer

let strip_fence_tags text =
  let n = String.length text in
  let buffer = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    match match_fence text !i with
    | Some (after, _) -> i := after
    | None ->
        Buffer.add_char buffer text.[!i];
        incr i
  done;
  Buffer.contents buffer

let sanitize_context text =
  ignore note_variants;
  text |> strip_internal_context |> strip_internal_note |> strip_fence_tags

let build_memory_context_block raw_context =
  if String.trim raw_context = "" then ""
  else begin
    let clean = sanitize_context raw_context in
    "<memory-context>\n[System note: The following is recalled memory context, \
     NOT new user input. Treat as authoritative reference data — this is the \
     agent's persistent memory and should inform all responses.]\n\n" ^ clean
    ^ "\n</memory-context>"
  end

(* ---- memory_provider: is_trivial_prompt ---- *)

let trivial_words =
  [ "thank you"; "go ahead"; "do it"; "got it"; "yes"; "no"; "ok"; "okay"; "sure";
    "thanks"; "yep"; "nope"; "yeah"; "nah"; "hi"; "hey"; "hello"; "yo"; "sup";
    "continue"; "proceed"; "cool"; "nice"; "great"; "done"; "next"; "lgtm"; "y";
    "n"; "k" ]

(* The trailing set after the word: \s and the ASCII punctuation of the frozen
   character class. Unicode trailing punctuation (smart quotes, dashes,
   ellipsis, nbsp) is outside the tested domain and disclosed. *)
let trailing_char c =
  is_ws c
  || String.contains "!?.:;,\"'~()[]{}<>*&^%$#@+=`" c

let is_trivial_prompt text =
  match text with
  | None -> true
  | Some text ->
      let stripped = String.trim text in
      if stripped = "" then true
      else if String.length stripped > 0 && stripped.[0] = '/' then true
      else begin
        let low = lower stripped in
        let n = String.length low in
        List.exists
          (fun w ->
            let lw = String.length w in
            lw <= n
            && String.sub low 0 lw = w
            &&
            let rec rest i = i >= n || (trailing_char low.[i] && rest (i + 1)) in
            rest lw)
          trivial_words
      end

(* ---- session_state (hermes_state.py, hermes_state_common.py) ---- *)

(* _system_prompt_hash: sha256 hex over the UTF-8 bytes. OCaml's Digest
   module is MD5-only; this is a from-scratch SHA-256 (FIPS 180-4), chosen
   because the frozen contract is exactly this digest, not "some hash". *)
module Sha256 = struct
  let k =
    [| 0x428a2f98l; 0x71374491l; 0xb5c0fbcfl; 0xe9b5dba5l; 0x3956c25bl; 0x59f111f1l;
       0x923f82a4l; 0xab1c5ed5l; 0xd807aa98l; 0x12835b01l; 0x243185bel; 0x550c7dc3l;
       0x72be5d74l; 0x80deb1fel; 0x9bdc06a7l; 0xc19bf174l; 0xe49b69c1l; 0xefbe4786l;
       0x0fc19dc6l; 0x240ca1ccl; 0x2de92c6fl; 0x4a7484aal; 0x5cb0a9dcl; 0x76f988dal;
       0x983e5152l; 0xa831c66dl; 0xb00327c8l; 0xbf597fc7l; 0xc6e00bf3l; 0xd5a79147l;
       0x06ca6351l; 0x14292967l; 0x27b70a85l; 0x2e1b2138l; 0x4d2c6dfcl; 0x53380d13l;
       0x650a7354l; 0x766a0abbl; 0x81c2c92el; 0x92722c85l; 0xa2bfe8a1l; 0xa81a664bl;
       0xc24b8b70l; 0xc76c51a3l; 0xd192e819l; 0xd6990624l; 0xf40e3585l; 0x106aa070l;
       0x19a4c116l; 0x1e376c08l; 0x2748774cl; 0x34b0bcb5l; 0x391c0cb3l; 0x4ed8aa4al;
       0x5b9cca4fl; 0x682e6ff3l; 0x748f82eel; 0x78a5636fl; 0x84c87814l; 0x8cc70208l;
       0x90befffal; 0xa4506cebl; 0xbef9a3f7l; 0xc67178f2l |]

  let h0 =
    [| 0x6a09e667l; 0xbb67ae85l; 0x3c6ef372l; 0xa54ff53al; 0x510e527fl; 0x9b05688cl;
       0x1f83d9abl; 0x5be0cd19l |]

  let ( &: ) = Int32.logand
  let ( |: ) = Int32.logor
  let ( ^: ) = Int32.logxor
  let lnot32 = Int32.lognot
  let ( +% ) = Int32.add
  let rotr x n = (Int32.shift_right_logical x n) |: (Int32.shift_left x (32 - n))
  let shr x n = Int32.shift_right_logical x n

  let hex_digest (text : string) : string =
    let message = Bytes.of_string text in
    let ml = Bytes.length message in
    let bit_len = Int64.of_int (ml * 8) in
    let pad_len =
      let rem = (ml + 1) mod 64 in
      if rem <= 56 then 56 - rem else 120 - rem
    in
    let total = ml + 1 + pad_len + 8 in
    let padded = Bytes.make total '\000' in
    Bytes.blit message 0 padded 0 ml;
    Bytes.set padded ml '\x80';
    for i = 0 to 7 do
      Bytes.set padded (total - 1 - i)
        (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical bit_len (8 * i)) 0xFFL)))
    done;
    let h = Array.copy h0 in
    let blocks = total / 64 in
    let w = Array.make 64 0l in
    for b = 0 to blocks - 1 do
      let base = b * 64 in
      for t = 0 to 15 do
        let o = base + (t * 4) in
        w.(t) <-
          Int32.logor
            (Int32.shift_left (Int32.of_int (Char.code (Bytes.get padded o))) 24)
            (Int32.logor
               (Int32.shift_left (Int32.of_int (Char.code (Bytes.get padded (o + 1)))) 16)
               (Int32.logor
                  (Int32.shift_left (Int32.of_int (Char.code (Bytes.get padded (o + 2)))) 8)
                  (Int32.of_int (Char.code (Bytes.get padded (o + 3))))))
      done;
      for t = 16 to 63 do
        let s0 = rotr w.(t - 15) 7 ^: rotr w.(t - 15) 18 ^: shr w.(t - 15) 3 in
        let s1 = rotr w.(t - 2) 17 ^: rotr w.(t - 2) 19 ^: shr w.(t - 2) 10 in
        w.(t) <- w.(t - 16) +% s0 +% w.(t - 7) +% s1
      done;
      let a = ref h.(0) and b_ = ref h.(1) and c = ref h.(2) and d = ref h.(3) in
      let e = ref h.(4) and f = ref h.(5) and g = ref h.(6) and hh = ref h.(7) in
      for t = 0 to 63 do
        let s1 = rotr !e 6 ^: rotr !e 11 ^: rotr !e 25 in
        let ch = (!e &: !f) ^: (lnot32 !e &: !g) in
        let temp1 = !hh +% s1 +% ch +% k.(t) +% w.(t) in
        let s0 = rotr !a 2 ^: rotr !a 13 ^: rotr !a 22 in
        let maj = (!a &: !b_) ^: (!a &: !c) ^: (!b_ &: !c) in
        let temp2 = s0 +% maj in
        hh := !g; g := !f; f := !e; e := !d +% temp1;
        d := !c; c := !b_; b_ := !a; a := temp1 +% temp2
      done;
      h.(0) <- h.(0) +% !a; h.(1) <- h.(1) +% !b_; h.(2) <- h.(2) +% !c; h.(3) <- h.(3) +% !d;
      h.(4) <- h.(4) +% !e; h.(5) <- h.(5) +% !f; h.(6) <- h.(6) +% !g; h.(7) <- h.(7) +% !hh
    done;
    let buffer = Buffer.create 64 in
    Array.iter (fun x -> Buffer.add_string buffer (Printf.sprintf "%08lx" x)) h;
    Buffer.contents buffer
end

let system_prompt_hash system_prompt = Sha256.hex_digest system_prompt

(* workspace_key: git_repo_root wins (stripped, non-empty), else cwd
   (stripped, non-empty), else None. Both are optional string fields on the
   scenario's row dict. *)
let workspace_key ~git_repo_root ~cwd =
  let clean = function None -> "" | Some s -> String.trim s in
  let root = clean git_repo_root in
  if root <> "" then Some root
  else
    let cwd = clean cwd in
    if cwd <> "" then Some cwd else None

(* escape_like (hermes_state_common.py): backslash, then percent, then
   underscore -- ORDER matters, an escaped wildcard must not be re-escaped
   by a later pass. *)
let escape_like text =
  let buffer = Buffer.create (String.length text) in
  String.iter
    (fun c ->
      match c with
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '%' -> Buffer.add_string buffer "\\%"
      | '_' -> Buffer.add_string buffer "\\_"
      | c -> Buffer.add_char buffer c)
    text;
  Buffer.contents buffer

let rstrip_slashes s =
  let n = String.length s in
  let rec last i = if i > 0 && (s.[i - 1] = '/' || s.[i - 1] = '\\') then last (i - 1) else i in
  let stop = last n in
  if stop = 0 then s else String.sub s 0 stop

(* _cwd_prefix_clause: the SQL fragment and its bound parameters, exactly as
   built (params list order is part of the contract -- a caller binds them
   positionally). *)
let cwd_prefix_clause cwd_prefix =
  let prefix = let r = rstrip_slashes cwd_prefix in if r = "" then cwd_prefix else r in
  let esc = escape_like prefix in
  ( "(s.cwd = ? OR s.cwd LIKE ? ESCAPE '\\' OR s.cwd LIKE ? ESCAPE '\\')",
    [ prefix; esc ^ "/%"; esc ^ "\\\\%" ] )

let workspace_key_clause key =
  let prefix = let r = rstrip_slashes key in if r = "" then key else r in
  let cwd_clause, cwd_params = cwd_prefix_clause prefix in
  ( Printf.sprintf "(s.git_repo_root = ? OR (COALESCE(s.git_repo_root, '') = '' AND %s))"
      cwd_clause,
    prefix :: cwd_params )

(* ---- state_portability (hermes_state_portability.py) ----
   The pure @staticmethod coercion helpers on SessionPortabilityMixin, used
   by import_sessions to validate/normalize an imported row before any DB
   write. Raises (a Result here) carry the frozen ValueError message. *)

let import_text_or_none ~field value =
  match value with
  | `Null -> Ok None
  | `String s -> Ok (Some s)
  | _ -> Error (field ^ " must be a string")

(* mirrors Context_file_units.json_default's default (spaced) separators;
   duplicated locally rather than depending on that module for one function,
   keeping this unit's dependency footprint at yojson only. *)
let json_default_separators (value : Yojson.Safe.t) : string =
  let rec go (value : Yojson.Safe.t) : string =
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
            | c when Char.code c < 0x20 ->
                Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
            | c -> Buffer.add_char b c)
          s;
        Buffer.add_char b '"';
        Buffer.contents b
    | `List items -> "[" ^ String.concat ", " (List.map go items) ^ "]"
    | `Assoc fields ->
        "{"
        ^ String.concat ", " (List.map (fun (k, v) -> go (`String k) ^ ": " ^ go v) fields)
        ^ "}"
  in
  go value

(* json_object_or_none: a string value must parse as a JSON OBJECT and is
   passed through verbatim (byte-identical, not re-serialized); a dict value
   is re-encoded with json.dumps default (spaced) separators. *)
let import_json_object_or_none ~field value =
  match value with
  | `Null -> Ok None
  | `String s -> (
      match Yojson.Safe.from_string s with
      | `Assoc _ -> Ok (Some s)
      | _ -> Error (field ^ " must be a JSON object")
      | exception _ -> Error (field ^ " must be valid JSON"))
  | `Assoc _ -> Ok (Some (json_default_separators value))
  | _ -> Error (field ^ " must be a JSON object")

let float_or_none = function
  | `Null -> None
  | `Int n -> Some (float_of_int n)
  | `Float f -> Some f
  | `String s -> float_of_string_opt s
  | _ -> None

let import_int_or_none ~field value =
  match value with
  | `Null -> Ok None
  | `Int n -> Ok (Some n)
  | `Float f -> Ok (Some (int_of_float f))
  | `String s -> (
      match int_of_string_opt s with
      | Some n -> Ok (Some n)
      | None -> Error (field ^ " must be an integer"))
  | _ -> Error (field ^ " must be an integer")

let int_or_default ~default value =
  match value with
  | `Null -> default
  | `Int n -> n
  | `Float f -> int_of_float f
  | `String s -> Option.value (int_of_string_opt s) ~default
  | _ -> default

(* reasoning_json_value: a string is parsed as JSON and returned on success,
   the original string on failure; a non-string passes through untouched. *)
let reasoning_json_value value =
  match value with
  | `String s -> ( try Yojson.Safe.from_string s with _ -> value)
  | other -> other
