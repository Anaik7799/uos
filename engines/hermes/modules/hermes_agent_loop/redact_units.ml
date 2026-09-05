(* Redaction units, reproduced faithfully from the frozen agent/redact.py
   (the measured profile read completely before writing; parity is measured
   by the redact.* scenarios, never assumed).

   Measured profile: redact_sensitive_text with force=true,
   redact_url_credentials=true, code_file=false, file_read=false — exactly
   the arguments the two frozen callers already under measurement pass
   (context_engine.sanitize_memory_context and
   context_compressor._redact_compaction_text).

   Implemented pattern classes, in the frozen application ORDER (the order
   is observable when classes overlap — a JWT inside a Bearer header is
   masked by the header pass, and its masked head is too short for the JWT
   pass to rematch):

     1. vendor-prefix tokens (all 57 frozen prefixes), masked head-6/tail-4
        with the 18-char floor
     2. Authorization / Proxy-Authorization headers, scheme word preserved
     3. x-api-key-style secret headers
     4. database connection-string passwords
     5. bare-token URL userinfo (the colon-less form)
     6. JWTs
     7. the strict URL-credential pass: sensitive query params and userinfo

   Excluded classes, disclosed — each is a separate frozen sub-unit and the
   scenario domain is constructed to keep them inert (no assignment shapes
   outside URLs, no quoted JSON fields, no yaml colons, no telegram
   digit-colon shapes, no BEGIN/END key blocks, no plus signs, no clean
   form bodies, no control-split tokens): the ENV/config/YAML/JSON
   assignment battery, telegram tokens, private-key blocks, form bodies,
   E.164 phones, and the control-split token pre-pass. *)

(* mask_secret with head=6 tail=4 floor=18, on the clean-token domain (the
   frozen strips display-control bytes first; no scenario token carries
   them). The empty-token case historically returns three stars. *)
let mask_token token =
  let n = String.length token in
  if n = 0 then "***"
  else if n < 18 then "***"
  else String.sub token 0 6 ^ "..." ^ String.sub token (n - 4) 4

let is_digit c = c >= '0' && c <= '9'
let is_upper c = c >= 'A' && c <= 'Z'
let is_alpha c = (c >= 'a' && c <= 'z') || is_upper c
let is_alnum c = is_alpha c || is_digit c

let cls_alnum c = is_alnum c
let cls_alnum_dash c = is_alnum c || c = '-'
let cls_alnum_us c = is_alnum c || c = '_'
let cls_alnum_dash_us c = is_alnum c || c = '-' || c = '_'
let cls_alnum_dash_us_eq c = cls_alnum_dash_us c || c = '='
let cls_upper_digit c = is_upper c || is_digit c
let cls_gitlab c = is_alnum c || c = '_' || c = '-'
let cls_gitlab_dotted c = cls_gitlab c || c = '.'

(* One row per frozen _PREFIX_PATTERNS entry, in the frozen order. Run is
   prefix + at least [min] class characters, consumed greedily; Exact is
   prefix + exactly [count] class characters; Xapp and Xox carry their
   structured middles. *)
type shape =
  | Run of string * (char -> bool) * int
  | Exact of string * (char -> bool) * int
  | Xapp
  | Xox

let prefix_patterns =
  [ Run ("sk-", cls_alnum_dash_us, 10); Run ("ghp_", cls_alnum, 10);
    Run ("github_pat_", cls_alnum_us, 10); Run ("gho_", cls_alnum, 10);
    Run ("ghu_", cls_alnum, 10); Run ("ghs_", cls_alnum, 10);
    Run ("ghr_", cls_alnum, 10); Xapp; Xox;
    Run ("AIza", cls_alnum_dash_us, 30); Run ("pplx-", cls_alnum, 10);
    Run ("fal_", cls_alnum_dash_us, 10); Run ("fc-", cls_alnum, 10);
    Run ("bb_live_", cls_alnum_dash_us, 10);
    Run ("gAAAA", cls_alnum_dash_us_eq, 20); Exact ("AKIA", cls_upper_digit, 16);
    Run ("sk_live_", cls_alnum, 10); Run ("sk_test_", cls_alnum, 10);
    Run ("rk_live_", cls_alnum, 10); Run ("SG.", cls_alnum_dash_us, 10);
    Run ("hf_", cls_alnum, 10); Run ("r8_", cls_alnum, 10);
    Run ("npm_", cls_alnum, 10); Run ("pypi-", cls_alnum_dash_us, 10);
    Run ("dop_v1_", cls_alnum, 10); Run ("doo_v1_", cls_alnum, 10);
    Run ("am_", cls_alnum_dash_us, 10); Run ("sk_", cls_alnum_us, 10);
    Run ("tvly-", cls_alnum, 10); Run ("exa_", cls_alnum, 10);
    Run ("gsk_", cls_alnum, 10); Run ("syt_", cls_alnum, 10);
    Run ("retaindb_", cls_alnum, 10); Run ("hsk-", cls_alnum, 10);
    Run ("mem0_", cls_alnum, 10); Run ("brv_", cls_alnum, 10);
    Run ("xai-", cls_alnum, 30); Run ("ntn_", cls_alnum, 10);
    Run ("fw-", cls_alnum, 30); Run ("fw_", cls_alnum, 30);
    Run ("fpk_", cls_alnum, 30); Run ("glpat-", cls_gitlab, 10);
    Run ("gloas-", cls_gitlab, 10); Run ("gldt-", cls_gitlab, 10);
    Run ("glrt-", cls_gitlab_dotted, 10); Run ("glrtr-", cls_gitlab_dotted, 10);
    Run ("glcbt-", cls_gitlab, 10); Run ("glptt-", cls_gitlab, 10);
    Run ("glft-", cls_gitlab, 10); Run ("glimt-", cls_gitlab, 10);
    Run ("glagent-", cls_gitlab, 10); Run ("glsoat-", cls_gitlab, 10);
    Run ("glffct-", cls_gitlab, 10); Run ("glwt-", cls_gitlab, 10);
    Run ("GR1348941", cls_gitlab, 10) ]

let starts_with text i prefix =
  let l = String.length prefix in
  i + l <= String.length text && String.sub text i l = prefix

let run_length text i cls =
  let n = String.length text in
  let rec go j = if j < n && cls text.[j] then go (j + 1) else j in
  go i - i

(* Try one shape at position [i]; return the match end offset. Mirrors the
   frozen regex alternation: leftmost position, first listed alternative,
   greedy runs. *)
let match_shape text i = function
  | Run (prefix, cls, min_run) ->
      if starts_with text i prefix then begin
        let start = i + String.length prefix in
        let length = run_length text start cls in
        if length >= min_run then Some (start + length) else None
      end
      else None
  | Exact (prefix, cls, count) ->
      if starts_with text i prefix then begin
        let start = i + String.length prefix in
        let length = run_length text start cls in
        if length >= count then Some (start + count) else None
      end
      else None
  | Xapp ->
      if starts_with text i "xapp-" then begin
        let d = i + 5 in
        let digits = run_length text d is_digit in
        if digits >= 1 && starts_with text (d + digits) "-" then begin
          let start = d + digits + 1 in
          let length = run_length text start cls_alnum_dash in
          if length >= 10 then Some (start + length) else None
        end
        else None
      end
      else None
  | Xox ->
      if starts_with text i "xox" then begin
        let n = String.length text in
        if
          i + 4 < n
          && (match text.[i + 3] with 'b' | 'a' | 'p' | 'r' | 's' -> true | _ -> false)
          && text.[i + 4] = '-'
        then begin
          let start = i + 5 in
          let length = run_length text start cls_alnum_dash in
          if length >= 10 then Some (start + length) else None
        end
        else None
      end
      else None

let redact_prefix_tokens text =
  let n = String.length text in
  let buffer = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    let matched =
      List.find_map (fun shape -> match match_shape text !i shape with
        | Some finish -> Some finish
        | None -> None)
        prefix_patterns
    in
    match matched with
    | Some finish ->
        Buffer.add_string buffer (mask_token (String.sub text !i (finish - !i)));
        i := finish
    | None ->
        Buffer.add_char buffer text.[!i];
        incr i
  done;
  Buffer.contents buffer

(* The frozen header pattern: an optional Proxy- prefix, Authorization, a
   colon, optional whitespace, an optional scheme word, then the value —
   IGNORECASE. The value class is one-or-more characters excluding
   whitespace and both quote characters; the scheme word is a letter
   followed by word/dot/plus/dash characters and 1+ spaces. When no value
   follows the scheme, the regex backtracks and the scheme itself is the
   masked value. (Spelled in prose: a star-paren sequence inside an OCaml
   comment closes it.) *)
let lower = String.lowercase_ascii

let redact_auth_headers text =
  let n = String.length text in
  let buffer = Buffer.create n in
  let is_space c =
    c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012' || c = '\011'
  in
  let is_scheme_char c = is_alnum c || c = '_' || c = '.' || c = '+' || c = '-' in
  let is_value_char c =
    not (c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012' || c = '"' || c = '\'')
  in
  let header_at i =
    let try_prefix p =
      let l = String.length p in
      if i + l <= n && lower (String.sub text i l) = p then Some (i + l) else None
    in
    match try_prefix "proxy-authorization:" with
    | Some e -> Some e
    | None -> try_prefix "authorization:"
  in
  let i = ref 0 in
  while !i < n do
    match header_at !i with
    | None ->
        Buffer.add_char buffer text.[!i];
        incr i
    | Some after_colon ->
        Buffer.add_string buffer (String.sub text !i (after_colon - !i));
        let ws = run_length text after_colon is_space in
        Buffer.add_string buffer (String.sub text after_colon ws);
        let value_start = after_colon + ws in
        if value_start >= n || not (is_value_char text.[value_start]) then i := value_start
        else begin
          (* try scheme + spaces + value; else the token alone is the value *)
          let first_len = run_length text value_start is_value_char in
          let scheme_ok =
            is_alpha text.[value_start]
            && run_length text value_start is_scheme_char = first_len
          in
          let after_first = value_start + first_len in
          let gap = run_length text after_first is_space in
          if scheme_ok && gap > 0 && after_first + gap < n && is_value_char text.[after_first + gap]
          then begin
            let value_len = run_length text (after_first + gap) is_value_char in
            Buffer.add_string buffer (String.sub text value_start (first_len + gap));
            Buffer.add_string buffer
              (mask_token (String.sub text (after_first + gap) value_len));
            i := after_first + gap + value_len
          end
          else begin
            Buffer.add_string buffer (mask_token (String.sub text value_start first_len));
            i := after_first
          end
        end
  done;
  Buffer.contents buffer

(* (x-api-key|x-goog-api-key|api-key|apikey|x-api-token|x-auth-token|
    x-access-token)\s*:\s*(\S+), IGNORECASE. *)
let secret_header_names =
  [ "x-goog-api-key"; "x-access-token"; "x-auth-token"; "x-api-token"; "x-api-key";
    "api-key"; "apikey" ]

let redact_secret_headers text =
  let n = String.length text in
  let buffer = Buffer.create n in
  let is_ws c = c = ' ' || c = '\t' in
  let not_space c =
    not (c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012' || c = '\011')
  in
  let name_at i =
    List.find_map
      (fun name ->
        let l = String.length name in
        if i + l <= n && lower (String.sub text i l) = name then Some l else None)
      secret_header_names
  in
  let i = ref 0 in
  while !i < n do
    match name_at !i with
    | None ->
        Buffer.add_char buffer text.[!i];
        incr i
    | Some name_len ->
        let after = !i + name_len in
        let ws1 = run_length text after is_ws in
        if after + ws1 < n && text.[after + ws1] = ':' then begin
          let after_colon = after + ws1 + 1 in
          let ws2 = run_length text after_colon is_ws in
          let value_start = after_colon + ws2 in
          let value_len = run_length text value_start not_space in
          if value_len > 0 then begin
            Buffer.add_string buffer (String.sub text !i (value_start - !i));
            Buffer.add_string buffer (mask_token (String.sub text value_start value_len));
            i := value_start + value_len
          end
          else begin
            Buffer.add_char buffer text.[!i];
            incr i
          end
        end
        else begin
          Buffer.add_char buffer text.[!i];
          incr i
        end
  done;
  Buffer.contents buffer

(* ((?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqp)://[^:\s]+:)
   ([^@\s]+)(@), IGNORECASE — password replaced with three stars. *)
let db_schemes = [ "postgresql"; "postgres"; "mongodb+srv"; "mongodb"; "mysql"; "redis"; "amqp" ]

let redact_db_connstrings text =
  let n = String.length text in
  let buffer = Buffer.create n in
  let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012' || c = '\011' in
  let scheme_at i =
    List.find_map
      (fun scheme ->
        let l = String.length scheme in
        if
          i + l + 3 <= n
          && lower (String.sub text i l) = scheme
          && String.sub text (i + l) 3 = "://"
        then Some (i + l + 3)
        else None)
      db_schemes
  in
  let i = ref 0 in
  while !i < n do
    match scheme_at !i with
    | None ->
        Buffer.add_char buffer text.[!i];
        incr i
    | Some after_scheme ->
        let user_len =
          run_length text after_scheme (fun c -> (not (is_ws c)) && c <> ':')
        in
        let colon = after_scheme + user_len in
        if user_len > 0 && colon < n && text.[colon] = ':' then begin
          let pw_start = colon + 1 in
          let pw_len = run_length text pw_start (fun c -> (not (is_ws c)) && c <> '@') in
          let at = pw_start + pw_len in
          if pw_len > 0 && at < n && text.[at] = '@' then begin
            Buffer.add_string buffer (String.sub text !i (pw_start - !i));
            Buffer.add_string buffer "***@";
            i := at + 1
          end
          else begin
            Buffer.add_string buffer (String.sub text !i (after_scheme - !i));
            i := after_scheme
          end
        end
        else begin
          Buffer.add_string buffer (String.sub text !i (after_scheme - !i));
          i := after_scheme
        end
  done;
  Buffer.contents buffer

(* ((?:https?|wss?|git|ssh|ftp|ftps|sftp)://)([^\s:@/]{8,})(@[^\s]+),
   IGNORECASE — the colon-less bare-token userinfo, masked head/tail. *)
let bare_schemes = [ "https"; "http"; "wss"; "ws"; "git"; "ssh"; "ftps"; "ftp"; "sftp" ]

let redact_url_bare_tokens text =
  let n = String.length text in
  let buffer = Buffer.create n in
  let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012' || c = '\011' in
  let scheme_at i =
    List.find_map
      (fun scheme ->
        let l = String.length scheme in
        if
          i + l + 3 <= n
          && lower (String.sub text i l) = scheme
          && String.sub text (i + l) 3 = "://"
        then Some (i + l + 3)
        else None)
      bare_schemes
  in
  let i = ref 0 in
  while !i < n do
    match scheme_at !i with
    | None ->
        Buffer.add_char buffer text.[!i];
        incr i
    | Some after_scheme ->
        let token_len =
          run_length text after_scheme (fun c ->
              (not (is_ws c)) && c <> ':' && c <> '@' && c <> '/')
        in
        let at = after_scheme + token_len in
        if token_len >= 8 && at < n && text.[at] = '@' && at + 1 < n
           && not (is_ws text.[at + 1])
        then begin
          Buffer.add_string buffer (String.sub text !i (after_scheme - !i));
          Buffer.add_string buffer (mask_token (String.sub text after_scheme token_len));
          Buffer.add_char buffer '@';
          i := at + 1
        end
        else begin
          Buffer.add_string buffer (String.sub text !i (after_scheme - !i));
          i := after_scheme
        end
  done;
  Buffer.contents buffer

(* eyJ[A-Za-z0-9_-]{10,}(?:\.[A-Za-z0-9_=-]{4,}){0,2} — masked head/tail. *)
let redact_jwts text =
  let n = String.length text in
  let buffer = Buffer.create n in
  let cls_header c = is_alnum c || c = '_' || c = '-' in
  let cls_part c = cls_header c || c = '=' in
  let i = ref 0 in
  while !i < n do
    if starts_with text !i "eyJ" then begin
      let body = run_length text (!i + 3) cls_header in
      if body >= 10 then begin
        let finish = ref (!i + 3 + body) in
        let parts = ref 0 in
        let continue_ = ref true in
        while !continue_ && !parts < 2 do
          if !finish < n && text.[!finish] = '.' then begin
            let part = run_length text (!finish + 1) cls_part in
            if part >= 4 then begin
              finish := !finish + 1 + part;
              incr parts
            end
            else continue_ := false
          end
          else continue_ := false
        done;
        Buffer.add_string buffer (mask_token (String.sub text !i (!finish - !i)));
        i := !finish
      end
      else begin
        Buffer.add_char buffer text.[!i];
        incr i
      end
    end
    else begin
      Buffer.add_char buffer text.[!i];
      incr i
    end
  done;
  Buffer.contents buffer

(* The strict URL-credential pass: ([?#&;])(key)=(value) with the key
   canonicalized (percent-decoded up to three rounds, casefolded, dashes to
   underscores) and matched exactly against the sensitive set; then
   (//)(userinfo)@ with user:*** or a full *** for the colon-less form. *)
let sensitive_query_params =
  [ "access_token"; "refresh_token"; "id_token"; "token"; "api_key"; "apikey";
    "client_secret"; "password"; "auth"; "jwt"; "session"; "secret"; "key";
    "code"; "signature"; "x_amz_signature" ]

let percent_decode s =
  let n = String.length s in
  let buffer = Buffer.create n in
  let hex c =
    if is_digit c then Some (Char.code c - Char.code '0')
    else if c >= 'a' && c <= 'f' then Some (Char.code c - Char.code 'a' + 10)
    else if c >= 'A' && c <= 'F' then Some (Char.code c - Char.code 'A' + 10)
    else None
  in
  let i = ref 0 in
  while !i < n do
    (match s.[!i] with
     | '%' when !i + 2 < n -> (
         match (hex s.[!i + 1], hex s.[!i + 2]) with
         | Some hi, Some lo ->
             Buffer.add_char buffer (Char.chr ((hi * 16) + lo));
             i := !i + 3
         | _ ->
             Buffer.add_char buffer '%';
             incr i)
     | '+' ->
         Buffer.add_char buffer ' ';
         incr i
     | c ->
         Buffer.add_char buffer c;
         incr i)
  done;
  Buffer.contents buffer

let canonical_param_name name =
  let rec settle value rounds =
    if rounds = 0 then value
    else
      let next = percent_decode value in
      if next = value then value else settle next (rounds - 1)
  in
  String.map (fun c -> if c = '-' then '_' else c) (lower (settle name 3))

let redact_strict_url_credentials text =
  let n = String.length text in
  (* params *)
  let cls_key c = is_alnum c || c = '_' || c = '.' || c = '~' || c = '+' || c = '%' || c = '-' in
  let cls_value c =
    not
      (c = '#' || c = '&' || c = ';' || c = ' ' || c = '\t' || c = '\n' || c = '\r'
      || c = '\012' || c = '\011' || c = '"' || c = '\'' || c = '<' || c = '>')
  in
  let buffer = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    let c = text.[!i] in
    if (c = '?' || c = '#' || c = '&' || c = ';') && !i + 1 < n then begin
      let key_len = run_length text (!i + 1) cls_key in
      let eq = !i + 1 + key_len in
      if key_len > 0 && eq < n && text.[eq] = '=' then begin
        let value_len = run_length text (eq + 1) cls_value in
        let key = String.sub text (!i + 1) key_len in
        if List.mem (canonical_param_name key) sensitive_query_params then begin
          Buffer.add_char buffer c;
          Buffer.add_string buffer key;
          Buffer.add_string buffer "=***";
          i := eq + 1 + value_len
        end
        else begin
          (* a non-sensitive pair is consumed WHOLE, as the frozen regex
             does -- a delimiter character inside its value must not
             re-trigger scanning *)
          Buffer.add_string buffer (String.sub text !i (eq + 1 + value_len - !i));
          i := eq + 1 + value_len
        end
      end
      else begin
        Buffer.add_char buffer c;
        incr i
      end
    end
    else begin
      Buffer.add_char buffer c;
      incr i
    end
  done;
  let text = Buffer.contents buffer in
  (* userinfo: (//)([^/\s?#@]+)@ *)
  let n = String.length text in
  let cls_userinfo c =
    not
      (c = '/' || c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012' || c = '\011'
      || c = '?' || c = '#' || c = '@')
  in
  let buffer = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    if !i + 1 < n && text.[!i] = '/' && text.[!i + 1] = '/' then begin
      let info_len = run_length text (!i + 2) cls_userinfo in
      let at = !i + 2 + info_len in
      if info_len > 0 && at < n && text.[at] = '@' then begin
        let userinfo = String.sub text (!i + 2) info_len in
        Buffer.add_string buffer "//";
        (match String.index_opt userinfo ':' with
         | Some colon -> Buffer.add_string buffer (String.sub userinfo 0 colon ^ ":***@")
         | None -> Buffer.add_string buffer "***@");
        i := at + 1
      end
      else begin
        Buffer.add_string buffer "//";
        i := !i + 2
      end
    end
    else begin
      Buffer.add_char buffer text.[!i];
      incr i
    end
  done;
  Buffer.contents buffer

(* The measured composite, in the frozen order. *)
let redact_sensitive_text ~redact_url_credentials text =
  let text = redact_prefix_tokens text in
  let text = redact_auth_headers text in
  let text = redact_secret_headers text in
  let text = redact_db_connstrings text in
  let text = redact_url_bare_tokens text in
  let text = redact_jwts text in
  if redact_url_credentials then redact_strict_url_credentials text else text
