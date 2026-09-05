(** Canonical five-owner FPP portfolio consumed by Ops and formal projections. *)

type model_entry = private {
  owner : Fpp_window_authority.owner;
  model : Fpp_model.model;
}

val all : model_entry list
val models : unit -> (Fpp_window_authority.owner * Fpp_model.model) list
val source_digest : string

type jujutsu_fragment

val jujutsu_fragment : jujutsu_fragment
val jujutsu_effect_kind_ids : jujutsu_fragment -> string list
val jujutsu_operation_activity_ids : jujutsu_fragment -> string list
val standalone_phase_template_ids : jujutsu_fragment -> string list
val conditional_family_template_ids : jujutsu_fragment -> string list
val candidate_verification_action_ids : jujutsu_fragment -> string list
val formal_oracle_action_ids : jujutsu_fragment -> string list
val action_work_class_ids : jujutsu_fragment -> string list
val completion_receipt_work_ids : jujutsu_fragment -> string list
val static_template_digest : jujutsu_fragment -> string
val controlled_lifecycle_state_ids : jujutsu_fragment -> string list
val conditional_control_state_ids : jujutsu_fragment -> string list
val conditional_control_event_ids : jujutsu_fragment -> string list
val conditional_channel_kind_ids : jujutsu_fragment -> string list
val jujutsu_fragment_digest : jujutsu_fragment -> string
val jujutsu_fragment_gaps : unit -> string list
val activation_posture : [ `Implemented_unavailable ]
(** Pure Task-7A declaration only.  The fragment is not composed into the
    Operations model and cannot admit or execute an activity until the closed
    Task-7A/8/9 source transaction is complete. *)

val diagnostics : unit -> Fractal_diagnostic.t list
val module_mapping_gaps : unit -> string list
val debug_mapping_gaps : unit -> string list
val validate : unit -> string list
val receipt_json : unit -> Yojson.Safe.t

module For_test : sig
  type mutation =
    Drop_wiki | Duplicate_harness | Rename_ops_model | Drop_mapped_component
    | Drop_debug_component | Drop_debug_event
  val mutate : mutation -> model_entry list
  val validate_entries : model_entry list -> string list

  type fragment_mutation =
    | Drop_jujutsu_effect
    | Duplicate_operation_activity
    | Drop_conditional_channel
    | Claim_live_activation
    | Drop_phase_template
    | Flatten_conditional_template
    | Swap_completion_receipt_work

  val mutate_fragment : fragment_mutation -> jujutsu_fragment
  val validate_fragment : jujutsu_fragment -> string list
end
