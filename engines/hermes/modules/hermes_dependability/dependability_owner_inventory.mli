(** Pure five-owner inventory and terminal-conjunction algebra.

    This module owns no store, effect, capability, process, clock, filesystem,
    SQLite value, or upper [Run_*] type.  Prepared values are structural and
    nonauthorizing.  A current value additionally requires the distinct opaque
    producer seal for its exact role; producer-seal allocation belongs to root
    bootstrap and no seal constructor is exposed here. *)

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
  owner_session:Identity.t ->
  recovery_attempt:Identity.t ->
  challenge:Identity.t ->
  transition:Identity.t ->
  (context, refusal) result
(** Binds every fragment to one recovery-manifest attempt. *)

type denominator

val make_denominator :
  expected:Identity.t list ->
  observed:Identity.t list ->
  (denominator, refusal) result
(** Requires an exact, nonempty, duplicate-free, ordered denominator. *)

type activation
type writer_fence
type dispatch
type recovery_vault
type completion_store

type _ role =
  | Activation : activation role
  | Writer_fence : writer_fence role
  | Dispatch : dispatch role
  | Recovery_vault : recovery_vault role
  | Completion_store : completion_store role

type packed_role = Pack_role : 'role role -> packed_role

val role_id : packed_role -> string

type inventory_kind
type terminal_kind
type recovery_only_terminal_kind

type ('kind, 'role) prepared
type ('kind, 'role) current

type 'role fragment_prepared = (inventory_kind, 'role) prepared
type 'role fragment_current = (inventory_kind, 'role) current
type 'role terminal_fragment_prepared = (terminal_kind, 'role) prepared
type 'role terminal_fragment_current = (terminal_kind, 'role) current
type 'role recovery_only_terminal_fragment_prepared =
  (recovery_only_terminal_kind, 'role) prepared
type 'role recovery_only_terminal_fragment_current =
  (recovery_only_terminal_kind, 'role) current

val prepare_fragment :
  role:'role role ->
  context:context ->
  denominator:denominator ->
  owner_readback:Identity.t ->
  ('role fragment_prepared, refusal) result
(** Structural owner-local inventory preparation.  The result is neither
    current nor authorizing and cannot be composed by {!compose}. *)

val prepared_fragment_digest : ('kind, 'role) prepared -> string

type prepared_manifest

val prepare_manifest :
  activation:activation fragment_prepared ->
  writer_fence:writer_fence fragment_prepared ->
  dispatch:dispatch fragment_prepared ->
  recovery_vault:recovery_vault fragment_prepared ->
  completion_store:completion_store fragment_prepared ->
  (prepared_manifest, refusal) result
(** Exact five-argument structural join.  It exists so the algebra can be
    tested before root bootstrap distributes producer seals. *)

val prepared_manifest_digest : prepared_manifest -> string
val prepared_manifest_status : prepared_manifest -> [ `Prepared_nonauthorizing ]

(** Each producer-seal type is nominally distinct and abstract.  There is no
    generic producer seal and no lower constructor. *)
type activation_producer_seal
type writer_fence_producer_seal
type dispatch_producer_seal
type recovery_vault_producer_seal
type completion_store_producer_seal

val seal_activation_current :
  activation_producer_seal ->
  ('kind, activation) prepared ->
  ('kind, activation) current

val seal_writer_fence_current :
  writer_fence_producer_seal ->
  ('kind, writer_fence) prepared ->
  ('kind, writer_fence) current

val seal_dispatch_current :
  dispatch_producer_seal ->
  ('kind, dispatch) prepared ->
  ('kind, dispatch) current

val seal_recovery_vault_current :
  recovery_vault_producer_seal ->
  ('kind, recovery_vault) prepared ->
  ('kind, recovery_vault) current

val seal_completion_store_current :
  completion_store_producer_seal ->
  ('kind, completion_store) prepared ->
  ('kind, completion_store) current

type manifest

val compose :
  activation:activation fragment_current ->
  writer_fence:writer_fence fragment_current ->
  dispatch:dispatch fragment_current ->
  recovery_vault:recovery_vault fragment_current ->
  completion_store:completion_store fragment_current ->
  (manifest, refusal) result
(** The sole exact current inventory join.  No list, generic fragment or
    caller-supplied manifest digest is accepted. *)

val manifest_digest : manifest -> string

type _ terminal_readback =
  | Activation_terminal_readback :
      { current_pointer : Identity.t } -> activation terminal_readback
  | Writer_fence_terminal_readback :
      { mutation_frontier : Identity.t; fence : Identity.t } ->
      writer_fence terminal_readback
  | Dispatch_terminal_readback :
      { dispatch_readback : Identity.t } -> dispatch terminal_readback
  | Recovery_vault_terminal_readback :
      { vault_readback : Identity.t } -> recovery_vault terminal_readback
  | Completion_store_terminal_readback :
      { completion_readback : Identity.t } -> completion_store terminal_readback

val prepare_terminal_fragment :
  fragment:'role fragment_prepared ->
  unresolved_obligations:int ->
  readback:'role terminal_readback ->
  ('role terminal_fragment_prepared, refusal) result
(** Requires exactly zero unresolved obligations. *)

type prepared_terminal_conjunction

val prepare_terminal_conjunction :
  activation:activation terminal_fragment_prepared ->
  writer_fence:writer_fence terminal_fragment_prepared ->
  dispatch:dispatch terminal_fragment_prepared ->
  recovery_vault:recovery_vault terminal_fragment_prepared ->
  completion_store:completion_store terminal_fragment_prepared ->
  (prepared_terminal_conjunction, refusal) result

val prepared_terminal_digest : prepared_terminal_conjunction -> string
val prepared_terminal_status :
  prepared_terminal_conjunction -> [ `Prepared_nonauthorizing ]

type terminal_conjunction

val compose_terminal_conjunction :
  activation:activation terminal_fragment_current ->
  writer_fence:writer_fence terminal_fragment_current ->
  dispatch:dispatch terminal_fragment_current ->
  recovery_vault:recovery_vault terminal_fragment_current ->
  completion_store:completion_store terminal_fragment_current ->
  (terminal_conjunction, refusal) result

val terminal_conjunction_digest : terminal_conjunction -> string

type prepared_conditional_terminal

val prepare_conditional_terminal :
  activation:activation terminal_fragment_prepared ->
  dispatch:dispatch terminal_fragment_prepared ->
  (prepared_conditional_terminal, refusal) result
(** The exact activation/dispatch zero-unresolved-obligation join. *)

val prepared_conditional_terminal_digest :
  prepared_conditional_terminal -> string

val prepared_conditional_terminal_status :
  prepared_conditional_terminal -> [ `Prepared_nonauthorizing ]

type conditional_terminal_current

val compose_conditional_terminal :
  activation:activation terminal_fragment_current ->
  dispatch:dispatch terminal_fragment_current ->
  (conditional_terminal_current, refusal) result

val conditional_terminal_digest : conditional_terminal_current -> string

type _ recovery_only_readback =
  | Recovery_activation_terminal_readback :
      { causal_transition : Identity.t;
        successor_generation_pointer : Identity.t } ->
      activation recovery_only_readback
  | Recovery_writer_fence_terminal_readback :
      { mutation_frontier : Identity.t; fence : Identity.t } ->
      writer_fence recovery_only_readback
  | Recovery_dispatch_terminal_readback :
      { dispatch_readback : Identity.t;
        operation_tree_source_readback : Identity.t } ->
      dispatch recovery_only_readback
  | Recovery_vault_readback :
      { recovery_readback : Identity.t } -> recovery_vault recovery_only_readback
  | Recovery_completion_store_readback :
      { completion_readback : Identity.t } ->
      completion_store recovery_only_readback

val prepare_recovery_only_terminal_fragment :
  fragment:'role fragment_prepared ->
  readback:'role recovery_only_readback ->
  ('role recovery_only_terminal_fragment_prepared, refusal) result
(** A separate causal recovery-only preparation.  It cannot be formed from an
    ordinary success, divergence, exhaustion, or no-effect terminal fact. *)

type prepared_recovery_only_terminal

val prepare_recovery_only_terminal :
  activation:activation recovery_only_terminal_fragment_prepared ->
  writer_fence:writer_fence recovery_only_terminal_fragment_prepared ->
  dispatch:dispatch recovery_only_terminal_fragment_prepared ->
  recovery_vault:recovery_vault recovery_only_terminal_fragment_prepared ->
  completion_store:completion_store recovery_only_terminal_fragment_prepared ->
  (prepared_recovery_only_terminal, refusal) result

val prepared_recovery_only_terminal_digest :
  prepared_recovery_only_terminal -> string

val prepared_recovery_only_terminal_status :
  prepared_recovery_only_terminal -> [ `Prepared_nonauthorizing ]

type recovery_only_terminal_current

val compose_recovery_only_terminal :
  activation:activation recovery_only_terminal_fragment_current ->
  writer_fence:writer_fence recovery_only_terminal_fragment_current ->
  dispatch:dispatch recovery_only_terminal_fragment_current ->
  recovery_vault:recovery_vault recovery_only_terminal_fragment_current ->
  completion_store:completion_store recovery_only_terminal_fragment_current ->
  (recovery_only_terminal_current, refusal) result

val recovery_only_terminal_digest : recovery_only_terminal_current -> string

val current_join_authority : [ `Lower_pure_nonauthorizing ]
(** All current values are proofs/data only.  This module exposes no operation
    that can interpret them as an effect or runtime capability. *)

val source_digest : string
