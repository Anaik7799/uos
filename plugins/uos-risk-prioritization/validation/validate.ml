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
  print_json (`Assoc ["status",`String "PASS";"checks",`Int !count;
    "authority",`String "REPORT_ONLY";"behavioral_agent_tests",`String "UNRUN"])
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
    if root<>"" then (
      let alias=root^"/skills/uos-risk-prioritization/SKILL.md" in
      local alias; require (read alias=read skill) ("skill alias drift: "^alias);
      let rule=root^"/rules/"^stamp^"-risk-prioritization-sop.md" in
      local rule; require (read rule=read sop) ("rule alias drift: "^rule)))
    ["";".codex";".claude";".gemini";".agents"];
  let manifest=plugin^"/.codex-plugin/plugin.json" in
  local manifest; let m=json manifest in
  require (text "name" m="uos-risk-prioritization" && text "version" m="1.0.0") "plugin identity/version";
  require (text "skills" m="./skills/") "plugin skills path";
  require (not (has "mcpServers" m || has "apps" m || has "hooks" m)) "unexpected active plugin capability";
  List.iter local [planning^"-policy.json";planning^"-record.schema.json";planning^"-example.json";
    "governance/agents/policy/"^stamp^"-risk-priority-bindings.toml";"tools/risk-priority-check";
    plugin^"/validation/priority.ml";plugin^"/validation/validate.ml";plugin^"/validation/dune";plugin^"/validation/dune-project";
    plugin^"/validation/uos-risk-priority-validation.opam"];
  let profile=json (planning^"-policy.json") in
  require (field "factors" profile=`List (List.map (fun s->`String s)
    ["criticality";"stpa";"fmea";"dependency";"impact"])) "factor profile drift";
  require (field "rpn_maxima" (field "fmea" profile)=`List (List.map (fun n->`Int n) [5;15;35;70;125]))
    "FMEA band profile drift";
  ignore (check_record (schema ()) (sample ()));
  print_json (`Assoc ["status",`String "PASS";"local_paths_checked",`Int !checked;
    "authority",`String "REPORT_ONLY";"runtime_enforcement",`String "NOT_ASSERTED";
    "global_skill_dependency",`Bool false])
let () =
  try
    match Array.to_list Sys.argv with
    | [_;"--adversarial"] -> print_json (`Assoc ["checks",`Int (Adversarial.run ())])
    | [_;"--selftest"] -> selftest ()
    | [_;"--package"] -> check_package ()
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
    | _ -> prerr_endline "Usage: risk-priority-check --selftest | --package | --record FILE | --rank FILE";exit 2
  with
  | Invalid message -> prerr_endline ("INVALID: "^message);exit 1
  | exn -> prerr_endline ("ERROR: "^Printexc.to_string exn);exit 1
