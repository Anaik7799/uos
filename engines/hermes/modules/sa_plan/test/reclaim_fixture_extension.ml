
(* TEST-ONLY extension. Concatenated to exact production Store source ONLY in
   the private test executable; excluded from the sa_plan library/interface.
   Injected clocks/hooks here have no production authority. *)
type reclaim_checkpoint = After_reclaim_claim of int | Before_reclaim_commit | After_reclaim_commit
let initialize_reclaim_receipts_for_development store =
 transaction store(fun()->
  match reclaim_schema_valid store.db with Ok()->Ok()|Error _->
  let open Result.Let_syntax in
  let%bind ()=with_stmt store.db "SELECT 1 FROM sa_plan_plan LIMIT 1"(fun stmt->
    match Sqlite3.step stmt with Sqlite3.Rc.DONE->Ok()|_->Error "development initialization requires empty plan database")in
  List.fold reclaim_schema ~init:(Ok())~f:(fun acc(_,sql)->Result.bind acc~f:(fun()->exec store.db "initialize development reclaim schema" sql)))
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
let reclaim_execute store r ~observe_now ~checkpoint =
 match reclaim_request_validate r with Error _ as e->e|Ok()->
 if store.closed||store.transaction_active then Error(Reclaim_refused "reclaim requires open sole-owner connection without outer transaction")else
 match (try Result.bind(reclaim_storage_settings store.db)~f:(fun()->exec store.db "begin reclaim transaction" "BEGIN IMMEDIATE")with _->Error "reclaim begin unavailable")with Error e->Error(Reclaim_refused e)|Ok()->
 store.transaction_active<-true;
 let committed=ref false in
 let poison()=store.transaction_active<-false;store.closed<-true;
  (try ignore(close_db store.db:bool)with _->())in
 let rollback_refusal message=
  store.transaction_active<-false;
  try match Sqlite3.exec store.db "ROLLBACK"with Sqlite3.Rc.OK->Error(Reclaim_refused message)|_->poison();Error Reclaim_unknown
  with _->poison();Error Reclaim_unknown in
 try
  let body()=
   let open Result.Let_syntax in
   let%bind prior=reclaim_lookup store.db r in
   match prior with Some receipt->Ok(Reclaim_historical receipt)|None->
   let now=observe_now()in
   let fresh time=Int64.(time>=now&&now>=0L&&time<r.request_deadline_ns&&now<=Int64.max_value-r.reclaim_lease_ns&&time<now+r.reclaim_lease_ns)in
   let%bind ()=if fresh now then Ok()else Error "reclaim deadline/clock invalid"in
   let%bind before,before_sha=recovery_snapshot_bounded store ~plan_id:r.reclaim_plan_id in
   let%bind ()=if String.equal before_sha r.expected_snapshot_sha256&&reclaim_same_old(reclaim_expired before now)(reclaim_sorted r)then Ok()else Error "snapshot or complete expired set changed"in
   let expected_post=reclaim_expected_post r before now in
   let%bind ()=with_stmt store.db "SELECT count(*) FROM (SELECT 1 FROM sa_plan_reclaim_receipt LIMIT 257)"(fun stmt->
    match Sqlite3.step stmt with Sqlite3.Rc.ROW when Sqlite3.column_int stmt 0<256->Ok()|_->Error "reclaim receipt capacity")in
   let%bind ()=List.foldi(reclaim_sorted r)~init:(Ok())~f:(fun i acc t->let%bind ()=acc in
    let%bind claim=claim_task store ~plan_id:r.reclaim_plan_id ~task_id:t.reclaim_task_id ~worker:t.old_worker ~now_ns:now ~lease_ns:r.reclaim_lease_ns in
    if not(String.equal claim.task_id t.reclaim_task_id&&claim.attempt=t.old_attempt+1)then Error "claim identity/attempt mismatch"else(checkpoint(After_reclaim_claim(i+1));Ok()))in
   let%bind after,after_sha=recovery_snapshot_bounded store ~plan_id:r.reclaim_plan_id in
   let final=observe_now()in
   let%bind ()=if fresh final && List.is_empty(reclaim_expired after final)&&reclaim_post_matches expected_post after then Ok()else Error "precommit exact post-state/clock/deadline/expired set changed"in
   let receipt=reclaim_receipt_expected r now final after_sha in let bytes=Yojson.Basic.to_string receipt in
   let%bind ()=if String.length bytes<=8192 then Ok()else Error "receipt size limit"in
   let%bind ()=with_stmt store.db "INSERT INTO sa_plan_reclaim_receipt VALUES(?,?,?,?)"(fun stmt->
    let request=reclaim_request_bytes r in
    let%bind ()=bind_values_result "insert causal reclaim receipt" stmt[TEXT r.reclaim_request_id;TEXT(reclaim_digest request);TEXT request;TEXT bytes]in step_done "insert causal reclaim receipt"stmt)in
   let%bind readback=reclaim_lookup store.db r in
   let%bind ()=match readback with Some read when String.equal(Yojson.Basic.to_string read)bytes->Ok()|_->Error "causal reclaim readback mismatch"in
   checkpoint Before_reclaim_commit;
   let last=observe_now()in
   (* Even an adversarial fixture clock must finish before the last state
      proof. No caller callback runs between this read and COMMIT. Physical
      query/commit latency remains a separate external clock-window gap. *)
   let%bind actual_final,actual_final_sha=recovery_snapshot_bounded store ~plan_id:r.reclaim_plan_id in
   if not(fresh last&&Int64.(last>=final)&&List.is_empty(reclaim_expired actual_final last)
      && String.equal after_sha actual_final_sha&&reclaim_post_matches expected_post actual_final)
   then Error "final exact post-state/effect-time check failed"else Ok(Reclaim_committed receipt)
  in
  (match body()with
   | Error e->rollback_refusal e
   | Ok outcome->
    (match Sqlite3.exec store.db "COMMIT"with
     | Sqlite3.Rc.OK->committed:=true;store.transaction_active<-false;checkpoint After_reclaim_commit;Ok outcome
     | _->poison();Error Reclaim_unknown))
 with _->if !committed then Error Reclaim_unknown else rollback_refusal "reclaim operation failed"
module Reclaim_for_development = struct let execute=reclaim_execute end
