#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup,yojson,sqlite3,cryptokit";;

(* @agent_intent: Versioned product specifications and review artifacts in the
   existing UOS tracking database. This is catalog IO, never task authority.
   @laws: atomic import; identical replay is a no-op; conflicting replay fails;
   source presence and declared coverage never grant verification/admission. *)
open Yojson.Basic.Util
let fail message = failwith message
let require condition message = if not condition then fail message
let read path =
  require ((Unix.stat path).Unix.st_size <= 8 * 1024 * 1024) "input exceeds 8 MiB";
  match Bos.OS.File.read (Fpath.v path) with Ok s -> s | Error (`Msg e) -> fail e
let sha s = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) s
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let rec canonical = function
  | `Assoc xs ->
      require (List.length xs = List.length (List.sort_uniq String.compare (List.map fst xs)))
        "duplicate object key";
      `Assoc (List.map (fun (k,v) -> k,canonical v) xs |> List.sort compare)
  | `List xs -> `List (List.map canonical xs) | x -> x
let encoded j = Yojson.Basic.to_string (canonical j)
let text k j = member k j |> to_string
let items k j = member k j |> to_list
let nonempty k j = let s = text k j in require (String.trim s <> "") ("empty "^k); s
let check_hex s = String.length s = 64 && String.for_all (fun c ->
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) s
let rc db expected got = require (expected = got) (Sqlite3.errmsg db)
let exec db sql = rc db Sqlite3.Rc.OK (Sqlite3.exec db sql)
let query db sql values =
  let stmt = Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
    List.iteri (fun i v -> rc db Sqlite3.Rc.OK (Sqlite3.bind stmt (i+1) v)) values;
    let rec loop acc = match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW -> loop (Array.to_list (Sqlite3.row_data stmt)::acc)
      | Sqlite3.Rc.DONE -> List.rev acc | other -> rc db Sqlite3.Rc.DONE other; []
    in loop [])
let s x = Sqlite3.Data.TEXT x
let with_db ~readonly path f =
  require (Sys.file_exists path) "database must already exist";
  let db = if readonly then Sqlite3.db_open ~mode:`READONLY path else Sqlite3.db_open path in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () ->
    Sqlite3.busy_timeout db 3000;
    exec db "PRAGMA foreign_keys=ON";
    if readonly then exec db "PRAGMA query_only=ON";
    f db)

let schema = {|
CREATE TABLE IF NOT EXISTS product_catalog_schema(version INTEGER PRIMARY KEY CHECK(version=1));
INSERT INTO product_catalog_schema VALUES(1) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS product_artifacts(
  id TEXT NOT NULL, revision TEXT NOT NULL, kind TEXT NOT NULL, locator TEXT NOT NULL,
  sha256 TEXT NOT NULL CHECK(length(sha256)=64), content TEXT,
  payload TEXT NOT NULL CHECK(json_valid(payload)),
  PRIMARY KEY(id,revision));
CREATE TABLE IF NOT EXISTS product_specifications(
  id TEXT NOT NULL, revision TEXT NOT NULL, title TEXT NOT NULL, created_at TEXT NOT NULL,
  payload TEXT NOT NULL CHECK(json_valid(payload)), PRIMARY KEY(id,revision));
CREATE TABLE IF NOT EXISTS product_features(
  spec_id TEXT NOT NULL, revision TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL,
  category TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('MAPPED','PARTIAL','UNRUN','REVIEWED')),
  payload TEXT NOT NULL CHECK(json_valid(payload)), PRIMARY KEY(spec_id,revision,id),
  FOREIGN KEY(spec_id,revision) REFERENCES product_specifications(id,revision));
CREATE TABLE IF NOT EXISTS product_oracles(
  spec_id TEXT NOT NULL, revision TEXT NOT NULL, id TEXT NOT NULL,
  status TEXT NOT NULL, payload TEXT NOT NULL CHECK(json_valid(payload)),
  PRIMARY KEY(spec_id,revision,id),
  FOREIGN KEY(spec_id,revision) REFERENCES product_specifications(id,revision));
CREATE TABLE IF NOT EXISTS product_findings(
  spec_id TEXT NOT NULL, revision TEXT NOT NULL, id TEXT NOT NULL, severity TEXT NOT NULL,
  title TEXT NOT NULL, payload TEXT NOT NULL CHECK(json_valid(payload)),
  PRIMARY KEY(spec_id,revision,id),
  FOREIGN KEY(spec_id,revision) REFERENCES product_specifications(id,revision));
CREATE TABLE IF NOT EXISTS product_artifact_links(
  spec_id TEXT NOT NULL, revision TEXT NOT NULL, artifact_id TEXT NOT NULL,
  artifact_revision TEXT NOT NULL, role TEXT NOT NULL,
  PRIMARY KEY(spec_id,revision,artifact_id,artifact_revision,role),
  FOREIGN KEY(spec_id,revision) REFERENCES product_specifications(id,revision),
  FOREIGN KEY(artifact_id,artifact_revision) REFERENCES product_artifacts(id,revision));
CREATE TABLE IF NOT EXISTS product_imports(
  spec_id TEXT NOT NULL, revision TEXT NOT NULL, manifest_sha256 TEXT NOT NULL,
  manifest TEXT NOT NULL CHECK(json_valid(manifest)),
  PRIMARY KEY(spec_id,revision),
  FOREIGN KEY(spec_id,revision) REFERENCES product_specifications(id,revision));
CREATE VIEW IF NOT EXISTS product_requirement_list AS
 SELECT f.spec_id,f.revision,f.id AS feature_id,json_extract(r.value,'$.id') AS requirement_id,
 json_extract(r.value,'$.shall') AS requirement
 FROM product_features f,json_each(f.payload,'$.requirements') r;
CREATE VIEW IF NOT EXISTS product_acceptance_list AS
 SELECT f.spec_id,f.revision,f.id AS feature_id,json_extract(a.value,'$.id') AS case_id,
 json_extract(a.value,'$.assertion') AS assertion,json_extract(a.value,'$.status') AS status
 FROM product_features f,json_each(f.payload,'$.acceptance') a;
CREATE VIEW IF NOT EXISTS product_implementation_map AS
 SELECT f.spec_id,f.revision,f.id AS feature_id,json_extract(m.value,'$.path') AS path,
 json_extract(m.value,'$.sha256') AS sha256,json_extract(m.value,'$.status') AS status
 FROM product_features f,json_each(f.payload,'$.mappings') m;
CREATE VIEW IF NOT EXISTS product_feature_oracles AS
 SELECT f.spec_id,f.revision,f.id AS feature_id,o.value AS oracle_id
 FROM product_features f,json_each(f.payload,'$.oracle_ids') o;
CREATE VIEW IF NOT EXISTS product_detail_list AS
 SELECT f.spec_id,f.revision,f.id,f.name,f.category,f.status,
 json_extract(f.payload,'$.use_case') AS use_case,
 json_extract(f.payload,'$.gap') AS remaining_gap,
 json_extract(f.payload,'$.implementation') AS implementation,
 json_extract(f.payload,'$.sa_plan_task') AS sa_plan_task
 FROM product_features f;
|}

let protect_history db =
  List.iter (fun table -> List.iter (fun action ->
    exec db ("CREATE TRIGGER IF NOT EXISTS " ^ table ^ "_no_" ^ String.lowercase_ascii action ^
      " BEFORE " ^ action ^ " ON " ^ table ^
      " BEGIN SELECT RAISE(ABORT,'product catalog history is append-only'); END")) ["UPDATE";"DELETE"])
    ["product_artifacts";"product_specifications";"product_features";"product_oracles";
     "product_findings";"product_artifact_links";"product_imports"]

let unique label xs = require (List.length xs = List.length (List.sort_uniq String.compare xs))
  ("duplicate " ^ label)
let validate j =
  ignore (canonical j);
  require (text "schema" j = "uos.product-catalog/v1") "unsupported bundle schema";
  let spec = member "specification" j in
  List.iter (fun k -> ignore (nonempty k spec)) ["id";"revision";"title";"created_at";"sa_plan_plan"];
  require (text "admission_status" spec = "NOT_ADMITTED") "catalog cannot grant admission";
  let features = items "features" j and oracles = items "oracles" j and artifacts = items "artifacts" j in
  require (features <> [] && List.length features <= 1000) "feature count outside bounds";
  unique "feature" (List.map (text "id") features);
  unique "oracle" (List.map (text "id") oracles);
  unique "artifact" (List.map (text "id") artifacts);
  unique "finding" (List.map (text "id") (items "findings" j));
  let oracle_ids = List.map (text "id") oracles in
  List.iter (fun f ->
    List.iter (fun k -> ignore (nonempty k f)) ["id";"name";"category";"status";"use_case";"gap";"implementation"];
    require (List.mem (text "status" f) ["MAPPED";"PARTIAL";"UNRUN";"REVIEWED"])
      "feature state cannot claim runtime verification";
    require (items "requirements" f <> [] && items "acceptance" f <> []) "missing requirement/acceptance";
    List.iter (fun r -> ignore (nonempty "id" r); ignore (nonempty "shall" r)) (items "requirements" f);
    List.iter (fun a -> ignore (nonempty "id" a); ignore (nonempty "assertion" a);
      require (text "status" a = "UNRUN") "catalog acceptance definitions must remain UNRUN; use execution receipts")
      (items "acceptance" f);
    List.iter (fun id -> require (List.mem (to_string id) oracle_ids) "dangling oracle") (items "oracle_ids" f);
    List.iter (fun m ->
      let path = nonempty "path" m in
      if text "status" m = "SOURCE_PRESENT" then
        require (sha (read path) = text "sha256" m) ("mapping changed: " ^ path)) (items "mappings" f)
    ) features;
  unique "requirement" (List.concat_map (fun f -> List.map (text "id") (items "requirements" f)) features);
  unique "acceptance" (List.concat_map (fun f -> List.map (text "id") (items "acceptance" f)) features);
  List.iter (fun a ->
    List.iter (fun k -> ignore (nonempty k a)) ["id";"revision";"kind";"locator"];
    require (check_hex (text "sha256" a)) "invalid artifact hash";
    match member "content" a with
    | `String body -> require (sha body = text "sha256" a) "artifact body hash mismatch"
    | `Null -> () | _ -> fail "invalid artifact content") artifacts;
  let artifact_keys = List.map (fun a -> text "id" a,text "revision" a) artifacts in
  List.iter (fun l -> require (List.mem (text "artifact_id" l,text "artifact_revision" l) artifact_keys)
    "dangling artifact link") (items "artifact_links" j)

let transaction db f =
  exec db "BEGIN IMMEDIATE";
  try let value = f () in exec db "COMMIT"; value
  with exn -> exec db "ROLLBACK"; raise exn

let insert_once db ~table ~columns ~values ~keys ~key_values ~payload =
  let where = String.concat " AND " (List.map (fun k -> k ^ "=?") keys) in
  match query db ("SELECT payload FROM " ^ table ^ " WHERE " ^ where) key_values with
  | [[Sqlite3.Data.TEXT prior]] -> require (prior = payload) ("conflicting immutable " ^ table ^ " version")
  | [] -> ignore (query db ("INSERT INTO " ^ table ^ "(" ^ String.concat "," columns ^
      ") VALUES(" ^ String.concat "," (List.map (fun _ -> "?") columns) ^ ")") values)
  | _ -> fail "invalid stored product row"

let import db j ~authorize =
  validate j;
  let payload = encoded j and spec = member "specification" j in
  let id = text "id" spec and rev = text "revision" spec in
  transaction db (fun () ->
    authorize ();
    exec db schema;
    protect_history db;
    let prior = query db "SELECT manifest_sha256 FROM product_imports WHERE spec_id=? AND revision=?" [s id;s rev] in
    if prior <> [] then require (prior = [[s (sha payload)]]) "manifest revision already exists with different content";
    let put table cols values keys key_values row = insert_once db ~table ~columns:(cols@["payload"])
      ~values:(values@[s (encoded row)]) ~keys ~key_values ~payload:(encoded row) in
    List.iter (fun a -> put "product_artifacts" ["id";"revision";"kind";"locator";"sha256";"content"]
      [s (text "id" a);s (text "revision" a);s (text "kind" a);s (text "locator" a);s (text "sha256" a);
       (match member "content" a with `Null -> Sqlite3.Data.NULL | v -> s (to_string v))]
      ["id";"revision"] [s (text "id" a);s (text "revision" a)] a) (items "artifacts" j);
    put "product_specifications" ["id";"revision";"title";"created_at"]
      [s id;s rev;s (text "title" spec);s (text "created_at" spec)] ["id";"revision"] [s id;s rev] spec;
    List.iter (fun f -> put "product_features" ["spec_id";"revision";"id";"name";"category";"status"]
      [s id;s rev;s (text "id" f);s (text "name" f);s (text "category" f);s (text "status" f)]
      ["spec_id";"revision";"id"] [s id;s rev;s (text "id" f)] f) (items "features" j);
    List.iter (fun o -> put "product_oracles" ["spec_id";"revision";"id";"status"]
      [s id;s rev;s (text "id" o);s (text "status" o)]
      ["spec_id";"revision";"id"] [s id;s rev;s (text "id" o)] o) (items "oracles" j);
    List.iter (fun f -> put "product_findings" ["spec_id";"revision";"id";"severity";"title"]
      [s id;s rev;s (text "id" f);s (text "severity" f);s (text "title" f)]
      ["spec_id";"revision";"id"] [s id;s rev;s (text "id" f)] f) (items "findings" j);
    List.iter (fun l -> ignore (query db
      "INSERT INTO product_artifact_links VALUES(?,?,?,?,?) ON CONFLICT DO NOTHING"
      [s id;s rev;s (text "artifact_id" l);s (text "artifact_revision" l);s (text "role" l)])) (items "artifact_links" j);
    ignore (query db "INSERT INTO product_imports VALUES(?,?,?,?) ON CONFLICT DO NOTHING" [s id;s rev;s (sha payload);s payload]);
    require (query db "PRAGMA foreign_key_check" [] = []) "foreign-key violation";
    (* Covers cooperative in-flight ownership changes. Separate databases cannot
       supply an atomic scheduler/effect fence; no such claim is made here. *)
    authorize ())

let authorize () =
  let env name = match Sys.getenv_opt name with Some x when x <> "" -> x | _ -> fail ("missing "^name) in
  let plan = env "UOS_PRODUCT_PLAN" and task = env "UOS_PRODUCT_TASK" in
  let worker = env "UOS_PRODUCT_WORKER" and attempt = int_of_string (env "UOS_PRODUCT_ATTEMPT") in
  with_db ~readonly:true "var/sa-plan/uos.sqlite3" (fun db ->
    match query db "SELECT state,worker,attempt,lease_until_ns FROM sa_plan_task WHERE plan_id=? AND id=?" [s plan;s task] with
    | [[Sqlite3.Data.TEXT "executing";Sqlite3.Data.TEXT w;Sqlite3.Data.INT a;Sqlite3.Data.INT until]] ->
        require (w = worker && a = Int64.of_int attempt && Int64.to_float until > Unix.gettimeofday () *. 1e9)
          "Sa-plan ownership or lease mismatch"
    | _ -> fail "Sa-plan task is not currently owned")

let summary db =
  List.iter (fun table ->
    let rows = query db ("SELECT count(*) FROM " ^ table) [] in
    match rows with [[Sqlite3.Data.INT n]] -> Printf.printf "%s=%Ld\n" table n | _ -> fail "count failed")
    ["product_specifications";"product_features";"product_requirement_list";"product_acceptance_list";
     "product_oracles";"product_artifacts";"product_findings";"product_implementation_map"];
  require (query db "PRAGMA integrity_check" [] = [[s "ok"]]) "integrity check failed";
  print_endline "integrity=ok; catalog_only=true; production_admission=NOT_ADMITTED"

let run () = match Array.to_list Sys.argv with
  | [_;"check";manifest] -> validate (Yojson.Basic.from_string (read manifest)); print_endline "catalog manifest valid"
  | [_;"import";manifest] ->
      let j = Yojson.Basic.from_string (read manifest) in
      require (text "sa_plan_plan" (member "specification" j) = Option.value (Sys.getenv_opt "UOS_PRODUCT_PLAN") ~default:"")
        "bundle plan differs from current authority";
      with_db ~readonly:false "data/sqlite/uos_verification_tracking.sqlite3" (fun db -> import db j ~authorize; summary db)
  | [_;"summary"] -> with_db ~readonly:true "data/sqlite/uos_verification_tracking.sqlite3" summary
  | [_;"features"] -> with_db ~readonly:true "data/sqlite/uos_verification_tracking.sqlite3" (fun db ->
      query db "SELECT payload FROM product_features ORDER BY spec_id,revision,id" []
      |> List.iter (function [Sqlite3.Data.TEXT body] -> print_endline body | _ -> fail "bad feature"))
  | [_;"artifact";id] -> with_db ~readonly:true "data/sqlite/uos_verification_tracking.sqlite3" (fun db ->
      let rows = query db "SELECT content,sha256 FROM product_artifacts WHERE id=? ORDER BY revision" [s id] in
      require (rows <> []) "artifact not found";
      List.iter (function [Sqlite3.Data.TEXT body;Sqlite3.Data.TEXT digest] ->
        require (sha body = digest) "stored artifact digest mismatch"; print_endline body
        | [Sqlite3.Data.NULL;_] -> fail "external artifact is a reference only"
        | _ -> fail "invalid artifact") rows)
  | _ -> fail "usage: ocaml tools/product_catalog.ml {check MANIFEST|import MANIFEST|summary|features|artifact ID}"
let () = if not !Sys.interactive && Filename.basename Sys.argv.(0) = "product_catalog.ml" then
  try run () with exn -> prerr_endline ("product-catalog: " ^ Printexc.to_string exn); exit 1
