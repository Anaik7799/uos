(* Actual pinned SQLite/native SQL bridge, synthetic private DBs only. *)
module M=Sqlite_main_mapping
let checks=ref 0
let check label b=if not b then failwith label;incr checks
let ok label=function Ok x->x|Error e->failwith(label^":"^M.error_label e)
let error=function Error _->true|_->false
let exec db sql=check("SQL "^sql)(Sqlite3.exec db sql=Sqlite3.Rc.OK)
let close db=Fun.protect ~finally:(fun()->Core.Gc.keep_alive db)(fun()->check"close sqlite"(Sqlite3.db_close db))
let scalar db sql=let st=Sqlite3.prepare db sql in Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st;Core.Gc.keep_alive db)(fun()->check"scalar row"(Sqlite3.step st=Sqlite3.Rc.ROW);Sqlite3.column_text st 0)
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in check"read bounded"(n<=33554432);really_input_string c n)
let write p s=let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
 Fun.protect ~finally:(fun()->Unix.close fd)(fun()->let rec loop n=if n<String.length s then let k=Unix.write_substring fd s n(String.length s-n)in check"write"(k>0);loop(n+k)in loop 0;Unix.fsync fd)
external parse_maps : string -> int64 -> int64 -> int = "caml_uos_main_mapping_parse_test"
external runtime_data : unit -> string*string*string*string = "caml_uos_main_mapping_runtime"
external identity_range : int64 -> int64 -> bool = "caml_uos_main_mapping_identity_range_test"
external retained_identity : Unix.file_descr -> (int64*int64) option = "caml_uos_main_mapping_retained_identity"
let run_lifetime directory database=
 let source=Filename.concat(Filename.dirname(Filename.dirname Sys.executable_name))"sqlite_main_mapping_stubs.c"in
 let prefix=match Astring.String.cut ~sep:"static void mapping_sql"(read source)with Some(p,_)->p|_->failwith"fixed C parser boundary"in
 let body={c|
static char fixed_maps[MAP_CAP+1];
static int snapshot(void *pointer,struct map_identity *id){
 int f=open("/proc/self/maps",O_RDONLY|O_CLOEXEC|O_NOFOLLOW);if(f<0)return -5;size_t n=0;unsigned attempts=0;
 while(++attempts<256){ssize_t k=read(f,fixed_maps+n,MAP_CAP+1-n);if(k<0){if(errno==EINTR)continue;close(f);return -5;}
 if(!k){int result=parse_maps(fixed_maps,n,(uint64_t)(uintptr_t)pointer,FETCH_BYTES,id);if(close(f))return -5;return result;}
 n+=(size_t)k;if(n>MAP_CAP){close(f);return -2;}}close(f);return -5;}
int main(int argc,char**argv){
 if(argc!=2)return 2;sqlite3 *db=NULL;sqlite3_file *file=NULL;
 if(sqlite3_open_v2(argv[1],&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_FULLMUTEX|SQLITE_OPEN_PRIVATECACHE,NULL)!=SQLITE_OK)return 3;
 int held=open(argv[1],O_RDONLY|O_CLOEXEC);struct stat st;
 if(held<0||fstat(held,&st))return 4;
 if(sqlite3_file_control(db,"main",SQLITE_FCNTL_FILE_POINTER,&file)!=SQLITE_OK||!file||!file->pMethods->xFetch)return 5;
 sqlite3_int64 limit=1048576;if(sqlite3_file_control(db,"main",SQLITE_FCNTL_MMAP_SIZE,&limit)!=SQLITE_OK)return 6;
 void *p=NULL;if(file->pMethods->xFetch(file,0,FETCH_BYTES,&p)!=SQLITE_OK||!p)return 7;
 struct map_identity identity;if(proc_identity(p,&identity)!=1||identity.device!=(uint64_t)st.st_dev||identity.inode!=(uint64_t)st.st_ino)return 8;
 limit=0;if(sqlite3_file_control(db,"main",SQLITE_FCNTL_MMAP_SIZE,&limit)!=SQLITE_OK)return 9;
 if(snapshot(p,&identity)!=1||identity.inode!=(uint64_t)st.st_ino)return 10;
 if(file->pMethods->xUnfetch(file,0,p)!=SQLITE_OK)return 11;
 int after_unfetch=snapshot(p,&identity);if(after_unfetch<0)return 12;
 if(after_unfetch==1&&(identity.device!=(uint64_t)st.st_dev||identity.inode!=(uint64_t)st.st_ino))return 13;
 if(sqlite3_close(db)!=SQLITE_OK)return 14;
 int after_close=snapshot(p,&identity);if(after_close!=0)return 15;
 if(close(held))return 16;
 printf("LIFETIME_WHILE_PINNED=1 AFTER_UNFETCH_MAP=%d AFTER_CLOSE_MAP=%d parser_errors_never_absence=1\n",after_unfetch,after_close);return 0;}
|c}in
 let body=prefix^"\n#include <sys/stat.h>\n"^body in
 let cpath=directory^"/lifetime.c"and exe=directory^"/lifetime.exe"in write cpath body;
 let root="/home/an/NAS-setup/uos"in
 let env=Astring.String.Map.of_list["PATH","/usr/bin:/bin";"LANG","C.UTF-8"]in
 let run label program args=
  let command=Bos.Cmd.of_list([root^"/toolchains/opam-ocaml/bin/ocaml";"-I";"+unix";root^"/tools/ecology_process.ml";"10000";"1048576";"merged";program]@args)in
  match Bos.OS.Cmd.run_out ~env command|>Bos.OS.Cmd.out_string ~trim:false with
  |Ok(text,(_,`Exited code))->Printf.printf"%s %s%!"label text;check label(code=0)
  |_->failwith(label^" unknown")in
 run"lifetime C compile""/nix/store/w88q44gqd1qg5wmkk7v0h97rpiqvam0l-gcc-wrapper-15.3.0/bin/gcc"
  ["-O2";"-I"^root^"/toolchains/opam-ocaml/lib/ocaml";"-I/nix/store/538744yaz5y7xyx780wpfw2azby9iqxj-sqlite-3.53.3-dev/include";
   cpath;"-L/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib";"-Wl,-rpath,/nix/store/xcv2rrfly0za0kdhzvmc0j2a6074zkib-sqlite-3.53.3/lib";"-lsqlite3";"-o";exe];
 run"separate actual unfetch/close observations"exe[database];Unix.unlink cpath;Unix.unlink exe
let ()=
 if Array.length Sys.argv=2&&Sys.argv.(1)="--expect-runtime-hold"then(
  let v,id,path,_=runtime_data()in Printf.printf"WRONG_DSO callbackVersion=%s bindingVersion=%s sourceID=%s path=%s\n%!"v(Sqlite3.sqlite_version_info())id path;
  check"wrong actual DSO refuses before connection"(M.register()=Error M.Unsupported_runtime);
  print_endline"PASS wrong-runtime HOLD no connection opened";exit 0);
 let runtime=ok"runtime"(M.register())in
 check"exact version"(runtime.version="3.53.3"&&Sqlite3.sqlite_version()=3053003);
 Printf.printf"SQLITE=%s SOURCE=%s DSO=%s\n%!"runtime.version runtime.source_id runtime.dso_path;
 let valid="1000-3000 r--s 00000000 08:01 123 /private/never-read\n4000-5000 rw-p 00000000 00:00 0 \n"in
 check"whole mapping positive"(parse_maps valid 0x1000L 4096L=1);
 check"offset within same VMA cannot pretend file offset zero"(parse_maps valid 0x1001L 1L<0);
 check"absent is explicit zero"(parse_maps valid 0x8000L 1L=0);
 check"span beyond VMA refuses"(parse_maps valid 0x1000L 8193L<0);
 check"pointer plus length overflow"(parse_maps valid(-1L)4096L<0);
 let later="2000-3000 r--s 00000000 08:01 123\n"in
 check"overlap with start in gap is HOLD not absent"(parse_maps later 0x1800L 4096L<0);
 check"range ending at VMA start is absent"(parse_maps later 0x1000L 4096L=0);
 check"range starting at VMA end is absent"(parse_maps later 0x3000L 4096L=0);
 check"genuine short gap is absent"(parse_maps later 0x1800L 1L=0);
 check"partial overlap from VMA interior is HOLD"(parse_maps later 0x2800L 4096L<0);
 let alias=Int64.add Int64.min_int 123L in
 check"synthetic native high-bit inode aliases tagged-int 123"(Int64.of_int(Int64.to_int alias)=123L);
 check"synthetic aliased native inode refuses"(not(identity_range 1L alias));
 check"zero native inode refuses"(not(identity_range 0L 0L));
 check"signed64 maximum inode and device supported"(identity_range Int64.max_int Int64.max_int);
 check"beyond OCaml max_int native identity remains supported"(identity_range 0L(Int64.succ(Int64.of_int max_int)));
 check"native high-bit device refuses"(not(identity_range Int64.min_int 1L));
 let make_maps count width=String.concat""(List.init count(fun i->
  let lo=(i+1)*4096 in let prefix=Printf.sprintf"%016x-%016x %s 00000000 08:01 %d "lo(lo+4096)(if i=0 then"r--s"else"rw-p")(if i=0 then 123 else 0)in
  prefix^String.make(width-1-String.length prefix)'x'^"\n"))in
 check"exact byte/line cap complete parse positive"(parse_maps(make_maps 8192 128)4096L 4096L=1);
 check"one extra line refuses after found candidate"(parse_maps(make_maps 8193 96)4096L 4096L<0);
 List.iter(fun raw->check"malformed full maps always HOLD"(parse_maps raw 0x1000L 4096L<0))
 ["";valid^"bad\n";String.sub valid 0(String.length valid-1);valid^"\000\n";
  "1000-3000 r--s 00000000 08:01 123";"1000-3000 r--s 00000000 08:01 -1\n";
  "1000-3000 r--s 00000000 08:01 18446744073709551616\n";
  "1000-3000 r--s 00000000 08:01 123\n2000-5000 rw-p 0 00:00 0\n";
  String.make(1048576+1)'x'];
 List.iter(fun raw->check"unsupported mapping refuses"(parse_maps raw 0x1000L 4096L<0))
 ["1000-3000 rw-s 00000000 08:01 123\n";"1000-3000 r--p 00000000 08:01 123\n";
  "1000-3000 r-xs 00000000 08:01 123\n";"1000-3000 r--s 00001000 08:01 123\n";
  "1000-3000 r--s 00000000 00:00 0\n";"1000-1800 r--s 0 08:01 123\n1800-3000 r--s 800 08:01 123\n"];
 let dir=Filename.temp_file"uos-sqlite-mapping-"""in Unix.unlink dir;Unix.mkdir dir 0o700;
 let a=dir^"/a.sqlite3"and b=dir^"/b.sqlite3"and saved=dir^"/saved.sqlite3"in
 let setup=Sqlite3.db_open ~mutex:`FULL ~cache:`PRIVATE a in Unix.chmod a 0o600;
 exec setup"CREATE TABLE probe(n INTEGER)";exec setup"INSERT INTO probe VALUES(17)";
 check"setup actual DELETE mode"(scalar setup"PRAGMA journal_mode"="delete");close setup;
 write b(read a);check"identical bytes"(read a=read b);
 let held_a=Unix.openfile a[Unix.O_RDONLY;Unix.O_CLOEXEC]0 and held_b=Unix.openfile b[Unix.O_RDONLY;Unix.O_CLOEXEC]0 in
 let open_ro ?(mutex=`FULL) ?vfs p=Sqlite3.db_open ~mode:`READONLY ~mutex ~cache:`PRIVATE ~uri:false ?vfs p in
 let initialize db ~mmap=
  check"SQL actual same source ID"(scalar db"SELECT sqlite_source_id()"=runtime.source_id);
  check"SQL actual version"(scalar db"SELECT sqlite_version()"=runtime.version);
  check"explicit mmap pragma result"(scalar db(if mmap then"PRAGMA mmap_size=1048576"else"PRAGMA mmap_size=0")=(if mmap then"1048576"else"0"));
  exec db"BEGIN";ignore(scalar db"SELECT name FROM sqlite_schema LIMIT 1")in
 let raw_check=open_ro a in initialize raw_check ~mmap:true;exec raw_check"ROLLBACK";close raw_check;
 let db=ok"opaque open A"(M.open_readonly a)in
 let observed=ok"positive connection A"(M.observe_main db ~retained:held_a)in
 check"match independent actual retained A FD"(retained_identity held_a=Some(M.device observed,M.inode observed)&&M.observed_bytes observed=4096);
 check"same bytes B not same mapping object"(M.observe_main db ~retained:held_b=Error M.Identity_mismatch);
 ignore(ok"opaque close A"(M.close db));check"closed object refuses"(M.observe_main db ~retained:held_a=Error M.Closed_connection);
 ignore(ok"idempotent exact close"(M.close db));
 Unix.rename a saved;Unix.rename b a;
 let clone=ok"opaque open substituted B"(M.open_readonly a)in
 Unix.rename a b;Unix.rename saved a;
 check"ABA named A remains true"((Unix.stat a).st_ino=(Unix.fstat held_a).st_ino);
 check"ABA mapping rejects expected A"(M.observe_main clone ~retained:held_a=Error M.Identity_mismatch);
 ignore(ok"ABA actual mapping identifies retained B"(M.observe_main clone ~retained:held_b));
 let child=Unix.fork()in if child=0 then(
  if M.observe_main clone ~retained:held_b<>Error M.Ownership_mismatch||M.close clone<>Error M.Ownership_mismatch then Unix._exit 3;
  Unix.rename a saved;Unix.rename b a;Unix.rename a b;Unix.rename saved a;Unix._exit 0);
 let _,status=Unix.waitpid[]child in check"external ABA child reaped"(status=Unix.WEXITED 0);
 check"external ABA rejects A"(M.observe_main clone ~retained:held_a=Error M.Identity_mismatch);
 ignore(ok"parent remains usable after inherited alias refusal"(M.observe_main clone ~retained:held_b));
 ignore(ok"opaque close clone"(M.close clone));
 let no_mmap=ok"opaque no-mmap open"(M.open_readonly ~mmap:false a)in check"missing mmap HOLD"(error(M.observe_main no_mmap ~retained:held_a));ignore(ok"no mmap close"(M.close no_mmap));
 let raw_refuses db=
  let st=Sqlite3.prepare db"SELECT uos_main_mapping_identity_v1(?1,?2)"in
  Fun.protect ~finally:(fun()->ignore(Sqlite3.finalize st);Core.Gc.keep_alive st)(fun()->
   ignore(Sqlite3.bind_values st[Sqlite3.Data.INT(Int64.of_int(Unix.fstat held_a).st_dev);Sqlite3.Data.INT(Int64.of_int(Unix.fstat held_a).st_ino)]);
   Sqlite3.step st=Sqlite3.Rc.ERROR)in
 let no_mutex=open_ro ~mutex:`NO a in initialize no_mutex ~mmap:true;check"raw SQL no mutex HOLD"(raw_refuses no_mutex);exec no_mutex"ROLLBACK";close no_mutex;
 let unsupported=open_ro ~vfs:"unix-none" a in initialize unsupported ~mmap:true;
 check"raw SQL unsupported VFS HOLD"(raw_refuses unsupported);exec unsupported"ROLLBACK";close unsupported;
 let no_tx=open_ro a in check"raw SQL no read transaction HOLD"(raw_refuses no_tx);close no_tx;
 let rw=Sqlite3.db_open ~mutex:`FULL a in check"raw SQL read-write connection HOLD"(raw_refuses rw);close rw;
 let concurrent=ok"concurrent opaque open"(M.open_readonly a)in
 let domains=List.init 2(fun _->Domain.spawn(fun()->for _=1 to 10 do
  ignore(ok"serialized observation"(M.observe_main concurrent ~retained:held_a));Gc.full_major()done))in
 List.iter Domain.join domains;ignore(ok"serialized close"(M.close concurrent));
 run_lifetime dir a;
 let wal_writer=Sqlite3.db_open ~mutex:`FULL ~cache:`PRIVATE a in
 check"actual WAL mode result"(scalar wal_writer"PRAGMA journal_mode=WAL"="wal");
 exec wal_writer"INSERT INTO probe VALUES(18)";
 check"actual nonempty WAL exists"((Unix.stat(a^"-wal")).st_size>0);
 let wal_reader=ok"opaque WAL readonly open"(M.open_readonly a)in
 ignore(ok"main mapping observation while WAL active (not WAL binding)"(M.observe_main wal_reader ~retained:held_a));
 ignore(ok"close WAL reader"(M.close wal_reader));close wal_writer;
 Printf.printf"WAL_MODE_OBSERVED=wal MAIN_MAPPING_ONLY WAL_SHM_IDENTITY=UNPROVEN\n%!";
 Unix.close held_a;Unix.close held_b;List.iter(fun p->if Sys.file_exists p then Unix.unlink p)[a;b;a^"-wal";a^"-shm"];Unix.rmdir dir;
 Printf.printf"PASS %d SQLite main-mapping checks; no FD/WAL/SHM/authority claim\n%!"!checks
