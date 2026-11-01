(* Internal bounded observations only; no signing/provisioning implementation. *)
(* PRIVATE fixture interpreter and test trust. Never linked into production.
   Fixed NONSECRET R/I vectors; no live DB/config/keys. Complete FOUR-row
   synthetic portfolio retains every source reference from the supplied old
   matrix, re-observed from actual candidate bytes. It is NOT a canonical
   main-plan preflight, independent human/model review or production grant. *)
module K=Recovery_kernel
module R=Recovery_resource
module S=Recovery_adapter_store
external fixture_persist : unit -> bool = "caml_uos_control_fixture_persist"
external retained_identity : Unix.file_descr -> (int64*int64)option = "caml_uos_main_mapping_retained_identity"
let need b s=if not b then failwith s
let ok=function Ok x->x|Error _->failwith"fixture validation refused"
let s x=`String x
let read p=Bounded.read ~limit:1048576 p
let write p b=let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in
 let c=Unix.out_channel_of_descr fd in Fun.protect ~finally:(fun()->close_out c)(fun()->output_string c b;flush c;Unix.fsync fd)
let json p=Bounded.json_text(read p)
let field j k=Yojson.Basic.Util.member k j
let text j k=Yojson.Basic.Util.to_string(field j k)
let set j k v=match j with `Assoc fs->`Assoc(List.map(fun(a,b)->a,if a=k then v else b)fs)|_->failwith"object"
let hash p=K.sha256(Bounded.read ~limit:100663296 p)
let capture p=
 let st=Unix.lstat p in need(st.Unix.st_kind=Unix.S_REG&&st.Unix.st_uid=Unix.geteuid()&&st.Unix.st_nlink=1&&st.Unix.st_perm land 0o077=0)"private locator required";
 read p
let physical database=
 `Assoc(List.map(fun(role,suffix)->
   let fd=Unix.openfile(database^suffix)[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
   let device,inode=Fun.protect ~finally:(fun()->Unix.close fd)(fun()->ok(match retained_identity fd with Some x->Ok x|_->Error"identity"))in
   role,`Assoc["device",s(Int64.to_string device);"inode",s(Int64.to_string inode)])
  ["main","";"wal","-wal";"shm","-shm"])
let schema=[
 "control_resource_receipt","CREATE TABLE control_resource_receipt(request_id TEXT PRIMARY KEY,binding_json TEXT NOT NULL)";
 "control_no_update","CREATE TRIGGER control_no_update BEFORE UPDATE ON control_resource_receipt BEGIN SELECT RAISE(ABORT,'control receipts are append-only'); END";
 "control_no_delete","CREATE TRIGGER control_no_delete BEFORE DELETE ON control_resource_receipt BEGIN SELECT RAISE(ABORT,'control receipts are append-only'); END"]
let sql db q=need(Sqlite3.exec db q=Sqlite3.Rc.OK)("private SQL refused: "^Sqlite3.errmsg db)
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o700)
let with_db p f=let db=Sqlite3.db_open p in Fun.protect ~finally:(fun()->ignore(Sqlite3.db_close db);Core.Gc.keep_alive db)(fun()->f db)
let stamp t=let t=Unix.gmtime t in Printf.sprintf"%04d-%02d-%02dT%02d:%02d:%02dZ"(t.Unix.tm_year+1900)(t.Unix.tm_mon+1)t.Unix.tm_mday t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec
let check_schema db=
 let st=Sqlite3.prepare db"SELECT name,sql FROM sqlite_schema WHERE name GLOB 'control_*' ORDER BY name LIMIT 4"in
 Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st))(fun()->
 let rec rows xs=match Sqlite3.step st with Sqlite3.Rc.DONE->List.sort compare xs
 |Sqlite3.Rc.ROW when List.length xs<3->rows((Sqlite3.column_text st 0,Sqlite3.column_text st 1)::xs)
 |_->failwith"control schema bound"in need(rows[]=List.sort compare schema)"control schema changed")
let control_lookup db id binding=
 check_schema db;
 let st=Sqlite3.prepare db"SELECT CASE WHEN typeof(binding_json)='text' THEN CAST(substr(CAST(binding_json AS BLOB),1,16385) AS TEXT) ELSE NULL END FROM control_resource_receipt WHERE request_id=? LIMIT 2"in
 Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st;Core.Gc.keep_alive db)(fun()->
 ignore(Sqlite3.bind st 1(Sqlite3.Data.TEXT id));match Sqlite3.step st with
 |Sqlite3.Rc.DONE->false
 |Sqlite3.Rc.ROW->let b=Sqlite3.column_text st 0 in need(b=binding&&String.length b<=16384&&Sqlite3.step st=Sqlite3.Rc.DONE)"control receipt conflict";true
 |_->failwith"control receipt lookup")
(* Initial actual NTP sample, not resampled synchronization. This complete
   checker executes BEFORE bound VFS open; every descriptor is closed first.
   Same-handle Store revalidates the full snapshot under BEGIN IMMEDIATE. *)
let checker root database portfolio bindings clock_tracking vfs_manifest =
 let raw=read portfolio in
 let records=Yojson.Basic.Util.to_list(Bounded.json_text raw)in
 let old=Sys.getcwd()in
 Fun.protect ~finally:(fun()->Unix.chdir old)(fun()->
 Unix.chdir root;
 let records=List.map(Record.check_record(Record.schema()))records in
 let native=ok(K.native_clock())in
 ignore(Host_clock.parse ~now:(Unix.gettimeofday())clock_tracking);
 let now=stamp(Int64.to_float native.utc_ns/.1e9)in
 let live=Live_plan.read ~path:database ~plan:K.fixed_plan in
 let projected=Checker.reclaim_set_projection ~now_ns:native.utc_ns bindings records live in
 let report=Checker.audit ~root ~now projected in
 let findings=report.Checker.findings@Checker.coherence ~reclaim_set:bindings ~now_ns:native.utc_ns records live@Checker.final_time_findings ~now records in
 if findings<>[]then failwith(Yojson.Basic.to_string(Checker.findings_json findings));
 Checker.verify_again ~root report.evidence;
 (* Stable decision-bearing report; observation time is a distinct field in
    the stored report file, never a synthetic refresh of an old review. *)
 `Assoc["domain",s"uos.private-recovery-control-checker.v1";"status",s"PASS";
 "scope",s"COMPLETE_SYNTHETIC_FOUR_TASK_PLAN_NOT_CANONICAL_PREFLIGHT";
 "portfolio_sha256",s(K.sha256 raw);"snapshot_sha256",s(Live_plan.digest live);
 "clock_tracking_sha256",s(K.sha256 clock_tracking);
 "physical_sqlite",physical database;"vfs_source_manifest_sha256",s vfs_manifest;
 "ranked",Checker.order_json report.ranked;
 "evidence",`List(List.map(fun(p,h)->`Assoc["path",s p;"sha256",s h])report.evidence)])
let bindings request=
 let j=Yojson.Basic.from_string request in
 Yojson.Basic.Util.(to_list(member"old"j))|>List.map(fun j->text j"task",text j"worker",Yojson.Basic.Util.to_int(field j"attempt"),Int64.of_string(text j"lease"))
let check_saved locator request=
 let root=text locator"evidence_root"and database=text locator"database"in
 let report=checker root database(text locator"portfolio")(bindings request)(text locator"clock_tracking")(text locator"vfs_manifest")in
 need(K.sha256(Yojson.Basic.to_string report)=text locator"checker_sha256")"checker decision changed";
 report
let source_boundary locator=
 let raw=read(text locator"portfolio")in
 let records=Yojson.Basic.Util.to_list(Bounded.json_text raw)in
 let now=Record.now_utc()in
 let report=Checker.audit ~root:(text locator"evidence_root")~now
  (List.map(fun j->if text j"task_state"="executing"then set j"task_state"(s"available")else j)records)in
 need(report.Checker.findings=[]&&Checker.final_time_findings ~now records=[])"source/assessment expiry";
 Checker.verify_again ~root:(text locator"evidence_root")report.evidence;
 ignore(Host_clock.parse ~now:(Unix.gettimeofday())(text locator"clock_tracking"))
