module C = Sa_plan_control_plane
type t = { domain : C.domain; identity : C.identity; state : C.bridge_state; version : int64; lease : C.lease option; evidence : C.evidence_ref list; seen : string list; events : C.event list }
let create ~domain ~identity = { domain; identity; state = C.Observed; version = 0L; lease = None; evidence = []; seen = []; events = [] }
let id = function C.Advance x -> x.command_id | C.Claim x -> x.command_id | C.Progress x -> x.command_id | C.Complete x -> x.command_id
let permitted from_state target =
  match from_state, target with
  | C.Observed, (C.Oriented | C.Blocked | C.Deferred | C.Permanent_failure)
  | C.Oriented, (C.Selected | C.Blocked | C.Deferred | C.Retryable_failure | C.Permanent_failure)
  | C.Selected, (C.Materialized | C.Blocked | C.Deferred | C.Retryable_failure | C.Permanent_failure)
  | C.Materialized, (C.Preflighted | C.Blocked | C.Deferred | C.Retryable_failure | C.Permanent_failure)
  | C.Preflighted, (C.Leased | C.Blocked | C.Deferred | C.Expired | C.Retryable_failure | C.Permanent_failure)
  | C.Leased, (C.Executing | C.Blocked | C.Expired | C.Retryable_failure | C.Permanent_failure)
  | C.Executing, (C.Verifying | C.Blocked | C.Expired | C.Retryable_failure | C.Permanent_failure)
  | C.Verifying, (C.Verified | C.Blocked | C.Retryable_failure | C.Permanent_failure)
  | C.Verified, (C.Recorded | C.Blocked | C.Retryable_failure | C.Permanent_failure)
  | C.Recorded, C.Completed
  | (C.Blocked | C.Deferred | C.Expired | C.Retryable_failure | C.Permanent_failure), C.Reconciled
  | C.Reconciled, (C.Oriented | C.Selected | C.Materialized | C.Preflighted | C.Blocked | C.Deferred | C.Permanent_failure) -> true
  | _ -> false
let transition t command_id target evidence lease =
  if not (permitted t.state target) then t else
  let version = Int64.succ t.version in
  { t with state = target; version; lease; evidence = t.evidence @ evidence; seen = command_id :: t.seen; events = t.events @ [ C.Transitioned { command_id; from_state = t.state; to_state = target; version } ] }
let apply t command =
  let command_id = id command in
  if List.mem command_id t.seen then t else
  match command with
  | C.Advance { target; evidence; _ } when target <> C.Leased && target <> C.Completed -> transition t command_id target evidence t.lease
  | C.Claim { owner; lease_id; fencing_token; _ } when String.equal lease_id t.identity.lease_id -> transition t command_id C.Leased [] (Some { C.id = lease_id; owner; fencing_token })
  | C.Progress { owner; fencing_token; target; evidence; _ } ->
      (match t.lease with Some lease when String.equal lease.owner owner && Int64.equal lease.fencing_token fencing_token -> transition t command_id target evidence t.lease | _ -> t)
  | C.Complete { owner; fencing_token; evidence; _ } ->
      (match t.lease with Some lease when String.equal lease.owner owner && Int64.equal lease.fencing_token fencing_token -> transition t command_id C.Completed evidence t.lease | _ -> t)
  | _ -> t
let replay = List.fold_left apply
let observe t = { C.domain = t.domain; identity = t.identity; state = t.state; version = t.version; lease = t.lease; evidence = t.evidence; event_count = List.length t.events }
