(** L3 contract: Interrupt control and turn budget management.

    Reference capability: [agent_loop.interrupt_control]
    Frozen anchor: [agent_loop.interrupt_control.70b2efe95be5.json]
*)

type t = Turn_budget.t = { maximum : int; consumed : int }

type consume_result = Turn_budget.consume_result = { allowed : bool; budget : t }

(*@ predicate well_formed (b: t) =
      b.consumed >= 0 &&
      b.consumed <= (if b.maximum >= 0 then b.maximum else 0) *)

val create : int -> t
(*@ b = create maximum
    pure
    ensures b.consumed = 0
    ensures b.maximum = maximum
    ensures well_formed b *)

val used : t -> int
(*@ n = used b
    pure
    requires well_formed b
    ensures n = b.consumed
    ensures n >= 0 *)

val remaining : t -> int
(*@ n = remaining b
    pure
    requires well_formed b
    ensures n = (if b.maximum - b.consumed >= 0 then b.maximum - b.consumed else 0)
    ensures n >= 0 *)

val consume : t -> consume_result
(*@ r = consume b
    requires well_formed b
    ensures well_formed r.budget
    ensures r.budget.maximum = b.maximum
    ensures r.allowed <-> b.consumed < b.maximum
    ensures r.allowed -> r.budget.consumed = b.consumed + 1
    ensures not r.allowed -> r.budget = b
    ensures used r.budget = used b + (if r.allowed then 1 else 0) *)

val refund : t -> t
(*@ c = refund b
    pure
    requires well_formed b
    ensures well_formed c
    ensures c.maximum = b.maximum
    ensures c.consumed = if b.consumed = 0 then 0 else b.consumed - 1 *)

val process : model_id:string -> messages:Yojson.Safe.t list -> Yojson.Safe.t
(*@ res = process ~model_id ~messages
    pure *)
