#use "topfind";;
#require "bos,yojson,cryptokit,unix";;
(* Ordinary local registration only. No fixture signing, credentials or DBs. *)
let root = "/home/an/NAS-setup/uos"
let ws = root ^ "/.uos-workspaces/codex-recovery-metadata-route-20261101"
let lib = "/tmp/uos-unified-app-build-fea562/lib"
let provider_ws = root ^ "/.uos-workspaces/codex-trust-discovery-20261101"
let read p = let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)
  (fun()->really_input_string c(in_channel_length c))
let sha s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s
  |> Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p s=mkdir(Filename.dirname p);let fd=Unix.openfile p
  [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in let c=Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun()->close_out c)(fun()->output_string c s)
let provider_paths = [
 "native/ocaml/recovery_trust_metadata/recovery_trust_metadata.ml", "33dc1663e0bd1f87720f2f3bdc2faf86fae261197001a17cc29b2c257aef299c";
 "native/ocaml/recovery_trust_metadata/recovery_trust_metadata.mli", "382a17864f462d267d18b26eb7aa3db26109bc2df5604c3ae271fdd91b91fe32";
 "native/ocaml/recovery_trust_metadata/recovery_trust_metadata_port.ml", "94ebea4ea25be62f14f51777e46a658de69578e6dd6cc681e1a1a4da45350ef2";
 "apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_trust_discovery.gleam", "b3e3175767e4bd329dacba4d6dd9c993881a84ac61dca74861dd48aca691335d" ]
let affected = [
 "src/cepaf_gleam/mcp/runtime_gateway.gleam";
 "src/cepaf_gleam/mcp/adapters/recovery_control.gleam";
 "src/cepaf_gleam/harness/recovery_owner.gleam";
 "src/cepaf_gleam/harness/recovery_owner_store.gleam";
 "src/cepaf_gleam/harness/recovery_factual_reply.gleam";
 "src/cepaf_gleam/mcp/tools.gleam";
 "src/cepaf_gleam/mcp/registry.gleam";
 "src/cepaf_gleam/mcp/server.gleam";
 "test/mcp_recovery_metadata_resource_test.gleam" ]
let () =
 let red=Array.length Sys.argv=2&&Sys.argv.(1)="--registration-red"in
 if not(red||(Array.length Sys.argv=2&&Sys.argv.(1)="--ordinary"))then
  failwith "only --ordinary or ordinary baseline --registration-red";
 mkdir(ws^"/var/harness");
 let base=Filename.temp_file ~temp_dir:(ws^"/var/harness")"metadata-route-ordinary-"""in
 Unix.unlink base;Unix.mkdir base 0o700;mkdir(base^"/tmp");
 Printf.printf "BASE=%s\n%!"base;
 let pins=ref[]in
 let capture p=let s=read p in pins:=(p,sha s)::!pins;s in
 let env=Astring.String.Map.of_list[
  "PATH",root^"/toolchains/nix-profile/bin:"^root^"/toolchains/opam-ocaml/bin:/usr/bin:/bin";
  "OPAM_SWITCH_PREFIX",root^"/toolchains/opam-ocaml";"TMPDIR",base^"/tmp";
  "UOS_READINESS_FIXTURE_ROOT",base^"/workspace"]in
 let refs=ref[]in
 let run label exe args=
  let argv=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";
   root^"/tools/ecology_process.ml";"60000";"262144";"merged";exe]@args in
  let command=base^"/"^label^"-command.json"in
  write command(Yojson.Basic.to_string(`List(List.map(fun s->`String s)argv)));
  match Bos.OS.Cmd.run_out ~env ~err:Bos.OS.Cmd.err_run_out(Bos.Cmd.of_list argv)
   |>Bos.OS.Cmd.out_string ~trim:false with
  |Ok(out,(_,`Exited n))->
    let log=base^"/"^label^".log"and status=base^"/"^label^".exit"in
    write log out;write status(string_of_int n^"\n");refs:=command::log::status::!refs;
    Printf.printf "%s exit%d\n%!"label n;if n<>0 then failwith(label^" failed; retained at "^base);out
  |_->failwith("unknown outcome retained at "^base)in
 let package=base^"/package"in
 write(package^"/gleam.toml")
  "name = \"recovery_metadata_route_private\"\nversion = \"0.0.0\"\ntarget = \"erlang\"\n[dependencies]\ncepaf_gleam = \">=0.0.0\"\ngleam_stdlib = \">=0.0.0\"\ngleam_json = \">=0.0.0\"\ngleam_otp = \">=0.0.0\"\ngleam_erlang = \">=0.0.0\"\ngleeunit = \">=0.0.0\"\nenvoy = \">=0.0.0\"\nsimplifile = \">=0.0.0\"\n";
 List.iter(fun rel->let target=if String.starts_with ~prefix:"src/"rel then rel
  else"src/"^Filename.basename rel in write(package^"/"^target)
  (capture(ws^"/apps/cepaf_gleam/"^rel)))affected;
 if not red then(
  List.iter(fun(rel,expected)->
   let original=capture(provider_ws^"/"^rel)and imported=capture(ws^"/"^rel)in
   if sha original<>expected||sha imported<>expected then failwith("reviewed provider pin "^rel))provider_paths;
  write(package^"/src/cepaf_gleam/harness/recovery_trust_discovery.gleam")
   (read(ws^"/apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_trust_discovery.gleam"));
  let native=base^"/native"in
  write(native^"/dune-project")"(lang dune 3.17)\n";
  List.iter(fun name->write(native^"/"^name)
   (read(ws^"/native/ocaml/recovery_trust_metadata/"^name)))
   ["recovery_trust_metadata.ml";"recovery_trust_metadata.mli";"recovery_trust_metadata_port.ml"];
  write(native^"/dune")"(library (name recovery_trust_metadata) (wrapped false) (modules recovery_trust_metadata) (libraries core sqlite3 yojson unix))\n(executable (name recovery_trust_metadata_port) (modules recovery_trust_metadata_port) (libraries recovery_trust_metadata))\n";
  ignore(run"01-public-native-build"(root^"/toolchains/opam-ocaml/bin/dune")
   ["build";"--root";native;"--build-dir";base^"/native-build";"-j1";"recovery_trust_metadata_port.exe"]));
 List.iter(fun name->let p="src/cepaf_gleam/mcp/"^name^".gleam"in
  write(base^"/workspace/"^p)(capture(ws^"/apps/cepaf_gleam/"^p)))
  ["registry";"admission";"receipts";"dispatch";"route_convergence";"server"];
 List.iter(fun p->ignore(capture p))[
  ws^"/tools/validation/recovery_metadata_route_fixture.ml";root^"/tools/ecology_process.ml";
  root^"/toolchains/gleam-1.16.0/bin/gleam";root^"/toolchains/opam-ocaml/bin/dune";
  root^"/toolchains/nix-profile/bin/erl";
  ws^"/apps/cepaf_gleam/src/cepaf_gleam/mcp/resources.gleam";
  lib^"/cepaf_gleam/ebin/cepaf_gleam@mcp@resources.beam";
  lib^"/cepaf_gleam/ebin/telegram_store_transport_ffi.beam";
  lib^"/cepaf_gleam/ebin/mcp_stdio_ffi.beam"];
 ignore(run"02-compile"(root^"/toolchains/gleam-1.16.0/bin/gleam")
  ["compile-package";"--target";"erlang";"--package";package;"--out";base^"/out";"--lib";lib]);
 let ebins=Sys.readdir lib|>Array.to_list|>List.sort String.compare
  |>List.filter_map(fun n->let p=lib^"/"^n^"/ebin"in if Sys.file_exists p then Some p else None)in
 let eval="code:ensure_loaded(telegram_store_transport_ffi),code:ensure_loaded('cepaf_gleam@harness@recovery_owner'),erlang:trace_pattern({telegram_store_transport_ffi,request_config_with_cleanup,2},true,[call_count]),erlang:trace_pattern({telegram_store_transport_ffi,finite_request_with_cleanup,2},true,[call_count]),erlang:trace_pattern({'cepaf_gleam@harness@recovery_owner',start,1},true,[call_count]),io:format(\"GATEWAY=~p ADAPTER=~p OTP=~p~n\",[code:which('cepaf_gleam@mcp@runtime_gateway'),code:which('cepaf_gleam@mcp@adapters@recovery_control'),erlang:system_info(otp_release)]),R=eunit:test({timeout,15,fun mcp_recovery_metadata_resource_test:ordinary_gateway_private_metadata_unknown_and_status_held_test/0},[verbose]),C=[erlang:trace_info({telegram_store_transport_ffi,request_config_with_cleanup,2},call_count),erlang:trace_info({telegram_store_transport_ffi,finite_request_with_cleanup,2},call_count),erlang:trace_info({'cepaf_gleam@harness@recovery_owner',start,1},call_count)],io:format(\"NATIVE_AND_OWNER_COUNTS=~p~n\",[C]),case {R,C}of{ok,[{call_count,0},{call_count,0},{call_count,0}]}->halt(0);_->halt(2)end."in
 let log=run"03-ordinary-gateway-resource"(root^"/toolchains/nix-profile/bin/erl")
  (["+S";"2:2";"-noshell";"-pa"]@ebins@["-pa";base^"/out/ebin";"-eval";eval])in
 List.iter(fun(module_name,marker)->
  if not(Astring.String.is_infix ~affix:(marker^"=\""^base^"/out/ebin/"^module_name^".beam\"")log)
  then failwith("wrong loaded module "^module_name))
  ["cepaf_gleam@mcp@runtime_gateway","GATEWAY";"cepaf_gleam@mcp@adapters@recovery_control","ADAPTER"];
 List.iter(fun(p,h)->if sha(read p)<>h then failwith("source drift "^p))!pins;
 let ref_file p=`Assoc["path",`String p;"sha256",`String(sha(read p))]in
 let time=Unix.gmtime(Unix.gettimeofday())in
 let prefix=Printf.sprintf"%04d%02d%02d-%02d%02d"(time.tm_year+1900)(time.tm_mon+1)time.tm_mday time.tm_hour time.tm_sec in
 let receipt=base^"/"^prefix^"-metadata-resource-route-development-receipt.json"in
 write receipt(Yojson.Basic.pretty_to_string(`Assoc[
  "schema",`String"uos.recovery-metadata-resource-route-development.v1";
  "authority",`String"NONE";"production_enabled",`Bool false;
  "source_before_after",`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins);
  "evidence",`List(List.map ref_file !refs);
  "artifacts",`List(List.map(fun name->ref_file(base^"/out/ebin/"^name^".beam"))
   ["cepaf_gleam@mcp@runtime_gateway";"cepaf_gleam@mcp@adapters@recovery_control";"cepaf_gleam@harness@recovery_trust_discovery"]);
  "provider_source_receipt",ref_file("/tmp/uos-trust-metadata-5119f2/20261101-0340-trust-metadata-provider-development-receipt.json");
  "ordinary_tests_passed",`Int 1;"traced_native_and_owner_start_calls",`Int 0;
  "limits",`List(List.map(fun s->`String s)[
   "Actual local public gateway actor resources/list, resources/read and recovery_control_status with a fixture launcher principal, not live HTTP/OIDC authentication.";
   "Exact reviewed provider native3 and Gleam source; production provider None, UNKNOWN without I/O. Public native module compiled only, not executed; no private SQLite fixture or keys.";
   "Per-request principal-private registry entry, no metadata content retained in shared registry/cache. Status HELD, no mutation/signing/trusted-roster inference.";
   "Zero counts cover only paired legacy/finite transport functions and recovery_owner.start, not every FFI. Native source never selects JWK/seed/credential columns; key IDs and custody references are private metadata, not key bytes.";
   "Existing resources BEAM and FFI dependencies pinned; fresh gateway/adapter/discovery modules, not full app/release closure. Six-core candidate identity is a projection, not admission.";
   "Only one ordinary integration test. No fault, adversarial, signals, swaps, mutations, broad suites, canonical DB/tasks/config/runtime/keys/JJ effects."])]));
 Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"receipt(sha(read receipt))
