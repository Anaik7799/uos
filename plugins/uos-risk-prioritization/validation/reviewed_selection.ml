(* Reviewed equal-score choice; report-only, never claim or effect authority. *)
open Priority
open Record
let keys j expected =
  unique j;
  require (List.sort String.compare (List.map fst (obj j)) =
    List.sort String.compare expected) "selection review fields differ"
let bounded_text key maximum j =
  let s=text key j in
  require (s<>"" && String.trim s=s && String.length s<=maximum &&
    String.for_all (fun c->Char.code c>=32 && Char.code c<>127) s)
    ("invalid review text: "^key); s
let group ranked =
  match ranked with
  | [] -> raise (Invalid "no eligible selection candidates")
  | first::_ -> List.filter (fun (r:ranked)->
      r.effective_class=first.effective_class &&
      r.effective_score=first.effective_score) ranked
let proposal review =
  (* Fixed canonical key order; proof and evidence path are excluded, avoiding
     circular hashing. All decision-bearing fields are covered. *)
  let names=["schema";"plan_id";"portfolio_sha256";"selected_task";"tied_tasks";
    "observed_at";"valid_until";"reviewer";"reason";"comparisons"] in
  Yojson.Basic.to_string (`Assoc(List.map(fun k->k,field k review) names))
let check_time ~now review =
  let observed=text "observed_at" review and expires=text "valid_until" review in
  require (fresh ~now ~observed ~expires) "selection review stale or future";
  require (utc_seconds expires - utc_seconds observed <= 3600)
    "selection review lifetime exceeds one hour"
let apply ~now ~raw ~records ~selected ~(report:Checker.report) ~review ~proof =
  keys review ["schema";"plan_id";"portfolio_sha256";"selected_task";"tied_tasks";
    "observed_at";"valid_until";"reviewer";"reason";"comparisons";
    "review_evidence_path";"review_evidence_sha256"];
  require (text "schema" review="uos.reviewed-tie-selection.v1") "selection review schema";
  check_time ~now review;
  let digest=text "portfolio_sha256" review in
  require (hex64 digest && digest=Bounded.sha256 raw) "selection portfolio changed";
  let plan=text "plan_id" (List.hd records) in
  require (text "plan_id" review=plan &&
    List.for_all(fun r->text "plan_id" r=plan) records) "selection plan differs";
  require (text "selected_task" review=selected) "selection requested task differs";
  let tied=group report.ranked in
  require (List.length tied>=2) "selection requires a top eligible tie";
  let ids=List.map(fun (r:ranked)->r.task.id) tied |> List.sort String.compare in
  let declared=List.map str (arr(field "tied_tasks" review)) in
  require (List.length declared<=1000 && declared=List.sort_uniq String.compare declared &&
    declared=ids && List.mem selected ids) "selection tie group differs";
  let reviewer=bounded_text "reviewer" 160 review in
  require (List.for_all(fun r->text "actor" r<>reviewer) records)
    "selection reviewer is an assessment actor";
  ignore(bounded_text "reason" 2048 review);
  let costs=arr(field "comparisons" review) in
  require (List.length costs=List.length ids) "selection cost denominator differs";
  let cost_ids=List.map(fun row->
    keys row ["task_id";"benefit";"cost_bound_seconds";"basis"];
    let id=bounded_text "task_id" 160 row in
    ignore(bounded_text "benefit" 1024 row);
    ignore(bounded_text "basis" 1024 row);
    let seconds=int(field "cost_bound_seconds" row) in
    require(seconds>=1 && seconds<=86400) "selection cost bound outside 1..86400";
    id) costs in
  require (List.sort String.compare cost_ids=ids) "selection cost group differs";
  require (hex64(text "review_evidence_sha256" review) &&
    Bounded.sha256 proof=text "review_evidence_sha256" review) "selection proof bytes differ";
  let envelope=Bounded.json_text proof in unique envelope;
  require(text "status" envelope="SUCCESS") "selection reviewer response incomplete";
  let conversation=bounded_text "conversation_id" 160 envelope in
  require(reviewer="agy:"^conversation) "selection reviewer differs from evidence";
  let verdict=Bounded.json_text(text "response" envelope) in
  keys verdict ["verdict";"proposal_sha256";"reason"];
  require(text "verdict" verdict="APPROVE" &&
    text "proposal_sha256" verdict=Bounded.sha256(proposal review))
    "selection review does not approve this exact proposal";
  ignore(bounded_text "reason" 2048 verdict);
  (* Only exact findings emitted for adjacent members of this top group may
     be discharged. A different tie, source or sensitivity finding survives. *)
  let rec tie_findings = function
    | a::(b::_ as tail) ->
        Checker.issue "RP-COST-TIE" a.task.id
          ("Unresolved equal-score ordering with "^b.task.id)
          "Record comparative benefit and bounded cost; refresh ratings if new evidence discriminates. No automatic cost override is supported."
        ::tie_findings tail
    | _ -> [] in
  let expected=tie_findings tied in
  require(List.for_all(fun f->List.mem f report.findings) expected)
    "selection does not match computed tie findings";
  let findings=List.filter(fun f->not(List.mem f expected)) report.findings in
  let chosen=List.find(fun (r:ranked)->r.task.id=selected) report.ranked in
  {report with ranked=chosen::List.filter(fun (r:ranked)->r.task.id<>selected) report.ranked;
    findings}

let verify_again ~root ~now ~review_path ~review_bytes ~proof_path ~proof_bytes ~review =
  require(Bounded.evidence ~root review_path=review_bytes &&
    Bounded.evidence ~root proof_path=proof_bytes)
    "selection review or proof changed during preflight";
  check_time ~now review
