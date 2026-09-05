(** Validated hierarchical names used by every Sa-plan entity. *)

type t

val make : string list -> (t, string) result
val parse : string -> (t, string) result
val append : t -> string -> (t, string) result
val parent : t -> t option
val segments : t -> string list
val to_string : t -> string
val to_relpath : t -> string

