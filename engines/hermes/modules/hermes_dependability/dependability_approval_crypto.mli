(** Pure, validation-only Ed25519 approval-ticket verification.

    The module owns no private key, seed, signing operation, random source, or
    effect.  The domain separator and canonical length framing are fixed by
    this interface. *)

type public_key
type signature
type canonical_signed_bytes
type verified

type error =
  | Public_key_wrong_length
  | Public_key_malformed
  | Signature_wrong_length
  | Empty_ticket
  | Noncanonical_ticket
  | Signature_invalid

val algorithm : string
val domain_separator : string
val public_key_bytes : int
val signature_bytes : int

val public_key_of_octets : string -> (public_key, error) result
val signature_of_octets : string -> (signature, error) result
val public_key_identity : public_key -> string
(** Canonical SHA-256 identity only; never key octets or signing authority. *)

(** Accepts only a nonempty canonical decimal-length-framed ticket.  Domain
    separation is added internally and cannot be selected by the caller. *)
val canonical_signed_bytes :
  canonical_ticket_bytes:string -> (canonical_signed_bytes, error) result

val verify :
  public_key -> signature -> canonical_signed_bytes -> (verified, error) result

(** Validation evidence only; never an approval or execution capability. *)
val verified_digest : verified -> string

(** RFC 8032 section 7.1 verification-only provider check. *)
val provider_self_test : unit -> bool

val source_digest : string
