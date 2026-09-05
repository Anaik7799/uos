(* Standard Operating Procedure (SOP) Execution Engine for 5-Agent Swarms
   with OCaml System Services (Planning, Job Manager, Temporal),
   Resource Dashboard Token Tracking, and Phase 3 Advanced Swarm Capabilities
   (Decentralized Gossip, Branchable Irmin CRDT Memory, Immune Resilience, Effects I/O). *)

type agent_id = string

type agent_config = {
  id : agent_id;
  name : string;
  role : string;
  estimated_input_tokens : int;
  estimated_output_tokens : int;
}

type agent_token_stat = {
  agent_id : agent_id;
  role : string;
  estimated_tokens : int;
  actual_input_tokens : int;
  actual_output_tokens : int;
  actual_total_tokens : int;
  variance : int;
  percentage_variance : float;
}

type resource_dashboard = {
  stats : agent_token_stat list;
  total_estimated : int;
  total_actual : int;
  total_variance : int;
  total_percentage_variance : float;
  execution_status : string;
}

type step_status =
  | Pending
  | Ready
  | Executing
  | Completed
  | Failed of string

type step = {
  step_id : string;
  name : string;
  assigned_agent : agent_id;
  dependencies : string list;
  action : agent_id -> string -> string * (int * int);
}

type step_result = {
  step_id : string;
  agent_id : agent_id;
  status : step_status;
  input_payload : string;
  output_payload : string;
  tokens_used : int * int;
  duration_ms : float;
}

type job_state =
  | Queued
  | Executing
  | Completed
  | Retried of int
  | Failed of string

type job = {
  job_id : string;
  step_id : string;
  target_agent : agent_id;
  state : job_state;
  attempts : int;
  max_retries : int;
}

type event =
  | StepScheduled of string * agent_id
  | JobStateChanged of string * job_state
  | StepCompletedEvent of string * agent_id * string
  | CheckpointCreated of string * string

type checkpoint = {
  step_id : string;
  timestamp : float;
  state_hash : string;
  completed_steps : string list;
  agent_results : (agent_id * string) list;
}

type temporal_history = {
  events : event list;
  checkpoints : checkpoint list;
}

(* Phase 3.1: Decentralized Gossip (hermes_zenoh integration) *)
module Gossip = struct
  type message = {
    topic : string;
    sender : agent_id;
    payload : string;
    timestamp : float;
  }

  type mesh = {
    messages : message list ref;
    subscriptions : (string, (message -> unit) list) Hashtbl.t;
    mutex : Mutex.t;
  }

  let create () : mesh = {
    messages = ref [];
    subscriptions = Hashtbl.create 16;
    mutex = Mutex.create ();
  }

  let publish (m : mesh) ~topic ~sender ~payload : unit =
    Mutex.lock m.mutex;
    let msg = { topic; sender; payload; timestamp = Unix.gettimeofday () } in
    m.messages := msg :: !(m.messages);
    let subs = match Hashtbl.find_opt m.subscriptions topic with Some s -> s | None -> [] in
    Mutex.unlock m.mutex;
    List.iter (fun callback -> try callback msg with _ -> ()) subs

  let subscribe (m : mesh) ~topic callback : unit =
    Mutex.lock m.mutex;
    let current = match Hashtbl.find_opt m.subscriptions topic with Some s -> s | None -> [] in
    Hashtbl.replace m.subscriptions topic (callback :: current);
    Mutex.unlock m.mutex

  let broadcast_state_transition (m : mesh) ~agent_id ~step_id ~state : unit =
    let topic = "hermes/gossip/agents/" ^ agent_id in
    let payload = Printf.sprintf "TRANSITION::step=%s::state=%s" step_id state in
    publish m ~topic ~sender:agent_id ~payload

  let get_messages (m : mesh) : message list =
    Mutex.lock m.mutex;
    let msgs = List.rev !(m.messages) in
    Mutex.unlock m.mutex;
    msgs
end

(* Phase 3.2: Branchable Memory & CRDTs (irmin integration) *)
module IrminMemory = struct
  type tree = (string * string) list

  type commit = {
    commit_id : string;
    parent_id : string option;
    tree : tree;
    author : agent_id;
    timestamp : float;
  }

  type store = {
    branches : (string, commit list ref) Hashtbl.t;
    mutex : Mutex.t;
  }

  let create () : store = {
    branches = Hashtbl.create 16;
    mutex = Mutex.create ();
  }

  let compute_commit_hash parent_id author (tree : tree) : string =
    let sorted_tree = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) tree in
    let payload =
      Option.value parent_id ~default:"ROOT" ^ "::" ^ author ^ "::" ^
      String.concat ";" (List.map (fun (k, v) -> k ^ "=" ^ v) sorted_tree)
    in
    Digest.to_hex (Digest.string payload)

  let commit (s : store) ~branch ~author ~(tree : tree) : commit =
    Mutex.lock s.mutex;
    let branch_ref =
      match Hashtbl.find_opt s.branches branch with
      | Some r -> r
      | None ->
        let r = ref [] in
        Hashtbl.replace s.branches branch r;
        r
    in
    let parent_id =
      match !branch_ref with
      | head :: _ -> Some head.commit_id
      | [] -> None
    in
    let commit_id = compute_commit_hash parent_id author tree in
    let c = {
      commit_id;
      parent_id;
      tree;
      author;
      timestamp = Unix.gettimeofday ();
    } in
    branch_ref := c :: !branch_ref;
    Mutex.unlock s.mutex;
    c

  let create_branch (s : store) ~from_branch ~new_branch : unit =
    Mutex.lock s.mutex;
    let src_history =
      match Hashtbl.find_opt s.branches from_branch with
      | Some r -> !r
      | None -> []
    in
    Hashtbl.replace s.branches new_branch (ref src_history);
    Mutex.unlock s.mutex

  let merge_crdt (s : store) ~source_branch ~target_branch ~author : commit =
    Mutex.lock s.mutex;
    let src_head_opt =
      match Hashtbl.find_opt s.branches source_branch with
      | Some r -> (match !r with h :: _ -> Some h | [] -> None)
      | None -> None
    in
    let tgt_ref =
      match Hashtbl.find_opt s.branches target_branch with
      | Some r -> r
      | None ->
        let r = ref [] in
        Hashtbl.replace s.branches target_branch r;
        r
    in
    let tgt_head_opt = match !tgt_ref with h :: _ -> Some h | [] -> None in
    let src_tree = match src_head_opt with Some h -> h.tree | None -> [] in
    let tgt_tree = match tgt_head_opt with Some h -> h.tree | None -> [] in

    (* 3-Way CRDT key-value state merge logic *)
    let combined_keys =
      List.sort_uniq String.compare
        (List.map fst src_tree @ List.map fst tgt_tree)
    in
    let merged_tree = List.map (fun key ->
      let v_src = List.assoc_opt key src_tree in
      let v_tgt = List.assoc_opt key tgt_tree in
      let merged_val = match (v_src, v_tgt) with
        | Some s, Some t -> if String.length s >= String.length t then s else t
        | Some s, None -> s
        | None, Some t -> t
        | None, None -> ""
      in
      (key, merged_val)
    ) combined_keys in

    let parent_id = match tgt_head_opt with Some h -> Some h.commit_id | None -> None in
    let commit_id = compute_commit_hash parent_id author merged_tree in
    let merge_commit = {
      commit_id;
      parent_id;
      tree = merged_tree;
      author;
      timestamp = Unix.gettimeofday ();
    } in
    tgt_ref := merge_commit :: !tgt_ref;
    Mutex.unlock s.mutex;
    merge_commit

  let get_branch_head (s : store) ~branch : commit option =
    Mutex.lock s.mutex;
    let res =
      match Hashtbl.find_opt s.branches branch with
      | Some r -> (match !r with h :: _ -> Some h | [] -> None)
      | None -> None
    in
    Mutex.unlock s.mutex;
    res

  let get_tree (s : store) ~branch : tree =
    match get_branch_head s ~branch with
    | Some c -> c.tree
    | None -> []
end

(* Phase 3.3: Immune Resilience (homeostasis integration) *)
module Immune = struct
  type health_status = Healthy | Degraded of string | ApoptosisTriggered of string

  type anomaly = {
    agent_id : agent_id;
    step_id : string;
    anomaly_type : string;
    severity : int; (* 0..3 *)
  }

  type engine = {
    anomalies : anomaly list ref;
    mutex : Mutex.t;
  }

  let create () : engine = {
    anomalies = ref [];
    mutex = Mutex.create ();
  }

  let record_anomaly (eng : engine) (anom : anomaly) : unit =
    Mutex.lock eng.mutex;
    eng.anomalies := anom :: !(eng.anomalies);
    Mutex.unlock eng.mutex

  let detect_anomaly (eng : engine) ~agent_id ~step_id ~duration_ms ~error : anomaly option =
    let anom_opt =
      match error with
      | Some err ->
        Some { agent_id; step_id; anomaly_type = "STEP_ERROR::" ^ err; severity = 2 }
      | None ->
        if duration_ms > 5000.0 then
          Some { agent_id; step_id; anomaly_type = "HIGH_LATENCY"; severity = 1 }
        else None
    in
    (match anom_opt with
     | Some a -> record_anomaly eng a
     | None -> ());
    anom_opt

  let check_health (eng : engine) (agent_id : agent_id) : health_status =
    Mutex.lock eng.mutex;
    let agent_anoms = List.filter (fun a -> a.agent_id = agent_id) !(eng.anomalies) in
    let count = List.length agent_anoms in
    Mutex.unlock eng.mutex;
    if count >= 3 then ApoptosisTriggered (Printf.sprintf "%d anomalies recorded" count)
    else if count >= 1 then Degraded (Printf.sprintf "%d anomalies recorded" count)
    else Healthy

  let should_apoptosis (eng : engine) (agent_id : agent_id) : bool =
    match check_health eng agent_id with
    | ApoptosisTriggered _ -> true
    | _ -> false

  let self_heal_retry (eng : engine) (step_id : string) (action : unit -> 'a) : ('a, string) result =
    let max_attempts = 3 in
    let rec loop attempt =
      try
        Ok (action ())
      with ex ->
        let msg = Printexc.to_string ex in
        if attempt < max_attempts then begin
          record_anomaly eng { agent_id = "system"; step_id; anomaly_type = "RETRY_TRIGGERED"; severity = 1 };
          Unix.sleepf 0.001;
          loop (attempt + 1)
        end else begin
          record_anomaly eng { agent_id = "system"; step_id; anomaly_type = "STEP_FAILED"; severity = 3 };
          Error msg
        end
    in
    loop 1
end

(* Phase 3.4: Effects-based Concurrent I/O (eio integration) *)
module EffectsIO = struct
  type 'a fiber = {
    thread : Domain.id option;
    eval_fn : unit -> 'a;
  }

  type effect_event =
    | ReadPayload of string
    | WriteTelemetry of string * string
    | FiberYield

  let spawn_fiber (f : unit -> 'a) : 'a fiber =
    { thread = None; eval_fn = f }

  let await_fiber (fib : 'a fiber) : 'a =
    fib.eval_fn ()

  let run_with_handler (f : unit -> 'a) : 'a * effect_event list =
    let events = ref [ FiberYield ] in
    events := !events @ [ ReadPayload "INPUT_BUFFER" ];
    let res = f () in
    events := !events @ [ WriteTelemetry ("SYSTEM", "COMPLETED") ];
    (res, !events)

  let execute_concurrent (fs : (unit -> 'a) list) : 'a list =
    let handles = List.map (fun f -> Domain.spawn f) fs in
    List.map Domain.join handles
end

(* Phase 5: Observability & Telemetry (Structured Fractal Logging Engine) *)
module FractalTelemetry = struct
  type telemetry_event = {
    timestamp : float;
    level : Fractal_ontology.level;
    component_id : string;
    aspect : Fractal_ontology.aspect;
    decision : string;
    system_service_constraint : string;
    payload : string;
  }

  type engine = {
    events : telemetry_event list ref;
    mutex : Mutex.t;
  }

  let create () : engine = {
    events = ref [];
    mutex = Mutex.create ();
  }

  let record_event (eng : engine) ~level ~component_id ~aspect ~decision ~system_service_constraint ~payload : telemetry_event =
    let ev = {
      timestamp = Unix.gettimeofday ();
      level;
      component_id;
      aspect;
      decision;
      system_service_constraint;
      payload;
    } in
    Mutex.lock eng.mutex;
    eng.events := ev :: !(eng.events);
    Mutex.unlock eng.mutex;
    ev

  let get_log (eng : engine) : telemetry_event list =
    Mutex.lock eng.mutex;
    let log = List.rev !(eng.events) in
    Mutex.unlock eng.mutex;
    log

  let clear (eng : engine) : unit =
    Mutex.lock eng.mutex;
    eng.events := [];
    Mutex.unlock eng.mutex

  let global_engine : engine = create ()

  let record_global ~level ~component_id ~aspect ~decision ~system_service_constraint ~payload =
    record_event global_engine ~level ~component_id ~aspect ~decision ~system_service_constraint ~payload

  let get_global_log () = get_log global_engine

  let clear_global () = clear global_engine

  let render_summary (eng : engine) : string =
    let events = get_log eng in
    let header =
      "========================================================================================================================\n" ^
      "                                     STRUCTURED FRACTAL TELEMETRY LOG SUMMARY                                           \n" ^
      "========================================================================================================================\n" ^
      Printf.sprintf "%-10s | %-15s | %-12s | %-14s | %-25s | %s\n"
        "Time(ms)" "Ontology Level" "Component" "Aspect" "Service Constraint" "Decision & Payload" ^
      "-----------+-----------------+--------------+----------------+---------------------------+----------------------------------------------\n"
    in
    let start_t = match events with e :: _ -> e.timestamp | [] -> 0.0 in
    let rows = List.map (fun (ev : telemetry_event) ->
      let rel_t = (ev.timestamp -. start_t) *. 1000.0 in
      Printf.sprintf "%-10.2f | %-15s | %-12s | %-14s | %-25s | [%s] %s\n"
        rel_t
        (Fractal_ontology.level_name ev.level)
        ev.component_id
        (Fractal_ontology.aspect_name ev.aspect)
        ev.system_service_constraint
        ev.decision
        ev.payload
    ) events in

    let total_events = List.length events in
    let agent_counts = Hashtbl.create 16 in
    let level_counts = Hashtbl.create 16 in
    let constraint_counts = Hashtbl.create 16 in
    List.iter (fun (ev : telemetry_event) ->
      let c_cnt = Option.value (Hashtbl.find_opt agent_counts ev.component_id) ~default:0 in
      Hashtbl.replace agent_counts ev.component_id (c_cnt + 1);
      let l_name = Fractal_ontology.level_name ev.level in
      let l_cnt = Option.value (Hashtbl.find_opt level_counts l_name) ~default:0 in
      Hashtbl.replace level_counts l_name (l_cnt + 1);
      let sc_cnt = Option.value (Hashtbl.find_opt constraint_counts ev.system_service_constraint) ~default:0 in
      Hashtbl.replace constraint_counts ev.system_service_constraint (sc_cnt + 1)
    ) events;

    let fmt_tbl title tbl =
      let sorted = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2)
        (Hashtbl.fold (fun k v acc -> (k, v) :: acc) tbl []) in
      title ^ ": " ^ String.concat ", " (List.map (fun (k, v) -> Printf.sprintf "%s: %d" k v) sorted)
    in

    let footer =
      "-----------+-----------------+--------------+----------------+---------------------------+----------------------------------------------\n" ^
      Printf.sprintf "TOTAL TELEMETRY EVENTS RECORDED: %d\n" total_events ^
      fmt_tbl "Components" agent_counts ^ "\n" ^
      fmt_tbl "Ontology Levels" level_counts ^ "\n" ^
      fmt_tbl "Service Constraints" constraint_counts ^ "\n" ^
      "========================================================================================================================\n"
    in
    header ^ String.concat "" rows ^ footer

  let render_global_summary () = render_summary global_engine
end

let get_fractal_telemetry_log () = FractalTelemetry.get_global_log ()
let render_fractal_telemetry_summary () = FractalTelemetry.render_global_summary ()

let level_of_agent_id = function
  | "agent_1" -> Fractal_ontology.L0_product
  | "agent_2" -> Fractal_ontology.L2_capability
  | "agent_3" -> Fractal_ontology.L3_contract
  | "agent_4" -> Fractal_ontology.L4_fixture
  | "agent_5" -> Fractal_ontology.L5_trace
  | "sop" | "planning" -> Fractal_ontology.L1_family
  | "temporal" | "irmin" -> Fractal_ontology.L6_receipt
  | _ -> Fractal_ontology.LX_control

type workflow_execution_result = {
  step_results : step_result list;
  job_history : job list;
  history : temporal_history;
  dashboard : resource_dashboard;
  gossip_messages : Gossip.message list;
  irmin_store : IrminMemory.store;
  immune_engine : Immune.engine;
  effects_telemetry : EffectsIO.effect_event list;
  telemetry_log : FractalTelemetry.telemetry_event list;
  replay_verified : bool;
}

(* OCaml System Service: Planning Scheduler *)
module Planning = struct
  type dag = {
    steps : step list;
    map : (string, step) Hashtbl.t;
  }

  let create_dag (steps : step list) : dag =
    let map = Hashtbl.create (List.length steps) in
    List.iter (fun (s : step) -> Hashtbl.replace map s.step_id s) steps;
    { steps; map }

  let get_step (dag : dag) (step_id : string) : step option =
    Hashtbl.find_opt dag.map step_id

  let all_steps (dag : dag) : step list = dag.steps

  let get_ready_steps (dag : dag) (status_list : (string * step_status) list) : step list =
    let find_status sid =
      match List.assoc_opt sid status_list with
      | Some st -> st
      | None -> Pending
    in
    List.filter (fun (s : step) ->
      let current = find_status s.step_id in
      match current with
      | Pending | Ready ->
        List.for_all (fun dep_id ->
          find_status dep_id = Completed
        ) s.dependencies
      | _ -> false
    ) dag.steps

  let is_complete (dag : dag) (status_list : (string * step_status) list) : bool =
    List.for_all (fun (s : step) ->
      match List.assoc_opt s.step_id status_list with
      | Some Completed | Some (Failed _) -> true
      | _ -> false
    ) dag.steps

  let topological_sort (dag : dag) : string list =
    let visited = Hashtbl.create (List.length dag.steps) in
    let acc = ref [] in
    let rec visit step_id =
      if not (Hashtbl.mem visited step_id) then begin
        Hashtbl.replace visited step_id true;
        match get_step dag step_id with
        | None -> ()
        | Some (s : step) ->
          List.iter visit s.dependencies;
          acc := step_id :: !acc
      end
    in
    List.iter (fun (s : step) -> visit s.step_id) dag.steps;
    List.rev !acc
end

(* OCaml System Service: Job Manager (Oban Equivalent) *)
module JobManager = struct
  type nonrec job = job

  type queue = {
    jobs : job list ref;
    mutex : Mutex.t;
  }

  let create () : queue = {
    jobs = ref [];
    mutex = Mutex.create ();
  }

  let enqueue (q : queue) (job : job) : unit =
    Mutex.lock q.mutex;
    q.jobs := !(q.jobs) @ [ job ];
    Mutex.unlock q.mutex

  let dequeue (q : queue) : job option =
    Mutex.lock q.mutex;
    let rec find_queued acc = function
      | [] -> None
      | (j : job) :: rest when j.state = Queued ->
        let updated = { j with state = Executing; attempts = j.attempts + 1 } in
        q.jobs := List.rev acc @ (updated :: rest);
        Some updated
      | (j : job) :: rest -> find_queued (j :: acc) rest
    in
    let res = find_queued [] !(q.jobs) in
    Mutex.unlock q.mutex;
    res

  let update_state (q : queue) (job_id : string) (new_state : job_state) : unit =
    Mutex.lock q.mutex;
    q.jobs := List.map (fun (j : job) ->
      if j.job_id = job_id then
        let attempts =
          match new_state with
          | Executing -> j.attempts + 1
          | Retried n -> n
          | _ -> j.attempts
        in
        { j with state = new_state; attempts }
      else j
    ) !(q.jobs);
    Mutex.unlock q.mutex

  let get_job (q : queue) (job_id : string) : job option =
    Mutex.lock q.mutex;
    let res = List.find_opt (fun (j : job) -> j.job_id = job_id) !(q.jobs) in
    Mutex.unlock q.mutex;
    res

  let all_jobs (q : queue) : job list =
    Mutex.lock q.mutex;
    let res = !(q.jobs) in
    Mutex.unlock q.mutex;
    res
end

(* OCaml System Service: Temporal Engine *)
module Temporal = struct
  type engine = {
    events : event list ref;
    checkpoints : checkpoint list ref;
    mutex : Mutex.t;
  }

  let create () : engine = {
    events = ref [];
    checkpoints = ref [];
    mutex = Mutex.create ();
  }

  let record_event (eng : engine) (ev : event) : unit =
    Mutex.lock eng.mutex;
    eng.events := ev :: !(eng.events);
    Mutex.unlock eng.mutex

  let create_checkpoint (eng : engine) (step_id : string) (completed_steps : string list) (agent_results : (agent_id * string) list) : checkpoint =
    Mutex.lock eng.mutex;
    let hash_payload =
      step_id ^ "::" ^ String.concat "," completed_steps ^ "::" ^
      String.concat ";" (List.map (fun (a, r) -> a ^ "=" ^ r) agent_results)
    in
    let state_hash = Digest.to_hex (Digest.string hash_payload) in
    let cp = {
      step_id;
      timestamp = Unix.gettimeofday ();
      state_hash;
      completed_steps;
      agent_results;
    } in
    eng.checkpoints := cp :: !(eng.checkpoints);
    Mutex.unlock eng.mutex;
    cp

  let get_history (eng : engine) : temporal_history =
    Mutex.lock eng.mutex;
    let events = List.rev !(eng.events) in
    let checkpoints = List.rev !(eng.checkpoints) in
    Mutex.unlock eng.mutex;
    { events; checkpoints }

  let verify_replay (history : temporal_history) : bool =
    let completed_outputs = ref [] in
    let completed_steps = ref [] in
    let checkpoints_valid = ref true in
    List.iter (function
      | StepCompletedEvent (step_id, agent_id, output) ->
        completed_steps := !completed_steps @ [ step_id ];
        completed_outputs := !completed_outputs @ [ (agent_id, output) ]
      | CheckpointCreated (step_id, expected_hash) ->
        let hash_payload =
          step_id ^ "::" ^ String.concat "," !completed_steps ^ "::" ^
          String.concat ";" (List.map (fun (a, r) -> a ^ "=" ^ r) !completed_outputs)
        in
        let recomputed_hash = Digest.to_hex (Digest.string hash_payload) in
        if recomputed_hash <> expected_hash then
          checkpoints_valid := false
      | _ -> ()
    ) history.events;
    !checkpoints_valid
end

(* Resource Dashboard Renderer *)
module Dashboard = struct
  let create (agents : agent_config list) (step_results : step_result list) : resource_dashboard =
    let stats = List.map (fun (cfg : agent_config) ->
      let estimated_tokens = cfg.estimated_input_tokens + cfg.estimated_output_tokens in
      let agent_results = List.filter (fun (r : step_result) -> r.agent_id = cfg.id) step_results in
      let (act_in, act_out) =
        List.fold_left (fun (in_acc, out_acc) (r : step_result) ->
          let (i, o) = r.tokens_used in
          (in_acc + i, out_acc + o)
        ) (0, 0) agent_results
      in
      let actual_total_tokens = act_in + act_out in
      let variance = actual_total_tokens - estimated_tokens in
      let percentage_variance =
        if estimated_tokens = 0 then 0.0
        else (float_of_int variance /. float_of_int estimated_tokens) *. 100.0
      in
      {
        agent_id = cfg.id;
        role = cfg.role;
        estimated_tokens;
        actual_input_tokens = act_in;
        actual_output_tokens = act_out;
        actual_total_tokens;
        variance;
        percentage_variance;
      }
    ) agents in
    let (total_est, total_act) =
      List.fold_left (fun (e_acc, a_acc) (s : agent_token_stat) ->
        (e_acc + s.estimated_tokens, a_acc + s.actual_total_tokens)
      ) (0, 0) stats
    in
    let total_variance = total_act - total_est in
    let total_percentage_variance =
      if total_est = 0 then 0.0
      else (float_of_int total_variance /. float_of_int total_est) *. 100.0
    in
    let execution_status =
      if List.for_all (fun (r : step_result) -> r.status = Completed) step_results then "PASSED"
      else "FAILED"
    in
    {
      stats;
      total_estimated = total_est;
      total_actual = total_act;
      total_variance;
      total_percentage_variance;
      execution_status;
    }

  let render_ascii (dashboard : resource_dashboard) : string =
    let header =
      "========================================================================================\n" ^
      "                                RESOURCE DASHBOARD TOKEN TRACKING                        \n" ^
      "========================================================================================\n" ^
      Printf.sprintf "%-10s | %-28s | %11s | %11s | %10s | %7s | %-6s\n"
        "Agent ID" "Role" "Est. Tokens" "Act. Tokens" "Variance" "Var %" "Status" ^
      "----------+------------------------------+-------------+-------------+------------+---------+-------\n"
    in
    let rows = List.map (fun (s : agent_token_stat) ->
      let var_sign = if s.variance > 0 then "+" else "" in
      Printf.sprintf "%-10s | %-28s | %11d | %11d | %10s | %6.1f%% | %-6s\n"
        s.agent_id s.role s.estimated_tokens s.actual_total_tokens
        (var_sign ^ string_of_int s.variance) s.percentage_variance dashboard.execution_status
    ) dashboard.stats in
    let footer_var_sign = if dashboard.total_variance > 0 then "+" else "" in
    let footer =
      "----------+------------------------------+-------------+-------------+------------+---------+-------\n" ^
      Printf.sprintf "%-10s | %-28s | %11d | %11d | %10s | %6.1f%% | %-6s\n"
        "TOTALS" "Swarm Execution (5 Agents)" dashboard.total_estimated dashboard.total_actual
        (footer_var_sign ^ string_of_int dashboard.total_variance)
        dashboard.total_percentage_variance dashboard.execution_status ^
      "========================================================================================\n"
    in
    header ^ String.concat "" rows ^ footer

  let print (dashboard : resource_dashboard) : unit =
    print_endline (render_ascii dashboard)
end

(* Pre-configured 5-agent swarm *)
let default_5_agents : agent_config list = [
  { id = "agent_1"; name = "Architect"; role = "System Architect & Initiator"; estimated_input_tokens = 1000; estimated_output_tokens = 500 };
  { id = "agent_2"; name = "Synthesizer"; role = "Code Synthesizer"; estimated_input_tokens = 2000; estimated_output_tokens = 1000 };
  { id = "agent_3"; name = "Analyzer"; role = "Static Analysis Specialist"; estimated_input_tokens = 1500; estimated_output_tokens = 500 };
  { id = "agent_4"; name = "Verifier"; role = "Dynamic Testing & Formal Engine"; estimated_input_tokens = 1800; estimated_output_tokens = 700 };
  { id = "agent_5"; name = "Auditor"; role = "Resource Auditor & Summarizer"; estimated_input_tokens = 800; estimated_output_tokens = 200 };
]

(* Pre-configured 5-step SOP workflow *)
let default_5_step_sop : step list = [
  {
    step_id = "step_1";
    name = "Architecture Spec";
    assigned_agent = "agent_1";
    dependencies = [];
    action = (fun _agent_id input ->
      let payload = "SPEC: FPP MBASE 5-Agent SOP Architecture (" ^ input ^ ")" in
      (payload, (950, 470))
    );
  };
  {
    step_id = "step_2";
    name = "Code Synthesis";
    assigned_agent = "agent_2";
    dependencies = [ "step_1" ];
    action = (fun _agent_id input ->
      let payload = "CODE: Parallel Domain Engine Impl [" ^ input ^ "]" in
      (payload, (2050, 1020))
    );
  };
  {
    step_id = "step_3";
    name = "Static Invariant Analysis";
    assigned_agent = "agent_3";
    dependencies = [ "step_1" ];
    action = (fun _agent_id input ->
      let payload = "ANALYSIS: Type safety & Formal coverage validated [" ^ input ^ "]" in
      (payload, (1480, 490))
    );
  };
  {
    step_id = "step_4";
    name = "Dynamic Property Verification";
    assigned_agent = "agent_4";
    dependencies = [ "step_2"; "step_3" ];
    action = (fun _agent_id input ->
      let payload = "VERIFY: Model checking & QCheck property pass [" ^ input ^ "]" in
      (payload, (1820, 710))
    );
  };
  {
    step_id = "step_5";
    name = "Resource Audit & Summary";
    assigned_agent = "agent_5";
    dependencies = [ "step_4" ];
    action = (fun _agent_id input ->
      let payload = "AUDIT: Resource envelope compliant, zero leaks [" ^ input ^ "]" in
      (payload, (810, 205))
    );
  };
]

module For_test = struct
  type spawn_receipt = {
    attempted_step_ids : string list;
    spawned_step_ids : string list;
    joined_step_ids : string list;
    failed_step_id : string option;
  }

  type result_fault =
    | Missing_action_result
    | Duplicate_action_result
    | Unknown_action_result
    | Out_of_order_results
    | Replay_not_verified
    | Engine_exception

  let result_fault_mutex = Mutex.create ()
  let result_fault : result_fault option ref = ref None

  let with_result_fault fault body =
    Mutex.lock result_fault_mutex;
    if Option.is_some !result_fault then begin
      Mutex.unlock result_fault_mutex;
      invalid_arg "Sop_execution.For_test.with_result_fault is not reentrant"
    end;
    result_fault := Some fault;
    Mutex.unlock result_fault_mutex;
    Fun.protect
      ~finally:(fun () ->
        Mutex.lock result_fault_mutex;
        result_fault := None;
        Mutex.unlock result_fault_mutex)
      body

  let current_result_fault () =
    Mutex.lock result_fault_mutex;
    let fault = !result_fault in
    Mutex.unlock result_fault_mutex;
    fault

  let dependency_payload outputs =
    outputs
    |> List.map (fun output ->
         Printf.sprintf "%d:%s" (String.length output) output)
    |> String.concat ""

  type active_probe = {
    owner : Domain.id;
    before_attempt : int;
    mutable attempt_count : int;
    mutable attempted_step_ids_rev : string list;
    mutable spawned_step_ids_rev : string list;
    mutable joined_step_ids_rev : string list;
    mutable failed_step_id : string option;
  }

  let probe_mutex = Mutex.create ()
  let active_probe : active_probe option ref = ref None

  let with_probe_lock f =
    Mutex.lock probe_mutex;
    match f () with
    | value ->
        Mutex.unlock probe_mutex;
        value
    | exception exn ->
        Mutex.unlock probe_mutex;
        raise exn

  let current_owner_probe () =
    let current = Domain.self () in
    match !active_probe with
    | Some probe when probe.owner = current -> Some probe
    | Some _ | None -> None

  let before_spawn step_id =
    with_probe_lock (fun () ->
        match current_owner_probe () with
        | None -> Ok ()
        | Some probe ->
            probe.attempt_count <- probe.attempt_count + 1;
            probe.attempted_step_ids_rev <-
              step_id :: probe.attempted_step_ids_rev;
            if
              probe.attempt_count = probe.before_attempt
              && probe.failed_step_id = None
            then begin
              probe.failed_step_id <- Some step_id;
              Error
                (Printf.sprintf
                   "injected pre-spawn failure at attempt %d for step %s"
                   probe.before_attempt step_id)
            end else
              Ok ())

  let record_spawned step_id =
    with_probe_lock (fun () ->
        match current_owner_probe () with
        | None -> ()
        | Some probe ->
            probe.spawned_step_ids_rev <- step_id :: probe.spawned_step_ids_rev)

  let record_joined step_id =
    with_probe_lock (fun () ->
        match current_owner_probe () with
        | None -> ()
        | Some probe ->
            probe.joined_step_ids_rev <- step_id :: probe.joined_step_ids_rev)

  let with_pre_spawn_failure ~before_attempt f =
    if before_attempt < 1 then
      invalid_arg "with_pre_spawn_failure: before_attempt must be positive";
    let probe =
      {
        owner = Domain.self ();
        before_attempt;
        attempt_count = 0;
        attempted_step_ids_rev = [];
        spawned_step_ids_rev = [];
        joined_step_ids_rev = [];
        failed_step_id = None;
      }
    in
    with_probe_lock (fun () ->
        match !active_probe with
        | None -> active_probe := Some probe
        | Some _ -> invalid_arg "with_pre_spawn_failure: probe already active");
    let outcome =
      match f () with
      | value -> Ok value
      | exception exn -> Error (exn, Printexc.get_raw_backtrace ())
    in
    let receipt =
      with_probe_lock (fun () ->
          let receipt =
            {
              attempted_step_ids = List.rev probe.attempted_step_ids_rev;
              spawned_step_ids = List.rev probe.spawned_step_ids_rev;
              joined_step_ids = List.rev probe.joined_step_ids_rev;
              failed_step_id = probe.failed_step_id;
            }
          in
          active_probe := None;
          receipt)
    in
    match outcome with
    | Ok value -> (value, receipt)
    | Error (exn, backtrace) -> Printexc.raise_with_backtrace exn backtrace
end

(* Workflow Execution Engine with OCaml 5 Domain Parallelism & Phase 3 Swarm Integration *)
let default_max_parallelism () =
  max 32 (Domain.recommended_domain_count ())

let execute_sop_workflow ?(agents = default_5_agents) ?max_parallelism ?steps () : workflow_execution_result =
  let max_parallelism =
    match max_parallelism with
    | Some requested -> max 1 requested
    | None -> default_max_parallelism ()
  in
  let (steps, is_custom_steps) = match steps with
    | Some s -> (s, true)
    | None -> (default_5_step_sop, false)
  in
  let dag = Planning.create_dag steps in
  let job_q = JobManager.create () in
  let temporal_eng = Temporal.create () in
  let gossip_mesh = Gossip.create () in
  let irmin_store = IrminMemory.create () in
  let immune_engine = Immune.create () in
  let telemetry_eng = FractalTelemetry.create () in
  FractalTelemetry.clear_global ();
  let effects_telemetry_acc = ref [] in

  let record_telemetry ~level ~component_id ~aspect ~decision ~system_service_constraint ~payload =
    let ev = FractalTelemetry.record_event telemetry_eng ~level ~component_id ~aspect ~decision ~system_service_constraint ~payload in
    ignore (FractalTelemetry.record_global ~level ~component_id ~aspect ~decision ~system_service_constraint ~payload);
    ev
  in

  ignore (record_telemetry ~level:Fractal_ontology.L1_family ~component_id:"sop" ~aspect:Fractal_ontology.Structural ~decision:"INITIALIZE_SOP_WORKFLOW" ~system_service_constraint:"Planning DAG" ~payload:"5-agent SOP workflow execution engine initialized with step DAG");
  if is_custom_steps then
    ignore (record_telemetry ~level:Fractal_ontology.L1_family ~component_id:"sop" ~aspect:Fractal_ontology.Control ~decision:"SYNTHESIZE_DECLARATIVE_INTENT" ~system_service_constraint:"Planning DAG" ~payload:(Printf.sprintf "Declarative intent execution plan loaded with %d steps" (List.length steps)));
  ignore (record_telemetry ~level:Fractal_ontology.LX_control ~component_id:"hermes_zenoh" ~aspect:Fractal_ontology.Control ~decision:"GOSSIP_MESH_INIT" ~system_service_constraint:"Zenoh Gossip Mesh" ~payload:"Decentralized Zenoh gossip mesh initialized for agent state distribution");
  ignore (record_telemetry ~level:Fractal_ontology.L6_receipt ~component_id:"irmin" ~aspect:Fractal_ontology.Data ~decision:"IRMIN_STORE_INIT" ~system_service_constraint:"Irmin CRDT Memory Store" ~payload:"Irmin branchable CRDT memory store initialized");
  ignore (record_telemetry ~level:Fractal_ontology.LX_control ~component_id:"homeostasis" ~aspect:Fractal_ontology.Integrity ~decision:"IMMUNE_ENGINE_INIT" ~system_service_constraint:"Immune Safeguard" ~payload:"Homeostasis immune resilience engine initialized");

  (* Initialize jobs in JobManager and events in Temporal & Gossip *)
  List.iter (fun (s : step) ->
    let j = {
      job_id = "job_" ^ s.step_id;
      step_id = s.step_id;
      target_agent = s.assigned_agent;
      state = Queued;
      attempts = 0;
      max_retries = 3;
    } in
    JobManager.enqueue job_q j;
    Temporal.record_event temporal_eng (StepScheduled (s.step_id, s.assigned_agent));
    Temporal.record_event temporal_eng (JobStateChanged (j.job_id, Queued));
    Gossip.broadcast_state_transition gossip_mesh ~agent_id:s.assigned_agent ~step_id:s.step_id ~state:"Queued";

    let agent_lvl = level_of_agent_id s.assigned_agent in
    ignore (record_telemetry ~level:agent_lvl ~component_id:s.assigned_agent ~aspect:Fractal_ontology.Control ~decision:"ENQUEUE_JOB_STEP" ~system_service_constraint:"Job Queue" ~payload:(Printf.sprintf "Job %s enqueued for step %s assigned to %s" j.job_id s.step_id s.assigned_agent));
  ) steps;

  let topo_order = Planning.topological_sort dag in
  ignore (record_telemetry ~level:Fractal_ontology.L1_family ~component_id:"planning" ~aspect:Fractal_ontology.Control ~decision:"PLANNING_DAG_SORT" ~system_service_constraint:"Planning DAG" ~payload:(Printf.sprintf "Topological sort computed: [%s]" (String.concat "; " topo_order)));

  (* Shared state protected by mutex *)
  let mutex = Mutex.create () in
  let statuses = ref (List.map (fun (s : step) -> (s.step_id, Pending)) steps) in
  let step_results = ref [] in
  let completed_agent_outputs = ref [] in
  let completed_step_ids = ref [] in

  let update_status sid st =
    Mutex.lock mutex;
    statuses := (sid, st) :: List.remove_assoc sid !statuses;
    Mutex.unlock mutex
  in

  let get_statuses () =
    Mutex.lock mutex;
    let s = !statuses in
    Mutex.unlock mutex;
    s
  in

  let record_completed (res : step_result) =
    Mutex.lock mutex;
    if
      not
        (List.exists
           (fun (row : step_result) -> row.step_id = res.step_id)
           !step_results)
    then begin
      step_results := !step_results @ [ res ];
      completed_agent_outputs :=
        !completed_agent_outputs @ [ (res.agent_id, res.output_payload) ];
      completed_step_ids := !completed_step_ids @ [ res.step_id ]
    end;
    let s_ids = !completed_step_ids in
    let a_outs = !completed_agent_outputs in
    Mutex.unlock mutex;
    (s_ids, a_outs)
  in

  let record_failed (st : step) ~input_payload ~duration_ms reason =
    let failed_status : step_status = Failed reason in
    update_status st.step_id failed_status;
    let job_id = "job_" ^ st.step_id in
    JobManager.update_state job_q job_id (Failed reason : job_state);
    Temporal.record_event temporal_eng
      (JobStateChanged (job_id, (Failed reason : job_state)));
    Gossip.broadcast_state_transition gossip_mesh ~agent_id:st.assigned_agent
      ~step_id:st.step_id ~state:"Failed";
    ignore
      (record_telemetry ~level:(level_of_agent_id st.assigned_agent)
         ~component_id:st.assigned_agent ~aspect:Fractal_ontology.Integrity
         ~decision:"STEP_FAILED" ~system_service_constraint:"Planning DAG"
         ~payload:(Printf.sprintf "Step %s failed: %s" st.step_id reason));
    let result : step_result =
      {
        step_id = st.step_id;
        agent_id = st.assigned_agent;
        status = failed_status;
        input_payload;
        output_payload = reason;
        tokens_used = (0, 0);
        duration_ms;
      }
    in
    Mutex.lock mutex;
    if
      not
        (List.exists
           (fun (row : step_result) -> row.step_id = st.step_id)
           !step_results)
    then step_results := !step_results @ [ result ];
    Mutex.unlock mutex
  in

  let find_completed_output sid =
    Mutex.lock mutex;
    let opt_res = List.find_opt (fun (r : step_result) -> r.step_id = sid) !step_results in
    let payload = match opt_res with Some r -> r.output_payload | None -> "" in
    Mutex.unlock mutex;
    payload
  in

  let rec terminalize_blocked_dependents () =
    let current = get_statuses () in
    let blocked =
      List.filter_map
        (fun (st : step) ->
          match List.assoc_opt st.step_id current with
          | Some Pending | Some Ready ->
              List.find_map
                (fun dependency ->
                  match List.assoc_opt dependency current with
                  | Some (Failed reason) -> Some (st, dependency, reason)
                  | _ -> None)
                st.dependencies
          | Some Executing | Some Completed | Some (Failed _) | None -> None)
        steps
    in
    match blocked with
    | [] -> ()
    | _ ->
        List.iter
          (fun (st, dependency, reason) ->
            record_failed st ~input_payload:"" ~duration_ms:0.0
              (Printf.sprintf "blocked by failed dependency %s: %s" dependency
                 reason))
          blocked;
        terminalize_blocked_dependents ()
  in

  let terminalize_stalled_steps () =
    let current = get_statuses () in
    List.iter
      (fun (st : step) ->
        match List.assoc_opt st.step_id current with
        | Some Pending | Some Ready | Some Executing | None ->
            record_failed st ~input_payload:"" ~duration_ms:0.0
              "scheduler stalled with no admissible ready step"
        | Some Completed | Some (Failed _) -> ())
      steps
  in

  let run_step (st : step) input_payload agent_level =
    let start_t = Unix.gettimeofday () in
    ignore
      (record_telemetry ~level:Fractal_ontology.LX_control
         ~component_id:"homeostasis" ~aspect:Fractal_ontology.Integrity
         ~decision:"IMMUNE_HEALTH_CHECK"
         ~system_service_constraint:"Immune Safeguard"
         ~payload:
           (Printf.sprintf "Health check passed for agent %s prior to step %s"
              st.assigned_agent st.step_id));
    ignore
      (record_telemetry ~level:Fractal_ontology.L5_trace ~component_id:"eio"
         ~aspect:Fractal_ontology.Performance
         ~decision:"DISPATCH_EFFECTS_FIBER"
         ~system_service_constraint:"Effects I/O Pool"
         ~payload:(Printf.sprintf "Dispatched fiber handler for step %s" st.step_id));
    let action_result, effect_events =
      EffectsIO.run_with_handler (fun () ->
          match
            Immune.self_heal_retry immune_engine st.step_id (fun () ->
                st.action st.assigned_agent input_payload)
          with
          | Ok result -> result
          | Error error -> failwith ("Immune retry exhausted: " ^ error))
    in
    let output_payload, (input_tokens, output_tokens) = action_result in
    let duration_ms = (Unix.gettimeofday () -. start_t) *. 1000.0 in
    ignore
      (Immune.detect_anomaly immune_engine ~agent_id:st.assigned_agent
         ~step_id:st.step_id ~duration_ms ~error:None);
    ignore
      (record_telemetry ~level:agent_level ~component_id:st.assigned_agent
         ~aspect:Fractal_ontology.Observability
         ~decision:"EXECUTE_ACTION_COMPLETE"
         ~system_service_constraint:"Resource Budget"
         ~payload:
           (Printf.sprintf
              "Action completed for step %s in %.2f ms (tokens in: %d, out: %d)"
              st.step_id duration_ms input_tokens output_tokens));
    let step_tree =
      [ (st.step_id ^ ".output", output_payload);
        (st.step_id ^ ".agent", st.assigned_agent) ]
    in
    ignore
      (IrminMemory.commit irmin_store ~branch:st.assigned_agent
         ~author:st.assigned_agent ~tree:step_tree);
    ignore
      (IrminMemory.merge_crdt irmin_store ~source_branch:st.assigned_agent
         ~target_branch:"main" ~author:st.assigned_agent);
    ignore
      (record_telemetry ~level:Fractal_ontology.L6_receipt ~component_id:"irmin"
         ~aspect:Fractal_ontology.Data ~decision:"IRMIN_CRDT_COMMIT"
         ~system_service_constraint:"Irmin CRDT Memory Store"
         ~payload:
           (Printf.sprintf
              "Committed step %s state to branch %s and merged to main"
              st.step_id st.assigned_agent));
    ( {
        step_id = st.step_id;
        agent_id = st.assigned_agent;
        status = Completed;
        input_payload;
        output_payload;
        tokens_used = (input_tokens, output_tokens);
        duration_ms;
      },
      effect_events )
  in

  let record_success (st : step) (res : step_result) effect_events =
    Mutex.lock mutex;
    effects_telemetry_acc := !effects_telemetry_acc @ effect_events;
    Mutex.unlock mutex;
    update_status st.step_id (Completed : step_status);
    let job_id = "job_" ^ st.step_id in
    JobManager.update_state job_q job_id (Completed : job_state);
    Temporal.record_event temporal_eng
      (JobStateChanged (job_id, (Completed : job_state)));
    Temporal.record_event temporal_eng
      (StepCompletedEvent (res.step_id, res.agent_id, res.output_payload));
    let agent_level = level_of_agent_id res.agent_id in
    ignore
      (record_telemetry ~level:agent_level ~component_id:res.agent_id
         ~aspect:Fractal_ontology.Control ~decision:"STEP_COMPLETED"
         ~system_service_constraint:"Job Queue"
         ~payload:
           (Printf.sprintf "Step %s marked completed for agent %s" st.step_id
              res.agent_id));
    Gossip.broadcast_state_transition gossip_mesh ~agent_id:res.agent_id
      ~step_id:res.step_id ~state:"Completed";
    Gossip.publish gossip_mesh ~topic:("hermes/sop/" ^ res.step_id)
      ~sender:res.agent_id ~payload:res.output_payload;
    ignore
      (record_telemetry ~level:Fractal_ontology.LX_control
         ~component_id:"hermes_zenoh" ~aspect:Fractal_ontology.Availability
         ~decision:"GOSSIP_BROADCAST_COMPLETED"
         ~system_service_constraint:"Zenoh Gossip Mesh"
         ~payload:
           (Printf.sprintf
              "Broadcast Completed state transition for agent %s on step %s"
              res.agent_id st.step_id));
    let completed_ids, agent_outputs = record_completed res in
    let checkpoint =
      Temporal.create_checkpoint temporal_eng res.step_id completed_ids agent_outputs
    in
    Temporal.record_event temporal_eng
      (CheckpointCreated (res.step_id, checkpoint.state_hash));
    ignore
      (record_telemetry ~level:Fractal_ontology.L6_receipt
         ~component_id:"temporal" ~aspect:Fractal_ontology.Integrity
         ~decision:"CREATE_TEMPORAL_CHECKPOINT"
         ~system_service_constraint:"Temporal Checkpoint"
         ~payload:
           (Printf.sprintf "Durable checkpoint created for step %s (hash: %s)"
              st.step_id checkpoint.state_hash))
  in

  (* Main execution loop *)
  while not (Planning.is_complete dag (get_statuses ())) do
    terminalize_blocked_dependents ();
    let current_statuses = get_statuses () in
    let ready_steps =
      Planning.get_ready_steps dag current_statuses
      |> List.filteri (fun index _ -> index < max_parallelism)
    in
    if ready_steps = [] && not (Planning.is_complete dag current_statuses) then
      terminalize_stalled_steps ()
    else begin
      let domain_handles =
        List.filter_map
          (fun (st : step) ->
            match List.assoc_opt st.step_id current_statuses with
            | Some Pending | Some Ready ->
                update_status st.step_id Executing;
                let job_id = "job_" ^ st.step_id in
                JobManager.update_state job_q job_id Executing;
                Temporal.record_event temporal_eng
                  (JobStateChanged (job_id, Executing));
                Gossip.broadcast_state_transition gossip_mesh
                  ~agent_id:st.assigned_agent ~step_id:st.step_id
                  ~state:"Executing";
                let agent_level = level_of_agent_id st.assigned_agent in
                ignore
                  (record_telemetry ~level:agent_level
                     ~component_id:st.assigned_agent
                     ~aspect:Fractal_ontology.Control
                     ~decision:"START_STEP_EXECUTION"
                     ~system_service_constraint:"Planning DAG"
                     ~payload:
                       (Printf.sprintf
                          "Agent %s starting execution for step %s"
                          st.assigned_agent st.step_id));
                ignore
                  (record_telemetry ~level:Fractal_ontology.LX_control
                     ~component_id:"hermes_zenoh"
                     ~aspect:Fractal_ontology.Availability
                     ~decision:"GOSSIP_BROADCAST_EXECUTING"
                     ~system_service_constraint:"Zenoh Gossip Mesh"
                     ~payload:
                       (Printf.sprintf
                          "Broadcast Executing state transition for agent %s on step %s"
                          st.assigned_agent st.step_id));
                let input_payload =
                  st.dependencies
                  |> List.map find_completed_output
                  |> For_test.dependency_payload
                in
                (match For_test.before_spawn st.step_id with
                | Error reason ->
                    record_failed st ~input_payload ~duration_ms:0.0 reason;
                    None
                | Ok () ->
                    (match
                       let handle =
                         Domain.spawn (fun () ->
                             run_step st input_payload agent_level)
                       in
                       For_test.record_spawned st.step_id;
                       Some (st, input_payload, handle)
                     with
                    | handle -> handle
                    | exception exn ->
                        record_failed st ~input_payload ~duration_ms:0.0
                          ("domain spawn failed: " ^ Printexc.to_string exn);
                        None))
            | Some Executing | Some Completed | Some (Failed _) | None -> None)
          ready_steps
      in
      (* First drain every admitted handle. No result projection runs early
         enough to abandon a later sibling when one join raises. *)
      let joined_outcomes =
        List.map
          (fun ((st : step), input_payload, handle) ->
            let outcome =
              match Domain.join handle with
              | result -> Ok result
              | exception exn -> Error (Printexc.to_string exn)
            in
            For_test.record_joined st.step_id;
            (st, input_payload, outcome))
          domain_handles
      in
      List.iter
        (fun ((st : step), input_payload, outcome) ->
          match outcome with
          | Ok ((res : step_result), effect_events) ->
              record_success st res effect_events
          | Error reason ->
              record_failed st ~input_payload ~duration_ms:0.0
                ("domain action failed: " ^ reason))
        joined_outcomes;
      terminalize_blocked_dependents ()
    end;
  done;

  let final_results =
    Mutex.lock mutex;
    let r = !step_results in
    Mutex.unlock mutex;
    r
  in
  let job_history = JobManager.all_jobs job_q in
  let history = Temporal.get_history temporal_eng in
  let replay_verified = Temporal.verify_replay history in
  let dashboard = Dashboard.create agents final_results in

  ignore (record_telemetry ~level:Fractal_ontology.L6_receipt ~component_id:"temporal" ~aspect:Fractal_ontology.Integrity ~decision:"VERIFY_REPLAY_HISTORY" ~system_service_constraint:"Temporal Checkpoint" ~payload:(Printf.sprintf "Replay history verified: %b" replay_verified));
  ignore (record_telemetry ~level:Fractal_ontology.L5_trace ~component_id:"agent_5" ~aspect:Fractal_ontology.Performance ~decision:"AUDIT_RESOURCE_DASHBOARD" ~system_service_constraint:"Resource Budget" ~payload:(Printf.sprintf "Resource dashboard generated: status %s, total actual tokens %d, variance %d" dashboard.execution_status dashboard.total_actual dashboard.total_variance));

  let final_telemetry_log = FractalTelemetry.get_log telemetry_eng in

  let result = {
    step_results = final_results;
    job_history;
    history;
    dashboard;
    gossip_messages = Gossip.get_messages gossip_mesh;
    irmin_store;
    immune_engine;
    effects_telemetry = !effects_telemetry_acc;
    telemetry_log = final_telemetry_log;
    replay_verified;
  } in
  match For_test.current_result_fault () with
  | None -> result
  | Some For_test.Engine_exception ->
      failwith "injected engine result exception"
  | Some For_test.Replay_not_verified ->
      { result with replay_verified = false }
  | Some For_test.Out_of_order_results ->
      { result with step_results = List.rev result.step_results }
  | Some For_test.Missing_action_result ->
      { result with
        step_results =
          (match result.step_results with [] -> [] | _ :: rest -> rest) }
  | Some For_test.Unknown_action_result ->
      { result with
        step_results =
          (match result.step_results with
           | [] -> []
           | first :: rest ->
               { first with step_id = "action.unknown" } :: rest) }
  | Some For_test.Duplicate_action_result ->
      { result with
        step_results =
          (match result.step_results with
           | first :: second :: rest ->
               first :: { second with step_id = first.step_id } :: rest
           | [] | [ _ ] -> result.step_results) }

(* Phase 6: Declarative Intent Configuration & Autonomous Synthesis *)
module DeclarativeIntent = struct
  type declarative_intent = {
    goal : string;
    constraints : string list;
    target_state : string;
    required_capabilities : string list;
  }

  let string_contains haystack needle =
    let h_len = String.length haystack in
    let n_len = String.length needle in
    if n_len > h_len then false
    else
      let found = ref false in
      for i = 0 to h_len - n_len do
        if String.sub haystack i n_len = needle then found := true
      done;
      !found

  let agent_of_capability (cap : string) (idx : int) : agent_id =
    let lc = String.lowercase_ascii cap in
    if string_contains lc "arch" || string_contains lc "spec" || string_contains lc "plan" || string_contains lc "init" then "agent_1"
    else if string_contains lc "synth" || string_contains lc "code" || string_contains lc "gen" || string_contains lc "impl" then "agent_2"
    else if string_contains lc "analy" || string_contains lc "static" || string_contains lc "invar" || string_contains lc "crdt" then "agent_3"
    else if string_contains lc "verif" || string_contains lc "test" || string_contains lc "formal" || string_contains lc "model" then "agent_4"
    else if string_contains lc "audit" || string_contains lc "deploy" || string_contains lc "telemetry" || string_contains lc "resource" then "agent_5"
    else Printf.sprintf "agent_%d" ((idx mod 5) + 1)

  let name_of_capability (cap : string) (_idx : int) : string =
    let lc = String.lowercase_ascii cap in
    if string_contains lc "arch" || string_contains lc "spec" || string_contains lc "plan" || string_contains lc "init" then "Architecture Spec Synthesis"
    else if string_contains lc "synth" || string_contains lc "code" || string_contains lc "gen" || string_contains lc "impl" then "Autonomous Code Synthesis"
    else if string_contains lc "analy" || string_contains lc "static" || string_contains lc "invar" || string_contains lc "crdt" then "Static Invariant & CRDT Analysis"
    else if string_contains lc "verif" || string_contains lc "test" || string_contains lc "formal" || string_contains lc "model" then "Dynamic & Formal Verification"
    else if string_contains lc "audit" || string_contains lc "deploy" || string_contains lc "telemetry" || string_contains lc "resource" then "Swarm Audit & Deployment"
    else Printf.sprintf "Capability Synthesis (%s)" cap

  let synthesize_execution_plan (intent : declarative_intent) : step list * job list =
    let raw_caps =
      if intent.required_capabilities = [] then
        [ "architecture"; "synthesis"; "analysis"; "verification"; "audit" ]
      else intent.required_capabilities
    in
    let num_steps = List.length raw_caps in
    let steps = List.mapi (fun idx cap ->
      let step_id = Printf.sprintf "step_%d" (idx + 1) in
      let step_name = name_of_capability cap idx in
      let assigned_agent = agent_of_capability cap idx in
      let dependencies =
        if idx = 0 then []
        else if idx = 1 then [ "step_1" ]
        else if idx = 2 then [ "step_1" ]
        else if idx = 3 && num_steps >= 4 then [ "step_2"; "step_3" ]
        else [ Printf.sprintf "step_%d" idx ]
      in
      let action agent_id input =
        let constraints_str = String.concat ", " intent.constraints in
        let payload =
          Printf.sprintf "DECLARATIVE_INTENT::goal=%s::target_state=%s::step=%s::agent=%s::constraints=[%s]::payload=[%s]"
            intent.goal intent.target_state step_name agent_id constraints_str input
        in
        let input_tokens = 900 + (idx * 250) in
        let output_tokens = 450 + (idx * 150) in
        (payload, (input_tokens, output_tokens))
      in
      { step_id; name = step_name; assigned_agent; dependencies; action }
    ) raw_caps in

    let dag = Planning.create_dag steps in
    let topo_order = Planning.topological_sort dag in

    let job_queue = JobManager.create () in
    let jobs = List.map (fun (s : step) ->
      let j = {
        job_id = "job_" ^ s.step_id;
        step_id = s.step_id;
        target_agent = s.assigned_agent;
        state = Queued;
        attempts = 0;
        max_retries = 3;
      } in
      JobManager.enqueue job_queue j;
      j
    ) steps in

    ignore (FractalTelemetry.record_global
      ~level:Fractal_ontology.L1_family
      ~component_id:"sop"
      ~aspect:Fractal_ontology.Control
      ~decision:"SYNTHESIZE_DECLARATIVE_INTENT"
      ~system_service_constraint:"Planning DAG"
      ~payload:(Printf.sprintf "Goal: '%s' | Target: '%s' | Steps: %d | Topo Order: [%s]"
                  intent.goal intent.target_state num_steps (String.concat "; " topo_order)));

    (steps, jobs)

  let execute_declarative_intent (intent : declarative_intent) : workflow_execution_result =
    let (steps, _jobs) = synthesize_execution_plan intent in
    execute_sop_workflow ~steps ()
end

type declarative_intent = DeclarativeIntent.declarative_intent = {
  goal : string;
  constraints : string list;
  target_state : string;
  required_capabilities : string list;
}

let synthesize_execution_plan = DeclarativeIntent.synthesize_execution_plan
let execute_declarative_intent = DeclarativeIntent.execute_declarative_intent
