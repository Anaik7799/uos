(** Pure, fail-closed dependency identity authority.

    A [carrier] is abstract and process-local.  Its only serializable projection
    is a bounded, non-authorizing [receipt] containing digests, expiry, and
    disposition.  This module accepts no payload bytes, source, credential,
    filesystem handle, argv, callback, or execution capability. *)

type diagnostic_code =
  | Durable_owner_unavailable
  | Invalid_binding
  | Invalid_redacted_evidence
  | Dependency_conflict
  | Dependency_expired
  | Dependency_binding_mismatch
  | Foreign_carrier
  | Dependency_capacity_exhausted

type diagnostic = private {
  code : diagnostic_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
}

type durable_owner_current
type registry

val production_posture : [ `Implemented_unavailable ]
val maximum_live_dependencies : int
(** Production construction remains unavailable until a durable owner-current
    receipt and a controlled clock-current receipt can be supplied. *)

type binding = private {
  execution_identity : string;
  activity_digest : string;
  producer_action_id : string;
  consumer_action_id : string;
  request_digest : string;
  expires_at_ns : int64;
}

val make_binding :
  execution_identity:string -> activity_digest:string ->
  producer_action_id:string -> consumer_action_id:string ->
  request_digest:string -> expires_at_ns:int64 ->
  (binding, diagnostic) result

type evidence_disposition = Dependency_succeeded | Dependency_unavailable

type redacted_evidence = private {
  disposition : evidence_disposition;
  evidence_digest : string;
}

val make_redacted_evidence :
  disposition:evidence_disposition -> evidence_digest:string ->
  (redacted_evidence, diagnostic) result

type carrier

type receipt = private {
  receipt_id : string;
  binding_digest : string;
  owner_digest : string;
  evidence_digest : string;
  expires_at_ns : int64;
  was_replayed : bool;
}

val open_registry : owner:durable_owner_current -> (registry, diagnostic) result

val issue_once :
  registry -> binding:binding -> evidence:redacted_evidence -> now_ns:int64 ->
  (registry * carrier * receipt, diagnostic) result
(** Exact replay is stable.  The same owner/binding with changed evidence is a
    conflict.  Expired or nonfuture bindings are refused. *)

val resolve :
  registry -> owner:durable_owner_current -> binding:binding ->
  carrier:carrier -> now_ns:int64 -> (redacted_evidence, diagnostic) result
(** Resolves only when registry identity, durable owner, execution, activity,
    producer, consumer, request, and expiry all match exactly. *)

val string_of_diagnostic_code : diagnostic_code -> string
val source_digest : string

module For_test : sig
  val durable_owner_current :
    owner_id:string -> generation:int -> owner_digest:string ->
    (durable_owner_current, diagnostic) result

  type source_mutation =
    | Drop_execution_identity
    | Drop_activity_digest
    | Drop_producer_action
    | Drop_consumer_action
    | Drop_request_digest
    | Drop_expiry
    | Drop_durable_owner

  val source_digest_with_mutation : source_mutation -> string
end
