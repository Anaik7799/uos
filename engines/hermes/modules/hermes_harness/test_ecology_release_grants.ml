module S=Ecology_release_grants
let checks=ref 0
let check label b=if not b then failwith("TEST FAILED: "^label);incr checks
let ok label=function Ok x->x|Error e->failwith(label^": "^S.error_code e)
let err label expected=function Error e->check label(e=expected)|Ok _->check label false
let field j k=Yojson.Safe.Util.member k j
let string=Yojson.Safe.Util.to_string
let status j=field j "status"|>string
let replace key value=function `Assoc xs->`Assoc(List.map(fun(k,v)->k,if k=key then value else v)xs)|_->assert false
let tag label="sha256:"^Digestif.SHA256.(to_hex(digest_string label))
let issue ?(rid="issue-a")?(grant="grant-a")?(intent="intent-a")?(expiry=5000L)()=`Assoc[
 "schema_version",`Int 1;"operation",`String"issue";"request_id",`String rid;"grant_id",`String grant;
 "intent_digest",`String(tag intent);"approval_digest",`String(tag"approval");"owner_binding_digest",`String(tag"owner");"expires_utc_ms",`Intlit(Int64.to_string expiry)]
let consume ?(rid="consume-a")?(grant="grant-a")?(step="step-a")?(epoch=1)?(generation=0)?(command="replace:0")()=`Assoc[
 "schema_version",`Int 1;"operation",`String"consume";"request_id",`String rid;"grant_id",`String grant;"step_digest",`String(tag step);"epoch",`Int epoch;"generation",`Int generation;"command",`String command]
let revoke ?(rid="revoke-a")?(grant="grant-a")?(reason="operator_revoked")()=`Assoc["schema_version",`Int 1;"operation",`String"revoke";"request_id",`String rid;"grant_id",`String grant;"reason",`String reason]
let lookup ?(grant="grant-a")step=`Assoc["schema_version",`Int 1;"operation",`String"lookup";"grant_id",`String grant;"step_digest",(match step with None->`Null|Some step->`String(tag step))]
let request json=ok "decode"(S.decode_request(Yojson.Safe.to_string json))
let run t json=S.execute t(request json)
let run_ok t json=ok "execute"(run t json)
let base=Filename.temp_file ~temp_dir:(Unix.realpath(Filename.get_temp_dir_name()))"uos-release-grants-tests-"""
let ()=Unix.unlink base;Unix.mkdir base 0o700
let serial=ref 0
let path()=incr serial;let p=base^"/fixture-"^string_of_int !serial in Unix.mkdir p 0o700;p^"/facts.sqlite3"
let open_clock ?limits path clock=ok "open"(S.For_test.open_with_clock ?limits ~path ~now_ms:(fun()-> !clock)())
let with_store ?limits f=let p=path()and clock=ref 1000L in let t=open_clock ?limits p clock in
 Fun.protect ~finally:(fun()->ignore(S.close t))(fun()->f p t clock)
let zero=Sys.opaque_identity(int_of_string"0")
let[@inline never]rec keep x=if zero<>0 then keep(Sys.opaque_identity x)
let raw path f=let db=Sqlite3.db_open ~mode:`NO_CREATE ~uri:false path in Fun.protect ~finally:(fun()->ignore(Fun.protect ~finally:(fun()->keep db)(fun()->Sqlite3.db_close db)))(fun()->f db)
let count path table=raw path(fun db->let out=ref(-1)in let rc=Sqlite3.exec db ~cb:(fun row _->out:=int_of_string(Option.get row.(0)))("SELECT COUNT(*) FROM "^table)in check "raw count succeeded"(rc=Sqlite3.Rc.OK);!out)
let events p=count p "ecology_release_grant_events_v1"
let grants p=count p "ecology_release_grants_v1"
let facts_only j=
 check "no native authority"(field j "authority"=`String"NONE");
 List.iter(fun key->check("false "^key)(field j key=`Bool false))["authorized";"admitted";"new_effect_permission"];
 check "closed envelope13"(List.length(Yojson.Safe.Util.to_assoc j)=13)
let basic()=with_store(fun p t clock->
 let created=run_ok t(issue())in facts_only created;check "fresh issued"(status created="issued");
 check "actual native test-clock issue timestamp"(field(field created "grant")"issued_utc_ms"=`Intlit"1000");
 check "closed grant15"(List.length(Yojson.Safe.Util.to_assoc(field created "grant"))=15);
 clock:=2000L;let replay=run_ok t(issue())in facts_only replay;check "issue replay fact"(status replay="issue_replayed"&&events p=1);
 err "new issue request ID cannot reissue grant" S.Conflict(run t(issue ~rid:"new-issue"()));
 err "intent unique across grant IDs" S.Conflict(run t(issue ~rid:"other-issue"~grant:"other-grant"()));
 let used=run_ok t(consume())in facts_only used;check "first consume is a durable fact"(status used="consumed"&&events p=2);
 check "closed step8"(List.length(Yojson.Safe.Util.to_assoc(field used "step"))=8);
 let expected=Option.get(S.request_digest(request(consume())))in check "consume request digest bound"(field used "request_digest"=`String expected);
 let duplicate=run_ok t(consume ~rid:"new-consume"())in facts_only duplicate;
 check "different request ID same step is historical original identity"(status duplicate="already_consumed"&&field duplicate "request_id"=`String"consume-a"&&events p=2);
 err "same request ID conflicting body" S.Conflict(run t(consume ~command:"restore:0"()));
 err "same tuple changed digest" S.Conflict(run t(consume ~rid:"collision"~step:"other-step"()));
 err "same digest changed tuple" S.Conflict(run t(consume ~rid:"collision"~generation:1()));
 clock:=2100L;let revoked=run_ok t(revoke())in facts_only revoked;check "revoke durable"(status revoked="revoked"&&events p=3);
 let historical=run_ok t(consume())in facts_only historical;check "historical consume after revoke never fresh"(status historical="already_consumed"&&field(field historical "grant")"revoked"=`Bool true);
 err "new step after revoke refused" S.Revoked(run t(consume ~rid:"new-step"~step:"new"~generation:1()));
 err "new grant cannot bypass revoked intent" S.Conflict(run t(issue ~rid:"resurrect"~grant:"resurrect"~expiry:6000L()));
 let old=run_ok t(revoke ~rid:"other-revoke"~reason:"owner_changed"())in check "already revoked original identity retained"(status old="already_revoked"&&field old "request_id"=`String"revoke-a");
 clock:=6000L;let found=run_ok t(lookup(Some"step-a"))in facts_only found;
 check "lookup facts expire and revoke independently"(field(field found "grant")"expired"=`Bool true&&field(field found "grant")"revoked"=`Bool true);
 check "lookup nullable current request identity"(field found "request_id"=`Null&&field found "request_digest"=`Null&&field found "event_index"=`Null);
 check "lookup exact consumed step"(field(field found "step")"request_id"=`String"consume-a");
 let absent=run_ok t(lookup ~grant:"absent"None)in facts_only absent;check "missing grant absent not ready"(status absent="absent"&&field absent "grant"=`Null&&field absent "step"=`Null);
 check "basic counts immutable"(grants p=1&&events p=3))
let parser()=
 let original=issue()in let request1=request original and request2=request(match original with `Assoc xs->`Assoc(List.rev xs)|_->assert false)in
 check "canonical request hash independent of object order"(S.request_digest request1=S.request_digest request2);
 List.iter(fun raw->check "malformed RFC JSON refused"(match S.decode_request raw with Error S.Invalid_json->true|_->false))
 ["";"{}true";"{\"schema_version\":1,\"schema_version\":1}";"[NaN]";"[1e0]";"[\"\\ud800\"]";"[\"\255\"]";String.make 262145 'x'];
 List.iter(fun(k,v)->err("closed issue field "^k)S.Invalid_request(S.decode_request(Yojson.Safe.to_string(replace k v original))))
 ["schema_version",`Int 2;"request_id",`String"bad id";"grant_id",`String(String.make 129 'a');"intent_digest",`String(String.make 64 'a');"approval_digest",`String("sha256:"^String.make 64 'A');"owner_binding_digest",`Null;"expires_utc_ms",`Int 0];
 (match original with `Assoc xs->List.iter(fun(k,v)->err "unknown key including caller clock refused" S.Invalid_request(S.decode_request(Yojson.Safe.to_string(`Assoc((k,v)::xs)))))["now_utc_ms",`Int 1000;"issued_utc_ms",`Int 1000;"db",`String"/other"]|_->());
 List.iter(fun cmd->err("command rejects "^cmd)S.Invalid_request(S.decode_request(Yojson.Safe.to_string(consume ~command:cmd()))))
 ["replace:00";"replace:-1";"replace:15";"restore:15";"stage_files";"delete";"resume_readers;rm"];
 List.iter(fun cmd->ignore(request(consume ~command:cmd()));check "closed valid p.command_key"true)
 (["stage";"fence_readers";"verify_candidate";"verify_previous";"resume_readers"]@List.concat_map(fun i->["replace:"^string_of_int i;"restore:"^string_of_int i])(List.init 15 Fun.id));
 List.iter(fun e->err "epoch bounds"S.Invalid_request(S.decode_request(Yojson.Safe.to_string(consume ~epoch:e()))))[0;-1];
 check "request body256KiB bound"(S.max_request_bytes=262144&&S.max_response_bytes=262144)
let expiry()=
 with_store(fun p t clock->ignore(run_ok t(issue()));clock:=5000L;
  err "consume at exact expiry refused"S.Expired(run t(consume()));check "expiry no consume row"(events p=1));
 with_store(fun _ t clock->ignore(run_ok t(issue ~expiry:3601000L()));clock:=3600999L;check "maximum1h TTL accepts prior boundary"(status(run_ok t(consume()))="consumed"));
 with_store(fun p t _->err "TTL over1h refused"S.Expired(run t(issue ~expiry:3601001L()));check "bad TTL leaves zero grant/events"(grants p=0&&events p=0));
 with_store(fun p t clock->ignore(run_ok t(issue()));S.For_test.on_stage t(function S.For_test.After_insert->clock:=5000L|_->());
  err "expiry during validation before commit rollback"S.Expired(run t(consume()));check "precommit expiry restores counts"(events p=1));
 with_store(fun p t clock->S.For_test.on_stage t(function S.For_test.Before_commit->clock:=5000L|_->());err "issue expires before commit refused"S.Expired(run t(issue()));check "issue rollback both tables"(events p=0&&grants p=0));
 with_store(fun p t clock->ignore(run_ok t(issue()));clock:=999L;err "persisted clock rollback refused"S.Clock_rollback(run t(consume()));clock:=0L;err "invalid clock refused"S.Invalid_clock(run t(consume()));check "clock holds preserve issue"(events p=1))
let faults()=
 with_store(fun p t _->S.For_test.on_stage t(function S.For_test.After_insert->failwith"after-insert"|_->());
  (try ignore(run t(issue()));check "expected rollback exception"false with Failure s->check "unexpected callback exception propagated"(s="after-insert"));check "unexpected rollback both tables"(events p=0&&grants p=0));
 with_store(fun p t _->S.For_test.on_stage t(function S.For_test.Commit_error->failwith"commit"|_->());err "commit failure uncertain"S.Commit_unknown(run t(issue()));check "failed commit no row"(events p=0&&grants p=0));
 with_store(fun p t _->S.For_test.on_stage t(function S.For_test.After_commit->failwith"lost ack"|_->());err "lost ACK uncertain"S.Commit_unknown(run t(issue()));check "lost ACK durable row retained"(events p=1&&grants p=1);
  S.For_test.on_stage t(fun _->());check "readonly reconciliation sees issue"(status(run_ok t(lookup None))="found");check "no replayed issue fresh"(status(run_ok t(issue()))="issue_replayed"));
 with_store(fun p t _->ignore(run_ok t(issue()));S.For_test.on_stage t(function S.For_test.After_commit->raw p(fun db->ignore(Sqlite3.exec db"DROP TRIGGER ecology_release_grants_no_delete_v1"))|_->());
  err "postcommit schema readback error unknown"S.Commit_unknown(run t(consume()));check "postcommit consume stays recorded"(events p=2));
 with_store(fun p t _->let nested=ref false in S.For_test.on_stage t(function S.For_test.After_insert->nested:=(run t(lookup None)=Error S.Nested_transaction)|_->());
  ignore(run_ok t(issue()));check "nested call refused without taking transaction" !nested;check "outer commit preserved"(events p=1));
 with_store(fun p t _->ignore(run_ok t(issue()));raw p(fun db->List.iter(fun sql->check "raw append-only UPDATE DELETE refused"(Sqlite3.exec db sql<>Sqlite3.Rc.OK))[
  "UPDATE ecology_release_grants_v1 SET expires_utc_ms=999999";"DELETE FROM ecology_release_grants_v1";"UPDATE ecology_release_grant_events_v1 SET observed_utc_ms=1";"DELETE FROM ecology_release_grant_events_v1"]);check "raw attempts no mutation"(events p=1&&grants p=1));
 with_store(fun p t _->raw p(fun db->ignore(Sqlite3.exec db"DROP INDEX ecology_release_grant_intent_v1"));err "schema trigger/index exactness refused"S.Schema_mismatch(run t(issue()));check "schema error no rows"(events p=0));
 with_store(fun p t _->raw p(fun db->ignore(Sqlite3.exec db"BEGIN IMMEDIATE");err "bounded busy refuses"S.Store_unavailable(run t(issue()));ignore(Sqlite3.exec db"ROLLBACK"));check "busy rollback unchanged"(events p=0))
let limits()=
 let limits={S.default_limits with max_grants=1;max_events=3}in
 with_store ~limits(fun p t _->ignore(run_ok t(issue()));ignore(run_ok t(consume()));
  err "forward consume holds preserving revoke escrow"S.Resource_bound(run t(consume ~rid:"second"~step:"second"~generation:1()));
  check "revocation uses reserved final slot"(status(run_ok t(revoke()))="revoked");
  check "historical replay remains fact at capacity"(status(run_ok t(consume()))="already_consumed");
  err "grant cap refuses fresh independent intent"S.Resource_bound(run t(issue ~rid:"other"~grant:"other"~intent:"other"()));check "capacity holds counts"(events p=3&&grants p=1));
 with_store ~limits:{S.default_limits with max_db_bytes=1048576}(fun p t _->
  err "byte escrow refuses forward issue before exhaustion"S.Resource_bound(run t(issue()));check "byte hold no partial grant"(grants p=0&&events p=0));
 List.iter(fun l->err "invalid limits fail before open"S.Resource_bound(S.open_store ~limits:l ~path:(path())()))[
 {S.default_limits with max_grants=0};{S.default_limits with max_grants=4097};{S.default_limits with max_events=32769};{S.default_limits with max_db_bytes=16777217}];
 let p=path()in let parent=Filename.dirname p in Unix.chmod parent 0o755;err "private parent required"S.Invalid_path(S.open_store ~path:p());
 let p=path()in let target=p^".target"in let fd=Unix.openfile target[Unix.O_CREAT;Unix.O_WRONLY]0o600 in Unix.close fd;Unix.symlink target p;err "symlink DB refuses"S.Invalid_path(S.open_store ~path:p());
 let p=path()in let fd=Unix.openfile p[Unix.O_CREAT;Unix.O_WRONLY]0o600 in Unix.close fd;Unix.link p(p^".alias");err "hardlink DB refuses"S.Invalid_path(S.open_store ~path:p());
 err "missing DB parent refused"S.Invalid_path(S.open_store ~path:(base^"/missing/facts.sqlite3")())
let crash()=
 List.iter(fun stage->let p=path()and clock=ref 1000L in
  let t=open_clock p clock in ignore(ok "close seed"(S.close t));
  let pid=Unix.fork()in if pid=0 then(let t=open_clock p clock in S.For_test.on_stage t(fun at->if at=stage then Unix._exit 77);ignore(run t(issue()));Unix._exit 90);
  let _,st=Unix.waitpid[]pid in check "bounded injected crash observed"(st=Unix.WEXITED 77);
  let t=open_clock p clock in let found=run_ok t(lookup None)in check "crash rollback or committed issue truth"(status found=(if stage=S.For_test.After_commit then "found"else "absent"));
  if stage=S.For_test.After_commit then check "restart exact replay historical only"(status(run_ok t(issue()))="issue_replayed");ignore(S.close t)
 )[S.For_test.After_insert;S.For_test.Before_commit;S.For_test.After_commit]
(* Independent finite set/boolean oracle: no SQL/query/row implementation is
   reused. Same public commands are interpreted by the oracle and real store. *)
let seeded_oracle()=
 List.iter(fun seed->let rng=Random.State.make[|seed|]in
  for _scenario=0 to 23 do with_store(fun p t clock->
   ignore(run_ok t(issue()));let seen=ref[]and revoked=ref false and expected_events=ref 1 in
   for _=0 to 19 do
    match Random.State.int rng 5 with
    |0->clock:=Int64.add !clock 50L
    |1->clock:=Int64.max !clock 5000L
    |2->let j=run_ok t(revoke())in
      check "oracle revoke monotonic"(status j=(if !revoked then "already_revoked"else "revoked"));
      if not !revoked then incr expected_events;revoked:=true
    |3->let j=run_ok t(lookup None)in
      check "oracle readback revoked/expiry independent"(field(field j"grant")"revoked"=`Bool !revoked && field(field j"grant")"expired"=`Bool(!clock>=5000L))
    |_->let key=Random.State.int rng 4 in let id="step-"^string_of_int key in
      let actual=run t(consume ~rid:id ~step:id ~generation:key ~command:("replace:"^string_of_int key)())in
      if List.mem key !seen then check "oracle consumed historical never fresh"(status(ok"historical"actual)="already_consumed")
      else if !revoked then err "oracle revoked veto"S.Revoked actual
      else if !clock>=5000L then err "oracle expiry veto"S.Expired actual
      else(check "oracle fresh fact"(status(ok"fresh"actual)="consumed");seen:=key::!seen;incr expected_events)
   done;
   check "oracle exact append count"(events p= !expected_events);
   check "oracle single immutable grant"(grants p=1))done
 )[17;91]
let concurrent()=
 for _=1 to 12 do
  let p=path()and clock=ref 1000L in let t=open_clock p clock in ignore(run_ok t(issue()));ignore(S.close t);
  (* Initialize each connection while its peer is idle, then release both
     operation barriers. Concurrent schema initialization itself may return
     the specified bounded busy HOLD; it is not a progress guarantee. *)
  let spawn operation=
   let rr,rw=Unix.pipe ~cloexec:true()and gr,gw=Unix.pipe ~cloexec:true()in
   let pid=Unix.fork()in if pid=0 then(
    Unix.close rr;Unix.close gw;let t=open_clock p clock in
    ignore(Unix.write_substring rw "r" 0 1);Unix.close rw;
    let signal=Bytes.create 1 in ignore(Unix.read gr signal 0 1);Unix.close gr;
    let result=run t operation in ignore(S.close t);
    Unix._exit(match result with Ok j when status j="consumed"||status j="revoked"->0|Error S.Revoked->10|_->90));
   Unix.close rw;Unix.close gr;
   let ready,_,_=Unix.select[rr][][]2. in
   if ready=[]then(Unix.kill pid Sys.sigkill;ignore(Unix.waitpid[]pid);failwith"connection barrier timeout");
   let signal=Bytes.create 1 in check "concurrent connection prepared"(Unix.read rr signal 0 1=1);Unix.close rr;pid,gw in
  let a,ga=spawn(consume())in let b,gb=spawn(revoke())in
  ignore(Unix.write_substring ga "g" 0 1);Unix.close ga;ignore(Unix.write_substring gb "g" 0 1);Unix.close gb;
  let _,sa=Unix.waitpid[]a and _,sb=Unix.waitpid[]b in
  check "consume/revoke linearizes in owned SQLite transaction"((sa=Unix.WEXITED 0||sa=Unix.WEXITED 10)&&sb=Unix.WEXITED 0);
  let t=open_clock p clock in let final=run_ok t(lookup(Some"step-a"))in
  check "concurrent final revoke permanent"(field(field final"grant")"revoked"=`Bool true);
  (match sa with Unix.WEXITED 10->check"revoke won no consume event"(field final"step"=`Null)|_->check"consume won durable fact retained"(field final"step"<>`Null));ignore(S.close t)
 done
let gc_and_open_failures()=
 let fds()=Array.length(Sys.readdir"/proc/self/fd")in let before=fds()in
 let stop=Atomic.make false in let collector=Domain.spawn(fun()->while not(Atomic.get stop)do Gc.full_major();Unix.sleepf 0.001 done)in
 Fun.protect ~finally:(fun()->Atomic.set stop true;Domain.join collector)(fun()->
  for _=1 to 16 do with_store(fun _ t _->ignore(run_ok t(issue()));ignore(run_ok t(consume()));ignore(run_ok t(revoke())))done;
  for _=1 to 8 do
   let p=path()in let o=open_out_bin p in output_string o"not-a-SQLite-fixture";close_out o;Unix.chmod p 0o600;
   let bytes=let i=open_in_bin p in let s=really_input_string i(in_channel_length i)in close_in i;s in
   check "malformed DB refuses with rooted cleanup"(match S.open_store ~path:p()with Error _->true|Ok t->ignore(S.close t);false);
   let i=open_in_bin p in let after=really_input_string i(in_channel_length i)in close_in i;check "malformed DB bytes preserved"(bytes=after)
  done);
 check "rooted open/close under GC no descriptor leak"(fds()=before)
let frame s=let h=Bytes.create 4 in for i=0 to 3 do Bytes.set h i(Char.chr((String.length s lsr((3-i)*8))land 255))done;Bytes.to_string h^s
let child ?guardian worker db wire=
 let ir,iw=Unix.pipe ~cloexec:true()and or_,ow=Unix.pipe ~cloexec:true()in let err=Unix.openfile"/dev/null"[Unix.O_WRONLY]0 in
 let exe,argv=match guardian with None->worker,[|worker;db|]|Some g->g,[|g;worker;db;"3000"|]in
 let pid=Unix.create_process exe argv ir ow err in Unix.close ir;Unix.close ow;Unix.close err;
 let rec send off=if off<String.length wire then let n=Unix.write_substring iw wire off(String.length wire-off)in if n<=0 then failwith"pipe"else send(off+n)in send 0;
 if guardian=None then Unix.close iw;
 let out=Buffer.create 4096 and b=Bytes.create 4096 and until=Unix.gettimeofday()+.4. in
 let rec collect()=if Unix.gettimeofday()>until then(Unix.kill pid Sys.sigkill;ignore(Unix.waitpid[]pid);failwith"child timeout");
  let r,_,_=Unix.select[or_][][]0.05 in if r=[]then collect()else let n=Unix.read or_ b 0 4096 in
  if n>0 then(Buffer.add_subbytes out b 0 n;check"wire output bound"(Buffer.length out<=262148);collect())in
 collect();Unix.close or_;if guardian<>None then Unix.close iw;
 let _,status=Unix.waitpid[]pid in check"real child reaped exit0"(status=Unix.WEXITED 0);
 let out=Buffer.contents out in check "exact frame header"(String.length out>=4);let n=ref 0 in for i=0 to 3 do n:=(!n lsl 8)lor Char.code out.[i]done;
 check"exact frame size"(!n=String.length out-4);Yojson.Safe.from_string(String.sub out 4 !n)
let port worker guardian=
 let p=path()in let expires=Int64.add(Int64.of_float(Unix.gettimeofday()*.1000.))60000L in
 let issue=issue ~expiry:expires()in
 let call json=child ~guardian worker p(frame(Yojson.Safe.to_string json))in
 let j=call issue in facts_only j;check "actual guarded issue"(status j="issued");
 let j=call(consume())in facts_only j;check "actual guarded consume"(status j="consumed");
 let j=call(lookup(Some"step-a"))in facts_only j;check "actual readback lost ACK safe"(status j="found"&&field j"step"<>`Null);
 let j=call(consume())in check "actual replay is AlreadyConsumed"(status j="already_consumed");
 let j=call(revoke())in facts_only j;check "actual guarded revoke"(status j="revoked");
 let j=call(consume ~rid:"new"~step:"new"~generation:1())in facts_only j;check "actual refused new consume"(status j="hold"&&field j"reason"=`String"revoked");
 List.iter(fun wire->let p=path()in let j=child worker p wire in check "malformed/trailing frame refused"(status j="hold");check "bad frame never opens DB"(not(Sys.file_exists p)))
 ["";"\000\000\000\000";"\255\255\255\255";frame(Yojson.Safe.to_string issue)^"x"]
let phase name f=f();Printf.printf "%s checks=%d PASS\n%!"name !checks
let ()=phase"parser"parser;phase"basic"basic;phase"expiry"expiry;phase"faults"faults;phase"limits"limits;phase"crash"crash;phase"seeded-oracle"seeded_oracle;phase"concurrent"concurrent;phase"GC-and-open-failures"gc_and_open_failures;
 (match Array.to_list Sys.argv with [_;"--worker";worker;"--guardian";guardian]->port worker guardian|[_]->()|_->failwith"test args");
 Printf.printf "%d checks PASS actual_guardian=%b scope=factual_storage_not_release_authority fixtures=%s\n%!" !checks(Array.length Sys.argv=5)base
