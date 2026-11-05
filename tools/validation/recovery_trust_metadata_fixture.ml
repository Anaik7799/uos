#use "topfind";;
#require "bos,yojson,cryptokit,unix";;
(* Ordinary private fixture only: no canonical IAM/task DB or key operations.
   Exact production implementation is assembled with a test-only fixed locator.
   The generated worker accepts no DB path from its request or argv. *)
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p s=mkdir(Filename.dirname p);let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect ~finally:(fun()->close_out c)(fun()->output_string c s)
let sha s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let ()=
 if Array.length Sys.argv<>2 then failwith"one fixed workspace argument required";
 let root=Sys.argv.(1)in
 if Filename.basename root<>"codex-trust-discovery-20261101"then failwith"fixed fixture workspace";
 let base=Filename.temp_file"uos-trust-metadata-"""in Unix.unlink base;Unix.mkdir base 0o700;
 let pins=ref[]in
 let capture p=let s=read p in pins:=(p,sha s)::!pins;s in
 let run name executable args=
  write(base^"/"^name^"-command.json")(Yojson.Basic.to_string(`List(List.map(fun x->`String x)(executable::args))));
  match Bos.OS.Cmd.run_out ~err:Bos.OS.Cmd.err_run_out ~env:(Astring.String.Map.of_list["PATH","/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin:/usr/bin:/bin";"OPAM_SWITCH_PREFIX","/home/an/NAS-setup/uos/toolchains/opam-ocaml"])(Bos.Cmd.of_list(executable::args))|>Bos.OS.Cmd.out_string ~trim:false with
  |Ok(out,(_,`Exited n))->write(base^"/"^name^".log")out;Printf.printf"%s exit%d %s\n%!"name n base;n,out
  |_->failwith"unknown fixture process outcome"in
 let src=root^"/native/ocaml/recovery_trust_metadata/"in
 let code=capture(src^"recovery_trust_metadata.ml")in
 ignore(capture(root^"/tools/validation/recovery_trust_metadata_fixture.ml"));
 let prod=base^"/production"in
 write(prod^"/recovery_trust_metadata.ml")code;
 write(prod^"/recovery_trust_metadata.mli")(capture(src^"recovery_trust_metadata.mli"));
 write(prod^"/recovery_trust_metadata_port.ml")(capture(src^"recovery_trust_metadata_port.ml"));
 let append=Printf.sprintf {|
let fixture_anchor () =
 let path=%S in
 let db=Sqlite3.db_open path in
 let sql={sql|CREATE TABLE realms(id TEXT PRIMARY KEY,name TEXT NOT NULL UNIQUE,issuer_url TEXT NOT NULL,gcp_binding TEXT,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL);
CREATE TABLE signing_keys(kid TEXT PRIMARY KEY,realm_id TEXT NOT NULL REFERENCES realms(id),alg TEXT NOT NULL CHECK(alg IN ('RS256','ES256','EdDSA')),public_jwk TEXT NOT NULL,vault_secret_name TEXT NOT NULL,created_at INTEGER NOT NULL,rotated_at INTEGER,retired_at INTEGER);
CREATE TABLE schema_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
INSERT INTO schema_meta VALUES('version','1');
INSERT INTO realms VALUES('private-realm','ordinary-fixture','https://nas-1.tail55d152.ts.net/realms/fixture',NULL,1,1);
INSERT INTO signing_keys VALUES('fixture-kid','private-realm','EdDSA','NOT_QUERIED','iam/signing/eddsa/fixture-kid',1,NULL,NULL);|sql} in
 if Sqlite3.exec db sql<>Sqlite3.Rc.OK then failwith"fixture schema";
 if not(Sqlite3.db_close db)then failwith"fixture close";
 Unix.chmod path 0o600;let st=Unix.stat path in
 {database=path;realm="private-realm";device=st.Unix.st_dev;inode=st.Unix.st_ino}
let ()=
 let a=fixture_anchor()in
 let before=let c=open_in_bin a.database in let s=really_input_string c(in_channel_length c)in close_in c;s in
 let r=observe_bound a in let json=encode r in
 print_endline json;
 let j=Yojson.Basic.from_string json in
 let open Yojson.Basic.Util in
 if member"status"j<>`String"OBSERVED_METADATA_ONLY"then failwith"ordinary configured provider did not observe metadata";
 if member"authority"j<>`String"NONE"||member"trusted_roster"j<>`Bool false then failwith"metadata is not authority";
 let keys=to_list(member"keys"j)in
 if List.length keys<>1||member"kid"(List.hd keys)<>`String"fixture-kid"then failwith"bounded key metadata";
 let after=let c=open_in_bin a.database in let s=really_input_string c(in_channel_length c)in close_in c;s in
 if before<>after then failwith"reader changed main fixture bytes";
 if Sys.file_exists(a.database^"-journal")then failwith"reader created rollback journal";
 print_endline"NATIVE_ORDINARY_METADATA_PASS"
|}(base^"/private-iam.sqlite3")in
 write(base^"/fixture.ml")(code^append);
 let ocamlfind="/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocamlfind"in
 let compile name packages output source=
  let warning_set=if name="04-guardian"then"+a-4-40-42-44-70"else"+a-4-40-42-70"in
  let n,_=run name ocamlfind["ocamlopt";"-w";warning_set;"-warn-error";warning_set;"-package";packages;"-linkpkg";
   "-cc";"/nix/store/w88q44gqd1qg5wmkk7v0h97rpiqvam0l-gcc-wrapper-15.3.0/bin/gcc";
   "-ccopt";"-L/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib";
   "-ccopt";"-Wl,-rpath,/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib";
   "-o";output;source]in if n<>0 then failwith(name^" failed")in
 compile"01-native-compile""core,sqlite3,yojson,unix"(base^"/fixture.exe")(base^"/fixture.ml");
 let n,out=run"02-native-tests"(base^"/fixture.exe")[]in
 if n<>0||not(Astring.String.is_infix ~affix:"NATIVE_ORDINARY_METADATA_PASS"out)then failwith"native fixture failed";
 if not(Astring.String.is_infix ~affix:"\"sqlite_version\":\"3.53.3\""out)then failwith"pinned SQLite mismatch";
 let db=base^"/private-iam.sqlite3"in let st=Unix.stat db in
 let worker=base^"/metadata_worker.exe"and guardian=base^"/metadata_guardian.exe"in
 write(base^"/metadata_worker.ml")(code^Printf.sprintf"\nlet ()=serve_with(fun()->observe_bound{database=%S;realm=\"private-realm\";device=%d;inode=%d})\n"db st.Unix.st_dev st.Unix.st_ino);
 compile"03-native-worker""core,sqlite3,yojson,unix"worker(base^"/metadata_worker.ml");
 write(base^"/metadata_guardian.ml")(capture(root^"/tools/telegram_store_transport_guardian.ml"));
 compile"04-guardian""unix,mtime.clock"guardian(base^"/metadata_guardian.ml");
 List.iter(fun ext->let name="04-production-"^ext in let n,_=run name ocamlfind["ocamlopt";"-package";"core,sqlite3,yojson,unix";"-w";"+a-4-40-42-70";"-warn-error";"+a-4-40-42-70";"-I";prod;"-c";prod^"/recovery_trust_metadata."^ext]in if n<>0 then failwith name)["mli";"ml"];
 let package=base^"/package"in
 write(package^"/gleam.toml")"name = \"trust_metadata_private\"\nversion = \"0.0.0\"\ntarget = \"erlang\"\n[dependencies]\ncepaf_gleam = \">=0.0.0\"\ngleam_stdlib = \">=0.0.0\"\ngleam_json = \">=0.0.0\"\ngleeunit = \">=0.0.0\"\n";
 let cp relative target=write(package^"/src/"^target)(capture(root^"/apps/cepaf_gleam/"^relative))in
 cp"src/cepaf_gleam/harness/telegram_store_transport.gleam""cepaf_gleam/harness/telegram_store_transport.gleam";
 List.iter(fun name->cp("src/cepaf_gleam/mcp/"^name^".gleam")("cepaf_gleam/mcp/"^name^".gleam"))["resources";"principal";"types"];
 let module_code=capture(root^"/apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_trust_discovery.gleam")in
 let extension=capture(root^"/apps/cepaf_gleam/test/fixtures/recovery_trust_discovery_fixture.gleam.inc")in
 write(package^"/src/cepaf_gleam/harness/recovery_trust_discovery.gleam")(module_code^extension);
 cp"test/harness_recovery_trust_discovery_test.gleam""harness_recovery_trust_discovery_test.gleam";
 write(package^"/src/ordinary_metadata_ipc_test.gleam")(Printf.sprintf{|
import cepaf_gleam/harness/recovery_trust_discovery as discovery
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/resources
import cepaf_gleam/mcp/types
import gleam/string
import gleeunit/should
pub fn actual_private_native_metadata_resource_test() {
 let report=discovery.fixture_observe_fixed_launcher(%S,%S,%S,%S)
 let p=principal.from_launcher_env(actor: "ordinary-observer",client:types.ClientProfile("codex"),workspace_root:%S,session_id:"private")
 let entry=discovery.resource(report,p)
 let assert Ok(#(readback,_))=resources.read_resource(resources.registry([entry],[]),resources.empty_cache(),p,discovery.resource_uri)
 let raw=readback.content
 string.contains(raw,"\"status\":\"OBSERVED_METADATA_ONLY\"") |> should.be_true
 string.contains(raw,"\"kid\":\"fixture-kid\"") |> should.be_true
 string.contains(raw,"\"sqlite_version\":\"3.53.3\"") |> should.be_true
 string.contains(raw,"\"custody_reference\":\"iam/signing/eddsa/fixture-kid\"") |> should.be_true
 string.contains(raw,"\"trusted_roster\":false") |> should.be_true
 string.contains(raw,"\"custody_verified\":false") |> should.be_true
 string.contains(raw,"\"purpose_binding\":\"UNKNOWN\"") |> should.be_true
 string.contains(raw,"\"authority\":\"NONE\"") |> should.be_true
}
|}guardian(sha(read guardian))worker(sha(read worker))root);
 let lib="/tmp/uos-unified-app-build-fea562/lib"in
 let n,_=run"05-gleam-compile""/home/an/NAS-setup/uos/toolchains/gleam-1.16.0/bin/gleam"["compile-package";"--target";"erlang";"--package";package;"--out";base^"/out";"--lib";lib]in
 if n<>0 then failwith"Gleam compile failed";
 List.iter(fun name->write(base^"/ffi/"^name^".erl")(capture(root^"/apps/cepaf_gleam/src/"^name^".erl")))["telegram_store_transport_ffi";"telegram_store_codec_ffi"];
 let n,_=run"06-ffi-compile""/home/an/NAS-setup/uos/toolchains/nix-profile/bin/erlc"["-Werror";"-o";base^"/out/ebin";base^"/ffi/telegram_store_transport_ffi.erl";base^"/ffi/telegram_store_codec_ffi.erl"]in
 if n<>0 then failwith"FFI compile failed";
 let ebins=Sys.readdir lib|>Array.to_list|>List.sort String.compare|>List.filter_map(fun n->let p=lib^"/"^n^"/ebin"in if Sys.file_exists p then Some p else None)in
 let eval="io:format(\"DISCOVERY=~p FFI=~p OTP=~p~n\",[code:which('cepaf_gleam@harness@recovery_trust_discovery'),code:which(telegram_store_transport_ffi),erlang:system_info(otp_release)]),case eunit:test([harness_recovery_trust_discovery_test,ordinary_metadata_ipc_test],[verbose])of ok->halt(0);_->halt(2)end."in
 let gn,gout=run"07-gleam-tests""/home/an/NAS-setup/uos/toolchains/nix-profile/bin/erl"(["+S";"2:2";"-noshell";"-pa"]@ebins@["-pa";base^"/out/ebin";"-eval";eval])in
 if gn<>0||not(Astring.String.is_infix ~affix:"All 3 tests passed."gout)then failwith"actual observation tests failed";
 let prodpackage=base^"/production-package"in
 write(prodpackage^"/gleam.toml")(read(package^"/gleam.toml"));
 List.iter(fun relative->write(prodpackage^"/src/"^relative)(read(package^"/src/"^relative)))
 ["cepaf_gleam/harness/telegram_store_transport.gleam";"cepaf_gleam/mcp/resources.gleam";"cepaf_gleam/mcp/principal.gleam";"cepaf_gleam/mcp/types.gleam";"harness_recovery_trust_discovery_test.gleam"];
 write(prodpackage^"/src/cepaf_gleam/harness/recovery_trust_discovery.gleam")module_code;
 let n,_=run"08-production-gleam""/home/an/NAS-setup/uos/toolchains/gleam-1.16.0/bin/gleam"["compile-package";"--target";"erlang";"--package";prodpackage;"--out";base^"/production-out";"--lib";lib]in
 if n<>0 then failwith"production Gleam compile";
 let n,_=run"09-production-public-tests""/home/an/NAS-setup/uos/toolchains/nix-profile/bin/erl"(["+S";"2:2";"-noshell";"-pa"]@ebins@["-pa";base^"/production-out/ebin";"-eval";"case eunit:test(harness_recovery_trust_discovery_test,[verbose])of ok->halt(0);_->halt(2)end."])in
 if n<>0 then failwith"production public observation tests";
 ignore(capture(root^"/native/nifs/rust/ferriskey_nif/src/db.rs"));
 List.iter(fun(p,h)->if sha(read p)<>h then failwith"source changed")!pins;
 write(base^"/observation.json")(Yojson.Basic.pretty_to_string(`Assoc["authority",`String"NONE";"mode",`String"ORDINARY_PRIVATE_METADATA_ONLY";"exit",`Int n;"source",`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins)]));
 let ref_file p=`Assoc["path",`String p;"sha256",`String(sha(read p))]in
 let outputs=Sys.readdir base|>Array.to_list|>List.filter(fun name->Filename.check_suffix name".log"||Filename.check_suffix name"-command.json")|>List.sort String.compare|>List.map(fun name->ref_file(base^"/"^name))in
 let stamp=Unix.gmtime(Unix.gettimeofday())in
 let timestamp=Printf.sprintf"%04d%02d%02d-%02d%02d"(stamp.tm_year+1900)(stamp.tm_mon+1)stamp.tm_mday stamp.tm_hour stamp.tm_min in
 let receipt=base^"/"^timestamp^"-trust-metadata-provider-development-receipt.json"in
 write receipt(Yojson.Basic.pretty_to_string(`Assoc[
 "schema",`String"uos.trust-metadata-provider-development.v1";"authority",`String"NONE";"production_provider",`String"UNCONFIGURED_UNKNOWN";
 "mode",`String"ORDINARY_PRIVATE_FIXTURE_ONLY";"source_before_after",`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins);
 "native_result",`String"ACTUAL_METADATA_OBSERVED_MAIN_BYTES_UNCHANGED_NO_ROLLBACK_JOURNAL";
 "private_eunit_tests",`Int 3;"production_public_eunit_tests",`Int 2;"sqlite_version_observed",`String"3.53.3";
 "logs_and_commands",`List outputs;
 "artifacts",`List(List.map ref_file[worker;guardian;base^"/out/ebin/cepaf_gleam@harness@recovery_trust_discovery.beam";base^"/production-out/ebin/cepaf_gleam@harness@recovery_trust_discovery.beam"]);
 "pinned_sqlite_library",ref_file"/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib/libsqlite3.so.3.53.3";
 "limits",`List(List.map(fun s->`String s)[
 "No real protected IAM locator, issuer roster, key custody, purpose signing, canonical recovery or runtime registry activation is established.";
 "Only realm ID/issuer and active key ID/algorithm/reference/current-or-rotating metadata read. No JWK, key/seed, users, GCP binding or credential table values read. Custody references are PRIVATE metadata.";
 "Source schema version1/required tables and bounded projected field types checked, not exact whole IAM DDL/schema-semantic authentication.";
 "Native locator is a fixed private fixture worker literal plus inode/device. Production API has no locator constructor and observe/serve remain unconfigured. Gleam private extension is excluded from production source.";
 "Caller authentication, integrity of actual launcher/anchor, immutable trusted configuration and role independence remain external unsatisfied production obligations. Metadata does not authenticate itself.";
 "Filesystem checks are cooperative lstat/realpath pre/post, not SQLite FD-origin proof or hostile same-UID ABA protection; readonly SQLite may coordinate WAL/SHM.";
 "SQLite busy timeout100ms and bounded data projection are not total CPU/IO proof; paired guardian bounds process with5s dispatch/cleanup protocol, cooperative process-group premise, no cgroup/powerloss proof.";
 "Native wall clock is an observation, not synchronization/freshness authorization; no roster/grant/custody/purpose or permission is inferred.";
 "Only ordinary tests executed. No fault/preload/signal/swap/interruption/mutant/adversarial/broad suite or production DB effects.";
 "Private native warning44 disabled solely for unchanged existing guardian open Unix; earlier compile failures retained. No official app/release/full-application-build or system-admission claim."
 ])]));
 Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"receipt(sha(read receipt));
 Printf.printf"BASE=%s\n%!"base;
 if n<>0||not(Astring.String.is_infix ~affix:"NATIVE_ORDINARY_METADATA_PASS"out)then exit 2
