open Priority
open Record
let selftest () =
  let count=ref (Priority.selftest ()) in
  let check name b=incr count; require b ("record test: " ^ name) in
  let s=schema () and ex=sample () in
  ignore (check_record s ex); incr count;
  let reject name j=check name (try ignore (check_record s j);false with Invalid _->true) in
  reject "forged product" (change "score" (`Int 3125) ex);
  reject "false ready with blocker" (change "blockers" (`List [`String "missing control"]) ex);
  reject "bad timestamp" (change "observed_at" (`String "yesterday") ex);
  reject "expired window" (change "valid_until" (field "observed_at" ex) ex);
  reject "extra privilege flag" (change "approved" (`Bool true) ex);
  let f=field "factors" ex in
  let impact=field "impact" f in
  reject "zero factor" (change "factors" (change "impact" (change "value" (`Int 0) impact) f) ex);
  let snap=field "snapshot" ex in
  let ev=List.hd (arr (field "evidence" snap)) in
  reject "placeholder digest" (change "snapshot"
    (change "evidence" (`List [change "sha256" (`String "authentic_physical_probe") ev]) snap) ex);
  let stpa=field "stpa_analysis" ex in
  reject "missing UCA type" (change "stpa_analysis"
    (change "ucas" (`List (List.tl (arr (field "ucas" stpa)))) stpa) ex);
  reject "duplicate JSON field" (`Assoc (("score",`Int 960)::obj ex));
  let unknown_impact=change "value" `Null (change "low" (`Int 1) (change "high" (`Int 5) impact)) in
  let unknown=change "factors" (change "impact" unknown_impact f) ex
    |> change "score" `Null |> change "score_interval" (`List [`Int 240;`Int 1200]) in
  reject "unknown cannot be ready" unknown;
  ignore (check_record s (change "readiness" (`String "needs_evidence") unknown));
  incr count;
  reject "FMEA severity interval cannot be understated"
    (change "factors" (change "fmea" (change "low" (`Int 1) (field "fmea" f)) f)
      (change "score_interval" (`List [`Int 240;`Int 960]) ex));
  !count
let check_package () =
  let repo=Unix.realpath "." in
  let checked=ref 0 in
  let local path =
    require (Sys.file_exists path) ("missing file: " ^ path);
    let resolved=Unix.realpath path in
    require (String.starts_with ~prefix:(repo ^ "/") resolved) ("external dependency: " ^ path);
    incr checked in
  let docs=[sop;
    "docs/wiki/"^stamp^"-risk-prioritization-guide.md";
    "docs/zk/"^stamp^"-adr-risk-prioritization.md";
    "docs/journal/"^stamp^"-risk-prioritization-journal.md";
    "contracts/rules/20260907-1606-risk-checker-contract.md";
    "docs/wiki/20260907-1606-risk-checkers-guide.md";
    "docs/journal/20260907-1606-risk-checkers-journal.md";
    skill;plugin^"/skills/uos-risk-prioritization/references/"^stamp^"-superpowers-bindings.md"] in
  List.iter (fun path ->
    local path; let content=read path in
    require (contains content "SC-RISK-PRIORITY-001" || contains content "risk-prioritization-sop.md")
      ("missing policy link: "^path);
    for i=1 to 18 do
      require (contains content (Printf.sprintf "CHK-%02d-" i)) ("missing checklist row: "^path)
    done;
    require (contains content "http://nas-1.tail55d152.ts.net:4100/") ("missing FQDN: "^path)) docs;
  List.iter (fun root ->
    let agent=if root="" then "AGENTS.md" else root^"/AGENTS.md" in
    local agent;
    require (contains (read agent) "SC-RISK-PRIORITY-001") ("agent binding missing: "^agent);
    require (contains (read agent) "SC-RISK-CHECK-001" && contains (read agent) "--preflight" &&
      contains (read agent) "--active-check") ("strong checker binding missing: "^agent);
    if root<>"" then (
      let alias=root^"/skills/uos-risk-prioritization/SKILL.md" in
      local alias; require (read alias=read skill) ("skill alias drift: "^alias);
      let rule=root^"/rules/"^stamp^"-risk-prioritization-sop.md" in
      local rule; require (read rule=read sop) ("rule alias drift: "^rule)))
    ["";".codex";".claude";".gemini";".agents"];
  let manifest=plugin^"/.codex-plugin/plugin.json" in
  local manifest; let m=json manifest in
  require (text "name" m="uos-risk-prioritization" && text "version" m="1.1.0") "plugin identity/version";
  require (text "skills" m="./skills/") "plugin skills path";
  require (not (has "mcpServers" m || has "apps" m || has "hooks" m)) "unexpected active plugin capability";
  require (List.for_all (fun (key,_)->List.mem key ["name";"version";"description";"author";"skills";"interface"])
    (obj m)) "unsupported plugin surface";
  require (field "capabilities" (field "interface" m)=`List []) "unexpected plugin capability";
  List.iter local [planning^"-policy.json";planning^"-record.schema.json";planning^"-example.json";
    "governance/agents/policy/"^stamp^"-risk-priority-bindings.toml";"tools/risk-priority-check";
    plugin^"/validation/priority.ml";plugin^"/validation/record.ml";plugin^"/validation/bounded.ml";
    plugin^"/validation/checker.ml";plugin^"/validation/live_plan.ml";plugin^"/validation/host_clock.ml";
    plugin^"/validation/adversarial.ml";plugin^"/validation/validate.ml";plugin^"/validation/dune";plugin^"/validation/dune-project";
    plugin^"/validation/uos-risk-priority-validation.opam"];
  let profile=json (planning^"-policy.json") in
  require (Bounded.sha256 (read (planning^"-policy.json"))="8b3764ea10dff7b9c93232b3938e4dd660f835ba600a4a148fc5458e05283af2")
    "canonical policy drift; update the versioned implementation and tests deliberately";
  require (field "factors" profile=`List (List.map (fun s->`String s)
    ["criticality";"stpa";"fmea";"dependency";"impact"])) "factor profile drift";
  require (field "rpn_maxima" (field "fmea" profile)=`List (List.map (fun n->`Int n) [5;15;35;70;125]))
    "FMEA band profile drift";
  ignore (check_record (schema ()) (sample ()));
  (`Assoc ["status",`String "PASS";"local_paths_checked",`Int !checked;
    "authority",`String "REPORT_ONLY";"runtime_enforcement",`String "NOT_ASSERTED";
    "global_skill_dependency",`Bool false])
let portfolio path =
  let bytes=read path in
  let value=Bounded.json_text bytes in unique value;
  let s=schema () in
  let xs=arr value in require (List.length xs<=1000) "portfolio exceeds bound";
  let records=List.map (check_record s) xs in
  require (records<>[]) "empty portfolio";
  bytes,records
let run_audit ?active path selected =
  ignore (check_package ());
  let timer=Mtime_clock.counter () and wall_start=Unix.gettimeofday () in
  let raw,records=portfolio path in
  let clock=Host_clock.observe () in
  let now=now_utc () in
  let root=Unix.realpath "." in
  let report=Checker.audit ~root ~now records in
  let findings=ref report.findings in
  let live_observation=ref None in
  let live_info=match selected with
    | None -> `String "NOT_CHECKED"
    | Some task_id ->
        let database=Filename.concat root "var/sa-plan/uos.sqlite3" in
        let plan=text "plan_id" (List.hd records) in
        let live=Live_plan.read ~path:database ~plan in
        let ns=Int64.add (Int64.of_float (ceil (Unix.gettimeofday () *. 1e9))) 1024L in
        findings:= !findings @ Checker.coherence ~now_ns:ns records live;
        (match active with
        | Some (worker,attempt) ->
            require (attempt>=1 && attempt<=1000000) "invalid active attempt";
            if not (List.exists (fun (t:Live_plan.task)->t.id=task_id && t.state="executing" &&
              t.worker=Some worker && t.attempt=attempt) live) then
              findings:= !findings @ [Checker.issue "RP-ACTIVE-OWNER" task_id
                "Active worker/attempt does not match the current executing task."
                "Stop this attempt's effects; re-observe ownership through Sa-plan."]
        | None -> (match report.ranked with
            | first::_ when first.task.id=task_id -> ()
            | _ -> findings:= !findings @ [Checker.issue "RP-SELECTION" task_id
                "Requested task is not the first eligible candidate."
                "Refresh the complete plan and investigate blocked or higher-priority work."]));
        Checker.verify_again ~root report.evidence;
        let after=Live_plan.read ~path:database ~plan in
        require (Live_plan.digest live=Live_plan.digest after)
          "Sa-plan changed during preflight; refresh the observation";
        live_observation:=Some after;
        `Assoc ["plan_id",`String plan;"snapshot_sha256",`String (Live_plan.digest live);
          "tasks",`List (List.map Live_plan.to_json live);
          "mode",`String "READONLY";"lease_fencing_authority",`String "NOT_GRANTED"] in
  Checker.verify_again ~root report.evidence;
  require (read path=raw) "input portfolio changed during preflight";
  let clock_end=Host_clock.observe () in
  let ended=now_utc () in
  let final_ns=Int64.add (Int64.of_float (ceil (Unix.gettimeofday () *. 1e9))) 1024L in
  Option.iter (fun live->findings:= !findings @ Checker.coherence ~now_ns:final_ns records live)
    !live_observation;
  findings:= !findings @ Checker.final_time_findings ~now:ended records;
  findings:=List.sort_uniq compare !findings;
  let elapsed=Mtime.Span.to_float_ns (Mtime_clock.count timer) /. 1e9 in
  Host_clock.consistent ~wall_start ~elapsed ~wall_end:(Unix.gettimeofday ());
  let pass= !findings=[] in
  print_json (`Assoc [
    "status",`String (if not pass then "HOLD" else
      if selected=None then "LISTED_EVIDENCE_VALID" else if active=None then "PREFLIGHT_PASS"
      else "ACTIVE_OBSERVATION_PASS");
    "authority",`String "NONE";"runtime_admission",`String "NOT_GRANTED";
    "observed_at",`String now;"completed_at",`String ended;"elapsed_monotonic_seconds",`Float elapsed;
    "clock_start",Host_clock.to_json clock;"clock_end",Host_clock.to_json clock_end;
    "assessment_sha256",`String (Bounded.sha256 raw);
    "evidence_files_checked",`Int (List.length report.evidence);
    "sa_plan",live_info;"order",Checker.order_json report.ranked;
    "findings",Checker.findings_json !findings;
    "limits",`List (List.map (fun s->`String s) [
      "Listed byte equality does not prove source completeness, runtime behavior or signed provenance.";
      "Analysis prose, class judgments, cost ties and control effectiveness require qualified review.";
      "Observation is not atomic with a later Sa-plan claim/effect; recheck authority and fencing then.";
      "Snapshot is confined to one complete plan; no global optimum is asserted."])]);
  if not pass then exit 1
let verify_receipt path =
  let raw=read path in
  let j=Bounded.json_text raw in unique j;
  require (valid_utc (text "observed_at" j)) "receipt timestamp invalid";
  let artifacts=arr (field "artifacts" j) in
  require (artifacts<>[] && List.length artifacts<=256) "receipt artifact count exceeds 1..256";
  Checker.assert_distinct "receipt artifact" (List.map (text "path") artifacts);
  let root=Unix.realpath "." in
  let mismatches=ref [] and total=ref 0 in
  List.iter (fun item->
    let p=text "path" item in
    try
      ignore (Bounded.safe_relative p);
      let target=text "hash_target" item in
      ignore (Bounded.safe_relative target);
      require (hex64 (text "sha256" item)) "invalid digest";
      if has "link_target" item then (
        require (Unix.readlink (Filename.concat root p)=text "link_target" item) "receipt alias link changed";
        require (target=p || String.starts_with ~prefix:(p^"/") target) "receipt target is outside declared alias")
      else require (target=p && (Unix.lstat (Filename.concat root p)).Unix.st_kind=Unix.S_REG)
        "undeclared receipt alias";
      let resolved=Unix.realpath (Filename.concat root target) in
      require (String.starts_with ~prefix:(root^"/") resolved) "receipt alias leaves repository";
      let relative=String.sub resolved (String.length root+1) (String.length resolved-String.length root-1) in
      let bytes=Bounded.evidence ~root relative in
      total:= !total+String.length bytes;
      require (!total<=16777216) "receipt exceeds 16 MiB";
      require (Bounded.sha256 bytes=text "sha256" item && Unix.realpath (Filename.concat root target)=resolved)
        "receipt hash/alias mismatch"
    with Invalid _ | Unix.Unix_error _ | Sys_error _ -> mismatches:=p::!mismatches) artifacts;
  require (read path=raw) "receipt changed during verification";
  print_json (`Assoc ["status",`String (if !mismatches=[] then "LISTED_ARTIFACTS_MATCH" else "STALE_OR_CHANGED_ARTIFACTS");
    "authority",`String "NONE";"observed_at",`String (now_utc ());
    "receipt_sha256",`String (Bounded.sha256 raw);
    "artifacts_checked",`Int (List.length artifacts);
    "mismatches",`List (List.map (fun s->`String s) (List.rev !mismatches));
    "test_results_and_signer",`String "NOT_AUTHENTICATED";
    "fresh_runtime_evidence",`String "NOT_ASSERTED"]);
  if !mismatches<>[] then exit 1
let () =
  try
    match Array.to_list Sys.argv with
    | [_;"--all"] ->
        let base=selftest () and adversarial=Adversarial.run () in
        let package=check_package () in
        print_json (`Assoc ["status",`String "PASS";"authority",`String "NONE";
          "baseline_checks",`Int base;"adversarial_checks",`Int adversarial;
          "independent_dag_scenarios",`Int 32768;"package",package;
          "runtime_admission",`String "NOT_GRANTED";"live_agent_tests",`String "UNRUN"])
    | [_;"--adversarial"] -> print_json (`Assoc ["status",`String "PASS";
        "authority",`String "NONE";"checks",`Int (Adversarial.run ());"independent_dag_scenarios",`Int 32768])
    | [_;"--selftest"] -> print_json (`Assoc ["status",`String "PASS";"checks",`Int (selftest ());
        "authority",`String "REPORT_ONLY";"behavioral_agent_tests",`String "UNRUN"])
    | [_;"--package"] -> print_json (check_package ())
    | [_;"--audit";path] -> run_audit path None
    | [_;"--receipt";path] -> verify_receipt path
    | [_;"--preflight";path;task] -> run_audit path (Some task)
    | [_;"--active-check";path;task;worker;attempt] ->
        run_audit ~active:(worker,int_of_string attempt) path (Some task)
    | [_;"--plan";plan] ->
        let live=Live_plan.read ~path:"var/sa-plan/uos.sqlite3" ~plan in
        print_json (`Assoc ["status",`String "OBSERVED";"authority",`String "NONE";
          "observed_at",`String (now_utc ());"snapshot_sha256",`String (Live_plan.digest live);
          "tasks",`List (List.map Live_plan.to_json live)])
    | [_;"--record";path] ->
        ignore (check_record (schema ()) (json path));
        print_json (`Assoc ["status",`String "STRUCTURE_AND_ARITHMETIC_VALID";
          "live_source_digest_match",`String "NOT_CHECKED";"authority",`String "REPORT_ONLY"])
    | [_;"--rank";path] ->
        let s=schema () in
        let records=List.map (check_record s) (arr (json path)) in
        require (List.length records<=1000) "portfolio exceeds bound";
        let plans=List.map (text "plan_id") records |> List.sort_uniq String.compare in
        require (List.length plans<=1) "rank one plan at a time";
        let now=now_utc () in
        let ranked=rank ~now (List.map candidate records) in
        print_json (`Assoc ["authority",`String "ADVISORY_NOT_AUTHORIZATION";
          "observed_now",`String now;"live_source_digest_match",`String "NOT_CHECKED";
          "cost_tie_review",`String "MANUAL_BEFORE_STABLE_FALLBACK";
          "tasks",`List (List.map (fun r -> `Assoc [
            "task_id",`String r.task.id;
            "effective_class",`String ("P"^string_of_int r.effective_class);
            "effective_score",`Int r.effective_score;
            "origins",`List (List.map (fun s->`String s) r.origins)]) ranked)])
    | _ -> prerr_endline "Usage: risk-priority-check --all | --selftest | --adversarial | --package | --record FILE | --rank FILE | --audit PORTFOLIO | --preflight PORTFOLIO TASK | --active-check PORTFOLIO TASK WORKER ATTEMPT | --plan PLAN | --receipt FILE";exit 2
  with
  | Invalid message -> print_json (`Assoc ["status",`String "HOLD";"authority",`String "NONE";
      "rule",`String "RP-INVALID";"detail",`String message]);exit 1
  | _ -> print_json (`Assoc ["status",`String "HOLD";"authority",`String "NONE";
      "rule",`String "RP-UNAVAILABLE";"detail",`String "Input, dependency or checker unavailable; inspect locally."]);exit 1
