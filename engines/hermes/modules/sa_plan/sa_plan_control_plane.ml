type domain = Otp_parity | Sa_plan | Infranodus | Documentation | Fdc
type bridge_state = Observed | Oriented | Selected | Materialized | Preflighted | Leased | Executing | Verifying | Verified | Recorded | Completed | Blocked | Deferred | Expired | Retryable_failure | Permanent_failure | Reconciled
type identity = { ooda_slice_id : string; sa_plan_id : string; sa_task_id : string; lease_id : string; gate_run_id : string; commit_sha : string; cycle_id : string }
type lease = { id : string; owner : string; fencing_token : int64 }
type evidence_ref = { id : string; kind : string; digest : string }
type command = Advance of { command_id : string; target : bridge_state; evidence : evidence_ref list } | Claim of { command_id : string; owner : string; lease_id : string; fencing_token : int64 } | Progress of { command_id : string; owner : string; fencing_token : int64; target : bridge_state; evidence : evidence_ref list } | Complete of { command_id : string; owner : string; fencing_token : int64; evidence : evidence_ref list }
type event = Transitioned of { command_id : string; from_state : bridge_state; to_state : bridge_state; version : int64 }
type error = Empty_command_id | Empty_owner | Non_positive_fencing_token of int64 | Invalid_identity of string | Invalid_transition of { from_state : bridge_state; target : bridge_state } | Owner_mismatch of string | Fence_mismatch of { expected : int64; actual : int64 } | Lease_missing | Terminal_state
type observation = { domain : domain; identity : identity; state : bridge_state; version : int64; lease : lease option; evidence : evidence_ref list; event_count : int }
type t = { domain : domain; identity : identity; state : bridge_state; version : int64; lease : lease option; evidence : evidence_ref list; events : event list; command_ids : string list }

let nonempty field value = if String.equal value "" then Error (Invalid_identity field) else Ok ()
let create ~domain ~identity =
  match nonempty "ooda_slice_id" identity.ooda_slice_id, nonempty "sa_plan_id" identity.sa_plan_id,
        nonempty "sa_task_id" identity.sa_task_id, nonempty "lease_id" identity.lease_id,
        nonempty "gate_run_id" identity.gate_run_id, nonempty "commit_sha" identity.commit_sha,
        nonempty "cycle_id" identity.cycle_id with
  | Ok (), Ok (), Ok (), Ok (), Ok (), Ok (), Ok () -> Ok { domain; identity; state = Observed; version = 0L; lease = None; evidence = []; events = []; command_ids = [] }
  | Error error, _, _, _, _, _, _ | _, Error error, _, _, _, _, _ | _, _, Error error, _, _, _, _ | _, _, _, Error error, _, _, _ | _, _, _, _, Error error, _, _ | _, _, _, _, _, Error error, _ | _, _, _, _, _, _, Error error -> Error error

let allowed_transition from_state target =
  match from_state, target with
  | Observed, (Oriented | Blocked | Deferred | Permanent_failure) -> true
  | Oriented, (Selected | Blocked | Deferred | Retryable_failure | Permanent_failure) -> true
  | Selected, (Materialized | Blocked | Deferred | Retryable_failure | Permanent_failure) -> true
  | Materialized, (Preflighted | Blocked | Deferred | Retryable_failure | Permanent_failure) -> true
  | Preflighted, (Leased | Blocked | Deferred | Expired | Retryable_failure | Permanent_failure) -> true
  | Leased, (Executing | Blocked | Expired | Retryable_failure | Permanent_failure) -> true
  | Executing, (Verifying | Blocked | Expired | Retryable_failure | Permanent_failure) -> true
  | Verifying, (Verified | Blocked | Retryable_failure | Permanent_failure) -> true
  | Verified, (Recorded | Blocked | Retryable_failure | Permanent_failure) -> true
  | Recorded, Completed -> true
  | (Blocked | Deferred | Expired | Retryable_failure | Permanent_failure), Reconciled -> true
  | Reconciled, (Oriented | Selected | Materialized | Preflighted | Blocked | Deferred | Permanent_failure) -> true
  | _ -> false

let command_id = function Advance c -> c.command_id | Claim c -> c.command_id | Progress c -> c.command_id | Complete c -> c.command_id
let validate_command command =
  if String.equal (command_id command) "" then Error Empty_command_id
  else
    match command with
    | Advance _ -> Ok ()
    | Claim { owner; fencing_token; _ }
    | Progress { owner; fencing_token; _ }
    | Complete { owner; fencing_token; _ } ->
        if String.equal owner "" then Error Empty_owner
        else if Int64.compare fencing_token 0L <= 0 then Error (Non_positive_fencing_token fencing_token)
        else Ok ()
let with_transition t command_id target evidence lease =
  if not (allowed_transition t.state target) then Error (Invalid_transition { from_state = t.state; target })
  else
    let version = Int64.succ t.version in
    let event = Transitioned { command_id; from_state = t.state; to_state = target; version } in
    Ok { t with state = target; version; lease; evidence = t.evidence @ evidence; events = t.events @ [ event ]; command_ids = command_id :: t.command_ids }
let require_lease t owner fencing_token =
  match t.lease with
  | None -> Error Lease_missing
  | Some lease when not (String.equal lease.owner owner) -> Error (Owner_mismatch owner)
  | Some lease when not (Int64.equal lease.fencing_token fencing_token) -> Error (Fence_mismatch { expected = lease.fencing_token; actual = fencing_token })
  | Some _ -> Ok ()
let apply t command =
  let id = command_id command in
  match validate_command command with
  | Error error -> Error error
  | Ok () ->
      if List.mem id t.command_ids then Ok t else
      match command with
      | Advance { target; evidence; _ } ->
          if target = Leased || target = Completed then Error (Invalid_transition { from_state = t.state; target })
          else with_transition t id target evidence t.lease
      | Claim { owner; lease_id; fencing_token; _ } ->
          if not (String.equal lease_id t.identity.lease_id) then Error (Invalid_identity "lease_id")
          else with_transition t id Leased [] (Some { id = lease_id; owner; fencing_token })
      | Progress { owner; fencing_token; target; evidence; _ } ->
          (match require_lease t owner fencing_token with Ok () -> with_transition t id target evidence t.lease | Error error -> Error error)
      | Complete { owner; fencing_token; evidence; _ } ->
      if t.state = Completed then Error Terminal_state
          else (match require_lease t owner fencing_token with Ok () -> with_transition t id Completed evidence t.lease | Error error -> Error error)
let replay initial commands =
  List.fold_left
    (fun result command ->
      match result with Ok state -> apply state command | Error _ as error -> error)
    (Ok initial) commands
let observe t = { domain = t.domain; identity = t.identity; state = t.state; version = t.version; lease = t.lease; evidence = t.evidence; event_count = List.length t.events }
let string_of_error = function
  | Empty_command_id -> "empty command id"
  | Empty_owner -> "empty owner"
  | Non_positive_fencing_token token -> "non-positive fencing token: " ^ Int64.to_string token
  | Invalid_identity field -> "invalid identity: " ^ field
  | Invalid_transition _ -> "invalid transition"
  | Owner_mismatch owner -> "owner mismatch: " ^ owner
  | Fence_mismatch _ -> "fence mismatch"
  | Lease_missing -> "lease missing"
  | Terminal_state -> "terminal state"
