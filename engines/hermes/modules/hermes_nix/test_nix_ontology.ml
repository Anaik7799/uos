let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let () =
  check "ONT-1 all 8 levels are represented"
    (List.length Nix_ontology.all_nodes = 8);

  check "ONT-2 ontology graph validates without duplicates"
    (Result.is_ok (Nix_ontology.validate_ontology_graph ()));

  check "ONT-3 node lookup by level and name succeeds"
    (match Nix_ontology.find_node Nix_ontology.L0 "nix-substrate-daemon" with
     | Some n -> n.owner = Nix_ontology.Substrate_daemon_owner
     | None -> false);

  check "ONT-4 each node has non-empty invariants and hazards"
    (List.for_all (fun n -> n.Nix_ontology.invariants <> [] && n.hazards <> []) Nix_ontology.all_nodes);

  if !failures <> [] then begin
    List.iter (fun f -> Printf.eprintf "FAIL: %s\n" f) !failures;
    exit 1
  end else
    print_endline "PASS test_nix_ontology"
