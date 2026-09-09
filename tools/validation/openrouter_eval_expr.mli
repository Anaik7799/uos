(** Restricted expression algebra. Terms are constructible only by the bounded
    parser; recursive and compiled observations must agree on every environment. *)
type language = Gleam | Ocaml | Mojo | Quint
type value = Number of int | Boolean of bool
type term
exception Invalid of string
val reject : string -> 'a
val require : bool -> string -> unit
val parse : language -> string list -> string -> term
val observe : (string * value) list -> term -> value
val compile : term -> (string * value) list -> value
val render : language -> term -> string
val number : value -> int
val boolean : value -> bool
val same : value -> value -> bool
val lookup : (string * value) list -> string -> value
val json_value : value -> [> `Int of int | `Bool of bool ]
