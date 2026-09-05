let checks = ref 0
let failures = ref 0

let rete_required =
  Array.length Sys.argv = 2 && String.equal Sys.argv.(1) "--rete"

let raven_required =
  Array.length Sys.argv = 2 && String.equal Sys.argv.(1) "--raven"

let receipts_required =
  Array.length Sys.argv = 2 && String.equal Sys.argv.(1) "--receipts"

let rete_law_names =
  [ "the Rete compile context exists";
    "a valid join network compiles";
    "compiled network digest is deterministic SHA-256";
    "empty sessions from distinct compiled networks have distinct digests";
    "a forward or unknown join is rejected";
    "duplicate rule ids are rejected";
    "duplicate fact attributes are rejected before session mutation";
    "assert records a canonical changed delta";
    "a source fact populates alpha and beta prefixes without activating a join";
    "delta receipts are bound to the compiled network";
    "alpha memories and beta joins create one deterministic activation";
    "a mismatched join cannot create a final token or activation";
    "byte-identical duplicate assertion is idempotent";
    "same-id different-content assertion is atomic and rejected";
    "update of a missing target returns the unchanged session";
    "fixed point empties the agenda and binds complete digests";
    "identical support cannot refire in the same truth interval";
    "content update invalidates refraction and permits one new firing";
    "restoring prior content after invalidation opens a new truth interval";
    "retract unlinks alpha beta agenda and dependent refraction state";
    "reassert after retract opens a new truth interval";
    "replay and manual delta application have identical final state";
    "replay omission changes the admitted final state";
    "replay rejects an update before its target assertion";
    "fact budget exhaustion is atomic and bounded";
    "alpha budget exhaustion is atomic and bounded";
    "beta budget exhaustion is atomic and bounded";
    "agenda budget exhaustion is atomic and bounded";
    "an invalid RHS update preserves the pre-activation session";
    "oscillation exhausts the firing budget rather than converging";
    "trace entry exhaustion is bounded and records truncation";
    "trace digest binds the truncation flag";
    "the supported static subset agrees with Hermes_rete";
    "the differential oracle is non-vacuous against an inverted mutant";
    "the differential oracle has analysis-only authority" ]

let raven_law_names =
  [ "the Raven decision context exists";
    "a valid complete matrix returns a closed receipt";
    "the Raven engine identity is deterministic MCDA v1";
    "Raven decision authority is load-bearing and not caller supplied";
    "the receipt is bound to the exact current gate context";
    "canonical matrix and receipt digests ignore input permutation";
    "matrix trace and receipt digests are lowercase SHA-256";
    "ranking and scores agree with an independent exhaustive loop";
    "input order cannot select the winner";
    "Pareto dominance is disclosed exactly";
    "every admitted cell contributes with its evidence digest";
    "direction-specific normalization is exact";
    "the sensitivity margin is stable and conservative";
    "the decision trace is complete bounded and digest-bound";
    "an exact score tie uses only the declared total order";
    "tie resolution is permutation invariant";
    "prohibited alternatives are filtered before ranking";
    "failed hard constraints are filtered and disclosed";
    "a matrix with no feasible alternative is rejected";
    "contradictory hard constraints are rejected";
    "an unstable sensitivity margin blocks selection";
    "an explicit feasible forced selection is disclosed";
    "unknown or prohibited forced selection is rejected";
    "criterion weights must total exactly one million PPM";
    "criterion weights must be strictly positive";
    "duplicate criterion identifiers are rejected";
    "duplicate alternative identifiers are rejected";
    "a missing alternative criterion cell is rejected";
    "a duplicate alternative criterion cell is rejected";
    "unknown cell references are rejected";
    "cell and constraint evidence requires lowercase SHA-256";
    "the tie order must be a duplicate-free total alternative order";
    "criterion scale domains must be increasing and bounded";
    "cell and constraint values must stay within the criterion domain";
    "unsafe fixed-point arithmetic bounds are rejected";
    "the alternative budget is independent and enforced";
    "the criterion budget is independent and enforced";
    "the cell budget is independent and enforced";
    "the constraint budget is independent and enforced";
    "the decision trace budget is independent and enforced";
    "the sensitivity threshold must be within PPM range";
    "an expired exact-head receipt is rejected before decision";
    "different admitted contexts produce different receipt authority";
    "substituting exact cell evidence changes receipt authority" ]

let receipt_law_names =
  [ "the receipt-hardening context exists";
    "Rete produces closed receipts for identical work in two contexts";
    "Rete receipt fields bind authority and the exact current context";
    "Rete receipt fields bind network input session output and trace identity";
    "identical Rete work in distinct contexts has distinct receipt authority";
    "the exact Rete receipt validates against its context";
    "Rete validation rejects an identical-work foreign-context receipt";
    "Rete validation rejects a stale-current-time context";
    "Rete validation rejects every private identity mutation";
    "Rete validation rejects verdict and receipt-digest mutations";
    "Raven produces a closed receipt for the admitted matrix";
    "the exact Raven receipt validates against its context and matrix";
    "Raven validation accepts a canonical input permutation";
    "Raven validation rejects a foreign-context receipt";
    "Raven validation rejects matrix and evidence substitution";
    "Raven validation rejects result substitution";
    "exact Rete dispatch binds canonical accept outcome and fixed point";
    "exact Rete dispatch rejects coherent accept to block substitution";
    "exact Rete dispatch rejects coherent network substitution";
    "exact Rete dispatch rejects coherent fact substitution";
    "exact Rete dispatch rejects cross-context validation" ]

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf
      "FAIL coordinate=L6/observe rca=Implementation hazard=%s check=%s\n"
      (if receipts_required then "HZ-T6-INTELLIGENCE-RECEIPT-01"
       else if raven_required then "HZ-T6-INTELLIGENCE-RAVEN-01"
       else "HZ-T6-INTELLIGENCE-RETE-01")
      name
  end

let provenance : Run_model.provenance =
  { source_revision = "task6-foundation"; source_clean = true;
    configuration_digest = String.make 64 'a';
    authority_digest = String.make 64 'b';
    executable_digest = String.make 64 'c' }

let context_named ~run_id ~request_id ~observed_at_ns ~current_at_ns =
  match
    Run_safety.For_test.current_head_receipt ~run_id ~provenance
      ~observed_at_ns ~current_at_ns
      ~expires_at_ns:(Int64.add current_at_ns 1_000L)
  with
  | Error _ as error -> error
  | Ok current_head ->
      Run_safety.make_gate_context ~current_head
        ~request_id
        ~activity_id:"activity.decide-intent"
        ~coordinate:{ level = Ops_capability.L2; phase = Ops_capability.Decide }
        ~plane:Ops_capability.Control_plane

let context () =
  context_named ~run_id:"run-intelligence"
    ~request_id:"request-intelligence" ~observed_at_ns:900L
    ~current_at_ns:1_000L

let check_engine context engine expected_gate =
  begin match
    Run_intelligence.unavailable_receipt context ~engine
      ~reason:"engine execution evidence is not yet admitted"
  with
  | Error _ ->
      check "intelligence engine constructs a context-bound receipt" false;
      check "intelligence gate identity is exact" false;
      check "intelligence authority stays load-bearing" false;
      check "intelligence receipt validates against its context" false
  | Ok receipt ->
      check "intelligence engine constructs a context-bound receipt" true;
      check "intelligence gate identity is exact" (receipt.gate = expected_gate);
      check "intelligence authority stays load-bearing"
        (receipt.authority = Run_safety.Load_bearing_dispatch_gate);
      check "intelligence receipt validates against its context"
        (Result.is_ok (Run_safety.validate_receipt ~context receipt)
         && match receipt.outcome with
            | Run_safety.Unavailable_observed _ -> true
            | Run_safety.Satisfied | Run_safety.Rejected _ -> false)
  end

module R = Run_intelligence.Rete_ul

let fact id kind attrs =
  match R.make_fact ~fact_id:id ~fact_kind:kind ~attrs with
  | Ok value -> value
  | Error message -> failwith message

let budgets ?(facts = 32) ?(alpha = 64) ?(beta = 64) ?(agenda = 32)
    ?(firings = 32) ?(trace = 64) () : R.budgets =
  { max_facts = facts; max_alpha_entries = alpha; max_beta_tokens = beta;
    max_agenda = agenda; max_firings = firings; max_trace_entries = trace }

let join_network ?(limits = budgets ()) () : R.network =
  let source : R.pattern =
    { pattern_id = "pattern.source"; fact_kind = "source";
      conditions = [ R.Bind ("key", "key") ] }
  in
  let policy : R.pattern =
    { pattern_id = "pattern.policy"; fact_kind = "policy";
      conditions =
        [ R.Join_eq ("key", "key");
          R.Field_eq ("enabled", R.Bool true) ] }
  in
  { network_id = "network.join"; budgets = limits;
    rules =
      [ { rule_id = "rule.join"; salience = 10; patterns = [ source; policy ];
          actions =
            [ R.Assert_rhs
                { fact_id = "diagnosis-1"; fact_kind = "diagnosis";
                  attrs =
                    [ ("key", R.Variable "key");
                      ("status", R.Literal (R.String "matched")) ] } ] } ] }

let source ?(version = 1) () =
  fact "source-1" "source"
    [ ("key", R.String "alpha"); ("version", R.Int version) ]

let policy ?(key = "alpha") () =
  fact "policy-1" "policy"
    [ ("key", R.String key); ("enabled", R.Bool true) ]

let oscillating_network limits : R.network =
  let toggle_pattern value pattern_id : R.pattern =
    { pattern_id; fact_kind = "toggle";
      conditions = [ R.Field_eq ("mode", R.String value) ] }
  in
  let toggle_action value =
    R.Update_rhs
      { fact_id = "toggle-1"; fact_kind = "toggle";
        attrs = [ ("mode", R.Literal (R.String value)) ] }
  in
  { network_id = "network.oscillating"; budgets = limits;
    rules =
      [ { rule_id = "rule.a-to-b"; salience = 1;
          patterns = [ toggle_pattern "a" "pattern.a" ];
          actions = [ toggle_action "b" ] };
        { rule_id = "rule.b-to-a"; salience = 1;
          patterns = [ toggle_pattern "b" "pattern.b" ];
          actions = [ toggle_action "a" ] } ] }

let apply_ok = function
  | Ok (session, receipt) -> (session, receipt)
  | Error (error, _, _) -> failwith error.Run_safety.message

let compile_ok context network =
  match R.compile context network with
  | Ok compiled -> compiled
  | Error error -> failwith error.Run_safety.message

let create_ok context compiled =
  match R.create context compiled with
  | Ok session -> session
  | Error error -> failwith error.Run_safety.message

let run_ok context session =
  match R.run_to_fixed_point context session with
  | Ok value -> value
  | Error (error, _, _) -> failwith error.Run_safety.message

module M = Run_intelligence.Raven_matrix

let raven_budgets ?(alternatives = 8) ?(criteria = 8) ?(cells = 64)
    ?(constraints = 32) ?(trace = 64) ?(max_abs_value = 1_000_000L) () :
    M.budgets =
  { max_alternatives = alternatives; max_criteria = criteria;
    max_cells = cells; max_constraints = constraints; max_trace_entries = trace;
    max_abs_value }

let digest character = String.make 64 character

let raven_criteria () : M.criterion list =
  [ { criterion_id = "criterion.reliability"; direction = M.Maximize;
      weight_ppm = 600_000; scale_min = 0L; scale_max = 100L };
    { criterion_id = "criterion.latency"; direction = M.Minimize;
      weight_ppm = 400_000; scale_min = 0L; scale_max = 100L } ]

let raven_alternatives () : M.alternative list =
  [ { alternative_id = "alternative.alpha"; prohibited = false };
    { alternative_id = "alternative.beta"; prohibited = false };
    { alternative_id = "alternative.gamma"; prohibited = false } ]

let raven_cells () : M.cell list =
  [ { alternative_id = "alternative.alpha";
      criterion_id = "criterion.reliability"; value = 90L;
      evidence_digest = digest '1' };
    { alternative_id = "alternative.alpha";
      criterion_id = "criterion.latency"; value = 40L;
      evidence_digest = digest '2' };
    { alternative_id = "alternative.beta";
      criterion_id = "criterion.reliability"; value = 80L;
      evidence_digest = digest '3' };
    { alternative_id = "alternative.beta";
      criterion_id = "criterion.latency"; value = 20L;
      evidence_digest = digest '4' };
    { alternative_id = "alternative.gamma";
      criterion_id = "criterion.reliability"; value = 70L;
      evidence_digest = digest '5' };
    { alternative_id = "alternative.gamma";
      criterion_id = "criterion.latency"; value = 50L;
      evidence_digest = digest '6' } ]

let raven_matrix () : M.matrix =
  { matrix_id = "matrix.dispatch"; criteria = raven_criteria ();
    alternatives = raven_alternatives (); cells = raven_cells (); constraints = [];
    tie_order =
      [ "alternative.beta"; "alternative.alpha"; "alternative.gamma" ];
    selection_policy = M.Require_stable; min_sensitivity_ppm = 10_000;
    budgets = raven_budgets () }

let valid_lower_sha256 value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let contains text fragment =
  let text_length = String.length text and fragment_length = String.length fragment in
  let rec search index =
    index + fragment_length <= text_length
    && (String.sub text index fragment_length = fragment || search (index + 1))
  in
  fragment_length = 0 || search 0

let independent_score (matrix : M.matrix) alternative_id =
  matrix.criteria
  |> List.fold_left
       (fun total (criterion : M.criterion) ->
         let cell =
           List.find
             (fun (cell : M.cell) ->
               String.equal cell.alternative_id alternative_id
               && String.equal cell.criterion_id criterion.criterion_id)
             matrix.cells
         in
         let span = Int64.sub criterion.scale_max criterion.scale_min in
         let distance =
           match criterion.direction with
           | M.Maximize -> Int64.sub cell.value criterion.scale_min
           | M.Minimize -> Int64.sub criterion.scale_max cell.value
         in
         let normalized =
           Int64.div (Int64.mul distance 1_000_000L) span
         in
         let contribution =
           Int64.div
             (Int64.mul normalized (Int64.of_int criterion.weight_ppm))
             1_000_000L
         in
         Int64.add total contribution)
       0L
  |> Int64.to_int

let raven_decision context matrix =
  match M.decide context matrix with Ok receipt -> Some receipt | Error _ -> None

let check_raven_error context name fragment matrix =
  match M.decide context matrix with
  | Error issue -> check name (contains issue.Run_safety.message fragment)
  | Ok _ -> check name false

let run_raven_tests context =
  let matrix = raven_matrix () in
  let base = raven_decision context matrix in
  let permuted : M.matrix =
    { matrix with criteria = List.rev matrix.criteria;
      alternatives = List.rev matrix.alternatives;
      cells = List.rev matrix.cells; constraints = List.rev matrix.constraints }
  in
  let permuted_receipt = raven_decision context permuted in
  check "the Raven decision context exists" true;
  check "a valid complete matrix returns a closed receipt" (Option.is_some base);
  check "the Raven engine identity is deterministic MCDA v1"
    (Option.exists (fun receipt -> receipt.M.engine = M.Deterministic_mcda_v1) base);
  check "Raven decision authority is load-bearing and not caller supplied"
    (Option.exists
       (fun receipt ->
         receipt.M.authority = Run_safety.Load_bearing_dispatch_gate)
       base);
  check "the receipt is bound to the exact current gate context"
    (Option.exists
       (fun receipt -> String.equal receipt.M.context_digest context.context_digest)
       base);
  check "canonical matrix and receipt digests ignore input permutation"
    (match base, permuted_receipt with
     | Some left, Some right ->
         String.equal left.matrix_digest right.matrix_digest
         && String.equal left.receipt_digest right.receipt_digest
     | None, _ | _, None -> false);
  check "matrix trace and receipt digests are lowercase SHA-256"
    (Option.exists
       (fun receipt ->
         valid_lower_sha256 receipt.M.matrix_digest
         && valid_lower_sha256 receipt.trace_digest
         && valid_lower_sha256 receipt.receipt_digest)
       base);
  let expected_scores =
    matrix.alternatives
    |> List.map (fun (alternative : M.alternative) ->
           (alternative.alternative_id,
            independent_score matrix alternative.alternative_id))
    |> List.sort (fun (left_id, left) (right_id, right) ->
           let score = Int.compare right left in
           if score <> 0 then score else String.compare left_id right_id)
  in
  check "ranking and scores agree with an independent exhaustive loop"
    (Option.exists
       (fun receipt ->
         List.map
           (fun (row : M.ranked_alternative) ->
             (row.alternative_id, row.score_ppm))
           receipt.M.ranking
         = expected_scores)
       base);
  check "input order cannot select the winner"
    (match base, permuted_receipt with
     | Some left, Some right ->
         String.equal left.selected_alternative "alternative.beta"
         && String.equal left.selected_alternative right.selected_alternative
     | None, _ | _, None -> false);
  check "Pareto dominance is disclosed exactly"
    (Option.exists
       (fun receipt ->
         receipt.M.dominance
         = [ ("alternative.alpha", "alternative.gamma");
             ("alternative.beta", "alternative.gamma") ])
       base);
  check "every admitted cell contributes with its evidence digest"
    (Option.exists
       (fun receipt ->
         List.length receipt.M.contributions = 6
         && List.for_all
              (fun (row : M.contribution) ->
                valid_lower_sha256 row.evidence_digest)
              receipt.contributions)
       base);
  check "direction-specific normalization is exact"
    (Option.exists
       (fun receipt ->
         List.exists
           (fun (row : M.contribution) ->
             String.equal row.alternative_id "alternative.beta"
             && String.equal row.criterion_id "criterion.latency"
             && row.normalized_ppm = 800_000 && row.weighted_ppm = 320_000)
           receipt.M.contributions)
       base);
  check "the sensitivity margin is stable and conservative"
    (Option.exists
       (fun receipt -> receipt.M.stable && receipt.sensitivity_margin_ppm = 20_000)
       base);
  check "the decision trace is complete bounded and digest-bound"
    (Option.exists
       (fun receipt ->
         List.length receipt.M.decision_trace = 9
         && List.exists
              (String.equal "selected:alternative.beta") receipt.decision_trace
         && List.length receipt.decision_trace <= matrix.budgets.max_trace_entries
         && valid_lower_sha256 receipt.trace_digest)
       base);

  let tied_cells =
    matrix.cells
    |> List.map (fun (cell : M.cell) ->
           if String.equal cell.alternative_id "alternative.beta"
           then
             if String.equal cell.criterion_id "criterion.reliability"
             then { cell with value = 90L }
             else { cell with value = 40L }
           else cell)
  in
  let tied : M.matrix =
    { matrix with cells = tied_cells; min_sensitivity_ppm = 0 }
  in
  let tied_receipt = raven_decision context tied in
  check "an exact score tie uses only the declared total order"
    (Option.exists
       (fun receipt ->
         match receipt.M.ranking with
         | first :: second :: _ ->
             String.equal first.alternative_id "alternative.beta"
             && String.equal second.alternative_id "alternative.alpha"
             && first.score_ppm = second.score_ppm
         | _ -> false)
       tied_receipt);
  let tied_permuted =
    raven_decision context
      { tied with alternatives = List.rev tied.alternatives;
        cells = List.rev tied.cells }
  in
  check "tie resolution is permutation invariant"
    (match tied_receipt, tied_permuted with
     | Some left, Some right ->
         String.equal left.selected_alternative right.selected_alternative
         && String.equal left.receipt_digest right.receipt_digest
     | None, _ | _, None -> false);

  let prohibited_alternatives =
    matrix.alternatives
    |> List.map (fun (alternative : M.alternative) ->
           if String.equal alternative.alternative_id "alternative.beta"
           then { alternative with prohibited = true }
           else alternative)
  in
  let prohibited : M.matrix =
    { matrix with alternatives = prohibited_alternatives }
  in
  check "prohibited alternatives are filtered before ranking"
    (Option.exists
       (fun receipt ->
         String.equal receipt.M.selected_alternative "alternative.alpha"
         && List.exists
              (fun (excluded : M.exclusion) ->
                String.equal excluded.alternative_id "alternative.beta"
                && excluded.reason = M.Prohibited)
              receipt.exclusions)
       (raven_decision context prohibited));
  let latency_constraint : M.hard_constraint =
    { constraint_id = "constraint.beta-latency";
      alternative_id = "alternative.beta";
      criterion_id = "criterion.latency"; relation = M.At_most;
      threshold = 10L; evidence_digest = digest '7' }
  in
  let constrained : M.matrix =
    { matrix with constraints = [ latency_constraint ] }
  in
  check "failed hard constraints are filtered and disclosed"
    (Option.exists
       (fun receipt ->
         String.equal receipt.M.selected_alternative "alternative.alpha"
         && List.exists
              (fun (excluded : M.exclusion) ->
                String.equal excluded.alternative_id "alternative.beta"
                && excluded.reason
                   = M.Constraint_failed [ "constraint.beta-latency" ])
              receipt.exclusions)
       (raven_decision context constrained));
  let all_prohibited : M.matrix =
    { matrix with alternatives =
        List.map
          (fun (alternative : M.alternative) ->
            { alternative with prohibited = true })
          matrix.alternatives }
  in
  check_raven_error context "a matrix with no feasible alternative is rejected"
    "no feasible alternative" all_prohibited;
  let lower_constraint : M.hard_constraint =
    { latency_constraint with constraint_id = "constraint.beta-latency-lower";
      relation = M.At_least; threshold = 30L; evidence_digest = digest '8' }
  in
  let contradictory : M.matrix =
    { matrix with constraints = [ latency_constraint; lower_constraint ] }
  in
  check_raven_error context "contradictory hard constraints are rejected"
    "contradictory constraints" contradictory;
  let unstable : M.matrix =
    { matrix with min_sensitivity_ppm = 20_001 }
  in
  check_raven_error context "an unstable sensitivity margin blocks selection"
    "sensitivity" unstable;
  let forced : M.matrix =
    { unstable with selection_policy = M.Force_if_feasible "alternative.alpha" }
  in
  check "an explicit feasible forced selection is disclosed"
    (Option.exists
       (fun receipt -> receipt.M.forced
         && String.equal receipt.selected_alternative "alternative.alpha")
       (raven_decision context forced));
  let forced_prohibited : M.matrix =
    { prohibited with
      selection_policy = M.Force_if_feasible "alternative.beta" }
  in
  let forced_unknown : M.matrix =
    { matrix with selection_policy = M.Force_if_feasible "alternative.unknown" }
  in
  let invalid_force candidate =
    match M.decide context candidate with
    | Error issue -> contains issue.Run_safety.message "forced selection"
    | Ok _ -> false
  in
  check "unknown or prohibited forced selection is rejected"
    (invalid_force forced_prohibited && invalid_force forced_unknown);

  let first_criterion, second_criterion =
    match matrix.criteria with
    | [ first; second ] -> (first, second)
    | _ -> failwith "Raven fixture must contain two criteria"
  in
  check_raven_error context
    "criterion weights must total exactly one million PPM" "one million"
    { matrix with criteria =
        [ { first_criterion with weight_ppm = 599_999 }; second_criterion ] };
  check_raven_error context "criterion weights must be strictly positive"
    "strictly positive"
    { matrix with criteria =
        [ { first_criterion with weight_ppm = 0 };
          { second_criterion with weight_ppm = 1_000_000 } ] };
  check_raven_error context "duplicate criterion identifiers are rejected"
    "duplicate criterion"
    { matrix with criteria = [ first_criterion; first_criterion ] };
  let first_alternative = List.hd matrix.alternatives in
  check_raven_error context "duplicate alternative identifiers are rejected"
    "duplicate alternative"
    { matrix with alternatives = first_alternative :: matrix.alternatives };
  let first_cell = List.hd matrix.cells in
  check_raven_error context "a missing alternative criterion cell is rejected"
    "complete cell" { matrix with cells = List.tl matrix.cells };
  check_raven_error context "a duplicate alternative criterion cell is rejected"
    "duplicate cell" { matrix with cells = first_cell :: matrix.cells };
  check_raven_error context "unknown cell references are rejected" "unknown cell"
    { matrix with cells =
        { first_cell with alternative_id = "alternative.unknown" }
        :: List.tl matrix.cells };
  let bad_cell_evidence : M.matrix =
    { matrix with cells =
        { first_cell with evidence_digest = digest 'A' } :: List.tl matrix.cells }
  in
  let bad_constraint_evidence : M.matrix =
    { matrix with constraints =
        [ { latency_constraint with evidence_digest = digest 'A' } ] }
  in
  let evidence_error candidate =
    match M.decide context candidate with
    | Error issue -> contains issue.Run_safety.message "evidence digest"
    | Ok _ -> false
  in
  check "cell and constraint evidence requires lowercase SHA-256"
    (evidence_error bad_cell_evidence && evidence_error bad_constraint_evidence);
  let bad_tie_order : M.matrix =
    { matrix with tie_order =
        [ "alternative.beta"; "alternative.alpha" ] }
  in
  let duplicate_tie_order : M.matrix =
    { matrix with tie_order =
        [ "alternative.beta"; "alternative.beta"; "alternative.gamma" ] }
  in
  let tie_error candidate =
    match M.decide context candidate with
    | Error issue -> contains issue.Run_safety.message "tie order"
    | Ok _ -> false
  in
  check "the tie order must be a duplicate-free total alternative order"
    (tie_error bad_tie_order && tie_error duplicate_tie_order);
  check_raven_error context
    "criterion scale domains must be increasing and bounded" "scale domain"
    { matrix with criteria =
        { first_criterion with scale_max = 0L } :: [ second_criterion ] };
  let out_of_domain : M.matrix =
    { matrix with cells =
        { first_cell with value = 101L } :: List.tl matrix.cells }
  in
  let out_of_constraint_domain : M.matrix =
    { matrix with constraints =
        [ { latency_constraint with threshold = 101L } ] }
  in
  let domain_error candidate =
    match M.decide context candidate with
    | Error issue -> contains issue.Run_safety.message "criterion domain"
    | Ok _ -> false
  in
  check "cell and constraint values must stay within the criterion domain"
    (domain_error out_of_domain && domain_error out_of_constraint_domain);
  check_raven_error context "unsafe fixed-point arithmetic bounds are rejected"
    "arithmetic bound"
    { matrix with budgets =
        { matrix.budgets with max_abs_value = Int64.max_int } };
  check_raven_error context "the alternative budget is independent and enforced"
    "alternative budget"
    { matrix with budgets = { matrix.budgets with max_alternatives = 2 } };
  check_raven_error context "the criterion budget is independent and enforced"
    "criterion budget"
    { matrix with budgets = { matrix.budgets with max_criteria = 1 } };
  check_raven_error context "the cell budget is independent and enforced"
    "cell budget"
    { matrix with budgets = { matrix.budgets with max_cells = 5 } };
  check_raven_error context "the constraint budget is independent and enforced"
    "constraint budget"
    { constrained with budgets =
        { constrained.budgets with max_constraints = 0 } };
  check_raven_error context "the decision trace budget is independent and enforced"
    "trace budget"
    { matrix with budgets = { matrix.budgets with max_trace_entries = 8 } };
  check_raven_error context
    "the sensitivity threshold must be within PPM range" "sensitivity threshold"
    { matrix with min_sensitivity_ppm = 1_000_001 };
  let stale_head =
    Run_safety.For_test.current_head_receipt ~run_id:"run-raven-stale"
      ~provenance ~observed_at_ns:900L ~current_at_ns:1_000L
      ~expires_at_ns:999L
  in
  check "an expired exact-head receipt is rejected before decision"
    (Result.is_error stale_head);
  let other_context =
    match
      Run_safety.For_test.current_head_receipt ~run_id:"run-raven-other"
        ~provenance ~observed_at_ns:901L ~current_at_ns:1_000L
        ~expires_at_ns:2_000L
    with
    | Error _ -> None
    | Ok current_head ->
        Run_safety.make_gate_context ~current_head
          ~request_id:"request-raven-other"
          ~activity_id:"activity.decide-intent"
          ~coordinate:{ level = Ops_capability.L2; phase = Ops_capability.Decide }
          ~plane:Ops_capability.Control_plane
        |> Result.to_option
  in
  check "different admitted contexts produce different receipt authority"
    (match base, other_context with
     | Some left, Some other ->
         begin match M.decide other matrix with
         | Ok right ->
             not (String.equal left.context_digest right.context_digest)
             && not (String.equal left.receipt_digest right.receipt_digest)
         | Error _ -> false
         end
     | None, _ | _, None -> false);
  let substituted : M.matrix =
    { matrix with cells =
        { first_cell with evidence_digest = digest '9' } :: List.tl matrix.cells }
  in
  check "substituting exact cell evidence changes receipt authority"
    (match base, raven_decision context substituted with
     | Some left, Some right ->
         not (String.equal left.matrix_digest right.matrix_digest)
         && not (String.equal left.receipt_digest right.receipt_digest)
     | None, _ | _, None -> false)

let rete_closed_receipt context =
  match R.compile context (join_network ()) with
  | Error _ -> None
  | Ok compiled ->
      begin match R.create context compiled with
      | Error _ -> None
      | Ok empty ->
          begin match R.assert_fact context (source ()) empty with
          | Error _ -> None
          | Ok (with_source, _) ->
              begin match R.assert_fact context (policy ()) with_source with
              | Error _ -> None
              | Ok (active, _) ->
                  begin match R.run_to_fixed_point context active with
                  | Error _ -> None
                  | Ok (session, receipt) -> Some (compiled, session, receipt)
                  end
              end
          end
      end

let static_dispatch_network () : R.network =
  { network_id = "network.exact-static-dispatch"; budgets = budgets ();
    rules =
      [ { rule_id = "rule.exact-static-block"; salience = 10;
          patterns =
            [ { pattern_id = "pattern.exact-static"; fact_kind = "dispatch";
                conditions = [ R.Field_eq ("unsafe", R.Bool true) ] } ];
          actions = [ R.Block_rhs "unsafe dispatch" ] } ] }

let static_accept_facts () =
  [ fact "dispatch-1" "dispatch" [ ("unsafe", R.Bool false) ] ]

let static_block_facts () =
  [ fact "dispatch-1" "dispatch" [ ("unsafe", R.Bool true) ] ]

let static_dispatch_receipt context network facts =
  match R.compile context network with
  | Error _ -> None
  | Ok compiled ->
      let deltas = List.map (fun item -> R.Assert_fact item) facts in
      match R.replay context compiled deltas with
      | Ok (_, receipt) -> Some receipt
      | Error _ -> None

let run_exact_dispatch_reds context foreign_context =
  let network = static_dispatch_network () in
  let facts = static_accept_facts () in
  let receipt = static_dispatch_receipt context network facts in
  let admitted =
    Option.bind receipt (fun receipt ->
        R.admit_dispatch context ~network ~facts receipt |> Result.to_option)
  in
  check "exact Rete dispatch binds canonical accept outcome and fixed point"
    (match admitted with
     | Some (exact : R.dispatch_receipt) ->
         exact.authority = Run_safety.Load_bearing_dispatch_gate
         && exact.static_outcome = R.Static_accept
         && exact.fixed_point && exact.empty_agenda
         && Result.is_ok
              (R.validate_dispatch ~context ~network ~facts exact)
     | None -> false);
  check "exact Rete dispatch rejects coherent accept to block substitution"
    (match receipt, R.static_outcome context network (static_block_facts ()) with
     | Some receipt, Ok R.Static_block ->
         Result.is_error
           (R.admit_dispatch context ~network ~facts:(static_block_facts ())
              receipt)
     | _ -> false);
  let substituted_network =
    { network with network_id = "network.exact-static-dispatch-substituted" }
  in
  check "exact Rete dispatch rejects coherent network substitution"
    (match receipt, admitted with
     | Some receipt, Some exact ->
         Result.is_error
           (R.admit_dispatch context ~network:substituted_network ~facts receipt)
         && Result.is_error
              (R.validate_dispatch ~context ~network:substituted_network ~facts
                 exact)
     | _ -> false);
  let substituted_facts =
    [ fact "dispatch-2" "dispatch" [ ("unsafe", R.Bool false) ] ]
  in
  check "exact Rete dispatch rejects coherent fact substitution"
    (match receipt, admitted with
     | Some receipt, Some exact ->
         Result.is_error
           (R.admit_dispatch context ~network ~facts:substituted_facts receipt)
         && Result.is_error
              (R.validate_dispatch ~context ~network ~facts:substituted_facts
                 exact)
     | _ -> false);
  check "exact Rete dispatch rejects cross-context validation"
    (match foreign_context, admitted with
     | Some foreign, Some exact ->
         Result.is_error
           (R.validate_dispatch ~context:foreign ~network ~facts exact)
     | _ -> false)

let run_receipt_tests context =
  let foreign_context =
    context_named ~run_id:"run-intelligence"
      ~request_id:"request-intelligence-foreign" ~observed_at_ns:900L
      ~current_at_ns:1_000L
    |> Result.to_option
  in
  let stale_context =
    context_named ~run_id:"run-intelligence"
      ~request_id:"request-intelligence" ~observed_at_ns:1_000L
      ~current_at_ns:1_100L
    |> Result.to_option
  in
  let base = rete_closed_receipt context in
  let foreign = Option.bind foreign_context rete_closed_receipt in
  run_exact_dispatch_reds context foreign_context;
  check "the receipt-hardening context exists" true;
  check "Rete produces closed receipts for identical work in two contexts"
    (Option.is_some base && Option.is_some foreign);
  check "Rete receipt fields bind authority and the exact current context"
    (Option.exists
       (fun (_, _, (receipt : R.rete_receipt)) ->
         receipt.authority = Run_safety.Load_bearing_dispatch_gate
         && String.equal receipt.context_digest context.context_digest
         && String.equal receipt.current_head_digest context.current_head_digest
         && Int64.equal receipt.current_at_ns context.current_at_ns)
       base);
  check "Rete receipt fields bind network input session output and trace identity"
    (Option.exists
       (fun (compiled, session, (receipt : R.rete_receipt)) ->
         String.equal receipt.network_digest (R.compiled_digest compiled)
         && String.equal receipt.session_digest (R.snapshot session).session_digest
         && List.for_all valid_lower_sha256
              [ receipt.network_digest; receipt.input_fact_digest;
                receipt.session_digest; receipt.output_fact_digest;
                receipt.trace_digest; receipt.receipt_digest ])
       base);
  check "identical Rete work in distinct contexts has distinct receipt authority"
    (match base, foreign with
     | Some (_, _, left), Some (_, _, right) ->
         not (String.equal left.context_digest right.context_digest)
         && not (String.equal left.receipt_digest right.receipt_digest)
     | None, _ | _, None -> false);
  let exact_ok =
    match base with
    | None -> false
    | Some (_, _, receipt) -> Result.is_ok (R.validate_receipt ~context receipt)
  in
  check "the exact Rete receipt validates against its context" exact_ok;
  check "Rete validation rejects an identical-work foreign-context receipt"
    (exact_ok
     && match foreign with
        | Some (_, _, receipt) ->
            Result.is_error (R.validate_receipt ~context receipt)
        | None -> false);
  check "Rete validation rejects a stale-current-time context"
    (exact_ok
     && match base, stale_context with
        | Some (_, _, receipt), Some stale ->
            Result.is_error (R.validate_receipt ~context:stale receipt)
        | None, _ | _, None -> false);
  let mutations_are_rejected mutations =
    exact_ok
    && match base with
       | None -> false
       | Some (_, _, receipt) ->
           List.for_all
             (fun mutation ->
               receipt
               |> fun value -> R.For_test.mutate_receipt value mutation
               |> R.validate_receipt ~context
               |> Result.is_error)
             mutations
  in
  check "Rete validation rejects every private identity mutation"
    (mutations_are_rejected
       [ R.For_test.Authority; R.For_test.Context_digest;
         R.For_test.Current_head_digest; R.For_test.Current_at_ns;
         R.For_test.Network_digest; R.For_test.Input_fact_digest;
         R.For_test.Session_digest; R.For_test.Output_fact_digest;
         R.For_test.Trace_digest ]);
  check "Rete validation rejects verdict and receipt-digest mutations"
    (mutations_are_rejected
       [ R.For_test.Fixed_point; R.For_test.Empty_agenda;
         R.For_test.Firing_count; R.For_test.Receipt_digest ]);

  let matrix = raven_matrix () in
  let raven = raven_decision context matrix in
  let permuted : M.matrix =
    { matrix with criteria = List.rev matrix.criteria;
      alternatives = List.rev matrix.alternatives;
      cells = List.rev matrix.cells; constraints = List.rev matrix.constraints }
  in
  let raven_exact_ok =
    match raven with
    | None -> false
    | Some receipt -> Result.is_ok (M.validate_receipt ~context ~matrix receipt)
  in
  check "Raven produces a closed receipt for the admitted matrix"
    (Option.is_some raven);
  check "the exact Raven receipt validates against its context and matrix"
    raven_exact_ok;
  check "Raven validation accepts a canonical input permutation"
    (raven_exact_ok
     && match raven with
        | None -> false
        | Some receipt ->
            Result.is_ok (M.validate_receipt ~context ~matrix:permuted receipt));
  check "Raven validation rejects a foreign-context receipt"
    (raven_exact_ok
     && match raven, foreign_context with
        | Some receipt, Some foreign ->
            Result.is_error (M.validate_receipt ~context:foreign ~matrix receipt)
        | None, _ | _, None -> false);
  let first_cell = List.hd matrix.cells in
  let matrix_mutation : M.matrix =
    { matrix with cells = { first_cell with value = 91L } :: List.tl matrix.cells }
  in
  let evidence_substitution : M.matrix =
    { matrix with cells =
        { first_cell with evidence_digest = digest '9' } :: List.tl matrix.cells }
  in
  check "Raven validation rejects matrix and evidence substitution"
    (raven_exact_ok
     && match raven with
        | None -> false
        | Some receipt ->
            Result.is_error
              (M.validate_receipt ~context ~matrix:matrix_mutation receipt)
            && Result.is_error
                 (M.validate_receipt ~context ~matrix:evidence_substitution receipt));
  let forced : M.matrix =
    { matrix with selection_policy = M.Force_if_feasible "alternative.alpha" }
  in
  let forced_receipt = raven_decision context forced in
  check "Raven validation rejects result substitution"
    (raven_exact_ok
     && match forced_receipt with
        | None -> false
        | Some receipt ->
            Result.is_error (M.validate_receipt ~context ~matrix receipt))

let () =
  Printf.printf "[unit] intelligence authority foundation\n";
  begin match context () with
  | Error _ ->
      check "the intelligence context is admitted" false;
      List.iter
        (fun _ ->
          check "intelligence engine constructs a context-bound receipt" false;
          check "intelligence gate identity is exact" false;
          check "intelligence authority stays load-bearing" false;
          check "intelligence receipt validates against its context" false)
        [ Run_intelligence.Rete_ul; Run_intelligence.Raven_matrix ]
  | Ok context ->
      check "the intelligence context is admitted" true;
      check_engine context Run_intelligence.Rete_ul Run_safety.Rete_ul;
      check_engine context Run_intelligence.Raven_matrix Run_safety.Raven_matrix
  end;
  check "Rete_UL and Raven matrix have distinct gate identities"
    (Run_intelligence.gate Run_intelligence.Rete_ul
     <> Run_intelligence.gate Run_intelligence.Raven_matrix);

  if rete_required || raven_required || receipts_required then begin
    if !failures > 0 then begin
      Printf.eprintf "rete_ul_preflight=failed foundation_failures=%d\n" !failures;
      exit 2
    end;
    checks := 0;
    failures := 0
  end;

  if receipts_required then begin
    Printf.printf
      "[receipt-hardening] context and exact-input receipt validation\n";
    begin match context () with
    | Error _ -> List.iter (fun name -> check name false) receipt_law_names
    | Ok context -> run_receipt_tests context
    end
  end
  else if raven_required then begin
    Printf.printf "[raven-matrix] deterministic checked fixed-point MCDA\n";
    begin match context () with
    | Error _ -> List.iter (fun name -> check name false) raven_law_names
    | Ok context -> run_raven_tests context
    end
  end
  else if not rete_required then
    Printf.printf
      "rete_ul_status=Implemented_structural execution=not-requested\n"
  else begin
  Printf.printf "[rete-compile] indexed alpha/beta network validation\n";
  begin match context () with
  | Error _ ->
      if rete_required then List.iter (fun name -> check name false) rete_law_names
      else
        Printf.printf
          "rete_ul_status=Unavailable_observed reason=%S\n"
          "gate context unavailable before paused Rete_UL execution"
  | Ok context ->
      let network = join_network () in
      begin match R.compile context network with
      | Error issue ->
          if rete_required then
            List.iter (fun name -> check name false) rete_law_names
          else
            Printf.printf
              "rete_ul_status=Unavailable_observed reason=%S\n"
              issue.Run_safety.message
      | Ok compiled ->
      check "the Rete compile context exists" true;
      begin match R.compile context network with
      | Ok right ->
          check "a valid join network compiles" true;
          check "compiled network digest is deterministic SHA-256"
            (String.length (R.compiled_digest compiled) = 64
             && String.equal (R.compiled_digest compiled) (R.compiled_digest right))
      | Error _ ->
          check "a valid join network compiles" false;
          check "compiled network digest is deterministic SHA-256" false
      end;
      let other_network : R.network =
        { network with network_id = "network.join.other" }
      in
      let other_compiled = compile_ok context other_network in
      let other_empty = create_ok context other_compiled in
      check "empty sessions from distinct compiled networks have distinct digests"
        (not
           (String.equal (R.snapshot (create_ok context compiled)).session_digest
              (R.snapshot other_empty).session_digest));
      let forward_join : R.network =
        { network_id = "network.forward-join"; budgets = budgets ();
          rules =
            [ { rule_id = "rule.forward"; salience = 0;
                patterns =
                  [ { pattern_id = "pattern.forward"; fact_kind = "policy";
                      conditions = [ R.Join_eq ("key", "not_bound") ] } ];
                actions = [ R.Block_rhs "must never compile" ] } ] }
      in
      check "a forward or unknown join is rejected"
        (Result.is_error (R.compile context forward_join));
      let duplicate_rule =
        match network.rules with
        | [ rule ] -> { network with rules = [ rule; rule ] }
        | _ -> network
      in
      check "duplicate rule ids are rejected"
        (Result.is_error (R.compile context duplicate_rule));
      check "duplicate fact attributes are rejected before session mutation"
        (Result.is_error
           (R.make_fact ~fact_id:"bad" ~fact_kind:"source"
              ~attrs:[ ("key", R.String "a"); ("key", R.String "b") ]));

      Printf.printf "[rete-delta] persistent atomic assert/update/retract\n";
      let empty = create_ok context compiled in
      let after_source, source_delta =
        R.assert_fact context (source ()) empty |> apply_ok
      in
      check "assert records a canonical changed delta"
        (source_delta.changed
         && String.length source_delta.delta_digest = 64
         && String.length source_delta.receipt_digest = 64);
      let source_snapshot = R.snapshot after_source in
      check
        "a source fact populates alpha and beta prefixes without activating a join"
        (source_snapshot.fact_count = 1 && source_snapshot.alpha_entry_count = 1
         && source_snapshot.beta_token_count = 1
         && source_snapshot.agenda_count = 0);
      let _, other_source_delta =
        R.assert_fact context (source ()) other_empty |> apply_ok
      in
      check "delta receipts are bound to the compiled network"
        (not
           (String.equal source_delta.receipt_digest
              other_source_delta.receipt_digest));
      let after_policy, _ =
        R.assert_fact context (policy ()) after_source |> apply_ok
      in
      let ready = R.snapshot after_policy in
      check "alpha memories and beta joins create one deterministic activation"
        (ready.fact_count = 2 && ready.alpha_entry_count = 2
         && ready.beta_token_count >= 2 && ready.agenda_count = 1);
      let mismatched0 = create_ok context compiled in
      let mismatched1, _ =
        R.assert_fact context (source ()) mismatched0 |> apply_ok
      in
      let mismatched, _ =
        R.assert_fact context (policy ~key:"beta" ()) mismatched1 |> apply_ok
      in
      let mismatched_snapshot = R.snapshot mismatched in
      check "a mismatched join cannot create a final token or activation"
        (mismatched_snapshot.alpha_entry_count = 2
         && mismatched_snapshot.beta_token_count = 1
         && mismatched_snapshot.agenda_count = 0);
      let idempotent, idempotent_receipt =
        R.assert_fact context (source ()) after_policy |> apply_ok
      in
      check "byte-identical duplicate assertion is idempotent"
        (not idempotent_receipt.changed
         && String.equal (R.snapshot idempotent).session_digest
              ready.session_digest);
      let conflicting = source ~version:2 () in
      begin match R.assert_fact context conflicting after_policy with
      | Error (_, returned, partial) ->
          check "same-id different-content assertion is atomic and rejected"
            (String.equal (R.snapshot returned).session_digest ready.session_digest
             && partial.entries = [])
      | Ok _ ->
          check "same-id different-content assertion is atomic and rejected" false
      end;
      begin match
        R.update_fact context
          (fact "missing" "source" [ ("key", R.String "x") ]) after_policy
      with
      | Error (_, returned, _) ->
          check "update of a missing target returns the unchanged session"
            (String.equal (R.snapshot returned).session_digest ready.session_digest)
      | Ok _ ->
          check "update of a missing target returns the unchanged session" false
      end;

      Printf.printf "[rete-fixed-point] deterministic agenda and truth-interval refraction\n";
      let fired, receipt = run_ok context after_policy in
      let fired_snapshot = R.snapshot fired in
      check "fixed point empties the agenda and binds complete digests"
        (receipt.fixed_point && receipt.empty_agenda && receipt.firing_count = 1
         && fired_snapshot.fact_count = 3 && fired_snapshot.agenda_count = 0
         && String.length receipt.receipt_digest = 64);
      let again, again_receipt = run_ok context fired in
      check "identical support cannot refire in the same truth interval"
        (again_receipt.firing_count = 0
         && String.equal (R.snapshot again).session_digest fired_snapshot.session_digest);
      let updated, _ = R.update_fact context (source ~version:2 ()) fired |> apply_ok in
      let refired, refired_receipt = run_ok context updated in
      check "content update invalidates refraction and permits one new firing"
        (refired_receipt.firing_count = 1);
      let restored, _ =
        R.update_fact context (source ()) refired |> apply_ok
      in
      let _, restored_receipt = run_ok context restored in
      check "restoring prior content after invalidation opens a new truth interval"
        (restored_receipt.firing_count = 1);
      let retracted, _ = R.retract_fact context ~fact_id:"policy-1" refired |> apply_ok in
      let retracted_snapshot = R.snapshot retracted in
      check "retract unlinks alpha beta agenda and dependent refraction state"
        (retracted_snapshot.fact_count = 2 && retracted_snapshot.agenda_count = 0
         && retracted_snapshot.beta_token_count < (R.snapshot updated).beta_token_count);
      let relinked, _ = R.assert_fact context (policy ()) retracted |> apply_ok in
      check "reassert after retract opens a new truth interval"
        ((R.snapshot relinked).agenda_count = 1);

      Printf.printf "[rete-replay] delta log is deterministic and equivalent\n";
      let deltas =
        [ R.Assert_fact (source ()); R.Assert_fact (policy ());
          R.Update_fact (source ~version:2 ()) ]
      in
      begin match R.replay context compiled deltas with
      | Ok (replayed, replay_receipt) ->
          let manual0 = create_ok context compiled in
          let manual1, _ = R.assert_fact context (source ()) manual0 |> apply_ok in
          let manual2, _ = R.assert_fact context (policy ()) manual1 |> apply_ok in
          let manual3, _ = R.update_fact context (source ~version:2 ()) manual2 |> apply_ok in
          let manual, manual_receipt = run_ok context manual3 in
          check "replay and manual delta application have identical final state"
            (String.equal (R.snapshot replayed).session_digest
               (R.snapshot manual).session_digest
             && String.equal replay_receipt.output_fact_digest
                  manual_receipt.output_fact_digest)
      | Error _ ->
          check "replay and manual delta application have identical final state" false
      end;
      begin match
        R.replay context compiled deltas,
        R.replay context compiled [ R.Assert_fact (source ()) ]
      with
      | Ok (_, complete), Ok (_, omitted) ->
          check "replay omission changes the admitted final state"
            (not
               (String.equal complete.output_fact_digest
                  omitted.output_fact_digest))
      | _ -> check "replay omission changes the admitted final state" false
      end;
      check "replay rejects an update before its target assertion"
        (Result.is_error
           (R.replay context compiled
              [ R.Update_fact (source ~version:2 ());
                R.Assert_fact (source ()); R.Assert_fact (policy ()) ]));

      Printf.printf "[rete-bounds] caps and RHS errors fail with bounded partial traces\n";
      let tiny = compile_ok context (join_network ~limits:(budgets ~facts:1 ()) ()) in
      let tiny0 = create_ok context tiny in
      let tiny1, _ = R.assert_fact context (source ()) tiny0 |> apply_ok in
      begin match R.assert_fact context (policy ()) tiny1 with
      | Error (_, returned, partial) ->
          check "fact budget exhaustion is atomic and bounded"
            (String.equal (R.snapshot returned).session_digest
               (R.snapshot tiny1).session_digest
             && List.length partial.entries <= 64)
      | Ok _ -> check "fact budget exhaustion is atomic and bounded" false
      end;
      let alpha_limited =
        compile_ok context (join_network ~limits:(budgets ~alpha:1 ()) ())
      in
      let alpha0 = create_ok context alpha_limited in
      let alpha1, _ = R.assert_fact context (source ()) alpha0 |> apply_ok in
      begin match R.assert_fact context (policy ()) alpha1 with
      | Error (_, returned, partial) ->
          check "alpha budget exhaustion is atomic and bounded"
            (String.equal (R.snapshot returned).session_digest
               (R.snapshot alpha1).session_digest
             && partial.entries = [])
      | Ok _ -> check "alpha budget exhaustion is atomic and bounded" false
      end;
      let beta_limited =
        compile_ok context (join_network ~limits:(budgets ~beta:1 ()) ())
      in
      let beta0 = create_ok context beta_limited in
      let beta1, _ = R.assert_fact context (source ()) beta0 |> apply_ok in
      begin match R.assert_fact context (policy ()) beta1 with
      | Error (_, returned, partial) ->
          check "beta budget exhaustion is atomic and bounded"
            (String.equal (R.snapshot returned).session_digest
               (R.snapshot beta1).session_digest
             && partial.entries = [])
      | Ok _ -> check "beta budget exhaustion is atomic and bounded" false
      end;
      let agenda_network : R.network =
        match network.rules with
        | [ (rule : R.rule) ] ->
            { network_id = "network.double-agenda";
              budgets = budgets ~agenda:1 ();
              rules = [ rule; { rule with rule_id = "rule.join.second" } ] }
        | _ -> failwith "join fixture must contain exactly one rule"
      in
      let agenda_compiled = compile_ok context agenda_network in
      let agenda0 = create_ok context agenda_compiled in
      let agenda1, _ = R.assert_fact context (source ()) agenda0 |> apply_ok in
      begin match R.assert_fact context (policy ()) agenda1 with
      | Error (_, returned, partial) ->
          check "agenda budget exhaustion is atomic and bounded"
            (String.equal (R.snapshot returned).session_digest
               (R.snapshot agenda1).session_digest
             && partial.entries = [])
      | Ok _ -> check "agenda budget exhaustion is atomic and bounded" false
      end;
      let missing_rhs : R.network =
        { network_id = "network.missing-rhs"; budgets = budgets ();
          rules =
            [ { rule_id = "rule.missing-rhs"; salience = 1;
                patterns =
                  [ { pattern_id = "pattern.trigger"; fact_kind = "trigger";
                      conditions = [] } ];
                actions =
                  [ R.Update_rhs
                      { fact_id = "missing-target"; fact_kind = "derived";
                        attrs = [ ("status", R.Literal (R.String "bad")) ] } ] } ] }
      in
      let rhs_compiled = compile_ok context missing_rhs in
      let rhs0 = create_ok context rhs_compiled in
      let rhs1, _ =
        R.assert_fact context (fact "trigger-1" "trigger" []) rhs0 |> apply_ok
      in
      begin match R.run_to_fixed_point context rhs1 with
      | Error (_, returned, partial) ->
          check "an invalid RHS update preserves the pre-activation session"
            (String.equal (R.snapshot returned).session_digest
               (R.snapshot rhs1).session_digest
             && partial.entries <> [])
      | Ok _ ->
          check "an invalid RHS update preserves the pre-activation session" false
      end;

      let oscillating = oscillating_network (budgets ~firings:3 ()) in
      let osc_compiled = compile_ok context oscillating in
      let osc0 = create_ok context osc_compiled in
      let osc1, _ =
        R.assert_fact context
          (fact "toggle-1" "toggle" [ ("mode", R.String "a") ]) osc0
        |> apply_ok
      in
      begin match R.run_to_fixed_point context osc1 with
      | Error (_, _, partial) ->
          check "oscillation exhausts the firing budget rather than converging"
            (List.length partial.entries = 3)
      | Ok _ ->
          check "oscillation exhausts the firing budget rather than converging" false
      end;
      let trace_case firings =
        let compiled =
          compile_ok context
            (oscillating_network (budgets ~firings ~trace:3 ()))
        in
        let initial = create_ok context compiled in
        let active, _ =
          R.assert_fact context
            (fact "toggle-1" "toggle" [ ("mode", R.String "a") ]) initial
          |> apply_ok
        in
        match R.run_to_fixed_point context active with
        | Error (_, _, partial) -> partial
        | Ok _ -> failwith "oscillation unexpectedly reached a fixed point"
      in
      let complete_trace = trace_case 3 in
      let truncated_trace = trace_case 4 in
      check "trace entry exhaustion is bounded and records truncation"
        (List.length complete_trace.entries = 3
         && List.length truncated_trace.entries = 3
         && not complete_trace.truncated && truncated_trace.truncated
         && complete_trace.entries = truncated_trace.entries);
      check "trace digest binds the truncation flag"
        (not
           (String.equal complete_trace.trace_digest
              truncated_trace.trace_digest));

      Printf.printf "[differential] Hermes_rete is an explicit non-authority oracle\n";
      let static_network : R.network =
        { network_id = "network.static-oracle"; budgets = budgets ();
          rules =
            [ { rule_id = "rule.static-block"; salience = 1;
                patterns =
                  [ { pattern_id = "pattern.static"; fact_kind = "drift";
                      conditions = [ R.Field_eq ("unsafe", R.Bool true) ] } ];
                actions = [ R.Block_rhs "unsafe drift" ] } ] }
      in
      let static_facts =
        [ fact "drift-1" "drift" [ ("unsafe", R.Bool true) ] ]
      in
      begin match
        R.static_outcome context static_network static_facts,
        R.hermes_rete_static_outcome static_network static_facts
      with
      | Ok candidate, Ok oracle ->
          check "the supported static subset agrees with Hermes_rete"
            (candidate = oracle && oracle = R.Static_block);
          let mutant =
            match candidate with
            | R.Static_accept -> R.Static_block
            | R.Static_block -> R.Static_accept
          in
          check "the differential oracle is non-vacuous against an inverted mutant"
            (mutant <> oracle);
          check "the differential oracle has analysis-only authority"
            (R.differential_oracle_authority = Run_safety.Analysis_only)
      | _ ->
          check "the supported static subset agrees with Hermes_rete" false;
          check "the differential oracle is non-vacuous against an inverted mutant" false;
          check "the differential oracle has analysis-only authority" false
      end
      end
  end;
  end;
  Printf.printf "%s: checks=%d failures=%d\n"
    (if rete_required then "run_intelligence_rete_ul"
     else if raven_required then "run_intelligence_raven_matrix"
     else if receipts_required then "run_intelligence_receipt_hardening"
     else "run_intelligence_foundation")
    !checks !failures;
  let self =
    Suite_telemetry.observe ~suite:"test_run_intelligence"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
