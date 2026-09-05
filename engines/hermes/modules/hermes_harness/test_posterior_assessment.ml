(* The engines must run BEFORE an agent sees anything, and this suite pins
   that they actually run rather than being named in a comment.

   Every property carries a negative control (HZ-FIX-03): a check no wrong
   input fails is not a check. *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let contains text needle =
  let n = String.length needle in
  let rec at i =
    i + n <= String.length text && (String.sub text i n = needle || at (i + 1))
  in
  at 0

open Expect_posterior

let ev ?(site = "s") ?(cause = "c") ?(kill = 0.9) path output =
  { site; cause; path_changed = path; output_changed = output; churn = 0.5;
    mutation_kill_rate = kill }

let good_provenance =
  { Posterior_assessment.profile = "full"; suites_run = 192; suites_passed = 188;
    suites_failed = 4; suites_skipped = 0;
    formal_checks = [ ("gospel", true); ("z3-windows", true) ] }

let prepare pairs =
  Posterior_assessment.prepare ~provenance:good_provenance ~blast:[]
    ~negative:negative_space_empty ~oracles:[] pairs

let mk site cause kill path output =
  let e = ev ~site ~cause ~kill path output in
  match update ~prior:uniform_prior e with Ok p -> (e, p) | Error m -> failwith m

(* --------------------------------------------------------- RULIAD layer *)

let ruliad_layer () =
  match Posterior_assessment.check_ontology () with
  | Error m -> check false ("RULIAD exploration succeeds :: " ^ m)
  | Ok o ->
      (* The whole fractal-ontology claim rests on this: a declared state no
         observation can produce is dead ontology. *)
      check (o.Posterior_assessment.unreachable = [])
        "RULIAD every declared state is reachable from the evidence space";
      check (List.length o.Posterior_assessment.reachable = List.length states)
        "RULIAD the closure covers all four states";
      (* Confluence: exactly one terminal, so the reachable set does not depend
         on the order observations arrive in. A classification whose support
         depended on arrival order would not be a classification. *)
      check o.Posterior_assessment.confluent
        "RULIAD the closure is confluent (order-independent)";
      check (o.Posterior_assessment.states_explored > 1)
        "RULIAD exploration visited more than the initial state (non-vacuous)"

(* ----------------------------------------------------------- RETE layer *)

let rete_layer () =
  (* Forty sites, one cause: the engine must condense them. *)
  let many = List.init 40 (fun i -> mk (Printf.sprintf "s%02d" i) "one-cause" 0.9 false true) in
  (match prepare many with
  | Error m -> check false ("RETE prepare succeeds :: " ^ m)
  | Ok p ->
      check (p.Posterior_assessment.sites_in = 40) "RETE every site entered working memory";
      check (List.length p.Posterior_assessment.clusters = 1)
        "RETE forty sites condense to one derived cluster fact";
      (* The payload an oracle receives must NOT contain the raw rows — that is
         the entire reason the engines run first. *)
      let payload = Posterior_assessment.agent_payload p in
      check (contains payload "40 site(s) condensed to 1 cluster")
        "RETE the payload states the condensation";
      check (not (contains payload "s07")) "RETE the payload omits individual raw sites";
      check (contains payload "ontology:") "RETE the payload carries the ruliad validation");

  (* Distinct causes must NOT be merged — the negative control for the join. *)
  (match
     prepare
       [ mk "a" "cause-a" 0.9 true false; mk "b" "cause-b" 0.9 false true ]
   with
  | Error m -> check false ("RETE distinct causes :: " ^ m)
  | Ok p ->
      check (List.length p.Posterior_assessment.clusters = 2)
        "RETE distinct causes stay distinct");

  (* ALPHA: a non-discriminating site is withheld by the engine, not by a fold
     in the caller. *)
  (match
     prepare
       [ mk "weak" "weak-cause" 0.01 false true ]
   with
  | Error m -> check false ("RETE alpha :: " ^ m)
  | Ok p ->
      check (p.Posterior_assessment.withheld = [ "weak-cause" ])
        "RETE the alpha network withholds a non-discriminating cause");
  (* Positive control: a discriminating site is NOT withheld, or the alpha rule
     is simply withholding everything. *)
  (match
     prepare
       [ mk "strong" "strong-cause" 0.99 false true ]
   with
  | Error m -> check false ("RETE alpha control :: " ^ m)
  | Ok p ->
      check (p.Posterior_assessment.withheld = [])
        "RETE a discriminating cause is not withheld")

(* ------------------------------------------------------- ORDERING layer *)

let ordering_layer () =
  (* The gate travels WITH the payload, so the agent receives the decision and
     not merely the evidence for it. *)
  (match prepare [ mk "s" "silent-cause" 0.9 true false ] with
  | Error m -> check false ("ORDERING prepare :: " ^ m)
  | Ok p ->
      check (p.Posterior_assessment.gate <> Proceed)
        "ORDERING a silent divergence reaches the agent already gated";
      let payload = Posterior_assessment.agent_payload p in
      check (contains payload "gate: blocked-pending-measurement")
        "ORDERING the payload leads with the verdict, not the raw evidence";
      check (contains payload "recommended next measurement:")
        "ORDERING the payload ends with a measurement";
      check (contains payload "AS-IS:") "ORDERING the payload carries the AS-IS state";
      check (Posterior_assessment.agent_payload p = payload)
        "ORDERING the payload is deterministic");

  (* PROVENANCE REFUSALS. Testing and formal checks must ALREADY have run.
     Each of these must be refused before any engine turns, or "run the tests
     first" is a convention rather than a property. *)
  let refused label provenance =
    match
      Posterior_assessment.prepare ~provenance ~blast:[] ~negative:negative_space_empty
        ~oracles:[] [ mk "s" "c" 0.9 true false ]
    with
    | Ok _ -> check false ("ORDERING " ^ label ^ " must be refused")
    | Error m -> check (contains m "provenance refused") ("ORDERING " ^ label ^ " is refused")
  in
  refused "an unrun suite set"
    { good_provenance with Posterior_assessment.suites_run = 0; suites_passed = 0;
      suites_failed = 0 };
  refused "a provenance that does not balance"
    { good_provenance with Posterior_assessment.suites_passed = 1 };
  refused "absent formal evidence"
    { good_provenance with Posterior_assessment.formal_checks = [] };
  (* Positive control: the refusals must not be firing on a good provenance. *)
  (match prepare [ mk "s" "c" 0.9 true false ] with
  | Ok _ -> incr passed
  | Error m -> check false ("ORDERING a complete provenance is accepted :: " ^ m));

  (* BLAST RADIUS — the predictive half, bounded by what the suite can see. *)
  let edges =
    [ ("hermes_ops", "hermes_wiki_fpp"); ("hermes_harness", "hermes_wiki_fpp");
      ("hermes_ops_dashboard", "hermes_ops"); ("unrelated", "something_else") ]
  in
  let r = Posterior_assessment.blast_radius ~edges "hermes_wiki_fpp" in
  check (List.length r.Posterior_assessment.dependents = 3)
    "BLAST the transitive reverse cone is reached, not just direct dependents";
  check (List.mem "hermes_ops_dashboard" r.Posterior_assessment.dependents)
    "BLAST a second-order dependent is included";
  check (not (List.mem "unrelated" r.Posterior_assessment.dependents))
    "BLAST an unrelated module is excluded";
  check (r.Posterior_assessment.depth >= 2) "BLAST depth reflects the longest chain";
  (* Negative control: a leaf nothing depends on predicts for itself alone. *)
  let contained = Posterior_assessment.blast_radius ~edges "something_else" in
  check (List.length contained.Posterior_assessment.dependents = 1)
    "BLAST a barely-depended module has a small radius";
  let isolated = Posterior_assessment.blast_radius ~edges "nobody_depends_on_me" in
  check (isolated.Posterior_assessment.dependents = [])
    "BLAST an isolated module's failure is contained";
  check (contains (Posterior_assessment.render_blast_radius isolated) "contained")
    "BLAST containment is stated, not left to inference"

let assessment_layer () =
  let open Posterior_assessment in
  (* ADMIRALTY: a proof and an opinion must not pool. *)
  check (admissible A_reliable C1_confirmed) "ADMIRALTY a confirmed reliable claim is admissible";
  check (not (admissible C_fairly C3_possible)) "ADMIRALTY a possible fair-source claim is NOT admissible";
  check (not (admissible A_reliable C4_doubtful)) "ADMIRALTY reliability alone does not admit";
  check (not (admissible E_unreliable C1_confirmed)) "ADMIRALTY confirmation alone does not admit";
  check (admiralty_code A_reliable C1_confirmed = "A1") "ADMIRALTY the code renders as two axes";
  (* ACH ranks by fewest inconsistencies, not most support. *)
  let rows =
    [ { hypothesis = "popular but contradicted"; inconsistent_with = [ "e1"; "e2" ] };
      { hypothesis = "survives"; inconsistent_with = [] } ]
  in
  (match ach_rank rows with
  | first :: _ -> check (first.hypothesis = "survives") "ACH the surviving hypothesis ranks first"
  | [] -> check false "ACH ranking produced nothing");
  (* A red-team attack with no countermeasure must SAY so. *)
  let a =
    { claims =
        [ { proposition = "join derives clusters"; source = "test_posterior_assessment";
            reliability = A_reliable; credibility = C1_confirmed; verified_in_source = true };
          { proposition = "constants will drift"; source = "codex";
            reliability = C_fairly; credibility = C3_possible; verified_in_source = false } ];
      devils = [ { against = "the gate changes behaviour"; refuted_if = "a run proceeds past a blocked verdict" } ];
      ach = rows;
      red = [ { attack = "inflate kill rate with brittle assertions"; countermeasure = None } ] }
  in
  let text = render_assessment a in
  check (contains text "[A1]") "ASSESSMENT a verified internal claim grades A1";
  check (contains text "[C3]") "ASSESSMENT an unverified oracle claim grades C3";
  check (contains text "(read, not verified)") "ASSESSMENT unverified claims are marked";
  check (contains text "1 admissible") "ASSESSMENT only the confirmed claim is admissible";
  check (contains text "refuted if:") "ASSESSMENT every claim carries its refutation";
  check (contains text "NO COUNTERMEASURE") "ASSESSMENT an unanswered attack is stated, not omitted";
  check (render_assessment a = text) "ASSESSMENT rendering is deterministic"

let () =
  Printf.printf "=== posterior assessment (rete -> ruliad -> agent) ===\n";
  List.iter
    (fun (name, layer) -> layer (); Printf.printf "  %-10s done\n" name)
    [ ("ruliad", ruliad_layer); ("rete", rete_layer); ("ordering", ordering_layer);
      ("assessment", assessment_layer) ];
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_posterior_assessment" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_posterior_assessment ]);
  exit (Suite_telemetry.exit_code self)
