#use "topfind";;
#require "bos,yojson,cryptokit,unix";;
(* One bounded ordinary flow. No canonical database, fault cases or grant. *)
let root="/home/an/NAS-setup/uos"
let ws=root^"/.uos-workspaces/codex-recovery-readonly-snapshot-20261101"
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p s=mkdir(Filename.dirname p);let fd=Unix.openfile p[Unix.O_CREAT;Unix.O_EXCL;Unix.O_WRONLY]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c s)
let ()=
 if Array.length Sys.argv<>2||not(List.mem Sys.argv.(1)["--ordinary";"--api-red"])then failwith"ordinary mode required";
 mkdir(ws^"/var/harness");let base=Filename.temp_file~temp_dir:(ws^"/var/harness")"readonly-snapshot-"""in
 Unix.unlink base;Unix.mkdir base 0o700;mkdir(base^"/tmp");
 Printf.printf"BASE=%s\n%!"base;
 let pins=ref[]in let capture p=let b=read p in pins:=(p,sha b)::!pins;b in
 let source=ws^"/engines/hermes/modules/sa_plan"and private_root=base^"/source"in
 let excluded=["recovery_kernel";"recovery_port";"recovery_owner_journal";"recovery_owner_journal_port"]in
 Sys.readdir source|>Array.to_list|>List.sort String.compare|>List.iter(fun n->
  if (Filename.check_suffix n".ml"||Filename.check_suffix n".mli")&&not(List.mem(Filename.remove_extension n)excluded)
  then write(private_root^"/"^n)(capture(source^"/"^n)));
 write(private_root^"/dune-project")"(lang dune 3.17)\n";
 write(private_root^"/dune")"(library (name sa_plan) (libraries core digestif sqlite3 yojson) (preprocess (pps ppx_jane)))\n";
 write(private_root^"/test/test_recovery_readonly_snapshot.ml")(capture(source^"/test/test_recovery_readonly_snapshot.ml"));
 ignore(capture(source^"/test/dune"));
 write(private_root^"/test/dune")"(executable (name test_recovery_readonly_snapshot) (libraries sa_plan digestif sqlite3 yojson unix))\n";
 List.iter(fun p->ignore(capture p))[ws^"/tools/validation/recovery_readonly_snapshot_fixture.ml";root^"/tools/ecology_process.ml";root^"/toolchains/opam-ocaml/bin/dune";root^"/toolchains/opam-ocaml/bin/ocaml"];
 let env=Astring.String.Map.of_list["PATH",root^"/toolchains/opam-ocaml/bin:"^root^"/toolchains/nix-profile/bin:/usr/bin:/bin";"OPAM_SWITCH_PREFIX",root^"/toolchains/opam-ocaml";"TMPDIR",base^"/tmp"]in
 let logs=ref[]in
 let run label exe args=
  let argv=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"60000";"262144";"merged";exe]@args in
  let command=base^"/"^label^"-command.json"in write command(Yojson.Basic.to_string(`List(List.map(fun s->`String s)argv)));
  match Bos.OS.Cmd.run_out~env~err:Bos.OS.Cmd.err_run_out(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string~trim:false with
  |Ok(out,(_,`Exited n))->let log=base^"/"^label^".log"and status=base^"/"^label^".exit"in
   write log out;write status(string_of_int n^"\n");logs:=command::log::status::!logs;
   Printf.printf"%s exit%d\n%!"label n;if n<>0 then failwith(label^" failed; preserved "^base);out
  |_->failwith("UNKNOWN; preserved "^base)in
 ignore(run"01-build"(root^"/toolchains/opam-ocaml/bin/dune")["build";"--root";private_root;"--build-dir";base^"/build";"-j1";"test/test_recovery_readonly_snapshot.exe"]);
 if Sys.argv.(1)="--api-red"then failwith"unexpected API already present";
 let executable=base^"/build/default/test/test_recovery_readonly_snapshot.exe"in
 let log=run"02-ordinary-readonly-flow"executable[]in
 if not(Astring.String.is_infix~affix:"ONE_ORDINARY_READONLY_SNAPSHOT_FLOW_PASS checks=10 authority=NONE production_route=UNCONFIGURED"log)then failwith"ordinary marker absent";
 List.iter(fun(p,h)->if sha(read p)<>h then failwith("source changed "^p))!pins;
 let ref_file p=`Assoc["path",`String p;"sha256",`String(sha(read p))]in
 let tm=Unix.gmtime(Unix.gettimeofday())in
 let prefix=Printf.sprintf"%04d%02d%02d-%02d%02d"(tm.tm_year+1900)(tm.tm_mon+1)tm.tm_mday tm.tm_hour tm.tm_sec in
 let receipt=base^"/"^prefix^"-readonly-recovery-snapshot-development-receipt.json"in
 write receipt(Yojson.Basic.pretty_to_string(`Assoc[
  "schema",`String"uos.recovery-readonly-snapshot-development.v1";"authority",`String"NONE";"production_route",`String"UNCONFIGURED";
  "source_before_after",`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins);
  "evidence",`List(List.map ref_file !logs);"artifact",ref_file executable;
  "ordinary_flows_passed",`Int 1;"ordinary_checks",`Int 10;
  "scope",`String"READONLY/query_only/trusted_schemaOFF/deferred transaction reuses exact existing bounded Store projection. No handle, query, callback, migration, grant or mutator is returned. Private fixture v7 initialized through ordinary Store APIs, all setup handles closed before observer, same JSON/SHA independently recomputed, observed query_only, main bytes unchanged, fresh reopen exact parity.";
  "limits",`List(List.map(fun s->`String s)["No canonical DB read or mutation and no MCP observation route enabled; caller native path/plan inputs are factual DATA, not trusted locator/authority.";"SQLite read-only/query_only is not whole-filesystem non-write isolation; WAL/SHM coordination, concurrency, hostile filesystem races, fork/crash/locks and unsupported schema cases UNVERIFIED in this one ordinary flow.";"Existing projection LIMITs do not bound all SQLite CPU/memory. External process guardian bounds this fixture; API itself has no cgroup/physical wall-clock proof.";"No restricted/fault/adversarial/broad tests, live tasks/runtime/config/keys or production effects."])]));
 Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"receipt(sha(read receipt))
