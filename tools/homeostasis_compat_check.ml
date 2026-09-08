#use "release_process.ml";;
(* Compile candidate tests in a new private directory. No installer or cutover. *)
let ()=try
 require(Array.length Sys.argv=3)"usage: SOURCE focused|all";
 let source=realpath Sys.argv.(1)and mode=Sys.argv.(2)in
 require(List.mem mode["focused";"all"])"invalid mode";
 let tmp=temp "uos-homeostasis-compat-"in
 let source_hashes=inventory(source^"/apps/cepaf_gleam/src")and test_hashes=inventory(source^"/apps/cepaf_gleam/test")in
 let candidate=checked "/home/an/.cargo/bin/jj"["--repository";source;"log";"-r";"@";"--no-graph";"-T";"commit_id"]|>String.trim in
 write_new(tmp^"/source-provenance.json")(Yojson.Safe.to_string(`Assoc[
  "candidate",`String candidate;"source",`Assoc(List.map(fun(p,h)->p,`String h)source_hashes);
  "tests",`Assoc(List.map(fun(p,h)->p,`String h)test_hashes)]));
 copy(source^"/apps/cepaf_gleam/src")(tmp^"/src");
 let toml=read_file(source^"/apps/cepaf_gleam/gleam.toml")65536 in
 write_new(tmp^"/gleam.toml")(String.split_on_char '\n' toml|>List.filter((<>)"[dev-dependencies]")|>String.concat"\n");
 let tests=["e2e_full_stack_test";"fractal_bdd_31x7_test";"tui_15_evolutionary_cycles_test";"tui_bdd_scenarios_test";"wisp_api_comprehensive_test"]in
 if mode="all"then ignore(checked"/usr/bin/cp"["-R";"--";source^"/apps/cepaf_gleam/test/.";tmp^"/src/"])
 else List.iter(fun n->copy(source^"/apps/cepaf_gleam/test/"^n^".gleam")(tmp^"/src/"^n^".gleam"))tests;
 if mode="all"then(
  mkdir(tmp^"/priv")0o700;
  let native=canonical^"/apps/cepaf_gleam/priv"in
  let artifacts=Sys.readdir native|>Array.to_list|>List.filter(fun n->Filename.check_suffix n".so")in
  require(List.length artifacts=9)"expected9 preprovisioned native artifacts";
  List.iter(fun n->copy(native^"/"^n)(tmp^"/priv/"^n))artifacts;
  Sys.readdir native|>Array.iter(fun n->if Filename.check_suffix n".sha256"then copy(native^"/"^n)(tmp^"/priv/"^n));
  copy(source^"/GEMINI.md")(tmp^"/GEMINI.md");
  write_new(tmp^"/native-provenance.json")(Yojson.Safe.to_string(`Assoc(List.map(fun n->n,`String(sha(native^"/"^n)))artifacts))));
 let lib=canonical^"/apps/cepaf_gleam/build/dev/erlang"in
 let compiled=tmp^"/cepaf_gleam"in
 let build=run ~seconds:180."/home/an/.nix-profile/bin/gleam"["compile-package";"--target";"erlang";"--package";tmp;"--out";compiled;"--lib";lib]in
 write_new(tmp^"/build.log")build.output;require(build.code=0)("compile failed "^tmp);
 if mode="all"&&not(Sys.file_exists(compiled^"/priv"))then copy(tmp^"/priv")(compiled^"/priv");
 let paths=Sys.readdir lib|>Array.to_list|>List.filter_map(fun d->let p=lib^"/"^d^"/ebin"in if d<>"cepaf_gleam"&&Sys.file_exists p then Some p else None)in
 let calls=["e2e_full_stack_test:e2e_workflow_prajna_biomorphic_check_test";"fractal_bdd_31x7_test:bdd_l2_homeostasis_interaction_test";"tui_15_evolutionary_cycles_test:evolutionary_cycle_01_simd_scorer_test";"tui_bdd_scenarios_test:given_homeostasis_tab_without_observation_then_reports_unknown_test";"tui_bdd_scenarios_test:given_evolution_tab_without_observation_then_denies_execution_test";"wisp_api_comprehensive_test:homeostasis_has_no_control_authority_test";"wisp_api_comprehensive_test:homeostasis_does_not_fabricate_pid_convergence_test"]in
 let selected=if mode="focused"then"["^String.concat","(List.map(fun n->"fun "^n^"/0")calls)^"]"
 else let modules=Sys.readdir(compiled^"/ebin")|>Array.to_list
  |>List.filter(fun n->Filename.check_suffix n"_test.beam")|>List.sort String.compare in
  require(List.length modules>100)"missing complete test module inventory";
  "["^String.concat","(List.map(fun n->"'"^Filename.chop_suffix n".beam"^"'")modules)^"]"in
 let expr="{module,gleeunit}=code:ensure_loaded(gleeunit),case eunit:test("^selected^",[verbose,{scale_timeouts,10}]) of ok->halt(0);error->halt(1) end."in
 let run_dir=if mode="focused"then tmp else(
  let root=tmp^"/fixture-repository"in mkdir root 0o700;mkdir(root^"/apps")0o700;
  let app=root^"/apps/cepaf_gleam"in mkdir app 0o700;mkdir(app^"/test")0o700;
  copy(source^"/apps/cepaf_gleam/test/fixtures")(app^"/test/fixtures");
  List.iter(fun rel->
   let rec parents p=if p<>root&&not(Sys.file_exists p)then(parents(Filename.dirname p);mkdir p 0o700)in
   parents(Filename.dirname(root^"/"^rel));copy(source^"/"^rel)(root^"/"^rel))
   ["tools/verification/candidate_snapshot.ml";"engines/hermes/modules/hermes_dependability/dependability_approval.ml"];
  copy(tmp^"/priv")(app^"/priv");copy(source^"/GEMINI.md")(app^"/GEMINI.md");app)in
 let run_tests=in_dir run_dir(fun()->run ~seconds:240. ~limit:8388608
  ~extra:["UOS_SA_PLAN_DB="^tmp^"/fixture-sa-plan.sqlite3";"UOS_KM_DB="^tmp^"/fixture-km.sqlite3"]
  (otp^"/erl")(["+S";"4:4";"-noshell";"-pa"]@paths@["-pa";compiled^"/ebin";"-eval";expr]))in
 write_new(tmp^"/test.log")run_tests.output;
 require(inventory(source^"/apps/cepaf_gleam/src")=source_hashes&&inventory(source^"/apps/cepaf_gleam/test")=test_hashes)"candidate drift during tests";
 emit "homeostasis-compat"(if run_tests.code=0 then"PASS"else"FAIL")
 ["mode",`String mode;"candidate",`String candidate;"evidence",`String tmp;"exit",`Int run_tests.code;
 "tail",`String(String.sub run_tests.output(max 0(String.length run_tests.output-600))(min 600(String.length run_tests.output)))];
 exit run_tests.code
 with e->emit"homeostasis-compat""FAIL"["error",`String(Printexc.to_string e)];exit 1;;
