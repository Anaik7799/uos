(* Development-only SQLite fixtures. No ingress, grants or canonical DB. *)
module S=Reclaim_fixture
module Production=Sa_plan.Store
let checks=ref 0
let check label value=incr checks;if not value then failwith label
let ok=function Ok x->x|Error _->failwith "unexpected refusal"
let fixture ?(schema=true) f=
 let path=Filename.temp_file "uos-three-reclaim-" ".sqlite3"in
 let s=ok(S.open_db path)in
 Fun.protect ~finally:(fun()->S.close s;List.iter(fun p->if Sys.file_exists p then Sys.remove p)[path;path^"-wal";path^"-shm"])(fun()->
 if schema then ignore(ok(S.initialize_reclaim_receipts_for_development s));
 ignore(ok(S.create_plan s ~id:"p" ~name:"private/reclaim" ~title:"fixture" ~now_ns:1L));
 List.iter(fun id->ignore(ok(S.create_task s ~plan_id:"p" ~id ~name:("private/"^id) ~title:id ~parent_id:None ~dependencies:[] ~priority:0 ~now_ns:1L));
  ignore(ok(S.claim_task s ~plan_id:"p" ~task_id:id ~worker:("worker-"^id) ~now_ns:10L ~lease_ns:10L)))["a";"b";"c"];
 let _,sha=ok(S.recovery_snapshot_bounded s ~plan_id:"p")in
 let old=List.map(fun id->S.{reclaim_task_id=id;old_worker="worker-"^id;old_attempt=1;old_lease_until_ns=20L})["a";"b";"c"]in
 let r=S.{reclaim_request_id="private-request";reclaim_plan_id="p";expected_snapshot_sha256=sha;expired_tasks=old;reclaim_lease_ns=100L;request_deadline_ns=1000L}in
 f path s r)
let run ?(clock=(fun()->30L)) ?(hook=(fun _->())) s r=
 S.Reclaim_for_development.execute s r ~observe_now:clock ~checkpoint:hook
let snap s=snd(ok(S.recovery_snapshot_bounded s ~plan_id:"p"))
let refused=function Error(S.Reclaim_refused _)->true|_->false
let raw path sql=let d=Sqlite3.db_open path in Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close d);Core.Gc.keep_alive d)(fun()->
 if Sqlite3.exec d sql<>Sqlite3.Rc.OK then failwith(Sqlite3.errmsg d))
let read_bounded p=
 let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->
  let n=in_channel_length c in if n>1048576 then failwith "fixture source/log bound"else really_input_string c n)
let executable_directory()=Filename.dirname(Unix.realpath Sys.executable_name)
let public_api_probe source=
 let file=Filename.temp_file "uos-reclaim-api-" ".ml"in let log=file^".log"and out=file^".cmo"in
 Fun.protect ~finally:(fun()->List.iter(fun p->if Sys.file_exists p then Sys.remove p)[file;log;out;Filename.chop_extension out^".cmi"])(fun()->
  let c=open_out_bin file in output_string c source;close_out c;
  let library=Filename.dirname(executable_directory())^"/.sa_plan.objs/byte"in
  let prefix="/home/an/NAS-setup/uos/toolchains/opam-ocaml"in
  let env=Array.of_list["PATH="^prefix^"/bin:/home/an/NAS-setup/uos/toolchains/nix-profile/bin:/usr/bin:/bin";"OCAMLPATH="^prefix^"/lib"]in
  let input=Unix.openfile "/dev/null"[Unix.O_RDONLY]0 and output=Unix.openfile "/dev/null"[Unix.O_WRONLY]0 and errors=Unix.openfile log[Unix.O_CREAT;Unix.O_TRUNC;Unix.O_WRONLY]0o600 in
  let pid=Fun.protect ~finally:(fun()->List.iter Unix.close[input;output;errors])(fun()->
   Unix.create_process_env "/usr/bin/timeout"[|"timeout";"--kill-after=1s";"5s";prefix^"/bin/ocamlfind";"ocamlc";"-package";"core,digestif,sqlite3,yojson";"-I";library;"-c";file;"-o";out|]env input output errors)in
  let _,status=Unix.waitpid[]pid in status,read_bounded log)
let ()=
 let directory=executable_directory()in
 let production_source=read_bounded(Filename.dirname directory^"/sa_plan_store.ml")and extension=read_bounded(directory^"/reclaim_fixture_extension.ml")in
 check "test variant exact production bytes plus extension"(read_bounded(directory^"/reclaim_fixture.ml")="open Sa_plan__\n"^production_source^extension);
 check "production source contains no fixture writer alias"(not(Astring.String.is_infix ~affix:"let reclaim_execute" production_source));
 let status,_=public_api_probe "module S=Sa_plan.Store\nlet _=S.reclaim_three\n"in
 check "actual production API positive compile control"(status=Unix.WEXITED 0);
 List.iter(fun(symbol,source)->let status,errors=public_api_probe source in
  check "actual production API rejects test effect interface"(status=Unix.WEXITED 2&&Astring.String.is_infix ~affix:symbol errors))
 ["Reclaim_for_development","module S=Sa_plan.Store\nlet _=S.Reclaim_for_development.execute\n";
  "initialize_reclaim_receipts_for_development","module S=Sa_plan.Store\nlet _=S.initialize_reclaim_receipts_for_development\n";
  "Reclaim_for_development","let _=Sa_plan__Sa_plan_store.Reclaim_for_development.execute\n"];
 fixture(fun path s r->
  let before=snap s in
  let p=ok(Production.open_existing path)in
  let request=Production.{reclaim_request_id=r.S.reclaim_request_id;reclaim_plan_id=r.S.reclaim_plan_id;expected_snapshot_sha256=r.S.expected_snapshot_sha256;
   expired_tasks=List.map(fun t->Production.{reclaim_task_id=t.S.reclaim_task_id;old_worker=t.S.old_worker;old_attempt=t.S.old_attempt;old_lease_until_ns=t.S.old_lease_until_ns})r.S.expired_tasks;
   reclaim_lease_ns=r.S.reclaim_lease_ns;request_deadline_ns=r.S.request_deadline_ns}in
  Fun.protect ~finally:(fun()->Production.close p)(fun()->
   check "production entrypoint unavailable without capability"(match Production.reclaim_three p request with Error(Production.Reclaim_refused _)->true|_->false));
  check "unavailable production call no effects"(before=snap s);
  let ack=ok(run s r)in
  check "known commit"(match ack with S.Reclaim_committed _->true|_->false);
  check "all three attempts increment"(List.for_all(fun id->match ok(S.find_task s ~plan_id:"p" ~id_or_name:id)with Some t->t.attempt=2&&t.worker=Some("worker-"^id)|_->false)["a";"b";"c"]);
  check "snapshot changed"(before<>snap s);
  check "historical exact replay"(match ok(run ~clock:(fun()->5000L)s r)with S.Reclaim_historical _->true|_->false);
  check "historical replay no new attempt"(match ok(S.find_task s ~plan_id:"p" ~id_or_name:"a")with Some t->t.attempt=2|_->false);
  check "conflicting ID refuses"(refused(run s {r with reclaim_lease_ns=101L}));
  check "readonly reconciliation exact"(Option.is_some(ok(S.reconcile_reclaim s r)));
  S.close s;let s2=ok(S.open_existing path)in
  Fun.protect ~finally:(fun()->S.close s2)(fun()->check "receipt survives reopen"(Option.is_some(ok(S.reconcile_reclaim s2 r)))));
 fixture ~schema:false(fun _ s r->let before=snap s in check "absent schema failclosed"(refused(run s r));check "absent schema no effects"(before=snap s));
 List.iter(fun change->fixture(fun _ s r->let before=snap s in check "stale/invalid request refuses"(refused(run s(change r)));check "refusal leaves all rows"(snap s=before)))[
  (fun r->{r with S.expected_snapshot_sha256=String.make 64 '0'});
  (fun r->{r with S.expired_tasks=List.tl r.S.expired_tasks});
  (fun r->{r with S.expired_tasks=r.S.expired_tasks@[List.hd r.S.expired_tasks]});
  (fun r->{r with S.expired_tasks=List.map(fun t->{t with S.old_worker="other"})r.S.expired_tasks});
  (fun r->{r with S.expired_tasks=List.map(fun t->{t with S.old_attempt=2})r.S.expired_tasks});
  (fun r->{r with S.expired_tasks=List.map(fun t->{t with S.old_lease_until_ns=19L})r.S.expired_tasks});
  (fun r->{r with S.expired_tasks=List.map(fun t->{t with S.old_lease_until_ns=0L})r.S.expired_tasks});
  (fun r->{r with S.reclaim_lease_ns=0L});
  (fun r->{r with S.request_deadline_ns=30L})];
 fixture(fun _ s r->let before=snap s in check "not yet expired refuses"(refused(run ~clock:(fun()->19L)s r));check "no partial claim"(before=snap s));
 List.iter(fun mutation->fixture(fun path s r->
  ignore(ok(S.create_task s ~plan_id:"p" ~id:"d" ~name:"private/d" ~title:"d" ~parent_id:None ~dependencies:[] ~priority:0 ~now_ns:1L));
  let r={r with S.expected_snapshot_sha256=snap s}in let before=snap s in
  raw path("CREATE TRIGGER fixture_corrupt_after_claim AFTER UPDATE ON sa_plan_task WHEN OLD.id='a' BEGIN "^mutation^"; END");
  check "actual trigger wrong postgoal refuses"(refused(run s r));
  check "trigger corruption all rows rollback"(before=snap s);
  check "trigger corruption no causal receipt"(ok(S.reconcile_reclaim s r)=None)))
 ["UPDATE sa_plan_task SET worker='other-worker' WHERE id='a'";
  "UPDATE sa_plan_task SET state='available' WHERE id='a'";
  "UPDATE sa_plan_task SET lease_until_ns=999 WHERE id='a'";
  "UPDATE sa_plan_task SET attempt=3 WHERE id='a'";
  "UPDATE sa_plan_task SET result='fixture-corruption' WHERE id='a'";
  "UPDATE sa_plan_task SET worker='other-worker' WHERE id='d'"];
 fixture(fun _ s r->let before=snap s in
  let hook=function S.Before_reclaim_commit->ignore(ok(S.release_task s ~plan_id:"p" ~task_id:"a" ~worker:"worker-a" ~expected_attempt:2 ~now_ns:31L))|_->()in
  check "last hook postgoal mutation refuses"(refused(run ~hook s r));check "last hook rolls back receipt and claims"(before=snap s));
 fixture(fun _ s r->let before=snap s in let calls=ref 0 in
  let clock()=incr calls;if !calls=3 then ignore(ok(S.release_task s ~plan_id:"p" ~task_id:"a" ~worker:"worker-a" ~expected_attempt:2 ~now_ns:30L));30L in
  check "last clock callback mutation refuses"(refused(run ~clock s r));
  check "last clock callback task changes rollback"(before=snap s);
  check "last clock callback receipt rollback"(ok(S.reconcile_reclaim s r)=None));
 fixture(fun path s r->let before=snap s in
  raw path "CREATE TRIGGER fixture_after_receipt AFTER INSERT ON sa_plan_reclaim_receipt BEGIN UPDATE sa_plan_task SET worker='post-receipt-corruption' WHERE id='a'; END";
  check "receipt trigger postgoal mutation refuses"(refused(run s r));
  check "receipt trigger rolls back all claims"(before=snap s);
  check "receipt trigger rolls back inserted receipt"(ok(S.reconcile_reclaim s r)=None));
 List.iter(fun sql->fixture(fun path s r->
  raw path sql;
  let r={r with S.expected_snapshot_sha256=snap s}in let before=snap s in
  check "changed old tuple/set refuses even with current digest"(refused(run s r));
  check "changed tuple/set refusal no effects"(before=snap s)))
 ["UPDATE sa_plan_task SET worker='new-owner' WHERE id='a'";
  "UPDATE sa_plan_task SET attempt=2 WHERE id='a'";
  "UPDATE sa_plan_task SET lease_until_ns=21 WHERE id='a'";
  "UPDATE sa_plan_task SET state='completed' WHERE id='a'";
  "DELETE FROM sa_plan_task WHERE id='a'"];
 fixture(fun path s r->
  raw path "INSERT INTO sa_plan_task(plan_id,id,name,ordinal,task_type,title,state,worker,attempt,lease_until_ns) VALUES('p','d','private/d',4,'task','d','executing','worker-d',1,20)";
  let r={r with S.expected_snapshot_sha256=snap s}in let before=snap s in
  check "extra expired task refuses complete set"(refused(run s r));check "extra task no effects"(before=snap s));
 fixture(fun _ s r->check "exclusive expiry boundary succeeds"(Result.is_ok(run ~clock:(fun()->20L)s r)));
 fixture(fun path s r->
  raw path "UPDATE sa_plan_task SET lease_until_ns=0";
  let r={r with S.expected_snapshot_sha256=snap s;expired_tasks=List.map(fun t->{t with S.old_lease_until_ns=0L})r.S.expired_tasks}in
  let before=snap s in check "matching zero lease tuple is invalid"(refused(run s r));check "zero lease refuses without effects"(before=snap s));
 fixture(fun path s r->
  raw path "UPDATE sa_plan_task SET lease_until_ns=1";
  let r={r with S.expected_snapshot_sha256=snap s;expired_tasks=List.map(fun t->{t with S.old_lease_until_ns=1L})r.S.expired_tasks}in
  check "positive minimum old lease accepted"(Result.is_ok(run ~clock:(fun()->1L)s r)));
 fixture(fun _ s r->let before=snap s in check "partial failure rolls back"(refused(run ~hook:(function S.After_reclaim_claim 1->failwith "fixture failure"|_->())s r));check "rollback all3"(before=snap s);check "rollback no receipt"(ok(S.reconcile_reclaim s r)=None));
 fixture(fun _ s r->let before=snap s in let times=ref[30L;1000L]in let clock()=match !times with x::xs->times:=xs;x|[]->1000L in
  check "precommit deadline refuses"(refused(run ~clock s r));check "late deadline rollback"(before=snap s));
 fixture(fun _ s r->let before=snap s in let times=ref[30L;31L;1000L]in let clock()=match !times with x::xs->times:=xs;x|[]->1000L in
  check "final deadline after receipt insertion refuses"(refused(run ~clock s r));check "final deadline task rollback"(before=snap s);
  check "final deadline receipt rollback"(ok(S.reconcile_reclaim s r)=None));
 fixture(fun _ s r->let before=snap s in let times=ref[30L;29L]in let clock()=match !times with x::xs->times:=xs;x|[]->29L in
  check "regressing clock refuses"(refused(run ~clock s r));check "clock rollback"(before=snap s));
 fixture(fun _ s r->
  ignore(ok(S.create_task s ~plan_id:"p" ~id:"d" ~name:"private/d" ~title:"d" ~parent_id:None ~dependencies:[] ~priority:0 ~now_ns:1L));
  ignore(ok(S.claim_task s ~plan_id:"p" ~task_id:"d" ~worker:"worker-d" ~now_ns:25L ~lease_ns:10L));
  let r={r with S.expected_snapshot_sha256=snap s}in let before=snap s in let times=ref[30L;40L]in
  let clock()=match !times with x::xs->times:=xs;x|[]->40L in
  check "new expiry before commit refuses"(refused(run ~clock s r));check "new expiry rollback"(before=snap s));
 fixture(fun _ s r->
  check "lost ACK unknown"(match run ~hook:(function S.After_reclaim_commit->failwith "lost ack"|_->())s r with Error S.Reclaim_unknown->true|_->false);
  check "lost ACK durable reconciliation"(Option.is_some(ok(S.reconcile_reclaim s r))));
 fixture(fun path s r->
  raw path "DROP TRIGGER sa_plan_reclaim_no_delete";
  check "missing append-only trigger refuses"(refused(run s r)));
 fixture ~schema:false(fun _ s _->check "never migrate existing nonempty database"(Result.is_error(S.initialize_reclaim_receipts_for_development s)));
 fixture(fun path s r->
  S.close s;raw path "PRAGMA journal_mode=DELETE";
  let reopened=ok(S.open_existing path)in Fun.protect ~finally:(fun()->S.close reopened)(fun()->
   let before=snap reopened in check "unreviewed durability settings refuse"(refused(run reopened r));
   check "durability refusal no effects"(before=snap reopened)));
 fixture(fun path s r->
  let before=snap s in
  raw path "CREATE TRIGGER fixture_fail_second BEFORE UPDATE ON sa_plan_task WHEN OLD.id='b' BEGIN SELECT RAISE(ABORT,'fixture failure'); END";
  check "SQLite second claim failure refuses"(refused(run s r));check "SQLite failure first claim rollback"(before=snap s));
 fixture(fun path s r->
  raw path "WITH RECURSIVE n(x) AS(VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<256) INSERT INTO sa_plan_reclaim_receipt SELECT 'full-'||x,'bad','{}','{}' FROM n";
  let before=snap s in check "receipt capacity refuses before effects"(refused(run s r));check "capacity no task effects"(before=snap s));
 fixture(fun path s r->
  ignore(ok(run s r));
  List.iter(fun sql->let d=Sqlite3.db_open path in Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close d);Core.Gc.keep_alive d)(fun()->
   check "append-only receipt refuses mutation"(Sqlite3.exec d sql<>Sqlite3.Rc.OK)))["DELETE FROM sa_plan_reclaim_receipt";"UPDATE sa_plan_reclaim_receipt SET request_sha256='bad'";
    "INSERT INTO sa_plan_reclaim_receipt SELECT * FROM sa_plan_reclaim_receipt"]);
 (* Abrupt death while holding the transaction must leave no partial claims or
    causal receipt. The child opens its own SQLite connection after fork. *)
 fixture(fun path s r->
  let before=snap s in S.close s;
  let pid=Unix.fork()in
  if pid=0 then(let child=ok(S.open_existing path)in
   ignore(run ~hook:(function S.After_reclaim_claim 1->Unix._exit 77|_->())child r);Unix._exit 2);
  let _,status=Unix.waitpid[]pid in check "actual crash injection reached first claim"(status=Unix.WEXITED 77);
  let reopened=ok(S.open_existing path)in Fun.protect ~finally:(fun()->S.close reopened)(fun()->
   check "actual crash rolls back all tasks"(before=snap reopened);
   check "actual crash no causal receipt"(ok(S.reconcile_reclaim reopened r)=None)));
 fixture(fun path s r->
  S.close s;let pid=Unix.fork()in
  if pid=0 then(let child=ok(S.open_existing path)in
   ignore(run ~hook:(function S.After_reclaim_commit->Unix._exit 88|_->())child r);Unix._exit 2);
  let _,status=Unix.waitpid[]pid in check "actual ACK loss after durable commit"(status=Unix.WEXITED 88);
  let reopened=ok(S.open_existing path)in Fun.protect ~finally:(fun()->S.close reopened)(fun()->
   check "crash after commit retains causal receipt"(Option.is_some(ok(S.reconcile_reclaim reopened r)));
   check "crash recovery gives historical only"(match ok(run reopened r)with S.Reclaim_historical _->true|_->false)));
 fixture(fun path s r->
  S.close s;
  let spawn()=let pid=Unix.fork()in if pid=0 then(
   let child=ok(S.open_existing path)in
   let code=match run child r with Ok(S.Reclaim_committed _)->0|Ok(S.Reclaim_historical _)->1|_->2 in
   S.close child;Unix._exit code);pid in
  let p1=spawn()and p2=spawn()in
  let _,a=Unix.waitpid[]p1 and _,b=Unix.waitpid[]p2 in
  check "concurrent exact request one commit one historical"(List.sort compare[a;b]=[Unix.WEXITED 0;Unix.WEXITED 1]);
  let reopened=ok(S.open_existing path)in Fun.protect ~finally:(fun()->S.close reopened)(fun()->
   check "concurrent replay increments once"(List.for_all(fun id->match ok(S.find_task reopened ~plan_id:"p" ~id_or_name:id)with Some t->t.attempt=2|_->false)["a";"b";"c"])));
 fixture(fun path s r->
  let before=snap s in S.close s;
  let lock=Sqlite3.db_open path in
  if Sqlite3.exec lock "BEGIN IMMEDIATE"<>Sqlite3.Rc.OK then failwith "fixture lock";
  let ready_r,ready_w=Unix.pipe()and sampled_r,sampled_w=Unix.pipe()in
  let pid=Unix.fork()in
  if pid=0 then(
   Unix.close ready_r;Unix.close sampled_r;
   ignore(Sqlite3.db_close lock);Core.Gc.keep_alive lock;
   let child=ok(S.open_existing path)in
   ignore(Unix.write_substring ready_w "r" 0 1);Unix.close ready_w;
   let result=run ~clock:(fun()->ignore(Unix.write_substring sampled_w "t" 0 1);1000L)child r in
   S.close child;Unix.close sampled_w;Unix._exit(if refused result then 0 else 2));
  Unix.close ready_w;Unix.close sampled_w;
  let buffer=Bytes.create 1 in
  check "waiter reaches invocation"(Unix.read ready_r buffer 0 1=1);Unix.close ready_r;
  let readable,_,_=Unix.select[sampled_r][][]0.03 in
  check "clock not sampled before acquiring writer lock"(readable=[]);
  check "fixture writer unlocks"(Sqlite3.exec lock "COMMIT"=Sqlite3.Rc.OK);
  ignore(Sqlite3.db_close lock);Core.Gc.keep_alive lock;
  let _,status=Unix.waitpid[]pid in Unix.close sampled_r;
  check "late lock sees expired deadline"(status=Unix.WEXITED 0);
  let reopened=ok(S.open_existing path)in Fun.protect ~finally:(fun()->S.close reopened)(fun()->
   check "late lock leaves all claims unchanged"(before=snap reopened)));
 Printf.printf "%d checks PASS fixture_only=true authority=false\n%!" !checks
