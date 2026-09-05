module Management = Sa_plan.Management
module Store = Sa_plan.Store

let plan_id = "uos/ocaml-gleam-tests/v1"
let workflow_id = plan_id ^ "/workflow"
let queue = "uos-ocaml-gleam-v1-reserved"
let title = "Additive Gleam counterparts; retain every OCaml original"
let baseline = "governance/testing/ocaml_gleam/20260905-2149-source-candidates.json"
let baseline_revision = "22008c49704ab12e809537d0d7a7c43810158fba"
let baseline_sha256 = "fa274d8d918ca0d845f995651a8be508048f28c5d73da7367f2fcdea4a11ea51"

let families =
  [ "hermes_agent_loop", 17; "hermes_dependability", 23;
    "hermes_dune_graph", 1; "hermes_fpp_authority", 1;
    "hermes_harness", 82; "hermes_nix", 8; "hermes_ops", 35;
    "hermes_ops_dashboard", 23; "hermes_sysml", 6;
    "hermes_toolchain", 2; "hermes_vcs", 19; "hermes_vision", 2;
    "hermes_wiki", 69; "hermes_zellij", 3; "swarm", 18; "system_engg", 9 ]

let node ?(parent_id = Some "OGL") id title dependencies =
  Management.{ id; parent_id; task_type = Story; title;
               estimate_points = None; dependencies }

let family_id i stage = Printf.sprintf "OGL.M%02d.%s" (i + 1) stage
let family_nodes =
  List.mapi (fun i (family, candidates) ->
    let d = family_id i "D" and p = family_id i "P"
    and v = family_id i "V" and r = family_id i "R" in
    [ node d (Printf.sprintf "%s: classify %d candidates; enumerate cases and fixtures" family candidates) ["OGL.00"];
      node p (family ^ ": implement traced Gleam assertions over original libraries") [d; "OGL.05"];
      node v (family ^ ": execute both suites, boundaries, properties and mutants") [p; "OGL.02"];
      node r (family ^ ": independent source-case and safety review") [v] ]) families
  |> List.concat

let nodes =
  [ node ~parent_id:None "OGL" title ["OGL.94"];
    node "OGL.00" "Freeze and validate source inventory; preserve originals and Dune files" [];
    node "OGL.01" "Verify pinned OTP29, Gleam, OCaml and native build readiness" ["OGL.00"];
    node "OGL.02" "Implement Gleam preservation gate and expanded Dune classification" ["OGL.00"];
    node "OGL.03" "Implement all seven parity-algebra layers and bounded native adapter" ["OGL.01"];
    node "OGL.04" "Independently review pilot, case map, transport and mutation evidence" ["OGL.02"; "OGL.03"];
    node "OGL.05" "Admit pilot pattern only after fresh source-preservation and parity evidence" ["OGL.04"] ]
  @ family_nodes
  @ [ node "OGL.91" "Integrate all family evidence; report unknowns and nonstandard tests" (List.mapi (fun i _ -> family_id i "R") families);
      node "OGL.92" "Recheck every original test, fixture, helper and Dune declaration unchanged" ["OGL.91"];
      node "OGL.93" "Run final differential, fault, formal and mutation gates; reject vacuity" ["OGL.91"];
      node "OGL.94" "Independent final review and explicit operator integration handoff" ["OGL.92"; "OGL.93"] ]

let strings values = `List (List.map (fun x -> `String x) values)
let node_json (n : Management.plan_node) =
  `Assoc ["id", `String n.id; "title", `String n.title;
          "parent_id", (match n.parent_id with None -> `Null | Some p -> `String p);
          "dependencies", strings n.dependencies]

let specification =
  `Assoc ["version", `Int 1; "plan_id", `String plan_id;
          "workflow_id", `String workflow_id;
          "backend", `String "Sa_plan.Store/sqlite/local-temporal-style-history";
          "temporal_service_connected", `Bool false;
          "dispatch_enabled", `Bool false; "queue", `String queue;
          "source_baseline", `String baseline;
          "source_baseline_sha256", `String baseline_sha256;
          "source_revision", `String baseline_revision;
          "candidate_files", `Int 318; "case_denominator", `Null;
          "originals_policy", `String "retain-byte-for-byte-permanently";
          "jobs_enforce_dependencies", `Bool false;
          "required_worker_gate", `String "authorization + Store.claim_task + fresh source evidence before effects";
          "unavailable", strings ["Temporal server/SDK"; "signals"; "durable timers"; "workflow cancellation"; "worker dispatcher"];
          "tasks", `List (List.map node_json nodes)]

let ( let* ) = Result.bind
let workflow_kind = "uos.additive-ocaml-gleam.registration.v1"
let workflow_input = Yojson.Basic.to_string specification
let worker = "UosOcamlGleamReservedNoDispatcher"
let job_nodes = List.filter (fun (n : Management.plan_node) -> n.id <> "OGL") nodes
let job_id (n : Management.plan_node) = plan_id ^ "/jobs/" ^ n.id
let job_name n = String.lowercase_ascii (job_id n)
let job_args (n : Management.plan_node) =
  `Assoc ["plan_id", `String plan_id; "task_id", `String n.id;
          "workflow_id", `String workflow_id;
          "activity_id", `String (n.id ^ "/execute/v1");
          "idempotency_key", `String (plan_id ^ "/" ^ n.id ^ "/execute/v1");
          "dependencies", strings n.dependencies;
          "dispatch_enabled", `Bool false; "requires_task_claim", `Bool true;
          "source_baseline", `String baseline;
          "source_baseline_sha256", `String baseline_sha256;
          "originals_policy", `String "retain-byte-for-byte-permanently";
          "criticality", `String (if String.starts_with ~prefix:"OGL.M" n.id then "P1" else "P0");
          "fmea_status", `String "assessment-required-no-invented-scores";
          "effects", `List []]
  |> Yojson.Basic.to_string

let same_job (n : Management.plan_node) (j : Store.job_view) =
  j.id = job_id n && j.name = job_name n && j.queue = queue
  && j.worker = worker && j.args = job_args n && j.max_attempts = 3

let job_state = function
  | Store.Job_available -> "available" | Job_executing -> "executing"
  | Job_retry -> "retry" | Job_completed -> "completed"
  | Job_discarded -> "discarded" | Job_cancelled -> "cancelled"

let rec all f = function
  | [] -> Ok ()
  | x :: xs -> let* () = f x in all f xs

let ensure_workflow store ~now_ns =
  let* workflows = Store.list_workflows store in
  match List.find_opt (fun (w : Store.workflow_view) -> w.id = workflow_id) workflows with
  | None -> Store.start_workflow_with_input store ~id:workflow_id
              ~name:workflow_id ~kind:workflow_kind ~input:workflow_input ~now_ns
  | Some w when w.name = workflow_id && w.kind = workflow_kind
                && w.input = workflow_input && w.state = "running" -> Ok ()
  | Some _ -> Error "workflow immutable input drift or terminal state; no overwrite"

let ensure_jobs store ~now_ns =
  let* existing = Store.list_jobs store ~queue:None in
  all (fun n ->
    match List.find_opt (fun (j : Store.job_view) -> j.id = job_id n) existing with
    | Some j when same_job n j -> Ok ()
    | Some _ -> Error ("job immutable input drift: " ^ n.id)
    | None ->
        let* _ = Store.enqueue_job store ~id:(job_id n) ~name:(job_name n)
          ~queue ~worker ~args:(job_args n) ~max_attempts:3 ~now_ns in
        Ok ()) job_nodes

let observe store =
  let* plan = Store.find_plan store ~id_or_name:plan_id in
  let* () = match plan with
    | Some p when p.title = title -> Ok ()
    | _ -> Error "plan absent or title drift" in
  let* tasks = Store.list_task_observations store ~plan_id in
  let* jobs = Store.list_jobs store ~queue:(Some queue) in
  let* workflows = Store.list_workflows store in
  let* workflow = match List.find_opt
      (fun (w : Store.workflow_view) -> w.id = workflow_id) workflows with
    | Some w when w.name = workflow_id && w.kind = workflow_kind && w.input = workflow_input -> Ok w
    | _ -> Error "workflow absent or immutable input drift" in
  let* () =
    if List.length tasks <> List.length nodes || List.length jobs <> List.length job_nodes then
      Error "persisted task/job set is incomplete or has unexpected members"
    else all (fun (n : Management.plan_node) ->
      match List.find_opt (fun (t : Store.task_observation) -> t.task.id = n.id) tasks with
      | Some t when t.task.title = n.title && t.task.parent_id = n.parent_id
                    && List.sort String.compare t.dependencies = List.sort String.compare n.dependencies -> Ok ()
      | _ -> Error ("task definition drift: " ^ n.id)) nodes in
  let* () = all (fun n ->
    match List.find_opt (fun (j : Store.job_view) -> j.id = job_id n) jobs with
    | Some j when same_job n j -> Ok ()
    | _ -> Error ("job definition drift: " ^ n.id)) job_nodes in
  let* summary = Store.summary store ~plan_id in
  let task_json (t : Store.task_observation) =
    `Assoc ["id", `String t.task.id; "title", `String t.task.title;
            "state", `String t.task.state; "attempt", `Int t.task.attempt;
            "dependencies", strings t.dependencies] in
  let job_json (j : Store.job_view) =
    `Assoc ["id", `String j.id; "queue", `String j.queue;
            "state", `String (job_state j.state); "attempt", `Int j.attempt;
            "max_attempts", `Int j.max_attempts; "args", Yojson.Basic.from_string j.args] in
  let event_json (e : Store.workflow_event) =
    `Assoc ["sequence", `Int e.sequence; "kind", `String e.kind;
            "occurred_at_ns", `String (Int64.to_string e.occurred_at_ns)] in
  Ok (`Assoc ["plan_id", `String plan_id; "workflow_id", `String workflow_id;
              "workflow_state", `String workflow.state;
              "dispatch_enabled", `Bool false; "queue", `String queue;
              "backend", `String "Sa_plan.Store/sqlite/local-temporal-style-history";
              "temporal_service_connected", `Bool false;
              "task_count", `Int (List.length tasks); "job_count", `Int (List.length jobs);
              "completed", `Int summary.completed; "ready", `Int summary.ready;
              "executing", `Int summary.executing;
              "job_attempts", `Int (List.fold_left (fun n (j : Store.job_view) -> n + j.attempt) 0 jobs);
              "tasks", `List (List.map task_json tasks);
              "jobs", `List (List.map job_json jobs);
              "events", `List (List.map event_json workflow.events)])

let materialize store ~now_ns =
  if now_ns <= 0L then Error "registration requires positive observed UTC nanoseconds"
  else Store.with_transaction store (fun () ->
    let* () = Store.register_plan store ~id:plan_id ~title ~nodes in
    let* () = ensure_workflow store ~now_ns in
    let* () = ensure_jobs store ~now_ns in
    observe store)
