(** Pure, fail-closed lifecycle oracle for an evolving parity node. *)

type phase =
  | Cataloged | Specified | Implemented | Scenario_tested | Trace_matched
  | Evidence_accepted | Diverged

type event = { id : string; snapshot_digest : string; target : phase }
type state = { snapshot_digest : string; node_id : string; phase : phase; applied : string list }
type error = Snapshot_mismatch | Invalid_transition | Event_conflict

let create ~snapshot_digest ~node_id = { snapshot_digest; node_id; phase = Cataloged; applied = [] }

let allowed = function
  | Cataloged, Specified | Specified, Implemented | Implemented, Scenario_tested
  | Scenario_tested, Trace_matched | Trace_matched, Evidence_accepted
  | Trace_matched, Diverged | Evidence_accepted, Diverged | Diverged, Implemented -> true
  | _ -> false

let apply state (event : event) =
  if event.snapshot_digest <> state.snapshot_digest then Error Snapshot_mismatch
  else if List.mem event.id state.applied then Ok state
  else if not (allowed (state.phase, event.target)) then Error Invalid_transition
  else Ok { state with phase = event.target; applied = state.applied @ [ event.id ] }

let replay state events =
  List.fold_left
    (fun current event -> match current with Error _ -> current | Ok state -> apply state event)
    (Ok state) events
