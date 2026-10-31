#use "topfind";;
#require "bos.setup,yojson,cryptokit,mtime.clock";;

(* Bounded native FILE IO kernel, not policy, a grant issuer or a live CLI.
   Preconditions: cooperative exclusive ownership and frozen directory topology;
   the existing admitted controller owns task/risk/epoch/reader fencing.
   Per-file rename is atomic. The set is NOT group atomic. A bounded supervised
   worker must preempt/reap blocked native filesystem calls; byte/entry limits
   and a nonblocking cooperative journal lock are not a hard wall-clock guarantee.
   The lock is per journal, not cross-transaction admission or a root lease.
   Known images mean bytes+mode equality, not authenticated origin or detection
   of a byte-identical external rewrite. Existing UID must be the worker's UID;
   old GID is preserved on replacement/restoration or the operation holds before
   touching the target. Absent-file replacement uses the captured parent GID.
   ACL/xattr migration is outside this kernel. Private journal/images/stages
   remain for reconciliation/cleanup.
   All target bytes and their fingerprints stay private; no payload/hash output.
   Descriptor and old/new images are immutable, O_EXCL-created private files.
   Events are evidence checkpoints only; no scheduler or admission state lives
   here. Intent fsync precedes mutation; parent fsync precedes checkpoint fsync.
   Forward IO reserves its complete pair AND one uninterrupted full restoration
   pass. Retries consume finite journal capacity; unlimited recovery is NOT
   promised. A partial/torn log tail holds for separately authorized manual
   reconciliation: never truncate/ignore/regenerate uncertain history. *)

module Kernel : sig
  type context
  type transaction
  type edit = { relative:string; replacement:string }
  type image_state = Old | New | Both | Unknown
  type error = Invalid_input | Unsafe_path | Already_exists | Busy | Missing_state
    | Corrupt_state | Binding_mismatch | Unknown_image | Changed | Resource_bound
    | Io_error | Closed | Unsupported_metadata
  val error_label : error -> string
  val max_files : int
  val max_file_bytes : int
  val make_context : root:string -> state_relative:string -> transaction_id:string ->
    candidate:string -> manifest_sha256:string -> (context,error) result
  val prepare : context -> edit list -> (transaction,error) result
  val load : context -> expected_descriptor_sha256:string -> (transaction,error) result
  (* Private controller persistence only. NEVER publish per-image fingerprints
     or derive an expected pin from the mutable same-journal checksum. *)
  val private_descriptor_sha256 : transaction -> string
  val count : transaction -> int
  val inspect : transaction -> index:int -> (image_state,error) result
  val replace_one : ?after_mutation:(unit -> unit) -> ?after_parent_sync:(unit -> unit) ->
    transaction -> index:int -> (unit,error) result
  val restore_one : ?after_mutation:(unit -> unit) -> ?after_parent_sync:(unit -> unit) ->
    transaction -> index:int -> (unit,error) result
  val verify_previous : transaction -> (unit,error) result
  val verify_replacement : transaction -> (unit,error) result
  val close : transaction -> (unit,error) result
end = struct
  type error = Invalid_input | Unsafe_path | Already_exists | Busy | Missing_state
    | Corrupt_state | Binding_mismatch | Unknown_image | Changed | Resource_bound
    | Io_error | Closed | Unsupported_metadata
  let error_label = function Invalid_input->"invalid_input" | Unsafe_path->"unsafe_path"
    | Already_exists->"already_exists" | Busy->"busy" | Missing_state->"missing_state"
    | Corrupt_state->"corrupt_state" | Binding_mismatch->"binding_mismatch"
    | Unknown_image->"unknown_image_hold" | Changed->"changed_hold"
    | Resource_bound->"resource_bound" | Io_error->"io_error" | Closed->"closed"
    | Unsupported_metadata->"unsupported_metadata_hold"
  exception Stop of error
  let need b e = if not b then raise(Stop e)
  let safe f = try Ok(f()) with Stop e->Error e
    | Unix.Unix_error((Unix.EAGAIN|Unix.EACCES),"lockf",_)->Error Busy
    | Unix.Unix_error(Unix.ENOENT,_,_)->Error Missing_state
    | Yojson.Json_error _->Error Corrupt_state
    | Invalid_argument _ | Failure _ | Stack_overflow->Error Corrupt_state
    | Unix.Unix_error _ | Sys_error _ -> Error Io_error
  let max_files=15
  let max_file_bytes=1024*1024
  let max_descriptor=65536
  let max_events=256
  let max_event_bytes=32768
  let hash s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s
    |> Cryptokit.transform_string(Cryptokit.Hexa.encode())
  let hex64 s=String.length s=64 && String.for_all(function '0'..'9'|'a'..'f'->true|_->false)s
  let chars s=String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'.'|'_'|'-'|'/'|'@'->true|_->false)s
  let forbidden p=String.starts_with ~prefix:".uos-txn-" p || List.mem p [".jj";".git";"events-quarantine";"credentials";"auth.json";
    "credentials.json";"id_rsa";"id_ed25519"] ||
    List.exists(fun suffix->String.ends_with ~suffix p)[".sqlite3";".db";"-wal";"-shm"]
  let relative s=String.length s>0 && String.length s<=1024 && s.[0]<>'/' && chars s &&
    List.for_all(fun p->p<>"" && p<>"." && p<>".." && not(forbidden p))(String.split_on_char '/' s)
  let absolute s=String.length s>1 && String.length s<=3072 && s.[0]='/' && chars s &&
    List.for_all(fun p->p<>"" && p<>"." && p<>"..") (List.tl(String.split_on_char '/' s)) &&
    not(List.exists(fun p->s=p || String.starts_with ~prefix:(p^"/")s)["/proc";"/sys";"/dev"])
  type context={root:string; state_relative:string; id:string; candidate:string; manifest:string}
  type edit={relative:string; replacement:string}
  type saved=Absent | Present of {sha:string; size:int; mode:int; uid:int; gid:int}
  type entry={relative:string; parent_dev:int; parent_ino:int; parent_uid:int;parent_gid:int;
    old:saved; fresh_sha:string; fresh_size:int;fresh_uid:int;fresh_gid:int}
  type transaction={ctx:context; entries:entry array; descriptor_hash:string; lock:Unix.file_descr;
    owner_pid:int; mutable closed:bool}
  type image_state=Old | New | Both | Unknown
  type current=Absent_now | Present_now of {bytes:string; stat:Unix.stats}
  let active_locks:(string,int)Hashtbl.t=Hashtbl.create 8
  let state ctx=Filename.concat ctx.root ctx.state_relative
  let target_relative ctx rel=relative rel && not(rel=ctx.state_relative ||
    String.starts_with ~prefix:(ctx.state_relative^"/")rel ||
    String.starts_with ~prefix:(rel^"/")ctx.state_relative)
  let same_id a b=a.Unix.st_dev=b.Unix.st_dev && a.Unix.st_ino=b.Unix.st_ino
  let same_snapshot a b=same_id a b && a.Unix.st_kind=b.Unix.st_kind &&
    a.Unix.st_size=b.Unix.st_size && a.Unix.st_mtime=b.Unix.st_mtime &&
    a.Unix.st_ctime=b.Unix.st_ctime && a.Unix.st_perm=b.Unix.st_perm &&
    a.Unix.st_nlink=b.Unix.st_nlink && a.Unix.st_uid=b.Unix.st_uid && a.Unix.st_gid=b.Unix.st_gid
  let owned st=st.Unix.st_uid=Unix.geteuid()
  let directory st=st.Unix.st_kind=Unix.S_DIR && owned st && st.Unix.st_perm land 0o022=0
  let root_stat ctx=
    let st=Unix.lstat ctx.root in
    need(directory st && Unix.realpath ctx.root=ctx.root)Unsafe_path; st
  let path ctx rel=need(relative rel)Unsafe_path;
    need(String.length ctx.root+1+String.length rel<=4096)Resource_bound;
    ignore(root_stat ctx);
    let rec walk prefix=function
      | []->raise(Stop Unsafe_path)
      | [last]->Filename.concat prefix last,Unix.lstat prefix
      | p::rest->let next=Filename.concat prefix p in
        need(directory(Unix.lstat next))Unsafe_path;walk next rest in
    walk ctx.root (String.split_on_char '/' rel)
  let stat_opt p=try Some(Unix.lstat p)with Unix.Unix_error(Unix.ENOENT,_,_)->None
  let safe_file st=st.Unix.st_kind=Unix.S_REG && st.Unix.st_nlink=1 && owned st
  let read_regular ?mode p limit=
    let before=Unix.lstat p in
    need(safe_file before)Unsafe_path;
    (match mode with None->()|Some m->need(before.Unix.st_perm=m)Corrupt_state);
    need(before.Unix.st_size>=0 && before.Unix.st_size<=limit)Resource_bound;
    let fd=Unix.openfile p [Unix.O_RDONLY;Unix.O_NONBLOCK;Unix.O_CLOEXEC]0 in
    Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
      need(same_snapshot before(Unix.fstat fd))Changed;
      let out=Buffer.create before.Unix.st_size and chunk=Bytes.create 4096 in
      let rec loop ()=
        need(same_snapshot before(Unix.fstat fd) && same_snapshot before(Unix.lstat p))Changed;
        let capacity=min 4096 (limit+1-Buffer.length out) in need(capacity>0)Resource_bound;
        let n=Unix.read fd chunk 0 capacity in
        if n=0 then () else (need(Buffer.length out+n<=limit)Resource_bound;
          Buffer.add_subbytes out chunk 0 n;loop()) in
      loop(); need(Buffer.length out=before.Unix.st_size && same_snapshot before(Unix.fstat fd) &&
        same_snapshot before(Unix.lstat p))Changed;
      Buffer.contents out,before)
  let sync_directory p=
    let before=Unix.lstat p in need(directory before)Unsafe_path;
    let fd=Unix.openfile p [Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
    Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
      need(same_id before(Unix.fstat fd) && same_id before(Unix.lstat p))Changed;
      Unix.fsync fd)
  let write_all fd s=
    let rec loop at=if at<String.length s then
      let n=Unix.write_substring fd s at (String.length s-at) in
      need(n>0)Io_error;loop(at+n) in loop 0
  let create_file ?owner p contents mode=
    let fd=try Unix.openfile p [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600
      with Unix.Unix_error(Unix.EEXIST,_,_)->raise(Stop Already_exists) in
    Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
      Unix.fchmod fd 0o600;write_all fd contents;
      (match owner with None->()|Some(uid,gid)->
        let st=Unix.fstat fd in need(st.Unix.st_uid=uid)Unsupported_metadata;
        if st.Unix.st_gid<>gid then
          (try Unix.fchown fd (-1) gid with Unix.Unix_error((Unix.EPERM|Unix.EACCES),_,_)->
            raise(Stop Unsupported_metadata));
        let st=Unix.fstat fd in need(st.Unix.st_uid=uid && st.Unix.st_gid=gid)Unsupported_metadata);
      (* Restore stages are created0600, then given the exact old mode BEFORE
         atomic rename so a crash cannot expose an unrecognized mode window. *)
      Unix.fchmod fd mode;
      let actual=Unix.fstat fd in
      need(actual.Unix.st_perm=mode && actual.Unix.st_uid=Unix.geteuid())Unsupported_metadata;
      (match owner with None->()|Some(uid,gid)->
        need(actual.Unix.st_uid=uid && actual.Unix.st_gid=gid)Unsupported_metadata);
      Unix.fsync fd)
  let private_path ctx name=Filename.concat(state ctx)name
  let image_name kind index=Printf.sprintf "%s-%02d.bin" kind index
  let temp_path ctx entry index kind=
    let p,_=path ctx entry.relative in
    Filename.concat(Filename.dirname p)(Printf.sprintf ".uos-txn-%s-%02d-%s" ctx.id index kind)
  let check_state_dir ctx=
    let p,_=path ctx ctx.state_relative in let st=Unix.lstat p in
    need(directory st && st.Unix.st_perm=0o700)Corrupt_state
  let make_context ~root ~state_relative ~transaction_id ~candidate ~manifest_sha256 = safe(fun()->
    need(absolute root && relative state_relative && hex64 transaction_id && hex64 candidate && hex64 manifest_sha256)Invalid_input;
    {root;state_relative;id=transaction_id;candidate;manifest=manifest_sha256})
  let release ctx fd=
    (try Unix.lockf fd Unix.F_ULOCK 0 with Unix.Unix_error _->());
    Unix.close fd;Hashtbl.remove active_locks(state ctx)
  let acquire ctx create=
    check_state_dir ctx;
    let key=state ctx in
    need(Hashtbl.find_opt active_locks key<>Some(Unix.getpid()))Busy;
    let name=private_path ctx "lock" in
    let fd=if create then (
      let fd=Unix.openfile name [Unix.O_RDWR;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
      Unix.fchmod fd 0o600;Unix.fsync fd;fd)
      else (
        let before=Unix.lstat name in need(safe_file before && before.Unix.st_perm=0o600)Corrupt_state;
        let fd=Unix.openfile name [Unix.O_RDWR;Unix.O_NONBLOCK;Unix.O_CLOEXEC]0 in
        if not(same_snapshot before(Unix.fstat fd) && same_snapshot before(Unix.lstat name))then
          (Unix.close fd;raise(Stop Changed));fd) in
    try Unix.lockf fd Unix.F_TLOCK 0;Hashtbl.replace active_locks key (Unix.getpid());fd
    with e->Unix.close fd;raise e
  let count t=Array.length t.entries
  let close t=safe(fun()->need(t.owner_pid=Unix.getpid())Closed;
    if not t.closed then (t.closed<-true;release t.ctx t.lock))
  let private_descriptor_sha256 t=t.descriptor_hash
  let check_handle t=
    need(not t.closed && t.owner_pid=Unix.getpid())Closed;
    check_state_dir t.ctx;
    let st=Unix.fstat t.lock in
    need(safe_file st && st.Unix.st_perm=0o600 && same_id st (Unix.lstat(private_path t.ctx "lock")))Changed
  let read_target ctx e=
    let p,parent=path ctx e.relative in
    need(parent.Unix.st_dev=e.parent_dev && parent.Unix.st_ino=e.parent_ino &&
      parent.Unix.st_uid=e.parent_uid && parent.Unix.st_gid=e.parent_gid)Changed;
    match stat_opt p with None->Absent_now | Some _->
      let bytes,stat=read_regular p max_file_bytes in Present_now{bytes;stat}
  let matches_old e=function
    | Absent_now->e.old=Absent
    | Present_now c->match e.old with Absent->false|Present old->
      String.length c.bytes=old.size && hash c.bytes=old.sha && c.stat.Unix.st_perm=old.mode &&
      c.stat.Unix.st_uid=old.uid && c.stat.Unix.st_gid=old.gid
  let matches_new e=function Absent_now->false|Present_now c->
    String.length c.bytes=e.fresh_size && hash c.bytes=e.fresh_sha && c.stat.Unix.st_perm=0o600 &&
    c.stat.Unix.st_uid=e.fresh_uid && c.stat.Unix.st_gid=e.fresh_gid
  let classify e c=match matches_old e c,matches_new e c with
    | true,true->Both | true,false->Old | false,true->New | false,false->Unknown
  let same_current a b=match a,b with Absent_now,Absent_now->true
    | Present_now a,Present_now b->same_snapshot a.stat b.stat && a.bytes=b.bytes | _->false
  let private_image ctx kind i expected_sha expected_size=
    let bytes,_=read_regular ~mode:0o600 (private_path ctx(image_name kind i))max_file_bytes in
    need(String.length bytes=expected_size && hash bytes=expected_sha)Corrupt_state;bytes
  let int=function `Int n->n|_->raise(Stop Corrupt_state)
  let str=function `String s->s|_->raise(Stop Corrupt_state)
  let obj keys=function `Assoc fs->
    need(List.sort compare(List.map fst fs)=List.sort compare keys)Corrupt_state;fs
    |_->raise(Stop Corrupt_state)
  let get k fs=try List.assoc k fs with Not_found->raise(Stop Corrupt_state)
  let json_old=function Absent->`Null | Present o->`Assoc[
    "sha256",`String o.sha;"size",`Int o.size;"mode",`Int o.mode;"uid",`Int o.uid;"gid",`Int o.gid]
  let json_entry e=`Assoc["relative",`String e.relative;"parent_dev",`Int e.parent_dev;
    "parent_ino",`Int e.parent_ino;"parent_uid",`Int e.parent_uid;"parent_gid",`Int e.parent_gid;
    "old",json_old e.old;"new_sha256",`String e.fresh_sha;"new_size",`Int e.fresh_size;
    "new_uid",`Int e.fresh_uid;"new_gid",`Int e.fresh_gid]
  let descriptor ctx root entries=Yojson.Safe.to_string(`Assoc[
    "version",`Int 1;"root",`String ctx.root;"root_dev",`Int root.Unix.st_dev;
    "root_ino",`Int root.Unix.st_ino;"root_uid",`Int root.Unix.st_uid;"root_gid",`Int root.Unix.st_gid;
    "transaction_id",`String ctx.id;
    "candidate",`String ctx.candidate;"manifest_sha256",`String ctx.manifest;
    "entries",`List(Array.to_list(Array.map json_entry entries))])
  let parse_descriptor ctx bytes=
    let json=Yojson.Safe.from_string bytes in
    need(Yojson.Safe.to_string json=bytes)Corrupt_state;
    let fs=obj["version";"root";"root_dev";"root_ino";"root_uid";"root_gid";
      "transaction_id";"candidate";"manifest_sha256";"entries"]json in
    need(int(get "version" fs)=1)Corrupt_state;
    need(str(get "root" fs)=ctx.root && str(get "transaction_id" fs)=ctx.id &&
      str(get "candidate" fs)=ctx.candidate && str(get "manifest_sha256" fs)=ctx.manifest)Binding_mismatch;
    let root=root_stat ctx in
    need(int(get "root_dev" fs)=root.Unix.st_dev && int(get "root_ino" fs)=root.Unix.st_ino &&
      int(get "root_uid" fs)=root.Unix.st_uid && int(get "root_gid" fs)=root.Unix.st_gid)Changed;
    let entries=match get "entries" fs with `List xs->
      need(List.length xs>=1 && List.length xs<=max_files)Corrupt_state;
      List.map(fun j->let f=obj["relative";"parent_dev";"parent_ino";"parent_uid";"parent_gid";
        "old";"new_sha256";"new_size";"new_uid";"new_gid"]j in
        let rel=str(get "relative" f) in need(target_relative ctx rel)Corrupt_state;
        let old=match get "old" f with `Null->Absent | j->let o=obj["sha256";"size";"mode";"uid";"gid"]j in
          let sha=str(get "sha256" o) and size=int(get "size" o) and mode=int(get "mode" o) in
          let uid=int(get "uid" o) and gid=int(get "gid" o) in
          need(hex64 sha && size>=0 && size<=max_file_bytes && mode>=0 && mode<=0o7777 &&
            uid=Unix.geteuid() && gid>=0)Corrupt_state;
          Present{sha;size;mode;uid;gid} in
        let fresh_sha=str(get "new_sha256" f) and fresh_size=int(get "new_size" f) in
        let fresh_uid=int(get "new_uid" f) and fresh_gid=int(get "new_gid" f) in
        let parent_uid=int(get "parent_uid" f) and parent_gid=int(get "parent_gid" f) in
        need(hex64 fresh_sha && fresh_size>=0 && fresh_size<=max_file_bytes &&
          fresh_uid=Unix.geteuid() && fresh_gid>=0 && parent_uid=Unix.geteuid() && parent_gid>=0)Corrupt_state;
        {relative=rel;parent_dev=int(get "parent_dev" f);parent_ino=int(get "parent_ino" f);
          parent_uid;parent_gid;old;fresh_sha;fresh_size;fresh_uid;fresh_gid})xs
      |> Array.of_list | _->raise(Stop Corrupt_state) in
    let paths=Array.to_list(Array.map(fun e->e.relative)entries) in
    need(List.length paths=List.length(List.sort_uniq compare paths))Corrupt_state;entries
  let event op index kind=Yojson.Safe.to_string(`Assoc[
    "kind",`String kind;"operation",`String op;"index",`Int index])
  let read_events t=
    let bytes,_=read_regular ~mode:0o600 (private_path t.ctx "events.jsonl")max_event_bytes in
    let lines=if bytes="" then [] else (
      need(String.ends_with ~suffix:"\n" bytes)Corrupt_state;
      String.sub bytes 0 (String.length bytes-1)|>String.split_on_char '\n') in
    need(List.length lines<=max_events)Resource_bound;
    let pending=List.fold_left(fun pending line->
      let j=Yojson.Safe.from_string line in need(Yojson.Safe.to_string j=line)Corrupt_state;
      let f=obj["kind";"operation";"index"]j in
      let op=str(get "operation" f) and index=int(get "index" f) in
      need((op="replace" || op="restore") && index>=0 && index<count t)Corrupt_state;
      match str(get "kind" f) with
      | "intent"->Some(op,index)
      | "checkpoint"->need(pending=Some(op,index))Corrupt_state;None
      |_->raise(Stop Corrupt_state))None lines in
    List.length lines,String.length bytes,pending
  let reserve_operation t op index restore=
    let n,used,pending=read_events t in
    let needs_intent=pending<>Some(op,index) in
    let line op index kind=String.length(event op index kind)+1 in
    let own_events=if needs_intent then 2 else 1 in
    let own_bytes=line op index "checkpoint" + if needs_intent then line op index "intent" else 0 in
    let rollback_events=if restore then 0 else 2*count t in
    let rollback_bytes=if restore then 0 else
      Array.to_list(Array.mapi(fun i _->line "restore" i "intent" + line "restore" i "checkpoint")t.entries)
      |>List.fold_left(+)0 in
    need(n+own_events+rollback_events<=max_events && used+own_bytes+rollback_bytes<=max_event_bytes)Resource_bound;
    needs_intent
  let append_event t op index kind=
    let n,size,_=read_events t in let line=event op index kind ^ "\n" in
    need(n<max_events && size+String.length line<=max_event_bytes)Resource_bound;
    let p=private_path t.ctx "events.jsonl" in let before=Unix.lstat p in
    let fd=Unix.openfile p [Unix.O_WRONLY;Unix.O_APPEND;Unix.O_NONBLOCK;Unix.O_CLOEXEC]0 in
    Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
      need(same_snapshot before(Unix.fstat fd))Changed;write_all fd line;Unix.fsync fd);
    sync_directory(state t.ctx)
  let check_descriptor t=
    check_handle t;
    let bytes,_=read_regular ~mode:0o600 (private_path t.ctx "descriptor.json")max_descriptor in
    let stamp,_=read_regular ~mode:0o600 (private_path t.ctx "descriptor.sha256")64 in
    need(hex64 stamp && stamp=t.descriptor_hash && hash bytes=stamp)Corrupt_state;
    ignore(parse_descriptor t.ctx bytes);ignore(read_events t)
  let check_private_images t=
    Array.iteri(fun i e->ignore(private_image t.ctx "new" i e.fresh_sha e.fresh_size);
      match e.old with Absent->()|Present o->ignore(private_image t.ctx "old" i o.sha o.size))t.entries;
    let expected=["lock";"descriptor.json";"descriptor.sha256";"events.jsonl"] @
      (Array.to_list(Array.mapi(fun i e->image_name "new" i ::
        (match e.old with Absent->[]|Present _->[image_name "old" i]))t.entries)|>List.concat) in
    let dir=Unix.opendir(state t.ctx) in
    let actual=Fun.protect ~finally:(fun()->Unix.closedir dir)(fun()->
      let rec read n xs=match (try Some(Unix.readdir dir)with End_of_file->None)with
        | None->xs | Some("."|"..")->read n xs
        | Some name->need(n<4+2*max_files)Corrupt_state;read(n+1)(name::xs) in read 0 []) in
    need(List.sort compare actual=List.sort compare expected)Corrupt_state
  let all_known t=
    let parents=Hashtbl.create max_files and files=Hashtbl.create max_files in
    Array.iter(fun e->
      let key=e.parent_dev,e.parent_ino,Filename.basename e.relative in
      need(not(Hashtbl.mem parents key))Unsafe_path;Hashtbl.add parents key ();
      let current=read_target t.ctx e in need(classify e current<>Unknown)Unknown_image;
      match current with Absent_now->()|Present_now c->
        let key=c.stat.Unix.st_dev,c.stat.Unix.st_ino in
        need(not(Hashtbl.mem files key))Unsafe_path;Hashtbl.add files key ())t.entries
  let ensure_stage ctx e i kind bytes mode uid gid=
    let p=temp_path ctx e i kind in
    (match stat_opt p with None->create_file ~owner:(uid,gid) p bytes mode | Some _->());
    (* Always verify BOTH fresh and reused stages. chmod/chown may silently
       strip metadata on some filesystems; never discover that after rename. *)
    let actual,st=read_regular p max_file_bytes in
    need(actual=bytes && st.Unix.st_perm=mode && st.Unix.st_uid=uid && st.Unix.st_gid=gid)Corrupt_state;
    sync_directory(Filename.dirname p);p
  let prepare ctx (edits:edit list)=safe(fun()->
    let rec bounded_count n=function []->n|_::xs->need(n<max_files)Invalid_input;bounded_count(n+1)xs in
    need(bounded_count 0 edits>=1)Invalid_input;
    let paths=List.map(fun (e:edit)->e.relative)edits in
    need(List.length paths=List.length(List.sort_uniq compare paths))Invalid_input;
    List.iter(fun (e:edit)->need(relative e.relative && String.length e.replacement<=max_file_bytes)Invalid_input;
      need(target_relative ctx e.relative)Unsafe_path)edits;
    let root=root_stat ctx in
    let state_dir,parent=path ctx ctx.state_relative in
    (try Unix.mkdir state_dir 0o700 with Unix.Unix_error(Unix.EEXIST,_,_)->raise(Stop Already_exists));
    Unix.chmod state_dir 0o700;sync_directory(Filename.dirname state_dir);
    need(same_id parent(Unix.lstat(Filename.dirname state_dir)))Changed;
    let lock=acquire ctx true in
    try
      let aliases=Hashtbl.create max_files and file_aliases=Hashtbl.create max_files in
      let entries=List.mapi(fun i (edit:edit)->
        let p,parent=path ctx edit.relative in
        let key=parent.Unix.st_dev,parent.Unix.st_ino,Filename.basename p in
        need(not(Hashtbl.mem aliases key))Unsafe_path;Hashtbl.add aliases key ();
        let old=match stat_opt p with None->Absent | Some _->
          let bytes,st=read_regular p max_file_bytes in
          let key=st.Unix.st_dev,st.Unix.st_ino in
          need(not(Hashtbl.mem file_aliases key))Unsafe_path;Hashtbl.add file_aliases key ();
          create_file(private_path ctx(image_name "old" i))bytes 0o600;
          Present{sha=hash bytes;size=String.length bytes;mode=st.Unix.st_perm;
            uid=st.Unix.st_uid;gid=st.Unix.st_gid} in
        create_file(private_path ctx(image_name "new" i))edit.replacement 0o600;
        let fresh_uid,fresh_gid=match old with Absent->Unix.geteuid(),parent.Unix.st_gid|Present o->o.uid,o.gid in
        let e={relative=edit.relative;parent_dev=parent.Unix.st_dev;parent_ino=parent.Unix.st_ino;
          parent_uid=parent.Unix.st_uid;parent_gid=parent.Unix.st_gid;old;
          fresh_sha=hash edit.replacement;fresh_size=String.length edit.replacement;fresh_uid;fresh_gid} in
        ignore(ensure_stage ctx e i "new" edit.replacement 0o600 fresh_uid fresh_gid);e)edits|>Array.of_list in
      let bytes=descriptor ctx root entries in need(String.length bytes<=max_descriptor)Resource_bound;
      create_file(private_path ctx "events.jsonl")"" 0o600;
      create_file(private_path ctx "descriptor.json")bytes 0o600;
      create_file(private_path ctx "descriptor.sha256")(hash bytes)0o600;
      sync_directory state_dir;
      let t={ctx;entries;descriptor_hash=hash bytes;lock;owner_pid=Unix.getpid();closed=false} in
      check_private_images t;all_known t;t
    with e->release ctx lock;raise e)
  let load ctx ~expected_descriptor_sha256=safe(fun()->
    need(hex64 expected_descriptor_sha256)Invalid_input;
    let lock=acquire ctx false in
    try
      let bytes,_=read_regular ~mode:0o600 (private_path ctx "descriptor.json")max_descriptor in
      let stamp,_=read_regular ~mode:0o600 (private_path ctx "descriptor.sha256")64 in
      need(hex64 stamp)Corrupt_state;
      need(stamp=expected_descriptor_sha256)Binding_mismatch;
      need(hash bytes=expected_descriptor_sha256)Corrupt_state;
      let entries=parse_descriptor ctx bytes in
      let t={ctx;entries;descriptor_hash=stamp;lock;owner_pid=Unix.getpid();closed=false} in
      check_descriptor t;check_private_images t;all_known t;t
    with e->release ctx lock;raise e)
  let at t index=need(index>=0 && index<count t)Invalid_input;t.entries.(index)
  let inspect t ~index=safe(fun()->check_descriptor t;let e=at t index in classify e(read_target t.ctx e))
  let mutate ?(after_mutation=fun()->()) ?(after_parent_sync=fun()->()) t ~index ~restore=safe(fun()->
    check_descriptor t;let e=at t index in
    check_private_images t;all_known t;
    let original=read_target t.ctx e in need(classify e original<>Unknown)Unknown_image;
    let op=if restore then "restore" else "replace" in
    let needs_intent=reserve_operation t op index restore in
    if needs_intent then append_event t op index "intent";
    let p,_=path t.ctx e.relative in
    let already=if restore then matches_old e original else matches_new e original in
    if not already then (
      let desired=if restore then match e.old with Absent->None|Present o->
          Some(private_image t.ctx "old" index o.sha o.size,o.mode,o.uid,o.gid)
        else Some(private_image t.ctx "new" index e.fresh_sha e.fresh_size,0o600,e.fresh_uid,e.fresh_gid) in
      let stage=match desired with None->None|Some(bytes,mode,uid,gid)->
        Some(ensure_stage t.ctx e index (if restore then "restore" else "new") bytes mode uid gid) in
      need(same_current original(read_target t.ctx e))Changed;
      (match stage with None->Unix.unlink p|Some temp->Unix.rename temp p);
      after_mutation());
    (* An earlier process may have renamed and died BEFORE its parent fsync.
       Known desired bytes do not prove durable directory state: sync also on
       every idempotent/Absent/Both replay, before issuing its checkpoint. *)
    sync_directory(Filename.dirname p);after_parent_sync();
    let actual=read_target t.ctx e in
    need((if restore then matches_old e actual else matches_new e actual))Changed;
    append_event t op index "checkpoint")
  let replace_one ?after_mutation ?after_parent_sync t ~index=
    mutate ?after_mutation ?after_parent_sync t ~index ~restore:false
  let restore_one ?after_mutation ?after_parent_sync t ~index=
    mutate ?after_mutation ?after_parent_sync t ~index ~restore:true
  let verify_previous t=safe(fun()->check_descriptor t;check_private_images t;
    Array.iter(fun e->need(matches_old e(read_target t.ctx e))Unknown_image)t.entries)
  let verify_replacement t=safe(fun()->check_descriptor t;check_private_images t;
    Array.iter(fun e->need(matches_new e(read_target t.ctx e))Unknown_image)t.entries)
end
include Kernel
