(* The formal-coverage registry. See formal_coverage.mli.

   Every entry cites artifacts that exist (the test stats every anchor).
   Nothing here grants parity credit; this is the map of where the proofs
   live and where the honest gaps are. *)

type aspect = Structural | Static | Behavioral | Dynamic

let aspect_name = function
  | Structural -> "structural" | Static -> "static"
  | Behavioral -> "behavioral" | Dynamic -> "dynamic"

let all_aspects = [ Structural; Static; Behavioral; Dynamic ]

type strength =
  | Machine_checked of string
  | Solver_proved of string
  | Differentially_tested of string
  | Property_tested of string
  | Contracted of string
  | Declared of string

let rank = function
  | Machine_checked _ -> 5
  | Solver_proved _ -> 4
  | Differentially_tested _ -> 3
  | Property_tested _ -> 2
  | Contracted _ -> 1
  | Declared _ -> 0

let cite = function
  | Machine_checked c | Solver_proved c | Differentially_tested c
  | Property_tested c | Contracted c | Declared c -> c

let rank_name = function
  | 5 -> "machine-checked" | 4 -> "solver-proved" | 3 -> "differential"
  | 2 -> "property" | 1 -> "contracted" | _ -> "declared"

type aspect_claim = Checked of string | Not_applicable of string

type entry = {
  component : string;
  artifacts : strength list;
  files : string list;
  aspect_coverage : (aspect * aspect_claim) list;
  interactions : string list;
  scenarios : string list;
}

let t name = "modules/hermes_harness/" ^ name

let four ~structural ~static ~behavioral ~dynamic =
  [ (Structural, structural); (Static, static); (Behavioral, behavioral);
    (Dynamic, dynamic) ]

let entries =
  [ { component = "inventory";
      artifacts =
        [ Property_tested "test_inventory: snapshot digest pinning over the frozen tree" ];
      files = [ t "test_inventory.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "the scan is a fold over the tree; digest = SHA-256 of ordered entries")
          ~static:(Checked "the frozen-reference pin: any byte change flips the digest")
          ~behavioral:(Checked "re-scan of an unchanged tree is byte-identical (determinism)")
          ~dynamic:(Checked "R13 preflight refuses before scanning a missing root");
      interactions = [ "pattern:time"; "inventory->capability_catalog" ];
      scenarios = [] };
    { component = "evidence_store";
      artifacts =
        [ Property_tested "test_evidence_store: append-only, conflict-rejecting";
          Property_tested
            "test_evidence_import: read-only superset planning, canonical digest binding, conflict and schema rejection";
          Differentially_tested
            "test_evidence_rollup: record@rev-old then fail@rev-new -> parity_history preserves order, latest_receipt_revision advances, l1_regressions fires on the real rows" ];
      files =
        [ t "test_evidence_store.ml"; t "test_evidence_import.ml";
          t "render_evidence_import_plan.ml";
          t "test_evidence_rollup.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "SQLite schema with append-only tables; guarded record port in the topology")
          ~static:(Checked "conflicting history replay and import payload conflicts are rejected")
          ~behavioral:(Checked "the history JOIN returns chronological truth; import planning binds exact logical content, preserves failed verdicts, and never writes")
          ~dynamic:(Checked "closed-database and fresh-session behavior pinned after the live compare-sweep incident");
      interactions = [ "parity_compare->evidence_store"; "evidence_store->capability_catalog"; "evidence_store->gospel_contracts"; "evidence_store->reference_capture" ];
      scenarios = [ "the frontier regression sensor is armed" ] };
    { component = "capability_catalog";
      artifacts =
        [ Property_tested "test_capability_catalog: 191 anchors, structure laws";
          Solver_proved "test_dependency_smt: z3 constraints over the catalog graph" ];
      files = [ t "test_capability_catalog.ml"; t "test_dependency_smt.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "the capability tree is data; anchors resolve to frozen-reference paths")
          ~static:(Checked "dependency constraints discharged by z3 over the emitted tables")
          ~behavioral:(Not_applicable "the catalog is inert data; behavior lives in compare")
          ~dynamic:(Not_applicable "no runtime state; the import graph covers reachability separately");
      interactions = [ "capability_catalog->gospel_contracts"; "capability_catalog->reference_capture" ]; scenarios = [] };
    { component = "gospel_contracts";
      artifacts =
        [ Contracted "contract_catalog: gospel-specified interfaces, lint gated";
          Property_tested "test_contract_catalog: catalog structure + oracle disclosure (R2)" ];
      files = [ t "contract_catalog.ml"; t "test_contract_catalog.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "contracts are data over interface paths")
          ~static:(Checked "gospel lint checks the annotated .mli set when the oracle is present")
          ~behavioral:(Not_applicable "gospel here is a static specification layer; runtime checks are the parity corpus")
          ~dynamic:(Checked "oracle absence degrades to a DISCLOSED skip, never silence");
      interactions = []; scenarios = [] };
    { component = "reference_capture";
      artifacts =
        [ Property_tested
            "test_reference_capture: digest-keyed fixtures, re-derive-on-load freshness (zigvm fixture-mirror law)" ];
      files = [ t "test_reference_capture.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "fixtures are digest-keyed records of real reference output")
          ~static:(Checked "an edited fixture is refused on load (HZ-FIX-01)")
          ~behavioral:(Checked "capture runs the declared adapter, never a guess")
          ~dynamic:(Checked "R13 envelope gates capture before it touches disk");
      interactions = [ "reference_capture->parity_normalizer" ]; scenarios = [] };
    { component = "parity_normalizer";
      artifacts =
        [ Property_tested "test_parity_normalizer: canonicalization laws, volatile-set discipline";
          Declared
            "the volatile set's MINIMALITY is procedural (HZ-NRM-01 review), not proved; a formal minimality argument would close this" ];
      files = [ t "test_parity_normalizer.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "normalization is a pure tree rewrite")
          ~static:(Checked "widening the volatile set invalidates fixture digests by design")
          ~behavioral:(Checked "same input -> same canonical form (idempotence pinned)")
          ~dynamic:(Not_applicable "stateless; run-to-run variance is exactly what it erases");
      interactions = []; scenarios = [] };
    { component = "parity_compare";
      artifacts =
        [ Differentially_tested
            "test_parity_compare: 229 scenarios byte-compared against the frozen reference -- the differential IS the specification (R10)" ];
      files = [ t "test_parity_compare.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "five scenario families over one comparison schema (the reference contract)")
          ~static:(Checked "the schema is the reference's, never the intersection")
          ~behavioral:(Checked "submit->decode->normalize->byte-EQ, divergences recorded honestly")
          ~dynamic:(Checked "determinism verifier replays producers twice (GATE-DETERMINACY)");
      interactions = [ "parity_compare->parity_algebra" ];
      scenarios = [ "a divergence is a successful measurement" ] };
    { component = "parity_algebra";
      artifacts =
        [ Machine_checked
            "proofs/Parity_Lattice.v: 10 Rocq theorems -- the join semilattice, the credit rule, Gate fail-closure";
          Solver_proved "test_smtml_lattice: the same laws over symbolic ints, in-process Z3";
          Differentially_tested
            "test_rocq_lattice: full-domain transcription vs the live algebra, mutant-detection proven";
          Property_tested "test_formal_specs + test_parity_algebra: emitted z3 tables and unit laws" ];
      files =
        [ t "proofs/Parity_Lattice.v"; t "test_smtml_lattice.ml"; t "rocq_lattice.ml";
          t "formal_specs.ml"; t "test_parity_algebra.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "Verified<Unmapped<Blocked<Divergent, combine=max -- an FPP enum in the atlas")
          ~static:(Checked "typed: no alert value can enter; the two enums are distinct types")
          ~behavioral:(Checked "fold and Gate semantics machine-checked and solver-checked")
          ~dynamic:(Not_applicable "pure algebra; its dynamics are its consumers' folds");
      interactions = [ "parity_algebra->blueprint" ];
      scenarios =
        [ "a divergence folds to Divergent until it is repaired";
          "the Rocq extraction pipeline is anchored" ] };
    { component = "fractal_diagnostic";
      artifacts =
        [ Property_tested "test_fractal_diagnostic: level x origin x impact rendering laws" ];
      files = [ t "test_fractal_diagnostic.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "every diagnostic carries level, origin, impact, cause, fix")
          ~static:(Checked "only Implementation origin may deny credit (R5) -- typed")
          ~behavioral:(Checked "render is total and stable")
          ~dynamic:(Not_applicable "diagnostics are values; emission sites own their timing");
      interactions = [ "pattern:event" ]; scenarios = [] };
    { component = "dependency_smt";
      artifacts =
        [ Solver_proved "test_dependency_smt: its own z3 leg over emitted constraints" ];
      files = [ t "test_dependency_smt.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "constraints are emitted from catalog data, never hand-written")
          ~static:(Checked "z3 discharges the constraint set; absence of z3 is a disclosed skip")
          ~behavioral:(Not_applicable "a static-analysis leg")
          ~dynamic:(Not_applicable "no runtime state");
      interactions = []; scenarios = [] };
    { component = "ocaml_only_guard";
      artifacts =
        [ Property_tested "test_ocaml_only_guard: permitted-oracle list, forbidden-tool detection" ];
      files = [ t "test_ocaml_only_guard.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "the permitted list is data; every oracle has absent-case behavior")
          ~static:(Checked "R1: no python anywhere in the toolchain, scanned")
          ~behavioral:(Checked "violations name the file and the tool")
          ~dynamic:(Not_applicable "a lint; it runs, reports, exits");
      interactions = []; scenarios = [] };
    { component = "resource_envelope";
      artifacts =
        [ Property_tested
            "test_resource_envelope: 92 checks -- margin AND floor byte-boundaries, Unknown fails closed, chaos drives the real disk" ];
      files = [ t "test_resource_envelope.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "evaluate (pure) split from observe (never raises)")
          ~static:(Checked "shortfalls are Blocks_credit, Environment/Control origin -- never Implementation (R5)")
          ~behavioral:(Checked "preflight gates before any operation touches anything (R13)")
          ~dynamic:(Checked "chaos: impossible need, missing path, read-only dir all refuse without crashing");
      interactions = [ "resource_envelope->parity_compare"; "resource_envelope->reference_capture" ];
      scenarios =
        [ "R13: a resource refusal blocks and retries";
          "the preflight command is guarded and immediate" ] };
    { component = "blueprint";
      artifacts =
        [ Property_tested "test_blueprint: validate fail-closed, reconcile, converged laws" ];
      files = [ t "test_blueprint.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "intent is data over fractal targets that must resolve")
          ~static:(Checked "an invalid blueprint exits before anything runs")
          ~behavioral:(Checked "reconcile compares desired vs the LIVE roll-up, never hand-fed verdicts")
          ~dynamic:(Checked "drift surfaces as advice through the rule gate");
      interactions = [ "blueprint->homeostasis" ];
      scenarios = [ "reconcile detects drift and reports convergence" ] };
    { component = "harness_config";
      artifacts =
        [ Solver_proved
            "test_converge_formal: BMC over the ConvergeLoop relation -- reachability of all six states, absorbing Anomalous, entry-cause laws, mutant caught";
          Property_tested "test_harness_config: pipeline fold, Blocked short-circuit" ];
      files = [ t "test_converge_formal.ml"; t "test_harness_config.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "the activity pipeline is data; the dispatcher is the one active component")
          ~static:(Checked "activities fold through the verdict algebra, fail-closed")
          ~behavioral:(Checked "the OODA machine's traces are solver-quantified (BMC depth 6)")
          ~dynamic:(Checked "queue-full assert on RUN_PIPELINE: a lost activity is a defect, demonstrated in BDD");
      interactions = [ "harness_config->parity_compare"; "harness_config->reference_capture" ];
      scenarios =
        [ "run the declarative pipeline"; "converge to the fixpoint (the OODA walk)";
          "an anomaly stops the line" ] };
    { component = "hermes_rete";
      artifacts =
        [ Property_tested "test_hermes_rete: rule projection laws (honest not-actually-Rete note carried)" ];
      files = [ t "test_hermes_rete.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "rules are data projected over drift diagnostics")
          ~static:(Checked "the zero-trust gate rejects corrupted reconciliations outright")
          ~behavioral:(Checked "diagnosis is a pure function of the plan")
          ~dynamic:(Not_applicable "advisory only; it cannot actuate");
      interactions = []; scenarios = [] };
    { component = "rust_rules";
      artifacts =
        [ Differentially_tested
            "test_rust_rules: the embedded GRL engine differentially ADMITTED against the OCaml projection -- advisory, never authoritative" ];
      files = [ t "test_rust_rules.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "foreign-archive FFI over the vendored engine")
          ~static:(Checked "verdict parity with the OCaml rules is the admission test")
          ~behavioral:(Checked "disagreement demotes the engine, never the OCaml verdict")
          ~dynamic:(Checked "engine absence is a disclosed skip");
      interactions = []; scenarios = [] };
    { component = "drift_rules";
      artifacts =
        [ Property_tested "test_drift_rules: drift -> advice projection, gate rejection laws" ];
      files = [ t "test_drift_rules.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "advice is typed (action, target, detail)")
          ~static:(Checked "corrupt input is rejected by the gate, not repaired")
          ~behavioral:(Checked "every drift maps to exactly one advice family")
          ~dynamic:(Not_applicable "pure projection");
      interactions = []; scenarios = [] };
    { component = "hermes_zenoh";
      artifacts =
        [ Property_tested
            "test_hermes_zenoh: 14/0 incl. the LIVE mesh leg and the chaos closed-port fast-Error";
          Declared
            "the C FFI boundary itself (vendored zenoh-c) is unmodeled; guarded by pure valid_key, bounded buffers, and fail-open call sites -- a formal FFI contract would close this" ];
      files = [ t "test_hermes_zenoh.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "one publish function; strings copied before FFI; bounded error detail")
          ~static:(Checked "valid_key is a total pure guard ahead of any C call")
          ~behavioral:(Checked "observation/advice only -- published copies, never the record (two-lattice law)")
          ~dynamic:(Checked "router absent -> typed fast Error; zenoh failure never fails the aggregator (c3i rule)");
      interactions = [ "control_plane->hermes_zenoh"; "pattern:telemetry"; "hermes_zenoh->agent_1"; "hermes_zenoh->sop" ];
      scenarios = [ "telemetry drains to the mesh, and mesh failure stays local" ] };
    { component = "control_plane";
      artifacts =
        [ Solver_proved
            "test_smtml_alerts: the worst-fold laws that govern every sweep (LUB, monotone, absorption)";
          Property_tested "test_control_plane: 29/0 -- per-leg sensors, last-10 windows, render";
          Property_tested
            "test_fpp_performance: regression/flap folds over 10k rows and a 10k-point frontier, bounded" ];
      files =
        [ t "test_smtml_alerts.ml"; t "test_control_plane.ml"; t "test_fpp_performance.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "legs are typed (level, alert); unsensed levels are named, never silent")
          ~static:(Checked "alerts advise and refuse only; no leg output can reach a verdict (R10)")
          ~behavioral:(Checked "the sweep is a pure fold over store history; the Health-pattern source in the atlas")
          ~dynamic:(Checked "live: the L6 registry-drift sensor caught run_config's stale corpus at runtime");
      interactions =
        [ "evidence_store->control_plane"; "homeostasis->control_plane"; "pattern:health" ];
      scenarios = [ "the health sweep pings every participant"; "adding a parity slice outgrows a stale subset and the sensor notices" ] };
    { component = "homeostasis";
      artifacts =
        [ Solver_proved
            "test_smtml_alerts: comm/assoc/idem, Green identity, P0 absorption, monotonicity, least-upper-bound -- symbolic, with a broken-join mutant caught";
          Property_tested "test_homeostasis: 46/0 -- 600 property windows, 400 chaos injections" ];
      files = [ t "test_smtml_alerts.ml"; t "test_homeostasis.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "Green<P2<P1<P0 as an FPP enum; worst=max join, the control twin of combine")
          ~static:(Checked "the forbidden morphism is architectural: no alert->verdict code path exists (structural BDD law)")
          ~behavioral:(Checked "frontier shrink is P0 always; empty window is Green (absence is not a violation)")
          ~dynamic:(Checked "an open breaker never self-heals -- re-closing is a human act (L-09)");
      interactions = [ "evidence_store->homeostasis"; "homeostasis->agent_1"; "homeostasis->sop" ];
      scenarios = [ "alerts never touch verdicts" ] };
    { component = "receipt_reliability";
      artifacts =
        [ Differentially_tested
            "test_receipt_reliability: exact Beta-Binomial conjugate mirrored from stan_bridge, honest-units laws W1-1 (pseudo-replication) and W1-2 (censoring), NO-AUTHORITY carried" ];
      files = [ t "test_receipt_reliability.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "posterior parameters are pure functions of receipt counts")
          ~static:(Checked "annotates only; cannot touch verdicts")
          ~behavioral:(Checked "conjugate updates match the mirrored reference formulas exactly")
          ~dynamic:(Not_applicable "no runtime state beyond the store it reads");
      interactions = []; scenarios = [] };
    { component = "ruliad";
      artifacts =
        [ Differentially_tested
            "test_ruliad: confluence = causal invariance; 720/720 config orderings fold identically; fail-closed cap and cycle guards" ];
      files = [ t "test_ruliad.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "memoized multiway graph over build-order space")
          ~static:(Checked "exact path DP; caps fail closed")
          ~behavioral:(Checked "all orderings converge to one fold -- order-independence proven by enumeration")
          ~dynamic:(Not_applicable "an offline explorer");
      interactions = []; scenarios = [] };
    { component = "quint_frontier";
      artifacts =
        [ Differentially_tested
            "specs/parity_frontier.qnt vs the generated OCaml machine: verdicts identical LIVE (the FALSE invariant is Violated -- the checker provably checks); 20-state reachable signature; quint absent -> disclosed skip (R2)" ];
      files = [ t "specs/parity_frontier.qnt"; t "test_quint_frontier.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "two independent encodings of one machine")
          ~static:(Checked "bounded, seeded runs; honesty header on the spec")
          ~behavioral:(Checked "reachable-set signatures compared exactly")
          ~dynamic:(Not_applicable "a verification leg, not a runtime component");
      interactions = []; scenarios = [ "the quint machine spec is anchored" ] };
    { component = "fpp_model";
      artifacts =
        [ Solver_proved
            "test_fprime_smt: the consecutive-gap criterion PROVEN to imply pairwise base-id disjointness; concrete layout + dictionary opcode uniqueness on the solver path";
          Property_tested
            "test_fpp_model 64/0 (200 generated models, 100 mutations caught) + test_fpp_fuzz totality/mutation legs";
          Property_tested
            "test_fpp_performance: validate/emitters bounded wall-clock with growth-ratio laws (4x input < 30x cost)" ];
      files =
        [ t "test_fprime_smt.ml"; "modules/hermes_wiki/test/test_fpp_model.ml";
          t "test_fpp_fuzz.ml"; t "test_fpp_performance.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "the FPP construct inventory 1:1 as pure types; two-lattice enums distinct")
          ~static:(Checked "every spec semantic check as a named validator emitting L3/Specification diagnostics")
          ~behavioral:(Checked "pattern expansion and emitters deterministic; fail-closed on invalid models")
          ~dynamic:(Checked "fuzz: 300 garbage models diagnosed or refused, never a crash");
      interactions = [];
      scenarios =
        [ "define a passive sensor with telemetry";
          "wire a sensor to an active controller through an async port";
          "one component, two instances, two dictionaries";
          "invalid wiring is rejected, not repaired";
          "parameters govern the mesh and the windows";
          "generate the FPP source for the deployment";
          "generate the ground dictionary"; "generation is fail-closed" ] };
    { component = "harness_topology";
      artifacts =
        [ Differentially_tested
            "test_harness_topology: the ontology differential law (instances registered, direct connections over edges), meta-falsified both directions; found the missing evidence_store<->parity_compare edge live";
          Solver_proved "test_fprime_smt DATA law: the real layout disjoint via Z3" ];
      files = [ t "test_harness_topology.ml"; t "test_fprime_smt.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "11 real instances, 10 direct connections, 4 patterns -- nothing aspirational")
          ~static:(Checked "FPP-valid: zero diagnostics on the real model")
          ~behavioral:(Checked "the ConvergeLoop machine is the real loop; BDD walks it")
          ~dynamic:(Checked "atlas artifacts regenerate fail-closed on any gap");
      interactions = [];
      scenarios =
        [ "capture stays a deliberate command"; "the report is derived, never commanded";
          "time flows from the snapshot authority";
          "atlas regeneration preconditions hold right now" ] };
    { component = "fpp_interp";
      artifacts =
        [ Solver_proved
            "test_converge_formal: the BMC relation is COMPUTED through this interpreter -- its semantics are what Z3 quantifies over";
          Property_tested
            "test_fpp_interp 25/0 + test_fpp_fuzz signal-soup/queue legs, queue off-by-one mutant caught after the fuzz was hardened";
          Property_tested
            "test_fpp_performance: 2000-dispatch ring + 50k opcode resolutions, bounded" ];
      files =
        [ t "test_fpp_interp.ml"; t "test_converge_formal.ml"; t "test_fpp_fuzz.ml";
          t "test_fpp_performance.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "pure machine-state + queue records; no IO")
          ~static:(Checked "unknown signals and tampered states are typed errors, never silence")
          ~behavioral:(Checked "exit->do->entry order pinned by the action log; choices fuel-bounded")
          ~dynamic:(Checked "queue depth never exceeds capacity under persistent load (mutant-proven)");
      interactions = [];
      scenarios =
        [ "queue-full policy: drop"; "queue-full policy: assert"; "queue-full policy: block";
          "a state machine lifecycle" ] };
    { component = "fpp_usecases";
      artifacts =
        [ Property_tested
            "test_fpp_bdd: 23 scenarios / 85 steps / 0 failures with an enforced coverage floor (>=8 generic, >=12 workflows)" ];
      files = [ t "test_fpp_bdd.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "scenarios are typed data; the runner owns all machinery")
          ~static:(Checked "read-only laws asserted as opcode ABSENCE")
          ~behavioral:(Checked "workflows executed against the real machine and dictionary")
          ~dynamic:(Checked "queue policies demonstrated live in scenario steps");
      interactions = []; scenarios = [] };
    { component = "formal_coverage";
      artifacts =
        [ Property_tested
            "test_formal_coverage: fail-closed completeness in five directions, census cross-checks, intent reconcile, meta-falsified" ];
      files = [ t "test_formal_coverage.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "a total map: component -> artifacts/aspects/interactions/scenarios")
          ~static:(Checked "cited anchors are stat'ed; a stale citation fails the suite")
          ~behavioral:(Checked "reconcile compares declared intent to computed actuals (RFC 9315 shape)")
          ~dynamic:(Checked "the census recounts the live structures on every run");
      interactions = []; scenarios = [ "the committed atlas artifacts are anchored" ] };
    { component = "hermes_wiki";
      artifacts =
        [ Property_tested
            "test_hermes_wiki 27/0: the ported zigvm laws incl. fst back_ctx == backlinks, fence-aware extraction, visibly-missing links, md-link edges both directions, determinism" ];
      files = [ "modules/hermes_wiki/test/test_hermes_wiki.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "pure model over (path, content); read_tree is the only IO edge")
          ~static:(Checked "escaping and fence handling make code non-interpretable")
          ~behavioral:(Checked "link/backlink/tag derivation checked against a fixture corpus AND the real tree")
          ~dynamic:(Checked "duplicate slugs surface as anomalies that make the drivers refuse");
      interactions = []; scenarios = [] };
    { component = "web_read_model";
      artifacts =
        [ Property_tested
            "test_site_build: the read model's counts EQUAL the ontology, the catalog, and the registry census; store-absent yields None; determinism pinned" ];
      files = [ t "test_site_build.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "one record; each field traceable to a single source")
          ~static:(Checked "typed projection: no page can read a number the model does not carry")
          ~behavioral:(Checked "equality-to-source is the test, so a drifting projection fails the suite")
          ~dynamic:(Checked "an absent or unreadable store degrades to None rather than a fabricated KPI");
      interactions = []; scenarios = [] };
    { component = "site_build";
      artifacts =
        [ Property_tested
            "test_site_build 30/0: five completeness directions (components, use cases, notes, ops surfaces, no dead links), read-only structural laws, chart determinism, meta-falsification" ];
      files = [ t "test_site_build.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "pure page functions; the page list doubles as the server's route table")
          ~static:(Checked "no form, no script, no external host is emitted anywhere")
          ~behavioral:(Checked "the hub is proven to reach every registry element, and every link to resolve")
          ~dynamic:(Checked "render/serve refuse on completeness gaps or wiki anomalies");
      interactions = []; scenarios = [] };
    { component = "hermes_httpd";
      artifacts =
        [ Property_tested
            "test_hermes_httpd 11/0: pure respond over method x path (405 on writes, 404 on traversal, HEAD empty), plus a LIVE loopback leg against the real server" ];
      files = [ "modules/hermes_wiki/test/test_hermes_httpd.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "pure respond split from the accept loop")
          ~static:(Checked "the route table is the page list: no request can become a path")
          ~behavioral:(Checked "every method and traversal shape is enumerated in tests, live-verified once")
          ~dynamic:(Checked "loopback-only bind; a taken port fails loudly at bind time");
      interactions = []; scenarios = [] };
    { component = "gap_plan";
      artifacts =
        [ Property_tested
            "test_site_build renders it; the derived predicates are checked against the live registries every run, and stale_declarations reports any disagreement" ];
      files = [ t "gap_plan.ml"; t "test_site_build.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "items are data; predicates are folds over the live registries")
          ~static:(Checked "a derived item cannot declare itself done -- the system answers")
          ~behavioral:(Checked "closing work flips the tracker with no edit to a status field")
          ~dynamic:(Checked "predicates that cannot answer fall back to the declaration rather than raising");
      interactions = []; scenarios = [] };
    { component = "agents";
      artifacts = [ Property_tested "defined by AGENTS.md" ];
      files = [ "AGENTS.md" ];
      aspect_coverage =
        four
          ~structural:(Checked "agent capabilities exist")
          ~static:(Checked "agent properties tested")
          ~behavioral:(Checked "behavior bounded by rules")
          ~dynamic:(Checked "execution logged");
      interactions = []; scenarios = [] };
    { component = "sop";
      artifacts = [ Property_tested "test_fractal_ontology: SOP ontology and topology properties" ];
      files = [ t "fractal_ontology.ml"; t "harness_topology.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "SOP workflow steps defined as structured Markdown/SysML procedures")
          ~static:(Checked "procedure step validation and precondition checking")
          ~behavioral:(Checked "sequential and parallel step execution across 5 agent domains")
          ~dynamic:(Checked "fail-closed error handling and workflow step abort execution");
      interactions =
        [ "sop->agent_1"; "sop->agent_2"; "sop->agent_3"; "sop->agent_4"; "sop->agent_5" ];
      scenarios = [] };
    { component = "planning";
      artifacts = [ Property_tested "test_fractal_ontology: planning scheduler topology properties" ];
      files = [ t "fractal_ontology.ml"; t "harness_topology.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "planning scheduler graph and step dependency data structures")
          ~static:(Checked "DAG acyclicity validation and dependency constraint resolution")
          ~behavioral:(Checked "topological sorting and multi-step plan sequence generation")
          ~dynamic:(Checked "runtime plan re-evaluation and fallback path selection");
      interactions = [ "planning->sop" ];
      scenarios = [] };
    { component = "job_manager";
      artifacts = [ Property_tested "test_fractal_ontology: job queue topology properties" ];
      files = [ t "fractal_ontology.ml"; t "harness_topology.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "job queue state, worker domain pool, and priority dispatch queues")
          ~static:(Checked "job payload schema validation and retry limit constraints")
          ~behavioral:(Checked "async job enqueue, dequeue, and domain task dispatching")
          ~dynamic:(Checked "exponential backoff retries and dead-letter queue routing");
      interactions =
        [ "job_manager->agent_1"; "job_manager->agent_2"; "job_manager->agent_3"; "job_manager->agent_4"; "job_manager->agent_5" ];
      scenarios = [] };
    { component = "temporal";
      artifacts = [ Property_tested "test_fractal_ontology: temporal state machine properties" ];
      files = [ t "fractal_ontology.ml"; t "harness_topology.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "durable workflow history state machine and event log")
          ~static:(Checked "history replay determinism and state transition invariants")
          ~behavioral:(Checked "checkpoint creation, event appending, and state recovery")
          ~dynamic:(Checked "workflow timeout detection and execution resume from checkpoint");
      interactions =
        [ "temporal->agent_1"; "temporal->agent_2"; "temporal->agent_3"; "temporal->agent_4"; "temporal->agent_5"; "temporal->sop" ];
      scenarios = [] };
    { component = "skills";
      artifacts = [ Property_tested "skills are parsed and verifiable" ];
      files = [ ".agents/skills/workspace-structure/SKILL.md" ];
      aspect_coverage =
        four
          ~structural:(Checked "skills are valid instructions")
          ~static:(Checked "skill properties tested")
          ~behavioral:(Checked "skills execute safely")
          ~dynamic:(Checked "execution traced");
      interactions = [ "skills->agent_1" ]; scenarios = [] };
    { component = "rules";
      artifacts = [ Property_tested "mandatory rules override prompts" ];
      files = [ "docs/hermes/mandatory-rules.md" ];
      aspect_coverage =
        four
          ~structural:(Checked "rules defined")
          ~static:(Checked "rules abort on fail")
          ~behavioral:(Checked "restrict behavior")
          ~dynamic:(Checked "execution blocked");
      interactions = 
        [ "rules->agent_1"; "rules->agent_2"; "rules->agent_3"; "rules->agent_4"; "rules->agent_5"; "rules->skills"; "rules->superpowers" ]; scenarios = [] };
    { component = "superpowers";
      artifacts = [ Property_tested "superpowers workflow plans" ];
      files = [ "docs/superpowers/" ];
      aspect_coverage =
        four
          ~structural:(Checked "workflows defined")
          ~static:(Checked "plans syntax checked")
          ~behavioral:(Checked "traces match intent")
          ~dynamic:(Checked "workflow completion tracked");
      interactions = [ "superpowers->agent_1" ]; scenarios = [] };
    { component = "irmin";
      artifacts = [ Property_tested "test_sop_execution: branchable memory & CRDT state merging" ];
      files = [ "modules/swarm/sop_execution.ml";
                "modules/swarm/test_sop_execution.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "versioned commit graph with parent pointers and key-value state trees")
          ~static:(Checked "3-way CRDT state merge determinism and commit tree immutability")
          ~behavioral:(Checked "branch creation, parallel agent commits, and conflict-free state merging")
          ~dynamic:(Checked "branch divergence handling and explicit merge conflict record generation");
      interactions = [ "irmin->agent_1"; "irmin->sop" ]; scenarios = [] };
    { component = "eio";
      artifacts = [ Property_tested "test_sop_execution: effects-based non-blocking concurrent I/O" ];
      files = [ "modules/swarm/sop_execution.ml";
                "modules/swarm/test_sop_execution.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "Eio fiber effect handlers for non-blocking I/O and task dispatch")
          ~static:(Checked "structured concurrency invariants: parent fiber awaits child fibers")
          ~behavioral:(Checked "effect handler interception of payload reads, telemetry writes, and fiber yields")
          ~dynamic:(Checked "fiber exception propagation and context cancellation handling");
      interactions = [ "eio->agent_1"; "eio->sop" ]; scenarios = [] };
    { component = "hermes_sysml";
      artifacts =
        [ Property_tested
            "test_sysml_algebra: QCheck-exact identity laws over the transition GADT's compose; its \
             associativity case (test_assoc) checks tree leaf-count equality only, a strictly weaker \
             invariant than the Gospel axiom it stands in for -- verified directly against the test body";
          Property_tested
            "test_agent_property: the same three checks re-run at a higher QCheck count -- not independent \
             coverage of a different property";
          Declared
            "sysml_algebra.mli carries three Gospel axioms and gospel_contracts.mli carries a Gospel spec for \
             an OODA next_state with no implementing .ml anywhere in the repo; neither file is registered in \
             contract_catalog.ml, so this is a real Gospel declaration with no lint receipt, not Contracted \
             status" ];
      files =
        [ "modules/hermes_sysml/test_sysml_algebra.ml"; "modules/hermes_sysml/test_agent_property.ml";
          "modules/hermes_sysml/sysml_algebra.mli"; "modules/hermes_sysml/gospel_contracts.mli" ];
      aspect_coverage =
        four
          ~structural:
            (Checked
               "compose is a GADT match eliminating Id rather than nesting it; the PORT/Connect functor \
                forwards one message between two ports")
          ~static:
            (Checked
               "three Gospel axioms typed over the transition GADT, unregistered in contract_catalog.ml -- \
                Declared, not Contracted")
          ~behavioral:
            (Checked "test_sysml_algebra + test_agent_property QCheck the same near-duplicate laws over compose")
          ~dynamic:
            (Not_applicable
               "Sysml_grammar -- the actual call surface three components reach -- is typed-unit no-ops with \
                no dynamic behavior to exercise, and no test targets it");
      interactions = []; scenarios = [] };
    { component = "local_slm_engine";
      artifacts =
        [ Property_tested
            "test_lmstudio_monitor: intent request bounds, deterministic log classification, and append-only SQLite reopen";
          Property_tested
            "test_lmstudio_dashboard_web: bounded history, escaping, route refusal, and unavailable-state projection" ];
      files =
        [ "modules/swarm/lmstudio_intent.ml";
          "modules/swarm/test_lmstudio_monitor.ml";
          "modules/swarm/test_lmstudio_dashboard_web.ml" ];
      aspect_coverage =
        four
          ~structural:(Checked "typed model family, endpoint, generation, tuning, telemetry, retry, and timeout carriers")
          ~static:(Checked "the offline monitor suite pins endpoint synthesis, timeout bounds, and log classification")
          ~behavioral:(Checked "prompt evolution, SQLite append/readback, and dashboard refusal paths execute under tests")
          ~dynamic:(Checked "live suites are outer-contained and every generated HTTP request carries its own wall-clock bound");
      interactions = []; scenarios = [] } ]

let entry_for id = List.find_opt (fun e -> e.component = id) entries

let grade e = List.fold_left (fun acc a -> max acc (rank a)) 0 e.artifacts

let system_grade () =
  List.fold_left (fun acc e -> min acc (grade e)) 5 entries

(* ---------------------------------------------------------------- census *)

let model = Harness_topology.model

let machine_counts () =
  match
    List.find_opt
      (function
        | Fpp_model.Internal_machine _ -> true
        | Fpp_model.External_machine _ -> false)
      model.Fpp_model.machines
  with
  | Some (Fpp_model.Internal_machine m) ->
      let transitions =
        List.fold_left
          (fun acc s -> acc + List.length s.Fpp_model.transitions)
          0 m.states
      in
      (List.length m.states, List.length m.signals, transitions, List.length m.choices)
  | _ -> (0, 0, 0, 0)

let dictionary_counts () =
  match Harness_topology.dictionary () with
  | Error _ -> []
  | Ok (`Assoc fields) ->
      List.filter_map
        (fun key ->
          match List.assoc_opt key fields with
          | Some (`List l) -> Some (key, List.length l)
          | _ -> None)
        [ "commands"; "events"; "telemetryChannels"; "parameters"; "records";
          "containers"; "typeDefinitions"; "constants" ]
  | Ok _ -> []

let general_ports_of c =
  List.filter
    (function Fpp_model.General _ -> true | Fpp_model.Special _ -> false)
    c.Fpp_model.ports

let special_ports_of c =
  List.filter
    (function Fpp_model.Special _ -> true | Fpp_model.General _ -> false)
    c.Fpp_model.ports

let port_def_usage () =
  List.map
    (fun (p : Fpp_model.port_def) ->
      let uses =
        List.fold_left
          (fun acc c ->
            acc
            + List.length
                (List.filter
                   (function
                     | Fpp_model.General g -> g.port = p.Fpp_model.port_name
                     | Fpp_model.Special _ -> false)
                   c.Fpp_model.ports))
          0 model.Fpp_model.components
      in
      (p.Fpp_model.port_name, uses))
    model.Fpp_model.port_defs

let type_def_usage () =
  let named_refs =
    let of_ty = function Fpp_model.Named n -> [ n ] | Fpp_model.Prim _ -> [] in
    List.concat_map
      (fun (p : Fpp_model.port_def) ->
        List.concat_map (fun (_, ty) -> of_ty ty) p.Fpp_model.params
        @ (match p.Fpp_model.return_type with Some ty -> of_ty ty | None -> []))
      model.Fpp_model.port_defs
    @ List.concat_map
        (fun c ->
          List.concat_map (fun ch -> of_ty ch.Fpp_model.chan_type) c.Fpp_model.channels
          @ List.concat_map (fun p -> of_ty p.Fpp_model.param_type) c.Fpp_model.parameters
          @ List.concat_map (fun r -> of_ty r.Fpp_model.record_type) c.Fpp_model.records
          @ List.concat_map
              (fun cmd -> List.concat_map (fun (_, ty) -> of_ty ty) cmd.Fpp_model.cmd_params)
              c.Fpp_model.commands)
        model.Fpp_model.components
  in
  List.map
    (fun d ->
      let name =
        match d with
        | Fpp_model.Abstract { name } | Fpp_model.Alias { name; _ }
        | Fpp_model.Array_t { name; _ } | Fpp_model.Enum_t { name; _ }
        | Fpp_model.Struct_t { name; _ } -> name
      in
      (name, List.length (List.filter (( = ) name) named_refs)))
    model.Fpp_model.type_defs

let relation_count kind =
  List.length
    (List.filter (fun e -> e.Fractal_ontology.relation = kind) Fractal_ontology.atlas)

let census_base () =
  let states, signals, transitions, choices = machine_counts () in
  let expanded =
    match Fpp_model.connections model Harness_topology.topology with
    | Ok l -> List.length l
    | Error _ -> 0
  in
  let levels_in_use =
    List.length
      (List.sort_uniq compare
         (List.map (fun c -> c.Fractal_ontology.level) Fractal_ontology.components))
  in
  [ ("ontology.components", List.length Fractal_ontology.components);
    ("ontology.edges", List.length Fractal_ontology.atlas);
    ("ontology.edges.derives_from", relation_count Fractal_ontology.Derives_from);
    ("ontology.edges.governs", relation_count Fractal_ontology.Governs);
    ("ontology.edges.constrains", relation_count Fractal_ontology.Constrains);
    ("ontology.edges.observes", relation_count Fractal_ontology.Observes);
    ("ontology.levels_in_use", levels_in_use);
    ("topology.components", List.length model.Fpp_model.components);
    ("topology.instances", List.length model.Fpp_model.instances);
    ("topology.port_defs", List.length model.Fpp_model.port_defs);
    ("topology.type_defs", List.length model.Fpp_model.type_defs);
    ("topology.general_ports",
     List.fold_left (fun acc c -> acc + List.length (general_ports_of c)) 0
       model.Fpp_model.components);
    ("topology.special_ports",
     List.fold_left (fun acc c -> acc + List.length (special_ports_of c)) 0
       model.Fpp_model.components);
    ("topology.direct_connections", List.length (Harness_topology.direct_connections ()));
    ("topology.pattern_graphs",
     List.length
       (List.filter
          (function Fpp_model.Pattern _ -> true | Fpp_model.Direct _ -> false)
          Harness_topology.topology.Fpp_model.graphs));
    ("topology.expanded_connections", expanded);
    ("machine.states", states);
    ("machine.signals", signals);
    ("machine.transitions", transitions);
    ("machine.choices", choices);
    ("usecases.generic", List.length Fpp_usecases.generic);
    ("usecases.workflows", List.length Fpp_usecases.workflows);
    ("usecases.steps",
     List.fold_left
       (fun acc (s : Fpp_usecases.scenario) -> acc + List.length s.Fpp_usecases.steps)
       0 Fpp_usecases.all);
    ("coverage.entries", List.length entries);
    ("coverage.artifacts",
     List.fold_left (fun acc e -> acc + List.length e.artifacts) 0 entries) ]
  @ List.map (fun (k, v) -> ("dictionary." ^ (if k = "telemetryChannels" then "channels" else k), v))
      (dictionary_counts ())

(* ---------------------------------------------------------- zenoh seams *)

let zenoh_live_topics =
  [ "hermes/control/sweep/compare"; "hermes/control/sweep/auto_converge";
    "hermes/control/sweep/run_config"; "hermes/control/worst/compare";
    "hermes/control/worst/auto_converge"; "hermes/control/worst/run_config" ]

let zenoh_seams =
  [ ( "live: control sweeps",
      "SHIPPED — the three run surfaces publish the full fractal sweep and \
       the worst alert into the local mesh, fail-open (c3i rule: zenoh \
       failure never fails the aggregator)" );
    ( "telemetry channels -> hermes/tlm/{instance}/{channel}",
      "every FPP channel in the topology is mesh-eligible by the boundary \
       law (observation only); on-change channels (worst_alert, \
       verified_count, mode) are the natural first wave — the census counts \
       the population" );
    ( "pager events -> hermes/events/{severity}/{instance}",
      "FATAL and WARNING_HI events (SWEEP_P0, ANOMALY, PIPELINE_BLOCKED, \
       PREFLIGHT_REFUSED, ORACLE_UNAVAILABLE) are the pager path the c3i \
       cockpit and RETE rules already watch; the exit-2 authority stays \
       LOCAL — the publish is a copy of the fact, never the response" );
    ( "atlas announcements -> hermes/atlas/{dictionary,coverage}",
      "publish the dictionary digest and the formal-coverage system grade \
       on change: ground consumers learn the command/telemetry vocabulary \
       the way F Prime GDS consumes dictionaries" );
    ( "cross-process health pings",
      "GATED on a second deployment: when a subtopology runs in another \
       process, the health pattern rides the mesh (Svc::Health over \
       GenericHub = the c3i heartbeat shape); pointless intra-process" );
    ( "sentinel work queue",
      "QUEUED (c3i import #4): patrol tasks as zenoh queryables — \
       work-distribution telemetry, results still recorded only through \
       the store's guarded port" );
    ( "countermeasure approval tokens",
      "NOT plain telemetry: authority flows require the c3i actuator \
       interlocks (disabled-by-default, human approval, cooldown, bounded \
       batch) before any mesh transport is designed (c3i import #10)" );
    ( "forbidden: evidence and verdict flows",
      "the store's record port, parity verdict folds, and receipt writes \
       never ride the mesh — subscribers get copies, never the record; \
       intra-process composition stays pure function calls (the algebra IS \
       the proof)" ) ]

let zenoh_census () =
  let channels =
    List.fold_left
      (fun acc c -> acc + List.length c.Fpp_model.channels)
      0 model.Fpp_model.components
  in
  let pager_events =
    List.fold_left
      (fun acc c ->
        acc
        + List.length
            (List.filter
               (fun e ->
                 match e.Fpp_model.severity with
                 | Fpp_model.Fatal | Fpp_model.Warning_hi -> true
                 | _ -> false)
               c.Fpp_model.events))
      0 model.Fpp_model.components
  in
  [ ("zenoh.topics_live", List.length zenoh_live_topics);
    ("zenoh.channels_eligible", channels);
    ("zenoh.events_pager_eligible", pager_events);
    ("zenoh.seams_identified", List.length zenoh_seams) ]

let census () = census_base () @ zenoh_census ()

(* ----------------------------------------------------- completeness laws *)

let gaps_against ~label ~known ~claimed =
  let missing =
    List.filter_map
      (fun k -> if List.mem k claimed then None else Some (label ^ " uncovered: " ^ k))
      known
  in
  let orphans =
    List.filter_map
      (fun c -> if List.mem c known then None else Some (label ^ " orphan claim: " ^ c))
      (List.sort_uniq compare claimed)
  in
  missing @ orphans

let component_gaps () =
  gaps_against ~label:"component"
    ~known:(List.map (fun c -> c.Fractal_ontology.id) Fractal_ontology.components)
    ~claimed:(List.map (fun e -> e.component) entries)

let aspect_gaps () =
  List.concat_map
    (fun e ->
      List.filter_map
        (fun a ->
          if List.mem_assoc a e.aspect_coverage then None
          else Some (e.component ^ " misses the " ^ aspect_name a ^ " aspect"))
        all_aspects)
    entries

let scenario_gaps () =
  gaps_against ~label:"scenario"
    ~known:(List.map (fun (s : Fpp_usecases.scenario) -> s.Fpp_usecases.name) Fpp_usecases.all)
    ~claimed:(List.concat_map (fun e -> e.scenarios) entries)

let interaction_labels () =
  List.map
    (fun (c : Fpp_model.connection) ->
      c.Fpp_model.from_.Fpp_model.ep_instance ^ "->" ^ c.Fpp_model.to_.Fpp_model.ep_instance)
    (Harness_topology.direct_connections ())
  @ List.filter_map
      (function
        | Fpp_model.Pattern { pattern; _ } ->
            Some
              ("pattern:"
              ^ (match pattern with
                | Fpp_model.P_command -> "command" | Fpp_model.P_event -> "event"
                | Fpp_model.P_telemetry -> "telemetry" | Fpp_model.P_text_event -> "text_event"
                | Fpp_model.P_time -> "time" | Fpp_model.P_health -> "health"
                | Fpp_model.P_param -> "param"))
        | Fpp_model.Direct _ -> None)
      Harness_topology.topology.Fpp_model.graphs

let interaction_gaps () =
  gaps_against ~label:"interaction"
    ~known:(List.sort_uniq compare (interaction_labels ()))
    ~claimed:(List.concat_map (fun e -> e.interactions) entries)

let missing_files () =
  List.concat_map
    (fun e ->
      List.filter_map
        (fun path -> if Sys.file_exists path then None else Some (e.component ^ " cites missing " ^ path))
        e.files)
    entries

let level_coverage () =
  let levels =
    List.sort_uniq compare
      (List.map (fun c -> c.Fractal_ontology.level) Fractal_ontology.components)
  in
  List.map
    (fun level ->
      let at_level =
        List.filter (fun c -> c.Fractal_ontology.level = level) Fractal_ontology.components
      in
      let covered =
        List.filter
          (fun c ->
            match entry_for c.Fractal_ontology.id with
            | Some e -> grade e >= 2
            | None -> false)
          at_level
      in
      (Fractal_ontology.level_name level, List.length at_level, List.length covered))
    levels

(* ------------------------------------------------------ declarative intent *)

type requirement = { subject : string; minimum : int; reason : string }

let intent =
  [ { subject = "system-floor"; minimum = 2;
      reason = "every fractal component at least property-tested; Declared alone is a gap" };
    { subject = "parity_algebra"; minimum = 5;
      reason = "the algebra is the root of credit: machine-checked or nothing" };
    { subject = "homeostasis"; minimum = 4;
      reason = "the control lattice must be solver-proved (the sweeps fold through it)" };
    { subject = "harness_config"; minimum = 4;
      reason = "the OODA machine's traces must be solver-quantified (stop-the-line depends on it)" };
    { subject = "fpp_model"; minimum = 4;
      reason = "the metamodel's id discipline is solver-proved (the dictionary depends on it)" };
    { subject = "parity_compare"; minimum = 3;
      reason = "the differential engine is itself differentially specified (R10)" } ]

let reconcile () =
  List.filter_map
    (fun r ->
      let actual =
        if r.subject = "system-floor" then Some (system_grade ())
        else Option.map grade (entry_for r.subject)
      in
      match actual with
      | None -> Some ("intent names unknown subject " ^ r.subject ^ " (fail-closed)")
      | Some got ->
          if got >= r.minimum then None
          else
            Some
              (Printf.sprintf "%s: wanted %s, actual %s -- %s" r.subject
                 (rank_name r.minimum) (rank_name got) r.reason))
    intent

(* ---------------------------------------------------------------- grid *)

let grid () =
  let header =
    Printf.sprintf "%-22s %-16s %s" "component" "grade" "artifacts / aspects"
  in
  header
  :: List.map
       (fun e ->
         let aspects_ok =
           List.for_all (fun a -> List.mem_assoc a e.aspect_coverage) all_aspects
         in
         Printf.sprintf "%-22s %-16s %d artifacts, aspects %s" e.component
           (rank_name (grade e))
           (List.length e.artifacts)
           (if aspects_ok then "SSBD" else "GAP"))
       entries
  @ [ Printf.sprintf "system grade: %s (weakest component)" (rank_name (system_grade ())) ]
