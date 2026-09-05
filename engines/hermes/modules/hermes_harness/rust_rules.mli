(** The embedded Rust rule engine (rust-rule-engine, GRL), integrated via FFI.

    A second, independent rule engine beside the OCaml {!Hermes_rete} mirror --
    admitted under the harness's own discipline: the OCaml engine is the
    reference, and the differential test in [test_rust_rules] asserts both
    engines reach the same conclusions over the same drift facts. The FFI
    surface is one call, JSON in and JSON out (the oracle discipline: validated
    output, classified failure, absence/crash is an [Error], never a wrong
    answer). The Rust side never panics across the boundary.

    GRL (Grule Rule Language) example:
    {v
      rule FixCandidate "divergent drift needs a candidate fix" {
          when Drift.Actual == "divergent"
          then Drift.Advice = "fix-candidate";
      }
    v} *)

type result = {
  rules_fired : int;
  cycle_count : int;
  facts : Yojson.Safe.t;  (** the facts object after then-actions ran *)
}

val eval : grl:string -> facts:Yojson.Safe.t -> (result, string) Stdlib.result
(** Run the GRL rules over the facts (an object of fact-name -> field object).
    Every failure -- unreadable input, rejected GRL, execution error, engine
    crash -- is [Error reason]; the call never raises. *)

val available : unit -> bool
(** True: the engine is statically linked. Exposed so callers can state the
    dependency uniformly with other oracles. *)
