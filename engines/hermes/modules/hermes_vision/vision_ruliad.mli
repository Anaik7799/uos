(* Ruliad: multiway exploration of the diagnosis rule-space.

   The rete tests assert order-independence on ONE example. The ruliad
   framing already landed in this repository — rule-space exploration,
   multiway branching, causal invariance — and this applies it where it
   actually pays: CAUSAL INVARIANCE IS EXACTLY THE ORDER-INDEPENDENCE
   CLAIM. If the diagnosis depends on the order facts arrive in, it is
   an artefact of the harness rather than a property of the system, and
   one hand-picked example cannot show otherwise.

   So the whole reachable state space is enumerated — every assignment
   of LIVE/ABSENT/UNKNOWN to six stages — and every branch is checked.

   3^6 = 729 states, each with permuted fact orders. Small enough to
   explore exhaustively, which is the point: where the space IS
   enumerable, sampling it is a choice to know less. *)

type state = string list   (* one verdict per stage, in ontology order *)

val states : unit -> state list
val facts_of_state : state -> Vision_rules.fact list

(* Every state whose diagnosis depends on the ORDER the facts arrived
   in. Empty is the law — causal invariance over the whole space, not
   over one example. *)
val order_dependent : unit -> state list

(* Every state where a stage is blamed although its upstream also
   failed. Empty is the cascade law, checked exhaustively rather than on
   the one cascade a test author thought of. *)
val cascade_violations : unit -> state list

(* Every state where an unmeasured stage is blamed. Empty is the second
   law. *)
val unmeasured_blamed : unit -> state list

(* States that reach no conclusion at all. Reported rather than assumed
   empty: a rule set that silently declines on some inputs is a rule set
   with holes. *)
val undiagnosed : unit -> state list

val summary : unit -> string
