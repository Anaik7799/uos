(* The stage that runs BEFORE an agent — human or model — is shown anything.

   An oracle should receive condensed, validated facts, never raw evidence.
   That is the same information-density argument the emitter makes about
   context windows, applied to the oracle call itself: forty sites sharing a
   cause are one fact, and a state no evidence can reach is a lie in the
   ontology. Sending raw rows spends the oracle's attention on work a machine
   already did.

   Two existing engines do the work. R14 is explicit that a concern zigvm or
   this repository already solved must be reused or mirrored, never
   reinvented, and the emitter's hand-rolled join was exactly the second
   thing — a second rule engine standing beside Hermes_rete. It is retired
   here.

   - Hermes_rete  — a forward-chaining rule engine over a working memory,
                    with the action node asserting derived facts. Its own
                    header is explicit that it is a NAIVE MATCHER, not the
                    Rete algorithm: no alpha/beta network, no token memories,
                    no unlinking. The filter and join rules below play the
                    alpha and beta ROLES; calling the engine "Rete" would
                    adopt a claim its author deliberately refused, and a
                    stale identity is muda the structure algebra names.
   - Ruliad       — multiway exploration of the ontology's own state space,
                    to prove every declared state is reachable and that the
                    classifier is confluent over the evidence space.

   Order matters and is the point of this module: RETE, then RULIAD, then the
   agent. Never the agent first. *)

module V = Hermes_rete.Value

(* ------------------------------------------------------------ 1. RETE *)

let site_kind = "site"
let cluster_kind = "cluster"
let withheld_kind = "withheld"

(* Evidence enters the working memory as facts. The posterior's classification
   travels with it so the rules can reason over the state, not just the raw
   booleans. *)
let assert_evidence wm pairs =
  List.iter
    (fun ((ev : Expect_posterior.evidence), (p : Expect_posterior.posterior)) ->
      Hermes_rete.WM.insert wm site_kind
        [ ("site", V.String ev.site);
          ("cause", V.String ev.cause);
          ("state", V.String (Expect_posterior.state_name p.argmax));
          ("path_changed", V.Bool ev.path_changed);
          ("output_changed", V.Bool ev.output_changed);
          (* Rates are carried as basis points so the engine's integer
             comparison is exact; a float Eq in a rule engine is a defect
             waiting for a rounding change. *)
          ("kill_bp", V.Int (int_of_float (ev.mutation_kill_rate *. 10_000.)));
          ("priority_bp", V.Int (int_of_float (Expect_posterior.priority p *. 10_000.))) ])
    pairs

let attr fact name =
  match List.assoc_opt name fact.Hermes_rete.attrs with Some v -> Some v | None -> None

let string_attr fact name =
  match attr fact name with Some (V.String s) -> s | _ -> ""

let int_attr fact name = match attr fact name with Some (V.Int i) -> i | _ -> 0

(* The JOIN rule (beta ROLE — the engine has no beta network). Two sites
   sharing a cause are one fact. Expressed as a real join —
   pattern one binds a site, pattern two binds another whose cause equals the
   first's — so the engine performs the correlation, not a fold in this file. *)
let cluster_rule =
  { Hermes_rete.name = "beta-join-by-cause";
    patterns =
      (* VarBind takes the VARIABLE first and the FIELD second: bind `c` to the
         value of this fact's `cause`, so the second pattern can join on it. *)
      [ { pat_kind = site_kind;
          conds = [ Hermes_rete.VarBind ("c", "cause") ];
          bind_name = Some "left" };
        { pat_kind = site_kind;
          conds = [ Hermes_rete.VarCmp ("cause", Hermes_rete.Eq, "c") ];
          bind_name = Some "right" } ];
    action =
      (fun wm named ->
        match (List.assoc_opt "left" named, List.assoc_opt "right" named) with
        | Some left, Some right ->
            let cause = string_attr left "cause" in
            let already =
              List.exists
                (fun f -> String.equal (string_attr f "cause") cause)
                (Hermes_rete.WM.get_by_kind wm cluster_kind)
            in
            if not already then
              Hermes_rete.WM.insert wm cluster_kind
                [ ("cause", V.String cause);
                  ("state", V.String (string_attr left "state"));
                  ("priority_bp", V.Int (int_attr left "priority_bp")) ];
            ignore right;
            Ok ()
        | _ -> Ok ()) }

(* The FILTER rule (alpha ROLE). A site that survives mutation discriminates nothing, so its cluster
   is withheld from the dense payload. Withheld, never dropped — Ops_mutate
   holds that a survivor is a finding, and deleting it would launder a weak
   test into an equivalent mutant. *)
let withhold_rule ~min_kill_bp =
  { Hermes_rete.name = "alpha-withhold-non-discriminating";
    patterns =
      [ { pat_kind = site_kind; conds = []; bind_name = Some "s" } ];
    action =
      (fun wm named ->
        match List.assoc_opt "s" named with
        | Some s when int_attr s "kill_bp" <= min_kill_bp ->
            let cause = string_attr s "cause" in
            let already =
              List.exists
                (fun f -> String.equal (string_attr f "cause") cause)
                (Hermes_rete.WM.get_by_kind wm withheld_kind)
            in
            if not already then
              Hermes_rete.WM.insert wm withheld_kind
                [ ("cause", V.String cause); ("site", V.String (string_attr s "site")) ];
            Ok ()
        | _ -> Ok ()) }

let rules ~min_kill_bp = [ cluster_rule; withhold_rule ~min_kill_bp ]

(* ---------------------------------------------------------- 2. RULIAD *)

(* The ontology's own state space, explored rather than asserted. A declared
   state that no observation can produce is dead ontology, and the whole
   fractal-ontology claim rests on every state being reachable.

   The system: a state is a classification, a move is an observation from the
   four-point evidence space, and applying a move is the classifier itself. *)
let observe (path, output) =
  { Expect_posterior.site = "probe"; cause = "probe"; path_changed = path;
    output_changed = output; churn = 0.5; mutation_kill_rate = 1.0 }

let classify move =
  match Expect_posterior.update ~prior:Expect_posterior.uniform_prior (observe move) with
  | Ok p -> Some p.Expect_posterior.argmax
  | Error _ -> None

(* The state is the ACCUMULATED set of classifications reached, not the current
   one. That is deliberate and it is what makes the exploration legal: a set
   only grows, so the system is monotone and the graph is acyclic, where
   "current classification" would cycle immediately and Ruliad refuses a cyclic
   system rather than diverging on it.

   It also asks a better question. The terminal of a monotone system is the
   CLOSURE — every state the evidence space can produce — and confluence
   (exactly one terminal) proves that closure is independent of the order
   observations arrive in. An ontology whose reachable set depended on
   observation order would not be a classification at all. *)
let ontology_system () =
  let evidence_space = [ (false, false); (true, false); (false, true); (true, true) ] in
  { Ruliad.initial = ([] : string list);
    (* A move is APPLICABLE only when it would grow the set. Without this the
       system self-loops the moment an observation repeats a classification
       already reached, and a self-edge is a cycle: Ruliad refuses a cyclic
       system rather than diverging on its path DP. Filtering here makes every
       applicable move strictly monotone, which is what the exploration needs
       and what "closure" means. *)
    moves =
      (fun reached ->
        List.filter
          (fun move ->
            match classify move with
            | None -> false
            | Some state -> not (List.mem (Expect_posterior.state_name state) reached))
          evidence_space);
    apply =
      (fun reached move ->
        match classify move with
        | None -> reached
        | Some state -> List.sort_uniq compare (Expect_posterior.state_name state :: reached));
    canonical = (fun reached -> String.concat "|" (List.sort compare reached)) }

type ontology_check = {
  reachable : Expect_posterior.state list;
  unreachable : Expect_posterior.state list;
  confluent : bool;
  states_explored : int;
}

let check_ontology () =
  match Ruliad.explore (ontology_system ()) with
  | Error message -> Error message
  | Ok graph ->
      (* The closure is the terminal of a monotone system. *)
      let closure = match graph.Ruliad.terminals with [ t ] -> t | _ -> [] in
      let reachable =
        List.filter (fun s -> List.mem (Expect_posterior.state_name s) closure)
          Expect_posterior.states
      in
      let unreachable =
        List.filter (fun s -> not (List.mem (Expect_posterior.state_name s) closure))
          Expect_posterior.states
      in
      Ok
        { reachable; unreachable; confluent = graph.Ruliad.confluent;
          states_explored = graph.Ruliad.state_count }

(* ------------------------------------------- 4. PROVENANCE: AS-IS state

   An agent must never be handed evidence that has not already been through
   the suites and the formal checks. Enforcing that by convention would mean
   trusting every future caller to run things in order, so it is enforced by
   the type: agent_payload consumes a [prepared], [prepare] demands a
   [provenance], and a provenance that does not describe a completed run is
   REFUSED rather than rendered.

   This is the AS-IS half of the payload — what is true right now, measured,
   with the denominator visible so a reader can tell coverage from luck. *)

type provenance = {
  profile : string;              (* fast | full — the denominator matters *)
  suites_run : int;
  suites_passed : int;
  suites_failed : int;
  suites_skipped : int;
  formal_checks : (string * bool) list;  (* name, passed *)
}

let provenance_complete p =
  (* A skip is disclosed and never counted green (R22), so a run carrying
     skips is not a complete denominator no matter how many suites passed. *)
  p.suites_run > 0 && p.suites_skipped = 0 && p.formal_checks <> []

let check_provenance p =
  if p.suites_run = 0 then
    Error "no test evidence: the suites have not run, so there is nothing for an agent to assess"
  else if p.suites_passed + p.suites_failed + p.suites_skipped <> p.suites_run then
    Error
      (Printf.sprintf
         "provenance does not balance: %d passed + %d failed + %d skipped <> %d run"
         p.suites_passed p.suites_failed p.suites_skipped p.suites_run)
  else if p.formal_checks = [] then
    Error "no formal evidence: the formal checks have not run, so the assessment is untethered"
  else Ok ()

let render_provenance p =
  let failed_formal = List.filter (fun (_, ok) -> not ok) p.formal_checks in
  Printf.sprintf
    "AS-IS: profile=%s suites %d/%d passed, %d failed, %d skipped; formal %d/%d passed%s%s\n"
    p.profile p.suites_passed p.suites_run p.suites_failed p.suites_skipped
    (List.length p.formal_checks - List.length failed_formal)
    (List.length p.formal_checks)
    (if failed_formal = [] then ""
     else "; formal failures: " ^ String.concat ", " (List.map fst failed_formal))
    (if provenance_complete p then "" else "  [INCOMPLETE DENOMINATOR]")

(* ------------------------------ 5. BLAST RADIUS: the predictive half

   What a suite can PREDICT is bounded by what it can see, and what it can see
   is its reverse dependency cone: the modules that would be affected if the
   thing it exercises is wrong. A suite over a leaf that eight components
   depend on predicts for eight components; a suite over an aggregate nothing
   imports predicts for itself alone.

   That cone is the fractal atlas read backwards, and it is the honest bound
   on a suite's foresight. Anything wider is speculation; anything narrower
   throws away the reach the dependency graph already proves. *)

type blast_radius = {
  origin : string;
  dependents : string list;   (* transitive reverse cone, excluding origin *)
  depth : int;                (* longest chain to a dependent *)
}

(* [edges] is (dependent, dependency): "a depends on b". The cone is computed
   to a fixpoint, and a cycle cannot hang it because membership only grows. *)
let blast_radius ~edges origin =
  let rec grow frontier reached depth best_depth =
    match frontier with
    | [] -> (reached, best_depth)
    | _ ->
        let next =
          List.filter_map
            (fun (dependent, dependency) ->
              if List.mem dependency frontier && not (List.mem dependent reached) then
                Some dependent
              else None)
            edges
        in
        let next = List.sort_uniq compare next in
        if next = [] then (reached, best_depth)
        else grow next (List.sort_uniq compare (next @ reached)) (depth + 1) (depth + 1)
  in
  let dependents, depth = grow [ origin ] [] 1 0 in
  { origin; dependents = List.filter (fun d -> d <> origin) dependents; depth }

let render_blast_radius r =
  Printf.sprintf "PREDICTIVE: %s reaches %d dependent(s) at depth %d%s\n" r.origin
    (List.length r.dependents) r.depth
    (if r.dependents = [] then " — a failure here is contained"
     else ": " ^ String.concat ", " r.dependents)
(* ------------------------------------------------- 3. THE AGENT PAYLOAD *)

type prepared = {
  provenance : provenance;
  blast : blast_radius list;
  clusters : string list;      (* cause keys the rete derived *)
  withheld : string list;      (* cause keys the alpha withheld *)
  sites_in : int;              (* what went in, so the condensation ratio is visible *)
  ontology : ontology_check;
  report : Expect_posterior.report;
  gate : Expect_posterior.verdict;
}

let prepare ?(min_kill_rate = 0.20) ~provenance ~blast ~negative ~oracles pairs =
  (* ORDER, enforced. Testing and the formal checks must already have run and
     balanced before anything reaches an engine, let alone an agent. A caller
     cannot skip this by forgetting: prepare demands the provenance, and
     agent_payload cannot be reached except through a prepared. *)
  match check_provenance provenance with
  | Error message -> Error ("provenance refused: " ^ message)
  | Ok () -> (
  match check_ontology () with
  | Error message -> Error ("ruliad exploration failed: " ^ message)
  | Ok ontology ->
      if ontology.unreachable <> [] then
        (* Fail closed. A classifier with an unreachable state is asserting a
           distinction it can never draw, and no agent should be asked to
           reason over one. *)
        Error
          ("ontology has unreachable state(s): "
          ^ String.concat ", " (List.map Expect_posterior.state_name ontology.unreachable))
      else
        let wm = Hermes_rete.WM.create () in
        assert_evidence wm pairs;
        let min_kill_bp = int_of_float (min_kill_rate *. 10_000.) in
        match Hermes_rete.fire_rules wm (rules ~min_kill_bp) with
        | Error message -> Error ("rete assessment failed: " ^ message)
        | Ok () ->
            let causes kind =
              List.sort_uniq compare
                (List.map (fun f -> string_attr f "cause") (Hermes_rete.WM.get_by_kind wm kind))
            in
            let report = Expect_posterior.assess ~min_kill_rate ~negative ~oracles pairs in
            Ok
              { clusters = causes cluster_kind; withheld = causes withheld_kind;
                sites_in = List.length pairs; ontology; provenance; blast;
                report; gate = Expect_posterior.gate report })

(* What an oracle actually receives. Derived facts and validation only — never
   the raw rows, which is the whole point of running the engines first. *)
let agent_payload prepared =
  let b = Buffer.create 512 in
  let p fmt = Printf.ksprintf (Buffer.add_string b) fmt in
  Buffer.add_string b (render_provenance prepared.provenance);
  List.iter (fun r -> Buffer.add_string b (render_blast_radius r)) prepared.blast;
  p "ontology: %d state(s) explored, all reachable, confluent=%b\n"
    prepared.ontology.states_explored prepared.ontology.confluent;
  p "rete: %d site(s) condensed to %d cluster(s), %d withheld\n" prepared.sites_in
    (List.length prepared.clusters) (List.length prepared.withheld);
  if prepared.sites_in > 0 then
    p "condensation: %d:1\n" (prepared.sites_in / max 1 (List.length prepared.clusters));
  p "gate: %s\n" (Expect_posterior.verdict_name prepared.gate);
  Buffer.add_string b (Expect_posterior.render_report prepared.report);
  Buffer.contents b


(* ------------------------- 6. ASSESSMENT: how a claim is to be believed

   Orientation ranks and condenses. It does not say how much to TRUST what
   it condensed, and pooling a proved theorem with a model's opinion is how a
   confident guess acquires the standing of evidence.

   Four instruments, each answering a different question, and each declared
   rather than left to a reader's judgement.

   ADMIRALTY. The NATO two-axis grading: source reliability A-F, information
   credibility 1-6. A mechanically checked proof and an LLM's prediction are
   both "opinions" to a pooling average; graded, one is A1 and the other is
   C3, and the difference survives into the payload. This matters directly
   here — two oracles reviewed this module, and their sharpest claims were
   verified in source before being believed (R2: oracles, never authors).
   Grading records which claims earned that and which did not. *)

type reliability = A_reliable | B_usually | C_fairly | D_not_usually | E_unreliable | F_unjudged
type credibility = C1_confirmed | C2_probable | C3_possible | C4_doubtful | C5_improbable | C6_unjudged

let reliability_code = function
  | A_reliable -> "A" | B_usually -> "B" | C_fairly -> "C"
  | D_not_usually -> "D" | E_unreliable -> "E" | F_unjudged -> "F"

let credibility_code = function
  | C1_confirmed -> "1" | C2_probable -> "2" | C3_possible -> "3"
  | C4_doubtful -> "4" | C5_improbable -> "5" | C6_unjudged -> "6"

let admiralty_code r c = reliability_code r ^ credibility_code c

(* Admissible as evidence only when the source is reliable AND the claim was
   independently confirmed. Everything else informs and does not decide —
   which is R2's discipline expressed as a grade rather than a habit. *)
let admissible r c =
  (match r with A_reliable | B_usually -> true | _ -> false)
  && match c with C1_confirmed | C2_probable -> true | _ -> false

type claim = {
  proposition : string;
  source : string;
  reliability : reliability;
  credibility : credibility;
  verified_in_source : bool;   (* did someone check it, or merely read it? *)
}

(* DEVIL'S ADVOCATE. A claim with no stated way to be wrong is not a finding,
   it is a preference. Each carries the observation that would refute it. *)
type devils_advocate = { against : string; refuted_if : string }

(* ACH — analysis of competing hypotheses. The discipline is that evidence
   DISCONFIRMS: a hypothesis surviving because nothing contradicted it is
   ranked by the diagnosticity of the evidence against it, never by how much
   supports it. Consistency is cheap; inconsistency is informative. *)
type ach_row = { hypothesis : string; inconsistent_with : string list }

let ach_rank rows =
  (* Fewest inconsistencies first — the surviving hypothesis, not the popular
     one. Ties keep declaration order so the output stays deterministic. *)
  List.stable_sort
    (fun a b -> compare (List.length a.inconsistent_with) (List.length b.inconsistent_with))
    rows

(* RED TEAM. Not a critique of the finding — an attack on the MEASUREMENT.
   How would this assessment be made to say what someone wanted? *)
type red_team = { attack : string; countermeasure : string option }

type assessment = {
  claims : claim list;
  devils : devils_advocate list;
  ach : ach_row list;
  red : red_team list;
}

let render_assessment a =
  let b = Buffer.create 512 in
  let p fmt = Printf.ksprintf (Buffer.add_string b) fmt in
  if a.claims <> [] then begin
    p "ADMIRALTY: %d claim(s), %d admissible\n" (List.length a.claims)
      (List.length
         (List.filter (fun c -> admissible c.reliability c.credibility) a.claims));
    List.iter
      (fun c ->
        p "  [%s] %-28s %s%s\n" (admiralty_code c.reliability c.credibility) c.source
          c.proposition
          (if c.verified_in_source then "" else "  (read, not verified)"))
      a.claims
  end;
  if a.devils <> [] then begin
    p "DEVIL'S ADVOCATE: %d\n" (List.length a.devils);
    List.iter (fun d -> p "  %s — refuted if: %s\n" d.against d.refuted_if) a.devils
  end;
  if a.ach <> [] then begin
    p "ACH: %d hypothesis(es), ranked by fewest inconsistencies\n" (List.length a.ach);
    List.iter
      (fun r ->
        p "  %-40s inconsistent with %d: %s\n" r.hypothesis
          (List.length r.inconsistent_with)
          (String.concat "; " r.inconsistent_with))
      (ach_rank a.ach)
  end;
  if a.red <> [] then begin
    p "RED TEAM: %d attack(s) on the measurement\n" (List.length a.red);
    List.iter
      (fun r ->
        p "  %s → %s\n" r.attack
          (match r.countermeasure with Some c -> c | None -> "NO COUNTERMEASURE"))
      a.red
  end;
  Buffer.contents b
