#use "topfind";;
#require "bos,yojson,cryptokit,unix";;
(* ONE ordinary actual native checker observation + DATA binder and actual
   default-refusing gateway. No trusted grant/APPROVE or effect is fabricated. *)
let root="/home/an/NAS-setup/uos"
let ws=root^"/.uos-workspaces/codex-admission-reviewable-20261101"
let cached=root^"/.uos-workspaces/codex-recovery-observed-20261101/var/harness/integrated-ordinary-3b82e8/lib"
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let sha b=Cryptokit.hash_string(Cryptokit.Hash.sha256())b|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let write p s=mkdir(Filename.dirname p);let fd=Unix.openfile p[Unix.O_CREAT;Unix.O_EXCL;Unix.O_WRONLY]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c s;flush c;Unix.fsync fd)
let replace text old replacement=String.concat replacement(Astring.String.cuts~sep:old text)
let jread p=Yojson.Basic.from_string(read p)
let s x=`String x
let text j k=Yojson.Basic.Util.(member k j|>to_string)
let production=["harness/admission";"harness/operations";"harness/successor_mcp";"mcp/registry";"mcp/runtime_gateway";"mcp/route_convergence"]
let ()=
 if Array.length Sys.argv<>2||Sys.argv.(1)<>"--ordinary"then failwith"ordinary mode only";
 mkdir(ws^"/var/harness");let base=Filename.temp_file~temp_dir:(ws^"/var/harness")"reviewed-recovery-ordinary-"""in Unix.unlink base;Unix.mkdir base 0o700;
 List.iter(fun x->mkdir(base^"/"^x))["tmp";"case";"assessment-root/var/sa-plan"];
 Printf.printf"BASE=%s\n%!"base;
 let pins=ref[]and refs=ref[]in
 let capture p=let b=read p in pins:=(p,sha b)::!pins;b in
 let copy p dst=write dst(capture p)in
 List.iter(fun p->ignore(capture p))[ws^"/tools/validation/reviewed_recovery_admission_fixture.ml";root^"/tools/ecology_process.ml";root^"/toolchains/opam-ocaml/bin/ocaml";root^"/toolchains/opam-ocaml/bin/dune";root^"/toolchains/gleam-1.16.0/bin/gleam";root^"/toolchains/nix-profile/bin/erl"];
 let env=Astring.String.Map.of_list["PATH",root^"/toolchains/opam-ocaml/bin:"^root^"/toolchains/nix-profile/bin:/usr/bin:/bin";"OPAM_SWITCH_PREFIX",root^"/toolchains/opam-ocaml";"OCAMLPATH",root^"/toolchains/opam-ocaml/lib";"TMPDIR",base^"/tmp";"DUNE_CACHE","disabled";"ERL_FLAGS","+S 4:4 +A 2";"ERL_CRASH_DUMP","/dev/null";"UOS_REVIEWED_RECOVERY_CASE",base^"/case";"UOS_REVIEWED_RECOVERY_ROOT",ws]in
 let run ?cwd label exe args=
  let argv=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"60000";"262144";"merged";exe]@args in
  let command=base^"/"^label^"-command.json"in write command(Yojson.Basic.to_string(`List(List.map s argv)));
  let invoke()=Bos.OS.Cmd.run_out~env~err:Bos.OS.Cmd.err_run_out(Bos.Cmd.of_list argv)|>Bos.OS.Cmd.out_string~trim:false in
  let result=match cwd with None->invoke()|Some dir->let old=Sys.getcwd()in Fun.protect~finally:(fun()->Unix.chdir old)(fun()->Unix.chdir dir;invoke())in
  match result with
  |Ok(out,(_,`Exited n))->let log=base^"/"^label^".log"and status=base^"/"^label^".exit"in write log out;write status(string_of_int n^"\n");refs:=command::log::status::!refs;Printf.printf"%s exit%d\n%!"label n;if n<>0 then failwith(label^" failed; retained "^base);out
  |_->failwith("UNKNOWN retained "^base)in
 let source=ws^"/engines/hermes/modules/sa_plan"and project=base^"/native-source"in
 let excluded=["recovery_kernel";"recovery_port";"recovery_owner_journal";"recovery_owner_journal_port"]in
 Sys.readdir source|>Array.to_list|>List.sort String.compare|>List.iter(fun n->if(Filename.check_suffix n".ml"||Filename.check_suffix n".mli")&&not(List.mem(Filename.remove_extension n)excluded)then copy(source^"/"^n)(project^"/store/"^n));
 write(project^"/dune-project")"(lang dune 3.17)\n";
 write(project^"/store/dune")"(library (name sa_plan) (libraries core digestif sqlite3 yojson) (preprocess (pps ppx_jane)))\n";
 List.iter(fun n->copy(source^"/development/checker/"^n)(project^"/checker/"^n))["priority.ml";"bounded.ml";"record.ml";"live_plan.ml";"checker.ml";"host_clock.ml";"dune"];
 let original=capture(source^"/test/test_recovery_snapshot_checker_integration.ml")in
 let prefix=match Astring.String.cut~sep:" (* Compatibility only:"original with Some(a,_)->a|None->failwith"setup source marker changed"in
 let setup=prefix^" Printf.printf\"ONE_ORDINARY_OBSERVATION_SETUP_PASS checks=%d\\n%!\" !check_count\n"in
 let setup=replace setup"codex-recovery-snapshot-integration-20261101""codex-admission-reviewable-20261101"|>fun x->replace x"out^\"/synthetic.sqlite3\"""Filename.dirname out^\"/assessment-root/var/sa-plan/uos.sqlite3\""in
 write(project^"/test/ordinary_setup.ml")setup;
 write(project^"/test/dune")"(executable (name ordinary_setup) (libraries sa_plan control_checker core digestif sqlite3 yojson unix mtime.clock.os))\n";
 let validation=ws^"/plugins/uos-risk-prioritization/validation"in
 Sys.readdir validation|>Array.to_list|>List.sort String.compare|>List.iter(fun n->if Filename.check_suffix n".ml"||Filename.check_suffix n".mli"||n="dune"then copy(validation^"/"^n)(project^"/validator/"^n));
 ignore(run"01-native-build"(root^"/toolchains/opam-ocaml/bin/dune")["build";"--root";project;"--build-dir";base^"/native-build";"-j1";"test/ordinary_setup.exe";"validator/validate.exe"]);
 ignore(run"02-observation-setup"(base^"/native-build/default/test/ordinary_setup.exe")[ws;base^"/case"]);
 (* Mirror public policy/evidence only. No source-tree DB/cache/config/key is read. *)
 let package_paths=["AGENTS.md";"contracts/rules/20260907-1559-risk-prioritization-sop.md";"docs/wiki/20260907-1559-risk-prioritization-guide.md";"docs/zk/20260907-1559-adr-risk-prioritization.md";"docs/journal/20260907-1559-risk-prioritization-journal.md";"contracts/rules/20260907-1606-risk-checker-contract.md";"docs/wiki/20260907-1606-risk-checkers-guide.md";"docs/journal/20260907-1606-risk-checkers-journal.md";"plugins/uos-risk-prioritization/skills/uos-risk-prioritization/SKILL.md";"plugins/uos-risk-prioritization/skills/uos-risk-prioritization/references/20260907-1559-superpowers-bindings.md";"plugins/uos-risk-prioritization/.codex-plugin/plugin.json";"governance/planning/20260907-1559-risk-priority-policy.json";"governance/planning/20260907-1559-risk-priority-record.schema.json";"governance/planning/20260907-1559-risk-priority-example.json";"governance/agents/policy/20260907-1559-risk-priority-bindings.toml";"tools/risk-priority-check"]in
 let aliases=List.concat_map(fun r->[r^"/AGENTS.md";r^"/skills/uos-risk-prioritization/SKILL.md";r^"/rules/20260907-1559-risk-prioritization-sop.md"])[".codex";".claude";".gemini";".agents"]in
 let evidence=["engines/hermes/modules/sa_plan/sa_plan_store.ml";"engines/hermes/modules/sa_plan/sa_plan_store.mli";"engines/hermes/modules/sa_plan/development/checker/live_plan.ml";"engines/hermes/modules/sa_plan/development/checker/checker.ml";"engines/hermes/modules/sa_plan/test/test_recovery_snapshot_checker_integration.ml"]in
 let vfiles=Sys.readdir validation|>Array.to_list|>List.filter(fun n->Filename.check_suffix n".ml"||Filename.check_suffix n".mli"||List.mem n["dune";"dune-project";"uos-risk-priority-validation.opam"])|>List.map(fun n->"plugins/uos-risk-prioritization/validation/"^n)in
 List.sort_uniq String.compare(package_paths@aliases@evidence@vfiles)|>List.iter(fun p->copy(ws^"/"^p)(base^"/assessment-root/"^p));
 let factual=jread(base^"/case/factual-proposal.json")in
 let request=Yojson.Basic.Util.member"request"factual in
 let old=Yojson.Basic.Util.(member"old"request|>to_list)in
 let bindings=`List(List.map(fun row->`Assoc["task_id",s(text row"task");"worker",s(text row"worker");"attempt",Yojson.Basic.Util.member"attempt"row;"lease_until_ns",s(text row"lease")])old)in
 let plan=text request"plan"and selected=text(List.hd old)"task"in
 let binding_json=Yojson.Basic.to_string(`Assoc["plan_id",s plan;"bindings",bindings])in
 let report=run~cwd:(base^"/assessment-root")"03-full-cli-checker"(base^"/native-build/default/validator/validate.exe")["--reclaim-set-preflight";base^"/case/portfolio.json";selected;binding_json]in
 let report_json=Yojson.Basic.from_string report in
 if text report_json"status"<>"RECLAIM_PREFLIGHT_PASS"then failwith"actual checker did not pass";
 write(base^"/case/full-cli-report.json")report;
 let manifest=production|>List.map(fun p->"apps/cepaf_gleam/src/cepaf_gleam/"^p^".gleam")|>List.sort String.compare|>List.map(fun path->`Assoc["path",s path;"sha256",s(sha(capture(ws^"/"^path)))])|>fun xs->Yojson.Basic.to_string(`List xs)in
 let proposal=`Assoc["schema",s"uos.harness-reviewed-recovery-proposal.v1";"plan_id",s plan;"selected_task",s selected;"target_worker",s(text(List.hd old)"worker");"snapshot_sha256",Yojson.Basic.Util.(member"sa_plan"report_json|>member"snapshot_sha256");"assessment_sha256",Yojson.Basic.Util.member"assessment_sha256"report_json;"source_manifest_sha256",s(sha manifest);"bindings",bindings;"selection_review",`Null]in
 write(base^"/case/admission-proposal.json")(Yojson.Basic.to_string proposal);
 let package=base^"/gleam-package"in
 write(package^"/gleam.toml")"name = \"reviewed_recovery_private\"\nversion = \"0.0.0\"\ntarget = \"erlang\"\n[dependencies]\ncepaf_gleam = \">=0.0.0\"\nuos_swarm = \">=0.0.0\"\ngleam_stdlib = \">=0.0.0\"\ngleam_json = \">=0.0.0\"\ngleam_otp = \">=0.0.0\"\ngleam_erlang = \">=0.0.0\"\ngleam_crypto = \">=0.0.0\"\nenvoy = \">=0.0.0\"\nsimplifile = \">=0.0.0\"\ngleeunit = \">=0.0.0\"\n";
 List.iter(fun p->copy(ws^"/apps/cepaf_gleam/src/cepaf_gleam/"^p^".gleam")(package^"/src/cepaf_gleam/"^p^".gleam"))production;
 copy(ws^"/apps/cepaf_gleam/test/harness_reviewed_recovery_test.gleam")(package^"/src/harness_reviewed_recovery_test.gleam");
 ignore(run"04-gleam-build"(root^"/toolchains/gleam-1.16.0/bin/gleam")["compile-package";"--target";"erlang";"--package";package;"--out";base^"/gleam-out";"--lib";cached]);
 let dependency_paths=Sys.readdir cached|>Array.to_list|>List.sort String.compare|>List.map(fun n->cached^"/"^n^"/ebin")|>List.filter Sys.file_exists in
 let modules=List.map(fun p->"cepaf_gleam@"^replace p"/""@")production@["harness_reviewed_recovery_test"]in
 let loaded=String.concat","(List.map(fun m->Printf.sprintf"%S = code:which('%s'), io:format(\"LOADED ~s~n\", [code:which('%s')])"(base^"/gleam-out/ebin/"^m^".beam")m m)modules)in
 let eval=loaded^", case eunit:test(harness_reviewed_recovery_test,[verbose]) of ok -> halt(0); _ -> halt(2) end."in
 let testlog=run"05-ordinary-gleam-tests"(root^"/toolchains/nix-profile/bin/erl")(["+S";"4:4";"-noshell"]@List.concat_map(fun p->["-pa";p])dependency_paths@["-pa";base^"/gleam-out/ebin";"-eval";eval])in
 if not(Astring.String.is_infix~affix:"All 4 tests passed"testlog)then failwith"test marker missing";
 List.iter(fun(p,h)->if sha(read p)<>h then failwith("source drift "^p))!pins;
 let file p=`Assoc["path",s p;"sha256",s(sha(read p))]in
 let artifacts=["snapshot-before.json";"portfolio.json";"checker.json";"factual-proposal.json";"full-cli-report.json";"admission-proposal.json"]|>List.map(fun n->file(base^"/case/"^n))in
 let receipt=base^"/receipt.json"in
 let generated=modules|>List.map(fun m->file(base^"/gleam-out/ebin/"^m^".beam"))in
 write receipt(Yojson.Basic.pretty_to_string(`Assoc["schema",s"uos.reviewed-recovery-admission-development.v1";"author",s"LOCAL_CODEX_RELAY";"authority",s"NONE";"production_admitted",`Bool false;"source_before_after",`List(List.map(fun(p,h)->`Assoc["path",s p;"sha256",s h])!pins);"evidence",`List(List.map file !refs);"candidate_beams",`List generated;"native_setup_binary",file(base^"/native-build/default/test/ordinary_setup.exe");"native_checker_binary",file(base^"/native-build/default/validator/validate.exe");"factual_artifacts",`List artifacts;"ordinary_tests",`Int 4;"limitations",`List(List.map s["Only private synthetic v7 plan/portfolio. Full existing native CLI checker really executed, including clock consistency; no independent assessment/review or canonical authority.";"Actual six-module candidate overlay on existing reviewed app dependencies, not a fresh full app closure. Two inherited operations warnings retained. Dependency runtime freshness inherited from the earlier reviewed app, not recertified by this overlay.";"No genuine current grant or completed dedicated review was invented. Authenticated positive preparation UNRUN; actual gateway refuses missing grant. Distinct session label is not authenticated session ownership.";"Proposal sources are six captured modules, not full compiler/runtime/dependency closure. Manual cross-language JSON comparison is not a wire/refinement proof.";"Prepared observation cannot create TaskFence/owner/executor. Production native interpreter, trusted recovery issuer, nine-object migration and effect-time whole-projection transaction remain unavailable.";"No fault, concurrent, adversarial, partial-cache, crash or mutation tests. No canonical task/DB/runtime/key/VCS effects or new external inference/network/package calls. Local Codex model cost UNKNOWN."])]));
 Printf.printf"RECEIPT=%s\nSHA256=%s\n%!"receipt(sha(read receipt))
