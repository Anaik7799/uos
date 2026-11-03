#use "topfind";;
#require "bos,yojson,cryptokit,mtime.clock.os";;
#use "tools/recovery_development_capsule.ml";;
(* DEVELOPMENT ONLY. Source-built one-shot FOUR-task recovery composition.
   Usage SOURCE TOOLCHAINS RESOURCE_SOURCE VFS_SOURCE FULL_APP_LIB OLD_PORTFOLIO LAUNCHER
   --ordinary. Existing R/I vectors exist only in SEPARATE fixture-provider
   processes. Keyless client workers use the reviewed external purpose seam.
   This does not establish managed custody, provider authentication or real keys.
   Every generated writer/adapter is confined to this unique private build.
   The production owner, Store interface and recovery_port are unchanged. *)
let need b why=if not b then failwith why
let ()=need(Array.length Sys.argv=9)"usage SOURCE TOOLCHAINS RESOURCE_SOURCE VFS_SOURCE FULL_APP_LIB OLD_PORTFOLIO LAUNCHER --ordinary"
let root=Unix.realpath Sys.argv.(1)and tc=Unix.realpath Sys.argv.(2)and resource=Unix.realpath Sys.argv.(3)
let vfs=Unix.realpath Sys.argv.(4)
let full_lib=Unix.realpath Sys.argv.(5)and seed=Unix.realpath Sys.argv.(6)and launcher=Unix.realpath Sys.argv.(7)
let red=false
let ()=need(Sys.argv.(8)="--ordinary")"only isolated ordinary mode authorized; broad/fault suites disabled"
(* Unique ignored workspace storage, avoiding the measured shared /tmp quota
   and preserving all previously accepted source/build receipts unchanged. *)
let base=
 let directory=root^"/var/harness"in
 (match Bos.OS.Dir.create~path:true~mode:0o700(Fpath.v directory)with Ok _->()|_->failwith"private build root");
 let p=Filename.temp_file~temp_dir:directory"uos-native-signer-bundle-"""in Unix.unlink p;Unix.mkdir p 0o700;p
let ()=Printf.printf"FIXTURE=%s\n%!"base
let read ?(max=100663296)p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in need(n<=max)"read byte bound";really_input_string c n)
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let mkdir p=match Bos.OS.Dir.create ~mode:0o700 ~path:true(Fpath.v p)with Ok _->()|_->failwith"mkdir"
let ()=mkdir(base^"/compiler-tmp")
let write p b=let c=open_out_bin p in output_string c b;close_out c;Unix.chmod p 0o600
let writej p j=write p(Yojson.Safe.pretty_to_string j^"\n")
let replace a b source=match Astring.String.cut ~sep:a source with
 |Some(x,y)->need(not(Astring.String.is_infix ~affix:a y))"private unique adaptation";x^b^y
 |None->failwith("adaptation missing: "^a)
let pins=ref []
let capture p=let b=read p in pins:=(p,sha b)::!pins;b
let copy p q=write q(capture p)
let env=Astring.String.Map.of_list["PATH",tc^"/toolchains/opam-ocaml/bin:"^tc^"/toolchains/nix-profile/bin:/usr/bin:/bin";
 "OCAMLPATH",tc^"/toolchains/opam-ocaml/lib";"DUNE_CACHE","disabled";"LANG","C.UTF-8";"ERL_CRASH_DUMP","/dev/null";"ERL_FLAGS","+S 4:4 +A 2"]
let runs=ref []
let run ?(expected=0)?(extra=[])label exe args=
 let argv=[tc^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"60000";"1048576";"merged";exe]@args in
 writej(base^"/"^label^"-command.json")(`List(List.map(fun x->`String x)argv));
 let env=List.fold_left(fun e(k,v)->Astring.String.Map.add k v e)env extra in
 (* Build tools alone use private scratch; runtime VM/native finite profiles
    retain their prior explicit environment. No shared/tmp quota workaround
    changes any production policy or invokes a restricted test. *)
 let env=if exe=tc^"/toolchains/opam-ocaml/bin/dune"||exe=tc^"/toolchains/gleam-1.16.0/bin/gleam"
  then Astring.String.Map.add"TMPDIR"(base^"/compiler-tmp")env else env in
 match Bos.OS.Cmd.run_out ~env(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string ~trim:false with
 |Ok(text,(_,`Exited code))->write(base^"/"^label^".log")text;write(base^"/"^label^".exit")(string_of_int code^"\n");
  runs:=(label,code,sha text)::!runs;Printf.printf"%s exit=%d\n%!"label code;need(code=expected)("failed "^base^"/"^label^".log");text
 |_->failwith("process unknown "^label)

let ()=
 need(Unix.realpath(Sys.getcwd())=root)"run from explicit candidate source root";
 ignore(capture(root^"/tools/recovery_development_capsule.ml"));
 ignore(capture(root^"/tools/validation/recovery_native_signer_bundle_fixture.ml"));
 List.iter(fun n->ignore(capture(full_lib^"/cepaf_gleam/ebin/"^n^".beam")))
  ["telegram_store_transport_ffi";"cepaf_gleam@harness@native_launch";"cepaf_gleam@harness@recovery_wire";"cepaf_gleam@harness@value";"cepaf_gleam@mcp@json_guard"];
 let sp=root^"/engines/hermes/modules/sa_plan"in
 let native=base^"/native-source"in mkdir(native^"/store");mkdir(native^"/fixture");

 let signer_dir=native^"/signing"in mkdir signer_dir;
 let signer_source=root^"/native/ocaml/recovery_resource_signer/"in
 List.iter(fun(n,h)->let bytes=capture(signer_source^n)in need(sha bytes=h)"reviewed native-v2 signer drift";write(signer_dir^"/"^n)bytes)
  ["recovery_resource_signer.ml","542dd558f109e3aba0c31abc4599cf71cbeeda8842811ba5009fe628c30b90fd";
   "recovery_resource_signer.mli","c68f96cdfadd037876f1c0ef48909a911e72d258565fa3870f20b4a9107ba6cf";
   "recovery_resource_signer_port.ml","3c4057e4b324738bee61aa6017805d8ce956a1a7d6d4dcd5293d9bf024af8fbf"];
 copy(signer_source^"dune")(signer_dir^"/dune");
 write(signer_dir^"/fixture_native_signer.ml")(read(signer_dir^"/recovery_resource_signer.ml"));
 let provider_fixture=capture(signer_source^"test/recovery_external_provider_fixture.ml.inc")in
 need(sha provider_fixture="13cee29ecaf953cd43df4896c8c74ef045a49ed8e1955e2deee92add658c996a")"reviewed external provider fixture drift";
 write(signer_dir^"/fixture_native_provider.ml")(read(signer_dir^"/recovery_resource_signer.ml")^provider_fixture);
 let channel=open_out_gen[Open_wronly;Open_append]0o600(signer_dir^"/dune")in
 output_string channel"\n(library (name fixture_native_signer) (wrapped false) (modules fixture_native_signer) (libraries recovery_kernel recovery_resource digestif yojson mirage-crypto-ec unix mtime.clock.os))\n(library (name fixture_native_provider) (wrapped false) (modules fixture_native_provider) (libraries recovery_kernel recovery_resource digestif yojson mirage-crypto-ec unix mtime.clock.os))\n";close_out channel;
 let names=Sys.readdir sp
|>Array.to_list|>List.sort String.compare|>List.filter(fun n->(Filename.check_suffix n".ml"||Filename.check_suffix n".mli")&&not(List.mem n["recovery_kernel.ml";"recovery_kernel.mli";"recovery_port.ml";"recovery_owner_journal.ml";"recovery_owner_journal.mli";"recovery_owner_journal_port.ml"]))in
 List.iter(fun n->copy(sp^"/"^n)(native^"/store/"^n))names;
 write(native^"/store/dune")"(library (name sa_plan) (libraries core digestif sqlite3 yojson) (preprocess (pps ppx_jane)))\n";
 let rec tree src dst=mkdir dst;Sys.readdir src|>Array.to_list|>List.sort String.compare|>List.iter(fun n->
  let p=src^"/"^n and q=dst^"/"^n in
  match(Unix.lstat p).Unix.st_kind with Unix.S_DIR->tree p q|Unix.S_REG->copy p q|_->failwith"source type")in
 tree(sp^"/development")(native^"/store/development");
 let dep_manifest=read(sp^"/development/reviewed-dependencies.sha256")in
 String.split_on_char '\n' dep_manifest|>List.filter(fun s->s<>"")|>List.iter(fun line->
  need(String.length line>66&&String.sub line 64 2="  ")"dependency manifest";
  let expected=String.sub line 0 64 and path=String.sub line 66(String.length line-66)in
  need(sha(read(sp^"/development/"^path))=expected)"reviewed dependency copy drift");
 let vfs_manifest=sha dep_manifest in
 let dso="/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib/libsqlite3.so.3.53.3"in
 need(sha(capture dso)="83be5e2629d718bf67b5bd0b545f56fd3438773791bfaf26f0bdbd78e9e5f16b")"SQLite DSO drift";
 List.iter(fun n->copy(sp^"/"^n)(native^"/fixture/"^n))
  ["recovery_kernel.ml";"recovery_kernel.mli";"recovery_owner_journal.ml";"recovery_owner_journal.mli";"recovery_owner_journal_port.ml";"recovery_port.ml"];
 copy(root^"/tools/telegram_store_transport_guardian.ml")(native^"/fixture/recovery_fixture_guardian.ml");
 write(native^"/dune-project")"(lang dune 3.0)\n(name recovery_adapter_private)\n";
 write(native^"/fixture/dune"){d|
(library (name recovery_kernel) (wrapped false) (modules recovery_kernel) (libraries digestif yojson mirage-crypto-ec unix mtime.clock ptime.clock))
(library (name recovery_owner_journal) (wrapped false) (modules recovery_owner_journal) (libraries core digestif yojson sqlite3 unix))
(executable (name recovery_owner_journal_port) (modules recovery_owner_journal_port) (libraries recovery_owner_journal))
(executable (name recovery_fixture_guardian) (modules recovery_fixture_guardian) (libraries unix mtime.clock))
(executable (name recovery_port) (modules recovery_port) (libraries recovery_kernel yojson))
|d};
 ignore(run "01-native-build"(tc^"/toolchains/opam-ocaml/bin/dune")
  ["build";"--root";native;"--build-dir";base^"/native-build";"-j1";
   "store/development/test/recovery_native_fixture_port.exe";"store/development/recovery_adapter_data_port.exe";"fixture/recovery_fixture_guardian.exe";"fixture/recovery_owner_journal_port.exe";"fixture/recovery_port.exe";"signing/recovery_resource_signer_port.exe";"signing/fixture_native_signer.cmxa"]);
 let bin=base^"/native-build/default/fixture"in
 let worker=base^"/native-build/default/store/development/test/recovery_native_fixture_port.exe"and guardian=bin^"/recovery_fixture_guardian.exe"and journal=bin^"/recovery_owner_journal_port.exe"in
 let clock=String.trim
(run "02-clock""/usr/bin/chronyc"["-c";"tracking"])in
 let driver=base^"/driver.json"in
 mkdir(base^"/cases");
 writej driver(`Assoc["domain",`String"PRIVATE_RECOVERY_ADAPTER_DRIVER";"source_root",`String root;"evidence_root",`String tc;"seed_portfolio",`String seed;
 "evidence_directory",`String(base^"/cases");"vfs_manifest",`String vfs_manifest;
 "worker",`String worker;"guardian",`String guardian;"journal_worker",`String journal;"launcher",`String launcher;"clock_tracking",`String clock]);
 let package=base^"/package"in mkdir(package^"/src/cepaf_gleam/harness");
 write(package^"/gleam.toml")"name = \"recovery_control_private\"\nversion = \"0.1.0\"\ntarget = \"erlang\"\n[dependencies]\ncepaf_gleam = \">=0.0.0\"\ngleam_stdlib = \">=0.0.0\"\ngleam_erlang = \">=0.0.0\"\ngleam_otp = \">=0.0.0\"\ngleam_json = \">=0.0.0\"\ngleam_crypto = \">=0.0.0\"\ngleeunit = \">=0.0.0\"\nenvoy = \">=0.0.0\"\nsimplifile = \">=0.0.0\"\n";
 List.iter(fun n->let p=root^"/apps/cepaf_gleam/src/cepaf_gleam/harness/"^n^".gleam"in
  let b=capture p in write(package^"/src/cepaf_gleam/harness/"^n^".gleam")
   (if n="recovery_owner"then b^capture(root^"/apps/cepaf_gleam/test/fixtures/recovery_owner_fixture_extension.gleam.inc")else b))
 ["recovery_owner";"recovery_owner_store";"recovery_factual_reply";"recovery_native_signature_facts"];
 let test_source=capture(root^"/apps/cepaf_gleam/test/fixtures/recovery_control_actor_test.gleam.inc")in
 let common=match Astring.String.cut ~sep:"// Missing resource/checker guards"test_source with Some(a,_)->a|_->failwith"ordinary common marker"in
 let common=replace "fn prepare(ttl) {""fn prepare(_ttl) {"common in
 let common=replace "let data=helper(env(\"UOS_CONTROL_DRIVER_LOCATOR\"),\"prepare\",ttl)""let data=helper(env(\"UOS_NATIVE_SIGNED_CASE\"),\"prepared\",0)"common in
 let ordinary=match Astring.String.cut ~sep:"// ORDINARY_ONLY_BEGIN"test_source with Some(_,b)->
  (match Astring.String.cut ~sep:"// ORDINARY_ONLY_END"b with Some(a,_)->a|_->failwith"ordinary end marker")|_->failwith"ordinary start marker"in
 write(package^"/src/recovery_control_actor_test.gleam")
  (String.concat""(Astring.String.cuts ~sep:"import simplifile\n"common)^ordinary);
 ignore(run "03-gleam-compile"(tc^"/toolchains/gleam-1.16.0/bin/gleam")["compile-package";"--target";"erlang";"--package";package;"--out";base^"/gleam-out";"--lib";full_lib]);

 (* Benign source-catalog compatibility observation: no release is staged or
    activated; only source-list membership is evaluated at actual directories. *)
 let prior=root^"/../codex-finite-launcher-20261031/tools/ecology_release.ml"in
 let current=capture(root^"/tools/ecology_release.ml")and prior_bytes=capture prior in
 let section marker source=let _,s=match Astring.String.cut~sep:marker source with Some x->x|_->failwith"catalog start"in
  let body=match Astring.String.cut~sep:"let source_manifest"s with Some(x,_)->x|_->failwith"catalog end"in marker^body in
 let functions=let _,s=match Astring.String.cut~sep:"let rec files root rel ="prior_bytes with Some x->x|_->failwith"files start"in
  let b=match Astring.String.cut~sep:"let inventory"s with Some(x,_)->x|_->failwith"files end"in "let rec files root rel ="^b in
 let compatibility=base^"/source-catalog-compatibility.ml"in
 write compatibility("open Unix\nlet need b s=if not b then failwith s\nlet deadline()=()\nlet safe_relative p=p<>\"\"&&not(String.contains p '\\000')\n"^functions^
  "\nmodule Old=struct\n"^section"let source_inputs root payload ="prior_bytes^"end\nmodule Current=struct\n"^
  section"let recovery_source_inputs root ="current^"end\n"^{c|
let ()=
 let root=Sys.argv.(1)and old_root=Sys.argv.(2)in
 let baseline=Old.source_inputs root []and added=Current.recovery_source_inputs root in
 let actual=Current.source_inputs root []in
 need(actual=List.sort_uniq String.compare(baseline@added))"existing catalog membership changed";
 need(Current.recovery_source_inputs old_root=[]&&Current.source_inputs old_root[]=Old.source_inputs old_root[])"baseline without adapter changed";
 Printf.printf"SOURCE_CATALOG_COMPATIBLE baseline=%d additions=%d current=%d legacy_root_unchanged=true\n"(List.length baseline)(List.length added)(List.length actual)
|c});
 ignore(run"03a-source-catalog-compatibility"(tc^"/toolchains/opam-ocaml/bin/ocaml")["-I";"+unix";"unix.cma";compatibility;root;Unix.realpath(root^"/../codex-finite-launcher-20261031")]);
 let helper=worker in
 let capsule=match Development_capsule.assemble_data~source_root:root~build_root:(base^"/native-build")~beam_root:(base^"/gleam-out/ebin")~launcher with
 |Ok a->a|Error e->failwith e in
 let capsule_id=Development_capsule.identifier capsule and capsule_dir=Development_capsule.directory capsule in
 writej(base^"/retained-development-bundle-id.json")(`Assoc["schema",`String"uos.development-bundle-retained-data.v1";"expected_identifier",`String capsule_id;"directory",`String capsule_dir;"authority",`String"NONE"]);
 let retained=Yojson.Safe.from_string(read(base^"/retained-development-bundle-id.json"))in
 let expected=Yojson.Safe.Util.(to_string(member"expected_identifier"retained))in
 let capsule=match Development_capsule.verify_data~directory:capsule_dir~expected_identifier:expected with Ok a->a|Error e->failwith e in
 let bundled=Development_capsule.directory capsule in
 let worker=bundled^"/native/recovery_data.exe"and guardian=bundled^"/native/guardian.exe"and journal=bundled^"/native/journal.exe"and launcher=bundled^"/native/finite_launcher.exe"in
 let data=read worker and initialization_helper=read helper in
 need(Astring.String.is_infix~affix:"camlRecovery_native_prepare"initialization_helper)"initializer metadata positive control unavailable";
 need(not(Astring.String.is_infix~affix:"camlRecovery_adapter_prepare"data)&&not(Astring.String.is_infix~affix:"camlRecovery_native_prepare"data)&&not(Astring.String.is_infix~affix:"fixture-review-key"data))"initializer/fixture seed module linked into data port";
 writej driver(`Assoc["domain",`String"PRIVATE_RECOVERY_CAPSULE_DRIVER";"source_root",`String root;"evidence_root",`String tc;"seed_portfolio",`String seed;
  "evidence_directory",`String(base^"/cases");"vfs_manifest",`String vfs_manifest;
  "worker",`String worker;"guardian",`String guardian;"journal_worker",`String journal;"launcher",`String launcher;"clock_tracking",`String clock]);

 let ebins=Sys.readdir full_lib|>Array.to_list|>List.sort String.compare|>List.filter_map(fun n->let p=full_lib^"/"^n^"/ebin"in if Sys.file_exists p then Some p else None)in
 let quote s=Yojson.Safe.to_string(`String s)in
 let binstr s="list_to_binary("^quote s^")"in
 let finite worker argument="{finite_configuration,linux_x8664,native_storage_v1,"^
  String.concat","(List.map binstr[launcher;sha(read launcher);guardian;sha(read guardian);worker;sha(read worker);argument])^"}"in
 let vm eval label=run label(tc^"/toolchains/nix-profile/bin/erl")
  (["+S";"4:4";"-noshell";"-pa"]@ebins@["-pa";base^"/gleam-out/ebin";"-pa";bundled^"/beam";"-eval";eval])in
 let draft_eval="{{ok,Raw},{some,{0,T}}}=telegram_store_transport_ffi:finite_request_with_cleanup("^finite helper driver^",<<\"{\\\"operation\\\":\\\"draft\\\",\\\"value\\\":30000}\">>),true=T>0,io:format(\"DRAFT_RESULT:~s~n\",[Raw]),D=json:decode(Raw),true=maps:is_key(<<\"draft\">>,D),halt(0)."in
 let draft_log=vm draft_eval"03b-actual-finite-unsigned-draft"in
 let line=String.split_on_char '\n'draft_log|>List.find(fun l->String.starts_with~prefix:"DRAFT_RESULT:"l)in
 let draft=Yojson.Safe.from_string(String.sub line 13(String.length line-13))in
 let get k=Yojson.Safe.Util.(to_string(member k draft))in
 writej(base^"/unsigned-draft-reference.json")draft;
 let manifest_path=get"manifest_path"and manifest_sha=get"manifest_sha256"in
 (* Test backend PROCESS owns a single deliberately public vector. The finite
    client workers below have only reviewed purpose+manifest+socket metadata;
    no private key, signer callback or raw message comes from their requests. *)
 let socket_dir=Filename.temp_file ~temp_dir:"/tmp""uos-native-provider-"""in
 Unix.unlink socket_dir;Unix.mkdir socket_dir 0o700;
 let reviewer_socket=socket_dir^"/reviewer.sock"and issuer_socket=socket_dir^"/issuer.sock"in
 List.iter(fun(name,role,vector,path)->write(signer_dir^"/"^name^".ml")(Printf.sprintf{w|
(* TEST-ONLY separate purpose provider; known public vector, not real custody. *)
let ()=
 let key=match Mirage_crypto_ec.Ed25519.priv_of_octets(String.make 32 %C)with Ok k->k|_->failwith"public test vector"in
 Fixture_native_provider.fixture_provider Fixture_native_provider.%s key %S %S %S
|w}vector role path manifest_path manifest_sha))
 ["reviewer_fixture_provider","Reviewer",'R',reviewer_socket;"issuer_fixture_provider","Issuer",'I',issuer_socket];
 let ch=open_out_gen[Open_wronly;Open_append]0o600(signer_dir^"/dune")in
 output_string ch"\n(executable (name reviewer_fixture_provider) (modules reviewer_fixture_provider) (libraries fixture_native_provider))\n(executable (name issuer_fixture_provider) (modules issuer_fixture_provider) (libraries fixture_native_provider))\n";close_out ch;
 ignore(run"03c-separate-public-vector-provider-build"(tc^"/toolchains/opam-ocaml/bin/dune")
  ["build";"--root";native;"--build-dir";base^"/native-build";"-j1";"signing/reviewer_fixture_provider.exe";"signing/issuer_fixture_provider.exe"]);
 let services=ref[]and reaped=ref[]in
 let mono()=Mtime_clock.now_ns()in
 let start name=
  let fd=Unix.openfile(base^"/"^name^".log")[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
  let exe=base^"/native-build/default/signing/"^name^".exe"in
  let null=Unix.openfile"/dev/null"[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
  let pid=Fun.protect~finally:(fun()->Unix.close null;Unix.close fd)(fun()->Unix.create_process exe[|exe|]null fd fd)in
  services:=(name,pid)::!services in
 let rec reap until=
  services:=List.filter(fun(name,pid)->match Unix.waitpid[Unix.WNOHANG]pid with
   |0,_->true
   |_,Unix.WEXITED 0->reaped:=`Assoc["provider",`String name;"pid",`Int pid;"exit",`Int 0]::!reaped;false
   |_->failwith"PROVIDER_NONZERO_OR_SIGNAL_UNKNOWN_NO_RETRY")!services;
  if !services<>[]then(need(mono()<until)"PROVIDER_REAP_UNKNOWN_NO_RETRY";ignore(Unix.select[][][]0.01);reap until)in
 let cleanup()=
  if !services<>[]then(
   List.iter(fun(_,pid)->try Unix.kill pid Sys.sigterm with Unix.Unix_error(Unix.ESRCH,_,_)->())!services;
   let until=Int64.add(mono())2000000000L in
   let rec finish()=
    services:=List.filter(fun(_,pid)->try match Unix.waitpid[Unix.WNOHANG]pid with 0,_->true|_->false with Unix.Unix_error(Unix.ECHILD,_,_)->false)!services;
    if !services<>[]then(need(mono()<until)"PROVIDER_CLEANUP_UNKNOWN_NO_NEW_FLOW";ignore(Unix.select[][][]0.01);finish())in finish())in
 let reviewer=base^"/native-build/default/signing/reviewer_fixture_worker.exe"and issuer=base^"/native-build/default/signing/issuer_fixture_worker.exe"in
 let expected="{expected_data,"^String.concat","(List.map binstr[get"intent_id";manifest_sha;get"request_sha256";get"capability_sha256"])^"}"in
 let collect_eval=lazy("code:ensure_loaded(telegram_store_transport_ffi),erlang:trace_pattern({telegram_store_transport_ffi,finite_request_with_cleanup,2},true,[call_count]),erlang:trace_pattern({telegram_store_transport_ffi,request_config_with_cleanup,2},true,[call_count]),{ok,F}='cepaf_gleam@harness@recovery_native_signature_facts':collect_four("^
  finite reviewer"/NATIVE_SIGNING_NO_CALLER_LOCATOR"^","^finite issuer"/NATIVE_SIGNING_NO_CALLER_LOCATOR"^","^expected^
  "),Facts='cepaf_gleam@harness@recovery_native_signature_facts':facts_json(F),Clean='cepaf_gleam@harness@recovery_native_signature_facts':cleanup_json(F),io:format(\"NATIVE_SIGNATURE_FACTS:~s~nNATIVE_SIGNATURE_CLEANUP:~s~nSIGNER_CLIENT=~p~n\",[Facts,Clean,code:which('cepaf_gleam@harness@recovery_native_signature_facts')]),Body=iolist_to_binary([\"{\\\"operation\\\":\\\"finalize\\\",\\\"facts\\\":\",Facts,\",\\\"value\\\":0}\"]),{{ok,Ready},{some,{0,T}}}=telegram_store_transport_ffi:finite_request_with_cleanup("^
  finite helper(get"draft")^",Body),true=T>0,J=json:decode(Ready),<<\"FOUR_GUARDED_NATIVE_V2_DETACHED_FACTS\">>=maps:get(<<\"signature_source\">>,J),io:format(\"NATIVE_SIGNED_READY:~s~nSIGNING_FINITE=~p SIGNING_LEGACY=~p~n\",[Ready,erlang:trace_info({telegram_store_transport_ffi,finite_request_with_cleanup,2},call_count),erlang:trace_info({telegram_store_transport_ffi,request_config_with_cleanup,2},call_count)]),halt(0).")in
 let signature_log=Fun.protect~finally:cleanup(fun()->
  start"reviewer_fixture_provider";start"issuer_fixture_provider";
  writej(base^"/provider-started.json")(`List(List.map(fun(name,pid)->`Assoc["provider",`String name;"pid",`Int pid])!services));
  let until=Int64.add(mono())5000000000L in
  let rec ready()=if Sys.file_exists reviewer_socket&&Sys.file_exists issuer_socket then()else
   (need(mono()<until)"PROVIDER_READY_UNKNOWN_NO_RETRY";ignore(Unix.select[][][]0.01);ready())in ready();
  List.iter(fun(name,role,path)->let st=Unix.lstat path in
   need(st.Unix.st_kind=Unix.S_SOCK&&st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_perm land 0o077=0)"private socket DATA metadata";
   write(signer_dir^"/"^name^".ml")(Printf.sprintf{w|
(* KEYLESS fixture client: metadata DATA only, not provider authentication. *)
let ()=
 let socket:Fixture_native_signer.socket_anchor={path=%S;device=%d;inode=%d;uid=%d}in
 let provider:Fixture_native_signer.provider={role=Fixture_native_signer.%s;manifest_path=%S;manifest_sha=%S;socket}in
 Fixture_native_signer.serve_with(Fixture_native_signer.sign_bound provider)
|w}path st.Unix.st_dev st.Unix.st_ino st.Unix.st_uid role manifest_path manifest_sha))
   ["reviewer_fixture_worker","Reviewer",reviewer_socket;"issuer_fixture_worker","Issuer",issuer_socket];
  let ch=open_out_gen[Open_wronly;Open_append]0o600(signer_dir^"/dune")in
  output_string ch"\n(executable (name reviewer_fixture_worker) (modules reviewer_fixture_worker) (libraries fixture_native_signer))\n(executable (name issuer_fixture_worker) (modules issuer_fixture_worker) (libraries fixture_native_signer))\n";close_out ch;
  ignore(run"03c-keyless-native-client-build"(tc^"/toolchains/opam-ocaml/bin/dune")
   ["build";"--root";native;"--build-dir";base^"/native-build";"-j1";"signing/reviewer_fixture_worker.exe";"signing/issuer_fixture_worker.exe"]);
  List.iter(fun n->let bytes=read(signer_dir^"/"^n^".ml")in
   need(not(Astring.String.is_infix~affix:"String.make 32"bytes)&&not(Astring.String.is_infix~affix:"fixture_native_provider"bytes))"key/provider linked in finite client")
   ["reviewer_fixture_worker";"issuer_fixture_worker"];
  let log=vm (Lazy.force collect_eval)"03d-four-actual-finite-native-signatures-and-finalize"in
  reap(Int64.add(mono())2000000000L);
  need(List.length !reaped=2)"two provider exits required before owner transaction";
  writej(base^"/provider-reaped.json")(`List(List.rev !reaped));
  List.iter(fun name->need(Astring.String.is_infix~affix:"PROVIDER_TWO_PURPOSE_CALLS_COMPLETED"(read(base^"/"^name^".log")))"provider purpose count")
   ["reviewer_fixture_provider";"issuer_fixture_provider"];
  log)in
 need(Astring.String.is_infix~affix:"SIGNING_FINITE={call_count,5} SIGNING_LEGACY={call_count,0}"signature_log)"actual signing transport counts";
 let line prefix=String.split_on_char '\n'signature_log|>List.find(fun l->String.starts_with~prefix l)|>fun l->String.sub l(String.length prefix)(String.length l-String.length prefix)in
 let facts=Yojson.Safe.from_string(line"NATIVE_SIGNATURE_FACTS:")and cleanup=Yojson.Safe.from_string(line"NATIVE_SIGNATURE_CLEANUP:")in
 need(List.length(Yojson.Safe.Util.to_list facts)=4&&List.length(Yojson.Safe.Util.to_list cleanup)=4)"four exact facts/cleanup";
 writej(base^"/native-signature-facts.json")facts;writej(base^"/native-signature-cleanup.json")cleanup;
 let ready=Yojson.Safe.from_string(line"NATIVE_SIGNED_READY:")in
 writej(base^"/native-signed-ready.json")ready;
 let signed_case=Filename.dirname(get"draft")^"/native-signed-ready.json"in
 need(Yojson.Safe.from_string(read signed_case)=ready)"finalized case byte readback";
 let ebins=Sys.readdir full_lib

|>Array.to_list|>List.sort String.compare|>List.filter_map(fun n->let p=full_lib^"/"^n^"/ebin"in if Sys.file_exists p then Some p else None)in
 let extra=["UOS_NATIVE_SIGNED_CASE",signed_case;"UOS_CONTROL_DRIVER_LOCATOR",driver;"UOS_CONTROL_LAUNCHER",launcher;"UOS_CONTROL_LAUNCHER_SHA",sha(read launcher);
 "UOS_CONTROL_GUARDIAN",guardian;"UOS_CONTROL_GUARDIAN_SHA",sha(read guardian);"UOS_CONTROL_HELPER",helper;"UOS_CONTROL_HELPER_SHA",sha(read helper);
 "UOS_CONTROL_WORKER",worker;"UOS_CONTROL_WORKER_SHA",sha(read worker);"UOS_CONTROL_JOURNAL",journal;"UOS_CONTROL_JOURNAL_SHA",sha(read journal)]in
 let eval="code:ensure_loaded(telegram_store_transport_ffi),erlang:trace_pattern({telegram_store_transport_ffi,finite_request_with_cleanup,2},true,[call_count]),erlang:trace_pattern({telegram_store_transport_ffi,request_config_with_cleanup,2},true,[call_count]),io:format(\"OWNER=~p FFI=~p~n\",[code:which('cepaf_gleam@harness@recovery_owner'),code:which(telegram_store_transport_ffi)]),R=eunit:test({timeout,25,fun recovery_control_actor_test:ordinary_bound_owner_commit_history_test/0},[verbose]),io:format(\"DECODER=~p JOURNAL_CLIENT=~p~n\",[code:which('cepaf_gleam@harness@recovery_factual_reply'),code:which('cepaf_gleam@harness@recovery_owner_store')]),io:format(\"FINITE=~p LEGACY=~p~n\",[erlang:trace_info({telegram_store_transport_ffi,finite_request_with_cleanup,2},call_count),erlang:trace_info({telegram_store_transport_ffi,request_config_with_cleanup,2},call_count)]),case R of ok->halt(0);_->halt(2)end."in
 let log=run ~expected:(if red then 2 else 0)~extra "04-control-e2e"(tc^"/toolchains/nix-profile/bin/erl")
  (["+S";"4:4";"-noshell";"-pa"]@ebins@["-pa";base^"/gleam-out/ebin";"-pa";bundled^"/beam";"-eval";eval])in
 need(Astring.String.is_infix ~affix:"LEGACY={call_count,0}"log)"legacy transport used";
 need(Astring.String.is_infix ~affix:("OWNER=\""^bundled^"/beam/")log)"wrong loaded owner";
 need(Astring.String.is_infix ~affix:("FFI=\""^full_lib^"/cepaf_gleam/ebin/telegram_store_transport_ffi.beam")log)"wrong loaded FFI";
 need(Astring.String.is_infix ~affix:("DECODER=\""^bundled^"/beam/")log)"wrong loaded factual decoder";
 need(Astring.String.is_infix ~affix:("JOURNAL_CLIENT=\""^bundled^"/beam/")log)"wrong loaded journal client";
 need(Astring.String.is_infix ~affix:"Test passed."log)"missing ordinary path result";
 List.iter(fun(p,h)->need(sha(read p)=h)("source drift "^p))!pins;
 let refs=List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins in
 let cases=Sys.readdir(base^"/cases")|>Array.to_list|>List.sort String.compare
  |>List.filter(fun n->(Unix.lstat(base^"/cases/"^n)).Unix.st_kind=Unix.S_REG)|>List.map(fun n->
  let p=base^"/cases/"^n in `Assoc["path",`String p;"sha256",`String(sha(read p))])in
 writej(base^"/receipt.json")(`Assoc["schema",`String"uos.recovery-native-signer-bundle-development.v1";"mode",`String"ORDINARY_DEVELOPMENT_PATH_ONLY_PRODUCTION_HOLD";
 "authority",`String"NONE";"activation",`Bool false;"source_root",`String root;"resource_dependency",`String resource;"base",`String base;
 "execution_mode",`String"ISOLATED_ORDINARY_OPEN_COMMIT_HISTORY_ONLY";"other_cases",`String"NOT_RUN_CURRENT_RESTRICTION_NO_PROXY_NO_FAULT_PRELOAD_NO_ATTACK_OR_MUTANT_RUNS";
 "development_bundle",`Assoc["expected_identifier",`String capsule_id;"directory",`String bundled;"manifest_sha256",`String(sha(read(bundled^"/development-manifest.json")));"production_release",`Bool false];
 "retained_identifier",`String(base^"/retained-development-bundle-id.json");
 "initializer_helper_outside_bundle",`String helper;
 "data_port_fixture_seed_module_absent",`Bool true;
 "native_four_signature_facts",`Assoc["facts",`String(base^"/native-signature-facts.json");"cleanup",`String(base^"/native-signature-cleanup.json");"unsigned_draft",draft;"manifest_sha256",`String manifest_sha;"reviewer_worker_sha256",`String(sha(read reviewer));"issuer_worker_sha256",`String(sha(read issuer));"managed_provider",`String"UNAVAILABLE_SEPARATE_PUBLIC_VECTOR_TEST_PROVIDER_ONLY";"provider_reaped",`String(base^"/provider-reaped.json")];"source_before_after",`List refs;"cases",`List cases;
 "public_source_mirror_roots",`List(Sys.readdir(base^"/cases")|>Array.to_list|>List.sort String.compare|>List.filter_map(fun n->let p=base^"/cases/"^n in if(Unix.lstat p).Unix.st_kind=Unix.S_DIR then Some(`String p)else None));
 "runs",`List(List.rev_map(fun(label,exit,hash)->`Assoc["label",`String label;"exit",`Int exit;"stdout_sha256",`String hash])!runs);
 "native_worker_sha256",`String(sha(read worker));"guardian_sha256",`String(sha(read guardian));"launcher_sha256",`String(sha(read launcher));
 "scope",`String"Actual checker core on synthetic four-task plan executes and CLOSES ALL descriptors BEFORE bound writer. Full snapshot and postgoal revalidated under BEGIN on same borrowed public SQLite handle as task/resource receipt. Signed context binds actual main/WAL/SHM IDs; reviewed writable VFS issues only retained origins. Fixed R/I TEST trust, no production authority. Initial NTP observation only. Private PERSIST_WAL initializer, no keeper escape. Only ONE ordinary integration test was run. No fault, signal, corruption, partial-cache, expiry or concurrent test was run. Actual candidate factual decoder and owner are used without reply-string rewriting. Test-only owner startup extension remains explicit; public start unavailable. Bundle uses packaged owner/decoder/journal/data-port/guardian/finite launcher. Unsigned initializer/finalizer, two KEYLESS finite client workers and two SEPARATE test-provider processes remain outside bundle. Each provider alone holds one public R/I vector, reconstructs the pinned purpose independently and exits after2calls; actual provider exits0 required before owner transaction. All4 signatures use native purpose messages through finite launcher/guardian and external-purpose socket seam, not JWT or helper inline signing. Socket metadata and pinned-key possession do not establish real provider custody/authentication, replay/revocation or current-owner authority. No seed/config/locator/DB/WAL/SHM file is copied into bundle. Baseline Store initialization functions remain inert library code with no data-port initializer request. Native interpreter/DSO/BEAM dependency closure external; no operational release artifact, hostile sameUID/cgroup/powerloss/general incarnation or full release closure proof. Private initialization NOT production migration.";
 "no_effects",`List(List.map(fun x->`String x)["canonical task/DB";"production runtime";"real keys";"VCS";"production source interfaces"])]);
 print_endline(base^"/receipt.json")
