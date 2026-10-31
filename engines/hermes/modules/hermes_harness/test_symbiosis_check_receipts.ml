module S=Symbiosis_check_receipts
let checks=ref 0
let check name condition=incr checks;if not condition then failwith name
let ok name=function Ok x->x|Error e->failwith(name^":"^S.error_code e)
let err name expected=function Error e->check name(e=expected)|Ok _->check name false
let member key=function `Assoc xs->List.assoc key xs|_->failwith "object expected"
let replace key value=function `Assoc xs->`Assoc(List.map(fun(k,v)->k,if k=key then value else v)xs)|_->failwith"object"
let receipt_json ?(owner="owner-a") ?(epoch=0) ?(a="claude") ?(seq=1) id =
  `Assoc["receipt_id",`String id;"operation_id",`String("operation-"^id);
    "owner_id",`String owner;"owner_epoch",`Int epoch;"agent",`String a;
    "candidate",`String(String.make 40 'a');"config_digest",`String(String.make 64 'b');
    "session",`String "session-a";"sequence",`Int seq;"clock_domain",`String "nas-boot-a";
    "probe",`String "functional";"service_id",`String "knowledge_search";
    "started_mono_ms",`Int(-100);"observed_mono_ms",`Int(-90);"expires_mono_ms",`Int 100;
    "observed_utc_us",`Intlit "1793470000000000";"status",`String "ready_scoped";
    "reason",`String "none";"results",`Assoc["function",`Bool true;"performance",`Bool true;"operation",`Bool true];
    "coverage",`Null]
let receipt ?owner ?epoch ?a ?seq id=ok "receipt"(S.receipt_of_json(receipt_json ?owner ?epoch ?a ?seq id))
let key ?(a="claude") ()=ok "latest key"(S.latest_key_of_json(`Assoc[
  "owner_id",`String "owner-a";"owner_epoch",`Int 0;"agent",`String a;
  "candidate",`String(String.make 40 'a');"config_digest",`String(String.make 64 'b');
  "session",`String "session-a";"clock_domain",`String "nas-boot-a";
  "probe",`String "functional";"service_id",`String "knowledge_search"]))
let request operation fields=Yojson.Safe.to_string(`Assoc(["schema_version",`Int 1;"operation",`String operation]@fields))
let guardian = match Array.to_list Sys.argv with
  |[_]->None|[_;"--guardian";path]->Some path|_->failwith"expected optional --guardian PATH"
let fixtures=ref []
let private_path()=
  let p=Filename.temp_file "uos-symbiosis-receipt-" ".sqlite3" in fixtures:=p:: !fixtures;p
let cleanup()=List.iter(fun p->List.iter(fun p->try Unix.unlink p with Unix.Unix_error(Unix.ENOENT,_,_)->())
  [p;p^"-wal";p^"-shm"])!fixtures
let with_store ?(limits=S.default_limits) f=
  let path=private_path() in let s=ok "open"(S.open_store ~limits ~path()) in
  Fun.protect ~finally:(fun()->ignore(S.close s))(fun()->f path s)
let raw path f=let db=Sqlite3.db_open path in
  Fun.protect ~finally:(fun()->check "raw fixture closes"(Sqlite3.db_close db))(fun()->f db)
let count path=raw path(fun db->let n=ref(-1)in
  check "count query"(Sqlite3.exec db ~cb:(fun row _->n:=int_of_string(Option.get row.(0)))
    "SELECT count(*) FROM symbiosis_check_receipt_v1"=Sqlite3.Rc.OK);!n)

let basics()=with_store(fun path s->
  let r=receipt "r1" in
  (match ok "append"(S.append s r)with S.Stored _->check "first inserted" true|_->check"first inserted"false);
  (match ok "replay"(S.append s r)with S.Replayed _->check "exact replay" true|_->check"exact replay"false);
  check "one row"(count path=1);
  let read=Option.get(ok "get"(S.get s ~receipt_id:"r1")) in
  check "digest native"(member "payload_sha256"(S.stored_json read)=`String(S.payload_sha256 r));
  check "indexed latest"(Option.is_some(ok "latest"(S.latest s(key()))));
  check "cross-agent query absent"(ok "other agent"(S.latest s(key ~a:"pi"()))=None);
  check "absent exact get"(ok "absent"(S.get s ~receipt_id:"missing")=None);
  let changed=ok "changed"(S.receipt_of_json(replace "observed_utc_us" (`Intlit "1793470000000001")(receipt_json "r1")))in
  err "divergent same receipt" S.Conflict(S.append s changed);
  err "divergent same identity" S.Conflict(S.append s(receipt "another-id"));
  let op_alias=receipt_json ~seq:2 "r2" |> replace "operation_id" (`String "operation-r1") in
  err "divergent same operation" S.Conflict(S.append s(ok "op alias"(S.receipt_of_json op_alias)));
  ignore(ok "second"(S.append s(receipt ~seq:3 "r3")));
  err "new lower sequence" S.Out_of_order(S.append s(receipt ~seq:2 "r2"));
  ignore(ok "new epoch"(S.append s(receipt ~epoch:1 "e1")));
  err "new retired epoch" S.Stale_epoch(S.append s(receipt ~seq:4 "old-epoch"));
  (match ok "historical replay"(S.append s r)with S.Replayed _->check"old replay records only"true|_->check"old replay"false);
  check"no replay rows"(count path=3);
  List.iter(fun sql->raw path(fun db->check"append-only refusal"(Sqlite3.exec db sql<>Sqlite3.Rc.OK)))
    ["UPDATE symbiosis_check_receipt_v1 SET payload='changed'";"DELETE FROM symbiosis_check_receipt_v1"];
  let unknown=receipt_json ~seq:2 ~epoch:1 "unknown" |> replace "status" (`String "unknown")
    |>replace "reason" (`String "timed_out") |>replace "observed_mono_ms" (`Int 200)
    |>replace "results" (`Assoc["function",`Null;"performance",`Null;"operation",`Null]) in
  ignore(ok "unknown persisted"(S.append s(ok "unknown codec"(S.receipt_of_json unknown))));
  let stopped=receipt_json ~seq:3 ~epoch:1 "stopped" |> replace "status" (`String "stop")
    |>replace "results" (`Assoc["function",`Bool false;"performance",`Null;"operation",`Null]) in
  ignore(ok "stop persists"(S.append s(ok "stop codec"(S.receipt_of_json stopped))));
  ignore(ok "close"(S.close s));
  err "closed read" S.Closed(S.get s ~receipt_id:"r1");
  let reopened=ok "reopen"(S.open_store ~path())in
  check "durable reopen"(Option.is_some(ok "reopened get"(S.get reopened ~receipt_id:"r1")));
  ignore(ok "close reopened"(S.close reopened)))

let json_controls()=
  let good=Yojson.Safe.to_string(receipt_json "r1") in
  let j=ok "strict positive"(S.parse_json good)in
  ignore(ok "roundtrip"(S.receipt_of_json j));
  let normalized=ok "typed integer normalization"(S.receipt_of_json
    (replace "owner_epoch" (`Intlit"00")(receipt_json "r1")))in
  check"native integer canonical law"(S.payload_sha256 normalized=S.payload_sha256(receipt"r1"));
  let bad=["{/*comment*/\"x\":1}";"{\"x\":1,\"x\":2}";"{\"x\":{\"a\":0,\"a\":1}}";
    "{\"x\":NaN}";"{\"x\":01}";"{\"x\":+1}";"{\"x\":1,}";"{\"x\":[1,]}";
    "{\"x\":\"\\uD800\"}";"{\"x\":\"\\uDC00\"}";"{\"x\":\"\192\128\"}";
    "{\"x\":\"\244\144\128\128\"}";"{\"x\":\"\237\160\128\"}";"{} trailing";
    String.make 262145 ' ';"{\"x\":"^String.make 18 '['^"0"^String.make 18 ']'^"}"] in
  List.iter(fun text->err "strict negative" S.Invalid_json(S.parse_json text))bad;
  List.iter(fun text->ignore(ok "scalar unicode positive"(S.parse_json text)))
    ["{\"x\":\"\\uD800\\uDC00\"}";"{\"x\":\"\244\143\191\191\"}";"{\"x\":\"\194\128\"}"];
  List.iter(fun j->err "invalid receipt" S.Invalid_receipt(S.receipt_of_json j))[
    replace "agent" (`String "unknown")(receipt_json "r1");replace "status" (`String "admitted")(receipt_json "r1");
    replace "candidate" (`String "bad")(receipt_json "r1");replace "observed_mono_ms" (`Int 200)(receipt_json "r1");
    replace "observed_utc_us" (`Int(-1))(receipt_json "r1");
    (match receipt_json "r1"with `Assoc xs->`Assoc(("caller_digest",`String "fake")::xs)|x->x)];
  let request=request "append"["receipt",receipt_json "r1"] in
  ignore(ok "decode request"(S.decode_request request));
  err "wire unknown operation" S.Invalid_request(S.decode_request "{\"schema_version\":1,\"operation\":\"execute\"}");
  err "wire unknown keys" S.Invalid_request(S.decode_request "{\"schema_version\":1,\"operation\":\"get\",\"receipt_id\":\"a\",\"db\":\"/other\"}")

let coverage_controls()=
  let binding=`Assoc["candidate",`String(String.make 40 'a');"config_digest",`String(String.make 64 'b');"session",`String "session-a"] in
  let dimension=`Assoc["passed",`Bool true;"observed_mono_ms",`Int(-95)]in
  let service name=`Assoc["agent",`String "claude";"service_id",`String name;"binding",binding;
    "function",dimension;"performance",dimension;"operation",dimension]in
  let proof services=`Assoc["agent",`String "claude";"binding",binding;"services",`List services]in
  let base=receipt_json "coverage" |>replace "probe" (`String "coverage") in
  let first=ok "coverage"(S.receipt_of_json(replace "coverage" (proof[service "b";service "a"])base))in
  let second=ok "coverage reordered"(S.receipt_of_json(replace "coverage" (proof[service "a";service "b"])base))in
  check"coverage set canonicalization"(S.payload_sha256 first=S.payload_sha256 second);
  List.iter(fun p->err "coverage identity/set shape" S.Invalid_receipt
    (S.receipt_of_json(replace "coverage" p base)))[
      proof[service "a";service "a"];proof[];
      replace "agent" (`String "pi")(proof[service "a"]);
      proof[replace "agent" (`String "pi")(service "a")];
      proof[replace "performance" (`Assoc["passed",`Bool false;"observed_mono_ms",`Int(-95)])(service "a")];
      proof(List.init 257(fun n->service(string_of_int n))) ]

let failures()=
  let path=private_path()in
  let evidence=match Evidence_store.open_db ~path with Ok s->s|Error e->failwith e in
  let s=ok "attach"(S.For_test.attach ~limits:S.default_limits evidence)in
  check"outer begin"(Sqlite3.exec evidence.db "BEGIN IMMEDIATE"=Sqlite3.Rc.OK);
  err "nested refused" S.Nested_transaction(S.append s(receipt "nested"));
  check"outer remains owned"(Sqlite3.exec evidence.db "ROLLBACK"=Sqlite3.Rc.OK);
  S.For_test.on_stage s(fun stage->if stage=S.For_test.After_insert then failwith "injected-after-insert");
  (try ignore(S.append s(receipt "rolled"));check"expected injected exception"false
   with Failure msg->check"exception preserved"(msg="injected-after-insert"));
  check"unexpected exception rolled back"(count path=0);
  S.For_test.on_stage s(fun stage->if stage=S.For_test.Before_commit then failwith "injected-precommit");
  err "precommit failure" S.Store_unavailable(S.append s(receipt "precommit"));
  check"precommit rollback"(count path=0);
  S.For_test.on_stage s(fun stage->if stage=S.For_test.Commit_error then failwith "injected-commit" );
  err "commit uncertain" S.Commit_unknown(S.append s(receipt "commit-fail"));
  check"commit failure rollback"(count path=0);
  S.For_test.on_stage s(fun _->());ignore(ok "owner recovers"(S.append s(receipt "ok")));
  ignore(ok "close attached"(S.close s));check"legacy connection remains owned"(Sqlite3.db_close evidence.db);
  with_store(fun path s->
    raw path(fun db->check "schema mutant installed"(Sqlite3.exec db "DROP TRIGGER symbiosis_no_delete_v1"=Sqlite3.Rc.OK));
    err "changed schema fail closed" S.Schema_mismatch(S.append s(receipt "schema"));
    check"schema error no rows"(count path=0))

let bounds()=
  let limits={S.default_limits with max_rows=2}in
  with_store ~limits(fun path s->
    ignore(ok "bound1"(S.append s(receipt "r1")));ignore(ok"bound2"(S.append s(receipt ~seq:2 "r2")));
    err "row limit" S.Resource_bound(S.append s(receipt ~seq:3 "r3"));
    check"resource hold preserves rows"(count path=2);
    (match ok "replay at cap"(S.append s(receipt "r1"))with S.Replayed _->check"replay at cap"true|_->check"replay at cap"false));
  with_store ~limits:{S.default_limits with max_payload_bytes=10}(fun _ s->
    err "payload limit" S.Resource_bound(S.append s(receipt "r1")));
  err "relative path" S.Invalid_path(S.open_store ~path:"relative.sqlite"());
  err "parent alias" S.Invalid_path(S.open_store ~path:"/tmp/../tmp/alias.sqlite"());
  let target=private_path()and link=private_path()in Unix.unlink link;Unix.symlink target link;
  err "symlink refused" S.Invalid_path(S.open_store ~path:link());
  let hard=private_path()in Unix.unlink hard;Unix.link target hard;
  err "hardlink refused" S.Invalid_path(S.open_store ~path:target())

let path_and_busy_controls()=
  let path=private_path()and foreign=private_path()in
  Unix.symlink foreign (path^"-wal");
  err "sidecar symlink refused before SQLite" S.Invalid_path(S.open_store ~path());
  check "sidecar foreign file untouched"((Unix.stat foreign).Unix.st_size=0);
  Unix.unlink(path^"-wal");
  let path=private_path()in Unix.mkfifo(path^"-wal")0o600;
  err "sidecar FIFO refused" S.Invalid_path(S.open_store ~path());Unix.unlink(path^"-wal");
  let path=private_path()in
  let fd=Unix.openfile path[Unix.O_WRONLY]0o600 in Unix.ftruncate fd 33_554_433;Unix.close fd;
  err "oversize existing file refused" S.Resource_bound(S.open_store ~path());
  with_store(fun path s->raw path(fun db->
    check "fixture write lock"(Sqlite3.exec db "BEGIN IMMEDIATE"=Sqlite3.Rc.OK);
    err "lock contention holds" S.Store_unavailable(S.append s(receipt "busy"));
    check "fixture unlock"(Sqlite3.exec db "ROLLBACK"=Sqlite3.Rc.OK));
    check "busy failure no rows"(count path=0);
    ignore(ok "after busy still usable"(S.append s(receipt "after-busy"))))

let poisoned_and_readonly_controls()=
  let path=private_path()in
  let evidence=match Evidence_store.open_db ~path with Ok s->s|Error e->failwith e in
  let s=ok "poison attach"(S.For_test.attach ~limits:S.default_limits evidence)in
  check"query-only fixture"(Sqlite3.exec evidence.db "PRAGMA query_only=ON"=Sqlite3.Rc.OK);
  err "readonly refuses append" S.Store_unavailable(S.append s(receipt"readonly"));
  check"query-only reset"(Sqlite3.exec evidence.db "PRAGMA query_only=OFF"=Sqlite3.Rc.OK);
  S.For_test.on_stage s(fun stage->if stage=S.For_test.After_insert then(
    check"injected external rollback"(Sqlite3.exec evidence.db "ROLLBACK"=Sqlite3.Rc.OK);
    failwith"rollback-confirmation-fixture"));
  (try ignore(S.append s(receipt"rollback-failure"));check"injected failure expected"false
   with Failure text->check"injected failure propagated"(text="rollback-confirmation-fixture"));
  err "unconfirmed rollback fences owner" S.Rollback_failed(S.append s(receipt"after-poison"));
  check"poison preserves rows"(count path=0);
  ignore(ok"poison owner closes"(S.close s));check"poison raw closes"(Sqlite3.db_close evidence.db)

let postcommit_uncertainty_controls()=
  List.iter(fun resource_fault->
    let path=private_path()in
    let evidence=match Evidence_store.open_db ~path with Ok s->s|Error e->failwith e in
    let limits={S.default_limits with max_db_bytes=524288}in
    let s=ok "postcommit fixture attach"(S.For_test.attach ~limits evidence)in
    S.For_test.on_stage s(fun stage->if stage=S.For_test.After_commit then(
      if resource_fault then(
        check"resource mutant raises private page ceiling"(Sqlite3.exec evidence.db "PRAGMA max_page_count=100000"=Sqlite3.Rc.OK);
        check"resource mutant table"(Sqlite3.exec evidence.db "CREATE TABLE postcommit_resource_pad(value BLOB)"=Sqlite3.Rc.OK);
        check"resource mutant bytes"(Sqlite3.exec evidence.db "INSERT INTO postcommit_resource_pad VALUES(zeroblob(600000))"=Sqlite3.Rc.OK))
      else check"postcommit index drop"(Sqlite3.exec evidence.db "DROP INDEX symbiosis_latest_v1"=Sqlite3.Rc.OK)));
    let request=ok"postcommit request"(S.decode_request(request"append"["receipt",receipt_json"committed-before-readback"]))in
    err "any postcommit readback failure is uncertain" S.Commit_unknown(S.execute s request);
    check"postcommit error preserves committed row"(count path=1);
    (if resource_fault then err "resource reason separately observable on read" S.Resource_bound(S.get s ~receipt_id:"committed-before-readback")
     else err"schema reason separately observable on read"S.Schema_mismatch(S.get s ~receipt_id:"committed-before-readback"));
    ignore(ok"postcommit close"(S.close s));check"postcommit raw close"(Sqlite3.db_close evidence.db)) [false;true]

let gc_pressure_control()=
  let malformed=List.init 8(fun _->let path=private_path()in
    let output=open_out_bin path in output_string output "not-an-SQLite-database";close_out output;path)in
  let wrong_schema=List.init 8(fun _->let path=private_path()in
    raw path(fun db->check"GC fixture wrong receipt schema"(Sqlite3.exec db
      "CREATE TABLE symbiosis_check_receipt_v1(wrong INTEGER)"=Sqlite3.Rc.OK));path)in
  let stop=Atomic.make false in
  let collector=Domain.spawn(fun()->while not(Atomic.get stop)do
    ignore(Sys.opaque_identity(Bytes.create 4096));Gc.full_major()done)in
  Fun.protect ~finally:(fun()->Atomic.set stop true;Domain.join collector)(fun()->
    for n=1 to 32 do with_store(fun _ s->
      let id="gc-"^string_of_int n in
      ignore(ok"GC-pressure native close/finalize"(S.append s(receipt id)));
      check"GC-pressure exact read"(Option.is_some(ok"GC read"(S.get s ~receipt_id:id))))done;
    List.iter(fun path->err"malformed SQLite open closes under GC" S.Store_unavailable
      (S.open_store ~path()))malformed;
    List.iter(fun path->err"wrong receipt schema closes under GC" S.Schema_mismatch
      (S.open_store ~path()))wrong_schema);
  let owned=malformed@wrong_schema in
  let leaks=Array.fold_left(fun count fd->
    try let target=Unix.readlink(Filename.concat "/proc/self/fd" fd)in
      if List.mem target owned then count+1 else count
    with Unix.Unix_error(Unix.ENOENT,_,_)->count)0(Sys.readdir "/proc/self/fd")in
  check"failed initialization retains no owned database FD"(leaks=0);
  List.iter(fun path->raw path(fun db->
    let tables=ref 0 in
    check"failed initialization schema query"(Sqlite3.exec db ~cb:(fun _ _->incr tables)
      "SELECT name FROM sqlite_master WHERE name='check_evidence'"=Sqlite3.Rc.OK);
    check"wrong namespace caused no legacy DDL"(!tables=0)))wrong_schema;
  List.iter(fun path->let input=open_in_bin path in
    let text=Fun.protect ~finally:(fun()->close_in input)(fun()->really_input_string input(in_channel_length input))in
    check"malformed bytes preserved"(text="not-an-SQLite-database"))malformed

let read_exact fd size=
  let b=Bytes.create size and until=Unix.gettimeofday()+.3.0 in
  let rec loop offset=if offset<size then(
    let remaining=until-.Unix.gettimeofday()in
    if remaining<=0.0 then failwith "fixture handshake deadline";
    let ready,_,_=Unix.select[fd][][]remaining in
    if ready=[]then loop offset else
    let n=Unix.read fd b offset(size-offset)in if n=0 then failwith"fixture handshake EOF"else loop(offset+n))in
  loop 0;b
let concurrency divergent=
  let path=private_path()in
  let initialized=ok "concurrency init"(S.open_store ~path())in ignore(ok"concurrency close"(S.close initialized));
  let gate_read,gate_write=Unix.pipe ~cloexec:true()and answer_read,answer_write=Unix.pipe ~cloexec:true()in
  let children=List.init 2(fun number->
    let ready_read,ready_write=Unix.pipe ~cloexec:true()in
    let pid=Unix.fork()in
    if pid=0 then(
      Unix.close gate_write;Unix.close answer_read;Unix.close ready_read;
      let s=ok "concurrent child open"(S.open_store ~path())in
      ignore(Unix.write ready_write(Bytes.of_string"r")0 1);Unix.close ready_write;
      ignore(read_exact gate_read 1);
      let r=if divergent && number=1 then ok "divergent child receipt"(S.receipt_of_json
        (replace "observed_utc_us" (`Intlit"1793470000000001")(receipt_json"concurrent")))else receipt"concurrent"in
      let answer=match S.append s r with Ok(S.Stored _)->"s"|Ok(S.Replayed _)->"r"|Error S.Conflict->"c"|_->"e"in
      ignore(S.close s);ignore(Unix.write answer_write(Bytes.of_string answer)0 1);Unix._exit 0);
    Unix.close ready_write;ignore(read_exact ready_read 1);Unix.close ready_read;pid)in
  Unix.close gate_read;Unix.close answer_write;
  ignore(Unix.write gate_write(Bytes.of_string"gg")0 2);Unix.close gate_write;
  let answers=Bytes.to_string(read_exact answer_read 2)in Unix.close answer_read;
  List.iter(fun pid->let _,status=Unix.waitpid[]pid in check "concurrent owned process exits"(status=Unix.WEXITED 0))children;
  let sorted=String.to_seq answers |> List.of_seq |> List.sort Char.compare in
  check "concurrent linearization"(sorted=if divergent then ['c';'s']else ['r';'s']);
  check "concurrent exactly one row"(count path=1)

let crash_reopen()=
  List.iter(fun stage->let path=private_path()in
    let initialized=ok "crash initialize"(S.open_store ~path())in ignore(ok"crash close"(S.close initialized));
    let pid=Unix.fork()in
    if pid=0 then(let s=ok"child reopen"(S.open_store ~path())in
      S.For_test.on_stage s(fun seen->if seen=stage then Unix._exit 79);
      ignore(S.append s(receipt "crash-id"));Unix._exit 80);
    let _,status=Unix.waitpid[]pid in check"owned crash reached"(status=Unix.WEXITED 79);
    let s=ok"crash readback reopen"(S.open_store ~path())in
    let exists=Option.is_some(ok"crash exact get"(S.get s ~receipt_id:"crash-id"))in
    check"crash boundary durable state"(exists=(stage=S.For_test.After_commit));
    if exists then(match ok"postcommit lostACK replay"(S.append s(receipt "crash-id"))with S.Replayed _->check"lostACK idempotent"true|_->check"lostACK idempotent"false);
    ignore(ok"crash final close"(S.close s))) [S.For_test.After_insert;S.For_test.After_commit]

let seeded_oracle seed=
  with_store(fun path s->let rng=Random.State.make[|seed|]in
    let seen=Hashtbl.create 128 and last=ref 0 in
    for _n=1 to 80 do
      let replay= !last>0 && Random.State.int rng 3=0 in
      let seq=if replay then 1+Random.State.int rng !last else !last+1 in
      let id="oracle-"^string_of_int seq in
      let r=receipt ~seq id in
      let out=ok"oracle append"(S.append s r)in
      check"independent set replay law"(match out,Hashtbl.mem seen id with S.Stored _,false|S.Replayed _,true->true|_->false);
      Hashtbl.replace seen id ();last:=max !last seq;
      check"independent cardinality law"(count path=Hashtbl.length seen);
      let changed=ok"oracle conflicting value"(S.receipt_of_json(replace "observed_utc_us" (`Intlit "1793470000000001")(receipt_json ~seq id)))in
      err "oracle immutable binding law" S.Conflict(S.append s changed)
    done)

let write_all fd bytes=
  let rec loop offset=if offset<Bytes.length bytes then
    let n=Unix.write fd bytes offset(Bytes.length bytes-offset)in if n=0 then failwith"pipe closed"else loop(offset+n)in loop 0
let frame body=let n=String.length body in let b=Bytes.create(n+4)in
  for i=0 to 3 do Bytes.set b i(Char.chr((n lsr((3-i)*8))land 255))done;
  Bytes.blit_string body 0 b 4 n;b
let port ?(guarded=true) path bytes=
  let executable=Filename.concat(Filename.dirname Sys.executable_name)"symbiosis_receipt_port.exe"in
  let program,args,keep_open=match guardian,guarded with
    |Some guardian,true->guardian,[|guardian;executable;path;"1000"|],true
    |_->executable,[|executable;path|],false in
  let input_read,input_write=Unix.pipe ~cloexec:true()and output_read,output_write=Unix.pipe ~cloexec:true()in
  let pid=Unix.create_process program args input_read output_write Unix.stderr in
  Unix.close input_read;Unix.close output_write;write_all input_write bytes;
  if not keep_open then Unix.close input_write;
  let deadline=Unix.gettimeofday()+.5.0 and buffer=Buffer.create 4096 in
  let rec read()=
    let left=deadline-.Unix.gettimeofday()in
    if left<=0.0 then(Unix.kill pid Sys.sigkill;ignore(Unix.waitpid[]pid);failwith"port deadline");
    let ready,_,_=Unix.select[output_read][][]left in
    if ready=[]then read()else let bytes=Bytes.create 8192 in
    match Unix.read output_read bytes 0 8192 with
    |0->()|n->if Buffer.length buffer+n>S.max_response_bytes+4 then failwith"port output bound";
       Buffer.add_subbytes buffer bytes 0 n;read()in
  read();Unix.close output_read;if keep_open then Unix.close input_write;
  let _,status=Unix.waitpid[]pid in check"worker exits"(status=Unix.WEXITED 0);
  let bytes=Buffer.contents buffer in check"response frame header"(String.length bytes>=4);
  let n=ref 0 in for i=0 to 3 do n:=(!n lsl 8)lor Char.code bytes.[i]done;
  check"response exact frame"(!n=String.length bytes-4);
  ok"response strict JSON"(S.parse_json(String.sub bytes 4 !n))
let worker_controls()=
  let path=private_path()in
  let r=receipt_json "wire-one"in
  let out=port path(frame(request"append"["receipt",r]))in
  check"actual append worker"(member"status"out=`String"stored");
  check"native never authority"(member"authority"out=`String"NONE"&&member"admitted"out=`Bool false);
  let out=port path(frame(request"append"["receipt",r]))in
  check"actual worker replay"(member"status"out=`String"replayed");
  let out=port path(frame(request"get"["receipt_id",`String"wire-one"]))in
  check"actual worker get"(member"status"out=`String"found");
  List.iter(fun bytes->let target=private_path()in Unix.unlink target;
    let out=port ~guarded:false target bytes in
    check"bad wire hold"(member"status"out=`String"hold");
    check"invalid before DB creation"(not(Sys.file_exists target)))
    [Bytes.of_string"\000\000\000\001";Bytes.cat(frame"{}")(Bytes.of_string"x");
     frame"{\"schema_version\":1,\"operation\":\"get\",\"receipt_id\":\"x\",\"receipt_id\":\"y\"}";
     Bytes.of_string"\000\004\000\001"]

let ()=Fun.protect ~finally:cleanup(fun()->
  basics();json_controls();coverage_controls();failures();bounds();path_and_busy_controls();poisoned_and_readonly_controls();postcommit_uncertainty_controls();
  crash_reopen();concurrency false;concurrency true;gc_pressure_control();
  seeded_oracle 0x31;seeded_oracle 0x32;worker_controls();
  Printf.printf "symbiosis_check_receipts: %d checks PASS; existing_guardian=%b\n" !checks (Option.is_some guardian))
