#use "topfind";;
#require "bos,yojson,cryptokit,unix";;
(* One ordinary actual adapter/owner lifecycle, using versioned migrations.
   Frozen sources remain untouched. Only private initializer/observer assembly
   is adapted; the real adapter, VFS, control_execute/history and owner stay exact. *)
let root="/home/an/NAS-setup/uos"
let ws=root^"/.uos-workspaces/codex-migration-adapter-20261101"
let donor=root^"/.uos-workspaces/codex-recovery-observed-20261101"
let need b why=if not b then failwith why
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in need(n<=100663296)"input bound";really_input_string c n)
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p b=mkdir(Filename.dirname p);let fd=Unix.openfile p[Unix.O_CREAT;Unix.O_EXCL;Unix.O_WRONLY]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c b;flush c;Unix.fsync fd)
let replace a b source=match Astring.String.cut~sep:a source with Some(x,y)->need(not(Astring.String.is_infix~affix:a y))("ambiguous private adaptation "^a);x^b^y|_->failwith("missing private adaptation "^a)
let quote=Printf.sprintf"%S"
let ()=
 need(Array.length Sys.argv=2&&Sys.argv.(1)="--ordinary")"ordinary mode only";
 mkdir(ws^"/var/harness");let base=Filename.temp_file~temp_dir:(ws^"/var/harness")"migrated-adapter-"""in Unix.unlink base;Unix.mkdir base 0o700;mkdir(base^"/tmp");
 Printf.printf"WRAPPER=%s\n%!"base;
 let pins=ref[]in let capture p=let b=read p in pins:=(p,sha b)::!pins;b in
 let manifest=donor^"/var/harness/uos-native-signer-bundle-fb85d5/27-source-manifest.sha256"in
 need(sha(capture manifest)="ceb153859a317eda5a70631a5c91b4a09891153908d7ea44cc19caed7fc3d7cc")"reviewed observed27 manifest";
 String.split_on_char '\n'(read manifest)|>List.filter((<>)"")|>List.iter(fun line->
  need(String.length line>66&&String.sub line 64 2="  ")"manifest format";
  let p=String.sub line 66(String.length line-66)in need(sha(capture p)=String.sub line 0 64)"sealed donor source drift");
 let child=ws^"/engines/hermes/modules/sa_plan"in
 let migrator_inputs=["recovery_schema_migration.ml","f6e8fa16405bd940a98aaba7b45d5cbef9d259fb1e60e3e2a8f960507035e885";
  "recovery_schema_migration.mli","bcd0c821e390483bec13a58bc13d3459b0a6d22c5a0f3b90585c631debd25531";
  "recovery_schema_migration_v2.ml","f77fb63aa1843328caa7763182da746290f5bb4c33147169db2f2b8e9b459b64";
  "recovery_schema_migration_v2.mli","e42f064a25e8b128634451ce1114716843e62f9ac1b91854649a726ba4345c24";
  "test/recovery_migration_fixture.ml","2240a33db033b51ce2f50612ca5a8b28c515627b9e9b1bfbbe7f8e59d9374966";
  "test/recovery_migration_v2_fixture.ml","08f9c566e5dcb487568a3dfc24bd2491281124852cc63964672b9f348057a35b"]in
 List.iter(fun(p,h)->need(sha(capture(child^"/"^p))=h)"reviewed migration input drift")migrator_inputs;
 ignore(capture(child^"/development/test/recovery_migrated_schema_prepare.ml"));
 ignore(capture(ws^"/tools/validation/recovery_migrated_adapter_fixture.ml"));
 let capsule_path=base^"/private_capsule.ml"in
 let capsule=capture(donor^"/tools/recovery_development_capsule.ml")in
 need(sha capsule="e75c35d4e4d60acd80595d8c3222b5ef1711af85d177907bd78076869fd7dcf4")"capsule source drift";
 write capsule_path(replace"let root=source_root^\"/var/development-capsules/recovery\""("let root="^quote(ws^"/var/development-capsules/recovery"))capsule);
 let runner_path=base^"/private_runner.ml"in
 let original=capture(donor^"/tools/validation/recovery_native_signer_bundle_fixture.ml")in
 need(sha original="8d7327315d28ba061f8fb7c3f2b1e0bc9c094c4d682534baf33df530def1e7fe")"ordinary driver drift";
 let migration_code={code|
 let migration_source=CHILD_SOURCE in
 let migration=native^"/migration"in mkdir migration;
 List.iter(fun n->copy(migration_source^"/"^n)(migration^"/"^n))
  ["recovery_schema_migration.ml";"recovery_schema_migration.mli";"recovery_schema_migration_v2.ml";"recovery_schema_migration_v2.mli"];
 write(migration^"/migration_store.ml")("open Sa_plan__\n"^capture(sp^"/sa_plan_store.ml"));
 write(migration^"/recovery_migration_v1_helpers.ml")
  (replace"module S=Recovery_kernel_fixture""module S=Migration_store"(capture(migration_source^"/test/recovery_migration_fixture.ml")));
 copy(migration_source^"/test/recovery_migration_v2_fixture.ml")(migration^"/recovery_migration_v2_fixture.ml");
 copy(migration_source^"/development/test/recovery_migrated_schema_prepare.ml")(migration^"/recovery_migrated_schema_prepare.ml");
 write(migration^"/dune")"(library (name migration_specs) (wrapped false) (modules recovery_schema_migration recovery_schema_migration_v2) (libraries yojson))\n(library (name migration_initializer) (wrapped false) (modules migration_store recovery_migration_v1_helpers recovery_migration_v2_fixture recovery_migrated_schema_prepare) (libraries migration_specs sa_plan recovery_kernel core digestif sqlite3 yojson unix) (preprocess (pps ppx_jane)))\n";
 let prepare=native^"/store/development/test/recovery_native_prepare.ml"in
 let source=read prepare in
 let source=replace"let prepared=ok(Recovery_adapter.prepare_private_existing_v7~database)in""let prepared=Recovery_migrated_schema_prepare.migrate database in"source in
 let source=replace"/schema-preparation.json""/schema-migration.json"source in
 let source=replace"(root^\"/var/harness/\")"CHILD_HARNESS_PREFIXsource in
 need(not(Astring.String.is_infix~affix:"Recovery_adapter.prepare_private_existing_v7"source))"private schema prep must not be invoked";
 write prepare source;ignore(capture prepare);
 let port=native^"/store/development/test/recovery_native_fixture_port.ml"in
 let port_source=replace" |\"bound_observation\"->P.json"" |\"migration_receipts\"->`Bool(Recovery_migrated_schema_prepare.preserved dir)\n |\"bound_observation\"->P.json"(read port)in
 let port_source=replace"|\"observe\"|\"probe\"|\"probe_pending\"|\"resource_receipt\"|\"bound_observation\"|\"signed_physical\"->""|\"observe\"|\"probe\"|\"probe_pending\"|\"resource_receipt\"|\"bound_observation\"|\"signed_physical\"|\"migration_receipts\"->"port_source in
 write port port_source;ignore(capture port);
 let dune_path=native^"/store/development/test/dune"in
 let dune=replace"(modules recovery_native_prepare)\n (libraries ""(modules recovery_native_prepare)\n (libraries migration_initializer "(read dune_path)in
 let dune=replace"(modules recovery_native_fixture_port)\n (libraries ""(modules recovery_native_fixture_port)\n (libraries migration_initializer "dune in
 write dune_path dune;ignore(capture dune_path);
 ignore(capture PRIVATE_RUNNER);ignore(capture PRIVATE_CAPSULE);
|code}in
 let migration_code=migration_code|>replace"CHILD_SOURCE"(quote child)
  |>replace"CHILD_HARNESS_PREFIXsource"("("^quote(quote(ws^"/var/harness/"))^") source")
  |>replace"PRIVATE_RUNNER"(quote runner_path)|>replace"PRIVATE_CAPSULE"(quote capsule_path)in
 let add_assertions={code|
 let ordinary=replace
  "helper(text(f.data,\"directory\"),\"resource_receipt\",0) |> should.equal(v.Boolean(True))"
  "helper(text(f.data,\"directory\"),\"resource_receipt\",0) |> should.equal(v.Boolean(True))\n  helper(text(f.data,\"directory\"),\"migration_receipts\",0) |> should.equal(v.Boolean(True))"ordinary in
 let ordinary=replace"text(value,\"status\") |> should.equal(\"HISTORICAL\")"
  "text(value,\"status\") |> should.equal(\"HISTORICAL\")\n  helper(text(f.data,\"directory\"),\"migration_receipts\",0) |> should.equal(v.Boolean(True))"ordinary in
 let ordinary=replace"history.phase |> should.equal(c.HistoricalFact)"
  "history.phase |> should.equal(c.HistoricalFact)\n  helper(text(f.data,\"directory\"),\"migration_receipts\",0) |> should.equal(v.Boolean(True))"ordinary in
|code}in
 let runner=original
  |>replace"#use \"tools/recovery_development_capsule.ml\";;"("#use "^quote capsule_path^";;")
  |>replace"let directory=root^\"/var/harness\""("let directory="^quote(ws^"/var/harness"))
  |>replace" tree(sp^\"/development\")(native^\"/store/development\");"(" tree(sp^\"/development\")(native^\"/store/development\");\n"^migration_code)
  |>replace" write(package^\"/src/recovery_control_actor_test.gleam\")"(add_assertions^" write(package^\"/src/recovery_control_actor_test.gleam\")")
  |>replace"let data=read worker and initialization_helper=read helper in""let data=read worker and initialization_helper=read helper in\n need(not(Astring.String.is_infix~affix:\"camlRecovery_migrated_schema_prepare\"data)&&not(Astring.String.is_infix~affix:\"camlRecovery_migration_v2_fixture\"data))\"migration linked in data port\";"
 in write runner_path runner;
 let full_lib=donor^"/var/harness/integrated-ordinary-3b82e8/lib"in
 let launcher=root^"/.uos-workspaces/codex-unified-recovery-20261101/var/ecology/native-builds/cas/c1c16abf383dffd8b1834a96bd67563f5728b7be3beb26e4badd27e47647ef86/finite_launcher.exe"in
 let argv=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"60000";"1048576";"merged";
  root^"/toolchains/opam-ocaml/bin/ocaml";"-I";donor;runner_path;donor;root;
  root^"/.uos-workspaces/codex-recovery-resource-20261101";root^"/.uos-workspaces/codex-sqlite-write-vfs-20261101";full_lib;
  root^"/var/harness/20261031-1334-codex-hive/issuer-recovery/parent-current-risk.json";launcher;"--ordinary"]in
 write(base^"/ordinary-command.json")(Yojson.Basic.to_string(`List(List.map(fun s->`String s)argv)));
 let env=Astring.String.Map.of_list["PATH",root^"/toolchains/opam-ocaml/bin:"^root^"/toolchains/nix-profile/bin:/usr/bin:/bin";"OPAM_SWITCH_PREFIX",root^"/toolchains/opam-ocaml";"TMPDIR",base^"/tmp";"DUNE_CACHE","disabled"]in
 let prior=Sys.getcwd()in
 let result=Fun.protect~finally:(fun()->Unix.chdir prior)(fun()->Unix.chdir donor;Bos.OS.Cmd.run_out~env~err:Bos.OS.Cmd.err_run_out(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string~trim:false)in
 let out,exit_code=match result with Ok(out,(_,`Exited n))->out,n|_->"UNKNOWN",-1 in
 write(base^"/ordinary.log")out;write(base^"/ordinary.exit")(string_of_int exit_code^"\n");
 Printf.printf"ORDINARY_EXIT=%d\n%!"exit_code;need(exit_code=0)("ordinary run failed; retained "^base);
 let native_base=String.split_on_char '\n'out|>List.find(fun l->String.starts_with~prefix:"FIXTURE="l)|>fun l->String.sub l 8(String.length l-8)in
 let raw=native_base^"/receipt.json"in
 let r=Yojson.Safe.from_string(read raw)in
 let cases=Yojson.Safe.Util.(member"cases"r|>to_list)in
 need(List.length cases=1)"one ordinary case";
 List.iter(fun item->
  let path=Yojson.Safe.Util.(member"path"item|>to_string)in
  let ready=Yojson.Safe.from_string(read path)in
  let dir=Yojson.Safe.Util.(member"directory"ready|>to_string)in
  ignore(capture(dir^"/schema-migration.json"));
  need(not(Sys.file_exists(dir^"/schema-preparation.json")))"private schema preparation after migration";
  let report=Yojson.Safe.from_string(read(dir^"/schema-migration.json"))in
  need(Yojson.Safe.Util.member"status"report=`String"MIGRATED_V1_THEN_V2_DATA_ONLY")"migration status";
  ignore(capture(dir^"/migration-facts.json")))cases;
 List.iter(fun(p,h)->need(sha(read p)=h)("input changed "^p))!pins;
 let ref_file p=`Assoc["path",`String p;"sha256",`String(sha(read p))]in
 let tm=Unix.gmtime(Unix.gettimeofday())in let prefix=Printf.sprintf"%04d%02d%02d-%02d%02d"(tm.tm_year+1900)(tm.tm_mon+1)tm.tm_mday tm.tm_hour tm.tm_sec in
 let receipt=base^"/"^prefix^"-migrated-adapter-development-receipt.json"in
 write receipt(Yojson.Basic.pretty_to_string(`Assoc["schema",`String"uos.recovery-migrated-adapter-development.v1";"authority",`String"NONE";"production_enabled",`Bool false;
  "source_before_after",`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins);
  "actual_private_runner",ref_file runner_path;"actual_private_capsule",ref_file capsule_path;"underlying_ordinary_receipt",ref_file raw;
  "evidence",`List(List.map(fun p->ref_file(base^"/"^p))["ordinary.log";"ordinary.exit";"ordinary-command.json"]);
  "scope",`String"Existing ordinary finite external-purpose signer/owner/control_execute/history assembly. ONLY generated initializer replaces private schema preparation with actualv1+v2 migrations. Realadapter/dataport/VFS/controller sources unchanged; migrationhelpers excludeddata-port. Setup/migrationfdzero checks, fresh signingidentitiesafterv2, v1+v2receipts/schema12 checkedaftercommit/directhistory/newownerhistory. Journal initializesseparately. FixedpublicfixtureR/I vectors only, no productionauthority.";
  "limits",`List(List.map(fun s->`String s)["Privategeneratedsource/initializerandcapsulestorageadaptations, notnewproductioninterface. Frozenobserved27source+reviewedv2 dependency ratherthanself-containednewsourcepublication.";"No canonicalrecovery/currentauthority, actualcustody, fullreleaseclosure, hostileFS/powerloss/cgroup/formalproof. ExistingVFS42 freshprocess/cooperativeinode/nativecallee assumptions retained.";"Onlyoneordinarypositiveflow. No flagged/fault/concurrent/partial-cache/adversarial/signal/expiry/mutanttests or canonicalDB/task/runtime/config/realkey/JJ effects."])]));
 Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"receipt(sha(read receipt))
