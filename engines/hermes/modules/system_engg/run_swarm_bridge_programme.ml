module Management = Sa_plan.Management
module Store = Sa_plan.Store

let timestamp = "20260812-2145"
let plan_id = "run-swarm-bridge/20260812-2145/programme"
let lifecycle_projection_id =
  "run-swarm-bridge/20260812-2145/lifecycle-projection"
let recovery_projection_id =
  "run-swarm-bridge/20260812-2145/recovery-projection"
let state_path = "state/run_swarm_bridge_programme.sqlite3"
let state_bytes_needed = 1 * 1024 * 1024

type receipt = {
  registered_nodes : int;
  lifecycle_projection_running : bool;
  recovery_projection_jobs : int;
}

let parse_cli_arguments = function
  | [] -> Ok state_path
  | [ "--path"; path ] when String.equal path state_path -> Ok path
  | [ "--path"; _ ] -> Error ("--path must be exactly " ^ state_path)
  | _ -> Error "accepted arguments: no arguments, or --path followed by the declared state path"

let state_resources path =
  [ Resource_envelope.Disk_space
      { path = Filename.dirname path; bytes_needed = state_bytes_needed;
        margin = Resource_envelope.default_margin };
    Resource_envelope.Writable path ]

let preflight_state_path path =
  if not (String.equal path state_path) then
    Error ("state path must be exactly " ^ state_path)
  else
    (* Resource identity and observation belong to the controlled owner.
       Do not perform a shadow filesystem probe ahead of its receipt gate. *)
    let checks = Resource_envelope.preflight (state_resources path) in
    if Resource_envelope.satisfied checks then Ok ()
    else
      Error
        ("state resource envelope refused: "
         ^ String.concat "; "
             (List.map Resource_envelope.render_check
                (Resource_envelope.unmet_checks checks)))

let task_specs =
  [
    ("Independently admit and correct relational authority",
     [ "Assign an independent reviewer"; "Reproduce the focused result";
       "Verify raw-row correspondence"; "Attack vacuity";
       "Record the gate"; "Commit the independent receipt" ]);
    ("Close topology, effect-target, and fast-path authority",
     [ "Write topology REDs"; "Define the closed topology API";
       "Extend formal and MBSE projections"; "Write effect-target REDs";
       "Add the topology-derived target registry"; "Write fast-path REDs";
       "Add the private selection API"; "Run focused GREEN serially";
       "Commit topology and fast-path authority" ]);
    ("Implement hard-isolated dual-backend Z3 authority",
     [ "Admit worker and protocol RED executables in Dune";
       "Capture protocol RED"; "Implement the closed protocol";
       "Capture process RED"; "Implement worker containment";
       "Implement parent supervision";
       "Capture and close the Z3 campaign RED";
       "Run GREEN and containment review"; "Commit Z3 authority" ]);
    ("Build exact intelligence and opaque assurance admission",
     [ "Write exact-input REDs"; "Add exact validators";
       "Replace loose list admission with private carriers";
       "Run focused GREEN serially"; "Commit assurance admission" ]);
    ("Add store-backed production current-head authority",
     [ "Add a compile-coherent unavailable production surface";
       "Write behavioral REDs"; "Implement observation";
       "Run safety and event-store GREEN"; "Commit current-head authority" ]);
    ("Implement bridge admission, event authority, and immutable plan",
     [ "Define the public private-carrier API"; "Write admission REDs";
       "Add the unavailable scaffold"; "Capture behavioral RED";
       "Implement event and plan authority";
       "Run pre-execution GREEN"; "Commit bridge admission" ]);
    ("Add the sole engine call and durable attempt wrappers",
     [ "Write execution REDs"; "Capture execution RED";
       "Add the sole call"; "Implement the wrapper state machine";
       "Validate projection and full readback";
       "Run GREEN and mutants"; "Commit execution authority" ]);
    ("Flip the repository ratchet from reservation to presence",
     [ "Capture the presence RED"; "Add recursion and two-call mutants";
       "Run presence GREEN"; "Commit the presence ratchet" ]);
    ("Add a typed verification effect target and migrate Ops_verify",
     [ "Define the typed verification request";
       "Write target and Ops_verify REDs";
       "Route verification through the bridge"; "Run verification GREEN";
       "Commit verification target" ]);
    ("Remove the generic command Swarm wrapper",
     [ "Write command-algebra REDs"; "Remove the generic constructor";
       "Split pure and effectful runtime paths";
       "Prove four-surface equivalence"; "Run the final call census";
       "Commit command migration" ]);
    ("Convergence, mutation, durable campaign, and handover",
     [ "Register the completed capability path";
       "Run the serialized focused chain";
       "Run registered mutation offload";
       "Run the complete repository gate twice";
       "Run the admitted 300-attempt campaign";
       "Verify external-surface non-admission";
       "Write completion records"; "Commit completion" ]);
  ]

let task_id index = Printf.sprintf "RSB.T%02d" (index + 1)
let step_id task_index step_index =
  Printf.sprintf "RSB.T%02d.S%02d" (task_index + 1) (step_index + 1)

let story ?parent_id ?(dependencies = []) id title =
  Management.{
    id; parent_id; task_type = Story; title; estimate_points = None;
    dependencies;
  }

let nodes =
  let tasks =
    List.mapi
      (fun task_index (title, steps) ->
        let id = task_id task_index in
        let final_step = step_id task_index (List.length steps - 1) in
        let task = story ~parent_id:"RSB" ~dependencies:[ final_step ] id title in
        let step_nodes =
          List.mapi
            (fun step_index step_title ->
              let dependencies =
                if step_index > 0 then [ step_id task_index (step_index - 1) ]
                else if task_index > 0 then [ task_id (task_index - 1) ]
                else []
              in
              story ~parent_id:id ~dependencies
                (step_id task_index step_index) step_title)
            steps
        in
        task :: step_nodes)
      task_specs
    |> List.concat
  in
  story ~dependencies:[ task_id 10 ] "RSB"
    "Run_swarm_bridge and FPP whole-system completion" :: tasks

let validate () =
  if List.length task_specs <> 11 then Error "expected eleven programme tasks"
  else if List.length nodes <> 83 then Error "expected exactly 83 durable nodes"
  else
    let state = List.fold_left Management.add_node Management.empty nodes in
    match Management.execution_plan state with
    | Error diagnostic -> Error diagnostic
    | Ok order when List.length order <> List.length nodes ->
        Error "execution plan lost nodes"
    | Ok _ -> Ok ()

let find_workflow workflows =
  List.find_opt (fun (workflow : Store.workflow_view) ->
      String.equal workflow.id lifecycle_projection_id) workflows

let find_job jobs =
  List.find_opt (fun (job : Store.job_view) ->
      String.equal job.id recovery_projection_id) jobs

let active_job_state = function
  | Store.Job_available | Store.Job_executing | Store.Job_retry -> true
  | Store.Job_completed | Store.Job_discarded | Store.Job_cancelled -> false

let observe store =
  match Store.list_tasks store ~plan_id with
  | Error diagnostic -> Error diagnostic
  | Ok tasks ->
      (match Store.list_workflows store with
       | Error diagnostic -> Error diagnostic
       | Ok workflows ->
           (match Store.list_jobs store ~queue:(Some "run-swarm-bridge") with
            | Error diagnostic -> Error diagnostic
            | Ok jobs ->
                let lifecycle_projection_running =
                  match find_workflow workflows with
                  | Some workflow -> String.equal workflow.state "running"
                  | None -> false
                in
                let recovery_projection_jobs =
                  List.fold_left
                    (fun count (job : Store.job_view) ->
                      if String.equal job.id recovery_projection_id
                         && active_job_state job.state
                      then count + 1 else count)
                    0 jobs
                in
                if not lifecycle_projection_running then
                  Error "lifecycle projection is absent or not running"
                else if recovery_projection_jobs <> 1 then
                  Error "recovery projection must have exactly one active job"
                else
                  Ok { registered_nodes = List.length tasks;
                       lifecycle_projection_running;
                       recovery_projection_jobs }))

let ensure_workflow store now_ns =
  match Store.list_workflows store with
  | Error diagnostic -> Error diagnostic
  | Ok workflows ->
      (match find_workflow workflows with
       | Some workflow when String.equal workflow.state "running" -> Ok ()
       | Some workflow ->
           Error ("lifecycle projection is terminal: " ^ workflow.state)
       | None ->
           Store.start_workflow_with_input store ~id:lifecycle_projection_id
             ~name:"run-swarm-bridge/lifecycle-projection/20260812-2145"
             ~kind:"run_swarm_bridge_completion_projection"
             ~input:"{\"plan_id\":\"run-swarm-bridge/20260812-2145/programme\"}"
             ~now_ns)

let ensure_job store now_ns =
  match Store.list_jobs store ~queue:(Some "run-swarm-bridge") with
  | Error diagnostic -> Error diagnostic
  | Ok jobs ->
      (match find_job jobs with
       | Some job when active_job_state job.state -> Ok ()
       | Some _ -> Error "recovery projection job is terminal"
       | None ->
           (match Store.enqueue_job store ~id:recovery_projection_id
                    ~name:"run-swarm-bridge/recovery-projection/20260812-2145"
                    ~queue:"run-swarm-bridge"
                    ~worker:"RunSwarmBridgeProjectionSupervisor"
                    ~args:"{\"lifecycle_projection_id\":\"run-swarm-bridge/20260812-2145/lifecycle-projection\"}"
                    ~max_attempts:3 ~now_ns with
            | Ok _ -> Ok ()
            | Error diagnostic -> Error diagnostic))

let materialize_on_store store ~now_ns ~after_plan ~after_workflow =
  Store.with_transaction store (fun () ->
      match
        Store.register_plan store ~id:plan_id
          ~title:"Run_swarm_bridge and FPP completion" ~nodes
      with
      | Error _ as error -> error
      | Ok () ->
          (match after_plan () with
           | Error _ as error -> error
           | Ok () ->
               (match ensure_workflow store now_ns with
                | Error _ as error -> error
                | Ok () ->
                    (match after_workflow () with
                     | Error _ as error -> error
                     | Ok () ->
                         (match ensure_job store now_ns with
                          | Error _ as error -> error
                          | Ok () -> observe store)))))

let materialize ~now_ns =
  match preflight_state_path state_path with
  | Error _ as error -> error
  | Ok () ->
      (match validate () with
       | Error _ as error -> error
       | Ok () ->
           (match Store.open_db state_path with
            | Error _ as error -> error
            | Ok store ->
                Fun.protect ~finally:(fun () -> Store.close store)
                  (fun () ->
                    materialize_on_store store ~now_ns
                      ~after_plan:(fun () -> Ok ())
                      ~after_workflow:(fun () -> Ok ()))))

module For_test = struct
  type fault = After_plan | After_workflow

  let materialize_at_internal ~path ~now_ns ~fault =
    match validate () with
    | Error _ as error -> error
    | Ok () ->
        (match Store.open_db path with
         | Error _ as error -> error
         | Ok store ->
             Fun.protect ~finally:(fun () -> Store.close store)
               (fun () ->
                 let inject checkpoint () =
                   match fault with
                   | Some requested when requested = checkpoint ->
                       Error "injected programme materialization failure"
                   | None | Some _ -> Ok ()
                 in
                 materialize_on_store store ~now_ns
                   ~after_plan:(inject After_plan)
                   ~after_workflow:(inject After_workflow)))

  let materialize_at ~path ~now_ns =
    materialize_at_internal ~path ~now_ns ~fault:None

  let materialize_at_with_fault ~path ~now_ns ~fault =
    materialize_at_internal ~path ~now_ns ~fault:(Some fault)
end
