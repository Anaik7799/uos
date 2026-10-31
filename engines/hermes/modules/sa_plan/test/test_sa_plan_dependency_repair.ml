module U = Unix
open Core
module S = Sa_plan.Store
module M = Sa_plan.Management
let checks = ref 0
let check name value = incr checks; if not value then failwith ("FAILED "^name)
let ok = function Ok x -> x | Error e -> failwith e
let node ?(dependencies=[]) id = M.{id;parent_id=None;task_type=Story;title=id;estimate_points=Some 1;dependencies}
let raw path f =
  let db = Sqlite3.db_open path in
  Exn.protect ~f:(fun () -> f db) ~finally:(fun () -> let _ = Sqlite3.db_close db in Gc.keep_alive db)
let exec path sql = raw path (fun db -> match Sqlite3.exec db sql with Sqlite3.Rc.OK -> () | _ -> failwith (Sqlite3.errmsg db))
let scalar path sql = raw path (fun db -> let stmt=Sqlite3.prepare db sql in
  Exn.protect ~f:(fun () -> match Sqlite3.step stmt with Sqlite3.Rc.ROW -> Sqlite3.column_text stmt 0 | _ -> failwith "missing scalar")
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt : Sqlite3.Rc.t);Gc.keep_alive stmt;Gc.keep_alive db))
let audit_exists path = String.equal (scalar path "SELECT count(*) FROM sqlite_master WHERE name='sa_plan_dependency_repair'") "1"
let fixture f =
  let path = Stdlib.Filename.temp_file "uos-dependency-repair-" ".sqlite3" in
  let store = ok (S.open_db path) in
  Exn.protect ~f:(fun () ->
    ok (S.register_plan store ~id:"plan" ~title:"synthetic private fixture" ~nodes:[node "maint";node "b";node "c";node "d";node ~dependencies:["b"] "a"]);
    let claim=ok (S.claim_task store ~plan_id:"plan" ~task_id:"maint" ~worker:"worker" ~now_ns:100L ~lease_ns:1000L) in
    f path store claim.attempt)
    ~finally:(fun () -> S.close store;List.iter [path;path^"-wal";path^"-shm"] ~f:(fun p -> if Stdlib.Sys.file_exists p then Stdlib.Sys.remove p))
let request attempt : S.dependency_repair = {operation_id="repair-1";plan_id="plan";maintenance_task_id="maint";worker="worker";expected_attempt=attempt;target_task_id="a";prerequisite_task_id="c";expected_dependencies=["b"]}
let run s r now = S.add_dependency_observed s r ~observe_now:(fun () -> now)
let deps s id = let xs=ok (S.list_task_observations s ~plan_id:"plan") in
  (List.find_exn xs ~f:(fun (v:S.task_observation) -> String.equal v.task.id id)).dependencies
let reject name s r = check name (Result.is_error (run s r 200L))
let complete s id = let c=ok (S.claim_task s ~plan_id:"plan" ~task_id:id ~worker:"finish" ~now_ns:300L ~lease_ns:100L) in
  ok (S.complete_task s ~plan_id:"plan" ~task_id:id ~worker:"finish" ~expected_attempt:c.attempt ~result:"fixture" ~now_ns:301L)

let () =
  fixture (fun path s attempt ->
    let r=request attempt in
    let fingerprint=scalar path "SELECT graph_fingerprint FROM sa_plan_plan WHERE id='plan'" in
    let before_ready=(ok (S.summary s ~plan_id:"plan")).ready in
    let receipt=ok (run s r 200L) in
    check "additive exact old edges preserved" (List.equal String.equal (deps s "a") ["b";"c"]);
    check "receipt before and after explicit" (List.equal String.equal receipt.before_dependencies ["b"] && List.equal String.equal receipt.after_dependencies ["b";"c"]);
    check "registered provenance unchanged" (String.equal fingerprint receipt.registered_graph_fingerprint && String.equal fingerprint (scalar path "SELECT graph_fingerprint FROM sa_plan_plan WHERE id='plan'"));
    check "schema v7 preserved" (S.schema_version s=7);
    check "adding prerequisite never increases readiness" ((ok (S.summary s ~plan_id:"plan")).ready <= before_ready);
    let replay=ok (run s r 201L) in
    check "identical retry returns original durable receipt" (replay.replayed && Int64.equal replay.recorded_at_ns receipt.recorded_at_ns && String.equal replay.request_sha256 receipt.request_sha256);
    check "one audit row only" (String.equal (scalar path "SELECT count(*) FROM sa_plan_dependency_repair") "1");
    reject "same operation changed request refuses" s {r with prerequisite_task_id="d"};
    List.iter ["UPDATE sa_plan_dependency_repair SET worker='forged'";"DELETE FROM sa_plan_dependency_repair"] ~f:(fun sql ->
      raw path (fun db -> let rc=Sqlite3.exec db sql in check "raw audit mutation refused" ((match rc with Sqlite3.Rc.OK -> false | _ -> true) && String.is_substring (Sqlite3.errmsg db) ~substring:"append-only")));
    complete s "b";
    check "old prerequisites completed still blocked by newly added edge" (Result.is_error (S.claim_task s ~plan_id:"plan" ~task_id:"a" ~worker:"soak" ~now_ns:400L ~lease_ns:100L));
    complete s "c";
    let claim=ok (S.claim_task s ~plan_id:"plan" ~task_id:"a" ~worker:"soak" ~now_ns:400L ~lease_ns:100L) in
    check "all prerequisites completed restores readiness" (String.equal claim.task_id "a");
    reject "executing target refuses even idempotent retry" s r);
  fixture (fun path s attempt ->
    let r=request attempt in
    List.iter [ {r with expected_attempt=attempt+1};{r with worker="foreign"};
      {r with plan_id="missing-plan"};{r with maintenance_task_id="missing-maint"};
      {r with target_task_id="missing-target"};{r with prerequisite_task_id="missing-prerequisite"};
      {r with prerequisite_task_id="a"};{r with target_task_id="maint";expected_dependencies=[]};
      {r with expected_dependencies=[]};{r with expected_dependencies=["b";"b"]};
      {r with operation_id="../unsafe"} ] ~f:(reject "invalid or stale request refuses" s);
    check "exclusive lease expiry boundary" (Result.is_error (run s r 1100L));
    check "negative clock refuses" (Result.is_error (run s r (-1L)));
    check "failed first repair leaves no lazy audit namespace" (not (audit_exists path));
    check "failed first repair leaves old dependencies" (List.equal String.equal (deps s "a") ["b"]);
    let n=ref 0 in
    check "lease expiry during graph validation rolls back DDL and edge" (Result.is_error (S.add_dependency_observed s r ~observe_now:(fun () -> incr n;if !n=1 then 200L else 1100L)));
    check "expiry rollback preserves graph and audit absence" (List.equal String.equal (deps s "a") ["b"] && not (audit_exists path));
    let n=ref 0 in
    check "host clock regression refuses" (Result.is_error (S.add_dependency_observed s r ~observe_now:(fun () -> incr n;if !n=1 then 200L else 199L))));
  fixture (fun path s attempt ->
    let r=request attempt in
    ok (S.create_plan s ~id:"foreign" ~name:"fixture/foreign" ~title:"foreign" ~now_ns:1L);
    ok (S.create_task s ~plan_id:"foreign" ~id:"alien" ~name:"fixture/foreign/alien" ~title:"foreign-only task" ~parent_id:None ~dependencies:[] ~priority:0 ~now_ns:1L);
    reject "foreign plan prerequisite cannot cross namespace" s {r with prerequisite_task_id="alien"};
    reject "foreign plan maintenance task cannot cross namespace" s {r with maintenance_task_id="alien"};
    let c=ok (S.claim_task s ~plan_id:"plan" ~task_id:"d" ~worker:"busy" ~now_ns:150L ~lease_ns:500L) in
    reject "executing target rejects new edge" s {r with target_task_id="d";expected_dependencies=[]};
    ok (S.complete_task s ~plan_id:"plan" ~task_id:"d" ~worker:"busy" ~expected_attempt:c.attempt ~result:"done" ~now_ns:200L);
    reject "completed target rejects new edge" s {r with target_task_id="d";expected_dependencies=[]};
    check "no audit DDL for target refusal" (not (audit_exists path)));
  fixture (fun _path s attempt ->
    let r=request attempt in
    ignore (ok (run s {r with operation_id="first-current-edge";target_task_id="c";prerequisite_task_id="a";expected_dependencies=[]} 200L) : S.dependency_repair_receipt);
    reject "cycle uses actual amended graph not original fingerprint" s r;
    check "cycle refusal keeps original target edges" (List.equal String.equal (deps s "a") ["b"]));
  fixture (fun path s attempt ->
    let r=request attempt in
    ignore (ok (run s r 200L) : S.dependency_repair_receipt);
    ignore (ok (run s {r with operation_id="unrelated-edge";target_task_id="d";prerequisite_task_id="b";expected_dependencies=[]} 201L) : S.dependency_repair_receipt);
    reject "replay holds when exact whole postgraph changed" s r;
    check "old receipt preserved on postgraph HOLD" (Option.is_some (ok (S.lookup_dependency_repair s ~operation_id:r.operation_id)));
    check "two successful operations exactly two audit rows" (String.equal (scalar path "SELECT count(*) FROM sa_plan_dependency_repair") "2"));
  fixture (fun path s attempt ->
    exec path "CREATE TABLE sa_plan_dependency_repair (operation_id TEXT)";
    reject "wrong preexisting audit namespace refuses" s (request attempt);
    check "wrong schema refusal leaves edge unchanged" (List.equal String.equal (deps s "a") ["b"]));
  fixture (fun path s attempt ->
    exec path "CREATE TRIGGER fixture_fail_edge AFTER INSERT ON sa_plan_dependency WHEN NEW.task_id='a' AND NEW.dependency_id='c' BEGIN SELECT RAISE(ABORT,'seeded edge failure'); END";
    reject "seeded SQL effect failure rolls back" s (request attempt);
    check "edge failure rolls back graph and new audit DDL" (List.equal String.equal (deps s "a") ["b"] && not (audit_exists path)));
  fixture (fun path s attempt ->
    let r=request attempt in ignore (ok (run s r 200L) : S.dependency_repair_receipt);
    exec path "DROP TRIGGER sa_plan_dependency_repair_no_update";
    reject "missing append-only trigger refuses" s {r with operation_id="missing-trigger";target_task_id="d";prerequisite_task_id="b";expected_dependencies=[]};
    exec path "CREATE TRIGGER sa_plan_dependency_repair_no_update BEFORE UPDATE ON sa_plan_dependency_repair BEGIN SELECT 1; END";
    reject "wrong append-only trigger definition refuses" s {r with operation_id="wrong-trigger";target_task_id="d";prerequisite_task_id="b";expected_dependencies=[]});
  (* Independent bounded Kahn oracle vs the persisted Store DFS interpretation.
     Two deterministic seeds choose graphs; all nodes are created before edges. *)
  List.iter [17;91] ~f:(fun seed ->
    let rng=Random.State.make [|seed|] in
    for iteration=0 to 19 do
      fixture (fun _path s attempt ->
        let edges=ref ["a","b"] in
        let acyclic_kahn edges =
          let remaining=ref ["a";"b";"c";"d"] in
          let rec drain () = match List.find !remaining ~f:(fun n -> not (List.exists edges ~f:(fun (a,b) -> String.equal a n && List.mem !remaining b ~equal:String.equal))) with
            | None -> List.is_empty !remaining
            | Some n -> remaining:=List.filter !remaining ~f:(fun x -> not (String.equal x n));drain () in drain () in
        for operation=0 to 5 do
          let names=[|"a";"b";"c";"d"|] in
          let target=names.(Random.State.int rng 4) and prerequisite=names.(Random.State.int rng 4) in
          let expected=List.filter_map !edges ~f:(fun (a,b) -> if String.equal a target then Some b else None) in
          let allowed=not (String.equal target prerequisite) && not (List.mem expected prerequisite ~equal:String.equal) && acyclic_kahn ((target,prerequisite)::!edges) in
          let r={ (request attempt) with operation_id=Printf.sprintf "seed-%d-%d-%d" seed iteration operation;target_task_id=target;prerequisite_task_id=prerequisite;expected_dependencies=expected } in
          let result=run s r 200L in
          check "seeded Kahn reference agrees with actual persisted DFS decision" (Bool.equal allowed (Result.is_ok result));
          if allowed then edges:=(target,prerequisite)::!edges
        done)
    done);
  Printf.printf "dependency-repair %d meaningful checks completed\n%!" !checks

(* Actual bounded CLI boundary controls; executable supplied by private build,
   never a production path or shell. Only synthetic DBs and a minimal env enter. *)
let cli_request_json (r:S.dependency_repair) = `Assoc [
  "operation_id",`String r.operation_id;"plan_id",`String r.plan_id;
  "maintenance_task_id",`String r.maintenance_task_id;"worker",`String r.worker;
  "expected_attempt",`Int r.expected_attempt;"target_task_id",`String r.target_task_id;
  "prerequisite_task_id",`String r.prerequisite_task_id;
  "expected_dependencies",`List (List.map r.expected_dependencies ~f:(fun x -> `String x))]
let invoke_cli executable path arguments input =
  let rd,wr=U.pipe ~cloexec:true () and output,child_output=U.pipe ~cloexec:true () in
  let null=U.openfile "/dev/null" [U.O_WRONLY] 0 in
  let env=[|"PATH=/usr/bin:/bin";"UOS_SA_PLAN_DB="^path|] in
  let pid=U.create_process_env executable (Array.of_list (executable::arguments)) env rd child_output null in
  U.close rd;U.close child_output;U.close null;
  let deadline=U.gettimeofday () +. 10. in
  let reaped=ref false in
  Exn.protect ~f:(fun () ->
    let bytes=Bytes.of_string input in
    let rec send offset = if offset < Bytes.length bytes then
      let n=U.write wr bytes offset (Bytes.length bytes-offset) in send (offset+n) in
    send 0;U.close wr;
    let result=Buffer.create 2048 and chunk=Bytes.create 4096 in
    let rec receive () =
      let remaining=deadline -. U.gettimeofday () in
      if Float.(remaining <= 0.) then failwith "CLI timeout";
      let ready,_,_=U.select [output] [] [] remaining in
      if List.is_empty ready then failwith "CLI timeout";
      match U.read output chunk 0 (Bytes.length chunk) with
      | 0 -> ()
      | n -> if Buffer.length result+n > 8192 then failwith "CLI output bound";
          Buffer.add_subbytes result chunk ~pos:0 ~len:n;receive () in
    receive ();
    let rec await () = match U.waitpid [U.WNOHANG] pid with
      | 0,_ -> if Float.(U.gettimeofday () >= deadline) then failwith "CLI reap timeout";
          ignore (U.select [] [] [] 0.01 : U.file_descr list * U.file_descr list * U.file_descr list);await ()
      | _,status -> reaped:=true;status in
    let status=await () in
    (match status with U.WEXITED n -> n | U.WSIGNALED _ | U.WSTOPPED _ -> -1),Buffer.contents result)
    ~finally:(fun () ->
      (try U.close wr with _ -> ());(try U.close output with _ -> ());
      if not !reaped then (try U.kill pid Stdlib.Sys.sigkill;ignore (U.waitpid [] pid : int * U.process_status) with _ -> ()))
let () = match Sys.getenv "UOS_DEPENDENCY_REPAIR_TEST_CLI" with
  | None -> Printf.printf "dependency-repair CLI boundary UNRUN: private executable not supplied\n%!"
  | Some executable ->
      fixture (fun path s _ ->
        let now=Time_ns.now () |> Time_ns.to_int_ns_since_epoch |> Int64.of_int in
        let owned=ok (S.claim_task s ~plan_id:"plan" ~task_id:"maint" ~worker:"worker" ~now_ns:now ~lease_ns:60_000_000_000L) in
        let r=request owned.attempt in
        let body=cli_request_json r |> Yojson.Safe.to_string in
        let code,receipt=invoke_cli executable path ["task";"dependency-add"] body in
        check "actual CLI structured request succeeds" (code=0 && String.is_substring receipt ~substring:"\"replayed\":false");
        let code,receipt=invoke_cli executable path ["--dependency-add"] body in
        check "actual CLI replay emits historical receipt without reinsert" (code=0 && String.is_substring receipt ~substring:"\"replayed\":true");
        let fields=match cli_request_json r with `Assoc xs -> xs | _ -> assert false in
        let malformed=[
          Yojson.Safe.to_string (`Assoc (("operation_id",`String "duplicate")::fields));
          Yojson.Safe.to_string (`Assoc (("review",`String "opaque-not-authority")::fields));
          Yojson.Safe.to_string (`Assoc (List.filter fields ~f:(fun (k,_) -> not (String.equal k "expected_dependencies"))));
          Yojson.Safe.to_string (`Assoc (("now_ns",`String "1")::fields));
          Yojson.Safe.to_string (`Assoc (List.map fields ~f:(fun (k,v) -> k,if String.equal k "expected_attempt" then `String "1" else v)));
          "//comment\n"^body;"{";String.make 65537 ' ';"{\"operation_id\":\"\255\"}"
        ] in
        List.iter malformed ~f:(fun input ->
          let code,_=invoke_cli executable path ["--dependency-add"] input in
          check "actual CLI refuses malformed duplicate unknown missing oversized or nonRFC input" (code<>0));
        let code,_=invoke_cli executable path ["--dependency-add";"extra"] "" in
        check "actual CLI refuses extra argv before stdin effects" (code=2);
        check "all CLI refusals preserve exact edge and one audit row" (List.equal String.equal (deps s "a") ["b";"c"] && String.equal (scalar path "SELECT count(*) FROM sa_plan_dependency_repair") "1");
        let absent=path^"-must-not-create" in
        let code,_=invoke_cli executable absent ["--dependency-add"] body in
        check "actual CLI never creates missing database" (code<>0 && not (Stdlib.Sys.file_exists absent)));
      Printf.printf "dependency-repair including CLI %d meaningful checks completed\n%!" !checks

(* Exhaustive small-domain interpretation: every directed graph without self
   edges on three nodes (64), every acyclic base (observed count), and all nine
   possible additive ordered pairs including self. Independent Floyd-Warshall
   closure decides cycles; this is finite coverage, never a general proof. *)
let () =
  let names=[|"x";"y";"z"|] in
  let pairs=[|(0,1);(0,2);(1,0);(1,2);(2,0);(2,1)|] in
  let closure_acyclic edges =
    let reach=Array.init 3 ~f:(fun _ -> Array.create ~len:3 false) in
    List.iter edges ~f:(fun (a,b) -> reach.(a).(b)<-true);
    for k=0 to 2 do for a=0 to 2 do for b=0 to 2 do
      reach.(a).(b)<-reach.(a).(b) || (reach.(a).(k) && reach.(k).(b))
    done done done;
    not (reach.(0).(0) || reach.(1).(1) || reach.(2).(2)) in
  let bases=ref 0 and transitions=ref 0 in
  for mask=0 to 63 do
    let edges=Array.to_list (Array.filter_mapi pairs ~f:(fun bit edge ->
      if Stdlib.(mask land (1 lsl bit)) <> 0 then Some edge else None)) in
    if closure_acyclic edges then begin
      incr bases;
      for target=0 to 2 do for prerequisite=0 to 2 do
        let path=Stdlib.Filename.temp_file "uos-repair-exhaustive-" ".sqlite3" in
        let s=ok (S.open_db path) in
        Exn.protect ~f:(fun () ->
          let nodes=Array.to_list (Array.mapi names ~f:(fun i id ->
            let dependencies=List.filter_map edges ~f:(fun (a,b) -> if a=i then Some names.(b) else None) in
            node ~dependencies id)) in
          ok (S.register_plan s ~id:"plan" ~title:"finite synthetic matrix" ~nodes:(node "maint"::nodes));
          let claim=ok (S.claim_task s ~plan_id:"plan" ~task_id:"maint" ~worker:"worker" ~now_ns:100L ~lease_ns:1000L) in
          let expected=List.filter_map edges ~f:(fun (a,b) -> if a=target then Some names.(b) else None) in
          let r={ (request claim.attempt) with operation_id="finite-transition";
            target_task_id=names.(target);prerequisite_task_id=names.(prerequisite);
            expected_dependencies=expected } in
          let before=(ok (S.summary s ~plan_id:"plan")).ready in
          let already=List.exists edges ~f:(fun (a,b) -> a=target && b=prerequisite) in
          let oracle=target<>prerequisite && not already && closure_acyclic ((target,prerequisite)::edges) in
          let observed=run s r 200L in
          check "exhaustive three-node transitive closure agrees with persisted additive decision" (Bool.equal oracle (Result.is_ok observed));
          check "exhaustive additive readiness is monotone nonincreasing" ((ok (S.summary s ~plan_id:"plan")).ready <= before);
          incr transitions)
          ~finally:(fun () -> S.close s;List.iter [path;path^"-wal";path^"-shm"] ~f:(fun p -> if Stdlib.Sys.file_exists p then Stdlib.Sys.remove p))
      done done
    end
  done;
  check "finite base and transition domain cardinality" (!bases=25 && !transitions=225);
  Printf.printf "dependency-repair exhaustive64graphs/%dDAGbases/%dtransitions; %d total checks\n%!" !bases !transitions !checks

let () =
  fixture (fun path s attempt ->
    let calls=ref 0 in
    let result=S.add_dependency_observed s (request attempt) ~observe_now:(fun () ->
      incr calls;match !calls with 1 -> 200L | 2 -> 201L | _ -> 1100L) in
    check "precommit expiry after successful insert and audit readback rolls back everything" (Result.is_error result && !calls=3);
    check "precommit expiry leaves original graph and no new audit schema" (List.equal String.equal (deps s "a") ["b"] && not (audit_exists path)));
  fixture (fun path s attempt ->
    let calls=ref 0 in
    let result=S.add_dependency_observed s (request attempt) ~observe_now:(fun () ->
      incr calls;match !calls with 1 -> 200L | 2 -> 201L | _ -> 200L) in
    check "regression between prewrite and precommit observations refuses" (Result.is_error result && List.equal String.equal (deps s "a") ["b"] && not (audit_exists path)));
  List.iter [255;256] ~f:(fun count ->
    let path=Stdlib.Filename.temp_file "uos-repair-count-bound-" ".sqlite3" in
    let s=ok (S.open_db path) in
    Exn.protect ~f:(fun () ->
      let dependencies=List.init count ~f:(fun i -> Printf.sprintf "d%03d" i) in
      let nodes=node "maint"::node "p"::node ~dependencies "target"::List.map dependencies ~f:node in
      ok (S.register_plan s ~id:"plan" ~title:"dependency set bound" ~nodes);
      let claim=ok (S.claim_task s ~plan_id:"plan" ~task_id:"maint" ~worker:"worker" ~now_ns:100L ~lease_ns:1000L) in
      let r={ (request claim.attempt) with target_task_id="target";prerequisite_task_id="p";expected_dependencies=dependencies } in
      let result=run s r 200L in
      check "dependency set boundary255to256 accepts and256to257 refuses" (Bool.equal (count=255) (Result.is_ok result));
      let observed=deps s "target" in
      check "resulting dependency set remains at most256 and old edges preserved" (List.length observed<=256 && List.for_all dependencies ~f:(fun id -> List.mem observed id ~equal:String.equal)))
      ~finally:(fun () -> S.close s;List.iter [path;path^"-wal";path^"-shm"] ~f:(fun p -> if Stdlib.Sys.file_exists p then Stdlib.Sys.remove p)));
  Printf.printf "dependency-repair final clock/count boundary suite: %d total checks\n%!" !checks
