let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let () =
  check "D1 schema rows preserve the exact auxiliary-role order"
    (List.map Jj_dependency_schema.role Jj_dependency_schema.all
     = Jj_action_kind.auxiliary_roles);
  check "D2 every role has exactly one total owner/carrier declaration"
    (List.for_all Jj_dependency_schema.is_well_formed Jj_dependency_schema.all);
  check "D3 every dependency carrier is bridge-nonserializable"
    (List.for_all
       (fun row -> Jj_dependency_schema.carrier_class row
                   = Jj_dependency_schema.Nonserializable_bridge_carrier)
       Jj_dependency_schema.all);
  check "D4 lookup is exact and rejects an unknown role only by type exclusion"
    (List.for_all
       (fun role ->
          match Jj_dependency_schema.for_role role with
          | Some row -> Jj_dependency_schema.role row = role
          | None -> false)
       Jj_action_kind.auxiliary_roles);
  check "D5 release-bundle observation has its distinct least-authority owner"
    (match Jj_dependency_schema.for_role Jj_action_kind.Observe_release_bundle with
     | Some row ->
         Jj_dependency_schema.owner row = Jj_dependency_schema.Release_owner
     | None -> false);
  List.iter (fun failure -> Printf.printf "FAILED: %s\n" failure) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 5 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_dependency_schema"
      ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_jj_protocol ]);
  exit (Suite_telemetry.exit_code self)
