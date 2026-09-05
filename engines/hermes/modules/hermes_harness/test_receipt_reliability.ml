(* The exact conjugate math at its boundaries, the honest bounded band, the
   per-node grouping over latest-per-scenario rows (pseudo-replication-safe by
   construction), and the censoring disclosure. NO-AUTHORITY is structural: the
   module exposes no verdicts, only posteriors. *)

let close a b = Float.abs (a -. b) < 1e-9

let () =
  let open Receipt_reliability in
  (* Exact conjugate update: Beta(1,1) + 3/4 -> Beta(4,2). *)
  let p = posterior ~a:1.0 ~b:1.0 ~n:4 ~k:3 in
  assert (close p.alpha 4.0 && close p.beta 2.0);
  assert (close (mean p) (4.0 /. 6.0));
  (* Variance of Beta(4,2): ab / (s^2 (s+1)) = 8 / (36*7). *)
  assert (close (variance p) (8.0 /. 252.0));

  (* The moment band is clamped to [0,1] -- honest at the extremes. *)
  let all_pass = posterior ~a:1.0 ~b:1.0 ~n:17 ~k:17 in
  let low, high = cred95 all_pass in
  assert (low >= 0.0 && high <= 1.0 && low < high);
  let all_fail = posterior ~a:1.0 ~b:1.0 ~n:5 ~k:0 in
  let low_f, high_f = cred95 all_fail in
  assert (low_f >= 0.0 && high_f <= 1.0);

  (* Zero evidence: the posterior IS the prior; the band is wide, not confident. *)
  let none = posterior ~a:1.0 ~b:1.0 ~n:0 ~k:0 in
  assert (close (mean none) 0.5);
  let low_n, high_n = cred95 none in
  assert (high_n -. low_n > 0.5);

  (* per_node groups latest-per-scenario rows by fractal node with the uniform
     prior. 2 pass + 1 fail under one capability; 1 pass under another. *)
  let rows =
    [ ("model_routing.provider_transports.request_shaping", true);
      ("model_routing.provider_transports.session_replay", true);
      ("model_routing.provider_transports.request_shaping", false);
      ("tool_execution.path_and_url_safety", true) ]
  in
  let table = per_node rows in
  let find node = List.find (fun r -> r.node = node) table in
  let transports = find "hermes.model_routing.provider_transports" in
  assert (transports.scenarios = 3 && transports.passing = 2);
  assert (close transports.post.alpha 3.0 && close transports.post.beta 2.0);
  let paths = find "hermes.tool_execution.path_and_url_safety" in
  assert (paths.scenarios = 1 && paths.passing = 1);

  (* Censoring: a node with no receipts is disclosed, never in the table. *)
  let missing =
    unmeasured ~measured:table
      ~all_nodes:
        [ "hermes.model_routing.provider_transports";
          "hermes.tool_execution.path_and_url_safety"; "hermes.mcp.mcp_client" ]
  in
  assert (missing = [ "hermes.mcp.mcp_client" ]);
  assert (not (List.exists (fun r -> r.node = "hermes.mcp.mcp_client") table));

  assert (String.length (render transports) > 0);
  print_endline "receipt_reliability: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_receipt_reliability" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_receipt_reliability ]);
  exit (Suite_telemetry.exit_code self)
