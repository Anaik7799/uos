(* Determinacy gate over the candidate corpus (zigvm GATE-DETERMINACY): replay
   each candidate producer twice and byte-compare the normalized renders. The
   candidate is pure, so every producer must be Stable; any variance exits
   non-zero with a fractal diagnostic, because a non-reproducible apparatus
   proves nothing about parity. Reuses the Parity_compare producers and the
   Determinism_verifier. *)

let () =
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else "." in
  let normalizer = Parity_normalizer.default in
  let reference_root = Bootstrap.reference_root root in
  let snapshot =
    match Inventory.scan ~root:reference_root with
    | Ok entries -> Inventory.snapshot_digest entries
    | Error message -> prerr_endline message; exit 1
  in
  let unstable = ref 0 and checked = ref 0 in
  let one ~scenario_id ~node producer =
    incr checked;
    match Determinism_verifier.check ~normalizer producer with
    | Determinism_verifier.Stable digest ->
        Printf.printf "  %-22s STABLE  %s\n" scenario_id (String.sub digest 0 12)
    | Unstable _ as verdict ->
        incr unstable;
        (match Determinism_verifier.to_diagnostic ~scenario_id ~node verdict with
        | Some diagnostic ->
            Printf.printf "  %-22s UNSTABLE\n%s\n" scenario_id
              (Fractal_diagnostic.render diagnostic)
        | None -> ())
  in
  let default = function Some value -> value | None -> `Null in
  Printf.printf "determinism gate: replay twice, byte-identical\n\n-- response decoding --\n";
  List.iter
    (fun (id, response) ->
      one ~scenario_id:id ~node:(Parity_compare.node_of id) (fun () ->
          default (Parity_compare.candidate_decode response)))
    Parity_compare.decode_scenarios;
  Printf.printf "\n-- interrupt control --\n";
  List.iter
    (fun (id, params) ->
      one ~scenario_id:id ~node:(Parity_compare.node_of id) (fun () ->
          default (Parity_compare.candidate_budget params)))
    Parity_compare.budget_scenarios;
  Printf.printf "\n-- session replay --\n";
  List.iter
    (fun (session_id, _, _) ->
      match Session_fixture.load ~root ~normalizer session_id ~snapshot_digest:snapshot with
      | Ok session ->
          one ~scenario_id:session_id ~node:(Parity_compare.node_of session_id) (fun () ->
              default (Parity_compare.candidate_session session))
      | Error failure ->
          Printf.printf "  %-22s (skipped: %s)\n" session_id (Session_fixture.describe failure))
    Parity_compare.session_scenarios;
  Printf.printf "\nchecked: %d   unstable: %d\n" !checked !unstable;
  if !unstable > 0 then exit 1
