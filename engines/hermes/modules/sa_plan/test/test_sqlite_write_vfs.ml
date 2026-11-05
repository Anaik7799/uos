(* PRIVATE real Store vertical: exact production Store + existing test-only
   reclaim interpreter, SAME bound SQLite handle. No production task authority. *)
module W=Sqlite_write_vfs_fixture
module S=Recovery_kernel_fixture
module K=Recovery_kernel
let checks=ref 0
let check label b=if not b then failwith label;incr checks
let ok=function Ok x->x|Error _->failwith"unexpected refusal"
let now()=(ok(K.native_clock())).utc_ns
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in if n>65536 then failwith"fixture bound";really_input_string c n)
let write p bytes=let f=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in Fun.protect ~finally:(fun()->Unix.close f)(fun()->let rec loop n=if n<String.length bytes then let k=Unix.write_substring f bytes n(String.length bytes-n)in if k<=0 then failwith"write"else loop(n+k)in loop 0;Unix.fsync f)
external native_identity : Unix.file_descr -> (int64*int64)option = "caml_uos_main_mapping_retained_identity"
external setup_persist : unit -> bool = "caml_private_write_setup_persist"
let identity p=let f=Unix.openfile p[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in Fun.protect ~finally:(fun()->Unix.close f)(fun()->match native_identity f with Some(device,inode)->W.{device;inode}|_->failwith"identity")
let copy a b=let bytes=let c=open_in_bin a in Fun.protect ~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in if n>33554432 then failwith"copy bound";really_input_string c n)in write b bytes
let child directory mode=
 check"private fixture namespace only"(String.starts_with ~prefix:"/tmp/uos-write-vfs-test-"directory&&Unix.realpath directory=directory);
 let path=directory^"/tasks.sqlite3"in
 let expected=W.{main=identity path;wal=identity(path^"-wal");shm=identity(path^"-shm")}in
 let request=S.cap_request_bytes(read(directory^"/request.json"))in
 let replacements=match mode with "swap-main"->["",0]|"swap-wal"->["-wal",1]|"swap-shm"->["-shm",2]|"swap-all"->["",0;"-wal",1;"-shm",2]|_->[]in
 (* All copy FDs close BEFORE the bound connection acquires POSIX locks. *)
 List.iter(fun(suffix,r)->copy(path^suffix)(directory^"/clone"^string_of_int r))replacements;
 let session=match W.open_existing ~directory ~basename:"tasks.sqlite3" ~expected with Ok s->s|Error e->Printf.eprintf"BOUND_OPEN_REFUSED_%s\n%!"(W.error_label e);exit 2 in
 List.iter(fun(suffix,r)->Unix.rename(path^suffix)(directory^"/old"^string_of_int r);Unix.rename(directory^"/clone"^string_of_int r)(path^suffix))replacements;
 (match Sys.getenv_opt"UOS_PRIVATE_WRITE_FAULT"with Some _->Unix.putenv"UOS_PRIVATE_WRITE_ARMED""1"|None->());
 let borrow f=W.with_private_db session(fun db->
  let store=S.{db;closed=false;transaction_active=false;schema_version=7}in
  let result=f store in if store.closed then W.Unknown else W.Known result)in
 if mode="settings"then(
  ignore(ok(W.with_private_db session(fun db->
   List.iter(fun sql->check("critical SQL setting refused "^sql)(Sqlite3.exec db sql=Sqlite3.Rc.AUTH))
    ["PRAGMA synchronous=OFF";"PRAGMA main.synchronous=OFF";"PRAGMA wal_autocheckpoint=1";"PRAGMA journal_mode=DELETE";"PRAGMA mmap_size=4096";"PRAGMA foreign_keys=OFF";"PRAGMA temp_store=FILE";"PRAGMA wal_checkpoint(TRUNCATE)";"PRAGMA wal_checkpoint(RESTART)"];
   List.iter(fun(sql,expected)->let st=Sqlite3.prepare db sql in Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st)(fun()->check("actual guarded setting "^sql)(Sqlite3.step st=Sqlite3.Rc.ROW&&Sqlite3.column_int st 0=expected)))
    ["PRAGMA synchronous",2;"PRAGMA wal_autocheckpoint",0;"PRAGMA mmap_size",0];
   W.Known())));print_endline"CRITICAL_SQL_SETTINGS_LOCKED");
 let called=ref false and fresh=ref false in
 if mode="reconcile"then(
  match borrow(fun store->called:=true;S.reconcile_reclaim store request)with
  |Ok(Ok(Some _))->print_endline"HISTORICAL_FACT_ONLY_NO_FORWARD_EXECUTION"
  |Ok(Ok None)->print_endline"ABSENT_FACT_UNKNOWN_STAYS_BLOCKED_NO_RETRY"
  |_->print_endline"UNKNOWN_RECONCILE_ONLY")
 else(
  let result=borrow(fun store->called:=true;S.reclaim_execute store request ~observe_now:now ~checkpoint:(fun _->()))in
  match result with
  |Ok(Ok(S.Reclaim_committed _))->fresh:=true;print_endline"COMMITTED_SAME_BOUND_CONNECTION"
  |Ok(Ok(S.Reclaim_historical _))->print_endline"HISTORICAL_NO_NEW_EFFECT"
  |Ok(Error(S.Reclaim_refused _))->print_endline"REFUSED"
  |_->print_endline"UNKNOWN_RECONCILE_ONLY");
 if mode="reconcile"&&not(W.process_poisoned())then(
  ignore(ok(W.with_private_db session(fun db->
   let st=Sqlite3.prepare db"PRAGMA quick_check"in
   Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st)(fun()->
    check"fresh bound child actually executes integrity query"(Sqlite3.step st=Sqlite3.Rc.ROW&&Sqlite3.column_text st 0="ok"&&Sqlite3.step st=Sqlite3.Rc.DONE));W.Known())));
  print_endline"FRESH_BOUND_INTEGRITY_OK");
 if replacements<>[]then check"replacement blocks Store callback before any SQL write"(not !called);
 if mode="acklost"then(Unix.kill(Unix.getpid())Sys.sigkill;Unix._exit 98);
 if mode="checkpoint"&&not(W.process_poisoned())then(
  let result=W.with_private_db session(fun db->
   let st=Sqlite3.prepare db"PRAGMA wal_checkpoint(PASSIVE)"in
   let row=Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st)(fun()->
    if Sqlite3.step st<>Sqlite3.Rc.ROW then None else Some(Sqlite3.column_int st 0,Sqlite3.column_int st 1,Sqlite3.column_int st 2))in
   match row with Some(0,log,done_)when log>0&&log=done_->Printf.printf"CHECKPOINT busy=0 log=%d done=%d\n"log done_;W.Known()
   |_->W.Unknown)in
  if result<>Ok()then print_endline"CHECKPOINT_UNKNOWN_RECONCILE_ONLY");
 if W.process_poisoned()then(
  let attempted=ref false in
  check"poison blocks private callback"(match W.with_private_db session(fun _->attempted:=true;W.Known())with Error _->not !attempted|_->false);
  check"poison blocks snapshot"(match W.snapshot session with Error _->true|_->false);
  check"poison blocks new session"(W.open_existing ~directory ~basename:"tasks.sqlite3" ~expected=Error W.Poisoned);
  check"unknown cleanup remains terminal"(match W.close session with Error _->true|_->false);
  Printf.printf"UNKNOWN_WORKER_EXIT_REQUIRED checks=%d\n%!"!checks;exit 0);
 let observation=ok(W.snapshot session)in check"exact observed descriptor identities"(W.identities observation=expected);
 let diag=W.diagnostics observation in
 let metric role key=let open Yojson.Safe.Util in let rows=to_list(member"resources"diag)in
  let row=List.find(fun r->to_string(member"role"r)=role)rows in match member key row with `Int n->Int64.of_int n|`Intlit n->Int64.of_string n|_->failwith"metric"in
 if !fresh then(check"fresh commit actual WAL writes"(metric"wal""writes">0L);check"fresh commit actual successful WAL sync"(metric"wal""syncs">0L));
 print_endline(Yojson.Safe.to_string diag);
 let closed=W.close session in
 (match closed with Ok()->check"exact repeated close"(W.close session=Ok())
 |Error _->check"uncertain close poisons process"(W.process_poisoned());check"uncertain close exact terminal replay"(W.close session=closed);print_endline"UNKNOWN_CLEANUP_WORKER_EXIT_REQUIRED");
 Printf.printf"PASS bound writer child %s checks=%d\n%!"mode !checks
let run ?fault directory mode expected_exit=
 let root="/home/an/NAS-setup/uos"in
 (match fault with None->()|Some _->check"private fault DSO explicitly built"(Sys.file_exists(Filename.dirname Sys.executable_name^"/sqlite_write_fault_shim.so")));
 let args=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"10000";"1048576";"merged";Sys.executable_name;"--child";directory;mode]in
 let env=Astring.String.Map.of_list(["PATH","/usr/bin:/bin";"LANG","C.UTF-8"]@(match fault with None->[]|Some selection->["LD_PRELOAD",Filename.dirname Sys.executable_name^"/sqlite_write_fault_shim.so";"UOS_PRIVATE_WRITE_FAULT",selection]))in
 match Bos.OS.Cmd.run_out ~env(Bos.Cmd.of_list args)|>Bos.OS.Cmd.out_string ~trim:false with
 |Ok(text,(_,`Exited code))->Printf.printf"CHILD %s exit=%d\n%s%!"mode code text;check("exit "^mode)(code=expected_exit);
  if mode="reconcile"&&code=0 then check"fresh bound integrity witness present"(Astring.String.is_infix ~affix:"FRESH_BOUND_INTEGRITY_OK"text);text
 |_->failwith"child cleanup unknown"
let no_fixture_fds directory=
 let live=Array.to_list(Sys.readdir"/proc/self/fd")|>List.filter(fun name->try String.starts_with ~prefix:(directory^"/tasks.sqlite3")(Unix.readlink("/proc/self/fd/"^name))with Unix.Unix_error _->false)in
 check"no initializer/keeper resource FD remains"(live=[])
let fixture ?(keeper=true) test=
 let directory=Filename.temp_file"uos-write-vfs-test-"""in Unix.unlink directory;Unix.mkdir directory 0o700;
 let database=directory^"/tasks.sqlite3"in
 check"private helper persistent sidecars"(setup_persist());
 let store=ok(S.open_db database)in Unix.chmod database 0o600;
 ignore(ok(S.initialize_cap_fixture store));let time=now()in
 ignore(ok(S.create_plan store ~id:K.fixed_plan ~name:"private/write-vfs"~title:"fixture"~now_ns:time));
 List.iter(fun(id,worker)->ignore(ok(S.create_task store ~plan_id:K.fixed_plan ~id ~name:("private/"^id)~title:id~parent_id:None~dependencies:[]~priority:0~now_ns:time));
  ignore(ok(S.claim_task store ~plan_id:K.fixed_plan ~task_id:id ~worker ~now_ns:(Int64.sub time 3000000000L)~lease_ns:1000000000L)))K.fixed_members;
 let before,sha=ok(S.recovery_snapshot_bounded store ~plan_id:K.fixed_plan)in
 let request=S.{reclaim_request_id="private-bound-request";reclaim_plan_id=K.fixed_plan;expected_snapshot_sha256=sha;expired_tasks=List.map(fun(id,worker)->S.{reclaim_task_id=id;old_worker=worker;old_attempt=1;old_lease_until_ns=Int64.sub time 2000000000L})K.fixed_members;reclaim_lease_ns=20000000000L;request_deadline_ns=Int64.add time 30000000000L}in
 write(directory^"/request.json")(S.reclaim_request_bytes request);
 write(directory^"/before.json")(Yojson.Basic.to_string before);
 List.iter(fun suffix->Unix.chmod(database^suffix)0o600)["-wal";"-shm"];
 Printf.printf"FIXTURE %s\n%!"directory;
 if not keeper then(S.close store;no_fixture_fds directory;print_endline"ALL_INITIALIZER_SQLITE_HANDLES_CLOSED_NO_KEEPER");
 Fun.protect ~finally:(fun()->S.close store)(fun()->test directory store request)
let coherent store request before=
 let actual,after_sha=ok(S.recovery_snapshot_bounded store ~plan_id:K.fixed_plan)in
 let receipt=ok(S.reconcile_reclaim store request)in
 (match receipt with
 |None->check"no receipt implies exact unchanged whole state"(S.reclaim_post_matches before actual)
 |Some j->let open Yojson.Basic.Util in
  let observed=Int64.of_string(to_string(member"observed_ns"j))in
  check"one receipt implies exact whole three-row post-state"(S.reclaim_post_matches(S.reclaim_expected_post request before observed)actual);
  check"receipt binds actual full post snapshot"(to_string(member"after_snapshot"j)=after_sha));
 let db=store.S.db in let st=Sqlite3.prepare db"PRAGMA quick_check"in
 Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st;Core.Gc.keep_alive db)(fun()->
  check"parent held-connection SQLite integrity"(Sqlite3.step st=Sqlite3.Rc.ROW&&Sqlite3.column_text st 0="ok"&&Sqlite3.step st=Sqlite3.Rc.DONE));
 Printf.printf"RECONCILED committed=%d no-partial-three-row-state=1\n%!"(if receipt=None then 0 else 1);receipt
let fresh_coherent directory request before=
 no_fixture_fds directory;
 let store=ok(S.open_existing(directory^"/tasks.sqlite3"))in
 let result=Fun.protect ~finally:(fun()->S.close store)(fun()->coherent store request before)in no_fixture_fds directory;result
let legacy_keeper_suite()=(
 fixture(fun directory store _->
  let text=run directory "normal"0 in check"actual first same-db commit"(Astring.String.is_infix ~affix:"COMMITTED_SAME_BOUND_CONNECTION"text);
  let text=run directory "normal"0 in check"fresh bound replay historical"(Astring.String.is_infix ~affix:"HISTORICAL_NO_NEW_EFFECT"text);
  let rows,_=ok(S.recovery_snapshot_bounded store ~plan_id:K.fixed_plan)in
  Yojson.Basic.Util.to_list rows|>List.iter(fun row->check"all real Store attempts exactly two"(Yojson.Basic.Util.(to_int(member"attempt"row))=2)));
 fixture(fun directory _ _->let text=run directory "checkpoint"0 in check"real bounded checkpoint"(Astring.String.is_infix ~affix:"CHECKPOINT busy=0"text));
 fixture(fun directory store request->let before,_=ok(S.recovery_snapshot_bounded store ~plan_id:K.fixed_plan)in
  let text=run directory"settings"0 in check"critical SQL refusal actual control"(Astring.String.is_infix ~affix:"CRITICAL_SQL_SETTINGS_LOCKED"text);
  check"fixed Store still commits with guarded settings"(coherent store request before<>None));
 fixture(fun directory store request->
  let before,_=ok(S.recovery_snapshot_bounded store ~plan_id:K.fixed_plan)in
  ignore(run directory"acklost"125);
  let text=run directory"reconcile"0 in check"lost ACK uses fresh history-only binding"(Astring.String.is_infix ~affix:"HISTORICAL_FACT_ONLY_NO_FORWARD_EXECUTION"text);
  check"successful commit then lost ACK remains exactly one fact"(coherent store request before<>None));
 List.iter(fun fault->fixture(fun directory store request->
  let before,_=ok(S.recovery_snapshot_bounded store ~plan_id:K.fixed_plan)in
  let mode=if fault="main-truncate-eio"then"checkpoint"else"normal"in
  let code=if String.starts_with ~prefix:"kill-"fault then 125 else 0 in
  let text=run ~fault directory mode code in
  check("actual fault fired "^fault)(Astring.String.is_infix ~affix:("PRIVATE_POSIX_FAULT "^fault)text);
  if fault="wal-sync-after-success-eio"||fault="kill-after-wal-sync"then check"after-success fault really observed successful underlying sync"(Astring.String.is_infix ~affix:"CONFIRMED_REAL_SYNC_SUCCESS"text);
  if fault="wal-sync-real-failure-control"then(check"failed actual sync never classified after-success"(Astring.String.is_infix ~affix:"REAL_SYNC_FAILED_NO_AFTER_SUCCESS rc=-1"text&&not(Astring.String.is_infix ~affix:"CONFIRMED_REAL_SYNC_SUCCESS"text)));
  let text=run directory"reconcile"0 in
  check"fresh reconcile executes no forward path"(Astring.String.is_infix ~affix:"HISTORICAL_FACT_ONLY_NO_FORWARD_EXECUTION"text||Astring.String.is_infix ~affix:"ABSENT_FACT_UNKNOWN_STAYS_BLOCKED_NO_RETRY"text);
  ignore(coherent store request before)))
 ["wal-write-eio";"wal-write-short";"wal-sync-eio";"wal-sync-after-success-eio";"wal-sync-real-failure-control";"kill-after-wal-write";"kill-before-wal-sync";"kill-after-wal-sync";"main-truncate-eio";"main-close-eio"];
 List.iter(fun mode->fixture(fun directory store request->
  let before,_=ok(S.recovery_snapshot_bounded store ~plan_id:K.fixed_plan)in
  let text=run directory mode 0 in check"swap refuses callback and requires exit"(Astring.String.is_infix ~affix:"UNKNOWN_WORKER_EXIT_REQUIRED"text);
  (* Reaped child first; restore locators before querying the original parent
     connection, whose normal Unix VFS correctly refuses a moved main file. *)
  let roles=match mode with"swap-main"->["",0]|"swap-wal"->["-wal",1]|"swap-shm"->["-shm",2]|_->["",0;"-wal",1;"-shm",2]in
  List.iter(fun(suffix,r)->Unix.rename(directory^"/tasks.sqlite3"^suffix)(directory^"/rejected-clone"^string_of_int r);Unix.rename(directory^"/old"^string_of_int r)(directory^"/tasks.sqlite3"^suffix))roles;
  check"resource replacement did not mutate original Store"(coherent store request before=None)))
 ["swap-main";"swap-wal";"swap-shm";"swap-all"];
 fixture ~keeper:false(fun directory _ request->
  let before=Yojson.Basic.from_string(read(directory^"/before.json"))in
  let text=run directory"normal"0 in check"genuine first opener commits"(Astring.String.is_infix ~affix:"COMMITTED_SAME_BOUND_CONNECTION"text);
  let text=run directory"reconcile"0 in check"genuine no-keeper reopen observes fact"(Astring.String.is_infix ~affix:"HISTORICAL_FACT_ONLY_NO_FORWARD_EXECUTION"text);
  check"no-keeper commit exact full goal"(fresh_coherent directory request before<>None));
 List.iter(fun bytes->fixture ~keeper:false(fun directory _ request->
  let before=Yojson.Basic.from_string(read(directory^"/before.json"))in
  Unix.truncate(directory^"/tasks.sqlite3-shm")bytes;
  ignore(run directory"reconcile"0);
  check"partial cache rebuilt without task effect"(fresh_coherent directory request before=None))) [0;3;4096;12288];
 Printf.printf"PASS %d writable real-Store checks; fixture only no authority\n%!"!checks)

(* Current authorized verification is ordinary functional use ONLY. The prior
   keeper-based/fault suite is retained, not rerun for this repair or summed. *)
let ordinary_no_keeper()=
 fixture ~keeper:false(fun directory _ request->
  let before=Yojson.Basic.from_string(read(directory^"/before.json"))in
  let first=run directory "normal" 0 in
  check"ordinary no-keeper bound commit"(Astring.String.is_infix ~affix:"COMMITTED_SAME_BOUND_CONNECTION"first);
  no_fixture_fds directory;
  let history=run directory "reconcile" 0 in
  check"ordinary no-keeper fresh history"(Astring.String.is_infix ~affix:"HISTORICAL_FACT_ONLY_NO_FORWARD_EXECUTION"history);
  check"ordinary complete three-row goal"(fresh_coherent directory request before<>None));
 fixture ~keeper:false(fun directory _ request->
  let before=Yojson.Basic.from_string(read(directory^"/before.json"))in
  ignore(run directory "acklost" 125);no_fixture_fds directory;
  let history=run directory "reconcile" 0 in
  check"already-supported interrupted-process history"(Astring.String.is_infix ~affix:"HISTORICAL_FACT_ONLY_NO_FORWARD_EXECUTION"history);
  check"interrupted ACK exact committed fact"(fresh_coherent directory request before<>None));
 Printf.printf"PASS %d ordinary no-keeper checks; previous fault/adversarial controls UNRUN for repair\n%!"!checks
let ()=
 if Array.length Sys.argv=4&&Sys.argv.(1)="--child"then child Sys.argv.(2)Sys.argv.(3)
 else if Array.length Sys.argv=2&&Sys.argv.(1)="--legacy-keeper-suite"then legacy_keeper_suite()
 else ordinary_no_keeper()
