(** Nonauthorizing recovery-transition reference preparation.
    Only the dependability authority store may seal a prepared reference. *)

module Expiry : Jj_id.ID

type prepared_reference
type reference
type reference_current

val prepare :
  owner_session:Jj_runtime_current_protocol.Owner_session.t ->
  activation_generation:Jj_runtime_current_protocol.Activation_generation.t ->
  activity:Jj_runtime_current_protocol.Activity_identity.t ->
  commitment:Jj_runtime_current_protocol.Source_transition_commitment.t ->
  target:Jj_runtime_manifest.target_transition Jj_runtime_manifest.slot ->
  consumer:Jj_action_kind.frontier_action ->
  expiry:Expiry.t ->
  (prepared_reference, Jj_error.t) result

val prepared_key : prepared_reference -> string
val source_digest : string
