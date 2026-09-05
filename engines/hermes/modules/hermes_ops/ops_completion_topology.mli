(** FPP control/data-plane topology for the typed completion command path.

    This is deliberately distinct from {!Ops_topology}: that model is the
    read-only verification monitor required by R22, whereas this model owns
    command ingress, immutable receipt storage, MBSE projection and formal
    evidence flow. *)

val command_gateway : Fpp_model.component
val completion_history : Fpp_model.component
val mbse_projector : Fpp_model.component
val formal_oracle : Fpp_model.component
val instances : Fpp_model.instance list
val command_flow : Fpp_model.graph
val model : Fpp_model.model
