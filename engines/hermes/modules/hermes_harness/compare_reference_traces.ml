(* Run the L4-L6 differential comparison and record the receipts.

   A deliberate command, not part of verify: it writes parity evidence, and
   evidence that appears as a side effect of a routine command is evidence
   nobody chose to trust. Output is the fractal diagnostic for every divergence
   and a rolled-up family verdict.

   The first run is EXPECTED to show divergences. The candidate reproduces some
   of the reference's request shaping and not all of it; finding exactly which
   is the entire point. A clean sweep on the first run would be more suspicious
   than a mix. *)

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
  let state_directory = Filename.concat root "state" in
  let path = Filename.concat state_directory "hermes_harness.sqlite3" in
  (* Resource-envelope preflight: nothing is consumed that was not checked.
     This is the operation that hit ENOSPC this session; it now declares the
     resources it needs and refuses -- with a named, fractal cause -- before a
     capture writes a temp tree or the store takes a receipt, rather than dying
     mid-write. A shortfall is Environment/Control: it blocks the run, it never
     touches parity credit. *)
  let envelope =
    Resource_envelope.
      [ Frozen_reference { root = reference_root };
        Disk_space { path = root; bytes_needed = 64 * 1024 * 1024; margin = default_margin };
        Temp_space { bytes_needed = 32 * 1024 * 1024; margin = default_margin };
        Writable state_directory ]
  in
  let checks = Resource_envelope.preflight envelope in
  if not (Resource_envelope.satisfied checks) then begin
    Printf.eprintf "preflight refused: %d of %d resources unavailable\n\n"
      (List.length (Resource_envelope.unmet_checks checks))
      (List.length checks);
    List.iter
      (fun diagnostic -> prerr_endline (Fractal_diagnostic.render diagnostic))
      (Resource_envelope.to_diagnostics checks);
    exit 1
  end;
  Printf.printf "preflight: %d resources satisfied\n" (List.length checks);
  match Inventory.scan ~root:reference_root with
  | Error message -> prerr_endline message; exit 1
  | Ok entries ->
      let snapshot_digest = Inventory.snapshot_digest entries in
      let harness_revision = git_revision root in
      let store =
        match Evidence_store.open_db ~path with
        | Ok store -> store
        | Error message -> prerr_endline message; exit 1
      in
      (* Register the snapshot this run measured against, so the read-only
         dashboard can key its KPIs off it -- the compare records receipts
         under [snapshot_digest] but nothing else pinned that digest in
         source_snapshot, so latest_snapshot returned None and the dashboard
         rendered 0/95. Guarded on the current latest so repeated runs do not
         append duplicate rows; a best-effort failure never blocks the
         measurement (the receipts are the load-bearing record). *)
      (match Evidence_store.latest_snapshot store with
      | Ok (Some current) when current = snapshot_digest -> ()
      | _ ->
          ignore
            (Evidence_store.record_snapshot store ~digest:snapshot_digest
               ~entry_count:(List.length entries)));
      Printf.printf "snapshot: %s\nharness:  %s\nnormalization: %s\n\n" snapshot_digest
        harness_revision (Parity_normalizer.describe normalizer);
      let record_failures = ref 0 in
      let report_outcome scenario_id outcome =
        (match outcome with
        | Parity_compare.Compared comparison -> (
            (match Parity_compare.record ~store ~snapshot_digest ~harness_revision
                     ~normalizer comparison with
            | Ok () -> ()
            | Error message ->
                (* Unrecorded evidence is a Control-origin failure: the
                   comparison happened but nothing was stored, so the run must
                   not read as complete. *)
                incr record_failures;
                Printf.printf "  %-22s RECORD FAILED\n%s\n" comparison.scenario_id
                  (Fractal_diagnostic.render
                     (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
                        ~origin:Fractal_diagnostic.Control
                        ~impact:Fractal_diagnostic.Blocks_credit
                        ~node:comparison.node ~subject:comparison.scenario_id
                        ~message:("could not record receipt: " ^ message)
                        ~cause:"the evidence store rejected the receipt"
                        ~fix:"resolve the store conflict; a comparison whose receipt is not stored is not evidence"
                        ())));
            match comparison.diagnostic with
            | None ->
                Printf.printf "  %-22s VERIFIED  ref=%s\n" comparison.scenario_id
                  (String.sub comparison.reference_digest 0 12)
            | Some diagnostic ->
                Printf.printf "  %-22s DIVERGENT\n%s\n" comparison.scenario_id
                  (Fractal_diagnostic.render diagnostic))
        | Parity_compare.Blocked diagnostic ->
            Printf.printf "  %-22s BLOCKED\n%s\n" scenario_id
              (Fractal_diagnostic.render diagnostic));
        outcome
      in
      Printf.printf "-- request shaping --\n";
      let request_outcomes =
        List.map
          (fun scenario_id ->
            report_outcome scenario_id
              (Parity_compare.compare_scenario ~root ~normalizer ~snapshot_digest scenario_id))
          Parity_compare.scenarios
      in
      Printf.printf "\n-- response decoding --\n";
      let decode_outcomes =
        List.map
          (fun (scenario_id, _) ->
            report_outcome scenario_id
              (Parity_compare.compare_decode_scenario ~root ~normalizer ~snapshot_digest
                 scenario_id))
          Parity_compare.decode_scenarios
      in
      Printf.printf "\n-- interrupt control --\n";
      let budget_outcomes =
        List.map
          (fun (scenario_id, _) ->
            report_outcome scenario_id
              (Parity_compare.compare_budget_scenario ~root ~normalizer ~snapshot_digest
                 scenario_id))
          Parity_compare.budget_scenarios
      in
      Printf.printf "\n-- session replay (submit -> decode) --\n";
      let session_outcomes =
        List.map
          (fun (session_id, _, _) ->
            report_outcome session_id
              (Parity_compare.compare_session_scenario ~root ~normalizer ~snapshot_digest
                 session_id))
          Parity_compare.session_scenarios
      in
      Printf.printf "\n-- path & url safety --\n";
      let path_outcomes =
        List.map
          (fun (scenario_id, _) ->
            report_outcome scenario_id
              (Parity_compare.compare_path_scenario ~root ~normalizer ~snapshot_digest
                 scenario_id))
          Parity_compare.path_scenarios
      in
      Printf.printf "\n-- rate & retry --\n";
      let retry_outcomes =
        List.map
          (fun (scenario_id, _) ->
            report_outcome scenario_id
              (Parity_compare.compare_retry_scenario ~root ~normalizer ~snapshot_digest
                 scenario_id))
          Parity_compare.retry_scenarios
      in
      Printf.printf "\n-- route resolution --\n";
      let route_outcomes =
        List.map
          (fun (scenario_id, _) ->
            report_outcome scenario_id
              (Parity_compare.compare_route_scenario ~root ~normalizer ~snapshot_digest
                 scenario_id))
          Parity_compare.route_scenarios
      in
      Printf.printf "\n-- anthropic adapter --\n";
      let anthropic_outcomes =
        List.map
          (fun (scenario_id, _) ->
            report_outcome scenario_id
              (Parity_compare.compare_anthropic_scenario ~root ~normalizer ~snapshot_digest
                 scenario_id))
          Parity_compare.anthropic_scenarios
      in
      Printf.printf "\n-- codex runtime --\n";
      let codex_outcomes =
        List.map
          (fun (scenario_id, _) ->
            report_outcome scenario_id
              (Parity_compare.compare_codex_scenario ~root ~normalizer ~snapshot_digest scenario_id))
          Parity_compare.codex_scenarios
      in
      Printf.printf "\n-- gemini adapter --\n";
      let gemini_outcomes =
        List.map
          (fun (scenario_id, _) ->
            report_outcome scenario_id
              (Parity_compare.compare_gemini_scenario ~root ~normalizer ~snapshot_digest scenario_id))
          Parity_compare.gemini_scenarios
      in
      Printf.printf "\n-- cloud vendor adapters (bedrock) --\n";
      let bedrock_outcomes =
        List.map
          (fun (scenario_id, _) ->
            report_outcome scenario_id
              (Parity_compare.compare_bedrock_scenario ~root ~normalizer ~snapshot_digest scenario_id))
          Parity_compare.bedrock_scenarios
      in
      Printf.printf "\n-- message hygiene --\n";
      let hygiene_outcomes =
        List.map
          (fun (scenario_id, _) ->
            report_outcome scenario_id
              (Parity_compare.compare_hygiene_scenario ~root ~normalizer ~snapshot_digest
                 scenario_id))
          Parity_compare.hygiene_scenarios
      in
      Printf.printf "\n-- conversation loop (send path) --\n";
      let loop_outcomes =
        List.map
          (fun (scenario_id, _) ->
            report_outcome scenario_id
              (Parity_compare.compare_loop_scenario ~root ~normalizer ~snapshot_digest
                 scenario_id))
          Parity_compare.loop_scenarios
      in
      let slice_family title scenarios =
        Printf.printf "\n-- %s --\n" title;
        List.map
          (fun (scenario_id, _) ->
            report_outcome scenario_id
              (Parity_compare.compare_slice_scenario ~scenarios ~root ~normalizer
                 ~snapshot_digest scenario_id))
          scenarios
      in
      let prompt_outcomes =
        slice_family "prompt assembly" Parity_compare.prompt_scenarios
      in
      let context_outcomes =
        slice_family "context engine (references)" Parity_compare.context_scenarios
      in
      let compress_outcomes =
        slice_family "context compression (markers)" Parity_compare.compress_scenarios
      in
      let finalize_outcomes =
        slice_family "turn finalization" Parity_compare.finalize_scenarios
      in
      let redact_outcomes =
        slice_family "redaction" Parity_compare.redact_scenarios
      in
      let tool_outcomes =
        slice_family "tool execution (units)" Parity_compare.tool_scenarios
      in
      let context_file_outcomes =
        slice_family "context files (units)" Parity_compare.context_file_scenarios
      in
      let memory_outcomes =
        slice_family "memory (units)" Parity_compare.memory_scenarios
      in
      let skill_outcomes =
        slice_family "skills (units)" Parity_compare.skill_scenarios
      in
      let cli_outcomes =
        slice_family "interactive_cli (units)" Parity_compare.cli_scenarios
      in
      let mcp_outcomes =
        slice_family "mcp (units)" Parity_compare.mcp_scenarios
      in
      let subagent_outcomes =
        slice_family "subagents (units)" Parity_compare.subagent_scenarios
      in
      Evidence_store.close store;
      let outcomes =
        request_outcomes @ decode_outcomes @ budget_outcomes @ session_outcomes @ path_outcomes
        @ retry_outcomes @ route_outcomes @ anthropic_outcomes @ codex_outcomes @ gemini_outcomes
        @ bedrock_outcomes @ hygiene_outcomes @ loop_outcomes
        @ prompt_outcomes @ context_outcomes @ compress_outcomes @ finalize_outcomes
        @ redact_outcomes @ tool_outcomes @ context_file_outcomes @ memory_outcomes @ skill_outcomes
        @ cli_outcomes @ mcp_outcomes @ subagent_outcomes
      in
      let report = Parity_compare.roll_up outcomes in
      Printf.printf
        "\nrequest shaping: %s\nresponse decoding: %s\ninterrupt control: %s\nsession replay: %s\npath & url safety: %s\nrate & retry: %s\nroute resolution: %s\nanthropic adapter: %s\ncodex runtime: %s\ngemini adapter: %s\ncloud vendor adapters: %s\nmessage hygiene: %s\nconversation loop: %s\nprompt assembly: %s\ncontext engine: %s\ncontext compression: %s\nturn finalization: %s\nredaction: %s\ntool execution: %s\ncontext files: %s\nmemory: %s\nskills: %s\ninteractive_cli: %s\nmcp: %s\nsubagents: %s\noverall: %s\n"
        (Parity_algebra.render_report (Parity_compare.roll_up request_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up decode_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up budget_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up session_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up path_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up retry_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up route_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up anthropic_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up codex_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up gemini_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up bedrock_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up hygiene_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up loop_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up prompt_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up context_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up compress_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up finalize_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up redact_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up tool_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up context_file_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up memory_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up skill_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up cli_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up mcp_outcomes))
        (Parity_algebra.render_report (Parity_compare.roll_up subagent_outcomes))
        (Parity_algebra.render_report report);
      (* A divergence is a successful measurement, so it does not fail the run --
         the verdict carries the parity result. But a RECORD failure means
         evidence was lost, which is a control failure and must fail loudly, or
         a future session trusts a receipt that was never written. *)
      if !record_failures > 0 then (
        Printf.eprintf "\n%d receipt(s) failed to record; evidence is incomplete\n"
          !record_failures;
        exit 1);
      (* Full-fractal control sweep -- read-only over the store just written;
         alerts observe/refuse/advise, never touching the verdicts above (R10).
         Exit 2 on P0: a REGRESSION (previously-passing scenario now failing)
         stops the line even though the divergence itself was recorded as a
         successful measurement; a first-time divergence does not trip this. *)
      (* The write session above is closed; the sweep reads through its own
         fresh handle -- the deliberate act and the observation stay separate
         sessions, and a failed reopen degrades the telemetry legs to empty
         (absence is not a violation) instead of crashing the report. *)
      let history, frontier_counts, receipts_revision =
        match Evidence_store.open_db ~path with
        | Error message ->
            Printf.printf "\ncontrol plane: store unavailable (%s)\n" message;
            ([], [], None)
        | Ok sweep_store ->
            let history = Evidence_store.parity_history sweep_store ~snapshot_digest in
            let evolution = Evidence_store.evolution_history sweep_store ~snapshot_digest in
            let revision =
              Evidence_store.latest_receipt_revision sweep_store ~snapshot_digest
            in
            Evidence_store.close sweep_store;
            ( (match history with
              | Ok rows -> rows
              | Error message -> Printf.printf "\ncontrol plane: %s\n" message; []),
              (match evolution with
              | Error _ -> []
              | Ok rows ->
                  List.map
                    (fun (row : Evidence_store.evolution) ->
                      let s = row.Evidence_store.satisfied in
                      if s = "" then 0 else List.length (String.split_on_char ',' s))
                    rows),
              match revision with Ok revision -> revision | Error _ -> None )
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
              [ l0_frontier ~counts:frontier_counts
                  ~total:(List.length Parity_intent.blueprint);
                l1_regressions ~history;
                l2_flaps ~history;
                l3_contract_oracle ~available:gospel_available;
                l4_receipt_currency ~receipts_revision ~current:harness_revision;
                l6_observation_coverage ~recorded ~corpus:(List.length outcomes);
                lx_envelope ~satisfied:true (* the R13 gate at the top passed *) ];
            unsensed = [ ("L5 trace", "normalizer-version sensor queued") ] }
      in
      let sweep_text = String.concat "\n" (Control_plane.render sweep) in
      Printf.printf "\ncontrol plane (full fractal sweep):\n%s\n" sweep_text;
      (* The parity ledger: each scenario's newest verdict scored against its
         OWN receipt trajectory (Jeffreys prior over the flip rate), movers
         ranked in bits, steady mass as one number. Rendered in the volatile
         tail so the standing sections above stay prefix-stable. *)
      Printf.printf "\n%s" (Parity_ledger.render (Parity_ledger.assess history));
      (* Mesh telemetry: observation only, best-effort (c3i rule) -- receipts
         were already recorded above; the mesh gets copies, never the record. *)
      (match Hermes_zenoh.publish ~key:"hermes/control/sweep/compare" ~payload:sweep_text with
      | Ok () -> print_endline "zenoh: published -> hermes/control/sweep/compare"
      | Error detail -> print_endline ("zenoh: " ^ detail ^ " -- telemetry stays local"));
      ignore
        (Hermes_zenoh.publish ~key:"hermes/control/worst/compare"
           ~payload:(Homeostasis.describe (Control_plane.worst sweep)));
      (match Control_plane.worst sweep with
      | Homeostasis.P0 _ -> exit 2
      | _ -> ())
