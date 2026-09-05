(** Pure, closed action-constructor authority for controlled Jujutsu work.

    The 29 auxiliary roles below are an exact denominator. Frontier actions
    are deliberately separate: adding either frontier constructor to
    [auxiliary_role] would change approval, target, and formal denominators. *)

type auxiliary_role =
  | Acquire_clock
  | Observe_external_resource
  | Observe_repository_source
  | Observe_release_bundle
  | Consume_approval_nonce
  | Acquire_writer_lease
  | Renew_writer_lease
  | Release_writer_lease
  | Observe_tree
  | Observe_object
  | Acquire_network_scope
  | Release_network_scope
  | Acquire_credential_lease
  | Release_credential_lease
  | Materialize_candidate
  | Write_partition
  | Restore_partition
  | Restore_sealed_record_preimage
  | Write_sealed_record_candidate
  | Remove_disposable_scope
  | Stage_recovery_set
  | Reconcile_recovery_set
  | Cleanup_recovery_set
  | Verify_candidate_tree
  | Execute_jj_process
  | Readback_jj_state
  | Reserve_completion_receipt
  | Finalize_completion_receipt
  | Execute_formal_oracle

type candidate_step =
  | Toolchain_check
  | Jj_reverse_cone
  | Jj_live_campaign
  | Jj_formal_receipt_validation
  | Jj_precompletion_readback

type formal_tool = Gospel | Z3 | Rocq | Iris | Quint

(** Every formal request contains one positive case and an immutable bounded
    denominator of named negative controls. *)
type formal_case =
  | Positive
  | Negative_control of Jj_id.Negative_control.t

(** Request-specific formal work. The representation is abstract so callers
    cannot detach a case from its selected tool. *)
type formal_process

val formal_process : tool:formal_tool -> case:formal_case -> formal_process
val formal_process_tool : formal_process -> formal_tool
val formal_process_case : formal_process -> formal_case
val formal_case_key : formal_case -> string
val formal_process_key : formal_process -> string
val formal_case_schema : string list

type activity_frontier = Reconciled_terminal

type frontier_action =
  | Activate_source_recovery_branch
  | Set_activity_frontier of activity_frontier

(** The only lower action sum. It carries typed constructors and never argv,
    target names, open strings, capabilities, or effects. *)
type t =
  | Jujutsu_operation of Jj_operation.t
  | Auxiliary of auxiliary_role
  | Candidate_process of candidate_step
  | Formal_process of formal_process
  | Frontier_action of frontier_action

val auxiliary_roles : auxiliary_role list
val candidate_steps : candidate_step list
val formal_tools : formal_tool list
val frontier_actions : frontier_action list

val auxiliary_role_key : auxiliary_role -> string
val candidate_step_key : candidate_step -> string
val formal_tool_key : formal_tool -> string
val frontier_action_key : frontier_action -> string
val action_key : t -> string

(** Digest of the operation authority plus every ordered finite denominator. *)
val source_digest : string

module For_test : sig
  (** Non-authorizing mutation surface used only to prove digest sensitivity. *)
  val digest_denominators :
    auxiliary_roles:auxiliary_role list ->
    candidate_steps:candidate_step list ->
    formal_tools:formal_tool list ->
    formal_case_schema:string list ->
    frontier_actions:frontier_action list ->
    string
end
