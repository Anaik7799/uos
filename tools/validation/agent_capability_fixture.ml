#use "topfind";;
#require "bos,yojson,cryptokit,unix";;
(* Ordinary pure data/algebra tests, no DB/model/network/worker/task effects. *)
let root="/home/an/NAS-setup/uos"
let ws=root^"/.uos-workspaces/codex-agent-ontology-20261101"
let lib=root^"/.uos-workspaces/codex-recovery-observed-20261101/var/harness/integrated-ordinary-3b82e8/lib"
let need b s=if not b then failwith s
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in need(n<=1048576)"source bound";really_input_string c n)
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p b=mkdir(Filename.dirname p);let fd=Unix.openfile p[Unix.O_CREAT;Unix.O_EXCL;Unix.O_WRONLY]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c b;flush c;Unix.fsync fd)
let ()=
 need(Array.length Sys.argv=2&&Sys.argv.(1)="--ordinary")"ordinary only";
 mkdir(ws^"/var/harness");let base=Filename.temp_file~temp_dir:(ws^"/var/harness")"agent-capabilities-"""in Unix.unlink base;Unix.mkdir base 0o700;mkdir(base^"/tmp");
 Printf.printf"BASE=%s\n%!"base;
 let pins=ref[]and evidence=ref[]in
 let capture p=let b=read p in pins:=(p,sha b)::!pins;b in
 let copy p q=write q(capture p)in
 let sources=["harness/agent_capabilities";"harness/agent_ecology";"harness/client_profiles"]in
 let package=base^"/package"in
 write(package^"/gleam.toml")"name = \"agent_capability_private\"\nversion = \"0.0.0\"\ntarget = \"erlang\"\n[dependencies]\ngleam_stdlib = \">=0.0.0\"\ngleeunit = \">=0.0.0\"\n";
 List.iter(fun p->copy(ws^"/apps/cepaf_gleam/src/cepaf_gleam/"^p^".gleam")(package^"/src/cepaf_gleam/"^p^".gleam"))sources;
 copy(ws^"/apps/cepaf_gleam/test/harness_agent_capabilities_test.gleam")(package^"/src/harness_agent_capabilities_test.gleam");
 ignore(capture(ws^"/tools/validation/agent_capability_fixture.ml"));
 let owners=["apps/cepaf_gleam/src/cepaf_gleam/harness/successor_mcp.gleam";"apps/cepaf_gleam/src/cepaf_gleam/harness/admission.gleam";"apps/cepaf_gleam/src/cepaf_gleam/harness/operations.gleam";"apps/cepaf_gleam/src/cepaf_gleam/harness/client_mcp.gleam";"apps/cepaf_gleam/src/cepaf_gleam/harness/client_profiles.gleam";"apps/cepaf_gleam/src/cepaf_gleam/harness/agy_dispatch.gleam";"apps/uos_swarm/src/uos_swarm/openrouter_worker.gleam";"apps/uos_swarm/src/uos_swarm/token_monitor_native.gleam";"apps/uos_swarm/src/uos_swarm/token_monitor_billing.gleam";"tools/ecology_budget.ml";"tools/ecology_process.ml";"apps/cepaf_gleam/src/cepaf_gleam/harness/agent_ecology.gleam"]in
 let owners=owners@["apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_daemon.gleam";"apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_runtime.gleam";"apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_rpc.gleam";"apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_tools.gleam";"apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_supervisor.gleam";"apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_claude_code.gleam"]in
 List.iter(fun p->ignore(capture(ws^"/"^p)))owners;
 let env=Astring.String.Map.of_list["PATH",root^"/toolchains/nix-profile/bin:"^root^"/toolchains/opam-ocaml/bin:/usr/bin:/bin";"TMPDIR",base^"/tmp";"ERL_CRASH_DUMP","/dev/null"]in
 let run label exe args=
  let argv=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"30000";"262144";"merged";exe]@args in
  write(base^"/"^label^"-command.json")(Yojson.Basic.to_string(`List(List.map(fun s->`String s)argv)));
  match Bos.OS.Cmd.run_out~env~err:Bos.OS.Cmd.err_run_out(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string~trim:false with
  |Ok(out,(_,`Exited n))->write(base^"/"^label^".log")out;write(base^"/"^label^".exit")(string_of_int n^"\n");
   List.iter(fun suffix->evidence:=(base^"/"^label^suffix)::!evidence)["-command.json";".log";".exit"];
   Printf.printf"%s exit=%d\n%!"label n;need(n=0)("failure retained "^base);out
  |_->failwith("UNKNOWN retained "^base)in
 ignore(run"01-compile"(root^"/toolchains/gleam-1.16.0/bin/gleam")["compile-package";"--target";"erlang";"--package";package;"--out";base^"/out";"--lib";lib]);
 let paths=Sys.readdir lib|>Array.to_list|>List.sort compare|>List.map(fun n->lib^"/"^n^"/ebin")|>List.filter Sys.file_exists in
 let eval=Printf.sprintf"%S = code:which('cepaf_gleam@harness@agent_capabilities'), %S = code:which('cepaf_gleam@harness@agent_ecology'), io:format(\"OTP=~s ERTS=~s~n\",[erlang:system_info(otp_release),erlang:system_info(version)]), case eunit:test(harness_agent_capabilities_test,[verbose]) of ok -> halt(0); _ -> halt(2) end."(base^"/out/ebin/cepaf_gleam@harness@agent_capabilities.beam")(base^"/out/ebin/cepaf_gleam@harness@agent_ecology.beam")in
 let out=run"02-ordinary-tests"(root^"/toolchains/nix-profile/bin/erl")(["+S";"2:2";"-noshell"]@List.concat_map(fun p->["-pa";p])paths@["-pa";base^"/out/ebin";"-eval";eval])in
 need(Astring.String.is_infix~affix:"All 11 tests passed"out)"ordinary test marker";
 List.iter(fun(p,h)->need(sha(read p)=h)("source drift "^p))!pins;
 let file p=`Assoc["path",`String p;"sha256",`String(sha(read p))]in
 let beams=Sys.readdir(base^"/out/ebin")|>Array.to_list|>List.filter(fun p->Filename.check_suffix p".beam")|>List.sort compare|>List.map(fun p->file(base^"/out/ebin/"^p))in
 let tm=Unix.gmtime(Unix.gettimeofday())in let prefix=Printf.sprintf"%04d%02d%02d-%02d%02d"(tm.tm_year+1900)(tm.tm_mon+1)tm.tm_mday tm.tm_hour tm.tm_sec in
 let receipt=base^"/"^prefix^"-agent-capability-ontology-development-receipt.json"in
 write receipt(Yojson.Basic.pretty_to_string(`Assoc["schema",`String"uos.agent-capability-ontology-development.v1";"authority",`String"NONE";"production_enabled",`Bool false;
  "source_before_after",`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins);
  "evidence",`List(List.map file !evidence);"beams",`List beams;"ordinary_tests",`Int 11;
  "scope",`String"Existing agent_ecology renders actual typedregistry; fouragents×seven coarsecapability sourcecoordinates, eighteen bounded sourceownerrefs/fourfunctionannotatedcalledges. Runtime/provider/exactmodelrequestedDATA are independent; legacyPibridge/defaults includedwithoutadmissionclaim. Pure requirement union/sequence laws with independent directmembership oracle. Data-only exactcandidate/scope/inference/dualclock checks preserve originalobservation+immutabledeadlines+separatechainlocalcheckedathighwater. Paid singlecompletionprojection retainsliability; everyvalue requires existing admission.";
  "limits",`List(List.map(fun s->`String s)["No complete repository code inventory, currentloadedbackend availability, authenticcollector/clock/IAM, authorityconstructor, deployment or canonicaltask/DB/key/model/network effect.";"Observation validation is callerDATA and highwater onlyalongretainedvaluechain, not global collectorownership. Paidcompletionprojection is not full distributedcontroller/release protocol.";"Seven coarsefamilies omit servicepreflight/function/performance/operationalcoverage, fullKMsearch/transclude/writeback, alltoolmethods and actual four-backend dispatch. KnowledgeRead maps scopedread_file only.";"Ordinary finite pure laws only; no model calls, fault/concurrent/adversarial/flagged tests, solver/runtime refinement or whole-systemformalproof.";"Three source modules compiledagainstcachedexternalBEAMdeps, notwholefreshapp/releaseclosure. New Pi completion candidate in anotherworkspace is notregistered as implementedonthisbaseline."])]));
 Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"receipt(sha(read receipt))
