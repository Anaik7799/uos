(** Bayesian reliability over parity receipts — the Stan leg, mirrored from the
    zigvm stan_bridge (R14).

    The FIRST model is CONJUGATE (Beta-Binomial), computed exactly in pure OCaml:
    prior Beta(a,b) + k passes of n scenarios -> posterior Beta(a+k, b+n-k). The
    closed form IS the oracle any future MCMC sampler would be differentially
    admitted against (the zigvm substrate discipline).

    Two statistical-honesty laws carried over verbatim:
    - PSEUDO-REPLICATION: historical re-runs of a deterministic check are
      correlated, so the honest observation unit is a scenario's LATEST verdict
      (exactly what {!Evidence_store.parity_results} returns), and the posterior
      lives over the population of scenarios per node.
    - CENSORING: a node with no receipts is absence of evidence, not evidence of
      failure — it is disclosed as unmeasured, never placed in a denominator.

    NO AUTHORITY: posteriors and credible bands ANNOTATE the parity picture
    beside the hard verdicts; they never gate, never decide, never grant or deny
    credit (R10 untouched). *)

type posterior = { alpha : float; beta : float }

val posterior : a:float -> b:float -> n:int -> k:int -> posterior
(** Exact conjugate update: Beta(a+k, b+n-k). *)

val mean : posterior -> float
val variance : posterior -> float

val cred95 : posterior -> float * float
(** The bounded moment band (mean +/- 2 sd, clamped to [0,1]) — an honest,
    report-only summary; the exact Beta quantile needs the inverse incomplete
    beta and is deliberately not pretended to. *)

type node_reliability = {
  node : string;
  scenarios : int;   (** n: scenarios with a latest verdict under this node *)
  passing : int;     (** k *)
  post : posterior;  (** Beta(1+k, 1+n-k): uniform prior Beta(1,1), stated *)
}

val per_node : (string * bool) list -> node_reliability list
(** Group latest-per-scenario [(contract_id, passed)] rows (the
    pseudo-replication-safe read) by fractal node via
    {!Evidence_rollup.node_of_contract}; uniform prior; sorted by node. *)

val unmeasured : measured:node_reliability list -> all_nodes:string list -> string list
(** The censoring disclosure: nodes with no receipts at all, reported beside the
    table, never inside it. *)

val render : node_reliability -> string
