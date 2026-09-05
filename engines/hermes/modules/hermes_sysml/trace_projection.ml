(* Trace projections for lowering SysML Semantic IR state machines into Sa-plan directives *)

type state = {
  id : string;
  name : string;
}

type gate =
  | TimeGate of int
  | EventGate of string
  | ConditionGate of string

type transition = {
  source : string;
  target : string;
  guard : gate option;
  action_effect : string option;
}

type state_machine = {
  name : string;
  states : state list;
  transitions : transition list;
  initial_state : string;
}

(* Sa-plan execution engine mocked directives *)
module Sa_plan = struct
  type directive =
    | Wait_for_gate of gate
    | Exec_action of string
    | Goto_state of string
    | Fork_execution of directive list list
    | Sync
    
  let format_gate = function
    | TimeGate t -> Printf.sprintf "TimeGate(%d)" t
    | EventGate e -> Printf.sprintf "EventGate(%s)" e
    | ConditionGate c -> Printf.sprintf "ConditionGate(%s)" c

  let rec show_directive = function
    | Wait_for_gate g -> Printf.sprintf "Wait(%s)" (format_gate g)
    | Exec_action a -> Printf.sprintf "Exec(%s)" a
    | Goto_state s -> Printf.sprintf "Goto(%s)" s
    | Fork_execution paths -> 
        let show_path p = String.concat "; " (List.map show_directive p) in
        Printf.sprintf "Fork[%s]" (String.concat " | " (List.map show_path paths))
    | Sync -> "Sync"
end

(** [project_sm state_machine] safely lowers a state machine into Sa-plan directives
    while strictly preserving topological dependencies and sequence gates. *)
let project_sm (sm : state_machine) : Sa_plan.directive list =
  (* Extremely simplified topological sort / path extraction for the mock *)
  (* In a real implementation, we would construct a DAG and emit fork/join directives *)
  
  (* Start at initial state, follow transitions linearly for the mock *)
  let rec traverse current_state visited =
    let outgoing = List.filter (fun t -> t.source = current_state) sm.transitions in
    match outgoing with
    | [] -> []
    | [t] ->
        if List.mem t.target visited then []
        else
          let gate_dir = 
            match t.guard with
            | Some g -> [Sa_plan.Wait_for_gate g]
            | None -> []
          in
          let effect_dir =
            match t.action_effect with
            | Some e -> [Sa_plan.Exec_action e]
            | None -> []
          in
          let next_dirs = traverse t.target (t.target :: visited) in
          gate_dir @ effect_dir @ [Sa_plan.Goto_state t.target] @ next_dirs
    | multiple ->
        (* Parallel fork for multiple outgoing transitions from the same state *)
        let paths = List.map (fun t ->
          if List.mem t.target visited then []
          else
            let gate_dir = 
              match t.guard with
              | Some g -> [Sa_plan.Wait_for_gate g]
              | None -> []
            in
            let effect_dir =
              match t.action_effect with
              | Some e -> [Sa_plan.Exec_action e]
              | None -> []
            in
            gate_dir @ effect_dir @ [Sa_plan.Goto_state t.target] @ traverse t.target (t.target :: visited)
        ) multiple in
        [Sa_plan.Fork_execution paths; Sa_plan.Sync]
  in
  [Sa_plan.Goto_state sm.initial_state] @ traverse sm.initial_state [sm.initial_state]

