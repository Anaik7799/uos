(* DEVELOPMENT DATA interpretation, never a production trust constructor.
   The Store and VFS modules are library-private; only closed data operations
   below are exported. No signing key or arbitrary caller callback is accepted. *)
module S=Recovery_adapter_store
module W=Recovery_adapter_vfs
module C=Recovery_adapter_context
module K=Recovery_kernel
module R=Recovery_resource
type observation={reply:string;diagnostics:Yojson.Safe.t}
let need=C.need
let ok=C.ok
let text=C.text
let field=C.field
let response status code receipt=Yojson.Basic.to_string(`Assoc[
 "schema",`String"uos.recovery-adapter.factual.v1";
 "status",`String status;"code",`String code;"authority",`String"NONE";
 "application_admitted",`Bool false;"system_admitted",`Bool false;"receipt",receipt])
let private_directory dir=
 need(String.starts_with~prefix:"/tmp/uos-control-private-"dir&&Filename.dirname dir="/tmp"&&Unix.realpath dir=dir)"private synthetic namespace required";
 let st=Unix.lstat dir in
 need(st.Unix.st_kind=Unix.S_DIR&&st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_perm land 0o077=0)"private directory owner"
let private_database database=
 let dir=Filename.dirname database in private_directory dir;
 need(database=dir^"/tasks.sqlite3")"fixed private database basename";
 let st=Unix.lstat database in
 need(st.Unix.st_kind=Unix.S_REG&&st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_nlink=1&&st.Unix.st_perm land 0o077=0)"private database metadata"
let prepare_private_existing_v7 ~database=
 let open_requested=ref false in
 try private_database database;
 open_requested:=true;
 let store=ok(S.open_existing database)in
 let result=try S.prepare_additional_private store with _->Error S.Prepare_unknown in
 let closed=Fun.protect~finally:(fun()->Core.Gc.keep_alive store.S.db)(fun()->
  try Sqlite3.db_close store.S.db with _->false)in
 store.S.closed<-true;
 if not closed then Error"PREPARE_CLEANUP_UNKNOWN"else match result with
 |Error S.Prepare_unknown->Error"PREPARE_OUTCOME_UNKNOWN"
 |Error S.Prepare_refused->Error"PREPARE_REFUSED_AFTER_CONFIRMED_ROLLBACK"
 |Ok digest->Ok(Yojson.Basic.to_string(`Assoc[
  "schema",`String"uos.recovery-adapter.private-preparation.v1";
  "status",`String"PREPARED_DATA_ONLY";"authority",`String"NONE";
  "before_task_snapshot_sha256",`String digest;"after_task_snapshot_sha256",`String digest;
  "snapshot_scope",`String"FIXED_PLAN_BOUNDED_PROJECTION";
  "production_migration",`Bool false]))
 with _->Error(if !open_requested then"PREPARE_OUTCOME_UNKNOWN"else"PREPARE_PRIVATE_NAMESPACE_REFUSED")
let handle_private_data ~locator ~request=
 let bound_started=ref false in
 try
 need(String.length request>0&&String.length request<=65536)"frame bound";
 let dir=Filename.dirname locator in private_directory dir;
 need(locator=dir^"/locator.json")"fixed private locator";
 let l=Bounded.json_text(C.capture locator)in
 need(text l"domain"="PRIVATE_RECOVERY_CONTROL_FIXTURE")"development data domain";
 let database=text l"database"and journal=text l"journal"in
 private_database database;
 need(database=dir^"/tasks.sqlite3"&&journal=dir^"/owner.sqlite3"
  &&text l"kernel"=dir^"/kernel.json"&&text l"anchor"=dir^"/anchor.json"
  &&text l"portfolio"=dir^"/portfolio.json")"fixed private data namespace";
 let config=ok(K.read_pinned_data~path:(text l"kernel")~sha256:(text l"kernel_sha256"))in
 let anchor_bytes=C.capture(text l"anchor")in
 need(K.sha256 anchor_bytes=text l"anchor_sha256")"independently retained TEST anchor pin";
 let anchor=ok(R.anchor_data anchor_bytes)in
 let j=Bounded.json_text request in need(Yojson.Basic.to_string j=request)"canonical request";
 let fs=match j with `Assoc fs when List.map fst fs=["operation";"request";"capability";"reviewer_signature";"issuer_signature"]->fs|_->failwith"closed request"in
 let get k=Yojson.Basic.Util.to_string(List.assoc k fs)in
 let request_bytes=get"request"and capability_bytes=get"capability"and reviewer_signature=get"reviewer_signature"and issuer_signature=get"issuer_signature"in
 let history=get"operation"="inspect"in need(history||get"operation"="commit")"closed operation";
 let report_bytes=C.read(dir^"/checker.json")in
 let report=Bounded.json_text report_bytes and cap=Bounded.json_text capability_bytes in
 need(K.sha256 report_bytes=text cap"evidence_sha256"&&text cap"context_sha256"=text cap"evidence_sha256"
  &&text cap"evidence_sha256"=text l"checker_sha256")"signed resource/checker context";
 let physical=field report"physical_sqlite"in
 need(C.physical database=physical)"physical resources differ";
 let id role=let v=field physical role in W.{device=Int64.of_string(text v"device");inode=Int64.of_string(text v"inode")}in
 let expected=W.{main=id"main";wal=id"wal";shm=id"shm"}in
 (* Resource and full checker handles close BEFORE W.open_existing. No file
    descriptor to these inodes is closed inside the retained bound lifetime. *)
 let database_resource=ok(R.open_owned database)in
 Fun.protect~finally:(fun()->R.close database_resource)(fun()->
 let journal_resource=ok(R.open_owned journal)in
 Fun.protect~finally:(fun()->R.close journal_resource)(fun()->
 let resource_bytes=text l"resource"and resource_reviewer_signature=text l"resource_review"and resource_issuer_signature=text l"resource_issuer"in
 if history then(
  let e=ok(R.verify_history anchor~request_bytes~capability_bytes~reviewer_signature~issuer_signature~resource_bytes~resource_reviewer_signature~resource_issuer_signature)in
  ignore(ok(R.check_history_boundary e~database:database_resource~journal:journal_resource)))
 else(
  let e=ok(R.verify anchor~request_bytes~capability_bytes~reviewer_signature~issuer_signature~resource_bytes~resource_reviewer_signature~resource_issuer_signature)in
  ignore(ok(R.check_effect_boundary e~database:database_resource~journal:journal_resource)))));
 if not history then ignore(C.check_saved l request_bytes);
 let fresh=if history then None else Some(ok(K.verify config~request_bytes~capability_bytes~reviewer_signature~issuer_signature))in
 let historical=if history then Some(ok(K.verify_history config~request_bytes~capability_bytes~reviewer_signature~issuer_signature))else None in
 let cfg=Bounded.json_text(C.capture(text l"kernel"))and aj=Bounded.json_text anchor_bytes in
 (* This fixed-order canonical JSON is domain separated and every variable
    field is a fixed-width SHA256. Only these authenticated byte digests enter
    the resource receipt. Locator data cannot rename what signatures bound. *)
 let record_binding=Yojson.Basic.to_string(`Assoc[
  "domain",`String"uos.private-recovery-control-resource-receipt.v2";
  "request_sha256",`String(K.sha256 request_bytes);
  "capability_sha256",`String(K.sha256 capability_bytes);
  "resource_sha256",`String(K.sha256(text l"resource"));
  "anchor_sha256",`String(K.sha256 anchor_bytes);
  "checker_sha256",`String(K.sha256 report_bytes);
  "configuration_sha256",`String(K.configuration_sha256 config);
  "portfolio_sha256",`String(text cap"portfolio_sha256");
  "source_sha256",`String(text cfg"source_sha256");
  "worker_sha256",`String(text cfg"worker_sha256");
  "guardian_sha256",`String(text cfg"guardian_sha256");
  "launcher_sha256",`String(text aj"launcher_sha256");
  "owner_source_sha256",`String(text aj"owner_source_sha256");
  "journal_worker_sha256",`String(text aj"journal_worker_sha256");
  "vfs_source_manifest_sha256",`String(text report"vfs_source_manifest_sha256")])in
 need(text l"binding"=record_binding)"derived signed resource binding mismatch";
 let boundary()=try
  (match fresh with Some e->ignore(ok(K.still_valid e))|None->());C.source_boundary l;
  List.iter(fun(path,pin)->need(C.hash path=pin)"signed implementation/input changed")
   [text l"worker",text cfg"worker_sha256";text l"guardian",text cfg"guardian_sha256";
    text l"source_root"^"/engines/hermes/modules/sa_plan/sa_plan_store.ml",text cfg"source_sha256";
    text l"launcher",text aj"launcher_sha256";text l"journal_worker",text aj"journal_worker_sha256";
    text l"source_root"^"/apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_owner.gleam",text aj"owner_source_sha256"];
  Ok()with _->Error"signed source/clock boundary refused"in
 if not history then ignore(ok(boundary()));
 bound_started:=true;
 let session=match W.open_existing~directory:dir~basename:"tasks.sqlite3"~expected with
 |Ok x->x|Error e->failwith("BOUND_OPEN_"^W.error_label e)in
 let result=W.with_private_db session(fun db->
  let store=S.{db;closed=false;transaction_active=false;schema_version=7}in
  let outcome=if history then(
   try C.sql db"BEGIN";
    let result=S.control_history store(Option.get historical)~record_binding in
    (match result with
    |Ok receipt->C.sql db"COMMIT";Ok(response(match receipt with Some _->"HISTORICAL"|None->"HOLD")
     (match receipt with Some _->"COMMITTED_FACT_ONLY"|None->"ABSENT_RECONCILE_ONLY")(Option.value receipt~default:`Null))
    |Error _->if Sqlite3.exec db"ROLLBACK"=Sqlite3.Rc.OK then Ok(response"HOLD""HISTORY_MISMATCH"`Null)else Error"HISTORY_CLEANUP_UNKNOWN")
   with _->if Sqlite3.exec db"ROLLBACK"=Sqlite3.Rc.OK then Ok(response"HOLD""HISTORY_UNAVAILABLE"`Null)else Error"HISTORY_CLEANUP_UNKNOWN")
  else match S.control_execute store(Option.get fresh)~record_binding~boundary:(fun()->
   match boundary()with Error _ as e->e|Ok()->match W.snapshot session with
   |Ok observed when W.identities observed=expected->Ok()|_->Error"retained resource observation changed")with
  |Ok(S.Cap_committed r)->Ok(response"COMMITTED""COMMITTED_FACT"r)
  |Ok(S.Cap_historical r)->Ok(response"HISTORICAL""NO_NEW_PERMISSION"r)
  |Error S.Reclaim_unknown->Error"UNKNOWN"
  |Error(S.Reclaim_refused _)->Ok(response"HOLD""REFUSED_ROLLBACK"`Null)in
  if store.S.closed then W.Unknown else W.Known outcome)in
 let diagnostics=match W.snapshot session with Ok o->W.diagnostics o|_->`Null in
 let closed=W.close session in
 match result,closed with
 |Ok(Ok reply),Ok()->Ok{reply;diagnostics}
 |_->Ok{reply=response"UNKNOWN""BOUND_RECONCILE_ONLY"`Null;diagnostics}
 with _->if !bound_started then Ok{reply=response"UNKNOWN""BOUND_RECONCILE_ONLY"`Null;diagnostics=`Null}
  else Error"PRIVATE_ADAPTER_REFUSED"
