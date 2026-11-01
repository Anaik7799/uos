#use "topfind";;
#require "bos,yojson,cryptokit";;
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
let base=Filename.temp_file ~temp_dir:"/tmp""uos-recovery-control-"""
let ()=Unix.unlink base;Unix.mkdir base 0o700;Printf.printf"FIXTURE=%s\n%!"base
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
 ignore(capture(root^"/tools/validation/recovery_control_fixture.ml"));
 List.iter(fun n->ignore(capture(full_lib^"/cepaf_gleam/ebin/"^n^".beam")))
  ["telegram_store_transport_ffi";"cepaf_gleam@harness@native_launch";"cepaf_gleam@harness@recovery_wire";"cepaf_gleam@harness@value";"cepaf_gleam@mcp@json_guard"];
 let rr="/engines/hermes/modules/sa_plan/recovery_resource"in
 need(sha(read(resource^rr^".ml"))="a3d6278e5882822201ee0fd4f4c1a60100b56158b0da9afb952bfa1569e8618f")"reviewed resource source drift";
 need(sha(read(resource^rr^".mli"))="c90181b027c131fb0e286c57fda44ab9229a9207645ffd8243550d583c64d602")"reviewed resource interface drift";
 let native=base^"/native-source"in mkdir(native^"/store");mkdir(native^"/checker");mkdir(native^"/fixture");
 let vfs_receipt="/tmp/20261101-0251-sqlite-first-opener-ordinary-development-receipt.json"in
 let vr=capture vfs_receipt in need(sha vr="c1e715021b7e4f3f7262cd4c737ce53cc47fd7e5b89a811f2d4e8abda13e4c61")"reviewed ordinary VFS receipt drift";
 let vj=Yojson.Safe.from_string vr in
 let declared=Yojson.Safe.Util.(to_list(member"source_pins"vj)@to_list(member"dependencies"vj))in
 let vfs_inputs=List.map(fun n->
  let p=vfs^"/engines/hermes/modules/sa_plan/"^n in
  let expected=List.find(fun j->Yojson.Safe.Util.(to_string(member"path"j))=p)declared in
  let bytes=capture p in need(sha bytes=Yojson.Safe.Util.(to_string(member"sha256"expected)))("VFS source drift "^p);
  write(native^"/fixture/"^n)bytes;n,sha bytes)
  ["sqlite_main_mapping.ml";"sqlite_main_mapping.mli";"sqlite_main_mapping_stubs.c";"sqlite_write_vfs.ml";"sqlite_write_vfs.mli";"sqlite_write_vfs_stubs.c"]in
 let vfs_manifest=sha(Yojson.Safe.to_string(`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])vfs_inputs)))in
 let dso="/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib/libsqlite3.so.3.53.3"in
 need(sha(capture dso)="83be5e2629d718bf67b5bd0b545f56fd3438773791bfaf26f0bdbd78e9e5f16b")"pinned SQLite DSO drift";
 write(native^"/fixture/sqlite_write_vfs_fixture.ml")(read(vfs^"/engines/hermes/modules/sa_plan/sqlite_write_vfs.ml"));
 (* PRIVATE public-API provisioning bridge, never a production initializer.
    No raw OCaml Sqlite3 representation cast, no keeper child/session escape. *)
 write(native^"/fixture/control_persist_stubs.c"){c|
#include <sqlite3.h>
#include <caml/mlvalues.h>
static int persist(sqlite3*db,char**error,const sqlite3_api_routines*api){
 (void)error;(void)api;int yes=1,out=0;
 if(sqlite3_db_config(db,SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE,1,&out)!=SQLITE_OK||out!=1)return SQLITE_ERROR;
 if(sqlite3_wal_autocheckpoint(db,0)!=SQLITE_OK)return SQLITE_ERROR;
 return sqlite3_file_control(db,"main",SQLITE_FCNTL_PERSIST_WAL,&yes);
}
CAMLprim value caml_uos_control_fixture_persist(value unit){(void)unit;return Val_bool(sqlite3_auto_extension((void(*)(void))persist)==SQLITE_OK);}
|c};
 write(native^"/dune-project")"(lang dune 3.0)\n(name recovery_control_private)\n";
 let sp=root^"/engines/hermes/modules/sa_plan"in
 let names=Sys.readdir sp|>Array.to_list|>List.sort String.compare|>List.filter(fun n->(Filename.check_suffix n".ml"||Filename.check_suffix n".mli")&&not(List.mem n["recovery_kernel.ml";"recovery_kernel.mli";"recovery_port.ml";"recovery_owner_journal.ml";"recovery_owner_journal.mli";"recovery_owner_journal_port.ml"]))in
 List.iter(fun n->copy(sp^"/"^n)(native^"/store/"^n))names;
 write(native^"/store/dune")"(library (name sa_plan) (libraries core digestif sqlite3 yojson) (preprocess (pps ppx_jane)))\n";
 List.iter(fun n->copy(root^"/plugins/uos-risk-prioritization/validation/"^n^".ml")(native^"/checker/"^n^".ml"))
  ["priority";"bounded";"record";"live_plan";"checker";"host_clock"];
 write(native^"/checker/dune")"(library (name control_checker) (wrapped false) (libraries yojson unix cryptokit sqlite3 mtime.clock.os))\n";
 List.iter(fun n->copy(sp^"/"^n)(native^"/fixture/"^n))
  ["recovery_kernel.ml";"recovery_kernel.mli";"recovery_owner_journal.ml";"recovery_owner_journal.mli";"recovery_owner_journal_port.ml";"recovery_port.ml"];
 List.iter(fun suffix->copy(resource^rr^suffix)(native^"/fixture/recovery_resource"^suffix))[".ml";".mli"];
 copy(root^"/tools/telegram_store_transport_guardian.ml")(native^"/fixture/recovery_fixture_guardian.ml");
 List.iter(fun n->copy(sp^"/test/"^n)(native^"/fixture/"^n))
  ["recovery_control_fixture_prepare.ml";"recovery_control_fixture_port.ml"];
 let store=capture(sp^"/sa_plan_store.ml")and helpers=capture(sp^"/test/reclaim_fixture_extension.ml")and kernel=capture(sp^"/test/recovery_kernel_fixture_extension.ml")in
 (* Actual test-only adaptation, not a production hook. The SAME Store handle
    checks the signed resource/checker before every native freshness boundary
    and appends its binding within the task/capability transaction. *)
 let adapted=if red then kernel^{|
let control_execute _ _ ~boundary:_ ~record_binding:_ = Error (Reclaim_refused "MISSING_COMPOSED_RESOURCE_INTERPRETER")
|}else
  let prefix=match Astring.String.cut ~sep:"let cap_execute store e="kernel with Some(p,_)->p|None->failwith"kernel split"in
  let body=match Astring.String.cut ~sep:"let cap_execute store e="kernel with Some(_,b)->b|None->assert false in
  let body=replace "let%bind clock=Recovery_kernel.still_valid e in" "let%bind ()=boundary() in\n   let%bind clock=Recovery_kernel.still_valid e in"body in
  let body=replace "match prior with Some j->Ok(Cap_historical j)|None->" "match prior with Some j->\n   let%bind ()=if Recovery_control_fixture_prepare.control_lookup store.db r.reclaim_request_id record_binding then Ok()else Error\"missing bound resource history\"in Ok(Cap_historical j)|None->"body in
  let insert={|let%bind ()=with_stmt store.db "INSERT INTO control_resource_receipt VALUES(?,?)"(fun st->
   let%bind ()=bind_values_result "same-transaction signed resource/checker binding"st[TEXT r.reclaim_request_id;TEXT record_binding]in step_done "control receipt"st)in
  let%bind ()=if Recovery_control_fixture_prepare.control_lookup store.db r.reclaim_request_id record_binding then Ok()else Error"control receipt readback"in
  let%bind readback=cap_lookup store e r in|}in
  let body=replace "let%bind readback=cap_lookup store e r in"insert body in
  (* Avoid circular modules: helper's SQL lookup is factored as a tiny private
     local binding; prepare and worker use this SAME implementation below. *)
  let body=String.concat"Control_receipt.lookup"(Astring.String.cuts ~sep:"Recovery_control_fixture_prepare.control_lookup"body)in
  prefix^"let control_execute store e ~boundary ~record_binding="^body in
 write(native^"/fixture/recovery_kernel_fixture.ml")("open Sa_plan__\n"^store^helpers^adapted);
 (* Strict bounded receipt lookup is shared by the generated executor and
    native adapter, without exposing anything in the production Store MLI. *)
 let receipt={|let lookup db id binding =
 let st=Sqlite3.prepare db "SELECT CASE WHEN typeof(binding_json)='text' THEN CAST(substr(CAST(binding_json AS BLOB),1,16385) AS TEXT) ELSE NULL END FROM control_resource_receipt WHERE request_id=? LIMIT 2"in
 Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st;Core.Gc.keep_alive db)(fun()->
 if Sqlite3.bind st 1(Sqlite3.Data.TEXT id)<>Sqlite3.Rc.OK then failwith"bind";
 match Sqlite3.step st with
 |Sqlite3.Rc.DONE->false
 |Sqlite3.Rc.ROW->let b=Sqlite3.column_text st 0 in
   if b<>binding||String.length b>16384||Sqlite3.step st<>Sqlite3.Rc.DONE then failwith"bound control history conflict";true
 |_->failwith"control receipt lookup")
|}in write(native^"/fixture/control_receipt.ml")receipt;
 write(native^"/fixture/dune"){|(library (name recovery_kernel) (wrapped false) (modules recovery_kernel recovery_resource) (libraries digestif yojson mirage-crypto-ec unix mtime.clock ptime.clock))
(library (name recovery_owner_journal) (wrapped false) (modules recovery_owner_journal) (libraries core digestif yojson sqlite3 unix))
(executable (name recovery_owner_journal_port) (modules recovery_owner_journal_port) (libraries recovery_owner_journal))
(library (name control_receipt) (wrapped false) (modules control_receipt) (libraries sqlite3 core))
(library (name recovery_kernel_fixture) (wrapped false) (modules recovery_kernel_fixture) (libraries core sa_plan recovery_kernel sqlite3 control_receipt) (preprocess (pps ppx_jane)))
(library (name sqlite_main_mapping) (wrapped false) (modules sqlite_main_mapping) (libraries core digestif sqlite3 unix threads) (foreign_stubs (language c) (names sqlite_main_mapping_stubs) (flags (:standard -I/nix/store/538744yaz5y7xyx780wpfw2azby9iqxj-sqlite-3.53.3-dev/include -Wall -Wextra -Werror))) (c_library_flags -L/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib -Wl,-rpath,/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib -lsqlite3 -ldl))
(library (name sqlite_write_vfs) (wrapped false) (modules sqlite_write_vfs) (libraries sqlite_main_mapping core sqlite3 yojson unix) (foreign_stubs (language c) (names sqlite_write_vfs_stubs) (flags (:standard -I/nix/store/538744yaz5y7xyx780wpfw2azby9iqxj-sqlite-3.53.3-dev/include -Wall -Wextra -Werror))) (c_library_flags -L/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib -Wl,-rpath,/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib -lsqlite3 -ldl -lpthread))
(library (name sqlite_write_vfs_fixture) (wrapped false) (modules sqlite_write_vfs_fixture) (libraries sqlite_write_vfs sqlite_main_mapping core sqlite3 yojson unix))
(library (name recovery_control_fixture_prepare) (wrapped false) (modules recovery_control_fixture_prepare) (libraries recovery_kernel_fixture recovery_kernel recovery_owner_journal control_checker sqlite_main_mapping core mirage-crypto-ec yojson sqlite3 unix) (foreign_stubs (language c) (names control_persist_stubs) (flags (:standard -I/nix/store/538744yaz5y7xyx780wpfw2azby9iqxj-sqlite-3.53.3-dev/include -Wall -Wextra -Werror))))
(executable (name recovery_control_fixture_port) (modules recovery_control_fixture_port) (libraries recovery_control_fixture_prepare recovery_kernel_fixture recovery_kernel sqlite_write_vfs_fixture core sqlite3 yojson unix) (link_flags (:standard -cc /nix/store/w88q44gqd1qg5wmkk7v0h97rpiqvam0l-gcc-wrapper-15.3.0/bin/gcc -ccopt -L/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib -ccopt -Wl,-rpath,/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib)))
(executable (name recovery_fixture_guardian) (modules recovery_fixture_guardian) (libraries unix mtime.clock))
(executable (name recovery_port) (modules recovery_port) (libraries recovery_kernel yojson))
|};
 ignore(run "01-native-build"(tc^"/toolchains/opam-ocaml/bin/dune")["build";"--root";native;"--build-dir";base^"/native-build";"-j1";"fixture/recovery_control_fixture_port.exe";"fixture/recovery_fixture_guardian.exe";"fixture/recovery_owner_journal_port.exe";"fixture/recovery_port.exe"]);
 let bin=base^"/native-build/default/fixture"in
 let worker=bin^"/recovery_control_fixture_port.exe"and guardian=bin^"/recovery_fixture_guardian.exe"and journal=bin^"/recovery_owner_journal_port.exe"in
 let clock=String.trim(run "02-clock""/usr/bin/chronyc"["-c";"tracking"])in
 let driver=base^"/driver.json"in
 mkdir(base^"/cases");
 writej driver(`Assoc["domain",`String"PRIVATE_RECOVERY_CONTROL_DRIVER";"source_root",`String root;"evidence_root",`String tc;"seed_portfolio",`String seed;
 "evidence_directory",`String(base^"/cases");"vfs_manifest",`String vfs_manifest;
 "worker",`String worker;"guardian",`String guardian;"journal_worker",`String journal;"launcher",`String launcher;"clock_tracking",`String clock]);
 let package=base^"/package"in mkdir(package^"/src/cepaf_gleam/harness");
 write(package^"/gleam.toml")"name = \"recovery_control_private\"\nversion = \"0.1.0\"\ntarget = \"erlang\"\n[dependencies]\ncepaf_gleam = \">=0.0.0\"\ngleam_stdlib = \">=0.0.0\"\ngleam_erlang = \">=0.0.0\"\ngleam_otp = \">=0.0.0\"\ngleam_json = \">=0.0.0\"\ngleam_crypto = \">=0.0.0\"\ngleeunit = \">=0.0.0\"\nenvoy = \">=0.0.0\"\nsimplifile = \">=0.0.0\"\n";
 List.iter(fun n->let p=root^"/apps/cepaf_gleam/src/cepaf_gleam/harness/"^n^".gleam"in
  let b=capture p in write(package^"/src/cepaf_gleam/harness/"^n^".gleam")
   (if n="recovery_owner"then b^capture(root^"/apps/cepaf_gleam/test/fixtures/recovery_owner_fixture_extension.gleam.inc")else b))
 ["recovery_owner";"recovery_owner_store"];
 let test_source=capture(root^"/apps/cepaf_gleam/test/fixtures/recovery_control_actor_test.gleam.inc")in
 let common=match Astring.String.cut ~sep:"// Missing resource/checker guards"test_source with Some(a,_)->a|_->failwith"ordinary common marker"in
 let ordinary=match Astring.String.cut ~sep:"// ORDINARY_ONLY_BEGIN"test_source with Some(_,b)->
  (match Astring.String.cut ~sep:"// ORDINARY_ONLY_END"b with Some(a,_)->a|_->failwith"ordinary end marker")|_->failwith"ordinary start marker"in
 write(package^"/src/recovery_control_actor_test.gleam")
  (String.concat""(Astring.String.cuts ~sep:"import simplifile\n"common)^ordinary);
 ignore(run "03-gleam-compile"(tc^"/toolchains/gleam-1.16.0/bin/gleam")["compile-package";"--target";"erlang";"--package";package;"--out";base^"/gleam-out";"--lib";full_lib]);
 let ebins=Sys.readdir full_lib|>Array.to_list|>List.sort String.compare|>List.filter_map(fun n->let p=full_lib^"/"^n^"/ebin"in if Sys.file_exists p then Some p else None)in
 let extra=["UOS_CONTROL_DRIVER_LOCATOR",driver;"UOS_CONTROL_LAUNCHER",launcher;"UOS_CONTROL_LAUNCHER_SHA",sha(read launcher);
 "UOS_CONTROL_GUARDIAN",guardian;"UOS_CONTROL_GUARDIAN_SHA",sha(read guardian);"UOS_CONTROL_HELPER",worker;"UOS_CONTROL_HELPER_SHA",sha(read worker);
 "UOS_CONTROL_WORKER",worker;"UOS_CONTROL_WORKER_SHA",sha(read worker);"UOS_CONTROL_JOURNAL",journal;"UOS_CONTROL_JOURNAL_SHA",sha(read journal)]in
 let eval="code:ensure_loaded(telegram_store_transport_ffi),erlang:trace_pattern({telegram_store_transport_ffi,finite_request_with_cleanup,2},true,[call_count]),erlang:trace_pattern({telegram_store_transport_ffi,request_config_with_cleanup,2},true,[call_count]),io:format(\"OWNER=~p FFI=~p~n\",[code:which('cepaf_gleam@harness@recovery_owner'),code:which(telegram_store_transport_ffi)]),R=eunit:test({timeout,25,fun recovery_control_actor_test:ordinary_bound_owner_commit_history_test/0},[verbose]),io:format(\"FINITE=~p LEGACY=~p~n\",[erlang:trace_info({telegram_store_transport_ffi,finite_request_with_cleanup,2},call_count),erlang:trace_info({telegram_store_transport_ffi,request_config_with_cleanup,2},call_count)]),case R of ok->halt(0);_->halt(2)end."in
 let log=run ~expected:(if red then 2 else 0)~extra "04-control-e2e"(tc^"/toolchains/nix-profile/bin/erl")
  (["+S";"4:4";"-noshell";"-pa"]@ebins@["-pa";base^"/gleam-out/ebin";"-eval";eval])in
 need(Astring.String.is_infix ~affix:"LEGACY={call_count,0}"log)"legacy transport used";
 need(Astring.String.is_infix ~affix:("OWNER=\""^base^"/gleam-out/ebin/")log)"wrong loaded owner";
 need(Astring.String.is_infix ~affix:("FFI=\""^full_lib^"/cepaf_gleam/ebin/telegram_store_transport_ffi.beam")log)"wrong loaded FFI";
 need(Astring.String.is_infix ~affix:"Test passed."log)"missing ordinary path result";
 List.iter(fun(p,h)->need(sha(read p)=h)("source drift "^p))!pins;
 let refs=List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins in
 let cases=Sys.readdir(base^"/cases")|>Array.to_list|>List.sort String.compare|>List.map(fun n->
  let p=base^"/cases/"^n in `Assoc["path",`String p;"sha256",`String(sha(read p))])in
 writej(base^"/receipt.json")(`Assoc["schema",`String"uos.recovery-control-development.v1";"mode",`String"ORDINARY_DEVELOPMENT_PATH_ONLY_PRODUCTION_HOLD";
 "authority",`String"NONE";"activation",`Bool false;"source_root",`String root;"resource_dependency",`String resource;"base",`String base;
 "execution_mode",`String"ISOLATED_ORDINARY_OPEN_COMMIT_HISTORY_ONLY";"other_cases",`String"NOT_RUN_CURRENT_RESTRICTION_NO_PROXY_NO_FAULT_PRELOAD_NO_ATTACK_OR_MUTANT_RUNS";
 "source_before_after",`List refs;"cases",`List cases;"runs",`List(List.rev_map(fun(label,exit,hash)->`Assoc["label",`String label;"exit",`Int exit;"stdout_sha256",`String hash])!runs);
 "native_worker_sha256",`String(sha(read worker));"guardian_sha256",`String(sha(read guardian));"launcher_sha256",`String(sha(read launcher));
 "scope",`String"Actual checker core on synthetic four-task plan executes and CLOSES ALL descriptors BEFORE bound writer. Full snapshot and postgoal revalidated under BEGIN on same borrowed public SQLite handle as task/resource receipt. Signed context binds actual main/WAL/SHM IDs; reviewed writable VFS issues only retained origins. Fixed R/I TEST trust, no production authority. Initial NTP observation only. Private PERSIST_WAL initializer, no keeper escape. POSIX-preload fault tests remain separate VFS component evidence; finite control path uses actual fixed fixture signals, no preload inheritance. No hostile sameUID/cgroup/powerloss/general incarnation or full native release closure proof. Private initialization NOT production migration.";
 "no_effects",`List(List.map(fun x->`String x)["canonical task/DB";"production runtime";"real keys";"VCS";"production source interfaces"])]);
 print_endline(base^"/receipt.json")
