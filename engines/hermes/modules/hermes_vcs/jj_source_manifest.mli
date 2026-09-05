(** Pure immutable source-manifest authority. All observations are injected by
    a controlled adapter; this module owns no filesystem or process effect. *)

module Identity : sig
  type t
  type error = Empty | Too_long | Invalid_byte
  val make : string -> (t, error) result
  val to_string : t -> string
end

module Symlink_target : sig
  type t
  type error = Empty | Too_long | Invalid_byte
  val make : string -> (t, error) result
  val to_string : t -> string
end

module Exclusion_reason : sig
  type t
  type error = Empty | Too_long | Invalid_byte
  val make : string -> (t, error) result
  val to_string : t -> string
end

type error =
  | Invalid_size
  | Carrier_refused of Mainline_carrier_policy.refusal
  | Symlink_target_required
  | Symlink_target_forbidden
  | Symlink_size_mismatch
  | Symlink_digest_mismatch
  | Invalid_sanitization_identity
  | Exclusion_reason_required
  | Exclusion_reason_forbidden
  | Empty_manifest
  | Too_many_entries
  | Path_identity_conflict

type entry

val entry :
  path:Jj_path.t ->
  mode:Jj_split_manifest.file_mode ->
  symlink_target:Symlink_target.t option ->
  size_bytes:int ->
  content_digest:Jj_split_manifest.Digest.t ->
  artifact:Mainline_carrier_policy.artifact_class ->
  disposition:Mainline_carrier_policy.disposition ->
  sanitizer_identity:Identity.t option ->
  projection_identity:Identity.t option ->
  exclusion_reason:Exclusion_reason.t option ->
  (entry, error) result

val entry_digest : entry -> string

type t

val max_entries : int
val make : entry list -> (t, error) result
val entry_count : t -> int
val entries : t -> entry list
val digest : t -> string
val schema_id : string
val source_digest : string
