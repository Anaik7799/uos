open Core

type t = {
  db : Sqlite3.db;
  mutable closed : bool;
  mutable transaction_active : bool;
  schema_version : int;
}

type bridge_domain = Sa_plan_control_plane.domain =
  | Otp_parity
  | Sa_plan
  | Infranodus
  | Documentation
  | Fdc

type bridge_mapping_request = {
  domain : bridge_domain;
  ooda_slice_id : string;
  idempotency_key : string;
  source_fingerprint : string;
  dependency_snapshot : string;
  prompt_ledger_hash : string;
  safety_packet_hash : string;
  formal_evidence_hash : string;
  sa_plan_id : string option;
  sa_task_id : string option;
  lifecycle_state : string;
  created_at_ns : int64;
}

type bridge_mapping = {
  id : string;
  domain : bridge_domain;
  ooda_slice_id : string;
  idempotency_key : string;
  source_fingerprint : string;
  dependency_snapshot : string;
  prompt_ledger_hash : string;
  safety_packet_hash : string;
  formal_evidence_hash : string;
  sa_plan_id : string option;
  sa_task_id : string option;
  lifecycle_state : string;
  version : int64;
}

type bridge_command_receipt = {
  mapping_id : string;
  command_id : string;
  request_hash : string;
  result : string;
  replayed : bool;
  recorded_at_ns : int64;
}

type bridge_event = {
  mapping_id : string;
  sequence : int64;
  version : int64;
  kind : string;
  payload : string;
  occurred_at_ns : int64;
}

type outbox_state = Outbox_pending | Outbox_delivered

type bridge_outbox = {
  id : string;
  mapping_id : string;
  command_id : string;
  event_sequence : int64;
  endpoint : string;
  state : outbox_state;
}

type bridge_ack = {
  consumer : string;
  outbox_id : string;
  replayed : bool;
  outbox : bridge_outbox;
}

type bridge_atomic_enqueue = {
  receipt : bridge_command_receipt;
  event : bridge_event;
  outbox : bridge_outbox;
}

type bridge_lease = {
  mapping_id : string;
  owner : string;
  lease_id : string;
  fencing_token : int64;
  expires_at_ns : int64;
  task_attempt : int option;
}

type summary = { total : int; completed : int; ready : int; executing : int }
type claim = { task_id : string; attempt : int; lease_until_ns : int64 }
type plan_view = { id : string; name : string; title : string }

type task_view = {
  plan_id : string;
  id : string;
  name : string;
  title : string;
  parent_id : string option;
  state : string;
  priority : int;
  worker : string option;
  attempt : int;
}

type job_state =
  | Job_available
  | Job_executing
  | Job_retry
  | Job_completed
  | Job_discarded
  | Job_cancelled

type job_view = {
  id : string;
  name : string;
  queue : string;
  worker : string;
  args : string;
  state : job_state;
  attempt : int;
  max_attempts : int;
  available_at_ns : int64;
  lease_owner : string option;
  lease_until_ns : int64 option;
  result : string option;
}

type workflow_event = {
  sequence : int;
  kind : string;
  payload : string;
  occurred_at_ns : int64;
}

type selection_factors = {
  stpa : int;
  fema : int;
  criticality : int;
  dependency : int;
  standards : int;
  agent_fit : int;
}

type selection_evidence = {
  actor : string;
  old_priority : int option;
  new_priority : int;
  factors : selection_factors;
  rationale : string;
  recorded_at_ns : int64;
}

type task_observation = {
  task : task_view;
  estimate_points : int option;
  lease_until_ns : int64 option;
  dependencies : string list;
  selection : selection_evidence option;
}

type workflow_view = {
  id : string;
  name : string;
  kind : string;
  input : string;
  state : string;
  result : string option;
  created_at_ns : int64;
  completed_at_ns : int64 option;
  events : workflow_event list;
}

type session_observation_row = {
  hermes_sequence : int64;
  source_journal_ref : string;
  host_boot_id : string;
  event_id : string;
  payload_hash : string;
  local_sequence : int64;
  session_ref : string;
  resource_ref : string;
  epoch : int64;
  candidate_ref : string;
}

type session_observation_write = {
  source_journal_ref : string;
  host_boot_id : string;
  event_id : string;
  declared_payload_hash : string;
  computed_payload_hash : string;
  local_sequence : int64;
  session_ref : string;
  resource_ref : string;
  epoch : int64;
  candidate_ref : string;
}

type session_reconciliation_kind =
  | Payload_hash_mismatch
  | Body_conflict
  | Sequence_conflict
  | Sequence_gap
  | Out_of_order

type session_reconciliation = {
  reconciliation_sequence : int64;
  kind : session_reconciliation_kind;
  source_journal_ref : string;
  host_boot_id : string;
  event_id : string;
  declared_payload_hash : string;
  computed_payload_hash : string;
  local_sequence : int64;
  expected_sequence : int64 option;
}

type session_observation_store_outcome =
  | Observation_stored of {
      observation : session_observation_row;
      replayed : bool;
    }
  | Observation_reconciliation of session_reconciliation

let rc_error context rc =
  Error (Printf.sprintf "%s: SQLite %s" context (Sqlite3.Rc.to_string rc))

let exec db context sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> Ok ()
  | rc -> rc_error context rc

let with_stmt db sql f =
  let stmt = Sqlite3.prepare db sql in
  Exn.protect
    ~f:(fun () -> f stmt)
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt : Sqlite3.Rc.t))

let bind stmt index value =
  match Sqlite3.bind stmt index value with
  | Sqlite3.Rc.OK -> Ok ()
  | rc -> rc_error (Printf.sprintf "bind parameter %d" index) rc

let bind_values_result context stmt values =
  match Sqlite3.bind_values stmt values with
  | Sqlite3.Rc.OK -> Ok ()
  | rc -> rc_error context rc

let step_done context stmt =
  match Sqlite3.step stmt with
  | Sqlite3.Rc.DONE -> Ok ()
  | rc -> rc_error context rc

let ensure_open store =
  if store.closed then Error "Sa-plan store is closed" else Ok ()

let schema =
  {|
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
CREATE TABLE IF NOT EXISTS sa_plan_plan (
  id TEXT PRIMARY KEY,
  name TEXT,
  title TEXT NOT NULL,
  graph_fingerprint TEXT NOT NULL,
  created_at_ns INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS sa_plan_task (
  plan_id TEXT NOT NULL,
  id TEXT NOT NULL,
  name TEXT,
  ordinal INTEGER NOT NULL,
  parent_id TEXT,
  task_type TEXT NOT NULL,
  title TEXT NOT NULL,
  estimate_points INTEGER,
  priority INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL CHECK (state IN ('available','executing','completed')),
  worker TEXT,
  lease_until_ns INTEGER,
  attempt INTEGER NOT NULL DEFAULT 0,
  result TEXT,
  completed_at_ns INTEGER,
  PRIMARY KEY (plan_id, id),
  FOREIGN KEY (plan_id) REFERENCES sa_plan_plan(id)
);
CREATE TABLE IF NOT EXISTS sa_plan_dependency (
  plan_id TEXT NOT NULL,
  task_id TEXT NOT NULL,
  dependency_id TEXT NOT NULL,
  PRIMARY KEY (plan_id, task_id, dependency_id),
  FOREIGN KEY (plan_id, task_id) REFERENCES sa_plan_task(plan_id, id),
  FOREIGN KEY (plan_id, dependency_id) REFERENCES sa_plan_task(plan_id, id)
);
CREATE TABLE IF NOT EXISTS sa_plan_activity (
  workflow_id TEXT NOT NULL,
  activity_id TEXT NOT NULL,
  result TEXT NOT NULL,
  completed_at_ns INTEGER NOT NULL,
  PRIMARY KEY (workflow_id, activity_id)
);
CREATE TABLE IF NOT EXISTS sa_plan_selection_evidence (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  plan_id TEXT NOT NULL,
  task_id TEXT NOT NULL,
  actor TEXT NOT NULL,
  old_priority INTEGER,
  new_priority INTEGER NOT NULL,
  stpa INTEGER NOT NULL,
  fema INTEGER NOT NULL,
  criticality INTEGER NOT NULL,
  dependency INTEGER NOT NULL,
  standards INTEGER NOT NULL,
  agent_fit INTEGER NOT NULL,
  rationale TEXT NOT NULL,
  recorded_at_ns INTEGER NOT NULL,
  FOREIGN KEY (plan_id, task_id) REFERENCES sa_plan_task(plan_id, id)
);
CREATE INDEX IF NOT EXISTS sa_plan_selection_latest
  ON sa_plan_selection_evidence(plan_id, task_id, sequence DESC);
CREATE INDEX IF NOT EXISTS sa_plan_task_state
  ON sa_plan_task(plan_id, state, ordinal);
CREATE INDEX IF NOT EXISTS sa_plan_dependency_task
  ON sa_plan_dependency(plan_id, task_id);
CREATE TABLE IF NOT EXISTS sa_plan_job (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  queue TEXT NOT NULL,
  worker TEXT NOT NULL,
  args TEXT NOT NULL,
  state TEXT NOT NULL CHECK
    (state IN ('available','executing','retry','completed','discarded','cancelled')),
  attempt INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL,
  available_at_ns INTEGER NOT NULL,
  lease_owner TEXT,
  lease_until_ns INTEGER,
  result TEXT,
  inserted_at_ns INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sa_plan_job_ready
  ON sa_plan_job(queue, state, available_at_ns, inserted_at_ns);
CREATE TABLE IF NOT EXISTS sa_plan_workflow (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL DEFAULT 'workflow',
  input TEXT NOT NULL DEFAULT '',
  state TEXT NOT NULL CHECK (state IN ('running','completed','failed')),
  result TEXT,
  created_at_ns INTEGER NOT NULL,
  completed_at_ns INTEGER
);
CREATE TABLE IF NOT EXISTS sa_plan_workflow_event (
  workflow_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  kind TEXT NOT NULL,
  payload TEXT NOT NULL,
  occurred_at_ns INTEGER NOT NULL,
  PRIMARY KEY (workflow_id, sequence),
  FOREIGN KEY (workflow_id) REFERENCES sa_plan_workflow(id)
);
CREATE TABLE IF NOT EXISTS sa_plan_workflow_activity (
  workflow_id TEXT NOT NULL,
  id TEXT NOT NULL,
  name TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  result TEXT NOT NULL,
  completed_at_ns INTEGER NOT NULL,
  PRIMARY KEY (workflow_id, id),
  UNIQUE (workflow_id, name),
  UNIQUE (workflow_id, idempotency_key),
  FOREIGN KEY (workflow_id) REFERENCES sa_plan_workflow(id)
);
CREATE TABLE IF NOT EXISTS sa_plan_schema_meta (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  version INTEGER NOT NULL
);
|}

let schema_v4 =
  {|
CREATE TABLE IF NOT EXISTS sa_plan_bridge_mapping (
  id TEXT PRIMARY KEY, domain TEXT NOT NULL, ooda_slice_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL UNIQUE, source_fingerprint TEXT NOT NULL,
  dependency_snapshot TEXT NOT NULL, prompt_ledger_hash TEXT NOT NULL,
  safety_packet_hash TEXT NOT NULL, formal_evidence_hash TEXT NOT NULL,
  sa_plan_id TEXT, sa_task_id TEXT, lifecycle_state TEXT NOT NULL DEFAULT 'observed',
  version INTEGER NOT NULL DEFAULT 0, created_at_ns INTEGER NOT NULL,
  UNIQUE(domain, ooda_slice_id),
  CHECK ((sa_plan_id IS NULL) = (sa_task_id IS NULL)),
  FOREIGN KEY(sa_plan_id, sa_task_id) REFERENCES sa_plan_task(plan_id, id)
);
CREATE TABLE IF NOT EXISTS sa_plan_bridge_command (
  mapping_id TEXT NOT NULL, command_id TEXT NOT NULL, request_hash TEXT NOT NULL,
  result TEXT NOT NULL, recorded_at_ns INTEGER NOT NULL,
  PRIMARY KEY(mapping_id, command_id),
  UNIQUE(command_id),
  FOREIGN KEY(mapping_id) REFERENCES sa_plan_bridge_mapping(id)
);
CREATE TABLE IF NOT EXISTS sa_plan_bridge_event (
  mapping_id TEXT NOT NULL, sequence INTEGER NOT NULL, version INTEGER NOT NULL,
  kind TEXT NOT NULL, payload TEXT NOT NULL, occurred_at_ns INTEGER NOT NULL,
  PRIMARY KEY(mapping_id, sequence),
  UNIQUE(mapping_id, version),
  FOREIGN KEY(mapping_id) REFERENCES sa_plan_bridge_mapping(id)
);
CREATE TABLE IF NOT EXISTS sa_plan_webhook_outbox (
  id TEXT PRIMARY KEY, mapping_id TEXT NOT NULL, command_id TEXT NOT NULL,
  event_sequence INTEGER NOT NULL, endpoint TEXT NOT NULL,
  state TEXT NOT NULL CHECK(state IN ('pending','delivered')),
  FOREIGN KEY(mapping_id) REFERENCES sa_plan_bridge_mapping(id),
  FOREIGN KEY(mapping_id, command_id) REFERENCES sa_plan_bridge_command(mapping_id, command_id),
  FOREIGN KEY(mapping_id, event_sequence) REFERENCES sa_plan_bridge_event(mapping_id, sequence),
  UNIQUE(mapping_id, command_id, event_sequence)
);
CREATE TABLE IF NOT EXISTS sa_plan_webhook_inbox (
  consumer TEXT NOT NULL, outbox_id TEXT NOT NULL, acknowledged_at_ns INTEGER NOT NULL,
  PRIMARY KEY(consumer, outbox_id),
  FOREIGN KEY(outbox_id) REFERENCES sa_plan_webhook_outbox(id)
);
CREATE TABLE IF NOT EXISTS sa_plan_preflight (
  mapping_id TEXT NOT NULL, packet_hash TEXT NOT NULL, decision TEXT NOT NULL,
  recorded_at_ns INTEGER NOT NULL, PRIMARY KEY(mapping_id, packet_hash),
  FOREIGN KEY(mapping_id) REFERENCES sa_plan_bridge_mapping(id)
);
CREATE TABLE IF NOT EXISTS sa_plan_reconciliation (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT, mapping_id TEXT NOT NULL,
  kind TEXT NOT NULL, outcome TEXT NOT NULL, recorded_at_ns INTEGER NOT NULL,
  FOREIGN KEY(mapping_id) REFERENCES sa_plan_bridge_mapping(id)
);
|}

let schema_v5 =
  {|
CREATE TABLE IF NOT EXISTS sa_plan_bridge_lease (
  mapping_id TEXT PRIMARY KEY,
  owner TEXT NOT NULL,
  lease_id TEXT NOT NULL,
  fencing_token INTEGER NOT NULL CHECK(fencing_token > 0),
  expires_at_ns INTEGER NOT NULL,
  FOREIGN KEY(mapping_id) REFERENCES sa_plan_bridge_mapping(id)
);
|}

let schema_v6 =
  {|
CREATE TABLE IF NOT EXISTS sa_plan_session_observation_inbox (
  hermes_sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  source_journal_ref TEXT NOT NULL,
  host_boot_id TEXT NOT NULL,
  event_id TEXT NOT NULL UNIQUE,
  payload_hash TEXT NOT NULL,
  local_sequence INTEGER NOT NULL CHECK(local_sequence > 0),
  session_ref TEXT NOT NULL,
  resource_ref TEXT NOT NULL,
  epoch INTEGER NOT NULL CHECK(epoch >= 0),
  candidate_ref TEXT NOT NULL,
  UNIQUE(source_journal_ref, local_sequence)
);
CREATE INDEX IF NOT EXISTS sa_plan_session_observation_journal_order
  ON sa_plan_session_observation_inbox(
    source_journal_ref, local_sequence
  );
CREATE TABLE IF NOT EXISTS sa_plan_session_observation_reconciliation (
  reconciliation_sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL CHECK(kind IN (
    'payload_hash_mismatch','body_conflict','sequence_conflict',
    'sequence_gap','out_of_order'
  )),
  source_journal_ref TEXT NOT NULL,
  host_boot_id TEXT NOT NULL,
  event_id TEXT NOT NULL,
  declared_payload_hash TEXT NOT NULL,
  computed_payload_hash TEXT NOT NULL,
  local_sequence INTEGER NOT NULL,
  expected_sequence INTEGER
);
CREATE INDEX IF NOT EXISTS sa_plan_session_reconciliation_journal_order
  ON sa_plan_session_observation_reconciliation(
    source_journal_ref, reconciliation_sequence
  );
|}

let column_exists db table column =
  with_stmt db
    ("PRAGMA table_info(" ^ table ^ ")")
    (fun stmt ->
      let rec loop () =
        match Sqlite3.step stmt with
        | Sqlite3.Rc.ROW ->
            if String.equal (Sqlite3.column_text stmt 1) column then Ok true
            else loop ()
        | Sqlite3.Rc.DONE -> Ok false
        | rc -> rc_error ("inspect " ^ table ^ " columns") rc
      in
      loop ())

let ensure_column db ~table ~column ~definition =
  Result.bind (column_exists db table column) ~f:(function
    | true -> Ok ()
    | false ->
        exec db
          ("add " ^ table ^ "." ^ column)
          ("ALTER TABLE " ^ table ^ " ADD COLUMN " ^ definition))

let legacy_segment value =
  "legacy-" ^ Stdlib.Digest.to_hex (Stdlib.Digest.string value)

let backfill_plan_names db =
  with_stmt db "SELECT id FROM sa_plan_plan WHERE name IS NULL OR name = ''"
    (fun stmt ->
      let rec rows acc =
        match Sqlite3.step stmt with
        | Sqlite3.Rc.ROW -> rows (Sqlite3.column_text stmt 0 :: acc)
        | Sqlite3.Rc.DONE -> Ok (List.rev acc)
        | rc -> rc_error "read unnamed Sa-plan plans" rc
      in
      Result.bind (rows []) ~f:(fun ids ->
          List.fold ids ~init:(Ok ()) ~f:(fun acc id ->
              Result.bind acc ~f:(fun () ->
                  with_stmt db "UPDATE sa_plan_plan SET name = ? WHERE id = ?"
                    (fun update ->
                      Result.bind
                        (bind_values_result "bind legacy plan name" update
                           [
                             Sqlite3.Data.TEXT
                               ("legacy/plans/" ^ legacy_segment id);
                             TEXT id;
                           ])
                        ~f:(fun () ->
                          step_done "backfill legacy plan name" update))))))

let backfill_task_names db =
  with_stmt db
    "SELECT plan_id, id FROM sa_plan_task WHERE name IS NULL OR name = ''"
    (fun stmt ->
      let rec rows acc =
        match Sqlite3.step stmt with
        | Sqlite3.Rc.ROW ->
            rows
              ((Sqlite3.column_text stmt 0, Sqlite3.column_text stmt 1) :: acc)
        | Sqlite3.Rc.DONE -> Ok (List.rev acc)
        | rc -> rc_error "read unnamed Sa-plan tasks" rc
      in
      Result.bind (rows []) ~f:(fun ids ->
          List.fold ids ~init:(Ok ()) ~f:(fun acc (plan_id, id) ->
              Result.bind acc ~f:(fun () ->
                  with_stmt db
                    "UPDATE sa_plan_task SET name = ? WHERE plan_id = ? AND id \
                     = ?" (fun update ->
                      let name =
                        "legacy/tasks/" ^ legacy_segment plan_id ^ "/"
                        ^ legacy_segment id
                      in
                      Result.bind
                        (bind_values_result "bind legacy task name" update
                           [ Sqlite3.Data.TEXT name; TEXT plan_id; TEXT id ])
                        ~f:(fun () ->
                          step_done "backfill legacy task name" update))))))

let migrate_schema db =
  let steps =
    [
      (fun () ->
        ensure_column db ~table:"sa_plan_plan" ~column:"name"
          ~definition:"name TEXT");
      (fun () ->
        ensure_column db ~table:"sa_plan_plan" ~column:"created_at_ns"
          ~definition:"created_at_ns INTEGER NOT NULL DEFAULT 0");
      (fun () ->
        ensure_column db ~table:"sa_plan_task" ~column:"name"
          ~definition:"name TEXT");
      (fun () ->
        ensure_column db ~table:"sa_plan_task" ~column:"priority"
          ~definition:"priority INTEGER NOT NULL DEFAULT 0");
      (fun () ->
        ensure_column db ~table:"sa_plan_workflow" ~column:"kind"
          ~definition:"kind TEXT NOT NULL DEFAULT 'workflow'");
      (fun () ->
        ensure_column db ~table:"sa_plan_workflow" ~column:"input"
          ~definition:"input TEXT NOT NULL DEFAULT ''");
      (fun () -> backfill_plan_names db);
      (fun () -> backfill_task_names db);
      (fun () ->
        exec db "index Sa-plan names"
          "CREATE UNIQUE INDEX IF NOT EXISTS sa_plan_plan_name ON \
           sa_plan_plan(name);CREATE UNIQUE INDEX IF NOT EXISTS \
           sa_plan_task_name ON sa_plan_task(plan_id, name);");
      (fun () ->
        exec db "record Sa-plan schema version"
          "INSERT INTO sa_plan_schema_meta(singleton, version) VALUES (1, 3) \
           ON CONFLICT(singleton) DO UPDATE SET version = excluded.version");
    ]
  in
  List.fold steps ~init:(Ok ()) ~f:(fun acc step ->
      Result.bind acc ~f:(fun () -> step ()))

let read_schema_version db =
  with_stmt db "SELECT version FROM sa_plan_schema_meta WHERE singleton=1"
    (fun stmt ->
      match Sqlite3.step stmt with
      | Sqlite3.Rc.DONE -> Ok 0
      | Sqlite3.Rc.ROW -> Ok (Int64.to_int_exn (Sqlite3.column_int64 stmt 0))
      | rc -> rc_error "read Sa-plan schema version" rc)

let raw_transaction db label f =
  match exec db ("begin " ^ label) "BEGIN IMMEDIATE" with
  | Error _ as error -> error
  | Ok () -> (
      match Or_error.try_with f with
      | Error error ->
          ignore (Sqlite3.exec db "ROLLBACK" : Sqlite3.Rc.t);
          Error (Error.to_string_hum error)
      | Ok (Error _ as error) ->
          ignore (Sqlite3.exec db "ROLLBACK" : Sqlite3.Rc.t);
          error
      | Ok (Ok value) -> (
          match exec db ("commit " ^ label) "COMMIT" with
          | Ok () -> Ok value
          | Error _ as error ->
              ignore (Sqlite3.exec db "ROLLBACK" : Sqlite3.Rc.t);
              error))

(** Migration law: each version transition is one raw transaction. *)
let migrate_v4 db =
  raw_transaction db "Sa-plan v4 migration" (fun () ->
      Result.bind (exec db "create Sa-plan v4 bridge schema" schema_v4)
        ~f:(fun () ->
          exec db "record Sa-plan schema version 4"
            "INSERT INTO sa_plan_schema_meta(singleton, version) VALUES (1, 4) \
             ON CONFLICT(singleton) DO UPDATE SET version = excluded.version"))

(* Audit law: a version-4 marker is trusted only when its admitted bridge shape is readable.
   Ephemeral pre-admission draft-v4 layouts are deliberately unsupported. *)
let audit_v4_shape db =
  let check sql =
    with_stmt db sql (fun stmt ->
        match Sqlite3.step stmt with
        | Sqlite3.Rc.ROW | Sqlite3.Rc.DONE -> Ok ()
        | rc -> rc_error "audit Sa-plan v4 bridge shape" rc)
  in
  List.fold
    [
      "SELECT id,sa_plan_id,sa_task_id,lifecycle_state,version FROM \
       sa_plan_bridge_mapping";
      "SELECT mapping_id,command_id,request_hash,result,recorded_at_ns FROM \
       sa_plan_bridge_command";
      "SELECT mapping_id,sequence,version FROM sa_plan_bridge_event";
      "SELECT id,mapping_id,command_id,event_sequence,endpoint,state FROM \
       sa_plan_webhook_outbox";
      "SELECT consumer,outbox_id,acknowledged_at_ns FROM sa_plan_webhook_inbox";
      "SELECT mapping_id,packet_hash,decision,recorded_at_ns FROM \
       sa_plan_preflight";
      "SELECT sequence,mapping_id,kind,outcome,recorded_at_ns FROM \
       sa_plan_reconciliation";
    ] ~init:(Ok ()) ~f:(fun result sql ->
      Result.bind result ~f:(fun () -> check sql))
  |> Result.bind ~f:(fun () ->
      with_stmt db "PRAGMA foreign_key_check" (fun stmt ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.DONE -> Ok ()
          | Sqlite3.Rc.ROW -> Error "Sa-plan v4 foreign key violation"
          | rc -> rc_error "audit Sa-plan v4 foreign keys" rc))

let migrate_v5 db =
  raw_transaction db "Sa-plan v5 fenced lease migration" (fun () ->
      Result.bind (exec db "create Sa-plan v5 fenced lease schema" schema_v5)
        ~f:(fun () ->
          exec db "record Sa-plan schema version 5"
            "INSERT INTO sa_plan_schema_meta(singleton, version) VALUES (1, 5) \
             ON CONFLICT(singleton) DO UPDATE SET version = excluded.version"))

let audit_v5_shape db =
  Result.bind (audit_v4_shape db) ~f:(fun () ->
      with_stmt db
        "SELECT mapping_id,owner,lease_id,fencing_token,expires_at_ns FROM sa_plan_bridge_lease"
        (fun stmt ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW | Sqlite3.Rc.DONE -> Ok ()
          | rc -> rc_error "audit Sa-plan v5 fenced lease shape" rc))

let migrate_v6 db =
  raw_transaction db "Sa-plan v6 session observation migration" (fun () ->
      Result.bind
        (exec db "create Sa-plan v6 session observation schema" schema_v6)
        ~f:(fun () ->
          exec db "record Sa-plan schema version 6"
            "INSERT INTO sa_plan_schema_meta(singleton, version) VALUES (1, 6) \
             ON CONFLICT(singleton) DO UPDATE SET version = excluded.version"))

let audit_v6_shape db =
  Result.bind (audit_v5_shape db) ~f:(fun () ->
      let queries =
        [ "SELECT hermes_sequence,source_journal_ref,host_boot_id,event_id,\
           payload_hash,local_sequence,session_ref,resource_ref,epoch,\
           candidate_ref FROM sa_plan_session_observation_inbox";
          "SELECT reconciliation_sequence,kind,source_journal_ref,host_boot_id,\
           event_id,declared_payload_hash,computed_payload_hash,local_sequence,\
           expected_sequence FROM sa_plan_session_observation_reconciliation" ]
      in
      List.fold queries ~init:(Ok ()) ~f:(fun result sql ->
          Result.bind result ~f:(fun () ->
              with_stmt db sql (fun stmt ->
                  match Sqlite3.step stmt with
                  | Sqlite3.Rc.ROW | Sqlite3.Rc.DONE -> Ok ()
                  | rc -> rc_error "audit Sa-plan v6 observation shape" rc))))

let migrate_v7 db =
  raw_transaction db "Sa-plan v7 task attempt binding" (fun () ->
      Result.bind
        (ensure_column db ~table:"sa_plan_bridge_lease" ~column:"task_attempt"
           ~definition:"task_attempt INTEGER CHECK(task_attempt IS NULL OR (typeof(task_attempt) = 'integer' AND task_attempt > 0))")
        ~f:(fun () ->
          (* NULL is deliberate: never infer authority for a pre-upgrade lease. *)
          exec db "record Sa-plan schema version 7"
            "UPDATE sa_plan_schema_meta SET version = 7 WHERE singleton = 1"))

let audit_v7_shape db =
  Result.bind (audit_v6_shape db) ~f:(fun () ->
      with_stmt db "SELECT task_attempt FROM sa_plan_bridge_lease" (fun stmt ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW | Sqlite3.Rc.DONE -> Ok ()
          | rc -> rc_error "audit Sa-plan v7 attempt binding" rc))

let open_db path =
  try
    let db = Sqlite3.db_open path in
    Sqlite3.busy_timeout db 5_000;
    match exec db "initialize Sa-plan schema" schema with
    | Ok () -> (
        match read_schema_version db with
        | Ok version when version > 7 ->
            ignore (Sqlite3.db_close db : bool);
            Error "unsupported future Sa-plan schema"
        | Ok version -> (
            let migrate_core =
              if version < 3 then
                raw_transaction db "Sa-plan v3 migration" (fun () ->
                    migrate_schema db)
              else Ok ()
            in
            match migrate_core with
            | Error _ as error ->
                ignore (Sqlite3.db_close db : bool);
                error
            | Ok () -> (
                let migrate_bridge =
                  if version < 4 then migrate_v4 db else Ok ()
                in
                match migrate_bridge with
                | Ok () -> (
                    let migrate_leases = if version < 5 then migrate_v5 db else Ok () in
                    match migrate_leases with
                    | Error _ as error ->
                        ignore (Sqlite3.db_close db : bool);
                        error
                    | Ok () ->
                        let migrate_observations =
                          if version < 6 then migrate_v6 db else Ok ()
                        in
                        (match migrate_observations with
                        | Error _ as error ->
                            ignore (Sqlite3.db_close db : bool);
                            error
                        | Ok () -> (match
                          Result.bind
                            (if version < 7 then migrate_v7 db else Ok ())
                            ~f:(fun () -> audit_v7_shape db)
                          with
                          | Ok () ->
                              Ok
                                {
                                  db;
                                  closed = false;
                                  transaction_active = false;
                                  schema_version = 7;
                                }
                          | Error _ as error ->
                              ignore (Sqlite3.db_close db : bool);
                              error)))
                | Error _ as error ->
                    ignore (Sqlite3.db_close db : bool);
                    error))
        | Error _ as error ->
            ignore (Sqlite3.db_close db : bool);
            error)
    | Error _ as error ->
        ignore (Sqlite3.db_close db : bool);
        error
  with exn -> Error (Exn.to_string exn)

let close store =
  if not store.closed then begin
    store.closed <- true;
    ignore (Sqlite3.db_close store.db : bool)
  end

let schema_version store = store.schema_version
let rollback db = ignore (Sqlite3.exec db "ROLLBACK" : Sqlite3.Rc.t)

let transaction store f =
  match ensure_open store with
  | Error _ as error -> error
  | Ok () when store.transaction_active -> f ()
  | Ok () -> (
      match exec store.db "begin immediate transaction" "BEGIN IMMEDIATE" with
      | Error _ as error -> error
      | Ok () -> (
          store.transaction_active <- true;
          let body = Or_error.try_with f in
          store.transaction_active <- false;
          match body with
          | Error error ->
              rollback store.db;
              Error (Error.to_string_hum error)
          | Ok (Error message) ->
              rollback store.db;
              Error message
          | Ok (Ok value) -> (
              match exec store.db "commit transaction" "COMMIT" with
              | Ok () -> Ok value
              | Error message ->
                  rollback store.db;
                  Error message)))

let with_transaction = transaction

let session_reconciliation_kind_text = function
  | Payload_hash_mismatch -> "payload_hash_mismatch"
  | Body_conflict -> "body_conflict"
  | Sequence_conflict -> "sequence_conflict"
  | Sequence_gap -> "sequence_gap"
  | Out_of_order -> "out_of_order"

let session_reconciliation_kind_of_text = function
  | "payload_hash_mismatch" -> Ok Payload_hash_mismatch
  | "body_conflict" -> Ok Body_conflict
  | "sequence_conflict" -> Ok Sequence_conflict
  | "sequence_gap" -> Ok Sequence_gap
  | "out_of_order" -> Ok Out_of_order
  | value -> Error ("unknown session reconciliation kind: " ^ value)

let optional_int64 stmt column =
  match Sqlite3.column stmt column with
  | Sqlite3.Data.INT value -> Some value
  | _ -> None

let session_observation_of_row stmt =
  { hermes_sequence = Sqlite3.column_int64 stmt 0;
    source_journal_ref = Sqlite3.column_text stmt 1;
    host_boot_id = Sqlite3.column_text stmt 2;
    event_id = Sqlite3.column_text stmt 3;
    payload_hash = Sqlite3.column_text stmt 4;
    local_sequence = Sqlite3.column_int64 stmt 5;
    session_ref = Sqlite3.column_text stmt 6;
    resource_ref = Sqlite3.column_text stmt 7;
    epoch = Sqlite3.column_int64 stmt 8;
    candidate_ref = Sqlite3.column_text stmt 9 }

let session_observation_select =
  "SELECT hermes_sequence,source_journal_ref,host_boot_id,event_id,\
   payload_hash,local_sequence,session_ref,resource_ref,epoch,candidate_ref \
   FROM sa_plan_session_observation_inbox"

let find_session_observation_by_event_db db event_id =
  with_stmt db (session_observation_select ^ " WHERE event_id = ?") (fun stmt ->
      Result.bind (bind stmt 1 (Sqlite3.Data.TEXT event_id)) ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW -> Ok (Some (session_observation_of_row stmt))
          | Sqlite3.Rc.DONE -> Ok None
          | rc -> rc_error "read session observation by event" rc))

let find_session_observation_by_local_sequence_db db ~source_journal_ref
    ~local_sequence =
  with_stmt db
    (session_observation_select
     ^ " WHERE source_journal_ref = ? AND local_sequence = ?")
    (fun stmt ->
      Result.bind
        (bind_values_result "bind session observation sequence" stmt
           [ Sqlite3.Data.TEXT source_journal_ref; INT local_sequence ])
        ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW -> Ok (Some (session_observation_of_row stmt))
          | Sqlite3.Rc.DONE -> Ok None
          | rc -> rc_error "read session observation by sequence" rc))

let next_local_sequence_db db source_journal_ref =
  with_stmt db
    "SELECT MAX(local_sequence) FROM sa_plan_session_observation_inbox \
     WHERE source_journal_ref = ?" (fun stmt ->
      Result.bind (bind stmt 1 (Sqlite3.Data.TEXT source_journal_ref))
        ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW ->
              (match Sqlite3.column stmt 0 with
              | Sqlite3.Data.NULL -> Ok 1L
              | Sqlite3.Data.INT value when Int64.(value < max_value) ->
                  Ok Int64.(value + 1L)
              | Sqlite3.Data.INT _ ->
                  Error "session journal local sequence exhausted"
              | _ -> Error "invalid session journal sequence aggregate")
          | rc -> rc_error "read next session observation sequence" rc))

let session_reconciliation_of_row stmt =
  Result.map
    (session_reconciliation_kind_of_text (Sqlite3.column_text stmt 1))
    ~f:(fun kind ->
      { reconciliation_sequence = Sqlite3.column_int64 stmt 0;
        kind;
        source_journal_ref = Sqlite3.column_text stmt 2;
        host_boot_id = Sqlite3.column_text stmt 3;
        event_id = Sqlite3.column_text stmt 4;
        declared_payload_hash = Sqlite3.column_text stmt 5;
        computed_payload_hash = Sqlite3.column_text stmt 6;
        local_sequence = Sqlite3.column_int64 stmt 7;
        expected_sequence = optional_int64 stmt 8 })

let record_session_reconciliation_db db (write : session_observation_write)
    ~kind ~expected_sequence =
  with_stmt db
    "INSERT INTO sa_plan_session_observation_reconciliation(\
       kind,source_journal_ref,host_boot_id,event_id,declared_payload_hash,\
       computed_payload_hash,local_sequence,expected_sequence\
     ) VALUES(?,?,?,?,?,?,?,?)" (fun stmt ->
      let expected =
        Option.value_map expected_sequence ~default:Sqlite3.Data.NULL
          ~f:(fun value -> Sqlite3.Data.INT value)
      in
      Result.bind
        (bind_values_result "bind session observation reconciliation" stmt
           [ TEXT (session_reconciliation_kind_text kind);
             TEXT write.source_journal_ref;
             TEXT write.host_boot_id;
             TEXT write.event_id;
             TEXT write.declared_payload_hash;
             TEXT write.computed_payload_hash;
             INT write.local_sequence;
             expected ])
        ~f:(fun () ->
          Result.bind
            (step_done "record session observation reconciliation" stmt)
            ~f:(fun () ->
              let sequence = Sqlite3.last_insert_rowid db in
              Ok
                (Observation_reconciliation
                   { reconciliation_sequence = sequence;
                     kind;
                     source_journal_ref = write.source_journal_ref;
                     host_boot_id = write.host_boot_id;
                     event_id = write.event_id;
                     declared_payload_hash = write.declared_payload_hash;
                     computed_payload_hash = write.computed_payload_hash;
                     local_sequence = write.local_sequence;
                     expected_sequence }))))

let existing_observation_matches (write : session_observation_write)
    (row : session_observation_row) =
  String.equal write.source_journal_ref row.source_journal_ref
  && String.equal write.host_boot_id row.host_boot_id
  && String.equal write.event_id row.event_id
  && String.equal write.computed_payload_hash row.payload_hash
  && Int64.equal write.local_sequence row.local_sequence
  && String.equal write.session_ref row.session_ref
  && String.equal write.resource_ref row.resource_ref
  && Int64.equal write.epoch row.epoch
  && String.equal write.candidate_ref row.candidate_ref

let insert_session_observation_db db (write : session_observation_write) =
  with_stmt db
    "INSERT INTO sa_plan_session_observation_inbox(\
       source_journal_ref,host_boot_id,event_id,payload_hash,local_sequence,\
       session_ref,resource_ref,epoch,candidate_ref\
     ) VALUES(?,?,?,?,?,?,?,?,?)" (fun stmt ->
      Result.bind
        (bind_values_result "bind session observation inbox" stmt
           [ TEXT write.source_journal_ref;
             TEXT write.host_boot_id;
             TEXT write.event_id;
             TEXT write.computed_payload_hash;
             INT write.local_sequence;
             TEXT write.session_ref;
             TEXT write.resource_ref;
             INT write.epoch;
             TEXT write.candidate_ref ])
        ~f:(fun () ->
          Result.bind (step_done "insert session observation inbox" stmt)
            ~f:(fun () ->
              Result.map
                (find_session_observation_by_event_db db write.event_id)
                ~f:(function
                  | Some observation ->
                      Observation_stored { observation; replayed = false }
                  | None ->
                      failwith "inserted session observation is unreadable"))))

let ingest_session_observation store (write : session_observation_write) =
  transaction store (fun () ->
      if not
           (String.equal write.declared_payload_hash write.computed_payload_hash)
      then
        record_session_reconciliation_db store.db write
          ~kind:Payload_hash_mismatch ~expected_sequence:None
      else
        Result.bind
          (find_session_observation_by_event_db store.db write.event_id)
          ~f:(function
            | Some observation when existing_observation_matches write observation ->
                Ok (Observation_stored { observation; replayed = true })
            | Some _ ->
                record_session_reconciliation_db store.db write
                  ~kind:Body_conflict ~expected_sequence:None
            | None ->
                Result.bind
                  (next_local_sequence_db store.db write.source_journal_ref)
                  ~f:(fun expected_sequence ->
                    if Int64.(write.local_sequence > expected_sequence) then
                      record_session_reconciliation_db store.db write
                        ~kind:Sequence_gap
                        ~expected_sequence:(Some expected_sequence)
                    else if Int64.(write.local_sequence < expected_sequence) then
                      Result.bind
                        (find_session_observation_by_local_sequence_db store.db
                           ~source_journal_ref:write.source_journal_ref
                           ~local_sequence:write.local_sequence)
                        ~f:(fun occupied ->
                          let kind =
                            if Option.is_some occupied then Out_of_order
                            else Sequence_conflict
                          in
                          record_session_reconciliation_db store.db write ~kind
                            ~expected_sequence:(Some expected_sequence))
                    else insert_session_observation_db store.db write)))

let list_session_reconciliations store ~source_journal_ref =
  Result.bind (ensure_open store) ~f:(fun () ->
      with_stmt store.db
        "SELECT reconciliation_sequence,kind,source_journal_ref,host_boot_id,\
         event_id,declared_payload_hash,computed_payload_hash,local_sequence,\
         expected_sequence FROM sa_plan_session_observation_reconciliation \
         WHERE source_journal_ref = ? ORDER BY reconciliation_sequence"
        (fun stmt ->
          Result.bind (bind stmt 1 (Sqlite3.Data.TEXT source_journal_ref))
            ~f:(fun () ->
              let rec rows acc =
                match Sqlite3.step stmt with
                | Sqlite3.Rc.ROW ->
                    Result.bind (session_reconciliation_of_row stmt)
                      ~f:(fun row -> rows (row :: acc))
                | Sqlite3.Rc.DONE -> Ok (List.rev acc)
                | rc -> rc_error "list session observation reconciliations" rc
              in
              rows [])))

let bridge_domain_text = function
  | Otp_parity -> "otp"
  | Sa_plan -> "sa-plan"
  | Infranodus -> "infranodus"
  | Documentation -> "documentation"
  | Fdc -> "fdc"

let bridge_id (request : bridge_mapping_request) =
  "bridge/" ^ bridge_domain_text request.domain ^ "/" ^ request.ooda_slice_id

let bridge_domain_of_text = function
  | "otp" -> Ok Otp_parity
  | "sa-plan" -> Ok Sa_plan
  | "infranodus" -> Ok Infranodus
  | "documentation" -> Ok Documentation
  | "fdc" -> Ok Fdc
  | value -> Error ("unknown bridge domain: " ^ value)

let bridge_mapping_of_row stmt =
  Result.map
    (bridge_domain_of_text (Sqlite3.column_text stmt 1))
    ~f:(fun domain ->
      {
        id = Sqlite3.column_text stmt 0;
        domain;
        ooda_slice_id = Sqlite3.column_text stmt 2;
        idempotency_key = Sqlite3.column_text stmt 3;
        source_fingerprint = Sqlite3.column_text stmt 4;
        dependency_snapshot = Sqlite3.column_text stmt 5;
        prompt_ledger_hash = Sqlite3.column_text stmt 6;
        safety_packet_hash = Sqlite3.column_text stmt 7;
        formal_evidence_hash = Sqlite3.column_text stmt 8;
        sa_plan_id =
          (match Sqlite3.column stmt 9 with
          | Sqlite3.Data.TEXT v -> Some v
          | _ -> None);
        sa_task_id =
          (match Sqlite3.column stmt 10 with
          | Sqlite3.Data.TEXT v -> Some v
          | _ -> None);
        lifecycle_state = Sqlite3.column_text stmt 11;
        version = Sqlite3.column_int64 stmt 12;
      })

let find_mapping_db db id =
  with_stmt db
    "SELECT \
     id,domain,ooda_slice_id,idempotency_key,source_fingerprint,dependency_snapshot,prompt_ledger_hash,safety_packet_hash,formal_evidence_hash,sa_plan_id,sa_task_id,lifecycle_state,version \
     FROM sa_plan_bridge_mapping WHERE id=?" (fun s ->
      Result.bind (bind s 1 (Sqlite3.Data.TEXT id)) ~f:(fun () ->
          match Sqlite3.step s with
          | Sqlite3.Rc.ROW ->
              Result.map (bridge_mapping_of_row s) ~f:Option.some
          | Sqlite3.Rc.DONE -> Ok None
          | rc -> rc_error "read bridge mapping" rc))

let find_bridge_mapping store ~id =
  Result.bind (ensure_open store) ~f:(fun () -> find_mapping_db store.db id)

(* Clock input is supplied by the supervised adapter; arithmetic never wraps. *)
let lease_deadline ~worker ~now_ns ~lease_ns =
  if String.is_empty (String.strip worker) then Error "lease worker must be non-empty"
  else if Int64.(now_ns < 0L) then Error "lease time must be non-negative"
  else if Int64.(lease_ns <= 0L) then Error "lease duration must be positive"
  else if Int64.(now_ns > max_value - lease_ns) then Error "lease deadline overflow"
  else Ok Int64.(now_ns + lease_ns)

let validate_completion ~worker ~expected_attempt ~now_ns =
  if String.is_empty (String.strip worker) then Error "completion worker must be non-empty"
  else if expected_attempt <= 0 then Error "completion requires a positive original claim attempt"
  else if Int64.(now_ns < 0L) then Error "completion time must be non-negative"
  else Ok ()

let bridge_lease_of_row stmt =
  {
    mapping_id = Sqlite3.column_text stmt 0;
    owner = Sqlite3.column_text stmt 1;
    lease_id = Sqlite3.column_text stmt 2;
    fencing_token = Sqlite3.column_int64 stmt 3;
    expires_at_ns = Sqlite3.column_int64 stmt 4;
    task_attempt =
      (match Sqlite3.column stmt 5 with
       | INT n when Int64.(n > 0L && n <= of_int Stdlib.max_int) ->
           Some (Int64.to_int_exn n)
       | _ -> None);
  }

let find_bridge_lease_db db ~mapping_id =
  with_stmt db
    "SELECT mapping_id,owner,lease_id,fencing_token,expires_at_ns,task_attempt \
     FROM sa_plan_bridge_lease WHERE mapping_id = ?" (fun stmt ->
      Result.bind (bind stmt 1 (Sqlite3.Data.TEXT mapping_id)) ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW -> Ok (Some (bridge_lease_of_row stmt))
          | Sqlite3.Rc.DONE -> Ok None
          | rc -> rc_error "read Sa-plan bridge lease" rc))

let find_bridge_lease store ~mapping_id =
  Result.bind (ensure_open store) ~f:(fun () ->
      find_bridge_lease_db store.db ~mapping_id)

let mapped_task mapping =
  match mapping.sa_plan_id, mapping.sa_task_id with
  | Some plan_id, Some task_id -> Ok (plan_id, task_id)
  | None, None -> Error "bridge lease requires a materialized Sa-plan task"
  | _ -> Error "bridge mapping has unpaired Sa-plan identity"

let task_claim_for_bridge db ~plan_id ~task_id ~owner ~expires_at_ns ~now_ns =
  let open Result.Let_syntax in
  let%bind () =
    with_stmt db
      {|UPDATE sa_plan_task SET state = 'executing', worker = ?,
          lease_until_ns = ?, attempt = attempt + 1
        WHERE plan_id = ? AND id = ? AND attempt >= 0 AND attempt < ?
          AND (state = 'available' OR (state = 'executing' AND lease_until_ns <= ?))
          AND NOT EXISTS (
            SELECT 1 FROM sa_plan_dependency AS edge
            JOIN sa_plan_task AS dependency
              ON dependency.plan_id = edge.plan_id AND dependency.id = edge.dependency_id
            WHERE edge.plan_id = sa_plan_task.plan_id AND edge.task_id = sa_plan_task.id
              AND dependency.state <> 'completed')
      |} (fun stmt ->
        let%bind () = bind_values_result "bind fenced bridge task claim" stmt
          [ TEXT owner; INT expires_at_ns; TEXT plan_id; TEXT task_id;
            INT (Int64.of_int Stdlib.max_int); INT now_ns ] in
        let%bind () = step_done "claim fenced bridge task" stmt in
        if Sqlite3.changes db = 1 then Ok ()
        else Error "bridge task is blocked, leased, terminal or attempt-exhausted")
  in
  with_stmt db "SELECT attempt FROM sa_plan_task WHERE plan_id=? AND id=?" (fun stmt ->
      let%bind () = bind_values_result "read bridge task attempt" stmt
        [ TEXT plan_id; TEXT task_id ] in
      match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int stmt 0)
      | rc -> rc_error "read bridge claimed attempt" rc)

let claim_bridge_lease store ~mapping_id ~owner ~lease_id ~now_ns ~lease_ns =
  let open Result.Let_syntax in
  let%bind expires_at_ns = lease_deadline ~worker:owner ~now_ns ~lease_ns in
  if String.is_empty (String.strip mapping_id) || String.is_empty (String.strip lease_id) then
    Error "bridge claim requires non-empty mapping and lease id"
  else
    transaction store (fun () ->
        let%bind mapping = find_mapping_db store.db mapping_id in
        let%bind mapping = match mapping with
          | Some mapping -> Ok mapping
          | None -> Error "bridge lease mapping does not exist" in
        let%bind plan_id, task_id = mapped_task mapping in
        let%bind prior = find_bridge_lease_db store.db ~mapping_id in
        let%bind fencing_token = match prior with
          | Some lease when Int64.(lease.expires_at_ns > now_ns) ->
              Error "bridge lease is still live"
          | Some lease when Int64.(lease.fencing_token <= 0L || lease.fencing_token = max_value) ->
              Error "bridge fencing token is invalid or exhausted"
          | Some lease -> Ok Int64.(lease.fencing_token + 1L)
          | None -> Ok 1L in
        let%bind attempt = task_claim_for_bridge store.db ~plan_id ~task_id
          ~owner ~expires_at_ns ~now_ns in
        (* BEGIN IMMEDIATE protects the lease read, task claim and binding write. *)
        let%bind () =
          with_stmt store.db
            {|INSERT INTO sa_plan_bridge_lease
                (mapping_id,owner,lease_id,fencing_token,expires_at_ns,task_attempt)
              VALUES(?,?,?,?,?,?)
              ON CONFLICT(mapping_id) DO UPDATE SET owner=excluded.owner,
                lease_id=excluded.lease_id, fencing_token=excluded.fencing_token,
                expires_at_ns=excluded.expires_at_ns, task_attempt=excluded.task_attempt|}
            (fun stmt ->
              let%bind () = bind_values_result "write bound bridge lease" stmt
                [ TEXT mapping_id; TEXT owner; TEXT lease_id; INT fencing_token;
                  INT expires_at_ns; INT (Int64.of_int attempt) ] in
              step_done "write bound bridge lease" stmt)
        in
        Ok { mapping_id; owner; lease_id; fencing_token; expires_at_ns;
             task_attempt = Some attempt })

let complete_bridge_task store ~mapping_id ~owner ~lease_id ~fencing_token
    ~result ~now_ns =
  let open Result.Let_syntax in
  if String.is_empty (String.strip owner) || String.is_empty (String.strip lease_id)
     || Int64.(fencing_token <= 0L || now_ns < 0L) then
    Error "bridge completion requires owner, lease id, positive fence and non-negative time"
  else
    transaction store (fun () ->
        let%bind mapping = find_mapping_db store.db mapping_id in
        let%bind mapping = match mapping with
          | Some mapping -> Ok mapping
          | None -> Error "bridge completion mapping does not exist" in
        let%bind plan_id, task_id = mapped_task mapping in
        let%bind lease = find_bridge_lease_db store.db ~mapping_id in
        let%bind lease = match lease with
          | None -> Error "bridge completion lease is missing"
          | Some lease when not (String.equal lease.owner owner
                 && String.equal lease.lease_id lease_id
                 && Int64.equal lease.fencing_token fencing_token) ->
              Error "bridge completion rejected by stale lease fence"
          | Some lease when Int64.(lease.expires_at_ns <= now_ns) ->
              Error "bridge completion rejected by expired lease"
          | Some lease -> Ok lease in
        let%bind attempt = match lease.task_attempt with
          | Some attempt when attempt > 0 -> Ok attempt
          | _ -> Error "bridge completion lacks an original task attempt binding" in
        with_stmt store.db
          {|UPDATE sa_plan_task SET state='completed',result=?,completed_at_ns=?,lease_until_ns=NULL
            WHERE plan_id=? AND id=? AND state='executing' AND worker=?
              AND attempt=? AND lease_until_ns > ?|}
          (fun stmt ->
            let%bind () = bind_values_result "complete bound bridge task" stmt
              [ TEXT result; INT now_ns; TEXT plan_id; TEXT task_id; TEXT owner;
                INT (Int64.of_int attempt); INT now_ns ] in
            let%bind () = step_done "complete bound bridge task" stmt in
            if Sqlite3.changes store.db = 1 then Ok ()
            else Error "bridge completion lost task attempt or lease authority"))

let ensure_bridge_mapping store request =
  let id = bridge_id request in
  if
    not
      (Bool.equal
         (Option.is_some request.sa_plan_id)
         (Option.is_some request.sa_task_id))
  then Error "sa_plan_id and sa_task_id must be paired"
  else
    transaction store (fun () ->
        Result.bind (find_mapping_db store.db id) ~f:(function
          | Some mapping
            when String.equal mapping.idempotency_key request.idempotency_key
                 && String.equal mapping.source_fingerprint
                      request.source_fingerprint
                 && String.equal mapping.dependency_snapshot
                      request.dependency_snapshot
                 && String.equal mapping.prompt_ledger_hash
                      request.prompt_ledger_hash
                 && String.equal mapping.safety_packet_hash
                      request.safety_packet_hash
                 && String.equal mapping.formal_evidence_hash
                      request.formal_evidence_hash
                 && Option.equal String.equal mapping.sa_plan_id
                      request.sa_plan_id
                 && Option.equal String.equal mapping.sa_task_id
                      request.sa_task_id
                 && String.equal mapping.lifecycle_state request.lifecycle_state
            ->
              Ok mapping
          | Some _ -> Error "conflicting OODA mapping reuse"
          | None ->
              with_stmt store.db
                "INSERT INTO \
                 sa_plan_bridge_mapping(id,domain,ooda_slice_id,idempotency_key,source_fingerprint,dependency_snapshot,prompt_ledger_hash,safety_packet_hash,formal_evidence_hash,sa_plan_id,sa_task_id,lifecycle_state,created_at_ns) \
                 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)" (fun s ->
                  Result.bind
                    (bind_values_result "insert bridge mapping" s
                       [
                         TEXT id;
                         TEXT (bridge_domain_text request.domain);
                         TEXT request.ooda_slice_id;
                         TEXT request.idempotency_key;
                         TEXT request.source_fingerprint;
                         TEXT request.dependency_snapshot;
                         TEXT request.prompt_ledger_hash;
                         TEXT request.safety_packet_hash;
                         TEXT request.formal_evidence_hash;
                         Option.value_map request.sa_plan_id
                           ~default:Sqlite3.Data.NULL ~f:(fun x -> TEXT x);
                         Option.value_map request.sa_task_id
                           ~default:Sqlite3.Data.NULL ~f:(fun x -> TEXT x);
                         TEXT request.lifecycle_state;
                         INT request.created_at_ns;
                       ])
                    ~f:(fun () ->
                      Result.map (step_done "insert bridge mapping" s)
                        ~f:(fun () ->
                          {
                            id;
                            domain = request.domain;
                            ooda_slice_id = request.ooda_slice_id;
                            idempotency_key = request.idempotency_key;
                            source_fingerprint = request.source_fingerprint;
                            dependency_snapshot = request.dependency_snapshot;
                            prompt_ledger_hash = request.prompt_ledger_hash;
                            safety_packet_hash = request.safety_packet_hash;
                            formal_evidence_hash = request.formal_evidence_hash;
                            sa_plan_id = request.sa_plan_id;
                            sa_task_id = request.sa_task_id;
                            lifecycle_state = request.lifecycle_state;
                            version = 0L;
                          })))))

let command_db db ~mapping_id ~command_id =
  with_stmt db
    "SELECT request_hash,result,recorded_at_ns FROM sa_plan_bridge_command \
     WHERE mapping_id=? AND command_id=?" (fun s ->
      Result.bind
        (bind_values_result "read bridge command" s
           [ TEXT mapping_id; TEXT command_id ])
        ~f:(fun () ->
          match Sqlite3.step s with
          | Sqlite3.Rc.ROW ->
              Ok
                (Some
                   {
                     mapping_id;
                     command_id;
                     request_hash = Sqlite3.column_text s 0;
                     result = Sqlite3.column_text s 1;
                     replayed = true;
                     recorded_at_ns = Sqlite3.column_int64 s 2;
                   })
          | Sqlite3.Rc.DONE -> Ok None
          | rc -> rc_error "read bridge command" rc))

let record_command_db db ~mapping_id ~command_id ~request_hash ~result
    ~recorded_at_ns =
  if String.equal command_id "" then Error "empty bridge command id"
  else
    Result.bind (command_db db ~mapping_id ~command_id) ~f:(function
      | Some receipt ->
          if String.equal receipt.request_hash request_hash then Ok receipt
          else Error "conflicting bridge command hash"
      | None ->
          with_stmt db
            "INSERT INTO \
             sa_plan_bridge_command(mapping_id,command_id,request_hash,result,recorded_at_ns) \
             VALUES(?,?,?,?,?)" (fun s ->
              Result.bind
                (bind_values_result "insert bridge command" s
                   [
                     TEXT mapping_id;
                     TEXT command_id;
                     TEXT request_hash;
                     TEXT result;
                     INT recorded_at_ns;
                   ])
                ~f:(fun () ->
                  Result.map (step_done "insert bridge command" s) ~f:(fun () ->
                      {
                        mapping_id;
                        command_id;
                        request_hash;
                        result;
                        replayed = false;
                        recorded_at_ns;
                      }))))

let record_bridge_command store ~mapping_id ~command_id ~request_hash ~result
    ~recorded_at_ns =
  transaction store (fun () ->
      record_command_db store.db ~mapping_id ~command_id ~request_hash ~result
        ~recorded_at_ns)

let find_bridge_command store ~mapping_id ~command_id =
  Result.bind (ensure_open store) ~f:(fun () ->
      command_db store.db ~mapping_id ~command_id)

let append_event_db db ~mapping_id ~kind ~payload ~occurred_at_ns =
  match find_mapping_db db mapping_id with
  | Error _ as error -> error
  | Ok None -> Error "unknown bridge mapping"
  | Ok (Some mapping) ->
      let version = Int64.succ mapping.version in
      with_stmt db
        "UPDATE sa_plan_bridge_mapping SET version=? WHERE id=? AND version=?"
        (fun update ->
          match
            bind_values_result "advance bridge version" update
              [ INT version; TEXT mapping_id; INT mapping.version ]
          with
          | Error _ as error -> error
          | Ok () -> (
              match step_done "advance bridge version" update with
              | Error _ as error -> error
              | Ok () when Sqlite3.changes db <> 1 ->
                  Error "lost bridge mapping compare-and-swap"
              | Ok () ->
                  with_stmt db
                    "INSERT INTO \
                     sa_plan_bridge_event(mapping_id,sequence,version,kind,payload,occurred_at_ns) \
                     VALUES(?,?,?,?,?,?)" (fun insert ->
                      match
                        bind_values_result "insert bridge event" insert
                          [
                            TEXT mapping_id;
                            INT version;
                            INT version;
                            TEXT kind;
                            TEXT payload;
                            INT occurred_at_ns;
                          ]
                      with
                      | Error _ as error -> error
                      | Ok () ->
                          Result.map (step_done "insert bridge event" insert)
                            ~f:(fun () ->
                              {
                                mapping_id;
                                sequence = version;
                                version;
                                kind;
                                payload;
                                occurred_at_ns;
                              }))))

let append_bridge_event store ~mapping_id ~kind ~payload ~occurred_at_ns =
  transaction store (fun () ->
      append_event_db store.db ~mapping_id ~kind ~payload ~occurred_at_ns)

let record_command_and_enqueue_outbox store ~mapping_id ~command_id
    ~request_hash ~result ~event_kind ~event_payload ~endpoint ~outbox_id
    ~recorded_at_ns =
  transaction store (fun () ->
      match
        record_command_db store.db ~mapping_id ~command_id ~request_hash ~result
          ~recorded_at_ns
      with
      | Error _ as error -> error
      | Ok receipt when receipt.replayed ->
          with_stmt store.db
            "SELECT id,event_sequence,endpoint,state FROM \
             sa_plan_webhook_outbox WHERE mapping_id=? AND command_id=?"
            (fun outbox_stmt ->
              Result.bind
                (bind_values_result "read replay outbox" outbox_stmt
                   [ TEXT mapping_id; TEXT command_id ])
                ~f:(fun () ->
                  match Sqlite3.step outbox_stmt with
                  | Sqlite3.Rc.DONE ->
                      Error "missing durable outbox for replayed command"
                  | Sqlite3.Rc.ROW ->
                      let outbox_id = Sqlite3.column_text outbox_stmt 0 in
                      let sequence = Sqlite3.column_int64 outbox_stmt 1 in
                      let endpoint = Sqlite3.column_text outbox_stmt 2 in
                      let state =
                        if
                          String.equal
                            (Sqlite3.column_text outbox_stmt 3)
                            "delivered"
                        then Outbox_delivered
                        else Outbox_pending
                      in
                      with_stmt store.db
                        "SELECT version,kind,payload,occurred_at_ns FROM \
                         sa_plan_bridge_event WHERE mapping_id=? AND \
                         sequence=?" (fun event_stmt ->
                          Result.bind
                            (bind_values_result "read replay event" event_stmt
                               [ TEXT mapping_id; INT sequence ])
                            ~f:(fun () ->
                              match Sqlite3.step event_stmt with
                              | Sqlite3.Rc.ROW ->
                                  Ok
                                    {
                                      receipt;
                                      event =
                                        {
                                          mapping_id;
                                          sequence;
                                          version =
                                            Sqlite3.column_int64 event_stmt 0;
                                          kind =
                                            Sqlite3.column_text event_stmt 1;
                                          payload =
                                            Sqlite3.column_text event_stmt 2;
                                          occurred_at_ns =
                                            Sqlite3.column_int64 event_stmt 3;
                                        };
                                      outbox =
                                        {
                                          id = outbox_id;
                                          mapping_id;
                                          command_id;
                                          event_sequence = sequence;
                                          endpoint;
                                          state;
                                        };
                                    }
                              | Sqlite3.Rc.DONE ->
                                  Error
                                    "missing durable event for replayed command"
                              | rc -> rc_error "read replay event" rc))
                  | rc -> rc_error "read replay outbox" rc))
      | Ok receipt -> (
          match
            append_event_db store.db ~mapping_id ~kind:event_kind
              ~payload:event_payload ~occurred_at_ns:recorded_at_ns
          with
          | Error _ as error -> error
          | Ok event ->
              with_stmt store.db
                "INSERT INTO \
                 sa_plan_webhook_outbox(id,mapping_id,command_id,event_sequence,endpoint,state) \
                 VALUES(?,?,?,?,?,'pending')" (fun stmt ->
                  match
                    bind_values_result "insert bridge outbox" stmt
                      [
                        TEXT outbox_id;
                        TEXT mapping_id;
                        TEXT command_id;
                        INT event.sequence;
                        TEXT endpoint;
                      ]
                  with
                  | Error _ as error -> error
                  | Ok () ->
                      Result.map (step_done "insert bridge outbox" stmt)
                        ~f:(fun () ->
                          {
                            receipt;
                            event;
                            outbox =
                              {
                                id = outbox_id;
                                mapping_id;
                                command_id;
                                event_sequence = event.sequence;
                                endpoint;
                                state = Outbox_pending;
                              };
                          }))))

let ack_bridge_outbox store ~consumer ~outbox_id ~acknowledged_at_ns =
  transaction store (fun () ->
      with_stmt store.db
        "SELECT mapping_id,command_id,event_sequence,endpoint,state FROM \
         sa_plan_webhook_outbox WHERE id=?" (fun outbox_stmt ->
          match bind outbox_stmt 1 (TEXT outbox_id) with
          | Error _ as error -> error
          | Ok () -> (
              match Sqlite3.step outbox_stmt with
              | Sqlite3.Rc.DONE -> Error "unknown bridge outbox"
              | Sqlite3.Rc.ROW ->
                  let state =
                    if
                      String.equal
                        (Sqlite3.column_text outbox_stmt 4)
                        "delivered"
                    then Outbox_delivered
                    else Outbox_pending
                  in
                  let outbox =
                    {
                      id = outbox_id;
                      mapping_id = Sqlite3.column_text outbox_stmt 0;
                      command_id = Sqlite3.column_text outbox_stmt 1;
                      event_sequence = Sqlite3.column_int64 outbox_stmt 2;
                      endpoint = Sqlite3.column_text outbox_stmt 3;
                      state;
                    }
                  in
                  with_stmt store.db
                    "SELECT 1 FROM sa_plan_webhook_inbox WHERE consumer=? AND \
                     outbox_id=?" (fun seen ->
                      match
                        bind_values_result "read bridge ack" seen
                          [ TEXT consumer; TEXT outbox_id ]
                      with
                      | Error _ as error -> error
                      | Ok () -> (
                          match Sqlite3.step seen with
                          | Sqlite3.Rc.ROW ->
                              Ok
                                { consumer; outbox_id; replayed = true; outbox }
                          | Sqlite3.Rc.DONE ->
                              with_stmt store.db
                                "INSERT INTO \
                                 sa_plan_webhook_inbox(consumer,outbox_id,acknowledged_at_ns) \
                                 VALUES(?,?,?)" (fun insert ->
                                  match
                                    bind_values_result "insert bridge ack"
                                      insert
                                      [
                                        TEXT consumer;
                                        TEXT outbox_id;
                                        INT acknowledged_at_ns;
                                      ]
                                  with
                                  | Error _ as error -> error
                                  | Ok () -> (
                                      match
                                        step_done "insert bridge ack" insert
                                      with
                                      | Error _ as error -> error
                                      | Ok () ->
                                          with_stmt store.db
                                            "UPDATE sa_plan_webhook_outbox SET \
                                             state='delivered' WHERE id=?"
                                            (fun update ->
                                              Result.bind
                                                (bind update 1 (TEXT outbox_id))
                                                ~f:(fun () ->
                                                  Result.bind
                                                    (step_done
                                                       "mark bridge outbox \
                                                        delivered"
                                                       update) ~f:(fun () ->
                                                      if
                                                        Sqlite3.changes store.db
                                                        <> 1
                                                      then
                                                        Error
                                                          "lost bridge outbox \
                                                           delivery update"
                                                      else
                                                        Ok
                                                          {
                                                            consumer;
                                                            outbox_id;
                                                            replayed = false;
                                                            outbox =
                                                              {
                                                                outbox with
                                                                state =
                                                                  Outbox_delivered;
                                                              };
                                                          })))))
                          | rc -> rc_error "read bridge ack" rc))
              | rc -> rc_error "read bridge outbox" rc)))

(* cp-27: the durable pending-outbox read. A row is pending FOR A CONSUMER
   iff no inbox ack row exists for (consumer, outbox_id); ordering is
   deterministic (mapping, event sequence, id). Read-only. *)
let list_pending_bridge_outbox store ~consumer =
  with_stmt store.db
    {|
SELECT o.id, o.mapping_id, o.command_id, o.event_sequence, o.endpoint, o.state
FROM sa_plan_webhook_outbox AS o
WHERE NOT EXISTS (
  SELECT 1 FROM sa_plan_webhook_inbox AS i
  WHERE i.outbox_id = o.id AND i.consumer = ?
)
ORDER BY o.mapping_id, o.event_sequence, o.id
|}
    (fun stmt ->
      Result.bind (bind stmt 1 (TEXT consumer)) ~f:(fun () ->
          let rec collect acc =
            match Sqlite3.step stmt with
            | Sqlite3.Rc.DONE -> Ok (List.rev acc)
            | Sqlite3.Rc.ROW ->
                let state =
                  if String.equal (Sqlite3.column_text stmt 5) "delivered"
                  then Outbox_delivered
                  else Outbox_pending
                in
                collect
                  ({
                     id = Sqlite3.column_text stmt 0;
                     mapping_id = Sqlite3.column_text stmt 1;
                     command_id = Sqlite3.column_text stmt 2;
                     event_sequence = Sqlite3.column_int64 stmt 3;
                     endpoint = Sqlite3.column_text stmt 4;
                     state;
                   }
                  :: acc)
            | rc -> rc_error "list pending bridge outbox" rc
          in
          collect []))

let record_bridge_preflight store ~mapping_id ~packet_hash ~decision
    ~recorded_at_ns =
  transaction store (fun () ->
      with_stmt store.db
        "INSERT OR IGNORE INTO \
         sa_plan_preflight(mapping_id,packet_hash,decision,recorded_at_ns) \
         VALUES(?,?,?,?)" (fun s ->
          Result.bind
            (bind_values_result "insert bridge preflight" s
               [
                 TEXT mapping_id;
                 TEXT packet_hash;
                 TEXT decision;
                 INT recorded_at_ns;
               ])
            ~f:(fun () -> step_done "insert bridge preflight" s)))

let record_bridge_reconciliation store ~mapping_id ~kind ~outcome
    ~recorded_at_ns =
  transaction store (fun () ->
      with_stmt store.db
        "INSERT INTO \
         sa_plan_reconciliation(mapping_id,kind,outcome,recorded_at_ns) \
         VALUES(?,?,?,?)" (fun s ->
          Result.bind
            (bind_values_result "insert bridge reconciliation" s
               [ TEXT mapping_id; TEXT kind; TEXT outcome; INT recorded_at_ns ])
            ~f:(fun () -> step_done "insert bridge reconciliation" s)))

let task_type_text = function
  | Sa_plan_management.Epic -> "epic"
  | Story -> "story"
  | Bug -> "bug"
  | Subtask -> "subtask"

let node_fingerprint node =
  let dependencies =
    List.sort node.Sa_plan_management.dependencies ~compare:String.compare
  in
  String.concat ~sep:"\031"
    [
      node.id;
      Option.value node.parent_id ~default:"";
      task_type_text node.task_type;
      node.title;
      Option.value_map node.estimate_points ~default:"" ~f:Int.to_string;
      String.concat ~sep:"\030" dependencies;
    ]

let graph_fingerprint nodes =
  nodes
  |> List.sort ~compare:(fun a b -> String.compare a.Sa_plan_management.id b.id)
  |> List.map ~f:node_fingerprint
  |> String.concat ~sep:"\029"

let validate_nodes nodes =
  let ids = List.map nodes ~f:(fun node -> node.Sa_plan_management.id) in
  let unique_ids = String.Set.of_list ids in
  if Set.length unique_ids <> List.length ids then
    Error "Duplicate task ID in Sa-plan graph"
  else
    match
      List.find_map nodes ~f:(fun node ->
          List.find node.dependencies ~f:(fun dependency ->
              not (Set.mem unique_ids dependency))
          |> Option.map ~f:(fun dependency -> (node.id, dependency)))
    with
    | Some (task, dependency) ->
        Error
          (Printf.sprintf "Unknown dependency %s required by %s" dependency task)
    | None ->
        let state =
          List.fold nodes ~init:Sa_plan_management.empty
            ~f:Sa_plan_management.add_node
        in
        Result.map (Sa_plan_management.execution_plan state) ~f:(fun _ -> ())

let query_existing_fingerprint db id =
  with_stmt db "SELECT graph_fingerprint FROM sa_plan_plan WHERE id = ?"
    (fun stmt ->
      match bind stmt 1 (Sqlite3.Data.TEXT id) with
      | Error _ as error -> error
      | Ok () -> (
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW -> Ok (Some (Sqlite3.column_text stmt 0))
          | Sqlite3.Rc.DONE -> Ok None
          | rc -> rc_error "read existing Sa-plan" rc))

let insert_plan db ~id ~title ~fingerprint =
  with_stmt db
    "INSERT INTO sa_plan_plan(id, name, title, graph_fingerprint, \
     created_at_ns) VALUES (?, ?, ?, ?, 0)" (fun stmt ->
      match bind stmt 1 (Sqlite3.Data.TEXT id) with
      | Error _ as error -> error
      | Ok () -> (
          match
            bind stmt 2
              (Sqlite3.Data.TEXT ("legacy/plans/" ^ legacy_segment id))
          with
          | Error _ as error -> error
          | Ok () -> (
              match bind stmt 3 (Sqlite3.Data.TEXT title) with
              | Error _ as error -> error
              | Ok () -> (
                  match bind stmt 4 (Sqlite3.Data.TEXT fingerprint) with
                  | Error _ as error -> error
                  | Ok () -> step_done "insert Sa-plan" stmt))))

let insert_task db ~plan_id ~ordinal node =
  with_stmt db
    {|
INSERT INTO sa_plan_task
  (plan_id, id, name, ordinal, parent_id, task_type, title, estimate_points,
   priority, state)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 'available')
|}
    (fun stmt ->
      let values =
        [
          Sqlite3.Data.TEXT plan_id;
          TEXT node.Sa_plan_management.id;
          TEXT
            ("legacy/tasks/" ^ legacy_segment plan_id ^ "/"
           ^ legacy_segment node.id);
          INT (Int64.of_int ordinal);
          Option.value_map node.parent_id ~default:Sqlite3.Data.NULL
            ~f:(fun value -> Sqlite3.Data.TEXT value);
          TEXT (task_type_text node.task_type);
          TEXT node.title;
          Option.value_map node.estimate_points ~default:Sqlite3.Data.NULL
            ~f:(fun value -> Sqlite3.Data.INT (Int64.of_int value));
        ]
      in
      match Sqlite3.bind_values stmt values with
      | Sqlite3.Rc.OK -> step_done "insert Sa-plan task" stmt
      | rc -> rc_error "bind Sa-plan task" rc)

let insert_dependency db ~plan_id ~task_id dependency_id =
  with_stmt db
    "INSERT INTO sa_plan_dependency(plan_id, task_id, dependency_id) VALUES \
     (?, ?, ?)" (fun stmt ->
      match
        Sqlite3.bind_values stmt
          [ Sqlite3.Data.TEXT plan_id; TEXT task_id; TEXT dependency_id ]
      with
      | Sqlite3.Rc.OK -> step_done "insert Sa-plan dependency" stmt
      | rc -> rc_error "bind Sa-plan dependency" rc)

let register_plan store ~id ~title ~nodes =
  match validate_nodes nodes with
  | Error _ as error -> error
  | Ok () ->
      let fingerprint = graph_fingerprint nodes in
      transaction store (fun () ->
          match query_existing_fingerprint store.db id with
          | Error _ as error -> error
          | Ok (Some existing) when String.equal existing fingerprint -> Ok ()
          | Ok (Some _) -> Error (Printf.sprintf "Sa-plan %s graph drift" id)
          | Ok None -> (
              match insert_plan store.db ~id ~title ~fingerprint with
              | Error _ as error -> error
              | Ok () ->
                  let ordered =
                    List.sort nodes ~compare:(fun a b ->
                        String.compare a.Sa_plan_management.id b.id)
                  in
                  let tasks_result =
                    List.foldi ordered ~init:(Ok ()) ~f:(fun ordinal acc node ->
                        Result.bind acc ~f:(fun () ->
                            insert_task store.db ~plan_id:id ~ordinal node))
                  in
                  let dependencies_result =
                    List.fold ordered ~init:(Ok ()) ~f:(fun acc node ->
                        List.fold node.dependencies ~init:acc
                          ~f:(fun inner dependency ->
                            Result.bind inner ~f:(fun () ->
                                insert_dependency store.db ~plan_id:id
                                  ~task_id:node.id dependency)))
                  in
                  Result.bind tasks_result ~f:(fun () -> dependencies_result)))

let validate_name value =
  Result.map (Sa_plan_name.parse value) ~f:Sa_plan_name.to_string

let create_plan store ~id ~name ~title ~now_ns =
  if String.is_empty id then Error "Sa-plan plan ID must be non-empty"
  else if String.is_empty title then
    Error "Sa-plan plan title must be non-empty"
  else
    Result.bind (validate_name name) ~f:(fun name ->
        transaction store (fun () ->
            with_stmt store.db
              {|
INSERT INTO sa_plan_plan(id, name, title, graph_fingerprint, created_at_ns)
VALUES (?, ?, ?, 'dynamic-v1', ?)
|}
              (fun stmt ->
                Result.bind
                  (bind_values_result "bind Sa-plan plan creation" stmt
                     [ Sqlite3.Data.TEXT id; TEXT name; TEXT title; INT now_ns ])
                  ~f:(fun () -> step_done "create Sa-plan plan" stmt))))

let find_plan store ~id_or_name =
  match ensure_open store with
  | Error _ as error -> error
  | Ok () ->
      with_stmt store.db
        "SELECT id, name, title FROM sa_plan_plan WHERE id = ? OR name = ? \
         LIMIT 1" (fun stmt ->
          Result.bind
            (bind_values_result "bind Sa-plan plan lookup" stmt
               [ Sqlite3.Data.TEXT id_or_name; TEXT id_or_name ])
            ~f:(fun () ->
              match Sqlite3.step stmt with
              | Sqlite3.Rc.DONE -> Ok None
              | Sqlite3.Rc.ROW ->
                  Ok
                    (Some
                       {
                         id = Sqlite3.column_text stmt 0;
                         name = Sqlite3.column_text stmt 1;
                         title = Sqlite3.column_text stmt 2;
                       })
              | rc -> rc_error "read Sa-plan plan" rc))

let rename_plan store ~id_or_name ~new_name ~now_ns:_ =
  Result.bind (validate_name new_name) ~f:(fun new_name ->
      transaction store (fun () ->
          with_stmt store.db
            "UPDATE sa_plan_plan SET name = ? WHERE id = ? OR name = ?"
            (fun stmt ->
              Result.bind
                (bind_values_result "bind Sa-plan plan rename" stmt
                   [
                     Sqlite3.Data.TEXT new_name;
                     TEXT id_or_name;
                     TEXT id_or_name;
                   ])
                ~f:(fun () ->
                  Result.bind (step_done "rename Sa-plan plan" stmt)
                    ~f:(fun () ->
                      if Sqlite3.changes store.db = 1 then Ok ()
                      else Error ("Unknown Sa-plan plan: " ^ id_or_name))))))

let entity_exists db sql values =
  with_stmt db sql (fun stmt ->
      Result.bind (bind_values_result "bind existence query" stmt values)
        ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW -> Ok true
          | Sqlite3.Rc.DONE -> Ok false
          | rc -> rc_error "read existence query" rc))

let next_task_ordinal db plan_id =
  with_stmt db
    "SELECT COALESCE(MAX(ordinal), -1) + 1 FROM sa_plan_task WHERE plan_id = ?"
    (fun stmt ->
      Result.bind (bind stmt 1 (Sqlite3.Data.TEXT plan_id)) ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int stmt 0)
          | rc -> rc_error "read next Sa-plan task ordinal" rc))

let create_task store ~plan_id ~id ~name ~title ~parent_id ~dependencies
    ~priority ~now_ns:_ =
  if String.is_empty id then Error "Sa-plan task ID must be non-empty"
  else if String.is_empty title then
    Error "Sa-plan task title must be non-empty"
  else if priority < 0 then Error "Sa-plan task priority must be non-negative"
  else
    Result.bind (validate_name name) ~f:(fun name ->
        transaction store (fun () ->
            let require_task referenced_id =
              Result.bind
                (entity_exists store.db
                   "SELECT 1 FROM sa_plan_task WHERE plan_id = ? AND id = ?"
                   [ Sqlite3.Data.TEXT plan_id; TEXT referenced_id ])
                ~f:(function
                  | true -> Ok ()
                  | false ->
                      Error ("Unknown Sa-plan task dependency: " ^ referenced_id))
            in
            let require_references () =
              Option.to_list parent_id @ dependencies
              |> List.dedup_and_sort ~compare:String.compare
              |> List.fold ~init:(Ok ()) ~f:(fun acc referenced_id ->
                  Result.bind acc ~f:(fun () -> require_task referenced_id))
            in
            let insert_task_row ordinal =
              with_stmt store.db
                {|
INSERT INTO sa_plan_task
  (plan_id, id, name, ordinal, parent_id, task_type, title,
   estimate_points, priority, state)
VALUES (?, ?, ?, ?, ?, 'story', ?, NULL, ?, 'available')
|}
                (fun stmt ->
                  let values =
                    [
                      Sqlite3.Data.TEXT plan_id;
                      TEXT id;
                      TEXT name;
                      INT (Int64.of_int ordinal);
                      Option.value_map parent_id ~default:Sqlite3.Data.NULL
                        ~f:(fun value -> Sqlite3.Data.TEXT value);
                      TEXT title;
                      INT (Int64.of_int priority);
                    ]
                  in
                  Result.bind
                    (bind_values_result "bind Sa-plan task creation" stmt values)
                    ~f:(fun () -> step_done "create Sa-plan task" stmt))
            in
            let insert_dependencies () =
              List.fold dependencies ~init:(Ok ()) ~f:(fun acc dependency_id ->
                  Result.bind acc ~f:(fun () ->
                      insert_dependency store.db ~plan_id ~task_id:id
                        dependency_id))
            in
            Result.bind
              (entity_exists store.db "SELECT 1 FROM sa_plan_plan WHERE id = ?"
                 [ Sqlite3.Data.TEXT plan_id ]) ~f:(function
              | false -> Error ("Unknown Sa-plan plan: " ^ plan_id)
              | true ->
                  Result.bind (require_references ()) ~f:(fun () ->
                      Result.bind (next_task_ordinal store.db plan_id)
                        ~f:(fun ordinal ->
                          Result.bind (insert_task_row ordinal)
                            ~f:insert_dependencies)))))

let task_view_of_stmt stmt =
  let optional_text column =
    match Sqlite3.column stmt column with
    | Sqlite3.Data.NULL -> None
    | _ -> Some (Sqlite3.column_text stmt column)
  in
  {
    plan_id = Sqlite3.column_text stmt 0;
    id = Sqlite3.column_text stmt 1;
    name = Sqlite3.column_text stmt 2;
    title = Sqlite3.column_text stmt 3;
    parent_id = optional_text 4;
    state = Sqlite3.column_text stmt 5;
    priority = Sqlite3.column_int stmt 6;
    worker = optional_text 7;
    attempt = Sqlite3.column_int stmt 8;
  }

let task_view_columns =
  "plan_id, id, name, title, parent_id, state, priority, worker, attempt"

let find_task store ~plan_id ~id_or_name =
  match ensure_open store with
  | Error _ as error -> error
  | Ok () ->
      with_stmt store.db
        ("SELECT " ^ task_view_columns
       ^ " FROM sa_plan_task WHERE plan_id = ? AND (id = ? OR name = ?) LIMIT 1"
        )
        (fun stmt ->
          Result.bind
            (bind_values_result "bind Sa-plan task lookup" stmt
               [ Sqlite3.Data.TEXT plan_id; TEXT id_or_name; TEXT id_or_name ])
            ~f:(fun () ->
              match Sqlite3.step stmt with
              | Sqlite3.Rc.DONE -> Ok None
              | Sqlite3.Rc.ROW -> Ok (Some (task_view_of_stmt stmt))
              | rc -> rc_error "read Sa-plan task" rc))

let list_tasks store ~plan_id =
  match ensure_open store with
  | Error _ as error -> error
  | Ok () ->
      with_stmt store.db
        ("SELECT " ^ task_view_columns
       ^ " FROM sa_plan_task WHERE plan_id = ? ORDER BY ordinal, id")
        (fun stmt ->
          Result.bind (bind stmt 1 (Sqlite3.Data.TEXT plan_id)) ~f:(fun () ->
              let rec loop acc =
                match Sqlite3.step stmt with
                | Sqlite3.Rc.ROW -> loop (task_view_of_stmt stmt :: acc)
                | Sqlite3.Rc.DONE -> Ok (List.rev acc)
                | rc -> rc_error "list Sa-plan tasks" rc
              in
              loop []))

let rename_task store ~plan_id ~id_or_name ~new_name ~now_ns:_ =
  Result.bind (validate_name new_name) ~f:(fun new_name ->
      transaction store (fun () ->
          with_stmt store.db
            {|
UPDATE sa_plan_task SET name = ?
WHERE plan_id = ? AND (id = ? OR name = ?)
|}
            (fun stmt ->
              Result.bind
                (bind_values_result "bind Sa-plan task rename" stmt
                   [
                     Sqlite3.Data.TEXT new_name;
                     TEXT plan_id;
                     TEXT id_or_name;
                     TEXT id_or_name;
                   ])
                ~f:(fun () ->
                  Result.bind (step_done "rename Sa-plan task" stmt)
                    ~f:(fun () ->
                      if Sqlite3.changes store.db = 1 then Ok ()
                      else Error ("Unknown Sa-plan task: " ^ id_or_name))))))

let scalar_count db sql plan_id =
  with_stmt db sql (fun stmt ->
      match bind stmt 1 (Sqlite3.Data.TEXT plan_id) with
      | Error _ as error -> error
      | Ok () -> (
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW -> Ok (Sqlite3.column_int stmt 0)
          | rc -> rc_error "read Sa-plan summary" rc))

let summary store ~plan_id =
  match ensure_open store with
  | Error _ as error -> error
  | Ok () ->
      let count where =
        scalar_count store.db
          ("SELECT COUNT(*) FROM sa_plan_task WHERE plan_id = ? " ^ where)
          plan_id
      in
      Result.bind (count "") ~f:(fun total ->
          Result.bind (count "AND state = 'completed'") ~f:(fun completed ->
              Result.bind (count "AND state = 'executing'") ~f:(fun executing ->
                  let ready_sql =
                    {|
SELECT COUNT(*) FROM sa_plan_task AS task
WHERE task.plan_id = ? AND task.state = 'available'
AND NOT EXISTS (
  SELECT 1 FROM sa_plan_dependency AS edge
  JOIN sa_plan_task AS dependency
    ON dependency.plan_id = edge.plan_id
   AND dependency.id = edge.dependency_id
  WHERE edge.plan_id = task.plan_id AND edge.task_id = task.id
    AND dependency.state <> 'completed'
)
|}
                  in
                  Result.map (scalar_count store.db ready_sql plan_id)
                    ~f:(fun ready -> { total; completed; ready; executing }))))

let select_claimable db ~plan_id ~now_ns =
  let sql =
    {|
SELECT task.id, task.attempt
FROM sa_plan_task AS task
WHERE task.plan_id = ?
  AND (task.state = 'available'
       OR (task.state = 'executing' AND task.lease_until_ns <= ?))
  AND NOT EXISTS (
    SELECT 1 FROM sa_plan_dependency AS edge
    JOIN sa_plan_task AS dependency
      ON dependency.plan_id = edge.plan_id
     AND dependency.id = edge.dependency_id
    WHERE edge.plan_id = task.plan_id AND edge.task_id = task.id
      AND dependency.state <> 'completed'
  )
ORDER BY task.ordinal, task.id
LIMIT 1
|}
  in
  with_stmt db sql (fun stmt ->
      Result.bind
        (bind_values_result "bind claim query" stmt
           [ Sqlite3.Data.TEXT plan_id; INT now_ns ])
        ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW ->
              Ok (Some (Sqlite3.column_text stmt 0, Sqlite3.column_int stmt 1))
          | Sqlite3.Rc.DONE -> Ok None
          | rc -> rc_error "select claimable Sa-plan task" rc))

let claim_update store ~plan_id ~task_id ~worker ~now_ns ~lease_until_ns
    ~previous_attempt =
  if previous_attempt < 0 || previous_attempt = Stdlib.max_int then
    Error "Sa-plan task attempt is invalid or exhausted"
  else with_stmt store.db
    {|
UPDATE sa_plan_task
SET state = 'executing', worker = ?, lease_until_ns = ?, attempt = attempt + 1
WHERE plan_id = ? AND id = ? AND attempt = ?
  AND (state = 'available' OR (state = 'executing' AND lease_until_ns <= ?))
|}
    (fun stmt ->
      let values =
        [
          Sqlite3.Data.TEXT worker;
          INT lease_until_ns;
          TEXT plan_id;
          TEXT task_id;
          INT (Int64.of_int previous_attempt);
          INT now_ns;
        ]
      in
      Result.bind (bind_values_result "bind claim update" stmt values)
        ~f:(fun () ->
          Result.bind (step_done "claim Sa-plan task" stmt) ~f:(fun () ->
              if Sqlite3.changes store.db = 1 then
                Ok
                  (Some
                     { task_id; attempt = previous_attempt + 1; lease_until_ns })
              else Error "Sa-plan task claim lost compare-and-set")))

let claim_next store ~plan_id ~worker ~now_ns ~lease_ns =
  Result.bind (lease_deadline ~worker ~now_ns ~lease_ns) ~f:(fun lease_until_ns ->
    transaction store (fun () ->
        Result.bind (select_claimable store.db ~plan_id ~now_ns) ~f:(function
          | None -> Ok None
          | Some (task_id, previous_attempt) ->
              claim_update store ~plan_id ~task_id ~worker ~now_ns
                ~lease_until_ns ~previous_attempt)))

let select_specific_claimable db ~plan_id ~id_or_name ~now_ns =
  with_stmt db
    {|
SELECT task.attempt, task.id
FROM sa_plan_task AS task
WHERE task.plan_id = ? AND (task.id = ? OR task.name = ?)
  AND (task.state = 'available'
       OR (task.state = 'executing' AND task.lease_until_ns <= ?))
  AND NOT EXISTS (
    SELECT 1 FROM sa_plan_dependency AS edge
    JOIN sa_plan_task AS dependency
      ON dependency.plan_id = edge.plan_id
     AND dependency.id = edge.dependency_id
    WHERE edge.plan_id = task.plan_id AND edge.task_id = task.id
      AND dependency.state <> 'completed'
  )
|}
    (fun stmt ->
      Result.bind
        (bind_values_result "bind specific task claim" stmt
           [ Sqlite3.Data.TEXT plan_id; TEXT id_or_name; TEXT id_or_name; INT now_ns ])
        ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW ->
              let attempt = Sqlite3.column_int stmt 0 in
              let actual_id = Sqlite3.column_text stmt 1 in
              Ok (Some (attempt, actual_id))
          | Sqlite3.Rc.DONE -> Ok None
          | rc -> rc_error "select specific claimable Sa-plan task" rc))

let claim_task store ~plan_id ~task_id ~worker ~now_ns ~lease_ns =
  Result.bind (lease_deadline ~worker ~now_ns ~lease_ns) ~f:(fun lease_until_ns ->
    transaction store (fun () ->
        Result.bind
          (select_specific_claimable store.db ~plan_id ~id_or_name:task_id ~now_ns)
          ~f:(function
          | None -> Error ("Sa-plan task is not claimable: " ^ task_id)
          | Some (previous_attempt, actual_id) ->
              Result.bind
                (claim_update store ~plan_id ~task_id:actual_id ~worker ~now_ns
                   ~lease_until_ns ~previous_attempt) ~f:(function
                | Some claim -> Ok claim
                | None -> Error "specific Sa-plan task claim disappeared"))))

let release_task store ~plan_id ~task_id ~worker ~expected_attempt ~now_ns =
  let open Result.Let_syntax in
  let%bind () = validate_completion ~worker ~expected_attempt ~now_ns in
  transaction store (fun () ->
      with_stmt store.db
        {|UPDATE sa_plan_task SET state = 'available', worker = NULL, lease_until_ns = NULL
          WHERE plan_id = ? AND (id = ? OR name = ?) AND state = 'executing'
            AND worker = ? AND attempt = ? AND lease_until_ns > ?|}
        (fun stmt ->
          let%bind () = bind_values_result "bind Sa-plan task release" stmt
            [ TEXT plan_id; TEXT task_id; TEXT task_id; TEXT worker;
              INT (Int64.of_int expected_attempt); INT now_ns ] in
          let%bind () = step_done "release Sa-plan task" stmt in
          if Sqlite3.changes store.db = 1 then Ok ()
          else Error "Sa-plan release rejected: current unexpired claim attempt required"))

let complete_task store ~plan_id ~task_id ~worker ~expected_attempt ~result ~now_ns =
  let open Result.Let_syntax in
  let%bind () = validate_completion ~worker ~expected_attempt ~now_ns in
  transaction store (fun () ->
      with_stmt store.db
        {|UPDATE sa_plan_task SET state = 'completed', result = ?, completed_at_ns = ?,
            lease_until_ns = NULL
          WHERE plan_id = ? AND (id = ? OR name = ?) AND state = 'executing'
            AND worker = ? AND attempt = ? AND lease_until_ns > ?|}
        (fun stmt ->
          let%bind () = bind_values_result "bind task completion" stmt
            [ TEXT result; INT now_ns; TEXT plan_id; TEXT task_id; TEXT task_id;
              TEXT worker; INT (Int64.of_int expected_attempt); INT now_ns ] in
          let%bind () = step_done "complete Sa-plan task" stmt in
          if Sqlite3.changes store.db = 1 then Ok ()
          else Error "Sa-plan completion rejected: current unexpired claim attempt required"))

let select_activity db ~workflow_id ~activity_id =
  with_stmt db
    "SELECT result FROM sa_plan_activity WHERE workflow_id = ? AND activity_id \
     = ?" (fun stmt ->
      Result.bind
        (bind_values_result "bind activity query" stmt
           [ Sqlite3.Data.TEXT workflow_id; TEXT activity_id ])
        ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW -> Ok (Some (Sqlite3.column_text stmt 0))
          | Sqlite3.Rc.DONE -> Ok None
          | rc -> rc_error "read Sa-plan activity" rc))

let complete_activity store ~workflow_id ~activity_id ~result ~now_ns =
  transaction store (fun () ->
      match select_activity store.db ~workflow_id ~activity_id with
      | Error _ as error -> error
      | Ok (Some persisted) -> Ok persisted
      | Ok None ->
          with_stmt store.db
            {|
INSERT INTO sa_plan_activity(workflow_id, activity_id, result, completed_at_ns)
VALUES (?, ?, ?, ?)
|}
            (fun stmt ->
              Result.bind
                (bind_values_result "bind activity completion" stmt
                   [
                     Sqlite3.Data.TEXT workflow_id;
                     TEXT activity_id;
                     TEXT result;
                     INT now_ns;
                   ])
                ~f:(fun () ->
                  Result.map (step_done "complete Sa-plan activity" stmt)
                    ~f:(fun () -> result))))

let validate_factor label value =
  if value < 0 then Error (label ^ " selection factor must be non-negative")
  else Ok ()

let validate_factors factors =
  [
    ("stpa", factors.stpa);
    ("fema", factors.fema);
    ("criticality", factors.criticality);
    ("dependency", factors.dependency);
    ("standards", factors.standards);
    ("agent_fit", factors.agent_fit);
  ]
  |> List.fold ~init:(Ok ()) ~f:(fun acc (label, value) ->
      Result.bind acc ~f:(fun () -> validate_factor label value))

let record_selection store ~plan_id ~task_id ~actor ~old_priority ~new_priority
    ~factors ~rationale ~now_ns =
  if String.is_empty actor then
    Error "Sa-plan selection actor must be non-empty"
  else if String.is_empty rationale then
    Error "Sa-plan selection rationale must be non-empty"
  else if new_priority < 0 then
    Error "Sa-plan selection priority must be non-negative"
  else
    Result.bind (validate_factors factors) ~f:(fun () ->
        transaction store (fun () ->
            with_stmt store.db
              {|
INSERT INTO sa_plan_selection_evidence
  (plan_id, task_id, actor, old_priority, new_priority, stpa, fema,
   criticality, dependency, standards, agent_fit, rationale, recorded_at_ns)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
|}
              (fun stmt ->
                let values =
                  [
                    Sqlite3.Data.TEXT plan_id;
                    TEXT task_id;
                    TEXT actor;
                    Option.value_map old_priority ~default:Sqlite3.Data.NULL
                      ~f:(fun value -> Sqlite3.Data.INT (Int64.of_int value));
                    INT (Int64.of_int new_priority);
                    INT (Int64.of_int factors.stpa);
                    INT (Int64.of_int factors.fema);
                    INT (Int64.of_int factors.criticality);
                    INT (Int64.of_int factors.dependency);
                    INT (Int64.of_int factors.standards);
                    INT (Int64.of_int factors.agent_fit);
                    TEXT rationale;
                    INT now_ns;
                  ]
                in
                Result.bind
                  (bind_values_result "bind selection evidence" stmt values)
                  ~f:(fun () -> step_done "insert selection evidence" stmt))))

let latest_selection store ~plan_id ~task_id =
  match ensure_open store with
  | Error _ as error -> error
  | Ok () ->
      with_stmt store.db
        {|
SELECT actor, old_priority, new_priority, stpa, fema, criticality,
       dependency, standards, agent_fit, rationale, recorded_at_ns
FROM sa_plan_selection_evidence
WHERE plan_id = ? AND task_id = ?
ORDER BY sequence DESC LIMIT 1
|}
        (fun stmt ->
          Result.bind
            (bind_values_result "bind latest selection" stmt
               [ Sqlite3.Data.TEXT plan_id; TEXT task_id ])
            ~f:(fun () ->
              match Sqlite3.step stmt with
              | Sqlite3.Rc.DONE -> Ok None
              | Sqlite3.Rc.ROW ->
                  let old_priority =
                    match Sqlite3.column stmt 1 with
                    | Sqlite3.Data.NULL -> None
                    | _ -> Some (Sqlite3.column_int stmt 1)
                  in
                  Ok
                    (Some
                       {
                         actor = Sqlite3.column_text stmt 0;
                         old_priority;
                         new_priority = Sqlite3.column_int stmt 2;
                         factors =
                           {
                             stpa = Sqlite3.column_int stmt 3;
                             fema = Sqlite3.column_int stmt 4;
                             criticality = Sqlite3.column_int stmt 5;
                             dependency = Sqlite3.column_int stmt 6;
                             standards = Sqlite3.column_int stmt 7;
                             agent_fit = Sqlite3.column_int stmt 8;
                           };
                         rationale = Sqlite3.column_text stmt 9;
                         recorded_at_ns = Sqlite3.column_int64 stmt 10;
                       })
              | rc -> rc_error "read latest selection" rc))

let task_runtime store ~plan_id ~task_id =
  with_stmt store.db
    {|
SELECT estimate_points, lease_until_ns
FROM sa_plan_task WHERE plan_id = ? AND id = ?
|}
    (fun stmt ->
      Result.bind
        (bind_values_result "bind task observation runtime" stmt
           [ Sqlite3.Data.TEXT plan_id; TEXT task_id ])
        ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW ->
              let optional_int column =
                match Sqlite3.column stmt column with
                | Sqlite3.Data.NULL -> None
                | _ -> Some (Sqlite3.column_int stmt column)
              in
              let optional_int64 column =
                match Sqlite3.column stmt column with
                | Sqlite3.Data.NULL -> None
                | _ -> Some (Sqlite3.column_int64 stmt column)
              in
              Ok (optional_int 0, optional_int64 1)
          | Sqlite3.Rc.DONE -> Error ("Unknown Sa-plan task: " ^ task_id)
          | rc -> rc_error "read task observation runtime" rc))

let task_dependencies store ~plan_id ~task_id =
  with_stmt store.db
    {|
SELECT dependency_id FROM sa_plan_dependency
WHERE plan_id = ? AND task_id = ? ORDER BY dependency_id
|}
    (fun stmt ->
      Result.bind
        (bind_values_result "bind task observation dependencies" stmt
           [ Sqlite3.Data.TEXT plan_id; TEXT task_id ])
        ~f:(fun () ->
          let rec loop acc =
            match Sqlite3.step stmt with
            | Sqlite3.Rc.ROW -> loop (Sqlite3.column_text stmt 0 :: acc)
            | Sqlite3.Rc.DONE -> Ok (List.rev acc)
            | rc -> rc_error "read task observation dependencies" rc
          in
          loop []))

let list_task_observations store ~plan_id =
  Result.bind (list_tasks store ~plan_id) ~f:(fun tasks ->
      List.fold tasks ~init:(Ok []) ~f:(fun acc task ->
          Result.bind acc ~f:(fun observations ->
              Result.bind (task_runtime store ~plan_id ~task_id:task.id)
                ~f:(fun (estimate_points, lease_until_ns) ->
                  Result.bind
                    (task_dependencies store ~plan_id ~task_id:task.id)
                    ~f:(fun dependencies ->
                      Result.map
                        (latest_selection store ~plan_id ~task_id:task.id)
                        ~f:(fun selection ->
                          {
                            task;
                            estimate_points;
                            lease_until_ns;
                            dependencies;
                            selection;
                          }
                          :: observations)))))
      |> Result.map ~f:List.rev)

let job_state_to_text = function
  | Job_available -> "available"
  | Job_executing -> "executing"
  | Job_retry -> "retry"
  | Job_completed -> "completed"
  | Job_discarded -> "discarded"
  | Job_cancelled -> "cancelled"

let job_state_of_text = function
  | "available" -> Job_available
  | "executing" -> Job_executing
  | "retry" -> Job_retry
  | "completed" -> Job_completed
  | "discarded" -> Job_discarded
  | "cancelled" -> Job_cancelled
  | value -> failwith ("unknown durable Sa-plan job state: " ^ value)

let optional_text stmt column =
  match Sqlite3.column stmt column with
  | Sqlite3.Data.NULL -> None
  | _ -> Some (Sqlite3.column_text stmt column)

let optional_int64 stmt column =
  match Sqlite3.column stmt column with
  | Sqlite3.Data.NULL -> None
  | _ -> Some (Sqlite3.column_int64 stmt column)

let job_view_of_stmt stmt =
  {
    id = Sqlite3.column_text stmt 0;
    name = Sqlite3.column_text stmt 1;
    queue = Sqlite3.column_text stmt 2;
    worker = Sqlite3.column_text stmt 3;
    args = Sqlite3.column_text stmt 4;
    state = job_state_of_text (Sqlite3.column_text stmt 5);
    attempt = Sqlite3.column_int stmt 6;
    max_attempts = Sqlite3.column_int stmt 7;
    available_at_ns = Sqlite3.column_int64 stmt 8;
    lease_owner = optional_text stmt 9;
    lease_until_ns = optional_int64 stmt 10;
    result = optional_text stmt 11;
  }

let job_columns =
  "id, name, queue, worker, args, state, attempt, max_attempts, \
   available_at_ns, lease_owner, lease_until_ns, result"

let find_job_db db id_or_name =
  with_stmt db
    ("SELECT " ^ job_columns
   ^ " FROM sa_plan_job WHERE id = ? OR name = ? LIMIT 1")
    (fun stmt ->
      Result.bind
        (bind_values_result "bind Sa-plan job lookup" stmt
           [ Sqlite3.Data.TEXT id_or_name; TEXT id_or_name ])
        ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.DONE -> Ok None
          | Sqlite3.Rc.ROW -> Ok (Some (job_view_of_stmt stmt))
          | rc -> rc_error "read Sa-plan job" rc))

let enqueue_job store ~id ~name ~queue ~worker ~args ~max_attempts ~now_ns =
  if String.is_empty id then Error "Sa-plan job ID must be non-empty"
  else if String.is_empty queue then Error "Sa-plan job queue must be non-empty"
  else if String.is_empty worker then
    Error "Sa-plan job worker must be non-empty"
  else if max_attempts <= 0 then
    Error "Sa-plan job max_attempts must be positive"
  else
    Result.bind (validate_name name) ~f:(fun name ->
        transaction store (fun () ->
            with_stmt store.db
              {|
INSERT INTO sa_plan_job
  (id, name, queue, worker, args, state, attempt, max_attempts,
   available_at_ns, inserted_at_ns)
VALUES (?, ?, ?, ?, ?, 'available', 0, ?, ?, ?)
|}
              (fun stmt ->
                Result.bind
                  (bind_values_result "bind Sa-plan job enqueue" stmt
                     [
                       Sqlite3.Data.TEXT id;
                       TEXT name;
                       TEXT queue;
                       TEXT worker;
                       TEXT args;
                       INT (Int64.of_int max_attempts);
                       INT now_ns;
                       INT now_ns;
                     ])
                  ~f:(fun () ->
                    Result.bind (step_done "enqueue Sa-plan job" stmt)
                      ~f:(fun () ->
                        Result.bind (find_job_db store.db id) ~f:(function
                          | Some job -> Ok job
                          | None -> Error "enqueued Sa-plan job disappeared"))))))

let select_claimable_job db ~queue ~now_ns =
  with_stmt db
    ("SELECT " ^ job_columns
   ^ {|
 FROM sa_plan_job
 WHERE queue = ? AND available_at_ns <= ?
   AND (state IN ('available','retry')
        OR (state = 'executing' AND lease_until_ns <= ?))
 ORDER BY available_at_ns, inserted_at_ns, id
 LIMIT 1
|}
    )
    (fun stmt ->
      Result.bind
        (bind_values_result "bind claimable Sa-plan job" stmt
           [ Sqlite3.Data.TEXT queue; INT now_ns; INT now_ns ])
        ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.DONE -> Ok None
          | Sqlite3.Rc.ROW -> Ok (Some (job_view_of_stmt stmt))
          | rc -> rc_error "select claimable Sa-plan job" rc))

let claim_job store ~queue ~worker ~now_ns ~lease_ns =
  let open Result.Let_syntax in
  let%bind lease_until_ns = lease_deadline ~worker ~now_ns ~lease_ns in
  transaction store (fun () ->
      let%bind job = select_claimable_job store.db ~queue ~now_ns in
      match job with
      | None -> Ok None
      | Some job when job.attempt < 0 || job.attempt = Stdlib.max_int ->
          Error "Sa-plan job attempt is invalid or exhausted"
      | Some job ->
          with_stmt store.db
            {|UPDATE sa_plan_job SET state = 'executing', lease_owner = ?,
                lease_until_ns = ?, attempt = attempt + 1
              WHERE id = ? AND attempt = ? AND
                (state IN ('available','retry')
                 OR (state = 'executing' AND lease_until_ns <= ?))|}
            (fun stmt ->
              let%bind () = bind_values_result "bind Sa-plan job claim" stmt
                [ TEXT worker; INT lease_until_ns; TEXT job.id;
                  INT (Int64.of_int job.attempt); INT now_ns ] in
              let%bind () = step_done "claim Sa-plan job" stmt in
              if Sqlite3.changes store.db <> 1 then
                Error "Sa-plan job claim lost compare-and-set"
              else
                Result.bind (find_job_db store.db job.id) ~f:(function
                  | Some claimed -> Ok (Some claimed)
                  | None -> Error "claimed Sa-plan job disappeared")))

let retry_delay_ns ~attempt =
  let shift = Int.min 20 (Int.max 0 attempt) in
  let seconds = Int64.shift_left 15L shift |> Int64.min 3_600L in
  Int64.(seconds * 1_000_000_000L)

let complete_job store ~id_or_name ~worker ~expected_attempt ~outcome ~now_ns =
  let open Result.Let_syntax in
  let%bind () = validate_completion ~worker ~expected_attempt ~now_ns in
  transaction store (fun () ->
      let%bind job = find_job_db store.db id_or_name in
      match job with
      | None -> Error ("Unknown Sa-plan job: " ^ id_or_name)
      | Some job ->
          if not (Poly.equal job.state Job_executing)
             || not (Option.equal String.equal job.lease_owner (Some worker))
             || job.attempt <> expected_attempt
             || not (Option.value_map job.lease_until_ns ~default:false
                       ~f:(fun deadline -> Int64.(deadline > now_ns)))
          then Error "Sa-plan job completion rejected: current unexpired claim attempt required"
          else
            let%bind state, result, available_at_ns =
              match outcome with
              | `Ok result -> Ok (Job_completed, result, job.available_at_ns)
              | `Error error when job.attempt >= job.max_attempts ->
                  Ok (Job_discarded, error, job.available_at_ns)
              | `Error error ->
                  Result.map
                    (lease_deadline ~worker ~now_ns ~lease_ns:(retry_delay_ns ~attempt:job.attempt))
                    ~f:(fun deadline -> Job_retry, error, deadline)
            in
            with_stmt store.db
              {|UPDATE sa_plan_job SET state = ?, result = ?, available_at_ns = ?,
                  lease_owner = NULL, lease_until_ns = NULL
                WHERE id = ? AND state = 'executing' AND lease_owner = ?
                  AND attempt = ? AND lease_until_ns > ?|}
              (fun stmt ->
                let%bind () = bind_values_result "bind Sa-plan job completion" stmt
                  [ TEXT (job_state_to_text state); TEXT result; INT available_at_ns;
                    TEXT job.id; TEXT worker; INT (Int64.of_int expected_attempt); INT now_ns ] in
                let%bind () = step_done "complete Sa-plan job" stmt in
                if Sqlite3.changes store.db <> 1 then
                  Error "Sa-plan job completion lost compare-and-set"
                else
                  Result.bind (find_job_db store.db job.id) ~f:(function
                    | Some completed -> Ok completed
                    | None -> Error "completed Sa-plan job disappeared")))

let cancel_job store ~id_or_name ~reason ~now_ns:_ =
  if String.is_empty reason then Error "Sa-plan job cancellation reason must be non-empty"
  else
    transaction store (fun () ->
        Result.bind (find_job_db store.db id_or_name) ~f:(function
          | None -> Error ("Unknown Sa-plan job: " ^ id_or_name)
          | Some job ->
              (match job.state with
              | Job_completed | Job_discarded | Job_cancelled ->
                  Error "Sa-plan job cancellation rejected: job is terminal"
              | Job_available | Job_executing | Job_retry ->
                  with_stmt store.db
                    {|
UPDATE sa_plan_job
SET state = 'cancelled', result = ?,
    lease_owner = NULL, lease_until_ns = NULL
WHERE id = ? AND state IN ('available', 'executing', 'retry')
|}
                    (fun stmt ->
                      Result.bind
                        (bind_values_result "bind Sa-plan job cancellation" stmt
                           [ Sqlite3.Data.TEXT reason; TEXT job.id ])
                        ~f:(fun () ->
                          Result.bind (step_done "cancel Sa-plan job" stmt)
                            ~f:(fun () ->
                              if Sqlite3.changes store.db <> 1 then
                                Error
                                  "Sa-plan job cancellation lost compare-and-set"
                              else
                                Result.bind (find_job_db store.db job.id)
                                  ~f:(function
                                  | Some cancelled -> Ok cancelled
                                  | None ->
                                      Error
                                        "cancelled Sa-plan job disappeared")))))))

let list_jobs store ~queue =
  match ensure_open store with
  | Error _ as error -> error
  | Ok () ->
      let sql =
        "SELECT " ^ job_columns ^ " FROM sa_plan_job"
        ^ (match queue with None -> "" | Some _ -> " WHERE queue = ?")
        ^ " ORDER BY inserted_at_ns, id"
      in
      with_stmt store.db sql (fun stmt ->
          let bound =
            match queue with
            | None -> Ok ()
            | Some queue -> bind stmt 1 (Sqlite3.Data.TEXT queue)
          in
          Result.bind bound ~f:(fun () ->
              let rec loop acc =
                match Sqlite3.step stmt with
                | Sqlite3.Rc.ROW -> loop (job_view_of_stmt stmt :: acc)
                | Sqlite3.Rc.DONE -> Ok (List.rev acc)
                | rc -> rc_error "list Sa-plan jobs" rc
              in
              loop []))

let find_workflow_id db id_or_name =
  with_stmt db
    "SELECT id, state FROM sa_plan_workflow WHERE id = ? OR name = ? LIMIT 1"
    (fun stmt ->
      Result.bind
        (bind_values_result "bind Sa-plan workflow lookup" stmt
           [ Sqlite3.Data.TEXT id_or_name; TEXT id_or_name ])
        ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.DONE -> Ok None
          | Sqlite3.Rc.ROW ->
              Ok (Some (Sqlite3.column_text stmt 0, Sqlite3.column_text stmt 1))
          | rc -> rc_error "read Sa-plan workflow" rc))

let append_workflow_event db ~workflow_id ~kind ~payload ~now_ns =
  with_stmt db
    {|
INSERT INTO sa_plan_workflow_event
  (workflow_id, sequence, kind, payload, occurred_at_ns)
SELECT ?, COALESCE(MAX(sequence), -1) + 1, ?, ?, ?
FROM sa_plan_workflow_event WHERE workflow_id = ?
|}
    (fun stmt ->
      Result.bind
        (bind_values_result "bind Sa-plan workflow event" stmt
           [
             Sqlite3.Data.TEXT workflow_id;
             TEXT kind;
             TEXT payload;
             INT now_ns;
             TEXT workflow_id;
           ])
        ~f:(fun () -> step_done "append Sa-plan workflow event" stmt))

let start_workflow_with_input store ~id ~name ~kind ~input ~now_ns =
  if String.is_empty id then Error "Sa-plan workflow ID must be non-empty"
  else if String.is_empty kind then
    Error "Sa-plan workflow kind must be non-empty"
  else
    Result.bind (validate_name name) ~f:(fun name ->
        transaction store (fun () ->
            with_stmt store.db
              {|
INSERT INTO sa_plan_workflow(id, name, kind, input, state, created_at_ns)
VALUES (?, ?, ?, ?, 'running', ?)
|}
              (fun stmt ->
                Result.bind
                  (bind_values_result "bind Sa-plan workflow start" stmt
                     [
                       Sqlite3.Data.TEXT id;
                       TEXT name;
                       TEXT kind;
                       TEXT input;
                       INT now_ns;
                     ])
                  ~f:(fun () ->
                    Result.bind (step_done "start Sa-plan workflow" stmt)
                      ~f:(fun () ->
                        append_workflow_event store.db ~workflow_id:id
                          ~kind:"workflow_started" ~payload:input ~now_ns)))))

let start_workflow store ~id ~name ~now_ns =
  start_workflow_with_input store ~id ~name ~kind:"workflow" ~input:"" ~now_ns

let finish_workflow store ~id_or_name ~state ~result ~now_ns =
  transaction store (fun () ->
      Result.bind (find_workflow_id store.db id_or_name) ~f:(function
        | None -> Error ("Unknown Sa-plan workflow: " ^ id_or_name)
        | Some (_, current) when not (String.equal current "running") ->
            Error "Sa-plan workflow is already terminal"
        | Some (workflow_id, _) ->
            with_stmt store.db
              {|
UPDATE sa_plan_workflow
SET state = ?, result = ?, completed_at_ns = ?
WHERE id = ? AND state = 'running'
|}
              (fun stmt ->
                Result.bind
                  (bind_values_result "bind Sa-plan workflow completion" stmt
                     [
                       Sqlite3.Data.TEXT state;
                       TEXT result;
                       INT now_ns;
                       TEXT workflow_id;
                     ])
                  ~f:(fun () ->
                    Result.bind (step_done "finish Sa-plan workflow" stmt)
                      ~f:(fun () ->
                        if Sqlite3.changes store.db <> 1 then
                          Error
                            "Sa-plan workflow completion lost compare-and-set"
                        else
                          append_workflow_event store.db ~workflow_id
                            ~kind:
                              (if String.equal state "completed" then
                                 "workflow_completed"
                               else "workflow_failed")
                            ~payload:result ~now_ns)))))

let complete_workflow store ~id_or_name ~result ~now_ns =
  finish_workflow store ~id_or_name ~state:"completed" ~result ~now_ns

let fail_workflow store ~id_or_name ~error ~now_ns =
  finish_workflow store ~id_or_name ~state:"failed" ~result:error ~now_ns

let find_workflow_activity db ~workflow_id ~idempotency_key =
  with_stmt db
    {|
SELECT result FROM sa_plan_workflow_activity
WHERE workflow_id = ? AND idempotency_key = ?
|}
    (fun stmt ->
      Result.bind
        (bind_values_result "bind Sa-plan workflow activity lookup" stmt
           [ Sqlite3.Data.TEXT workflow_id; TEXT idempotency_key ])
        ~f:(fun () ->
          match Sqlite3.step stmt with
          | Sqlite3.Rc.DONE -> Ok None
          | Sqlite3.Rc.ROW -> Ok (Some (Sqlite3.column_text stmt 0))
          | rc -> rc_error "read Sa-plan workflow activity" rc))

let complete_workflow_activity store ~workflow_id_or_name ~id ~name
    ~idempotency_key ~result ~now_ns =
  if String.is_empty id || String.is_empty idempotency_key then
    Error "Sa-plan activity ID and idempotency key must be non-empty"
  else
    Result.bind (validate_name name) ~f:(fun name ->
        transaction store (fun () ->
            Result.bind (find_workflow_id store.db workflow_id_or_name)
              ~f:(function
              | None ->
                  Error ("Unknown Sa-plan workflow: " ^ workflow_id_or_name)
              | Some (workflow_id, state) ->
                  Result.bind
                    (find_workflow_activity store.db ~workflow_id
                       ~idempotency_key) ~f:(function
                    | Some persisted -> Ok persisted
                    | None when not (String.equal state "running") ->
                        Error "Sa-plan workflow is terminal"
                    | None ->
                        with_stmt store.db
                          {|
INSERT INTO sa_plan_workflow_activity
  (workflow_id, id, name, idempotency_key, result, completed_at_ns)
VALUES (?, ?, ?, ?, ?, ?)
|}
                          (fun stmt ->
                            Result.bind
                              (bind_values_result
                                 "bind Sa-plan workflow activity" stmt
                                 [
                                   Sqlite3.Data.TEXT workflow_id;
                                   TEXT id;
                                   TEXT name;
                                   TEXT idempotency_key;
                                   TEXT result;
                                   INT now_ns;
                                 ])
                              ~f:(fun () ->
                                Result.bind
                                  (step_done
                                     "complete Sa-plan workflow activity" stmt)
                                  ~f:(fun () ->
                                    Result.map
                                      (append_workflow_event store.db
                                         ~workflow_id ~kind:"activity_completed"
                                         ~payload:(id ^ ":" ^ result)
                                         ~now_ns)
                                      ~f:(fun () -> result))))))))

let workflow_history store ~id_or_name =
  match ensure_open store with
  | Error _ as error -> error
  | Ok () ->
      Result.bind (find_workflow_id store.db id_or_name) ~f:(function
        | None -> Error ("Unknown Sa-plan workflow: " ^ id_or_name)
        | Some (workflow_id, _) ->
            with_stmt store.db
              {|
SELECT sequence, kind, payload, occurred_at_ns
FROM sa_plan_workflow_event WHERE workflow_id = ? ORDER BY sequence
|}
              (fun stmt ->
                Result.bind (bind stmt 1 (Sqlite3.Data.TEXT workflow_id))
                  ~f:(fun () ->
                    let rec loop acc =
                      match Sqlite3.step stmt with
                      | Sqlite3.Rc.ROW ->
                          loop
                            ({
                               sequence = Sqlite3.column_int stmt 0;
                               kind = Sqlite3.column_text stmt 1;
                               payload = Sqlite3.column_text stmt 2;
                               occurred_at_ns = Sqlite3.column_int64 stmt 3;
                             }
                            :: acc)
                      | Sqlite3.Rc.DONE -> Ok (List.rev acc)
                      | rc -> rc_error "read Sa-plan workflow history" rc
                    in
                    loop [])))

let list_workflows store =
  match ensure_open store with
  | Error _ as error -> error
  | Ok () ->
      with_stmt store.db
        {|
SELECT id, name, kind, input, state, result, created_at_ns, completed_at_ns
FROM sa_plan_workflow ORDER BY created_at_ns, id
|}
        (fun stmt ->
          let rec rows acc =
            match Sqlite3.step stmt with
            | Sqlite3.Rc.ROW ->
                rows
                  (( Sqlite3.column_text stmt 0,
                     Sqlite3.column_text stmt 1,
                     Sqlite3.column_text stmt 2,
                     Sqlite3.column_text stmt 3,
                     Sqlite3.column_text stmt 4,
                     optional_text stmt 5,
                     Sqlite3.column_int64 stmt 6,
                     optional_int64 stmt 7 )
                  :: acc)
            | Sqlite3.Rc.DONE -> Ok (List.rev acc)
            | rc -> rc_error "list Sa-plan workflows" rc
          in
          Result.bind (rows []) ~f:(fun workflows ->
              List.fold workflows ~init:(Ok [])
                ~f:(fun
                    acc
                    ( id,
                      name,
                      kind,
                      input,
                      state,
                      result,
                      created_at_ns,
                      completed_at_ns )
                  ->
                  Result.bind acc ~f:(fun views ->
                      Result.map (workflow_history store ~id_or_name:id)
                        ~f:(fun events ->
                          {
                            id;
                            name;
                            kind;
                            input;
                            state;
                            result;
                            created_at_ns;
                            completed_at_ns;
                            events;
                          }
                          :: views)))
              |> Result.map ~f:List.rev))
