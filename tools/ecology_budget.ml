#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "unix,sqlite3,yojson,mtime.clock";;

(* @agent_intent: Append-only UTC daily liability reservations, never network I/O.
   @laws: fixed USD0.25; <=USD10/day in ONE canonical ledger; call IDs single-use;
   no refunds; clock rollback/missing/corrupt storage deny; liability is not spend.
   SQLite is an evidence interpreter of the pure Gleam policy and event oracle. *)

let daily_limit = 10_000_000_000L
let reservation = 250_000_000L
let max_input_bytes = 16_384
let max_body_bytes = 65_536
let max_tokens = 4096
let template_tokens = 2048

type error = Invalid_request of string | Exhausted | Duplicate_call_id
  | Clock_rollback | Invalid_clock | Missing_ledger | Corrupt_ledger
  | Ledger_exists | Ledger_busy | Ledger_io | Resource_bound

let error_label = function
  | Invalid_request _ -> "invalid_request" | Exhausted -> "budget_exhausted"
  | Duplicate_call_id -> "duplicate_call_id" | Clock_rollback -> "clock_rollback"
  | Invalid_clock -> "invalid_clock" | Missing_ledger -> "ledger_missing"
  | Corrupt_ledger -> "ledger_corrupt" | Ledger_exists -> "ledger_exists"
  | Ledger_busy -> "ledger_busy" | Ledger_io -> "ledger_io"
  | Resource_bound -> "resource_bound"

let ceilings = [
  "z-ai/glm-5.3",(1400,4400);
  "moonshotai/kimi-k3",(3000,15000);
  "deepseek/deepseek-v4-pro-0813",(1320,3960);
  "deepseek/deepseek-v4-flash-0731",(65,180);
  "google/gemma-4-31b-it",(90,340);
  "google/gemma-4-26b-a4b-it",(90,340)]

module type REQUEST = sig
  type t
  val make : call_id:string -> model:string -> max_tokens:int -> input_bytes:int -> body_bytes:int -> (t,error) result
  val call_id : t -> string
  val model : t -> string
  val max_tokens : t -> int
  val input_bytes : t -> int
  val body_bytes : t -> int
  val worst_case : t -> int64
end

module Request : REQUEST = struct
  type t = {id:string; model_id:string; tokens:int; input:int; body:int; worst:int64}
  let call_id r=r.id
  let model r=r.model_id
  let max_tokens r=r.tokens
  let input_bytes r=r.input
  let body_bytes r=r.body
  let worst_case r=r.worst
  let make ~call_id ~model ~max_tokens:tokens ~input_bytes:input ~body_bytes:body =
    let valid_id=String.length call_id>=1 && String.length call_id<=128 &&
      String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'.'|'-'|'_'|':'->true|_->false)call_id in
    if not valid_id then Error(Invalid_request "call_id")
    else if tokens<1 || tokens>4096 then Error(Invalid_request "max_tokens")
    else if input<0 || input>max_input_bytes then Error(Invalid_request "input_bytes")
    else if body<1 || body<input || body>max_body_bytes then Error(Invalid_request "body_bytes")
    else match List.assoc_opt model ceilings with
      | None -> Error(Invalid_request "model")
      | Some(prompt,completion) ->
        let worst=Int64.add(Int64.mul(Int64.of_int(input+2048))(Int64.of_int prompt))
          (Int64.mul(Int64.of_int tokens)(Int64.of_int completion)) in
        if worst>reservation then Error(Invalid_request "price_bound")
        else Ok{id=call_id;model_id=model;tokens;input;body;worst}
end

type time = {us:int64; day:string}
let time us =
  if us<0L || us>8_000_000_000_000_000L then Error Invalid_clock else
  try let tm=Unix.gmtime(Int64.to_float(Int64.div us 1_000_000L)) in
    Ok{us;day=Printf.sprintf "%04d-%02d-%02d" (tm.Unix.tm_year+1900) (tm.Unix.tm_mon+1) tm.Unix.tm_mday}
  with _->Error Invalid_clock

type snapshot = {utc_day:string; reserved:int64; count:int; observed_us:int64}
let remaining snapshot=Int64.sub daily_limit snapshot.reserved

module type STORE = sig
  type t
  val initialize : now:int64 -> string -> (t,error) result
  val observe : now:int64 -> t -> (snapshot,error) result
  val reserve : now:int64 -> t -> Request.t -> (t * snapshot,error) result
end

module Oracle : STORE = struct
  type event = Reserved of time * Request.t
  type t = {initialized:time; events:event list}
  let initialize ~now _locator = match time now with
    | Error e->Error e | Ok initialized->Ok{initialized;events=[]}
  let latest t=List.fold_left(fun last (Reserved(at,_))->Int64.max last at.us)t.initialized.us t.events
  let observe ~now t = match time now with
    | Error e->Error e
    | Ok at when at.us<latest t -> Error Clock_rollback
    | Ok at ->
      let count=List.fold_left(fun count(Reserved(when_,_))->count+(if when_.day=at.day then 1 else 0))0 t.events in
      Ok{utc_day=at.day;reserved=Int64.mul(Int64.of_int count)reservation;count;observed_us=at.us}
  let reserve ~now t request = match observe ~now t,time now with
    | Error e,_ | _,Error e -> Error e
    | Ok observed,Ok at ->
      if List.exists(fun(Reserved(_,r))->Request.call_id r=Request.call_id request)t.events then Error Duplicate_call_id
      else if Int64.add observed.reserved reservation>daily_limit then Error Exhausted
      else let next={t with events=Reserved(at,request)::t.events} in
        match observe ~now next with Error e->Error e|Ok observation->Ok(next,observation)
end
module _ : STORE = Oracle

let get_ok = function Ok x->x|Error e->failwith(error_label e)
let fixture id = get_ok(Request.make ~call_id:id ~model:"moonshotai/kimi-k3" ~max_tokens:4096 ~input_bytes:16384 ~body_bytes:20000)

module Make_laws(S:STORE) = struct
  let run locator =
    let checks=ref 0 in
    let check name truth = if not truth then failwith("LAW FAILED: "^name); incr checks in
    let now=1_788_921_600_000_000L in
    let state=ref(get_ok(S.initialize ~now locator)) in
    check "B8-empty-liability" ((get_ok(S.observe ~now !state)).reserved=0L);
    for index=1 to 40 do
      let next,observation=get_ok(S.reserve ~now:(Int64.add now(Int64.of_int index)) !state(fixture(string_of_int index))) in
      state:=next;
      check "B1-B2-cap-and-fixed-liability" (observation.reserved=Int64.mul(Int64.of_int index)reservation && observation.reserved<=daily_limit)
    done;
    let at=Int64.add now 100L in
    check "B1-forty-first-denied" (match S.reserve ~now:at !state(fixture "41")with Error Exhausted->true|_->false);
    check "B3-duplicate-before-budget-check" (match S.reserve ~now:at !state(fixture "1")with Error Duplicate_call_id->true|_->false);
    check "B4-clock-rollback" (match S.observe ~now !state with Error Clock_rollback->true|_->false);
    let tomorrow=Int64.add now 86_400_000_000L in
    check "B3-cross-day-duplicate" (match S.reserve ~now:tomorrow !state(fixture "1")with Error Duplicate_call_id->true|_->false);
    let next,newday=get_ok(S.reserve ~now:tomorrow !state(fixture "new-day")) in
    state:=next;
    check "B1-UTC-day-reset" (newday.reserved=reservation && remaining newday=Int64.sub daily_limit reservation);
    check "B4-cross-day-rollback" (match S.reserve ~now:at !state(fixture "old-day")with Error Clock_rollback->true|_->false);
    !checks
end

let oracle_selftest () =
  let module L=Make_laws(Oracle) in
  let count=L.run "oracle" in
  let bad_cases=[("",1,0,1);("bad/id",1,0,1);("ok",0,0,1);("ok",4097,0,1);("ok",1,1048577,2000000);("ok",1,5,4);("ok",1,0,4194305)] in
  List.iter(fun(id,tokens,input,body)->match Request.make ~call_id:id ~model:"z-ai/glm-5.3" ~max_tokens:tokens ~input_bytes:input ~body_bytes:body with
    | Error(Invalid_request _)->()|_->failwith "B9 smart constructor accepted invalid input")bad_cases;
  if Request.worst_case(fixture "worst")<>116_736_000L then failwith "price arithmetic";
  `Assoc["status",`String"PASS";"interpretation",`String"immutable_event_oracle";
    "checks",`Int(count+List.length bad_cases+1);"network_calls",`Int 0]

exception Budget_error of error
let fail error=raise(Budget_error error)
let require condition error=if not condition then fail error
let mono ()=Mtime.Span.to_float_ns(Mtime_clock.elapsed()) /. 1e9
let operation_started=mono()
let deadline ()=require(mono() -. operation_started<30.)Resource_bound
let sql_ok = function
  | Sqlite3.Rc.OK | Sqlite3.Rc.DONE -> ()
  | Sqlite3.Rc.BUSY | Sqlite3.Rc.LOCKED -> fail Ledger_busy
  | Sqlite3.Rc.CORRUPT | Sqlite3.Rc.NOTADB | Sqlite3.Rc.SCHEMA -> fail Corrupt_ledger
  | _ -> fail Ledger_io
let exec db sql=deadline();sql_ok(Sqlite3.exec db sql)
let statement db sql values f =
  deadline();let stmt=Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize stmt))(fun()->
    sql_ok(Sqlite3.bind_values stmt values);f stmt)
let rows db sql values = statement db sql values(fun stmt->
  let rec next acc count =
    deadline();require(count<100)Resource_bound;
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> next(Array.init(Sqlite3.column_count stmt)(Sqlite3.column stmt)::acc)(count+1)
    | Sqlite3.Rc.DONE -> List.rev acc
    | code -> sql_ok code;assert false in next [] 0)
let one db sql values=match rows db sql values with [row]->row|_->fail Corrupt_ledger
let db_int = function Sqlite3.Data.INT n->n|_->fail Corrupt_ledger
let db_text = function Sqlite3.Data.TEXT s->s|_->fail Corrupt_ledger

let quoted value="'"^value^"'" (* Only the finite source-owned model constants use this. *)
let price_case side="CASE model "^String.concat " "(List.map(fun(model,prices)->"WHEN "^quoted model^" THEN "^string_of_int(side prices))ceilings)^" ELSE -1 END"
let schema = [
  "budget_meta","CREATE TABLE budget_meta (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL CHECK(version=1), initialized_us INTEGER NOT NULL CHECK(initialized_us>=0 AND initialized_us<=8000000000000000), daily_limit_nd INTEGER NOT NULL CHECK(daily_limit_nd=10000000000), reservation_nd INTEGER NOT NULL CHECK(reservation_nd=250000000)) STRICT";
  "reservations","CREATE TABLE reservations (call_id TEXT PRIMARY KEY NOT NULL CHECK(length(call_id)>=1 AND length(call_id)<=128 AND call_id NOT GLOB '*[^a-zA-Z0-9._:-]*' AND instr(call_id,char(0))=0), utc_day TEXT NOT NULL CHECK(length(utc_day)=10), observed_us INTEGER NOT NULL CHECK(observed_us>=0 AND observed_us<=8000000000000000), model TEXT NOT NULL CHECK(model IN ("^String.concat ","(List.map(fun(model,_)->quoted model)ceilings)^")), max_tokens INTEGER NOT NULL CHECK(max_tokens>=1 AND max_tokens<=4096), input_bytes INTEGER NOT NULL CHECK(input_bytes>=0 AND input_bytes<=1048576), body_bytes INTEGER NOT NULL CHECK(body_bytes>=1 AND body_bytes>=input_bytes AND body_bytes<=4194304), worst_case_nd INTEGER NOT NULL CHECK(worst_case_nd>=0 AND worst_case_nd<=250000000), amount_nd INTEGER NOT NULL CHECK(amount_nd=250000000), CHECK(utc_day IS strftime('%Y-%m-%d',observed_us/1000000,'unixepoch')), CHECK(worst_case_nd=(input_bytes+2048)*("^price_case fst^")+max_tokens*("^price_case snd^"))) STRICT";
  "reservations_day","CREATE INDEX reservations_day ON reservations(utc_day)";
  "reservations_time","CREATE INDEX reservations_time ON reservations(observed_us)";
  "meta_no_update","CREATE TRIGGER meta_no_update BEFORE UPDATE ON budget_meta BEGIN SELECT RAISE(ABORT,'append_only'); END";
  "meta_no_delete","CREATE TRIGGER meta_no_delete BEFORE DELETE ON budget_meta BEGIN SELECT RAISE(ABORT,'append_only'); END";
  "meta_single_insert","CREATE TRIGGER meta_single_insert BEFORE INSERT ON budget_meta WHEN EXISTS(SELECT 1 FROM budget_meta) BEGIN SELECT RAISE(ABORT,'append_only'); END";
  "reservations_no_update","CREATE TRIGGER reservations_no_update BEFORE UPDATE ON reservations BEGIN SELECT RAISE(ABORT,'append_only'); END";
  "reservations_no_delete","CREATE TRIGGER reservations_no_delete BEFORE DELETE ON reservations BEGIN SELECT RAISE(ABORT,'append_only'); END";
  "reservations_no_replace","CREATE TRIGGER reservations_no_replace BEFORE INSERT ON reservations WHEN EXISTS(SELECT 1 FROM reservations WHERE call_id=NEW.call_id) BEGIN SELECT RAISE(ABORT,'duplicate_call_id'); END";
  "reservations_cap","CREATE TRIGGER reservations_cap BEFORE INSERT ON reservations WHEN COALESCE((SELECT SUM(amount_nd) FROM reservations WHERE utc_day=NEW.utc_day),0)+NEW.amount_nd>10000000000 BEGIN SELECT RAISE(ABORT,'budget_exhausted'); END";
  "reservations_clock","CREATE TRIGGER reservations_clock BEFORE INSERT ON reservations WHEN NEW.observed_us<(SELECT initialized_us FROM budget_meta WHERE id=1) OR NEW.observed_us<COALESCE((SELECT MAX(observed_us) FROM reservations),0) BEGIN SELECT RAISE(ABORT,'clock_rollback'); END"]

let normalize_path path =
  require(String.length path>0 && String.length path<=4096 && not(String.contains path '\000'))(Invalid_request "ledger_path");
  require(path<>"" && path<>":memory:")(Invalid_request "ledger_path");
  let parent=Unix.realpath(Filename.dirname path) in
  Filename.concat parent(Filename.basename path)

let regular path =
  let st=try Unix.lstat path with Unix.Unix_error(Unix.ENOENT,_,_)->fail Missing_ledger in
  require(st.Unix.st_kind=Unix.S_REG)Corrupt_ledger;
  require(st.Unix.st_size>=0 && st.Unix.st_size<=32*1024*1024)Resource_bound;
  st

let sidecar_bounds path =
  List.iter(fun(suffix,maximum)->
    try let st=Unix.lstat(path^suffix) in
      require(st.Unix.st_kind=Unix.S_REG)Corrupt_ledger;
      require(st.Unix.st_size<=maximum)Resource_bound
    with Unix.Unix_error(Unix.ENOENT,_,_)->())
    ["-wal",8*1024*1024;"-shm",1024*1024]

let safe_result f = try Ok(f()) with
  | Budget_error error -> Error error
  | Unix.Unix_error(Unix.ENOENT,_,_) -> Error Missing_ledger
  | Sqlite3.Error _ | Sqlite3.SqliteError _ -> Error Corrupt_ledger
  | _ -> Error Ledger_io

let with_db ~write path f =
  let before=regular path in
  sidecar_bounds path;
  let db=Sqlite3.db_open ~mode:(if write then `NO_CREATE else `READONLY) ~uri:false ~mutex:`FULL path in
  Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db))(fun()->
    let after=regular path in
    require(before.Unix.st_dev=after.Unix.st_dev && before.Unix.st_ino=after.Unix.st_ino)Corrupt_ledger;
    Sqlite3.busy_timeout db 1000;
    ignore(Sqlite3.enable_load_extension db false);
    exec db "PRAGMA trusted_schema=OFF";
    exec db "PRAGMA recursive_triggers=ON";
    if write then exec db "PRAGMA synchronous=FULL" else exec db "PRAGMA query_only=ON";
    exec db(if write then "BEGIN IMMEDIATE" else "BEGIN");
    try let result=f db in exec db "COMMIT";result
    with e->ignore(Sqlite3.exec db "ROLLBACK");raise e)

let validate_schema db =
  let actual=rows db "SELECT name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name" []
    |> List.map(fun row->db_text row.(0),String.trim(db_text row.(1))) in
  require(actual=List.sort compare schema)Corrupt_ledger;
  let integrity=one db "PRAGMA integrity_check(1)" [] in
  require(db_text integrity.(0)="ok")Corrupt_ledger;
  let meta=one db "SELECT version,initialized_us,daily_limit_nd,reservation_nd FROM budget_meta WHERE id=1" [] in
  require(db_int meta.(0)=1L && db_int meta.(2)=daily_limit && db_int meta.(3)=reservation)Corrupt_ledger;
  let initialized=db_int meta.(1) in
  let broken=rows db "SELECT utc_day FROM reservations GROUP BY utc_day HAVING SUM(amount_nd)>10000000000 LIMIT 1" [] in
  require(broken=[])Corrupt_ledger;
  initialized

let observe_db db ~now =
  let at=match time now with Ok t->t|Error e->fail e in
  let initialized=validate_schema db in
  let maximum=one db "SELECT COALESCE(MAX(observed_us),0) FROM reservations" [] |> fun row->db_int row.(0) in
  require(now>=initialized && now>=maximum)Clock_rollback;
  let totals=one db "SELECT COALESCE(SUM(amount_nd),0),COUNT(*) FROM reservations WHERE utc_day=?" [Sqlite3.Data.TEXT at.day] in
  let reserved=db_int totals.(0) and count=db_int totals.(1) in
  require(reserved>=0L && reserved<=daily_limit && reserved=Int64.mul count reservation && count<=40L)Corrupt_ledger;
  {utc_day=at.day;reserved;count=Int64.to_int count;observed_us=now}

let reserve_with_clock clock path request = safe_result(fun()->
  let path=normalize_path path in
  with_db ~write:true path(fun db->
    (* Sample the public host clock only after owning the immediate transaction.
       Lock acquisition order must not manufacture apparent clock rollback. *)
    let now=clock() in
    let observation=observe_db db ~now in
    let exists=rows db "SELECT 1 FROM reservations WHERE call_id=?" [Sqlite3.Data.TEXT(Request.call_id request)] in
    require(exists=[])Duplicate_call_id;
    require(Int64.add observation.reserved reservation<=daily_limit)Exhausted;
    statement db "INSERT INTO reservations(call_id,utc_day,observed_us,model,max_tokens,input_bytes,body_bytes,worst_case_nd,amount_nd) VALUES(?,?,?,?,?,?,?,?,?)" [
      Sqlite3.Data.TEXT(Request.call_id request);Sqlite3.Data.TEXT observation.utc_day;Sqlite3.Data.INT now;
      Sqlite3.Data.TEXT(Request.model request);Sqlite3.Data.INT(Int64.of_int(Request.max_tokens request));
      Sqlite3.Data.INT(Int64.of_int(Request.input_bytes request));Sqlite3.Data.INT(Int64.of_int(Request.body_bytes request));
      Sqlite3.Data.INT(Request.worst_case request);Sqlite3.Data.INT reservation
    ](fun stmt->sql_ok(Sqlite3.step stmt));
    path,{observation with reserved=Int64.add observation.reserved reservation;count=observation.count+1}))

module Persistent : STORE with type t=string = struct
  type t=string
  let initialize ~now path = safe_result(fun()->
    (match time now with Ok _->()|Error e->fail e);
    let path=normalize_path path in
    (try ignore(Unix.lstat path);fail Ledger_exists with Unix.Unix_error(Unix.ENOENT,_,_)->());
    let fd=Unix.openfile path [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
    Unix.fsync fd;Unix.close fd;
    let db=Sqlite3.db_open ~mode:`NO_CREATE ~uri:false path in
    Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db))(fun()->
      Sqlite3.busy_timeout db 1000;
      exec db "PRAGMA journal_mode=WAL";exec db "PRAGMA synchronous=FULL";
      exec db "BEGIN IMMEDIATE";
      try List.iter(fun(_,sql)->exec db sql)schema;
        statement db "INSERT INTO budget_meta(id,version,initialized_us,daily_limit_nd,reservation_nd) VALUES(1,1,?,10000000000,250000000)" [Sqlite3.Data.INT now](fun stmt->sql_ok(Sqlite3.step stmt));
        ignore(observe_db db ~now);exec db "COMMIT"
      with e->ignore(Sqlite3.exec db "ROLLBACK");raise e);
    path)
  let observe ~now path = safe_result(fun()->
    let path=normalize_path path in with_db ~write:false path(fun db->observe_db db ~now))
  let reserve ~now path request = reserve_with_clock(fun()->now)path request
end
module _ : STORE = Persistent

let json_int value=`Intlit(Int64.to_string value)
let snapshot_json ~path ~grant ~call_id snapshot = `Assoc[
  "status",`String(if grant then "reserved" else "status");
  "dispatch_authorized",`Bool grant;"task_authority",`Bool false;
  "budget_scope",`String"this_database_only";"ledger_path",`String path;
  "call_id",(match call_id with None->`Null|Some id->`String id);
  "utc_day",`String snapshot.utc_day;"observed_us",json_int snapshot.observed_us;
  "reservation_nanodollars",json_int reservation;"daily_limit_nanodollars",json_int daily_limit;
  "daily_reserved_nanodollars",json_int snapshot.reserved;"remaining_nanodollars",json_int(remaining snapshot);
  "reservation_count",`Int snapshot.count;"actual_spend_nanodollars",`Null;
  "refunds_supported",`Bool false]

let decode_request body = try
  require(String.length body<=4096)(Invalid_request "input_bound");
  let object_=match Yojson.Safe.from_string body with `Assoc pairs->pairs|_->fail(Invalid_request "object") in
  let keys=List.map fst object_ |> List.sort String.compare in
  require(keys=List.sort String.compare["call_id";"model";"max_tokens";"input_bytes";"body_bytes"])(Invalid_request "fields");
  let text key=match List.assoc key object_ with `String s->s|_->fail(Invalid_request key) in
  let number key=match List.assoc key object_ with `Int n->n|_->fail(Invalid_request key) in
  Request.make ~call_id:(text "call_id") ~model:(text "model") ~max_tokens:(number "max_tokens") ~input_bytes:(number "input_bytes") ~body_bytes:(number "body_bytes")
with Budget_error e->Error e|_->Error(Invalid_request "json")

let read_stdin () =
  let buffer=Bytes.create 4097 in
  let rec read offset=deadline();
    require(offset<=4096)(Invalid_request "input_bound");
    let count=input stdin buffer offset (4097-offset) in
    if count=0 then Bytes.sub_string buffer 0 offset else read(offset+count) in
  read 0

let host_now ()=Int64.of_float(Unix.gettimeofday() *. 1e6)
let main () =
  require(Array.length Sys.argv<=3 && Array.for_all(fun arg->String.length arg<=4096 && not(String.contains arg '\000'))Sys.argv)(Invalid_request "argv");
  match Array.to_list Sys.argv with
  | [_;"oracle-selftest"] -> oracle_selftest()
  | [_;"init";path] ->
    let actual=get_ok(Persistent.initialize ~now:(host_now()) path) in
    `Assoc["status",`String"initialized";"dispatch_authorized",`Bool false;"ledger_path",`String actual;"budget_scope",`String"this_database_only"]
  | [_;"status";path] ->
    let actual=normalize_path path in
    let snapshot=get_ok(safe_result(fun()->with_db ~write:false actual(fun db->observe_db db ~now:(host_now())))) in
    snapshot_json ~path:actual ~grant:false ~call_id:None snapshot
  | [_;"reserve";path] ->
    let request=get_ok(decode_request(read_stdin())) in
    let actual,snapshot=get_ok(reserve_with_clock host_now path request) in
    snapshot_json ~path:actual ~grant:true ~call_id:(Some(Request.call_id request)) snapshot
  | _ -> fail(Invalid_request "usage: init DB | reserve DB | status DB | oracle-selftest")

let cli () = try print_endline(Yojson.Safe.to_string(main())) with
  | Budget_error error ->
    print_endline(Yojson.Safe.to_string(`Assoc["status",`String"denied";"dispatch_authorized",`Bool false;"reason",`String(error_label error);
      "detail",(match error with Invalid_request detail->`String detail|_->`Null);"actual_spend_nanodollars",`Null;"task_authority",`Bool false]));exit 1
  | Failure label ->
    print_endline(Yojson.Safe.to_string(`Assoc["status",`String"denied";"dispatch_authorized",`Bool false;"reason",`String label;"actual_spend_nanodollars",`Null;"task_authority",`Bool false]));exit 1
  | _ -> print_endline "{\"status\":\"denied\",\"dispatch_authorized\":false,\"reason\":\"ledger_io\",\"actual_spend_nanodollars\":null,\"task_authority\":false}";exit 1

let () = cli()
