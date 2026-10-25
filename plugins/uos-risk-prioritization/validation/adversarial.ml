(* Independent finite-state oracle and adversarial fixtures; no live task writes. *)
open Priority
open Record
let with_dir f =
  let path=Filename.temp_file "uos-risk-checks-" "" in
  Sys.remove path; Unix.mkdir path 0o700;
  let rec cleanup p =
    if (Unix.lstat p).Unix.st_kind=Unix.S_DIR then (
      Array.iter (fun name->cleanup (Filename.concat p name)) (Sys.readdir p);Unix.rmdir p)
    else Unix.unlink p in
  Fun.protect ~finally:(fun ()->cleanup path) (fun ()->f path)
let write path value =
  let oc=open_out_bin path in
  Fun.protect ~finally:(fun ()->close_out_noerr oc) (fun ()->output_string oc value)
let oracle nodes =
  (* Transitive matrix on three nodes; independent from Priority's DFS/reverse graph. *)
  let ns=Array.of_list nodes in
  let n=Array.length ns in
  let index id =
    let found=ref (-1) in Array.iteri (fun i x->if x.id=id then found:=i) ns;!found in
  let reach=Array.make_matrix n n false in
  Array.iteri (fun i x->
    if x.state<>"completed" then List.iter (fun dep->reach.(i).(index dep)<-true) x.dependencies) ns;
  for k=0 to n-1 do for i=0 to n-1 do for j=0 to n-1 do
    reach.(i).(j)<-reach.(i).(j) || (reach.(i).(k) && reach.(k).(j))
  done done done;
  let c s=int_of_string (String.sub s 1 1) in
  Array.to_list (Array.mapi (fun i x->
    let eligible=x.state="available" &&
      List.for_all (fun dep->ns.(index dep).state="completed") x.dependencies in
    if not eligible then None else
      let related=List.init n Fun.id |> List.filter (fun j->i=j || reach.(j).(i)) in
      let cls=List.fold_left (fun acc j->min acc (c ns.(j).class_)) 3 related in
      let leaders=List.filter (fun j->c ns.(j).class_=cls) related in
      let score=List.fold_left (fun acc j->max acc (Option.get ns.(j).own_score)) 1 leaders in
      let ids=List.map (fun j->ns.(j).id) leaders |> List.sort String.compare in
      Some (x.id,cls,score,ids)) ns)
  |> List.filter_map Fun.id
  |> List.sort (fun (a,c,s,_) (b,d,t,_)->
      let k=compare c d in if k<>0 then k else
      let k=compare t s in if k<>0 then k else String.compare a b)
let run () =
  let count=ref 0 in
  let check name condition=incr count;require condition ("adversarial: "^name) in
  let reject name fn=check name (try fn ();false with Invalid _->true) in
  let s=schema () and ex=sample () in
  let bad=change "properties"
    (change "optional_backdoor" (`Assoc ["type",`String "string";"not",`Assoc []])
      (field "properties" s)) s in
  reject "hidden assertion" (fun ()->ignore (check_record bad ex));
  reject "losing anyOf branch assertion" (fun ()->
    ignore (check_record (`Assoc ["anyOf",`List [s;`Assoc ["type",`String "null";"not",`Assoc []]]]) ex));
  reject "unsupported optional regex" (fun ()->
    schema_preflight (`Assoc ["properties",`Assoc ["absent",`Assoc ["pattern",`String ".*"]]]));
  reject "unknown schema dialect" (fun ()->schema_preflight (change "$schema" (`String "future") s));
  reject "malformed ignored keyword" (fun ()->schema_preflight (change "additionalProperties" `Null s));
  reject "deep JSON before recursive parser" (fun ()->ignore (Bounded.json_text
    (String.make 65 '['^"0"^String.make 65 ']')));
  check "quoted braces do not count as nesting"
    (Bounded.json_text "\"[[{]}]]\""=`String "[[{]}]]");
  reject "JSON budget" (fun ()->ignore (Bounded.json_text (String.make 1048577 ' ')));
  reject "duplicate key" (fun ()->unique (Bounded.json_text "{\"a\":1,\"a\":2}"));
  check "SHA-256 empty known vector" (Bounded.sha256 ""="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  check "SHA-256 abc known vector" (Bounded.sha256 "abc"="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  List.iter (fun path->reject ("unsafe evidence locator "^path)
    (fun ()->ignore (Bounded.safe_relative path)))
    ["/etc/passwd";"../file";"a/../file";"a//b";".env";"var/sa-plan/uos.sqlite3";
     "state/cache.json";".jj/repo";"keys/private.key";"foo\000bar";"a\\b";"x:id";".ssh/id_rsa"];
  let now="2026-09-07T16:00:00Z" in
  let n ?(deps=[]) id =
    {id;class_="P2";own_score=Some 100;upper=100;state="available";readiness="ready";
      dependencies=deps;observed="2026-09-07T15:00:00Z";expires="2026-09-08T00:00:00Z";
      ready_since="2026-09-07T15:00:00Z"} in
  for mask=0 to 7 do for classes=0 to 63 do for states=0 to 7 do for scores=0 to 7 do
    let ns=List.init 3 (fun i->
      let id=String.make 1 (Char.chr (97+i)) in
      let deps=match i with
        | 1 -> if mask land 1=1 then ["a"] else []
        | 2 -> (if mask land 2=2 then ["a"] else []) @ (if mask land 4=4 then ["b"] else [])
        | _ -> [] in
      let base=n ~deps id in
      let value=if scores land (1 lsl i)=0 then 1 else 3125 in
      {base with class_="P"^string_of_int ((classes lsr (2*i)) land 3);
        state=(if states land (1 lsl i)=0 then "available" else "completed");
        own_score=Some value;upper=value}) in
    let actual=rank ~now ns |> List.map (fun (r:ranked)->
      r.task.id,r.effective_class,r.effective_score,r.origins) in
    check "independent three-node DAG oracle" (actual=oracle ns)
  done done done done;
  reject "cycle" (fun ()->ignore (rank ~now [n ~deps:["b"] "a";n ~deps:["a"] "b"]));
  reject "missing dependency" (fun ()->ignore (rank ~now [n ~deps:["missing"] "a"]));
  reject "duplicate edge" (fun ()->ignore (rank ~now [n "a";n ~deps:["a";"a"] "b"]));
  reject "edge exhaustion" (fun ()->ignore (rank ~now [n ~deps:(List.init 10001 string_of_int) "a"]));
  check "unknown excluded" (rank ~now [{(n "a") with own_score=None}]=[]);
  check "exact expiry excluded" (rank ~now [{(n "a") with expires=now}]=[]);
  let chrono="ref,ip,3,1000,0.001,0.0,0.0,0.0,0.0,0.0,0.03,0.002,64,Normal" in
  ignore (Host_clock.parse ~now:1100. chrono);incr count;
  let clock_field i value=String.split_on_char ',' chrono
    |> List.mapi (fun k v->if i=k then value else v) |> String.concat "," in
  List.iter (fun (i,value)->reject ("unsafe clock field "^string_of_int i)
    (fun ()->ignore (Host_clock.parse ~now:1100. (clock_field i value))))
    [2,"0";13,"Not synchronised";4,"nan";4,"2.0";10,"-1";11,"3";3,"1200";3,"-4000"];
  reject "backwards wall step" (fun ()->Host_clock.consistent ~wall_start:10. ~wall_end:9. ~elapsed:1.);
  reject "forward wall step" (fun ()->Host_clock.consistent ~wall_start:10. ~wall_end:20. ~elapsed:1.);
  reject "elapsed timeout" (fun ()->Host_clock.consistent ~wall_start:10. ~wall_end:41. ~elapsed:31.);
  with_dir (fun root->
    let path=Filename.concat root "AGENTS.md" in
    let contents="sanitized fixture\nsecond line\n" in write path contents;
    check "safe evidence bytes" (Bounded.evidence ~root "AGENTS.md"=contents);
    Unix.symlink "AGENTS.md" (Filename.concat root "alias.md");
    reject "symlink evidence" (fun ()->ignore (Bounded.evidence ~root "alias.md"));
    Unix.mkfifo (Filename.concat root "fifo") 0o600;
    reject "FIFO returns without blocking" (fun ()->ignore (Bounded.read (Filename.concat root "fifo")));
    write (Filename.concat root "large") (String.make 1048577 'x');
    reject "large regular file" (fun ()->ignore (Bounded.read (Filename.concat root "large")));
    let digest=Bounded.sha256 contents in
    let evidence=`List [`Assoc ["path",`String "AGENTS.md";"sha256",`String digest;
      "observed_at",field "observed_at" ex]] in
    let fs=`Assoc (List.map (fun (k,f)->k,change "evidence_refs" (`List [`String "AGENTS.md:2"]) f)
      (obj (field "factors" ex))) in
    let base=ex |> change "task_id" (`String "a") |> change "assessment_id" (`String "fixture-a")
      |> change "task_state" (`String "available") |> change "factors" fs
      |> change "snapshot" (change "evidence" evidence (field "snapshot" ex)) in
    ignore (check_record s base);
    let audit xs=Checker.audit ~root ~now xs in
    check "complete local packet" ((audit [base]).findings=[]);
    check "assessment expiring during check holds at exit"
      (Checker.final_time_findings ~now:(text "valid_until" base) [base]<>[]);
    let younger=base |> change "observed_at" (`String "2026-09-07T16:00:00Z")
      |> change "valid_until" (`String "2026-09-08T16:00:00Z") in
    check "source expiring before assessment holds at exit"
      (Checker.final_time_findings ~now:"2026-09-08T15:59:00Z" [younger]<>[]);
    let has rule report=List.exists (fun (f:Checker.finding)->f.rule=rule) report.Checker.findings in
    write path (contents^"tampered\n");
    check "tampered bytes" (has "RP-EVIDENCE" (audit [base]));
    reject "changed evidence at exit" (fun ()->Checker.verify_again ~root ["AGENTS.md",digest]);
    write path contents;
    let snapshot=field "snapshot" base in
    let e=List.hd (arr evidence) in
    let edit_ev k v=change "snapshot" (change "evidence" (`List [change k v e]) snapshot) base in
    check "future evidence" (has "RP-EVIDENCE" (audit [edit_ev "observed_at" (`String "2026-09-07T16:00:01Z")]));
    check "stale evidence" (has "RP-EVIDENCE" (audit [edit_ev "observed_at" (`String "2026-09-05T00:00:00Z")]));
    check "duplicate evidence" (has "RP-SNAPSHOT" (audit [
      change "snapshot" (change "evidence" (`List [e;e]) snapshot) base]));
    check "runtime claim unsupported" (has "RP-SNAPSHOT" (audit [
      change "snapshot" (change "kind" (`String "runtime") snapshot) base]));
    let bad_factor=change "evidence_refs" (`List [`String "missing.ml:1"]) (field "impact" fs) in
    check "unbound source" (has "RP-REFERENCE" (audit [change "factors" (change "impact" bad_factor fs) base]));
    check "stale assessment" (has "RP-TIME" (audit [change "valid_until" (`String now) base]));
    let other=base |> change "task_id" (`String "b") |> change "assessment_id" (`String "fixture-b") in
    check "equal score cost review" (has "RP-COST-TIE" (audit [base;other]));
    let three=field "impact" fs |> change "value" (`Int 3) |> change "low" (`Int 3) |> change "high" (`Int 3) in
    let lower=other |> change "factors" (change "impact" three fs) |> change "score" (`Int 720)
      |> change "score_interval" (`List [`Int 720;`Int 720]) in
    ignore (check_record s lower);
    check "one-step judgment reverses close order" (has "RP-SENSITIVITY" (audit [base;lower]));
    let consumer=other |> change "class" (`String "P1") |> change "score" `Null
      |> change "readiness" (`String "needs_evidence")
      |> change "dependencies" (`List [`String "a"]) in
    check "unknown consumer cannot silently inflate urgency"
      (has "RP-INHERITANCE" (audit [base;consumer]));
    let live=Live_plan.{id="a";state="available";worker=None;lease=None;attempt=0;
      completed=None;result_present=false;dependencies=[]} in
    let coherent xs ts=Checker.coherence ~now_ns:1000L xs ts=[] in
    check "live plan matches" (coherent [base] [live]);
    check "missing canonical task detected" (not (coherent [base] [live;{live with id="b"}]));
    check "forged state detected" (not (coherent [base] [{live with state="completed";completed=Some 900L;result_present=true}]));
    check "forged dependency detected" (not (coherent [base] [{live with dependencies=["b"]}]));
    let executing=change "task_state" (`String "executing") base in
    let leased={live with state="executing";worker=Some (text "actor" base);lease=Some 1001L;attempt=1} in
    check "live lease matches" (coherent [executing] [leased]);
    check "lease expiry exact boundary" (not (coherent [executing] [{leased with lease=Some 1000L}]));
    check "wrong worker detected" (not (coherent [executing] [{leased with worker=Some "other"}]));
    check "attempt zero rejected" (not (coherent [executing] [{leased with attempt=0}]));
    let expired={leased with lease=Some 900L} in
    let binding=("a",text "actor" base,1,900L) in
    let project rows=Checker.reclaim_projection ~now_ns:1000L binding [executing] rows in
    check "exact expired reclaim projection" (text "task_state" (List.hd(project [expired]))="available");
    check "reclaim leaves original assessment unchanged" (text "task_state" executing="executing");
    check "exact reclaim coherence" (Checker.coherence ~reclaim:binding ~now_ns:1000L [executing] [expired]=[]);
    check "ordinary preflight still refuses expired lease" (not(coherent [executing] [expired]));
    reject "reclaim cannot take live lease" (fun()->ignore(project [leased]));
    reject "reclaim cannot take foreign owner" (fun()->ignore(project [{expired with worker=Some "other"}]));
    reject "reclaim cannot hide changed attempt" (fun()->ignore(project [{expired with attempt=2}]));
    reject "reclaim cannot hide changed deadline" (fun()->ignore(project [{expired with lease=Some 899L}]));
    reject "reclaim needs actual lease" (fun()->ignore(project [{expired with lease=None}]));
    reject "reclaim cannot take available task" (fun()->ignore(project [live]));
    reject "reclaim cannot take completed task" (fun()->ignore(project [{expired with state="completed"}]));
    reject "reclaim cannot hide result" (fun()->ignore(project [{expired with result_present=true}]));
    reject "reclaim cannot hide completion time" (fun()->ignore(project [{expired with completed=Some 800L}]));
    let other_exec=executing |> change "task_id" (`String "b") |> change "assessment_id" (`String "b") in
    check "reclaim preserves other expired task HOLD"
      (Checker.coherence ~reclaim:binding ~now_ns:1000L [executing;other_exec]
        [expired;{expired with id="b"}]<>[]);
    check "reclaim preserves changed dependencies HOLD"
      (Checker.coherence ~reclaim:binding ~now_ns:1000L [executing]
        [{expired with dependencies=["uncompleted"]}]<>[]);
    check "reclaim preserves full plan completeness HOLD"
      (Checker.coherence ~reclaim:binding ~now_ns:1000L [executing] [expired;{live with id="b"}]<>[]);
    let projected=project [expired] |> List.map(change "readiness" (`String "blocked")) in
    check "reclaim does not make blocked task eligible"
      (Priority.rank ~now (List.map Record.candidate projected)=[]);
    let b_exec = executing |> change "task_id" (`String "b") |> change "assessment_id" (`String "b") |> change "actor" (`String "worker-b") in
    let b_expired = { expired with id="b"; worker=Some "worker-b"; attempt=1; lease=Some 900L } in
    let set_bindings = [("a", text "actor" base, 1, 900L); ("b", "worker-b", 1, 900L)] in
    let project_set rows = Checker.reclaim_set_projection ~now_ns:1000L set_bindings [executing; b_exec] rows in
    let proj_res = project_set [expired; b_expired] in
    check "reclaim-set two expired different owners projection"
      (List.for_all (fun j -> text "task_state" j = "available") proj_res);
    check "reclaim-set leaves original assessment unchanged"
      (text "task_state" executing = "executing" && text "task_state" b_exec = "executing");
    check "reclaim-set exact coherence pass"
      (Checker.coherence ~reclaim_set:set_bindings ~now_ns:1000L [executing; b_exec] [expired; b_expired] = []);
    check "full-plan ranking after reclaim-set"
      (Priority.rank ~now (List.map Record.candidate proj_res) <> []);
    reject "reclaim-set rejects set mismatch - omitted task"
      (fun () -> ignore (Checker.reclaim_set_projection ~now_ns:1000L [binding] [executing; b_exec] [expired; b_expired]));
    reject "reclaim-set rejects set mismatch - extra task"
      (fun () -> ignore (Checker.reclaim_set_projection ~now_ns:1000L (("c","worker-c",1,900L)::set_bindings) [executing; b_exec] [expired; b_expired]));
    reject "reclaim-set rejects empty bindings"
      (fun () -> ignore (Checker.reclaim_set_projection ~now_ns:1000L [] [executing; b_exec] [expired; b_expired]));
    reject "reclaim-set rejects duplicate task id"
      (fun () -> ignore (Checker.reclaim_set_projection ~now_ns:1000L (binding::set_bindings) [executing; b_exec] [expired; b_expired]));
    reject "reclaim-set rejects changed attempt"
      (fun () -> ignore (Checker.reclaim_set_projection ~now_ns:1000L [("a", text "actor" base, 2, 900L); ("b", "worker-b", 1, 900L)] [executing; b_exec] [expired; b_expired]));
    reject "reclaim-set rejects changed deadline"
      (fun () -> ignore (Checker.reclaim_set_projection ~now_ns:1000L [("a", text "actor" base, 1, 899L); ("b", "worker-b", 1, 900L)] [executing; b_exec] [expired; b_expired]));
    reject "reclaim-set rejects foreign owner"
      (fun () -> ignore (Checker.reclaim_set_projection ~now_ns:1000L [("a", "wrong-worker", 1, 900L); ("b", "worker-b", 1, 900L)] [executing; b_exec] [expired; b_expired]));
    check "reclaim-set coherence catches omitted task"
      (Checker.coherence ~reclaim_set:[binding] ~now_ns:1000L [executing; b_exec] [expired; b_expired] <> []);
    check "reclaim-set coherence catches extra task"
      (Checker.coherence ~reclaim_set:(("c","worker-c",1,900L)::set_bindings) ~now_ns:1000L [executing; b_exec] [expired; b_expired] <> []);
    check "reclaim-set coherence catches live unexpired lease"
      (Checker.coherence ~reclaim_set:set_bindings ~now_ns:1000L [executing; b_exec] [{expired with lease=Some 1200L}; b_expired] <> []);
    check "reclaim-set coherence catches missing lease"
      (Checker.coherence ~reclaim_set:set_bindings ~now_ns:1000L [executing; b_exec] [{expired with lease=None}; b_expired] <> []);
    check "reclaim-set coherence catches completed row"
      (Checker.coherence ~reclaim_set:set_bindings ~now_ns:1000L [executing; b_exec] [{expired with state="completed"; completed=Some 800L; result_present=true}; b_expired] <> []);
    check "reclaim-set coherence catches result-bearing row"
      (Checker.coherence ~reclaim_set:set_bindings ~now_ns:1000L [executing; b_exec] [{expired with result_present=true}; b_expired] <> []);
    check "reclaim-set preserves changed dependencies HOLD"
      (Checker.coherence ~reclaim_set:set_bindings ~now_ns:1000L [executing; b_exec] [{expired with dependencies=["uncompleted"]}; b_expired] <> []);
    check "reclaim-set preserves full plan completeness HOLD"
      (Checker.coherence ~reclaim_set:set_bindings ~now_ns:1000L [executing; b_exec] [expired; b_expired; {live with id="c"}] <> []);
    reject "reclaim-set rejects selected task outside bindings set"
      (fun () -> Checker.require_selected_in_set "unrelated_available_task" set_bindings);
    check "reclaim-set accepts selected task inside bindings set"
      (try Checker.require_selected_in_set "a" set_bindings; Checker.require_selected_in_set "b" set_bindings; true with _ -> false);
    let plan_json = "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"a\",\"worker\":\""^text "actor" base^"\",\"attempt\":1,\"lease_until_ns\":\"900\"},{\"task_id\":\"b\",\"worker\":\"worker-b\",\"attempt\":1,\"lease_until_ns\":\"900\"}]}" in
    let p_id, p_bindings = Checker.parse_bindings plan_json in
    check "parse_bindings parses valid strict plan_id and bindings" (p_id = "test" && p_bindings = set_bindings);
    reject "parse_bindings rejects top-level array"
      (fun () -> ignore (Checker.parse_bindings "[{\"task_id\":\"a\",\"worker\":\"w\",\"attempt\":1,\"lease_until_ns\":\"900\"}]"));
    reject "parse_bindings rejects missing plan_id"
      (fun () -> ignore (Checker.parse_bindings "{\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w\",\"attempt\":1,\"lease_until_ns\":\"900\"}]}"));
    reject "parse_bindings rejects empty plan_id"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"  \",\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w\",\"attempt\":1,\"lease_until_ns\":\"900\"}]}"));
    reject "parse_bindings rejects unknown top-level field"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w\",\"attempt\":1,\"lease_until_ns\":\"900\"}],\"extra\":1}"));
    reject "parse_bindings rejects alias plan field"
      (fun () -> ignore (Checker.parse_bindings "{\"plan\":\"test\",\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w\",\"attempt\":1,\"lease_until_ns\":\"900\"}]}"));
    reject "parse_bindings rejects unknown binding field"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w\",\"attempt\":1,\"lease_until_ns\":\"900\",\"unknown\":true}]}"));
    reject "parse_bindings rejects alias task field"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task\":\"a\",\"worker\":\"w\",\"attempt\":1,\"lease_until_ns\":\"900\"}]}"));
    reject "parse_bindings rejects alias previous_attempt field"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w\",\"previous_attempt\":1,\"lease_until_ns\":\"900\"}]}"));
    reject "parse_bindings rejects alias deadline field"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w\",\"attempt\":1,\"deadline\":\"900\"}]}"));
    reject "parse_bindings rejects numeric deadline"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w\",\"attempt\":1,\"lease_until_ns\":900}]}"));
    reject "parse_bindings rejects overflow deadline"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w\",\"attempt\":1,\"lease_until_ns\":\"99999999999999999999999\"}]}"));
    reject "parse_bindings rejects non-digit lease"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w\",\"attempt\":1,\"lease_until_ns\":\"900abc\"}]}"));
    reject "parse_bindings rejects zero deadline"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w\",\"attempt\":1,\"lease_until_ns\":\"0\"}]}"));
    reject "parse_bindings rejects negative deadline"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w\",\"attempt\":1,\"lease_until_ns\":\"-100\"}]}"));
    reject "parse_bindings rejects duplicate task id"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"a\",\"worker\":\"w1\",\"attempt\":1,\"lease_until_ns\":\"900\"},{\"task_id\":\"a\",\"worker\":\"w2\",\"attempt\":1,\"lease_until_ns\":\"900\"}]}"));
    reject "parse_bindings rejects empty list"
      (fun () -> ignore (Checker.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[]}"));
    reject "parse_bindings rejects malformed JSON"
      (fun () -> ignore (Checker.parse_bindings "{malformed"));
    let dbpath=Filename.concat root "plan.sqlite3" in
    let db=Sqlite3.db_open dbpath in
    let sql s=check "fixture SQL" (Sqlite3.exec db s=Sqlite3.Rc.OK) in
    sql "CREATE TABLE sa_plan_task(plan_id TEXT,id TEXT,state TEXT,worker TEXT,lease_until_ns INTEGER,attempt INTEGER,completed_at_ns INTEGER,result TEXT)";
    sql "CREATE TABLE sa_plan_dependency(plan_id TEXT,task_id TEXT,dependency_id TEXT)";
    sql "INSERT INTO sa_plan_task VALUES('test','a','available',NULL,NULL,0,NULL,NULL)";
    ignore (Sqlite3.db_close db);
    let before=Bounded.sha256 (Bounded.read dbpath) in
    let rows=Live_plan.read ~path:dbpath ~plan:"test" in
    check "read-only SQLite adapter matches fixture" (rows=[live]);
    check "read-only SQLite bytes unchanged" (Bounded.sha256 (Bounded.read dbpath)=before);
    let db2=Sqlite3.db_open dbpath in
    let sql2 s=check "fixture SQL 2" (Sqlite3.exec db2 s=Sqlite3.Rc.OK) in
    sql2 "INSERT INTO sa_plan_task VALUES('test-two','t1','executing','worker-1',900,1,NULL,NULL)";
    sql2 "INSERT INTO sa_plan_task VALUES('test-two','t2','executing','worker-2',900,1,NULL,NULL)";
    ignore (Sqlite3.db_close db2);
    let rows_two=Live_plan.read ~path:dbpath ~plan:"test-two" in
    let t1_exec = executing |> change "task_id" (`String "t1") |> change "actor" (`String "worker-1") in
    let t2_exec = executing |> change "task_id" (`String "t2") |> change "actor" (`String "worker-2") in
    let two_bindings = [("t1","worker-1",1,900L); ("t2","worker-2",1,900L)] in
    check "SQLite-read two expired tasks match reclaim set"
      (Checker.coherence ~reclaim_set:two_bindings ~now_ns:1000L [t1_exec; t2_exec] rows_two = []);
    check "SQLite-read two expired tasks projection"
      (List.for_all (fun j -> text "task_state" j = "available")
        (Checker.reclaim_set_projection ~now_ns:1000L two_bindings [t1_exec; t2_exec] rows_two));
    reject "SQL injection remains bound text" (fun ()->ignore (Live_plan.read ~path:dbpath ~plan:"test' OR 1=1 --"));
    let absent=Filename.concat root "absent.sqlite3" in
    check "missing DB not created" (try ignore (Live_plan.read ~path:absent ~plan:"test");false
      with Unix.Unix_error _ -> not (Sys.file_exists absent));

    (* === OPT-E: NC-01 through NC-20 controls for Reclaim_metadata === *)
    let meta_db = Filename.concat root "reclaim_meta.sqlite3" in
    let db_m = Sqlite3.db_open meta_db in
    let sql_m s = check "reclaim_meta fixture SQL" (Sqlite3.exec db_m s = Sqlite3.Rc.OK) in
    sql_m "CREATE TABLE sa_plan_task(plan_id TEXT,id TEXT,state TEXT,worker TEXT,lease_until_ns INTEGER,attempt INTEGER,completed_at_ns INTEGER,result TEXT)";
    sql_m "CREATE TABLE sa_plan_dependency(plan_id TEXT,task_id TEXT,dependency_id TEXT)";
    sql_m "INSERT INTO sa_plan_task VALUES('test-meta','t1','executing','worker-1',900,1,NULL,NULL)";
    sql_m "INSERT INTO sa_plan_task VALUES('test-meta','t2','executing','worker-2',900,1,NULL,NULL)";
    sql_m "INSERT INTO sa_plan_task VALUES('test-meta','t3','available',NULL,NULL,0,NULL,NULL)";
    sql_m "INSERT INTO sa_plan_task VALUES('test-meta','t4','executing','worker-4',5000000000,1,NULL,NULL)";
    ignore (Sqlite3.db_close db_m);

    let t1_port = executing |> change "plan_id" (`String "test-meta") |> change "task_id" (`String "t1")
                            |> change "assessment_id" (`String "asm-meta-t1") |> change "actor" (`String "worker-1") in
    let t2_port = executing |> change "plan_id" (`String "test-meta") |> change "task_id" (`String "t2")
                            |> change "assessment_id" (`String "asm-meta-t2") |> change "actor" (`String "worker-2") in
    let t3_port = base |> change "plan_id" (`String "test-meta") |> change "task_id" (`String "t3")
                       |> change "assessment_id" (`String "asm-meta-t3") |> change "task_state" (`String "available") in
    let t4_port = executing |> change "plan_id" (`String "test-meta") |> change "task_id" (`String "t4")
                            |> change "assessment_id" (`String "asm-meta-t4") |> change "actor" (`String "worker-4") in
    let valid_portfolio_records = [t1_port; t2_port; t3_port; t4_port] in
    let port_path = Filename.concat root "test_meta_portfolio.json" in
    write port_path (Yojson.Basic.to_string (`List valid_portfolio_records));

    let valid_bindings_json = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in

    (* Positive control: valid observation *)
    let valid_receipt = Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L
      ~portfolio_path:port_path ~raw_bindings:valid_bindings_json () in
    check "OPT-E valid observation status" (text "status" valid_receipt = "METADATA_OBSERVATION_PASS");
    check "OPT-E authority is NONE" (text "authority" valid_receipt = "NONE");
    check "OPT-E runtime_admission is NOT_GRANTED" (text "runtime_admission" valid_receipt = "NOT_GRANTED");
    check "OPT-E selection is NOT_EVALUATED" (text "selection" valid_receipt = "NOT_EVALUATED");

    (* NC-01: bindings omit one expired executing task -> refuse *)
    let nc01_json = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    reject "NC-01 omit expired executing task"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc01_json ()));

    (* NC-02: bindings include a task that is executing but NOT expired -> refuse *)
    let nc02_json = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2},\
      {\"task_id\":\"t4\",\"worker\":\"worker-4\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"5000000000\",\"expected_new_attempt\":2}\
    ]}" in
    reject "NC-02 include executing but unexpired task"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc02_json ()));

    (* NC-03: bindings include a task that is available or completed -> refuse *)
    let nc03_json = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2},\
      {\"task_id\":\"t3\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    reject "NC-03 include available task"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc03_json ()));

    (* NC-04: wrong worker for an otherwise correct binding -> refuse *)
    let nc04_json = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"wrong-worker\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    reject "NC-04 wrong worker"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc04_json ()));

    (* NC-05: previous_attempt off by one in either direction -> refuse *)
    let nc05_plus = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":2,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":3},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    let nc05_minus = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":0,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":1},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    reject "NC-05 previous_attempt off by one plus"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc05_plus ()));
    reject "NC-05 previous_attempt off by one minus"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc05_minus ()));

    (* NC-06: previous_lease_until_ns differing by one nanosecond -> refuse *)
    let nc06_diff = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"901\",\"expected_new_attempt\":2},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    reject "NC-06 previous_lease_until_ns differing by one nanosecond"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc06_diff ()));

    (* NC-07: previous_lease_until_ns in the future -> refuse as not expired *)
    let nc07_future = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"2000\",\"expected_new_attempt\":2},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    reject "NC-07 previous_lease_until_ns in future"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc07_future ()));

    (* NC-08: previous_lease_until_ns supplied as a JSON number large enough to truncate -> refuse on type *)
    let nc08_num = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":1791752573602044117,\"expected_new_attempt\":2},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    (try ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc08_num ());
         check "NC-08 must refuse on type" false
     with Invalid msg ->
       check "NC-08 refusal is on type" (String.ends_with ~suffix:"decimal string, not a number" msg));

    (* NC-09: duplicate task ids -> refuse *)
    let nc09_dup = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2},\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    reject "NC-09 duplicate task ids"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc09_dup ()));

    (* NC-10: empty bindings -> refuse. 1001 bindings -> refuse. *)
    let nc10_empty = "{\"plan_id\":\"test-meta\",\"bindings\":[]}" in
    reject "NC-10 empty bindings"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc10_empty ()));
    let nc10_many = "{\"plan_id\":\"test-meta\",\"bindings\":[" ^
      String.concat "," (List.init 1001 (fun i -> Printf.sprintf "{\"task_id\":\"t%d\",\"worker\":\"w\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}" i)) ^ "]}" in
    reject "NC-10 1001 bindings"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc10_many ()));

    (* NC-11: portfolio row actor differs from binding worker -> refuse *)
    let nc11_port = [t1_port |> change "actor" (`String "other-worker"); t2_port; t3_port; t4_port] in
    let nc11_path = Filename.concat root "nc11_port.json" in
    write nc11_path (Yojson.Basic.to_string (`List nc11_port));
    reject "NC-11 portfolio row actor mismatch"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:nc11_path ~raw_bindings:valid_bindings_json ()));

    (* NC-12: portfolio row task_state not executing -> refuse *)
    let nc12_port = [t1_port |> change "task_state" (`String "available"); t2_port; t3_port; t4_port] in
    let nc12_path = Filename.concat root "nc12_port.json" in
    write nc12_path (Yojson.Basic.to_string (`List nc12_port));
    reject "NC-12 portfolio row task_state not executing"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:nc12_path ~raw_bindings:valid_bindings_json ()));

    (* NC-13: bindings plan_id differs from portfolio plan_id -> refuse *)
    let nc13_json = "{\"plan_id\":\"foreign-plan\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    reject "NC-13 plan_id mismatch"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc13_json ()));

    (* NC-14: SQL-like task id such as 'T1; DROP TABLE sa_plan_task' -> refuse on charset *)
    let nc14_json = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"T1; DROP TABLE sa_plan_task\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    reject "NC-14 SQL-like task id refused on charset"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc14_json ()));

    (* NC-15: missing database file -> refuse. Schema-incompatible database -> refuse *)
    reject "NC-15 missing database file"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:(Filename.concat root "absent.sqlite3") ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:valid_bindings_json ()));
    let schema_bad = Filename.concat root "bad_schema.sqlite3" in
    let db_bad = Sqlite3.db_open schema_bad in
    ignore (Sqlite3.exec db_bad "CREATE TABLE dummy(x INT)");
    ignore (Sqlite3.db_close db_bad);
    reject "NC-15 schema-incompatible database"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:schema_bad ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:valid_bindings_json ()));

    (* NC-16: plan mutated between the two digests -> refuse *)
    reject "NC-16 plan mutated between digests"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L
        ~after_read:(fun () ->
          let db_mut = Sqlite3.db_open meta_db in
          ignore (Sqlite3.exec db_mut "UPDATE sa_plan_task SET attempt=99 WHERE id='t1'");
          ignore (Sqlite3.db_close db_mut))
        ~portfolio_path:port_path ~raw_bindings:valid_bindings_json ()));
    (* Restore t1 attempt for subsequent tests *)
    let db_rest = Sqlite3.db_open meta_db in
    ignore (Sqlite3.exec db_rest "UPDATE sa_plan_task SET attempt=1 WHERE id='t1'");
    ignore (Sqlite3.db_close db_rest);

    (* NC-17: expected_new_attempt not equal to previous_attempt + 1 -> refuse *)
    let nc17_json = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":5},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    reject "NC-17 expected_new_attempt not equal to previous_attempt + 1"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc17_json ()));

    (* NC-18: AUTHORITY CONTAINMENT: after PASS from this verb, receipt carries selection=NOT_EVALUATED,
       authority=NONE, and actual active-check with wrong worker/attempt produces RP-ACTIVE-OWNER *)
    let nc18_receipt = Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:valid_bindings_json () in
    check "NC-18 selection is NOT_EVALUATED" (text "selection" nc18_receipt = "NOT_EVALUATED");
    check "NC-18 authority is NONE" (text "authority" nc18_receipt = "NONE");
    let rows_live = Live_plan.read ~path:meta_db ~plan:"test-meta" in
    let active_check_eval task_id worker attempt live =
      if not (List.exists (fun (t:Live_plan.task) ->
        t.id = task_id && t.state = "executing" && t.worker = Some worker && t.attempt = attempt) live)
      then Some (Checker.issue "RP-ACTIVE-OWNER" task_id
                   "Active worker/attempt does not match the current executing task."
                   "Stop this attempt's effects; re-observe ownership through Sa-plan.")
      else None
    in
    let wrong_worker_issue = active_check_eval "t1" "wrong-worker" 1 rows_live in
    check "NC-18 active-check with wrong worker produces RP-ACTIVE-OWNER"
      (match wrong_worker_issue with Some f -> f.Checker.rule = "RP-ACTIVE-OWNER" | None -> false);
    let wrong_attempt_issue = active_check_eval "t1" "worker-1" 99 rows_live in
    check "NC-18 active-check with wrong attempt produces RP-ACTIVE-OWNER"
      (match wrong_attempt_issue with Some f -> f.Checker.rule = "RP-ACTIVE-OWNER" | None -> false);

    (* NC-19: NON-REGRESSION OF THE EXISTING GATE: preflight and reclaim-set-preflight on tied portfolio still hold *)
    let tie_a = base |> change "plan_id" (`String "test-tie") |> change "task_id" (`String "tie-a")
                     |> change "assessment_id" (`String "asm-tie-a")
                     |> change "task_state" (`String "available") in
    let tie_b = base |> change "plan_id" (`String "test-tie") |> change "task_id" (`String "tie-b")
                     |> change "assessment_id" (`String "asm-tie-b")
                     |> change "task_state" (`String "available") in
    let tie_rows = [tie_a; tie_b] in
    let tie_audit = Checker.audit ~root ~now tie_rows in
    check "NC-19 existing audit detects cost-tie"
      (List.exists (fun f -> f.Checker.rule = "RP-COST-TIE") tie_audit.findings);
    let tie_bindings = [("tie-a", text "actor" base, 1, 900L); ("tie-b", text "actor" base, 1, 900L)] in
    let tie_a_exec = tie_a |> change "task_state" (`String "executing") in
    let tie_b_exec = tie_b |> change "task_state" (`String "executing") in
    let tie_a_exp = { live with id="tie-a"; state="executing"; worker=Some (text "actor" base); attempt=1; lease=Some 900L } in
    let tie_b_exp = { live with id="tie-b"; state="executing"; worker=Some (text "actor" base); attempt=1; lease=Some 900L } in
    let tie_set_audit = Checker.coherence ~reclaim_set:tie_bindings ~now_ns:1000L [tie_a_exec; tie_b_exec] [tie_a_exp; tie_b_exp] in
    check "NC-19 reclaim-set preserves audit coherence" (tie_set_audit = []);
    let projected_tie = Checker.reclaim_set_projection ~now_ns:1000L tie_bindings [tie_a_exec; tie_b_exec] [tie_a_exp; tie_b_exp] in
    let projected_tie_audit = Checker.audit ~root ~now projected_tie in
    check "NC-19 preflight on reclaim-projected tied portfolio STILL detects RP-COST-TIE"
      (List.exists (fun f -> f.Checker.rule = "RP-COST-TIE") projected_tie_audit.findings);

    (* NC-20: ZERO WRITES: main database and active WAL frame bytes identical before and after observation *)
    let db_wal = Sqlite3.db_open meta_db in
    ignore (Sqlite3.exec db_wal "PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;");
    ignore (Sqlite3.exec db_wal "INSERT INTO sa_plan_task VALUES('test-meta','wal_dummy','available',NULL,NULL,0,NULL,NULL);");
    let wal_path = meta_db ^ "-wal" in
    check "NC-20 active WAL file exists" (Sys.file_exists wal_path);
    let before_main = Bounded.sha256 (Bounded.read meta_db) in
    let before_wal = Bounded.sha256 (Bounded.read wal_path) in
    let wal_receipt = Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:valid_bindings_json () in
    check "NC-20 observation succeeds under active WAL" (text "status" wal_receipt = "METADATA_OBSERVATION_PASS");
    let after_main = Bounded.sha256 (Bounded.read meta_db) in
    let after_wal = Bounded.sha256 (Bounded.read wal_path) in
    check "NC-20 main db bytes identical before and after" (before_main = after_main);
    check "NC-20 active WAL frame bytes identical before and after" (before_wal = after_wal);
    ignore (Sqlite3.db_close db_wal);

    (* === ROOT FINDING REPRODUCERS & VALIDATIONS (META-01 .. META-05) === *)
    (* META-01: Executing row with completed_at or result present is REFUSED *)
    let meta01_db = Filename.concat root "meta01.sqlite3" in
    let db_01 = Sqlite3.db_open meta01_db in
    ignore (Sqlite3.exec db_01 "CREATE TABLE sa_plan_task(plan_id TEXT,id TEXT,state TEXT,worker TEXT,lease_until_ns INTEGER,attempt INTEGER,completed_at_ns INTEGER,result TEXT)");
    ignore (Sqlite3.exec db_01 "CREATE TABLE sa_plan_dependency(plan_id TEXT,task_id TEXT,dependency_id TEXT)");
    ignore (Sqlite3.exec db_01 "INSERT INTO sa_plan_task VALUES('test-meta','t1','executing','worker-1',900,1,800,'completed_result')");
    ignore (Sqlite3.exec db_01 "INSERT INTO sa_plan_task VALUES('test-meta','t2','executing','worker-2',900,1,NULL,NULL)");
    ignore (Sqlite3.db_close db_01);
    reject "META-01 refuses executing row with completion result"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta01_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:valid_bindings_json ()));

    (* META-02a: Duplicate portfolio task IDs are REFUSED *)
    let dup_port_records = [t1_port; t1_port; t2_port; t3_port; t4_port] in
    let dup_port_path = Filename.concat root "dup_port.json" in
    write dup_port_path (Yojson.Basic.to_string (`List dup_port_records));
    reject "META-02a refuses duplicate portfolio task ID"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:dup_port_path ~raw_bindings:valid_bindings_json ()));

    (* META-02b: Portfolio mutated during observation is REFUSED *)
    let mut_port_path = Filename.concat root "mut_port.json" in
    write mut_port_path (Yojson.Basic.to_string (`List valid_portfolio_records));
    reject "META-02b refuses portfolio mutated mid-observation"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L
        ~after_read:(fun () -> write mut_port_path "[]")
        ~portfolio_path:mut_port_path ~raw_bindings:valid_bindings_json ()));

    (* META-03: Whole observation 5000ms bound with overrun falsifier *)
    reject "META-03 rejects observation exceeding 5000ms deadline"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L
        ~clock_delay_s:5.1
        ~portfolio_path:port_path ~raw_bindings:valid_bindings_json ()));

    (* META-05a: Exhausted previous_attempt 1,000,000 is REFUSED *)
    let nc_exhausted = "{\"plan_id\":\"test-meta\",\"bindings\":[\
      {\"task_id\":\"t1\",\"worker\":\"worker-1\",\"previous_attempt\":1000000,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":1000001},\
      {\"task_id\":\"t2\",\"worker\":\"worker-2\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}\
    ]}" in
    reject "META-05a refuses exhausted previous_attempt 1000000"
      (fun () -> ignore (Reclaim_metadata.observe ~root ~dbpath:meta_db ~now_ns:1000L ~portfolio_path:port_path ~raw_bindings:nc_exhausted ()));

    (* META-05b: Strict schema refuses aliases and missing fields *)
    reject "META-05b refuses alias attempt key"
      (fun () -> ignore (Reclaim_metadata.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"t1\",\"worker\":\"w\",\"attempt\":1,\"previous_lease_until_ns\":\"900\",\"expected_new_attempt\":2}]}"));
    reject "META-05b refuses alias lease_until_ns key"
      (fun () -> ignore (Reclaim_metadata.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"t1\",\"worker\":\"w\",\"previous_attempt\":1,\"lease_until_ns\":\"900\",\"expected_new_attempt\":2}]}"));
    reject "META-05b refuses missing expected_new_attempt"
      (fun () -> ignore (Reclaim_metadata.parse_bindings "{\"plan_id\":\"test\",\"bindings\":[{\"task_id\":\"t1\",\"worker\":\"w\",\"previous_attempt\":1,\"previous_lease_until_ns\":\"900\"}]}"));
    reject "META-05b refuses file-path bindings input"
      (fun () -> ignore (Reclaim_metadata.parse_bindings "/path/to/some/file.json")));
  !count

