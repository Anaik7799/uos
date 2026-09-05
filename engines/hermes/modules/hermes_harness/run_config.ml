(* Execute the harness's standard declarative configuration against the REAL
   subsystems: the point where the harness's own operation becomes declarative.

   The blueprint below is the comprehensive intent -- product (L0), family (L1)
   and capability (L2) targets -- validated against the real fractal (targets
   must resolve in the capability catalog), reconciled against the LIVE evidence
   roll-up (Evidence_store.parity_results), never against hand-fed verdicts.
   The activity pipeline is Harness_config.standard_pipeline: the resource
   preflight GATES everything (R13), compare produces differential evidence
   (read-only -- receipts stay with the deliberate compare command), contracts/
   determinism/reconcile run as checks, the report closes the loop.

   Read-only by design: Capture is not in the standard pipeline, and the driver
   maps it to Blocked -- a read-only interpreter refuses to write evidence, and
   Blocked is exactly "cannot proceed, nothing proved". *)

(* The comprehensive intent and its fractal resolver live in Parity_intent,
   shared with ruliad_frontier (the multiway explorer over the same space). *)
let parity_intent = Parity_intent.blueprint
let resolver = Parity_intent.resolver

(* ------------------------------------------------------------- real driver *)

let driver ~root ~snapshot_digest ~normalizer ~actual : Harness_config.driver =
  let scenario_verdicts () =
    let outcome_verdict o = Parity_compare.outcome_verdict o in
    List.map
      (fun id -> outcome_verdict (Parity_compare.compare_scenario ~root ~normalizer ~snapshot_digest id))
      Parity_compare.scenarios
    @ List.map
        (fun (id, _) ->
          outcome_verdict (Parity_compare.compare_decode_scenario ~root ~normalizer ~snapshot_digest id))
        Parity_compare.decode_scenarios
    @ List.map
        (fun (id, _) ->
          outcome_verdict (Parity_compare.compare_budget_scenario ~root ~normalizer ~snapshot_digest id))
        Parity_compare.budget_scenarios
    @ List.map
        (fun (id, _, _) ->
          outcome_verdict (Parity_compare.compare_session_scenario ~root ~normalizer ~snapshot_digest id))
        Parity_compare.session_scenarios
    @ List.map
        (fun (id, _) ->
          outcome_verdict (Parity_compare.compare_path_scenario ~root ~normalizer ~snapshot_digest id))
        Parity_compare.path_scenarios
  in
  { capture =
      (fun _ -> Parity_algebra.Blocked (* read-only interpreter: capture is a deliberate command *));
    compare =
      (fun _ -> (Parity_algebra.report ~required:true (scenario_verdicts ())).verdict);
    check_contracts =
      (fun () ->
        let verdicts =
          List.map
            (fun (contract : Contract_catalog.contract) ->
              match
                Gospel_check.check
                  ~load_path:[ "modules/hermes_harness"; "modules/hermes_harness/gospel_stubs" ]
                  ~interface:contract.Contract_catalog.interface ()
              with
              | Ok Gospel_check.Checked -> Parity_algebra.Verified
              | Ok (Gospel_check.Rejected _) -> Parity_algebra.Divergent
              | Ok Gospel_check.Unavailable | Error _ -> Parity_algebra.Blocked)
            Contract_catalog.all
        in
        Harness_config.outcome_of_list verdicts);
    check_determinism =
      (fun () ->
        let default = function Some v -> v | None -> `Null in
        let unstable = ref 0 in
        let one producer =
          match Determinism_verifier.check ~normalizer producer with
          | Determinism_verifier.Stable _ -> ()
          | Determinism_verifier.Unstable _ -> incr unstable
        in
        List.iter
          (fun (_, response) -> one (fun () -> default (Parity_compare.candidate_decode response)))
          Parity_compare.decode_scenarios;
        List.iter
          (fun (_, params) -> one (fun () -> default (Parity_compare.candidate_budget params)))
          Parity_compare.budget_scenarios;
        List.iter
          (fun (_, params) -> one (fun () -> default (Parity_compare.candidate_path params)))
          Parity_compare.path_scenarios;
        if !unstable > 0 then Parity_algebra.Blocked else Parity_algebra.Verified);
    preflight =
      (fun resources ->
        if Resource_envelope.satisfied (Resource_envelope.preflight resources) then
          Parity_algebra.Verified
        else Parity_algebra.Blocked);
    reconcile =
      (fun blueprint ->
        let plan = Blueprint.reconcile blueprint ~actual in
        List.iter
          (fun (r : Blueprint.reconciled) ->
            match r.outcome with
            | Blueprint.Satisfied ->
                Printf.printf "    intent %-16s SATISFIED\n" r.directive.Blueprint.id
            | Blueprint.Drift { desired; actual } ->
                Printf.printf "    intent %-16s DRIFT (want %s, actual %s)\n"
                  r.directive.Blueprint.id (Parity_algebra.name desired)
                  (Parity_algebra.name actual))
          plan;
        (* Drift diagnosis: the rule engine turns each drift into advice, and
           its zero-trust gate rejects a corrupted reconciliation outright. *)
        (match Drift_rules.diagnose plan with
        | Error message -> Printf.printf "    RULE GATE REJECTED: %s\n" message
        | Ok advice ->
            List.iter
              (fun (a : Drift_rules.advice) ->
                Printf.printf "    advice %-18s %s: %s\n" a.Drift_rules.action
                  a.Drift_rules.target a.Drift_rules.detail)
              advice);
        Printf.printf "    %s\n" (Blueprint.summary plan);
        if Blueprint.converged plan then Parity_algebra.Verified else Parity_algebra.Blocked);
    report =
      (fun () ->
        match Parity_dashboard.generate ~root with
        | Error message ->
            (* A report surface that cannot read the store must refuse, not
               assert (the dashboard follows evidence -- fail-closed). *)
            print_endline ("    report: " ^ message);
            Parity_algebra.Blocked
        | Ok html ->
            let dir = Filename.concat root "state/dashboard" in
            (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
            let path = Filename.concat dir "parity_dashboard.html" in
            let channel = open_out_bin path in
            output_string channel html;
            close_out channel;
            Parity_algebra.Verified) }

let git_revision root =
  let command = "git -C " ^ Filename.quote root ^ " rev-parse HEAD" in
  try
    let channel = Unix.open_process_in command in
    Fun.protect
      ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () -> String.trim (input_line channel))
  with _ -> "unknown"

let () =
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else "." in
  let normalizer = Parity_normalizer.default in
  let reference_root = Bootstrap.reference_root root in
  match Inventory.scan ~root:reference_root with
  | Error message -> prerr_endline message; exit 1
  | Ok entries -> (
      let snapshot_digest = Inventory.snapshot_digest entries in
      (* Intent validation against the real fractal, fail-closed. *)
      (match Blueprint.validate ~resolve:resolver parity_intent with
      | Error errors ->
          prerr_endline "blueprint invalid:";
          List.iter (fun e -> prerr_endline ("  " ^ Blueprint.describe_error e)) errors;
          exit 1
      | Ok () -> ());
      let store_path = Filename.concat root "state/hermes_harness.sqlite3" in
      match Evidence_store.open_db ~path:store_path with
      | Error message -> prerr_endline message; exit 1
      | Ok store ->
          let actual =
            match Evidence_store.parity_results store ~snapshot_digest with
            | Ok rows ->
                (* Full-fractal lookup: capability nodes from the roll-up,
                   family nodes and the product root rolled over the catalog
                   (an uncovered slice keeps its family honestly Unmapped). *)
                Evidence_rollup.actual_with_families
                  ~catalog:Parity_intent.family_catalog
                  ~nodes:(Evidence_rollup.per_node rows)
            | Error message -> prerr_endline message; Evidence_store.close store; exit 1
          in
          Evidence_store.close store;
          let envelope =
            Resource_envelope.
              [ Frozen_reference { root = reference_root };
                Disk_space { path = root; bytes_needed = 64 * 1024 * 1024; margin = default_margin };
                Temp_space { bytes_needed = 32 * 1024 * 1024; margin = default_margin };
                Writable (Filename.concat root "state") ]
          in
          let pipeline =
            Harness_config.standard_pipeline ~preflight:envelope ~blueprint:parity_intent
          in
          Printf.printf "== plan ==\n%s\n"
            (Harness_config.render_plan (Harness_config.plan pipeline));
          Printf.printf "== execute ==\n";
          let verdict, trail =
            Harness_config.execute (driver ~root ~snapshot_digest ~normalizer ~actual) pipeline
          in
          Printf.printf "\n== trail ==\n";
          List.iter
            (fun (o : Harness_config.outcome) ->
              Printf.printf "  %-28s %s\n" o.activity_label (Parity_algebra.name o.verdict))
            trail;
          Printf.printf "\nfolded verdict: %s\n" (Parity_algebra.name verdict);
          (* Full-fractal control sweep. This surface iterates its OWN corpus
             subset -- if the store shows receipts for MORE scenarios than the
             subset lists, the L6 leg fires P1: the registry-drift sensor
             catching this very command's staleness live. Read-only; exit 2 on
             P0 only (R10: alerts never touch verdicts). *)
          let corpus_size =
            List.length Parity_compare.scenarios
            + List.length Parity_compare.decode_scenarios
            + List.length Parity_compare.budget_scenarios
            + List.length Parity_compare.session_scenarios
            + List.length Parity_compare.path_scenarios
          in
          let frontier_counts, history, receipts_revision =
            match Evidence_store.open_db ~path:store_path with
            | Error message ->
                Printf.printf "\ncontrol plane: store unavailable (%s)\n" message;
                ([], [], None)
            | Ok store ->
                let evolution = Evidence_store.evolution_history store ~snapshot_digest in
                let history = Evidence_store.parity_history store ~snapshot_digest in
                let revision = Evidence_store.latest_receipt_revision store ~snapshot_digest in
                Evidence_store.close store;
                ( (match evolution with
                  | Error _ -> []
                  | Ok rows ->
                      List.map
                        (fun (row : Evidence_store.evolution) ->
                          let s = row.Evidence_store.satisfied in
                          if s = "" then 0 else List.length (String.split_on_char ',' s))
                        rows),
                  (match history with Ok h -> h | Error _ -> []),
                  match revision with Ok r -> r | Error _ -> None )
          in
          let recorded =
            List.length (List.sort_uniq compare (List.map (fun (_, s, _) -> s) history))
          in
          let gospel_available =
            Gospel_check.configured_binary () <> None
            || Gospel_check.path_binary "gospel" <> None
          in
          let sweep =
            Control_plane.
              { legs =
                  [ l0_frontier ~counts:frontier_counts
                      ~total:(List.length Parity_intent.blueprint);
                    l1_regressions ~history;
                    l2_flaps ~history;
                    l3_contract_oracle ~available:gospel_available;
                    l4_receipt_currency ~receipts_revision ~current:(git_revision root);
                    l6_observation_coverage ~recorded ~corpus:corpus_size;
                    lx_envelope ~satisfied:true (* the pipeline's R13 gate ran *) ];
                unsensed = [ ("L5 trace", "normalizer-version sensor queued") ] }
          in
          let sweep_text = String.concat "\n" (Control_plane.render sweep) in
          Printf.printf "\ncontrol plane (full fractal sweep):\n%s\n" sweep_text;
          (* Mesh telemetry: observation only, best-effort (c3i rule). *)
          (match
             Hermes_zenoh.publish ~key:"hermes/control/sweep/run_config" ~payload:sweep_text
           with
          | Ok () -> print_endline "zenoh: published -> hermes/control/sweep/run_config"
          | Error detail -> print_endline ("zenoh: " ^ detail ^ " -- telemetry stays local"));
          ignore
            (Hermes_zenoh.publish ~key:"hermes/control/worst/run_config"
               ~payload:(Homeostasis.describe (Control_plane.worst sweep)));
          (match Control_plane.worst sweep with
          | Homeostasis.P0 _ -> exit 2
          | _ -> ()))
