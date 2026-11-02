(* Test-only private SQLite/Ed25519 fixture service. Fixed NON-SECRET R/I seed
   vectors. No real keys, canonical DB, production paths or authority. *)
module K=Recovery_kernel
module S=Recovery_kernel_fixture
let ok=function Ok x->x|Error _->failwith"fixture unavailable"
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in if n>33554432 then failwith"filebound";really_input_string c n)
let write p b=let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect ~finally:(fun()->close_out c)(fun()->output_string c b)
let sha p=K.sha256(read p)
let s x=`String x
let hex str=String.concat""(List.init(String.length str)(fun i->Printf.sprintf"%02x"(Char.code str.[i])))
let key c=ok(Mirage_crypto_ec.Ed25519.priv_of_octets(String.make 32 c))
let public c=hex(Mirage_crypto_ec.Ed25519.pub_to_octets(Mirage_crypto_ec.Ed25519.pub_of_priv(key c)))
let signer subject session kid seed=`Assoc["subject",s subject;"session",s session;"kid",s kid;"public_key_hex",s(public seed)]
let sign seed msg=hex(Mirage_crypto_ec.Ed25519.sign ~key:(key seed)msg)
let prepare ttl=
 if ttl<300||ttl>60000 then failwith"ttl";
 let own=Unix.realpath(Filename.dirname Sys.executable_name)in
 let worker=Filename.concat own"recovery_owner_fixture_wrapper.exe"and guardian=Filename.concat own"recovery_fixture_guardian.exe"in
 let journal_worker=Filename.concat(Filename.dirname own)"recovery_owner_journal_port.exe"in
 let directory=Filename.temp_file"uos-recovery-owner-fixture-"""in Sys.remove directory;Unix.mkdir directory 0o700;
 let database=Filename.concat directory"tasks.sqlite3"and journal=Filename.concat directory"owner.sqlite3"and cfgpath=Filename.concat directory"launcher.json"and ready=Filename.concat directory"effect-ready"in
 let clock=ok(K.native_clock())in
 let db=ok(S.open_db database)in Unix.chmod database 0o600;ignore(ok(S.initialize_cap_fixture db));
 ignore(ok(S.create_plan db ~id:K.fixed_plan ~name:"private/recovery-owner"~title:"fixture"~now_ns:clock.utc_ns));
 let lease=Int64.sub clock.utc_ns 2000000000L in
 List.iter(fun(id,worker)->ignore(ok(S.create_task db ~plan_id:K.fixed_plan ~id ~name:("private/"^id)~title:id ~parent_id:None ~dependencies:[] ~priority:0~now_ns:clock.utc_ns));
  ignore(ok(S.claim_task db ~plan_id:K.fixed_plan ~task_id:id ~worker ~now_ns:(Int64.sub lease 1000000000L)~lease_ns:1000000000L)))K.fixed_members;
 let _,snapshot=ok(S.recovery_snapshot_bounded db ~plan_id:K.fixed_plan)in S.close db;
 let journal_db=Sqlite3.db_open journal in Unix.chmod journal 0o600;
 Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close journal_db);Core.Gc.keep_alive journal_db)(fun()->
  List.iter(fun sql->if Sqlite3.exec journal_db sql<>Sqlite3.Rc.OK then failwith"journalinit")(["PRAGMA journal_mode=WAL";"PRAGMA synchronous=FULL"]@Recovery_owner_journal.schema_statements));
 let cfg=Yojson.Basic.to_string(`Assoc["domain",s"uos.sa-plan.recovery-launcher-data.v1";"profile",s K.profile;"host",s(clock.host^".tail55d152.ts.net");"boot",s clock.boot;"epoch",s"1";
  "source_sha256",s(sha(Filename.concat(Filename.dirname own)"sa_plan_store.ml"));"worker_sha256",s(sha worker);"guardian_sha256",s(sha guardian);
  "reviewer",signer"fixture-reviewer""fixture-review-session""fixture-review-key"'R';"issuer",signer"fixture-issuer""fixture-issuer-session""fixture-issuer-key"'I'])in write cfgpath cfg;
 let deadline_ms=Int64.div(Int64.add clock.utc_ns 120000000000L)1000000L in
 let r=S.{reclaim_request_id="fixture-owner-request";reclaim_plan_id=K.fixed_plan;expected_snapshot_sha256=snapshot;expired_tasks=List.map(fun(id,worker)->S.{reclaim_task_id=id;old_worker=worker;old_attempt=1;old_lease_until_ns=lease})K.fixed_members;reclaim_lease_ns=10000000000L;request_deadline_ns=Int64.mul deadline_ms 1000000L}in
 let request=S.reclaim_request_bytes r in
 let get k=Yojson.Basic.Util.member k(Yojson.Basic.from_string cfg)in
 let until=Int64.add clock.utc_ns(Int64.mul(Int64.of_int ttl)1000000L)in
 let mono_until=Int64.add clock.mono_ns(Int64.mul(Int64.of_int(ttl-10))1000000L)in
 let cap=Yojson.Basic.to_string(`Assoc[
  "domain",s"uos.sa-plan.reclaim-three.effect-capability.v1";"profile",s K.profile;"configuration_sha256",s(K.sha256 cfg);"request_sha256",s(K.sha256 request);
  "evidence_sha256",s(String.make 64 'e');"context_sha256",s(String.make 64 'c');"proposal_sha256",s(String.make 64 'a');"portfolio_sha256",s(String.make 64 'b');"selection_sha256",s(String.make 64 'd');"factual_review_sha256",s(String.make 64 'f');
  "source_sha256",get"source_sha256";"worker_sha256",get"worker_sha256";"guardian_sha256",get"guardian_sha256";
  "reviewer",s"fixture-reviewer";"reviewer_session",s"fixture-review-session";"issuer",s"fixture-issuer";"issuer_session",s"fixture-issuer-session";
  "host",get"host";"boot",s clock.boot;"clock_domain",s clock.domain;"epoch",s"1";
  "issued_utc_ns",s(Int64.to_string(Int64.sub clock.utc_ns 1000000000L));"expires_utc_ns",s(Int64.to_string until);
  "issued_mono_ns",s(Int64.to_string(Int64.sub clock.mono_ns 1000000000L));"expires_mono_ns",s(Int64.to_string mono_until)])in
 let reviewer=sign 'R'(K.review_message cap)in let issuer=sign 'I'(K.issuer_message cap ~reviewer_signature:reviewer)in
 let body operation=Yojson.Basic.to_string(`Assoc["operation",s operation;"request",s request;"capability",s cap;"reviewer_signature",s reviewer;"issuer_signature",s issuer])in
 let locator_path=Filename.concat directory"native-locator.json"in
 write locator_path(Yojson.Basic.to_string(`List[s cfgpath;s(K.sha256 cfg);s database;s ready]));
 let factual=Yojson.Basic.to_string(`Assoc["request_id",s r.reclaim_request_id;"plan",s K.fixed_plan;"snapshot_sha256",s("sha256:"^snapshot);
  "members",`List(List.map(fun t->`Assoc["task_id",s t.S.reclaim_task_id;"worker",s t.S.old_worker;"old_attempt",`Int 1;"old_lease_ns",s(Int64.to_string lease);"lease_ms",`Int 10000])r.expired_tasks);
  "deadline_utc_ms",`Int(Int64.to_int deadline_ms)])in
 `Assoc["directory",s directory;"guardian",s guardian;"guardian_sha256",s(sha guardian);"worker",s worker;"worker_sha256",s(sha worker);
  "journal_worker",s journal_worker;"journal_worker_sha256",s(sha journal_worker);"journal_database",s journal;
  "native_locator",s locator_path;
  "factual_request",s factual;"context_sha256",s(String.make 64 'c');"commit_body",s(body"commit");"inspect_body",s(body"inspect");"expires_utc_ns",s(Int64.to_string until);"marker",s(ready^".pid")]
let observe directory=
 let db=ok(S.open_existing(Filename.concat directory"tasks.sqlite3"))in
 Fun.protect ~finally:(fun()->S.close db)(fun()->`List(List.map(fun(id,_)->match ok(S.find_task db ~plan_id:K.fixed_plan ~id_or_name:id)with Some t->`Int t.attempt|_->`Null)K.fixed_members))
let probe directory ~created=
 let marker=Filename.concat directory"effect-ready.pid"in
 if not(Sys.file_exists marker)then(
  let db=Sqlite3.db_open ~mode:`READONLY(Filename.concat directory"owner.sqlite3")in
  Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db);Core.Gc.keep_alive db)(fun()->
   let st=Sqlite3.prepare db"SELECT sequence,record_json FROM recovery_owner_event ORDER BY sequence LIMIT 2"in
   Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st)(fun()->
    match Sqlite3.step st with
    |Sqlite3.Rc.DONE->`Bool true
    |Sqlite3.Rc.ROW when created&&Sqlite3.column st 0=Sqlite3.Data.INT 1L->
      let j=Yojson.Basic.from_string(Sqlite3.column_text st 1)in
      let pending=Yojson.Basic.Util.(member"phase"j=`String"pending")in
      `Bool(pending&&Sqlite3.step st=Sqlite3.Rc.DONE)
    |_->`Bool false)))else
 let pid=int_of_string(String.trim(read marker))in
 `Bool(not(Sys.file_exists("/proc/"^string_of_int pid)))
let run directory bytes=
 let open Yojson.Basic.Util in let j=Yojson.Basic.from_string bytes in match to_string(member"operation"j)with
 |"prepare"->prepare(to_int(member"ttl_ms"j))
 |"observe"->observe directory
 |"probe"->probe directory ~created:false
 |"probe_pending_created"->probe directory ~created:true
 |"corrupt_journal"->let db=Sqlite3.db_open(Filename.concat directory"owner.sqlite3")in
   Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db);Core.Gc.keep_alive db)(fun()->`Bool(Sqlite3.exec db"DROP TRIGGER recovery_owner_no_update"=Sqlite3.Rc.OK))
 |"hold_lock"->let path=Filename.concat directory"tasks.sqlite3"in let db=Sqlite3.db_open path in
   if Sqlite3.exec db"BEGIN IMMEDIATE"<>Sqlite3.Rc.OK then failwith"fixture lock";
   write(Filename.concat directory"lock-ready")(string_of_int(Unix.getpid()));while true do Unix.sleep 60 done;`Null
 |_->failwith"fixture operation"
let ()=
 let result=try
  if Array.length Sys.argv<>2 then failwith"fixtureargv";
  let h=really_input_string stdin 4 in let n=ref 0 in String.iter(fun c->n:=(!n lsl 8)lor Char.code c)h;
  if !n<1|| !n>16384 then failwith"fixtureframe";
  let b=really_input_string stdin !n in (try ignore(input_char stdin);failwith"trailing"with End_of_file->());run Sys.argv.(1)b
 with _->`Assoc["fixture_error",`Bool true]in
 let b=Yojson.Basic.to_string result in let n=String.length b in for i=3 downto 0 do output_char stdout(Char.chr((n lsr(8*i))land 255))done;output_string stdout b;flush stdout
