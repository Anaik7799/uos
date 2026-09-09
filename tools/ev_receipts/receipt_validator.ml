(* Read-only EV receipt consistency. This never authenticates producers or admits EVs. *)
let require b message = if not b then failwith message
let sha bytes = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) bytes
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let hex n s = String.length s=n && String.for_all (function '0'..'9'|'a'..'f'->true|_->false) s
let mono () = Mtime.Span.to_float_ns (Mtime_clock.elapsed ()) /. 1e9
let finite x = match classify_float x with FP_nan|FP_infinite->false|_->true
type budget = { clock : unit -> float; deadline : float; mutable remaining_bytes : int }
let make_budget ?(clock=mono) ?(seconds=120.) ?(bytes=16777216) () =
 require(finite seconds && seconds>0. && bytes>=0) "invalid reader budget";
 let now=clock() in require(finite now) "invalid budget clock";
 {clock;deadline=now+.seconds;remaining_bytes=bytes}
let check_budget budget =
 let now=budget.clock() in require(finite now && now<budget.deadline) "validation deadline"
let charge budget bytes =
 check_budget budget;
 require(bytes>=0 && bytes<=budget.remaining_bytes) "aggregate content byte quota";
 budget.remaining_bytes<-budget.remaining_bytes-bytes
let assoc = function `Assoc xs->xs|_->failwith "expected object"
let field key obj = try List.assoc key (assoc obj) with Not_found->failwith("missing key: "^key)
let str = function `String s->require(String.length s>0 && String.length s<=1024 && not(String.contains s '\000')) "invalid string";s|_->failwith "expected string"
let int = function `Int n->n|_->failwith "expected integer"
let number = function `Int n->float_of_int n|`Float f->require(finite f) "nonfinite number";f|_->failwith "expected finite number"
let list = function `List xs->xs|_->failwith "expected array"
let keys expected obj =
 let names=List.map fst(assoc obj) in
 require(List.length names=List.length(List.sort_uniq String.compare names)) "duplicate object key";
 require(List.sort String.compare names=List.sort String.compare expected) "missing or unknown object key"
let strings ?(empty=false) value =
 let xs=List.map str(list value) in
 require(List.length xs<=256 && (empty || xs<>[])) "empty or excessive array";
 require(List.length xs=List.length(List.sort_uniq String.compare xs)) "duplicate array entry";xs
let same_strings expected value = require(List.sort String.compare(strings value)=List.sort String.compare expected) "coverage or scope mismatch"
let parse bytes =
 require(String.length bytes<=1048576) "JSON byte quota";
 (* Limit nesting before calling the recursive parser, including malformed input. *)
 let depth=ref 0 and quoted=ref false and escaped=ref false and tokens=ref 0 in
 String.iter(fun c->if !quoted then (if !escaped then escaped:=false else if c='\\' then escaped:=true else if c='"' then quoted:=false)
  else match c with '"'->quoted:=true| '['|'{'->incr depth;incr tokens;require(!depth<=32) "JSON depth quota"
  |']'|'}'->decr depth|','|':'->incr tokens|_->())bytes;
 require(!tokens<=50000) "JSON token quota";
 let json=Yojson.Basic.from_string bytes in
 let rec visit depth value = require(depth<=32) "JSON depth quota";
  match value with
  | `Assoc xs->let names=List.map fst xs in require(List.length names=List.length(List.sort_uniq String.compare names)) "duplicate JSON key";
    List.iter(fun(k,v)->require(String.length k<=1024) "key length quota";visit(depth+1)v)xs
  | `List xs->List.iter(visit(depth+1))xs
  | `Float x->require(finite x) "nonfinite JSON number"
  | `String s->require(String.length s<=8192) "JSON string quota"
  | _->() in
 visit 0 json;json
let safe_path path =
 require(path<>"" && String.length path<=1024 && Filename.is_relative path) "nonrelative or empty path";
 let pieces=String.split_on_char '/' path in
 require(List.length pieces<=24 && List.for_all(fun p->p<>"" && p<>"." && p<>".." &&
  String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'|'.'->true|_->false)p)pieces) "noncanonical path";
 require(not(List.exists(fun p->List.mem p [".git";".jj";".ssh";".gnupg"])pieces)) "private state path";
 pieces
let same_stat a b = a.Unix.st_dev=b.Unix.st_dev && a.Unix.st_ino=b.Unix.st_ino && a.Unix.st_kind=b.Unix.st_kind &&
 a.Unix.st_size=b.Unix.st_size && a.Unix.st_mtime=b.Unix.st_mtime && a.Unix.st_ctime=b.Unix.st_ctime
let read_regular ?budget workspace relative =
 Option.iter check_budget budget;
 let pieces=safe_path relative in
 let rec walk base=function []->failwith "empty path"|[name]->let p=base^"/"^name in
  let st=Unix.lstat p in require(st.Unix.st_kind=Unix.S_REG && st.Unix.st_size<=1048576) "nonregular or oversized input";p,st
 |name::rest->let p=base^"/"^name in require((Unix.lstat p).Unix.st_kind=Unix.S_DIR) "symlink or nondirectory path component";walk p rest in
 let path,before=walk workspace pieces in
 Option.iter(fun b->charge b before.Unix.st_size)budget;
 let fd=Unix.openfile path [Unix.O_RDONLY;Unix.O_NONBLOCK] 0 in
 Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
  require(same_stat before(Unix.fstat fd)) "file identity changed before read";
  let bytes=Bytes.create before.Unix.st_size in
  let rec read offset = if offset<Bytes.length bytes then let n=Unix.read fd bytes offset(Bytes.length bytes-offset) in require(n>0) "file truncated";read(offset+n) in
  read 0;
  let extra=Bytes.create 1 in require(Unix.read fd extra 0 1=0) "file grew";
  require(same_stat before(Unix.fstat fd) && same_stat before(Unix.lstat path)) "file changed during read";
  ignore(walk workspace pieces);Option.iter check_budget budget;Bytes.to_string bytes)
(* Bounded argv-only reader, adapted from tools/release_process.ml. No shell, stdin,
   network command, task operation or live evidence append is exposed. *)
let run ~seconds ~limit exe args =
 let r,w=Unix.pipe ~cloexec:true () in let started=mono() in
 let pid=Unix.fork() in
 if pid=0 then (try ignore(Unix.setsid());Unix.close r;Unix.dup2 w Unix.stdout;Unix.close w;
  let null=Unix.openfile "/dev/null" [Unix.O_RDWR] 0 in Unix.dup2 null Unix.stdin;Unix.dup2 null Unix.stderr;Unix.close null;
  Unix.execv exe(Array.of_list(exe::args)) with _->Unix._exit 127);
 Unix.close w;Unix.set_nonblock r;
 let status=ref None and eof=ref false and buf=Buffer.create 1024 and chunk=Bytes.create 8192 in
 let stop () = (try Unix.kill (-pid) Sys.sigkill with _->());
  if !status=None then ((try Unix.kill pid Sys.sigkill with _->());try ignore(Unix.waitpid [] pid) with _->());
  (try Unix.close r with _->()) in
 try
  while not !eof || !status=None do
   require(mono()-.started<=seconds) "subprocess timeout";
   if !status=None then (match Unix.waitpid [Unix.WNOHANG] pid with 0,_->()|_,s->status:=Some s);
   let ready,_,_=Unix.select (if !eof then [] else [r]) [] [] 0.01 in
   if ready<>[] then (try let n=Unix.read r chunk 0 (Bytes.length chunk) in
    if n=0 then eof:=true else(require(Buffer.length buf+n<=limit) "subprocess output quota";Buffer.add_subbytes buf chunk 0 n)
    with Unix.Unix_error((Unix.EAGAIN|Unix.EWOULDBLOCK),_,_)->())
  done;
  Unix.close r;
  require(!status=Some(Unix.WEXITED 0)) "read-only subprocess failed";
  Buffer.contents buf
 with e->stop();raise e
let jj ?budget workspace args =
 let rec root p = if Sys.file_exists(p^"/toolchains/nix-profile/bin/jj") then p else
  let parent=Filename.dirname p in require(parent<>p) "pinned jj unavailable";root parent in
 let exe=root workspace ^"/toolchains/nix-profile/bin/jj" in
 let seconds,limit=match budget with None->5.,1048576|Some b->
  check_budget b;min 5. (b.deadline-.b.clock()),min 1048576 b.remaining_bytes in
 require(seconds>0. && limit>0) "reader budget exhausted";
 let output=run ~seconds ~limit exe (["--ignore-working-copy";"--no-pager";"--color";"never";"-R";workspace]@args) in
 Option.iter(fun b->charge b(String.length output))budget;output
let candidate_bytes ?budget workspace revision path =
 let budget=Option.value ~default:(make_budget()) budget in
 let query args=jj ~budget workspace args in
 require(hex 40 revision) "invalid immutable commit ID";
 let selector="commit_id(\""^revision^"\")" in
 let resolved=query ["log";"-r";selector;"--no-graph";"-T";"self.commit_id() ++ \"\\n\""] in
 require(resolved=revision^"\n") "resolved commit ID mismatch";
 ignore(safe_path path);
 let metadata=query ["file";"list";"-r";selector;"-T";"file_type ++ \" \" ++ path ++ \"\\n\"";"--";path] in
 require(metadata="file "^path^"\n") "candidate source is missing, ambiguous, or nonregular";
 query ["file";"show";"-r";selector;"-T";"\"\"";"--";path]
let reference obj = keys ["path";"sha256"]obj;
 let p=str(field "path" obj) and h=str(field "sha256" obj) in ignore(safe_path p);require(hex 64 h) "invalid SHA256";p,h
let period ~now obj =
 let start=number(field "started_at" obj) and finish=number(field "finished_at" obj) in
 require(start>0. && start<=finish && finish<=now && now-.start<=3600. && finish-.start<=1800.) "stale, future or unordered invocation time";start,finish
let clean_execution obj =
 require(field "timed_out" obj=`Bool false && field "output_overflow" obj=`Bool false) "timeout or output overflow";
 let argv=list(field "command" obj) in require(argv<>[] && List.length argv<=256) "command argument quota";List.iter(fun x->ignore(str x))argv
let clock ~now ~start obj =
 keys ["source";"observed_at";"stratum";"offset_seconds";"uncertainty_seconds";"reference_age_seconds"]obj;
 require(str(field "source" obj)="chronyc tracking") "unrecognized clock source";
 let at=number(field "observed_at" obj) and stratum=int(field "stratum" obj) in
 require(at>0. && at<=start && start-.at<=300. && at<=now) "clock observation time";
 let offset=number(field "offset_seconds" obj) and uncertainty=number(field "uncertainty_seconds" obj) and age=number(field "reference_age_seconds" obj) in
 require(stratum>=1 && stratum<=15 && abs_float offset<2. && uncertainty>=0. && uncertainty<2. && age>=0. && age<=4096.) "unsynchronized clock observation"
let validate ~workspace ~bundle ~expected_ev ~expected_revision ~now =
 require(finite now && now>0.) "invalid observation time";
 require(expected_ev>=1 && expected_ev<=109 && hex 40 expected_revision) "invalid expected identity";
 let workspace=Unix.realpath workspace in require((Unix.lstat workspace).Unix.st_kind=Unix.S_DIR && Sys.file_exists(workspace^"/.jj")) "Jujutsu workspace required";
 let earliest=ref now in
 let started=mono() and tracked=Hashtbl.create 32 and budget=make_budget() in
 let read p = check_budget budget;
 require(now +. (mono()-.started) -. !earliest <=3600.) "receipt expired during validation";
  let b=read_regular ~budget workspace p in
  require(Hashtbl.length tracked<512) "tracked reference quota";
  (match Hashtbl.find_opt tracked p with Some h->require(h=sha b) "reused file changed"|None->Hashtbl.add tracked p(sha b));b in
 let referenced obj = let p,h=reference obj in let b=read p in require(sha b=h) "referenced bytes digest mismatch";p,h,b in
 let bundle_bytes=read bundle in let b=parse bundle_bytes in
 keys ["schema";"ev";"revision";"acceptance_ids";"scope";"source_manifest";"policy";"runtime";"formal"]b;
 require(str(field "schema" b)="uos.ev-bundle.v1" && int(field "ev" b)=expected_ev && str(field "revision" b)=expected_revision) "bundle identity mismatch";
 let coverage=strings(field "acceptance_ids" b) and scope=strings(field "scope" b) in
 List.iter(fun id->require(String.for_all(function 'A'..'Z'|'a'..'z'|'0'..'9'|'-'|'_'|'.'->true|_->false)id) "invalid acceptance ID")coverage;
 List.iter(fun p->ignore(safe_path p))scope;
 let manifest=list(field "source_manifest" b) in require(List.length manifest<=128 && manifest<>[]) "source manifest quota";
 let names=List.map(fun entry->let p,h,bytes=referenced entry in
  require(sha(candidate_bytes ~budget workspace expected_revision p)=h) "source differs from immutable candidate";
  require(bytes<>"") "empty source";p)manifest in
 require(names=List.sort_uniq String.compare names && names=List.sort String.compare scope) "manifest must be sorted, unique and cover scope";
 let manifest_hash=sha(Yojson.Basic.to_string(field "source_manifest" b)) in
 let policy_path,policy_hash,_=referenced(field "policy" b) in
 require(sha(candidate_bytes ~budget workspace expected_revision policy_path)=policy_hash) "policy differs from immutable candidate";
 let _,rh,rb=referenced(field "runtime" b) and _,fh,fb=referenced(field "formal" b) in
 require(rh<>fh) "runtime and formal receipts must differ";
 let output reference = let _,h,bytes=referenced reference in require(bytes<>"") "empty invocation output";h in
 let receipt kind bytes =
  let r=parse bytes in
  keys ["schema";"kind";"ev";"revision";"scope";"source_manifest_sha256";"policy_sha256";"acceptance_ids";"invocation";"clock";"toolchain";"negative_controls";"formal_result"]r;
  require(str(field "schema" r)="uos.ev-receipt.v1" && str(field "kind" r)=kind && int(field "ev" r)=expected_ev && str(field "revision" r)=expected_revision) "receipt identity mismatch";
  same_strings coverage(field "acceptance_ids" r);same_strings scope(field "scope" r);
  require(str(field "source_manifest_sha256" r)=manifest_hash && str(field "policy_sha256" r)=policy_hash) "receipt source or policy mismatch";
  let invocation=field "invocation" r in
  keys ["id";"command";"started_at";"finished_at";"exit_code";"timed_out";"output_overflow";"status";"executed_checks";"failed_checks";"skipped_checks";"output"]invocation;
  let id=str(field "id" invocation) in
  let start,finish=period ~now invocation in earliest:=min !earliest start;clean_execution invocation;
  require(int(field "exit_code" invocation)=0 && str(field "status" invocation)="PASS" && int(field "executed_checks" invocation)>=List.length coverage && int(field "executed_checks" invocation)<=1000000 && int(field "failed_checks" invocation)=0 && int(field "skipped_checks" invocation)=0) "nonpassing or unexecuted checks";
  let positive_output=output(field "output" invocation) in
  clock ~now ~start (field "clock" r);
  let toolchain=field "toolchain" r in keys ["name";"version";"executable_sha256"]toolchain;
  ignore(str(field "name" toolchain));ignore(str(field "version" toolchain));require(hex 64(str(field "executable_sha256" toolchain))) "toolchain digest";
  let controls=list(field "negative_controls" r) in require(controls<>[] && List.length controls<=32) "missing or excessive negative controls";
  let control_ids=List.map(fun c->keys ["id";"command";"started_at";"finished_at";"expected_exit_code";"actual_exit_code";"timed_out";"output_overflow";"output"]c;
   let cs,ce=period ~now c in require(cs>=start && ce<=finish) "control outside invocation";clean_execution c;
   let expected=int(field "expected_exit_code" c) in require(expected>0 && expected<=125 && int(field "actual_exit_code" c)=expected) "negative control did not reject";
   require(output(field "output" c)<>positive_output) "negative control reuses positive output";str(field "id" c))controls in
  require(List.length control_ids=List.length(List.sort_uniq String.compare control_ids)) "duplicate negative controls";
  if kind="runtime" then require(field "formal_result" r=`Null) "runtime formal result must be null"
  else (let f=field "formal_result" r in keys ["verifier";"result";"sorry_count";"unsupported_count";"undeclared_axioms"]f;
   ignore(str(field "verifier" f));require(str(field "result" f)="PASS" && int(field "sorry_count" f)=0 && int(field "unsupported_count" f)=0 && strings ~empty:true(field "undeclared_axioms" f)=[]) "formal result unresolved");id,positive_output in
 let runtime_id,runtime_output=receipt "runtime" rb and formal_id,formal_output=receipt "formal" fb in
 require(runtime_id<>formal_id && runtime_output<>formal_output) "two keys reuse invocation or output";
 Hashtbl.iter(fun p h->require(sha(read_regular ~budget workspace p)=h) "evidence changed before result")tracked;
 check_budget budget;
 require(now +. (mono()-.started) -. !earliest <=3600.) "receipt expired during validation";
 `Assoc ["schema",`String "uos.ev-consistency.v1";"status",`String "EVIDENCE_CONSISTENT";"authority",`String "NONE";
  "ev",`Int expected_ev;"revision",`String expected_revision;"bundle_sha256",`String(sha bundle_bytes);
  "runtime_sha256",`String rh;"formal_sha256",`String fh;"source_manifest_sha256",`String manifest_hash;
  "policy_sha256",`String policy_hash;"acceptance_ids",`List(List.map(fun x->`String x)coverage);
  "valid_until",`Float(!earliest+.3600.);"content_bytes_charged",`Int(16777216-budget.remaining_bytes);
  "limits",`List(List.map(fun x->`String x)["Synthetic or fabricated producer claims can be internally consistent; producer authenticity is not established.";
   "Listed source equality is checked against immutable Jujutsu bytes; semantic scope and acceptance completeness require independent review.";
   "Invocation execution and formal semantics are producer claims, not re-executed or authenticated here.";
   "Policy selection is caller-provided; canonical policy identity and applicability are not established.";
   "The shared byte budget includes local content, Jujutsu stdout and final rehashes; host-clock reads have a separate quota. Local filesystem calls require cooperative return and have no hard wall-clock guarantee.";
   "Trusted host and cooperative filesystem assumed; same-UID hostile races are not defeated.";
   "No task, runtime, review, integration or admission authority is granted."])]
let validate_clock_text ~now body =
 let parts=String.split_on_char ','(String.trim body)|>Array.of_list in
 require(Array.length parts=14 && parts.(13)="Normal") "host clock unavailable or unsynchronized";
 let n k = let f=float_of_string parts.(k) in require(finite f) "nonfinite clock field";f in
 let stratum=int_of_string parts.(2) and age=now-.n 3 in
 let offset=abs_float(n 4) and delay=n 10 and dispersion=n 11 in
 require(stratum>=1 && stratum<=15 && age>=0. && age<=4096. && offset<2. && delay>=0. && dispersion>=0. && delay/.2.+.dispersion<2.) "host clock outside synchronization bounds"
let observe_clock () =
 let body=run ~seconds:3. ~limit:8192 "/usr/bin/chronyc" ["-c";"tracking"] in
 let now=Unix.gettimeofday() in validate_clock_text ~now body;now,sha body
let finalize_observation ~now ~finished ~elapsed ~clock_start ~clock_end result =
 require(finite now && finite finished && finite elapsed && elapsed>=0. && finished>=now) "invalid final observation time";
 require(abs_float((finished-.now)-.elapsed)<0.25) "host clock stepped during validation";
 let valid_until=number(field "valid_until" result) in
 require(finished<=valid_until && now+.elapsed<=valid_until) "receipt expired during final clock observation";
 `Assoc(assoc result@[
  "observed_at",`Float now;"completed_at",`Float finished;"elapsed_seconds",`Float elapsed;
  "host_clock_start_sha256",`String clock_start;"host_clock_end_sha256",`String clock_end])
