let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin incr failed; Printf.printf "FAILED: %s\n" name end

let () =
  let open Run_jj_authority in
  let expected_constituents =
    [ "jj-source-authority"; "run-topology"; "run-fpp-authority";
      "run-mbse"; "run-formal-relation"; "module-intent";
      "ops-config-declaration"; "run-root-bootstrap";
      "dependability-filesystem-protocol";
      "dependability-clock-protocol";
      "dependability-process-protocol";
      "dependability-approval-protocol";
      "dependability-writer-lease-protocol"; "jj-target-protocol";
      "jj-dependency-schema"; "run-dependency-authority";
      "run-swarm-preparation"; "jj-runtime-manifest-schema";
      "jj-runtime-current-protocol"; "run-jj-runtime-registry";
      "jj-recovery-transition-port-protocol";
      "jj-completion-store-protocol" ]
  in
  check "JA1 source constituent denominator is exact and ordered"
    (List.map constituent_id constituents = expected_constituents
     && List.map constituent_kind_id constituent_kinds
        = expected_constituents
     && constituent_count = 22);
  check "JA2 every constituent carries a real lowercase SHA-256 source digest"
    (List.for_all
       (fun constituent ->
         let value = constituent_digest constituent in
         String.length value = 64
         && String.for_all
              (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
              value)
       constituents);
  let first_digest = source_digest () in
  let replay_digest = source_digest () in
  check "JA3 composition is deterministic exact and replay-stable"
    (match first_digest, replay_digest with
     | Ok first, Ok replay ->
         String.length first = 64 && first = replay
     | Error _, _ | _, Error _ -> false);
  check "JA4 dropping any one constituent is a real denominator refusal"
    (List.for_all
       (fun kind ->
         For_test.mutation_refuses (For_test.Drop_constituent kind))
       constituent_kinds);
  check "JA5 duplicate reorder and digest mismatch mutants refuse"
    (List.for_all For_test.mutation_refuses
       [ For_test.Reorder_constituents; For_test.Duplicate_constituent;
         For_test.Mismatch_constituent_digest ]);
  check "JA6 forbidden reverse dependencies are source-bound and refuse"
    (List.for_all For_test.mutation_refuses
       [ For_test.Add_bridge_dependency;
         For_test.Add_operator_dependency;
         For_test.Add_concrete_target_dependency;
         For_test.Add_aggregate_ops_dependency ]);
  check "JA7 currentness and no-substitution laws are mutation-bound"
    (List.for_all For_test.mutation_refuses
       [ For_test.Forge_current_receipt;
         For_test.Drop_runtime_manifest_current;
         For_test.Drop_static_sources_current;
         For_test.Substitute_digest_string ]);
  check "JA8 every mutant changes or removes the canonical source digest"
    (match first_digest with
     | Error _ -> false
     | Ok canonical ->
         List.for_all
           (fun mutation ->
             match For_test.source_digest_with_mutation mutation with
             | Error _ -> true
             | Ok changed -> canonical <> changed)
           (List.map
              (fun kind -> For_test.Drop_constituent kind)
              constituent_kinds
            @ [ For_test.Reorder_constituents;
                For_test.Duplicate_constituent;
                For_test.Mismatch_constituent_digest;
                For_test.Add_bridge_dependency;
                For_test.Add_operator_dependency;
                For_test.Add_concrete_target_dependency;
                For_test.Add_aggregate_ops_dependency;
                For_test.Forge_current_receipt;
                For_test.Drop_runtime_manifest_current;
                For_test.Drop_static_sources_current;
                For_test.Substitute_digest_string ]));
  let expected_current_prerequisites =
    List.map (fun id -> "static-current:" ^ id) expected_constituents
    @ [ "observed-runtime-manifest-current" ]
  in
  check "JA9 current receipt has the exact static plus observed denominator"
    (List.map current_prerequisite_id current_prerequisites
       = expected_current_prerequisites
     && List.length current_prerequisites = 23);
  check "JA10 no absent lower current receipt is promoted"
    (production_posture = `Implemented_unavailable
     && List.for_all
          (fun prerequisite ->
            Result.is_error (current_prerequisite_status prerequisite))
          current_prerequisites);
  check "JA11 authority boundary laws are exact and ordered"
    (boundary_laws
     = [ "bridge-neutral"; "operator-neutral"; "target-declaration-only";
         "no-aggregate-ops"; "no-current-forgery";
         "no-digest-string-substitution" ]);
  Printf.printf "run_jj_authority: %d passed, %d failed\n" !passed !failed;
  let telemetry =
    Suite_telemetry.observe ~suite:"test_run_jj_authority"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit telemetry ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code telemetry)
