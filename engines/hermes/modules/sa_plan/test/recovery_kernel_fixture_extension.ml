
(* TEST-ONLY execution interpreter. Dune concatenates exact production Store
   bytes + reviewed test helpers + this extension into a PRIVATE test module.
   Not linked into the sa_plan library or production worker. No clock/hook
   injection: every check calls Recovery_kernel's actual native clock. *)
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
let initialize_cap_fixture store=
 let open Result.Let_syntax in
 let%bind ()=initialize_reclaim_receipts_for_development store in
 transaction store(fun()->
  let%bind ()=with_stmt store.db "SELECT 1 FROM sa_plan_plan LIMIT 1"(fun st->match Sqlite3.step st with Sqlite3.Rc.DONE->Ok()|_->Error"empty fixture required")in
  List.fold cap_schema~init:(Ok())~f:(fun acc(_,sql)->let%bind ()=acc in exec store.db "fixture capability schema"sql))
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
let cap_inspect_history path e=
 (* A separate physically READONLY connection and deferred read snapshot.
    No initializer, migration, BEGIN IMMEDIATE, claim or capability conversion. *)
 try let db=Sqlite3.db_open ~mode:`READONLY ~uri:false path in
 Fun.protect ~finally:(fun()->ignore(close_db db:bool))(fun()->
  let open Result.Let_syntax in
  Sqlite3.busy_timeout db 500;
  let%bind ()=exec db"history query-only""PRAGMA query_only=ON"in
  let%bind version=read_schema_version db in
  let%bind ()=if version=7 then audit_v7_shape db else Error"history requires exact existing v7"in
  let%bind ()=exec db"history read snapshot""BEGIN"in
  let store={db;closed=false;transaction_active=true;schema_version=7}in
  let result=cap_lookup_digests store ~evidence:(Recovery_kernel.historical_evidence_sha256 e)
   ~capability:(Recovery_kernel.historical_capability_sha256 e)(cap_request_bytes(Recovery_kernel.historical_request_bytes e))in
  match result with
  |Error _ as e->ignore(Sqlite3.exec db"ROLLBACK");e
  |Ok value->let%bind ()=exec db"finish history read""COMMIT"in Ok value)
 with _->Error"history read unavailable"
type cap_outcome=Cap_committed of Yojson.Basic.t|Cap_historical of Yojson.Basic.t
let cap_reconcile store e=
 let r=cap_request e in transaction store(fun()->cap_lookup store e r)
let cap_execute store e=
 let r=cap_request e in
 if store.closed||store.transaction_active then Error Reclaim_unknown else
 match reclaim_request_validate r with Error _ as err->err|Ok()->
 match Result.bind(reclaim_storage_settings store.db)~f:(fun()->exec store.db "begin private capability transaction""BEGIN IMMEDIATE")with
 |Error message->Error(Reclaim_refused message)
 |Ok()->
 store.transaction_active<-true;
 let committed=ref false in
 let poison()=store.closed<-true;store.transaction_active<-false;(try ignore(close_db store.db:bool)with _->())in
 let rollback message=store.transaction_active<-false;
  try match Sqlite3.exec store.db "ROLLBACK"with Sqlite3.Rc.OK->Error(Reclaim_refused message)|_->poison();Error Reclaim_unknown
  with _->poison();Error Reclaim_unknown in
 try
 let body()=
  let open Result.Let_syntax in
  let%bind prior=cap_lookup store e r in
  match prior with Some j->Ok(Cap_historical j)|None->
  let%bind unbound=reclaim_lookup store.db r in
  let%bind ()=if Option.is_none unbound then Ok()else Error"unbound factual history cannot authorize new effect"in
  let last=ref None in
  let fresh()=
   let%bind clock=Recovery_kernel.still_valid e in
   let%bind ()=match !last with None->Ok()|Some(previous:Recovery_kernel.clock)->
    if Int64.(clock.utc_ns>=previous.utc_ns&&clock.mono_ns>=previous.mono_ns)then Ok()else Error"native clock regressed"in
   last:=Some clock;Ok clock.utc_ns in
  let%bind now=fresh()in
  let%bind ()=if Int64.(now<r.request_deadline_ns&&now<=Int64.max_value-r.reclaim_lease_ns)then Ok()else Error"native request deadline"in
  let%bind before,before_sha=recovery_snapshot_bounded store ~plan_id:r.reclaim_plan_id in
  let%bind ()=if String.equal before_sha r.expected_snapshot_sha256&&reclaim_same_old(reclaim_expired before now)(reclaim_sorted r)then Ok()else Error"exact complete expired set/snapshot changed"in
  let expected=reclaim_expected_post r before now in
  let%bind ()=with_stmt store.db "SELECT count(*) FROM (SELECT 1 FROM sa_plan_recovery_cap_receipt LIMIT 257)"(fun st->match Sqlite3.step st with Sqlite3.Rc.ROW when Sqlite3.column_int st 0<256->Ok()|_->Error"capability receipt capacity")in
  let%bind ()=List.fold(reclaim_sorted r)~init:(Ok())~f:(fun acc t->
   let%bind ()=acc in let%bind _=fresh()in
   let%bind claim=claim_task store ~plan_id:r.reclaim_plan_id ~task_id:t.reclaim_task_id ~worker:t.old_worker ~now_ns:now ~lease_ns:r.reclaim_lease_ns in
   if claim.attempt=t.old_attempt+1 then Ok()else Error"claim attempt mismatch")in
  let%bind _=fresh()in let%bind after,after_sha=recovery_snapshot_bounded store ~plan_id:r.reclaim_plan_id in
  let%bind ()=if reclaim_post_matches expected after then Ok()else Error"exact whole postgoal mismatch"in
  let%bind final=fresh()in
  let factual=reclaim_receipt_expected r now final after_sha in
  let%bind ()=with_stmt store.db "INSERT INTO sa_plan_reclaim_receipt VALUES(?,?,?,?)"(fun st->
   let bytes=reclaim_request_bytes r in let%bind ()=bind_values_result "private factual receipt"st[TEXT r.reclaim_request_id;TEXT(reclaim_digest bytes);TEXT bytes;TEXT(Yojson.Basic.to_string factual)]in step_done "private factual receipt"st)in
  let record=cap_record e factual in let bytes=Yojson.Basic.to_string record in
  let%bind ()=if String.length bytes<=16384 then Ok()else Error"capability receipt bytes"in
  let%bind ()=with_stmt store.db "INSERT INTO sa_plan_recovery_cap_receipt VALUES(?,?,?,?)"(fun st->
   let%bind ()=bind_values_result "private capability receipt"st[TEXT r.reclaim_request_id;TEXT(Recovery_kernel.evidence_sha256 e);TEXT(Recovery_kernel.capability_sha256 e);TEXT bytes]in step_done "private capability receipt"st)in
  let%bind readback=cap_lookup store e r in
  let%bind ()=if Option.value_map readback~default:false~f:(fun j->String.equal bytes(Yojson.Basic.to_string j))then Ok()else Error"capability receipt readback"in
  (* Last native clock observation occurs before the last post-state query.
     No injected callback/hook runs here; physical query/COMMIT latency remains
     external, so this is a checked precommit sample, not real-time atomicity. *)
  let%bind last=fresh()in
  let%bind actual,sha=recovery_snapshot_bounded store ~plan_id:r.reclaim_plan_id in
  if Int64.(last<now+r.reclaim_lease_ns)&&reclaim_post_matches expected actual&&String.equal sha after_sha&&List.is_empty(reclaim_expired actual last)
  then Ok(Cap_committed record)else Error"final exact postgoal/expiry changed"in
 match body()with Error msg->rollback msg|Ok outcome->
 (match Sqlite3.exec store.db "COMMIT"with
  |Sqlite3.Rc.OK->committed:=true;store.transaction_active<-false;Ok outcome
  |_->poison();Error Reclaim_unknown)
 with _->if !committed then Error Reclaim_unknown else rollback"private capability transaction unavailable"
