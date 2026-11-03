#use "topfind";;
#require "bos,yojson,cryptokit,unix";;
(* Ordinary pure policy/projection tests only. No watchdog/collector startup,
   live database, provider, task, credential, solver or fault scenario. *)
let root="/home/an/NAS-setup/uos"
(* Run and bind this exact workspace's sources, not the author's sibling. *)
let ws=Sys.getcwd()
let cached=root^"/.uos-workspaces/codex-recovery-observed-20261101/var/harness/integrated-ordinary-3b82e8/lib"
let require b m=if not b then failwith m
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in require(n<=1048576)"source bound";really_input_string c n)
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p b=mkdir(Filename.dirname p);let fd=Unix.openfile p[Unix.O_CREAT;Unix.O_EXCL;Unix.O_WRONLY]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c b;flush c;Unix.fsync fd)
let ()=
 require(Array.length Sys.argv=4&&Sys.argv.(1)="--ordinary")"--ordinary C01..C10 expected-test-count only";
 let cycle=Sys.argv.(2) and expected=int_of_string Sys.argv.(3) in
 let is_cycle=List.mem cycle ["C01";"C02";"C03";"C04";"C05";"C06";"C07";"C08";"C09";"C10"]in
 require(is_cycle||cycle="REPAIR-COSTMODE")"local cycle or separate repair label";
 mkdir(ws^"/var/harness");let base=Filename.temp_file~temp_dir:(ws^"/var/harness")("agent-meta-"^cycle^"-")""in Unix.unlink base;Unix.mkdir base 0o700;
 List.iter(fun p->mkdir(base^"/"^p))["tmp";"lib"];
 Printf.printf"BASE=%s\n%!"base;
 let pins=ref[]and refs=ref[]in
 let capture p=let b=read p in pins:=(p,sha b)::!pins;b in
 let copy a b=write b(capture a)in
 copy(ws^"/tools/validation/agent_meta_policy_fixture.ml")(base^"/driver-source.ml");
 copy(ws^"/docs/design/20261101-0502-uos-four-agent-capability-ontology-intent-spec.md")(base^"/spec-source.md");
 ignore(capture(root^"/tools/ecology_process.ml"));
 (* Cached dependencies remain read-only inputs, not a qualified full closure. *)
 Sys.readdir cached|>Array.to_list|>List.sort compare|>List.iter(fun n->if n<>"uos_swarm"then Unix.symlink(cached^"/"^n)(base^"/lib/"^n));
 let swarm=base^"/swarm"and package=base^"/package"in
 write(swarm^"/gleam.toml")"name = \"uos_swarm\"\nversion = \"0.1.0\"\ntarget = \"erlang\"\n[dependencies]\ngleam_stdlib = \">=0.0.0\"\ngleam_json = \">=0.0.0\"\n";
 copy(ws^"/apps/uos_swarm/src/uos_swarm/symbiosis_preflight.gleam")(swarm^"/src/uos_swarm/symbiosis_preflight.gleam");
 write(package^"/gleam.toml")"name = \"agent_preflight_private\"\nversion = \"0.0.0\"\ntarget = \"erlang\"\n[dependencies]\nuos_swarm = \">=0.0.0\"\ngleam_stdlib = \">=0.0.0\"\ngleam_json = \">=0.0.0\"\ngleeunit = \">=0.0.0\"\n";
 let modules=["harness/agent_capabilities";"harness/agent_preflight_map";"harness/agent_meta_policy";"harness/agent_ecology";"harness/client_profiles"]in
 List.iter(fun p->copy(ws^"/apps/cepaf_gleam/src/cepaf_gleam/"^p^".gleam")(package^"/src/cepaf_gleam/"^p^".gleam"))modules;
 let test_modules=["harness_agent_preflight_map_test";"harness_agent_capabilities_test";"harness_agent_meta_policy_test"] in
 List.iter(fun p->copy(ws^"/apps/cepaf_gleam/test/"^p^".gleam")(package^"/src/"^p^".gleam"))test_modules;
 let env=Astring.String.Map.of_list["PATH",root^"/toolchains/nix-profile/bin:"^root^"/toolchains/opam-ocaml/bin:/usr/bin:/bin";"TMPDIR",base^"/tmp";"ERL_CRASH_DUMP","/dev/null"]in
 let run label executable args=
  let argv=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"30000";"262144";"merged";executable]@args in
  write(base^"/"^label^"-command.json")(Yojson.Basic.to_string(`List(List.map(fun s->`String s)argv)));
  match Bos.OS.Cmd.run_out~env~err:Bos.OS.Cmd.err_run_out(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string~trim:false with
  |Ok(out,(_,`Exited code))->write(base^"/"^label^".log")out;write(base^"/"^label^".exit")(string_of_int code^"\n");
   List.iter(fun suffix->refs:=(base^"/"^label^suffix)::!refs)["-command.json";".log";".exit"];
   Printf.printf"%s exit=%d\n%!"label code;require(code=0)("retained failure "^base);out
  |_->failwith("UNKNOWN retained "^base)in
 let gleam=root^"/toolchains/gleam-1.16.0/bin/gleam"in
 ignore(run"01-policy-compile"gleam["compile-package";"--target";"erlang";"--package";swarm;"--out";base^"/lib/uos_swarm";"--lib";base^"/lib"]);
 ignore(run"02-projection-compile"gleam["compile-package";"--target";"erlang";"--package";package;"--out";base^"/out";"--lib";base^"/lib"]);
 let paths=Sys.readdir(base^"/lib")|>Array.to_list|>List.sort compare|>List.map(fun n->base^"/lib/"^n^"/ebin")|>List.filter Sys.file_exists in
 let actual_modules=List.map(fun p->"cepaf_gleam@"^String.concat"@"(String.split_on_char '/'p))modules@test_modules in
 let loaded=String.concat","(List.map(fun m->Printf.sprintf"%S=code:which('%s')"(base^"/out/ebin/"^m^".beam")m)actual_modules)in
 let eval=loaded^","^Printf.sprintf"%S=code:which('uos_swarm@symbiosis_preflight'),io:format(\"OTP=~s ERTS=~s~n\",[erlang:system_info(otp_release),erlang:system_info(version)]),case eunit:test([harness_agent_preflight_map_test,harness_agent_capabilities_test,harness_agent_meta_policy_test],[verbose]) of ok->halt(0);_->halt(2)end."(base^"/lib/uos_swarm/ebin/uos_swarm@symbiosis_preflight.beam")in
 let output=run"03-ordinary-tests"(root^"/toolchains/nix-profile/bin/erl")(["+S";"2:2";"-noshell"]@List.concat_map(fun p->["-pa";p])paths@["-pa";base^"/out/ebin";"-eval";eval])in
 require(Astring.String.is_infix~affix:(Printf.sprintf"All %d tests passed"expected)output)"ordinary test count";
 List.iter(fun(p,h)->require(sha(read p)=h)("input changed "^p))!pins;
 let file p=`Assoc["path",`String p;"sha256",`String(sha(read p))]in
 let beams=List.map(fun m->file(base^"/out/ebin/"^m^".beam"))actual_modules@[file(base^"/lib/uos_swarm/ebin/uos_swarm@symbiosis_preflight.beam")]in
 let tm=Unix.gmtime(Unix.gettimeofday())in let prefix=Printf.sprintf"%04d%02d%02d-%02d%02d"(tm.tm_year+1900)(tm.tm_mon+1)tm.tm_mday tm.tm_hour tm.tm_sec in
 let receipt=base^"/"^prefix^"-agent-meta-policy-development-receipt.json"in
 write receipt(Yojson.Basic.pretty_to_string(`Assoc["schema",`String"uos.agent-meta-policy-development.v1";"cycle",(if is_cycle then `String cycle else `Null);"post_cycle_repair",(if is_cycle then `Null else `String cycle);"authority",`String"NONE";"production_enabled",`Bool false;
  "source_before_after",`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins);"evidence",`List(List.map file !refs);"beams",`List beams;"ordinary_test_total",`Int expected;"new_meta_tests",`Int(expected-19);"inherited_ontology_preflight_tests",`Int 19;
  "scope",`String"Pure bounded H0-H3 policy DATA with existing ecology integration; exact source snapshot retained per local cycle. No admission, runtime owner, provider, scheduler, cryptographic custody, settlement or process cleanup implementation. Single immutable-state transition is not distributed atomicity.";
  "limits",`List(List.map(fun s->`String s)["This is a pure policy data interpreter, not the live controller, scheduler, admission or budget ledger. Caller must retain the current state; no distributed atomicity or external authentication is established.";"Identity, reviewer custody, capacity, host/boot/VM clocks, ledger and cleanup references are unauthenticated DATA. No passing state authenticates a role, reaps a process, settles cost or permits an effect.";"Freshness/high-water checks apply to supplied clock values on successful returned states only. Missing observations HOLD; no real collector or clock IO is present.";(Printf.sprintf"Only %d ordinary EUnit tests (%d new meta +19 inherited). No provider/credential/canonicaltask/DB/runtime/JJ effects, monitor startup, fault/concurrent/partialcache/adversarial/previouslyflagged tests, formal proof/refinement, fuzz/chaos/soak or performance benchmarks."expected(expected-19));"Minimal fresh policy+five-module cepaf overlay on cached dependencies, not a fresh full app or qualified production closure. Cache symlinks are not read-only mounts; no hermetic toolchain claim."])]));
 Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"receipt(sha(read receipt))
