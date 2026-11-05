(* Private setup/observation helper. Creates ONLY unique /tmp fixtures. Not an
   issuer, real peer review, canonical task/coordinator adapter or production
   VCS operation. The fixture application's source-bound test really runs. *)
module K=Jj_integration_fixture_kernel
module S=Sa_plan.Store
let s x=`String x
let now()=Int64.of_float(Unix.gettimeofday()*.1e9)
let write p b=let c=open_out_bin p in output_string c b;close_out c
let prepare scenario=
 K.need(List.mem scenario["good";"omitted";"conflict";"dirty";"kill_before_effect";"kill_after_effect";"kill_after_receipt";"undeclared";"manifest_duplicate";"manifest_missing";"manifest_extra";"bad_review";"bad_tests";"expire_before_spawn";"deadline_before_spawn";"block_reserve"])"fixture scenario";
 let directory=Filename.temp_file"uos-jj-integration-"""in Unix.unlink directory;Unix.mkdir directory 0o700;
 let repository=directory^"/repository"and control=directory^"/control"and tasks=directory^"/tasks.sqlite3"in
 Unix.mkdir control 0o700;
 ignore(K.run directory["git";"init";"--no-colocate";repository]);
 let jj args=K.run directory(["--repository";repository;"--config";"user.name=\"UOS private fixture\"";"--config";"user.email=\"fixture@uos.invalid\"";"--config";"ui.color=\"never\"";"--config";"ui.paginate=\"never\""]@args)in
 write(repository^"/answer.ml")"let () = print_endline \"1\"\n";
 write(repository^"/contract.txt")"base contract\n";
 write(repository^"/stable.txt")"unchanged base file\n";
 ignore(jj["describe";"-m";"private base"]);ignore(jj["bookmark";"set";"main";"-r";"@"]);
 let base=K.main directory repository in
 ignore(jj["new";"main";"-m";"private complete candidate"]);
 write(repository^"/answer.ml")"let () = print_endline \"42\"\n";
 write(repository^"/contract.txt")"complete intended contract\n";
 if scenario="undeclared"then write(repository^"/undeclared.txt")"not in the reviewed manifest\n";
 ignore(jj["describe";"-m";"private complete candidate"]);
 let intended=K.query directory repository["log";"--no-graph";"-r";"@";"-T";"commit_id"]in
 let paths=match scenario with
 |"manifest_duplicate"->["answer.ml";"answer.ml";"contract.txt"]
 |"manifest_missing"->["answer.ml"]
 |"manifest_extra"->["answer.ml";"contract.txt";"stable.txt"]
 |_->["answer.ml";"contract.txt"]in
 let manifest=K.encode(`List(List.map(fun path->`Assoc["path",s path;"sha256",s(K.sha(K.file directory repository intended path))])paths))in
 let manifest_path=directory^"/manifest.json"and review=directory^"/review.json"and tests=directory^"/tests.json"in
 write manifest_path manifest;
 (* Real execution of this known synthetic candidate. Never arbitrary code
    from a public wire request; this setup helper is PRIVATE test code only. *)
 let extracted=directory^"/candidate.ml"and output=directory^"/candidate-output"in
 write extracted(K.file directory repository intended"answer.ml");
 let fd=Unix.openfile output[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 and input=Unix.openfile"/dev/null"[Unix.O_RDONLY]0 in
 let ocaml="/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocaml"in
 let runtime="/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocamlrun-a100"in
 let pid=Unix.create_process_env runtime[|runtime;ocaml;extracted|](K.fixed_env directory)input fd fd in
 Unix.close input;Unix.close fd;let _,status=Unix.waitpid[]pid in
 K.need(status=Unix.WEXITED 0&&String.trim(K.read output)="42")"ACTUAL_CANDIDATE_TEST_FAILED";
 (* This deterministic, non-independent fixture source check is real but NOT
    authenticated peer review or production review authority. *)
 K.need(K.file directory repository intended"answer.ml"="let () = print_endline \"42\"\n"&&K.file directory repository intended"contract.txt"="complete intended contract\n")"FIXTURE_SOURCE_CHECK";
 write review(K.encode(`Assoc["domain",s"uos.jj.fixture-review-observation.v1";"verdict",s(if scenario="bad_review"then"FIXTURE_REVIEW_REJECT"else"FIXTURE_SOURCE_CHECK_PASS_NOT_INDEPENDENT_NOT_AUTHORITY");"candidate",s intended;"manifest_sha256",s(K.sha manifest)]));
 write tests(K.encode(`Assoc["domain",s"uos.jj.fixture-test-observation.v1";"candidate",s intended;"manifest_sha256",s(K.sha manifest);"exit",`Int(if scenario="bad_tests"then 1 else 0);"stdout_sha256",s(K.sha(K.read output))]));
 let selected=ref intended in
 if scenario="omitted"then(ignore(jj["new";base;"-m";"private omitted change"]);write(repository^"/answer.ml")"let () = print_endline \"42\"\n";ignore(jj["describe";"-m";"private omitted change"]);selected:=K.query directory repository["log";"--no-graph";"-r";"@";"-T";"commit_id"]);
 if scenario="conflict"then(
  ignore(jj["new";base;"-m";"private other branch"]);write(repository^"/answer.ml")"let () = print_endline \"99\"\n";ignore(jj["describe";"-m";"private other branch"]);
  let other=K.query directory repository["log";"--no-graph";"-r";"@";"-T";"commit_id"]in
  ignore(jj["new";intended;other;"-m";"private conflicted merge"]);selected:=K.query directory repository["log";"--no-graph";"-r";"@";"-T";"commit_id"]);
 ignore(jj["new";!selected;"-m";"private clean workspace"]);
 let op=K.operation directory repository in
 if scenario="dirty"then write(repository^"/answer.ml")"dirty unsnapshotted bytes\n";
 let db=K.ok(S.open_db tasks)in Unix.chmod tasks 0o600;
 ignore(K.ok(S.create_plan db ~id:"uos/private-jj"~name:"private/jj"~title:"fixture"~now_ns:(now())));
 ignore(K.ok(S.create_task db ~plan_id:"uos/private-jj"~id:"INTEGRATE"~name:"private/integrate"~title:"fixture"~parent_id:None~dependencies:[]~priority:0~now_ns:(now())));
 ignore(K.ok(S.claim_task db ~plan_id:"uos/private-jj"~task_id:"INTEGRATE"~worker:"fixture-worker"~now_ns:(now())~lease_ns:1800000000000L));S.close db;
 let cfg=directory^"/locator.json"in
 write cfg(K.encode(`Assoc["directory",s directory;"repository",s repository;"control",s control;"tasks",s tasks;"owner",s"fixture-owner";"epoch",`Int 1;"manifest",s manifest_path;"review",s review;"tests",s tests;"fault",s(if String.starts_with ~prefix:"kill_"scenario||List.mem scenario["expire_before_spawn";"deadline_before_spawn";"block_reserve"]then scenario else"none")]));
 let bin=Filename.dirname(Unix.realpath Sys.executable_name)in
 `Assoc["directory",s directory;"locator",s cfg;"expected_main",s base;"candidate",s !selected;"expected_operation",s op;
 "manifest_sha256",s(K.sha manifest);"review_sha256",s(K.sha(K.read review));"tests_sha256",s(K.sha(K.read tests));
 "guardian",s(bin^"/jj_integration_fixture_guardian.exe");"guardian_sha256",s(K.binary_sha(bin^"/jj_integration_fixture_guardian.exe"));
 "worker",s(bin^"/jj_integration_fixture_port.exe");"worker_sha256",s(K.binary_sha(bin^"/jj_integration_fixture_port.exe"))]
let ()=
 try
  if Array.length Sys.argv<>3 then failwith"setup args";
  let result=match Sys.argv.(1)with
  |"prepare"->prepare Sys.argv.(2)
  |"observe"->let cfg=K.config Sys.argv.(2)in `Assoc["main",s(K.main(K.text"directory"cfg)(K.text"repository"cfg));"operation",s(K.operation(K.text"directory"cfg)(K.text"repository"cfg))]
  |"alter:operation"->let cfg=K.config Sys.argv.(2)in
   ignore(K.run(K.text"directory"cfg)(K.common(K.text"repository"cfg)@["bookmark";"set";"scratch";"-r";"main"]));`Bool true
  |"alter:owner"->let cfg=K.config Sys.argv.(2)in
   let next=match cfg with `Assoc fs->`Assoc(List.map(fun(k,v)->k,if k="epoch"then`Int 2 else v)fs)|_->assert false in write Sys.argv.(2)(K.encode next);`Bool true
  |"alter:lease"->let cfg=K.config Sys.argv.(2)in
   let db=Sqlite3.db_open ~mode:`NO_CREATE ~uri:false(K.text"tasks"cfg)in
   Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db);Core.Gc.keep_alive db)(fun()->K.need(Sqlite3.exec db"UPDATE sa_plan_task SET lease_until_ns=1 WHERE id='INTEGRATE'"=Sqlite3.Rc.OK)"private lease fault");`Bool true
  |"probe:output"->let cfg=K.config Sys.argv.(2)in let dir=K.text"directory"cfg in
   let code=try ignore(K.run dir(K.common(K.text"repository"cfg)@["log";"--no-graph";"-r";"all()";"-T";"\""^String.make 100000 'x'^"\""]));"UNBOUNDED_ACCEPTED"with K.Hold code->code in
   let largest=Array.fold_left(fun n name->if String.starts_with ~prefix:"jj-output-"name then max n(Unix.lstat(dir^"/"^name)).Unix.st_size else n)0(Sys.readdir dir)in
   `Assoc["code",s code;"largest_retained_bytes",`Int largest]
  |_->failwith"setup operation"in print_endline(K.encode result)
 with K.Hold code->prerr_endline code;exit 2
