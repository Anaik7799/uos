(** Pure, nonauthorizing credential-custody declaration foundation.

    This module never acquires or stores a secret. Until a separately governed
    secret-provider handoff exists, every declared lease is
    [Unavailable_observed] and cannot authorize network or VCS work. *)

type remote
type transport = Ssh_strict | Https_tls13
type endpoint_policy = Registered_ssh_endpoint | Registered_https_endpoint
type host_key_policy = Pinned_host_key_required | Host_key_not_applicable
type tls_policy = Tls_not_applicable | Tls_1_3_pinned_server

type status = Unavailable_observed | Expired | Revoked | Cleaned
type declaration
type lease
type redacted_receipt

type error =
  | Invalid_remote
  | Invalid_clock_receipt
  | Clock_rollback
  | Invalid_lease
  | Credential_unavailable
  | Lease_expired
  | Lease_revoked
  | Lease_cleaned

val remote : string -> (remote, error) result
(* Stable opaque identity for binding a named remote into lower request
   authority.  It reveals no endpoint, URL, host key, or credential. *)
val remote_digest : remote -> string
val declare : remote:remote -> transport:transport -> declaration

val endpoint_policy : declaration -> endpoint_policy
val host_key_policy : declaration -> host_key_policy
val tls_policy : declaration -> tls_policy
val scrubbed_inheritance : declaration -> string list
val scrub_policy_digest : declaration -> string
val configuration_id : declaration -> string
val declaration_digest : declaration -> string

val declare_unavailable :
  clock:Dependability_clock.receipt -> declaration -> lease
(** Creates only redacted lease metadata. It accepts no secret, environment
    value, endpoint, URL, socket, callback, or effect carrier. *)

val observe :
  now:Dependability_clock.receipt -> lease -> (lease, error) result
(** Applies expiry only. Expired, revoked, and cleaned states are absorbing. *)

val revoke : lease -> lease
val cleanup : lease -> lease
val validate : lease -> (unit, error) result
val validate_current :
  now:Dependability_clock.receipt -> lease -> (unit, error) result

val status : lease -> status
val authorization_permitted : lease -> bool
(* Always [false] in this nonauthorizing foundation. *)
val matches_remote : lease -> remote -> bool
val lease_reference : lease -> string
val lease_digest : lease -> string

val redacted_receipt : lease -> redacted_receipt
val redacted_status : redacted_receipt -> status
val redacted_remote : redacted_receipt -> string
val redacted_digest : redacted_receipt -> string

val source_digest : string

module For_test : sig
  type mutation =
    | Drop_remote_binding
    | Drop_endpoint_policy
    | Drop_host_key_policy
    | Drop_tls_policy
    | Drop_scrub_policy
    | Permit_serialization
    | Promote_unavailable
    | Remove_expiry
    | Remove_revocation
    | Remove_cleanup

  val source_digest_with_mutation : mutation -> string
end
