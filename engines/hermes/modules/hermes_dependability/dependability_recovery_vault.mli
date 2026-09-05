(** Bounded, nonauthorizing recovery-vault foundation.

    The vault binds sealed content identities and exact recovery progress but
    never exposes a native path, locator, bytes, filesystem handle, or upper
    [Run_*]/[Ops_*] value.  Production physical effects remain unavailable
    until the descriptor-relative filesystem backend and nominal authority-
    store vault-open fences are implemented.  The injected algebra under
    {!For_test} performs no effect and cannot mint a current owner fragment. *)

type rca_origin =
  | Specification
  | Implementation
  | Environment
  | Evidence
  | Control

type diagnostic

val diagnostic_code : diagnostic -> string
val diagnostic_coordinate : diagnostic -> string
val diagnostic_origin : diagnostic -> rca_origin

type b_success
type completion_record

type _ purpose =
  | B_success : b_success purpose
  | Completion_record : completion_record purpose

type packed_purpose = Pack_purpose : 'purpose purpose -> packed_purpose

val purpose_id : packed_purpose -> string

type context
type current_context

val prepare_context :
  manifest:Jj_id.Receipt.t ->
  authority:Dependability_authority_store.operational ->
  recovery_attempt:Jj_id.Request.t ->
  challenge:Jj_id.Receipt.t ->
  transition:Jj_id.Receipt.t ->
  observed_at:Dependability_clock.receipt ->
  (context, diagnostic) result
(** Prepared context is manifest/session/attempt/transition bound but remains
    nonauthorizing. *)

val context_digest : context -> string

val validate_context_current :
  now:Dependability_clock.receipt ->
  context ->
  (current_context, diagnostic) result
(** Validates the private bounded clock receipt.  This proves freshness only;
    it does not substitute for the not-yet-landed authority-store vault fence. *)

val current_context_digest : current_context -> string

type anchors

val prepare_anchors :
  operation:Jj_id.Operation.t ->
  workspace:Jj_id.Workspace.t ->
  source:Jj_id.Receipt.t ->
  anchors
(** Operation/workspace/source identities are retained only in the sealed
    digest. *)

type object_role = Original | Candidate | Remainder

val object_role_id : object_role -> string

type sealed_object

val max_object_size_bytes : int

val seal_absent :
  ?role:object_role ->
  locator:Jj_id.Receipt.t ->
  unit ->
  (sealed_object, diagnostic) result
(** Only an [Original] object may be absent. *)

val seal_present :
  role:object_role ->
  locator:Jj_id.Receipt.t ->
  mode:Jj_split_manifest.file_mode ->
  size_bytes:int ->
  content_digest:Jj_split_manifest.Digest.t ->
  symlink_target_digest:Jj_split_manifest.Digest.t option ->
  (sealed_object, diagnostic) result
(** Accepts metadata and content identities only; no bytes or raw locator can
    be recovered from the result.  Symlink content and target digests must be
    identical, while non-symlinks must not carry a target digest. *)

val sealed_object_digest : sealed_object -> string

type 'purpose prepared

val max_entries : int

val prepare :
  purpose:'purpose purpose ->
  context:current_context ->
  anchors:anchors ->
  objects:sealed_object list ->
  ('purpose prepared, diagnostic) result
(** Requires one exact [Original], [Candidate], and [Remainder] object per
    redacted locator, with no duplicate or missing role. *)

val prepared_status : 'purpose prepared -> [ `Prepared_nonauthorizing ]
val prepared_entry_count : 'purpose prepared -> int
val prepared_digest : 'purpose prepared -> string

(** Nominal production roles.  No constructor is exposed and the open
    functions below currently refuse, so no caller can obtain or serialize a
    capability. *)
type 'purpose operational_capability
type 'purpose recovery_capability
type lifecycle_capability
type effect_receipt

val open_operational :
  purpose:'purpose purpose ->
  context:current_context ->
  (('purpose operational_capability * lifecycle_capability), diagnostic) result

val open_recovery :
  purpose:'purpose purpose ->
  context:current_context ->
  (('purpose recovery_capability * lifecycle_capability), diagnostic) result

val stage_once :
  'purpose operational_capability ->
  'purpose prepared ->
  request:Jj_id.Request.t ->
  (effect_receipt, diagnostic) result

val restore_once :
  'purpose recovery_capability ->
  'purpose prepared ->
  request:Jj_id.Request.t ->
  (effect_receipt, diagnostic) result

val readback_once :
  'purpose recovery_capability ->
  'purpose prepared ->
  request:Jj_id.Request.t ->
  (effect_receipt, diagnostic) result

val cleanup_once :
  lifecycle_capability ->
  'purpose prepared ->
  request:Jj_id.Request.t ->
  (effect_receipt, diagnostic) result
(** Every physical entrypoint is [Unavailable_observed] in this foundation. *)

val effect_receipt_digest : effect_receipt -> string
val effect_receipt_replayed : effect_receipt -> bool

type action = Stage | Restore | Readback | Cleanup

val action_id : action -> string

type lifecycle_state =
  | Prepared
  | Staging
  | Staged
  | Restoring
  | Restored
  | Reading_back
  | Readback_verified
  | Cleaning
  | Cleaned
  | Indeterminate of action

val source_digest : string

module For_test : sig
  (** A persistent injected state machine.  Observations are typed identities,
      not callbacks or effect closures; its outputs are explicitly
      nonauthorizing. *)
  type 'purpose model
  type injected_outcome = Applied_exact | Reply_lost
  type lost_reply_resolution =
    | Applied_exact_on_readback
    | Not_applied_on_readback
  type transition_receipt

  val start : 'purpose prepared -> 'purpose model
  val state : 'purpose model -> lifecycle_state
  val completed : 'purpose model -> int
  val total : 'purpose model -> int
  val model_digest : 'purpose model -> string

  val step :
    'purpose model ->
    now:Dependability_clock.receipt ->
    request:Jj_id.Request.t ->
    action:action ->
    evidence:Jj_id.Receipt.t ->
    outcome:injected_outcome ->
    (('purpose model * transition_receipt), diagnostic) result

  val reconcile_lost_reply :
    'purpose model ->
    now:Dependability_clock.receipt ->
    request:Jj_id.Request.t ->
    action:action ->
    readback:Jj_id.Receipt.t ->
    resolution:lost_reply_resolution ->
    (('purpose model * transition_receipt), diagnostic) result

  val receipt_digest : transition_receipt -> string
  val receipt_replayed : transition_receipt -> bool

  val prepare_recovery_inventory :
    'purpose model ->
    now:Dependability_clock.receipt ->
    ( Dependability_owner_inventory.recovery_vault
      Dependability_owner_inventory.fragment_prepared,
      diagnostic )
    result
  (** Derives the exact sealed-object/progress/readback denominator and returns
      only a prepared fragment.  This module has no producer seal and cannot
      construct a current fragment. *)

  type mutation =
    | Cross_purpose_restore
    | Emit_raw_payload
    | Skip_currentness
    | Drop_replay_check
    | Guess_lost_reply
    | Forge_current_inventory
    | Skip_cleanup_order
    | Unbind_manifest_session
    | Enable_filesystem_backend

  val source_digest_with_mutation : mutation -> string
end
