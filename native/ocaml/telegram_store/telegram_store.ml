(* Unified Operational System (UOS)
 * telegram_store.ml - Isolated Native OCaml SQLite Storage Kernel
 * Spec: uos.telegram-durable-store-corrected-development-spec.v1
 * Plan: uos/telegram-runtime/20261001-1150
 * Wire Spec: 20261011-1247-telegram_store_wire_v2.json
 *)

type row_result = {
  key: string;
  exists: bool;
  version: int;
  canonical_value_base64: string;
  sha256: string;
}

type receipt = {
  operation_id: string;
  request_digest: string;
  generation: int;
  summary_json: string;
  committed_utc_us: int64;
}

type read_set_assertion = {
  key: string;
  expected_version: int;
  expected_sha256: string;
}

type change = {
  key: string;
  expected_version: int;
  expected_sha256: string;
  new_value_base64: string;
}

type reservation_delta = {
  rows: int;
  receipts: int;
}

type apply_request = {
  db_path: string;
  bot_id: string;
  operation_id: string;
  request_digest: string;
  expected_generation: int;
  read_set_assertions: read_set_assertion list;
  changes: change list;
  reservation_delta: reservation_delta;
  summary_json: string;
}

type apply_result = {
  replay: bool;
  receipt: receipt;
}

(* Limits & Bounds per Adopted Spec *)
let max_request_json_bytes = 1_048_572
let max_response_json_bytes = 1_048_572
let max_key_bytes = 256
let max_operation_id_bytes = 128
let max_request_digest_bytes = 128
let max_value_bytes = 98_304
let max_aggregate_decoded_values = 524_288
let max_changes = 128
let max_read_set_assertions = 128
let max_read_keys = 64
let max_receipt_summary_bytes = 65_536
let max_reservation_delta_rows = 20
let max_reservation_delta_receipts = 64
let max_rows_capacity = 20_000
let max_receipts_capacity = 20_000
let max_db_main_bytes = 268_435_456 (* 256 MiB *)
let max_inbox_index_limit = 100
let sqlite_busy_timeout_ms = 250
let schema_version = "uos.telegram-store.v2"

(* Stage barriers for SIGKILL crash recovery tests (not exposed via CLI/JSON/env) *)
type stage_barrier =
  | Init_after_ddl
  | Init_after_meta
  | Apply_between_rows
  | Apply_pre_commit
  | Apply_post_commit_pre_reply

let test_stage_hook : (stage_barrier -> unit) ref = ref (fun _ -> ())

let trigger_stage_hook (b : stage_barrier) : unit =
  !test_stage_hook b

(* Test Hooks for Commit Uncertainty & Fault Injection (Not exposed in CLI/JSON) *)
let test_hook_fail_init_during_commit = ref false
let test_hook_fail_init_after_commit = ref false
let test_hook_fail_apply_before_commit = ref false
let test_hook_fail_apply_during_commit = ref false
let test_hook_fail_apply_after_commit = ref false

let reset_test_hooks () =
  test_stage_hook := (fun _ -> ());
  test_hook_fail_init_during_commit := false;
  test_hook_fail_init_after_commit := false;
  test_hook_fail_apply_before_commit := false;
  test_hook_fail_apply_during_commit := false;
  test_hook_fail_apply_after_commit := false

(* Exact schema definitions in sqlite_master *)
let expected_schema_objects = [
  ("table", "kv_rows", "CREATE TABLE kv_rows (key TEXT PRIMARY KEY, version INTEGER NOT NULL, canonical_value_bytes BLOB NOT NULL, sha256 TEXT NOT NULL)");
  ("table", "meta", "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
  ("table", "receipts", "CREATE TABLE receipts (operation_id TEXT PRIMARY KEY, request_digest TEXT NOT NULL, generation INTEGER NOT NULL, summary_json TEXT NOT NULL, committed_utc_us INTEGER NOT NULL)");
  ("trigger", "receipts_no_delete", "CREATE TRIGGER receipts_no_delete BEFORE DELETE ON receipts BEGIN SELECT RAISE(FAIL, 'receipts are append-only'); END");
  ("trigger", "receipts_no_update", "CREATE TRIGGER receipts_no_update BEFORE UPDATE ON receipts BEGIN SELECT RAISE(FAIL, 'receipts are append-only'); END");
]

(* Base64, Hex and Crypto Utilities *)
let encode_canonical_base64 (raw : string) : string =
  Cryptokit.transform_string (Cryptokit.Base64.encode_compact_pad ()) raw

let decode_canonical_base64 (s : string) : (string, string) result =
  if String.length s mod 4 <> 0 then Error "invalid_base64"
  else
    try
      let decoded = Cryptokit.transform_string (Cryptokit.Base64.decode ()) s in
      let re_encoded = Cryptokit.transform_string (Cryptokit.Base64.encode_compact_pad ()) decoded in
      if String.equal re_encoded s then Ok decoded
      else Error "invalid_base64"
    with _ -> Error "invalid_base64"

let sha256_hex (raw : string) : string =
  let h = Cryptokit.Hash.sha256 () in
  h#add_string raw;
  let hex = Cryptokit.transform_string (Cryptokit.Hexa.encode ()) h#result in
  String.lowercase_ascii hex

let is_valid_hex_64 (h : string) : bool =
  if String.length h <> 64 then false
  else
    let rec loop idx =
      if idx = 64 then true
      else
        let c = h.[idx] in
        if (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') then loop (idx + 1)
        else false
    in
    loop 0

let is_valid_bot_id (bot_id : string) : bool =
  let len = String.length bot_id in
  if len = 0 || len > 16 then false
  else if bot_id.[0] = '0' then false
  else
    let rec all_digits idx =
      if idx = len then true
      else
        let c = bot_id.[idx] in
        if c >= '0' && c <= '9' then all_digits (idx + 1) else false
    in
    if not (all_digits 0) then false
    else
      try
        let n = Int64.of_string bot_id in
        n >= 1L && n <= 9007199254740991L
      with _ -> false

let now_utc_us () : int64 =
  Int64.of_float (Unix.gettimeofday () *. 1_000_000.0)

(* Strict UTF-8 Scalar Validation per RFC 3629 *)
let is_valid_utf8 (s : string) : bool =
  let len = String.length s in
  let rec loop i =
    if i >= len then true
    else
      let b0 = Char.code s.[i] in
      if b0 <= 0x7F then
        loop (i + 1)
      else if b0 >= 0xC2 && b0 <= 0xDF then
        if i + 1 >= len then false
        else
          let b1 = Char.code s.[i + 1] in
          if b1 >= 0x80 && b1 <= 0xBF then loop (i + 2)
          else false
      else if b0 = 0xE0 then
        if i + 2 >= len then false
        else
          let b1 = Char.code s.[i + 1] in
          let b2 = Char.code s.[i + 2] in
          if b1 >= 0xA0 && b1 <= 0xBF && b2 >= 0x80 && b2 <= 0xBF then loop (i + 3)
          else false
      else if (b0 >= 0xE1 && b0 <= 0xEC) || (b0 >= 0xEE && b0 <= 0xEF) then
        if i + 2 >= len then false
        else
          let b1 = Char.code s.[i + 1] in
          let b2 = Char.code s.[i + 2] in
          if b1 >= 0x80 && b1 <= 0xBF && b2 >= 0x80 && b2 <= 0xBF then loop (i + 3)
          else false
      else if b0 = 0xED then
        if i + 2 >= len then false
        else
          let b1 = Char.code s.[i + 1] in
          let b2 = Char.code s.[i + 2] in
          (* 0xA0..0xBF are UTF-16 surrogates U+D800..U+DFFF, which are forbidden *)
          if b1 >= 0x80 && b1 <= 0x9F && b2 >= 0x80 && b2 <= 0xBF then loop (i + 3)
          else false
      else if b0 = 0xF0 then
        if i + 3 >= len then false
        else
          let b1 = Char.code s.[i + 1] in
          let b2 = Char.code s.[i + 2] in
          let b3 = Char.code s.[i + 3] in
          if b1 >= 0x90 && b1 <= 0xBF && b2 >= 0x80 && b2 <= 0xBF && b3 >= 0x80 && b3 <= 0xBF then loop (i + 4)
          else false
      else if b0 >= 0xF1 && b0 <= 0xF3 then
        if i + 3 >= len then false
        else
          let b1 = Char.code s.[i + 1] in
          let b2 = Char.code s.[i + 2] in
          let b3 = Char.code s.[i + 3] in
          if b1 >= 0x80 && b1 <= 0xBF && b2 >= 0x80 && b2 <= 0xBF && b3 >= 0x80 && b3 <= 0xBF then loop (i + 4)
          else false
      else if b0 = 0xF4 then
        if i + 3 >= len then false
        else
          let b1 = Char.code s.[i + 1] in
          let b2 = Char.code s.[i + 2] in
          let b3 = Char.code s.[i + 3] in
          if b1 >= 0x80 && b1 <= 0x8F && b2 >= 0x80 && b2 <= 0xBF && b3 >= 0x80 && b3 <= 0xBF then loop (i + 4)
          else false
      else
        false
  in
  loop 0

let max_json_depth = 64

let add_utf8_codepoint (buf : Buffer.t) (cp : int) : unit =
  if cp <= 0x7F then
    Buffer.add_char buf (Char.chr cp)
  else if cp <= 0x7FF then begin
    Buffer.add_char buf (Char.chr (0xC0 lor (cp lsr 6)));
    Buffer.add_char buf (Char.chr (0x80 lor (cp land 0x3F)))
  end else if cp <= 0xFFFF then begin
    Buffer.add_char buf (Char.chr (0xE0 lor (cp lsr 12)));
    Buffer.add_char buf (Char.chr (0x80 lor ((cp lsr 6) land 0x3F)));
    Buffer.add_char buf (Char.chr (0x80 lor (cp land 0x3F)))
  end else if cp <= 0x10FFFF then begin
    Buffer.add_char buf (Char.chr (0xF0 lor (cp lsr 18)));
    Buffer.add_char buf (Char.chr (0x80 lor ((cp lsr 12) land 0x3F)));
    Buffer.add_char buf (Char.chr (0x80 lor ((cp lsr 6) land 0x3F)));
    Buffer.add_char buf (Char.chr (0x80 lor (cp land 0x3F)))
  end

(* Strict RFC 8259 Standard JSON Validator (Rejects lone surrogates, Yojson extensions, comments, duplicate keys) *)
let validate_strict_json (s : string) : (unit, string) result =
  if not (is_valid_utf8 s) then Error "invalid_utf8"
  else
    let len = String.length s in
    let pos = ref 0 in
    let peek () =
      if !pos < len then Some s.[!pos] else None
    in
    let advance () =
      incr pos
    in
    let skip_ws () =
      let rec loop () =
        match peek () with
        | Some (' ' | '\t' | '\r' | '\n') -> advance (); loop ()
        | _ -> ()
      in
      loop ()
    in
    let parse_hex_digit c =
      if c >= '0' && c <= '9' then Some (Char.code c - Char.code '0')
      else if c >= 'a' && c <= 'f' then Some (Char.code c - Char.code 'a' + 10)
      else if c >= 'A' && c <= 'F' then Some (Char.code c - Char.code 'A' + 10)
      else None
    in
    let parse_u4 () =
      if !pos + 4 > len then None
      else
        let h0 = parse_hex_digit s.[!pos] in
        let h1 = parse_hex_digit s.[!pos + 1] in
        let h2 = parse_hex_digit s.[!pos + 2] in
        let h3 = parse_hex_digit s.[!pos + 3] in
        match h0, h1, h2, h3 with
        | Some d0, Some d1, Some d2, Some d3 ->
            pos := !pos + 4;
            Some ((d0 lsl 12) lor (d1 lsl 8) lor (d2 lsl 4) lor d3)
        | _ -> None
    in
    let rec parse_string () =
      advance (); (* skip leading '"' *)
      let buf = Buffer.create 32 in
      let rec loop () =
        match peek () with
        | None -> Error "unterminated_string"
        | Some '"' ->
            advance ();
            Ok (Buffer.contents buf)
        | Some '\\' ->
            advance ();
            (match peek () with
            | None -> Error "unterminated_escape"
            | Some '"' -> advance (); Buffer.add_char buf '"'; loop ()
            | Some '\\' -> advance (); Buffer.add_char buf '\\'; loop ()
            | Some '/' -> advance (); Buffer.add_char buf '/'; loop ()
            | Some 'b' -> advance (); Buffer.add_char buf '\b'; loop ()
            | Some 'f' -> advance (); Buffer.add_char buf '\012'; loop ()
            | Some 'n' -> advance (); Buffer.add_char buf '\n'; loop ()
            | Some 'r' -> advance (); Buffer.add_char buf '\r'; loop ()
            | Some 't' -> advance (); Buffer.add_char buf '\t'; loop ()
            | Some 'u' ->
                advance ();
                (match parse_u4 () with
                | None -> Error "invalid_unicode_escape"
                | Some cp ->
                    if cp >= 0xD800 && cp <= 0xDBFF then begin
                      (* High surrogate - MUST be followed by \uDC00..\uDFFF *)
                      match peek () with
                      | Some '\\' ->
                          advance ();
                          (match peek () with
                          | Some 'u' ->
                              advance ();
                              (match parse_u4 () with
                              | Some low when low >= 0xDC00 && low <= 0xDFFF ->
                                  let full_cp = 0x10000 + ((cp - 0xD800) lsl 10) + (low - 0xDC00) in
                                  add_utf8_codepoint buf full_cp;
                                  loop ()
                              | _ -> Error "lone_surrogate")
                          | _ -> Error "lone_surrogate")
                      | _ -> Error "lone_surrogate"
                    end else if cp >= 0xDC00 && cp <= 0xDFFF then
                      Error "lone_surrogate"
                    else begin
                      add_utf8_codepoint buf cp;
                      loop ()
                    end)
            | Some _ -> Error "invalid_escape")
        | Some c ->
            let code = Char.code c in
            if code < 0x20 then Error "unescaped_control_char"
            else begin
              advance ();
              Buffer.add_char buf c;
              loop ()
            end
      in
      loop ()
    and parse_number () =
      let start_pos = !pos in
      if peek () = Some '-' then advance ();
      match peek () with
      | Some '0' ->
          advance ();
          (match peek () with
          | Some ('0'..'9') -> Error "leading_zero_number"
          | _ -> check_frac_exp start_pos)
      | Some ('1'..'9') ->
          advance ();
          while (match peek () with Some ('0'..'9') -> true | _ -> false) do advance () done;
          check_frac_exp start_pos
      | _ -> Error "invalid_number"
    and check_frac_exp _start_pos =
      let frac_res =
        if peek () = Some '.' then begin
          advance ();
          match peek () with
          | Some ('0'..'9') ->
              advance ();
              while (match peek () with Some ('0'..'9') -> true | _ -> false) do advance () done;
              Ok ()
          | _ -> Error "trailing_decimal_point"
        end else Ok ()
      in
      match frac_res with
      | Error e -> Error e
      | Ok () ->
          if peek () = Some 'e' || peek () = Some 'E' then begin
            advance ();
            if peek () = Some '+' || peek () = Some '-' then advance ();
            match peek () with
            | Some ('0'..'9') ->
                advance ();
                while (match peek () with Some ('0'..'9') -> true | _ -> false) do advance () done;
                Ok ()
            | _ -> Error "invalid_exponent"
          end else
            Ok ()
    and parse_value depth : (unit, string) result =
      if depth > max_json_depth then Error "json_nesting_depth_exceeded"
      else begin
        skip_ws ();
        match peek () with
        | None -> Error "unexpected_eof"
        | Some '"' ->
            (match parse_string () with
            | Ok _ -> Ok ()
            | Error e -> Error e)
        | Some '{' -> parse_object (depth + 1)
        | Some '[' -> parse_array (depth + 1)
        | Some ('-' | '0'..'9') -> parse_number ()
        | Some 't' ->
            if !pos + 4 <= len && String.sub s !pos 4 = "true" then begin
              pos := !pos + 4; Ok ()
            end else Error "invalid_literal"
        | Some 'f' ->
            if !pos + 5 <= len && String.sub s !pos 5 = "false" then begin
              pos := !pos + 5; Ok ()
            end else Error "invalid_literal"
        | Some 'n' ->
            if !pos + 4 <= len && String.sub s !pos 4 = "null" then begin
              pos := !pos + 4; Ok ()
            end else Error "invalid_literal"
        | Some _ -> Error "invalid_token"
      end
    and parse_array depth =
      if depth > max_json_depth then Error "json_nesting_depth_exceeded"
      else begin
        advance (); (* skip '[' *)
        skip_ws ();
        if peek () = Some ']' then begin advance (); Ok () end
        else
          let rec loop () =
            match parse_value depth with
            | Error e -> Error e
            | Ok () ->
                skip_ws ();
                match peek () with
                | Some ',' ->
                    advance ();
                    skip_ws ();
                    if peek () = Some ']' then Error "trailing_comma"
                    else loop ()
                | Some ']' -> advance (); Ok ()
                | _ -> Error "expected_comma_or_bracket"
          in
          loop ()
      end
    and parse_object depth =
      if depth > max_json_depth then Error "json_nesting_depth_exceeded"
      else begin
        advance (); (* skip '{' *)
        skip_ws ();
        if peek () = Some '}' then begin advance (); Ok () end
        else
          let rec loop keys =
            skip_ws ();
            if peek () <> Some '"' then Error "expected_string_key"
            else
              match parse_string () with
              | Error e -> Error e
              | Ok k ->
                  if List.mem k keys then Error "duplicate_json_keys"
                  else begin
                    skip_ws ();
                    if peek () <> Some ':' then Error "expected_colon"
                    else begin
                      advance ();
                      match parse_value depth with
                      | Error e -> Error e
                      | Ok () ->
                          skip_ws ();
                          match peek () with
                          | Some ',' ->
                              advance ();
                              skip_ws ();
                              if peek () = Some '}' then Error "trailing_comma"
                              else loop (k :: keys)
                          | Some '}' -> advance (); Ok ()
                          | _ -> Error "expected_comma_or_brace"
                    end
                  end
          in
          loop []
      end
    in
    match parse_value 0 with
    | Error e -> Error e
    | Ok () ->
        skip_ws ();
        if !pos < len then Error "trailing_garbage"
        else Ok ()

(* Canonical Versioned Injective Request Digest Derivation *)
let compute_request_digest
    ~(bot_id : string)
    ~(operation_id : string)
    ~(expected_generation : int)
    ~(read_set : read_set_assertion list)
    ~(changes : change list)
    ~(reservation_delta : reservation_delta)
    ~(summary_json : string) : string =
  let sorted_read_set =
    List.sort (fun (a : read_set_assertion) (b : read_set_assertion) -> String.compare a.key b.key) read_set
  in
  let sorted_changes =
    List.sort (fun (c1 : change) (c2 : change) -> String.compare c1.key c2.key) changes
  in
  let buf = Buffer.create 4096 in
  Buffer.add_string buf "uos.telegram-store.apply.v2\n";
  let add_lp_field s =
    Buffer.add_string buf (string_of_int (String.length s));
    Buffer.add_char buf ':';
    Buffer.add_string buf s;
    Buffer.add_char buf '\n'
  in
  add_lp_field bot_id;
  add_lp_field operation_id;
  Buffer.add_string buf (string_of_int expected_generation ^ "\n");
  Buffer.add_string buf (string_of_int (List.length sorted_read_set) ^ "\n");
  List.iter (fun (a : read_set_assertion) ->
    add_lp_field a.key;
    Buffer.add_string buf (string_of_int a.expected_version ^ "\n");
    add_lp_field a.expected_sha256;
  ) sorted_read_set;
  Buffer.add_string buf (string_of_int (List.length sorted_changes) ^ "\n");
  List.iter (fun (c : change) ->
    add_lp_field c.key;
    Buffer.add_string buf (string_of_int c.expected_version ^ "\n");
    add_lp_field c.expected_sha256;
    add_lp_field c.new_value_base64;
  ) sorted_changes;
  Buffer.add_string buf (Printf.sprintf "%d:%d\n" reservation_delta.rows reservation_delta.receipts);
  add_lp_field summary_json;
  sha256_hex (Buffer.contents buf)

(* Path, Permissions, Hardlink, and Full Ancestor Chain Confinement *)
let validate_path (path : string) : (unit, string) result =
  if String.length path = 0 || path.[0] <> '/' then Error "db_path_invalid"
  else if String.contains path '\000' then Error "db_path_invalid"
  else
    let parts = String.split_on_char '/' path in
    if List.mem ".." parts || List.mem "." parts then Error "db_path_invalid"
    else Ok ()

let check_dir_permissions (dir : string) : (unit, string) result =
  try
    let st = Unix.lstat dir in
    if st.st_kind <> Unix.S_DIR then Error "db_directory_insecure"
    else if st.st_uid <> Unix.getuid () then Error "db_directory_insecure"
    else if (st.st_perm land 0o777) <> 0o700 then Error "db_directory_insecure"
    else Ok ()
  with _ -> Error "db_directory_insecure"

let check_ancestor_paths (path : string) : (unit, string) result =
  let ( let* ) = Result.bind in
  let* () = validate_path path in
  let parent_dir = Filename.dirname path in
  let components = List.filter (fun s -> String.length s > 0) (String.split_on_char '/' parent_dir) in
  let check_component current is_immediate_parent =
    try
      let st = Unix.lstat current in
      if st.st_kind = Unix.S_LNK then
        if is_immediate_parent then Error "db_directory_insecure"
        else Error "db_path_symlink"
      else if st.st_kind <> Unix.S_DIR then
        Error "db_directory_insecure"
      else if is_immediate_parent then begin
        if st.st_uid <> Unix.getuid () then
          Error "db_directory_insecure"
        else if (st.st_perm land 0o777) <> 0o700 then
          Error "db_directory_insecure"
        else
          Ok ()
      end else begin
        let uid = Unix.getuid () in
        if st.st_uid <> uid && st.st_uid <> 0 then
          Error "db_directory_insecure"
        else
          (* Only exact root-owned sticky /tmp is exempt from group/other writable check *)
          let is_root_sticky_tmp =
            (current = "/tmp") && st.st_uid = 0 && ((st.st_perm land 0o1000) <> 0)
          in
          if is_root_sticky_tmp then
            Ok ()
          else
            let group_or_other_writable = (st.st_perm land 0o022) <> 0 in
            if group_or_other_writable then
              Error "db_directory_insecure"
            else
              Ok ()
      end
    with
    | Unix.Unix_error (Unix.ENOENT, _, _) -> Error "db_directory_insecure"
    | _ -> Error "db_directory_insecure"
  in
  let* () = check_component "/" (parent_dir = "/") in
  let rec walk current = function
    | [] -> Ok ()
    | comp :: rest ->
        let next = if current = "/" then "/" ^ comp else current ^ "/" ^ comp in
        let is_parent = (rest = []) in
        let* () = check_component next is_parent in
        walk next rest
  in
  walk "/" components

let check_new_db_path (path : string) : (unit, string) result =
  let ( let* ) = Result.bind in
  let* () = check_ancestor_paths path in
  if Sys.file_exists path then Error "db_already_exists"
  else
    try
      ignore (Unix.lstat path);
      Error "db_already_exists"
    with
    | Unix.Unix_error (Unix.ENOENT, _, _) -> Ok ()
    | _ -> Error "db_path_invalid"

let check_existing_db_path (path : string) : (int * int, string) result =
  let ( let* ) = Result.bind in
  let* () = check_ancestor_paths path in
  try
    let st = Unix.lstat path in
    if st.st_kind <> Unix.S_REG then Error "db_path_symlink"
    else if st.st_uid <> Unix.getuid () then Error "db_file_insecure"
    else if st.st_nlink <> 1 then Error "db_file_insecure"
    else if (st.st_perm land 0o777) <> 0o600 then Error "db_file_insecure"
    else Ok (st.st_dev, st.st_ino)
  with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> Error "db_not_found"
  | _ -> Error "db_path_invalid"

let fsync_dir (dir_path : string) : (unit, string) result =
  try
    let fd = Unix.openfile dir_path [Unix.O_RDONLY; Unix.O_CLOEXEC] 0 in
    Fun.protect
      ~finally:(fun () -> try Unix.close fd with _ -> ())
      (fun () ->
        try
          Unix.fsync fd;
          Ok ()
        with _ -> Error "fsync_failed")
  with _ -> Error "fsync_failed"

let with_process_lock (db_path : string) (f : unit -> ('a, string) result) : ('a, string) result =
  let lock_path = db_path ^ ".process_lock" in
  let check_lock_stat () =
    try
      let st = Unix.lstat lock_path in
      if st.st_kind <> Unix.S_REG then Error "db_path_symlink"
      else if st.st_uid <> Unix.getuid () then Error "db_file_insecure"
      else if st.st_nlink <> 1 then Error "db_file_insecure"
      else Ok ()
    with
    | Unix.Unix_error (Unix.ENOENT, _, _) -> Ok ()
    | _ -> Error "db_file_insecure"
  in
  match check_lock_stat () with
  | Error e -> Error e
  | Ok () ->
      let fd_opt =
        try
          let fd = Unix.openfile lock_path [Unix.O_CREAT; Unix.O_RDWR; Unix.O_CLOEXEC] 0o600 in
          let st = Unix.fstat fd in
          if st.st_uid <> Unix.getuid () || st.st_nlink <> 1 then begin
            Unix.close fd;
            None
          end else
            Some fd
        with _ -> None
      in
      match fd_opt with
      | None -> Error "db_locked"
      | Some fd ->
          let locked =
            try
              Unix.lockf fd Unix.F_TLOCK 0;
              true
            with _ -> false
          in
          if not locked then begin
            Unix.close fd;
            Error "db_locked"
          end else
            Fun.protect
              ~finally:(fun () ->
                (try Unix.lockf fd Unix.F_ULOCK 0 with _ -> ());
                (try Unix.close fd with _ -> ()))
              f

let verify_file_identity (path : string) ((orig_dev, orig_ino) : int * int) : (unit, string) result =
  try
    let st = Unix.lstat path in
    if st.st_dev = orig_dev && st.st_ino = orig_ino then Ok ()
    else Error "db_file_replaced"
  with _ -> Error "db_file_replaced"

(* SQLite Parameter and Binding Helpers *)
let check_bind rc =
  if rc <> Sqlite3.Rc.OK then Error "sqlite_error" else Ok ()

let bind_text stmt idx text =
  check_bind (Sqlite3.bind_text stmt idx text)

let bind_int stmt idx v =
  check_bind (Sqlite3.bind_int stmt idx v)

let bind_int64 stmt idx v =
  check_bind (Sqlite3.bind_int64 stmt idx v)

let bind_blob stmt idx blob =
  check_bind (Sqlite3.bind_blob stmt idx blob)

let exec_sql db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> Ok ()
  | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
  | Sqlite3.Rc.FULL -> Error "capacity_exhausted"
  | _ -> Error "sqlite_error"

(* Guaranteed Prepared Statement Finalization via Fun.protect *)
let with_prepared_stmt db sql f =
  let stmt =
    try Sqlite3.prepare db sql
    with _ -> failwith "sqlite_prepare_failed"
  in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () -> f stmt)

(* Pragmas and Schema Helpers *)
let query_single_string db sql =
  with_prepared_stmt db sql (fun stmt ->
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_text stmt 0)
    | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
    | _ -> Error "pragma_verification_failed")

let query_single_int db sql =
  with_prepared_stmt db sql (fun stmt ->
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int stmt 0)
    | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
    | _ -> Error "pragma_verification_failed")

let exec_pragma db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> Ok ()
  | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
  | _ -> Error "pragma_verification_failed"

let setup_new_db_pragmas db =
  Sqlite3.busy_timeout db sqlite_busy_timeout_ms;
  match query_single_string db "PRAGMA journal_mode = WAL;" with
  | Error e -> Error e
  | Ok jm ->
      if String.lowercase_ascii jm <> "wal" then Error "invalid_journal_mode"
      else
        match exec_pragma db "PRAGMA synchronous = FULL;" with
        | Error e -> Error e
        | Ok () ->
            match query_single_int db "PRAGMA synchronous;" with
            | Ok 2 ->
                (match exec_pragma db "PRAGMA foreign_keys = ON;" with
                | Error e -> Error e
                | Ok () ->
                    match query_single_int db "PRAGMA foreign_keys;" with
                    | Ok 1 ->
                        (match query_single_int db "PRAGMA page_size;" with
                        | Ok page_size when page_size > 0 ->
                            let max_pages = max_db_main_bytes / page_size in
                            (match exec_pragma db (Printf.sprintf "PRAGMA max_page_count = %d;" max_pages) with
                            | Error e -> Error e
                            | Ok () -> Ok ())
                        | _ -> Error "pragma_verification_failed")
                    | _ -> Error "pragma_verification_failed")
            | _ -> Error "pragma_verification_failed"

let verify_existing_db_pragmas db =
  Sqlite3.busy_timeout db sqlite_busy_timeout_ms;
  match query_single_string db "PRAGMA journal_mode;" with
  | Error e -> Error e
  | Ok jm ->
      if String.lowercase_ascii jm <> "wal" then Error "invalid_journal_mode"
      else
        match exec_pragma db "PRAGMA synchronous = FULL;" with
        | Error e -> Error e
        | Ok () ->
            match query_single_int db "PRAGMA synchronous;" with
            | Ok 2 ->
                (match exec_pragma db "PRAGMA foreign_keys = ON;" with
                | Error e -> Error e
                | Ok () ->
                    match query_single_int db "PRAGMA foreign_keys;" with
                    | Ok 1 ->
                        (match query_single_int db "PRAGMA page_size;" with
                        | Ok page_size when page_size > 0 ->
                            let max_pages = max_db_main_bytes / page_size in
                            (match exec_pragma db (Printf.sprintf "PRAGMA max_page_count = %d;" max_pages) with
                            | Error e -> Error e
                            | Ok () -> Ok ())
                        | _ -> Error "pragma_verification_failed")
                    | _ -> Error "pragma_verification_failed")
            | _ -> Error "pragma_verification_failed"

let verify_schema db (expected_bot_id : string option) : (int * string * int * int, string) result =
  let ( let* ) = Result.bind in
  let objs_res =
    with_prepared_stmt db "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name;" (fun stmt_objs ->
      let rec collect_objs acc =
        match Sqlite3.step stmt_objs with
        | Sqlite3.Rc.ROW ->
            let t = Sqlite3.column_text stmt_objs 0 in
            let n = Sqlite3.column_text stmt_objs 1 in
            let s = Sqlite3.column_text stmt_objs 2 in
            collect_objs ((t, n, s) :: acc)
        | Sqlite3.Rc.DONE -> Ok (List.rev acc)
        | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
        | _ -> Error "sqlite_error"
      in
      collect_objs [])
  in
  let* actual_objs = objs_res in
  let match_obj (t1, n1, s1) (t2, n2, s2) =
    String.equal t1 t2 && String.equal n1 n2 && String.equal s1 s2
  in
  if not (List.equal match_obj actual_objs expected_schema_objects) then
    Error "schema_mismatch"
  else
    let get_meta key =
      with_prepared_stmt db "SELECT value FROM meta WHERE key = ?;" (fun stmt ->
        let* () = bind_text stmt 1 key in
        match Sqlite3.step stmt with
        | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_text stmt 0)
        | Sqlite3.Rc.DONE -> Error "schema_mismatch"
        | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
        | _ -> Error "sqlite_error")
    in
    let* s = get_meta "schema" in
    if s <> schema_version then Error "schema_mismatch"
    else
      let* bot_id_stored = get_meta "bot_id" in
      let* () =
        match expected_bot_id with
        | Some expected_id when expected_id <> bot_id_stored -> Error "bot_id_mismatch"
        | _ -> Ok ()
      in
      let* gen_str = get_meta "generation" in
      let gen = try int_of_string gen_str with _ -> -1 in
      if gen < 1 then Error "schema_mismatch"
      else
        let* rr_str = get_meta "reserved_rows" in
        let rr = try int_of_string rr_str with _ -> -1 in
        if rr < 0 then Error "schema_mismatch"
        else
          let* rrec_str = get_meta "reserved_receipts" in
          let rrec = try int_of_string rrec_str with _ -> -1 in
          if rrec < 0 then Error "schema_mismatch"
          else Ok (gen, bot_id_stored, rr, rrec)

(* Operation 1: initialize_new with Atomic Schema + 5 Meta Entries Transaction & Fsync *)
let initialize_new (db_path : string) (bot_id : string) : (int, string) result =
  let ( let* ) = Result.bind in
  if not (is_valid_bot_id bot_id) then Error "invalid_bot_id"
  else
    let* () = check_new_db_path db_path in
    let dir = Filename.dirname db_path in
    let fd_opt =
      try
        Some (Unix.openfile db_path [Unix.O_CREAT; Unix.O_EXCL; Unix.O_RDWR; Unix.O_CLOEXEC] 0o600)
      with
      | Unix.Unix_error (Unix.EEXIST, _, _) -> None
      | _ -> None
    in
    match fd_opt with
    | None ->
        if Sys.file_exists db_path then Error "db_already_exists"
        else Error "db_path_invalid"
    | Some fd ->
        Unix.close fd;
        with_process_lock db_path (fun () ->
          let db =
            try Sqlite3.db_open db_path
            with _ -> failwith "db_open_failed"
          in
          Fun.protect
            ~finally:(fun () -> ignore (Sqlite3.db_close db))
            (fun () ->
              Unix.chmod db_path 0o600;
              let* () = setup_new_db_pragmas db in
              let* () = exec_sql db "BEGIN IMMEDIATE;" in
              let tx_res =
                try
                  let ddl =
                    "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);\n" ^
                    "CREATE TABLE kv_rows (key TEXT PRIMARY KEY, version INTEGER NOT NULL, canonical_value_bytes BLOB NOT NULL, sha256 TEXT NOT NULL);\n" ^
                    "CREATE TABLE receipts (operation_id TEXT PRIMARY KEY, request_digest TEXT NOT NULL, generation INTEGER NOT NULL, summary_json TEXT NOT NULL, committed_utc_us INTEGER NOT NULL);\n" ^
                    "CREATE TRIGGER receipts_no_update BEFORE UPDATE ON receipts BEGIN SELECT RAISE(FAIL, 'receipts are append-only'); END;\n" ^
                    "CREATE TRIGGER receipts_no_delete BEFORE DELETE ON receipts BEGIN SELECT RAISE(FAIL, 'receipts are append-only'); END;\n"
                  in
                  let* () = exec_sql db ddl in
                  trigger_stage_hook Init_after_ddl;
                  let insert_meta key value =
                    with_prepared_stmt db "INSERT INTO meta (key, value) VALUES (?, ?);" (fun stmt ->
                      let* () = bind_text stmt 1 key in
                      let* () = bind_text stmt 2 value in
                      let rc = Sqlite3.step stmt in
                      if rc = Sqlite3.Rc.DONE then Ok ()
                      else if rc = Sqlite3.Rc.BUSY then Error "sqlite_busy"
                      else Error "sqlite_error")
                  in
                  let* () = insert_meta "schema" schema_version in
                  let* () = insert_meta "bot_id" bot_id in
                  let* () = insert_meta "generation" "1" in
                  let* () = insert_meta "reserved_rows" "0" in
                  let* () = insert_meta "reserved_receipts" "0" in
                  trigger_stage_hook Init_after_meta;
                  Ok ()
                with _ ->
                  ignore (Sqlite3.exec db "ROLLBACK;");
                  Error "sqlite_error"
              in
              match tx_res with
              | Error err ->
                  ignore (Sqlite3.exec db "ROLLBACK;");
                  Error err
              | Ok () ->
                  let commit_res =
                    try
                      if !test_hook_fail_init_during_commit then begin
                        ignore (Sqlite3.exec db "ROLLBACK;");
                        Error "commit_uncertain"
                      end else
                        match exec_sql db "COMMIT;" with
                        | Error _ -> Error "commit_uncertain"
                        | Ok () -> Ok ()
                    with _ ->
                      Error "commit_uncertain"
                  in
                  match commit_res with
                  | Error err -> Error err
                  | Ok () ->
                      if !test_hook_fail_init_after_commit then
                        Error "commit_uncertain"
                      else
                        match fsync_dir dir with
                        | Error _ -> Error "commit_uncertain"
                        | Ok () -> Ok 1))

(* Operation 2: read_keys *)
let read_keys (db_path : string) (keys : string list) : (int * row_result list, string) result =
  let ( let* ) = Result.bind in
  if List.length keys > max_read_keys then Error "read_keys_too_many"
  else if List.exists (fun k -> String.length k = 0 || String.length k > max_key_bytes) keys then Error "key_too_long"
  else
    let* file_id = check_existing_db_path db_path in
    with_process_lock db_path (fun () ->
      let db =
        try Sqlite3.db_open ~mode:`NO_CREATE db_path
        with _ -> failwith "db_open_failed"
      in
      Fun.protect
        ~finally:(fun () -> ignore (Sqlite3.db_close db))
        (fun () ->
          let* () = verify_file_identity db_path file_id in
          let* () = verify_existing_db_pragmas db in
          let* () = exec_sql db "BEGIN;" in
          let tx_res =
            try
              let* (gen, _, _, _) = verify_schema db None in
              let rec fetch_rows acc total_bytes = function
                | [] -> Ok (List.rev acc, total_bytes)
                | k :: rest ->
                    let row_res =
                      with_prepared_stmt db "SELECT version, canonical_value_bytes, sha256 FROM kv_rows WHERE key = ?;" (fun stmt ->
                        let* () = bind_text stmt 1 k in
                        match Sqlite3.step stmt with
                        | Sqlite3.Rc.ROW ->
                            let ver = Sqlite3.column_int stmt 0 in
                            let raw = Sqlite3.column_blob stmt 1 in
                            let sha = Sqlite3.column_text stmt 2 in
                            if not (String.equal (sha256_hex raw) sha) then
                              Error "corrupt_row_hash"
                            else
                              let enc = encode_canonical_base64 raw in
                              let b_len = String.length raw in
                              let row = {
                                key = k;
                                exists = true;
                                version = ver;
                                canonical_value_base64 = enc;
                                sha256 = sha;
                              } in
                              Ok (row, b_len)
                        | Sqlite3.Rc.DONE ->
                            let row = {
                              key = k;
                              exists = false;
                              version = 0;
                              canonical_value_base64 = "";
                              sha256 = "";
                            } in
                            Ok (row, 0)
                        | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
                        | _ -> Error "sqlite_error")
                    in
                    let* (row, b_len) = row_res in
                    let new_total = total_bytes + b_len in
                    if new_total > max_aggregate_decoded_values then
                      Error "aggregate_values_too_large"
                    else
                      fetch_rows (row :: acc) new_total rest
              in
              let* (rows, _) = fetch_rows [] 0 keys in
              let* () = exec_sql db "COMMIT;" in
              Ok (gen, rows)
            with _ ->
              ignore (Sqlite3.exec db "ROLLBACK;");
              Error "sqlite_error"
          in
          match tx_res with
          | Ok result -> Ok result
          | Error err ->
              ignore (Sqlite3.exec db "ROLLBACK;");
              Error err))

(* Operation 3: read_inbox_index *)
let read_inbox_index (db_path : string) (limit : int) (after_key : string option) : (int * string list, string) result =
  let ( let* ) = Result.bind in
  if limit <= 0 || limit > max_inbox_index_limit then Error "invalid_limit"
  else
    let* () =
      match after_key with
      | None -> Ok ()
      | Some ak ->
          if not (String.starts_with ~prefix:"inbox/" ak) then Error "invalid_after_key"
          else if String.length ak <= 6 || String.length ak > max_key_bytes then Error "invalid_after_key"
          else if ak >= "inbox0" then Error "invalid_after_key"
          else Ok ()
    in
    let* file_id = check_existing_db_path db_path in
    with_process_lock db_path (fun () ->
      let db =
        try Sqlite3.db_open ~mode:`NO_CREATE db_path
        with _ -> failwith "db_open_failed"
      in
      Fun.protect
        ~finally:(fun () -> ignore (Sqlite3.db_close db))
        (fun () ->
          let* () = verify_file_identity db_path file_id in
          let* () = verify_existing_db_pragmas db in
          let* () = exec_sql db "BEGIN;" in
          let tx_res =
            try
              let* (gen, _, _, _) = verify_schema db None in
              let sql =
                match after_key with
                | None ->
                    "SELECT key FROM kv_rows WHERE key >= 'inbox/' AND key < 'inbox0' ORDER BY key ASC LIMIT ?;"
                | Some _ ->
                    "SELECT key FROM kv_rows WHERE key > ? AND key >= 'inbox/' AND key < 'inbox0' ORDER BY key ASC LIMIT ?;"
              in
              let keys_res =
                with_prepared_stmt db sql (fun stmt ->
                  let* () =
                    match after_key with
                    | None -> bind_int stmt 1 limit
                    | Some ak ->
                        let* () = bind_text stmt 1 ak in
                        bind_int stmt 2 limit
                  in
                  let rec collect acc =
                    match Sqlite3.step stmt with
                    | Sqlite3.Rc.ROW ->
                        let k = Sqlite3.column_text stmt 0 in
                        collect (k :: acc)
                    | Sqlite3.Rc.DONE -> Ok (List.rev acc)
                    | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
                    | _ -> Error "sqlite_error"
                  in
                  collect [])
              in
              let* keys = keys_res in
              let* () = exec_sql db "COMMIT;" in
              Ok (gen, keys)
            with _ ->
              ignore (Sqlite3.exec db "ROLLBACK;");
              Error "sqlite_error"
          in
          match tx_res with
          | Ok result -> Ok result
          | Error err ->
              ignore (Sqlite3.exec db "ROLLBACK;");
              Error err))

(* Operation 4: lookup_operation *)
let lookup_operation (db_path : string) (operation_id : string) : (receipt option, string) result =
  let ( let* ) = Result.bind in
  if String.length operation_id = 0 || String.length operation_id > max_operation_id_bytes then Error "invalid_operation_id"
  else
    let* file_id = check_existing_db_path db_path in
    with_process_lock db_path (fun () ->
      let db =
        try Sqlite3.db_open ~mode:`NO_CREATE db_path
        with _ -> failwith "db_open_failed"
      in
      Fun.protect
        ~finally:(fun () -> ignore (Sqlite3.db_close db))
        (fun () ->
          let* () = verify_file_identity db_path file_id in
          let* () = verify_existing_db_pragmas db in
          let* () = exec_sql db "BEGIN;" in
          let tx_res =
            try
              let* _ = verify_schema db None in
              let opt_res =
                with_prepared_stmt db "SELECT operation_id, request_digest, generation, summary_json, committed_utc_us FROM receipts WHERE operation_id = ?;" (fun stmt ->
                  let* () = bind_text stmt 1 operation_id in
                  match Sqlite3.step stmt with
                  | Sqlite3.Rc.ROW ->
                      let op_id = Sqlite3.column_text stmt 0 in
                      let digest = Sqlite3.column_text stmt 1 in
                      let gen = Sqlite3.column_int stmt 2 in
                      let summary = Sqlite3.column_text stmt 3 in
                      let ts = Sqlite3.column_int64 stmt 4 in
                      Ok (Some {
                        operation_id = op_id;
                        request_digest = digest;
                        generation = gen;
                        summary_json = summary;
                        committed_utc_us = ts;
                      })
                  | Sqlite3.Rc.DONE -> Ok None
                  | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
                  | _ -> Error "sqlite_error")
              in
              let* opt = opt_res in
              let* () = exec_sql db "COMMIT;" in
              Ok opt
            with _ ->
              ignore (Sqlite3.exec db "ROLLBACK;");
              Error "sqlite_error"
          in
          match tx_res with
          | Ok result -> Ok result
          | Error err ->
              ignore (Sqlite3.exec db "ROLLBACK;");
              Error err))

(* Operation 5: apply with Full Validation, Injective Replay Matching & Commit Uncertainty *)
let apply (req : apply_request) : (apply_result, string) result =
  let ( let* ) = Result.bind in
  let* () =
    if String.length req.bot_id = 0 then Error "invalid_bot_id"
    else if String.length req.operation_id = 0 || String.length req.operation_id > max_operation_id_bytes then Error "invalid_operation_id"
    else if not (is_valid_hex_64 req.request_digest) then Error "request_digest_invalid"
    else if req.expected_generation < 1 then Error "stale_generation"
    else if List.length req.read_set_assertions > max_read_set_assertions then Error "read_set_too_many"
    else if List.length req.changes > max_changes then Error "changes_too_many"
    else if String.length req.summary_json > max_receipt_summary_bytes then Error "receipt_too_large"
    else if req.reservation_delta.rows > max_reservation_delta_rows || req.reservation_delta.receipts > max_reservation_delta_receipts then Error "invalid_reservation_delta"
    else if req.reservation_delta.rows < -max_rows_capacity || req.reservation_delta.receipts < -max_receipts_capacity then Error "invalid_reservation_delta"
    else Ok ()
  in
  let* () =
    match validate_strict_json req.summary_json with
    | Ok () -> Ok ()
    | Error _ -> Error "invalid_json"
  in
  let key_valid k = String.length k > 0 && String.length k <= max_key_bytes in
  let* () =
    let rec check_rs = function
      | [] -> Ok ()
      | (a : read_set_assertion) :: rest ->
          if not (key_valid a.key) then Error "key_too_long"
          else if a.expected_version < 0 then Error "invalid_read_set_assertion"
          else if a.expected_version = 0 && a.expected_sha256 <> "" then Error "invalid_read_set_assertion"
          else check_rs rest
    in
    check_rs req.read_set_assertions
  in
  let* () =
    let rec check_ch = function
      | [] -> Ok ()
      | (c : change) :: rest ->
          if not (key_valid c.key) then Error "key_too_long"
          else if c.expected_version < 0 then Error "invalid_change"
          else if c.expected_version = 0 && c.expected_sha256 <> "" then Error "invalid_change"
          else check_ch rest
    in
    check_ch req.changes
  in
  let rec has_dup_read_keys = function
    | [] -> false
    | (a : read_set_assertion) :: rest ->
        if List.exists (fun (a2 : read_set_assertion) -> a.key = a2.key) rest then true
        else has_dup_read_keys rest
  in
  let* () = if has_dup_read_keys req.read_set_assertions then Error "duplicate_read_set_key" else Ok () in
  let rec has_dup_change_keys = function
    | [] -> false
    | (c : change) :: rest ->
        if List.exists (fun (c2 : change) -> c.key = c2.key) rest then true
        else has_dup_change_keys rest
  in
  let* () = if has_dup_change_keys req.changes then Error "duplicate_change_key" else Ok () in
  let derived_digest =
    compute_request_digest
      ~bot_id:req.bot_id
      ~operation_id:req.operation_id
      ~expected_generation:req.expected_generation
      ~read_set:req.read_set_assertions
      ~changes:req.changes
      ~reservation_delta:req.reservation_delta
      ~summary_json:req.summary_json
  in
  let* () =
    if not (String.equal req.request_digest derived_digest) then Error "request_digest_mismatch"
    else Ok ()
  in
  let rec pre_decode acc total_bytes net_new = function
    | [] -> Ok (List.rev acc, net_new)
    | (c : change) :: rest ->
        let* decoded = decode_canonical_base64 c.new_value_base64 in
        let d_len = String.length decoded in
        if d_len > max_value_bytes then Error "value_too_large"
        else
          let new_total = total_bytes + d_len in
          if new_total > max_aggregate_decoded_values then Error "aggregate_values_too_large"
          else if not (is_valid_utf8 decoded) then Error "invalid_value"
          else
            match validate_strict_json decoded with
            | Error _ -> Error "invalid_value"
            | Ok () ->
                let sha = sha256_hex decoded in
                let new_net = if c.expected_version = 0 then net_new + 1 else net_new in
                pre_decode ((c, decoded, sha) :: acc) new_total new_net rest
  in
  let* decoded_changes, net_new_rows = pre_decode [] 0 0 req.changes in
  let* file_id = check_existing_db_path req.db_path in
  with_process_lock req.db_path (fun () ->
    let db =
      try Sqlite3.db_open ~mode:`NO_CREATE req.db_path
      with _ -> failwith "db_open_failed"
    in
    Fun.protect
      ~finally:(fun () -> ignore (Sqlite3.db_close db))
      (fun () ->
        let* () = verify_file_identity req.db_path file_id in
        let* () = verify_existing_db_pragmas db in
        let* () = exec_sql db "BEGIN IMMEDIATE;" in
        let rollback_and_return err =
          ignore (Sqlite3.exec db "ROLLBACK;");
          Error err
        in
        let tx_body () =
          let* (current_gen, _, cur_res_rows, cur_res_rec) = verify_schema db (Some req.bot_id) in
          let rep_res =
            with_prepared_stmt db "SELECT request_digest, generation, summary_json, committed_utc_us FROM receipts WHERE operation_id = ?;" (fun stmt_rep ->
              let* () = bind_text stmt_rep 1 req.operation_id in
              let rep_step = Sqlite3.step stmt_rep in
              if rep_step = Sqlite3.Rc.ROW then
                let dig = Sqlite3.column_text stmt_rep 0 in
                let gen = Sqlite3.column_int stmt_rep 1 in
                let sum = Sqlite3.column_text stmt_rep 2 in
                let ts = Sqlite3.column_int64 stmt_rep 3 in
                Ok (`Found (dig, gen, sum, ts))
              else if rep_step = Sqlite3.Rc.DONE then Ok `NotFound
              else if rep_step = Sqlite3.Rc.BUSY then Error "sqlite_busy"
              else Error "sqlite_error")
          in
          let* rep_data = rep_res in
          match rep_data with
          | `Found (dig, gen, sum, ts) ->
              if String.equal dig derived_digest then
                Ok (`Replay {
                  operation_id = req.operation_id;
                  request_digest = dig;
                  generation = gen;
                  summary_json = sum;
                  committed_utc_us = ts;
                })
              else
                Error "operation_collision_digest_mismatch"
          | `NotFound ->
              let* () = if current_gen <> req.expected_generation then Error "stale_generation" else Ok () in
              let check_read_set () =
                let rec loop = function
                  | [] -> Ok ()
                  | (a : read_set_assertion) :: rest ->
                      let row_status =
                        with_prepared_stmt db "SELECT version, canonical_value_bytes, sha256 FROM kv_rows WHERE key = ?;" (fun stmt ->
                          let* () = bind_text stmt 1 a.key in
                          match Sqlite3.step stmt with
                          | Sqlite3.Rc.ROW ->
                              let ver = Sqlite3.column_int stmt 0 in
                              let raw = Sqlite3.column_blob stmt 1 in
                              let sha = Sqlite3.column_text stmt 2 in
                              if not (String.equal (sha256_hex raw) sha) then Ok `Corrupt
                              else Ok (`Row (ver, sha))
                          | Sqlite3.Rc.DONE -> Ok `Absent
                          | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
                          | _ -> Error "sqlite_error")
                      in
                      let* status = row_status in
                      match status with
                      | `Corrupt -> Error "corrupt_row_hash"
                      | `Absent ->
                          if a.expected_version = 0 then loop rest
                          else Error "read_set_conflict"
                      | `Row (v, s) ->
                          if a.expected_version > 0 && a.expected_version = v && String.equal a.expected_sha256 s then loop rest
                          else Error "read_set_conflict"
                in
                loop req.read_set_assertions
              in
              let* () = check_read_set () in
              let check_cas () =
                let rec loop = function
                  | [] -> Ok ()
                  | (c, _, _) :: rest ->
                      let row_status =
                        with_prepared_stmt db "SELECT version, canonical_value_bytes, sha256 FROM kv_rows WHERE key = ?;" (fun stmt ->
                          let* () = bind_text stmt 1 c.key in
                          match Sqlite3.step stmt with
                          | Sqlite3.Rc.ROW ->
                              let ver = Sqlite3.column_int stmt 0 in
                              let raw = Sqlite3.column_blob stmt 1 in
                              let sha = Sqlite3.column_text stmt 2 in
                              if not (String.equal (sha256_hex raw) sha) then Ok `Corrupt
                              else Ok (`Row (ver, sha))
                          | Sqlite3.Rc.DONE -> Ok `Absent
                          | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
                          | _ -> Error "sqlite_error")
                      in
                      let* status = row_status in
                      match status with
                      | `Corrupt -> Error "corrupt_row_hash"
                      | `Absent ->
                          if c.expected_version = 0 then loop rest
                          else Error "cas_conflict"
                      | `Row (v, s) ->
                          if c.expected_version > 0 && c.expected_version = v && String.equal c.expected_sha256 s then loop rest
                          else Error "cas_conflict"
                in
                loop decoded_changes
              in
              let* () = check_cas () in
              let new_reserved_rows = cur_res_rows + req.reservation_delta.rows in
              let new_reserved_receipts = cur_res_rec + req.reservation_delta.receipts in
              let* () = if new_reserved_rows < 0 || new_reserved_receipts < 0 then Error "invalid_reservation_delta" else Ok () in
              let* cur_rows = query_single_int db "SELECT count(*) FROM kv_rows;" in
              let* cur_receipts = query_single_int db "SELECT count(*) FROM receipts;" in
              let total_row_demand = cur_rows + net_new_rows + new_reserved_rows in
              let total_receipt_demand = cur_receipts + 1 + new_reserved_receipts in
              let* () =
                if total_row_demand > max_rows_capacity || total_receipt_demand > max_receipts_capacity then
                  Error "capacity_exhausted"
                else Ok ()
              in
              let apply_mutations () =
                let rec loop idx = function
                  | [] -> Ok ()
                  | (c, raw, sha) :: rest ->
                      if idx > 0 then trigger_stage_hook Apply_between_rows;
                      let step_res =
                        if c.expected_version = 0 then
                          with_prepared_stmt db "INSERT INTO kv_rows (key, version, canonical_value_bytes, sha256) VALUES (?, 1, ?, ?);" (fun stmt ->
                            let* () = bind_text stmt 1 c.key in
                            let* () = bind_blob stmt 2 raw in
                            let* () = bind_text stmt 3 sha in
                            let step_rc = Sqlite3.step stmt in
                            match step_rc with
                            | Sqlite3.Rc.DONE -> Ok ()
                            | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
                            | Sqlite3.Rc.FULL -> Error "capacity_exhausted"
                            | _ -> Error "sqlite_error")
                        else
                          with_prepared_stmt db "UPDATE kv_rows SET version = ?, canonical_value_bytes = ?, sha256 = ? WHERE key = ?;" (fun stmt ->
                            let* () = bind_int stmt 1 (c.expected_version + 1) in
                            let* () = bind_blob stmt 2 raw in
                            let* () = bind_text stmt 3 sha in
                            let* () = bind_text stmt 4 c.key in
                            let step_rc = Sqlite3.step stmt in
                            match step_rc with
                            | Sqlite3.Rc.DONE -> Ok ()
                            | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
                            | Sqlite3.Rc.FULL -> Error "capacity_exhausted"
                            | _ -> Error "sqlite_error")
                      in
                      match step_res with
                      | Ok () -> loop (idx + 1) rest
                      | Error e -> Error e
                in
                loop 0 decoded_changes
              in
              let* () = apply_mutations () in
              let next_gen = current_gen + 1 in
              let update_meta key value =
                with_prepared_stmt db "UPDATE meta SET value = ? WHERE key = ?;" (fun stmt ->
                  let* () = bind_text stmt 1 value in
                  let* () = bind_text stmt 2 key in
                  let step_rc = Sqlite3.step stmt in
                  match step_rc with
                  | Sqlite3.Rc.DONE -> Ok ()
                  | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
                  | Sqlite3.Rc.FULL -> Error "capacity_exhausted"
                  | _ -> Error "sqlite_error")
              in
              let* () = update_meta "generation" (string_of_int next_gen) in
              let* () = update_meta "reserved_rows" (string_of_int new_reserved_rows) in
              let* () = update_meta "reserved_receipts" (string_of_int new_reserved_receipts) in
              let commit_ts = now_utc_us () in
              let ins_res =
                with_prepared_stmt db "INSERT INTO receipts (operation_id, request_digest, generation, summary_json, committed_utc_us) VALUES (?, ?, ?, ?, ?);" (fun stmt_ins ->
                  let* () = bind_text stmt_ins 1 req.operation_id in
                  let* () = bind_text stmt_ins 2 derived_digest in
                  let* () = bind_int stmt_ins 3 next_gen in
                  let* () = bind_text stmt_ins 4 req.summary_json in
                  let* () = bind_int64 stmt_ins 5 commit_ts in
                  let rec_rc = Sqlite3.step stmt_ins in
                  if rec_rc = Sqlite3.Rc.BUSY then Error "sqlite_busy"
                  else if rec_rc = Sqlite3.Rc.FULL then Error "capacity_exhausted"
                  else if rec_rc <> Sqlite3.Rc.DONE then Error "sqlite_error"
                  else Ok ())
              in
              let* () = ins_res in
              Ok (`Commit {
                operation_id = req.operation_id;
                request_digest = derived_digest;
                generation = next_gen;
                summary_json = req.summary_json;
                committed_utc_us = commit_ts;
              })
        in
        let tx_res =
          try tx_body ()
          with _ ->
            ignore (Sqlite3.exec db "ROLLBACK;");
            Error "sqlite_error"
        in
        match tx_res with
        | Error err -> rollback_and_return err
        | Ok (`Replay recpt) ->
            ignore (Sqlite3.exec db "ROLLBACK;");
            Ok { replay = true; receipt = recpt }
        | Ok (`Commit recpt) ->
            let pre_commit_res =
              try
                trigger_stage_hook Apply_pre_commit;
                Ok ()
              with _ ->
                ignore (Sqlite3.exec db "ROLLBACK;");
                Error "sqlite_error"
            in
            match pre_commit_res with
            | Error err -> rollback_and_return err
            | Ok () ->
                let commit_res =
                  try
                    if !test_hook_fail_apply_before_commit then begin
                      ignore (Sqlite3.exec db "ROLLBACK;");
                      Error "simulated_before_commit_failure"
                    end else if !test_hook_fail_apply_during_commit then begin
                      ignore (Sqlite3.exec db "COMMIT;");
                      Error "commit_uncertain"
                    end else
                      match exec_sql db "COMMIT;" with
                      | Error _ -> Error "commit_uncertain"
                      | Ok () -> Ok ()
                  with _ ->
                    Error "commit_uncertain"
                in
                match commit_res with
                | Error err -> Error err
                | Ok () ->
                    try
                      trigger_stage_hook Apply_post_commit_pre_reply;
                      if !test_hook_fail_apply_after_commit then
                        Error "commit_uncertain"
                      else
                        Ok { replay = false; receipt = recpt }
                    with _ ->
                      Error "commit_uncertain"))

(* Strict JSON Protocol Handler & Exact Schemas *)
let check_duplicate_keys json =
  let rec has_dup_in_list = function
    | [] -> false
    | (k, _) :: rest ->
        if List.exists (fun (k2, _) -> k = k2) rest then true
        else has_dup_in_list rest
  in
  let rec check = function
    | `Assoc fields ->
        if has_dup_in_list fields then true
        else List.exists (fun (_, v) -> check v) fields
    | `List items -> List.exists check items
    | _ -> false
  in
  check json

let check_allowed_fields (allowed : string list) (fields : (string * Yojson.Safe.t) list) : bool =
  List.for_all (fun (k, _) -> List.mem k allowed) fields

let allowed_init_fields = ["command"; "bot_id"; "db_path"]
let allowed_read_keys_fields = ["command"; "keys"; "db_path"]
let allowed_read_inbox_fields = ["command"; "limit"; "after_key"; "db_path"]
let allowed_lookup_fields = ["command"; "operation_id"; "db_path"]
let allowed_apply_fields = [
  "command"; "bot_id"; "operation_id"; "request_digest";
  "expected_generation"; "read_set_assertions"; "changes";
  "reservation_delta"; "summary_json"; "db_path"
]
let allowed_read_set_item_fields = ["key"; "expected_version"; "expected_sha256"]
let allowed_change_item_fields = ["key"; "expected_version"; "new_value_base64"; "expected_sha256"]
let allowed_res_delta_fields = ["rows"; "receipts"]

let make_error_json (err : string) : string =
  Yojson.Safe.to_string (`Assoc [ ("ok", `Bool false); ("error", `String err) ])

let run_command_json ?configured_db_path (input_str : string) : string =
  if String.length input_str > max_request_json_bytes then make_error_json "oversized_frame"
  else
    match validate_strict_json input_str with
    | Error "duplicate_json_keys" -> make_error_json "duplicate_json_keys"
    | Error _ -> make_error_json "invalid_json"
    | Ok () ->
        let parsed_opt =
          try Some (Yojson.Safe.from_string input_str)
          with _ -> None
        in
        match parsed_opt with
        | Some (`Assoc top_fields as json) ->
            if check_duplicate_keys json then make_error_json "duplicate_json_keys"
            else
              let get_field fld =
                try Some (List.assoc fld top_fields) with Not_found -> None
              in
              let resolve_db_path () =
                match get_field "db_path" with
                | None ->
                    (match configured_db_path with
                    | Some conf_p -> Ok conf_p
                    | None -> Error "db_path_invalid")
                | Some (`String p) ->
                    (match configured_db_path with
                    | Some conf_p when not (String.equal p conf_p) -> Error "db_path_mismatch"
                    | _ -> Ok p)
                | Some _ -> Error "invalid_json"
              in
              (match get_field "command" with
              | Some (`String "initialize_new") ->
                  if not (check_allowed_fields allowed_init_fields top_fields) then
                    make_error_json "unknown_json_field"
                  else
                    (match resolve_db_path () with
                    | Error err -> make_error_json err
                    | Ok db_path ->
                        let bot_id_opt =
                          match get_field "bot_id" with
                          | Some (`String s) when is_valid_bot_id s -> Some s
                          | Some (`Int i) ->
                              let s = string_of_int i in
                              if is_valid_bot_id s then Some s else None
                          | Some (`Intlit s) when is_valid_bot_id s -> Some s
                          | _ -> None
                        in
                        (match bot_id_opt with
                        | None -> make_error_json "invalid_bot_id"
                        | Some bot_id ->
                            (match initialize_new db_path bot_id with
                            | Ok gen -> Yojson.Safe.to_string (`Assoc [ ("ok", `Bool true); ("generation", `Int gen) ])
                            | Error err -> make_error_json err)))
              | Some (`String "read_keys") ->
                  if not (check_allowed_fields allowed_read_keys_fields top_fields) then
                    make_error_json "unknown_json_field"
                  else
                    (match resolve_db_path () with
                    | Error err -> make_error_json err
                    | Ok db_path ->
                        (match get_field "keys" with
                        | Some (`List key_nodes) ->
                            let parse_keys () =
                              let rec loop acc = function
                                | [] -> Ok (List.rev acc)
                                | (`String k) :: rest ->
                                    if String.length k = 0 || String.length k > max_key_bytes then Error "key_too_long"
                                    else loop (k :: acc) rest
                                | _ :: _ -> Error "invalid_json"
                              in
                              loop [] key_nodes
                            in
                            (match parse_keys () with
                            | Error err -> make_error_json err
                            | Ok keys ->
                                (match read_keys db_path keys with
                                | Ok (gen, rows) ->
                                    let row_nodes =
                                      List.map (fun (r : row_result) ->
                                        `Assoc [
                                          ("key", `String r.key);
                                          ("exists", `Bool r.exists);
                                          ("version", `Int r.version);
                                          ("canonical_value_base64", `String r.canonical_value_base64);
                                          ("sha256", `String r.sha256);
                                        ]
                                      ) rows
                                    in
                                    Yojson.Safe.to_string (`Assoc [
                                      ("ok", `Bool true);
                                      ("generation", `Int gen);
                                      ("rows", `List row_nodes);
                                    ])
                                | Error err -> make_error_json err))
                        | _ -> make_error_json "invalid_json"))
              | Some (`String "read_inbox_index") ->
                  if not (check_allowed_fields allowed_read_inbox_fields top_fields) then
                    make_error_json "unknown_json_field"
                  else
                    (match resolve_db_path () with
                    | Error err -> make_error_json err
                    | Ok db_path ->
                        (match get_field "limit" with
                        | Some (`Int limit) ->
                            let after_key_res =
                              match get_field "after_key" with
                              | None | Some `Null -> Ok None
                              | Some (`String ak) -> Ok (Some ak)
                              | Some _ -> Error "invalid_json"
                            in
                            (match after_key_res with
                            | Error e -> make_error_json e
                            | Ok after_key ->
                                match read_inbox_index db_path limit after_key with
                                | Ok (gen, keys) ->
                                    let key_nodes = List.map (fun k -> `String k) keys in
                                    Yojson.Safe.to_string (`Assoc [
                                      ("ok", `Bool true);
                                      ("generation", `Int gen);
                                      ("keys", `List key_nodes);
                                    ])
                                | Error err -> make_error_json err)
                        | _ -> make_error_json "invalid_limit"))
              | Some (`String "lookup_operation") ->
                  if not (check_allowed_fields allowed_lookup_fields top_fields) then
                    make_error_json "unknown_json_field"
                  else
                    (match resolve_db_path () with
                    | Error err -> make_error_json err
                    | Ok db_path ->
                        (match get_field "operation_id" with
                        | Some (`String op_id) when String.length op_id > 0 && String.length op_id <= max_operation_id_bytes ->
                            (match lookup_operation db_path op_id with
                            | Ok None ->
                                Yojson.Safe.to_string (`Assoc [
                                  ("ok", `Bool true);
                                  ("found", `Bool false);
                                ])
                            | Ok (Some r) ->
                                Yojson.Safe.to_string (`Assoc [
                                  ("ok", `Bool true);
                                  ("found", `Bool true);
                                  ("receipt", `Assoc [
                                    ("operation_id", `String r.operation_id);
                                    ("request_digest", `String r.request_digest);
                                    ("generation", `Int r.generation);
                                    ("summary_json", `String r.summary_json);
                                    ("committed_utc_us", `Int (Int64.to_int r.committed_utc_us));
                                  ]);
                                ])
                            | Error err -> make_error_json err)
                        | _ -> make_error_json "invalid_operation_id"))
              | Some (`String "apply") ->
                  if not (check_allowed_fields allowed_apply_fields top_fields) then
                    make_error_json "unknown_json_field"
                  else
                    (match resolve_db_path () with
                    | Error err -> make_error_json err
                    | Ok db_path ->
                        let bot_id_opt =
                          match get_field "bot_id" with
                          | Some (`String s) when is_valid_bot_id s -> Some s
                          | Some (`Int i) ->
                              let s = string_of_int i in
                              if is_valid_bot_id s then Some s else None
                          | Some (`Intlit s) when is_valid_bot_id s -> Some s
                          | _ -> None
                        in
                        let op_id_opt =
                          match get_field "operation_id" with
                          | Some (`String s) when String.length s > 0 && String.length s <= max_operation_id_bytes -> Some s
                          | _ -> None
                        in
                        let req_digest_opt =
                          match get_field "request_digest" with
                          | Some (`String s) when is_valid_hex_64 s -> Some s
                          | _ -> None
                        in
                        let exp_gen_opt =
                          match get_field "expected_generation" with
                          | Some (`Int i) when i >= 1 -> Some i
                          | _ -> None
                        in
                        (match bot_id_opt, op_id_opt, req_digest_opt, exp_gen_opt with
                        | None, _, _, _ -> make_error_json "invalid_bot_id"
                        | _, None, _, _ -> make_error_json "invalid_operation_id"
                        | _, _, None, _ -> make_error_json "request_digest_invalid"
                        | _, _, _, None -> make_error_json "stale_generation"
                        | Some bot_id, Some op_id, Some req_digest, Some exp_gen ->
                            let parse_read_set () =
                              match get_field "read_set_assertions" with
                              | Some (`List nodes) ->
                                  let rec loop acc = function
                                    | [] -> Ok (List.rev acc)
                                    | node :: rest ->
                                        (match node with
                                        | `Assoc fields when check_allowed_fields allowed_read_set_item_fields fields ->
                                            let k_opt = match List.assoc_opt "key" fields with Some (`String s) -> Some s | _ -> None in
                                            let v_opt = match List.assoc_opt "expected_version" fields with Some (`Int i) -> Some i | _ -> None in
                                            let sha_field = List.assoc_opt "expected_sha256" fields in
                                            (match k_opt, v_opt, sha_field with
                                            | Some k, Some 0, (None | Some `Null | Some (`String "")) ->
                                                loop ({ key = k; expected_version = 0; expected_sha256 = "" } :: acc) rest
                                            | Some k, Some v, Some (`String s) when v > 0 && is_valid_hex_64 s ->
                                                loop ({ key = k; expected_version = v; expected_sha256 = s } :: acc) rest
                                            | Some _, Some 0, Some _ -> Error "invalid_read_set_assertion"
                                            | Some _, Some v, _ when v > 0 -> Error "invalid_read_set_assertion"
                                            | _ -> Error "invalid_json")
                                        | `Assoc _ -> Error "unknown_json_field"
                                        | _ -> Error "invalid_json")
                                  in
                                  loop [] nodes
                              | _ -> Error "invalid_json"
                            in
                            let parse_changes () =
                              match get_field "changes" with
                              | Some (`List nodes) ->
                                  let rec loop acc = function
                                    | [] -> Ok (List.rev acc)
                                    | node :: rest ->
                                        (match node with
                                        | `Assoc fields when check_allowed_fields allowed_change_item_fields fields ->
                                            let k_opt = match List.assoc_opt "key" fields with Some (`String s) -> Some s | _ -> None in
                                            let v_opt = match List.assoc_opt "expected_version" fields with Some (`Int i) -> Some i | _ -> None in
                                            let b64_opt = match List.assoc_opt "new_value_base64" fields with Some (`String s) -> Some s | _ -> None in
                                            let sha_field = List.assoc_opt "expected_sha256" fields in
                                            (match k_opt, v_opt, b64_opt with
                                            | Some k, Some 0, Some b64 ->
                                                (match sha_field with
                                                | None | Some `Null | Some (`String "") ->
                                                    loop ({ key = k; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64 } :: acc) rest
                                                | Some _ -> Error "invalid_change")
                                            | Some k, Some v, Some b64 when v > 0 ->
                                                (match sha_field with
                                                | Some (`String s) when is_valid_hex_64 s ->
                                                    loop ({ key = k; expected_version = v; expected_sha256 = s; new_value_base64 = b64 } :: acc) rest
                                                | _ -> Error "invalid_change")
                                            | _ -> Error "invalid_json")
                                        | `Assoc _ -> Error "unknown_json_field"
                                        | _ -> Error "invalid_json")
                                  in
                                  loop [] nodes
                              | _ -> Error "invalid_json"
                            in
                            let parse_res_delta () =
                              match get_field "reservation_delta" with
                              | Some (`Assoc fields) when check_allowed_fields allowed_res_delta_fields fields ->
                                  let r_opt = match List.assoc_opt "rows" fields with Some (`Int i) -> Some i | _ -> None in
                                  let rec_opt = match List.assoc_opt "receipts" fields with Some (`Int i) -> Some i | _ -> None in
                                  (match r_opt, rec_opt with
                                  | Some rows, Some receipts -> Ok { rows; receipts }
                                  | _ -> Error "invalid_json")
                              | Some (`Assoc _) -> Error "unknown_json_field"
                              | _ -> Error "invalid_json"
                            in
                            let parse_summary () =
                              match get_field "summary_json" with
                              | Some (`String s) ->
                                  (match validate_strict_json s with
                                  | Ok () -> Ok s
                                  | Error _ -> Error "invalid_json")
                              | Some (`Assoc _ as node) ->
                                  let s = Yojson.Safe.to_string node in
                                  (match validate_strict_json s with
                                  | Ok () -> Ok s
                                  | Error _ -> Error "invalid_json")
                              | Some (`List _ as node) ->
                                  let s = Yojson.Safe.to_string node in
                                  (match validate_strict_json s with
                                  | Ok () -> Ok s
                                  | Error _ -> Error "invalid_json")
                              | _ -> Error "invalid_json"
                            in
                            (match parse_read_set (), parse_changes (), parse_res_delta (), parse_summary () with
                            | Error "unknown_json_field", _, _, _
                            | _, Error "unknown_json_field", _, _
                            | _, _, Error "unknown_json_field", _ -> make_error_json "unknown_json_field"
                            | Error "invalid_read_set_assertion", _, _, _ -> make_error_json "invalid_read_set_assertion"
                            | _, Error "invalid_change", _, _ -> make_error_json "invalid_change"
                            | Ok read_set, Ok changes, Ok res_delta, Ok summary_json_str ->
                                let req = {
                                  db_path;
                                  bot_id;
                                  operation_id = op_id;
                                  request_digest = req_digest;
                                  expected_generation = exp_gen;
                                  read_set_assertions = read_set;
                                  changes;
                                  reservation_delta = res_delta;
                                  summary_json = summary_json_str;
                                } in
                                (match apply req with
                                | Ok res ->
                                    Yojson.Safe.to_string (`Assoc [
                                      ("ok", `Bool true);
                                      ("replay", `Bool res.replay);
                                      ("receipt", `Assoc [
                                        ("operation_id", `String res.receipt.operation_id);
                                        ("request_digest", `String res.receipt.request_digest);
                                        ("generation", `Int res.receipt.generation);
                                        ("summary_json", `String res.receipt.summary_json);
                                        ("committed_utc_us", `Int (Int64.to_int res.receipt.committed_utc_us));
                                      ]);
                                    ])
                                | Error err -> make_error_json err)
                            | _ -> make_error_json "invalid_json")))
              | _ -> make_error_json "unknown_command")
        | _ -> make_error_json "invalid_json"
