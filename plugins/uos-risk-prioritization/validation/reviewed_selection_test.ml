open Priority
open Record
let run () =
  let count=ref 0 in
  let check name value=incr count;require value ("selection test: "^name) in
  let reject name f=check name (try ignore(f());false with Invalid _->true) in
  let now="2026-10-25T01:00:00Z" in
  let base=sample() |> change "actor" (`String "producer")
    |> change "plan_id" (`String "test/selection")
    |> change "task_state" (`String "available") |> change "readiness" (`String "ready")
    |> change "dependencies" (`List []) |> change "blockers" (`List [])
    |> change "observed_at" (`String now)
    |> change "valid_until" (`String "2026-10-25T01:30:00Z")
    |> change "ready_since" (`String now) in
  let records=List.map(fun id->change "task_id" (`String id) base) ["A";"B"] in
  let ranked=rank ~now (List.map candidate records) in
  let findings=Checker.analysis ~now records ranked in
  let report:Checker.report={ranked;findings;evidence=[]} in
  check "real unmodified checker emits tie" (List.exists(fun(f:Checker.finding)->f.rule="RP-COST-TIE") findings);
  let raw=Yojson.Basic.to_string(`List records) in
  let cost id=`Assoc["task_id",`String id;"benefit",`String "bounded ready workflow";
    "cost_bound_seconds",`Int 120;"basis",`String "analyst bound, not measured forecast"] in
  let review=`Assoc["schema",`String "uos.reviewed-tie-selection.v1";
    "plan_id",`String "test/selection";"portfolio_sha256",`String(Bounded.sha256 raw);
    "selected_task",`String "B";"tied_tasks",`List[`String "A";`String "B"];
    "observed_at",`String now;"valid_until",`String "2026-10-25T01:30:00Z";
    "reviewer",`String "agy-independent-reviewer";"reason",`String "B reuses accepted adapters";
    "comparisons",`List[cost "A";cost "B"];
    "review_evidence_path",`String "governance/planning/test-review.json";
    "review_evidence_sha256",`String(String.make 64 '0')] in
  let seal r =
    let verdict=`Assoc["verdict",`String "APPROVE";
      "proposal_sha256",`String(Bounded.sha256(Reviewed_selection.proposal r));
      "reason",`String "bounded comparative choice";"reviewer",field "reviewer" r] in
    let proof=Yojson.Basic.to_string(`Assoc["status",`String "SUCCESS";
      "conversation_id",`String "independent";
      "response",`String(Yojson.Basic.to_string verdict)]) in
    change "review_evidence_sha256" (`String(Bounded.sha256 proof)) r,proof in
  let review,proof=seal review in
  let apply ?(time=now) ?(input=raw) ?(rs=records) ?(rep=report) ?(task="B") ?(evidence=proof) r =
    Reviewed_selection.apply ~now:time ~raw:input ~records:rs ~selected:task
      ~report:rep ~review:r ~proof:evidence in
  let accepted=apply review in
  check "review chooses B, no score changes" (List.map(fun(r:ranked)->r.task.id) accepted.ranked=["B";"A"] &&
    List.map(fun(r:ranked)->r.effective_score) accepted.ranked=List.map(fun(r:ranked)->r.effective_score) ranked &&
    accepted.findings=[] && accepted.evidence=report.evidence);
  reject "changed portfolio" (fun()->apply ~input:(raw^" ") review);
  reject "changed requested task" (fun()->apply ~task:"A" review);
  reject "changed decision lacks approval" (fun()->apply(change "reason" (`String "other") review));
  reject "future" (fun()->apply ~time:"2026-10-25T00:59:59Z" review);
  reject "expiry boundary" (fun()->apply ~time:"2026-10-25T01:30:00Z" review);
  reject "too long lifetime" (fun()->let r,p=seal(change "valid_until" (`String "2026-10-25T02:00:01Z") review) in apply ~evidence:p r);
  reject "wrong plan" (fun()->let r,p=seal(change "plan_id" (`String "other/plan") review) in apply ~evidence:p r);
  reject "self review" (fun()->apply ~rs:(List.map(change "actor" (`String "agy-independent-reviewer")) records) review);
  reject "proof mismatch" (fun()->apply ~evidence:(proof^" ") review);
  reject "reviewer mismatch" (fun()->apply(change "reviewer" (`String "agy:another") review));
  reject "unknown field" (fun()->apply(`Assoc(("force",`Bool true)::obj review)));
  reject "duplicate field" (fun()->apply(`Assoc(("plan_id",field "plan_id" review)::obj review)));
  List.iter(fun(name,ids)->reject name(fun()->let r,p=seal(change "tied_tasks" (`List(List.map(fun s->`String s) ids)) review) in apply ~evidence:p r))
    ["missing member",["B"];"duplicate member",["A";"B";"B"];"extra member",["A";"B";"C"];"unsorted",["B";"A"]];
  reject "cost denominator" (fun()->let r,p=seal(change "comparisons" (`List[cost "A"]) review) in apply ~evidence:p r);
  reject "cost duplicate" (fun()->let r,p=seal(change "comparisons" (`List[cost "A";cost "A"]) review) in apply ~evidence:p r);
  reject "cost bounds" (fun()->let r,p=seal(change "comparisons" (`List[cost "A";change "cost_bound_seconds" (`Int 0) (cost "B")]) review) in apply ~evidence:p r);
  let first=List.hd ranked in
  let higher={first with task={first.task with id="C"};effective_score=first.effective_score+1} in
  reject "higher priority prevents tie choice" (fun()->apply ~rep:{report with ranked=higher::ranked} review);
  let urgent={higher with effective_class=0} in
  reject "higher safety class prevents tie choice" (fun()->apply ~rep:{report with ranked=urgent::ranked} review);
  reject "single eligible candidate" (fun()->apply ~rep:{report with ranked=[first]} review);
  List.iter(fun rule->
    let other=Checker.issue rule "A" "unresolved" "repair" in
    let r=apply ~rep:{report with findings=other::findings} review in
    check ("retains "^rule) (r.findings=[other]))
    ["RP-EVIDENCE";"RP-SENSITIVITY";"RP-INHERITANCE";"RP-TIME";"RP-COST-TIE"];
  reject "no matching emitted finding" (fun()->apply ~rep:{report with findings=[]} review);
  let bad_envelope=Bounded.json_text proof |> change "status" (`String "FAILED") |> Yojson.Basic.to_string in
  reject "failed reviewer" (fun()->apply ~evidence:bad_envelope
    (change "review_evidence_sha256" (`String(Bounded.sha256 bad_envelope)) review));
  let bad=Bounded.json_text proof in
  let verdict=Bounded.json_text(text "response" bad) |> change "verdict" (`String "HOLD") in
  let bad=change "response" (`String(Yojson.Basic.to_string verdict)) bad |> Yojson.Basic.to_string in
  reject "HOLD reviewer" (fun()->apply ~evidence:bad
    (change "review_evidence_sha256" (`String(Bounded.sha256 bad)) review));

  let root=Filename.temp_file "uos-selection-" "" in
  Sys.remove root;Unix.mkdir root 0o700;
  let rp=Filename.concat root "review.json" and pp=Filename.concat root "proof.json" in
  let write p s=let o=open_out_bin p in Fun.protect ~finally:(fun()->close_out o) (fun()->output_string o s) in
  let rb=Yojson.Basic.to_string review in
  Fun.protect ~finally:(fun()->List.iter(fun p->try Sys.remove p with _->()) [rp;pp];Unix.rmdir root) (fun()->
    write rp rb;write pp proof;
    let verify time=Reviewed_selection.verify_again ~root ~now:time ~review_path:"review.json"
      ~review_bytes:rb ~proof_path:"proof.json" ~proof_bytes:proof ~review in
    verify now;check "end evidence initially matches" true;
    write rp (rb^" ");
    reject "end review bytes change" (fun()->verify now);write rp rb;
    write pp (proof^" ");
    reject "end proof bytes change" (fun()->verify now);write pp proof;
    reject "review expires during observation" (fun()->verify "2026-10-25T01:30:00Z");
    Sys.remove pp;Unix.symlink rp pp;
    reject "proof symlink rejected" (fun()->verify now));
  !count
