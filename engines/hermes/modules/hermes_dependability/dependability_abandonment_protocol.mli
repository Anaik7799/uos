(** Pure, bridge-neutral structural algebra for abandonment evidence.

    Preparation validates only shared shape, exact denominators and contextual
    agreement.  It grants no effect, successor, completion or no-effect
    authority.  Current attestations require seven distinct producer seals.
    Those seals deliberately have no public constructor in this foundation;
    [Run_root_bootstrap] must later own their one-shot distribution. *)

type refusal

module Identity : sig
  type t

  val make : string -> (t, refusal) result
  val to_string : t -> string
  val equal : t -> t -> bool
end

val refusal_code : refusal -> string

type context

val make_context :
  manifest:Identity.t ->
  dispatch:Identity.t ->
  session:Identity.t ->
  attempt:Identity.t ->
  transition:Identity.t ->
  (context, refusal) result

type denominator

val make_denominator :
  expected:Identity.t list ->
  observed:Identity.t list ->
  (denominator, refusal) result
(** This is a nonauthorizing structural preparation.  It rejects an empty,
    duplicated, dropped, inserted or reordered denominator. *)

type global_no_effect
type fenced_unentered_tail

type _ purpose =
  | Global_no_effect : global_no_effect purpose
  | Fenced_unentered_tail : fenced_unentered_tail purpose

type claim
type target_entry
type effect_role
type event
type frontier
type session
type before_after

type _ role =
  | Claim : claim role
  | Target_entry : target_entry role
  | Effect : effect_role role
  | Event : event role
  | Frontier : frontier role
  | Session : session role
  | Before_after : before_after role

type session_state = Quiescent | Fenced_dead

type _ target_fact =
  | No_source_changing_target_entry : global_no_effect target_fact
  | Terminal_entered_target_prefix_and_tail_unentered :
      fenced_unentered_tail target_fact

type _ effect_fact =
  | No_effect_applied : global_no_effect effect_fact
  | Terminal_entered_effect_prefix_and_tail_unentered :
      fenced_unentered_tail effect_fact

type _ event_fact =
  | No_effect_event : global_no_effect event_fact
  | Terminal_entered_event_prefix_and_tail_unentered :
      fenced_unentered_tail event_fact

type _ frontier_fact =
  | No_mutation_attempted : global_no_effect frontier_fact
  | Terminal_mutation_frontier_and_tail_unentered :
      fenced_unentered_tail frontier_fact

type _ before_after_fact =
  | Exact_operation_tree_source_equal_and_resources_released :
      global_no_effect before_after_fact
  | Pending_transition_and_writer_fence_retained :
      fenced_unentered_tail before_after_fact

type ('purpose, 'role) prepared_attestation
type ('purpose, 'role) current_attestation
type 'purpose prepared_abandonment_evidence
type 'purpose abandonment_evidence_current

val prepare_claim :
  purpose:'purpose purpose ->
  context:context ->
  denominator:denominator ->
  (('purpose, claim) prepared_attestation, refusal) result

val prepare_target_entry :
  context:context ->
  denominator:denominator ->
  fact:'purpose target_fact ->
  (('purpose, target_entry) prepared_attestation, refusal) result

val prepare_effect :
  context:context ->
  denominator:denominator ->
  fact:'purpose effect_fact ->
  (('purpose, effect_role) prepared_attestation, refusal) result

val prepare_event :
  context:context ->
  denominator:denominator ->
  fact:'purpose event_fact ->
  (('purpose, event) prepared_attestation, refusal) result

val prepare_frontier :
  context:context ->
  denominator:denominator ->
  fact:'purpose frontier_fact ->
  (('purpose, frontier) prepared_attestation, refusal) result

val prepare_session :
  purpose:'purpose purpose ->
  context:context ->
  denominator:denominator ->
  state:session_state ->
  (('purpose, session) prepared_attestation, refusal) result

val prepare_before_after :
  context:context ->
  denominator:denominator ->
  fact:'purpose before_after_fact ->
  (('purpose, before_after) prepared_attestation, refusal) result

val prepare_join :
  claim:('purpose, claim) prepared_attestation ->
  target_entry:('purpose, target_entry) prepared_attestation ->
  effect_attestation:('purpose, effect_role) prepared_attestation ->
  event:('purpose, event) prepared_attestation ->
  frontier:('purpose, frontier) prepared_attestation ->
  session:('purpose, session) prepared_attestation ->
  before_after:('purpose, before_after) prepared_attestation ->
  ('purpose prepared_abandonment_evidence, refusal) result
(** Exact seven-role structural join.  Its result remains prepared and
    explicitly nonauthorizing. *)

val prepared_evidence_digest : 'purpose prepared_abandonment_evidence -> string

val prepared_evidence_status :
  'purpose prepared_abandonment_evidence -> [ `Prepared_nonauthorizing ]

(** Distinct seals have no public constructors or generic supertype. *)
type claim_producer_seal
type target_entry_producer_seal
type effect_producer_seal
type event_producer_seal
type frontier_producer_seal
type session_producer_seal
type before_after_producer_seal

val seal_claim :
  claim_producer_seal ->
  ('purpose, claim) prepared_attestation ->
  ('purpose, claim) current_attestation

val seal_target_entry :
  target_entry_producer_seal ->
  ('purpose, target_entry) prepared_attestation ->
  ('purpose, target_entry) current_attestation

val seal_effect :
  effect_producer_seal ->
  ('purpose, effect_role) prepared_attestation ->
  ('purpose, effect_role) current_attestation

val seal_event :
  event_producer_seal ->
  ('purpose, event) prepared_attestation ->
  ('purpose, event) current_attestation

val seal_frontier :
  frontier_producer_seal ->
  ('purpose, frontier) prepared_attestation ->
  ('purpose, frontier) current_attestation

val seal_session :
  session_producer_seal ->
  ('purpose, session) prepared_attestation ->
  ('purpose, session) current_attestation

val seal_before_after :
  before_after_producer_seal ->
  ('purpose, before_after) prepared_attestation ->
  ('purpose, before_after) current_attestation

val compose :
  claim:('purpose, claim) current_attestation ->
  target_entry:('purpose, target_entry) current_attestation ->
  effect_attestation:('purpose, effect_role) current_attestation ->
  event:('purpose, event) current_attestation ->
  frontier:('purpose, frontier) current_attestation ->
  session:('purpose, session) current_attestation ->
  before_after:('purpose, before_after) current_attestation ->
  ('purpose abandonment_evidence_current, refusal) result
(** Exact purpose-indexed seven-argument current join. *)

val abandonment_evidence_digest :
  'purpose abandonment_evidence_current -> string

val source_digest : string
