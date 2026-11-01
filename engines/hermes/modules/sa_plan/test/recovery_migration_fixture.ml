(* TEST-ONLY SQLite interpreter. Never linked into a production library/port.
   Public DATA + filesystem identity are NOT authenticated migration authority.
   Task DB and owner journal migrate in DISTINCT transactions. No global atomic
   upgrade, hostile same-UID FS guarantee, power-loss proof or time-sync proof. *)
open Recovery_schema_migration
module S=Recovery_kernel_fixture
type stage = After_ddl | Before_final_checks | After_commit
exception Hold of string
let require b code=if not b then raise(Hold code)
let get=function Ok v->v|Error _->raise(Hold"STORE_UNAVAILABLE")
let sha s=Digestif.SHA256.(to_hex(digest_string s))
let close db=Fun.protect ~finally:(fun()->Core.Gc.keep_alive db)(fun()->ignore(Sqlite3.db_close db))
let stmt db sql values f=
 Fun.protect ~finally:(fun()->Core.Gc.keep_alive db)(fun()->
  let st=Sqlite3.prepare db sql in Fun.protect
   ~finally:(fun()->Fun.protect ~finally:(fun()->Core.Gc.keep_alive st)(fun()->ignore(Sqlite3.finalize st)))
   (fun()->require(Sqlite3.bind_values st values=Sqlite3.Rc.OK)"SQL_BIND";f st))
let exec db sql=require(Sqlite3.exec db sql=Sqlite3.Rc.OK)"SQL_FAILURE"
let scalar db sql=stmt db sql[](fun st->
 require(Sqlite3.step st=Sqlite3.Rc.ROW)"SQL_SCALAR";
 match Sqlite3.column st 0 with Sqlite3.Data.INT n->n|_->raise(Hold"SQL_INTEGER"))
let lexical s=String.length s>0&&String.length s<=200&&String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'_'->true|_->false)s
let ident s=require(lexical s)"SCHEMA_IDENTIFIER";"\""^s^"\""
let all_schema db=
 stmt db "SELECT CAST(substr(CAST(name AS BLOB),1,201) AS TEXT),CAST(substr(CAST(sql AS BLOB),1,8193) AS TEXT) FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' ORDER BY name LIMIT 129"[](fun st->
  let rec walk n acc=match Sqlite3.step st with
  |Sqlite3.Rc.DONE->List.rev acc
  |Sqlite3.Rc.ROW when n<128->(match Sqlite3.column st 0,Sqlite3.column st 1 with
    |Sqlite3.Data.TEXT name,Sqlite3.Data.TEXT sql when lexical name&&String.length sql<=8192&&not(String.contains sql '\000')->walk(n+1)((name,sql)::acc)
    |_->raise(Hold"SCHEMA_BOUND"))
  |_->raise(Hold"SCHEMA_BOUND")in walk 0 [])
let owned target name=
 let prefix p=String.starts_with ~prefix:p name in
 match target with
 |Task_store->prefix"sa_plan_reclaim_"||prefix"sa_plan_recovery_cap_"||prefix"sa_plan_recovery_migration_"
 |Owner_journal->prefix"recovery_owner_"||prefix"recovery_migration_"
let core_schema db target=List.filter(fun(n,_)->not(owned target n))(all_schema db)
let schema_sha pairs=sha(Yojson.Basic.to_string(`List(List.map(fun(n,s)->`List[`String n;`String s])pairs)))
let core_schema_sha db target=schema_sha(core_schema db target)
let expected target=List.sort compare(schema target@receipt_schema target)
let layout db target=
 let current=List.filter(fun(n,_)->owned target n)(all_schema db)in
 if current=[]then `Absent
 else if current=List.sort compare(schema target)then `Legacy_complete
 else if current=expected target then `Current
 else raise(Hold"RECOVERY_SCHEMA_MISMATCH")
let page_bound db=
 let pages=scalar db"PRAGMA page_count"and size=scalar db"PRAGMA page_size"in
 require(pages>=0L&&size>0L&&size<=65536L&&pages<=Int64.div 33554432L size)"DATABASE_QUOTA"
let file_identity path=
 let st=Unix.lstat path in require(st.Unix.st_kind=Unix.S_REG&&st.st_uid=Unix.geteuid()&&st.st_nlink=1&&st.st_perm land 0o077=0&&st.st_size<=33554432)"PRIVATE_RESOURCE_REQUIRED";st
let resource r=
 require(Unix.realpath r.database=r.database)"RESOURCE_ALIAS";
 let st=file_identity r.database in
 require(st.st_dev=r.device&&st.st_ino=r.inode)"RESOURCE_IDENTITY_MISMATCH";
 List.iter(fun suffix->let p=r.database^suffix in
  try ignore(file_identity p)with Unix.Unix_error(Unix.ENOENT,_,_)->())["-wal";"-shm"]
let fresh r=
 let c=get(Recovery_kernel.native_clock())in
 require(c.utc_ns<r.expires_utc_ns&&c.mono_ns<r.expires_mono_ns)"MIGRATION_EXPIRED";
 require(Int64.sub r.expires_utc_ns c.utc_ns<=3600000000000L&&Int64.sub r.expires_mono_ns c.mono_ns<=3600000000000L)"WINDOW_BOUND";c
let table target=match target with Task_store->"sa_plan_recovery_migration_receipt"|Owner_journal->"recovery_migration_receipt"
let lookup db r=
 stmt db("SELECT CASE WHEN typeof(request_sha256)='text' THEN CAST(substr(CAST(request_sha256 AS BLOB),1,65) AS TEXT) ELSE NULL END,CASE WHEN typeof(request_json)='text' THEN CAST(substr(CAST(request_json AS BLOB),1,8193) AS TEXT) ELSE NULL END,CASE WHEN typeof(receipt_json)='text' THEN CAST(substr(CAST(receipt_json AS BLOB),1,4097) AS TEXT) ELSE NULL END FROM "^table r.target^" WHERE migration_id=? LIMIT 2")[Sqlite3.Data.TEXT r.migration_id](fun st->
 match Sqlite3.step st with
 |Sqlite3.Rc.DONE->None
 |Sqlite3.Rc.ROW->(match Sqlite3.column st 0,Sqlite3.column st 1,Sqlite3.column st 2 with
  |Sqlite3.Data.TEXT digest,Sqlite3.Data.TEXT bytes,Sqlite3.Data.TEXT receipt when String.length receipt<=4096&&bytes=request_bytes r&&digest=sha bytes->
   let j=Yojson.Basic.from_string receipt in
   let expected_keys=["domain";"migration_id";"resource_id";"request_sha256";"source_sha256";"before_schema_sha256";"installed_schema_sha256";"observed_utc_ns";"observed_mono_ns";"preserved_tables";"authority"]in
   let open Yojson.Basic.Util in
   require((match j with `Assoc fs->List.map fst fs=expected_keys|_->false)&&Yojson.Basic.to_string j=receipt
    &&member"domain"j=`String"uos.recovery-schema-migration-receipt.v1"&&member"migration_id"j=`String r.migration_id
    &&member"resource_id"j=`String r.resource_id&&member"request_sha256"j=`String digest&&member"source_sha256"j=`String r.source_sha256
    &&member"before_schema_sha256"j=`String r.before_schema_sha256&&member"installed_schema_sha256"j=`String(schema_sha(expected r.target))
    &&member"authority"j=`String"NONE")"CORRUPT_RECEIPT";
   let utc=Int64.of_string(to_string(member"observed_utc_ns"j))and mono=Int64.of_string(to_string(member"observed_mono_ns"j))in
   let count=to_int(member"preserved_tables"j)in
   require(utc>0L&&utc<r.expires_utc_ns&&mono>0L&&mono<r.expires_mono_ns&&count>=0&&count<=64)"CORRUPT_RECEIPT";
   require(Sqlite3.step st=Sqlite3.Rc.DONE)"DUPLICATE_RECEIPT";Some j
  |_->raise(Hold"MIGRATION_ID_CONFLICT"))
 |_->raise(Hold"RECEIPT_READ_FAILED"))
(* Conservation oracle: typed full values remain private memory, never emitted,
   logged or hashed as public evidence. This includes results, sqlite_sequence,
   previous factual/capability receipts and all non-target tables. Bounds below
   constrain returned allocations, not SQLite C-query scheduling/CPU. *)
let data db target=
 let names=stmt db"SELECT CAST(substr(CAST(name AS BLOB),1,201) AS TEXT) FROM sqlite_schema WHERE type='table' ORDER BY name LIMIT 65"[](fun st->
  let rec walk acc=match Sqlite3.step st with
  |Sqlite3.Rc.DONE->List.rev acc
  |Sqlite3.Rc.ROW when List.length acc<64->(match Sqlite3.column st 0 with Sqlite3.Data.TEXT n->ignore(ident n);walk(n::acc)|_->raise(Hold"TABLE_NAME"))
  |_->raise(Hold"TABLE_BOUND")in walk [])in
 let count=ref 0 and bytes=ref 0 in
 List.filter_map(fun name->if name=table target then None else
 let rows=stmt db("SELECT rowid,* FROM "^ident name^" ORDER BY rowid LIMIT 20001")[](fun st->
  let rec walk acc=match Sqlite3.step st with
  |Sqlite3.Rc.DONE->List.rev acc
  |Sqlite3.Rc.ROW->incr count;require(!count<=20000)"ROW_BOUND";
   let row=Array.init(Sqlite3.column_count st)(fun i->let v=Sqlite3.column st i in
    bytes:= !bytes+(match v with Sqlite3.Data.TEXT s|Sqlite3.Data.BLOB s->String.length s|_->8);
    require(!bytes<=16777216)"PRESERVATION_BYTES_BOUND";v)in walk(row::acc)
  |_->raise(Hold"PRESERVATION_READ")in walk [])in Some(name,rows))names
let equal_data a b=a=b
let audit db r=
 (match r.target with Task_store->require(get(S.read_schema_version db)=7)"V7_REQUIRED";ignore(get(S.audit_v7_shape db))|Owner_journal->());
 require(core_schema_sha db r.target=r.before_schema_sha256)"CORE_SCHEMA_CHANGED";
 (match r.target with Owner_journal->require(core_schema db r.target=[])"JOURNAL_RESOURCE_SHAPE"|Task_store->())
let opened r readonly f=
 resource r;
 let db=if readonly then Sqlite3.db_open ~mode:`READONLY ~mutex:`FULL ~uri:false r.database
  else Sqlite3.db_open ~mode:`NO_CREATE ~mutex:`FULL ~uri:false r.database in
 Fun.protect ~finally:(fun()->close db)(fun()->
  Sqlite3.busy_timeout db 150;
  if readonly then exec db"PRAGMA query_only=ON"else exec db"PRAGMA synchronous=FULL";
  let mode=stmt db"PRAGMA journal_mode"[](fun st->require(Sqlite3.step st=Sqlite3.Rc.ROW)"WAL_REQUIRED";Sqlite3.column st 0)in
  require(mode=Sqlite3.Data.TEXT"wal")"WAL_REQUIRED";resource r;page_bound db;f db)
let exception_code=function
 |Hold code->code
 |Sqlite3.Error _|Sqlite3.SqliteError _|Sqlite3.InternalError _->"SQL_UNAVAILABLE"
 |Unix.Unix_error _|Sys_error _->"RESOURCE_UNAVAILABLE"
 |Yojson.Json_error _|Yojson.Basic.Util.Type_error _|Failure _|Invalid_argument _->"INVALID_STORED_DATA"
 |_->"UNEXPECTED_FAILURE"
let execute ?(checkpoint=(fun _ _->())) r=
 match validate r with Error e->Error e|Ok()->
 try opened r false(fun db->
  let committed=ref false and committing=ref false and active=ref false in
  try
   ignore(fresh r);exec db"BEGIN IMMEDIATE";active:=true;
   let observed=fresh r in resource r;audit db r;
   let original_layout=layout db r.target in
   let history=match original_layout with `Current->lookup db r|_->None in
   match history with
   |Some receipt->committing:=true;exec db"COMMIT";active:=false;committed:=true;Ok(`Historical,receipt)
   |None->
    if original_layout=`Current then require(scalar db("SELECT COUNT(*) FROM "^table r.target)=0L)"ALREADY_MIGRATED_DIFFERENT_REQUEST";
    let before=data db r.target and before_core=core_schema db r.target in
    let old_names=List.map fst before in
    (match original_layout with `Absent->List.iter(fun(_,sql)->exec db sql)(schema r.target@receipt_schema r.target)
    |`Legacy_complete->List.iter(fun(_,sql)->exec db sql)(receipt_schema r.target)|`Current->());
    checkpoint After_ddl db;
    require(layout db r.target=`Current)"INSTALLED_SCHEMA_MISMATCH";
    let s x=`String x in let receipt=`Assoc[
     "domain",s"uos.recovery-schema-migration-receipt.v1";"migration_id",s r.migration_id;"resource_id",s r.resource_id;
     "request_sha256",s(sha(request_bytes r));"source_sha256",s r.source_sha256;"before_schema_sha256",s r.before_schema_sha256;
     "installed_schema_sha256",s(schema_sha(expected r.target));"observed_utc_ns",s(Int64.to_string observed.utc_ns);
     "observed_mono_ns",s(Int64.to_string observed.mono_ns);"preserved_tables",`Int(List.length before);"authority",s"NONE"]in
    stmt db("INSERT INTO "^table r.target^" VALUES(?,?,?,?)")[Sqlite3.Data.TEXT r.migration_id;Sqlite3.Data.TEXT(sha(request_bytes r));Sqlite3.Data.TEXT(request_bytes r);Sqlite3.Data.TEXT(Yojson.Basic.to_string receipt)](fun st->require(Sqlite3.step st=Sqlite3.Rc.DONE)"RECEIPT_INSERT");
    checkpoint Before_final_checks db;
    (* Every injected test callback finishes BEFORE this final exact proof. *)
    page_bound db;ignore(fresh r);resource r;audit db r;
    require(core_schema db r.target=before_core&&layout db r.target=`Current)"SCHEMA_POSTGOAL";
    let after=data db r.target in
    require(equal_data before(List.filter(fun(n,_)->List.mem n old_names)after)
     &&List.for_all(fun(n,rows)->List.mem n old_names||rows=[])after)"DATA_POSTGOAL";
    require(lookup db r=Some receipt)"RECEIPT_POSTGOAL";page_bound db;
    ignore(fresh r);committing:=true;exec db"COMMIT";active:=false;committed:=true;
    checkpoint After_commit db;
    resource r;require(layout db r.target=`Current&&lookup db r=Some receipt)"POSTCOMMIT_READBACK";
    Ok(`Installed,receipt)
  with exn->
   if !committed then Error Commit_unknown
   else if !committing then(ignore(try Sqlite3.exec db"ROLLBACK"with _->Sqlite3.Rc.ERROR);Error Commit_unknown)
   else if !active then(
    let rolled=try Sqlite3.exec db"ROLLBACK"=Sqlite3.Rc.OK with _->false in
    if rolled then Error(Refused(exception_code exn))else Error Commit_unknown)
   else Error(Refused(exception_code exn)))
 with exn->Error(Refused(exception_code exn))
let reconcile r=
 match validate r with Error e->Error e|Ok()->
 try opened r true(fun db->
  exec db"BEGIN";
  Fun.protect ~finally:(fun()->ignore(Sqlite3.exec db"ROLLBACK"))(fun()->
   audit db r;require(layout db r.target=`Current)"RECOVERY_SCHEMA_MISMATCH";
   let receipt=lookup db r in exec db"COMMIT";Ok receipt))
 with exn->Error(Refused(exception_code exn))
