(* Automatic convergence of configuration to intent, LIVE. The closed loop of
   intent-based networking, honestly bounded by R10:

   1. Declare the intent (Parity_intent.blueprint).
   2. Compute actual by running the full differential-evidence corpus against the
      frozen reference (deterministic -- the determinism gate proves it), rolled
      up per fractal node and family.
   3. Reconcile: the satisfied intents are those whose target verdict meets the
      desired one.
   4. Iterate to a fixpoint (Converge.converge -- monotone, bounded, terminating;
      the lattice laws it rests on are machine-checked in Parity_Lattice.v).

   The loop converges the OBSERVED configuration to intent as far as the current
   candidate allows and settles at a fixpoint whose residual drift is exactly the
   real candidate work the loop cannot fabricate (R10). Drift_rules turns that
   residual into an actionable runbook. Nothing here grants credit. *)

let slice_nodes ~root ~normalizer ~snapshot_digest =
  let ov = Parity_compare.outcome_verdict in
  (* per covered capability node, roll its scenario verdicts up *)
  [ ( "hermes.model_routing.provider_transports",
      Parity_algebra.roll_up ~required:true
        (List.map (fun id -> ov (Parity_compare.compare_scenario ~root ~normalizer ~snapshot_digest id))
           Parity_compare.scenarios
        @ List.map (fun (id, _) -> ov (Parity_compare.compare_decode_scenario ~root ~normalizer ~snapshot_digest id))
            Parity_compare.decode_scenarios
        @ List.map (fun (id, _, _) -> ov (Parity_compare.compare_session_scenario ~root ~normalizer ~snapshot_digest id))
            Parity_compare.session_scenarios) );
    ( "hermes.agent_loop.interrupt_control",
      Parity_algebra.roll_up ~required:true
        (List.map (fun (id, _) -> ov (Parity_compare.compare_budget_scenario ~root ~normalizer ~snapshot_digest id))
           Parity_compare.budget_scenarios) );
    ( "hermes.tool_execution.path_and_url_safety",
      Parity_algebra.roll_up ~required:true
        (List.map (fun (id, _) -> ov (Parity_compare.compare_path_scenario ~root ~normalizer ~snapshot_digest id))
           Parity_compare.path_scenarios) );
    ( "hermes.model_routing.rate_and_retry",
      Parity_algebra.roll_up ~required:true
        (List.map (fun (id, _) -> ov (Parity_compare.compare_retry_scenario ~root ~normalizer ~snapshot_digest id))
           Parity_compare.retry_scenarios) );
    ( "hermes.model_routing.route_resolution",
      Parity_algebra.roll_up ~required:true
        (List.map (fun (id, _) -> ov (Parity_compare.compare_route_scenario ~root ~normalizer ~snapshot_digest id))
           Parity_compare.route_scenarios) );
    ( "hermes.model_routing.anthropic_adapter",
      Parity_algebra.roll_up ~required:true
        (List.map (fun (id, _) -> ov (Parity_compare.compare_anthropic_scenario ~root ~normalizer ~snapshot_digest id))
           Parity_compare.anthropic_scenarios) );
    ( "hermes.model_routing.codex_runtime",
      Parity_algebra.roll_up ~required:true
        (List.map (fun (id, _) -> ov (Parity_compare.compare_codex_scenario ~root ~normalizer ~snapshot_digest id))
           Parity_compare.codex_scenarios) );
    ( "hermes.model_routing.gemini_adapter",
      Parity_algebra.roll_up ~required:true
        (List.map (fun (id, _) -> ov (Parity_compare.compare_gemini_scenario ~root ~normalizer ~snapshot_digest id))
           Parity_compare.gemini_scenarios) );
    ( "hermes.model_routing.cloud_vendor_adapters",
      Parity_algebra.roll_up ~required:true
        (List.map (fun (id, _) -> ov (Parity_compare.compare_bedrock_scenario ~root ~normalizer ~snapshot_digest id))
           Parity_compare.bedrock_scenarios) ) ]

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
  (* R13: refuse with a named fractal cause when the frozen reference is
     absent, instead of dying raw inside the scan (F-OH-4 -- ACP separation:
     the control plane reports even when the data plane is broken). *)
  let checks =
    Resource_envelope.preflight Resource_envelope.[ Frozen_reference { root = reference_root } ]
  in
  if not (Resource_envelope.satisfied checks) then begin
    prerr_endline "preflight refused:";
    List.iter
      (fun d -> prerr_endline (Fractal_diagnostic.render d))
      (Resource_envelope.to_diagnostics checks);
    exit 1
  end;
  match Inventory.scan ~root:reference_root with
  | Error message -> prerr_endline message; exit 1
  | Ok entries ->
      let snapshot_digest = Inventory.snapshot_digest entries in
      (match Blueprint.validate ~resolve:Parity_intent.resolver Parity_intent.blueprint with
      | Error errors ->
          prerr_endline "blueprint invalid:";
          List.iter (fun e -> prerr_endline ("  " ^ Blueprint.describe_error e)) errors;
          exit 1
      | Ok () -> ());
      let all_intents = List.map (fun d -> d.Blueprint.id) Parity_intent.blueprint in
      (* The convergence step: recompute actual from the differential corpus and
         return the satisfied-intent set. Deterministic and idempotent for a
         fixed candidate, so the loop reaches its fixpoint honestly. *)
      let satisfied_now () =
        let nodes = slice_nodes ~root ~normalizer ~snapshot_digest in
        let actual =
          Evidence_rollup.actual_with_families ~catalog:Parity_intent.family_catalog ~nodes
        in
        List.filter_map
          (fun (d : Blueprint.directive) ->
            if actual d.Blueprint.target = d.Blueprint.desired then Some d.Blueprint.id else None)
          Parity_intent.blueprint
      in
      let cached = satisfied_now () in
      let step _ = cached (* pure function of the fixed candidate; recomputed once *) in
      Printf.printf "automatic convergence: declare intent -> reconcile -> iterate to fixpoint\n\n";
      let outcome = Converge.converge ~max_iterations:16 ~all_intents ~step [] in
      Printf.printf "trajectory: %s\n"
        (String.concat " -> "
           (List.map (fun s -> Printf.sprintf "{%s}" (String.concat "," (List.sort compare s)))
              (Converge.trajectory ~max_iterations:16 ~step [])));
      Printf.printf "\n%s\n" (Converge.describe outcome);
      (* Turn the residual drift into the runbook via the rule engine. *)
      (match outcome with
      | Converge.Settled { drift; _ } when drift <> [] ->
          let nodes = slice_nodes ~root ~normalizer ~snapshot_digest in
          let actual =
            Evidence_rollup.actual_with_families ~catalog:Parity_intent.family_catalog ~nodes
          in
          let reconciled = Blueprint.reconcile Parity_intent.blueprint ~actual in
          (match Drift_rules.diagnose reconciled with
          | Ok advice ->
              Printf.printf "\nresidual work (the runbook the loop cannot fabricate -- R10):\n";
              List.iter
                (fun (a : Drift_rules.advice) ->
                  Printf.printf "  %-20s %s: %s\n" a.Drift_rules.action a.Drift_rules.target
                    a.Drift_rules.detail)
                advice
          | Error message -> Printf.printf "  rule gate: %s\n" message)
      | _ -> ());
      (* Full-fractal control sweep (the c3i controller pass, R14): one leg
         per level with a live sensor, unsensed levels named -- no silent
         caps. Read-only over the store; recording stays with the deliberate
         commands. A missing or unreadable store degrades the telemetry legs
         to empty (absence of telemetry is not a violation); no alert grants
         or denies parity credit (R10). *)
      let frontier_counts, history, receipts_revision =
        match
          Evidence_store.open_db
            ~path:(Filename.concat root "state/hermes_harness.sqlite3")
        with
        | Error message ->
            Printf.printf
              "\ncontrol plane: store unavailable (%s) -- telemetry absent, not a violation\n"
              message;
            ([], [], None)
        | Ok store ->
            let evolution = Evidence_store.evolution_history store ~snapshot_digest in
            let history = Evidence_store.parity_history store ~snapshot_digest in
            let revision = Evidence_store.latest_receipt_revision store ~snapshot_digest in
            Evidence_store.close store;
            ( (match evolution with
              | Error message -> Printf.printf "\ncontrol plane: %s\n" message; []
              | Ok rows ->
                  List.map
                    (fun (row : Evidence_store.evolution) ->
                      let s = row.Evidence_store.satisfied in
                      if s = "" then 0 else List.length (String.split_on_char ',' s))
                    rows),
              (match history with Ok h -> h | Error _ -> []),
              match revision with Ok r -> r | Error _ -> None )
      in
      let corpus_size =
        List.length Parity_compare.scenarios
        + List.length Parity_compare.decode_scenarios
        + List.length Parity_compare.session_scenarios
        + List.length Parity_compare.budget_scenarios
        + List.length Parity_compare.path_scenarios
        + List.length Parity_compare.retry_scenarios
        + List.length Parity_compare.route_scenarios
        + List.length Parity_compare.anthropic_scenarios
        + List.length Parity_compare.codex_scenarios
        + List.length Parity_compare.gemini_scenarios
        + List.length Parity_compare.bedrock_scenarios
      in
      let recorded =
        List.length (List.sort_uniq compare (List.map (fun (_, s, _) -> s) history))
      in
      let gospel_available =
        Gospel_check.configured_binary () <> None || Gospel_check.path_binary "gospel" <> None
      in
      let sweep =
        Control_plane.
          { legs =
              [ l0_frontier ~counts:frontier_counts ~total:(List.length all_intents);
                l1_regressions ~history;
                l2_flaps ~history;
                l3_contract_oracle ~available:gospel_available;
                l4_receipt_currency ~receipts_revision ~current:(git_revision root);
                l6_observation_coverage ~recorded ~corpus:corpus_size;
                lx_envelope ~satisfied:true (* the R13 gate above passed *) ];
            unsensed = [ ("L5 trace", "normalizer-version sensor queued") ] }
      in
      let sweep_text = String.concat "\n" (Control_plane.render sweep) in
      Printf.printf "\ncontrol plane (full fractal sweep):\n%s\n" sweep_text;
      (* Mesh telemetry (c3i rule: a zenoh failure never fails the run).
         Published data is observation, never authority -- the store remains
         the only source of parity truth (the two-lattice law). *)
      (match Hermes_zenoh.publish ~key:"hermes/control/sweep/auto_converge" ~payload:sweep_text with
      | Ok () -> print_endline "zenoh: published -> hermes/control/sweep/auto_converge"
      | Error detail -> print_endline ("zenoh: " ^ detail ^ " -- telemetry stays local"));
      ignore
        (Hermes_zenoh.publish ~key:"hermes/control/worst/auto_converge"
           ~payload:(Homeostasis.describe (Control_plane.worst sweep)));
      (* Exit teeth -- a control, not a report: an in-run Anomaly or any P0
         leg stops the line (exit 2, distinct from exit 1 = refused
         configuration). *)
      (match (outcome, Control_plane.worst sweep) with
      | Converge.Anomaly _, _ -> exit 2
      | _, Homeostasis.P0 _ -> exit 2
      | _ -> ())
