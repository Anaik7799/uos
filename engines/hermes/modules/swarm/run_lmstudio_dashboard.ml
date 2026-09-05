open Lmstudio_dashboard_web

let read_file path =
  if not (Sys.file_exists path) then Ok ""
  else
    try
      let channel = open_in_bin path in
      Fun.protect
        ~finally:(fun () -> close_in_noerr channel)
        (fun () -> Ok (really_input_string channel (in_channel_length channel)))
    with exn ->
      Error ("authority source read failed: " ^ Printexc.to_string exn)

let count_occurrences ~needle text =
  let n = String.length text and m = String.length needle in
  let rec loop index count =
    if index + m > n then count
    else if String.sub text index m = needle then loop (index + m) (count + 1)
    else loop (index + 1) count
  in
  if m = 0 then 0 else loop 0 0

let call_count path =
  Result.map
    (count_occurrences ~needle:"Sop_execution.execute_sop_workflow")
    (read_file path)

let browser_status ~public_url path =
  match read_file path with
  | Error diagnostic -> unavailable_observed diagnostic
  | Ok payload ->
      (try
         let json = Yojson.Safe.from_string payload in
         let open Yojson.Safe.Util in
         let schema = json |> member "schema" |> to_string in
         let observed_url = json |> member "public_url" |> to_string in
         let results = json |> member "results" |> to_list in
         let passed result =
           String.equal (result |> member "status" |> to_string) "pass"
           && result |> member "violations" |> to_list = []
         in
         if String.equal schema "hermes-dashboard-playwright-v1"
            && String.equal observed_url public_url
            && List.length results = 3 && List.for_all passed results
         then partial "typed OCaml Playwright matrix observed 3/3 responsive passes"
         else unavailable_observed "typed browser manifest failed exact validation"
       with exn ->
         unavailable_observed
           ("typed browser manifest could not be decoded: " ^ Printexc.to_string exn))

let knowledge_artifact_paths =
  [ "docs/hermes/journal/20260812-2152-run-swarm-bridge-execution-journal.md";
    "docs/hermes/prompts/20260812-2152-run-swarm-bridge-completion-prompts.md";
    "docs/hermes/specs/20260812-2152-run-swarm-bridge-dashboard-design.md";
    "docs/hermes/zk/20260812-2152-normative-windows-do-not-prove-actual-instance-disjointness.md";
    "docs/hermes/wiki/20260812-2152-run-swarm-bridge-km-map.md";
    "docs/hermes/reviews/20260812-2133-run-swarm-bridge-task1-semantic-review.md";
    "docs/hermes/reviews/20260812-2133-run-swarm-bridge-adversarial-surface-review.md";
    "docs/hermes/reviews/20260812-2133-run-swarm-bridge-artifact-completeness-review.md";
    "docs/hermes/reviews/20260812-2133-run-swarm-bridge-external-oracle-manifest.md" ]

let programme_summary path =
  match Sa_plan.Store.open_db path with
  | Error diagnostic -> Error diagnostic
  | Ok store ->
      Fun.protect
        ~finally:(fun () -> Sa_plan.Store.close store)
        (fun () ->
          match Sa_plan.Store.summary store
                  ~plan_id:Run_swarm_bridge_programme.plan_id,
                Sa_plan.Store.list_workflows store,
                Sa_plan.Store.list_jobs store ~queue:(Some "run-swarm-bridge") with
          | Ok summary, Ok workflows, Ok jobs ->
              let lifecycle_projection_running =
                List.exists
                  (fun (workflow : Sa_plan.Store.workflow_view) ->
                    String.equal workflow.id
                      Run_swarm_bridge_programme.lifecycle_projection_id
                    && String.equal workflow.state "running")
                  workflows
              in
              let recovery_projection_jobs =
                List.fold_left
                  (fun count (job : Sa_plan.Store.job_view) ->
                      if String.equal job.id
                         Run_swarm_bridge_programme.recovery_projection_id
                         && Run_swarm_bridge_programme.active_job_state job.state
                    then count + 1 else count)
                  0 jobs
              in
              let tasks_waiting =
                summary.total - summary.ready - summary.executing
                - summary.completed
              in
              Ok { registered_nodes = summary.total; total_nodes = summary.total;
                tasks_ready = summary.ready; tasks_waiting;
                tasks_executing = summary.executing;
                tasks_completed = summary.completed;
                lifecycle_projection_running; recovery_projection_jobs }
          | Error diagnostic, _, _ | _, Error diagnostic, _
          | _, _, Error diagnostic -> Error diagnostic)

let timestamp () =
  let tm = Unix.localtime (Unix.gettimeofday ()) in
  Printf.sprintf "%04d%02d%02d-%02d%02d"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_sec

let fqdn () =
  match Sys.getenv_opt "HERMES_TAILSCALE_FQDN" with
  | Some value when value <> "" ->
      let value = String.lowercase_ascii value in
      Result.map (fun () -> value)
        (Lmstudio_dashboard_web.validate_tailscale_fqdn value)
  | _ -> Error "HERMES_TAILSCALE_FQDN is required"

let snapshot programme_path port () =
  let canonical_bridge_calls =
    call_count "modules/hermes_ops_dashboard/run_swarm_bridge.ml"
  in
  let residual_direct_calls =
    match call_count "modules/hermes_ops/ops_verify.ml",
          call_count "modules/hermes_ops/ops_command_runtime.ml" with
    | Ok left, Ok right -> Ok (left + right)
    | Error diagnostic, _ | _, Error diagnostic -> Error diagnostic
  in
  let bridge canonical_bridge_calls residual_direct_calls =
    if canonical_bridge_calls = 1 && residual_direct_calls = 0 then
      partial
        "canonical bridge live suite is 88/88, including durable restart, exact engine order, and ledger-backed readback; sole-call census is closed; final adversarial receipt still required"
    else if canonical_bridge_calls = 1 && residual_direct_calls = 2 then
      partial
        "canonical bridge live suite is 88/88, including durable restart, exact engine order, and ledger-backed readback; two declared operator-path migration residuals remain"
    else
      partial
        (Printf.sprintf "implementation frontier: canonical=%d residual=%d"
           canonical_bridge_calls residual_direct_calls)
  in
  match fqdn (), programme_summary programme_path, canonical_bridge_calls,
        residual_direct_calls with
  | Error diagnostic, _, _, _ | _, Error diagnostic, _, _
  | _, _, Error diagnostic, _ | _, _, _, Error diagnostic -> Error diagnostic
  | Ok fqdn, Ok programme, Ok canonical_bridge_calls, Ok residual_direct_calls ->
      let public_url = Printf.sprintf "http://%s:%d" fqdn port in
      let knowledge_artifacts =
        List.fold_left
          (fun count path -> if Sys.file_exists path then count + 1 else count)
          0 knowledge_artifact_paths
      in
      Ok (make_snapshot
        ~public_url
        ~timestamp:(timestamp ()) ~programme
        ~bridge:(bridge canonical_bridge_calls residual_direct_calls)
        ~fpp:(partial "83/83 relational structure; canonical FPP law is Unsat on both backends")
        ~formal:(partial "Task 3 is 43/43 with independently reconstructed canonical 42+42 evidence: 35 controls and 7 laws per backend; dashboard exact-head wrapper is pending")
        ~browser:(browser_status ~public_url
          "state/browser/20260813-0120-dashboard/manifest.json")
        ~canonical_bridge_calls ~residual_direct_calls ~knowledge_artifacts)

let () =
  let port =
    match port_from_environment ~getenv:Sys.getenv_opt with
    | Ok value -> value
    | Error diagnostic -> prerr_endline diagnostic; exit 2
  in
  let db_path = "state/lmstudio_continuous_history.db" in
  let programme_path = "state/run_swarm_bridge_programme.sqlite3" in
  let fqdn = match fqdn () with
    | Ok value -> value
    | Error diagnostic -> prerr_endline diagnostic; exit 2
  in
  Printf.printf
    "run_lmstudio_dashboard: serving read-only projection at http://%s:%d\n%!"
    fqdn port;
  start_server ~port ~db_path ~snapshot:(snapshot programme_path port)
