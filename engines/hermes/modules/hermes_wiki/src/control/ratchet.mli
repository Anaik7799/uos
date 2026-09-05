(* HW.10.2.1 — warnings as errors, the ratchet: every monitored count is
   monotone non-increasing against an in-tree pin. A breach REFUSES; an
   improvement invites a deliberate re-pin (outside the battery, like the
   render baseline). The evaluator is an S36 instance: pins are the
   declaration, sensed gauges the observation, and the verdict list is a
   read of the residue — fail-closed on unknown gauges in BOTH directions
   (a gauge without a pin and a pin without a gauge are each drift).

   Gauge names are law-tied to Wiki_topology telemetry channels
   (test_ratchet): a count the actor model does not name cannot be
   ratcheted. R14 mirrors: Sphinx -W; zigvm e9 parity non-regression. *)

type verdict =
  | Held of { gauge : string; at : int }                          (* current = pin *)
  | Improved of { gauge : string; previous : int; current : int } (* current < pin: re-pin invited *)
  | Breached of { gauge : string; previous : int; current : int } (* current > pin: REFUSE *)

(* The atlas signature, the whole law in one function:
   Ok iff current <= previous. *)
val check : previous:int -> current:int -> (unit, string) result

val judge : gauge:string -> previous:int -> current:int -> verdict

(* Pin-file lines <-> pins. Total: a malformed line is a NAMED error, a
   duplicate gauge is refused (write functionality). One canonical
   serialisation: sorted by gauge, "gauge value". parse of serialize is
   the identity. *)
val parse_pins : string list -> ((string * int) list, string) result
val serialize_pins : (string * int) list -> string list

(* Every pin must be sensed and every sensed gauge pinned — unknowns on
   either side fail closed with the offender named. Verdicts are sorted
   by gauge (one serialisation, pinnable). *)
val evaluate :
  pins:(string * int) list ->
  gauges:(string * int) list ->
  (verdict list, string) result

val breaches : verdict list -> verdict list
val render : verdict -> string
