(* The live-actual roll-up: contracts map to fractal nodes, latest scenario
   verdicts roll up per node in the parity lattice, and the end-to-end read from
   a real (temp) store honours append-only supersession -- a scenario re-verified
   later wins, without erasing the old receipt. *)

let temp_store () =
  let path = Filename.temp_file "rollup-" ".sqlite3" in
  Sys.remove path;
  match Evidence_store.open_db ~path with
  | Ok store -> (store, path)
  | Error message -> failwith message

let () =
  let open Evidence_rollup in
  (* Contract -> node mapping takes the first two dotted components. *)
  assert (node_of_contract "model_routing.provider_transports.request_shaping"
          = "hermes.model_routing.provider_transports");
  assert (node_of_contract "agent_loop.interrupt_control" = "hermes.agent_loop.interrupt_control");

  (* Roll-up: one failing scenario makes the node Divergent; all-pass is
     Verified; grouping is per node. *)
  let rows =
    [ ("model_routing.provider_transports.request_shaping", true);
      ("model_routing.provider_transports.session_replay", true);
      ("agent_loop.interrupt_control", true);
      ("agent_loop.interrupt_control", false) ]
  in
  let nodes = per_node rows in
  let verdict node = List.assoc node nodes in
  assert (verdict "hermes.model_routing.provider_transports" = Parity_algebra.Verified);
  assert (verdict "hermes.agent_loop.interrupt_control" = Parity_algebra.Divergent);

  (* actual_of: an unknown node is Unmapped, never a pass. *)
  let actual = actual_of nodes in
  assert (actual "hermes.model_routing.provider_transports" = Parity_algebra.Verified);
  assert (actual "hermes.nope.nothing" = Parity_algebra.Unmapped);

  (* End-to-end against a real store: record a scenario verified at an old
     revision as FAILED, then re-verified at a new revision as PASSED -- the
     latest wins (supersession without erasure). *)
  let store, path = temp_store () in
  let snapshot = "feedfacefeedface" in
  let scenario : Evidence_store.scenario =
    { snapshot_digest = snapshot; id = "s1"; feature_id = "model_routing";
      contract_id = "model_routing.provider_transports.request_shaping";
      fixture_digest = "f"; reference_digest = "r" }
  in
  (match Evidence_store.record_scenario store scenario with
  | Ok () -> ()
  | Error m -> failwith m);
  let record_pair_and_verdict ~trace_id ~passed =
    let trace : Evidence_store.paired_trace =
      { snapshot_digest = snapshot; scenario_id = "s1"; trace_id;
        reference_trace = "ref"; candidate_trace = (if passed then "ref" else "cand");
        normalization_version = "v1" }
    in
    (match Evidence_store.record_paired_trace store trace with
    | Ok () -> ()
    | Error m -> failwith m);
    let verification : Evidence_store.verification =
      { snapshot_digest = snapshot; scenario_id = "s1"; trace_id;
        verifier = "parity-compare-v1"; harness_revision = trace_id;
        check = "normalized-trace-equal"; passed; evidence_digest = "d" }
    in
    match Evidence_store.record_verification store verification with
    | Ok () -> ()
    | Error m -> failwith m
  in
  record_pair_and_verdict ~trace_id:"shaping@rev1" ~passed:false;
  record_pair_and_verdict ~trace_id:"shaping@rev2" ~passed:true;
  (match live store ~snapshot_digest:snapshot with
  | Ok actual ->
      assert (actual "hermes.model_routing.provider_transports" = Parity_algebra.Verified);
      assert (actual "hermes.unrelated.node" = Parity_algebra.Unmapped)
  | Error m -> failwith m);
  (* Family-level evidence: a family is Verified ONLY when every slice is;
     an uncovered slice counts Unmapped (the vacuous-truth guard at family
     scale); a Divergent slice absorbs; the product root rolls over families. *)
  let catalog =
    [ ("model_routing", [ "hermes.model_routing.a"; "hermes.model_routing.b" ]);
      ("agent_loop", [ "hermes.agent_loop.c" ]);
      ("mcp", [ "hermes.mcp.d" ]) ]
  in
  let nodes =
    [ ("hermes.model_routing.a", Parity_algebra.Verified);
      ("hermes.model_routing.b", Parity_algebra.Verified);
      ("hermes.agent_loop.c", Parity_algebra.Divergent) ]
  in
  let families = family_verdicts ~catalog ~nodes in
  assert (List.assoc "hermes.model_routing" families = Parity_algebra.Verified);
  assert (List.assoc "hermes.agent_loop" families = Parity_algebra.Divergent);
  assert (List.assoc "hermes.mcp" families = Parity_algebra.Unmapped);
  (* the product absorbs the worst family verdict *)
  assert (List.assoc "hermes" families = Parity_algebra.Divergent);
  (* a family with one covered and one uncovered slice is NOT verified *)
  let partial =
    family_verdicts ~catalog:[ ("f", [ "hermes.f.x"; "hermes.f.y" ]) ]
      ~nodes:[ ("hermes.f.x", Parity_algebra.Verified) ]
  in
  assert (List.assoc "hermes.f" partial = Parity_algebra.Unmapped);
  (* the full-fractal lookup resolves all three levels, else Unmapped *)
  let actual = actual_with_families ~catalog ~nodes in
  assert (actual "hermes.model_routing.a" = Parity_algebra.Verified);
  assert (actual "hermes.model_routing" = Parity_algebra.Verified);
  assert (actual "hermes" = Parity_algebra.Divergent);
  assert (actual "hermes.nope" = Parity_algebra.Unmapped);

  (* The ruliad evolution trajectory: append-only rows in insertion order;
     identical replay is a no-op; a divergent payload for the same key is
     rejected (the standard immutability guard). *)
  let evolution ~revision ~satisfied ~orders : Evidence_store.evolution =
    { snapshot_digest = snapshot; harness_revision = revision; satisfied;
      remaining_orders = orders; state_count = orders * 2; confluent = true;
      folded_verdict = "divergent" }
  in
  (match Evidence_store.record_evolution store (evolution ~revision:"r1" ~satisfied:"" ~orders:30) with
  | Ok () -> () | Error m -> failwith m);
  (match Evidence_store.record_evolution store
           (evolution ~revision:"r2" ~satisfied:"paths,transports" ~orders:4) with
  | Ok () -> () | Error m -> failwith m);
  (* identical replay: no-op *)
  (match Evidence_store.record_evolution store (evolution ~revision:"r1" ~satisfied:"" ~orders:30) with
  | Ok () -> () | Error m -> failwith ("identical replay must be a no-op: " ^ m));
  (* divergent replay: rejected *)
  (match Evidence_store.record_evolution store (evolution ~revision:"r1" ~satisfied:"" ~orders:31) with
  | Error _ -> ()
  | Ok () -> failwith "a divergent evolution replay must be rejected");
  (match Evidence_store.evolution_history store ~snapshot_digest:snapshot with
  | Ok [ first; second ] ->
      assert (first.Evidence_store.harness_revision = "r1" && first.Evidence_store.remaining_orders = 30);
      assert (second.Evidence_store.harness_revision = "r2"
              && second.Evidence_store.satisfied = "paths,transports")
  | Ok rows -> failwith (Printf.sprintf "expected 2 evolution rows, got %d" (List.length rows))
  | Error m -> failwith m);

  Evidence_store.close store;
  Sys.remove path;
  print_endline "evidence_rollup: ok"

(* Append-only completeness for the control plane's history reader:
   parity_history returns EVERY receipt chronologically (old pass, then new
   fail), while parity_results keeps only the latest -- supersession preserves
   exactly the trajectory the regression/flap sensors read; and the regression
   sensor trips on it end-to-end (meta-falsification: real store rows fire the
   P0). *)
let () =
  let store, path = temp_store () in
  let snapshot = "cafef00dcafef00d" in
  let scenario : Evidence_store.scenario =
    { snapshot_digest = snapshot; id = "h1"; feature_id = "model_routing";
      contract_id = "model_routing.provider_transports.request_shaping";
      fixture_digest = "f"; reference_digest = "r" }
  in
  (match Evidence_store.record_scenario store scenario with
  | Ok () -> ()
  | Error m -> failwith m);
  let record ~trace_id ~passed =
    let trace : Evidence_store.paired_trace =
      { snapshot_digest = snapshot; scenario_id = "h1"; trace_id;
        reference_trace = "ref"; candidate_trace = (if passed then "ref" else "cand");
        normalization_version = "v1" }
    in
    (match Evidence_store.record_paired_trace store trace with
    | Ok () -> ()
    | Error m -> failwith m);
    let verification : Evidence_store.verification =
      { snapshot_digest = snapshot; scenario_id = "h1"; trace_id;
        verifier = "parity-compare-v1"; harness_revision = trace_id;
        check = "normalized-trace-equal"; passed; evidence_digest = "d" }
    in
    match Evidence_store.record_verification store verification with
    | Ok () -> ()
    | Error m -> failwith m
  in
  record ~trace_id:"rev-old" ~passed:true;
  record ~trace_id:"rev-new" ~passed:false;
  (match Evidence_store.parity_history store ~snapshot_digest:snapshot with
  | Error m -> failwith m
  | Ok rows ->
      assert (
        rows
        = [ ("model_routing.provider_transports.request_shaping", "h1", true);
            ("model_routing.provider_transports.request_shaping", "h1", false) ]));
  (match Evidence_store.latest_receipt_revision store ~snapshot_digest:snapshot with
  | Error m -> failwith m
  | Ok revision -> assert (revision = Some "rev-new"));
  (match Evidence_store.parity_history store ~snapshot_digest:snapshot with
  | Error m -> failwith m
  | Ok rows ->
      let leg = Control_plane.l1_regressions ~history:rows in
      assert (
        match leg.Control_plane.alert with Homeostasis.P0 _ -> true | _ -> false));
  Evidence_store.close store;
  Sys.remove path;
  print_endline "parity_history: append-only trajectory law ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_evidence_rollup" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_evidence_rollup ]);
  exit (Suite_telemetry.exit_code self)
