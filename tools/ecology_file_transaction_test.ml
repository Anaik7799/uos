#use "ecology_file_transaction.ml";;

(* Actual-FS private synthetic fixtures only. Product is a library, not a CLI.
   Worker modes below refuse non-private/non-temp roots and use fixed synthetic
   bindings; they are test children, not live cutover commands or grant paths.
   Crash77 is injected after a real rename/unlink, before parent fsync and ACK.
   Fresh interpreter recovery checks bytes/absence/modes, not merely statuses.
   This is process-crash evidence, NOT a power-loss or hostile-filesystem proof.
   All fixture trees are preserved, including any failed case. *)
module K=Kernel
let checks=ref 0
let check name yes=incr checks;if not yes then failwith("TEST FAILED: "^name)
let ok=function Ok x->x|Error e->failwith("unexpected "^K.error_label e)
let id=String.make 64 'c' and candidate=String.make 64 'a' and manifest=String.make 64 'b'
let context root=ok(K.make_context ~root ~state_relative:".transaction" ~transaction_id:id
  ~candidate ~manifest_sha256:manifest)
let stat_opt path=try Some(Unix.lstat path)with Unix.Unix_error(Unix.ENOENT,_,_)->None
let read path=let ic=open_in_bin path in Fun.protect ~finally:(fun()->close_in ic)(fun()->
  let n=in_channel_length ic in if n>2*K.max_file_bytes then failwith "test read bound";
  really_input_string ic n)
let write ?(mode=0o600) path body=
  let fd=Unix.openfile path [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_TRUNC;Unix.O_CLOEXEC]mode in
  let out=Unix.out_channel_of_descr fd in Fun.protect ~finally:(fun()->close_out out)(fun()->
    output_string out body;flush out;Unix.fchmod fd mode;Unix.fsync fd)
(* Test-only stand-in for separately retained trusted controller state. Product
   never reads this file; load receives a caller pin, not the journal checksum. *)
let controller_pin root=Filename.concat root ".trusted-controller-descriptor-pin"
let save_pin root t=write(controller_pin root)(K.private_descriptor_sha256 t)
let external_pin root=let pin=read(controller_pin root)in
  if String.length pin<>64 then failwith "controller pin bound";pin
let load root=K.load(context root) ~expected_descriptor_sha256:(external_pin root)
let close t=ignore(ok(K.close t))
let relative i=Printf.sprintf "files/target-%02d.conf" i
let target root i=Filename.concat root(relative i)
let old i=if i mod 3=0 then None else Some("old:"^string_of_int i,
  if i mod 4=1 then 0o644 else if i mod 2=0 then 0o640 else 0o600)
let fresh i="new:"^string_of_int i^String.make(i+1)'z'
let edits n=List.init n(fun i->{K.relative=relative i;replacement=fresh i})
let initialize root n=
  Unix.mkdir root 0o700;Unix.mkdir(Filename.concat root "files")0o700;
  for i=0 to n-1 do match old i with None->()|Some(body,mode)->write ~mode(target root i)body done
let verify_old root n=
  for i=0 to n-1 do match old i with
  | None->check "original absence restored" (stat_opt(target root i)=None)
  | Some(body,mode)->check "original bytes restored" (read(target root i)=body);
    let st=Unix.stat(target root i)in
    check "original mode restored" (st.Unix.st_perm=mode);
    check "original uid restored" (st.Unix.st_uid=Unix.geteuid());
    check "original gid restored" (st.Unix.st_gid=Unix.getegid())
  done
let verify_new root n=
  for i=0 to n-1 do
    check "new bytes installed" (read(target root i)=fresh i);
    let st=Unix.stat(target root i)in
    check "new mode0600" (st.Unix.st_perm=0o600);
    check "replacement preserves uid" (st.Unix.st_uid=Unix.geteuid());
    check "replacement preserves gid" (st.Unix.st_gid=Unix.getegid())
  done
let worker_allowed root=
  let temp=Unix.realpath(Filename.get_temp_dir_name()) in
  let prefix=temp ^ "/uos-file-transaction-test-" in
  String.starts_with ~prefix root && Unix.realpath root=root &&
  let st=Unix.lstat root in st.Unix.st_kind=Unix.S_DIR &&
    st.Unix.st_uid=Unix.geteuid() && st.Unix.st_perm=0o700
let worker mode root n stop=
  if not(worker_allowed root) || n<1 || n>15 || stop<0 || stop>=n then exit 2;
  let ctx=context root in
  if mode="expect-busy" then (match K.load ctx ~expected_descriptor_sha256:(external_pin root) with Error K.Busy->exit 0|_->exit 3);
  let t=ok(K.load ctx ~expected_descriptor_sha256:(external_pin root)) in
  Fun.protect ~finally:(fun()->close t)(fun()->
    match mode with
    | "apply-crash"->for i=0 to stop do
        let after_mutation()=if i=stop then Unix._exit 77 in
        ignore(ok(K.replace_one ~after_mutation t ~index:i)) done;exit 4
    | "restore-crash"->for i=n-1 downto stop do
        let after_mutation()=if i=stop then Unix._exit 77 in
        ignore(ok(K.restore_one ~after_mutation t ~index:i)) done;exit 4
    | "apply-all"->for i=0 to n-1 do ignore(ok(K.replace_one t ~index:i))done;
        ignore(ok(K.verify_replacement t))
    | "recover"->for i=n-1 downto 0 do ignore(ok(K.restore_one t ~index:i))done;
        ignore(ok(K.verify_previous t))
    | _->exit 2)
let ()=match Array.to_list Sys.argv with
  | [_;"--worker";mode;root;n;stop]->
    (try worker mode root(int_of_string n)(int_of_string stop);exit 0
     with Failure message->prerr_endline message;exit 5)
  | [_]->()
  | _->prerr_endline "test takes no arguments";exit 2

let temp=Unix.realpath(Filename.get_temp_dir_name())
let run_dir=Filename.concat temp("uos-file-transaction-test-"^string_of_int(Unix.getpid()))
let ()=Unix.mkdir run_dir 0o700
let serial=ref 0
let fixture n label=incr serial;let root=Filename.concat run_dir(Printf.sprintf "%03d-%s" !serial label)in
  initialize root n;root
let interpreter=Unix.realpath Sys.executable_name
let source=Unix.realpath Sys.argv.(0)
let run_child root n mode stop=
  let prefix=Filename.concat root(Printf.sprintf "child-%s-%d" mode stop) in
  let out=Unix.openfile(prefix^".stdout")[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in
  let err=Unix.openfile(prefix^".stderr")[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in
  let argv=[|"/usr/bin/timeout";"--kill-after=1s";"12s";interpreter;"-w";
    "@A-4-29-40-41-42-44-45-48-58";source;"--worker";mode;root;string_of_int n;string_of_int stop|] in
  let pid=Fun.protect ~finally:(fun()->Unix.close out;Unix.close err)
    (fun()->Unix.create_process argv.(0)argv Unix.stdin out err) in
  let _,status=Unix.waitpid[]pid in match status with Unix.WEXITED code->code|_-> -1
let prepared root n=let t=ok(K.prepare(context root)(edits n))in save_pin root t;close t
let private_file root name=Filename.concat(Filename.concat root ".transaction")name
let load_refused name root predicate=let answer=load root in
  (match answer with Ok t->close t|Error _->());
  check name(match answer with Error e->predicate e|Ok _->false)
let is_hold _=true
let hash s=Cryptokit.hash_string(Cryptokit.Hash.sha256())s
  |>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let rewrite_descriptor root f=
  let path=private_file root "descriptor.json" in
  let changed=f(Yojson.Safe.from_string(read path)) |>Yojson.Safe.to_string in
  write path changed;write(private_file root "descriptor.sha256")(hash changed)
let observe_parent_sync root observations ()=
  incr observations;
  let lines=read(private_file root "events.jsonl") |>String.split_on_char '\n'|>List.filter((<>)"")in
  let last=List.hd(List.rev lines)|>Yojson.Safe.from_string in
  check "actual parent fsync callback precedes checkpoint"
    (Yojson.Safe.Util.member "kind" last=`String"intent")
let ()=
  List.iter(fun n->
    let root=fixture n "normal" in let ctx=context root in let t=ok(K.prepare ctx(edits n))in
    save_pin root t;
    check "exact file count" (K.count t=n);verify_old root n;
    check "private directory0700" ((Unix.stat(Filename.concat root ".transaction")).Unix.st_perm=0o700);
    Array.iter(fun name->check "private file0600"
      ((Unix.stat(private_file root name)).Unix.st_perm=0o600))(Sys.readdir(Filename.concat root ".transaction"));
    check "sameprocess lock refuses" (load root=Error K.Busy);
    let fork=Unix.fork()in
    if fork=0 then Unix._exit(if K.close t=Error K.Closed then 0 else 7);
    check "inherited handle close refuses without unlock" (snd(Unix.waitpid[]fork)=Unix.WEXITED 0);
    check "freshprocess lock nonblocking" (run_child root n "expect-busy" 0=0);
    check "old set not replacement" (K.verify_replacement t=Error K.Unknown_image);
    for i=0 to n-1 do ignore(ok(K.replace_one t ~index:i))done;verify_new root n;
    ignore(ok(K.verify_replacement t));
    check "new state not mistaken for previous" (K.verify_previous t=Error K.Unknown_image);
    let syncs=ref 0 in
    ignore(ok(K.replace_one ~after_parent_sync:(observe_parent_sync root syncs) t ~index:0));
    check "already-new replay fsyncs parent" (!syncs=1);
    for i=n-1 downto 0 do ignore(ok(K.restore_one t ~index:i))done;
    ignore(ok(K.verify_previous t));verify_old root n;
    let syncs=ref 0 in
    ignore(ok(K.restore_one ~after_parent_sync:(observe_parent_sync root syncs) t ~index:0));
    check "already-absent replay fsyncs parent" (!syncs=1);close t;
    check "closed handle refuses" (K.replace_one t ~index:0=Error K.Closed);
    let loaded=ok(load root)in ignore(ok(K.verify_previous loaded));close loaded)
    [14;15];
  List.iter(fun n->for stop=0 to n-1 do
    let root=fixture n "apply-crash" in prepared root n;
    check "real postrename apply crash77" (run_child root n "apply-crash" stop=77);
    check "freshprocess full recovery" (run_child root n "recover" 0=0);
    verify_old root n;
    let root=fixture n "restore-crash" in prepared root n;
    check "freshprocess all new" (run_child root n "apply-all" 0=0);
    check "real postmutation restore crash77" (run_child root n "restore-crash" stop=77);
    check "freshprocess recovery after recovery crash" (run_child root n "recover" 0=0);
    verify_old root n
  done)[14;15];
  let root=fixture 2 "unknown-edit" in let t=ok(K.prepare(context root)(edits 2))in
  save_pin root t;
  write(target root 1)"external-UNKNOWN";
  check "inspect external edit UNKNOWN" (K.inspect t ~index:1=Ok K.Unknown);
  check "unrelated unknown prevents effects" (K.replace_one t ~index:0=Error K.Unknown_image);
  check "unknown never overwritten on restore" (K.restore_one t ~index:1=Error K.Unknown_image);
  check "external bytes unchanged" (read(target root 1)="external-UNKNOWN");close t;
  load_refused "freshload unknown HOLD" root((=)K.Unknown_image);
  let root=fixture 2 "unknown-mode" in prepared root 2;
  Unix.chmod(target root 1)0o400;load_refused "external mode HOLD" root((=)K.Unknown_image);
  let root=fixture 2 "external-delete" in prepared root 2;
  Unix.unlink(target root 1);load_refused "external deletion HOLD" root((=)K.Unknown_image);
  List.iter(fun name->let root=fixture 2 ("missing-"^name)in prepared root 2;
    Unix.unlink(private_file root name);load_refused "incomplete private state refuses" root is_hold;
    load_refused "failedload releases lock" root is_hold)
    ["descriptor.json";"descriptor.sha256";"old-01.bin";"new-00.bin";"events.jsonl"];
  let root=fixture 2 "backup-corrupt" in prepared root 2;
  write(private_file root "old-01.bin")"BAD:1";load_refused "backup digest corrupt refuses" root((=)K.Corrupt_state);
  let root=fixture 2 "descriptor-malformed" in prepared root 2;
  rewrite_descriptor root(function `Assoc fs->`Assoc(List.remove_assoc "entries" fs)|_->assert false);
  load_refused "malformed descriptor coherent stamp cannot change external pin" root((=)K.Binding_mismatch);
  let root=fixture 2 "descriptor-binding" in prepared root 2;
  let other=ok(K.make_context ~root ~state_relative:".transaction" ~transaction_id:id
    ~candidate:(String.make 64 'f') ~manifest_sha256:manifest)in
  check "candidate context binding required" (K.load other ~expected_descriptor_sha256:(external_pin root)=Error K.Binding_mismatch);
  let root=fixture 2 "coherent-private-rewrite" in prepared root 2;
  let forged="coherent altered replacement" in
  write(private_file root "new-00.bin")forged;
  write(Filename.concat root (Printf.sprintf "files/.uos-txn-%s-00-new" id))forged;
  rewrite_descriptor root(function
    | `Assoc fs->`Assoc(List.map(fun(k,v)->if k="entries" then k,(match v with
      | `List(`Assoc first::rest)->`List(`Assoc(List.map(fun(k,v)->
        if k="new_sha256" then k,`String(hash forged)
        else if k="new_size" then k,`Int(String.length forged) else k,v)first)::rest)
      |_->failwith "fixture entries") else k,v)fs)
    |_->failwith "fixture descriptor");
  check "coherent rewrite actually changed same-journal pin"
    (external_pin root<>read(private_file root "descriptor.sha256"));
  load_refused "coherent descriptor stamp and image rewrite refuses trusted original pin"
    root((=)K.Binding_mismatch);
  verify_old root 2;
  let root=fixture 2 "state-extra-file" in prepared root 2;
  write(private_file root "unexpected")"x";load_refused "extra private file refuses" root((=)K.Corrupt_state);
  let root=fixture 2 "state-permissions" in prepared root 2;
  Unix.chmod(private_file root "old-01.bin")0o644;load_refused "backup public mode refuses" root((=)K.Corrupt_state);
  let root=fixture 2 "bad-event" in prepared root 2;
  write(private_file root "events.jsonl")"{\"kind\":\"checkpoint\",\"operation\":\"replace\",\"index\":0}\n";
  load_refused "checkpoint without durable intent refuses" root((=)K.Corrupt_state);
  let root=fixture 2 "partial-event-tail" in prepared root 2;
  let t=ok(load root)in ignore(ok(K.replace_one t ~index:0));close t;
  let event_path=private_file root "events.jsonl" in
  let tail=read event_path ^ "{\"kind\":\"intent\"" in
  write event_path tail;
  let preimage=read(private_file root "old-01.bin") in
  let fresh_image=read(private_file root "new-00.bin") in
  let current0=read(target root 0) and current1=read(target root 1)in
  load_refused "partial event tail HOLD for manual reconciliation" root((=)K.Corrupt_state);
  check "partial tail never truncated or regenerated" (read event_path=tail);
  check "partial tail preserves private preimages" (read(private_file root "old-01.bin")=preimage &&
    read(private_file root "new-00.bin")=fresh_image);
  check "partial tail preserves current target images" (read(target root 0)=current0 && read(target root 1)=current1);
  let root=fixture 2 "bounded-rollback-escrow" in prepared root 2;
  let t=ok(load root)in ignore(ok(K.replace_one t ~index:0));
  for _=1 to 125 do ignore(ok(K.replace_one t ~index:0))done;
  let events_before=read(private_file root "events.jsonl") in
  let original1=read(target root 1) and inode1=(Unix.lstat(target root 1)).Unix.st_ino in
  check "forward full pair and rollback credit reserved before mutation"
    (K.replace_one t ~index:1=Error K.Resource_bound);
  check "near-capacity refusal adds no intent or false checkpoint"
    (read(private_file root "events.jsonl")=events_before);
  check "near-capacity forward refusal does not mutate old target"
    (read(target root 1)=original1 && (Unix.lstat(target root 1)).Unix.st_ino=inode1);
  ignore(ok(K.restore_one t ~index:1));ignore(ok(K.restore_one t ~index:0));
  ignore(ok(K.verify_previous t));verify_old root 2;
  let lines=read(private_file root "events.jsonl")|>String.split_on_char '\n'|>List.filter((<>)"")in
  check "reserved one full restore completes exactly at256 events" (List.length lines=256);
  let at_cap=read(private_file root "events.jsonl")in
  check "further retries HOLD at finite journal cap" (K.restore_one t ~index:0=Error K.Resource_bound);
  check "finite retry HOLD preserves full log" (read(private_file root "events.jsonl")=at_cap);
  close t;
  let root=fixture 2 "stage-metadata-refusal" in prepared root 2;
  let t=ok(load root)in
  let stage=Filename.concat root(Printf.sprintf "files/.uos-txn-%s-00-new" id)in
  Unix.chmod stage 0o640;
  check "wrong staged metadata refuses before rename" (K.replace_one t ~index:0=Error K.Corrupt_state);
  check "stage failure leaves absent target absent" (stat_opt(target root 0)=None);
  check "stage failure leaves other target bytes intact" (read(target root 1)="old:1");
  close t;
  let root=fixture 2 "target-hardlink" in
  Unix.link(target root 1)(Filename.concat root "alias");
  check "hardlink target refuses" (K.prepare(context root)(edits 2)=Error K.Unsafe_path);
  let root=fixture 2 "target-symlink" in
  Unix.unlink(target root 1);Unix.symlink "target-00.conf" (target root 1);
  check "symlink target refuses before read" (K.prepare(context root)(edits 2)=Error K.Unsafe_path);
  let root=fixture 2 "parent-symlink" in
  Unix.symlink "files" (Filename.concat root "alias");
  check "symlink parent refuses" (K.prepare(context root)[{K.relative="alias/target-01.conf";replacement="x"}]=Error K.Unsafe_path);
  let root=fixture 2 "duplicate" in
  check "duplicate targets refuse" (K.prepare(context root)[{K.relative=relative 0;replacement="x"};{K.relative=relative 0;replacement="y"}]=Error K.Invalid_input);
  let root=fixture 2 "traversal" in
  List.iter(fun path->check "unsafe relative refuses"
    (match K.prepare(context root)[{K.relative=path;replacement="x"}]with Error _->true|_->false))
    ["../outside";"/etc/passwd";"files/../other";"files//x";".jj/config";"files/auth.json";".uos-txn-forged"];
  let root=fixture 1 "bound-new" in
  check "new image over bound refuses before prepare"
    (K.prepare(context root)[{K.relative=relative 0;replacement=String.make(K.max_file_bytes+1)'x'}]=Error K.Invalid_input);
  let root=fixture 2 "bound-old" in write(target root 1)(String.make(K.max_file_bytes+1)'x');
  check "old image over bound refuses" (K.prepare(context root)(edits 2)=Error K.Resource_bound);
  let root=fixture 1 "exact-bound" in let bytes=String.make K.max_file_bytes 'n' in
  let t=ok(K.prepare(context root)[{K.relative=relative 0;replacement=bytes}])in
  ignore(ok(K.replace_one t ~index:0));check "exact1MiB image accepted" (read(target root 0)=bytes);
  ignore(ok(K.restore_one t ~index:0));ignore(ok(K.verify_previous t));verify_old root 1;close t;
  let root=fixture 2 "identical-both" in Unix.chmod(target root 1)0o600;
  let before=Unix.lstat(target root 1)in
  let t=ok(K.prepare(context root)[{K.relative=relative 1;replacement="old:1"}])in
  check "identical bytes and0600 mode explicitly Both" (K.inspect t ~index:0=Ok K.Both);
  let mutations=ref 0 in let after_mutation()=incr mutations in
  let syncs=ref 0 in let after_parent_sync=observe_parent_sync root syncs in
  ignore(ok(K.replace_one ~after_mutation ~after_parent_sync t ~index:0));
  ignore(ok(K.restore_one ~after_mutation ~after_parent_sync t ~index:0));
  ignore(ok(K.verify_previous t));ignore(ok(K.verify_replacement t));
  check "identical images perform no mutation" (!mutations=0);
  check "Both-image replays still fsync parent" (!syncs=2);
  check "identical images preserve target inode" ((Unix.lstat(target root 1)).Unix.st_ino=before.Unix.st_ino);
  close t;
  let supplementary=Array.to_list(Unix.getgroups())|>List.find_opt(fun gid->gid<>Unix.getegid())in
  (match supplementary with
  | None->print_endline "supplementary_gid_fixture=UNRUN_NO_DISTINCT_AVAILABLE_GROUP"
  | Some gid->
    let root=fixture 2 "supplementary-gid" in
    Unix.chown(target root 1)(-1)gid;
    let t=ok(K.prepare(context root)(edits 2))in
    for i=0 to 1 do ignore(ok(K.replace_one t ~index:i))done;
    let now=Unix.stat(target root 1)in
    check "nondefault gid preserved in replacement" (now.Unix.st_gid=gid && now.Unix.st_uid=Unix.geteuid());
    for i=1 downto 0 do ignore(ok(K.restore_one t ~index:i))done;
    ignore(ok(K.verify_previous t));let restored=Unix.stat(target root 1)in
    check "nondefault gid and mode restored" (restored.Unix.st_gid=gid && restored.Unix.st_perm=0o644);
    close t;
    let root=fixture 2 "external-gid-edit" in prepared root 2;
    Unix.chown(target root 1)(-1)gid;
    load_refused "external gid change is UNKNOWN" root((=)K.Unknown_image);
    print_endline "supplementary_gid_fixture=PASS");
  Printf.printf "PASS native_file_transaction checks=%d apply_crash_cases=29 restore_crash_cases=29 fresh_process_recovery=true fixtures=%s\n" !checks run_dir
