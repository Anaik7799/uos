(* The gap plan as tracked data. See gap_plan.mli.

   Where a live predicate can decide an item, it does — `status` prefers
   the predicate over the declaration, and `stale_declarations` reports
   any place the two disagree so the tracker cannot drift from reality. *)

type state = Open | Partial | Closed

type item = {
  id : string;
  phase : string;
  title : string;
  evidence : string;
  derived : (unit -> state) option;
  declared : state;
}

type summary = { closed : int; partial : int; open_ : int }

(* ------------------------------------------------------- live predicates *)

let file_exists path () = if Sys.file_exists path then Closed else Open

let module_registered id () =
  if List.exists (fun (c : Fractal_ontology.component) -> c.Fractal_ontology.id = id)
       Fractal_ontology.components
  then Closed
  else Open

let all_registered ids () =
  let present =
    List.filter
      (fun id ->
        List.exists
          (fun (c : Fractal_ontology.component) -> c.Fractal_ontology.id = id)
          Fractal_ontology.components)
      ids
  in
  if List.length present = List.length ids then Closed
  else if present = [] then Open
  else Partial

let coverage_clean () =
  if
    Formal_coverage.component_gaps () = []
    && Formal_coverage.aspect_gaps () = []
    && Formal_coverage.scenario_gaps () = []
    && Formal_coverage.interaction_gaps () = []
    && Formal_coverage.missing_files () = []
  then Closed
  else Open

let intent_clean () = if Formal_coverage.reconcile () = [] then Closed else Open

let lx_constructor_exists () =
  (* F-LX-1: closed when a control-plane failure can be filed at LX
     instead of borrowing an evidence level. *)
  if Fractal_diagnostic.level_name Fractal_diagnostic.LX_control = "LX/control-plane"
  then Closed else Open

let wiki_pages_at_least n () =
  let model = Hermes_wiki.build (Hermes_wiki.read_tree "docs/hermes") in
  if List.length model.Hermes_wiki.pages >= n then Closed else Open

let usecases_at_least n () =
  if List.length Fpp_usecases.all >= n then Closed else Open

(* ------------------------------------------------------------- the items *)

let it ?derived id phase title evidence declared =
  { id; phase; title; evidence; derived; declared }

let items =
  [ (* ---- Phase 0: truth fixes ---- *)
    it "F-BT-3" "0 truth" "Battery validates the canonical blueprint"
      "one assert in the battery: Blueprint.validate over Parity_intent.blueprint" Open;
    it "H9/F-SW-2" "0 truth" "declarative-configuration.md §4 status flip"
      "five landed formal tools still marked unbuilt in the doc" Open;
    it "F-SW-8" "0 truth" "Stale '20-state signature' strings"
      "HANDOVER + test message say 20; the test asserts 44" Open;
    it ~derived:(fun () -> file_exists "modules/hermes_harness/test_atlas_freshness.ml" ())
      "G-1" "0 truth" "Atlas freshness law (regenerate and byte-compare)"
      "derived artifacts can drift between manual renders; one law covers all"
      Open;
    it ~derived:lx_constructor_exists "F-LX-1" "0 truth"
      "LX constructor in Fractal_diagnostic.fractal_level"
      "control-plane failures currently borrow evidence levels" Open;
    it "F-L6-1" "0 truth" "Drift level derived from target arity"
      "every intent drift files at L6 regardless of target" Open;
    (* ---- Phase 1: completeness engine ---- *)
    it "F-CO-2" "1 completeness" "R12 module-completeness test (dune vs ontology)"
      "the RED enumerates every unregistered module; exemptions must be reasoned"
      Open;
    it
      ~derived:
        (all_registered
           [ "converge"; "auto_converge"; "evidence_rollup"; "parity_intent";
             "run_config"; "parity_dashboard"; "determinism_verifier";
             "formal_specs"; "rocq_lattice" ])
      "F-CO-1/7/8" "1 completeness" "Register the remaining mechanism components"
      "nine modules still outside the ontology" Open;
    it "F-CO-4" "1 completeness" "Nine call-site-justified atlas edges"
      "blueprint->evidence_rollup, harness_config->{...}, etc." Open;
    it "F-CO-5" "1 completeness" "quint_frontier edges + no-isolated-node test"
      "an isolated atlas node is invisible to traversal" Open;
    (* ---- Phase 2: corpus SSoT ---- *)
    it "H6/F-SW-3" "2 ssot" "One shared scenario registry"
      "run_config folds 22 of 28; the L6 sensor detects but does not fix" Partial;
    it "F-L0-2" "2 ssot" "Empty blueprint folds to Unmapped, not Verified"
      "the vacuous-truth hole at the authoring layer" Open;
    it "F-L1-1/F-OH-8" "2 ssot" "Missing directives + requires-consistency rule"
      "routing_family declares 4 slices, rolls over 7" Open;
    it "F-BT-5" "2 ssot" "node_of_contract refuses unknown ids"
      "today it fabricates pseudo-nodes" Open;
    it "F-CO-12" "2 ssot" "Delete the drifted second blueprint (SSoT)"
      "reconcile_blueprint carries hand-fed stale actuals" Open;
    (* ---- Phase 3: validation semantics ---- *)
    it "H3/F-CO-3" "3 validation" "Conflict detection (Conflicting_desire + ancestors)"
      "same-target different-desired and ancestor/descendant unsatisfiability" Open;
    it "F-SW-5/F-BT-8" "3 validation" "HZ-INT-01/02 hazards threaded through drift"
      "live drift diagnostics render UNANALYSED" Open;
    it "F-L3-1" "3 validation" "Intent addresses L3 contracts and L4 families"
      "capability-exposure shortfall; gospel verdicts fold to one scalar" Open;
    it "F-LX-2" "3 validation" "Level test proves the EXECUTED run, not the declared map"
      "levels_of unions both Gate arms including the never-run arm" Open;
    (* ---- Phase 4: fast OODA ---- *)
    it "H4/F-OH-1" "4 fast-ooda" "Fast observe tick (zigvm Vcache mirror)"
      "one sha256sum per file over 8,556 files (~17 s) every loop entry" Open;
    it "H7/F-BT-1" "4 fast-ooda" "Real per-iteration step; Anomaly detector reachable"
      "let step _ = cached — fixpoint in one step by construction" Open;
    it "H5/F-OH-3" "4 fast-ooda" "Unattended loop (--watch, OCaml, no cron)"
      "every perturbation waits for a human today" Open;
    it "F-OH-6/F-CO-6" "4 fast-ooda" "TMPDIR countermeasure applier"
      "the one Automatic countermeasure has no applier" Open;
    (* ---- Phase 5: c3i controllers ---- *)
    it "c3i-2" "5 controllers" "runbook_registry (fail-closed tracked-runbook gate)"
      "P0/P1 with no registered runbook = configuration error" Open;
    it "c3i-3" "5 controllers" "oracle_freshness (binary-version + probe tiers)"
      "the L4 receipt-currency half is live" Partial;
    it "c3i-4" "5 controllers" "sentinel_patrol (work queue, never a verdict)"
      "autonomous re-observation FSM" Open;
    it "c3i-5" "5 controllers" "pressure_governor (hysteresis backpressure)"
      "oscillation property + EmergencyStop drain" Open;
    it "c3i-6" "5 controllers" "quarantine_registry (noise suppression only)"
      "quarantined scenarios still run and still record" Open;
    it "c3i-7" "5 controllers" "reliability_drift (Welford + z-score)"
      "3-sigma with min-sample gate and explicit re-anchor" Open;
    it "c3i-8" "5 controllers" "failure_pattern (CV classifier)"
      "bursty / periodic / Poisson over Blocked inter-arrivals" Open;
    it "c3i-9" "5 controllers" "loop_slo (loop budgets only)"
      "non-goal test: no parity-SLO constructors exist" Open;
    it "c3i-10" "5 controllers" "countermeasure_actuator (LAST, behind interlocks)"
      "gated on every interlock proven + the chaos probe green" Open;
    it "c3i-11" "5 controllers" "chaos_probe (game-day)"
      "kill a mock oracle mid-run: Blocked-not-Divergent, breaker opens, exit 2" Open;
    (* ---- Phase 6: mesh ---- *)
    it "Z-1" "6 mesh" "Per-channel telemetry topics derived from the model"
      "hermes/tlm/{instance}/{channel}; names come from the atlas" Open;
    it "Z-2" "6 mesh" "Pager path with runbook hints (needs c3i-2)"
      "FATAL/WARNING_HI to hermes/events/{severity}/{instance}" Open;
    it "Z-3" "6 mesh" "Atlas announcements (dictionary digest, coverage grade)"
      "ground consumers learn the vocabulary the way GDS does" Open;
    it "Z-4" "6 mesh" "Cross-process health pings (gated on subtopologies)"
      "pointless intra-process; opens with a second deployment" Open;
    (* ---- Phase 7: formal deepening ---- *)
    it "FS-1" "7 formal" "smtml upgrade unblocks the datatype route"
      "F-SMTML-1 pin notices when the frontend stops crashing" Open;
    it "FS-2" "7 formal" "Quint leg for ConvergeLoop (generated .qnt)"
      "BMC exists; the second-encoding differential does not" Open;
    it "FS-3" "7 formal" "coqc + quint on the host (ops task)"
      "both legs currently run as disclosed skips" Open;
    it "FS-4" "7 formal" "dune-graph vs topology differential"
      "a third encoding of the component graph" Open;
    it "FS-5" "7 formal" "Normalizer volatile-set minimality argument"
      "closes a registry Declared cell: per-path both-sides-nondeterministic law" Open;
    it "FS-6" "7 formal" "Zenoh FFI contract (gospel pre/post + property harness)"
      "closes the second registry Declared cell" Open;
    it "FS-7" "7 formal" "Packet sets / PrmDb / subtopologies / hierarchy"
      "consumer-gated: modeling ahead of use is the anti-pattern" Open;
    (* ---- Wiki/ZK/web migration ---- *)
    it ~derived:(wiki_pages_at_least 36) "W0" "8 wiki-web"
      "Migrate the six Hermes-topic notes into docs/hermes/{zk,wiki}"
      "provenance frontmatter preserved" Open;
    it ~derived:(fun () -> file_exists "modules/hermes_wiki/src/engine/hermes_wiki.ml" ())
      "W1-core" "8 wiki-web" "Wiki/ZK core engine (model, frontmatter, links, renderer)"
      "test_hermes_wiki incl. the fst back_ctx == backlinks law" Open;
    it "W1-laws" "8 wiki-web" "Port the full 91-law docs_wiki suite as a library"
      "core laws ported; the remaining zigvm laws are the W1 balance" Partial;
    it "W2" "8 wiki-web" "The twelve ZK/wiki CLI surfaces + parity table test"
      "moc/neighborhood/coverage/anomalies/query/temporal/asof" Open;
    it "W3" "8 wiki-web" "Derived pages + typed-edge == atlas differential"
      "component pages exist on the site; the differential law is next" Partial;
    it ~derived:(fun () -> file_exists "modules/hermes_harness/site_build.ml" ())
      "W4" "8 wiki-web" "Web interface: hub, dashboard, components, use cases, analytics"
      "test_site_build: completeness, determinism, read-only laws" Open;
    it "W5" "8 wiki-web" "Interactive SPA (gated decision)"
      "bonsai_web absent and route_algebra_core deleted; js_of_ocaml recommended"
      Open;
    (* ---- cross-cutting, derived ---- *)
    it ~derived:coverage_clean "X-1" "cross" "Coverage completeness stays gap-free"
      "five directions, checked every run" Closed;
    it ~derived:intent_clean "X-2" "cross" "Declared intent reconciles clean"
      "raising a floor beyond actual shows up here" Closed;
    it ~derived:(usecases_at_least 32) "X-3" "cross" "Use-case catalog >= 32 scenarios"
      "BDD floor enforced by the runner" Closed;
    it ~derived:(module_registered "formal_coverage") "X-4" "cross"
      "The registry itself is registered (R12 applies to the tracker)"
      "self-application: the coverage module has an ontology entry" Closed ]

let status item =
  match item.derived with Some predicate -> predicate () | None -> item.declared

let summary () =
  List.fold_left
    (fun acc item ->
      match status item with
      | Closed -> { acc with closed = acc.closed + 1 }
      | Partial -> { acc with partial = acc.partial + 1 }
      | Open -> { acc with open_ = acc.open_ + 1 })
    { closed = 0; partial = 0; open_ = 0 }
    items

let by_phase () =
  let phases = List.sort_uniq compare (List.map (fun i -> i.phase) items) in
  List.map (fun p -> (p, List.filter (fun i -> i.phase = p) items)) phases

let stale_declarations () =
  List.filter_map
    (fun item ->
      match item.derived with
      | None -> None
      | Some predicate ->
          let live = predicate () in
          if live = item.declared then None
          else
            Some
              (Printf.sprintf "%s: declared %s but the system says %s" item.id
                 (match item.declared with
                 | Open -> "open" | Partial -> "partial" | Closed -> "closed")
                 (match live with
                 | Open -> "open" | Partial -> "partial" | Closed -> "closed")))
    items
