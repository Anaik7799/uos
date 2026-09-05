(* Z3: proving the state machines rather than testing them.

   The restart tests assert that specific traces are legal or illegal.
   That is sampling. What the design actually claims is universal — NO
   path reaches Promoted without passing through Gating — and a test
   cannot establish that, only fail to refute it. SMT can.

   Three verdicts, as everywhere: [Discharged] when Z3 reports the
   negation unsatisfiable, [Refuted] with the counterexample when it
   finds one, and [Unavailable] when Z3 cannot be asked. A missing
   solver proves nothing and must never read as a proof. *)

type verdict =
  | Discharged of string
  | Refuted of string
  | Unavailable of string

val verdict_name : verdict -> string
val z3_available : unit -> bool

(* The bounded-reachability query for the restart machine, as SMT-LIB.
   Emitted so the obligation can be read and reviewed, not just run. *)
val promoted_requires_gating : depth:int -> string

(* NON-VACUITY. An `unsat` proves nothing if the encoding is
   contradictory — every query over a contradiction is unsat, so a proof
   suite built only from unsat results can be entirely vacuous. This
   control asserts a REACHABLE trace and must come back sat; if it does
   not, the encoding is broken and every discharge beside it is
   worthless. *)
val reachability_control : depth:int -> string

val check : string -> verdict

(* Both together: the obligation must be unsat AND the control sat.
   Either alone is not a proof. *)
val prove_restart_machine : ?depth:int -> unit -> verdict
