open Core

(** Temporal-style Durable Workflow Execution.
    Workflows are state machines that event-source their transitions. 
    If the harness crashes, workflows resume from the last completed Activity. *)

type activity_id = string [@@deriving sexp, compare]

type event =
  | WorkflowStarted
  | ActivityScheduled of activity_id
  | ActivityCompleted of activity_id * string (* result payload *)
  | ActivityFailed of activity_id * string (* error payload *)
  | WorkflowCompleted of string
  [@@deriving sexp]

type workflow_state = {
  workflow_id: string;
  history: event list;
  is_completed: bool;
}

(** Start a durable workflow execution *)
let start_workflow ~id =
  { workflow_id = id; history = [WorkflowStarted]; is_completed = false }

(** Apply an event to rebuild state (Event Sourcing) *)
let apply_event state event =
  let is_completed = match event with
    | WorkflowCompleted _ -> true
    | _ -> state.is_completed
  in
  { state with history = event :: state.history; is_completed }

(** Execute an activity durably. 
    If the activity is already in the history as Completed, it returns the cached result 
    without running the function, ensuring exactly-once execution despite crashes. *)
let execute_activity state ~activity_id ~f =
  (* Check history to see if it already completed *)
  let already_completed = List.find_map state.history ~f:(function
    | ActivityCompleted (id, res) when String.equal id activity_id -> Some (Ok res)
    | ActivityFailed (id, err) when String.equal id activity_id -> Some (Error err)
    | _ -> None
  ) in
  match already_completed with
  | Some result -> (state, result)
  | None ->
      (* We must actually run it *)
      let state = apply_event state (ActivityScheduled activity_id) in
      try
        let result = f () in
        let state = apply_event state (ActivityCompleted (activity_id, result)) in
        (state, Ok result)
      with ex ->
        let err = Exn.to_string ex in
        let state = apply_event state (ActivityFailed (activity_id, err)) in
        (state, Error err)

let complete_workflow state ~result =
  apply_event state (WorkflowCompleted result)
