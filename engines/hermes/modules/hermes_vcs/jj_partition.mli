(** Pure proof that one B-recovery physical restoration matches the sealed
    partition manifest. This module owns no effect or authorizing value. *)

type restored

type error =
  | Invalid_symlink_target
  | Restored_payload_too_large
  | Physical_restoration_not_required
  | Partition_does_not_reconstruct
  | Path_mismatch
  | Mode_mismatch
  | Byte_mismatch
  | Symlink_target_mismatch

(** Constructors copy no payload into the proof. They retain only its
    SHA-256 digest and its exact physical kind. *)
val regular :
  path:Jj_path.t -> bytes -> (restored, error) result
val executable :
  path:Jj_path.t -> bytes -> (restored, error) result
val symlink :
  path:Jj_path.t -> target:bytes -> (restored, error) result

type proof

(** [prove] accepts only a B branch whose identity-free schema requires
    physical restoration. The manifest remains the sole source of expected
    path, full-byte digest, mode, and selected/remainder reconstruction. *)
val prove :
  branch:Jj_recovery_schema.b_branch ->
  partition:Jj_split_manifest.partition ->
  restored:restored ->
  (proof, error) result

val proof_path : proof -> Jj_path.t
val proof_mode : proof -> Jj_split_manifest.file_mode
val proof_manifest_digest : proof -> string
val proof_restored_blob : proof -> Jj_split_manifest.Digest.t
val proof_digest : proof -> string

val source_digest : string
