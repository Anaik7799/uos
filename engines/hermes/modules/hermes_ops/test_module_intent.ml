let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else (incr failed; Printf.printf "FAILED: %s\n" name)

let all_surfaces =
  [ Ops_capability.Ocaml_api; Ops_capability.Cli;
    Ops_capability.Mcp; Ops_capability.Zenoh ]

let () =
  check "M1 every live Dune-owning directory has one semantic interface"
    (List.length Module_intent.all = 39
     && List.map (fun (item : Module_intent.t) -> item.owner_directory) Module_intent.all
        = Module_intent.observed_dune_directories ~root:"."
     && Module_intent.validate ~root:"." = []);
  check "M2 the semantic ownership partition covers every Stanza witness exactly once"
    (let owned = List.concat_map (fun (item : Module_intent.t) -> item.libraries) Module_intent.all in
     List.length owned = List.length Stanza.all
     && List.length owned = List.length (List.sort_uniq Stanza.compare owned));
  check "M3 every interface declares all four surfaces"
    (List.for_all
       (fun (item : Module_intent.t) ->
         List.map fst item.surfaces |> List.sort_uniq compare
         = List.sort_uniq compare all_surfaces)
       Module_intent.all);
  check "M4 FPP applicability is non-vacuous and explicit"
    (List.exists
       (fun (item : Module_intent.t) ->
         match item.fpp with Module_intent.Fpp_components _ -> true | _ -> false)
       Module_intent.all
     && List.for_all
          (fun (item : Module_intent.t) ->
            match item.fpp with
            | Module_intent.Fpp_components mappings ->
                mappings <> [] && List.for_all (fun (_, components) -> components <> []) mappings
            | Module_intent.Fpp_not_applicable reason -> String.length (String.trim reason) >= 20)
          Module_intent.all);
  check "M5 effects never receive direct-read mediation"
    (List.for_all
       (fun (item : Module_intent.t) ->
         match item.effect_posture, item.mediation with
         | (Module_intent.Guarded_write | External_effect), Module_intent.Direct_read -> false
         | _ -> true)
       Module_intent.all);
  let known_config_ids =
    List.map (fun (item : Ops_config.element) -> item.key) Ops_config.elements
  in
  check "M6 every configuration reference resolves to Ops_config.elements"
    (Module_intent.validate_configuration_references
       ~known_ids:known_config_ids Module_intent.all = []);
  check "M6a Jujutsu owns the exact nine declarative configuration identities"
    (match
       List.find_opt
         (fun (item : Module_intent.t) ->
           item.owner_directory = "modules/hermes_vcs")
         Module_intent.all
     with
     | None -> false
     | Some item ->
         item.configuration_ids =
           [ "JUJUTSU_RELEASE_ID"; "JUJUTSU_CONFIG_ID";
             "JUJUTSU_OPERATOR_PUBLIC_KEY_ID";
             "JUJUTSU_RESOURCE_BUDGET_PROFILE";
             "JUJUTSU_SOURCE_CARRIER_POLICY"; "JUJUTSU_APPROVAL_POLICY";
             "JUJUTSU_WRITER_LEASE_POLICY"; "JUJUTSU_CREDENTIAL_POLICY";
             "JUJUTSU_COMPLETION_RECONCILE_ATTEMPT_LIMIT" ]);
  List.iter
    (fun (name, mutation) ->
      check ("NEGATIVE CONTROL: " ^ name)
        (Module_intent.For_test.validate_interfaces ~root:"."
           (Module_intent.For_test.mutate mutation) <> []))
    [ ("missing owner", Module_intent.For_test.Drop_first);
      ("duplicate library", Duplicate_first_library);
      ("empty purpose", Erase_first_purpose);
      ("direct external effect", Force_direct_external_effect);
      ("universal FPP inapplicability", Make_all_fpp_inapplicable);
      ("unknown capability", Add_unknown_capability) ];
  check "NEGATIVE CONTROL: unknown configuration"
    (Module_intent.For_test.validate_configuration_references
       ~known_ids:known_config_ids
       (Module_intent.For_test.mutate Add_unknown_configuration) <> []);
  check "M7 ontology atlas and algebra projections are nonempty"
    (match Module_intent_docs.surfaces () with
     | [ (_, ontology); (_, atlas); (_, algebra) ] ->
         String.length ontology > 5_000
         && String.length atlas > 20_000
         && String.length algebra > 1_000
     | _ -> false);
  Printf.printf "module_intent: %d passed, %d failed\n" !passed !failed;
  let self = Suite_telemetry.observe ~suite:"test_module_intent"
      ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability ]);
  exit (Suite_telemetry.exit_code self)
