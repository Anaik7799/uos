(* ONE ordinary synthetic existing-Store flow. No production adapter, signature,
   reviewer approval, route grant or canonical task/database is constructed. *)
module S=Sa_plan.Store
let ok=function Ok x->x|Error e->failwith e
let s x=`String x
let sha x=Digestif.SHA256.(to_hex(digest_string x))
let check_count=ref 0
let check label b=if not b then failwith label else(incr check_count;Printf.printf"PASS %s\n%!"label)
let write p body=let fd=Unix.openfile p[Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in
 let c=Unix.out_channel_of_descr fd in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c body;flush c;Unix.fsync fd)
let writej dir name j=
 let path=dir^"/"^name and bytes=Yojson.Basic.to_string j in
 write path bytes;
 if Bounded.read path<>bytes then failwith"persisted canonical bytes changed"
let now_ns()=Core.Time_ns.now()|>Core.Time_ns.to_int_ns_since_epoch|>Int64.of_int
let stamp seconds=let t=Unix.gmtime seconds in Printf.sprintf"%04d-%02d-%02dT%02d:%02d:%02dZ"(t.Unix.tm_year+1900)(t.Unix.tm_mon+1)t.Unix.tm_mday t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec
let set j k v=match j with `Assoc xs->`Assoc(List.map(fun(a,b)->a,if a=k then v else b)xs)|_->failwith"record"
let text j k=Yojson.Basic.Util.(member k j|>to_string)
let members=["OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT","codex-symbiosis-preflight-20261031";
 "OI02E_RELEASE_AUTHORITY_PREPARATION","codex-release-authority-20261031";
 "OI02_ATOMIC_11_TARGET_CAPSULE_CUTOVER","codex-hive-cutover-20261031"]
let plan="uos/codex-handover-open-items-fractal-plan/20261031-1240"
let ()=
 if Array.length Sys.argv<>3 then failwith"private source-root output-directory only";
 let root=Unix.realpath Sys.argv.(1)and out=Unix.realpath Sys.argv.(2)in
 if Filename.basename root<>"codex-recovery-snapshot-integration-20261101"||not(String.starts_with~prefix:(root^"/var/harness/")out)then failwith"isolated fixture only";
 Unix.chdir root;
 let database=out^"/synthetic.sqlite3"in
 let setup=ok(S.open_db database)in Unix.chmod database 0o600;
 let initial=now_ns()in
 ok(S.create_plan setup~id:plan~name:"private/snapshot-checker"~title:"Synthetic four-task snapshot fixture"~now_ns:initial);
 List.iteri(fun i(id,worker)->
  ok(S.create_task setup~plan_id:plan~id~name:("private/"^id)~title:id~parent_id:None~dependencies:[]~priority:i~now_ns:initial);
  (* Historical timestamps are PRIVATE fixture setup data, not live authority.
     Different real stored attempts prevent proposal generation assuming1. *)
  for n=0 to i do
   ignore(ok(S.claim_task setup~plan_id:plan~task_id:id~worker
    ~now_ns:(Int64.sub initial(Int64.of_int((20-n*2-i)*1000000000)))~lease_ns:1000000000L))
  done)members;
 ok(S.create_task setup~plan_id:plan~id:"CONTROL_SENTINEL"~name:"private/sentinel"~title:"Full-plan conservation sentinel"~parent_id:None~dependencies:[]~priority:9~now_ns:initial);
 S.close setup;
 let clock=Host_clock.observe()in
 let observed=ok(S.recovery_snapshot_readonly~path:database~plan_id:plan)in
 let observed_utc_ns=now_ns()and observed_mono_ns=Mtime_clock.now_ns()in
 check "query_only actually observed"observed.query_only_observed;
 check "one deferred read transaction"(observed.transaction_mode="DEFERRED_READ_ONLY");
 check "exact SQLite version observed"(observed.sqlite_version=Sqlite3.sqlite_version_info());
 let live=Live_plan.of_snapshot observed.snapshot in
 check "canonical snapshot JSON roundtrip"(`List(List.map Live_plan.to_json live)=observed.snapshot);
 check "snapshot bytes independently rehashed"(sha(Yojson.Basic.to_string observed.snapshot)=observed.snapshot_sha256);
 check "checker digest exact Store digest"(Live_plan.digest live=observed.snapshot_sha256);
 check "whole four-row plan retained"(List.length live=4);
 let expired=List.filter(fun(t:Live_plan.task)->t.state="executing"&&match t.lease with None->failwith"missing executing lease"|Some n->n<=observed_utc_ns)live in
 check "complete expired set exactly intended three"(List.sort compare(List.map(fun(t:Live_plan.task)->t.id,Option.get t.worker)expired)=List.sort compare members);
 let bindings=List.map(fun(t:Live_plan.task)->
  let worker=match t.worker with Some w when w<>""->w|_->failwith"missing old worker"in
  let lease=match t.lease with Some n when n>0L->n|_->failwith"missing old lease"in
  if t.attempt<1||t.completed<>None||t.result_present then failwith"inconsistent expired task";
  t.id,worker,t.attempt,lease)expired in
 check "proposal derives nonuniform actual attempts"(List.sort compare(List.map(fun(_,_,n,_)->n)bindings)=[1;2;3]);
 let observed_at=stamp(Unix.gettimeofday()-.1.)and until=stamp(Unix.gettimeofday()+.120.)in
 let paths=["AGENTS.md";"engines/hermes/modules/sa_plan/sa_plan_store.ml";"engines/hermes/modules/sa_plan/sa_plan_store.mli";
  "engines/hermes/modules/sa_plan/development/checker/live_plan.ml";"engines/hermes/modules/sa_plan/development/checker/checker.ml";
  "engines/hermes/modules/sa_plan/test/test_recovery_snapshot_checker_integration.ml"]in
 let evs=`List(List.map(fun p->`Assoc["path",s p;"sha256",s(Bounded.sha256(Bounded.evidence~root p));"observed_at",s observed_at])paths)in
 let sample=Record.sample()in
 let rows=List.map(fun(t:Live_plan.task)->let index=if t.id="CONTROL_SENTINEL"then 3 else (List.find_index(fun(id,_)->id=t.id)members|>Option.get) in
  sample|>fun j->set j"assessment_id"(s("private-snapshot-"^string_of_int index))|>fun j->set j"plan_id"(s plan)
  |>fun j->set j"task_id"(s t.id)|>fun j->set j"actor"(s(Option.value t.worker~default:"private-assessor"))
  |>fun j->set j"scope"(s"PRIVATE observed fixture assessment DATA, not independent review")
  |>fun j->set j"task_state"(s t.state)|>fun j->set j"dependencies"(`List(List.map s t.dependencies))
  |>fun j->set j"class"(s("P"^string_of_int index))|>fun j->set j"observed_at"(s observed_at)
  |>fun j->set j"valid_until"(s until)|>fun j->set j"ready_since"(s observed_at)
  |>fun j->set j"snapshot"(`Assoc["kind",s"working_tree";"reference",s"Actual private v7 snapshot, candidate source only, no canonical authority";"evidence",evs]))live in
 let portfolio_bytes=Yojson.Basic.to_string(`List rows)in write(out^"/portfolio.json")portfolio_bytes;
 let records=List.map(Record.check_record(Record.schema()))rows in
 let projected=Checker.reclaim_set_projection~now_ns:observed_utc_ns bindings records live in
 let now=stamp(Unix.gettimeofday())in
 let audit=Checker.audit~root~now projected in
 let findings=audit.Checker.findings@Checker.coherence~reclaim_set:bindings~now_ns:observed_utc_ns records live@Checker.final_time_findings~now records in
 if findings<>[]then failwith(Yojson.Basic.to_string(Checker.findings_json findings));
 Checker.verify_again~root audit.evidence;
 check "actual full checker source time coherence findings empty"(findings=[]);
 let report=`Assoc["domain",s"uos.private-snapshot-checker-report.v1";"scope",s"AUTHOR_TEST_OBSERVATION_NOT_REVIEW_APPROVAL";
  "snapshot_sha256",s observed.snapshot_sha256;"portfolio_sha256",s(sha portfolio_bytes);"ranked",Checker.order_json audit.ranked;
  "clock",Host_clock.to_json clock;"observed_utc_ns",s(Int64.to_string observed_utc_ns);"observed_mono_ns",s(Int64.to_string observed_mono_ns);
  "findings",Checker.findings_json findings;"evidence",`List(List.map(fun(p,h)->`Assoc["path",s p;"sha256",s h])audit.evidence)]in
 let report_bytes=Yojson.Basic.to_string report in
 let request=S.{reclaim_request_id="private-snapshot-checker-request";reclaim_plan_id=plan;expected_snapshot_sha256=observed.snapshot_sha256;
  expired_tasks=List.map(fun(id,worker,attempt,lease)->S.{reclaim_task_id=id;old_worker=worker;old_attempt=attempt;old_lease_until_ns=lease})bindings;
  reclaim_lease_ns=30000000000L;request_deadline_ns=Int64.add observed_utc_ns 120000000000L}in
 let request_json=`Assoc["domain",s"uos.sa-plan.reclaim-three.v1";"request_id",s request.reclaim_request_id;"plan",s plan;"snapshot",s request.expected_snapshot_sha256;
  "old",`List(List.map(fun t->`Assoc["task",s t.S.reclaim_task_id;"worker",s t.S.old_worker;"attempt",`Int t.S.old_attempt;"lease",s(Int64.to_string t.S.old_lease_until_ns)])request.expired_tasks);
  "duration",s(Int64.to_string request.reclaim_lease_ns);"deadline",s(Int64.to_string request.request_deadline_ns)]in
 let proposal=`Assoc["domain",s"uos.recovery.snapshot-checker-factual-proposal.v1";"authority",s"NONE";"application_admitted",`Bool false;
  "snapshot",observed.snapshot;"snapshot_sha256",s observed.snapshot_sha256;"portfolio",`List rows;"portfolio_sha256",s(sha portfolio_bytes);
  "checker",report;"checker_sha256",s(sha report_bytes);"request",request_json;"request_sha256",s(sha(Yojson.Basic.to_string request_json));
  "review",`Assoc["status",s"UNAVAILABLE"];"selection",`Assoc["status",s"UNAVAILABLE";"diagnostic_ranking",Checker.order_json audit.ranked];
  "mcp_route",`Assoc["status",s"HELD";"reasons",`List(List.map s["RECLAIM_PREFLIGHT_PASS_NOT_ACCEPTED_BY_EXISTING_CLAIM_GATE";"EXPIRED_CONTROLLING_FENCE_REFUSED";"SINGLE_CLAIM_NOT_FULL_SET_REVIEWED_RECEIPT"])]]in
 writej out"snapshot-before.json"observed.snapshot;writej out"checker.json"report;writej out"factual-proposal.json"proposal;
 check "persisted canonical report and proposal hashes exact"(sha(Bounded.read(out^"/checker.json"))=sha report_bytes&&sha(Bounded.read(out^"/factual-proposal.json"))=sha(Yojson.Basic.to_string proposal));
 check "proposal exact actual snapshot and report binding"(Yojson.Basic.Util.member"snapshot"proposal=observed.snapshot&&text proposal"checker_sha256"=sha report_bytes);
 check "proposal no review or selection permission"(text(Yojson.Basic.Util.member"review"proposal)"status"="UNAVAILABLE"&&text(Yojson.Basic.Util.member"mcp_route"proposal)"status"="HELD");
 (* Compatibility only: this direct private Store call is NOT authorized by
    the proposal and is NOT evidence of MCP/preflight/fence recovery safety. *)
 let selected=List.hd expired in
 let actual_before=ok(S.recovery_snapshot_readonly~path:database~plan_id:plan)in
 check "fresh preclaim snapshot still matches proposal"(actual_before.snapshot_sha256=observed.snapshot_sha256);
 let store=ok(S.open_existing database)in
 let claim=Fun.protect~finally:(fun()->S.close store)(fun()->ok(S.claim_task store~plan_id:plan~task_id:selected.id~worker:(Option.get selected.worker)~now_ns:(now_ns())~lease_ns:30000000000L))in
 let after=ok(S.recovery_snapshot_readonly~path:database~plan_id:plan)in
 let after_tasks=Live_plan.of_snapshot after.snapshot in
 let changed=List.filter(fun(t:Live_plan.task)->let old=List.find(fun(o:Live_plan.task)->o.id=t.id)live in Live_plan.to_json old<>Live_plan.to_json t)after_tasks in
 check "existing private claim changes exactly selected row"(List.length changed=1&&(List.hd changed).id=selected.id);
 check "existing Store increments actual observed attempt"(claim.attempt=selected.attempt+1&&(List.hd changed).attempt=claim.attempt);
 check "fresh postclaim digest actually changed"(after.snapshot_sha256<>observed.snapshot_sha256);
 writej out"snapshot-after.json"after.snapshot;
 Printf.printf"ONE_ORDINARY_SNAPSHOT_CHECKER_FLOW_PASS checks=%d snapshot=%s proposal=%s authority=NONE production_route=HELD\n%!"!check_count observed.snapshot_sha256(sha(Yojson.Basic.to_string proposal))
