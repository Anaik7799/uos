#use "topfind";;
#require "bos,yojson,cryptokit,unix,mtime.clock.os";;
(* Ordinary signature-only fixture. Never opens a canonical DB, uses no genuine
   key, performs no task/release/config effects, and runs no restricted tests. *)
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p s=mkdir(Filename.dirname p);let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect ~finally:(fun()->close_out c)(fun()->output_string c s)
let sha s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let ()=
 if Array.length Sys.argv<>2||Filename.basename Sys.argv.(1)<>"codex-external-custody-signer-20261101"then failwith"fixed workspace argument";
 let ws=Unix.realpath Sys.argv.(1)and root="/home/an/NAS-setup/uos"in
 let scratch=ws^"/var/harness"in mkdir scratch;
 let base=Filename.temp_file ~temp_dir:scratch "uos-native-resource-signer-"""in Unix.unlink base;Unix.mkdir base 0o700;
 mkdir(base^"/tmp");
 let pins=ref[]in let capture p=let s=read p in pins:=(p,sha s)::!pins;s in
 List.iter(fun p->ignore(capture p))[root^"/toolchains/opam-ocaml/bin/ocaml";root^"/toolchains/opam-ocaml/bin/ocamlopt.opt";root^"/toolchains/opam-ocaml/bin/dune";root^"/toolchains/nix-profile/bin/erl";root^"/tools/ecology_process.ml"];
 let run label exe args=
  let argv=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"60000";"65536";"merged";exe]@args in
  write(base^"/"^label^"-command.json")(Yojson.Basic.to_string(`List(List.map(fun s->`String s)argv)));
  let env=Astring.String.Map.of_list["PATH",root^"/toolchains/opam-ocaml/bin:"^root^"/toolchains/nix-profile/bin:/usr/bin:/bin";"OPAM_SWITCH_PREFIX",root^"/toolchains/opam-ocaml";"DUNE_CACHE","disabled";"TMPDIR",base^"/tmp"]in
  match Bos.OS.Cmd.run_out ~err:Bos.OS.Cmd.err_run_out ~env(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string ~trim:false with
  |Ok(out,(_,`Exited code))->write(base^"/"^label^".log")out;Printf.printf"%s exit%d BASE=%s\n%!"label code base;if code<>0 then failwith(label^" failed");out
  |_->failwith"unknown outcome"in
 let native=base^"/native"and build=base^"/build"in
 write(native^"/dune-project")"(lang dune 3.0)\n(name native_resource_signer_fixture)\n";
 let src=ws^"/native/ocaml/recovery_resource_signer/"and kernel=ws^"/engines/hermes/modules/sa_plan/"in
 List.iter(fun name->write(native^"/"^name)(capture(kernel^name)))["recovery_kernel.ml";"recovery_kernel.mli";"recovery_resource.ml";"recovery_resource.mli"];
 let signer_code=capture(src^"recovery_resource_signer.ml")in
 if Astring.String.is_infix~affix:"key:Mirage_crypto_ec.Ed25519.priv"signer_code
  ||Astring.String.is_infix~affix:"Ed25519.sign"signer_code then failwith"SIGNER_CLIENT_MUST_NOT_HOLD_OR_USE_PRIVATE_KEYS";
 List.iter(fun name->write(native^"/"^name)(capture(src^name)))["recovery_resource_signer.ml";"recovery_resource_signer.mli";"recovery_resource_signer_port.ml"];
 ignore(capture(ws^"/tools/validation/recovery_resource_signer_fixture.ml"));
 write(native^"/fixture_signer.ml")signer_code;
 write(native^"/fixture_provider.ml")(signer_code^capture(src^"test/recovery_external_provider_fixture.ml.inc"));
 write(native^"/fixture_guardian.ml")(capture(root^"/tools/telegram_store_transport_guardian.ml"));
 let preparer={|
module K=Recovery_kernel
module R=Recovery_resource
let ok=function Ok x->x|Error _->failwith"fixture data refused"
let s x=`String x
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let hash p=K.sha256(read p)
let hex b=String.concat""(List.init(String.length b)(fun i->Printf.sprintf"%02x"(Char.code b.[i])))
let public c=let key=ok(Mirage_crypto_ec.Ed25519.priv_of_octets(String.make 32 c))in hex(Mirage_crypto_ec.Ed25519.pub_to_octets(Mirage_crypto_ec.Ed25519.pub_of_priv key))
let write p raw=let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect ~finally:(fun()->close_out c)(fun()->output_string c raw;flush c;Unix.fsync fd)
let ()=
 let base=Sys.argv.(1)and ws=Sys.argv.(2)and guardian=Sys.argv.(3)in
 let now=ok(K.native_clock())in
 let database=base^"/private-resource"and journal=base^"/private-journal"in write database"";write journal"";
 let db=ok(R.open_owned database)and jo=ok(R.open_owned journal)in
 let effect_worker="/tmp/uos-recovery-control-ef8ee5/native-build/default/fixture/recovery_port.exe"and journal_worker="/tmp/uos-recovery-control-ef8ee5/native-build/default/fixture/recovery_owner_journal_port.exe"in
 let launcher="/home/an/NAS-setup/uos/.uos-workspaces/codex-unified-recovery-20261101/var/ecology/native-builds/cas/c1c16abf383dffd8b1834a96bd67563f5728b7be3beb26e4badd27e47647ef86/finite_launcher.exe"in
 let owner="/home/an/NAS-setup/uos/.uos-workspaces/codex-recovery-control-20261101/apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_owner.gleam"in
 let source=ws^"/engines/hermes/modules/sa_plan/recovery_kernel.ml"in
 let signer role seed=`Assoc["subject",s("private-"^role);"session",s("private-"^role^"-session");"kid",s("private-"^role^"-kid");"public_key_hex",s(public seed)]in
 let config=Yojson.Basic.to_string(`Assoc[
 "domain",s"uos.sa-plan.recovery-launcher-data.v1";"profile",s K.profile;"host",s(now.host^".tail55d152.ts.net");"boot",s now.boot;"epoch",s"1";
 "source_sha256",s(hash source);"worker_sha256",s(hash effect_worker);"guardian_sha256",s(hash guardian);"reviewer",signer"reviewer"'R';"issuer",signer"issuer"'I'])in
 ignore(ok(K.configuration_data config));
 let anchor=Yojson.Basic.to_string(`Assoc["domain",s"uos.sa-plan.recovery-resource-anchor-data.v2";"kernel_configuration",s config;
 "database_resource",s"uos/canonical-sa-plan";"database_identity",R.identity_json db;"journal_resource",s"uos/recovery-owner-journal";"journal_identity",R.identity_json jo;
 "owner",s"private-signature-fixture-owner";"generation",s"1";"epoch",s"1";"launcher_sha256",s(hash launcher);"owner_source_sha256",s(hash owner);"journal_worker_sha256",s(hash journal_worker)])in
 R.close db;R.close jo;ignore(ok(R.anchor_data anchor));
 let duration=30000000000L and deadline=Int64.add now.utc_ns 180000000000L in
 let request=Yojson.Basic.to_string(`Assoc["domain",s"uos.sa-plan.reclaim-three.v1";"request_id",s"ordinary-native-signature";"plan",s K.fixed_plan;"snapshot",s(K.sha256"PRIVATE_SYNTHETIC_NO_TASK_DB");
 "old",`List(List.map(fun(task,worker)->`Assoc["task",s task;"worker",s worker;"attempt",`Int 1;"lease",s(Int64.to_string(Int64.sub now.utc_ns 2000000000L))])K.fixed_members);
 "duration",s(Int64.to_string duration);"deadline",s(Int64.to_string deadline)])in
 let cfg=Yojson.Basic.from_string config in let field k=Yojson.Basic.Util.member k cfg in
 let cap=Yojson.Basic.to_string(`Assoc[
 "domain",s"uos.sa-plan.reclaim-three.effect-capability.v1";"profile",s K.profile;"configuration_sha256",s(K.sha256 config);"request_sha256",s(K.sha256 request);
 "evidence_sha256",s(K.sha256"PRIVATE_SIGNING_NOT_CHECKER_EVIDENCE");"context_sha256",s(K.sha256"PRIVATE_SIGNING_CONTEXT");"proposal_sha256",s(K.sha256 request);
 "portfolio_sha256",s(K.sha256"PRIVATE_NO_RISK_PORTFOLIO");"selection_sha256",s(K.sha256"PRIVATE_NO_REAL_SELECTION");"factual_review_sha256",s(K.sha256"PRIVATE_NO_INDEPENDENT_REVIEW");
 "source_sha256",field"source_sha256";"worker_sha256",field"worker_sha256";"guardian_sha256",field"guardian_sha256";
 "reviewer",s"private-reviewer";"reviewer_session",s"private-reviewer-session";"issuer",s"private-issuer";"issuer_session",s"private-issuer-session";
 "host",field"host";"boot",s now.boot;"clock_domain",s now.domain;"epoch",s"1";
 "issued_utc_ns",s(Int64.to_string(Int64.sub now.utc_ns 1000000000L));"expires_utc_ns",s(Int64.to_string(Int64.add now.utc_ns 120000000000L));
 "issued_mono_ns",s(Int64.to_string(Int64.sub now.mono_ns 1000000000L));"expires_mono_ns",s(Int64.to_string(Int64.add now.mono_ns 120000000000L))])in
 let pin p=`Assoc["path",s p;"sha256",s(hash p)]in
 let manifest=Yojson.Basic.to_string(`Assoc["domain",s"uos.recovery.native-signing.launcher-fixture.v2";"intent_id",s"ordinary-native-signature";"kernel_configuration",s config;"resource_anchor",s anchor;"request",s request;"capability",s cap;"database",s database;"journal",s journal;
 "pins",`Assoc["source",pin source;"worker",pin effect_worker;"guardian",pin guardian;"launcher",pin launcher;"owner_source",pin owner;"journal_worker",pin journal_worker]])in
 write(base^"/manifest.json")manifest;
 print_endline(K.sha256 manifest)
|}in
 write(native^"/fixture_prepare.ml")preparer;
 let validator={|
module K=Recovery_kernel
module R=Recovery_resource
let ok=function Ok x->x|Error e->failwith e
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let text j k=Yojson.Basic.Util.(to_string(member k j))
let ()=
 let m=Yojson.Basic.from_string(read Sys.argv.(1))and fs=Yojson.Basic.Util.to_list(Yojson.Basic.from_string(read Sys.argv.(2)))in
 if List.length fs<>4 then failwith"four facts required";
 List.iter(fun f->if text f"status"<>"SIGNATURE_FACT_ONLY"||text f"authority"<>"NONE"||Yojson.Basic.Util.member"admitted"f<>`Bool false then failwith"fact not authority")fs;
 let sig_at i=text(List.nth fs i)"signature_hex"in
 let request_bytes=text m"request"and capability_bytes=text m"capability"in
 let config=ok(K.configuration_data(text m"kernel_configuration"))and anchor=ok(R.anchor_data(text m"resource_anchor"))in
 let fresh=ok(K.verify config ~request_bytes ~capability_bytes ~reviewer_signature:(sig_at 0)~issuer_signature:(sig_at 1))in
 let resource_bytes=ok(R.resource_bytes anchor ~request_bytes ~capability_bytes ~reviewer_signature:(sig_at 0)~issuer_signature:(sig_at 1))in
 List.iteri(fun i f->let expected=List.nth["review_kernel";"issue_kernel";"review_resource";"issue_resource"]i in
  if text f"operation"<>expected||text f"intent_id"<>"ordinary-native-signature"||text f"manifest_sha256"<>K.sha256(read Sys.argv.(1))||text f"request_sha256"<>K.sha256 request_bytes||text f"capability_sha256"<>K.sha256 capability_bytes then failwith"signature fact binding";
  let expected_resource=if i<2 then`Null else`String(K.sha256 resource_bytes)in
  if Yojson.Basic.Util.member"resource_sha256"f<>expected_resource then failwith"resource fact binding")fs;
 let evidence=ok(R.verify anchor ~request_bytes ~capability_bytes ~reviewer_signature:(sig_at 0)~issuer_signature:(sig_at 1)~resource_bytes ~resource_reviewer_signature:(sig_at 2)~resource_issuer_signature:(sig_at 3))in
 let database=ok(R.open_owned(text m"database"))and journal=ok(R.open_owned(text m"journal"))in
 ignore(ok(R.check_effect_boundary evidence ~database ~journal));R.close database;R.close journal;
 if K.authority fresh<>"NONE_UNTIL_INDEPENDENT_LAUNCHER_AND_INGRESS_ADMISSION"then failwith"no grant";
 let req=ok(Recovery_resource_signer.request_of_json"{\"schema\":\"uos.recovery.native-signing.v2\",\"operation\":\"review_kernel\",\"intent_id\":\"ordinary-native-signature\",\"kernel_review\":\"\",\"kernel_issuer\":\"\",\"resource_review\":\"\"}")in
 (match Recovery_resource_signer.sign req with Error"Unavailable"->()|_->failwith"production must be unavailable");
 Printf.printf"FOUR_PURPOSE_NATIVE_SIGNATURES_VERIFIED_PRODUCTION_UNAVAILABLE authority=NONE resource_sha256=%s\n"(K.sha256 resource_bytes)
|}in
 write(native^"/fixture_validate.ml")validator;
 let dune={|
(library (name recovery_kernel) (wrapped false) (modules recovery_kernel recovery_resource) (libraries digestif yojson mirage-crypto-ec unix mtime.clock ptime.clock))
(library (name recovery_resource_signer) (wrapped false) (modules recovery_resource_signer) (libraries recovery_kernel digestif yojson mirage-crypto-ec unix))
(library (name fixture_signer) (wrapped false) (modules fixture_signer) (libraries recovery_kernel digestif yojson mirage-crypto-ec unix))
(library (name fixture_provider) (wrapped false) (modules fixture_provider) (libraries recovery_kernel digestif yojson mirage-crypto-ec unix))
(executable (name recovery_resource_signer_port) (modules recovery_resource_signer_port) (libraries recovery_resource_signer))
(executable (name fixture_prepare) (modules fixture_prepare) (libraries recovery_kernel digestif yojson mirage-crypto-ec unix))
(executable (name fixture_validate) (modules fixture_validate) (libraries recovery_resource_signer recovery_kernel yojson unix))
(executable (name fixture_guardian) (modules fixture_guardian) (libraries unix mtime.clock))
|}in
 write(native^"/dune")dune;
 let dune_exe=root^"/toolchains/opam-ocaml/bin/dune"in
 let build_targets label targets=ignore(run label dune_exe(["build";"--root";native;"--build-dir";build;"-j1"]@targets))in
 build_targets"01-native-build"["fixture_prepare.exe";"fixture_guardian.exe";"fixture_validate.exe";"recovery_resource_signer_port.exe"];
 let bin=build^"/default"in let guardian=bin^"/fixture_guardian.exe"in
 let manifest_sha=String.trim(run"02-fixed-manifest"(bin^"/fixture_prepare.exe")[base;ws;guardian])in
 if String.length manifest_sha<>64 then failwith"manifest digest";
 let socket_directory=Filename.temp_file"uos-custody-"""in Unix.unlink socket_directory;Unix.mkdir socket_directory 0o700;
 let reviewer_socket=socket_directory^"/reviewer.sock"and issuer_socket=socket_directory^"/issuer.sock"in
 List.iter(fun(name,role,vector,path)->write(native^"/"^name^".ml")(Printf.sprintf{|
let ()=
 let key=match Mirage_crypto_ec.Ed25519.priv_of_octets(String.make 32 %C)with Ok k->k|Error _->failwith"public fixture vector"in
 Fixture_provider.fixture_provider Fixture_provider.%s key %S %S %S
|}vector role path(base^"/manifest.json")manifest_sha))["reviewer_provider","Reviewer",'R',reviewer_socket;"issuer_provider","Issuer",'I',issuer_socket];
 let channel=open_out_gen[Open_wronly;Open_append]0o600(native^"/dune")in
 output_string channel"\n(executable (name reviewer_provider) (modules reviewer_provider) (libraries fixture_provider))\n(executable (name issuer_provider) (modules issuer_provider) (libraries fixture_provider))\n";close_out channel;
 build_targets"03-provider-services"["reviewer_provider.exe";"issuer_provider.exe"];
 let services=ref[]in
 let start name=
  let log=base^"/"^name^".log"in
  let fd=Unix.openfile log[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in
  let exe=bin^"/"^name^".exe"in
  let pid=Fun.protect~finally:(fun()->Unix.close fd)(fun()->Unix.create_process exe[|exe|]Unix.stdin fd fd)in
  services:=(name,pid)::!services in
 let mono()=Mtime_clock.now_ns()in
 let rec reap until=
  services:=List.filter(fun(name,pid)->match Unix.waitpid[Unix.WNOHANG]pid with
   |0,_->true|_,Unix.WEXITED 0->Printf.printf"PROVIDER_REAPED=%s exit0\n%!"name;false
   |_->failwith"private provider failed")!services;
  if !services<>[]then(if mono()>=until then failwith"provider cleanup unknown"else(ignore(Unix.select[][][]0.01);reap until))in
 let cleanup()=
  List.iter(fun(_,pid)->try match Unix.waitpid[Unix.WNOHANG]pid with 0,_->Unix.kill pid Sys.sigterm|_->()with Unix.Unix_error(Unix.ECHILD,_,_)->())!services;
  if !services<>[]then(try reap(Int64.add(mono())2000000000L)with _->failwith"PROVIDER_CLEANUP_UNKNOWN_NO_RETRY")in
 let reviewer=bin^"/reviewer_worker.exe"and issuer=bin^"/issuer_worker.exe"in
 let quote s=Yojson.Basic.to_string(`String s)in
 let cfg p="{local_configuration,list_to_binary("^quote guardian^"),list_to_binary("^quote(sha(read guardian))^"),list_to_binary("^quote p^"),list_to_binary("^quote(sha(read p))^"),<<\"/NATIVE_SIGNING_NO_CALLER_LOCATOR\">>}"in
 let eval=lazy("io:format(\"FFI=~p OTP=~p~n\",[code:which(telegram_store_transport_ffi),erlang:system_info(otp_release)]),Call=fun(C,Op,KR,KI,RR)->B=iolist_to_binary([\"{\\\"schema\\\":\\\"uos.recovery.native-signing.v2\\\",\\\"operation\\\":\\\"\",Op,\"\\\",\\\"intent_id\\\":\\\"ordinary-native-signature\\\",\\\"kernel_review\\\":\\\"\",KR,\"\\\",\\\"kernel_issuer\\\":\\\"\",KI,\"\\\",\\\"resource_review\\\":\\\"\",RR,\"\\\"}\"]),{{ok,Reply},{some,{0,T}}}=telegram_store_transport_ffi:request_config_with_cleanup(C,B),true=T>0,M=json:decode(Reply),io:format(\"FACT:~s~n\",[Reply]),<<\"SIGNATURE_FACT_ONLY\">>=maps:get(<<\"status\">>,M),maps:get(<<\"signature_hex\">>,M)end,Review="^cfg reviewer^",Issuer="^cfg issuer^",KR=Call(Review,<<\"review_kernel\">>,<<>>,<<>>,<<>>),KI=Call(Issuer,<<\"issue_kernel\">>,KR,<<>>,<<>>),RR=Call(Review,<<\"review_resource\">>,KR,KI,<<>>),_=Call(Issuer,<<\"issue_resource\">>,KR,KI,RR),halt(0).")in
 let lib="/tmp/uos-unified-app-build-fea562/lib"in
 let ffibeam=lib^"/cepaf_gleam/ebin/telegram_store_transport_ffi.beam"in ignore(capture ffibeam);
 let logs=Fun.protect~finally:cleanup(fun()->
 start"reviewer_provider";start"issuer_provider";
 let until=Int64.add(mono())5000000000L in
 let rec ready()=if Sys.file_exists reviewer_socket&&Sys.file_exists issuer_socket then()else
  if mono()>=until then failwith"provider readiness unknown"else(ignore(Unix.select[][][]0.01);ready())in ready();
 List.iter(fun(name,role,path)->let st=Unix.lstat path in
  write(native^"/"^name^".ml")(Printf.sprintf{|
let ()=
 let socket:Fixture_signer.socket_anchor={path=%S;device=%d;inode=%d;uid=%d}in
 let provider:Fixture_signer.provider={role=Fixture_signer.%s;manifest_path=%S;manifest_sha=%S;socket}in
 Fixture_signer.serve_with(Fixture_signer.sign_bound provider)
|}path st.Unix.st_dev st.Unix.st_ino st.Unix.st_uid role(base^"/manifest.json")manifest_sha))
  ["reviewer_worker","Reviewer",reviewer_socket;"issuer_worker","Issuer",issuer_socket];
 let channel=open_out_gen[Open_wronly;Open_append]0o600(native^"/dune")in
 output_string channel"\n(executable (name reviewer_worker) (modules reviewer_worker) (libraries fixture_signer))\n(executable (name issuer_worker) (modules issuer_worker) (libraries fixture_signer))\n";close_out channel;
 build_targets"03-role-workers"["reviewer_worker.exe";"issuer_worker.exe"];
 List.iter(fun p->let bytes=read p in if Astring.String.is_infix~affix:"String.make 32"bytes||Astring.String.is_infix~affix:"fixture_provider"bytes then failwith"client source linked fixture key provider")
  [native^"/reviewer_worker.ml";native^"/issuer_worker.ml"];
 let logs=run"04-actual-four-guarded-signatures"(root^"/toolchains/nix-profile/bin/erl")["+S";"2:2";"-noshell";"-pa";lib^"/cepaf_gleam/ebin";"-eval";Lazy.force eval]in
 reap(Int64.add(mono())2000000000L);logs)in
 if not(Astring.String.is_infix ~affix:("FFI=\""^ffibeam^"\"")logs)then failwith"actual paired FFI path mismatch";
 let facts=String.split_on_char '\n' logs|>List.filter_map(fun line->if String.starts_with ~prefix:"FACT:"line then Some(Yojson.Basic.from_string(String.sub line 5(String.length line-5)))else None)in
 write(base^"/facts.json")(Yojson.Basic.to_string(`List facts));
 ignore(run"05-unchanged-native-verifiers"(bin^"/fixture_validate.exe")[base^"/manifest.json";base^"/facts.json"]);
 List.iter(fun(p,h)->if sha(read p)<>h then failwith("source drift "^p))!pins;
 let refs=Sys.readdir base|>Array.to_list|>List.filter(fun n->Filename.check_suffix n".log"||Filename.check_suffix n"-command.json"||n="facts.json"||n="manifest.json")|>List.sort String.compare|>List.map(fun n->let p=base^"/"^n in `Assoc["path",`String p;"sha256",`String(sha(read p))])in
 let stamp=Unix.gmtime(Unix.gettimeofday())in let prefix=Printf.sprintf"%04d%02d%02d-%02d%02d"(stamp.tm_year+1900)(stamp.tm_mon+1)stamp.tm_mday stamp.tm_hour stamp.tm_min in
 let receipt=base^"/"^prefix^"-native-resource-signing-development-receipt.json"in
 write receipt(Yojson.Basic.pretty_to_string(`Assoc["schema",`String"uos.native-resource-signing-development.v2";"authority",`String"NONE";"production_provider",`String"Unavailable";"mode",`String"ORDINARY_PRIVATE_SIGNATURE_ONLY";
 "source_before_after",`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins);"evidence",`List refs;"four_exact_purposes_verified",`Bool true;
 "native_artifacts",`List(List.map(fun p->`Assoc["path",`String p;"sha256",`String(sha(read p))])[reviewer;issuer;guardian;bin^"/reviewer_provider.exe";bin^"/issuer_provider.exe";bin^"/recovery_resource_signer_port.exe";bin^"/fixture_validate.exe"]);
 "retained_failures",`List(List.map(fun p->`String p)["/tmp/uos-native-resource-signer-63d372/01-native-build.log";"/tmp/uos-native-resource-signer-7b364a/01-native-build.log";"/tmp/uos-native-resource-signer-959571/03-role-workers.log";ws^"/var/harness/uos-native-resource-signer-520fba/05-unchanged-native-verifiers.log"]);
 "limits",`List(List.map(fun s->`String s)["Fixed public R/I vectors only; no real keys/keygen/export/custody/provider/independent factual review or grant.";"Native kernel v1 inner plus resource v2 outer signatures exactly; no JWT adaptation. All four guarded calls followed by unchanged K.verify/R.verify and private resource identity check.";"Manifest locator+digest compiled into fixture workers by owning driver, not supplied request; actual production protected launcher configuration absent. This does not authenticate organizational custody.";"Only synthetic request/evidence digests, empty private resource files; no real checker/portfolio/task DB or canonical recovery is established.";"Actual existing source/worker/guardian/launcher/owner/journal artifacts hash checked. Single source pin is kernel source, not whole release/toolchain closure. Signed finite-launcher pin is not execution through that launcher.";"Native UTC/Linux MONOTONIC/boot checked; no NTP synchronization proof/current owner high-water/durable signer replay/revocation log or signature-commit atomicity.";"Cooperative private file/manifest topology, no hostile same-UID ABA/FD confinement/cgroup/powerloss proof; scheduling after check remains residual.";"Only ordinary happy-path signing/verification/public-unavailable check executed; restricted/broad/fault/mutation tests UNRUN. No live service/config/task/JJ effects."])]));
 Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"receipt(sha(read receipt))
