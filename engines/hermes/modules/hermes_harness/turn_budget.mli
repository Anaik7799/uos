(** L3 contract: immutable iteration budget shared by one agent turn lineage.

    Reference capability: [agent_loop.interrupt_control]
    Frozen anchor: [agent/iteration_budget.py]

    The Gospel specifications below are the contract obligation. They are
    unchecked until a [gospel] binary is available; see
    [gospel_contract_runner.ml]. An unchecked contract grants no parity
    credit. *)

type t = { maximum : int; consumed : int }

type consume_result = { allowed : bool; budget : t }

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

