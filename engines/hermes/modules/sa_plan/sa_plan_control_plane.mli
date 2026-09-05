(** Pure, durable-state contract for one OODA slice.  Replaying a stable command
    identifier is effectively-once for this state machine only; it makes no
    claim about exactly-once transport or external side effects.

    The Gospel declarations below deliberately cover the pure control algebra,
    not the durable Store or transport interpreters.  The independent oracle is
    [Sa_plan_control_plane_oracle]; [test_sa_plan_control_plane] checks replay
    chunking, fencing, idempotency, and observational agreement. *)

type domain = Otp_parity | Sa_plan | Infranodus | Documentation | Fdc
type bridge_state = Observed | Oriented | Selected | Materialized | Preflighted | Leased | Executing | Verifying | Verified | Recorded | Completed | Blocked | Deferred | Expired | Retryable_failure | Permanent_failure | Reconciled
type identity = { ooda_slice_id : string; sa_plan_id : string; sa_task_id : string; lease_id : string; gate_run_id : string; commit_sha : string; cycle_id : string }
type lease = { id : string; owner : string; fencing_token : int64 }
type evidence_ref = { id : string; kind : string; digest : string }
type command = Advance of { command_id : string; target : bridge_state; evidence : evidence_ref list } | Claim of { command_id : string; owner : string; lease_id : string; fencing_token : int64 } | Progress of { command_id : string; owner : string; fencing_token : int64; target : bridge_state; evidence : evidence_ref list } | Complete of { command_id : string; owner : string; fencing_token : int64; evidence : evidence_ref list }
type event = Transitioned of { command_id : string; from_state : bridge_state; to_state : bridge_state; version : int64 }
type error = Empty_command_id | Empty_owner | Non_positive_fencing_token of int64 | Invalid_identity of string | Invalid_transition of { from_state : bridge_state; target : bridge_state } | Owner_mismatch of string | Fence_mismatch of { expected : int64; actual : int64 } | Lease_missing | Terminal_state
type observation = { domain : domain; identity : identity; state : bridge_state; version : int64; lease : lease option; evidence : evidence_ref list; event_count : int }
type t
val create : domain:domain -> identity:identity -> (t, error) result
(*@ r = create ~domain ~identity
    pure *)
val allowed_transition : bridge_state -> bridge_state -> bool
(*@ r = allowed_transition from_state target
    pure *)
val apply : t -> command -> (t, error) result
(*@ r = apply state command
    pure *)
val replay : t -> command list -> (t, error) result
(*@ r = replay state commands
    pure *)
val observe : t -> observation
(*@ r = observe state
    pure *)
val string_of_error : error -> string
(*@ r = string_of_error error
    pure *)
