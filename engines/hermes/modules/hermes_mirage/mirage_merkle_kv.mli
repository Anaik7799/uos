(** Irmin-Style Merkle DAG Key-Value Store satisfying MIRAGE_KV (EV-87) *)

type t

val create : unit -> t
val get : t -> string list -> (string, Mirage_signatures.error) result
val set : t -> string list -> string -> (t, Mirage_signatures.write_error) result
val remove : t -> string list -> (t, Mirage_signatures.write_error) result
val list : t -> string list -> (string list list, Mirage_signatures.error) result
val digest : t -> string list -> (string, Mirage_signatures.error) result
val root_hash : t -> string
val branch : t -> t
val merge : our:t -> their:t -> (t, string) result
