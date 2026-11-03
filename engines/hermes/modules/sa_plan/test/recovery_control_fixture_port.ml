(* PRIVATE compiled fixture worker. The same-connection interpreter is built
   from exact Store/kernel fixture bytes plus the source-bound adaptation in
   recovery_control_fixture.ml. This file is never a production entrypoint.
   Temporary resource/checker descriptors close before the bound lifetime.
   Same public SQLite handle owns retained main/WAL/SHM origins. Cooperative
   namespace/custody premises remain; production entrypoints stay closed. *)
module P=Recovery_control_fixture_prepare
module S=Recovery_kernel_fixture
module K=Recovery_kernel
module R=Recovery_resource
module W=Sqlite_write_vfs_fixture
let need=P.need
let ok=P.ok
let text=P.text
let field=P.field
let read=P.read
let write=P.write
let s=P.s
let response status code receipt=Yojson.Basic.to_string(`Assoc[
 "status",s status;"code",s code;"authority",s"FIXTURE_ONLY_NONE_IN_PRODUCTION";"receipt",receipt])
let directory p=need(String.starts_with ~prefix:"/tmp/uos-control-private-" p&&Filename.dirname p="/tmp"&&Unix.realpath p=p)"private directory only";
 let st=Unix.lstat p in need(st.Unix.st_kind=Unix.S_DIR&&st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_perm land 0o077=0)"private owner"
let locator p=let bytes=P.capture p in (* exact private config shape is pinned by the fixture driver, not authority *)
 Yojson.Basic.from_string bytes
let pid directory=let n=int_of_string(String.trim(read(directory^"/worker.pid")))in need(n>1&&n<>Unix.getpid())"PID";n
let absent directory=not(Sys.file_exists(directory^"/worker.pid"))||not(Sys.file_exists("/proc/"^string_of_int(pid directory)))
let resource_binding locator= text locator"binding"
let native locator_path body=
 let l=locator locator_path in need(text l"domain"="PRIVATE_RECOVERY_CONTROL_FIXTURE")"locator scope";
 let dbpath=text l"database"and journalpath=text l"journal"in
 let dir=Filename.dirname locator_path in directory dir;
 need(locator_path=dir^"/locator.json"&&dbpath=dir^"/tasks.sqlite3"&&journalpath=dir^"/owner.sqlite3"
  &&text l"kernel"=dir^"/kernel.json"&&text l"anchor"=dir^"/anchor.json"&&text l"portfolio"=dir^"/portfolio.json")"fixed private resource namespace";
 let marker=dir^"/worker.pid"in
 let c=open_out_bin marker in output_string c(string_of_int(Unix.getpid()));close_out c;Unix.chmod marker 0o600;
 let cfg=ok(K.read_pinned_data ~path:(text l"kernel")~sha256:(text l"kernel_sha256"))in
 let anchor_bytes=P.capture(text l"anchor")in need(K.sha256 anchor_bytes=text l"anchor_sha256")"independent fixture anchor changed";
 let anchor=ok(R.anchor_data anchor_bytes)in
 let j=Yojson.Basic.from_string body in
 need(Yojson.Basic.to_string j=body)"canonical wire";
 let fs=match j with `Assoc fs when List.map fst fs=["operation";"request";"capability";"reviewer_signature";"issuer_signature"]->fs|_->failwith"wire schema"in
 let get k=Yojson.Basic.Util.to_string(List.assoc k fs)in
 let request_bytes=get"request"and capability_bytes=get"capability"and reviewer_signature=get"reviewer_signature"and issuer_signature=get"issuer_signature"in
 let resource_bytes=text l"resource"and resource_reviewer_signature=text l"resource_review"and resource_issuer_signature=text l"resource_issuer"in

 let cap=Yojson.Basic.from_string capability_bytes in
 let report_bytes=read(dir^"/checker.json")in let report=Yojson.Basic.from_string report_bytes in
 need(K.sha256 report_bytes=text cap"evidence_sha256"&&text cap"context_sha256"=text cap"evidence_sha256"
   &&text cap"evidence_sha256"=text l"checker_sha256")"signed checker/resource context";
 let physical=field report"physical_sqlite"in
 need(P.physical dbpath=physical)"signed main/WAL/SHM identities changed";
 let id role=let v=field physical role in W.{device=Int64.of_string(text v"device");inode=Int64.of_string(text v"inode")}in
 let expected=W.{main=id"main";wal=id"wal";shm=id"shm"}in
 (* ALL temporary resource/checker descriptors are closed before bound open.
    No R.close/second SQLite connection may occur inside the bound lifetime. *)
 let check_resource historical=
  let d=ok(R.open_owned dbpath)in Fun.protect ~finally:(fun()->R.close d)(fun()->
  let j=ok(R.open_owned journalpath)in Fun.protect ~finally:(fun()->R.close j)(fun()->
   if historical then(
    let h=ok(R.verify_history anchor ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature ~resource_bytes ~resource_reviewer_signature ~resource_issuer_signature)in
    ignore(ok(R.check_history_boundary h ~database:d ~journal:j)))else(
    let e=ok(R.verify anchor ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature ~resource_bytes ~resource_reviewer_signature ~resource_issuer_signature)in
    ignore(ok(R.check_effect_boundary e ~database:d ~journal:j)))))in
 let history=get"operation"="inspect"in
 need(history||get"operation"="commit")"operation";
 check_resource history;
 if not history then ignore(P.check_saved l request_bytes);
 let fresh=if history then None else Some(ok(K.verify cfg ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature))in
 let historical=if history then Some(ok(K.verify_history cfg ~request_bytes ~capability_bytes ~reviewer_signature ~issuer_signature))else None in
 let config=Yojson.Basic.from_string(P.capture(text l"kernel"))and aj=Yojson.Basic.from_string anchor_bytes in
 let boundary()=try
  (match fresh with Some e->ignore(ok(K.still_valid e))|None->());
  P.source_boundary l;
  List.iter(fun(path,pin)->need(P.hash path=pin)"source/process pin changed")
   [text l"worker",text config"worker_sha256";text l"guardian",text config"guardian_sha256";
    text l"source_root"^"/engines/hermes/modules/sa_plan/sa_plan_store.ml",text config"source_sha256";
    text l"launcher",text aj"launcher_sha256";text l"journal_worker",text aj"journal_worker_sha256";
    text l"source_root"^"/apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_owner.gleam",text aj"owner_source_sha256"];
  Ok()with _->Error"signed source/clock boundary refused"in
 if not history then ignore(ok(boundary()));
 if Sys.file_exists(dir^"/lock-ready")then(match fresh with Some e->
  let clock=ok(K.still_valid e)in write(dir^"/before-begin")(Yojson.Basic.to_string(`Assoc["utc_ns",s(Int64.to_string clock.utc_ns);"mono_ns",s(Int64.to_string clock.mono_ns)]))|None->());
 let session=match W.open_existing ~directory:dir ~basename:"tasks.sqlite3"~expected with Ok x->x|Error e->failwith("BOUND_OPEN_REFUSED_"^W.error_label e)in
 if Sys.file_exists(dir^"/pause_after_open")then(
  write(dir^"/bound-open-ready")"actual retained main/WAL/SHM connection open";
  let until=Unix.gettimeofday()+.3. in
  while not(Sys.file_exists(dir^"/release_after_open"))&&Unix.gettimeofday()<until do ignore(Unix.select[][][]0.001)done);
 let result=W.with_private_db session(fun db->
  let store=S.{db;closed=false;transaction_active=false;schema_version=7}in
  let outcome=if history then(try
    P.sql db"BEGIN";
    let h=Option.get historical in let r=S.cap_request_bytes request_bytes in
    let receipt=ok(S.cap_lookup_digests store ~evidence:(K.historical_evidence_sha256 h)~capability:(K.historical_capability_sha256 h)r)in
    let bound=P.control_lookup db r.S.reclaim_request_id(resource_binding l)in P.sql db"COMMIT";
    Ok(match receipt,bound with Some r,true->response"HISTORICAL""COMMITTED_FACT_ONLY"r|_->response"HOLD""ABSENT_RECONCILE_ONLY"`Null)
   with _->
    (* Malformed history is refusal only after actual read transaction cleanup.
       VFS poison/failed rollback still causes Unknown and process retirement. *)
    if Sqlite3.exec db"ROLLBACK"=Sqlite3.Rc.OK then Ok(response"HOLD""HISTORY_MISMATCH"`Null)
    else Error"HISTORY_CLEANUP_UNKNOWN")else(
    P.check_schema db;
    if Sys.file_exists(dir^"/kill_before")then(
     Sqlite3.create_fun0 db"private_control_block"(fun()->write(dir^"/fault-ready")"first actual claim observed; second uncommitted";while true do Unix.sleep 60 done;Sqlite3.Data.NULL);
     P.sql db"CREATE TEMP TRIGGER private_partial BEFORE UPDATE ON sa_plan_task WHEN OLD.id='OI02E_RELEASE_AUTHORITY_PREPARATION' AND (SELECT attempt FROM sa_plan_task WHERE id='OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT')=2 BEGIN SELECT private_control_block(); END");
    let checked_boundary()=match boundary()with Error _ as e->e|Ok()->
      (match W.snapshot session with Ok observed when W.identities observed=expected->Ok()|_->Error"retained SQLite resource identity changed")in
    match S.control_execute store(Option.get fresh)~boundary:checked_boundary ~record_binding:(resource_binding l)with
    |Ok(S.Cap_committed r)->Ok(response"COMMITTED""FIXTURE_COMMIT"r)
    |Ok(S.Cap_historical r)->Ok(response"HISTORICAL""NO_NEW_PERMISSION"r)
    |Error S.Reclaim_unknown->Error"UNKNOWN"
    |Error(S.Reclaim_refused _)->Ok(response"HOLD""REFUSED_ROLLBACK"`Null))in
  if store.S.closed then W.Unknown else W.Known outcome)in
 let observed=match W.snapshot session with Ok o->Some(W.diagnostics o)|_->None in
 if not(Sys.file_exists(dir^"/bound-observation.json"))then write(dir^"/bound-observation.json")
  (Yojson.Safe.to_string(`Assoc["sqlite_version",`String(Sqlite3.sqlite_version_info());"diagnostics",Option.value observed~default:`Null]));
 let committed=match result with Ok(Ok b)->(try text(Yojson.Basic.from_string b)"status"="COMMITTED"with _->false)|_->false in
 if committed&&Sys.file_exists(dir^"/kill_after")then(write(dir^"/fault-ready")"actual COMMIT complete; ACK withheld";while true do Unix.sleep 60 done);
 let closed=W.close session in
 match result,closed with Ok(Ok body),Ok()->body|_->response"UNKNOWN""BOUND_RECONCILE_ONLY"`Null
let observe dir=
 directory dir;let store=ok(S.open_existing(dir^"/tasks.sqlite3"))in
 Fun.protect ~finally:(fun()->S.close store)(fun()->`List(List.map(fun(id,_)->match ok(S.find_task store ~plan_id:K.fixed_plan ~id_or_name:id)with Some t->`Int t.S.attempt|_->`Null)K.fixed_members))
let helper dir op value=
 directory dir;
 match op with
 |"pause_after_open"|"release_after_open"->write(dir^"/"^op)"private post-open fault control";`Bool true
 |"swap_wal"|"swap_shm"->let suffix=if op="swap_wal"then"-wal"else"-shm"in
   let path=dir^"/tasks.sqlite3"^suffix in let bytes=Bounded.read ~limit:33554432 path in
   write(path^".clone")bytes;Unix.rename path(path^".old");Unix.rename(path^".clone")path;`Bool true
 |"restore_sidecars"->List.iter(fun suffix->let p=dir^"/tasks.sqlite3"^suffix in if Sys.file_exists(p^".old")then(Unix.rename p(p^".rejected");Unix.rename(p^".old")p))["-wal";"-shm"];`Bool true
 |"observe"->observe dir
 |"bound_observation"->P.json(dir^"/bound-observation.json")
 |"signed_physical"->field(P.json(dir^"/checker.json"))"physical_sqlite"
 |"probe"|"probe_pending"->
  if Sys.file_exists(dir^"/worker.pid")then `Bool(absent dir)else
  P.with_db(dir^"/owner.sqlite3")(fun db->
   let st=Sqlite3.prepare db"SELECT record_json FROM recovery_owner_event ORDER BY sequence LIMIT 2"in
   Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st))(fun()->match Sqlite3.step st with
    |Sqlite3.Rc.DONE->`Bool true
    |Sqlite3.Rc.ROW when op="probe_pending"->let j=Yojson.Basic.from_string(Sqlite3.column_text st 0)in `Bool(text j"phase"="pending"&&Sqlite3.step st=Sqlite3.Rc.DONE)
    |_->`Bool false))
 |"resource_receipt"->P.with_db(dir^"/tasks.sqlite3")(fun db->
    let l=locator(dir^"/locator.json")in `Bool(P.control_lookup db"private-control-request"(resource_binding l)))
 |"nul_receipt"->P.with_db(dir^"/tasks.sqlite3")(fun db->
    let l=locator(dir^"/locator.json")in let expected=resource_binding l^"\000suffix"in
    P.sql db"DROP TRIGGER control_no_update";
    let st=Sqlite3.prepare db"UPDATE control_resource_receipt SET binding_json=? WHERE request_id='private-control-request'"in
    Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st;Core.Gc.keep_alive db)(fun()->
      need(Sqlite3.bind st 1(Sqlite3.Data.TEXT expected)=Sqlite3.Rc.OK&&Sqlite3.step st=Sqlite3.Rc.DONE&&Sqlite3.changes db=1)"actual NUL row mutation");
    P.sql db(List.assoc"control_no_update"P.schema);
    let st=Sqlite3.prepare db"SELECT CAST(binding_json AS BLOB) FROM control_resource_receipt"in
    Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st;Core.Gc.keep_alive db)(fun()->
      need(Sqlite3.step st=Sqlite3.Rc.ROW&&Sqlite3.column st 0=Sqlite3.Data.BLOB expected)"actual full NUL suffix bytes");`Bool true)
 |"lookup_integrity"->P.with_db(dir^"/tasks.sqlite3")(fun db->
    let l=locator(dir^"/locator.json")in
    let accepts f=try `Bool(f db"private-control-request"(resource_binding l))with _->`Bool false in
    `List[accepts P.control_lookup;accepts Control_receipt.lookup])
 |"clone"->
  List.iter(fun file->let p=dir^"/"^file in let bytes=Bounded.read ~limit:33554432 p in
    let before=Unix.lstat p in let q=p^".clone"in write q bytes;need(read q=bytes)"clone equality";
    let after=Unix.lstat q in need(before.Unix.st_dev=after.Unix.st_dev&&before.Unix.st_ino<>after.Unix.st_ino)"clone physical inequality";
    Unix.rename q p)["tasks.sqlite3";"tasks.sqlite3-wal";"tasks.sqlite3-shm";"owner.sqlite3"];`Bool true
 |"source"->let p=dir^"/source-evidence/AGENTS.md"in let bytes=read p in Unix.unlink p;write p(bytes^"\nPRIVATE FIXTURE SOURCE DRIFT\n");`Bool true
 |"fourth"->P.with_db(dir^"/tasks.sqlite3")(fun db->P.sql db"UPDATE sa_plan_task SET state='executing',worker='fixture-fourth',attempt=1,lease_until_ns=1 WHERE id='CONTROL_SENTINEL'");`Bool true
 |"epoch"->let l=locator(dir^"/locator.json")in let p=text l"anchor"in let j=Yojson.Basic.from_string(read p)in
   let b=Yojson.Basic.to_string(P.set j"epoch"(s"2"))in Unix.unlink p;write p b;`Bool true
 |"kill_before"|"kill_after"->write(dir^"/"^op)"fixture-only fault";`Bool true
 |"kill"->let n=pid dir in
   let c=open_in_bin("/proc/"^string_of_int n^"/cmdline")in
   let cmd=Fun.protect ~finally:(fun()->close_in c)(fun()->let b=Bytes.create 16385 in let count=input c b 0 16385 in need(count<16385)"proc bound";Bytes.sub_string b 0 count)in
   need(String.contains cmd '\000'&&Record.contains cmd(dir^"/locator.json"))"fixture PID provenance";
   Unix.kill n Sys.sigkill;`Bool true
 |"lock"->need(value>=1&&value<=3000)"lock bound";
   P.with_db(dir^"/tasks.sqlite3")(fun db->P.sql db"BEGIN IMMEDIATE";write(dir^"/lock-ready")"locked";ignore(Unix.select[][][](float_of_int value/.1000.));P.sql db"ROLLBACK");`Bool true
 |_->failwith"private helper operation"
let ()=
 let b=try
  need(Array.length Sys.argv=2)"fixture argv";
  let h=really_input_string stdin 4 in let n=ref 0 in String.iter(fun c->n:=(!n lsl 8)lor Char.code c)h;
  need(!n>0&& !n<=65536)"frame bound";let body=really_input_string stdin !n in
  (try ignore(input_char stdin);failwith"trailing frame"with End_of_file->());
  let loc=Sys.argv.(1)in
  let j=Bounded.json_text body in
  let op=text j"operation"in
  if op="commit"||op="inspect"then native loc body else(
  need(List.mem op["prepare";"observe";"probe";"probe_pending";"resource_receipt";"bound_observation";"signed_physical"])"ordinary helper operation only";
  let value=Yojson.Basic.Util.to_int(field j"value")in
  need(P.fixture_persist())"private persistent-WAL helper initializer";
  let result=if op="prepare"then P.prepare(P.json loc)value else helper loc op value in
  Yojson.Basic.to_string result)
 with e-> response"HOLD"("FIXTURE_REFUSED_"^Printexc.to_string e)`Null in
 let n=String.length b in for i=3 downto 0 do output_char stdout(Char.chr((n lsr(8*i))land 255))done;output_string stdout b;flush stdout
