#use "ecology_file_transaction_port.ml";;
(* Private synthetic actual-FS and child-process controls. No production paths,
   grants, config bytes, public per-image fingerprints or network/model IO. *)
module P=Port
let checks=ref 0
let check name b=incr checks;if not b then failwith("TEST FAILED: "^name)
let field j k=match j with `Assoc xs->List.assoc k xs|_->failwith "object"
let s=function `String s->s|_->failwith "string"
let code j=s(field j "code")
let status j=s(field j "status")
let write path body=let oc=open_out_bin path in Unix.chmod path 0o600;
 Fun.protect ~finally:(fun()->close_out oc)(fun()->output_string oc body;flush oc;Unix.fsync(Unix.descr_of_out_channel oc))
let read path=let ic=open_in_bin path in Fun.protect ~finally:(fun()->close_in ic)(fun()->really_input_string ic(in_channel_length ic))
let mkdir p=Unix.mkdir p 0o700
let temp=Unix.realpath(Filename.get_temp_dir_name())
let base=Filename.concat temp(Printf.sprintf "uos-cutover-port-%d-%06x"(Unix.getpid())(Random.bits()))
let ()=mkdir base
let seq=ref 0
let digest c="sha256:"^String.make 64 c
let tx=digest 'a'and candidate=digest 'b'and manifest=digest 'c'
type fixture={home:string;root:string;control:string;staging:string;config:string}
let fixture ?(count=2)()=
 incr seq;let home=Filename.concat base(string_of_int !seq)in mkdir home;
 let root=Filename.concat home "files"and control=Filename.concat home "control"and staging=Filename.concat home "staging"in
 List.iter mkdir[root;control;staging];
 for i=0 to count-1 do write(Filename.concat root(Printf.sprintf "target%d"i))("old-secret-"^string_of_int i);
  write(Filename.concat staging(Printf.sprintf "source%d"i))("new-secret-"^string_of_int i)done;
 let config=Filename.concat home "config.json"in
 write config(P.encoded(`Assoc["schema_version",`Int 1;"root",`String root;"state_relative",`String ".txn";
 "control_directory",`String control;"staging_directory",`String staging;"transaction_id",`String tx;
 "candidate",`String candidate;"manifest",`String manifest]));{home;root;control;staging;config}
let req ?(epoch=1)?(generation=0) operation payload=`Assoc[
 "schema_version",`Int 1;"transaction_id",`String tx;"candidate",`String candidate;"manifest",`String manifest;
 "epoch",`Int epoch;"generation",`Int generation;"operation",`String operation;"payload",payload]
let call f ?epoch ?generation op payload=P.run f.config(P.encoded(req ?epoch ?generation op payload))
let empty=`Assoc[]
let edits n=`Assoc["edits",`List(List.init n(fun i->`Assoc["relative",`String(Printf.sprintf "target%d"i);
 "replacement_relative",`String(Printf.sprintf "source%d"i)]))]
let index i=`Assoc["index",`Int i]
let command k i=`Assoc["kind",`String k;"index",i]
let pending k i=`Assoc["command",command k i]
let result k i observation=`Assoc["command",command k i;"observation",observation]
let obs k=`Assoc["kind",`String k;"candidate",`Null;"manifest",`Null;"physical_count",`Null]
let records j=match field j "records"with `List xs->xs|_->failwith "records"
let crash f req hook=
 match Unix.fork()with
 |0->let c=P.decode_config f.config in let r=P.decode_request c req in
   ignore(P.execute ~hook:(fun h->if h=hook then Unix._exit 77)c r);Unix._exit 90
 |pid->let _,st=Unix.waitpid[]pid in check "injected child crash"(st=Unix.WEXITED 77)
let ()=
 let f=fixture()in
 check "initial inspect unprepared"(field(call f "inspect" empty)"prepared"=`Bool false);
 check "controller stage intent"(status(call f "checkpoint_pending"(pending "stage_files" `Null))="ok");
 let staged=call f "stage"(edits 2)in check "stage actual backups+independent pin"(status staged="ok" && field staged "prepared"=`Bool true);
 check "private pin is independent path"(Sys.file_exists(Filename.concat f.control "descriptor-pin.json"));
 check "stage did not mutate targets"(read(Filename.concat f.root "target0")="old-secret-0");
 let wire=P.encoded staged in List.iter(fun secret->check "no image bytes or private digest in receipt"(not(String.contains wire '\000') &&
  not(try ignore(Str.search_forward(Str.regexp_string secret)wire 0);true with Not_found->false)))
 ["old-secret";"new-secret";"descriptor_sha256"];
 let prepared=`Assoc["kind",`String "prepared";"candidate",`Null;"manifest",`String manifest;"physical_count",`Int 2]in
 check "controller prepared checkpoint"(status(call f "checkpoint_result"(result "stage_files" `Null prepared))="ok");
 let before=List.length(records(call f "inspect" empty))in
 check "stage exact replay no effects"(code(call f "stage"(edits 2))="replayed");
 check "replay no log growth"(List.length(records(call f "inspect" empty))=before);
 check "stage conflicting replay refused"(code(call f "stage"(edits 1))="conflicting_replay");
 check "native replace actual"(status(call f ~generation:1 "replace_one"(index 0))="ok" && read(Filename.concat f.root "target0")="new-secret-0");
 check "file-only verification fails mixed"(status(call f ~generation:2 "verify_new" empty)="unknown");
 check "no implicit retry pending verification"(code(call f ~generation:2 "verify_new" empty)="pending_outcome");
 check "stale generation refused"(code(call f ~generation:0 "restore_one"(index 0))="stale_generation");
 check "new epoch requires marker"(code(call f ~epoch:2 ~generation:3 "restore_one"(index 0))="recovery_marker_required");
 check "durable recovery epoch"(status(call f ~epoch:2 ~generation:3 "recovery_epoch" empty)="ok");
 check "restore after recovery"(status(call f ~epoch:2 ~generation:4 "restore_one"(index 0))="ok" && read(Filename.concat f.root "target0")="old-secret-0");
 check "verify old all"(status(call f ~epoch:2 ~generation:5 "verify_old" empty)="ok");
 check "close leaves evidence"(status(call f ~epoch:2 ~generation:6 "close" empty)="ok" && Sys.file_exists(Filename.concat f.control "descriptor-pin.json"));
 let f=fixture()in
 check "checkpoint result without intent"(code(call f "checkpoint_result"(result "fence_readers" `Null(obs "succeeded")))="missing_checkpoint_intent");
 ignore(call f "checkpoint_pending"(pending "fence_readers" `Null));
 check "checkpoint conflict refuses"(code(call f "checkpoint_result"(result "resume_readers" `Null(obs "succeeded")))="conflicting_checkpoint");
 check "exact external checkpoint"(status(call f "checkpoint_result"(result "fence_readers" `Null(obs "succeeded")))="ok");
 List.iter(fun hook->let f=fixture()in crash f(req "stage"(edits 2))hook;
   let report=call f "inspect" empty in
   check "stage crash retains pending"(List.length(records report)>=1);
   if hook=P.Before_effect then check "before effect stays unprepared"(field report "prepared"=`Bool false)
   else check "after stage effect independent pin reconciles backup set"(field report "prepared"=`Bool true);
   let replay=call f "stage"(edits 2)in
   check "lost stage ACK never reruns"(if hook=P.After_result then code replay="replayed"else status replay="unknown"))
 [P.Before_effect;P.After_effect;P.After_result];
 List.iter(fun hook->let f=fixture()in ignore(call f "stage"(edits 2));
  crash f(req ~generation:1 "replace_one"(index 0))hook;
  check "actual rename happened before crash"(read(Filename.concat f.root "target0")="new-secret-0");
  let report=call f "inspect" empty in check "crash restart has actual new image"(match field report "images"with `List(`String "new"::_)->true|_->false);
  check "crashed mutation cannot blind replay"(status(call f ~generation:1 "replace_one"(index 0))="unknown");
  ignore(call f ~epoch:2 ~generation:2 "recovery_epoch" empty);
  check "explicit new epoch restoration"(status(call f ~epoch:2 ~generation:3 "restore_one"(index 0))="ok" && read(Filename.concat f.root "target0")="old-secret-0"))
 [P.Kernel_mutation;P.Kernel_parent_sync];
 let f=fixture()in ignore(call f "stage"(edits 2));
 Unix.unlink(Filename.concat f.control "descriptor-pin.json");
 check "orphan state never trusts journal checksum"(code(call f "inspect" empty)="orphan_kernel_state");
 let f=fixture()in ignore(call f "stage"(edits 2));
 let p=Filename.concat f.control "record-000.json"in write p "{\"torn\":";
 check "partial record strict HOLD"(status(call f "inspect" empty)="hold");
 check "torn record preserved"(read p="{\"torn\":");
 let f=fixture()in Unix.symlink(Filename.concat f.root "target0")(Filename.concat f.staging "alias");
 let evil=`Assoc["edits",`List[`Assoc["relative",`String "target0";"replacement_relative",`String "alias"]]]in
 check "staging symlink refused before source read"(status(call f "stage" evil)="unknown");
 check "symlink refusal no target effect"(read(Filename.concat f.root "target0")="old-secret-0");
 let f=fixture()in
 let text=P.encoded(req "inspect" empty)in
 List.iter(fun bad->check "strict wire malformed refused"(status(P.run f.config bad)="hold"))
 ["/*comment*/"^text;text^"x";"{\"schema_version\":1,\"schema_version\":1}";"[NaN]";"[1,]";"[\"\\ud800\"]";"[\""^String.make 1(Char.chr 0x80)^"\"]";String.make 262145 ' '];
 List.iter(fun (key,v)->match req "inspect" empty with `Assoc xs->
  check "closed envelope field guard"(status(P.run f.config(P.encoded(`Assoc(List.map(fun(k,x)->k,if k=key then v else x)xs))))="hold")|_->())
 ["epoch",`Int 0;"generation",`Int(-1);"transaction_id",`String(digest 'd');"candidate",`String "sha256:bad";"manifest",`String("SHA256:"^String.make 64 'c');"payload",`Assoc["unknown",`Int 1]];
 let f=fixture ~count:15()in check "maximum15 stage actual"(status(call f "stage"(edits 15))="ok");
 for i=0 to 14 do check "all15 native replace"(status(call f ~generation:(i+1)"replace_one"(index i))="ok")done;
 check "all15 replacement verification"(status(call f ~generation:16 "verify_new" empty)="ok");
 for i=14 downto 0 do check "all15 actual restore"(status(call f ~generation:(31-i)"restore_one"(index i))="ok")done;
 check "all15 prior verification"(status(call f ~generation:32 "verify_old" empty)="ok");
 Printf.printf "%d library actual-FS checks PASS; private fixtures retained\n%!" !checks

let frame text=let n=String.length text in let b=Bytes.create 4 in
 for i=0 to 3 do Bytes.set b i(Char.chr((n lsr((3-i)*8))land 255))done;Bytes.to_string b^text
let framed_read bytes=
 let p=Filename.concat base "frame"in write p bytes;let ic=open_in_bin p in
 Fun.protect ~finally:(fun()->close_in ic)(fun()->
 try Ok(P.read_frame ic)with P.Hold code->Error code|End_of_file->Error "truncated_frame")
let ()=
 let valid=P.encoded(req "inspect" empty)in
 check "exact single frame decoded"(framed_read(frame valid)=Ok valid);
 List.iter(fun bytes->check "invalid framing refuses"(match framed_read bytes with Error _->true|_->false))
 ["";"\000";"\000\000\000\000";"\255\255\255\255";"\000\004\000\001";frame valid^"x";frame valid^frame valid;
  String.sub(frame valid)0(String.length valid+3)];
 List.iter(fun raw->check "strict UTF8 scalar rejection"(match P.parse_json("[\""^raw^"\"]")with Error _->true|_->false))
 ["\192\128";"\244\144\128\128";"\237\160\128";"\240\128\128\128";"\226\130";"\128"];
 List.iter(fun raw->check "valid Unicode scalar accepted"(match P.parse_json("[\""^raw^"\"]")with Ok _->true|_->false))
 ["\194\128";"\224\160\128";"\237\159\191";"\244\143\191\191";"\\ud800\\udc00"];
 let f=fixture()in
 let fifo=Filename.concat f.staging "fifo"in Unix.mkfifo fifo 0o600;
 let p=`Assoc["edits",`List[`Assoc["relative",`String "target0";"replacement_relative",`String "fifo"]]]in
 check "FIFO rejected without blocking read"(status(call f "stage" p)="unknown");
 check "FIFO refusal preserves target"(read(Filename.concat f.root "target0")="old-secret-0");
 let f=fixture()in write(Filename.concat f.staging "source0")(String.make(Kernel.max_file_bytes+1)'x');
 check "oversize staged file refused"(status(call f "stage"(edits 2))="unknown");
 check "oversize no target effect"(read(Filename.concat f.root "target0")="old-secret-0");
 let f=fixture()in Unix.link(Filename.concat f.staging "source0")(Filename.concat f.staging "hardlink");
 check "staged hardlink refused"(status(call f "stage"(edits 2))="unknown");
 let f=fixture()in Unix.chmod f.control 0o755;
 check "nonprivate control directory refused"(code(call f "inspect" empty)="unsafe_directory");
 let f=fixture()in
 write(Filename.concat f.control "unexpected")"untouched-private";
 check "unexpected owned namespace file HOLD"(code(call f "inspect" empty)="unexpected_control_file");
 check "unknown namespace preserved"(read(Filename.concat f.control "unexpected")="untouched-private");
 let f=fixture()in ignore(call f "stage"(edits 2));
 let path=Filename.concat f.control "record-001.json"in
 let original=read path in
 let j=P.json original in let fs=match j with `Assoc xs->xs|_->assert false in
 let corrupt=`Assoc(List.map(fun(k,v)->if k="record"then k,`Assoc["operation",`String "stage";"epoch",`Int 1;"generation",`Int 0;
 "status",`String "result";"payload",`Assoc["forged",`Bool true]]else k,v)fs)in
 write path(P.encoded corrupt);
 check "corrupt typed result HOLD"(status(call f "inspect" empty)="hold");
 check "corrupt result preserves files"(read(Filename.concat f.root "target0")="old-secret-0");
 let f=fixture()in
 for i=0 to 127 do
  ignore(call f ~generation:i "checkpoint_pending"(pending "fence_readers" `Null));
  ignore(call f ~generation:i "checkpoint_result"(result "fence_readers" `Null(obs "succeeded")))done;
 check "256 durable records inspect"(List.length(records(call f "inspect" empty))=256);
 check "record bound prevents new intent"(code(call f ~generation:128 "checkpoint_pending"(pending "fence_readers" `Null))="record_bound");
 check "record bound no kernel preparation"(not(Sys.file_exists(Filename.concat f.root ".txn")));
 Printf.printf "%d total library/framing/resource checks PASS\n%!" !checks

(* Optional actual compiled worker+guardian tests. Supplied argv pins are test
   executable locators, never commands/shell text or production configuration. *)
let process ?guardian worker config bytes=
 let input_r,input_w=Unix.pipe ~cloexec:true()and output_r,output_w=Unix.pipe ~cloexec:true()in
 let err=Unix.openfile "/dev/null"[Unix.O_WRONLY]0 in
 let executable,args=match guardian with None->worker,[|worker;config|]
  |Some g->g,[|g;worker;config;"3000"|]in
 let pid=Unix.create_process executable args input_r output_w err in
 Unix.close input_r;Unix.close output_w;Unix.close err;
 let rec send at=if at<String.length bytes then let n=Unix.write_substring input_w bytes at(String.length bytes-at)in send(at+n)in send 0;
 if guardian=None then Unix.close input_w;
 let b=Buffer.create 1024 and chunk=Bytes.create 4096 in
 let rec collect()=let ready,_,_=Unix.select[output_r][][]4. in
  if ready=[]then(Unix.kill pid Sys.sigkill;failwith "bounded test child timeout");
  let n=Unix.read output_r chunk 0 4096 in if n>0 then(Buffer.add_subbytes b chunk 0 n;check "test response bounded"(Buffer.length b<=P.max_response_bytes+4);collect())in
 collect();Unix.close output_r;if guardian<>None then Unix.close input_w;
 let _,st=Unix.waitpid[]pid in st,Buffer.contents b
let decode_response wire=
 if String.length wire<4 then failwith "missing worker frame";
 let n=ref 0 in for i=0 to 3 do n:=(!n lsl 8)lor Char.code wire.[i]done;
 check "response exact frame length"(!n=String.length wire-4);P.json(String.sub wire 4 !n)
let ()=match Array.to_list Sys.argv with
 |[_]->()
 |[_;"--worker";worker;"--guardian";guardian]->
  let f=fixture()in
  List.iter(fun(operation,payload)->let st,wire=process worker f.config(frame(P.encoded(req operation payload)))in
    check "direct worker exits0"(st=Unix.WEXITED 0);check "direct framed success"(status(decode_response wire)="ok"))
   ["stage",edits 2;"inspect",empty];
  List.iter(fun bytes->let st,wire=process worker f.config bytes in check "badwire child exit0 typed refusal"(st=Unix.WEXITED 0);
   check "badwire typed HOLD"(status(decode_response wire)="hold"))
   ["";"\000\000\000\000";"\255\255\255\255";frame(P.encoded(req "inspect" empty))^"x"];
  let f=fixture()in
  List.iter(fun(operation,payload)->let st,wire=process ~guardian worker f.config(frame(P.encoded(req operation payload)))in
    check "guardian observed worker exit and reaped"(st=Unix.WEXITED 0);
    check "actual guardian framed native success"(status(decode_response wire)="ok"))
   ["stage",edits 2;"inspect",empty];
  Printf.printf "%d total checks PASS; actual_guardian=true\n%!" !checks
 |_->failwith "test argv: [--worker EXEC --guardian EXEC]"

let ()=
 (* Actual prepared near-limit regression: unlike an empty ledger fixture,
    originals are retained and one target has genuinely been replaced. *)
 let f=fixture ~count:15()in
 check "escrow fixture actual15 preparation"(status(call f "stage"(edits 15))="ok");
 check "escrow fixture genuine prior rename"(status(call f ~generation:1 "replace_one"(index 0))="ok");
 let next=ref 2 and filled=ref false in
 while not !filled do
  let p=call f ~generation:!next "checkpoint_pending"(pending "fence_readers" `Null)in
  if status p<>"ok"then(check "forward checkpoint hits escrow boundary"(code p="recovery_escrow");filled:=true)
  else let r=call f ~generation:!next "checkpoint_result"(result "fence_readers" `Null(obs "succeeded"))in
   if status r<>"ok"then(check "forward result hits escrow boundary"(code r="recovery_escrow");filled:=true)
   else incr next
 done;
 incr next;
 let before=read(Filename.concat f.root "target1")in
 let forward=call f ~generation:!next "replace_one"(index 1)in
 check "near-limit forward refuses before target effect"(code forward="recovery_escrow" && read(Filename.concat f.root "target1")=before);
 let n=List.length(records(call f "inspect" empty))in
 check "remaining control slots include full recovery escrow"(256-n>=13+4*15);
 let gen=ref(!next+1)in
 let rc op payload=let j=call f ~epoch:2 ~generation:!gen op payload in check("bounded complete recovery "^op)(status j="ok");j in
 ignore(rc "recovery_epoch" empty);incr gen;
 ignore(rc "checkpoint_pending"(pending "fence_readers" `Null));
 ignore(rc "checkpoint_result"(result "fence_readers" `Null(obs "succeeded")));incr gen;
 for i=14 downto 0 do
  ignore(rc "checkpoint_pending"(pending "restore_file"(`Int i)));
  ignore(rc "restore_one"(index i));
  ignore(rc "checkpoint_result"(result "restore_file"(`Int i)(obs "succeeded")));incr gen
 done;
 ignore(rc "checkpoint_pending"(pending "verify_previous" `Null));
 ignore(rc "verify_old" empty);
 let verified=`Assoc["kind",`String "verified";"candidate",`String(digest 'd');"manifest",`Null;"physical_count",`Null]in
 ignore(rc "checkpoint_result"(result "verify_previous" `Null verified));incr gen;
 ignore(rc "checkpoint_pending"(pending "resume_readers" `Null));
 ignore(rc "checkpoint_result"(result "resume_readers" `Null(obs "succeeded")));incr gen;
 ignore(rc "close" empty);
 for i=0 to 14 do check "near-limit all15 original bytes restored"(read(Filename.concat f.root(Printf.sprintf "target%d"i))="old-secret-"^string_of_int i)done;
 check "complete restore fits finite256 control slots"(List.length(records(call f "inspect" empty))<=256);
 (* Explicit overlap regressions must refuse BEFORE creating any intent or
    Kernel stage, not merely detect later private-namespace corruption. *)
 List.iter(fun target->let f=fixture()in
  let control=Filename.concat f.root "control"in Unix.rename f.control control;
  let j=P.json(read f.config)in let fs=match j with `Assoc fs->fs|_->assert false in
  write f.config(P.encoded(`Assoc(List.map(fun(k,v)->k,if k="control_directory"then `String control else v)fs)));
  let payload=`Assoc["edits",`List[`Assoc["relative",`String target;"replacement_relative",`String "source0"]]]in
  check "private control target alias refused before intent"(code(call f "stage" payload)="private_target_alias");
  check "alias refusal no kernel state"(not(Sys.file_exists(Filename.concat f.root ".txn")));
  check "alias refusal no private record"(not(Sys.file_exists(Filename.concat control "record-000.json"))))
 ["control/record-000.json";"control/lock";"control/descriptor-pin.json"];
 let f=fixture()in
 let staging=Filename.concat f.root "staging"in Unix.rename f.staging staging;
 let fs=match P.json(read f.config)with `Assoc fs->fs|_->assert false in
 write f.config(P.encoded(`Assoc(List.map(fun(k,v)->k,if k="staging_directory"then `String staging else v)fs)));
 let payload=`Assoc["edits",`List[`Assoc["relative",`String "staging/source0";"replacement_relative",`String "source0"]]]in
 check "staging target alias refused"(code(call f "stage" payload)="private_target_alias");
 let f=fixture()in let config=Filename.concat f.root "controller-config.json"in Unix.rename f.config config;
 let f={f with config}in
 let payload=`Assoc["edits",`List[`Assoc["relative",`String "controller-config.json";"replacement_relative",`String "source0"]]]in
 check "locator target alias refused"(code(call f "stage" payload)="private_target_alias");
 Printf.printf "%d total checks PASS; control escrow + alias regressions\n%!" !checks
let ()=
 let f=fixture()in ignore(call f "stage"(edits 2));
 check "new epoch cannot reset generation"(code(call f ~epoch:2 ~generation:0 "recovery_epoch" empty)="recovery_epoch_not_new");
 let record=Filename.concat f.control "record-000.json"in let original=read record in write record(original^" ");
 check "noncanonical control record fails closed"(code(call f "inspect" empty)="noncanonical_record");
 let f=fixture()in
 let c=P.decode_config f.config and r=P.decode_request(P.decode_config f.config)(req "stage"(edits 2))in
 let unknown=try ignore(P.execute ~hook:(function P.After_result->Unix.unlink(Filename.concat f.control "descriptor-pin.json")|_->())c r);false
  with P.Hold code->code="commit_unknown"in
 check "post-result readback failure classified unknown"unknown;
 check "post-result committed history retained"(Sys.file_exists(Filename.concat f.control "record-001.json"));
 Printf.printf "%d TOTAL checks PASS; no authority or activation\n%!" !checks
let ()=
 List.iter(fun operation->let f=fixture()in ignore(call f "stage"(edits 2));
  let r=if operation="checkpoint_result"then(
    ignore(call f ~generation:1 "checkpoint_pending"(pending "fence_readers" `Null));
    req ~generation:1 operation(result "fence_readers" `Null(obs "succeeded")))
   else req ~epoch:2 ~generation:1 operation empty in
  let c=P.decode_config f.config in let r=P.decode_request c r in
  let before=List.length(P.read_records c)in
  let unknown=try ignore(P.execute ~hook:(function P.After_result->Unix.unlink(Filename.concat f.control "descriptor-pin.json")|_->())c r);false
   with P.Hold code->code="commit_unknown"in
  check("postappend unknown "^operation)unknown;
  check("postappend retains durable record "^operation)(List.length(P.read_records c)=before+1))
 ["checkpoint_result";"recovery_epoch"];
 Printf.printf "%d FINAL TOTAL checks PASS; existing guardian included when supplied\n%!" !checks
