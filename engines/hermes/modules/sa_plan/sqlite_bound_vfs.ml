type identity={device:int64;inode:int64}
type resources={main:identity;wal:identity;shm:identity}
type error=Refused|Unsupported|Ownership|Closed|Poisoned|Io|Runtime|Invalid_input
type connection={owner:int;mutable terminal:(unit,error)result option}
type observation={resources:resources;counters:int64 array}
external native_open : string -> string -> (int64*int64) array -> int = "caml_uos_bound_vfs_open"
external reserve_owner : unit -> int = "caml_uos_bound_vfs_reserve"
external native_snapshot : unit -> int64 array = "caml_uos_bound_vfs_snapshot"
external native_close : unit -> int = "caml_uos_bound_vfs_close"
external process_poisoned : unit -> bool = "caml_uos_bound_vfs_poisoned"
let error_label=function Refused->"REFUSED"|Unsupported->"UNSUPPORTED"|Ownership->"OWNERSHIP"|Closed->"CLOSED"|Poisoned->"PROCESS_POISONED"|Io->"IO"|Runtime->"RUNTIME"|Invalid_input->"INVALID_INPUT"
let status=function 0->Ok()|1->Error Refused|2->Error Unsupported|3->Error Ownership|4->Error Closed|5->Error Poisoned|_->Error Io
let valid i=i.device>=0L&&i.inode>0L
let safe_dir p=String.length p>1&&String.length p<=3900&&p.[0]='/'&&not(String.contains p '\000')&&
 List.for_all(fun s->s<>""&&s<>"."&&s<>"..")List.(tl(String.split_on_char '/' p))
let safe_base p=String.length p>0&&String.length p<=128&&p<>"."&&p<>".."&&String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'|'.'->true|_->false)p
let open_readonly ~directory ~basename ~expected=
 if not(safe_dir directory&&safe_base basename&&List.for_all valid[expected.main;expected.wal;expected.shm])then Error Invalid_input else
 if process_poisoned()then Error Poisoned else
 match status(reserve_owner())with Error _ as e->e|Ok()->
 match Sqlite_main_mapping.register()with Error _->Error Runtime|Ok _->
 (try if Unix.realpath directory<>directory then Error Invalid_input else
 let pair i=i.device,i.inode in
 match status(native_open directory basename(Array.of_list(List.map pair[expected.main;expected.wal;expected.shm])))with
 |Error _ as e->e|Ok()->Ok{owner=Unix.getpid();terminal=None}
 with Unix.Unix_error _|Sys_error _->Error Invalid_input)
let snapshot c=
 if c.owner<>Unix.getpid()then Error Ownership else match c.terminal with
 |Some(Ok())->Error Closed|Some(Error e)->Error e|None->
 let a=native_snapshot()in if Array.length a<>26 then Error Io else
 match status(Int64.to_int a.(0))with Error _ as e->e|Ok()->
 let at i={device=a.(1+7*i);inode=a.(2+7*i)}in
 Ok{resources={main=at 0;wal=at 1;shm=at 2};counters=a}
let close c=if c.owner<>Unix.getpid()then Error Ownership else match c.terminal with
 |Some r->r|None->let r=status(native_close())in (if r<>Error Ownership then c.terminal<-Some r);r
let identities o=o.resources
let diagnostics o=
 let a=o.counters in
 let role name n=`Assoc["role",`String name;"device",`Intlit(Int64.to_string a.(1+7*n));"inode",`Intlit(Int64.to_string a.(2+7*n));"opens",`Intlit(Int64.to_string a.(3+7*n));"closes",`Intlit(Int64.to_string a.(4+7*n));"reads",`Intlit(Int64.to_string a.(5+7*n));"maps",`Intlit(Int64.to_string a.(6+7*n));"locks",`Intlit(Int64.to_string a.(7+7*n))]in
 `Assoc["schema",`String"uos-bound-readonly-vfs-v1";"authority",`String"NONE";"application_admitted",`Bool false;"system_admitted",`Bool false;"resources",`List[role"main"0;role"wal"1;role"shm"2];"entropy_calls",`Intlit(Int64.to_string a.(22));"wal_rw_refused_ro_retry",`Intlit(Int64.to_string a.(23));"schema_entries",`Intlit(Int64.to_string a.(24));"production_adapter",`String"UNAVAILABLE"]
