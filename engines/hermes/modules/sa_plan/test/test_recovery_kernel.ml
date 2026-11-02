(* Non-secret deterministic test vectors only. No real key, roster or DB read. *)
module K=Recovery_kernel
module S=Recovery_kernel_fixture
let count=ref 0
let check label b=incr count;if not b then failwith label
let ok=function Ok x->x|Error _->failwith"unexpected refusal"
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let cfgbytes=read Fixture_launcher.path
let cfg=ok(K.read_pinned_data ~path:Fixture_launcher.path ~sha256:Fixture_launcher.sha)
let hex s=String.concat""(List.init(String.length s)(fun i->Printf.sprintf"%02x"(Char.code s.[i])))
let key seed=ok(Mirage_crypto_ec.Ed25519.priv_of_octets(String.make 32 seed))
let signature seed message=hex(Mirage_crypto_ec.Ed25519.sign ~key:(key seed) message)
let request r=S.reclaim_request_bytes r
let json s=Yojson.Basic.from_string s
let change field value bytes=match json bytes with `Assoc fs->Yojson.Basic.to_string(`Assoc(List.map(fun(k,v)->k,if k=field then value else v)fs))|_->failwith"object fixture"
let data k=match json cfgbytes with `Assoc fs->List.assoc k fs|_->failwith"config fixture"
let cap r=
 let c=ok(K.native_clock())in
 Yojson.Basic.to_string(`Assoc[
 "domain",`String"uos.sa-plan.reclaim-three.effect-capability.v1";"profile",`String K.profile;
 "configuration_sha256",`String Fixture_launcher.sha;"request_sha256",`String(K.sha256(request r));
 "evidence_sha256",`String(String.make 64 'e');"context_sha256",`String(String.make 64 'c');
 "proposal_sha256",`String(String.make 64 'a');"portfolio_sha256",`String(String.make 64 'b');"selection_sha256",`String(String.make 64 'd');"factual_review_sha256",`String(String.make 64 'f');
 "source_sha256",data"source_sha256";"worker_sha256",data"worker_sha256";"guardian_sha256",data"guardian_sha256";
 "reviewer",`String"fixture-reviewer";"reviewer_session",`String"fixture-review-session";"issuer",`String"fixture-issuer";"issuer_session",`String"fixture-issuer-session";
 "host",data"host";"boot",data"boot";"clock_domain",`String c.domain;"epoch",`String"1";
 "issued_utc_ns",`String(Int64.to_string(Int64.sub c.utc_ns 1000000000L));
 "expires_utc_ns",`String(Int64.to_string(Int64.add c.utc_ns 20000000000L));
 "issued_mono_ns",`String(Int64.to_string(Int64.sub c.mono_ns 1000000000L));
 "expires_mono_ns",`String(Int64.to_string(Int64.add c.mono_ns 19000000000L))])
let signed r bytes=
 let review=signature 'R'(K.review_message bytes)in let issuer=signature 'I'(K.issuer_message bytes ~reviewer_signature:review)in
 K.verify cfg ~request_bytes:(request r)~capability_bytes:bytes ~reviewer_signature:review ~issuer_signature:issuer
let raw sql=
 let d=Sqlite3.db_open Fixture_launcher.database in Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close d);Core.Gc.keep_alive d)(fun()->if Sqlite3.exec d sql<>Sqlite3.Rc.OK then failwith(Sqlite3.errmsg d))
let fixture ?(schema=true) f=
 List.iter(fun suffix->let p=Fixture_launcher.database^suffix in if Sys.file_exists p then Sys.remove p)["";"-wal";"-shm"];
 let s=ok(S.open_db Fixture_launcher.database)in
 Fun.protect ~finally:(fun()->S.close s)(fun()->
 if schema then ignore(ok(S.initialize_cap_fixture s));
 let now=(ok(K.native_clock())).utc_ns in
 ignore(ok(S.create_plan s ~id:K.fixed_plan ~name:"private/recovery"~title:"fixture"~now_ns:now));
 List.iter(fun(id,worker)->ignore(ok(S.create_task s ~plan_id:K.fixed_plan ~id ~name:("private/"^id)~title:id ~parent_id:None ~dependencies:[] ~priority:0~now_ns:now));
 ignore(ok(S.claim_task s ~plan_id:K.fixed_plan ~task_id:id ~worker ~now_ns:(Int64.sub now 3000000000L)~lease_ns:1000000000L)))K.fixed_members;
 let _,sha=ok(S.recovery_snapshot_bounded s ~plan_id:K.fixed_plan)in
 let r=S.{reclaim_request_id="fixture-request";reclaim_plan_id=K.fixed_plan;expected_snapshot_sha256=sha;
 expired_tasks=List.map(fun(id,worker)->S.{reclaim_task_id=id;old_worker=worker;old_attempt=1;old_lease_until_ns=Int64.sub now 2000000000L})K.fixed_members;
 reclaim_lease_ns=10000000000L;request_deadline_ns=Int64.add now 30000000000L}in f s r)
let snapshot s=snd(ok(S.recovery_snapshot_bounded s ~plan_id:K.fixed_plan))
let refused=function Error _->true|_->false
let frame s=let n=String.length s in String.init 4(fun i->Char.chr((n lsr(8*(3-i)))land 255))^s
let exchange ?(guardian=true) ?(wire=None) executable locator body=
 let input,parent_input=Unix.pipe ~cloexec:true()and parent_output,output=Unix.pipe ~cloexec:true()in
 let null=Unix.openfile"/dev/null"[Unix.O_WRONLY]0 in
 let argv=if guardian then[|Fixture_launcher.guardian;executable;locator;"3000"|]else[|executable|]in
 let pid=Unix.create_process argv.(0)argv input output null in Unix.close input;Unix.close output;Unix.close null;
 let bytes=match wire with Some s->s|None->frame body in
 let b=Bytes.of_string bytes in let rec send n=if n<Bytes.length b then let k=Unix.write parent_input b n(Bytes.length b-n)in send(n+k)in send 0;
 (* Guardian input remains OPEN until response/reap; it closes worker stdin. *)
 if not guardian then Unix.close parent_input;
 let buffer=Buffer.create 1024 and chunk=Bytes.create 4096 and until=Unix.gettimeofday()+.5.0 in
 let rec drain()=
  let remaining=until-.Unix.gettimeofday()in if remaining<=0. then(Unix.kill pid Sys.sigkill;failwith"bounded fixture transport deadline");
  let ready,_,_=Unix.select[parent_output][][]remaining in
  if ready=[]then drain()else let n=Unix.read parent_output chunk 0 4096 in if n>0 then(Buffer.add_subbytes buffer chunk 0 n;if Buffer.length buffer>65536 then failwith"fixture response bound";drain())in
 drain();Unix.close parent_output;
 let _,status=Unix.waitpid[]pid in if guardian then Unix.close parent_input;
 let output=Buffer.contents buffer in
 if status<>Unix.WEXITED 0||String.length output<4 then Error"TRANSPORT_HOLD"else
 let n=ref 0 in for i=0 to 3 do n:=(!n lsl 8)lor Char.code output.[i]done;
 if !n<>String.length output-4 then Error"RESPONSE_FRAME"else Ok(String.sub output 4 !n)
let locator=Yojson.Basic.to_string(`List[`String Fixture_launcher.path;`String Fixture_launcher.sha;`String Fixture_launcher.database])
let wire r capability=
 let review=signature 'R'(K.review_message capability)in let issuer=signature 'I'(K.issuer_message capability ~reviewer_signature:review)in
 Yojson.Basic.to_string(`Assoc["operation",`String"commit";"request",`String(request r);"capability",`String capability;"reviewer_signature",`String review;"issuer_signature",`String issuer])
let status bytes=Yojson.Basic.Util.(to_string(member"status"(json bytes)))
let wait_until predicate seconds=
 let deadline=Unix.gettimeofday()+.seconds in
 let rec loop()=if predicate()then()else if Unix.gettimeofday()>=deadline then failwith"bounded fixture wait"else(ignore(Unix.select[][][]0.001);loop())in loop()
let native_after target=wait_until(fun()->(ok(K.native_clock())).mono_ns>=target)2.0
let fork_execute body=
 let input,wr=Unix.pipe ~cloexec:true()and rd,output=Unix.pipe ~cloexec:true()in
 let ready=Filename.temp_file ~temp_dir:(Filename.dirname Fixture_launcher.path)"ready-"""in Sys.remove ready;
 let loc=Yojson.Basic.to_string(`List[`String Fixture_launcher.path;`String Fixture_launcher.sha;`String Fixture_launcher.database;`String ready])in
 let null=Unix.openfile"/dev/null"[Unix.O_WRONLY]0 in
 let pid=Unix.create_process Fixture_launcher.worker[|Fixture_launcher.worker;loc|]input output null in
 Unix.close input;Unix.close output;Unix.close null;
 let bytes=Bytes.of_string(frame body)in let rec send n=if n<Bytes.length bytes then send(n+Unix.write wr bytes n(Bytes.length bytes-n))in send 0;Unix.close wr;
 (try wait_until(fun()->Sys.file_exists ready)2.0 with exn->Unix.kill pid Sys.sigkill;ignore(Unix.waitpid[]pid);raise exn);Unix.unlink ready;
 pid,rd
let reap_result(pid,rd)=
 let ready,_,_=Unix.select[rd][][]5.0 in if ready=[]then(Unix.kill pid Sys.sigkill;ignore(Unix.waitpid[]pid);failwith"child result deadline");
 let b=Bytes.create 4096 and buffer=Buffer.create 4096 in
 let rec drain()=let n=Unix.read rd b 0 4096 in if n>0 then(Buffer.add_subbytes buffer b 0 n;drain())in drain();Unix.close rd;
 let _,child_status=Unix.waitpid[]pid in check"owned native child actually reaped"(child_status=Unix.WEXITED 0);
 let bytes=Buffer.contents buffer in if String.length bytes<4 then failwith"child frame";
 match status(String.sub bytes 4(String.length bytes-4))with"COMMITTED"->"committed"|"HISTORICAL"->"historical"|"HOLD"->"refused"|_->"unknown"
let locked f=
 let d=Sqlite3.db_open Fixture_launcher.database in
 Fun.protect ~finally:(fun()->ignore(Sqlite3.exec d"ROLLBACK");ignore(Sqlite3.db_close d);Core.Gc.keep_alive d)(fun()->
  if Sqlite3.exec d"BEGIN IMMEDIATE"<>Sqlite3.Rc.OK then failwith"fixture lock";f d)
let compile_api source=
 let file=Filename.concat(Filename.dirname Fixture_launcher.path)"history_api.ml"in
 let c=open_out_bin file in output_string c source;close_out c;
 let own=Unix.realpath(Filename.dirname Sys.executable_name)in
 let parent=Filename.dirname own in
 let output=Unix.openfile(Filename.concat(Filename.dirname file)"compile.log")[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_TRUNC]0o600 in
 let input=Unix.openfile"/dev/null"[Unix.O_RDONLY]0 in
 let argv=[|"timeout";"5s";"/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocamlfind";"ocamlc";"-package";"core,digestif,sqlite3,yojson,mirage-crypto-ec,mtime.clock,ptime.clock,unix";
  "-I";Filename.concat own".recovery_kernel_fixture.objs/byte";"-I";Filename.concat parent".recovery_kernel.objs/byte";
  "-I";Filename.concat parent".sa_plan.objs/byte";"-c";file|]in
 let pid=Unix.create_process"/usr/bin/timeout"argv input output output in Unix.close input;Unix.close output;
 let _,status=Unix.waitpid[]pid in status,read(Filename.concat(Filename.dirname file)"compile.log")
let ()=
 check"fixture actual worker pin"(data"worker_sha256"=`String(K.sha256(read Fixture_launcher.worker)));
 check"fixture actual guardian pin"(data"guardian_sha256"=`String(K.sha256(read Fixture_launcher.guardian)));
 check"production owner absent"(K.production_owner_status()="ADMITTED_RECOVERY_OWNER_UNAVAILABLE");
 let prod=read"../sa_plan_store.ml"and ext=read"reclaim_fixture_extension.ml"and capext=read"recovery_kernel_fixture_extension.ml"in
 check"private module exact production source plus fixture extensions"(read"recovery_kernel_fixture.ml"="open Sa_plan__\n"^prod^ext^capext);
 check"production interface has no capability executor"(not(Astring.String.is_infix ~affix:"cap_execute"(read"../sa_plan_store.mli")));
 check"wrong caller configuration pin refused"(refused(K.read_pinned_data ~path:Fixture_launcher.path ~sha256:(String.make 64 '0')));
 let parent=Filename.dirname Fixture_launcher.path in
 let symlink=Filename.concat parent"symlink.json"and hardlink=Filename.concat parent"hardlink.json"in
 Unix.symlink Fixture_launcher.path symlink;
 check"configuration symlink refuses"(refused(K.read_pinned_data ~path:symlink ~sha256:Fixture_launcher.sha));Unix.unlink symlink;
 Unix.link Fixture_launcher.path hardlink;
 check"configuration hardlink refuses"(refused(K.read_pinned_data ~path:hardlink ~sha256:Fixture_launcher.sha));Unix.unlink hardlink;
 let c=Unix.openfile(Filename.concat parent"oversize.json")[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in
 let out=Unix.out_channel_of_descr c in output_string out(String.make 32769 'x');close_out out;
 check"oversize regular configuration refuses before parser"(refused(K.read_pinned_data ~path:(Filename.concat parent"oversize.json")~sha256:(String.make 64 '0')));
 let compiled,_=compile_api"let f p (h:Recovery_kernel.historical_evidence) = Recovery_kernel_fixture.cap_inspect_history p h\n"in
 check"actual history-only public read API compile positive"(compiled=Unix.WEXITED 0);
 List.iter(fun code->let compiled,errors=compile_api code in
  check"actual history-only type cannot reach commit or freshness"(compiled=Unix.WEXITED 2&&Astring.String.is_infix ~affix:"historical_evidence"errors&&Astring.String.is_infix ~affix:"verified_evidence"errors))
 ["let f s (h:Recovery_kernel.historical_evidence) = Recovery_kernel_fixture.cap_execute s h\n";
  "let f (h:Recovery_kernel.historical_evidence) = Recovery_kernel.still_valid h\n"];
 fixture(fun s r->let before=snapshot s and c=cap r in let e=ok(signed r c)in
  check"actual two-purpose Ed25519 positive"(K.request_bytes e=request r);
  check"verified evidence still has no production authority"(K.authority e="NONE_UNTIL_INDEPENDENT_LAUNCHER_AND_INGRESS_ADMISSION");
  let review=signature 'X'(K.review_message c)in let issuer=signature 'I'(K.issuer_message c ~reviewer_signature:review)in
  check"otherwise-consistent wrong reviewer signature"(refused(K.verify cfg ~request_bytes:(request r)~capability_bytes:c ~reviewer_signature:review ~issuer_signature:issuer));
  let review=signature 'R'(K.review_message c)in
  check"otherwise-consistent wrong issuer signature"(refused(K.verify cfg ~request_bytes:(request r)~capability_bytes:c ~reviewer_signature:review ~issuer_signature:(signature 'X'(K.issuer_message c ~reviewer_signature:review))));
  check"swapped signed purposes refuse"(refused(K.verify cfg ~request_bytes:(request r)~capability_bytes:c ~reviewer_signature:(signature 'R'(K.issuer_message c ~reviewer_signature:review))~issuer_signature:(signature 'I'(K.review_message c))));
  check"native actual VM domain is separate"(refused(signed r(change"clock_domain"(`String"beam-vm-fixture")c)));
  check"production framed worker refuses even valid fixture evidence"(status(ok(exchange ~guardian:false Fixture_launcher.production""(wire r c)))="HOLD");
  check"production refusal has no task mutation"(snapshot s=before);
  let result=ok(exchange Fixture_launcher.worker locator(wire r c))in
  check"actual guardian framed crypto-to-SQLite commit"(status result="COMMITTED");
  check"all three actual attempts advance"(List.for_all(fun(id,_)->match ok(S.find_task s ~plan_id:K.fixed_plan ~id_or_name:id)with Some t->t.attempt=2|_->false)K.fixed_members);
  check"actual dual context/factual receipt durable"(Option.is_some(ok(S.cap_reconcile s e)));
  check"actual exact replay historical only"(status(ok(exchange Fixture_launcher.worker locator(wire r c)))="HISTORICAL");
  check"replay does not increment"(List.for_all(fun(id,_)->match ok(S.find_task s ~plan_id:K.fixed_plan ~id_or_name:id)with Some t->t.attempt=2|_->false)K.fixed_members));
 fixture(fun _ r->let c=cap r in
  List.iter(fun k->check("valid signatures but changed fixed binding "^k)(refused(signed r(change k(`String(String.make 64 '0'))c))))
   ["configuration_sha256";"request_sha256";"source_sha256";"worker_sha256";"guardian_sha256"];
  List.iter(fun k->check("valid signatures but changed identity/domain "^k)(refused(signed r(change k(`String"different")c))))
   ["domain";"profile";"reviewer";"reviewer_session";"issuer";"issuer_session";"host";"boot";"clock_domain";"epoch"];
  List.iter(fun malformed->check"otherwise-valid noncanonical JSON refused"(refused(signed r malformed)))
   [" "^c;"/*x*/"^c;String.sub c 0(String.length c-1)^",\"x\":0}";change"expires_utc_ns"(`String"999999999999999999999999999999")c;c^"\000"];
  let now=ok(K.native_clock())in
  check"actual expired signed evidence refuses"(refused(signed r(change"expires_utc_ns"(`String(Int64.to_string(Int64.sub now.utc_ns 1L)))c)));
  check"actual future signed evidence refuses"(refused(signed r(change"issued_utc_ns"(`String(Int64.to_string(Int64.add now.utc_ns 10000000000L)))c))));
 fixture ~schema:false(fun s r->let before=snapshot s in check"missing schema no silent migration"(refused(S.cap_execute s(ok(signed r(cap r)))));check"missing schema no task effect"(before=snapshot s));
 List.iter(fun sql->fixture(fun s r->raw sql;let before=snapshot s in
  check"exact stale tuple or full set changed refuses"(refused(S.cap_execute s(ok(signed r(cap r)))));
  check"stale refusal rolls all back"(snapshot s=before)))
 ["UPDATE sa_plan_task SET worker='different' WHERE id='OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT'";
  "UPDATE sa_plan_task SET attempt=2 WHERE id='OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT'";
  "INSERT INTO sa_plan_task(plan_id,id,name,ordinal,task_type,title,state,worker,attempt,lease_until_ns) SELECT plan_id,'fourth','private/fourth',4,'task','fourth','executing','fourth',1,1 FROM sa_plan_task LIMIT 1"];
 List.iter(fun sql->fixture(fun s r->raw sql;let before=snapshot s in
  check"actual malicious trigger postgoal rolls back"(refused(S.cap_execute s(ok(signed r(cap r)))));
  check"trigger task mutation rolled back"(snapshot s=before);
  check"trigger no auth/factual receipt survives"(ok(S.cap_reconcile s(ok(signed r(cap r))))=None)))
 ["CREATE TRIGGER corrupt AFTER UPDATE ON sa_plan_task WHEN OLD.id='OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT' BEGIN UPDATE sa_plan_task SET worker='corrupt' WHERE id=OLD.id; END";
  "CREATE TRIGGER corrupt AFTER INSERT ON sa_plan_recovery_cap_receipt BEGIN UPDATE sa_plan_task SET state='available' WHERE id='OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT'; END";
  "CREATE TRIGGER fail_second BEFORE UPDATE ON sa_plan_task WHEN OLD.id='OI02E_RELEASE_AUTHORITY_PREPARATION' BEGIN SELECT RAISE(ABORT,'fixture partial failure'); END"];
 fixture(fun s r->let e=ok(signed r(cap r))in let before=snapshot s in
  raw"DROP TRIGGER sa_plan_recovery_cap_no_delete";
  check"tampered schema refuses"(refused(S.cap_execute s e));check"tampered schema no task effects"(snapshot s=before));
 fixture(fun s r->let c=cap r in let e=ok(signed r c)in
  let b=wire r c in check"trailing wire refused"(status(ok(exchange Fixture_launcher.worker locator(b^" ")))="HOLD");
  check"bad wire no mutation"(snapshot s=r.S.expected_snapshot_sha256);
  ignore(ok(S.cap_execute s e));
  let e2=ok(signed r(change"proposal_sha256"(`String(String.make 64 '9'))c))in
  check"same request different authenticated context refuses"(refused(S.cap_execute s e2));
  check"original receipt remains exact"(Option.is_some(ok(S.cap_reconcile s e))));
 fixture(fun s r->
  let c=cap r and now=ok(K.native_clock())in
  let c=change"expires_utc_ns"(`String(Int64.to_string(Int64.add now.utc_ns 300000000L)))c
   |>change"expires_mono_ns"(`String(Int64.to_string(Int64.add now.mono_ns 250000000L)))in
  let _=ok(signed r c)and before=snapshot s in
  let result=locked(fun d->let child=fork_execute(wire r c)in native_after(Int64.add now.mono_ns 300000000L);ignore(Sqlite3.exec d"COMMIT");reap_result child)in
  check"actual lock wait across signed deadline refuses after lock"(result="refused");check"expired-after-lock has no partial effects"(snapshot s=before));
 fixture(fun s r->let body=wire r(cap r)and before=snapshot s in
  let result=locked(fun d->let child=fork_execute body in
   if Sqlite3.exec d"UPDATE sa_plan_task SET worker='concurrent-owner' WHERE id='OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT'"<>Sqlite3.Rc.OK then failwith"concurrent mutation";
   ignore(Sqlite3.exec d"COMMIT");reap_result child)in
  check"concurrent owner changed while waiting refuses"(result="refused");
  check"concurrent change persisted but reclaim did not advance attempts"(snapshot s<>before&&List.for_all(fun(id,_)->match ok(S.find_task s ~plan_id:K.fixed_plan ~id_or_name:id)with Some t->t.attempt=1|_->false)K.fixed_members));
 fixture(fun s r->let body=wire r(cap r)in
  let a,b=locked(fun d->let a=fork_execute body and b=fork_execute body in ignore(Sqlite3.exec d"COMMIT");reap_result a,reap_result b)in
  check"overlapping exact requests commit once then historical"(List.sort String.compare[a;b]=["committed";"historical"]);
  check"overlap only one lease attempt change"(List.for_all(fun(id,_)->match ok(S.find_task s ~plan_id:K.fixed_plan ~id_or_name:id)with Some t->t.attempt=2|_->false)K.fixed_members));
 fixture(fun s r->let body1=wire r(cap r)in let r2={r with S.reclaim_request_id="conflicting-request"}in let body2=wire r2(cap r2)in
  let a,b=locked(fun d->let a=fork_execute body1 and b=fork_execute body2 in ignore(Sqlite3.exec d"COMMIT");reap_result a,reap_result b)in
  check"overlapping distinct requests one commit one stale-set refusal"(List.sort String.compare[a;b]=["committed";"refused"]);
  check"distinct overlap cannot double increment"(List.for_all(fun(id,_)->match ok(S.find_task s ~plan_id:K.fixed_plan ~id_or_name:id)with Some t->t.attempt=2|_->false)K.fixed_members));
 fixture(fun s r->
  let capability=cap r in let e=ok(signed r capability)in
  (* Fill stdout BEFORE spawning. The actual worker blocks only while sending
     its framed response AFTER COMMIT. No executor hook/clock is injected. *)
  let input,parent_input=Unix.pipe ~cloexec:true()and parent_output,output=Unix.pipe ~cloexec:true()in
  Unix.set_nonblock output;let b=Bytes.make 4096 'x'in
  let rec fill()=try ignore(Unix.write output b 0 4096);fill()with Unix.Unix_error((Unix.EAGAIN|Unix.EWOULDBLOCK),_,_)->()in fill();Unix.clear_nonblock output;
  let null=Unix.openfile"/dev/null"[Unix.O_WRONLY]0 in
  let pid=Unix.create_process Fixture_launcher.worker[|Fixture_launcher.worker;locator|]input output null in
  Unix.close input;Unix.close output;Unix.close null;
  let bytes=Bytes.of_string(frame(wire r capability))in let rec send n=if n<Bytes.length bytes then send(n+Unix.write parent_input bytes n(Bytes.length bytes-n))in send 0;Unix.close parent_input;
  wait_until(fun()->Option.is_some(ok(S.cap_reconcile s e)))2.0;
  Unix.kill pid Sys.sigkill;let _,reaped=Unix.waitpid[]pid in Unix.close parent_output;
  check"actual kill after COMMIT before ACK has genuine reaping"(reaped=Unix.WSIGNALED Sys.sigkill);
  check"lost ACK reconciles committed authenticated historical fact"(Option.is_some(ok(S.cap_reconcile s e)));
  check"lost ACK retry cannot reexecute"(match ok(S.cap_execute s e)with S.Cap_historical _->true|_->false));
 fixture(fun s r->let e=ok(signed r(cap r))and before=snapshot s in
  locked(fun _->let pid,rd=fork_execute(wire r(cap r))in Unix.kill pid Sys.sigkill;ignore(Unix.waitpid[]pid);Unix.close rd);
  check"actual killed lock-waiter leaves no effects"(snapshot s=before);
  check"actual killed lock-waiter leaves no causal receipt"(ok(S.cap_reconcile s e)=None));
 fixture(fun s r->
  let now=ok(K.native_clock())in
  let c=cap r|>change"expires_utc_ns"(`String(Int64.to_string(Int64.add now.utc_ns 300000000L)))
   |>change"expires_mono_ns"(`String(Int64.to_string(Int64.add now.mono_ns 250000000L)))in
  check"history regression genuine pre-expiry framed commit"(status(ok(exchange Fixture_launcher.worker locator(wire r c)))="COMMITTED");
  native_after(Int64.add now.mono_ns 350000000L);
  let before=snapshot s in
  let inspect=change"operation"(`String"inspect")(wire r c)in
  check"new framed worker after expiry recovers original signed history"(status(ok(exchange Fixture_launcher.worker locator inspect))="HISTORICAL");
  check"expired signature history read does not mutate projection"(before=snapshot s);
  check"same expired bytes cannot commit or rearm"(status(ok(exchange Fixture_launcher.worker locator(wire r c)))="HOLD");
  check"expired commit refusal does not increment"(before=snapshot s);
  check"historical replay stays historical"(status(ok(exchange Fixture_launcher.worker locator inspect))="HISTORICAL");
  let bad=change"reviewer_signature"(`String(String.make 128 '0'))inspect in
  check"expired history still requires actual valid signatures"(status(ok(exchange Fixture_launcher.worker locator bad))="HOLD");
  let conflict=wire r(change"proposal_sha256"(`String(String.make 64 '9'))c)|>change"operation"(`String"inspect")in
  check"expired history rejects re-signed conflicting context"(status(ok(exchange Fixture_launcher.worker locator conflict))="HOLD");
  check"all expired history controls no task mutation"(before=snapshot s));
 fixture(fun s r->
  let now=ok(K.native_clock())in
  let c=cap r|>change"expires_utc_ns"(`String(Int64.to_string(Int64.add now.utc_ns 300000000L)))
   |>change"expires_mono_ns"(`String(Int64.to_string(Int64.add now.mono_ns 250000000L)))in
  let before=snapshot s in native_after(Int64.add now.mono_ns 350000000L);
  let inspect=change"operation"(`String"inspect")(wire r c)in
  let response=ok(exchange Fixture_launcher.worker locator inspect)in
  check"expired valid signature without durable receipt is not committed"(status response="HOLD"&&Yojson.Basic.Util.(to_string(member"code"(json response)))="ABSENT_RECONCILE_ONLY");
  check"absent history cannot execute"(status(ok(exchange Fixture_launcher.worker locator(wire r c)))="HOLD");
  check"absent history controls no changes"(before=snapshot s));
 Printf.printf"PASS %d native recovery fixture checks; production owner unavailable; authority NONE\n"!count
