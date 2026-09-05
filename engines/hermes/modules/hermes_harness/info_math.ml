(* Exact information-theoretic primitives, log-domain throughout.

   ADAPTED from the operator-supplied expect_atlas Mathx module (2026-08-12
   paste) — one of the three modules whose source arrived COMPLETE; the
   surrounding binary remains truncated and is refused elsewhere. Landed here
   as a Dune library because each of these closes a named gap:

     - beta_pred / capacity   the PRINCIPLED prior the ledger design wants:
                              a site's change rate from its own history under
                              a Jeffreys prior, flakiness attenuated as a
                              binary-symmetric channel — replacing the
                              hand-authored constants both external reviews
                              named as this design's weak point.
     - eig_bits (Lindley)     expected information gain of a probe: the exact
                              machinery behind codex's counterfactual
                              discriminator — "choose the cheapest measurement
                              with maximum expected entropy reduction".
     - kl / entropy / lse2    the calibration loop's future Brier
                              decomposition needs these and nothing supplied
                              them.

   Everything is exact; nothing samples. The suite pins the paste's own
   numeric anchors (a 0/40 site moving carries 6.36 bits; a 26/40 site,
   0.63) so the port is verified against its source's claims, not assumed. *)

let log2 x = log x /. log 2.0

(* Binary entropy. Total at the edges: h2 0 = h2 1 = 0 by definition rather
   than NaN, because a limit the caller must special-case is a defect. *)
let h2 p =
  if p <= 0.0 || p >= 1.0 then 0.0
  else (-.p *. log2 p) -. ((1.0 -. p) *. log2 (1.0 -. p))

(* Posterior predictive P(event) under Beta(a,b) after k of n observations.
   With a = b = 0.5 this is the Jeffreys prior: a 0-of-n site does not get
   probability zero — zero would make its eventual change infinitely
   surprising, and an infinity in a report is a broken gauge. *)
let beta_pred ~k ~n ~a ~b = (k +. a) /. (n +. a +. b)

let clampp p = if p < 1e-12 then 1e-12 else if p > 1.0 then 1.0 else p
let surprisal p = -.log2 (clampp p)

(* Channel capacity of a binary symmetric channel with crossover epsilon.
   A site that flakes at rate ε carries at most this fraction of a bit per
   observation — the PRINCIPLED discount for flaky evidence, replacing any
   arbitrary penalty. At ε = 0.5 the capacity is exactly 0: the formal
   statement of "this verdict is independent of the code", which is what the
   event-store flake measured empirically before it was fixed. *)
let capacity ~epsilon = max 0.0 (1.0 -. h2 epsilon)

(* log-sum-exp in base 2, guarded against the empty case and overflow. *)
let lse2 = function
  | [] -> neg_infinity
  | xs ->
      let m = List.fold_left max neg_infinity xs in
      m +. log2 (List.fold_left (fun acc x -> acc +. (2.0 ** (x -. m))) 0.0 xs)

let normalize_log2 scores =
  let z = lse2 scores in
  List.map (fun s -> 2.0 ** (s -. z)) scores

let entropy_bits p =
  let e =
    List.fold_left (fun a x -> if x > 1e-12 then a -. (x *. log2 x) else a) 0.0 p
  in
  if e < 0.0 then 0.0 else e

let kl_bits p q =
  let s =
    List.fold_left2
      (fun a pi qi -> if pi > 1e-12 then a +. (pi *. log2 (pi /. clampp qi)) else a)
      0.0 p q
  in
  if s < 0.0 then 0.0 else s

(* Exact expected information gain I(H;Y) — Lindley's criterion. [post] is the
   current posterior over hypotheses; [outcomes] gives, per outcome label, the
   likelihood row P(y|h). This is the number that turns "which probe next?"
   from a preference into an argmax: run the measurement whose EIG per unit
   cost is highest. *)
let eig_bits ~post ~outcomes =
  let n = Array.length post in
  let total = ref 0.0 in
  List.iter
    (fun (_label, row) ->
      let py = ref 0.0 in
      for j = 0 to n - 1 do
        py := !py +. (post.(j) *. row.(j))
      done;
      if !py > 1e-12 then
        for j = 0 to n - 1 do
          if row.(j) > 1e-12 && post.(j) > 1e-12 then
            total := !total +. (post.(j) *. row.(j) *. log2 (row.(j) /. !py))
        done)
    outcomes;
  if !total < 0.0 then 0.0 else !total
