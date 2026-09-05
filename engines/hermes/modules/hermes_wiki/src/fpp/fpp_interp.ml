(* The FPP simulator. See fpp_interp.mli for the semantics contract. *)

open Fpp_model

type machine_state = { current : string; log : string list }

let init machine =
  match machine with
  | External_machine { machine_name } ->
      Error ("state machine " ^ machine_name ^ " is external: no behavior to interpret")
  | Internal_machine { initial = actions, target; _ } ->
      Ok { current = target; log = actions }

let guard_holds guards name = List.assoc_opt name guards = Some true

(* Resolve a target through the choice graph, accumulating arc actions.
   Fuel bounds the walk: a validated machine's choice graph is acyclic, but
   the interpreter must be total on ANY machine (fuzz feeds it garbage). *)
let rec resolve ~states ~choices guards fuel acc = function
  | To_state s -> (
      match List.find_opt (fun st -> st.state_name = s) states with
      | Some state -> Ok (state, acc)
      | None -> Error ("target state " ^ s ^ " is not defined"))
  | To_choice c -> (
      if fuel <= 0 then Error "choice resolution exceeded fuel (cycle?)"
      else
        match List.find_opt (fun ch -> ch.choice_name = c) choices with
        | None -> Error ("choice " ^ c ^ " is not defined")
        | Some choice ->
            let actions, target =
              if guard_holds guards choice.choice_guard then choice.if_true
              else choice.if_false
            in
            resolve ~states ~choices guards (fuel - 1) (acc @ actions) target)

let dispatch ~machine ~guards state signal =
  match machine with
  | External_machine { machine_name } ->
      Error ("state machine " ^ machine_name ^ " is external: no behavior to interpret")
  | Internal_machine { machine_name; signals; states; choices; _ } -> (
      if not (List.exists (fun s -> s.signal_name = signal) signals) then
        Error ("signal " ^ signal ^ " is not defined on " ^ machine_name)
      else
        match List.find_opt (fun s -> s.state_name = state.current) states with
        | None -> Error ("current state " ^ state.current ^ " is not defined")
        | Some source -> (
            match
              List.find_opt (fun t -> t.on_signal = signal) source.transitions
            with
            | None -> Ok state (* unhandled: dropped, spec semantics *)
            | Some transition -> (
                match transition.guard with
                | Some g when not (guard_holds guards g) -> Ok state
                | _ -> (
                    match
                      resolve ~states ~choices guards
                        (List.length choices + 1)
                        transition.do_actions transition.target
                    with
                    | Error e -> Error e
                    | Ok (target_state, actions) ->
                        Ok
                          { current = target_state.state_name;
                            log =
                              state.log @ source.exit_ @ actions
                              @ target_state.entry }))))

(* ------------------------------------------------------- command queues *)

type queue = { capacity : int; depth : int; dropped : int }

let empty_queue ~capacity = { capacity; depth = 0; dropped = 0 }

type dispatch_result =
  | Executed
  | Enqueued of queue
  | Dropped of queue
  | Blocked
  | Assert_failed

let send_command model ~instance ~opcode ~queue =
  match List.find_opt (fun i -> i.inst_name = instance) model.instances with
  | None -> Error ("unknown instance " ^ instance)
  | Some i -> (
      match
        List.find_opt (fun c -> c.comp_name = i.of_component) model.components
      with
      | None -> Error ("unknown component " ^ i.of_component)
      | Some c ->
          let relative = opcode - i.base_id in
          if relative < 0 || relative >= id_span c then
            Error
              (Printf.sprintf "opcode 0x%X is outside %s's id window" opcode instance)
          else if
            List.exists
              (fun p -> p.set_opcode = relative || p.save_opcode = relative)
              c.parameters
          then Ok Executed
          else (
            match List.find_opt (fun cmd -> cmd.opcode = relative) c.commands with
            | None -> Error (Printf.sprintf "unknown opcode 0x%X on %s" opcode instance)
            | Some cmd -> (
                match cmd.cmd_kind with
                | Sync_cmd | Guarded_cmd -> Ok Executed
                | Async_cmd { queue_full; _ } -> (
                    match queue with
                    | None -> Error ("async command " ^ cmd.cmd_name ^ " needs a queue")
                    | Some q ->
                        if q.depth < q.capacity then
                          Ok (Enqueued { q with depth = q.depth + 1 })
                        else (
                          match queue_full with
                          | Assert -> Ok Assert_failed
                          | Block -> Ok Blocked
                          | Drop -> Ok (Dropped { q with dropped = q.dropped + 1 }))))))
