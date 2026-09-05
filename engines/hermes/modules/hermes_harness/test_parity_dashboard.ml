(* The dashboard is a generated presentation surface; the test guards that every
   KPI it must surface actually appears in the output, so a rendering change that
   silently drops one fails here. render is pure over a kpi, so no IO is needed.

   Since the F-SW-1/F-OH-2/F-L0-1 fix, the KPIs themselves are DERIVED from the
   store's (contract_id, passed) rows by [kpi_of_rows] -- these tests prove the
   derivation is differential (different evidence -> different numbers), so a
   hand-frozen dashboard can never come back silently. *)

let contains text needle =
  let length = String.length text and needle_length = String.length needle in
  let rec loop index =
    index + needle_length <= length
    && (String.sub text index needle_length = needle || loop (index + 1))
  in
  needle_length = 0 || loop 0

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    print_endline ("FAILED: " ^ name)
  end

let empty_hermes =
  Hermes_analysis.{ files = 0; lines = 0; defs = 0; classes = 0; modules = [] }

(* ------------------------------------------------------------ derivation *)

(* Synthetic latest-per-scenario rows across three capability nodes: two pass,
   one fails. Every KPI must follow the rows, not a constant. *)
let mixed_rows =
  [ ("model_routing.provider_transports.request_shaping", true);
    ("model_routing.rate_and_retry.retry_after", true);
    ("agent_loop.interrupt_control.iteration_budget", false) ]

let () =
  let kpi =
    Parity_dashboard.kpi_of_rows ~hermes:empty_hermes ~fixtures:0
      ~snapshot:"testsnap" ~contracts_declared:11 ~control:[] ~rows:mixed_rows
  in
  check "derived verified counts the passing rows" (kpi.Parity_dashboard.verified = 2);
  check "derived total counts all rows" (kpi.Parity_dashboard.total_scenarios = 3);
  check "derived covered_slices counts distinct nodes"
    (kpi.Parity_dashboard.covered_slices = 3);
  check "no family is verified from partial coverage"
    (kpi.Parity_dashboard.families_verified = 0);
  check "snapshot is threaded through" (kpi.Parity_dashboard.snapshot = "testsnap");
  (* The differential guard: removing the failing row must CHANGE the KPIs.
     A derivation that ignored its input would pass the checks above with
     constants; this one cannot. *)
  let kpi' =
    Parity_dashboard.kpi_of_rows ~hermes:empty_hermes ~fixtures:0
      ~snapshot:"testsnap" ~contracts_declared:11 ~control:[]
      ~rows:(List.filter snd mixed_rows)
  in
  check "different evidence yields different totals"
    (kpi'.Parity_dashboard.total_scenarios = 2
    && kpi'.Parity_dashboard.covered_slices = 2
    && kpi'.Parity_dashboard.total_scenarios <> kpi.Parity_dashboard.total_scenarios)

(* ---------------------------------------------- family-scale vacuous truth *)

(* Build one passing row per model_routing capability FROM THE CATALOG (no
   hand-rolled node list -- the catalog is the single source). *)
let routing_contract_ids =
  List.filter_map
    (fun (c : Capability_catalog.capability) ->
      let node = Capability_catalog.node_id c in
      let prefix = "hermes.model_routing." in
      let plen = String.length prefix in
      if String.length node > plen && String.sub node 0 plen = prefix then
        (* node = hermes.<family>.<cap> -> contract id <family>.<cap>.synthetic *)
        Some (String.sub node 7 (String.length node - 7) ^ ".synthetic")
      else None)
    Capability_catalog.all

let () =
  check "the catalog exposes the model_routing capabilities"
    (List.length routing_contract_ids >= 2);
  let full = List.map (fun id -> (id, true)) routing_contract_ids in
  let kpi_full =
    Parity_dashboard.kpi_of_rows ~hermes:empty_hermes ~fixtures:0
      ~snapshot:"testsnap" ~contracts_declared:11 ~control:[] ~rows:full
  in
  check "a family with every slice verified counts as verified"
    (kpi_full.Parity_dashboard.families_verified = 1);
  (* Drop one slice: the family must fall back to unverified -- the
     vacuous-truth guard at family scale, now visible on the dashboard. *)
  let kpi_partial =
    Parity_dashboard.kpi_of_rows ~hermes:empty_hermes ~fixtures:0
      ~snapshot:"testsnap" ~contracts_declared:11 ~control:[] ~rows:(List.tl full)
  in
  check "one uncovered slice unverifies the family"
    (kpi_partial.Parity_dashboard.families_verified = 0);
  (* Render honesty: the family pill text is derived from the same verdicts. *)
  let html = Parity_dashboard.render kpi_full in
  check "verified family pill is derived"
    (contains html
       ("VERIFIED \xe2\x80\x94 all "
       ^ string_of_int (List.length routing_contract_ids)
       ^ " slices"));
  check "uncovered families say so" (contains html "no differential evidence");
  check "derived snapshot appears in the render" (contains html "testsnap");
  check "the contract chip is derived, not a constant"
    (contains html "11 declared")

(* ------------------------------------------------- rendering guard (kept) *)

let () =
  let kpi =
    Parity_dashboard.kpi_of_rows ~hermes:empty_hermes ~fixtures:13
      ~snapshot:"70b2efe95be5" ~contracts_declared:11 ~control:[]
      ~rows:
        (List.init 13 (fun i ->
             ("model_routing.provider_transports.s" ^ string_of_int i, true)))
  in
  let html = Parity_dashboard.render kpi in
  check "strict parity stays family-level honest" (contains html "Strict parity: 0 of");
  check "well-formed document" (contains html "<!doctype html>");
  check "dark scheme media query" (contains html "prefers-color-scheme:dark");
  check "explicit theme toggle hook" (contains html "data-theme=\"dark\"");
  check "headline title" (contains html "Hermes parity harness");
  check "headline scenario KPI" (contains html "13/13");
  check "covered capability named" (contains html "provider_transports");
  List.iter
    (fun level -> check ("fractal chain shows " ^ level) (contains html level))
    [ "L0"; "L1"; "L2"; "L3"; "L4"; "L5"; "L6" ];
  List.iter
    (fun (family, _) ->
      check ("family row " ^ family) (contains html family))
    (Parity_dashboard.families ());
  check "snapshot pin shown" (contains html "70b2efe95be5")

(* Control-plane section: rendered when sweep lines are supplied, absent when
   not (the section never fabricates a sweep it was not given). *)
let () =
  let base ~control =
    Parity_dashboard.kpi_of_rows ~hermes:empty_hermes ~fixtures:0 ~snapshot:"s"
      ~contracts_declared:11 ~control ~rows:[]
  in
  let with_control =
    Parity_dashboard.render
      (base ~control:[ "  L0 product     green"; "  L5 trace       unsensed -- queued" ])
  in
  check "control sweep section renders"
    (contains with_control "Control plane (fractal sweep)");
  check "control sweep lines render" (contains with_control "unsensed -- queued");
  check "no control lines, no section"
    (not (contains (Parity_dashboard.render (base ~control:[])) "Control plane (fractal sweep)"))

let () =
  Printf.printf "parity_dashboard: passed: %d failed: %d\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_parity_dashboard" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_parity_dashboard ]);
  exit (Suite_telemetry.exit_code self)
