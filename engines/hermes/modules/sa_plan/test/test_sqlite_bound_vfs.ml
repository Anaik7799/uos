module M=Sqlite_bound_vfs
let checks=ref 0
let check label yes=if not yes then failwith label;incr checks
let ok=function Ok x->x|Error e->failwith(M.error_label e)
let exec db s=check"fixture sql"(Sqlite3.exec db s=Sqlite3.Rc.OK)
let native_close db=check"fixture sqlite close"(Sqlite3.db_close db);Core.Gc.keep_alive db
external fd_identity : Unix.file_descr -> (int64*int64)option = "caml_uos_main_mapping_retained_identity"
let identity p=let fd=Unix.openfile p[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in Fun.protect ~finally:(fun()->Unix.close fd)(fun()->match fd_identity fd with Some(device,inode)->M.{device;inode}|None->failwith"native identity")
let copy a b=let input=open_in_bin a in let n=in_channel_length input in
 if n>33554432 then failwith"fixture copy bound";
 let bytes=Fun.protect ~finally:(fun()->close_in input)(fun()->really_input_string input n)in
 let fd=Unix.openfile b[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
 Fun.protect ~finally:(fun()->Unix.close fd)(fun()->
 let rec loop n=if n<String.length bytes then let k=Unix.write_substring fd bytes n(String.length bytes-n)in if k<=0 then failwith"copy write"else loop(n+k)in loop 0;Unix.fsync fd)
let run_lock path conflict=
 let root="/home/an/NAS-setup/uos"in
 let command=Bos.Cmd.of_list[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"5000";"65536";"merged";Sys.executable_name;"--lock";path;if conflict then"conflict"else"free"]in
 match Bos.OS.Cmd.run_out ~env:(Astring.String.Map.of_list["PATH","/usr/bin:/bin"])command|>Bos.OS.Cmd.out_string with
 |Ok(_,(_,`Exited 0))->check"independent exec actual SHM readmark lock"true|_->failwith"external lock witness"
let child case directory=
 let path=directory^"/a.sqlite3"in let expected=M.{main=identity path;wal=identity(path^"-wal");shm=identity(path^"-shm")}in
 let expected=if case="bad-id"then M.{expected with wal={expected.wal with inode=Int64.succ expected.wal.inode}}else expected in
 (match case with
 |"symlink"->Unix.rename(path^"-wal")(path^"-wal-saved");Unix.symlink(path^"-wal-saved")(path^"-wal")
 |"hardlink"->Unix.link(path^"-wal")(directory^"/alias")
 |"missing"->Unix.rename(path^"-wal")(path^"-wal-saved")
 |"mode"->Unix.chmod(path^"-shm")0o644
 |"journal"->let f=Unix.openfile(path^"-journal")[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in Unix.close f
 |_->());
 if case="race"then(
  let barrier=Atomic.make 0 in
  let contender()=ignore(Atomic.fetch_and_add barrier 1);while Atomic.get barrier<2 do Domain.cpu_relax()done;
   match M.open_readonly ~directory ~basename:"a.sqlite3" ~expected with
   |Ok c->ignore(ok(M.snapshot c));ignore(ok(M.close c));"owner"
   |Error M.Refused->"refused"|Error e->failwith(M.error_label e)in
  let a=Domain.spawn contender and b=Domain.spawn contender in
  let outcomes=List.sort String.compare[Domain.join a;Domain.join b]in
  check"simultaneous first opens exactly one owner"(outcomes=["owner";"refused"]);
  print_endline"PASS race atomic first owner 1 winner 1 refused";exit 0);
 let opened=M.open_readonly ~directory ~basename:"a.sqlite3" ~expected in
 if List.mem case["bad-id";"symlink";"hardlink";"missing";"mode";"journal"]then(
  check"unsafe resource refuses"(match opened with Error _->true|_->false);
  check"pre-open resource refusal cleans without poison"(not(M.process_poisoned()));
  Printf.printf"PASS child %s %d\n%!"case !checks;exit 0);
 let connection=ok opened in
 let before=ok(M.snapshot connection)in check"three exact expected identities"(M.identities before=expected);
 if case="gc"then(
  Gc.set{(Gc.get())with minor_heap_size=4096};
  for n=1 to 1000 do
   ignore(Array.init 32(fun _->Bytes.make 100 'x'));
   check"GC stressed snapshot identities"(M.identities(ok(M.snapshot connection))=expected);
   if n mod 10=0 then Gc.full_major()else Gc.minor()
  done;print_endline"PASS snapshot GC stress 1000 observations 100 full major cycles");
 if case="locks"||case="forbidden-close"then(
  run_lock(path^"-shm")true;
  if case="forbidden-close"then(
   let alias=Unix.openfile(path^"-shm")[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in Unix.close alias;
   run_lock(path^"-shm")false;
   print_endline"COUNTEREXAMPLE foreign same-inode close drops SHM lock; trusted no-other-closes premise REQUIRED"));
 if case="aba"then(
  List.iteri(fun i suffix->let p=path^suffix in let save=directory^"/saved"^string_of_int i in Unix.rename p save;copy save p;
    check"all three pathname clones distinct"(identity p<>List.nth[expected.main;expected.wal;expected.shm]i))["";"-wal";"-shm"];
  check"post-ABA actual connection still bound to original descriptors"(M.identities(ok(M.snapshot connection))=expected));
 if case="thread"then(
  let result=Domain.join(Domain.spawn(fun()->M.snapshot connection))in check"other native thread snapshot refuses"(result=Error M.Ownership);
  let result=Domain.join(Domain.spawn(fun()->M.close connection))in check"other native thread close refuses"(result=Error M.Ownership);
  ignore(ok(M.snapshot connection)));
 Printf.printf"OBSERVATION %s\n%!"(Yojson.Safe.to_string(M.diagnostics(ok(M.snapshot connection))));
 ignore(ok(M.close connection));check"close idempotent exact outcome"(M.close connection=Ok());check"no poisoned cleanup"(not(M.process_poisoned()));
 check"closed refuses"(M.snapshot connection=Error M.Closed);
 check"no connection lifetime reuse"(match M.open_readonly ~directory ~basename:"a.sqlite3"~expected with Error M.Refused->true|_->false);
 (* Verify normal default Unix VFS/open hooks restored AFTER the bound lifetime. *)
 let db=Sqlite3.db_open":memory:"in exec db"CREATE TABLE restored(n)";native_close db;
 Printf.printf"PASS child %s %d\n%!"case !checks
let run_child case=
 let dir=Filename.temp_file"uos-bound-vfs-test-"""in Unix.unlink dir;Unix.mkdir dir 0o700;
 let path=dir^"/a.sqlite3"in let db=Sqlite3.db_open ~mutex:`FULL path in Unix.chmod path 0o600;
 exec db"PRAGMA journal_mode=WAL";exec db"CREATE TABLE fixture(n)";exec db"INSERT INTO fixture VALUES(17)";
 List.iter(fun suffix->Unix.chmod(path^suffix)0o600)["-wal";"-shm"];
 let root="/home/an/NAS-setup/uos"in
 let args=[root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"10000";"1048576";"merged";Sys.executable_name;"--child";case;dir]in
 let env=Astring.String.Map.of_list["PATH","/usr/bin:/bin";"LANG","C.UTF-8"]in
 let result=Bos.OS.Cmd.run_out ~env(Bos.Cmd.of_list args)|>Bos.OS.Cmd.out_string ~trim:false in
 (match result with Ok(text,(_,`Exited code))->Printf.printf"CASE %s fixture=%s exit=%d\n%s%!"case dir code text;check("case "^case)(code=0)|_->failwith"child outcome unknown");
 native_close db
let ()=if Array.length Sys.argv=4&&Sys.argv.(1)="--lock"then(
 let fd=Unix.openfile Sys.argv.(2)[Unix.O_RDWR;Unix.O_CLOEXEC]0 in ignore(Unix.lseek fd 124 Unix.SEEK_SET);
 let acquired=try Unix.lockf fd Unix.F_TLOCK 1;true with Unix.Unix_error((Unix.EACCES|Unix.EAGAIN),_,_)->false in
 Unix.close fd;exit(if acquired=(Sys.argv.(3)="free")then 0 else 2))
 else if Array.length Sys.argv=4&&Sys.argv.(1)="--child"then child Sys.argv.(2)Sys.argv.(3)else(
 List.iter run_child["normal";"aba";"bad-id";"symlink";"hardlink";"missing";"mode";"journal";"thread";"locks";"forbidden-close";"race";"gc"];
 Printf.printf"PASS %d parent checks / 13 isolated cases; readonly no authority\n%!"!checks)
