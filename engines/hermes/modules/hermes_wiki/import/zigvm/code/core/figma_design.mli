(** Pure OCaml design algebra projected into an editable Figma interpretation.
    Runtime equivalence is still decided by Bonsai plus typed OCaml Playwright. *)

type observation = {
  modes : string list;
  breakpoints : (string * int) list;
  tokens : string list;
  pages : string list;
  components : string list;
  component_variants : (string * string list) list;
  product_screens : string list;
  screens : string list;
  transitions : string list;
  minimum_target : int;
}

module Initial : sig
  type t
  val default : unit -> t
end

module Final : sig
  type t
  val default : unit -> t
  val with_minimum_target : t -> int -> t
end

val observe_initial : Initial.t -> observation
val observe_final : Final.t -> observation
val validate_final : Final.t -> (unit, string list) result
val to_yojson : Final.t -> Yojson.Safe.t
