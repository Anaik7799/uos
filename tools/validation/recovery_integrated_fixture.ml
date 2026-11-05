#use "topfind";;
#require "bos,cryptokit,yojson,unix";;
(* Ordinary source/application composition only. No production owner, native
   authority, canonical task database, provider or release activation. *)
let root="/home/an/NAS-setup/uos"
let ws=Sys.argv.(1)
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->let n=in_channel_length c in if n>67108864 then failwith "file bound";really_input_string c n)
let sha s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p s=mkdir(Filename.dirname p);let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect ~finally:(fun()->close_out_noerr c)(fun()->output_string c s;flush c;Unix.fsync fd)
let sorted p=Sys.readdir p|>Array.to_list|>List.sort String.compare
let count=ref 0 and total=ref 0
let rec files ?(follow=false) p=
 incr count;if !count>100000 then failwith "inventory count";
 let st=if follow then Unix.stat p else Unix.lstat p in
 match st.Unix.st_kind with
 |Unix.S_DIR->List.concat_map(fun n->files ~follow(p^"/"^n))(sorted p)
 |Unix.S_REG->total:= !total+st.st_size;if !total>1_000_000_000 then failwith "inventory bytes";[p,sha(read p)]
 |_->failwith("unsupported entry "^p)
let locals=["uos_tui";"uos_swarm";"cepaf_gleam"]
let cache=root^"/apps/cepaf_gleam/build/dev/erlang"
let packages=sorted cache|>List.filter(fun n->n<>"gleam_version"&&not(List.mem n locals))
let source_pins()=count:=0;total:=0;List.concat_map(fun a->let base=ws^"/apps/"^a in
 List.concat_map(fun d->files(base^"/"^d))["src";"test"]@
 List.map(fun n->let p=base^"/"^n in p,sha(read p))["gleam.toml";"manifest.toml"])locals
let cache_pins()=count:=0;total:=0;List.concat_map(fun n->List.concat_map(fun sub->let p=cache^"/"^n^"/"^sub in if Sys.file_exists p then files ~follow:true p else[])["ebin";"_gleam_artefacts";"include";"priv"])packages
let jp xs=`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])xs)
let ()=
 if not(Filename.is_relative ws) && Filename.basename ws="codex-recovery-observed-20261101" && Unix.realpath(Sys.getcwd())=Unix.realpath ws then ()else failwith "fixed isolated cwd required";
 mkdir(ws^"/var/harness");let dir=Filename.temp_file ~temp_dir:(ws^"/var/harness")"integrated-ordinary-"""in Unix.unlink dir;Unix.mkdir dir 0o700;
 Printf.printf "BASE=%s\n%!"dir;mkdir(dir^"/compiler-tmp");mkdir(dir^"/lib");
 let before=source_pins()and cached=cache_pins()in
 write(dir^"/source-before.json")(Yojson.Safe.pretty_to_string(jp before));write(dir^"/cache-before.json")(Yojson.Safe.pretty_to_string(jp cached));
 let env=Astring.String.Map.of_list["PATH",root^"/toolchains/nix-profile/bin:"^root^"/toolchains/opam-ocaml/bin:/usr/bin:/bin";"LANG","C.UTF-8";"ERL_FLAGS","+S 4:4 +A 2";"ERL_CRASH_DUMP","/dev/null";"OPAM_SWITCH_PREFIX",root^"/toolchains/opam-ocaml";"OCAMLPATH",root^"/toolchains/opam-ocaml/lib";"DUNE_CACHE","disabled";"TMPDIR",dir^"/compiler-tmp";"UOS_READINESS_FIXTURE_ROOT",dir^"/readiness-root"]in
 let run label cap exe args=
  let argv=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"60000";string_of_int cap;"merged";exe]@args in
  write(dir^"/"^label^"-command.json")(Yojson.Safe.to_string(`List(List.map(fun s->`String s)argv)));
  match Bos.OS.Cmd.run_out ~env ~err:Bos.OS.Cmd.err_run_out(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string ~trim:false with
  |Ok(out,(_,`Exited n))->write(dir^"/"^label^".log")out;write(dir^"/"^label^".exit")(string_of_int n^"\n");Printf.printf "%s exit=%d\n%!"label n;if n<>0 then failwith(label^" failed; no fetch");out
  |_->failwith(label^" unknown")in
 let metadata_sources=List.map(fun n->let p=ws^"/native/ocaml/recovery_trust_metadata/"^n in p,sha(read p))["recovery_trust_metadata.ml";"recovery_trust_metadata.mli";"recovery_trust_metadata_port.ml"]in
 List.iter(fun(p,_)->write(dir^"/metadata-source/"^Filename.basename p)(read p))metadata_sources;
 write(dir^"/metadata-source/dune-project")"(lang dune 3.17)\n";
 write(dir^"/metadata-source/dune")"(library (name recovery_trust_metadata) (wrapped false) (modules recovery_trust_metadata) (libraries core sqlite3 yojson unix))\n(executable (name recovery_trust_metadata_port) (modules recovery_trust_metadata_port) (libraries recovery_trust_metadata))\n";
 ignore(run "00-public-metadata-build"1048576(root^"/toolchains/opam-ocaml/bin/dune")["build";"--root";dir^"/metadata-source";"--build-dir";dir^"/metadata-build";"-j1";"recovery_trust_metadata_port.exe"]);
 List.iter(fun(p,h)->if sha(read p)<>h then failwith "metadata source drift")metadata_sources;
 write(dir^"/metadata-source-pins.json")(Yojson.Safe.pretty_to_string(jp metadata_sources));
 List.iter(fun n->Unix.symlink(cache^"/"^n)(dir^"/lib/"^n))packages;
 List.iter(fun n->ignore(run("01-build-"^n)1048576(root^"/toolchains/gleam-1.16.0/bin/gleam")["compile-package";"--target";"erlang";"--package";ws^"/apps/"^n;"--out";dir^"/lib/"^n;"--lib";dir^"/lib"]))locals;
 let after=source_pins()and cached_after=cache_pins()in if before<>after||cached<>cached_after then failwith "source/cache drift";
 write(dir^"/source-after.json")(Yojson.Safe.pretty_to_string(jp after));write(dir^"/cache-after.json")(Yojson.Safe.pretty_to_string(jp cached_after));
 let fixture_root=dir^"/readiness-root"in
 List.iter(fun n->let p="src/cepaf_gleam/mcp/"^n^".gleam"in write(fixture_root^"/"^p)(read(ws^"/apps/cepaf_gleam/"^p)))["registry";"admission";"receipts";"dispatch";"route_convergence";"server"];
 let ebins=sorted(dir^"/lib")|>List.filter_map(fun n->let p=dir^"/lib/"^n^"/ebin"in if Sys.file_exists p then Some p else None)in
 let eval="code:ensure_loaded(telegram_store_transport_ffi),code:ensure_loaded('cepaf_gleam@harness@recovery_owner'),erlang:trace_pattern({telegram_store_transport_ffi,request_config_with_cleanup,2},true,[call_count]),erlang:trace_pattern({telegram_store_transport_ffi,finite_request_with_cleanup,2},true,[call_count]),erlang:trace_pattern({'cepaf_gleam@harness@recovery_owner',start,1},true,[call_count]),io:format(\"GATEWAY=~p SERVER=~p ADAPTER=~p OWNER=~p SIGNER_CLIENT=~p NATIVE_LAUNCH=~p FFI=~p OTP=~p~n\",[code:which('cepaf_gleam@mcp@runtime_gateway'),code:which('cepaf_gleam@mcp@server'),code:which('cepaf_gleam@mcp@adapters@recovery_control'),code:which('cepaf_gleam@harness@recovery_owner'),code:which('cepaf_gleam@harness@recovery_native_signature_facts'),code:which('cepaf_gleam@harness@native_launch'),code:which(telegram_store_transport_ffi),erlang:system_info(otp_release)]),R=eunit:test([mcp_recovery_control_readiness_test,{\"ordinary registry coverage\",fun mcp_registry_test:listed_tool_has_dispatch_schema_and_owner_test/0}],[verbose]),C=[erlang:trace_info({telegram_store_transport_ffi,request_config_with_cleanup,2},call_count),erlang:trace_info({telegram_store_transport_ffi,finite_request_with_cleanup,2},call_count),erlang:trace_info({'cepaf_gleam@harness@recovery_owner',start,1},call_count)],io:format(\"NATIVE_AND_OWNER_COUNTS=~p~n\",[C]),case {R,C}of{ok,[{call_count,0},{call_count,0},{call_count,0}]}->halt(0);_->halt(2)end."in
 let log=run "02-actual-public-status-list"262144(root^"/toolchains/nix-profile/bin/erl")(["+S";"2:2";"-noshell";"-pa"]@ebins@["-eval";eval])in
 List.iter(fun(name,marker)->if not(Astring.String.is_infix ~affix:(marker^"=\""^dir^"/lib/cepaf_gleam/ebin/"^name^".beam\"")log)then failwith("unexpected loaded path "^name))[
 "cepaf_gleam@mcp@runtime_gateway","GATEWAY";"cepaf_gleam@mcp@server","SERVER";"cepaf_gleam@mcp@adapters@recovery_control","ADAPTER";"cepaf_gleam@harness@recovery_owner","OWNER";"cepaf_gleam@harness@recovery_native_signature_facts","SIGNER_CLIENT";"cepaf_gleam@harness@native_launch","NATIVE_LAUNCH";"telegram_store_transport_ffi","FFI"];
 if not(Astring.String.is_infix ~affix:"All 3 tests passed."log)then failwith "status count";
 let metadata_eval="code:ensure_loaded(telegram_store_transport_ffi),code:ensure_loaded('cepaf_gleam@harness@recovery_owner'),erlang:trace_pattern({telegram_store_transport_ffi,request_config_with_cleanup,2},true,[call_count]),erlang:trace_pattern({telegram_store_transport_ffi,finite_request_with_cleanup,2},true,[call_count]),erlang:trace_pattern({'cepaf_gleam@harness@recovery_owner',start,1},true,[call_count]),io:format(\"GATEWAY=~p ADAPTER=~p DISCOVERY=~p RESOURCES=~p FFI=~p OTP=~p~n\",[code:which('cepaf_gleam@mcp@runtime_gateway'),code:which('cepaf_gleam@mcp@adapters@recovery_control'),code:which('cepaf_gleam@harness@recovery_trust_discovery'),code:which('cepaf_gleam@mcp@resources'),code:which(telegram_store_transport_ffi),erlang:system_info(otp_release)]),R=eunit:test({timeout,15,fun mcp_recovery_metadata_resource_test:ordinary_gateway_private_metadata_unknown_and_status_held_test/0},[verbose]),C=[erlang:trace_info({telegram_store_transport_ffi,request_config_with_cleanup,2},call_count),erlang:trace_info({telegram_store_transport_ffi,finite_request_with_cleanup,2},call_count),erlang:trace_info({'cepaf_gleam@harness@recovery_owner',start,1},call_count)],io:format(\"NATIVE_AND_OWNER_COUNTS=~p~n\",[C]),case{R,C}of{ok,[{call_count,0},{call_count,0},{call_count,0}]}->halt(0);_->halt(2)end."in
 let metadata_log=run "03-actual-private-metadata-resource-status"262144(root^"/toolchains/nix-profile/bin/erl")(["+S";"2:2";"-noshell";"-pa"]@ebins@["-eval";metadata_eval])in
 List.iter(fun(name,marker)->if not(Astring.String.is_infix ~affix:(marker^"=\""^dir^"/lib/cepaf_gleam/ebin/"^name^".beam\"")metadata_log)then failwith("unexpected metadata loaded path "^name))[
 "cepaf_gleam@mcp@runtime_gateway","GATEWAY";"cepaf_gleam@mcp@adapters@recovery_control","ADAPTER";"cepaf_gleam@harness@recovery_trust_discovery","DISCOVERY";"cepaf_gleam@mcp@resources","RESOURCES";"telegram_store_transport_ffi","FFI"];
 let artifacts=List.concat_map(fun n->count:=0;total:=0;files(dir^"/lib/"^n^"/ebin"))locals in
 write(dir^"/all-three-package-artifacts.json")(Yojson.Safe.pretty_to_string(jp artifacts));
 let inputs=source_pins()in if before<>inputs || cached<>cache_pins()then failwith "final input drift";
 let receipt=`Assoc["schema",`String"uos.recovery-observed-application-development.v1";"source_root",`String ws;"private_build",`String dir;"authority",`String"NONE";"activation",`Bool false;"application_admitted",`Bool false;"source_inputs",`Int(List.length before);"cached_dependencies",`Int(List.length cached);"fresh_packages",`List(List.map(fun x->`String x)locals);"all_fresh_package_artifacts",`Int(List.length artifacts);"ordinary_public_gateway_tests",`Int 4;"native_or_owner_start_calls_during_public_status",`Int 0;"native_metadata_worker",`Assoc["path",`String(dir^"/metadata-build/default/recovery_trust_metadata_port.exe");"sha256",`String(sha(read(dir^"/metadata-build/default/recovery_trust_metadata_port.exe")));"execution",`String"COMPILED_NOT_EXECUTED"];"ordinary_native_flow",`String"SEPARATE_NEXT_RUN_NOT_INFERRED_FROM_STATUS";"warnings",`String"Retained build logs; unrelated existing warnings not omitted; no whole-project zero-warning claim";"metadata",`String"Low-level pinned compile-package; no official .app/release closure claim";"source_catalog",`String"Candidate exact sources and cached dependencies separately pinned; MCP candidateID sixcore digest not full release closure";"excluded",`String"Only one ordinary fixture-principal resources/list/read/status and3existing publicstatus/list regressions. ProviderNone returnsUNKNOWN, keys[]/rosterfalse/custodyfalse; no real OIDC auth or privacy-negative proof. All restricted/broad/fault/adversarial/concurrent cases UNRUN; no canonicalDB/task/runtime/key/JJ effects; public status never starts production owner or signing"]in
 write(dir^"/application-receipt.json")(Yojson.Safe.pretty_to_string receipt^"\n");Printf.printf "APPLICATION_RECEIPT=%s\nFRESH_LIB=%s\n%!"(dir^"/application-receipt.json")(dir^"/lib")
