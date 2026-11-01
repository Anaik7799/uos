#use "topfind";;
#require "bos,yojson,cryptokit,unix";;
(* Ordinary bounded read-only verification of the actual pinned Node/worker/SDK.
   No invocation of Node, model SDK, provider, reservation or credential access. *)
let root="/home/an/NAS-setup/uos"
let ws=root^"/.uos-workspaces/codex-pi-review-runtime-pin-20261101"
let node=root^"/toolchains/nix-profile/bin/node"
let sdk="/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js"
let sha_file p=
 let fd=Unix.openfile p[Unix.O_RDONLY]0 in
 Fun.protect~finally:(fun()->Unix.close fd)(fun()->
  let h=Cryptokit.Hash.sha256()and b=Bytes.create 65536 in
  let rec loop()=match Unix.read fd b 0(Bytes.length b)with 0->()|n->h#add_substring b 0 n;loop()in
  loop();Cryptokit.transform_string(Cryptokit.Hexa.encode())h#result)
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p s=let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c s;flush c;Unix.fsync fd)
let refj p=`Assoc["path",`String p;"sha256",`String(sha_file p)]
let owned=["apps/cepaf_gleam/src/pi_review_io.erl";"apps/cepaf_gleam/test/pi_review_runtime_pin_test.erl";"tools/validation/pi_review_runtime_pin_fixture.ml"]
let ()=
 if Array.length Sys.argv<>2||Sys.argv.(1)<>"--ordinary"then failwith"ordinary mode only";
 let before=List.map(fun p->ws^"/"^p,sha_file(ws^"/"^p))owned in
 mkdir(ws^"/var/harness");
 let base=Filename.temp_file~temp_dir:(ws^"/var/harness")"pi-runtime-pin-ordinary-"""in Unix.unlink base;Unix.mkdir base 0o700;
 mkdir(base^"/ebin");mkdir(base^"/tmp");
 Printf.printf"BASE=%s\n%!"base;
 let worker=ws^"/apps/cepaf_gleam/priv/uos_pi_review_once.mjs"in
 let pins=`Assoc["node_sha256",`String(sha_file node);"worker_sha256",`String(sha_file worker);"sdk_sha256",`String(sha_file sdk)]in
 write(base^"/runtime.json")(Yojson.Basic.to_string pins);
 let metadata=`List(List.map(fun p->`Assoc["path",`String p;"size",`Int(Unix.stat p).Unix.st_size;"sha256",`String(sha_file p)])[node;worker;sdk])in
 write(base^"/actual-public-inputs.json")(Yojson.Basic.pretty_to_string metadata^"\n");
 let env=Astring.String.Map.of_list["PATH",root^"/toolchains/opam-ocaml/bin:"^root^"/toolchains/nix-profile/bin:/usr/bin:/bin";"OPAM_SWITCH_PREFIX",root^"/toolchains/opam-ocaml";"OCAMLPATH",root^"/toolchains/opam-ocaml/lib";"ERL_CRASH_DUMP","/dev/null";"ERL_FLAGS","+S 2:2 +A 2";"TMPDIR",base^"/tmp";"UOS_PI_PIN_SOURCE_ROOT",ws;"UOS_PI_PIN_RUNTIME",base^"/runtime.json"]in
 let logs=ref[]in
 let run label exe args=
  let argv=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"60000";"32768";"merged";exe]@args in
  let command=base^"/"^label^"-command.json"in write command(Yojson.Basic.to_string(`List(List.map(fun x->`String x)argv)));
  match Bos.OS.Cmd.run_io~env(Bos.Cmd.of_list argv)Bos.OS.Cmd.in_null|>Bos.OS.Cmd.out_string~trim:false with
  |Ok(out,(_,`Exited n))->let log=base^"/"^label^".log"and status=base^"/"^label^".exit"in write log out;write status(string_of_int n^"\n");logs:=command::log::status::!logs;Printf.printf"%s exit%d\n%!"label n;if n<>0 then failwith("failed retained "^base)
  |_->failwith("UNKNOWN retained "^base)in
 run"01-compile"(root^"/toolchains/nix-profile/bin/erlc")["-Werror";"-o";base^"/ebin";ws^"/apps/cepaf_gleam/src/pi_review_io.erl";ws^"/apps/cepaf_gleam/test/pi_review_runtime_pin_test.erl"];
 let checks=Printf.sprintf"true=(code:which(pi_review_io)=:=%S),true=(code:which(pi_review_runtime_pin_test)=:=%S),case eunit:test(pi_review_runtime_pin_test,[verbose]) of ok->halt(0);_->halt(2)end."(base^"/ebin/pi_review_io.beam")(base^"/ebin/pi_review_runtime_pin_test.beam")in
 run"02-tests"(root^"/toolchains/nix-profile/bin/erl")["+S";"2:2";"-noshell";"-pa";base^"/ebin";"-eval";checks];
 List.iter(fun(p,h)->if sha_file p<>h then failwith("source drift "^p))before;
 let gate_sources=["apps/cepaf_gleam/src/cepaf_gleam/harness/review_completion.gleam";"apps/cepaf_gleam/src/cepaf_gleam/harness/review_dispatch.gleam";"apps/cepaf_gleam/src/cepaf_gleam/harness/operations.gleam";"apps/cepaf_gleam/src/cepaf_gleam/harness/successor_mcp.gleam"]in
 let manifest=String.concat"\n"(List.map(fun(p,h)->h^"  "^String.sub p(String.length ws+1)(String.length p-String.length ws-1))before)^"\n"in
 write(base^"/3-source-manifest.sha256")manifest;
 let j=`Assoc["schema",`String"uos.pi-runtime-pin-ordinary.v1";"author",`String"LOCAL_CODEX_RELAY";"authority",`String"NONE";"admitted",`Bool false;"ordinary_eunit_pass",`Int 4;"source_manifest",refj(base^"/3-source-manifest.sha256");"sources",`List(List.map(fun(p,_)->refj p)before);"actual_public_inputs",metadata;"test_inputs",`List[refj(base^"/runtime.json");refj(base^"/actual-public-inputs.json")];"retained_gate_sources",`List(List.map(fun p->refj(ws^"/"^p))gate_sources);"logs",`List(List.map refj !logs);"artifacts",`List(List.map(fun n->refj(base^"/ebin/"^n))["pi_review_io.beam";"pi_review_runtime_pin_test.beam"]);"compiler",refj(root^"/toolchains/nix-profile/bin/erlc");"runtime",refj(root^"/toolchains/nix-profile/bin/erl");"supervisor_source",refj(root^"/tools/ecology_process.ml");"runtime_node_executed",`Bool false;"provider_or_credentials_used",`Bool false;"production_readiness",`String"SOURCE_CLOSED_UNAVAILABLE";"scope",`String"Read-only fixed runtime pins only; no launch/environment/authorization/cost/cleanup qualification.";"limits",`List(List.map(fun s->`String s)["Node128MiB, worker64KiB, SDK1MiB; 64KiB pread chunks, shared5s monotonic check deadline; filesystem operations/physical scheduling are not preemptible by this loop.";"Trusted stable public source and same-UID filesystem/process premise; metadata and SHA observations do not bind a later exec inode or complete runtime closure.";"Clean environment, actual postcatalog fence, full SDK/runtime closure, current ZDR/price eligibility, real authority/grant and cleanup remain unverified; production gate cannot be cleared by pin result.";"Only Erlang IO module+ordinary test compiled with -Werror; no fresh whole Gleam app build or external inference.";"No flagged fault/concurrent/partial-cache/adversarial/mutant cases. No canonical task/DB/runtime/config/key/JJ writes."])]in
 write(base^"/receipt.json")(Yojson.Basic.pretty_to_string j^"\n");Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"(base^"/receipt.json")(sha_file(base^"/receipt.json"))
