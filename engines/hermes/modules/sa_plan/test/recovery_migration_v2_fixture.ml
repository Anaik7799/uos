(* TEST-ONLY fixed migration interpreter. Never linked into production.
   Reuse reviewed v1 bounded I/O/conservation helpers, never its injected hooks.
   Cooperative owned paths, not retained-FD or authenticated resource proof. *)
module V1=Recovery_schema_migration
module V2=Recovery_schema_migration_v2
module F=Recovery_migration_v1_helpers
let require=F.require
let sha=F.sha
let sorted=List.sort compare
let expected=sorted(V2.schema@V2.receipt_schema)
let owned n=F.owned V1.Task_store n||String.starts_with~prefix:"control_"n
let core db=List.filter(fun(n,_)->not(owned n))(F.all_schema db)
let extension db=List.filter(fun(n,_)->owned n)(F.all_schema db)
let table="sa_plan_recovery_migration_receipt"
let old_rows db=
 if List.mem_assoc table(F.all_schema db)then
  F.stmt db("SELECT rowid,* FROM "^table^" ORDER BY rowid LIMIT 257")[](fun st->
   let rec loop n acc=match Sqlite3.step st with
   |Sqlite3.Rc.DONE->List.rev acc
   |Sqlite3.Rc.ROW when n<256->
     let row=Array.init(Sqlite3.column_count st)(fun i->let v=Sqlite3.column st i in
      (match v with Sqlite3.Data.TEXT s|Sqlite3.Data.BLOB s->require(String.length s<=16384)"OLD_RECEIPT_BOUND"|_->());v)in
     loop(n+1)(row::acc)
   |_->raise(F.Hold"OLD_RECEIPT_BOUND")in loop 0 [])
 else []
let previous_schema r db=sorted(core db@V2.predecessor_schema r.V2.predecessor)
let audit_core r db=
 require(F.schema_sha(previous_schema r db)=r.V2.base.before_schema_sha256)"PREDECESSOR_SCHEMA_CHANGED";
 require(F.scalar db"SELECT version FROM sa_plan_schema_meta WHERE singleton=1"=7L)"V7_REQUIRED"
let read_one db id=
 if List.mem_assoc table(F.all_schema db)then
 F.stmt db("SELECT CASE WHEN typeof(request_sha256)='text' THEN CAST(substr(CAST(request_sha256 AS BLOB),1,65) AS TEXT) ELSE NULL END,CASE WHEN typeof(request_json)='text' THEN CAST(substr(CAST(request_json AS BLOB),1,8193) AS TEXT) ELSE NULL END,CASE WHEN typeof(receipt_json)='text' THEN CAST(substr(CAST(receipt_json AS BLOB),1,8193) AS TEXT) ELSE NULL END FROM "^table^" WHERE migration_id=? LIMIT 2")[Sqlite3.Data.TEXT id](fun st->
  match Sqlite3.step st with
  |Sqlite3.Rc.DONE->None
  |Sqlite3.Rc.ROW->(match Sqlite3.column st 0,Sqlite3.column st 1,Sqlite3.column st 2 with
    |Sqlite3.Data.TEXT h,Sqlite3.Data.TEXT request,Sqlite3.Data.TEXT receipt when String.length h=64&&String.length request<=8192&&String.length receipt<=8192->
      require(Sqlite3.step st=Sqlite3.Rc.DONE)"DUPLICATE_ID";Some(h,request,receipt)
    |_->raise(F.Hold"RECEIPT_TYPE_BOUND"))
  |_->raise(F.Hold"RECEIPT_READ"))
 else None
let lookup db r=
 match read_one db r.V2.base.migration_id with
 |None->None
 |Some(h,bytes,receipt)->
  require(bytes=V2.request_bytes r&&h=sha bytes)"MIGRATION_ID_CONFLICT";
  let j=Yojson.Basic.from_string receipt in
  let open Yojson.Basic.Util in
  let fields=["domain";"migration_id";"request_sha256";"resource_id";"source_sha256";"before_schema_sha256";"installed_schema_sha256";"observed_utc_ns";"observed_mono_ns";"authority"]in
  require((match j with `Assoc xs->List.map fst xs=fields|_->false)
   &&Yojson.Basic.to_string j=receipt&&member"domain"j=`String"uos.recovery-schema-migration-receipt.v2"
   &&member"migration_id"j=`String r.base.migration_id
   &&member"request_sha256"j=`String h&&member"installed_schema_sha256"j=`String(F.schema_sha expected)
   &&member"source_sha256"j=`String r.base.source_sha256
   &&member"before_schema_sha256"j=`String r.base.before_schema_sha256
   &&member"resource_id"j=`String r.base.resource_id&&member"authority"j=`String"NONE")"RECEIPT_MISMATCH";
  let number key=let raw=to_string(member key j)in let n=Int64.of_string raw in require(Int64.to_string n=raw)"RECEIPT_CLOCK";n in
  let utc=number"observed_utc_ns"and mono=number"observed_mono_ns"in
  require(utc>0L&&utc<r.base.expires_utc_ns&&mono>0L&&mono<r.base.expires_mono_ns)"RECEIPT_CLOCK";
  Some j
let run_opened r readonly f=
 F.resource r.V2.base;
 let db=Sqlite3.db_open~mode:(if readonly then `READONLY else `NO_CREATE)~uri:false~mutex:`FULL r.base.database in
 let result=try
  Sqlite3.busy_timeout db 150;
  F.exec db(if readonly then"PRAGMA query_only=ON;PRAGMA trusted_schema=OFF"else"PRAGMA synchronous=FULL;PRAGMA trusted_schema=OFF");
  require(F.stmt db"PRAGMA journal_mode"[](fun st->require(Sqlite3.step st=Sqlite3.Rc.ROW)"WAL_REQUIRED";Sqlite3.column_text st 0)="wal")"WAL_REQUIRED";
  F.page_bound db;f db
 with e->Error(V1.Refused(F.exception_code e))in
 let closed=try let result=Sqlite3.db_close db in Core.Gc.keep_alive db;result with _->false in
 if not closed then Error V1.Commit_unknown else result
let execute r=match V2.validate r with Error e->Error e|Ok()->
 try run_opened r false(fun db->
  let active=ref false and committing=ref false in
  let previous=ref None in
  let fresh()=
   let now=F.fresh r.base in
   (match !previous with None->()|Some(old:Recovery_kernel.clock)->
    require(now.utc_ns>=old.utc_ns&&now.mono_ns>=old.mono_ns)"CLOCK_REGRESSION");
   previous:=Some now;now in
  try
   ignore(fresh());F.exec db"BEGIN IMMEDIATE";active:=true;
   let observed=fresh()in F.resource r.base;F.page_bound db;audit_core r db;
   let layout=extension db in
   if layout=expected then(match lookup db r with
    |Some receipt->F.exec db"COMMIT";active:=false;Ok(`Historical,receipt)
    |None->raise(F.Hold"V2_ALREADY_INSTALLED_WITH_OTHER_ID"))
   else(
    require(layout=sorted(V2.predecessor_schema r.predecessor))"PREDECESSOR_LAYOUT_MISMATCH";
    let before=F.data db V1.Task_store and receipts=old_rows db and old_core=core db in
    let names=List.map fst before in
    List.iter(fun(_,ddl)->F.exec db ddl)V2.resource_schema;
    if r.predecessor=V2.Legacy_six then List.iter(fun(_,ddl)->F.exec db ddl)V2.receipt_schema;
    require(extension db=expected&&core db=old_core)"SCHEMA_POSTGOAL";
    let receipt=`Assoc[
     "domain",`String"uos.recovery-schema-migration-receipt.v2";
     "migration_id",`String r.base.migration_id;
     "request_sha256",`String(sha(V2.request_bytes r));
     "resource_id",`String r.base.resource_id;
     "source_sha256",`String r.base.source_sha256;
     "before_schema_sha256",`String r.base.before_schema_sha256;
     "installed_schema_sha256",`String(F.schema_sha expected);
     "observed_utc_ns",`String(Int64.to_string observed.Recovery_kernel.utc_ns);
     "observed_mono_ns",`String(Int64.to_string observed.mono_ns);
     "authority",`String"NONE"]in
    let bytes=Yojson.Basic.to_string receipt in
    F.stmt db("INSERT INTO "^table^" VALUES(?,?,?,?)")
     [Sqlite3.Data.TEXT r.base.migration_id;Sqlite3.Data.TEXT(sha(V2.request_bytes r));Sqlite3.Data.TEXT(V2.request_bytes r);Sqlite3.Data.TEXT bytes]
     (fun st->require(Sqlite3.step st=Sqlite3.Rc.DONE)"RECEIPT_INSERT");
    ignore(fresh());F.resource r.base;F.page_bound db;audit_core r db;
    require(extension db=expected&&core db=old_core)"SCHEMA_POSTGOAL";
    let after=F.data db V1.Task_store in
    require(before=List.filter(fun(n,_)->List.mem n names)after&&List.for_all(fun(n,rows)->List.mem n names||rows=[])after)"DATA_POSTGOAL";
    let after_receipts=old_rows db in
    require(List.length after_receipts=List.length receipts+1&&List.for_all(fun row->List.mem row after_receipts)receipts)"OLD_RECEIPTS_CHANGED";
    require(lookup db r=Some receipt)"RECEIPT_READBACK";
    ignore(fresh());committing:=true;F.exec db"COMMIT";active:=false;
    require(extension db=expected&&lookup db r=Some receipt)"POSTCOMMIT_READBACK";
    Ok(`Installed,receipt))
  with e->
   if !committing then Error V1.Commit_unknown
   else if !active then
    (if (try Sqlite3.exec db"ROLLBACK"=Sqlite3.Rc.OK with _->false)
     then Error(V1.Refused(F.exception_code e))else Error V1.Commit_unknown)
   else Error(V1.Refused(F.exception_code e)))
 with e->Error(V1.Refused(F.exception_code e))
let reconcile r=match V2.validate r with Error e->Error e|Ok()->
 try run_opened r true(fun db->
  F.exec db"BEGIN";
  try audit_core r db;require(extension db=expected)"V2_LAYOUT_REQUIRED";
   let fact=lookup db r in F.exec db"COMMIT";Ok fact
  with e->ignore(Sqlite3.exec db"ROLLBACK");Error(V1.Refused(F.exception_code e)))
 with e->Error(V1.Refused(F.exception_code e))
