(* Unified Operational System (UOS)
 * telegram_store.ml - Isolated Native OCaml SQLite Storage Kernel
 * Spec: uos.telegram-durable-store-corrected-development-spec.v1
 * Plan: uos/telegram-runtime/20261001-1150
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
let schema_version = "uos.telegram-store.v1"

(* Exact schema definitions in sqlite_master *)
let expected_schema_objects = [
  ("table", "kv_rows", "CREATE TABLE kv_rows (key TEXT PRIMARY KEY, version INTEGER NOT NULL, canonical_value_bytes BLOB NOT NULL, sha256 TEXT NOT NULL)");
  ("table", "meta", "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
  ("table", "receipts", "CREATE TABLE receipts (operation_id TEXT PRIMARY KEY, request_digest TEXT NOT NULL, generation INTEGER NOT NULL, summary_json TEXT NOT NULL, committed_utc_us INTEGER NOT NULL)");
  ("trigger", "receipts_no_delete", "CREATE TRIGGER receipts_no_delete BEFORE DELETE ON receipts BEGIN SELECT RAISE(FAIL, 'receipts are append-only'); END");
  ("trigger", "receipts_no_update", "CREATE TRIGGER receipts_no_update BEFORE UPDATE ON receipts BEGIN SELECT RAISE(FAIL, 'receipts are append-only'); END");
]

(* Base64 and Crypto Utilities *)
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

let now_utc_us () : int64 =
  Int64.of_float (Unix.gettimeofday () *. 1_000_000.0)

(* Canonical Request Digest Derivation *)
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
    List.sort (fun (a : change) (b : change) -> String.compare a.key b.key) changes
  in
  let buf = Buffer.create 2048 in
  Buffer.add_string buf "uos.telegram-store.apply.v1\n";
  Buffer.add_string buf ("bot:" ^ bot_id ^ "\n");
  Buffer.add_string buf ("op:" ^ operation_id ^ "\n");
  Buffer.add_string buf ("gen:" ^ string_of_int expected_generation ^ "\n");
  List.iter (fun (a : read_set_assertion) ->
    Buffer.add_string buf ("read:" ^ a.key ^ ":" ^ string_of_int a.expected_version ^ ":" ^ a.expected_sha256 ^ "\n")
  ) sorted_read_set;
  List.iter (fun (c : change) ->
    Buffer.add_string buf ("change:" ^ c.key ^ ":" ^ string_of_int c.expected_version ^ ":" ^ c.expected_sha256 ^ ":" ^ c.new_value_base64 ^ "\n")
  ) sorted_changes;
  Buffer.add_string buf ("res:" ^ string_of_int reservation_delta.rows ^ ":" ^ string_of_int reservation_delta.receipts ^ "\n");
  Buffer.add_string buf ("summary:" ^ summary_json ^ "\n");
  sha256_hex (Buffer.contents buf)

(* Path, Permissions, Hardlink, and Symlink Guards *)
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

let check_new_db_path (path : string) : (unit, string) result =
  match validate_path path with
  | Error e -> Error e
  | Ok () ->
      let dir = Filename.dirname path in
      match check_dir_permissions dir with
      | Error e -> Error e
      | Ok () ->
          if Sys.file_exists path then Error "db_already_exists"
          else
            try
              ignore (Unix.lstat path);
              Error "db_already_exists"
            with
            | Unix.Unix_error (Unix.ENOENT, _, _) -> Ok ()
            | _ -> Error "db_path_invalid"

let check_existing_db_path (path : string) : (int * int, string) result =
  match validate_path path with
  | Error e -> Error e
  | Ok () ->
      let dir = Filename.dirname path in
      match check_dir_permissions dir with
      | Error e -> Error e
      | Ok () ->
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

(* Pragmas and Schema Helpers *)
let query_single_string db sql =
  let stmt = Sqlite3.prepare db sql in
  let res =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_text stmt 0)
    | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
    | _ -> Error "pragma_verification_failed"
  in
  ignore (Sqlite3.finalize stmt);
  res

let query_single_int db sql =
  let stmt = Sqlite3.prepare db sql in
  let res =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int stmt 0)
    | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
    | _ -> Error "pragma_verification_failed"
  in
  ignore (Sqlite3.finalize stmt);
  res

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
  let stmt_objs = Sqlite3.prepare db "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name;" in
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
  let objs_res = collect_objs [] in
  ignore (Sqlite3.finalize stmt_objs);
  let* actual_objs = objs_res in
  let match_obj (t1, n1, s1) (t2, n2, s2) =
    String.equal t1 t2 && String.equal n1 n2 && String.equal s1 s2
  in
  if not (List.equal match_obj actual_objs expected_schema_objects) then
    Error "schema_mismatch"
  else
    let get_meta key =
      let stmt = Sqlite3.prepare db "SELECT value FROM meta WHERE key = ?;" in
      let* () = bind_text stmt 1 key in
      let res =
        match Sqlite3.step stmt with
        | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_text stmt 0)
        | Sqlite3.Rc.DONE -> Error "schema_mismatch"
        | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
        | _ -> Error "sqlite_error"
      in
      ignore (Sqlite3.finalize stmt);
      res
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

(* Operation 1: initialize_new *)
let initialize_new (db_path : string) (bot_id : string) : (int, string) result =
  let ( let* ) = Result.bind in
  if String.length bot_id = 0 then Error "invalid_bot_id"
  else
    let* () = validate_path db_path in
    let dir = Filename.dirname db_path in
    let* () = check_dir_permissions dir in
    (* Atomic exclusive creation using O_CREAT | O_EXCL *)
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
              let ddl =
                "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);\n" ^
                "CREATE TABLE kv_rows (key TEXT PRIMARY KEY, version INTEGER NOT NULL, canonical_value_bytes BLOB NOT NULL, sha256 TEXT NOT NULL);\n" ^
                "CREATE TABLE receipts (operation_id TEXT PRIMARY KEY, request_digest TEXT NOT NULL, generation INTEGER NOT NULL, summary_json TEXT NOT NULL, committed_utc_us INTEGER NOT NULL);\n" ^
                "CREATE TRIGGER receipts_no_update BEFORE UPDATE ON receipts BEGIN SELECT RAISE(FAIL, 'receipts are append-only'); END;\n" ^
                "CREATE TRIGGER receipts_no_delete BEFORE DELETE ON receipts BEGIN SELECT RAISE(FAIL, 'receipts are append-only'); END;\n"
              in
              let* () = exec_sql db ddl in
              let insert_meta key value =
                let stmt = Sqlite3.prepare db "INSERT INTO meta (key, value) VALUES (?, ?);" in
                let* () = bind_text stmt 1 key in
                let* () = bind_text stmt 2 value in
                let rc = Sqlite3.step stmt in
                ignore (Sqlite3.finalize stmt);
                if rc = Sqlite3.Rc.DONE then Ok ()
                else if rc = Sqlite3.Rc.BUSY then Error "sqlite_busy"
                else Error "sqlite_error"
              in
              let* () = insert_meta "schema" schema_version in
              let* () = insert_meta "bot_id" bot_id in
              let* () = insert_meta "generation" "1" in
              let* () = insert_meta "reserved_rows" "0" in
              let* () = insert_meta "reserved_receipts" "0" in
              let* () = fsync_dir dir in
              Ok 1))

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
          let rollback_and_return err =
            ignore (Sqlite3.exec db "ROLLBACK;");
            Error err
          in
          let tx_body () =
            let* (gen, _, _, _) = verify_schema db None in
            let rec fetch_rows acc total_bytes = function
              | [] -> Ok (List.rev acc, total_bytes)
              | k :: rest ->
                  let stmt = Sqlite3.prepare db "SELECT version, canonical_value_bytes, sha256 FROM kv_rows WHERE key = ?;" in
                  let* () = bind_text stmt 1 k in
                  let res =
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
                    | _ -> Error "sqlite_error"
                  in
                  ignore (Sqlite3.finalize stmt);
                  let* (row, b_len) = res in
                  let new_total = total_bytes + b_len in
                  if new_total > max_aggregate_decoded_values then
                    Error "aggregate_values_too_large"
                  else
                    fetch_rows (row :: acc) new_total rest
            in
            let* (rows, _) = fetch_rows [] 0 keys in
            let* () = exec_sql db "COMMIT;" in
            Ok (gen, rows)
          in
          match tx_body () with
          | Ok result -> Ok result
          | Error err -> rollback_and_return err))

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
          let rollback_and_return err =
            ignore (Sqlite3.exec db "ROLLBACK;");
            Error err
          in
          let tx_body () =
            let* (gen, _, _, _) = verify_schema db None in
            let sql =
              match after_key with
              | None ->
                  "SELECT key FROM kv_rows WHERE key >= 'inbox/' AND key < 'inbox0' ORDER BY key ASC LIMIT ?;"
              | Some _ ->
                  "SELECT key FROM kv_rows WHERE key > ? AND key >= 'inbox/' AND key < 'inbox0' ORDER BY key ASC LIMIT ?;"
            in
            let stmt = Sqlite3.prepare db sql in
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
            let res = collect [] in
            ignore (Sqlite3.finalize stmt);
            let* keys = res in
            let* () = exec_sql db "COMMIT;" in
            Ok (gen, keys)
          in
          match tx_body () with
          | Ok result -> Ok result
          | Error err -> rollback_and_return err))

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
          let rollback_and_return err =
            ignore (Sqlite3.exec db "ROLLBACK;");
            Error err
          in
          let tx_body () =
            let* _ = verify_schema db None in
            let stmt = Sqlite3.prepare db "SELECT operation_id, request_digest, generation, summary_json, committed_utc_us FROM receipts WHERE operation_id = ?;" in
            let* () = bind_text stmt 1 operation_id in
            let res =
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
              | _ -> Error "sqlite_error"
            in
            ignore (Sqlite3.finalize stmt);
            let* opt = res in
            let* () = exec_sql db "COMMIT;" in
            Ok opt
          in
          match tx_body () with
          | Ok result -> Ok result
          | Error err -> rollback_and_return err))

(* Operation 5: apply *)
let apply (req : apply_request) : (apply_result, string) result =
  let ( let* ) = Result.bind in
  let* () =
    if String.length req.bot_id = 0 then Error "invalid_bot_id"
    else if String.length req.operation_id = 0 || String.length req.operation_id > max_operation_id_bytes then Error "invalid_operation_id"
    else if String.length req.request_digest = 0 || String.length req.request_digest > max_request_digest_bytes then Error "request_digest_invalid"
    else if req.expected_generation < 1 then Error "stale_generation"
    else if List.length req.read_set_assertions > max_read_set_assertions then Error "read_set_too_many"
    else if List.length req.changes > max_changes then Error "changes_too_many"
    else if String.length req.summary_json > max_receipt_summary_bytes then Error "receipt_too_large"
    else if req.reservation_delta.rows > max_reservation_delta_rows || req.reservation_delta.receipts > max_reservation_delta_receipts then Error "invalid_reservation_delta"
    else if req.reservation_delta.rows < -max_rows_capacity || req.reservation_delta.receipts < -max_receipts_capacity then Error "invalid_reservation_delta"
    else Ok ()
  in
  let key_valid k = String.length k > 0 && String.length k <= max_key_bytes in
  let* () =
    if List.exists (fun (a : read_set_assertion) -> not (key_valid a.key)) req.read_set_assertions then Error "key_too_long"
    else if List.exists (fun (c : change) -> not (key_valid c.key)) req.changes then Error "key_too_long"
    else Ok ()
  in
  let rec has_dup_keys = function
    | [] -> false
    | (c : change) :: rest -> if List.exists (fun (c2 : change) -> c.key = c2.key) rest then true else has_dup_keys rest
  in
  let* () = if has_dup_keys req.changes then Error "duplicate_change_key" else Ok () in
  (* Independently derive canonical request digest from actual parameters *)
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
          else
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
          (* MUST verify bot_id and schema BEFORE checking replay *)
          let* (current_gen, _, cur_res_rows, cur_res_rec) = verify_schema db (Some req.bot_id) in
          let stmt_rep = Sqlite3.prepare db "SELECT request_digest, generation, summary_json, committed_utc_us FROM receipts WHERE operation_id = ?;" in
          let* () = bind_text stmt_rep 1 req.operation_id in
          let rep_step = Sqlite3.step stmt_rep in
          let rep_data =
            if rep_step = Sqlite3.Rc.ROW then
              let dig = Sqlite3.column_text stmt_rep 0 in
              let gen = Sqlite3.column_int stmt_rep 1 in
              let sum = Sqlite3.column_text stmt_rep 2 in
              let ts = Sqlite3.column_int64 stmt_rep 3 in
              `Found (dig, gen, sum, ts)
            else if rep_step = Sqlite3.Rc.DONE then `NotFound
            else if rep_step = Sqlite3.Rc.BUSY then `Busy
            else `SqlError
          in
          ignore (Sqlite3.finalize stmt_rep);
          match rep_data with
          | `Busy -> Error "sqlite_busy"
          | `SqlError -> Error "sqlite_error"
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
                      let stmt = Sqlite3.prepare db "SELECT version, canonical_value_bytes, sha256 FROM kv_rows WHERE key = ?;" in
                      let* () = bind_text stmt 1 a.key in
                      let status =
                        match Sqlite3.step stmt with
                        | Sqlite3.Rc.ROW ->
                            let ver = Sqlite3.column_int stmt 0 in
                            let raw = Sqlite3.column_blob stmt 1 in
                            let sha = Sqlite3.column_text stmt 2 in
                            if not (String.equal (sha256_hex raw) sha) then `Corrupt
                            else `Row (ver, sha)
                        | Sqlite3.Rc.DONE -> `Absent
                        | Sqlite3.Rc.BUSY -> `Busy
                        | _ -> `SqlError
                      in
                      ignore (Sqlite3.finalize stmt);
                      match status with
                      | `Busy -> Error "sqlite_busy"
                      | `SqlError -> Error "sqlite_error"
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
                      let stmt = Sqlite3.prepare db "SELECT version, canonical_value_bytes, sha256 FROM kv_rows WHERE key = ?;" in
                      let* () = bind_text stmt 1 c.key in
                      let status =
                        match Sqlite3.step stmt with
                        | Sqlite3.Rc.ROW ->
                            let ver = Sqlite3.column_int stmt 0 in
                            let raw = Sqlite3.column_blob stmt 1 in
                            let sha = Sqlite3.column_text stmt 2 in
                            if not (String.equal (sha256_hex raw) sha) then `Corrupt
                            else `Row (ver, sha)
                        | Sqlite3.Rc.DONE -> `Absent
                        | Sqlite3.Rc.BUSY -> `Busy
                        | _ -> `SqlError
                      in
                      ignore (Sqlite3.finalize stmt);
                      match status with
                      | `Busy -> Error "sqlite_busy"
                      | `SqlError -> Error "sqlite_error"
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
                let rec loop = function
                  | [] -> Ok ()
                  | (c, raw, sha) :: rest ->
                      if c.expected_version = 0 then begin
                        let stmt = Sqlite3.prepare db "INSERT INTO kv_rows (key, version, canonical_value_bytes, sha256) VALUES (?, 1, ?, ?);" in
                        let* () = bind_text stmt 1 c.key in
                        let* () = bind_blob stmt 2 raw in
                        let* () = bind_text stmt 3 sha in
                        let step_rc = Sqlite3.step stmt in
                        ignore (Sqlite3.finalize stmt);
                        match step_rc with
                        | Sqlite3.Rc.DONE -> loop rest
                        | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
                        | Sqlite3.Rc.FULL -> Error "capacity_exhausted"
                        | _ -> Error "sqlite_error"
                      end else begin
                        let stmt = Sqlite3.prepare db "UPDATE kv_rows SET version = ?, canonical_value_bytes = ?, sha256 = ? WHERE key = ?;" in
                        let* () = bind_int stmt 1 (c.expected_version + 1) in
                        let* () = bind_blob stmt 2 raw in
                        let* () = bind_text stmt 3 sha in
                        let* () = bind_text stmt 4 c.key in
                        let step_rc = Sqlite3.step stmt in
                        ignore (Sqlite3.finalize stmt);
                        match step_rc with
                        | Sqlite3.Rc.DONE -> loop rest
                        | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
                        | Sqlite3.Rc.FULL -> Error "capacity_exhausted"
                        | _ -> Error "sqlite_error"
                      end
                in
                loop decoded_changes
              in
              let* () = apply_mutations () in
              let next_gen = current_gen + 1 in
              let update_meta key value =
                let stmt = Sqlite3.prepare db "UPDATE meta SET value = ? WHERE key = ?;" in
                let* () = bind_text stmt 1 value in
                let* () = bind_text stmt 2 key in
                let step_rc = Sqlite3.step stmt in
                ignore (Sqlite3.finalize stmt);
                match step_rc with
                | Sqlite3.Rc.DONE -> Ok ()
                | Sqlite3.Rc.BUSY -> Error "sqlite_busy"
                | Sqlite3.Rc.FULL -> Error "capacity_exhausted"
                | _ -> Error "sqlite_error"
              in
              let* () = update_meta "generation" (string_of_int next_gen) in
              let* () = update_meta "reserved_rows" (string_of_int new_reserved_rows) in
              let* () = update_meta "reserved_receipts" (string_of_int new_reserved_receipts) in
              let commit_ts = now_utc_us () in
              let stmt_ins = Sqlite3.prepare db "INSERT INTO receipts (operation_id, request_digest, generation, summary_json, committed_utc_us) VALUES (?, ?, ?, ?, ?);" in
              let* () = bind_text stmt_ins 1 req.operation_id in
              let* () = bind_text stmt_ins 2 derived_digest in
              let* () = bind_int stmt_ins 3 next_gen in
              let* () = bind_text stmt_ins 4 req.summary_json in
              let* () = bind_int64 stmt_ins 5 commit_ts in
              let rec_rc = Sqlite3.step stmt_ins in
              ignore (Sqlite3.finalize stmt_ins);
              if rec_rc = Sqlite3.Rc.BUSY then Error "sqlite_busy"
              else if rec_rc = Sqlite3.Rc.FULL then Error "capacity_exhausted"
              else if rec_rc <> Sqlite3.Rc.DONE then Error "sqlite_error"
              else
                Ok (`Commit {
                  operation_id = req.operation_id;
                  request_digest = derived_digest;
                  generation = next_gen;
                  summary_json = req.summary_json;
                  committed_utc_us = commit_ts;
                })
        in
        match tx_body () with
        | Error err -> rollback_and_return err
        | Ok (`Replay recpt) ->
            ignore (Sqlite3.exec db "ROLLBACK;");
            Ok { replay = true; receipt = recpt }
        | Ok (`Commit recpt) ->
            let* () = exec_sql db "COMMIT;" in
            Ok { replay = false; receipt = recpt }))

(* JSON Protocol Handler *)
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

let make_error_json (err : string) : string =
  Yojson.Safe.to_string (`Assoc [ ("ok", `Bool false); ("error", `String err) ])

let run_command_json ?configured_db_path (input_str : string) : string =
  if String.length input_str > max_request_json_bytes then make_error_json "oversized_frame"
  else
    let parsed_opt =
      try Some (Yojson.Safe.from_string input_str)
      with _ -> None
    in
    match parsed_opt with
    | None -> make_error_json "invalid_json"
    | Some json ->
        if check_duplicate_keys json then make_error_json "duplicate_json_keys"
        else
          let get_field fld = function
            | `Assoc l -> (try Some (List.assoc fld l) with Not_found -> None)
            | _ -> None
          in
          let get_string fld obj =
            match get_field fld obj with
            | Some (`String s) -> Some s
            | _ -> None
          in
          let get_int fld obj =
            match get_field fld obj with
            | Some (`Int i) -> Some i
            | _ -> None
          in
          let resolve_db_path obj =
            match get_string "db_path" obj with
            | Some p ->
                (match configured_db_path with
                | Some conf_p when not (String.equal p conf_p) -> Error "db_path_mismatch"
                | _ -> Ok p)
            | None ->
                (match configured_db_path with
                | Some conf_p -> Ok conf_p
                | None -> Error "db_path_invalid")
          in
          match get_string "command" json with
          | None -> make_error_json "unknown_command"
          | Some "initialize_new" ->
              (match resolve_db_path json with
              | Error err -> make_error_json err
              | Ok db_path ->
                  let bot_id_opt =
                    match get_field "bot_id" json with
                    | Some (`String s) -> Some s
                    | Some (`Int i) -> Some (string_of_int i)
                    | Some (`Intlit s) -> Some s
                    | _ -> None
                  in
                  (match bot_id_opt with
                  | None -> make_error_json "invalid_bot_id"
                  | Some bot_id ->
                      (match initialize_new db_path bot_id with
                      | Ok gen -> Yojson.Safe.to_string (`Assoc [ ("ok", `Bool true); ("generation", `Int gen) ])
                      | Error err -> make_error_json err)))
          | Some "read_keys" ->
              (match resolve_db_path json with
              | Error err -> make_error_json err
              | Ok db_path ->
                  (match get_field "keys" json with
                  | Some (`List key_nodes) ->
                      let keys =
                        List.filter_map (function `String s -> Some s | _ -> None) key_nodes
                      in
                      if List.length keys <> List.length key_nodes then make_error_json "invalid_json"
                      else
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
                        | Error err -> make_error_json err)
                  | _ -> make_error_json "invalid_json"))
          | Some "read_inbox_index" ->
              (match resolve_db_path json with
              | Error err -> make_error_json err
              | Ok db_path ->
                  (match get_int "limit" json with
                  | None -> make_error_json "invalid_limit"
                  | Some limit ->
                      let after_key_res =
                        match get_field "after_key" json with
                        | None | Some `Null -> Ok None
                        | Some (`String ak) -> Ok (Some ak)
                        | _ -> Error "invalid_json"
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
                          | Error err -> make_error_json err)))
          | Some "lookup_operation" ->
              (match resolve_db_path json with
              | Error err -> make_error_json err
              | Ok db_path ->
                  (match get_string "operation_id" json with
                  | None -> make_error_json "invalid_operation_id"
                  | Some op_id ->
                      match lookup_operation db_path op_id with
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
                      | Error err -> make_error_json err))
          | Some "apply" ->
              (match resolve_db_path json with
              | Error err -> make_error_json err
              | Ok db_path ->
                  let bot_id_opt =
                    match get_field "bot_id" json with
                    | Some (`String s) -> Some s
                    | Some (`Int i) -> Some (string_of_int i)
                    | Some (`Intlit s) -> Some s
                    | _ -> None
                  in
                  let op_id_opt = get_string "operation_id" json in
                  let req_digest_opt = get_string "request_digest" json in
                  let exp_gen_opt = get_int "expected_generation" json in
                  match bot_id_opt, op_id_opt, req_digest_opt, exp_gen_opt with
                  | Some bot_id, Some op_id, Some req_digest, Some exp_gen ->
                      let parse_read_set () =
                        match get_field "read_set_assertions" json with
                        | Some (`List nodes) ->
                            let rec loop acc = function
                              | [] -> Ok (List.rev acc)
                              | node :: rest ->
                                  match get_string "key" node, get_int "expected_version" node, get_string "expected_sha256" node with
                                  | Some k, Some v, Some s -> loop ({ key = k; expected_version = v; expected_sha256 = s } :: acc) rest
                                  | Some k, Some 0, None -> loop ({ key = k; expected_version = 0; expected_sha256 = "" } :: acc) rest
                                  | _ -> Error "invalid_json"
                            in
                            loop [] nodes
                        | _ -> Error "invalid_json"
                      in
                      let parse_changes () =
                        match get_field "changes" json with
                        | Some (`List nodes) ->
                            let rec loop acc = function
                              | [] -> Ok (List.rev acc)
                              | node :: rest ->
                                  match get_string "key" node, get_int "expected_version" node, get_string "new_value_base64" node with
                                  | Some k, Some v, Some b64 ->
                                      let sha = match get_string "expected_sha256" node with Some s -> s | None -> "" in
                                      loop ({ key = k; expected_version = v; expected_sha256 = sha; new_value_base64 = b64 } :: acc) rest
                                  | _ -> Error "invalid_json"
                            in
                            loop [] nodes
                        | _ -> Error "invalid_json"
                      in
                      let parse_res_delta () =
                        match get_field "reservation_delta" json with
                        | Some (`Assoc _) as obj ->
                            let o = Option.get obj in
                            (match get_int "rows" o, get_int "receipts" o with
                            | Some rows, Some receipts -> Ok { rows; receipts }
                            | _ -> Error "invalid_json")
                        | _ -> Error "invalid_json"
                      in
                      let parse_summary () =
                        match get_field "summary_json" json with
                        | Some (`String s) -> Ok s
                        | Some (`Assoc _) as node -> Ok (Yojson.Safe.to_string (Option.get node))
                        | Some (`List _) as node -> Ok (Yojson.Safe.to_string (Option.get node))
                        | _ -> Error "invalid_json"
                      in
                      (match parse_read_set (), parse_changes (), parse_res_delta (), parse_summary () with
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
                      | _ -> make_error_json "invalid_json")
                  | _ -> make_error_json "invalid_json")
          | _ -> make_error_json "unknown_command"
