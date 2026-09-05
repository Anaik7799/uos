(* Bayesian reliability over parity receipts -- the exact Beta-Binomial
   conjugate, mirrored from the zigvm stan_bridge (R14). Pure OCaml: the
   closed-form posterior IS the oracle a future MCMC sampler would be admitted
   against. Pseudo-replication-safe by construction (the input is the
   latest-per-scenario read); censoring disclosed, never denominated; and NO
   AUTHORITY -- posteriors annotate, they never gate. *)

type posterior = { alpha : float; beta : float }

(* prior Beta(a,b) + (k passes / n scenarios) -> Beta(a+k, b+n-k). EXACT. *)
let posterior ~a ~b ~n ~k =
  { alpha = a +. float_of_int k; beta = b +. float_of_int (n - k) }

let mean p = p.alpha /. (p.alpha +. p.beta)

let variance p =
  let s = p.alpha +. p.beta in
  p.alpha *. p.beta /. (s *. s *. (s +. 1.0))

(* The bounded moment band (mean +/- 2 sd, clamped): an honest report-only
   summary. The exact Beta quantile needs the inverse incomplete beta; zigvm
   deliberately did not pretend to it, and neither do we. *)
let cred95 p =
  let m = mean p and sd = sqrt (variance p) in
  (Float.max 0.0 (m -. (2.0 *. sd)), Float.min 1.0 (m +. (2.0 *. sd)))

type node_reliability = {
  node : string;
  scenarios : int;
  passing : int;
  post : posterior;
}

(* Uniform prior Beta(1,1), stated. The rows are latest-per-scenario, so n is a
   population of scenarios, not a history of correlated re-runs. *)
let per_node rows =
  let nodes =
    rows
    |> List.map (fun (contract, _) -> Evidence_rollup.node_of_contract contract)
    |> List.sort_uniq compare
  in
  List.map
    (fun node ->
      let mine =
        List.filter (fun (contract, _) -> Evidence_rollup.node_of_contract contract = node) rows
      in
      let n = List.length mine in
      let k = List.length (List.filter snd mine) in
      { node; scenarios = n; passing = k; post = posterior ~a:1.0 ~b:1.0 ~n ~k })
    nodes

let unmeasured ~measured ~all_nodes =
  List.filter (fun node -> not (List.exists (fun r -> r.node = node) measured)) all_nodes

let render r =
  let low, high = cred95 r.post in
  Printf.sprintf "%-45s %2d/%-2d pass  P(pass)=%.2f  [%.2f, %.2f]" r.node r.passing
    r.scenarios (mean r.post) low high
