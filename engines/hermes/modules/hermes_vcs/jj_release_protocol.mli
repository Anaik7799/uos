(** Pure release pin/observation consistency protocol.

    A bundle proves only that the supplied typed observations agree with the
    pin.  It is not a signature, approval, currentness, or execution receipt. *)

module Digest : sig
  type t
  val make : string -> (t, Jj_error.t) result
  val to_string : t -> string
end

type pin
type bundle

type mismatch =
  | Tag_mismatch
  | Commit_mismatch
  | Tree_mismatch
  | Archive_mismatch
  | Documentation_mismatch
  | Executable_mismatch
  | Config_mismatch

val pin :
  release_id:Jj_id.Request.t ->
  tag:Digest.t ->
  commit:Digest.t ->
  tree:Digest.t ->
  archive:Digest.t ->
  documentation:Digest.t ->
  executable:Digest.t ->
  config:Digest.t ->
  pin

val observe :
  pin:pin ->
  tag:Digest.t ->
  commit:Digest.t ->
  tree:Digest.t ->
  archive:Digest.t ->
  documentation:Digest.t ->
  executable:Digest.t ->
  config:Digest.t ->
  (bundle, mismatch list) result

val pin_digest : pin -> string
val bundle_digest : bundle -> string
val source_digest : string
