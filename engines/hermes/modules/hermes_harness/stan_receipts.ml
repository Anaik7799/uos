(* Reliability annotation over the LIVE parity receipts: the exact Beta-Binomial
   posterior per fractal node, from latest-per-scenario verdicts, with the
   unmeasured nodes disclosed (censoring) rather than denominated. NO AUTHORITY:
   this prints posteriors beside the hard verdicts; it gates nothing. *)

let () =
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else "." in
  let reference_root = Bootstrap.reference_root root in
  match Inventory.scan ~root:reference_root with
  | Error message -> prerr_endline message; exit 1
  | Ok entries -> (
      let snapshot_digest = Inventory.snapshot_digest entries in
      let path = Filename.concat root "state/hermes_harness.sqlite3" in
      match Evidence_store.open_db ~path with
      | Error message -> prerr_endline message; exit 1
      | Ok store ->
          let rows =
            match Evidence_store.parity_results store ~snapshot_digest with
            | Ok rows -> rows
            | Error message -> prerr_endline message; Evidence_store.close store; exit 1
          in
          Evidence_store.close store;
          let table = Receipt_reliability.per_node rows in
          Printf.printf
            "receipt reliability (exact Beta-Binomial, uniform prior; latest verdict per \
             scenario -- pseudo-replication-safe; ADVISORY ONLY)\n\n";
          List.iter
            (fun r -> print_endline ("  " ^ Receipt_reliability.render r))
            table;
          let all_nodes =
            List.map Capability_catalog.node_id Capability_catalog.all
            |> List.sort_uniq compare
          in
          let missing =
            Receipt_reliability.unmeasured ~measured:table ~all_nodes
          in
          Printf.printf
            "\nunmeasured (censored -- absence of evidence, never a denominator): %d of %d \
             capability nodes\n"
            (List.length missing) (List.length all_nodes);
          Printf.printf "\nposteriors annotate; the parity verdicts remain the sole authority\n")
