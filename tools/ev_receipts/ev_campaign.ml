(* Native observation of a closed, private EV98 component campaign.
   This is neither an admission endpoint nor producer authentication. *)
open Receipt_validator

let js s = `String s
let strings xs = `List(List.map js xs)
let contains text part =
 let rec loop i = i+String.length part<=String.length text &&
  (String.sub text i (String.length part)=part || loop(i+1)) in loop 0
let replace_once text before after =
 let rec positions i acc =
  if i+String.length before>String.length text then List.rev acc
  else positions(i+1)(if String.sub text i (String.length before)=before then i::acc else acc) in
 match positions 0 [] with
 | [i] -> String.sub text 0 i ^ after ^ String.sub text (i+String.length before) (String.length text-i-String.length before)
 | _ -> failwith "negative mutation anchor must occur exactly once"

let transcript cases = String.concat "" (List.concat_map(fun id->["EV98 START "^id^"\n";"EV98 PASS "^id^"\n"])cases)
let validate_transcript ~cases ~exit_code ~output =
 require(exit_code=0 && output=transcript cases) "incomplete, extra, reordered or nonpassing case execution"

type outcome = { status: Unix.process_status; output: string; stdout: string; stderr: string; elapsed: float; failure: string option }
let process ~deadline ~cwd ~environment ~seconds ~limit exe args =
 let started=mono() in
 let until=min deadline (started+.seconds) in
 require(until>started && limit>0) "campaign process budget exhausted";
 let r,w=Unix.pipe ~cloexec:true () in
 let er,ew=Unix.pipe ~cloexec:true () in
 let pid=Unix.fork() in
 if pid=0 then (try ignore(Unix.setsid());Unix.chdir cwd;Unix.close r;Unix.close er;
  Unix.dup2 w Unix.stdout;Unix.dup2 ew Unix.stderr;Unix.close w;Unix.close ew;
  let null=Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in Unix.dup2 null Unix.stdin;Unix.close null;
  Unix.execve exe (Array.of_list(exe::args)) environment with _->Unix._exit 127);
 Unix.close w;Unix.close ew;Unix.set_nonblock r;Unix.set_nonblock er;
 let status=ref None and eof=ref false and err_eof=ref false and buffer=Buffer.create 4096 and failure=ref None in
 let stdout=Buffer.create 4096 and stderr=Buffer.create 1024 in
 let chunk=Bytes.create 8192 in
 let terminate () =
  (try Unix.kill (-pid) Sys.sigkill with Unix.Unix_error(Unix.ESRCH,_,_)->());
  if !status=None then ((try Unix.kill pid Sys.sigkill with Unix.Unix_error(Unix.ESRCH,_,_)->());
   status:=Some(snd(Unix.waitpid [] pid))) in
 Fun.protect ~finally:(fun()->terminate();Unix.close r;Unix.close er)(fun()->
  (try
    while (!status=None || not !eof || not !err_eof) && !failure=None do
     if mono()>=until then failure:=Some "TIMEOUT"
     else (
      if !status=None then (match Unix.waitpid [Unix.WNOHANG] pid with 0,_->()|_,s->status:=Some s);
      let readers=(if !eof then [] else [r])@(if !err_eof then [] else [er]) in
      let ready,_,_=Unix.select readers [] [] 0.01 in
      List.iter(fun fd->try
       let n=Unix.read fd chunk 0 (Bytes.length chunk) in
       if n=0 then (if fd=r then eof:=true else err_eof:=true)
       else if Buffer.length buffer+n>limit then failure:=Some "OUTPUT_QUOTA"
       else (Buffer.add_subbytes buffer chunk 0 n;Buffer.add_subbytes (if fd=r then stdout else stderr) chunk 0 n)
       with Unix.Unix_error((Unix.EAGAIN|Unix.EWOULDBLOCK),_,_)->())ready)
    done
   with e->failure:=Some(Printexc.to_string e));
  terminate();
  {status=Option.get !status;output=Buffer.contents buffer;stdout=Buffer.contents stdout;stderr=Buffer.contents stderr;elapsed=mono()-.started;failure= !failure})

let status_json = function
 | Unix.WEXITED n -> `Assoc["kind",js "EXITED";"code",`Int n]
 | Unix.WSIGNALED n -> `Assoc["kind",js "SIGNALED";"ocaml_signal",`Int n]
 | Unix.WSTOPPED n -> `Assoc["kind",js "STOPPED";"ocaml_signal",`Int n]
let passed result = result.status=Unix.WEXITED 0 && result.failure=None
let exited result = match result.status with Unix.WEXITED n->n|_-> -1

let rec mkdir path =
 if not(Sys.file_exists path) then (mkdir(Filename.dirname path);Unix.mkdir path 0o700)
let write path bytes =
 mkdir(Filename.dirname path);
 let fd=Unix.openfile path [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC] 0o600 in
 let channel=Unix.out_channel_of_descr fd in
 Fun.protect ~finally:(fun()->close_out_noerr channel)(fun()->output_string channel bytes;flush channel)
let private_directory () =
 let name=Filename.temp_file "uos-ev98-campaign-" ".reserve" in
 (* The exclusively reserved file prevents another campaign taking this name. *)
 let path=name^".d" in Unix.mkdir path 0o700;path
let read_file budget path =
 check_budget budget;
 let before=Unix.lstat path in
 require(before.Unix.st_kind=Unix.S_REG && before.Unix.st_size<=67108864) "campaign nonregular or excessive file";
 charge budget before.Unix.st_size;
 let fd=Unix.openfile path [Unix.O_RDONLY;Unix.O_NONBLOCK;Unix.O_CLOEXEC] 0 in
 Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
  require(same_stat before(Unix.fstat fd)) "campaign file identity changed";
  let bytes=Bytes.create before.Unix.st_size in
  let rec loop offset=if offset<Bytes.length bytes then (
   let n=Unix.read fd bytes offset(Bytes.length bytes-offset) in require(n>0) "campaign file truncated";loop(offset+n)) in
  loop 0;
  let extra=Bytes.create 1 in require(Unix.read fd extra 0 1=0) "campaign file grew";
  require(same_stat before(Unix.fstat fd) && same_stat before(Unix.lstat path)) "campaign file changed";
  check_budget budget;Bytes.to_string bytes)
let reference path bytes = `Assoc["path",js path;"sha256",js(sha bytes);"bytes",`Int(String.length bytes)]
let file_names root relative =
 let count=ref 0 in
 let rec visit depth relative =
 incr count;require(depth<=24 && !count<=2048) "campaign tree quota";
 let path=if relative="" then root else root^"/"^relative in
 match (Unix.lstat path).Unix.st_kind with
 | Unix.S_REG -> [relative]
 | Unix.S_DIR ->
   let names=Array.to_list(Sys.readdir path) |> List.sort String.compare in
   require(List.length names<=1024) "directory entry quota";
   List.concat_map(fun n->visit(depth+1)(if relative="" then n else relative^"/"^n)) names
 | _ -> failwith "nonregular campaign tree entry" in
 visit 0 relative

let runner cases =
 "import gleam/io\n" ^
 String.concat "\n"(List.map((^)"import ")
  (List.sort_uniq String.compare(List.map(fun id->List.hd(String.split_on_char '.' id))cases))) ^
 "\n\npub fn main() {\n" ^
 String.concat ""(List.map(fun id->Printf.sprintf "  io.println(\"EV98 START %s\")\n  %s()\n  io.println(\"EV98 PASS %s\")\n" id id id)cases)^"}\n"
let manifest = "name = \"cepaf_gleam\"\nversion = \"1.0.0\"\ntarget = \"erlang\"\n[dependencies]\ngleam_stdlib = \"0.71.0\"\ngleam_json = \"3.1.0\"\ngleeunit = \"1.9.0\"\n"
let mutations = [
 "queue-capacity", "apps/cepaf_gleam/src/cepaf_gleam/crdt/delta_mesh_engine.gleam",
 "pub const max_pending_outbound = 256", "pub const max_pending_outbound = 257",
 "delta_mesh_engine_test.full_queue_rejects_without_advancing_round_and_can_drain_test";
 "physical-health-order", "apps/cepaf_gleam/src/cepaf_gleam/crdt/health_bridge.gleam",
 "int.compare(a.value.sample_epoch_us, b.value.sample_epoch_us)", "int.compare(b.value.sample_epoch_us, a.value.sample_epoch_us)",
 "delta_mesh_engine_test.newer_sample_time_wins_over_an_older_logical_counter_test";
 "nonforward-deadman-time", "apps/cepaf_gleam/src/cepaf_gleam/ha/deadman_freshness.gleam",
 "case now_ms <= reg.last_eval_ms", "case now_ms == reg.last_eval_ms",
 "deadman_freshness_test.backward_tick_cannot_clear_a_trip_test";
]
let recipe_descriptor =
 let refs xs=`List(List.map(fun(p,h)->`Assoc["path",js p;"sha256",js h])xs) in
 `Assoc["id",js Ev98_recipe.id;"baseline",js Ev98_recipe.baseline;
  "sources",strings Ev98_recipe.sources;"fixed_acceptance_and_policy",refs Ev98_recipe.fixed;
  "cases",strings Ev98_recipe.cases;"dependency_files",refs Ev98_recipe.dependency_files;
  "tools",`List(List.map(fun(n,p,h)->`Assoc["name",js n;"path",js p;"sha256",js h])Ev98_recipe.tools);
  "launcher_protocol",js "direct-ELF-ERTS";"launcher_environment",strings Ev98_recipe.launcher_environment;
  "private_manifest",js manifest;"positive_runner_sha256",js(sha(runner Ev98_recipe.cases));
  "mutations",`List(List.map(fun(n,p,b,a,c)->`Assoc["id",js n;"path",js p;"before",js b;"after",js a;"case",js c])mutations)]
let recipe_bytes = Yojson.Basic.to_string recipe_descriptor

let observe ~workspace ~ev ~revision =
 require(ev=98 && hex 40 revision) "observe supports only EV98 and a full lowercase immutable commit ID";
 let workspace=Unix.realpath workspace in
 require(Sys.file_exists(workspace^"/.jj")) "Jujutsu workspace required";
 let clock_start=run ~seconds:3. ~limit:8192 "/usr/bin/chronyc" ["-c";"tracking"] in
 let now=Unix.gettimeofday() and began=mono() in validate_clock_text ~now clock_start;
 let budget=make_budget ~seconds:180. ~bytes:268435456 () in
 let directory=private_directory() in
 let observations=ref [] and bindings=ref [] and negatives=ref [] and executed=ref [] in
 let finished_clock=ref `Null and error=ref None in
 let tool n=let _,p,_=List.find(fun(name,_,_)->name=n)Ev98_recipe.tools in p in
 let alias_dir=directory^"/native-bin" in Unix.mkdir alias_dir 0o700;
 let alias=alias_dir^"/erl" in Unix.symlink(tool "erlexec")alias;
 let environment=Array.of_list(["PATH="^alias_dir^":"^Filename.dirname(tool "escript")^":/usr/bin:/bin";
  "HOME="^directory;"TMPDIR="^directory;"LANG=C.UTF-8";"LC_ALL=C.UTF-8";
  "ERL_CRASH_DUMP="^directory^"/erl_crash.dump";"ERL_CRASH_DUMP_SECONDS=0"] @ Ev98_recipe.launcher_environment) in
 let invocations=ref 0 in
 let invoke name seconds exe args =
  check_budget budget;incr invocations;
  require(!invocations<=64) "campaign invocation quota";
  let started=Unix.gettimeofday() in
  let result=process ~deadline:budget.deadline ~cwd:directory ~environment ~seconds ~limit:1048576 exe args in
  charge budget(String.length result.output);
  let output=directory^"/"^name^".output" in write output result.output;
  let out=directory^"/"^name^".stdout" and err=directory^"/"^name^".stderr" in
  write out result.stdout;write err result.stderr;
  observations:= !observations@[`Assoc["name",js name;"argv",strings(exe::args);"cwd",js directory;
   "started_at",`Float started;"finished_at",`Float(Unix.gettimeofday());
   "elapsed_seconds",`Float result.elapsed;"deadline_seconds",`Float seconds;
   "termination",status_json result.status;"failure",(match result.failure with None->`Null|Some s->js s);
   "combined_output",reference output result.output;
   "stdout",reference out result.stdout;"stderr",reference err result.stderr]];
  result in
 let bind path bytes=bindings:= !bindings@[reference path bytes] in
 (try
   write(directory^"/recipe.json")recipe_bytes;bind(directory^"/recipe.json")recipe_bytes;
   write(directory^"/clock-start.output")clock_start;bind(directory^"/clock-start.output")clock_start;
   List.iter(fun(name,p,h)->let bytes=read_file budget p in
    require(name="boot" || String.starts_with ~prefix:"\127ELF" bytes) "recipe executable is not ELF";
    require(sha bytes=h) "pinned tool digest mismatch";bind p bytes)Ev98_recipe.tools;
   let producer_path=Unix.realpath Sys.executable_name in
   bind producer_path (read_file budget producer_path);
   (* The candidate reader is exactly the hashed recipe tool, never a workspace
      tool discovery path. User JJ/BEAM flags are absent from the child environment. *)
   let query args =
    let result=invoke("candidate-"^string_of_int(!invocations)) 5. (tool "jj")
     (["--ignore-working-copy";"--no-pager";"--color";"never";"-R";workspace]@args) in
    require(passed result) "pinned candidate reader failed";result.stdout in
   let selector="commit_id(\""^revision^"\")" in
   require(query["log";"-r";selector;"--no-graph";"-T";"self.commit_id() ++ \"\\n\""]=revision^"\n") "resolved commit ID mismatch";
   let candidate path =
    ignore(safe_path path);
    require(query["file";"list";"-r";selector;"-T";"file_type ++ \" \" ++ path ++ \"\\n\"";"--";"root:"^path]="file "^path^"\n") "candidate source missing or nonregular";
    query["file";"show";"-r";selector;"-T";"\"\"";"--";"root:"^path] in
   let source=List.map(fun path->path,candidate path)Ev98_recipe.sources in
   let fixed=List.map(fun(path,expected)->let bytes=candidate path in
    require(sha bytes=expected) ("fixed acceptance or policy mismatch: "^path);path,bytes)Ev98_recipe.fixed in
   let original_manifest=candidate "apps/cepaf_gleam/gleam.toml" in
   bind "candidate:apps/cepaf_gleam/gleam.toml" original_manifest;
   bind "candidate:apps/cepaf_gleam/manifest.toml" (candidate "apps/cepaf_gleam/manifest.toml");
   List.iter(fun(p,b)->bind ("candidate:"^p) b)(source@fixed);
   let dependency_names=List.concat_map(fun name->file_names Ev98_recipe.dependency_root name)Ev98_recipe.dependencies in
   require(List.sort String.compare dependency_names=List.sort String.compare(List.map fst Ev98_recipe.dependency_files)) "dependency closure file set mismatch";
   List.iter(fun(path,expected)->let bytes=read_file budget (Ev98_recipe.dependency_root^"/"^path) in
    require(sha bytes=expected)("pinned dependency digest mismatch: "^path);
    let target=directory^"/lib/"^path in write target bytes;bind target bytes)Ev98_recipe.dependency_files;
   let gleam_version=invoke "gleam-version" 5. (tool "gleam") ["--version"] in
   require(passed gleam_version) "Gleam version observation failed";
   let otp_version=invoke "otp-version" 5. (tool "erlexec") ["-version"] in
   require(passed otp_version) "OTP version observation failed";
   let run_package name cases mutation =
    let package=directory^"/"^name in
    let package_sources=List.map(fun(p,b)->p,(match mutation with Some(path,before,after) when p=path->replace_once b before after|_->b))source in
    let stage p bytes=let target=package^"/"^p in write target bytes;bind target bytes in
    List.iter(fun(p,b)->stage(String.sub p 17 (String.length p-17))b)package_sources;
    List.iter(fun(p,b)->if String.starts_with ~prefix:"apps/cepaf_gleam/test/" p && not(String.ends_with ~suffix:"/ev_delta_freshness_runner.gleam" p)
      then stage("src/"^Filename.basename p)b)fixed;
    stage "src/ev98_campaign_runner.gleam" (runner cases);
    stage "gleam.toml" manifest;
    let compiled=package^"/compiled" in
    let compile=invoke(name^"-compile")30. (tool "gleam")
     ["compile-package";"--target";"erlang";"--package";package;"--out";compiled;"--lib";directory^"/lib"] in
    require(passed compile)("component compilation failed: "^name);
    let outputs=file_names compiled "" in require(List.length outputs<=1024) "compiled file quota";
    List.iter(fun p->let full=compiled^"/"^p in bind full(read_file budget full))outputs;
    let paths=(compiled^"/ebin")::List.map(fun dep->directory^"/lib/"^dep^"/ebin")Ev98_recipe.dependencies in
    invoke(name^"-execute")15. (tool "erlexec")
     (["+S";"2:2";"+A";"1";"-noinput";"-noshell";"-boot";"no_dot_erlang";"-pa"]@paths@
      ["-s";"ev98_campaign_runner";"main";"-s";"init";"stop"]) in
   let positive=run_package "positive" Ev98_recipe.cases None in
   require(positive.failure=None) "positive process failure";
   validate_transcript ~cases:Ev98_recipe.cases ~exit_code:(exited positive) ~output:positive.output;
   executed:=Ev98_recipe.cases;
   List.iter(fun(name,path,before,after,case)->
    let result=run_package name [case] (Some(path,before,after)) in
    require(result.failure=None && result.status=Unix.WEXITED 1 &&
      String.starts_with ~prefix:("EV98 START "^case^"\n") result.output &&
      not(contains result.output("EV98 PASS "^case)) && contains result.output (List.nth(String.split_on_char '.' case)1) &&
      contains result.output "{'gleeunit@should',equal,2," && contains result.output "gleam_error=>panic")
      ("negative mutation was not rejected by its designated assertion: "^name);
    let mutant_path=directory^"/"^name^"/"^String.sub path 17 (String.length path-17) in
    let mutant=read_file budget mutant_path in
    require(mutant=replace_once(List.assoc path source)before after) "executed mutant source mismatch";
    let runner_path=directory^"/"^name^"/src/ev98_campaign_runner.gleam" in
    negatives:= !negatives@[`Assoc["id",js name;"source",js path;"original_sha256",js(sha(List.assoc path source));
     "mutant",reference mutant_path mutant;"runner",reference runner_path(read_file budget runner_path);
     "before",js before;"after",js after;"case",js case;"compile_invocation",js(name^"-compile");
     "execution_invocation",js(name^"-execute");"status",js "MUTANT_REJECTED"]])mutations;
   (* Recheck actual private executable inputs and observed tool bytes after execution. *)
   List.iter(fun binding->let p=Yojson.Basic.Util.to_string(field "path" binding) in
    if not(String.starts_with ~prefix:"candidate:" p) then
     require(sha(read_file budget p)=Yojson.Basic.Util.to_string(field "sha256" binding)) "bound artifact changed during campaign") !bindings;
   List.iter(fun invocation->List.iter(fun key->let ref=field key invocation in
    let path=Yojson.Basic.Util.to_string(field "path" ref) in
    require(sha(read_file budget path)=Yojson.Basic.Util.to_string(field "sha256" ref)) "captured output changed during campaign")
    ["combined_output";"stdout";"stderr"]) !observations;
   require((Unix.lstat alias).Unix.st_kind=Unix.S_LNK && Unix.readlink alias=tool "erlexec" && Unix.realpath alias=tool "erlexec") "native launcher alias changed";
   check_budget budget;
   let clock_end=run ~seconds:(min 3. (budget.deadline-.mono())) ~limit:8192 "/usr/bin/chronyc" ["-c";"tracking"] in
   let finished=Unix.gettimeofday() in validate_clock_text ~now:finished clock_end;check_budget budget;
   require(finished>=now && finished-.now<=180. && abs_float((finished-.now)-.(mono()-.began))<0.25) "campaign wall clock discontinuity";
   write(directory^"/clock-end.output")clock_end;bind(directory^"/clock-end.output")clock_end;
   finished_clock:=js(sha clock_end)
  with e->error:=Some(Printexc.to_string e));
 let report=`Assoc[
  "schema",js "uos.ev-component-campaign.v1";"recipe",js Ev98_recipe.id;"recipe_sha256",js(sha recipe_bytes);
  "ev",`Int ev;"revision",js revision;"workspace",js workspace;
  "status",js(if !error=None then "COMPONENT_OBSERVED" else "HOLD");
  "authority",js "NONE";"formal",js "Formal_unavailable";"sovereign",js "Sovereign_pending";
  "full_ev_runtime",js "NOT_ESTABLISHED";"admission",js "NOT_GRANTED";
  "scope",strings Ev98_recipe.sources;
  "limits",strings["Private single-host component execution only; no deployed mesh or effect-time fence";
   "Finite acceptance cases and three mutants do not prove all EV98 behavior";
   "Local cooperative host observation; no invocation or sovereign authentication";
   "Executable and dependency hashes do not establish a reproducible release closure"];
  "started_at",`Float now;"finished_at",`Float(Unix.gettimeofday());
  "clock_start",js(sha clock_start);"clock_end", !finished_clock;
  "environment",strings(Array.to_list environment);
  "launcher_alias",`Assoc["path",js alias;"target",js(tool "erlexec")];
  "executed_cases",strings !executed;"negative_controls",`List !negatives;
  "bindings",`List !bindings;"invocations",`List !observations;
  "artifacts",js directory;"error",(match !error with None->`Null|Some s->js s)] in
 write(directory^"/report.json")(Yojson.Basic.pretty_to_string report);report
