(* LOCAL Codex relay. Stored events are facts, not authentication or permission.
   Reuses the existing strict parser/Evidence_store carrier and schema; the
   private namespace has its own exact append-only schema. No new task store. *)
type error=Invalid_json|Invalid_request|Invalid_path|Schema_mismatch|Nested_transaction|Store_unavailable|Resource_bound|Conflict|Missing_grant|Revoked|Expired|Invalid_clock|Clock_rollback|Commit_unknown|Rollback_failed|Closed
let error_code=function Invalid_json->"invalid_json"|Invalid_request->"invalid_request"|Invalid_path->"invalid_local_path"|Schema_mismatch->"schema_mismatch"|Nested_transaction->"nested_transaction"|Store_unavailable->"store_unavailable"|Resource_bound->"resource_bound"|Conflict->"conflicting_replay"|Missing_grant->"missing_grant"|Revoked->"revoked"|Expired->"expired"|Invalid_clock->"invalid_clock"|Clock_rollback->"clock_rollback"|Commit_unknown->"commit_unknown"|Rollback_failed->"rollback_failed"|Closed->"closed"
let( let* ) x f=match x with Ok v->f v|Error e->Error e
let require b e=if b then Ok()else Error e
let max_request_bytes=262144
let max_response_bytes=262144
type limits={max_grants:int;max_events:int;max_db_bytes:int}
let default_limits={max_grants=4096;max_events=32768;max_db_bytes=16777216}
let max_clock=8_000_000_000_000L
let max_sequence=9_000_000_000_000L
let ttl=3_600_000L
(* Conservative finite storage envelope, not a disk-full or universal SQLite
   growth guarantee: reserve one row and256KiB per not-yet-revoked grant, plus
   256KiB for the current append at<=4096-byte pages. Unknown failures HOLD. *)
let revocation_bytes=262144L
let sha text="sha256:"^Digestif.SHA256.(to_hex(digest_string text))
exception Bad
let check b=if not b then raise Bad
let rec canonical=function `Assoc xs->`Assoc(List.sort(fun(a,_)(b,_)->String.compare a b)(List.map(fun(k,v)->k,canonical v)xs))|`List xs->`List(List.map canonical xs)|`Int n->`Intlit(string_of_int n)|`Intlit s->`Intlit(Int64.to_string(Int64.of_string s))|v->v
let encoded j=Yojson.Safe.to_string(canonical j)
let obj names=function `Assoc xs when List.length xs=List.length names && List.for_all(fun k->List.length(List.filter(fun(a,_)->a=k)xs)=1)names->xs|_->raise Bad
let field xs k=List.assoc k xs
let str=function `String s->s|_->raise Bad
let integer=function `Int n->Int64.of_int n|`Intlit s->Int64.of_string s|_->raise Bad
let id j=let s=str j in check(String.length s>0 && String.length s<=128 && String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'|'.'|':'|'/'->true|_->false)s);s
let digest j=let s=str j in check(String.length s=71 && String.starts_with ~prefix:"sha256:" s && String.for_all(function '0'..'9'|'a'..'f'->true|_->false)(String.sub s 7 64));s
let clock_value n=n>0L && n<=max_clock
let command j=let s=str j in
 check(List.mem s ["stage";"fence_readers";"verify_candidate";"verify_previous";"resume_readers"] ||
 List.exists(fun i->s="replace:"^string_of_int i || s="restore:"^string_of_int i)(List.init 15 Fun.id));s
let reason j=let s=str j in check(List.mem s["operator_revoked";"owner_changed";"candidate_changed";"evidence_stale";"expired";"cancelled";"containment"]);s
let s x=`String x and n x=`Intlit(Int64.to_string x)
type issue={grant:string;intent:string;approval:string;owner:string;expires:int64}
type consume={grant:string;step:string;epoch:int64;generation:int64;command:string}
type action=Issue of issue|Revoke of string*string|Consume of consume|Lookup of string*string option
type request={request_id:string option;action:action;payload:string;digest:string option}
let operation=function Issue _->"issue"|Revoke _->"revoke"|Consume _->"consume"|Lookup _->"lookup"
let grant_id=function Issue x->x.grant|Revoke(g,_)|Lookup(g,_)->g|Consume x->x.grant
let decode_request text=
 match Symbiosis_check_receipts.parse_json text with Error _->Error Invalid_json|Ok j->try
 let op=match j with `Assoc xs->str(field xs "operation")|_->raise Bad in
 let fields=match op with
 |"issue"->["schema_version";"operation";"request_id";"grant_id";"intent_digest";"approval_digest";"owner_binding_digest";"expires_utc_ms"]
 |"revoke"->["schema_version";"operation";"request_id";"grant_id";"reason"]
 |"consume"->["schema_version";"operation";"request_id";"grant_id";"step_digest";"epoch";"generation";"command"]
 |"lookup"->["schema_version";"operation";"grant_id";"step_digest"]|_->raise Bad in
 let o=obj fields j in let get=field o in check(integer(get "schema_version")=1L);
 let grant=id(get "grant_id")in
 let action=match op with
 |"issue"->let expires=integer(get "expires_utc_ms")in check(clock_value expires);Issue{grant;intent=digest(get "intent_digest");approval=digest(get "approval_digest");owner=digest(get "owner_binding_digest");expires}
 |"revoke"->Revoke(grant,reason(get "reason"))
 |"consume"->let epoch=integer(get "epoch")and generation=integer(get "generation")in check(epoch>0L && epoch<=max_sequence && generation>=0L && generation<=max_sequence);Consume{grant;step=digest(get "step_digest");epoch;generation;command=command(get "command")}
 |_->Lookup(grant,match get "step_digest"with `Null->None|j->Some(digest j))in
 let payload=encoded j in
 let request_id=if op="lookup"then None else Some(id(get "request_id"))in
 Ok{request_id;action;payload;digest=Option.map(fun _->sha payload)request_id}
 with Bad|Not_found|Failure _->Error Invalid_request
let request_json r=Yojson.Safe.from_string r.payload
let request_digest r=r.digest
let grants="ecology_release_grants_v1"
let events="ecology_release_grant_events_v1"
let definitions=[
 "table",grants,"CREATE TABLE ecology_release_grants_v1 (grant_index INTEGER PRIMARY KEY CHECK(grant_index>0), grant_id TEXT NOT NULL, intent_digest TEXT NOT NULL, approval_digest TEXT NOT NULL, owner_binding_digest TEXT NOT NULL, issued_utc_ms INTEGER NOT NULL CHECK(typeof(issued_utc_ms)='integer' AND issued_utc_ms>0), expires_utc_ms INTEGER NOT NULL CHECK(typeof(expires_utc_ms)='integer' AND expires_utc_ms>issued_utc_ms AND expires_utc_ms-issued_utc_ms<=3600000), issue_request_id TEXT NOT NULL, issue_request_digest TEXT NOT NULL, issue_event_index INTEGER NOT NULL CHECK(issue_event_index>0))";
 "table",events,"CREATE TABLE ecology_release_grant_events_v1 (event_index INTEGER PRIMARY KEY CHECK(event_index>0), request_id TEXT NOT NULL, request_digest TEXT NOT NULL, operation TEXT NOT NULL CHECK(operation IN ('issue','revoke','consume')), grant_id TEXT NOT NULL REFERENCES ecology_release_grants_v1(grant_id), step_digest TEXT, epoch INTEGER, generation INTEGER, command TEXT, reason TEXT, observed_utc_ms INTEGER NOT NULL CHECK(typeof(observed_utc_ms)='integer' AND observed_utc_ms>0), payload TEXT NOT NULL, CHECK((operation='consume' AND step_digest IS NOT NULL AND typeof(epoch)='integer' AND epoch>0 AND typeof(generation)='integer' AND generation>=0 AND command IS NOT NULL AND reason IS NULL) OR (operation='revoke' AND reason IS NOT NULL AND step_digest IS NULL AND epoch IS NULL AND generation IS NULL AND command IS NULL) OR (operation='issue' AND step_digest IS NULL AND epoch IS NULL AND generation IS NULL AND command IS NULL AND reason IS NULL)))";
 "index","ecology_release_grant_id_v1","CREATE UNIQUE INDEX ecology_release_grant_id_v1 ON ecology_release_grants_v1(grant_id)";
 "index","ecology_release_grant_intent_v1","CREATE UNIQUE INDEX ecology_release_grant_intent_v1 ON ecology_release_grants_v1(intent_digest)";
 "index","ecology_release_grant_issue_request_v1","CREATE UNIQUE INDEX ecology_release_grant_issue_request_v1 ON ecology_release_grants_v1(issue_request_id)";
 "index","ecology_release_grant_request_v1","CREATE UNIQUE INDEX ecology_release_grant_request_v1 ON ecology_release_grant_events_v1(request_id)";
 "index","ecology_release_grant_step_v1","CREATE UNIQUE INDEX ecology_release_grant_step_v1 ON ecology_release_grant_events_v1(grant_id,step_digest) WHERE operation='consume'";
 "index","ecology_release_grant_tuple_v1","CREATE UNIQUE INDEX ecology_release_grant_tuple_v1 ON ecology_release_grant_events_v1(grant_id,epoch,generation,command) WHERE operation='consume'";
 "index","ecology_release_grant_revoke_v1","CREATE UNIQUE INDEX ecology_release_grant_revoke_v1 ON ecology_release_grant_events_v1(grant_id) WHERE operation='revoke'";
 "index","ecology_release_grant_head_v1","CREATE INDEX ecology_release_grant_head_v1 ON ecology_release_grant_events_v1(grant_id,event_index)";
 "trigger","ecology_release_grants_no_update_v1","CREATE TRIGGER ecology_release_grants_no_update_v1 BEFORE UPDATE ON ecology_release_grants_v1 BEGIN SELECT RAISE(ABORT,'release grants are append-only'); END";
 "trigger","ecology_release_grants_no_delete_v1","CREATE TRIGGER ecology_release_grants_no_delete_v1 BEFORE DELETE ON ecology_release_grants_v1 BEGIN SELECT RAISE(ABORT,'release grants are append-only'); END";
 "trigger","ecology_release_grant_events_no_update_v1","CREATE TRIGGER ecology_release_grant_events_no_update_v1 BEFORE UPDATE ON ecology_release_grant_events_v1 BEGIN SELECT RAISE(ABORT,'release grant events are append-only'); END";
 "trigger","ecology_release_grant_events_no_delete_v1","CREATE TRIGGER ecology_release_grant_events_no_delete_v1 BEFORE DELETE ON ecology_release_grant_events_v1 BEGIN SELECT RAISE(ABORT,'release grant events are append-only'); END"]
let sql_exception=function Sqlite3.Error _|Sqlite3.SqliteError _|Sqlite3.InternalError _|Sqlite3.RangeError _|Sqlite3.DataTypeError _->true|_->false
(* Exact pinned Core.Gc opaque-zero liveness technique used by the existing
   receipt owner, without linking colliding Core. Installed core/gc.ml:295-302
   SHA256810d5359aaa2388eb5efb0927550298e2e7d4192d05b54eac6a4c2ee0d51133b.
   Keeps sqlite3-ocaml5.4.1 custom handles live beyond blocking C boundaries. *)
let lifetime_zero=Sys.opaque_identity(int_of_string "0")
let[@inline never] rec keep_alive x=if lifetime_zero<>0 then keep_alive(Sys.opaque_identity x)
let close_db db=Fun.protect ~finally:(fun()->keep_alive db)(fun()->Sqlite3.db_close db)
let finalize st=Fun.protect ~finally:(fun()->keep_alive st)(fun()->Sqlite3.finalize st)
let exec db sql=Fun.protect ~finally:(fun()->keep_alive db)(fun()->try let rc=Sqlite3.exec db sql in if Sqlite3.Rc.is_success rc then Ok()else Error Store_unavailable with ex when sql_exception ex->Error Store_unavailable)
let stmt db sql values f=Fun.protect ~finally:(fun()->keep_alive db)(fun()->try
 let st=Sqlite3.prepare db sql in
 let answer=try `Result(match Sqlite3.bind_values st values with rc when Sqlite3.Rc.is_success rc->f st|_->Error Store_unavailable)with ex->`Raised ex in
 let rc=finalize st in match answer with `Raised ex->raise ex|`Result answer->if Sqlite3.Rc.is_success rc then answer else Error Store_unavailable
 with ex when sql_exception ex->Error Store_unavailable)
let text s=Sqlite3.Data.TEXT s and num n=Sqlite3.Data.INT n
let nullable f=function None->Sqlite3.Data.NULL|Some x->f x
let query_one db sql values f=stmt db sql values(fun st->match Sqlite3.step st with Sqlite3.Rc.DONE->Ok None|Sqlite3.Rc.ROW->let* value=f st in Ok(Some value)|_->Error Store_unavailable)
let pragma db name=let* v=query_one db("PRAGMA "^name)[](fun st->match Sqlite3.column st 0 with Sqlite3.Data.INT n->Ok n|_->Error Store_unavailable)in match v with Some n->Ok n|None->Error Store_unavailable
let schema_state db=stmt db "SELECT type,name,sql FROM main.sqlite_master WHERE tbl_name IN ('ecology_release_grants_v1','ecology_release_grant_events_v1') OR name GLOB 'ecology_release_grant*' ORDER BY name LIMIT 15"[](fun st->
 let rec loop acc=match Sqlite3.step st with Sqlite3.Rc.DONE->Ok acc|Sqlite3.Rc.ROW->loop((Sqlite3.column_text st 0,Sqlite3.column_text st 1,Sqlite3.column_text st 2)::acc)|_->Error Store_unavailable in
 let* rows=loop []in if rows=[]then Ok false else if List.length rows=List.length definitions && List.for_all(fun row->List.mem row definitions)rows then Ok true else Error Schema_mismatch)
let valid_limits l=l.max_grants>0 && l.max_grants<=4096 && l.max_events>0 && l.max_events<=32768 && l.max_db_bytes>=131072 && l.max_db_bytes<=16777216
let safe_path p=String.length p>1 && String.length p<=4096 && p.[0]='/' && not(String.contains p '\000') && List.for_all(fun x->x<>""&&x<>"."&&x<>"..") (List.tl(String.split_on_char '/' p))
let prepare_path path=try
 let* ()=require(safe_path path)Invalid_path in
 let parts=String.split_on_char '/'(Filename.dirname path)|>List.filter((<>)"")in
 ignore(List.fold_left(fun p name->let p=Filename.concat p name in if(Unix.lstat p).Unix.st_kind<>Unix.S_DIR then raise Bad;p)"/"parts);
 let parent=Unix.lstat(Filename.dirname path)in if parent.st_uid<>Unix.geteuid() || parent.st_perm<>0o700 then raise Bad;
 (try let st=Unix.lstat path in if st.st_kind<>Unix.S_REG || st.st_nlink<>1 || st.st_uid<>Unix.geteuid() || st.st_perm<>0o600 then raise Bad
 with Unix.Unix_error(Unix.ENOENT,_,_)->
  let fd=Unix.openfile path[Unix.O_CREAT;Unix.O_EXCL;Unix.O_WRONLY;Unix.O_CLOEXEC]0o600 in
  Fun.protect ~finally:(fun()->Unix.close fd)(fun()->Unix.fsync fd);
  let parent=Unix.openfile(Filename.dirname path)[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
  Fun.protect ~finally:(fun()->Unix.close parent)(fun()->Unix.fsync parent));
 let st=Unix.lstat path in Ok(st.st_dev,st.st_ino)
 with Unix.Unix_error _|Bad->Error Invalid_path
type stage=After_insert|Before_commit|Commit_error|After_commit
type t={evidence:Evidence_store.t;path:string;identity:int*int;limits:limits;now_ms:unit->int64;mutable active:bool;mutable closed:bool;mutable poisoned:bool;mutable hook:stage->unit;mutable sampled:int64;mutable expires:int64 option;mutable reserve_bytes:int64;mutable append_bytes:int64}
let physical_files path identity maximum=try
 let main=Unix.lstat path in
 let* ()=require((main.st_dev,main.st_ino)=identity)Invalid_path in
 let total=List.fold_left(fun sum path->try let st=Unix.lstat path in
  if st.st_kind<>Unix.S_REG || st.st_nlink<>1 || st.st_uid<>Unix.geteuid() || st.st_perm<>0o600 then raise Bad;
  Int64.add sum(Int64.of_int st.st_size)with Unix.Unix_error(Unix.ENOENT,_,_)->sum)0L[path;path^"-wal";path^"-shm"]in
 require(total<=Int64.of_int maximum)Resource_bound
 with Unix.Unix_error _|Bad->Error Invalid_path
let physical t=physical_files t.path t.identity t.limits.max_db_bytes
let resource t=let* ()=physical t in let* pages=pragma t.evidence.db "page_count"in let* size=pragma t.evidence.db "page_size"in require(size>0L && pages<=Int64.div(Int64.of_int t.limits.max_db_bytes)size)Resource_bound
let byte_escrow t reserved append=
 let* ()=resource t in let* pages=pragma t.evidence.db "page_count"in let* size=pragma t.evidence.db "page_size"in
 let* ()=require(size>0L && size<=4096L)Resource_bound in
 try let physical=List.fold_left(fun total path->try Int64.add total(Int64.of_int(Unix.lstat path).st_size)with Unix.Unix_error(Unix.ENOENT,_,_)->total)0L[t.path;t.path^"-wal";t.path^"-shm"]in
 let observed=Int64.max physical(Int64.mul pages size)in
 require(Int64.add observed(Int64.add reserved append)<=Int64.of_int t.limits.max_db_bytes)Resource_bound
 with Unix.Unix_error _->Error Invalid_path
let available t=if t.closed then Error Closed else if t.poisoned then Error Rollback_failed else Ok()
let ensure_schema t=let* ()=available t in let* present=schema_state t.evidence.db in require present Schema_mismatch
let sample t minimum=let now=t.now_ms()in let* ()=require(clock_value now)Invalid_clock in let* ()=require(now>=minimum && now>=t.sampled)Clock_rollback in t.sampled<-now;Ok now
let transaction ?(hooks=true) t body=
 let* ()=available t in if t.active then Error Nested_transaction else
 match exec t.evidence.db "BEGIN IMMEDIATE"with Error _->Error Store_unavailable|Ok()->
 t.active<-true;t.sampled<-0L;t.expires<-None;t.reserve_bytes<-0L;t.append_bytes<-0L;
 let rollback e=let rc=exec t.evidence.db "ROLLBACK"in t.active<-false;match rc with Ok()->Error e|Error _->t.poisoned<-true;Error Rollback_failed in
 let unexpected ex=let rc=exec t.evidence.db "ROLLBACK"in t.active<-false;(match rc with Ok()->()|Error _->t.poisoned<-true);raise ex in
 let result=try body()with ex->unexpected ex in
 match result with Error e->rollback e|Ok value->
 let before=try
  if hooks then t.hook Before_commit;
  let* ()=byte_escrow t t.reserve_bytes t.append_bytes in let* now=sample t t.sampled in
  match t.expires with Some expires->require(now<expires)Expired|None->Ok()
 with Failure _->Error Store_unavailable|ex->unexpected ex in
 match before with Error e->rollback e|Ok()->
 let committed=try if hooks then t.hook Commit_error;exec t.evidence.db "COMMIT"with Failure _->Error Commit_unknown|ex->unexpected ex in
 match committed with Error _->rollback Commit_unknown|Ok()->
 t.active<-false;
 try if hooks then t.hook After_commit;match physical t with Ok()->Ok value|Error _->Error Commit_unknown
 with Failure _|Unix.Unix_error _|Sys_error _->Error Commit_unknown
let initialize t=
 Sqlite3.busy_timeout t.evidence.db 100;
 let* ()=exec t.evidence.db "PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; PRAGMA wal_autocheckpoint=1; PRAGMA journal_size_limit=1048576"in
 let* full=pragma t.evidence.db "synchronous"in let* fk=pragma t.evidence.db "foreign_keys"in let* ()=require(full=2L && fk=1L)Store_unavailable in
 let* size=pragma t.evidence.db "page_size"in let* ()=exec t.evidence.db("PRAGMA max_page_count="^Int64.to_string(Int64.div(Int64.of_int t.limits.max_db_bytes)size))in
 transaction ~hooks:false t(fun()->let* present=schema_state t.evidence.db in if present then Ok()else
  let* ()=List.fold_left(fun acc(_,_,sql)->let* ()=acc in exec t.evidence.db sql)(Ok())definitions in
  let* present=schema_state t.evidence.db in require present Schema_mismatch)
let open_internal ?(limits=default_limits) ~path ~now_ms ()=
 let* ()=require(valid_limits limits)Resource_bound in let* identity=prepare_path path in
 let* ()=physical_files path identity limits.max_db_bytes in
 let* db=try Ok(Sqlite3.db_open ~mode:`NO_CREATE ~uri:false ~mutex:`FULL ~cache:`PRIVATE path)with ex when sql_exception ex->Error Store_unavailable in
 let cleanup e=try if close_db db then Error e else Error Rollback_failed with ex when sql_exception ex->Error Rollback_failed in
 let initialized=try `Result(let* ()=physical_files path identity limits.max_db_bytes in
  let* _=schema_state db in let* ()=exec db Evidence_store.schema in
  let t={evidence={Evidence_store.db=db};path;identity;limits;now_ms;active=false;closed=false;poisoned=false;hook=(fun _->());sampled=0L;expires=None;reserve_bytes=0L;append_bytes=0L}in
  let* ()=initialize t in Ok t)with ex->`Raised ex in
 match initialized with `Result(Ok t)->Ok t|`Result(Error e)->cleanup e|`Raised ex->match cleanup Store_unavailable with Error Rollback_failed->Error Rollback_failed|_->if sql_exception ex then Error Store_unavailable else raise ex
let host_ms()=let ms=Unix.gettimeofday()*.1000. in if classify_float ms=FP_nan || classify_float ms=FP_infinite || ms<=0. || ms>Int64.to_float max_clock then 0L else Int64.of_float(floor ms)
let open_store ?limits ~path ()=open_internal ?limits ~path ~now_ms:host_ms()
let close t=if t.closed then Ok()else if t.active then Error Nested_transaction else
 try if close_db t.evidence.db then(t.closed<-true;Ok())else Error Store_unavailable
 with ex when sql_exception ex->Error Store_unavailable

type grant={index:int64;id:string;intent:string;approval:string;owner:string;issued:int64;expires:int64;issue_id:string;issue_digest:string;issue_event:int64}
type event={index:int64;request:request;at:int64}
let grant_columns="grant_index,grant_id,intent_digest,approval_digest,owner_binding_digest,issued_utc_ms,expires_utc_ms,issue_request_id,issue_request_digest,issue_event_index"
let event_columns="event_index,request_id,request_digest,operation,grant_id,step_digest,epoch,generation,command,reason,observed_utc_ms,payload"
let nullable_text st i=match Sqlite3.column st i with Sqlite3.Data.NULL->None|Sqlite3.Data.TEXT s->Some s|_->raise Bad
let nullable_int st i=match Sqlite3.column st i with Sqlite3.Data.NULL->None|Sqlite3.Data.INT n->Some n|_->raise Bad
let event_row st=try
 let index=Sqlite3.column_int64 st 0 and at=Sqlite3.column_int64 st 10 and payload=Sqlite3.column_text st 11 in
 let* r=match decode_request payload with Ok r when r.request_id<>None && r.payload=payload->Ok r|_->Error Schema_mismatch in
 check(index>0L && index<=32768L && clock_value at && r.request_id=Some(Sqlite3.column_text st 1) && r.digest=Some(Sqlite3.column_text st 2) && operation r.action=Sqlite3.column_text st 3 && grant_id r.action=Sqlite3.column_text st 4);
 let step,epoch,generation,command,reason=match r.action with Consume c->Some c.step,Some c.epoch,Some c.generation,Some c.command,None|Revoke(_,why)->None,None,None,None,Some why|Issue _->None,None,None,None,None|Lookup _->raise Bad in
 check(nullable_text st 5=step && nullable_int st 6=epoch && nullable_int st 7=generation && nullable_text st 8=command && nullable_text st 9=reason);
 Ok{index;request=r;at}
 with Bad|Failure _|Not_found->Error Schema_mismatch
let event_by_id t id=query_one t.evidence.db("SELECT "^event_columns^" FROM main."^events^" WHERE request_id=? LIMIT 1")[text id]event_row
let event_by_index t index=query_one t.evidence.db("SELECT "^event_columns^" FROM main."^events^" WHERE event_index=? LIMIT 1")[num index]event_row
let grant_row st=try
 let g={index=Sqlite3.column_int64 st 0;id=Sqlite3.column_text st 1;intent=Sqlite3.column_text st 2;approval=Sqlite3.column_text st 3;owner=Sqlite3.column_text st 4;issued=Sqlite3.column_int64 st 5;expires=Sqlite3.column_int64 st 6;issue_id=Sqlite3.column_text st 7;issue_digest=Sqlite3.column_text st 8;issue_event=Sqlite3.column_int64 st 9}in
 ignore(id(`String g.id));ignore(id(`String g.issue_id));List.iter(fun x->ignore(digest(`String x)))[g.intent;g.approval;g.owner;g.issue_digest];
 check(g.index>0L && g.index<=4096L && g.issue_event>0L && clock_value g.issued && clock_value g.expires && g.expires>g.issued && Int64.sub g.expires g.issued<=ttl);Ok g
 with Bad|Failure _->Error Schema_mismatch
let grant_by_id t id=
 let* g=query_one t.evidence.db("SELECT "^grant_columns^" FROM main."^grants^" WHERE grant_id=? LIMIT 1")[text id]grant_row in
 match g with None->Ok None|Some g->let* e=event_by_index t g.issue_event in
 (match e with Some{request={request_id=Some request_id;digest=Some request_digest;action=Issue i;_};at;_}
 when request_id=g.issue_id && request_digest=g.issue_digest && at=g.issued && i.grant=g.id && i.intent=g.intent && i.approval=g.approval && i.owner=g.owner && i.expires=g.expires->Ok(Some g)|_->Error Schema_mismatch)
let revoke_by_grant t id=query_one t.evidence.db("SELECT "^event_columns^" FROM main."^events^" WHERE grant_id=? AND operation='revoke' LIMIT 1")[text id]event_row
let step_by_digest t id step=query_one t.evidence.db("SELECT "^event_columns^" FROM main."^events^" WHERE grant_id=? AND operation='consume' AND step_digest=? LIMIT 1")[text id;text step]event_row
let head t=let* e=query_one t.evidence.db("SELECT event_index,observed_utc_ms FROM main."^events^" ORDER BY event_index DESC LIMIT 1")[](fun st->Ok(Sqlite3.column_int64 st 0,Sqlite3.column_int64 st 1))in
 match e with None->Ok(0L,0L)|Some(index,at)->let* ()=require(index>0L && index<=Int64.of_int t.limits.max_events && clock_value at)Resource_bound in Ok(index,at)
let counts t=
 let* count=query_one t.evidence.db("SELECT (SELECT COUNT(*) FROM main."^grants^"),(SELECT COUNT(*) FROM main."^events^")")[](fun st->Ok(Sqlite3.column_int64 st 0,Sqlite3.column_int64 st 1))in
 match count with Some(g,e)->let* ()=require(g>=0L && g<=Int64.of_int t.limits.max_grants && e>=0L && e<=Int64.of_int t.limits.max_events)Resource_bound in Ok(g,e)|None->Error Store_unavailable
let reserve_append t active_after event_count=
 let* ()=require(active_after>=0L && Int64.add(Int64.succ event_count)active_after<=Int64.of_int t.limits.max_events)Resource_bound in
 let reserved=Int64.mul active_after revocation_bytes in
 let* ()=byte_escrow t reserved revocation_bytes in
 t.reserve_bytes<-reserved;t.append_bytes<-revocation_bytes;Ok()
let unrevoked t=
 let* n=query_one t.evidence.db("SELECT COUNT(*) FROM main."^grants^" g WHERE NOT EXISTS (SELECT 1 FROM main."^events^" e WHERE e.grant_id=g.grant_id AND e.operation='revoke')")[]
  (fun st->Ok(Sqlite3.column_int64 st 0))in match n with Some n when n>=0L && n<=Int64.of_int t.limits.max_grants->Ok n|_->Error Resource_bound
let insert_event t index at r=
 let request_id=Option.get r.request_id and request_digest=Option.get r.digest in
 let step,epoch,generation,command,reason=match r.action with Consume c->Some c.step,Some c.epoch,Some c.generation,Some c.command,None|Revoke(_,why)->None,None,None,None,Some why|Issue _->None,None,None,None,None|Lookup _->raise Bad in
 let* ()=stmt t.evidence.db("INSERT INTO main."^events^" VALUES(?,?,?,?,?,?,?,?,?,?,?,?)")
 [num index;text request_id;text request_digest;text(operation r.action);text(grant_id r.action);nullable text step;nullable num epoch;nullable num generation;nullable text command;nullable text reason;num at;text r.payload]
 (fun st->match Sqlite3.step st with Sqlite3.Rc.DONE->Ok()|_->Error Store_unavailable)in
 t.hook After_insert;let* found=event_by_index t index in match found with Some e when e.request.payload=r.payload && e.at=at->Ok e|_->Error Schema_mismatch
let historical e=match e.request.action with Issue _->"issue_replayed"|Revoke _->"already_revoked"|Consume _->"already_consumed"|Lookup _->"found"
let mutate t r=transaction t(fun()->
 let* ()=ensure_schema t in let* ()=resource t in let* count_grants,count_events=counts t in let* active=unrevoked t in let* last,last_at=head t in
 let* _=sample t last_at in
 let* previous=event_by_id t(Option.get r.request_id)in
 match previous with
 |Some e when e.request.payload=r.payload->Ok(historical e,e)
 |Some _->Error Conflict
 |None->
 let* g=grant_by_id t(grant_id r.action)in
 match r.action,g with
 |Issue i,None->
  let* same_intent=query_one t.evidence.db("SELECT grant_id FROM main."^grants^" WHERE intent_digest=? LIMIT 1")[text i.intent](fun st->Ok(Sqlite3.column_text st 0))in
  let* ()=require(same_intent=None)Conflict in
  let* ()=require(count_grants<Int64.of_int t.limits.max_grants && count_events<Int64.of_int t.limits.max_events)Resource_bound in
  let* ()=reserve_append t(Int64.succ active)count_events in
  let index=Int64.succ last in
  let* now=sample t last_at in let* ()=require(i.expires>now && Int64.sub i.expires now<=ttl)Expired in
  t.expires<-Some i.expires;
  let* ()=stmt t.evidence.db("INSERT INTO main."^grants^" VALUES(?,?,?,?,?,?,?,?,?,?)")
   [num(Int64.succ count_grants);text i.grant;text i.intent;text i.approval;text i.owner;num now;num i.expires;text(Option.get r.request_id);text(Option.get r.digest);num index]
   (fun st->match Sqlite3.step st with Sqlite3.Rc.DONE->Ok()|_->Error Store_unavailable)in
  let* e=insert_event t index now r in Ok("issued",e)
 |Issue _,Some _->Error Conflict
 |(Revoke _|Consume _),None->Error Missing_grant
 |Revoke(grant,_),Some _->
  let* old=revoke_by_grant t grant in
  (match old with Some e->Ok("already_revoked",e)|None->
   let* ()=require(count_events<Int64.of_int t.limits.max_events)Resource_bound in
   let* ()=reserve_append t(Int64.pred active)count_events in
   let* now=sample t last_at in let* e=insert_event t(Int64.succ last)now r in Ok("revoked",e))
 |Consume c,Some g->
  let* collisions=stmt t.evidence.db("SELECT "^event_columns^" FROM main."^events^" WHERE grant_id=? AND operation='consume' AND (step_digest=? OR (epoch=? AND generation=? AND command=?)) LIMIT 3")
   [text c.grant;text c.step;num c.epoch;num c.generation;text c.command](fun st->let rec loop acc=match Sqlite3.step st with Sqlite3.Rc.DONE->Ok(List.rev acc)|Sqlite3.Rc.ROW->let* e=event_row st in loop(e::acc)|_->Error Store_unavailable in loop[])in
  (match collisions with
   |[e] when e.request.action=Consume c->Ok("already_consumed",e)
   |_::_->Error Conflict
   |[]->let* revoked=revoke_by_grant t c.grant in let* ()=require(revoked=None)Revoked in
    let* ()=require(count_events<Int64.of_int t.limits.max_events)Resource_bound in
    let* ()=reserve_append t active count_events in
    let* now=sample t last_at in let* ()=require(now<g.expires)Expired in t.expires<-Some g.expires;
    let* e=insert_event t(Int64.succ last)now r in Ok("consumed",e))
 |Lookup _,_->Error Invalid_request)
let optional_json f=function Some x->f x|None->`Null
let grant_json g revocation observed=
 let reason,time,request,index=match revocation with None->`Null,`Null,`Null,`Null|Some e->
  (match e.request.action with Revoke(_,why)->s why,n e.at,optional_json s e.request.request_id,n e.index|_->raise Bad)in
 `Assoc["grant_id",s g.id;"intent_digest",s g.intent;"approval_digest",s g.approval;"owner_binding_digest",s g.owner;
 "issued_utc_ms",n g.issued;"expires_utc_ms",n g.expires;"issue_request_id",s g.issue_id;"issue_request_digest",s g.issue_digest;"issue_event_index",n g.issue_event;
 "revoked",`Bool(revocation<>None);"revoked_reason",reason;"revoked_utc_ms",time;"revoke_request_id",request;"revoke_event_index",index;"expired",`Bool(observed>=g.expires)]
let step_json e=match e.request.action with Consume c->`Assoc["request_id",optional_json s e.request.request_id;"request_digest",optional_json s e.request.digest;"event_index",n e.index;"step_digest",s c.step;"epoch",n c.epoch;"generation",n c.generation;"command",s c.command;"consumed_utc_ms",n e.at]|_->raise Bad
let reply status event observed grant step reason=`Assoc[
 "schema_version",`Int 1;"authority",s "NONE";"authorized",`Bool false;"admitted",`Bool false;"new_effect_permission",`Bool false;
 "status",s status;"request_id",(match event with None->`Null|Some e->optional_json s e.request.request_id);
 "request_digest",(match event with None->`Null|Some e->optional_json s e.request.digest);
 "event_index",optional_json(fun e->n e.index)event;"observed_utc_ms",optional_json n observed;"grant",grant;"step",step;"reason",optional_json s reason]
let hold_json e=reply(if e=Commit_unknown || e=Rollback_failed then "unknown"else "hold")None None `Null `Null(Some(error_code e))
let read_state t grant_id step=transaction ~hooks:false t(fun()->
 let* ()=ensure_schema t in let* ()=resource t in let* _=counts t in let* _,last_at=head t in
 let* g=grant_by_id t grant_id in
 match g with None->let* now=sample t last_at in Ok(now,`Null,`Null)
 |Some g->let* revoked=revoke_by_grant t grant_id in
  let* found=match step with None->Ok None|Some step->step_by_digest t grant_id step in
  let* now=sample t last_at in Ok(now,grant_json g revoked now,optional_json step_json found))
let execute t r=match r.action with
 |Lookup(grant,step)->let* now,g,s=read_state t grant step in Ok(reply(if g=`Null then "absent"else "found")None(Some now)g s None)
 |_->let* status,e=mutate t r in
  let step=match e.request.action with Consume c->Some c.step|_->None in
  (match read_state t(grant_id e.request.action)step with
   |Ok(now,g,s)when g<>`Null->Ok(reply status(Some e)(Some now)g s None)
   |_->Error Commit_unknown)
module For_test=struct
 type nonrec stage=stage=After_insert|Before_commit|Commit_error|After_commit
 let open_with_clock ?limits ~path ~now_ms ()=open_internal ?limits ~path ~now_ms()
 let on_stage t hook=t.hook<-hook
end
