type t = { db : Sqlite3.db }

type feature = {
  snapshot_digest : string;
  id : string;
  label : string;
  source_domains : string list;
}

type feature_history = {
  snapshot_digest : string;
  feature_id : string;
  git_revision : string;
  phase : string;
  status : string;
  implementation_anchor : string;
  evidence_digest : string;
}

type fractal_node = {
  snapshot_digest : string;
  id : string;
  level : int;
  parent_id : string option;
  semantic_key : string;
  label : string;
  required : bool;
  status_policy : string;
}

type artifact = {
  snapshot_digest : string;
  id : string;
  kind : string;
  path : string;
  title : string;
  content_digest : string;
  git_revision : string;
}

type knowledge_link = {
  snapshot_digest : string;
  artifact_id : string;
  system : string;
  locator : string;
  relation : string;
  content_digest : string;
}

type git_commit = { revision : string; tree_digest : string; parent_revisions : string list; subject : string }
type node_revision = {
  snapshot_digest : string; node_id : string; git_revision : string; phase : string;
  strict_status : string; implementation_anchor : string; evidence_digest : string;
}

type contract = {
  snapshot_digest : string; id : string; node_id : string;
  interface_path : string; law : string;
}

type contract_receipt = {
  snapshot_digest : string; contract_id : string; harness_revision : string;
  verifier : string; interface_digest : string; verdict : string;
}

type scenario = {
  snapshot_digest : string; id : string; feature_id : string; contract_id : string;
  fixture_digest : string; reference_digest : string;
}

type paired_trace = {
  snapshot_digest : string; scenario_id : string; trace_id : string;
  reference_trace : string; candidate_trace : string; normalization_version : string;
}

type verification = {
  snapshot_digest : string; scenario_id : string; trace_id : string;
  verifier : string; harness_revision : string; check : string; passed : bool;
  evidence_digest : string;
}

let error db context rc =
  Error (Printf.sprintf "%s: %s: %s" context (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))

let exec db context sql =
  match Sqlite3.exec db sql with
  | rc when Sqlite3.Rc.is_success rc -> Ok ()
  | rc -> error db context rc

let with_statement db sql f =
  let statement = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize statement))
    (fun () -> f statement)

let bind_values db statement values =
  match Sqlite3.bind_values statement values with
  | rc when Sqlite3.Rc.is_success rc -> Ok ()
  | rc -> error db "bind values" rc

let step_done db context statement =
  match Sqlite3.step statement with
  | Sqlite3.Rc.DONE -> Ok ()
  | rc -> error db context rc

let with_transaction db f =
  match exec db "begin evidence transaction" "BEGIN IMMEDIATE" with
  | Error _ as error -> error
  | Ok () ->
      (match f () with
      | Ok () as success ->
          (match exec db "commit evidence transaction" "COMMIT" with
          | Ok () -> success
          | Error _ as error -> error)
      | Error _ as error ->
          ignore (Sqlite3.exec db "ROLLBACK");
          error)

(* Immutable evidence tables must never silently absorb a divergent payload.
   Every append-only insert first probes for a row that shares its key but
   differs in any other column, and fails closed when one exists. *)
let reject_divergent_replay store ~context ~sql values =
  with_statement store.db sql (fun check ->
      match bind_values store.db check values with
      | Error _ as error -> error
      | Ok () ->
          match Sqlite3.step check with
          | Sqlite3.Rc.ROW -> Error context
          | Sqlite3.Rc.DONE -> Ok ()
          | rc -> error store.db "check divergent replay" rc)

let insert_immutable store ~context ~conflict_context ~conflict_sql ~conflict_values ~insert_sql
    ~insert_values =
  match reject_divergent_replay store ~context:conflict_context ~sql:conflict_sql conflict_values with
  | Error _ as error -> error
  | Ok () ->
      with_statement store.db insert_sql (fun statement ->
          match bind_values store.db statement insert_values with
          | Error _ as error -> error
          | Ok () -> step_done store.db context statement)

let status_to_string = function
  | Core.Pending -> "pending"
  | Core.Passed -> "passed"
  | Core.Failed message -> "failed:" ^ message

let status_of_string = function
  | "pending" -> Core.Pending
  | "passed" -> Core.Passed
  | value when String.starts_with ~prefix:"failed:" value ->
      Core.Failed (String.sub value 7 (String.length value - 7))
  | value -> Core.Failed ("invalid stored status: " ^ value)

let schema =
  {|PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY
);
CREATE TABLE IF NOT EXISTS source_snapshot (
  id INTEGER PRIMARY KEY,
  digest TEXT NOT NULL,
  entry_count INTEGER NOT NULL CHECK(entry_count >= 0),
  recorded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS check_evidence (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  status TEXT NOT NULL,
  recorded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS capability_cell (
  snapshot_digest TEXT NOT NULL,
  domain TEXT NOT NULL,
  file_count INTEGER NOT NULL CHECK(file_count >= 0),
  domain_digest TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('unmapped', 'specified', 'implemented', 'verified', 'approved_divergence')),
  PRIMARY KEY(snapshot_digest, domain)
);
CREATE TABLE IF NOT EXISTS feature_catalog (
  snapshot_digest TEXT NOT NULL,
  id TEXT NOT NULL,
  label TEXT NOT NULL,
  source_domains TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, id)
);
CREATE TABLE IF NOT EXISTS feature_history (
  snapshot_digest TEXT NOT NULL,
  feature_id TEXT NOT NULL,
  git_revision TEXT NOT NULL,
  phase TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('unmapped', 'specified', 'implemented', 'verified', 'approved_divergence')),
  implementation_anchor TEXT NOT NULL,
  evidence_digest TEXT NOT NULL,
  recorded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(snapshot_digest, feature_id, git_revision, phase),
  FOREIGN KEY(snapshot_digest, feature_id) REFERENCES feature_catalog(snapshot_digest, id)
);
CREATE TABLE IF NOT EXISTS fractal_node (
  snapshot_digest TEXT NOT NULL,
  node_id TEXT NOT NULL,
  level INTEGER NOT NULL CHECK(level BETWEEN 0 AND 6),
  parent_node_id TEXT,
  semantic_key TEXT NOT NULL,
  label TEXT NOT NULL,
  required INTEGER NOT NULL CHECK(required IN (0, 1)),
  status_policy TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, node_id),
  UNIQUE(snapshot_digest, semantic_key),
  CHECK((level = 0 AND parent_node_id IS NULL) OR (level > 0 AND parent_node_id IS NOT NULL)),
  FOREIGN KEY(snapshot_digest, parent_node_id)
    REFERENCES fractal_node(snapshot_digest, node_id) DEFERRABLE INITIALLY DEFERRED
);
CREATE TABLE IF NOT EXISTS artifact_catalog (
  snapshot_digest TEXT NOT NULL,
  artifact_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('documentation','text','diagram','ui','design','video','image','audio','source','test','fixture','trace','build','report')),
  path TEXT NOT NULL,
  title TEXT NOT NULL,
  content_digest TEXT NOT NULL,
  git_revision TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, artifact_id)
);
CREATE TABLE IF NOT EXISTS node_artifact (
  snapshot_digest TEXT NOT NULL,
  node_id TEXT NOT NULL,
  artifact_id TEXT NOT NULL,
  role TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, node_id, artifact_id, role),
  FOREIGN KEY(snapshot_digest, node_id) REFERENCES fractal_node(snapshot_digest, node_id),
  FOREIGN KEY(snapshot_digest, artifact_id) REFERENCES artifact_catalog(snapshot_digest, artifact_id)
);
CREATE TABLE IF NOT EXISTS knowledge_link (
  snapshot_digest TEXT NOT NULL,
  artifact_id TEXT NOT NULL,
  system TEXT NOT NULL CHECK(system IN ('docs','wiki','zk')),
  locator TEXT NOT NULL,
  relation TEXT NOT NULL,
  content_digest TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, artifact_id, system, locator, relation),
  FOREIGN KEY(snapshot_digest, artifact_id) REFERENCES artifact_catalog(snapshot_digest, artifact_id)
);
CREATE TABLE IF NOT EXISTS git_commit (
  revision TEXT PRIMARY KEY, tree_digest TEXT NOT NULL, parent_revisions TEXT NOT NULL,
  subject TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS node_revision (
  snapshot_digest TEXT NOT NULL, node_id TEXT NOT NULL, git_revision TEXT NOT NULL,
  phase TEXT NOT NULL, strict_status TEXT NOT NULL, implementation_anchor TEXT NOT NULL,
  evidence_digest TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest,node_id,git_revision,phase),
  FOREIGN KEY(snapshot_digest,node_id) REFERENCES fractal_node(snapshot_digest,node_id),
  FOREIGN KEY(git_revision) REFERENCES git_commit(revision)
);
CREATE TABLE IF NOT EXISTS capability_contract (
  snapshot_digest TEXT NOT NULL,
  contract_id TEXT NOT NULL,
  node_id TEXT NOT NULL,
  interface_path TEXT NOT NULL,
  law TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, contract_id),
  FOREIGN KEY(snapshot_digest, node_id) REFERENCES fractal_node(snapshot_digest, node_id)
);
CREATE TABLE IF NOT EXISTS capability_contract_receipt (
  snapshot_digest TEXT NOT NULL,
  contract_id TEXT NOT NULL,
  harness_revision TEXT NOT NULL,
  verifier TEXT NOT NULL,
  interface_digest TEXT NOT NULL,
  verdict TEXT NOT NULL CHECK(verdict IN ('checked', 'rejected', 'unavailable')),
  PRIMARY KEY(snapshot_digest, contract_id, harness_revision, verifier),
  FOREIGN KEY(snapshot_digest, contract_id)
    REFERENCES capability_contract(snapshot_digest, contract_id)
);
CREATE TABLE IF NOT EXISTS parity_scenario (
  snapshot_digest TEXT NOT NULL, id TEXT NOT NULL, feature_id TEXT NOT NULL,
  contract_id TEXT NOT NULL, fixture_digest TEXT NOT NULL, reference_digest TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, id)
);
CREATE TABLE IF NOT EXISTS parity_trace_pair (
  snapshot_digest TEXT NOT NULL, scenario_id TEXT NOT NULL, trace_id TEXT NOT NULL,
  reference_trace TEXT NOT NULL, candidate_trace TEXT NOT NULL, normalization_version TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, scenario_id, trace_id),
  FOREIGN KEY(snapshot_digest, scenario_id) REFERENCES parity_scenario(snapshot_digest, id)
);
CREATE TABLE IF NOT EXISTS ruliad_evolution (
  snapshot_digest TEXT NOT NULL, harness_revision TEXT NOT NULL,
  satisfied TEXT NOT NULL, remaining_orders INTEGER NOT NULL,
  state_count INTEGER NOT NULL, confluent INTEGER NOT NULL CHECK(confluent IN (0, 1)),
  folded_verdict TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, harness_revision, satisfied)
);
CREATE TABLE IF NOT EXISTS parity_verification (
  snapshot_digest TEXT NOT NULL, scenario_id TEXT NOT NULL, trace_id TEXT NOT NULL,
  verifier TEXT NOT NULL, harness_revision TEXT NOT NULL, check_name TEXT NOT NULL,
  passed INTEGER NOT NULL CHECK(passed IN (0, 1)), evidence_digest TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, scenario_id, trace_id, verifier, harness_revision, check_name),
  FOREIGN KEY(snapshot_digest, scenario_id, trace_id)
    REFERENCES parity_trace_pair(snapshot_digest, scenario_id, trace_id)
);|}

let open_db ~path =
  try
    let db = Sqlite3.db_open path in
    match exec db "migrate evidence store" schema with
    | Ok () -> Ok { db }
    | Error _ as error ->
        ignore (Sqlite3.db_close db);
        error
  with exception_ -> Error (Printexc.to_string exception_)

let record_snapshot store ~digest ~entry_count =
  with_transaction store.db (fun () ->
      with_statement store.db
        "INSERT INTO source_snapshot(digest, entry_count) VALUES (?, ?)" (fun statement ->
          match
            bind_values store.db statement
              [ Sqlite3.Data.TEXT digest; Sqlite3.Data.INT (Int64.of_int entry_count) ]
          with
          | Error _ as error -> error
          | Ok () -> step_done store.db "record source snapshot" statement))

let record_check store ~name ~status =
  with_transaction store.db (fun () ->
      with_statement store.db
        "INSERT INTO check_evidence(name, status) VALUES (?, ?)" (fun statement ->
          match
            bind_values store.db statement
              [ Sqlite3.Data.TEXT name; Sqlite3.Data.TEXT (status_to_string status) ]
          with
          | Error _ as error -> error
          | Ok () -> step_done store.db "record check evidence" statement))

let latest_readiness store =
  let checks = ref [] in
  match
    Sqlite3.exec store.db
      ~cb:(fun row _ ->
        if Array.length row = 2 then
          match row.(0), row.(1) with
          | Some name, Some status -> checks := { Core.name; status = status_of_string status } :: !checks
          | _ -> ())
      "SELECT name, status FROM check_evidence \
       WHERE id IN (SELECT MAX(id) FROM check_evidence GROUP BY name) ORDER BY name"
  with
  | rc when Sqlite3.Rc.is_success rc -> Ok (Core.readiness !checks)
  | rc -> error store.db "read latest readiness" rc

let existing_cell_count store ~snapshot_digest =
  with_statement store.db
    "SELECT COUNT(*) FROM capability_cell WHERE snapshot_digest = ?" (fun statement ->
      match bind_values store.db statement [ Sqlite3.Data.TEXT snapshot_digest ] with
      | Error _ as error -> error
      | Ok () ->
          match Sqlite3.step statement with
          | Sqlite3.Rc.ROW ->
              (match Sqlite3.column statement 0 with
              | Sqlite3.Data.INT count -> Ok (Int64.to_int count)
              | _ -> Error "invalid capability cell count")
          | rc -> error store.db "count capability cells" rc)

let existing_cell store ~snapshot_digest ~domain =
  with_statement store.db
    "SELECT file_count, domain_digest FROM capability_cell \
     WHERE snapshot_digest = ? AND domain = ?" (fun statement ->
      match
        bind_values store.db statement
          [ Sqlite3.Data.TEXT snapshot_digest; Sqlite3.Data.TEXT domain ]
      with
      | Error _ as error -> error
      | Ok () ->
          match Sqlite3.step statement with
          | Sqlite3.Rc.DONE -> Ok None
          | Sqlite3.Rc.ROW ->
              (match Sqlite3.column statement 0, Sqlite3.column statement 1 with
              | Sqlite3.Data.INT count, Sqlite3.Data.TEXT digest ->
                  Ok (Some (Int64.to_int count, digest))
              | _ -> Error "invalid capability cell row")
          | rc -> error store.db "read capability cell" rc)

let compatible_manifest store ~snapshot_digest cells =
  match existing_cell_count store ~snapshot_digest with
  | Error _ as error -> error
  | Ok 0 -> Ok ()
  | Ok count when count <> List.length cells -> Error "snapshot manifest conflict: domain count changed"
  | Ok _ ->
      List.fold_left
        (fun result (cell : Inventory.domain_summary) ->
          match result with
          | Error _ -> result
          | Ok () ->
              (match existing_cell store ~snapshot_digest ~domain:cell.domain with
              | Ok (Some (file_count, digest))
                when file_count = cell.file_count && String.equal digest cell.digest -> Ok ()
              | Ok _ -> Error ("snapshot manifest conflict: " ^ cell.domain)
              | Error _ as error -> error))
        (Ok ()) cells

let record_cells store ~snapshot_digest cells =
  match compatible_manifest store ~snapshot_digest cells with
  | Error _ as error -> error
  | Ok () -> with_transaction store.db (fun () ->
      List.fold_left
        (fun result (cell : Inventory.domain_summary) ->
          match result with
          | Error _ -> result
          | Ok () ->
              with_statement store.db
                "INSERT INTO capability_cell(snapshot_digest, domain, file_count, domain_digest, status) \
                 VALUES (?, ?, ?, ?, 'unmapped') \
                 ON CONFLICT(snapshot_digest, domain) DO UPDATE SET \
                   file_count = excluded.file_count, domain_digest = excluded.domain_digest \
                 WHERE capability_cell.file_count = excluded.file_count \
                   AND capability_cell.domain_digest = excluded.domain_digest"
                (fun statement ->
                  match
                    bind_values store.db statement
                      [ Sqlite3.Data.TEXT snapshot_digest; Sqlite3.Data.TEXT cell.domain;
                        Sqlite3.Data.INT (Int64.of_int cell.file_count); Sqlite3.Data.TEXT cell.digest ]
                  with
                  | Error _ as error -> error
                  | Ok () -> step_done store.db "record capability cell" statement))
        (Ok ()) cells)

let cells store ~snapshot_digest =
  let rows = ref [] in
  with_statement store.db
    "SELECT domain, file_count, domain_digest, status FROM capability_cell \
     WHERE snapshot_digest = ? ORDER BY domain" (fun statement ->
      match bind_values store.db statement [ Sqlite3.Data.TEXT snapshot_digest ] with
      | Error _ as error -> error
      | Ok () ->
          let rec read () =
            match Sqlite3.step statement with
            | Sqlite3.Rc.ROW ->
                let value index =
                  match Sqlite3.column statement index with
                  | Sqlite3.Data.TEXT text -> text
                  | Sqlite3.Data.INT integer -> Int64.to_string integer
                  | _ -> ""
                in
                rows := (value 0, int_of_string (value 1), value 2, value 3) :: !rows;
                read ()
            | Sqlite3.Rc.DONE -> Ok (List.rev !rows)
            | rc -> error store.db "read capability cells" rc
          in
          read ())

let feature_separator = "\x1f"

let invalid_feature (feature : feature) =
  String.trim feature.snapshot_digest = "" || String.trim feature.id = ""
  || String.trim feature.label = ""
  || feature.source_domains = []
  || List.exists (fun domain -> String.trim domain = "") feature.source_domains

let encoded_domains domains = String.concat feature_separator domains

let decoded_domains encoded =
  if encoded = "" then [] else String.split_on_char feature_separator.[0] encoded

let existing_feature store ~snapshot_digest ~id =
  with_statement store.db
    "SELECT label, source_domains FROM feature_catalog WHERE snapshot_digest = ? AND id = ?"
    (fun statement ->
      match bind_values store.db statement [ Sqlite3.Data.TEXT snapshot_digest; Sqlite3.Data.TEXT id ] with
      | Error _ as error -> error
      | Ok () ->
          match Sqlite3.step statement with
          | Sqlite3.Rc.DONE -> Ok None
          | Sqlite3.Rc.ROW ->
              (match Sqlite3.column statement 0, Sqlite3.column statement 1 with
              | Sqlite3.Data.TEXT label, Sqlite3.Data.TEXT source_domains ->
                  Ok (Some (label, decoded_domains source_domains))
              | _ -> Error "invalid feature catalog row")
          | rc -> error store.db "read feature catalog row" rc)

let record_features store features =
  let rec validate seen = function
    | [] -> Ok ()
    | (feature : feature) :: rest ->
        if invalid_feature feature then Error ("invalid feature: " ^ feature.id)
        else if List.mem (feature.snapshot_digest, feature.id) seen then
          Error ("duplicate feature: " ^ feature.id)
        else validate ((feature.snapshot_digest, feature.id) :: seen) rest
  in
  match validate [] features with
  | Error _ as error -> error
  | Ok () ->
      with_transaction store.db (fun () ->
        List.fold_left
          (fun result (feature : feature) ->
            match result with
            | Error _ -> result
            | Ok () ->
                (match existing_feature store ~snapshot_digest:feature.snapshot_digest ~id:feature.id with
                | Error _ as error -> error
                | Ok (Some (label, domains))
                  when String.equal label feature.label && domains = feature.source_domains -> Ok ()
                | Ok (Some _) -> Error ("feature catalog conflict: " ^ feature.id)
                | Ok None ->
                    with_statement store.db
                      "INSERT INTO feature_catalog(snapshot_digest,id,label,source_domains) VALUES (?,?,?,?)"
                      (fun statement ->
                        match bind_values store.db statement
                          [ Sqlite3.Data.TEXT feature.snapshot_digest; Sqlite3.Data.TEXT feature.id;
                            Sqlite3.Data.TEXT feature.label;
                            Sqlite3.Data.TEXT (encoded_domains feature.source_domains) ] with
                        | Error _ as error -> error
                        | Ok () -> step_done store.db "record feature catalog row" statement)))
          (Ok ()) features)

let features store ~snapshot_digest =
  let rows = ref [] in
  with_statement store.db
    "SELECT id, label, source_domains FROM feature_catalog WHERE snapshot_digest = ? ORDER BY id"
    (fun statement ->
      match bind_values store.db statement [ Sqlite3.Data.TEXT snapshot_digest ] with
      | Error _ as error -> error
      | Ok () ->
          let rec read () =
            match Sqlite3.step statement with
            | Sqlite3.Rc.ROW ->
                (match Sqlite3.column statement 0, Sqlite3.column statement 1, Sqlite3.column statement 2 with
                | Sqlite3.Data.TEXT id, Sqlite3.Data.TEXT label, Sqlite3.Data.TEXT domains ->
                    rows := (id, label, decoded_domains domains) :: !rows
                | _ -> ());
                read ()
            | Sqlite3.Rc.DONE -> Ok (List.rev !rows)
            | rc -> error store.db "read feature catalog" rc
          in
          read ())

let invalid_feature_history (history : feature_history) =
  String.trim history.snapshot_digest = "" || String.trim history.feature_id = ""
  || String.trim history.git_revision = "" || String.trim history.phase = ""
  || String.trim history.implementation_anchor = ""
  || String.trim history.evidence_digest = ""
  || not (List.mem history.status
            [ "unmapped"; "specified"; "implemented"; "verified"; "approved_divergence" ])

let record_feature_history store (history : feature_history) =
  if invalid_feature_history history then Error ("invalid feature history: " ^ history.feature_id)
  else
    let values =
      [ Sqlite3.Data.TEXT history.snapshot_digest; Sqlite3.Data.TEXT history.feature_id;
        Sqlite3.Data.TEXT history.git_revision; Sqlite3.Data.TEXT history.phase;
        Sqlite3.Data.TEXT history.status; Sqlite3.Data.TEXT history.implementation_anchor;
        Sqlite3.Data.TEXT history.evidence_digest ]
    in
    with_transaction store.db (fun () ->
      insert_immutable store
        ~context:"record feature history"
        ~conflict_context:("feature history conflict: " ^ history.feature_id)
        ~conflict_sql:
          "SELECT 1 FROM feature_history WHERE snapshot_digest=? AND feature_id=? \
           AND git_revision=? AND phase=? \
           AND (status<>? OR implementation_anchor<>? OR evidence_digest<>?)"
        ~conflict_values:values
        ~insert_sql:
          "INSERT INTO feature_history(snapshot_digest,feature_id,git_revision,phase,status,implementation_anchor,evidence_digest) \
           VALUES (?,?,?,?,?,?,?) ON CONFLICT(snapshot_digest,feature_id,git_revision,phase) DO NOTHING"
        ~insert_values:values)

let feature_history store ~snapshot_digest ~feature_id =
  let rows = ref [] in
  with_statement store.db
    "SELECT git_revision, phase, status, implementation_anchor, evidence_digest \
     FROM feature_history WHERE snapshot_digest = ? AND feature_id = ? \
     ORDER BY recorded_at, git_revision, phase"
    (fun statement ->
      match bind_values store.db statement [ Sqlite3.Data.TEXT snapshot_digest; Sqlite3.Data.TEXT feature_id ] with
      | Error _ as error -> error
      | Ok () ->
          let rec read () =
            match Sqlite3.step statement with
            | Sqlite3.Rc.ROW ->
                (match Sqlite3.column statement 0, Sqlite3.column statement 1,
                       Sqlite3.column statement 2, Sqlite3.column statement 3,
                       Sqlite3.column statement 4 with
                | Sqlite3.Data.TEXT git_revision, Sqlite3.Data.TEXT phase,
                  Sqlite3.Data.TEXT status, Sqlite3.Data.TEXT implementation_anchor,
                  Sqlite3.Data.TEXT evidence_digest ->
                    rows := { snapshot_digest; feature_id; git_revision; phase; status;
                              implementation_anchor; evidence_digest } :: !rows
                | _ -> ());
                read ()
            | Sqlite3.Rc.DONE -> Ok (List.rev !rows)
            | rc -> error store.db "read feature history" rc
          in
          read ())

let valid_artifact_kind = function
  | "documentation" | "text" | "diagram" | "ui" | "design" | "video"
  | "image" | "audio" | "source" | "test" | "fixture" | "trace" | "build"
  | "report" -> true
  | _ -> false

let invalid_node (node : fractal_node) =
  String.trim node.snapshot_digest = "" || String.trim node.id = ""
  || node.level < 0 || node.level > 6 || String.trim node.semantic_key = ""
  || String.trim node.label = "" || String.trim node.status_policy = ""
  || (node.level = 0) <> Option.is_none node.parent_id

let record_fractal_nodes store nodes =
  if List.exists invalid_node nodes then Error "invalid fractal node"
  else with_transaction store.db (fun () ->
    List.fold_left
      (fun result (node : fractal_node) ->
        match result with
        | Error _ -> result
        | Ok () ->
            let parent =
              match node.parent_id with
              | None -> Sqlite3.Data.NULL
              | Some value -> Sqlite3.Data.TEXT value
            in
            let values =
              [ Sqlite3.Data.TEXT node.snapshot_digest; Sqlite3.Data.TEXT node.id;
                Sqlite3.Data.INT (Int64.of_int node.level); parent;
                Sqlite3.Data.TEXT node.semantic_key; Sqlite3.Data.TEXT node.label;
                Sqlite3.Data.INT (if node.required then 1L else 0L);
                Sqlite3.Data.TEXT node.status_policy ]
            in
            insert_immutable store
              ~context:"record fractal node"
              ~conflict_context:("fractal node conflict: " ^ node.id)
              ~conflict_sql:
                "SELECT 1 FROM fractal_node WHERE snapshot_digest=? AND node_id=? AND \
                 (level<>? OR COALESCE(parent_node_id,'')<>COALESCE(?, '') OR semantic_key<>? OR label<>? OR required<>? OR status_policy<>?)"
              ~conflict_values:values
              ~insert_sql:
                "INSERT INTO fractal_node(snapshot_digest,node_id,level,parent_node_id,semantic_key,label,required,status_policy) \
                 VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(snapshot_digest,node_id) DO NOTHING"
              ~insert_values:values)
      (Ok ()) nodes)

let invalid_artifact (artifact : artifact) =
  String.trim artifact.snapshot_digest = "" || String.trim artifact.id = ""
  || not (valid_artifact_kind artifact.kind) || String.trim artifact.path = ""
  || String.trim artifact.title = "" || String.trim artifact.content_digest = ""
  || String.trim artifact.git_revision = ""

let record_artifacts store artifacts =
  if List.exists invalid_artifact artifacts then Error "invalid artifact"
  else with_transaction store.db (fun () ->
    List.fold_left
      (fun result (artifact : artifact) ->
        match result with
        | Error _ -> result
        | Ok () ->
            let values =
              [ Sqlite3.Data.TEXT artifact.snapshot_digest; Sqlite3.Data.TEXT artifact.id;
                Sqlite3.Data.TEXT artifact.kind; Sqlite3.Data.TEXT artifact.path;
                Sqlite3.Data.TEXT artifact.title; Sqlite3.Data.TEXT artifact.content_digest;
                Sqlite3.Data.TEXT artifact.git_revision ]
            in
            insert_immutable store
              ~context:"record artifact"
              ~conflict_context:("artifact catalog conflict: " ^ artifact.id)
              ~conflict_sql:
                "SELECT 1 FROM artifact_catalog WHERE snapshot_digest=? AND artifact_id=? \
                 AND (kind<>? OR path<>? OR title<>? OR content_digest<>? OR git_revision<>?)"
              ~conflict_values:values
              ~insert_sql:
                "INSERT INTO artifact_catalog(snapshot_digest,artifact_id,kind,path,title,content_digest,git_revision) \
                 VALUES (?,?,?,?,?,?,?) ON CONFLICT(snapshot_digest,artifact_id) DO NOTHING"
              ~insert_values:values)
      (Ok ()) artifacts)

(* node_artifact carries no columns outside its primary key, so a replay can
   never differ from what is stored; DO NOTHING is safe here. *)
let link_node_artifacts store ~snapshot_digest links =
  if List.exists (fun (_, _, role) -> String.trim role = "") links then Error "blank artifact role"
  else with_transaction store.db (fun () ->
    List.fold_left
      (fun result (node_id, artifact_id, role) ->
        match result with
        | Error _ -> result
        | Ok () -> with_statement store.db
            "INSERT INTO node_artifact(snapshot_digest,node_id,artifact_id,role) VALUES (?,?,?,?) ON CONFLICT DO NOTHING"
            (fun statement -> match bind_values store.db statement
              [ Sqlite3.Data.TEXT snapshot_digest; Sqlite3.Data.TEXT node_id;
                Sqlite3.Data.TEXT artifact_id; Sqlite3.Data.TEXT role ] with
            | Error _ as error -> error | Ok () -> step_done store.db "link node artifact" statement))
      (Ok ()) links)

let link_node_artifact store ~snapshot_digest ~node_id ~artifact_id ~role =
  link_node_artifacts store ~snapshot_digest [ (node_id, artifact_id, role) ]

let node_artifacts store ~snapshot_digest ~node_id =
  let rows = ref [] in
  with_statement store.db
    "SELECT a.artifact_id,a.kind,a.path,a.title,a.content_digest,a.git_revision,n.role \
     FROM node_artifact n JOIN artifact_catalog a \
       ON a.snapshot_digest=n.snapshot_digest AND a.artifact_id=n.artifact_id \
     WHERE n.snapshot_digest=? AND n.node_id=? ORDER BY a.artifact_id,n.role"
    (fun statement -> match bind_values store.db statement
      [ Sqlite3.Data.TEXT snapshot_digest; Sqlite3.Data.TEXT node_id ] with
    | Error _ as error -> error
    | Ok () -> let rec read () = match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
          (match Sqlite3.column statement 0, Sqlite3.column statement 1,
                 Sqlite3.column statement 2, Sqlite3.column statement 3,
                 Sqlite3.column statement 4, Sqlite3.column statement 5,
                 Sqlite3.column statement 6 with
          | Sqlite3.Data.TEXT id, Sqlite3.Data.TEXT kind, Sqlite3.Data.TEXT path,
            Sqlite3.Data.TEXT title, Sqlite3.Data.TEXT content_digest,
            Sqlite3.Data.TEXT git_revision, Sqlite3.Data.TEXT role ->
              rows := ({ snapshot_digest; id; kind; path; title; content_digest; git_revision }, role) :: !rows
          | _ -> ()); read ()
      | Sqlite3.Rc.DONE -> Ok (List.rev !rows)
      | rc -> error store.db "read node artifacts" rc in read ())

let invalid_knowledge_link (link : knowledge_link) =
  String.trim link.snapshot_digest = "" || String.trim link.artifact_id = ""
  || not (List.mem link.system [ "docs"; "wiki"; "zk" ])
  || String.trim link.locator = "" || String.trim link.relation = ""
  || String.trim link.content_digest = ""

let record_knowledge_links store links =
  if List.exists invalid_knowledge_link links then Error "invalid knowledge link"
  else with_transaction store.db (fun () ->
    List.fold_left
      (fun result (link : knowledge_link) -> match result with
      | Error _ -> result
      | Ok () ->
          let values =
            [ Sqlite3.Data.TEXT link.snapshot_digest; Sqlite3.Data.TEXT link.artifact_id;
              Sqlite3.Data.TEXT link.system; Sqlite3.Data.TEXT link.locator;
              Sqlite3.Data.TEXT link.relation; Sqlite3.Data.TEXT link.content_digest ]
          in
          insert_immutable store
            ~context:"record knowledge link"
            ~conflict_context:("knowledge link conflict: " ^ link.artifact_id ^ "/" ^ link.locator)
            ~conflict_sql:
              "SELECT 1 FROM knowledge_link WHERE snapshot_digest=? AND artifact_id=? \
               AND system=? AND locator=? AND relation=? AND content_digest<>?"
            ~conflict_values:values
            ~insert_sql:
              "INSERT INTO knowledge_link(snapshot_digest,artifact_id,system,locator,relation,content_digest) \
               VALUES (?,?,?,?,?,?) ON CONFLICT DO NOTHING"
            ~insert_values:values)
      (Ok ()) links)

let artifact_knowledge_links store ~snapshot_digest ~artifact_id =
  let rows = ref [] in
  with_statement store.db
    "SELECT system,locator,relation,content_digest FROM knowledge_link \
     WHERE snapshot_digest=? AND artifact_id=? ORDER BY system,locator,relation"
    (fun statement -> match bind_values store.db statement
      [ Sqlite3.Data.TEXT snapshot_digest; Sqlite3.Data.TEXT artifact_id ] with
    | Error _ as error -> error
    | Ok () -> let rec read () = match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
          (match Sqlite3.column statement 0, Sqlite3.column statement 1,
                 Sqlite3.column statement 2, Sqlite3.column statement 3 with
          | Sqlite3.Data.TEXT system, Sqlite3.Data.TEXT locator,
            Sqlite3.Data.TEXT relation, Sqlite3.Data.TEXT content_digest ->
              rows := { snapshot_digest; artifact_id; system; locator; relation; content_digest } :: !rows
          | _ -> ()); read ()
      | Sqlite3.Rc.DONE -> Ok (List.rev !rows)
      | rc -> error store.db "read artifact knowledge links" rc in read ())

let commit_separator = "\x1f"
let record_git_commits store commits =
  with_transaction store.db (fun () -> List.fold_left (fun result (commit : git_commit) ->
    match result with Error _ -> result | Ok () ->
      let values =
        [ Sqlite3.Data.TEXT commit.revision; Sqlite3.Data.TEXT commit.tree_digest;
          Sqlite3.Data.TEXT (String.concat commit_separator commit.parent_revisions);
          Sqlite3.Data.TEXT commit.subject ]
      in
      insert_immutable store
        ~context:"record git commit"
        ~conflict_context:("git commit conflict: " ^ commit.revision)
        ~conflict_sql:
          "SELECT 1 FROM git_commit WHERE revision=? AND (tree_digest<>? OR parent_revisions<>? OR subject<>?)"
        ~conflict_values:values
        ~insert_sql:
          "INSERT INTO git_commit(revision,tree_digest,parent_revisions,subject) VALUES (?,?,?,?) ON CONFLICT(revision) DO NOTHING"
        ~insert_values:values) (Ok ()) commits)

let record_node_revisions store revisions =
  with_transaction store.db (fun () -> List.fold_left (fun result (revision : node_revision) ->
    match result with Error _ -> result | Ok () ->
      let values =
        [ Sqlite3.Data.TEXT revision.snapshot_digest; Sqlite3.Data.TEXT revision.node_id;
          Sqlite3.Data.TEXT revision.git_revision; Sqlite3.Data.TEXT revision.phase;
          Sqlite3.Data.TEXT revision.strict_status; Sqlite3.Data.TEXT revision.implementation_anchor;
          Sqlite3.Data.TEXT revision.evidence_digest ]
      in
      insert_immutable store
        ~context:"record node revision"
        ~conflict_context:("node revision conflict: " ^ revision.node_id)
        ~conflict_sql:
          "SELECT 1 FROM node_revision WHERE snapshot_digest=? AND node_id=? AND git_revision=? \
           AND phase=? AND (strict_status<>? OR implementation_anchor<>? OR evidence_digest<>?)"
        ~conflict_values:values
        ~insert_sql:
          "INSERT INTO node_revision(snapshot_digest,node_id,git_revision,phase,strict_status,implementation_anchor,evidence_digest) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"
        ~insert_values:values) (Ok ()) revisions)

let node_revisions store ~snapshot_digest ~node_id =
  let rows = ref [] in with_statement store.db
    "SELECT git_revision,phase,strict_status,implementation_anchor,evidence_digest FROM node_revision WHERE snapshot_digest=? AND node_id=? ORDER BY git_revision,phase"
    (fun statement -> match bind_values store.db statement [Sqlite3.Data.TEXT snapshot_digest; Sqlite3.Data.TEXT node_id] with
    | Error _ as error -> error | Ok () -> let rec read () = match Sqlite3.step statement with
      | Sqlite3.Rc.ROW -> (match Sqlite3.column statement 0,Sqlite3.column statement 1,Sqlite3.column statement 2,Sqlite3.column statement 3,Sqlite3.column statement 4 with
        | Sqlite3.Data.TEXT git_revision,Sqlite3.Data.TEXT phase,Sqlite3.Data.TEXT strict_status,Sqlite3.Data.TEXT implementation_anchor,Sqlite3.Data.TEXT evidence_digest ->
          rows := {snapshot_digest;node_id;git_revision;phase;strict_status;implementation_anchor;evidence_digest} :: !rows | _ -> ()); read ()
      | Sqlite3.Rc.DONE -> Ok (List.rev !rows) | rc -> error store.db "read node revisions" rc in read ())

(* An L3 contract declaration is stable for a snapshot; its check receipt is
   scoped to the harness revision and the verifier that produced it, so an
   "unavailable" observation and a later real check coexist as history rather
   than colliding. *)
let record_contracts store contracts =
  with_transaction store.db (fun () ->
    List.fold_left
      (fun result (contract : contract) ->
        match result with
        | Error _ -> result
        | Ok () ->
            let values =
              [ Sqlite3.Data.TEXT contract.snapshot_digest; Sqlite3.Data.TEXT contract.id;
                Sqlite3.Data.TEXT contract.node_id; Sqlite3.Data.TEXT contract.interface_path;
                Sqlite3.Data.TEXT contract.law ]
            in
            insert_immutable store
              ~context:"record capability contract"
              ~conflict_context:("capability contract conflict: " ^ contract.id)
              ~conflict_sql:
                "SELECT 1 FROM capability_contract WHERE snapshot_digest=? AND contract_id=? \
                 AND (node_id<>? OR interface_path<>? OR law<>?)"
              ~conflict_values:values
              ~insert_sql:
                "INSERT INTO capability_contract(snapshot_digest,contract_id,node_id,interface_path,law) \
                 VALUES (?,?,?,?,?) ON CONFLICT(snapshot_digest,contract_id) DO NOTHING"
              ~insert_values:values)
      (Ok ()) contracts)

let record_contract_receipts store receipts =
  with_transaction store.db (fun () ->
    List.fold_left
      (fun result (receipt : contract_receipt) ->
        match result with
        | Error _ -> result
        | Ok () ->
            if not (List.mem receipt.verdict [ "checked"; "rejected"; "unavailable" ]) then
              Error ("invalid contract verdict: " ^ receipt.verdict)
            else
              let values =
                [ Sqlite3.Data.TEXT receipt.snapshot_digest; Sqlite3.Data.TEXT receipt.contract_id;
                  Sqlite3.Data.TEXT receipt.harness_revision; Sqlite3.Data.TEXT receipt.verifier;
                  Sqlite3.Data.TEXT receipt.interface_digest; Sqlite3.Data.TEXT receipt.verdict ]
              in
              insert_immutable store
                ~context:"record capability contract receipt"
                ~conflict_context:("capability contract receipt conflict: " ^ receipt.contract_id)
                ~conflict_sql:
                  "SELECT 1 FROM capability_contract_receipt WHERE snapshot_digest=? \
                   AND contract_id=? AND harness_revision=? AND verifier=? \
                   AND (interface_digest<>? OR verdict<>?)"
                ~conflict_values:values
                ~insert_sql:
                  "INSERT INTO capability_contract_receipt(snapshot_digest,contract_id,harness_revision,verifier,interface_digest,verdict) \
                   VALUES (?,?,?,?,?,?) \
                   ON CONFLICT(snapshot_digest,contract_id,harness_revision,verifier) DO NOTHING"
                ~insert_values:values)
      (Ok ()) receipts)

(* Only a checked contract counts. Unavailable and rejected verdicts are
   recorded but never grant L3 credit. *)
let checked_contracts store ~snapshot_digest ~harness_revision =
  let values = ref [] in
  with_statement store.db
    "SELECT DISTINCT contract_id FROM capability_contract_receipt \
     WHERE snapshot_digest = ? AND harness_revision = ? AND verdict = 'checked' \
     ORDER BY contract_id"
    (fun statement ->
      match bind_values store.db statement
        [ Sqlite3.Data.TEXT snapshot_digest; Sqlite3.Data.TEXT harness_revision ] with
      | Error _ as error -> error
      | Ok () ->
          let rec read () = match Sqlite3.step statement with
            | Sqlite3.Rc.ROW ->
                (match Sqlite3.column statement 0 with
                | Sqlite3.Data.TEXT value -> values := value :: !values
                | _ -> ()); read ()
            | Sqlite3.Rc.DONE -> Ok (List.rev !values)
            | rc -> error store.db "read checked contracts" rc
          in read ())

let record_scenario store (scenario : scenario) =
  let values =
    [ Sqlite3.Data.TEXT scenario.snapshot_digest;
      Sqlite3.Data.TEXT scenario.id; Sqlite3.Data.TEXT scenario.feature_id;
      Sqlite3.Data.TEXT scenario.contract_id; Sqlite3.Data.TEXT scenario.fixture_digest;
      Sqlite3.Data.TEXT scenario.reference_digest ]
  in
  with_transaction store.db (fun () ->
    insert_immutable store
      ~context:"record parity scenario"
      ~conflict_context:("parity scenario conflict: " ^ scenario.id)
      ~conflict_sql:
        "SELECT 1 FROM parity_scenario WHERE snapshot_digest=? AND id=? \
         AND (feature_id<>? OR contract_id<>? OR fixture_digest<>? OR reference_digest<>?)"
      ~conflict_values:values
      ~insert_sql:
        "INSERT INTO parity_scenario(snapshot_digest,id,feature_id,contract_id,fixture_digest,reference_digest) \
         VALUES (?,?,?,?,?,?) ON CONFLICT(snapshot_digest,id) DO NOTHING"
      ~insert_values:values)

let record_paired_trace store (trace : paired_trace) =
  let values =
    [ Sqlite3.Data.TEXT trace.snapshot_digest;
      Sqlite3.Data.TEXT trace.scenario_id; Sqlite3.Data.TEXT trace.trace_id;
      Sqlite3.Data.TEXT trace.reference_trace; Sqlite3.Data.TEXT trace.candidate_trace;
      Sqlite3.Data.TEXT trace.normalization_version ]
  in
  with_transaction store.db (fun () ->
    insert_immutable store
      ~context:"record paired trace"
      ~conflict_context:("paired trace conflict: " ^ trace.scenario_id ^ "/" ^ trace.trace_id)
      ~conflict_sql:
        "SELECT 1 FROM parity_trace_pair WHERE snapshot_digest=? AND scenario_id=? AND trace_id=? \
         AND (reference_trace<>? OR candidate_trace<>? OR normalization_version<>?)"
      ~conflict_values:values
      ~insert_sql:
        "INSERT INTO parity_trace_pair(snapshot_digest,scenario_id,trace_id,reference_trace,candidate_trace,normalization_version) \
         VALUES (?,?,?,?,?,?) ON CONFLICT(snapshot_digest,scenario_id,trace_id) DO NOTHING"
      ~insert_values:values)

let record_verification store (verification : verification) =
  let values =
    [ Sqlite3.Data.TEXT verification.snapshot_digest;
      Sqlite3.Data.TEXT verification.scenario_id; Sqlite3.Data.TEXT verification.trace_id;
      Sqlite3.Data.TEXT verification.verifier; Sqlite3.Data.TEXT verification.harness_revision;
      Sqlite3.Data.TEXT verification.check; Sqlite3.Data.INT (if verification.passed then 1L else 0L);
      Sqlite3.Data.TEXT verification.evidence_digest ]
  in
  with_transaction store.db (fun () ->
    insert_immutable store
      ~context:"record parity verification"
      ~conflict_context:
        ("parity verification conflict: " ^ verification.scenario_id ^ "/" ^ verification.trace_id
         ^ "/" ^ verification.check)
      ~conflict_sql:
        "SELECT 1 FROM parity_verification WHERE snapshot_digest=? AND scenario_id=? AND trace_id=? \
         AND verifier=? AND harness_revision=? AND check_name=? \
         AND (passed<>? OR evidence_digest<>?)"
      ~conflict_values:values
      ~insert_sql:
        "INSERT INTO parity_verification(snapshot_digest,scenario_id,trace_id,verifier,harness_revision,check_name,passed,evidence_digest) \
         VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(snapshot_digest,scenario_id,trace_id,verifier,harness_revision,check_name) DO NOTHING"
      ~insert_values:values)

let verified_scenarios store ~snapshot_digest ~harness_revision =
  let values = ref [] in
  with_statement store.db
    "SELECT DISTINCT scenario_id FROM parity_verification \
     WHERE snapshot_digest = ? AND harness_revision = ? AND passed = 1 ORDER BY scenario_id"
    (fun statement ->
      match bind_values store.db statement [ Sqlite3.Data.TEXT snapshot_digest; Sqlite3.Data.TEXT harness_revision ] with
      | Error _ as error -> error
      | Ok () ->
          let rec read () = match Sqlite3.step statement with
            | Sqlite3.Rc.ROW ->
                (match Sqlite3.column statement 0 with Sqlite3.Data.TEXT value -> values := value :: !values | _ -> ()); read ()
            | Sqlite3.Rc.DONE -> Ok (List.rev !values)
            | rc -> error store.db "read verified scenarios" rc
          in read ())

(* ----------------------------------------------------- ruliad evolution *)

(* The system's trajectory through its own build space: one row per observed
   frontier state, append-only under the standard immutability guard (an
   identical replay is a no-op; a divergent payload for the same key is
   rejected). This is telemetry about the HARNESS's evolution, not parity
   evidence -- it grants nothing and is keyed by revision so history reads as a
   trajectory. *)
type evolution = {
  snapshot_digest : string;
  harness_revision : string;
  satisfied : string;        (* comma-joined sorted intent ids; "" = none *)
  remaining_orders : int;
  state_count : int;
  confluent : bool;
  folded_verdict : string;
}

let record_evolution store (e : evolution) =
  let values =
    [ Sqlite3.Data.TEXT e.snapshot_digest; Sqlite3.Data.TEXT e.harness_revision;
      Sqlite3.Data.TEXT e.satisfied; Sqlite3.Data.INT (Int64.of_int e.remaining_orders);
      Sqlite3.Data.INT (Int64.of_int e.state_count);
      Sqlite3.Data.INT (if e.confluent then 1L else 0L);
      Sqlite3.Data.TEXT e.folded_verdict ]
  in
  with_transaction store.db (fun () ->
    insert_immutable store ~context:"record ruliad evolution"
      ~conflict_context:("ruliad evolution conflict: " ^ e.harness_revision ^ "/" ^ e.satisfied)
      ~conflict_sql:
        "SELECT 1 FROM ruliad_evolution WHERE snapshot_digest=? AND harness_revision=? \
         AND satisfied=? AND (remaining_orders<>? OR state_count<>? OR confluent<>? OR \
         folded_verdict<>?)"
      ~conflict_values:values
      ~insert_sql:
        "INSERT INTO ruliad_evolution(snapshot_digest,harness_revision,satisfied,\
         remaining_orders,state_count,confluent,folded_verdict) VALUES (?,?,?,?,?,?,?) \
         ON CONFLICT(snapshot_digest,harness_revision,satisfied) DO NOTHING"
      ~insert_values:values)

let evolution_history store ~snapshot_digest =
  let rows = ref [] in
  with_statement store.db
    "SELECT harness_revision, satisfied, remaining_orders, state_count, confluent, \
     folded_verdict FROM ruliad_evolution WHERE snapshot_digest = ? ORDER BY rowid"
    (fun statement ->
      match bind_values store.db statement [ Sqlite3.Data.TEXT snapshot_digest ] with
      | Error _ as error -> error
      | Ok () ->
          let rec read () = match Sqlite3.step statement with
            | Sqlite3.Rc.ROW ->
                (match
                   ( Sqlite3.column statement 0, Sqlite3.column statement 1,
                     Sqlite3.column statement 2, Sqlite3.column statement 3,
                     Sqlite3.column statement 4, Sqlite3.column statement 5 )
                 with
                | Sqlite3.Data.TEXT harness_revision, Sqlite3.Data.TEXT satisfied,
                  Sqlite3.Data.INT remaining_orders, Sqlite3.Data.INT state_count,
                  Sqlite3.Data.INT confluent, Sqlite3.Data.TEXT folded_verdict ->
                    rows :=
                      { snapshot_digest; harness_revision; satisfied;
                        remaining_orders = Int64.to_int remaining_orders;
                        state_count = Int64.to_int state_count;
                        confluent = confluent = 1L; folded_verdict }
                      :: !rows
                | _ -> ());
                read ()
            | Sqlite3.Rc.DONE -> Ok (List.rev !rows)
            | rc -> error store.db "read ruliad evolution" rc
          in read ())

(* The latest recorded verdict per scenario, with the contract it belongs to --
   the read the declarative-intent layer reconciles against. "Latest" is the
   most recently inserted verification for the scenario (rowid order): the
   candidate evolves, so a scenario re-verified at a newer harness revision
   supersedes the older receipt without erasing it (the store stays append-only). *)
let parity_results store ~snapshot_digest =
  let rows = ref [] in
  with_statement store.db
    "SELECT s.contract_id, v.passed FROM parity_verification v \
     JOIN parity_scenario s ON s.snapshot_digest = v.snapshot_digest AND s.id = v.scenario_id \
     WHERE v.snapshot_digest = ? AND v.rowid = \
       (SELECT MAX(v2.rowid) FROM parity_verification v2 \
        WHERE v2.snapshot_digest = v.snapshot_digest AND v2.scenario_id = v.scenario_id) \
     ORDER BY s.contract_id, s.id"
    (fun statement ->
      match bind_values store.db statement [ Sqlite3.Data.TEXT snapshot_digest ] with
      | Error _ as error -> error
      | Ok () ->
          let rec read () = match Sqlite3.step statement with
            | Sqlite3.Rc.ROW ->
                (match (Sqlite3.column statement 0, Sqlite3.column statement 1) with
                | Sqlite3.Data.TEXT contract, Sqlite3.Data.INT passed ->
                    rows := (contract, passed = 1L) :: !rows
                | _ -> ());
                read ()
            | Sqlite3.Rc.DONE -> Ok (List.rev !rows)
            | rc -> error store.db "read parity results" rc
          in read ())

(* Full chronological receipt history -- (contract_id, scenario_id, passed) in
   insertion order. Unlike [parity_results] this does NOT collapse to
   latest-per-scenario: the control plane's regression and flap sensors read
   the whole trajectory (append-only supersession preserved it for exactly
   this). *)
let parity_history store ~snapshot_digest =
  let rows = ref [] in
  with_statement store.db
    "SELECT s.contract_id, v.scenario_id, v.passed FROM parity_verification v \
     JOIN parity_scenario s ON s.snapshot_digest = v.snapshot_digest AND s.id = v.scenario_id \
     WHERE v.snapshot_digest = ? ORDER BY v.rowid"
    (fun statement ->
      match bind_values store.db statement [ Sqlite3.Data.TEXT snapshot_digest ] with
      | Error _ as error -> error
      | Ok () ->
          let rec read () = match Sqlite3.step statement with
            | Sqlite3.Rc.ROW ->
                (match
                   ( Sqlite3.column statement 0, Sqlite3.column statement 1,
                     Sqlite3.column statement 2 )
                 with
                | Sqlite3.Data.TEXT contract, Sqlite3.Data.TEXT scenario, Sqlite3.Data.INT passed
                  ->
                    rows := (contract, scenario, passed = 1L) :: !rows
                | _ -> ());
                read ()
            | Sqlite3.Rc.DONE -> Ok (List.rev !rows)
            | rc -> error store.db "read parity history" rc
          in read ())

(* The harness revision of the most recent receipt at this snapshot -- the
   control plane's receipt-currency (staleness lead-time) input. *)
let latest_receipt_revision store ~snapshot_digest =
  with_statement store.db
    "SELECT harness_revision FROM parity_verification WHERE snapshot_digest = ? \
     ORDER BY rowid DESC LIMIT 1"
    (fun statement ->
      match bind_values store.db statement [ Sqlite3.Data.TEXT snapshot_digest ] with
      | Error _ as error -> error
      | Ok () -> (
          match Sqlite3.step statement with
          | Sqlite3.Rc.ROW ->
              (match Sqlite3.column statement 0 with
              | Sqlite3.Data.TEXT revision -> Ok (Some revision)
              | _ -> Ok None)
          | Sqlite3.Rc.DONE -> Ok None
          | rc -> error store.db "read latest receipt revision" rc))

(* The most recently recorded frozen-source snapshot digest. Lets read-only
   report surfaces key their store reads without re-scanning the frozen tree
   (the scan costs seconds; the pin is already in the store). *)
let latest_snapshot store =
  with_statement store.db
    "SELECT digest FROM source_snapshot ORDER BY rowid DESC LIMIT 1"
    (fun statement ->
      match Sqlite3.step statement with
      | Sqlite3.Rc.ROW ->
          (match Sqlite3.column statement 0 with
          | Sqlite3.Data.TEXT digest -> Ok (Some digest)
          | _ -> Ok None)
      | Sqlite3.Rc.DONE -> Ok None
      | rc -> error store.db "read latest snapshot" rc)

let close store = ignore (Sqlite3.db_close store.db)
