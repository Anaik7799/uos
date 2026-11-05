type identity={device:int64;inode:int64}
type resources={main:identity;wal:identity;shm:identity}
type error=Refused|Unsupported|Ownership|Closed|Poisoned|Io|Runtime|Invalid_input|Unknown_outcome
type session={db:Sqlite3.db;owner:int;mutable terminal:(unit,error)result option}
type observation={resources:resources;counters:int64 array}
external reserve_owner : unit->int = "caml_uos_write_vfs_reserve"
external prepare : string->string->(int64*int64)array->int = "caml_uos_write_vfs_prepare"
external ready : unit->int = "caml_uos_write_vfs_ready"
external phase : int->int = "caml_uos_write_vfs_phase"
external native_snapshot : unit->int64 array = "caml_uos_write_vfs_snapshot"
external release : unit->int = "caml_uos_write_vfs_release"
external process_poisoned : unit->bool = "caml_uos_write_vfs_poisoned"
external poison : unit->unit = "caml_uos_write_vfs_poison"
external native_owner : unit->int = "caml_uos_write_vfs_owner"
let status=function 0->Ok()|1->Error Refused|2->Error Unsupported|3->Error Ownership|4->Error Closed|5->Error Poisoned|_->Error Io
let error_label=function Refused->"REFUSED"|Unsupported->"UNSUPPORTED"|Ownership->"OWNERSHIP"|Closed->"CLOSED"|Poisoned->"PROCESS_POISONED"|Io->"IO"|Runtime->"RUNTIME"|Invalid_input->"INVALID_INPUT"|Unknown_outcome->"UNKNOWN_OUTCOME"
let safe_dir p=String.length p>1&&String.length p<=3900&&p.[0]='/'&&not(String.contains p '\000')&&List.for_all(fun s->s<>""&&s<>"."&&s<>"..")List.(tl(String.split_on_char '/' p))
let safe_base p=String.length p>0&&String.length p<=128&&p<>"."&&p<>".."&&String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'|'.'->true|_->false)p
let close s=
 if s.owner<>Unix.getpid()||native_owner()<>0 then Error Ownership else match s.terminal with Some r->r|None->
 if process_poisoned()then(s.terminal<-Some(Error Poisoned);Error Poisoned)else
 let closed=Fun.protect ~finally:(fun()->Core.Gc.keep_alive s.db)(fun()->try Sqlite3.db_close s.db with _->false)in
 let r=if closed then status(release())else(poison();Error Unknown_outcome)in
 if r<>Error Ownership then s.terminal<-Some r;r
let open_existing ~directory ~basename ~expected=
 let valid i=i.device>=0L&&i.inode>0L in
 if not(safe_dir directory&&safe_base basename&&List.for_all valid[expected.main;expected.wal;expected.shm])then Error Invalid_input else
 if process_poisoned()then Error Poisoned else
 match status(reserve_owner())with Error _ as e->e|Ok()->
 match Sqlite_main_mapping.register()with Error _->Error Runtime|Ok _->
 (try if Unix.realpath directory<>directory then Error Invalid_input else
 let pair i=i.device,i.inode in
 match status(prepare directory basename(Array.of_list(List.map pair[expected.main;expected.wal;expected.shm])))with
 |Error _ as e->e|Ok()->
 (try
 let db=Sqlite3.db_open ~mode:`NO_CREATE ~uri:false ~mutex:`FULL ~cache:`PRIVATE ~vfs:"uos-bound-write-development-v1"(directory^"/"^basename)in
 let s={db;owner=Unix.getpid();terminal=None}in
 let result=try
  if List.for_all(fun sql->Sqlite3.exec db sql=Sqlite3.Rc.OK)["PRAGMA synchronous=FULL";"PRAGMA mmap_size=0";"PRAGMA temp_store=MEMORY";"PRAGMA foreign_keys=ON"]
  then status(ready())else Error Refused
  with _->Error Io in
 Core.Gc.keep_alive db;
 (match result with Ok()->Ok s|Error e->(match close s with Ok()->Error e|Error _ as unknown->unknown))
 with _->poison();Error Unknown_outcome)
 with Unix.Unix_error _|Sys_error _->Error Invalid_input)
let snapshot s=
 if s.owner<>Unix.getpid()then Error Ownership else match s.terminal with
 |Some(Ok())->Error Closed|Some(Error e)->Error e|None->
 let a=Fun.protect ~finally:(fun()->Core.Gc.keep_alive s.db)(fun()->native_snapshot())in
 if Array.length a<>42 then Error Io else match status(Int64.to_int a.(0))with
 |Error _ as e->e|Ok()->let at r={device=a.(1+7*r);inode=a.(2+7*r)}in
 Ok{resources={main=at 0;wal=at 1;shm=at 2};counters=a}
let identities o=o.resources
let diagnostics o=
 let a=o.counters in
 let role label r=`Assoc["role",`String label;"device",`Intlit(Int64.to_string a.(1+7*r));"inode",`Intlit(Int64.to_string a.(2+7*r));"opens",`Intlit(Int64.to_string a.(3+7*r));"writes",`Intlit(Int64.to_string a.(26+r));"syncs",`Intlit(Int64.to_string a.(29+r));"truncates",`Intlit(Int64.to_string a.(32+r))]in
 `Assoc["schema",`String"uos-bound-write-development-v1";"authority",`String"NONE";"application_admitted",`Bool false;"system_admitted",`Bool false;"production_store_mutator",`String"UNAVAILABLE";"resources",`List[role"main"0;role"wal"1;role"shm"2];"written_bytes",`Intlit(Int64.to_string a.(35));"main_wal_written_bytes",`Intlit(Int64.to_string(Int64.sub a.(35)a.(38)));"phase",`Intlit(Int64.to_string a.(36));"shm_reset3_calls",`Intlit(Int64.to_string a.(37));"shm_zero_append_writes",`Intlit(Int64.to_string a.(38));"shm_dms_lock",`Intlit(Int64.to_string a.(39));"shm_map_window_active",`Intlit(Int64.to_string a.(40));"connection_initialized",`Bool(a.(41)=1L)]
(* Hidden by production MLI. Exact source may be assembled into a PRIVATE
   fixture module; that adapter alone may use the existing Store on this SAME
   public-binding handle. Unknown is mandatory if Store closed/poisoned it. *)
type 'a private_result=Known of 'a|Unknown [@@warning "-37"]
let[@warning "-32"] with_private_db s f=
 if s.owner<>Unix.getpid()||native_owner()<>0 then Error Ownership else
 match s.terminal with Some(Ok())->Error Closed|Some(Error e)->Error e|None->
 if process_poisoned()then Error Poisoned else
 match status(phase 1)with Error _ as e->e|Ok()->
 Fun.protect ~finally:(fun()->Core.Gc.keep_alive s.db)(fun()->
  try match f s.db with
  |Unknown->poison();s.terminal<-Some(Error Unknown_outcome);Error Unknown_outcome
  |Known value->(match status(phase 0)with Ok()->Ok value|Error e->poison();s.terminal<-Some(Error e);Error e)
  with _->poison();s.terminal<-Some(Error Unknown_outcome);Error Unknown_outcome)
