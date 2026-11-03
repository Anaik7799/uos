
(* Source-owned internal extension; no interpreter string substitutions.
   Closed factual operations; no production authority or public callback. *)
let reclaim_expired json now =
 let open Yojson.Basic.Util in
 List.filter_map(to_list json)~f:(fun row->
  let state=to_string(member"state"row)in
  if not(List.mem ["available";"executing";"completed"]state~equal:String.equal)then failwith "invalid task state";
  if not(String.equal state"executing")then None else
  let lease=Int64.of_string(to_string(member"lease_until_ns"row))in
  if Int64.(lease<=0L)then failwith "nonpositive executing lease";
  if Int64.(lease>now)then None else Some{
   reclaim_task_id=to_string(member"task_id"row);old_worker=to_string(member"worker"row);
   old_attempt=to_int(member"attempt"row);old_lease_until_ns=lease})
let reclaim_same_old a b=String.equal(Yojson.Basic.to_string(`List(List.map a~f:reclaim_old_json)))(Yojson.Basic.to_string(`List(List.map b~f:reclaim_old_json)))
(* Derive the entire checker projection from the actual BEFORE state. Only the
   three approved rows may change, and only their four claim fields. *)
let reclaim_expected_post r before now =
 let open Yojson.Basic.Util in
 `List(List.map(to_list before)~f:(fun row->
  let id=to_string(member"task_id"row)in
  match List.find r.expired_tasks~f:(fun t->String.equal t.reclaim_task_id id)with
  | None->row
  | Some t->`Assoc(List.map(to_assoc row)~f:(fun(k,v)->k,match k with
    |"state"->`String"executing"|"worker"->`String t.old_worker
    |"attempt"->`Int(t.old_attempt+1)
    |"lease_until_ns"->`String(Int64.to_string(Int64.(now+r.reclaim_lease_ns)))
    |_->v))))
let reclaim_post_matches expected actual =
 String.equal(Yojson.Basic.to_string expected)(Yojson.Basic.to_string actual)
let reclaim_storage_settings db =
 Result.bind(with_stmt db "PRAGMA journal_mode"(fun stmt->match Sqlite3.step stmt with
  | Sqlite3.Rc.ROW when String.equal(Sqlite3.column_text stmt 0)"wal"->Ok()
  | _->Error "reclaim requires WAL durability configuration"))~f:(fun()->
 with_stmt db "PRAGMA synchronous"(fun stmt->match Sqlite3.step stmt with
  | Sqlite3.Rc.ROW when (match Sqlite3.column stmt 0 with Sqlite3.Data.INT n->Int64.(n=2L||n=3L)|_->false)->Ok()
  | _->Error "reclaim requires FULL or EXTRA synchronous configuration"))

let cap_schema=[
 "sa_plan_recovery_cap_receipt","CREATE TABLE sa_plan_recovery_cap_receipt (request_id TEXT PRIMARY KEY, evidence_sha256 TEXT NOT NULL, capability_sha256 TEXT NOT NULL, receipt_json TEXT NOT NULL)";
 "sa_plan_recovery_cap_no_update","CREATE TRIGGER sa_plan_recovery_cap_no_update BEFORE UPDATE ON sa_plan_recovery_cap_receipt BEGIN SELECT RAISE(ABORT,'recovery capability receipts are append-only'); END";
 "sa_plan_recovery_cap_no_delete","CREATE TRIGGER sa_plan_recovery_cap_no_delete BEFORE DELETE ON sa_plan_recovery_cap_receipt BEGIN SELECT RAISE(ABORT,'recovery capability receipts are append-only'); END"]
let cap_schema_valid db=
 with_stmt db "SELECT CAST(substr(CAST(name AS BLOB),1,201) AS TEXT),CAST(substr(CAST(sql AS BLOB),1,8193) AS TEXT) FROM sqlite_schema WHERE name GLOB 'sa_plan_recovery_cap_*' ORDER BY name LIMIT 4"(fun st->
  let rec loop acc=match Sqlite3.step st with
   |Sqlite3.Rc.DONE->if List.equal (fun(a,b)(c,d)->String.equal a c&&String.equal b d)(List.sort acc~compare:Poly.compare)(List.sort cap_schema~compare:Poly.compare)then Ok()else Error"capability receipt schema absent or mismatched"
   |Sqlite3.Rc.ROW when List.length acc<3->loop((Sqlite3.column_text st 0,Sqlite3.column_text st 1)::acc)
   |_->Error"capability receipt schema invalid"in loop[])
let cap_request_bytes bytes=
 let open Yojson.Basic.Util in
 let j=Yojson.Basic.from_string bytes in
 {reclaim_request_id=to_string(member"request_id"j);reclaim_plan_id=to_string(member"plan"j);
 expected_snapshot_sha256=to_string(member"snapshot"j);
 expired_tasks=List.map(to_list(member"old"j))~f:(fun t->{reclaim_task_id=to_string(member"task"t);old_worker=to_string(member"worker"t);old_attempt=to_int(member"attempt"t);old_lease_until_ns=Int64.of_string(to_string(member"lease"t))});
 reclaim_lease_ns=Int64.of_string(to_string(member"duration"j));request_deadline_ns=Int64.of_string(to_string(member"deadline"j))}
let cap_request e=cap_request_bytes(Recovery_kernel.request_bytes e)
let cap_record_digests ~evidence ~capability factual=`Assoc["domain",`String"uos.sa-plan.recovery-cap-receipt.v1";
 "evidence_sha256",`String evidence;"capability_sha256",`String capability;"factual",factual]
let cap_record e factual=cap_record_digests ~evidence:(Recovery_kernel.evidence_sha256 e)~capability:(Recovery_kernel.capability_sha256 e)factual
let cap_lookup_digests store ~evidence:expected_evidence ~capability:expected_capability r=
 let open Result.Let_syntax in
 let%bind ()=cap_schema_valid store.db in
 with_stmt store.db "SELECT CASE WHEN typeof(evidence_sha256)='text' THEN CAST(substr(CAST(evidence_sha256 AS BLOB),1,65) AS TEXT) ELSE NULL END,CASE WHEN typeof(capability_sha256)='text' THEN CAST(substr(CAST(capability_sha256 AS BLOB),1,65) AS TEXT) ELSE NULL END,CASE WHEN typeof(receipt_json)='text' THEN CAST(substr(CAST(receipt_json AS BLOB),1,16385) AS TEXT) ELSE NULL END FROM sa_plan_recovery_cap_receipt WHERE request_id=? LIMIT 2"(fun st->
  let%bind ()=bind_values_result "lookup private capability receipt"st[TEXT r.reclaim_request_id]in
  match Sqlite3.step st with
  |Sqlite3.Rc.DONE->Ok None
  |Sqlite3.Rc.ROW->
   let evidence=Sqlite3.column_text st 0 and capability=Sqlite3.column_text st 1 and bytes=Sqlite3.column_text st 2 in
   if String.length bytes>16384||not(String.equal evidence expected_evidence&&String.equal capability expected_capability)then Error"capability replay conflict"else
   let%bind factual=reclaim_lookup store.db r in
   (match factual with Some factual when String.equal bytes(Yojson.Basic.to_string(cap_record_digests ~evidence ~capability factual))->
    (match Sqlite3.step st with Sqlite3.Rc.DONE->Ok(Some(cap_record_digests ~evidence ~capability factual))|_->Error"duplicate capability receipt")
    |_->Error"capability/factual receipt mismatch")
  |rc->rc_error "read private capability receipt"rc)
let cap_lookup store e r=cap_lookup_digests store ~evidence:(Recovery_kernel.evidence_sha256 e)~capability:(Recovery_kernel.capability_sha256 e)r

type cap_outcome=Cap_committed of Yojson.Basic.t|Cap_historical of Yojson.Basic.t
let resource_schema=[
 "control_resource_receipt","CREATE TABLE control_resource_receipt(request_id TEXT PRIMARY KEY,binding_json TEXT NOT NULL)";
 "control_no_update","CREATE TRIGGER control_no_update BEFORE UPDATE ON control_resource_receipt BEGIN SELECT RAISE(ABORT,'control receipts are append-only'); END";
 "control_no_delete","CREATE TRIGGER control_no_delete BEFORE DELETE ON control_resource_receipt BEGIN SELECT RAISE(ABORT,'control receipts are append-only'); END"]
let resource_schema_valid db=
 with_stmt db "SELECT name,sql FROM sqlite_schema WHERE name GLOB 'control_*' ORDER BY name LIMIT 4"(fun st->
 let rec loop acc=match Sqlite3.step st with
 |Sqlite3.Rc.DONE->if List.equal Poly.equal(List.sort acc~compare:Poly.compare)(List.sort resource_schema~compare:Poly.compare)then Ok()else Error"resource receipt schema mismatch"
 |Sqlite3.Rc.ROW when List.length acc<3->loop((Sqlite3.column_text st 0,Sqlite3.column_text st 1)::acc)
 |_->Error"resource receipt schema bound"in loop[])
let resource_lookup db id expected=
 let open Result.Let_syntax in let%bind ()=resource_schema_valid db in
 with_stmt db "SELECT CASE WHEN typeof(binding_json)='text' THEN CAST(substr(CAST(binding_json AS BLOB),1,16385) AS TEXT) ELSE NULL END FROM control_resource_receipt WHERE request_id=? LIMIT 2"(fun st->
 let%bind ()=bind_values_result "resource read"st[TEXT id]in match Sqlite3.step st with
 |Sqlite3.Rc.DONE->Ok false
 |Sqlite3.Rc.ROW->if String.equal(Sqlite3.column_text st 0)expected&&String.length expected<=16384&&Poly.(Sqlite3.step st=Sqlite3.Rc.DONE)then Ok true else Error"resource receipt conflict"
 |_->Error"resource read failed")
type prepare_error=Prepare_refused|Prepare_unknown
let prepare_additional_private store=
 let open Result.Let_syntax in
 if store.closed||store.transaction_active then Error Prepare_unknown else
 match Sqlite3.exec store.db"BEGIN IMMEDIATE"with
 |Sqlite3.Rc.OK->
 store.transaction_active<-true;
 let commit_requested=ref false in
 let rollback()=store.transaction_active<-false;
  try if Poly.(Sqlite3.exec store.db"ROLLBACK"=Sqlite3.Rc.OK)then Error Prepare_refused else Error Prepare_unknown
  with _->Error Prepare_unknown in
 (try let body()=
 let%bind ()=if store.schema_version=7 then Ok()else Error"existing v7 required"in
 let%bind before,sha=recovery_snapshot_bounded store~plan_id:Recovery_kernel.fixed_plan in
 let%bind ()=if List.length(Yojson.Basic.Util.to_list before)>=4 then Ok()else Error"populated synthetic plan required"in
 let install prefix expected validate=
  let%bind present=with_stmt store.db("SELECT count(*) FROM sqlite_schema WHERE name GLOB '"^prefix^"*'")(fun st->match Sqlite3.step st with Sqlite3.Rc.ROW->Ok(Sqlite3.column_int st 0)|_->Error"schema count")in
  if present=0 then List.fold expected~init:(Ok())~f:(fun acc(_,sql)->let%bind ()=acc in exec store.db "private prepare"sql)
  else validate store.db in
 let%bind ()=install "sa_plan_reclaim_" reclaim_schema reclaim_schema_valid in
 let%bind ()=install "sa_plan_recovery_cap_" cap_schema cap_schema_valid in
 let%bind ()=install "control_" resource_schema resource_schema_valid in
 let%bind ()=reclaim_schema_valid store.db in let%bind ()=cap_schema_valid store.db in let%bind ()=resource_schema_valid store.db in
 let%bind after,sha2=recovery_snapshot_bounded store~plan_id:Recovery_kernel.fixed_plan in
 if String.equal sha sha2&&reclaim_post_matches before after then Ok sha else Error"fixed-plan projection changed during preparation"in
 match body()with Error _->rollback()|Ok sha->
  commit_requested:=true;
  let rc=Sqlite3.exec store.db"COMMIT"in store.transaction_active<-false;
  (match rc with Sqlite3.Rc.OK->Ok sha|_->Error Prepare_unknown)
 with _->if !commit_requested then(store.transaction_active<-false;Error Prepare_unknown)else rollback())
 |_->Error Prepare_unknown
let control_history store h ~record_binding=
 let open Result.Let_syntax in
 let r=cap_request_bytes(Recovery_kernel.historical_request_bytes h)in
 let%bind receipt=cap_lookup_digests store~evidence:(Recovery_kernel.historical_evidence_sha256 h)~capability:(Recovery_kernel.historical_capability_sha256 h)r in
 let%bind bound=resource_lookup store.db r.reclaim_request_id record_binding in
 match receipt,bound with Some receipt,true->Ok(Some receipt)|None,false->Ok None|_->Error"incoherent historical resource receipt"
let control_execute store e ~boundary ~record_binding=
 let r=cap_request e in
 if store.closed||store.transaction_active then Error Reclaim_unknown else
 match reclaim_request_validate r with Error _ as e->e|Ok()->
 match Result.bind(reclaim_storage_settings store.db)~f:(fun()->exec store.db "begin internal development transaction""BEGIN IMMEDIATE")with
 |Error message->Error(Reclaim_refused message)
 |Ok()->store.transaction_active<-true;
 let committed=ref false in
 (* Borrowed handle is NEVER closed here; VFS owns lifetime. *)
 let unknown()=store.closed<-true;store.transaction_active<-false;Error Reclaim_unknown in
 let rollback message=store.transaction_active<-false;
  try if Poly.(Sqlite3.exec store.db"ROLLBACK"=Sqlite3.Rc.OK)then Error(Reclaim_refused message)else unknown()with _->unknown()in
 try let body()=
  let open Result.Let_syntax in
  let%bind prior=cap_lookup store e r in
  match prior with Some j->let%bind bound=resource_lookup store.db r.reclaim_request_id record_binding in
   if bound then Ok(Cap_historical j)else Error"missing bound resource history"
  |None->
  let%bind unbound=reclaim_lookup store.db r in
  let%bind ()=if Option.is_none unbound then Ok()else Error"unbound factual history"in
  let last=ref None in let fresh()=
   let%bind ()=boundary()in let%bind clock=Recovery_kernel.still_valid e in
   let%bind ()=match !last with None->Ok()|Some(previous:Recovery_kernel.clock)->
    if Int64.(clock.utc_ns>=previous.utc_ns&&clock.mono_ns>=previous.mono_ns)then Ok()else Error"native clock regression"in
   last:=Some clock;Ok clock.utc_ns in
  let%bind now=fresh()in
  let%bind ()=if Int64.(now<r.request_deadline_ns&&now<=Int64.max_value-r.reclaim_lease_ns)then Ok()else Error"native deadline"in
  let%bind before,before_sha=recovery_snapshot_bounded store~plan_id:r.reclaim_plan_id in
  let%bind ()=if String.equal before_sha r.expected_snapshot_sha256&&reclaim_same_old(reclaim_expired before now)(reclaim_sorted r)then Ok()else Error"full snapshot/expired set changed"in
  let expected=reclaim_expected_post r before now in
  let%bind ()=resource_schema_valid store.db in
  let%bind ()=with_stmt store.db "SELECT count(*) FROM (SELECT 1 FROM sa_plan_recovery_cap_receipt LIMIT 257)"(fun st->match Sqlite3.step st with Sqlite3.Rc.ROW when Sqlite3.column_int st 0<256->Ok()|_->Error"receipt capacity")in
  let%bind ()=List.fold(reclaim_sorted r)~init:(Ok())~f:(fun acc t->let%bind ()=acc in let%bind _=fresh()in
   let%bind claim=claim_task store~plan_id:r.reclaim_plan_id~task_id:t.reclaim_task_id~worker:t.old_worker~now_ns:now~lease_ns:r.reclaim_lease_ns in
   if claim.attempt=t.old_attempt+1 then Ok()else Error"attempt mismatch")in
  let%bind _=fresh()in let%bind after,after_sha=recovery_snapshot_bounded store~plan_id:r.reclaim_plan_id in
  let%bind ()=if reclaim_post_matches expected after then Ok()else Error"whole postgoal mismatch"in
  let%bind final=fresh()in let factual=reclaim_receipt_expected r now final after_sha in
  let%bind ()=with_stmt store.db"INSERT INTO sa_plan_reclaim_receipt VALUES(?,?,?,?)"(fun st->
   let bytes=reclaim_request_bytes r in let%bind ()=bind_values_result "factual insert"st[TEXT r.reclaim_request_id;TEXT(reclaim_digest bytes);TEXT bytes;TEXT(Yojson.Basic.to_string factual)]in step_done "factual insert"st)in
  let record=cap_record e factual in let bytes=Yojson.Basic.to_string record in
  let%bind ()=if String.length bytes<=16384&&String.length record_binding<=16384 then Ok()else Error"receipt byte bound"in
  let%bind ()=with_stmt store.db"INSERT INTO sa_plan_recovery_cap_receipt VALUES(?,?,?,?)"(fun st->
   let%bind ()=bind_values_result "capability insert"st[TEXT r.reclaim_request_id;TEXT(Recovery_kernel.evidence_sha256 e);TEXT(Recovery_kernel.capability_sha256 e);TEXT bytes]in step_done "capability insert"st)in
  let%bind ()=with_stmt store.db"INSERT INTO control_resource_receipt VALUES(?,?)"(fun st->
   let%bind ()=bind_values_result "resource insert"st[TEXT r.reclaim_request_id;TEXT record_binding]in step_done "resource insert"st)in
  let%bind bound=resource_lookup store.db r.reclaim_request_id record_binding in
  let%bind readback=cap_lookup store e r in
  let%bind ()=if bound&&Option.value_map readback~default:false~f:(fun j->String.equal bytes(Yojson.Basic.to_string j))then Ok()else Error"receipt readback"in
  let%bind last=fresh()in let%bind actual,sha=recovery_snapshot_bounded store~plan_id:r.reclaim_plan_id in
  if Int64.(last<now+r.reclaim_lease_ns)&&reclaim_post_matches expected actual&&String.equal sha after_sha&&List.is_empty(reclaim_expired actual last)
  then Ok(Cap_committed record)else Error"final exact postgoal/expiry changed"in
 match body()with Error msg->rollback msg|Ok outcome->
 (match Sqlite3.exec store.db"COMMIT"with Sqlite3.Rc.OK->committed:=true;store.transaction_active<-false;Ok outcome|_->unknown())
 with _->if !committed then unknown()else rollback"internal development transaction unavailable"
