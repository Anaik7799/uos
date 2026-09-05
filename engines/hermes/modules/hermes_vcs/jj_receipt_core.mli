(** Pure normalized receipt data for controlled Jujutsu.

    Sensitive payload bytes are held only by an abstract ephemeral value. A
    durable receipt accepts normalized summaries and digests, never those
    bytes. This leaf is non-authorizing and imports no execution/store type. *)

type digest = Jj_secret_scan.digest

type payload_kind =
  | Patch
  | Description
  | Operation_log_description
  | Credential_bearing_remote_url

type sensitive_payload
type payload_error = Empty_payload | Payload_too_large

val sensitive_payload :
  kind:payload_kind -> bytes:string -> (sensitive_payload, payload_error) result

type payload_summary
val normalize_payload : sensitive_payload -> payload_summary
val payload_kind : payload_summary -> payload_kind
val payload_byte_length : payload_summary -> int
val payload_digest : payload_summary -> digest

type anchor_retention =
  | Until_terminal_readback
  | Until_reconciled

type recovery_anchor

val recovery_anchor :
  identity:Jj_id.Receipt.t ->
  prefix:digest ->
  cut:digest ->
  disposition:digest ->
  retention:anchor_retention ->
  recovery_anchor

type receipt_kind = Observation | Mutation | Recovery
type disposition = First_applied | Replayed | No_effect | Indeterminate
type receipt

type receipt_error =
  | Too_many_payload_summaries
  | Duplicate_payload_summary

(** Every accepted field contributes to [canonical_digest]. Payload summaries
    are sorted, so semantically identical input order is deterministic. *)
val make :
  receipt_id:Jj_id.Receipt.t ->
  request_id:Jj_id.Request.t ->
  operation:Jj_operation.t ->
  kind:receipt_kind ->
  disposition:disposition ->
  request_digest:digest ->
  target_digest:digest ->
  before_digest:digest ->
  after_digest:digest ->
  readback_id:Jj_id.Receipt.t ->
  readback_digest:digest ->
  secret_scan:Jj_secret_scan.scan ->
  payloads:payload_summary list ->
  recovery:recovery_anchor option ->
  (receipt, receipt_error) result

val canonical_digest : receipt -> digest
val safe_summary : receipt -> string
val recovery_anchor_retained : receipt -> bool
val source_digest : string

module For_test : sig
  type mutation =
    | Receipt_id
    | Request_id
    | Operation
    | Receipt_kind
    | Disposition
    | Request_digest
    | Target_digest
    | Before_digest
    | After_digest
    | Readback_id
    | Readback_digest
    | Secret_scan_digest
    | Payload_kind
    | Payload_length
    | Payload_digest
    | Recovery_identity
    | Recovery_prefix
    | Recovery_cut
    | Recovery_disposition
    | Recovery_retention

  val canonical_digest_with_mutation : receipt -> mutation -> string
end
