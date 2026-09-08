#!/usr/bin/env ocaml
#use "release_process.ml";;
(* argv-only common operational core; no deployment or peer dispatch. *)
let jstr x = `String x
let jint x = `Int x
let jfloat x = `Float x
let jbool x = `Bool x
let jobj x = `Assoc x
let jarr x = `List x
let jnull = `Null
let json = Yojson.Safe.to_string
let session="codex-side-unification-20260908-0701"
let plan_id="uos/unification-cycles/20260908-0701"
let worker="codex-side-unification-cycles"
let zenoh="http://nas-1.tail55d152.ts.net:8080"
let digest s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s |> Cryptokit.transform_string(Cryptokit.Hexa.encode())
let contains s needle=
 let n=String.length needle in let rec loop i=i+n<=String.length s&&(String.sub s i n=needle||loop(i+1))in loop 0
let first_json text=
 String.split_on_char '\n' text |> List.find_map(fun s->try Some(Yojson.Safe.from_string s)with _->None)|>Option.get
type focus={id:string;domain:string;layer:int;aspects:int list;factors:int list;deps:string list;kind:string;purpose:string}
let f id domain layer aspects factors deps kind purpose={id;domain;layer;aspects;factors;deps;kind;purpose}
let catalog=[
 f "C01" "control" 0 [17] [5;5;5;5;5] [] "authority" "Current task, clock and cooperative ownership";
 f "C02" "dynamic" 1 [4;7] [5;4;4;5;4] ["C01"] "clock" "Clock uncertainty versus logical ordering";
 f "C03" "static" 2 [2;3;5] [4;4;4;5;4] ["C01"] "package" "Complete artifact bytes and candidate";
 f "C04" "structural" 2 [2;3] [4;4;4;4;4] ["C03"] "source" "Application source equals tested release";
 f "C05" "dynamic" 3 [4] [5;5;4;5;4] ["C03"] "identity" "Actual private OTP/ERTS and process identity";
 f "C06" "dynamic" 3 [4;17] [5;5;5;5;5] ["C01"] "production" "Production declaration and recovery gaps";
 f "C07" "control" 0 [6;7;17] [4;5;4;4;4] ["C01"] "checker" "Bounded process and12 stage negatives";
 f "C08" "structural" 4 [6;7] [4;4;4;4;3] ["C07"] "prefix" "Independent transition model agreement";
 f "C09" "structural" 4 [4;7;11;13] [4;4;4;4;4] ["C04";"C08"] "unit" "Fresh Gleam contracts and FPP tests";
 f "C10" "static" 2 [1;5;6] [4;4;4;4;3] ["C03"] "corruption" "Private-copy corruption rejection";
 f "C11" "data" 3 [4;13] [4;4;4;3;3] ["C05"] "tui-real" "Observed counters, unavailable health";
 f "C12" "data" 3 [13] [3;3;3;3;3] ["C11"] "tui-test" "Explicit simulated disturbance";
 f "C13" "data" 3 [13] [4;4;4;3;3] ["C11"] "tui-unavailable" "Missing TUI evidence cannot be healthy";
 f "C14" "control" 5 [11;12;13;14] [4;4;4;4;4] ["C05";"C09"] "browser" "Rendered controls, updates and layouts";
 f "C15" "data" 5 [11;13] [4;4;4;4;3] ["C05"] "api-real" "Real API provenance";
 f "C16" "data" 5 [11;13] [4;4;4;4;3] ["C15"] "api-unavailable" "503 for unavailable source";
 f "C17" "data" 5 [11;13] [3;3;3;3;3] ["C15"] "api-test" "Changing explicitly simulated scenarios";
 f "C18" "dynamic" 5 [11;13] [4;4;4;3;3] ["C14"] "stream" "Fresh browser stale/reorder evidence";
 f "C19" "control" 6 [10;17] [4;4;4;4;4] ["C01"] "board" "Actual registry; no inferred peer ACK";
 f "C20" "data" 6 [10] [4;4;4;4;4] ["C19"] "mirror" "Exact own-cycle Zenoh readback";
 f "C21" "static" 7 [14] [3;4;3;3;4] ["C14"] "navigation" "Fresh eight-route navigation evidence";
 f "C22" "wiki" 7 [16] [3;3;3;3;4] ["C05"] "wiki" "Wiki rendering and engine source";
 f "C23" "zk" 8 [16] [3;3;3;3;4] ["C05"] "zk" "ZK index and source record inventory";
 f "C24" "km" 8 [16] [4;4;4;4;4] ["C22";"C23"] "km" "Served raw SOP equals source bytes";
 f "C25" "structural" 4 [7;8] [4;5;4;4;4] ["C04"] "atlas" "Declaration flags versus proof";
 f "C26" "dynamic" 6 [8;9] [4;5;4;4;4] ["C04"] "forecast" "Demonstration versus live calibration";
 f "C27" "control" 0 [6;8] [4;4;4;3;3] ["C04"] "rete" "Rule source versus runtime integration";
 f "C28" "structural" 8 [6;7] [4;5;4;4;4] ["C04"] "formal" "Invocation-specific formal evidence";
 f "C29" "km" 9 (List.init 17((+)1)) [4;4;4;4;5] ["C24";"C25";"C26";"C27";"C28"] "coverage" "Account for all17 aspects, preserve unknowns";
 f "C30" "control" 9 [10;15;16;17] [5;5;4;5;5] (List.init 29(fun i->Printf.sprintf "C%02d"(i+1))) "closure" "Reconcile30 decisions and publication receipts"
]
let score xs=require(List.length xs=5&&List.for_all(fun n->n>=1&&n<=5)xs)"invalid risk factors";List.fold_left( * )1 xs
let adjusted failures x=List.mapi(fun i n->if i=4&&List.mem x.domain failures then min 5(n+1)else n)x.factors
let choose done_ids failures pending=
 let ready=List.filter(fun x->List.for_all(fun d->List.mem d done_ids)x.deps)pending in
 match List.sort(fun a b->let c=compare(score(adjusted failures b))(score(adjusted failures a))in if c=0 then String.compare a.id b.id else c)ready with
 |x::_->x|[]->failwith "dependency deadlock"
let plan_json()=jarr(List.map(fun x->jobj[
 "id",jstr x.id;"domain",jstr x.domain;"layer",jint x.layer;"aspects",jarr(List.map jint x.aspects);
 "factors",jarr(List.map jint x.factors);"dependencies",jarr(List.map jstr x.deps);"check",jstr x.kind;"purpose",jstr x.purpose])catalog)
let selection_table()=
 let out=Buffer.create 4096 in
 for a=1 to 5 do for b=1 to 5 do for ready=0 to 1 do for failed=0 to 1 do
 let deps=if ready=1 then [] else ["not_observed"] in
 let left=f "a" "data" 1 [] [a;1;1;1;1] deps "" "" and right=f "b" "static" 1 [] [b;1;1;1;1] deps "" "" in
 let picked=try if (choose [] (if failed=1 then ["data"] else []) [left;right]).id="a" then 0 else 1 with Failure _ -> -1 in
 Buffer.add_string out(Printf.sprintf "%d %d %d %d %d\n"a b ready failed picked)
 done done done done;Buffer.contents out
let selfcheck()=
 let n=ref 0 in let check b label=require b label;incr n in let rejects f=try f();false with _->true in
 check(List.length catalog=30)"thirty focuses";
 check(List.length(List.sort_uniq String.compare(List.map(fun x->x.id)catalog))=30)"unique IDs";
 check(List.length(List.sort_uniq compare(List.map(fun x->x.layer)catalog))=10)"ten layers";
 check(List.length(List.sort_uniq String.compare(List.map(fun x->x.domain)catalog))=8)"eight domains";
 check(List.sort_uniq compare(List.concat_map(fun x->x.aspects)catalog)=List.init 17((+)1))"seventeen aspects";
 let rec walk todo done_ids=match todo with []->done_ids|_->let x=choose done_ids [] todo in walk(List.filter(fun y->x.id<>y.id)todo)(x.id::done_ids)in
 check(List.length(walk catalog [])=30)"acyclic closure";
 check(rejects(fun()->ignore(score[0;1;1;1;1])))"unknown not zero";
 check(rejects(fun()->ignore(score[6;1;1;1;1])))"factor ceiling";
 check(rejects(fun()->ignore(choose [] [] [List.nth catalog 29])))"no dependency skip";
 let a=f "a" "data" 1 [] [1;1;1;1;1] [] "" "" and b=f "b" "static" 1 [] [1;1;1;1;2] [] "" "" in
 check((choose [] [] [a;b]).id="b")"risk order";
 check((choose [] ["data"] [a;b]).id="a")"failure-sensitive reassessment";
 check((choose [] [] [a;{b with factors=a.factors}]).id="a")"stable tie";
 check(digest "x"<>digest "y")"substitution";
 check(List.length(String.split_on_char '\n'(String.trim(selection_table())))=100)"model100";
 emit "unification-selftest" "PASS" ["checks",jint !n]
let coord args=
 require(List.for_all(fun s->not(String.contains s '\\')&&not(String.contains s '"')&&not(String.contains s '\n'))args)"unsafe coordinator string";
 let q s="<<\""^s^"\">>"in
 let params=String.concat ","(List.map q((canonical^"/var/coordination/tri-agent")::args))in
 let expr="case session_sync_cli:run(["^params^"]) of {ok,B}->io:put_chars(B),halt(0);{error,E}->io:put_chars(E),halt(1) end."in
 let lib=canonical^"/apps/uos_swarm/build/dev/erlang"in
 let paths=Sys.readdir lib|>Array.to_list|>List.filter_map(fun d->let p=lib^"/"^d^"/ebin"in if Sys.file_exists p then Some p else None)in
 checked(otp^"/erl")(["+S";"2:2";"-noshell";"-pa"]@paths@["-eval";expr])|>Yojson.Safe.from_string
let request base path=
 target base;let prefix="http://nas-1.tail55d152.ts.net:"in let p=String.sub base(String.length prefix)(String.length base-String.length prefix)in
 let resolve=if port p>=49152 then["--resolve";"nas-1.tail55d152.ts.net:"^p^":127.0.0.1"]else[]in
 let r=run ~seconds:10. "/usr/bin/curl"(["--noproxy";"*";"--silent";"--show-error";"--max-time";"6";"--max-filesize";"1048576";"-w";"\n%{http_code}"]@resolve@[base^path])in
 require(r.code=0)"HTTP transport";let cut=String.rindex r.output '\n'in
 int_of_string(String.sub r.output(cut+1)(String.length r.output-cut-1)),String.sub r.output 0 cut
let risk_binary=lazy(
 let source=source_root()^"/plugins/uos-risk-prioritization/validation"in
 let before=inventory source and build=temp "uos-unification-risk-"in
 let links=build^"/existing-runtime-links"in mkdir links 0o700;
 let libraries=List.map(fun(name,filename)->let actual=realpath("/usr/lib/x86_64-linux-gnu/"^filename)in
  require((stat actual).st_kind=S_REG)"runtime library missing";symlink actual(links^"/"^name);actual,sha actual)
 ["libsqlite3.so","libsqlite3.so.0";"libgmp.so","libgmp.so.10"]in
 write_new(build^"/existing-runtime-libraries.json")(json(jobj(List.map(fun(p,h)->p,jstr h)libraries)));
 ignore(checked ~seconds:90. ~extra:["DUNE_CACHE=disabled";"LIBRARY_PATH="^links] "/home/an/dev/ver/zigvm/_opam/bin/dune"
 ["build";"-j";"1";"--root";source;"--build-dir";build;"./validate.exe"]);
 require(inventory source=before)"risk checker source changed during build";
 require(List.for_all(fun(p,h)->sha p=h)libraries)"runtime library changed during build";
 build^"/default/validate.exe")
let active risk=let binary=Lazy.force risk_binary in in_dir canonical(fun()->checked ~seconds:10. binary["--active-check";risk;"RUN30";worker;"1"]|>first_json)
let mirror key doc temp_file=
 write_new temp_file(json doc);
 ignore(checked ~seconds:10. "/usr/bin/curl"["--noproxy";"*";"--silent";"--show-error";"--fail";"--max-time";"6";"--request";"PUT";"-H";"Content-Type: application/json";"--data-binary";"@"^temp_file;zenoh^"/"^key]);
 let samples=fetch zenoh("/"^key)|>Yojson.Safe.from_string|>Yojson.Safe.Util.to_list in
 require(List.exists(fun item->try let xs=assoc item in str(field "key"xs)=key&&Yojson.Safe.equal(field "value"xs)doc with _->false)samples)"Zenoh exact readback missing"
let listen ()=
 let board=coord["inbox";session]|>assoc|>field "messages"|>Yojson.Safe.Util.to_list in
 let last=List.filteri(fun i _->i>=List.length board-10)board in
 let messages=List.map(fun m->let m=assoc m in let e=assoc(field "envelope" m)in
  jobj["id",field "message_id" m;"from",field "from" e;"timestamp",field "ts_iso" e;"lamport",field "lamport" e;"payload",field "payload" e])last in
 let raw=fetch zenoh "/uos/tui/state/*" in
 let samples=Yojson.Safe.from_string raw|>Yojson.Safe.Util.to_list in
 let states=List.map(fun item->let a=assoc item in jobj["key",field "key" a;"timestamp",field "timestamp" a;"value_sha256",jstr(digest(json(field "value" a)))])samples in
 jobj["schema",jstr"uos.unification-inbound.v1";"authority",jstr"NONE";
 "interpretation",jstr"Peer observations and declarations; never execution authority or proof";
 "board_inbox_count",jint(List.length board);"board_last10",jarr messages;"zenoh_samples",jarr states;"zenoh_response_sha256",jstr(digest raw)]
let validate_real_api doc=
 let a=assoc doc in require(str(field "status"a)="observed")"real API status";
 require(field "metrics"a=`Null&&str(field "verification"a)="not_verified"&&str(field "control_authority"a)="none")"real API authority";
 let runtime=field "runtime"a|>assoc in
 List.iter(fun k->require(int(field k runtime)>=0)("negative runtime "^k))["scheduler_count";"process_count";"memory_total_mib";"run_queue_length";"uptime_seconds"];
 require(int(field "scheduler_count"runtime)>0&&int(field "process_count"runtime)>0)"empty runtime";
 let age=int(field "age_us"a)and ttl=int(field "ttl_us"a)in require(age>=0&&ttl>0&&ttl<=5000000&&age<=ttl)"stale runtime";
 let fields=field "fields"a|>Yojson.Safe.Util.to_list|>List.map(fun v->let x=assoc v in str(field "id"x),str(field "value"x))in
 require(List.assoc "health"fields="UNKNOWN")"invented health";
 List.iter(fun (display,k)->require(List.assoc display fields=string_of_int(int(field k runtime)))"runtime projection differs")
 ["schedulers","scheduler_count";"processes","process_count";"vm_memory","memory_total_mib";"run_queue","run_queue_length";"uptime","uptime_seconds"]
let transport_envelope doc=
 let bytes=json doc in jobj["schema",jstr"uos.evidence-bytes.v1";"payload_sha256",jstr(digest bytes);"payload_json",jstr bytes;"authority",jstr"NONE"]
let validate_envelope original received=
 let a=assoc received in keys["schema";"payload_sha256";"payload_json";"authority"]a;
 require(str(field "schema"a)="uos.evidence-bytes.v1"&&str(field "authority"a)="NONE")"envelope schema/authority";
 let bytes=str(field "payload_json"a)in require(bytes=json original&&str(field "payload_sha256"a)=digest bytes)"envelope substitution"

let probe kind source release base risk completed publications=
 let call args=checked ~seconds:230. "/home/an/dev/ver/zigvm/_opam/bin/ocaml"((source^"/tools/release_process.ml")::args)in
 let file p=read_file(source^"/"^p)4194304 in
 let body path code needles=let c,b=request base path in require(c=code)("HTTP "^string_of_int c);List.iter(fun n->require(contains b n)("missing "^n))needles;b in
 match kind with
 |"authority"->ignore(active risk);"PASS","Canonical task and clock checked; fencing is cooperative",jnull
 |"clock"->let o=active risk|>assoc in "PASS","Physical uncertainty and logical sequence are distinct",field "clock_end"o
 |"package"->"PASS","Complete inventory and bytes verified",jstr(verify_release release)
 |"source"->let rev=verify_release release in let d=checked "/home/an/.cargo/bin/jj"["--repository";source;"diff";"--from";rev;"--to";"@";"--summary";"apps"]in require(String.trim d="")"application source drift";"PASS","Application source unchanged",jnull
 |"identity"->let b=fetch base "/api/v1/runtime/identity"in ignore(identity b(verify_release release));"PASS","Actual private identity",Yojson.Safe.from_string b
 |"production"->let code,b=request "http://nas-1.tail55d152.ts.net:4100" "/api/v1/runtime/identity"in let m=Yojson.Safe.from_string b|>assoc in
  if code<>200||not(bool(field "managed"m))||str(field "declared_candidate_revision"m)=""then"BLOCKED","Production candidate/recovery binding absent",jobj m else"OBSERVED","Identity only; admission not established",jobj m
 |"checker"->"PASS","Fresh native process and stage checker",jstr(call["selftest"])
 |"prefix"->let a=call["model-table"]in let b=checked ~seconds:45. "/home/an/.pixi/bin/pixi"["run";"--no-install";"--frozen";"--manifest-path";canonical^"/services/inference/max/pixi.toml";"mojo";source^"/tools/release_process.mojo";"model-table"]in require(a=b)"prefix parity";"PASS","Independent prefix agreement",jstr(digest a)
 |"unit"->"PASS","Fresh Gleam and three-language differential execution",jstr(call["unit";source])
 |"corruption"->"PASS","Private copy corruption rejected",jstr(call["package-faults";release])
 |"tui-real"|"tui-test"|"tui-unavailable" as k->
  let mode,scenario,needle=if k="tui-real"then"real","nominal","UNKNOWN"else if k="tui-test"then"test","disturbance","SIMULATED"else"test","unavailable","UNKNOWN"in
  let b=call["tui";release;mode;scenario;"1"]in require(contains b needle)"TUI provenance";"PASS","Native terminal evidence",jstr b
 |"browser"->let prefix="http://nas-1.tail55d152.ts.net:"in let p=String.sub base(String.length prefix)(String.length base-String.length prefix)in "PASS","Actual browser execution",jstr(call["browser";source;release;p])
 |"api-real"->let doc=Yojson.Safe.from_string(body "/api/v1/homeostasis?mode=real" 200 [])in validate_real_api doc;"PASS","Typed real API counters, unknown health and no authority",doc
 |"api-unavailable"->"PASS","Unavailable source503",Yojson.Safe.from_string(body "/api/v1/homeostasis?mode=test&scenario=unavailable" 503 ["UNKNOWN"])
 |"api-test"->let a=body "/api/v1/homeostasis?mode=test&scenario=nominal" 200 ["SIMULATED"]in let b=body "/api/v1/homeostasis?mode=test&scenario=disturbance" 200 ["SIMULATED"]in require(a<>b)"frozen fixtures";"PASS","Distinct explicit simulations",jnull
 |"stream"|"navigation" as k->let prev=List.assoc "C14"completed|>assoc in require(str(field "status"prev)="PASS")"browser prerequisite";
  "PASS",(if k="stream"then"Reused fresh C14 stale/reorder/disconnect evidence"else"Reused fresh C14 eight-route rendered/navigation evidence"),jstr"C14"
 |"board"->"OBSERVED","Actual registry; no peer ACK inferred",coord["status"]
 |"mirror"->require(List.for_all(fun x->bool(field "zenoh_readback"(assoc x)))publications)"prior mirrors incomplete";"PASS","Own prior publications read back",jint(List.length publications)
 |"wiki"->ignore(body "/wiki" 200 ["wiki"]);require(Sys.file_exists(source^"/engines/hermes/modules/hermes_wiki"))"wiki engine missing";"OBSERVED","Wiki route and engine source; knowledge correctness unverified",jnull
 |"zk"->ignore(body "/zk" 200 ["Z"]);let p=checked "/usr/bin/rg"["--files";source^"/docs/zk"]in "OBSERVED","ZK route and source inventory",jstr(digest p)
 |"km"->let p="docs/sop/20260908-0551-web-release-sdlc-sre-runbook.md"in let code,b=request "http://nas-1.tail55d152.ts.net:4100"("/raw/.uos-workspaces/"^Filename.basename source^"/"^p)in require(code=200&&b=file p)"served artifact drift";"PASS","Raw SOP equals source bytes",jstr(digest b)
 |"atlas"->"BLOCKED","Atlas declarations lack fresh invocation-specific proof",jstr(digest(file "apps/cepaf_gleam/src/cepaf_gleam/fpp/algebraic_atlas.gleam"))
 |"forecast"->"BLOCKED","Demonstration health cannot establish live calibration",jstr(digest(file "apps/cepaf_gleam/src/cepaf_gleam/ha/fractal_forecast.gleam"))
 |"rete"->"OBSERVED","Rule source present; runtime release integration unverified",jstr(digest(file "apps/cepaf_gleam/src/cepaf_gleam/knowledge/rete_ul_verifier.gleam"))
 |"formal"->"BLOCKED","No fresh full-system FPP/Lean/Quint/Gospel invocation receipt",jnull
 |"coverage"->"BLOCKED","17 aspects inventoried; unknown obligations prevent admission",plan_json()
 |"closure"->require(List.length completed=29&&List.length publications=29)"predecessor count";require(List.for_all(fun x->bool(field "zenoh_readback"(assoc x)))publications)"mirror gaps";"OBSERVED","Scoped30 decisions; residuals stay nonpassing",jnull
 |_->failwith "unknown focus"
let run_cycles source release p out risk=
 require(port p>=49152)"private staging required";require(not(Filename.is_relative out)&&not(Sys.file_exists out))"new output directory required";
 let subject=verify_release release and base="http://nas-1.tail55d152.ts.net:"^p in ignore(active risk);mkdir out 0o700;
 let revision=String.trim(checked "/home/an/.cargo/bin/jj"["--repository";source;"log";"-r";"@";"--no-graph";"-T";"commit_id"])in
 let code_hash=sha(source^"/tools/unification_cycles.ml")and core_hash=sha(source^"/tools/release_process.ml")in
 require(hex 40 revision)"invalid checker revision";
 write_new(out^"/plan.json")(json(plan_json()));
 let start=mono()and previous=ref(String.make 64 '0')and completed=ref[]and publications=ref[]and failures=ref[]and todo=ref catalog in
 for cycle=1 to 30 do
  require(mono()-.start<540.)"overall cycle budget";
  require(sha(source^"/tools/unification_cycles.ml")=code_hash&&sha(source^"/tools/release_process.ml")=core_hash)"checker drift";
  ignore(active risk);
  let inbound=listen()in
  let inbound_path=Printf.sprintf "%s/inbound-%02d.json"out cycle in write_new inbound_path(json inbound^"\n");
  let x=choose(List.map fst !completed)!failures !todo in let factors=adjusted !failures x in let before=mono()in
  let status,note,detail=try probe x.kind source release base risk !completed !publications with e->"FAIL",Printexc.to_string e,jnull in
  let record=jobj["schema",jstr"uos.unification-cycle.v1";"cycle",jint cycle;"focus",jstr x.id;"plan",jstr plan_id;"task",jstr"RUN30";"attempt",jint 1;"owner",jstr worker;
   "checker_revision",jstr revision;"checker_sha256",jstr code_hash;"core_sha256",jstr core_hash;"subject_candidate",jstr subject;"inbound_sha256",jstr(sha inbound_path);
   "domain",jstr x.domain;"fractal_layer",jint x.layer;"aspects",jarr(List.map jint x.aspects);"factors",jarr(List.map jint factors);"priority",jint(score factors);
   "selection",jstr"Hard authority gate, completed observation dependencies, highest revised ordinal risk; failures raise domain impact by1 capped at5";
   "goal",jstr x.purpose;"status",jstr status;"note",jstr note;"detail",detail;"wall_clock_utc_us",jstr(Int64.to_string(Int64.of_float(gettimeofday()*.1e6)));
   "monotonic_elapsed_seconds",jfloat(mono()-.before);"local_logical_step",jint cycle;"previous_sha256",jstr !previous;"authority",jstr"NONE";"system_admitted",jbool false]in
  let bytes=json record in let hash=digest bytes in let path=Printf.sprintf "%s/cycle-%02d.json"out cycle in write_new path(bytes^"\n");
  let op=Printf.sprintf "evo-0701-cycle-%02d"cycle in
  ignore(coord["heartbeat";session;revision;"plan:"^plan_id;op^"-heartbeat"]);ignore(coord["check";session;"runtime:indrajaal-web-staging";"4"]);
  let message=Printf.sprintf "Cycle%02d %s L%d %s: %s. %s. Evidence sha256=%s; no admission."cycle x.id x.layer x.domain status x.purpose hash in
  let ack=coord["send";session;"broadcast";(if status="FAIL"||status="BLOCKED"then"Andon"else"Progress");message;"plan:"^plan_id^",candidate:"^subject;op]in
  let key=Printf.sprintf "uos/tui/state/evolution/%s/cycle/%02d"session cycle in
  let mirrored,error=try mirror key (transport_envelope record)(out^"/"^op^"-put.json");true,""with e->false,Printexc.to_string e in
  let publication=jobj["cycle",jint cycle;"evidence_sha256",jstr hash;"board_ack",ack;"zenoh_key",jstr key;"zenoh_readback",jbool mirrored;"error",jstr error]in
  write_new(Printf.sprintf "%s/publication-%02d.json"out cycle)(json publication^"\n");
  completed:=(x.id,record)::!completed;publications:=!publications@[publication];previous:=hash;
  if status="FAIL"||status="BLOCKED"then failures:=x.domain::!failures;
  todo:=List.filter(fun y->y.id<>x.id)!todo;
  emit "unification-cycle" status["cycle",jint cycle;"focus",jstr x.id;"domain",jstr x.domain;"priority",jint(score factors);"zenoh_readback",jbool mirrored;"evidence",jstr path]
 done;
 let nonpassing=List.filter(fun(_,r)->str(field "status"(assoc r))<>"PASS")!completed in
 let result=jobj["schema",jstr"uos.unification-run.v1";"decisions",jint 30;"system_admitted",jbool false;"checker_revision",jstr revision;"subject_candidate",jstr subject;
 "hash_chain_tip",jstr !previous;"nonpassing",jarr(List.map(fun(id,r)->jobj["focus",jstr id;"status",field "status"(assoc r)])nonpassing);
 "publications",jarr !publications;"elapsed_monotonic_seconds",jfloat(mono()-.start)]in
 write_new(out^"/summary.json")(Yojson.Safe.pretty_to_string result^"\n");
 emit "unification-run" "RECORDED"["decisions",jint 30;"nonpassing",jint(List.length nonpassing);"evidence",jstr out;"system_admitted",jbool false]
let verify_cycles ?(require_mirrors=true) out=
 let summary=read_file(out^"/summary.json")4194304|>Yojson.Safe.from_string|>assoc in
 require(int(field "decisions"summary)=30 && not(bool(field "system_admitted"summary)))"summary admission/count";
 let previous=ref(String.make 64 '0')and done_ids=ref []and failures=ref []and pending=ref catalog and sequence=ref 0 and nonpassing=ref 0 and mirror_gaps=ref 0 and nonpassing_records=ref [] in
 for cycle=1 to 30 do
  let raw=read_file(Printf.sprintf "%s/cycle-%02d.json"out cycle)4194304 in
  require(String.ends_with ~suffix:"\n" raw)"receipt delimiter";
  let body=String.sub raw 0(String.length raw-1)in
  let r=Yojson.Safe.from_string body|>assoc in let hash=digest body in
  let chosen=choose !done_ids !failures !pending in let status=str(field "status"r)in
  require(List.mem status["PASS";"FAIL";"BLOCKED";"OBSERVED"])"invalid status";
  require(int(field "cycle"r)=cycle&&int(field "local_logical_step"r)=cycle)"cycle ordering";
  require(str(field "focus"r)=chosen.id && str(field "domain"r)=chosen.domain && int(field "fractal_layer"r)=chosen.layer)"selection identity";
  require(field "aspects"r=jarr(List.map jint chosen.aspects))"aspect substitution";
  let factors=adjusted !failures chosen in
  require(field "factors"r=jarr(List.map jint factors)&&int(field "priority"r)=score factors)"priority substitution";
  require(str(field "previous_sha256"r)= !previous)"hash chain";
  require(str(field "authority"r)="NONE"&&not(bool(field "system_admitted"r)))"receipt admission";
  List.iter(fun k->require(field k r=field k summary)("summary identity "^k))["checker_revision";"subject_candidate"];
  require(str(field "inbound_sha256"r)=sha(Printf.sprintf "%s/inbound-%02d.json"out cycle))"inbound substitution";
  let p=read_file(Printf.sprintf "%s/publication-%02d.json"out cycle)4194304|>Yojson.Safe.from_string|>assoc in
  require(int(field "cycle"p)=cycle&&str(field "evidence_sha256"p)=hash)"publication binding";
  let ack=field "board_ack"p|>assoc in let n=int(field "sequence"ack)in
  require(bool(field "ok"ack)&&n> !sequence)"board receipt sequence";
  require(str(field "zenoh_key"p)=Printf.sprintf "uos/tui/state/evolution/%s/cycle/%02d"session cycle)"publisher namespace";
  if not(bool(field "zenoh_readback"p))then incr mirror_gaps;
  if require_mirrors then require(bool(field "zenoh_readback"p))"mirror unconfirmed";
  require(List.nth(Yojson.Safe.Util.to_list(field "publications"summary))(cycle-1)=jobj p)"summary publication substitution";
  sequence:=n;previous:=hash;done_ids:=chosen.id::!done_ids;pending:=List.filter(fun x->x.id<>chosen.id)!pending;
  if status<>"PASS"then(incr nonpassing;nonpassing_records:=jobj["focus",jstr chosen.id;"status",jstr status]::!nonpassing_records);
  if status="FAIL"||status="BLOCKED"then failures:=chosen.domain::!failures
 done;
 require(str(field "hash_chain_tip"summary)= !previous)"summary tip";
 require(List.length(Yojson.Safe.Util.to_list(field "nonpassing"summary))= !nonpassing)"nonpassing count";
 require(field "nonpassing"summary=jarr !nonpassing_records)"nonpassing status substitution";
 emit "unification-receipt-integrity" "PASS"["cycles",jint 30;"nonpassing",jint !nonpassing;"original_mirror_gaps",jint !mirror_gaps;"transport_status",jstr(if !mirror_gaps=0 then"PASS"else"HOLD")]

let repair_tests ()=
 let fixture=jobj["status",jstr"observed";"metrics",jnull;"verification",jstr"not_verified";"control_authority",jstr"none";"age_us",jint 0;"ttl_us",jint 5000000;
 "runtime",jobj["scheduler_count",jint 2;"process_count",jint 91;"memory_total_mib",jint 35;"run_queue_length",jint 0;"uptime_seconds",jint 1];
 "fields",jarr(List.map(fun(id,v)->jobj["id",jstr id;"value",jstr v])["health","UNKNOWN";"schedulers","2";"processes","91";"vm_memory","35";"run_queue","0";"uptime","1"])]in
 let n=ref 0 in let check f=f();incr n and reject f=require(try f();false with _->true)"negative repair escaped";incr n in
 let replace k v d=jobj((k,v)::List.remove_assoc k(assoc d))in
 check(fun()->validate_real_api fixture);
 List.iter(fun(k,v)->reject(fun()->validate_real_api(replace k v fixture)))["status",jstr"OBSERVED";"metrics",jobj["health",jint 1];"control_authority",jstr"execute";"age_us",jint 5000001;"ttl_us",jint 0];
 reject(fun()->validate_real_api(replace "runtime"(replace "process_count"(jint(-1))(field "runtime"(assoc fixture)))fixture));
 reject(fun()->validate_real_api(replace "fields"(jarr[])fixture));
 let original=jobj["duration",jfloat 0.00014119599999773413;"text",jstr"α\nquoted \"text\""]in let encoded=transport_envelope original in
 check(fun()->validate_envelope original(Yojson.Safe.from_string(json encoded)));
 reject(fun()->validate_envelope original(replace "payload_json"(jstr"{}")encoded));
 reject(fun()->validate_envelope original(replace "payload_sha256"(jstr(String.make 64 '0'))encoded));
 reject(fun()->validate_envelope original(replace "authority"(jstr"execute")encoded));
 reject(fun()->validate_envelope original(jobj(("schema",jstr"duplicate")::assoc encoded)));
 emit "unification-repair-tests" "PASS"["checks",jint !n]
let reconcile out dest risk=
 verify_cycles ~require_mirrors:false out;
 require(not(Filename.is_relative dest)&&not(Sys.file_exists dest))"new reconciliation output required";ignore(active risk);mkdir dest 0o700;
 let revision=String.trim(checked "/home/an/.cargo/bin/jj"["log";"-r";"@";"--no-graph";"-T";"commit_id"])in require(hex 40 revision)"repair revision";
 let receipts=List.init 30(fun i->
  let cycle=i+1 in ignore(active risk);
  let raw=read_file(Printf.sprintf "%s/cycle-%02d.json"out cycle)4194304 in let doc=Yojson.Safe.from_string raw in
  let envelope=transport_envelope doc in let key=Printf.sprintf "uos/tui/state/evolution/%s/receipts/%02d"session cycle in let op=Printf.sprintf "evo-lossless-0701-%02d"cycle in
  ignore(coord["heartbeat";session;revision;"plan:"^plan_id;op^"-heartbeat"]);ignore(coord["check";session;"runtime:indrajaal-web-staging";"4"]);
  mirror key envelope(Printf.sprintf "%s/envelope-%02d.json"dest cycle);
  let sample=fetch zenoh("/"^key)|>Yojson.Safe.from_string|>Yojson.Safe.Util.to_list|>List.find(fun v->str(field "key"(assoc v))=key)in
  validate_envelope doc(field "value"(assoc sample));
  let ack=coord["send";session;"broadcast";"Progress";Printf.sprintf "Lossless mirror repair for recorded cycle%02d: original receipt preserved; byte/hash envelope read back exactly. Original cycle status is unchanged; no new cycle or admission."cycle;"plan:"^plan_id;op]in
  let r=jobj["cycle",jint cycle;"original_sha256",field "payload_sha256"(assoc envelope);"zenoh_key",jstr key;"readback",jbool true;"board_ack",ack]in
  write_new(Printf.sprintf "%s/reconciliation-%02d.json"dest cycle)(json r^"\n");r)in
 let result=jobj["schema",jstr"uos.unification-reconciliation.v1";"original_summary_sha256",jstr(sha(out^"/summary.json"));"repair_revision",jstr revision;"authority",jstr"NONE";"records",jarr receipts]in
 write_new(dest^"/summary.json")(json result^"\n");
 emit "unification-lossless-reconciliation" "PASS"["receipts",jint 30;"evidence",jstr dest]

let verify_reconciliation out dest=
 verify_cycles ~require_mirrors:false out;
 let summary=read_file(dest^"/summary.json")4194304|>Yojson.Safe.from_string|>assoc in
 require(str(field "schema"summary)="uos.unification-reconciliation.v1"&&str(field "authority"summary)="NONE")"reconciliation schema";
 require(str(field "original_summary_sha256"summary)=sha(out^"/summary.json"))"reconciliation source binding";
 let all=field "records"summary|>Yojson.Safe.Util.to_list in require(List.length all=30)"reconciliation count";
 let sequence=ref 0 in
 for cycle=1 to 30 do
  let original=read_file(Printf.sprintf "%s/cycle-%02d.json"out cycle)4194304|>Yojson.Safe.from_string in
  let local=read_file(Printf.sprintf "%s/envelope-%02d.json"dest cycle)4194304|>Yojson.Safe.from_string in validate_envelope original local;
  let r=read_file(Printf.sprintf "%s/reconciliation-%02d.json"dest cycle)4194304|>Yojson.Safe.from_string in require(List.nth all(cycle-1)=r)"reconciliation receipt substitution";
  let r=assoc r in require(int(field "cycle"r)=cycle&&bool(field "readback"r))"reconciliation identity";
  require(str(field "original_sha256"r)=digest(json original))"reconciliation digest";
  let key=Printf.sprintf "uos/tui/state/evolution/%s/receipts/%02d"session cycle in require(str(field "zenoh_key"r)=key)"reconciliation namespace";
  let ack=field "board_ack"r|>assoc in let n=int(field "sequence"ack)in require(bool(field "ok"ack)&&n> !sequence)"reconciliation board receipt";sequence:=n;
  let sample=fetch zenoh("/"^key)|>Yojson.Safe.from_string|>Yojson.Safe.Util.to_list|>List.find(fun v->str(field "key"(assoc v))=key)in
  validate_envelope original(field "value"(assoc sample))
 done;
 emit "unification-reconciliation-verification" "PASS"["receipts",jint 30;"fresh_live_readbacks",jint 30;"system_admitted",jbool false]

let receipt_faults out=
 verify_cycles ~require_mirrors:false out;
 let scratch=temp "uos-unification-receipt-faults-"in let target=scratch^"/private-copy"in copy out target;
 let n=ref 0 in
 let check relative change=
  let path=target^"/"^relative in let original=read_file path 4194304 in
  unlink path;write_new path(change original);
  let rejected=try verify_cycles ~require_mirrors:false target;false with _->true in
  unlink path;write_new path original;require rejected("receipt fault escaped "^relative);incr n in
 let replace k v raw=let a=Yojson.Safe.from_string raw|>assoc in json(jobj((k,v)::List.remove_assoc k a))^"\n"in
 check "summary.json"(replace "system_admitted"(jbool true));
 check "summary.json"(replace "hash_chain_tip"(jstr(String.make 64 '0')));
 check "summary.json"(replace "nonpassing"(jarr(List.init 12(fun _->jobj["focus",jstr"C01";"status",jstr"PASS"]))));
 check "cycle-01.json"(replace "previous_sha256"(jstr(String.make 64 '1')));
 check "cycle-01.json"(replace "priority"(jint 1));
 check "cycle-01.json"(fun raw->String.sub raw 0(String.length raw-1));
 check "inbound-01.json"(fun _->"{}\n");
 check "publication-01.json"(replace "evidence_sha256"(jstr(String.make 64 '1')));
 verify_cycles ~require_mirrors:false target;
 emit "unification-receipt-faults" "PASS"["rejections",jint !n;"private_copy",jstr target;"original_summary_sha256",jstr(sha(out^"/summary.json"))]

let retain out reconciled dest=
 verify_cycles ~require_mirrors:false out;
 require(not(Filename.is_relative dest)&&not(Sys.file_exists dest))"new evidence destination required";
 let bounded dir=let xs=files dir ""in require(List.for_all(fun p->String.ends_with ~suffix:".json"p)xs)"unexpected evidence file";
  require(List.fold_left(fun total p->total+(stat(dir^"/"^p)).st_size)0 xs<=16777216)"evidence byte budget"in
 bounded out;bounded reconciled;mkdir dest 0o700;copy out(dest^"/run");copy reconciled(dest^"/lossless");
 List.iter(fun(src,name)->write_new(dest^"/"^name)(read_file src 4194304))
 ["/tmp/uos-native-unit-e6458b/unit.log","20260908-0753-unit.txt";
  "/tmp/uos-native-unit-e6458b/differential.txt","20260908-0753-transitions.txt";
  "/tmp/uos-release-browser-fff572/browser.log","20260908-0753-browser.txt"];
 let entries=inventory dest in
 write_new(dest^"/20260908-0753-inventory.json")(json(jobj(List.map(fun(p,h)->p,jstr h)entries)));
 emit "unification-evidence-retention" "PASS"["files",jint(List.length entries);"destination",jstr dest]

let ()=
 Sys.set_signal Sys.sigalrm(Sys.Signal_handle(fun _->failwith "overall audit deadline"));ignore(alarm 600);
 try(match Array.to_list Sys.argv with
 |[_;"plan"]->print_endline(json(plan_json()))
 |[_;"selection-table"]->print_string(selection_table())
 |[_;"selftest"]->selfcheck()
 |[_;"listen"]->print_endline(json(listen()))
 |[_;"verify-run";out]->verify_cycles out
 |[_;"verify-integrity";out]->verify_cycles ~require_mirrors:false out
 |[_;"repair-tests"]->repair_tests()
 |[_;"probe-real";base]->let code,b=request base "/api/v1/homeostasis?mode=real"in require(code=200)"real API transport";validate_real_api(Yojson.Safe.from_string b);emit "typed-real-api" "PASS"[]
 |[_;"reconcile-run";out;dest;risk]->reconcile out dest risk
 |[_;"verify-reconciliation";out;dest]->verify_reconciliation out dest
 |[_;"receipt-faults";out]->receipt_faults out
 |[_;"authority-check";risk]->print_endline(json(active risk))
 |_::"risk-check"::args when args<>[]->let binary=Lazy.force risk_binary in print_string(in_dir canonical(fun()->checked ~seconds:30. binary args))
 |[_;"retain";out;reconciled;dest]->retain out reconciled dest
 |[_;"run";source;release;p;out;risk]->run_cycles source release p out risk
 |_->failwith "usage: plan | selection-table | selftest | repair-tests | listen | probe-real TAILSCALE_BASE | authority-check RISK | verify-run OUT | verify-integrity OUT | receipt-faults OUT | reconcile-run OUT NEW_DEST RISK | verify-reconciliation OUT RECONCILED | retain OUT RECONCILED NEW_DEST | run SOURCE RELEASE PRIVATE_PORT NEW_OUTPUT RISK")
 with e->emit "unification-command" "FAIL"["error",jstr(Printexc.to_string e)];exit 1
