(* Two ordinary versioned upgrade/history flows in isolated private databases.
   No failure injection, adversarial/concurrent tests, real keys or live DB. *)
module V1=Recovery_schema_migration
module V2=Recovery_schema_migration_v2
module F=Recovery_migration_v1_helpers
module G=Recovery_migration_v2_fixture
module S=Recovery_kernel_fixture
let ok=function Ok x->x|Error _->failwith"ordinary fixture refused"
let checks=ref 0
let check label b=if not b then failwith label else(incr checks;Printf.printf"PASS %s\n%!"label)
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let source_schema path=
 let raw=read path in
 if F.sha raw<>"77aa249145c0b630588c7ec874cddbace7f6916d1888389c3c1a491c2e2a18cd"then failwith"reviewed adapter source changed";
 (* A deliberately closed literal-only projection, NOT an OCaml evaluator.
    Actual reviewed adapter's three schema rows are each one literal line. *)
 let active=ref false in
 let rows=String.split_on_char '\n'raw|>List.filter_map(fun line->
  if line="let schema=["then(active:=true;None)
  else if !active then
   let ends=String.ends_with~suffix:"]"(String.trim line)in
   let pair=Scanf.sscanf line" %S,%S"(fun a b->a,b)in
   if ends then active:=false;Some pair
  else None)in
 if !active||List.length rows<>3 then failwith"unsupported literal schema projection";
 rows
let raw path f=
 let db=Sqlite3.db_open~mode:`NO_CREATE~uri:false path in
 Fun.protect~finally:(fun()->let closed=Sqlite3.db_close db in Core.Gc.keep_alive db;if not closed then failwith"private read close unknown")(fun()->f db)
let ()=
 if Array.length Sys.argv<>3 then failwith"explicit source root and public adapter evidence required";
 let root=Unix.realpath Sys.argv.(1)in
 let v1ml=read(root^"/engines/hermes/modules/sa_plan/recovery_schema_migration.ml")in
 let v1mli=read(root^"/engines/hermes/modules/sa_plan/recovery_schema_migration.mli")in
 let local_adapter=root^"/engines/hermes/modules/sa_plan/development/recovery_adapter_context.ml"in
 let adapter=if Sys.file_exists local_adapter then local_adapter else Sys.argv.(2)in
 check"actual adapter resource DDL exact parity"(V2.resource_schema=source_schema adapter);
 check"v1 task schema still six objects"(List.length(V1.schema V1.Task_store)=6);
 check"v2 task payload exactly nine objects"(List.length V2.schema=9);
 check"generic migration receipt schema unchanged"(V2.receipt_schema=V1.receipt_schema V1.Task_store);
 List.iter(fun predecessor->
  let path=Filename.temp_file"uos-migration-v2-"".sqlite3"in
  let setup=ok(S.open_db path)in Unix.chmod path 0o600;
  Fun.protect~finally:(fun()->S.close setup;List.iter(fun p->if Sys.file_exists p then Sys.remove p)[path;path^"-wal";path^"-shm"])(fun()->
   ok(S.create_plan setup~id:"p"~name:"private/v2"~title:"Ordinary private v2 migration"~now_ns:1L);
   ok(S.create_task setup~plan_id:"p"~id:"a"~name:"private/a"~title:"Existing row"~parent_id:None~dependencies:[]~priority:0~now_ns:1L);
   S.close setup;
   let st=Unix.lstat path and clock=ok(Recovery_kernel.native_clock())in
   let base=V1.{migration_id="v1-ordinary";resource_id="private-task-store";database=path;device=st.st_dev;inode=st.st_ino;target=Task_store;
    source_sha256=F.sha v1ml;before_schema_sha256=raw path(fun db->F.core_schema_sha db Task_store);
    expires_utc_ns=Int64.add clock.utc_ns 60000000000L;expires_mono_ns=Int64.add clock.mono_ns 60000000000L}in
   (match predecessor with
    |V2.Legacy_six->raw path(fun db->List.iter(fun(_,ddl)->F.exec db ddl)(V1.schema V1.Task_store))
    |V2.V1_with_receipts->check"genuine ordinary v1 migration installed first"(match F.execute base with Ok(`Installed,_)->true|_->false));
   let before_data,before_receipts,before_schema=raw path(fun db->F.data db V1.Task_store,G.old_rows db,F.all_schema db)in
   let before_bytes=V1.request_bytes base in
   let request=V2.{base={base with migration_id="v2-ordinary";source_sha256=F.sha(read(root^"/engines/hermes/modules/sa_plan/recovery_schema_migration_v2.ml"));before_schema_sha256=F.schema_sha before_schema};predecessor}in
   check"v2 production migration unavailable"(V2.migrate request=Error V2.Authority_unavailable);
   check"new request has versioned v2 domain"(Yojson.Basic.Util.member"domain"(Yojson.Basic.from_string(V2.request_bytes request))=`String"uos.recovery-schema-migration-data.v2");
   let receipt=match G.execute request with Ok(`Installed,j)->j|_->failwith"ordinary v2 install refused"in
   check"v2 receipt domain explicitly versioned"(Yojson.Basic.Util.member"domain"receipt=`String"uos.recovery-schema-migration-receipt.v2");
   let after_data,after_receipts,after_schema=raw path(fun db->F.data db V1.Task_store,G.old_rows db,F.all_schema db)in
   let names=List.map fst before_data in
   check"all original typed rows preserved"(before_data=List.filter(fun(n,_)->List.mem n names)after_data);
   check"all original v1 migration receipts preserved"(List.for_all(fun row->List.mem row after_receipts)before_receipts);
   check"exactly one new versioned receipt appended"(List.length after_receipts=List.length before_receipts+1);
   check"complete task extension layout twelve objects"(List.length(List.filter(fun(n,_)->G.owned n)after_schema)=12);
   check"resource receipt table initially empty"(raw path(fun db->F.scalar db"SELECT COUNT(*) FROM control_resource_receipt"=0L));
   check"exact replay gives historical fact only"(match G.execute request with Ok(`Historical,j)->j=receipt|_->false);
   check"read-only reconciliation returns same v2 fact"(G.reconcile request=Ok(Some receipt));
   check"historical replay appends no extra receipt"(raw path(fun db->G.old_rows db=after_receipts));
   check"v1 request serialization remains byte identical"(V1.request_bytes base=before_bytes)))
 [V2.Legacy_six;V2.V1_with_receipts];
 check"v1 module source unchanged"(read(root^"/engines/hermes/modules/sa_plan/recovery_schema_migration.ml")=v1ml);
 check"v1 interface source unchanged"(read(root^"/engines/hermes/modules/sa_plan/recovery_schema_migration.mli")=v1mli);
 Printf.printf"TWO_ORDINARY_V2_MIGRATION_FLOWS_PASS checks=%d authority=NONE production=UNAVAILABLE\n%!"!checks
