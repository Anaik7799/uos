#use "topfind";;
#require "core,sqlite3,yojson,bos.setup";;
#directory "/home/an/NAS-setup/uos/engines/hermes/_build/default/modules/sa_plan/.sa_plan.objs/byte";;
#directory "/home/an/NAS-setup/uos/engines/hermes/_build/default/modules/sa_plan";;
#load "sa_plan.cma";;

(* Bounded administration through the existing Sa_plan.Store API.
   No SQL writes, worker dispatch, source ingestion or implementation admission. *)
module S = Sa_plan.Store
open Yojson.Basic.Util
let fail = failwith
let must b m = if not b then fail m
let ok = function Ok x -> x | Error e -> fail e
let bos = function Ok x -> x | Error (`Msg e) -> fail e
let str k j = member k j |> to_string
let arr k j = member k j |> to_list
let strs k j = arr k j |> List.map to_string
let a x = `Assoc x
let s x = `String x
let i x = `Int x
let ss xs = `List(List.map s xs)
let obj_set key value = function `Assoc xs -> `Assoc((key,value)::List.remove_assoc key xs) | _ -> fail "object expected"
let compact = Yojson.Basic.to_string
let canonical xs = List.sort_uniq String.compare xs
let now () = Core.Time_ns.now () |> Core.Time_ns.to_int_ns_since_epoch |> Int64.of_int
let run args =
  let text,(_,status)=bos(Bos.OS.Cmd.run_out(Bos.Cmd.of_list args)|>Bos.OS.Cmd.out_string) in
  must(status=`Exited 0)("command failed: "^List.hd args);String.trim text
let sha p = String.sub(run["sha256sum";p])0 64
let write p j = bos(Bos.OS.File.write(Fpath.v p)(Yojson.Basic.pretty_to_string j^"\n"))
let task_name manifest t = str "plan_id" manifest ^ "/task/" ^ String.lowercase_ascii(str "id" t)
let priority t = match str "priority" t with "P0"->100 | "P1"->80 | "P2"->50 | "P3"->20 | _->fail "unsupported priority"
let topo tasks =
  let ids=List.map(str "id")tasks in
  must(List.length ids=List.length(canonical ids))"duplicate task ID";
  List.iter(fun t->List.iter(fun d->must(List.mem d ids)("unknown dependency: "^d))(strs "depends_on" t))tasks;
  let rec loop done_ids out pending =
    if pending=[]then List.rev out else
    let ready,rest=List.partition(fun t->List.for_all(fun d->List.mem d done_ids)(strs "depends_on" t))pending in
    must(ready<>[])"cycle in execution DAG";
    loop(List.map(str "id")ready@done_ids)(List.rev_append ready out)rest
  in loop [] [] tasks
let validate m =
  must(str "schema" m="uos.sa-plan-execution.v1")"unsupported manifest schema";
  must(member "per_command_timeout_seconds" m=`Int 1200)"command ceiling must be 1200 seconds";
  must(member "dispatch_enabled" m=`Bool false)"registration cannot enable dispatch";
  let tasks=arr "tasks" m in
  let order=topo tasks and ids=List.map(str "id")tasks in
  must(List.mem "PLAN00" ids && List.mem "R03" ids)"planning/final task missing";
  let rec ancestors seen id = if List.mem id seen then seen else List.fold_left ancestors (id::seen) (strs "depends_on" (List.find(fun t->str "id" t=id)tasks)) in
  must(canonical(ancestors [] "R03")=canonical ids)"some tasks do not reach R03";
  let requirements=List.map(str "id")(arr "requirements" m) in
  let covered=List.concat_map(strs "requirements")tasks |> canonical in
  must(canonical requirements=covered)"requirement coverage mismatch";
  let workflows=arr "workflows" m and jobs=arr "jobs" m in
  let wids=List.map(str "id")workflows in
  must(List.length wids=List.length(canonical wids))"duplicate workflow ID";
  must(canonical(List.map(str "task_id")jobs)=canonical ids && List.length jobs=List.length tasks)"one job per task required";
  let jids=List.map(str "id")jobs in must(List.length jids=List.length(canonical jids))"duplicate job ID";
  List.iter(fun j->
    let t=List.find(fun t->str "id" t=str "task_id" j)tasks in
    must(canonical(strs "depends_on" j)=canonical(strs "depends_on" t))"job/task dependency drift";
    must(List.mem(str "workflow_id" j)wids)"unknown workflow";
    ignore(ok(Sa_plan.Name.parse(str "name" j))))jobs;
  List.iter(fun w->ignore(ok(Sa_plan.Name.parse(str "name" w)));List.iter(fun id->must(List.mem id ids)"unknown workflow task")(strs "tasks" w))workflows;
  List.iter(fun f->List.iter(fun id->must(List.mem id ids)"unmapped review finding")(strs "tasks" f))(arr "finding_map" m);
  must(List.length(arr "finding_map" m)=9)"expected nine review mappings";
  List.iter(fun input->must(sha(str "path" input)=str "sha256" input)("source digest drift: "^str "path" input))(arr "source_inputs" m);
  let legacy=member "legacy_plan" m in
  must(List.length(arr "tasks" legacy)=75)"legacy task mapping incomplete";
  List.iter(fun t->must(str "registration_action" t="LINK_EXISTING_DO_NOT_DUPLICATE")"legacy tasks must not be copied";List.iter(fun id->must(List.mem id ids)"legacy owner missing")(strs "master_tasks" t))(arr "tasks" legacy);
  order

let args_for m digest job = compact(a[
  "schema",s "uos.task-job.v1";"plan_id",member "plan_id" m;"task_id",member "task_id" job;
  "workflow_id",member "workflow_id" job;"manifest_sha256",s digest;
  "depends_on",member "depends_on" job;"external_dependencies",member "external_dependencies" job;
  "operation",s(if str "task_id" job="PLAN00" then "register-and-verify-plan" else "execute-task");
  "required_task_lease",`Bool true;"dispatch_enabled",`Bool false;"timeout_seconds",`Int 1200])
let workflow_input m digest w = compact(a[
  "plan_id",member "plan_id" m;"manifest_sha256",s digest;"tasks",member "tasks" w;
  "execution_started",`Bool false;"mode",s "registered-awaiting-task-evidence";
  "activities",member "task_execution_protocol" m])
let job_state = function
  | S.Job_available->"available" | S.Job_executing->"executing" | S.Job_retry->"retry"
  | S.Job_completed->"completed" | S.Job_discarded->"discarded" | S.Job_cancelled->"cancelled"
let verify_records store m digest =
  let pid=str "plan_id" m in
  let observed=ok(S.list_task_observations store ~plan_id:pid) in
  let expected=arr "tasks" m in
  must(List.length observed=List.length expected)"stored task count drift";
  List.iter(fun t->
    let row=List.find(fun (o:S.task_observation)->o.task.id=str "id" t)observed in
    must(row.task.name=task_name m t && row.task.title=str "title" t && row.task.priority=priority t && row.task.parent_id=None)"stored task metadata drift";
    must(canonical row.dependencies=canonical(strs "depends_on" t))"stored dependency drift")expected;
  let jobs=ok(S.list_jobs store ~queue:None) in
  let selected=List.filter(fun (j:S.job_view)->String.starts_with ~prefix:(pid^"/job/")j.id)jobs in
  must(List.length selected=List.length(arr "jobs" m))"stored job count drift";
  List.iter(fun j->
    let actual=List.find(fun (r:S.job_view)->r.id=str "id" j)selected in
    must(actual.name=str "name" j && actual.queue=str "queue" j && actual.worker=str "worker" j && actual.max_attempts=(member "max_attempts" j|>to_int) && actual.args=args_for m digest j)"stored job payload drift") (arr "jobs" m);
  let workflows=ok(S.list_workflows store) in
  let selected_w=List.filter(fun (w:S.workflow_view)->String.starts_with ~prefix:(pid^"/workflow")w.id)workflows in
  must(List.length selected_w=List.length(arr "workflows" m))"stored workflow count drift";
  List.iter(fun w->let actual=List.find(fun (r:S.workflow_view)->r.id=str "id" w)selected_w in
    must(actual.name=str "name" w && actual.kind=str "kind" w && actual.input=workflow_input m digest w)"stored workflow input drift")(arr "workflows" m);
  observed,selected,selected_w
let register store m digest =
  let order=validate m in
  ok(S.with_transaction store(fun()->
    let pid=str "plan_id" m and tick=now() in
    (match ok(S.find_plan store ~id_or_name:pid)with
    |None->ok(S.create_plan store ~id:pid ~name:(str "name" m) ~title:(str "title" m) ~now_ns:tick)
    |Some p->must(p.name=str "name" m && p.title=str "title" m)"stored plan drift");
    List.iter(fun t->let id=str "id" t in match ok(S.find_task store ~plan_id:pid ~id_or_name:id)with
      |Some _->()
      |None->ok(S.create_task store ~plan_id:pid ~id ~name:(task_name m t) ~title:(str "title" t) ~parent_id:None ~dependencies:(strs "depends_on" t) ~priority:(priority t) ~now_ns:tick))order;
    let existing_w=ok(S.list_workflows store) in
    List.iter(fun w->if not(List.exists(fun(r:S.workflow_view)->r.id=str "id" w)existing_w)then
      ok(S.start_workflow_with_input store ~id:(str "id" w) ~name:(str "name" w) ~kind:(str "kind" w) ~input:(workflow_input m digest w) ~now_ns:tick))(arr "workflows" m);
    let existing_j=ok(S.list_jobs store ~queue:None) in
    List.iter(fun j->if not(List.exists(fun(r:S.job_view)->r.id=str "id" j)existing_j)then
      ignore(ok(S.enqueue_job store ~id:(str "id" j) ~name:(str "name" j) ~queue:(str "queue" j) ~worker:(str "worker" j) ~args:(args_for m digest j) ~max_attempts:(member "max_attempts" j|>to_int) ~now_ns:tick)))(arr "jobs" m);
    ignore(verify_records store m digest);Ok()))
let observe store m digest =
  let tasks,jobs,workflows=verify_records store m digest in
  let summary=ok(S.summary store ~plan_id:(str "plan_id" m)) in
  let implementation=List.filter(fun(t:S.task_observation)->t.task.id<>"PLAN00")tasks in
  a["schema",s "uos.sa-plan-execution-observation.v1";"plan_id",member "plan_id" m;
    "tasks",i summary.total;"completed",i summary.completed;"ready",i summary.ready;"executing",i summary.executing;
    "jobs",i(List.length jobs);"workflows",i(List.length workflows);
    "implementation_tasks",i(List.length implementation);
    "implementation_completed",i(List.length(List.filter(fun(t:S.task_observation)->t.task.state="completed")implementation));
    "implementation_attempts",i(List.fold_left(fun acc(t:S.task_observation)->acc+t.task.attempt)0 implementation);
    "task_records",`List(List.map(fun(t:S.task_observation)->a["id",s t.task.id;"state",s t.task.state;"attempt",i t.task.attempt;"dependencies",ss t.dependencies;"priority",i t.task.priority])tasks);
    "job_records",`List(List.map(fun(j:S.job_view)->a["id",s j.id;"state",s(job_state j.state);"attempt",i j.attempt;"queue",s j.queue;"result",(match j.result with None->`Null|Some x->s x)])jobs);
    "workflow_records",`List(List.map(fun(w:S.workflow_view)->a["id",s w.id;"state",s w.state;"event_count",i(List.length w.events)])workflows)]
let complete_planning store m digest =
  ok(S.with_transaction store(fun()->
    let tasks,jobs,_=verify_records store m digest in
    must(List.for_all(fun(t:S.task_observation)->t.task.id="PLAN00" || t.task.state="available" && t.task.attempt=0)tasks)"implementation already started: planning completion needs review";
    let pid=str "plan_id" m and worker="codex.plan-registration" in
    let meta=List.find(fun(t:S.task_observation)->t.task.id="PLAN00")tasks in
    if meta.task.state<>"completed" then begin
      let result=compact(a["scope",s "planning-and-registration-only";"manifest_sha256",s digest;"registration_readback_verified",`Bool true;"implementation_cases_executed",i 0]) in
      ignore(ok(S.claim_task store ~plan_id:pid ~task_id:"PLAN00" ~worker ~now_ns:(now()) ~lease_ns:1320000000000L));
      let job=List.find(fun(j:S.job_view)->j.id=pid^"/job/PLAN00")jobs in
      let claimed=ok(S.claim_job store ~queue:job.queue ~worker ~now_ns:(now()) ~lease_ns:1320000000000L) in
      must(Option.map(fun(j:S.job_view)->j.id)claimed=Some job.id)"unexpected planning job claim";
      ignore(ok(S.complete_job store ~id_or_name:job.id ~worker ~outcome:(`Ok result) ~now_ns:(now())));
      ignore(ok(S.complete_workflow_activity store ~workflow_id_or_name:(pid^"/workflow") ~id:"PLAN00-registration" ~name:(pid^"/activity/plan00-registration") ~idempotency_key:(digest^":PLAN00:registration") ~result ~now_ns:(now())));
      ok(S.complete_task store ~plan_id:pid ~task_id:"PLAN00" ~worker ~result ~now_ns:(now()))
    end;
    Ok()))
let selftest m digest =
  let path=Filename.temp_file "uos-sa-plan-execution-selftest-" ".sqlite3" in
  let store=ok(S.open_db path)in
  let checked=ref[] in
  let pass x=checked:=x::!checked in
  let reject name f = let rejected=try f();false with _->true in must rejected(name^" was accepted");pass name in
  Fun.protect ~finally:(fun()->S.close store) (fun()->
    register store m digest;let before=observe store m digest in
    must(member "tasks" before=`Int 71 && member "ready" before=`Int 1 && member "implementation_completed" before=`Int 0)"unexpected initial state";pass "registration-and-readback";
    register store m digest;must(observe store m digest=before)"replay changed state";pass "idempotent-replay";
    let tasks=arr "tasks" m in
    let replace id key value = obj_set "tasks" (`List(List.map(fun t->if str "id" t=id then obj_set key value t else t)tasks))m in
    reject "unknown-dependency"(fun()->ignore(validate(replace "E01" "depends_on" (ss["absent"]))));
    reject "cycle"(fun()->ignore(validate(replace "PLAN00" "depends_on" (ss["R03"]))));
    reject "task-metadata-drift"(fun()->register store (replace "E01" "title" (s "different payload")) digest);
    must(observe store m digest=before)"failed update changed records";pass "failed-update-preserves-state";
    let rollback=S.with_transaction store(fun()->ok(S.create_plan store ~id:"uos/rollback-control" ~name:"uos/rollback-control" ~title:"rollback" ~now_ns:(now()));Error "deliberate rollback")in
    must(Result.is_error rollback && ok(S.find_plan store ~id_or_name:"uos/rollback-control")=None)"transaction did not roll back";pass "atomic-rollback";
    must(Result.is_error(S.claim_task store ~plan_id:(str "plan_id" m) ~task_id:"E03" ~worker:"probe" ~now_ns:(now()) ~lease_ns:1000000000L))"unsatisfied task claim succeeded";pass "dependency-claim-rejection";
    complete_planning store m digest;let done_view=observe store m digest in
    must(member "completed" done_view=`Int 1 && member "ready" done_view=`Int 1 && member "implementation_attempts" done_view=`Int 0)"planning completion leaked execution";pass "planning-only-completion";
    register store m digest;complete_planning store m digest;must(observe store m digest=done_view)"completion replay changed state";pass "completion-replay";
    a["status",s "PASSED";"checks",ss(List.rev !checked);"count",i(List.length !checked);"scratch_store",s path;"scope",s "registration-and-planning-only"])
let with_store db f =
  let store=ok(S.open_db db)in Fun.protect ~finally:(fun()->S.close store)(fun()->f store)
let () = try
  must(Array.length Sys.argv>=3)"usage: ocaml tools/sa_plan_execution.ml validate|selftest|register|status|complete-planning MANIFEST [DB] [RECEIPT]";
  let op=Sys.argv.(1) and path=Sys.argv.(2)in
  let m=Yojson.Basic.from_file path in ignore(validate m);let digest=sha path in
  let value=match op with
  |"validate"->a["status",s "VALIDATED";"tasks",i(List.length(arr "tasks" m));"jobs",i(List.length(arr "jobs" m));"workflows",i(List.length(arr "workflows" m));"requirements",i(List.length(arr "requirements" m));"legacy_links",i 75;"implementation_cases_executed",i 0]
  |"selftest"->selftest m digest
  |"register"|"status"|"complete-planning"->
    must(Array.length Sys.argv>=4)"database argument required";
    let db=Sys.argv.(3)in must(db=str "database" m)"database must match the canonical manifest";
    if op="status"then must(Sys.file_exists db)"store unavailable; status cannot create a new database"
    else begin ignore(Unix.umask 0o077);ignore(bos(Bos.OS.Dir.create ~path:true(Fpath.v(Filename.dirname db))))end;
    let proof=if op="complete-planning"then selftest m digest else `Null in
    with_store db(fun store->
      if op="register"then register store m digest;
      if op="complete-planning"then complete_planning store m digest;
      let view=observe store m digest in
      a["schema",s "uos.sa-plan-registration-receipt.v1";"status",s(if op="complete-planning"then "PLAN_REGISTERED_VERIFIED_IMPLEMENTATION_UNRUN" else "SA_PLAN_OBSERVED");
        "clock_utc",s(run["date";"-u";"+%Y-%m-%dT%H:%M:%SZ"]);"database",s db;"manifest",s path;"manifest_sha256",s digest;
        "adapter_sha256",s(sha Sys.argv.(0));"runtime_library",s "/home/an/NAS-setup/uos/engines/hermes/_build/default/modules/sa_plan/sa_plan.cma";
        "runtime_library_sha256",s(sha "/home/an/NAS-setup/uos/engines/hermes/_build/default/modules/sa_plan/sa_plan.cma");
        "jj_candidate",s(run["jj";"log";"-r";"@";"--no-graph";"-T";"change_id ++ \" \" ++ commit_id"]);
        "selftest",proof;"observed",view;"legacy_plan",member "legacy_plan" m;
        "dispatch_enabled",`Bool false;"temporal_service_connected",`Bool false;"system_admission_granted",`Bool false])
  |_ ->fail("unknown operation: "^op) in
  if Array.length Sys.argv>4 then write Sys.argv.(4)value;
  (match member "observed" value with
  |`Null->print_endline(compact value)
  |o->print_endline(compact(a["status",member "status" value;"tasks",member "tasks" o;"jobs",member "jobs" o;"workflows",member "workflows" o;"completed",member "completed" o;"ready",member "ready" o;"implementation_completed",member "implementation_completed" o;"implementation_attempts",member "implementation_attempts" o])))
with exn->prerr_endline("sa-plan execution: "^Printexc.to_string exn);exit 1
