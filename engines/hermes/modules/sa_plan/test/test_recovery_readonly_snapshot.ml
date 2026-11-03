(* One ordinary, private read-only projection flow; not canonical recovery. *)
module S=Sa_plan.Store
let ok=function Ok x->x|Error e->failwith e
let check label b=if not b then failwith label else Printf.printf"PASS %s\n%!"label
let read p=let c=open_in_bin p in Fun.protect~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c))
let sha s=Digestif.SHA256.(to_hex(digest_string s))
let ()=
 let path=Filename.temp_file "uos-readonly-observation-" ".sqlite3"in
 let s=ok(S.open_db path)in
 Fun.protect~finally:(fun()->S.close s;List.iter(fun p->if Sys.file_exists p then Sys.remove p)[path;path^"-wal";path^"-shm"])(fun()->
  ok(S.create_plan s~id:"p"~name:"ordinary/observation"~title:"private"~now_ns:1L);
  List.iter(fun id->ok(S.create_task s~plan_id:"p"~id~name:("ordinary/"^id)~title:id~parent_id:None~dependencies:[]~priority:0~now_ns:1L);
   ignore(ok(S.claim_task s~plan_id:"p"~task_id:id~worker:("worker-"^id)~now_ns:10L~lease_ns:10L)))["a";"b";"c"];
  let expected,expected_sha=ok(S.recovery_snapshot_bounded s~plan_id:"p")in
  S.close s;
  let before=sha(read path)in
  let observed=ok(S.recovery_snapshot_readonly~path~plan_id:"p")in
  check "same exact canonical snapshot JSON"(Yojson.Basic.to_string observed.snapshot=Yojson.Basic.to_string expected);
  check "same exact canonical snapshot digest"(observed.snapshot_sha256=expected_sha);
  check "snapshot digest independently recomputed"(sha(Yojson.Basic.to_string observed.snapshot)=observed.snapshot_sha256);
  check "query_only actually observed"observed.query_only_observed;
  check "deferred read transaction"(observed.transaction_mode="DEFERRED_READ_ONLY");
  check "actual SQLite version recorded"(observed.sqlite_version=Sqlite3.sqlite_version_info());
  check "fixture main bytes unchanged"(sha(read path)=before);
  check "complete expired tuples available as facts"(List.length(Yojson.Basic.Util.to_list observed.snapshot)=3);
  let again=ok(S.recovery_snapshot_readonly~path~plan_id:"p")in
  check "fresh reopen exact same digest"(again.snapshot_sha256=expected_sha);
  check "close/reopen leaves main unchanged"(sha(read path)=before);
  print_endline"ONE_ORDINARY_READONLY_SNAPSHOT_FLOW_PASS checks=10 authority=NONE production_route=UNCONFIGURED")
