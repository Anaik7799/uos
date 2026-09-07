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
    reject "SQL injection remains bound text" (fun ()->ignore (Live_plan.read ~path:dbpath ~plan:"test' OR 1=1 --"));
    let absent=Filename.concat root "absent.sqlite3" in
    check "missing DB not created" (try ignore (Live_plan.read ~path:absent ~plan:"test");false
      with Unix.Unix_error _ -> not (Sys.file_exists absent)));
  !count
