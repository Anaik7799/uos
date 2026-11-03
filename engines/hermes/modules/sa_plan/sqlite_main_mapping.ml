(* Bounded native SQL bridge only; never an issuer, mutator, task authority or
   effect-ready constructor. All DB access is through public Sqlite3 API. *)
type error=Unsupported_runtime|Registration_failed|Retained_changed|Mapping_unavailable
 |Identity_mismatch|Unsupported_connection|Query_refused|Closed_connection|Ownership_mismatch|Close_failed
type runtime={version:string;source_id:string;dso_path:string}
type observation={dev:int64;ino:int64;bytes:int}
type connection={db:Sqlite3.db;owner:int;mutex:Mutex.t;mutable terminal:(unit,error)result option}
let device x=x.dev and inode x=x.ino and observed_bytes x=x.bytes
let error_label=function Unsupported_runtime->"UNSUPPORTED_RUNTIME"|Registration_failed->"REGISTRATION_FAILED"
 |Retained_changed->"RETAINED_CHANGED"|Mapping_unavailable->"MAIN_MAPPING_UNAVAILABLE"
 |Identity_mismatch->"MAIN_MAPPING_IDENTITY_MISMATCH"|Unsupported_connection->"UNSUPPORTED_CONNECTION"|Query_refused->"QUERY_REFUSED"
 |Closed_connection->"CLOSED_CONNECTION"|Ownership_mismatch->"OWNERSHIP_MISMATCH"|Close_failed->"CLOSE_FAILED"
external install : unit -> bool = "caml_uos_main_mapping_register"
external actual_runtime : unit -> string*string*string*string = "caml_uos_main_mapping_runtime"
external retained_identity : Unix.file_descr -> (int64*int64) option = "caml_uos_main_mapping_retained_identity"
let dso="/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib/libsqlite3.so.3.53.3"
let dso_hash="83be5e2629d718bf67b5bd0b545f56fd3438773791bfaf26f0bdbd78e9e5f16b"
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in
 if n>4194304 then failwith"bound";really_input_string c n)
let register()=try
 let version,source_id,path,header=actual_runtime()in let canonical=Unix.realpath path in let st=Unix.lstat canonical in
 if Sqlite3.sqlite_version()<>3053003||Sqlite3.sqlite_version_info()<>"3.53.3"||version<>"3.53.3"||source_id<>header||
 canonical<>dso||st.st_uid<>0||st.st_perm land 0o222<>0||Digestif.SHA256.(to_hex(digest_string(read canonical)))<>dso_hash
 then Error Unsupported_runtime else if not(install())then Error Registration_failed else Ok{version;source_id;dso_path=canonical}
 with Unix.Unix_error _|Sys_error _|Failure _->Error Unsupported_runtime
let private_regular st=st.Unix.st_kind=Unix.S_REG&&st.st_uid=Unix.geteuid()&&st.st_nlink=1&&st.st_perm land 0o077=0&&st.st_size>=4096&&st.st_size<=33554432
let same a b=a.Unix.st_dev=b.Unix.st_dev&&a.st_ino=b.st_ino&&a.st_uid=b.st_uid&&a.st_gid=b.st_gid&&a.st_perm=b.st_perm&&a.st_nlink=b.st_nlink&&a.st_size=b.st_size&&a.st_mtime=b.st_mtime&&a.st_ctime=b.st_ctime
let sql_error db=match Sqlite3.errmsg db with
 |"UOS_MAP_IDENTITY_MISMATCH"->Identity_mismatch
 |"UOS_MAP_MMAP_UNAVAILABLE"|"UOS_MAP_PROC_UNAVAILABLE"|"UOS_MAP_ABSENT"|"UOS_MAP_INVALID"|"UOS_MAP_BOUND"|"UOS_MAP_UNFETCH"->Mapping_unavailable
 |"UOS_MAP_MUTEX"|"UOS_MAP_READ_TRANSACTION"|"UOS_MAP_VFS"|"UOS_MAP_FILE_METHODS"|"UOS_MAP_FILE_BOUND"->Unsupported_connection
 |_->Query_refused
let safe_path p=String.length p>1&&String.length p<=4096&&p.[0]='/'&&not(String.contains p '\000')&&
 List.for_all(fun s->s<>""&&s<>"."&&s<>"..")List.(tl(String.split_on_char '/' p))
let close_db db=Fun.protect ~finally:(fun()->Core.Gc.keep_alive db)(fun()->try Sqlite3.db_close db with _->false)
let open_readonly ?(mmap=true) path=
 try match register()with Error _ as e->e|Ok runtime->
 if not(safe_path path&&Unix.realpath path=path&&private_regular(Unix.lstat path))then Error Retained_changed else
 let db=Sqlite3.db_open ~mode:`READONLY ~mutex:`FULL ~cache:`PRIVATE ~uri:false path in
 let result=try
   let version=Sqlite3.prepare db"SELECT sqlite_version(),sqlite_source_id()"in
   let matching=Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize version);Core.Gc.keep_alive version)(fun()->
    Sqlite3.step version=Sqlite3.Rc.ROW&&Sqlite3.column_text version 0=runtime.version&&Sqlite3.column_text version 1=runtime.source_id)in
   if not matching then Error Unsupported_runtime else
   let st=Sqlite3.prepare db(if mmap then"PRAGMA mmap_size=1048576"else"PRAGMA mmap_size=0")in
   let set=Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st)(fun()->
    Sqlite3.step st=Sqlite3.Rc.ROW&&Sqlite3.column_int64 st 0=(if mmap then 1048576L else 0L))in
   if not set||Sqlite3.exec db"BEGIN"<>Sqlite3.Rc.OK then Error Unsupported_connection else
   let st=Sqlite3.prepare db"SELECT name FROM sqlite_schema LIMIT 1"in
   let ready=Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st)(fun()->
    match Sqlite3.step st with Sqlite3.Rc.ROW|Sqlite3.Rc.DONE->true|_->false)in
   if ready then Ok{db;owner=Unix.getpid();mutex=Mutex.create();terminal=None}else Error Query_refused
  with Sqlite3.Error _|Sqlite3.SqliteError _|Sqlite3.InternalError _->Error Query_refused in
 (match result with Ok _->result|Error _->if close_db db then result else Error Close_failed)
 with Unix.Unix_error _|Sys_error _->Error Retained_changed
 |Sqlite3.Error _|Sqlite3.SqliteError _|Sqlite3.InternalError _|Failure _->Error Query_refused
let serialized c f=
 if Unix.getpid()<>c.owner then Error Ownership_mismatch else(
 Mutex.lock c.mutex;
 Fun.protect ~finally:(fun()->Mutex.unlock c.mutex;Core.Gc.keep_alive c)(fun()->
  if Unix.getpid()<>c.owner then Error Ownership_mismatch else f()))
let close c=serialized c(fun()->match c.terminal with Some result->result|None->
 c.terminal<-Some(Error Close_failed);
 let rollback=try Sqlite3.exec c.db"ROLLBACK"=Sqlite3.Rc.OK with _->false in
 let result=if close_db c.db&&rollback then Ok()else Error Close_failed in
 c.terminal<-Some result;result)
let observe_main c ~retained=serialized c(fun()->match c.terminal with
 Some(Error _)->Error Close_failed|Some(Ok())->Error Closed_connection|None->
 let db=c.db in Fun.protect ~finally:(fun()->Core.Gc.keep_alive db;Core.Gc.keep_alive retained)(fun()->
 try match register()with Error _ as e->e|Ok _->
 let held=Unix.dup ~cloexec:true retained in
 Fun.protect ~finally:(fun()->Unix.close held)(fun()->
 let before=Unix.fstat held in
 match retained_identity held with None->Error Retained_changed|Some(dev,ino)->
 if not(private_regular before)then Error Retained_changed else
 let statement=Sqlite3.prepare db"SELECT uos_main_mapping_identity_v1(?1,?2)"in
 Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize statement);Core.Gc.keep_alive statement)(fun()->
  if Sqlite3.bind_values statement[Sqlite3.Data.INT dev;Sqlite3.Data.INT ino]<>Sqlite3.Rc.OK then Error Query_refused else
  match Sqlite3.step statement with
  |Sqlite3.Rc.ROW->
    let raw=Sqlite3.column_text statement 0 in
    let expected=Printf.sprintf"main-mapping-v1|%Ld|%Ld|4096"dev ino in
    let after=Unix.fstat held in
    if raw<>expected||Sqlite3.step statement<>Sqlite3.Rc.DONE then Error Query_refused
    else if not(private_regular after&&same before after&&retained_identity held=Some(dev,ino))then Error Retained_changed
    else Ok{dev;ino;bytes=4096}
  |_->Error(sql_error db)))
 with Unix.Unix_error _->Error Retained_changed
 |Sqlite3.Error _|Sqlite3.SqliteError _|Sqlite3.InternalError _|Failure _->Error Query_refused))
