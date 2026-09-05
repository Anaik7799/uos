(* The gap plan as tracked DATA: every open item from the inventory, its
   phase, its approach, and — where a live predicate exists — a status
   DERIVED from the running system rather than hand-maintained. Closing an
   item flips this module's output with no edit to a status field, which
   is the only kind of progress tracking that cannot lie.

   Source of the item list: docs/hermes/gap-execution-plan.md and
   docs/hermes/wiki-zk-migration-plan.md. *)

type state = Open | Partial | Closed

type item = {
  id : string;         (* the inventory id: F-CO-2, c3i-4, W3, ... *)
  phase : string;      (* execution phase from the plan *)
  title : string;
  evidence : string;   (* what closes it / how it is checked *)
  derived : (unit -> state) option;  (* live predicate, when one exists *)
  declared : state;    (* fallback when no predicate is possible *)
}

type summary = { closed : int; partial : int; open_ : int }

val items : item list
val status : item -> state
val summary : unit -> summary
val by_phase : unit -> (string * item list) list

(* Items whose DERIVED status disagrees with a stale declaration — the
   self-check that keeps the tracker honest. *)
val stale_declarations : unit -> string list
