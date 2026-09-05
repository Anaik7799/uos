open Core

(** State-based CRDTs for decentralized Task Planning.
    Currently maps to a LWW-Element-Set (Last-Writer-Wins) for task status. *)

module Task_status = struct
  type t =
    | Backlog
    | In_progress
    | In_review
    | Done
  [@@deriving sexp, compare, equal]

  let to_string = function
    | Backlog -> "Backlog"
    | In_progress -> "In Progress"
    | In_review -> "In Review"
    | Done -> "Done"
end

module Task = struct
  type t = {
    id: string;
    title: string;
    description: string;
    status: Task_status.t;
    timestamp: float;
  } [@@deriving sexp, compare]

  (** Merges two task records, choosing the one with the higher timestamp (LWW CRDT) *)
  let merge a b =
    if Float.(a.timestamp >= b.timestamp) then a else b
end

type t = Task.t String.Map.t

let empty : t = String.Map.empty

let add_or_update state (task : Task.t) =
  Map.update state task.id ~f:(function
    | None -> task
    | Some existing -> Task.merge existing task)

let merge state1 state2 =
  Map.merge state1 state2 ~f:(fun ~key:_ -> function
    | `Left t | `Right t -> Some t
    | `Both (t1, t2) -> Some (Task.merge t1 t2))

