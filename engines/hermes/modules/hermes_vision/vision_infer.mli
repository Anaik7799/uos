(* Stan: how confident is a pass rate?

   "The suite passed" and "the suite passed 40 times out of 40" are
   different claims, and a flaky stage is the failure mode that survives
   longest precisely because a single green run cannot distinguish it
   from a healthy one. This estimates the underlying pass rate from
   observed runs, with an interval — so "we have not seen it fail" and
   "we have shown it rarely fails" stop being the same sentence.

   -------------------------------------------------------------------
   THE POSTERIOR IS COMPUTED HERE; STAN IS THE ORACLE

   Beta-Binomial is conjugate, so the posterior is exact and needs no
   sampler. Computing it in OCaml means the estimate is available with
   no toolchain at all, and it is deterministic — an MCMC estimate would
   differ run to run and could not be an expect-tested value.

   Stan's role is to CHECK that, not to produce it. [stan_model] emits
   the model whose posterior must agree, and [stan_available] says
   whether cmdstan can be asked. When it cannot, the cross-check is
   Unavailable — never silently skipped, and never taken as agreement. *)

type estimate = {
  runs : int;
  passes : int;
  mean : float;        (* posterior mean pass rate *)
  low : float;         (* 5% credible bound *)
  high : float;        (* 95% credible bound *)
}

(* Jeffreys prior (Beta 1/2, 1/2): it does not pretend 0/0 runs mean a
   50% pass rate the way a uniform prior nearly does, and it does not
   claim certainty from a single observation. *)
val estimate : runs:int -> passes:int -> (estimate, string) result

(* THE POINT OF THE INTERVAL. A stage that has passed every observed run
   may still fail often enough to matter; this answers whether the
   evidence RULES OUT a failure rate above [threshold]. Zero failures in
   three runs does not. *)
val rules_out_flakiness : estimate -> threshold:float -> bool

(* How many consecutive passes are needed before a rate above
   [threshold] is ruled out at 95%. The number is usually larger than
   people expect, which is the useful part. *)
val runs_needed : threshold:float -> int

(* The Stan model for the same posterior, emitted so the oracle can be
   asked whether it agrees. *)
val stan_model : string
val stan_available : unit -> bool

(* Cross-check against Stan. [Ok agreement] when cmdstan verified the
   model compiles; [Error] when it refused; and the whole thing is
   [Unavailable] as an Error naming that, never a quiet pass. *)
val stan_check : unit -> (string, string) result
