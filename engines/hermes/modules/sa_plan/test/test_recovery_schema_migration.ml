module M=Recovery_schema_migration
module F=Recovery_migration_fixture
module S=Recovery_kernel_fixture
let checks=ref 0
let check label v=incr checks;if not v then failwith label
let ok=function Ok x->x|Error _->failwith"unexpected refusal"
let sql db statement=if Sqlite3.exec db statement<>Sqlite3.Rc.OK then failwith(Sqlite3.errmsg db)
let raw path f=let db=Sqlite3.db_open ~mode:`NO_CREATE ~uri:false path in Fun.protect ~finally:(fun()->F.close db)(fun()->f db)
let refuse code=function Error(M.Refused got)->got=code|_->false
let any_refusal=function Error(M.Refused _)->true|_->false
let root_dir=Filename.dirname(Unix.realpath Sys.executable_name)
let journal_request=
 let s x=`String x in Yojson.Basic.to_string(`Assoc["schema_version",`Int 1;"operation",s"latest";
 "binding",`Assoc["owner_id",s"fixture-owner";"operation_id",s(String.make 64 'a');"request_sha256",s(String.make 64 'b');"context_sha256",s(String.make 64 'c')];"expected_previous",`Null;"event",`Null])
let journal_ok path=Yojson.Basic.Util.member"status"(Yojson.Basic.from_string(Recovery_owner_journal.handle ~database:path journal_request))=`String"ok"
let fixture f=
 let path=Filename.temp_file"uos-recovery-migration-"".sqlite3"in
 let db=ok(S.open_db path)in Unix.chmod path 0o600;
 let exec sql=if Sqlite3.exec db.S.db sql<>Sqlite3.Rc.OK then failwith(Sqlite3.errmsg db.S.db)in
 exec"PRAGMA journal_mode=WAL";exec"PRAGMA synchronous=FULL";
 ignore(ok(S.create_plan db ~id:"p"~name:"private/migration"~title:"fixture"~now_ns:1L));
 ignore(ok(S.create_task db ~plan_id:"p"~id:"a"~name:"private/a"~title:"fixture"~parent_id:None~dependencies:[]~priority:0~now_ns:1L));
 let stat=Unix.stat path and clock=ok(Recovery_kernel.native_clock())in
 let r=M.{migration_id="migration-1";resource_id="fixture/tasks";database=path;device=stat.Unix.st_dev;inode=stat.Unix.st_ino;target=Task_store;
 source_sha256=String.make 64 'a';before_schema_sha256=F.core_schema_sha db.S.db Task_store;expires_utc_ns=Int64.add clock.utc_ns 10000000000L;expires_mono_ns=Int64.add clock.mono_ns 10000000000L}in
 Fun.protect ~finally:(fun()->S.close db;List.iter(fun p->if Sys.file_exists p then Sys.remove p)[path;path^"-wal";path^"-shm"])(fun()->f db r)
let journal ?(legacy=false) f=
 let path=Filename.temp_file"uos-journal-migration-"".sqlite3"in Unix.chmod path 0o600;
 let db=Sqlite3.db_open path in
 sql db"PRAGMA journal_mode=WAL";sql db"PRAGMA synchronous=FULL";
 if legacy then List.iter(sql db)Recovery_owner_journal.schema_statements;
 let stat=Unix.stat path and c=ok(Recovery_kernel.native_clock())in
 let r=M.{migration_id="journal-migration-1";resource_id="fixture/journal";database=path;device=stat.st_dev;inode=stat.st_ino;target=Owner_journal;
 source_sha256=String.make 64 'a';before_schema_sha256=F.core_schema_sha db Owner_journal;expires_utc_ns=Int64.add c.utc_ns 10000000000L;expires_mono_ns=Int64.add c.mono_ns 10000000000L}in
 Fun.protect ~finally:(fun()->F.close db;List.iter(fun p->if Sys.file_exists p then Sys.remove p)[path;path^"-wal";path^"-shm"])(fun()->f db r)
let scoped r ttl_ms=
 let c=ok(Recovery_kernel.native_clock())in
 {r with M.expires_utc_ns=Int64.add c.utc_ns(Int64.mul(Int64.of_int ttl_ms)1000000L);
 expires_mono_ns=Int64.add c.mono_ns(Int64.mul(Int64.of_int ttl_ms)1000000L)}
let await fd=let b=Bytes.create 1 in if Unix.read fd b 0 1<>1 then failwith"child readiness"
let signal fd=ignore(Unix.write_substring fd "x" 0 1)
let kill_reap pid=Unix.kill pid Sys.sigkill;let _,st=Unix.waitpid[]pid in check"owned child physically reaped"(st=Unix.WSIGNALED Sys.sigkill)
let compile_probe bytes=
 let path=Filename.temp_file"uos-migration-api-"".ml"in let log=path^".log"and out=path^".cmo"in
 let c=open_out_bin path in output_string c bytes;close_out c;
  Fun.protect ~finally:(fun()->List.iter(fun p->if Sys.file_exists p then Sys.remove p)[path;out;Filename.chop_extension out^".cmi"])(fun()->
  let output=Unix.openfile log[Unix.O_CREAT;Unix.O_TRUNC;Unix.O_WRONLY]0o600 in
  let null=Unix.openfile"/dev/null"[Unix.O_RDONLY]0 in
  let prefix="/home/an/NAS-setup/uos/toolchains/opam-ocaml"in
  let library=Filename.dirname root_dir^"/.recovery_schema_migration.objs/byte"in
  let pid=Unix.create_process(prefix^"/bin/ocamlfind")[|"ocamlfind";"ocamlc";"-package";"yojson";"-I";library;"-c";path;"-o";out|]null output output in
  Unix.close output;Unix.close null;let _,status=Unix.waitpid[]pid in
  Printf.printf"API compile receipt %s exit=%s\n%!"log(match status with Unix.WEXITED n->string_of_int n|_->"signal");status)
let ()=
 check"production API positive compile control"(compile_probe"let _=Recovery_schema_migration.migrate\n"=Unix.WEXITED 0);
 check"production API has no execute constructor"(compile_probe"let _=Recovery_schema_migration.execute\n"=Unix.WEXITED 2);
 check"private fixture not in production library"(compile_probe"let _=Recovery_migration_fixture.execute\n"=Unix.WEXITED 2);
 check"task schema exact reviewed parity"(M.schema M.Task_store=S.reclaim_schema@S.cap_schema);
 check"journal schema exact reviewed parity"(List.map snd(M.schema M.Owner_journal)=Recovery_owner_journal.schema_statements);
 fixture(fun db r->
  sql db.S.db"UPDATE sa_plan_task SET result=CAST(x'736563726574006279746573' AS TEXT),completed_at_ns=123 WHERE id='a'";
  let before=F.data db.S.db r.M.target in
  check"public production entry refuses"(M.migrate r=Error M.Authority_unavailable);
  check"explicit private migration installs"(match F.execute r with Ok(`Installed,_)->true|_->false);
  check"all original typed rows including NUL result preserved"(before=List.filter(fun(n,_)->List.mem n(List.map fst before))(F.data db.S.db r.target));
  check"core remains v7"(ok(S.read_schema_version db.S.db)=7);
  check"read-only historical lookup"(Option.is_some(ok(F.reconcile r)));
  check"exact replay historical only"(match F.execute r with Ok(`Historical,_)->true|_->false);
  check"conflicting same ID refuses"(refuse"MIGRATION_ID_CONFLICT"(F.execute{r with source_sha256=String.make 64 'c'}));
  check"different ID not silent second migration"(refuse"ALREADY_MIGRATED_DIFFERENT_REQUEST"(F.execute{r with migration_id="second"}));
  let table=F.table r.target in
  check"migration receipt UPDATE denied"(Sqlite3.exec db.S.db("UPDATE "^table^" SET receipt_json='{}'")=Sqlite3.Rc.CONSTRAINT);
  check"migration receipt DELETE denied"(Sqlite3.exec db.S.db("DELETE FROM "^table)=Sqlite3.Rc.CONSTRAINT));
 fixture(fun db r->
  List.iter(fun(_,ddl)->sql db.S.db ddl)(M.schema M.Task_store);
  sql db.S.db"INSERT INTO sa_plan_reclaim_receipt VALUES('historic','exact','request','receipt')";
  sql db.S.db"INSERT INTO sa_plan_recovery_cap_receipt VALUES('historic','exact','capability','receipt')";
  let before=F.data db.S.db r.target in
  check"exact existing complete extension adopted explicitly"(match F.execute r with Ok(`Installed,_)->true|_->false);
  check"old receipts remain byte exact"(before=List.filter(fun(n,_)->List.mem n(List.map fst before))(F.data db.S.db r.target)));
 List.iter(fun ddl->fixture(fun db r->sql db.S.db ddl;
  let before=F.all_schema db.S.db in check"partial or unknown namespace HOLD"(refuse"RECOVERY_SCHEMA_MISMATCH"(F.execute r));
  check"partial namespace unchanged"(F.all_schema db.S.db=before)))
  [snd(List.hd(M.schema M.Task_store));"CREATE TABLE sa_plan_recovery_cap_unexpected(x)";"CREATE TABLE sa_plan_recovery_migration_receipt(x)"];
 fixture(fun db r->
  ignore(ok(F.execute r));sql db.S.db"DROP TRIGGER sa_plan_recovery_migration_no_delete";
  check"tampered migration trigger refused"(refuse"RECOVERY_SCHEMA_MISMATCH"(F.execute r)));
 fixture(fun db r->sql db.S.db"UPDATE sa_plan_schema_meta SET version=6";
  check"wrong core version refuses no migration"(refuse"V7_REQUIRED"(F.execute r));check"core version not silently upgraded"(ok(S.read_schema_version db.S.db)=6));
 fixture(fun db r->sql db.S.db"CREATE TABLE unrelated_new(x)";
  check"schema changed since capture refuses"(refuse"CORE_SCHEMA_CHANGED"(F.execute r)));
 fixture(fun db r->
  check"wrong physical resource refuses"(refuse"RESOURCE_IDENTITY_MISMATCH"(F.execute{r with inode=r.inode+1}));
  check"wrong declared schema refuses"(refuse"CORE_SCHEMA_CHANGED"(F.execute{r with before_schema_sha256=String.make 64 '0'}));
  let link=r.database^".link"in Unix.symlink r.database link;
  check"resource symlink refused before SQLite"(any_refusal(F.execute{r with database=link}));Unix.unlink link;
  Unix.link r.database link;check"resource hardlink refused"(refuse"PRIVATE_RESOURCE_REQUIRED"(F.execute r));Unix.unlink link;
  check"resource refusals retain absent schema"(F.layout db.S.db r.target=`Absent));
 fixture(fun _ r->let c=ok(Recovery_kernel.native_clock())in
  check"expired UTC boundary refuses"(refuse"MIGRATION_EXPIRED"(F.execute{r with expires_utc_ns=c.utc_ns}));
  check"expired monotonic boundary refuses"(refuse"MIGRATION_EXPIRED"(F.execute{r with expires_mono_ns=c.mono_ns})));
 List.iter(fun stage->fixture(fun db r->
  let before=F.data db.S.db r.target in
  let outcome=F.execute ~checkpoint:(fun s _->if s=stage then failwith"fixture injected failure")r in
  check"precommit failure confirmed rollback"(any_refusal outcome);
  check"DDL receipt and rows all rollback"(F.layout db.S.db r.target=`Absent&&F.data db.S.db r.target=before)))
  [F.After_ddl;F.Before_final_checks];
 fixture(fun db r->let before=F.data db.S.db r.target in
  let outcome=F.execute ~checkpoint:(fun stage migration_db->match stage with F.Before_final_checks->sql migration_db"UPDATE sa_plan_task SET worker='forged' WHERE id='a'"|_->())r in
  check"late callback changed target caught"(refuse"DATA_POSTGOAL"outcome);
  check"late mutation rollback preserved original"(F.layout db.S.db r.target=`Absent&&F.data db.S.db r.target=before));
 fixture(fun db r->let outcome=F.execute ~checkpoint:(fun stage _->match stage with F.After_commit->failwith"lost ACK"|_->())r in
  check"lost ACK classified unknown"(outcome=Error M.Commit_unknown);
  check"unknown retains durable row"(F.scalar db.S.db("SELECT COUNT(*) FROM "^F.table r.target)=1L);
  check"unknown reconciles exact historical receipt"(Option.is_some(ok(F.reconcile r))));
 fixture(fun db r->let outcome=F.execute ~checkpoint:(fun stage migration_db->match stage with F.After_commit->sql migration_db"DROP TRIGGER sa_plan_recovery_migration_no_delete"|_->())r in
  check"postcommit readback schema failure always unknown"(outcome=Error M.Commit_unknown);
  check"postcommit failure does not erase committed row"(F.scalar db.S.db("SELECT COUNT(*) FROM "^F.table r.target)=1L));
 journal(fun db r->check"empty journal resource initially unavailable"(not(journal_ok r.database));
  check"separate journal migration installs"(match F.execute r with Ok(`Installed,_)->true|_->false);
  check"version2 journal works through actual existing handler"(journal_ok r.database);
  check"exact version2 six-object schema"(List.length(F.all_schema db)=6));
 journal ~legacy:true(fun db r->check"legacy3 backward compatibility"(journal_ok r.database);
  check"explicit legacy3 to version2 upgrade"(match F.execute r with Ok(`Installed,_)->true|_->false);
  check"upgraded journal still works"(journal_ok r.database);
  sql db"DROP TRIGGER recovery_migration_no_delete";
  check"partial version2 does not fall back to legacy"(not(journal_ok r.database)));
 journal ~legacy:true(fun db r->
  let j=Yojson.Basic.from_string journal_request in
  let append=match j with `Assoc fs->`Assoc(List.map(fun(k,v)->k,match k with "operation"->`String"append"|"event"->`Assoc["sequence",`Int 1;"phase",`String"pending";"receipt_sha256",`Null]|_->v)fs)|_->assert false in
  let reply=Yojson.Basic.from_string(Recovery_owner_journal.handle ~database:r.database(Yojson.Basic.to_string append))in
  check"actual legacy pending receipt before migration"(Yojson.Basic.Util.member"code"reply=`String"APPENDED");
  let old=F.data db r.target in
  ignore(ok(F.execute r));
  check"nonempty owner journal rows byte exact across migration"(old=List.filter(fun(n,_)->List.mem n(List.map fst old))(F.data db r.target));
  let latest=Yojson.Basic.from_string(Recovery_owner_journal.handle ~database:r.database journal_request)in
  check"v2 existing worker validates full old chain"(Yojson.Basic.Util.member"record"latest=Yojson.Basic.Util.member"record"reply);
  sql db"CREATE TABLE unexpected_extra(x)";
  check"version2 extra seventh object refuses"(not(journal_ok r.database)));
 journal ~legacy:true(fun db r->sql db"CREATE TABLE foreign_object(x)";
  check"unknown journal object never passing"(not(journal_ok r.database));
  check"unexpected core hash HOLD"(refuse"CORE_SCHEMA_CHANGED"(F.execute r)));
 journal ~legacy:true(fun db r->sql db"CREATE TABLE foreign_object(x)";
  let forged_target={r with M.before_schema_sha256=F.core_schema_sha db M.Owner_journal}in
  check"journal target never accepts foreign namespace even matching supplied digest"(refuse"JOURNAL_RESOURCE_SHAPE"(F.execute forged_target)));
 fixture(fun db r->let p=r.database^".absent"in
  check"production does not create absent resource"(M.migrate{r with database=p}=Error M.Authority_unavailable&&not(Sys.file_exists p));
  check"fixture also no implicit database create"(any_refusal(F.execute{r with database=p})&&not(Sys.file_exists p));
  check"no resource effect"(F.layout db.S.db r.target=`Absent));
 fixture(fun db r->
  let before=F.data db.S.db r.target in
  let outcome=F.execute ~checkpoint:(fun stage migration_db->if stage=F.Before_final_checks then(
   sql migration_db"CREATE TABLE fixture_large(x BLOB)";
   sql migration_db"INSERT INTO fixture_large VALUES(zeroblob(33554432))";
   sql migration_db"DROP TABLE fixture_large"))r in
  check"postDDL allocated pages quota refuses before commit"(refuse"DATABASE_QUOTA"outcome);
  check"quota rollback preserves original rows and absent extension"(F.layout db.S.db r.target=`Absent&&F.data db.S.db r.target=before));
 fixture(fun db r->
  let rd,wr=Unix.pipe()in
  let pid=Unix.fork()in
  if pid=0 then(Unix.close rd;raw r.database(fun lock->sql lock"BEGIN IMMEDIATE";signal wr;Unix.sleepf 0.08;sql lock"ROLLBACK");Unix._exit 0);
  Unix.close wr;await rd;Unix.close rd;
  let short=scoped r 30 in let start=ok(Recovery_kernel.native_clock())in
  let outcome=F.execute short in let finish=ok(Recovery_kernel.native_clock())in
  let _,status=Unix.waitpid[]pid in
  check"lock fixture exited and reaped"(status=Unix.WEXITED 0);
  check"actual lock wait observed"(Int64.sub finish.mono_ns start.mono_ns>=40000000L);
  check"expired after lock not authorized by presample"(refuse"MIGRATION_EXPIRED"outcome);
  check"late lock expiry no DDL"(F.layout db.S.db r.target=`Absent));
 fixture(fun db r->
  let rd,wr=Unix.pipe()in let pid=Unix.fork()in
  if pid=0 then(Unix.close rd;raw r.database(fun lock->sql lock"BEGIN IMMEDIATE";signal wr;Unix.sleep 60);Unix._exit 0);
  Unix.close wr;await rd;Unix.close rd;
  let outcome=F.execute r in kill_reap pid;
  check"busy lock bounded refusal"(any_refusal outcome);
  check"busy refusal no DDL"(F.layout db.S.db r.target=`Absent));
 List.iter(fun stage->fixture(fun db r->
  let before=F.data db.S.db r.target in
  let rd,wr=Unix.pipe()in let pid=Unix.fork()in
  if pid=0 then(Unix.close rd;ignore(F.execute ~checkpoint:(fun got _->if got=stage then(signal wr;while true do Unix.pause()done))r);Unix._exit 3);
  Unix.close wr;await rd;Unix.close rd;kill_reap pid;
  check"actual killed precommit process rolls back DDL and row"(F.layout db.S.db r.target=`Absent&&F.data db.S.db r.target=before)))
  [F.After_ddl;F.Before_final_checks];
 fixture(fun db original->
  let r=scoped original 250 in
  let rd,wr=Unix.pipe()in let pid=Unix.fork()in
  if pid=0 then(Unix.close rd;ignore(F.execute ~checkpoint:(fun stage _->if stage=F.After_commit then(signal wr;while true do Unix.pause()done))r);Unix._exit 3);
  Unix.close wr;await rd;Unix.close rd;kill_reap pid;
  Unix.sleepf 0.3;
  check"killed postcommit ACK-loss receipt remains durable"(F.scalar db.S.db("SELECT COUNT(*) FROM "^F.table r.target)=1L);
  check"post-expiry restart history read succeeds without renewed effect"(Option.is_some(ok(F.reconcile r)));
  check"expired fixture execution stays refused"(refuse"MIGRATION_EXPIRED"(F.execute r)));
 fixture(fun db r->
  let spawn()=let rd,wr=Unix.pipe()in let pid=Unix.fork()in
   if pid=0 then(Unix.close rd;let code=match F.execute r with Ok(`Installed,_)->"I"|Ok(`Historical,_)->"H"|_->"R"in
    ignore(Unix.write_substring wr code 0 1);Unix._exit 0);Unix.close wr;pid,rd in
  let a,ra=spawn()and b,rb=spawn()in
  let read fd=let s=Bytes.create 1 in if Unix.read fd s 0 1<>1 then failwith"concurrent result";Unix.close fd;Bytes.to_string s in
  let ca=read ra and cb=read rb in
  let _,sa=Unix.waitpid[]a and _,sb=Unix.waitpid[]b in
  check"both competing fixture children reaped"(sa=Unix.WEXITED 0&&sb=Unix.WEXITED 0);
  check"overlapping exact requests one install one history"(List.sort compare[ca;cb]=["H";"I"]);
  check"overlapping requests exactly one receipt"(F.scalar db.S.db("SELECT COUNT(*) FROM "^F.table r.target)=1L));
 Printf.printf"%d recovery migration checks PASS\n%!"!checks
