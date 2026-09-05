(** Bridge-neutral, nonauthorizing slot-currentness claims.
    This module deliberately exposes no grant allocator or current-attestation mint. *)

module Owner_session : Jj_id.ID
module Source_identity : Jj_id.ID
module Config_identity : Jj_id.ID
module Host_identity : Jj_id.ID
module Clock_identity : Jj_id.ID
module Activity_identity : Jj_id.ID
module Source_transition_commitment : Jj_id.ID

module Lifecycle_epoch : sig
  type t
  val make : int -> (t, Jj_error.t) result
  val to_int : t -> int
end

module Activation_generation : sig
  type t
  val make : int -> (t, Jj_error.t) result
  val to_int : t -> int
end

type 'slot owner_claim
type ('generation, 'slot) current_attestation

val claim :
  slot:'slot Jj_runtime_manifest.slot ->
  owner:Owner_session.t ->
  epoch:Lifecycle_epoch.t ->
  source:Source_identity.t ->
  config:Config_identity.t ->
  host:Host_identity.t ->
  clock:Clock_identity.t ->
  ('slot owner_claim, Jj_error.t) result

val claim_key : 'slot owner_claim -> string
val source_digest : string
