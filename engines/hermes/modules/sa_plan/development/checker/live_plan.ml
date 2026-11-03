(* Read-only Sa-plan observation; no schema creation, claim, completion or priority writes. *)
open Priority
type task = { id:string; state:string; worker:string option; lease:int64 option;
  attempt:int; completed:int64 option; result_present:bool; dependencies:string list }
let ok rc = require (rc=Sqlite3.Rc.OK) "Sa-plan read-only query failed"
let optional_text = function Sqlite3.Data.NULL->None | Sqlite3.Data.TEXT s->Some s
  | _->raise (Invalid "invalid Sa-plan text column")
let optional_int = function Sqlite3.Data.NULL->None | Sqlite3.Data.INT n->Some n
  | _->raise (Invalid "invalid Sa-plan integer column")
let text s i = match Sqlite3.column s i with Sqlite3.Data.TEXT t->t
  | _->raise (Invalid "invalid Sa-plan text")
let number s i = match Sqlite3.column s i with Sqlite3.Data.INT n->n
  | _->raise (Invalid "invalid Sa-plan integer")
let read ~path ~plan =
  require ((Unix.lstat path).Unix.st_kind=Unix.S_REG) "Sa-plan database must exist as a regular file";
  let db=Sqlite3.db_open ~mode:`READONLY ~uri:false ~mutex:`FULL path in
  Fun.protect ~finally:(fun ()->ignore (Sqlite3.db_close db)) (fun ()->
    Sqlite3.busy_timeout db 500;
    ok (Sqlite3.exec db "PRAGMA query_only=ON");
    ok (Sqlite3.exec db "BEGIN");
    let rows sql parse =
      let stmt=Sqlite3.prepare db sql in
      Fun.protect ~finally:(fun ()->ignore (Sqlite3.finalize stmt)) (fun ()->
        ok (Sqlite3.bind_text stmt 1 plan);
        let rec loop acc = match Sqlite3.step stmt with
          | Sqlite3.Rc.ROW -> loop (parse stmt::acc)
          | Sqlite3.Rc.DONE -> List.rev acc
          | _ -> raise (Invalid "Sa-plan query unavailable/schema incompatible") in
        loop []) in
    let tasks=rows
      "SELECT id,state,worker,lease_until_ns,attempt,completed_at_ns,result IS NOT NULL FROM sa_plan_task WHERE plan_id=? ORDER BY id LIMIT 1001"
      (fun s->
        let attempt=number s 4 in
        require (attempt>=0L && attempt<=1000000L) "invalid Sa-plan attempt";
        {id=text s 0;state=text s 1;worker=optional_text (Sqlite3.column s 2);
         lease=optional_int (Sqlite3.column s 3);attempt=Int64.to_int attempt;
         completed=optional_int (Sqlite3.column s 5);result_present=number s 6=1L;dependencies=[]}) in
    require (tasks<>[] && List.length tasks<=1000) "empty/missing/oversize Sa-plan plan";
    let deps=rows
      "SELECT task_id,dependency_id FROM sa_plan_dependency WHERE plan_id=? ORDER BY task_id,dependency_id LIMIT 10001"
      (fun s->text s 0,text s 1) in
    require (List.length deps<=10000) "Sa-plan edge budget exceeded";
    let ids=List.map (fun t->t.id) tasks in
    List.iter (fun (a,b)->require (List.mem a ids && List.mem b ids) "orphan Sa-plan dependency") deps;
    let tasks=List.map (fun t->
      {t with dependencies=List.filter_map (fun (a,b)->if a=t.id then Some b else None) deps}) tasks in
    ok (Sqlite3.exec db "ROLLBACK");
    tasks)
let to_json t =
  let opt f=function None->`Null | Some v->f v in
  `Assoc ["task_id",`String t.id;"state",`String t.state;
    "worker",opt (fun s->`String s) t.worker;
    "lease_until_ns",opt (fun n->`String (Int64.to_string n)) t.lease;
    "attempt",`Int t.attempt;
    "completed_at_ns",opt (fun n->`String (Int64.to_string n)) t.completed;
    "result_present",`Bool t.result_present;
    "dependencies",`List (List.map (fun s->`String s) t.dependencies)]
let digest ts = Bounded.sha256 (Yojson.Basic.to_string (`List (List.map to_json ts)))

(* Pure bridge from the canonical Store projection. No new database reader or
   fallback: consumers must separately establish the observation's provenance.
   Exact key order/types and round-trip bytes prevent normalization from silently
   changing the snapshot that was hashed by Store.recovery_snapshot_readonly. *)
let of_snapshot snapshot =
  let optional parse = function `Null -> None | v -> Some(parse v) in
  let string maximum = function
    | `String s when String.length s>0 && String.length s<=maximum && not(String.contains s '\000')->s
    | _ ->raise(Invalid "canonical snapshot string") in
  let decimal = function
    | `String s ->(try let n=Int64.of_string s in require(Int64.to_string n=s)"canonical snapshot decimal";n
       with _->raise(Invalid "canonical snapshot decimal"))
    | _ ->raise(Invalid "canonical snapshot decimal") in
  let tasks=match snapshot with
    | `List rows when rows<>[] && List.length rows<=1000 ->
      List.map(function
        | `Assoc["task_id",id;"state",state;"worker",worker;"lease_until_ns",lease;
            "attempt",`Int attempt;"completed_at_ns",completed;"result_present",`Bool result_present;
            "dependencies",`List deps] ->
          require(attempt>=0 && attempt<=1000000 && List.length deps<=10000)"canonical snapshot bounds";
          {id=string 200 id;state=string 64 state;worker=optional(string 200)worker;
           lease=optional decimal lease;attempt;completed=optional decimal completed;
           result_present;dependencies=List.map(string 200)deps}
        | _ ->raise(Invalid "canonical snapshot object"))rows
    | _ ->raise(Invalid "canonical snapshot rows") in
  require(`List(List.map to_json tasks)=snapshot)"canonical snapshot roundtrip";
  tasks

