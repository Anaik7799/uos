(** Deterministic text-to-concept graph initial encoding. *)

val tokenize : string -> string list
val from_text : ?window:int -> id:string -> title:string -> string -> Graph_intelligence.t
val sentiment : string -> float

