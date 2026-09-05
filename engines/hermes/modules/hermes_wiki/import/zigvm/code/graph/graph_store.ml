module Graph = Graph_intelligence

type context = {
  id : string;
  title : string;
  kind : string;
  updated_at : string;
  node_count : int;
  edge_count : int;
}

type job = {
  id : int;
  command : string;
  state : string;
  requested_by : string;
  role : string;
  attempts : int;
  max_attempts : int;
  inserted_at : string;
  updated_at : string;
  error : string option;
  result : Yojson.Safe.t option;
}

type work_item = { job : job; args : Yojson.Safe.t }

let ensure_schema db =
  Db.exec db
    "CREATE TABLE IF NOT EXISTS graph_contexts (\
     id TEXT PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL,\
     source_kind TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,\
     updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, node_count INTEGER NOT NULL DEFAULT 0,\
     edge_count INTEGER NOT NULL DEFAULT 0);\
     CREATE TABLE IF NOT EXISTS graph_snapshots (\
     id INTEGER PRIMARY KEY AUTOINCREMENT, context_id TEXT NOT NULL, digest TEXT NOT NULL,\
     graph_json TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,\
     UNIQUE(context_id,digest), FOREIGN KEY(context_id) REFERENCES graph_contexts(id));\
     CREATE TABLE IF NOT EXISTS graph_sources (\
     id INTEGER PRIMARY KEY AUTOINCREMENT, context_id TEXT NOT NULL, source_kind TEXT NOT NULL,\
     source_uri TEXT NOT NULL, content_digest TEXT, state TEXT NOT NULL DEFAULT 'queued',\
     provenance_json TEXT NOT NULL DEFAULT '{}', refreshed_at TEXT,\
     FOREIGN KEY(context_id) REFERENCES graph_contexts(id));\
     CREATE TABLE IF NOT EXISTS graph_statements (\
     id INTEGER PRIMARY KEY AUTOINCREMENT, context_id TEXT NOT NULL, source_id INTEGER,\
     ordinal INTEGER NOT NULL, content TEXT NOT NULL, content_digest TEXT NOT NULL,\
     metadata_json TEXT NOT NULL DEFAULT '{}', UNIQUE(context_id,content_digest),\
     FOREIGN KEY(context_id) REFERENCES graph_contexts(id),\
     FOREIGN KEY(source_id) REFERENCES graph_sources(id));\
     CREATE TABLE IF NOT EXISTS graph_insights (\
     id INTEGER PRIMARY KEY AUTOINCREMENT, context_id TEXT NOT NULL, provider TEXT NOT NULL,\
     model TEXT NOT NULL, mode TEXT NOT NULL, evidence_json TEXT NOT NULL,\
     prompt_digest TEXT NOT NULL, response_text TEXT, response_digest TEXT,\
     state TEXT NOT NULL, usage_json TEXT NOT NULL DEFAULT '{}',\
     created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,\
     FOREIGN KEY(context_id) REFERENCES graph_contexts(id));\
     CREATE TABLE IF NOT EXISTS graph_jobs (\
     id INTEGER PRIMARY KEY AUTOINCREMENT, idempotency_key TEXT NOT NULL UNIQUE,\
     command TEXT NOT NULL, args_json TEXT NOT NULL, requested_by TEXT NOT NULL, role TEXT NOT NULL,\
     state TEXT NOT NULL CHECK(state IN ('available','executing','retry','completed','discarded')),\
     attempts INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL DEFAULT 5,\
     scheduled_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,\
     inserted_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,\
     updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, error TEXT);\
     CREATE INDEX IF NOT EXISTS graph_jobs_poll ON graph_jobs(state,scheduled_at,id);\
     CREATE INDEX IF NOT EXISTS graph_snapshots_context ON graph_snapshots(context_id,id DESC);";
  if
    Db.scalar db
      "SELECT name FROM pragma_table_info('graph_jobs') WHERE name='result_json' LIMIT 1;"
    = None
  then Db.exec db "ALTER TABLE graph_jobs ADD COLUMN result_json TEXT;"

let split unit_separator row = String.split_on_char unit_separator row

let load_system_graph db =
  let node_rows =
    Db.rows db
      "SELECT kind||char(31)||name||char(31)||COALESCE(layer,'')||char(31)||\
       COALESCE(stratum,'')||char(31)||COALESCE(detail,'')\
       FROM onto_node WHERE present=1 ORDER BY kind,name;"
  in
  let nodes =
    List.filter_map
      (fun row ->
        match split '\x1f' row with
        | [ kind; name; layer; group; detail ] ->
            Some
              Graph.
                {
                  id = kind ^ ":" ^ name;
                  label = name;
                  kind;
                  layer;
                  group;
                  detail;
                  weight = 1.;
                }
        | _ -> None)
      node_rows
  in
  let edge_rows =
    Db.rows db
      "SELECT src||char(31)||dst||char(31)||rel FROM onto_edge \
       WHERE present=1 ORDER BY src,rel,dst;"
  in
  let edges =
    List.filter_map
      (fun row ->
        match split '\x1f' row with
        | [ source; target; relation ] ->
            Some Graph.{ source; target; relation; weight = 1. }
        | _ -> None)
      edge_rows
  in
  Graph.normalize
    { id = "system"; title = "ZigVM living ontology"; kind = "system"; nodes; edges }

let sql_text value =
  "'" ^ String.concat "''" (String.split_on_char '\'' value) ^ "'"

let save_graph db ~source_kind graph =
  ensure_schema db;
  let graph = Graph.normalize graph in
  let analytics = Graph.analyze graph in
  let json = Graph.to_yojson ~analytics graph |> Yojson.Safe.to_string in
  let digest = Digest.to_hex (Digest.string json) in
  Db.transaction db (fun () ->
      Db.exec db
        (Printf.sprintf
           "INSERT INTO graph_contexts(id,title,kind,source_kind,node_count,edge_count)\
            VALUES(%s,%s,%s,%s,%d,%d)\
            ON CONFLICT(id) DO UPDATE SET title=excluded.title,kind=excluded.kind,\
            source_kind=excluded.source_kind,node_count=excluded.node_count,\
            edge_count=excluded.edge_count,updated_at=CURRENT_TIMESTAMP;"
           (sql_text graph.id) (sql_text graph.title) (sql_text graph.kind)
           (sql_text source_kind)
           analytics.node_count analytics.edge_count);
      Db.exec db
        (Printf.sprintf
           "INSERT OR IGNORE INTO graph_snapshots(context_id,digest,graph_json)\
            VALUES(%s,%s,%s);"
           (sql_text graph.id) (sql_text digest) (sql_text json)));
  digest

let snapshot_system_graph db graph = save_graph db ~source_kind:"harness" graph

let save_text_graph db ~source_uri ~text graph =
  let digest = save_graph db ~source_kind:"text" graph in
  let content_digest = Digest.to_hex (Digest.string text) in
  Db.transaction db (fun () ->
      Db.exec db
        (Printf.sprintf
           "INSERT INTO graph_sources(context_id,source_kind,source_uri,content_digest,state,\
            provenance_json,refreshed_at) VALUES(%s,'text',%s,%s,'completed','{}',CURRENT_TIMESTAMP);"
           (sql_text graph.id) (sql_text source_uri) (sql_text content_digest));
      Db.exec db
        (Printf.sprintf
           "INSERT OR IGNORE INTO graph_statements\
            (context_id,source_id,ordinal,content,content_digest,metadata_json)\
            VALUES(%s,last_insert_rowid(),0,%s,%s,'{}');"
           (sql_text graph.id) (sql_text text) (sql_text content_digest)));
  digest

let load_graph db id =
  ensure_schema db;
  match
    Db.scalar db
      (Printf.sprintf
         "SELECT graph_json FROM graph_snapshots WHERE context_id=%s ORDER BY id DESC LIMIT 1;"
         (sql_text id))
  with
  | None -> None
  | Some encoded -> (
      try
        match Graph.of_yojson (Yojson.Safe.from_string encoded) with
        | Ok graph -> Some graph
        | Error _ -> None
      with Yojson.Json_error _ -> None)

let int_of_text value = try int_of_string value with _ -> 0

let context_of_row row =
  match split '\x1f' row with
  | [ id; title; kind; updated_at; node_count; edge_count ] ->
      Some
        {
          id;
          title;
          kind;
          updated_at;
          node_count = int_of_text node_count;
          edge_count = int_of_text edge_count;
        }
  | _ -> None

let list_contexts db =
  ensure_schema db;
  Db.rows db
    "SELECT id||char(31)||title||char(31)||kind||char(31)||updated_at||char(31)||\
     node_count||char(31)||edge_count FROM graph_contexts ORDER BY updated_at DESC,id;"
  |> List.filter_map context_of_row

let contexts_to_yojson contexts =
  `Assoc
    [
      ( "contexts",
        `List
          (List.map
             (fun (context : context) ->
               `Assoc
                 [
                   ("id", `String context.id);
                   ("title", `String context.title);
                   ("kind", `String context.kind);
                   ("updated_at", `String context.updated_at);
                   ("node_count", `Int context.node_count);
                   ("edge_count", `Int context.edge_count);
                 ])
             contexts) );
    ]

let supported_commands =
  [ "import"; "refresh"; "analyze"; "compare"; "export"; "generate" ]

let job_of_row row =
  match split '\x1f' row with
  | [ id; command; state; requested_by; role; attempts; max_attempts; inserted_at; updated_at; error; result ] ->
      Some
        {
          id = int_of_text id;
          command;
          state;
          requested_by;
          role;
          attempts = int_of_text attempts;
          max_attempts = int_of_text max_attempts;
          inserted_at;
          updated_at;
          error = if error = "" then None else Some error;
          result =
            if result = "" then None
            else
              (try Some (Yojson.Safe.from_string result)
               with Yojson.Json_error _ -> None);
        }
  | _ -> None

let get_job db id =
  if id < 1 then None
  else
    Db.rows db
      (Printf.sprintf
         "SELECT id||char(31)||command||char(31)||state||char(31)||requested_by||\
          char(31)||role||char(31)||attempts||char(31)||max_attempts||char(31)||\
          inserted_at||char(31)||updated_at||char(31)||COALESCE(error,'')||\
          char(31)||COALESCE(result_json,'')\
          FROM graph_jobs WHERE id=%d LIMIT 1;"
         id)
    |> function row :: _ -> job_of_row row | [] -> None

let enqueue db ~command ~args ~requested_by ~role ~idempotency_key =
  ensure_schema db;
  if not (List.mem command supported_commands) then Error "unsupported command"
  else if String.length requested_by = 0 || String.length requested_by > 256 then
    Error "invalid requester identity"
  else
    match args with
    | `Assoc _ ->
        let args_json = Yojson.Safe.to_string args in
        if String.length args_json > 1_048_576 then Error "command payload exceeds 1 MiB"
        else
          let key =
            match idempotency_key with
            | Some value when String.length value > 0 && String.length value <= 128 -> value
            | Some _ -> ""
            | None ->
                Digest.to_hex
                  (Digest.string
                     (command ^ "\x1f" ^ requested_by ^ "\x1f" ^ args_json))
          in
          if key = "" then Error "invalid idempotency key"
          else
            Db.transaction db (fun () ->
                Db.exec db
                  (Printf.sprintf
                     "INSERT OR IGNORE INTO graph_jobs\
                      (idempotency_key,command,args_json,requested_by,role,state)\
                      VALUES(%s,%s,%s,%s,%s,'available');"
                     (sql_text key) (sql_text command) (sql_text args_json)
                     (sql_text requested_by) (sql_text role));
                match
                  Db.scalar db
                    (Printf.sprintf
                       "SELECT id FROM graph_jobs WHERE idempotency_key=%s LIMIT 1;"
                       (sql_text key))
                with
                | Some id -> (
                    match get_job db (int_of_text id) with
                    | Some job -> Ok job
                    | None -> Error "job disappeared after admission")
                | None -> Error "job admission failed")
    | _ -> Error "command args must be a JSON object"

let job_to_yojson job =
  `Assoc
    [
      ("id", `Int job.id);
      ("command", `String job.command);
      ("state", `String job.state);
      ("requested_by", `String job.requested_by);
      ("role", `String job.role);
      ("attempts", `Int job.attempts);
      ("max_attempts", `Int job.max_attempts);
      ("inserted_at", `String job.inserted_at);
      ("updated_at", `String job.updated_at);
      ("error", match job.error with Some value -> `String value | None -> `Null);
      ("result", match job.result with Some value -> value | None -> `Null);
    ]

let claim_next db =
  ensure_schema db;
  let projection =
    "id||char(31)||command||char(31)||state||char(31)||requested_by||char(31)||\
     role||char(31)||attempts||char(31)||max_attempts||char(31)||inserted_at||\
     char(31)||updated_at||char(31)||COALESCE(error,'')||char(31)||\
     COALESCE(result_json,'')||char(31)||args_json"
  in
  match
    Db.rows db
      (Printf.sprintf
         {|UPDATE graph_jobs
            SET state='executing', attempts=attempts+1,
                updated_at=CURRENT_TIMESTAMP, error=NULL, result_json=NULL
          WHERE id=(SELECT id FROM graph_jobs
                    WHERE state IN ('available','retry')
                      AND scheduled_at<=CURRENT_TIMESTAMP
                    ORDER BY scheduled_at,id LIMIT 1)
          RETURNING %s;|}
         projection)
  with
  | [] -> None
  | row :: _ -> (
      match List.rev (split '\x1f' row) with
      | args_json :: reversed_job -> (
          let job_row = String.concat "\x1f" (List.rev reversed_job) in
          match job_of_row job_row with
          | None -> None
          | Some job ->
              let args =
                try Yojson.Safe.from_string args_json
                with Yojson.Json_error _ -> `Assoc []
              in
              Some { job; args })
      | [] -> None)

let finish_job db ~id outcome =
  if id < 1 then None
  else (
    (match outcome with
    | Ok result ->
        Db.exec db
          (Printf.sprintf
             {|UPDATE graph_jobs
                  SET state='completed', result_json=%s, error=NULL,
                      updated_at=CURRENT_TIMESTAMP
                WHERE id=%d AND state='executing';|}
             (sql_text (Yojson.Safe.to_string result)) id)
    | Error message ->
        Db.exec db
          (Printf.sprintf
             {|UPDATE graph_jobs
                  SET state=CASE WHEN attempts>=max_attempts THEN 'discarded' ELSE 'retry' END,
                      error=%s, result_json=NULL,
                      scheduled_at=datetime('now','+'||MIN(attempts,60)||' seconds'),
                      updated_at=CURRENT_TIMESTAMP
                WHERE id=%d AND state='executing';|}
             (sql_text message) id));
    get_job db id)

let recover_stale_jobs db =
  ensure_schema db;
  Db.transaction db (fun () ->
      Db.exec db
        "UPDATE graph_jobs SET state='retry',updated_at=CURRENT_TIMESTAMP,\
         scheduled_at=CURRENT_TIMESTAMP,error='recovered stale execution lease'\
         WHERE state='executing' AND updated_at < datetime('now','-5 minutes')\
         AND attempts < max_attempts;\
         UPDATE graph_jobs SET state='discarded',updated_at=CURRENT_TIMESTAMP,\
         error='attempt budget exhausted during recovery'\
         WHERE state='executing' AND updated_at < datetime('now','-5 minutes')\
         AND attempts >= max_attempts;";
      Option.value ~default:"0" (Db.scalar db "SELECT changes();") |> int_of_text)
