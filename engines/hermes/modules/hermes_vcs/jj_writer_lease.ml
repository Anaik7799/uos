type claim = {
  lease_id : Jj_id.Lease.t;
  repository : Jj_id.Repository.t;
  workspace : Jj_id.Workspace.t;
  expected_operation : Jj_id.Operation.t;
  expected_change : Jj_id.Change.t;
  expected_commit : Jj_id.Commit.t;
  holder : Jj_id.Approval.t;
  expires_at_epoch : int64;
  fence_epoch : int64;
  operator_quiescence : Jj_id.Receipt.t;
  release_readback : Jj_id.Receipt.t option;
}

type validation_error = Invalid_fence | Already_expired | Already_released
type mutation_state = Not_started | Started
type stale_reason =
  | Head_changed
  | External_writer_detected
  | Lease_expired
  | Lease_expired_during_started_mutation

type current = { claim : claim }
type state =
  | Current of current
  | Stale of { reason : stale_reason; full_readback : bool }

let validate ~now_epoch claim =
  if Int64.compare claim.fence_epoch 0L <= 0 then Error Invalid_fence
  else if Option.is_some claim.release_readback then Error Already_released
  else if Int64.compare now_epoch claim.expires_at_epoch >= 0 then
    Error Already_expired
  else Ok (Current { claim })

let stale mutation_state reason =
  Stale { reason; full_readback = mutation_state = Started }

let observe state ~now_epoch ~observed_operation ~external_writer_detected
    ~mutation_state =
  match state with
  | Stale _ -> state
  | Current current ->
      if external_writer_detected then
        stale mutation_state External_writer_detected
      else if
        not
          (String.equal
             (Jj_id.Operation.to_string observed_operation)
             (Jj_id.Operation.to_string current.claim.expected_operation))
      then stale mutation_state Head_changed
      else if Int64.compare now_epoch current.claim.expires_at_epoch >= 0 then
        stale mutation_state
          (match mutation_state with
           | Not_started -> Lease_expired
           | Started -> Lease_expired_during_started_mutation)
      else state

let permits_next = function Current _ -> true | Stale _ -> false

let started_mutation_may_complete = function
  | Stale { reason = Lease_expired_during_started_mutation; _ } -> true
  | Current _ | Stale _ -> false

let requires_full_readback = function
  | Current _ -> false
  | Stale { full_readback; _ } -> full_readback

let stale_reason = function
  | Current _ -> None
  | Stale { reason; _ } -> Some reason

let source_digest =
  Jj_id.length_frame
    [ "jj-writer-lease.v1";
      "claim:lease,repository,workspace,operation,change,commit,holder,expiry,fence,quiescence,release-readback";
      "validation:invalid-fence,already-expired,already-released";
      "mutation:not-started,started";
      "stale:head-changed,external-writer,expired,expired-during-started";
      "laws:absorbing-stale,started-may-complete,full-readback,next-fenced" ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
