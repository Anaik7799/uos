#use "topfind";;
#require "bos,yojson,cryptokit";;
#use "tools/recovery_development_capsule.ml";;
(* DEVELOPMENT ONLY. Source-built one-shot FOUR-task recovery composition.
   Usage SOURCE TOOLCHAINS RESOURCE_SOURCE VFS_SOURCE FULL_APP_LIB OLD_PORTFOLIO LAUNCHER
   --ordinary. Existing R/I vectors are public fixtures, not real keys.
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
 let p=Filename.temp_file~temp_dir:directory"uos-recovery-capsule-"""in Unix.unlink p;Unix.mkdir p 0o700;p
let ()=Printf.printf"FIXTURE=%s\n%!"base
let read ?(max=100663296)p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in need(n<=max)"read byte bound";really_input_string c n)
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let mkdir p=match Bos.OS.Dir.create ~mode:0o700 ~path:true(Fpath.v p)with Ok _->()|_->failwith"mkdir"
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
 match Bos.OS.Cmd.run_out ~env(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string ~trim:false with
 |Ok(text,(_,`Exited code))->write(base^"/"^label^".log")text;write(base^"/"^label^".exit")(string_of_int code^"\n");
  runs:=(label,code,sha text)::!runs;Printf.printf"%s exit=%d\n%!"label code;need(code=expected)("failed "^base^"/"^label^".log");text
 |_->failwith("process unknown "^label)

let ()=
 need(Unix.realpath(Sys.getcwd())=root)"run from explicit candidate source root";
 ignore(capture(root^"/tools/recovery_development_capsule.ml"));
 ignore(capture(root^"/tools/validation/recovery_capsule_fixture.ml"));
 List.iter(fun n->ignore(capture(full_lib^"/cepaf_gleam/ebin/"^n^".beam")))
  ["telegram_store_transport_ffi";"cepaf_gleam@harness@native_launch";"cepaf_gleam@harness@recovery_wire";"cepaf_gleam@harness@value";"cepaf_gleam@mcp@json_guard"];
 let sp=root^"/engines/hermes/modules/sa_plan"in
 let native=base^"/native-source"in mkdir(native^"/store");mkdir(native^"/fixture");
 let names=Sys.readdir sp|>Array.to_list|>List.sort String.compare|>List.filter(fun n->(Filename.check_suffix n".ml"||Filename.check_suffix n".mli")&&not(List.mem n["recovery_kernel.ml";"recovery_kernel.mli";"recovery_port.ml";"recovery_owner_journal.ml";"recovery_owner_journal.mli";"recovery_owner_journal_port.ml"]))in
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
   "store/development/test/recovery_adapter_fixture_port.exe";"store/development/recovery_adapter_data_port.exe";"fixture/recovery_fixture_guardian.exe";"fixture/recovery_owner_journal_port.exe";"fixture/recovery_port.exe"]);
 let bin=base^"/native-build/default/fixture"in
 let worker=base^"/native-build/default/store/development/test/recovery_adapter_fixture_port.exe"and guardian=bin^"/recovery_fixture_guardian.exe"and journal=bin^"/recovery_owner_journal_port.exe"in
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
 ["recovery_owner";"recovery_owner_store";"recovery_factual_reply"];
 let test_source=capture(root^"/apps/cepaf_gleam/test/fixtures/recovery_control_actor_test.gleam.inc")in
 let common=match Astring.String.cut ~sep:"// Missing resource/checker guards"test_source with Some(a,_)->a|_->failwith"ordinary common marker"in
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
 need(Astring.String.is_infix~affix:"camlRecovery_adapter_prepare"initialization_helper)"initializer metadata positive control unavailable";
 need(not(Astring.String.is_infix~affix:"camlRecovery_adapter_prepare"data)&&not(Astring.String.is_infix~affix:"fixture-review-key"data))"initializer/fixture seed module linked into data port";
 writej driver(`Assoc["domain",`String"PRIVATE_RECOVERY_CAPSULE_DRIVER";"source_root",`String root;"evidence_root",`String tc;"seed_portfolio",`String seed;
  "evidence_directory",`String(base^"/cases");"vfs_manifest",`String vfs_manifest;
  "worker",`String worker;"guardian",`String guardian;"journal_worker",`String journal;"launcher",`String launcher;"clock_tracking",`String clock]);
 let ebins=Sys.readdir full_lib
|>Array.to_list|>List.sort String.compare|>List.filter_map(fun n->let p=full_lib^"/"^n^"/ebin"in if Sys.file_exists p then Some p else None)in
 let extra=["UOS_CONTROL_DRIVER_LOCATOR",driver;"UOS_CONTROL_LAUNCHER",launcher;"UOS_CONTROL_LAUNCHER_SHA",sha(read launcher);
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
 let cases=Sys.readdir(base^"/cases")|>Array.to_list|>List.sort String.compare|>List.map(fun n->
  let p=base^"/cases/"^n in `Assoc["path",`String p;"sha256",`String(sha(read p))])in
 writej(base^"/receipt.json")(`Assoc["schema",`String"uos.recovery-capsule-development.v1";"mode",`String"ORDINARY_DEVELOPMENT_PATH_ONLY_PRODUCTION_HOLD";
 "authority",`String"NONE";"activation",`Bool false;"source_root",`String root;"resource_dependency",`String resource;"base",`String base;
 "execution_mode",`String"ISOLATED_ORDINARY_OPEN_COMMIT_HISTORY_ONLY";"other_cases",`String"NOT_RUN_CURRENT_RESTRICTION_NO_PROXY_NO_FAULT_PRELOAD_NO_ATTACK_OR_MUTANT_RUNS";
 "development_bundle",`Assoc["expected_identifier",`String capsule_id;"directory",`String bundled;"manifest_sha256",`String(sha(read(bundled^"/development-manifest.json")));"production_release",`Bool false];
 "retained_identifier",`String(base^"/retained-development-bundle-id.json");
 "initializer_helper_outside_bundle",`String helper;
 "data_port_fixture_seed_module_absent",`Bool true;
 "source_before_after",`List refs;"cases",`List cases;"runs",`List(List.rev_map(fun(label,exit,hash)->`Assoc["label",`String label;"exit",`Int exit;"stdout_sha256",`String hash])!runs);
 "native_worker_sha256",`String(sha(read worker));"guardian_sha256",`String(sha(read guardian));"launcher_sha256",`String(sha(read launcher));
 "scope",`String"Actual checker core on synthetic four-task plan executes and CLOSES ALL descriptors BEFORE bound writer. Full snapshot and postgoal revalidated under BEGIN on same borrowed public SQLite handle as task/resource receipt. Signed context binds actual main/WAL/SHM IDs; reviewed writable VFS issues only retained origins. Fixed R/I TEST trust, no production authority. Initial NTP observation only. Private PERSIST_WAL initializer, no keeper escape. Only ONE ordinary integration test was run. No fault, signal, corruption, partial-cache, expiry or concurrent test was run. Actual candidate factual decoder and owner are used without reply-string rewriting. Test-only owner startup extension remains explicit; public start unavailable. Bundle uses packaged owner/decoder/journal/data-port/guardian/finite launcher. Initializer and test signing helper remain outside bundle; no seed/config/locator/DB/WAL/SHM file is copied. Baseline Store initialization functions remain inert library code, with no data-port initializer request. Native interpreter/DSO/BEAM dependency closure external, no operational release artifact. No hostile sameUID/cgroup/powerloss/general incarnation or full native release closure proof. Private initialization NOT production migration.";
 "no_effects",`List(List.map(fun x->`String x)["canonical task/DB";"production runtime";"real keys";"VCS";"production source interfaces"])]);
 print_endline(base^"/receipt.json")
