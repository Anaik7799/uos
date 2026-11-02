#use "topfind";;
#require "bos,yojson,cryptokit,unix";;
(* One ordinary observer/checker/DATA-proposal plus private Store compatibility
   flow. No production task, route, approval, signer or new mutator. *)
let root="/home/an/NAS-setup/uos"
let ws=root^"/.uos-workspaces/codex-recovery-snapshot-integration-20261101"
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p s=mkdir(Filename.dirname p);let fd=Unix.openfile p[Unix.O_CREAT;Unix.O_EXCL;Unix.O_WRONLY]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c s;flush c;Unix.fsync fd)
let ()=
 if Array.length Sys.argv<>2||Sys.argv.(1)<>"--ordinary"then failwith"ordinary mode only";
 mkdir(ws^"/var/harness");let base=Filename.temp_file~temp_dir:(ws^"/var/harness")"snapshot-checker-"""in Unix.unlink base;Unix.mkdir base 0o700;mkdir(base^"/tmp");mkdir(base^"/case");
 Printf.printf"BASE=%s\n%!"base;
 let pins=ref[]in let capture p=let b=read p in pins:=(p,sha b)::!pins;b in
 let source=ws^"/engines/hermes/modules/sa_plan"and project=base^"/source"in
 let excluded=["recovery_kernel";"recovery_port";"recovery_owner_journal";"recovery_owner_journal_port"]in
 Sys.readdir source|>Array.to_list|>List.sort String.compare|>List.iter(fun n->
  if(Filename.check_suffix n".ml"||Filename.check_suffix n".mli")&&not(List.mem(Filename.remove_extension n)excluded)
  then write(project^"/store/"^n)(capture(source^"/"^n)));
 write(project^"/dune-project")"(lang dune 3.17)\n";
 write(project^"/store/dune")"(library (name sa_plan) (libraries core digestif sqlite3 yojson) (preprocess (pps ppx_jane)))\n";
 List.iter(fun n->write(project^"/checker/"^n)(capture(source^"/development/checker/"^n))) ["priority.ml";"bounded.ml";"record.ml";"live_plan.ml";"checker.ml";"host_clock.ml";"dune"];
 write(project^"/test/test_recovery_snapshot_checker_integration.ml")(capture(source^"/test/test_recovery_snapshot_checker_integration.ml"));
 write(project^"/test/dune")"(executable (name test_recovery_snapshot_checker_integration) (libraries sa_plan control_checker core digestif sqlite3 yojson unix mtime.clock.os))\n";
 List.iter(fun p->ignore(capture p))[ws^"/tools/validation/recovery_snapshot_checker_fixture.ml";root^"/tools/ecology_process.ml";root^"/toolchains/opam-ocaml/bin/dune";root^"/toolchains/opam-ocaml/bin/ocaml";ws^"/AGENTS.md";ws^"/governance/planning/20260907-1559-risk-priority-example.json";ws^"/governance/planning/20260907-1559-risk-priority-record.schema.json"];
 let env=Astring.String.Map.of_list["PATH",root^"/toolchains/opam-ocaml/bin:"^root^"/toolchains/nix-profile/bin:/usr/bin:/bin";"OPAM_SWITCH_PREFIX",root^"/toolchains/opam-ocaml";"OCAMLPATH",root^"/toolchains/opam-ocaml/lib";"TMPDIR",base^"/tmp";"DUNE_CACHE","disabled"]in
 let logs=ref[]in
 let run label exe args=
  let argv=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"60000";"262144";"merged";exe]@args in
  let command=base^"/"^label^"-command.json"in write command(Yojson.Basic.to_string(`List(List.map(fun s->`String s)argv)));
  match Bos.OS.Cmd.run_out~env~err:Bos.OS.Cmd.err_run_out(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string~trim:false with
  |Ok(out,(_,`Exited n))->let log=base^"/"^label^".log"and status=base^"/"^label^".exit"in write log out;write status(string_of_int n^"\n");logs:=command::log::status::!logs;
   Printf.printf"%s exit%d\n%!"label n;if n<>0 then failwith(label^" failed; retained "^base);out
  |_->failwith("UNKNOWN retained "^base)in
 ignore(run"01-build"(root^"/toolchains/opam-ocaml/bin/dune")["build";"--root";project;"--build-dir";base^"/build";"-j1";"test/test_recovery_snapshot_checker_integration.exe"]);
 let executable=base^"/build/default/test/test_recovery_snapshot_checker_integration.exe"in
 let log=run"02-ordinary-snapshot-checker-proposal"executable[ws;base^"/case"]in
 if not(Astring.String.is_infix~affix:"ONE_ORDINARY_SNAPSHOT_CHECKER_FLOW_PASS"log)then failwith"ordinary marker absent";
 List.iter(fun(p,h)->if sha(read p)<>h then failwith("source changed "^p))!pins;
 let ref_file p=`Assoc["path",`String p;"sha256",`String(sha(read p))]in
 let tm=Unix.gmtime(Unix.gettimeofday())in let prefix=Printf.sprintf"%04d%02d%02d-%02d%02d"(tm.tm_year+1900)(tm.tm_mon+1)tm.tm_mday tm.tm_hour tm.tm_sec in
 let receipt=base^"/"^prefix^"-snapshot-checker-proposal-development-receipt.json"in
 write receipt(Yojson.Basic.pretty_to_string(`Assoc["schema",`String"uos.snapshot-checker-proposal-development.v1";"author",`String"LOCAL_CODEX_RELAY";"authority",`String"NONE";"production_route",`String"HELD";
  "source_before_after",`List(List.map(fun(p,h)->`Assoc["path",`String p;"sha256",`String h])!pins);"evidence",`List(List.map ref_file !logs);"artifact",ref_file executable;
  "factual_artifacts",`List(List.map(fun n->ref_file(base^"/case/"^n))["snapshot-before.json";"portfolio.json";"checker.json";"factual-proposal.json";"snapshot-after.json"]);
  "ordinary_flows",`Int 1;"scope",`String"Only reviewed Store.recovery_snapshot_readonly supplies live rows to pure exact Live_plan conversion, checker, complete expired tuple derivation and fixed-purpose DATA proposal. No fallback Live_plan.read call. Actual source/portfolio/checker/snapshot bytes bound; selection/review UNAVAILABLE. Then direct private existing Store.claim_task compatibility observation changes exactly1row and increments observed attempt, not full-set MCP recovery safety.";
  "limitations",`List(List.map(fun s->`String s)["PRIVATE synthetic four-task v7 DB, test-authored risk assessments/distinct classes; no canonical preflight, independent tie selection/review or authority.";"Current MCP claim gate does not accept RECLAIM_PREFLIGHT_PASS, expired controlling fence refused; storage single claim lacks full-set reviewed receipt. Fixture reports routeHELD, does not enable or bypass existing Gleam path.";"Snapshot/clock are observation-time facts, not effect-time lease/resource proof; live grant/owner/custody/migration/quiescence remain absent.";"Logical read-only SQLite may coordinate sidecars. No hostileFS/process/cgroup/powerloss/refinement/concurrency/fault proof.";"One ordinary case only; no restricted tests, canonicalDB/tasks/runtime/key/JJ mutations or new external model/network/package calls."])]));
 Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"receipt(sha(read receipt))
