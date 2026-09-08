(* SC-PROVENANCE-001 — append-only cycle chain in SQLite.

   The file journal was corrupted in place three times on 2026-09-07. This store
   refuses in-place mutation at the database level: the triggers, not the writer,
   are the control. The writer below can only append, and only contiguously. *)

exception Invalid of string
let require c m = if not c then raise (Invalid m)

(* The cycle chain is shared runtime state, not repository content: var/ is
   gitignored, so it exists only in the canonical checkout and is NOT copied
   into sibling workspaces. Resolving this path relative to the current
   workspace would silently create a SECOND chain per workspace, each with its
   own sequence 1 and its own digests, which is precisely the divergence the
   append-only store exists to prevent.

   So the path is absolute and canonical by default, and overridable by
   UOS_KM_DB for tests, mirroring how tools/sa-plan resolves UOS_SA_PLAN_DB. *)
let default_db_path = "/home/an/NAS-setup/uos/var/km/provenance-cycles.sqlite3"

let db_path =
  match Sys.getenv_opt "UOS_KM_DB" with
  | Some p when String.trim p <> "" -> p
  | _ -> default_db_path

let schema = {sql|
CREATE TABLE IF NOT EXISTS cycle (
  sequence         INTEGER PRIMARY KEY,
  cycle_id         TEXT NOT NULL UNIQUE,
  plan_id          TEXT NOT NULL,
  task_id          TEXT NOT NULL,
  kind             TEXT NOT NULL,
  title            TEXT NOT NULL,
  body             TEXT NOT NULL,
  observed_utc     TEXT NOT NULL,
  evidence_json    TEXT NOT NULL,
  previous_digest  TEXT NOT NULL,
  digest           TEXT NOT NULL UNIQUE
);
CREATE TRIGGER IF NOT EXISTS cycle_no_update BEFORE UPDATE ON cycle
BEGIN SELECT RAISE(ABORT, 'cycle rows are append-only'); END;
CREATE TRIGGER IF NOT EXISTS cycle_no_delete BEFORE DELETE ON cycle
BEGIN SELECT RAISE(ABORT, 'cycle rows are append-only'); END;
CREATE TRIGGER IF NOT EXISTS cycle_chain BEFORE INSERT ON cycle
WHEN NOT (
  NEW.sequence = (SELECT COALESCE(MAX(sequence),0)+1 FROM cycle)
  AND NEW.previous_digest = COALESCE((SELECT digest FROM cycle WHERE sequence = NEW.sequence-1), '')
)
BEGIN SELECT RAISE(ABORT, 'cycle chain broken: sequence must be contiguous and previous_digest must match'); END;
|sql}

let ok rc = require (rc = Sqlite3.Rc.OK) "sqlite operation failed"

let sha256 s = Cryptokit.(transform_string (Hexa.encode ()) (hash_string (Hash.sha256 ()) s))

let open_db () =
  let db = Sqlite3.db_open ~mutex:`FULL db_path in
  Sqlite3.busy_timeout db 2000;
  ok (Sqlite3.exec db "PRAGMA journal_mode=WAL");
  ok (Sqlite3.exec db schema);
  db

let text s i = match Sqlite3.column s i with Sqlite3.Data.TEXT t -> t | _ -> ""
let num  s i = match Sqlite3.column s i with Sqlite3.Data.INT n -> Int64.to_int n | _ -> 0

let head db =
  let stmt = Sqlite3.prepare db "SELECT COALESCE(MAX(sequence),0) FROM cycle" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
    match Sqlite3.step stmt with Sqlite3.Rc.ROW -> num stmt 0 | _ -> 0)

let digest_at db seq =
  if seq <= 0 then ""
  else begin
    let stmt = Sqlite3.prepare db "SELECT digest FROM cycle WHERE sequence=?" in
    Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
      ok (Sqlite3.bind_int stmt 1 seq);
      match Sqlite3.step stmt with Sqlite3.Rc.ROW -> text stmt 0 | _ -> "")
  end

(* Canonical form is the concatenation used for the chain digest. Changing it
   invalidates every stored digest, which is the point: it is a schema pin. *)
let canonical ~seq ~cycle_id ~plan_id ~task_id ~kind ~title ~body ~observed ~evidence ~prev =
  String.concat "\x1f"
    [ "uos-km-cycle/v1"; string_of_int seq; cycle_id; plan_id; task_id; kind;
      title; body; observed; evidence; prev ]

let append db ~cycle_id ~plan_id ~task_id ~kind ~title ~body ~observed ~evidence =
  let seq = head db + 1 in
  let prev = digest_at db (seq - 1) in
  let digest = sha256 (canonical ~seq ~cycle_id ~plan_id ~task_id ~kind ~title ~body
                         ~observed ~evidence ~prev) in
  let stmt = Sqlite3.prepare db
    "INSERT INTO cycle (sequence,cycle_id,plan_id,task_id,kind,title,body,observed_utc,evidence_json,previous_digest,digest) \
     VALUES (?,?,?,?,?,?,?,?,?,?,?)" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
    ok (Sqlite3.bind_int  stmt 1 seq);
    List.iteri (fun i v -> ok (Sqlite3.bind_text stmt (i + 2) v))
      [ cycle_id; plan_id; task_id; kind; title; body; observed; evidence; prev; digest ];
    require (Sqlite3.step stmt = Sqlite3.Rc.DONE) "cycle insert refused by store";
    (seq, digest))

(* Recomputes every digest from stored fields. Detects any row whose content no
   longer matches its digest, and any break in the previous_digest chain. *)
let verify db =
  let stmt = Sqlite3.prepare db
    "SELECT sequence,cycle_id,plan_id,task_id,kind,title,body,observed_utc,evidence_json,previous_digest,digest \
     FROM cycle ORDER BY sequence" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
    let rec loop n expect_seq expect_prev bad =
      match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW ->
        let seq = num stmt 0 in
        let f i = text stmt i in
        let prev = f 9 and stored = f 10 in
        let recomputed = sha256 (canonical ~seq ~cycle_id:(f 1) ~plan_id:(f 2) ~task_id:(f 3)
                                   ~kind:(f 4) ~title:(f 5) ~body:(f 6) ~observed:(f 7)
                                   ~evidence:(f 8) ~prev) in
        let bad =
          if seq <> expect_seq then ("sequence gap at " ^ string_of_int seq) :: bad
          else if prev <> expect_prev then ("previous_digest mismatch at " ^ string_of_int seq) :: bad
          else if recomputed <> stored then ("content digest mismatch at " ^ string_of_int seq) :: bad
          else bad in
        loop (n + 1) (seq + 1) stored bad
      | Sqlite3.Rc.DONE -> (n, List.rev bad)
      | _ -> raise (Invalid "cycle scan failed") in
    loop 0 1 "" [])

let close db = ignore (Sqlite3.db_close db)
