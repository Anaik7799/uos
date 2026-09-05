(** Generated documentation projections for the declarative-configuration
    ontology, fractal functional atlas, and fractal functional algebra. *)

val surfaces : unit -> (string * string) list
val drifted : unit -> string list
val cross_reference_drift : unit -> string list
val write : unit -> (string, string) result
val check : unit -> string * int
