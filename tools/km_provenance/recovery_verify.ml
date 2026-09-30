(* Read-only recovery oracle. Reuses the canonical digest function and schema;
   never initializes or alters a candidate, and does not mint admission. *)
let need = Km_chain.require
let query db sql =
  let stmt = Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
    let rec loop acc = match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW -> loop (Array.to_list (Sqlite3.row_data stmt) :: acc)
      | Sqlite3.Rc.DONE -> List.rev acc
      | _ -> failwith "oracle query failed" in loop [])
let verify path =
  let st = Unix.lstat path in
  need (st.Unix.st_kind = Unix.S_REG && st.Unix.st_size >= 512 && st.Unix.st_size <= 67108864)
    "existing bounded regular database required";
  let db = Sqlite3.db_open ~mode:`READONLY ~mutex:`FULL path in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () ->
    Sqlite3.busy_timeout db 2000;
    Km_chain.ok (Sqlite3.exec db "BEGIN");
    need (query db "PRAGMA integrity_check" = [[Sqlite3.Data.TEXT "ok"]]) "SQLite integrity";
    let reference = Sqlite3.db_open ":memory:" in
    let guards = Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close reference)) (fun () ->
      Km_chain.ok (Sqlite3.exec reference Km_chain.schema);
      query reference "SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name") in
    let actual = query db "SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name" in
    need (List.for_all (fun guard -> List.mem guard actual) guards) "required trigger definitions";
    let rows, defects = Km_chain.verify db in
    need (rows > 0 && defects = []) "verified nonempty cryptographic cycle chain required";
    let holds = match query db "SELECT count(*) FROM merge_hold" with
      | [[Sqlite3.Data.INT n]] -> Int64.to_int n | _ -> failwith "hold count unavailable" in
    let releases = match query db "SELECT count(*) FROM merge_hold_release" with
      | [[Sqlite3.Data.INT n]] -> Int64.to_int n | _ -> failwith "release count unavailable" in
    Km_chain.ok (Sqlite3.exec db "COMMIT");
    `Assoc ["ok",`Bool true; "rows",`Int rows; "holds",`Int holds; "releases",`Int releases])
let () =
  try
    need (Array.length Sys.argv = 2) "one database path required";
    print_endline (Yojson.Safe.to_string (verify Sys.argv.(1)))
  with exn ->
    print_endline (Yojson.Safe.to_string (`Assoc ["ok",`Bool false; "error",`String (Printexc.to_string exn)]));
    exit 1
