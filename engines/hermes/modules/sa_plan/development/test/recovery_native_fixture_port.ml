
(* Ordinary-only private helper. No fault/swap/expiry/concurrent operations. *)
module P=Recovery_native_prepare
module S=Sa_plan.Store
module K=Recovery_kernel
let need=P.need
let ok=P.ok
let text=P.text
let directory dir=
 need(String.starts_with~prefix:"/tmp/uos-control-private-"dir&&Filename.dirname dir="/tmp"&&Unix.realpath dir=dir)"private directory";
 let st=Unix.lstat dir in need(st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_perm land 0o077=0)"private owner"
let helper dir op=
 directory dir;
 match op with
 |"observe"->let store=ok(S.open_existing(dir^"/tasks.sqlite3"))in
  Fun.protect~finally:(fun()->S.close store)(fun()->`List(List.map(fun(id,_)->
   match ok(S.find_task store~plan_id:K.fixed_plan~id_or_name:id)with Some t->`Int t.S.attempt|_->`Null)K.fixed_members))
 |"bound_observation"->P.json(dir^"/bound-observation.json")
 |"signed_physical"->P.field(P.json(dir^"/checker.json"))"physical_sqlite"
 |"resource_receipt"->P.with_db(dir^"/tasks.sqlite3")(fun db->
  `Bool(P.control_lookup db"private-control-request"(text(P.json(dir^"/locator.json"))"binding")))
 |"probe"|"probe_pending"->
  if Sys.file_exists(dir^"/worker.pid")then(
   let pid=int_of_string(String.trim(P.read(dir^"/worker.pid")))in
   need(pid>1&&pid<>Unix.getpid())"PID";`Bool(not(Sys.file_exists("/proc/"^string_of_int pid))))else
  P.with_db(dir^"/owner.sqlite3")(fun db->let st=Sqlite3.prepare db"SELECT record_json FROM recovery_owner_event ORDER BY sequence LIMIT 2"in
   Fun.protect~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st;Core.Gc.keep_alive db)(fun()->match Sqlite3.step st with
   |Sqlite3.Rc.DONE->`Bool true
   |Sqlite3.Rc.ROW when op="probe_pending"->let j=Bounded.json_text(Sqlite3.column_text st 0)in `Bool(text j"phase"="pending"&&Sqlite3.step st=Sqlite3.Rc.DONE)
   |_->`Bool false))
 |_->failwith"ordinary helper operation only"

let ()=
 let begun=ref false in
 let body=try
  need(Array.length Sys.argv=2)"one private data locator";
  let h=really_input_string stdin 4 in let n=ref 0 in String.iter(fun c->n:=(!n lsl 8)lor Char.code c)h;
  need(!n>0&& !n<=65536)"frame";let bytes=really_input_string stdin !n in
  (try ignore(input_char stdin);failwith"trailing"with End_of_file->());
  let j=Bounded.json_text bytes in let op=text j"operation"in let loc=Sys.argv.(1)in
  let result=match op with
  |"draft"->begun:=true;P.draft(P.json loc)(Yojson.Basic.Util.to_int(P.field j"value"))
  |"finalize"->begun:=true;P.finalize loc(P.field j"facts")
  |"prepared"->directory(Filename.dirname loc);let p=P.json loc in
   need(text p"signature_source"="FOUR_GUARDED_NATIVE_V2_DETACHED_FACTS")"native signature provenance";p
  |"observe"|"probe"|"probe_pending"|"resource_receipt"|"bound_observation"|"signed_physical"->
   need(P.fixture_persist())"private persistent WAL observation";helper loc op
  |_->failwith"ordinary native signer integration operation only"in
  Yojson.Basic.to_string result
 with error->
  let code=match error with
  |Unix.Unix_error(Unix.EUNKNOWNERR 122,_,_)->"PRIVATE_RESOURCE_QUOTA_OUTCOME_UNKNOWN"
  |Unix.Unix_error(Unix.ENOSPC,_,_)->"PRIVATE_RESOURCE_SPACE_OUTCOME_UNKNOWN"
  |Sys_error message when String.ends_with~suffix:"Disk quota exceeded"message->"PRIVATE_RESOURCE_QUOTA_OUTCOME_UNKNOWN"
  |Sys_error message when String.ends_with~suffix:"No space left on device"message->"PRIVATE_RESOURCE_SPACE_OUTCOME_UNKNOWN"
  |_->if !begun then"PRIVATE_OUTCOME_UNKNOWN"else"PRIVATE_REFUSED"in
  Yojson.Basic.to_string(`Assoc["status",`String(if !begun then"UNKNOWN"else"HOLD");"authority",`String"NONE";"code",`String code])in
 let n=String.length body in for i=3 downto 0 do output_char stdout(Char.chr((n lsr(8*i))land 255))done;
 output_string stdout body;flush stdout
