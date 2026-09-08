#use "unification_cycles.ml";;
(* Reusable fifty-focus audit. Sa-plan owns the task; no deployment or peer dispatch. *)
type config={source:string;release:string;base:string;out:string;risk:string;plan:string;task:string;worker_id:string;session_id:string;attempt:int;workspace_epoch:int;runtime_epoch:int};;
let read_config path=
 let a=read_file path 65536 |> Yojson.Safe.from_string |> assoc in
 keys ["source";"release";"private_port";"output";"risk";"plan";"task";"worker";"session";"attempt";"workspace_epoch";"runtime_epoch"]a;
 let s k=str(field k a)and n k=int(field k a)in
 let p=s "private_port"in require(port p>=49152)"private port required";
 List.iter(fun k->let v=s k in require(v<>""&&not(String.contains v '\n')&&not(String.contains v '"')&&not(String.contains v '\\'))("unsafe field "^k))
 ["source";"release";"output";"risk";"plan";"task";"worker";"session"];
 let source=realpath(s "source")in require(Sys.file_exists(source^"/.jj"))"isolated JJ source required";
 require(source<>canonical && String.starts_with ~prefix:(canonical^"/.uos-workspaces/")source)"sibling workspace required";
 List.iter(fun k->require(not(Filename.is_relative(s k)))"absolute artifact path required")["source";"release";"output";"risk"];
 require(n "attempt">0&&n "workspace_epoch">0&&n "runtime_epoch">0)"positive fences required";
 {source;release=s "release";base="http://nas-1.tail55d152.ts.net:"^p;out=s "output";risk=s "risk";plan=s "plan";task=s "task";worker_id=s "worker";session_id=s "session";attempt=n "attempt";workspace_epoch=n "workspace_epoch";runtime_epoch=n "runtime_epoch"};;
let cfocus i domain layer aspects factors deps kind purpose=f(Printf.sprintf "N%02d" i)domain layer aspects factors deps kind purpose;;
let focuses=
 let row i d l a v deps k p=cfocus i d l a v(List.map(fun n->Printf.sprintf "N%02d" n)deps)k p in
 [
 row 1 "control" 0 [17] [5;5;5;5;5] [] "authority" "Fresh task, clock and separate leases";
 row 2 "control" 2 [6;8;13] [5;5;5;4;4] [1] "guard" "Fresh typed JSON regression suite";
 row 3 "data" 2 [8;13] [5;5;5;4;4] [2] "guard-substring" "Reject value and longer-key substitutions";
 row 4 "data" 2 [8;13] [4;5;4;4;4] [2] "guard-syntax" "Reject malformed and concatenated documents";
 row 5 "data" 2 [8;13] [4;5;4;4;4] [2] "guard-nesting" "Nested keys and arrays confer no top-level field";
 row 6 "data" 2 [7;13] [4;4;4;4;4] [2] "guard-escaping" "Escaped and Unicode field identity";
 row 7 "data" 2 [7;13] [3;3;3;3;3] [2] "guard-values" "Null and false preserve presence semantics";
 row 8 "control" 2 [8;13] [4;5;4;4;4] [2] "guard-fallback" "Metadata escaping and verdict non-interference";
 row 9 "control" 2 [3;8] [4;4;4;4;4] [2] "guard-limit" "Oversize output fails before parsing";
 row 10 "structural" 4 [6;7] [4;5;4;4;4] [2] "guard-oracle" "Independent OCaml object-membership oracle";
 row 11 "structural" 4 [4;7;11;13] [4;4;4;4;4] [10] "unit" "Full scoped Gleam and FPP compatibility";
 row 12 "dynamic" 1 [4] [5;5;4;4;4] [1] "runtime-spoof" "Actual OTP27/29 ignores spoofed environment";
 row 13 "static" 2 [2;3;5] [4;4;4;5;4] [1] "package" "Exact candidate and complete byte inventory";
 row 14 "structural" 2 [2;3] [4;4;4;4;4] [13] "source" "Application source equals packaged revision";
 row 15 "control" 0 [6;7;17] [4;5;4;4;4] [1] "checker" "Bounded process and lifecycle checker suite";
 row 16 "structural" 4 [6;7] [4;4;4;4;3] [15] "prefix" "Independent338 transition comparison"
 ]@
 List.mapi(fun i(stage,_)->row(17+i)"control"(i mod 10)[6;7;17][4;4;4;4;3][15]("stage:"^stage)("Lifecycle "^stage^" receipt negatives; same fresh checker invocation"))stages @
 [
 row 29 "static" 2 [1;5;6] [4;4;4;4;4] [13] "corruption" "Corrupted private package copies reject";
 row 30 "dynamic" 3 [4] [5;5;4;5;4] [13] "identity" "Actual staged OTP/ERTS and process identity";
 row 31 "dynamic" 3 [4;17] [5;5;5;5;5] [1] "production" "Observe production binding without cutover";
 row 32 "data" 3 [4;13] [4;4;4;4;3] [30] "tui-real" "Observed terminal data and unknown physical health";
 row 33 "data" 3 [13] [3;3;3;3;3] [32] "tui-test" "Explicit terminal simulation";
 row 34 "data" 3 [13] [4;4;4;4;3] [32] "tui-unavailable" "Unavailable terminal data stays unknown";
 row 35 "control" 5 [11;12;13;14] [4;4;4;4;4] [11;30] "browser" "Actual eight-route browser interaction";
 row 36 "data" 5 [11;13] [4;4;4;4;3] [30] "api-real" "Typed real API provenance and fresh counters";
 row 37 "data" 5 [11;13] [4;4;4;4;3] [36] "api-unavailable" "Unavailable fixture returns503";
 row 38 "data" 5 [11;13] [3;3;3;3;3] [36] "api-test" "Fixture switch changes explicit simulation";
 row 39 "dynamic" 5 [11;13] [4;4;4;4;3] [35] "stream" "Reuse fresh browser stale/reorder/cleanup negatives";
 row 40 "static" 7 [12;13;14] [3;4;3;4;4] [35] "navigation" "Eight-route rendering and links from same browser run";
 row 41 "control" 6 [10;17] [4;4;4;4;4] [1] "board" "Actual board sessions and peer claims";
 row 42 "data" 6 [10] [4;4;4;4;4] [41] "mirror" "Exact owned receipt readbacks";
 row 43 "wiki" 7 [16] [3;3;3;3;4] [30] "wiki" "Wiki route and source; semantics remain scoped";
 row 44 "zk" 8 [16] [3;3;3;3;4] [30] "zk" "ZK route and source inventory";
 row 45 "km" 8 [14;16] [4;4;4;4;4] [43;44] "km" "Served runbook bytes; external source comparison recorded separately";
 row 46 "structural" 8 [6;7;8] [4;5;4;4;4] [14] "atlas" "Declaration-only atlas and formal evidence limits";
 row 47 "dynamic" 6 [8;9] [4;5;4;4;4] [14] "forecast" "Precommitted local forecasts versus measured outcomes";
 row 48 "control" 0 [6;8] [4;4;4;3;3] [14] "rete" "Rule source and control-authority separation";
 row 49 "control" 9 [3;9] [4;5;4;4;4] [1] "gateway" "Tailnet model selection versus actual inference";
 row 50 "km" 9 (List.init 17((+)1)) [5;5;4;5;5] (List.init 49((+)1)) "closure" "Fifty outcomes, all17 references and synchronization"
 ];;
let plans()=jarr(List.map(fun x->jobj["id",jstr x.id;"domain",jstr x.domain;"layer",jint x.layer;"aspects",jarr(List.map jint x.aspects);"factors",jarr(List.map jint x.factors);"dependencies",jarr(List.map jstr x.deps);"check",jstr x.kind;"purpose",jstr x.purpose])focuses);;
let active50 c=let binary=Lazy.force risk_binary in in_dir canonical(fun()->checked ~seconds:15. binary["--active-check";c.risk;c.task;c.worker_id;string_of_int c.attempt]|>first_json);;
let heartbeat c revision op=
 ignore(coord["heartbeat";c.session_id;revision;"plan:"^c.plan;op^"-hb"]);
 ignore(coord["check";c.session_id;"workspace:"^c.source;string_of_int c.workspace_epoch]);
 ignore(coord["check";c.session_id;"runtime:indrajaal-web-staging";string_of_int c.runtime_epoch]);;
let inbound50 c=
 let board=coord["inbox";c.session_id]|>assoc|>field "messages"|>Yojson.Safe.Util.to_list in
 let last=List.filteri(fun i _->i>=List.length board-10)board in
 let raw=fetch zenoh "/uos/tui/state/*"in
 let states=Yojson.Safe.from_string raw|>Yojson.Safe.Util.to_list|>List.map(fun i->let a=assoc i in jobj["key",field "key"a;"timestamp",field "timestamp"a;"value_sha256",jstr(digest(json(field "value"a)))])in
 jobj["board_last10",jarr last;"zenoh",jarr states;"zenoh_sha256",jstr(digest raw);"authority",jstr"NONE"];;
let lines_json text=String.split_on_char '\n' text |> List.filter_map(fun s->try Some(Yojson.Safe.from_string s)with _->None);;
let last_json text=lines_json text |> List.rev |> List.hd;;
let guard_reference body key=
 if String.length body<3||String.length body>1048576 then false else
 try match Yojson.Safe.from_string body with `Assoc xs->List.mem_assoc key xs|_->false with _->false;;
let outcome_probability passed scored=float_of_int(passed+1)/.float_of_int(scored+2);;
let brier p pass=(p-.(if pass then 1. else 0.))**2.;;
let selftest50()=
 let n=ref 0 in let chk name b=require b name;incr n in
 chk "fifty" (List.length focuses=50);
 chk "unique" (List.length(List.sort_uniq compare(List.map(fun x->x.id)focuses))=50);
 chk "ten layers"(List.length(List.sort_uniq compare(List.map(fun x->x.layer)focuses))=10);
 chk "eight domains"(List.length(List.sort_uniq compare(List.map(fun x->x.domain)focuses))=8);
 chk "seventeen"(List.sort_uniq compare(List.concat_map(fun x->x.aspects)focuses)=List.init 17((+)1));
 let rec walk ids xs=match xs with []->ids|_->let x=choose ids [] xs in walk(x.id::ids)(List.filter(fun y->y.id<>x.id)xs)in
 chk "DAG"(List.length(walk[] focuses)=50);
 chk "substring oracle"(not(guard_reference "{\"message\":\"status\"}" "status"));
 chk "nested oracle"(not(guard_reference "{\"x\":{\"status\":1}}" "status"));
 chk "null is present"(guard_reference "{\"status\":null}" "status");
 chk "trailing rejects"(not(guard_reference "{\"status\":1}garbage" "status"));
 chk "forecast prior"(outcome_probability 0 0=0.5);
 chk "forecast bound"(outcome_probability 50 50<1.);
 chk "proper score"(brier 1. true=0.&&brier 1. false=1.);
 let bad={(List.hd focuses) with deps=["absent"]}in
 chk "missing prerequisite"(try ignore(choose[][][bad]);false with _->true);
 emit "fifty-selftest" "PASS"["checks",jint !n];;
let run50 c=
 ignore(active50 c);require(not(Sys.file_exists c.out))"new output directory required";mkdir c.out 0o700;
 let subject=verify_release c.release in
 let revision=checked "/home/an/.cargo/bin/jj"["--repository";c.source;"log";"-r";"@";"--no-graph";"-T";"commit_id"]|>String.trim in
 let protected=["tools/evolution_cycles.ml";"tools/evolution_cycles.mojo";"tools/unification_cycles.ml";"tools/release_process.ml";"tools/release_process.mojo";"tools/output_guard_check.ml";"tools/validation/release_browser_capture.ml";"apps/cepaf_gleam/src/cepaf_gleam/ha/module_guard.gleam";"apps/cepaf_gleam/test/module_guard_contract_test.gleam"]in
 let hashes=List.map(fun p->p,sha(c.source^"/"^p))protected in
 let memo=Hashtbl.create 8 in
 let call tool args=checked ~seconds:230. "/home/an/dev/ver/zigvm/_opam/bin/ocaml"(["-I";c.source^"/tools";c.source^"/tools/"^tool]@args)in
 let cached key thunk=match Hashtbl.find_opt memo key with Some x->x|None->let x=thunk()in Hashtbl.add memo key x;x in
 let guard()=cached "guard"(fun()->let report=call "output_guard_check.ml"[c.source]|>last_json in
   let path=str(field "evidence"(assoc report))in
   let cases=read_file(path^"/cases.json")1048576 |> Yojson.Safe.from_string in
   jobj["report",report;"cases",cases;"log",jstr(read_file(path^"/unit.log")1048576)])in
 let checker()=cached "checker"(fun()->jstr(call "release_process.ml"["selftest"]))in
 let completed=ref[]and publications=ref[]and todo=ref focuses and failures=ref[]and previous=ref(String.make 64 '0')and successes=ref 0 and scored=ref 0 and total_score=ref 0. in
 write_new(c.out^"/plan.json")(json(plans()));
 let started=mono()in
 for cycle=1 to 50 do
  require(mono()-.started<900.)"cycle-run deadline";
  List.iter(fun(p,h)->require(sha(c.source^"/"^p)=h)"checker source drift")hashes;
  let op=Printf.sprintf "%s-cycle-%02d" c.session_id cycle in
  heartbeat c revision op;let auth=active50 c in
  let incoming=inbound50 c in let ip=Printf.sprintf "%s/inbound-%02d.json"c.out cycle in write_new ip(json incoming);
  let focus=choose(List.map fst !completed)!failures !todo in
  let p=outcome_probability !successes !scored in
  let forecast=jobj["schema",jstr"uos.local-forecast.v1";"focus",jstr focus.id;"event",jstr"check_returns_PASS";"horizon",jstr"this bounded focus";"probability",jfloat p;"method",jstr"Laplace-smoothed prior outcomes; dependent checks, not calibrated system confidence";"issued_utc_us",jstr(Int64.to_string(Int64.of_float(gettimeofday()*.1e6))); "authority",jstr"NONE"]in
  let fp=Printf.sprintf "%s/forecast-%02d.json"c.out cycle in write_new fp(json forecast);
  let before=mono()in
  let status,note,detail=try
   match focus.kind with
   |"authority"->"PASS","Current task and separate cooperative fences",auth
   |"guard"->"PASS","Fresh6 test functions plus20 payload cases",guard()
   |"guard-substring"|"guard-syntax"|"guard-nesting"|"guard-escaping"|"guard-values"|"guard-oracle" as kind->
     let g=guard()|>assoc in let rows=field "cases"g|>Yojson.Safe.Util.to_list in
     let wanted=match kind with
      |"guard-substring"->["value_substring";"longer_key"]|"guard-syntax"->["malformed";"trailing_text";"two_documents"]
      |"guard-nesting"->["nested_key";"array_root"]|"guard-escaping"->["escaped_key";"unicode_key";"quoted_key";"nul_name"]
      |"guard-values"->["null_value";"false_value"]|_->List.map(fun j->str(field "id"(assoc j)))rows in
     let selected=List.filter(fun j->List.mem(str(field "id"(assoc j)))wanted)rows in require(List.length selected=List.length wanted)"missing case";
     List.iter(fun j->let a=assoc j in let actual=bool(field "actual"a)in
       require(actual=bool(field "expected"a)&&actual=guard_reference(str(field "body"a))(str(field "field"a)))"independent guard disagreement")selected;
     "PASS","Selected cases reused from fresh N02; independent OCaml syntax/object oracle",jarr selected
   |"guard-fallback"|"guard-limit" as k->let g=guard()|>assoc in let log=str(field "log"g)in
     let test=if k="guard-limit"then"large_payload_rejected_test"else"metadata_cannot_change_json_verdict_test"in
     require(contains log(test^"...ok"))"guard subtest absent";
     "PASS","Fresh N02 subtest receipt reused explicitly",field "report"g
   |"runtime-spoof"->"PASS","Actual OTP observation ignores spoofed environment",jstr(call "release_process.ml"["runtime-check";c.source])
   |"checker"->"PASS","Fresh113 bounded checker tests",checker()
   |k when String.starts_with ~prefix:"stage:"k->
     let stage=String.sub k 6(String.length k-6)in
     let rs=str(checker())|>lines_json|>List.filter(fun j->try String.starts_with ~prefix:("stage_"^stage^"_")(str(field "stage"(assoc j)))with _->false)in
     require(List.length rs>=7&&List.for_all(fun j->str(field "status"(assoc j))="PASS")rs)"stage check missing";
     "PASS","Contract validation negatives from same fresh N15 invocation; actual stage completion separate",jarr rs
   |"stream"|"navigation" as k->
     let original=List.assoc "N35" !completed|>assoc in require(str(field "status"original)="PASS")"browser prerequisite failed";
     "PASS","Same fresh N35 browser execution; no second suite counted",jstr(if k="stream"then"stale/reordered/malformed/disconnect"else"eight rendered routes")
   |"board"->"OBSERVED","Bounded actual board snapshot; peer prose is not verification",incoming
   |"mirror"->require(List.for_all(fun j->bool(field "zenoh_readback"(assoc j)))!publications)"publication missing";"PASS","All prior owned cycle envelopes read back",jint(List.length !publications)
   |"forecast"->"OBSERVED","Precommitted local forecast log and proper scores; no live system calibration",jobj["scored",jint !scored;"sum_brier",jfloat !total_score]
   |"gateway"->let _,route=request "http://nas-1.tail55d152.ts.net:4100" "/api/v1/intelligence/route"in
     let _,state=request "http://nas-1.tail55d152.ts.net:4100" "/api/v1/inference/status"in
     "BLOCKED","Selection/status endpoints do not establish executable Gemma inference",jobj["route",Yojson.Safe.from_string route;"status",Yojson.Safe.from_string state]
   |"closure"->require(List.length !completed=49&&List.length !publications=49)"closure predecessor count";"OBSERVED","All50 focus references; production/formal/whole-system gates remain separate",plans()
   |kind->probe kind c.source c.release c.base c.risk !completed !publications
  with e->"FAIL",Printexc.to_string e,jnull in
  let score_value=if status="PASS"||status="FAIL"then(incr scored;if status="PASS"then incr successes;let s=brier p(status="PASS")in total_score:= !total_score+.s;jfloat s)else jnull in
  let record=jobj["schema",jstr"uos.evolution-cycle.v2";"cycle",jint cycle;"focus",jstr focus.id;"goal",jstr focus.purpose;"plan",jstr c.plan;"task",jstr c.task;"attempt",jint c.attempt;"owner",jstr c.worker_id;"session",jstr c.session_id;
   "source_candidate",jstr subject;"checker_revision",jstr revision;"checker_hashes",jobj(List.map(fun(p,h)->p,jstr h)hashes);"domain",jstr focus.domain;"layer",jint focus.layer;"aspects",jarr(List.map jint focus.aspects);
   "factors",jarr(List.map jint(adjusted !failures focus));"priority",jint(score(adjusted !failures focus));"dependencies",jarr(List.map jstr focus.deps);
   "status",jstr status;"note",jstr note;"detail",detail;"utc_us",jstr(Int64.to_string(Int64.of_float(gettimeofday()*.1e6)));"elapsed_seconds",jfloat(mono()-.before);"logical_step",jint cycle;
   "inbound_sha256",jstr(sha ip);"forecast_sha256",jstr(sha fp);"brier",score_value;"previous_sha256",jstr !previous;"authority",jstr"NONE";"system_admitted",jbool false]in
  let rp=Printf.sprintf "%s/cycle-%02d.json"c.out cycle in write_new rp(json record);let hash=sha rp in
  heartbeat c revision(op^"-publish");ignore(active50 c);
  let message=Printf.sprintf "Cycle %02d/50 %s L%d %s: %s. %s. Evidence %s. No admission."cycle focus.id focus.layer focus.domain status focus.purpose hash in
  let board=coord["send";c.session_id;"broadcast";"Report";message;"plan:"^c.plan;op]in
  let key=Printf.sprintf "uos/tui/state/evolution/%s/cycle/%02d"c.session_id cycle in
  let envelope=transport_envelope record in
  let before_put=fetch zenoh("/"^key)|>Yojson.Safe.from_string|>Yojson.Safe.Util.to_list in
  require(before_put=[])"new owned key must be absent";
  mirror key envelope (Printf.sprintf "%s/envelope-%02d.json"c.out cycle);
  let pub=jobj["cycle",jint cycle;"key",jstr key;"board",board;"zenoh_readback",jbool true;"payload_sha256",jstr hash;"authority",jstr"NONE"]in
  write_new(Printf.sprintf "%s/publication-%02d.json"c.out cycle)(json pub);
  publications:= !publications@[pub];completed:= !completed@[focus.id,record];todo:=List.filter(fun x->x.id<>focus.id)!todo;previous:=hash;
  if status="FAIL"||status="BLOCKED"then failures:=List.sort_uniq compare(focus.domain::!failures);
  emit "evolution-cycle" status ["cycle",jint cycle;"focus",jstr focus.id;"sha256",jstr hash]
 done;
 let count status=List.filter(fun(_,r)->str(field "status"(assoc r))=status)!completed|>List.length in
 let summary=jobj["schema",jstr"uos.evolution-summary.v2";"cycles",jint 50;"plan",jstr c.plan;"source_candidate",jstr subject;"checker_revision",jstr revision;"pass",jint(count"PASS");"fail",jint(count"FAIL");"blocked",jint(count"BLOCKED");"observed",jint(count"OBSERVED");"scored_forecasts",jint !scored;"sum_brier",jfloat !total_score;"last_sha256",jstr !previous;"authority",jstr"NONE";"system_admitted",jbool false]in
 write_new(c.out^"/summary.json")(json summary);print_endline(json summary);;
let verify50 ?(quiet=false) out=
 require(read_file(out^"/plan.json")1048576 |> Yojson.Safe.from_string = plans())"plan substitution";
 let previous=ref(String.make 64 '0')and ids=ref[]and failures=ref[]and pending=ref focuses in
 let counts=Hashtbl.create 4 and passed=ref 0 and scored=ref 0 and briers=ref 0. and identity=ref None in
 for n=1 to 50 do
  let p=Printf.sprintf "%s/cycle-%02d.json"out n in let r=read_file p 4194304 |> Yojson.Safe.from_string |> assoc in
  let selected=choose !ids !failures !pending in
  require(int(field "cycle"r)=n&&str(field "focus"r)=selected.id&&str(field "previous_sha256"r)= !previous)"chain/order mismatch";
  require(int(field "priority"r)=score(adjusted !failures selected))"priority forged";
  require(field "factors"r=jarr(List.map jint(adjusted !failures selected))&&field "dependencies"r=jarr(List.map jstr selected.deps))"selection metadata forged";
  require(str(field "schema"r)="uos.evolution-cycle.v2"&&int(field "logical_step"r)=n)"schema/logical clock mismatch";
  require(str(field "domain"r)=selected.domain&&int(field "layer"r)=selected.layer&&field "aspects"r=jarr(List.map jint selected.aspects))"scope metadata forged";
  let binding=List.map(fun k->field k r)["plan";"task";"attempt";"owner";"session";"source_candidate";"checker_revision";"checker_hashes"]in
  (match !identity with None->identity:=Some binding|Some old->require(old=binding)"identity drift");
  require(str(field "authority"r)="NONE"&&not(bool(field "system_admitted"r)))"authority forged";
  List.iter(fun(prefix,key)->require(sha(Printf.sprintf "%s/%s-%02d.json"out prefix n)=str(field key r))"linked artifact substitution")["forecast","forecast_sha256";"inbound","inbound_sha256"];
  let forecast=read_file(Printf.sprintf "%s/forecast-%02d.json"out n)65536|>Yojson.Safe.from_string|>assoc in
  let probability=outcome_probability !passed !scored in
  require(str(field "schema"forecast)="uos.local-forecast.v1"&&str(field "focus"forecast)=selected.id&&str(field "event"forecast)="check_returns_PASS"&&str(field "authority"forecast)="NONE")"forecast metadata";
  require(Yojson.Safe.Util.to_float(field "probability"forecast)=probability)"forecast altered";
  require(Int64.compare(Int64.of_string(str(field "issued_utc_us"forecast)))(Int64.of_string(str(field "utc_us"r)))<=0)"forecast issued after outcome";
  let status=str(field "status"r)in require(List.mem status ["PASS";"FAIL";"BLOCKED";"OBSERVED"])"invalid outcome";
  Hashtbl.replace counts status(1+Option.value~default:0(Hashtbl.find_opt counts status));
  if status="PASS"||status="FAIL"then(let b=brier probability(status="PASS")in
    require(abs_float(Yojson.Safe.Util.to_float(field "brier"r)-.b)<1e-12)"Brier altered";
    incr scored;if status="PASS"then incr passed;briers:= !briers+.b)
  else require(field "brier"r=jnull)"unscored outcome falsely calibrated";
  let pub=read_file(Printf.sprintf "%s/publication-%02d.json"out n)1048576 |> Yojson.Safe.from_string |> assoc in
  require(int(field "cycle"pub)=n&&str(field "authority"pub)="NONE"&&bool(field "zenoh_readback"pub)&&str(field "payload_sha256"pub)=sha p)"publication mismatch";
  require(str(field "key"pub)=Printf.sprintf "uos/tui/state/evolution/%s/cycle/%02d"(str(field "session"r))n)"publication namespace mismatch";
  let env=read_file(Printf.sprintf "%s/envelope-%02d.json"out n)4194304 |> Yojson.Safe.from_string in validate_envelope(jobj r)env;
  previous:=sha p;ids:=selected.id::!ids;pending:=List.filter(fun f->f.id<>selected.id)!pending;
  let s=str(field "status"r)in if s="FAIL"||s="BLOCKED"then failures:=List.sort_uniq compare(selected.domain::!failures)
 done;
 let summary=read_file(out^"/summary.json")65536 |> Yojson.Safe.from_string |> assoc in
 require(int(field "cycles"summary)=50&&str(field "last_sha256"summary)= !previous)"summary mismatch";
 List.iter(fun(k,s)->require(int(field k summary)=Option.value~default:0(Hashtbl.find_opt counts s))"summary count altered")["pass","PASS";"fail","FAIL";"blocked","BLOCKED";"observed","OBSERVED"];
 require(int(field "scored_forecasts"summary)= !scored&&abs_float(Yojson.Safe.Util.to_float(field "sum_brier"summary)-. !briers)<1e-12)"forecast summary altered";
 require(str(field "schema"summary)="uos.evolution-summary.v2"&&str(field "authority"summary)="NONE"&&not(bool(field "system_admitted"summary)))"summary authority altered";
 if not quiet then emit "fifty-integrity" "PASS"["cycles",jint 50];;
let ()=if Filename.basename Sys.argv.(0)="evolution_cycles.ml"then(
 Sys.set_signal Sys.sigalrm(Sys.Signal_handle(fun _->failwith"overall deadline"));ignore(alarm 1200);
 try match Array.to_list Sys.argv with
 |[_;"plan"]->print_endline(json(plans()))
 |[_;"selftest"]->selftest50()
 |[_;"selection-table"]->print_string(selection_table())
 |[_;"run";config]->run50(read_config config)
 |[_;"verify";out]->verify50 out
 |_->failwith"usage: plan | selftest | selection-table | run CONFIG | verify OUTPUT"
 with e->emit "fifty-command" "FAIL"["error",jstr(Printexc.to_string e)];exit 1);;
