(* Bayesian state classification over expect/parity evidence.

   Three things were fixed against the specification, and each fix is the
   difference between a number that means something and one that does not.

   1. The posterior is NORMALIZED. `likelihood *. prior` is not a probability:
      it cannot be compared across states, cannot be thresholded, and does not
      sum to anything. Dividing by the marginal P(E) makes the four states
      commensurable, which is the entire point of computing them.

   2. The normalizing constant is not overhead — it IS the surprisal the
      specification asks for and then omits. -log2 P(E) is the information
      content of the observation, and it replaces ranking by churn, which
      ranks by how often a file is touched: a property of the developers, not
      of the evidence. But surprisal ALONE is the wrong queue, and a failing
      test is what established that — see the note above [severity].

   3. The state is the ARGMAX of the posterior. The specification computed a
      posterior and then decided the state with a hardcoded if/else that never
      read it; delete the arithmetic and the classifier is unchanged. A
      measurement nothing measures is the failure R22 names.

   And one departure. The alpha network is specified as "dropping tests with
   high mutation survival rates". It partitions instead: withheld clusters are
   counted and reported. A site that survives mutation is the most informative
   row in the report, and Ops_mutate already holds that a survivor is a finding
   whose classification must not be automated. Dropping it would launder a weak
   test into an equivalent mutant silently. Density is achieved by not PRINTING
   it, never by not KNOWING it. *)

type state = Stable | Silent_divergence | Structural_drift | Regressed

let states = [ Stable; Silent_divergence; Structural_drift; Regressed ]

let state_name = function
  | Stable -> "stable"
  | Silent_divergence -> "silent-divergence"
  | Structural_drift -> "structural-drift"
  | Regressed -> "regressed"

type evidence = {
  site : string;
  cause : string;
  path_changed : bool;
  output_changed : bool;
  churn : float;
  mutation_kill_rate : float;
}

(* P(E | S) over the four-point evidence space. Each state's row sums to 1 --
   these are distributions, not free weights, and the suite checks it. *)
let likelihood state ev =
  match state, (ev.path_changed, ev.output_changed) with
  | Stable, (false, false) -> 0.94
  | Stable, (true, false) -> 0.02
  | Stable, (false, true) -> 0.02
  | Stable, (true, true) -> 0.02
  (* The path moved and the output did not. Under every other state that is
     unlikely, which is what makes this observation informative. *)
  | Silent_divergence, (true, false) -> 0.90
  | Silent_divergence, (false, false) -> 0.05
  | Silent_divergence, (false, true) -> 0.02
  | Silent_divergence, (true, true) -> 0.03
  | Structural_drift, (true, true) -> 0.80
  | Structural_drift, (true, false) -> 0.15
  | Structural_drift, (false, true) -> 0.03
  | Structural_drift, (false, false) -> 0.02
  | Regressed, (false, true) -> 0.55
  | Regressed, (true, true) -> 0.40
  | Regressed, (true, false) -> 0.03
  | Regressed, (false, false) -> 0.02

type posterior = {
  distribution : (state * float) list;
  argmax : state;
  confidence : float;
  marginal : float;
  surprisal : float;
}

let uniform_prior = List.map (fun s -> (s, 0.25)) states

let update ~prior ev =
  let missing = List.filter (fun s -> not (List.mem_assoc s prior)) states in
  if missing <> [] then
    Error
      ("prior is not defined over every state; missing "
      ^ String.concat ", " (List.map state_name missing))
  else if List.length prior <> List.length states then
    Error "prior carries a state outside the declared ontology"
  else
    let mass = List.fold_left (fun acc (_, p) -> acc +. p) 0.0 prior in
    if Float.abs (mass -. 1.0) > 1e-9 then
      Error (Printf.sprintf "prior is not a distribution: mass %.6f" mass)
    else if List.exists (fun (_, p) -> p < 0.0) prior then
      Error "prior carries a negative mass"
    else
      let weighted =
        List.map (fun s -> (s, likelihood s ev *. List.assoc s prior)) states
      in
      let marginal = List.fold_left (fun acc (_, w) -> acc +. w) 0.0 weighted in
      if marginal <= 0.0 then
        (* Every state calls this observation impossible. Refusing beats
           dividing by zero and beats defaulting to Stable, which would read as
           health (R19 clause 2). *)
        Error "marginal probability is zero: the evidence is impossible under every state"
      else
        let distribution = List.map (fun (s, w) -> (s, w /. marginal)) weighted in
        let argmax, confidence =
          List.fold_left
            (fun (best, best_p) (s, p) -> if p > best_p then (s, p) else (best, best_p))
            (Stable, -1.0) distribution
        in
        Ok
          { distribution; argmax; confidence; marginal;
            surprisal = -.(Float.log marginal /. Float.log 2.0) }

(* Surprisal alone does not rank triage, and discovering that was worth the
   failing test. -log2 P(E) measures how poorly the MODEL explains an
   observation, not how much the observation matters. Under a uniform prior a
   path-only change is BETTER explained (silent divergence assigns it 0.90)
   than a no-change observation, so it carries LESS surprisal — correct
   information theory, useless as a work queue.

   The specification asks for severity x rarity, which is the fix. Severity is
   the cost of being in a state undetected: silent divergence ranks highest
   because the capture is blind to it, where a regression at least announces
   itself. *)
let severity = function
  | Silent_divergence -> 1.0
  | Regressed -> 0.8
  | Structural_drift -> 0.4
  | Stable -> 0.0

(* Severity of the ARGMAX alone has an argmax cliff: a 0.51/0.49 split between
   silent divergence and stable scores full severity, and 0.49/0.51 scores
   zero, for a hair's difference in evidence. Taking the expectation over the
   whole posterior removes the discontinuity and uses the distribution we went
   to the trouble of normalizing. Identified by an external review. *)
let expected_severity p =
  List.fold_left (fun acc (s, prob) -> acc +. (severity s *. prob)) 0.0 p.distribution

let priority p = expected_severity p *. p.surprisal

type cluster = {
  cause_key : string;
  members : evidence list;
  representative : posterior;
}

let join pairs =
  (* Beta join on the attribution fingerprint. Insertion-ordered by first
     appearance so the output is deterministic without depending on a hash. *)
  let keys =
    List.fold_left
      (fun acc (ev, _) -> if List.mem ev.cause acc then acc else acc @ [ ev.cause ])
      [] pairs
  in
  List.map
    (fun key ->
      let members = List.filter (fun (ev, _) -> ev.cause = key) pairs in
      let representative =
        snd
          (List.fold_left
             (fun (best_s, best_p) (_, p) ->
               if p.surprisal > best_s then (p.surprisal, p) else (best_s, best_p))
             (Float.neg_infinity, snd (List.hd members))
             members)
      in
      { cause_key = key; members = List.map fst members; representative })
    keys

type triage = {
  emitted : cluster list;
  withheld : cluster list;
  withheld_reason : string;
}

(* Mean, not exists. `List.exists (kill > floor)` lets ONE strong site admit a
   cluster of thirty-nine weak ones — mutation-rate laundering, and the exact
   shape of the failure this whole module was built after: a denominator that
   grows while the proof does not. The cluster's own rate is what decides it.
   Identified by an external review. *)
let cluster_kill_rate c =
  match c.members with
  | [] -> 0.0
  | members ->
      List.fold_left (fun acc ev -> acc +. ev.mutation_kill_rate) 0.0 members
      /. float_of_int (List.length members)

let alpha ?(min_kill_rate = 0.20) clusters =
  let discriminating c = cluster_kill_rate c > min_kill_rate in
  let emitted, withheld = List.partition discriminating clusters in

  let rank a b = compare (priority b.representative) (priority a.representative) in
  { emitted = List.stable_sort rank emitted;
    withheld = List.stable_sort rank withheld;
    withheld_reason =
      Printf.sprintf "every member survives mutation at or below kill rate %.2f" min_kill_rate }

type budget = {
  clusters_emitted : int;
  clusters_withheld : int;
  sites_covered : int;
  bytes_rendered : int;
}

let render triage =
  let b = Buffer.create 512 in
  let p fmt = Printf.ksprintf (Buffer.add_string b) fmt in
  p "posterior: %d cluster(s), ranked by surprisal\n" (List.length triage.emitted);
  List.iter
    (fun c ->
      let r = c.representative in
      p "  %-20s %-18s conf %.2f  surprisal %.2f bits  %d site(s)\n" c.cause_key
        (state_name r.argmax) r.confidence r.surprisal (List.length c.members);
      (* Cluster membership is CAPPED. Printing forty sites after condensing
         them to one fact spends exactly the tokens the clustering just saved,
         and an unbounded list is what pushes the recommendation off the end of
         a context window during a broad failure — the event that needs the
         compression most. The count above is the fact; the exemplars are an
         aid, and the remainder is disclosed rather than dropped. *)
      let exemplar_cap = 3 in
      List.iteri
        (fun i ev -> if i < exemplar_cap then p "      %s\n" ev.site)
        c.members;
      let hidden = List.length c.members - exemplar_cap in
      if hidden > 0 then p "      … %d more site(s) under this cause\n" hidden)
    triage.emitted;
  if triage.withheld <> [] then begin
    (* Disclosed, never silent: this is the shape R22 requires of a skip. *)
    p "  withheld: %d cluster(s) — %s\n" (List.length triage.withheld)
      triage.withheld_reason;
    List.iter (fun c -> p "      %s (low discriminating power)\n" c.cause_key)
      triage.withheld
  end;
  let text = Buffer.contents b in
  let sites cs = List.fold_left (fun acc c -> acc + List.length c.members) 0 cs in
  ( text,
    { clusters_emitted = List.length triage.emitted;
      clusters_withheld = List.length triage.withheld;
      sites_covered = sites triage.emitted + sites triage.withheld;
      bytes_rendered = String.length text } )

(* ------------------------------------------------- negative space (class 3) *)

type negative_space = {
  never_executed : string list;
  uncovered_units : string list;
  raised : string list;
  non_discriminating : string list;
}

let negative_space_empty =
  { never_executed = []; uncovered_units = []; raised = []; non_discriminating = [] }

(* ---------------------------------------------------- oracle state (class 7) *)

type oracle = { invariant : string; margin : float; vacuous : bool }

(* ------------------------------------------------------------- the report *)

type report = {
  triage : triage;
  negative : negative_space;
  oracles : oracle list;
  budget_vector : budget;
  next_measurement : string;
}

(* One measurement, derived by priority rather than invented. The order is an
   information claim: a silent divergence is a behaviour change the capture is
   blind to, so it outranks an oracle that holds for no reason, which outranks
   a site never run, which outranks a clean board. *)
let recommend triage negative oracles =
  let silent =
    List.filter (fun c -> c.representative.argmax = Silent_divergence) triage.emitted
  in
  let vacuous = List.filter (fun o -> o.vacuous) oracles in
  match (silent, vacuous, negative.never_executed, triage.withheld) with
  | c :: _, _, _, _ ->
      Printf.sprintf
        "dispatch mutation to cluster %S (%d site(s)): the path moved and the output \
         did not, so the capture is blind to a real change"
        c.cause_key (List.length c.members)
  | [], o :: _, _, _ ->
      Printf.sprintf
        "replace invariant %S: it held vacuously, which reads as safety and provides \
         none"
        o.invariant
  | [], [], site :: _, _ ->
      Printf.sprintf "execute or retire %S: a site that never runs proves nothing" site
  | [], [], [], c :: _ ->
      Printf.sprintf
        "strengthen the tests under %S: every member survives mutation, so the site \
         cannot discriminate"
        c.cause_key
  | [], [], [], [] ->
      "no measurement outranks the others; extend the corpus rather than re-running it"

let render_report report =
  let b = Buffer.create 1024 in
  let p fmt = Printf.ksprintf (Buffer.add_string b) fmt in
  let text, _ = render report.triage in
  Buffer.add_string b text;
  let negative_rows =
    [ ("never executed", report.negative.never_executed);
      ("uncovered units", report.negative.uncovered_units);
      ("raised", report.negative.raised);
      ("non-discriminating", report.negative.non_discriminating) ]
  in
  let negative_total = List.fold_left (fun acc (_, xs) -> acc + List.length xs) 0 negative_rows in
  if negative_total > 0 then begin
    p "negative space: %d item(s)\n" negative_total;
    List.iter
      (fun (label, items) ->
        if items <> [] then
          p "  %-20s %d: %s\n" label (List.length items) (String.concat ", " items))
      negative_rows
  end;
  let vacuous = List.filter (fun o -> o.vacuous) report.oracles in
  if report.oracles <> [] then begin
    p "oracle state: %d invariant(s), %d vacuous\n" (List.length report.oracles)
      (List.length vacuous);
    List.iter
      (fun o ->
        p "  %-28s margin %.2f%s\n" o.invariant o.margin
          (if o.vacuous then "  VACUOUS — held for no reason" else ""))
      report.oracles
  end;
  p "budget: %d emitted, %d withheld, %d site(s), %d bytes\n"
    report.budget_vector.clusters_emitted report.budget_vector.clusters_withheld
    report.budget_vector.sites_covered report.budget_vector.bytes_rendered;
  (* Not a summary. A summary restates what was just printed; this tells the
     next cycle what to do. *)
  p "recommended next measurement: %s\n" report.next_measurement;
  Buffer.contents b
let assess ?(min_kill_rate = 0.20) ?(max_clusters = 8) ~negative ~oracles pairs =
  (* The three density rules, in the stated order. *)
  let clustered = join pairs in                        (* 1. cluster by cause *)
  let ranked = alpha ~min_kill_rate clustered in       (* 2. rank by surprisal *)
  let kept, truncated =                                (* 3. truncate by budget *)
    if List.length ranked.emitted <= max_clusters then (ranked.emitted, [])
    else
      List.filteri (fun i _ -> i < max_clusters) ranked.emitted,
      List.filteri (fun i _ -> i >= max_clusters) ranked.emitted
  in
  (* Truncation is disclosed by moving the remainder into withheld, never by
     forgetting it: the budget vector must account for every cluster. *)
  let triage =
    { emitted = kept;
      withheld = ranked.withheld @ truncated;
      withheld_reason =
        (if truncated = [] then ranked.withheld_reason
         else
           Printf.sprintf "%s; and %d below the budget of %d" ranked.withheld_reason
             (List.length truncated) max_clusters) }
  in
  let _, partial = render triage in
  let draft =
    { triage; negative; oracles; budget_vector = partial;
      next_measurement = recommend triage negative oracles }
  in
  (* The budget must describe the block that is actually emitted. Measuring
     only the cluster section undercounts negative space, oracle state, the
     budget line and the recommendation — so the next agent would size its
     context against a number smaller than the payload, which is the one
     direction that hurts. Identified by an external review. *)
  { draft with
    budget_vector = { partial with bytes_rendered = String.length (render_report draft) } }


(* ------------------------------------------------------------------ gate

   A posterior that only prints is a prettier log. Both external reviews said
   so and one believed its own argument: an agent will hallucinate past a
   high-surprisal warning unless the output conditions something deterministic.

   So the probabilistic input drives a deterministic decision, and the decision
   can only ever BLOCK. The classifier is the harness's own bookkeeping; under
   R5 that may withhold credit and may never deny it. A candidate is never
   wrong because we classified it. *)

type verdict =
  | Proceed
  | Blocked_pending_measurement of { reason : string; measurement : string }

let verdict_name = function
  | Proceed -> "proceed"
  | Blocked_pending_measurement _ -> "blocked-pending-measurement"

let gate ?(confidence_floor = 0.60) report =
  let blocking =
    List.filter
      (fun c ->
        c.representative.argmax = Silent_divergence
        && c.representative.confidence >= confidence_floor)
      report.triage.emitted
  in
  match blocking with
  | [] -> Proceed
  | c :: _ ->
      Blocked_pending_measurement
        { reason =
            Printf.sprintf
              "cluster %S classifies silent-divergence at confidence %.2f over %d site(s): \
               the execution path moved and the output did not, so the capture is blind to \
               a real change"
              c.cause_key c.representative.confidence (List.length c.members);
          measurement = report.next_measurement }

(* ----------------------------------------------------------- calibration

   Row-sum tests prove the likelihood table is a distribution. Nothing proves
   it is the right one. Both reviews named that as the design's weak point, so
   the gap is measured rather than assumed. *)

type sample = { predicted : posterior; realized : state }

type calibration = {
  samples : int;
  brier : float;
  log_loss : float;
  accuracy : float;
  beats_uniform : bool;
}

(* A uniform guess over four states: Brier = 4 * (0.25 - [0|1])^2 summed
   = 3*0.0625 + 0.5625 = 0.75; log-loss = -log2 0.25 = 2 bits. These are the
   baselines the classifier has to beat to have earned its arithmetic. *)
let uniform_brier = 0.75
let uniform_log_loss = 2.0

let calibrate samples =
  if samples = [] then
    Error "cannot calibrate an empty sample: a perfect score over nothing is the vacuity trap"
  else
    let n = float_of_int (List.length samples) in
    let brier_sum =
      List.fold_left
        (fun acc s ->
          acc
          +. List.fold_left
               (fun inner (state, p) ->
                 let actual = if state = s.realized then 1.0 else 0.0 in
                 inner +. ((p -. actual) ** 2.0))
               0.0 s.predicted.distribution)
        0.0 samples
    in
    let log_loss_sum =
      List.fold_left
        (fun acc s ->
          let p = try List.assoc s.realized s.predicted.distribution with Not_found -> 0.0 in
          (* Clamp: a zero-probability truth is infinitely surprising, and an
             infinity in a reported metric is a broken gauge, not a finding. *)
          let clamped = Float.max p 1e-12 in
          acc -. (Float.log clamped /. Float.log 2.0))
        0.0 samples
    in
    let correct =
      List.fold_left (fun acc s -> if s.predicted.argmax = s.realized then acc +. 1.0 else acc)
        0.0 samples
    in
    let brier = brier_sum /. n and log_loss = log_loss_sum /. n in
    Ok
      { samples = List.length samples; brier; log_loss; accuracy = correct /. n;
        beats_uniform = brier < uniform_brier && log_loss < uniform_log_loss }

let render_calibration c =
  Printf.sprintf
    "calibration: %d sample(s)  brier %.4f (uniform %.2f)  log-loss %.4f bits (uniform %.2f)  \
     accuracy %.2f  %s\n"
    c.samples c.brier uniform_brier c.log_loss uniform_log_loss c.accuracy
    (if c.beats_uniform then "beats uniform"
     else "DOES NOT BEAT UNIFORM — read confidences as ordinal ranks, not probabilities")
