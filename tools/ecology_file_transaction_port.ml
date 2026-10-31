#use "ecology_file_transaction.ml";;

(* LOCAL CODEX relay implementation; bounded IO, never release authority.
   Compile by removing the two Kernel toplevel directives and this #use line,
   retaining exact Kernel source SHA in the private build receipt. Run ONLY
   behind the reviewed OS guardian. Cooperative same-UID/frozen-topology
   premises are inherited from Kernel, not upgraded into hostile-FS safety.
   Control directory is separately owned, private and OUTSIDE the kernel
   journal. Its immutable pin is never recovered from the journal checksum.
   All output is PRIVATE control metadata, never public telemetry. Native
   file verification is not candidate runtime-health verification. Checkpoint
   observations are trusted caller data, not authenticated authority. *)
module Port = struct
let max_request_bytes=262144
let max_response_bytes=262144
let max_records=256
let max_record_bytes=8192
let max_control_bytes=262144
exception Hold of string
exception Bad_json
exception Bad_receipt
 type parse_error=Invalid_json
let need b code=if not b then raise(Hold code)
(* Strict grammar adapted from UOS-owned symbiosis_check_receipts.ml frozen
   146387176ca599ba3933620b8363a4d406a8088842e8a597dc4c4c6eb4f001e7;
   no foreign source, dependencies or schema authority imported. *)
let utf8 s =
  let n=String.length s in
  let byte i=Char.code s.[i] in
  let cont i=i<n && byte i>=0x80 && byte i<=0xbf in
  let rec loop i = i=n ||
    let c=byte i in
    if c<0x80 then loop(i+1)
    else if c>=0xc2 && c<=0xdf then cont(i+1) && loop(i+2)
    else if c>=0xe0 && c<=0xef then
      cont(i+1) && cont(i+2) && (c<>0xe0 || byte(i+1)>=0xa0)
      && (c<>0xed || byte(i+1)<0xa0) && loop(i+3)
    else if c>=0xf0 && c<=0xf4 then
      cont(i+1) && cont(i+2) && cont(i+3)
      && (c<>0xf0 || byte(i+1)>=0x90) && (c<>0xf4 || byte(i+1)<0x90)
      && loop(i+4)
    else false in
  loop 0

(* Closed strict JSON grammar: protocol numbers are integers. No comments,
   tuples, trailing commas, NaN, duplicate members or lone Unicode surrogates. *)
let parse_json text =
  let n=String.length text in
  if n=0 || n>max_request_bytes || not(utf8 text) then Error Invalid_json else
  let i=ref 0 and nodes=ref 0 in
  let bad()=raise Bad_json in
  let rec ws()=if !i<n && List.mem text.[!i] [' ';'\t';'\r';'\n'] then(incr i;ws()) in
  let take c=ws(); if !i>=n || text.[!i]<>c then bad() else incr i in
  let hex c=match c with '0'..'9'->Char.code c-48|'a'..'f'->Char.code c-87|'A'..'F'->Char.code c-55|_->bad() in
  let four()=if !i+4>n then bad(); let x=ref 0 in for k=0 to 3 do x:=(!x lsl 4) lor hex text.[!i+k] done;i:= !i+4;!x in
  let string_token()=
    ws();let start= !i in take '"';
    let rec scan()=
      if !i>=n then bad();
      match text.[!i] with
      | '"' -> incr i
      | '\\' -> incr i;if !i>=n then bad();let c=text.[!i] in incr i;
          (match c with
          | '"'|'\\'|'/'|'b'|'f'|'n'|'r'|'t'->()
          | 'u'->let h=four() in
              if h>=0xd800 && h<=0xdbff then(
                if !i+2>n || text.[!i]<>'\\' || text.[!i+1]<>'u' then bad();
                i:= !i+2;let l=four() in if l<0xdc00 || l>0xdfff then bad())
              else if h>=0xdc00 && h<=0xdfff then bad()
          | _->bad());scan()
      | c when Char.code c<32 -> bad()
      | _ -> incr i;scan() in
    scan(); match Yojson.Safe.from_string(String.sub text start (!i-start)) with
    | `String s->s|_->bad() in
  let rec value depth =
    incr nodes;if depth>16 || !nodes>20_000 then bad();ws();if !i>=n then bad();
    match text.[!i] with
    | '"' -> `String(string_token())
    | '{' -> incr i;ws();let seen=Hashtbl.create 16 in
        let rec members acc =
          let key=string_token() in if Hashtbl.mem seen key then bad();Hashtbl.add seen key ();
          take ':';let v=value(depth+1) in ws();
          if !i<n && text.[!i]=',' then(incr i;members((key,v)::acc))
          else(take '}';`Assoc(List.rev((key,v)::acc))) in
        if !i<n && text.[!i]='}' then(incr i;`Assoc[])else members []
    | '[' -> incr i;ws();
        let rec items acc count =
          if count>=1024 then bad();let v=value(depth+1) in ws();
          if !i<n && text.[!i]=',' then(incr i;items(v::acc)(count+1))
          else(take ']';`List(List.rev(v::acc))) in
        if !i<n && text.[!i]=']' then(incr i;`List[])else items [] 0
    | 't' -> literal "true" (`Bool true)
    | 'f' -> literal "false" (`Bool false)
    | 'n' -> literal "null" `Null
    | '-'|'0'..'9' ->
        let start= !i in if text.[!i]='-' then incr i;
        if !i>=n then bad();
        (match text.[!i] with
        | '0' -> incr i
        | '1'..'9' -> incr i;while !i<n && text.[!i]>='0' && text.[!i]<='9' do incr i done
        | _ -> bad());
        if !i-start>20 then bad();
        let number=Int64.of_string(String.sub text start (!i-start)) in
        `Intlit(Int64.to_string number)
    | _ -> bad()
  and literal s v =
    let size=String.length s in if !i+size>n || String.sub text !i size<>s then bad();
    i:= !i+size;v in
  try let j=value 0 in ws();if !i<>n then bad();Ok j
  with Bad_json|Failure _|Yojson.Json_error _ -> Error Invalid_json

let rec canonical = function
  | `Assoc fields -> `Assoc(List.sort (fun(a,_)(b,_)->String.compare a b)
      (List.map(fun(k,v)->k,canonical v)fields))
  | `List xs -> `List(List.map canonical xs)
  | `Int n -> `Intlit(string_of_int n)
  | `Intlit n -> `Intlit(Int64.to_string(Int64.of_string n))
  | x -> x
let encoded j=Yojson.Safe.to_string(canonical j)
let obj names=function
 |`Assoc xs when List.length xs=List.length names && List.for_all(fun k->List.mem_assoc k xs)names->xs
 |_->raise Bad_receipt
let get xs k=List.assoc k xs
let str=function `String s->s|_->raise Bad_receipt
let integer=function `Int n->n|`Intlit s->(try int_of_string s with Failure _->raise Bad_receipt)|_->raise Bad_receipt
let number n=`Int n
let string s=`String s
let json text=match parse_json text with Ok j->j|Error _->raise(Hold "invalid_json")
let hex s=String.length s=64 && String.for_all(function '0'..'9'|'a'..'f'->true|_->false)s
let digest j=let s=str j in need(String.length s=71 && String.starts_with ~prefix:"sha256:" s && hex(String.sub s 7 64))"invalid_digest";s
let bare s=String.sub s 7 64
let absolute s=String.length s>1 && String.length s<=3072 && s.[0]='/' &&
  not(String.ends_with ~suffix:"/" s) && List.for_all(fun x->x<>"" && x<>"." && x<>"..")
  (List.tl(String.split_on_char '/' s)) && not(String.contains s '\000')
let relative s=String.length s>0 && String.length s<=1024 && s.[0]<>'/' &&
 List.for_all(fun x->x<>"" && x<>"." && x<>"..") (String.split_on_char '/' s) &&
 String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'.'|'_'|'-'|'/'|'@'->true|_->false)s
let inside dir p=p=dir || String.starts_with ~prefix:(dir^"/")p
let identical a b=a.Unix.st_dev=b.Unix.st_dev && a.Unix.st_ino=b.Unix.st_ino &&
 a.Unix.st_kind=b.Unix.st_kind && a.Unix.st_size=b.Unix.st_size &&
 a.Unix.st_mtime=b.Unix.st_mtime && a.Unix.st_ctime=b.Unix.st_ctime &&
 a.Unix.st_perm=b.Unix.st_perm && a.Unix.st_uid=b.Unix.st_uid && a.Unix.st_gid=b.Unix.st_gid
let private_file st=st.Unix.st_kind=Unix.S_REG && st.Unix.st_nlink=1 &&
 st.Unix.st_uid=Unix.geteuid() && st.Unix.st_perm=0o600
let read_private path cap=
 let before=Unix.lstat path in need(private_file before && before.Unix.st_size<=cap)"unsafe_private_file";
 let fd=Unix.openfile path [Unix.O_RDONLY;Unix.O_NONBLOCK;Unix.O_CLOEXEC]0 in
 Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
  need(identical before(Unix.fstat fd) && identical before(Unix.lstat path))"changed_private_file";
  let buf=Bytes.create(cap+1)in
  let rec loop at=if at=cap+1 then at else let n=Unix.read fd buf at(cap+1-at)in if n=0 then at else loop(at+n)in
  let size=loop 0 in need(size<=cap && size=before.Unix.st_size &&
   identical before(Unix.fstat fd) && identical before(Unix.lstat path))"changed_private_file";
  Bytes.sub_string buf 0 size)
let directory ?(private_mode=true) path=
 need(absolute path && Unix.realpath path=path)"unsafe_directory";
 let st=Unix.lstat path in need(st.Unix.st_kind=Unix.S_DIR && st.Unix.st_uid=Unix.geteuid() &&
 (if private_mode then st.Unix.st_perm=0o700 else st.Unix.st_perm land 0o022=0))"unsafe_directory"
let sync_dir path=let fd=Unix.openfile path [Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
 Fun.protect ~finally:(fun()->Unix.close fd)(fun()->Unix.fsync fd)
let write_new path bytes=
 need(String.length bytes<=max_record_bytes)"record_bound";
 let fd=Unix.openfile path [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
 Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
  Unix.fchmod fd 0o600;let rec loop i=if i<String.length bytes then let n=Unix.write_substring fd bytes i(String.length bytes-i)in
   need(n>0)"write_failed";loop(i+n)in loop 0;Unix.fsync fd);
 sync_dir(Filename.dirname path);
 need(read_private path max_record_bytes=bytes)"write_readback_failed"
type config={root:string;state_relative:string;control:string;staging:string;locator:string;tx:string;candidate:string;manifest:string}
let binding c=["transaction_id",string c.tx;"candidate",string c.candidate;"manifest",string c.manifest]
let check_binding c j=let o=obj ["transaction_id";"candidate";"manifest"] j in
 need(digest(get o "transaction_id")=c.tx && digest(get o "candidate")=c.candidate && digest(get o "manifest")=c.manifest)"binding_mismatch"
let decode_config path=
 need(absolute path && Unix.realpath path=path)"invalid_config_path";
 let o=obj ["schema_version";"root";"state_relative";"control_directory";"staging_directory";"transaction_id";"candidate";"manifest"] (json(read_private path 16384))in
 need(integer(get o "schema_version")=1)"invalid_schema";
 let c={root=str(get o "root");state_relative=str(get o "state_relative");control=str(get o "control_directory");locator=path;
 staging=str(get o "staging_directory");tx=digest(get o "transaction_id");candidate=digest(get o "candidate");manifest=digest(get o "manifest")}in
 directory ~private_mode:false c.root;directory c.control;directory c.staging;
 need(relative c.state_relative)"unsafe_state_path";
 let journal=Filename.concat c.root c.state_relative in
 need(not(inside journal c.control) && not(inside c.control journal) && not(inside journal c.staging) &&
 not(inside c.control c.staging) && not(inside c.staging c.control))"overlapping_private_directories";c
let context c=match Kernel.make_context ~root:c.root ~state_relative:c.state_relative ~transaction_id:(bare c.tx)
 ~candidate:(bare c.candidate) ~manifest_sha256:(bare c.manifest)with Ok x->x|Error e->raise(Hold(Kernel.error_label e))
let kernel=function Ok x->x|Error e->raise(Hold(Kernel.error_label e))
let command j=
 let o=obj ["kind";"index"]j in let k=str(get o "kind")and i=get o "index"in
 if List.mem k ["replace_file";"restore_file"]then need(integer i>=0 && integer i<15)"invalid_index"
 else need(List.mem k ["stage_files";"fence_readers";"verify_candidate";"verify_previous";"resume_readers"] && i=`Null)"invalid_command";
 canonical j
let observation j=
 let o=obj ["kind";"candidate";"manifest";"physical_count"]j in
 let c=get o "candidate"and m=get o "manifest"and n=get o "physical_count"in
 (match str(get o "kind")with
 |"succeeded"|"failed"->need(c=`Null && m=`Null && n=`Null)"invalid_observation"
 |"prepared"->ignore(digest m);need(c=`Null && integer n>0 && integer n<=15)"invalid_observation"
 |"verified"->ignore(digest c);need(m=`Null && n=`Null)"invalid_observation"
 |_->raise(Hold "invalid_observation"));canonical j
let native_ops=["stage";"replace_one";"restore_one";"verify_new";"verify_old";"close"]
type request={epoch:int;generation:int;operation:string;payload:Yojson.Safe.t}
let decode_request c j=
 let o=obj ["schema_version";"transaction_id";"candidate";"manifest";"epoch";"generation";"operation";"payload"]j in
 need(integer(get o "schema_version")=1)"invalid_schema";
 check_binding c (`Assoc(List.map(fun k->k,get o k)["transaction_id";"candidate";"manifest"]));
 let r={epoch=integer(get o "epoch");generation=integer(get o "generation");operation=str(get o "operation");payload=canonical(get o "payload")}in
 need(r.epoch>0 && r.epoch<=9_000_000_000_000 && r.generation>=0 && r.generation<=9_000_000_000_000)"invalid_sequence";
 (match r.operation with
 |"stage"->let p=obj ["edits"]r.payload in (match get p "edits"with
   |`List es->need(List.length es>0 && List.length es<=15)"edit_count";
    let names=List.map(fun e->let p=obj ["relative";"replacement_relative"]e in
     let a=str(get p "relative")and b=str(get p "replacement_relative")in need(relative a && relative b)"unsafe_edit";
     let target=Filename.concat c.root a in
     need(not(inside c.control target) && not(inside c.staging target) && target<>c.locator &&
      not(inside(Filename.concat c.root c.state_relative)target))"private_target_alias";a)es in
    need(List.length(List.sort_uniq compare names)=List.length names)"duplicate_edit"
   |_->raise Bad_receipt)
 |"replace_one"|"restore_one"->let p=obj ["index"]r.payload in let n=integer(get p "index")in need(n>=0 && n<15)"invalid_index"
 |"verify_new"|"verify_old"|"close"|"inspect"|"recovery_epoch"->ignore(obj []r.payload)
 |"checkpoint_pending"->let p=obj ["command"]r.payload in ignore(command(get p "command"))
 |"checkpoint_result"->let p=obj ["command";"observation"]r.payload in ignore(command(get p "command"));ignore(observation(get p "observation"))
 |_->raise(Hold "invalid_operation"));r
let record r status payload=`Assoc["operation",string r.operation;"epoch",number r.epoch;"generation",number r.generation;"payload",payload;"status",string status]
let fields j=obj ["operation";"epoch";"generation";"payload";"status"]j
let value j k=get(fields j)k
let sequence j=integer(value j "epoch"),integer(value j "generation")
let is r j=sequence j=(r.epoch,r.generation) && str(value j "operation")=r.operation
let pin_path c=Filename.concat c.control "descriptor-pin.json"
let exists p=try ignore(Unix.lstat p);true with Unix.Unix_error(Unix.ENOENT,_,_)->false
let pin c=
 let o=obj ["schema_version";"binding";"descriptor_sha256";"physical_count"](json(read_private(pin_path c)max_record_bytes))in
 need(integer(get o "schema_version")=1)"invalid_pin";check_binding c(get o "binding");
 let digest=str(get o "descriptor_sha256")in need(hex digest)"invalid_pin";
 let n=integer(get o "physical_count")in need(n>=1 && n<=15)"invalid_pin";digest,n
let save_pin c t=
 write_new(pin_path c)(encoded(`Assoc["schema_version",number 1;"binding",`Assoc(binding c);
 "descriptor_sha256",string(Kernel.private_descriptor_sha256 t);"physical_count",number(Kernel.count t)]))
let list_control c=
 let d=Unix.opendir c.control in Fun.protect ~finally:(fun()->Unix.closedir d)(fun()->
  let rec loop n acc=match Unix.readdir d with
  |"."|".."->loop n acc
  |name->need(n<max_records+2)"control_file_count";loop(n+1)(name::acc)
  |exception End_of_file->acc in loop 0 [])
let event_name i=Printf.sprintf "record-%03d.json" i
let stored c j=encoded(`Assoc["schema_version",number 1;"binding",`Assoc(binding c);"record",j])
let used_bytes c records=List.fold_left(fun n j->n+String.length(stored c j))0 records
let read_records c=
 let names=list_control c in
 let events=List.filter(fun n->n<>"lock" && n<>"descriptor-pin.json")names in
 need(List.length events<=max_records)"record_count";
 let total=ref 0 in
 let records=List.mapi(fun i _->let name=event_name i in need(List.mem name events)"unexpected_control_file";
  let bytes=read_private(Filename.concat c.control name)max_record_bytes in
  total:= !total+String.length bytes;need(!total<=max_control_bytes)"control_byte_bound";
  let parsed=json bytes in need(encoded parsed=bytes)"noncanonical_record";
  let envelope=obj ["schema_version";"binding";"record"]parsed in
  need(integer(get envelope "schema_version")=1)"invalid_record";check_binding c(get envelope "binding");
  let j=get envelope "record"in let f=fields j in
  let op=str(get f "operation")and status=str(get f "status")in
  need(List.mem op(native_ops@["checkpoint_pending";"checkpoint_result";"recovery_epoch"]) && List.mem status ["pending";"result"])"invalid_record";
  let e=integer(get f "epoch")and g=integer(get f "generation")in need(e>0 && g>=0)"invalid_record";
  if List.mem op native_ops && status="result"then(
   let p=obj ["index";"files_verified";"prepared";"count"](get f "payload")in
   need(get p "prepared"=`Bool true && integer(get p "count")>=1 && integer(get p "count")<=15 &&
    get p "files_verified"=`Bool(List.mem op["verify_new";"verify_old"]))"invalid_record";
   if List.mem op["replace_one";"restore_one"]then need(integer(get p "index")>=0 && integer(get p "index")<15)"invalid_record"
   else need(get p "index"=`Null)"invalid_record")
  else(
   ignore(decode_request c (`Assoc(["schema_version",number 1;"epoch",number e;"generation",number g;
    "operation",string op;"payload",get f "payload"]@binding c)));
   need(status=(if op="checkpoint_result" || op="recovery_epoch"then "result"else "pending"))"invalid_record");
  canonical j
 )events in
 let rec validate previous = function []->()|j::tail->
  let e,g=sequence j and op=str(value j "operation")and status=str(value j "status")in
  let latest=List.fold_left(fun acc j->max acc(sequence j))(0,0)previous in
  need((e,g)>=latest)"corrupt_record_order";
  if fst latest>0 && e>fst latest then need(op="recovery_epoch" && status="result" && g>snd latest)"missing_recovery_marker";
  let same operation=List.filter(fun old->sequence old=(e,g) && str(value old "operation")=operation)previous in
  need(not(List.exists(fun old->str(value old "status")=status)(same op)))"duplicate_record";
  if List.mem op native_ops && status="result"then need(List.length(same op)=1)"missing_native_intent";
  if op="checkpoint_result"then(
   let ps=same "checkpoint_pending"in need(List.length ps=1)"missing_checkpoint_intent";
   let cmd=get(obj["command"](value(List.hd ps)"payload"))"command"in
   need(encoded cmd=encoded(get(obj["command";"observation"](value j "payload"))"command"))"conflicting_checkpoint");
  validate(previous@[j])tail in
 validate [] records;records
let append c records j=
 need(List.length records<max_records)"record_bound";
 let bytes=stored c j in
 (* Every recovery record type has a closed schema fitting this explicit
    quota. Only the stage intent may contain a larger bounded path list. *)
 if not(str(value j "operation")="stage" && str(value j "status")="pending")then
  need(String.length bytes<=1024)"recovery_record_byte_bound";
 let old_bytes=used_bytes c records in
 need(old_bytes+String.length bytes<=max_control_bytes)"control_byte_bound";
 (try write_new(Filename.concat c.control(event_name(List.length records)))bytes
  with Hold _|Unix.Unix_error _|Sys_error _->raise(Hold "commit_unknown"));records@[j]
let lock c=
 let path=Filename.concat c.control "lock"in
 let fd=if exists path then(
  let st=Unix.lstat path in need(private_file st)"unsafe_lock";
  let fd=Unix.openfile path [Unix.O_RDWR;Unix.O_NONBLOCK;Unix.O_CLOEXEC]0 in
  if not(identical st(Unix.fstat fd) && identical st(Unix.lstat path))then(Unix.close fd;raise(Hold "changed_lock"));fd)
 else(let fd=Unix.openfile path[Unix.O_RDWR;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in Unix.fsync fd;sync_dir c.control;fd)in
 try Unix.lockf fd Unix.F_TLOCK 0;fd with e->Unix.close fd;raise e
let with_transaction c f=
 let expected,n=pin c in let t=kernel(Kernel.load(context c)~expected_descriptor_sha256:expected)in
 let closed=ref false in
 Fun.protect ~finally:(fun()->if not !closed then ignore(Kernel.close t))(fun()->
  need(Kernel.count t=n)"pin_count_mismatch";let result=f t in
  kernel(Kernel.close t);closed:=true;result)
let image=function Kernel.Old->"old"|Kernel.New->"new"|Kernel.Both->"both"|Kernel.Unknown->"unknown"
let snapshot c=
 if exists(pin_path c)then with_transaction c(fun t->true,Kernel.count t,
  `List(List.init(Kernel.count t)(fun i->string(image(kernel(Kernel.inspect t ~index:i))))))
 else(need(not(exists(Filename.concat c.root c.state_relative)))"orphan_kernel_state";false,0,`List[])
let check_order records r=
 let latest=List.fold_left(fun acc j->max acc(sequence j))(0,0)records in
 need(r.epoch>=fst latest)"stale_epoch";
 need(r.epoch<>fst latest || r.generation>=snd latest)"stale_generation";
 if records<>[] && r.epoch>fst latest then need(r.operation="recovery_epoch")"recovery_marker_required";
 if r.operation="recovery_epoch"then need(r.epoch>fst latest && r.generation>snd latest)"recovery_epoch_not_new"
let checkpoint_command r=let p=match r.payload with `Assoc p->p|_->raise Bad_receipt in get p "command"
let checkpoint_kind r=str(get(obj["kind";"index"](checkpoint_command r))"kind")
let recovering records epoch=List.exists(fun j->integer(value j "epoch")=epoch &&
 (List.mem(str(value j "operation"))["recovery_epoch";"restore_one";"verify_old"] ||
 (List.mem(str(value j "operation"))["checkpoint_pending";"checkpoint_result"] &&
  let p=match value j "payload"with `Assoc p->p|_->raise Bad_receipt in
  let kind=str(get(obj["kind";"index"](get p "command"))"kind")in
  List.mem kind["restore_file";"verify_previous"])))records
let recovery_record records r=
 List.mem r.operation["recovery_epoch";"restore_one";"verify_old"] ||
 (r.operation="close" && recovering records r.epoch) ||
 (List.mem r.operation["checkpoint_pending";"checkpoint_result"] &&
  let k=checkpoint_kind r in List.mem k["restore_file";"verify_previous"] ||
   (List.mem k["fence_readers";"resume_readers"] && recovering records r.epoch))
let reserve_recovery c records r=
 let declared=if r.operation="stage"then match get(obj["edits"]r.payload)"edits"with `List es->List.length es|_->raise Bad_receipt
  else if exists(pin_path c)then snd(pin c)else 0 in
 if declared>0 && not(recovery_record records r)then(
  (* One uninterrupted full pass: reconstruction checkpoint pair, epoch,
     reader fence pair, N*(native restore pair + controller pair), previous
     file+controller verification pairs, reader resume pair, final close pair.
     A retry/repeated crash may exhaust this finite quota and must HOLD. *)
  let reserve_records=13+4*declared in
  let slots=if List.mem r.operation native_ops then 2 else 1 in
  let intent=String.length(stored c(record r "pending" r.payload))in
  let bytes=if List.mem r.operation native_ops then intent+1024 else String.length(stored c(record r "result" r.payload))in
  need(List.length records+slots+reserve_records<=max_records &&
   used_bytes c records+bytes+reserve_records*1024<=max_control_bytes)"recovery_escrow")
let checkpoint_validate records r=
 let own pending j=str(value j "operation")=pending && sequence j=(r.epoch,r.generation)in
 if r.operation="checkpoint_result"then(
  let p=List.filter(own "checkpoint_pending")records in need(List.length p=1)"missing_checkpoint_intent";
  let previous=get(obj ["command"](value(List.hd p)"payload"))"command"in
  need(encoded previous=encoded(checkpoint_command r))"conflicting_checkpoint")
type hook=Before_effect|Kernel_mutation|Kernel_parent_sync|After_effect|After_result
let execute_native ?(hook=fun _->()) c r=
 match r.operation with
 |"stage"->need(not(exists(pin_path c)))"pin_exists";
  let es=get(obj ["edits"]r.payload)"edits"in
  let edits=match es with `List es->List.map(fun e->let p=obj ["relative";"replacement_relative"]e in
    let rel=str(get p "replacement_relative")in let path=Filename.concat c.staging rel in
    need(Unix.realpath path=path)"unsafe_staging_path";
    let replacement=read_private path Kernel.max_file_bytes in
    {Kernel.relative=str(get p "relative");replacement})es|_->raise Bad_receipt in
  let t=kernel(Kernel.prepare(context c)edits)in
  let closed=ref false in
  Fun.protect ~finally:(fun()->if not !closed then ignore(Kernel.close t))(fun()->save_pin c t;
   let n=Kernel.count t in kernel(Kernel.close t);closed:=true;
   `Assoc["index",`Null;"files_verified",`Bool false;"prepared",`Bool true;"count",number n])
 |_->with_transaction c(fun t->
   let index=if List.mem r.operation["replace_one";"restore_one"]then get(obj ["index"]r.payload)"index"else `Null in
   (match r.operation with
    |"replace_one"->kernel(Kernel.replace_one ~after_mutation:(fun()->hook Kernel_mutation) ~after_parent_sync:(fun()->hook Kernel_parent_sync) t ~index:(integer index))
    |"restore_one"->kernel(Kernel.restore_one ~after_mutation:(fun()->hook Kernel_mutation) ~after_parent_sync:(fun()->hook Kernel_parent_sync) t ~index:(integer index))
    |"verify_new"->kernel(Kernel.verify_replacement t)
    |"verify_old"->kernel(Kernel.verify_previous t)
    |"close"->()|_->raise Bad_receipt);
   `Assoc["index",index;"files_verified",`Bool(List.mem r.operation["verify_new";"verify_old"]);
    "prepared",`Bool true;"count",number(Kernel.count t)])
let response c r status code records=
 let prepared,count,images=snapshot c in
 `Assoc(["schema_version",number 1;"status",string status;"code",string code;"epoch",number r.epoch;
 "generation",number r.generation;"operation",string r.operation;"prepared",`Bool prepared;"count",number count;
 "images",images;"records",`List records]@binding c)
(* Hooks exist only as injected library test callbacks, never wire fields. *)
let execute ?(hook=fun _->()) c r=
 let fd=lock c in Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
 let records=read_records c in
 if r.operation="inspect"then response c r "ok" "inspected" records else(
 let existing=List.filter(is r)records in
 let pending=List.filter(fun j->str(value j "status")="pending")existing in
 let result=List.filter(fun j->str(value j "status")="result")existing in
 let check_replay()=
  let previous=if r.operation="checkpoint_pending" || r.operation="checkpoint_result" || r.operation="recovery_epoch"
   then value(List.hd existing)"payload"else value(List.hd pending)"payload"in
  need(encoded previous=encoded r.payload)"conflicting_replay"in
 if existing<>[]then(check_replay();if result<>[] || r.operation="checkpoint_pending"
   then response c r "ok" "replayed" records else response c r "unknown" "pending_outcome" records)
 else(
 check_order records r;checkpoint_validate records r;reserve_recovery c records r;
 if List.mem r.operation native_ops then(
  need(List.length records<=max_records-2)"record_bound";
  let used=List.fold_left(fun n j->n+String.length(encoded j)+512)0 records in
  need(used+2*max_record_bytes<=max_control_bytes)"control_byte_bound";
  let records=append c records(record r "pending" r.payload)in hook Before_effect;
  (* Once intent is durable, any failure is uncertain: never auto-reexecute. *)
  let result=try Ok(execute_native ~hook c r)with Hold code->Error code|Unix.Unix_error _|Sys_error _->Error "native_io_failure"
    |Yojson.Json_error _->Error "corrupt_state"in
  match result with
  |Error code->(try response c r "unknown" code records with Hold _|Unix.Unix_error _|Sys_error _->raise(Hold "commit_unknown"))
  |Ok payload->hook After_effect;
    let records=try append c records(record r "result" payload)with Hold _|Unix.Unix_error _|Sys_error _->raise(Hold "commit_unknown")in
    hook After_result;
    (try response c r "ok" "completed" records with Hold _|Unix.Unix_error _|Sys_error _|Yojson.Json_error _->raise(Hold "commit_unknown")))
 else(
 let status=if r.operation="checkpoint_pending"then "pending"else "result"in
 let records=append c records(record r status r.payload)in hook After_result;
 (try response c r "ok" "recorded" records with Hold _|Unix.Unix_error _|Sys_error _|Yojson.Json_error _->raise(Hold "commit_unknown"))))))
let hold code=`Assoc["schema_version",number 1;"status",string(if code="commit_unknown"then "unknown"else "hold");"code",string code]
let run config_path text=
 try let c=decode_config config_path in let r=decode_request c(json text)in execute c r
 with Hold code->hold code|Bad_receipt->hold "invalid_request"|Unix.Unix_error _|Sys_error _->hold "native_io_failure"
let read_frame ic=
 let h=Bytes.create 4 in really_input ic h 0 4;let n=ref 0L in
 for i=0 to 3 do n:=Int64.logor(Int64.shift_left !n 8)(Int64.of_int(Char.code(Bytes.get h i)))done;
 need(!n>0L && !n<=Int64.of_int max_request_bytes)"frame_bound";
 let text=really_input_string ic(Int64.to_int !n)in
 (match input_char ic with _->raise(Hold "trailing_frame_data")|exception End_of_file->());text
let emit oc j=
 let body=encoded j in need(String.length body<=max_response_bytes)"response_bound";
 let h=Bytes.create 4 in for i=0 to 3 do Bytes.set h i(Char.chr((String.length body lsr((3-i)*8))land 255))done;
 output_bytes oc h;output_string oc body;flush oc
let main()=
 set_binary_mode_in stdin true;set_binary_mode_out stdout true;
 let result=try need(Array.length Sys.argv=2)"argument_count";run Sys.argv.(1)(read_frame stdin)
 with Hold code->hold code|End_of_file->hold "truncated_frame"|Unix.Unix_error _|Sys_error _->hold "native_io_failure"in
 try emit stdout result with Hold _->emit stdout(hold "response_bound")
end
(* Executable entry point is added ONLY by the reviewed private compiled build:
   let ()=Port.main(). #use remains library-only for actual-FS tests. *)
