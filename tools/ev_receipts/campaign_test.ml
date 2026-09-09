(* Behavioral CLI tests. Invoke with the built producer, workspace and candidate. *)
let require b why = if not b then failwith why
let get key = Yojson.Basic.Util.member key
let unit_tests () =
 let count=ref 0 in
 let test name f=incr count;f();Printf.printf "PASS %s\n%!" name in
 let refuses f=let rejected=try f();false with Failure _->true in require rejected "negative accepted" in
 let cases=["sample.first";"sample.second"] in
 let valid=Ev_campaign.transcript cases in
 test "complete execution" (fun()->Ev_campaign.validate_transcript ~cases ~exit_code:0 ~output:valid);
 List.iter(fun(name,output,exit_code)->test name(fun()->refuses(fun()->Ev_campaign.validate_transcript ~cases ~exit_code ~output)))
  ["empty coverage","",0;"omitted case",Ev_campaign.transcript["sample.first"],0;
   "duplicate case",Ev_campaign.transcript["sample.first";"sample.first";"sample.second"],0;
   "reordered cases",Ev_campaign.transcript(List.rev cases),0;
   "extra output",valid^"extra\n",0;"nonzero despite markers",valid,1;
   "start without return","EV98 START sample.first\n",0];
 test "unique mutation"(fun()->require(Ev_campaign.replace_once "a-b-c" "b" "x"="a-x-c") "mutation result");
 test "missing mutation anchor"(fun()->refuses(fun()->ignore(Ev_campaign.replace_once "a" "b" "x")));
 test "ambiguous mutation anchor"(fun()->refuses(fun()->ignore(Ev_campaign.replace_once "b-b" "b" "x")));
 test "recipe executables are ELF"(fun()->List.iter(fun(name,path,_)->if name<>"boot" then
  let c=open_in_bin path in let magic=Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->really_input_string c 4) in
  require(magic="\127ELF") ("recipe executable uses a wrapper: "^name)) Ev98_recipe.tools);
 test "nested compilers select the pinned ELF launcher"(fun()->
  let _,launcher,_=List.find(fun(name,_,_)->name="erlexec")Ev98_recipe.tools in
  List.iter(fun expected->require(List.mem expected Ev98_recipe.launcher_environment) "compiler emulator selection is not pinned")
   ["ESCRIPT_EMULATOR="^launcher;"ERLC_EMULATOR="^launcher;"ERLC_USE_SERVER=false"]);
 let child mode seconds limit =Ev_campaign.process ~deadline:(Receipt_validator.mono()+.2.) ~cwd:"/tmp" ~environment:[||]
  ~seconds ~limit (Unix.realpath Sys.executable_name) [mode] in
 test "actual nonzero child"(fun()->let r=child "child-exit" 1. 1024 in require(r.status=Unix.WEXITED 3 && r.failure=None && r.output="actual child\n") "child status lost");
 test "stdout and stderr stay separate"(fun()->let r=child "child-streams" 1. 1024 in require(r.status=Unix.WEXITED 0 && r.stdout="out\n" && r.stderr="err\n") "streams conflated");
 test "actual silent timeout"(fun()->let r=child "child-wait" 0.05 1024 in require(r.failure=Some "TIMEOUT" && r.elapsed<1.) "timeout not bounded");
 test "actual output quota"(fun()->let r=child "child-flood" 1. 16 in require(r.failure=Some "OUTPUT_QUOTA" && String.length r.output<=16) "output quota not enforced");
 test "actual signal termination"(fun()->let r=child "child-signal" 1. 1024 in require(r.status=Unix.WSIGNALED Sys.sigterm && r.failure=None) "signal status lost");
 test "descendant holding pipe is terminated"(fun()->let r=child "child-descendant" 0.05 1024 in require(r.failure=Some "TIMEOUT" && r.elapsed<1.) "descendant escaped deadline");
 test "global deadline overrides child allowance"(fun()->let r=Ev_campaign.process ~deadline:(Receipt_validator.mono()+.0.05) ~cwd:"/tmp" ~environment:[||] ~seconds:30. ~limit:1024 (Unix.realpath Sys.executable_name)["child-wait"] in require(r.failure=Some "TIMEOUT" && r.elapsed<1.) "global deadline ignored");
 Printf.printf "PASS %d campaign unit/process cases\n%!" !count
let run exe args =
 let file=Filename.temp_file "uos-campaign-test-" ".json" in
 let fd=Unix.openfile file [Unix.O_WRONLY;Unix.O_TRUNC] 0o600 in
 let pid=Unix.create_process exe (Array.of_list(exe::args)) Unix.stdin fd Unix.stderr in
 Unix.close fd;
 let _,status=Unix.waitpid [] pid in
 let json=Yojson.Basic.from_file file in
 Printf.printf "observed %s: %s %s\n%!" file
  (Yojson.Basic.to_string(get "status" json)) (Yojson.Basic.to_string(get "error" json));
 status,json
let () =
 match Array.to_list Sys.argv with
 | [_;"unit"] ->unit_tests()
 | [_;"child-exit"] ->print_endline "actual child";exit 3
 | [_;"child-streams"] ->print_endline "out";prerr_endline "err"
 | [_;"child-wait"] ->ignore(Unix.select [] [] [] 2.)
 | [_;"child-flood"] ->print_string(String.make 100000 'x');flush stdout
 | [_;"child-signal"] ->Unix.kill(Unix.getpid())Sys.sigterm
 | [_;"child-descendant"] ->if Unix.fork()=0 then (ignore(Unix.select [] [] [] 2.);Unix._exit 0)
 | _::"--ignore-working-copy"::_ ->
   Ev_campaign.write (Sys.getenv "CAMPAIGN_FAKE_JJ_MARKER") "untrusted candidate reader ran\n";exit 1
 | [_;exe;workspace;revision] ->
  let status,j=run exe ["observe";workspace;"98";revision] in
  require(status=Unix.WEXITED 0) "fixed EV98 campaign must execute successfully";
  require(get "status" j=`String "COMPONENT_OBSERVED") "component result missing";
  require(get "formal" j=`String "Formal_unavailable") "formal credit invented";
  require(get "sovereign" j=`String "Sovereign_pending") "sovereign credit invented";
  require(get "authority" j=`String "NONE") "effect authority invented";
  require(List.length(Yojson.Basic.Util.to_list(get "executed_cases" j))=42) "actual case coverage";
  require(List.length(Yojson.Basic.Util.to_list(get "negative_controls" j))=3) "negative controls missing";
  let actual=Yojson.Basic.Util.to_list(get "executed_cases" j) |> List.map Yojson.Basic.Util.to_string in
  require(actual=Ev98_recipe.cases) "recipe case order drift";
  let bindings=Yojson.Basic.Util.to_list(get "bindings" j) in
  require(List.length bindings>100) "artifact binding missing";
  List.iter(fun binding->let path=Yojson.Basic.Util.to_string(get "path" binding) in
   let bytes=if String.starts_with ~prefix:"candidate:" path then
     Receipt_validator.candidate_bytes workspace revision (String.sub path 10 (String.length path-10))
    else let c=open_in_bin path in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->really_input_string c(in_channel_length c)) in
   require(get "sha256" binding=`String(Receipt_validator.sha bytes)) "binding does not match actual bytes")bindings;
  List.iter(fun args->let status,j=run exe args in
    require(status<>Unix.WEXITED 0 && get "status" j=`String "HOLD") "unsupported request accepted")
   [["observe";workspace;"99";revision];["observe";workspace;"98";"@"];
    ["observe";workspace;"98";String.make 40 '0'];
    ["observe";workspace;"98";revision;"arbitrary-policy.json"];
    ["observe";workspace;"98";"337f99137673d7866b958a38bd490fb876b2880f"]];
  let fake=Ev_campaign.private_directory() in
  Ev_campaign.mkdir(fake^"/.jj");Ev_campaign.mkdir(fake^"/toolchains/nix-profile/bin");
  Unix.symlink(Unix.realpath Sys.executable_name)(fake^"/toolchains/nix-profile/bin/jj");
  let marker=fake^"/reader-ran" in Unix.putenv "CAMPAIGN_FAKE_JJ_MARKER" marker;
  let status,j=run exe ["observe";fake;"98";revision] in
  require(status<>Unix.WEXITED 0 && get "status" j=`String "HOLD") "invalid workspace accepted";
  require(not(Sys.file_exists marker)) "caller workspace substituted the pinned JJ reader";
  print_endline "PASS 7 campaign CLI cases including artifact rehash and reader substitution refusal"
 | _ -> failwith "campaign_test PRODUCER WORKSPACE REVISION"
