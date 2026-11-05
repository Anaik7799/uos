(* TEST-ONLY factual interpreter, not linked into production Sa-plan/harness.
   Gleam owns intent/orchestration. This kernel supplies finite file/JJ facts,
   last-moment storage CAS and one-use durable markers. Fixture predicates are
   not real reviewer authentication or integration/main coordinator authority.
   JJ has NO intrinsic expected-operation CAS: cooperative ownership is assumed;
   divergent operation heads/unknown writes HOLD, never auto retry/rollback. *)
module S=Sa_plan.Store
let jj="/nix/store/vzrnnii3369cn2a2bgdlkx9gh6m297fj-jujutsu-0.44.0/bin/jj"
let jj_sha="630fe2c54d0b9f53794aa37c1274a344e6067175ac9e8925087974fb3d0c4966"
let sha s=Digestif.SHA256.(to_hex(digest_string s))
let s x=`String x
exception Hold of string
let need b code=if not b then raise(Hold code)
let ok=function Ok x->x|Error _->raise(Hold"STORE_UNAVAILABLE")
let read p=
 let st=Unix.lstat p in need(st.st_kind=Unix.S_REG&&st.st_nlink=1&&st.st_size<=262144)"FILE_BOUND";
 let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->really_input_string c st.st_size)
let binary_sha p=
 let st=Unix.lstat p in need(st.st_kind=Unix.S_REG&&st.st_size>0&&st.st_size<=67108864)"BINARY_BOUND";
 let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->sha(really_input_string c st.st_size))
let encode=Yojson.Basic.to_string
let json raw=need(String.length raw>0&&String.length raw<=262144)"JSON_BOUND";
 let j=Yojson.Basic.from_string raw in need(encode j=raw)"NONCANONICAL_JSON";j
let field k j=Yojson.Basic.Util.member k j
let text k j=Yojson.Basic.Util.to_string(field k j)
let integer k j=Yojson.Basic.Util.to_int(field k j)
let closed keys=function `Assoc fs->need(List.map fst fs=keys)"CLOSED_SCHEMA"|_->raise(Hold"CLOSED_SCHEMA")
let hex n v=String.length v=n&&String.for_all(function 'a'..'f'|'0'..'9'->true|_->false)v
let canonical p=need(Unix.realpath p=p)"PATH_ALIAS";p
let durable path bytes=
 let fd=Unix.openfile path[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
 Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
  let rec write n=if n<String.length bytes then let k=Unix.write_substring fd bytes n(String.length bytes-n)in need(k>0)"WRITE_FAILED";write(n+k)in
  write 0;Unix.fsync fd);
 let parent=Unix.openfile(Filename.dirname path)[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
 Fun.protect ~finally:(fun()->Unix.close parent)(fun()->Unix.fsync parent)
let exists p=try ignore(Unix.lstat p);true with Unix.Unix_error(Unix.ENOENT,_,_)->false
let fixed_env directory=[|"HOME="^directory;"XDG_CONFIG_HOME="^directory;"JJ_CONFIG=/dev/null";
 "GIT_CONFIG_NOSYSTEM=1";"GIT_CONFIG_GLOBAL=/dev/null";"PATH=/nonexistent";"LANG=C";"LC_ALL=C";"TZ=UTC"|]
let active_deadline=ref Int64.max_int
let mono()=Mtime_clock.now_ns()
let check_deadline()=need(Int64.compare(mono())!active_deadline<0)"MONOTONIC_DEADLINE"
let run ?(before_spawn=(fun()->())) directory args=
 let stat=Unix.lstat jj in need(stat.st_kind=Unix.S_REG&&stat.st_uid=0&&stat.st_perm land 0o222=0&&stat.st_size<=67108864)"JJ_TOOL_SHAPE";
 need(binary_sha jj=jj_sha)"JJ_TOOL_MISMATCH";
 let input=Unix.openfile"/dev/null"[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
 let rd,wr=Unix.pipe ~cloexec:true()in
 let pid=try
  before_spawn();check_deadline();
  Unix.create_process_env jj(Array.of_list(jj::args))(fixed_env directory)input wr wr
 with e->Unix.close input;Unix.close rd;Unix.close wr;raise e in
 Unix.close input;Unix.close wr;Unix.set_nonblock rd;
 let limit=262144 and output=Buffer.create 4096 in
 let deadline=Int64.min !active_deadline(Int64.add(mono())2500000000L)in
 let status=ref None and eof=ref false in
 let reap()=match !status with Some _->()|None->
  (try Unix.kill pid Sys.sigkill with Unix.Unix_error(Unix.ESRCH,_,_)->());
  (try let _,s=Unix.waitpid[]pid in status:=Some s with Unix.Unix_error(Unix.ECHILD,_,_)->())in
 let preserve()=let p=Filename.temp_file ~temp_dir:directory"jj-output-"""in
  let c=open_out_bin p in output_string c(Buffer.contents output);close_out c;
  durable(p^".args.json")(encode(`List(List.map s args)))in
 Fun.protect ~finally:(fun()->Unix.close rd;reap())(fun()->
  let bytes=Bytes.create 4096 in
  let rec drain()=try match Unix.read rd bytes 0 4096 with
   |0->eof:=true
   |n->need(Buffer.length output+n<=limit)"JJ_OUTPUT_BOUND";Buffer.add_subbytes output bytes 0 n;drain()
   with Unix.Unix_error((Unix.EAGAIN|Unix.EWOULDBLOCK),_,_)->()in
  let rec loop()=
   need(Int64.compare(mono())deadline<0)"JJ_DEADLINE_UNKNOWN";
   drain();
   (match !status with None->(match Unix.waitpid[Unix.WNOHANG]pid with 0,_->()|_,s->status:=Some s)|_->());
   match !status,!eof with Some s,true->s|_->ignore(Unix.select[rd][][]0.005);loop()in
  try let status=loop()in
   if status<>Unix.WEXITED 0 then(preserve();raise(Hold"JJ_COMMAND_UNKNOWN"));Buffer.contents output
  with e->(try preserve()with _->());raise e)
let common repository=["--ignore-working-copy";"--at-operation";"@";"--repository";repository;
 "--config";"ui.color=\"never\"";"--config";"ui.paginate=\"never\"";
 "--config";"user.name=\"UOS private fixture\"";"--config";"user.email=\"fixture@uos.invalid\""]
let query directory repository args=String.trim(run directory(common repository@args))
let main directory repository=query directory repository["log";"--no-graph";"-r";"main";"-T";"commit_id"]
let operation directory repository=query directory repository["op";"log";"--no-graph";"-n";"1";"-T";"id"]
let file directory repository revision path=
 need(String.length path>0&&String.length path<=512&&String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'/'|'_'|'-'|'.'->true|_->false)path)"SOURCE_PATH";
 run directory(common repository@["file";"show";"-r";revision;"root:"^path])
let rec walk root relative=
 let path=if relative=""then root else root^"/"^relative in
 let st=Unix.lstat path in match st.st_kind with
 |Unix.S_DIR->Array.to_list(Sys.readdir path)|>List.filter(fun n->relative<>""||n<>".jj")|>List.concat_map(fun n->
   need(n<>".git")"COLOCATED_GIT_REFUSED";walk root(if relative=""then n else relative^"/"^n))
 |Unix.S_REG->need(st.st_nlink=1&&st.st_size<=262144)"WORKTREE_FILE_BOUND";[relative]
 |_->raise(Hold"WORKTREE_UNSUPPORTED")
let clean directory repository=
 let actual=List.sort compare(walk repository"")in need(List.length actual<=64)"WORKTREE_BOUND";
 let tracked=query directory repository["file";"list";"-r";"@";"-T";"path ++ \"\\n\""]in
 let tracked=if tracked=""then[]else String.split_on_char '\n' tracked|>List.sort compare in
 actual=tracked&&List.for_all(fun path->read(repository^"/"^path)=file directory repository"@"path)actual
let config path=
 let j=json(read path)in
 closed["directory";"repository";"control";"tasks";"owner";"epoch";"manifest";"review";"tests";"fault"]j;
 let directory=canonical(text"directory"j)in
 need(String.starts_with ~prefix:"/tmp/uos-jj-integration-"directory)"PRIVATE_FIXTURE_ONLY";
 List.iter(fun k->let p=canonical(text k j)in need(String.starts_with ~prefix:(directory^"/")p)"FIXTURE_PATH_CONTAINMENT")["repository";"control";"tasks";"manifest";"review";"tests"];
 need(not(exists(text"repository"j^"/.git"))&&exists(text"repository"j^"/.jj"))"STANDALONE_JJ_REQUIRED";j
let intent raw=
 let j=json raw in
 closed["domain";"logical_id";"plan";"task";"worker";"attempt";"integration_owner";"integration_epoch";"expected_main";"candidate";"expected_operation";"manifest_sha256";"review_sha256";"tests_sha256"]j;
 need(text"domain"j="uos.jj.fast-forward-integration-data.v1")"INTENT_DOMAIN";
 List.iter(fun(k,n)->need(hex n(text k j))"INTENT_DIGEST")["expected_main",40;"candidate",40;"expected_operation",128;"manifest_sha256",64;"review_sha256",64;"tests_sha256",64];
 List.iter(fun k->let v=text k j in need(String.length v>0&&String.length v<=160&&String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'|'/'|'.'->true|_->false)v)"INTENT_ID")["logical_id";"plan";"task";"worker";"integration_owner"];
 need(integer"attempt"j>0&&integer"integration_epoch"j>0)"INTENT_ATTEMPT";j
let task_fence cfg request=
 need(text"integration_owner"request=text"owner"cfg&&integer"integration_epoch"request=integer"epoch"cfg)"INTEGRATION_OWNER_EPOCH";
 let db=ok(S.open_existing(text"tasks"cfg))in
 let observed=Fun.protect ~finally:(fun()->S.close db)(fun()->
  let tasks=ok(S.list_task_observations db ~plan_id:(text"plan"request))in
  need(List.length tasks=1)"PRIVATE_SINGLE_TASK_FIXTURE";
  match List.find_opt(fun o->o.S.task.id=text"task"request)tasks with Some t->t|_->raise(Hold"TASK_ABSENT"))in
 let task=observed.S.task in
 let now=Int64.of_float(Unix.gettimeofday()*.1e9)in
 need(task.state="executing"&&task.worker=Some(text"worker"request)&&task.attempt=integer"attempt"request&&
  match observed.lease_until_ns with Some deadline->deadline>Int64.add now 1000000000L|_->false)"TASK_LEASE_FENCE";
 need(observed.dependencies=[])"TASK_DEPENDENCY_UNIMPLEMENTED";
 now
let facts cfg request=
 let directory=text"directory"cfg and repository=text"repository"cfg in
 let _=task_fence cfg request in
 need(main directory repository=text"expected_main"request&&operation directory repository=text"expected_operation"request)"REVISION_OPERATION_CAS";
 need(clean directory repository)"DIRTY_WORKSPACE";
 let candidate=text"candidate"request in
 need(query directory repository["log";"--no-graph";"-r";candidate^" & conflicts()";"-T";"commit_id"]="")"CANDIDATE_CONFLICT";
 need(query directory repository["diff";"--from";candidate;"--to";"@";"-T";"path ++ \"\\n\""]="")"WORKSPACE_CANDIDATE_TREE";
 need(query directory repository["log";"--no-graph";"-r";candidate^" & descendants("^text"expected_main"request^")";"-T";"commit_id"]=candidate)"CANDIDATE_NOT_DESCENDANT";
 let manifest=read(text"manifest"cfg)in need(sha manifest=text"manifest_sha256"request)"MANIFEST_PIN";
 let members=Yojson.Basic.Util.to_list(json manifest)in need(List.length members>0&&List.length members<=32)"MANIFEST_BOUND";
 let paths=List.map(fun m->closed["path";"sha256"]m;let p=text"path"m in need(hex 64(text"sha256"m))"MANIFEST_HASH";p)members in
 need(List.length(List.sort_uniq compare paths)=List.length paths)"MANIFEST_DUPLICATE";
 let changed=query directory repository["diff";"--from";text"expected_main"request;"--to";candidate;"-T";"path ++ \"\\n\""]in
 let changed=if changed=""then[]else String.split_on_char '\n'changed in
 need(List.length changed<=32&&List.sort compare paths=List.sort compare changed)"MANIFEST_COVERAGE";
 List.iter(fun m->let path=text"path"m in
  need(not(Filename.is_relative path=false)&&not(List.exists(fun p->p=""||p="."||p="..")(String.split_on_char '/'path)))"SOURCE_PATH";
  need(sha(file directory repository candidate path)=text"sha256"m)"CANDIDATE_INCOMPLETE")members;
 let evidence key=let bytes=read(text key cfg)in need(sha bytes=text(key^"_sha256")request)"EVIDENCE_PIN";
  let j=json bytes in need(text"candidate"j=candidate&&text"manifest_sha256"j=text"manifest_sha256"request)"EVIDENCE_CANDIDATE_BINDING";j in
 let review=evidence"review"in closed["domain";"verdict";"candidate";"manifest_sha256"]review;
 need(text"domain"review="uos.jj.fixture-review-observation.v1"&&text"verdict"review="FIXTURE_SOURCE_CHECK_PASS_NOT_INDEPENDENT_NOT_AUTHORITY")"REVIEW_VERDICT";
 let tests=evidence"tests"in closed["domain";"candidate";"manifest_sha256";"exit";"stdout_sha256"]tests;
 need(text"domain"tests="uos.jj.fixture-test-observation.v1"&&integer"exit"tests=0&&text"stdout_sha256"tests=sha"42\n")"TEST_VERDICT";
 need(main directory repository=text"expected_main"request&&operation directory repository=text"expected_operation"request)"FINAL_REVISION_OPERATION_CAS";
 let now=task_fence cfg request in check_deadline();
 encode(`Assoc["profile",s"PRIVATE_FIXTURE_ONLY";"candidate",s candidate;"expected_main",field"expected_main"request;"observed_utc_ns",s(Int64.to_string now)])
let response digest code fact=encode(`Assoc["schema",s"uos.jj.integration-fixture-reply.v1";"code",s code;"intent_sha256",s digest;"fact",s fact;"authority",s"NONE"])
let history receipt digest request=
 let bytes=read receipt in let j=json bytes in
 closed["domain";"intent_sha256";"from";"to";"before_operation";"after_operation";"authority"]j;
 need(text"domain"j="uos.jj.private-integration-committed-fact.v1"&&text"intent_sha256"j=digest&&
  text"from"j=text"expected_main"request&&text"to"j=text"candidate"request&&
  text"before_operation"j=text"expected_operation"request&&hex 128(text"after_operation"j)&&
  text"after_operation"j<>text"before_operation"j&&text"authority"j="NONE")"HISTORICAL_BINDING";bytes
let perform_ff locator cfg request digest receipt=
 let directory=text"directory"cfg and repository=text"repository"cfg in
 (* Exact finite effect: existing bookmark, descendant already validated. This
    is NOT intrinsic JJ CAS. Cooperative exclusive owner is still a premise. *)
 ignore(facts cfg request);
 if text"fault"cfg="kill_before_effect"then Unix.kill(Unix.getpid())Sys.sigkill;
 let before_spawn()=
  if text"fault"cfg="expire_before_spawn"then(
   let db=Sqlite3.db_open ~mode:`NO_CREATE ~uri:false(text"tasks"cfg)in
   Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db);Core.Gc.keep_alive db)(fun()->
    need(Sqlite3.exec db"UPDATE sa_plan_task SET lease_until_ns=1 WHERE id='INTEGRATE'"=Sqlite3.Rc.OK)"FIXTURE_EXPIRE_FAULT"));
  if text"fault"cfg="deadline_before_spawn"then Unix.sleepf 0.12;
  need(encode(config locator)=encode cfg)"FINAL_CONFIGURATION_CAS";
  ignore(task_fence cfg request);check_deadline()in
 if text"fault"cfg="deadline_before_spawn"then active_deadline:=Int64.add(mono())100000000L;
 ignore(run ~before_spawn directory(common repository@["bookmark";"move";"exact:main";"--from";text"expected_main"request;"--to";text"candidate"request]));
 if text"fault"cfg="kill_after_effect"then Unix.kill(Unix.getpid())Sys.sigkill;
 need(main directory repository=text"candidate"request&&clean directory repository)"POSTSTATE_UNKNOWN";
 let operations=query directory repository["op";"log";"--no-graph";"-n";"2";"-T";"id ++ \"\\n\""]|>String.split_on_char '\n'in
 let after=match operations with [after;before] when hex 128 after&&before=text"expected_operation"request&&after<>before->after|_->raise(Hold"OPERATION_ANCESTRY_UNKNOWN")in
 let bytes=encode(`Assoc["domain",s"uos.jj.private-integration-committed-fact.v1";"intent_sha256",s digest;
 "from",field"expected_main"request;"to",field"candidate"request;"before_operation",field"expected_operation"request;
 "after_operation",s after;"authority",s"NONE"])in
 durable receipt bytes;
 if text"fault"cfg="kill_after_receipt"then Unix.kill(Unix.getpid())Sys.sigkill;
 history receipt digest request
let handle locator bytes=
 active_deadline:=Int64.add(mono())12000000000L;
 let digest=ref(String.make 64 '0')in
 try
 let envelope=json bytes in closed["operation";"intent"]envelope;
 let raw=text"intent"envelope in let request=intent raw in digest:=sha raw;
 let cfg=config locator and op=text"operation"envelope in
 let control=text"control"cfg in let stem=control^"/"^ !digest in
 let pending=stem^".pending"and consumed=stem^".consumed"and receipt=stem^".receipt"in
 let lock=Unix.openfile(control^"/integration.lock")[Unix.O_RDWR;Unix.O_CREAT;Unix.O_CLOEXEC]0o600 in
 Fun.protect ~finally:(fun()->Unix.close lock)(fun()->
  (try Unix.lockf lock Unix.F_TLOCK 0 with Unix.Unix_error _->raise(Hold"INTEGRATION_BUSY"));
  match op with
  |"history"->if exists receipt then response !digest"HISTORICAL"(history receipt !digest request)else response !digest"RECONCILE_ONLY"""
  |"inspect"->response !digest"PREFLIGHT_DATA"(facts cfg request)
  |"reserve"->if exists receipt then response !digest"HISTORICAL"(history receipt !digest request)
    else if exists pending then(need(read pending=raw)"PENDING_CONFLICT";response !digest"RECONCILE_ONLY""")
    else(let fact=facts cfg request in
     need(Array.length(Sys.readdir control)<64)"CONTROL_CAPACITY";
     let logical=control^"/logical-"^sha(text"logical_id"request)in
     if exists logical then need(read logical=raw)"LOGICAL_ID_CONFLICT"else durable logical raw;
     durable pending raw;
     if text"fault"cfg="block_reserve"then(
      durable(control^"/reserve-ready")"actual pending durable; native reserve blocked";
      let rec blocked()=check_deadline();if not(exists(control^"/release-reserve"))then(Unix.sleepf 0.005;blocked())in blocked());
     response !digest"PENDING_CREATED"fact)
  |"fast_forward"->
   need(exists pending&&read pending=raw)"PENDING_REQUIRED";
   if exists receipt then response !digest"HISTORICAL"(history receipt !digest request)
   else if exists consumed then response !digest"RECONCILE_ONLY"""
   else(let _=facts cfg request in durable consumed raw;
    (* After consumed, ALL refusal/error is unknown: a JJ write might exist. *)
    try response !digest"INTEGRATED"(perform_ff locator cfg request !digest receipt)
    with _->response !digest"UNKNOWN""")
  |_->raise(Hold"UNKNOWN_OPERATION"))
 with Hold code->response !digest("REFUSED_"^code)""|_->response !digest"UNKNOWN"""
