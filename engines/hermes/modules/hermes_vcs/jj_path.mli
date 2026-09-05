type t
type error = Empty | Too_long | Absolute | Invalid_segment | Glob_ambiguous

val make : string -> (t, error) result
val to_string : t -> string
val equal : t -> t -> bool
val compare : t -> t -> int
val source_digest : string
