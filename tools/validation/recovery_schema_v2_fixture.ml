#use "topfind";;
#require "bos,yojson,cryptokit,unix";;
(* Only the two ordinary private versioned migration flows; no old broad suite. *)
let root="/home/an/NAS-setup/uos"
let ws=root^"/.uos-workspaces/codex-recovery-schema-v2-20261101"
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p s=mkdir(Filename.dirname p);let fd=Unix.openfile p[Unix.O_CREAT;Unix.O_EXCL;Unix.O_WRONLY]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c s;flush c;Unix.fsync fd)
let ()=
 if Array.length Sys.argv<>2||Sys.argv.(1)<>"--ordinary"then failwith"ordinary mode only";
 mkdir(ws^"/var/harness");let base=Filename.temp_file~temp_dir:(ws^"/var/harness")"migration-v2-ordinary-"""in Unix.unlink base;Unix.mkdir base 0o700;mkdir(base^"/tmp");
 Printf.printf"BASE=%s\n%!"base;
 let pins=ref[]in let capture p=let b=read p in pins:=(p,sha b)::!pins;b in
 let source=ws^"/engines/hermes/modules/sa_plan"in
 Sys.readdir source|>Array.to_list|>List.sort String.compare|>List.iter(fun n->
  if Filename.check_suffix n".ml"||Filename.check_suffix n".mli"||n="dune"then ignore(capture(source^"/"^n)));
 List.iter(fun p->ignore(capture(source^"/"^p)))["test/dune";"test/recovery_migration_fixture.ml";"test/recovery_migration_v2_fixture.ml";"test/test_recovery_schema_migration_v2.ml";"test/reclaim_fixture_extension.ml";"test/recovery_kernel_fixture_extension.ml"];
 let adapter=root^"/.uos-workspaces/codex-recovery-observed-20261101/engines/hermes/modules/sa_plan/development/recovery_adapter_context.ml"in
 if sha(capture adapter)<>"77aa249145c0b630588c7ec874cddbace7f6916d1888389c3c1a491c2e2a18cd"then failwith"reviewed adapter DDL source changed";
 List.iter(fun p->ignore(capture p))[ws^"/tools/validation/recovery_schema_v2_fixture.ml";ws^"/engines/hermes/dune-project";root^"/tools/ecology_process.ml";root^"/toolchains/opam-ocaml/bin/dune";root^"/toolchains/opam-ocaml/bin/ocaml"];
 let env=Astring.String.Map.of_list["PATH",root^"/toolchains/opam-ocaml/bin:"^root^"/toolchains/nix-profile/bin:/usr/bin:/bin";"OPAM_SWITCH_PREFIX",root^"/toolchains/opam-ocaml";"TMPDIR",base^"/tmp";"DUNE_CACHE","disabled"]in
 let logs=ref[]in
 let run label exe args=
  let argv=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"60000";"262144";"merged";exe]@args in
  let command=base^"/"^label^"-command.json"in write command(Yojson.Basic.to_string(`List(List.map(fun s->`String s)argv)));
  match Bos.OS.Cmd.run_out~env~err:Bos.OS.Cmd.err_run_out(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string~trim:false with
  |Ok(out,(_,`Exited n))->let log=base^"/"^label^".log"and status=base^"/"^label^".exit"in write log out;write status(string_of_int n^"\n");logs:=command::log::status::!logs;Printf.printf"%s exit%d\n%!"label n;if n<>0 then failwith(label^" failed; preserved "^base);out
  |_->failwith("UNKNOWN; preserved "^base)in
 ignore(run"01-canonical-dune-build"(root^"/toolchains/opam-ocaml/bin/dune")["build";"--root";ws^"/engines/hermes";"--build-dir";base^"/build";"-j1";"modules/sa_plan/test/test_recovery_schema_migration_v2.exe"]);
 let executable=base^"/build/default/modules/sa_plan/test/test_recovery_schema_migration_v2.exe"in
 let log=run"02-two-ordinary-versioned-upgrades"executable[ws;adapter]in
 if not(Astring.String.is_infix~affix:"TWO_ORDINARY_V2_MIGRATION_FLOWS_PASS"log)then failwith"ordinary marker absent";
 List.iter(fun(p,h)->if sha(read p)<>h then failwith("source changed "^p))!pins;
 let ref_file p=`Assoc["path",`String p;"sha256",`String(sha(read p))]in
 let tm=Unix.gmtime(Unix.gettimeofday())in let prefix=Printf.sprintf"%04d%02d%02d-%02d%02d"(tm.tm_year+1900)(tm.tm_mon+1)tm.tm_mday tm.tm_hour tm.tm_sec in
 let receipt=base^"/"^prefix^"-recovery-schema-v2-development-receipt.json"in
 write receipt(Yojson.Basic.pretty_to_string(`Assoc["schema",`String"uos.recovery-schema-v2-development.v1";"authority",`String"NONE";"production_enabled",`Bool false;
  "source_before_after",`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins);"evidence",`List(List.map ref_file !logs);"artifact",ref_file executable;
  "ordinary_flows",`Int 2;
  "scope",`String"Versioned task-only v2 schema DATA extends exact old6 with actualadapter3; genericmigrationreceipt3 reused. V1 module/interface unchanged. Private fixed interpreter upgrades completelegacy6 orv1nine to12, preserves originaltypedrows+oldv1migrationreceipts, appendsonev2receipt, readonlyhistory+exactreplay. Test-onlyv1helpers generatedbyDuneverbatimcopy, no new publicwriter/clock/hook/initializer.";
  "limitations",`List(List.map(fun s->`String s)["Production migrate remains Authority_unavailable; no trusted custody/resourceowner/issuer/route/migration capability supplied. All request fields DATA.";"V1 public schema/request semantics unchanged. Oldv1private historical interpreter may HOLD onnewv2schema; oldreceiptbytes preserved, not silentlyreinterpreted or certified asgenuineauthority.";"Cooperativepath/devino checks, not retainedSQLiteFD/hostileFS isolation. Nativeclock is UTC+Linuxmonotonic, not synchronizedNTP proof. Two databases still migrate inseparatetransactions.";"Fulltyped preservation is boundedprivateRAM, neverpublished/hashrawrows. 16MiB acceptedaggregate isnotstrictpreallocation/peakprocessbound; oldhelper32MiB/resource andexternalguard separate. Close/commit uncertainty reported, failurepaths nottestedhere.";"Onlytwoordinarypositiveflows, no fault/concurrency/partial-cache/adversarial/restricted/negativeAPItests, canonicalDB/task/runtime/config/keys/JJ or externalmodel/package/networkeffects. No fullavailability/powerloss/refinementproof."])]));
 Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"receipt(sha(read receipt))
