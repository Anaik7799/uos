(** Distinct bounded ASCII identities. Equal text never erases identity kind. *)

module type ID = sig
  type t
  val make : string -> (t, Jj_error.t) result
  val to_string : t -> string
end

module Repository : ID
module Workspace : ID
module Operation : ID
module Change : ID
module Commit : ID
module Bookmark : ID
module Remote : ID
module Executable : ID
module Approval : ID
module Lease : ID
module Intent : ID
module Request : ID
module Event : ID
module Receipt : ID
(* Immutable SHA-256 identities accept exactly 64 lowercase hexadecimal
   bytes; unlike the general IDs they are not human tokens. *)
module Formal_source : ID
module Formal_model : ID
(* Bounded canonical identity for a named formal negative-control case. *)
module Negative_control : ID

val length_frame : string list -> string
val source_digest : string
