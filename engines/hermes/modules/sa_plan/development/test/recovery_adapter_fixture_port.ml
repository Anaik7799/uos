
(* Ordinary-only private helper. No fault/swap/expiry/concurrent operations. *)
module P=Recovery_adapter_prepare
module S=Sa_plan.Store
module K=Recovery_kernel
let need=P.need
let ok=P.ok
let text=P.text
(* Retained for process lifetime, not unlocked after constructing a reply.
   This is cooperative fixture bookkeeping, NOT a guardian cleanup witness. *)
let marker_lock : Unix.file_descr option ref=ref None
let claim_marker marker=
 let fd=Unix.openfile marker[Unix.O_RDWR;Unix.O_CREAT;Unix.O_CLOEXEC]0o600 in
 try
  let st=Unix.fstat fd and path=Unix.lstat marker in
  need(st.Unix.st_kind=Unix.S_REG&&st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_nlink=1&&st.Unix.st_perm land 0o077=0
   &&st.Unix.st_dev=path.Unix.st_dev&&st.Unix.st_ino=path.Unix.st_ino)"marker metadata";
  Unix.lockf fd Unix.F_TLOCK 0;
  Unix.ftruncate fd 0;
  let pid=string_of_int(Unix.getpid())in
  let rec put at=if at<String.length pid then let n=Unix.write_substring fd pid at(String.length pid-at)in
   need(n>0)"marker short write";put(at+n)in put 0;Unix.fsync fd;marker_lock:=Some fd
 with e->Unix.close fd;raise e
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
 let effect_boundary_begun=ref false in
 let body=try
  need(Array.length Sys.argv=2)"one private locator argument";
  let h=really_input_string stdin 4 in let n=ref 0 in String.iter(fun c->n:=(!n lsl 8)lor Char.code c)h;
  need(!n>0&& !n<=65536)"frame";let body=really_input_string stdin !n in
  (try ignore(input_char stdin);failwith"trailing"with End_of_file->());
  let locator=Sys.argv.(1)in let j=Bounded.json_text body in let op=text j"operation"in
  if op="commit"||op="inspect"then(
   let dir=Filename.dirname locator in directory dir;
   (* Same inode is locked before truncation/write, never replaced or unlinked.
      Other cooperating workers cannot overwrite the live owner's marker.
      Actual subsequent I/O still requires the paired guardian reaping result. *)
   claim_marker(dir^"/worker.pid");
   effect_boundary_begun:=true;
   let r=ok(Recovery_adapter.handle_private_data~locator~request:body)in
   if not(Sys.file_exists(dir^"/bound-observation.json"))then P.write(dir^"/bound-observation.json")
    (Yojson.Safe.to_string(`Assoc["sqlite_version",`String(Sqlite3.sqlite_version_info());"diagnostics",r.diagnostics]));
   r.reply)
  else(
   need(List.mem op["prepare";"observe";"probe";"probe_pending";"resource_receipt";"bound_observation";"signed_physical"])"ordinary-only mode";
   need(P.fixture_persist())"private persistent WAL initialization";
   let result=if op="prepare"then(effect_boundary_begun:=true;P.prepare(P.json locator)(Yojson.Basic.Util.to_int(P.field j"value")))else helper locator op in
   Yojson.Basic.to_string result)
 with _->if !effect_boundary_begun then
  "{\"schema\":\"uos.recovery-adapter.factual.v1\",\"status\":\"UNKNOWN\",\"code\":\"OUTCOME_OR_OBSERVATION_UNKNOWN\",\"authority\":\"NONE\",\"application_admitted\":false,\"system_admitted\":false,\"receipt\":null}"
 else "{\"schema\":\"uos.recovery-adapter.factual.v1\",\"status\":\"HOLD\",\"code\":\"PRIVATE_REFUSED\",\"authority\":\"NONE\",\"application_admitted\":false,\"system_admitted\":false,\"receipt\":null}"in
 let n=String.length body in for i=3 downto 0 do output_char stdout(Char.chr((n lsr(8*i))land 255))done;
 output_string stdout body;flush stdout
