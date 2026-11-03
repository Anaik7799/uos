(* PRIVATE initializer/read-only observation bridge. No production linkage.
   Actual v1 then v2 fixed fixture migrations replace private schema preparation.
   Every setup/migration reader closes before retained-VFS/signature work. *)
module V1=Recovery_schema_migration
module V2=Recovery_schema_migration_v2
module F=Recovery_migration_v1_helpers
module G=Recovery_migration_v2_fixture
module S=Sa_plan.Store
module K=Recovery_kernel
let require b why=if not b then failwith why
let ok=function Ok x->x|Error _->failwith"migration initializer unavailable"
let text j k=Yojson.Basic.Util.(member k j|>to_string)
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->let n=in_channel_length c in require(n<=1048576)"private metadata bound";really_input_string c n)
let write p b=let fd=Unix.openfile p[Unix.O_CREAT;Unix.O_EXCL;Unix.O_WRONLY]0o600 in let c=Unix.out_channel_of_descr fd in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c b;flush c;Unix.fsync fd)
let directory dir=
 require(String.starts_with~prefix:"/tmp/uos-control-private-"dir&&Filename.dirname dir="/tmp"&&Unix.realpath dir=dir)"private migration namespace";
 let st=Unix.lstat dir in require(st.st_kind=Unix.S_DIR&&st.st_uid=Unix.geteuid()&&st.st_perm land 0o077=0)"private directory"
let with_read path f=
 let db=Sqlite3.db_open~mode:`READONLY~uri:false~mutex:`FULL path in
 Fun.protect~finally:(fun()->let closed=Sqlite3.db_close db in Core.Gc.keep_alive db;require closed"migration observation close unknown")
  (fun()->F.exec db"PRAGMA query_only=ON;PRAGMA trusted_schema=OFF";f db)
let zero_role_fds database=
 let roles=List.map(fun suffix->let st=Unix.stat(database^suffix)in st.Unix.st_dev,st.st_ino)["";"-wal";"-shm"]in
 let fds=Sys.readdir"/proc/self/fd"in require(Array.length fds<=4096)"FD inventory bound";
 let counts=Array.make 3 0 in
 Array.iter(fun name->
  try let st=Unix.stat("/proc/self/fd/"^name)in
   List.iteri(fun i identity->if identity=(st.Unix.st_dev,st.st_ino)then counts.(i)<-counts.(i)+1)roles
  with Unix.Unix_error((Unix.ENOENT|Unix.EBADF),_,_)->())fds;
 require(Array.for_all((=)0)counts)"setup or migration role descriptor remains open";
 `List(Array.to_list(Array.map(fun n->`Int n)counts))
let snapshot path=
 let store=ok(S.open_existing path)in
 Fun.protect~finally:(fun()->S.close store)(fun()->ok(S.recovery_snapshot_bounded store~plan_id:K.fixed_plan))
let base_from_json j=
 require(text j"domain"="uos.recovery-schema-migration-data.v1"&&text j"target"="task_store_v7_extensions_v1")"expected v1 DATA profile";
 let n k=Int64.of_string(text j k)in
 V1.{migration_id=text j"migration_id";resource_id=text j"resource_id";database=text j"database";
  device=Yojson.Basic.Util.(member"device"j|>to_int);inode=Yojson.Basic.Util.(member"inode"j|>to_int);target=Task_store;
  source_sha256=text j"source_sha256";before_schema_sha256=text j"before_schema_sha256";
  expires_utc_ns=n"expires_utc_ns";expires_mono_ns=n"expires_mono_ns"}
let preserved dir=
 directory dir;
 let j=Yojson.Basic.from_string(read(dir^"/migration-facts.json"))in
 require(text j"domain"="PRIVATE_MIGRATED_ADAPTER_FACTS")"private migration facts";
 let field k=Yojson.Basic.Util.member k j in
 let v1=base_from_json(field"v1_request")in
 let v2json=field"v2_request"in
 let v2=V2.{base=base_from_json(Yojson.Basic.Util.member"base_v1_data"v2json);predecessor=V1_with_receipts}in
 require(v1.database=dir^"/tasks.sqlite3"&&v2.base.database=v1.database)"fixed migration resource";
 with_read v1.database(fun db->
  F.exec db"BEGIN";
  let good=G.extension db=G.expected&&F.lookup db v1=Some(field"v1_receipt")
   &&G.lookup db v2=Some(field"v2_receipt")&&F.scalar db"SELECT COUNT(*) FROM sa_plan_recovery_migration_receipt"=2L in
  F.exec db"COMMIT";require good"migration receipts or schema changed");
 ignore(zero_role_fds v1.database);true
let migrate database=
 let dir=Filename.dirname database in directory dir;
 require(database=dir^"/tasks.sqlite3")"fixed private task database";
 ignore(zero_role_fds database);
 (* The fixture's WAL initializer creates sidecars with the process umask.
    Establish the migrator's private-file prerequisite only after all setup
    handles close; this changes no migration policy or database schema. *)
 List.iter(fun suffix->let path=database^suffix in
  let st=Unix.lstat path in
  require(st.st_kind=Unix.S_REG&&st.st_uid=Unix.geteuid()&&st.st_nlink=1)
   "private setup role required";
  Unix.chmod path 0o600)["";"-wal";"-shm"];
 let before,before_sha=snapshot database in ignore(zero_role_fds database);
 let st=Unix.lstat database and clock=ok(K.native_clock())in
 let r1=V1.{migration_id="adapter-v1-setup";resource_id="private-migrated-task-store";database;
  device=st.st_dev;inode=st.st_ino;target=Task_store;
  source_sha256="f6e8fa16405bd940a98aaba7b45d5cbef9d259fb1e60e3e2a8f960507035e885";
  before_schema_sha256=with_read database(fun db->F.core_schema_sha db Task_store);
  expires_utc_ns=Int64.add clock.utc_ns 60000000000L;expires_mono_ns=Int64.add clock.mono_ns 60000000000L}in
 let receipt1=match F.execute r1 with Ok(`Installed,j)->j|_->failwith"v1 migration not installed"in
 ignore(zero_role_fds database);
 let r2=V2.{base={r1 with migration_id="adapter-v2-upgrade";
  source_sha256="f77fb63aa1843328caa7763182da746290f5bb4c33147169db2f2b8e9b459b64";
  before_schema_sha256=with_read database(fun db->F.schema_sha(F.all_schema db))};predecessor=V1_with_receipts}in
 let receipt2=match G.execute r2 with Ok(`Installed,j)->j|_->failwith"v2 migration not installed"in
 let after,after_sha=snapshot database in
 require(before=after&&before_sha=after_sha)"migration task projection changed";
 let fds=zero_role_fds database in
 let facts=`Assoc["domain",`String"PRIVATE_MIGRATED_ADAPTER_FACTS";
  "v1_request",Yojson.Basic.from_string(V1.request_bytes r1);"v1_receipt",receipt1;
  "v2_request",Yojson.Basic.from_string(V2.request_bytes r2);"v2_receipt",receipt2;
  "before_task_snapshot_sha256",`String before_sha;"after_task_snapshot_sha256",`String after_sha;
  "role_descriptors_after_migration",fds;"authority",`String"NONE"]in
 write(dir^"/migration-facts.json")(Yojson.Basic.to_string facts);
 require(preserved dir)"initial migration evidence";
 Yojson.Basic.to_string(`Assoc["schema",`String"uos.private-migrated-adapter-preparation.v1";
  "status",`String"MIGRATED_V1_THEN_V2_DATA_ONLY";"authority",`String"NONE";
  "before_task_snapshot_sha256",`String before_sha;"after_task_snapshot_sha256",`String after_sha;
  "snapshot_scope",`String"FIXED_PLAN_BOUNDED_PROJECTION";"post_migration_private_schema_preparation_calls",`Int 0;
  "role_descriptors_after_migration",fds;"production_migration",`Bool false])
