let () =
  let open Evolution_model in
  let initial = create ~snapshot_digest:"S" ~node_id:"hermes.agent.turn" in
  let event id target = { id; snapshot_digest = "S"; target } in
  (* BDD: Given a cataloged feature, when all required evidence phases arrive,
     then it becomes accepted. *)
  let accepted =
    replay initial
      [ event "spec" Specified; event "impl" Implemented;
        event "scenario" Scenario_tested; event "trace" Trace_matched;
        event "proof" Evidence_accepted ]
  in
  assert (accepted = Ok { initial with phase = Evidence_accepted;
                                      applied = [ "spec"; "impl"; "scenario"; "trace"; "proof" ] });
  let accepted = match accepted with Ok state -> state | Error _ -> assert false in
  (* TDD law: duplicate delivery is idempotent, not a second transition. *)
  assert (replay initial [ event "spec" Specified; event "spec" Specified ]
          = Ok { initial with phase = Specified; applied = [ "spec" ] });
  (* Chaos: an out-of-order receipt and stale snapshot both fail closed. *)
  assert (apply initial (event "proof" Evidence_accepted) = Error Invalid_transition);
  assert (apply initial { id = "wrong"; snapshot_digest = "other"; target = Specified }
          = Error Snapshot_mismatch);
  (* Evolution: divergence is explicit; repair returns to implementation. *)
  let diverged = apply accepted (event "diff" Diverged) in
  assert (match diverged with Ok state -> state.phase = Diverged | Error _ -> false);
  assert (match diverged with
          | Ok state -> apply state (event "repair" Implemented) = Ok { state with phase = Implemented; applied = state.applied @ [ "repair" ] }
          | Error _ -> false)

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_evolution_model" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_evolution_model ]);
  exit (Suite_telemetry.exit_code self)
