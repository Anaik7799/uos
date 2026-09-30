#use "topfind";;
#require "yojson,cryptokit,unix";;

(* Independent finite static-rule oracle. This validates a local evidence carrier,
   not its producer, candidate identity, freshness, dispatch authority or EV status. *)
exception Refused of string
let require b why=if not b then raise(Refused why)
let sha bytes=Cryptokit.transform_string(Cryptokit.Hexa.encode())(Cryptokit.hash_string(Cryptokit.Hash.sha256())bytes)
let edges=[|(0,1);(0,2);(0,3);(1,2);(1,3);(2,3)|]
let bit mask n=mask land (1 lsl n)<>0
let expected mask seeds=
  let relation=Array.init 4(fun i->Array.init 4(fun j->i=j))in
  Array.iteri(fun n(u,v)->if bit mask n then relation.(u).(v)<-true)edges;
  for k=0 to 3 do for i=0 to 3 do for j=0 to 3 do
    relation.(i).(j)<-relation.(i).(j)||(relation.(i).(k)&&relation.(k).(j))
  done done done;
  let facts=ref 0 in
  for v=0 to 3 do for s=0 to 3 do
    if bit seeds s && relation.(s).(v)then facts:= !facts lor (1 lsl v)
  done done;
  let fired=ref 0 in Array.iteri(fun n(u,_)->if bit mask n && bit !facts u then incr fired)edges;
  !facts,!fired
let max_receipt=4*1024*1024
let max_output=1024*1024
let read_receipt path=
  require(not(Filename.is_relative path))"receipt path must be absolute";
  let initial=Unix.lstat path in require(initial.Unix.st_kind=Unix.S_REG)"receipt must be a regular non-symlink file";
  require(initial.Unix.st_size<=max_receipt)"receipt byte limit";
  let fd=Unix.openfile path[Unix.O_RDONLY;Unix.O_NONBLOCK]0 in
  Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
    let opened=Unix.fstat fd in
    require(opened.Unix.st_kind=Unix.S_REG && opened.st_dev=initial.st_dev && opened.st_ino=initial.st_ino)"receipt changed during open";
    let out=Buffer.create 4096 and block=Bytes.create 8192 in
    let rec loop()=let n=Unix.read fd block 0 (Bytes.length block)in if n>0 then begin
      require(Buffer.length out+n<=max_receipt)"receipt byte limit";Buffer.add_subbytes out block 0 n;loop()end in
    loop();Buffer.contents out)
let parse bytes=
  require(String.length bytes<=max_receipt)"receipt byte limit";
  let depth=ref 0 and quoted=ref false and escaped=ref false in
  String.iter(fun c->if !quoted then(if !escaped then escaped:=false else if c='\\'then escaped:=true else if c='"'then quoted:=false)
    else if c='"'then quoted:=true else if c='['||c='{'then(incr depth;require(!depth<=64)"JSON depth limit")else if c=']'||c='}'then decr depth)bytes;
  let json=try Yojson.Safe.from_string bytes with _->raise(Refused "malformed JSON")in
  let nodes=ref 0 in
  let rec inspect depth j=incr nodes;require(!nodes<=10000 && depth<=64)"JSON node/depth limit";
    match j with
    |`Assoc pairs->let seen=Hashtbl.create 32 in List.iter(fun(k,v)->require(not(Hashtbl.mem seen k))"duplicate JSON key";Hashtbl.add seen k();inspect(depth+1)v)pairs
    |`List xs->List.iter(inspect(depth+1))xs
    |`String _|`Int _|`Intlit _|`Float _|`Bool _|`Null->()
    |_->raise(Refused "non-JSON syntax")in inspect 0 json;json
let field key=function `Assoc xs->(try List.assoc key xs with Not_found->raise(Refused("missing field "^key)))|_->raise(Refused "expected JSON object")
let text=function `String s->s|_->raise(Refused "expected string")
let number=function `Float n->n|`Int n->float_of_int n|_->raise(Refused "expected finite number")
let finite n=match classify_float n with FP_nan|FP_infinite->false|_->true
let canonical_int s upper=
  let n=try int_of_string s with _->raise(Refused "invalid corpus integer")in
  require(n>=0 && n<=upper && string_of_int n=s)"noncanonical/out-of-range corpus integer";n
let validate bytes=
  let json=parse bytes in
  require(field "schema"json=`String "uos.ev-native-invocation.v1")"native receipt schema";
  require(field "exit_code"json=`Int 0 && field "failure"json=`Null)"abnormal invocation";
  let termination=field "child_termination"json in
  require(field "kind"termination=`String "EXITED" && field "code"termination=`Int 0)"child not normally exited";
  let args=match field "argv"json with`List xs->xs|_->raise(Refused "argv must be list")in
  require(args<>[] && List.length args<=512)"argv bounds";
  List.iter(fun j->let s=text j in require(String.length s<=4096 && not(String.contains s '\000'))"argv string bounds")args;
  require(not(Filename.is_relative(text(List.hd args))))"argv executable not absolute";
  let start=field "utc_started"json|>number and finish=field "utc_finished"json|>number
  and elapsed=field "elapsed_seconds"json|>number and deadline=field "deadline_seconds"json|>number in
  require(List.for_all finite[start;finish;elapsed;deadline])"nonfinite time";
  require(start>=0. && finish>=start && deadline>0. && deadline<=60. && elapsed>=0. && elapsed<=deadline+.1. && finish-.start<=deadline+.1.)"invocation time bounds";
  let output=field "output"json|>text in
  require(String.length output<=max_output)"output byte limit";
  require(field "output_sha256"json=`String(sha output))"output digest mismatch";
  let lines=String.split_on_char '\n'output in require(List.length lines<=4096)"line limit";
  let seen=Array.make 2048 false and cases=ref 0 and diagnostics=ref 0 in
  List.iter(fun line->require(String.length line<=4096)"line byte limit";
    if String.starts_with ~prefix:"RETE_CASE"line then begin
      let e,s,o,f,n=match String.split_on_char '|'line with
      |["RETE_CASE";e;s;o;f;n]->canonical_int e 63,canonical_int s 15,canonical_int o 1,canonical_int f 15,canonical_int n 6
      |_->raise(Refused "malformed RETE_CASE row")in
      let key=((e*16)+s)*2+o in require(not seen.(key))"duplicate corpus tuple";
      seen.(key)<-true;incr cases;
      let expected_facts,expected_fired=expected e s in
      require(f=expected_facts && n=expected_fired)(Printf.sprintf "closure/count mismatch edge=%d seed=%d order=%d expected=%d,%d observed=%d,%d"e s o expected_facts expected_fired f n)
    end else if line<>""then incr diagnostics)lines;
  require(!cases=2048 && Array.for_all Fun.id seen)"incomplete corpus";
  `Assoc["schema",`String "uos.ev107.rete-reference.v1";"status",`String "FINITE_CORPUS_CONSISTENT";
    "authority",`String "NONE";"admission",`String "NOT_GRANTED";
    "receipt_sha256",`String(sha bytes);"output_sha256",`String(sha output);
    "cases",`Int !cases;"diagnostic_lines",`Int !diagnostics;
    "algorithm",`String "Four-node reflexive transitive relation; fired count is present edges with reachable antecedent";
    "limits",`List(List.map(fun s->`String s)["Finite64DAG edge masks16seed masks2orders only; no general Rete refinement proof";"Receipt consistency cannot authenticate producer, candidate, executable or source; external immutable bindings and actual replay required";"Matching corpus does not grant dispatch effects, formal authority or EV admission";"Input4MiB/output1MiB/depth64/nodes10000/lines4096/line4096; native declared deadline<=60s checked, not externally enforced by this reader";"Recorded finite ordered timestamps checked; freshness/NTP synchronization and transitive execution closure not established"])]

(* Synthetic test producer uses a queue-based graph walk, not the relation
   algorithm above. These fixtures are never real runtime or admission evidence. *)
let fixture_expected mask seeds=
 let seen=Array.init 4(bit seeds)and work=Queue.create()in
 Array.iteri(fun i yes->if yes then Queue.add i work)seen;
 while not(Queue.is_empty work)do let u=Queue.take work in
 Array.iteri(fun n(a,b)->if bit mask n && a=u && not seen.(b)then(seen.(b)<-true;Queue.add b work))edges done;
 let facts=ref 0 and fired=ref 0 in
 Array.iteri(fun i yes->if yes then facts:= !facts lor(1 lsl i))seen;
 Array.iteri(fun n(u,_)->if bit mask n && seen.(u)then incr fired)edges;!facts,!fired
let fixture_output()=
 let b=Buffer.create 65536 in
 for e=0 to 63 do for s=0 to 15 do for o=0 to 1 do
 let f,n=fixture_expected e s in Printf.bprintf b "RETE_CASE|%d|%d|%d|%d|%d\n"e s o f n
 done done done;Buffer.contents b
let fixture output=`Assoc["schema",`String "uos.ev-native-invocation.v1";"argv",`List[`String "/synthetic/not-executed"];
 "utc_started",`Float 1000.;"utc_finished",`Float 1001.;"elapsed_seconds",`Float 1.;"deadline_seconds",`Float 30.;
 "exit_code",`Int 0;"failure",`Null;"child_termination",`Assoc["kind",`String "EXITED";"code",`Int 0];
 "output",`String output;"output_sha256",`String(sha output)]
let set k v=function `Assoc xs->`Assoc((k,v)::List.remove_assoc k xs)|_->assert false
let self_test()=
 let checks=ref 0 in
 let check name expected_pass bytes=
   let outcome=try ignore(validate bytes);true with Refused _->false in
   require(outcome=expected_pass)("self-test "^name);incr checks;Printf.printf "ORACLE_FIXTURE PASS %s\n%!"name in
 let out=fixture_output()in let good=fixture out in let run n ok j=check n ok(Yojson.Safe.to_string j)in
 run "synthetic-complete-independent-walk" true good;
 let rows=String.split_on_char '\n'out|>List.filter((<>)"")in
 let body xs=String.concat "\n"xs^"\n"in
 run "omission" false(fixture(body(List.tl rows)));
 run "duplicate" false(fixture(body(List.hd rows::rows)));
 run "duplicate-replaces-missing" false(fixture(body(List.hd rows::List.hd rows::List.tl(List.tl rows))));
 run "false-closure" false(fixture(body("RETE_CASE|0|0|0|1|0"::List.tl rows)));
 run "false-fired-count" false(fixture(body("RETE_CASE|0|0|0|0|1"::List.tl rows)));
 run "noncanonical-number" false(fixture(body("RETE_CASE|00|0|0|0|0"::List.tl rows)));
 run "malformed-row" false(fixture(body("RETE_CASE|0|0|0|0"::List.tl rows)));
 run "wrong-order" false(fixture(body("RETE_CASE|0|0|2|0|0"::List.tl rows)));
 run "digest-tamper" false(set "output_sha256"(`String(String.make 64 '0'))good);
 run "failed-exit" false(set "exit_code"(`Int 1)good);
 run "timeout" false(set "failure"(`String "timeout")good);
 run "killed" false(set "child_termination"(`Assoc["kind",`String "SIGNALED";"code",`Int 0])good);
 run "unbounded-child" false(set "deadline_seconds"(`Float 600.)good);
 run "elapsed-overrun" false(set "elapsed_seconds"(`Float 60.)good);
 run "regressing-time" false(set "utc_finished"(`Float 999.)good);
 let without_start=match good with `Assoc xs->`Assoc(List.remove_assoc "utc_started"xs)|_->assert false in
 let tail=Yojson.Safe.to_string without_start in
 check "nonfinite-time" false("{\"utc_started\":1e999,"^String.sub tail 1(String.length tail-1));
 run "output-oversize" false(fixture(String.make(max_output+1)'x'));
 let serialized=Yojson.Safe.to_string good in
 check "duplicate-key" false("{\"exit_code\":1,"^String.sub serialized 1(String.length serialized-1));
 check "escaped-duplicate-key" false("{\"exit_\\u0063ode\":1,"^String.sub serialized 1(String.length serialized-1));
 run "nested-duplicate-key" false(set "child_termination"(`Assoc["kind",`String "EXITED";"code",`Int 0;"code",`Int 1])good);
 check "malformed-json" false "{";
 check "oversize-json" false(String.make(max_receipt+1)' ');
 check "depth-limit" false(String.make 65 '['^"0"^String.make 65 ']');
 let private_dir=Filename.temp_dir "ev107-oracle-synthetic-" "" in
 let receipt=private_dir^"/receipt.json"in
 let channel=open_out_bin receipt in output_string channel serialized;close_out channel;
 check "regular-file-read" true(read_receipt receipt);
 let refused_path name path=
   let refused=try ignore(read_receipt path);false with Refused _->true in
   require refused("self-test "^name);incr checks;Printf.printf "ORACLE_FIXTURE PASS %s\n%!"name in
 Unix.symlink receipt(private_dir^"/link.json");refused_path "symlink-file-refusal"(private_dir^"/link.json");
 refused_path "directory-refusal"private_dir;
 Unix.mkfifo(private_dir^"/fifo")0o600;refused_path "fifo-refusal"(private_dir^"/fifo");
 refused_path "relative-path-refusal" "receipt.json";
 Printf.printf "ORACLE_FIXTURE SUMMARY synthetic_only=true checks=%d PASS\n" !checks
let ()=
 try match Array.to_list Sys.argv with
 |[_;"--self-test"]->self_test()
 |[_;path]->let bytes=read_receipt path in let report=validate bytes in print_endline(Yojson.Safe.to_string report)
 |_->raise(Refused "usage: ev107_rete_reference.ml ABSOLUTE_NATIVE_RECEIPT | --self-test")
 with Refused why->prerr_endline(Yojson.Safe.to_string(`Assoc["status",`String "REFUSED";"reason",`String why;"authority",`String "NONE"]));exit 1
 |Unix.Unix_error(e,_,_)->prerr_endline("REFUSED: "^Unix.error_message e);exit 1
