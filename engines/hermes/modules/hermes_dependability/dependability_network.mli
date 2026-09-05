(** Pure, nonauthorizing network-policy declaration and observation authority.

    This module has no transport backend: it cannot resolve names, open a
    socket, render a URL, send bytes, or authorize a Jujutsu operation.  A
    request consumes only a named remote and [observe] consumes an opaque
    credential lease.  The credential declaration digest carries the endpoint,
    strict host-key, and TLS policy; all returned evidence is redacted and
    nonauthorizing. *)

type operation = Remote_synchronization | Remote_publication
type idempotency = Stable_request_identity_required | Expected_remote_tip_cas_required
type redaction = Credentials_and_payloads_redacted
type status = Unavailable_observed | Expired | Revoked | Cleaned

type request
type receipt

type error =
  | Remote_lease_mismatch
  | Invalid_credential_lease
  | Invalid_clock_receipt
  | Clock_rollback

val all_operations : operation list
val maximum_timeout_ms : int
val maximum_response_bytes : int

val declare : remote:Dependability_credential.remote -> operation -> request
(** Declares only the closed remote operation.  The caller cannot supply a URL,
    hostname, endpoint, timeout, response bound, credential, or effect. *)

val timeout_ms : request -> int
val max_response_bytes : request -> int
val idempotency : request -> idempotency
val request_digest : request -> string

val observe :
  now:Dependability_clock.receipt ->
  lease:Dependability_credential.lease ->
  request ->
  (receipt, error) result
(** Validates current opaque credential custody.  Missing credentials remain
    [Unavailable_observed]; expiry, revocation, and cleanup are absorbing.
    This is an observation only, never a network effect or authorization. *)

val status : receipt -> status
(* Always [false] until a separately admitted controlled network backend
   returns a current apply-once/readback receipt. *)
val network_permitted : receipt -> bool
val redacted_remote : receipt -> string
val credential_lease_digest : receipt -> string
val observation_clock_digest : receipt -> string
val redaction : receipt -> redaction
val receipt_digest : receipt -> string

val validate_current :
  now:Dependability_clock.receipt ->
  lease:Dependability_credential.lease ->
  receipt ->
  (unit, error) result
(** Revalidates the private observation clock and exact current lease.  A
    receipt cannot remain current after expiry, revocation, cleanup, rollback,
    or lease replacement. *)

val source_digest : string

module For_test : sig
  type mutation =
    | Drop_remote_binding
    | Drop_credential_binding
    | Drop_timeout
    | Widen_response_bound
    | Drop_idempotency
    | Drop_redaction
    | Drop_expiry
    | Drop_cleanup

  val source_digest_with_mutation : mutation -> string
end
