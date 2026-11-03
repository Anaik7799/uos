#use "topfind";;
#require "bos,yojson,cryptokit";;
(* LOCAL Codex relay. PRIVATE fixture only: no admitted owner/signing service,
   canonical DB/config/task or live process effects. Existing public R/I test
   vectors only. Production recovery_port/Store remain refusing. Args SRC TC.
   Exact production owner+separate .inc extension; explicit private test-source
   adaptation selects finite transport. External native workers are source-built
   and pinned here, NOT falsely included in the finite-launch v3 artifact.
   Two identical DBs demonstrate the signed physical-resource binding GAP. *)
let need b s=if not b then failwith s
let ()=need(Array.length Sys.argv=3)"usage: unified_recovery_finite_fixture.ml SOURCE_ROOT TOOLCHAIN_ROOT"
let root=Unix.realpath Sys.argv.(1)and tc=Unix.realpath Sys.argv.(2)
let base=Filename.temp_file ~temp_dir:"/tmp" "uos-unified-finite-fixture-" ""
let ()=Unix.unlink base;Unix.mkdir base 0o700;Printf.printf "FIXTURE=%s\n%!"base
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->
 let n=in_channel_length c in need(n<=67108864)"file bound";really_input_string c n)
let sha s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let write p s=let c=open_out_bin p in output_string c s;close_out c
let mkdir p=match Bos.OS.Dir.create ~mode:0o700 ~path:true(Fpath.v p)with Ok _->()|_->failwith"mkdir"
let replace a b text=match Astring.String.cut ~sep:a text with Some(x,y)->need(not(Astring.String.is_infix ~affix:a y))"unique private patch";x^b^y|_->failwith("private patch missing "^a)
let replace_all a b text=String.concat b(Astring.String.cuts ~sep:a text)
let env=Astring.String.Map.of_list["PATH",tc^"/toolchains/opam-ocaml/bin:"^tc^"/toolchains/nix-profile/bin:/usr/bin:/bin";
 "OCAMLPATH",tc^"/toolchains/opam-ocaml/lib";"LANG","C.UTF-8";"DUNE_CACHE","disabled";"ERL_CRASH_DUMP","/dev/null";"ERL_FLAGS","+S 4:4 +A 2"]
let serial=ref 0
let run ?(extra=[]) ?(expected=0) label exe args=
 incr serial;let label=Printf.sprintf "%02d-%s" !serial label in
 let argv=[tc^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"60000";"1048576";"merged";exe]@args in
 write(base^"/"^label^"-command.json")(Yojson.Safe.to_string(`List(List.map(fun s->`String s)argv)));
 let env=List.fold_left(fun e(k,v)->Astring.String.Map.add k v e)env extra in
 match Bos.OS.Cmd.run_out ~env(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string ~trim:false with
 |Ok(text,(_,`Exited code))->write(base^"/"^label^".log")text;write(base^"/"^label^".exit")(string_of_int code^"\n");
   Printf.printf "%s exit=%d\n%!"label code;need(code=expected)("failed "^base^"/"^label^".log");text
 |_->failwith("unknown "^label)
let ()=
 let src=["apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_owner.gleam";"apps/cepaf_gleam/src/cepaf_gleam/harness/recovery_owner_store.gleam";
 "apps/cepaf_gleam/test/fixtures/recovery_owner_fixture_extension.gleam.inc";"apps/cepaf_gleam/test/fixtures/recovery_owner_actor_test.gleam.inc";
 "tools/validation/unified_recovery_finite_fixture.ml"]in
 let inputs=List.map(fun p->p,read(root^"/"^p))src in
 let native=base^"/native"in
 ignore(run "native-build"(tc^"/toolchains/opam-ocaml/bin/dune")
  ["build";"--root";root^"/engines/hermes";"--build-dir";native;"-j1";
   "modules/sa_plan/test/recovery_owner_fixture.exe";"modules/sa_plan/test/test_recovery_owner_journal.exe";"modules/sa_plan/recovery_port.exe"]);
 let actual=Yojson.Safe.from_string(run "finite-artifact"(tc^"/toolchains/opam-ocaml/bin/ocaml")
  [root^"/tools/ecology_native_build.ml";"build";root;tc])in
 let field k=Yojson.Safe.Util.(member k actual|>to_string)in
 let fixture_native=native^"/default/modules/sa_plan/test"in
 let full_lib=match Sys.getenv_opt"UOS_UNIFIED_APP_LIB"with Some p->Unix.realpath p|_->failwith"explicit fresh fullapp lib required"in
 need(Sys.file_exists(full_lib^"/cepaf_gleam/ebin/cepaf_gleam@harness@native_launch.beam"))"fullapp missing";
 let package=base^"/package"in mkdir(package^"/src/cepaf_gleam/harness");
 write(package^"/gleam.toml")"name = \"unified_finite_recovery_private\"\nversion = \"0.1.0\"\ntarget = \"erlang\"\n[dependencies]\ncepaf_gleam = \">=0.0.0\"\ngleam_stdlib = \">=0.0.0\"\ngleam_erlang = \">=0.0.0\"\ngleam_otp = \">=0.0.0\"\ngleam_json = \">=0.0.0\"\ngleam_crypto = \">=0.0.0\"\ngleeunit = \">=0.0.0\"\nenvoy = \">=0.0.0\"\nsimplifile = \">=0.0.0\"\n";
 List.iter(fun name->let p="apps/cepaf_gleam/src/cepaf_gleam/harness/"^name^".gleam"in
  let text=read(root^"/"^p)in write(package^"/src/cepaf_gleam/harness/"^name^".gleam")
   (if name="recovery_owner"then text^read(root^"/apps/cepaf_gleam/test/fixtures/recovery_owner_fixture_extension.gleam.inc")else text))
  ["recovery_owner";"recovery_owner_store"];
 List.iter(fun name->write(package^"/src/"^name^".gleam")(read(root^"/apps/cepaf_gleam/test/"^name^".gleam")))
  ["harness_recovery_owner_test";"harness_recovery_owner_store_test"];
 let original=read(root^"/apps/cepaf_gleam/test/fixtures/recovery_owner_actor_test.gleam.inc")in
 let transformed=original
  |>replace "import cepaf_gleam/harness/telegram_store_transport as t" "import cepaf_gleam/harness/native_launch as n\nimport gleam/list"
  |>replace_all "t.reviewed_local_configuration(" "finite("
  |>replace_all "t.LocalConfiguration" "n.Configuration"
  |>replace_all "s.raw_exchange(" "s.raw_exchange_finite("
  |>replace_all "c.configuration_data(" "c.finite_configuration_data("
  |>replace_all "s.exchange(" "finite_exchange("
  |>replace "fn fixture(ttl, timeout) {\n  let data = call_helper(\"/unused-private-fixture\", \"prepare\", ttl)\n  let journal ="
   "fn fixture(ttl, timeout) {\n  let data = call_helper(\"/unused-private-fixture\", \"prepare\", ttl)\n  from_data(data, timeout)\n}\nfn from_data(data, timeout) {\n  let journal ="in
 let additions={gleam|
fn finite(g, gh, worker, wh, config) {
  let assert Ok(c) = n.reviewed_configuration(n.LinuxX8664, n.NativeStorageV1,
    env("UOS_FINITE_LAUNCHER"), env("UOS_FINITE_LAUNCHER_SHA"), g, gh, worker, wh, config)
  c
}
fn finite_exchange(config, binding, event, previous) {
  s.exchange_connection_data(s.finite_connection_data(config), binding, event, previous)
}
pub fn public_start_with_finite_data_still_cannot_dispatch_test() {
  let f=fixture(20_000, 15_000)
  let assert Ok(owner)=c.start(f.config) |> result.map(fn(x){x.data})
  let state=await(owner,2000)
  state.phase |> should.equal(c.Unavailable)
  state.observed_effect_exchanges |> should.equal(0)
  observe(f) |> should.equal(v.Array([v.Integer(1),v.Integer(1),v.Integer(1)]))
  c.stop(owner,1000) |> should.be_ok()
}
pub fn production_port_remains_argument_refusing_hold_test() {
  let f=fixture(20_000,15_000)
  let config=finite(field(f.data,"guardian"),field(f.data,"guardian_sha256"),
    env("UOS_PRODUCTION_RECOVERY_PORT"),env("UOS_PRODUCTION_RECOVERY_PORT_SHA"),field(f.data,"native_locator"))
  let raw=s.raw_exchange_finite(config,field(f.data,"commit_body"))
  s.successful(raw.cleanup) |> should.be_true()
  let assert Ok(body)=raw.body
  let assert Ok(value)=json_guard.native_inspect(body,6)
  field(value,"status") |> should.equal("HOLD")
  field(value,"code") |> should.equal("ARGUMENTS_REFUSED")
  field(value,"authority") |> should.equal("NONE")
  observe(f) |> should.equal(v.Array([v.Integer(1),v.Integer(1),v.Integer(1)]))
}
// COUNTEREXAMPLE, not an authorization success test. Current signed fixture
// capability has no physical task-DB or owner-journal identity. Identical A/B
// copies can both execute under PRIVATE always-allow adapters. Real path HOLD.
pub fn identical_private_resources_expose_unsigned_db_namespace_gap_test() {
  let a=fixture(30_000,15_000)
  let source=field(a.data,"directory")
  let destination=source<>"-separate-copy"
  list.each(["tasks.sqlite3","owner.sqlite3"],fn(name){
    simplifile.is_file(source<>"/"<>name<>"-wal") |> should.equal(Ok(False))
    simplifile.is_file(source<>"/"<>name<>"-shm") |> should.equal(Ok(False))
  })
  simplifile.create_directory(destination) |> should.be_ok()
  simplifile.set_permissions_octal(destination,0o700) |> should.be_ok()
  list.each(["tasks.sqlite3","owner.sqlite3"],fn(name){
    simplifile.copy_file(source<>"/"<>name,destination<>"/"<>name) |> should.be_ok()
    simplifile.set_permissions_octal(destination<>"/"<>name,0o600) |> should.be_ok()
    simplifile.read_bits(source<>"/"<>name) |> should.equal(simplifile.read_bits(destination<>"/"<>name))
  })
  let assert Ok(locator)=simplifile.read(field(a.data,"native_locator"))
  let assert Ok(v.Array([cfg,pin,_,_]))=json_guard.native_inspect(locator,6)
  let copied_locator=destination<>"/native-locator.json"
  simplifile.write(copied_locator,json.to_string(v.encode(v.Array([cfg,pin,v.Text(destination<>"/tasks.sqlite3"),v.Text(destination<>"/effect-ready")])))) |> should.be_ok()
  simplifile.set_permissions_octal(copied_locator,0o600) |> should.be_ok()
  let data=a.data |> v.set("directory",v.Text(destination))
    |> v.set("journal_database",v.Text(destination<>"/owner.sqlite3"))
    |> v.set("native_locator",v.Text(copied_locator))
    |> v.set("marker",v.Text(destination<>"/effect-ready.pid"))
  let b=from_data(data,15_000)
  c.operation_id(a.config) |> should.equal(c.operation_id(b.config))
  field(a.data,"commit_body") |> should.equal(field(b.data,"commit_body"))
  let owner_a=start(a,fn(body){real(a,body)})
  let assert Ok(done_a)=commit(owner_a)
  done_a.phase |> should.equal(c.HistoricalFact)
  let owner_b=start(b,fn(body){real(b,body)})
  let assert Ok(done_b)=commit(owner_b)
  done_b.phase |> should.equal(c.HistoricalFact)
  observe(a) |> should.equal(v.Array([v.Integer(2),v.Integer(2),v.Integer(2)]))
  observe(b) |> should.equal(v.Array([v.Integer(2),v.Integer(2),v.Integer(2)]))
  simplifile.write(env("UOS_UNIFIED_RESOURCE_REPORT"),json.to_string(json.object([
    #("classification",json.string("PRIVATE_RESOURCE_BINDING_COUNTEREXAMPLE")),
    #("directory_a",json.string(source)),#("directory_b",json.string(destination)),
    #("operation_id",json.string(c.operation_id(a.config))),
    #("initial_task_and_journal_bytes_equal",json.bool(True)),
    #("identical_signed_commit_bytes",json.bool(True)),
    #("observed_attempts_a",v.encode(observe(a))),#("observed_attempts_b",v.encode(observe(b))),
    #("authority",json.string("NONE")),#("production_ready",json.bool(False))
  ]))) |> should.be_ok()
  c.stop(owner_a,1000) |> should.be_ok()
  c.stop(owner_b,1000) |> should.be_ok()
}
|gleam}in
 write(package^"/src/recovery_finite_actor_test.gleam")(transformed^additions);
 ignore(run "gleam-fixture-compile"(tc^"/toolchains/gleam-1.16.0/bin/gleam")
  ["compile-package";"--target";"erlang";"--package";package;"--out";base^"/out";"--lib";full_lib]);
 let artifact_path=field"directory"in
 let extra=["UOS_FINITE_LAUNCHER",field"launcher";"UOS_FINITE_LAUNCHER_SHA",field"launcher_sha256";
 "UOS_OWNER_GUARDIAN",fixture_native^"/recovery_fixture_guardian.exe";"UOS_OWNER_GUARDIAN_SHA",sha(read(fixture_native^"/recovery_fixture_guardian.exe"));
 "UOS_OWNER_FIXTURE",fixture_native^"/recovery_owner_fixture.exe";"UOS_OWNER_FIXTURE_SHA",sha(read(fixture_native^"/recovery_owner_fixture.exe"));
 "UOS_PRODUCTION_RECOVERY_PORT",native^"/default/modules/sa_plan/recovery_port.exe";"UOS_PRODUCTION_RECOVERY_PORT_SHA",sha(read(native^"/default/modules/sa_plan/recovery_port.exe"))]in
 let extra=("UOS_UNIFIED_RESOURCE_REPORT",base^"/resource-counterexample.json")::extra in
 let ebins=Sys.readdir full_lib|>Array.to_list|>List.sort String.compare|>List.filter_map(fun n->let p=full_lib^"/"^n^"/ebin"in if Sys.file_exists p then Some p else None)in
 let eval="code:ensure_loaded(telegram_store_transport_ffi),erlang:trace_pattern({telegram_store_transport_ffi,finite_request_with_cleanup,2},true,[call_count]),erlang:trace_pattern({telegram_store_transport_ffi,request_config_with_cleanup,2},true,[call_count]),Tests=[{timeout,15,fun M:F/0}||M<-[harness_recovery_owner_test,harness_recovery_owner_store_test,recovery_finite_actor_test],{F,0}<-M:module_info(exports),lists:suffix(\"_test\",atom_to_list(F))],Result=eunit:test(Tests,[verbose]),io:format(\"FINITE_CALLS=~p LEGACY_CALLS=~p~n\",[erlang:trace_info({telegram_store_transport_ffi,finite_request_with_cleanup,2},call_count),erlang:trace_info({telegram_store_transport_ffi,request_config_with_cleanup,2},call_count)]),case Result of ok->halt(0);_->halt(2)end."in
 let log=run ~extra "unified-finite-actor-tests"(tc^"/toolchains/nix-profile/bin/erl")
  (["+S";"4:4";"-noshell";"-pa"]@ebins@["-pa";base^"/out/ebin";"-eval";eval])in
 need(Astring.String.is_infix ~affix:"All 21 tests passed."log)"expected21groups";
 need(Astring.String.is_infix ~affix:"LEGACY_CALLS={call_count,0}"log)"legacy IO unexpectedly used";
 let journal_log=run "native-journal-regressions"(fixture_native^"/test_recovery_owner_journal.exe")[]in
 List.iter(fun(p,b)->need(read(root^"/"^p)=b)("source changed "^p))inputs;
 let report=`Assoc["schema",`String"uos.unified-finite-recovery-fixture.v1";"status",`String"SCOPED_PRIVATE_COMPOSITION_PASS";
 "attribution",`String"LOCAL_CODEX_RELAY";"fixture",`String base;"native_artifact",actual;"native_source_build",`String native;
 "sources",`List(List.map(fun(p,b)->`Assoc["path",`String p;"sha256",`String(sha b)])inputs);
 "actor_tests_sha256",`String(sha log);"artifact_scope",`String(artifact_path^": finite launcher only used from this artifact; journal/fixture/recovery binaries are separately source-built external test executables");
 "native_journal_tests_sha256",`String(sha journal_log);"actual_actor_test_groups",`Int 21;
 "resource_counterexample",`String"Identical private A/B task and owner DB copies both commit under one fixture signed capability: signed physical resource/journal namespace binding absent. This is a production blocker, not authority.";
 "production",`String"Public owner unavailable; production recovery port HOLD; no canonical DB/task/runtime/config/key changes";
 "authority",`String"NONE";"activation",`Bool false]in
 write(base^"/receipt.json")(Yojson.Safe.pretty_to_string report^"\n");print_endline(base^"/receipt.json")
