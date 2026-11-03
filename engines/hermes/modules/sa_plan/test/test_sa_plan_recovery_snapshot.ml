(* Development-only private fixtures. This is a read prerequisite, not reclaim,
   receipt, grant, selection, lease renewal or ordinary dispatch. Canonical
   checker modules below are copied byte-for-byte by narrowly scoped Dune rules. *)
module S=Sa_plan.Store
let checks=ref 0
let check name b=incr checks;if not b then failwith("FAILED "^name)
let ok=function Ok x->x|Error e->failwith e
let raw path f=let db=Sqlite3.db_open path in
 Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db);Core.Gc.keep_alive db)(fun()->f db)
let exec path sql=raw path(fun db->match Sqlite3.exec db sql with Sqlite3.Rc.OK->()|_->failwith(Sqlite3.errmsg db))
let fixture count f=
 let path=Filename.temp_file "uos-recovery-snapshot-" ".sqlite3"in
 let s=ok(S.open_db path)in
 Fun.protect ~finally:(fun()->S.close s;List.iter(fun p->if Sys.file_exists p then Sys.remove p)[path;path^"-wal";path^"-shm"])(fun()->
  ok(S.create_plan s ~id:"p" ~name:"fixture/plan" ~title:"private fixture" ~now_ns:1L);
  ok(S.with_transaction s(fun()->
   for n=0 to count-1 do let id=Printf.sprintf "n%04d"n in
    ok(S.create_task s ~plan_id:"p" ~id ~name:("fixture/tasks/"^id) ~title:id ~parent_id:None ~dependencies:[] ~priority:0 ~now_ns:1L)
   done;Ok()));f path s)
let snapshot s=ok(S.recovery_snapshot_bounded s ~plan_id:"p")
let reject s=match S.recovery_snapshot_bounded s ~plan_id:"p"with Error _->true|Ok _->false
let parity path s=
 let json,digest=snapshot s in
 let expected=Live_plan.read ~path ~plan:"p"in
 check "exact independent checker JSON bytes"(Yojson.Basic.to_string json=Yojson.Basic.to_string(`List(List.map Live_plan.to_json expected)));
 check "exact independent checker SHA256"(digest=Live_plan.digest expected)
let ()=
 fixture 3(fun path s->
  exec path "UPDATE sa_plan_task SET state='completed',completed_at_ns=300,result='SYNTHETIC_PRIVATE_RESULT_MUST_NOT_ESCAPE' WHERE id='n0000'";
  exec path "UPDATE sa_plan_task SET state='executing',worker='worker-b',attempt=2,lease_until_ns=500 WHERE id='n0001'";
  exec path "INSERT INTO sa_plan_dependency VALUES('p','n0002','n0000'); INSERT INTO sa_plan_dependency VALUES('p','n0002','n0001')";
  parity path s;
  let json,_=snapshot s in
  check "raw result bytes absent"(not(Astring.String.is_infix ~affix:"SYNTHETIC_PRIVATE_RESULT_MUST_NOT_ESCAPE"(Yojson.Basic.to_string json)));
  check "result presence retained"(Yojson.Basic.Util.member "result_present"(List.hd(Yojson.Basic.Util.to_list json))=`Bool true);
  check "completed timestamp retained"(Yojson.Basic.Util.member "completed_at_ns"(List.hd(Yojson.Basic.Util.to_list json))=`String"300");
  check "missing plan refuses"(Result.is_error(S.recovery_snapshot_bounded s ~plan_id:"missing")));
 fixture 1000(fun path s->parity path s;check "1000 tasks boundary"(List.length(Yojson.Basic.Util.to_list(fst(snapshot s)))=1000));
 fixture 1001(fun _ s->check "1001 tasks refuse"(reject s));
 fixture 101(fun path s->
  exec path "WITH RECURSIVE n(x) AS(VALUES(0) UNION ALL SELECT x+1 FROM n WHERE x<9999) INSERT INTO sa_plan_dependency SELECT 'p',printf('n%04d',x/101),printf('n%04d',x%101) FROM n";
  parity path s;
  exec path "INSERT INTO sa_plan_dependency VALUES('p','n0099','n0001')";
  check "10001 edges refuse"(reject s));
 List.iter(fun sql->fixture 1(fun path s->exec path("PRAGMA ignore_check_constraints=ON;"^sql);check "malformed/orphan/oversized metadata refuses"(reject s)))[
  "UPDATE sa_plan_task SET attempt=-1";
  "UPDATE sa_plan_task SET attempt=1000001";
  "UPDATE sa_plan_task SET attempt='bad-integer'";
  "UPDATE sa_plan_task SET lease_until_ns='bad-clock'";
  "UPDATE sa_plan_task SET attempt=1.5";
  "UPDATE sa_plan_task SET worker=CAST('worker' AS BLOB)";
  "UPDATE sa_plan_task SET state=CAST('available' AS BLOB)";
  "UPDATE sa_plan_task SET id=CAST('n0000' AS BLOB)";
  "UPDATE sa_plan_task SET worker='trusted'||char(0)||'suffix'";
  "UPDATE sa_plan_task SET state='available'||char(0)||'suffix'";
  "UPDATE sa_plan_task SET id='n0000'||char(0)||'suffix'";
  "INSERT INTO sa_plan_dependency VALUES('p','n0000', 'n0000'||char(0)||'suffix')";
  "INSERT INTO sa_plan_dependency VALUES('p','n0000'||char(0)||'suffix','n0000')";
  "UPDATE sa_plan_task SET worker=CAST(X'C080' AS TEXT)";
  "UPDATE sa_plan_task SET worker=replace(hex(zeroblob(101)),'0','w')";
  "UPDATE sa_plan_task SET id=replace(hex(zeroblob(101)),'0','i')";
  "INSERT INTO sa_plan_dependency VALUES('p','n0000','absent')"];
 (* The SQL must reject malformed numeric storage BEFORE sqlite3-ocaml copies
    its payload. Measure OCaml allocation only, not SQLite/process memory. *)
 List.iter(fun column->List.iter(fun expression->fixture 1(fun path s->
  exec path("UPDATE sa_plan_task SET "^column^"="^expression);
  let before=Gc.allocated_bytes()in
  let refused=reject s in
  let allocated=Gc.allocated_bytes()-.before in
  check (column^" large malformed value refuses") refused;
  Printf.printf "numeric_projection column=%s allocated_bytes=%.0f\n%!" column allocated;
  check (column^" malformed payload is not copied into OCaml") (allocated<262144.)
 ))["zeroblob(2097152)";"CAST(zeroblob(2097152) AS TEXT)"])
 ["lease_until_ns";"attempt";"completed_at_ns"];
 (* Byte lengths, rather than Unicode scalar counts, determine the cap. *)
 List.iter(fun (ascii_count,suffix_hex,accepted)->fixture 1(fun path s->
  exec path(Printf.sprintf
   "UPDATE sa_plan_task SET worker=substr(replace(hex(zeroblob(100)),'0','a'),1,%d)||CAST(X'%s' AS TEXT)"
   ascii_count suffix_hex);
  let result=S.recovery_snapshot_bounded s ~plan_id:"p"in
  check "UTF8 exact byte boundary acceptance"(Result.is_ok result=accepted);
  if accepted then parity path s))
 [(198,"C2A2",true);(199,"C2A2",false);
  (197,"E282AC",true);(198,"E282AC",false);
  (196,"F48FBFBF",true);(197,"F48FBFBF",false);
  (199,"C2",false);(198,"E282",false);(197,"F48FBF",false)];
 fixture 1(fun path s->
  let before=snapshot s in
  ok(S.with_transaction s(fun()->
   check "nested reader joins actual write transaction"(snapshot s=before);
   let pid=Unix.fork()in
   if pid=0 then(raw path(fun db->Sqlite3.busy_timeout db 30;
     let rc=Sqlite3.exec db "UPDATE sa_plan_task SET attempt=9"in exit(if rc=Sqlite3.Rc.BUSY||rc=Sqlite3.Rc.LOCKED then 0 else 2)));
   let _,status=Unix.waitpid[]pid in check "competing writer fenced during outer transaction"(status=Unix.WEXITED 0);
   check "same transaction snapshot remains byte-identical"(snapshot s=before);Ok()));
  exec path "UPDATE sa_plan_task SET attempt=9";
  check "committed later change changes exact digest"(snd(snapshot s)<>snd before));
 Printf.printf "%d checks PASS read_only_snapshot=true reclaim_implemented=false\n%!" !checks
