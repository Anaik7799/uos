open Core

(** Full Planning & Task Management.
    Hierarchical epic/story tracking and constraint resolution. *)

type task_type = 
  | Epic
  | Story
  | Bug
  | Subtask
  [@@deriving sexp]

type plan_node = {
  id: string;
  parent_id: string option;
  task_type: task_type;
  title: string;
  estimate_points: int option;
  dependencies: string list; (* IDs of blockers *)
} [@@deriving sexp]

type t = plan_node String.Map.t

let empty : t = String.Map.empty

let add_node state node =
  Map.set state ~key:node.id ~data:node

(** Resolves the execution order by doing a topological sort over dependencies.
    Returns Ok (ordered_ids) or Error if a cycle is detected. *)
let execution_plan state =
  (* A naive DAG resolution representing high-level planning constraint satisfaction *)
  let rec resolve resolved pending =
    if Map.is_empty pending then Ok (List.rev resolved)
    else
      (* Find nodes whose dependencies are all in the 'resolved' list *)
      let ready = Map.filter pending ~f:(fun node ->
        List.for_all node.dependencies ~f:(fun dep -> List.mem resolved dep ~equal:String.equal)
      ) in
      if Map.is_empty ready then
        Error "Cyclic dependencies detected in planning DAG"
      else
        let newly_resolved = Map.keys ready in
        let new_pending = Map.filter_keys pending ~f:(fun k -> not (List.mem newly_resolved k ~equal:String.equal)) in
        resolve (newly_resolved @ resolved) new_pending
  in
  resolve [] state

(** Bridges the Planning system into the Oban Job Queue *)
let dispatch_plan_to_queue state ~queue_name =
  match execution_plan state with
  | Error e -> Error e
  | Ok ordered_ids ->
      let jobs = List.map ordered_ids ~f:(fun id ->
        Sa_plan_oban.insert ~queue:queue_name ~worker:"PlanningWorker" ~args:id ~max_attempts:3
      ) in
      Ok jobs
