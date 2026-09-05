val sha256_string : string -> string
val sha256_file : string -> (string, [ `Msg of string ]) result

module Content_id : sig
  type t
  val of_string : string -> t
  val parse : string -> (t, string) result
  val to_string : t -> string
  val equal : t -> t -> bool
end
