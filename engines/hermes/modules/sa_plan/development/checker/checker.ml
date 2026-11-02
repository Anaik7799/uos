(* Deterministic evidence and decision analysis. Findings veto; nothing authorizes effects. *)
open Priority
open Record
type finding = {rule:string; task:string; detail:string; next_check:string}
type report = {ranked:ranked list; findings:finding list; evidence:(string*string) list}
let issue rule task detail next_check = {rule;task;detail;next_check}
let findings_json xs = `List (List.map (fun f->`Assoc [
  "rule",`String f.rule;"task_id",`String f.task;"severity",`String "HOLD";
  "detail",`String f.detail;"next_check",`String f.next_check]) xs)
let assert_distinct label xs =
  require (List.length xs=List.length (List.sort_uniq String.compare xs)) ("duplicate "^label)
let lifetime j=match text "phase" j with "incident"->900 | "release"->3600 | _->86400
let reference r =
  match String.rindex_opt r ':' with
  | None -> r,None
  | Some i ->
      let path=String.sub r 0 i in
      let line=String.sub r (i+1) (String.length r-i-1) in
      require (line<>"" && String.for_all (fun c->c>='0' && c<='9') line) "invalid evidence line reference";
      let n=int_of_string line in require (n>0) "nonpositive evidence line";path,Some n
let sensitivity j =
  let fs=field "factors" j in
  let names=["criticality";"stpa";"fmea";"dependency";"impact"] in
  let values=List.map (fun n->nullable_int (field "value" (field n fs))) names in
  let declared=List.map int (arr (field "score_interval" j)) in
  match List.mem None values with
  | true -> List.hd declared,List.nth declared 1
  | false ->
      let values=List.map Option.get values in
      let scenarios=List.concat (List.mapi (fun i v ->
        List.map (fun delta ->
          let altered=List.mapi (fun index n->if i=index then max 1 (min 5 (v+delta)) else n) values in
          score altered) [-1;0;1]) values) in
      List.fold_left min (List.hd declared) scenarios,
      List.fold_left max (List.nth declared 1) scenarios
let analysis ~now records ranked =
  let get id=List.find (fun j->text "task_id" j=id) records in
  let range r kind =
    List.fold_left (fun (lo,hi) id->
      let j=get id in
      let l,h=if kind="sensitivity" then sensitivity j else
        let xs=arr (field "score_interval" j) in int (List.hd xs),int (List.nth xs 1) in
      max lo l,max hi h) (1,1) r.origins in
  let inherited=List.filter_map (fun r->
    let dubious=List.filter (fun id->
      let j=get id in nullable_int (field "score" j)=None ||
      not (fresh ~now ~observed:(text "observed_at" j) ~expires:(text "valid_until" j))) r.origins in
    if dubious=[] then None else Some (issue "RP-INHERITANCE" r.task.id
      ("Urgency depends on uncertain/stale origins: "^String.concat "," dubious)
      "Refresh the consumer assessment; preserve the safety hold while collecting evidence.")) ranked in
  let rec adjacent = function
    | a::(b::_ as rest) ->
        let here=if a.effective_class<>b.effective_class then [] else
          let lo,_=range a "interval" and _,hi=range b "interval" in
          let slow,_=range a "sensitivity" and _,shigh=range b "sensitivity" in
          if a.effective_score=b.effective_score then
            [issue "RP-COST-TIE" a.task.id ("Unresolved equal-score ordering with "^b.task.id)
              "Record comparative benefit and bounded cost; refresh ratings if new evidence discriminates. No automatic cost override is supported."]
          else if lo<=hi || slow<=shigh then
            [issue "RP-SENSITIVITY" a.task.id ("Ordering against "^b.task.id^" is provisional under intervals or one-factor +/-1 scenarios.")
              "Run the cheapest authorized discriminating probe or obtain a separate reviewed selection; this preflight cannot clear the ambiguity."]
          else [] in
        here @ adjacent rest
    | _ -> [] in
  inherited @ adjacent ranked
let audit ~root ~now records =
  require (records<>[] && List.length records<=1000) "portfolio must contain 1..1000 tasks";
  let plans=List.map (text "plan_id") records |> List.sort_uniq String.compare in
  require (List.length plans=1) "portfolio must contain one plan";
  assert_distinct "assessment ID" (List.map (text "assessment_id") records);
  require (List.fold_left (fun n j->n+List.length (arr (field "dependencies" j))) 0 records<=10000)
    "dependency edge budget exceeded";
  let ranked=rank ~now (List.map candidate records) in
  let findings=ref [] in
  let add f=if List.length !findings<255 then findings:=f::!findings
    else if List.length !findings=255 then findings:=issue "RP-OUTPUT-BOUND" ""
      "Further findings omitted; preflight remains held." "Reduce the plan's diagnostic scope."::!findings in
  let capture rule id next f =
    try f () with
    | Invalid detail -> add (issue rule id detail next)
    | Sys_error _ | Unix.Unix_error _ -> add (issue rule id "Evidence is inaccessible or changed." next) in
  let cache=Hashtbl.create 32 and bytes=ref 0 in
  let evidence path =
    match Hashtbl.find_opt cache path with
    | Some v->v
    | None->
        require (Hashtbl.length cache<256) "evidence file count exceeds 256";
        let content=Bounded.evidence ~root path in
        bytes:= !bytes+String.length content;
        require (!bytes<=16777216) "evidence total exceeds 16 MiB";
        let v=Bounded.sha256 content,content in Hashtbl.add cache path v;v in
  List.iter (fun j->
    let id=text "task_id" j in
    capture "RP-TIME" id "Re-observe this assessment using synchronized host time." (fun ()->
      require (fresh ~now ~observed:(text "observed_at" j) ~expires:(text "valid_until" j)) "stale/future assessment";
      require (text "ready_since" j<=now) "ready time is in the future");
    capture "RP-ANALYSIS" id "Resolve the contradictory/missing analysis fields." (fun ()->
      assert_distinct "FMEA mode ID" (List.map (text "id") (arr (field "fmea_modes" j)));
      let stpa=field "stpa_analysis" j in
      assert_distinct "hazard ID" (List.map str (arr (field "hazards" stpa)));
      assert_distinct "loss ID" (List.map str (arr (field "losses" stpa)));
      if field "value" (field "stpa" (field "factors" j))=`Int 1 then
        require (List.for_all (fun u->text "applicability" u="not_applicable") (arr (field "ucas" stpa)))
          "T=1 contradicts an applicable UCA");
    let snapshot=field "snapshot" j in
    let evs=arr (field "evidence" snapshot) in
    capture "RP-SNAPSHOT" id "Use a working-tree packet; runtime/revision claims require their own verified adapter." (fun ()->
      require (text "kind" snapshot="working_tree") "only listed working-tree bytes can be checked here";
      require (List.length evs<=256) "too many evidence references";
      assert_distinct "evidence path" (List.map (text "path") evs));
    List.iter (fun ev->
      capture "RP-EVIDENCE" id "Re-observe sanitized source bytes and bind their current SHA-256 digest." (fun ()->
        let path=text "path" ev and observed=text "observed_at" ev in
        require (observed<=text "observed_at" j && utc_seconds now-utc_seconds observed<=lifetime j)
          "evidence predates the freshness window or postdates the assessment";
        let digest,_=evidence path in
        require (digest=text "sha256" ev) ("SHA-256 mismatch: "^path))) evs;
    List.iter (fun (name,f)->
      capture "RP-REFERENCE" id "Bind every factor source to a listed evidence digest and valid line." (fun ()->
        let refs=List.map str (arr (field "evidence_refs" f)) in
        assert_distinct ("factor reference "^name) refs;
        List.iter (fun r->
          let path,line=reference r in
          require (List.exists (fun ev->text "path" ev=path) evs) ("unbound factor reference: "^r);
          let _,contents=evidence path in
          Option.iter (fun n->
            let lines=1+String.fold_left (fun count c->if c='\n' then count+1 else count) 0 contents in
            require (n<=lines) "evidence line exceeds file") line) refs))
      (obj (field "factors" j))) records;
  List.iter add (analysis ~now records ranked);
  let evidence=Hashtbl.fold (fun path (digest,_) acc->(path,digest)::acc) cache []
    |> List.sort compare in
  {ranked;findings=List.rev !findings;evidence}
(* Read-only reclaim observation. This never creates a lease or makes an
   expired attempt executable. The exact previous worker/attempt/deadline must
   still match; ordinary preflight/active checks retain their strict behavior. *)
let reclaim_matches ~now_ns (id,worker,attempt,lease) (t:Live_plan.task) =
  id=t.id && worker<>"" && t.state="executing" && t.worker=Some worker &&
  attempt>=1 && attempt<1000000 && t.attempt=attempt &&
  lease>0L && lease<=now_ns && t.lease=Some lease &&
  t.completed=None && not t.result_present
let reclaim_projection ~now_ns binding records live =
  let id,worker,_,_=binding in
  require (List.exists (reclaim_matches ~now_ns binding) live)
    "reclaim requires exact expired same-worker attempt and lease";
  require (List.exists (fun j->text "task_id" j=id &&
    text "task_state" j="executing" && text "actor" j=worker) records)
    "reclaim assessment must declare the original executing owner";
  List.map (fun j->if text "task_id" j<>id then j else
    match j with `Assoc xs -> `Assoc (List.map (fun(k,v)->
      k,(if k="task_state" then `String "available" else v)) xs)
    | _ -> raise (Invalid "invalid reclaim record")) records
let reclaim_set_projection ~now_ns bindings records live =
  require (bindings <> []) "reclaim set cannot be empty";
  require (List.length bindings <= 1000) "reclaim set exceeds bound";
  let ids = List.map (fun (id,_,_,_) -> id) bindings in
  require (List.length ids = List.length (List.sort_uniq String.compare ids))
    "reclaim set contains duplicate task IDs";
  let expired_executing = List.filter (fun (t : Live_plan.task) ->
    t.state = "executing" &&
    Option.fold ~none:true ~some:(fun lease -> lease <= now_ns) t.lease) live
  in
  let expired_ids = List.map (fun (t : Live_plan.task) -> t.id) expired_executing |> List.sort String.compare in
  let binding_ids = List.sort String.compare ids in
  require (binding_ids = expired_ids)
    "reclaim set must exactly equal all expired executing tasks in observed plan";
  List.iter (fun binding ->
    let id, worker, _, _ = binding in
    require (List.exists (reclaim_matches ~now_ns binding) live)
      ("reclaim requires exact expired same-worker attempt and lease: " ^ id);
    require (List.exists (fun j -> text "task_id" j = id &&
      text "task_state" j = "executing" && text "actor" j = worker) records)
      ("reclaim assessment must declare the original executing owner: " ^ id)) bindings;
  List.map (fun j ->
    let id = text "task_id" j in
    if not (List.mem id ids) then j
    else match j with `Assoc xs -> `Assoc (List.map (fun (k,v) ->
      k, (if k = "task_state" then `String "available" else v)) xs)
    | _ -> raise (Invalid "invalid reclaim record")) records
let require_selected_in_set selected bindings =
  let ids = List.map (fun (id, _, _, _) -> id) bindings in
  require (List.mem selected ids) "selected task must be a member of reclaim bindings set"
let parse_bindings raw =
  let v =
    try Bounded.json_text raw
    with Invalid msg -> raise (Invalid msg)
    | e -> raise (Invalid ("malformed JSON in bindings: " ^ Printexc.to_string e))
  in
  unique v;
  let fields =
    match v with
    | `Assoc fs -> fs
    | _ -> raise (Invalid "reclaim payload must be a JSON object with plan_id and bindings")
  in
  let keys = List.map fst fields |> List.sort String.compare in
  require (keys = ["bindings"; "plan_id"])
    "reclaim payload must contain exactly {plan_id, bindings} with no unknown or alias fields";
  let plan_id =
    match List.assoc "plan_id" fields with
    | `String s -> s
    | _ -> raise (Invalid "plan_id must be a string")
  in
  require (String.trim plan_id <> "") "plan_id cannot be empty";
  let items =
    match List.assoc "bindings" fields with
    | `List is -> is
    | _ -> raise (Invalid "bindings must be a JSON array")
  in
  require (items <> []) "reclaim bindings list cannot be empty";
  require (List.length items <= 1000) "reclaim bindings list exceeds bound";
  let bindings = List.map (fun item ->
    unique item;
    let item_fields =
      match item with
      | `Assoc fs -> fs
      | _ -> raise (Invalid "reclaim binding must be a JSON object")
    in
    let item_keys = List.map fst item_fields |> List.sort String.compare in
    require (item_keys = ["attempt"; "lease_until_ns"; "task_id"; "worker"])
      "reclaim binding must contain exactly {task_id, worker, attempt, lease_until_ns} with no unknown or alias fields";
    let task =
      match List.assoc "task_id" item_fields with
      | `String s -> s
      | _ -> raise (Invalid "task_id must be a string")
    in
    require (String.trim task <> "") "task_id cannot be empty";
    let worker =
      match List.assoc "worker" item_fields with
      | `String s -> s
      | _ -> raise (Invalid "worker must be a string")
    in
    require (String.trim worker <> "") "worker cannot be empty";
    let attempt =
      match List.assoc "attempt" item_fields with
      | `Int n -> n
      | _ -> raise (Invalid "attempt must be an integer")
    in
    require (attempt >= 1 && attempt < 1000000) "invalid reclaim attempt";
    let lease_str =
      match List.assoc "lease_until_ns" item_fields with
      | `String s -> s
      | `Int _ | `Float _ -> raise (Invalid "lease_until_ns must be a decimal string, not a number")
      | _ -> raise (Invalid "lease_until_ns must be a decimal string")
    in
    require (String.length lease_str > 0 && String.length lease_str <= 20) "invalid lease_until_ns length";
    require (String.for_all (fun c -> c >= '0' && c <= '9') lease_str) "lease_until_ns must be decimal digits";
    let lease =
      try
        let l = Int64.of_string lease_str in
        require (l > 0L) "lease_until_ns must be positive";
        l
      with _ -> raise (Invalid "lease_until_ns overflow or non-decimal")
    in
    (task, worker, attempt, lease)
  ) items in
  let ids = List.map (fun (id, _, _, _) -> id) bindings in
  require (List.length ids = List.length (List.sort_uniq String.compare ids))
    "reclaim bindings contain duplicate task IDs";
  (plan_id, bindings)
let parse_bindings_with_plan = parse_bindings
let coherence ?reclaim ?reclaim_set ~now_ns records live =
  let out=ref [] in
  let add id detail=out:=issue "RP-SA-PLAN" id detail
    "Re-read the canonical plan and refresh its complete assessment; claim only through Sa-plan."::!out in
  let declared=List.map (text "task_id") records |> List.sort String.compare in
  let actual=List.map (fun (t:Live_plan.task)->t.id) live |> List.sort String.compare in
  if declared<>actual then add "" "Portfolio omits/adds canonical plan tasks; full-plan ordering is required.";
  List.iter (fun j->
    let id=text "task_id" j in
    match List.find_opt (fun (t:Live_plan.task)->t.id=id) live with
    | None->add id "task is absent from Sa-plan"
    | Some t->
        if t.state<>text "task_state" j then add id "declared task state differs from Sa-plan";
        if List.sort String.compare t.dependencies<>
          List.sort String.compare (List.map str (arr (field "dependencies" j)))
        then add id "declared dependencies differ from Sa-plan";
        if t.state="executing" then (
          if t.worker<>Some (text "actor" j) then add id "executing worker does not match assessment actor";
          let exact_reclaim =
            match reclaim with
            | Some binding -> reclaim_matches ~now_ns binding t
            | None ->
                match reclaim_set with
                | Some bindings -> List.exists (fun b -> reclaim_matches ~now_ns b t) bindings
                | None -> false
          in
          if not exact_reclaim &&
            (t.attempt<1 || not (Option.fold ~none:false ~some:(fun n->n>now_ns) t.lease))
          then add id "executing lease is missing or expired at this observation")
        else if t.state="available" && (t.worker<>None || t.lease<>None) then
          add id "available task retains inconsistent ownership";
        if t.state="completed" &&
          (not t.result_present || not (Option.fold ~none:false ~some:(fun n->n>0L && n<=now_ns) t.completed))
        then add id "completed task lacks a valid completion record") records;
  Option.iter (fun binding->
    if not (List.exists (reclaim_matches ~now_ns binding) live) then
      let id,_,_,_=binding in add id "reclaim binding changed or is not an expired owned attempt") reclaim;
  Option.iter (fun bindings->
    let expired_executing = List.filter (fun (t:Live_plan.task)->
      t.state="executing" && Option.fold ~none:true ~some:(fun lease->lease<=now_ns) t.lease) live in
    let expired_ids = List.map (fun (t:Live_plan.task)->t.id) expired_executing |> List.sort String.compare in
    let binding_ids = List.map (fun (id,_,_,_)->id) bindings |> List.sort_uniq String.compare in
    if List.length bindings <> List.length binding_ids then
      add "" "reclaim set contains duplicate task IDs";
    if binding_ids <> expired_ids then
      add "" "reclaim set must exactly equal all expired executing tasks in observed plan";
    List.iter (fun binding->
      if not (List.exists (reclaim_matches ~now_ns binding) live) then
        let id,_,_,_=binding in add id "reclaim binding changed or is not an expired owned attempt") bindings) reclaim_set;
  List.rev !out
let verify_again ~root evidence =
  List.iter (fun (path,digest)->
    require (Bounded.sha256 (Bounded.evidence ~root path)=digest) ("source changed during preflight: "^path)) evidence
let final_time_findings ~now records =
  List.filter_map (fun j->
    let expired=not (fresh ~now ~observed:(text "observed_at" j) ~expires:(text "valid_until" j)) ||
      List.exists (fun ev->utc_seconds now-utc_seconds (text "observed_at" ev)>lifetime j)
        (arr (field "evidence" (field "snapshot" j))) in
    if not expired then None else Some (issue "RP-TIME-END" (text "task_id" j)
      "Assessment or source evidence expired during checks." "Refresh evidence before selection.")) records
let order_json ranked = `List (List.map (fun (r:ranked)->`Assoc [
  "task_id",`String r.task.id;"effective_class",`String ("P"^string_of_int r.effective_class);
  "effective_score",`Int r.effective_score;
  "origins",`List (List.map (fun s->`String s) r.origins)]) ranked)
