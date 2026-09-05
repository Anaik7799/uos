let () =
  (* Every contract names a real capability slice and a present interface. *)
  List.iter
    (fun (contract : Contract_catalog.contract) ->
      if Capability_catalog.find contract.capability_key = None then
        failwith (contract.id ^ ": unknown capability " ^ contract.capability_key);
      if not (Sys.file_exists contract.interface) then
        failwith (contract.id ^ ": missing interface " ^ contract.interface);
      if String.trim contract.law = "" then failwith (contract.id ^ ": empty law"))
    Contract_catalog.all;
  let ids = List.map (fun (c : Contract_catalog.contract) -> c.id) Contract_catalog.all in
  assert (List.length (List.sort_uniq compare ids) = List.length ids);

  (* An unavailable or rejected verdict never counts as a checked contract. *)
  let path = Filename.temp_file "hermes-contract" ".sqlite3" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      match Evidence_store.open_db ~path with
      | Error message -> failwith message
      | Ok store ->
          let snapshot_digest = String.make 64 'a' in
          let node : Evidence_store.fractal_node =
            { snapshot_digest; id = "hermes"; level = 0; parent_id = None;
              semantic_key = "hermes"; label = "Hermes"; required = true;
              status_policy = "all-children" }
          in
          assert (Evidence_store.record_fractal_nodes store [ node ] = Ok ());
          let contract : Evidence_store.contract =
            { snapshot_digest; id = "demo.contract"; node_id = "hermes";
              interface_path = "modules/hermes_harness/turn_budget.mli"; law = "DEMO-LAW" }
          in
          assert (Evidence_store.record_contracts store [ contract ] = Ok ());
          (* Declarations are immutable under replay. *)
          assert (Evidence_store.record_contracts store [ contract ] = Ok ());
          assert
            (match Evidence_store.record_contracts store [ { contract with law = "OTHER" } ] with
            | Error _ -> true | Ok () -> false);
          let receipt : Evidence_store.contract_receipt =
            { snapshot_digest; contract_id = contract.id; harness_revision = "rev1";
              verifier = "gospel-unavailable"; interface_digest = String.make 64 'b';
              verdict = "unavailable" }
          in
          assert (Evidence_store.record_contract_receipts store [ receipt ] = Ok ());
          assert
            (Evidence_store.checked_contracts store ~snapshot_digest ~harness_revision:"rev1"
             = Ok []);
          (* A real check at the same revision is a distinct verifier, not a
             conflicting overwrite. *)
          assert
            (Evidence_store.record_contract_receipts store
               [ { receipt with verifier = "gospel"; verdict = "checked" } ]
             = Ok ());
          assert
            (Evidence_store.checked_contracts store ~snapshot_digest ~harness_revision:"rev1"
             = Ok [ contract.id ]);
          (* A divergent verdict under the same key is still rejected. *)
          assert
            (match
               Evidence_store.record_contract_receipts store
                 [ { receipt with verifier = "gospel"; verdict = "rejected" } ]
             with
            | Error _ -> true | Ok () -> false);
          assert
            (match
               Evidence_store.record_contract_receipts store
                 [ { receipt with verdict = "bogus" } ]
             with
            | Error _ -> true | Ok () -> false);
          Evidence_store.close store);
  Printf.printf "contracts: %d\n" (List.length Contract_catalog.all)

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_contract_catalog" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_contract_catalog ]);
  exit (Suite_telemetry.exit_code self)
