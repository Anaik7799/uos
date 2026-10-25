//// Bounded host observations and executable policy checks, never a hardware-lock claim.
import cepaf_gleam/harness/observer_policy as obs
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option,None,Some}
import gleam/result
import gleam/string

pub const policy_sha256 = "e82c5775f576fa73037034f7b1619b3215857113b9416224805c057f7b24b724"
pub const policy_source_sha256 = "6b63d440c8108902969f3a53219ab5e895481b83efa79d2739b412d58b90d752"
const policy_exe = "/home/an/NAS-setup/uos/var/recovery-runtime/20261025-0032-storage/native/telegram_storage_policy"
const protected_serial = "25503L801736"

@external(erlang,"sa_plan_observer_ffi","observe_checked")
fn invoke(guardian:String,sha:String,args:List(String),deadline:Int,max_bytes:Int)->Result(obs.Observation,String)

@external(erlang,"telegram_ecology_clock","now_ms")
fn now_ms()->Int

type Device { Device(name:String,parent:Option(String),kind:String,size:Int,ro:Bool,mounts:List(Option(String)),serial:Option(String)) }
fn device_decoder() {
 use name <- decode.field("name",decode.string)
 use parent <- decode.field("pkname",decode.optional(decode.string))
 use kind <- decode.field("type",decode.string)
 use size <- decode.field("size",decode.int)
 use ro <- decode.field("ro",decode.bool)
 use mounts <- decode.field("mountpoints",decode.list(decode.optional(decode.string)))
 use serial <- decode.field("serial",decode.optional(decode.string))
 decode.success(Device(name,parent,kind,size,ro,mounts,serial))
}
fn devices_decoder() {
 use rows <- decode.field("blockdevices",decode.list(device_decoder()))
 decode.success(rows)
}
fn policy_decoder() {
 use schema <- decode.field("schema",decode.string)
 use status <- decode.field("status",decode.string)
 use authority <- decode.field("authority",decode.string)
 use admission <- decode.field("runtime_admission",decode.string)
 use matched <- decode.field("protected_id_configured",decode.bool)
 use checks <- decode.field("checks",decode.dict(decode.string,decode.bool))
 case schema=="uos.storage.policy.v1" && status=="observed" && authority=="observation_only" && admission=="NOT_GRANTED" {
   True->decode.success(#(matched,checks))
   False->decode.failure(#(False,dict.new()),"storage policy envelope")
 }
}
fn clean_text(s:String,max:Int)->Bool {
 let forbidden="\u{0}\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{9}\u{a}\u{b}\u{c}\u{d}\u{e}\u{f}\u{10}\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{18}\u{19}\u{1a}\u{1b}\u{1c}\u{1d}\u{1e}\u{1f}\u{7f}"
 string.byte_size(s)<=max && !list.any(string.to_graphemes(forbidden),fn(c){string.contains(s,c)})
}
fn name_valid(s:String)->Bool {
 string.byte_size(s)>0 && string.byte_size(s)<=64 && s!="." && s!=".."
 && list.all(string.to_graphemes(s),fn(c){string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-",c)})
}
fn optional_valid(v:Option(String),f:fn(String)->Bool)->Bool {case v {None->True Some(s)->f(s)}}
fn valid_device(d:Device)->Bool {
 name_valid(d.name) && optional_valid(d.parent,name_valid)
 && name_valid(d.kind) && d.size>=0 && d.size<=9_007_199_254_740_991
 && {d.kind!="disk" || d.size>0}
 && list.length(d.mounts)<=64 && list.all(d.mounts,fn(v){optional_valid(v,fn(s){clean_text(s,1024)})})
 && optional_valid(d.serial,fn(s){clean_text(s,128)})
}
fn ancestor(d:Device,rows:List(Device),left:Int)->Result(Device,String) {
 case left<=0,d.parent {
   True,_->Error("storage_topology_refused")
   False,None->Ok(d)
   False,Some(name)-> {
     use parent <- result.try(list.find(rows,fn(p){p.name==name}) |> result.replace_error("storage_topology_refused"))
     ancestor(parent,rows,left-1)
   }
 }
}
fn number(s:String)->Result(Int,String) {
 use _ <- result.try(case s!="" && string.byte_size(s)<=16
   && list.all(string.to_graphemes(s),fn(c){string.contains("0123456789",c)}) {
   True->Ok(Nil) False->Error("capacity_payload_refused")
 })
 int.parse(s) |> result.replace_error("capacity_payload_refused")
}
fn capacity(raw:String)->Result(#(Int,Int,Int),String) {
 use fields <- result.try(case string.byte_size(raw)<=1024,string.split(string.trim(raw),"\n") {
   True,[_header,data]->Ok(string.split(string.trim(data)," ") |> list.filter(fn(s){s!=""}))
   _,_->Error("capacity_payload_refused")
 })
 case fields {
   [t,u,a]-> {
     use total <- result.try(number(t))
     use used <- result.try(number(u))
     use available <- result.try(number(a))
     case total>0 && total<=9_007_199_254_740_991 && used+available<=total {
       True->Ok(#(total,used,available)) False->Error("capacity_payload_refused")
     }
   }
   _->Error("capacity_payload_refused")
 }
}
fn serial_present(d:Device)->Bool {case d.serial {Some(s)->string.trim(s)!="" None->False}}
fn protected_match(d:Device,configured:Bool)->json.Json {
 case configured,d.serial {True,Some(s)->json.bool(string.trim(s)==protected_serial) _,_->json.null()}
}
pub fn project(blocks:String,df:String,policy:String,started:Int,completed:Int)->Result(String,String) {
 use _ <- result.try(case string.byte_size(blocks)<=65536 && string.byte_size(policy)<=4096
   && started>0 && completed>=started && completed-started<=5000 {
   True->Ok(Nil) False->Error("storage_payload_refused")
 })
 use rows <- result.try(json.parse(blocks,devices_decoder()) |> result.replace_error("storage_payload_refused"))
 use _ <- result.try(case rows!=[] && list.length(rows)<=256 && list.all(rows,valid_device)
   && list.length(list.unique(list.map(rows,fn(d){d.name})))==list.length(rows) {
   True->Ok(Nil) False->Error("storage_payload_refused")
 })
 use _ <- result.try(list.try_map(rows,fn(d){ancestor(d,rows,16)}))
 let disks=list.filter(rows,fn(d){d.kind=="disk"})
 use _ <- result.try(case disks!=[] && list.length(disks)<=64 {True->Ok(Nil) False->Error("storage_payload_refused")})
 use root <- result.try(case list.filter(rows,fn(d){list.contains(d.mounts,Some("/"))}) {
   []->Ok(None)
   [d]->ancestor(d,rows,16) |> result.map(Some)
   _->Error("storage_topology_refused")
 })
 use space <- result.try(capacity(df))
 use p <- result.try(json.parse(policy,policy_decoder()) |> result.replace_error("storage_policy_refused"))
 let #(configured,checks)=p
 let required=["default_configuration_valid","protected_path_denied","protected_partition_denied","protected_serial_denied","missing_nvme_serial_denied","renamed_root_path_denied","ordinary_candidate_valid"]
 use _ <- result.try(case dict.size(checks)==7 && list.all(required,fn(k){dict.has_key(checks,k)}) {
   True->Ok(Nil) False->Error("storage_policy_refused")
 })
 let root_disk=case root {Some(d) if d.kind=="disk"->Some(d) _->None}
 let rendered=json.object([
 #("schema",json.string("uos.telegram.storage.v1")),#("status",json.string("observed")),
 #("scope",json.string("host_block_devices_root_capacity_and_policy_probe")),
 #("observed_at_ms",json.int(completed)),#("observation_started_at_ms",json.int(started)),
 #("snapshot_atomic",json.bool(False)),#("authority",json.string("observation_only")),
 #("runtime_admission",json.string("NOT_GRANTED")),#("osd_allocation_authority",json.string("NOT_GRANTED")),
 #("production_interlock_enforcement",json.string("NOT_ESTABLISHED")),
 #("policy_worker_sha256",json.string(policy_sha256)),#("policy_source_sha256",json.string(policy_source_sha256)),
 #("protected_id_configured",json.bool(configured)),#("policy_checks",json.object(list.map(dict.to_list(checks),fn(p){#(p.0,json.bool(p.1))}))),
 #("policy_checks_passed",json.bool(configured && list.all(dict.values(checks),fn(v){v}))),
 #("root_disk",case root_disk {None->json.null() Some(d)->json.string(d.name)}),
 #("root_serial_matches_protected",case root_disk {None->json.null() Some(d)->protected_match(d,configured)}),
 #("root_filesystem",json.object([#("total_bytes",json.int(space.0)),#("used_bytes",json.int(space.1)),#("available_bytes",json.int(space.2))])),
 #("device_count",json.int(list.length(rows))),#("disk_count",json.int(list.length(disks))),
 #("disks",json.array(disks,fn(d){json.object([
   #("name",json.string(d.name)),#("size_bytes",json.int(d.size)),#("kernel_read_only",json.bool(d.ro)),
   #("serial_present",json.bool(serial_present(d))),#("protected_serial_match",protected_match(d,configured)),
   #("contains_root_filesystem",json.bool(case root_disk {Some(r)->r.name==d.name None->False})),
 ])})),
 ]) |> json.to_string
 case string.byte_size(rendered)<=32768 {True->Ok(rendered) False->Error("storage_payload_refused")}
}
pub fn receipt_payload(receipt:Result(obs.Observation,String),limit:Int)->Result(String,String) {
 use r <- result.try(receipt |> result.replace_error("storage_read_unavailable"))
 use _ <- result.try(case r.guardian_result=="child_exited" && r.cleanup=="confirmed"
   && r.child_exit==0 && bit_array.byte_size(r.payload)<=limit {
   True->Ok(Nil) False->Error("storage_receipt_refused")
 })
 bit_array.to_string(r.payload) |> result.replace_error("storage_payload_refused")
}
fn read_one(exe:String,sha:String,args:List(String),limit:Int)->Result(String,String) {
 invoke("/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe",
 "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be",
 ["--exe",exe,"--sha256",sha,"--deadline-ms","1000","--max-bytes",int.to_string(limit),"--",..args],1000,limit)
 |> receipt_payload(limit)
}
pub fn read()->Result(String,String) {
 let started=now_ms()
 use blocks <- result.try(read_one("/usr/bin/lsblk","0d9c90e59ccb43a880108d353de046accf608050de644e9ff61b81de79a33570",
 ["--json","--bytes","--list","--exclude","7","--output","NAME,PKNAME,TYPE,SIZE,RO,MOUNTPOINTS,SERIAL"],65536))
 use df <- result.try(read_one("/usr/bin/df","bf411cf00676ce1dde116d0127e5d16a0f61b723dd1a02e6befb95773acd6b77",
 ["--block-size=1","--output=size,used,avail","/"],1024))
 use policy <- result.try(read_one(policy_exe,policy_sha256,[],4096))
 project(blocks,df,policy,started,now_ms())
}
