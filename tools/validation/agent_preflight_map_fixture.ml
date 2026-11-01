#use "topfind";;
#require "bos,yojson,cryptokit,unix";;
(* Ordinary pure policy/projection tests only. No watchdog/collector startup,
   live database, provider, task, credential, solver or fault scenario. *)
let root="/home/an/NAS-setup/uos"
let ws=root^"/.uos-workspaces/codex-agent-preflight-ontology-20261101"
let cached=root^"/.uos-workspaces/codex-recovery-observed-20261101/var/harness/integrated-ordinary-3b82e8/lib"
let require b m=if not b then failwith m
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in require(n<=1048576)"source bound";really_input_string c n)
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p b=mkdir(Filename.dirname p);let fd=Unix.openfile p[Unix.O_CREAT;Unix.O_EXCL;Unix.O_WRONLY]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c b;flush c;Unix.fsync fd)
let ()=
 require(Array.length Sys.argv=2&&Sys.argv.(1)="--ordinary")"ordinary only";
 mkdir(ws^"/var/harness");let base=Filename.temp_file~temp_dir:(ws^"/var/harness")"agent-preflight-"""in Unix.unlink base;Unix.mkdir base 0o700;
 List.iter(fun p->mkdir(base^"/"^p))["tmp";"lib"];
 Printf.printf"BASE=%s\n%!"base;
 let pins=ref[]and refs=ref[]in
 let capture p=let b=read p in pins:=(p,sha b)::!pins;b in
 let copy a b=write b(capture a)in
 ignore(capture(ws^"/tools/validation/agent_preflight_map_fixture.ml"));
 ignore(capture(root^"/tools/ecology_process.ml"));
 (* Cached dependencies remain read-only inputs, not a qualified full closure. *)
 Sys.readdir cached|>Array.to_list|>List.sort compare|>List.iter(fun n->if n<>"uos_swarm"then Unix.symlink(cached^"/"^n)(base^"/lib/"^n));
 let swarm=base^"/swarm"and package=base^"/package"in
 write(swarm^"/gleam.toml")"name = \"uos_swarm\"\nversion = \"0.1.0\"\ntarget = \"erlang\"\n[dependencies]\ngleam_stdlib = \">=0.0.0\"\ngleam_json = \">=0.0.0\"\n";
 copy(ws^"/apps/uos_swarm/src/uos_swarm/symbiosis_preflight.gleam")(swarm^"/src/uos_swarm/symbiosis_preflight.gleam");
 write(package^"/gleam.toml")"name = \"agent_preflight_private\"\nversion = \"0.0.0\"\ntarget = \"erlang\"\n[dependencies]\nuos_swarm = \">=0.0.0\"\ngleam_stdlib = \">=0.0.0\"\ngleam_json = \">=0.0.0\"\ngleeunit = \">=0.0.0\"\n";
 let modules=["harness/agent_capabilities";"harness/agent_preflight_map";"harness/agent_ecology";"harness/client_profiles"]in
 List.iter(fun p->copy(ws^"/apps/cepaf_gleam/src/cepaf_gleam/"^p^".gleam")(package^"/src/cepaf_gleam/"^p^".gleam"))modules;
 List.iter(fun p->copy(ws^"/apps/cepaf_gleam/test/"^p^".gleam")(package^"/src/"^p^".gleam"))["harness_agent_preflight_map_test";"harness_agent_capabilities_test"];
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
 let actual_modules=List.map(fun p->"cepaf_gleam@"^String.concat"@"(String.split_on_char '/'p))modules@["harness_agent_preflight_map_test";"harness_agent_capabilities_test"]in
 let loaded=String.concat","(List.map(fun m->Printf.sprintf"%S=code:which('%s')"(base^"/out/ebin/"^m^".beam")m)actual_modules)in
 let eval=loaded^","^Printf.sprintf"%S=code:which('uos_swarm@symbiosis_preflight'),io:format(\"OTP=~s ERTS=~s~n\",[erlang:system_info(otp_release),erlang:system_info(version)]),case eunit:test([harness_agent_preflight_map_test,harness_agent_capabilities_test],[verbose]) of ok->halt(0);_->halt(2)end."(base^"/lib/uos_swarm/ebin/uos_swarm@symbiosis_preflight.beam")in
 let output=run"03-ordinary-tests"(root^"/toolchains/nix-profile/bin/erl")(["+S";"2:2";"-noshell"]@List.concat_map(fun p->["-pa";p])paths@["-pa";base^"/out/ebin";"-eval";eval])in
 require(Astring.String.is_infix~affix:"All 19 tests passed"output)"ordinary test count";
 List.iter(fun(p,h)->require(sha(read p)=h)("input changed "^p))!pins;
 let file p=`Assoc["path",`String p;"sha256",`String(sha(read p))]in
 let beams=List.map(fun m->file(base^"/out/ebin/"^m^".beam"))actual_modules@[file(base^"/lib/uos_swarm/ebin/uos_swarm@symbiosis_preflight.beam")]in
 let tm=Unix.gmtime(Unix.gettimeofday())in let prefix=Printf.sprintf"%04d%02d%02d-%02d%02d"(tm.tm_year+1900)(tm.tm_mon+1)tm.tm_mday tm.tm_hour tm.tm_sec in
 let receipt=base^"/"^prefix^"-agent-preflight-map-development-receipt.json"in
 write receipt(Yojson.Basic.pretty_to_string(`Assoc["schema",`String"uos.agent-preflight-map-development.v1";"authority",`String"NONE";"production_enabled",`Bool false;
  "source_before_after",`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins);"evidence",`List(List.map file !refs);"beams",`List beams;"new_ordinary_tests",`Int 8;"inherited_ontology_tests",`Int 11;
  "scope",`String"Existing pure preflight policy freshlycompiled with3readonlyaccessors, no health/scheduling/record changes. Freshcepafprojection renders actual4agents×8existingclasses×3dimensions, exactState-ownedcallerregistries/lastleafDATA. Both40hexcommitandtaggedSHA256retainedwithunknownlinkage; catalogcompletenessunattested. Existingecologyformatterintegrated. Syntheticordinarypolicyrecordfixtureonly; no monitor/collector startup.";
  "limits",`List(List.map(fun s->`String s)["Registry completeness/collector authenticity/actualruntimeavailability/authority remain unverified. Ready means existing policy DATA, never deployment/task grant.";"Last service observations remain visible after expiry and must not be treated as fresh evidence. Overall coverage freshness uses existingpolicy only.";"Crosswalk is partial/related-concept/crosscutting, not set inclusion or necessary prerequisites; read_file/configuration/proposals do not prove search/writeback/transport or fullKMservice operations.";"Only pureordinary19tests; no model/provider/credential/canonicaltask/DB/runtime/JJ effects, monitor/timer/collector startup, fault/concurrent/partialcache/adversarial/previouslyflagged tests or formalrefinement proof.";"Minimalfreshpolicy+fourmodulecepaf overlay on cachedexternaldeps, notfreshfullapplication or qualifiedproductionclosure. Cache symlinks are not read-only mounts; nohermetictoolchainclaim."])]));
 Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"receipt(sha(read receipt))
