let failures = ref []
let outcome = ref (0, 0)
let check name condition = if not condition then failures := name :: !failures

let unique values =
  List.sort_uniq String.compare values |> List.length = List.length values

let () =
  let nodes = Jj_ontology.all in
  check "O1 exact L0-L6/LX ontology denominator"
    (List.map (fun node -> node.Jj_ontology.coordinate.level) nodes
     = [ Jj_ontology.L0; L1; L2; L3; L4; L5; L6; LX ]);
  check "O2 node coordinates and identities are unique and canonical"
    (unique (List.map (fun node -> node.Jj_ontology.coordinate.node) nodes)
     && unique
          (List.map
             (fun node -> node.Jj_ontology.identity.authority_digest)
             nodes)
     && List.for_all
          (fun node ->
             node.Jj_ontology.identity.schema_id <> ""
             && String.length node.Jj_ontology.identity.authority_digest = 64)
          nodes);
  check "O3 every node carries total obligations"
    (List.for_all
       (fun node ->
          node.Jj_ontology.invariants <> []
          && node.inputs <> [] && node.outputs <> [] && node.hazards <> [])
       nodes);
  check "O4 no ontology node claims runtime availability"
    (List.for_all
       (fun node ->
          match node.Jj_ontology.lifecycle with
          | Declared_unavailable | Implemented_unavailable -> true)
       nodes);
  check "O5 ontology digest kills structural mutants"
    (List.for_all
       (fun mutation ->
          Jj_ontology.source_digest
          <> Jj_ontology.For_test.source_digest_with_mutation mutation)
       [ Jj_ontology.For_test.Drop_node; Change_identity; Drop_invariant;
         Claim_available ]);
  let model = Jj_sysml.model in
  check "S1 SysML parts are the exact ontology projection"
    (List.map (fun (part : Jj_sysml.part) -> part.id) model.parts
     = List.map (fun node -> node.Jj_ontology.coordinate.node) nodes);
  check "S2 sparse path has one fewer connections than parts and no dangling end"
    (List.length model.connections + 1 = List.length model.parts
     && Jj_sysml.connection_endpoints_exist model);
  check "S3 every ontology invariant becomes one structural requirement"
    (Jj_sysml.requirement_count model
     = List.fold_left
         (fun count node -> count + List.length node.Jj_ontology.invariants)
         0 nodes);
  check "S4 operation allocation is exact, sparse, and unavailable"
    (Jj_sysml.operation_count model = List.length Jj_operation.all
     && Jj_sysml.operation_denominator_is_exact model
     && List.for_all
          (fun (allocation : Jj_sysml.operation_allocation) ->
             allocation.intent_part = "jj.intent-operation"
             && allocation.effect_part = "jj.effect-attempt"
             && match allocation.lifecycle with
                | Jj_ontology.Declared_unavailable
                | Implemented_unavailable -> true)
          model.operation_allocations);
  check "S5 SysML projection binds exact ontology and operation authorities"
    (model.ontology_digest = Jj_ontology.source_digest
     && model.operation_authority_digest = Jj_operation.source_digest);
  check "S6 SysML digest kills projection mutants"
    (List.for_all
       (fun mutation ->
          Jj_sysml.source_digest
          <> Jj_sysml.For_test.source_digest_with_mutation mutation)
       [ Jj_sysml.For_test.Drop_part; Reverse_connection; Drop_requirement;
         Change_operation ]);
  List.iter (fun name -> Printf.eprintf "FAIL %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  outcome := (11 - failed, failed)
