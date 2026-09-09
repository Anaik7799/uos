(* Native tests link the exact production source after removing only interpreter
   directives and the one CLI entrypoint. No live ledger or network is used. *)
open Ecology_budget

let checks=ref 0
let check name truth=if not truth then failwith("TEST FAILED: "^name);incr checks
let base=1_788_921_600_000_000L
let directory=Sys.argv.(2)
let cli_path=Sys.argv.(1)
let path name=Filename.concat directory name
let write path text=let ch=open_out_bin path in Fun.protect ~finally:(fun()->close_out ch)(fun()->output_string ch text)
let read path=let ch=open_in_bin path in Fun.protect ~finally:(fun()->close_in ch)(fun()->really_input_string ch(in_channel_length ch))
let fresh name=get_ok(Persistent.initialize ~now:base(path name))
let member key value=Yojson.Safe.Util.member key value
let text key value=Yojson.Safe.Util.to_string(member key value)
let count key value=Yojson.Safe.Util.to_int(member key value)
let grant value=member "dispatch_authorized" value=`Bool true
let reason expected value=not(grant value) && text "reason" value=expected
let next_file=ref 0
let children=ref []
let spawn ?gate args input =
  incr next_file;
  let stem=path("process-"^string_of_int !next_file) in
  write(stem^".in")input;
  let input_fd=Unix.openfile(stem^".in")[Unix.O_RDONLY]0 in
  let output_fd=Unix.openfile(stem^".out")[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in
  let pid=Unix.fork() in
  if pid=0 then (try
    (match gate with None->()|Some fd->let b=Bytes.create 1 in ignore(Unix.read fd b 0 1);Unix.close fd);
    Unix.dup2 input_fd Unix.stdin;Unix.dup2 output_fd Unix.stdout;Unix.dup2 output_fd Unix.stderr;
    Unix.close input_fd;Unix.close output_fd;
    Unix.execve cli_path(Array.of_list(cli_path::args))(Unix.environment())
  with _->Unix._exit 126);
  Unix.close input_fd;Unix.close output_fd;children:=pid::!children;pid,stem^".out"
let collect(pid,output)=
  let _,status=Unix.waitpid [] pid in children:=List.filter((<>)pid)!children;
  let body=read output in
  (match status with Unix.WEXITED n->n|_->125),Yojson.Safe.from_string body
let run args input=collect(spawn args input)
let request id=Printf.sprintf {|{"call_id":%S,"model":"moonshotai/kimi-k3","max_tokens":4096,"input_bytes":16384,"body_bytes":20000}|} id
let reserve db id=run["reserve";db](request id)
let race db ids =
  let r,w=Unix.pipe ~cloexec:true () in
  let launched=List.map(fun id->spawn ~gate:r ["reserve";db](request id))ids in
  Unix.close r;
  let signal=Bytes.make(List.length ids)'x' in ignore(Unix.write w signal 0(Bytes.length signal));Unix.close w;
  List.map collect launched

let shared_laws () =
  let module O=Make_laws(Oracle) in let module P=Make_laws(Persistent) in
  let oracle=O.run "oracle" and persistent=P.run(path "laws.sqlite3") in
  checks:= !checks+oracle+persistent;
  check "invalid initial clock does not create a ledger" (Persistent.initialize ~now:(-1L)(path "badclock.sqlite3")=Error Invalid_clock && not(Sys.file_exists(path "badclock.sqlite3")));
  Printf.printf "shared_laws oracle=%d sqlite=%d\n%!" oracle persistent

let differential () =
  let rng=Random.State.make[|20260909|] in
  let o=ref(get_ok(Oracle.initialize ~now:base "differential")) in
  let p=ref(fresh "differential.sqlite3") in
  for step=0 to 127 do
    let day=step/48 in
    let offset=if Random.State.int rng 8=0 then -1000 else step*10 in
    let now=Int64.add base(Int64.add(Int64.mul(Int64.of_int day)86_400_000_000L)(Int64.of_int offset)) in
    let id="seeded-"^string_of_int(Random.State.int rng 45) in
    let request=fixture id in
    let lhs=Oracle.reserve ~now !o request and rhs=Persistent.reserve ~now !p request in
    (match lhs,rhs with
      | Ok(next_o,a),Ok(next_p,b)->o:=next_o;p:=next_p;check "observational trace homomorphism" (a=b)
      | Error a,Error b->check "observational rejection homomorphism" (a=b)
      | _->failwith "oracle/storage divergence");
    check "status observational agreement" (Oracle.observe ~now !o=Persistent.observe ~now !p)
  done;
  Printf.printf "differential seed=20260909 steps=128 observations=256\n%!"

let sql_negative_cases () =
  let ledger=fresh "append.sqlite3" in
  ignore(get_ok(Persistent.reserve ~now:base ledger(fixture "held")));
  let db=Sqlite3.db_open ~mode:`NO_CREATE ledger in
  let denied sql=check("raw SQL refuses "^sql)(Sqlite3.exec db sql<>Sqlite3.Rc.OK) in
  List.iter denied[
    "UPDATE reservations SET amount_nd=0";
    "DELETE FROM reservations";
    "UPDATE budget_meta SET initialized_us=0";
    "DELETE FROM budget_meta";
    "INSERT OR REPLACE INTO budget_meta SELECT * FROM budget_meta";
    "INSERT OR REPLACE INTO reservations SELECT * FROM reservations";
    "INSERT INTO reservations SELECT NULL,utc_day,observed_us,model,max_tokens,input_bytes,body_bytes,worst_case_nd,amount_nd FROM reservations LIMIT 1";
    "INSERT INTO reservations SELECT 'bad/id',utc_day,observed_us,model,max_tokens,input_bytes,body_bytes,worst_case_nd,amount_nd FROM reservations LIMIT 1";
    "INSERT INTO reservations SELECT 'fraction',utc_day,observed_us,model,1.5,input_bytes,body_bytes,(input_bytes+2048)*3000+1.5*15000,amount_nd FROM reservations LIMIT 1";
    "INSERT INTO reservations SELECT 'bad-model',utc_day,observed_us,'unknown',max_tokens,input_bytes,body_bytes,worst_case_nd,amount_nd FROM reservations LIMIT 1";
    "INSERT INTO reservations SELECT 'rollback',utc_day,observed_us-1,model,max_tokens,input_bytes,body_bytes,worst_case_nd,amount_nd FROM reservations LIMIT 1"
  ];
  check "failed falsifiers preserve liability" ((get_ok(Persistent.observe ~now:base ledger)).reserved=reservation);
  ignore(Sqlite3.exec db "DROP TRIGGER reservations_no_update");
  ignore(Sqlite3.db_close db);
  check "removed trigger fails schema validation" (Persistent.reserve ~now:base ledger(fixture "unsafe")=Error Corrupt_ledger);
  check "missing reserve cannot create" (Persistent.reserve ~now:base(path "absent.sqlite3")(fixture "x")=Error Missing_ledger && not(Sys.file_exists(path "absent.sqlite3")));
  check "missing status cannot create" (Persistent.observe ~now:base(path "absent.sqlite3")=Error Missing_ledger);
  write(path "garbage.sqlite3")"not sqlite";
  check "corrupt ledger denied" (Persistent.observe ~now:base(path "garbage.sqlite3")=Error Corrupt_ledger);
  check "corrupt ledger cannot be reinitialized" (Persistent.initialize ~now:base(path "garbage.sqlite3")=Error Ledger_exists);
  Unix.symlink ledger(path "link.sqlite3");
  check "symlink ledger denied" (Persistent.observe ~now:base(path "link.sqlite3")=Error Corrupt_ledger);
  let sidecar=fresh "sidecar.sqlite3" in
  Unix.symlink ledger(sidecar^"-wal");
  check "symlink WAL denied" (Persistent.observe ~now:base sidecar=Error Corrupt_ledger);
  let oversized=fresh "oversized.sqlite3" in
  Unix.truncate oversized(32*1024*1024+1);
  check "oversized DB denied before SQLite open" (Persistent.observe ~now:base oversized=Error Resource_bound);
  let empty=fresh "truncated.sqlite3" in Unix.truncate empty 12;
  check "truncated ledger denied" (Persistent.observe ~now:base empty=Error Corrupt_ledger);
  let locked=fresh "locked.sqlite3" in
  let lock=Sqlite3.db_open locked in ignore(Sqlite3.exec lock "BEGIN IMMEDIATE");
  let before=mono() in
  check "contended database denies within busy timeout" (Persistent.reserve ~now:base locked(fixture "locked")=Error Ledger_busy && mono() -. before<2.5);
  ignore(Sqlite3.exec lock "ROLLBACK");ignore(Sqlite3.db_close lock)

let public_cli_cases () =
  let missing=path "cli-missing.sqlite3" in
  let code,result=run["status";missing]"" in
  check "CLI missing state fails closed" (code=1 && reason "ledger_missing" result && not(Sys.file_exists missing));
  let db=path "cli.sqlite3" in
  let code,initialized=run["init";db]"" in
  check "explicit CLI initialization grants no dispatch" (code=0 && not(grant initialized));
  let code,first=reserve db "durable" in
  check "fresh reservation authorizes exactly one budget dispatch" (code=0 && grant first && count "reservation_count" first=1);
  check "scope and liability truth" (text "budget_scope" first="this_database_only" && text "ledger_path" first=db && member "actual_spend_nanodollars" first=`Null && member "task_authority" first=`Bool false);
  let code,duplicate=reserve db "durable" in
  check "separate process retry cannot grant again" (code=1 && reason "duplicate_call_id" duplicate);
  let code,status=run["status";db]"" in
  check "separate process reopen observes held liability" (code=0 && count "reservation_count" status=1 && member "daily_reserved_nanodollars" status=`Int 250000000 && not(grant status));
  let malformed=["";"[]";"{";String.make 4097 'x';
    {|{"call_id":"x","call_id":"x","model":"z-ai/glm-5.3","max_tokens":1,"input_bytes":0,"body_bytes":1}|};
    {|{"call_id":"x","model":"z-ai/glm-5.3","max_tokens":1,"input_bytes":0,"body_bytes":1,"now":0}|};
    {|{"call_id":"x","model":"z-ai/glm-5.3","max_tokens":1.0,"input_bytes":0,"body_bytes":1}|};
    {|{"call_id":"x","model":"z-ai/glm-5.3","max_tokens":4097,"input_bytes":0,"body_bytes":1}|};
    {|{"call_id":"x","model":"unknown","max_tokens":1,"input_bytes":0,"body_bytes":1}|};
    {|{"call_id":"bad/id","model":"z-ai/glm-5.3","max_tokens":1,"input_bytes":0,"body_bytes":1}|};
    {|{"call_id":"x","model":"z-ai/glm-5.3","max_tokens":1,"input_bytes":-1,"body_bytes":1}|}
  ] in
  List.iter(fun body->let code,response=run["reserve";db]body in check "malformed CLI input never grants"(code=1 && reason "invalid_request" response))malformed;
  let _,after=run["status";db]"" in
  check "invalid calls do not append" (count "reservation_count" after=1);
  let future=Int64.add(host_now())86_400_000_000L in
  let future_db=get_ok(Persistent.initialize ~now:future(path "future.sqlite3")) in
  let code,response=run["status";future_db]"" in
  check "public CLI rejects persisted future clock" (code=1 && reason "clock_rollback" response)

let concurrency () =
  let now=Int64.sub(host_now())1_000_000L in
  let cap=get_ok(Persistent.initialize ~now(path "cap-race.sqlite3")) in
  for i=1 to 38 do ignore(get_ok(Persistent.reserve ~now cap(fixture("prefill-"^string_of_int i)))) done;
  let outcomes=race cap(List.init 8(fun i->"contender-"^string_of_int i)) in
  let grants=List.filter(fun(code,j)->code=0 && grant j)outcomes |> List.length in
  let denied=List.filter(fun(code,j)->code=1 && reason "budget_exhausted" j)outcomes |> List.length in
  check "8-process final-slot race grants 2 denies 6" (grants=2 && denied=6);
  let _,after=run["status";cap]"" in
  check "8-process final-slot race preserves exactly $10" (count "reservation_count" after=40 && member "daily_reserved_nanodollars" after=`Int 10000000000);
  let duplicate=get_ok(Persistent.initialize ~now(path "duplicate-race.sqlite3")) in
  let outcomes=race duplicate(List.init 8(fun _->"same-call")) in
  let grants=List.filter(fun(code,j)->code=0 && grant j)outcomes |> List.length in
  let denied=List.filter(fun(code,j)->code=1 && reason "duplicate_call_id" j)outcomes |> List.length in
  check "8-process duplicate race grants 1 denies 7" (grants=1 && denied=7);
  Printf.printf "concurrency processes=8 final_slots=2 grants=2 exhausted=6 duplicate_grants=1 duplicate_denied=7\n%!"

(* Discriminating mutations run the same public law suite. *)
module Mutant_cap : STORE = struct
  type t=int
  let initialize ~now:_ _=Ok 0
  let snap now count=let t=get_ok(time now) in {utc_day=t.day;reserved=Int64.mul(Int64.of_int count)reservation;count;observed_us=now}
  let observe ~now t=Ok(snap now t)
  let reserve ~now t _=Ok(t+1,snap now(t+1))
end
module Mutant_duplicate : STORE = struct
  include Oracle
  let reserve ~now t r=match Oracle.reserve ~now t r with
    | Error Duplicate_call_id -> let observation=get_ok(Oracle.observe ~now t) in Ok(t,observation)
    | other->other
end
module Mutant_clock : STORE = struct
  include Oracle
  let observe ~now t=match Oracle.observe ~now t with
    | Error Clock_rollback->let at=get_ok(time now) in Ok{utc_day=at.day;reserved=0L;count=0;observed_us=now}
    | other->other
end
let mutants () =
  let rejects name run=check("law suite kills "^name)(try ignore(run());false with Failure _->true) in
  let module C=Make_laws(Mutant_cap) in rejects "cap-removal"(fun()->C.run "mutant");
  let module D=Make_laws(Mutant_duplicate) in rejects "duplicate-grant"(fun()->D.run "mutant");
  let module T=Make_laws(Mutant_clock) in rejects "rollback-ignore"(fun()->T.run "mutant")

let () =
  Sys.set_signal Sys.sigalrm(Sys.Signal_handle(fun _->List.iter(fun pid->try Unix.kill pid Sys.sigkill with _->())!children;failwith "test deadline"));
  ignore(Unix.alarm 25);
  shared_laws();differential();sql_negative_cases();public_cli_cases();concurrency();mutants();
  ignore(Unix.alarm 0);
  Printf.printf "{\"status\":\"PASS\",\"checks\":%d,\"seed\":20260909,\"trace_steps\":128,\"race_processes\":8,\"mutants_killed\":3,\"network_calls\":0,\"sqlite_version\":%S,\"budget_scope\":\"scratch_database_only\"}\n%!" !checks(Sqlite3.sqlite_version_info())
