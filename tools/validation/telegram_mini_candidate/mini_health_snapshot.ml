(* Device reads only; one private empty lock file. No /dev opens, commands or serials. *)
open Yojson.Safe
let str x = `String x
let integer x = `Int x
let opt f = function None -> `Null | Some x -> f x
let starts s p = String.starts_with ~prefix:p s
let safe_component s =
 String.length s > 0 && String.length s <= 64 &&
 String.for_all (fun c -> Char.code c>=32 && Char.code c<=126 && c<>'/') s &&
 s <> "." && s <> ".."
let entries path =
 let d=Unix.opendir path in
 Fun.protect ~finally:(fun()->Unix.closedir d)(fun()->
  let rec loop n a =
   if n > 512 then failwith "directory_limit" else
   match Unix.readdir d with
   | "." | ".." -> loop n a
   | s -> if safe_component s then loop (n+1) (s::a) else failwith "invalid_component"
   | exception End_of_file -> List.sort String.compare a
  in loop 0 [])
let root =
 if Array.length Sys.argv = 1 then "/sys"
 else if Array.length Sys.argv=3 && Sys.argv.(1)="--fixture" then (
  let p=Sys.argv.(2) in
  if not(starts p "/tmp/uos-mini-health-test-") || String.contains p '\000'
    || List.mem ".." (String.split_on_char '/' p) then failwith "fixture_path";
  let real=Unix.realpath p in
  let st=Unix.lstat real in
  if real<>p || st.st_kind<>Unix.S_DIR || st.st_uid<>Unix.getuid() || st.st_perm land 0o077 <> 0
    then failwith "fixture_owner";
  p)
 else failwith "arguments"

(* Kernel lock remains held even if a sysfs syscall cannot be interrupted.
   No second collector can enter until this process exits; no timeout unlock. *)
let collector_lock =
 let dir=if root="/sys" then "/run/user/"^string_of_int(Unix.getuid()) else root in
 let st=Unix.lstat dir in
 if st.st_kind<>Unix.S_DIR || st.st_uid<>Unix.getuid() || st.st_perm land 0o077<>0
 then failwith "lock_directory";
 let p=dir^(if root="/sys" then "/uos-mini-health.lock" else "/.collector.lock") in
 let fd=try Unix.openfile p [Unix.O_RDWR;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC] 0o600
 with Unix.Unix_error(Unix.EEXIST,_,_)->
  let before=Unix.lstat p in
  if before.st_kind<>Unix.S_REG || before.st_uid<>Unix.getuid()
    || before.st_perm land 0o077<>0 || before.st_nlink<>1 then failwith "lock_identity";
  let fd=Unix.openfile p [Unix.O_RDWR;Unix.O_CLOEXEC] 0 in
  let after=Unix.fstat fd in
  if after.st_dev<>before.st_dev || after.st_ino<>before.st_ino then
    (Unix.close fd;failwith "lock_changed");
  fd in
 (try Unix.lockf fd Unix.F_TLOCK 0 with _->Unix.close fd;failwith "collector_busy");
 fd

let confined p =
 let q=Unix.realpath p in
 if not(starts q (root^"/")) then failwith "outside_source";
 q
let read p =
 try
  let q=confined p in
  let before=Unix.lstat q in
  if before.st_kind<>Unix.S_REG then failwith "attribute_kind";
  let fd=Unix.openfile q [Unix.O_RDONLY;Unix.O_NONBLOCK;Unix.O_CLOEXEC] 0 in
  Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
   let after=Unix.fstat fd in
   if after.st_kind<>Unix.S_REG || before.st_dev<>after.st_dev || before.st_ino<>after.st_ino then None else
   let b=Bytes.create 513 in
   let rec loop n =
    if n=513 then None else
    let got=Unix.read fd b n (513-n) in
    if got=0 then (
     if n>512 || confined p<>q then None else
     let s=String.trim(Bytes.sub_string b 0 n) in
     if String.length s>128 || not(String.for_all(fun c->Char.code c>=32 && Char.code c<=126)s)
     then None else Some s)
    else loop(n+got)
   in loop 0)
 with _ -> None
let number p =
 match read p with
 | Some s -> (try let n=int_of_string s in if string_of_int n=s then Some n else None with _->None)
 | None -> None
let bounded lo hi = function Some n when n>=lo && n<=hi -> Some n | _ -> None
let list_or_empty path =
 try let p=confined path in entries p,true with _ -> [],false
exception Device_limit
let collected=ref []
let row_count=ref 0
let row id kind label state reading unit high critical grade thresholds_valid =
 if !row_count>=64 then raise Device_limit;incr row_count;
 let value=`Assoc["id",str id;"kind",str kind;"label",str label;"state",str state;
 "reading",reading;"unit",str unit;"high",high;"critical",critical;"grade",str grade;"thresholds_valid",`Bool thresholds_valid] in collected:=value::!collected;value
let name base fallback = match read(base^"/name")with Some s when s<>""->s|_->fallback
let supported_driver s = List.mem s ["acpitz";"nvme";"k10temp";"coretemp";"amdgpu";"spd5118";"fixture"] || starts s "r8169_"
let sensor_id s =
 starts s "temp" && String.ends_with ~suffix:"_input" s && String.length s>10 &&
 let digits=String.sub s 4 (String.length s-10) in
 digits<>"" && String.for_all(function '0'..'9'->true|_->false)digits
let collect_sensors() =
 let ds,available=list_or_empty(root^"/class/hwmon") in
 let partial=ref(not available) in
 let rows=List.concat_map(fun d->
  let base=root^"/class/hwmon/"^d in
  let driver=name base d in
  if not(supported_driver driver) then
    [row("sensor:"^d)"sensor"driver "not_sampled" `Null "none" `Null `Null "unknown" false]
  else let files,ok=list_or_empty base in
  if not ok then partial:=true;
  List.filter_map(fun f->if not(sensor_id f)then None else
   let stem=String.sub f 0 (String.length f-6) in
   let value=number(base^"/"^f)|>bounded (-100000) 250000 in
   let high_path=base^"/"^stem^"_max" and crit_path=base^"/"^stem^"_crit" in
   let high=number high_path|>bounded 1 250000 in
   let crit=number crit_path|>bounded 1 250000 in
   let coherent=match high,crit with Some a,Some b->a<=b|_->true in
   let thresholds_valid=coherent && (high<>None || not(List.mem(stem^"_max")files)) && (crit<>None || not(List.mem(stem^"_crit")files)) in
   let grade=match value,high,crit with
     | Some v,_,Some c when coherent && v>=c -> "critical"
     | Some v,Some h,_ when coherent && v>=h -> "warning"
     | Some _,_,Some _ when thresholds_valid -> "normal"
     | Some _,Some _,_ when thresholds_valid -> "normal"
     | _ -> "unknown" in
   let label=name base d ^ " " ^ (match read(base^"/"^stem^"_label")with Some x when x<>""->x|_->stem) in
   Some(row("temperature:"^d^":"^stem)"temperature"label
     (if value=None then "unavailable" else if not coherent then "inconsistent_thresholds" else if not thresholds_valid then "invalid_thresholds" else "observed")
     (opt integer value)"milli_celsius"(opt integer high)(opt integer crit)grade thresholds_valid)
  )files)ds in rows,not !partial
let collect_network() =
 let ds,available=list_or_empty(root^"/class/net")in
 let rows=List.map(fun d->
  let base=root^"/class/net/"^d in
  let state=match read(base^"/operstate")with Some x when List.mem x ["unknown";"notpresent";"down";"lowerlayerdown";"testing";"dormant";"up"]->x|_->"unavailable"in
  let carrier=number(base^"/carrier")|>bounded 0 1 in
  row("network:"^d)"network"d state(opt integer carrier)"carrier" `Null `Null "unknown" true)ds in
 rows,available
let collect_blocks() =
 let ds,available=list_or_empty(root^"/block")in
 let included=List.filter(fun d->not(starts d "loop") && not(starts d "ram") && not(starts d "zram"))ds in
 let rows=List.map(fun d->
  let base=root^"/block/"^d in
  let sectors=number(base^"/size")|>bounded 0 9007199254740991 in
  let state=match read(base^"/device/state")with Some s when s<>""->s|_->"unknown"in
  row("block:"^d)"block"d state(opt integer sectors)"512_byte_sectors" `Null `Null "unknown" true)included in
 rows,available,List.length ds-List.length included
let () =
 let start=Unix.gettimeofday() in
 let sok,nok,bok,excluded,truncated=try
  let _,sok=collect_sensors()in let _,nok=collect_network()in let _,bok,excluded=collect_blocks()in
  sok,nok,bok,Some excluded,false
 with Device_limit -> true,false,false,None,true in
 let rows=List.rev !collected in
 if not(sok||nok||bok)then failwith "sources_unavailable";
 if List.length rows>64 then failwith "device_limit";
 let finish=Unix.gettimeofday()in
 if finish<start || finish-.start>2.0 then failwith "deadline_or_clock";
 let result=`Assoc["schema",str"uos.mini.device-observation.v1";"observed_at",integer(int_of_float finish);
 "source",str(if root="/sys"then"linux_sysfs"else"private_fixture");
 "complete",`Bool(sok&&nok&&bok);"truncated",`Bool truncated;"excluded_virtual_blocks",opt integer excluded;
 "devices",`List rows] in
 let raw=Yojson.Safe.to_string result in if String.length raw>32768 then failwith "output_limit";
 print_endline raw
