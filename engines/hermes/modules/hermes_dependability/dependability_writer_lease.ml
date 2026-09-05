type rca_origin = Specification | Implementation | Environment | Evidence | Control

type diagnostic =
  | Physical_owner_lock_backend_unavailable
  | Approval_current_carrier_unavailable
  | Authority_writer_fence_transition_unavailable
  | Authority_role_session_fence_unavailable
  | Nominal_writer_peer_open_fence_unavailable
  | Clock_receipt_invalid

let diagnostic_code = function
  | Physical_owner_lock_backend_unavailable ->
      "physical-owner-lock-backend-unavailable"
  | Approval_current_carrier_unavailable ->
      "approval-current-carrier-unavailable"
  | Authority_writer_fence_transition_unavailable ->
      "authority-writer-fence-transition-unavailable"
  | Authority_role_session_fence_unavailable ->
      "authority-role-session-fence-unavailable"
  | Nominal_writer_peer_open_fence_unavailable ->
      "nominal-writer-peer-open-fence-unavailable"
  | Clock_receipt_invalid -> "clock-receipt-invalid"

let diagnostic_coordinate _ = "L2.Task6.WriterLease"
let diagnostic_origin _ = Evidence

type prerequisite =
  | Physical_owner_lock_backend
  | Approval_current_carrier
  | Authority_writer_fence_transition
  | Authority_role_session_fence
  | Nominal_writer_peer_open_fence

let prerequisite_status = function
  | Physical_owner_lock_backend -> Error Physical_owner_lock_backend_unavailable
  | Approval_current_carrier -> Error Approval_current_carrier_unavailable
  | Authority_writer_fence_transition ->
      Error Authority_writer_fence_transition_unavailable
  | Authority_role_session_fence ->
      Error Authority_role_session_fence_unavailable
  | Nominal_writer_peer_open_fence ->
      Error Nominal_writer_peer_open_fence_unavailable

let production_posture = `Implemented_unavailable

type acquisition_contract = {
  lease : Jj_id.Lease.t;
  repository : Jj_id.Repository.t;
  workspace : Jj_id.Workspace.t;
  expected_operation : Jj_id.Operation.t;
  expected_change : Jj_id.Change.t;
  expected_commit : Jj_id.Commit.t;
  holder : Jj_id.Approval.t;
  operator_quiescence : Jj_id.Receipt.t;
  observed_at : Dependability_clock.receipt;
  digest : string;
}

let sha256 values =
  values |> String.concat "\000"
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let prepare_acquisition ~lease ~repository ~workspace ~expected_operation
    ~expected_change ~expected_commit ~holder ~operator_quiescence ~observed_at =
  match Dependability_clock.validate observed_at with
  | Error _ -> Error Clock_receipt_invalid
  | Ok () ->
      let digest =
        sha256
          [ "dependability-writer-lease-acquisition-v1";
            Jj_id.Lease.to_string lease;
            Jj_id.Repository.to_string repository;
            Jj_id.Workspace.to_string workspace;
            Jj_id.Operation.to_string expected_operation;
            Jj_id.Change.to_string expected_change;
            Jj_id.Commit.to_string expected_commit;
            Jj_id.Approval.to_string holder;
            Jj_id.Receipt.to_string operator_quiescence;
            Dependability_clock.digest observed_at ]
      in
      Ok
        { lease; repository; workspace; expected_operation; expected_change;
          expected_commit; holder; operator_quiescence; observed_at; digest }

let acquisition_digest contract = contract.digest

type mutation_state = Not_started | Started

type fence_reason =
  | Head_changed
  | External_writer_detected
  | Lease_expired
  | Lease_expired_during_started_mutation

type contract_state =
  | Eligible_nonauthorizing of acquisition_contract
  | Fenced of {
      reason : fence_reason;
      full_readback : bool;
    }

let initial_state contract = Eligible_nonauthorizing contract

let fenced ~mutation_state reason =
  Fenced { reason; full_readback = mutation_state = Started }

let observe state ~now ~observed_operation ~external_writer_detected
    ~mutation_state =
  match state with
  | Fenced _ -> Ok state
  | Eligible_nonauthorizing contract ->
      if external_writer_detected then
        Ok (fenced ~mutation_state External_writer_detected)
      else if
        String.equal
          (Jj_id.Operation.to_string observed_operation)
          (Jj_id.Operation.to_string contract.expected_operation)
      then
        begin
          match
            Dependability_clock.validate_current ~now contract.observed_at
          with
          | Ok () -> Ok state
          | Error Dependability_clock.Expired ->
              Ok
                (fenced ~mutation_state
                   (match mutation_state with
                    | Not_started -> Lease_expired
                    | Started -> Lease_expired_during_started_mutation))
          | Error _ -> Error Clock_receipt_invalid
        end
      else Ok (fenced ~mutation_state Head_changed)

let contract_is_current = function
  | Eligible_nonauthorizing _ -> true
  | Fenced _ -> false

let permits_acquisition_request = contract_is_current
let permits_next_governed_action _ = false

let started_mutation_may_complete = function
  | Fenced { reason = Lease_expired_during_started_mutation; _ } -> true
  | Eligible_nonauthorizing _ | Fenced _ -> false

let requires_full_readback = function
  | Eligible_nonauthorizing _ -> false
  | Fenced { full_readback; _ } -> full_readback

let fence_reason = function
  | Eligible_nonauthorizing _ -> None
  | Fenced { reason; _ } -> Some reason

type readback_requirement =
  | No_readback_required
  | Full_supervision_readback_required

let readback_requirement state =
  if requires_full_readback state then Full_supervision_readback_required
  else No_readback_required

type registered_owner = |

let open_registered ~authority:_ ~writer_fence:_ ~approval:_ ~observed_at:_ =
  Error Physical_owner_lock_backend_unavailable

let source_digest =
  sha256
    [ "dependability-writer-lease-bounded-foundation-v1";
      "prepared-contract-is-nonauthorizing";
      "clock-receipt-owned-expiry-no-raw-time";
      "fences:head-external-expired-expired-during-started";
      "absorbing-fence";
      "started-mutation-may-complete-with-full-readback";
      "no-next-governed-action-without-held-lease";
      "physical-lock-approval-current-authority-transition-session-peer-open-required";
      "no-owner-current-fence-seal-or-execution-authority-forgery" ]

module For_test = struct
  type mutation =
    | Invent_physical_lock
    | Drop_approval_current
    | Drop_authority_fence_transition
    | Accept_raw_time
    | Permit_after_fence
    | Kill_started_mutation_on_expiry
    | Skip_full_readback
    | Forge_current_owner

  let mutation_name = function
    | Invent_physical_lock -> "invent-physical-lock"
    | Drop_approval_current -> "drop-approval-current"
    | Drop_authority_fence_transition -> "drop-authority-fence-transition"
    | Accept_raw_time -> "accept-raw-time"
    | Permit_after_fence -> "permit-after-fence"
    | Kill_started_mutation_on_expiry -> "kill-started-mutation-on-expiry"
    | Skip_full_readback -> "skip-full-readback"
    | Forge_current_owner -> "forge-current-owner"

  let source_digest_with_mutation mutation =
    sha256
      [ "dependability-writer-lease-bounded-foundation-v1";
        mutation_name mutation ]
end
