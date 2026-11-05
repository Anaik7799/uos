(** Metadata observation only. No locator, key, signer or authority constructor.
    A production launcher binding is deliberately absent. *)
type observation
val observe : unit -> observation
val encode : observation -> string
val serve : unit -> unit
