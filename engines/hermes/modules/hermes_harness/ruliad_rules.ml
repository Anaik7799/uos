(* The ruliad rule catalog: the canonical concepts, each with its source and --
   the part that keeps this from being prose -- its MAPPING onto this harness and
   its enforcement status. The seed pattern: typed data, completeness-tested
   (test_ruliad_rules), referenced by the docs rather than restated by them.

   Definition of record (MathWorld, fetched 2026-08-08): "the entangled limit of
   everything that is computationally possible, i.e., the result of following
   all possible computational rules in all possible ways" (Wolfram 2020, 2021). *)

type enforcement =
  | Enforced of string  (* the module/test that carries it: bare = hermes_harness/, or a repo-relative path *)
  | Advisory of string  (* why it cannot be a test, and how it is used instead *)

type rule = {
  id : string;
  concept : string;
  statement : string;        (* the canonical claim *)
  harness_mapping : string;  (* what it means IN THIS SYSTEM *)
  source : string;           (* reference key(s) from [references] *)
  enforcement : enforcement;
}

let rules =
  [ { id = "RUL-DEF";
      concept = "the ruliad";
      statement =
        "The entangled limit of everything that is computationally possible: the result of \
         following all possible computational rules in all possible ways; unique, with no \
         choices or outside inputs required.";
      harness_mapping =
        "The design space of the harness is treated as a slice of this limit: any concrete \
         run (a config, a build order, a normalizer setting) is one path through a space the \
         explorer can map; Ruliad.explore builds the full slice reachable from a state.";
      source = "mathworld-ruliad, wolfram-concept-2021";
      enforcement = Enforced "ruliad.ml" };
    { id = "RUL-PCE";
      concept = "principle of computational equivalence";
      statement =
        "Almost all rules lead to computations that are equivalent: there is only one \
         ultimate equivalence class for computations above a low threshold of complexity.";
      harness_mapping =
        "Grounds the differential method itself: the frozen Python reference and the OCaml \
         candidate are computationally equivalent SYSTEMS, so equivalence must be established \
         by running both and comparing traces, not by inspecting either alone (R10).";
      source = "mathworld-ruliad";
      enforcement = Advisory "an equivalence-class claim about computation in general; it motivates the differential method rather than being a testable property of one module" };
    { id = "RUL-IRREDUCIBILITY";
      concept = "computational irreducibility";
      statement =
        "A complex system's behaviour cannot in general be shortcut by a formula; you have to \
         run the process to see what happens.";
      harness_mapping =
        "R10 in ruliad language: only L4-L6 differential evidence grants parity -- the \
         comparison must be RUN; no catalog, contract or static analysis shortcuts it. The \
         explorer enumerates orders of work but never pretends to shortcut the per-edge work.";
      source = "user-brief, wolfram-concept-2021";
      enforcement = Enforced "test_parity_compare.ml" };
    { id = "RUL-CAUSAL-INVARIANCE";
      concept = "causal invariance";
      statement =
        "Stable, invariant outcomes hold regardless of the order in which events or \
         operations occur -- all branching paths reconverge to the same result.";
      harness_mapping =
        "Confluence of the harness's own algebras, proved twice over: the z3-discharged join \
         laws (formal_specs) say WHY, and Ruliad.explore verifies it exhaustively -- 720/720 \
         config-fold orderings and 30/30 frontier build orders reach one terminal.";
      source = "user-brief, wolfram-concept-2021";
      enforcement = Enforced "test_ruliad.ml" };
    { id = "RUL-MULTIWAY";
      concept = "multiway branching";
      statement =
        "Design choices are branching paths of a multiway system; different paths are \
         alternate operational scenarios or states, applied in all possible ways.";
      harness_mapping =
        "The parity frontier IS a multiway system: states are satisfied-intent sets, moves \
         are builds whose requires are met; ruliad_frontier enumerates every valid plan and \
         surfaces today's next-move options from the live evidence state.";
      source = "mathworld-ruliad, user-brief";
      enforcement = Enforced "ruliad_frontier.ml" };
    { id = "RUL-RULE-SPACE";
      concept = "rule-space exploration";
      statement =
        "Treat the system design as one path through a vast space of possible rules and \
         component interactions, not a fixed blueprint.";
      harness_mapping =
        "Beyond the frontier: the journal-specced normalizer rule-space (2^n volatile-set \
         configurations classified by which divergences each would hide -- the one component \
         that can manufacture false parity, HZ-NRM-01) is the next enumeration target.";
      source = "user-brief, wolfram-rulial-2020";
      enforcement = Advisory "the normalizer rule-space enumeration is specced in the formal-methods continuation journal (section 2) and lands with its own battery when built" };
    { id = "RUL-OBSERVER";
      concept = "observers and coordinatization";
      statement =
        "The ruliad can be coordinatized and sampled in different ways; what an observer \
         perceives depends on the frame from which they sample it.";
      harness_mapping =
        "The fractal ontology's aspects and the dashboard's KPI frames are coordinate frames \
         over one underlying evidence state: the same receipts sampled as verdicts, \
         posteriors, drift advice, or coverage -- different frames, one ruliad slice.";
      source = "mathworld-ruliad";
      enforcement = Enforced "fractal_ontology.ml" };
    { id = "RUL-EMERGENCE";
      concept = "emergence";
      statement =
        "System-level behaviours emerge from simple local rules; small design tweaks can \
         produce unexpected global results.";
      harness_mapping =
        "Why hazards are analysed at every fractal level (R6): a local rule change (a widened \
         volatile path, a lenient parser) emerges as a global false-parity failure; the \
         STPA/FMEA table exists to predict these emergent routes to H-1.";
      source = "user-brief (directive)";
      enforcement = Enforced "modules/hermes_wiki/src/fpp/fractal_diagnostic.ml" };
    { id = "RUL-FORECAST-LIMIT";
      concept = "limits of forecasting";
      statement =
        "Complex systems possess irreducible outcomes that cannot be fully predicted ahead \
         of time; plan for uncertainty rather than pretending to certainty.";
      harness_mapping =
        "The reliability layer refuses fabricated certainty: exact posteriors with honest \
         wide bands under small n, pseudo-replication and censoring laws pinned in tests -- \
         uncertainty is reported, never rounded away.";
      source = "user-brief (directive)";
      enforcement = Enforced "receipt_reliability.ml" };
    { id = "RUL-MEMOIZATION";
      concept = "regularity exploitation (the HashLife lesson)";
      statement =
        "Vast rule-application spaces collapse when regular substructure is memoized: \
         HashLife evaluates astronomically many cell updates by hashing repeated space-time \
         blocks.";
      harness_mapping =
        "Ruliad.explore memoizes states by canonical key: factorial path spaces collapse onto \
         the state lattice (362880 paths on 512 states, x708, measured) -- the same lesson, \
         applied to multiway exploration instead of quadtrees.";
      source = "hashlife-paper, golly";
      enforcement = Enforced "test_ruliad.ml" };
    { id = "RUL-DECISION-FRAME";
      concept = "decision-space mapping";
      statement =
        "Options are coordinate frames or slices within a universe of potential choices, \
         not a binary fork; map the space before choosing a path.";
      harness_mapping =
        "ruliad_frontier turns 'what next' into an enumerated space: all remaining plans, \
         their convergence guarantee (order is free), and the current option set -- the \
         choice is then made on measured grounds (reliability bands, effort), not guesses.";
      source = "user-brief, wolfram-concept-2021";
      enforcement = Enforced "ruliad_frontier.ml" };
    { id = "RUL-RULIOLOGY";
      concept = "ruliology";
      statement =
        "The empirical study of what simple rules do: run them, observe, classify -- the \
         methodology for exploring rule spaces case by case.";
      harness_mapping =
        "The harness's standing method is ruliology over the reference: probe the frozen \
         system with concrete scenarios, observe actual behaviour, classify honestly \
         (verified/divergent/blocked), and never assume what a rule does without running it.";
      source = "wolfram-ruliology-2026";
      enforcement = Enforced "reference_capture.ml" };
    { id = "RUL-EVOLUTION";
      concept = "system evolution in rulial space";
      statement =
        "A system's history is a trajectory through its rule space: successive states under \
         progressive rule application, trackable and comparable over time.";
      harness_mapping =
        "The ruliad_evolution table records each observed frontier state (satisfied set, \
         remaining plans, confluence, folded verdict) per harness revision, append-only: the \
         harness's own trajectory through its build space, queryable as history.";
      source = "mathworld-ruliad, wolfram-concept-2021";
      enforcement = Enforced "evidence_store.ml" };
  ]

(* The bibliography of record: everything the directive supplied plus the
   MathWorld page's own reference list (fetched 2026-08-08). *)
let references =
  [ ("mathworld-ruliad", "Weisstein/MathWorld, 'Ruliad', https://mathworld.wolfram.com/Ruliad.html");
    ("wolfram-rulial-2020", "Wolfram, S. 'Exploring Rulial Space: The Case of Turing Machines', Jun 9 2020");
    ("wolfram-concept-2021", "Wolfram, S. 'The Concept of the Ruliad', Nov 10 2021");
    ("wolfram-expression-2023", "Wolfram, S. 'Expression Evaluation and Fundamental Physics: The Rulial Case', Sep 29 2023");
    ("wolfram-ruliology-2026", "Wolfram, S. 'What Is Ruliology?', Jan 12 2026");
    ("wolfram-pnp-2026", "Wolfram, S. 'P vs. NP and the Difficulty of Computation: A Ruliological Approach', Jan 30 2026");
    ("wolfram-games-2026", "Wolfram, S. 'Games between Programs: The Ruliology of Competition', Jun 4 2026");
    ("hashlife-paper", "'An Algorithm for Compressing Space and Time' (HashLife), ar5iv 1208.2456");
    ("hashlife-impl", "ngmsoftware/hashlife, https://github.com/ngmsoftware/hashlife");
    ("golly", "Golly cellular-automata simulator, https://golly.sourceforge.io/");
    ("user-brief", "the directive's systems-engineering brief (rule-space exploration, irreducibility, multiway branching, causal invariance, emergence, forecasting limits)") ]
