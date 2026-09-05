(** Closed repository-verification effect target.

    This adapter accepts only the topology-admitted
    [activity.verify-repository] carrier.  Its injected capture boundary is
    typed by {!Run_topology.action_work}; it is not a generic command API and
    it never reads configuration or process state from the environment. *)

type status = Passed | Failed | Skipped
type availability = Available | Unavailable

type capture =
  | Executed of { exit_code : int; output : string }
  | Executable_unavailable of { executable : string; reason : string }

type run_capture = Run_topology.action_work -> capture

type observation = private {
  action_id : string;
  action_digest : string;
  status : status;
  availability : availability;
  exit_code : int option;
  output : string;
  output_bytes : int;
  output_digest : string;
  output_truncated : bool;
}

type diagnostic_code =
  | Invalid_activity
  | Invalid_prepared_request
  | Unsupported_work
  | Capture_failure
  | Invalid_observation

type diagnostic = private {
  code : diagnostic_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
}

type registration

val make_registry :
  activity:Run_topology.admitted_activity -> run_capture:run_capture ->
  (registration, diagnostic list) result
(** Registers the exact repository target and its one closed effect kind.
    Apply prevalidates the preparation-v3 activity, authority, action, and
    closed work projection against the retained topology row before invoking
    [run_capture].  Task-7A work owned by any other target is refused before
    capture. Query reconciles only the target-native receipt retained for the
    exact idempotency key.  The returned owner retains the private observation
    bytes; they never enter an effect receipt or the bridge event stream. *)

val target_registry : registration -> Run_effect_authority.target_registry
(** Projects only the admitted target registry needed to open the effect
    interpreter.  It exposes no observation or capture payload. *)

val observation_of_receipt :
  registration -> Run_effect_authority.receipt ->
  (observation, diagnostic) result
(** Independently reads back and validates the bounded owner-held observation
    against the receipt's nonauthorizing evidence identity and digest.
    A nonzero execution decodes as {!Failed}; an unavailable executable as
    {!Skipped} and {!Unavailable}.  Neither state is green. *)

val maximum_observation_output_bytes : int
(** Maximum output bytes retained in the committed observation.  The digest
    and [output_bytes] continue to bind the full capture. *)
