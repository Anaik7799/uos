(* Adapted from UOS receipt-store transaction/GC-lifetime patterns. Metadata
   journal only; an append/status never supplies authorization or task facts. *)
let( let* )=Result.bind
let sha s=Digestif.SHA256.(to_hex(digest_string s))
let s x=`String x
let require b e=if b then Ok()else Error e
let schema_statements=[
 "CREATE TABLE recovery_owner_event (sequence INTEGER PRIMARY KEY, request_sha256 TEXT NOT NULL, request_json TEXT NOT NULL, record_json TEXT NOT NULL)";
 "CREATE TRIGGER recovery_owner_no_update BEFORE UPDATE ON recovery_owner_event BEGIN SELECT RAISE(ABORT,'recovery owner records are append-only'); END";
 "CREATE TRIGGER recovery_owner_no_delete BEFORE DELETE ON recovery_owner_event BEGIN SELECT RAISE(ABORT,'recovery owner records are append-only'); END"]
let names=["recovery_owner_event";"recovery_owner_no_update";"recovery_owner_no_delete"]
let close db=Fun.protect ~finally:(fun()->Core.Gc.keep_alive db)(fun()->Sqlite3.db_close db)
let finalize st=Fun.protect ~finally:(fun()->Core.Gc.keep_alive st)(fun()->ignore(Sqlite3.finalize st))
let stmt db sql values f=Fun.protect ~finally:(fun()->Core.Gc.keep_alive db)(fun()->
 try let st=Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun()->finalize st)(fun()->
   let rc=Sqlite3.bind_values st values in if rc<>Sqlite3.Rc.OK then Error"SQL_BOUND"else f st)
 with Sqlite3.Error _|Sqlite3.SqliteError _|Sqlite3.InternalError _->Error"SQL_UNAVAILABLE")
let exec db sql=Fun.protect ~finally:(fun()->Core.Gc.keep_alive db)(fun()->try if Sqlite3.exec db sql=Sqlite3.Rc.OK then Ok()else Error"SQL_UNAVAILABLE"with _->Error"SQL_UNAVAILABLE")
let canonical raw=
 if String.length raw=0||String.length raw>16384||not(String.for_all(fun c->Char.code c>=32&&Char.code c<=126)raw)then Error"WIRE_BOUND"else
 let depth=ref 0 and quote=ref false and escape=ref false and bad=ref false in
 String.iter(fun c->if !quote then(if !escape then escape:=false else if c='\\'then escape:=true else if c='"'then quote:=false)
  else if c='"'then quote:=true else if c='{'||c='['then(incr depth;if !depth>5 then bad:=true)else if c='}'||c=']'then(decr depth;if !depth<0 then bad:=true))raw;
 if !bad|| !quote|| !depth<>0 then Error"WIRE_DEPTH"else
 try let j=Yojson.Basic.from_string raw in if Yojson.Basic.to_string j=raw then Ok j else Error"NONCANONICAL_JSON"with Yojson.Json_error _->Error"INVALID_JSON"
let fields keys=function `Assoc fs when List.map fst fs=keys->Ok fs|_->Error"CLOSED_SCHEMA"
let field fs k=List.assoc k fs
let text=function `String v->Ok v|_->Error"TEXT_REQUIRED"
let digest j=let* v=text j in let* ()=require(String.length v=64&&String.for_all(function 'a'..'f'|'0'..'9'->true|_->false)v)"DIGEST_REQUIRED"in Ok v
let nullable_digest=function `Null->Ok None|j->let* v=digest j in Ok(Some v)
let id j=let* v=text j in let* ()=require(String.length v>0&&String.length v<=160&&String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'-'|'_'|'.'|'/'->true|_->false)v)"IDENTIFIER_REQUIRED"in Ok v
let binding j=let* fs=fields["owner_id";"operation_id";"request_sha256";"context_sha256"]j in
 let* _=id(field fs"owner_id")in let* _=digest(field fs"operation_id")in let* _=digest(field fs"request_sha256")in let* _=digest(field fs"context_sha256")in Ok j
let phase j=let* p=text j in let* ()=require(List.mem p["pending";"unknown";"committed_fact";"refused";"reconcile_only"])"PHASE_REQUIRED"in Ok p
let event j=let* fs=fields["sequence";"phase";"receipt_sha256"]j in
 let* sequence=match field fs"sequence"with `Int n when n>0&&n<=256->Ok n|_->Error"SEQUENCE_BOUND"in
 let* phase=phase(field fs"phase")in let* receipt=nullable_digest(field fs"receipt_sha256")in
 let* ()=require((phase="committed_fact")=Option.is_some receipt)"RECEIPT_PHASE_MISMATCH"in Ok(sequence,phase,receipt)
let opt=function None->`Null|Some v->s v
let record binding sequence phase receipt previous=
 let body=`Assoc["domain",s"uos.recovery-owner-record.v1";"binding",binding;"sequence",`Int sequence;"phase",s phase;
  "receipt_sha256",opt receipt;"previous_sha256",opt previous]in
 `Assoc["sequence",`Int sequence;"phase",s phase;"receipt_sha256",opt receipt;"previous_sha256",opt previous;"sha256",s(sha(Yojson.Basic.to_string body))]
let schema db=
 stmt db"SELECT CAST(substr(CAST(name AS BLOB),1,201) AS TEXT),CAST(substr(CAST(sql AS BLOB),1,8193) AS TEXT) FROM sqlite_schema WHERE sql IS NOT NULL ORDER BY name LIMIT 7"[] (fun st->
  let legacy=List.sort compare(List.combine names schema_statements)in
  let version2=List.sort compare(legacy@Recovery_schema_migration.receipt_schema Recovery_schema_migration.Owner_journal)in
  let rec read count acc=match Sqlite3.step st with
   |Sqlite3.Rc.DONE->let actual=List.sort compare acc in require(actual=legacy||actual=version2)"SCHEMA_MISMATCH"
   |Sqlite3.Rc.ROW when count<6->(match Sqlite3.column st 0,Sqlite3.column st 1 with
     |Sqlite3.Data.TEXT a,Sqlite3.Data.TEXT b->read(count+1)((a,b)::acc)|_->Error"SCHEMA_TYPE")
   |_->Error"SCHEMA_MISMATCH"in read 0 [])
let page_bound db=let read pragma=stmt db pragma[](fun st->match Sqlite3.step st with Sqlite3.Rc.ROW->(match Sqlite3.column st 0 with Sqlite3.Data.INT n when n>=0L->Ok n|_->Error"PAGE_BOUND")|_->Error"PAGE_BOUND")in
 let* count=read"PRAGMA page_count"in let* size=read"PRAGMA page_size"in
 require(size>0L&&size<=65536L&&count<=Int64.div 33554432L size)"DATABASE_BOUND"
let settings db=
 let* ()=stmt db"PRAGMA journal_mode"[](fun st->match Sqlite3.step st with Sqlite3.Rc.ROW when Sqlite3.column st 0=Sqlite3.Data.TEXT"wal"->Ok()|_->Error"WAL_REQUIRED")in
 stmt db"PRAGMA synchronous"[](fun st->match Sqlite3.step st with Sqlite3.Rc.ROW when (match Sqlite3.column st 0 with Sqlite3.Data.INT n->n=2L||n=3L|_->false)->Ok()|_->Error"FULL_REQUIRED")
let identity path=
 try let st=Unix.lstat path in
 if st.Unix.st_kind=Unix.S_REG&&st.Unix.st_nlink=1&&st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_perm land 0o077=0&&st.Unix.st_size<=33554432 then Ok st else Error"PRIVATE_DATABASE_REQUIRED"
 with Unix.Unix_error _->Error"DATABASE_UNAVAILABLE"
type stored={sequence:int;request:string;record:Yojson.Basic.t}
let row st=
 match Sqlite3.column st 0,Sqlite3.column st 1,Sqlite3.column st 2,Sqlite3.column st 3 with
 |Sqlite3.Data.INT n,Sqlite3.Data.TEXT digest,Sqlite3.Data.TEXT request,Sqlite3.Data.TEXT bytes when n>0L&&n<=256L&&String.length request<=16384&&String.length bytes<=4096&&sha request=digest->
  let* _=canonical request in let* record=canonical bytes in Ok{sequence=Int64.to_int n;request;record}
 |_->Error"CORRUPT_RECORD"
let row_query="SELECT CASE WHEN typeof(sequence)='integer' THEN sequence ELSE NULL END,CASE WHEN typeof(request_sha256)='text' THEN CAST(substr(CAST(request_sha256 AS BLOB),1,65) AS TEXT) ELSE NULL END,CASE WHEN typeof(request_json)='text' THEN CAST(substr(CAST(request_json AS BLOB),1,16385) AS TEXT) ELSE NULL END,CASE WHEN typeof(record_json)='text' THEN CAST(substr(CAST(record_json AS BLOB),1,4097) AS TEXT) ELSE NULL END FROM recovery_owner_event "
let latest db=
 let* ()=stmt db"SELECT count(*),min(sequence),max(sequence) FROM (SELECT sequence FROM recovery_owner_event LIMIT 257)"[](fun st->
  match Sqlite3.step st with
  |Sqlite3.Rc.ROW->(match Sqlite3.column st 0,Sqlite3.column st 1,Sqlite3.column st 2 with
   |Sqlite3.Data.INT 0L,Sqlite3.Data.NULL,Sqlite3.Data.NULL->Ok()
   |Sqlite3.Data.INT count,Sqlite3.Data.INT 1L,Sqlite3.Data.INT max when count>0L&&count<=256L&&count=max->Ok()
   |_->Error"JOURNAL_GAP_OR_CAPACITY")
  |_->Error"JOURNAL_BOUND_UNAVAILABLE")in
 stmt db(row_query^"ORDER BY sequence DESC LIMIT 1")[](fun st->match Sqlite3.step st with Sqlite3.Rc.DONE->Ok None|Sqlite3.Rc.ROW->let* r=row st in Ok(Some r)|_->Error"LATEST_UNAVAILABLE")
let validate_record b r=
 let* j=canonical r.request in let* fs=fields["schema_version";"operation";"binding";"expected_previous";"event"]j in
 let* binding= binding(field fs"binding")in let* ()=require(binding=b&&field fs"schema_version"=`Int 1&&field fs"operation"=s"append")"JOURNAL_BINDING_MISMATCH"in
 let* previous=nullable_digest(field fs"expected_previous")in let* sequence,phase,receipt=event(field fs"event")in
 require(sequence=r.sequence&&r.record=record b sequence phase receipt previous)"CORRUPT_RECORD"
let complete_history db b=
 let* selected=latest db in
 stmt db(row_query^"ORDER BY sequence LIMIT 257")[](fun st->
  let rec walk expected previous last=
   match Sqlite3.step st with
   |Sqlite3.Rc.DONE->require(last=selected)"HEAD_HISTORY_MISMATCH" |> Result.map(fun()->last)
   |Sqlite3.Rc.ROW when expected<=256->
    let* r=row st in let* ()=validate_record b r in
    let fs=Yojson.Basic.Util.to_assoc r.record in
    let* actual_previous=nullable_digest(List.assoc"previous_sha256"fs)in
    let* phase=text(List.assoc"phase"fs)in
    let* ()=require(r.sequence=expected&&actual_previous=previous&&((expected=1&&phase="pending")||(expected>1&&phase<>"pending")))"ANCESTRY_OR_REARM_MISMATCH"in
    let digest=Yojson.Basic.Util.to_string(List.assoc"sha256"fs)in
    walk(expected+1)(Some digest)(Some r)
   |_->Error"HISTORY_BOUND_OR_SQL_FAILURE"in walk 1 None None)
let response status code b r=Yojson.Basic.to_string(`Assoc["status",s status;"code",s code;"binding",b;"record",r;"authority",s"NONE"])
let operate db bytes b op previous ev=
 let* ()=schema db in let* ()=page_bound db in
 let read()=complete_history db b in
 if op="latest"then(
  let* ()=exec db"BEGIN"in
  let result=let* ()=schema db in let* current=read()in Ok("LATEST",Option.fold ~none:`Null~some:(fun r->r.record)current)in
  match result with Error _ as e->ignore(exec db"ROLLBACK");e|Ok value->let* ()=exec db"COMMIT"in Ok value)else
 let* sequence,phase,receipt=event ev in
 let* ()=settings db in let* ()=exec db"BEGIN IMMEDIATE"in
 let committed=ref false in
 let rollback e=match exec db"ROLLBACK"with Ok()->Error e|Error _->Error"COMMIT_UNKNOWN"in
 try
  let body()=
   let* ()=schema db in let* current=read()in
   let* existing=stmt db(row_query^"WHERE sequence=? LIMIT 1")[Sqlite3.Data.INT(Int64.of_int sequence)](fun st->match Sqlite3.step st with Sqlite3.Rc.DONE->Ok None|Sqlite3.Rc.ROW->let* r=row st in Ok(Some r)|_->Error"LOOKUP_UNAVAILABLE")in
   match existing with
   |Some r->let* ()=validate_record b r in let* ()=require(r.request=bytes)"CONFLICTING_REPLAY"in Ok("REPLAY",r.record)
   |None->
    let expected_seq=Option.fold ~none:1~some:(fun r->r.sequence+1)current in
    let expected_previous=Option.map(fun r->Yojson.Basic.Util.to_string(Yojson.Basic.Util.member"sha256"r.record))current in
    let* ()=require(sequence=expected_seq&&previous=expected_previous&&sequence<=256)"JOURNAL_CAS_OR_CAPACITY"in
    let* ()=require((sequence=1&&phase="pending")||(sequence>1&&phase<>"pending"))"NO_REARM"in
    let recd=record b sequence phase receipt previous in let record_bytes=Yojson.Basic.to_string recd in
    let* ()=stmt db"INSERT INTO recovery_owner_event VALUES(?,?,?,?)"[Sqlite3.Data.INT(Int64.of_int sequence);TEXT(sha bytes);TEXT bytes;TEXT record_bytes](fun st->match Sqlite3.step st with Sqlite3.Rc.DONE->Ok()|_->Error"APPEND_UNAVAILABLE")in
    let* readback=read()in let* ()=require(Option.fold ~none:false~some:(fun r->r.sequence=sequence&&r.request=bytes&&r.record=recd)readback)"READBACK_MISMATCH"in
    let* ()=page_bound db in Ok("APPENDED",recd)in
  match body()with Error e->rollback e|Ok result->
   (match exec db"COMMIT"with Error _->Error"COMMIT_UNKNOWN"|Ok()->committed:=true;Ok result)
 with _->if !committed then Error"COMMIT_UNKNOWN"else rollback"JOURNAL_UNAVAILABLE"
let handle ~database bytes=
 let execute()=
  let* j=canonical bytes in let* fs=fields["schema_version";"operation";"binding";"expected_previous";"event"]j in
  let* ()=require(field fs"schema_version"=`Int 1)"SCHEMA_VERSION"in
  let* op=text(field fs"operation")in let* ()=require(op="latest"||op="append")"UNKNOWN_OPERATION"in
  let* b=binding(field fs"binding")in let* previous=nullable_digest(field fs"expected_previous")in
  let* ()=if op="latest"then require(previous=None&&field fs"event"=`Null)"LATEST_SCHEMA"else Ok()in
  let* before=identity database in
  let rec sidecars=function []->Ok()|suffix::rest->
   let path=database^suffix in
   let* ()=try ignore(Unix.lstat path);let* _=identity path in Ok()with Unix.Unix_error(Unix.ENOENT,_,_)->Ok()in
   sidecars rest in
  let* ()=sidecars["-wal";"-shm"]in
  let db=Sqlite3.db_open ~mode:(if op="latest"then `READONLY else `NO_CREATE)~uri:false database in
  Fun.protect ~finally:(fun()->ignore(close db))(fun()->
   Sqlite3.busy_timeout db 500;
   let* after=identity database in let* ()=require(before.Unix.st_dev=after.Unix.st_dev&&before.Unix.st_ino=after.Unix.st_ino)"DATABASE_IDENTITY_CHANGED"in
   let* ()=if op="latest"then exec db"PRAGMA query_only=ON"else Ok()in
   let result=operate db bytes b op previous(field fs"event")in
   match result with Ok(code,r)->Ok(response"ok"code b r)|Error code->Ok(response(if code="COMMIT_UNKNOWN"then"unknown"else"hold")code b`Null))in
 try match execute()with Ok s->s|Error code->response"hold"code`Null`Null
 with _->response"unknown""NATIVE_UNAVAILABLE"`Null`Null
