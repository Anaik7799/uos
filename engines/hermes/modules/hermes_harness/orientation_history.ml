(* Durable memory for the orientation pipeline: pass history and key state,
   in SQLite under state/ — the stratum HANDOVER names as the system of record
   alongside the repository.

   Mirrors Ops_completion_history's idiom (R14): one db handle, Rc-checked
   exec, prepared statements finalized under Fun.protect. Two tables:

     orientation_state    the CURRENT value per key — what an agent asks for
     orientation_history  append-only — every write, every pass, forever

   R3 governs the history: a replay of the same (pass_id, key) with an
   identical payload is a no-op; with a DIFFERENT payload it is REFUSED, and
   the conflict is the finding. State rows move only through a recorded
   history write, so the current value never lacks provenance.

   R4/R16: timestamps are PARAMETERS. This module never reads a clock — a
   store that invents its own time cannot be tested for what it records. *)

type t = { db : Sqlite3.db }

let fail db context rc =
  Error
    (Printf.sprintf "%s: %s: %s" context (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))

let exec db sql =
  match Sqlite3.exec db sql with
  | rc when Sqlite3.Rc.is_success rc -> Ok ()
  | rc -> fail db "exec" rc

let with_statement db sql f =
  let statement = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize statement))
    (fun () -> f statement)

let bind db statement values =
  match Sqlite3.bind_values statement values with
  | rc when Sqlite3.Rc.is_success rc -> Ok ()
  | rc -> fail db "bind" rc

let step_done db statement =
  match Sqlite3.step statement with
  | Sqlite3.Rc.DONE -> Ok ()
  | rc -> fail db "step" rc

let schema =
  "CREATE TABLE IF NOT EXISTS orientation_state (\n\
  \  key TEXT PRIMARY KEY,\n\
  \  value TEXT NOT NULL,\n\
  \  pass_id TEXT NOT NULL,\n\
  \  head TEXT NOT NULL,\n\
  \  recorded_at TEXT NOT NULL);\n\
   CREATE TABLE IF NOT EXISTS orientation_history (\n\
  \  pass_id TEXT NOT NULL,\n\
  \  key TEXT NOT NULL,\n\
  \  value TEXT NOT NULL,\n\
  \  head TEXT NOT NULL,\n\
  \  recorded_at TEXT NOT NULL,\n\
  \  PRIMARY KEY (pass_id, key));"

let open_store path =
  let rec ensure directory =
    if not (Sys.file_exists directory) then begin
      ensure (Filename.dirname directory);
      try Unix.mkdir directory 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
    end
  in
  ensure (Filename.dirname path);
  let db = Sqlite3.db_open path in
  match exec db schema with Ok () -> Ok { db } | Error _ as e -> e

let close store = ignore (Sqlite3.db_close store.db)

let existing_payload store ~pass_id ~key =
  with_statement store.db
    "SELECT value FROM orientation_history WHERE pass_id = ? AND key = ?"
    (fun statement ->
      match bind store.db statement [ Sqlite3.Data.TEXT pass_id; Sqlite3.Data.TEXT key ] with
      | Error _ as e -> e
      | Ok () -> (
          match Sqlite3.step statement with
          | Sqlite3.Rc.ROW -> Ok (Some (Sqlite3.Data.to_string_coerce (Sqlite3.column statement 0)))
          | Sqlite3.Rc.DONE -> Ok None
          | rc -> fail store.db "select" rc))

(* The single write path. History first — the record IS the provenance — then
   the state upsert. An identical replay is a no-op (idempotence, R3); a
   divergent replay is refused and the conflict is the finding. *)
let record store ~pass_id ~head ~recorded_at ~key ~value =
  match existing_payload store ~pass_id ~key with
  | Error _ as e -> e
  | Ok (Some previous) when previous = value -> Ok ()
  | Ok (Some previous) ->
      Error
        (Printf.sprintf
           "history conflict for (%s, %s): a different payload is already recorded \
            (%d bytes vs %d). Investigate why it changed; never delete rows to force \
            the write through (HZ-CTL-01)."
           pass_id key (String.length previous) (String.length value))
  | Ok None -> (
      let insert =
        with_statement store.db
          "INSERT INTO orientation_history (pass_id, key, value, head, recorded_at) \
           VALUES (?, ?, ?, ?, ?)"
          (fun statement ->
            match
              bind store.db statement
                [ Sqlite3.Data.TEXT pass_id; Sqlite3.Data.TEXT key; Sqlite3.Data.TEXT value;
                  Sqlite3.Data.TEXT head; Sqlite3.Data.TEXT recorded_at ]
            with
            | Error _ as e -> e
            | Ok () -> step_done store.db statement)
      in
      match insert with
      | Error _ as e -> e
      | Ok () ->
          with_statement store.db
            "INSERT INTO orientation_state (key, value, pass_id, head, recorded_at) \
             VALUES (?, ?, ?, ?, ?) ON CONFLICT(key) DO UPDATE SET \
             value = excluded.value, pass_id = excluded.pass_id, \
             head = excluded.head, recorded_at = excluded.recorded_at"
            (fun statement ->
              match
                bind store.db statement
                  [ Sqlite3.Data.TEXT key; Sqlite3.Data.TEXT value; Sqlite3.Data.TEXT pass_id;
                    Sqlite3.Data.TEXT head; Sqlite3.Data.TEXT recorded_at ]
              with
              | Error _ as e -> e
              | Ok () -> step_done store.db statement))

let record_pass store ~pass_id ~head ~recorded_at entries =
  let rec loop = function
    | [] -> Ok ()
    | (key, value) :: rest -> (
        match record store ~pass_id ~head ~recorded_at ~key ~value with
        | Error _ as e -> e
        | Ok () -> loop rest)
  in
  loop entries

let rows store sql binder =
  with_statement store.db sql (fun statement ->
      match binder statement with
      | Error _ as e -> e
      | Ok () ->
          let collected = ref [] in
          let rec walk () =
            match Sqlite3.step statement with
            | Sqlite3.Rc.ROW ->
                let cell i = Sqlite3.Data.to_string_coerce (Sqlite3.column statement i) in
                collected := (cell 0, cell 1, cell 2, cell 3) :: !collected;
                walk ()
            | Sqlite3.Rc.DONE -> Ok (List.rev !collected)
            | rc -> fail store.db "walk" rc
          in
          walk ())

(* (key, value, pass_id, recorded_at), key-ordered so output is deterministic. *)
let state store =
  rows store "SELECT key, value, pass_id, recorded_at FROM orientation_state ORDER BY key"
    (fun _ -> Ok ())

let history store ~pass_id =
  rows store
    "SELECT key, value, head, recorded_at FROM orientation_history WHERE pass_id = ? ORDER BY key"
    (fun statement -> bind store.db statement [ Sqlite3.Data.TEXT pass_id ])

let counts store =
  with_statement store.db
    "SELECT (SELECT COUNT(*) FROM orientation_state), \
     (SELECT COUNT(*) FROM orientation_history), \
     (SELECT COUNT(DISTINCT pass_id) FROM orientation_history)"
    (fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
          let cell i =
            match Sqlite3.column statement i with Sqlite3.Data.INT n -> Int64.to_int n | _ -> 0
          in
          Ok (cell 0, cell 1, cell 2)
      | rc -> fail store.db "counts" rc)

(* ---------------------------------------------------- calibration samples

   The loop's fifth phase (R30): the Act receipt re-enters as Observe. A
   sample is a PREDICTION paired with what actually turned out to be true.

   The realised label must come from OUTSIDE the classifier's own features.
   Deriving it from (path_changed, output_changed) — the same inputs the
   prediction used — would make agreement automatic and the score
   meaningless: the vacuity trap one level up from HZ-FIX-03, and the reason
   `calibrate` refuses an empty sample rather than scoring perfectly over
   nothing.

   So labelling is a deliberate act, and this table records it. *)

let sample_schema =
  "CREATE TABLE IF NOT EXISTS calibration_sample (\n\
  \  sample_id TEXT PRIMARY KEY,\n\
  \  path_changed INTEGER NOT NULL,\n\
  \  output_changed INTEGER NOT NULL,\n\
  \  predicted TEXT NOT NULL,\n\
  \  realised TEXT NOT NULL,\n\
  \  labelled_by TEXT NOT NULL,\n\
  \  recorded_at TEXT NOT NULL);"

let ensure_samples store = exec store.db sample_schema

let record_sample store ~sample_id ~path_changed ~output_changed ~predicted ~realised
    ~labelled_by ~recorded_at =
  match ensure_samples store with
  | Error _ as e -> e
  | Ok () ->
      (* Same R3 discipline as the history: an identical replay is a no-op, a
         divergent one is refused. A relabelled sample is a finding about the
         labeller, not a row to overwrite. *)
      with_statement store.db
        "INSERT INTO calibration_sample (sample_id, path_changed, output_changed, \
         predicted, realised, labelled_by, recorded_at) VALUES (?, ?, ?, ?, ?, ?, ?) \
         ON CONFLICT(sample_id) DO NOTHING"
        (fun statement ->
          match
            bind store.db statement
              [ Sqlite3.Data.TEXT sample_id;
                Sqlite3.Data.INT (if path_changed then 1L else 0L);
                Sqlite3.Data.INT (if output_changed then 1L else 0L);
                Sqlite3.Data.TEXT predicted; Sqlite3.Data.TEXT realised;
                Sqlite3.Data.TEXT labelled_by; Sqlite3.Data.TEXT recorded_at ]
          with
          | Error _ as e -> e
          | Ok () -> step_done store.db statement)

(* (path_changed, output_changed, realised) — the caller re-predicts so the
   scoring uses the CURRENT model rather than a stored verdict from an older
   one. A calibration that scored yesterday's predictions against yesterday's
   model could never detect the model drifting. *)
let samples store =
  match ensure_samples store with
  | Error _ as e -> e
  | Ok () ->
      with_statement store.db
        "SELECT path_changed, output_changed, realised FROM calibration_sample \
         ORDER BY sample_id"
        (fun statement ->
          let collected = ref [] in
          let rec walk () =
            match Sqlite3.step statement with
            | Sqlite3.Rc.ROW ->
                let int_at i =
                  match Sqlite3.column statement i with
                  | Sqlite3.Data.INT n -> Int64.to_int n
                  | _ -> 0
                in
                collected :=
                  (int_at 0 = 1, int_at 1 = 1,
                   Sqlite3.Data.to_string_coerce (Sqlite3.column statement 2))
                  :: !collected;
                walk ()
            | Sqlite3.Rc.DONE -> Ok (List.rev !collected)
            | rc -> fail store.db "samples" rc
          in
          walk ())
