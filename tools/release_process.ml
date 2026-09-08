#!/usr/bin/env ocaml
#use "topfind";;
#require "unix,yojson,cryptokit,mtime.clock.os";;
(* Native release preparation and probes. No shell evaluation, deployment
   authority, task mutation, production stop, or implicit admission. *)
open Unix
let require b s = if not b then failwith s
let emit stage status fields =
 print_endline(Yojson.Safe.to_string(`Assoc(
 ["schema",`String "uos.release-check.v1";"stage",`String stage;
  "status",`String status;"authority",`String "NONE"] @ fields)))
let mono() = Mtime.Span.to_float_ns(Mtime_clock.elapsed()) /. 1e9
let otp = "/nix/store/qq9f90d5giydnhpdxlqq83n21c22jq0b-erlang-29.0.6/lib/erlang/bin"
let canonical = "/home/an/NAS-setup/uos"
let env extra =
 let base=["PATH="^otp^":/home/an/.cargo/bin:/home/an/.nix-profile/bin:/home/an/dev/ver/zigvm/_opam/bin:/usr/bin:/bin";
 "LANG=C.UTF-8";"ERL_FLAGS=+S 2:2 +A 2";"ERL_CRASH_DUMP=/dev/null";"CC=/usr/bin/cc"] in
 let inherited=List.filter_map(fun k->Option.map(fun v->k^"="^v)(Sys.getenv_opt k))
 ["HOME";"XDG_RUNTIME_DIR";"DBUS_SESSION_BUS_ADDRESS";"OPAM_SWITCH_PREFIX";"OCAMLPATH"] in
 Array.of_list(extra @ base @ inherited)
type execution={code:int;output:string;elapsed:float}
let run ?(seconds=30.) ?(limit=4194304) ?(extra=[]) exe args =
 require(seconds>0. && seconds<=240.) "invalid deadline";
 require(not(Filename.is_relative exe)) "executable must be absolute";
 let r,w=pipe ~cloexec:true () in let started=mono() in let pid=fork() in
 if pid=0 then (try ignore(setsid());close r;dup2 w stdout;dup2 w stderr;close w;
   let n=openfile "/dev/null" [O_RDONLY] 0 in dup2 n stdin;close n;
   execve exe (Array.of_list(exe::args)) (env extra) with _->_exit 127);
 close w;set_nonblock r;
 let buf=Buffer.create 4096 and bytes=Bytes.create 8192 in let status=ref None and eof=ref false in
 let stop()=(try kill (-pid) Sys.sigkill with _->(try kill pid Sys.sigkill with _->()));
   (try ignore(waitpid [] pid) with _->());(try close r with _->()) in
 try
  while not !eof || !status=None do
   require(mono()-.started<=seconds) "subprocess timeout";
   if !status=None then (match waitpid [WNOHANG] pid with 0,_->()|_,s->status:=Some s);
   let ready,_,_=select (if !eof then [] else [r]) [] [] 0.02 in
   if ready<>[] then (try let n=read r bytes 0 (Bytes.length bytes) in
    if n=0 then eof:=true else (require(Buffer.length buf+n<=limit) "subprocess output limit";Buffer.add_subbytes buf bytes 0 n)
    with Unix_error((EAGAIN|EWOULDBLOCK),_,_)->())
  done;
  close r;
  let code=match !status with Some(WEXITED n)->n|Some(WSIGNALED n)|Some(WSTOPPED n)->128+n|None->125 in
  {code;output=Buffer.contents buf;elapsed=mono()-.started}
 with e->stop();raise e
let checked ?(seconds=30.) ?(extra=[]) exe args =
 let r=run ~seconds ~extra exe args in
 require(r.code=0)(Printf.sprintf "command failed (%s exit %d): %s" exe r.code
  (String.sub r.output 0 (min 2000(String.length r.output))));r.output
let read_file p max_bytes =
 let st=lstat p in require(st.st_kind=S_REG && st.st_size<=max_bytes)("invalid file: "^p);
 let ic=open_in_bin p in Fun.protect(fun()->really_input_string ic st.st_size) ~finally:(fun()->close_in_noerr ic)
let write_new p body =
 let fd=openfile p [O_WRONLY;O_CREAT;O_EXCL] 0o600 in let oc=out_channel_of_descr fd in
 Fun.protect(fun()->output_string oc body;flush oc;fsync fd) ~finally:(fun()->close_out_noerr oc)
let temp prefix=let p=Filename.temp_file prefix "" in unlink p;mkdir p 0o700;p
let hex n s=String.length s=n && String.for_all(function '0'..'9'|'a'..'f'->true|_->false)s
let sha p =
 let h=Cryptokit.Hash.sha256() and b=Bytes.create 65536 in let ic=open_in_bin p in
 Fun.protect(fun()->let rec loop()=let n=input ic b 0(Bytes.length b) in
  if n>0 then(h#add_substring b 0 n;loop()) in loop();
  Cryptokit.transform_string(Cryptokit.Hexa.encode()) h#result) ~finally:(fun()->close_in_noerr ic)
let rec files ?(depth=0) root rel =
 require(depth<=24) "directory nesting limit";
 let p=Filename.concat root rel in match(lstat p).st_kind with
 | S_REG->[rel]
 | S_DIR->Sys.readdir p |> Array.to_list |> List.sort String.compare |> List.concat_map(fun name->
   require(not(String.contains name '\n') && not(String.contains name '\r')) "invalid filename";
   files ~depth:(depth+1) root (if rel="" then name else rel^"/"^name))
 | _->failwith("non-regular release entry: "^rel)
let inventory root =
 let xs=files root "" |> List.filter((<>)"release-manifest.json") in
 require(List.length xs>0 && List.length xs<=20000) "inventory count limit";
 let size=List.fold_left(fun n p->n+(lstat(root^"/"^p)).st_size)0 xs in
 require(size<=536870912) "release byte limit";List.map(fun p->p,sha(root^"/"^p))xs
let assoc=function `Assoc xs->xs|_->failwith "expected JSON object"
let str=function `String s->s|_->failwith "expected JSON string"
let bool=function `Bool b->b|_->failwith "expected JSON boolean"
let int=function `Int n->n|`Intlit s->int_of_string s|_->failwith "expected JSON integer"
let field k xs=try List.assoc k xs with Not_found->failwith("missing "^k)
let keys required xs=require(List.sort String.compare(List.map fst xs)=List.sort String.compare required) "unknown/missing/duplicate JSON key"
let verify_release root =
 let m=read_file(root^"/release-manifest.json")4194304 |> Yojson.Safe.from_string |> assoc in
 keys ["schema";"candidate";"otp";"files";"application_admitted"] m;
 require(str(field "schema" m)="uos.release-manifest.v1") "manifest schema";
 require(not(bool(field "application_admitted" m))) "manifest cannot grant admission";
 let rev=str(field "candidate" m) in require(hex 40 rev) "invalid candidate";
 require(str(field "otp" m)="29") "unsupported runtime";
 let expected=field "files" m |> assoc |> List.map(fun(p,v)->p,str v) in
 List.iter(fun(p,d)->require(hex 64 d && Filename.is_relative p && p<>""
   && not(List.mem ".."(String.split_on_char '/' p))) "invalid manifest entry")expected;
 require(List.sort compare expected=List.sort compare(inventory root)) "inventory or bytes differ";
 require(String.trim(read_file(root^"/candidate.revision")42)=rev) "candidate differs";
 require(String.trim(checked(otp^"/erl")["-noshell";"-eval";"io:put_chars(erlang:system_info(otp_release)),halt()."])="29") "wrong actual OTP";
 rev
let copy src dst=ignore(checked "/usr/bin/cp" ["-R";"--";src;dst])
let in_dir p f=let old=getcwd() in chdir p;Fun.protect f ~finally:(fun()->chdir old)
let source_root()=
 let p=Sys.argv.(0)|>Filename.dirname|>Filename.dirname|>realpath in
 require(Sys.file_exists(p^"/.jj")) "build from repository tools/release_process.ml";p
let build dest =
 require(not(Filename.is_relative dest) && not(Sys.file_exists dest)) "new absolute destination required";
 let source=source_root() in
 let revision()=checked "/home/an/.cargo/bin/jj" ["--repository";source;"log";"-r";"@";"--no-graph";"-T";"commit_id"]|>String.trim in
 let rev=revision() in require(hex 40 rev) "invalid JJ revision";
 let tmp=temp "uos-native-release-" in mkdir(tmp^"/apps")0o700;
 List.iter(fun app->let s=source^"/apps/"^app and d=tmp^"/apps/"^app in mkdir d 0o700;
  copy(s^"/src")(d^"/src");List.iter(fun f->copy(s^"/"^f)(d^"/"^f))["gleam.toml";"manifest.toml"];
  if Sys.file_exists(s^"/priv/static") then(mkdir(d^"/priv")0o700;copy(s^"/priv/static")(d^"/priv/static")))
 ["cepaf_gleam";"indrajaal_gleam_web"];
 let app=tmp^"/apps/indrajaal_gleam_web" in mkdir(app^"/build")0o700;
 copy(canonical^"/apps/indrajaal_gleam_web/build/packages")(app^"/build/packages");
 let r=in_dir app(fun()->run ~seconds:180. "/home/an/.nix-profile/bin/gleam" ["export";"erlang-shipment"]) in
 write_new(tmp^"/build.log")r.output;require(r.code=0)("build failed: "^tmp^"/build.log");
 require(revision()=rev) "source changed during build";
 mkdir dest 0o700;
 Array.iter(fun n->if n<>"entrypoint.sh" && n<>"entrypoint.ps1" then copy(app^"/build/erlang-shipment/"^n)(dest^"/"^n))
 (Sys.readdir(app^"/build/erlang-shipment"));
 write_new(dest^"/candidate.revision")(rev^"\n");
 List.iter(fun name->copy(source^"/tools/"^name)(dest^"/"^name))["release_process.ml";"release_process.mojo"];
 mkdir(dest^"/release-env")0o700;
 List.iter(fun name->copy(source^"/ops/release/"^name)(dest^"/release-env/"^name))["flake.nix";"flake.lock"];
 let entries=inventory dest in
 write_new(dest^"/release-manifest.json")(Yojson.Safe.pretty_to_string(`Assoc[
 "schema",`String "uos.release-manifest.v1";"candidate",`String rev;"otp",`String "29";
 "application_admitted",`Bool false;"files",`Assoc(List.map(fun(p,h)->p,`String h)entries)]));
 ignore(verify_release dest);emit "build" "PASS" ["candidate",`String rev;"release",`String dest;
 "build_log",`String(tmp^"/build.log");"elapsed_monotonic_seconds",`Float r.elapsed;"files",`Int(List.length entries)]
let port s=
 require(String.length s<=5 && s<>"" && String.for_all(function '0'..'9'->true|_->false)s) "invalid port";
 let p=int_of_string s in require(p>=1024 && p<=65535) "port out of range";p
let launch kind release rest =
 let rev=verify_release release in
 let paths=Sys.readdir release|>Array.to_list|>List.filter_map(fun d->let p=release^"/"^d^"/ebin" in if Sys.file_exists p then Some p else None) in
 let extra,tail=match kind,rest with
 | "web",[p;host]->ignore(port p);
   require(host="nas-1.tail55d152.ts.net") "canonical Tailscale FQDN required for private staging";
   ["UOS_WEB_CANDIDATE="^rev;"UOS_WEB_PORT="^p;"UOS_WEB_BIND="^string_of_inet_addr inet_addr_loopback;
    "UOS_WEB_INSTANCE="^Option.value(Sys.getenv_opt "UOS_WEB_INSTANCE")~default:"manual-web";
    "UOS_WEB_ROLE="^Option.value(Sys.getenv_opt "UOS_WEB_ROLE")~default:"backup";
    "UOS_WEB_MANAGED="^Option.value(Sys.getenv_opt "UOS_WEB_MANAGED")~default:"false"],
   ["-eval";"'indrajaal_gleam_web@@main':run(indrajaal_gleam_web)."]
 | "tui",[mode;scenario;cycle]->
   require(List.mem mode ["real";"test"]) "invalid mode";
   require(List.mem scenario ["nominal";"disturbance";"recovery";"unavailable"]) "invalid scenario";
   let n=int_of_string cycle in require(n>=1 && n<=30) "cycle out of range";
   [],["-eval";"cepaf_gleam@ui@tui@homeostasis_evolution_view:main(),halt().";"-extra";mode;scenario;cycle]
 | _->failwith "web RELEASE PORT TAILSCALE_FQDN | tui RELEASE MODE SCENARIO CYCLE" in
 chdir release;
 ignore(alarm 0);
 execve(otp^"/erl")(Array.of_list((otp^"/erl")::["+S";"4:4";"+A";"4";"-noshell";"-pa"]@paths@tail))(env extra)
let runtime_check source =
 List.iter(fun bin->let tmp=temp "uos-runtime-check-" in
 ignore(checked(bin^"/erlc")["-o";tmp;source^"/apps/indrajaal_gleam_web/src/uos_web_runtime_ffi.erl"]);
 let result=checked ~extra:["UOS_OTP_RELEASE=99"] (bin^"/erl")["-noshell";"-pa";tmp;"-eval";
 "Actual=list_to_binary(erlang:system_info(otp_release)),{Reported,Erts,_,_,_,_,_}=uos_web_runtime_ffi:observe_vm(),case Actual=:=Reported andalso Reported=/= <<\"99\">> of true->io:format(\"OTP ~ts ERTS ~ts~n\",[Actual,Erts]),halt(0);false->halt(1) end."] in
 emit "runtime" "PASS" ["observed",`String(String.trim result)])
 ["/usr/lib/erlang/bin";otp]
let target base =
 let prefix="http://nas-1.tail55d152.ts.net:" in require(String.starts_with ~prefix base) "only canonical Tailscale FQDN allowed";
 ignore(port(String.sub base (String.length prefix)(String.length base-String.length prefix)))
let fetch base path =
 target base;
 let prefix="http://nas-1.tail55d152.ts.net:" in
 let p=String.sub base (String.length prefix) (String.length base-String.length prefix) in
 let resolve=if port p>=49152 then ["--resolve";"nas-1.tail55d152.ts.net:"^p^":127.0.0.1"] else [] in
 checked ~seconds:10. "/usr/bin/curl" (["--silent";"--show-error";"--fail";"--max-time";"5";"--connect-timeout";"2";
 "--max-filesize";"1048576";"--noproxy";"*"]@resolve@[base^path])
let identity body candidate =
 let m=Yojson.Safe.from_string body|>assoc in
 require(str(field "schema" m)="uos.web-runtime-identity.v1") "identity schema";
 require(str(field "otp_release" m)="29") "wrong live OTP";
 require(String.starts_with ~prefix:"17."(str(field "erts_version" m))) "OTP/ERTS mismatch";
 require(bool(field "runtime_ready" m)) "runtime not ready";
 require(not(bool(field "application_admitted" m))) "telemetry cannot grant admission";
 require(str(field "declared_candidate_revision" m)=candidate) "wrong candidate";
 let pid=str(field "os_pid" m) and id=str(field "run_id" m) in require(pid<>"" && id<>"") "missing process identity";id
let smoke base rev =
 require(hex 40 rev) "invalid expected revision";
 let before=identity(fetch base "/api/v1/runtime/identity")rev in
 List.iter(fun path->require(String.length(fetch base path)>0)("empty "^path))
 ["/";"/planning";"/mirage";"/wiki";"/zk";"/homeostasis/evolution";"/homeostasis/components";"/homeostasis/terminal"];
 let after=identity(fetch base "/api/v1/runtime/identity")rev in require(before=after) "process changed during probe";
 emit "smoke" "PASS" ["candidate",`String rev;"run_id",`String after;"pages",`Int 8]
let stages=[
 "intake",["task_claim";"clock";"scope"];
 "design",["hazards";"rollback_design";"acceptance"];
 "source",["candidate";"isolated_workspace";"source_stability"];
 "build",["toolchain";"build_exit";"dependency_snapshot"];
 "test",["unit";"negative";"browser";"tui"];
 "package",["inventory";"digest";"unexpected_file_rejection"];
 "staging",["full_server";"smoke";"restart";"rollback_rehearsal"];
 "authorize",["operator_request";"task_fence";"runtime_fence";"exact_target"];
 "deploy",["target_recheck";"bounded_cutover";"fallback_ready"];
 "observe",["live_identity";"fresh_data";"route_regression";"logs"];
 "recover",["fault_injection";"rollback_receipt";"restored_identity"];
 "close",["journal";"remaining_gaps";"task_completion"]]
let validate_record rev record =
 let m=assoc record in keys ["stage";"candidate";"status";"checks";"observed_at";"valid_until";"evidence_sha256"]m;
 let name=str(field "stage" m) in let required=try List.assoc name stages with Not_found->failwith "unknown stage" in
 require(str(field "candidate" m)=rev) "receipt candidate mismatch";
 require(str(field "status" m)="PASS") "receipt not passing";
 let xs=assoc(field "checks" m) in keys required xs;List.iter(fun(_,v)->require(bool v) "false requirement")xs;
 require(hex 64(str(field "evidence_sha256" m))) "invalid evidence digest";
 let observed=int(field "observed_at" m) and valid=int(field "valid_until" m) in let now=int_of_float(gettimeofday()) in
 require(observed<=now && now<=valid && valid-observed<=3600 && valid>=observed) "stale or future receipt";name
let validate_packet rev body =
 require(hex 40 rev) "invalid revision";
 let m=assoc body in keys ["schema";"candidate";"records"]m;
 require(str(field "schema" m)="uos.release-stages.v1" && str(field "candidate" m)=rev) "packet identity";
 let rs=match field "records" m with `List xs->xs|_->failwith "records must be array" in
 require(List.map(validate_record rev)rs=List.map fst stages) "missing, duplicate or unordered stages"
let packet p rev =
 validate_packet rev (read_file p 4194304|>Yojson.Safe.from_string);
 emit "packet" "PASS" ["scope",`String "structural consistency only; evidence and live authority must be checked independently"]
let selftest()=
 let n=ref 0 in let check label f=f();incr n;emit label "PASS" [] in
 let rejects f=try f();false with _->true in
 check "argv_no_shell"(fun()->let r=run "/usr/bin/printf" ["%s";"$(id);literal"] in require(r.code=0 && r.output="$(id);literal") "argv interpreted");
 check "nonzero_preserved"(fun()->require((run "/usr/bin/false" []).code=1) "exit lost");
 check "timeout_reaped"(fun()->require(rejects(fun()->ignore(run ~seconds:0.05 "/usr/bin/sleep" ["2"]))) "timeout accepted");
 check "output_bounded"(fun()->require(rejects(fun()->ignore(run ~limit:16 "/usr/bin/printf" ["%100s";"x"]))) "large output accepted");
 check "exec_failure"(fun()->require((run "/does/not/exist" []).code=127) "exec failure lost");
 check "bad_url"(fun()->require(rejects(fun()->target "http://example.com:4100")) "host accepted");
 check "bad_port"(fun()->require(rejects(fun()->ignore(port "4100;id"))) "port accepted");
 let rev=String.make 40 'a' and now=int_of_float(gettimeofday()) in
 List.iter(fun(stage,checks)->
  let valid=`Assoc["stage",`String stage;"candidate",`String rev;"status",`String "PASS";
   "checks",`Assoc(List.map(fun k->k,`Bool true)checks);"observed_at",`Int now;"valid_until",`Int(now+60);"evidence_sha256",`String(String.make 64 'b')] in
  check("stage_"^stage^"_positive")(fun()->ignore(validate_record rev valid));
  List.iter(fun key->check("stage_"^stage^"_reject_"^key)(fun()->
   let bad=`Assoc(("checks",`Assoc(List.map(fun k->k,`Bool(k<>key))checks))::List.remove_assoc "checks"(assoc valid)) in
   require(rejects(fun()->ignore(validate_record rev bad))) "false requirement accepted"))checks;
  List.iter(fun(key,value)->check("stage_"^stage^"_bad_"^key)(fun()->
   let bad=`Assoc((key,value)::List.remove_assoc key(assoc valid)) in
   require(rejects(fun()->ignore(validate_record rev bad))) "invalid receipt accepted"))
  ["candidate",`String(String.make 40 'c');"status",`String "UNKNOWN";"valid_until",`Int(now-1);"evidence_sha256",`String "missing"])stages;
 let records=List.map(fun(stage,checks)->`Assoc["stage",`String stage;"candidate",`String rev;"status",`String "PASS";
  "checks",`Assoc(List.map(fun k->k,`Bool true)checks);"observed_at",`Int now;"valid_until",`Int(now+60);"evidence_sha256",`String(String.make 64 'b')])stages in
 let valid_packet rs=`Assoc["schema",`String "uos.release-stages.v1";"candidate",`String rev;"records",`List rs] in
 check "packet_complete" (fun()->validate_packet rev(valid_packet records));
 List.iter(fun(label,rs)->check label(fun()->require(rejects(fun()->validate_packet rev(valid_packet rs))) "bad packet accepted"))
 ["packet_empty",[];"packet_missing",List.tl records;"packet_reordered",List.rev records;
  "packet_duplicate",List.hd records::records];
 check "packet_duplicate_key" (fun()->require(rejects(fun()->validate_packet rev (`Assoc(("candidate",`String rev)::assoc(valid_packet records))))) "duplicate accepted");
 emit "selftest" "PASS" ["checks",`Int !n;"scope",`String "checker tests; not production stage completion"]
let model_table() =
 let b=Buffer.create 8192 in
 for current=0 to 12 do for incoming=0 to 12 do for valid=0 to 1 do
  let next=if current<12 && current=incoming && valid=1 then current+1 else -1 in
  Buffer.add_string b(Printf.sprintf "%d %d %d %d\n" current incoming valid next)
 done done done;Buffer.contents b
let unit source =
 let tmp=temp "uos-native-unit-" in copy(source^"/apps/cepaf_gleam/src")(tmp^"/src");
 ignore(checked "/usr/bin/cp" ["-R";"--";source^"/apps/indrajaal_gleam_web/src/.";tmp^"/src/"]);
 let toml=read_file(source^"/apps/cepaf_gleam/gleam.toml")65536 in
 write_new(tmp^"/gleam.toml")(String.split_on_char '\n' toml|>List.filter((<>)"[dev-dependencies]")|>String.concat "\n");
 let names=["homeostasis_algebra";"homeostasis_ui_contract";"homeostasis_evidence";"agui_sse_api";"homeostasis_evolution_engine";"homeostasis_evolution_hud";"homeostasis_fprime_simulated";"homeostasis_fprime_wired";"physiological_homeostasis";"sysadmin_tui";"release_lifecycle"] in
 List.iter(fun n->copy(source^"/apps/cepaf_gleam/test/"^n^"_test.gleam")(tmp^"/src/"^n^"_test.gleam"))names;
 List.iter(fun n->copy(source^"/apps/indrajaal_gleam_web/test/"^n^".gleam")(tmp^"/src/"^n^".gleam"))
 ["runtime_identity_test";"homeostasis_transport_test";"homeostasis_http_probe"];
 let lib=canonical^"/apps/cepaf_gleam/build/dev/erlang" in
 let built=run ~seconds:90. "/home/an/.nix-profile/bin/gleam" ["compile-package";"--target";"erlang";"--package";tmp;"--out";tmp^"/compiled";"--lib";lib] in
 write_new(tmp^"/build.log")built.output;require(built.code=0)("unit build failed: "^tmp^"/build.log");
 let paths=Sys.readdir lib|>Array.to_list|>List.filter_map(fun d->let p=lib^"/"^d^"/ebin" in if Sys.file_exists p then Some p else None) in
 let args=["-noshell";"-pa"]@paths@["-pa";tmp^"/compiled/ebin";"-eval"] in
 let expr="case eunit:test(["^String.concat ","(List.map(fun n->n^"_test")names@["runtime_identity_test";"homeostasis_transport_test"])^"],[verbose]) of ok->halt(0);error->halt(1) end." in
 let tested=run ~seconds:60. (otp^"/erl")(args@[expr]) in write_new(tmp^"/unit.log")tested.output;
 require(tested.code=0)("unit failure: "^tmp^"/unit.log");
 let gleam=checked(otp^"/erl")(args@["release_lifecycle_test:print_model_table(),halt()."]) in
 require(gleam=model_table()) "FPP interpreter disagrees with OCaml prefix oracle";
 let mojo=checked ~seconds:60. "/home/an/.pixi/bin/pixi"
 ["run";"--no-install";"--frozen";"--manifest-path";canonical^"/services/inference/max/pixi.toml";"mojo";source^"/tools/release_process.mojo";"model-table"] in
 require(mojo=model_table()) "Mojo interpreter disagrees with OCaml prefix oracle";
 write_new(tmp^"/differential.txt")gleam;
 emit "unit-and-differential" "PASS" ["evidence",`String tmp;"transition_cases",`Int 338;
 "unit_output",`String(String.sub tested.output (max 0(String.length tested.output-100))(min 100(String.length tested.output)))]
let browser source release p =
 require(port p>=49152) "browser checks require a private high port";
 let rev=verify_release release and tmp=temp "uos-release-browser-" in
 let base="http://nas-1.tail55d152.ts.net:"^p in smoke base rev;
 copy(source^"/tools/validation/homeostasis_browser_check.ml")(tmp^"/browser_check.ml");
 let toolchain=Option.value(Sys.getenv_opt "UOS_RELEASE_TOOLCHAIN")
  ~default:(canonical^"/var/releases/indrajaal-web/toolchain-20260908-0551") |> realpath in
 require(String.starts_with ~prefix:"/nix/store/" toolchain
   && Sys.file_exists(toolchain^"/bin/cc") && Sys.file_exists(toolchain^"/lib/libcurl.so"))
  "pinned Nix release toolchain required; see ops/release/flake.nix";
 ignore(checked ~seconds:60. "/home/an/dev/ver/zigvm/_opam/bin/ocamlfind"
  ["ocamlopt";"-cc";toolchain^"/bin/cc";"-ccopt";"-L"^toolchain^"/lib";
   "-cclib";"-Wl,-rpath,"^toolchain^"/lib";"-linkpkg";"-package";"playwright,eio_main,yojson";
   "-o";tmp^"/browser-check";tmp^"/browser_check.ml"]);
 let r=run ~seconds:90. (tmp^"/browser-check")
  [base^"/homeostasis/evolution";tmp;"/opt/google/chrome/chrome";"--full-release"] in
 write_new(tmp^"/browser.log")r.output;
 require(r.code=0)("browser failed: "^tmp^"/browser.log");smoke base rev;
 let checks=String.split_on_char '\n' r.output|>List.filter(String.starts_with ~prefix:"PASS: ")|>List.length in
 emit "browser" "PASS" ["checks",`Int checks;"evidence",`String tmp;"candidate",`String rev;"toolchain",`String toolchain]
let package_faults release =
 ignore(verify_release release);
 let tmp=temp "uos-package-faults-" in
 let clone=tmp^"/copy" in copy release clone;
 let rejects label f =
  f();
  let refused=try ignore(verify_release clone);false with _->true in
  require refused(label^" accepted");emit label "PASS" [] in
 let candidate=read_file(clone^"/candidate.revision")42 in
 rejects "altered_artifact" (fun()->let oc=open_out_bin(clone^"/candidate.revision")in output_string oc(String.make 40 'f'^"\n");close_out oc);
 let oc=open_out_bin(clone^"/candidate.revision")in output_string oc candidate;close_out oc;
 rejects "unexpected_file" (fun()->write_new(clone^"/rogue.beam")"fixture");
 unlink(clone^"/rogue.beam");
 let saved=read_file(clone^"/candidate.revision")42 in unlink(clone^"/candidate.revision");
 require (try ignore(verify_release clone);false with _->true) "missing artifact accepted";
 emit "missing_artifact" "PASS" [];
 write_new(clone^"/candidate.revision")saved;
 rejects "symlink" (fun()->symlink "/dev/null" (clone^"/unexpected-link"));
 unlink(clone^"/unexpected-link");ignore(verify_release clone);
 emit "package-faults" "PASS" ["checks",`Int 5;"scope",`String "private copied release only"]
let parity source release base =
 let rev=verify_release release and tmp=temp "uos-frontend-parity-" in
 let ml="/home/an/dev/ver/zigvm/_opam/bin/ocaml" in
 let n=ref 0 in
 let compare_case label arguments expected =
  let a=run ~seconds:90. ml ((source^"/tools/release_process.ml")::arguments) in
  let b=run ~seconds:90. "/home/an/.pixi/bin/pixi"
   (["run";"--no-install";"--frozen";"--manifest-path";canonical^"/services/inference/max/pixi.toml";
      "mojo";source^"/tools/release_process.mojo"]@arguments) in
  write_new(tmp^"/"^label^"-ocaml.txt")a.output;write_new(tmp^"/"^label^"-mojo.txt")b.output;
  require(a.code=expected && b.code=expected)("exit parity failure: "^label);
  require(a.output=b.output)("output parity failure: "^label);
  incr n;emit ("parity_"^label) "PASS" [] in
 List.iter(fun(label,args,code)->compare_case label args code)[
  "checker",["selftest"],0;"prefix",["model-table"],0;"model_checks",["model-selftest"],0;
  "runtime",["runtime-check";source],0;"package",["verify";release],0;
  "corruption",["package-faults";release],0;
  "missing_package",["verify";tmp^"/missing"],1;"refuse_overwrite",["build";release],1;
  "unknown_command",["unknown"],1;"bad_mode",["tui";release;"bad";"nominal";"1"],1;
  "bad_port",["web";release;"4100;id";"127.0.0.1"],1;
  "bad_host",["smoke";"http://example.com:4100";rev],1;
  "wrong_revision",["smoke";base;String.make 40 'a'],1;
  "smoke",["smoke";base;rev],0;
  "test_tui",["tui";release;"test";"disturbance";"3"],0];
 emit "frontend-parity" "PASS" ["cases",`Int !n;"evidence",`String tmp;
 "scope",`String "exact exit/stdout parity for listed cases; dynamic VM values and mutation targets have separate probes"]
let main()=match Array.to_list Sys.argv with
 | [_;"browser";source;release;p]->browser source release p
 | [_;"parity";source;release;base]->parity source release base
 | [_;"model-selftest"]->ignore(model_table());emit "model-selftest" "PASS" ["checks",`Int 338]
 | [_;"package-faults";release]->package_faults release
 | [_;"unit";source]->unit source
 | [_;"model-table"]->print_string(model_table())
 | [_;"selftest"]->selftest()
 | [_;"runtime-check";source]->runtime_check source
 | [_;"build";dest]->build dest
 | [_;"verify";dest]->let rev=verify_release dest in emit "package" "PASS" ["candidate",`String rev]
 | [_;"smoke";base;rev]->smoke base rev
 | [_;"packet";p;rev]->packet p rev
 | _::("web"|"tui" as kind)::release::rest->launch kind release rest
 | _->failwith "usage: selftest | runtime-check SOURCE | unit SOURCE | browser SOURCE RELEASE PRIVATE_PORT | build DEST | verify RELEASE | web RELEASE PORT TAILSCALE_FQDN | tui RELEASE MODE SCENARIO CYCLE | smoke TAILSCALE_BASE REVISION | packet JSON REVISION | parity SOURCE RELEASE TAILSCALE_BASE"
let ()=
 if Filename.basename Sys.argv.(0) = "release_process.ml" then (
 Sys.set_signal Sys.sigalrm (Sys.Signal_handle(fun _->failwith "overall command deadline"));
 ignore(alarm 240);
 try main() with e->emit "command" "FAIL" ["error",`String(Printexc.to_string e)];exit 1)
