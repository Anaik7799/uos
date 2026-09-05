(** Forward-chaining production-rule engine — the drift-diagnosis rule gate.

    Mirrored from the prior zigvm harness's [rete.ml] (R14), including its
    honest naming note: this is a NAIVE forward-chaining matcher, not the Rete
    algorithm — no alpha/beta network, no token memories, no unlinking. At this
    fact/rule volume (dozens of facts, a handful of rules) the naive re-match is
    correct and fast, and what is load-bearing is the ZERO-TRUST GATE
    discipline: rules whose action returns [Error] REJECT the run, fail-closed.
    A genuine Rete network is worth building only if the volume grows.

    Facts are (kind, attribute) rows; patterns join facts across kinds through
    variable bindings; a rule's action either accepts (optionally inserting new
    facts — diagnosis) or rejects with a reason (the gate). *)

module Value : sig
  type t = Int of int | String of string | Bool of bool

  val to_string : t -> string
  val equals : t -> t -> bool
end

type fact = { fact_kind : string; attrs : (string * Value.t) list }

type operator = Eq | Neq | StartsWith | EndsWith

type condition =
  | FieldCmp of string * operator * Value.t  (** field vs constant *)
  | VarBind of string * string               (** bind variable to field *)
  | VarCmp of string * operator * string     (** field vs bound variable — the join *)

type pattern = { pat_kind : string; conds : condition list; bind_name : string option }

module WM : sig
  type t

  val create : unit -> t
  val insert : t -> string -> (string * Value.t) list -> unit
  val get_by_kind : t -> string -> fact list
end

type rule = {
  name : string;
  patterns : pattern list;
  action : WM.t -> (string * fact) list -> (unit, string) result;
}

val fire_rules : WM.t -> rule list -> (unit, string) result
(** Fire each rule over every complete pattern match (joins via bindings). The
    first action that returns [Error] rejects the whole run, naming the rule --
    the fail-closed gate. *)
