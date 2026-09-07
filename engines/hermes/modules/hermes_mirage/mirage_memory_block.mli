(** In-Memory Sector-Level Block Device satisfying MIRAGE_BLOCK (EV-87) *)

type t

val create : ?sector_size:int -> int64 -> (t, string) result
val get_info : t -> Mirage_signatures.block_info
val read : t -> int64 -> bytes list -> (unit, Mirage_signatures.error) result
val write : t -> int64 -> bytes list -> (unit, Mirage_signatures.write_error) result
val disconnect : t -> unit
